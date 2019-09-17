##############################################################################
# $Id$
#
# fhem Modul für Geräte mit Modbus-Interface - 
# Basis für logische Geräte-Module wie zum Beispiel ModbusSET.pm
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
#   2014-07-07  initial version
#   2015-01-25  optimized many details, changed some function parameters, moved fCodeMap to the 
#               logical device, changed the meaning of the type charaters in fCodeMap 
#               (holding register is now h instead of r, discrete is d and input register is i)
#               added fcode 4
#   2015-01-26  added fcode 16 for writing multiple registers at once (to be tested carefully!)
#               (if the device supports it and it is put it in the fcode Map at the client module)
#               added parseInfo key format, corrected the packing of data types 
#               (now use the unpack code defined in the parseInfo hash)
#   2015-01-27  defLen im Modul-hash des logischen Moduls als Default
#   2015-01-31  changed the way GET and SET send data. Special handling s needed in case a read request has not been 
#               answered by the device or in case the necessary delay are not over.
#               new deviceInfo structure for device specific settings replaces fCodeMap and other defaults
#   2015-02-07  added clear text error codes, fixed wrong length in fcode 16, removed return code for successful set
#   2015-02-11  added missing code to handle defUnpack when sending a write function code
#   2015-02-16  support for defPoll und defShowGet in deviceInfo,
#               defaultpoll in parseInfo, defPoll in deviceInfo und das entsprechende Attribut können auch auf "once"
#               gesetzt werden
#               defaultpolldelay bzw. das Attribut kann mit x beginnen und ist dann Multiplikator des Intervalls
#   2015-02-26  defaultpoll in poll und defaultpolldelay in polldelay umbenannt
#               attribute für timing umbenannt
#   2015-03-8   added coils / discrete inputs
#
#   2015-04-13  Statistics for bus usage
#   2015-05-15  fixed bugs in SetIODev
#   2015-05-18  alternative statistics / profiling 
#               fixed delays, to be taken from logical device - not physical
#               added missing dev-x-defExpr attribute to DevAttrList
#   2015-07-05  added revRegs / defRevRegs attributes
#   2015-07-17  added bswapRegs to reverse Byte-order on arbitrary length string (thanks to Marco)
#   2015-07-22  added encode and decode
#   2015-08-17  allow register 0, delete unused variable assignments
#   2016-03-28  check if $po is valid before doing Win USB stuff in _Ready
#   2016-04-07  added some logging, added tid checking
#   2016-04-07  check if there is a good frame after one with wrong tid, add noArg for get - prevents wrong readings ...
#   2016-06-14  new delay handling, new attrs on the physical device:
#               busDelay, clientSwitchDelay, dropQueueDoubles
#               new attrs on the logical device: alignTime, enableControlSet
#   2016-06-30  use non blocking open, new attrs: nextOpenDelay, maxTimeoutsToReconnect, disable
#   2016-08-13  textArg, fehler bei showGet, umstellung der Prüfungen bei Get und Set (controlSet, ?, ...)
#               open / reconnect handling komplett überarbeitet
#   2016-08-20  textArg fehlte noch in der Liste der erlaubten Attribute
#   2016-09-20  fixed bug in define when destination was undefined (introduced in preparation for Modbus ASCII)
#   2016-10-02  first version with Modbus ASCII support, disable attribute closes Modbus connections over TCP
#   2016-10-08  revRegs und bswapRegs in Send eingebaut, bugs bei revRegs / bswapRegs behoben
#               validate interval in define and set interval, restructured Opening of connections
#   2016-11-17  fixed missing timer set in Notify when rereadcfg is seen,
#               accept Responses from different ID after a broadcast
#       3.5.1   restructure set / send for unpack and revRegs / swapRegs
#   2016-11-20  restructured parseFrames and its calls / returns
#               optimized logging, fixed bugs with RevRegs
#   2016-11-26  first trial of new scanner
#   2016-12-01  ID Scanner, fixes for disable (delete queue), Logging enhancements
#   2016-12-04  remove Blanks in set if textArg is not set, Attribute dev-h-brokenFC3
#               fixed a bug when writing coils
#   2016-12-10  more checks, more logging (include Version in Log of Send), added silentReconnect
#   2016-12-17  fixed a bug when a modbus device was defined without path to a serial device 
#   2016-12-18  attribute to set log level for timeouts (timeoutLogLevel), openTimeout
#   2016-12-21  fixed $ret in keep
#   2016-12-27  check for undefined $val in ParseObj and Log with timeoutLogLevel
#   2016-12-28  removed RAWBUFFER and added some initiualisation for $ioHash->{READ}{BUFFER}, fixed logging for timeouts
#   2017-01-02  new attribute allowShortResponses 
#
#   2017-01-06  removed misleading log "destination device" at define when IODev Attr is not known yet.
#   2017-01-10  call Modbus_Statistics($ioHash, "Timeouts", 0); in EndBusy to keep Reading updated even if no timeout occured
#   2017-01-11  allow reconnect also for serial (add getIOHash in controlSet reconnect) in preparation for a common open
#   2017-01-14  fix timeoutLogLevel usage in ReadAnswer to use physical device attrs instaed of logical device attrs
#               use IsDisabled instead of AttrVal, restructure Open calls, 
#               common NotifyFN for physical and logical devices
#               disable for physical devices will even close a serial interface
#               fix Module type checking for "Modbus" insted of "MODBUS"
#               skip garbage in frames
#   2017-01-18  support for leading zeros in adresses in obj- attributes
#   2017-01-22  check that skipGarbage is only defined for physical device attrs or TCP devices
#               parseframes now logs tid only for TCP where it makes sense
#   2017-01-25  changed all expression evals to use a common function and catch warnings
#               new attribute ignoreExpr
#   2017-02-11  optimize logging
#   2017-03-12  fix disable for logical attribues (disable ist in PhysAttrs ...) - introduce more global vars for attributes
#   2017-04-15  added some debug logging and explicit return 0 in checkDelays
#   2017-04-21  optimize call to _send in GetUpdate, new attribute nonPrioritizedSet
#               remove unused variables for devInfo / parseInfo in ParseObj
#   2017-05-08  better warning handler restore (see $oldSig)
#   2017-07-15  new attribute sortUpdate to sort the requests by their object address 
#               new attribute brokenFC5 for misbehaving devices that don't understand the normal ff00 to set a coil to 1
#               set this attr e.g. to 0100 if the device wants 0100 instead of ff00
#   2017-07-18  started implementing data types (3.6.0)
#   2017-07-25  set saveAsModule 
#   2017-08-17  nicer logging of timeouts 
#   2017-09-17  extended check for missing len attribute with unpack that expects > 16 bits
#                   in _send
#
#   2017-12-06  restructure in order to allow Modbus slave processing
#   2018-07-14  rearrange functions, fix logical versus physical hash ...
#   2018-07-21  added tcp server functionality, relay functionality, passive mode
#   2018-10-01  fix to allow fractions of a second as interval during define
#   2018-10-06  fix bug where lrecv was stored in the {READ has instead of {REMEMBER}, 
#               modify registration of logical devices with their id
#               add @val to ParseObj for additional unpack fields
#   2018-10-12  smaller bugfixes, new attributes enableQueueLengthReading and retriesAfterTimeout
#   2018-11-05  use DevIO_IsOpen, check if fc6 can be used or fc16 needs to be used, rework open calls
#   2018-11-10  fixed setExpr -> setexpr
#   2018-12-01  fixed bug in startUpdateTimer when interval > timeout of a slave
#   2019-01-10  Log in Mapconvert von Level 3 auf 4 geändert
#   2019-01-11  logging changes
#   2019-01-29  added defSet, defHint and type options for set and hint
#               logging enhancements
#   2019-01-31  fixed bug in GetSetCheck (failed to check for busy)
#   2019-02-09  optimized logging in level 4/5
#   2019-02-19  little bug fix (warning)
#   2019-04-05  add a require for DevIO also in LDInitialize to be on the safe side ...
#   2019-04-15  add ModbusReadingsFn to allow the manipulation of readings in a derived module,
#               allow parseInfo and deviceInfo in device hash with priority over module hash
#   2019-04-17  better logging
#   2019-05-11  convert multiple spaces, tabs or newlines in maps to just one blank
#   2019-06-01  fix bug where disabling tcp master results in mass log (Close, ready, close ...)
#   2019-09-17  remove only partly commented debug log
#
#
#
#
#   ToDo / Ideas 
#                   Allow parseInfo in device Hash with priority over Module Hash
#                   Allow setting of a _Setup function in the ModbusXY initialize function to be called after init done and not disabled
#                       this can then modify the parseInfo Hash depending of a model variant or an offset   
#                       maybe call whenever startUpdateTime is called as well and _setup has not been caled yet?
#                       or do it depending on a certain object which is requested during normal getupdate? as expr?
#           
#                   learn objects in passive mode
#
#                   when an attr is set for a TCP slave or relay, copy attrs to running connection devices
#                   at modify from tcp to serial iodev hash key and DeviceName key are kept and wrong
#                   min / max checking as slave when we get write fcodes
#
#                   document serverTimeout, slave attributes, passive mode, reconnect,
#
#                   fix profiler calls
#                   option to close a tcp connection after the response has been received and only open it
#                       for the next request (connection handling in processRequestQueue instead of only readyfn
#
#                   put new connection in a special room (even hidden does not work reliably)
#                   conflicting definitions of attrs for expr etc. when slave uses them 
#                       to write and then to read and send response 
#                   test requesting fc 15 multiple coils
#                   test pack c/I types as response
#                   register offset as attribute evaluated at runtime when sending and parsing (Comptrol etc.)
#                   clearBufferAfterParsing als Option, die den Rest des Buffers wegwirft
#
#                   get reading key (type / adr)
#                   filterEcho (wie in private post im Forum vorgeschlagen)
#                   docu for set saveAsModule to save attr definitions as module and add it to .setlist
#                   define data types VT_R4 -> revregs, len2, unpack f> ...
#                   async output for scan? table? with revregs etc.?
#                   get object-interpretations h123 -> Alle Variationen mit revregs und bswap und unpacks ...
#                   nonblocking disable attr für xp
#
#                   average response time per modbus id in profiling
#                   reread after failed requests / timeouts -> rereadList filled in getUpdate, remove in parse?
#
#                   attr with a list of set commands / requests to launch when polling (Helios support)
#
#                   set/get definition with multiple requests as raw containig opt. readings / input
#
#                   Autoconfigure? (Combine testweise erhöhen, Fingerprinting -> DB?, ...?)
#
#


####################################################################################
# Internals / data structures
####################################################################################

# $hash->{MODBUSID}         Modbus ID that this device is responsible for

# $hash->{INTERVAL}         Interval for cyclic request of a master device
# $hash->{RELAY}            used for mode relay: name of a master device where we forward requests to
# $hash->{DeviceName}       needed by DevIo to get Device, Port, Speed etc.
# $hash->{IODev}            hash of the io device or this device itself if connecting through tcp
# $hash->{defptr}           reference to the name of the logical device responsible for an id (defptr}{lName} => id
# $hash->{TCPConn}          set to 1 if connecting through tcp/ip
# $hash->{TCPServer}        set to 1 if this is a tcp server / listening device (not a connection itself)
# $hash->{TCPChild}         set to 1 if this is a tcp server connection (child of a devive with TCPServer = 1)
# $hash->{EXPECT}           internal state - what are we waiting for (can be request, response, idle or ...)

# $hash->{MODE} can be master, slave, relay or passive - set during ld define
# relay is special because it to another master device to pass over requests to

# $hash->{FRAME}            the frame just received, beeing parsed / handled
# $hash->{REQUEST}          the request just received, beeing parsed / handled
# $hash->{RESPONSE}         the response just received, beeing parsed / handled or created




####################
# more explanations
####################

#
# if a logical device uses a serial physical device as io device, then $hash->{MODE}
# is copied to the physical device and locks this device into this mode.
#
# $hash->{PROTOCOL} can be RTU, ASCII or TCP
# as with MODE the PROTOCOL key is also copied and locked to the physical io device
#
# $hash->{DEST} contains ip address/port if connection through tcp


# phys connection   proto           mode on physical device
#
# serial            rtu / ascii     master and slave at same time not working, 
#                                   slave can not hear master / only one master per line
#                                   also master and passive at sime time does not make sense
#                                   also slave and passive is useless
#                                   so if one logical device is passive, physical device can be locked passive
#
#                                   if one is master or slave, physical can be set to same
#
# serial            rtu / ascii     passive possible, physical then can also be locked.
#
# serial            tcp             nonsense
#
# tcp               rtu / ascii     passive not possible, only master / slave. phys = logocal
#                   tcp             same.

# so when definig / assigning iodev, mode can be locked on physical side.
# same applies to protocol. rtu and ascii over same physical line is nonsense.

# for connections over tcp (Modbus TCP or RTU/ASCII over TCP $ioHash = $hash during define
# so $hash->{MODBUSID}, $hash->{PROTOCOL}, $hash->{MODE}, $hash->{IODev} is available

# for serial connections at runtime or when physical is already there when logical is defined
# and also for serial connections at startup when physical is not present when logical is defined
# NotifyFn is triggered at INITIALIZED, REREADCFG and MODIFIED.
# here ModbusLD_GetIOHash($hash) is called where everything should happen (call register etc.)

#
# for enable after disable on physical side everything is done. On logical side GetIOHash is called again.
# for attr IODev SetIODev is called
# ReadyFn also doesnt change anything regarding IODev / Registration

# So mainly things are handled after a define / initialized which triggers NotifyFn for every device 
# Notify calls GetIoHash which calls SetIODev
#

#
# Exprs und Maps
# --------------
#
# Fhem Master       Expr    Register in externem Gerät (read)   Readings in Fhem                # implemented in ParseObj
# Fhem Slave        Expr    Werte von externem Gerät (write)    Readings in Fhem                # implemented in ParseObj
#
# Fhem Master    setexpr    Benutzereingabe (set->write)        Register in externem Gerät      # implemented in Set
# Fhem Slave     setexpr    Readings in Fhem (read)             Register zu externem Gerät      # implemented in PackObj
#                
#
# Fhem Master       Map     Registerdarstellung extern (read)   Readings in Fhem                # implemented in ParseObj
# Fhem Slave        Map     Werte von externem Gerät (write)    Readings in Fhem                # implemented in ParseObj
#
# Fhem Master     revMap    Benutzereingabe (set->write)        Register in externem Gerät      # implemented in Set
# Fhem Slave      revMap    Readings in Fhem (read)             Register in externem Gerät      # implemented in PackObj
#


package main;

use strict;
use warnings;

# return time as float, not just full seconds
use Time::HiRes qw( gettimeofday tv_interval);
use TcpServerUtils;


use POSIX qw(strftime);
use Encode qw(decode encode);

sub Modbus_Initialize($);
sub Modbus_Define($$);
sub Modbus_Undef($$);
sub Modbus_Read($);
sub Modbus_ReadAnswer($);
sub Modbus_Ready($);
sub ModbusLD_ParseObj($$);
sub Modbus_ParseResponse($$%);
sub Modbus_ProcessRequestQueue($;$);
sub Modbus_ResponseTimeout($);
sub Modbus_CRC($);
sub Modbus_SyncHashKey($$$);
sub Modbus_ObjInfo($$$;$$);
sub Modbus_CheckEval($\@$$);
sub Modbus_Open($;$$$);
sub Modbus_FrameText($;$$);

# functions to be used from logical modules
sub ModbusLD_ExpandParseInfo($);
sub ModbusLD_Initialize($);
sub ModbusLD_Define($$);
sub ModbusLD_Undef($$);
sub ModbusLD_Get($@);
sub ModbusLD_Set($@);

sub ModbusLD_GetUpdate($);
sub ModbusLD_GetIOHash($);
sub ModbusLD_DoRequest($$$;$$$$);
sub ModbusLD_StartUpdateTimer($);

my $Modbus_Version = '4.1.5 - 17.9.2019';
my $Modbus_PhysAttrs = 
        "queueDelay " .
        "queueMax " .
        "queueTimeout " .
        "busDelay " .
        "clientSwitchDelay " .
        "dropQueueDoubles:0,1 " .
        "enableQueueLengthReading:0,1 " .
        "retriesAfterTimeout " .
        "profileInterval " .
        "openTimeout " .
        "nextOpenDelay " .
        "maxTimeoutsToReconnect " .             # for Modbus over TCP/IP only        
        "skipGarbage:0,1 " .
        "timeoutLogLevel:3,4 " .
        "silentReconnect:0,1 ";
        
my $Modbus_LogAttrs = 
        "IODev " .                              # fhem.pl macht dann $hash->{IODev} = $defs{$ioname}
        "queueMax " .
        "alignTime " .
        "enableControlSet:0,1 " .
        "nonPrioritizedSet:0,1 " .
        "nonPrioritizedGet:0,1 " .
        "sortUpdate:0,1 " .
        "scanDelay ";
        
my $Modbus_CommonAttrs = 
        "disable:0,1 ";
        
my %Modbus_errCodes = (
    "01" => "illegal function",
    "02" => "illegal data address",
    "03" => "illegal data value",
    "04" => "slave device failure",
    "05" => "acknowledge",
    "06" => "slave device busy",
    "08" => "memory parity error",
    "0a" => "gateway path unavailable",
    "0b" => "gateway target failed to respond"
);

my %Modbus_defaultFCode = (
    "c"     =>  {               
            read        =>  1,      
            write       =>  5,      
            },
    "d"     =>  {               
            read        =>  2,      
            },
    "i"     =>  {               
            read        =>  4,      
            },
    "h"     =>  {               
            read        =>  3,      
            write       =>  6,      
            },
);

my %writeCode = (
    1   =>  0,
    2   =>  0,
    3   =>  0,
    4   =>  0,
    5   =>  1,
    6   =>  1,
    15  =>  1,
    16  =>  1
);

my %Modbus_PDUOverhead = (
    "RTU"   =>  3,
    "ASCII" =>  7,
    "TCP"   =>  7);

    
#####################################
# _initialize für das physische Basismodul
sub Modbus_Initialize($)
{
    my ($modHash) = @_;

    require "$attr{global}{modpath}/FHEM/DevIo.pm";

    $modHash->{ReadFn}   = "Modbus_Read";
    $modHash->{ReadyFn}  = "Modbus_Ready";
    $modHash->{DefFn}    = "Modbus_Define";
    $modHash->{UndefFn}  = "Modbus_Undef";
    $modHash->{NotifyFn} = "Modbus_Notify";
    $modHash->{AttrFn}   = "Modbus_Attr";

    $modHash->{AttrList} = "do_not_notify:1,0 " . 
        $Modbus_PhysAttrs .
        $Modbus_CommonAttrs .
        $readingFnAttributes;
    return;
}


#####################################
sub ModbusLD_Initialize($ )
{
    my ($modHash) = @_;

    require "$attr{global}{modpath}/FHEM/DevIo.pm";

    $modHash->{DefFn}     = "ModbusLD_Define";    # functions are provided by the Modbus base module
    $modHash->{UndefFn}   = "ModbusLD_Undef";
    $modHash->{ReadFn}    = "Modbus_Read";
    $modHash->{ReadyFn}   = "Modbus_Ready";
    $modHash->{AttrFn}    = "ModbusLD_Attr";
    $modHash->{SetFn}     = "ModbusLD_Set";
    $modHash->{GetFn}     = "ModbusLD_Get";
    $modHash->{NotifyFn}  = "Modbus_Notify";


    $modHash->{AttrList}= 
        "do_not_notify:1,0 " .         
        $Modbus_LogAttrs . 
        $Modbus_CommonAttrs .
        $readingFnAttributes;

    $modHash->{ObjAttrList} = 
        "obj-[cdih][0-9]+-reading " .
        "obj-[cdih][0-9]+-name " .
        "obj-[cdih][0-9]+-min " .
        "obj-[cdih][0-9]+-max " .
        "obj-[cdih][0-9]+-hint " .
        "obj-[cdih][0-9]+-map " .
        "obj-[cdih][0-9]+-set " .
        "obj-[cdih][0-9]+-setexpr " .
        "obj-[cdih][0-9]+-textArg " .
        "obj-[cdih][0-9]+-revRegs " .
        "obj-[cdih][0-9]+-bswapRegs " .
        "obj-[cdih][0-9]+-len " .
        "obj-[cdih][0-9]+-unpack " .
        "obj-[cdih][0-9]+-decode " .
        "obj-[cdih][0-9]+-encode " .
        "obj-[cdih][0-9]+-expr " .
        "obj-[cdih][0-9]+-ignoreExpr " .
        "obj-[cdih][0-9]+-format " .
        "obj-[ih][0-9]+-type " .
        "obj-[cdih][0-9]+-showGet " .
        "obj-[cdih][0-9]+-allowWrite " .
        "obj-[cdih][0-9]+-poll " .
        "obj-[cdih][0-9]+-polldelay ";

        #"(get|set)([0-9]+)request([0-9]+) "
        
    $modHash->{DevAttrList} = 
        "dev-([cdih]-)*read " .
        "dev-([cdih]-)*write " .
        "dev-([cdih]-)*combine " .
        "dev-([cdih]-)*allowShortResponses " .
        "dev-([cdih]-)*addressErrCode " .
        "dev-([cdih]-)*valueErrCode " .

        "dev-([cdih]-)*defRevRegs " .
        "dev-([cdih]-)*defBswapRegs " .
        "dev-([cdih]-)*defLen " .
        "dev-([cdih]-)*defUnpack " .
        "dev-([cdih]-)*defDecode " .
        "dev-([cdih]-)*defEncode " .
        "dev-([cdih]-)*defExpr " .
        "dev-([cdih]-)*defSet " .
        "dev-([cdih]-)*defHint " .
        "dev-([cdih]-)*defSetexpr " .
        "dev-([cdih]-)*defIgnoreExpr " .
        "dev-([cdih]-)*defFormat " .
        "dev-([cdih]-)*defShowGet " .
        "dev-([cdih]-)*defAllowWrite " .
        "dev-([cdih]-)*defPoll " .
        "dev-h-brokenFC3 " .
        "dev-c-brokenFC5 " .
        
        "dev-type-[A-Za-z0-9_]+-unpack " .
        "dev-type-[A-Za-z0-9_]+-len " .
        "dev-type-[A-Za-z0-9_]+-encode " .
        "dev-type-[A-Za-z0-9_]+-decode " .
        "dev-type-[A-Za-z0-9_]+-revRegs " .
        "dev-type-[A-Za-z0-9_]+-bswapRegs " .
        "dev-type-[A-Za-z0-9_]+-format " .
        "dev-type-[A-Za-z0-9_]+-expr " .
        "dev-type-[A-Za-z0-9_]+-map " .
        "dev-type-[A-Za-z0-9_]+-hint " .
        "dev-type-[A-Za-z0-9_]+-set " .

        "dev-timing-timeout " .
        "dev-timing-serverTimeout " .       
        "dev-timing-sendDelay " .
        "dev-timing-commDelay ";
    return;            
}


#################################################
# Define für das physische serielle Basismodul.
# modbus id, Intervall etc. gibt es hier nicht
# sondern im logischen Modul.
#
# entsprechend wird auch getUpdate im 
# logischen Modul aufgerufen.
#
# Modbus over TCP is opened in the logical open
#
sub Modbus_Define($$)
{
    my ($ioHash, $def) = @_;
    my @a = split("[ \t]+", $def);
    my ($name, $type, $dev) = @a;
    
    return "wrong syntax: define <name> $type [tty-devicename|none]"
        if(@a < 3 || @a > 3);
    
    $ioHash->{DeviceName} = $dev;           # needed by DevIo to get Device, Port, Speed etc.       
    $ioHash->{IODev}      = $ioHash;        # point back to self to make getIOHash easier 
    $ioHash->{SerialConn} = 1;
    
    Modbus_Close($ioHash, 1);               # close, set Expect, clear Buffer, but don't set state to disconnected 

    Log3 $name, 3, "$name: defined as $dev";
    return;                                 # open is done later from NOTIFY
}



#####################################
sub ModbusLD_Define($$)
{
    my ($hash, $def) = @_;
    my ($name, $module, $id, $interval, $mode, $dest, $proto, $relay);
    
    #           name    modul    id
    my $sR = qr/(\S+)\s+(\S+)\s+(\d+)\s+/;
    #                  destination aber nicht RTU etc.
    my $dR = qr/(?:\s+(?!(?:RTU|ASCII|TCP))(\S+))?/;
    #                  protocol 
    my $pR = qr/(?:\s+(RTU|ASCII|TCP))?/;
    
    #                 interv
    if ($def =~ /${sR}(\d\.?\d*)${dR}${pR}\s*$/) {
        # classic master define
        ($name, $module, $id, $interval, $dest, $proto) = ($1, $2, $3, $4, $5, $6);
        $mode     = 'master';
        $interval = 0 if (!defined($interval));
        Log3 $name, 3, "$name: defined with id $id, interval $interval, protocol " .
                        ($proto ? $proto : "default (RTU)") . ", mode $mode" .
                        ($dest ? ", connection to $dest" : "");
    } elsif ($def =~ /${sR}(slave|passive)${dR}${pR}\s*$/) {
        # classic slave or passive define
        ($name, $module, $id, $mode, $dest, $proto) = ($1, $2, $3, $4, $5, $6);
        $interval = 0;
        if ($mode eq 'passive' && $dest) {
            Log3 $name, 3, "$name: define as passive is only possible for serial connections, not with a defined host:port";
            return "Define as passive is only possible for serial connections, not with a defined host:port";
        }
        Log3 $name, 3, "$name: defined with id $id, protocol " .
                    ($proto ? $proto : "default (RTU)") . ", mode $mode" .
                    ($dest ? ", listening at $dest" : "");
    } elsif ($def =~ /${sR}(relay)${dR}${pR}\s+to\s+(\S+)$/) {
        # relay define
        ($name, $module, $id, $mode, $dest, $proto, $relay) = ($1, $2, $3, $4, $5, $6, $7);
        $interval = 0;
        Log3 $name, 3, "$name: defined with id $id, interval $interval, protocol " .
                    ($proto ? $proto : "default (RTU)") . ", mode $mode" .
                    ($dest ? ", listening at $dest" : "") .
                    " and relay to device $relay";
    } else {
        ($name, $module) = ($def =~ /(\S+)\s+(\S+)\s+.*/);
        return "Usage: define <name> $module <id> <interval>|slave|relay|passive [host:port] [RTU|ASCII|TCP] [to <relayMasterDevice>]"
    }
    $proto = "RTU" if (!$proto);
    
    # for Modbus TCP physical = logical so IODev and MODE is set.    
    # for Modbus over serial lines this is set when IODev Attr and GetIOHash is called 
    # or later when it is needed and GetIOHash is called
    
    # for TCP $id is an optional Unit ID that is ignored by most devices
    # but some gateways may use it to select the device to forward to.
        
    $hash->{MODBUSID}        = $id;
    $hash->{MODE}            = $mode;
    $hash->{PROTOCOL}        = $proto;
    $hash->{'.getList'}      = "";
    $hash->{'.setList'}      = "";
    $hash->{".updateSetGet"} = 1;
    $hash->{STATE}           = "disconnected";      # initial value
    $hash->{NOTIFYDEV}       = "global";            # NotifyFn nur aufrufen wenn global events (INITIALIZED etc.)
    $hash->{MODULEVERSION}   = "Modbus $Modbus_Version";
    
    if ($interval) {
        $hash->{INTERVAL}    = $interval;
    } else {
        delete $hash->{INTERVAL};
    }
    if ($relay) {
        $hash->{RELAY}       = $relay;
    } else {
        delete $hash->{RELAY};
    }

    if ($dest) {                                    # Modbus über TCP mit IP Adresse (TCP oder auch RTU/ASCII über TCP)
        $dest .= ":502" if ($dest !~ /.*:[0-9]/);   # add default port if no port specified
        $hash->{DeviceName}    = $dest;             # needed by DevIo to get Device, Port, Speed etc.
        $hash->{IODev}         = $hash;             # Modul ist selbst IODev
        $hash->{defptr}{$name} = $id;               # logisches Gerät für die Id (eigenes Device bei TCP)
        $hash->{TCPConn}       = 1;
        $hash->{TCPServer}     = 1 if ($mode eq 'slave' || $mode eq 'relay');
        my $modHash = $modules{$hash->{TYPE}};
        $modHash->{AttrList} .= $Modbus_PhysAttrs;  # affects all devices - even non TCP - sorry ...
        #Log3 $name, 3, "$name: added attributes for physical devices for Modbus TCP";
    } else {
        $dest = '';
        delete $hash->{TCPConn};
        delete $hash->{TCPServer};
        delete $hash->{TCPChild};
    }           
    # connection will be opened later in NotifyFN
    # for serial connections we use a separate physical device. This is set in Notify
    
    return;
}



#####################################
# delete physical Device
sub Modbus_Undef($$)
{
    my ($ioHash, $arg) = @_;
    my $name = $ioHash->{NAME};

    Modbus_Close($ioHash,1 ,1) if (DevIo_IsOpen($ioHash));  # close, set Expect, clear Buffer, don't set state, don't delete yet

    # lösche auch die Verweise aus logischen Modulen auf dieses physische.
    foreach my $d (keys %{$ioHash->{defptr}}) {
        Log3 $name, 3, "$name: Undef is removing IO device for $d";
        my $lHash = $defs{$d};
        delete $lHash->{IODev} if ($lHash);
        ModbusLD_StopUpdateTimer($ioHash);          # in case this is a TCP connected device
    }
    #Log3 $name, 3, "$name: _UnDef done";
    return;
}



#####################################
sub ModbusLD_Undef($$)
{
    my ($hash, $arg) = @_;
    my $name = $hash->{NAME};
    Log3 $name, 3, "$name: _UnDef is closing $name";    
    ModbusLD_UnregAtIODev($hash);
    Modbus_Close($hash,1 ,1) if (DevIo_IsOpen($hash));      # close, set Expect, clear Buffer, don't set state, don't delete yet
    ModbusLD_StopUpdateTimer($hash);                # in case this is a TCP connected device
    delete $hash->{PROTOCOL};                       # just in case somebody keeps a pointer to our hash ...
    delete $hash->{MODE};
    return;
}



#########################################################################
sub Modbus_ManageUserAttr($$)
{                     
    my ($hash, $aName) = @_;       
    my $name    = $hash->{NAME};
    my $modHash = $modules{$hash->{TYPE}};

    # handle wild card attributes -> Add to userattr to allow modification in fhemweb
    if (" $modHash->{AttrList} " !~ m/ ${aName}[ :;]/) {
        # nicht direkt in der Liste -> evt. wildcard attr in AttrList
        foreach my $la (split " ", $modHash->{AttrList}) {
            $la =~ /([^:;]+)(:?.*)/;
            my $vgl = $1;           # attribute name in list - probably a regex
            my $opt = $2;           # attribute hint in list
            if ($aName =~ $vgl) {   # yes - the name in the list now matches as regex
                # $aName ist eine Ausprägung eines wildcard attrs
                addToDevAttrList($name, "$aName" . $opt);    # create userattr with hint to allow change in fhemweb
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
}




#########################################################################
# AttrFn for physical device. 
# special treatment only für attr disable.
#
sub Modbus_Attr(@)
{
    my ($cmd,$name,$aName,$aVal) = @_;
    my $hash = $defs{$name};        # hash des physischen Devices
    
    Log3 $name, 5, "$name: attr $cmd $aName" . (defined($aVal) ? ", $aVal" : "");
    if ($aName eq 'disable' && $init_done) {        # only after init_done, otherwise see NotifyFN
        # disable on a physical serial device
        if ($cmd eq "set" && $aVal) {
            Log3 $name, 3, "$name: attr disable set" . (DevIo_IsOpen($hash) ? ", closing connection" : "");
            Modbus_Close($hash);            # close, set Expect, clear Buffer, set state to disconnected
            
        } elsif ($cmd eq "del" || ($cmd eq "set" && !$aVal)) {
            Log3 $name, 3, "$name: attr disable removed";
            Modbus_Open($hash); 
        }
    }   
    return undef;
}


# todo: when changing server-timeout -> reset internal timer

#########################################################################
# AttrFn for logical device. 
sub ModbusLD_Attr(@)
{
    my ($cmd,$name,$aName,$aVal) = @_;
    my $hash = $defs{$name};        # hash des logischen Devices
    my $inCheckEval = 0;

    if ($cmd eq "set") {
        if ($aName =~ "expr") {     # validate all Expressions
            my $val = 1;
            my @val = (0,0,0,0,0,0);
            if ($aVal !~ /readingsBulkUpdate/) {    # dont even try if it contains this command
                eval $aVal;
                if ($@) {
                    Log3 $name, 3, "$name: attr with invalid Expression in attr $name $aName $aVal: $@";
                    return "Invalid Expression $aVal";
                }
            } else {
                Log3 $name, 5, "$name: attr $name $aName $aVal is not checked now because it contains readingsBulkUpdate";
            }
        } elsif ($aName eq "IODev") {
            if ($hash->{TCPConn}) {
                return "Attr IODev is not allowed for devices connected through TCP";
            }           
            if (!ModbusLD_SetIODev($hash, $aVal) && $init_done) {       # set physical device proto, mode, register/unregister, ...
                return "$aVal can not be used as IODev, see log for details";
            }
              
        } elsif ($aName eq 'alignTime') {
            my ($alErr, $alHr, $alMin, $alSec, undef) = GetTimeSpec($aVal);
            return "Invalid Format $aVal in $aName : $alErr" if ($alErr);
            my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
            $hash->{TimeAlign}    = fhemTimeLocal($alSec, $alMin, $alHr, $mday, $mon, $year);
            $hash->{TimeAlignFmt} = FmtDateTime($hash->{TimeAlign});
            ModbusLD_StartUpdateTimer($hash);     # change / start timer for alignment 
        } elsif (" $Modbus_PhysAttrs " =~ /\ $aName[: ]/) {
            if (!$hash->{TCPConn} && !$hash->{SerialConn}) {
                Log3 $name, 3, "$name: attr $aName is only valid for physical Modbus devices or Modbus TCP - please use this attribute for your physical IO device" . ($hash->{IODev}{NAME} ? ' ' . $hash->{IODev}{NAME} : "");
                return "attribute $aName is only valid for physical Modbus devices or Modbus TCP - please use this attribute for your physical IO device" . ($hash->{IODev}{NAME} ? ' ' . $hash->{IODev}{NAME} : "");
            }
        } elsif ($aName =~ /(obj-[cdih])[0-9]+-reading/) {
            return "unsupported character in reading name $aName ".
                "(not A-Za-z/\\d_\\.-)" if(!goodReadingName($aName));
        } elsif ($aName eq "SSL") {
            if (!$hash->{TCPConn}) {
                Log3 $name, 3, "$name: attr $aName is only valid Modbus TCP slaves";
                return "attribute $aName is only valid for Modbus TCP slaves";
            }       
            TcpServer_SetSSL($hash);
            if($hash->{CD}) {
                my $ret = IO::Socket::SSL->start_SSL($hash->{CD});
                Log3 $name, 3, "$hash->{NAME} start_SSL: $ret" if($ret);
            }
        }
        if ($aName =~ /(obj-[cdih])(0+([0-9]+))-/) {
            # leading zero in obj-Attr detected
            if (length($2) > 5) {
                my $new = $1 . substr("00000", 0, 5 - length ($3)) . $3;
                Log3 $name, 3, "$name: attr $aName address is too long, shortened to $new ($2/$3)";
                $aName = $new;
            }
            if (!$hash->{LeadingZeros}) {
                $hash->{LeadingZeros} = 1;
                Log3 $name, 3, "$name: attr support for leading zeros in object addresses enabled. This might slow down the fhem modbus module a bit";
            }
        }
        Modbus_ManageUserAttr($hash, $aName);
        
    } elsif ($cmd eq "del") {    
        #Log3 $name, 5, "$name: attr del $aName";
        if ($aName =~ /obj-[cdih]0[0-9]+-/) {
            if (!(grep !/$aName/, grep (/obj-[cdih]0[0-9]+-/, keys %{$attr{$name}}))) {
                delete $hash->{LeadingZeros};   # no more leading zeros            
            }
        }
    }
    $hash->{".updateSetGet"} = 1;
    Log3 $name, 5, "$name: attr change set updateGetSetList to 1";
    
    if ($aName eq 'disable' && $init_done) {    # if not init_done, nothing to be done here (see NotifyFN)
        # disable on a logical device (not physical here!)
        if ($cmd eq "set" && $aVal) {           # disable set
            if ($hash->{TCPConn}) {             # Modbus over TCP connection
                Log3 $name, 3, "$name: attr disable set" .
                    (DevIo_IsOpen($hash) ? ", closing TCP connection" : "");
                Modbus_Close($hash);            # close, set Expect, clear Buffer, set state to disconnected
            } else {
                ModbusLD_UnregAtIODev($hash);
            }
            ModbusLD_StopUpdateTimer($hash);  # in case this is logical or a TCP connected device
            
        } elsif ($cmd eq "del" || ($cmd eq "set" && !$aVal)) {
            Log3 $name, 3, "$name: attr disable removed" . 
                ($hash->{TCPConn} ? ", opening TCP connection" : "");
            if ($hash->{TCPConn}) {             # Modbus over TCP connection
                Modbus_Open($hash);             # should be called with hash of physical device but for TCP it's the same
            } else {
                ModbusLD_UnregAtIODev($hash);   # cleanup 
                my $ioHash = ModbusLD_GetIOHash($hash);     # get ioName for meaningful logging
                if ($ioHash) {
                    ModbusLD_RegisterAtIODev($hash, $ioHash);
                    my $ioName = $ioHash->{NAME};    
                    Log3 $name, 3, "$name: using $ioName for communication";
                } else {
                    Log3 $name, 3, "$name: no IODev for communication";
                }
            }           
            ModbusLD_StartUpdateTimer($hash);   # first Update in 1 second or aligned if interval is defined
        }
    }   
    return;
}


#####################################
sub ModbusLD_UpdateGetSetList($)
{
    my ($hash)    = @_;
    my $name      = $hash->{NAME};
    my $modHash   = $modules{$hash->{TYPE}};
    
    my $parseInfo = ($hash->{parseInfo} ? $hash->{parseInfo} : $modHash->{parseInfo});
    my $devInfo   = ($hash->{deviceInfo} ? $hash->{deviceInfo} : $modHash->{deviceInfo});
    
    if (AttrVal($name, "enableControlSet", 1)) {            # spezielle Sets freigeschaltet (since 4.0 1 by default)
        if ($hash->{MODE} && $hash->{MODE} eq 'master') {
            $hash->{'.setList'} = "interval reread:noArg reconnect:noArg stop:noArg start:noArg close:noArg saveAsModule ";
            if ($hash->{PROTOCOL} =~ /RTU|ASCII/) {
                $hash->{'.setList'} .= "scanModbusId ";
            }
            $hash->{'.setList'} .= "scanStop:noArg scanModbusObjects ";
        } else { 
            $hash->{'.setList'}  = "reconnect:noArg saveAsModule ";
        }
    } else {
        $hash->{'.setList'}  = "";
    }
    $hash->{'.getList'}  = "";
    
    if ($hash->{MODE} && $hash->{MODE} eq 'master') {
        my @ObjList = keys (%{$parseInfo});
        foreach my $at (keys %{$attr{$name}}) {
            if ($at =~ /^obj-(.*)-reading$/) {
                push @ObjList, $1 if (!$parseInfo->{$1});
            }
        }
        #Log3 $name, 5, "$name: UpdateGetSetList full object list: " . join (" ",  @ObjList);
        
        foreach my $objCombi (sort @ObjList) {
            my $reading = Modbus_ObjInfo($hash, $objCombi, "reading");
            my $showget = Modbus_ObjInfo($hash, $objCombi, "showGet", "defShowGet");    # all default to ""
            my $set     = Modbus_ObjInfo($hash, $objCombi, "set",     "defSet"); 
            my $map     = Modbus_ObjInfo($hash, $objCombi, "map",     "defMap");
            my $hint    = Modbus_ObjInfo($hash, $objCombi, "hint",    "defHint");
            #my $type    = substr($objCombi, 0, 1);
            #my $adr     = substr($objCombi, 1);
            my $setopt;
            $hash->{'.getList'} .= "$reading:noArg " if ($showget); # sichtbares get
    
            if ($set) {                 # gibt es für das Reading ein SET?
                if ($map){              # ist eine Map definiert, aus der Hints abgeleitet werden können?
                    my $hl = Modbus_MapToHint($map);
                    $setopt = $reading . ":$hl";
                } else {
                    $setopt = $reading; # nur den Namen für setopt verwenden.
                }
                if ($hint){             # hints explizit definiert? (überschreibt evt. schon abgeleitete hints)
                    $setopt = $reading . ":" . $hint;
                }
                $hash->{'.setList'} .= "$setopt ";     # Liste aller Sets inkl. der Hints nach ":" für Rückgabe bei Set ?
            }
        }
    }
    Log3 $name, 5, "$name: UpdateSetList: setList=$hash->{'.setList'}";
    Log3 $name, 5, "$name: UpdateSetList: getList=$hash->{'.getList'}";
    $hash->{".updateSetGet"} = 0;
    return;
}


#####################################
# Get Funktion für logische Geräte / Module
sub ModbusLD_Get($@)
{
    my ($hash, @a) = @_;
    return "\"get $a[0]\" needs at least one argument" if(@a < 2);
    my $name    = $hash->{NAME};
    my $getName = $a[1];
    my $async   = AttrVal($name, "nonPrioritizedGet", 0);
    my $err;

    my $objCombi = Modbus_ObjKey($hash, $getName);
    Log3 $name, 5, "$name: get called with $getName " . ($objCombi ? "($objCombi)" : "") if ($getName ne "?");

    if (!$objCombi) {
        ModbusLD_UpdateGetSetList($hash) if ($hash->{".updateSetGet"});
        #Log3 $name, 5, "$name: get $getName not found, return list $hash->{'.getList'}" if ($getName ne "?");
        return "Unknown argument $a[1], choose one of $hash->{'.getList'}";
    }

    my $msg = ModbusLD_GetSetChecks($hash, $async);
    return $msg if ($msg);                                      # no other action because io device is not usable anyway
    
    delete $hash->{gotReadings};
    if ($async) {
        ModbusLD_DoRequest($hash, $objCombi, "read", 0, 0, 0, "get $getName"); # no force, just queue
    } else {
        ModbusLD_DoRequest($hash, $objCombi, "read", 0, 1, 0, "get $getName"); # add at beginning of queue and force send / sleep if necessary
        $err = Modbus_ReadAnswer(ModbusLD_GetIOHash($hash));    # ioHash has been checked above already in GetSetChecks
    }
    Modbus_StartQueueTimer($hash, 0);                           # call processRequestQueue at next possibility (others waiting?)
    return $err if ($err);
    return $hash->{gotReadings}{$getName};
}


#####################################
sub ModbusLD_Set($@)
{
    my ($hash, @a) = @_;
    return "\"set $a[0]\" needs at least an argument" if(@a < 2);

    my ($name, $setName, @setValArr) = @a;
    my $setVal = (@setValArr ? join(' ', @setValArr) : "");
    my $rawVal = "";
    my $async  = AttrVal($name, "nonPrioritizedSet", 0);
    
    if (AttrVal($name, "enableControlSet", 1)) {                # spezielle Sets freigeschaltet?
        my $error = ModbusLD_ControlSet($hash, $setName, $setVal);
        return if (defined($error) && $error eq "0");           # control set found and done.
        return $error if ($error);                              # error
        # continue if ControlSet function returned undef
    }
    
    my $objCombi = Modbus_ObjKey($hash, $setName);
    Log3 $name, 5, "$name: set called with $setName " . 
            ($objCombi ? "($objCombi) " : " ") . 
            (defined($setVal) ? "setVal = $setVal" :"") if ($setName ne "?");
    
    if (!$objCombi) {
        ModbusLD_UpdateGetSetList($hash) if ($hash->{".updateSetGet"});
        #Log3 $name, 5, "$name: set $setName not found, return list $hash->{'.setList'}" if ($setName ne "?");
        return "Unknown argument $a[1], choose one of $hash->{'.setList'}";
    } 
    if (!defined($setVal)) {
        Log3 $name, 3, "$name: set without value for $setName";
        return "No Value given to set $setName";
    }
    
    my $msg = ModbusLD_GetSetChecks($hash, $async);
    return $msg if ($msg);                              # no other action because io device is not usable anyway
    
    my $ioHash = ModbusLD_GetIOHash($hash);             # ioHash has been checked in GetSetChecks above already

    my $map     = Modbus_ObjInfo($hash, $objCombi, "map", "defMap");
    my $setmin  = Modbus_ObjInfo($hash, $objCombi, "min", "", "");        # default to ""
    my $setmax  = Modbus_ObjInfo($hash, $objCombi, "max", "", "");        # default to ""
    my $setexpr = Modbus_ObjInfo($hash, $objCombi, "setexpr", "defSetexpr");
    my $textArg = Modbus_ObjInfo($hash, $objCombi, "textArg");
    my $unpack  = Modbus_ObjInfo($hash, $objCombi, "unpack", "defUnpack", "n");   
    my $revRegs = Modbus_ObjInfo($hash, $objCombi, "revRegs", "defRevRegs");     
    my $swpRegs = Modbus_ObjInfo($hash, $objCombi, "bswapRegs", "defBswapRegs"); 
    my $len     = Modbus_ObjInfo($hash, $objCombi, "len", "defLen", 1); 
   
    my $type    = substr($objCombi, 0, 1);
    my $fCode   = Modbus_DevInfo($hash, $type, "write", $Modbus_defaultFCode{$type}{write});
    
    # 1. Schritt: Map prüfen
    if ($map) {                  
        $rawVal = Modbus_MapConvert ($hash, $map, $setVal, 1);      # use reversed map
        return "set value $setVal did not match defined map" if (!defined($rawVal));
        Log3 $name, 5, "$name: set converted $setVal to $rawVal using map $map";
    } else {
       $rawVal = $setVal;
    }
    
    # 2. Schritt: falls definiert Min- und Max-Werte prüfen
    if ($rawVal =~ /^\s*-?\d+\.?\d*\s*$/) {             # a number (potentially with blanks)
        $rawVal =~ s/\s+//g if (!$textArg);             # remove blanks
        if ($setmin ne "") {                            
            Log3 $name, 5, "$name: set is checking value $rawVal against min $setmin";
            return "value $rawVal is smaller than min ($setmin)" if ($rawVal < $setmin);
        }
        if ($setmax ne "") {
            Log3 $name, 5, "$name: set is checking value $rawVal against max $setmax";
            return "value $rawVal is bigger than max ($setmax)" if ($rawVal > $setmax);
        }
    } else {
        if (!$textArg) {
            Log3 $name, 3, "$name: set value $rawVal is not numeric and textArg not specified";
            return "Set Value $rawVal is not numeric and textArg not specified";
        }
    }
    
    # 3. Schritt: Konvertiere mit setexpr falls definiert
    my @val = ($rawVal);
    $rawVal = Modbus_CheckEval($hash, @val, $setexpr, "setexpr for $setName") if ($setexpr);
    
    # 4. Schritt: Pack value
    my $packedVal;
    if ($fCode == 5) {      # special treatment when writing one coil
        if (Modbus_DevInfo($hash, "c", "brokenFC5", 0)) {
            my $oneCode = lc Modbus_DevInfo($hash, "c", "brokenFC5");
            $packedVal = pack ('H4', ($rawVal ? $oneCode : "0000"));
        } else {
            $packedVal = pack ('H4', ($rawVal ? "FF00" : "0000"));
        }
    } else {
        $packedVal = pack ($unpack, $rawVal);   
    }
    Log3 $name, 5, "$name: set packed hex " . unpack ('H*', $rawVal) . " with $unpack to hex " . unpack ('H*', $packedVal);
    
    # 5. Schritt: RevRegs / SwapRegs if needed
    $packedVal = Modbus_RevRegs($hash, $packedVal, $len) if ($revRegs && $len > 1);
    $packedVal = Modbus_SwpRegs($hash, $packedVal, $len) if ($swpRegs);
    
    if ($async) {
        ModbusLD_DoRequest($hash, $objCombi, "write", $packedVal, 0, 0, "set $setName");   # no force, just queue at the end
    } else {
        ModbusLD_DoRequest($hash, $objCombi, "write", $packedVal, 1, 0, "set $setName");   # add at beginning and force send / sleep if necessary
        my $err = Modbus_ReadAnswer($ioHash);
        return $err if ($err);
    }
    if ($fCode == 15 || $fCode == 16) {                             # read after write
        Log3 $name, 5, "$name: set is sending read after write";
        if ($async) {
            ModbusLD_DoRequest($hash, $objCombi, "read", 0, 0, 0, "set $setName Rd");     # no force, just queue at the end
        } else {
            ModbusLD_DoRequest($hash, $objCombi, "read", 0, 1, 0, "set $setName Rd");     # as 1st and force send / sleep if necessary
            my $err = Modbus_ReadAnswer($ioHash);
            return "$err (in read after write for FCode 16)" if ($err);          
        }
    }
    Modbus_StartQueueTimer($hash, 0);                               # call processRequestQueue at next possibility (others waiting?)
    return;     # no return code if no error 
}


#
# SET command - handle predefined control sets
################################################
sub ModbusLD_ControlSet($$$)
{
    my ($hash, $setName, $setVal) = @_;
    my $name = $hash->{NAME};
    
    if ($setName eq 'interval') {
        return "set interval is only allowed when Fhem is Modbus master" if ($hash->{MODE} ne 'master');
        if (!$setVal || $setVal !~ /[0-9.]+/) {
            Log3 $name, 3, "$name: set interval $setVal not valid, continuing with $hash->{INTERVAL} (sec)";
            return "No valid Interval specified";
        } else {
            $hash->{INTERVAL} = $setVal;
            Log3 $name, 3, "$name: set interval changed interval to $hash->{INTERVAL} seconds";
            ModbusLD_StartUpdateTimer($hash);
            return "0";
        }
        
    } elsif ($setName eq 'reread') {
        return "set reread is only allowed when Fhem is Modbus master" if ($hash->{MODE} ne 'master');
        ModbusLD_GetUpdate("reread:$name");
        return "0";
        
    } elsif ($setName eq 'reconnect') {     
        if (!$hash->{TCPConn} && $hash->{TYPE} ne 'Modbus') {
            Log3 $name, 3, "$name: reconnect only possible for physical or TCP connections, not for logical devices";
            return "reconnect only possible for physical or TCP connections, not for logical devices";
        }
        # todo: close and immediate reopen might case problems on windows with usb device 
        # needs testing

        my $msg = ModbusLD_CheckDisable($hash);
        return $msg if ($msg);

        Modbus_Open($hash, 0, 0, 1);    # async but close first
        return "0";

    } elsif ($setName eq 'close') {     
        if (!$hash->{TCPConn} && $hash->{TYPE} ne 'Modbus') {
            Log3 $name, 3, "$name: close only possible for physical or TCP connections, not for logical devices";
            return "close only possible for physical or TCP connections, not for logical devices";
        }
        Modbus_Close($hash);         # should be called with hash of physical device but for TCP it's the same
        return "0";
        
    } elsif ($setName eq 'stop') {
        return "set stop is only allowed when Fhem is Modbus master" if ($hash->{MODE} ne 'master');
        ModbusLD_StopUpdateTimer($hash);
        return "0";
        
    } elsif ($setName eq 'start') {
        my $msg = ModbusLD_CheckDisable($hash);
        return $msg if ($msg);

        return "set start is only allowed when Fhem is Modbus master" if ($hash->{MODE} ne 'master');
        ModbusLD_StartUpdateTimer($hash);
        return "0";
        
    } elsif ($setName eq 'scanStop') {
        Log3 $name, 3, "$name: scanStop - try asyncOutput to $hash";
        my $cl = $hash->{CL};
        asyncOutput($cl, 'Hallo <b>Du</b>');
        
        my $msg = ModbusLD_CheckDisable($hash);
        return $msg if ($msg);
        return "set scanStop is only allowed when Fhem is Modbus master" if ($hash->{MODE} ne 'master');
        RemoveInternalTimer ("scan:$name");
        delete $hash->{scanId};
        delete $hash->{scanIdStart};
        delete $hash->{scanIdEnd};
        delete $hash->{scanOAdr};
        delete $hash->{scanOStart};
        delete $hash->{scanOEnd};
        delete $hash->{scanOLen};
        delete $hash->{scanOType};
        return "0";

    } elsif ($setName eq 'scanModbusId') {
        my $msg = ModbusLD_CheckDisable($hash);
        return $msg if ($msg);
        return "set scanModbusId is only allowed when Fhem is Modbus master" if ($hash->{MODE} ne 'master');
        delete $hash->{scanOStart};
        delete $hash->{scanOEnd};
        $hash->{scanIdStart} = 1;
        $hash->{scanIdEnd}   = 255;
        $hash->{scanOType}   = 'h';
        $hash->{scanOAdr}    = 100;
        $hash->{scanOLen}    = 1;
        if ($setVal && $setVal =~ /([0-9]+) *- *([0-9]+) +([hicd][0-9]+)/) {
            $hash->{scanIdStart} = $1;
            $hash->{scanIdEnd}   = $2;
            $hash->{scanOType}  = substr($3,0,1);
            $hash->{scanOAdr} = substr($3,1);
        }
        Log3 $name, 3, "$name: set scan range specified as Modbus Id $hash->{scanIdStart} to $hash->{scanIdEnd}" .
                        " with $hash->{scanOType}$hash->{scanOAdr}, Len ";
        delete $hash->{scanId};
        
        my $now        = gettimeofday();
        my $scanDelay  = AttrVal($name, "scanDelay", 1);  
        RemoveInternalTimer ("scan:$name");
        InternalTimer($now+$scanDelay, "ModbusLD_ScanIds", "scan:$name", 0);   
        return "0";
        
    } elsif ($setName eq 'scanModbusObjects') { 
        my $msg = ModbusLD_CheckDisable($hash);
        return $msg if ($msg);
        return "set scanModbusObjects is only allowed when Fhem is Modbus master" if ($hash->{MODE} ne 'master');
        delete $hash->{scanId};
        delete $hash->{scanIdStart};
        delete $hash->{scanIdEnd};
        $hash->{scanOType}  = "h";
        $hash->{scanOStart} = "1";
        $hash->{scanOEnd}   = "16384";
        $hash->{scanOLen}   = "1";
        if ($setVal && $setVal =~ /([hicd][0-9]+) *- *([hicd]?([0-9]+)) ?(len)? ?([0-9]+)?/) {
            $hash->{scanOType}  = substr($1,0,1);
            $hash->{scanOStart} = substr($1,1);
            $hash->{scanOEnd}   = $3;
            $hash->{scanOLen}   = ($5 ? $5 : 1);
        }
        Log3 $name, 3, "$name: set scan $hash->{scanOType} from $hash->{scanOStart} to $hash->{scanOEnd} len $hash->{scanOLen}";        
        delete $hash->{scanOAdr};
        
        my $now        = gettimeofday();
        my $scanDelay  = AttrVal($name, "scanDelay", 1);  
        RemoveInternalTimer ("scan:$name");
        InternalTimer($now+$scanDelay, "ModbusLD_ScanObjects", "scan:$name", 0);
        return "0";
    } elsif ($setName eq 'saveAsModule') {         
        my $fName = $setVal;            
        my $out;
        my $last = "x";
        
        if (!open($out, ">", "/tmp/98_ModbusGen$fName.pm")) {
            Log3 $name, 3, "$name: set saveAsModule cannot create output file $hash->{OUTPUT}";
            return;
        };
        
        print $out "
##############################################
# \$Id: 98_ModbusGen${fName}.pm \$
# von ModbusAttr generiertes Modul 

package main;
use strict;
use warnings;

";
        print $out "sub ModbusGen${fName}_Initialize(\$);\n";
        print $out "my %ModbusGen${fName}parseInfo = (\n";
        
        foreach my $a (sort keys %{$attr{$name}}) {
            if ($a =~ /^obj-([^\-]+)-(.*)$/) {
                if ($1 ne $last) {
                    if ($last ne "x") {
                        # Abschluss des letzten Eintrags
                        printf $out "%26s", "},\n";
                    }
                    # Neuer Key
                    printf $out "%2s", " ";
                    printf $out "%16s%s", "\"$1\"", " =>  { ";
                    $last = $1;
                } else {
                    printf $out "%25s", " ";
                }
                printf $out "%15s%s", "\'".$2."\'", " => \'$attr{$name}{$a}\',\n";
            }
        }
        printf $out "%28s", "}\n";
        print  $out ");\n\n";
        print  $out "my %ModbusGen${fName}deviceInfo = (\n";

        $last = "x";
        foreach my $a (sort keys %{$attr{$name}}) {
            if ($a =~ /^dev-((type-)?[^\-]+)-(.*)$/) {
                if ($1 ne $last) {
                    if ($last ne "x") {
                        printf $out "%26s", "},\n";
                    }
                    printf $out "%2s", " ";
                    printf $out "%16s%s", "\"$1\"", " =>  { ";
                    $last = $1;
                } else {
                    printf $out "%25s", " ";
                }
                printf $out "%15s%s", "\'".$3."\'", " => \'$attr{$name}{$a}\',\n";
            }
        }
        printf $out "%28s", "}\n";
        print  $out ");\n\n";

        print  $out "
#####################################
sub ModbusGen${fName}_Initialize(\$)
{
    my (\$modHash) = \@_;
    require \"\$attr{global}{modpath}/FHEM/98_Modbus.pm\";
    \$modHash->{parseInfo}  = \\%ModbusGen${fName}parseInfo;  # defines registers, inputs, coils etc. for this Modbus Defive
    \$modHash->{deviceInfo} = \\%ModbusGen${fName}deviceInfo; # defines properties of the device like defaults and supported function codes

    ModbusLD_Initialize(\$modHash);              # Generic function of the Modbus module does the rest
    
    \$modHash->{AttrList} = \$modHash->{AttrList} . \" \" .     # Standard Attributes like IODEv etc 
        \$modHash->{ObjAttrList} . \" \" .                     # Attributes to add or overwrite parseInfo definitions
        \$modHash->{DevAttrList} . \" \" .                     # Attributes to add or overwrite devInfo definitions
        \"poll-.* \" .                                        # overwrite poll with poll-ReadingName
        \"polldelay-.* \";                                    # overwrite polldelay with polldelay-ReadingName
}
";
        
        return "0"; 
    }
    return undef;   # no control set identified - continue with other sets
}


#####################################
# called via internal timer from 
# logical device module with 
# scan:name - name of logical device
#
sub ModbusLD_ScanObjects($) {
    my $param = shift;
    my ($calltype,$name) = split(':',$param);
    my $hash       = $defs{$name};   # hash des logischen Devices, da GetUpdate aus dem logischen Modul per Timer gestartet wird
    my $now        = gettimeofday();
    my $scanDelay  = AttrVal($name, "scanDelay", 1);  
    my $ioHash     = ModbusLD_GetIOHash($hash);         # get ioHash to check for full queue. It has been checked in GetSetChecks
    my $queue      = $ioHash->{QUEUE};
    my $qlen       = ($ioHash->{QUEUE} ? scalar(@{$ioHash->{QUEUE}}) : 0);
    my $qMax       = AttrVal($ioHash->{NAME}, "queueMax", AttrVal($name, "queueMax", 100));
    RemoveInternalTimer ("scan:$name");
    if ($qlen && $qlen > $qMax / 2) {
        InternalTimer($now+$scanDelay, "ModbusLD_ScanObjects", "scan:$name", 0);
        Log3 $name, 5, "$name: ScanObjects waits until queue gets smaller";
        return;
    }
    if (defined($hash->{scanOAdr})) {
        if ($hash->{scanOAdr} < $hash->{scanOEnd}) {
            $hash->{scanOAdr}++;
        } else {
            delete $hash->{scanOAdr};
            delete $hash->{scanOStart};
            delete $hash->{scanOEnd};
            delete $hash->{scanOType};
            delete $hash->{scanOLen};
            return; # end
        }   
    } else {        
        $hash->{scanOAdr} = $hash->{scanOStart};
    }
    ModbusLD_DoRequest ($hash, $hash->{scanOType}.$hash->{scanOAdr}, 'scanobj', 0, 0, $hash->{scanOLen}, "scan");
    InternalTimer($now+$scanDelay, "ModbusLD_ScanObjects", "scan:$name", 0);
    return;
}


#####################################
# called via internal timer from 
# logical device module with 
# scan:name - name of logical device
#
sub ModbusLD_ScanIds($) {
    my $param = shift;
    my ($calltype,$name) = split(':',$param);
    my $hash       = $defs{$name};   # hash des logischen Devices, da GetUpdate aus dem logischen Modul per Timer gestartet wird
    my $now        = gettimeofday();
    my $scanDelay  = AttrVal($name, "scanDelay", 1);  
    my $ioHash     = ModbusLD_GetIOHash($hash);         # get ioHash to check for full queue. It has been checked in GetSetChecks
    my $queue      = $ioHash->{QUEUE};
    my $qLen       = ($ioHash->{QUEUE} ? scalar(@{$ioHash->{QUEUE}}) : 0);
    my $qMax       = AttrVal($ioHash->{NAME}, "queueMax", AttrVal($name, "queueMax", 100));
    
    RemoveInternalTimer ("scan:$name");
    if ($qLen && $qLen > $qMax) {
        InternalTimer($now+$scanDelay, "ModbusLD_ScanIds", "scan:$name", 0);
        Log3 $name, 5, "$name: ScanIds waits until queue gets smaller";
        return;
    }
    if ($hash->{scanId}) {
        if ($hash->{scanId} < $hash->{scanIdEnd}) {
            $hash->{scanId}++;
        } else {
            delete $hash->{scanId};
            delete $hash->{scanIdStart};
            delete $hash->{scanIdEnd};
            delete $hash->{scanOAdr};
            delete $hash->{scanOLen};
            delete $hash->{scanOType};

            return; # end
        }   
    } else {        
        $hash->{scanId} = $hash->{scanIdStart};
    }
    ModbusLD_DoRequest ($hash, $hash->{scanOType}.$hash->{scanOAdr}, 'scanid'.$hash->{scanId}, 0, 0, $hash->{scanOLen}, "scan ids");
    InternalTimer($now+$scanDelay, "ModbusLD_ScanIds", "scan:$name", 0);
    return;
}


#####################################
# called via expr
sub ModbusLD_ScanFormat($$) 
{
    my ($hash, $val) = @_;
    my $name = $hash->{NAME};
    use bytes;
    my $len = length($val);
    my $i   = unpack("s", $val);
    my $n   = unpack("S", $val);
    my $h   = unpack("H*", $val);
    Log3 $name, 5, "$name: ScanFormat hex=$h, bytes=$len";
    
    my $ret = "hex=$h, string=";
        for my $c (split //, $val) {
            if ($c =~ /[[:graph:]]/) {
                $ret .= $c;
            } else {
                $ret .= ".";
            }
        }
                
        $ret .= ", s=" . unpack("s", $val) .
        ", s>=" . unpack("s>", $val) .
        ", S=" . unpack("S", $val) .
        ", S>=" . unpack("S>", $val);
    if ($len > 2) {         
        $ret .= ", i=" . unpack("s", $val) .
        ", i>=" . unpack("s>", $val) .
        ", I=" . unpack("S", $val) .
        ", I>=" . unpack("S>", $val);

        $ret .= ", f=" . unpack("f", $val) .
        ", f>=" . unpack("f>", $val);

        #my $r1 = substr($h, 0, 4);
        #my $r2 = substr($h, 4, 4);
        #my $rev = pack ("H*", $r2 . $r1);
        #$ret .= ", revf=" . unpack("f", $rev) .
        #", revf>=" . unpack("f>", $rev);

    }
    return $ret;
}



####################################################################################
# Notify for INITIALIZED -> Open defined physical / logical (tcp) device
# both for physical and logical tcp connected devices
#
# Bei jedem Define erzeugt Fhem.pl ein $hash{NTFY_ORDER} für das 
# Device falls im Modul eine NotifyFn gesetzt ist.
#
# bei jedem Define, Rename oder Modify wird der interne Hash %ntfyHash
# gelöscht und beim nächsten Event in createNtfyHash() neu erzeugt 
# wenn er nicht existiert.
#
# Im %ntfyHash wird dann für jede mögliche Event-Quelle als Key auf die Liste
# der Event-Empfänger verwiesen.
#
# die createNtfyHash() Funktion schaut für jedes Device nach $hash{NOTIFYDEV}
# falls existent wird das Gerät nur für die in $hash{NOTIFYDEV} aufgelisteten 
# Event-Erzeuger in deren ntfyHash-Eintrag es Evet-Empfänger aufgenommen.
#
# Um ein Gerät als Event-Empfänger aus den Listen mit Event-Empfängern zu entfernen 
# könnte man $hash{NOTIFYDEV} auf "," setzen und %ntfyHash auf () löschen...
# 
# im Modul die NotifyFn zu entfernen würde den Aufruf verhindern, aber 
# $hash{NTFY_ORDER} bleibt und daher erzeugt auch createNtfyHash() immer wieder verweise
# auf das Gerät, obwohl die NotifyFn nicht mehr registriert ist ...
#
#
sub Modbus_Notify($$)
{
    my ($hash, $source) = @_;
    my $name  = $hash->{NAME};              # my Name
    my $sName = $source->{NAME};            # Name of Device that created the events
    return if($sName ne "global");          # only interested in global Events

    my $events = deviceEvents($source, 1);
    return if(!$events);                    # no events
    
    #Log3 $name, 5, "$name: Notify called for source $source->{NAME} with events: @{$events}";
    return if (!grep(m/^INITIALIZED|REREADCFG|(MODIFIED $name)$|(DEFINED $name)$/, @{$events}));
    # DEFINED is not triggered if init is not done.
    
    if (IsDisabled($name)) {
        Log3 $name, 3, "$name: Notify / Init: device is disabled";
        return;
    }   
    
    # physical device or TCP - open connection here
    if ($hash->{TYPE} eq "Modbus" || $hash->{TCPConn}) {   # physical device or Modbus TCP -> call open (even for slave)
        Log3 $name, 4, "$name: Notify / Init: opening connection";
        Modbus_Open($hash);                             # connection or listening socket for tcp slave
        
    } else {                                            # logical device and not Modbus TCP -> check for IO Device
        ModbusLD_UnregAtIODev($hash);                   # first unregster / cleanup potential old and wrong registrations and locks
        delete $hash->{IODev};                          # force call to setIODev and set state to opened
        my $ioHash = ModbusLD_GetIOHash($hash);
        if ($ioHash) {
            Log3 $name, 3, "$name: Notify / Init: using $ioHash->{NAME} for communication";
            #ModbusLD_RegisterAtIODev($hash, $ioHash);  # no need to call this - already done when calling GetIOHash ...
        } else {
            Log3 $name, 3, "$name: Notify / Init: no IODev for communication";
            # continue anyway - maybe we'll have an iodev later
        }
    }
    # logical device going through an IO Device
    if ($hash->{TYPE} ne "Modbus" && $hash->{MODE} eq 'master') {        
        ModbusLD_StartUpdateTimer($hash);               # logical device -> first Update in 1 second or aligned if interval is defined
    
    # relay device to communicate through
    } elsif ($hash->{MODE} && $hash->{MODE} eq 'relay') {    # Mode relay -> find / check relay device
        my $reName = $hash->{RELAY};
        my $reIOHash = Modbus_GetRelayIO($hash);
        if ($reIOHash) {
            Log3 $name, 3, "$name: Notify / Init: using $reName as Modbus relay device";
        } else {
            Log3 $name, 3, "$name: Notify / Init: no relay device for communication ($reName must be a modbus master)";
        }
    }
    #Log3 $name, 3, "$name: _Notify done";
    return;
}


###########################
# open connection 
# $hash is physical or both (connection over TCP)
# called from set reconnect, Attr / LDAttr (disable), 
#        Notify (initialized, rereadcfg, |(MODIFIED $name)), 
#        Ready, ProcessRequestQueue and GetSetChecks
sub Modbus_Open($;$$$)
{
    my ($hash, $ready, $force, $closeFirst) = @_;
    my $name   = $hash->{NAME};
    my $now    = gettimeofday();
    my $caller = Modbus_Caller();
    $ready    = 0 if (!$ready);
    
    if (!$hash->{TCPConn} && $hash->{TYPE} ne 'Modbus') {
        Log3 $name, 3, "$name: open called from $caller for logical device - this should not happen";
        return;
    }
    if ($hash->{TCPChild}) {
        Log3 $name, 3, "$name: open called for a TCP Child hash - this should not happen";
        return;
    }
    if ($hash->{TCPServer}) {
        # Modbus slave or relay over TCP connection -> open listening port
        Log3 $name, 5, "$name: Open called for listening to a TCP connection";
        if ($closeFirst && $hash->{FD}) {       # DevIo_IsOpen($hash) doesn't work for TCP server 
            Modbus_Close($hash, 1);             # close, set Expect, clear Buffer, don't set state
        }
        my ($dest, $port) = split("[: \t]+", $hash->{DeviceName});
        my $ret = TcpServer_Open($hash, $port, $dest);
        if ($ret) {
            Log3 $name, 3, "$name: TcpServerOpen returned $ret";
        } else {
            $hash->{STATE} = "opened";
            readingsSingleUpdate($hash, "state", "opened", 1);
        }
    } else {
        Log3 $name, 5, "$name: open called from $caller" if ($caller ne "Ready"); 
        if ($hash->{BUSY_OPENDEV}) {            # still waiting for callback to last open 
            if ($hash->{LASTOPEN} && $now > $hash->{LASTOPEN} + (AttrVal($name, "openTimeout", 3) * 2)
                                  && $now > $hash->{LASTOPEN} + 15) {
                Log3 $name, 3, "$name: open - still waiting for open callback, timeout is over twice - this should never happen";
                Log3 $name, 3, "$name: open - stop waiting for callback and reset the BUSY flag.";
                $hash->{BUSY_OPENDEV} = 0;
            } else {
                return;
            }
        }    
        if (!$ready) {                              # not called from _Ready
            if ($closeFirst && DevIo_IsOpen($hash)) {   # close first and already open
                Log3 $name, 5, "$name: Open called for DevIo connection - closing first";
                Modbus_Close($hash, 1);             # close, set Expect, clear Buffer, don't set state to disconnected
                delete $hash->{NEXT_OPEN};
                delete $hash->{DevIoJustClosed};    # allow direct opening without further delay
            } else {
                if ($hash->{LASTOPEN} && $now < $hash->{LASTOPEN} + (AttrVal($name, "openTimeout", 3))) {
                    # ignore too many open requests within openTimeout without close inbetween (let ready do its job)
                    Log3 $name, 5, "$name: successive open ignored";
                    return;
                }
            }
        }
        Log3 $name, 4, "$name: open trying to open connection to $hash->{DeviceName}" if (!$ready);
        $hash->{IODev}          = $hash if ($hash->{TCPConn});     # point back to self
        $hash->{BUSY_OPENDEV}   = 1;
        $hash->{LASTOPEN}       = $now;
        $hash->{nextOpenDelay}  = AttrVal($name, "nextOpenDelay", 60);   
        $hash->{devioLoglevel}  = (AttrVal($name, "silentReconnect", 0) ? 4 : 3);
        $hash->{TIMEOUT}        = AttrVal($name, "openTimeout", 3);
        if ($force) {
            DevIo_OpenDev($hash, $ready, 0);                       # standard open
        } else {
            DevIo_OpenDev($hash, $ready, 0, \&Modbus_OpenCB);      # async open
        }
    }
    $hash->{EXPECT} = (!$hash->{MODE} || $hash->{MODE} eq 'master' ? 'idle' : 'request');
    Modbus_StopQueueTimer($hash);
    $hash->{READ}{BUFFER} = "";                           # clear Buffer for reception
    delete $hash->{TIMEOUT};
    return;
}


#####################################
sub Modbus_OpenCB($$)
{
    my ($hash, $msg) = @_;
    my $name = $hash->{NAME};
    if ($msg) {
        Log3 $name, 5, "$name: Open callback: $msg" if ($msg);
    }
    delete $hash->{BUSY_OPENDEV};
    if (DevIo_IsOpen($hash)) {
        delete $hash->{TIMEOUTS} ;
        ModbusLD_StartUpdateTimer($hash);       # if INTERVAL is set in this device
    }
    return;
}


##################################################
# close connection 
# $hash is physical or both (connection over TCP)
sub Modbus_Close($;$$)
{
    my ($hash, $noState, $noDelete) = @_;
    my $name = $hash->{NAME};
    
    if (!$hash->{TCPConn} && $hash->{TYPE} ne 'Modbus') {
        Log3 $name, 3, "$name: close called from " . Modbus_Caller() . 
                        " for logical device - this should not happen";
        return;
    }
    
    Log3 $name, 5, "$name: Close called from " . Modbus_Caller() . 
        ($noState || $noDelete ? " with " : "") . ($noState ? "noState" : "") .     # set state?
        ($noState && $noDelete ? " and " : "") . ($noDelete ? "noDelete" : "");     # command delete on connection device?
    
    delete $hash->{LASTOPEN};               # reset so next open will actually call OpenDev
    if ($hash->{TCPChild}) {
        if (defined($hash->{CD})) {         # connection hash
            Log3 $name, 4, "$name: Close TCP server connection and delete hash";
            TcpServer_Close($hash);
            RemoveInternalTimer ("stimeout:$name");
            CommandDelete(undef, $name) if (!$noDelete);
            if ($hash->{CHILDOF} && $hash->{CHILDOF}{LASTCONN} && $hash->{CHILDOF}{LASTCONN} eq $hash->{NAME}) {
                Log3 $name, 5, "$name: Close is removing lastconn from parent device $hash->{CHILDOF}{NAME}";
                delete $hash->{CHILDOF}{LASTCONN}
            }
        }
    } elsif ($hash->{TCPServer}) {
        if ($hash->{FD}){
            Log3 $name, 4, "$name: Close TCP server socket, now look for active connections";
            TcpServer_Close($hash);
            foreach my $conn (keys %{$hash->{CONNECTHASH}}) {
                my $chash = $hash->{CONNECTHASH}{$conn};
                TcpServer_Close($chash);
                Log3 $chash->{NAME}, 4, "$chash->{NAME}: Close TCP server connection of parent $name and delete hash";
                RemoveInternalTimer ("stimeout:$chash->{NAME}");
                CommandDelete(undef, $chash->{NAME}) if (!$noDelete);
            }
            delete $hash->{CONNECTHASH};
            Log3 $name, 4, "$name: Close deleted CONNECTHASH";
        }
    } else {
        Log3 $name, 4, "$name: Close connection with DevIo_CloseDev";
        # close even if it was not open yet but on ready list (need to remove entry from readylist)
        DevIo_CloseDev($hash);
    }
    
    if (!$noState) {
        $hash->{STATE} = "disconnected";
        readingsSingleUpdate($hash, "state", "disconnected", 1);
    }
    
    $hash->{EXPECT} = 'idle';
    $hash->{READ}{BUFFER} = "";       # clear Buffer for reception
    Modbus_StopQueueTimer($hash);
    RemoveInternalTimer ("timeout:$name");
    ModbusLD_StopUpdateTimer($hash);
    delete $hash->{nextTimeout};
    delete $hash->{QUEUE};
}
    

# ready fn for physical device
# and logical device (in case of tcp when logical device opens connection)
###########################################################################
sub Modbus_Ready($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};
    
    if($hash->{STATE} eq "disconnected") {  
        if (IsDisabled($name)) {
            Log3 $name, 3, "$name: ready called but $name is disabled - don't try to reconnect - call Modbus_close";
            Modbus_Close($hash, 1);         # close, set Expect, clear Buffer, don't set state to disconnected
            return;
        }
        Modbus_Open($hash, 1);      # reopen, dont call DevIoClose before reopening
        return;                     # a return value only triggers direct read for windows - main loop select
    }
    # This is relevant for windows/USB only
    my $po = $hash->{USBDev};
    if ($po) {
        my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
        return ($InBytes>0);        # tell fhem.pl to read when we return if data available
    }
    return;
}




#####################################
# Called from the global loop, when the select for hash->{FD} reports data
# hash is hash of the physical device ( = logical device for TCP)
sub Modbus_HandleServerConnection($)
{
    my $hash  = shift;
    my $name  = $hash->{NAME};
    my $chash = TcpServer_Accept($hash, $hash->{TYPE}); # accept with this module
    return if(!$chash);
    $chash->{CD}->flush();
    Log3 $name, 4, "$name: HandleServerConnection accepted new TCP connection as device $chash->{NAME}";
    $chash->{MODBUSID}  = $hash->{MODBUSID};
    $chash->{PROTOCOL}  = $hash->{PROTOCOL};
    $chash->{MODE}      = $hash->{MODE};
    $chash->{RELAY}     = $hash->{RELAY};
    $chash->{CHILDOF}   = $hash;                                # point to parent device to get object definitions from there
    $chash->{IODev}     = $chash;
    $chash->{TCPConn}   = 1;
    $chash->{TCPChild}  = 1;
    $chash->{EXPECT}    = 'request';
    DoTrigger("global", "DEFINED $chash->{NAME}", 1) if($init_done);    
    $attr{$chash->{NAME}}{verbose} = $attr{$name}{verbose};     # copy verbose attr from parent
    $hash->{LASTCONN} = $chash->{NAME};                         # point from parent device to last connection device
    $hash->{CONNECTHASH}{$chash->{NAME}} = $chash;
    CommandAttr(undef, "$chash->{NAME} room Connections");      # try to set room (doesn't work reliably yet)
    
    my $to = gettimeofday() + Modbus_DevInfo($hash, "timing", "serverTimeout", 120); 
    InternalTimer($to, "Modbus_ServerTimeout", "stimeout:$chash->{NAME}", 0);

    return;
}


##############################################
# check time gap between now and last read
# to clear old buffer or set expect to request
sub Modbus_HandleGaps($)
{
    my $hash = shift;
    my $name = $hash->{NAME};
    my $now  = gettimeofday();

    # check timing / frameGap and remove old buffer if necessary
    my $to  = AttrVal($name, "frameGap", 1.5);
    if ($hash->{REMEMBER}{lrecv}) {
        my $gap = ($now - $hash->{REMEMBER}{lrecv});
        if ($gap > $to && $hash->{READ}{BUFFER}) {
            Log3 $name, 5, "$name: read drops existing buffer content " . 
                        unpack ('H*', $hash->{READ}{BUFFER}) . " after " . sprintf ('%.2f', $gap) . " secs.";
            $hash->{READ}{BUFFER} = '';
        }
        if ($gap > $to * 2) {
            if ($hash->{MODE} ne 'master') {
                $hash->{EXPECT} = 'request';
                Log3 $name, 5, "$name: read gap is twice timeout -> expecting a new request now";
            }
        }
    } else {
        if ($hash->{READ}{BUFFER}) {
            Log3 $name, 5, "$name: read initially clears existing buffer content " .
                unpack ('H*', $hash->{READ}{BUFFER});
            $hash->{READ}{BUFFER} = '';
        }
    }
}


#####################################
# Called from the global loop, when the select for hash->{FD} reports data
# hash is hash of the physical device ( = logical device for TCP)
sub Modbus_Read($)
{
    my $hash = shift;
    my $name = $hash->{NAME};
    my $now  = gettimeofday();
    my $buf;
    
    if (!$hash->{MODE} || !$hash->{PROTOCOL}) { # MODE and PROTOCOL keys are taken from logical device in NOTIFY
        $hash->{READ}{BUFFER} = '';             # nothing defined / initializd yet
        return;                                 # EXPECT doesn't matter, Logging frame not needed
    }
    
    if($hash->{TCPServer} || $hash->{TCPChild}) {   
        # TCP Server mode
        if($hash->{SERVERSOCKET}) {   
            # this is a TCP server / modbus slave device , accept and create a child device hash for the connection
            Modbus_HandleServerConnection($hash);
            return;
        } else {        # TCP client device connection device hash
            Modbus_Profiler($hash, "Read"); 
            my $ret = sysread($hash->{CD}, $buf, 256) if ($hash->{CD});
            if(!defined($ret) || $ret <= 0) {   # connection closed
                Log3 $name, 3, "$name: read from TCP server connection got null -> closing";
                CommandDelete(undef, $name);
                return;
            }
            RemoveInternalTimer ("stimeout:$name");
            my $to = $now + Modbus_DevInfo($hash, "timing", "serverTimeout", 120); 
            InternalTimer($to, "Modbus_ServerTimeout", "stimeout:$name", 0);
        }
    } else {
        Modbus_Profiler($hash, "Read"); 
        $buf = DevIo_SimpleRead($hash);
        return if(!defined($buf));
    }
    
    Modbus_HandleGaps ($hash);              # check timing / frameGap and remove old buffer if necessary
    $hash->{READ}{BUFFER} .= $buf;  
    $hash->{REMEMBER}{lrecv} = $now;        # physical side
    Log3 $name, 5, "$name: read buffer: " . unpack ('H*',$hash->{READ}{BUFFER}); 
    delete $hash->{FRAME};                  # remove old stuff
        
    for (;;) {
        # parse frame start, create $hash->{FRAME} with {MODBUSID}, {FCODE}, {DATA}
        # and for TCP also $hash->{FRAME}{PDULEXP} and $hash->{FRAME}{TID}
        if (!Modbus_ParseFrameStart($hash)) {
            # not enough data / no frame match
            Log3 $name, 5, "$name: read did not see a valid frame start yet, wait for more data";
            return;
        }    
        my $frame = $hash->{FRAME};                         # is set after HandleFrameStart
        
        if ($hash->{EXPECT} eq 'response') {                # --- RESPONSE ---
            if (Modbus_HandleResponse($hash)) {             # check for valid PDU, CRC, parse, set DEVHASH, log, drop data, ret 1 if done
                delete $hash->{REQUEST};
                delete $hash->{RESPONSE};
                Modbus_StartQueueTimer($hash, 0);           # call processRequestQueue at next possibility if appropriate
            } else {
                return;                                     # wait for more data
            }
            
        } elsif ($hash->{EXPECT} eq 'request') {            # --- REQUEST ---
            if (Modbus_HandleRequest($hash)) {              # check for valid PDU, parse, set DEVHASH, ret 1 if finished
                                                            # ERROR is only set by Checkum Check or unsupported fCode here.
            } else {
                return;                                     # wait for more data
            }
        } elsif ($hash->{EXPECT} eq 'waitrelay') {          # still waiting for response from relay device
            Log3 $name, 3, "$name: read got new data while waiting for relay response, expect $hash->{EXPECT}, drop buffer " .
                unpack ('H*', $hash->{READ}{BUFFER});
            $hash->{READ}{BUFFER} = '';
            return;

        } elsif ($hash->{EXPECT} eq 'idle') {               # master is doing nothing but maybe there is an illegal other master?
            Log3 $name, 3, "$name: read got new data while idle, drop buffer " .
                unpack ('H*', $hash->{READ}{BUFFER});
            $hash->{READ}{BUFFER} = '';
            return;
            
        } else {        
            Log3 $name, 3, "$name: internal error, illegal EXPECT value $hash->{EXPECT}, drop buffer " .
                unpack ('H*', $hash->{READ}{BUFFER});
            $hash->{READ}{BUFFER} = '';
            return;
            
        }
        return if (!$hash->{READ}{BUFFER});                 # return if no more data, else parse on
    }
}



################################################################################
# Called from get / set to get a direct answer - only for Fhem as master.
# calls ReadAnswerTimeout or ReadAnswerError 
# Returns an error message or undef if success.
# queue time is started after calling ReadAnswer as well as in ReadAnswerTimeout and ReadAnswerError
sub Modbus_ReadAnswer($)
{
    my ($hash) = @_;                            # called with physicak io device hash
    my $name = $hash->{NAME};       
    my $now  = gettimeofday();
    
    Log3 $name, 5, "$name: ReadAnswer called from " . Modbus_Caller();
    
    return "No IO Device hash" if (!$hash);
    if (IsDisabled ($name)) {
        return Modbus_ReadAnswerError($hash, "ReadAnswer called but Device $name is disabled");
    }
    return Modbus_ReadAnswerError($hash, "ReadAnswer called but Device $name is not connected") 
        if ($^O !~ /Win/ && !defined($hash->{FD}));
    return Modbus_ReadAnswerError($hash, "ReadAnswer called but Device $name mode or protocol not set")
        if (!$hash->{MODE} || !$hash->{PROTOCOL});
    # MODE and PROTOCOL are set in Notify for logcal device. Probably this case can never happen
    # for these early returns nothing more needs to be done because further sending / reading fails anyway

    my $buf;
    my $rin = '';

    my $logHash = $hash->{REQUEST}{DEVHASH};            # logical device that sent the last request
    # note that this might be a diffrent logical device than the one we got called from!
    # get timeout. In case ReadAnswer is called after a delay or to take over an async read, 
    # only wait for remaining time
    my $to   = Modbus_DevInfo($logHash, "timing", "timeout", 2); 
    my $rest = ($hash->{nextTimeout} ? $hash->{nextTimeout} - $now : 0);        
    # nextTimeout is set when a request is sent. This can be the last getUpdate or the get/set

    if ($rest <= 0) {
        return Modbus_ReadAnswerTimeout($hash, "Timeout already over when ReadAnswer is called");
    }
    if ($rest < $to) {
        Log3 $name, 5, "$name: ReadAnswer called and remaining timeout is $rest";
        $to = $rest;
    } else {
        Log3 $name, 5, "$name: ReadAnswer called";
    }
    
    RemoveInternalTimer ("timeout:$name");              # remove timer, timeout is handled in here now
    Modbus_Profiler($hash, "Read");     
    for (;;) {

        if($^O =~ m/Win/ && $hash->{USBDev}) {        
            $hash->{USBDev}->read_const_time($to*1000);   # set timeout (ms)
            $buf = $hash->{USBDev}->read(999);
            if(length($buf) == 0) {
                return Modbus_ReadAnswerTimeout($hash, "Timeout waiting for a modbus response in ReadAnswer");
            }
        } else {
            if(!$hash->{FD}) {
                return Modbus_ReadAnswerError($hash, "ReadAnswer called but Device $name lost connection");
            }
            vec($rin, $hash->{FD}, 1) = 1;    # setze entsprechendes Bit in rin
            my $nfound = select($rin, undef, undef, $to);
            if($nfound < 0) {
                next if ($! == EAGAIN() || $! == EINTR() || $! == 0);
                my $err = $!;
                DevIo_Disconnected($hash);  # close, set state but put back on readyfnlist for reopening
                Log3 $name, 3, "$name: ReadAnswer error: $err";
                return "Modbus_ReadAnswer error: $err";
            }
            if($nfound == 0) {
                return Modbus_ReadAnswerTimeout($hash, "Timeout waiting for a modbus response in ReadAnswer");
            }

            $buf = DevIo_SimpleRead($hash);
            if(!defined($buf)) {
                return Modbus_ReadAnswerError($hash, "ReadAnswer got no data");
            }
        }
        if($buf) {
            $now = gettimeofday();
            $hash->{READ}{BUFFER} .= $buf;
            $hash->{REMEMBER}{lrecv}    = $now;
            $logHash->{REMEMBER}{lrecv} = $now;
            Log3 $name, 5, "$name: ReadAnswer got: " . unpack ("H*", $hash->{READ}{BUFFER});
        }
        
        delete $hash->{FRAME};              # remove old stuff
        # get $hash->{FRAME}{MODBUSID}, $hash->{FRAME}{FCODE}, $hash->{FRAME}{DATA}
        # and for TCP also $hash->{FRAME}{PDULEXP} and $hash->{FRAME}{TID}
        if (!Modbus_ParseFrameStart($hash)) {
            # not enough data / no frame match
            Log3 $name, 5, "$name: ReadAnswer got no valid frame after HandleFrameStart, wait for more data";
            next;
        }    
        my $frame = $hash->{FRAME};         # is set after HandleFrameStart     
        # check for valid PDU with checksum, parse, remove, log
        if (Modbus_HandleResponse($hash)) { # end of parsing. error or valid frame, calls ResponseDone at end
            my $ret;
            if ($hash->{RESPONSE}{ERRCODE}) {
                $ret = "Error code $hash->{RESPONSE}{ERRCODE} / $Modbus_errCodes{$hash->{RESPONSE}{ERRCODE}}";
                Log3 $name, 5, "$name: ReadAnswer got $ret";
            }
            delete $hash->{REQUEST};
            delete $hash->{RESPONSE};
            return $ret;
        }
    }
}


sub Modbus_SkipGarbageCheck($$) 
{
    my ($hash, $startByte) = @_;
    my $name = $hash->{NAME};
    my ($start, $skip);
    
    $start = index($hash->{READ}{BUFFER}, $startByte);
    if ($start > 0) {
        $skip  = substr($hash->{READ}{BUFFER}, 0, $start);
        $hash->{READ}{BUFFER} = substr($hash->{READ}{BUFFER}, $start);
        Log3 $name, 4, "$name: SkipGarbageCheck skipped $start bytes (" . 
                unpack ('H*', $skip) . " from " .  unpack ('H*', $hash->{READ}{BUFFER}) . ")";
    }
    return $hash->{READ}{BUFFER};
}


#####################################################
# parse the beginning of a request or response frame
sub Modbus_ParseFrameStart($)
{
    my ($hash) = @_;
    my $name  = $hash->{NAME};
    my $proto = $hash->{PROTOCOL};
    my $expId = $hash->{REQUEST}{MODBUSID} if ($hash->{REQUEST} && $hash->{REQUEST}{MODBUSID});
    my $frameString = $hash->{READ}{BUFFER};
    my ($id, $fCode, $data, $tid, $dlen, $pdu, $null);
    
    #Log3 $name, 5, "$name: ParseFrameStart called from " . Modbus_Caller();
    use bytes;
    if ($proto eq "RTU") {
        # Skip for RTU only works when expectId is passed (parsing Modbus responses from a known Id)
        $frameString = Modbus_SkipGarbageCheck($hash, pack('C', $expId)) if ($expId);
        if ($frameString =~ /(..)(.+)(..)/s) {        # (id fCode) (data) (crc)     /s means treat as single line ...
            ($id, $fCode) = unpack ('CC', $1);
            $data = $2;
        } else {
            return undef;                       # data still incomplete - continue reading
        }
        
    } elsif ($proto eq "ASCII") {
        $frameString = Modbus_SkipGarbageCheck($hash, ':');
        if ($frameString =~ /:(..)(..)(.+)(..)\r\n/) {# : (id) (fCode) (data) (lrc) \r\n
            no warnings;                        # no warning if data is not hex
            $id    = hex($1);
            $fCode = hex($2);
            $data  = pack('H*', $3);
        } else {
            return undef;                       # data still incomplete - continue reading
        }

    } elsif ($proto eq "TCP") {
        if (length($frameString) < 8) {
            return undef;
        }
        ($tid, $null, $dlen, $id, $pdu) = unpack ('nnnCa*', $frameString);
        ($fCode, $data) = unpack ('Ca*', $pdu);
        $hash->{FRAME}{TID} = $tid;
        $hash->{FRAME}{PDULEXP} = $dlen-1;  # data length without id
        #Log3 $name, 5, "$name: ParseFrameStart for TCP extracted tid $tid, null, dlen $dlen, id $id and pdu " . unpack ('H*', $pdu);
    }
    $hash->{FRAME}{MODBUSID} = $id;
    $hash->{FRAME}{FCODE} = $fCode;
    $hash->{FRAME}{DATA} = $data;
    Log3 $name, 4, "$name: ParseFrameStart ($proto) extracted id $id, fCode $fCode" .
            ($hash->{FRAME}{TID} ? ", tid " . $hash->{FRAME}{TID} : "") .
            ($dlen ? ", dlen " . $dlen : "") .
            " and data " . unpack ('H*', $data);
    return 1;
}


#############################################################################
# called after ParseFrameStart by read / readAnswer if we are master
# check that response fits our request_method, call parseResponse
# validate checksums, call parseObj to set readings
# return undef if need more data or 1 if final success or error.
# responseDone is called at the end
#
# note that we could be the master part of a relay and the request 
# might have come in through a TCP slave part of the relay
# so data in the response might need to be interpreted in the context
# of a TCP slave parent device ...
#############################################################################
sub Modbus_HandleResponse($)
{
    my ($hash) = @_;
    my $name  = $hash->{NAME};
    my $frame = $hash->{FRAME};
    my $logHash;
    my $request = $hash->{REQUEST};
    
    Log3 $name, 5, "$name: HandleResponse called from " . Modbus_Caller();
    
    if ($request) {
        $logHash = $request->{DEVHASH};
        if ($request->{FRAME} && $hash->{READ}{BUFFER} eq $request->{FRAME} && $frame->{FCODE} < 5) {
            Log3 $name, 3, "$name: HandleResponse read the same data sent before - looks like an echo!";    
            # just log, looks strange but might be ok.
        }
        
        if ($frame->{MODBUSID} != $request->{MODBUSID} && $request->{MODBUSID} != 0) {
            Modbus_AddFrameError($frame, "Modbus ID $frame->{MODBUSID} of response does not match request ID $request->{MODBUSID}");
        }
        if ($hash->{PROTOCOL} eq "TCP" && $request->{TID} != $frame->{TID}) {
            Modbus_AddFrameError($frame, "TID $frame->{TID} in Modbus TCP response does not match request TID $request->{TID}");
        }   
        if ($request->{FCODE} != $frame->{FCODE} && $frame->{FCODE} < 128) {
            Modbus_AddFrameError($frame, "Function code $frame->{FCODE} in Modbus response does not match request function code $request->{FCODE}");
        }
    } else {
        Log3 $name, 5, "$name: HandleResponse got data but we don't have a request";
        $logHash = Modbus_GetLogHash ($hash, $frame->{MODBUSID});
    }
    
    $hash->{REMEMBER}{lid} = $frame->{MODBUSID};        # device id we last heard from 
    if ($logHash) {
        $logHash->{REMEMBER}{lrecv} = gettimeofday();
        $hash->{REMEMBER}{lname}  = $logHash->{NAME};   # logical device name
    }
    
    my %responseData;                                   # create new response structure
    my $response = \%responseData;
    $response->{ADR}       = $request->{ADR};           # prefill so we don't need $request in ParseResponse and it gets shorter
    $response->{LEN}       = $request->{LEN};
    $response->{DEVHASH}   = $request->{DEVHASH};       # needed for relay responses
    $response->{OPERATION} = $request->{OPERATION};     # for later call to parseObj
    
    my %brokenFC;
    if ($logHash) {
        $brokenFC{3} = Modbus_DevInfo($logHash, "c", "brokenFC3", 0);
        $brokenFC{5} = Modbus_DevInfo($logHash, "c", "brokenFC5", 0);
    } else {
        $brokenFC{3} = 0;       
    }

    # parse response and fill response hash
    # also $frame->{PDULEXP} will be set now if not already earlier.    
    if (!Modbus_ParseResponse($hash, $response, %brokenFC)) {
        return;                         # frame not complete - continue reading
    }
    $hash->{RESPONSE} = $response;      # save for later parsing of response
    my $frameLen = $frame->{PDULEXP} + $Modbus_PDUOverhead{$hash->{PROTOCOL}};
    my $readLen  = length($hash->{READ}{BUFFER});
    
    Modbus_CheckChecksum($hash);        # calls AddFrameError if needed so $frame->{ERROR} might be set afterwards if checksum wrong
    
    if ($frame->{ERROR}) {              # can be wrong ID, TID or fCode (set above) or unsupported fCode or bad checksum
        if ($readLen < $frameLen ) {
            Log3 $name, 5, "$name: HandleResponse did not get a valid frame yet, wait for more data";
            return;                     # frame not complete and error - continue reading
        }
    } else {
        # no error so far
        if ($readLen < $frameLen ) {
            # frame is too small but no error - even checksum is fine!
            if (!$logHash || !Modbus_DevInfo($logHash, $response->{TYPE}, "allowShortResponses", 0)) {
                Log3 $name, 5, "$name: HandleResponse got a short Frame with valid checksum - wait for more data";
                return;                 # frame seems valid but is too short and short frames are not allowed -> continue reading
            }
        }
        
        # got a valid frame, long enough
        Modbus_Profiler($hash, "Fhem");   
        if ($response->{ERRCODE}) {         # valid error message response
            my $hexFCode = unpack ("H*", pack("C", $response->{FCODE}));
            my $errCode  = $Modbus_errCodes{$response->{ERRCODE}};
            if ($logHash) {                 # be quiet if no logical device hash (not our responsibility)
                Log3 $name, 4, "$name: HandleResponse got response with error code $hexFCode / $response->{ERRCODE}" . 
                        ($errCode ? ", $errCode" : "");
            }
        } else {                            # no error response, now check if we can parse data
            if ($frame->{FCODE} < 15) {     # is there data to parse? (nothing to parse after response to 15 / 16)
                if ($logHash) {
                    # loghash is the logical device stored as DEVHASH in Request 
                    #     that's the device that sent the request if we are the master
                    #     or the salve part of a relay that received the original request 
                    # or (if no request) the device registered with id (probably this doesn't lead anywhere then)
                                        
                    my $parseLogHash1 = ($logHash->{CHILDOF} ? $logHash->{CHILDOF} : $logHash);
                    if ($parseLogHash1) {   # try to parse in logical device that sent request
                        Log3 $name, 5, "$name: HandleResponse now passing to logical device $parseLogHash1->{NAME} for parsing data";
                        ModbusLD_ParseObj($parseLogHash1, $response);     
                        Log3 $name, 5, "$name: HandleResponse got " . scalar keys (%{$parseLogHash1->{gotReadings}}) . " readings from ParseObj for $parseLogHash1->{NAME}";
                    }
                }
                if ($logHash->{MODE} eq 'relay' && $logHash->{RELAY}) {
                    # as a relay also try to parse the response in the logical relay forward device                     
                    my $parseLogHash2 = $defs{$logHash->{RELAY}};
                    if ($parseLogHash2) {
                        Log3 $name, 5, "$name: HandleResponse now also passing to logical device $parseLogHash2->{NAME} for parsing data";
                        ModbusLD_ParseObj($parseLogHash2, $response);     
                        Log3 $name, 5, "$name: HandleResponse got " . scalar keys (%{$parseLogHash2->{gotReadings}}) . " readings from ParseObj for $parseLogHash2->{NAME}";
                    }
                }
            }
        }
        if ($response->{DEVHASH} && $response->{DEVHASH}{MODE} eq 'relay') {
            Modbus_RelayResponse($hash);        # add to {ERROR} if relay device is unavailable
        }
    }
    Modbus_ResponseDone($hash, 4);              # log, profiler, drop data, timer
    return 1;                                   # error or not, parsing is done.
}


#
# Parse Response, called from handleResponse with 
# require {FRAME} to be filled before by HandleFrameStart
# fill {RESPONSE} and some more fields of {FRAME}
#######################################################################
sub Modbus_ParseResponse($$%)
{
    my ($hash, $response, %brokenFC) = @_;
    my $name  = $hash->{NAME};
    my $frame = $hash->{FRAME};
    Log3 $name, 5, "$name: ParseResponse called from " . Modbus_Caller();
    
    return undef if (!$frame->{FCODE});                     # function code has been extracted
    my $fCode  = $frame->{FCODE};                           # filled in handleFrameStart
    my $data   = $frame->{DATA};
    
    use bytes;
    $response->{FCODE}    = $fCode;
    $response->{MODBUSID} = $frame->{MODBUSID};
    
    # if we don't have enough data then checksum check will fail later which is fine.
    # however unpack might produce undefined results if there is not enough data so return early.
    my $dataLength = length($data);
    if ($fCode == 1 || $fCode == 2) {                       
        # read coils / discrete inputs,                     pdu: fCode, num of bytes, coils
        # adr and len are copied from request
        return if ($dataLength) < 1;
        my ($len, $values) = unpack ('Ca*', $data);         # length of values data and values from frame
        $response->{VALUES}   = $values;
        $response->{TYPE}     = ($fCode == 1 ? 'c' : 'd');  # coils or discrete inputs
        $frame->{PDULEXP}     = $len + 2;                   # 1 Byte fCode + 1 Byte len + len of expected values
        
    } elsif ($fCode == 3 || $fCode == 4) {                  
        # read holding/input registers,                     pdu: fCode, num of bytes, registers
        return if ($dataLength) < 1;
        my ($len, $values) = unpack ('Ca*', $data);
        $response->{TYPE}  = ($fCode == 3 ? 'h' : 'i');     # holding registers / input registers
        $frame->{PDULEXP}  = $len + 2;                      # 1 Byte fCode + 1 Byte len + len of expected values
        if ($brokenFC{3} && $fCode == 3) {
            # devices that respond with wrong pdu           pdu: fCode, adr, registers
            Log3 $name, 5, "$name: ParseResponse uses fix for broken fcode 3";
            my $adr;
            ($adr, $values)   = unpack ('na*', $data);
            $response->{ADR}  = $adr;                       # adr of registers
            $frame->{PDULEXP} = $response->{LEN} * 2 + 3;   # 1 Byte fCode + 2 Byte adr + 2 bytes per register
        }
        $response->{VALUES} = $values;
        
    } elsif ($fCode == 5) {                                 
        # write single coil,                                pdu: fCode, adr, coil (FF00)
        return if ($dataLength) < 3;
        my ($adr, $values) = unpack ('nH4', $data);         # 2 bytes adr, 2 bytes values
        if ($brokenFC{5} && $fCode == 5) {
            Log3 $name, 5, "$name: ParseResponse uses fix for broken fcode 5";
            $values = ($values eq "0000" ? 0 : 1);
        } else {
            $values = ($values eq "ff00" ? 1 : 0);
        }
        $response->{ADR}    = $adr;                         # adr of coil
        $response->{LEN}    = 1;                            # always one coil
        $response->{VALUES} = $values;
        $response->{TYPE}   = 'c';                          # coils
        $frame->{PDULEXP}   = 5;                            # 1 Byte fCode + 2 Bytes adr + 2 Bytes coil

    } elsif ($fCode == 6) {        
        # write single (holding) register,                  pdu: fCode, adr, register
        return if ($dataLength) < 2;
        my ($adr, $values)  = unpack ('na*', $data);  
        $response->{ADR}    = $adr;                         # adr of register
        $response->{VALUES} = $values;
        $response->{TYPE}   = 'h';                          # holding registers
        $frame->{PDULEXP}   = 5;                            # 1 Byte fCode + 2 Bytes adr + 2 Bytes register
        
    } elsif ($fCode == 15 || $fCode == 16) {                
        # write mult coils/hold. regis,                     pdu: fCode, adr, len    
        return if ($dataLength) < 2;
        $response->{TYPE} = ($fCode == 15 ? 'c' : 'c');     # coils / holding registers
        $frame->{PDULEXP} = 5;                              # 1 byte fCode + 2 byte adr + 2 bytes len   
        # response to fc 15 / 16 does not contain data -> nothing to be done, parseObj will not be called
        
    } elsif ($fCode >= 128) {
        # error fCode                                       pdu: fCode, data
        return if ($dataLength) < 1;
        $response->{ERRCODE} = unpack ("H2", $data);
        $frame->{PDULEXP}    = 2;                           # 1 byte error fCode + 1 code   
    } else {
        # other function code
        Modbus_AddFrameError($frame, "Function code $fCode not implemented");
        $frame->{PDULEXP} = 2;
        # todo: now we don't know the length! maybe better drop everything we have ...
    }
    $response->{PDU} = pack ('C', $fCode) . substr($data, 0, $frame->{PDULEXP});
    return 1;       # go on with other checks / handling / dropping
}

#
# Daten aufbereiten:
# Modul ist Master, gelesene Daten von einem Gerät zu Readings expr, format, map, ...
#                   set von Fhem, Daten an Gerät senden, kein Format, aber setexpr
#
# Modul ist Slave, angefragte Daten an einen anderen Master liefern, setexpr, inverse map
#                   geschriebene Daten von einem anderen Master in Readings, map, expr, format, ...
#
#

#################################################
# Parse holding / input register / coil Data
# called from ParseResponse which is only called from HandleResponse
# or from HandleRequest (for write requests as slave)
# with logical device hash, data string
# and the object type/adr to start with
sub ModbusLD_ParseObj($$) {
    my ($logHash, $dataPtr) = @_;
    # $dataPtr can be response (mode master) or request (mode slave and write request)
    my $name      = $logHash->{NAME};
    my $type      = $dataPtr->{TYPE};
    my $startAdr  = $dataPtr->{ADR};
    my $valuesLen = $dataPtr->{LEN};
    my $op        = $dataPtr->{OPERATION};
    my $lastAdr   = ($valuesLen ? $startAdr + $valuesLen -1 : 0);
    my ($unpack, $format, $expr, $ignExpr, $map, $rest, $objLen, $encode, $decode);
    $op = "" if (!$op);
    Log3 $name, 5, "$name: ParseObj called with data " . unpack ("H*", $dataPtr->{VALUES}) . ", type $type, adr $startAdr" .  ($valuesLen ? ", valuesLen $valuesLen" : "") .  ($op ? ", op $op" : "");
    delete $logHash->{gotReadings};         # will be filled later and queried by caller. Used for logging and return value in get-command

    if ($type =~ "[cd]") {
        # valuesLen is only used for coils / discrete inputs
        $valuesLen = 1 if (!$valuesLen);
        $rest = unpack ("b$valuesLen", $dataPtr->{VALUES});   # convert binary data to bit string
        Log3 $name, 5, "$name: ParseObj shortened coil / input bit string: " . $rest . ", start adr $startAdr, valuesLen $valuesLen";
    } else {
        $rest = $dataPtr->{VALUES};
    }
    use bytes;
    readingsBeginUpdate($logHash);
    while (length($rest) > 0) {
        # einzelne Felder verarbeiten
        my $key     = $type . $startAdr;
        my $reading = Modbus_ObjInfo($logHash, $key, "reading");  # "" if nothing specified
        
        if ($op =~ /scanid([0-9]+)/) {      # scanning for Modbus ID
            $reading = "scanId-" . $1 . "-Response-$key";
            $logHash->{MODBUSID} = $1;
            Log3 $name, 3, "$name: ParseObj scanIds got response from Id $1 - set internal MODBUSID to $1";
        } elsif ($op eq 'scanobj') {        # scan Modbus objects
            Log3 $name, 5, "$name: ParseObj scanobj reading=$reading";
            if (!$reading) {
                my $fKey = $type . sprintf ("%05d", $startAdr);
                $reading   = "scan-$fKey";
                Log3 $name, 5, "$name: ParseObj scanobj sets reading=$reading";
                CommandAttr(undef, "$name obj-${fKey}-reading $reading");
            }
            if ($type =~ "[hi]") {
                my $l = length($rest) / 2;
                $l = 1 if ($l < 1);
                CommandAttr(undef, "$name dev-h-defLen $l")
                    if (AttrVal($name, "dev-h-defLen", "") ne "$l");
                CommandAttr(undef, "$name dev-h-defUnpack a" . $l*2) 
                    if (AttrVal($name, "dev-h-defUnpack", "") ne ('a'.$l*2));
                CommandAttr(undef, "$name dev-h-defExpr ModbusLD_ScanFormat(\$hash, \$val)")
                    if (AttrVal($name, "dev-h-defExpr", "") ne "ModbusLD_ScanFormat(\$hash, \$val)");
            }
        }
        #Log3 $name, 5, "$name: ParseObj reading is $reading";
        
        if ($reading) {
            if ($type =~ "[cd]") {      # coils or digital inputs
                $unpack    = "a";       # for coils just take the next 0/1 from the string
                $objLen    = 1;         # one byte contains one bit from the 01001100 string unpacked above
            } else {                    # holding / input register
                #Log3 $name, 5, "$name: ParseObj is getting infos for registers";
                $unpack     = Modbus_ObjInfo($logHash, $key, "unpack",    "defUnpack", "n"); 
                $objLen     = Modbus_ObjInfo($logHash, $key, "len",       "defLen", 1);     # default to 1 Reg / 2 Bytes
                $encode     = Modbus_ObjInfo($logHash, $key, "encode",    "defEncode");     # character encoding 
                $decode     = Modbus_ObjInfo($logHash, $key, "decode",    "defDecode");     # character decoding 
                my $revRegs = Modbus_ObjInfo($logHash, $key, "revRegs",   "defRevRegs");    # do not reverse register order by default
                my $swpRegs = Modbus_ObjInfo($logHash, $key, "bswapRegs", "defBswapRegs");  # dont reverse bytes in registers by default
                
                $rest = Modbus_RevRegs($logHash, $rest, $objLen) if ($revRegs && $objLen > 1);
                $rest = Modbus_SwpRegs($logHash, $rest, $objLen) if ($swpRegs);
            };
            $format  = Modbus_ObjInfo($logHash, $key, "format",     "defFormat");           # no format if nothing specified
            $expr    = Modbus_ObjInfo($logHash, $key, "expr",       "defExpr");
            $ignExpr = Modbus_ObjInfo($logHash, $key, "ignoreExpr", "defIgnoreExpr");
            $map     = Modbus_ObjInfo($logHash, $key, "map",        "defMap");              # no map if not specified
            Log3 $name, 5, "$name: ParseObj ObjInfo for $key: reading=$reading, unpack=$unpack, expr=$expr, format=$format, map=$map";
            
            #my $val = unpack ($unpack, $rest);      # verarbeite so viele register wie passend (ggf. über mehrere Register)
            my @val = unpack ($unpack, $rest);      # fill @val array in case $unpack contains codes for more fields, other elements can be used in expr later.
            
            if (!defined($val[0])) {
                my $logLvl = AttrVal($name, "timeoutLogLevel", 3);
                Log3 $name, $logLvl, "$name: ParseObj unpack of " . unpack ('H*', $rest) . " with $unpack for $reading resulted in undefined value";
            } else {
                # todo: log other array elements
                my $vString = "";
                foreach my $v (@val) {
                    $vString .= ($vString eq "" ? "" : ", ") . ($v =~ /[[:print:]]/ ? $v : "") . " hex " . unpack ('H*', $v);
                }
                Log3 $name, 5, "$name: ParseObj unpacked " . unpack ('H*', $rest) . " with $unpack to " . $vString;
      
                for (my $i =0; $i < @val; $i++) {
                    $val[$i] = decode($decode, $val[$i]) if ($decode);
                    $val[$i] = encode($encode, $val[$i]) if ($encode);
                }
                
                # Exp zur Ignorieren der Werte?
                my $ignore;
                $ignore = Modbus_CheckEval($logHash, @val, $ignExpr, "ignoreExpr for $reading") if ($ignExpr);

                # Exp zur Nachbearbeitung der Werte?
                my $val = $val[0];
                $val = Modbus_CheckEval($logHash, @val, $expr, "expr for $reading") if ($expr);

                # Map zur Nachbereitung der Werte?
                if ($map) {
                    my $nVal = Modbus_MapConvert ($logHash, $map, $val);
                    if (defined($nVal)) {
                        Log3 $name, 5, "$name: ParseObj for $reading maps value $val to $nVal with " . $map;
                        $val = $nVal 
                    } else {
                        Log3 $name, 5, "$name: ParseObj for $reading $val does not match map " . $map;
                    }
                }
                # Format angegeben?
                if ($format) {
                    Log3 $name, 5, "$name: ParseObj for $reading does sprintf with format " . $format .
                        ", value is $val";
                    $val = sprintf($format, $val);
                    Log3 $name, 5, "$name: ParseObj for $reading sprintf result is $val";
                }
                if ($ignore) {
                    Log3 $name, 4, "$name: ParseObj for $reading ignores $val because of ignoreExpr. Reading not updated";
                } else {                
                    if ($logHash->{MODE} eq 'slave') {
                        if (Modbus_ObjInfo($logHash, $key, "allowWrite", "defAllowWrite", 0)) { # write allowed. 
                            my $device = $name;                                 # default device is myself
                            my $rname  = $reading;                              # given name as reading name
                            my $dev    = $logHash;
                            if ($rname =~ /^([^\:]+):(.+)$/) {                  # can we split given name to device:reading?
                                $device = $1;
                                $rname  = $2;
                                $dev    = $defs{$device};
                            }
                            
                            my $outOfBounds;
                            my $setmin  = Modbus_ObjInfo($logHash, $key, "min", "", "");        # default to ""
                            my $setmax  = Modbus_ObjInfo($logHash, $key, "max", "", "");        # default to ""
                            if ($val =~ /^\s*-?\d+\.?\d*\s*$/) {             # a number (potentially with blanks)
                                if ($setmin ne "") {                            
                                    $val =~ s/\s+//g;
                                    Log3 $name, 5, "$name: parseObj is checking value $val against min $setmin";
                                    if ($val < $setmin) {
                                        $outOfBounds = 1;
                                    }
                                }
                                if ($setmax ne "") {
                                    $val =~ s/\s+//g;
                                    Log3 $name, 5, "$name: set is checking value $val against max $setmax";
                                    if ($val > $setmax) {
                                        $outOfBounds = 1;
                                    }
                                }
                            }                           
                            if (!$outOfBounds) {
                                if (!Modbus_TryCall($logHash, 'ModbusReadingsFn', $reading, $val)) {    
                                    Log3 $name, 4, "$name: ParseObj assigns value $val to reading $rname of device $device";
                                    if ($dev eq $logHash) {
                                        readingsBulkUpdate($dev, $rname, $val);         # assign value to one of this devices readings 
                                    } else {
                                        readingsSingleUpdate($dev, $rname, $val, 1);    # assign value to reading - another Fhem device
                                    }
                                }
                                $logHash->{gotReadings}{$reading} = $val;
                            } else {
                                Log3 $name, 4, "$name: ParseObj ignores value $val because it is out of bounds ($setmin / $setmax) for reading $rname of device $device";
                                my $code = Modbus_DevInfo($logHash, $type, "valueErrCode", 1);
                                $dataPtr->{ERRCODE} = $code if ($code);
                            }
                        } else {
                            Log3 $name, 4, "$name: ParseObj refuses to set reading $reading (allowWrite not set)";
                            my $code = Modbus_DevInfo($logHash, $type, "notAllowedErrCode", 1);
                            $dataPtr->{ERRCODE} = $code if ($code);
                        }
                    } else {
                        if (!Modbus_TryCall($logHash, 'ModbusReadingsFn', $reading, $val)) {    
                            Log3 $name, 4, "$name: ParseObj assigns value $val to $reading";
                            readingsBulkUpdate($logHash, $reading, $val);
                        }
                        $logHash->{gotReadings}{$reading} = $val;
                        $logHash->{lastRead}{$key}        = gettimeofday();     # used for pollDelay checking by getUpdate (mode master)
                    }
                }
            }
        } else {
            Log3 $name, 5, "$name: ParseObj has no information about parsing $key";
            $objLen = 1;
            if ($logHash->{MODE} eq 'slave') {
                my $code = Modbus_DevInfo($logHash, $type, "addressErrCode", 2);
                $dataPtr->{ERRCODE} = $code if ($code);
            }
        }
        
        # gehe zum nächsten Wert
        if ($type =~ "[cd]") {
            $startAdr++;
            if (length($rest) > 1) {
                $rest = substr($rest, 1);
            } else {
                $rest = "";
            }
            last if ($lastAdr && $startAdr > $lastAdr);     # only set for unpacked coil / input bit string
        } else {
            $startAdr += $objLen;            
            if (length($rest) > ($objLen*2)) {
                $rest = substr($rest, $objLen * 2);         # take rest of rest starting at len*2 until the end  
            } else {
                $rest = "";
            }
        }
        Log3 $name, 5, "$name: ParseObj moves to next object, skip $objLen to $type$startAdr" if ($rest);
    }
    readingsEndUpdate($logHash, 1);
    return;
}



###############################################
# call parse request, get logical device responsible
# write / read data as requested
# call send response
#
# when called we have $hash->{FRAME}{MODBUSID}, $hash->{FRAME}{FCODE}, $hash->{FRAME}{DATA}
# and for TCP also $hash->{FRAME}{PDULEXP} and $hash->{FRAME}{TID}
#
# return undef if read should continue reading 
# or 1 if we can react on data that was read

sub Modbus_HandleRequest($) 
{
    my ($hash) = @_;    
    my $name  = $hash->{NAME};                      # name of physical device   
    my $frame = $hash->{FRAME};
    my $id    = $frame->{MODBUSID};
    my $fCode = $frame->{FCODE};
    my $logHash;
    
    Log3 $name, 5, "$name: HandleRequest called from " . Modbus_Caller();
    
    my %requestData;                                # create new request structure
    my $request = \%requestData;
    
    if (!Modbus_ParseRequest($hash, $request)) {
        Log3 $name, 5, "$name: HandleRequest could not parse request frame yet, wait for more data";
        return;
    }
    # for unknown fCode $request->{ERRCODE} as well as {ERROR} are set by ParseRequest, later CreateResponse copies ERRCODE from Request into Response
    
    $hash->{REQUEST} = $request;
    my $frameLen = $frame->{PDULEXP} + $Modbus_PDUOverhead{$hash->{PROTOCOL}};
    my $readLen  = length($hash->{READ}{BUFFER});
    
    #Log3 $name, 5, "$name: HandleRequest is now calling CheckChecksum";
    Modbus_CheckChecksum($hash);                    # get $hash->{FRAME}{CHECKSUMCALC}, $hash->{FRAME}{CHECKSUMSENT} and $hash->{FRAME}{CHECKSUMERROR}  
    
    if ($frame->{CHECKSUMERROR}) {                  # ignore frame->{ERROR} here since the ony other possible error is unsupported fCode which should create a response
        if ($readLen < $frameLen ) {
            Log3 $name, 5, "$name: HandleRequest did not get a valid frame yet, wait for more data";
            return;                                 # frame not complete and error - continue reading
        } else {
            Modbus_RequestDone($hash, 4);           # log, profiler, drop data
            return 1;                               # error or not, parsing is done.
        }
    } else {
        if ($readLen < $frameLen ) {
            Log3 $name, 5, "$name: HandleRequest got valid checksum but short frame.";
            return;
        }
        # got a valid frame - maybe we can't handle it (unsupported fCode -> ERRCODE)
        Modbus_Profiler($hash, "Fhem");   
        Modbus_LogFrame($hash, "HandleRequest", 4);
        
        # look for Modbus logical device with the right ID. (slave or relay)
        $logHash = Modbus_GetLogHash($hash, $id);
        
        if ($logHash) {                             # our id, we are responsible
            $request->{DEVHASH} = $logHash;
            if ($hash->{MODE} eq 'slave') {
                if (!$request->{ERRCODE} && $writeCode{$fCode}) {   # supported write fCode request contains data to be parsed and stored
                    # parse the request value, set reading with formatting etc. like for replies
                    Log3 $name, 5, "$name: passing value string of write request to ParseObj to set readings";                  
                    # we don't pass length here but check definitions and allowance for each register / len defined by attributes starting at adr
                    
                    my $parseLogHash1 = ($logHash->{CHILDOF} ? $logHash->{CHILDOF} : $logHash);
                    my $pName = $parseLogHash1->{NAME}; 
                    ModbusLD_ParseObj($parseLogHash1, $request);
                    # parseObj can also set ERRCODE (illegal address, value out of bounds) 
                    # so CreateResponse/PackResponse will create an error message back to master
                    Log3 $pName, 5, "$pName: HandleRequest got " . scalar keys (%{$parseLogHash1->{gotReadings}}) . " readings from ParseObj";
                }
            }
        } else {
            Log3 $name, 4, "$name: $id is not one of our Modbus Ids";
        }
    }
    if ($logHash) {
        if ($hash->{MODE} eq 'slave') {
            Modbus_CreateResponse($hash);           # data or unsupported fCode error if request->{ERRCODE} and {ERROR} were set during parse
        } elsif ($hash->{MODE} eq 'relay') {                    
            Modbus_RelayRequest($hash, $frame);     # even if unspoorted fCode ...
        }
    }
    Modbus_RequestDone($hash, 4);                   # log, profiler, drop data
    return 1;                                       # error or not, parsing is done.
}



    
# handle Passive
#
# Zustands var lesen Request oder Response
# lese request wie bei slave,
# lese response wie bei Master, bei Timeout wieder auf Request warten
#
# problem: was kommt gerade?
#
#



# Mode master:
# create request structure -> queue -> send
# read response, parse to frame, response structure, parse data -> readings
#
# Mode slave:
# read request, parse request structure -> set readings for write requests, get values for read requests as data string
# create response pdu, pack frame and send
#
# Mode passive:
# read request, parse request structure, 
# read response, parse to frame, response structure, parse data -> readings
#
# Mode relay (if mode at all) needs two active connections!
# read request, parse request structure 
#   pass to Master device -> queue -> send
#   read response, parse to frame, pdu (response structure not needed here)
# take response pdu, pack frame and send
# 

 
#
# Parse Request, called from handleRequest
#
# require $physHash->{FRAME} to be filled before by HandleFrameStart
#
#######################################################################
sub Modbus_ParseRequest($$)
{
    my ($hash, $request) = @_;
    my $name  = $hash->{NAME};
    my $frame = $hash->{FRAME};
    return if (!$frame->{FCODE});
    my $fCode = $frame->{FCODE};                        # filled in handleFrameStart
    my $data  = $frame->{DATA};
    
    Log3 $name, 5, "$name: ParseRequest called from " . Modbus_Caller();
    
    use bytes;
    my $dataLength = length($data);
    $request->{FCODE}    = $frame->{FCODE};             
    $request->{MODBUSID} = $frame->{MODBUSID};
    $request->{TID}      = $frame->{TID} if ($frame->{TID});

    if ($fCode == 1 || $fCode == 2) {
        # read coils / discrete inputs,                 pdu: fCode, StartAdr, Len (=number of coils)
        return if ($dataLength) < 4;
        my ($adr, $len) = unpack ('nn', $data);
        $request->{TYPE}  = ($fCode == 1 ? 'c' : 'd');  # coils or discrete inputs
        $request->{ADR}   = $adr;                       # 16 Bit Coil / Input adr
        $request->{LEN}   = $len;                       # 16 Bit number of Coils / Inputs
        $frame->{PDULEXP} = 5;                          # fCode + 2x16Bit  
        
    } elsif ($fCode == 3 || $fCode == 4) {      
        # read holding/input registers,                 pdu: fCode, StartAdr, Len (=number of regs)
        return if ($dataLength) < 4;
        my ($adr, $len) = unpack ('nn', $data);
        $request->{TYPE}  = ($fCode == 3 ? 'h' : 'i');  # holding registers / input registers
        $request->{ADR}   = $adr;                       # 16 Bit Coil / Input adr
        $request->{LEN}   = $len;                       # 16 Bit number of Coils / Inputs
        $frame->{PDULEXP} = 5;                          # fCode + 2x16Bit  
        
    } elsif ($fCode == 5) {                     
        # write single coil,                            pdu: fCode, StartAdr, Value (1-bit as FF00)
        return if ($dataLength) < 4;
        my ($adr, $value) = unpack ('na*', $data);
        $request->{TYPE}   = 'c';                       # coil
        $request->{ADR}    = $adr;                      # 16 Bit Coil adr
        $request->{LEN}    = 1;
        $request->{VALUES} = $value;
        $frame->{PDULEXP} = 5;                          # fCode + 2 16Bit Values  
        
    } elsif ($fCode == 6) {                     
        # write single holding register,                pdu: fCode, StartAdr, Value
        return if ($dataLength) < 4;
        my ($adr, $value) = unpack ('na*', $data);
        $request->{TYPE}  = 'h';                        # holding register
        $request->{ADR}   = $adr;                       # 16 Bit holding register adr
        $request->{LEN}   = 1;
        $request->{VALUES} = $value;
        $frame->{PDULEXP} = 5;                          # fCode + 2x16Bit 

    } elsif ($fCode == 15) {                    
        # write multiple coils,                         pdu: fCode, StartAdr, NumOfCoils, ByteCount, Values as bits
        return if ($dataLength) < 6;
        my ($adr, $len, $bytes, $values) = unpack ('nnCa*', $data);
        $request->{TYPE}  = 'c';                        # coils
        $request->{ADR}   = $adr;                       # 16 Bit Coil adr
        $request->{LEN}   = $len;
        $request->{VALUES} = $values;
        $frame->{PDULEXP} = 6 + $bytes;                 # fCode + 2x16Bit + bytecount + values

    } elsif ($fCode == 16) {                    
        # write multiple regs,                          pdu: fCode, StartAdr, NumOfRegs, ByteCount, Values
        my ($adr, $len, $bytes, $values) = unpack ('nnCa*', $data);
        return if ($dataLength) < 6;
        $request->{TYPE}  = 'h';                        # coils
        $request->{ADR}   = $adr;                       # 16 Bit Coil adr
        $request->{LEN}   = $len;
        $request->{VALUES} = $values;
        $frame->{PDULEXP} = 6 + $bytes;                 # fCode + 2x16Bit + bytecount + values

    } else {                                            # function code not implemented yet
        $request->{ERRCODE} = 1;                        # error code 1 in Modbus response = illegal function
        Modbus_AddFrameError($frame, "Function code $fCode not implemented");
        $frame->{PDULEXP} = 2;
    }
    $request->{PDU} = pack ('C', $fCode) . substr($data, 0, $frame->{PDULEXP});
    return 1;   # continue handling / dropping this frame
}



#######################################################
# get the valid io device for the relay forward device
# called with the logical device hash of a relay 
# this relay device hash has hash->{RELAY} set to the name of the forward device
# also sets $hash->{RELID} (in the logical relay device) 
# to the Modbus id of the relay forward device 
sub Modbus_GetRelayIO($) 
{
    my ($hash) = @_;    
    my $name   = $hash->{NAME};
    my $reName;
    my $reHash;
    my $reIOHash;
    my $msg;
    
    if (!$hash->{RELAY}) {
        $msg = "GetRelay doesn't have a relay forward device";
    } else {
        $reName = $hash->{RELAY};                           # name of the relay forward device as defined
        $reHash = $defs{$reName};
        #Log3 $name, 5, "$name: GetRelayIO for relay forward device $reHash->{NAME}";
        if (!$reHash || !$reHash->{MODULEVERSION} || 
                $reHash->{MODULEVERSION} !~ /^Modbus / || $reHash->{MODE} ne 'master'
                || $reHash->{TYPE} eq 'Modbus') {
            $msg = "relay forward device $reName is not a modbus master";
        } else {
            # now we have a $reHash for the logical relay device at least
            $reIOHash = ModbusLD_GetIOHash($reHash);        # get io device hash of the relay forward device
            my $slIOHash = ModbusLD_GetIOHash($hash);       # get io device hash of the relay slave part. Check later if available
            if (!$reIOHash) {
                $msg = "no relay forward io device";
            } elsif ($reIOHash eq $slIOHash) {
                $msg = "relay forward io device must not must not be same as receiving device";
            } else {
                # now check for disabled devices
                $msg = ModbusLD_CheckDisable($reHash);      # is relay forward device or its io device disabled?
            }
        }
    }
    # don't check if relay io device is actually opened. This will be done when the queue is processed 
    if ($msg) {
        Log3 $name, 3, "$name: GetRelayIO: $msg";
        delete $hash->{RELID};
        return;
    }
    $hash->{RELID} = $reHash->{MODBUSID};
    Log3 $name, 5, "$name: GetRelayIO found $reIOHash->{NAME} as Modbus relay forward io device";
    return $reIOHash;
}


#############################################
# relay request to the specified relay device 
sub Modbus_RelayRequest($$) 
{
    my ($hash, $frame) = @_;    
    my $name    = $hash->{NAME};                        # the io device of the device defined with MODE relay (received the request)
    my $request = $hash->{REQUEST};
    my $slHash  = $request->{DEVHASH};                  # the logical device with MODE relay (that handled the incoming request)

    Log3 $name, 5, "$name: RelayRequest called from " . Modbus_Caller();
    
    my $reIOHash = Modbus_GetRelayIO($slHash);          # the io device of the relay forward device (relay to)
    
    if (!$reIOHash) {
        Modbus_AddFrameError($frame, "relay device unavailable");
        $request->{ERRCODE} = 10;                       # gw path unavail; 11=gw target fail to resp.
        Modbus_CreateResponse($hash);                   # error response with request data and errcode 
    } else {
        my $id = $slHash->{RELID};
        my %fRequest = %{$request};                     # create a copy to modify and forward
                                                        # (DEVHASH stays the logical device that received the incoming request)
        Modbus_LogFrame($hash, "RelayRequest via $reIOHash->{NAME}, Proto $reIOHash->{PROTOCOL} with id $id", 4);
        if ($reIOHash->{PROTOCOL} eq 'TCP') {           # forward as Modbus TCP?
            my $tid = int(rand(255));
            $fRequest{TID} = $tid;                      # new transaction id for Modbus TCP forwarding
        }
        $fRequest{MODBUSID} = $id;                      # Modified target ID for the request to forward
        $fRequest{DBGINFO}  = "relayed";
        Modbus_QueueRequest($reIOHash, \%fRequest, 0);  # dont't force, just queue
        $hash->{EXPECT} = "waitrelay"                   # wait for relay response to then send our response         
    }
}



##########################################
# relay response back to the device that 
# sent the original request. We are master
sub Modbus_RelayResponse($) 
{
    my ($hash) = @_;    
    my $name     = $hash->{NAME};                       # physical device that received response 
    my $response = $hash->{RESPONSE};                   # response for the request we did pass on
        
    my $slHash   = $response->{DEVHASH};                # hash of logical relay device that got the first request
    my $ioHash   = ModbusLD_GetIOHash($slHash);         # the ioHash that received the original request
    if (!$ioHash) {
        Log3 $name, 4, "$name: relaying response back failed because slave side io device disappeared";
        return;
    }
    my $request  = $ioHash->{REQUEST};                  # original request to relay
    
    # adjust Modbus ID for back communication
    $response->{MODBUSID} = $request->{MODBUSID} if ($request->{MODBUSID});
    $response->{TID} = $request->{TID} if ($request->{TID});
    Modbus_LogFrame($slHash, "RelayResponse via $slHash->{NAME}, ioDev $slHash->{IODev}{NAME}", 4, $request, $response);
    
    my $responseFrame = Modbus_PackFrame($ioHash, $request->{MODBUSID}, $response->{PDU}, $request->{TID}); 
    Modbus_Send($ioHash, $request->{MODBUSID}, $responseFrame, $slHash);
    Modbus_Profiler($hash, "Wait");   
    return;
}


#########################################
# called from HandleRequest, RelayRequest
# and responseTimeout (when a relay wants to 
# inform its master about the downstream timeout)
#
# the start adr and length of the request is
# taken to assemble a response frame out of
# one or several objects
#

sub Modbus_CreateResponse($)
{
    my ($hash) = @_;
    my $request = $hash->{REQUEST};
    my $logHash = $request->{DEVHASH};
    
    $logHash = $logHash->{CHILDOF} if ($logHash->{CHILDOF});
    my $name = $logHash->{NAME};                 # name of logical device    
    
    Log3 $name, 5, "$name: CreateResponse called from " . Modbus_Caller();
    
    my %responseData;
    my $response = \%responseData;
    $hash->{RESPONSE} = $response;
    
    # get values for response
    $response->{ADR}      = $request->{ADR};
    $response->{LEN}      = $request->{LEN};
    $response->{TYPE}     = $request->{TYPE};
    $response->{MODBUSID} = $request->{MODBUSID};
    $response->{FCODE}    = $request->{FCODE};
    $response->{TID}      = $request->{TID} if ($request->{TID});
    $response->{ERRCODE}  = $request->{ERRCODE};
    
    # pack one or more values into a vales string
    $response->{VALUES}   = ModbusLD_PackObj($logHash, $response) if (!$response->{ERRCODE});
        
    Log3 $name, 5, "$name: prepare response pdu";
    my $responsePDU = Modbus_PackResponse($hash, $response);     # creates response or error PDU Data if {ERRCODE} is set

    # pack and send
    my $responseFrame = Modbus_PackFrame($hash, $response->{MODBUSID}, $responsePDU, $response->{TID});
        
    Log3 $name, 4, "$name: CreateResponse sends " .
                    ($response->{ERRCODE} ? 
                        "fc " . ($response->{FCODE} + 128) . " error code $response->{ERRCODE}" :
                        "fc $response->{FCODE}") .
                    " to id $response->{MODBUSID}, " .
                    ($response->{TID} ? "tid $response->{TID} " : "") .
                    "for $response->{TYPE} $response->{ADR}, len $response->{LEN}" .
                   ", device $name ($hash->{PROTOCOL}), pdu " . 
                    unpack ('H*', $responsePDU) . ", V $Modbus_Version";
    
    # todo: logHash passed to send is used to set lsend. For TCP connected master devices this is irrelevant
    # only for connected slaves this should be checked / set
    
    Modbus_Send($hash, $response->{MODBUSID}, $responseFrame, $logHash);
    Modbus_Profiler($hash, "Idle");   
}
        


##############################################################
# called from logical device functions 
# get, set, scan etc. with log dev hash, create request 
# and call QueueRequest
sub ModbusLD_DoRequest($$$;$$$$){
    my ($hash, $objCombi, $op, $v1, $force, $reqLen, $dbgInfo) = @_;
    # $hash     : the logical device hash
    # $objCombi : type+adr 
    # $op       : read, write or scanids/scanobj
    # $v1       : value for writing (already packed, also for coil ff00 or 0000)
    # $force    : put in front of queue and don't reschedule but wait if necessary
    
    my $name    = $hash->{NAME};                # name of logical device
    my $devId   = ($op =~ /^scanid([0-9]+)/ ? $1 : $hash->{MODBUSID});
    my $proto   = $hash->{PROTOCOL};
    my $type    = substr($objCombi, 0, 1);
    my $adr     = substr($objCombi, 1);
    my $reading = Modbus_ObjInfo($hash, $objCombi, "reading");
    my $objLen  = Modbus_ObjInfo($hash, $objCombi, "len", "defLen", 1);
    my $fcKey   = $op;
    if ($op =~ /^scan/) {
        $objLen = ($reqLen ? $reqLen : 0);      # for scan there is no objLen but reqLen is given - avoid confusing log and set objLen ...
        $fcKey  = 'read';
    }
    
    #Log3 $name, 5, "$name: DoRequest called from " . Modbus_Caller();
    my $ioHash = ModbusLD_GetIOHash($hash);     # send queue is at physical hash
    my $qlen   = ($ioHash->{QUEUE} ? scalar(@{$ioHash->{QUEUE}}) : 0);
    
    #Log3 $name, 4, "$name: DoRequest called from " . Modbus_Caller() . " with $type$adr, objLen $objLen / reqLen " .
    #    ($reqLen ? $reqLen : "-") . " to id $devId, op $op, qlen $qlen" .
    #    ((defined($v1) && $op eq 'write') ? ", value hex " . unpack ('H*', $v1) : "");
    
    $reqLen = $objLen if (!$reqLen);            # combined reqLen from GetUpdate or scans

    return if (ModbusLD_CheckDisable($hash));   # returns if there is no io device

    # check if defined unpack code matches a corresponding len and log warning if appropriate
    my $unpack = Modbus_ObjInfo($hash, $objCombi, "unpack", "defUnpack", "n"); 
    if ($objLen < 2 && $unpack =~ /lLIqQfFNVD/) {
        Log3 $name, 3, "$name: DoRequest with unpack $unpack but len seems too small - please set obj-${objCombi}-Len!";
    }       
    
    my $defFC = $Modbus_defaultFCode{$type}{$fcKey};
    $defFC = 16 if ($defFC == 6 && $reqLen > 1);
    my $fCode = Modbus_DevInfo($hash, $type, $fcKey, $defFC); 
    if (!$fCode) {
        Log3 $name, 3, "$name: DoRequest did not find fCode for $fcKey type $type";
        return;
    } elsif ($fCode == 6 && $reqLen > 1) {
        Log3 $name, 3, "$name: DoRequest tries to use function code 6 to write more than one register. This will not work"
    }
    my %request;
    $request{FCODE}     = $fCode;   # function code
    $request{DEVHASH}   = $hash;    # logical device in charge
    $request{TYPE}      = $type;    # type of object (cdih)
    $request{ADR}       = $adr;     # address of object
    $request{LEN}       = $reqLen;  # number of registers / length of object
    $request{READING}   = $reading; # reading name of the object
    $request{MODBUSID}  = $devId;   # ModbusId of the addressed device - coming from logical device hash
    $request{VALUES}    = $v1;      # Value to be written (from set, already packed, even for coil a packed 0/1)
    $request{OPERATION} = $op;      # read / write / scan
    $request{DBGINFO}   = $dbgInfo if ($dbgInfo);   # additional debug info
    
    if ($proto eq "TCP") {
        my $tid = int(rand(255));
        $request{TID} = $tid;       # transaction id for Modbus TCP
    }
    delete $ioHash->{RETRY};
    
    #$ioHash->{REQUEST} = \%request;    # It might overwrite the one sent -> dont link here
    Modbus_LogFrame($hash, "DoRequest called from " . Modbus_Caller() . " created", 4, \%request);
    Modbus_QueueRequest($ioHash, \%request, $force);    
}   



#####################################
# called from CreateRequest
# with physical device hash
sub Modbus_QueueRequest($$$){
    my ($hash, $request, $force) = @_;
    # $hash     : the physical device hash
    # $force    : put in front of queue and don't reschedule but sleep if necessary
    
    my $name  = $hash->{NAME};                # name of physical device with the queue
    my $qlen  = ($hash->{QUEUE} ? scalar(@{$hash->{QUEUE}}) : 0);
    my $lName = ($request->{DEVHASH} ? $request->{DEVHASH}{NAME} : "unknown");
    my $lqMax = AttrVal($lName, "queueMax", 100);
    my $qMax  = AttrVal($name, "queueMax", $lqMax);
    
    Log3 $name, 5, "$name: QueueRequest called from " . Modbus_Caller() . 
        " ($lName) with $request->{TYPE}$request->{ADR}, qlen $qlen";
    
    return if (ModbusLD_CheckDisable($hash));       # also returns if there is no io device

    # check for queue doubles if not forcing
    if ($qlen && AttrVal($name, "dropQueueDoubles", 0) && !$force) {
        Log3 $name, 5, "$name: QueueRequest is checking if request for $request->{TYPE}$request->{ADR} is already in queue (len $qlen)";
        foreach my $elem (@{$hash->{QUEUE}}) {
            #Log3 $name, 5, "$name: QueueRequest checks $elem->{TYPE}$elem->{ADR} reqLen $elem->{LEN} to id $elem->{MODBUSID}?";
            if($elem->{ADR} == $request->{ADR} && $elem->{TYPE} eq $request->{TYPE} 
                && $elem->{LEN} == $request->{LEN} && $elem->{MODBUSID} eq $request->{MODBUSID}) {
                Log3 $name, 4, "$name: QueueRequest found request already in queue - dropping";
                return;
            }
        }
    }
    my $now  = gettimeofday();
    $request->{TIMESTAMP} = $now;
    if(!$qlen) {
        #Log3 $name, 5, "$name: QueueRequest is creating new queue";
        $hash->{QUEUE} = [ $request ];
    } else {
        #Log3 $name, 5, "$name: QueueRequest initial queue length is $qlen";
        if ($qlen > $qMax) {
            Log3 $name, 3, "$name: QueueRequest queue too long ($qlen), dropping new request";
        } else {
            if ($force) {
                unshift (@{$hash->{QUEUE}}, $request);          # prepend at beginning
            } else {
                push(@{$hash->{QUEUE}}, $request);              # add to end of queue
            }
        }
    }   
    if ($hash->{EXPECT} ne 'response' || $force) {              # even process queue diretly if force or not busy
        Modbus_ProcessRequestQueue("direct:".$name, $force);    # call directly - even wait if force is set
    } else {
        readingsSingleUpdate($hash, "QueueLength", ($hash->{QUEUE} ? scalar(@{$hash->{QUEUE}}) : 0), 1) if (AttrVal($name, "enableQueueLengthReading", 0));
        Modbus_StartQueueTimer($hash);                          # make sure timer is set
    }
    return;
}   



#######################################
# prüfe delays vor dem Senden
sub Modbus_CheckDelay($$$$$$)
{
    my ($ioHash, $devName, $force, $title, $delay, $last) = @_;
    return if (!$delay);
    my $now  = gettimeofday();
    my $name = $ioHash->{NAME};
    my $t2   = $last + $delay;
    my $rest = $t2 - $now;

    my $logMsg = "$name: CheckDelay called from " . Modbus_Caller() . 
                " $title (${delay}s since " . Modbus_FmtTime($last) . ")" .
                #" for $devName, now is " . Modbus_FmtTime($now) . 
                " for $devName" . 
                ($rest >=0 ? ", rest " . sprintf ("%.3f", $rest) : ", delay " . sprintf ("%.3f", $rest * -1) . "secs over");
    
    if ($rest > 0) {
        Modbus_Profiler($ioHash, "Delay");  
        if ($force) {
            Log3 $name, 4, $logMsg . ", sleep forced";
            sleep $rest if ($rest > 0 && $rest < $delay);
            return 0;
        } else {
            Log3 $name, 4, $logMsg . ", set timer to try again later";
            Modbus_StartQueueTimer($ioHash, $rest);     # call processRequestQueue when remeining delay is over
            return 1;
        }
    } else {
        Log3 $name, 5, $logMsg;
    }
    return 0;
}



# stopQueueTimer is called:
# - at the end of open and close (initialized state, queue should be empty)
# - when queue becomes empty while processing the queue
# when processRequestQueue gets called from fhem.pl via internal timer, this timer is removed internally -> nextQueueRun deleted

# startQueueTimer is called 
# - in queueRequest when something got added to the queue
# - end of get to set it to immediate processing
# - end of set to set it to immediate processing
# - in read after HandleResponse has done something to start immediate processing
# - in processRequestQueue to set a new delay
# - in checkDelay called from processRequestQueue 
#       before it returns 1 (to ask the caller to return because delay is not over yet)

# but startQueueTimer does only set the timer if the queue contains something

# processRequestQueue or startQueueTimer is not called in ResponseDone because 
# when ResponseDone is called from read, startQueueTimer is called in read after HandleResponse
# when ResponseDone is called from readAnswer, readAnswer returns to get/set who call stertQueueTimer at the end



######################################################
# set internal timer for next queue processing
# to now + passed delay (if delay is passed)
# if no delay is passed, use attribute queueDelay if no shorter timer is already set
sub Modbus_StartQueueTimer($;$)
{
    my ($ioHash, $pDelay) = @_;
    my $name = $ioHash->{NAME};
    my $qlen = ($ioHash->{QUEUE} ? scalar(@{$ioHash->{QUEUE}}) : 0);
    if ($ioHash->{MODE} && $ioHash->{MODE} eq 'master' && $qlen) {        
        my $now = gettimeofday();
        my $delay = (defined($pDelay) ? $pDelay : AttrVal($name, "queueDelay", 1));
        if ($ioHash->{nextQueueRun} && $ioHash->{nextQueueRun} < $now+$delay && !defined($pDelay)) {
            my $remain = $ioHash->{nextQueueRun} - $now;
            $remain = 0 if ($remain < 0);
            #Log3 $name, 5, "$name: StartQueueTimer called form " . Modbus_Caller() . 
            #    " has already set internal timer to call Modbus_ProcessRequestQueue in " . 
            #    sprintf ("%.3f", $remain) . " seconds";
            return;
        }
        RemoveInternalTimer ("queue:$name");  
        InternalTimer($now+$delay, "Modbus_ProcessRequestQueue", "queue:$name", 0);
        $ioHash->{nextQueueRun} = $now+$delay;
        Log3 $name, 5, "$name: StartQueueTimer called form " . Modbus_Caller() . 
            " sets internal timer to call Modbus_ProcessRequestQueue in " . 
            sprintf ("%.3f", $delay) . " seconds";
    } else {
        RemoveInternalTimer ("queue:$name");  
        delete $ioHash->{nextQueueRun};
        Log3 $name, 5, "$name: StartQueueTimer called from " . Modbus_Caller() . 
            " removes internal timer because it is not needed now";
    }
}


######################################################
# remove internal timer for next queue processing
sub Modbus_StopQueueTimer($)
{
    my ($ioHash) = @_;
    my $name = $ioHash->{NAME};
    if ($ioHash->{MODE} && $ioHash->{MODE} eq 'master' && $ioHash->{nextQueueRun}) {        
        RemoveInternalTimer ("queue:$name");  
        delete $ioHash->{nextQueueRun};
        Log3 $name, 5, "$name: StopQueueTimer called from " . Modbus_Caller() . 
            " removes internal timer to call Modbus_ProcessRequestQueue";
    }
}


#######################################
# Aufruf aus InternalTimer mit "queue:$name" 
# oder direkt mit "direkt:$name
# wobei name das physical device ist
# greift über den Request der Queue auf das logische Device zu
# um Timings und Zeitstempel zu verarbeiten
# setzt selbst wieder einen Timer nach qDelay (default 1 Sek)
# nach erfolgreichem Lesen einer response als Master wird HandleResponseQueue direkt aufgerufen
# nach einem Timeout wird ebenso direkt aufgerufen. 

# to be able to open tcp connections on demand and close them after communication
# ProcessRequestQueue should call open if necessary and then return / set timer with queueDelay
# to try again in x seconds.
# then the queue entries should have their own timeout so they can get removed e.g. after 10 seconds
# otherwise the queue will overflow sometimes.
# the age of entries is checked here and the entry removed if it is too old.
sub Modbus_ProcessRequestQueue($;$)
{
    my ($ckey,$name) = split(':', shift);
    my $force  = shift;                         # sleep if necessary, force sending now!
    my $ioHash = $defs{$name};
    my $queue  = $ioHash->{QUEUE};
    my $now    = gettimeofday();
    my $qDelay = AttrVal($name, "queueDelay", 1);  
    my $qTo    = AttrVal($name, "queueTimeout", 20);  
    my $request;
    
    #Log3 $name, 5, "$name: ProcessRequestQueue called from " . Modbus_Caller() . " as $ckey:$name" . ($force ? ", force" : "");
    delete $ioHash->{nextQueueRun};             # internal timer has fired / called us -> clean up
    
    for(;;) {                                   # get first usable entry
        if(!$queue || !scalar(@{$queue})) {     # nothing in queue -> return
            Log3 $name, 5, "$name: ProcessRequestQueue called from " . Modbus_Caller() . " as $ckey:$name" . ($force ? ", force" : "") . " has nothing in queue";
            readingsSingleUpdate($ioHash, "QueueLength", 0, 1) if (AttrVal($name, "enableQueueLengthReading", 0));
            return;
        }
        $request = $queue->[0];                                         # get top element from Queue
        if ($request && $request->{FCODE}) {                            # valid entry?
            $request->{TIMESTAMP} = $now if (!$request->{TIMESTAMP});   # should never happen
            last if ($now - $request->{TIMESTAMP} <= $qTo);             # element is not outdated -> exit loop
        }
        shift(@{$queue});                                               # remove invalid first element from queue and iterate
    }
    # now a valid element is at the top of the queue
    
    my $qlen    = ($queue ? scalar(@{$queue}) : 0);                     # can not be 0 now, otherwise would have returned above
    my $logHash = $request->{DEVHASH};
    my $msg = ModbusLD_CheckDisable($logHash);
    if ($msg) {                                 # logical or physical device is disabled, already logged by CheckDisable
        $msg = "dropping queue because logical or io device is disabled";
        delete $ioHash->{QUEUE};                # drop whole queue
    } elsif (!DevIo_IsOpen($ioHash)) {
        $msg = "device is disconnected";
        Modbus_Open($ioHash);                   # try to open asynchronously so we can proceed after qDelay
        # todo: this calls close and with that stops the update timer! -> set it again when reconnected.
        
    } elsif (!$init_done) {                     # fhem not initialized, wait with IO
        $msg = "device is not available yet (init not done)";
    } elsif ($ioHash->{MODE} && $ioHash->{MODE} ne 'master') {
        $msg = "dropping queue because device is not in mode master";
        delete $ioHash->{QUEUE};                # drop whole queue
    } elsif ($ioHash->{EXPECT} eq 'response') { # still busy waiting for response to last request
        $msg = "Fhem is still waiting for response, " . Modbus_FrameText($ioHash);
    }
    readingsSingleUpdate($ioHash, "QueueLength", ($queue ? scalar(@{$queue}) : 0), 1) if (AttrVal($name, "enableQueueLengthReading", 0));
    if ($msg) {
        Modbus_Profiler($ioHash, "Idle") if ($ioHash->{EXPECT} ne 'response');
        Log3 $name, 5, "$name: ProcessRequestQueue called from " . Modbus_Caller() . " returns, $msg, " .
                "qlen $qlen, try again in $qDelay seconds";
        Modbus_StartQueueTimer($ioHash);        # try again after qDelay, no shorter waiting time obvious
        return;
    }
    
    # check defined delays
    my $lBRead  = 999; 
    my $lBRText = "never";
    my $lRead   = 999;
    my $lRText  = "never";
    my $lSend   = 999;
    my $lSText  = "never";
    my $lIText  = "";
    if ($ioHash->{REMEMBER}{lrecv}) {
        $lBRead  = $now - $ioHash->{REMEMBER}{lrecv};
        $lBRText = sprintf("%.3f", $lBRead) . " secs ago";
    }
    if ($logHash->{REMEMBER}{lrecv}) {
        $lRead  = $now - $logHash->{REMEMBER}{lrecv};
        $lRText = sprintf("%.3f", $lRead) . " secs ago";
    }
    if ($logHash->{REMEMBER}{lsend}) {
        $lSend  = sprintf("%.3f", $now - $logHash->{REMEMBER}{lsend});
        $lSText = sprintf("%.3f", $lSend) . " secs ago";
    }
    if ($ioHash->{REMEMBER}{lid} && $ioHash->{REMEMBER}{lname}) {
        $lIText = "from id $ioHash->{REMEMBER}{lid} ($ioHash->{REMEMBER}{lname})";
    }
    Log3 $name, 4, "$name: ProcessRequestQueue called from " . Modbus_Caller() . ($force ? ", force" : "") . ", qlen $qlen, " .
                    "next entry to id $request->{DEVHASH}{MODBUSID} ($request->{DEVHASH}{NAME}), " .
                    "last send to this device was $lSText, last read $lRText, last read on bus $lBRText $lIText";

    # todo: use new vars from above and remove CheckDelay function
    my $reqId = $request->{MODBUSID};
    if ($ioHash->{REMEMBER}{lrecv}) {
        #Log3 $name, 5, "$name: ProcessRequestQueue check busDelay ...";
        return if (Modbus_CheckDelay($ioHash, $name, $force, 
                "busDelay", AttrVal($name, "busDelay", 0),
                $ioHash->{REMEMBER}{lrecv}));       # Profiler set to Delay, queue timer is set accordingly
                
        #Log3 $name, 5, "$name: ProcessRequestQueue check clientSwitchDelay ...";       
        my $clSwDelay = AttrVal($name, "clientSwitchDelay", 0);
        if ($clSwDelay && $ioHash->{REMEMBER}{lid}
            && $reqId != $ioHash->{REMEMBER}{lid}) {
            return if (Modbus_CheckDelay($ioHash, $name, $force, 
                    "clientSwitchDelay", $clSwDelay, 
                    $ioHash->{REMEMBER}{lrecv}));   # Profiler set to Delay, queue timer is set accordingly
        }
    }
    if ($logHash->{REMEMBER}{lrecv}) {
        return if (Modbus_CheckDelay($ioHash, $logHash->{NAME}, $force, 
                "commDelay", Modbus_DevInfo($logHash, "timing", "commDelay", 0.1),
                $logHash->{REMEMBER}{lrecv}));      # Profiler set to Delay, queue timer is set accordingly
    }
    if ($logHash->{REMEMBER}{lsend}) {
        return if (Modbus_CheckDelay($ioHash, $logHash->{NAME}, $force, 
                "sendDelay", Modbus_DevInfo($logHash, "timing", "sendDelay", 0.1),
                $logHash->{REMEMBER}{lsend}));      # Profiler set to Delay, queue timer is set accordingly
    }

    my $pdu   = Modbus_PackRequest($ioHash, $request);
    #Log3 $name, 4, "$name: ProcessRequestQueue got pdu from PackRequest: " . unpack 'H*', $pdu;
    
    my $frame = Modbus_PackFrame($ioHash, $reqId, $pdu, $request->{TID});
    
    Modbus_LogFrame ($ioHash, "ProcessRequestQueue (V$Modbus_Version) qlen $qlen, sending " . unpack ("H*", $frame), 4, $request);

    $request->{SENT}   = $now;
    $request->{FRAME}  = $frame;            # frame as data string for echo detection
    $ioHash->{REQUEST} = $request;          # save for later
    $ioHash->{EXPECT}  = 'response';        # expect to read a response
    
    $ioHash->{READ}{BUFFER} = "";           # clear Buffer for next reception
    
    Modbus_Statistics($ioHash, "Requests", 1);
    Modbus_Send($ioHash, $reqId, $frame, $logHash);
    Modbus_Profiler($ioHash, "Wait");   

    # todo: put in "setTimeoutTimer" function
    my $timeout = Modbus_DevInfo($logHash, "timing", "timeout", 2);
    my $toTime  = $now+$timeout;
    RemoveInternalTimer ("timeout:$name");
    InternalTimer($toTime, "Modbus_ResponseTimeout", "timeout:$name", 0);
    $ioHash->{nextTimeout} = $toTime;       # to be able to calculate remaining timeout time in ReadAnswer
        
    shift(@{$queue});                       # remove first element from queue
    readingsSingleUpdate($ioHash, "QueueLength", ($queue ? scalar(@{$queue}) : 0), 1) if (AttrVal($name, "enableQueueLengthReading", 0));
    Modbus_StartQueueTimer($ioHash);        # schedule next call if there are more items in the queue
    return;
}


###########################################################
# Pack holding / input register / coil Data for a response, 
# only called from createResponse which is only called from HandleRequest
# with logical device hash and the response hash

# two lengths:
# one (valuesLen) from the response hash LEN (copied from the request length)
# and one (len) from the objInfo for the current object
#

sub ModbusLD_PackObj($$) {
    my ($logHash, $response) = @_;
    my $name      = $logHash->{NAME};

    my $valuesLen = $response->{LEN};           # length of the values string requested
    my $type      = $response->{TYPE};          # object to start with
    my $startAdr  = $response->{ADR};
    
    my $lastAdr   = ($valuesLen ? $startAdr + $valuesLen -1 : 0);
    my $data      = "";
    my $counter   = 0;
    
    #Log3 $name, 5, "$name: PackObj called from " . Modbus_Caller();
    Log3 $name, 5, "$name: PackObj called from " . Modbus_Caller() . " with $type $startAdr" .  
                    ($valuesLen ? " and valuesLen $valuesLen" : "");
    $valuesLen = 1 if (!$valuesLen);
    use bytes;
    
    while ($counter < $valuesLen) {
        # einzelne Felder verarbeiten
        my $key     = $type . $startAdr;
        my $reading = Modbus_ObjInfo($logHash, $key, "reading");                    # is data coming from a reading
        my $expr    = Modbus_ObjInfo($logHash, $key, "setexpr", "defSetexpr");      # or a setexpr (convert to register data)
        my $format  = Modbus_ObjInfo($logHash, $key, "format", "defFormat");        # no format if nothing specified
        my $map     = Modbus_ObjInfo($logHash, $key, "map", "defMap");              # no map if not specified
        my $unpack  = Modbus_ObjInfo($logHash, $key, "unpack", "defUnpack", "n");  
        my $len     = Modbus_ObjInfo($logHash, $key, "len", "defLen", 1);           # default to 1 Reg / 2 Bytes
        my $decode  = Modbus_ObjInfo($logHash, $key, "decode", "defDecode");        # character decoding 
        my $encode  = Modbus_ObjInfo($logHash, $key, "encode", "defEncode");        # character encoding 
        my $revRegs = Modbus_ObjInfo($logHash, $key, "revRegs", "defRevRegs");      # do not reverse register order by default
        my $swpRegs = Modbus_ObjInfo($logHash, $key, "bswapRegs", "defBswapRegs");  # dont reverse bytes in registers by default
        
        if (!$reading && !$expr) {
            Log3 $name, 5, "$name: PackObj doesn't have reading or expr information for $key, set error code to 2";
            my $code = Modbus_DevInfo($logHash, $type, "addressErrCode", 2); 
            if ($code) {
                $response->{ERRCODE} = $code;       # if set, packResponse will not use values string
                return 0;
            }
        } else {
            Log3 $name, 5, "$name: PackObj ObjInfo for $key: reading=$reading, expr=$expr, format=$format, len=$len, map=$map, unpack=$unpack";
        }
        
        my $val = 0;    
        # value from defined reading
        if ($reading) {                                         # Reading as source of value
            my $device = $name;                                 # default device is myself
            my $rname  = $reading;                              # given name as reading name
            if ($rname =~ /^([^\:]+):(.+)$/) {                  # can we split given name to device:reading?
                $device = $1;
                $rname  = $2;
            }
            $val = ReadingsVal($device, $rname, "");
            Log3 $name, 4, "$name: PackObj for $key is using reading $rname of device $device with value $val";
        }
        
        # expression
        if ($expr) {                                            # expr as source or manipulation of value
            my @val = ($val);
            $val = Modbus_CheckEval($logHash, @val, $expr, "expression for $key");
            Log3 $name, 5, "$name: PackObj for $key converted value with setexpr $expr to $val";
        }
        
        # format
        if ($format) {                                          # format given?
            $val = sprintf($format, $val);
            Log3 $name, 5, "$name: PackObj for $key formats value with sprintf $format to $val";
        }       
        
        # map
        if ($map) {                  
            my $newVal = Modbus_MapConvert ($logHash, $map, $val, 1);       # use reversed map
            return "value $val did not match defined map" if (!defined($val));
            $val = $newVal;
        }
        
        # encode / decode
        $val = decode($decode, $val) if ($decode);
        $val = encode($encode, $val) if ($encode);

        if ($type =~ "[cd]") {
            $data .= ($val ? '1' : '0');
            $counter++;
        } else {
            my $dataPart = pack ($unpack, $val);                # use unpack code
            Log3 $name, 5, "$name: PackObj packed $val with pack code $unpack to " . unpack ('H*', $dataPart);
            $dataPart =  substr ($dataPart . pack ('x' . $len * 2, undef), 0, $len * 2);
            Log3 $name, 5, "$name: PackObj padded / cut object to " . unpack ('H*', $dataPart);
            $counter += $len; 
            
            $dataPart = Modbus_RevRegs($logHash, $dataPart, $len) if ($revRegs && length($dataPart > 3));
            $dataPart = Modbus_SwpRegs($logHash, $dataPart, $len) if ($swpRegs);
            $data .= $dataPart;
        }
        
        # gehe zum nächsten Wert
        if ($type =~ "[cd]") {
            $startAdr++;
        } else {
            $startAdr += $len;            
        }
        if ($counter < $valuesLen) {
            Log3 $name, 5, "$name: PackObj moves to next object, skip $len to $type$startAdr, counter=$counter";
        } else {
            Log3 $name, 5, "$name: PackObj counter reached $counter";
        }
        
    }
    if ($type =~ "[cd]") {
        Log3 $name, 5, "$name: PackObj full bit string is $data";
        $data = pack ("b$valuesLen", $data);
        Log3 $name, 5, "$name: PackObj packed / cut data string is " . unpack ('H*', $data);
        # todo: is this format correct?
        # not something like FF00? or only for special fc?
        
    } else {
        Log3 $name, 5, "$name: PackObj full data string is " . unpack ('H*', $data);
        # values len means registers so byte length is values len times 2
        $data =  substr ($data . pack ('x' . $valuesLen * 2, undef), 0, $valuesLen * 2);
        Log3 $name, 5, "$name: PackObj padded / cut data string to " . unpack ('H*', $data);
    }
    return $data;
}




#######################################
# Pack request pdu from fCode, adr, len 
# and optionally the packed value 
sub Modbus_PackRequest($$) 
{
    my ($ioHash, $request) = @_;
    my $name = $ioHash->{NAME};
    
    my $fCode  = $request->{FCODE};
    my $adr    = $request->{ADR};
    my $len    = $request->{LEN};
    my $values = $request->{VALUES};
    
    #Log3 $name, 5, "$name: PackRequest called from " . Modbus_Caller();
    my $data;
    if ($fCode == 1 || $fCode == 2) {           
    # read coils / discrete inputs,             pdu: fCode, startAdr, len (=number of coils)
        $data = pack ('nn', $adr, $len);        
    } elsif ($fCode == 3 || $fCode == 4) {      
        # read holding/input registers,         pdu: fCode, startAdr, len (=number of regs)
        $data = pack ('nn', $adr, $len);
    } elsif ($fCode == 5) {                     
        # write single coil,                    pdu: fCode, startAdr, value (1-bit as FF00)
        $data = pack ('n', $adr) . $values;
    } elsif ($fCode == 6) {                     
        # write single register,                pdu: fCode, startAdr, value
        $data = pack ('n', $adr) . $values;
        # todo: shorten bit string and log message if more than one register is attempted here
        
    } elsif ($fCode == 15) {                    
        # write multiple coils,                 pdu: fCode, startAdr, numOfCoils, byteCount, values
        $data = pack ('nnC', $adr, $len, int($len/8)+1) . $values;      
    } elsif ($fCode == 16) {                    
        # write multiple regs,                  pdu: fCode, startAdr, numOfRegs, byteCount, values
        $data = pack ('nnC', $adr, $len, $len*2) . $values;
    } else {                                    
        # function code not implemented yet
        Log3 $name, 3, "$name: Send function code $fCode not yet implemented";
        return;
    }
    return pack ('C', $fCode) . $data;
}   


###############################################################
# Pack response pdu from fCode, adr, len and the packed values 
# or an error pdu if $response->{ERRCODE} contains something
sub Modbus_PackResponse($$) 
{
    my ($ioHash, $response) = @_;
    my $name = $ioHash->{NAME};
    
    my $fCode  = $response->{FCODE};
    my $adr    = $response->{ADR};
    my $len    = $response->{LEN};
    my $values = $response->{VALUES};
    
    #Log3 $name, 5, "$name: PackResponse called from " . Modbus_Caller();
    my $data;
    if ($response->{ERRCODE}) {                 # error PDU                     pdu: fCode+128, Errcode
        return pack ('CC', $fCode + 128, $response->{ERRCODE});
    } elsif ($fCode == 1 || $fCode == 2) {      # read coils / discrete inputs, pdu: fCode, len (=number of bytes), coils/inputs as bits
        $data = pack ('C', int($len/8)+1) . $values;        
    } elsif ($fCode == 3 || $fCode == 4) {      # read holding/input registers, pdu: fCode, len (=number of bytes), registers
        $data = pack ('C', $len * 2) . $values;
    } elsif ($fCode == 5) {                     # write single coil,            pdu: fCode, startAdr, coil value (1-bit as FF00)
        $data = pack ('n', $adr) . $values;
    } elsif ($fCode == 6) {                     # write single register,        pdu: fCode, startAdr, register value
        $data = pack ('n', $adr) . $values;
    } elsif ($fCode == 15) {                    # write multiple coils,         pdu: fCode, startAdr, numOfCoils
        $data = pack ('nn', $adr, $len);      
    } elsif ($fCode == 16) {                    # write multiple regs,          pdu: fCode, startAdr, numOfRegs
        $data = pack ('nn', $adr, $len);
    } else {                                    # function code not implemented yet
        Log3 $name, 3, "$name: Send function code $fCode not yet implemented";
        return;
    }
    return pack ('C', $fCode) . $data;
}   


#######################################
# Pack Modbus Frame
sub Modbus_PackFrame($$$$) 
{
    my ($hash, $id, $pdu, $tid) = @_;
    my $name  = $hash->{NAME};
    my $proto = $hash->{PROTOCOL};
    
    #Log3 $name, 5, "$name: PackFrame called from " . Modbus_Caller() . " id $id" .
    #    ($tid ? ", tid $tid" : "") . ", pdu " . unpack ('H*', $pdu);
    
    my $packedId = pack ('C', $id);    
    my $frame;
    if ($proto eq "RTU") {                          # RTU frame format: ID, (fCode, data), CRC
        my $crc    = pack ('v', Modbus_CRC($packedId . $pdu));
        $frame     = $packedId . $pdu . $crc;
    } elsif ($proto eq "ASCII") {                   # ASCII frame format: ID, (fCode, data), LRC
        my $lrc    = uc(unpack ('H2', pack ('v', Modbus_LRC($packedId.$pdu))));
        $frame     = ':' . uc(unpack ('H2', $packedId) . unpack ('H*', $pdu)) . $lrc . "\r\n";
    } elsif ($proto eq "TCP") {                     # TCP frame format: tid, 0, len, ID, (fCode, data)
        my $dlen   = bytes::length($pdu)+1;         # length of pdu + Id
        my $header = pack ('nnnC', ($tid, 0, $dlen, $id));
        $frame     = $header.$pdu;
    } else {
        Log3 $name, 3, "$name: PackFrame got unknown protocol $proto";
    }
    return $frame;
}



#####################################
# send a frame string
# called from processRequestQueue, CreateResponse 
# and RelayResponse
sub Modbus_Send($$$;$)
{
    my ($ioHash, $id, $frame, $logHash) = @_;
    my $name = $ioHash->{NAME};
    Modbus_Profiler($ioHash, "Send");       
    #Log3 $name, 3, "$name: insert Garbage for testing";
    #$ioHash->{READ}{BUFFER} = pack ("C",0);  # test / debug / todo: remove
    #Log3 $name, 5, "$name: Send called from " . Modbus_Caller();
    
    if ($ioHash->{TCPServer}) {
        Log3 $name, 3, "$name: Send called for TCP Server hash - this should not happen";
        return;
    }
    
    if ($ioHash->{TCPChild}) {
        # write to TCP connected modbus master / tcp client (we are modbus slave)
        if (!$ioHash->{CD}) {
            Log3 $name, 3, "$name: no connection to send to";
            return;
        }
        Log3 $name, 4, "$name: Send " . unpack ('H*', $frame);
        for (;;) {
            my $l = syswrite($ioHash->{CD}, $frame);
            last if(!$l || $l == length($frame));
            $frame = substr($frame, $l);
        }
        $ioHash->{CD}->flush();
    } else {
        if (!DevIo_IsOpen($ioHash)) {
            Log3 $name, 3, "$name: no connection to send to";
            return;
        }
        # write to serial or TCP connected modbus slave / tcp server (we are modbus master)
        DevIo_SimpleWrite($ioHash, $frame, 0);
    }
    
    my $now = gettimeofday();
    $logHash->{REMEMBER}{lsend} = $now;         # remember when last send to this device
    $ioHash->{REMEMBER}{lsend}  = $now;         # remember when last send to this bus
    $ioHash->{REMEMBER}{lid}    = $id;          # device id we talked to
    $ioHash->{REMEMBER}{lname}  = $name;        # logical device name
}


#########################################################################
# set internal Timer to call GetUpdate if necessary
# either at next interval 
# or if start is passed in start seconds (e.g. 2 seconds after Fhem init)
# called from attr (disable, alignTime), set (interval, start), openCB, 
# notify (INITIALIZED|REREADCFG|MODIFIED|DEFINED) and getUpdate

# problem: when disconected while waiting for next update cycle, 
#   StartUpdateTimer gets called after immediate reopen. 
#   Timer should be set as short as possible (>= lastUpdate + Interval)
#   or if timeAlign, then 


# how to set timer after a new open?
# if timer is still running, just keep it 
#    but maybe alignTime was set in the meantime -> timer needs new alignment now or after next update
# if alignTime didn't change, timer can be kept.
#
# if timer is not running and last update was longer ago than interval, schedule update to happen immediately
#

sub ModbusLD_StartUpdateTimer($)
{
    my ($hash) = @_;
    my $name   = $hash->{NAME};
    my $now    = gettimeofday();
    my $action = "updated timer";
    my $intvl  = ($hash->{INTERVAL} ? $hash->{INTERVAL} : 0);
    my $delay;
    my $nextUpdate;
    
    #Log3 $name, 5, "$name: StartUpdateTimer called from " . Modbus_Caller();
    if ($intvl > 0) {   # there is an interval -> set timer
        if ($hash->{TimeAlign}) {
            # it doesn't matter when last update was, or if timer is still set. we can always calculate next update
            my $start   = ($hash->{lastUpdate} ? 0 : 2);        # first update at least 2 secs from now
            my $count   = int(($now - $hash->{TimeAlign} + $start) / $intvl);
            $nextUpdate = $hash->{TimeAlign} + $count * $intvl + $intvl;    

        } elsif ($hash->{TRIGGERTIME} && $hash->{TRIGGERTIME} <= ($now + $intvl)) {
            # timer is still set and shorter than new calculation -> keep and log
            $action = "kept existing timer";
            $nextUpdate = $hash->{TRIGGERTIME};
        } elsif (!$hash->{lastUpdate}) {
            # first time timer is set
            $action = "initialisation";
            $nextUpdate = $now + 2;
        } else {
            $nextUpdate = $hash->{lastUpdate} + $intvl;
            $nextUpdate = $now if ($nextUpdate < $now );
        }
        $hash->{TRIGGERTIME}     = $nextUpdate;
        $hash->{TRIGGERTIME_FMT} = FmtDateTime($nextUpdate);
        $delay = sprintf ("%.1f", $nextUpdate - $now);
        Log3 $name, 5, "$name: SetartUpdateTimer called from " . Modbus_Caller() . 
            " $action, will call GetUpdate in $delay sec at $hash->{TRIGGERTIME_FMT}, interval $intvl";
        RemoveInternalTimer("update:$name");
        InternalTimer($nextUpdate, "ModbusLD_GetUpdate", "update:$name", 0);
            
    } else {    # no interval -> no timer
        ModbusLD_StopUpdateTimer($hash);
    }
    return;
}


#########################################################################
# stop internal Timer to call GetUpdate (if it existed at all)
sub ModbusLD_StopUpdateTimer($)
{
    my ($hash) = @_;
    my $name   = $hash->{NAME};
    RemoveInternalTimer("update:$name");
    if ($hash->{TRIGGERTIME}) {
        Log3 $name, 4, "$name: internal update interval timer stopped";
        delete $hash->{TRIGGERTIME};
        delete $hash->{TRIGGERTIME_FMT};
        $hash->{TRIGGERTIME_SAVED} = $hash->{TRIGGERTIME};
    }
    return;
}


#####################################
# called via internal timer from 
# logical device module with 
# update:name - name of logical device
#
# connection doesn't need to be open - request can just be queued 
# and then processqueue will call async open and remove queue entries
# if they get too old
#
sub ModbusLD_GetUpdate($) {
    my $param = shift;
    my ($calltype,$name) = split(':',$param);
    my $hash      = $defs{$name};       # logisches Device, da GetUpdate aus dem logischen Modul per Timer gestartet wird
    my $modHash   = $modules{$hash->{TYPE}};

    my $parseInfo = ($hash->{parseInfo} ? $hash->{parseInfo} : $modHash->{parseInfo});
    my $devInfo   = ($hash->{deviceInfo} ? $hash->{deviceInfo} : $modHash->{deviceInfo});
    
    my $now       = gettimeofday();
    
    Log3 $name, 5, "$name: GetUpdate called from " . Modbus_Caller();
    $hash->{lastUpdate} = $now;
    if ($calltype eq "update") {
        delete $hash->{TRIGGERTIME};
        delete $hash->{TRIGGERTIME_FMT};
        ModbusLD_StartUpdateTimer($hash);
    }
    
    my $msg = ModbusLD_CheckDisable($hash);
    if ($msg) {
        Log3 $name, 5, "$name: GetUpdate called but $msg";
        return;
    }
    my $ioHash = ModbusLD_GetIOHash($hash);         # only needed for profiling, availability id checked in CheckDisable    
    Modbus_Profiler($ioHash, "Fhem");
    my @ObjList;
    my %readList;
    
    foreach my $at (keys %{$attr{$name}}) {
        if ($at =~ /^obj-(.*)-reading$/) {
            push @ObjList, $1 if (!$parseInfo->{$1});
        }
    };
    Log3 $name, 5, "$name: GetUpdate objects from attributes: " . join (" ",  @ObjList);
    push @ObjList, keys (%{$parseInfo});
    Log3 $name, 5, "$name: GetUpdate full object list: " . join (" ",  sort @ObjList);
    
    # create readList by checking delays and poll settings for ObjList
    foreach my $objCombi (sort @ObjList) {
        #my $type       = substr($objCombi, 0, 1);
        #my $adr        = substr($objCombi, 1);
        my $reading    = Modbus_ObjInfo($hash, $objCombi, "reading");
        my $objHashRef = $parseInfo->{$objCombi};
        #my $devTypeRef = $devInfo->{$type};
        my $poll       = Modbus_ObjInfo($hash, $objCombi, "poll", "defPoll", 0);
        my $lastRead   = ($hash->{lastRead}{$objCombi} ? $hash->{lastRead}{$objCombi} : 0);
        Log3 $name, 5, "$name: GetUpdate check $objCombi => $reading, poll = $poll, last = $lastRead";
        
        if (($poll && $poll ne "once") || ($poll eq "once" && !$lastRead)) {
        
            my $delay = Modbus_ObjInfo($hash, $objCombi, "polldelay", "", "0.5");
            if ($delay =~ "^x([0-9]+)") {
                $delay = $1 * ($hash->{INTERVAL} ? $hash->{INTERVAL} : 1);  
                # Delay als Multiplikator des Intervalls falls es mit x beginnt.
            }

            if ($now >= $lastRead + $delay) {
                Log3 $name, 4, "$name: GetUpdate will request $reading";
                $readList{$objCombi} = 1;                   # include it in the list of items to read
                # lastRead wird bei erfolgreichem Lesen in ParseObj gesetzt.
            } else {
                Log3 $name, 5, "$name: GetUpdate will skip $reading, delay not over";
            }
        }
    }
    
    Log3 $name, 5, "$name: GetUpdate tries to combine read commands";
    my ($obj,     $type,     $adr,     $reading,     $len,     $span);
    my ($nextObj, $nextType, $nextAdr, $nextReading, $nextLen, $nextSpan);
    my $maxLen;
    $adr  = 0; $type = ""; $span = 0; $nextSpan = 0;
    
    # combine objects in Readlist by increasing the length of a first object and removing the second
    foreach $nextObj (sort Modbus_compObjKeys keys %readList) {
        $nextType    = substr($nextObj, 0, 1);
        $nextAdr     = substr($nextObj, 1);
        $nextReading = Modbus_ObjInfo($hash, $nextObj, "reading");
        $nextLen     = Modbus_ObjInfo($hash, $nextObj, "len", "defLen", 1);
        $readList{$nextObj} = $nextLen;
        if ($obj && $maxLen){
            $nextSpan = ($nextAdr + $nextLen) - $adr;   # Combined length with next object
            if ($nextType eq $type && $nextSpan <= $maxLen && $nextSpan > $span) {
                Log3 $name, 5, "$name: GetUpdate combines request for $reading ($obj) with $nextReading ($nextObj), ".
                    "span=$nextSpan, max=$maxLen, drop read for $nextObj";
                delete $readList{$nextObj};             # no individual read for this object, combine with last
                $span = $nextSpan;
                $readList{$obj} = $nextSpan;            # increase the length to include following object
                next;   # don't change current object variables
            } else {
                Log3 $name, 5, "$name: GetUpdate cant combine request for $reading / $obj with $nextReading / $nextObj, ".
                    "span $nextSpan > max $maxLen";
                $nextSpan = 0;
            }
        }
        ($obj, $type, $adr, $reading, $len, $span) = ($nextObj,  $nextType, $nextAdr, $nextReading, $nextLen, $nextSpan);
        $maxLen = Modbus_DevInfo($hash, $type, "combine", 1);
        # Log3 $name, 5, "$name: GetUpdate: combine for $type is $maxLen";    
    }

    if (AttrVal($name, "sortUpdate", 0)) {
        Log3 $name, 5, "$name: GetUpdate is sorting objList before sending requests";
        foreach my $objCombi (sort Modbus_compObjKeys keys %readList) {
            my $span = $readList{$objCombi};
            ModbusLD_DoRequest($hash, $objCombi, "read", 0, 0, $span, "getUpdate");
        }
    } else {
        Log3 $name, 5, "$name: GetUpdate doesn't sort objList before sending requests";
        while (my ($objCombi, $span) = each %readList) {
            ModbusLD_DoRequest($hash, $objCombi, "read", 0, 0, $span, "getUpdate");
        }
    }
    Modbus_Profiler($ioHash, "Idle");   
    return;
}




######################################################
# log current frame in buffer 
sub Modbus_FrameText($;$$)
{
    my ($hash, $request, $response) = @_;
    my $now   = gettimeofday();
    $request  = $hash->{REQUEST} if (!$request);
    $response = $hash->{RESPONSE} if (!$response);
    
    return ($request ? "request: id $request->{MODBUSID}, fCode $request->{FCODE}" .
            (defined($request->{TID}) ? ", tid $request->{TID}" : "") .
            ($request->{TYPE} ? ", type $request->{TYPE}" : "") .
            (defined($request->{ADR}) ? ", adr $request->{ADR}" : "") .
            ($request->{LEN} ? ", len $request->{LEN}" : "") .
            ($request->{VALUES} ? ", value " . unpack('H*', $request->{VALUES}) : "") .
            ($request->{DEVHASH} ? " for device $request->{DEVHASH}{NAME}" : "") .
            ($request->{READING} ? " reading $request->{READING}" : "") . 
            ($request->{DBGINFO} ? " ($request->{DBGINFO})" : "") . 
            ($request->{TIMESTAMP} ? ", queued " . sprintf("%.2f", $now - $request->{TIMESTAMP}) . " secs ago" : "") . 
            ($request->{SENT} ? ", sent " . sprintf("%.2f", $now - $request->{SENT}) . " secs ago" : "") 
        : "") .         
        ($hash->{READ}{BUFFER} ? ", Current read buffer: " . unpack('H*', $hash->{READ}{BUFFER}) : ", read buffer empty") .
        ($hash->{FRAME}{MODBUSID} ? ", Id $hash->{FRAME}{MODBUSID}" : "") .
        ($hash->{FRAME}{FCODE} ? ", fCode $hash->{FRAME}{FCODE}" : "") .
        (defined($hash->{FRAME}{TID}) ? ", tid $hash->{FRAME}{TID}" : "") .
        ($response ? ", response: id $response->{MODBUSID}, fCode $response->{FCODE}" .
            (defined($response->{TID}) ? ", tid $response->{TID}" : "") .
            ($response->{TYPE} ? ", type $response->{TYPE}" : "") .
            (defined($response->{ADR}) ? ", adr $response->{ADR}" : "") .
            ($response->{LEN} ? ", len $response->{LEN}" : "") .
            ($response->{VALUES} ? ", value " . unpack('H*', $response->{VALUES}) : "")
        : "") .
        ($hash->{FRAME}{ERROR} ? ", error: $hash->{FRAME}{ERROR}" : "");
}



######################################################
# log current frame in buffer 
sub Modbus_LogFrame($$$;$$)
{
    my ($hash, $msg, $logLvl, $request, $response) = @_;
    my $name  = $hash->{NAME};
    Log3 $name, $logLvl, "$name: $msg " . Modbus_FrameText($hash, $request, $response);
    return;
}


######################################################
# drop current frame from buffer or clear full buffer
# caled from Timeout-, Done and Error functions
sub Modbus_DropFrame($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $drop = $hash->{READ}{BUFFER};
    my $rest = "";
    
    if ($hash->{MODE} ne 'master' && $hash->{FRAME}{PDULEXP} && $hash->{PROTOCOL}) {
        my $frameLen = $hash->{FRAME}{PDULEXP} + $Modbus_PDUOverhead{$hash->{PROTOCOL}};
        $drop = substr($hash->{READ}{BUFFER}, 0, $frameLen);
        $rest = substr($hash->{READ}{BUFFER}, $frameLen);
    }
    Log3 $name, 5, "$name: DropFrame - drop " . unpack ('H*', $drop) .
        ($rest ? " rest " . unpack ('H*', $rest) : "");
    $hash->{READ}{BUFFER} = $rest;
    delete $hash->{FRAME};
    return;
}


##################################################
# add a message to the $frame->{ERROR} String
sub Modbus_AddFrameError($$) 
{
    my ($frame, $msg) = @_;
    $frame->{ERROR} .= ($frame->{ERROR} ? ', ' : '') . $msg;
}


##################################################################
# get end of pdu / start of lrc / crc if applicable
# check crc / lrc and set $hash->{FRAME}{CHECKSUMERR} if necessary
# leave length checking, reaction / logging / dropping 
# to read function
sub Modbus_CheckChecksum($)
{   
    my ($hash) = @_;
    my $name  = $hash->{NAME};
    my $proto = $hash->{PROTOCOL};
    my $frame = $hash->{FRAME};
    
    use bytes;
    my $frameLen = $frame->{PDULEXP} + $Modbus_PDUOverhead{$hash->{PROTOCOL}};
    my $readLen  = length($hash->{READ}{BUFFER});
    delete $frame->{CHECKSUMERROR};
    
    if ($proto eq "RTU") {
        my $crcInputLen = ($readLen < $frameLen ? $readLen - 2 : $frameLen - 2);
        $frame->{CHECKSUMSENT} = unpack ('v', substr($hash->{READ}{BUFFER}, $crcInputLen, 2));
        $frame->{CHECKSUMCALC} = Modbus_CRC(substr($hash->{READ}{BUFFER}, 0, $crcInputLen));
    } elsif ($proto eq "ASCII") {
        my $lrcInputLen = ($readLen < $frameLen ? $readLen - 5 : $frameLen - 5); 
        $frame->{CHECKSUMSENT} = hex(substr($hash->{READ}{BUFFER}, $lrcInputLen + 1, 2));
        $frame->{CHECKSUMCALC} = Modbus_LRC(pack ('H*', substr($hash->{READ}{BUFFER}, 1, $lrcInputLen)));
    } elsif ($proto eq "TCP") {
        # nothing to be done.
        return 1;   
    } else {
        Log3 $name, 3, "$name: CheckChecksum (called from " . Modbus_Caller() . ") got unknown protocol $proto";
        return 0;
    }
    
    if ($frame->{CHECKSUMCALC} != $frame->{CHECKSUMSENT}) {
        $frame->{CHECKSUMERROR} = 1;
        Modbus_AddFrameError($frame, "Invalid checksum " . unpack ('H4', pack ('v', $frame->{CHECKSUMSENT})) .
        " received. Calculated " . unpack ('H4', pack ('v', $frame->{CHECKSUMCALC})));
        return 0;
    } else {
        Log3 $name, 5, "$name: CheckChecksum (called from " . Modbus_Caller() . "): " . unpack ('H4', pack ('v', $frame->{CHECKSUMSENT})) . " is valid";
    }
    return 1;
}


#######################################
sub Modbus_CountTimeouts($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};

    if ($hash->{TCPConn}) {             # modbus TCP/RTU/ASCII over TCP
        if ($hash->{TCPServer} || $hash->{TCPChild}) {
            Log3 $name, 3, "$name: CountTimeouts called for TCP Server connection - this should not happen";
            return;
        }
        if ($hash->{TIMEOUTS}) {
            $hash->{TIMEOUTS}++;
            my $max = AttrVal($name, "maxTimeoutsToReconnect", 0);
            if ($max && $hash->{TIMEOUTS} >= $max) {
                Log3 $name, 3, "$name: CountTimeouts counted $hash->{TIMEOUTS} successive timeouts, setting state to disconnected";
                DevIo_Disconnected($hash);      # close, set state and put on readyfnlist for reopening
            }
        } else {
            $hash->{TIMEOUTS} = 1;
        }
    }
    return;
}


###############################################
# Called via InternalTimer with "stimeout:$name" 
# timer is set in ...
# if this is called, we are TCP Slave
sub Modbus_ServerTimeout($)
{
    my ($param) = @_;
    my ($error,$name) = split(':',$param);
    my $hash = $defs{$name};
    if ($hash) {
        if ($hash->{CHILDOF}) {
            my $pHash = $hash->{CHILDOF};
            my $pName = $pHash->{NAME};
            if ($pName) {
                Log3 $pName, 4, "$pName: closing connection after inactivity";
            }
        }
        Modbus_Close($hash);
    }
    return;
};


###############################################
# Called via InternalTimer with "timeout:$name" 
# timer is set in HandleRequestQueue only
# if this is called, we are Master and did send a request
# or we were used as relay forward device 
sub Modbus_ResponseTimeout($)
{
    my ($param) = @_;
    my ($error,$name) = split(':',$param);
    my $hash = $defs{$name};
    my $logLvl = AttrVal($name, "timeoutLogLevel", 3);
    $hash->{EXPECT} = 'idle';
    #Log3 $name, 3, "$name: ResponseTimeout called, devhash=$hash->{REQUEST}{DEVHASH}, name of devhash=$hash->{REQUEST}{DEVHASH}{NAME}";
    #Modbus_StopQueueTimer($hash);                          # don't touch timer here - it is set anyway before fhem does anything else
    Modbus_LogFrame($hash, "Timeout waiting for a modbus response", $logLvl);
    Modbus_Statistics($hash, "Timeouts", 1);
    Modbus_CountTimeouts ($hash);
    if ($hash->{REQUEST}{DEVHASH}{MODE} eq 'relay') {       # create an error response
        # when relaying $hash->{REQUEST} is a copy of the original request
        my $slHash = $hash->{REQUEST}{DEVHASH};             # hash of logical relay device that got the first request
        my $ioHash = ModbusLD_GetIOHash($slHash);           # the ioHash that received the original request
        if (!$ioHash) {
            Log3 $name, 4, "$name: sending timout response back failed because relay slave side io device disappeared";
        } else {
            $ioHash->{REQUEST}{ERRCODE} = 11;               # gw target failed to respond       
            Modbus_CreateResponse($ioHash);                 # create an error response, don't pack values since ERRCODE is set
        }
    }
    Modbus_Profiler($hash, "Idle");
    Modbus_DropFrame($hash);
    delete $hash->{nextTimeout};
    
    my $retries = AttrVal($name, "retriesAfterTimeout", 0);
    $hash->{RETRY} = ($hash->{RETRY} ? $hash->{RETRY} : 0); # deleted in doRequest and responseDone
    if ($hash->{RETRY} < $retries) {
        $hash->{RETRY}++;
        Log3 $name, 4, "$name: retry last request, retry counter $hash->{RETRY}";
        Modbus_QueueRequest($hash, $hash->{REQUEST}, 1);    # force
    } else {
        delete $hash->{REQUEST};
        delete $hash->{RETRY};
    }
    
    Modbus_StartQueueTimer($hash, 0);                       # call processRequestQueue at next possibility if appropriate
    return;
};



#####################################
# Modbus_ResponseDone
# called with physical device hash at the end of HandleResponse which itself is calld from read / readanswer
sub Modbus_ResponseDone($$)
{
    my ($hash, $logLvl) = @_;
    my $name = $hash->{NAME};
    my $msg  = ($hash->{FRAME}{ERROR} ? "ResponseDone with error: $hash->{FRAME}{ERROR}" : "ResponseDone");
    Modbus_LogFrame($hash, $msg, $logLvl) if ($logLvl);
    Modbus_Statistics($hash, "Timeouts", 0);        # damit bei Bedarf das Reading gesetzt wird
    Modbus_Profiler($hash, "Idle");                 # todo: fix       
    $hash->{EXPECT} = ($hash->{MODE} eq 'master' ? 'idle' : 'request');
    Modbus_DropFrame($hash);
    delete $hash->{nextTimeout};
    delete $hash->{TIMEOUTS};
    delete $hash->{RETRY};
    RemoveInternalTimer ("timeout:$name");
    return;
}
# processRequestQueue or startQueueTimer is not called in ResponseDone because 
# when called from read, startQueueTimer is called in read after HandleResponse
# when called from readAnswer, readAnswer returns to get/set who call stertQueueTimer at the end



#####################################
# Modbus_RequestDone
# called with physical device hash from Read
# when we are succussfully done with a request and ready for the response
sub Modbus_RequestDone($$)
{
    my ($hash, $logLvl) = @_;
    my $name = $hash->{NAME};
    my $msg  = ($hash->{FRAME}{ERROR} ? "RequestDone with error: $hash->{FRAME}{ERROR}" : "RequestDone");
    Modbus_LogFrame($hash, $msg, $logLvl) if ($logLvl);
    Modbus_Profiler($hash, "Idle");                 # todo: fix
    
    if (($hash->{MODE} eq 'slave' || $hash->{MODE} eq 'relay') && $hash->{REQUEST}{DEVHASH}) {
        $hash->{EXPECT} = 'request';            # we did answer or forward this request (relaying made a copy) 
        #delete $hash->{REQUEST};               # dont't delete because sending an error fro the relay might need it
    } else {
        $hash->{EXPECT} = 'response';           # not our request, parse response that follows, keep $hash->{REQUEST} for parsing the response (e.g. passive)
    }
    Modbus_DropFrame($hash);
    delete $hash->{RESPONSE};
    return;
}



###############################################
# Called from ReadAnswer 
# we are master and did wait for a response
sub Modbus_ReadAnswerTimeout($$)
{
    my ($hash, $msg) = @_;
    my $name = $hash->{NAME};
    
    my $logLvl = AttrVal($name, "timeoutLogLevel", 3);
    $hash->{EXPECT} = 'idle';
    Modbus_LogFrame($hash, $msg, $logLvl);
    Modbus_Statistics($hash, "Timeouts", 1);
    Modbus_CountTimeouts ($hash);
    Modbus_Profiler($hash, "Idle");
    Modbus_DropFrame($hash);
    delete $hash->{nextTimeout};
    Modbus_StartQueueTimer($hash, 0);                           # call processRequestQueue at next possibility if appropriate
    return $msg;
};


###############################################
# Called from ReadAnswer 
# we are master and did wait for a response
sub Modbus_ReadAnswerError($$)
{
    my ($hash, $msg) = @_;
    my $name = $hash->{NAME};
    
    my $logLvl = AttrVal($name, "timeoutLogLevel", 3);
    $hash->{EXPECT} = 'idle';
    Modbus_LogFrame($hash, $msg, $logLvl);
    Modbus_Profiler($hash, "Idle");
    Modbus_DropFrame($hash);
    delete $hash->{REQUEST};
    delete $hash->{nextTimeout};
    Modbus_StartQueueTimer($hash, 0);                           # call processRequestQueue at next possibility if appropriate
    return $msg;
};


############################################
# Check if disabled or IO device is disabled
sub ModbusLD_CheckDisable($)
{
    my ($hash) = @_;    
    my $name   = $hash->{NAME};
    my $msg;
    #Log3 $name, 5, "$name: CheckDisable called from " . Modbus_Caller();
    
    if ($hash->{TYPE} eq 'Modbus' || $hash->{TCPConn}) {    # physical hash
        if (IsDisabled($name)) {
            $msg = "device is disabled";
        }
    } else {                                                # this is a logical device hash
        my $ioHash = ModbusLD_GetIOHash($hash);             # get physical io device hash
        if (IsDisabled($name)) {
            $msg = "device is disabled";
        } elsif (!$ioHash) {
            $msg = "no IO Device to communicate through";
        } elsif (IsDisabled($ioHash->{NAME})) {
            $msg = "IO device is disabled";
        }
    }
    Log3 $name, 5, "$name: CheckDisable returns $msg" if ($msg);
    return $msg;
}   


###############################################################
# Check if connection through IO Dev is not disabled 
# and call open (force) if necessary for prioritized get / set
# and potentially take over last read with readAnswer
#
# if non prioritized get / set (parameter async = 1) 
# we leave the connection management to ready and processRequestQueue 
# 
sub ModbusLD_GetSetChecks($$)
{
    my ($hash, $async) = @_;
    my $name   = $hash->{NAME};
    my $force  = !$async;
    my $msg    = ModbusLD_CheckDisable($hash);
    if (!$msg) {
        if ($hash->{MODE} && $hash->{MODE} ne 'master') {
            $msg = "only possible as Modbus master";
        } elsif ($force) {
            Log3 $name, 5, "$name: GetSetChecks with force";
            # only check connection if not async 
            my $ioHash = ModbusLD_GetIOHash($hash);             # physical hash to check busy / take over with readAnswer
            if (!$ioHash) {
                $msg = "no IO device";
            } elsif (!DevIo_IsOpen($ioHash)) {
                Modbus_Open($ioHash, 0, $force);                # force synchronous open unless non prioritized get / set
                if (!DevIo_IsOpen($ioHash)) {
                    $msg = "device is disconnected";
                }
            }
            if (!$msg) {
                if ($ioHash->{EXPECT} eq 'response') {     # Answer for last request has not yet arrived
                    
                    Log3 $name, 4, "$name: GetSetChecks calls ReadAnswer to take over async read" . 
                        " (still waiting for response to " . Modbus_FrameText($ioHash);
                    # no $msg because we want to continue afterwards
                    Modbus_ReadAnswer($ioHash);                 # finish last read and wait for result
                }
            }
        }
    }
    if ($msg) {
        Log3 $name, 5, "$name: GetSetChecks returns $msg";
    } else {
        Log3 $name, 5, "$name: GetSetChecks returns success";
    }
    return $msg;
}   
   

################################################################
# reconstruct the $hash->{IODev} pointer to the physical device
# if it is not set by checking the IODev attr or 
# searching for a suitable device
#
# called from GetIOHash with the logical hash
################################################################
sub ModbusLD_SetIODev($;$)
{
    my ($hash, $setIOName) = @_;
    return $hash if ($hash->{TCPConn});
    my $name = $hash->{NAME};
    my $id   = $hash->{MODBUSID};
    my $ioHash;
        
    Log3 $name, 5, "$name: SetIODev called from " . Modbus_Caller();
    my $ioName = ($setIOName ? $setIOName : AttrVal($name, "IODev", ""));
    
    if ($ioName) {                                  # if we have a name (passed or from attribute), check its usability
        if (!$defs{$ioName}) {
            Log3 $name, 3, "$name: SetIODev from $name to $ioName but $ioName does not exist (yet?)";
        } elsif (ModbusLD_CheckIOCompat($hash, $defs{$ioName},3)) {
            $ioHash = $defs{$ioName};               # ioName can be used as io device, set hash
        }
    }
    if (!$ioHash && !$ioName) {                     # if no attr and no name passed search for usable io device
        for my $p (sort { $defs{$b}{NR} <=> $defs{$a}{NR} } keys %defs) {       
            if (ModbusLD_CheckIOCompat($hash, $defs{$p},5)) {
                $ioHash = $defs{$p};
                last;
            }
        }
    }
    ModbusLD_UnregAtIODev($hash);
    if (!$ioHash) {                                 # still nothing found -> give up for now
        Log3 $name, 3, "$name: SetIODev found no usable physical modbus device";
        $hash->{STATE} = "disconnected";            # set state like DevIO would do it after disconnected
        readingsSingleUpdate($hash, "state", "disconnected", 1);
        delete $hash->{IODev};
        return undef;
    }
    ModbusLD_RegisterAtIODev($hash, $ioHash);

    # set initial state like DevIO would do it after open
    $hash->{STATE} = "opened";
    readingsSingleUpdate($hash, "state", "opened", 1);
    return $ioHash;
}

    
#####################################################################
# called from logical device fuctions with log dev hash 
# to get the physical io device hash which should be
# stored in $hash->{IODev} (fhem.pl sets this when IODev attr is set)
# reconstruct this pointer by calling SetIODev if necessary
#
# called from many LD functions like get, set, getUpdate, send, ...
#####################################################################
sub ModbusLD_GetIOHash($){
    my $hash = shift;
    my $name = $hash->{NAME};                                   # name of logical device
    #Log3 $name, 5, "$name: GetIOHash called from " . Modbus_Caller();
    
    return $hash if ($hash->{TCPConn});                         # for TCP/IP connected devices ioHash = hash
    return $hash if ($hash->{TYPE} eq 'Modbus');                # this is already the physical device!
    
    if ($hash->{IODev} && ModbusLD_CheckIOCompat($hash, $hash->{IODev}, 4)) {
        return $hash->{IODev};
    }
    
    Log3 $name, 4, "$name: GetIOHash (called from " . Modbus_Caller() . ") didn't find valid IODev hash key, calling SetIODev now";
    return $hash->{IODev} if (ModbusLD_SetIODev($hash));        # reconstruct pointer to physical device
    Log3 $name, 4, "$name: GetIOHash didn't find IODev attribute or matching physical serial Modbus device";
}


#####################################################################
# Check if $ioHash can be used as IODev for $hash
# return 1 if ok, log if not
#####################################################################
sub ModbusLD_CheckIOCompat($$;$){
    my ($hash, $ioHash, $logLvl) = @_;
    my $name   = $hash->{NAME};                                 # name of logical device
    my $ioName = $ioHash->{NAME};                               # name of physical device
    my $id     = $hash->{MODBUSID};                             # Modbus id of logical device

    return 1 if ($hash->{TCPConn});                             # for TCP/IP connected devices ioHash = hash so everything is fine 
    my $msg;
    if (!$ioHash) {
        #$msg = "no ioHash passed";
        return;
    } elsif (!$id){
        #$msg = "no Modbus id set for $name";
        return;
    } elsif ($ioHash->{TYPE} ne "Modbus") {                     # TCP was checked before so it has to be "Modbus"
        #$msg = "$ioName is not a physical Modbus Device";
        return;
    } elsif (!$hash->{PROTOCOL}) {
        $msg = "$name doesn't have a protocol set";
    } elsif (!$hash->{MODE}) {
        $msg = "$name doesn't have a mode set";
    } elsif ($ioHash->{PROTOCOL} && $ioHash->{PROTOCOL} ne $hash->{PROTOCOL}) {
        my $lName = Modbus_DevLockingKey($ioHash, 'PROTOCOL');
        $lName = 'unknown (this should not happen)' if (!$lName);
        $msg = "$ioName is locked to protocol $ioHash->{PROTOCOL} by $lName";
    } elsif ($ioHash->{MODE} && $ioHash->{MODE} ne $hash->{MODE}) {
        my $lName = Modbus_DevLockingKey($ioHash, 'MODE');
        $lName = 'unknown (this should not happen)' if (!$lName);   
        $msg = "$ioName is locked to mode $ioHash->{MODE} by $lName";
    } elsif ($ioHash->{MODE} && $ioHash->{MODE} ne 'master') {  # only for a master multiple devices can use the same id
        for my $ld (keys %{$ioHash->{defptr}}) {                # for each registered logical device    
            if ($ld ne $name && $defs{$ld} && $defs{$ld}{MODBUSID} == $id) {
                $msg = "$ioName has already registered id $id for $ld";
            }
        }
    }
    if ($msg) {
        Log3 $name, ($logLvl ? $logLvl : 5), "$name: CheckIOCompat (called from " . Modbus_Caller() . ") for $name and $ioName: $msg";
        return;
    }
    return 1;
}


################################################################
# register / lock protocol and mode at io dev 
################################################################
sub ModbusLD_RegisterAtIODev($$)
{
    my ($hash, $ioHash) = @_;
    return if ($hash->{TCPConn});
    my $name   = $hash->{NAME};
    my $id     = $hash->{MODBUSID};
    my $ioName = $ioHash->{NAME};

    Log3 $name, 3, "$name: RegisterAtIODev called from " . Modbus_Caller() . " registers $name at $ioName with id $id" . 
        ($hash->{MODE} ? ", MODE $hash->{MODE}" : "") .
        ($hash->{PROTOCOL} ? ", PROTOCOL $hash->{PROTOCOL}" : "");

    $hash->{IODev}         = $ioHash;               # point internal IODev to io device hash
    
    # todo: 
    # change way of registration. not with id but with name. 
    # only getLogHash needs change then (search all registered devices)
    
    $ioHash->{defptr}{$name} = $id;                 # register logical device for given id at io
    $ioHash->{PROTOCOL} = $hash->{PROTOCOL};        # lock protocol and mode
    $ioHash->{MODE}     = $hash->{MODE};
}
    
    

################################################################
# unregister / unlock protocol and mode at io dev 
# to be called when MODBUSID or IODEv changes 
# or when device is deleted
# see attr, notify or directly from undef
################################################################
sub ModbusLD_UnregAtIODev($)
{
    my ($hash) = @_;
    return if ($hash->{TCPConn});
    my $name = $hash->{NAME};
    my $id   = $hash->{MODBUSID};
    Log3 $name, 5, "$name: UnregAtIODev called from " . Modbus_Caller();

    for my $d (values %defs) {                      # go through all physical Modbus devices
        if ($d->{TYPE} eq 'Modbus') {
            my $protocolCount = 0;
            my $modeCount     = 0;
            for my $ld (keys %{$d->{defptr}}) {     # and their registrations
            #for my $id (keys %{$d->{defptr}}) {    # and their registrations
                my $ldev = $defs{$ld};
                if ($ldev && $ld eq $name) {   
                    Log3 $name, 5, "$name: UnregAtIODev is removing $name from registrations at $d->{NAME}";
                    delete $d->{defptr}{$name};     # delete id as key pointing to $hash if found
                } else {
                    if ($ldev && $ldev->{PROTOCOL} eq $d->{PROTOCOL}) {
                        $protocolCount++;
                    } else {
                        Log3 $name, 3, "$name: UnregAtIODev called from " . Modbus_Caller() . " found device $ld" .
                                " with protocol $ldev->{PROTOCOL} registered at $d->{NAME} with protocol $d->{PROTOCOL}." .
                                " This should not happen";
                    }
                    if ($ldev->{MODE} eq $d->{MODE}) {
                        $modeCount++;
                    } else {
                        Log3 $name, 3, "$name: UnregAtIODev called from " . Modbus_Caller() . " found device $ld" .
                                " with mode $ldev->{MODE} registered at $d->{NAME} with mode $d->{MODE}." .
                                " This should not happen";
                    }
                }
            }
            if (!$protocolCount && !$modeCount) {
                Log3 $name, 5, "$name: UnregAtIODev is removing locks at $d->{NAME}";
                delete $d->{PROTOCOL};
                delete $d->{MODE};
            }
        }
    }
}


#####################################################################
# called from HandleRequest / HandleResponse
# with Modbus ID to get logical device hash responsible for this Id
#
# The Id passed here (from a received Modbus frame) is looked up
# in the table of registered logical devices.
# for requests this is the way to find the right logical device hash
#
# for responses it should match the id of the request sent/seen before
# 
# The logical device hash pointed to should have this id set as well
# and if it is TCP connected, the logical has is also the physical
#

# todo: pass mode required (master or slave/relay?) ??

#####################################################################
sub Modbus_GetLogHash($$){
    my ($ioHash, $Id) = @_;
    my $name = $ioHash->{NAME};                 # name of physical device
    my $logHash;
    my $logName; 

    if ($ioHash->{TCPConn}) {
        $logHash = $ioHash;                     # Modbus TCP/RTU/ASCII über TCP, physical hash = logical hash
    } else {
        for my $ld (keys %{$ioHash->{defptr}}) {    # for each registered logical device    
            if ($ioHash->{defptr}{$ld} == $Id) {
                $logHash = $defs{$ld};
            }
        }
        if (!$logHash) {
            for my $d (values %defs) {          # go through all physical Modbus devices and look for a suitable one
                if ($d->{TYPE} ne 'Modbus' && $d->{MODULEVERSION} && $d->{MODULEVERSION} =~ /^Modbus / 
                        && $d->{MODBUSID} eq $Id && $d->{PROTOCOL} eq $ioHash->{PROTOCOL} && $d->{MODE} eq $ioHash->{MODE}) {
                    $logHash = $d;
                    Log3 $name, 3, "$name: GetLogHash called from " . Modbus_Caller() . 
                        " found logical device by searching! This should not happen";
                }
            }
        }
    }
    
    if ($logHash) {
        $logName = $logHash->{NAME};
        if ($logHash->{MODBUSID} != $Id) {
            Log3 $name, 3, "$name: GetLogHash called from " . Modbus_Caller() . " detected wrong Modbus Id";
            $logHash = undef;
        } else {
            Log3 $name, 5, "$name: GetLogHash returns hash for device $logName" if (!$ioHash->{TCPConn});
        }
    } else {
        Log3 $name, 5, "$name: GetLogHash didnt't find a logical device for Modbus id $Id";
    }
    return $logHash
}



#######################################################################################
# who locked key at iodev ?
sub Modbus_DevLockingKey($$)
{
    my ($ioHash, $key) = @_;
    my $ioName = $ioHash->{NAME};
    
    my $found;
    foreach my $ld (keys %{$ioHash->{defptr}}) {
        if ($defs{$ld} && $defs{$ld}{$key} eq $ioHash->{$key}) {
            $found = 1;
            Log3 $ioName, 5, "$ioName: DevLockingKey found $ld to lock key $key at $ioName as $defs{$ld}{$key}";
            return $ld;
        }
    }
    return undef;
}


########################################
# not used currently
sub Modbus_compObjAttrs ($$) {
    my ($a, $b)   = @_;
    my $aType  = substr($a, 4, 1);
    my $aStart = substr($a, 5);
    my $bType  = substr($b, 4, 1);
    my $bStart = substr($b, 5);
    my $result = ($aType cmp $bType);   
    if ($result) {
        return $result;
    }
    $result = $aStart <=> $bStart;
    return $result;
}


########################################
# used for sorting and combine checking
sub Modbus_compObjKeys ($$) {
    my ($a, $b)   = @_;
    my $aType  = substr($a, 0, 1);
    my $aStart = substr($a, 1);
    my $bType  = substr($b, 0, 1);
    my $bStart = substr($b, 1);
    my $result = ($aType cmp $bType);   
    if ($result) {
        return $result;
    }
    $result = $aStart <=> $bStart;
    return $result;
}



####################################################
# format time as string with msecs as fhem.pl does
sub Modbus_FmtTime($)
{
    my ($time) = @_;
    my $seconds = int ($time);
    my $mseconds = $time - $seconds;
    my @t = localtime($seconds);
    my $tim = sprintf("%02d:%02d:%02d", $t[2],$t[1],$t[0]);
    $tim .= sprintf(".%03d", $mseconds*1000);
    return $tim;
}



#####################################
sub Modbus_CRC($) {
  use bytes;
  my $frame = shift;
  my $crc = 0xFFFF;
  my ($chr, $lsb);
  for my $i (0..bytes::length($frame)-1) {
    $chr = ord(bytes::substr($frame, $i, 1));
    $crc ^= $chr;
    for (1..8) {
      $lsb = $crc & 1;
      $crc >>= 1;
      $crc ^= 0xA001 if $lsb;
      }
    }
  no bytes;
  return $crc;
}


#####################################
sub Modbus_LRC($) {
    use bytes;
    my $frame = shift;
    my $lrc   = 0;
    my $chr;
    for my $i (0..bytes::length($frame)-1) {
        $chr = ord(bytes::substr($frame, $i, 1));
        $lrc = ($lrc + $chr) & 0xff;
    }
    return (0xff - $lrc) +1;
}


#####################################
# called from send and parse
# reverse order of word registers
sub Modbus_RevRegs($$$) {
    my ($hash, $buffer, $len) = @_;             # hash only needed for logging
    my $name = $hash->{NAME};                   # name of device for logging

    Log3 $name, 5, "$name: RevRegs is reversing order of up to $len registers";
    my $work = substr($buffer, 0, $len * 2);    # the first 2*len bytes of buffer
    my $rest = substr($buffer, $len * 2);       # everything after len
    
    my $new = "";
    while ($work) {
        $new = substr($work, 0, 2) . $new;      # prepend first two bytes of work to new
        $work = substr($work, 2);               # remove first word from work
    }
    Log3 $name, 5, "$name: RevRegs string before is " . unpack ("H*", $buffer);
    $buffer = $new . $rest;
    Log3 $name, 5, "$name: RevRegs string after  is " . unpack ("H*", $buffer);
    return $buffer;
}


#####################################
# called from send and parse
# reverse byte order in word registers
sub Modbus_SwpRegs($$$) {
    my ($hash, $buffer, $len) = @_;             # hash only needed for logging
    my $name = $hash->{NAME};                   # name of device for logging

    Log3 $name, 5, "$name: SwpRegs is reversing byte order of up to $len registers";
    my $rest = substr($buffer, $len * 2);       # everything after len
    my $nval = "";
    for (my $i = 0; $i < $len; $i++) { 
        $nval = $nval . substr($buffer,$i*2 + 1,1) . substr($buffer,$i*2,1);
    }; 
    Log3 $name, 5, "$name: SwpRegs string before is " . unpack ("H*", $buffer);
    $buffer = $nval . $rest;
    Log3 $name, 5, "$name: SwpRegs string after  is " . unpack ("H*", $buffer);
    return $buffer;
}


################################################
# Get obj- Attribute with potential 
# leading zeros
sub Modbus_ObjAttr($$$) {
    my ($hash, $key, $oName) = @_;
    my $name  = $hash->{NAME};
    my $aName = "obj-".$key."-".$oName;
    return $attr{$name}{$aName} if (defined($attr{$name}{$aName}));
    if ($hash->{LeadingZeros}) {    
        if ($key =~ /([cdih])0*([0-9]+)/) {
            my $type = $1;
            my $adr  = $2;
            while (length($adr) <= 5) {             
                $aName = "obj-".$type.$adr."-".$oName;
                Log3 $name, 5, "$name: ObjInfo check $aName";
                return $attr{$name}{$aName} 
                    if (defined($attr{$name}{$aName}));
                $adr = '0' . $adr;
            }
        }
    }
    return undef;
}

    
################################################
# Get Object Info from Attributes,
# parseInfo Hash or default from deviceInfo Hash
sub Modbus_ObjInfo($$$;$$) {
    my ($hash, $key, $oName, $defName, $lastDefault) = @_;
    #   Device  h123  unpack  defUnpack
    $hash = $hash->{CHILDOF} if ($hash->{CHILDOF});                     # take info from parent device if TCP server conn (TCP slave)
    my $name      = $hash->{NAME};
    my $modHash   = $modules{$hash->{TYPE}};
    my $parseInfo = ($hash->{parseInfo} ? $hash->{parseInfo} : $modHash->{parseInfo});
    #Log3 $name, 5, "$name: ObjInfo called from " . Modbus_Caller() . " for $key, object $oName" . 
    #   ($defName ? ", defName $defName" : "") . ($lastDefault ? ", lastDefault $lastDefault" : "");
        
    my $reading = Modbus_ObjAttr($hash, $key, 'reading');
    if (!defined($reading) && $parseInfo->{$key} && $parseInfo->{$key}{reading}) {
        $reading = $parseInfo->{$key}{reading};
    }
    if (!defined($reading)) {
        #Log3 $name, 5, "$name: ObjInfo could not find a reading name";
        return (defined($lastDefault) ? $lastDefault : "");
    }
    
    #Log3 $name, 5, "$name: ObjInfo now looks at attrs for oName $oName / reading $reading / $key";
    if (defined($attr{$name})) {
        # check for explicit attribute for this object
        my $value = Modbus_ObjAttr($hash, $key, $oName);
        return $value if (defined($value));
        
        # check for special case: attribute can be name of reading with prefix like poll-reading
        return $attr{$name}{$oName."-".$reading} 
            if (defined($attr{$name}{$oName."-".$reading}));
    }
    
    # parseInfo for object $oName if special Fhem module using parseinfoHash
    return $parseInfo->{$key}{$oName}
        if (defined($parseInfo->{$key}) && defined($parseInfo->{$key}{$oName}));
    
    # check for type entry / attr ...
    if ($oName ne "type") {
        #Log3 $name, 5, "$name: ObjInfo checking types";
        my $dType = Modbus_ObjInfo($hash, $key, 'type', '', '***NoTypeInfo***');
        if ($dType ne '***NoTypeInfo***') {
            #Log3 $name, 5, "$name: ObjInfo for $key and $oName found type $dType";
            my $typeSpec = Modbus_DevInfo($hash, "type-$dType", $oName, '***NoTypeInfo***');
            if ($typeSpec ne '***NoTypeInfo***') {
                #Log3 $name, 5, "$name: ObjInfo $dType specifies $typeSpec for $oName";
                return $typeSpec;
            }
        }
        #Log3 $name, 5, "$name: ObjInfo no type";
    }
    # default for object type in deviceInfo / in attributes for device / type
    if ($defName) {
        #Log3 $name, 5, "$name: ObjInfo checking defaults Information defname=$defName";
        my $type = substr($key, 0, 1);
        if (defined($attr{$name})) {
            # check for explicit attribute for this object type
            my $daName    = "dev-".$type."-".$defName;
            #Log3 $name, 5, "$name: ObjInfo checking $daName";
            return $attr{$name}{$daName} 
                if (defined($attr{$name}{$daName}));
            
            # check for default attribute for all object types
            my $dadName   = "dev-".$defName;
            #Log3 $name, 5, "$name: ObjInfo checking $dadName";
            return $attr{$name}{$dadName} 
                if (defined($attr{$name}{$dadName}));
        }
        my $devInfo = ($hash->{deviceInfo} ? $hash->{deviceInfo} : $modHash->{deviceInfo});
        return $devInfo->{$type}{$defName}
            if (defined($devInfo->{$type}) && defined($devInfo->{$type}{$defName}));
    }
    return (defined($lastDefault) ? $lastDefault : "");
}


################################################
# Get Type Info from Attributes,
# or deviceInfo Hash
sub Modbus_DevInfo($$$;$) {
    my ($hash, $type, $oName, $lastDefault) = @_;
    #   Device h      read
    $hash = $hash->{CHILDOF} if ($hash->{CHILDOF});                     # take info from parent device if TCP server conn
    my $name    = $hash->{NAME};
    my $modHash = $modules{$hash->{TYPE}};
    my $devInfo = ($hash->{deviceInfo} ? $hash->{deviceInfo} : $modHash->{deviceInfo});
    my $aName   = "dev-".$type."-".$oName;
    my $adName  = "dev-".$oName;
    
    if (defined($attr{$name})) {
        # explicit attribute for this object type
        return $attr{$name}{$aName} 
            if (defined($attr{$name}{$aName}));
        
        # default attribute for all object types
        return $attr{$name}{$adName} 
            if (defined($attr{$name}{$adName}));
    }
    # default for object type in deviceInfo
    return $devInfo->{$type}{$oName}
        if (defined($devInfo->{$type}) && defined($devInfo->{$type}{$oName}));

    return (defined($lastDefault) ? $lastDefault : "");
}


##################################################
# Get Type/Adr for a reading name from Attributes,
# or parseInfo Hash
# called from get and set to get objCombi for name
sub Modbus_ObjKey($$) {
    my ($hash, $reading) = @_;
    return undef if ($reading eq '?');
    $hash = $hash->{CHILDOF} if ($hash->{CHILDOF});                     # take info from parent device if TCP server conn   
    my $name      = $hash->{NAME};
    my $modHash   = $modules{$hash->{TYPE}};    
    my $parseInfo = ($hash->{parseInfo} ? $hash->{parseInfo} : $modHash->{parseInfo});
    
    foreach my $a (keys %{$attr{$name}}) {
        if ($a =~ /obj-([cdih][0-9]+)-reading/ && $attr{$name}{$a} eq $reading) {
            return $1;
        }
    }
    foreach my $k (keys %{$parseInfo}) {
        return $k if ($parseInfo->{$k}{reading} && ($parseInfo->{$k}{reading} eq $reading));
    }
    return "";
}


sub Modbus_CheckEval($\@$$) {
    my ($hash, $valRef, $expr, $eName) = @_;
    my $name = $hash->{NAME};
    my $inCheckEval = 1;
    my @val = @{$valRef};
    my $val = $val[0];
    my $context = Modbus_Caller();
    my $desc = "$eName, val=@val, expr=$expr";
    my $result;
    my $oldSig = ($SIG{__WARN__} ? $SIG{__WARN__} : 'DEFAULT');
    Log3 $name, 5, "$name: CheckEval for $context evaluates $desc";
    $SIG{__WARN__} = sub { 
        Log3 $name, 3, "$name: CheckEval for $context warning evaluating $desc: @_"; 
    };
    $result = eval($expr);
    $SIG{__WARN__} = $oldSig;
    if ($@) {
        Log3 $name, 3, "$name: CheckEval for $context error evaluating $eName, val=$val, expr=$expr: $@";
    } else {
        Log3 $name, 5, "$name: CheckEval for $context result is $result";
    }               
    return $result;
}


# Try to call a user defined function if defined
#################################################
sub Modbus_TryCall($$$$)
{
    my ($hash, $fName, $reading, $val) = @_;
    my $name = $hash->{NAME};
    my $modHash = $modules{$hash->{TYPE}};
    if ($modHash->{$fName}) {
        my $func = $modHash->{$fName};
        Log3 $name, 5, "$name: " . Modbus_Caller() . " is calling $fName via TrCall for reading $reading and val $val";
        no strict "refs";     
        my $ret = eval { &{$func}($hash,$reading,$val) };
        if( $@ ) {         
            Log3 $name, 3, "$name: " . Modbus_Caller() . " error calling $fName: $@";
            return;
        }                   
        use strict "refs";
        return $ret
    }
    return;
}



#####################################
sub Modbus_Statistics($$$)
{
    my ($hash, $key, $value) = @_;
    my $name = $hash->{NAME};

    my $pInterval = AttrVal($name, "profileInterval", 0);  
    return if (!$pInterval);

    my $now = gettimeofday();
    my $pPeriod = int($now / $pInterval);

    if (!defined ($hash->{statistics}{lastPeriod}) || ($pPeriod != $hash->{statistics}{lastPeriod})) {
        readingsBeginUpdate($hash);
        foreach my $k (keys %{$hash->{statistics}{sums}}) {
            readingsBulkUpdate($hash, "Statistics_" . $k, $hash->{statistics}{sums}{$k});
            $hash->{statistics}{sums}{$k} = 0;
        }
        readingsEndUpdate($hash, 1);
        $hash->{statistics}{sums}{$key} = $value;
        $hash->{statistics}{lastPeriod} = $pPeriod;
    } else {
        if ($hash->{statistics}{sums}{$key}) {
            $hash->{statistics}{sums}{$key} += $value;
        } else {
            $hash->{statistics}{sums}{$key} = $value;
        }
    }
    return;
}


#####################################
sub Modbus_Profiler($$)
{
    my ($hash, $key) = @_;
    return if (!$hash);
    my $name = $hash->{NAME};
    
    my $pInterval = AttrVal($name, "profileInterval", 0);  
    return if (!$pInterval);
    
    my $now = gettimeofday();
    my $pPeriod = int($now / $pInterval);
    #my $micros = $now - (int ($now));
    #my ($seconds, $minute, $hour, @rest) = localtime ($now);
    
    # erster Aufruf? dann lastKey setzen und Startzeit merken, lastPeriod setzen
    if (!defined ($hash->{profiler}{lastKey})) {
        $hash->{profiler}{lastKey}     = $key;
        $hash->{profiler}{lastPeriod}  = $pPeriod;
        $hash->{profiler}{start}{$key} = $now;
        $hash->{profiler}{sums}{$key}  = 0 ;
        Log3 $name, 5, "$name: Profiling $key initialized, start $now";
        return;
    } 

    # merke letzten Key - für diesen ist bisher die Zeit vergangen
    my $lKey  = $hash->{profiler}{lastKey};
    
    # für den letzten Key: Diff seit Start
    my $lDiff = ($now - $hash->{profiler}{start}{$lKey});
    $lDiff    = 0 if (!$hash->{profiler}{start}{$lKey});
    
    # für den neuen Key: wenn noch kein start, dann startet die Messung jetzt
    if (!$hash->{profiler}{start}{$key}) {
        $hash->{profiler}{start}{$key} = $now;
    }
    
    Log3 $name, 5, "$name: Profiling $key, before $lKey, now is $now, $key started at " 
        . $hash->{profiler}{start}{$key} . ", $lKey started at " . $hash->{profiler}{start}{$lKey};
    
    # neue Minute
    if ($pPeriod != $hash->{profiler}{lastPeriod}) {
        my $overP = $now - ($pPeriod * $pInterval);     # time over the pPeriod start
        $overP = 0 if ($overP > $lDiff);    # if interval was modified things get inconsistant ...
        Log3 $name, 5, "$name: Profiling pPeriod changed, last pPeriod was " . $hash->{profiler}{lastPeriod} . 
                    " now $pPeriod, total diff for $lKey is $lDiff,  over $overP over the pPeriod";     
        Log3 $name, 5, "$name: Profiling add " . ($lDiff - $overP) . " to sum for $key";
        $hash->{profiler}{sums}{$lKey} += ($lDiff - $overP);
        
        readingsBeginUpdate($hash);
        foreach my $k (keys %{$hash->{profiler}{sums}}) {
            my $val = sprintf("%.2f", $hash->{profiler}{sums}{$k});
            Log3 $name, 5, "$name: Profiling set reading for $k to $val";
            readingsBulkUpdate($hash, "Profiler_" . $k . "_sum", $val);
            $hash->{profiler}{sums}{$k} = 0;
            $hash->{profiler}{start}{$k} = 0;
        }
        readingsEndUpdate($hash, 0);
        
        $hash->{profiler}{start}{$key} = $now;
        
        Log3 $name, 5, "$name: Profiling set new sum for $lKey to $overP";
        $hash->{profiler}{sums}{$lKey} = $overP;
        $hash->{profiler}{lastPeriod}  = $pPeriod;
        $hash->{profiler}{lastKey}     = $key;
    } else {
        if ($key eq $hash->{profiler}{lastKey}) {
            # nothing new - take time when key or pPeriod changes
            return;
        }
        Log3 $name, 5, "$name: Profiling add $lDiff to sum for $lKey " .
            "(now is $now, start for $lKey was $hash->{profiler}{start}{$lKey})";
        $hash->{profiler}{sums}{$lKey} += $lDiff;
        $hash->{profiler}{start}{$key} = $now;
        $hash->{profiler}{lastKey}     = $key;
    }
    return;
}


###########################################################
# return the name of the caling function for debug output
sub Modbus_Caller() 
{
    my ($package, $filename, $line, $subroutine, $hasargs, $wantarray, $evaltext, $is_require, $hints, $bitmask, $hinthash) = caller 2;
    return $1 if ($subroutine =~ /main::Modbus_(.*)/);
    return $1 if ($subroutine =~ /main::ModbusLD_(.*)/);
    return $1 if ($subroutine =~ /main::(.*)/);

    return "$subroutine";
}



# Try to convert a value with a map 
# called from Set and FormatReading
#########################################
sub Modbus_MapConvert($$$;$)
{
    my ($hash, $map, $val, $reverse) = @_;
    my $name = $hash->{NAME};
    
    $map =~ s/\s+/ /g;                                          # substitute all \t \n etc. by one space only       

    if ($reverse) {
        $map =~ s/([^, ][^,\$]*):([^,][^,\$]*),? */$2:$1, /g;   # reverse map
    }
    # spaces in words allowed, separator is ',' or ':'
    $val = decode ('UTF-8', $val);                              # convert nbsp from fhemweb
    $val =~ s/\s|&nbsp;/ /g;                                    # back to normal spaces in case it came from FhemWeb with coded Blank

    my %mapHash = split (/, *|:/, $map);                        # reverse hash aus dem reverse string                   

    if (defined($mapHash{$val})) {                              # Eintrag für den übergebenen Wert in der Map?
        my $newVal = $mapHash{$val};                            # entsprechender Raw-Wert für das Gerät
        Log3 $name, 5, "$name: MapConvert called from " . Modbus_Caller() . " converted $val to $newVal with" .
        ($reverse ? " reversed" : "") . " map $map";
        return $newVal;
    } else {
        Log3 $name, 4, "$name: MapConvert called from " . Modbus_Caller() . " did not find $val in" . 
        ($reverse ? " reversed" : "") . " map $map";
        return undef;
    }
}


# called from UpdateHintList
#########################################
sub Modbus_MapToHint($)
{
    my ($map) = @_;
    my $hint = $map;                                                # create hint from map
    $hint =~ s/\s+/&nbsp;/g;                                        # convert spaces for fhemweb
    $hint =~ s/([^,\$]+):([^,\$]+)(,?) */$2$3/g;                    # allow spaces in names
    return $hint;
}



1;

=pod
=item device
=item summary base module for devices with Modbus Interface
=item summary_DE Basismodul für Geräte mit Modbus-Interface
=begin html

<a name="Modbus"></a>
<h3>Modbus</h3>
<ul>
    Modbus defines a physical modbus interface and functions to be called from other logical modules / devices.
    This low level module takes care of the communication with modbus devices and provides Get, Set and cyclic polling 
    of Readings as well as formatting and input validation functions.
    The logical device modules for individual machines only need to define the supported modbus function codes and objects of the machine with the modbus interface in data structures. These data structures are then used by this low level module to implement Set, Get and automatic updateing of readings in a given interval.
    <br>
    This version of the Modbus module supports Modbus RTU and ASCII over serial / RS485 lines as well as Modbus TCP and Modbus RTU or RTU over TCP.
    It defines read / write functions for Modbus holding registers, input registers, coils and discrete inputs.
    <br><br>
    
    <b>Prerequisites</b>
    <ul>
        <li>
          This module requires the Device::SerialPort or Win32::SerialPort module.
        </li>
    </ul>
    <br>

    <a name="ModbusDefine"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; Modbus &lt;device&gt; </code>
        <br><br>
        A define of a physical device based on this module is only necessary if a shared physical device like a RS485 USB adapter is used. In the case of Modbus TCP this module will be used as a library for other modules that define all the data objects and no define of the base module is needed.
        <br>
        Example:<br>
        <br>
        <ul><code>define ModBusLine Modbus /dev/ttyUSB1@9600</code></ul>
        <br>
        In this example the module opens the given serial interface and other logical modules can access several Modbus devices connected to this bus concurrently.
        If your device needs special communications parameters like even parity you can add the number of data bits, the parity and the number of stopbits separated by commas after the baudrate e.g.:
        <br>
        <ul><code>define ModBusLine Modbus /dev/ttyUSB2@38400,8,E,2</code></ul>
        <br>
    </ul>
    <br>

    <a name="ModbusSet"></a>
    <b>Set-Commands</b><br>
    <ul>
        this low level device module doesn't provide set commands for itself but implements set 
        for logical device modules that make use of this module. See ModbusAttr for example.
    </ul>
    <br>
    <a name="ModbusGet"></a>
    <b>Get-Commands</b><br>
    <ul>
        this low level device module doesn't provide get commands for itself but implements get 
        for logical device modules that make use of this module.
    </ul>
    <br>
    <a name="ModbusAttr"></a>
    <b>Attributes</b><br><br>
    <ul>
        <li><a href="#do_not_notify">do_not_notify</a></li>
        <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
        <br>
        <li><b>queueMax</b></li> 
            max length of the queue used for sending requests, defaults to 200.
        <li><b>queueDelay</b></li> 
            modify the delay used when sending requests to the device from the internal queue, defaults to 1 second
        <li><b>queueTimeout</b></li> 
            modify the timeout used to remove old entries in the send queue for requests. By default entries that cound not be sent for more than 20 seconds will be deleted from the queue
        <li><b>enableQueueLengthReading</b></li> 
            if set to 1 the physical device will create a reading with the length of the queue ued internally to send requests.<br>
            
        <li><b>busDelay</b></li> 
            defines a delay that is always enforced between the last read from the bus and the next send to the bus for all connected devices
        <li><b>clientSwitchDelay</b></li> 
            defines a delay that is always enforced between the last read from the bus and the next send to the bus for all connected devices but only if the next send goes to a different device than the last one
        <li><b>dropQueueDoubles</b></li> 
            prevents new request to be queued if the same request is already in the send queue
        <li><b>retriesAfterTimeout</b></li> 
            tbd.    
            
        <li><b>skipGarbage</b></li> 
            if set to 1 this attribute will enhance the way the module treats Modbus response frames (RTU over serial lines) that look as if they have a wrong Modbus id as their first byte. If skipGarbage is set to 1 then the module will skip all bytes until a byte with the expected modbus id is seen. Under normal circumstances this behavior should not do any harm and lead to more robustness. However since it changes the original behavior of this module it has to be turned on explicitely.<br>
            For Modbus ASCII it skips bytes until the expected starting byte ":" is seen.
        <li><b>profileInterval</b></li> 
            if set to something non zero it is the time period in seconds for which the module will create bus usage statistics. 
            Please note that this number should be at least twice as big as the interval used for requesting values in logical devices that use this physical device<br>
            The bus usage statistics create the following readings:
            <ul>
                <li><b>Profiler_Delay_sum</b></li>
                    seconds used as delays to implement the defined sendDelay and commDelay
                <li><b>Profiler_Fhem_sum</b></li>
                    seconds spend processing in the module
                <li><b>Profiler_Idle_sum</b></li>
                    idle time 
                <li><b>Profiler_Read_sum</b></li>
                    seconds spent reading and validating the data read
                <li><b>Profiler_Send_sum</b></li>
                    seconds spent preparing and sending data
                <li><b>Profiler_Wait_sum</b></li>
                    seconds waiting for a response to a request
                <li><b>Statistics_Requests</b></li>
                    number of requests sent
                <li><b>Statistics_Timeouts</b></li>
                    timeouts encountered
            </ul>
    </ul>
    <br>
</ul>

=end html
=cut


