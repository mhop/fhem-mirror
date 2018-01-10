#!/usr/bin/perl

################################################################
#
#  Copyright notice
#
#  (c) 2005-2017
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
#
#  Homepage:  http://fhem.de
#
# $Id$


use strict;
use warnings;
use lib '.';
use IO::Socket;
use IO::Socket::INET;
use Time::HiRes qw(gettimeofday);
use Scalar::Util qw(looks_like_number);
use POSIX;
use File::Copy qw(copy);

##################################################
# Forward declarations
#
sub AddDuplicate($$);
sub AnalyzeCommand($$;$);
sub AnalyzeCommandChain($$;$);
sub AnalyzeInput($);
sub AnalyzePerlCommand($$;$);
sub AssignIoPort($;$);
sub AttrVal($$$);
sub AttrNum($$$;$);
sub CallFn(@);
sub CallInstanceFn(@);
sub CheckDuplicate($$@);
sub Debug($);
sub DoSet(@);
sub Dispatch($$$);
sub DoTrigger($$@);
sub EvalSpecials($%);
sub Each($$;$);
sub FileDelete($);
sub FileRead($);
sub FileWrite($@);
sub FmtDateTime($);
sub FmtTime($);
sub GetLogLevel(@);
sub GetTimeSpec($);
sub GetType($;$);
sub GlobalAttr($$$$);
sub HandleArchiving($;$);
sub HandleTimeout();
sub IOWrite($@);
sub InternalTimer($$$;$);
sub InternalVal($$$);
sub InternalNum($$$;$);
sub IsDevice($;$);
sub IsDisabled($);
sub IsDummy($);
sub IsIgnored($);
sub IsIoDummy($);
sub LoadModule($;$);
sub Log($$);
sub Log3($$$);
sub OldTimestamp($);
sub OldValue($);
sub OpenLogfile($);
sub PrintHash($$);
sub ReadingsNum($$$;$);
sub ReadingsTimestamp($$$);
sub ReadingsVal($$$);
sub RefreshAuthList();
sub RemoveInternalTimer($;$);
sub ReplaceEventMap($$$);
sub ResolveDateWildcards($@);
sub SecurityCheck();
sub SemicolonEscape($);
sub SignalHandling();
sub TimeNow();
sub Value($);
sub WakeUpFn($);
sub WriteStatefile();
sub XmlEscape($);
sub addEvent($$);
sub addToDevAttrList($$);
sub addToAttrList($);
sub addToWritebuffer($$@);
sub attrSplit($);
sub computeClientArray($$);
sub concatc($$$);
sub configDBUsed();
sub createNtfyHash();
sub createUniqueId();
sub devspec2array($;$);
sub doGlobalDef($);
sub escapeLogLine($);
sub evalStateFormat($);
sub fhem($@);
sub fhemTimeGm($$$$$$);
sub fhemTimeLocal($$$$$$);
sub fhemTzOffset($);
sub getAllAttr($;$);
sub getAllGets($;$);
sub getAllSets($;$);
sub getPawList($);
sub getUniqueId();
sub latin1ToUtf8($);
sub myrename($$$);
sub notifyRegexpChanged($$);
sub parseParams($;$$);
sub perlSyntaxCheck($%);
sub readingsBeginUpdate($);
sub readingsBulkUpdate($$$@);
sub readingsEndUpdate($$);
sub readingsSingleUpdate($$$$);
sub redirectStdinStdErr();
sub rejectDuplicate($$$);
sub restoreDir_init();
sub restoreDir_rmTree($);
sub restoreDir_saveFile($$);
sub restoreDir_mkDir($$$);
sub setGlobalAttrBeforeFork($);
sub setReadingsVal($$$$);
sub toJSON($);
sub utf8ToLatin1($);

sub CommandAttr($$);
sub CommandCancel($$);
sub CommandDefaultAttr($$);
sub CommandDefine($$);
sub CommandDefMod($$);
sub CommandDelete($$);
sub CommandDeleteAttr($$);
sub CommandDeleteReading($$);
sub CommandDisplayAttr($$);
sub CommandGet($$);
sub CommandIOWrite($$);
sub CommandInclude($$);
sub CommandList($$);
sub CommandModify($$);
sub CommandQuit($$);
sub CommandReload($$;$);
sub CommandRename($$);
sub CommandRereadCfg($$);
sub CommandSave($$);
sub CommandSet($$);
sub CommandSetReading($$);
sub CommandSetstate($$);
sub CommandShutdown($$);
sub CommandSleep($$);
sub CommandTrigger($$);

# configDB special
sub cfgDB_Init;
sub cfgDB_ReadAll($);
sub cfgDB_SaveState;
sub cfgDB_SaveCfg;
sub cfgDB_AttrRead($);
sub cfgDB_ReadFile($);
sub cfgDB_UpdateFile($);
sub cfgDB_WriteFile($@);

##################################################
# Variables:
# global, to be able to access them from modules

#Special values in %modules (used if set):
# AttrFn   - called for attribute changes
# DefFn    - define a "device" of this type
# DeleteFn - clean up (delete logfile), called by delete after UndefFn
# ExceptFn - called if the global select reports an except field
# FingerprintFn - convert messages for duplicate detection
# GetFn    - get some data from this device
# NotifyFn - call this if some device changed its properties
# ParseFn  - Interpret a raw message
# ReadFn   - Reading from a Device (see FHZ/WS300)
# ReadyFn  - check for available data, if no FD
# RenameFn - inform the device about its renameing
# SetFn    - set/activate this device
# ShutdownFn-called before shutdown
# StateFn  - set local info for this device, do not activate anything
# UndefFn  - clean up (delete timer, close fd), called by delete and rereadcfg

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
# NOTIFYDEV - if set, the notifyFn will only be called for this device

use vars qw($auth_refresh);
use vars qw($cmdFromAnalyze);   # used by the warnings-sub
use vars qw($lastWarningMsg);   # set by the warnings-sub
use vars qw($cvsid);            # used in 98_version.pm
use vars qw($devcount);         # Maximum device number, used for storing
use vars qw($featurelevel); 
use vars qw($fhem_started);     # used for uptime calculation
use vars qw($init_done);        #
use vars qw($internal_data);    # FileLog/DbLog -> SVG data transport
use vars qw($lastDefChange);    # number of last def/attr change
use vars qw($nextat);           # Time when next timer will be triggered.
use vars qw($readytimeout);     # Polling interval. UNIX: device search only
use vars qw($reread_active);
use vars qw($selectTimestamp);  # used to check last select exit timestamp
use vars qw($winService);       # the Windows Service object
use vars qw(%attr);             # Attributes
use vars qw(%cmds);             # Global command name hash.
use vars qw(%data);             # Hash for user data
use vars qw(%defaultattr);      # Default attributes, used by FHEM2FHEM
use vars qw(%defs);             # FHEM device/button definitions
use vars qw(%inform);           # Used by telnet_ActivateInform
use vars qw(%intAt);            # Internal at timer hash, global for benchmark
use vars qw(%logInform);        # Used by FHEMWEB/Event-Monitor
use vars qw(%modules);          # List of loaded modules (device/log/etc)
use vars qw(%ntfyHash);         # hash of devices needed to be notified.
use vars qw(%oldvalue);         # Old values, see commandref.html
use vars qw(%readyfnlist);      # devices which want a "readyfn"
use vars qw(%selectlist);       # devices which want a "select"
use vars qw(%value);            # Current values, see commandref.html
use vars qw(@authenticate);     # List of authentication devices
use vars qw(@authorize);        # List of authorization devices
use vars qw(@structChangeHist); # Contains the last 10 structural changes
use vars qw($haveInet6);        # Using INET6
use vars qw(%prioQueues);       #
use vars qw($fhemForked);       # 1 in a fhemFork()'ed process, else undef

$selectTimestamp = gettimeofday();
$cvsid = '$Id$';

my $AttrList = "alias comment:textField-long eventMap group room ".
               "suppressReading userReadings:textField-long ".
               "verbose:0,1,2,3,4,5";

my $currcfgfile="";             # current config/include file
my $currlogfile;                # logfile, without wildcards
my $duplidx=0;                  # helper for the above pool
my $evalSpecials;               # Used by EvalSpecials->AnalyzeCommand
my $intAtCnt=0;
my $logopened = 0;              # logfile opened or using stdout
my $namedef = "where <name> is a single device name, a list separated by komma (,) or a regexp. See the devspec section in the commandref.html for details.\n";
my $rcvdquit;                   # Used for quit handling in init files
my $readingsUpdateDelayTrigger; # needed internally
my $gotSig;                     # non-undef if got a signal
my $wbName = ".WRITEBUFFER";    # Buffer-name for delayed writing via select
my %comments;                   # Comments from the include files
my %duplicate;                  # Pool of received msg for multi-fhz/cul setups
my @cmdList;                    # Remaining commands in a chain. Used by sleep
my %sleepers;                   # list of sleepers

$init_done = 0;
$lastDefChange = 0;
$readytimeout = ($^O eq "MSWin32") ? 0.1 : 5.0;
$featurelevel = 5.8; # see also GlobalAttr


$modules{Global}{ORDER} = -1;
$modules{Global}{LOADED} = 1;
no warnings 'qw';
my @globalAttrList = qw(
  altitude
  apiversion
  archivecmd
  archivedir
  archivesort:timestamp,alphanum
  archiveCompress
  autoload_undefined_devices:1,0
  autosave:1,0
  backup_before_update
  backupcmd
  backupdir
  backupsymlink
  blockingCallMax
  commandref:modular,full
  configfile
  dnsHostsFile
  dnsServer
  dupTimeout
  exclude_from_update
  featurelevel:5.5,5.6,5.7,5.8,99.99
  genericDisplayType:switch,outlet,light,blind,speaker,thermostat
  holiday2we
  httpcompress:0,1
  language:EN,DE
  lastinclude
  latitude
  logdir
  logfile
  longitude
  modpath
  motd
  mseclog:1,0
  nofork:1,0
  nrarchive
  perlSyntaxCheck:0,1
  pidfilename
  proxy
  proxyAuth
  proxyExclude
  restartDelay
  restoreDirs
  sendStatistics:onUpdate,manually,never
  showInternalValues:1,0
  sslVersion
  stacktrace:1,0
  statefile
  title
  uniqueID
  updateInBackground:1,0
  updateNoFileCheck:1,0
  useInet6:1,0
  version
);
use warnings 'qw';
$modules{Global}{AttrList} = join(" ", @globalAttrList);
$modules{Global}{AttrFn} = "GlobalAttr";

use vars qw($readingFnAttributes);
$readingFnAttributes = "event-on-change-reading event-on-update-reading ".
                       "event-aggregator event-min-interval ".
                       "stateFormat:textField-long timestamp-on-change-reading";


%cmds = (
  "?"       => { ReplacedBy => "help" },
  "attr"    => { Fn=>"CommandAttr",
           Hlp=>"<devspec> <attrname> [<attrval>],set attribute for <devspec>"},
  "cancel"  => { Fn=>"CommandCancel",
           Hlp=>"[<id> [quiet]],list sleepers, cancel sleeper with <id>" },
  "createlog"=> { ModuleName => "autocreate" },
  "define"  => { Fn=>"CommandDefine",
           Hlp=>"<name> <type> <options>,define a device" },
  "defmod"  => { Fn=>"CommandDefMod",
           Hlp=>"<name> <type> <options>,define or modify a device" },
  "deleteattr" => { Fn=>"CommandDeleteAttr",
           Hlp=>"<devspec> [<attrname>],delete attribute for <devspec>" },
  "deletereading" => { Fn=>"CommandDeleteReading",
            Hlp=>"<devspec> [<attrname>],delete user defined reading for ".
                 "<devspec>" },
  "delete"  => { Fn=>"CommandDelete",
            Hlp=>"<devspec>,delete the corresponding definition(s)"},
  "displayattr"=> { Fn=>"CommandDisplayAttr",
            Hlp=>"<devspec> [attrname],display attributes" },
  "get"     => { Fn=>"CommandGet",
            Hlp=>"<devspec> <type dependent>,request data from <devspec>" },
  "include" => { Fn=>"CommandInclude",
            Hlp=>"<filename>,read the commands from <filenname>" },
  "iowrite" => { Fn=>"CommandIOWrite",
            Hlp=>"<iodev> <data>,write raw data with iodev" },
  "list"    => { Fn=>"CommandList",
            Hlp=>"[-r] [devspec],list definitions and status info" },
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
  "restore" => {
            Hlp=>"[list] [<filename|directory>],restore files saved by update"},
  "save"    => { Fn=>"CommandSave",
            Hlp=>"[configfile],write the configfile and the statefile" },
  "set"     => { Fn=>"CommandSet",
            Hlp=>"<devspec> <type dependent>,transmit code for <devspec>" },
  "setreading" => { Fn=>"CommandSetReading",
            Hlp=>"<devspec> <reading> <value>,set reading for <devspec>" },
  "setstate"=> { Fn=>"CommandSetstate",
            Hlp=>"<devspec> <state>,set the state shown in the command list" },
  "setdefaultattr" => { Fn=>"CommandDefaultAttr",
            Hlp=>"<attrname> <attrvalue>,set attr for following definitions" },
  "shutdown"=> { Fn=>"CommandShutdown",
            Hlp=>"[restart|exitValue],terminate the server" },
  "sleep"  => { Fn=>"CommandSleep",
            Hlp=>"<sec> [<id>] [quiet],sleep for sec, 3 decimal places" },
  "trigger" => { Fn=>"CommandTrigger",
            Hlp=>"<devspec> <state>,trigger notify command" },
  "update" => {
            Hlp => "[<fileName>|all|check|force] ".
                                      "[http://.../controlfile],update FHEM" },
  "updatefhem" => { ReplacedBy => "update" },
  "usb"     => { ModuleName => "autocreate" },
);

###################################################
# Start the program
my $fhemdebug;
$fhemdebug = shift @ARGV if($ARGV[0] eq "-d");

if(int(@ARGV) < 1) {
  print "Usage:\n";
  print "as server: fhem configfile\n";
  print "as client: fhem [host:]port cmd cmd cmd...\n";
  if($^O =~ m/Win/) {
    print "install as windows service: fhem.pl configfile -i\n";
    print "uninstall the windows service: fhem.pl -u\n";
  }
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
if(int(@ARGV) > 1 && $ARGV[$#ARGV] ne "-i") {
  my $buf;
  my $addr = shift @ARGV;
  $addr = "localhost:$addr" if($addr !~ m/:/);
  my $client = IO::Socket::INET->new(PeerAddr => $addr);
  die "Can't connect to $addr\n" if(!$client);
  for(my $i=0; $i < int(@ARGV); $i++) {
    syswrite($client, $ARGV[$i]."\n");
  }
  shutdown($client, 1);
  while(sysread($client, $buf, 256) > 0) {
    $buf =~ s/\xff\xfb\x01Password: //;
    $buf =~ s/\xff\xfc\x01\r\n//;
    $buf =~ s/\xff\xfd\x00//;
    print($buf);
  }
  exit(0);
}
# End of client code
###################################################


SignalHandling();

###################################################
# Windows Service Support: install/remove or start the fhem service
if($^O =~ m/Win/) {
  (my $dir = $0) =~ s+[/\\][^/\\]*$++; # Find the FHEM directory
  chdir($dir);
  $winService = eval {require FHEM::WinService; FHEM::WinService->new(\@ARGV);};
  if((!$winService || $@) && ($ARGV[$#ARGV] eq "-i" || $ARGV[$#ARGV] eq "-u")) {
    print "Cannot initialize FHEM::WinService: $@, exiting.\n";
    exit 0;
  }
}
$winService ||= {};

###################################################
# Server initialization
doGlobalDef($ARGV[0]);

if(configDBUsed()) {
  eval "use configDB";
  Log 1, $@ if($@);
  cfgDB_Init();
}


# As newer Linux versions reset serial parameters after fork, we parse the
# config file after the fork. But we need some global attr parameters before, so we
# read them here.
setGlobalAttrBeforeFork($attr{global}{configfile});

Log 1, $_ for eval{@{$winService->{ServiceLog}};};

# Go to background if the logfile is a real file (not stdout)
if($^O =~ m/Win/ && !$attr{global}{nofork}) {
  $attr{global}{nofork}=1;
}
if($attr{global}{logfile} ne "-" && !$attr{global}{nofork}) {
  defined(my $pid = fork) || die "Can't fork: $!";
  exit(0) if $pid;
}

# FritzBox special: Wait until the time is set via NTP,
# but not more than 2 hours
if(time() < 2*3600) {
  Log 1, "date/time not set, waiting up to 2 hours to be set.";
  while(time() < 2*3600) {
    sleep(5);
  }
}

###################################################
# initialize the readings semantics meta information
require RTypes;
RTypes_Initialize();

my $cfgErrMsg = "Messages collected while initializing FHEM:";
my $cfgRet="";
if(configDBUsed()) {
  my $ret = cfgDB_ReadAll(undef);
  $cfgRet .= "configDB: $ret\n" if($ret);

} else {
  my $ret = CommandInclude(undef, $attr{global}{configfile});
  $cfgRet .= "configfile: $ret\n" if($ret);

  my $stateFile = $attr{global}{statefile};
  if($stateFile) {
    my @t = localtime;
    $stateFile = ResolveDateWildcards($stateFile, @t);
    if(-r $stateFile) {
      $ret = CommandInclude(undef, $stateFile);
      $cfgRet .= "$stateFile: $ret\n" if($ret);
    }
  }
}

my $pfn = $attr{global}{pidfilename};
if($pfn) {
  die "$pfn: $!\n" if(!open(PID, ">$pfn"));
  print PID $$ . "\n";
  close(PID);
}

$init_done = 1;
$lastDefChange = 1;

foreach my $d (keys %defs) {
  if($defs{$d}{IODevMissing}) {
    if($defs{$d}{IODevName} && $defs{$defs{$d}{IODevName}}) {
      $defs{$d}{IODev} = $defs{$defs{$d}{IODevName}};
      delete $defs{$d}{IODevName};
    } else {
      Log 3, "No I/O device found for $defs{$d}{NAME}";
    }
    delete $defs{$d}{IODevMissing};
  }
}

if($cfgRet) {
  $attr{global}{autosave} = 0;
  $attr{global}{motd} = "$cfgErrMsg\n$cfgRet\nAutosave deactivated";
  Log 1, $cfgRet;

} elsif($attr{global}{motd} && $attr{global}{motd} =~ m/^$cfgErrMsg/) {
  $attr{global}{motd} = "";

} else {
  SecurityCheck();

}


$fhem_started = time;
DoTrigger("global", "INITIALIZED", 1);

my $osuser = "os:$^O user:".(getlogin || getpwuid($<) || "unknown");
Log 0, "Featurelevel: $featurelevel";
Log 0, "Server started with ".int(keys %defs).
        " defined entities ($attr{global}{version} perl:$] $osuser pid:$$)";

################################################
# Main Loop
sub MAIN {MAIN:};               #Dummy


my $errcount= 0;
$gotSig = undef if($gotSig && $gotSig eq "HUP");
while (1) {
  my ($rout,$rin, $wout,$win, $eout,$ein) = ('','', '','', '','');

  my $timeout = HandleTimeout();

  foreach my $p (keys %selectlist) {
    my $hash = $selectlist{$p};
    if(defined($hash->{FD})) {
      vec($rin, $hash->{FD}, 1) = 1
        if(!defined($hash->{directWriteFn}) && !$hash->{wantWrite} );
      vec($win, $hash->{FD}, 1) = 1
        if( (defined($hash->{directWriteFn}) ||
             defined($hash->{$wbName}) || 
             $hash->{wantWrite} ) && !$hash->{wantRead} );
    }
    vec($ein, $hash->{EXCEPT_FD}, 1) = 1
        if(defined($hash->{"EXCEPT_FD"}));
  }
  $timeout = $readytimeout if(keys(%readyfnlist) &&
                              (!defined($timeout) || $timeout > $readytimeout));
  $timeout = 5 if $winService->{AsAService} && $timeout > 5;
  my $nfound = select($rout=$rin, $wout=$win, $eout=$ein, $timeout);

  $winService->{serviceCheck}->() if($winService->{serviceCheck});
  if($gotSig) {
    CommandShutdown(undef, undef) if($gotSig eq "TERM");
    CommandRereadCfg(undef, "")   if($gotSig eq "HUP");
    $gotSig = undef;
  }

  if($nfound < 0) {
    my $err = int($!);
    next if($err==0 || $err==4); # 4==EINTR

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
    next if(!$p);       # Deleted in the loop
    my $hash = $selectlist{$p};
    my $isDev = ($hash && $hash->{NAME} && $defs{$hash->{NAME}});
    my $isDirect = ($hash && ($hash->{directReadFn} || $hash->{directWriteFn}));
    next if(!$isDev && !$isDirect);

    if(defined($hash->{FD}) && vec($rout, $hash->{FD}, 1)) {
      delete $hash->{wantRead};

      if($hash->{directReadFn}) {
        $hash->{directReadFn}($hash);
      } else {
        CallFn($hash->{NAME}, "ReadFn", $hash);
      }
    }

    if( defined($hash->{FD}) && vec($wout, $hash->{FD}, 1)) {
      delete $hash->{wantWrite};

      if($hash->{directWriteFn}) {
        $hash->{directWriteFn}($hash);

      } elsif(defined($hash->{$wbName})) {
        my $wb = $hash->{$wbName};
        alarm($hash->{ALARMTIMEOUT}) if($hash->{ALARMTIMEOUT});

        my $ret;
        eval { $ret = syswrite($hash->{CD}, $wb); };
        if($@) {
          Log 4, "Syswrite: $@, deleting $hash->{NAME}";
          TcpServer_Close($hash);
          CommandDelete(undef, $hash->{NAME});
          next;
        }

        my $werr = int($!);
        alarm(0) if($hash->{ALARMTIMEOUT});

        if(!defined($ret) && $werr == EWOULDBLOCK ) {
          $hash->{wantRead} = 1
            if(TcpServer_WantRead($hash));

        } elsif(!$ret) { # zero=EOF, undef=error
          Log 4, "Write error to $p, deleting $hash->{NAME}";
          TcpServer_Close($hash);
          CommandDelete(undef, $hash->{NAME});

        } else {
          if($ret >= length($wb)) { # for the > see Forum #29963
            delete($hash->{$wbName});
            if($hash->{WBCallback}) {
              no strict "refs";
              my $ret = &{$hash->{WBCallback}}($hash);
              use strict "refs";
              delete $hash->{WBCallback};
            }
          } else {
            $hash->{$wbName} = substr($wb, $ret);
          }
        }
      }
    }

    if(defined($hash->{"EXCEPT_FD"}) && vec($eout, $hash->{EXCEPT_FD}, 1)) {
      CallFn($hash->{NAME}, "ExceptFn", $hash);
    }
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
IsDevice($;$)
{
  my $devname = shift;
  my $devtype = shift;

  return 1
    if ( defined($devname)
      && defined( $defs{$devname} )
      && (!$devtype || $devtype eq "" ) );

  return 1
    if ( defined($devname)
      && defined( $defs{$devname} )
      && defined( $defs{$devname}{TYPE} )
      && $defs{$devname}{TYPE} =~ m/^$devtype$/ );

  return 0;
}

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
     defined($attr{$devname}) && $attr{$devname}{ignore}) {
    Log 4, "Ignoring $devname";
    return 1;
  }
  return 0;
}

sub
IsDisabled($)
{
  my $devname = shift;
  return 0 if(!$devname || !defined($attr{$devname}));

  return 1 if($attr{$devname}{disable});
  return 3 if($defs{$devname} && $defs{$devname}{STATE} &&
              $defs{$devname}{STATE} eq "inactive");
  return 3 if(ReadingsVal($devname, "state", "") eq "inactive");

  my $dfi = $attr{$devname}{disabledForIntervals};
  if(defined($dfi)) {
    $dfi =~ s/{([^\x7d]*)}/$cmdFromAnalyze=$1; eval $1/ge; # Forum #69787
    my ($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst) = localtime;
    my $dhms = sprintf("%s\@%02d:%02d:%02d", $wday, $hour, $min, $sec);
    foreach my $ft (split(" ", $dfi)) {
      my ($from, $to) = split("-", $ft);
      if(defined($from) && defined($to)) {
        $from = "$wday\@$from" if(index($from,"@") < 0);
        $to   = "$wday\@$to"   if(index($to,  "@") < 0);
        return 2 if($from le $dhms && $dhms le $to);
      }
    }
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

sub
GetVerbose($)
{
  my ($dev) = @_;
  if(defined($dev) &&
     defined($attr{$dev}) &&
     defined (my $devlevel = $attr{$dev}{verbose})) {
    return $devlevel;

  } else {
    return $attr{global}{verbose};

  }
}

sub
GetType($;$)
{
  my $devname = shift;
  my $default = shift;

  return $default unless ( IsDevice($devname) && $defs{$devname}{TYPE} );
  return $defs{$devname}{TYPE};
}


################################################
# the new Log with integrated loglevel checking
sub
Log3($$$)
{
  my ($dev, $loglevel, $text) = @_;

  $dev = $dev->{NAME} if(defined($dev) && ref($dev) eq "HASH");
     
  if(defined($dev) &&
     defined($attr{$dev}) &&
     defined (my $devlevel = $attr{$dev}{verbose})) {
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

  no strict "refs";
  foreach my $li (keys %logInform) {
    if($defs{$li}) {
      &{$logInform{$li}}($li, "$tim $loglevel : $text");
    } else {
      delete $logInform{$li};
    }
  }
  use strict "refs";

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

  return if(IsDummy($iohash->{NAME}));

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
AnalyzeCommandChain($$;$)
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

  $cmd =~ s/^\s*#.*$//s; # Remove comments at the beginning of the line

  $cmd =~ s/;;/SeMiCoLoN/g;
  my @saveCmdList = @cmdList;   # Needed for recursive calls
  @cmdList = split(";", $cmd);
  my $subcmd;
  my $localEvalSpecials = $evalSpecials;
  while(defined($subcmd = shift @cmdList)) {
    $subcmd =~ s/SeMiCoLoN/;/g;
    $evalSpecials = $localEvalSpecials;
    my $lret = AnalyzeCommand($c, $subcmd, "ACC");
    push(@ret, $lret) if(defined($lret));
  }
  @cmdList = @saveCmdList;
  $evalSpecials = undef;
  return join("\n", @ret) if(@ret);
  return undef;
}

#####################################
sub
AnalyzePerlCommand($$;$)
{
  my ($cl, $cmd, $calledFromChain) = @_; # third parmeter is deprecated

  return "Forbidden command $cmd." if($cl && !Authorized($cl, "cmd", "perl"));

  $cmd =~ s/\\ *\n/ /g;               # Multi-line. Probably not needed anymore

  # Make life easier for oneliners:
  if($featurelevel <= 5.6) {
    %value = ();
    foreach my $d (keys %defs) {
      $value{$d} = $defs{$d}{STATE}
    }
  }
  my ($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst) = localtime;
  my $hms = sprintf("%02d:%02d:%02d", $hour, $min, $sec);
  my $we = (($wday==0 || $wday==6) ? 1 : 0);
  if(!$we) {
    foreach my $h2we (split(",", AttrVal("global", "holiday2we", ""))) {
      my ($a, $b) = ReplaceEventMap($h2we, [$h2we, Value($h2we)], 0);
      $we = 1 if($b && $b ne "none");
    }
  }
  $month++;
  $year+=1900;
  my $today = sprintf('%04d-%02d-%02d', $year,$month,$mday);

  if($evalSpecials) {
    $cmd = join("", map { my $n = substr($_,1); # ignore the %
                          my $v = $evalSpecials->{$_};
                          $v =~ s/(['\\])/\\$1/g;
                          "my \$$n='$v';";
                        } keys %{$evalSpecials})
           . $cmd;
    # Normally this is deleted in AnalyzeCommandChain, but ECMDDevice calls us
    # directly, and combining perl with something else isnt allowed anyway.
    $evalSpecials = undef if(!$calledFromChain);
  }

  $cmdFromAnalyze = $cmd;
  my $ret = eval $cmd;
  Log 1, "ERROR evaluating $cmd: $@" if($@);
  $ret = $@ if($@);
  $cmdFromAnalyze = undef;
  return $ret;
}

sub
AnalyzeCommand($$;$)
{
  my ($cl, $cmd, $calledFromChain) = @_;

  $cmd = "" if(!defined($cmd)); # Forum #29963
  $cmd =~ s/^(\n|[ \t])*//;# Strip space or \n at the begginning
  $cmd =~ s/[ \t]*$//;

  Log 5, "Cmd: >$cmd<";
  if(!$cmd) {
    $evalSpecials = undef if(!$calledFromChain || $calledFromChain ne "ACC");
    return undef;
  }

  if($cmd =~ m/^{.*}$/s) {              # Perl code
    return AnalyzePerlCommand($cl, $cmd, 1);
  }

  if($cmd =~ m/^"(.*)"$/s) { # Shell code in bg, to be able to call us from it
    return "Forbidden command $cmd." if($cl && !Authorized($cl,"cmd","shell"));
    if($evalSpecials) {
      map { $ENV{substr($_,1)} = $evalSpecials->{$_}; } keys %{$evalSpecials};
      $evalSpecials = undef if(!$calledFromChain || $calledFromChain ne "ACC");
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
    $evalSpecials = undef if(!$calledFromChain || $calledFromChain ne "ACC");
  }
  my ($fn, $param) = split("[ \t][ \t]*", $cmd, 2);
  return undef if(!$fn);


  #############
  # Search for abbreviation
  sub
  getAbbr($$)
  {
    my ($fn,$h) = @_;
    my $lcfn = lc($fn);
    my $fnlen = length($fn);
    return $fn if(defined($h->{$fn}));
    foreach my $f (sort keys %{$h}) {
      if(length($f) >= $fnlen && lc(substr($f,0,$fnlen)) eq $lcfn) {
        Log 5, "AnalyzeCommand: trying $f for $fn";
        return $f;
      }
    }
    return undef;
  }

  my $lfn = getAbbr($fn,\%cmds);
  $fn = $lfn if($lfn);
  $fn = $cmds{$fn}{ReplacedBy}
                if(defined($cmds{$fn}) && defined($cmds{$fn}{ReplacedBy}));

  #############
  # autoload command with ModuleName
  if(!$cmds{$fn} || !defined($cmds{$fn}{Fn})) {
    my $modName;
    $modName = $cmds{$fn}{ModuleName} if($cmds{$fn} && $cmds{$fn}{ModuleName});
    $modName = getAbbr($fn,\%modules) if(!$modName);

    LoadModule($modName) if($modName);
    my $lfn = getAbbr($fn,\%cmds);
    $fn = $lfn if($lfn);
  }

  return "Unknown command $fn, try help." if(!$cmds{$fn} || !$cmds{$fn}{Fn});

  return "Forbidden command $fn." if($cl && !Authorized($cl,"cmd",$fn));

  if($cl && $cmds{$fn}{ClientFilter} &&
     $cl->{TYPE} !~ m/$cmds{$fn}{ClientFilter}/) {
    return "This command ($fn) is not valid for this input channel.";
  }

  $param = "" if(!defined($param));
  no strict "refs";
  my $ret = &{$cmds{$fn}{Fn} }($cl, $param, $fn);
  use strict "refs";
  return undef if(defined($ret) && $ret eq "");
  return $ret;
}

sub
devspec2array($;$)
{
  my ($name, $cl) = @_;

  return "" if(!defined($name));
  if(defined($defs{$name})) {
    if($cl && !Authorized($cl, "devicename", $name)) {
      Log 4, "Forbidden device $name";
      return "";
    }

    # FHEM2FHEM LOG mode fake device, avoid local set/attr/etc operations on it
    return "FHEM2FHEM_FAKE_$name" if($defs{$name}{FAKEDEVICE});
    return $name;
  }

  my (@ret, $isAttr);
  foreach my $l (split(",", $name)) {   # List of elements

    if(defined($defs{$l})) {
      push @ret, $l;
      next;
    }

    my @names = sort keys %defs;
    my @res;
    foreach my $dName (split(":FILTER=", $l)) {
      my ($n,$op,$re) = ("NAME","=",$dName);
      if($dName =~ m/^(.*?)(=|!=|<=|>=|<|>)(.*)$/) {
        ($n,$op,$re) = ($1,$2,$3);
        $isAttr = 1;    # Compatibility: return "" instead of $name
      }
      ($n,$op,$re) = ($1,"eval","") if($dName =~ m/^{(.*)}$/);

      my $fType="";
      if($n =~ m/^(.:)(.*$)/) {
        $fType = $1;
        $n = $2;
      }
      @res=();
      foreach my $d (@names) {
        next if($attr{$d} && $attr{$d}{ignore});

        if($op eq "eval") {
          my $exec = EvalSpecials($n, %{{"%DEVICE"=>$d}});
          push @res, $d if(AnalyzePerlCommand($cl, $exec));
          next;
        }

        my $hash = $defs{$d};
        if(!$hash->{TYPE}) {
          Log 1, "Error: >$d< has no TYPE, but following keys: >".
                                join(",", sort keys %{$hash})."<";
          delete($defs{$d});
          next;
        }
        my $val;
        $val = $hash->{$n} if(!$fType || $fType eq "i:");
        if(!defined($val) && (!$fType || $fType eq "r:")) {
          my $r = $hash->{READINGS};
          $val = $r->{$n}{VAL} if($r && $r->{$n});
        }
        if(!defined($val) && (!$fType || $fType eq "a:")) {
          $val = $attr{$d}{$n} if($attr{$d});
        }
        $val="" if(!defined($val));
        $val = $val->{NAME} if(ref($val) eq 'HASH' && $val->{NAME}); # IODev

        my $lre = ($n eq "room" || $n eq "group") ?
                                "(^|,)($re)(,|\$)" : "^($re)\$";
        my $valReNum =(looks_like_number($val) && looks_like_number($re) ? 1:0);
        eval { # a bad regexp is deadly
          if(($op eq  "=" && $val =~ m/$lre/s) ||
             ($op eq "!=" && $val !~ m/$lre/s) ||
             ($op eq "<"  && $valReNum && $val < $re) ||
             ($op eq ">"  && $valReNum && $val > $re) ||
             ($op eq "<=" && $valReNum && $val <= $re) ||
             ($op eq ">=" && $valReNum && $val >= $re)) {
            push @res, $d 
          }
        };

        if($@) {
          Log 1, "devspec2array $name: $@";
          stacktrace();
          return $name;
        }
      }
      @names = @res;
    }
    push @ret,@res;
  }
  return $name if(!@ret && !$isAttr);
  @ret = grep { Authorized($cl, "devicename", $_) } @ret if($cl);
  return @ret;
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
  my @t = localtime();
  my $gcfg = ResolveDateWildcards(AttrVal("global", "configfile", ""), @t);
  my $stf  = ResolveDateWildcards(AttrVal("global", "statefile",  ""), @t);
  if(!$init_done && $arg ne $stf && $arg ne $gcfg) {
    my $nr =  $devcount++;
    $comments{$nr}{TEXT} = "include $arg";
    $comments{$nr}{CFGFN} = $currcfgfile if($currcfgfile ne $gcfg);
  }
  $oldcfgfile  = $currcfgfile;
  $currcfgfile = $arg;

  my $bigcmd = "";
  $rcvdquit = 0;
  while(my $l = <$fh>) {
    $l =~ s/[\r\n]//g;

    if($l =~ m/^(.*)\\ *$/) {       # Multiline commands
      $bigcmd .= "$1\n";
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

  # STDOUT is closed in windows services per default
  if(!$winService->{AsAService} && $currlogfile eq "-") {
    open LOG, '>&STDOUT' || die "Can't dup stdout: $!";

  } else {

    HandleArchiving($defs{global}) if($defs{global}{currentlogfile});
    $defs{global}{currentlogfile} = $param;
    $defs{global}{logfile} = $attr{global}{logfile};

    open(LOG, ">>$currlogfile") || return("Can't open $currlogfile: $!");
    redirectStdinStdErr();
    
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
  return "Cannot open $cfgfile: $!"
        if(! -f $cfgfile && !configDBUsed());

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
  my $informMe = $inform{$name};
  %inform = ();

  doGlobalDef($cfgfile);
  my $ret;
  
  if(configDBUsed()) {
    $ret = cfgDB_ReadAll($cl);

  } else {
    setGlobalAttrBeforeFork($cfgfile);

    $ret = CommandInclude($cl, $cfgfile);
    if($attr{global}{statefile} && -r $attr{global}{statefile}) {
      my $ret2 = CommandInclude($cl, $attr{global}{statefile});
      $ret = (defined($ret) ? "$ret\n$ret2" : $ret2) if(defined($ret2));
    }
  }

  $defs{$name} = $selectlist{$name} = $cl if($name && $name ne "__anonymous__");
  $inform{$name} = $informMe if($informMe);
  @structChangeHist = ();
  $lastDefChange++;
  DoTrigger("global", "REREADCFG", 1);

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

sub
GetAllReadings($)
{
  my ($d) = @_;
  my @ret;
  my $val = $defs{$d}{STATE};
  if(defined($val) &&
     $val ne "unknown" &&
     $val ne "Initialized" &&
     $val ne "" &&
     $val ne "???") {
    $val =~ s/;/;;/g;
    $val =~ s/([ \t])/sprintf("\\%03o",ord($1))/eg if($val =~ m/^[ \t]*$/);
    $val =~ s/\n/\\\n/g;
    push @ret, "setstate $d $val";
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
      $val =~ s/\n/\\\n/g;
      push @ret,"setstate $d $rd->{TIME} $c $val";
    }
  }
  return @ret;
}

#####################################
sub
WriteStatefile()
{
  if(configDBUsed()) {
    return cfgDB_SaveState();
  }

  my $stateFile = AttrVal('global','statefile',undef);
  return "No statefile specified" if(!defined($stateFile));

  my @t = localtime;
  $stateFile = ResolveDateWildcards($stateFile, @t);

  if(!open(SFH, ">$stateFile")) {
    my $msg = "WriteStatefile: Cannot open $stateFile: $!";
    Log 1, $msg;
    return $msg;
  }

  my $t = localtime;
  print SFH "#$t\n";

  foreach my $d (sort keys %defs) {
    next if($defs{$d}{TEMPORARY});
    if($defs{$d}{VOLATILE}) {
      my $def = $defs{$d}{DEF};
      $def =~ s/;/;;/g; # follow-on-for-timer at
      print SFH "define $d $defs{$d}{TYPE} $def\n";
    }

    my @arr = GetAllReadings($d);
    print SFH join("\n", @arr)."\n" if(@arr);
  }

  return "$attr{global}{statefile}: $!" if(!close(SFH));
  return "";
}

sub
GetDefAndAttr($)
{
  my ($d) = @_;
  my @ret;

  if($d ne "global") {
    my $def = $defs{$d}{DEF};
    if(defined($def)) {
      $def =~ s/;/;;/g;
      $def =~ s/\n/\\\n/g;
      push @ret,"define $d $defs{$d}{TYPE} $def";
    } else {
      push @ret,"define $d $defs{$d}{TYPE}";
    }
  }

  foreach my $a (sort {
                   return -1 if($a eq "userattr"); # userattr must be first
                   return  1 if($b eq "userattr");
                   return $a cmp $b;
                 } keys %{$attr{$d}}) {
    next if($d eq "global" &&
            ($a eq "configfile" || $a eq "version"));
    my $val = $attr{$d}{$a};
    $val =~ s/;/;;/g;
    $val =~ s/\n/\\\n/g;
    push @ret,"attr $d $a $val";
  }
  return @ret;
}

#####################################
sub
CommandSave($$)
{
  my ($cl, $param) = @_;

  if($param && $param eq "?") {
    return "No structural changes." if(!@structChangeHist);
    return "Last 10 structural changes:\n  ".join("\n  ", @structChangeHist);
  }

  if(!$cl && !AttrVal("global", "autosave", 1)) { # Forum #78769
    Log 4, "Skipping save, as autosave is disabled";
    return;
  }
  my $restoreDir;
  $restoreDir = restoreDir_init() if(!configDBUsed());

  @structChangeHist = ();
  DoTrigger("global", "SAVE", 1);

  restoreDir_saveFile($restoreDir, $attr{global}{statefile});
  my $ret = WriteStatefile();

  return $ret if($ret);
  $ret = "";    # cfgDB_SaveState may return undef

  if(configDBUsed()) {
    $ret = cfgDB_SaveCfg();
    return ($ret ? $ret : "Saved configuration to the DB");
  }

  $param = $attr{global}{configfile} if(!$param);
  return "No configfile attribute set and no argument specified" if(!$param);
  restoreDir_saveFile($restoreDir, $param);
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
      restoreDir_saveFile($restoreDir, $cfgfile);
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

    my @arr = GetDefAndAttr($d);
    print $fh join("\n", @arr)."\n" if(@arr);

  }

  print SFH "include $attr{global}{lastinclude}\n"
        if($attr{global}{lastinclude} && $featurelevel <= 5.6);

  foreach my $key (keys %fh) {
    next if($fh{$key} eq "1"); ## R/O include files
    $ret .= "$key: $!" if(!close($fh{$key}));
  }

  return ($ret ? $ret : "Wrote configuration to $param");
}

#####################################
sub
CommandShutdown($$)
{
  my ($cl, $param) = @_;
  my $exitValue = 0;
  if($param && $param =~ m/^(\d+)$/) {
    $exitValue = $1;
    $param = "";
  }
  return "Usage: shutdown [restart|exitvalue]"
        if($param && $param ne "restart");

  DoTrigger("global", "SHUTDOWN", 1);
  Log 0, "Server shutdown";

  foreach my $d (sort keys %defs) {
    CallFn($d, "ShutdownFn", $defs{$d});
  }

  WriteStatefile();
  unlink($attr{global}{pidfilename}) if($attr{global}{pidfilename});
  if($param && $param eq "restart") {
    if ($^O !~ m/Win/) {
      system("(sleep " . AttrVal("global", "restartDelay", 2) .
                                 "; exec $^X $0 $attr{global}{configfile})&");
    } elsif ($winService->{AsAService}) {
      # use the OS SCM to stop and start the service
      exec('cmd.exe /C net stop fhem & net start fhem');
    }
  }
  exit($exitValue);
}


#####################################
sub
ReplaceSetMagic($$@)       # Forum #38276
{
  my $hash = shift;
  my $nsplit = shift;
  my $a = join(" ", @_);
  my $oa = $a;

  sub
  rsmVal($$$$$)
  {
    my ($all, $t, $d, $n, $s, $val) = @_;
    my $hash = $defs{$d};
    return $all if(!$hash);
    if(!$t || $t eq "r:") {
      my $r = $hash->{READINGS};
      if($s && ($s eq ":t" || $s eq ":sec")) {
        return $all if (!$r || !$r->{$n});
        $val = $r->{$n}{TIME};
        $val = time() - time_str2num($val) if($s eq ":sec");
        return $val;
      }
      $val = $r->{$n}{VAL} if($r && $r->{$n});
    }
    $val = $hash->{$n}   if(!defined($val) && (!$t || $t eq "i:"));
    $val = $attr{$d}{$n} if(!defined($val) && (!$t || $t eq "a:") && $attr{$d});
    return $all if(!defined($val));

    if($s && $s =~ /:d|:r|:i/ && $val =~ /(-?\d+(\.\d+)?)/) {
      $val = $1;
      $val = int($val) if ( $s eq ":i" );
      $val = round($val, defined($1) ? $1 : 1) if($s =~ /^:r(\d)?/);
    }
    return $val;
  }

  $a =~s/(\[([ari]:)?([a-zA-Z\d._]+):([a-zA-Z\d._\/-]+)(:(t|sec|i|d|r|r\d))?\])/
         rsmVal($1,$2,$3,$4,$5)/eg;

  my $esDef = ($evalSpecials ? 1 : 0);
  $evalSpecials->{'%DEV'} = $hash->{NAME};
  $a =~ s/{\((.*?)\)}/AnalyzePerlCommand($hash->{CL},$1,1)/egs;
  $evalSpecials = undef if(!$esDef);;

  return (undef, @_) if($oa eq $a);
  return (undef, split(/ /, $a, $nsplit));
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
  return CallFn($dev, "SetFn", $hash,
        $modules{$hash->{TYPE}}->{parseParams} ? parseParams(\@a) : @a)
    if($a[1] && $a[1] eq "?");

  @a = ReplaceEventMap($dev, \@a, 0) if($attr{$dev}{eventMap});
  my $err;
  ($err, @a) = ReplaceSetMagic($hash, 0, @a) if($featurelevel >= 5.7);
  return $err if($err);

  $hash->{".triggerUsed"} = 0; 
  my ($ret, $skipTrigger) = CallFn($dev, "SetFn", $hash, 
                $modules{$hash->{TYPE}}->{parseParams} ? parseParams(\@a) : @a);
  return $ret if($ret);
  return undef if($skipTrigger);

  # Backward compatibility. Use readingsUpdate in SetFn now
  # case: DoSet is called from a notify triggered by DoSet with same dev
  if(defined($hash->{".triggerUsed"}) && $hash->{".triggerUsed"} == 0) {
    shift @a;
    # set arg if the module did not triggered events
    my $arg;
    $arg = join(" ", @a) if(!$hash->{CHANGED} || !int(@{$hash->{CHANGED}}));
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
  foreach my $sdev (devspec2array($a[0], $cl)) {

    $a[0] = $sdev;
    $defs{$sdev}->{CL} = $cl if($defs{$sdev});
    my $ret = DoSet(@a);
    delete $defs{$sdev}->{CL} if($defs{$sdev});
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
  foreach my $sdev (devspec2array($a[0], $cl)) {
    if(!defined($defs{$sdev})) {
      push @rets, "Please define $sdev first";
      next;
    }
    if(!$modules{$defs{$sdev}{TYPE}}{GetFn}) {
      push @rets, "No get implemented for $sdev";
      next;
    }

    $a[0] = $sdev;
    $defs{$sdev}->{CL} = $cl;
    my $ret = CallFn($sdev, "GetFn", $defs{$sdev}, 
        $modules{$defs{$sdev}->{TYPE}}->{parseParams} ? parseParams(\@a) : @a);
    delete $defs{$sdev}->{CL};
    push @rets, $ret if(defined($ret) && $ret ne "");
  }
  return join("\n", @rets);
}

sub
asyncOutput($$)
{
  my ($cl, $ret) = @_;
  return undef if(!$cl || !$cl->{NAME});

  my $temporary;
  if($defs{$cl->{NAME}}) {
    $cl = $defs{$cl->{NAME}}; # Compatibility
  } else {
    $defs{$cl->{NAME}} = $cl; # timeconsuming answer: get fd ist already closed
    $temporary = 1;
  }

  CallFn($cl->{NAME}, "AsyncOutputFn", $cl, $ret);
  delete $defs{$cl->{NAME}} if($temporary);
  return undef;
}

#####################################
sub
LoadModule($;$)
{
  my ($m, $ignoreErr) = @_;

  if($modules{$m} && !$modules{$m}{LOADED}) {   # autoload
    my $o = $modules{$m}{ORDER};
    my $ret = CommandReload(undef, "${o}_$m", $ignoreErr);
    if($ret) {
      Log 0, $ret if(!$ignoreErr);
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
  my @a = split("[ \t]+", $def, 3);
  my ($ignoreErr, $temporary);

  # used by RSS in fhem.cfg.demo, with no GD installed
  if($a[0] && $a[0] eq "-ignoreErr") {
    $def =~ s/\s*-ignoreErr\s*//;
    @a = split("[ \t][ \t]*", $def, 3);
    $ignoreErr = 1;
  }
  if($a[0] && $a[0] eq "-temporary") { # Forum #39610, 46640
    $def =~ s/\s*-temporary\s*//;
    @a = split("[ \t][ \t]*", $def, 3);
    $temporary = 1;
  }

  my $name = $a[0];
  return "Usage: define <name> <type> <type dependent arguments>"
                if(int(@a) < 2);
  return "$name already defined, delete it first" if(defined($defs{$name}));
  return "Invalid characters in name (not A-Za-z0-9._): $name"
                        if(!goodDeviceName($name));

  my $m = $a[1];
  if(!$modules{$m}) {                           # Perhaps just wrong case?
    foreach my $i (keys %modules) {
      if(uc($m) eq uc($i)) {
        $m = $i;
        last;
      }
    }
  }

  my $newm = LoadModule($m, $ignoreErr);
  return "Cannot load module $m" if($newm eq "UNDEFINED");
  $m = $newm;

  return "Unknown module $m" if(!$modules{$m} || !$modules{$m}{DefFn});

  my %hash;

  $hash{NAME}  = $name;
  $hash{TYPE}  = $m;
  $hash{STATE} = "???";
  $hash{DEF}   = $a[2] if(int(@a) > 2);
  $hash{NR}    = $devcount++;
  $hash{CFGFN} = $currcfgfile
        if($currcfgfile ne AttrVal("global", "configfile", ""));
  $hash{CL}    = $cl;

  # If the device wants to issue initialization gets/sets, then it needs to be
  # in the global hash.
  $defs{$name} = \%hash;

  my $ret = CallFn($name, "DefFn", \%hash, 
                $modules{$m}->{parseParams} ? parseParams($def) : $def);
  if($ret) {
    Log 1, "define $def: $ret" if(!$ignoreErr);
    delete $defs{$name};                            # Veto
    delete $attr{$name};

  } else {
    delete $hash{CL};
    $hash{TEMPORARY} = 1 if($temporary);
    foreach my $da (sort keys (%defaultattr)) {     # Default attributes
      CommandAttr($cl, "$name $da $defaultattr{$da}");
    }
    if($modules{$m}{NotifyFn} && !$hash{NTFY_ORDER}) {
      $hash{NTFY_ORDER} = ($modules{$m}{NotifyOrderPrefix} ?
                $modules{$m}{NotifyOrderPrefix} : "50-") . $name;
    }
    %ntfyHash = ();
    addStructChange("define", $name, $def);
    DoTrigger("global", "DEFINED $name", 1) if($init_done);
  }
  return ($ret && $ignoreErr ?
        "Cannot define $name, remove -ignoreErr for details" : $ret);
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
  %ntfyHash = () if($hash->{NTFY_ORDER});

  $hash->{OLDDEF} = $hash->{DEF};
  $hash->{DEF} = $a[1];
  $hash->{CL} = $cl;
  my $ret = CallFn($a[0], "DefFn", $hash,
              $modules{$hash->{TYPE}}->{parseParams} ?
              parseParams("$a[0] $hash->{TYPE}".(defined($a[1]) ? " $a[1]":"")):
              "$a[0] $hash->{TYPE}".(defined($a[1]) ? " $a[1]" : ""));
  delete $hash->{CL};
  if($ret) {
    $hash->{DEF} = $hash->{OLDDEF};
  } else {
    addStructChange("modify", $a[0], $def);
    DoTrigger("global", "MODIFIED $a[0]", 1) if($init_done);
  }

  delete($hash->{OLDDEF});
  return $ret;
}

#####################################
sub
CommandDefMod($$)
{
  my ($cl, $def) = @_;
  my @a = split("[ \t]+", $def, 3);
  return "Usage: defmod <name> <type> <type dependent arguments>"
                if(int(@a) < 2);
  if($defs{$a[0]}) {
    $def = $a[2] ? "$a[0] $a[2]" : $a[0];
    return "defmod $a[0]: Cannot change the TYPE of an existing definition"
        if($a[1] ne $defs{$a[0]}{TYPE});
    return CommandModify($cl, $def);
  } else {
    return CommandDefine($cl, $def);
  }
}

#############
# internal
sub
AssignIoPort($;$)
{
  my ($hash, $proposed) = @_;
  my $ht = $hash->{TYPE};
  my $hn = $hash->{NAME};
  my $hasIODevAttr = ($ht &&
                      $modules{$ht}{AttrList} &&
                      $modules{$ht}{AttrList} =~ m/IODev/);

  $proposed = $attr{$hn}{IODev}
        if(!$proposed && $attr{$hn} && $attr{$hn}{IODev});
  
  if($proposed && $defs{$proposed} && !IsDisabled($proposed)) {
    $hash->{IODev} = $defs{$proposed};
    $attr{$hn}{IODev} = $proposed if($hasIODevAttr);
    delete($defs{$proposed}{".clientArray"});
    return;
  }
  # Set the I/O device, search for the last compatible one.
  for my $p (sort { $defs{$b}{NR} <=> $defs{$a}{NR} } keys %defs) {

    next if(IsDisabled($p));
    my $cl = $defs{$p}{Clients};
    $cl = $modules{$defs{$p}{TYPE}}{Clients} if(!$cl);

    if($cl && $defs{$p}{NAME} ne $hn) {      # e.g. RFR
      my @fnd = grep { $hash->{TYPE} =~ m/^$_$/; } split(":", $cl);
      if(@fnd) {
        $hash->{IODev} = $defs{$p};
        delete($defs{$p}{".clientArray"}); # Force a recompute
        last;
      }
    }
  }
  if($hash->{IODev}) {
    # See CUL_WS_Attr() for details
    $attr{$hn}{IODev} = $hash->{IODev}{NAME}
      if($hasIODevAttr && $hash->{TYPE} ne "CUL_WS");

  } else {
    if($init_done) {
      Log 3, "No I/O device found for $hn";
    } else {
      $hash->{IODevMissing} = 1;
    }
  }
  return undef;
}


#############
sub
CommandDelete($$)
{
  my ($cl, $def) = @_;
  return "Usage: delete <name>$namedef\n" if(!$def);

  my @rets;
  foreach my $sdev (devspec2array($def, $cl)) {
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

    my $temporary = $defs{$sdev}{TEMPORARY};
    addStructChange("delete", $sdev, $sdev) if(!$temporary);
    delete($attr{$sdev});
    delete($defs{$sdev});
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
  foreach my $sdev (devspec2array($a[0], $cl)) {

    if(!defined($defs{$sdev})) {
      push @rets, "Please define $sdev first";
      next;
    }

    $a[0] = $sdev;
    
    if($a[1] && $a[1] eq "userReadings") {
      delete($defs{$sdev}{'.userReadings'});
    }

    my $ret = CallFn($sdev, "AttrFn", "del", @a);
    if($ret) {
      push @rets, $ret;
      next;
    }

    if(@a == 1) {
      delete($attr{$sdev});
      addStructChange("deleteAttr", $sdev, $sdev);
      DoTrigger("global", "DELETEATTR $sdev", 1) if($init_done);

    } else {
      delete($attr{$sdev}{$a[1]}) if(defined($attr{$sdev}));
      addStructChange("deleteAttr", $sdev, join(" ", @a));
      DoTrigger("global", "DELETEATTR $sdev $a[1]", 1) if($init_done);

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
  my @devspec = devspec2array($a[0],$cl);

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

  eval { "" =~ m/$a[1]/ };
  return "Bad regexp $a[1]: $@" if($@);

  %ntfyHash = ();
  my @rets;
  foreach my $sdev (devspec2array($a[0],$cl)) {

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

sub
CommandSetReading($$)
{
  my ($cl, $def) = @_;

  my @a = split(" ", $def, 3);
  return "Usage: setreading <name> <reading> <value>\n$namedef" if(@a != 3);

  my $err;
  my @b = @a;
  my @rets;
  foreach my $sdev (devspec2array($a[0],$cl)) {

    if(!defined($defs{$sdev})) {
      push @rets, "Please define $sdev first";
      next;
    }
    my $hash = $defs{$sdev};
    if($featurelevel >= 5.7) {
      $hash->{CL} = $cl;
      ($err, @b) = ReplaceSetMagic($hash, 3, @a);
      delete $hash->{CL};
    }
    readingsSingleUpdate($defs{$sdev}, $b[1], $b[2], 1);
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
          $sstr .= sprintf("%*s %s:\n", $lev, " ", $c);
          $sstr .= PrintHash($h->{$c}, $lev+2);
        }
      } elsif(ref($h->{$c}) eq "ARRAY") {
         $sstr .= sprintf("%*s %s:\n", $lev, " ", $c);
         foreach my $v (@{$h->{$c}}) {
           $sstr .= sprintf("%*s %s\n", $lev+2, " ", defined($v) ? $v:"undef");
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

  if($param =~ m/^-r *(.*)$/i) {
    my @list;
    my $arg = $1;
    if($param =~ m/^-R/) {
      return "-R needs a valid device as argument" if(!$arg);
      push @list, $arg;
      push @list, getPawList($arg);
    } else {
      @list = devspec2array($arg ? $arg : ".*", $cl);
    }
    foreach my $d (@list) {
      return "No device named $d found" if(!defined($defs{$d}));
      $str .= "\n" if($str);
      my @a = GetDefAndAttr($d);
      $str .= join("\n", @a)."\n" if(@a);
    }
    foreach my $d (sort @list) {
      $str .= "\n" if($str);
      my @a = GetAllReadings($d);
      $str .= join("\n", @a)."\n" if(@a);
    }
    return $str;
  }

  if(!$param) { # List of all devices

    $str = "\nType list <name> for detailed info.\n";
    my $lt = "";

    # Sort first by type then by name
    for my $d (sort { my $x=$modules{$defs{$a}{TYPE}}{ORDER}.$defs{$a}{TYPE} cmp
                            $modules{$defs{$b}{TYPE}}{ORDER}.$defs{$b}{TYPE};
                         $x=($a cmp $b) if($x == 0); $x; } keys %defs) {
      next if(IsIgnored($d) || ($cl && !Authorized($cl,"devicename",$d)));
      my $t = $defs{$d}{TYPE};
      $str .= "\n$t:\n" if($t ne $lt);
      $str .= sprintf("  %-20s (%s)\n", $d, $defs{$d}{STATE});
      $lt = $t;
    }

  } else { # devspecArray

    my @arg = split(" ", $param);
    my @list = devspec2array($arg[0],$cl);
    if($arg[1]) {
      foreach my $sdev (@list) { # Show a Hash-Entry or Reading for each device

        my $first = 1;
        foreach  my $n (@arg[1..@arg-1]) {
          my $n = $n; # Forum #53223, for some perl versions $n is a reference
          my $fType="";
          if($n =~ m/^(.:)(.*$)/) {
            $fType = $1;
            $n = $2;
          }    

          if($defs{$sdev}) {
            if(defined($defs{$sdev}{$n}) && (!$fType || $fType eq "i:")) {
              my $val = $defs{$sdev}{$n};
              if(ref($val) eq 'HASH') {
                $val = ($val->{NAME} ? $val->{NAME} : # ???
                        join(" ", map { "$_=$val->{$_}" } sort keys %{$val}));
              }
              $str .= sprintf("%-20s %*s   %*s %s\n", $first?$sdev:'',
                        $arg[2]?19:0, '', $arg[2]?-15:0, $arg[2]?$n:'', $val);

            } elsif($defs{$sdev}{READINGS} &&
                    defined($defs{$sdev}{READINGS}{$n})
                    && (!$fType || $fType eq "r:")) {
              $str .= sprintf("%-20s %s   %*s %s\n", $first?$sdev:'',
                      $defs{$sdev}{READINGS}{$n}{TIME},
                      $arg[2]?-15:0, $arg[2]?$n:'', 
                      $defs{$sdev}{READINGS}{$n}{VAL});

            } elsif($attr{$sdev} && 
                    defined($attr{$sdev}{$n})
                    && (!$fType || $fType eq "a:")) {
              $str .= sprintf("%-20s %*s   %*s %s\n", $first?$sdev:'',
                        $arg[2]?19:0, '', $arg[2]?-15:0, $arg[2]?$n:'',
                        $attr{$sdev}{$n});

            }
          }
          $first = 0;
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
CommandReload($$;$)
{
  my ($cl, $param, $ignoreErr) = @_;
  my %hash;
  $param =~ s,/,,g;
  $param =~ s,\.pm$,,g;
  my $file = "$attr{global}{modpath}/FHEM/$param.pm";
  my $cfgDB = '-';
  if( ! -r "$file" ) {
    if(configDBUsed()) {
      # try to find the file in configDB
      my $r = _cfgDB_Fileexport($file); # create file temporarily
      return "Can't read $file from configDB." if ($r =~ m/^0/);
      $cfgDB = 'X';
    } else {
      # configDB not used and file not found: it's a real error!
      return "Can't read $file: $!";
    }
  }

  my $m = $param;
  $m =~ s,^([0-9][0-9])_,,;
  my $order = (defined($1) ? $1 : "00");
  Log 5, "Loading $file";

  no strict "refs";
  my $ret = eval {
    my $ret=do "$file";
    unlink($file) if($cfgDB eq 'X'); # delete temp file
    if(!$ret) {
      Log 1, "reload: Error:Modul $param deactivated:\n $@" if(!$ignoreErr);
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
  $modules{$m}{ldata} = $ldata if($ldata);

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
  return "Invalid characters in name (not A-Za-z0-9._): $new"
                        if(!goodDeviceName($new));
  return "Cannot rename global" if($old eq "global");

  %ntfyHash = ();
  $defs{$new} = $defs{$old};
  $defs{$new}{NAME} = $new;
  delete($defs{$old});          # The new pointer will preserve the hash

  $attr{$new} = $attr{$old} if(defined($attr{$old}));
  delete($attr{$old});

  $oldvalue{$new} = $oldvalue{$old} if(defined($oldvalue{$old}));
  delete($oldvalue{$old});

  CallFn($new, "RenameFn", $new,$old);# ignore replies

  addStructChange("rename", $new, $param);
  DoTrigger("global", "RENAMED $old $new", 1);
  return undef;
}

#####################################
sub
getAllAttr($;$)
{
  my ($d, $cl) = @_;
  return "" if(!$defs{$d});

  my $list = $AttrList; # Global values
  $list .= " " . $modules{$defs{$d}{TYPE}}{AttrList}
        if($modules{$defs{$d}{TYPE}}{AttrList});
  $list .= " " . $attr{global}{userattr}
        if($attr{global}{userattr});
  $list .= " " . $attr{$d}{userattr}
        if($attr{$d} && $attr{$d}{userattr});
  $list .= " userattr";
  return $list;
}

#####################################
sub
getAllGets($;$)
{
  my ($d, $cl) = @_;
  
  my $a2 = CommandGet($cl, "$d ?");
  return "" if($a2 !~ m/unknown.*choose one of /i);
  $a2 =~ s/.*choose one of //;
  return $a2;
}

#####################################
sub
getAllSets($;$)
{
  my ($d, $cl) = @_;
  return "" if(!$defs{$d});      # Just safeguarding
  
  if(AttrVal("global", "apiversion", 1)> 1) {
    my @setters= getSetters($defs{$d});
    return join(" ", @setters);
  }

  my $a2 = CommandSet($cl, "$d ?");
  $a2 =~ s/.*choose one of //;
  $a2 = "" if($a2 =~ /^No set implemented for/);
  return "" if($a2 eq "");

  $a2 = $defs{$d}{".eventMapCmd"}." $a2" if(defined($defs{$d}{".eventMapCmd"}));
  return $a2;
}

sub
GlobalAttr($$$$)
{
  my ($type, $me, $name, $val) = @_;

  if($type eq "del") {
    my %noDel = ( modpath=>1, verbose=>1, logfile=>1 );
    return "The global attribute $name cannot be deleted" if($noDel{$name});
    $featurelevel = 5.8 if($name eq "featurelevel");
    $haveInet6    = 0   if($name eq "useInet6"); # IPv6
    return undef;
  }

  return undef if($type ne "set");
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
    push @INC, $modpath if(!grep(/\Q$modpath\E/, @INC));
    $cvsid =~ m/(fhem.pl) (\d+) (\d+-\d+-\d+)/;
    $attr{global}{version} = "$1:$2/$3";
    my $counter = 0;

    if(configDBUsed()) {
      my $list = cfgDB_Read99(); # retrieve filelist from configDB
      if($list) {
        foreach my $m (split(/,/,$list)) {
          $m =~ m/^([0-9][0-9])_(.*)\.pm$/;
          CommandReload(undef, $m) if(!$modules{$2}{LOADED});
          $counter++;
        }
      }
    }

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
  elsif($name eq "featurelevel") {
    return "$val is not in the form N.N" if($val !~ m/^\d+\.\d+$/);
    $featurelevel = $val;
    
  }
  elsif($name eq "commandref" && $init_done) {
    my $root = $attr{global}{modpath};
    my $out = "";
    $out = ">> $currlogfile 2>&1" if($currlogfile ne "-" && $^O ne "MSWin32");
    if($val eq "full") {
      system("$^X $root/contrib/commandref_join.pl -noWarnings $out")
    } else {
      system("$^X $root/contrib/commandref_modular.pl $out");
    }
  }
  elsif($name eq "useInet6") {
    if($val || !defined($val)) {
      eval { require IO::Socket::INET6; require Socket6; };
      return $@ if($@);
      $haveInet6 = 1;
    } else {
      $haveInet6 = 0;
    }
  }

  return undef;
}

#####################################
sub
CommandAttr($$)
{
  my ($cl, $param) = @_;
  my ($ret, @a);

  @a = split(" ", $param, 3) if($param);

  return "Usage: attr <name> <attrname> [<attrvalue>]\n$namedef"
           if(@a && @a < 2);

  my @rets;
  foreach my $sdev (devspec2array($a[0],$cl)) {

    my $hash = $defs{$sdev};
    my $attrName = $a[1];
    if(!defined($hash)) {
      push @rets, "Please define $sdev first" if($init_done);#define -ignoreErr
      next;
    }

    my $list = getAllAttr($sdev);
    if($attrName eq "?") {
      push @rets, "$sdev: unknown attribute $attrName, choose one of $list";
      next;
    }

    if(" $list " !~ m/ ${attrName}[ :;]/) {
       my $found = 0;
       foreach my $atr (split("[ \t]", $list)) { # is it a regexp?
         $atr =~ /^([^;:]+)(:.*)?$/;
         my $base = $1;
         if(${attrName} =~ m/^$base$/) {
           $found++;
           last;
         }
      }
      if(!$found) {
        push @rets, "$sdev: unknown attribute $attrName. ".
                        "Type 'attr $a[0] ?' for a detailed list.";
        next;
      }
    }

    if($attrName eq 'disable' and $a[2] && $a[2] eq 'toggle') {
       $a[2] = IsDisabled($sdev) ? 0 : 1;
    }

    if($attrName eq "userReadings") {

      my @userReadings;
      # myReading1[:trigger1] [modifier1] { codecodecode1 }, ...
      my $arg= $a[2];

      # matches myReading1[:trigger2] { codecode1 }
      my $regexi= '\s*([\w.-]+)(:\S*)?\s+((\w+)\s+)?({.*?})\s*';
      my $regexo= '^(' . $regexi . ')(,\s*(.*))*$';
      my $rNo=0;

      while($arg =~ /$regexo/s) {
        my $reading= $2;
        my $trigger= $3 ? $3 : undef;
        my $modifier= $5 ? $5 : "none";
        my $perlCode= $6;
        #Log 1, sprintf("userReading %s has perlCode %s with modifier %s%s",
        # $userReading,$perlCode,$modifier,$trigger?" and trigger $trigger":"");
        if(grep { /$modifier/ }
                qw(none difference differential offset monotonic integral)) {
          $trigger =~ s/^:// if($trigger);
          my %userReading = ( reading => $reading,
                              trigger => $trigger,
                              modifier => $modifier,
                              perlCode => $perlCode );
          push @userReadings, \%userReading;
        } else {
          push @rets, "$sdev: unknown modifier $modifier for ".
                "userReading $reading, this userReading will be ignored";
        }
        $arg= defined($8) ? $8 : "";
      }
      $hash->{'.userReadings'}= \@userReadings;
    } 

    $a[0] = $sdev;
    my $oVal = ($attr{$sdev} ? $attr{$sdev}{$attrName} : "");

    if($attrName eq "eventMap") {
      delete $hash->{".eventMapHash"};
      delete $hash->{".eventMapCmd"};
      $attr{$sdev}{eventMap} = (defined $a[2] ? $a[2] : 1);
      my $r = ReplaceEventMap($sdev, "test", 1); # refresh eventMapCmd
      if($r =~ m/^ERROR in eventMap for /) {
        delete($attr{$sdev}{eventMap});
        return $r;
      }
    }

    my %ra = (
      "suppressReading"            => { s=>"\n" },
      "event-on-update-reading"    => { s=>"," },
      "event-on-change-reading"    => { s=>",", r=>":.*" },
      "timestamp-on-change-reading"=> { s=>"," },
      "event-min-interval"         => { s=>",", r=>";.*" },
      "devStateIcon"               => { s=>" ", r=>":.*", p=>"^{.*}\$",
                                  pv=>{"%name"=>1, "%state"=>1, "%type"=>1} },
    );

    if(defined($a[2]) && $ra{$attrName} && $init_done) {
      my ($lval,$rp) = ($a[2], $ra{$attrName}{p});

      if($rp && $lval =~ m/$rp/) {
        my $err = perlSyntaxCheck($a[2], %{$ra{$attrName}{pv}});
        return "attr $sdev $a[1]: $err" if($err);

      } else {
        for my $v (split($ra{$attrName}{s}, $lval)) {
          $v =~ s/$ra{$attrName}{r}// if($ra{$attrName}{r});
          my $err = "Argument $v for attr $sdev $a[1] is not a valid regexp";
          return "$err: use .* instead of *" if($v =~ /^\*/); # no err in eval!?
          eval { "Hallo" =~ m/^$v$/ };
          return "$err: $@" if($@);
        }
      }
    }

    if($fhemdebug && $sdev eq "global") {
      $a[2] = "-" if($attrName eq "logfile");
      $a[2] = 5   if($attrName eq "verbose");
    }
    $ret = CallFn($sdev, "AttrFn", "set", @a);
    if($ret) {
      push @rets, $ret;
      next;
    }

    my $val = $a[2];
    $val = 1 if(!defined($val));
    $attr{$sdev}{$attrName} = $val;

    if($attrName eq "IODev") {
      if(!$a[2] || !defined($defs{$a[2]})) {
        if($init_done) {
          push @rets,"$sdev: unknown IODev $a[2] specified";
        } else {
          $hash->{IODevMissing} = 1;
          $hash->{IODevName} = $a[2];
        }
        next;
      }

      my $ioname = $a[2];
      $hash->{IODev} = $defs{$ioname};
      delete($defs{$ioname}{".clientArray"}); # Force a recompute
    }
    if($attrName eq "stateFormat" && $init_done) {
      my $err = perlSyntaxCheck($a[2], ("%name"=>""));
      return $err if($err);
      evalStateFormat($hash);
    }
    addStructChange("attr", $sdev, $param) if(!defined($oVal) || $oVal ne $val);
    DoTrigger("global", "ATTR $sdev $attrName $val", 1) if($init_done);

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
  foreach my $sdev (devspec2array($a[0],$cl)) {
    if(!defined($defs{$sdev})) {
      push @rets, "Please define $sdev first";
      next;
    }

    my $d = $defs{$sdev};

    # Detailed state with timestamp
    if($a[1] =~ m/^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) +([^ ].*)$/s) {
      my ($tim, $nameval) =  ($1, $2);
      my ($sname, $sval) = split(" ", $nameval, 2);
      $sval = "" if(!defined($sval));
      my $ret = CallFn($sdev, "StateFn", $d, $tim, $sname, $sval);
      if($ret) {
        push @rets, $ret;
        next;
      }

      Log3 $d, 3, "WARNING: unsupported character in reading $sname ".
             "(not A-Za-z/\\d_\\.-), notify the $d->{TYPE} module maintainer."
        if(!goodReadingName($sname));

      if(!defined($d->{READINGS}{$sname}) ||
         !defined($d->{READINGS}{$sname}{TIME}) ||
         $d->{READINGS}{$sname}{TIME} lt $tim) {
        $d->{READINGS}{$sname}{VAL} = $sval;
        $d->{READINGS}{$sname}{TIME} = $tim;
      }

    } else {

      # The timestamp is not the correct one, but we do not store a timestamp
      # for this reading.
      my $tn = TimeNow();
      $a[1] =~ s/\\(...)/chr(oct($1))/ge if($a[1] =~ m/^(\\011|\\040)+$/);
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
  foreach my $sdev (devspec2array($dev,$cl)) {
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
WakeUpFn($)
{
  my $h = shift;
  delete $sleepers{$h->{id}} if( $h->{id} );

  $evalSpecials = $h->{evalSpecials};
  my $ret = AnalyzeCommandChain($h->{cl}, $h->{cmd});
  Log 2, "After sleep: $ret" if($ret && !$h->{quiet});
}
sub
CommandCancel($$)
{
  my ($cl, $param) = @_;
  my ($id, $quiet) = split(" ", $param, 3);
  return "Last parameter must be quiet" if($quiet && $quiet ne "quiet");

  if( !$id ) {
    my $ret;
    foreach $id (keys %sleepers) {
      $ret .= "\n" if( $ret );
      $ret .= sprintf( "%-10s %s", $id, $sleepers{$id}->{cmd} );
    }
    $ret = "no pending sleeps" if( !$ret );
    return $ret;

  } elsif( my $h = $sleepers{$id} ) {
    RemoveInternalTimer( $h );
    delete $sleepers{$h->{id}};

  } else {
    return "no such id: $id" if( !$quiet );

  }

  return undef;
}

sub
CommandSleep($$)
{
  my ($cl, $param) = @_;
  my ($sec, $id, $quiet) = split(" ", $param, 3);
  if( $id && $id eq 'quiet' ) {
    $quiet = $id;
    $id = undef;
  }

  return "Argument missing" if(!defined($sec));
  return "Cannot interpret $sec as seconds" if($sec !~ m/^[0-9\.]+$/);
  return "Last parameter must be quiet" if($quiet && $quiet ne "quiet");

  Log 4, "sleeping for $sec";

  if(@cmdList && $init_done) {
    my %h = (cmd          => join(";", @cmdList),
             evalSpecials => $evalSpecials,
             quiet        => $quiet,
             cl           => $cl,
             id           => $id);
    if( $id ) {
      RemoveInternalTimer( $sleepers{$id} ) if( $sleepers{$id} );
      $sleepers{$id} = \%h;
    }
    InternalTimer(gettimeofday()+$sec, "WakeUpFn", \%h, 0);
    @cmdList=();

  } else {
    Log 1,
     "WARNING: sleep without additional commands is deprecated and blocks FHEM";
    select(undef, undef, undef, $sec);

  }
  return undef;
}

#####################################
# Add a function to be executed after select returns. Only one function is
# executed after select returns.
# fn:   a function reference
# arg:  function argument
# nice: a number like in unix "nice". Smaller numbers mean higher priority.
#       limited to [-20,19], default 0
# returns the number of elements in the corrsponding queue
sub
PrioQueue_add($$;$)
{
  my ($fn, $arg, $nice) = @_;

  $nice =   0 if(!defined($nice) || !looks_like_number($nice));
  $nice = -20 if($nice <-20);
  $nice =  19 if($nice > 19);
  $nextat = 1;
  $prioQueues{$nice} = [] if(!defined $prioQueues{$nice});
  push(@{$prioQueues{$nice}},{fn=>$fn, arg=>$arg});
};


#####################################
# Return the time to the next event (or undef if there is none)
# and call each function which was scheduled for this time
sub
HandleTimeout()
{
  return undef if(!$nextat);

  my $now = gettimeofday();
  if($now < $nextat) {
    $selectTimestamp = $now;
    return ($nextat-$now);
  }

  $nextat = 0;
  #############
  # Check the internal list.
  foreach my $i (sort { $intAt{$a}{TRIGGERTIME} <=>
                        $intAt{$b}{TRIGGERTIME} }
                 grep { $intAt{$_}{TRIGGERTIME} <= $now } # sort is slow
                        keys %intAt) {
    $i = "" if(!defined($i)); # Forum #40598
    next if(!$intAt{$i}); # deleted in the loop
    my $tim = $intAt{$i}{TRIGGERTIME};
    my $fn = $intAt{$i}{FN};
    if(!defined($tim) || !defined($fn)) {
      delete($intAt{$i});
      next;
    }
    no strict "refs";
    &{$fn}($intAt{$i}{ARG});
    use strict "refs";
    delete($intAt{$i});
  }

  foreach my $i (keys %intAt) {
    my $tim = $intAt{$i}{TRIGGERTIME};
    $nextat = $tim if(defined($tim) && (!$nextat || $nextat > $tim));
  }

  if(%prioQueues) {
    my $nice = minNum(keys %prioQueues);
    my $entry = shift(@{$prioQueues{$nice}});
    delete $prioQueues{$nice} if(!@{$prioQueues{$nice}});
    &{$entry->{fn}}($entry->{arg});
    $nextat = 1 if(%prioQueues);
  }
 
  if(!$nextat) {
    $selectTimestamp = $now;
    return undef;
  }

  $now = gettimeofday(); # if some callbacks took longer
  $selectTimestamp = $now;

  return ($now < $nextat) ? ($nextat-$now) : 0;
}


#####################################
sub
InternalTimer($$$;$)
{
  my ($tim, $fn, $arg, $waitIfInitNotDone) = @_;

  $tim = 1 if(!$tim);
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

sub
RemoveInternalTimer($;$)
{
  my ($arg, $fn) = @_;
  return if(!$arg && !$fn);
  foreach my $a (keys %intAt) {
    delete($intAt{$a}) if((!$arg || $intAt{$a}{ARG} eq $arg) && 
                          (!$fn  || $intAt{$a}{FN} eq $fn));
  }
}

#####################################
sub
stacktrace()
{
  my $i = 1;
  my $max_depth = 50;
  
  # Forum #59831
  Log 1, "eval: $cmdFromAnalyze"
        if($cmdFromAnalyze && $attr{global}{verbose} < 3);
  Log 1, "stacktrace:";
  while( (my @call_details = (caller($i++))) && ($i<$max_depth) ) {
    Log 1, sprintf ("    %-35s called by %s (%s)",
               $call_details[3], $call_details[1], $call_details[2]);
  }
}

my $inWarnSub;

sub
SignalHandling()
{
  if($^O ne "MSWin32") {
    $SIG{TERM} = sub { $gotSig = "TERM"; };
    $SIG{PIPE} = 'IGNORE';
    $SIG{CHLD} = 'IGNORE';
    $SIG{HUP}  = sub { $gotSig = "HUP"; };
    $SIG{ALRM} = sub { Log 1, "ALARM signal, blocking write?" };
    #$SIG{'XFSZ'} = sub { Log 1, "XFSZ signal" }; # to test with limit filesize 
  }
  $SIG{__WARN__} = sub {
    my ($msg) = @_;

    return if($inWarnSub);
    $lastWarningMsg = $msg;
    if(!$attr{global}{stacktrace} && $data{WARNING}{$msg}) {
      $data{WARNING}{$msg}++;
      return;
    }
    $inWarnSub = 1;
    $data{WARNING}{$msg}++;
    chomp($msg);
    Log 1, "PERL WARNING: $msg"; 
    Log 3, "eval: $cmdFromAnalyze" if($cmdFromAnalyze);
    stacktrace() if($attr{global}{stacktrace} &&
                    $msg !~ m/ redefined at /);
    $inWarnSub = 0;
  };  
  # $SIG{__DIE__} = sub {...} #Removed. Forum #35796
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

sub
FmtDateTimeRFC1123($)
{
  my $t = gmtime(shift);
  if($t =~ m/^(...) (...) (..) (..:..:..) (....)$/) {
    return sprintf("$1, %02d $2 $5 $4 GMT", $3);
  }
  return $t;
}


#####################################
sub
ResolveDateWildcards($@)
{
  use POSIX qw(strftime);

  my ($f, @t) = @_;
  return $f if(!$f);
  return $f if($f !~ m/%/);     # Be fast if there is no wildcard
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
  # $NAME will be replaced with the device name which generated the event
  # $EVENT will be replaced with the whole event string
  # $EVTPART<N> will be replaced with single words of an event
  my ($exec, %specials)= @_;
  if($specials{__UNIQUECMD__}) {
    delete $specials{__UNIQUECMD__};
  } else {
    $exec = SemicolonEscape($exec);
  }

  my $idx = 0;
  if(defined($specials{"%EVENT"})) {
    foreach my $part (split(" ", $specials{"%EVENT"})) {
      $specials{"%EVTPART$idx"} = $part;
      $idx++;
    }
  }

  if($featurelevel > 5.6) {
    $evalSpecials = \%specials;
    return $exec;
  }

  # featurelevel <= 5.6 only:
  # The character % will be replaced with the received event,
  #     e.g. with on or off or measured-temp: 21.7 (Celsius)
  # The character @ will be replaced with the device name.
  # To use % or @ in the text itself, use the double mode (%% or @@).

  my $re = join("|", keys %specials); # Found the $syntax, skip the rest
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
# Parse a timespec: HH:MM:SS, HH:MM or { perfunc() }
sub
GetTimeSpec($)
{
  my ($tspec) = @_;
  my ($hr, $min, $sec, $fn);

  if($tspec =~ m/^([0-9]+):([0-5][0-9]):([0-5][0-9])$/) { # HH:MM:SS
    ($hr, $min, $sec) = ($1, $2, $3);

  } elsif($tspec =~ m/^([0-9]+):([0-5][0-9])$/) {         # HH:MM
    ($hr, $min, $sec) = ($1, $2, 0);

  } elsif($tspec =~ m/^{(.*)}$/) {                        # {function}
    $fn = $1;
    $tspec = AnalyzeCommand(undef, "{$fn}");
    $tspec = "<empty string>" if(!$tspec);
    my ($err, $fn2);
    ($err, $hr, $min, $sec, $fn2) = GetTimeSpec($tspec);
    return ("the function \"$fn\" must return a timespec and not $tspec.",
                undef, undef, undef, undef) if($err);

  } else {
    return ("Wrong timespec $tspec: either HH:MM:SS or {perlcode}",
                undef, undef, undef, undef);
  }
  return (undef, $hr, $min, $sec, $fn);
}


sub
deviceEvents($$)
{
  my ($hash, $withState) = @_; # withState returns stateEvent as state:event

  return undef if(!$hash || !$hash->{CHANGED});

  if($withState) {
    my $cws = $hash->{CHANGEDWITHSTATE};
    if(defined($cws)){
      if(int(@{$cws}) == 0) {
        if($hash->{READINGS} && $hash->{READINGS}{state}) {
          my $ostate = $hash->{READINGS}{state}{VAL};
          my $mstate = ReplaceEventMap($hash->{NAME}, $ostate, 1);
          @{$cws} = map { $_ eq $mstate ? "state: $ostate" : $_ }
                        @{$hash->{CHANGED}};
        } else {
          @{$cws} = @{$hash->{CHANGED}};
        }
      }
      return $cws;
    }
  }
  return $hash->{CHANGED};
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
  if(AttrVal($dev, "do_not_notify", 0)) {
    delete($hash->{CHANGED});
    delete($hash->{CHANGETIME});
    delete($hash->{CHANGEDWITHSTATE});
    return "";
  }
  my $now = TimeNow();

  ################
  # Log/notify modules
  # If modifying a device in its own trigger, do not call the triggers from
  # the inner loop.
  if($max && !defined($hash->{INTRIGGER})) {
    $hash->{INTRIGGER}=1;
    if($attr{global}{verbose} >= 5) {
      Log 5, "Starting notify loop for $dev, " . scalar(@{$hash->{CHANGED}}) . 
        " event(s), first is " . escapeLogLine($hash->{CHANGED}->[0]);
    }
    createNtfyHash() if(!%ntfyHash);
    $hash->{NTFY_TRIGGERTIME} = $now; # Optimize FileLog
    my $ntfyLst = (defined($ntfyHash{$dev}) ? $ntfyHash{$dev} : $ntfyHash{"*"});
    foreach my $n (@{$ntfyLst}) {
      next if(!defined($defs{$n}));     # Was deleted in a previous notify
      my $r = CallFn($n, "NotifyFn", $defs{$n}, $hash);
      $ret .= " $n:$r" if($r);
    }
    delete($hash->{NTFY_TRIGGERTIME});
    Log 5, "End notify loop for $dev";

    ################
    # Inform
    if($hash->{CHANGED}) {    # It gets deleted sometimes (?)
      foreach my $c (keys %inform) {
        my $dc = $defs{$c};
        if(!$dc || $dc->{NR} != $inform{$c}{NR}) {
          delete($inform{$c});
          next;
        }
        next if($inform{$c}{type} eq "raw");
        my $tn = $now;
        if($attr{global}{mseclog}) {
          my ($seconds, $microseconds) = gettimeofday();
          $tn .= sprintf(".%03d", $microseconds/1000);
        }
        my $re = $inform{$c}{regexp};
        my $events = deviceEvents($hash, $inform{$c}{type} =~ m/WithState/);
        $max = int(@{$events});
        for(my $i = 0; $i < $max; $i++) {
          my $event = $events->[$i];
          next if($re && !($dev =~ m/$re/ || "$dev:$event" =~ m/$re/));
          addToWritebuffer($dc,($inform{$c}{type} eq "timer" ? "$tn " : "").
                                "$hash->{TYPE} $dev $event\n");
        }
      }
    }

    delete($hash->{INTRIGGER});
  }


  ####################
  # Used by triggered perl programs to check the old value
  # Not suited for multi-valued devices (KS300, etc)
  $oldvalue{$dev}{TIME} = $now;
  $oldvalue{$dev}{VAL} = $hash->{STATE};

  if(!defined($hash->{INTRIGGER})) {
    delete($hash->{CHANGED});
    delete($hash->{CHANGETIME});
    delete($hash->{CHANGEDWITHSTATE});
  }

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
# Alternative to CallFn with optional functions in $defs, Forum #64741
sub
CallInstanceFn(@)
{
  my $d = shift;
  my $n = shift;

  if(!$d || !$defs{$d}) {
    $d = "<undefined>" if(!defined($d));
    Log 0, "Strange call for nonexistent $d: $n";
    return undef;
  }
  my $fn = $defs{$d}{$n} ? $defs{$d}{$n} : $defs{$d}{".$n"};
  return CallFn($d, $n, @_) if(!$fn);
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
  $defs{global}{STATE} = "no definition";
  $defs{global}{DEF}   = "no definition";
  $defs{global}{NAME}  = "global";

  CommandAttr(undef, "global verbose 3");
  CommandAttr(undef, "global configfile $arg");
  CommandAttr(undef, "global logfile -");
}

#####################################
# rename does not work over Filesystems: lets copy it
sub
myrename($$$)
{
  my ($name, $from, $to) = @_;

  my $ca = AttrVal($name, "archiveCompress", 0);
  if($ca) {
    eval { require Compress::Zlib; };
    if($@) {
      $ca = 0;
      Log 1, $@;
    }
  }
  $to .= ".gz" if($ca);
 
  if(!open(F, $from)) {
    Log(1, "Rename: Cannot open $from: $!");
    return;
  }
  if(!open(T, ">$to")) {
    Log(1, "Rename: Cannot open $to: $!");
    return;
  }

  if($ca) {
    my $d = Compress::Zlib::deflateInit(-WindowBits=>31);
    my $buf;
    while(sysread(F,$buf,32768) > 0) {
      syswrite(T, $d->deflate($buf));
    }
    syswrite(T, $d->flush());
  } else {
    while(my $l = <F>) {
      print T $l;
    }
  }
  close(F);
  close(T);
  unlink($from);
}

#####################################
# Make a directory and its parent directories if needed.
sub
HandleArchiving($;$)
{
  my ($log,$flogInitial) = @_;
  my $ln = $log->{NAME};
  return if(!$attr{$ln});

  # If there is a command, call that
  my $cmd = $attr{$ln}{archivecmd};
  if($cmd) {
    return if($flogInitial); # Forum #41245
    $cmd =~ s/%/$log->{currentlogfile}/g;
    Log 2, "Archive: calling $cmd";
    system($cmd);
    return;
  }

  my $nra = $attr{$ln}{nrarchive};
  my $ard = $attr{$ln}{archivedir};
  return if(!defined($nra));

  $nra++ if($ln eq "global"); # Forum #61450

  # If nrarchive is set, then check the last files:
  # Get a list of files:

  my ($dir, $file);
  if($log->{logfile} =~ m,^(.+)/([^/]+)$,) {
    ($dir, $file) = ($1, $2);
  } else {
    ($dir, $file) = (".", $log->{logfile});
  }

  $file =~ s/%./.+/g;
  my @t = localtime;
  $dir = ResolveDateWildcards($dir, @t);
  return if(!opendir(DH, $dir));
  my @files = sort grep {/^$file$/} readdir(DH);
  @files = sort { (stat("$dir/$a"))[9] cmp (stat("$dir/$b"))[9] } @files
        if(AttrVal("global", "archivesort", "alphanum") eq "timestamp");
  closedir(DH);

  my $max = int(@files)-$nra;
  $max-- if($flogInitial);
  for(my $i = 0; $i < $max; $i++) {
    if($ard) {
      Log 2, "Moving $files[$i] to $ard";
      myrename($ln, "$dir/$files[$i]", "$ard/$files[$i]");
    } else {
      Log 2, "Deleting $files[$i]";
      unlink("$dir/$files[$i]");
    }
  }
}

#####################################
# Call a logical device (FS20) ParseMessage with data from a physical device
# (FHZ). Note: $hash may be dummy, used by FHEM2FHEM
sub
Dispatch($$$)
{
  my ($hash, $dmsg, $addvals) = @_;
  my $module = $modules{$hash->{TYPE}};
  my $name = $hash->{NAME};

  if(GetVerbose($name) == 5) {
    Log3 $hash, 5, escapeLogLine("$name: dispatch $dmsg");
  }

  my ($isdup, $idx) = CheckDuplicate($name, $dmsg, $module->{FingerprintFn});
  return rejectDuplicate($name,$idx,$addvals) if($isdup);

  my @found;
  my $parserMod="";
  my $clientArray = $hash->{".clientArray"};
  $clientArray = computeClientArray($hash, $module) if(!$clientArray);

  foreach my $m (@{$clientArray}) {
    # Module is not loaded or the message is not for this module
    next if(!$modules{$m} || $dmsg !~ m/$modules{$m}{Match}/i);

    if( my $ffn = $modules{$m}{FingerprintFn} ) {
      ($isdup, $idx) = CheckDuplicate($name, $dmsg, $ffn);
      return rejectDuplicate($name,$idx,$addvals) if($isdup);
    }

    no strict "refs"; $readingsUpdateDelayTrigger = 1;
    @found = &{$modules{$m}{ParseFn}}($hash,$dmsg);
    use strict "refs"; $readingsUpdateDelayTrigger = 0;
    $parserMod = $m;
    last if(int(@found));
  }

  if(!int(@found) || !defined($found[0])) {
    my $h = $hash->{MatchList};
    $h = $module->{MatchList} if(!$h);
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
              $parserMod = $mname;
              last if(defined($found[0]));
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
    if(!int(@found) || !defined($found[0])) {
      DoTrigger($name, "UNKNOWNCODE $dmsg");
      Log3 $name, 3, "$name: Unknown code $dmsg, help me!";
      return undef;
    }
  }

  ################
  # Inform raw
  if(!$module->{noRawInform}) {
    foreach my $c (keys %inform) {
      if(!$defs{$c} || $defs{$c}{NR} != $inform{$c}{NR}) {
        delete($inform{$c});
        next;
      }
      next if($inform{$c}{type} ne "raw");
      syswrite($defs{$c}{CD}, "$hash->{TYPE} $name $dmsg\n");
    }
  }

  # Special return: Do not notify
  return undef if(!defined($found[0]) || $found[0] eq "");

  foreach my $found (@found) {

    if($found =~ m/^(UNDEFINED.*)/) {
      DoTrigger("global", $1);
      return undef;

    } else {
      if($defs{$found}) {
        if(!$defs{$found}{".noDispatchVars"}) { # CUL_HM special
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
        delete($defs{$found}{".noDispatchVars"});
        DoTrigger($found, undef);
      } else {
        Log 1, "ERROR: >$found< returned by the $parserMod ParseFn is invalid,".
               " notify the module maintainer";
        return undef;
      }
    }
  }

  $duplicate{$idx}{FND} = \@found 
        if(defined($idx) && defined($duplicate{$idx}));

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
addToDevAttrList($$)
{
  my ($dev,$arg) = @_;

  my $ua = $attr{$dev}{userattr};
  $ua = "" if(!$ua);
  my %hash = map { ($_ => 1) }
             grep { " $AttrList " !~ m/ $_ / }
             split(" ", "$ua $arg");
  $attr{$dev}{userattr} = join(" ", sort keys %hash);
}

sub
addToAttrList($)
{
  addToDevAttrList("global", shift);
}

sub
attrSplit($)
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
# $dir: 0: User to Device (i.e. set) 1: Device to Usr (i.e trigger)
# $dir: 0: $str is an array pointer  1: $str is a a string
sub
ReplaceEventMap($$$)
{
  my ($dev, $str, $dir) = @_;
  my $em = AttrVal($dev, "eventMap", undef);

  return $str    if($dir && !$em);
  return @{$str} if(!$dir && (!$em || int(@{$str}) < 2 ||
                    !defined($str->[1]) || $str->[1] eq "?"));

  return ReplaceEventMap2($dev, $str, $dir, $em) if($em =~ m/^{.*}$/s);
  my @emList = attrSplit($em);

  if(!defined $defs{$dev}{".eventMapCmd"}) {
    # Delete the first word of the translation (.*:), else it will be
    # interpreted as the single possible value for a dropdown
    # Why is the .*= deleted?
    $defs{$dev}{".eventMapCmd"} = join(" ", grep { !/ / }
                  map { $_ =~ s/.*?=//s; $_ =~ s/.*?://s; 
                        $_ =~ m/:/ ? $_ : "$_:noArg" } @emList);
  }

  my ($dname, $nstr);
  $dname = shift @{$str} if(!$dir);
  $nstr = join(" ", @{$str}) if(!$dir);

  my $changed;
  foreach my $rv (@emList) {
    # Real-Event-Regexp:GivenName[:modifier]
    my ($re, $val, $modifier) = split(":", $rv, 3);
    next if(!defined($val));
    if($dir) {  # dev -> usr
      my $reIsWord = ($re =~ m/^\w*$/); # dim100% is not \w only, cant use \b
      if($reIsWord) {
        if($str =~ m/\b$re\b/) {
          $str =~ s/\b$re\b/$val/;
          $changed = 1;
        }
      } else {
        if($str =~ m/$re/) {
          $str =~ s/$re/$val/;
          $changed = 1;
        }
      }

    } else {    # usr -> dev
      if($nstr eq $val) { # for special translations like <> and <<
        $nstr = $re;
        $changed = 1;
      } else {
        my $reIsWord = ($val =~ m/^\w*$/);
        if($reIsWord) {
          if($nstr =~ m/\b$val\b/) {
            $nstr =~ s/\b$val\b/$re/;
            $changed = 1;
          }
        } elsif($nstr =~ m/$val/) {
          $nstr =~ s/$val/$re/;
          $changed = 1;
        }
      }
    }
    last if($changed);

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

# $dir: 0:usr,$str is array pointer, 1:dev, $str is string
# perl notation: { dev=>{"re1"=>"Evt1",...}, dpy=>{"re2"=>"Set 1",...}}
sub
ReplaceEventMap2($$$)
{
  my ($dev, $str, $dir) = @_;

  my $hash = $defs{$dev};
  my $emh = $hash->{".eventMapHash"};
  if(!$emh) {
    eval "\$emh = $attr{$dev}{eventMap}";
    if($@) {
      my $msg = "ERROR in eventMap for $dev: $@";
      Log 1, $msg;
      return $msg;
    }
    $hash->{".eventMapHash"} = $emh;

    $defs{$dev}{".eventMapCmd"} = "";
    if($emh->{usr}) {
      my @cmd;
      my $fw = $emh->{fw};
      $defs{$dev}{".eventMapCmd"} = join(" ",
          map { ($fw && $fw->{$_}) ? $fw->{$_}:$_} sort keys %{$emh->{usr} });
    }
  }

  if($dir == 1) {
    $emh = $emh->{dev};
    if($emh) {
      foreach my $k (keys %{$emh}) {
        return $emh->{$k} if($str eq $k);
        return eval '"'.$emh->{$k}.'"' if($str =~ m/$k/);
      }
    }
    return $str;
  }

  $emh = $emh->{usr};
  return @{$str} if(!$emh);
    
  my $dname = shift @{$str};
  my $nstr = join(" ", @{$str});
  foreach my $k (keys %{$emh}) {
    my $nv;
    if($nstr eq $k) {
      $nv = $emh->{$k};

    } elsif($nstr =~ m/$k/) {
      my $NAME = $dev; # Compatibility, Forum #43023
      $nv = eval '"'.$emh->{$k}.'"';

    }
    if(defined($nv)) {
      my @arr = split(" ",$nv);
      unshift @arr, $dname;
      return @arr;
    }
  }
  unshift @{$str}, $dname;
  return @{$str};
}

sub
setGlobalAttrBeforeFork($)
{
  my ($f) = @_;

  my ($err, @rows);
  if($f eq 'configDB') {
    @rows = cfgDB_AttrRead('global');
  } else {
    ($err, @rows) = FileRead($f);
    die("$err\n") if($err);
  }

  foreach my $l (@rows) {
    $l =~ s/[\r\n]//g;
    next if($l !~ m/^attr\s+global\s+([^\s]+)\s+(.*)$/);
    my ($n,$v) = ($1,$2);
    $v =~ s/#.*//;
    $v =~ s/ .*$//;
    if($fhemdebug) {
      $v = "-" if($n eq "logfile");
      $v = 5   if($n eq "verbose");
    }
    $attr{global}{$n} = $v;
    GlobalAttr("set", "global", $n, $v);
  }
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
InternalNum($$$;$)
{
  my ($d,$n,$default,$round) = @_;
  my $val = InternalVal($d,$n,$default);
  $val = ($val =~ /(-?\d+(\.\d+)?)/ ? $1 : "");
  $val = round($val,$round) if($round);
  return $val;
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
ReadingsNum($$$;$)
{
  my ($d,$n,$default,$round) = @_;
  my $val = ReadingsVal($d,$n,$default);
  return undef if(!defined($val));
  $val = ($val =~ /(-?\d+(\.\d+)?)/ ? $1 : "");
  $val = round($val,$round) if($round);
  return $val;
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
ReadingsAge($$$)
{
  my ($device,$reading,$default) = @_;
  my $ts = ReadingsTimestamp($device,$reading,undef);
  return time() - time_str2num($ts) if(defined($ts));
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
  return $attr{$d}{$n} if(defined($attr{$d}) && defined($attr{$d}{$n}));
  return $default;
}

sub
AttrNum($$$;$)
{
  my ($d,$n,$default,$round) = @_;
  my $val = AttrVal($d,$n,$default);
  return undef if(!defined($val));
  $val = ($val =~ /(-?\d+(\.\d+)?)/ ? $1 : "");
  $val = round($val,$round) if($round);
  return $val;
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

sub 
concatc($$$) {
  my ($separator,$a,$b)= @_;;
  return($a && $b ?  $a . $separator . $b : $a . $b);
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
  
  if(!$name) {
    Log 1, "ERROR: empty name in readingsBeginUpdate";
    stacktrace();
    return;
  }

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
  
  my $attraggr = AttrVal($name, "event-aggregator", undef);
  if($attraggr) {
    my @a = split(/,/,$attraggr);
    $hash->{".attraggr"} = \@a;
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

  my $attrtocr= AttrVal($name, "timestamp-on-change-reading", undef);
  if($attrtocr) {
    my @a = split(/,/,$attrtocr);
    $hash->{".attrtocr"} = \@a;
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

  } elsif($sr =~ m/^{(.*)}$/s) {
    $st = eval $1;
    if($@) {
      $st = "Error evaluating $name stateFormat: $@";
      Log 1, $st;
    }

  } else {
    # Substitute reading names with their values, leave the rest untouched.
    $st = $sr;
    my $r = $hash->{READINGS};
    $st =~ s/\$name/$name/g;
    (undef, $st) = ReplaceSetMagic($hash, 1, $st);
    $st =~ s/\b([A-Za-z\d_\.-]+)\b/($r->{$1} ? $r->{$1}{VAL} : $1)/ge
      if($st eq $sr);

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
    foreach my $userReading (@{$hash->{'.userReadings'}}) {

      my $trigger = $userReading->{trigger};
      my $reading= $userReading->{reading};
      if(defined($trigger)) {
        my ($trRead, $ownRead);
        map { $trRead  = 1 if($_ && $_ =~ m/^$trigger$/);
              $ownRead = 1 if($_ && $_ =~ m/^$reading:/); } @{$hash->{CHANGED}};
        next if(!$trRead || $ownRead);
      }

      my $modifier= $userReading->{modifier};
      my $perlCode= $userReading->{perlCode};
      my $oldvalue= $userReading->{value};
      my $oldt= $userReading->{t};
      #Debug "Evaluating " . $reading;
      $cmdFromAnalyze = $perlCode;      # For the __WARN__ sub
      my $NAME = $name; # no exceptions, #53069
      my $value= eval $perlCode;
      $cmdFromAnalyze = undef;
      my $result;
      # store result
      if($@) {
        $value = "Error evaluating $name userReading $reading: $@";
        Log 1, $value;
        $result= $value;
      } elsif(!defined($value)) {
        $cmdFromAnalyze = $perlCode; # For the __WARN__ sub
        warn("$name userReadings $reading evaluated to undef");
        next;
      } elsif($modifier eq "none") {
        $result= $value;
      } elsif($modifier eq "difference") {
        $result= $value - $oldvalue if(defined($oldvalue));
      } elsif($modifier eq "differential") {
        my ($deltav, $deltat);
        $deltav = $value - $oldvalue if(defined($oldvalue));
        $deltat = $hash->{".updateTime"} - $oldt if(defined($oldt));
        if(defined($deltav) && defined($deltat) && ($deltat>= 1.0)) {
          $result= $deltav/$deltat;
        }
      } elsif($modifier eq "integral") {
        if(defined($oldt) && defined($oldvalue)) {
          my $deltat;
          $deltat = $hash->{".updateTime"} - $oldt if(defined($oldt));
          my $avgval= ($value + $oldvalue) / 2;
          $result = ReadingsVal($name,$reading,$value);
          if(defined($deltat) && $deltat>= 1.0) {
            $result+= $avgval*$deltat;
          }
        }
      } elsif($modifier eq "offset") {
        $oldvalue = $value if( !defined($oldvalue) );
        $result = ReadingsVal($name,$reading,0);
        $result += $oldvalue if( $value < $oldvalue );
      } elsif($modifier eq "monotonic") {
        $oldvalue = $value if( !defined($oldvalue) );
        $result = ReadingsVal($name,$reading,$value);
        $result += $value - $oldvalue if( $value > $oldvalue );
      } 
      readingsBulkUpdate($hash,$reading,$result,1) if(defined($result));
      # store value
      $userReading->{TIME}= $hash->{".updateTimestamp"};
      $userReading->{t}= $hash->{".updateTime"};
      $userReading->{value}= $value;
    }
  }
  evalStateFormat($hash);

  # turn off updating mode
  delete $hash->{".updateTimestamp"};
  delete $hash->{".updateTime"};
  delete $hash->{".attreour"};
  delete $hash->{".attreocr"};
  delete $hash->{".attraggr"};
  delete $hash->{".attrminint"};
  delete $hash->{".attrtocr"};


  # propagate changes
  if($dotrigger && $init_done) {
    DoTrigger($name, undef, 0) if(!$readingsUpdateDelayTrigger);
  } else {
    if(!defined($hash->{INTRIGGER})) {
      delete($hash->{CHANGED});
      delete($hash->{CHANGEDWITHSTATE})
    }
  }
  
  return undef;
}

sub
readingsBulkUpdateIfChanged($$$@) # Forum #58797
{
  my ($hash,$reading,$value,$changed)= @_;
  return undef if($value eq ReadingsVal($hash->{NAME},$reading,""));
  return readingsBulkUpdate($hash,$reading,$value,$changed);
}

# Call readingsBulkUpdate to update the reading.
# Example: readingsUpdate($hash,"temperature",$value);
# Optional parameter $changed: if defined, and is 0, do not trigger events. If
# 1, trigger. If not defined, the name of the reading decides (starting with .
# is 0, else 1). The event-on-* filtering is done additionally.
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
    stacktrace();
    return;
  }

  my $sp = AttrVal($name, "suppressReading", undef);
  return if($sp && $reading =~ m/^$sp$/);
  
  # shorthand
  my $readings = $hash->{READINGS}{$reading};

  if(!defined($changed)) {
    $changed = (substr($reading,0,1) ne "."); # Dont trigger dot-readings
  }
  $changed = 0 if($hash->{".ignoreEvent"});

  # if reading does not exist yet: fake entry to allow filtering
  $readings = { VAL => "" } if( !defined($readings) );

  my $update_timestamp = 1;
  if($changed) {
  
    # these flags determine if any of the "event-on" attributes are set
    my $attreocr = $hash->{".attreocr"};
    my $attreour = $hash->{".attreour"};

    # determine whether the reading is listed in any of the attributes
    my $eocr = $attreocr &&
               ( my @eocrv = grep { my $l = $_; $l =~ s/:.*//;
                   ($reading=~ m/^$l$/) ? $_ : undef} @{$attreocr});
    my $eour = $attreour && grep($reading =~ m/^$_$/, @{$attreour});

    # check if threshold is given
    my $eocrExists = $eocr;
    if( $eocr
        && $eocrv[0] =~ m/.*:(.*)/ ) {
      my $threshold = $1;

      if($value =~ m/([\d\.\-eE]+)/ && looks_like_number($1)) { #41083, #62190
        my $mv = $1;
        my $last_value = $hash->{".attreocr-threshold$reading"};
        if( !defined($last_value) ) {
          $hash->{".attreocr-threshold$reading"} = $mv;
        } elsif( abs($mv - $last_value) < $threshold ) {
          $eocr = 0;
        } else {
          $hash->{".attreocr-threshold$reading"} = $mv;
        }
      }
    }

    # determine if an event should be created:
    # always create event if no attribute is set
    # or if the reading is listed in event-on-update-reading
    # or if the reading is listed in event-on-change-reading...
    # ...and its value has changed...
    # ...and the change greater then the threshold
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
        $changed = 1 if($eocrExists);
      }
    }

    if( $attreocr ) {
      if( my $attrtocr = $hash->{".attrtocr"} ) {
        $update_timestamp = $changed
                if( $attrtocr && grep($reading =~ m/^$_$/, @{$attrtocr}) );
      }
    }

  }

  if($changed) {
    #Debug "Processing $reading: $value";
    my @v = grep { my $l = $_;
                  $l =~ s/:.*//;
                  ($reading=~ m/^$l$/) ? $_ : undef} @{$hash->{".attraggr"}};
    if(@v) {
      # e.g. power:20:linear:avg
      my (undef,$duration,$method,$function,$holdTime) = split(":", $v[0], 5);
      my $ts;
      if(defined($readings->{".ts"})) {
        $ts= $readings->{".ts"};
      } else {
        require "TimeSeries.pm";
        $ts= TimeSeries->new( { method => $method, 
                                autoreset => $duration,
                                holdTime => $holdTime } );
        $readings->{".ts"}= $ts;
        # access from command line:
        # { $defs{"myClient"}{READINGS}{"myValue"}{".ts"}{max} }
        #Debug "TimeSeries created.";
      }
      my $now = $hash->{".updateTime"};
      my $val = $value; # save value
      $changed = $ts->elapsed($now);
      $value = $ts->{$function} if($changed);
      $ts->add($now, $val); 
    } else {
      # If no event-aggregator attribute, then remove stale series if any.
      delete $readings->{".ts"};
    }
  }
  
  
  setReadingsVal($hash, $reading, $value, $hash->{".updateTimestamp"})
        if($update_timestamp); 
  
  my $rv = "$reading: $value";
  if($changed) {
    if($reading eq "state") {
      $rv = $value;
      $hash->{CHANGEDWITHSTATE} = [];
    }
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
fhemTzOffset($)
{
  # see http://stackoverflow.com/questions/2143528/whats-the-best-way-to-get-the-utc-offset-in-perl
  my $t = shift;
  my @l = localtime($t);
  my @g = gmtime($t);

  # the offset is positive if the local timezone is ahead of GMT, e.g. we get
  # 2*3600 seconds for CET DST vs GMT
  return 60*(($l[2] - $g[2] + 
            ((($l[5] << 9)|$l[7]) <=> (($g[5] << 9)|$g[7])) * 24)*60 +
            $l[1] - $g[1]);
}

sub
fhemTimeGm($$$$$$) 
{
  # see http://de.wikipedia.org/wiki/Unixzeit
  my ($sec,$min,$hour,$mday,$month,$year) = @_;

  # $mday= 1..
  # $month= 0..11
  # $year is year-1900
  
  $year += 1900;
  my $isleapyear= $year % 4 ? 0 : $year % 100 ? 1 : $year % 400 ? 0 : 1;
 
  # Forum #38610
  my $leapyears_date = int(($year-1)/4) -int(($year-1)/100) +int(($year-1)/400);
  my $leapyears_1970 = int((1970 -1)/4) -int((1970 -1)/100) +int((1970 -1)/400);
  my $leapyears = $leapyears_date - $leapyears_1970; 

  if ( $^O eq 'MacOS' ) {
    $year -= 1904;
  } else {
    $year -= 1970; # the Unix Epoch
  }

  my @d = (0,31,59,90,120,151,181,212,243,273,304,334); # no leap day
  # add one day in leap years if month is later than February
  $mday++ if($month>1 && $isleapyear);
  return $sec+60*($min+60*($hour+24*
              ($d[$month]+$mday-1+365*$year+$leapyears)));
}

sub
fhemTimeLocal($$$$$$) {
    my $t= fhemTimeGm($_[0],$_[1],$_[2],$_[3],$_[4],$_[5]);
    return $t-fhemTzOffset($t);
}

# compute the list of defined logical modules for a physical module
sub
computeClientArray($$)
{
  my ($hash, $module) = @_;
  my @a = ();
  my @mRe = split(":", $hash->{Clients} ? $hash->{Clients}:$module->{Clients});

  foreach my $m (sort { $modules{$a}{ORDER}.$a cmp $modules{$b}{ORDER}.$b }
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

# replaces some common control chars by escape sequences
# in order to make logs more readable
sub escapeLogLine($) {
  my ($s)= @_;
  
  # http://perldoc.perl.org/perlrebackslash.html
  my %escSequences = (
      '\a' => "\\a",
      '\e' => "\\e",
      '\f' => "\\f",
      '\n' => "\\n",
      '\r' => "\\r",
      '\t' => "\\t",
      );
  
  $s =~ s/\\/\\\\/g;
  foreach my $regex (keys %escSequences) {
    $s =~ s/$regex/$escSequences{$regex}/g;
  }
  $s =~ s/([\000-\037])/sprintf("\\%03o", ord($1))/eg;
  return $s;
}

sub
toJSON($)
{
  my $val = shift;

  if(not defined $val) {
    return "null";

  } elsif (not ref $val) {
    $val =~ s/([\x00-\x1f\x22\x5c\x7f])/sprintf '\u%04x', ord($1)/ge;

    return '"' . $val . '"';

  } elsif (ref $val eq 'ARRAY') {
    return '[' . join(',', map toJSON($_), @$val) . ']';

  } elsif (ref $val eq 'HASH') {
      return '{' . join(',', 
                   map { toJSON($_).":".toJSON($val->{$_}) } 
                   sort keys %$val) . '}';

  } else {
      return toJSON("toJSON: Cannot encode $val");

  }
}


sub
Debug($) {
  my $msg= shift;
  Log 1, "DEBUG>" . $msg;
}

sub
addToWritebuffer($$@)
{
  my ($hash, $txt, $callback, $nolimit) = @_;

  if($hash->{isChild}) {  # Wont go to the main select in a forked process
    TcpServer_WriteBlocking( $hash, $txt );
    if($callback) {
      no strict "refs";
      my $ret = &{$callback}($hash);
      use strict "refs";
    }
    return;
  }

  $hash->{WBCallback} = $callback;
  if(!$hash->{$wbName}) {
    $hash->{$wbName} = $txt;
  } elsif($nolimit || length($hash->{$wbName}) < 102400) {
    $hash->{$wbName} .= $txt;
  } else {
    return 0;
  }

  return 1; # success
}

sub
createNtfyHash()
{
  Log 5, "createNotifyHash";
  my @ntfyList = sort { $defs{$a}{NTFY_ORDER} cmp $defs{$b}{NTFY_ORDER} }
                 grep { $defs{$_}{NTFY_ORDER} && 
                        $defs{$_}{TYPE} && 
                        $modules{$defs{$_}{TYPE}}{NotifyFn} } keys %defs;
  my %d2a_cache;
  %ntfyHash = ("*" => []);
  foreach my $d (@ntfyList) {
    my $ndl = $defs{$d}{NOTIFYDEV};
    next if(!$ndl);
    my @ndlarr;
    if($d2a_cache{$ndl}) {
      @ndlarr = @{$d2a_cache{$ndl}};
    } else {
      @ndlarr = devspec2array($ndl);
      if(@ndlarr > 1) {
        my %h = map { $_ => 1 } @ndlarr;
        @ndlarr = keys %h;
      }
      $d2a_cache{$ndl} = \@ndlarr;
    }
    map { $ntfyHash{$_} = [] } @ndlarr;
  }

  my @nhk = keys %ntfyHash;
  foreach my $d (@ntfyList) {
    my $ndl = $defs{$d}{NOTIFYDEV};
    my $arr = ($ndl ? $d2a_cache{$ndl} : \@nhk);
    map { push @{$ntfyHash{$_}}, $d } @{$arr};
  }
}

sub
notifyRegexpChanged($$)
{
  my ($hash, $re) = @_;

  my @list2 = split(/\|/, $re);
  my @list = grep { m/./ }                                     # Forum #62369
             map  { (m/^\(?([A-Za-z0-9\.\_]+(?:\.[\+\*])?)(?::.*)?\)?$/ && 
                     ($defs{$1} || devspec2array($1) ne $1)) ? $1 : ""} @list2;
  if(@list && int(@list) == int(@list2)) {
    my %h = map { $_ => 1 } @list;
    @list = keys %h; # remove duplicates
    $hash->{NOTIFYDEV} = join(",", @list);
  } else {
    delete($hash->{NOTIFYDEV});
  }
  %ntfyHash = ();
}

sub
configDBUsed()
{ 
  return ($attr{global}{configfile} eq 'configDB');
}

sub
FileRead($)
{
  my ($param) = @_;
  my ($err, @ret, $fileName, $forceType);

  if(ref($param) eq "HASH") {
    $fileName = $param->{FileName};
    $forceType = $param->{ForceType};
  } else {
    $fileName = $param;
  }
  $forceType = "" if(!defined($forceType));

  if(configDBUsed() && $forceType ne "file") {
    ($err, @ret) = cfgDB_FileRead($fileName);

  } else {
    if(open(FH, $fileName)) {
      @ret = <FH>;
      close(FH);
      chomp(@ret);
    } else {
      $err = "Can't open $fileName: $!";
    }
  }

  return ($err, @ret);
}

sub
FileWrite($@)
{
  my ($param, @rows) = @_;
  my ($err, @ret, $fileName, $forceType, $nl);

  if(ref($param) eq "HASH") {
    $fileName = $param->{FileName};
    $forceType = $param->{ForceType};
    $nl = $param->{NoNL} ? "" : "\n";
  } else {
    $fileName = $param;
    $nl = "\n";
  }
  $forceType = "" if(!defined($forceType));

  if(configDBUsed() && $forceType ne "file") {
    return cfgDB_FileWrite($fileName, @rows);

  } else {
    if(open(FH, ">$fileName")) {
      binmode (FH);
      foreach my $l (@rows) {
        print FH $l,$nl;
      }
      close(FH);
      return undef;

    } else {
      return "Can't open $fileName: $!";

    }
  }
}

sub
FileDelete($)
{
  my ($param) = @_;
  my ($fileName, $forceType);
  if(ref($param) eq "HASH") {
    $fileName = $param->{FileName};
    $forceType = $param->{ForceType};
  } else {
    $fileName = $param;
  }
  $forceType //= '';
  if(configDBUsed() && lc($forceType) ne "file") {
    my $ret = _cfgDB_Filedelete($fileName);
    return ($ret ? undef : "$fileName: _cfgDB_Filedelete failed");
  } else {
    my $ret = unlink($fileName);
    return ($ret ? undef : "$fileName: $!");
  }
}

sub
getUniqueId()
{
  my ($err, $uniqueID) = getKeyValue("uniqueID");
  return $uniqueID if(defined($uniqueID));
  $uniqueID = createUniqueId();
  setKeyValue("uniqueID", $uniqueID);
  return $uniqueID;
}

my $srandUsed;
sub
createUniqueId()
{
  my $uniqueID;
  srand(time) if(!$srandUsed);
  $srandUsed = 1;
  $uniqueID = join "",map { unpack "H*", chr(rand(256)) } 1..16;
  return $uniqueID;
}

sub
getKeyValue($)
{
  my ($key) = @_;
  my $fName = $attr{global}{modpath}."/FHEM/FhemUtils/uniqueID";
  my ($err, @l) = FileRead($fName);
  return ($err, undef) if($err);
  for my $l (@l) {
    return (undef, $1) if($l =~ m/^$key:(.*)/);
  }
  return (undef, undef);
}

# Use an undefined value to delete the key
sub
setKeyValue($$)
{
  my ($key,$value) = @_;
  my $fName = $attr{global}{modpath}."/FHEM/FhemUtils/uniqueID";
  my ($err, @old) = FileRead($fName);
  my @new;
  if($err) {
    push(@new, "# This file is auto generated.",
               "# Please do not modify, move or delete it.",
               "");
    @old = ();
  }
  
  my $fnd;
  foreach my $l (@old) {
    if($l =~ m/^$key:/) {
      $fnd = 1;
      push @new, "$key:$value" if(defined($value));
    } else {
      push @new, $l;
    }
  }
  push @new, "$key:$value" if(!$fnd && defined($value));

  return FileWrite($fName, @new);
}

sub
addStructChange($$$)
{
  return if(!$init_done);

  my ($cmd, $dev, $param) = @_;
  return if(!$defs{$dev} || $defs{$dev}{TEMPORARY});

  $lastDefChange++;
  return if($defs{$dev}{VOLATILE});

  shift @structChangeHist if(@structChangeHist > 9);
  $param = substr($param, 0, 40)."..." if(length($param) > 40);
  push @structChangeHist, "$cmd $param";
}

sub
fhemFork()
{
  my $pid = fork;
  if(!defined($pid)) {
    Log 1, "Cannot fork: $!";
    stacktrace() if($attr{global}{stacktrace});
    return undef;
  }

  return $pid if($pid);

  # Child here
  # Close FDs as we cannot restart FHEM if child keeps TCP Serverports open
  foreach my $d (sort keys %defs) {
    my $h = $defs{$d};
    $h->{DBH}->{InactiveDestroy} = 1
      if($h->{DBH} && $h->{TYPE} eq 'DbLog'); #Forum #43271
    TcpServer_Close($h) if($h->{SERVERSOCKET});
    if($h->{DeviceName}) {
      require "$attr{global}{modpath}/FHEM/DevIo.pm";
      DevIo_CloseDev($h,1);
    }
  }
  $SIG{CHLD} = 'DEFAULT';  # Forum #50898
  $fhemForked = 1;
  return 0;
}

# Return the next element from the string (list) for each consecutive call.
# The index for the next call is stored in the device hash
sub
Each($$;$)      # can be used e.g. in at, Forum #40022
{
  my ($dev, $string, $sep) = @_;
  return "" if(!$defs{$dev});
  my $idx = ($defs{$dev}{EACH_INDEX} ? $defs{$dev}{EACH_INDEX} : 0);
  $sep = "," if(!$sep);
  my @arr = split($sep, $string);

  $idx = 0 if(@arr <= $idx);
  $defs{$dev}{EACH_INDEX} = $idx+1;

  return $arr[$idx];
}

##################
# Return 1 if Authorized, else 0
# Note: AuthorizeFn's returning 1 are not stackable.
sub
Authorized($$$)
{
  my ($cl, $type, $arg) = @_;

  return 1 if(!$init_done || !$cl || !$cl->{SNAME}); # Safeguarding
  RefreshAuthList() if($auth_refresh);
  my $sname = $cl->{SNAME};
  my $verbose = AttrVal($sname, "verbose", 1); # Speedup?

  foreach my $a (@authorize) {
    my $r = CallFn($a, "AuthorizeFn", $defs{$a}, $cl, $type, $arg);
    if($verbose >= 4) {
      Log3 $sname, 4, "authorize $sname/$type/$arg: $a returned ".
          ($r == 0 ? "dont care" : $r == 1 ? "allowed" : "prohibited");
    }
    return 1 if($r == 1);
    return 0 if($r == 2);
  }
  return 1;
}

##################
# Return 0 if not needed, 1 if authenticated, 2 if authentication failed
# Loop until one Authenticate is ok
sub
Authenticate($$)
{
  my ($cl, $arg) = @_;

  return 1 if(!$init_done || !$cl || !$cl->{SNAME}); # Safeguarding
  RefreshAuthList() if($auth_refresh);

  my $needed = 0;
  foreach my $a (@authenticate) {
    my $r = CallFn($a, "AuthenticateFn", $defs{$a}, $cl, $arg);
    $needed = $r if($r);
    return $r if($r == 1);
  }
  return $needed;
}

#####################################
sub
RefreshAuthList()
{
  @authorize = ();
  @authenticate = ();

  foreach my $d (sort keys %defs) {
    my $h = $defs{$d};
    next if(!$h->{TYPE} || !$modules{$h->{TYPE}});
    push @authorize, $d if($modules{$h->{TYPE}}{AuthorizeFn});
    push @authenticate, $d if($modules{$h->{TYPE}}{AuthenticateFn});
  }
  $auth_refresh = 0;
}

#####################################
sub
perlSyntaxCheck($%)
{
  my ($exec, %specials)= @_;

  my $psc = AttrVal("global", "perlSyntaxCheck", ($featurelevel>5.7) ? 1 : 0);
  return undef if(!$psc || !$init_done);

  my ($arr, $hash) = parseParams($exec, ';');
  $arr = [ $exec ] if(!@$arr); # temporary bugfix
  for my $cmd (@{$arr}) {
    next if($cmd !~ m/^\s*{/); # } for match
    $specials{__UNIQUECMD__}=1;
    $cmd = EvalSpecials("{return undef; $cmd}", %specials);
    my $r = AnalyzePerlCommand(undef, $cmd);
    return $r if($r);
  }
  return undef;
}

#####################################
sub
parseParams($;$$)
{
  my($cmd, $separator, $joiner) = @_;
  $separator = ' ' if(!$separator);
  $joiner = $separator if(!$joiner); # needed if separator is a regexp
  my(@a, %h);

  my @params;
  if( ref($cmd) eq 'ARRAY' ) {
    @params = @{$cmd};
  } else {
    @params = split($separator, $cmd);
  }

  while (@params) {
    my $param = shift(@params);
    next if($param eq "");
    my ($key, $value) = split( '=', $param, 2 );

    if( !defined( $value ) ) {
      $value = $key;
      $key = undef;

    # the key can not start with a { -> it must be a perl expression # vim:}
    } elsif( $key =~ m/^\s*{/ ) { # for vim: }
      $value = $param;
      $key = undef;
    }

    #collect all parts until the closing ' or "
    while( $param && $value =~ m/^('|")/ && $value !~ m/$1$/ ) {
      my $next = shift(@params);
      last if( !defined($next) );
      $value .= $joiner . $next;
    }
    #remove matching ' or " from the start and end
    if( $value =~ m/^('|")/ && $value =~ m/$1$/ ) {
      $value =~ s/^.(.*).$/$1/;
    }

    #collect all parts until opening { and closing } are matched
    if( $value =~ m/^\s*{/ ) { # } for match
      my $count = 0;
      for my $i (0..length($value)-1) {
        my $c = substr($value, $i, 1);
        ++$count if( $c eq '{' );
        --$count if( $c eq '}' );
      }

      while( $param && $count != 0 ) {
        my $next = shift(@params);
        last if( !defined($next) );
        $value .= $joiner . $next;

        for my $i (0..length($next)-1) {
          my $c = substr($next, $i, 1);
          ++$count if( $c eq '{' );
          --$count if( $c eq '}' );
        }
      }
    }

    if( defined($key) ) {
      $h{$key} = $value;
    } else {
      push @a, $value;
    }

  }
  return(\@a, \%h);
}

# get "Porbably Associated With" list for a devicename
sub
getPawList($)
{
  my ($d) = @_;
  my $h = $defs{$d};
  my @dob;
  foreach my $dn (sort keys %defs) {
    next if(!$dn || $dn eq $d);
    my $dh = $defs{$dn};
    if(($dh->{DEF} && $dh->{DEF} =~ m/\b$d\b/) ||
       ($h->{DEF}  && $h->{DEF}  =~ m/\b$dn\b/)) {
      push(@dob, $dn);
    }
  }
  return @dob;
}

sub
goodDeviceName($)
{
  my ($name) = @_;
  return ($name && $name =~ m/^[a-z0-9._]*$/i);
}

sub
makeDeviceName($) # Convert non-valid characters to _
{
  my ($name) = @_;
  $name = "UNDEFINED" if(!defined($name));
  $name =~ s/[^a-z0-9._]/_/gi;
  return $name;
}

sub
goodReadingName($)
{
  my ($name) = @_;
  return ($name && ($name =~ m/^[a-z0-9._\-\/]+$/i || $name =~ m/^\./));
}

sub
makeReadingName($) # Convert non-valid characters to _
{
  my ($name) = @_;
  $name = "UNDEFINED" if(!defined($name));
  return $name if($name =~ m/^\./);
  $name =~ s/[^a-z0-9._\-\/]/_/gi;
  return $name;
}

sub
computeAlignTime($$@)
{
  my ($timeSpec, $alignSpec, $triggertime) = @_; # triggertime is now if absent

  my ($alErr, $alHr, $alMin, $alSec, undef) = GetTimeSpec($alignSpec);
  return ("alignTime: $alErr", undef) if($alErr);

  my ($tmErr, $hr, $min, $sec, undef) = GetTimeSpec($timeSpec);
  return ("timeSpec: $tmErr", undef) if($alErr);

  my $now = time();
  my $alTime = ($alHr*60+$alMin)*60+$alSec-fhemTzOffset($now);
  my $step = ($hr*60+$min)*60+$sec;
  my $ttime = ($triggertime ? int($triggertime) : $now);
  my $off = ($ttime % 86400) - 86400;
  while($off < $alTime) {
    $off += $step;
  }
  $ttime += ($alTime-$off);
  $ttime += $step if($ttime < $now);
  return (undef, $ttime);
}

############################
my %restoreDir_dirs;
sub
restoreDir_mkDir($$$)
{
  my ($root, $dir, $isFile) = @_;
  if($isFile) { # Delete the file Component
    $dir =~ m,^(.*)/([^/]*)$,;
    $dir = $1;
  }
  return if($restoreDir_dirs{$dir});
  $restoreDir_dirs{$dir} = 1;
  my @p = split("/", $dir);
  for(my $i = 0; $i < int(@p); $i++) {
    my $path = "$root/".join("/", @p[0..$i]);
    if(!-d $path) {
      mkdir $path;
      Log 4, "MKDIR $root/".join("/", @p[0..$i]);
    }
  }
}

sub
restoreDir_rmTree($)
{
  my ($dir) = @_;

  my $dh;
  if(!opendir($dh, $dir)) {
    Log 1, "opendir $dir: $!";
    return;
  }
  my @files = grep { $_ ne "." && $_ ne ".." } readdir($dh);
  closedir($dh);

  foreach my $f (@files) {
    if(-d "$dir/$f") {
      restoreDir_rmTree("$dir/$f");
    } else {
      Log 4, "rm $dir/$f";
      if(!unlink("$dir/$f")) {
        Log 1, "rm $dir/$f failed: $!";
      }
    }
  }
  Log 4, "rmdir $dir";
  if(!rmdir($dir)) {
    Log 1, "rmdir $dir failed: $!";
  }
}

sub
restoreDir_init()
{
  my $root = $attr{global}{modpath};

  my $nDirs = AttrVal("global","restoreDirs", 3);
  if($nDirs !~ m/^\d+$/ || $nDirs < 0) {
    Log 1, "invalid restoreDirs value $nDirs, setting it to 3";
    $nDirs = 3;
  }
  return "" if($nDirs == 0);

  my $rdName = "restoreDir";
  my @t = localtime;
  my $restoreDir = sprintf("$rdName/%04d-%02d-%02d",
                        $t[5]+1900, $t[4]+1, $t[3]);
  Log 1, "MKDIR $restoreDir" if(!  -d "$root/restoreDir");
  restoreDir_mkDir($root, $restoreDir, 0);

  if(!opendir(DH, "$root/$rdName")) {
    Log 1, "opendir $root/$rdName: $!";
    return "";
  }
  my @oldDirs = sort grep { $_ !~ m/^\./ && $_ ne $restoreDir } readdir(DH);
  closedir(DH);
  while(int(@oldDirs) > $nDirs) {
    my $dir = "$root/$rdName/". shift(@oldDirs);
    next if($dir =~ m/$restoreDir/);    # Just in case
    Log 1, "RMDIR: $dir";
    restoreDir_rmTree($dir);
  }
    
  return $restoreDir;
}

sub
restoreDir_saveFile($$)
{
  my($restoreDir, $fName) = @_;

  return if(!$restoreDir || !$fName);

  my $root = $attr{global}{modpath};
  restoreDir_mkDir($root, "$restoreDir/$fName", 1);
  if(!copy($fName, "$root/$restoreDir/$fName")) {
    log 1, "copy $fName $root/$restoreDir/$fName failed:$!";
  }
}

sub
SecurityCheck()
{
  return if(AttrVal("global", "motd", "") eq "none");
  my @fnd;
  foreach my $sdev (devspec2array("TYPE=(telnet|FHEMWEB)")) {
    next if(!$defs{$sdev} || $defs{$sdev}{TEMPORARY});
    my $hash = { SNAME=>$sdev, TYPE=>$defs{$sdev}{TYPE}, NAME=>"SecurityCheck"};
    push(@fnd, "  $sdev is not password protected")
        if(!Authenticate($hash, undef));
  }
  if(@fnd) {
    push @fnd, "";
    my @l = devspec2array("TYPE=allowed");
    if(@l) {
      push @fnd, "Protect this FHEM installation by ".
                 "configuring the allowed device $l[0]";
    } else {
      push @fnd, "Protect this FHEM installation by ".
                 "defining an allowed device with define allowed allowed";
    }
  }

  if($^O !~ m/Win/ && $<==0) {
    push(@fnd, "Running with root privileges is discouraged.")
  }

  if(@fnd) {
    unshift(@fnd, "SecurityCheck:");
    push(@fnd, "You can disable this message with attr global motd none");
    $attr{global}{motd} = join("\n", @fnd);
  } elsif(AttrVal('global','motd','') =~ m/^SecurityCheck/) {
    delete $attr{global}{motd};
  }
}

1;
