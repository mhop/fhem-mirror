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
#   2017-01-04  some more beautification in logging
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
#   2018-12-17  modifications to support analog ferraris counters with IR at analog input pin, some smaller bug fixes, 
#               new attribute pulsesPerKWh, analogThresholds
#               reading names now follow the definition of the pin (end on D4 instead of 4 if the pin was defined as pinD4 and not pin4)
#               attributes that modify a pin or its reading names also look for the pin name (like D4 instead of 4 or A7 instead of 21)
#   2019-01-12  fixed a small bug in logging
#   2019-01-18  better logging for disallowed pins
#   2019-01-29  changed handling of analog pins to better support future boards like ESP32
#   2019-02-14  fixed typo in attr definitions
#   2019-02-15  fixed bug in configureDevice
#
# ideas / todo:
#
#   - max time for interpolation as attribute
#
#   - convert module to package
#
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

my $ArduCounter_Version = '6.10 - 15.3.2019';


my %ArduCounter_sets = (  
    "disable"       =>  "",
    "enable"        =>  "",
    "raw"           =>  "",
    "reset"         =>  "",
    "flash"         =>  "",
    "saveConfig"    => "",
    "reconnect"     =>  ""  
);

my %ArduCounter_gets = (  
    "info"   =>  "",
    "levels" =>  ""
);

 
my %AnalogPinMap = (
    "NANO" => { 
        "A0" => 14,
        "A1" => 15,
        "A2" => 16,
        "A3" => 17,             
        "A4" => 18,
        "A5" => 19,
        "A6" => 20,
        "A7" => 21 },
    "ESP8266" => {
        "A0" => 17 }
);
my %rAnalogPinMap = (
    "NANO" => { 
        14   => "A0",
        15   => "A1",
        16   => "A2",
        17   => "A3",
        18   => "A4",
        19   => "A5",
        20   => "A6",
        21   => "A7" },
    "ESP8266" => {
        17   => "A0" }
);


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
        'board:UNO,NANO,ESP8266 ' .
        'pin[AD]?[0-9]+ ' .
        'interval ' .
        'factor ' .                                     # legacy (should be removed, use pulsesPerKwh instead)
        'pulsesPerKWh ' .       
        'devVerbose:0,5,10,20 ' .                       # verbose level of board
        'analogThresholds ' .
        'readingNameCount[AD]?[0-9]+ ' .                # raw count for this running period
        'readingNamePower[AD]?[0-9]+ ' .
        'readingNameLongCount[AD]?[0-9]+ ' .            # long term count
        'readingNameInterpolatedCount[AD]?[0-9]+ ' .    # long term count including interpolation for offline times
        'readingNameCalcCount[AD]?[0-9]+ ' .            # new to be implemented by using factor for the counter as well
        'readingFactor[AD]?[0-9]+ ' .
        'readingPulsesPerKWh[AD]?[0-9]+ ' .
        'readingStartTime[AD]?[0-9]+ ' .
        'verboseReadings[AD]?[0-9]+ ' .
        'flashCommand ' .
        'helloSendDelay ' .
        'helloWaitTime ' .        
        'configDelay ' .                                # how many seconds to wait before sending config after reboot of board
        'keepAliveDelay ' .
        'keepAliveTimeout ' .
        'nextOpenDelay ' .
        'silentReconnect:0,1 ' .
        'openTimeout ' .
        
        'disable:0,1 ' .
        'do_not_notify:1,0 ' . 
        $readingFnAttributes;
    
    # todo: create rAnalogPinMap hash from AnalogPinMap
    
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
    # do open in notify after init_done or after a new defined device (also after init_done)    
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


##########################################################################
# Open Device
# called from Notify after init_done or when a new device is defined later,
#   or from Ready as reopen, 
#      from attr when disable is removed / set to 0,
#      from set reconnect, reset or after flash,
#      from delayed_open when a tcp connection was closed with "already busy"
#
# normally an open also resets the counter board, unless its hardware is modified
# to continue when opened.
#
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
        Log3 $name, 5, "$name: ArduCounter_Open succeeded immediately" if (!$reopen);
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


#######################################################
# Aufruf aus InternalTimer 
# falls in Parse TCP Connection wieder abgewiesen wird 
# weil "already busy"
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
    # DEFINED is not triggered if init is not done.

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



###########################################################
# return the name of the caling function for debug output
sub ArduCounter_Caller() 
{
    my ($package, $filename, $line, $subroutine, $hasargs, $wantarray, $evaltext, $is_require, $hints, $bitmask, $hinthash) = caller 2;
    return $1 if ($subroutine =~ /main::ArduCounter_(.*)/);
    return $1 if ($subroutine =~ /main::(.*)/);
    return "$subroutine";
}


#######################################
# Aufruf aus InternalTimer
# send "h" to ask for "Hello" since device didn't say "Started" so far - maybe it's still counting ...
# called with timer from _openCB, _Ready and if count is read in _Parse but no hello was received
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
    
    my @runningPins = sort grep (/[\d]/, keys %{$hash->{runningCfg}});
    Log3 $name, 5, "$name: ConfigureDevice: pins in running config: @runningPins";
    my @attrPins = sort grep (/pin([dDaA])?[\d]/, keys %{$attr{$name}});
    Log3 $name, 5, "$name: ConfigureDevice: pins from attrs: @attrPins";
    
    CHECKS: {
        # first check if device did send its config, then compare and send config if necessary
        if (!$hash->{runningCfg}) {
            Log3 $name, 5, "$name: ConfigureDevice: no running config received";
            last CHECKS;
        }
        Log3 $name, 5, "$name: ConfigureDevice: got running config - comparing";
        
        my $iAttr = AttrVal($name, "interval", "");     
        if (!$iAttr) {
            $iAttr = "30 60 2 2";
            Log3 $name, 5, "$name: ConfigureDevice: interval attr not set - take default $iAttr";
        }
        if ($iAttr =~ /^(\d+) (\d+) ?(\d+)? ?(\d+)?$/) {
            my $iRCfg = ($hash->{runningCfg}{I} ? $hash->{runningCfg}{I} : "");
            my $iACfg = "$1 $2" . ($3 ? " $3" : " 0") . ($4 ? " $4" : " 0");
            Log3 $name, 5, "$name: ConfigureDevice: comparing intervals (>$iRCfg< vs >$iACfg< from attr)";
            if (!$iRCfg || $iRCfg ne $iACfg) {
                Log3 $name, 5, "$name: ConfigureDevice: intervals don't match (>$iRCfg< vs >$iACfg< from attr)";
                last CHECKS;
            }
        } else {
            Log3 $name, 3, "$name: ConfigureDevice: can not compare against interval attr - wrong format";         
        }
        
        my $tAttr = AttrVal($name, "analogThresholds", ""); 
        if (!$tAttr) {
            Log3 $name, 3, "$name: ConfigureDevice: no analogThresholds attribute";         
        } else {
            if ($tAttr =~ /^(\d+) (\d+)/) {
                my $tRCfg = ($hash->{runningCfg}{T} ? $hash->{runningCfg}{T} : "");
                my $tACfg = "$1 $2";
                Log3 $name, 5, "$name: ConfigureDevice: comparing analog Thresholds (>$tRCfg< vs >$tACfg< from attr)";
                if (!$tRCfg || ($tRCfg ne $tACfg)) {
                    Log3 $name, 5, "$name: ConfigureDevice: analog Thresholds don't match (>$tRCfg< vs >$tACfg< from attr)";
                    last CHECKS;
                }
            } else {
                Log3 $name, 3, "$name: ConfigureDevice: can not compare against analogThreshold attr - wrong format";         
            }
            
        }
        
        Log3 $name, 5, "$name: ConfigureDevice: matches so far - now compare pins";
        # interval config matches - now check pins as well
        if (@runningPins != @attrPins) {
            Log3 $name, 5, "$name: ConfigureDevice: number of defined pins doesn't match (@runningPins vs. @attrPins)";
            last CHECKS;
        }
        for (my $i = 0; $i < @attrPins; $i++) {
            Log3 $name, 5, "$name: ConfigureDevice: compare pin $attrPins[$i] to $runningPins[$i]";
            $attrPins[$i] =~ /pin([dDaA])?([\d+]+)/;
            my $type = $1;
            my $aPinNum = $2;                   # pin number from attr
            
            $aPinNum = ArduCounter_PinNumber($hash, $type.$aPinNum) if ($type eq 'A');
            if (!$aPinNum) {                    # should never happen, because board type is known and pin was allowed
                Log3 $name, 5, "$name: ConfigureDevice can not compare pin config for $attrPins[$i], internal pin number can not be determined";
                last CHECKS;
            }
            
            last CHECKS if (!$hash->{runningCfg}{$aPinNum});            
            Log3 $name, 5, "$name: ConfigureDevice: now compare $attr{$name}{$attrPins[$i]} to $hash->{runningCfg}{$aPinNum}";
            
            last CHECKS if ($attr{$name}{$attrPins[$i]} !~ /^(rising|falling) ?(pullup)? ?([0-9]+)?/);
            my $aEdge = $1;
            my $aPull = ($2 ? $2 : "nop");
            my $aMin  = ($3 ? $3 : "");
            last CHECKS if ($hash->{runningCfg}{$aPinNum} !~ /^(rising|falling|-) ?(pullup|nop)? ?([0-9]+)?/);
            my $cEdge = $1;
            my $cPull = ($2 ? $2 : "");
            my $cMin  = ($3 ? $3 : "");

            last CHECKS if ($aEdge ne $cEdge || $aPull ne $cPull || $aMin ne $cMin);
            
        }
        Log3 $name, 5, "$name: ConfigureDevice: running config matches attributes";
        return;
    }
    Log3 $name, 5, "$name: ConfigureDevice: now check for pins without attr in @runningPins";
    my %cPins;      # get all pins from running config in a hash to find out if one is not defined on fhem side
    for (my $i = 0; $i < @runningPins; $i++) {
        $cPins{$runningPins[$i]} = 1;
        #Log3 $name, 3, "$name: ConfigureDevice remember pin $runningPins[$i]";
    }
    # send attributes to arduino device. Just call ArduCounter_Attr again
    Log3 $name, 3, "$name: ConfigureDevice: no match -> send config";
    while (my ($aName, $val) = each(%{$attr{$name}})) {
        if ($aName =~ /^(interval|analogThresholds)/) {
            Log3 $name, 5, "$name: ConfigureDevice calls Attr with $aName $val";
            ArduCounter_Attr("set", $name, $aName, $val); 
        } elsif ($aName =~ /^pin([dDaA])?([\d+]+)/) {
            my $type = $1;
            my $num  = $2;
            my $aPinNum = $num;
            $aPinNum = ArduCounter_PinNumber($hash, "A$num") if ($type =~ /[aA]/);
            if ($aPinNum) {
                delete $cPins{$aPinNum};
                #Log3 $name, 5, "$name: ConfigureDevice ignore pin $aPinNum";
                Log3 $name, 5, "$name: ConfigureDevice calls Attr with $aName $val";
                ArduCounter_Attr("set", $name, $aName, $val); 
            } else {
                Log3 $name, 3, "$name: ConfigureDevice can not send pin config for $aName, internal pin number can not be determined";
            }
        }
    }
    if (%cPins) {
        my $pins = join ",", keys %cPins;
        Log3 $name, 5, "$name: ConfigureDevice: pins in running config without attribute in Fhem: $pins";
        foreach my $pin (keys %cPins) {
            Log3 $name, 5, "$name: ConfigureDevice: removing pin $pin";
            ArduCounter_Write($hash, "${pin}d");
        }
    } else {
        Log3 $name, 5, "$name: ConfigureDevice: no pins in running config without attribute in Fhem";
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
        if ($aName =~ /^pin([DA]?)(\d+)/) {
            if (!$hash->{Initialized}) {        # no hello received yet
                Log3 $name, 5, "$name: pin validation and communication postponed until device is initialized";
                return undef;                   # accept attribute but don't send it to the device yet.
            }
            # board did send hello already and therefore allowedPins and Board should be set ...
            my $pinType = $1;
            my $pin     = $2;
            if ($hash->{allowedPins}) {             # list of allowed pins received with hello
                my %pins = map { $_ => 1 } split (",", $hash->{allowedPins});
                if ($init_done && %pins && !$pins{$pin}) {
                    Log3 $name, 3, "$name: Invalid pin in attr $name $aName $aVal";
                    return "Invalid / disallowed pin specification $aName. The board reports $hash->{allowedPins} as allowed.";
                }
            }
            $pin = ArduCounter_PinNumber($hash, $pinType.$pin) if ($pinType eq 'A');
            if (!$pin) {
                # this should never happen since Board is known and Pin was already verified to be allowed.
                Log3 $name, 3, "$name: can not determine internal pin number for attr $name $aName $aVal";
                return "pin specification is not valid or something went wrong. Check the logs";
            }
            if ($aVal =~ /^(rising|falling) ?(pullup)? ?([0-9]+)?/) {
                my $opt = "";
                if ($1 eq 'rising')       {$opt = "3"}
                elsif ($1 eq 'falling')   {$opt = "2"}
                $opt .= ($2 ? ",1" : ",0");         # pullup
                $opt .= ($3 ? ",$3" : "");          # min length
                
                if ($hash->{Initialized}) {         # hello already received       
                    ArduCounter_Write($hash, "${pin},${opt}a");
                } else {
                    
                }
                  
            } else {
                Log3 $name, 3, "$name: Invalid value in attr $name $aName $aVal";
                return "Invalid Value $aVal";
            }
        } elsif ($aName =~ /^pin.*/) {
            Log3 $name, 3, "$name: Invalid pin specification in attr $name $aName $aVal. Use something like pinD4 or PinA7";
            return "Invalid pin specification in attr $name $aName $aVal. Use something like pinD4 or PinA7";
        
        } elsif ($aName eq "devVerbose") {
            if ($aVal =~ /^(\d+)\s*$/) {
                my $t = $1;
                if ($t > 100) {
                    Log3 $name, 3, "$name: Invalid value in attr $name $aName $aVal";
                    return "Invalid Value $aVal";
                }
                if ($hash->{Initialized}) {
                    ArduCounter_Write($hash, "${t}v");
                } else {
                    Log3 $name, 5, "$name: communication postponed until device is initialized";
                }
            } else {
                Log3 $name, 3, "$name: Invalid value in attr $name $aName $aVal";
                return "Invalid Value $aVal";
            }           
            
        } elsif ($aName eq "analogThresholds") {
            if ($aVal =~ /^(\d+) (\d+)\s*$/) {
                my $min = $1;
                my $max = $2;
                if ($min < 1 || $min > 1023 || $max < $min || $max > 1023) {
                    Log3 $name, 3, "$name: Invalid value in attr $name $aName $aVal";
                    return "Invalid Value $aVal";
                }
                if ($hash->{Initialized}) {
                    ArduCounter_Write($hash, "${min},${max}t");
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
            if ($aName !~ 'pin([aAdD]?\d+)') {
                Log3 $name, 3, "$name: Invalid pin name in attr $name $aName $aVal";
                return "Invalid pin name $aName";
            }
            my $pin = $1;
            # todo: convert to internal value with AnalogPinMap

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
        if ($arg =~ /^\d+$/) {
            Log3 $name, 4, "$name: set devVerbose $arg called";
            ArduCounter_Write($hash, "$arg"."v");
            delete $hash->{analogLevels} if ($arg eq "0");
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
        
    } elsif ($attr eq "levels") {
        my $msg = "";
        foreach my $level (sort {$a <=> $b} keys %{$hash->{analogLevels}}) {
            $msg .= "$level: $hash->{analogLevels}{$level}\n";
        }
        return "observed levels from analog input:\n$msg\n";
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
    
    if ($line =~ /^ArduCounter V([\d\.]+) on ([^\ ]+)( ?[^\ ]*) compiled (.*) Hello(, pins ([0-9\,]+) available)? ?(T([\d]+),([\d]+) B([\d]+),([\d]+))?/) {  # setup / hello message
        $hash->{VersionFirmware} = ($1 ? $1 : 'unknown');
        $hash->{Board}           = ($2 ? $2 : 'unknown');
        $hash->{BoardDet}        = ($3 ? $3 : '');
        $hash->{SketchCompile}   = ($4 ? $4 : 'unknown');
        $hash->{allowedPins}     = $6 if ($6);
        my $mNow   = ($8 ? $8 : 0);
        my $mNowW  = ($9 ? $9 : 0);
        my $mBoot  = ($10 ? $10 : 0);
        my $mBootW = ($11 ? $11 : 0);
        if ($hash->{VersionFirmware} < "2.36") {
            $hash->{VersionFirmware} .= " - not compatible with this Module version - please flash new sketch";
            Log3 $name, 3, "$name: device reported outdated Arducounter Firmware ($hash->{VersionFirmware}) - please update!";
            delete $hash->{Initialized};
        } else {
            Log3 $name, 3, "$name: device sent hello: $line";
            $hash->{Initialized} = 1;                   # now device has finished its boot and reported its version
            delete $hash->{runningCfg};
            
            my $cft = AttrVal($name, "configDelay", 1); # wait for device to send cfg before reconf.
            RemoveInternalTimer ("cmpCfg:$name");
            InternalTimer($now+$cft, "ArduCounter_ConfigureDevice", "cmpCfg:$name", 0);
            
            my $deviceNowSecs  = ($mNow/1000) + ((0xFFFFFFFF / 1000) * $mNowW);
            my $deviceBootSecs = ($mBoot/1000) + ((0xFFFFFFFF / 1000) * $mBootW);
            my $bootTime = $now - ($deviceNowSecs - $deviceBootSecs);
            $hash->{deviceBooted} = $bootTime;          # for estimation of missed pulses up to now
            
            my $boardAttr = AttrVal($name, 'board', '');
            if ($hash->{Board} && $boardAttr && ($hash->{Board} ne $boardAttr)) {
                Log3 $name, 3, "attribute board is set to $boardAttr and is overwriting board $hash->{Board} reported by device";
                $hash->{Board} = $boardAttr;
            }
            # now enrich $hash->{allowedPins} with $rAnalogPinMap{$hash->{Board}}{$pin}
            if ($hash->{allowedPins} && $hash->{Board}) {
                my $newAllowed;
                my $first = 1;
                foreach my $pin (split (",", $hash->{allowedPins})) {
                    $newAllowed .= ($first ? '' : ','); # separate by , if not empty anymore
                    $newAllowed .= $pin;
                    if ($rAnalogPinMap{$hash->{Board}}{$pin}) {
                        $newAllowed .= ",$rAnalogPinMap{$hash->{Board}}{$pin}";
                    }
                    $first = 0;                 
                }
                $hash->{allowedPins} = $newAllowed;
            }
        }
        delete $hash->{WaitForHello};
        RemoveInternalTimer ("hwait:$name");            # dont wait for hello reply if already sent
        RemoveInternalTimer ("sendHello:$name");        # Hello not needed anymore if not sent yet
    } else {
        Log3 $name, 4, "$name: probably wrong firmware version - cannot parse line $line";
    }
}


######################################
# $hash->{Board} wird in parseHello gesetzt und ggf. dort gleich durch das Attribut Board überschrieben
# called from Attr and ConfigureDevice.
# in all cases Board and AllowedPins have been received with hello before
sub ArduCounter_PinNumber($$)
{
    my ($hash, $pinName) = @_;
    my $name = $hash->{NAME};
    my $boardAttr = AttrVal($name, "board", "");
    my $board = ($boardAttr ? $boardAttr : $hash->{Board});
    my $pin;

    if (!$board) {                              # maybe no hello received yet and no Board-attr set (should never be the case)
        my @boardOptions = keys %AnalogPinMap;
        my $count = 0;
        foreach my $candidate (@boardOptions) {
            if ($AnalogPinMap{$candidate}{$pinName}) {
                $board = $AnalogPinMap{$candidate}{$pinName};
                $count++;
            }
        }
        if ($count > 1) {
            Log3 $name, 3, "$name: PinNumber called from " . ArduCounter_Caller() . " can not determine internal pin number for $pinName, board type is not known (yet) and attribute Board is also not set";
        } elsif (!$count) {
            Log3 $name, 3, "$name: PinNumber called from " . ArduCounter_Caller() . " can not determine internal pin number for $pinName. No known board seems to support it";
        }
    }
    $pin = $AnalogPinMap{$board}{$pinName} if ($board);
    if ($pin) {
        Log3 $name, 5, "$name: PinNumber called from " . ArduCounter_Caller() . " returns $pin for $pinName";
    } else {
        Log3 $name, 5, "$name: PinNumber called from " . ArduCounter_Caller() . " returns unknown for $pinName";
    }
    return $pin                                 # might be undef
}


######################################
sub ArduCounter_PinName($$)
{
    my ($hash, $pin) = @_;
    my $name = $hash->{NAME};
  
    my $pinName = $pin;                         # start assuming that attrs are set as pinX
    if (!AttrVal($name, "pin$pinName", 0)) {    # if not
        if (AttrVal($name, "pinD$pin", 0)) {
            $pinName = "D$pin";                 # maybe pinDX?
            #Log3 $name, 5, "$name: using attrs with pin name D$pin";
        } elsif ($hash->{Board}) {
            my $aPin = $rAnalogPinMap{$hash->{Board}}{$pin};
            if ($aPin) {                        # or pinAX?
                $pinName = "$aPin";
                #Log3 $name, 5, "$name: using attrs with pin name $pinName instead of $pin or D$pin (Board $hash->{Board})";
            }
        }
    }
    return $pinName;
}


sub AduCounter_AttrVal($$$;$$$)
{
    my ($hash, $default, $a1, $a2, $a3, $a4) = @_;
    my $name = $hash->{NAME};
    return AttrVal($name, $a1, undef) if (defined (AttrVal($name, $a1, undef)));
    return AttrVal($name, $a2, undef) if (defined ($a2) && defined (AttrVal($name, $a2, undef)));
    return AttrVal($name, $a3, undef) if (defined ($a3) && defined (AttrVal($name, $a3, undef)));
    return AttrVal($name, $a4, undef) if (defined ($a4) && defined (AttrVal($name, $a4, undef)));
    return $default;
}


######################################
sub ArduCounter_LogPinDesc($$)
{
    my ($hash, $pin) = @_;
    my $pinName = ArduCounter_PinName ($hash, $pin);
    return AduCounter_AttrVal($hash, "pin$pin", "readingNameCount$pinName", "readingNameCount$pin", "readingNamePower$pinName", "readingNamePower$pin");
}


#########################################################################
sub ArduCounter_HandleCounters($$$$$$$$)
{
    my ($hash, $pin, $seq, $count, $time, $diff, $rDiff, $now) = @_;
    my $name = $hash->{NAME};
    
    my $pinName   = ArduCounter_PinName ($hash, $pin);
    
    my $rcname    = AduCounter_AttrVal($hash, "pin$pinName", "readingNameCount$pinName", "readingNameCount$pin");
    my $rlname    = AduCounter_AttrVal($hash, "long$pinName", "readingNameLongCount$pinName", "readingNameLongCount$pin");
    my $riname    = AduCounter_AttrVal($hash, "interpolatedLong$pinName", "readingNameInterpolatedCount$pinName", "readingNameInterpolatedCount$pin");
    my $rccname   = AduCounter_AttrVal($hash, "calcCounter$pinName", "readingNameCalcCount$pinName", "readingNameCalcCount$pin");
    my $ppk       = AduCounter_AttrVal($hash, 0, "readingPulsesPerKWh$pin", "pulsesPerKWh");
    my $lName     = ArduCounter_LogPinDesc($hash, $pin);
    
    my $longCount = ReadingsVal($name, $rlname, 0);             # alter long count Wert
    my $intpCount = ReadingsVal($name, $riname, 0);             # alter interpolated count Wert
    my $lastCount = ReadingsVal($name, $rcname, 0);
    my $cCounter  = ReadingsVal($name, $rccname, 0);            # calculated counter 
    my $iSum      = ReadingsVal($name, $rccname . "_i", 0);     # interpolation sum 
    my $lastSeq   = ReadingsVal($name, "seq".$pinName, 0);
    my $intrCount = 0;                                          # interpolated count to be added
    
    my $lastCountTS   = ReadingsTimestamp ($name, $rlname, 0);  # last time long count reading was set as string
    my $lastCountTNum = time_str2num($lastCountTS);             # time as number
    my $fLastCTim     = FmtTime($lastCountTNum);                # formatted for logging
    my $pLog = "$name: pin $pinName ($lName)";                  # start of log lines
        
    my $fBootTim;
    my $deviceBooted;
    if ($hash->{deviceBooted} && $lastCountTS && $hash->{deviceBooted} > $lastCountTNum) {  
        $deviceBooted = 1;                                      # first report for this pin after a restart
        $fBootTim = FmtTime($hash->{deviceBooted}) ;            # time device booted 
    }                                                           # without old readings, interpolation makes no sense anyway
    
    my $countStart = $count - $rDiff;                           # count at start of this reported interval
    $countStart = 0 if ($countStart < 0);

    my $timeGap = ($now - $time/1000 - $lastCountTNum);         # time between last report and start of currently reported interval
    $timeGap = 0 if ($timeGap < 0 || !$lastCountTS);
    
    my $seqGap = $seq - ($lastSeq + 1);                         # gap of reporting sequences if any
    $seqGap = 0 if (!$lastCountTS);                             # readings didn't exist yet
    if ($seqGap < 0) {                                          # new sequence number is smaller than last 
        $seqGap %= 256;                                         # correct seq gap
        Log3 $name, 5, "$pLog sequence wrapped from $lastSeq to $seq, set seqGap to $seqGap" if (!$deviceBooted);
    }   
    
    my $pulseGap = $countStart - $lastCount;                    # gap of missed pulses if any
    $pulseGap = 0 if (!$lastCountTS);                           # readings didn't exist yet
    if ($pulseGap < 0) {                                        # pulseGap < 0 should not happen
        $pulseGap = 0;
        Log3 $name, 3, "$pLog seems to have missed $seqGap reports in $timeGap seconds. " .
            "Last reported sequence was $lastSeq, now $seq. " .
            "Device count before was $lastCount, now $count with rDiff $rDiff " .
            "but pulseGap is $pulseGap. this is probably wrong and should not happen" if (!$deviceBooted);
    } 

    if ($deviceBooted) {                                         # first report for this pin after a restart -> do interpolation 
        # interpolate for period between last report before boot and boot time. 
        Log3 $name, 5, "$pLog device restarted at $fBootTim, last reported at $fLastCTim, " .
            "count changed from $lastCount to $count, sequence from $lastSeq to $seq";
        $seqGap   = $seq - 1;                                   # $seq should be 1 after restart
        $pulseGap = $countStart;                                # we missed everything up to the count at start of the reported interval
        
        my $lastInterval  = ReadingsVal ($name, "timeDiff$pinName", 0);     # time diff of last interval (old reading)
        my $lastCDiff     = ReadingsVal ($name, "countDiff$pinName", 0);    # count diff of last interval (old reading)
        my $offlTime      = sprintf ("%.2f", $hash->{deviceBooted} - $lastCountTNum);   # estimated offline time (last report in readings until boot)
        
        if ($lastInterval && ($offlTime > 0) && ($offlTime < 12*60*60)) {       # offline > 0 and < 12h
            my $lastRatio = $lastCDiff / $lastInterval;
            my $curRatio  = $diff / $time;
            my $intRatio  = 1000 * ($lastRatio + $curRatio) / 2;            
            $intrCount = int(($offlTime * $intRatio)+0.5);
            Log3 $name, 3, "$pLog interpolating for $offlTime secs until boot, $intrCount estimated pulses (before $lastCDiff in $lastInterval ms, now $diff in $time ms, avg ratio $intRatio p/s)";
        } else {
            Log3 $name, 4, "$pLog interpolation of missed pulses for pin $pinName ($lName) not possible - no valid historic data.";
        }              
    }
 
    Log3 $name, 3, "$pLog missed $seqGap reports in $timeGap seconds. Last reported sequence was $lastSeq, " . 
        "now $seq. Device count before was $lastCount, now $count with rDiff $rDiff. " .
        "Adding $pulseGap to long count and intpolated count readings" if ($pulseGap > 0);
    Log3 $name, 5, "$pLog adding rDiff $rDiff to long count $longCount and interpolated count $intpCount";
    Log3 $name, 5, "$pLog adding interpolated $intrCount to interpolated count $intpCount" if ($intrCount);

    $intpCount += ($rDiff + $pulseGap + $intrCount);
    $longCount += ($rDiff + $pulseGap);
    if ($ppk) {
        $cCounter += ($rDiff + $pulseGap + $intrCount) / $ppk;  # add to calculated counter
        $iSum     += $intrCount / $ppk;                         # sum of interpolation kWh
    }
    
    readingsBulkUpdate($hash, $rcname, $count);                 # device internal counter
    readingsBulkUpdate($hash, $rlname, $longCount);             # Fhem long counterr
    readingsBulkUpdate($hash, $riname, $intpCount);             # Fhem interpolated counter
    if ($ppk) {
        readingsBulkUpdate($hash, $rccname, $cCounter);         # Fhem calculated / interpolated counter
        readingsBulkUpdate($hash, $rccname . "_i", $iSum);      # Fhem interpolation sum
    }
    readingsBulkUpdate($hash, "seq".$pinName, $seq);            # Sequence number
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
        my $pin     = $1;
        my $count   = $2;       # internal counter at device
        my $diff    = $3;       # delta during interval
        my $rDiff   = $4;       # real delta including the first pulse after a restart
        my $time    = $5;       # interval in ms
        my $deTime  = $6;
        my $deTiW   = $7;
        my $reject  = $8;
        my $seq     = ($9 ? substr($9, 2) : "");
        my $avgLen  = ($10 ? substr($10, 2) : "");      
        my $pinName = ArduCounter_PinName($hash, $pin);
        
        # now get pin specific reading names and options - first try with pinName, then pin Number, then generic fallback for all pins
        my $factor = AduCounter_AttrVal($hash, 1000, "readingFactor$pinName", "readingFactor$pin", "factor");
        my $ppk    = AduCounter_AttrVal($hash, 0, "readingPulsesPerKWh$pinName", "readingPulsesPerKWh$pin", "pulsesPerKWh");
        my $rpname = AduCounter_AttrVal($hash, "power$pinName", "readingNamePower$pinName", "readingNamePower$pin");
        my $lName  = ArduCounter_LogPinDesc($hash, $pin);
        my $pLog   = "$name: pin $pinName ($lName)";    # start of log lines
              
        my $sTime  = $now - $time/1000;                 # start of observation interval (~first pulse) in secs (floating point)
        my $fSTime = FmtDateTime($sTime);               # formatted
        my $fSdTim = FmtTime($sTime);                   # only time formatted for logging
        my $fEdTim = FmtTime($now);                     # end of Interval - only time formatted for logging

        ArduCounter_HandleDeviceTime($hash, $deTime, $deTiW, $now);
        
        if (!$time || !$factor) {
            Log3 $name, 3, "$pLog skip line because time or factor is 0: $line";
            return;
        }                                       
        
        my $power;      
        if ($ppk) {                                     # new calculation with pulsee or rounds per unit (kWh)
            $power = sprintf ("%.3f", ($time ? ($diff/$time) * (3600000 / $ppk) : 0));
        } else {                                        # old calculation with a factor that is hard to understand
            $power = sprintf ("%.3f", ($time ? $diff/$time/1000*3600*$factor : 0));
        }
        
        Log3 $name, 4, "$pLog Cnt $count " . 
            "(diff $diff/$rDiff) in " . sprintf("%.3f", $time/1000) . "s" .
            " from $fSdTim until $fEdTim, seq $seq" .
            ((defined($reject) && $reject ne "") ? ", Rej $reject" : "") .
            (defined($avgLen) ? ", Avg ${avgLen}ms" : "") .
            ", result $power";   
        
        if (AttrVal($name, "readingStartTime$pinName", AttrVal($name, "readingStartTime$pin", 0))) {
            readingsBeginUpdate($hash);                     # special block: use time of interval start as reading time
            Log3 $name, 5, "$pLog readingStartTime$pinName specified: setting timestamp to $fSdTim";
            my $chIdx  = 0;  
            $hash->{".updateTime"}      = $sTime;
            $hash->{".updateTimestamp"} = $fSTime;
            readingsBulkUpdate($hash, $rpname, $power) if ($time);
            $hash->{CHANGETIME}[$chIdx++] = $fSTime;        # Intervall start
            readingsEndUpdate($hash, 1);                    # end of special block
            readingsBeginUpdate($hash);                     # start regular update block
        } else {
            # normal way to set readings
            readingsBeginUpdate($hash);                     # start regular update block
            readingsBulkUpdate($hash, $rpname, $power) if ($time);
        }
        
        
        if (defined($reject) && $reject ne "") {
            my $rejCount = ReadingsVal($name, "reject$pinName", 0);     # alter reject count Wert
            readingsBulkUpdate($hash, "reject$pinName", $reject + $rejCount);
        }
        readingsBulkUpdate($hash, "timeDiff$pinName", $time);   # these readings are used internally for calculations
        readingsBulkUpdate($hash, "countDiff$pinName", $diff);  # these readings are used internally for calculations

        if (AttrVal($name, "verboseReadings$pinName", AttrVal($name, "verboseReadings$pin", 0))) {
            readingsBulkUpdate($hash, "lastMsg$pinName", $line);
        }
        
        ArduCounter_HandleCounters($hash, $pin, $seq, $count, $time, $diff, $rDiff, $now);
        readingsEndUpdate($hash, 1);
                    
        if (!$hash->{Initialized}) {                        # device has sent count but not Started / hello after reconnect
            Log3 $name, 3, "$name: device is still counting";
            if (!$hash->{WaitForHello}) {                   # if hello not already sent, send it now
                ArduCounter_AskForHello("direct:$name");
            }
            RemoveInternalTimer ("sendHello:$name");        # don't send hello again
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
        if ($line =~ /^R([\d]+)/) {
            ArduCounter_ParseReport($hash, $line);
            
        } elsif ($line =~ /^H([\d]+) (.+)/) {               # pin pulse history as separate line
            my $pin  = $1;
            my $hist = $2;
            my $pinName = ArduCounter_PinName($hash, $pin);
            if (AttrVal($name, "verboseReadings$pinName", AttrVal($name, "verboseReadings$pin", 0))) {                    
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
            Log3 $name, 4, "$name: device sent interval config $hash->{runningCfg}{I}";

        } elsif ($line =~ /^T(.*)/) {                       # analog threshold config report after show/hello
            $hash->{runningCfg}{T} = $1;                    # save for later compare
            $hash->{runningCfg}{T} =~ s/\s+$//;             # remove spaces at end
            $retStr .= ($retStr ? "\n" : "") . $line;   
            Log3 $name, 4, "$name: device sent analog threshold config $hash->{runningCfg}{T}";

        } elsif ($line =~ /^V(.*)/) {                       # devVerbose
            $hash->{runningCfg}{V} = $1;                    # save for later compare
            $hash->{runningCfg}{V} =~ s/\s+$//;             # remove spaces at end
            $retStr .= ($retStr ? "\n" : "") . $line;   
            
        } elsif ($line =~ /^P([\d]+) (falling|rising|-) ?(pullup)? ?min ([\d]+)/) {    # pin configuration at device
            my $p = ($3 ? $3 : "nop");
            $hash->{runningCfg}{$1} = "$2 $p $4";           # save for later compare            
            $retStr .= ($retStr ? "\n" : "") . $line;     
            Log3 $name, 4, "$name: device sent config for pin $1: $2 $p min $4";
            
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
            
        } elsif ($line =~ /^L([\d]+)/) {                # analog level difference reported
            if ($hash->{analogLevels}{$1}) {
                $hash->{analogLevels}{$1}++;
            } else {
                $hash->{analogLevels}{$1} = 1;
            }
            
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
    The typical use case is an S0-Interface on an energy meter or water meter, but also reflection light barriers to monitor old ferraris counters are supported<br>
    Counters are configured with attributes that define which Arduino pins should count pulses and in which intervals the Arduino board should report the current counts.<br>
    The Arduino sketch that works with this module uses pin change interrupts so it can efficiently count pulses on all available input pins.<br>
    The module creates readings for pulse counts, consumption and optionally also a pulse history with pulse lengths and gaps of the last pulses.
    <br><br>
    <b>Prerequisites</b>
    <ul>
        <br>
        <li>
            This module requires an Arduino Uno, Nano, Jeenode, NodeMCU, Wemos D1 or similar device based on an Atmel 328p or ESP8266 running the ArduCounter sketch provided with this module<br>
            In order to flash an arduino board with the corresponding ArduCounter firmware from within Fhem, avrdude needs to be installed.<br>
            For old ferraris counters an Arduino Uno or Nano or ESP8266 board needs to be connected to a reflection light barrier 
            which consists simply of an infra red photo transistor (connected to A7 on Arduinos and A0 on ESP8266) and an infra red led (connected to D2 on Arduinos and to D6 on ESP8266), both with a resistor in line.
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
    <b>Configuration of ArduCounter digital counters</b><br><br>
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
        attr AC pulsesPerKWh 1000
        attr AC interval 60 300
        attr AC pinD4 falling pullup 5
        attr AC pinD5 falling pullup 30
        attr AC verboseReadingsD5
        attr AC pinD6 rising
        </pre>        
        This defines three counters connected to the pins D4, D5 and D5. <br>
        D4 and D5 have their pullup resistors activated and the impulse draws the pins to zero.  <br>
        For D4 and D5 the arduino measures the time in milliseconds between the falling edge and the rising edge. If this time is longer than the specified 5 or 30 milliseconds then the impulse is counted. <br>
        If the time is shorter then this impulse is regarded as noise and added to a separate reject counter.<br>
        verboseReadings5 causes the module to create additional readings like the pulse history which shows length and gaps between the last pulses.<br>
        For pin D6 the arduino does not check pulse lengths and counts every time when the signal changes from 0 to 1.<br>
        The ArduCounter sketch which must be loaded on the Arduino or ESP implements this using pin change interrupts,
        so all avilable input pins can be used, not only the ones that support normal interrupts. <br>
        The module has been tested with 14 inputs of an Arduino Uno counting in parallel and pulses as short as 3 milliseconds.
    </ul>
    <br>
    
    <b>Configuration of ArduCounter analog counters</b><br><br>
    <ul>
        this module and the corresponding sketch can be used to read out old analog ferraris energy counters. Therefore for an Arduino Uno or Nano board (the ESP version does not yet support analog measurements) needs to be connected to a reflection light barrier which consists simply of an infra red photo transistor (connected to A7 on Arduinos and A0 on ESP8266) and an infra red led (connected to D2 on Arduinos and to D6 on ESP8266), both with a resistor in line. The idea comes from Martin Kompf (https://www.kompf.de/tech/emeir.html) and has been adopted for ArduCounter to support old ferraris energy counters.<br>
        To support this mode, the sketch has to be compiled with analogIR defined. <br>
        The configuration is then similar to the one for digital counters:<br>
        <pre>
        define ACF ArduCounter /dev/ttyUSB4
        attr ACF analogThresholds 100 110
        attr ACF flashCommand avrdude -p atmega328P -b57600 -c arduino -P [PORT] -D -U flash:w:[HEXFILE] 2>[LOGFILE]
        attr ACF interval 60 300 2 2
        attr ACF pinA7 rising 20
        attr ACF pulsesPerKWh 75
        attr ACF stateFormat {sprintf("%.3f kW", ReadingsVal($name,"powerA7",0))}
        </pre>
        To find out the right analog thresholds you can set devVerbose to 20 which will ask the firmware of your conting board to report every analog measurement. The ArduCounter module will count how often each value is reported and you can then query these analog level counts with <code>get levels</code>. After a few turns of the ferraris disc the result of <code>get levels</code> might look like this:<br>
        <pre>
            observed levels from analog input:
            94: 21
            95: 79
            96: 6
            97: 2
            98: 3
            99: 2
            100: 2
            101: 1
            102: 3
            105: 2
            106: 1
            108: 2
            109: 1
            110: 1
            112: 1
            113: 3
            115: 4
            116: 9
            117: 14
            118: 71
            119: 103
            120: 118
            121: 155
            122: 159
            123: 143
            124: 147
            125: 158
            126: 198
            127: 249
            128: 220
            129: 230
            130: 201
            131: 140
            132: 147
            133: 153
            134: 141
            135: 119
            136: 105
            137: 109
            138: 114
            139: 83
            140: 33
            141: 14
            142: 1      
        </pre>
        This shows the measured values together with the frequency how often the individual value has been measured. It is obvious that most measurements result in values between 120 and 135, very few values are betweem 96 and 115 and another peak is around the value 95. <br>
        It means that the when the red mark of the ferraris disc is under the sensor, the value is around 95 and while the blank disc is under the sensor, the value is typically between 120 and 135. So a good upper threshold would be 120 and a good lower threshold would be for example 96.
        
    </ul>
    <br>

    <a name="ArduCounterset"></a>
    <b>Set-Commands</b><br>
    <ul>
        <li><b>raw</b></li> 
            send the value to the board so you can directly talk to the sketch using its commands.<br>
            This is not needed for normal operation but might be useful sometimes for debugging
        <li><b>flash</b></li> 
            flashes the ArduCounter firmware ArduCounter.hex from the fhem subdirectory FHEM/firmware
            onto the device. This command needs avrdude to be installed. The attribute flashCommand specidies how avrdude is called. If it is not modifed then the module sets it to avrdude -p atmega328P -c arduino -P [PORT] -D -U flash:w:[HEXFILE] 2>[LOGFILE]<br>
            This setting should work for a standard installation and the placeholders are automatically replaced when 
            the command is used. So normally there is no need to modify this attribute.<br>
            Depending on your specific Arduino board however, you might need to insert <code>-b 57600</code> in the flash Command. (e.g. for an Arduino Nano)
            ESP boards so far have to be fashed from the Arduino IDE. In a future version flashing over the air sould be supported.
        <li><b>reset</b></li> 
            reopens the arduino device and sends a command to it which causes a reinitialize and reset of the counters. Then the module resends the attribute configuration / definition of the pins to the device.
        <li><b>saveConfig</b></li> 
            stores the current interval, analog threshold and pin configuration to be stored in the EEPROM of the counter device so it can be retrieved after a reset.
        <li><b>enable</b></li> 
            sets the attribute disable to 0
        <li><b>disable</b></li> 
            sets the attribute disable to 1
        <li><b>reconnect</b></li> 
            closes the tcp connection to an ESP based counter board that is conected via TCP/IP and reopen the connection
            
    </ul>
    <br>
    <a name="ArduCounterget"></a>
    <b>Get-Commands</b><br>
    <ul>
        <li><b>info</b></li> 
            send a command to the Arduino board to get current counts.<br>
            This is not needed for normal operation but might be useful sometimes for debugging
        <li><b>levels</b></li> 
            show the count for the measured levels if an analog pin is used to measure e.g. the red mark of a ferraris counter disc. This is useful for setting the thresholds for analog measurements.  
    </ul>
    <br>
    <a name="ArduCounterattr"></a>
    <b>Attributes</b><br><br>
    <ul>
        <li><a href="#do_not_notify">do_not_notify</a></li>
        <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
        <br>
        <li><b>pin[AD]?[0-9]+</b></li> 
            Define a pin of the Arduino or ESP board as input. This attribute expects either 
            <code>rising</code>, <code>falling</code> or <code>change</code>, followed by an optional <code>pullup</code> and an optional number as value.<br>
            If a number is specified, the arduino will track rising and falling edges of each impulse and measure the length of a pulse in milliseconds. The number specified here is the minimal length of a pulse and a pause before a pulse. If one is too small, the pulse is not counted but added to a separate reject counter.<br>
            Example:<br>
            <code>
            attr MyCounter pinD4 falling pullup 30
            </code>
            
        <li><b>interval</b> normal max min mincout</li> 
            Defines the parameters that affect the way counting and reporting works.
            This Attribute expects at least two and a maximum of four numbers as value. The first is the normal interval, the second the maximal interval, the third is a minimal interval and the fourth is a minimal pulse count.
            <br><br>
            In the usual operation mode (when the normal interval is smaller than the maximum interval),
            the Arduino board just counts and remembers the time between the first impulse and the last impulse for each pin.<br>
            After the normal interval is elapsed the Arduino board reports the count and time for those pins where impulses were encountered.<br>
            This means that even though the normal interval might be 10 seconds, the reported time difference can be 
            something different because it observed impulses as starting and ending point.<br>
            The Power (e.g. for energy meters) is then calculated based of the counted impulses and the time between the first and the last impulse. <br>
            For the next interval, the starting time will be the time of the last impulse in the previous reporting period and the time difference will be taken up to the last impulse before the reporting interval has elapsed.
            <br><br>
            The second, third and fourth numbers (maximum, minimal interval and minimal count) exist for the special case when the pulse frequency is very low and the reporting time is comparatively short.<br>
            For example if the normal interval (first number) is 60 seconds and the device counts only one impulse in 90 seconds, the the calculated power reading will jump up and down and will give ugly numbers.<br>
            By adjusting the other numbers of this attribute this can be avoided.<br>
            In case in the normal interval the observed impulses are encountered in a time difference that is smaller than the third number (minimal interval) or if the number of impulses counted is smaller than the fourth number (minimal count) then the reporting is delayed until the maximum interval has elapsed or the above conditions have changed after another normal interval.<br>
            This way the counter will report a higher number of pulses counted and a larger time difference back to fhem. <br>
            Example:<br>
            <code>
            attr myCounter interval 60 600 5 2
            </code><br>
            If this is seems too complicated and you prefer a simple and constant reporting interval, then you can set the normal interval and the mximum interval to the same number. This changes the operation mode of the counter to just count during this normal and maximum interval and report the count. In this case the reported time difference is always the reporting interval and not the measured time between the real impulses.
            
        <li><b>factor</b></li> 
            Define a multiplicator for calculating the power from the impulse count and the time between the first and the last impulse. <br>
            This attribute is outdated and unintuitive so you should avoid it. <br>
            Instead you should specify the attribute pulsesPerKWh or readingPulsesPerKWh[0-9]+ (where [0-9]+ stands for the pin number).

        <li><b>readingFactor[0-9]+</b></li> 
            Override the factor attribute for this individual pin. <br>
            Just like the attribute factor, this is a rather cumbersome way to specify the pulses per kWh. <br>
            Instaed it is advised to use the attribute pulsesPerKWh or readingPulsesPerKWh[0-9]+ (where [0-9]+ stands for the pin number).
            
        <li><b>pulsesPerKWh</b></li> 
            specify the number of pulses that the meter is giving out per unit that sould be displayed (e.g. per kWh energy consumed). For many S0 counters this is 1000, for old ferraris counters this is 75 (rounds per kWh).<br>
            Example:
            <code>
            attr myCounter pulsesPerKWh 75
            </code>
        <li><b>readingPulsesPerKWh[0-9]+</b></li> 
            is the same as pulsesPerKWh but specified per pin individually in case you have multiple counters with different settings at the same time
            <br>
            Example:<br>
            <code>
            attr myCounter readingPulsesPerKWhA7 75<br>
            attr myCounter readingPulsesPerKWhD4 1000
            </code>

        <li><b>readingNameCount[AD]?[0-9]+</b></li> 
            Change the name of the counter reading pinX to something more meaningful. <br>
            Example:
            <code>
            attr myCounter readingNameCountD4 CounterHaus_internal
            </code>
        <li><b>readingNameLongCount[AD]?[0-9]+</b></li> 
            Change the name of the long counter reading longX to something more meaningful.<br>
            Example:
            <code>
            attr myCounter readingNameLongCountD4 CounterHaus_long
            </code>
            
        <li><b>readingNameInterpolatedCount[AD]?[0-9]+</b></li> 
            Change the name of the interpolated long counter reading InterpolatedlongX to something more meaningful.<br>
            Example:
            <code>
            attr myCounter readingNameInterpolatedCountD4 CounterHaus_interpolated
            </code>
            
        <li><b>readingNameCalcCount[AD]?[0-9]+</b></li> 
            Change the name of the real unit counter reading CalcCounterX to something more meaningful.<br>
            Example:
            <code>
            attr myCounter readingNameCalcCountD4 CounterHaus_kWh
            </code>
            
        <li><b>readingNamePower[AD]?[0-9]+</b></li> 
            Change the name of the power reading powerX to something more meaningful.<br>
            Example:
            <code>
            attr myCounter readingNamePowerD4 PowerHaus
            </code>
            
        <li><b>readingStartTime[AD]?[0-9]+</b></li> 
            Allow the reading time stamp to be set to the beginning of measuring intervals. 
            
        <li><b>verboseReadings[AD]?[0-9]+</b></li> 
            create readings timeDiff, countDiff and lastMsg for each pin <br>
            Example:
            <code>
            attr myCounter verboseReadingsD4 1
            </code>
            
        <li><b>devVerbose</b></li> 
            set the verbose level in the counting board. This defaults to 0. <br>
            If the value is >0, then the firmware will echo all commands sent to it by the Fhem module. <br>
            If the value is >=5, then the firmware will report the pulse history (assuming that the firmware has been compiled with this feature enabled)<br>
            If the value is >=10, then the firmware will report every level change of a pin<br>
            If the value is >=20, then the firmware will report every analog measurement (assuming that the firmware has been compiled with analog measurements for old ferraris counters or similar).
            
        <li><b>analogThresholds</b></li> 
            this Attribute is necessary when you use an arduino nano with connected reflection light barrier (photo transistor and led) to detect the red mark of an old ferraris energy counter. In this case the firmware uses an upper and lower threshold which can be set here.<br>
            Example:
            <code>
            attr myCounter analogThresholds 90 110
            </code><br>
            In order to find out the right threshold values you can set devVerbose to 20, wait for several turns of the ferraris disc and then use <code>get levels</code> to see the typical measurements for the red mark and the blank disc.
        
        <li><b>flashCommand</b></li> 
            sets the command to call avrdude and flash the onnected arduino with an updated hex file (by default it looks for ArduCounter.hex in the FHEM/firmware subdirectory.<br>
            This attribute contains <code>avrdude -p atmega328P -c arduino -P [PORT] -D -U flash:w:[HEXFILE] 2>[LOGFILE]</code> by default.<br>
            For an Arduino Nano based counter you should add <code>-b 57600</code> e.g. between the -P and -D options.<br>
            Example:
            <code>
            attr myCounter flashCommand avrdude -p atmega328P -c arduino -b 57600 -P [PORT] -D -U flash:w:[HEXFILE] 2>[LOGFILE]
            </code>            
            
        <li><b>keepAliveDelay</b></li> 
            defines an interval in which the module sends keepalive messages to a counter device that is conected via tcp.<br>
            This attribute is ignored if the device is connected via serial port.<br>
            If the device doesn't reply within a defined timeout then the module closes and tries to reopen the connection.<br>
            The module tells the device when to expect the next keepalive message and the device will also close the tcp connection if it doesn't see a keepalive message within the delay multiplied by 2.5<br>
            The delay defaults to 10 seconds.<br>
            Example:
            <code>
            attr myCounter keepAliveDelay 30
            </code>            
            
        <li><b>keepAliveTimeout</b></li> 
            defines the timeout when wainting for a keealive reply (see keepAliveDelay)
            The timeout defaults to 2 seconds.<br>
            Example:
            <code>
            attr myCounter keepAliveTimeout 3
            </code>            
            
        <li><b>nextOpenDelay</b></li> 
            defines the time that the module waits before retrying to open a disconnected tcp connection. <br>
            This defaults to 60 seconds.<br>
            Example:
            <code>
            attr myCounter nextOpenDelay 20
            </code>            
            
        <li><b>openTimeout</b></li> 
            defines the timeout after which tcp open gives up trying to establish a connection to the counter device.
            This timeout defaults to 3 seconds.<br>
            Example:
            <code>
            attr myCounter openTimeout 5
            </code>            
            
        <li><b>silentReconnect</b></li> 
            if set to 1, then it will set the loglevel for "disconnected" and "reappeared" messages to 4 instead of 3<br>
            Example:
            <code>
            attr myCounter silentReconnect 1
            </code>            
        <li><b>disable</b></li> 
            if set to 1 then the module closes the connection to a counter device.<br>
            
    </ul>
    <br>
    <b>Readings / Events</b><br>
    <ul>
        The module creates at least the following readings and events for each defined pin:
        <li><b>pin.*</b> e.g. pinD4</li> 
            the current internal count at this pin (internal to the Arduino / ESP device, starts at 0 when the device restarts). <br>
            The name of this reading can be changed with the attribute readingNameCount[AD]?[0-9]+ where [AD]?[0-9]+ stands for the pin description e.g. D4
            
        <li><b>long.*</b> e.g. longD5</li>  
            long count which keeps on counting up after fhem restarts whereas the pin.* count is only a temporary internal count that starts at 0 when the arduino board starts.<br>
            The name of this reading can be changed with the attribute readingNameLongCount[AD]?[0-9]+ where [AD]?[0-9]+ stands for the pin description e.g. D4
            
        <li><b>interpolatedLong.*</b></li>  
            like long.* but when the Arduino restarts the potentially missed pulses are interpolated based on the pulse rate before the restart and after the restart.<br>
            The name of this reading can be changed with the attribute readingNameInterpolatedCount[AD]?[0-9]+ where [AD]?[0-9]+ stands for the pin description e.g. D4
            
        <li><b>reject.*</b></li>    
            counts rejected pulses that are shorter than the specified minimal pulse length. 
            
        <li><b>power.*</b></li> 
            the current calculated power at this pin. <br>
            The name of this reading can be changed with the attribute readingNamePower[AD]?[0-9]+ where [AD]?[0-9]+ stands for the pin description e.g. D4
            
        <li><b>calcCounter.*</b></li>  
            similar to long count which keeps on counting up after fhem restarts but this counter will take the pulses per kWh setting into the calculation und thus not count count pulses but real kWh (or some other unit that is applicable)<br>
            The name of this reading can be changed with the attribute readingNameCalcCount[AD]?[0-9]+ where [AD]?[0-9]+ stands for the pin description e.g. D4
            
        <li><b>pinHistory.*</b></li> 
            shows detailed information of the last pulses. This is only available when a minimal pulse length is specified for this pin. Also the total number of impulses recorded here is limited to 20 for all pins together. The output looks like -36/7:0C, -29/7:1G, -22/8:0C, -14/7:1G, -7/7:0C, 0/7:1G<br>
            The first number is the relative time in milliseconds when the input level changed, followed by the length in milliseconds, the level and the internal action.<br>
            -36/7:0C for example means that 36 milliseconds before the reporting started, the input changed to 0V, stayed there for 7 milliseconds and this was counted.<br>
            
        <li><b>countDiff.*</b></li> 
            delta of the current count to the last reported one. This is used together with timeDiff.* to calculate the power consumption.
            
        <li><b>timeDiff.*</b></li> 
            time difference between the first pulse in the current observation interval and the last one. Used togehter with countDiff to calculate the power consumption.
            
        <li><b>seq.*</b></li> 
            internal sequence number of the last report from the board to Fhem.
    </ul>           
    <br>
</ul>

=end html
=cut

