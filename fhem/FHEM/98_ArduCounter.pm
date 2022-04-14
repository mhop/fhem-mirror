#############################################################################
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
#
#
# ideas / todo:
#   - use DoClose / SetStates -> Utils?
#   - check integration of device none and write tests
#
#   - DevIo_IsOpen instead of checking fd
#   - "static" ports that do not count but report every change or an analog value to Fhem
#   - check reply from device after sending a command
#   - rename existing readings if new name is specified in attr
#   - max time for interpolation as attribute
#   - detect level thresholds automatically for analog input, track drift
#   - timeMissed
#

#
# My house water meter:
# 36.4? pulses per liter
#
# one big tap open = 9l / min -> 0,5 qm / h
# Max 5qm / h theoretical max load
# = 83l/min = 1,6 l / sec => 50 pulses / sec = 50 Hz freq.
# => minimal duration 20 ms, sampling at 5ms is fine
#

package ArduCounter;

use strict;
use warnings;
use GPUtils     qw(:all);
use Time::HiRes qw(gettimeofday time);    
use DevIo;
use FHEM::HTTPMOD::Utils  qw(:all);

use Exporter ('import');
our @EXPORT_OK = qw();
our %EXPORT_TAGS = (all => [@EXPORT_OK]);

BEGIN {
    GP_Import( qw(
        fhem
        CommandAttr
        CommandDeleteAttr
        addToDevAttrList
        AttrVal
        ReadingsVal
        ReadingsTimestamp
        readingsSingleUpdate
        readingsBeginUpdate
        readingsBulkUpdate
        readingsEndUpdate
        readingsDelete
        InternalVal
        makeReadingName
        Log3
        RemoveInternalTimer
        InternalTimer
        deviceEvents
        EvalSpecials
        AnalyzePerlCommand
        CheckRegexp
        IsDisabled
        devspec2array
        FmtTime
        gettimeofday
        FmtDateTime
        GetTimeSpec
        fhemTimeLocal
        time_str2num
        min
        max
        minNum
        maxNum
        abstime2rel
        defInfo
        trim
        ltrim
        rtrim
        UntoggleDirect
        UntoggleIndirect
        IsInt
        fhemNc
        round
        sortTopicNum
        Svn_GetFile
        WriteFile

        DevIo_OpenDev
        DevIo_SimpleWrite
        DevIo_SimpleRead
        DevIo_CloseDev
        DevIo_Disconnected
        SetExtensions
        HttpUtils_NonblockingGet

        featurelevel
        defs
        modules
        attr
        init_done
    ));

    GP_Export( qw(
        Initialize
    ));
};


my $Module_version = '8.00 - 21.10.2021';


my %SetHash = (  
    'disable'       =>  '',
    'enable'        =>  '',
    'raw'           =>  '',
    'reset'         =>  '',
    'resetWifi'     =>  '',
    'flash'         =>  '',
    'saveConfig'    =>  '',
    'clearLevels'   =>  '',
    'counter'       =>  '',
    'clearCounters' =>  '',
    'clearHistory'  =>  '',
    'reconnect'     =>  ''  
);


my %GetHash = (  
    'info'    =>  '',
    'history' =>  '',
    'levels'  =>  ''
);

 
my %AnalogPinMap = (
    'NANO' => { 
        'A0' => 14,
        'A1' => 15,
        'A2' => 16,
        'A3' => 17,             
        'A4' => 18,
        'A5' => 19,
        'A6' => 20,
        'A7' => 21 },
    'ESP8266' => {
        'A0' => 17 },
    'ESP32' => {
        'A0' => 36 },
    'T-Display' => {
        'A0' => 36 }
);
my %rAnalogPinMap;



#########################################################################
# FHEM module intitialisation
# defines the functions to be called from FHEM
sub Initialize {
    my $hash = shift;

    $hash->{ReadFn}   = \&ArduCounter::ReadFn;
    $hash->{ReadyFn}  = \&ArduCounter::ReadyFn;
    $hash->{DefFn}    = \&ArduCounter::DefineFn;
    $hash->{UndefFn}  = \&ArduCounter::UndefFn;
    $hash->{GetFn}    = \&ArduCounter::GetFn;
    $hash->{SetFn}    = \&ArduCounter::SetFn;
    $hash->{AttrFn}   = \&ArduCounter::AttrFn;
    $hash->{NotifyFn} = \&ArduCounter::NotifyFn;
    $hash->{AttrList} =
        'board:UNO,NANO,ESP8266,ESP32,T-Display ' .
        'pin[AD]?[0-9]+ ' .                             # configuration of pins -> sent to device
        'interval ' .                                   # configuration of intervals -> sent to device
        'factor ' .                                     # legacy (should be removed, use pulsesPerKwh instead)
        'pulsesPerKWh ' .                               # old
        'pulsesPerUnit ' .   
        'flowUnitTime ' .                               # time for which the flow / consumtion is calculated. Defaults to 3600 seconds (one hour)    

        'devVerbose:0,5,10,20,30,40,50 ' .              # old configuration of verbose level of board -> sent to device
        'enableHistory:0,1 ' .                          # history creation on device
        'enableSerialEcho:0,1,2 ' .                     # serial echo of output via TCP from device
        'enablePinDebug:0,1 ' .                         # show pin state changes from device
        'enableAnalogDebug:0,1,2,3 ' .                  # show analog levels
        'enableDevTime:0,1 ' .                          # device will send its time so drift can be detected

        'analogThresholds ' .                           # legacy (should be removed, add to pin attributes instead)
        'readingNameCount[AD]?[0-9]+ ' .                # raw count for this running period
        'readingNamePower[AD]?[0-9]+ ' .
        'readingNameLongCount[AD]?[0-9]+ ' .            # long term count
        'readingNameInterpolatedCount[AD]?[0-9]+ ' .    # long term count including interpolation for offline times
        'readingNameCalcCount[AD]?[0-9]+ ' .            # new to be implemented by using factor for the counter as well
        'readingFactor[AD]?[0-9]+ ' .
        'readingPulsesPerKWh[AD]?[0-9]+ ' .
        'readingPulsesPerUnit[AD]?[0-9]+ ' .
        'readingFlowUnitTime[AD]?[0-9]+ ' .             # time for which the flow / consumtion is calculated. Defaults to 3600 seconds (one hour)    
        'readingStartTime[AD]?[0-9]+ ' .
        'verboseReadings[AD]?[0-9]+ ' .
        'runTime[AD]?[0-9]+ ' .                         # keep runTime for this pin
        'runTimeIgnore[AD]?[0-9]+ ' .                   # ignore runTime for this pin while specified devices switched on
        'flashCommand ' .
        'helloSendDelay ' .
        'helloWaitTime ' .        
        'configDelay ' .                                # how many seconds to wait before sending config after reboot of board
        'keepAliveDelay ' .
        'keepAliveTimeout ' .
        'keepAliveRetries ' .
        'nextOpenDelay ' .
        'silentReconnect:0,1 ' .
        'openTimeout ' .
        'maxHist ' .
        'deviceDisplay ' .
        'logFilter ' .
        'disable:0,1 ' .
        'do_not_notify:1,0 ' . 
        $main::readingFnAttributes;

    # initialize rAnalogPinMap for each board and pin
    foreach my $board (keys %AnalogPinMap) {
        foreach my $pinName (keys %{$AnalogPinMap{$board}}) {
            my $pin = $AnalogPinMap{$board}{$pinName};
            $rAnalogPinMap{$board}{$pin} = $pinName;
            #Log3 undef, 3, "ArduCounter: initialize rAalogPinMap $board - $pin - $pinName";
        }
    }
    return;
}

 
##########################################################################
# Define command
sub DefineFn {
    my $hash = shift;                           # reference to the Fhem device hash 
    my $def  = shift;                           # definition string
    my @a    = split( /[ \t]+/, $def );         # the above string split at space or tab

    return 'wrong syntax: define <name> ArduCounter devicename@speed or ipAdr:port'
      if ( @a < 3 );

    DevIo_CloseDev($hash);
    my $name = $a[0];
    my $dev  = $a[2];
    
    if ($dev =~ m/^[Nn]one$/) {                         # none
        # for testing 
    } elsif ($dev =~ m/^(.+):([0-9]+)$/) {                   # tcp conection with explicit port
        $hash->{TCP} = 1;                               
    } 
    elsif ($dev =~ m/^(\d+\.\d+\.\d+\.\d+)(?:\:([0-9]+))?$/) { 
        $hash->{TCP} = 1;
        $dev .= ':80' if (!$2);                         # ip adr with optional port
    } 
    else {                                              # serial connection
        if ($dev !~ /.+@([0-9]+)/) {
            $dev .= '@115200';                          # add new default serial speed
        } else {
            Log3 $name, 3, "$name: Warning: connection speed $1 is not the default for the latest ArduCounter firmware"
                if ($1 != 115200);
        }
    }
    $hash->{DeviceName}    = $dev;
    $hash->{VersionModule} = $Module_version;
    $hash->{NOTIFYDEV}     = "global";                  # NotifyFn nur aufrufen wenn global events (INITIALIZED)
    $hash->{STATE}         = "disconnected";
    
    delete $hash->{Initialized};                        # device might not be initialized - wait for hello / setup before cmds
        
    Log3 $name, 3, "$name: defined with $dev, Module version $Module_version";
    # do open in notify after init_done or after a new defined device (also after init_done)    
    return;
}


#########################################################################
# undefine command when device is deleted
sub UndefFn {                     
    my $hash = shift;       
    DevIo_CloseDev($hash);   
    return;          
}    


#####################################################
# remove timers, call DevIo_Disconnected 
# to set state and add to readyFnList
sub SetDisconnected {
    my $hash = shift;
    my $name = $hash->{NAME};
  
    RemoveInternalTimer ("alive:$name");            # no timeout if waiting for keepalive response
    RemoveInternalTimer ("keepAlive:$name");        # don't send keepalive messages anymore
    RemoveInternalTimer ("sendHello:$name");
    DevIo_Disconnected($hash);                      # close, add to readyFnList so _Ready is called to reopen
    return;
}


#####################################################
# open callback
sub OpenCallback {
    my $hash = shift;
    my $msg  = shift;
    my $name = $hash->{NAME};
    my $now  = gettimeofday();
    if ($msg) {
        Log3 $name, 5, "$name: Open callback: $msg" if ($msg);
    }
    delete $hash->{BUSY_OPENDEV};
    if ($hash->{FD}) {  
        Log3 $name, 5, "$name: DoOpen succeeded in callback";
        my $hdl = AttrVal($name, "helloSendDelay", 4);
        # send hello if device doesn't say "Started" withing $hdl seconds
        RemoveInternalTimer ("sendHello:$name");
        InternalTimer($now+$hdl, "ArduCounter::AskForHello", "sendHello:$name", 0);    
        
        if ($hash->{TCP}) {
            # send first keepalive immediately to turn on tcp mode in device
            KeepAlive("keepAlive:$name");   
        }
    } 
    else {      # no file descriptor after open
        #Log3 $name, 5, "$name: DoOpen failed - open callback called from DevIO without FD";
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
sub DoOpen {
    my $hash   = shift;
    my $reopen = shift // 0;
    my $name   = $hash->{NAME};
    my $now    = gettimeofday();
    my $caller = FhemCaller();

    if ($hash->{DeviceName} eq 'none') {
        Log3 $name, 5, "$name: open called from $caller, device is defined with none" if ($caller ne 'Ready'); 
        SetStates($hash, 'opened');
        return;
    } 
    
    if ($hash->{BUSY_OPENDEV}) {    # still waiting for callback to last open 
        if ($hash->{LASTOPEN} && $now > $hash->{LASTOPEN} + (AttrVal($name, "openTimeout", 3) * 2)
                              && $now > $hash->{LASTOPEN} + 15) {
            Log3 $name, 5, "$name: _Open - still waiting for open callback, timeout is over twice - this should never happen";
            Log3 $name, 5, "$name: _Open - stop waiting and reset the flag.";
            $hash->{BUSY_OPENDEV} = 0;
        } 
        else {                      # no timeout yet
            Log3 $name, 5, "$name: _Open - still waiting for open callback";
            return;
        }
    }    
    
    if (!$reopen) {                 # not called from _Ready
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

    DevIo_OpenDev($hash, $reopen, 0, \&OpenCallback);
    delete $hash->{TIMEOUT};    
    if ($hash->{FD}) {  
        Log3 $name, 5, "$name: DoOpen succeeded immediately" if (!$reopen);
    } else {
        Log3 $name, 5, "$name: DoOpen waiting for callback" if (!$reopen);
    }
    return;
}



##################################################
# close connection 
# $hash is physical or both (connection over TCP)
sub DoClose {
    my ($hash, $noState, $noDelete) = @_;
    my $name = $hash->{NAME};
       
    Log3 $name, 5, "$name: Close called from " . FhemCaller() . 
        ($noState || $noDelete ? ' with ' : '') . ($noState ? 'noState' : '') .     # set state?
        ($noState && $noDelete ? ' and ' : '') . ($noDelete ? 'noDelete' : '');     # command delete on connection device?
    
    delete $hash->{LASTOPEN};                           # reset so next open will actually call OpenDev
    if ($hash->{DeviceName} eq 'none') {
        Log3 $name, 4, "$name: Simulate closing connection to none";
    } 
    else {
        Log3 $name, 4, "$name: Close connection with DevIo_CloseDev";
        # close even if it was not open yet but on ready list (need to remove entry from readylist)
        DevIo_CloseDev($hash);
    }
    SetStates($hash, 'disconnected') if (!$noState);
    return;
}
    

#################################################################
# set state Reading and STATE internal 
# call instead of setting STATE directly and when inactive / disconnected
sub SetStates {
    my $hash     = shift;
    my $state    = shift;
    my $name     = $hash->{NAME};
    my $newState = $state;

    Log3 $name, 5, "$name: SetState called from " . FhemCaller() . " with $state sets state and STATE to $newState";
    $hash->{STATE} = $newState;
    return if ($newState eq ReadingsVal($name, 'state', ''));
    readingsSingleUpdate($hash, 'state', $newState, 1);
    return;
}



#########################################################################
sub ReadyFn {
    my $hash = shift;
    my $name = $hash->{NAME};
    
    if($hash->{STATE} eq "disconnected") {  
        RemoveInternalTimer ("alive:$name");        # no timeout if waiting for keepalive response
        RemoveInternalTimer ("keepAlive:$name");    # don't send keepalive messages anymore
        delete $hash->{Initialized};                # when reconnecting wait for setup / hello before further action
        if (IsDisabled($name)) {
            Log3 $name, 3, "$name: _Ready: $name is disabled - don't try to reconnect";
            DevIo_CloseDev($hash);                  # close, remove from readyfnlist so _ready is not called again         
            return;
        }
        DoOpen($hash, 1);                 # reopen, don't call DevIoClose before reopening
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
# called from InternalTimer 
# if TCP connection is busy or after firmware flash
sub DelayedOpen {
    my $param = shift;
    my (undef,$name) = split(/:/,$param);
    my $hash = $defs{$name};
    
    Log3 $name, 4, "$name: try to reopen connection after delay";
    RemoveInternalTimer ("delayedopen:$name");
    delete $hash->{DevIoJustClosed};    # otherwise open returns without doing anything this time and we are not on the readyFnList ...
    DoOpen($hash, 1);         # reopen
    return;
}


########################################################
# Notify for INITIALIZED or Modified 
# -> Open connection to device
sub NotifyFn {
    my ($hash, $source) = @_;
    return if($source->{NAME} ne "global");

    my $events = deviceEvents($source, 1);
    return if(!$events);

    my $name = $hash->{NAME};
    # Log3 $name, 5, "$name: Notify called for source $source->{NAME} with events: @{$events}";
  
    return if (!grep {m/^INITIALIZED|REREADCFG|(MODIFIED $name)$|(DEFINED $name)$/}  @{$events});
    # DEFINED is not triggered if init is not done.

    if (IsDisabled($name)) {
        Log3 $name, 3, "$name: Notify / Init: device is disabled";
        return;
    }   

    Log3 $name, 3, "$name: Notify called with events: @{$events}, " .
        "open device and set timer to send hello to device";
    DoOpen($hash);  
    return;  
}


######################################
# wrapper for DevIo write
sub DoWrite {
    my $hash = shift;
    my $line = shift;
    my $name = $hash->{NAME};
    if (!IsOpen($hash)) {
        Log3 $name, 5, "$name: Write: device is disconnected, dropping line to write";
        return 0;
    } 
    if (IsDisabled($name)) {
        Log3 $name, 5, "$name: Write called but device is disabled, dropping line to send";
        return 0;
    }   
    #Log3 $name, 5, "$name: Write: $line";  # devio will already log the write
    #DevIo_SimpleWrite($hash, "\n", 2);
    if ($hash->{DeviceName} eq 'none') {
        Log3 $name, 4, "$name: Simulate sending to none: $line";
    } else {
        DevIo_SimpleWrite($hash, "$line.", 2);
    }
    return 1;
}


########################################################################################
# return the internal pin number for an analog pin name name like A1
# $hash->{Board} is set in parseHello and potentially overwritten by Attribut board
# called from Attr and ConfigureDevice to translate analog pin specifications to numbers
# in all cases Board and AllowedPins have been received with hello before
sub InternalPinNumber {
    my $hash    = shift;
    my $pinName = shift;
    my $name    = $hash->{NAME};
    my $board   = $hash->{Board};
    my $pin;

    if (!$board) {                  # if board is not known, try to guess it
        # maybe no hello received yet and no Board-attr set (should never be the case)
        my @boardOptions = keys %AnalogPinMap;
        my $count = 0;
        foreach my $candidate (@boardOptions) {
            if ($AnalogPinMap{$candidate}{$pinName}) {
                $board = $candidate;
                $count++;
            }
        }
        if ($count > 1) {
            Log3 $name, 3, "$name: PinNumber called from " . FhemCaller() . 
                " can not determine internal pin number for $pinName," .
                " board type is not known (yet) and attribute Board is also not set";
        } 
        elsif (!$count) {
            Log3 $name, 3, "$name: PinNumber called from " . FhemCaller() . 
                " can not determine internal pin number for $pinName." .
                " No known board seems to support it";
        } 
        else {
            Log3 $name, 3, "$name: PinNumber called from " . FhemCaller() . 
                " does not know what kind of board is used. " .
                " Guessing $board ...";
        }
    }
    $pin = $AnalogPinMap{$board}{$pinName} if ($board);
    if ($pin) {
        Log3 $name, 5, "$name: PinNumber called from " . FhemCaller() . 
            " returns $pin for $pinName";
    } 
    else {
        Log3 $name, 5, "$name: PinNumber called from " . FhemCaller() . 
            " returns unknown for $pinName";
    }
    return $pin                                 # might be undef
}


######################################################
# return the the pin as it is used in a pin attr
# e.g. D2 or A1 for a passed pin number
sub PinName {
    my $hash = shift;
    my $pin  = shift;
    my $name = $hash->{NAME};
  
    my $pinName = $pin;                         # start assuming that attrs are set as pinX
    if (!AttrVal($name, "pin$pinName", 0)) {    # if not
        if (AttrVal($name, "pinD$pin", 0)) {    # is the pin defined as pinDX?
            $pinName = "D$pin";
            #Log3 $name, 5, "$name: using attrs with pin name D$pin";
        } 
        elsif ($hash->{Board}) {
            my $aPin = $rAnalogPinMap{$hash->{Board}}{$pin};
            if ($aPin) {                        # or pinAX?
                $pinName = "$aPin";
                #Log3 $name, 5, "$name: using attrs with pin name $pinName instead of $pin or D$pin (Board $hash->{Board})";
            }
        }
    }
    return $pinName;
}


#####################################################
# return the first attr in the list that is defined
sub AttrValFromList {
    my ($hash, $default, $a1, $a2, $a3, $a4) = @_;
    my $name = $hash->{NAME};
    return AttrVal($name, $a1, undef) if (defined (AttrVal($name, $a1, undef)));
    #Log3 $name, 5, "$name: AAV (" . FhemCaller() . ") $a1 not there";
    return AttrVal($name, $a2, undef) if (defined ($a2) && defined (AttrVal($name, $a2, undef)));
    #Log3 $name, 5, "$name: AAV (" . FhemCaller() . ") $a2 not there";
    return AttrVal($name, $a3, undef) if (defined ($a3) && defined (AttrVal($name, $a3, undef)));
    #Log3 $name, 5, "$name: AAV (" . FhemCaller() . ") $a3 not there";
    return AttrVal($name, $a4, undef) if (defined ($a4) && defined (AttrVal($name, $a4, undef)));
    #Log3 $name, 5, "$name: AAV (" . FhemCaller() . ") $a4 not there";
    return $default;
}


######################################################
# return a meaningful name (the relevant reading name) 
# for passed pin number
# called from functions that handle device output with pin number
sub LogPinDesc {
    my $hash = shift;
    my $pin  = shift;
    my $pinName = PinName ($hash, $pin);
    return AttrValFromList($hash, "pin$pin", "readingNameCount$pinName", "readingNameCount$pin", "readingNamePower$pinName", "readingNamePower$pin");
}


######################################################
# send 'a' command to the device to configure a pin
# called from attr (pin attribute) and configureDevice
# with a pinName
sub ConfigurePin {
    my ($hash, $pinArg, $aVal) = @_;
    my $name = $hash->{NAME};
    my $opt;

    if ($aVal !~ /^(rising|falling)[ \,\;]*(pullup)?[ \,\;]*(min +)?(\d+)?(?:[ \,\;]*(?:analog )out *(\d+)(?:[ \,\;]*threshold *(\d+)[ \,\;]+(\d+)))?/) {
        Log3 $name, 3, "$name: ConfigurePin got invalid config for $pinArg: $aVal";
        return "Invalid config for pin $pinArg: $aVal";
    }
    my ($edge, $pullup, $minText, $min, $aout, $t1, $t2) = ($1, $2, $3, $4, $5, $6, $7);
    if (!$hash->{Initialized}) {                        # no hello received yet
        Log3 $name, 5, "$name: pin validation and communication postponed until device is initialized";
        return;                                   # accept value but don't send it to the device yet.
    }
    my ($pin, $pinName) = ParsePin($hash, $pinArg);
    return "illegal pin $pinArg" if (!defined($pin));   # parsePin logs error if wrong pin spec

    if ($edge eq 'rising')       {$opt = "3"}           # pulse level rising or falling
    elsif ($edge eq 'falling')   {$opt = "2"}
    $opt .= ($pullup ? ",1" : ",0");                    # pullup
    $opt .= ($min ? ",$min" : ",2");                    # min length, default is 2
    if ($hash->{VersionFirmware} && $hash->{VersionFirmware} > "4.00") {
        if (defined($aout)) { $opt .= ",$aout" }        # analog out pin
        if (defined($t2))   { $opt .= ",$t1,$t2" }      # analog thresholds
    } 
    else {
        Log3 $name, 3, "$name: ConfigurePin sends old syntax to outdated firmware ($hash->{VersionFirmware})";    
    }                  

    Log3 $name, 5, "$name: ConfigurePin creates command ${pin},${opt}a";
    DoWrite($hash, "${pin},${opt}a");         # initialized is already checked above
    return;
}


######################################################
# send 'i' command to the device to configure a pin
sub ConfigureIntervals {
    my $hash = shift;
    my $aVal = shift;
    my $name = $hash->{NAME};
    my $cmd;

    if (!defined($aVal)) {
        $aVal = AttrVal($name, "interval", "");
        if (!$aVal) {
            Log3 $name, 4, "$name: attr interval not set";
            return;
        }
    }
    if ($aVal !~ /^(\d+)[\s\,](\d+)[\s\,]?(\d+)?[\s\,]?(\d+)?([\s\,](\d+)[\s\,]+(\d+))?/) {
        Log3 $name, 3, "$name: Invalid interval specification $aVal";
        return "Invalid interval specification $aVal";
    }           
    my ($min, $max, $sml, $cnt, $ain, $asm) = ($1, $2, $3, $4, $5, $6, $7);
    if ($min < 1 || $min > 3600 || $max < $min || $max > 3600) {
        Log3 $name, 3, "$name: Invalid value in interval specification $aVal";
        return "Invalid Value $aVal";
    }
    if (!$hash->{Initialized}) {
        Log3 $name, 5, "$name: communication postponed until device is initialized";
        return;
    }
    $sml = 0 if (!$sml);
    $cnt = 0 if (!$cnt);
    $ain = 50 if (!$ain);
    $asm = 4  if (!$asm);

    if ($hash->{VersionFirmware} && $hash->{VersionFirmware} > "4.00") {
        $cmd = "${min},${max},${sml},${cnt},${ain},${asm}i";
    } 
    else {      # old firmware
        $cmd = "${min},${max},${sml},${cnt}i";
    }
    Log3 $name, 5, "$name: ConfigureIntervals creates command $cmd";
    DoWrite($hash, $cmd);
    return;
}


######################################################
# send 'a' command to the device to configure a pin
sub ConfigureVerboseLevels {
    my ($hash, $eHist, $eSerial, $pinDebug, $aDebug, $eTime) = @_;
    my $name = $hash->{NAME};
    my $err;
    if (defined($eHist)) {
        if ($eHist !~ /^[01]$/) {
            $err = "illegal value for enableHistory: $eHist, only 0 and 1 allowed";
        }
    } 
    else {
        $eHist = AttrVal($name, "enableHistory", 0);
    }
    if (defined($eSerial)) {
        if ($eSerial !~ /^[012]$/) {
            $err = "illegal value enableSerialEcho: $eSerial, only 0,1 and 2 allowed";
        }
    } 
    else {
        $eSerial = AttrVal($name, "enableSerialEcho", 0);
    }
    if (defined($pinDebug)) {
        if ($pinDebug !~ /^[01]$/) {
            $err = "illegal value enablePinDebug: $pinDebug, only 0 and 1 allowed";
        }
    } 
    else {
        $pinDebug = AttrVal($name, "enablePinDebug", 0);
    }
    if (defined($aDebug)) {
        if ($aDebug !~ /^[0123]$/) {
            $err = "illegal value enable AnalogDebug: $aDebug, only 0-3 allowed";
        }
    } 
    else {
        $aDebug = AttrVal($name, "enableAnalogDebug", 0);
    }
    if (defined($eTime)) {
        if ($eTime !~ /^[01]$/) {
            $err = "illegal value enableDevTime: $eTime, only 0 and 1 allowed";
        }
    } 
    else {
        $eTime = AttrVal($name, "enableDevTime", 0);
    }
    if ($err) {
        Log3 $name, 3, "$name: $err";
        return $err;
    }
    if (!$hash->{Initialized}) {        # no hello received yet
        Log3 $name, 5, "$name: pin validation and communication postponed until device is initialized";
        return;                   # accept value but don't send it to the device yet.
    }

    my $cmd = "${eHist},${eSerial},${pinDebug},${aDebug},${eTime}v";
    Log3 $name, 5, "$name: ConfigureVerboseLevels creates command $cmd";
    DoWrite($hash, $cmd);
    return;
}


######################################################
# encode string as int sequence 
# used in communication with device
sub IntString {
    my ($inStr) = @_;
    my $byteNum = 0;
    my $val = 0;
    my $outStr;
    foreach my $char (split (//, $inStr)) {
        if ($byteNum) {
            $val = ord($char) * 256 + $val;         # second char -> add as high byte
            $outStr .= ",$val";
            $byteNum = 0;
        } 
        else {
            $val = ord($char);                      # first char
            $byteNum++;
        }
    }
    if ($byteNum) {                                 # low order byte has been set, high byte is still zero
        $outStr .= ",$val";                         # but not added to outstr yet

    } 
    else {                                        # high byte is used as well, 
        $outStr .= ",0";                            # add training zero if val is not already zero
    }
    return $outStr;
}


######################################################################
# send 'p' command to the device to configure 
# a tft display connected to the device
# called from configureDevice which handles hello message from device
# and from attr deviceDisplay with $aVal
sub ConfigureDisplay {
    my ($hash, $aVal) = @_;
    my ($pinArg, $pin, $pinName, $ppu, $fDiv, $unit, $fut, $funit);
    my $name = $hash->{NAME};
    if (!defined($aVal)) {
        $aVal = AttrVal($name, "deviceDisplay", "");
    }    
    if ($aVal =~ /^([AD\d]+)(?:[\s\,]+([^\s\,]+)(?:[\s\,]+([^\s\,]+)))\s*$/) {
        ($pinArg, $unit, $funit) = ($1, $2, $3);

        if (!$hash->{Initialized}) {                        # no hello received yet
            Log3 $name, 5, "$name: pin validation and communication postponed until device is initialized";
            return;                                   # accept value but don't send it to the device yet.
        }
        ($pin, $pinName) = ParsePin($hash, $pinArg);
        return "illegal pin $pinArg" if (!defined($pin));   # parsePin logs error if wrong pin spec

        $ppu = AttrValFromList($hash, 0, "readingPulsesPerUnit$pinName", "readingPulsesPerUnit$pin");
        $ppu = AttrValFromList($hash, 0, "readingPulsesPerKWh$pinName", "readingPulsesPerKWh$pin") if (!$ppu);
        $ppu = AttrValFromList($hash, 1, "pulsesPerUnit", "pulsesPerKWh") if (!$ppu);
        $fut = AttrValFromList($hash, 60, "readingFlowUnitTime$pinName", "readingFlowUnitTime$pin");
        Log3 $name, 5, "$name: ConfigureDisplay pin $pin / $pinName, ppu $ppu, fut $fut";
        if ($ppu =~ /(\.\d)/) {
            $fDiv = 10 ** (length($1)-1);
            $ppu = int($ppu * $fDiv);
        } else {
            $fDiv = 1;
        }
    } 
    else {
        Log3 $name, 3, "$name: Invalid device display configuration $aVal";
        return "Invalid device display configuration $aVal";        
    }
    Log3 $name, 5, "$name: ConfigureDisplay $pin, $ppu, $fDiv, $unit, $fut, $funit";
    if (!$hash->{Initialized}) {        # no hello received yet
        Log3 $name, 5, "$name: pin validation and communication postponed until device is initialized";
        return;                   # accept value but don't send it to the device yet.
    }
    my $cmd = "$pin,$ppu,$fDiv" . IntString($unit) . ",$fut" . IntString($funit) . "u";
    Log3 $name, 5, "$name: ConfigureDisplay creates command $cmd";
    DoWrite($hash, $cmd);
    return;
}


#######################################################
# called from InternalTimer 
# if relevant attr is changed
sub DelayedConfigureDisplay {
    my $param = shift;
    my (undef,$name) = split(/:/,$param);
    my $hash = $defs{$name};
    
    Log3 $name, 5, "$name: call configureDisplay after delay";
    RemoveInternalTimer ("delayedcdisp:$name");
    ConfigureDisplay($hash);
    return;
}



#######################################
# Aufruf aus InternalTimer
# send "h" to ask for "Hello" since device didn't say "Started" so far - maybe it's still counting ...
# called with timer from _openCB, _Ready and if count is read in _Parse but no hello was received
sub AskForHello {
    my $param = shift;
    my (undef,$name) = split(/:/,$param);
    my $hash = $defs{$name};
    
    Log3 $name, 5, "$name: ArduCounter $Module_version sending h(ello) to device to ask for firmware version";
    return if (!DoWrite( $hash, "h"));

    my $now = gettimeofday();
    my $hwt = AttrVal($name, "helloWaitTime", 2);
    RemoveInternalTimer ("hwait:$name");
    InternalTimer($now+$hwt, "ArduCounter::HelloTimeout", "hwait:$name", 0);
    $hash->{WaitForHello} = 1;
    return;
}


#######################################
# Aufruf aus InternalTimer
sub HelloTimeout {
    my $param = shift;
    my (undef,$name) = split(/:/,$param);
    my $hash = $defs{$name};
    delete $hash->{WaitForHello};
    RemoveInternalTimer ("hwait:$name");

    if ($hash->{DeviceName} !~ m/^(.+):([0-9]+)$/) {        # not TCP
        if (!$hash->{OpenRetries}) {
            $hash->{OpenRetries} = 1;
        } 
        else {
            $hash->{OpenRetries}++;
            if ($hash->{OpenRetries}++ > 4) {
                Log3 $name, 3, "$name: device didn't reply to h(ello). Is the right sketch flashed? Is serial speed set to 38400 or 115200 for firmware >4.0?";                
                return;
            }
        }
        Log3 $name, 5, "$name: HelloTimeout: DeviceName in hash is $hash->{DeviceName}";
        if ($hash->{DeviceName} !~ /(.+)@([0-9]+)(.*)/) {   # no serial speed specified
            $hash->{DeviceName} .= '@38400';                # should not happen (added during define)
            Log3 $name, 3, "$name: device didn't reply to h(ello). No serial speed set. Is the right sketch flashed? Trying again with \@38400";
        } 
        else {                                   
            if ($2 == 38400) {             
                $hash->{DeviceName} = "${1}\@115200${3}";    # now try 115200 if 38400 before
                Log3 $name, 3, "$name: device didn't reply to h(ello). Is the right sketch flashed? Serial speed was $2. Trying again with \@115200";
            } 
            else {
                $hash->{DeviceName} = "${1}\@38400${3}";    # now try 38400
                Log3 $name, 3, "$name: device didn't reply to h(ello). Is the right sketch flashed? Serial speed was $2. Trying again with \@38400";
            }
        }
        Log3 $name, 5, "$name: HelloTimeout: DeviceName in hash is set to $hash->{DeviceName}";
        DoOpen($hash);                            # try again                             
    }
    return;
}


############################################
# Aufruf aus Open / Ready und InternalTimer
# send "1k" to ask for "alive"
sub KeepAlive {
    my $param = shift;
    my (undef,$name) = split(/:/,$param);
    my $hash = $defs{$name};
    my $now  = gettimeofday();
    
    if (IsDisabled($name)) {
        return;
    }
    my $kdl = AttrVal($name, "keepAliveDelay", 10);     # next keepalive as timer
    my $kto = AttrVal($name, "keepAliveTimeout", 2);    # timeout waiting for response 
    
    Log3 $name, 5, "$name: sending k(eepAlive) to device" if (AttrVal($name, "logFilter", "N") =~ "N"); 
    DoWrite( $hash, "1,${kdl}k");  
    RemoveInternalTimer ("alive:$name");
    InternalTimer($now+$kto, "ArduCounter::AliveTimeout", "alive:$name", 0);
    #Log3 $name, 5, "$name: keepAlive timeout timer set  $kto";
    if ($hash->{TCP}) {        
        RemoveInternalTimer ("keepAlive:$name");
        InternalTimer($now+$kdl, "ArduCounter::KeepAlive", "keepAlive:$name", 0);    # next keepalive
        #Log3 $name, 5, "$name: keepAlive timer for next message set in $kdl";
    }
    return;
}


#######################################
# Aufruf aus InternalTimer
sub AliveTimeout {
    my $param = shift;
    my (undef,$name) = split(/:/,$param);
    my $hash = $defs{$name};
    #Log3 $name, 5, "$name: AliveTimeout called";
    $hash->{KeepAliveRetries} = 0 if (!$hash->{KeepAliveRetries});    
    if (++$hash->{KeepAliveRetries} > AttrVal($name, "keepAliveRetries", 2)) {
        Log3 $name, 3, "$name: device didn't reply to k(eeepAlive), no retries left, setting device to disconnected";
        SetDisconnected($hash);        # set to Disconnected but let _Ready try to Reopen
        delete $hash->{KeepAliveRetries};
    } 
    else {
        Log3 $name, 3, "$name: device didn't reply to k(eeepAlive), count=$hash->{KeepAliveRetries}";
    }
    return;
}


##########################################################################
# Send config commands after Board reported it is ready or still counting
# called when parsing hello message from device
sub ConfigureDevice {
    my $param = shift;
    my (undef,$name) = split(/:/,$param);
    my $hash = $defs{$name};
    
    # todo: check if device got disconnected in the meantime!
    my @runningPins = sort grep {/[\d]/} keys %{$hash->{runningCfg}};
    #Log3 $name, 5, "$name: ConfigureDevice: pins in running config: @runningPins";
    my @attrPins = sort grep {/pin([dDaA])?[\d]/} keys %{$attr{$name}};
    #Log3 $name, 5, "$name: ConfigureDevice: pins from attrs: @attrPins";
           
    #Log3 $name, 5, "$name: ConfigureDevice: check for pins without attr in list: @runningPins";
    my %cPins;      # get all pins from running config in a hash to find out if one is not defined on fhem side
    for (my $i = 0; $i < @runningPins; $i++) {
        $cPins{$runningPins[$i]} = 1;
        #Log3 $name, 3, "$name: ConfigureDevice remember pin $runningPins[$i]";
    }
    Log3 $name, 5, "$name: ConfigureDevice: send config";
    while (my ($aName, $val) = each(%{$attr{$name}})) {
        if ($aName =~ /^pin([DA])?([\d+]+)/) {                  # for each pin attr
            my $type = ($1 ? $1 : '');
            my $aPinNum = $2;                                   # if not overwritten for analog pins, we have already a number
            my $pinName = $type.$aPinNum;
            $aPinNum = InternalPinNumber($hash, $pinName) if ($type && $type eq 'A');    # if this is an analog pin specification translate it
            if ($aPinNum) {
                ConfigurePin($hash, $pinName, $val);
                delete $cPins{$aPinNum};                        # this pin from running config has an attr
            } 
            else {
                Log3 $name, 3, "$name: ConfigureDevice can not send pin config for $aName, internal pin number can not be determined";
            }
        }
    }
    if (%cPins) {                                               # remaining pins in running config without attrs
        my $pins = join ",", keys %cPins;
        Log3 $name, 5, "$name: ConfigureDevice: pins in running config without attribute in Fhem: $pins";
        foreach my $pin (keys %cPins) {
            Log3 $name, 5, "$name: ConfigureDevice: removing pin $pin";
            DoWrite($hash, "${pin}d");
        }
    } 
    else {
        Log3 $name, 5, "$name: ConfigureDevice: no pins in running config without attribute in Fhem";
    }

    ConfigureIntervals($hash);
    ConfigureVerboseLevels($hash);
    ConfigureDisplay($hash) if ($hash->{Board} =~ /Display/);

    DoWrite( $hash, "s");     # get new running config 
    return;
}


#########################################################################
# Attr command 
sub AttrFn {
    my ($cmd,$name,$aName,$aVal) = @_;
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value
    my $hash    = $defs{$name};
    my $modHash = $modules{$hash->{TYPE}};

    Log3 $name, 5, "$name: Attr called with @_";
    if ($cmd eq "set") {
        if ($aName =~ /^pin([DA]?\d+)/) {             # pin attribute -> add a pin
            my $pinName = $1;
            return ConfigurePin($hash, $pinName, $aVal);
        } 
        elsif ($aName eq "devVerbose") {
            my $text = "devVerbose has been replaced by " .
                    'enableHistory:0,1 ' .                          # history creation on device
                    'enableSerialEcho:0,1,2 ' .                     # serial echo of output via TCP from device
                    'enablePinDebug:0,1 ' .                         # show pin state changes from device
                    'enableAnalogDebug:0,1,2,3 ' .                  # show analog levels
                    'enableDevTime:0,1 ' .                          # device will send its time so drift can be detected
                    " please adapt you attribute configuration";

            Log3 $name, 3, "$name: $text";
            return $text;
        } 
        elsif ($aName eq "enableHistory") {
            return ConfigureVerboseLevels($hash, $aVal); 
        } 
        elsif ($aName eq "enableSerialEcho") {
            return ConfigureVerboseLevels($hash, undef, $aVal); 
        } 
        elsif ($aName eq "enablePinDebug") {
            return ConfigureVerboseLevels($hash, undef, undef, $aVal); 
        } 
        elsif ($aName eq "enableAnalogDebug") {
            return ConfigureVerboseLevels($hash, undef, undef, undef, $aVal); 
        } 
        elsif ($aName eq "enableDevTime") {
            return ConfigureVerboseLevels($hash, undef, undef, undef, undef, $aVal); 
        } 
        elsif ($aName eq "analogThresholds") {
            my $text = "analogThresholds has been removed. Thresholds are now part of the pin attribute. Please update your configuration";
            Log3 $name, 3, "$name: $text";

            if ($aVal =~ /^(\d+) (\d+)\s*$/) {
                my $min = $1;
                my $max = $2;
                if ($min < 1 || $min > 1023 || $max < $min || $max > 1023) {
                    Log3 $name, 3, "$name: Invalid value in attr $name $aName $aVal";
                    return "Invalid Value $aVal";
                }
                if ($hash->{Initialized}) {
                    DoWrite($hash, "${min},${max}t");
                } else {
                    Log3 $name, 5, "$name: communication postponed until device is initialized";
                }
            } 
            else {
                Log3 $name, 3, "$name: Invalid value in attr $name $aName $aVal";
                return "Invalid Value $aVal";
            }           
        } 
        elsif ($aName eq "interval") { 
            return ConfigureIntervals($hash, $aVal);
        } 
        elsif ($aName eq "board") {
            $hash->{Board} = $aVal;
        } 
        elsif ($aName eq "factor") {                          # log notice to remove this / replace
            if ($aVal =~ '^(\d+)$') {
            } else {
                Log3 $name, 3, "$name: Invalid value in attr $name $aName $aVal";
                return "Invalid Value $aVal";
            }           
        } 
        elsif ($aName eq "keepAliveDelay") {
            if ($aVal =~ '^(\d+)$') {
                if ($aVal > 3600) {
                    Log3 $name, 3, "$name: value too big in attr $name $aName $aVal";
                    return "Value too big: $aVal";
                }
            } 
            else {
                Log3 $name, 3, "$name: Invalid value in attr $name $aName $aVal";
                return "Invalid Value $aVal";
            }           
        } 
        elsif ($aName eq 'disable') {
            if ($aVal) {
                Log3 $name, 5, "$name: disable attribute set";                
                SetDisconnected($hash);    # set to disconnected and remove timers
                DevIo_CloseDev($hash);              # really close and remove from readyFnList again
                return;
            } else {
                Log3 $name, 3, "$name: disable attribute cleared";
                DoOpen($hash) if ($init_done);    # only if fhem is initialized
            }
        } 
        elsif ($aName eq 'deviceDisplay') {
            ConfigureDisplay($hash, $aVal);
        } 
        elsif ($aName =~ /pulsesPer/ || $aName =~ /[Ff]lowUnitTime/) {
            my $now = gettimeofday(); 
            RemoveInternalTimer ("delayedcdisp:$name");
            InternalTimer($now, "ArduCounter::DelayedConfigureDisplay", "delayedcdisp:$name", 0);
        } 
        elsif ($aName =~ /^verboseReadings([DA]?(\d+))/) {
            my $arg = $1;
            if (!$hash->{Initialized}) {        # no hello received yet
                return;                         # accept value for now.
            }
            my ($pin, $pinName) = ParsePin($hash, $arg);
            return "illegal pin $arg" if (!defined($pin));          # parsePin logs error if wrong pin spec

            if ($aVal eq "0") {
                UserReadingsDelete($hash, "lastMsg", $pin);
                UserReadingsDelete($hash, "pinHistory", $pin);
            } 
            elsif ($aVal eq "-1") {
                readingsDelete($hash, 'pin' . $pin);
                readingsDelete($hash, 'pin' . $pinName);
                readingsDelete($hash, 'long' . $pin);
                readingsDelete($hash, 'long' . $pinName);
                readingsDelete($hash, 'countDiff' . $pin);
                readingsDelete($hash, 'countDiff' . $pinName);
                readingsDelete($hash, 'timeDiff' . $pin);
                readingsDelete($hash, 'timeDiff' . $pinName);
                readingsDelete($hash, 'reject' . $pin);
                readingsDelete($hash, 'reject' . $pinName);
                readingsDelete($hash, 'interpolatedLong' . $pin);
                readingsDelete($hash, 'interpolatedLong' . $pinName);
            }
        }        
        ManageUserAttr($hash, $aName);
    } 
    elsif ($cmd eq "del") {
        if ($aName =~ 'pin(.*)') {
            my $arg = $1;
            if (!$hash->{Initialized}) {        # no hello received yet
                return;                         # accept value for now.
            }
            my ($pin, $pinName) = ParsePin($hash, $arg);
            if (defined($pin)) {
                DoWrite( $hash, "${pin}d");
            }

        } 
        elsif ($aName eq 'disable') {
            Log3 $name, 3, "$name: disable attribute removed";    
            DoOpen($hash) if ($init_done);       # if fhem is initialized
        }
    }
    return;
}



#########################################################################
# flash a device via serial or OTA with external commands
sub DoFlash {
    my ($hash, @args) = @_;
    my $name = $hash->{NAME};
    my $log = "";   
    my @deviceName = split(/@/, $hash->{DeviceName});
    my $port = $deviceName[0];
    my $firmwareFolder = "./FHEM/firmware/";
    my $logFile = AttrVal("global", "logdir", "./log") . "/ArduCounterFlash.log";
    my $ip;

    if ($port =~ /(\d+\.\d+\.\d+\.\d+):(\d+)/) {
        $ip   = $1;
        $port = $1;
    }
    
    my $hexFile  = shift @args; 
    my $netPort = 0;
    
    my $flashCommand = AttrVal($name, "flashCommand", "");
    if ($hash->{Board} =~ /ESP8266/ ) { 
        $hexFile = "ArduCounter-ESP8266.bin" if (!$hexFile);
        $netPort = 8266;
        if (!$flashCommand ) {
            if ($hash->{TCP}) {
                $flashCommand = 'espota.py -i[IP] -p [NETPORT] -f [BINFILE] >[LOGFILE] 2>&1';
            } 
            else {
                $flashCommand = 'esptool.py --chip esp8266 --port [PORT] --baud 115200 write_flash 0x0 [BINFILE] >[LOGFILE] 2>&1';
            }
        }
    } elsif ($hash->{Board} =~ /ESP32/ || $hash->{Board} =~ /T-Display/ ) {
        $netPort = 3232;
        if ($hash->{Board} =~ /T-Display/ ) {
            $hexFile = "ArduCounter-ESP32T.bin" if (!$hexFile);
        } 
        else {
            $hexFile = "ArduCounter-ESP32.bin" if (!$hexFile);
        }
        if (!$flashCommand ) {
            if ($hash->{TCP}) {
                $flashCommand = 'espota.py -i[IP] -p [NETPORT] -f [BINFILE] 2>[LOGFILE]';
                # https://github.com/esp8266/Arduino/blob/master/tools/espota.py
            } 
            else {
                $flashCommand = 'esptool.py --chip esp32 --port [PORT] --baud 460800 --before default_reset --after hard_reset write_flash -z ' .
                                '--flash_mode dio --flash_freq 40m --flash_size detect ' .
                                '0x1000  FHEM/firmware/ArduCounter-ESP32-bootloader_dio_40m.bin ' .
                                '0x8000  FHEM/firmware/ArduCounter-ESP32-partitions.bin ' .
                                '0xe000  FHEM/firmware/ArduCounter-ESP32-boot_app0.bin ' .
                                '0x10000 [BINFILE] >[LOGFILE] 2>&1';
                # to install do apt-get install python3, python3-pip
                # and then pip3 install esptool
            }
        }
    } 
    elsif ($hash->{Board} =~ /NANO/ ) {
        $hexFile = "ArduCounter-NANO.hex" if (!$hexFile);
        $flashCommand = 'avrdude -p atmega328P -b 57600 -c arduino -P [PORT] -D -U flash:w:[HEXFILE] 2>[LOGFILE]' if (!$flashCommand);        
    } 
    elsif ($hash->{Board} =~ /UNO/ ) {
        $hexFile = "ArduCounter-NANO.hex" if (!$hexFile);
        $flashCommand = 'avrdude -p atmega328P -c arduino -P [PORT] -D -U flash:w:[HEXFILE] 2>[LOGFILE]' if (!$flashCommand);
    } 
    else {
        if (!$hash->{Board}) {
            return "Flashing not possible if board type is unknown and no filename given. Try setting the board attribute (ESP8266, ESP32 or NANO)."; 
        } 
        else {
            return "Flashing $hash->{Board} not supported or board attribute wrong (should be ESP8266, ESP32 or NANO)"; 
        }
    }

    $hexFile = $firmwareFolder . $hexFile;
    return "The file '$hexFile' does not exist" if(!-e $hexFile);

    Log3 $name, 3, "$name: Flashing device at $port with $hexFile. See $logFile for details";
    
    $log .= "flashing device as ArduCounter for $name\n";
    $log .= "firmware file: $hexFile\n";

    $log .= "port: $port\n";
    $log .= "log file: $logFile\n";

    if($flashCommand) {
        if (-e $logFile) {
          unlink $logFile;
        }

        SetDisconnected($hash);
        DevIo_CloseDev($hash);
        $log .= "$name closed\n";

        $flashCommand =~ s/\Q[PORT]\E/$port/g;
        $flashCommand =~ s/\Q[IP]\E/$ip/g;
        $flashCommand =~ s/\Q[HEXFILE]\E/$hexFile/g;
        $flashCommand =~ s/\Q[BINFILE]\E/$hexFile/g;
        $flashCommand =~ s/\Q[LOGFILE]\E/$logFile/g;
        $flashCommand =~ s/\Q[NETPORT]\E/$netPort/g;

        $log .= "command: $flashCommand\n\n";
        `$flashCommand`;

        local $/=undef;
        if (-e $logFile) {
            open my $FILE, '<', $logFile;
            my $logText = <$FILE>;
            close $FILE;
            $log .= "--- flash command ---------------------------------------------------------------------------------\n";
            $log .= $logText;
            $log .= "--- flash command ---------------------------------------------------------------------------------\n\n";
        }
        else {
            $log .= "WARNING: flash command created no log file\n\n";
        }
        delete $hash->{Initialized};
        my $now   = gettimeofday(); 
        my $delay = 5;          # wait 5 seconds to give device time for reboot
        Log3 $name, 4, "$name: DoFlash set internal timer to call open";
        RemoveInternalTimer ("delayedopen:$name");
        InternalTimer($now+$delay, "ArduCounter::DelayedOpen", "delayedopen:$name", 0);
        $log .= "$name internal timer set to call open.\n";
    } 
    else {
         return "Flashing not possible if flash command is not set for this board and connection"; 
    }
    return $log;
}



#####################################################
# parse pin input and return pin number and pin name
sub ParsePin {
    my ($hash, $arg) = @_;
    my $name = $hash->{NAME};        
    if ($arg !~ /^([DA]?)(\d+)/) {
        Log3 $name, 3, "$name: parseTime got invalid pin spec $arg";
        return;
    } 
    my $pinType = $1;
    my $pin     = $2;
    $pin = InternalPinNumber($hash, $pinType.$pin) if ($pinType eq 'A');
    my $pinName = PinName ($hash, $pin);

    # if board did send allowed pins, check here
    if ($hash->{allowedPins}) {         # list of allowed pins received with hello
        my %pins = map { $_ => 1 } split (/,/, $hash->{allowedPins});
        if ($init_done && %pins && !$pins{$pin}) {
            Log3 $name, 3, "$name: Invalid / disallowed pin in specification $arg";
            return;
        }
    }
    return ($pin, $pinName);
}


#########################################################################
# clears all counter readings for a specified pin number
# called from set with a pin number
sub ClearPinCounters {
    my ($hash, $pin) = @_;
    DoWrite($hash, "${pin}c");
    my ($err, $msg) = ReadAnswer($hash, '(cleared \d+)|(Error:)');        

    UserReadingsDelete($hash, 'pin', $pin);             # internal device counter pinX
    UserReadingsDelete($hash, 'long', $pin);            # long counter longX
    UserReadingsDelete($hash, 'interpolated', $pin);    # interpolated long counter interpolatedLongX
    UserReadingsDelete($hash, 'calcCounter', $pin);     # calculated counter calcCounterX
    UserReadingsDelete($hash, 'calcCounter_i', $pin);   # calculated counter - ignored units calcCounterX_i
    UserReadingsDelete($hash, 'power', $pin);           # power reading powerX
    UserReadingsDelete($hash, 'seq', $pin);             # sequence seqX
        
    UserReadingsDelete($hash, 'reject', $pin);          # rejected pulsesin last reportng period rejectX
    UserReadingsDelete($hash, 'timeDiff', $pin);        # time difference of last reporting period timeDiffX
    UserReadingsDelete($hash, 'countDiff', $pin);       # count difference of last reporting period countDiffX        
    UserReadingsDelete($hash, 'lastMsg', $pin);         # last message from device

    UserReadingsDelete($hash, "runTime", $pin);
    UserReadingsDelete($hash, "runTimeIgnore", $pin);
    UserReadingsDelete($hash, ".switchOnTime", $pin);
    UserReadingsDelete($hash, ".lastCheckIgnoreTime", $pin);
    return;
}


#########################################################################
# SET command
sub SetFn {

    my @setValArr = @_;                     # remainder is set values 
    my $hash      = shift @setValArr;       # reference to Fhem device hash
    my $name      = shift @setValArr;       # Fhem device name
    my $setName   = shift @setValArr;       # name of the set option
    my $setVal    = join(' ', @setValArr);  # set values as one string   

    return "\"set $name\" needs at least an argument" if (!$setName);

    if(!defined($SetHash{$setName})) {
        my @cList = keys %SetHash;
        return "Unknown argument $setName, choose one of " . join(" ", @cList);
    } 
    if ($setName eq "disable") {
        Log3 $name, 4, "$name: set disable called";
        CommandAttr(undef, "$name disable 1");
        return;  
    } 
    elsif ($setName eq "enable") {
        Log3 $name, 4, "$name: set enable called";
        CommandAttr(undef, "$name disable 0");
        return;
    } 
    elsif ($setName eq "reconnect") {
        Log3 $name, 4, "$name: set reconnect called";
        DevIo_CloseDev($hash);   
        delete $hash->{OpenRetries};
        DoOpen($hash);
        return;
    } 
    elsif ($setName eq "clearLevels") {
        delete $hash->{analogLevels};
        return;
    } 
    elsif ($setName eq "clearHistory") {
        # remove history 
        delete $hash->{History};
        delete $hash->{HistoryPin};
        delete $hash->{LastHistSeq};
        delete $hash->{HistIdx};
        return;
    } 
    elsif ($setName eq "clearCounters") {                # clear counters for a specific pin
        my ($pin, $pinName) = ParsePin($hash, $setVal);
        return "illegal pin $setVal" if (!defined($pin));          # parsePin logs error if wrong pin spec

        Log3 $name, 4, "$name: Set $setName $setVal called - removing all readings for pin $pinName, internal $pin";
        ClearPinCounters($hash, $pin);
    } 
    elsif ($setName eq "counter") {                 # set counters for a specific pin
        if ($setVal =~ /([AD]?\d+)[\s\,]+([\d\.]+)/) {
            my $val = $2;
            my ($pin, $pinName) = ParsePin($hash, $1);
            return "illegal pin $setVal" if (!defined($pin));          # parsePin logs error if wrong pin spec
            Log3 $name, 4, "$name: Set $setName $setVal called - setting calcCounter for pin $pinName";
            readingsBeginUpdate($hash);
            UserBulkUpdate($hash, 'calcCounter', $pin, $val);
            readingsEndUpdate($hash,1);    
        } else {
            return "wrong syntax, use set counters pin value";
        }    
    } 
    elsif ($setName eq "flash") {
        return DoFlash($hash, @setValArr);        
    }

    if(!IsOpen($hash)) {
        Log3 $name, 4, "$name: Set $setName $setVal called but device is disconnected";
        return "Set called but device is disconnected";
    }
    if (IsDisabled($name)) {
        Log3 $name, 4, "$name: set $setName $setVal called but device is disabled";
        return;
    }   

    if ($setName eq "raw") {
        Log3 $name, 4, "$name: set raw $setVal called";
        DoWrite($hash, "$setVal");            
    } 
    elsif ($setName eq "saveConfig") {
        Log3 $name, 4, "$name: set saveConfig called";
        DoWrite($hash, "e");
    } 
    elsif ($setName eq "reset") {
        Log3 $name, 4, "$name: set reset called";
        if (DoWrite($hash, "r")) {
            delete $hash->{Initialized};
        }
        DevIo_CloseDev($hash); 
        DoOpen($hash);
        return "sent (r)eset command to device - waiting for its setup message";    
    } 
    elsif ($setName eq "resetWifi") {
        Log3 $name, 4, "$name: set resetWifi called";
        DoWrite($hash, "w");
        return "sent (w) command to device";
        
    }
    return;
}


#########################################################################
# GET command
sub GetFn {
    my @getValArr = @_;                     # rest is optional values
    my $hash      = shift @getValArr;       # reference to device hash
    my $name      = shift @getValArr;       # device name
    my $getName   = shift @getValArr;       # get option name
    my $getVal    = join(' ', @getValArr);  # optional value after get name

    return "\"get $name\" needs at least one argument" if (!$getName);

    if(!defined($GetHash{$getName})) {
        my @cList = keys %GetHash;
        return "Unknown argument $getName, choose one of " . join(" ", @cList);
    } 
    if ($getName eq "levels") {
        my $msg = "";
        foreach my $level (sort {$a <=> $b} keys %{$hash->{analogLevels}}) {
            $msg .= "$level: $hash->{analogLevels}{$level}\n";
        }
        return "observed levels from analog input:\n$msg\n";
    }
    if(!IsOpen($hash)) {
        Log3 $name, 4, "$name: Get called but device is disconnected";
        return ("Get called but device is disconnected", undef);
    }
    if (IsDisabled($name)) {
        Log3 $name, 4, "$name: get called but device is disabled";
        return;
    }   
    
    if ($getName eq "info") {
        Log3 $name, 5, "$name: Sending info command to device";
        DoWrite( $hash, "s");
        my ($err, $msg) = ReadAnswer($hash, 'Next report in.*seconds');        
        return ($err ? $err : $msg);  
    } 
    elsif ($getName eq "history") {
        Log3 $name, 5, "$name: get history";
        $hash->{HistIdx} = 0 if (!defined($hash->{HistIdx}));
        my $idx   = $hash->{HistIdx};           # HistIdx points to the next slot to be overwritten
        my $ret   = "";
        my $count = 0;
        my $histLine;
        while ($count < AttrVal($name, "maxHist", 1000)) {
            if (defined ($hash->{History}[$idx])) {
                if (!$getVal || !$hash->{HistoryPin} || $hash->{HistoryPin}[$idx] eq $getVal) {
                    $ret .= $hash->{History}[$idx] . "\n";
                }
            }
            $idx++;
            $count++;
            $idx = 0 if ($idx > AttrVal($name, "maxHist", 1000));
        }
        if (!AttrVal($name, "enableHistory", 0)) {
            $ret = "Make sure that enableHistory is set to 1 to get pin history data\n" . $ret;
        }
        return ($ret ? $ret : "no history data so far");
    }
    return;
}


###########################################
# calculate and log drift of device time
# called from parse_hello with T and B line,
# from parse with new N line
# and parse report with only N
sub ParseTime {
    my ($hash, $line, $now) = @_;
    my $name = $hash->{NAME};

    if ($line !~ /^[NT](\d+),(\d+) *(?:B(\d+),(\d+))?/) {
        Log3 $name, 4, "$name: probably wrong firmware version - cannot parse line $line";
        return;
    }
    my $mNow   = $1;
    my $mNowW  = $2;
    my $mBoot  = $3;
    my $mBootW = $4;

    my $deviceNowSecs  = ($mNow/1000) + ((0xFFFFFFFF / 1000) * $mNowW);
    #Log3 $name, 5, "$name: Device Time $deviceNowSecs";
    if (defined($mBoot)) {
        my $deviceBootSecs = ($mBoot/1000) + ((0xFFFFFFFF / 1000) * $mBootW);
        my $bootTime = $now - ($deviceNowSecs - $deviceBootSecs);
        $hash->{deviceBooted} = $bootTime;          # for estimation of missed pulses up to now
    }    
    
    if (defined ($hash->{'.DeTOff'}) && $hash->{'.LastDeT'}) {
        if ($deviceNowSecs >= $hash->{'.LastDeT'}) {
            $hash->{'.Drift2'} = ($now - $hash->{'.DeTOff'}) - $deviceNowSecs;
        } 
        else {
            $hash->{'.DeTOff'}  = $now - $deviceNowSecs;
            Log3 $name, 4, "$name: device did reset (now $deviceNowSecs, before $hash->{'.LastDeT'})." .
                " New offset is $hash->{'.DeTOff'}";
        }
    } 
    else {
        $hash->{'.DeTOff'}  = $now - $deviceNowSecs;
        $hash->{'.Drift2'}  = 0;
        $hash->{'.DriftStart'}  = $now;
        Log3 $name, 5, "$name: Initialize device clock offset to $hash->{'.DeTOff'}";
    }
    $hash->{'.LastDeT'} = $deviceNowSecs;  

    my $drTime = ($now - $hash->{'.DriftStart'});
    Log3 $name, 5, "$name: Device Time $deviceNowSecs" .
       ", Offset " . sprintf("%.3f", $hash->{'.DeTOff'}/1000) . 
       ", Drift "  . sprintf("%.3f", $hash->{'.Drift2'}) .
       "s in " . sprintf("%.3f", $drTime) . "s" .
       ($drTime > 0 ? ", " . sprintf("%.2f", $hash->{'.Drift2'} / $drTime * 100) . "%" : "");
    return;
}


sub ParseAvailablePins {
    my ($hash, $line) = @_;
    my $name = $hash->{NAME};
    
    Log3 $name, 5, "$name: Device sent available pins $line";
    # now enrich $line with $rAnalogPinMap{$hash->{Board}}{$pin}
    if ($line && $hash->{Board}) {
        my $newAllowed;
        my $first = 1;
        foreach my $pin (split (/,/, $line)) {
            $newAllowed .= ($first ? '' : ','); # separate by , if not empty anymore
            $newAllowed .= $pin;
            if ($rAnalogPinMap{$hash->{Board}}{$pin}) {
                $newAllowed .= ",$rAnalogPinMap{$hash->{Board}}{$pin}";
            }
            $first = 0;                 
        }
        $hash->{allowedPins} = $newAllowed;
    }
    return;
}


####################################################
# Hello is sent after reconnect or restart
# check firmware version, set device boot time hash
# set timer to configure device
sub ParseHello {
    my ($hash, $line, $now) = @_;
    my $name = $hash->{NAME};
    
    # current versions send Time and avaliable pins as separate lines, not here
    if ($line !~ /^ArduCounter V([\d\.]+) on ([^\ ]+) ?(.*) compiled (.*) (?:Started|Hello)(, pins ([0-9\,]+) available)? ?(T(\d+),(\d+) B(\d+),(\d+))?/) {
        Log3 $name, 4, "$name: probably wrong firmware version - cannot parse line $line";
        return;
    }
    $hash->{VersionFirmware} = ($1 ? $1 : '');
    $hash->{Board}           = ($2 ? $2 : 'unknown');
    $hash->{BoardDet}        = ($3 ? $3 : '');
    $hash->{SketchCompile}   = ($4 ? $4 : 'unknown');
    my $allowedPins          = $6;
    my $dTime                = $7;
    
    my $boardAttr = AttrVal($name, 'board', '');
    if ($hash->{Board} && $boardAttr && ($hash->{Board} ne $boardAttr)) {
        Log3 $name, 5, "attribute board is set to $boardAttr and is overwriting board $hash->{Board} reported by device";
        $hash->{Board} = $boardAttr;
    }

    if (!$hash->{VersionFirmware} || $hash->{VersionFirmware} < "2.36") {
        $hash->{VersionFirmware} .= " - not compatible with this Module version - please flash new sketch";
        Log3 $name, 3, "$name: device reported outdated Arducounter Firmware ($hash->{VersionFirmware}) - please update!";
        delete $hash->{Initialized};
    } 
    else {
        if ($hash->{VersionFirmware} < "4.00") {
            Log3 $name, 3, "$name: device sent hello with outdated Arducounter Firmware ($hash->{VersionFirmware}) - please update!";
        } 
        else {
            Log3 $name, 5, "$name: device sent hello: $line";
        }
        $hash->{Initialized} = 1;                   # device has finished its boot and reported version
        
        my $cft = AttrVal($name, "configDelay", 1); # wait for device to send cfg before reconf.
        RemoveInternalTimer ("cmpCfg:$name");
        InternalTimer($now+$cft, "ArduCounter::ConfigureDevice", "cmpCfg:$name", 0);

        ParseTime($hash, $dTime, $now) if ($dTime);
        ParseAvailablePins($hash, $allowedPins) if ($allowedPins);
    }
    delete $hash->{runningCfg};                     # new config will be sent now
    delete $hash->{WaitForHello};
    delete $hash->{OpenRetries};
    
    # remove old history - sequences won't fit anymore for future history messages
    delete $hash->{History};
    delete $hash->{HistoryPin};
    delete $hash->{LastHistSeq};
    delete $hash->{HistIdx};
    
    RemoveInternalTimer ("hwait:$name");            # dont wait for hello reply if already sent
    RemoveInternalTimer ("sendHello:$name");        # Hello not needed anymore if not sent yet
    return;
}



#########################################################################################
# return the name of the reading for a passed internal name 
# like 'long' or 'calcCounter' and its pin Number
# depending on verboseReadings and readingName attributes
# called with a base name and a pin number
sub UserReadingName {
    my ($hash, $rBaseName, $pin) = @_;
    my $name    = $hash->{NAME};
    my $pinName = PinName ($hash, $pin);
    my $verbose = AttrValFromList($hash, 0, "verboseReadings$pinName", "verboseReadings$pin");
    if ($verbose !~ /\-?[0-9]+/) {
        Log3 $name, 3, "illegal setting for verboseReadings: $verbose";
        $verbose = 0;
    }
    if ($rBaseName eq 'pin') {
        my $default = ($verbose >= 0 ? "pin$pinName" : ".pin$pinName");                     # hidden if verboseReadings < 0
        return AttrValFromList($hash, $default, "readingNameCount$pinName", "readingNameCount$pin");
    } 
    elsif ($rBaseName eq 'long') {
        my $default = ($verbose >= 0 ? "long$pinName" : ".long$pinName");                   # hidden if verboseReadings < 0
        return AttrValFromList($hash, $default, "readingNameLongCount$pinName", "readingNameLongCount$pin");
    } 
    elsif ($rBaseName eq 'interpolated') {
        my $default = ($verbose >= 0 ? "interpolatedLong$pinName" : "");                    # no reading if verboseReadings < 0
        return AttrValFromList($hash, $default, "readingNameInterpolatedCount$pinName", "readingNameInterpolatedCount$pin");
    } 
    elsif ($rBaseName eq 'calcCounter') {
        return AttrValFromList($hash, "calcCounter$pinName", "readingNameCalcCount$pinName", "readingNameCalcCount$pin");
    } 
    elsif ($rBaseName eq 'calcCounter_i') {
        return AttrValFromList($hash, "calcCounter$pinName" . "_i", "readingNameCalcCount$pinName" . "_i", "readingNameCalcCount$pin" . "_i");
    } 
    elsif ($rBaseName eq 'timeDiff') {
        return ($verbose >= 0 ? "timeDiff$pinName" : ".timeDiff$pinName");                  # hidden if verboseReadings < 0
    } 
    elsif ($rBaseName eq 'countDiff') {
        return ($verbose >= 0 ? "countDiff$pinName" : ".countDiff$pinName");                # hidden if verboseReadings < 0
    } 
    elsif ($rBaseName eq 'reject') {
        return ($verbose >= 0 ? "reject$pinName" : ".reject$pinName");                      # hidden if verboseReadings < 0
    } 
    elsif ($rBaseName eq 'power') {
        return AttrValFromList($hash, "power$pinName", "readingNamePower$pinName", "readingNamePower$pin");
    } 
    elsif ($rBaseName eq 'lastMsg') {
        return ($verbose > 0 ? "lastMsg$pinName" : "");                                     # no reading if verboseReadings < 1
    } 
    elsif ($rBaseName eq 'pinHistory') {
        return ($verbose > 0 ? "pinHistory$pinName" : "");                                  # no reading if verboseReadings < 1
    } 
    elsif ($rBaseName eq 'seq') {
        return ($verbose > 0 ? ".seq$pinName" : "");                                        # always hidden
    }  
    else {
        return $rBaseName . $pinName;
    }
    return;
}


#########################################################################
# return the value of the reading 
# with a passed internal name and a pin number
# depending on verboseReadings and readingName attributes
sub UserReadingsVal {
    my ($name, $rBaseName, $pin, $default) = @_;
    my $hash = $defs{$name};

    $default = 0 if (!defined($default));
    my $rName = UserReadingName($hash, $rBaseName, $pin);
    return $default if (!$rBaseName);
    return ReadingsVal($name, $rName, $default);
}


#########################################################################
# return the value of the reading 
# depending on verboseReadings and readingName attributes
# only called from HandleCounters with a base name and a pin number
sub UserReadingsTimestamp {
    my ($name, $rBaseName, $pin) = @_;
    my $hash = $defs{$name};

    my $rName = UserReadingName($hash, $rBaseName, $pin);
    return 0 if (!$rBaseName);
    return ReadingsTimestamp($name, $rName, 0);
}


#########################################################################
# bulk update readings
# depending on verboseReadings and readingName attributes
# called from functions that handle device reports 
# with a base name and a pin number, value and optional time
sub UserBulkUpdate {
    my ($hash, $rBaseName, $pin, $value, $sTime) = @_;
    my $name  = $hash->{NAME};
    my $rName = UserReadingName($hash, $rBaseName, $pin);
    if (!$rName) {
        #Log3 $name, 5, "UserBulkUpdate - suppress reading $rBaseName for pin $pin";
        return;
    }
    if (defined($sTime)) {
        my $fSdTim = FmtTime($sTime);                   # only time formatted for logging
        my $fSTime = FmtDateTime($sTime);               # date time formatted for reading
        Log3 $name, 5, "ReadingsUpdate - readingStartTime specified: setting timestamp to $fSdTim";
        my $chIdx  = 0;  
        $hash->{".updateTime"}      = $sTime;
        $hash->{".updateTimestamp"} = $fSTime;
        readingsBulkUpdate($hash, $rName, $value);
        $hash->{CHANGETIME}[$chIdx++] = $fSTime;        # Intervall start
        readingsEndUpdate($hash, 1);                    # end of special block
        readingsBeginUpdate($hash);                     # start regular update block
    } 
    else {
        readingsBulkUpdate($hash, $rName, $value);
    }
    return;
}


#########################################################################
# delete readings
# depending on verboseReadings and readingName attributes
# called with a pin number
sub UserReadingsDelete {
    my ($hash, $rBaseName, $pin) = @_;
    my $name = $hash->{NAME};

    my $rName = UserReadingName($hash, $rBaseName, $pin);
    readingsDelete($hash, $rName);
    return;
}


#########################################################################
sub HandleCounters {
    my ($hash, $pin, $seq, $count, $time, $diff, $rDiff, $now, $ppu) = @_;
    my $name = $hash->{NAME};
    
    my $pinName   = PinName ($hash, $pin);
    my $lName     = LogPinDesc($hash, $pin);
    my $pLog      = "$name: pin $pinName ($lName)";             # to be used as start of log lines

    my $longCount = UserReadingsVal($name, 'long', $pin);           # alter long count Wert
    my $intpCount = UserReadingsVal($name, 'interpolated', $pin);   # alter interpolated count Wert
    my $lastCount = UserReadingsVal($name, 'pin', $pin);
    my $cCounter  = UserReadingsVal($name, 'calcCounter', $pin);    # calculated counter 
    my $iSum      = UserReadingsVal($name, 'calcCounter_i', $pin);  # ignored sum 
    my $lastSeq   = UserReadingsVal($name, 'seq', $pin);
    my $intrCount = 0;                                          # interpolated count to be added    

    my $lastCountTS   = UserReadingsTimestamp ($name, 'pin', $pin); # last time long count reading was set as string
    my $lastCountTNum = time_str2num($lastCountTS);             # time as number
        
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

    if ($deviceBooted) {                                         # first report for this pin after a restart -> do interpolation 
        # interpolate for period between last report before boot and boot time. 
        Log3 $name, 5, "$pLog device restarted at $fBootTim, last reported at " . FmtTime($lastCountTNum) . " " .
            "count changed from $lastCount to $count, sequence from $lastSeq to $seq";
        $seqGap   = $seq - 1;                                   # $seq should be 1 after restart
        $pulseGap = $countStart;                                # we missed everything up to the count at start of the reported interval
        
        my $lastInterval  = UserReadingsVal ($name, "timeDiff", $pin);          # time diff of last interval (old reading)
        my $lastCDiff     = UserReadingsVal ($name, "countDiff", $pin);         # count diff of last interval (old reading)
        my $offlTime      = sprintf ("%.2f", $hash->{deviceBooted} - $lastCountTNum);   # estimated offline time (last report in readings until boot)
        
        if ($lastInterval && ($offlTime > 0) && ($offlTime < 12*60*60)) {               # offline > 0 and < 12h
            my $lastRatio = $lastCDiff / $lastInterval;
            my $curRatio  = $diff / $time;
            my $intRatio  = 1000 * ($lastRatio + $curRatio) / 2;            
            $intrCount = int(($offlTime * $intRatio)+0.5);
            Log3 $name, 3, "$pLog interpolating for $offlTime secs until boot, $intrCount estimated pulses (before $lastCDiff in $lastInterval ms, now $diff in $time ms, avg ratio $intRatio p/s)";
        } 
        else {
            Log3 $name, 4, "$pLog interpolation of missed pulses for pin $pinName ($lName) not possible - no valid historic data.";
        }              
    } 
    else {
        if ($pulseGap < 0) {                                    # pulseGap < 0 abd not booted should not happen
            Log3 $name, 3, "$pLog seems to have missed $seqGap reports in $timeGap seconds. " .
                "Last reported sequence was $lastSeq, now $seq. " .
                "Device count before was $lastCount, now $count with rDiff $rDiff " .
                "but pulseGap is $pulseGap. this is probably wrong and should not happen. Setting pulseGap to 0." if (!$deviceBooted);
            $pulseGap = 0;
        } 
    }
 
    Log3 $name, 3, "$pLog missed $seqGap reports in $timeGap seconds. Last reported sequence was $lastSeq, " . 
        "now $seq. Device count before was $lastCount, now $count with rDiff $rDiff. " .
        "Adding $pulseGap to long count and intpolated count readings" if ($pulseGap > 0);
    Log3 $name, 5, "$pLog adding rDiff $rDiff to long count $longCount and interpolated count $intpCount" if ($rDiff);
    Log3 $name, 5, "$pLog adding interpolated $intrCount to interpolated count $intpCount" if ($intrCount);

    $intpCount += ($rDiff + $pulseGap + $intrCount);
    $longCount += ($rDiff + $pulseGap);
    if ($ppu) {
        $cCounter += ($rDiff + $pulseGap + $intrCount) / $ppu;  # add to calculated counter
        $iSum     += $intrCount / $ppu;                         # sum of interpolation kWh
    }
    
    UserBulkUpdate($hash, 'pin', $pin, $count);
    UserBulkUpdate($hash, 'long', $pin, $longCount);
    UserBulkUpdate($hash, 'interpolated', $pin, $intpCount);
    UserBulkUpdate($hash, 'calcCounter', $pin, $cCounter) if ($ppu);
    UserBulkUpdate($hash, 'calcCounter_i', $pin, $iSum) if ($ppu);
    UserBulkUpdate($hash, 'seq', $pin, $seq);
    return;
}
  



#########################################################################
sub HandleRunTime {
    my ($hash, $pinName, $pin, $lastPower, $power) = @_;
    my $name  = $hash->{NAME};
    my $now   = int(gettimeofday());                                        # just work with seconds here 
    #Log3 $name, 5, "$name: HandleRunTime: power is $power";
    if ($power <= 0) {
        readingsDelete($hash, "runTime$pinName");
        readingsDelete($hash, "runTimeIgnore$pinName");
        readingsDelete($hash, ".switchOnTime$pinName");
        readingsDelete($hash, ".lastCheckIgnoreTime$pinName");
        return;
    }
    my $soTime = ReadingsVal($name, ".switchOnTime$pinName", 0);            # start time when power was >0 for the first time since it is >0
    if (!$soTime || !$lastPower) {
        $soTime = $now;
        readingsBulkUpdate($hash, ".switchOnTime$pinName", $now);           # save when consumption started
        readingsDelete($hash, "runTime$pinName");
        Log3 $name, 5, "$name: HandleRunTime: start from zero consumption - reset runtime and update .switchOnTime";
    }

    # check if an ignore device is on so runtime is not added currently
    my $doIgnore = 0;
    my $ignoreSpec = AttrValFromList($hash, "", "runTimeIgnore$pinName", "runTimeIgnore$pin");
    my @devices = devspec2array($ignoreSpec);
    #Log3 $name, 5, "$name: HandleRunTime: devices list is @devices";
    DEVICELOOP:
    foreach my $d (@devices) {
        my $state = (ReadingsVal($d, "state", ""));
        #Log3 $name, 5, "$name: HandleRunTime: check $d with state $state";
        if ($state =~ /1|on|open|BI/) {
            $doIgnore = 1;
            Log3 $name, 5, "$name: HandleRunTime: ignoreDevice $d is $state";
            last DEVICELOOP;
        }
    }

    my $iTime  = ReadingsVal($name, "runTimeIgnore$pinName", 0);            # time to ignore accumulated
    if ($doIgnore) {                                                        # ignore device is on
        my $siTime = ReadingsVal($name, ".lastCheckIgnoreTime$pinName",0);  # last time we saw ignore device on
        if ($siTime) {
            my $iAddTime = $now - $siTime;                                  # add to ignore time
            Log3 $name, 5, "$name: HandleRunTime: addiere $iAddTime auf ignoreTime $iTime";
            $iTime += $iAddTime;
            readingsBulkUpdate($hash, "runTimeIgnore$pinName", $iTime);     # remember time to ignore
        }
        #Log3 $name, 5, "$name: HandleRunTime: setze .lastCheckIgnoreTime auf now";
        readingsBulkUpdate($hash, ".lastCheckIgnoreTime$pinName", $now);    # last time we saw ignore device on
    } 
    else {                                                            
        Log3 $name, 5, "$name: HandleRunTime: no ignoreDevice is on, lösche .lastCheckIgnoreTime";
        readingsDelete($hash, ".lastCheckIgnoreTime$pinName");              # no ignore device is on -> remove marker for last time on
    }

    my $rTime = int($now - $soTime);                                        # time since water was switched on
    my $newRunTime = $rTime - $iTime;                                       # time since switch on minus ignore time
    Log3 $name, 5, "$name: HandleRunTime: runTime is now: $rTime - $iTime = $newRunTime";
    readingsBulkUpdate($hash, "runTime$pinName", $newRunTime);              # set new runtime reading
    return; 
}


#########################################################################
sub ParseReport {
    my ($hash, $line) = @_;
    my $name  = $hash->{NAME};
    my $now   = gettimeofday();
    if ($line =~ /^R(\d+) *C(\d+) *D(\d+) *[\/R](\d+) *T(\d+) *(N\d+,\d+)? *X(\d+)(?: *S(\d+))?(?: *A(\d+))?/)
    {
        # new count is beeing reported
        my ($pin, $count, $diff, $rDiff, $time, $dTime, $reject, $seq, $avgLen) =
            ($1, $2, $3, $4, $5, $6, $7, $8, $9);
        my $pinName = PinName($hash, $pin);
        my $power;      
        
        # first try with pinName, then pin Number, then generic fallback for all pins
        my $factor  = AttrValFromList($hash, 1000, "readingFactor$pinName", "readingFactor$pin", "factor");
        my $ppu     = AttrValFromList($hash, 0, "readingPulsesPerKWh$pinName", "readingPulsesPerKWh$pin", "pulsesPerKWh");
        $ppu        = AttrValFromList($hash, $ppu, "readingPulsesPerUnit$pin", "readingPulsesPerUnit$pinName", "pulsesPerUnit");
        my $fut     = AttrValFromList($hash, 3600, "readingFlowUnitTime$pin", "readingFlowUnitTime$pinName", "flowUnitTime");
        my $doRTime = AttrValFromList($hash, 0, "runTime$pinName", "runTime$pin");
        my $doSTime = AttrValFromList($hash, 0, "readingStartTime$pinName", "readingStartTime$pin");
        my $lName   = LogPinDesc($hash, $pin);
        my $pLog    = "$name: pin $pinName ($lName)";       # start of log lines              
        my $sTime   = $now - $time/1000;                    # start of interval (~first pulse) in secs (float)
        my $fSdTim  = FmtTime($sTime);                      # only time formatted for logging
        my $fEdTim  = FmtTime($now);                        # end of Interval - only time formatted for logging

        ParseTime($hash, $dTime, $now) if (defined($dTime));        # parse device time (old firmware, now line starting with N)
        
        if (!$time || !$factor) {
            Log3 $name, 3, "$pLog skip line because time or factor is 0: $line";
            return;
        }                                       
        
        if ($ppu) {                                     
            $power = ($diff/$time) * (1000 * $fut / $ppu);  # new calculation with pulses or rounds per unit (kWh)
        } 
        else {                                        
            $power = ($diff/$time) / 1000 * $fut * $factor; # old calculation with a factor that is hard to understand
        }
        my $powerFmt = sprintf ("%.3f", $power);
        
        Log3 $name, 4, "$pLog Cnt $count " . 
            "(diff $diff/$rDiff) in " . sprintf("%.3f", $time/1000) . "s" .
            " from $fSdTim until $fEdTim, seq $seq" . ((defined($reject) && $reject ne "") ? ", Rej $reject" : "") .
            (defined($avgLen) ? ", Avg ${avgLen}ms" : "") . (defined($ppu) ? ", PPU ${ppu}" : "") . 
            (defined($fut) ? ", FUT ${fut}s" : "") . ", result $powerFmt";   
        
        my $lastPower = UserReadingsVal($name, 'power', $pin);   # alter Power Wert
        readingsBeginUpdate($hash);
        UserBulkUpdate($hash, 'power', $pin, $powerFmt, ($doSTime ? $sTime : undef));

        #Log3 $name, 5, "$pLog last power $lastPower, power $power";
        HandleRunTime($hash, $pinName, $pin, $lastPower, $powerFmt) if ($doRTime);

        if (defined($reject) && $reject ne "") {
            my $rejCount = ReadingsVal($name, "reject$pinName", 0); # alter reject count Wert
            UserBulkUpdate($hash, 'reject', $pin, $reject + $rejCount);
        }
        UserBulkUpdate($hash, 'timeDiff', $pin, $time);     # used internally for interpolation
        UserBulkUpdate($hash, 'countDiff', $pin, $diff);    # used internally for interpolation
        UserBulkUpdate($hash, 'lastMsg', $pin, $line);
        
        HandleCounters($hash, $pin, $seq, $count, $time, $diff, $rDiff, $now, $ppu);
        readingsEndUpdate($hash, 1);
                    
        if (!$hash->{Initialized}) {                                # device sent count but no hello after reconnect
            Log3 $name, 3, "$name: device is still counting";
            if (!$hash->{WaitForHello}) {                           # if hello not already sent, send it now
                AskForHello("direct:$name");
            }
            RemoveInternalTimer ("sendHello:$name");                # don't send hello again
        }
    }
    return;
}


sub HandleHistory {
    my ($hash, $now, $pinName, $hist) = @_;
    my $name  = $hash->{NAME};
    my @hList = split(/, /, $hist);
    
    Log3 $name, 5, "$name: HandleHistory " . ($hash->{CL} ? "client $hash->{CL}{NAME}" : "no CL");
    
    foreach my $he (@hList) {
        if ($he) {
            if ($he =~ /(\d+)[s\,]([\d\-]+)[\/\:](\d+)\@([01])(?:\/(\d+))?(.)/) {
                my ($seq, $time, $len, $level, $alvl, $act) = ($1, $2, $3, $4, $5, $6);
                my $fTime = FmtDateTime($now + ($time/1000));
                my $action ="";
                if    ($act eq "C") {$action = "pulse counted"} 
                elsif ($act eq "G") {$action = "gap"} 
                elsif ($act eq "R") {$action = "short pulse reject"} 
                elsif ($act eq "X") {$action = "gap continued after ignored spike"} 
                elsif ($act eq "P") {$action = "pulse continued after ignored drop"} 
                my $histLine = "Seq " . sprintf ("%6s", $seq) . ' ' . $fTime . " Pin $pinName " . 
                    sprintf ("%7s", sprintf("%.3f", $len/1000)) . " seconds at $level" .
                    (defined($alvl) ? " (analog $alvl)" : "") . " -> $action";
                Log3 $name, 5, "$name: HandleHistory $histLine ($he)";
                $hash->{LastHistSeq} = $seq -1 if (!defined($hash->{LastHistSeq}));
                $hash->{HistIdx}     = 0 if (!defined($hash->{HistIdx}));
                if ($seq > $hash->{LastHistSeq} || $seq < ($hash->{LastHistSeq} - 10000)) {     # probably wrap
                    $hash->{History}[$hash->{HistIdx}] = $histLine;
                    $hash->{HistoryPin}[$hash->{HistIdx}] = $pinName;
                    $hash->{LastHistSeq} = $seq;
                    $hash->{HistIdx}++;
                }
                $hash->{HistIdx} = 0 if ($hash->{HistIdx} > AttrVal($name, "maxHist", 1000));
            } 
            else {
                Log3 $name, 5, "$name: HandleHistory - no match for $he";
            }
        }
    }
    return;
}


#########################################################################
sub Parse {
    my ($hash) = @_;
    my $name   = $hash->{NAME};
    my $retStr = "";
    
    my @lines = split /\n/, $hash->{buffer};
    my $now   = gettimeofday();
    
    foreach my $line (@lines) {
        $line =~ s/[\x0A\x0D]//g;
        #Log3 $name, 5, "$name: Parse line: #" . $line . "#";
        
        if ($line =~ /^ArduCounter V([\d\.]+).*(Started|Hello)/) {  # setup / hello message
            ParseHello($hash, $line, $now);        
        } 
        elsif ($line =~ /^(?:A|a|alive|Alive) *(?:(?:R|RSSI) *([\-\d]+))? *$/) {    # alive response
            my $rssi = $1;
            Log3 $name, 5, "$name: device sent alive response: $line" if (AttrVal($name, "logFilter", "N") =~ "N");
            RemoveInternalTimer ("alive:$name");
            delete $hash->{KeepAliveRetries};
            readingsSingleUpdate($hash, "RSSI", $rssi, 1) if ($rssi);            
        } 
        elsif ($line =~ /^R([\d]+)(.*)/) {                # report counters
            ParseReport($hash, $line);
            $retStr .= ($retStr ? "\n" : "") . "report for pin $1: $2";
        } 
        elsif ($line =~ /^C([0-9\,]+)/) {                 # available pins
            ParseAvailablePins($hash, $1);
            $retStr .= ($retStr ? "\n" : "") . "available pins: $1";
        } 
        elsif ($line =~ /^H([\d]+) (.+)/) {               # pin pulse history as separate line
            my $pin  = $1;
            my $hist = $2;
            my $pinName = PinName($hash, $pin);  
            HandleHistory($hash, $now, $pinName, $hist);
            if (AttrValFromList($hash, 0, "verboseReadings$pinName", "verboseReadings$pin") eq "1") {                    
                readingsSingleUpdate($hash, "pinHistory$pinName", $hist, 1);
            }
        } 
        elsif ($line =~ /^I(.*)/) {                       # interval config report after show/hello
            $retStr .= ($retStr ? "\n" : "") . "interval config: $1";
            $hash->{runningCfg}{I} = $1;                    # save for later compare
            $hash->{runningCfg}{I} =~ s/\s+$//;             # remove spaces at end
            Log3 $name, 4, "$name: device sent interval config $hash->{runningCfg}{I}";
        } 
        elsif ($line =~ /^U(.*)/) {                       # unit display config
            $retStr .= ($retStr ? "\n" : "") . "display unit config: $1";
            $hash->{runningCfg}{U} = $1;                    # save for later compare
            $hash->{runningCfg}{U} =~ s/\s+$//;             # remove spaces at end
            Log3 $name, 4, "$name: device sent unit display config $hash->{runningCfg}{U}";
        } 
        elsif ($line =~ /^V(.*)/) {                       # devVerbose
            $retStr .= ($retStr ? "\n" : "") . "verbose config: $1";
            $hash->{runningCfg}{V} = $1;                    # save for later compare
            $hash->{runningCfg}{V} =~ s/\s+$//;             # remove spaces at end
            Log3 $name, 4, "$name: device sent devVerbose $hash->{runningCfg}{V}";
        } 
        elsif ($line =~ /^P(\d+) *(f|falling|r|rising|-) *(p|pullup)? *(?:m|min)? *(\d+) *(?:(?:analog)? *(?:o|out|out-pin)? *(\d+) *(?:(?:t|thresholds) *(\d+) *[\/\, ] *(\d+))?)?(?:, R\d+.*)?/) {    # pin configuration at device
            my $p = ($3 ? $3 : "nop");
            $hash->{runningCfg}{$1} = $line;
            $retStr .= ($retStr ? "\n" : "") . "pin $1 config: $2 $p min length $4 " . ($5 ? "analog out $5 thresholds $6/$7" : "");
            Log3 $name, 4, "$name: device sent config for pin $1: $line"; 
        } 
        elsif ($line =~ /^N(.*)/) {                       # device time and boot time, track drift
            ParseTime($hash, $line, $now);
            $retStr .= ($retStr ? "\n" : "") . "device time $1";   
            Log3 $name, 4, "$name: device sent time info: $line";
        } 
        elsif ($line =~ /conn.* busy/) {
            my $now   = gettimeofday(); 
            my $delay = AttrVal($name, "nextOpenDelay", 60);  
            Log3 $name, 4, "$name: _Parse: primary tcp connection seems busy - delay next open";
            SetDisconnected($hash);                # set to disconnected (state), remove timers
            DevIo_CloseDev($hash);                          # close, remove from readyfnlist so _ready is not called again
            RemoveInternalTimer ("delayedopen:$name");
            InternalTimer($now+$delay, "ArduCounter::DelayedOpen", "delayedopen:$name", 0);
        # todo: the level reports should be recorded separately per pin
        } 
        elsif ($line =~ /^L\d+: *([\d]+) ?, ?([\d]+) ?, ?-> *([\d]+)/) { # analog level difference reported with details
            if ($hash->{analogLevels}{$3}) {
                $hash->{analogLevels}{$3}++;
            } else {
                $hash->{analogLevels}{$3} = 1;
            }
        } 
        elsif ($line =~ /^L\d+: *([\d]+)/) {          # analog level difference reported
            if ($hash->{analogLevels}{$1}) {
                $hash->{analogLevels}{$1}++;
            } else {
                $hash->{analogLevels}{$1} = 1;
            }  
        } 
        elsif ($line =~ /^Error:/) {                  # Error message from device
            $retStr .= ($retStr ? "\n" : "") . $line;  
            Log3 $name, 3, "$name: device: $line"; 
        } 
        elsif ($line =~ /^M (.*)/) {                  # other Message from device
            $retStr .= ($retStr ? "\n" : "") . $1;
            Log3 $name, 3, "$name: device: $1";
        } 
        elsif ($line =~ /^D (.*)/) {                  # debug / info Message from device
            $retStr .= ($retStr ? "\n" : "") . $1;
            Log3 $name, 4, "$name: device: $1"; 
        } 
        elsif ($line =~ /^[\s\n]*$/) {
            # blank line - ignore
        } 
        else {
            Log3 $name, 3, "$name: unparseable message from device: $line";
        }
    }
    $hash->{buffer} = "";
    return $retStr;
}



#########################################################################
# called from the global loop, when the select for hash->{FD} reports data
sub ReadFn {
    my $hash = shift;
    my $name = $hash->{NAME};
    my ($pin, $count, $diff, $power, $time, $reject, $msg);
    my $buf;

    if ($hash->{DeviceName} eq 'none') {            # simulate receiving
        if ($hash->{TestInput}) {
            $buf = $hash->{TestInput};
            delete $hash->{TestInput};
        }
    } 
    else {
        # read from serial device
        $buf = DevIo_SimpleRead($hash);      
        return if (!defined($buf) );
    }

    $hash->{buffer} .= $buf;    
    my $end = chop $buf;
    #Log3 $name, 5, "$name: Read: current buffer content: " . $hash->{buffer};

    # did we already get a full frame?
    return if ($end ne "\n");   
    Parse($hash);
    return;
}


#####################################
# Called from get / set to get a direct answer
# called with logical device hash
sub ReadAnswer {
    my ($hash, $expect) = @_;
    my $name   = $hash->{NAME};
    my $rin    = '';
    my $msgBuf = '';
    my $to     = AttrVal($name, "timeout", 2);
    my $buf;

    Log3 $name, 5, "$name: ReadAnswer called";  
    
    for(;;) {
        if ($hash->{DeviceName} eq 'none') {            # simulate receiving
            $buf = $hash->{TestInput};
            delete $hash->{TestInput};
        } 
        elsif($^O =~ m/Win/ && $hash->{USBDev}) {        
            $hash->{USBDev}->read_const_time($to*1000); # set timeout (ms)
            $buf = $hash->{USBDev}->read(999);
            if(length($buf) == 0) {
                Log3 $name, 3, "$name: Timeout in ReadAnswer";
                return ("Timeout reading answer", undef)
            }
        }
        else {
            if(!$hash->{FD}) {
                Log3 $name, 3, "$name: Device lost in ReadAnswer";
                return ("Device lost when reading answer", undef);
            }

            vec($rin, $hash->{FD}, 1) = 1;    # setze entsprechendes Bit in rin
            my $nfound = select($rin, undef, undef, $to);
            if($nfound < 0) {
                next if ($! == EAGAIN() || $! == EINTR() || $! == 0);
                my $err = $!;
                SetDisconnected($hash);                    # set to disconnected, remove timers, let _ready try to reopen
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
        $msgBuf .= Parse($hash);
        
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
=item summary Module for energy / water meters on arduino / ESP8266 / ESP32
=item summary_DE Modul für Strom / Wasserzähler mit Arduino, ESP8266 oder ESP32
=begin html

<a id="ArduCounter"></a>
<h3>ArduCounter</h3>

<ul>
    This module implements an Interface to an Arduino, ESP8266 or ESP32 based counter for pulses on any input pin of an Arduino Uno, Nano, Jeenode, 
    NodeMCU, Wemos D1, TTGO T-Display or similar device. <br>
    The device connects to Fhem either through USB / serial or via Wifi / TCP if an ESP board is used.<br>
    ArduCounter does not only count pulses but also measure pulse lenghts and the time between pulses so it can filter noise / bounces
    and gives better power/flow (Watts or liters/second) readings than systems that just count in fixed time intervals.<br>
    The number of pulses per kWh or liter is defineable and counters continue even when Fhem or the device restarts
    so you don't need additional user readings to make such calculations<br>
    The typical use case is an S0-Interface on an energy meter or water meter, but also reflection light barriers 
    to monitor old ferraris counters or analog water meters are supported<br>
    Counters are configured with attributes that define which GPIO pins should count pulses and in which intervals the board should report the current counts.<br>
    The sketch that works with this module uses pin change interrupts so it can efficiently count pulses on all available input pins.
    The module has been tested with 14 inputs of an Arduino Uno counting in parallel and pulses as short as 3 milliseconds.<br>
    The module creates readings for pulse counts, consumption and optionally also a pin history with pulse lengths and gaps of the last pulses.<br>
    If an ESP8266 or ESP32 is used, the device can be flashed and configured over Wifi (it opens its own temporary Hotspot / SSID for configuration 
    so you can set which existing SSID to connect to and which password to use). For TTGO T-Display boards (ESP32 with TFT display) 
    the local display on the device itself can also display Wifi status and current consumption.<br>
    <br>
    <b>Prerequisites</b>
    <ul>
        <br>
        <li>
            This module requires an Arduino Uno, Nano, Jeenode, NodeMCU, Wemos D1, TTGO T-Display or similar device based on an Atmel 328p, ESP8266 or ESP32 
            running the ArduCounter sketch provided with this module<br>
            In order to flash an arduino board with the corresponding ArduCounter firmware from within Fhem, avrdude needs to be installed.<br>
            To flash ESP32 or ESP8266 boards form within Fhem, Python and the scripts esptool.py / espota.py need to be installed.<br>
            For old ferraris counters a reflection light barrier which in the simpest case can consist of a photo transistor (connected to an anlalog input of the Arduino / ESP)  
            and an led or a laser module (connected to a digital output), both with a resistor in line are needed. 
            To drive a laser module with 5V, another transistor is typically needed to switch 5V from a 3.3V GPIO output.
        </li>
    </ul>
    <br>

    <a id="ArduCounter-define"></a>
    <b>Define</b>
    <ul>
        <br>
        <code>define &lt;name&gt; ArduCounter &lt;device&gt;</code><br>
        or<br>
        <code>define &lt;name&gt; ArduCounter &lt;ip:port&gt;</code><br>
        <br>
        &lt;device&gt; specifies the serial port to communicate with the Arduino.<br>
        &lt;ip:port&gt; specifies the ip address and tcp port to communicate with an esp8266 / ESP32 where port is typically 80.<br>
        
        The name of the serial device depends on your distribution and serial adapter.<br>
        You can also specify a baudrate for serial connections if the device name contains the @ character, e.g.: /dev/ttyUSB0@115200<br>
        The default baudrate of the ArduCounter firmware is 115200 since sketch version 4 and used to be 38400 since sketch version 1.4<br>
        The latest version of this module will however try different baudrates automatically if communication with the counting device seems not possible.
        <br>
        Example:<br>
        <br>
        <ul><code>define AC ArduCounter /dev/ttyUSB2@115200</code></ul>
        <ul><code>define AC ArduCounter 192.168.1.134:80</code></ul>
    </ul>
    <br>

    <a id="ArduCounter-configuration"></a>
    <b>Configuration of ArduCounter digital counters</b><br><br>
    <ul>
        Specify the pins where impulses should be counted e.g. as <code>attr AC pinX falling pullup min 25</code> <br>
        The X in pinX can be an Arduino / ESP GPIO pin number with or without the letter D e.g. pin4, pinD5, pin6, pinD7 ...<br>
        After the pin you can use the keywords falling or rising to define if a logical one / 5V (rising) or a logical zero / 0V (falling) should be treated as pulse.<br>
        The optional keyword pullup activates the pullup resistor for the given Pin. <br>
        The last argument is also optional but recommended and specifies a minimal pulse length in milliseconds.<br>
        An energy meter with S0 interface is typically connected to GND and an input pin like D4. <br>
        The S0 pulse then pulls the input down to 0V.<br>
        Since the minimal pulse lenght of an S0 interface is specified to be 30ms, the typical configuration for an s0 interface is <br>
        <code>attr AC pinX falling pullup min 25</code><br>
        Specifying a minimal pulse length is recommended since it filters bouncing of reed contacts or other noise. 
        The keyword <code>min</code> before <code>25</code> is optional.
        <br><br>
        Example:<br>
        <pre>
        define AC ArduCounter /dev/ttyUSB2
        attr AC pulsesPerUnit 1000
        attr AC interval 60 300
        attr AC pinD4 falling pullup min 5
        attr AC pinD5 falling pullup min 25
        attr AC pinD6 rising
        </pre>        
        This defines a counter that is connected to Fhem via serial line ttyUSB2 with three counters connected to the GPIO pins D4, D5 and D5. <br>
        D4 and D5 have their pullup resistors activated and the impulses draw the pins to zero.<br>
        For D4 and D5 the board measures the time in milliseconds between the falling edge and the rising edge. 
        If this time is longer than the specified 5 (or 25 for pin D5) milliseconds then the impulse is counted. <br>
        If the time is shorter then this impulse is regarded as noise and added to a separate reject counter.<br>
        For pin D6 the board uses a default minimal length of 2ms and counts every time when the signal changes from 1 (rising pulse) back to 0.
    </ul>
    <br>
    
    <b>Configuration of ArduCounter analog counters</b><br><br>
    <ul>
        This module and the corresponding ArduCounter sketch can be used to read water meters or old analog ferraris energy counters.<br> 
        Therefore a reflection light barrier needs to be connected to the board. This might simply consist of an infra red photo transistor 
        (connected to an analog input) and an infra red led (connected to a digital output), both with a resistor in line. 
        The idea comes from Martin Kompf (https://www.kompf.de/tech/emeir.html) and has been adopted for ArduCounter to support 
        old ferraris energy counters or water meters.<br>
        The configuration is then similar to the one for digital counters:<br>
        <pre>
        define WaterMeter ArduCounter 192.168.1.110:80
        attr ACF pinA0 rising pullup min 4 analog out 27 threshold 120,220
        attr ACF interval 5,60,2,15,10,3
        attr ACF pulsesPerUnit 35
        attr ACF stateFormat {sprintf("%.3f l/min", ReadingsVal($name,"powerA0",0))}
        </pre>
        In this case an analog GPIO pin is used as input and the normal configuration parameters are followed by the keyword 
        <code>analog out</code> or simply <code>out</code>, the gpio number of a GPIO output that connects a light source and the thresholds 
        that decide when an analog input value is regarded as "low" or "high".

        In the example an ESP32 is used via Wifi connection. GPIO pin A0 is used as analog input and is connected to a photo transistor that senses the intensity of light.
        GPIO 27 is used as LED output and switched on/off in a high frequency. On GPIO A0 the reflected light is measured 
        and the difference in a measurement between when the LED is off and when the LED is on is compared to the thresholds defined in the pinA0-attribute. 
        When the measured light difference is above <code>220</code>, then a pulse starts (since <code>rising</code> is specified). 
        When the measured difference is below <code>120</code> then the pulse ends.<br>
        <br>
        The attribute <code>interval</code> has the following meaning in the above example: 
        The device reports the current counts and the time difference beween the first and the last pulse if at least 2 pulses have been counted 
        and if they are more than 15 milliseconds apart form each other. If not, then the device continues counting. 
        If after 60 seconds these conditions are stil not met, then the device will report the current count anyways and use the current time as the end of the interval.<br>
        The last two numbers of the <code>interval</code> attribute define that the device will read the analog input 3 times and then work with the average. 
        Between each analog measurement series there will be a delay of 10 milliseconds.<br>
        <br>
        The attribute <code>pulsesPerUnit 35</code> defines that 35 pulses correspond to one unit (e.g. liter) and the reading <code>calcCounterA0</code> 
        is increased by the reported raw counts divided by 35.<br>
        To find out the right analog thresholds you can set the attribute <code>enableHistory</code> to 1 which will ask the firmware of your counting board 
        to report the average difference measurements before they are compared to a threshold. 
        The ArduCounter module will count how often each value is reported and you can then query these analog level counts with <code>get levels</code>. 
        After a few measuremets the result of <code>get levels</code> might look like this:<br>
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
        This shows the measured values together with the frequency how often the individual value has been measured. 
        It is obvious that most measurements result in values between 120 and 135, very few values are betweem 96 and 115 
        and another peak is around the value 95. <br>
        It means that in the example of a ferraris energy counter, when the red mark of the ferraris disc is under the sensor, 
        the value is around 95 and while when the blank disc is under the sensor, the value is typically between 120 and 135. 
        So a good upper threshold would be 120 and a good lower threshold would be for example 96.
        
    </ul>
    <br>

    <a id="ArduCounter-set"></a>
    <b>Set-Commands</b><br>
    <ul>
        <li><b>raw</b></li> 
            send the value to the board so you can directly talk to the sketch using its commands.<br>
            This is not needed for normal operation but might be useful sometimes for debugging
        <li><b>flash [&lt;file&gt;]</b></li> 
            flashes the ArduCounter firmware from the subdirectory FHEM/firmware onto the device.<br>
            Normally you can just specify <code>set myDevice flash</code>. The parameter &lt;file&gt; is optional and allows specifying an alternative firmware file.
            The attribute flashCommand can be used to override which command is executed. 
            If the attribute flashCommand is not specified then the module selects an appropriate command depending on the board type 
            (set with the attribute <code>board</code>) and depending on the connection (serial or Wifi).<br>
            For an arduino NANO for example the module would execute avrdude (which has to be installed of course) 
            and flash the connected arduino with the updated hex file <br>
            (by default it looks for ArduCounter.hex in the FHEM/firmware subdirectory).<br>
            For an Arduino UNO for example the default is <code>avrdude -p atmega328P -c arduino -P [PORT] -D -U flash:w:[HEXFILE] 2>[LOGFILE]</code><br>
            For an Arduino Nano based counter <code>-b 57600</code> is added.<br>
            For an ESP32 connected via Wifi, the module would call espota.py which will upload the firmware over the air.<br>
            If the attribute flashCommand is not specified for an ESP32 based board connected via serial line, then the module uses the command 
            <code>
                esptool.py --chip esp32 --port [PORT] --baud 460800 --before default_reset --after hard_reset write_flash -z 
                --flash_mode dio --flash_freq 40m --flash_size detect 
                0x1000 FHEM/firmware/ArduCounter_ESP32_bootloader_dio_40m.bin 
                0x8000 FHEM/firmware/ArduCounter_ESP32_partitions.bin
                0xe000  FHEM/firmware/ArduCounter_ESP32_boot_app0.bin 
                0x10000 FHEM/firmware/ArduCounter_ESP32_firmware.bin >[LOGFILE] 2>&1
            </code> for example which flashes the whole ESP32 with all the partitions. <br>
            For over the air flashing it would use 
            <code> espota.py -i[IP] -p [NETPORT] -f [BINFILE] 2>[LOGFILE]</code>.<br>
            Of course esptool.py or espota.py as well as python would need to be installed on the system.
            
        <li><b>resetWifi</b></li> 
            reset Wifi settings of the counting device so the Wifi Manager will come up after the next reset to select a wireless network and enter the Wifi passphrase.
        <li><b>reset</b></li> 
            sends a command to the device which causes a hardware reset or reinitialize and reset of the internal counters of the board. <br>
            The module then reopens the counting device and resends the attribute configuration / definition of the pins.
        <li><b>saveConfig</b></li> 
            stores the current interval, analog threshold and pin configuration in the EEPROM of the counter device so it will automatically be retrieved after a reset.
        <li><b>enable</b></li> 
            sets the attribute disable to 0
        <li><b>disable</b></li> 
            sets the attribute disable to 1
        <li><b>reconnect</b></li> 
            closes the tcp connection to an ESP based counter board that is conected via TCP/IP and reopen the connection
        <li><b>clearLevels</b></li> 
            clears the statistics for analog levels. This is only relevant if you use the board to read via a reflective light barrier 
            and you want to set the thresholds according to the statistics.            
        <li><b>clearCounters &lt;pin&gt;</b></li> 
            resets all the counter readings for the specified pin to 0
        <li><b>counter &lt;pin&gt;, &lt;value&gt;</b></li> 
            set the calcCounter reading for the specified pin to the given value
        <li><b>clearHistory</b></li> 
            deletes all the cached pin history entries
    </ul>
    <br>
    <a id="ArduCounter-get"></a>
    <b>Get-Commands</b><br>
    <ul>
        <li><b>info</b></li> 
            send a command to the Arduino board to get current counts.<br>
            This is not needed for normal operation but might be useful sometimes for debugging
        <li><b>levels</b></li> 
            show the count for the measured levels if an analog pin is used to measure e.g. the red mark of a ferraris counter disc. This is useful for setting the thresholds for analog measurements.  
        <li><b>history &lt;pin&gt;</b></li> 
            shows details regarding all the level changes that the counter device (Arduino or ESP) has detected and how they were used (counted or rejected)<br>
            If get history is issued with a pin name (e.g. get history D5) then only the history entries concerning D5 will be shown.<br>
            This information is sent from the device to Fhem if the attribute <code>enableHistory</code> is set to 1.<br>
            The maximum number of lines that the Arducounter module stores in a ring buffer is defined by the attribute maxHist and defaults to 1000.
    </ul>
    <br>
    <a id="ArduCounter-attr"></a>
    <b>Attributes</b><br><br>
    <ul>
        <li><a href="#do_not_notify">do_not_notify</a></li>
        <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
        <br>
		<li><a id="ArduCounter-attr-pin" data-pattern="pin.*">pin[AD]?[0-9]+&lt;rising|falling&gt; [&lt;pullup&gt;] [min] &lt;min length&gt; [[analog] out &lt;out pin&gt; [threshold] &lt;min, max&gt;]</a><br> 
            Define a GPIO pin of the Arduino or ESP board as input. This attribute expects for digital inputs either 
            <code>rising</code> or <code>falling</code>, followed by an optional <code>pullup</code> and the optional keyword <code>min</code> 
            and an optional number as minimal length of pulses and gaps between pulses.<br>
            The counter device will track rising and falling edges of each impulse and measure the length of a pulse in milliseconds.<br>
            The minimal length specified here is the minimal duration of a pulse and a pause before a pulse. If one is too small, 
            the pulse is not counted but added to a separate reject counter.<br>
            Example:<br>
            <pre>
            attr MyCounter pinD4 falling pullup 25
            </pre>
            For analog inputs with connected reflective light barries, you have to add <code>analog out</code> 
            and the GPIO pin number of the pin where the light source (LED or laser) is connected, the keyword <code>threshold</code> 
            followed by the lower and upper threshold separated by a komma.<br>
            Example:<br>
            <pre>
            attr MyCounter pinA0 rising pullup min 3 analog out 27 threshold 120,220
            </pre>
        </li>
        <li><a id="ArduCounter-attr-interval">interval &lt;normal&gt; &lt;max&gt; [&lt;min&gt; &lt;min count&gt; [&lt;analog interval&gt; &lt;analog samples&gt;]]</a><br> 
            Defines the parameters that affect the way counting and reporting works.
            This Attribute expects at least two and a maximum of six numbers as value. 
            The first is the normal interval, the second the maximal interval, the third is a minimal interval and the fourth is a minimal pulse count. 
            The last two numbers are only needed for counting with reflective light barriers. They specify the delay between the measurements 
            and the number of samples for each measurement.
            <br><br>
            In the usual operation mode (when the normal interval is smaller than the maximum interval),
            the Arduino board just counts and remembers the time between the first impulse and the last impulse for each pin.<br>
            After the normal interval is elapsed the Arduino board reports the count and time for those pins where impulses were encountered.<br>
            This means that even though the normal interval might be 10 seconds, the reported time difference can be 
            something different because it observed impulses as starting and ending point.<br>
            The Power (e.g. for energy meters) is then calculated based of the counted impulses and the time between the first and the last impulse. <br>
            For the next interval, the starting time will be the time of the last impulse in the previous reporting period 
            and the time difference will be taken up to the last impulse before the reporting interval has elapsed.
            <br><br>
            The second, third and fourth numbers (maximum, minimal interval and minimal count) exist for the special case 
            when the pulse frequency is very low and the reporting time is comparatively short.<br>
            For example if the normal interval (first number) is 60 seconds and the device counts only one impulse in 90 seconds, 
            the the calculated power reading will jump up and down and will give ugly numbers.<br>
            By adjusting the other numbers of this attribute this can be avoided.<br>
            In case in the normal interval the observed impulses are encountered in a time difference that is smaller than the third number (minimal interval) 
            or if the number of impulses counted is smaller than the fourth number (minimal count) then the reporting is delayed until the maximum interval has elapsed 
            or the above conditions have changed after another normal interval.<br>
            This way the counter will report a higher number of pulses counted and a larger time difference back to fhem. <br>
            Example:<br>
            <pre>
            attr myCounter interval 60 600 5 2
            </pre><br>
            If this is seems too complicated and you prefer a simple and constant reporting interval, then you can set the normal interval and the mximum interval to the same number. 
            This changes the operation mode of the counter to just count during this normal and maximum interval and report the count. 
            In this case the reported time difference is always the reporting interval and not the measured time between the real impulses.
            <br><br>
            For analog sampling the last two numbers define the delay in milliseconds between analog measurements and the number of samples that will be taken as one mesurement.
        </li>
		<li><a id="ArduCounter-attr-board">board</a><br> 
            specify the type of the board used for ArduCounter like NANO, UNO, ESP32, ESP8266 or T-Display<br>
            Example:
            <pre>
            attr myCounter board NANO
            </pre>
        </li>
		<li><a id="ArduCounter-attr-pulsesPerUnit" data-pattern="pulsesPer.*">pulsesPerUnit &lt;number&gt;</a><br> 
            specify the number of pulses that the meter is giving out per unit that sould be displayed (e.g. per kWh energy consumed). <br>
            For many S0 counters this is 1000, for old ferraris counters this is 75 (rounds per kWh).<br>
            This attribute used to be called pulsesPerKWh and this name still works but the new name should be used preferably since the old one could be removed in future versions.<br>
            Example:
            <pre>
            attr myCounter pulsesPerUnit 75
            </pre>
        </li>
		<li><a id="ArduCounter-attr-readingPulsesPerUnit" data-pattern="readingPulsesPer.*">readingPulsesPerUnit[AD]?[0-9]+ &lt;number&gt;</a><br> 
            is the same as pulsesPerUnit but specified per GPIO pin individually in case you have multiple counters with different settings at the same time<br>
            This attribute used to be called readingPulsesPerKWh[AD]?[0-9]+ and this name still works but the new name should be used preferably 
            since the old one could be removed in future versions.<br>
            <br>
            Example:<br>
            <pre>
            attr myCounter readingPulsesPerUnitA7 75<br>
            attr myCounter readingPulsesPerUnitD4 1000
            </pre>

        </li>
		<li><a id="ArduCounter-attr-readingFlowUnitTime" data-pattern="readingFlowUnitTime.*">readingFlowUnitTime[AD]?[0-9]+ &lt;time&gt;</a><br> 
            specified the time period in seconds which is used as the basis for calculating the current flow or power for the given pin.<br>
            If the counter e.g. counts liters and you want to see the flow in liters per minute, then you have to set this attribute to 60.<br>
            If you count kWh and you want to see the current power in kW, then specify 3600 (one hour).<br>
            Since this attribute is just used for multiplying the consumption per second, you can also use it to get watts 
            instead of kW by using 3600000 instead of 3600.

        </li>
		<li><a id="ArduCounter-attr-flowUnitTime" data-pattern="flowUnitTime">flowUnitTime &lt;time&gt;</a><br> 
            like readingFlowUnitTimeXX but applies to all pins that have no explicit readingFlowUnitTimeXX attribute.

        </li>
		<li><a id="ArduCounter-attr-readingNameCount" data-pattern="readingNameCount">readingNameCount[AD]?[0-9]+ &lt;new name&gt;</a><br> 
            Change the name of the counter reading pinX to something more meaningful. <br>
            Example:
            <pre>
            attr myCounter readingNameCountD4 CounterHaus_internal
            </pre>
        </li>
		<li><a id="ArduCounter-attr-readingNameLongCount" data-pattern="readingNameLongCount">readingNameLongCount[AD]?[0-9]+ &lt;new name&gt;</a><br> 
            Change the name of the long counter reading longX to something more meaningful.<br>
            Example:
            <pre>
            attr myCounter readingNameLongCountD4 CounterHaus_long
            </pre>
            
        </li>
		<li><a id="ArduCounter-attr-readingNameInterpolatedCount" data-pattern="readingNameInterpolatedCount">readingNameInterpolatedCount[AD]?[0-9]+ &lt;new name&gt;</a><br> 
            Change the name of the interpolated long counter reading InterpolatedlongX to something more meaningful.<br>
            Example:
            <pre>
            attr myCounter readingNameInterpolatedCountD4 CounterHaus_interpolated
            </pre>
            
        </li>
		<li><a id="ArduCounter-attr-readingNameCalcCount" data-pattern="readingNameCalcCount">readingNameCalcCount[AD]?[0-9]+ &lt;new name&gt;</a><br> 
            Change the name of the real unit counter reading CalcCounterX to something more meaningful.<br>
            Example:
            <pre>
            attr myCounter readingNameCalcCountD4 CounterHaus_kWh
            </pre>
            
        </li>
		<li><a id="ArduCounter-attr-readingNamePower" data-pattern="readingNamePower">readingNamePower[AD]?[0-9]+ &lt;new name&gt;</a><br> 
            Change the name of the power reading powerX to something more meaningful.<br>
            Example:
            <pre>
            attr myCounter readingNamePowerD4 PowerHaus_kW
            </pre>
            
        </li>
		<li><a id="ArduCounter-attr-readingStartTime" data-pattern="readingStartTime">readingStartTime[AD]?[0-9]+ [0|1]</a><br> 
            Allow the reading time stamp to be set to the beginning of measuring intervals. 
            This is a hack where the timestamp of readings is artificially set to a past time and may have side effects 
            so avoid it unless you fully understand how Fhem works with readings and their time.
            
        </li>
		<li><a id="ArduCounter-attr-verboseReadings" data-pattern="verboseReadings">verboseReadings[AD]?[0-9]+ [0|1]</a><br> 
            create the additional readings lastMsg and pinHistory for each pin<br>
            if verboseReafings is set to 1 for the specified pin.<br>
            If set to -1 then the internal counter, the long counter and interpolated long counter readings will be hidden.<br>
            Example:
            <pre>
            attr myCounter verboseReadingsD4 1
            </pre>
            
        </li>
		<li><a id="ArduCounter-attr-enableHistory" data-pattern="enableHistory">enableHistory [0|1]</a><br>
            tells the counting device to record the individual time of each change at each GPIO pin and send it to Fhem. 
            This information is cached on the Fhem side and can be viewed with the command <code>get history</code>
            The optput of <code>get history</code> will look like this:
            <pre>
                Seq  12627 2020-03-22 20:39:54 Pin D5   0.080 seconds at 0 -> pulse counted
                Seq  12628 2020-03-22 20:39:55 Pin D5   1.697 seconds at 1 -> gap
                Seq  12629 2020-03-22 20:39:56 Pin D5   0.080 seconds at 0 -> pulse counted
                Seq  12630 2020-03-22 20:39:56 Pin D5   1.694 seconds at 1 -> gap
                Seq  12631 2020-03-22 20:39:58 Pin D5   0.081 seconds at 0 -> pulse counted
                Seq  12632 2020-03-22 20:39:58 Pin D5   1.693 seconds at 1 -> gap
                Seq  12633 2020-03-22 20:40:00 Pin D5   0.081 seconds at 0 -> pulse counted
                Seq  12634 2020-03-22 20:40:00 Pin D5   1.696 seconds at 1 -> gap
                Seq  12635 2020-03-22 20:40:02 Pin D5   0.081 seconds at 0 -> pulse counted
                Seq  12636 2020-03-22 20:40:02 Pin D5   1.699 seconds at 1 -> gap
                Seq  12637 2020-03-22 20:40:03 Pin D5   0.079 seconds at 0 -> pulse counted
                Seq  12638 2020-03-22 20:40:03 Pin D5   1.700 seconds at 1 -> gap
                Seq  12639 2020-03-22 20:40:05 Pin D5   0.080 seconds at 0 -> pulse counted
                Seq  12642 2020-03-22 20:40:05 Pin D5   1.699 seconds at 1 -> gap
                Seq  12643 2020-03-22 20:40:07 Pin D5   0.080 seconds at 0 -> pulse counted
                Seq  12644 2020-03-22 20:40:07 Pin D5   1.698 seconds at 1 -> gap            
            </pre>

        </li>
		<li><a id="ArduCounter-attr-enableSerialEcho" data-pattern="enableSerialEcho">enableSerialEcho [0|1]</a><br> 
            tells the counting device to show diagnostic data over the serial line when connected via TCP
            
        </li>
		<li><a id="ArduCounter-attr-enablePinDebug" data-pattern="enablePinDebug">enablePinDebug [0|1]</a><br> 
            tells the counting device to show every level change of the defined input pins over the serial line or via TCP
        </li>
		<li><a id="ArduCounter-attr-enableAnalogDebug" data-pattern="enableAnalogDebug">enableAnalogDebug [0|1]</a><br> 
            tells the counting device to show every analog measurement of the defined analog input pins over the serial line or via TCP
        </li>
		<li><a id="ArduCounter-attr-enableDevTime" data-pattern="enableDevTime">enableDevTime [0|1]</a><br> 
            tells the counting device to show its internal millis timer so a drift between the devices time and fhem time can be calculated and logged

        </li>
		<li><a id="ArduCounter-attr-maxHist" data-pattern="maxHist">maxHist &lt;max entries&gt;</a><br> 
            specifies how many pin history lines hould be buffered for "get history".<br>
            This attribute defaults to 1000.
            
        </li>
		<li><a id="ArduCounter-attr-analogThresholds" data-pattern="analogThresholds">analogThresholds</a><br> 
            this Attribute is outdated. Please specify the analog thresholds for reflective light barrier input with the attribute "pin..."
        
        </li>
		<li><a id="ArduCounter-attr-flashCommand" data-pattern="flashCommand">flashCommand &lt;new shell command&gt;</a><br> 
            overrides the default command to flash the firmware via Wifi (OTA) or serial line. It is recommended to not define this attribute. <br>
            Example:
            <pre>            
            attr myCounter flashCommand avrdude -p atmega328P -c arduino -b 57600 -P [PORT] -D -U flash:w:[HEXFILE] 2>[LOGFILE]
            </pre>
            <code>[PORT]</code> is automatically replaced with the serial port for this device as it is specified in the <code>define</code> command.<br>
            <code>[HEXFILE]</code> or <code>[BINFILE]</code> are synonyms and are both automatically replaced with the firmware file appropriate for the device. 
            For ESP32 boards <code>[HEXFILE]</code> would be replaced by ArduCounter-8266.bin for example.<br>
            <code>[LOGFILE]</code> is automatically replaced ArduCounterFlash.log in the fhem log subdirectory.<br>
            <code>[NETPORT]</code> is automatically replaced by the tcp port number used for OTA flashing. 
            For ESP32 this usually is 3232 and for 8266 Bords it is 8266.<br>
            
        </li>
		<li><a id="ArduCounter-attr-keepAliveDelay" data-pattern="keepAliveDelay">keepAliveDelay &lt;delay&gt;</a><br> 
            defines an interval in which the module sends keepalive messages to a counter device that is conected via tcp.<br>
            This attribute is ignored if the device is connected via serial port.<br>
            If the device doesn't reply within a defined timeout then the module closes and tries to reopen the connection.<br>
            The module tells the device when to expect the next keepalive message and the device will also close the tcp connection if it doesn't see a keepalive message within the delay multiplied by 3<br>
            The delay defaults to 10 seconds.<br>
            Example:
            <pre>
            attr myCounter keepAliveDelay 30
            </pre>            
            
        </li>
		<li><a id="ArduCounter-attr-keepAliveTimeout" data-pattern="keepAliveTimeout">keepAliveTimeout &lt;seconds&gt;</a><br> 
            defines the timeout when wainting for a keealive reply (see keepAliveDelay)
            The timeout defaults to 2 seconds.<br>
            Example:
            <pre>
            attr myCounter keepAliveTimeout 3
            </pre>            
        </li>
		<li><a id="ArduCounter-attr-keepAliveRetries" data-pattern="keepAliveRetries">keepAliveRetries &lt;max number of retries&gt;</a><br> 
            defines how often sending a keepalive is retried before the connection is closed and reopened.<br>
            It defaults to 2.<br>
            Example:
            <pre>
            attr myCounter keepAliveRetries 3
            </pre>            
        </li>
		<li><a id="ArduCounter-attr-nextOpenDelay" data-pattern="nextOpenDelay">nextOpenDelay &lt;delay&gt;</a><br> 
            defines the time in seconds that the module waits before retrying to open a disconnected tcp connection. <br>
            This defaults to 60 seconds.<br>
            Example:
            <pre>
            attr myCounter nextOpenDelay 20
            </pre>            
        </li>
		<li><a id="ArduCounter-attr-openTimeout" data-pattern="openTimeout">openTimeout &lt;timeout&gt;</a><br> 
            defines the timeout in seconds after which tcp open gives up trying to establish a connection to the counter device.
            This timeout defaults to 3 seconds.<br>
            Example:
            <pre>
            attr myCounter openTimeout 5
            </pre>            
        </li>
		<li><a id="ArduCounter-attr-silentReconnect" data-pattern="silentReconnect">silentReconnect [0|1]</a><br> 
            if set to 1, then it will set the loglevel for "disconnected" and "reappeared" messages to 4 instead of 3<br>
            Example:
            <pre>
            attr myCounter silentReconnect 1
            </pre>            
        </li>
        <li><a id="ArduCounter-attr-deviceDisplay">deviceDisplay &lt;pin&gt; &lt;unit&gt; &lt;flowUnit&gt;</a><br>
            controls the unit strings that a local display on the counting device will show. <br> 
            Example:
            <pre>
            attr myCounter deviceDisplay 36,l,l/m
            attr myCounter deviceDisplay 36,kWh,kW
            </pre>      
        </li>
		<li><a id="ArduCounter-attr-disable" data-pattern="disable">disable [0|1]</a><br> 
            if set to 1 then the module is disabled and closes the connection to a counter device.<br>
        </li>
		<li><a id="ArduCounter-attr-factor">factor</a><br> 
            Define a multiplicator for calculating the power from the impulse count and the time between the first and the last impulse. <br>
            This attribute is outdated and unintuitive so you should avoid it. <br>
            Instead you should specify the attribute pulsesPerUnit or readingPulsesPerUnit[0-9]+ (where [0-9]+ stands for the pin number).
        </li>
		<li><a id="ArduCounter-attr-readingFactor" data-pattern="readingFactor.*">readingFactor[AD]?[0-9]+</a><br> 
            Override the factor attribute for this individual pin. <br>
            Just like the attribute factor, this is a rather cumbersome way to specify the pulses per kWh. <br>
            Instead it is advised to use the attribute pulsesPerUnit or readingPulsesPerUnit[0-9]+ (where [0-9]+ stands for the pin number).
        </li>
		<li><a id="ArduCounter-attr-runTime" data-pattern="runTime">runTime[AD]?[0-9]+</a><br> 
            if this attribute is set for a pin, then a new reading will be created which accumulates the run time for this pin while consumption is greater than 0.<br>
            This allows e.g. to check if a water meter shows water consumption for a time longer than X without stop.
        </li>
		<li><a id="ArduCounter-attr-runTimeIgnore" data-pattern="runTimeIgnore">runTimeIgnore[AD]?[0-9]+</a><br> 
            this allows to ignore consumption for the run time attribute while a certain other device is switched on.
        </li>
		<li><a id="ArduCounter-attr-devVerbose">devVerbose</a><br> 
            this attribute is outdated and has been replaced with the attributes 
            <code>enableHistory, enableSerialEcho, enablePinDebug, enableAnalogDebug, enableDevTime</code>
        </li>
		<li><a id="ArduCounter-attr-configDelay">configDelay</a><br> 
            specify the time to wait for the board to report its configuration before Fhem sends the commands to reconfigure the board 
        </li>
		<li><a id="ArduCounter-attr-helloSendDelay">helloSendDelay</a><br> 
            specify the time to wait for the board to report its type before Fhem sends the commands to ask for it 
        </li>
		<li><a id="ArduCounter-attr-helloWaitTime">helloWaitTime</a><br> 
            specify the time to wait for the board to report its type when Fhem has asked for it before a timeout occurs 
        </li>
    </ul>
    <br>
    <b>Readings / Events</b><br>
    <ul>
        The module creates at least the following readings and events for each defined pin:
        <li><b>calcCounter.*</b></li>  
            This is recommended reading for counting units based on the pulses and the attribute pulsesPerUnit. It is similar to interpolated long count 
            which keeps on counting up after fhem restarts but this counter will take the pulses per Unit attribute into the calculation und thus does not 
            count pulses but real Units (kWh, liters or some other unit that is applicable)<br>
            The name of this reading can be changed with the attribute readingNameCalcCount[AD]?[0-9]+ where [AD]?[0-9]+ stands for the pin description e.g. D4.<br>
			Another reading with the same name but ending in _i (e.g. calcCounterD4_i) will show how many kWh (or other units) of the above value is interpolated.

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
            the current calculated power / flow at this pin.<br>
            The name of this reading can be changed with the attribute readingNamePower[AD]?[0-9]+ where [AD]?[0-9]+ stands for the pin description e.g. D4.<br>
            This reading depends on the attributes pulsesPerUnit as well as readingFlowUnitTime or flowUnitTime for calculation 
            
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
        <li><b>runTime.*</b></li> 
            this reading will only be created when the attribute runTime[AD]?[0-9]+ is set for a given pin.<br>
            It contains the time in seconds that the consumption / flow observed at the specified pin has not ben zero.<br>
            If a water meter which outputs 10 impulses per liter on its digital output is for example connected to GPIO pin D6, 
            then if the attribute runTimeD6 is set to 1, the reading runTimeD6 will show for how many seconds the water has been flowing without a stop longer than the 
            observation interval specifie in the interval-attribute. This is helpful when you want to create alerts in case someone forgot to close a water tap.<br>
    </ul>           
    <br>
</ul>

=end html
=cut

