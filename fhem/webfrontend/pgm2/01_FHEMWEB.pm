##############################################
package main;

use strict;
use warnings;

use IO::Socket;


###################
# Config
my $__ME;
my $FHEMWEBdir;
my $FHEMWEB_tmpfile    = "/tmp/file.$$";
my $FHEMWEB_reldoc;

use vars qw(%defs);
use vars qw(%attr);

# Nothing to config below
#########################

#########################
# Forward declaration
sub FHEMWEB_checkDirs();
sub FHEMWEB_digestCgi($);
sub FHEMWEB_doDetail($);
sub FHEMWEB_fileList($);
sub FHEMWEB_makeTable($$$$$$$$);
sub FHEMWEB_parseXmlList();
sub FHEMWEB_showRoom();
sub FHEMWEB_showArchive($);
sub FHEMWEB_showLog($);
sub FHEMWEB_showLogWrapper($);
sub FHEMWEB_popup($$$);
sub FHEMWEB_textfield($$);
sub FHEMWEB_submit($$);
sub FHEMWEB_roomOverview();
sub FHEMWEB_fatal($);
sub pF($@);
sub pO(@);
sub FHEMWEB_AnswerCall($);
sub FHEMWEB_zoomLink($$$$);
sub FHEMWEB_calcWeblink($$);

#########################
# As we are _not_ multithreaded, it is safe to use global variables.
my %__icons;
my $__iconsread;
my %__rooms;
my %__devs;
my %__types;
my $__room;
my $__detail;
my $__title;
my $__cmdret;
my $__scrolledweblinkcount;
my %__wlpos;
my $__RET;
my $__RETTYPE;
my $__SF;
my $__ti;  # Tabindex for all input fields
my @__zoom;
my %__zoom;
my $__plotmode;


#####################################
sub
FHEMWEB_Initialize($)
{
  my ($hash) = @_;

  $hash->{ReadFn}  = "FHEMWEB_Read";

  $hash->{DefFn}   = "FHEMWEB_Define";
  $hash->{UndefFn} = "FHEMWEB_Undef";
  $hash->{AttrList}= "loglevel:0,1,2,3,4,5,6 webdir webname plotmode:gnuplot,gnuplot-scroll,SVG";
}

#####################################
sub
FHEMWEB_Define($$)
{
  my ($hash, $def) = @_;
  my ($name, $type, $port, $global) = split("[ \t]+", $def);
  return "Usage: define <name> FHEMWEB <tcp-portnr> [global]"
        if($port !~ m/^[0-9]+$/ || $port < 1 || $port > 65535 ||
           ($global && $global ne "global"));

  $hash->{STATE} = "Initialized";
  $hash->{PORT} = IO::Socket::INET->new(
          Proto        => 'tcp',
          LocalHost    => (($global && $global eq "global") ? undef : "localhost"),
          LocalPort    => $port,
          Listen       => 10,
          ReuseAddr    => 1);

  return "Can't open server port at $port: $!" if(!$hash->{PORT});

  $hash->{FD} = $hash->{PORT}->fileno();
  $hash->{SERVERSOCKET} = "True";
  Log(2, "FHEMWEB port $port opened");

  ###############
  # Initialize internal structures
  my $n = 0;
  @__zoom = ("day","week","month","year");
  %__zoom = map { $_, $n++ } @__zoom;

  return undef;
}

#####################################
sub
FHEMWEB_Undef($$)
{
  my ($hash, $arg) = @_;
  close($hash->{PORT});
  return undef;
}

#####################################
sub
FHEMWEB_Read($)
{
  my ($hash) = @_;

  if($hash->{SERVERSOCKET}) {   # Accept and create a child

    my @clientinfo = $hash->{PORT}->accept();
    my $name = $hash->{NAME};
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
    Log($ll, "Connection accepted from $nhash{NAME}");
    return;

  }

  my $name = $hash->{SNAME};
  my $ll = GetLogLevel($name,4);
  $FHEMWEBdir = ($attr{$name} && $attr{$name}{webdir}) ? 
                        $attr{$name}{webdir} : "$attr{global}{modpath}/FHEM";
  $__ME = "/" . (($attr{$name} && $attr{$name}{webname}) ? 
                                $attr{$name}{webname} : "fhem");
  $FHEMWEB_reldoc = "$__ME/commandref.html";
  $__SF = "<form method=\"get\" action=\"$__ME\">";

  # Data from HTTP Client
  my $buf;
  my $ret = sysread($hash->{CD}, $buf, 1024);

  if(!defined($ret) || $ret <= 0) {
    close($hash->{CD});
    delete($defs{$hash->{NAME}});
    # Don't delete the attr entry.
    Log($ll, "Connection closed for $hash->{NAME}");
    return;
  }

  $hash->{BUF} .= $buf;
  #Log(1, "Got: >$hash->{BUF}<");
  return if($hash->{BUF} !~ m/\n\n$/ && $hash->{BUF} !~ m/\r\n\r\n$/);

  my @lines = split("[\r\n]", $hash->{BUF});
  my ($mode, $arg, $method) = split(" ", $lines[0]);
  $hash->{BUF} = "";

  Log($ll, "HTTP $hash->{NAME} GET $arg");
  $__plotmode = $attr{$name}{plotmode} ? $attr{$name}{plotmode} : "gnuplot";

  FHEMWEB_AnswerCall($arg);

  my $c = $hash->{CD};
  my $l = length($__RET);
#  my $exp = localtime(time()+300) . " GMT";
#            "Expires: $exp\r\n",
  print  $c "HTTP/1.1 200 OK\r\n",
            "Content-Length: $l\r\n",
            "Content-Type: $__RETTYPE\r\n\r\n",
            $__RET;
}


sub
FHEMWEB_AnswerCall($)
{
  my ($arg) = @_;

  %__rooms = ();
  %__devs = ();
  %__wlpos = ();
  %__types = ();
  $__room = "";
  $__detail = "";
  $__title = "";
  $__cmdret = "";
  $__RET = "";
  $__RETTYPE = "text/html; charset=ISO-8859-1";
  $__ti = 1;

  # Lets go:
  if($arg =~ m/^$FHEMWEB_reldoc/) {
    open(FH, "$FHEMWEBdir/commandref.html") || return;
    pO join("", <FH>);
    close(FH);
    return;
  } elsif($arg =~ m,^$__ME/style.css,) {
    open(FH, "$FHEMWEBdir/style.css") || return;
    pO join("", <FH>);
    close(FH);
    $__RETTYPE = "text/css";
    return;
  } elsif($arg =~ m,^$__ME/icons/(.*)$,) {
    open(FH, "$FHEMWEBdir/$1") || return;
    pO join("", <FH>);
    close(FH);
    $__RETTYPE = "image/gif";
    return;
  } elsif($arg !~ m/^$__ME(.*)/) {
    Log(5, "Unknown document $arg requested");
    return;
  }

  my $cmd = FHEMWEB_digestCgi($1);

  $__cmdret = fC($cmd) if($cmd && 
                          $cmd !~ /^showlog/ &&
                          $cmd !~ /^toweblink/ &&
                          $cmd !~ /^showarchive/ &&
                          $cmd !~ /^edit/);
  FHEMWEB_parseXmlList();
  return FHEMWEB_showLog($cmd) if($cmd =~ m/^showlog /);

  if($cmd =~ m/^toweblink (.*)$/) {
    my @aa = split(":", $1);
    my $max = 0;
    for my $d (keys %__devs) {
      $max = ($1+1) if($d =~ m/^wl_(\d+)$/ && $1 >= $max);
    }
    $__devs{$aa[0]}{INT}{currentlogfile}{VAL} =~ m,([^/]*)$,;
    $aa[2] = "CURRENT" if($1 eq $aa[2]);
    $__cmdret = fC("define wl_$max weblink fileplot $aa[0]:$aa[1]:$aa[2]");
    if(!$__cmdret) {
      $__detail = "wl_$max";
      FHEMWEB_parseXmlList()
    }
  }

  pO "<html><head><title>$__title</title>";
  pO "<link href=\"$__ME/style.css\" rel=\"stylesheet\"/>";
  pO "</head><body name=\"$__title\">\n";

  if($__cmdret) {
    $__detail = "";
    $__room = "";
    $__cmdret =~ s/</&lt;/g;
    $__cmdret =~ s/>/&gt;/g;
    pO "<div id=\"right\">\n";
    pO "<pre>$__cmdret</pre>\n";
    pO "</div>\n";
  }

  FHEMWEB_roomOverview();
  FHEMWEB_doDetail($__detail)  if($__detail);
  FHEMWEB_showRoom()           if($__room && !$__detail);
  FHEMWEB_showLogWrapper($cmd) if($cmd =~ /^showlogwrapper/);
  FHEMWEB_showArchive($cmd)    if($cmd =~ m/^showarchive/);
  pO "</body></html>";
}


###########################
# Digest CGI parameters
sub
FHEMWEB_digestCgi($)
{
  my ($arg) = @_;
  my (%arg, %val, %dev);
  my ($cmd, $c) = ("","","");

  $arg =~ s/^\?//;
  foreach my $pv (split("&", $arg)) {
    $pv =~ s/\+/ /g;
    $pv =~ s/%(..)/chr(hex($1))/ge;
    my ($p,$v) = split("=",$pv, 2);
    $v =~ s/[\r]\n/\\\n/g;              # Multiline: escape the NL for fhem
    #Log(0, "P: $p, V: $v");

    if($p eq "detail")       { $__detail = $v; }
    if($p eq "room")         { $__room = $v; }
    if($p eq "cmd")          { $cmd = $v; }
    if($p =~ m/^arg\.(.*)$/) { $arg{$1} = $v; }
    if($p =~ m/^val\.(.*)$/) { $val{$1} = $v; }
    if($p =~ m/^dev\.(.*)$/) { $dev{$1} = $v; }
    if($p =~ m/^cmd\.(.*)$/) { $cmd = $v; $c= $1; }
    if($p eq "wlpos")        { %__wlpos =  split(/[=;]/, $v); }


  }
  $cmd.=" $dev{$c}" if($dev{$c});
  $cmd.=" $arg{$c}" if($arg{$c});
  $cmd.=" $val{$c}" if($val{$c});
  return $cmd;
}

#####################
# Get the data and parse it. We are parsing XML in a non-scientific way :-)
sub
FHEMWEB_parseXmlList()
{
  my $name;
  foreach my $l (split("\n", fC("xmllist"))) {

    ####### Device
    if($l =~ m/^\t\t<(.*) name="(.*)" state="(.*)" sets="(.*)" attrs="(.*)">/){
      $name = $2;
      $__devs{$name}{type}  = ($1 eq "HMS" ? "KS300" : $1);
      $__devs{$name}{state} = $3;
      $__devs{$name}{sets}  = $4;
      $__devs{$name}{attrs} = $5;
      next;
    }
    ####### INT, ATTR & STATE
    if($l =~ m,^\t\t\t<(.*) key="(.*)" value="([^"]*)"(.*)/>,) {
      my ($t, $n, $v, $m) = ($1, $2, $3, $4);
      $v =~ s/&lt;br&gt;/<br>/g;
      $__devs{$name}{$t}{$n}{VAL} = $v;
      if($m) {
        $m =~ m/measured="(.*)"/;
        $__devs{$name}{$t}{$n}{TIM} = $1;
      }

      if($t eq "ATTR" && $n eq "room") {
        $__rooms{$v}{$name} = 1;
	if($name eq "global") {
	  $__rooms{$v}{LogFile} = 1;
	  $__devs{LogFile}{ATTR}{room}{VAL} = $v;
	}
      }

      if($name eq "global" && $n eq "logfile") {
	my $ln = "LogFile";
	$__devs{$ln}{type}  = "FileLog";
        $__devs{$ln}{INT}{logfile}{VAL} = $v;
        $__devs{$ln}{state} = "active";
      }
    }

  }
  if(defined($__devs{global}{ATTR}{archivedir})) {
    $__devs{LogFile}{ATTR}{archivedir}{VAL} = 
     $__devs{global}{ATTR}{archivedir}{VAL};
  }

  #################
  #Tag the gadgets without room with "Unsorted"
  if(%__rooms) {
    foreach my $name (keys %__devs ) {
      if(!$__devs{$name}{ATTR}{room}) {
        $__devs{$name}{ATTR}{room}{VAL} = "Unsorted";
        $__rooms{Unsorted}{$name} = 1;
      }
    }
  }

  ###############
  # Needed for type sorting
  foreach my $d (sort keys %__devs ) {
    $__types{$__devs{$d}{type}} = 1;
  }
  $__title = $__devs{global}{ATTR}{title}{VAL} ? 
               $__devs{global}{ATTR}{title}{VAL} : "First page";
  $__room = $__devs{$__detail}{ATTR}{room}{VAL} if($__detail);
}

##############################
sub
FHEMWEB_makeTable($$$$$$$$)
{
  my($d,$t,$header,$hash,$clist,$ccmd,$makelink,$cmd) = (@_);

  return if(!$hash && !$clist);

  $t = "EM" if($t =~ m/^EM.*$/);        # EMWZ,EMEM,etc.
  pO "  <table class=\"$t\">\n";

  # Header
  pO "  <tr>";
  foreach my $h (split(",", $header)) {
    pO "<th>$h</th>";
  }
  pO "</tr>\n";
  if($clist) {
    my @al = map { s/[:;].*//;$_ } split(" ", $clist);
    pO "<td>" . FHEMWEB_popup("arg.$ccmd$d",\@al,undef) . "</td>";
    pO "<td>" . FHEMWEB_textfield("val.$ccmd$d", 6)    . "</td>";
    pO "<td>" . FHEMWEB_submit("cmd.$ccmd$d", $ccmd)    . "</td>";
    pO FHEMWEB_hidden("dev.$ccmd$d", $d);
    pO "</td></tr><tr><td>\n";
  }

  my $row = 1;
  foreach my $v (sort keys %{$hash}) {
    pF "    <tr class=\"%s\">", $row?"odd":"even";
    $row = ($row+1)%2;
    if($makelink && $FHEMWEB_reldoc) {
      pO "<td><a href=\"$FHEMWEB_reldoc#$v\">$v</a></td>";
    } else {
      pO "<td>$v</td>";
    }

    if($v eq "DEF") {
      FHEMWEB_makeEdit($d, $t, "modify", $hash->{$v}{VAL});
    } else {
      pO "<td id=\"show\">$hash->{$v}{VAL}</td>";
    }

    pO "<td>$hash->{$v}{TIM}</td>" if($hash->{$v}{TIM});
    pO "<td><a href=\"$__ME?cmd.$d=$cmd $d $v&detail=$d\">$cmd</a></td>"
        if($cmd);

    pO "</tr>\n";
  }
  pO "  </table>\n";
  pO "<br>\n";
  
}

##############################
sub
FHEMWEB_showArchive($)
{
  my ($arg) = @_;
  my (undef, $d) = split(" ", $arg);

  my $fn = $__devs{$d}{INT}{logfile}{VAL};
  if($fn =~ m,^(.+)/([^/]+)$,) {
    $fn = $2;
  }
  $fn = $__devs{$d}{ATTR}{archivedir}{VAL} . "/" . $fn;
  my $t = $__devs{$d}{type};

  pO "<div id=\"right\">\n";
  pO "<table><tr><td>\n";
  pO "<table class=\"$t\"><tr><td>\n";

  my $row =  0;
  my $l = $__devs{$d}{ATTR}{logtype};
  foreach my $f (FHEMWEB_fileList($fn)) {
    pF "    <tr class=\"%s\"><td>$f</td>", $row?"odd":"even";
    $row = ($row+1)%2;
    if(!defined($l)) {
      pO "<td><a href=\"$__ME?cmd=showlogwrapper $d text $f\">text</a></td>";
    } else {
      foreach my $ln (split(",", $l->{VAL})) {
	my ($lt, $name) = split(":", $ln);
	$name = $lt if(!$name);
	pO "<td><a href=\"$__ME?cmd=showlogwrapper $d $lt $f\">$name</a></td>";
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
FHEMWEB_doDetail($)
{
  my ($d) = @_;

  pO $__SF;
  pO FHEMWEB_hidden("detail", $d);

  $__room = $__devs{$d}{ATTR}{room}{VAL}
                if($__devs{$d}{ATTR}{room});

  my $t = $__devs{$d}{type};

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
  FHEMWEB_makeTable($d, $t,
        "<a href=\"$FHEMWEB_reldoc#${t}set\">State</a>,Value,Measured",
        $__devs{$d}{STATE}, $__devs{$d}{sets}, "set", 0, undef);
  FHEMWEB_makeTable($d, $t, "Internal,Value",
        $__devs{$d}{INT}, "", undef, 0, undef);
  FHEMWEB_makeTable($d, $t,
        "<a href=\"$FHEMWEB_reldoc#attr\">Attribute</a>,Value,Action",
        $__devs{$d}{ATTR}, $__devs{$d}{attrs}, "attr", 1,
        $d eq "global" ? "" : "deleteattr");
  pO "</td></tr></table>\n";
  pO "</div>\n";

  pO "</form>\n";
}

##############
# Room overview
sub
FHEMWEB_roomOverview()
{
  pO $__SF;

  pO "<div id=\"hdr\">\n";
  pO "<table><tr><td>";
  pO "<a href=\"$FHEMWEB_reldoc\">Cmd</a>: ";
  pO FHEMWEB_textfield("cmd", 30);
  $__scrolledweblinkcount = 0;
  if($__room) {
    pO FHEMWEB_hidden("room", "$__room");
    if(!$__detail) {    # Global navigation buttons for weblink >= 2
      FHEMWEB_calcWeblink(undef,undef);
      if($__scrolledweblinkcount) {
        pO "</td><td>";
        pO "&nbsp;&nbsp;";
        FHEMWEB_zoomLink("zoom=-1", "Zoom-in.png", "zoom in", 0);
        FHEMWEB_zoomLink("zoom=1",  "Zoom-out.png","zoom out", 0);
        FHEMWEB_zoomLink("all=-1",  "Prev.png",    "prev", 0);
        FHEMWEB_zoomLink("all=1",   "Next.png",    "next", 0);
      }
    }
  }
  pO "</td></tr></table>";
  pO "</div>\n";

  pO "<div id=\"left\">\n";
  pO "  <table><tr><td>\n";  # Need for "right" compatibility
    pO "  <table class=\"room\" summary=\"Room list\">\n";
  $__room = "" if(!$__room);
  foreach my $r (sort keys %__rooms) {
    next if($r eq "hidden");
    pF "    <tr%s>", $r eq $__room ? " class=\"sel\"" : "";
    pO "<td><a href=\"$__ME?room=$r\">$r</a>";
    pO "</td></tr>\n";
  }

  pF "    <tr%s>",  "all" eq $__room ? " class=\"sel\"" : "";
  pO "<td><a href=\"$__ME?room=all\">All together</a></td>";
  pO "    </tr>\n";

  pO "  </table>\n";
  pO "  </table>\n";
  pO "</div>\n";
  pO "</form>\n";
}

#################
# Read in the icons
  sub
FHEMWEB_checkDirs()
{
  return if($__iconsread && (time() - $__iconsread) < 5);
  %__icons = ();
  if(opendir(DH, $FHEMWEBdir)) {
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

########################
# Generate the html output: i.e present the data
sub
FHEMWEB_showRoom()
{
  FHEMWEB_checkDirs();

  pO $__SF;
  pO "<div id=\"right\">\n";
  pO "  <table><tr><td>\n";  # Need for equal width of subtables

  foreach my $type (sort keys %__types) {
    
    #################
    # Filter the devices in the room
    if($__room && $__room ne "all") {
      my $havedev;
      foreach my $d (sort keys %__devs ) {
        next if($__devs{$d}{type} ne $type);
        next if(!$__rooms{$__room}{$d});
        $havedev = 1;
        last;
      }
      next if(!$havedev);
    }

    my $rf = ($__room ? "&room=$__room" : "");


    ############################
    # Print the table headers
    my $t = $type;
    $t = "EM" if($t =~ m/^EM.*$/);
    pO "  <table class=\"$t\" summary=\"List of $type devices\">\n";

    if($type eq "FS20") {
      pO "    <tr><th>FS20 dev.</th><th>State</th>";
      pO "<th colspan=\"2\">Set to</th>";
      pO "</tr>\n";
    }
    if($type eq "FHT") {
      pO "    <tr><th>FHT dev.</th><th>Measured</th>";
      pO "<th>Set to</th>";
      pO "</tr>\n";
    }

    my $hstart = "    <tr><th>";
    my $hend   = "</th></tr>\n";
    pO $hstart . "Logs" . $hend                       if($type eq "FileLog");
    pO $hstart . "HMS/KS300</th><th>Readings" . $hend if($type eq "KS300");
    pO $hstart . "Scheduled commands (at)" . $hend    if($type eq "at");
    pO $hstart . "Triggers (notify)" . $hend          if($type eq "notify");
    pO $hstart . "Global variables" . $hend        if($type eq "_internal_");

    my $row=1;
    foreach my $d (sort keys %__devs ) {

      next if($__devs{$d}{type} ne $type);
      next if($__room && $__room ne "all" &&
             !$__rooms{$__room}{$d});

      pF "    <tr class=\"%s\">", $row?"odd":"even";
      $row = ($row+1)%2;

      #####################
      # Check if the icon exists

      my $v = $__devs{$d}{state};

      if($type eq "FS20") {

        my $v = $__devs{$d}{state};
        my $iv = $v;
        my $iname = "";

        if(defined($__devs{$d}) &&
           defined($__devs{$d}{ATTR}{showtime})) {
          $v = $__devs{$d}{STATE}{state}{TIM};
        } elsif($iv) {
          $iv =~ s/ .*//; # Want to be able to have icons for "on-for-timer xxx"
          $iname = $__icons{"$type"}     if($__icons{"$type"});
          $iname = $__icons{"$type.$iv"} if($__icons{"$type.$iv"});
          $iname = $__icons{"$d"}        if($__icons{"$d"});
          $iname = $__icons{"$d.$iv"}    if($__icons{"$d.$iv"});
        }

        pO "<td><a href=\"$__ME?detail=$d\">$d</a></td>";
        if($iname) {
          pO "<td align=\"center\"><img src=\"$__ME/icons/$iname\" ".
                  "alt=\"$v\"/></td>";
        } else {
          pO "<td align=\"center\">$v</td>";
        }
        if($__devs{$d}{sets}) {
          pO "<td><a href=\"$__ME?cmd.$d=set $d on$rf\">on</a></td>";
          pO "<td><a href=\"$__ME?cmd.$d=set $d off$rf\">off</a></td>";
        }

      } elsif($type eq "FHT") {

        $v = $__devs{$d}{STATE}{"measured-temp"}{VAL};

        $v =~ s/ .*//;
        pO "<td><a href=\"$__ME?detail=$d\">$d</a></td>";
        pO "<td align=\"center\">$v&deg;</td>";

        $v = sprintf("%2.1f", int(2*$v)/2) if($v =~ m/[0-9.-]/);
        my @tv = map { ($_.".0", $_+0.5) } (16..26);
        $v = int($v*20)/$v if($v =~ m/^[0-9].$/);
        pO FHEMWEB_hidden("arg.$d", "desired-temp");
        pO FHEMWEB_hidden("dev.$d", $d);
        pO "<td>" .
            FHEMWEB_popup("val.$d",\@tv,$v) .
            FHEMWEB_submit("cmd.$d", "set") . "</td>";

      } elsif($type eq "FileLog") {
        pO "<td><a href=\"$__ME?detail=$d\">$d</a></td><td>$v</td>\n";
        if($__devs{$d}{ATTR}{archivedir}) {
          pO "<td><a href=\"$__ME?cmd=showarchive $d\">archive</a></td>";
        }

        my $l = $__devs{$d}{ATTR}{logtype};
        if(!defined($l)) {
	  my %h = ("VAL" => "text");
	  $l = \%h;
	}

	foreach my $f (FHEMWEB_fileList($__devs{$d}{INT}{logfile}{VAL})) {
	  pF "    <tr class=\"%s\"><td>$f</td>", $row?"odd":"even";
	  $row = ($row+1)%2;
	  foreach my $ln (split(",", $l->{VAL})) {
	    my ($lt, $name) = split(":", $ln);
	    $name = $lt if(!$name);
	    pO "<td><a href=\"$__ME?cmd=showlogwrapper $d $lt $f\">$name</a></td>";
	  }
	  pO "</tr>";
	}

      } elsif($type eq "weblink") {

        $v = $__devs{$d}{INT}{LINK}{VAL};
        $t = $__devs{$d}{INT}{WLTYPE}{VAL};
        if($t eq "link") {
          pO "<td><a href=\"$v\">$d</a></td>\n";
        } elsif($t eq "fileplot") {
          my @va = split(":", $v, 3);
          if(@va != 3 || !$__devs{$va[0]}{INT}{currentlogfile}) {
	    pO "<td>Broken definition: $v</a></td>";
          } else {
            if($va[2] eq "CURRENT") {
              $__devs{$va[0]}{INT}{currentlogfile}{VAL} =~ m,([^/]*)$,;
              $va[2] = $1;
            }
            pO "<table><tr><td>";

            my $wl = "";
            $__wlpos{$va[0]} = $__wlpos{$d} if($__wlpos{$d});
            $wl = "&wlpos=" . join(";", map { "$_=$__wlpos{$_}" }
                                  grep { /(zoom|all|$va[0])/ } keys %__wlpos);
            
            pO "<img src=\"$__ME?cmd=showlog $d $va[0] $va[1] $va[2]$wl\"/>";
            pO "</td><td>";
            
            FHEMWEB_zoomLink("$d=-1", "Prev.png", "prev", 1);
            FHEMWEB_zoomLink("$d=1",  "Next.png", "next", 1);
            pO "<a href=\"$__ME?detail=$d\">$d</a></td>";
            pO "</td></tr></table>";

          }
        }

      } else {
        pO "<td><a href=\"$__ME?detail=$d\">$d</a></td><td>$v</td>\n";
      }
      pO "  </tr>\n";
    }
    pO "  </table>\n";
    pO "  <br>\n"; # Empty line
  }
  pO "  </td></tr>\n</table>\n";
  pO "</div>\n";
  pO "</form>\n";
}

#################
sub
FHEMWEB_fileList($)
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
FHEMWEB_showLogWrapper($)
{
  my ($cmd) = @_;
  my (undef, $d, $type, $file) = split(" ", $cmd, 4);

  if($type eq "text") {
    $__devs{$d}{INT}{logfile}{VAL} =~ m,^(.*)/([^/]*)$,; # Dir and File
    my $path = "$1/$file";
    $path = $__devs{$d}{ATTR}{archivedir}{VAL} . "/$file" if(!-f $path);

    open(FH, $path) || return FHEMWEB_fatal("$path: $!"); 
    my $cnt = join("", <FH>);
    close(FH);
    $cnt =~ s/</&lt;/g;
    $cnt =~ s/>/&gt;/g;

    pO "<div id=\"right\">\n";
    pO "<pre>$cnt</pre>\n";
    pO "</div>\n";

  } else {

    pO "<div id=\"right\">\n";
    pO "<table><tr></td>\n";
    pO "<table><tr></td>\n";
    pO "<td><img src=\"$__ME?cmd=showlog undef $d $type $file\"/>";
    pO "<a href=\"$__ME?cmd=toweblink $d:$type:$file\"><br>Convert to weblink</a></td>";
    pO "</td></tr></table>\n";
    pO "</td></tr></table>\n";
    pO "</div>\n";
  }
}

######################
sub
FHEMWEB_showLog($)
{
  my ($cmd) = @_;
  my (undef, $wl, $d, $type, $file) = split(" ", $cmd, 5);

  my $gplot_pgm = "$FHEMWEBdir/$type.gplot";
  return FHEMWEB_fatal("Cannot read $gplot_pgm") if(!-r $gplot_pgm);

  FHEMWEB_calcWeblink($d,$wl);
  if($__plotmode eq "gnuplot" || !$__devs{$d}{from}) {

    # Looking for the logfile....

    $__devs{$d}{INT}{logfile}{VAL} =~ m,^(.*)/([^/]*)$,; # Dir and File
    my $path = "$1/$file";
    $path = $__devs{$d}{ATTR}{archivedir}{VAL} . "/$file" if(!-f $path);
    return FHEMWEB_fatal("Cannot read $path") if(!-r $path);

    open(FH, $gplot_pgm) || FHEMWEB_fatal("$gplot_pgm: $!"); 
    my $gplot_script = join("", <FH>);
    close(FH);
    $gplot_script =~ s/<OUT>/$FHEMWEB_tmpfile/g;
    $gplot_script =~ s/<IN>/$path/g;
    $gplot_script =~ s/<TL>/$file/g;

    if($__devs{$wl} && $__devs{$wl}{ATTR}{fixedrange}) {
      my $fr = $__devs{$wl}{ATTR}{fixedrange}{VAL};
      $fr =~ s/ /\":\"/;
      $fr = "set xrange [\"$fr\"]\n";
      $gplot_script =~ s/(set timefmt ".*")/$1\n$fr/;
    }

    open(FH, "|gnuplot > /dev/null");# feed it to gnuplot
    print FH $gplot_script;
    close(FH);

  } else { # gnuplot-scroll

    ############################
    # Read in the template gnuplot file.  Digest the #FileLog lines.  Replace
    # the plot directive with our own, as we offer a file for each line
    my (@filelog, @data, $plot);
    open(FH, $gplot_pgm) || FHEMWEB_fatal("$gplot_pgm: $!"); 
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
    $gplot_script =~ s/<OUT>/$FHEMWEB_tmpfile/g;
    $gplot_script =~ s/<TL>/$file/g;

    my ($f,$t)=($__devs{$d}{from}, $__devs{$d}{to});

    my @path = split(" ", fC("get $d $file $FHEMWEB_tmpfile $f $t " .
                                join(" ", @filelog)));
    my $i = 0;
    $plot =~ s/\".*?using 1:[^ ]+ /"\"$path[$i++]\" using 1:2 "/gse;
    my $xrange = "set xrange [\"$f\":\"$t\"]\n";
    foreach my $p (@path) {
      next if(!-z $p);
      open(FH, ">$p");
      print FH "$f 0\n";
      close(FH);
    }

    open(FH, "|gnuplot > /dev/null");# feed it to gnuplot
    print FH $gplot_script, $xrange, $plot;
    close(FH);
    foreach my $p (@path) {
      unlink($p);
    }
  }


  $__RETTYPE = "image/png";
  open(FH, "$FHEMWEB_tmpfile.png");         # read in the result and send it
  pO join("", <FH>);
  close(FH);
  unlink("$FHEMWEB_tmpfile.png");
}

##################
sub
FHEMWEB_fatal($)
{
  my ($msg) = @_;
  pO "<html><body>$msg</body></html>";
}

##################
sub
FHEMWEB_hidden($$)
{
  my ($n, $v) = @_;
  return "<input type=\"hidden\" name=\"$n\" value=\"$v\"/>";
}

##################
sub
FHEMWEB_popup($$$)
{
  my ($n, $va, $def) = @_;
  my $s = "<select name=\"$n\" tabindex=\"$__ti\">";
  $__ti++;

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
FHEMWEB_textfield($$)
{
  my ($n, $z) = @_;
  my $s = "<input type=\"text\" name=\"$n\" tabindex=\"$__ti\" size=\"$z\"/>";
  $__ti++;
  return $s;
}

sub
FHEMWEB_makeEdit($$$$)
{
  my ($name, $type, $cmd, $val) = @_;

  pO "<td>";
  pO   "<div id=\"edit\" style=\"display:none\"><form>";
  my $eval = $val;
  $eval =~ s/<br>/\n/g;
  if($type eq "at" || $type eq "notify") {
    pO     "<textarea name=\"val.${cmd}$name\" cols=\"60\" rows=\"10\" ".
            "tabindex=\"$__ti\">$eval</textarea>";
  } else {
    pO     "<input type=\"text\" name=\"val.${cmd}$name\" size=\"40\" ".
            "tabindex=\"$__ti\" value=\"$eval\"/>";
  }
  $__ti++;
  pO     "<br>" . FHEMWEB_submit("cmd.${cmd}$name", "$cmd $name");
  pO   "</form></div>";
  $eval = "<pre>$eval</pre>" if($eval =~ m/\n/);
  pO   "<div id=\"disp\">$eval</div>";
  pO  "</td>";
}

##################
sub
FHEMWEB_submit($$)
{
  my ($n, $v) = @_;
  my $s ="<input type=\"submit\" tabindex=\"$__ti\" name=\"$n\" value=\"$v\"/>";
  $__ti++;
  return $s;
}

##################
sub
FHEMWEB_zoomLink($$$$)
{
  my ($cmd, $img, $alt, $br) = @_;

  my ($d,$off) = split("=", $cmd, 2);

  return if($__plotmode eq "gnuplot");
  return if($__devs{$d} && $__devs{$d}{ATTR}{fixedrange});
  return if($__devs{$d} && $__devs{$d}{ATTR}{noscroll});

  my $val = $__wlpos{$d};

  $cmd = "room=$__room&wlpos=";
  if($d eq "zoom") {

    $val = "day" if(!$val);
    $val = $__zoom{$val};
    return if(!defined($val) || $val+$off < 0 || $val+$off >= int(@__zoom) );
    $val = $__zoom[$val+$off];
    return if(!$val);
    $cmd .= "zoom=$val";

  } else {

    return if((!$val && $off > 0) || ($val && $val+$off > 0)); # no future
    $__wlpos{$d}=($val ? $val+$off : $off);
    $cmd .= join(";", map { "$_=$__wlpos{$_}" } sort keys %__wlpos);

    if(!defined($val)) {
      delete $__wlpos{$d};
    } else {
      $__wlpos{$d} = $val;
    }
  }

  pO "<a href=\"$__ME?$cmd\">";
  pO "<img style=\"border-color:transparent\" alt=\"$alt\" ".
                "src=\"$__ME/icons/$img\"/></a>";
  pO "<br>" if($br);
}

##################
# Calculate either the number of scrollable weblinks (for $d = undef) or
# for the device the valid from and to dates for the given zoom and offset
sub
FHEMWEB_calcWeblink($$)
{
  my ($d,$wl) = @_;

  return if($__plotmode eq "gnuplot");
  my $now = time();

  my $zoom = $__wlpos{zoom};
  $zoom = "day" if(!$zoom);

  if(!$d) {
    foreach my $d (sort keys %__devs ) {
      next if($__devs{$d}{type} ne "weblink");
      next if(!$__room || ($__room ne "all" && !$__rooms{$__room}{$d}));
      next if($__devs{$d}{ATTR} && $__devs{$d}{ATTR}{noscroll});
      next if($__devs{$d}{ATTR} && $__devs{$d}{ATTR}{fixedrange});
      $__scrolledweblinkcount++;
    }
    return;
  }

  return if(!$__devs{$wl});
  return if($__devs{$wl} && $__devs{$wl}{ATTR}{noscroll});

  if($__devs{$wl} && $__devs{$wl}{ATTR}{fixedrange}) {
    my @range = split(" ", $__devs{$wl}{ATTR}{fixedrange}{VAL});
    $__devs{$d}{from} = $range[0];
    $__devs{$d}{to}   = $range[1];
    return;
  }

  my $off = $__wlpos{$d};
  $off = 0 if(!$off);
  $off += $__wlpos{all} if($__wlpos{all});

  if($zoom eq "day") {

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
sub
pF($@)
{
  my $fmt = shift;
  $__RET .= sprintf $fmt, @_;
}

##################
sub
pO(@)
{
  $__RET .= shift;
}

##################
sub
fC($)
{
  my ($cmd) = @_;
  my $oll = $attr{global}{verbose};
  $attr{global}{verbose} = 0;
  my $ret = AnalyzeCommand(undef, $cmd);
  if($cmd !~ m/attr.*global.*verbose/) {
    $attr{global}{verbose} = $oll;
  }
  return $ret;
}


1;
