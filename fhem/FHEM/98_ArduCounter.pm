############################################################################
# $Id$
# fhem Modul für Impulszähler auf Basis von Arduino mit ArduCounter Sketch
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
#   Changelog:
#
#   2014-2-4    initial version
#   2014-3-12   added documentation
#   2015-02-08  renamed ACNT to ArduCounter
#   2016-01-01  added attributes for reading names
#   2016-10-15  fixed bug in handling Initialized / STATE
#               added attribute for individual factor for each pin
#   2016-10-29  added option to receive additional Message vom sketch and log it at level 4
#               added documentation, changed logging timestamp for power to begin of interval
#   2016-11-02  Attribute to control timestamp backdating
#   2016-11-04  allow number instead of rising etc. as change with min pulse length
#   2016-11-10  finish parsing new messages
#   2016-11-12  added attributes verboseReadings, readingStartTime
#               add readAnswer for get info
#   2016-12-13  better logging, ignore empty lines from Ardiuno
#               change to new communication syntax of sketch version 1.6
#   2016-12-24  add -b 57600 to flashCommand
#   2016-12-25  check for old firmware and log error, better logging, disable attribute
#   2017-01-01  improved logging
#   2017-01-02  modification for sketch 1.7, monitor clock drift difference between ardino and Fhem
#   2017-01-04  some more beatification in logging
#   2017-01-06  avoid reopening when disable=0 is set during startup
#   2017-02-06  Doku korrigiert
#   2017-02-18  fixed a bug that caused a missing open when the device is defined while fhem is already initialized
#   2017-05-09  fixed character encoding for documentation text
#   2017-09-24  interpolation of lost impulses during fhem restart / arduino reset
#   2017-10-03  bug fix
#   2017-10-06  more optimisations regarding longCount
#   2017-10-08  more little bug fixes (parsing debug messages)
#   2017-10-14  modifications for new sketch version 1.9
#   2017-11-26  minor modifications of log levels
#   2017-12-02  fixed adding up reject count reading
#   2017-12-27  modified logging levels
#   2018-01-01  little fixes
#   2018-01-02  extend reporting line with history H.*, create new reading pinHistory if received from device and verboseReadings is set to 1
#               create long count readings always, not only if attr verboseReadings is set to 1
#   2018-01-03  little docu fix
#   2018-01-13  little docu addon
#   2018-02-04  modifications for ArduCounter on ESP8266 connected via TCP
#                   remove "change" as option (only rising and falling allowed now)
#                   TCP connection handling, keepalive, 
#                   many changes more ...
#   2018-03-07  fix pinHistory when verboseReadings is not set
#   2018-03-08  parse board name in setup / hello message
#   2018-04-10  many smaller fixes, new interpolation based on real boot time, counter etc.
#   2018-05-13  send keepalive delay with k command, don't reset k timer when parsing a message
#   2018-07-17  modify define / notify so connection is opened after Event Defined 
#
# ideas / todo:
#   - OTA Flashing for ESP
#
#   - parse sequence num of history entries -> reconstruct long history list in perl mem 
#       and display with get history instead of readings incl. individual time
#
#   - timeMissed
#
#


package main;

use strict;                          
use warnings;                        
use Time::HiRes qw(gettimeofday);    

my %ArduCounter_sets = (  
    "disable"       =>  "",
    "enable"        =>  "",
    "raw"           =>  "",
    "reset"         =>  "",
    "flash"         =>  "",
    "devVerbose"    => "",
    "saveConfig"    => "",
    "reconnect"     =>  ""  
);

my %ArduCounter_gets = (  
    "info"   =>  ""
);

my $ArduCounter_Version = '5.94 - 13.5.2018';

#
# FHEM module intitialisation
# defines the functions to be called from FHEM
#########################################################################
sub ArduCounter_Initialize($)
{
    my ($hash) = @_;

    require "$attr{global}{modpath}/FHEM/DevIo.pm";

    $hash->{ReadFn}   = "ArduCounter_Read";
    $hash->{ReadyFn}  = "ArduCounter_Ready";
    $hash->{DefFn}    = "ArduCounter_Define";
    $hash->{UndefFn}  = "ArduCounter_Undef";
    $hash->{GetFn}    = "ArduCounter_Get";
    $hash->{SetFn}    = "ArduCounter_Set";
    $hash->{AttrFn}   = "ArduCounter_Attr";
    $hash->{NotifyFn} = "ArduCounter_Notify";
    $hash->{AttrList} =
        'pin.* ' .
        "interval " .
        "factor " .
        "readingNameCount[0-9]+ " .
        "readingNamePower[0-9]+ " .
        "readingNameLongCount[0-9]+ " .
        "readingNameInterpolatedCount[0-9]+ " .
        "readingFactor[0-9]+ " .
        "readingStartTime[0-9]+ " .
        "verboseReadings[0-9]+ " .
        "flashCommand " .
        "helloSendDelay " .
        "helloWaitTime " .        
        "keepAliveDelay " .
        "keepAliveTimeout " .
        "nextOpenDelay " .
        "silentReconnect " .
        "openTimeout " .
        
        "disable:0,1 " .
        "do_not_notify:1,0 " . 
        $readingFnAttributes;
}

#
# Define command
##########################################################################
sub ArduCounter_Define($$)
{
    my ($hash, $def) = @_;
    my @a = split( "[ \t\n]+", $def );

    return "wrong syntax: define <name> ArduCounter devicename\@speed"
      if ( @a < 3 );

    DevIo_CloseDev($hash);
    my $name = $a[0];
    my $dev  = $a[2];
    
    if ($dev =~ m/^(.+):([0-9]+)$/) {
        # tcp conection
        $hash->{TCP} = 1;
    } else {
        if ($dev !~ /.+@([0-9]+)/) {
            $dev .= '@38400';
        } else {
            Log3 $name, 3, "$name: Warning: connection speed $1 is not the default for the ArduCounter firmware"
                if ($1 != 38400);
        }
    }
    $hash->{DeviceName}    = $dev;
    $hash->{VersionModule} = $ArduCounter_Version;
    $hash->{NOTIFYDEV}     = "global";                  # NotifyFn nur aufrufen wenn global events (INITIALIZED)
    $hash->{STATE}         = "disconnected";
    
    delete $hash->{Initialized};                        # device might not be initialized - wait for hello / setup before cmds
    
    if(!defined($attr{$name}{'flashCommand'})) {
        #$attr{$name}{'flashCommand'} = 'avrdude -p atmega328P -b 57600 -c arduino -P [PORT] -D -U flash:w:[HEXFILE] 2>[LOGFILE]';      # for nano
        $attr{$name}{'flashCommand'} = 'avrdude -p atmega328P -c arduino -P [PORT] -D -U flash:w:[HEXFILE] 2>[LOGFILE]';                # for uno
    }
    
    Log3 $name, 5, "$name: defined with $dev, Module version $ArduCounter_Version";
    #if ($init_done) {
    #    ArduCounter_Open($hash);
    #}   
    # do open in notify
    
    return;
}


#
# undefine command when device is deleted
#########################################################################
sub ArduCounter_Undef($$)    
{                     
    my ( $hash, $arg ) = @_;       
    DevIo_CloseDev($hash);             
}    


# remove timers, call DevIo_Disconnected 
# to set state and add to readyFnList
#####################################################
sub ArduCounter_Disconnected($)
{
    my $hash = shift;
    my $name = $hash->{NAME};
  
    RemoveInternalTimer ("alive:$name");            # no timeout if waiting for keepalive response
    RemoveInternalTimer ("keepAlive:$name");        # don't send keepalive messages anymore
    RemoveInternalTimer ("sendHello:$name");
    DevIo_Disconnected($hash);                      # close, add to readyFnList so _Ready is called to reopen
    delete $hash->{WaitForAlive};
}


#####################################
sub ArduCounter_OpenCB($$)
{
    my ($hash, $msg) = @_;
    my $name = $hash->{NAME};
    my $now  = gettimeofday();
    if ($msg) {
        Log3 $name, 5, "$name: Open callback: $msg" if ($msg);
    }
    delete $hash->{BUSY_OPENDEV};
    if ($hash->{FD}) {  
        Log3 $name, 5, "$name: ArduCounter_Open succeeded in callback";
        my $hdl = AttrVal($name, "helloSendDelay", 15);
        # send hello if device doesn't say "Started" withing $hdl seconds
        RemoveInternalTimer ("sendHello:$name");
        InternalTimer($now+$hdl, "ArduCounter_AskForHello", "sendHello:$name", 0);    
        
        if ($hash->{TCP}) {
            # send first keepalive immediately to turn on tcp mode in device
            ArduCounter_KeepAlive("keepAlive:$name");   
        }
    } else {
        #Log3 $name, 5, "$name: ArduCounter_Open failed - open callback called from DevIO without FD";
    }

    return;
}


########################################################
# Open Device
sub ArduCounter_Open($;$)
{
    my ($hash, $reopen) = @_;
    my $name = $hash->{NAME};
    my $now  = gettimeofday();
    $reopen  = 0 if (!$reopen);
    
    if ($hash->{BUSY_OPENDEV}) {  # still waiting for callback to last open 
        if ($hash->{LASTOPEN} && $now > $hash->{LASTOPEN} + (AttrVal($name, "openTimeout", 3) * 2)
                              && $now > $hash->{LASTOPEN} + 15) {
            Log3 $name, 5, "$name: _Open - still waiting for open callback, timeout is over twice - this should never happen";
            Log3 $name, 5, "$name: _Open - stop waiting and reset the flag.";
            $hash->{BUSY_OPENDEV} = 0;
        } else {
            Log3 $name, 5, "$name: _Open - still waiting for open callback";
            return;
        }
    }    
    
    if (!$reopen) {         # not called from _Ready
        DevIo_CloseDev($hash);
        delete $hash->{NEXT_OPEN};
        delete $hash->{DevIoJustClosed};
    }
    
    Log3 $name, 4, "$name: trying to open connection to $hash->{DeviceName}" if (!$reopen);

    $hash->{BUSY_OPENDEV}   = 1;
    $hash->{LASTOPEN}       = $now;
    $hash->{nextOpenDelay}  = AttrVal($name, "nextOpenDelay", 60);   
    $hash->{devioLoglevel}  = (AttrVal($name, "silentReconnect", 0) ? 4 : 3);
    $hash->{TIMEOUT}        = AttrVal($name, "openTimeout", 3);
    $hash->{buffer}         = "";       # clear Buffer for reception

    DevIo_OpenDev($hash, $reopen, 0, \&ArduCounter_OpenCB);
    delete $hash->{TIMEOUT};    
    if ($hash->{FD}) {  
        Log3 $name, 5, "$name: ArduCounter_Open succeeded immediatelay" if (!$reopen);
    } else {
        Log3 $name, 5, "$name: ArduCounter_Open waiting for callback" if (!$reopen);
    }

}


#########################################################################
sub ArduCounter_Ready($)
{
    my ($hash) = @_;
    my $name   = $hash->{NAME};
    
    if($hash->{STATE} eq "disconnected") {  
        RemoveInternalTimer ("alive:$name");        # no timeout if waiting for keepalive response
        RemoveInternalTimer ("keepAlive:$name");    # don't send keepalive messages anymore
        delete $hash->{WaitForAlive};
        delete $hash->{Initialized};                # when reconnecting wait for setup / hello before further action
        if (IsDisabled($name)) {
            Log3 $name, 3, "$name: _Ready: $name is disabled - don't try to reconnect";
            DevIo_CloseDev($hash);                  # close, remove from readyfnlist so _ready is not called again         
            return;
        }
        ArduCounter_Open($hash, 1);                 # reopen, don't call DevIoClose before reopening
        return;                                     # a return value triggers direct read for win
    }
    # This is relevant for windows/USB only
    my $po = $hash->{USBDev};
    if ($po) {
        my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
        return ($InBytes>0);                        # tell fhem.pl to read when we return
    }
    return;
}


#######################################
# Aufruf aus InternalTimer
sub ArduCounter_DelayedOpen($)
{
    my $param = shift;
    my (undef,$name) = split(':',$param);
    my $hash = $defs{$name};
    
    Log3 $name, 4, "$name: try to reopen connection after delay";
    RemoveInternalTimer ("delayedopen:$name");
    delete $hash->{DevIoJustClosed};    # otherwise open returns without doing anything this time and we are not on the readyFnList ...
    ArduCounter_Open($hash, 1);         # reopen
}


########################################################
# Notify for INITIALIZED or Modified 
# -> Open connection to device
sub ArduCounter_Notify($$)
{
    my ($hash, $source) = @_;
    return if($source->{NAME} ne "global");

    my $events = deviceEvents($source, 1);
    return if(!$events);

    my $name = $hash->{NAME};
    # Log3 $name, 5, "$name: Notify called for source $source->{NAME} with events: @{$events}";
  
    return if (!grep(m/^INITIALIZED|REREADCFG|(MODIFIED $name)|(DEFINED $name)$/, @{$source->{CHANGED}}));

    if (IsDisabled($name)) {
        Log3 $name, 3, "$name: Notify / Init: device is disabled";
        return;
    }   

    Log3 $name, 3, "$name: Notify called with events: @{$events}, open device and set timer to send hello to device";
    ArduCounter_Open($hash);    
}


######################################
# wrapper for DevIo write
sub ArduCounter_Write ($$)
{
    my ($hash, $line) = @_;
    my $name = $hash->{NAME};
    if ($hash->{STATE} eq "disconnected" || !$hash->{FD}) {
        Log3 $name, 5, "$name: Write: device is disconnected, dropping line to write";
        return 0;
    } 
    if (IsDisabled($name)) {
        Log3 $name, 5, "$name: Write called but device is disabled, dropping line to send";
        return 0;
    }   
    #Log3 $name, 5, "$name: Write: $line";  # devio will already log the write
    #DevIo_SimpleWrite($hash, "\n", 2);
    DevIo_SimpleWrite($hash, "$line.", 2);
    return 1;
}


#######################################
# Aufruf aus InternalTimer
# send "h" to ask for "Hello" since device didn't say "Started" so far - maybe it's still counting ...
# called with timer from _open, _Ready and if count is read in _Parse
sub ArduCounter_AskForHello($)
{
    my $param = shift;
    my (undef,$name) = split(':',$param);
    my $hash = $defs{$name};
    
    Log3 $name, 3, "$name: sending h(ello) to device to ask for version";
    return if (!ArduCounter_Write( $hash, "h"));

    my $now = gettimeofday();
    my $hwt = AttrVal($name, "helloWaitTime", 3);
    RemoveInternalTimer ("hwait:$name");
    InternalTimer($now+$hwt, "ArduCounter_HelloTimeout", "hwait:$name", 0);
    $hash->{WaitForHello} = 1;
}


#######################################
# Aufruf aus InternalTimer
sub ArduCounter_HelloTimeout($)
{
    my $param = shift;
    my (undef,$name) = split(':',$param);
    my $hash = $defs{$name};
    Log3 $name, 3, "$name: device didn't reply to h(ello). Is the right sketch flashed? Is speed set to 38400?";
    delete $hash->{WaitForHello};
    RemoveInternalTimer ("hwait:$name");
}


############################################
# Aufruf aus Open / Ready und InternalTimer
# send "1k" to ask for "alive"
sub ArduCounter_KeepAlive($)
{
    my $param = shift;
    my (undef,$name) = split(':',$param);
    my $hash = $defs{$name};
    my $now = gettimeofday();
    
    if (IsDisabled($name)) {
        return;
    }

    my $kdl = AttrVal($name, "keepAliveDelay", 10);     # next keepalive as timer
    my $kto = AttrVal($name, "keepAliveTimeout", 2);    # timeout waiting for response 
    
    Log3 $name, 5, "$name: sending k(eepAlive) to device";
    ArduCounter_Write( $hash, "1,${kdl}k");
    
    RemoveInternalTimer ("alive:$name");
    InternalTimer($now+$kto, "ArduCounter_AliveTimeout", "alive:$name", 0);
    $hash->{WaitForAlive} = 1;
    
    if ($hash->{TCP}) {        
        RemoveInternalTimer ("keepAlive:$name");
        InternalTimer($now+$kdl, "ArduCounter_KeepAlive", "keepAlive:$name", 0);    # next keepalive
    }
}


#######################################
# Aufruf aus InternalTimer
sub ArduCounter_AliveTimeout($)
{
    my $param = shift;
    my (undef,$name) = split(':',$param);
    my $hash = $defs{$name};
    Log3 $name, 3, "$name: device didn't reply to k(eeepAlive), setting to disconnected and try to reopen";
    delete $hash->{WaitForAlive};
    
    $hash->{KeepAliveRetries} = 0 if (!$hash->{KeepAliveRetries});
            
    if (++$hash->{KeepAliveRetries} > AttrVal($name, "keepAliveRetries", 1)) {
        Log3 $name, 3, "$name: no retries left, setting device to disconnected";
        ArduCounter_Disconnected($hash);        # set to Disconnected but let _Ready try to Reopen
    }
}


#
# Send config commands after Board reported it is ready or still counting
# called from internal timer to give device the time to report its config first
##########################################################################
sub ArduCounter_ConfigureDevice($)
{
    my $param = shift;
    my (undef,$name) = split(':',$param);
    my $hash = $defs{$name};
    
    # todo: check if device got disconnected in the meantime!
    
    # first check if device did send its config, then compare and send config if necessary
    if ($hash->{runningCfg}) {
        Log3 $name, 5, "$name: ConfigureDevice: got running config - comparing";
        my $iAttr = AttrVal($name, "interval", "");     
        if (!$iAttr) {
            $iAttr = "30 60 2 2";
            Log3 $name, 5, "$name: ConfigureDevice: interval attr not set - take default $iAttr";
        }
        if ($iAttr =~ /^(\d+) (\d+) ?(\d+)? ?(\d+)?$/) {
            #Log3 $name, 5, "$name: ConfigureDevice: comparing interval";
            my $iACfg = "$1 $2 " . ($3 ? $3 : "0") . " " . ($4 ? $4 : "0");
            if ($hash->{runningCfg}{I} eq $iACfg) {
                #Log3 $name, 5, "$name: ConfigureDevice: interval matches - now compare pins";
                # interval config matches - now check pins as well
                my @runningPins = sort grep (/[\d]/, keys %{$hash->{runningCfg}});
                #Log3 $name, 5, "$name: ConfigureDevice: pins in running config: @runningPins";
                my @attrPins = sort grep (/pin([dD])?[\d]/, keys %{$attr{$name}});
                #Log3 $name, 5, "$name: ConfigureDevice: pins from attrs: @attrPins";
                if (@runningPins == @attrPins) {
                    my $match = 1;
                    for (my $i = 0; $i < @attrPins; $i++) {
                        #Log3 $name, 5, "$name: ConfigureDevice: compare pin $attrPins[$i] to $runningPins[$i]";
                        $attrPins[$i] =~ /pin[dD]?([\d+]+)/;
                        my $pinNum = $1;
                        $runningPins[$i] =~ /pin[dD]?([\d]+)/;
                        $match = 0 if (!$1 || $1 ne $pinNum);
                        #Log3 $name, 5, "$name: ConfigureDevice: now compare pin $attrPins[$i] $attr{$name}{$attrPins[$i]} to $hash->{runningCfg}{$pinNum}";
                        $match = 0 if (($attr{$name}{$attrPins[$i]}) ne $hash->{runningCfg}{$pinNum});
                    }
                    if ($match) {        # Config matches -> leave
                        Log3 $name, 5, "$name: ConfigureDevice: running config matches attributes";
                        return;
                    }
                    Log3 $name, 5, "$name: ConfigureDevice: no match -> send config";
                } else {
                    Log3 $name, 5, "$name: ConfigureDevice: pin numbers don't match (@runningPins vs. @attrPins)";
                }
            } else {
                Log3 $name, 5, "$name: ConfigureDevice: interval does not match (>$hash->{runningCfg}{I}< vs >$iACfg< from attr)";
            }
        } else {
            Log3 $name, 5, "$name: ConfigureDevice: can not compare against interval attr";
        }
    } else {
        Log3 $name, 5, "$name: ConfigureDevice: no running config received";
    }
                    
    # send attributes to arduino device. Just call ArduCounter_Attr again
    Log3 $name, 3, "$name: sending configuration from attributes to device";
    while (my ($aName, $val) = each(%{$attr{$name}})) {
        if ($aName =~ "pin|interval") {
            Log3 $name, 3, "$name: ConfigureDevice calls Attr with $aName $val";
            ArduCounter_Attr("set", $name, $aName, $val); 
        }
    }
}


# Attr command 
#########################################################################
sub ArduCounter_Attr(@)
{
    my ($cmd,$name,$aName,$aVal) = @_;
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value

    my $hash    = $defs{$name};
    my $modHash = $modules{$hash->{TYPE}};

    
    #Log3 $name, 5, "$name: Attr called with @_";
    if ($cmd eq "set") {
        if ($aName =~ /^pin[dD]?(\d+)/) {
            my $pin = $1;
            my %pins;
            if ($hash->{allowedPins}) {
                %pins = map { $_ => 1 } split (",", $hash->{allowedPins});
            }
            if ($init_done && $hash->{allowedPins} && %pins && !$pins{$pin}) {
                Log3 $name, 3, "$name: Invalid pin in attr $name $aName $aVal";
                return "Invalid / disallowed pin specification $aName";
            }            
            if ($aVal =~ /^(rising|falling) ?(pullup)? ?([0-9]+)?/) {
                my $opt = "";
                if ($1 eq 'rising')       {$opt = "3"}
                elsif ($1 eq 'falling')   {$opt = "2"}
                $opt .= ($2 ? ",1" : ",0");         # pullup
                $opt .= ($3 ? ",$3" : "");          # min length
                
                if ($hash->{Initialized}) {         
                    ArduCounter_Write($hash, "${pin},${opt}a");
                } else {
                    Log3 $name, 5, "$name: communication postponed until device is initialized";
                }
                  
            } else {
                Log3 $name, 3, "$name: Invalid value in attr $name $aName $aVal";
                return "Invalid Value $aVal";
            }
        } elsif ($aName eq "interval") {
            if ($aVal =~ /^(\d+) (\d+) ?(\d+)? ?(\d+)?$/) {
                my $min = $1;
                my $max = $2;
                my $sml = $3;
                my $cnt = $4;
                if ($min < 1 || $min > 3600 || $max < $min || $max > 3600) {
                    Log3 $name, 3, "$name: Invalid value in attr $name $aName $aVal";
                    return "Invalid Value $aVal";
                }
                if ($hash->{Initialized}) {
                    $sml = 0 if (!$sml);
                    $cnt = 0 if (!$cnt);
                    ArduCounter_Write($hash, "${min},${max},${sml},${cnt}i");
                } else {
                    Log3 $name, 5, "$name: communication postponed until device is initialized";
                }
            } else {
                Log3 $name, 3, "$name: Invalid value in attr $name $aName $aVal";
                return "Invalid Value $aVal";
            }           
        } elsif ($aName eq "factor") {
            if ($aVal =~ '^(\d+)$') {
            } else {
                Log3 $name, 3, "$name: Invalid value in attr $name $aName $aVal";
                return "Invalid Value $aVal";
            }           
        } elsif ($aName eq "keepAliveDelay") {
            if ($aVal =~ '^(\d+)$') {
                if ($aVal > 300) {
                    Log3 $name, 3, "$name: value too big in attr $name $aName $aVal";
                    return "Value too big: $aVal";
                }
            } else {
                Log3 $name, 3, "$name: Invalid value in attr $name $aName $aVal";
                return "Invalid Value $aVal";
            }           
        } elsif ($aName eq 'disable') {
            if ($aVal) {
                Log3 $name, 5, "$name: disable attribute set";                
                ArduCounter_Disconnected($hash);    # set to disconnected and remove timers
                DevIo_CloseDev($hash);              # really close and remove from readyFnList again
                return;
            } else {
                Log3 $name, 3, "$name: disable attribute cleared";
                ArduCounter_Open($hash) if ($init_done);    # only if fhem is initialized
            }
        }       
        
        # handle wild card attributes -> Add to userattr to allow modification in fhemweb
        #Log3 $name, 3, "$name: attribute $aName checking ";
        if (" $modHash->{AttrList} " !~ m/ ${aName}[ :;]/) {
            # nicht direkt in der Liste -> evt. wildcard attr in AttrList
            foreach my $la (split " ", $modHash->{AttrList}) {
                $la =~ /([^:;]+)(:?.*)/;
                my $vgl = $1;           # attribute name in list - probably a regex
                my $opt = $2;           # attribute hint in list
                if ($aName =~ $vgl) {   # yes - the name in the list now matches as regex
                    # $aName ist eine Ausprägung eines wildcard attrs
                    addToDevAttrList($name, "$aName" . $opt);    # create userattr with hint to allow changing by click in fhemweb
                    if ($opt) {
                        # remove old entries without hint
                        my $ualist = $attr{$name}{userattr};
                        $ualist = "" if(!$ualist);  
                        my %uahash;
                        foreach my $a (split(" ", $ualist)) {
                            if ($a !~ /^${aName}$/) {    # entry in userattr list is attribute without hint
                                $uahash{$a} = 1;
                            } else {
                                Log3 $name, 3, "$name: added hint $opt to attr $a in userattr list";
                            }
                        }
                        $attr{$name}{userattr} = join(" ", sort keys %uahash);
                    }
                }
            }
        } else {
            # exakt in Liste enthalten -> sicherstellen, dass keine +* etc. drin sind.
            if ($aName =~ /\|\*\+\[/) {
                Log3 $name, 3, "$name: Atribute $aName is not valid. It still contains wildcard symbols";
                return "$name: Atribute $aName is not valid. It still contains wildcard symbols";
            }
        }
        
    } elsif ($cmd eq "del") {
        if ($aName =~ 'pin.*') {
            if ($aName !~ 'pin([dD]?\d+)') {
                Log3 $name, 3, "$name: Invalid pin name in attr $name $aName $aVal";
                return "Invalid pin name $aName";
            }
            my $pin = $1;

            if ($hash->{Initialized}) {     # did device already report its version?
                ArduCounter_Write( $hash, "${pin}d");
            } else {
                Log3 $name, 5, "$name: pin config can not be deleted since device is not initialized yet";
                return "device is not initialized yet";
            }

        } elsif ($aName eq 'disable') {
            Log3 $name, 3, "$name: disable attribute removed";    
            ArduCounter_Open($hash) if ($init_done);       # if fhem is initialized
        }
    }
    return undef;
}


# SET command
#########################################################################
sub ArduCounter_Flash($$)
{
    my ($hash, @args) = @_;
    my $name = $hash->{NAME};
    my $log = "";   
    my @deviceName = split('@', $hash->{DeviceName});
    my $port = $deviceName[0];
    my $firmwareFolder = "./FHEM/firmware/";
    my $logFile = AttrVal("global", "logdir", "./log") . "/ArduCounterFlash.log";
    
    return "Flashing ESP8266 not supported yet" if ($hash->{Board} =~ /ESP8266/);
    
    my $hexFile = $firmwareFolder . "ArduCounter.hex";
    return "The file '$hexFile' does not exist" if(!-e $hexFile);

    Log3 $name, 3, "$name: Flashing Aduino at $port with $hexFile. See $logFile for details";
    
    $log .= "flashing device as ArduCounter for $name\n";
    $log .= "hex file: $hexFile\n";

    $log .= "port: $port\n";
    $log .= "log file: $logFile\n";

    my $flashCommand = AttrVal($name, "flashCommand", "");

    if($flashCommand ne "") {
        if (-e $logFile) {
          unlink $logFile;
        }

        ArduCounter_Disconnected($hash);
        DevIo_CloseDev($hash);
        $log .= "$name closed\n";

        my $avrdude = $flashCommand;
        $avrdude =~ s/\Q[PORT]\E/$port/g;
        $avrdude =~ s/\Q[HEXFILE]\E/$hexFile/g;
        $avrdude =~ s/\Q[LOGFILE]\E/$logFile/g;

        $log .= "command: $avrdude\n\n";
        `$avrdude`;

        local $/=undef;
        if (-e $logFile) {
            open FILE, $logFile;
            my $logText = <FILE>;
            close FILE;
            $log .= "--- AVRDUDE ---------------------------------------------------------------------------------\n";
            $log .= $logText;
            $log .= "--- AVRDUDE ---------------------------------------------------------------------------------\n\n";
        }
        else {
            $log .= "WARNING: avrdude created no log file\n\n";
        }
        ArduCounter_Open($hash, 0);                 # new open
        $log .= "$name open called.\n";
        delete $hash->{Initialized};
    }
    return $log;
}


# SET command
#########################################################################
sub ArduCounter_Set($@)
{
    my ($hash, @a) = @_;
    return "\"set ArduCounter\" needs at least one argument" if ( @a < 2 );
    
    # @a is an array with DeviceName, SetName, Rest of Set Line
    my $name = shift @a;
    my $attr = shift @a;
    my $arg = join(" ", @a);

    if(!defined($ArduCounter_sets{$attr})) {
        my @cList = keys %ArduCounter_sets;
        return "Unknown argument $attr, choose one of " . join(" ", @cList);
    } 

    if ($attr eq "disable") {
        Log3 $name, 4, "$name: set disable called";
        CommandAttr(undef, "$name disable 1");
        return;
        
    } elsif ($attr eq "enable") {
        Log3 $name, 4, "$name: set enable called";
        CommandAttr(undef, "$name disable 0");
        return;

    } elsif ($attr eq "reconnect") {
        Log3 $name, 4, "$name: set reconnect called";
        DevIo_CloseDev($hash);   
        ArduCounter_Open($hash);
        return;

    } elsif ($attr eq "flash") {
        return ArduCounter_Flash($hash, @a);        
    }
    
    if(!$hash->{FD}) {
        Log3 $name, 4, "$name: Set $attr $arg called but device is disconnected";
        return ("Set called but device is disconnected", undef);
    }
    if (IsDisabled($name)) {
        Log3 $name, 4, "$name: set $attr $arg called but device is disabled";
        return;
    }   
    
    if ($attr eq "raw") {
        Log3 $name, 4, "$name: set raw $arg called";
        ArduCounter_Write($hash, "$arg");
                
    } elsif ($attr eq "saveConfig") {
        Log3 $name, 4, "$name: set saveConfig called";
        ArduCounter_Write($hash, "e");
        
    } elsif ($attr eq "reset") {
        Log3 $name, 4, "$name: set reset called";
        DevIo_CloseDev($hash); 
        ArduCounter_Open($hash);
        if (ArduCounter_Write($hash, "r")) {
            delete $hash->{Initialized};
            return "sent (r)eset command to device - waiting for its setup message";
        }
       
    } elsif ($attr eq "devVerbose") {
        if ($arg =~ /^\d$/) {
            Log3 $name, 4, "$name: set devVerbose $arg called";
            ArduCounter_Write($hash, "$arg"."v");
        } else {
            Log3 $name, 4, "$name: set devVerbose called with illegal value $arg";
        }            
    }
    return undef;
}


# GET command
#########################################################################
sub ArduCounter_Get($@)
{
    my ( $hash, @a ) = @_;
    return "\"set ArduCounter\" needs at least one argument" if ( @a < 2 );    
    my $name = shift @a;
    my $attr = shift @a;

    if(!defined($ArduCounter_gets{$attr})) {
        my @cList = keys %ArduCounter_gets;
        return "Unknown argument $attr, choose one of " . join(" ", @cList);
    } 

    if(!$hash->{FD}) {
        Log3 $name, 4, "$name: Get called but device is disconnected";
        return ("Get called but device is disconnected", undef);
    }

    if (IsDisabled($name)) {
        Log3 $name, 4, "$name: get called but device is disabled";
        return;
    }   
    
    if ($attr eq "info") {
        Log3 $name, 3, "$name: Sending info command to device";
        ArduCounter_Write( $hash, "s");
        my ($err, $msg) = ArduCounter_ReadAnswer($hash, 'Next report in.*seconds');
        
        return ($err ? $err : $msg);
    }
        
    return undef;
}


######################################
sub ArduCounter_HandleDeviceTime($$$$)
{
    my ($hash, $deTi, $deTiW, $now) = @_;
    my $name = $hash->{NAME};

    my $deviceNowSecs  = ($deTi/1000) + ((0xFFFFFFFF / 1000) * $deTiW);
    Log3 $name, 5, "$name: Device Time $deviceNowSecs";
    
    if (defined ($hash->{'.DeTOff'}) && $hash->{'.LastDeT'}) {
        if ($deviceNowSecs >= $hash->{'.LastDeT'}) {
            $hash->{'.Drift2'} = ($now - $hash->{'.DeTOff'}) - $deviceNowSecs;
        } else {
            $hash->{'.DeTOff'}  = $now - $deviceNowSecs;
            Log3 $name, 4, "$name: device did reset (now $deviceNowSecs, before $hash->{'.LastDeT'}). New offset is $hash->{'.DeTOff'}";
        }
    } else {
        $hash->{'.DeTOff'}  = $now - $deviceNowSecs;
        $hash->{'.Drift2'}  = 0;
        $hash->{'.DriftStart'}  = $now;
        Log3 $name, 5, "$name: Initialize device clock offset to $hash->{'.DeTOff'}";
    }
    $hash->{'.LastDeT'} = $deviceNowSecs;  

    my $drTime = ($now - $hash->{'.DriftStart'});
    #Log3 $name, 5, "$name: Device Time $deviceNowSecs" .
        #", Offset " . sprintf("%.3f", $hash->{'.DeTOff'}/1000) . 
        ", Drift "  . sprintf("%.3f", $hash->{'.Drift2'}) .
        "s in " . sprintf("%.3f", $drTime) . "s" .
        ($drTime > 0 ? ", " . sprintf("%.2f", $hash->{'.Drift2'} / $drTime * 100) . "%" : "");
}
            

######################################
sub ArduCounter_ParseHello($$$)
{
    my ($hash, $line, $now) = @_;
    my $name = $hash->{NAME};
    
    if ($line =~ /^ArduCounter V([\d\.]+) on ([^\ ]+ ?[^\ ]*) compiled (.*) Hello(, pins ([0-9\,]+) available)? ?(T([\d]+),([\d]+) B([\d]+),([\d]+))?/) {  # setup / hello message
        $hash->{VersionFirmware} = ($1 ? $1 : "unknown");
        $hash->{Board}           = ($2 ? $2 : "unknown");
        $hash->{SketchCompile}   = ($3 ? $3 : "unknown");
        $hash->{allowedPins}     = $5 if ($5);
        my $mNow   = ($7 ? $7 : 0);
        my $mNowW  = ($8 ? $8 : 0);
        my $mBoot  = ($9 ? $9 : 0);
        my $mBootW = ($10 ? $10 : 0);
        if ($hash->{VersionFirmware} < "2.36") {
            $hash->{VersionFirmware} .= " - not compatible with this Module version - please flash new sketch";
            Log3 $name, 3, "$name: device reported outdated Arducounter Firmware ($hash->{VersionFirmware}) - please update!";
            delete $hash->{Initialized};
        } else {
            Log3 $name, 3, "$name: device sent hello: $line";
            $hash->{Initialized} = 1;   # now device has finished its boot and reported its version
            delete $hash->{runningCfg};
            
            my $cft = AttrVal($name, "ConfigDelay", 1); # wait for device to send cfg before reconf.
            RemoveInternalTimer ("cmpCfg:$name");
            InternalTimer($now+$cft, "ArduCounter_ConfigureDevice", "cmpCfg:$name", 0);
            
            my $deviceNowSecs  = ($mNow/1000) + ((0xFFFFFFFF / 1000) * $mNowW);
            my $deviceBootSecs = ($mBoot/1000) + ((0xFFFFFFFF / 1000) * $mBootW);
            my $bootTime = $now - ($deviceNowSecs - $deviceBootSecs);
            $hash->{deviceBooted} = $bootTime;  # for estimation of missed pulses up to now
        }
        delete $hash->{WaitForHello};
        RemoveInternalTimer ("hwait:$name");        # dont wait for hello reply if already sent
        RemoveInternalTimer ("sendHello:$name");    # Hello not needed anymore if not sent yet
    } else {
        Log3 $name, 4, "$name: probably wrong firmware version - cannot parse line $line";
    }
}


#########################################################################
sub ArduCounter_HandleCounters($$$$$$$$)
{
    my ($hash, $pin, $sequence, $count, $time, $diff, $rDiff, $now) = @_;
    my $name = $hash->{NAME};
    
    my $rcname = AttrVal($name, "readingNameCount$pin", "pin$pin");         # internal count reading
    my $rlname = AttrVal($name, "readingNameLongCount$pin", "long$pin");    # long count
    my $riname = AttrVal($name, "readingNameInterpolatedCount$pin", "interpolatedLong$pin");
    my $lName  = AttrVal($name, "readingNamePower$pin", AttrVal($name, "readingNameCount$pin", "pin$pin")); # for logging
    
    my $longCount = ReadingsVal($name, $rlname, 0);        # alter long count Wert
    my $intpCount = ReadingsVal($name, $riname, 0);        # alter interpolated count Wert
    my $lastCount = ReadingsVal($name, $rcname, 0);
    my $lastSeq   = ReadingsVal($name, "seq".$pin, 0);
    
    my $lastCountTS = ReadingsTimestamp ($name, $rlname, 0);  # last time long count reading was set
    my $lastCountTNum = time_str2num($lastCountTS);
    my $fBootTim      = ($hash->{deviceBooted} ? FmtTime($hash->{deviceBooted}) : "never");     # time device booted 
    my $fLastCTim     = FmtTime($lastCountTNum);
    my $pulseGap = $count - $lastCount - $rDiff;
    my $seqGap   = $sequence - ($lastSeq + 1);

    if (!$lastCountTS && !$longCount && !$intpCount) {
        # new defined or deletereading done ...
        Log3 $name, 3, "$name: pin $pin ($lName) first report, initializing counters to " . ($count - $rDiff); 
        $longCount = $count - $rDiff;
        $intpCount = $count - $rDiff;
    }
    if ($lastCountTS && $hash->{deviceBooted} && $hash->{deviceBooted} > $lastCountTNum) {
        # first report for this pin after a restart 
        # -> do interpolation for period between last report before boot and boot time. count after boot has to be added later
        Log3 $name, 5, "$name: pin $pin ($lName) device restarted at $fBootTim, last reported at $fLastCTim, sequence for pin $pin changed from $lastSeq to $sequence and count from $lastCount to $count";
        $lastSeq  = 0;
        $seqGap   = $sequence - 1;      # $sequence should be 1 after restart
        $pulseGap = $count - $rDiff;    # 
        
        my $lastInterval  = ReadingsVal ($name, "timeDiff$pin", 0);
        my $lastCDiff     = ReadingsVal ($name, "countDiff$pin", 0);
        my $offlTime      = sprintf ("%.2f", $hash->{deviceBooted} - $lastCountTNum);
        
        if ($lastCountTS && $lastInterval && ($offlTime > 0) && ($offlTime < 12*60*60)) {       # > 0 and < 12h
            my $lastRatio = $lastCDiff / $lastInterval;
            my $curRatio  = $diff / $time;
            my $intRatio  = 1000 * ($lastRatio + $curRatio) / 2;
            my $intrCount = int(($offlTime * $intRatio)+0.5);

            Log3 $name, 3, "$name: pin $pin ($lName) interpolating for $offlTime secs until boot, $intrCount estimated pulses (before $lastCDiff in $lastInterval ms, now $diff in $time ms, avg ratio $intRatio p/s)";
            Log3 $name, 5, "$name: pin $pin ($lName) adding interpolated $intrCount to interpolated count $intpCount";
            $intpCount += $intrCount;
            
        } else {
            Log3 $name, 4, "$name: interpolation of missed pulses for pin $pin ($lName) not possible - no valid historic data.";
        }
    } elsif ($lastCountTS && $seqGap < 0) {         
        # new sequence number is smaller than last and we have old readings
        # and this is not after a reboot of the device
        $seqGap += 256;             # correct seq gap
        Log3 $name, 5, "$name: pin $pin ($lName) sequence wrapped from $lastSeq to $sequence, set seqGap to $seqGap";
    }
                
    if ($lastCountTS && $seqGap > 0) {
        # probably missed a report. Maybe even the first ones after a reboot (until reconnect)
        # take last count, delta to new reported count as missed pulses to correct long counter
        my $timeGap  = ($now - $time/1000 - $lastCountTNum);
        if ($pulseGap > 0) {
            $longCount += $pulseGap;
            $intpCount += $pulseGap;
            Log3 $name, 3, "$name: pin $pin ($lName) missed $seqGap reports in $timeGap seconds. Last reported sequence was $lastSeq, now $sequence. Device count before was $lastCount, now $count with rDiff $rDiff. Adding $pulseGap to long count and intpolated count readings";
        } elsif ($pulseGap == 0) {
            # outdated sketch?
            Log3 $name, 5, "$name: pin $pin ($lName) missed $seqGap sequence numbers in $timeGap seconds. Last reported sequence was $lastSeq, now $sequence. Device count before was $lastCount, now $count with rDiff $rDiff. Nothing is missing - ignore";
        } else {
            # strange ...
            Log3 $name, 3, "$name: Pin $pin ($lName) missed $seqGap reports in $timeGap seconds. " .
                "Last reported sequence was $lastSeq, now $sequence. " .
                "Device count before was $lastCount, now $count with rDiff $rDiff " .
                "but pulseGap is $pulseGap. this is wrong and should not happen";
        }
    } 
 
    Log3 $name, 5, "$name: pin $pin ($lName) adding rDiff $rDiff to long count $longCount and interpolated count $intpCount";
    
    $intpCount += $rDiff;
    $longCount += $rDiff;
    
    readingsBulkUpdate($hash, $rcname, $count);
    readingsBulkUpdate($hash, $rlname, $longCount);
    readingsBulkUpdate($hash, $riname, $intpCount);
    readingsBulkUpdate($hash, "seq".$pin, $sequence);
}
        

#########################################################################
sub ArduCounter_ParseReport($$)
{
    my ($hash, $line) = @_;
    my $name  = $hash->{NAME};
    my $now   = gettimeofday();
    if ($line =~ '^R([\d]+) C([\d]+) D([\d]+) ?[\/R]([\d]+) T([\d]+) N([\d]+),([\d]+) X([\d]+)( S[\d]+)?( A[\d]+)?')
    {
        # new count is beeing reported
        my $pin    = $1;
        my $count  = $2;        # internal counter at device
        my $diff   = $3;        # delta during interval
        my $rDiff  = $4;        # real delta including the first pulse after a restart
        my $time   = $5;        # interval
        my $deTime = $6;
        my $deTiW  = $7;
        my $reject = $8;
        my $seq    = ($9 ? substr($9, 2) : "");
        my $avgLen = ($10 ? substr($10, 2) : "");
        
        my $factor = AttrVal($name, "readingFactor$pin", AttrVal($name, "factor", 1000));
        my $rpname = AttrVal($name, "readingNamePower$pin", "power$pin");       # power reading name
        my $lName  = AttrVal($name, "readingNamePower$pin", AttrVal($name, "readingNameCount$pin", "pin$pin")); # for logging
              
        my $sTime  = $now - $time/1000;   # start of observation interval (~first pulse)
        my $fSTime = FmtDateTime($sTime); # formatted
        my $fSdTim = FmtTime($sTime);     # only time formatted for logging
        my $fEdTim = FmtTime($now);       # end of Interval - only time formatted for logging

        ArduCounter_HandleDeviceTime($hash, $deTime, $deTiW, $now);
        
        if (!$time || !$factor) {
            Log3 $name, 3, "$name: Pin $pin ($lName) skip line because time or factor is 0: $line";
            return;
        }
        my $power  = sprintf ("%.3f", ($time ? $diff/$time/1000*3600*$factor : 0));
        Log3 $name, 4, "$name: Pin $pin ($lName) Cnt $count " . 
            "(diff $diff/$rDiff) in " . sprintf("%.3f", $time/1000) . "s" .
            " from $fSdTim until $fEdTim" .
            ", seq $seq" .
            ((defined($reject) && $reject ne "") ? ", Rej $reject" : "") .
            (defined($avgLen) ? ", Avg ${avgLen}ms" : "") .
            ", result $power";   
        
        if (AttrVal($name, "readingStartTime$pin", 0)) {
            readingsBeginUpdate($hash);         # special block with potentially manipulates times    
            # special way to set readings: use time of interval start as reading time
            Log3 $name, 5, "$name: readingStartTime$pin specified: setting timestamp to $fSdTim";
            my $chIdx  = 0;  
            $hash->{".updateTime"}      = $sTime;
            $hash->{".updateTimestamp"} = $fSTime;
            readingsBulkUpdate($hash, $rpname, $power) if ($time);
            $hash->{CHANGETIME}[$chIdx++] = $fSTime;                # Intervall start
            readingsEndUpdate($hash, 1);        # end of special block
            readingsBeginUpdate($hash);         # start regular update block
        } else {
            # normal way to set readings
            readingsBeginUpdate($hash);         # start regular update block
            readingsBulkUpdate($hash, $rpname, $power) if ($time);
        }
        
        
        if (defined($reject) && $reject ne "") {
            my $rejCount = ReadingsVal($name, "reject$pin", 0);     # alter reject count Wert
            readingsBulkUpdate($hash, "reject$pin", $reject + $rejCount);
        }
        readingsBulkUpdate($hash, "timeDiff$pin", $time);
        readingsBulkUpdate($hash, "countDiff$pin", $diff);              

        if (AttrVal($name, "verboseReadings$pin", 0)) {
            readingsBulkUpdate($hash, "lastMsg$pin", $line);
        }
        
        ArduCounter_HandleCounters($hash, $pin, $seq, $count, $time, $diff, $rDiff, $now);
        readingsEndUpdate($hash, 1);
                    
        if (!$hash->{Initialized}) {                    # device has sent count but not Started / hello after reconnect
            Log3 $name, 3, "$name: device is still counting";
            if (!$hash->{WaitForHello}) {               # if hello not already sent, send it now
                ArduCounter_AskForHello("direct:$name");
            }
            RemoveInternalTimer ("sendHello:$name");    # don't send hello again
        }
    }
}


#########################################################################
sub ArduCounter_Parse($)
{
    my ($hash) = @_;
    my $name   = $hash->{NAME};
    my $retStr = "";
    
    my @lines = split /\n/, $hash->{buffer};
    my $now   = gettimeofday();
    
    foreach my $line (@lines) {
        #Log3 $name, 5, "$name: Parse line: $line";
        if ($line =~ /^R([\d]+)/)
        {
            ArduCounter_ParseReport($hash, $line);
            
        } elsif ($line =~ /^H([\d+]) (.+)/) {               # pin pulse history as separate line
            my $pin  = $1;
            my $hist = $2;
            if (AttrVal($name, "verboseReadings$pin", 0)) {                    
                readingsBeginUpdate($hash);         
                readingsBulkUpdate($hash, "pinHistory$pin", $hist);
                readingsEndUpdate($hash, 1);
            }

        } elsif ($line =~ /^M Next report in ([\d]+)/) {    # end of report tells when next
            $retStr .= ($retStr ? "\n" : "") . $line;  
            Log3 $name, 4, "$name: device: $line";

        } elsif ($line =~ /^I(.*)/) {                       # interval config report after show/hello
            $hash->{runningCfg}{I} = $1;                    # save for later compare
            $hash->{runningCfg}{I} =~ s/\s+$//;             # remove spaces at end
            $retStr .= ($retStr ? "\n" : "") . $line;   

        } elsif ($line =~ /^P([\d]+) (falling|rising|-) ?(pullup)? ?min ([\d]+)/) {    # pin configuration at device
            $hash->{runningCfg}{$1} = "$2 $3 $4";           # save for later compare
            
            $retStr .= ($retStr ? "\n" : "") . $line;     
            Log3 $name, 4, "$name: device sent config for pin $1: $1 $2 min $3";
            
        } elsif ($line =~ /^alive/) {                       # alive response
            RemoveInternalTimer ("alive:$name");
            $hash->{WaitForAlive} = 0;
            delete $hash->{KeepAliveRetries};
            
        } elsif ($line =~ /^ArduCounter V([\d\.]+).*(Started|Hello)/) {  # setup message
            ArduCounter_ParseHello($hash, $line, $now);       

        } elsif ($line =~ /^Status: ArduCounter V([\d\.]+)/) {   # response to s(how)
            $retStr .= ($retStr ? "\n" : "") . $line;
            
        } elsif ($line =~ /connection already busy/) {
            my $now   = gettimeofday(); 
            my $delay = AttrVal($name, "nextOpenDelay", 60);  
            Log3 $name, 4, "$name: _Parse: primary tcp connection seems busy - delay next open";
            ArduCounter_Disconnected($hash);            # set to disconnected (state), remove timers
            DevIo_CloseDev($hash);                      # close, remove from readyfnlist so _ready is not called again
            RemoveInternalTimer ("delayedopen:$name");
            InternalTimer($now+$delay, "ArduCounter_DelayedOpen", "delayedopen:$name", 0);
            
        } elsif ($line =~ /^D (.*)/) {                  # debug / info Message from device
            $retStr .= ($retStr ? "\n" : "") . $line;
            Log3 $name, 4, "$name: device: $1";
            
        } elsif ($line =~ /^M (.*)/) {                  # other Message from device
            $retStr .= ($retStr ? "\n" : "") . $line;
            Log3 $name, 3, "$name: device: $1";
            
        } elsif ($line =~ /^[\s\n]*$/) {
            # blank line - ignore
        } else {
            Log3 $name, 3, "$name: unparseable message from device: $line";
        }
    }
    $hash->{buffer} = "";
    return $retStr;
}



#########################################################################
# called from the global loop, when the select for hash->{FD} reports data
sub ArduCounter_Read($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};
    my ($pin, $count, $diff, $power, $time, $reject, $msg);
    
    # read from serial device
    my $buf = DevIo_SimpleRead($hash);      
    return if (!defined($buf) );

    $hash->{buffer} .= $buf;    
    my $end = chop $buf;
    #Log3 $name, 5, "$name: Read: current buffer content: " . $hash->{buffer};

    # did we already get a full frame?
    return if ($end ne "\n");   
    ArduCounter_Parse($hash);
}



#####################################
# Called from get / set to get a direct answer
# called with logical device hash
sub ArduCounter_ReadAnswer($$)
{
    my ($hash, $expect) = @_;
    my $name   = $hash->{NAME};
    my $rin    = '';
    my $msgBuf = '';
    my $to     = AttrVal($name, "timeout", 2);
    my $buf;

    Log3 $name, 5, "$name: ReadAnswer called";  
    
    for(;;) {

        if($^O =~ m/Win/ && $hash->{USBDev}) {        
            $hash->{USBDev}->read_const_time($to*1000);   # set timeout (ms)
            $buf = $hash->{USBDev}->read(999);
            if(length($buf) == 0) {
                Log3 $name, 3, "$name: Timeout in ReadAnswer";
                return ("Timeout reading answer", undef)
            }
        } else {
            if(!$hash->{FD}) {
                Log3 $name, 3, "$name: Device lost in ReadAnswer";
                return ("Device lost when reading answer", undef);
            }

            vec($rin, $hash->{FD}, 1) = 1;    # setze entsprechendes Bit in rin
            my $nfound = select($rin, undef, undef, $to);
            if($nfound < 0) {
                next if ($! == EAGAIN() || $! == EINTR() || $! == 0);
                my $err = $!;
                ArduCounter_Disconnected($hash);                    # set to disconnected, remove timers, let _ready try to reopen
                Log3 $name, 3, "$name: ReadAnswer error: $err";
                return("ReadAnswer error: $err", undef);
            }
            if($nfound == 0) {
                Log3 $name, 3, "$name: Timeout2 in ReadAnswer";
                return ("Timeout reading answer", undef);
            }

            $buf = DevIo_SimpleRead($hash);
            if(!defined($buf)) {
                Log3 $name, 3, "$name: ReadAnswer got no data";
                return ("No data", undef);
            }
        }

        if($buf) {
            #Log3 $name, 5, "$name: ReadAnswer got: $buf";
            $hash->{buffer} .= $buf;
        }
        
        my $end = chop $buf;
        #Log3 $name, 5, "$name: Current buffer content: " . $hash->{buffer};
        next if ($end ne "\n"); 


        $msgBuf .= "\n" if ($msgBuf);
        $msgBuf .= ArduCounter_Parse($hash);
        
        #Log3 $name, 5, "$name: ReadAnswer msgBuf: " . $msgBuf;
        if ($msgBuf =~ $expect) {
            Log3 $name, 5, "$name: ReadAnswer matched $expect";
            return (undef, $msgBuf);
        }
    }
    return ("no Data", undef);
}



1;


=pod
=item device
=item summary Module for counters based on arduino / ESP8266 board
=item summary_DE Modul für Strom / Wasserzähler mit Arduino- oder ESP8266
=begin html

<a name="ArduCounter"></a>
<h3>ArduCounter</h3>

<ul>
    This module implements an Interface to an Arduino or ESP8266 based counter for pulses on any input pin of an Arduino Uno, Nano, Jeenode, NodeMCU, Wemos D1 or similar device. The device connects to Fhem either through USB / serial or via tcp if an ESP board is used.<br>
    The typical use case is an S0-Interface on an energy meter or water meter<br>
    Counters are configured with attributes that define which Arduino pins should count pulses and in which intervals the Arduino board should report the current counts.<br>
    The Arduino sketch that works with this module uses pin change interrupts so it can efficiently count pulses on all available input pins.<br>
    The module creates readings for pulse counts, consumption and optionally also a pulse history with pulse lengths and gaps of the last pulses.
    <br><br>
    <b>Prerequisites</b>
    <ul>
        <br>
        <li>
            This module requires an Arduino Uno, Nano, Jeenode, NodeMCU, Wemos D1 or similar device based on an Atmel 328p or ESP8266 running the ArduCounter sketch provided with this module<br>
            In order to flash an arduino board with the corresponding ArduCounter firmware from within Fhem, avrdude needs to be installed.
        </li>
    </ul>
    <br>

    <a name="ArduCounterdefine"></a>
    <b>Define</b>
    <ul>
        <br>
        <code>define &lt;name&gt; ArduCounter &lt;device&gt;</code><br>
        or<br>
        <code>define &lt;name&gt; ArduCounter &lt;ip:port&gt;</code><br>
        <br>
        &lt;device&gt; specifies the serial port to communicate with the Arduino.<br>
        &lt;ip:port&gt; specifies the ip address and tcp port to communicate with an esp8266 where port is typically 80.<br>
        
        The name of the serial-device depends on your distribution.
        You can also specify a baudrate for serial connections if the device name contains the @
        character, e.g.: /dev/ttyUSB0@38400<br>
        The default baudrate of the ArduCounter firmware is 38400 since Version 1.4
        <br>
        Example:<br>
        <br>
        <ul><code>define AC ArduCounter /dev/ttyUSB2@38400</code></ul>
        <ul><code>define AC ArduCounter 192.168.1.134:80</code></ul>
    </ul>
    <br>

    <a name="ArduCounterconfiguration"></a>
    <b>Configuration of ArduCounter counters</b><br><br>
    <ul>
        Specify the pins where impulses should be counted e.g. as <code>attr AC pinX falling pullup 30</code> <br>
        The X in pinX can be an Arduino / ESP pin number with or without the letter D e.g. pin4, pinD5, pin6, pinD7 ...<br>
        After the pin you can use the keywords falling or rising to define if a logical one / 5V (rising) or a logical zero / 0V (falling) should be treated as pulse.<br>
        The optional keyword pullup activates the pullup resistor for the given Pin. <br>
        The last argument is also optional but recommended and specifies a minimal pulse length in milliseconds.<br>
        An energy meter with S0 interface is typically connected to GND and an input pin like D4. <br>
        The S0 pulse then pulls the input to 0V.<br>
        Since the minimal pulse lenght of the s0 interface is specified to be 30ms, the typical configuration for an s0 interface is <br>
        <code>attr AC pinX falling pullup 30</code><br>
        Specifying a minimal pulse length is recommended since it filters bouncing of reed contacts or other noise.
        <br><br>
        Example:<br>
        <pre>
        define AC ArduCounter /dev/ttyUSB2
        attr AC factor 1000
        attr AC interval 60 300
        attr AC pinD4 falling pullup 5
        attr AC pinD5 falling pullup 30
        attr AC verboseReadings5
        attr AC pinD6 rising
        </pre>
        
        This defines three counters connected to the pins D4, D5 and D5. <br>
        D4 and D5 have their pullup resistors activated and the impulse draws the pins to zero.  <br>
        For D4 and D5 the arduino measures the time in milliseconds between the falling edge and the rising edge. If this time is longer than the specified 5 or 30 milliseconds 
        then the impulse is counted. If the time is shorter then this impulse is regarded as noise and added to a separate reject counter.<br>
        verboseReadings5 causes the module to create additional readings like the pulse history which shows length and gaps between the last pulses.<br>
        For pin D6 the arduino does not check pulse lengths and counts every time when the signal changes from 0 to 1.<br>
        The ArduCounter sketch which must be loaded on the Arduino implements this using pin change interrupts,
        so all avilable input pins can be used, not only the ones that support normal interrupts. <br>
        The module has been tested with 14 inputs of an Arduino Uno counting in parallel and pulses as short as 3 milliseconds.
    </ul>
    <br>

    <a name="ArduCounterset"></a>
    <b>Set-Commands</b><br>
    <ul>
        <li><b>raw</b></li> 
            send the value to the board so you can directly talk to the sketch using its commands.<br>
            This is not needed for normal operation but might be useful sometimes for debugging<br>
        <li><b>flash</b></li> 
            flashes the ArduCounter firmware ArduCounter.hex from the fhem subdirectory FHEM/firmware
            onto the device. This command needs avrdude to be installed. The attribute flashCommand specidies how avrdude is called. If it is not modifed then the module sets it to avrdude -p atmega328P -c arduino -P [PORT] -D -U flash:w:[HEXFILE] 2>[LOGFILE]<br>
            This setting should work for a standard installation and the placeholders are automatically replaced when 
            the command is used. So normally there is no need to modify this attribute.<br>
            Depending on your specific Arduino board however, you might need to insert <code>-b 57600</code> in the flash Command. (e.g. for an Arduino Nano)<br>
            <br>
            ESP boards so far have to be fashed from the Arduino IDE. In a future version flashing over the air sould be supported.
        <li><b>reset</b></li> 
            reopens the arduino device and sends a command to it which causes a reinitialize and reset of the counters. Then the module resends the attribute configuration / definition of the pins to the device.
        <li><b>saveConfig</b></li> 
            stores the current interval and pin configuration to be stored in the EEPROM of the counter device so it can be retrieved after a reset.
    </ul>
    <br>
    <a name="ArduCounterget"></a>
    <b>Get-Commands</b><br>
    <ul>
        <li><b>info</b></li> 
            send a command to the Arduino board to get current counts.<br>
            This is not needed for normal operation but might be useful sometimes for debugging<br>
    </ul>
    <br>
    <a name="ArduCounterattr"></a>
    <b>Attributes</b><br><br>
    <ul>
        <li><a href="#do_not_notify">do_not_notify</a></li>
        <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
        <br>
        <li><b>pin.*</b></li> 
            Define a pin of the Arduino or ESP board as input. This attribute expects either 
            <code>rising</code>, <code>falling</code> or <code>change</code>, followed by an optional <code>pullup</code> and an optional number as value.<br>
            If a number is specified, the arduino will track rising and falling edges of each impulse and measure the length of a pulse in milliseconds. The number specified here is the minimal length of a pulse and a pause before a pulse. If one is too small, the pulse is not counted but added to a separate reject counter.
        <li><b>interval</b> normal max min mincout</li> 
            Defines the parameters that affect the way counting and reporting works.
            This Attribute expects at least two and a maximum of four numbers as value. The first is the normal interval, the second the maximal interval, the third is a minimal interval and the fourth is a minimal pulse count.

            In the usual operation mode (when the normal interval is smaller than the maximum interval),
            the Arduino board just counts and remembers the time between the first impulse and the last impulse for each pin.<br>
            After the normal interval is elapsed the Arduino board reports the count and time for those pins where impulses were encountered.<br>
            This means that even though the normal interval might be 10 seconds, the reported time difference can be 
            something different because it observed impulses as starting and ending point.<br>
            The Power (e.g. for energy meters) is then calculated based of the counted impulses and the time between the first and the last impulse. <br>
            For the next interval, the starting time will be the time of the last impulse in the previous 
            reporting period and the time difference will be taken up to the last impulse before the reporting
            interval has elapsed.
            <br><br>
            The second, third and fourth numbers (maximum, minimal interval and minimal count) exist for the special case when the pulse frequency is very low and the reporting time is comparatively short.<br>
            For example if the normal interval (first number) is 60 seconds and the device counts only one impulse in 90 seconds, the the calculated power reading will jump up and down and will give ugly numbers.<br>
            By adjusting the other numbers of this attribute this can be avoided.<br>
            In case in the normal interval the observed impulses are encountered in a time difference that is smaller than the third number (minimal interval) or if the number of impulses counted is smaller than the fourth number (minimal count) then the reporting is delayed until the maximum interval has elapsed or the above conditions have changed after another normal interval.<br>
            This way the counter will report a higher number of pulses counted and a larger time difference back to fhem.
            <br><br>
            If this is seems too complicated and you prefer a simple and constant reporting interval, then you can set the normal interval and the mximum interval to the same number. This changes the operation mode of the counter to just count during this normal and maximum interval and report the count. In this case the reported time difference is always the reporting interval and not the measured time between the real impulses.
        <li><b>factor</b></li> 
            Define a multiplicator for calculating the power from the impulse count and the time between the first and the last impulse
            
        <li><b>readingNameCount[0-9]+</b></li> 
            Change the name of the counter reading pinX to something more meaningful.
        <li><b>readingNameLongCount[0-9]+</b></li> 
            Change the name of the long counter reading longX to something more meaningful.
            
        <li><b>readingNameInterpolatedCount[0-9]+</b></li> 
            Change the name of the interpolated long counter reading InterpolatedlongX to something more meaningful.
            
        <li><b>readingNamePower[0-9]+</b></li> 
            Change the name of the power reading powerX to something more meaningful.
        <li><b>readingFactor[0-9]+</b></li> 
            Override the factor attribute for this individual pin.
        <li><b>readingStartTime[0-9]+</b></li> 
            Allow the reading time stamp to be set to the beginning of measuring intervals. 
        <li><b>verboseReadings[0-9]+</b></li> 
            create readings timeDiff, countDiff and lastMsg for each pin <br>
        <li><b>flashCommand</b></li> 
            sets the command to call avrdude and flash the onnected arduino with an updated hex file (by default it looks for ArduCounter.hex in the FHEM/firmware subdirectory.<br>
            This attribute contains <code>avrdude -p atmega328P -c arduino -P [PORT] -D -U flash:w:[HEXFILE] 2>[LOGFILE]</code> by default.<br>
            For an Arduino Nano based counter you should add <code>-b 57600</code> e.g. between the -P and -D options.
            
        <li><b>keepAliveDelay</b></li> 
            defines an interval in which the module sends keepalive messages to a counter device that is conected via tcp.<br>
            This attribute is ignored if the device is connected via serial port.<br>
            If the device doesn't reply within a defined timeout then the module closes and tries to reopen the connection.<br>
            The module tells the device when to expect the next keepalive message and the device will also close the tcp connection if it doesn't see a keepalive message within the delay multiplied by 2.5<br>
            The delay defaults to 10 seconds.
        <li><b>keepAliveTimeout</b></li> 
            defines the timeout when wainting for a keealive reply (see keepAliveDelay)
            The timeout defaults to 2 seconds.
        <li><b>nextOpenDelay</b></li> 
            defines the time that the module waits before retrying to open a disconnected tcp connection. <br>
            This defaults to 60 seconds.
        <li><b>openTimeout</b></li> 
            defines the timeout after which tcp open gives up trying to establish a connection to the counter device.
            This timeout defaults to 3 seconds.
        <li><b>silentReconnect</b></li> 
            if set to 1, then it will set the loglevel for "disconnected" and "reappeared" messages to 4 instead of 3           
        <li><b>disable</b></li> 
            if set to 1 then the module closes the connection to a counter device.<br>
            
    </ul>
    <br>
    <b>Readings / Events</b><br>
    <ul>
        The module creates at least the following readings and events for each defined pin:
        <li><b>pin.*</b></li> 
            the current count at this pin
        <li><b>long.*</b></li>  
            long count which keeps on counting up after fhem restarts whereas the pin.* count is only a temporary internal count that starts at 0 when the arduino board starts.
        <li><b>interpolatedLong.*</b></li>  
            like long.* but when the Arduino restarts the potentially missed pulses are interpolated based on the pulse rate before the restart and after the restart.
        <li><b>reject.*</b></li>    
            counts rejected pulses that are shorter than the specified minimal pulse length. 
        <li><b>power.*</b></li> 
            the current calculated power at this pin
        <li><b>pinHistory.*</b></li> 
            shows detailed information of the last pulses. This is only available when a minimal pulse length is specified for this pin. Also the total number of impulses recorded here is limited to 20 for all pins together. The output looks like -36/7:0C, -29/7:1G, -22/8:0C, -14/7:1G, -7/7:0C, 0/7:1G<br>
            The first number is the relative time in milliseconds when the input level changed, followed by the length in milliseconds, the level and the internal action.<br>
            -36/7:0C for example means that 36 milliseconds before the reporting started, the input changed to 0V, stayed there for 7 milliseconds and this was counted.<br>
        <li><b>countDiff.*</b></li> 
            delta of the current count to the last reported one. This is used together with timeDiff.* to calculate the power consumption.
        <li><b>timeDiff.*</b></li> 
            time difference between the first pulse in the current observation interval and the last one. Used togehter with countDiff to calculate the power consumption.
        <li><b>seq.*</b></li> 
            internal sequence number of the last report from the board to fhem.
    </ul>           
    <br>
</ul>

=end html
=cut

