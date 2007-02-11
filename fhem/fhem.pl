#!/usr/bin/perl

my $version = "=VERS= from =DATE=";

################################################################
#
#  Copyright notice
#
#  (c) 2005 Copyright: Rudolf Koenig (r dot koenig at koeniglich dot de)
#  All rights reserved
#
#  This script free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
#  Thanks for Tosti's site (<http://www.tosti.com/FHZ1000PC.html>)
#  for inspiration.
#
#  Homepage:  http://www.koeniglich.de/fhem/fhem.html


use strict;
use warnings;
use IO::File;
use IO::Socket;
use Net::hostent;
use Time::HiRes qw(gettimeofday);


##################################################
# Forward declarations
#
sub AnalyzeInput($);
sub AnalyzeCommand($$);
sub AnalyzeCommandChain($$);
sub IOWrite($@);
sub AssignIoPort($);
sub InternalTimer($$$);
sub fhz($);
sub CommandChain($$);
sub DoClose($);
sub HandleTimeout();
sub Log($$);
sub OpenLogfile($);
sub ResolveDateWildcards($@);
sub SignalHandling();
sub TimeNow();
sub DoSavefile();
sub SemicolonEscape($);
sub XmlEscape($);

sub CommandAt($$);
sub CommandAttr($$);
sub CommandDefAttr($$);
sub CommandDefine($$);
sub CommandDelete($$);
sub CommandFhzDev($$);
sub CommandGet($$);
sub CommandHelp($$);
sub CommandInclude($$);
sub CommandInform($$);
sub CommandList($$);
sub CommandLogfile($$);
sub CommandModpath($$);
sub CommandNotifyon($$);
sub CommandPidfile($$);
sub CommandPort($$);
sub CommandRereadCfg($$);
sub CommandQuit($$);
sub CommandSavefile($$);
sub CommandSet($$);
sub CommandSetstate($$);
sub CommandSleep($$);
sub CommandShutdown($$);
sub CommandVerbose($$);
sub CommandXmlList($$);
sub CommandTrigger($$);

##################################################
# Variables:
# global, to be able to access them from modules
use vars qw(%defs);		# FHEM device/button definitions
use vars qw(%logs);		# Log channels
use vars qw(%attr);		# Attributes
use vars qw(%value);		# Current values, see commandref.html
use vars qw(%oldvalue);		# Old values, see commandref.html
use vars qw(%devmods);		# List of loaded device modules

my %ntfy;
my %at;

my $server;			# Server socket
my $verbose = 0;
my $logfile;			# logfile name, if its "-" then wont background
my $currlogfile;		# logfile, without wildcards
my $logopened;
my %client;			# Client array
my %logmods;			# List of loaded logger modules
my $savefile = "";		# Save ste info and at cmd's here
my $nextat;
my $rcvdquit;			# Used for quit handling in init files
my $configfile=$ARGV[0];
my $sig_term = 0;		# if set to 1, terminate (saving the state)
my $modpath_set;                # Check if modpath was used, and report if not.
my $global_cl;			# To use from perl snippets
my $devcount = 0;		# To sort the devices
my %defattr;    		# Default attributes
my %intAt;			# Internal at timer hash.
my $intAtCnt=0;
my $init_done = 0;
my $pidfilename;


my %cmds = (
  "?"       => { Fn=>"CommandHelp",
	    Hlp=>",get this help" },
  "at"      => { Fn=>"CommandAt",
	    Hlp=>"<timespec> <command>,issue a command at a given time" },
  "attr"    => { Fn=>"CommandAttr", 
	    Hlp=>"<devname> <attrname> <attrvalue>,set attributes for <devname>" },
  "defattr" => { Fn=>"CommandDefAttr", 
	    Hlp=>"<attrname> <attrvalue>,set attr for following definitions" },
  "define"  => { Fn=>"CommandDefine",
	    Hlp=>"<name> <type> <options>,define a code" },
  "delete"  => { Fn=>"CommandDelete",
	    Hlp=>"{def|ntfy|at} name,delete the corresponding definition"},
  "get"     => { Fn=>"CommandGet", 
	    Hlp=>"<name> <type dependent>,request data from <name>" },
  "help"    => { Fn=>"CommandHelp",
	    Hlp=>",get this help" },
  "include" => { Fn=>"CommandInclude",
	    Hlp=>"<filename>,read the commands from <filenname>" },
  "inform" => { Fn=>"CommandInform",
	    Hlp=>"{on|off},echo all commands and events to this client" },
  "list"    => { Fn=>"CommandList",
	    Hlp=>"[device],list definitions and status info" },
  "logfile" => { Fn=>"CommandLogfile", 
	    Hlp=>"filename,use - for stdout" },
  "modpath" => { Fn=>"CommandModpath",
	    Hlp=>"<path>,the directory where the FHEM subdir is" },
  "notifyon"=> { Fn=>"CommandNotifyon",
	    Hlp=>"<name> <shellcmd>,exec <shellcmd> when recvd signal for <name>" },
  "pidfile" => { Fn=>"CommandPidfile", 
	    Hlp=>"filename,write the process id into the pidfile" },
  "port"    => { Fn=>"CommandPort",
	    Hlp=>"<port> [global],TCP/IP port for the server" },
  "quit"    => { Fn=>"CommandQuit",
	    Hlp=>",end the client session" },
  "reload"  => { Fn=>"CommandReload",
	    Hlp=>"<module-name>,reload the given module (e.g. 99_PRIV)" },
  "rereadcfg"  => { Fn=>"CommandRereadCfg",
	    Hlp=>",reread the config file" },
  "savefile"=> { Fn=>"CommandSavefile", 
	    Hlp=>"<filename>,on shutdown save all states and at entries" },
  "set"     => { Fn=>"CommandSet", 
	    Hlp=>"<name> <type dependent>,transmit code for <name>" },
  "setstate"=> { Fn=>"CommandSetstate", 
	    Hlp=>"<name> <state>,set the state shown in the command list" },
  "shutdown"=> { Fn=>"CommandShutdown",
	    Hlp=>",terminate the server" },
  "sleep"  => { Fn=>"CommandSleep",
            Hlp=>"<usecs>,sleep for usecs" },
  "trigger" => { Fn=>"CommandTrigger",
            Hlp=>"<dev> <state>,trigger notify command" },
  "verbose" => { Fn=>"CommandVerbose",
	    Hlp=>"<level>,verbosity level, 0-5" },
  "xmllist" => { Fn=>"CommandXmlList",
            Hlp=>",list definitions and status info as xml" },
);



###################################################
# Start the program
if(int(@ARGV) != 1 && int(@ARGV) != 2) {
  print "Usage:\n";
  print "as server: fhem configfile\n";
  print "as client: fhem [host:]port cmd\n";
  CommandHelp(undef, undef);
  exit(1);
}

###################################################
# Client code
if(int(@ARGV) == 2) {
  my $buf;
  my $addr = $ARGV[0];
  $addr = "localhost:$addr" if($ARGV[0] !~ m/:/);
  $server = IO::Socket::INET->new(PeerAddr => $addr);
  die "Can't connect to $addr\n" if(!$server);
  syswrite($server, "$ARGV[1] ; quit\n");
  my $err = 0;
  while(sysread($server, $buf, 256) > 0) {
    print($buf);
    $err = 1;
  }
  exit($err);
}

my $ret = CommandInclude(undef, $configfile);
die($ret) if($ret);

if($logfile ne "-") {
  defined(my $pid = fork) || die "Can't fork: $!";
  exit(0) if $pid;
}

die("No modpath specified in the configfile.\n") if(!$modpath_set);

if($savefile && -r $savefile) {
  $ret = CommandInclude(undef, $savefile);
  die($ret) if($ret);
}
SignalHandling();


Log 0, "Server started (version $version, pid $$)";

################################################
# Main loop

$init_done = 1;
CommandPidfile(undef, $pidfilename) if($pidfilename);

while (1) {
  my ($rout, $rin) = ('', '');

  vec($rin, $server->fileno(), 1) = 1;
  foreach my $p (keys %defs) {
    vec($rin, $defs{$p}{FD}, 1) = 1 if($defs{$p}{FD});
  }
  foreach my $c (keys %client) {
    vec($rin, fileno($client{$c}{fd}), 1) = 1;
  }

  my $nfound = select($rout=$rin, undef, undef, HandleTimeout());

  CommandShutdown(undef, undef) if($sig_term);

  if($nfound < 0) {
    next if ($! == EAGAIN() || $! == EINTR() || $! == 0);
    die("Select error $nfound / $!\n");
  }

  ###############################
  # Message from the hardware (FHZ1000/WS3000/etc)
  foreach my $p (keys %defs) {
    next if(!$defs{$p}{FD} || !vec($rout, $defs{$p}{FD}, 1));
    no strict "refs";
    &{$devmods{$defs{$p}{TYPE}}{ReadFn}}($defs{$p});
    use strict "refs";
  }
  
  if(vec($rout, $server->fileno(), 1)) {
    my @clientinfo = $server->accept();
    if(!@clientinfo) {
      Print("ERROR", 1, "016 Accept failed for admin port");
      next;
    }
    my @clientsock = sockaddr_in($clientinfo[1]);
    my $fd = $clientinfo[0];
    $client{$fd}{fd}   = $fd;
    $client{$fd}{addr} = inet_ntoa($clientsock[1]) . ":" . $clientsock[0];
    $client{$fd}{buffer} = "";
    Log 4, "Connection accepted from $client{$fd}{addr}";
  }

  foreach my $c (keys %client) {

    next unless (vec($rout, fileno($client{$c}{fd}), 1));

    my $buf;
    my $ret = sysread($client{$c}{fd}, $buf, 256);
    if(!defined($ret) || $ret <= 0) {
      DoClose($c);
      next;
    }
    if(ord($buf) == 4) {	# EOT / ^D
      CommandQuit($c, "");
      next;
    }
    $buf =~ s/\r//g;
    $client{$c}{buffer} .= $buf;
    AnalyzeInput($c);
  }
}

################################################
sub
IsDummy($)
{
  my $dev = shift;

  return 1 if(defined($attr{$dev}) && defined($attr{$dev}{dummy}));
  return 0;
}

################################################
sub
GetLogLevel($)
{
  my $dev = shift;

  return $attr{$dev}{loglevel}
  	if(defined($attr{$dev}) && defined($attr{$dev}{loglevel}));
  return 2;
}


################################################
sub
Log($$)
{
  my ($loglevel, $text) = @_;

  return if($loglevel > $verbose);

  my @t = localtime;
  my $nfile = ResolveDateWildcards($logfile, @t);
  OpenLogfile($nfile) if($currlogfile && $currlogfile ne $nfile);
  my $tim = sprintf("%04d.%02d.%02d %02d:%02d:%02d",
        $t[5]+1900,$t[4]+1,$t[3], $t[2],$t[1],$t[0]);

#  my ($seconds, $microseconds) = gettimeofday();
#  $tim = sprintf("%04d.%02d.%02d %02d:%02d:%02d.%03d",
#        $t[5]+1900,$t[4]+1,$t[3], $t[2],$t[1],$t[0], $microseconds/1000);

  if($logopened) {
    print LOG "$tim $loglevel: $text\n";
  } else {
    print "$tim $loglevel: $text\n";
  }
  return undef;
}


#####################################
sub
DoClose($)
{
  my $c = shift;

  Log 4, "Connection closed for $client{$c}{addr}";
  close($client{$c}{fd});
  delete($client{$c});
  return undef;
}

#####################################
sub
IOWrite($@)
{
  my ($hash, @a) = @_;

  my $iohash = $hash->{IODev};
  if(!$iohash) {
    Log 5, "No IO device found for $hash->{NAME}";
    return;
  }

  no strict "refs";
  &{$devmods{$iohash->{TYPE}}{WriteFn}}($iohash, @a);
  use strict "refs";
}

#####################################
sub
AnalyzeInput($)
{
  my $c = shift;

  while($client{$c}{buffer} =~ m/\n/) {
    my ($cmd, $rest) = split("\n", $client{$c}{buffer}, 2);
    $client{$c}{buffer} = $rest;
    if($cmd) {
      AnalyzeCommandChain($c, $cmd);
      return if(!defined($client{$c}));		 # quit
    } else {
      $client{$c}{prompt} = 1;
    }
    syswrite($client{$c}{fd}, "FHZ> ")
	      if($client{$c}{prompt} && $rest !~ m/\n/);
  }
}

#####################################
sub
AnalyzeCommandChain($$)
{
  my ($c, $cmd) = @_;
  $cmd =~ s/#.*$//;
  $cmd =~ s/;;/____/g;
  foreach my $subcmd (split(";", $cmd)) {
    $subcmd =~ s/____/;/g;
    AnalyzeCommand($c, $subcmd);
    last if($c && !defined($client{$c}));	 # quit
  }
}

#####################################
# Used from perl oneliners inside of scripts
sub
fhz($)
{
  my $param = shift;
  return AnalyzeCommandChain($global_cl, $param);
}

#####################################
sub
AnalyzeCommand($$)
{
  my ($cl, $cmd) = @_;

  $cmd =~ s/^[ \t]*//;			# Strip space
  $cmd =~ s/[ \t]*$//;

  Log 5, "Cmd: >$cmd<";
  return if(!$cmd);

  if($cmd =~ m/^{.*}$/) {		# Perl code

    # Make life easier for oneliners: 
    %value = ();
    foreach my $d (keys %defs) { $value{$d} = $defs{$d}{STATE } }
    my ($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst) = localtime;
    my $we = (($wday==0 || $wday==6) ? 1 : 0);
    $month++;
    $year+=1900;

    $global_cl = $cl;
    my $ret = eval $cmd;
    $ret = $@ if($@);
    if($ret) {
      if($cl) {
	syswrite($client{$cl}{fd}, "$ret\n")
      } else {
	Log 3, $ret;
      }
    }
    return $ret;

  }

  if($cmd =~ m/^"(.*)"$/) {		 # Shell code, always in bg
    system("$1 &"); 
    return;
  }

  $cmd =~ s/^[ \t]*//;
  my ($fn, $param) = split("[ \t][ \t]*", $cmd, 2);

  return if(!$fn);

  #############
  # Search for abbreviation
  if(!defined($cmds{$fn})) {
    foreach my $f (sort keys %cmds) {
      if(length($f) > length($fn) && substr($f, 0, length($fn)) eq $fn) {
	Log 5, "$fn => $f";
        $fn = $f;
        last;
      }
    }
  }

  if(!defined($cmds{$fn})) {
    if($cl) {
      syswrite($client{$cl}{fd}, "Unknown command  $fn, try help\n");
    } else {
      Log 1, "Unknown command >$fn<, try help";
    }
    return;
  }
  $param = "" if(!defined($param));
  no strict "refs";
  my $ret = &{$cmds{$fn}{Fn} }($cl, $param);
  use strict "refs";
  if($ret) {
    if($cl) {
      syswrite($client{$cl}{fd}, $ret . "\n");
    } else {
      Log 1, $ret;
      return $ret;
    }
  }
}

#####################################
sub
CommandHelp($$)
{
  my ($cl, $param) = @_;

  my $str = "\n" .
            "Possible commands:\n\n" . 
            "Command   Parameter                 Description\n" .
	    "-----------------------------------------------\n";

  for my $cmd (sort keys %cmds) {
    my @a = split(",", $cmds{$cmd}{Hlp}, 2);

    $str .= sprintf("%-9s %-25s %s\n", $cmd, $a[0], $a[1]);
  }
  return $str;
}

sub
CommandInclude($$)
{
  my ($cl, $arg) = @_;
  if(!open(CFG, $arg)) {
    return "Can't open $arg: $!";
  }

  my $bigcmd = "";
  $rcvdquit = 0;
  while(my $l = <CFG>) {
    chomp($l);
    if($l =~ m/^(.*)\\$/) {		# Multiline commands
      $bigcmd .= $1;
    } else {
      AnalyzeCommandChain($cl, $bigcmd . $l);
      $bigcmd = "";
    }
    last if($rcvdquit);
  }
  close(CFG);
  return undef;
}

#####################################
sub
CommandPort($$)
{
  my ($cl, $arg) = @_;

  my ($port, $global) = split(" ", $arg);
  if($global && $global ne "global") {
    return "Bad syntax, usage: port <portnumber> [global]";
  }

  close($server) if($server);
  $server = IO::Socket::INET->new(
	Proto        => 'tcp',
	LocalHost    => ($global ? undef : "localhost"),
	LocalPort    => $port,
	Listen       => 10,
	ReuseAddr    => 1);

  die "Can't open server port at $port\n" if(!$server);
  return undef;
}

#####################################
sub
OpenLogfile($)
{
  my $param = shift;

  close(LOG) if($logfile);
  $logopened=0;
  $currlogfile = $param;
  if($currlogfile eq "-") {

    open LOG, '>&STDOUT'    or die "Can't dup stdout: $!";

  } else {
    
    open(LOG, ">>$currlogfile") || return("Can't open $currlogfile: $!");
    # Redirect stdin/stderr

    open STDIN,  '</dev/null'  or return "Can't read /dev/null: $!";

    close(STDERR);
    open(STDERR, ">>$currlogfile") or return "Can't append STDERR to log: $!";
    STDERR->autoflush(1);

    close(STDOUT);
    open STDOUT, '>&STDERR'    or return "Can't dup stdout: $!";
    STDOUT->autoflush(1);
  }
  LOG->autoflush(1);
  $logopened = 1;
  return undef;
}

#####################################
sub
CommandLogfile($$)
{
  my ($cl, $param) = @_;

  $logfile = $param;

  my @t = localtime;
  my $ret = OpenLogfile(ResolveDateWildcards($param, @t));
  die($ret) if($ret);
  return undef;
}



#####################################
sub
CommandVerbose($$)
{
  my ($cl, $param) = @_;
  if($param =~ m/^[0-5]$/) {
    $verbose = $param;
    return undef;
  } else {
    return "Valid value for verbose are 0,1,2,3,4,5";
  }
}

#####################################
sub
CommandRereadCfg($$)
{
  my ($cl, $param) = @_;

  return "RereadCfg: No parameters are accepted" if($param);
  DoSavefile();

  foreach my $d (keys %defs) {
    no strict "refs";
    my $ret = &{$devmods{$defs{$d}{TYPE}}{UndefFn}}($defs{$d}, $d);
    use strict "refs";
    return $ret if($ret);
  }

  %defs = ();
  %logs = ();
  %attr = ();
  %ntfy = ();
  %at   = ();

  my $ret;
  $ret = CommandInclude($cl, $configfile);
  return $ret if($ret);
  $ret = CommandInclude($cl, $savefile) if($savefile);
  return $ret;
}

#####################################
sub
CommandQuit($$)
{
  my ($cl, $param) = @_;

  if(!$cl) {
    $rcvdquit = 1;
    return;
  }

  syswrite($client{$cl}{fd}, "Bye...\n") if($client{$cl}{prompt});
  DoClose($cl);
  return undef;
}

#####################################
sub
DoSavefile()
{
  return if(!$savefile);
  if(!open(SFH, ">$savefile")) {
    Log 1, "Cannot open $savefile: $!";
    return;
  }

  my $t = localtime;
  print SFH "#$t\n";

  foreach my $d (sort keys %defs) {
    my $t = $defs{$d}{TYPE};
    print SFH "setstate $d $defs{$d}{STATE}\n"
      if($defs{$d}{STATE} && $defs{$d}{STATE} ne "unknown");

    #############
    # Now the detailed list
    no strict "refs";
    my $str = &{$devmods{$defs{$d}{TYPE}}{ListFn}}($defs{$d});
    use strict "refs";
    next if($str =~ m/^No information about/);

    foreach my $l (split("\n", $str)) {
      print SFH "setstate $d $l\n"
    }

  }

  foreach my $t (sort keys %at) {
    # $t =~ s/_/ /g; # Why is this here?
    print SFH "at $t\n";
  }

  close(SFH);
}

#####################################
sub
CommandShutdown($$)
{
  my ($cl, $param) = @_;
  Log 0, "Server shutdown";
  DoSavefile();
  unlink($pidfilename) if($pidfilename);
  exit(0);
}

#####################################
sub
CommandNotifyon($$)
{
  my ($cl, $param) = @_;

  my @a = split("[ \t]", $param, 2);

  # Checking for misleading regexps
  eval { "Hallo" =~ m/^$a[0]$/ };
  return "Bad regexp: $@" if($@);

  $ntfy{$a[0]} = SemicolonEscape($a[1]);
  return undef;
}

#####################################
sub
DoSet(@)
{
  my @a = @_;

  my $dev = $a[0];
  my $ret;
  no strict "refs";
  $ret = &{$devmods{$defs{$dev}{TYPE}}{SetFn}}($defs{$dev}, @a);
  use strict "refs";

  return $ret if($ret);

  shift @a;
  return DoTrigger($dev, join(" ", @a));
}

#####################################
sub
CommandSet($$)
{
  my ($cl, $param) = @_;
  my @a = split("[ \t][ \t]*", $param);
  return "Usage: set <name> <type-dependent-options>" if(int(@a) < 1);

  my $dev = $a[0];
  my @rets;

  if(defined($defs{$dev})) {

    return DoSet(@a);

  } elsif($dev =~ m/,/) {		 # Enumeration (separated by ,)

    foreach my $sdev (split(",", $dev)) {
      push @rets, "Please define $sdev first" if(!defined($defs{$sdev}));
      $a[0] = $sdev;
      my $ret = DoSet(@a);
      push @rets, $ret if($ret);
    }
    return join("\n", @rets);

  } elsif($dev =~ m/-/) {		 # Range (separated by -)

    my @lim = split("-", $dev);
    foreach my $sdev (keys %defs) {
      next if($sdev lt $lim[0] || $sdev gt $lim[1]);
      $a[0] = $sdev;
      my $ret = DoSet(@a);
      push @rets, $ret if($ret);
    }
    return join("\n", @rets);

  } else {

    return "Please define $dev first ($param)";

  }
}


#####################################
sub
CommandGet($$)
{
  my ($cl, $param) = @_;

  my @a = split("[ \t][ \t]*", $param);
  return "Usage: get <name> <type-dependent-options>" if(int(@a) < 1);
  my $dev = $a[0];
  return "Please define $dev first ($param)" if(!defined($defs{$dev}));

  ########################
  # Type specific set
  my $ret;
  no strict "refs";
  $ret = &{$devmods{$defs{$a[0]}{TYPE}}{GetFn}}($defs{$dev}, @a);
  use strict "refs";

  return $ret;
}

#####################################
sub
GetTimeSpec($)
{
  my ($tspec) = @_;
  my ($hr, $min, $sec, $fn);

  if($tspec =~ m/^([0-9]+):([0-5][0-9]):([0-5][0-9])$/) {
    ($hr, $min, $sec) = ($1, $2, $3);
  } elsif($tspec =~ m/^([0-9]+):([0-5][0-9])$/) {
    ($hr, $min, $sec) = ($1, $2, 0);
  } elsif($tspec =~ m/^{(.*)}$/) {
    $fn = $1;
    $tspec = eval $fn;
    if(!$@ && $tspec =~ m/^([0-9]+):([0-5][0-9]):([0-5][0-9])$/) {
      ($hr, $min, $sec) = ($1, $2, $3);
    } elsif(!$@ && $tspec =~ m/^([0-9]+):([0-5][0-9])$/) {
      ($hr, $min, $sec) = ($1, $2, 0);
    } else {
      $tspec = "<empty string>" if(!$tspec);
      return ("the at function must return a timespec HH:MM:SS and not $tspec.",
      		undef, undef, undef, undef);
    }
  } else {
    return ("Wrong timespec $tspec: either HH:MM:SS or {perlcode}",
    		undef, undef, undef, undef);
  }
  return (undef, $hr, $min, $sec, $fn);
}

#####################################
sub
CommandAt($$)
{
  my ($cl, $def) = @_;
  my ($tm, $command) = split("[ \t]+", $def, 2);

  return "Usage: at <timespec> <fhem-command>" if(!$command);
  return "Wrong timespec, use \"[+][*[{count}]]<time or func>\""
                                        if($tm !~ m/^(\+)?(\*({\d+})?)?(.*)$/);
  my ($rel, $rep, $cnt, $tspec) = ($1, $2, $3, $4);
  my ($err, $hr, $min, $sec, $fn) = GetTimeSpec($tspec);
  return $err if($err);

  $rel = "" if(!defined($rel));
  $rep = "" if(!defined($rep));
  $cnt = "" if(!defined($cnt));

  my $ot = time;
  my @lt = localtime($ot);
  my $nt = $ot;

  $nt -= ($lt[2]*3600+$lt[1]*60+$lt[0]) 	# Midnight for absolute time
  			if($rel ne "+");
  $nt += ($hr*3600+$min*60+$sec); # Plus relative time
  $nt += 86400 if($ot >= $nt);# Do it tomorrow...

  @lt = localtime($nt);
  my $ntm = sprintf("%02d:%02d:%02d", $lt[2], $lt[1], $lt[0]);

  if($rep) {	# Setting the number of repetitions
    $cnt =~ s/[{}]//g;
    return undef if($cnt eq "0");
    $cnt = 0 if(!$cnt);
    $cnt--;
    $at{$def}{REP} = $cnt;
  }
  $at{$def}{NTM} = $ntm if($rel eq "+" || $fn);
  $at{$def}{TIM} = $nt;
  $at{$def}{CMD} = SemicolonEscape($command);
  $nextat = $nt if(!$nextat || $nextat > $nt);

  return undef;
}


#####################################
sub
CommandDefine($$)
{
  my ($cl, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "Usage: define <name> <type> <type dependent arguments>"
  					if(int(@a) < 2);
  return "Unknown type $a[1]"
  	if(!defined($devmods{$a[1]}) && !defined($logmods{$a[1]}));
  return "$a[0] already defined" if(defined($defs{$a[0]}));
  return "Only following characters are allowed in a name: A-Za-z0-9-.:"
        if($a[0] !~ m/^[a-z0-9.:-]*$/i);

  my %hash;

  $hash{NAME}  = $a[0];
  $hash{TYPE}  = $a[1];
  $hash{STATE} = "???";
  $hash{DEF}   = $def;
  $hash{NR}    = $devcount++;

  # If the device wants to issue initialization gets/sets, then it should be 
  # in the global hash.
  my $ghash = (defined($devmods{$a[1]}) ? \%defs : \%logs);
  $ghash->{$a[0]} = \%hash;

  ########################
  # Type specific define
  my $ret;
  my $fnname = ($devmods{$a[1]} ? $devmods{$a[1]}{DefFn} :
                                  $logmods{$a[1]}{DefFn} );
  no strict "refs";
  $ret = &{$fnname}(\%hash, @a);
  use strict "refs";
  if($ret) {
    delete $ghash->{$a[0]}
  } else {
    foreach my $da (sort keys (%defattr)) {     # Default attributes
      CommandAttr($cl, "$a[0] $da $defattr{$da}");
    }
  }
  return $ret;
}

#############
# internal
sub
AssignIoPort($)
{
  my ($hash) = @_;

  # Set the I/O device
  for my $p (sort { $defs{$b}{NR} cmp $defs{$a}{NR} } keys %defs) {
    my $cl = $devmods{$defs{$p}{TYPE}}{Clients};
    if(defined($cl) && $cl =~ m/:$hash->{TYPE}:/) {
      $hash->{IODev} = $defs{$p};
      last;
    }
  }
  Log 3, "No I/O device found for $hash->{NAME}" if(!$hash->{IODev});
}

#############
# internal
sub
DoDel($$$)
{
  my($hash, $type, $v) = @_;

  if($type eq "def") {
    no strict "refs";
    my $ret = &{$devmods{$hash->{$v}{TYPE}}{UndefFn}}($hash->{$v}, $v);
    use strict "refs";
    return $ret if($ret);
    delete($attr{$v});
  }
  delete($hash->{$v});
  return undef;
}

#############
sub
CommandDelete($$)
{
  my ($cl, $def) = @_;
  my @a = split("[ \t]+", $def, 2);
  my $hash;

  my $arg = $a[1];
  if($a[0] eq "def") {
    $hash = \%defs;
  } elsif($a[0] eq "ntfy") {
    $hash = \%ntfy;
  } elsif($a[0] eq "at") {
    $hash = \%at;
    $arg =~ s/ \([0-2][0-9]:[0-5][0-9]:[0-5][0-9]\)$//;
  } elsif($a[0] eq "attr") {
    $hash = \%attr;
  } else {
    return "Unknown delete category, use one of def, ntfy or at";
  }

  my $found;

  if(defined($hash->{$arg})) {

    my $ret = DoDel($hash, $a[0], $arg);
    return $ret if($ret);
    $found = 1;

  } else {

    # Checking for misleading regexps
    eval { "Hallo" =~ m/$arg/ };
    return "Bad argument: $@" if($@);

    foreach my $v (keys %{ $hash }) {
      if($v =~ m/$arg/) {
	my $ret = DoDel($hash, $a[0], $v);
	return $ret if($ret);
	$found = 1;
      }
    }

    ##############
    # Handle the logs too
    if(!$found && $a[0] eq "def") {
      foreach my $v (keys %logs) {
	if($v =~ m/$arg/) {
	  no strict "refs";
	  my $ret = &{$logmods{$logs{$v}{TYPE}}{UndefFn}}($logs{$v}, $v);
	  use strict "refs";
	  return $ret if($ret);
	  delete($logs{$v});
	  $found = 1;
	}
      }
    }
  }

  return "No $a[0] values matched $a[1]" if(!$found);

  return undef;
}

#####################################
sub
CommandList($$)
{
  my ($cl, $param) = @_;
  my $str;

  if(!$param) {

    $str = "\nType list <name> for detailed info.\n";
    my $lt = "";
    			# Sort first by type then by name
    for my $d (sort { my $x = $devmods{$defs{$a}{TYPE}}{ORDER} cmp
		  	      $devmods{$defs{$b}{TYPE}}{ORDER};
		         $x = ($a cmp $b) if($x == 0); $x; } keys %defs) {
      my $t = $defs{$d}{TYPE};
      $str .= "\n$t devices:\n" if($t ne $lt);
      $str .= sprintf("  %-20s (%s)\n", $d, $defs{$d}{STATE});
      $lt = $t;
    }
    $str .= "\n";

    $str .= "NotifyOn:\n";
    for my $n (sort keys %ntfy) {
      $str .= sprintf("  %-20s %s\n", $n, $ntfy{$n});
    }
    $str .= "\n";

    $str .= "At:\n";
    for my $i (sort keys %at) {
      if($at{$i}{NTM}) {
        $str .= "  $i ($at{$i}{NTM})\n";
      } else {
        $str .= "  $i\n";
      }
    }
    $str .= "\n";

    $str .= "Logs:\n";
    for my $i (sort keys %logs) {
      $str .= "  " . $logs{$i}{DEF} . "\n";
    }

  } else {

    my @a = split(" ", $param);
    return "Usage: list [name]" if(@a > 1);
    return "No device named $a[0] found" if(!defined($defs{$a[0]}));

    no strict "refs";
    $str = "\n";
    $str .= "Definition: $defs{$a[0]}{DEF}\n";
    $str .= "Attached I/O device: $defs{$a[0]}{IODev}{NAME}\n"
    					if($defs{$a[0]}{IODev});
    foreach my $c (sort keys %{$attr{$a[0]}}) {
      $str .= "$c $attr{$a[0]}{$c}\n";
    }
    $str .= &{$devmods{$defs{$a[0]}{TYPE}}{ListFn}}($defs{$a[0]});
    use strict "refs";
    
  }

  return $str;
}


#####################################
sub
XmlEscape($)
{
  my $a = shift;
  $a =~ s/&/&amp;/g;
  $a =~ s/"/&quot;/g;
  $a =~ s/</&lt;/g;
  $a =~ s/>/&gt;/g;
  $a =~ s/°/&#b0;/g;
  return $a;
}

#####################################
sub
CommandXmlList($$)
{
  my ($cl, $param) = @_;
  my $str = "<FHZINFO>\n";
  my $lt = "";


  for my $d (sort { my $x =
  		$devmods{$defs{$a}{TYPE}}{ORDER} cmp
    		$devmods{$defs{$b}{TYPE}}{ORDER};
    		$x = ($a cmp $b) if($x == 0); $x; } keys %defs) {

      my $t = $defs{$d}{TYPE};


      if($t ne $lt) {
        $str .= "\t</${lt}_DEVICES>\n" if($lt);
        $str .= "\t<${t}_DEVICES>\n";
      }
      $lt = $t;

      no strict "refs";
      my @lines = split("\n", &{$devmods{$t}{ListFn}}($defs{$d}));
      use strict "refs";

      my $def = XmlEscape($defs{$d}{DEF});
      my $xmld = XmlEscape($d);
      my $xmls = XmlEscape($defs{$d}{STATE});

      $def =~ s/ +/ /g;
      $str .= "\t\t<$t name=\"$xmld\" definition=\"$def\" state=\"$xmls\"";
      my $multiline = (int(@lines) || defined($attr{$d}));
      $str .= ($multiline ? ">\n" : "/>\n");

      foreach my $c (sort keys %{$attr{$d}}) {
        my $xc = XmlEscape($c);
        my $xv = XmlEscape($attr{$d}{$c});
	$str .= "\t\t\t<ATTR key=\"$xc\" value=\"$xv\"/>\n";
      }

      foreach my $l (@lines) {
        my ($date, $time, $attr, $val) = split(" ", $l, 4);
	$val = "" if(!$val);
        $attr = XmlEscape($attr);
        $val  = XmlEscape($val);
	$str .= "\t\t\t<STATE name=\"$attr\" " .
      		"value=\"$val\" measured=\"$date $time\"/>\n";
      }
      $str .= "\t\t</$t>\n" if($multiline);
  }
  $str .= "\t</${lt}_DEVICES>\n" if($lt);

  $lt = "";
  for my $i (sort keys %logs) {
    $str .= "\t<LOGS>\n" if(!$lt);
    $lt = XmlEscape($logs{$i}{DEF});
    my @a = split(" ", $lt, 2);
    $str .= "\t\t<LOG name=\"$a[0]\" definition=\"$lt\"/>\n";
    foreach my $a (sort keys %{$attr{$i}}) {
      my $xa = XmlEscape($a);
      my $v = XmlEscape($attr{$i}{$a});
      $str .= "\t\t\t<ATTR key=\"$xa\" value=\"$v\"/>\n";
    }
  }
  $str .= "\t</LOGS>\n" if($lt);

  $str .= "\t<NOTIFICATIONS>\n";
  for my $n (sort keys %ntfy) {
    my $xn = XmlEscape($n);
    my $cmd = XmlEscape($ntfy{$n});
    $str .= "\t\t<NOTIFY_ON event=\"$xn\" command=\"$cmd\"/>\n";
  }
  $str .= "\t</NOTIFICATIONS>\n";


  $str .= "\t<AT_JOBS>\n";
  for my $i (sort keys %at) {
    my $cmd = XmlEscape($i);
    if($at{$i}{NTM}) {
      $str .= "\t\t<AT command=\"$cmd\" next=\"$at{$i}{NTM}\"/>\n";
    } else {
      $str .= "\t\t<AT command=\"$cmd\"/>\n";
    }
    foreach my $c (sort keys %{$attr{$i}}) {
      my $xc = XmlEscape($c);
      my $v = XmlEscape($attr{$i}{$c});
      $str .= "\t\t\t<ATTR key=\"$xc\" value=\"$v\"/>\n";
    }
  }
  $str .= "\t</AT_JOBS>\n";
  $str .= "</FHZINFO>\n";
  return $str;
}

#####################################
sub
CommandReload($$)
{
  my ($cl, $param) = @_;
  my %hash;

  $param =~ s,[\./],,g;
  $param =~ s,\.pm$,,g;
  my $file = "$modpath_set/FHEM/$param.pm";
  return "Can't read $file: $!" if(! -r "$file");

  my $m = $param;
  $m =~ s,^[0-9][0-9]_,,;
  Log 2, "Loading $file";

  my $ret;
  no strict "refs";
  eval { 
    do "$file";
    $ret = &{ "${m}_Initialize" }(\%hash);
  };
  if($@) {
    return "$@";
  }
  use strict "refs";

  $devmods{$m} = \%hash if($hash{Category} eq "DEV");
  $logmods{$m} = \%hash if($hash{Category} eq "LOG");

  return undef;
}

#####################################
sub
CommandModpath($$)
{
  my ($cl, $param) = @_;

  return "modpath must point to a directory where the FHEM subdir is"
  	if(! -d "$param/FHEM");
  my $modpath = "$param/FHEM";

  opendir(DH, $modpath) || return "Can't read $modpath: $!";

  my $counter = 0;
  foreach my $m (sort grep(/^[0-9][0-9].*\.pm$/,readdir(DH))) {

    $counter++;
    Log 5, "Loading $m";
    require "$modpath/$m";

    next if($m !~ m/([0-9][0-9])_(.*)\.pm$/);

    $m = $2;
    my %hash;
    $hash{ORDER} = $1;

    no strict "refs";
    my $ret = &{ "${m}_Initialize" }(\%hash);
    use strict "refs";

    $devmods{$m} = \%hash if($hash{Category} eq "DEV");
    $logmods{$m} = \%hash if($hash{Category} eq "LOG");
  }
  closedir(DH);

  if(!$counter) {
    return "No modules found, " .
    		"point modpath to a directory where the FHEM subdir is";
  }

  $modpath_set = $param;

  return undef;
}

#####################################
sub
CommandAttr($$)
{
  my ($cl, $param) = @_;
  my $ret = undef;
  
  my @a = split(" ", $param, 3);
  return "Usage: attr [<devname>|at] <attrname> [<attrvalue>]" if(@a < 2);
  return "Usage: attr at <at-spec> <attrname>" if(@a < 3 && $a[0] eq "at");

  my $have = 0;

  if($a[0] eq "at") {				# "at" special

    my $arg = $a[1];
    $arg =~ s/ \([0-2][0-9]:[0-5][0-9]:[0-5][0-9]\)$//;

    if(defined($at{$arg})) {		# First the exact version
      $attr{$arg}{$a[2]} = "1";
    } else {				# then the regexp
      # Checking for misleading regexps
      eval { "Hallo" =~ m/$arg/ };
      return "Bad argument: $@" if($@);
      foreach my $a (keys %at) {
	if($a =~ m/$arg/) {
	  $attr{$a}{$a[2]} = "1";
	  $have = 1;
	  last;
	}
      }
    }
    return "No at spec found" if(!$have);
    return undef;
  }

  $have = 1 if(defined($defs{$a[0]}));
  $have = 1 if(defined($logs{$a[0]}));

  return "Please define $a[0] first: no device or log definition found"
    if(!$have);

  if(defined($a[2])) {
    $attr{$a[0]}{$a[1]} = $a[2];
  } else {
    $attr{$a[0]}{$a[1]} = "1";
  }
  return undef;
}

sub
CommandDefAttr($$)
{
  my ($cl, $param) = @_;

  my @a = split(" ", $param, 2);
  if(int(@a) == 0) {
    %defattr = ();
  } elsif(int(@a) == 1) {
    $defattr{$a[0]} = 1;
  } else {
    $defattr{$a[0]} = $a[1];
  } 
  return undef;
}

#####################################
sub
CommandSetstate($$)
{
  my ($cl, $param) = @_;
  my $ret = undef;
  
  my @a = split(" ", $param, 2);
  return "Usage: setstate <name> <state>" if(@a != 2);
  return "Please define $a[0] first" if(!defined($defs{$a[0]}));

  # Detailed state with timestamp
  if($a[1] =~ m/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} /) {
    my @b = split(" ", $a[1], 4);
    no strict "refs";
    $ret = &{$devmods{$defs{$a[0]}{TYPE}}{StateFn}}
    			($defs{$a[0]}, "$b[0] $b[1]", $b[2], $b[3]);
    use strict "refs";
    $oldvalue{$a[0]}{TIME} = "$b[0] $b[1]";
    $oldvalue{$a[0]}{VAL} = $b[2];
  } else {
    $defs{$a[0]}{STATE} = $a[1];
  }
  
  return $ret;
}

#####################################
sub
CommandSavefile($$)
{
  my ($cl, $param) = @_;
  
  $savefile = $param;
  return undef;
}

#####################################
sub
CommandPidfile($$)
{
  my ($cl, $param) = @_;
  
  $pidfilename = $param;
  return undef if(!$init_done);

  return "$param: $!" if(!open(PID, ">$param"));
  print PID $$ . "\n";
  close(PID);

  return undef;
}


#####################################
sub
CommandTrigger($$)
{
  my ($cl, $param) = @_;

  my ($dev, $state) = split(" ", $param, 2);
  return "Usage: trigger <device> <state>" if(!$state);
  return "Please define $dev first" if(!defined($defs{$dev}));
  return DoTrigger($dev, $state);
}

#####################################
sub
CommandInform($$)
{
  my ($cl, $param) = @_;

  if(!$cl) {
    return;
  }

  return "Usage: inform {on|off}" if($param !~ m/^(on|off)$/i);
  $client{$cl}{inform} = ($param =~ m/on/i);
  Log 4, "Setting inform to " . ($client{$cl}{inform} ? "on" : "off");

  return undef;
}

#####################################
sub
CommandSleep($$)
{
  my ($cl, $param) = @_;

  return "Cannot interpret $param as seconds" if($param !~ m/^[0-9\.]+$/);
  Log 4, "sleeping for $param";
  select(undef, undef, undef, $param);
  return undef;
}


#####################################
# Return the time to the next event (or undef if there is none)
# and call each function which was scheduled for this time
sub
HandleTimeout()
{
  return undef if(!$nextat);

  my $now = gettimeofday();
  return ($nextat-$now) if($now < $nextat);

  $nextat = 0;
  foreach my $i (keys %at) {
    if($now >= $at{$i}{TIM}) {
      my $skip = (defined($attr{$i}) && defined($attr{$i}{skip_next}));

      if($skip) {
        delete $attr{$i}{skip_next};
      } else {
        AnalyzeCommandChain(undef, $at{$i}{CMD});
      }

      my $count = $at{$i}{REP};
      delete $at{$i};
      if($count) {
	$i =~ s/{\d+}/{$count}/ if($i =~ m/^\+?\*{/);	# Replace the count }
        CommandAt(undef, $i);	# Recompute the next TIM
      }

    } else {

      $nextat = $at{$i}{TIM} if(!$nextat || $nextat > $at{$i}{TIM});

    }
  }

  #############
  # Check the internal list.
  foreach my $i (keys %intAt) {
    my $tim = $intAt{$i}{TIM};
    if($tim <= $now) {
      no strict "refs";
      &{$intAt{$i}{FN}}($intAt{$i}{ARG});
      use strict "refs";
      delete($intAt{$i});
    }
    $nextat = $tim if(!$nextat || $nextat > $tim);
  }

  return undef if(!$nextat);
  $now = gettimeofday();
  return ($now < $nextat) ? ($nextat-$now) : 0;
}


#####################################
sub
InternalTimer($$$)
{
  my ($tim, $fn, $arg) = @_;

  if(!$init_done) {
    select(undef, undef, undef, $tim-gettimeofday());
    no strict "refs";
    &{$fn}($arg);
    use strict "refs";
    return;
  }

  $intAt{$intAtCnt}{TIM} = $tim;
  $intAt{$intAtCnt}{FN} = $fn;
  $intAt{$intAtCnt}{ARG} = $arg;
  $intAtCnt++;
  $nextat = $tim if(!$nextat || $nextat > $tim);
}


#####################################
sub
SignalHandling()
{
  if ($^O ne "MSWin32") {

    $SIG{'INT'}  = sub { $sig_term = 1; };
    $SIG{'QUIT'} = sub { $sig_term = 1; };
    $SIG{'TERM'} = sub { $sig_term = 1; };
    $SIG{'PIPE'} = 'IGNORE';
    $SIG{'CHLD'} = 'IGNORE';
    $SIG{'HUP'}  = sub { CommandRereadCfg(undef, "") };
  }
}

#####################################
sub
TimeNow()
{
  my @t = localtime;
  return sprintf("%04d-%02d-%02d %02d:%02d:%02d",
      $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0]);
}

#####################################
sub
CommandChain($$)
{
  my ($retry, $list) = @_;
  my $ov = $verbose;
  my $oid = $init_done;

  $init_done = 0;
  $verbose = 1;
  foreach my $cmd (@{$list}) {
    for(my $n = 0; $n < $retry; $n++) {
      Log 1, sprintf("Trying again $cmd (%d out of %d)", $n+1,$retry) if($n>0);
      my $ret = AnalyzeCommand(undef, $cmd);
      last if(!$ret || $ret !~ m/Timeout/);
    }
  }
  $verbose = $ov;
  $init_done = $oid;
}

#####################################
sub
ResolveDateWildcards($@)
{
  my ($f, @t) = @_;
  return $f if(!$f);
  return $f if($f !~ m/%/);	# Be fast if there is no wildcard

  my $M = sprintf("%02d", $t[1]);      $f =~ s/%M/$M/g;
  my $H = sprintf("%02d", $t[2]);      $f =~ s/%H/$H/g;
  my $d = sprintf("%02d", $t[3]);      $f =~ s/%d/$d/g;
  my $m = sprintf("%02d", $t[4]+1);    $f =~ s/%m/$m/g;
  my $Y = sprintf("%04d", $t[5]+1900); $f =~ s/%Y/$Y/g;
  my $w = sprintf("%d",   $t[6]);      $f =~ s/%w/$w/g;
  my $j = sprintf("%03d", $t[7]+1);    $f =~ s/%j/$j/g;
  my $U = sprintf("%02d", int(($t[7]-$t[6]+6)/7));   $f =~ s/%U/$U/g;
  my $V = sprintf("%02d", int(($t[7]-$t[6]+7)/7)+1); $f =~ s/%V/$V/g;
  
  return $f;
}

sub
SemicolonEscape($)
{
  my $cmd = shift;

  $cmd =~ s/^[ \t]*//;
  $cmd =~ s/[ \t]*$//;
  if($cmd =~ m/^{.*}$/ || $cmd =~ m/^".*"$/) {
    $cmd =~ s/;/;;/g
  }
  return $cmd;
}

sub
DoTrigger($$)
{
  my ($dev, $ns) = @_;

  return "" if(!defined($defs{$dev}));

  if(defined($ns)) {
    $defs{$dev}{CHANGED}[0] = $ns;
  } elsif(!defined($defs{$dev}{CHANGED})) {
    return "";
  }
  Log 5, "Triggering $dev";

  my $max = int(@{$defs{$dev}{CHANGED}});
  my $ret = "";

  return "" if(defined($attr{$dev}) && defined($attr{$dev}{do_not_notify}));

  for(my $i = 0; $i < $max; $i++) {
    my $state = $defs{$dev}{CHANGED}[$i];
    my $fe = "$dev:$state";

    ################
    # Notify
    foreach my $n (sort keys %ntfy) {
      if($dev =~ m/^$n$/ || $fe =~ m/^$n$/) {
	my $exec = $ntfy{$n};

	$exec =~ s/%%/____/g;
	$exec =~ s/%/$state/g;
	$exec =~ s/____/%/g;

	$exec =~ s/@@/____/g;
	$exec =~ s/@/$dev/g;
	$exec =~ s/____/@/g;

	my $r = AnalyzeCommandChain(undef, $exec);
	$ret .= " $r" if($r);
      }
    }

    ################
    # Inform
    foreach my $c (keys %client) {
      next if(!$client{$c}{inform});
      syswrite($client{$c}{fd}, "$defs{$dev}{TYPE} $dev $state\n");
    }
  }


  ################
  # Log modules
  foreach my $l (sort keys %logs) {
    my $t = $logs{$l}{TYPE};
    no strict "refs";
    &{$logmods{$t}{LogFn}}($logs{$l}, $defs{$dev});
    use strict "refs";
  }

  ####################
  # Used by triggered perl programs to check the old value
  # Not suited for multi-valued devices (KS300, etc)
  $oldvalue{$dev}{TIME} = TimeNow();
  $oldvalue{$dev}{VAL} = $defs{$dev}{CHANGED}[0];

  delete($defs{$dev}{CHANGED});

  Log 3, "NTFY return: $ret" if($ret);
  return $ret;
}
