#!/usr/bin/perl

################################################################
#
#  Copyright notice
#
#  (c) 2005-2012
#  Copyright: Rudolf Koenig (r dot koenig at koeniglich dot de)
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
#  Homepage:  http://fhem.de
#
# $Id$


use strict;
use warnings;
use IO::Socket;
use Time::HiRes qw(gettimeofday);


##################################################
# Forward declarations
#
sub AddDuplicate($$);
sub AnalyzeCommand($$);
sub AnalyzeCommandChain($$);
sub AnalyzeInput($);
sub AnalyzePerlCommand($$);
sub AssignIoPort($);
sub AttrVal($$$);
sub CallFn(@);
sub CheckDuplicate($$@);
sub rejectDuplicate($$$);
sub CommandChain($$);
sub Dispatch($$$);
sub DoTrigger($$@);
sub EvalSpecials($%);
sub EventMapAsList($);
sub FmtDateTime($);
sub FmtTime($);
sub GetLogLevel(@);
sub GetTimeSpec($);
sub HandleArchiving($);
sub HandleTimeout();
sub IOWrite($@);
sub InternalTimer($$$$);
sub IsDummy($);
sub IsIgnored($);
sub IsDisabled($);
sub LoadModule($);
sub Log($$);
sub OpenLogfile($);
sub PrintHash($$);
sub ReadingsVal($$$);
sub RemoveInternalTimer($);
sub ReplaceEventMap($$$);
sub ResolveDateWildcards($@);
sub SecondsTillTomorrow($);
sub SemicolonEscape($);
sub SignalHandling();
sub TimeNow();
sub WriteStatefile();
sub XmlEscape($);
sub addEvent($$);
sub addToAttrList($);
sub createInterfaceDefinitions();
sub devspec2array($);
sub doGlobalDef($);
sub fhem($@);
sub fhz($);
sub getAllGets($);
sub getAllSets($);
sub readingsBeginUpdate($);
sub readingsBulkUpdate($$$@);
sub readingsEndUpdate($$);
sub readingsSingleUpdate($$$$);
sub redirectStdinStdErr();
sub setGlobalAttrBeforeFork($);
sub setReadingsVal($$$$);
sub evalStateFormat($);
sub latin1ToUtf8($);
sub Log($$);
sub Log3($$$);

sub CommandAttr($$);
sub CommandDefaultAttr($$);
sub CommandDefine($$);
sub CommandDelete($$);
sub CommandDeleteAttr($$);
sub CommandGet($$);
sub CommandHelp($$);
sub CommandIOWrite($$);
sub CommandInclude($$);
sub CommandInform($$);
sub CommandList($$);
sub CommandModify($$);
sub CommandQuit($$);
sub CommandReload($$);
sub CommandRename($$);
sub CommandRereadCfg($$);
sub CommandSave($$);
sub CommandSet($$);
sub CommandSetstate($$);
sub CommandShutdown($$);
sub CommandSleep($$);
sub CommandTrigger($$);

##################################################
# Variables:
# global, to be able to access them from modules

#Special values in %modules (used if set):
# DefFn    - define a "device" of this type
# UndefFn  - clean up (delete timer, close fd), called by delete and rereadcfg
# DeleteFn - clean up (delete logfile), called by delete after UndefFn
# ParseFn  - Interpret a raw message
# ListFn   - details for this "device"
# SetFn    - set/activate this device
# GetFn    - get some data from this device
# StateFn  - set local info for this device, do not activate anything
# NotifyFn - call this if some device changed its properties
# RenameFn - inform the device about its renameing
# ReadyFn  - check for available data, if no FD
# ReadFn   - Reading from a Device (see FHZ/WS300)

#Special values in %defs:
# TYPE    - The name of the module it belongs to
# STATE   - Oneliner describing its state
# NR      - its "serial" number
# DEF     - its definition
# READINGS- The readings. Each value has a "VAL" and a "TIME" component.
# FD      - FileDescriptor. Used by selectlist / readyfnlist
# IODev   - attached to io device
# CHANGED - Currently changed attributes of this device. Used by NotifyFn
# VOLATILE- Set if the definition should be saved to the "statefile"

use vars qw(%modules);		# List of loaded modules (device/log/etc)
use vars qw(%defs);		# FHEM device/button definitions
use vars qw(%attr);		# Attributes
use vars qw(%interfaces);       # Global interface definitions, see createInterfaceDefinitions below
use vars qw(%selectlist);	# devices which want a "select"
use vars qw(%readyfnlist);	# devices which want a "readyfn"
use vars qw($readytimeout);	# Polling interval. UNIX: device search only
$readytimeout = ($^O eq "MSWin32") ? 0.1 : 5.0;

use vars qw(%value);		# Current values, see commandref.html
use vars qw(%oldvalue);		# Old values, see commandref.html
use vars qw($init_done);        #
use vars qw($internal_data);    #
use vars qw(%cmds);             # Global command name hash. To be expanded
use vars qw(%data);		# Hash for user data
use vars qw($devcount);	        # To sort the devices
use vars qw(%defaultattr);    	# Default attributes, used by FHEM2FHEM
use vars qw(%addNotifyCB);	# Used by event enhancers (e.g. avarage)
use vars qw(%inform);	        # Used by telnet_ActivateInform

use vars qw($reread_active);

my $AttrList = "room group comment alias eventMap userReadings";

my %comments;			# Comments from the include files
my $ipv6;			# Using IPV6
my $currlogfile;		# logfile, without wildcards
my $currcfgfile="";		# current config/include file
my $logopened = 0;              # logfile opened or using stdout
my $rcvdquit;			# Used for quit handling in init files
my $sig_term = 0;		# if set to 1, terminate (saving the state)
my %intAt;			# Internal at timer hash.
my $nextat;                     # Time when next timer will be triggered.
my $intAtCnt=0;
my %duplicate;                  # Pool of received msg for multi-fhz/cul setups
my $duplidx=0;                  # helper for the above pool
my $readingsUpdateDelayTrigger; # needed internally
my $cvsid = '$Id$';
my $namedef =
  "where <name> is either:\n" .
  "- a single device name\n" .
  "- a list separated by komma (,)\n" .
  "- a regexp, if it contains one of the following characters: *[]^\$\n" .
  "- a range separated by dash (-)\n";
my @cmdList;                    # Remaining commands in a chain. Used by sleep
my $evalSpecials;       # Used by EvalSpecials->AnalyzeCommand parameter passing

$init_done = 0;

$modules{Global}{ORDER} = -1;
$modules{Global}{LOADED} = 1;
$modules{Global}{AttrList} =
  "archivecmd apiversion archivedir configfile lastinclude logfile " .
  "modpath nrarchive pidfilename port statefile title userattr " .
  "verbose:1,2,3,4,5 mseclog:1,0 version nofork:1,0 logdir holiday2we " .
  "autoload_undefined_devices:1,0 dupTimeout latitude longitude altitude " .
  "backupcmd backupdir backupsymlink backup_before_update " .
  "exclude_from_update motd updatebranch uniqueID ".
  "sendStatistics:onUpdate,manually,never updateInBackground:1,0 ".
  "showInternalValues:1,0 ";
$modules{Global}{AttrFn} = "GlobalAttr";

use vars qw($readingFnAttributes);
$readingFnAttributes = "event-on-change-reading event-on-update-reading ".
                      "event-min-interval stateFormat";


%cmds = (
  "?"       => { Fn=>"CommandHelp",
	    Hlp=>",get this help" },
  "attr" => { Fn=>"CommandAttr",
           Hlp=>"<devspec> <attrname> [<attrval>],set attribute for <devspec>"},
  "define"  => { Fn=>"CommandDefine",
	    Hlp=>"<name> <type> <options>,define a device/at/notify entity" },
  "deleteattr" => { Fn=>"CommandDeleteAttr",
	    Hlp=>"<devspec> [<attrname>],delete attribute for <devspec>" },
  "deletereading" => { Fn=>"CommandDeleteReading",
            Hlp=>"<devspec> [<attrname>],delete user defined reading for <devspec>" },
  "delete"  => { Fn=>"CommandDelete",
	    Hlp=>"<devspec>,delete the corresponding definition(s)"},
  "displayattr"=> { Fn=>"CommandDisplayAttr",
	    Hlp=>"<devspec> [attrname],display attributes" },
  "get"     => { Fn=>"CommandGet",
	    Hlp=>"<devspec> <type dependent>,request data from <devspec>" },
  "help"    => { Fn=>"CommandHelp",
	    Hlp=>",get this help" },
  "include" => { Fn=>"CommandInclude",
	    Hlp=>"<filename>,read the commands from <filenname>" },
  "inform" => { Fn=>"CommandInform",
            ClientFilter => "telnet",
	    Hlp=>"{on|timer|raw|off},echo all events to this client" },
  "iowrite" => { Fn=>"CommandIOWrite",
            Hlp=>"<iodev> <data>,write raw data with iodev" },
  "list"    => { Fn=>"CommandList",
	    Hlp=>"[devspec],list definitions and status info" },
  "modify"  => { Fn=>"CommandModify",
	    Hlp=>"device <options>,modify the definition (e.g. at, notify)" },
  "quit"    => { Fn=>"CommandQuit",
            ClientFilter => "telnet",
	    Hlp=>",end the client session" },
  "exit"    => { Fn=>"CommandQuit",
            ClientFilter => "telnet",
	    Hlp=>",end the client session" },
  "reload"  => { Fn=>"CommandReload",
	    Hlp=>"<module-name>,reload the given module (e.g. 99_PRIV)" },
  "rename"  => { Fn=>"CommandRename",
	    Hlp=>"<old> <new>,rename a definition" },
  "rereadcfg"  => { Fn=>"CommandRereadCfg",
	    Hlp=>"[configfile],read in the config after deleting everything" },
  "save"    => { Fn=>"CommandSave",
	    Hlp=>"[configfile],write the configfile and the statefile" },
  "set"     => { Fn=>"CommandSet",
	    Hlp=>"<devspec> <type dependent>,transmit code for <devspec>" },
  "setstate"=> { Fn=>"CommandSetstate",
	    Hlp=>"<devspec> <state>,set the state shown in the command list" },
  "setdefaultattr" => { Fn=>"CommandDefaultAttr",
	    Hlp=>"<attrname> <attrvalue>,set attr for following definitions" },
  "shutdown"=> { Fn=>"CommandShutdown",
	    Hlp=>"[restart],terminate the server" },
  "sleep"  => { Fn=>"CommandSleep",
            Hlp=>"<sec> [quiet],sleep for sec, 3 decimal places" },
  "trigger" => { Fn=>"CommandTrigger",
            Hlp=>"<devspec> <state>,trigger notify command" },
  "update" => {
            Hlp => "[development|stable] [<file>|check|fhem],update Fhem" },
  "updatefhem" => { ReplacedBy => "update" },
  "version" => { Fn => "CommandVersion",
            Hlp=>"[filter],print SVN version of loaded modules" },
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

# If started as root, and there is a fhem user in the /etc/passwd, su to it
if($^O !~ m/Win/ && $< == 0) {

  my @pw = getpwnam("fhem");
  if(@pw) {
    use POSIX qw(setuid setgid);

    # set primary group
    setgid($pw[3]);

    # read all secondary groups into an array:
    my @groups;
    while ( my ($name, $pw, $gid, $members) = getgrent() ) {
      push(@groups, $gid) if ( grep($_ eq $pw[0],split(/\s+/,$members)) );
    }

    # set the secondary groups via $)
    if (@groups) {
      $) = "$pw[3] ".join(" ",@groups);
    } else {
      $) = "$pw[3] $pw[3]";
    }

    setuid($pw[2]);
  }

}

###################################################
# Client code
if(int(@ARGV) == 2) {
  my $buf;
  my $addr = $ARGV[0];
  $addr = "localhost:$addr" if($ARGV[0] !~ m/:/);
  my $client = IO::Socket::INET->new(PeerAddr => $addr);
  die "Can't connect to $addr\n" if(!$client);
  syswrite($client, "$ARGV[1] ; quit\n");
  shutdown($client, 1);
  while(sysread($client, $buf, 256) > 0) {
    print($buf);
  }
  exit(0);
}
# End of client code
###################################################


###################################################
# for debugging
sub
Debug($) {
  my $msg= shift;
  Log 1, "DEBUG>" . $msg;
}
###################################################


###################################################
# Server initialization
doGlobalDef($ARGV[0]);

# As newer Linux versions reset serial parameters after fork, we parse the
# config file after the fork. Since need some global attr parameters before, we
# read them here.
setGlobalAttrBeforeFork($attr{global}{configfile});

if($^O =~ m/Win/ && !$attr{global}{nofork}) {
  Log 1, "Forcing 'attr global nofork' on WINDOWS";
  Log 1, "set it in the config file to avoid this message";
  $attr{global}{nofork}=1;
}


# Go to background if the logfile is a real file (not stdout)
if($attr{global}{logfile} ne "-" && !$attr{global}{nofork}) {
  defined(my $pid = fork) || die "Can't fork: $!";
  exit(0) if $pid;
}

# FritzBox special: Wait until the time is set via NTP,
# but not more than 2 hours
while(time() < 2*3600) {
  sleep(5);
}

my $ret = CommandInclude(undef, $attr{global}{configfile});
Log 1, "configfile: $ret" if($ret);

if($attr{global}{statefile} && -r $attr{global}{statefile}) {
  $ret = CommandInclude(undef, $attr{global}{statefile});
  Log 1, "statefile: $ret" if($ret);
}

SignalHandling();

my $pfn = $attr{global}{pidfilename};
if($pfn) {
  die "$pfn: $!\n" if(!open(PID, ">$pfn"));
  print PID $$ . "\n";
  close(PID);
}

# create the global interface definitions
createInterfaceDefinitions();

my $gp = $attr{global}{port};
if($gp) {
  Log 3, "Converting 'attr global port $gp' to 'define telnetPort telnet $gp'";
  my $ret = CommandDefine(undef, "telnetPort telnet $gp");
  Log 1, "$ret" if($ret);
  delete($attr{global}{port});
}

my $sc_text = "SecurityCheck:";
$attr{global}{motd} = "$sc_text\n\n"
        if(!$attr{global}{motd} || $attr{global}{motd} =~ m/^$sc_text/);

$init_done = 1;
DoTrigger("global", "INITIALIZED", 1);

$attr{global}{motd} .= "Running with root privileges."
        if($^O !~ m/Win/ && $<==0 && $attr{global}{motd} =~ m/^$sc_text/);
$attr{global}{motd} .=
        "\nRestart fhem for a new check if the problem is fixed,\n".
        "or set the global attribute motd to none to supress this message.\n"
        if($attr{global}{motd} =~ m/^$sc_text\n\n./);
my $motd = $attr{global}{motd};
if($motd eq "$sc_text\n\n") {
  delete($attr{global}{motd});
} else {
  if($motd ne "none") {
    $motd =~ s/\n/ /g;
    Log 2, $motd;
  }
}

Log 0, "Server started with ".int(keys %defs).
        " defined entities (version $attr{global}{version}, pid $$)";

################################################
# Main Loop
sub MAIN {MAIN:};               #Dummy


my $errcount= 0;
while (1) {
  my ($rout, $rin) = ('', '');

  my $timeout = HandleTimeout();

  foreach my $p (keys %selectlist) {
    vec($rin, $selectlist{$p}{FD}, 1) = 1;
  }
  $timeout = $readytimeout if(keys(%readyfnlist) &&
                              (!defined($timeout) || $timeout > $readytimeout));
  my $nfound = select($rout=$rin, undef, undef, $timeout);

  CommandShutdown(undef, undef) if($sig_term);

  if($nfound < 0) {
    my $err = int($!);
    next if ($err == 0);

    Log 1, "ERROR: Select error $nfound ($err), error count= $errcount";
    $errcount++;

    # Handling "Bad file descriptor". This is a programming error.
    if($err == 9) {  # BADF, don't want to "use errno.ph"
      my $nbad = 0;
      foreach my $p (keys %selectlist) {
        my ($tin, $tout) = ('', '');
        vec($tin, $selectlist{$p}{FD}, 1) = 1;
        if(select($tout=$tin, undef, undef, 0) < 0) {
          Log 1, "Found and deleted bad fileno for $p";
          delete($selectlist{$p});
          $nbad++;
        }
      }
      next if($nbad > 0);
      next if($errcount <= 3);
    }
    die("Select error $nfound ($err)\n");
  } else {
    $errcount= 0;
  }

  ###############################
  # Message from the hardware (FHZ1000/WS3000/etc) via select or the Ready
  # Function. The latter ist needed for Windows, where USB devices are not
  # reported by select, but is used by unix too, to check if the device is
  # attached again.
  foreach my $p (keys %selectlist) {
    next if(!$selectlist{$p} || !$selectlist{$p}{NAME}); # due to rereadcfg/del

    CallFn($selectlist{$p}{NAME}, "ReadFn", $selectlist{$p})
      if(vec($rout, $selectlist{$p}{FD}, 1));
  }
  foreach my $p (keys %readyfnlist) {
    next if(!$readyfnlist{$p});                 # due to rereadcfg / delete

    if(CallFn($readyfnlist{$p}{NAME}, "ReadyFn", $readyfnlist{$p})) {
      if($readyfnlist{$p}) {                    # delete itself inside ReadyFn
        CallFn($readyfnlist{$p}{NAME}, "ReadFn", $readyfnlist{$p});
      }

    }
  }

}

################################################
#Functions ahead, no more "plain" code

################################################
sub
IsDummy($)
{
  my $devname = shift;

  return 1 if(defined($attr{$devname}) && defined($attr{$devname}{dummy}));
  return 0;
}

sub
IsIgnored($)
{
  my $devname = shift;
  if($devname &&
     defined($attr{$devname}) &&
     defined($attr{$devname}{ignore})) {
    Log 4, "Ignoring $devname";
    return 1;
  }
  return 0;
}

sub
IsDisabled($)
{
  my $devname = shift;
  if($devname &&
     defined($attr{$devname}) &&
     defined($attr{$devname}{disable})) {
    Log 4, "Disabled $devname";
    return 1;
  }
  return 0;
}


################################################
sub
IsIoDummy($)
{
  my $name = shift;

  return IsDummy($defs{$name}{IODev}{NAME})
                if($defs{$name} && $defs{$name}{IODev});
  return 1;
}


################################################
sub
GetLogLevel(@)
{
  my ($dev,$deflev) = @_;
  my $df = defined($deflev) ? $deflev : 2;

  return $df if(!defined($dev));
  return $attr{$dev}{loglevel}
  	if(defined($attr{$dev}) && defined($attr{$dev}{loglevel}));
  return $df;
}


################################################
# the new Log with integrated loglevel checking
sub
Log3($$$)
{
  my ($dev, $loglevel, $text) = @_;
     
  if(defined($dev) &&
     defined($attr{$dev}) &&
     defined (my $devlevel = $attr{$dev}{loglevel})) {
    return if($loglevel > $devlevel);

  } else {
    return if($loglevel > $attr{global}{verbose});

  }

  my ($seconds, $microseconds) = gettimeofday();
  my @t = localtime($seconds);
  my $nfile = ResolveDateWildcards($attr{global}{logfile}, @t);
  OpenLogfile($nfile) if(!$currlogfile || $currlogfile ne $nfile);

  my $tim = sprintf("%04d.%02d.%02d %02d:%02d:%02d",
          $t[5]+1900,$t[4]+1,$t[3], $t[2],$t[1],$t[0]);
  if($attr{global}{mseclog}) {
    $tim .= sprintf(".%03d", $microseconds/1000);
  }

  if($logopened) {
    print LOG "$tim $loglevel: $text\n";
  } else {
    print "$tim $loglevel: $text\n";
  }
  return undef;
}

################################################
sub
Log($$)
{
  my ($loglevel, $text) = @_;
  Log3(undef, $loglevel, $text);
}


#####################################
sub
IOWrite($@)
{
  my ($hash, @a) = @_;

  my $dev = $hash->{NAME};
  return if(IsDummy($dev) || IsIgnored($dev));
  my $iohash = $hash->{IODev};
  if(!$iohash ||
     !$iohash->{TYPE} ||
     !$modules{$iohash->{TYPE}} ||
     !$modules{$iohash->{TYPE}}{WriteFn}) {
    Log 5, "No IO device or WriteFn found for $dev";
    return;
  }

  no strict "refs";
  my $ret = &{$modules{$iohash->{TYPE}}{WriteFn}}($iohash, @a);
  use strict "refs";
  return $ret;
}

#####################################
sub
CommandIOWrite($$)
{
  my ($cl, $param) = @_;
  my @a = split(" ", $param);

  return "Usage: iowrite <iodev> <param> ..." if(int(@a) < 2);

  my $name = shift(@a);
  my $hash = $defs{$name};
  return "$name not found" if(!$hash);
  return undef if(IsDummy($name) || IsIgnored($name));
  if(!$hash->{TYPE} ||
     !$modules{$hash->{TYPE}} ||
     !$modules{$hash->{TYPE}}{WriteFn}) {
    Log 1, "No IO device or WriteFn found for $name";
    return;
  }
  unshift(@a, "") if(int(@a) == 1);
  no strict "refs";
  my $ret = &{$modules{$hash->{TYPE}}{WriteFn}}($hash, @a);
  use strict "refs";
  return $ret;
}


#####################################
# i.e. split a line by ; (escape ;;), and execute each
sub
AnalyzeCommandChain($$)
{
  my ($c, $cmd) = @_;
  my @ret;

  if($cmd =~ m/^[ \t]*(#.*)?$/) {      # Save comments
    if(!$init_done) {
      if($currcfgfile ne AttrVal("global", "statefile", "")) {
        my $nr =  $devcount++;
        $comments{$nr}{TEXT} = $cmd;
        $comments{$nr}{CFGFN} = $currcfgfile
            if($currcfgfile ne AttrVal("global", "configfile", ""));
      }
    }
    return undef;
  }

  $cmd =~ s/#.*$//s;

  $cmd =~ s/;;/SeMiCoLoN/g;
  my @saveCmdList = @cmdList;   # Needed for recursive calls
  @cmdList = split(";", $cmd);
  my $subcmd;
  while(defined($subcmd = shift @cmdList)) {
    $subcmd =~ s/SeMiCoLoN/;/g;
    my $lret = AnalyzeCommand($c, $subcmd);
    push(@ret, $lret) if(defined($lret));
  }
  @cmdList = @saveCmdList;
  $evalSpecials = undef;
  return join("\n", @ret) if(@ret);
  return undef;
}

#####################################
sub
AnalyzePerlCommand($$)
{
  my ($cl, $cmd) = @_;

  $cmd =~ s/\\ *\n/ /g;               # Multi-line

  # Make life easier for oneliners:
  %value = ();
  foreach my $d (keys %defs) {
    $value{$d} = $defs{$d}{STATE}
  }
  my ($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst) = localtime;
  my $we = (($wday==0 || $wday==6) ? 1 : 0);
  if(!$we) {
    my $h2we = $attr{global}{holiday2we};
    $we = 1 if($h2we && $value{$h2we} && $value{$h2we} ne "none");
  }
  $month++;
  $year+=1900;

  if($evalSpecials) {
    $cmd = join("", map { my $n = substr($_,1);
                          my $v = $evalSpecials->{$_};
                          $v =~ s/(['\\])/\\$1/g;
                          "my \$$n='$v';";
                        } keys %{$evalSpecials})
           . $cmd;
    # Normally this is deleted in AnalyzeCommandChain, but ECMDDevice calls us
    # directly, and combining perl with something else isnt allowed anyway.
    $evalSpecials = undef;
  }

  my $ret = eval $cmd;
  $ret = $@ if($@);
  return $ret;
}

sub
AnalyzeCommand($$)
{
  my ($cl, $cmd) = @_;

  $cmd =~ s/^(\\\n|[ \t])*//;# Strip space or \\n at the begginning
  $cmd =~ s/[ \t]*$//;

  Log 5, "Cmd: >$cmd<";
  return undef if(!$cmd);

  if($cmd =~ m/^{.*}$/s) {		# Perl code
    return AnalyzePerlCommand($cl, $cmd);
  }

  if($cmd =~ m/^"(.*)"$/s) { # Shell code in bg, to be able to call us from it
    if($evalSpecials) {
      map { $ENV{substr($_,1)} = $evalSpecials->{$_}; } keys %{$evalSpecials};
    }
    my $out = "";
    $out = ">> $currlogfile 2>&1" if($currlogfile ne "-" && $^O ne "MSWin32");
    system("$1 $out &");
    return undef;
  }

  $cmd =~ s/^[ \t]*//;
  if($evalSpecials) {
    map { my $n = substr($_,1); my $v = $evalSpecials->{$_};
          $cmd =~ s/\$$n/$v/g; } keys %{$evalSpecials};
  }
  my ($fn, $param) = split("[ \t][ \t]*", $cmd, 2);
  return undef if(!$fn);

  #############
  # Search for abbreviation
  if(!defined($cmds{$fn})) {
    foreach my $f (sort keys %cmds) {
      if(length($f) > length($fn) && lc(substr($f,0,length($fn))) eq lc($fn)) {
	Log 5, "$fn => $f";
        $fn = $f;
        last;
      }
    }
  }
  $fn = $cmds{$fn}{ReplacedBy}
                if(defined($cmds{$fn}) && defined($cmds{$fn}{ReplacedBy}));

  #############
  # autoload commands.
  if(!defined($cmds{$fn}) || !defined($cmds{$fn}{Fn})) {
    map { $fn = $_ if(lc($fn) eq lc($_)); } keys %modules;
    $fn = LoadModule($fn);
    $fn = lc($fn) if(defined($cmds{lc($fn)}));
    return "Unknown command $fn, try help." if(!defined($cmds{$fn}));
  }

  if($cl && $cmds{$fn}{ClientFilter} &&
     $cl->{TYPE} !~ m/$cmds{$fn}{ClientFilter}/) {
    return "This command ($fn) is not valid for this input channel.";
  }

  $param = "" if(!defined($param));
  no strict "refs";
  my $ret = &{$cmds{$fn}{Fn} }($cl, $param);
  use strict "refs";
  return undef if(defined($ret) && $ret eq "");
  return $ret;
}

sub
devspec2array($)
{
  my %knownattr = ( "DEF"=>1, "STATE"=>1, "TYPE"=>1 );

  my ($name) = @_;

  return "" if(!defined($name));
  if(defined($defs{$name})) {
    # FHEM2FHEM LOG mode fake device, avoid local set/attr/etc operations on it
    return "FHEM2FHEM_FAKE_$name" if($defs{$name}{FAKEDEVICE});
    return $name;
  }
  # FAKE is set by FHEM2FHEM LOG

  my ($isattr, @ret);

  foreach my $l (split(",", $name)) {   # List

    if($l =~ m/(.*)=(.*)/) {
      my ($lattr,$re) = ($1, $2);
      if($knownattr{$lattr}) {
        eval {                          # a bad regexp may shut down fhem.pl
          foreach my $l (sort keys %defs) {
              push @ret, $l
                if($defs{$l}{$lattr} && (!$re || $defs{$l}{$lattr}=~m/^$re$/));
          }
        };
        if($@) {
          Log 1, "devspec2array $name: $@";
          return $name;
        }
      } else {
        foreach my $l (sort keys %attr) {
          push @ret, $l
            if($attr{$l}{$lattr} && (!$re || $attr{$l}{$lattr} =~ m/$re/));
        }
      }
      $isattr = 1;
      next;
    }

    my $regok;
    eval {                              # a bad regexp may shut down fhem.pl
      if($l =~ m/[*\[\]^\$]/) {         # Regexp
        push @ret, grep($_ =~ m/^$l$/, sort keys %defs);
        $regok = 1;
      }
    };
    if($@) {
      Log 1, "devspec2array $name: $@";
      return $name;
    }
    next if($regok);

    if($l =~ m/-/) {                    # Range
      my ($lower, $upper) = split("-", $l, 2);
      push @ret, grep($_ ge $lower && $_ le $upper, sort keys %defs);
      next;
    }
    push @ret, $l;
  }

  return $name if(!@ret && !$isattr);             # No match, return the input
  @ret = grep { !$attr{$_} || !$attr{$_}{ignore} } @ret
        if($name !~ m/^ignore=/);
  return @ret;
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
    next if(!$cmds{$cmd}{Hlp});
    next if($cl && $cmds{$cmd}{ClientFilter} &&
            $cl->{TYPE} !~ m/$cmds{$cmd}{ClientFilter}/);
    my @a = split(",", $cmds{$cmd}{Hlp}, 2);
    $str .= sprintf("%-9s %-25s %s\n", $cmd, $a[0], $a[1]);
  }
  return $str;
}

#####################################
sub
CommandInclude($$)
{
  my ($cl, $arg) = @_;
  my $fh;
  my @ret;
  my $oldcfgfile;

  if(!open($fh, $arg)) {
    return "Can't open $arg: $!";
  }
  Log 1, "Including $arg";
  if(!$init_done &&
     $arg ne AttrVal("global", "statefile", "") &&
     $arg ne AttrVal("global", "configfile", "")) {
    my $nr =  $devcount++;
    $comments{$nr}{TEXT} = "include $arg";
    $comments{$nr}{CFGFN} = $currcfgfile
          if($currcfgfile ne AttrVal("global", "configfile", ""));
  }
  $oldcfgfile  = $currcfgfile;
  $currcfgfile = $arg;

  my $bigcmd = "";
  $rcvdquit = 0;
  while(my $l = <$fh>) {
    $l =~ s/[\r\n]//g;

    if($l =~ m/^(.*)\\ *$/) {		# Multiline commands
      $bigcmd .= "$1\\\n";
    } else {
      my $tret = AnalyzeCommandChain($cl, $bigcmd . $l);
      push @ret, $tret if(defined($tret));
      $bigcmd = "";
    }
    last if($rcvdquit);

  }
  $currcfgfile = $oldcfgfile;
  close($fh);
  return join("\n", @ret) if(@ret);
  return undef;
}


#####################################
sub
OpenLogfile($)
{
  my $param = shift;

  close(LOG);
  $logopened=0;
  $currlogfile = $param;
  if($currlogfile eq "-") {

    open LOG, '>&STDOUT'    or die "Can't dup stdout: $!";

  } else {

    HandleArchiving($defs{global}) if($defs{global}{currentlogfile});
    $defs{global}{currentlogfile} = $param;
    $defs{global}{logfile} = $attr{global}{logfile};

    open(LOG, ">>$currlogfile") || return("Can't open $currlogfile: $!");
    redirectStdinStdErr() if($init_done);
    
  }
  LOG->autoflush(1);
  $logopened = 1;
  return undef;
}

sub
redirectStdinStdErr()
{
  # Redirect stdin/stderr
  return if(!$currlogfile || $currlogfile eq "-");

  open STDIN,  '</dev/null'      or print "Can't read /dev/null: $!\n";

  close(STDERR);
  open(STDERR, ">>$currlogfile") or print "Can't append STDERR to log: $!\n";
  STDERR->autoflush(1);

  close(STDOUT);
  open STDOUT, '>&STDERR'        or print "Can't dup stdout: $!\n";
  STDOUT->autoflush(1);
}


#####################################
sub
CommandRereadCfg($$)
{
  my ($cl, $param) = @_;
  my $name = ($cl ? $cl->{NAME} : "__anonymous__");
  my $cfgfile = ($param ? $param : $attr{global}{configfile});
  return "Cannot open $cfgfile: $!" if(! -f $cfgfile);

  $attr{global}{configfile} = $cfgfile;
  WriteStatefile();

  $reread_active=1;
  $init_done = 0;
  foreach my $d (sort { $defs{$b}{NR} <=> $defs{$a}{NR} } keys %defs) {
    my $ret = CallFn($d, "UndefFn", $defs{$d}, $d)
        if($name && $name ne $d);
    Log 1, "$d is against deletion ($ret), continuing with rereadcfg anyway"
        if($ret);
    delete $defs{$d};
  }

  %comments = ();
  %defs = ();
  %attr = ();
  %selectlist = ();
  %readyfnlist = ();
  %inform = ();

  doGlobalDef($cfgfile);
  setGlobalAttrBeforeFork($cfgfile);

  my $ret = CommandInclude($cl, $cfgfile);
  if($attr{global}{statefile} && -r $attr{global}{statefile}) {
    my $ret2 = CommandInclude($cl, $attr{global}{statefile});
    $ret = (defined($ret) ? "$ret\n$ret2" : $ret2) if(defined($ret2));
  }
  DoTrigger("global", "REREADCFG", 1);
  $defs{$name} = $selectlist{$name} = $cl if($name && $name ne "__anonymous__");

  $init_done = 1;
  $reread_active=0;
  return $ret;
}

#####################################
sub
CommandQuit($$)
{
  my ($cl, $param) = @_;

  if(!$cl) {
    $rcvdquit = 1;
  } else {
    $cl->{rcvdQuit} = 1;
    return "Bye..." if($cl->{prompt});
  }
  return undef;
}

#####################################
sub
WriteStatefile()
{
  return "No statefile specified" if(!$attr{global}{statefile});
  if(!open(SFH, ">$attr{global}{statefile}")) {
    my $msg = "WriteStateFile: Cannot open $attr{global}{statefile}: $!";
    Log 1, $msg;
    return $msg;
  }

  my $t = localtime;
  print SFH "#$t\n";

  foreach my $d (sort keys %defs) {
    next if($defs{$d}{TEMPORARY});
    print SFH "define $d $defs{$d}{TYPE} $defs{$d}{DEF}\n"
        if($defs{$d}{VOLATILE});

    my $val = $defs{$d}{STATE};
    if(defined($val) &&
       $val ne "unknown" &&
       $val ne "Initialized" &&
       $val ne "???") {
      $val =~ s/;/;;/g;
      print SFH "setstate $d $val\n"
    }

    #############
    # Now the detailed list
    my $r = $defs{$d}{READINGS};
    if($r) {
      foreach my $c (sort keys %{$r}) {

	my $rd = $r->{$c};
	if(!defined($rd->{TIME})) {
	  Log 4, "WriteStatefile $d $c: Missing TIME, using current time";
	  $rd->{TIME} = TimeNow();
	}

        if(!defined($rd->{VAL})) {
	  Log 4, "WriteStatefile $d $c: Missing VAL, setting it to 0";
	  $rd->{VAL} = 0;
        }
        my $val = $rd->{VAL};
        $val =~ s/;/;;/g;
	print SFH "setstate $d $rd->{TIME} $c $val\n";
      }
    }
  }

  close(SFH);
  return "";
}

#####################################
sub
CommandSave($$)
{
  my ($cl, $param) = @_;
  my $ret = "";

  DoTrigger("global", "SAVE", 1);

  WriteStatefile();

  $param = $attr{global}{configfile} if(!$param);
  return "No configfile attribute set and no argument specified" if(!$param);
  if(!open(SFH, ">$param")) {
    return "Cannot open $param: $!";
  }
  my %fh = ("configfile" => *SFH);
  my %skip;

  my %devByNr;
  map { $devByNr{$defs{$_}{NR}} = $_ } keys %defs;

  for(my $i = 0; $i < $devcount; $i++) {

    my ($h, $d);
    if($comments{$i}) {
      $h = $comments{$i};

    } else {
      $d = $devByNr{$i};
      next if(!defined($d) ||
              $defs{$d}{TEMPORARY} || # e.g. WEBPGM connections
              $defs{$d}{VOLATILE});   # e.g at, will be saved to the statefile
      $h = $defs{$d};
    }

    my $cfgfile = $h->{CFGFN} ? $h->{CFGFN} : "configfile";
    my $fh = $fh{$cfgfile};
    if(!$fh) {
      if(!open($fh, ">$cfgfile")) {
        $ret .= "Cannot open $cfgfile: $!, ignoring its content\n";
        $fh{$cfgfile} = 1;
        $skip{$cfgfile} = 1;
      } else {
        $fh{$cfgfile} = $fh;
      }
    }
    next if($skip{$cfgfile});

    if(!defined($d)) {
      print $fh $h->{TEXT},"\n";
      next;
    }

    if($d ne "global") {
      my $def = $defs{$d}{DEF};
      if(defined($def)) {
        $def =~ s/;/;;/g;
        print $fh "define $d $defs{$d}{TYPE} $def\n";
      } else {
        print $fh "define $d $defs{$d}{TYPE}\n";
      }
    }
    foreach my $a (sort keys %{$attr{$d}}) {
      next if($d eq "global" &&
              ($a eq "configfile" || $a eq "version"));
      my $val = $attr{$d}{$a};
      $val =~ s/;/;;/g;
      $val =~ s/\n/\\\n/g;
      print $fh "attr $d $a $val\n";
    }
  }
  print SFH "include $attr{global}{lastinclude}\n"
        if($attr{global}{lastinclude});

  foreach my $fh (values %fh) {
    close($fh) if($fh ne "1");
  }
  return ($ret ? $ret : undef);
}

#####################################
sub
CommandShutdown($$)
{
  my ($cl, $param) = @_;
  DoTrigger("global", "SHUTDOWN", 1);
  Log 0, "Server shutdown";

  foreach my $d (sort keys %defs) {
    CallFn($d, "ShutdownFn", $defs{$d});
  }

  WriteStatefile();
  unlink($attr{global}{pidfilename}) if($attr{global}{pidfilename});
  if($param && $param eq "restart") {
    system("(sleep 2; exec $^X $0 $attr{global}{configfile})&");
  }
  exit(0);
}

#####################################
sub
DoSet(@)
{
  my @a = @_;

  my $dev = $a[0];
  my $hash = $defs{$dev};
  return "Please define $dev first" if(!$hash);
  return "Bogus entry $dev without TYPE" if(!$hash->{TYPE});
  return "No set implemented for $dev" if(!$modules{$hash->{TYPE}}{SetFn});

  # No special handling needed fo the Usage check
  return CallFn($dev, "SetFn", $hash, @a) if($a[1] && $a[1] eq "?");

  @a = ReplaceEventMap($dev, \@a, 0) if($attr{$dev}{eventMap});
  $hash->{".triggerUsed"} = 0; 
  my ($ret, $skipTrigger) = CallFn($dev, "SetFn", $hash, @a);
  return $ret if($ret);
  return undef if($skipTrigger);

  # Backward compatibility. Use readingsUpdate in SetFn now
  # case: DoSet is called from a notify triggered by DoSet with same dev
  if(defined($hash->{".triggerUsed"}) && $hash->{".triggerUsed"} == 0) {
    shift @a;
    # set arg if the module did not triggered events
    my $arg = join(" ", @a) if(!$hash->{CHANGED} || !int(@{$hash->{CHANGED}}));
    DoTrigger($dev, $arg, 0);
  }
  delete($hash->{".triggerUsed"});

  return undef;
}


#####################################
sub
CommandSet($$)
{
  my ($cl, $param) = @_;
  my @a = split("[ \t][ \t]*", $param);
  return "Usage: set <name> <type-dependent-options>\n$namedef" if(int(@a)<1);

  my @rets;
  foreach my $sdev (devspec2array($a[0])) {

    $a[0] = $sdev;
    my $ret = DoSet(@a);
    push @rets, $ret if($ret);

  }
  return join("\n", @rets);
}


#####################################
sub
CommandGet($$)
{
  my ($cl, $param) = @_;

  my @a = split("[ \t][ \t]*", $param);
  return "Usage: get <name> <type-dependent-options>\n$namedef" if(int(@a) < 1);


  my @rets;
  foreach my $sdev (devspec2array($a[0])) {
    if(!defined($defs{$sdev})) {
      push @rets, "Please define $sdev first";
      next;
    }
    if(!$modules{$defs{$sdev}{TYPE}}{GetFn}) {
      push @rets, "No get implemented for $sdev";
      next;
    }

    $a[0] = $sdev;
    my $ret = CallFn($sdev, "GetFn", $defs{$sdev}, @a);
    push @rets, $ret if(defined($ret) && $ret ne "");
  }
  return join("\n", @rets);
}

#####################################
sub
LoadModule($)
{
  my ($m) = @_;

  if($modules{$m} && !$modules{$m}{LOADED}) {   # autoload
    my $o = $modules{$m}{ORDER};
    my $ret = CommandReload(undef, "${o}_$m");
    if($ret) {
      Log 0, $ret;
      return "UNDEFINED";
    }

    if(!$modules{$m}{LOADED}) {                 # Case corrected by reload?
      foreach my $i (keys %modules) {
        if(uc($m) eq uc($i) && $modules{$i}{LOADED}) {
          delete($modules{$m});
          $m = $i;
          last;
        }
      }
    }
  }
  return $m;
}

#####################################
sub
CommandDefine($$)
{
  my ($cl, $def) = @_;
  my @a = split("[ \t][ \t]*", $def, 3);
  my $name = $a[0];
  return "Usage: define <name> <type> <type dependent arguments>"
  					if(int(@a) < 2);
  return "$name already defined, delete it first" if(defined($defs{$name}));
  return "Invalid characters in name (not A-Za-z0-9.:_): $name"
                        if($name !~ m/^[a-z0-9.:_]*$/i);

  my $m = $a[1];
  if(!$modules{$m}) {                           # Perhaps just wrong case?
    foreach my $i (keys %modules) {
      if(uc($m) eq uc($i)) {
        $m = $i;
        last;
      }
    }
  }

  my $newm = LoadModule($m);
  return "Cannot load module $m" if($newm eq "UNDEFINED");
  $m = $newm;

  if(!$modules{$m} || !$modules{$m}{DefFn}) {
    my @m = grep { $modules{$_}{DefFn} || !$modules{$_}{LOADED} }
                sort keys %modules;
    return "Unknown module $m, choose one of @m";
  }

  my %hash;

  $hash{NAME}  = $name;
  $hash{TYPE}  = $m;
  $hash{STATE} = "???";
  $hash{DEF}   = $a[2] if(int(@a) > 2);
  $hash{NR}    = $devcount++;
  $hash{CFGFN} = $currcfgfile
        if($currcfgfile ne AttrVal("global", "configfile", ""));

  # If the device wants to issue initialization gets/sets, then it needs to be
  # in the global hash.
  $defs{$name} = \%hash;

  my $ret = CallFn($name, "DefFn", \%hash, $def);
  if($ret) {
    Log 1, "define: $ret";
    delete $defs{$name};                            # Veto
    delete $attr{$name};

  } else {
    foreach my $da (sort keys (%defaultattr)) {     # Default attributes
      CommandAttr($cl, "$name $da $defaultattr{$da}");
    }
    DoTrigger("global", "DEFINED $name", 1) if($init_done);

    if($modules{$m}{NotifyFn} && !$hash{NTFY_ORDER}) {
      $hash{NTFY_ORDER} = ($modules{$m}{NotifyOrderPrefix} ?
                $modules{$m}{NotifyOrderPrefix} : "50-") . $name;
    }

  }
  return $ret;
}

#####################################
sub
CommandModify($$)
{
  my ($cl, $def) = @_;
  my @a = split("[ \t]+", $def, 2);

  return "Usage: modify <name> <type dependent arguments>"
  					if(int(@a) < 1);

  # Return a list of modules
  return "Define $a[0] first" if(!defined($defs{$a[0]}));
  my $hash = $defs{$a[0]};

  $hash->{OLDDEF} = $hash->{DEF};
  $hash->{DEF} = $a[1];
  my $ret = CallFn($a[0], "DefFn", $hash,
        "$a[0] $hash->{TYPE}".(defined($a[1]) ? " $a[1]" : ""));
  $hash->{DEF} = $hash->{OLDDEF} if($ret);
  delete($hash->{OLDDEF});
  return $ret;
}

#############
# internal
sub
AssignIoPort($)
{
  my ($hash) = @_;

  # Set the I/O device, search for the last compatible one.
  for my $p (sort { $defs{$b}{NR} <=> $defs{$a}{NR} } keys %defs) {

    my $cl = $defs{$p}{Clients};
    $cl = $modules{$defs{$p}{TYPE}}{Clients} if(!$cl);

    if($cl && $defs{$p}{NAME} ne $hash->{NAME}) {      # e.g. RFR
      my @fnd = grep { $hash->{TYPE} =~ m/^$_$/; } split(":", $cl);
      if(@fnd) {
        $hash->{IODev} = $defs{$p};
        delete($defs{$p}{".clientArray"}); # Force a recompute
        last;
      }
    }
  }
  Log 3, "No I/O device found for $hash->{NAME}" if(!$hash->{IODev});
}


#############
sub
CommandDelete($$)
{
  my ($cl, $def) = @_;
  return "Usage: delete <name>$namedef\n" if(!$def);

  my @rets;
  foreach my $sdev (devspec2array($def)) {
    if(!defined($defs{$sdev})) {
      push @rets, "Please define $sdev first";
      next;
    }

    my $ret = CallFn($sdev, "UndefFn", $defs{$sdev}, $sdev);
    if($ret) {
      push @rets, $ret;
      next;
    }
    $ret = CallFn($sdev, "DeleteFn", $defs{$sdev}, $sdev);
    if($ret) {
      push @rets, $ret;
      next;
    }

    # Delete releated hashes
    foreach my $p (keys %selectlist) {
      if($selectlist{$p} && $selectlist{$p}{NAME} eq $sdev) {
        delete $selectlist{$p};
      }
    }
    foreach my $p (keys %readyfnlist) {
      delete $readyfnlist{$p}
        if($readyfnlist{$p} && $readyfnlist{$p}{NAME} eq $sdev);
    }

    delete($attr{$sdev});
    my $temporary = $defs{$sdev}{TEMPORARY};
    delete($defs{$sdev});       # Remove the main entry
    DoTrigger("global", "DELETED $sdev", 1) if(!$temporary);

  }
  return join("\n", @rets);
}

#############
sub
CommandDeleteAttr($$)
{
  my ($cl, $def) = @_;

  my @a = split(" ", $def, 2);
  return "Usage: deleteattr <name> [<attrname>]\n$namedef" if(@a < 1);

  my @rets;
  foreach my $sdev (devspec2array($a[0])) {

    if(!defined($defs{$sdev})) {
      push @rets, "Please define $sdev first";
      next;
    }

    $a[0] = $sdev;
    
    if($a[1] eq "userReadings") {
      delete($defs{$sdev}{'.userReadings'});
    }

    $ret = CallFn($sdev, "AttrFn", "del", @a);
    if($ret) {
      push @rets, $ret;
      next;
    }

    if(@a == 1) {
      delete($attr{$sdev});
    } else {
      delete($attr{$sdev}{$a[1]}) if(defined($attr{$sdev}));
    }

  }

  return join("\n", @rets);
}

#############
sub
CommandDisplayAttr($$)
{
  my ($cl, $def) = @_;

  my @a = split(" ", $def, 2);
  return "Usage: displayattr <name> [<attrname>]\n$namedef" if(@a < 1);

  my @rets;
  my @devspec = devspec2array($a[0]);

  foreach my $sdev (@devspec) {

    if(!defined($defs{$sdev})) {
      push @rets, "Please define $sdev first";
      next;
    }

    my $ap = $attr{$sdev};
    next if(!$ap);
    my $d = (@devspec > 1 ? "$sdev " : "");

    if(defined($a[1])) {
      push @rets, "$d$ap->{$a[1]}" if(defined($ap->{$a[1]}));

    } else {
      push @rets, map { "$d$_ $ap->{$_}" } sort keys %{$ap};

    }

  }

  return join("\n", @rets);
}

#############
sub
CommandDeleteReading($$)
{
  my ($cl, $def) = @_;

  my @a = split(" ", $def, 2);
  return "Usage: deletereading <name> <reading>\n$namedef" if(@a != 2);

  my @rets;
  foreach my $sdev (devspec2array($a[0])) {

    if(!defined($defs{$sdev})) {
      push @rets, "Please define $sdev first";
      next;
    }

    $a[0] = $sdev;
    my $readingspec= '^' . $a[1] . '$';

    foreach my $reading (grep { /$readingspec/ }
                                keys %{$defs{$sdev}{READINGS}} ) {
      delete($defs{$sdev}{READINGS}{$reading});
      push @rets, "Deleted reading $reading for device $sdev";
    }
    
  }

  return join("\n", @rets);
}

#############
sub
PrintHash($$)
{
  my ($h, $lev) = @_;
  my $si = AttrVal("global", "showInternalValues", 0);
  return "" if($h->{".visited"});
  $h->{".visited"} = 1;

  my ($str,$sstr) = ("","");
  foreach my $c (sort keys %{$h}) {
    next if(!$si && $c =~ m/^\./ || $c eq ".visited");
    if(ref($h->{$c})) {
      if(ref($h->{$c}) eq "HASH") {
        if(defined($h->{$c}{TIME}) && defined($h->{$c}{VAL})) {
          $str .= sprintf("%*s %-19s   %-15s %s\n",
                          $lev," ", $h->{$c}{TIME},$c,$h->{$c}{VAL});
        } elsif($c eq "IODev" || $c eq "HASH") {
          $str .= sprintf("%*s %-10s %s\n", $lev," ",$c, $h->{$c}{NAME});

        } else {
          $sstr .= sprintf("%*s %s:\n",
                          $lev, " ", uc(substr($c,0,1)).lc(substr($c,1)));
          $sstr .= PrintHash($h->{$c}, $lev+2);
        }
      } elsif(ref($h->{$c}) eq "ARRAY") {
         $sstr .= sprintf("%*s %s:\n", $lev, " ", $c);
         foreach my $v (@{$h->{$c}}) {
           $sstr .= sprintf("%*s %s\n", $lev+2, " ", $v);
         }
      }
    } else {
      my $v = $h->{$c};
      $str .= sprintf("%*s %-10s %s\n", $lev," ",$c, defined($v) ? $v : "");
    }
  }
  delete $h->{".visited"};
  return $str . $sstr;
}

#####################################
sub
CommandList($$)
{
  my ($cl, $param) = @_;
  my $str = "";

  if(!$param) { # List of all devices

    $str = "\nType list <name> for detailed info.\n";
    my $lt = "";

    # Sort first by type then by name
    for my $d (sort { my $x=$modules{$defs{$a}{TYPE}}{ORDER}.$defs{$a}{TYPE} cmp
		  	    $modules{$defs{$b}{TYPE}}{ORDER}.$defs{$b}{TYPE};
		         $x=($a cmp $b) if($x == 0); $x; } keys %defs) {
      next if(IsIgnored($d));
      my $t = $defs{$d}{TYPE};
      $str .= "\n$t:\n" if($t ne $lt);
      $str .= sprintf("  %-20s (%s)\n", $d, $defs{$d}{STATE});
      $lt = $t;
    }

  } else { # devspecArray

    my @arg = split(" ", $param);
    my @list = devspec2array($arg[0]);
    if($arg[1]) {
      foreach my $sdev (@list) { # Show a Hash-Entry or Reading for each device

        if($defs{$sdev} &&
           $defs{$sdev}{$arg[1]}) {
          $str .= $sdev . " " .
                  $defs{$sdev}{$arg[1]} . "\n";

        } elsif($defs{$sdev} &&
           $defs{$sdev}{READINGS} &&
           $defs{$sdev}{READINGS}{$arg[1]}) {
          $str .= $sdev . " ".
                  $defs{$sdev}{READINGS}{$arg[1]}{TIME} . " " .
                  $defs{$sdev}{READINGS}{$arg[1]}{VAL} . "\n";
        }
      }

    } elsif(@list == 1) { # Details
      my $sdev = $list[0];
      if(!defined($defs{$sdev})) {
        $str .= "No device named $param found";
      } else {
        $str .= "Internals:\n";
        $str .= PrintHash($defs{$sdev}, 2);
        $str .= "Attributes:\n";
        $str .= PrintHash($attr{$sdev}, 2);
      }

    } else {
      foreach my $sdev (@list) {         # List of devices
        $str .= "$sdev\n";
      }

    }
  }

  return $str;
}


#####################################
sub
CommandReload($$)
{
  my ($cl, $param) = @_;
  my %hash;
  $param =~ s,/,,g;
  $param =~ s,\.pm$,,g;
  my $file = "$attr{global}{modpath}/FHEM/$param.pm";
  return "Can't read $file: $!" if(! -r "$file");

  my $m = $param;
  $m =~ s,^([0-9][0-9])_,,;
  my $order = (defined($1) ? $1 : "00");
  Log 5, "Loading $file";

  no strict "refs";
  my $ret = eval {
    my $ret=do "$file";
    if(!$ret) {
      Log 1, "reload: Error:Modul $param deactivated:\n $@";
      return $@;
    }

    # Get the name of the initialize function. This may differ from the
    # filename as sometimes we live on a FAT fs with wrong case.
    my $fnname = $m;
    foreach my $i (keys %main::) {
      if($i =~ m/^(${m})_initialize$/i) {
        $fnname = $1;
        last;
      }
    }
    &{ "${fnname}_Initialize" }(\%hash);
    $m = $fnname;
    return undef;
  };
  use strict "refs";

  return "$@" if($@);
  return $ret if($ret);

  my ($defptr, $ldata);
  if($modules{$m}) {
    $defptr = $modules{$m}{defptr};
    $ldata = $modules{$m}{ldata};
  }
  $modules{$m} = \%hash;
  $modules{$m}{ORDER} = $order;
  $modules{$m}{LOADED} = 1;
  $modules{$m}{defptr} = $defptr if($defptr);
  $modules{$m}{ldata} = $defptr if($ldata);

  return undef;
}

#####################################
sub
CommandRename($$)
{
  my ($cl, $param) = @_;
  my ($old, $new) = split(" ", $param);

  return "old name is empty" if(!defined($old));
  return "new name is empty" if(!defined($new));

  return "Please define $old first" if(!defined($defs{$old}));
  return "$new already defined" if(defined($defs{$new}));
  return "Invalid characters in name (not A-Za-z0-9.:_): $new"
                        if($new !~ m/^[a-z0-9.:_]*$/i);
  return "Cannot rename global" if($old eq "global");

  $defs{$new} = $defs{$old};
  $defs{$new}{NAME} = $new;
  delete($defs{$old});          # The new pointer will preserve the hash

  $attr{$new} = $attr{$old} if(defined($attr{$old}));
  delete($attr{$old});

  $oldvalue{$new} = $oldvalue{$old} if(defined($oldvalue{$old}));
  delete($oldvalue{$old});

  CallFn($new, "RenameFn", $new,$old);# ignore replies

  DoTrigger("global", "RENAMED $old $new", 1);
  return undef;
}

#####################################
sub
getAllAttr($)
{
  my $d = shift;
  return "" if(!$defs{$d});

  my $list = $AttrList;
  $list .= " " . $modules{$defs{$d}{TYPE}}{AttrList}
        if($modules{$defs{$d}{TYPE}}{AttrList});
  $list .= " " . $attr{global}{userattr}
        if($attr{global}{userattr});
  return $list;
}

#####################################
sub
getAllGets($)
{
  my $d = shift;
  
  my $a2 = CommandGet(undef, "$d ?");
  return "" if($a2 !~ m/unknown.*choose one of /i);
  $a2 =~ s/.*choose one of //;
  return $a2;
}

#####################################
sub
getAllSets($)
{
  my $d = shift;
  
  if(AttrVal("global", "apiversion", 1)> 1) {
    my @setters= getSetters($defs{$d});
    return join(" ", @setters);
  }

  my $a2 = CommandSet(undef, "$d ?");
  $a2 =~ s/.*choose one of //;
  $a2 = "" if($a2 =~ /^No set implemented for/);
  return "" if($a2 eq "");

  my $em = AttrVal($d, "eventMap", undef);
  if($em) {
    # Delete the first word of the translation (.*:), else it will be
    # interpreted as the single possible value for a dropdown
    # Why is the .*= deleted?
    $em = join(" ", grep { !/ / }
                    map { $_ =~ s/.*?=//s;
                          $_ =~ s/.*?://s; $_ } 
                    EventMapAsList($em));
    $a2 = "$em $a2";
  }
  return $a2;
}

sub
GlobalAttr($$)
{
  my ($type, $me, $name, $val) = @_;

  return if($type ne "set");
  ################
  if($name eq "logfile") {
    my @t = localtime;
    my $ret = OpenLogfile(ResolveDateWildcards($val, @t));
    if($ret) {
      return $ret if($init_done);
      die($ret);
    }
  }

  ################
  elsif($name eq "verbose") {
    if($val =~ m/^[0-5]$/) {
      return undef;
    } else {
      $attr{global}{verbose} = 3;
      return "Valid value for verbose are 0,1,2,3,4,5";
    }
  }

  elsif($name eq "modpath") {
    return "modpath must point to a directory where the FHEM subdir is"
        if(! -d "$val/FHEM");
    my $modpath = "$val/FHEM";

    opendir(DH, $modpath) || return "Can't read $modpath: $!";
    push @INC, $modpath if(!grep(/$modpath/, @INC));
    eval { 
      use vars qw($DISTRIB_DESCRIPTION);
      # start of fix
      # "Use of uninitialized value" after a fresh 5.2 installation and first
      # time "updatefhem" release.pm does not reside in FhemUtils (what it
      # should), so we load it from $modpath
      if(-e "$modpath/FhemUtils/release.pm") {
        require "FhemUtils/release.pm";
      } elsif(-e "$modpath/release.pm") {
        require "release.pm";
      } else {
        $DISTRIB_DESCRIPTION = "unknown";
      }
      # end of fix
      $attr{global}{version} = "$DISTRIB_DESCRIPTION, $cvsid";
    };
    my $counter = 0;

    foreach my $m (sort readdir(DH)) {
      next if($m !~ m/^([0-9][0-9])_(.*)\.pm$/);
      $modules{$2}{ORDER} = $1;
      CommandReload(undef, $m)                  # Always load utility modules
         if($1 eq "99" && !$modules{$2}{LOADED});
      $counter++;
    }
    closedir(DH);

    if(!$counter) {
      return "No modules found, set modpath to a directory in which a " .
             "subdirectory called \"FHEM\" exists wich in turn contains " .
             "the fhem module files <*>.pm";
    }


  }

  return undef;
}

#####################################
sub
CommandAttr($$)
{
  my ($cl, $param) = @_;
  my $ret = undef;
  my @a;

  @a = split(" ", $param, 3) if($param);

  return "Usage: attr <name> <attrname> [<attrvalue>]\n$namedef"
           if(@a && @a < 2);

  my @rets;
  foreach my $sdev (devspec2array($a[0])) {

    my $hash =  $defs{$sdev};
    if(!defined($hash)) {
      push @rets, "Please define $sdev first";
      next;
    }

    my $list = getAllAttr($sdev);
    if($a[1] eq "?") {
      push @rets, "$sdev: unknown attribute $a[1], choose one of $list";
      next;
    }

    if(" $list " !~ m/ ${a[1]}[ :;]/) {
       my $found = 0;
       foreach my $atr (split("[ \t]", $list)) { # is it a regexp?
         if(${a[1]} =~ m/^$atr$/) {
           $found++;
           last;
         }
      }
      if(!$found) {
        push @rets, "$sdev: unknown attribute $a[1], ".
                        "choose one of $list or use attr global userattr $a[1]";
        next;
      }
    }

    if($a[1] eq "userReadings") {

      my %userReadings;
      # myReading1[:trigger1] [modifier1] { codecodecode1 }, ...
      my $arg= $a[2];

      # matches myReading1[:trigger2] { codecode1 }
      my $regexi= '\s*(\w+)(:\S*)?\s+((\w+)\s+)?({.*?})\s*';
      my $regexo= '^(' . $regexi . ')(,\s*(.*))*$';

      #Log 1, "arg is $arg";

      while($arg =~ /$regexo/) {
        my $userReading= $2;
        my $trigger= $3 ? $3 : undef;
        my $modifier= $5 ? $5 : "none";
        my $perlCode= $6;
        #Log 1, sprintf("userReading %s has perlCode %s with modifier %s%s",
        # $userReading,$perlCode,$modifier,$trigger?" and trigger $trigger":"");
        if(grep { /$modifier/ } qw(none difference differential offset monotonic)) {
          $trigger =~ s/^:// if($trigger);
          $userReadings{$userReading}{trigger}= $trigger;
          $userReadings{$userReading}{modifier}= $modifier;
          $userReadings{$userReading}{perlCode}= $perlCode;
        } else {
          push @rets, "$sdev: unknown modifier $modifier for ".
                "userReading $userReading, this userReading will be ignored";
        }
        $arg= defined($8) ? $8 : "";
      }
      $hash->{'.userReadings'}= \%userReadings;
    } 

    if($a[1] eq "IODev" && (!$a[2] || !defined($defs{$a[2]}))) {
      push @rets,"$sdev: unknown IODev specified";
      next;
    }

    $a[0] = $sdev;
    $ret = CallFn($sdev, "AttrFn", "set", @a);
    if($ret) {
      push @rets, $ret;
      next;
    }

    if(defined($a[2])) {
      $attr{$sdev}{$a[1]} = $a[2];
    } else {
      $attr{$sdev}{$a[1]} = "1";
    }
    if($a[1] eq "IODev") {
      my $ioname = $a[2];
      $hash->{IODev} = $defs{$ioname};
      $hash->{NR} = $devcount++
        if($defs{$ioname}{NR} > $hash->{NR});
    }
    if($a[1] eq "stateFormat" && $init_done) {
      evalStateFormat($hash);
    }

  }
  Log 3, join(" ", @rets) if(!$cl && @rets);
  return join("\n", @rets);
}


#####################################
# Default Attr
sub
CommandDefaultAttr($$)
{
  my ($cl, $param) = @_;

  my @a = split(" ", $param, 2);
  if(int(@a) == 0) {
    %defaultattr = ();
  } elsif(int(@a) == 1) {
    $defaultattr{$a[0]} = 1;
  } else {
    $defaultattr{$a[0]} = $a[1];
  }
  return undef;
}

#####################################
sub
CommandSetstate($$)
{
  my ($cl, $param) = @_;

  my @a = split(" ", $param, 2);
  return "Usage: setstate <name> <state>\n$namedef" if(@a != 2);

  my @rets;
  foreach my $sdev (devspec2array($a[0])) {
    if(!defined($defs{$sdev})) {
      push @rets, "Please define $sdev first";
      next;
    }

    my $d = $defs{$sdev};

    # Detailed state with timestamp
    if($a[1] =~ m/^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) +([^ ].*)$/) {
      my ($tim, $nameval) =  ($1, $2);
      my ($sname, $sval) = split(" ", $nameval, 2);
      (undef, $sval) = ReplaceEventMap($sdev, [$sdev, $sval], 0)
                                if($attr{$sdev}{eventMap});
      my $ret = CallFn($sdev, "StateFn", $d, $tim, $sname, $sval);
      if($ret) {
        push @rets, $ret;
        next;
      }

      if(!$d->{READINGS}{$sname} || $d->{READINGS}{$sname}{TIME} lt $tim) {
        $d->{READINGS}{$sname}{VAL} = $sval;
        $d->{READINGS}{$sname}{TIME} = $tim;
      }

    } else {

      # The timestamp is not the correct one, but we do not store a timestamp for
      # this reading.
      my $tn = TimeNow();
      $oldvalue{$sdev}{TIME} = $tn;
      $oldvalue{$sdev}{VAL} = ($init_done ? $d->{STATE} : $a[1]);

      # Do not overwrite state like "opened" or "initialized"
      $d->{STATE} = $a[1] if($init_done || $d->{STATE} eq "???");
      my $ret = CallFn($sdev, "StateFn", $d, $tn, "STATE", $a[1]);
      if($ret) {
        push @rets, $ret;
        next;
      }

    }
  }
  return join("\n", @rets);
}

#####################################
sub
CommandTrigger($$)
{
  my ($cl, $param) = @_;

  my ($dev, $state) = split(" ", $param, 2);
  return "Usage: trigger <name> <state>\n$namedef" if(!$dev);
  $state = "" if(!defined($state));

  my @rets;
  foreach my $sdev (devspec2array($dev)) {
    if(!defined($defs{$sdev})) {
      push @rets, "Please define $sdev first";
      next;
    }
    my $ret = DoTrigger($sdev, $state);
    if($ret) {
      push @rets, $ret;
      next;
    }
  }
  return join("\n", @rets);
}

#####################################
sub
CommandInform($$)
{
  my ($cl, $param) = @_;

  return if(!$cl);
  my $name = $cl->{NAME};

  return "Usage: inform {on|timer|raw|off} [regexp]"
        if($param !~ m/^(on|off|raw|timer)/);

  delete($inform{$name});
  if($param !~ m/^off/) {
    my ($type, $regexp) = split(" ", $param);
    $inform{$name}{NR} = $cl->{NR};
    $inform{$name}{type} = $type;
    if($regexp) {
      eval { "Hallo" =~ m/$regexp/ };
      return "Bad regexp: $@" if($@);
      $inform{$name}{regexp} = $regexp;
    }
    Log 4, "Setting inform to $param";

  }

  return undef;
}

#####################################
sub
WakeUpFn($)
{
  my $h = shift;
  $evalSpecials = $h->{evalSpecials};
  my $ret = AnalyzeCommandChain(undef, $h->{cmd});
  Log 2, "After sleep: $ret" if($ret && !$h->{quiet});
}


sub
CommandSleep($$)
{
  my ($cl, $param) = @_;
  my ($sec, $quiet) = split(" ", $param);

  return "Argument missing" if(!defined($sec));
  return "Cannot interpret $sec as seconds" if($sec !~ m/^[0-9\.]+$/);
  return "Second parameter must be quiet" if($quiet && $quiet ne "quiet");

  Log 4, "sleeping for $sec";

  if(!$cl && @cmdList && $sec && $init_done) {
    my %h = (cmd          => join(";", @cmdList),
             evalSpecials => $evalSpecials,
             quiet        => $quiet);
    InternalTimer(gettimeofday()+$sec, "WakeUpFn", \%h, 0);
    @cmdList=();

  } else {
    select(undef, undef, undef, $sec);

  }
  return undef;
}

#####################################
sub
CommandVersion($$)
{
  my ($cl, $param) = @_;

  my @ret = ("# $cvsid");
  foreach my $m (sort keys %modules) {
    next if(!$modules{$m}{LOADED} || $modules{$m}{ORDER} < 0);
    my $fn = "$attr{global}{modpath}/FHEM/".$modules{$m}{ORDER}."_$m.pm";
    if(!open(FH, $fn)) {
      push @ret, "$fn: $!";
    } else {
      push @ret, map { chomp; $_ } grep(/# \$Id:/, <FH>);
    }
  }
  if($param) {
    return join("\n", grep /$param/, @ret);
  } else {
    return join("\n", @ret);
  }
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

  $now += 0.01;# need to cover min delay at least
  $nextat = 0;
  #############
  # Check the internal list.
  foreach my $i (sort { $intAt{$a}{TRIGGERTIME} <=>
                        $intAt{$b}{TRIGGERTIME} } keys %intAt) {
    my $tim = $intAt{$i}{TRIGGERTIME};
    my $fn = $intAt{$i}{FN};
    if(!defined($tim) || !defined($fn)) {
      delete($intAt{$i});
      next;
    } elsif($tim <= $now) {
      no strict "refs";
      &{$fn}($intAt{$i}{ARG});
      use strict "refs";
      delete($intAt{$i});
    } else {
      $nextat = $tim if(!$nextat || $nextat > $tim);
	}
  }

  return undef if(!$nextat);
  $now = gettimeofday(); # possibly some tasks did timeout in the meantime
                         # we will cover them 
  return ($now+ 0.01 < $nextat) ? ($nextat-$now) : 0.01;
}


#####################################
sub
InternalTimer($$$$)
{
  my ($tim, $fn, $arg, $waitIfInitNotDone) = @_;

  if(!$init_done && $waitIfInitNotDone) {
    select(undef, undef, undef, $tim-gettimeofday());
    no strict "refs";
    &{$fn}($arg);
    use strict "refs";
    return;
  }
  $intAt{$intAtCnt}{TRIGGERTIME} = $tim;
  $intAt{$intAtCnt}{FN} = $fn;
  $intAt{$intAtCnt}{ARG} = $arg;
  $intAtCnt++;
  $nextat = $tim if(!$nextat || $nextat > $tim);
}

#####################################
sub
RemoveInternalTimer($)
{
  my ($arg) = @_;
  foreach my $a (keys %intAt) {
    delete($intAt{$a}) if($intAt{$a}{ARG} eq $arg);
  }
}

#####################################
sub
SignalHandling()
{
  if($^O ne "MSWin32") {
    $SIG{'INT'}  = sub { $sig_term = 1; };
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
  return FmtDateTime(time());
}

#####################################
sub
FmtDateTime($)
{
  my @t = localtime(shift);
  return sprintf("%04d-%02d-%02d %02d:%02d:%02d",
      $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0]);
}

sub
FmtTime($)
{
  my @t = localtime(shift);
  return sprintf("%02d:%02d:%02d", $t[2], $t[1], $t[0]);
}

#####################################
sub
CommandChain($$)
{
  my ($retry, $list) = @_;
  my $ov = $attr{global}{verbose};
  my $oid = $init_done;

  $init_done = 0;       # Rudi: ???
  $attr{global}{verbose} = 1;
  foreach my $cmd (@{$list}) {
    for(my $n = 0; $n < $retry; $n++) {
      Log 1, sprintf("Trying again $cmd (%d out of %d)", $n+1,$retry) if($n>0);
      my $ret = AnalyzeCommand(undef, $cmd);
      last if(!defined($ret) || $ret !~ m/Timeout/);
    }
  }
  $attr{global}{verbose} = $ov;
  $init_done = $oid;
}

#####################################
sub
ResolveDateWildcards($@)
{
  use POSIX qw(strftime);

  my ($f, @t) = @_;
  return $f if(!$f);
  return $f if($f !~ m/%/);	# Be fast if there is no wildcard
  $f =~ s/%L/$attr{global}{logdir}/g if($attr{global}{logdir}); #log directory
  return strftime($f,@t);
}

sub
SemicolonEscape($)
{
  my $cmd = shift;
  $cmd =~ s/^[ \t]*//;
  $cmd =~ s/[ \t]*$//;
  if($cmd =~ m/^{.*}$/s || $cmd =~ m/^".*"$/s) {
    $cmd =~ s/;/;;/g
  }
  return $cmd;
}

sub
EvalSpecials($%)
{
  # The character % will be replaced with the received event,
  #     e.g. with on or off or measured-temp: 21.7 (Celsius)
  # The character @ will be replaced with the device name.
  # To use % or @ in the text itself, use the double mode (%% or @@).
  # Instead of % and @, the parameters %EVENT (same as %),
  #     %NAME (same as @) and %TYPE (contains the device type, e.g. FHT)
  #     can be used. A single % looses its special meaning if any of these
  #     parameters appears in the definition.
  my ($exec, %specials)= @_;
  $exec = SemicolonEscape($exec);

  # %EVTPART due to HM remote logic
  my $idx = 0;
  if(defined($specials{"%EVENT"})) {
    foreach my $part (split(" ", $specials{"%EVENT"})) {
      $specials{"%EVTPART$idx"} = $part;
      $idx++;
    }
  }

  my $re = join("|", keys %specials);
  $re =~ s/%//g;
  if($exec =~ m/\$($re)\b/) {
    $evalSpecials = \%specials;
    return $exec;
  }

  $exec =~ s/%%/____/g;


  # perform macro substitution
  my $extsyntax= 0;
  foreach my $special (keys %specials) {
    $extsyntax+= ($exec =~ s/$special/$specials{$special}/g);
  }
  if(!$extsyntax) {
    $exec =~ s/%/$specials{"%EVENT"}/g;
  }
  $exec =~ s/____/%/g;

  $exec =~ s/@@/____/g;
  $exec =~ s/@/$specials{"%NAME"}/g;
  $exec =~ s/____/@/g;

  return $exec;
}

#####################################
# Parse a timespec: Either HH:MM:SS or HH:MM or { perfunc() }
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
    $tspec = AnalyzeCommand(undef, "{$fn}");
    if(!$@ && $tspec =~ m/^([0-9]+):([0-5][0-9]):([0-5][0-9])$/) {
      ($hr, $min, $sec) = ($1, $2, $3);
    } elsif(!$@ && $tspec =~ m/^([0-9]+):([0-5][0-9])$/) {
      ($hr, $min, $sec) = ($1, $2, 0);
    } else {
      $tspec = "<empty string>" if(!$tspec);
      return ("the at function \"$fn\" must return a timespec and not $tspec.",
      		undef, undef, undef, undef);
    }
  } else {
    return ("Wrong timespec $tspec: either HH:MM:SS or {perlcode}",
    		undef, undef, undef, undef);
  }
  return (undef, $hr, $min, $sec, $fn);
}


#####################################
# Do the notification
sub
DoTrigger($$@)
{
  my ($dev, $newState, $noreplace) = @_;
  my $ret = "";
  my $hash = $defs{$dev};
  return "" if(!defined($hash));

  $hash->{".triggerUsed"} = 1 if(defined($hash->{".triggerUsed"}));
  if(defined($newState)) {
    if($hash->{CHANGED}) {
      push @{$hash->{CHANGED}}, $newState;
    } else {
      $hash->{CHANGED}[0] = $newState;
    }
  } elsif(!defined($hash->{CHANGED})) {
    return "";
  }

  if(!$noreplace) {     # Backward compatibility for code without readingsUpdate
    if($attr{$dev}{eventMap}) {
      my $c = $hash->{CHANGED};
      for(my $i = 0; $i < @{$c}; $i++) {
        $c->[$i] = ReplaceEventMap($dev, $c->[$i], 1);
      }
      $hash->{STATE} = ReplaceEventMap($dev, $hash->{STATE}, 1);
    }
  }

  my $max = int(@{$hash->{CHANGED}});
  Log 5, "Triggering $dev ($max changes)";
  return "" if(defined($attr{$dev}) && defined($attr{$dev}{do_not_notify}));

  ################
  # Log/notify modules
  # If modifying a device in its own trigger, do not call the triggers from
  # the inner loop.
  if($max && !defined($hash->{INTRIGGER})) {
    $hash->{INTRIGGER}=1;
    my @ntfyList = sort { $defs{$a}{NTFY_ORDER} cmp $defs{$b}{NTFY_ORDER} }
                   grep { $defs{$_}{NTFY_ORDER} } keys %defs;
    Log 5, "Notify loop for $dev $hash->{CHANGED}->[0]";
    $hash->{NTFY_TRIGGERTIME} = TimeNow(); # Optimize FileLog
    foreach my $n (@ntfyList) {
      next if(!defined($defs{$n}));     # Was deleted in a previous notify
      my $r = CallFn($n, "NotifyFn", $defs{$n}, $hash);
      $ret .= $r if($r);
    }
    delete($hash->{NTFY_TRIGGERTIME});

    ################
    # Inform
    if($hash->{CHANGED}) {    # It gets deleted sometimes (?)
      $max = int(@{$hash->{CHANGED}}); # can be enriched in the notifies
      foreach my $c (keys %inform) {
        if(!$defs{$c} || $defs{$c}{NR} != $inform{$c}{NR}) {
          delete($inform{$c});
          next;
        }
        next if($inform{$c}{type} eq "raw");
        my $tn = TimeNow();
        if($attr{global}{mseclog}) {
          my ($seconds, $microseconds) = gettimeofday();
          $tn .= sprintf(".%03d", $microseconds/1000);
        }
        my $re = $inform{$c}{regexp};
        for(my $i = 0; $i < $max; $i++) {
          my $state = $hash->{CHANGED}[$i];
          next if($re && !($dev =~ m/$re/ || "$dev:$state" =~ m/$re/));
          syswrite($defs{$c}{CD},
            ($inform{$c}{type} eq "timer" ? "$tn " : "") .
            "$hash->{TYPE} $dev $state\n");
        }
      }
    }

    delete($hash->{INTRIGGER});
  }


  ####################
  # Used by triggered perl programs to check the old value
  # Not suited for multi-valued devices (KS300, etc)
  $oldvalue{$dev}{TIME} = TimeNow();
  $oldvalue{$dev}{VAL} = $hash->{STATE};

  delete($hash->{CHANGED}) if(!defined($hash->{INTRIGGER}));

  Log 3, "NTFY return: $ret" if($ret);

  return $ret;
}

#####################################
# Wrapper for calling a module function
sub
CallFn(@)
{
  my $d = shift;
  my $n = shift;

  if(!$d || !$defs{$d}) {
    $d = "<undefined>" if(!defined($d));
    Log 0, "Strange call for nonexistent $d: $n";
    return undef;
  }
  if(!$defs{$d}{TYPE}) {
    Log 0, "Strange call for typeless $d: $n";
    return undef;
  }
  my $fn = $modules{$defs{$d}{TYPE}}{$n};
  return "" if(!$fn);
  if(wantarray) {
    no strict "refs";
    my @ret = &{$fn}(@_);
    use strict "refs";
    return @ret;
  } else {
    no strict "refs";
    my $ret = &{$fn}(@_);
    use strict "refs";
    return $ret;
  }
}

#####################################
# Used from perl oneliners inside of scripts
sub
fhem($@)
{
  my ($param, $silent) = @_;
  my $ret = AnalyzeCommandChain(undef, $param);
  Log 3, "$param : $ret" if($ret && !$silent);
  return $ret;
}

#####################################
# initialize the global device
sub
doGlobalDef($)
{
  my ($arg) = @_;

  $devcount = 1;
  $defs{global}{NR}    = $devcount++;
  $defs{global}{TYPE}  = "Global";
  $defs{global}{STATE} = "<no definition>";
  $defs{global}{DEF}   = "<no definition>";
  $defs{global}{NAME}  = "global";

  CommandAttr(undef, "global verbose 3");
  CommandAttr(undef, "global configfile $arg");
  CommandAttr(undef, "global logfile -");
}

#####################################
# rename does not work over Filesystems: lets copy it
sub
myrename($$)
{
  my ($from, $to) = @_;

  if(!open(F, $from)) {
    Log(1, "Rename: Cannot open $from: $!");
    return;
  }
  if(!open(T, ">$to")) {
    Log(1, "Rename: Cannot open $to: $!");
    return;
  }
  while(my $l = <F>) {
    print T $l;
  }
  close(F);
  close(T);
  unlink($from);
}

#####################################
# Make a directory and its parent directories if needed.
sub
HandleArchiving($)
{
  my ($log) = @_;
  my $ln = $log->{NAME};
  return if(!$attr{$ln});

  # If there is a command, call that
  my $cmd = $attr{$ln}{archivecmd};
  if($cmd) {
    $cmd =~ s/%/$log->{currentlogfile}/g;
    Log 2, "Archive: calling $cmd";
    system($cmd);
    return;
  }

  my $nra = $attr{$ln}{nrarchive};
  my $ard = $attr{$ln}{archivedir};
  return if(!defined($nra));

  # If nrarchive is set, then check the last files:
  # Get a list of files:

  my ($dir, $file);
  if($log->{logfile} =~ m,^(.+)/([^/]+)$,) {
    ($dir, $file) = ($1, $2);
  } else {
    ($dir, $file) = (".", $log->{logfile});
  }

  $file =~ s/%./.+/g;
  return if(!opendir(DH, $dir));
  my @files = sort grep {/^$file$/} readdir(DH);
  closedir(DH);

  my $max = int(@files)-$nra;
  for(my $i = 0; $i < $max; $i++) {
    if($ard) {
      Log 2, "Moving $files[$i] to $ard";
      myrename("$dir/$files[$i]", "$ard/$files[$i]");
    } else {
      Log 2, "Deleting $files[$i]";
      unlink("$dir/$files[$i]");
    }
  }
}

#####################################
# Call a logical device (FS20) ParseMessage with data from a physical device
# (FHZ)
sub
Dispatch($$$)
{
  my ($hash, $dmsg, $addvals) = @_;
  my $iohash = $modules{$hash->{TYPE}}; # The phyiscal device module pointer
  my $name = $hash->{NAME};

  Log 5, "$name dispatch $dmsg";

  my ($isdup, $idx) = CheckDuplicate($name, $dmsg, $iohash->{FingerprintFn});
  return rejectDuplicate($name,$idx,$addvals) if($isdup);

  my @found;

  my $clientArray = $hash->{".clientArray"};
  $clientArray = computeClientArray($hash, $iohash) if(!$clientArray);

  foreach my $m (@{$clientArray}) {
    # Module is not loaded or the message is not for this module
    next if($dmsg !~ m/$modules{$m}{Match}/i);

    if( my $ffn = $modules{$m}{FingerprintFn} ) {
      (my $isdup, $idx) = CheckDuplicate($name, $dmsg, $ffn);
      return rejectDuplicate($name,$idx,$addvals) if($isdup);
    }

    no strict "refs"; $readingsUpdateDelayTrigger = 1;
    @found = &{$modules{$m}{ParseFn}}($hash,$dmsg);
    use strict "refs"; $readingsUpdateDelayTrigger = 0;
    last if(int(@found));
  }

  if(!int(@found)) {
    my $h = $hash->{MatchList}; $h = $iohash->{MatchList} if(!$h);
    if(defined($h)) {
      foreach my $m (sort keys %{$h}) {
        if($dmsg =~ m/$h->{$m}/) {
          my ($order, $mname) = split(":", $m);

          if($attr{global}{autoload_undefined_devices}) {
            my $newm = LoadModule($mname);
            $mname = $newm if($newm ne "UNDEFINED");
            if($modules{$mname} && $modules{$mname}{ParseFn}) {
              no strict "refs"; $readingsUpdateDelayTrigger = 1;
              @found = &{$modules{$mname}{ParseFn}}($hash,$dmsg);
              use strict "refs"; $readingsUpdateDelayTrigger = 0;
            } else {
              Log 0, "ERROR: Cannot autoload $mname";
            }

          } else {
            Log3 $name, 3, "$name: Unknown $mname device detected, " .
                        "define one to get detailed information.";
            return undef;

          }
        }
      }
    }
    if(!int(@found)) {
      DoTrigger($name, "UNKNOWNCODE $dmsg");
      Log3 $name, 3, "$name: Unknown code $dmsg, help me!";
      return undef;
    }
  }

  ################
  # Inform raw
  if(!$iohash->{noRawInform}) {
    foreach my $c (keys %inform) {
      if(!$defs{$c} || $defs{$c}{NR} != $inform{$c}{NR}) {
        delete($inform{$c});
        next;
      }
      next if($inform{$c}{type} ne "raw");
      syswrite($defs{$c}{CD}, "$hash->{TYPE} $name $dmsg\n");
    }
  }

  return undef if($found[0] eq "");	# Special return: Do not notify

  foreach my $found (@found) {

    if($found =~ m/^(UNDEFINED.*)/) {
      DoTrigger("global", $1);
      return undef;

    } else {
      if($defs{$found}) {
        $defs{$found}{MSGCNT}++;
        my $avtrigger = ($attr{$name} && $attr{$name}{addvaltrigger});
        if($addvals) {
          foreach my $av (keys %{$addvals}) {
            $defs{$found}{"${name}_$av"} = $addvals->{$av};
            push(@{$defs{$found}{CHANGED}}, "$av: $addvals->{$av}")
              if($avtrigger);
          }
        }
        $defs{$found}{"${name}_MSGCNT"}++;
        $defs{$found}{"${name}_TIME"} = TimeNow();
        $defs{$found}{LASTInputDev} = $name;
      }
      DoTrigger($found, undef);
    }
  }

  $duplicate{$idx}{FND} = \@found;

  return \@found;
}

sub
CheckDuplicate($$@)
{
  my ($ioname, $msg, $ffn) = @_;

  if($ffn) {
    no strict "refs";
    ($ioname,$msg) = &{$ffn}($ioname,$msg);
    use strict "refs";
    return (0, undef) if( !defined($msg) );
    #Debug "got $ffn ". $ioname .":". $msg;
  }

  my $now = gettimeofday();
  my $lim = $now-AttrVal("global","dupTimeout", 0.5);

  foreach my $oidx (keys %duplicate) {
    if($duplicate{$oidx}{TIM} < $lim) {
      delete($duplicate{$oidx});

    } elsif($duplicate{$oidx}{MSG} eq $msg &&
            $duplicate{$oidx}{ION} eq "") {
      return (1, $oidx);

    } elsif($duplicate{$oidx}{MSG} eq $msg &&
            $duplicate{$oidx}{ION} ne $ioname) {
      return (1, $oidx);

    }
  }
  #Debug "is unique";
  $duplicate{$duplidx}{ION} = $ioname;
  $duplicate{$duplidx}{MSG} = $msg;
  $duplicate{$duplidx}{TIM} = $now;
  $duplidx++;
  return (0, $duplidx-1);
}

sub
rejectDuplicate($$$)
{
  #Debug "is duplicate";
  my ($name,$idx,$addvals) = @_;
  my $found = $duplicate{$idx}{FND};
  foreach my $found (@{$found}) {
    if($addvals) {
      foreach my $av (keys %{$addvals}) {
        $defs{$found}{"${name}_$av"} = $addvals->{$av};
      }
    }
    $defs{$found}{"${name}_MSGCNT"}++;
    $defs{$found}{"${name}_TIME"} = TimeNow();
  }
  return $duplicate{$idx}{FND};
}

sub
AddDuplicate($$)
{
  $duplicate{$duplidx}{ION} = shift;
  $duplicate{$duplidx}{MSG} = shift;
  $duplicate{$duplidx}{TIM} = gettimeofday();
  $duplidx++;
}

# Add an attribute to the userattr list, if not yet present
sub
addToAttrList($)
{
  my $arg = shift;

  my $ua = "";
  $ua = $attr{global}{userattr} if($attr{global}{userattr});
  my @al = split(" ", $ua);
  my %hash;
  foreach my $a (@al) {
    $hash{$a} = 1 if(" $AttrList " !~ m/ $a /); # Cleanse old ones
  }
  $hash{$arg} = 1 if(" $AttrList " !~ m/ $arg /);
  $attr{global}{userattr} = join(" ", sort keys %hash);
}

sub
EventMapAsList($)
{
  my ($em) = @_;
  my $sc = " ";               # Split character
  my $fc = substr($em, 0, 1); # First character of the eventMap
  if($fc eq "," || $fc eq "/") {
    $sc = $fc;
    $em = substr($em, 1);
  }
  return split($sc, $em);
}

#######################
# $dir: 0 = User to Fhem (i.e. set), 1 = Fhem to User (i.e trigger)
sub
ReplaceEventMap($$$)
{
  my ($dev, $str, $dir) = @_;
  my $em = $attr{$dev}{eventMap};
  return $str    if($dir && !$em);
  return @{$str} if(!$dir && (!$em || int(@{$str}) < 2 || $str->[1] eq "?"));
  my $dname = shift @{$str} if(!$dir);

  my $nstr = join(" ", @{$str}) if(!$dir);
  my $changed;
  my @emList = EventMapAsList($em);
  foreach my $rv (@emList) {
    # Real-Event-Regexp:GivenName[:modifier]
    my ($re, $val, $modifier) = split(":", $rv, 3);
    next if(!defined($val));
    if($dir) {  # event -> GivenName
      if($str =~ m/$re/) {
        $str =~ s/$re/$val/;
        $changed = 1;
        last;
      }

    } else {    # GivenName -> set command
      if($nstr eq $val) { # for special translations like <> and <<
        $nstr = $re;
        $changed = 1;
        last;
      } elsif($nstr =~ m/\b$val\b/) {
        $nstr =~ s/\b$val\b/$re/;
        $changed = 1;
        last;
      }

    }
  }
  return $str if($dir);

  if($changed) {
    my @arr = split(" ",$nstr);
    unshift @arr, $dname;
    return @arr;
  } else {
    unshift @{$str}, $dname;
    return @{$str};
  }
}

sub
setGlobalAttrBeforeFork($)
{
  my ($f) = @_;
  open(FH, $f) || die("Cant open $f: $!\n");
  while(my $l = <FH>) {
    $l =~ s/[\r\n]//g;
    next if($l !~ m/^attr\s+global\s+([^\s]+)\s+(.*)$/);
    my ($n,$v) = ($1,$2);
    $v =~ s/#.*//;
    $v =~ s/ .*$//;
    $attr{global}{$n} = $v;
  }
  close(FH);
}


###########################################
# Functions used to make fhem-oneliners more readable,
# but also recommended to be used by modules
sub
InternalVal($$$)
{
  my ($d,$n,$default) = @_;
  if(defined($defs{$d}) &&
     defined($defs{$d}{$n})) {
     return $defs{$d}{$n};
  }
  return $default;
}

sub
ReadingsVal($$$)
{
  my ($d,$n,$default) = @_;
  if(defined($defs{$d}) &&
     defined($defs{$d}{READINGS}) &&
     defined($defs{$d}{READINGS}{$n}) &&
     defined($defs{$d}{READINGS}{$n}{VAL})) {
     return $defs{$d}{READINGS}{$n}{VAL};
  }
  return $default;
}

sub
ReadingsTimestamp($$$)
{
  my ($d,$n,$default) = @_;
  if(defined($defs{$d}) &&
     defined($defs{$d}{READINGS}) &&
     defined($defs{$d}{READINGS}{$n}) &&
     defined($defs{$d}{READINGS}{$n}{TIME})) {
     return $defs{$d}{READINGS}{$n}{TIME};
  }
  return $default;
}

sub
Value($)
{
  my ($d) = @_;
  if(defined($defs{$d}) &&
     defined($defs{$d}{STATE})) {
     return $defs{$d}{STATE};
  }
  return "";
}

sub
OldValue($)
{
  my ($d) = @_;
  return $oldvalue{$d}{VAL} if(defined($oldvalue{$d})) ;
  return "";
}

sub
OldTimestamp($)
{
  my ($d) = @_;
  return $oldvalue{$d}{TIME} if(defined($oldvalue{$d})) ;
  return "";
}

sub
AttrVal($$$)
{
  my ($d,$n,$default) = @_;
  return $attr{$d}{$n} if($d && defined($attr{$d}) && defined($attr{$d}{$n}));
  return $default;
}

################################################################
# Functions used by modules.
sub
setReadingsVal($$$$)
{
  my ($hash,$rname,$val,$ts) = @_;
  $hash->{READINGS}{$rname}{VAL} = $val;
  $hash->{READINGS}{$rname}{TIME} = $ts;
}

sub
addEvent($$)
{
  my ($hash,$event) = @_;
  push(@{$hash->{CHANGED}}, $event);
}

################################################################
#
# Meta-information for devices
# This part maintained by Boris Neubert omega at online dot de
#
################################################################


# get the names of interfaces for the device represented by the $hash
# empty list is returned if interfaces are not defined
sub
getInterfaces($) {
  my ($hash)= @_;
  #Debug "getInterfaces(" . $hash->{NAME} .")= ".$hash->{internals}{interfaces};
  if(defined($hash->{internals}{interfaces})) {
    return split(/:/, $hash->{internals}{interfaces});
  } else {
    return ();
  }
}

# get the names of the setters for a named interface
# empty list is returned if interface is not defined
sub
getSettersForInterface($) {
  my $interface= shift;
  if(defined($interface)) {
    return split /:/, $interfaces{$interface}{setters};
  } else {
    return ();
  }
}

# get the names of the getters for a named interface
# empty list is returned if interface is not defined
sub
getGettersForInterface($) {
  my $interface= shift;
  if(defined($interface)) {
    return split /:/, $interfaces{$interface}{getters};
  } else {
    return ();
  }
}

# get the names of the readings for a named interface
# empty list is returned if interface is not defined
sub
getReadingsForInterface($) {
  my $interface= shift;
  if(defined($interface)) {
    return split /:/, $interfaces{$interface}{readings};
  } else {
    return ();
  }
}

# get the names of the setters for the device represented by the $hash
# empty list is returned if interfaces are not defined
sub
getSetters($) {
  my ($hash)= @_;
  my ($interface, @setters);
  #Debug "getSetters...";
  foreach $interface (getInterfaces($hash)) {
    #Debug "Interface $interface";
    push @setters, getSettersForInterface($interface);
  } 
  return @setters;
}

# get the names of the getters for the device represented by the $hash
# empty list is returned if interfaces are not defined
sub
getGetters($) {
  my ($hash)= @_;
  my @getters;
  my $interface;
  foreach $interface (getInterfaces($hash)) {
    push @getters, getGettersForInterface($interface);
  }
  return @getters;
}

sub 
concatc($$$) {
  my ($separator,$a,$b)= @_;;
  return($a && $b ?  $a . $separator . $b : $a . $b);
}


# this creates the standard interface definitions as in
# http://fhemwiki.de/wiki/DevelopmentInterfaces
sub
createInterfaceDefinitions() {

  #Log 2, "Creating interface definitions...";
  # The interfaces list below consists of lines with the 
  # pipe-separated parts
  # - name
  # - ancestor
  # - colon separated list of readings
  # - colon-separated list of getters
  # - colon-separated list of setters
  # If no getters are listed they are considered identical
  # to the readings.
  # Ancestors must be listed before descendants.
  # Two interfaces can share a subset of readings, getters and setters
  # if and only if one interface is the ancestor of the other.
  my $IDefs= <<EOD;
interface||||
switch|interface|onoff||
switch_active|switch|||
switch_passive|switch|||on:off
dimmer|switch_passive|level||dimto:dimup:dimdown
temperature|interface|temperature||
humidity|interface|humidity||
wind|interface|wind||
power|interface|power:maxPower:energy||
EOD
  
  my ($i,@p);
  foreach $i (split /\n/, $IDefs) {
    my ($interface,$ancestor,$readings,$getters,$setters)= split /\|/, $i;
    $getters= $readings unless($getters);
    if($ancestor) {
      $readings=  concatc(":", $interfaces{$ancestor}{readings}, $readings);
      $getters=  concatc(":", $interfaces{$ancestor}{getters}, $getters);
      $setters=  concatc(":", $interfaces{$ancestor}{setters}, $setters);
    }
    $interfaces{$interface}{ancestor}= $ancestor;
    $interfaces{$interface}{readings}= $readings;
    $interfaces{$interface}{getters}= $getters;
    $interfaces{$interface}{setters}= $setters;
    Log 5, "Interface \"$interface\": " .
           "readings \"$readings\", getters \"$getters\", setters \"$setters\"";
  }

}


################################################################
#
# Wrappers for commonly used core functions in device-specific modules. 
#
################################################################

#
# Call readingsBeginUpdate before you start updating readings.
# The updated readings will all get the same timestamp,
# which is the time when you called this subroutine.
#
sub 
readingsBeginUpdate($)
{
  my ($hash)= @_;
  my $name = $hash->{NAME};
  
  # get timestamp
  my $now = gettimeofday();
  my $fmtDateTime = FmtDateTime($now);
  $hash->{".updateTime"} = $now; # in seconds since the epoch
  $hash->{".updateTimestamp"} = $fmtDateTime;

  my $attrminint = AttrVal($name, "event-min-interval", undef);
  if($attrminint) {
    my @a = split(/,/,$attrminint);
    $hash->{".attrminint"} = \@a;
  }

  my $attreocr= AttrVal($name, "event-on-change-reading", undef);
  if($attreocr) {
    my @a = split(/,/,$attreocr);
    $hash->{".attreocr"} = \@a;
  }
  
  my $attreour= AttrVal($name, "event-on-update-reading", undef);
  if($attreour) {
    my @a = split(/,/,$attreour);
    $hash->{".attreour"} = \@a;
  }

  $hash->{CHANGED}= () if(!defined($hash->{CHANGED}));
  return $fmtDateTime;
}

sub
evalStateFormat($)
{
  my ($hash) = @_;

  my $name = $hash->{NAME};

  ###########################
  # Set STATE
  my $sr = AttrVal($name, "stateFormat", undef);
  my $st = $hash->{READINGS}{state};
  if(!$sr) {
    $st = $st->{VAL} if(defined($st));

  } elsif($sr =~ m/^{(.*)}$/) {
    $st = eval $1;
    if($@) {
      $st = "Error evaluating $name stateFormat: $@";
      Log 1, $st;
    }

  } else {
    # Substitute reading names with their values, leave the rest untouched.
    $st = $sr;
    my $r = $hash->{READINGS};
    $st =~ s/\b([A-Za-z\d_\.-]+)\b/($r->{$1} ? $r->{$1}{VAL} : $1)/ge;

  }
  $hash->{STATE} = ReplaceEventMap($name, $st, 1) if(defined($st));
}

#
# Call readingsEndUpdate when you are done updating readings.
# This optionally calls DoTrigger to propagate the changes.
#
sub
readingsEndUpdate($$)
{
  my ($hash,$dotrigger)= @_;
  my $name = $hash->{NAME};

  $hash->{".triggerUsed"} = 1 if(defined($hash->{".triggerUsed"}));

  # process user readings
  if(defined($hash->{'.userReadings'})) {
    my %userReadings= %{$hash->{'.userReadings'}};
    foreach my $userReading (keys %userReadings) {

      my $trigger = $userReadings{$userReading}{trigger};
      if(defined($trigger)) {
        my @fnd = grep { $_ && $_ =~ m/^$trigger/ } @{$hash->{CHANGED}};
        next if(!@fnd);
      }

      my $modifier= $userReadings{$userReading}{modifier};
      my $perlCode= $userReadings{$userReading}{perlCode};
      my $oldvalue= $userReadings{$userReading}{value};
      my $oldt= $userReadings{$userReading}{t};
      #Debug "Evaluating " . $userReadings{$userReading};
      # evaluate perl code
      my $value= eval $perlCode;
      my $result;
      # store result
      if($@) {
        $value = "Error evaluating $name userReading $userReading: $@";
        Log 1, $value;
        $result= $value;
      } elsif($modifier eq "none") {
        $result= $value;
      } elsif($modifier eq "difference") {
        $result= $value - $oldvalue if(defined($oldvalue));
      } elsif($modifier eq "differential") {
        my $deltav= $value - $oldvalue if(defined($oldvalue));
        my $deltat= $hash->{".updateTime"} - $oldt if(defined($oldt));
        if(defined($deltav) && defined($deltat) && ($deltat>= 1.0)) {
          $result= $deltav/$deltat;
        }
      } elsif($modifier eq "offset") {
        $oldvalue= 0 if( !defined($oldvalue) );
        $result = ReadingsVal($name,$userReading,0);
        $result += $oldvalue if( $value < $oldvalue );
      } elsif($modifier eq "monotonic") {
        $oldvalue= 0 if( !defined($oldvalue) );
        $result = ReadingsVal($name,$userReading,0);
        $result += $value - $oldvalue if( $value > $oldvalue );
      } 
      readingsBulkUpdate($hash,$userReading,$result,1) if(defined($result));
      # store value
      $hash->{'.userReadings'}{$userReading}{TIME}= $hash->{".updateTimestamp"};
      $hash->{'.userReadings'}{$userReading}{t}= $hash->{".updateTime"};
      $hash->{'.userReadings'}{$userReading}{value}= $value;
    }
  }
  evalStateFormat($hash);

  # turn off updating mode
  delete $hash->{".updateTimestamp"};
  delete $hash->{".updateTime"};
  delete $hash->{".attreour"};
  delete $hash->{".attreocr"};
  delete $hash->{".attrminint"};


  # propagate changes
  if($dotrigger && $init_done) {
    DoTrigger($name, undef, 0) if(!$readingsUpdateDelayTrigger);
  } else {
    delete($hash->{CHANGED});
  }
  
  return undef;
}

#
# Call readingsBulkUpdate to update the reading.
# Example: readingsUpdate($hash,"temperature",$value);
#
sub
readingsBulkUpdate($$$@)
{
  my ($hash,$reading,$value,$changed)= @_;
  my $name= $hash->{NAME};

  return if(!defined($reading) || !defined($value));
  # sanity check
  if(!defined($hash->{".updateTimestamp"})) {
    Log 1, "readingsUpdate($name,$reading,$value) missed to call ".
                "readingsBeginUpdate first.";
    return;
  }
  
  # shorthand
  my $readings= $hash->{READINGS}{$reading};

  if(!defined($changed)) {
    $changed = (substr($reading,0,1) ne "."); # Dont trigger dot-readings
  }
  $changed = 0 if($hash->{".ignoreEvent"});

  # check for changes only if reading already exists
  if($changed && defined($readings)) {
  
    # these flags determine if any of the "event-on" attributes are set
    my $attreocr   = $hash->{".attreocr"};
    my $attreour   = $hash->{".attreour"};

    # these flags determine whether the reading is listed in any of
    # the attributes
    my $eocr= $attreocr && grep($reading =~ m/^$_$/, @{$attreocr});
    my $eour= $attreour && grep($reading =~ m/^$_$/, @{$attreour});
    # determine if an event should be created:
    # always create event if no attribute is set
    # or if the reading is listed in event-on-update-reading
    # or if the reading is listed in event-on-change-reading...
    # ...and its value has changed.
    $changed= !($attreocr || $attreour)
              || $eour  
              || ($eocr && ($value ne $readings->{VAL}));
    #Log 1, "EOCR:$eocr EOUR:$eour CHANGED:$changed";

    my @v = grep { my $l = $_;
                   $l =~ s/:.*//;
                   ($reading=~ m/^$l$/) ? $_ : undef} @{$hash->{".attrminint"}};
    if(@v) {
      my (undef, $minInt) = split(":", $v[0]);
      my $now = $hash->{".updateTime"};
      my $le = $hash->{".lastTime$reading"};
      if($le && $now-$le < $minInt) {
        if(!$eocr || ($eocr && $value eq $readings->{VAL})){
          $changed = 0;
        } else {
          $hash->{".lastTime$reading"} = $now;
        }
      } else {
        $hash->{".lastTime$reading"} = $now;
        $changed = 1 if($eocr);
      }
    }
  }
 
  setReadingsVal($hash, $reading, $value, $hash->{".updateTimestamp"}); 
  
  my $rv = "$reading: $value";
  if($changed) {
    $rv = "$value" if($reading eq "state");
    addEvent($hash, $rv);
  }
  return $rv;
}

#
# this is a shorthand call
#
sub
readingsSingleUpdate($$$$)
{
  my ($hash,$reading,$value,$dotrigger)= @_;
  readingsBeginUpdate($hash);
  my $rv = readingsBulkUpdate($hash,$reading,$value);
  readingsEndUpdate($hash,$dotrigger);
  return $rv;
}

##############################################################################
#
# date and time routines
#
##############################################################################

sub
fhemTzOffset($) {
    # see http://stackoverflow.com/questions/2143528/whats-the-best-way-to-get-the-utc-offset-in-perl
    my $t = shift;
    my @l = localtime($t);
    my @g = gmtime($t);

    # the offset is positive if the local timezone is ahead of GMT, e.g. we get 2*3600 seconds for CET DST vs GMT
    return 60*(($l[2] - $g[2] + ((($l[5]<<9)|$l[7]) <=> (($g[5]<<9)|$g[7])) * 24) * 60 + $l[1] - $g[1]);
}

sub
fhemTimeGm($$$$$$) {
    # see http://de.wikipedia.org/wiki/Unixzeit
    my ($sec,$min,$hour,$mday,$month,$year) = @_;

    # $mday= 1..
    # $month= 0..11
    # $year is year-1900
    
    $year+= 1900;
    my $isleapyear= $year % 4 ? 0 : $year % 100 ? 1 : $year % 400 ? 0 : 1;
    # here the Wikipedia as at 2012-12-01 is wrong and that code line is right
    my $leapyears= int(($year-1968)/4 - ($year-1900)/100 + ($year-1600)/400);
    #Debug sprintf("%02d.%02d.%04d %02d:%02d:%02d %d leap years, is leap year: %d", $mday,$month+1,$year,$hour,$min,$sec,$leapyears,$isleapyear);

    if ( $^O eq 'MacOS' ) {
      $year-= 1904;
    } else {
      $year-= 1970; # the Unix Epoch
    }

    my @d= (0,31,59,90,120,151,181,212,243,273,304,334); # no leap day
    # add one day in leap years if month is later than February
    $mday++ if($month>1 && $isleapyear);
    return $sec+60*($min+60*($hour+24*($d[$month]+$mday-1+365*$year+$leapyears)));
}

sub
fhemTimeLocal($$$$$$) {
    my $t= fhemTimeGm($_[0],$_[1],$_[2],$_[3],$_[4],$_[5]);
    return $t-fhemTzOffset($t);
}

sub
computeClientArray($$)
{
  my ($hash, $iohash) = @_;
  my @a = ();
  my @mRe = split(":", $hash->{Clients} ? $hash->{Clients}:$iohash->{Clients});

  foreach my $m (sort { $modules{$a}{ORDER} cmp $modules{$b}{ORDER} }
                  grep { defined($modules{$_}{ORDER}) } keys %modules) {
    foreach my $re (@mRe) {
      if($m =~ m/^$re$/) {
        push @a, $m if($modules{$m}{Match});
        last;
      }
    }
  }

  $hash->{".clientArray"} = \@a;
  return \@a;
}

# http://perldoc.perl.org/perluniintro.html, UNICODE IN OLDER PERLS
sub
latin1ToUtf8($)
{
  my ($s)= @_;
  $s =~ s/([\x80-\xFF])/chr(0xC0|ord($1)>>6).chr(0x80|ord($1)&0x3F)/eg;
  return $s;
}

sub
utf8ToLatin1($)
{
  my ($s)= @_;
  $s =~ s/([\xC2\xC3])([\x80-\xBF])/chr(ord($1)<<6&0xC0|ord($2)&0x3F)/eg;
  return $s;
}

1;
