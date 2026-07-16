# $Id$
##############################################################################
#
#     73_PRESENCE2.pm
#     Checks for the PRESENCE2 of a mobile phone or tablet by network ping or detection.
#     It reports the PRESENCE2 of this device as state.
#
#     Copyright by Markus Bloch
#     e-mail: Notausstieg0309@googlemail.com
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################

package main;

use strict;
use warnings;
use Blocking;
use Time::HiRes qw(gettimeofday usleep sleep);
use DevIo;

our $missingModul = "";

###############################################################################
# perl includes
eval "use Net::Ping;1"              or $missingModul .= "Net::Ping ";
eval "use IO::Async::Loop;1"        or $missingModul .= "IO::Async::Loop ";
eval "use Net::Async::Ping;1"       or $missingModul .= "Net::Async::Ping ";
eval "use List::Util qw(pairmap);1" or $missingModul .= "List::Util ";

my $ModuleName = "PRESENCE2";
my $ModuleVersion = "01.04";
my %LOG_Text = (
   0 => "SERVER:",
   1 => "ERROR:",
   2 => "SIGNIFICANT:",
   3 => "BASIC:",
   4 => "EXPANDED:",
   5 => "DEBUG:"
);

sub PRESENCE2_doDaemonEntityScan($$);
sub PRESENCE2_doDaemonCleanup();
sub PRESENCE2_Log($$$);
sub PRESENCE2_DebugLog($$$$;$);
sub PRESENCE2_dbgLogInit($@);

#######################################################################
sub PRESENCE2_Log($$$)
{

   my ( $hash, $loglevel, $text ) = @_;

   my $instHash = ( ref($hash) eq "HASH" ) ? $hash : $defs{$hash};
   my $instName = ( ref($hash) eq "HASH" ) ? $hash->{NAME} : $hash;

   if ($instHash->{helper}{FhemLog3Std}) {
      Log3 $hash, $loglevel, $instName . ": " . $text;
      return undef;
   }

   my $xline       = ( caller(0) )[2];

   my $xsubroutine = ( caller(1) )[3];

   my $sub         = ( split( ':', $xsubroutine ) )[2];

   $sub =~ s/PRESENCE2_// if ( defined $sub );;
   $sub ||= 'no-subroutine-specified';

   $text = $LOG_Text{$loglevel} . $text;
   $text = "[$instName | $sub.$xline] - " . $text;

   if ( $instHash->{helper}{logDebug} ) {
     PRESENCE2_DebugLog $instHash, $instHash->{helper}{debugLog} . "-%Y-%m.dlog", $loglevel, $text;
   } else {
     Log3 $hash, $loglevel, $text;
   }

} # End PRESENCE2_Log

#######################################################################
sub PRESENCE2_DebugLog($$$$;$) {

  my ($hash, $filename, $loglevel, $text, $timestamp) = @_;
  my $name = $hash->{'NAME'};
  my $tim;

  $loglevel .= ":" if ($loglevel);
  $loglevel ||= "";

  my ($seconds, $microseconds) = gettimeofday();
  my @t = localtime($seconds);
  my $nfile = ResolveDateWildcards("%L/" . $filename, @t);

  unless ($timestamp) {

    $tim = sprintf("%04d.%02d.%02d %02d:%02d:%02d", $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0]);

    if ($attr{global}{mseclog}) {
      $tim .= sprintf(".%03d", $microseconds / 1000);
    }
  } else {
    $tim = $timestamp;
  }

  open(my $fh, '>>', $nfile);
  print $fh "$tim $loglevel$text\n";
  close $fh;

  return undef;

} # end PRESENCE2__DebugLog

#######################################################################
sub PRESENCE2_dbgLogInit($@) {

   my ($hash, $cmd, $aName, $aVal) = @_;
   my $name = $hash->{NAME};

   if ($cmd eq "init" ) {
     $hash->{DEBUGLOG}             = "OFF";
     $hash->{helper}{debugLog}     = $name . "_debugLog";
     $hash->{helper}{logDebug}     = AttrVal($name, "verbose", 0) == 5;
     if ($hash->{helper}{logDebug}) {
       my ($seconds, $microseconds) = gettimeofday();
       my @t = localtime($seconds);
       my $nfile = ResolveDateWildcards($hash->{helper}{debugLog} . '-%Y-%m.dlog', @t);

       $hash->{DEBUGLOG} = '<html>'
                         . '<a href="/fhem/FileLog_logWrapper&amp;dev='
                         . $hash->{helper}{debugLog}
                         . '&amp;type=text&amp;file='
                         . $nfile
                         . '">DEBUG Log kann hier eingesehen werden</a>'
                         . '</html>';
     }
   }

   return if $aVal && $aVal == -1;

   my $dirdef     = Logdir() . "/";
   my $dbgLogFile = $dirdef . $hash->{helper}{debugLog} . '-%Y-%m.dlog';

   if ($cmd eq "set" ) {
     if ($aVal == 5) {

       unless (defined $defs{$hash->{helper}{debugLog}}) {
         my $dMod  = 'defmod ' . $hash->{helper}{debugLog} . ' FileLog ' . $dbgLogFile . ' FakeLog readonly';

         fhem($dMod, 1);

         if (my $dRoom = AttrVal($name, "room", undef)) {
           $dMod = 'attr -silent ' . $hash->{helper}{debugLog} . ' room ' . $dRoom;
           fhem($dMod, 1);
         }

         if (my $dGroup = AttrVal($name, "group", undef)) {
           $dMod = 'attr -silent ' . $hash->{helper}{debugLog} . ' group ' . $dGroup;
           fhem($dMod, 1);
         }
       }

       PRESENCE2_Log $name, 3, "redirection debugLog: $dbgLogFile started";

       $hash->{helper}{logDebug} = 1;

       PRESENCE2_Log $name, 3, "redirection debugLog: $dbgLogFile started";

       my ($seconds, $microseconds) = gettimeofday();
       my @t = localtime($seconds);
       my $nfile = ResolveDateWildcards($hash->{helper}{debugLog} . '-%Y-%m.dlog', @t);

       $hash->{DEBUGLOG} = '<html>'
                         . '<a href="/fhem/FileLog_logWrapper&amp;dev='
                         . $hash->{helper}{debugLog}
                         . '&amp;type=text&amp;file='
                         . $nfile
                         . '">DEBUG Log kann hier eingesehen werden</a>'
                         . '</html>';

     } elsif($aVal < 5 && $hash->{helper}{logDebug}) {
       fhem("delete " . $hash->{helper}{debugLog}, 1);

       PRESENCE2_Log $name, 3, "redirection debugLog: $dbgLogFile stopped";

       $hash->{helper}{logDebug} = 0;
       $hash->{DEBUGLOG}         = "OFF";

       PRESENCE2_Log $name, 3, "redirection debugLog: $dbgLogFile stopped";

#       unless (unlink glob($dirdef . $hash->{helper}{debugLog} . '*.dlog')) {
#         return "Temporary debug file: " . $dirdef . $hash->{helper}{debugLog} . "*.dlog could not be removed: $!";
#       }
     }
   }

   if ($cmd eq "del" ) {
     fhem("delete " . $hash->{helper}{debugLog}, 1) if $hash->{helper}{logDebug};

     PRESENCE2_Log $name, 3, "redirection debugLog: $dbgLogFile stopped";

     $hash->{helper}{logDebug} = 0;
     $hash->{DEBUGLOG}         = "OFF";

     PRESENCE2_Log $name, 3, "redirection debugLog: $dbgLogFile stopped";

     unless (unlink glob($dirdef . $hash->{helper}{debugLog} . '*.dlog')) {
       PRESENCE2_Log $name, 3, "Temporary debug file: " . $dirdef . $hash->{helper}{debugLog} . "*.dlog could not be removed: $!";
     }

   }

} # end PRESENCE2_dbgLogInit

#######################################################################
sub PRESENCE2_Initialize($) {
    my ($hash) = @_;

    # Provider
    $hash->{ReadFn}   = "PRESENCE2_lanBtRead";
    $hash->{ReadyFn}  = "PRESENCE2_lanBtReady";
    $hash->{SetFn}    = "PRESENCE2_Set";
    $hash->{RenameFn} = "PRESENCE2_Rename";
    $hash->{GetFn}    = "PRESENCE2_Get";
    $hash->{DefFn}    = "PRESENCE2_Define";
    $hash->{NotifyFn} = "PRESENCE2_Notify";
    $hash->{UndefFn}  = "PRESENCE2_Undef";
    $hash->{AttrFn}   = "PRESENCE2_Attr";
    $hash->{AttrList} = "disable:0,1 "
                      . "thresholdAbsence "
                      . "intervalNormal "
                      . "intervalPresent "
                      . "powerCmd "
                      . "prGroup:multiple,static,dynamic "
                      . "prGroupDisp:condense,verbose "
                      . "FhemLog3Std:0,1 "
                      . $readingFnAttributes;
}

#######################################################################
sub PRESENCE2_Rename($$$) {
    my ($name, $oldName) = @_;
    my $dN = PRESENCE2_getDaemonName();
    return if(!defined $dN);
    PRESENCE2_doDaemonCleanup();
}

#######################################################################
sub PRESENCE2_Define($$) {
    my ($hash, $def) = @_;
    my @a = split("[ \t]+", $def);
    my $username =  getlogin || getpwuid($<) || "[unknown]";
    my $name = $hash->{NAME};

    $hash->{NOTIFYDEV} = "global";
    $hash->{NAME}    = $name;
    $hash->{VERSION} = $ModuleVersion;

    # initialize DEBUG LOG function
    $hash->{helper}{FhemLog3Std}  = AttrVal($name, "FhemLog3Std", 0);
    PRESENCE2_dbgLogInit($hash, "init", "verbose", AttrVal($name, "verbose", -1));
    # end initialize DEBUG LOG function

    if(defined($a[2]) and defined($a[3])) {
        $attr{$name}{intervalNormal}       = (defined($a[4]) and $a[4] =~ /^\d+$/ and $a[4] > 0) ? $a[4] : 1;
        $attr{$name}{intervalPresent}      = (defined($a[5]) and $a[5] =~ /^\d+$/ and $a[5] > 0) ? $a[5] : 1;
        $hash->{INTERVAL}                  = (defined($a[4]) and $a[4] =~ /^\d+$/ and $a[4] > 0) ? $a[4] : 1;
        $hash->{TIMEOUT}                   = AttrVal($name, "nonblockingTimeOut", 60);
        $hash->{MODE}                      = $a[2];
        $hash->{ADDRESS}                   = $a[3];
        $hash->{MISSING_MODUL}             = $missingModul;
        $hash->{helper}{active}            = 1;
        $hash->{helper}{maybe}             = 0;
        $hash->{helper}{cnt}{th}           = 0;
        $hash->{helper}{cnt}{maybe}        = 0;
        $hash->{helper}{cnt}{state}        = 0;
        $hash->{helper}{cnt}{exec}         = 0;
        $hash->{helper}{nextScan}          = 0;
        $hash->{helper}{interval}{present} = 1;
        $hash->{helper}{interval}{absent}  = 1;
        $hash->{helper}{interval}{init}    = 30;
        $hash->{helper}{curState}          = "init";
        $hash->{helper}{DISABLED}          = 0;
        $hash->{helper}{disp}{condense}    = 1;
        $hash->{helper}{disp}{verbose}     = 0;
        $hash->{helper}{updateConfig}      = $name . ".Initialize";

        Log3 $name, 3, "$ModuleName ($name) - 'missingModul: $missingModul";
        $hash->{helper}{Ping}           = ($missingModul !~ /Net::Ping/) ? 1 : 0;
        $hash->{helper}{IO_Async_Loop}  = ($missingModul !~ /IO::Async::Loop/) ? 1 : 0;
        $hash->{helper}{Net_Async_Ping} = ($missingModul !~ /Net::Async::Ping/) ? 1 : 0;
        $hash->{helper}{List_Util}      = ($missingModul !~ /List::Util/) ? 1 : 0;

        if    ($a[2] eq "net-ping-tcp") {
            if ($^O !~ m/linux/) {
              my $msg = "net-ping-tcp is only supported by linux";
              Log3 $name, 2, "$ModuleName ($name) - " . $msg;
              return $msg;
            }
            elsif (!$hash->{helper}{Ping}) {
              my $msg = "Perl modul Net::Ping is not installed.";
              Log3 $name, 2, "$ModuleName ($name) - " . $msg;
              return $msg;
            }
            eval {
              my $p = Net::Ping->new('tcp', 2);
              $p->ping($hash->{ADDRESS});
            };

            if ($@) {
              my $msg = $@;
              $msg =~ s/at \/.*\/73_PRESENCE2.pm line.*//gs;
              $msg = "Perl modul Net::Ping - $msg";
              Log3 $name, 2, "$ModuleName ($name) - " . $msg;
              return $msg;
            }

            delete $attr{$name}{nonblockingTimeOut};
            $hash->{MODE} = "sub net-ping:tcp";
            $hash->{helper}{os}{search} = "present";
            $hash->{helper}{os}{Cmd} = "PRESENCE2_net_ping('" .$name. "', '" . $hash->{ADDRESS}. "', 'tcp')";
        }
        elsif ($a[2] eq "net-ping-icmp") {
            if ($^O !~ m/linux/) {
              my $msg = "net-ping-icmp is only supported by linux";
              Log3 $name, 2, "$ModuleName ($name) - " . $msg;
              return $msg;
            }
            elsif (!$hash->{helper}{Ping}) {
              my $msg = "Perl modul Net::Ping is not installed.";
              Log3 $name, 2, "$ModuleName ($name) - " . $msg;
              return $msg;
            }

            eval {
              my $p = Net::Ping->new('icmp', 2);
              $p->ping($hash->{ADDRESS});
            };

            if ($@) {
              my $msg = $@;
              $msg =~ s/at \/.*\/73_PRESENCE2.pm line.*//gs;
              $msg = "Perl modul Net::Ping - $msg";
              Log3 $name, 2, "$ModuleName ($name) - " . $msg;
              return $msg;
            }

            delete $attr{$name}{nonblockingTimeOut};
            $hash->{MODE} = "sub net-ping:icmp";
            $hash->{helper}{os}{search} = "present";
            $hash->{helper}{os}{Cmd} = "PRESENCE2_net_ping('" .$name. "', '" . $hash->{ADDRESS}. "', 'icmp')";
        }
        elsif ($a[2] eq "net-ping-async") {
            if ($^O !~ m/linux/) {
              my $msg = "net-async-ping is only supported by linux";
              Log3 $name, 2, "$ModuleName ($name) - " . $msg;
              return $msg;
            }
            elsif (!$hash->{helper}{IO_Async_Loop}) {
              my $msg = "Perl modul IO::Async::Loop is not installed.";
              Log3 $name, 2, "$ModuleName ($name) - " . $msg;
              return $msg;
            }
            elsif (!$hash->{helper}{Net_Async_Ping}) {
              my $msg = "Perl modul Net::Async::Ping is not installed.";
              Log3 $name, 2, "$ModuleName ($name) - " . $msg;
              return $msg;
            }
            delete $attr{$name}{nonblockingTimeOut};
            $hash->{MODE} = "sub net-ping-async";
            $hash->{helper}{os}{search} = "present";
            $hash->{helper}{os}{Cmd} = "PRESENCE2_net_async_ping('" .$name. "', '" . $hash->{ADDRESS}. "')";
        }
        elsif ($a[2] eq "lan-ping") {
            delete $attr{$name}{nonblockingTimeOut};
            $hash->{helper}{os}{Cmd} = ($^O =~ m/(Win|cygwin)/) ? "ping -n 1 -4 $hash->{ADDRESS}"
                                      :($^O =~ m/solaris/)      ? "ping $hash->{ADDRESS} 4"
                                      :                           "ping -c 1 -w 1 $hash->{ADDRESS} 2>&1"
                                      ;

            $hash->{helper}{os}{search} = $^O =~ m/solaris/? 'is alive'
                                         :                   '(ttl|TTL)=\d+'
                                         ;

            if ($^O !~ m/solaris/ && $^O !~ m/(Win|cygwin)/) {
              my $pingAttr = "disable:0,1 "
                        . "pingParam "
                        . "thresholdAbsence "
                        . "intervalNormal "
                        . "intervalPresent "
                        . "powerCmd "
                        . "prGroup:multiple,static,dynamic "
                        . "prGroupDisp:condense,verbose "
                        . "FhemLog3Std:0,1 "
                        . $readingFnAttributes;
              setDevAttrList($hash->{NAME}, $pingAttr);
            }

        }
        elsif ($a[2] eq "netcat") {
            delete $attr{$name}{nonblockingTimeOut};
            my ($Address, $Port) = split(/:/, $hash->{ADDRESS});

            # return "$Address is not a valid IP address" if ($Address !~ m/^\s*([0-9]{1,3}\.){3}[0-9]{1,3}\s*$/);

            $hash->{helper}{os}{Cmd} = "nc -vz $Address $Port 2>&1";

            $hash->{helper}{os}{search} = 'succeeded';

            if ($^O !~ m/solaris/ && $^O !~ m/(Win|cygwin)/) {
              my $pingAttr = "disable:0,1 "
                        . "thresholdAbsence "
                        . "intervalNormal "
                        . "intervalPresent "
                        . "powerCmd "
                        . "prGroup:multiple,static,dynamic "
                        . "prGroupDisp:condense,verbose "
                        . "FhemLog3Std:0,1 "
                        . $readingFnAttributes;
              setDevAttrList($hash->{NAME}, $pingAttr);
            }

        }
        elsif ($a[2] eq "lan-bluetooth") {
            delete $attr{$name}{nonblockingTimeOut};
            DevIo_CloseDev($hash);# {DevIo_CloseDev($dev{prBtTest })}

            $attr{$name}{intervalNormal}   = 30;
            $attr{$name}{intervalPresent}  = 30;
            my ($dev,$port) = split(":",$a[4].":5222");
            return "$dev is not a valid IP address" if ($dev !~ m/^\s*([0-9]{1,3}\.){3}[0-9]{1,3}\s*$/);
            $hash->{DeviceName} = "$dev:$port";
        }
        elsif ($a[2] eq "bluetooth") {

            delete $attr{$name}{nonblockingTimeOut};

            if ($^O !~ m/linux/) {
              my $msg = "local bluetooth is only supported by linux";
              Log3 $name, 2, "$ModuleName ($name) - " . $msg;
              return $msg;
            }

            my $hcitool = qx(which hcitool);
            Log3 $name, 5, "$ModuleName ($name) - 'which hcitool' returns: $hcitool";
            chomp $hcitool;

            unless(-x $hcitool) {
              my $msg = "no hcitool binary found. Please check that the bluez package is properly installed";
              Log3 $name, 2, "$ModuleName ($name) - " . $msg;
              return $msg;
            }

            unless($a[3] =~ /^\s*([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\s*$/)
            {
                my $msg = "given address is not a bluetooth hardware address";
                Log3 $name, 2, "$ModuleName ($name) - ".$msg;
                return $msg
            }

            my $blueAttr = "disable:0,1 "
                      . "thresholdAbsence "
                      . "intervalNormal "
                      . "intervalPresent "
                      . "powerCmd "
                      . "prGroup:multiple,static,dynamic "
                      . "prGroupDisp:condense,verbose "
                      . "FhemLog3Std:0,1 "
                      . "hcitoolParam:name,info ";

            my $hciDev = qx(hcitool dev);

            if ($hciDev =~ /Devices:/) {
              $hciDev =~ s/\s+/ /g;
              $hciDev =~ s/Devices:\s//g;
              $hciDev =~ s/(\s..:..:..:..:..:..)//g;
              $hciDev =~ s/\s+$//g;
              $hciDev =~ s/\s+/,/g;
              $hash->{helper}{os}{hci} = $hciDev;
              $blueAttr .= "bluetoothHciDevice:" . $hciDev . " ";
            }
            $blueAttr .= $readingFnAttributes;
            setDevAttrList($hash->{NAME}, $blueAttr);

            $hash->{helper}{os}{bluetoothHciDevice} = AttrVal($name, "bluetoothHciDevice", "");
            $hash->{helper}{os}{hcitoolParam} = AttrVal($name, "hcitoolParam", "name");

            $hash->{helper}{os}{Cmd}  = "hcitool";
            $hash->{helper}{os}{Cmd} .= " -i " . $hash->{helper}{os}{bluetoothHciDevice} if $hash->{helper}{os}{bluetoothHciDevice} ne "";

            $hash->{helper}{os}{Cmd} .= ' ' . $hash->{helper}{os}{hcitoolParam} . ' ' . $hash->{ADDRESS} . ' 2>/dev/null';
            if ($hash->{helper}{os}{hcitoolParam} eq "name") {
              $hash->{helper}{os}{search} = '[A-Za-z0-9]+';
            } else {
              $hash->{helper}{os}{search} = '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}';
            }
        }
        elsif ($a[2] =~ /(shellscript|function)/) {
            delete $attr{$name}{nonblockingTimeOut};
            if($def =~ /[ \t]+cmd:(.*?)[ \t]+scan:(.*)[ \t]*$/s) {
                $hash->{helper}{os}{Cmd} = $1;
                $hash->{helper}{os}{search} = $2;

                delete $hash->{helper}{ADDRESS};
                delete $hash->{ADDRESS};

                if($hash->{helper}{os}{Cmd} =~ /\|/) {
                    my $msg = "The command contains a pipe ( | ) symbol, which is not allowed.";
                    Log3 $name, 2, "$ModuleName ($name) - ".$msg;
                    return $msg;
                }
            }
            return "define $name failed. Please enter command and parse string" if(  !defined $hash->{helper}{os}{Cmd}    || $hash->{helper}{os}{Cmd}    eq ""
                                                                                  || !defined $hash->{helper}{os}{search} || $hash->{helper}{os}{search} eq ""
                                                                                  );
        }
        elsif ($a[2] eq "daemon") {
            return "only one daemon allowed" if(PRESENCE2_getDaemonName() ne $name);
            delete $attr{$name}{intervalPresent};
            delete $attr{$name}{thresholdAbsence};
            delete $attr{$name}{bluetoothHciDevice};
            delete $attr{$name}{hcitoolParam};
            $hash->{helper}{interval}{absent}  = 30;
            $hash->{helper}{interval}{present} = 30;

            my $daemonAttr = "disable:0,1 "
                        . "intervalNormal "
                        . "nonblockingTimeOut "
                        . "prGroup:multiple,static,dynamic "
                        . "prGroupDisp:condense,verbose "
                        . "FhemLog3Std:0,1 "
                        . $readingFnAttributes;
            setDevAttrList($hash->{NAME}, $daemonAttr);

            foreach (keys %{ $hash->{READINGS} }) {
              readingsDelete($hash, $_) if $_ =~ /^pGrp__total/ && defined $hash->{READINGS}{$_}{VAL};
            }
        }
        else {
            my $msg  = "unknown mode \"".$a[2]."\" in define statement. Please use:";
               $msg -= "lan-ping, netcat, daemon, shellscript, function, bluetooth,";
               $msg -= " lan-bluetooth, net-ping-icmp, net-ping-tcp, net-ping-async";
            Log3 $name, 2, "$ModuleName ($name) - ".$msg;
            return $msg
        }
    }
    else {
        my $msg = "wrong syntax for define statement: define <name> PRESENCE2 <mode> <device-address> ";
        Log3 $name, 2, "$ModuleName ($name) - $msg";
        return $msg;
    }

    delete($hash->{helper}{cachednr});

    readingsSingleUpdate($hash, "model", $hash->{MODE}, 0);

    if ($init_done) {
       RemoveInternalTimer("PRESENCE2_updateConfig");
       InternalTimer(2,"PRESENCE2_updateConfig", $hash->{helper}{updateConfig});
    }

    PRESENCE2_Log $name, 2, "define done";

    return undef;
}

#######################################################################
sub PRESENCE2_Undef($$) {
    my ($hash, $arg) = @_;

    if ($hash->{MODE} eq "daemon" && PRESENCE2_getAllEntities()){
        return "deletion of daemon not possible unless objects still present";
    }
    BlockingKill($hash->{helper}{RUNNING_PID}) if(defined($hash->{helper}{RUNNING_PID}));

    RemoveInternalTimer($hash);
    DevIo_CloseDev($hash);
}

#####################################
sub PRESENCE2_updateConfig($){
   my ($timerpara) = @_;

   # my ( $name, $func ) = split( /\./, $timerpara );
   my $index = rindex( $timerpara, "." );    # rechter Punkt
   my $func  = substr $timerpara, $index + 1, length($timerpara);    # function extrahieren
   my $name  = substr $timerpara, 0, $index;                         # name extrahieren
   my $hash  = $defs{$name};

   my @daemons = devspec2array("TYPE=PRESENCE2:FILTER=MODE=daemon");
   my $daemonName;

   if (int @daemons > 1) {

     PRESENCE2_Log $name, 2, "more than one daemon found";

     $daemonName = shift @daemons;# leave the first alive

     CommandDelete(undef,$_)foreach (@daemons);
   } elsif (int @daemons == 1) {

     $daemonName = $daemons[0];
     PRESENCE2_Log $name, 2, "one daemon found: " . $daemonName;

   } else {
     undef $daemonName;
   }

   if (!defined $daemonName){         # daemon not available
     PRESENCE2_Log $name, 2, "no daemon found. Creating one";
     CommandDefine(undef,'PsnceDaemon PRESENCE2 daemon daemon');
   }

   my $dN = PRESENCE2_getDaemonName();
   PRESENCE2_Log $name, 2, "using daemon: " . $dN;
   PRESENCE2_doDaemonCleanup();

   RemoveInternalTimer(undef,"PRESENCE2_daemonScanScheduler");
   InternalTimer(gettimeofday() + $attr{$dN}{intervalNormal}, "PRESENCE2_daemonScanScheduler", $defs{$dN}, 0);

   PRESENCE2_doEvtSetup("init");
   foreach (devspec2array("TYPE=PRESENCE2:FILTER=MODE=lan-bluetooth")){
     my $hash = $defs{$_};
     next if ($hash->{helper}{DISABLED} == 1);
     next if (defined $hash->{FD});
     DevIo_OpenDev($hash, 0, "PRESENCE2_lanBtDoInit");
   }

   my $gua = AttrVal("global","userattr","");
   $gua .=  ($gua =~ m/presentCycle/   ? "" : " presentCycle"  )
           .($gua =~ m/presentReading/ ? "" : " presentReading")
            ;

   CommandAttr(undef, "global userattr $gua") if(AttrVal("global","userattr","") ne $gua);
}

#####################################
sub PRESENCE2_Notify($$) {
    my ($hash, $dev) = @_;

    return undef if(!defined $hash || !defined $hash->{NAME} || !defined $hash->{MODE} || $hash->{MODE} ne "daemon"
                 || !defined $dev  || !defined $dev->{NAME}  || $dev->{NAME}  ne "global" );

    my $events = deviceEvents($dev, 1);
    my $name = $hash->{NAME};

    return "" if(IsDisabled($name)); # Return without any further action if the module is disabled

    if($dev->{NAME} eq "global" && grep(m/^INITIALIZED|REREADCFG$/, @{$events}))
    {

       PRESENCE2_Log $name, 2, "starting initial Config ";

       # initialize DEBUG LOG function
       PRESENCE2_Log $name, 2, "starting initial dbgLogInit";
       PRESENCE2_dbgLogInit($hash, "init", "verbose", AttrVal($name, "verbose", -1));
       # end initialize DEBUG LOG function

       PRESENCE2_Log $name, 2, "starting initial updateConfig " . $hash->{helper}{updateConfig};
       RemoveInternalTimer("PRESENCE2_updateConfig");
       PRESENCE2_updateConfig ($hash->{helper}{updateConfig});
    }

    if (grep /^(ATTR|DELETEATTR).*(presentCycle|presentReading)/,@{$events}){
        PRESENCE2_doEvtSetup($name."#".$_) foreach(@{$events});
    }

}

#####################################
sub PRESENCE2_Set($@) {
    my ($hash, @a) = @_;
    my $name = $hash->{NAME};

    return "No argument given" if(!defined($a[1]));

    my ($cmd) = ($a[1]);

    my $powerCmd = AttrVal($name, "powerCmd", undef);

    my $usage  = "Unknown argument " .$a[1]. ", choose one of";
       $usage .= ($hash->{MODE} eq "daemon" ? "" : " statusRequest:noArg");
       $usage .= " clearCounts:".($hash->{MODE} eq "daemon" ? "daemon,allEntities": "noArg");
       $usage .= " killChilds:noArg" if ($hash->{MODE} eq "daemon");
       $usage .= " active:noArg" if(!$hash->{helper}{active} && $hash->{MODE} ne "daemon");
       $usage .= " inactive:noArg" if($hash->{helper}{active} && $hash->{MODE} ne "daemon");
       $usage .= " power:noArg" if(defined($powerCmd) && $hash->{MODE} ne "daemon");

    if   ($cmd eq "statusRequest"){
        if($hash->{MODE} =~ m/(lan-ping|netcat|shellscript|function|bluetooth)/) {
            PRESENCE2_Log $name, 5, "starting local scan";
            readingsSingleUpdate($hash, "state", $cmd, 1);
            my $daemon = PRESENCE2_getDaemonName();
            return PRESENCE2_daemonScanScheduler($defs{$daemon}, $name);
        }
        elsif ($hash->{MODE} =~ m/(lan-bluetooth)/){
            if(exists($hash->{FD})){
                PRESENCE2_lanBtWrite($hash, "now");
            }
            else{
                return "$ModuleName definition \"$name\" is not connected to ".$hash->{DeviceName};
            }
        }
    }
    elsif($cmd eq "clearCounts"){
        $hash->{helper}{cnt}{$_} = 0 foreach (keys %{$hash->{helper}{cnt}});
        my @clearEnt = ($name);
        push @clearEnt,PRESENCE2_getBlockingEntites() if (defined $a[2] && $a[2] eq "allEntities");
        foreach (@clearEnt){
            my $cHash = $defs{$_};
            readingsBeginUpdate($cHash);
            foreach( (grep /Cnt$/,keys%{$cHash->{READINGS}})
                    ,"daemonMaxScanTime","daemonMinScanTime"
                    ){
                next if(!defined $cHash->{READINGS}{$_});
                readingsBulkUpdate($cHash, $_, 0);
            }
            readingsEndUpdate($cHash, 1);
        }
    }
    elsif($cmd eq "killChilds"){
        BlockingKill($hash->{helper}{RUNNING_PID}) if(defined($hash->{helper}{RUNNING_PID}));
        delete $hash->{helper}{RUNNING_PID};
    }
    elsif($cmd eq "active")
    {
        RemoveInternalTimer($hash);
        $hash->{helper}{DISABLED} = 0;
        $hash->{helper}{active}   = 1;
        if ($hash->{MODE} eq "lan-bluetooth"){
          if(defined($hash->{FD})){
            PRESENCE2_lanBtDoInit($hash) ;
          } else {
            DevIo_OpenDev($hash, 0, "PRESENCE2_lanBtDoInit");
          }
        }
        readingsSingleUpdate($hash, "state", "active", 1);
    }
    elsif($cmd eq "inactive")
    {
        $hash->{helper}{DISABLED} = 1;
        $hash->{helper}{active}   = 0;
        PRESENCE2_lanBtWrite($hash, "stop");
        readingsSingleUpdate($hash, "state", "inactive", 1);
    }
    elsif(defined($powerCmd) && $cmd eq "power")
    {
        my %specials = (
          '%NAME' => $name,
          '%ADDRESS' => (defined($hash->{ADDRESS}) ? $hash->{ADDRESS} : ""),
          '%ARGUMENT' => (defined($a[2]) ? $a[2] : "")
        );

        $powerCmd = EvalSpecials($powerCmd, %specials);

        PRESENCE2_Log $name, 5, "$ModuleName ($name) - executing powerCmd: $powerCmd";
        my $return = AnalyzeCommandChain(undef, $powerCmd);

        if($return)
        {
            PRESENCE2_Log $name, 3, "$ModuleName ($name) - executed powerCmd failed: ".$return;
            readingsSingleUpdate($hash, "powerCmd", "failed",1);
            return "executed powerCmd failed: ".$return;
        }
        else
        {
            readingsSingleUpdate($hash, "powerCmd", "executed",1);
        }
    }
    else{
        return $usage;
    }
}

#####################################
sub PRESENCE2_Get($@) {
    my ($hash, @a) = @_;
    my $name = $hash->{NAME};

    return "No argument given" if(!defined($a[1]));

    my ($cmd) = ($a[1]);

    if   ($cmd eq "list"){
        my $globAttr = AttrVal("global","showInternalValues","undef");

        $attr{global}{showInternalValues} = $a[2] eq "full" ? 1 : 0;
        my $ret = CommandList(undef,$name);

        if ($globAttr eq "undef"){
            delete $attr{global}{showInternalValues};
        }
        else{
            $attr{global}{showInternalValues} = $globAttr;
        }
        return $ret;
    }
    elsif($cmd eq "childInfo"){
        if (defined $a[2] && $a[2] eq "all"){
            return "BlockingCalls:\n".join("\nnext:----------\n",
                    map {(my $foo = $_) =~ s/(Pid:|Fn:|Arg:|Timeout:|ConnectedVia:)/\n   $1/g; $foo;}
                    grep /PRESENCE2/,BlockingInfo(undef,undef));
        }
        else{
            return "BlockingCalls:\n".join("\nnext:----------\n",
                    map {(my $foo = $_) =~ s/(Pid:|Fn:|Arg:|Timeout:|ConnectedVia:)/\n   $1/g; $foo;}
                    BlockingInfo(undef,undef));
        }
    }
    elsif($cmd eq "statusInfo"){
        my $ret;
        my @rets;
        if($hash->{MODE} eq "daemon"){
            if (defined $a[2] && $a[2] eq "definition"){
                $ret .= "daemon info\n"
                       .sprintf ("%-10s %-14s %-14s %-16s %10s:%-5s %5s",
                                ,"prGroup"
                                ,"MODE"
                                ,"entity"
                                ,""
                                ,"intvNorm"
                                ,"Pres"
                                ,"thres"
                                 );
                foreach my $e ($hash->{NAME} ){
                    push @rets, sprintf ("%-10s %-14s %-14s %-16s %10s:%-5s %5s",
                                ,AttrVal    ($e,"prGroup","default")
                                ,InternalVal($e,"MODE"   ,"--")
                                ,$e
                                ,""
                                ,$defs{$e}{helper}{interval}{absent}
                                ,"--"
                                ,"--"
                                 );
                    ;
                }
                $ret .= "\n".join("\n",sort @rets);
                @rets = ();
                $ret .= "\n"."\nentity info";
                $ret .= "\n".sprintf ("%-10s %-14s %-14s %-17s %10s:%-5s %5s\n",
                                ,"prGroup"
                                ,"MODE"
                                ,"entity"
                                ,"ADDRESS"
                                ,"intvNorm"
                                ,"Pres"
                                ,"thres"
                                 );
                foreach my $e (devspec2array("TYPE=PRESENCE2:FILTER=MODE!=(daemon)")){
                    push @rets, sprintf ("%-10s %-14s %-14s %-17s %10s:%-5s %5s",
                                ,AttrVal    ($e,"prGroup","default")
                                ,InternalVal($e,"MODE"   ,"--")
                                ,$e
                                ,InternalVal($e,"ADDRESS","--")
                                ,($defs{$name}{helper}{interval}{absent} > $defs{$e}{helper}{interval}{absent}  ? $defs{$name}{helper}{interval}{absent} : $defs{$e}{helper}{interval}{absent})
                                ,($defs{$name}{helper}{interval}{absent} > $defs{$e}{helper}{interval}{present} ? $defs{$name}{helper}{interval}{absent} : $defs{$e}{helper}{interval}{present})
                                ,AttrVal($e,"thresholdAbsence","1")
                                 );
                    ;
                }
                $ret .= "\n".join("\n",sort @rets);
                @rets = ();
                $ret .= "\n"."\nevent info";
                $ret .= "\n".sprintf ("%-14s %-16s %10s\n",
                                ,"entity"
                                ,"reading"
                                ,"cycle"
                                 );
                foreach my $e (keys %{$hash->{helper}{evnt}}){
                    push @rets, sprintf ("%-14s %-16s %10s",
                                ,$e
                                ,$hash->{helper}{evnt}{$e}{read}
                                ,$hash->{helper}{evnt}{$e}{cycle}
                                 );
                    ;
                }
                $ret .= "\n".join("\n",sort @rets);
            }
            else{
                $ret .= sprintf ("%-10s %-14s %-14s %-20s %-20s %9s %5s:%-8s %8s",
                                ,"prGroup"
                                ,"entity"
                                ,"presence"
                                ,"last disappear"
                                ,"last appear"
                                ,"stateChng"
                                ,"maybe"
                                ,"thresHld"
                                ,"executed"
                                 );
                foreach my $e (devspec2array("TYPE=PRESENCE2:FILTER=MODE!=(daemon)")){
                    push @rets, sprintf ("%-10s %-14s %-14s %-20s %-20s %9s %5s:%-8s %8s",
                                ,AttrVal($e,"prGroup","default")
                                ,$e
                                ,ReadingsVal($e,"presence","--")
                                ,ReadingsVal($e,"lastDisappear","--")
                                ,ReadingsVal($e,"lastAappear","--")
                                ,ReadingsVal($e,"appearCnt","0")
                                ,ReadingsVal($e,"maybeCnt","0")
                                ,ReadingsVal($e,"thresHldCnt","0")
                                ,$defs{$e}{helper}{cnt}{exec}
                                 );
                    ;
                }
                $ret .= "\n".join("\n",sort @rets);
                @rets = ();
                $ret .= "\n"."\nevent info";
                $ret .= "\n".sprintf ("%-14s %-10s",
                                ,"entity"
                                ,"state"
                                 );
                foreach my $e (keys %{$hash->{helper}{evnt}}){
                    push @rets, sprintf ("%-14s %-10s",
                                ,$e
                                ,ReadingsVal($name,"evt_".$e,"--")
                                 );
                    ;
                }
                $ret .= "\n".join("\n",sort @rets);
                @rets = ();
            }
        }
        return $ret;
    }
    else{
        return "Unknown argument $cmd, choose one of "
                   ." list:normal,full" 
                   .($hash->{MODE} =~ m/(daemon)/ ? " statusInfo:status,definition"
                                                   ." childInfo:PRESENCE2,all"
                                                  :"")
                   ;
    }

    return undef;
}

#####################################
sub PRESENCE2_Attr(@) {
    my @a = @_;
    my $hash = $defs{$a[1]};
    my $name = $hash->{NAME};

    if ($a[2] eq "verbose") {
      PRESENCE2_dbgLogInit($hash, $a[0], $a[2], $a[3]) if !$hash->{helper}{FhemLog3Std};
    }

    if($a[2] eq "FhemLog3Std") {
      if ($a[0] eq "set") {
        return "FhemLog3Std: $a[3]. Valid is 0 or 1." if $a[3] !~ /[0-1]/;
        $hash->{helper}{FhemLog3Std} = $a[3];
        if ($a[3]) {
          PRESENCE2_dbgLogInit($hash, "del", "verbose", 0) if AttrVal($name, "verbose", 0) == 5;
        } else {
          PRESENCE2_dbgLogInit($hash, "set", "verbose", 5) if AttrVal($name, "verbose", 0) == 5 && $a[3] == 0;
        }
      } else {
        $hash->{helper}{FhemLog3Std} = 0;
        PRESENCE2_dbgLogInit($hash, "set", "verbose", 5) if AttrVal($name, "verbose", 0) == 5;
      }
    }

    if ($a[0] eq "set") {
        if ($a[2] =~ m/^(disable)$/ ) {
            return $a[2] . " must be 0 or 1" if($a[3] !~ /0|1/) ;

            if ( $a[3] == 0 ){
              RemoveInternalTimer($hash);
              $hash->{helper}{DISABLED} = 0;
              readingsSingleUpdate($hash, "state", "active", 1);
              if ($hash->{MODE} eq "lan-bluetooth"){
                if(defined($hash->{FD})){
                  PRESENCE2_lanBtDoInit($hash) ;
                } else {
                  DevIo_OpenDev($hash, 0, "PRESENCE2_lanBtDoInit");
                }
              }
            }
            else {#disable
              readingsSingleUpdate($hash, "state", "disabled", 1);
              $hash->{helper}{DISABLED} = 1;
              PRESENCE2_lanBtWrite($hash, "stop");
            }
        }

        elsif($a[2] eq "thresholdAbsence") {
            return $a[2] . " must be a valid integer number" if($a[3] !~ /^\d+$/) ;
            return $a[2] . " not used by daemon"             if($hash->{MODE} eq "daemon");
        }

        elsif($a[2] =~ m/^interval(Normal|Present|nonblockingTimeOut)$/) {
            return $a[2] . " not a positive number" if( $a[3] !~ /^\d+$/ or $a[3] < 0);
            return $a[2] . " must be in between 30..240 seconds" if(($a[3] < 30 || $a[3] > 240) && $a[2] eq "nonblockingTimeOut");

            $hash->{helper}{nextScan} = gettimeofday();

            if ($hash->{MODE} eq "daemon"){
                $hash->{helper}{nextScan} += $a[3];
                return $a[2] . " not allowed for daemon entites" if($a[2] eq "intervalPresent");

                RemoveInternalTimer(undef,"PRESENCE2_daemonScanScheduler");
                InternalTimer($hash->{helper}{nextScan}, "PRESENCE2_daemonScanScheduler", $hash, 0);

                if($a[2] eq "nonblockingTimeOut") {
                  $hash->{TIMEOUT} = $a[3];
                } else{
                  $hash->{INTERVAL} = $a[3];
                }
            } else {
                return $a[2] . " not allowed for $hash->{MODE} entites" if($a[2] eq "nonblockingTimeOut");
            }

            if ($a[2] eq "intervalPresent"){
                $hash->{helper}{interval}{present} = $a[3];
            } elsif ($a[2] eq "intervalNormal") {
                $hash->{helper}{interval}{absent}  = $a[3];
                $hash->{helper}{interval}{present} = AttrVal($name, "intervalPresent", $a[3]);
            }
        }
        elsif ($a[2] eq "bluetoothHciDevice" ) {
            return $a[2] . " only used by bluetooth" if($hash->{MODE} ne "bluetooth");

            $hash->{helper}{os}{bluetoothHciDevice} = $a[3];
            $hash->{helper}{os}{Cmd} = 'hcitool -i ' . $hash->{helper}{os}{bluetoothHciDevice} . ' ' . $hash->{helper}{os}{hcitoolParam} . ' ' . $hash->{ADDRESS} . ' 2>/dev/null';

            if ($hash->{helper}{os}{hcitoolParam} eq "name") {
              $hash->{helper}{os}{search} = '[A-Za-z0-9]+';
            } else {
              $hash->{helper}{os}{search} = '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}';
            }
        }
        elsif ($a[2] eq "hcitoolParam" ) {
            return $a[2] . " only used by bluetooth" if($hash->{MODE} ne "bluetooth");

            $hash->{helper}{os}{hcitoolParam} = $a[3];

            $hash->{helper}{os}{Cmd}  = "hcitool";
            $hash->{helper}{os}{Cmd} .= " -i " . $hash->{helper}{os}{bluetoothHciDevice} if $hash->{helper}{os}{bluetoothHciDevice} ne "";

            $hash->{helper}{os}{Cmd} .= ' ' . $hash->{helper}{os}{hcitoolParam} . ' ' . $hash->{ADDRESS} . ' 2>/dev/null';
            if ($hash->{helper}{os}{hcitoolParam} eq "name") {
              $hash->{helper}{os}{search} = '[A-Za-z0-9]+';
            } else {
              $hash->{helper}{os}{search} = '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}';
            }
        }
        elsif ($a[2] eq "pingParam" ) {
            return $a[2] . " only used by ping for Linux" if($hash->{MODE} ne "lan-ping");
            return $a[2] . " only used by ping for Linux/Windows/CygWin" if($^O =~ m/solaris/ || $^O =~ m/(Win|cygwin)/);

            my $regex = qr/(-[cwi] ?\d{1,3}|-q -[cwi] ?\d{1,3}){0,1} ?(-[cwi] ?\d{1,3}|-q -[cwi] ?\d{1,3}){0,1} ?(-[cwi] ?\d{1,3}|-q -[cwi] ?\d{1,3}|-q){0,1}/ip;

            if ( $a[3] =~ m/$regex/g ) {
               return $a[2] . " mismatched parameters $a[3]" if length(${^MATCH}) != length($a[3]);
            } else {
               return $a[2] . " mismatched parameters $a[3]";
            }

            $hash->{helper}{os}{Cmd} = ($^O =~ m/(Win|cygwin)/) ? "ping $a[3] $hash->{ADDRESS}"
                                     : ($^O =~ m/solaris/)      ? "ping $hash->{ADDRESS} 4"
                                     :                            "ping $a[3] $hash->{ADDRESS} 2>&1"
                                     ;
        }
        elsif($a[2] eq "powerCmd")
        {
            my $powerOnFn = $a[3];

            $powerOnFn =~ s/^\s+//;
            $powerOnFn =~ s/\s+$//;

            if($powerOnFn eq "")
            {
                return "powerCmd contains no value";
            }
        }

    }

    elsif($a[0] eq "del") {
        if ($a[2] =~ m/^(disable)$/ ) {
          RemoveInternalTimer($hash);
          $hash->{helper}{DISABLED} = 0;
          readingsSingleUpdate($hash, "state", "active", 1);
          if ($hash->{MODE} eq "lan-bluetooth"){

            if(defined($hash->{FD})) {
              PRESENCE2_lanBtDoInit($hash) ;
            } else {
              DevIo_OpenDev($hash, 0, "PRESENCE2_lanBtDoInit");
            }
          }
        }

        elsif($a[2] eq "intervalPresent"){
            $hash->{helper}{interval}{present} = $hash->{helper}{interval};
        }

        elsif($a[2] eq "intervalNormal"){
            $hash->{helper}{interval}{absent}  = $hash->{MODE} eq "lan-bluetooth" ? 30 : 1;
            $hash->{helper}{interval}{present} = AttrVal($name, "intervalPresent", $hash->{helper}{interval}{absent});
            $hash->{INTERVAL} = 1;
        }
        elsif($a[2] eq "nonblockingTimeOut") {
            $hash->{TIMEOUT} = 60;
        }
        elsif ($a[2] eq "bluetoothHciDevice" ) {

            $hash->{helper}{os}{bluetoothHciDevice} = "";
            $hash->{helper}{os}{Cmd}    = 'hcitool ' . $hash->{helper}{os}{hcitoolParam} . ' ' . $hash->{ADDRESS} . ' 2>/dev/null';

            if ($hash->{helper}{os}{hcitoolParam} eq "name") {
              $hash->{helper}{os}{search} = '[A-Za-z0-9]+';
            } else {
              $hash->{helper}{os}{search} = '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}';
            }
        }
        elsif ($a[2] eq "hcitoolParam" ) {
            $hash->{helper}{os}{hcitoolParam} = "name";
            $hash->{helper}{os}{search} = '[A-Za-z0-9]+';

            $hash->{helper}{os}{Cmd}  = "hcitool";
            $hash->{helper}{os}{Cmd} .= " -i " . $hash->{helper}{os}{bluetoothHciDevice} if $hash->{helper}{os}{bluetoothHciDevice} ne "";

            $hash->{helper}{os}{Cmd} .= ' ' . $hash->{helper}{os}{hcitoolParam} . ' ' . $hash->{ADDRESS} . ' 2>/dev/null';

        }
        elsif ($a[2] eq "pingParam" ) {

            $hash->{helper}{os}{Cmd} = ($^O =~ m/(Win|cygwin)/) ? "ping -n 1 -4 $hash->{ADDRESS}"
                                     : ($^O =~ m/solaris/)      ? "ping $hash->{ADDRESS} 4"
                                     :                            "ping -c 1 -w 1 $hash->{ADDRESS} 2>&1"
                                     ;
        }
    }

    if($a[2] eq "intervalNormal"){
        PRESENCE2_lanBtUpdtTiming($hash);
    }

    elsif($a[2] eq "intervalPresent"){
        PRESENCE2_lanBtUpdtTiming($hash);
    }

    elsif($a[2] eq "prGroupDisp"){
        if ($a[0] eq "set") {                          # || $a[3] != m/(condense|verbose)/){
            $hash->{helper}{disp}{$_} = 0 foreach ("condense","verbose");#reset all
            foreach my $disp (split(",",$a[3])){
                return "$a[3] not vaild for $a[2]. Select on of condense|verbose" if ($disp !~ m/^(condense|verbose)$/);
            }
            foreach my $disp (split(",",$a[3])){
                $hash->{helper}{disp}{$disp} = 1;
            }
        }
        else{
            $hash->{helper}{disp}{condense}    = 1;
            $hash->{helper}{disp}{verbose}     = 0;
        }
        PRESENCE2_doDaemonCleanup();
    }

    elsif   ($a[2] eq "prGroup") {
        my %pgH = ( "static"  => 1
                   ,"dynamic" => 1
                   );

        if($a[0] eq "set"){
          $pgH{$_} = 1 foreach(grep/../, split(",", $a[3]));
        }

        foreach my $e (grep !/^$name$/,devspec2array("TYPE=PRESENCE2")){
            if (defined $attr{$e}{prGroup} && $attr{$e}{prGroup}){
                $pgH{$_} = 1 foreach(grep/../, split(",", $attr{$e}{prGroup}));
            }
        }
        my @pGroups = keys %pgH;
        my $pgs1 = join(",", @pGroups);
        my $pgs = " prGroup:multiple" . ($pgs1 ? "," . $pgs1 . " " : " ");
        $modules{PRESENCE2}{AttrList} =~ s/ prGroup.*? /$pgs/;
        my $dn = PRESENCE2_getDaemonName();
        $defs{$dn}{helper}{prGroups} = \@pGroups if (defined $dn && $dn ne "");
    }
    return undef;
}

#####################################
sub PRESENCE2_setNotfiyDev($) {############## todo
    my ($hash) = @_;

    notifyRegexpChanged($hash,"(global|".$hash->{EVENT_PRESENT}."|".$hash->{EVENT_ABSENT}.")");
}

#####################################
sub PRESENCE2_getBlockingEntites() {
    return devspec2array("TYPE=PRESENCE2:FILTER=MODE!=(daemon|lan-bluetooth)");
}

#####################################
sub PRESENCE2_getAllEntities() {
    return devspec2array("TYPE=PRESENCE2:FILTER=MODE!=(daemon)");
}

#####################################
sub PRESENCE2_getDaemonName() {
    my @a = devspec2array("TYPE=PRESENCE2:FILTER=MODE=daemon");
    return defined $a[0]? $a[0] : undef;
}

#####################################
sub PRESENCE2_lanBtWrite($$){
    my ($hash, $cmd) = @_;
    if (defined $hash->{FD}){
       PRESENCE2_Log $hash->{NAME}, 4 , "write : $cmd";
       DevIo_SimpleWrite($hash, $cmd . "\n", 2);
    }
    else{
       PRESENCE2_Log $hash->{NAME}, 4, "write ignored - no FD: $cmd ";
    }
}

#####################################
sub PRESENCE2_lanBtDoInit($){  ############## todo
    my ($hash) = @_;

    PRESENCE2_Log $hash->{NAME}, 4, "do init";
    if(!$hash->{helper}{DISABLED}){
        readingsSingleUpdate($hash, "state", "active", 1);
        PRESENCE2_lanBtUpdtTiming($hash);
    }
    else{
        readingsSingleUpdate($hash, "state", "disabled", 1);
    }
}

#####################################
sub PRESENCE2_lanBtRead($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $buf = DevIo_SimpleRead($hash);

    return "" if(!defined($buf));

    chomp $buf;

    readingsBeginUpdate($hash);

    for my $line (split /^/, $buf){
        PRESENCE2_Log $name, 5, "received data: $line";

        if($line =~ /^(absence|absent|present)(;*)(.*)/ && !$hash->{helper}{DISABLED}){
            my ($state,undef,$data) = ($1,$2,$3);
            PRESENCE2_Log $name, 4 , "status info:$state";
            $state = "absent" if($state eq "absence");
            PRESENCE2_ProcessState($hash, $state);

            if(defined $data){
                if($state eq "present"){
                    if($data =~ /^(.*);(.+)$/){# multi parameter response
                        foreach(split(";",$data)){
                            my ($read,$val) = split("=",$_,2);
                            next if (!defined $val);
                            readingsBulkUpdate($hash, $read, $val);
                        }
#                        PRESENCE2_lanBtProcessAddonData($hash, $data) ;
#                        readingsBulkUpdate($hash, "room"       , $2);
#                        readingsBulkUpdate($hash, "device_name", $1);
                    }
                    else{# single parameter response
                        readingsBulkUpdate($hash, "room"       , "unknown");
                        readingsBulkUpdate($hash, "device_name", $data);
                    }
                }
            }
        }
        elsif($line eq "command accepted"){
            readingsBulkUpdate($hash, "command_accepted", "yes");
        }
        elsif($line eq "command rejected"){
            readingsBulkUpdate($hash, "command_accepted", "no");
        }
        elsif($line =~ /socket_closed;(?:room='?)?(.+?)'?$/){
            PRESENCE2_Log $name, 3, "collectord lost connection to room $1";
        }
        elsif($line =~ /socket_reconnected;(?:room='?)?(.+?)'?$/){
            PRESENCE2_Log $name , 3, "collectord reconnected to room $1";
        }
        elsif($line =~ /error;(?:room='?)?(.+?)'?$/){
            PRESENCE2_Log $name, 3, "room $1 cannot execute hcitool to check device";
        }
        elsif($line =~ /error$/){
            PRESENCE2_Log $name, 3, "presenced cannot execute hcitool to check device";
        }
    }
    readingsEndUpdate($hash, 1);
}

#####################################
sub PRESENCE2_lanBtUpdtTiming($) {
    my ($hash) = @_;
    if($hash->{MODE} eq "lan-bluetooth"){
        PRESENCE2_lanBtWrite($hash, $hash->{ADDRESS} . "|" . $hash->{helper}{interval}{$hash->{helper}{curState}});
    }
}

#####################################
sub PRESENCE2_lanBtReady($) {
    my ($hash) = @_;
    if(!$hash->{helper}{DISABLED}){
        return DevIo_OpenDev($hash, 1, "PRESENCE2_lanBtDoInit");
    }
}

#####################################
sub PRESENCE2_lanBtProcessAddonData($$){
    my ($hash, $data) = @_;
    my (undef, $h) = parseParams($data, ";");
    readingsBulkUpdate($hash, $_, $h->{$_}) foreach (keys %{$h});
}

#####################################
sub PRESENCE2_ProcessState($$) {
    my ($hash, $state) = @_;
    my $name = $hash->{NAME};

    if ($state !~ m/absent|present/)
    {
        readingsBulkUpdate($hash, "state", $state);
        return;
    }

    my $thresHld  = ReadingsVal($name, "state", "") eq "present" ? AttrVal($name, "thresholdAbsence", 1) : 1;
    $hash->{helper}{cnt}{exec}++;
    if (++$hash->{helper}{cnt}{th} >= $thresHld)
    {
        $hash->{helper}{cnt}{th} = 0;
        if ($hash->{helper}{curState} ne $state){
            PRESENCE2_Log $name, 4, "changed from $hash->{helper}{curState} to $state";
            $hash->{helper}{timestamp}{$state} = FmtDateTime(gettimeofday());
            readingsBulkUpdate($hash, "last".($state eq "present"?"Appear":"Disappear")   , $hash->{helper}{timestamp}{$state});
            readingsBulkUpdate($hash, "appearCnt", ++$hash->{helper}{cnt}{state}) if ($state eq "present");
            $hash->{helper}{curState} = $state;
            PRESENCE2_lanBtUpdtTiming($hash);
        }
        readingsBulkUpdate($hash, "state"      , $state) if(!$hash->{helper}{DISABLED});
        readingsBulkUpdate($hash, "thresHldCnt", 0     ) if($hash->{helper}{maybe});
        $hash->{helper}{maybe} = 0;

    } else {
        PRESENCE2_Log $name, 4, "device is $state after $hash->{helper}{cnt}{th} check. "
                   .($thresHld - $hash->{helper}{cnt}{th})." attempts left before going absent";
        readingsBulkUpdate($hash, "maybeCnt"   , ++$hash->{helper}{cnt}{maybe}) if(!$hash->{helper}{maybe});
        readingsBulkUpdate($hash, "thresHldCnt", $hash->{helper}{cnt}{th});
        $hash->{helper}{maybe} = 1;
    }

    readingsBulkUpdate($hash, "presence", ($hash->{helper}{maybe} ? "maybe ":"") . $state) if(!$hash->{helper}{DISABLED});
}

sub PRESENCE2_daemonScanScheduler($;$) {
    my ($hash, $scanMeNow) = @_;        # $scanMeNow: force a scan immediately for a single device
    my $name = $hash->{NAME};
    my $daemonInterval = AttrVal($name, "intervalNormal", 30);
    my $now = gettimeofday();

    if (defined $hash->{helper}{RUNNING_PID}){
        PRESENCE2_Log $name, 4, "skip scan due to running job";
        $hash->{helper}{cnt}{skip} = defined $hash->{helper}{cnt}{skip} ? ($hash->{helper}{cnt}{skip} + 1) : 1;
        readingsSingleUpdate($hash, "daemonSkipCnt", $hash->{helper}{cnt}{skip}, 1);
    }
    else{
        if($init_done){
            my @scanNowList = ();
            if (defined $scanMeNow && defined $defs{$scanMeNow}){
                push @scanNowList,$scanMeNow;
            }
            else{# search for scanabled
                foreach my $e (PRESENCE2_getBlockingEntites()){
                    my $eh = $defs{$e}{helper};
                    next if ($eh->{nextScan} > $now);
                    next if ($eh->{DISABLED} == 1);
                    $eh->{nextScan} = $now + $eh->{interval}{$eh->{curState}};
                    push @scanNowList,$e;
                }
                PRESENCE2_doEvtCheck($hash,$now);
            }

            if (scalar(@scanNowList) > 0){# only fork if something to scan

                PRESENCE2_Log $name, 4, "PRESENCE2_doDaemonUnBlocking:\n" . $name . "#" . join(",",@scanNowList);

                my $nonBlockingTimeout = AttrVal( $name, "nonblockingTimeOut", 60 );

                $hash->{helper}{RUNNING_PID} = BlockingCall("PRESENCE2_doDaemonUnBlocking"
                                                          , $name . "#" . join(",", @scanNowList)
                                                          , "PRESENCE2_daemonScanReply"
                                                          , $nonBlockingTimeout
                                                          , "PRESENCE2_daemonAbortedScan"
                                                          , $hash);
                $hash->{helper}{RUNNING_PID}->{loglevel} = GetVerbose($name);
            }
        }
        $hash->{helper}{cnt}{skip} = 0;
        readingsSingleUpdate($hash, "daemonSkipCnt", $hash->{helper}{cnt}{skip}, 1);

        my $maxScanTime = ReadingsVal($name, "daemonMaxScanTime", $daemonInterval);
        my $minScanTime = ReadingsVal($name, "daemonMinScanTime", $daemonInterval);
        $daemonInterval = $maxScanTime if(int(($maxScanTime + $minScanTime) / 2) > $daemonInterval);
    }
    InternalTimer($now + $daemonInterval, "PRESENCE2_daemonScanScheduler", $hash, 0) if (!defined $scanMeNow);
}

sub PRESENCE2_doDaemonUnBlocking($) {
    my ($name,$scanListStr) = split("#",shift);
    my $start = gettimeofday();
    my @scanList =  split(",",$scanListStr);

    my @ret = ();
    foreach my $e (@scanList){
      push @ret, PRESENCE2_doDaemonEntityScan($name, $e);
    }

    my $duration = int(gettimeofday() - $start);
    return join("<n>", ($name, $duration)) ."#". join("<n>", @ret);
}

sub PRESENCE2_daemonScanReply($) {

    my $subPara = shift;

    my ($caller, $reply)  = split("#"  , $subPara);
    my ($name, $duration) = split("<n>", $caller);
    my @result            = split("<n>", $reply);

    my $hash = $defs{$name};
    delete $hash->{helper}{RUNNING_PID};

    foreach my $res (@result){
      my ($eName, $eStmp) = split('\|',$res);
      my ($eSstate, $eTime) = split('\]', $eStmp);
      if ($eName) {
        readingsBeginUpdate($defs{$eName});
        PRESENCE2_ProcessState($defs{$eName}, $eSstate);
        readingsEndUpdate($defs{$eName}, 1);
      }
    }

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "state", "active");
    foreach (@result){
        my ($eName, $eStmp)   = split('\|', $_);
        my ($eSstate, $eTime) = split('\]', $eStmp);
        readingsBulkUpdate($hash, "pr_" .$eName, $eSstate) if $eName;
        readingsBulkUpdate($hash, "st_" .$eName, $eTime) if $eName;
    }
    readingsBulkUpdate($hash, 'daemonMaxScanTime', $duration) if ($duration > ReadingsVal($name, 'daemonMaxScanTime', 0));
    my $minTime = ReadingsVal($name, 'daemonMinScanTime', 0);
    readingsBulkUpdate($hash, 'daemonMinScanTime', $duration) if ($duration <= ($minTime == 0 ? $duration : $minTime));

    my %stateH = (  "present"  => "pres"
                   ,"disabled" => "disa"
                   ,"absent"   => "abst"
                   ,"error"    => "erro"
                  );

    my @valStates = keys %stateH;
    my %pgps;
    foreach my $grp (@{$hash->{helper}{prGroups}},"default","total"){
        $pgps{$grp}{$stateH{$_}} = 0 foreach(keys %stateH);
    }

    foreach my $e (PRESENCE2_getAllEntities()){
        foreach my $grp (split(",", AttrVal($e,"prGroup", "default")), "total"){
            my $state = ReadingsVal($e, "state", "absent");
            next if(!grep /^$state$/,@valStates );
            $pgps{$grp}{$stateH{$state}}++ ;
        }
    }

    foreach my $pg (keys %pgps){
        next if(!$pg);
        if(  $hash->{helper}{disp}{condense}){
            readingsBulkUpdate($hash, "pGrp_".$pg, "dis:$pgps{$pg}{disa} ab:$pgps{$pg}{abst} pres:$pgps{$pg}{pres}");
        }
        if(  $hash->{helper}{disp}{verbose}){
            readingsBulkUpdate($hash, "pGrp_${pg}_ab"  , "$pgps{$pg}{abst}");
            readingsBulkUpdate($hash, "pGrp_${pg}_pres", "$pgps{$pg}{pres}");
            readingsBulkUpdate($hash, "pGrp_${pg}_dis" , "$pgps{$pg}{disa}");
        }
    }
    readingsEndUpdate($hash, 1);
    PRESENCE2_Log $name, 4, "duration:$duration reply:\n         ".join("\n         ",@result);
}

sub PRESENCE2_daemonAbortedScan($) {
    my ($hash) = @_;

    my $instHash = ( ref($hash) eq "HASH" ) ? $hash : $defs{$hash};
    my $instName = ( ref($hash) eq "HASH" ) ? $hash->{NAME} : $hash;

    my $xline       = ( caller(0) )[2];

    my $xsubroutine = ( caller(1) )[3];
    my $sub         = ( split( ':', $xsubroutine ) )[2];
    $sub =~ s/PRESENCE2_//       if ( defined $sub );
    $sub ||= 'no-subroutine-specified';

    PRESENCE2_Log $instName, 3, "scan aborted: $xline | $sub";

    delete $defs{$instName}{helper}{RUNNING_PID};
    $defs{$instName}{helper}{cnt}{aboart} = defined $defs{$instName}{helper}{cnt}{aboart} ? $defs{$instName}{helper}{cnt}{aboart} + 1 : 1;
    readingsSingleUpdate($instHash, "daemonAboartCnt", $defs{$instName}{helper}{cnt}{aboart}, 1);
}

sub PRESENCE2_doDaemonEntityScan($$) {
    my ($dn, $NAME) = @_;
    my ($ADDRESS, $local, $count, $hash) = (InternalVal($NAME,"ADDRESS",""), 0, 1, $defs{$NAME});

    $SIG{CHLD} = 'IGNORE';

    my $ps;
    my $temp;
    my $result = "";
    my $startTime = time();

    if (!defined $hash->{helper}{os}{Cmd} || !$hash->{helper}{os}{Cmd}){
      return "$NAME|error]0.0";
    }

    my $cmd = $hash->{helper}{os}{Cmd};
       $cmd =~ s/\$ADDRESS/$ADDRESS/;
       $cmd =~ s/\$NAME/$NAME/;

    my $search = $hash->{helper}{os}{search};
       $search =~ s/\$ADDRESS/$ADDRESS/;
       $search =~ s/\$NAME/$NAME/;

    if ($hash->{MODE} =~ /sub/){
      $temp = eval($cmd);

    } elsif ($hash->{MODE} eq "function"){
      $temp = AnalyzeCommandChain(undef, $cmd);

    } else {
      PRESENCE2_Log $hash->{NAME}, 5, "calling - $cmd";
      if (defined $hash->{helper}{os}{bluetoothHciDevice}) {
        my $wait = 1;
        while($wait)
        {   # check if another hcitool process is running
            $ps = qx(ps ax | grep hcitool | grep -v grep);
            if(not $ps =~ /^\s*$/)
            {
                # sleep between 1 and 5 seconds and try again
                PRESENCE2_Log $NAME, 5, "another hcitool command is running, waiting ...";
                sleep(rand(4)+1);
            }
            else
            {
                $wait = 0;
            }
        }
      }
      $temp = qx($cmd);
    }

    if (defined $hash->{helper}{os}{bluetoothHciDevice}) {
      $result = $temp =~ /$search/gs ? "present":"absent";

    } elsif(! defined($temp) or $temp eq "") {

      $result = "error:Could not execute command: \"$cmd\"";
      $temp = "empty";

    } elsif($temp =~ m/Unknown command/) {
      $temp =~ s/, try help\.$//;
      $result = "error:$temp";

    } elsif($temp =~ m/subError/) {
      $temp =~ s/subError://gs;
      $temp =~ s/at \/.*\/73_PRESENCE2.pm line.*//gs;
      $result = "error:$temp \"$cmd\"";
      $temp = "empty";

    } else {
      $result = $temp =~ /$search/gs ? "present":"absent";
    }

    PRESENCE2_Log $NAME, 4, "result:$result\n########command>$cmd\n########reply  >$temp";
    my $endTime = sprintf( "%.2f", time()-$startTime);
    return "$NAME|$result]$endTime";
}

sub PRESENCE2_doDaemonCleanup(){
    my $name = PRESENCE2_getDaemonName();
    my $hash = $defs{$name};
    my @list = PRESENCE2_getAllEntities();
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, ".associatedWith", join(",",@list));
    readingsEndUpdate($hash, 0);
    readingsSingleUpdate($defs{$_},".associatedWith",$name,0) foreach (@list);
    @list = map{"pr_".$_} @list;

    foreach my $key (grep /^pr_/,keys%{$hash->{READINGS}}){
        delete $hash->{READINGS}{$key} if(!scalar(grep (/^$key$/,@list)));
    }
    foreach my $key (grep /^pGrp_/,keys%{$hash->{READINGS}}){
        my $grp = $key;
        $grp =~ s/^pGrp_//;
        $grp =~ s/_(ab|pres|dis)$//;
        if(   !scalar(grep/$grp/,@{$hash->{helper}{prGroups}},"default")
          || ($key =~ m/_(ab|pres|dis)$/ && !$hash->{helper}{disp}{verbose})
          || ($key !~ m/_(ab|pres|dis)$/ && !$hash->{helper}{disp}{condense})
           ){
            delete $hash->{READINGS}{$key};
        }
    }
}

sub PRESENCE2_doEvtSetup($){
    my $cmd = shift;
    my ($name,$evt) = split("#",$cmd);
    my $now = int(gettimeofday());
    my $dn = PRESENCE2_getDaemonName();
    my $dnh = $defs{$dn};
    my @eArr;

    if(!defined $name || $name eq "init" || $name eq ""){
        my %eH;
        $eH{$_} = 1 foreach (devspec2array("presentCycle=[0-9]+"));
        $eH{$_} = 1 foreach (map{(my $foo = $_) =~ s/^evt_//; $foo;} grep/^evt_/,keys %{$dnh->{READINGS}});
        @eArr = (keys %eH);
    }
    else{
        my (undef,$eNm) = split(" ",$evt);
        push @eArr,$eNm;
    }

    foreach my $e (@eArr){
        if(defined $attr{$e}{presentCycle} && $attr{$e}{presentCycle} =~ m/^\d*$/){
            $dnh->{helper}{evnt}{$e}{read}     = AttrVal($e,"presentReading","state");
            $dnh->{helper}{evnt}{$e}{cycle}    = $attr{$e}{presentCycle};
            $dnh->{helper}{evnt}{$e}{nextScan} = $now + $dnh->{helper}{evnt}{$e}{cycle};
            PRESENCE2_Log $dn, 3, "$dn - adding event track for $e cycle: $dnh->{helper}{evnt}{$e}{cycle} reading:$dnh->{helper}{evnt}{$e}{read}";
        }
        else{
            delete $dnh->{helper}{evnt}{$e};
            delete $dnh->{READINGS}{"evt_".$e};
            delete $defs{$e}{READINGS}{"presentState"};
            PRESENCE2_Log $dn, 3, "remove event track for $e";
       }
    }
}

sub PRESENCE2_doEvtCheck($$){
    my ($dnh,$now) = @_;
    my @ret;
    foreach my $e (keys%{$dnh->{helper}{evnt}}){
        next if ($dnh->{helper}{evnt}{$e}{nextScan} > $now);
        my $time = 0;
        if(ReadingsTimestamp($e,$dnh->{helper}{evnt}{$e}{read},"2000-01-01 01:01:01") =~ m/(....)-(..)-(..) (..):(..):(..)/){
            #$time = timelocal($sec,$min,$hour,$mday,$mon,$year);
            $dnh->{helper}{evnt}{$e}{nextScan} = int(timelocal($6,$5,$4,$3,$2-1,$1-1900)) + $dnh->{helper}{evnt}{$e}{cycle};
        }
        push @ret,"$e|".($dnh->{helper}{evnt}{$e}{nextScan} < $now
                           ? "absent"
                           : "present");
    }

    PRESENCE2_doEvtCheckReply(join("<n>",@ret));
    return join("<n>",@ret);
}

sub PRESENCE2_doEvtCheckReply($){
    my $states = shift;
    my @evts = split("<n>",$states);
    my $dnh = $defs{PRESENCE2_getDaemonName()};

    readingsBeginUpdate($dnh);
    foreach (@evts){
        my ($eName,$eSstate) = split('\|',$_);
        readingsBulkUpdate($dnh, "evt_".$eName, $eSstate);
    }
    readingsEndUpdate($dnh, 1);

    foreach (@evts){
        my ($eName,$eSstate) = split('\|',$_);
        readingsSingleUpdate($defs{$eName}, "presentState", $eSstate,1);
    }
}

# 'tcp' or 'icmp'
# "present":"absent"
sub PRESENCE2_net_ping($$$) {

  my ($dn, $ip, $pType) = @_;
  my $result = "unknown";

  eval {
         my $p = Net::Ping->new($pType, 2);

         if ($p->ping($ip)) {
           $result = "present";
         } else {
           $result = "absent";
         }
  };

  if ($@) {
    $result = "subError:" . $@;
    PRESENCE2_Log $dn, 3, "Net::Ping::" .$pType. ": $@";
  }

  return $result;
}

sub PRESENCE2_net_async_ping($$) {

  my ($dn, $ip) = @_;
  my $result = "unknown";

  eval {
         my $p = Net::Async::Ping->new(
               'icmp' => {
                           default_timeout => 2,
                           use_ping_socket => 1,
                         },
         );

         my $loop = IO::Async::Loop->new;

         my $future = $p->ping($loop, $ip);

         $future->on_done(sub {
                                $loop->stop();
                                $result = "present";
                              }
                         );

         $future->on_fail(sub {
                                $loop->stop();
                                $result = "absent";
                              }
                         );

         $loop->loop_once();
         $loop->run;

  };

  if ($@) {
    $result = "subError:" . $@;
    PRESENCE2_Log $dn, 3, "Net::Async::Ping: $@";
  }

  return $result;
}

1;

=pod
=item helper
=item summary    provides PRESENCE2 detection checks
=item summary_DE stellt eine Anwesenheitserkennung zur Verf&uuml;gung
=begin html

<a id="PRESENCE2"></a>
<h3>PRESENCE2</h3>
<div>
<ul>
The PRESENCE2 module offers several ways to check for the presence of devices such as mobile phones or tablets.<br>
  In addition, actions at the FHEM or system level can be executed and analyzed periodically.<br>
  Other FHEM entities can also be managed for periodic activity.
  <br><br>
  This module offers various operating modes to meet your requirements. These are:<br><br>
  <ul>
      <li><b>lan-ping</b> – Device check using the operating system's ping command.</li>
      <li><b>net-ping-tcp</b> – Device check using the Perl module Net::Ping.</li>
      <li><b>net-ping-icmp</b> – Device check using the Perl module Net::Ping.</li>
      <li><b>lan-ping-async</b> – Device check using the Perl modules IO::Async::Loop and Net::Async::Ping.</li>
      <li><b>netcat</b> – Device check using the netcat network utility.</li>
      <li><b>function</b> – Execution of a user-defined FHEM command.</li>
      <li><b>shellscript</b> – Execution of a user-defined operating system command.</li>
      <li><b>bluetooth</b> – Bluetooth device scan from the FHEM server.</li>
      <li><b>lan-bluetooth</b> – Device check via LAN by connecting to a presenced or collectord instance.</li>
  </ul>
  <br>
  <B>Daemon entity:</B> A daemon entity is automatically created if no PRESENCE2 entity definition exists.<br>
  The daemon schedules and executes ping and scan actions for all entities except LAN-Bluetooth. It is executed cyclically, as defined by the "IntervalNormal" attribute.<br>
  Since the daemon performs the scanning activities (except for LAN-Bluetooth), reports and detections cannot occur more frequently than the daemon cycle.<br>
  <br><br>

  <a id="PRESENCE2-define"></a>
  <b>Define</b>
  <ul>
    <br><b>Mode: lan-ping</b><br>
    <code>define &lt;name&gt; PRESENCE2 lan-ping &lt;IP-address&gt;</code><br>
    Searches for a network device using the operating system's ping command and reports its presence status.<br>
    <u>Example</u><br>
    <code>define iPhone PRESENCE2 lan-ping 192.168.179.21</code><br>

    <br><b>Mode: net-ping-tcp</b><br>
    <code>define &lt;name&gt; PRESENCE2 net-ping-tcp &lt;IP-address&gt;</code><br>
    Searches for a network device using the Perl module net::ping in 'tcp' mode (echo port) and reports its presence status.<br>
    <u>Example</u><br>
    <code>define iPhone PRESENCE2 net-ping-tcp 192.168.179.21</code><br>
  
    <br><b>Mode: net-ping-icmp</b><br>
    <code>define &lt;name&gt; PRESENCE2 net-ping-icmp &lt;IP-address&gt;</code><br>
    Searches for a network device using the Perl module net::ping in 'icmp' mode (requires root privileges) and reports its presence status.<br>
    <u>Example</u><br>
    <code>define iPhone PRESENCE2 net-ping-icmp 192.168.179.21</code><br>

    <br><b>Mode: net-ping-async</b><br>
    <code>define &lt;name&gt; PRESENCE2 net-ping-async &lt;IP-address&gt;</code><br>
    Searches for a network device using the Perl modules IO::Async::Loop and Net::Async::Ping in 'icmp' mode (does not require root privileges) and reports its presence status.<br>
    <u>Example</u><br>
    <code>define iPhone PRESENCE2 net-ping-async 192.168.179.21</code><br>

    <br><b>Mode: netcat</b><br>
    <code>define &lt;name&gt; PRESENCE2 netcat &lt;ip-address:port&gt;</code><br>
    <u>Example</u><br>
    <code>define Something PRESENCE2 netcat 192.168.179.21:22</code><br>

    <br><b>Mode: function</b><br>
    <code>define &lt;name&gt; PRESENCE2 function cmd:&lt;command&gt; scan:&lt;scanExpression&gt;</code><br>
    Executes the FHEM <i>command</i> and parses the reply for <i>scanExpression</i>.<br>
    <ul>
      <li><i>command</i> can be any FHEM expression such as<br>
      <code>
        get PsnceDaemon list normal<br>
        { ReadingsVal("PsnceDaemon", "state", "empty") }
      </code>
      </li>
      <li><i>scanExpression</i> is a string or regex to parse the reply<br>
      </li>
    </ul>
    <u>Example</u><br>
    <code>define iPhone PRESENCE2 function cmd:{ snmpCheck("10.0.1.1", "0x44d77429f35c") } scan:1</code><br>

    <br><b>Mode: shellscript</b><br>
    <code>define &lt;name&gt; PRESENCE2 shellscript cmd:&lt;command&gt; scan:&lt;scanExpression&gt; </code><br>
    Executes the OS <i>command</i> and parses the reply for <i>scanExpression</i>.<br>
    <u>Example</u><br>
    <code>define iPhone PRESENCE2 shellscript cmd:/opt/check_device.sh iPhone scan:1</code><br>

    <br><b>Mode: bluetooth</b><br>
    <code>define &lt;name&gt; PRESENCE2 bluetooth &lt;address&gt;</code><br>
    Scans for the MAC <i>address</i> on the FHEM server's BT interface.<br>
    <u>Example</u><br>
    <code>define iPhone PRESENCE2 bluetooth 0a:8d:4f:51:3c:8f</code><br>

    <br><b>Mode: lan-bluetooth</b><br>
    <code>define &lt;name&gt; PRESENCE2 lan-bluetooth cmd:&lt;address&gt; scan:&lt;ip-address&gt; </code><br>
    Checks for a bluetooth device with the help of presenced or collectord. They can be installed where-ever you like, however accessible via network.
    The given device will be checked for PRESENCE2 status.<br>

    The default port is 5111 (presenced). Alternatly you can use port 5222 (collectord)<br>
    <u>Example</u><br>
    <code>define iPhone PRESENCE2 lan-bluetooth 0a:4f:36:d8:f9:89 127.0.0.1:5222</code><br><br>

    <u>presenced</u><br>
    <ul>presenced is a perl network daemon, which provides PRESENCE2 checks of multiple bluetooth devices over network.
    It listens on TCP port 5111 for incoming connections from a FHEM PRESENCE2 instance or a running collectord.<br>

    Executes the OS <i>command</i> and parses the reply for <i>scanExpression</i>.<br>
    <u>Example</u><br>
    <code>define iPhone PRESENCE2 lan-bluetooth 0a:8d:4f:51:3c:8f</code><br>

<PRE>
Usage:
  presenced [-d] [-p &lt;port&gt;] [-P &lt;filename&gt;]
  presenced [-h | --help]

Options:
  -p, --port
     TCP Port which should be used (Default: 5111)
  -P, --pid-file
     PID file for storing the local process id (Default: /var/run/presenced.pid)
  -d, --daemon
     detach from terminal and run as background daemon
  -n, --no-timestamps
     do not output timestamps in log messages
  -v, --verbose
     Print detailed log output
  -h, --help
     Print detailed help screen
</PRE>

    It uses the hcitool command (provided by a <a href="http://www.bluez.org" target="_new">bluez</a> installation)
    to make a paging request to the given bluetooth address (like 01:B4:5E:AD:F6:D3). The devices must not be visible, but
    still activated to receive bluetooth requests.<br><br>

    If a device is present, this is send to FHEM, as well as the device name as reading.<br><br>

    The presenced is available as:<br><br>
    <ul>
    <li>direct perl script file: <a href="https://svn.fhem.de/trac/export/HEAD/trunk/fhem/contrib/PRESENCE/presenced" target="_new">presenced</a></li>
    <li>.deb package for Debian/Raspbian (noarch): <a href="https://svn.fhem.de/trac/export/HEAD/trunk/fhem/contrib/PRESENCE/deb/presenced-1.5.deb" target="_new">presenced-1.5.deb</a></li>
    </ul>
    </ul><br><br>
        <u>lepresenced</u><br>
    <ul>lepresenced is a Perl network daemon that provides presence checks of
    multiple bluetooth devices over network. In contrast to presenced,
    lepresenced covers <u>Bluetooth 4.0 (low energy) devices, i. e.
    Gigaset G-Tags, FitBit Charges.</u>
    lepresenced listens on TCP port 5333 for connections of a PRESENCE2 definition
    or collectord.<br>

    To detect the presence of a device, it uses the command <i>hcitool lescan</i> (package:
    <a href="http://www.bluez.org" target="_new">bluez</a>) to continuously listen to
    beacons of Bluetooth LE devices.
    <br><br>

    If a device is present, this is send to FHEM, as well as the device name as reading.<br><br>

    The lepresenced is available as:<br><br>
    <ul>
    <li>Perl script: <a href="https://svn.fhem.de/trac/export/HEAD/trunk/fhem/contrib/PRESENCE/lepresenced" target="_new">lepresenced</a></li>
    <li>.deb package (noarch): <a href="https://svn.fhem.de/trac/export/HEAD/trunk/fhem/contrib/PRESENCE/deb/lepresenced-0.93-1.deb" target="_new">lepresenced-0.93-1.deb</a></li>
    </ul>
    </ul><br><br>

    <u>collectord</u><br>
    <ul>
    The collectord is a perl network daemon, which handles connections to several presenced installations to search for multiple bluetooth devices over network.<br><br>

    It listens on TCP port 5222 for incoming connections from a FHEM PRESENCE2 instance.
<PRE>
Usage:
  collectord -c &lt;configfile&gt; [-d] [-p &lt;port&gt;] [-P &lt;pidfile&gt;]
  collectord [-h | --help]

Options:
  -c, --configfile &lt;configfile&gt;
     The config file which contains the room and timeout definitions
  -p, --port
     TCP Port which should be used (Default: 5222)
  -P, --pid-file
     PID file for storing the local process id (Default: /var/run/collectord.pid)
  -d, --daemon
     detach from terminal and run as background daemon
  -n, --no-timestamps
     do not output timestamps in log messages
  -v, --verbose
     Print detailed log output
  -l, --logfile &lt;logfile&gt;
     log to the given logfile
  -h, --help
     Print detailed help screen
</PRE>
    Before the collectord can be used, it needs a config file, where all different rooms, which have a presenced detector, will be listed. This config file looks like:
    <br>
<PRE>
    # room definition
    # ===============
    #
    [room-name]              # name of the room
    address=192.168.0.10     # ip-address or hostname
    port=5111                # tcp port which should be used (5111 is default)
    presence_timeout=120     # timeout in seconds for each check when devices are present
    absence_timeout=20       # timeout in seconds for each check when devices are absent

    [living room]
    address=192.168.0.11
    port=5111
    presence_timeout=180
    absence_timeout=20
</PRE>

    If a device is present in any of the configured rooms, this is send to FHEM, as well as the device name as reading and the room which has detected the device.<br><br>

    The collectord is available as:<br><br>
    <ul>
    <li>direct perl script file: <a href="https://svn.fhem.de/trac/export/HEAD/trunk/fhem/contrib/PRESENCE/collectord" target="_new">collectord</a></li>
    <li>.deb package for Debian (noarch): <a href="https://svn.fhem.de/trac/export/HEAD/trunk/fhem/contrib/PRESENCE/deb/collectord-1.8.1.deb" target="_new">collectord-1.8.1.deb</a></li>
    </ul>
    </ul>
  </ul>
  <br>

  <a id="PRESENCE2-set"></a>
  <b>Set</b>
  <ul>
     <a id="PRESENCE2-set-active"></a>
     <li>
         <dt><code>set &lt;name&gt; active</code></dt>
         Activates the device.<br>
     </li><br>

     <a id="PRESENCE2-set-inactive"></a>
     <li>
         <dt><code>set &lt;name&gt; inactive</code></dt>
         Deactivates the device until the next restart of FHEM.<br>
     </li><br>

     <a id="PRESENCE2-set-statusRequest"></a>
     <li>
         <dt><code>set &lt;name&gt; statusRequest</code></dt>
         Schedules an immediatly check.<br>
     </li><br>

    <a id="PRESENCE2-set-power"></a>
     <li>
        <dt><code>set &lt;name&gt; power</code></dt>
        Runs the powerCmd command specified by the powerCmd parameter (only if the "powerCmd" attribute is defined)
     </li><br>

     <a id="PRESENCE2-set-killChilds"></a>
     <li>
         <dt><code>set &lt;name&gt; killChilds</code></dt>
         Kills all childs.<br>
     </li><br>

     <a id="PRESENCE2-set-clearCounts"></a>
     <li>
         <b>For childs:</b><br>
         <dt><code>set &lt;name&gt; clearCounts</code></dt>
         Reset counter values.<br>
         <br>
         <b>For daemon:</b><br>
         <dt><code>set &lt;name&gt; clearCounts &lt;daemon|allEntities&gt;</code></dt>
         &lt;daemon&gt; - clear all counts from daemon.<br>
         &lt;allEntities&gt; - clear all counts from daemon and all PRESENCE2 entities.<br>
     </li><br>
  </ul>
  <br>

  <a id="PRESENCE2-get"></a>
  <b>Get</b>
  <ul>
     <a id="PRESENCE2-get-list"></a>
     <li>
         <dt><code>set &lt;name&gt; list &lt;normal|full&gt;</code></dt>
         &lt;normal&gt; - execute list command.<br>
         &lt;full&gt; - execute list command and include hidden entries.<br>
     </li><br>

     <a id="PRESENCE2-get-childInfo"></a>
     <li>
         <b>daemon only</b><br>
         <dt><code>set &lt;name&gt; childInfo &lt;PRESENCE2|all&gt;</code></dt>
         &lt;PRESENCE2&gt; - Show all running forked processes started by PRESENCE2.<br>
         &lt;all&gt; - Show all running forked processes.<br>
     </li><br>

     <a id="PRESENCE2-get-statusInfo"></a>
     <li>
         <b>daemon only</b><br>
         <dt><code>set &lt;name&gt; statusInfo &lt;definition|status&gt;</code></dt>
         &lt;definition&gt; - Return a table of the definition for all PRESENCE2 entities.<br>
         &lt;status&gt; - Return a table of the status for all PRESENCE2 entities.<br>
     </li><br>
  </ul>
  <br>

  <a id="PRESENCE2-attr"></a>
  <b>Attributes</b>
  <ul>
    <a id="PRESENCE2-attr-FhemLog3Std"></a>
    <li>
      <dt><code>attr &lt;name&gt; FhemLog3Std &lt0 | 1&gt;</code></dt>
      If set, the log information will be written in standard FHEM format.<br>
      If the output to a separate log file was activated by a verbose 5, this will be ended.<br>
      The separate log file and the associated FileLog device are deleted.<br>
      If the attribute is set to 0 or deleted and the device verbose is set to 5, all log data will be written to a separate log file.<br>
      Log file name: deviceName_debugLog.dlog<br>
      In the INTERNAL Reading DEBUGLOG there is a link &lt;DEBUG log can be viewed here&gt; for direct viewing of the log.<br>
    </li><br>

    <a id="PRESENCE2-attr-intervalPresent"></a>
    <li>
       <dt><code>attr &lt;name&gt; intervalPresent &lt;seconds&gt;</code></dt>
       Time in seconds to check status if the device is in state present. It is adjusted to the daemons cycle.<br>
       Not applicable for daemon entity<br>
    </li><br>

    <a id="PRESENCE2-attr-intervalNormal"></a>
    <li>
       <dt><code>attr &lt;name&gt; intervalNormal &lt;seconds&gt;</code></dt>
       Time in seconds to check status if the device is in state present. It is adjusted to the daemons cycle.<br>
       Not applicable for daemon entity<br>
    </li><br>

    <a id="PRESENCE2-attr-nonblockingTimeOut"></a>
    <li>
       <dt><code>attr &lt;name&gt; nonblockingTimeOut &lt;30..240&gt&gt;</code></dt>
       timeout for regularly checking presende. Default is 60 (seconds).
    </li><br>

    <a id="PRESENCE2-attr-bluetoothHciDevice"></a>
    <li>
       <dt><code>attr &lt;name&gt; bluetoothHciDevice &lt;hci[0..n]&gt;</code></dt>
       (Only applicable in local "bluetooth" mode and not applicable to Daemon device)<br>
       <br>
       Set a specific bluetooth HCI device to use for scanning. If you have multiple bluetooth modules connected,<br>
       you can select a specific one to use for scanning (e.g. hci0, hci1, ...).<br>
    </li><br>

    <a id="PRESENCE2-attr-hcitoolParam"></a>
    <li>
       <dt><code>attr &lt;name&gt; hcitoolParam &lt;name|info&gt;</code></dt>
       (Only applicable in local "bluetooth" mode and not applicable to Daemon device)<br>
       <br>
       Selection of which parameter the hcitool should use to recognize a connected bluetooth device<br>
       Default is &lt;name&gt;
    </li><br>

    <a id="PRESENCE2-attr-pingParam"></a>
    <li>
       <dt><code>attr &lt;name&gt; pingParam &lt;params&gt;</code></dt>
       (Only available if OS is not Solaris or Windows/CygWin)<br>
       <br>
       Parameters, other than the IP/Host, as available in the command reference for the operating system command 'ping'.<br>
       Default for Linux: -c 1 -w 1 <br>
       Supported Parameters:<br>
        -q                 quiet output<br>
        -c <count>         stop after <count> replies<br>
        -w <deadline>      reply wait <deadline> in seconds<br>
        -i <interval>      seconds between sending each packet<br>
    </li><br>

    <a id="PRESENCE2-attr-disable"></a>
    <li>
        <dt><code>attr &lt;name&gt; disable &lt;0|1&gt;</code></dt>
        If activated, any check is disabled and state is set to disabled.<br>
    </li><br>

    <a id="PRESENCE2-attr-prGroup"></a>
    <li>
        <dt><code>attr &lt;name&gt; prGroup &lt;static|dynamic|...&gt;</code></dt>
        By defining a group, several presence devices can be assigned to a group and monitored.<br>
        &lt;static&gt; predefined.<br>
        &lt;dynamic&gt; predefined.<br>
        You can define your own groups.<br>
    </li><br>

    <a id="PRESENCE2-attr-prGroupDisp"></a>
    <li>
        <dt><code>attr &lt;name&gt; prGroupDisp &lt;condense|verbose&gt;</code></dt>
        &lt;condense&gt; - Shows presence group information in condensed mode. [default]<br>
        &lt;verbose&gt; - Shows presence group information in verbose mode.<br>
    </li><br>

    <b>child-processes only</b>
    <a id="PRESENCE2-attr-thresholdAbsence"></a>
    <li>
        <dt><code>attr &lt;name&gt; thresholdAbsence &lt;seconds&gt;</code></dt>
    </li><br>

    <b>for readings that shall be monitored</b>
    <a id="PRESENCE2-attr-presentCycle"></a>
    <li>
        <dt><code>attr &lt;name&gt; presentCycle &lt;seconds&gt;</code></dt>
        This attribute is available in every device in FHEM. If set, the reading to be monitored will be from the
        Attribute <i>presentReading</i> or the default Reading <i>state</i> by the Presence2 daemon for updating
        checked. If no update takes place within the defined period of time, the reading "presentState" is displayed in the device.
        set to "send". In the Presence2 daemon device the reading <i>evt_monitoredDevice</i> is generated and set accordingly.<br>
    </li><br>

    <a id="PRESENCE2-attr-presentReading"></a>
    <li>
        <dt><code>attr &lt;name&gt; presentReading &lt;name of the reading&gt;</code></dt>
        This attribute is available in every device in FHEM. It defines the reading that <i>presentCycle</i> monitors
        becomes. If the attribute is not set, the reading <i>state</i> is monitored.<br>
    </li><br>

    <a id="PRESENCE2-attr-powerCmd"></a>
    <li>
      <dt><code>attr &lt;name&gt; powerCmd &lt;command line&gt;</code></dt>

      A FHEM command capable of switching the device.<br><br>

      When the power command is executed (set command: power), the following placeholders are replaced by their corresponding values:
      <ul>
        <li><code>$NAME</code> - Name of the PRESENCE2 definition</li>
        <li><code>$ADDRESS</code> - The monitored address of the PRESENCE2 definition, as specified in the define command.</li>
        <li><code>$ARGUMENT</code> - The argument passed to the "power" set command (e.g., "on" or "off").</li>
      </ul>
      <br>
      Example FHEM commands:<br>
      <ul>
        <li><code>set PowerSwitch_1 on</code></li>
        <li><code>set PowerSwitch_1 $ARGUMENT</code></li>
        <li><code>"/opt/power_on.sh $ADDRESS"</code></li>
        <li><code>{powerOn("$ADDRESS", "username", "password")}</code></li>
      </ul>
    </li><br>

  </ul>
  <br>

  <a id="PRESENCE2-events"></a>
  <b>Readings/events:</b><br><br>
  <ul>
    <u>General</u><br>
    <ul>
    <li><b>state</b>: (absent|present|disabled) - The state of the device, check errors or "disabled" when the <a href=#PRESENCE2-attr-disable>disable</a> attribute is enabled.</li>
    <li><b>presence</b>: (absent|maybe absent|present|maybe present) - The presence state of the device. The value "maybe absent" only occurs if <a href=#PRESENCE2-attr-thresholdAbsence>thresholdAbsence</a> is activated.</li>
    <li><b>appearCnt</b>: count of entering availale</li>
    <li><b>lastAppear</b>: timestamp of last appearence</li>
    <li><b>lastDisappear</b>: timestamp of last disappearence</li>
    <li><b>thresHldCnt</b>: current thresdold counter. 0 = threshold not active</li>
    </ul><br>
    <u>Daemon specific readings/events:</u><br>
    <ul>
    <li><b>daemonMaxScanTime</b>: maximum time the scan job used. Should be less than intervalNormal to avoid skip.</li>
    <li><b>daemonSkipCnt</b>: counter of skipping the daemon job due to collision.</li>
    <li><b>pGrp_&lt;group&gt;</b>: counter summary of entites assigned to &lt;group&gt;</li>
    <li><b>pGrp_&lt;group&gt;_ab</b>: verbose counter summary of entites assigned to &lt;group&gt; : absent entities</li>
    <li><b>pGrp_&lt;group&gt;_dis</b>: verbose counter summary of entites assigned to &lt;group&gt; : disabled entities</li>
    <li><b>pGrp_&lt;group&gt;_pres</b>: verbose counter summary of entites assigned to &lt;group&gt; : present entities</li>
    <li><b>pr_&lt;entity&gt;</b>: status of the PRESENT supervision - see presentCycle</li>
    <li><b>st_&lt;entity&gt;</b>: scan time of the PRESENT supervision - see presentCycle</li>
    <li><b>evt_&lt;entiy&gt;</b>: status of the event supervision - see presentCycle</li>
    </ul><br>

    <u>Bluetooth specific readings/events:</u><br>
    <ul>
    <li><b>device_name</b>: $name - The name of the Bluetooth device in case it's present</li>
    </ul><br><br>
  </ul>
</ul>
</div>

=end html

=begin html_DE

<a id="PRESENCE2"></a>
<h3>PRESENCE2</h3>
<ul>
  Das PRESENCE2-Modul bietet mehrere Möglichkeiten um die Anwesenheit von Geräten wie Mobiltelefonen oder Tablets zu überprüfen.<br>
  Darüber hinaus können FHEM- oder Systemebene-Aktionen regelmäßig ausgeführt und analysiert werden<br>
  Weitere FHEM-Einheiten können für die regelmäßige Tätigkeit betreut werden.
  <br><br>
  Dieses Modul bietet verschiedene Betriebsmodi, um Euren Anforderungen gerecht zu werden. Dies sind:<br><br>
  <ul>
      <li><b>lan-ping</b> – Geräte-Prüfung mit Hilfe Betriebssystem ping.</li>
      <li><b>net-ping-tcp</b> – Geräte-Prüfung mit Hilfe Perl-Modul net::ping.</li>
      <li><b>net-ping-icmp</b> – Geräte-Prüfung mit Hilfe von Perl-Modul net::ping.</li>
      <li><b>lan-ping-async</b> – Geräte-Prüfung mit Hilfe von Perl-Module IO::Async::Loop und Net::Async::Ping.</li>
      <li><b>netcat</b> – Geräte-Prüfung mit Hilfe von Netzwerk-netcat.</li>
      <li><b>function</b> – Ausführen eines benutzerdefinierten FHEM-Befehls.</li>
      <li><b>shellscript</b> – Ausführen eines benutzerdefinierten Betriebssystembefehls.</li>
      <li><b>bluetooth</b> – Bluetooth-Gerätescan vom FHEM-Server .</li>
      <li><b>lan-bluetooth</b> – Geräte-Prüfung über LAN-Netzwerk durch Verbindung mit einer presenced- oder collectord-Instanz.</li>
  </ul>
  <br>
  <B>Daemon-Entität:</B> Eine Daemon-Entität wird automatisch erstellt, wenn keine Definition einer PRESENCE2-Entität vorliegt.<br>
  Der Daemon plant und führt die Ping- und Scan-Aktionen für alle Einheiten außer LAN-Bluetooth aus. Es wird zyklisch ausgeführt, wie durch das Attribut "IntervallNormal" definiert.<br>
  Da der Daemon die Scan-Aktivitäten ausführt (außer LAN-Bluetooth), können Berichte und Erkennungen nicht schneller als der Daemon-Zyklus sein.<br>
  <br><br>

  <a id="PRESENCE2-define"></a>
  <b>Define</b>
  <ul>
    <br><b>Modus: lan-ping</b><br>
    <code>define &lt;name&gt; PRESENCE2 lan-ping &lt;IP-Adresse&gt;</code><br>
    Sucht über den Betriebssystem Befehl ping nach einem Netzwerkgerät und meldet seinen Anwesenheits-Status.<br>
    <u>Beispiel</u><br>
    <code>define iPhone PRESENCE2 lan-ping 192.168.179.21</code><br>

    <br><b>Modus: net-ping-tcp</b><br>
    <code>define &lt;name&gt; PRESENCE2 net-ping-tcp &lt;IP-Adresse&gt;</code><br>
    Sucht über das Perl-Modul net::ping im Modus 'tcp' - Echo-Port - nach einem Netzwerkgerät und meldet seinen Anwesenheits-Status.<br>
    <u>Beispiel</u><br>
    <code>define iPhone PRESENCE2 net-ping-tcp 192.168.179.21</code><br>
  
    <br><b>Modus: net-ping-icmp</b><br>
    <code>define &lt;name&gt; PRESENCE2 net-ping-icmp &lt;IP-Adresse&gt;</code><br>
    Sucht über das Perl-Modul net::ping im Modus 'icmp' - es werden root Rechte benötigt - nach einem Netzwerkgerät und meldet seinen Anwesenheits-Status.<br>
    <u>Beispiel</u><br>
    <code>define iPhone PRESENCE2 net-ping-icmp 192.168.179.21</code><br>

    <br><b>Modus: net-ping-async</b><br>
    <code>define &lt;name&gt; PRESENCE2 net-ping-async &lt;IP-Adresse&gt;</code><br>
    Sucht über die Perl-Module IO::Async::Loop und Net::Async::Ping im Modus 'icmp' - es werden keine root Rechte benötigt - nach einem Netzwerkgerät und meldet seinen Anwesenheits-Status.<br>
    <u>Beispiel</u><br>
    <code>define iPhone PRESENCE2 net-ping-async 192.168.179.21</code><br>

    <br><b>Modus: netcat</b><br>
    <code>define &lt;name&gt; PRESENCE2 netcat &lt;IP-Adresse:Port&gt;</code><br>
    <u>Beispiel</u><br>
    <code>define Something PRESENCE2 netcat 192.168.179.21:22</code><br>

    <br><b>Modus: function</b><br>
    <code>define &lt;name&gt; PRESENCE2 function cmd:&lt;Befehl&gt; scan:&lt;scanExpression&gt;</code><br>
    Führt den FHEM-<i>Befehl</i> aus und analysiert die Antwort für <i>scanExpression</i>.<br>
    <ul>
      <li><i>Befehl</i> kann ein beliebiger FHEM-Ausdruck sein wie z. B.<br>
      <code>
        get PsnceDaemon-Liste list normal<br>
        { ReadingsVal("PsnceDaemon", "state", "empty") }
      </code>
      </li>
      <li><i>scanExpression</i> ist eine Zeichenfolge oder ein regulärer Ausdruck zum Parsen der Antwort<br>
      </li>
    </ul>
    <u>Beispiel</u><br>
    <code>define iPhone PRESENCE2 function cmd:{ snmpCheck("10.0.1.1", "0x44d77429f35c") } scan:1</code><br>

    <br><b>Modus: shellscript</b><br>
    <code>define &lt;name&gt; PRESENCE2 shellscript cmd:&lt;Script&gt; scan:&lt;scanExpression&gt; </code><br>
    Führt das Betriebssystem-<i>Script</i> aus und analysiert die Antwort für <i>scanExpression</i>.<br>
    <u>Beispiel</u><br>
    <code>define iPhone PRESENCE2 shellscript cmd:/opt/check_device.sh iPhone scan:1</code><br>

    <br><b>Modus: bluetooth</b><br>
    <code>define &lt;name&gt; PRESENCE2 bluetooth &lt;Adresse&gt;</code><br>
    Sucht nach der MAC-<i>Adresse</i> auf der BT-Schnittstelle des FHEM-Servers.<br>
    <u>Beispiel</u><br>
    <code>define iPhone PRESENCE2 bluetooth 0a:8d:4f:51:3c:8f</code><br>

    <br><b>Modus: lan-bluetooth</b><br>
    <code>define &lt;name&gt; PRESENCE2 lan-bluetooth cmd:&lt;address&gt; scannen:&lt;IP-Adresse&gt; </code><br>
    Sucht mit Hilfe von presenced oder collectord nach einem Bluetooth-Gerät. Sie können überall dort installiert werden, wo Sie möchten, und sind dennoch über das Netzwerk erreichbar.
    Das angegebene Gerät wird auf den PRESENCE2-Status überprüft.<br>

    Der Standardport ist 5111 (presenced). Alternativ können Sie Port 5222 (Collector)<br> verwenden
    <u>Beispiel</u><br>
    <code>define iPhone PRESENCE2 lan-bluetooth 0a:4f:36:d8:f9:89 127.0.0.1:5222</code><br><br>

    <u>presenced</u><br>
    <ul>presenced ist ein Perl-Netzwerk-Daemon, der PRESENCE2-Prüfungen mehrerer Bluetooth-Geräte über das Netzwerk bereitstellt.
    Es überwacht den TCP-Port 5111 auf eingehende Verbindungen von einer FHEM PRESENCE2-Instanz oder einem laufenden collectord.<br>

    Führt den Betriebssystem-<i>Befehl</i> aus und analysiert die Antwort für <i>scanExpression</i>.<br>
    <u>Beispiel</u><br>
    <code>define iPhone PRESENCE2 lan-bluetooth 0a:8d:4f:51:3c:8f</code><br>

<PRE>
Verwendung:
  presenced [-d] [-p &lt;Port&gt;] [-P &lt;Dateiname&gt;]
  presenced [-h | --help]

Optionen:
  -p, --port
     TCP-Port, der verwendet werden soll (Standard: 5111)
  -P, --pid-file
     PID-Datei zum Speichern der lokalen Prozess-ID (Standard: /var/run/presenced.pid)
  -d, --daemon
     Vom Terminal trennen und als Hintergrund-Daemon ausführen
  -n, --no-timestamps
     Zeitstempel in Protokollmeldungen nicht ausgeben
  -v, --verbose
     Detaillierte Protokollausgabe
  -h, --help
     Detaillierte Hilfe anzeigen
</PRE>

    Es verwendet den Befehl hcitool (bereitgestellt durch eine <a href="http://www.bluez.org" target="_new">bluez</a>-Installation).
    um eine Paging-Anfrage an die angegebene Bluetooth-Adresse zu stellen (z. B. 01:B4:5E:AD:F6:D3). Die Geräte dürfen aber nicht sichtbar sein
    weiterhin aktiviert, um Bluetooth-Anfragen zu empfangen.<br><br>

    Wenn ein Gerät vorhanden ist, wird dieses an FHEM gesendet, zusammen mit dem Gerätenamen als Lesegerät.<br><br>

    Das presenced ist verfügbar als:<br><br>
    <ul>
    <li>direkte Perl-Skriptdatei: <a href="https://svn.fhem.de/trac/export/HEAD/trunk/fhem/contrib/PRESENCE/presenced" target="_new">presenced</a> </li>
    <li>.deb-Paket für Debian/Raspbian (noarch): <a href="https://svn.fhem.de/trac/export/HEAD/trunk/fhem/contrib/PRESENCE/deb/presenced-1.5.deb" target="_new">presenced-1.5.deb</a></li>
    </ul>
    </ul><br><br>
    <u>lepresenced</u><br>
    <ul>lepresenced ist ein Perl-Netzwerk-Daemon, der PRESENCE2-Prüfungen von bereitstellt
    Mehrere Bluetooth-Geräte über das Netzwerk. Im Gegensatz zu presenced,
    lepresenced deckt <u>Bluetooth 4.0-Geräte (Low Energy) ab, d. e.
    Gigaset G-Tags, FitBit-Gebühren.</u>
    lepresenced lauscht am TCP-Port 5333 auf Verbindungen einer PRESENCE2-Definition
    oder collectord.<br>

    Um die Anwesenheit eines Geräts zu erkennen, verwendet es den Befehl <i>hcitool lescan</i> (Paket:
    <a href="http://www.bluez.org" target="_new">bluez</a>) zum kontinuierlichen Anhören
    Beacons von Bluetooth LE-Geräten.
    <br><br>

    Wenn ein Gerät vorhanden ist, wird dieses an FHEM gesendet, zusammen mit dem Gerätenamen als Lesegerät.<br><br>

    Das lepresenced ist verfügbar als:<br><br>
    <ul>
    <li>Perl-Skript: <a href="https://svn.fhem.de/trac/export/HEAD/trunk/fhem/contrib/PRESENCE/lepresenced" target="_new">lepresenced</a></ li>
    <li>.deb-Paket (noarch): <a href="https://svn.fhem.de/trac/export/HEAD/trunk/fhem/contrib/PRESENCE/deb/lepresenced-0.93-1.deb" target="_new">lepresenced-0.93-1.deb</a></li>
    </ul>
    </ul><br><br>

    <u>collectord</u><br>
    <ul>
    Der collectord ist ein Perl-Netzwerk-Daemon, der Verbindungen zu mehreren presenced-Installationen verwaltet, um über das Netzwerk nach mehreren Bluetooth-Geräten zu suchen.<br><br>

    Es überwacht den TCP-Port 5222 auf eingehende Verbindungen von einer FHEM PRESENCE2-Instanz.
<PRE>
Verwendung:
  collectord -c &lt;configfile&gt; [-d] [-p &lt;Port&gt;] [-P &lt;pidfile&gt;]
  collectord [-h | --help]

Optionen:
  -c, --configfile &lt;configfile&gt;
     Die Konfigurationsdatei, die die Raum- und Timeout-Definitionen enthält
  -p, --port
     TCP-Port, der verwendet werden soll (Standard: 5222)
  -P, --pid-file
     PID-Datei zum Speichern der lokalen Prozess-ID (Standard: /var/run/collector.pid)
  -d, --daemon
     Vom Terminal trennen und als Hintergrund-Daemon ausführen
  -n, --no-timestamps
     Zeitstempel in Protokollmeldungen nicht ausgeben
  -v, --verbose
     Detaillierte Protokollausgabe
  -l, --logfile &lt;logfile&gt;
     logt in die angegebene Protokolldatei
  -h, --help
     Detaillierte Hilfe anzeigen
</PRE>
    Bevor der collectord verwendet werden kann, benötigt er eine Konfigurationsdatei, in der alle verschiedenen Räume aufgelistet werden, die über einen presenced-Melder verfügen. Diese Konfigurationsdatei sieht so aus:
    <br>
<PRE>
    # room definition
    # ===============
    #
    [room-name]              # name of the room
    address=192.168.0.10     # ip-address or hostname
    port=5111                # tcp port which should be used (5111 is default)
    presence_timeout=120     # timeout in seconds for each check when devices are present
    absence_timeout=20       # timeout in seconds for each check when devices are absent

    [living room]
    address=192.168.0.11
    port=5111
    presence_timeout=180
    absence_timeout=20
</PRE>

    Wenn in einem der konfigurierten Räume ein Gerät vorhanden ist, wird dies an FHEM gesendet, zusammen mit dem Gerätenamen als Messwert und dem Raum, in dem das Gerät erkannt wurde.<br><br>

    Der Collector ist verfügbar als:<br><br>
    <ul>
    <li>direkte Perl-Skriptdatei: <a href="https://svn.fhem.de/trac/export/HEAD/trunk/fhem/contrib/PRESENCE/collectord" target="_new">collectord</a> </li>
    <li>.deb-Paket für Debian (noarch): <a href="https://svn.fhem.de/trac/export/HEAD/trunk/fhem/contrib/PRESENCE/deb/collectord-1.8.1.deb" target="_new">collectord-1.8.1.deb</a></li>
    </ul>
    </ul>
  </ul>
  <br>

  <a id="PRESENCE2-set"></a>
  <b>Set</b>
  <ul>
     <a id="PRESENCE2-set-active"></a>
     <li>
         <dt><code>set &lt;name&gt; active</code></dt>
         Aktiviert das Device.<br>
     </li><br>

     <a id="PRESENCE2-set-inactive"></a>
     <li>
         <dt><code>set &lt;name&gt; inactive</code></dt>
         Deaktiviert das Device bis zum nächsten Neustart von FHEM.<br>
     </li><br>

     <a id="PRESENCE2-set-statusRequest"></a>
     <li>
         <dt><code>set &lt;name&gt; statusRequest</code></dt>
         Holt den aktuellen Presence Status des Geräts.<br>
     </li><br>

     <a id="PRESENCE2-set-power"></a>
     <li>
        <dt><code>set &lt;name&gt; power</code></dt>
        Startet den powerCmd-Befehl welche durch den Parameter powerCmd angegeben ist (Nur wenn das Attribut "powerCmd" definiert ist)
     </li><br>

     <a id="PRESENCE2-set-killChilds"></a>
     <li>
         <dt><code>set &lt;name&gt; killChilds</code></dt>
         Entfernt alle Kind-Prozesse.<br>
     </li><br>

     <a id="PRESENCE2-set-clearCounts"></a>
     <li>
         <b>Kind-Prozesse:</b><br>
         <dt><code>set &lt;name&gt; clearCounts</code></dt>
         Zurücksetzen des Zählers.<br>
         <br>
         <b>Für Daemon:</b><br>
         <dt><code>set &lt;name&gt; clearCounts &lt;daemon|allEntities&gt;</code></dt>
         &lt;daemon&gt; - Lösche alle Zähler von Daemon.<br>
         &lt;allEntities&gt; - Löscht alle Zähler vom Daemon und allen PRESENCE2-Entitäten.<br>
     </li><br>
  </ul>
  <br>

  <a id="PRESENCE2-get"></a>
  <b>Get</b>
  <ul>
     <a id="PRESENCE2-get-list"></a>
     <li>
         <dt><code>set &lt;name&gt; list &lt;normal|full&gt;</code></dt>
         &lt;normal&gt; - List ausführen.<br>
         &lt;full&gt; - List ausführen und versteckte Einträge einschließen.<br>
     </li><br>

     <a id="PRESENCE2-get-childInfo"></a>
     <li>
         <b>Nur Daemon</b><br>
         <dt><code>set &lt;name&gt; childInfo &lt;PRESENCE2|all&gt;</code></dt>
         &lt;PRESENCE2&gt; – Zeigt alle laufenden Prozesse an, die von PRESENCE2 gestartet wurden.<br>
         &lt;all&gt; - Alle laufenden Prozesse werden angezeigt.<br>
     </li><br>

     <a id="PRESENCE2-get-statusInfo"></a>
     <li>
         <b>Nur Daemon</b><br>
         <dt><code>set &lt;name&gt; statusInfo &lt;definition|status&gt;</code></dt>
         &lt;definition&gt; - Gibt eine Tabelle der Definition für alle PRESENCE2-Entitäten zurück.<br>
         &lt;status&gt; - Gibt eine Tabelle mit dem Status für alle PRESENCE2-Entitäten zurück.<br>
     </li><br>
  </ul>
  <br>

  <a id="PRESENCE2-attr"></a>
  <b>Attributes</b>
  <ul>
    <a id="PRESENCE2-attr-FhemLog3Std"></a>
    <li>
      <dt><code>attr &lt;name&gt; FhemLog3Std &lt0 | 1&gt;</code></dt>
      Wenn gesetzt, werden die Log Informationen im Standard FHEM Format geschrieben.<br>
      Sofern durch ein verbose 5 die Ausgabe in eine seperate Log-Datei aktiviert wurde, wird diese beendet.<br>
      Die seperate Log-Datei und das zugehörige FileLog Device werden gelöscht.<br>
      Wird das Attribut auf 0 gesetzt oder gelöscht und ist das Device verbose auf 5 gesetzt, so werden alle Log-Daten in eine eigene Log-Datei geschrieben.<br>
      Name der Log-Datei:deviceName_debugLog.dlog<br>
      Im INTERNAL Reading DEBUGLOG wird ein Link &lt;DEBUG Log kann hier eingesehen werden&gt; zur direkten Ansicht des Logs angezeigt.<br>
    </li><br>

    <a id="PRESENCE2-attr-intervalPresent"></a>
    <li>
       <dt><code>attr &lt;name&gt; intervalPresent &lt;Sekunden&gt;</code></dt>
       Zeit in Sekunden, um den Status zu überprüfen, ob sich das Gerät im Status "Present" befindet. Es ist an den Daemonenzyklus angepasst.<br>
       Gilt nicht für Daemon-Entitäten<br>
    </li><br>

    <a id="PRESENCE2-attr-intervalNormal"></a>
    <li>
       <dt><code>attr &lt;name&gt; intervalNormal &lt;Sekunden&gt;</code></dt>
       Zeit in Sekunden, um den Status zu überprüfen, ob sich das Gerät im Status "Present" befindet. Es ist an den Daemonenzyklus angepasst.<br>
       Gilt nicht für Daemon-Entitäten<br>
    </li><br>

    <a id="PRESENCE2-attr-nonblockingTimeOut"></a>
    <li>
       <dt><code>attr &lt;name&gt; nonblockingTimeOut &lt;30..240&gt;</code></dt>
       Timeout f&uuml;r das regelm&auml;&szlig;ige prüfen auf Anwesenheit. Standard ist 60 (Sekunden).
    </li><br>

    <a id="PRESENCE2-attr-bluetoothHciDevice"></a>
    <li>
       <dt><code>attr  &lt;name&gt; bluetoothHciDevice &lt;hci[0..n]&gt;</code></dt>
       (Nur im lokalen Modus "bluetooth" und nicht für Daemon Device anwendbar)<br>
       <br>
       Sofern man mehrere Bluetooth-Empf&auml;nger verf&uuml;gbar hat, kann man mit diesem Attribut ein bestimmten Empf&auml;nger ausw&auml;hlen,<br>
       welcher zur Erkennung verwendet werden soll (bspw. hci0, hci1, ...).<br>
    </li><br>

    <a id="PRESENCE2-attr-hcitoolParam"></a>
    <li>
       <dt><code>attr &lt;name&gt; hcitoolParam &lt;name|info&gt;</code></dt>
       (Nur im lokalen Modus "bluetooth" und nicht für Daemon Device anwendbar)<br>
       <br>
       Auswahl über welchen Paramter das hcitool ein verbundenes Bluetooth Device erkennen soll.<br>
       Vorgabe ist &lt;name&gt;
    </li><br>

    <a id="PRESENCE2-attr-pingParam"></a>
    <li>
       <dt><code>attr &lt;name&gt; pingParam &lt;params&gt;</code></dt>
       (Nur verfügbar, wenn OS nicht Solaris oder Windows/CygWin)<br>
       <br>
       Parameter, außer der IP/Host, wie sie in der Befehlsreferenz für das Betriebssystem Kommando 'ping' verfügbar sind.<br>
       Default für Linux: -c 1 -w 1 <br>
       Supported Parameters:<br>
        -q                 quiet output<br>
        -c <count>         stop after <count> replies<br>
        -w <deadline>      reply wait <deadline> in seconds<br>
        -i <interval>      seconds between sending each packet<br>
    </li><br>

    <a id="PRESENCE2-attr-disable"></a>
    <li>
        <dt><code>attr &lt;name&gt; disable &lt;0|1&gt;</code></dt>
        Wenn aktiviert, ist jede Prüfung deaktiviert und der Status wird auf deaktiviert gesetzt.<br>
    </li><br>

    <a id="PRESENCE2-attr-prGroup"></a>
    <li>
        <dt><code>attr &lt;name&gt; prGroup &lt;static|dynamic|...&gt;</code></dt>
        Durch die Definition einer Gruppe können mehrere Präsenzgeräte einer Gruppe zugeordnet und überwacht werden.<br>
        &lt;static&gt; vordefiniert.<br>
        &lt;dynamic&gt; vordefiniert.<br>
        Sie können Ihre eigenen Gruppen definieren.<br>
    </li><br>

    <a id="PRESENCE2-attr-prGroupDisp"></a>
    <li>
        <dt><code>attr &lt;name&gt; prGroupDisp &lt;condense|verbose&gt;</code></dt>
        &lt;condense&gt; - Zeigt Informationen zur Anwesenheitsgruppe im komprimierten Modus an. [Standard]<br>
        &lt;verbose&gt; – Zeigt Informationen zur Anwesenheitsgruppe im ausführlichen Modus an.<br>
    </li><br>

    <b>Kind-Prozesse</b>
    <a id="PRESENCE2-attr-thresholdAbsence"></a>
    <li>
        <dt><code>attr &lt;name&gt; thresholdAbsence &lt;Sekunden&gt;</code></dt>
    </li><br>

    <b>für Readings, die überwacht werden sollen</b>
    <a id="PRESENCE2-attr-presentCycle"></a>
    <li>
        <dt><code>attr &lt;name&gt; presentCycle &lt;Sekunden&gt;</code></dt>
        Dieses Attribut steht in jedem Device in FHEM zur Verfügung. Wenn gesetzt, wird das zu überwachende Reading aus dem
        Attribut <i>presentReading</i> oder dem default Reading <i>state</i> durch den Presence2 Daemon auf Aktualisierung
        überprüft. Findet innerhalb der definierten Zeitspanne keine Aktuallisierung statt, wird im Device das Reading "presentState"
        auf "absend" gesetzt. Im Presence2 Daemon Device wird das Reading <i>evt_monitoredDevice</i> generiert und entsprechend gesetzt.<br>
    </li><br>

    <a id="PRESENCE2-attr-presentReading"></a>
    <li>
        <dt><code>attr &lt;name&gt; presentReading &lt;name des Readings&gt;</code></dt>
        Dieses Attribut steht in jedem Device in FHEM zur Verfügung. Es definiert das Reading, dass von <i>presentCycle</i> überwacht
        wird. Wird das Attribut nicht gesetzt, wird das Reading <i>state</i> überwacht.<br>
    </li><br>

    <a id="PRESENCE2-attr-powerCmd"></a>
    <li>
      <dt><code>attr &lt;name&gt; powerCmd &ltcommand line&gt;</code></dt>

      Ein FHEM-Befehl, welcher das Gerät schalten kann.<br><br>

      Wenn der power-Befehl ausgeführt wird (set-Befehl: power) werden folgende Platzhalter durch ihre entsprechenden Werte ersetzt:
      <ul>
        <li><code>$NAME</code> - Name der PRESENCE2 Definition</li>
        <li><code>$ADDRESS</code> - Die überwachte Addresse der PRESENCE2 Definition, wie sie im define-Befehl angegeben wurde.</li>
        <li><code>$ARGUMENT</code> - Das Argument, was dem Set-Befehl "power" übergeben wurde. (z. B. "on" oder "off")</li>
      </ul>
      <br>
      Beispielhafte FHEM-Befehle:<br>
      <ul>
        <li><code>set PowerSwitch_1 on</code></li>
        <li><code>set PowerSwitch_1 $ARGUMENT</code></li>
        <li><code>"/opt/power_on.sh $ADDRESS"</code></li>
        <li><code>{powerOn("$ADDRESS", "username", "password")}</code></li>
      </ul>
    </li><br>

  </ul>
  <br>

  <a id="PRESENCE2-events"></a>
  <b>Readings/events:</b><br><br>
  <ul>
    <u>Allgemein</u><br>
    <ul>
    <li><b>Status</b>: (absent|present|disabled) – Der Status des Geräts, Prüffehler oder "deaktiviert", wenn das Attribut <a href=#PRESENCE2-attr-disable>disable</a> aktiviert ist.</li>
    <li><b>presence</b>: (absent|maybe absent|present|maybe present) – Der Anwesenheits-Status des Geräts. Der Wert "maybe absent" tritt nur auf, wenn <a href=#PRESENCE2-attr-thresholdAbsence>thresholdAbsence</a> aktiviert ist.</li>
    <li><b>appearCnt</b>: Anzahl der verfügbaren Eingaben</li>
    <li><b>lastAppear</b>: Zeitstempel des letzten Erscheinens</li>
    <li><b>lastDisappear</b>: Zeitstempel des letzten Verschwindens</li>
    <li><b>thresHldCnt</b>: aktueller Schwellenwertzähler. 0 = Schwellenwert nicht aktiv</li>
    </ul><br>
    <u>Daemon-spezifische Messwerte/Ereignisse:</u><br>
    <ul>
    <li><b>daemonMaxScanTime</b>: maximale Zeit, die der Scanauftrag verwendet hat. Sollte kleiner als "intervalNormal" sein, um ein Überspringen zu vermeiden.</li>
    <li><b>daemonSkipCnt</b>: Zähler für das Überspringen des Daemon-Jobs aufgrund einer Kollision.</li>
    <li><b>pGrp_&lt;group&gt;</b>: Übersicht der der &lt;group&gt;</li> zugewiesenen Entitäten</li>
    <li><b>pGrp_&lt;group&gt;_ab</b>: Übersicht der Entitäten, die &lt;group&gt; zugewiesen sind. : fehlende Entitäten</li>
    <li><b>pGrp_&lt;group&gt;_dis</b>: Übersicht der Entitäten, die &lt;group&gt; zugewiesen sind. : deaktivierte Entitäten</li>
    <li><b>pGrp_&lt;group&gt;_pres</b>: Übersicht der Entitäten, die &lt;group&gt; zugewiesen sind. : gegenwärtige Entitäten</li>
    <li><b>pr_&lt;entity&gt;</b>: Status der PRESENT-Überwachung – siehe presentCycle</li>
    <li><b>st_&lt;entity&gt;</b>: Scan-Dauer der PRESENT-Überwachung – siehe presentCycle</li>
    <li><b>evt_&lt;entiy&gt;</b>: Status der Ereignisüberwachung – siehe presentCycle</li>
    </ul><br>

    <u>Bluetooth-spezifische Messwerte/Ereignisse:</u><br>
    <ul>
    <li><b>Gerätename</b>: $name – Der Name des Bluetooth-Geräts, falls vorhanden</li>
    </ul><br><br>
  </ul>
</ul>

=end html_DE

=cut
