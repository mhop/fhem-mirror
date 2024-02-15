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

sub PRESENCE2_doDaemonEntityScan($$);
sub PRESENCE2_doDaemonCleanup();

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
    $hash->{AttrList} = "do_not_notify:0,1 ".
                        "disable:0,1 ".
                        "ignore:1,0 dummy:1,0 ".
                        "thresholdAbsence ".
                        "intervalNormal intervalPresent ".
                        "prGroup:multiple,static,dynamic ".
                        "prGroupDisp:multiple,condense,verbose ".
                        $readingFnAttributes;

    $hash->{AttrRenameMap} = { "bluetooth_hci_device" => "bluetoothHciDevice"
                             };
    PRESENCE2_updateConfig();
}
sub PRESENCE2_Rename($$$) {
    my ($name, $oldName) = @_;
    my $dN = PRESENCE2_getDaemonName();
    return if(!defined $dN);
    PRESENCE2_doDaemonCleanup();
}
sub PRESENCE2_Define($$) {
    my ($hash, $def) = @_;
    my @a = split("[ \t]+", $def);
    my $username =  getlogin || getpwuid($<) || "[unknown]";
    my $name = $hash->{NAME};

    $hash->{NOTIFYDEV} = "global";

    if(defined($a[2]) and defined($a[3])) {
        $attr{$name}{intervalNormal}   = (defined($a[4]) and $a[4] =~ /^\d+$/ and $a[4] > 0) ? $a[4] : 1;
        $attr{$name}{intervalPresent}  = (defined($a[5]) and $a[5] =~ /^\d+$/ and $a[5] > 0) ? $a[5] : 1;
        $hash->{MODE}                = $a[2];
        $hash->{ADDRESS}             = $a[3];
        $hash->{helper}{maybe}       = 0;
        $hash->{helper}{cnt}{th}     = 0;
        $hash->{helper}{cnt}{maybe}  = 0;
        $hash->{helper}{cnt}{state}  = 0;
        $hash->{helper}{cnt}{exec}   = 0;
        $hash->{helper}{nextScan}    = 0;
        $hash->{helper}{interval}{present} = 1;
        $hash->{helper}{interval}{absent}  = 1;
        $hash->{helper}{interval}{init}    = 30;
        $hash->{helper}{curState}          = "init";
        $hash->{helper}{DISABLED}          = 0;
        $hash->{helper}{disp}{condense}    = 1;
        $hash->{helper}{disp}{verbose}     = 0;

        if   ($a[2] eq "lan-ping") {
#            if(-X "/usr/bin/ctlmgr_ctl" and not $username eq "root") {
#                my $msg = "FHEM is not running under root (currently $username) This check can only performed with root access";
#                Log 2, "PRESENCE2 ($name) - ".$msg;
#                return $msg;
#            }
            $hash->{helper}{os}{Cmd} = ($^O =~ m/(Win|cygwin)/) ? "ping -n 1 -4 $hash->{ADDRESS}"
                                      :($^O =~ m/solaris/)      ? "ping $hash->{ADDRESS} 4"
                                      :                           "ping -c 1 -w 1 $hash->{ADDRESS} 2>&1"
                                      ;
            $hash->{helper}{os}{search} = $^O =~ m/solaris/? 'is alive'
                                         :                   '(ttl|TTL)=\d+'
                                         ;

        }
        elsif($a[2] eq "lan-bluetooth") {
#            unless($a[3] =~ /^\s*([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\s*$/){
#                my $msg = "given address is not a bluetooth hardware address";
#                Log 2, "PRESENCE2 ($name) - ".$msg;
#                return $msg
#            }
            DevIo_CloseDev($hash);# {DevIo_CloseDev($dev{prBtTest })}

            $attr{$name}{intervalNormal}   = 30;
            $attr{$name}{intervalPresent}  = 30;
            my ($dev,$port) = split(":",$a[4].":5222");
            return "$dev not a valid IP address" if ($dev !~ m/^\s*([0-9]{1,3}\.){3}[0-9]{1,3}\s*$/);
            $hash->{DeviceName} = "$dev:$port";
        }
        elsif($a[2] eq "bluetooth") {
#            if(-X "/usr/bin/ctlmgr_ctl" and not $username eq "root") {
#                my $msg = "FHEM is not running under root (currently $username) This check can only performed with root access";
#                Log 2, "PRESENCE2 ($name) - ".$msg;
#                return $msg;
#            }

            unless($a[3] =~ /^\s*([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\s*$/)
            {
                my $msg = "given address is not a bluetooth hardware address";
                Log 2, "PRESENCE2 ($name) - ".$msg;
                return $msg
            }

            $hash->{helper}{os}{Cmd}    = "hcitool -i hci0 name $hash->{ADDRESS}";
            $hash->{helper}{os}{search} = '[A-Za-z0-9]+';
        }
        elsif($a[2] =~ /(shellscript|function)/) {
            if($def =~ /[ \t]+cmd:(.*?)[ \t]+scan:(.*)[ \t]*$/s) {
                $hash->{helper}{os}{Cmd} = $1;
                $hash->{helper}{os}{search} = $2;

                delete $hash->{helper}{ADDRESS};
                delete $hash->{ADDRESS};

                if($hash->{helper}{os}{Cmd} =~ /\|/) {
                    my $msg = "The command contains a pipe ( | ) symbol, which is not allowed.";
                    Log 2, "PRESENCE2 ($name) - ".$msg;
                    return $msg;
                }
            }
            return "define $name failed. Please enter command and parse string" if(  !defined $hash->{helper}{os}{Cmd}    || $hash->{helper}{os}{Cmd}    eq ""
                                                                                  || !defined $hash->{helper}{os}{search} || $hash->{helper}{os}{search} eq ""
                                                                                  );
        }
        elsif($a[2] eq "daemon") {
            return "only one daemon allowed" if(PRESENCE2_getDaemonName() ne $name);
            delete $attr{$name}{intervalPresent};
            delete $attr{$name}{thresholdAbsence};
            $hash->{helper}{interval}{absent}  = 30;
            $hash->{helper}{interval}{present} = 30;
            
        }
        else {
            my $msg = "unknown mode \"".$a[2]."\" in define statement: Please use lan-ping, daemon, shellscript, function,bluetooth,lan-bluetooth";
            Log 2, "PRESENCE2 ($name) - ".$msg;
            return $msg
        }
    }
    else {
        my $msg = "wrong syntax for define statement: define <name> PRESENCE2 <mode> <device-address> ";
        Log 2, "PRESENCE2 ($name) - $msg";
        return $msg;
    }
    

    delete($hash->{helper}{cachednr});

    readingsSingleUpdate($hash,"model",$hash->{MODE},0);
    PRESENCE2_updateConfig();
    return undef;
}
sub PRESENCE2_Undef($$) {
    my ($hash, $arg) = @_;
    
    if ($hash->{MODE} eq "daemon" && PRESENCE2_getAllEntites()){
        return "deletion of daemon not possible unless objects still present";
    }
    BlockingKill($hash->{helper}{RUNNING_PID}) if(defined($hash->{helper}{RUNNING_PID}));

    RemoveInternalTimer($hash);
    DevIo_CloseDev($hash);
}
sub PRESENCE2_updateConfig(){
    # this routine is called after the last define of a restart
    # this gives FHEM sufficient time to fill in attributes
    # it will also be called after each manual definition
    # Purpose is to parse attributes and read config
    if (!$init_done){
      RemoveInternalTimer("PRESENCE2_updateConfig");
      InternalTimer(2,"PRESENCE2_updateConfig", "PRESENCE2_updateConfig", 0);
      return;
    }
    {# ensure only one daemon
        my @daemons = devspec2array("TYPE=PRESENCE2:FILTER=MODE=daemon");
        my $daemonName = shift @daemons;# leave the first alive
        CommandDelete(undef,$_)foreach (@daemons);
        
        if (!defined $daemonName){         # daemon not available
            CommandDefine(undef,'PsnceDaemon PRESENCE2 daemon daemon');
        }
        my $dN = PRESENCE2_getDaemonName();
        PRESENCE2_doDaemonCleanup();
        RemoveInternalTimer(undef,"PRESENCE2_daemonScanScheduler");
        InternalTimer(gettimeofday() + $attr{$dN}{intervalNormal}, "PRESENCE2_daemonScanScheduler", $defs{$dN}, 0);
    }
    
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

sub PRESENCE2_Notify($$) {
    my ($hash,$dev) = @_;
    return undef if(!defined $hash || !defined $hash->{NAME} || !defined $hash->{MODE} || $hash->{MODE} ne "daemon" 
                 || !defined $dev  || !defined $dev->{NAME}  ||                           $dev->{NAME}  ne "global" 
                 );

    my $events = deviceEvents($dev,0);
    my $name = $hash->{NAME};

    if (grep /^(ATTR|DELETEATTR).*(presentCycle|presentReading)/,@{$events}){
        PRESENCE2_doEvtSetup($name."#".$_) foreach(@{$events});
    }

}

sub PRESENCE2_Set($@) {
    my ($hash, @a) = @_;
    my $name = $hash->{NAME};

    return "No Argument given" if(!defined($a[1]));
    my ($cmd) = ($a[1]);
    

    my $powerCmd = AttrVal($name, "powerCmd", undef);

    if   ($cmd eq "statusRequest"){
        if($hash->{MODE} =~ m/(lan-ping|shellscript|function|bluetooth)/) {
            Log3 $name, 5, "PRESENCE2 ($name) - starting local scan";
            my $daemon = PRESENCE2_getDaemonName();
            return PRESENCE2_daemonScanScheduler($defs{$daemon}, $name);
        }
        elsif ($hash->{MODE} =~ m/(lan-bluetooth)/){
            if(exists($hash->{FD})){
                PRESENCE2_lanBtWrite($hash, "now");
            }
            else{
                return "PRESENCE2 Definition \"$name\" is not connected to ".$hash->{DeviceName};
            }
        }
    }
    elsif($cmd eq "clearCounts"){
        
        $hash->{helper}{cnt}{$_} = 0 foreach (keys %{$hash->{helper}{cnt}});
        my @clearEnt = ($name);
        push @clearEnt,PRESENCE2_getBlockingEntites() if (defined $a[2] && $a[2] eq "allEntites");
        foreach (@clearEnt){
            my $cHash = $defs{$_};
            readingsBeginUpdate($cHash);
            foreach( (grep /Cnt$/,keys%{$cHash->{READINGS}})
                    ,"daemonMaxScanTime"
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
    else{
        return "Unknown argument $cmd, choose one of"
                    .($hash->{MODE} eq "daemon" ? "" : " statusRequest:noArg")
                    ." clearCounts:".($hash->{MODE} eq "daemon" ? "daemon,allEntites": "noArg")
                    ." killChilds:noArg"
                    ;
    }

}
sub PRESENCE2_Get($@) {
    my ($hash, @a) = @_;
    my $name = $hash->{NAME};

    return "No Argument given" if(!defined($a[1]));
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
                                ,"PRESENCE2"
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
                                ,ReadingsVal($e,"PRESENCE2","--")
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

sub PRESENCE2_Attr(@) {
    my @a = @_;
    my $hash = $defs{$a[1]};
    my $name = $hash->{NAME};

    if   ($a[0] eq "set") {
        if ($a[2] =~ m/^(disable|ignore|dummy)$/ ) {
            if (($a[2] eq "disable" && $a[3] eq "0" && AttrVal($name,"ignore" ,0) == 0 && AttrVal($name,"dummy",0)  == 0 )
            ||  ($a[2] eq "ignore"  && $a[3] eq "0" && AttrVal($name,"disable",0) == 0 && AttrVal($name,"dummy",0)  == 0 )
            ||  ($a[2] eq "dummy"   && $a[3] eq "0" && AttrVal($name,"disable",0) == 0 && AttrVal($name,"ignore",0) == 0 )
               ){#enable
                RemoveInternalTimer($hash);
                $hash->{helper}{DISABLED} = 0;
                readingsSingleUpdate($hash, "state", "disabled",1);
                if ($hash->{MODE} eq "lan-bluetooth"){
                    if(defined($hash->{FD})){
                        PRESENCE2_lanBtDoInit($hash) ;
                    }
                    else{
                        DevIo_OpenDev($hash, 0, "PRESENCE2_lanBtDoInit");
                    }
                }
            }
            else {#disable

                readingsSingleUpdate($hash, "state", "disabled",0);    
                $hash->{helper}{DISABLED} = 1;
                PRESENCE2_lanBtWrite($hash, "stop");
            }
        }
        elsif($a[2] eq "thresholdAbsence") {
            return $a[2]." must be a valid integer number" if($a[3] !~ /^\d+$/);
            return $a[2]." not used by daemon"             if($hash->{MODE} eq "daemon");
        }
        elsif($a[2] =~ m/^interval(Normal|Present)$/) {
            return $a[2]." not a positive number" if( $a[3] !~ /^\d+$/ or $a[3] < 0);
            $hash->{helper}{nextScan} = gettimeofday();
            if ($hash->{MODE} eq "daemon"){
                $hash->{helper}{nextScan} += $a[3];
                return $a[2]." not allowed for daemon entites" if($a[2] eq "intervalPresent");
                RemoveInternalTimer(undef,"PRESENCE2_daemonScanScheduler");
                InternalTimer($hash->{helper}{nextScan}, "PRESENCE2_daemonScanScheduler", $hash, 0);
            }
            if ($a[2] eq "intervalPresent"){
                $hash->{helper}{interval}{present} = $a[3];  
            }
            else{
                $hash->{helper}{interval}{absent}  = $a[3];
                $hash->{helper}{interval}{present} = AttrVal($name,"intervalPresent",$a[3]);
            }
        }
    }
    elsif($a[0] eq "del") {
        if ($a[2] =~ m/^(disable|ignore|dummy)$/ ) {
            if (($a[2] eq "disable" && AttrVal($name,"ignore" ,0) == 0 && AttrVal($name,"dummy" ,0) == 0 )
            ||  ($a[2] eq "ignore"  && AttrVal($name,"disable",0) == 0 && AttrVal($name,"dummy" ,0) == 0 )
            ||  ($a[2] eq "dummy"   && AttrVal($name,"disable",0) == 0 && AttrVal($name,"ignore",0) == 0 )
               ){#enable
                RemoveInternalTimer($hash);
                $hash->{helper}{DISABLED} = 0;
                readingsSingleUpdate($hash, "state", "disabled",1);
                if ($hash->{MODE} eq "lan-bluetooth"){
                    if(defined($hash->{FD})){
                        PRESENCE2_lanBtDoInit($hash) ;
                    }
                    else{
                        DevIo_OpenDev($hash, 0, "PRESENCE2_lanBtDoInit");
                    }
                }
            }
            else { #disable
                readingsSingleUpdate($hash, "state", "disabled",0);    
                $hash->{helper}{DISABLED} = 1;
                PRESENCE2_lanBtWrite($hash, "stop");
            }
        }
        elsif($a[2] eq "intervalPresent"){
            $hash->{helper}{interval}{present} = $hash->{helper}{interval}{absent};  
        }
        elsif($a[2] eq "intervalNormal"){
            $hash->{helper}{interval}{absent}  = $hash->{MODE} eq "lan-bluetooth" ? 30 : 1;
            $hash->{helper}{interval}{present} = AttrVal($name,"intervalPresent",$hash->{helper}{interval}{absent});
        }
    }

    if($a[2] =~ m/^interval(Normal|Present)$/){
        PRESENCE2_lanBtUpdtTiming($hash) ;
    }
    elsif($a[2] eq "prGroupDisp"){
        if   ($a[0] eq "set" || $a[3] != m/(condense|verbose)/){
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
            $pgH{$_} = 1 foreach(grep/../,split(",",$a[3]));
        }
        foreach my $e (grep !/^$name$/,devspec2array("TYPE=PRESENCE2")){
            if (defined $attr{$e}{prGroup} && $attr{$e}{prGroup}){
                $pgH{$_} = 1 foreach(grep/../,split(",",$attr{$e}{prGroup}));
            }
        }
        my @pGroups = keys %pgH;
        my $pgs1 = join(",",@pGroups);
        my $pgs = " prGroup:multiple".($pgs1 ? ",".$pgs1." " : " ");
        $modules{PRESENCE2}{AttrList} =~ s/ prGroup.*? /$pgs/;
        my $dn = PRESENCE2_getDaemonName();
        $defs{$dn}{helper}{prGroups} = \@pGroups if (defined $dn && $dn ne "");
    }
    return undef;
}

sub PRESENCE2_setNotfiyDev($) {############## todo
    my ($hash) = @_;

    notifyRegexpChanged($hash,"(global|".$hash->{EVENT_PRESENT}."|".$hash->{EVENT_ABSENT}.")");
}

sub PRESENCE2_getBlockingEntites() {
    return devspec2array("TYPE=PRESENCE2:FILTER=MODE!=(daemon|lan-bluetooth)");
}
sub PRESENCE2_getAllEntites() {
    return devspec2array("TYPE=PRESENCE2:FILTER=MODE!=(daemon)");
}
sub PRESENCE2_getDaemonName() {
    my @a = devspec2array("TYPE=PRESENCE2:FILTER=MODE=daemon");
    return defined $a[0]? $a[0] : undef;
}

sub PRESENCE2_lanBtWrite($$){
    my ($hash,$cmd) = @_;
    if (defined $hash->{FD}){
        Log3 $hash->{NAME}, 5 , "PRESENCE2 ($hash->{NAME}) - write : $cmd";
        DevIo_SimpleWrite($hash, $cmd."\n", 2);
    }
    else{
        Log3 $hash->{NAME}, 5 , "PRESENCE2 ($hash->{NAME}) - write ignored - no FD: $cmd ";
    }
}
sub PRESENCE2_lanBtDoInit($){############## todo
    my ($hash) = @_;

    Log3 $hash->{NAME}, 5, "PRESENCE2 ($hash->{NAME}) - do init";
    if(!$hash->{helper}{DISABLED}){
        readingsSingleUpdate($hash, "state", "active",0);
        PRESENCE2_lanBtUpdtTiming($hash);
    }
    else{
        readingsSingleUpdate($hash, "state", "disabled",0);
    }
}
sub PRESENCE2_lanBtRead($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $buf = DevIo_SimpleRead($hash);
    return "" if(!defined($buf));

    chomp $buf;

    readingsBeginUpdate($hash);

    for my $line (split /^/, $buf){
        Log3 $name, 5, "PRESENCE2 ($name) - received data: $line";

        if($line =~ /^(absence|absent|present)(;*)(.*)/ && !$hash->{helper}{DISABLED}){
            my ($state,undef,$data) = ($1,$2,$3);
            Log3 $name, 4 , "PRESENCE2 ($name) - status info:$state";
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
            Log3 $name, 3, "PRESENCE2 ($name) - collectord lost connection to room $1";
        }
        elsif($line =~ /socket_reconnected;(?:room='?)?(.+?)'?$/){
            Log3 $name , 3, "PRESENCE2 ($name) - collectord reconnected to room $1";
        }
        elsif($line =~ /error;(?:room='?)?(.+?)'?$/){
            Log3 $name, 3, "PRESENCE2 ($name) - room $1 cannot execute hcitool to check device";
        }
        elsif($line =~ /error$/){
            Log3 $name, 3, "PRESENCE2 ($name) - PRESENCE2d cannot execute hcitool to check device ";
        }
    }
    readingsEndUpdate($hash, 1);
}
sub PRESENCE2_lanBtUpdtTiming($) {
    my ($hash) = @_;
    if($hash->{MODE} eq "lan-bluetooth"){
        PRESENCE2_lanBtWrite($hash, $hash->{ADDRESS}
                                  ."|".$hash->{helper}{interval}{$hash->{helper}{curState}});
    }
}
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

sub PRESENCE2_ProcessState($$) {
    my ($hash, $state) = @_;
    my $name = $hash->{NAME};

    if ($state !~ m/(absent|present)/)
    {
        readingsBulkUpdate($hash, "state", $state);
        return;
    }

    my $thresHld  = ReadingsVal($name,"state","") eq "present" ? AttrVal($name,"thresholdAbsence", 1) : 1;
    $hash->{helper}{cnt}{exec}++;
    if (++$hash->{helper}{cnt}{th} >= $thresHld)
    {
        $hash->{helper}{cnt}{th} = 0;
        if ($hash->{helper}{curState} ne $state){
            Log3 $name, 4, "PRESENCE2 ($name) - chang from $hash->{helper}{curState} to $state";
            $hash->{helper}{timestamp}{$state} = FmtDateTime(gettimeofday());
            readingsBulkUpdate($hash, "last".($state eq "present"?"Appear":"Disappear")   , $hash->{helper}{timestamp}{$state});
            readingsBulkUpdate($hash, "appearCnt", ++$hash->{helper}{cnt}{state}) if ($state eq "present");
            $hash->{helper}{curState} = $state;
            PRESENCE2_lanBtUpdtTiming($hash);
        }
        readingsBulkUpdate($hash, "state"      , $state);
        readingsBulkUpdate($hash, "thresHldCnt", 0     ) if($hash->{helper}{maybe});
        $hash->{helper}{maybe} = 0;
    }
    else
    {
        Log3 $name, 4, "PRESENCE2 ($name) - device is $state after $hash->{helper}{cnt}{th} check. "
                   .($thresHld - $hash->{helper}{cnt}{th})." attempts left before going absent";
                   
        readingsBulkUpdate($hash, "maybeCnt"   , ++$hash->{helper}{cnt}{maybe}) if(!$hash->{helper}{maybe});
        readingsBulkUpdate($hash, "thresHldCnt", $hash->{helper}{cnt}{th});
        $hash->{helper}{maybe} = 1;
    }

    readingsBulkUpdate($hash, "PRESENCE2", ($hash->{helper}{maybe}?"maybe ":"").$state);

}
sub PRESENCE2_daemonScanScheduler($;$) {
    my ($hash,$scanMeNow) = @_; # $scanMeNow: force a scan immediately for a single device
    my $name = $hash->{NAME};
    my $daemonInterval = AttrVal($name,"intervalNormal",30);
    my $now = gettimeofday();
    
    if (defined $hash->{helper}{RUNNING_PID}){
        Log3 $name, 3, "PRESENCE2 ($name) - skip scan due to running job";
        $hash->{helper}{cnt}{skip} = defined $hash->{helper}{cnt}{skip} ? $hash->{helper}{cnt}{skip} : 1;
        readingsSingleUpdate($hash,"daemonSkipCnt",$hash->{helper}{cnt}{skip},1);
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

                Log3 $name, 3, "PRESENCE2_doDaemonUnBlocking:\n" . $name."#".join(",",@scanNowList);

                $hash->{helper}{RUNNING_PID} = BlockingCall("PRESENCE2_doDaemonUnBlocking"
                                                          , $name."#".join(",",@scanNowList)
                                                          , "PRESENCE2_daemonScanReply"
                                                          , 60
                                                          , "PRESENCE2_daemonAbortedScan"
                                                          , $hash);
            }
        }
    }
    InternalTimer($now + $daemonInterval, "PRESENCE2_daemonScanScheduler", $hash, 0) if (!defined $scanMeNow);
}

sub PRESENCE2_doDaemonUnBlocking($) {
    my ($name,$scanListStr) = split("#",shift);
    my $start = gettimeofday();
    my @scanList =  split(",",$scanListStr);

    my @ret = ();
    foreach my $e (@scanList){
        push @ret,PRESENCE2_doDaemonEntityScan($name,$e);
    }

    my $duration = int(gettimeofday() - $start);
    return join("<n>",($name,$duration))."#".join("<n>",@ret);
}

sub PRESENCE2_daemonScanReply($) {

    my $subPara = shift;

    # Log3 == PsnceDaemon<n>56#Daniel_Anwesend|absent<n>Edith_Anwesend|present<n>Joerg_Anwesend|present<n>Martin_Anwesend|absent<n>WG_TV_AN|absent

    my ($caller,$reply)  = split("#"  , $subPara);
    my ($name,$duration) = split("<n>", $caller);
    my @result           = split("<n>", $reply);

    my $hash = $defs{$name};
    delete $hash->{helper}{RUNNING_PID};

    foreach my $res (@result){
        my ($eName,$eSstate) = split('\|',$res);
        readingsBeginUpdate($defs{$eName});
        PRESENCE2_ProcessState($defs{$eName}, $eSstate);
        readingsEndUpdate($defs{$eName}, 1);
    }

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "state", "active");
    foreach (@result){
        my ($eName,$eSstate) = split('\|',$_);
        readingsBulkUpdate($hash, "pr_".$eName, $eSstate);
    }
    readingsBulkUpdate($hash, 'daemonMaxScanTime', $duration)if ($duration > ReadingsVal($name,'daemonMaxScanTime',0));
    
    my %stateH = (  "present"  => "pres"
                   ,"disabled" => "disa"
                   ,"absent"   => "abst"
                   ,"error"    => "erro"
                  );
    my @valStates = keys %stateH;
    my %pgps;
    foreach my $grp (@{$hash->{helper}{prGroups}},"default","_total"){
        $pgps{$grp}{$stateH{$_}} = 0 foreach(keys %stateH);
    }
    
    foreach my $e (PRESENCE2_getAllEntites()){
        foreach my $grp (split(",",AttrVal($e,"prGroup","default")),"_total"){
            my $state = ReadingsVal($e,"state","absent");
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
    Log3 $name, 5, "PRESENCE2 ($name) - , duration:$duration reply:\n         ".join("\n         ",@result);
}

sub PRESENCE2_daemonAbortedScan($) {
    my ($hash) = @_;

    my $instHash = ( ref($hash) eq "HASH" ) ? $hash : $defs{$hash};
    my $instName = ( ref($hash) eq "HASH" ) ? $hash->{NAME} : $hash;

    Log3 $instName, 2, "PRESENCE2 ($instName) - scan aborted";
    delete $defs{$instName}{helper}{RUNNING_PID};
    $defs{$instName}{helper}{cnt}{aboart} = defined $defs{$instName}{helper}{cnt}{aboart} ? $defs{$instName}{helper}{cnt}{aboart} + 1 : 1;
    readingsSingleUpdate($instHash, "daemonAboartCnt", $defs{$instName}{helper}{cnt}{aboart}, 1);
}

sub PRESENCE2_doDaemonEntityScan($$) {
    my ($dn,$NAME) = @_;
    my ($ADDRESS, $local, $count,$hash) = (InternalVal($NAME,"ADDRESS",""),0,1,$defs{$NAME});
    $SIG{CHLD} = 'IGNORE';
    
    my $temp;
    my $cmd = $hash->{helper}{os}{Cmd};
    
    if (!defined $hash->{helper}{os}{Cmd} || !$hash->{helper}{os}{Cmd}){
        return "$NAME|error";
    }
    $cmd =~ s/\$ADDRESS/$ADDRESS/;
    $cmd =~ s/\$NAME/$NAME/;
    if ($hash->{MODE} eq "function"){$temp = AnalyzeCommandChain(undef, $cmd);}
    else                            {$temp = qx($cmd);}

    my $result = "";
    my $search = $hash->{helper}{os}{search};
    $search =~ s/\$ADDRESS/$ADDRESS/;
    $search =~ s/\$NAME/$NAME/;
    if(! defined($temp) or  $temp eq ""){
        $result = "error|Could not execute command: \"$cmd\"";
        $temp = "empty";
    }
    else{
        chomp $temp;
        $result  = $temp =~ /$search/ ? "present":"absent";
    }
    Log3 $NAME, 5, "PRESENCE2 ($NAME) - result:$result\n########command>$cmd\n########reply  >$temp";
    return "$NAME|$result";
}
sub PRESENCE2_doDaemonCleanup(){
    my $name = PRESENCE2_getDaemonName();
    my $hash = $defs{$name};
    my @list = PRESENCE2_getAllEntites();
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
            Log3 $dn, 3, "PRESENCE2 ($dn) - adding event track for $e cycle: $dnh->{helper}{evnt}{$e}{cycle} reading:$dnh->{helper}{evnt}{$e}{read}";
        }
        else{
            delete $dnh->{helper}{evnt}{$e};
            delete $dnh->{READINGS}{"evt_".$e};
            delete $defs{$e}{READINGS}{"presentState"};
            Log3 $dn, 3, "PRESENCE2 ($name) - remove event track for $e";
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

1;

=pod
=item helper
=item summary    provides PRESENCE2 detection checks
=item summary_DE stellt eine Anwesenheitserkennung zur Verf&uuml;gung
=begin html

<a name="PRESENCE2"></a>
<h3>PRESENCE2</h3>
<ul>
  The PRESENCE2 module provides several possibilities to check the PRESENCE2 devices such as mobile phones or tablets.<br>
  Furthermore FHEM or system level actions can be executed and parsed periodicaly<br>
  Additional FHEM entites can be superviced for regular activity. 
  <br><br>
  This module provides several operational modes to serve your needs. These are:<br><br>
  <ul>
      <li><b>lan-ping</b> - device PRESENCE2 check utilizing network ping.</li>
      <li><b>function</b> - executing user defined FHEM command.</li>
      <li><b>shellscript</b> - executing user defined OS command.</li>
      <li><b>bluetooth</b> - bluetooth device scan from FHEM server .</li>
      <li><b>lan-bluetooth</b> - device PRESENCE2 check via LAN network by connecting to a PRESENCE2d or collectord instance.</li>
  </ul>
  <br>
  <B>Daemon entity: </B> A daemon entity is auto-created if not definition of a PRESENCE2 entity. <br>
  The daemon schedules and executes the ping and scan actions for all entites except lan-bluetooth. It cyclic executes as defined by attr intervalNormal. <br>
  Since the daemon executes the scan activities (except lan-bluetooth) any report and detection cannot be faster than the deamon cycle.<br>
  <br><br>
  <a name="PRESENCE2_define"></a>
  <b>Define</b><br><br>
  <ul><b>Mode: lan-ping</b><br>
    <code>define &lt;name&gt; PRESENCE2 lan-ping &lt;ip-address&gt;</code><br>
    Checks for a network device via PING requests and reports its PRESENCE2 state.<br>
    <u>Example</u><br>
    <code>define iPhone PRESENCE2 lan-ping 192.168.179.21</code><br>

    <br><b>Mode: function</b><br>
    <code>define &lt;name&gt; PRESENCE2 function cmd:&lt;command&gt; scan:&lt;scanExpression&gt;</code><br>
    Executes the FHEM <i>command</i> and parses the reply for <i>scanExpression</i>.<br>
    <ul>
      <li><i>command</i> can be any FHEM expression such as <br>
      <code>get PsnceDaemon list normal <br>
      {ReadingsVal("PsnceDaemon","state","empty")} <br>
      </code>
      </li>
      <li><i>scanExpression</i> is a string or regex to parse the reply<br>
      </li>
    </ul>
    <u>Example</u><br>
    <code>define iPhone PRESENCE2 function cmd:{snmpCheck("10.0.1.1","0x44d77429f35c")} scan:1</code><br>

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
    Checks for a bluetooth device with the help of PRESENCE2d or collectord. They can be installed where-ever you like, however accessible via network.
    The given device will be checked for PRESENCE2 status.<br>
    The default port is 5111 (PRESENCE2d). Alternatly you can use port 5222 (collectord)<br>
    <u>Example</u><br>
    <code>define iPhone PRESENCE2 lan-bluetooth 0a:4f:36:d8:f9:89 127.0.0.1:5222</code><br><br>
    <u>PRESENCE2d</u><br>
    <ul>PRESENCE2 is a perl network daemon, which provides PRESENCE2 checks of multiple bluetooth devices over network.
    It listens on TCP port 5111 for incoming connections from a FHEM PRESENCE2 instance or a running collectord.<br>

    Executes the OS <i>command</i> and parses the reply for <i>scanExpression</i>.<br>
    <u>Example</u><br>
    <code>define iPhone PRESENCE2 lan-bluetooth 0a:8d:4f:51:3c:8f</code><br>

<PRE>
Usage:
  PRESENCE2d [-d] [-p &lt;port&gt;] [-P &lt;filename&gt;]
  PRESENCE2d [-h | --help]

Options:
  -p, --port
     TCP Port which should be used (Default: 5111)
  -P, --pid-file
     PID file for storing the local process id (Default: /var/run/PRESENCE2d.pid)
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

    The PRESENCE2d is available as:<br><br>
    <ul>
    <li>direct perl script file: <a href="https://svn.fhem.de/trac/export/HEAD/trunk/fhem/contrib/PRESENCE2/PRESENCE2d" target="_new">PRESENCE2d</a></li>
    <li>.deb package for Debian/Raspbian (noarch): <a href="https://svn.fhem.de/trac/export/HEAD/trunk/fhem/contrib/PRESENCE2/deb/PRESENCE2d-1.5.deb" target="_new">PRESENCE2d-1.5.deb</a></li>
    </ul>
    </ul><br><br>
        <u>lePRESENCE2d</u><br>
    <ul>lePRESENCE2d is a Perl network daemon that provides PRESENCE2 checks of
    multiple bluetooth devices over network. In contrast to PRESENCE2d,
    lePRESENCE2d covers <u>Bluetooth 4.0 (low energy) devices, i. e.
    Gigaset G-Tags, FitBit Charges.</u>
    lePRESENCE2d listens on TCP port 5333 for connections of a PRESENCE2 definition
    or collectord.<br>

    To detect the PRESENCE2 of a device, it uses the command <i>hcitool lescan</i> (package:
    <a href="http://www.bluez.org" target="_new">bluez</a>) to continuously listen to
    beacons of Bluetooth LE devices.
    <br><br>

    If a device is present, this is send to FHEM, as well as the device name as reading.<br><br>

    The PRESENCE2d is available as:<br><br>
    <ul>
    <li>Perl script: <a href="https://svn.fhem.de/trac/export/HEAD/trunk/fhem/contrib/PRESENCE2/lePRESENCE2d" target="_new">lePRESENCE2d</a></li>
    <li>.deb package (noarch): <a href="https://svn.fhem.de/trac/export/HEAD/trunk/fhem/contrib/PRESENCE2/deb/" target="_new">contrib/PRESENCE2/deb/</a></li>
    </ul>
    </ul><br><br>
    <u>collectord</u><br>
    <ul>
    The collectord is a perl network daemon, which handles connections to several PRESENCE2d installations to search for multiple bluetooth devices over network.<br><br>

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
    Before the collectord can be used, it needs a config file, where all different rooms, which have a PRESENCE2d detector, will be listed. This config file looks like:
    <br>
<PRE>
    # room definition
    # ===============
    #
    [room-name]              # name of the room
    address=192.168.0.10     # ip-address or hostname
    port=5111                # tcp port which should be used (5111 is default)
    PRESENCE2_timeout=120     # timeout in seconds for each check when devices are present
    absence_timeout=20       # timeout in seconds for each check when devices are absent

    [living room]
    address=192.168.0.11
    port=5111
    PRESENCE2_timeout=180
    absence_timeout=20
</PRE>

    If a device is present in any of the configured rooms, this is send to FHEM, as well as the device name as reading and the room which has detected the device.<br><br>

    The collectord is available as:<br><br>

    <ul>
    <li>direct perl script file: <a href="https://svn.fhem.de/trac/export/HEAD/trunk/fhem/contrib/PRESENCE2/collectord" target="_new">collectord</a></li>
    <li>.deb package for Debian (noarch): <a href="https://svn.fhem.de/trac/export/HEAD/trunk/fhem/contrib/PRESENCE2/deb/collectord-1.8.1.deb" target="_new">collectord-1.8.1.deb</a></li>
    </ul>
    </ul>
  </ul>
  <br>
  <a name="PRESENCE2_set"></a>
  <b>Set</b>
  <ul>
     <li><b>statusRequest</b> - Schedules an immediatly check.</li>
     <li><b>clearCounts</b>   - reset counter values.</li>
     <li><b>statusRequest daemon</b> - (daemon only). clear all counts from deamon.</li>
     <li><b>statusRequest allEntities</b> - (daemon only). clear all counts from deamon and all PRESENCE2 entities.</li>
  </ul>
  <br>

  <a name="PRESENCE2_get"></a>
  <b>Get</b>
  <ul>
     <li><b>list normal</b> - execute list command.</li>
     <li><b>list full</b> - execute list command and include hidden entries.</li>
     <li><b>childInfo PRESENCE2</b> - (daemon only). show all running forked processes started by PRESENCE2.</li>
     <li><b>childInfo all</b> - (daemon only). show all running forked processes.</li>
     <li><b>statusInfo definition</b> - (daemon only). return a table of the definition for all PRESENCE2 entities.</li>
     <li><b>statusInfo stats</b> - (daemon only). return a table of the status for all PRESENCE2 entities.</li>
  </ul>
  <br>

  <a name="PRESENCE2_attr"></a>
  <b>Attributes</b><br><br>
  <ul>
    <li><b><a name="PRESENCE2_disable">disable</a></b></li>
    If activated, an check is disabled and state is set to disabled.<br>
    <li><b><a name="PRESENCE2_interavalAbsence">interavalAbsence</a></b></li>
    Time in seconds to check status, default 30. It is adjusted to the deamons cycle.<br>
    <li><b><a name="PRESENCE2_interavalPresent">interavalPresent</a></b></li>
    Time in seconds to check status if the device is in state present. It is adjusted to the deamons cycle.<br>
    Not applicable for daemon entity<br>
    <li><b><a name="PRESENCE2_thresholdAbsence">thresholdAbsence</a></b></li>
    The number of checks that have to result in "absent" before the state is changed to "absent".
    If this attribute is set to a value &gt;1, the reading PRESENCE2 will be set to "maybe absent" during the absence verification.<br>
    <li><b><a name="PRESENCE2_prGroup">prGroup</a></b></li>
    Assign the entity to a group for examination purpose. An entity can be assigned to multiple groups. Daemon will accumulate the status by groups.<br>
    <li><b><a name="PRESENCE2_prGroupDisp">thresholdAbsence</a></b></li>
    Display options for group readings. Options are <i>condensed</i> or <i>verbose</i>.<br>
    <li><b><a name="PRESENCE2_presentCycle">presentCycle</a></b></li>
    This attribut may be set to any (ANY) instance in FHEM. It defines the requested cycle time that a reading of the entiy needs to be renewed. The daemon will check the reading's update in its interval. Upon violation of the required timing the reading will toggle to absent.<br>
    The Reading to be superviced is defined in attr <i>presentReading</i> and defaults to <i>state</i>.<br>
    <li><b><a name="PRESENCE2_presentReading">presentReading</a></b></li>
    This attribut may be set to any (ANY) instance in FHEM. It defines the reading name that is supervices by <i>presentCycle</i>.<br>
  </ul>
  <br>

  <a name="PRESENCE2_events"></a>
  <b>Readings/events:</b><br><br>
  <ul>
    <u>General</u><br>
    <ul>
    <li><b>state</b>: (absent|present|disabled) - The state of the device, check errors or "disabled" when the <a href="#PRESENCE2_disable">disable</a> attribute is enabled</li>
    <li><b>PRESENCE2</b>: (absent|maybe absent|present|maybe present) - The PRESENCE2 state of the device. The value "maybe absent" only occurs if <a href="#PRESENCE2_thresholdAbsence">thresholdAbsence</a> is activated.</li>
    <li><b>appearCnt</b>: count of entering availale</li>
    <li><b>lastAppear</b>: timestamp of last appearence</li>
    <li><b>lastDisappear</b>: timestamp of last disappearence</li>
    <li><b>thresHldCnt</b>: current thresdold counter. 0 = threshold not active </li>

    </ul><br>
    <u>Daemon specific readings/events:</u><br><br>
    <ul>
    <li><b>daemonMaxScanTime</b>: maximum time the scan job used. Should be less than intervalNormal to avoid skip.</li>
    <li><b>daemonSkipCnt</b>: counter of skipping the daemon job due to collision.</li>
    <li><b>pGrp_&lt;group&gt;</b>: counter summary of entites assigned to &lt;group&gt;</li>
    <li><b>pGrp_&lt;group&gt;_ab</b>: verbose counter summary of entites assigned to &lt;group&gt; : absent entities</li>
    <li><b>pGrp_&lt;group&gt;_dis</b>: verbose counter summary of entites assigned to &lt;group&gt; : disabled entities</li>
    <li><b>pGrp_&lt;group&gt;_pres</b>: verbose counter summary of entites assigned to &lt;group&gt; : present entities</li>
    <li><b>pr_&lt;entity&gt;</b>: status of the PRESENT supervision - see presentCycle</li>
    <li><b>evt_&lt;entiy&gt;</b>: status of the event supervision - see presentCycle</li>
    </ul><br><br>

    <u>Bluetooth specific readings/events:</u><br>
    <ul>
    <li><b>device_name</b>: $name - The name of the Bluetooth device in case it's present</li>
    </ul><br><br>
  </ul>
</ul>

=end html

=cut
