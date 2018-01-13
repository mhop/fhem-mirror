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
#   2016-12-21  fixed $ret in OpenDev
#   2016-12-27  check for undefined $val in ParseObj and Log with timeoutLogLevel
#   2016-12-28  removed RAWBUFFER and added some initiualisation for $ioHash->{helper}{buffer}, fixed logging for timeouts
#   2017-01-02  new attribute allowShortResponses 
#
#   2017-01-06  removed misleading log "destination device" at define when IODev Attr is not knon yet.
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
#   2017-12-06  little fixes
#   2017-12-22  remember timeout time in $hash instead of reading it from intAt
#	2018-01-11	fix bug where defptr pointed to ioHash instead of logical hash when seting IODev Attr
#
#   ToDo / Ideas : 
#                   get reading key (type / adr)
#                   filterEcho (wie in private post im Forum vorgeschlagen)
#                   set saveAsModule to save attr definitions as module
#                   define data types VT_R4 -> revregs, len2, unpack f> ...
#                   async output for scan? table? with revregs etc.?
#                   get object-interpretations h123 -> Alle Variationen mit revregs und bswap und unpacks ...
#                   nonblocking disable attr für xp
#
#                   attr with a lits of set commands / requests to launch when polling (Helios support)
#
#                   passive listening to other modbus traffic (state machine, parse requests of others in special queue
#
#                   set definition with multiple requests as raw containig opt. readings / input
#                   map mit spaces wie bei HTTPMOD
#                   :noArg etc. für Hintlist und userattr wie in HTTPMOD optimieren
#
#                   Autoconfigure? (Combine testweise erhöhen, Fingerprinting -> DB?, ...?)
#                   Modbus Slave? separate module? 
#                   Modbus GW feature to translate TCP requests to serial RTU / ASCII requests in Fhem
#
#

package main;

use strict;
use warnings;

# return time as float, not just full seconds
use Time::HiRes qw( gettimeofday tv_interval);

use POSIX qw(strftime);
use Encode qw(decode encode);

sub Modbus_Initialize($);
sub Modbus_Define($$);
sub Modbus_Undef($$);
sub Modbus_Read($);
sub Modbus_Ready($);
sub Modbus_ParseObj($$$;$$);
sub Modbus_ParseFrames($);
sub Modbus_HandleSendQueue($;$);
sub Modbus_TimeoutSend($);
sub Modbus_CRC($);
sub ModbusLD_ObjInfo($$$;$$);

# functions to be used from logical modules
sub ModbusLD_ExpandParseInfo($);
sub ModbusLD_Initialize($);
sub ModbusLD_Define($$);
sub ModbusLD_Undef($$);
sub ModbusLD_Get($@);
sub ModbusLD_Set($@);
sub ModbusLD_ReadAnswer($;$);
sub ModbusLD_GetUpdate($);
sub ModbusLD_GetIOHash($);
sub ModbusLD_Send($$$;$$$);

my $Modbus_Version = '3.7.3 - 22.12.2017';
my $Modbus_PhysAttrs = 
        "queueDelay " .
        "busDelay " .
        "clientSwitchDelay " .
        "dropQueueDoubles:0,1 " .
        "profileInterval " .
        "openTimeout " .
        "nextOpenDelay " .
        "maxTimeoutsToReconnect " .             # for Modbus over TCP/IP only        
        "skipGarbage:0,1 " .
        "timeoutLogLevel:3,4 " .
        "silentReconnect:0,1 ";

my $Modbus_LogAttrs = 
        "queueMax " .
        "IODev " .                              # fhem.pl macht dann $hash->{IODev} = $defs{$ioname}
        "alignTime " .
        "enableControlSet:0,1 " .
        "nonPrioritizedSet:0,1 " .
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
# Define für das physische serielle Basismodul
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
        if(@a < 1);

    DevIo_CloseDev($ioHash);
    $ioHash->{BUSY} = 0;
    $ioHash->{helper}{buffer} = "";       # clear Buffer for reception
    
    if(!$dev || $dev eq "none") {
        Log 1, "$name: device is none, commands will be echoed only";
        return undef;
    }
    $ioHash->{DeviceName} = $dev;           # needed by DevIo to get Device, Port, Speed etc.    
    $ioHash->{TIMEOUT}    = AttrVal($name, "openTimeout", 3);
    #DevIo_OpenDev($ioHash, 0, 0);          # will be opened later in NotifyFN
    delete $ioHash->{TIMEOUT};
    return;
    
}


#####################################
# delete physical Device    # todo: check other callback functions (undef, delete, shutdown)
sub Modbus_Undef($$)
{
    my ($ioHash, $arg) = @_;
    my $name = $ioHash->{NAME};
    DevIo_CloseDev($ioHash); 
    RemoveInternalTimer ("timeout:$name");
    RemoveInternalTimer ("queue:$name");
    delete $ioHash->{nextTimeout};
    # lösche auch die Verweise aus logischen Modulen auf dieses physische.
    foreach my $d (values %{$ioHash->{defptr}}) {
        Log3 $name, 3, "$name: Undef is removing IO device for $d->{NAME}";
        delete $d->{IODev};
        RemoveInternalTimer ("update:$d->{NAME}");
    }
    return;
}


########################################################
# Notify for INITIALIZED -> Open defined logical device
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
# auf das Gerät, obwohl die NotifyFn nicht mehr regisrtiert ist ...
#
#
sub Modbus_Notify($$)           # both for physical and logical devices
{
    my ($hash, $source) = @_;
    my $name  = $hash->{NAME};              # my Name
    my $sName = $source->{NAME};            # Name of Device that created the events
    return if($sName ne "global");          # only interested in global Events

    my $events = deviceEvents($source, 1);
    return if(!$events);                    # no events
    
    # Log3 $name, 5, "$name: Notify called for source $source->{NAME} with events: @{$events}";
    return if (!grep(m/^INITIALIZED|REREADCFG|(MODIFIED $name)$/, @{$events}));

    if (IsDisabled($name)) {
        Log3 $name, 3, "$name: Notify / Init: device is disabled";
        return;
    }   
    if ($hash->{TYPE} eq "Modbus" || $hash->{DEST}) {   # physical device or Modbus TCP -> open connection
        Log3 $name, 3, "$name: Notify / Init: opening connection";
        Modbus_Open($hash);
    } else {                                            # logical device and not Modbus TCP -> check for IO Device
        my $ioHash = ModbusLD_GetIOHash($hash);
        my $ioName = $ioHash->{NAME};    
        if ($ioName) {
            Log3 $name, 3, "$name: Notify / Init: using $ioName for communication";
        } else {
            Log3 $name, 3, "$name: Notify / Init: no IODev for communication";
        }
    }   
    if ($hash->{TYPE} ne "Modbus") {        
        ModbusLD_SetTimer($hash, 1);     # logical device -> first Update in 1 second or aligned if interval is defined
    }
    return;
}


################################################
# Get Object Info from Attributes,
# parseInfo Hash or default from deviceInfo Hash
sub ModbusLD_ObjInfo($$$;$$) {
    my ($hash, $key, $oName, $defName, $lastDefault) = @_;
    #   Device  h123  unpack  defUnpack
    my $name      = $hash->{NAME};
    my $modHash   = $modules{$hash->{TYPE}};
    my $parseInfo = $modHash->{parseInfo};
    
    my $reading = ($parseInfo->{$key} && $parseInfo->{$key}{reading} ?
        $parseInfo->{$key}{reading} : "");
    $reading = AttrVal($name, "obj-".$key."-reading", $reading);
    return (defined($lastDefault) ? $lastDefault : "") if (!$reading);

    if (defined($attr{$name})) {
        
        # check for explicit attribute for this object
        my $aName = "obj-".$key."-".$oName;
        return $attr{$name}{$aName} 
            if (defined($attr{$name}{$aName}));
    
        if ($hash->{LeadingZeros}) {
            # attr for object with leading zeros in address detected
            if ($key =~ /([cdih])0*([0-9]+)/) {
                my $type = $1;
                my $adr  = $2;
                while (length($adr) <= 5) {
                    $aName = "obj-".$type.$adr."-".$oName;
                    Log3 $name, 5, "$name: Check $aName";
                    return $attr{$name}{$aName} 
                        if (defined($attr{$name}{$aName}));
                    $adr = '0' . $adr;
                }
            }
        }
        
        # check for special case: attribute can be name of reading with prefix like poll-reading
        return $attr{$name}{$oName."-".$reading} 
            if (defined($attr{$name}{$oName."-".$reading}));
    }
    
    # parseInfo for object $oName if special Fhem module using parseinfoHash
    return $parseInfo->{$key}{$oName}
        if (defined($parseInfo->{$key}) && defined($parseInfo->{$key}{$oName}));
    
    # check for type entry / attr ...
    if ($oName ne "type") {
        my $dType = ModbusLD_ObjInfo($hash, $key, 'type', 'noDefaultDevAttrForType', '***NoTypeInfo***');
        if ($dType ne '***NoTypeInfo***') {
            #Log3 $name, 5, "$name: ObjInfo for $key and $oName found type $dType";
            my $typeSpec = ModbusLD_DevInfo($hash, "type-$dType", $oName, '***NoTypeInfo***');
            if ($typeSpec ne '***NoTypeInfo***') {
                #Log3 $name, 5, "$name: $dType specifies $typeSpec for $oName";
                return $typeSpec;
            }
        }
    }
    
    # default for object type in deviceInfo / in attributes for device / type
    if ($defName) {
        my $type = substr($key, 0, 1);
        if (defined($attr{$name})) {
            # check for explicit attribute for this object type
            my $daName    = "dev-".$type."-".$defName;
            return $attr{$name}{$daName} 
                if (defined($attr{$name}{$daName}));
            
            # check for default attribute for all object types
            my $dadName   = "dev-".$defName;
            return $attr{$name}{$dadName} 
                if (defined($attr{$name}{$dadName}));
        }
        my $devInfo = $modHash->{deviceInfo};
        return $devInfo->{$type}{$defName}
            if (defined($devInfo->{$type}) && defined($devInfo->{$type}{$defName}));
    }
    return (defined($lastDefault) ? $lastDefault : "");
}


################################################
# Get Type Info from Attributes,
# or deviceInfo Hash
sub ModbusLD_DevInfo($$$;$) {
    my ($hash, $type, $oName, $lastDefault) = @_;
    #   Device h      read
    
    my $name      = $hash->{NAME};
    my $modHash   = $modules{$hash->{TYPE}};
    my $devInfo   = $modHash->{deviceInfo};
    my $aName     = "dev-".$type."-".$oName;
    my $adName    = "dev-".$oName;
    
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
sub ModbusLD_ObjKey($$) {
    my ($hash, $reading) = @_;
    my $name      = $hash->{NAME};
    my $modHash   = $modules{$hash->{TYPE}};
    my $parseInfo = $modHash->{parseInfo};

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


sub Modbus_CheckEval($$$$$) {
    my ($hash, $val, $expr, $context, $eName) = @_;
    # context e.g. "ParseObj", eName e.g. "ignoreExpr for $reading"
    my $name = $hash->{NAME};
    my $result;
    my $inCheckEval = 1;
    my $oldSig = ($SIG{__WARN__} ? $SIG{__WARN__} : 'DEFAULT');
    Log3 $name, 5, "$name: $context evaluates $eName, val=$val, expr $expr";
    $SIG{__WARN__} = sub { Log3 $name, 3, "$name: $context warning evaluating $eName, val=$val, expr $expr: @_"; };
    $result = eval($expr);
    $SIG{__WARN__} = $oldSig;
    if ($@) {
        Log3 $name, 3, "$name: $context error evaluating $eName, val=$val, expr=$expr: $@";
    } else {
        Log3 $name, 5, "$name: $context eval result is $result";
    }               
    return $result;
}


#################################################
# Parse holding / input register / coil Data
# only called from parseframes 
#      which is only called from read / readanswer
#
# with logical device hash, data string
# and the object type/adr to start with
sub Modbus_ParseObj($$$;$$) {
    my ($logHash, $data, $objCombi, $quantity, $op) = @_;
    my $name      = $logHash->{NAME};
    my $type      = substr($objCombi, 0, 1);
    my $startAdr  = substr($objCombi, 1);
    my $lastAdr   = ($quantity ? $startAdr + $quantity -1 : 0);
    my ($unpack, $format, $expr, $ignExpr, $map, $rest, $len, $encode, $decode);
    Log3 $name, 5, "$name: ParseObj called with " . unpack ("H*", $data) . " and start $startAdr" .  ($quantity ? ", quantity $quantity" : "") .  ($op ? ", op $op" : "");;

    if ($type =~ "[cd]") {
        # quantity is only used for coils / discrete inputs
        $quantity = 1 if (!$quantity);
        $rest = unpack ("b$quantity", $data);   # convert binary data to bit string
        Log3 $name, 5, "$name: ParseObj shortened bit string: " . $rest . " and start adr $startAdr, quantity $quantity";
    } else {
        $rest = $data;
    }
    use bytes;
    readingsBeginUpdate($logHash);
    while (length($rest) > 0) {
        # einzelne Felder verarbeiten
        my $key       = $type . $startAdr;
        my $reading   = ModbusLD_ObjInfo($logHash, $key, "reading");  # "" if nothing specified
        
        if ($op =~ /scanid([0-9]+)/) {      # scanning for Modbus ID
            $reading = "scanId-" . $1 . "-Response-$key";
            $logHash->{MODBUSID} = $1;
            Log3 $name, 3, "$name: ScanIds got reply from Id $1 - set internal MODBUSID to $1";
        } elsif ($op eq 'scanobj') {        # scan Modbus objects
            if (!$reading) {
                my $fKey = $type . sprintf ("%06d", $startAdr);
                $reading   = "scan-$fKey";
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
        if ($reading) {
            if ($type =~ "[cd]") {
                $unpack    = "a";       # for coils just take the next 0/1 from the string
                $len       = 1;         # one byte contains one bit from the 01001100 string unpacked above
            } else {
                $unpack     = ModbusLD_ObjInfo($logHash, $key, "unpack", "defUnpack", "n");  
                $len        = ModbusLD_ObjInfo($logHash, $key, "len", "defLen", 1);          # default to 1 Reg / 2 Bytes
                $encode     = ModbusLD_ObjInfo($logHash, $key, "encode", "defEncode");       # character encoding 
                $decode     = ModbusLD_ObjInfo($logHash, $key, "decode", "defDecode");       # character decoding 
                my $revRegs = ModbusLD_ObjInfo($logHash, $key, "revRegs", "defRevRegs");     # do not reverse register order by default
                my $swpRegs = ModbusLD_ObjInfo($logHash, $key, "bswapRegs", "defBswapRegs"); # dont reverse bytes in registers by default
                
                $rest = Modbus_RevRegs($logHash, $rest, $len) if ($revRegs && $len > 1);
                $rest = Modbus_SwpRegs($logHash, $rest, $len) if ($swpRegs);
            };
            $format  = ModbusLD_ObjInfo($logHash, $key, "format", "defFormat");          # no format if nothing specified
            $expr    = ModbusLD_ObjInfo($logHash, $key, "expr", "defExpr");
            $ignExpr = ModbusLD_ObjInfo($logHash, $key, "ignoreExpr", "defIgnoreExpr");
            $map     = ModbusLD_ObjInfo($logHash, $key, "map", "defMap");                # no map if not specified
            Log3 $name, 5, "$name: ParseObj ObjInfo for $key: reading=$reading, unpack=$unpack, expr=$expr, format=$format, map=$map";
            
            my $val = unpack ($unpack, $rest);      # verarbeite so viele register wie passend (ggf. über mehrere Register)
            
            if (!defined($val)) {
                my $logLvl = AttrVal($name, "timeoutLogLevel", 3);
                Log3 $name, $logLvl, "$name: ParseObj unpack of " . unpack ('H*', $rest) . " with $unpack for $reading resulted in undefined value";
            } else {
                Log3 $name, 5, "$name: ParseObj unpacked " . unpack ('H*', $rest) . 
                    " with $unpack to hex " . unpack ('H*', $val) .
                    ($val =~ /[[:print:]]/ ? " ($val)" : "");       # check for printable characters
      
                $val = decode($decode, $val) if ($decode);
                $val = encode($encode, $val) if ($encode);
                
                # Exp zur Ignorieren der Werte?
                my $ignore;
                $ignore = Modbus_CheckEval($logHash, $val, $ignExpr, "ParseObj", "ignoreExpr for $reading") if ($ignExpr);

                # Exp zur Nachbearbeitung der Werte?
                $val = Modbus_CheckEval($logHash, $val, $expr, "ParseObj", "expr for $reading") if ($expr);

                # Map zur Nachbereitung der Werte?
                if ($map) {
                    my %map = split (/[,: ]+/, $map);
                    Log3 $name, 5, "$name: ParseObj for $reading maps value to $val with " . $map;
                    $val = $map{$val} if ($map{$val});
                }
                # Format angegeben?
                if ($format) {
                    Log3 $name, 5, "$name: ParseObj for $reading does sprintf with format " . $format .
                        " value is $val";
                    $val = sprintf($format, $val);
                    Log3 $name, 5, "$name: ParseObj for $reading sprintf result is $val";
                }
                if ($ignore) {
                    Log3 $name, 4, "$name: ParseObj for $reading ignores $val because of ignoreExpr. Reading not updated";
                } else {
                    Log3 $name, 4, "$name: ParseObj for $reading assigns $val";
                    readingsBulkUpdate($logHash, $reading, $val);
                    $logHash->{gotReadings}{$reading} = $val;
                    $logHash->{lastRead}{$key}        = gettimeofday();
                }
            }
        } else {
            Log3 $name, 5, "$name: ParseObj has no information about parsing $key";
            $len = 1;
        }
        
        # gehe zum nächsten Wert
        if ($type =~ "[cd]") {
            $startAdr++;
            if (length($rest) > 1) {
                $rest = substr($rest, 1);
            } else {
                $rest = "";
            }
            last if ($lastAdr && $startAdr > $lastAdr);
        } else {
            $startAdr += $len;            
            if (length($rest) > ($len*2)) {
                $rest = substr($rest, $len * 2);    # take rest of rest starting at len*2 until the end  
            } else {
                $rest = "";
            }
        }
        Log3 $name, 5, "$name: ParseObj moves to next object, skip $len to $type$startAdr" if ($rest);
    }
    readingsEndUpdate($logHash, 1);
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
        Log3 $name, 5, "$name: Profiling: $key initialized, start $now";
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
    
    Log3 $name, 5, "$name: Profiling: $key, before $lKey, now is $now, $key started at " 
        . $hash->{profiler}{start}{$key} . ", $lKey started at " . $hash->{profiler}{start}{$lKey};
    
    # neue Minute
    if ($pPeriod != $hash->{profiler}{lastPeriod}) {
        my $overP = $now - ($pPeriod * $pInterval);     # time over the pPeriod start
        $overP = 0 if ($overP > $lDiff);    # if interval was modified things get inconsistant ...
        Log3 $name, 5, "$name: Profiling: pPeriod changed, last pPeriod was " . $hash->{profiler}{lastPeriod} . 
                    " now $pPeriod, total diff for $lKey is $lDiff,  over $overP over the pPeriod";     
        Log3 $name, 5, "$name: Profiling: add " . ($lDiff - $overP) . " to sum for $key";
        $hash->{profiler}{sums}{$lKey} += ($lDiff - $overP);
        
        readingsBeginUpdate($hash);
        foreach my $k (keys %{$hash->{profiler}{sums}}) {
            my $val = sprintf("%.2f", $hash->{profiler}{sums}{$k});
            Log3 $name, 5, "$name: Profiling: set reading for $k to $val";
            readingsBulkUpdate($hash, "Profiler_" . $k . "_sum", $val);
            $hash->{profiler}{sums}{$k} = 0;
            $hash->{profiler}{start}{$k} = 0;
        }
        readingsEndUpdate($hash, 0);
        
        $hash->{profiler}{start}{$key} = $now;
        
        Log3 $name, 5, "$name: Profiling: set new sum for $lKey to $overP";
        $hash->{profiler}{sums}{$lKey} = $overP;
        $hash->{profiler}{lastPeriod}  = $pPeriod;
        $hash->{profiler}{lastKey}     = $key;
    } else {
        if ($key eq $hash->{profiler}{lastKey}) {
            # nothing new - take time when key or pPeriod changes
            return;
        }
        Log3 $name, 5, "$name: Profiling: add $lDiff to sum for $lKey " .
            "(now is $now, start for $lKey was $hash->{profiler}{start}{$lKey})";
        $hash->{profiler}{sums}{$lKey} += $lDiff;
        $hash->{profiler}{start}{$key} = $now;
        $hash->{profiler}{lastKey}     = $key;
    }
    return;
}

    
#####################################
# Called from the read and readanswer functions with hash 
# of device that is reading (phys / log depending on TCP / RTU
# $ioHash->{REQUEST} holds request that was last sent
# log hash is taken from last request
# return: "text" is error, 0 is ignore, 1 is finished with success
sub Modbus_ParseFrames($)
{
    my $ioHash  = shift;                        # hash of io device given to function
    
    my $name    = $ioHash->{NAME};              # name of io device
    my $frame   = $ioHash->{helper}{buffer};    # frame is in buffer in io hash
    my $logHash = $ioHash->{REQUEST}{DEVHASH};  # logical device hash is saved in io hash (or points back to self)
    my $type    = $ioHash->{REQUEST}{TYPE};
    my $adr     = $ioHash->{REQUEST}{ADR};
    my $reqLen  = $ioHash->{REQUEST}{LEN};
    my $reqId   = $ioHash->{REQUEST}{MODBUSID};
    my $proto   = $ioHash->{REQUEST}{PROTOCOL};
    my $op      = $ioHash->{REQUEST}{OPERATION};
    my ($null, $dlen, $devAdr, $pdu, $fCode, $data, $eCRC, $CRC);
    my $tid     = 0;
    
    return "got data but did not send a request - ignoring" if (!$ioHash->{REQUEST} || !$proto);
    Log3 $name, 5, "$name: ParseFrames got: " . unpack ('H*', $frame);
    
    use bytes;  
    
    if ($proto eq "RTU") {
        if (AttrVal($name, "skipGarbage", 0)) {
            my $start = index($frame, pack('C', $reqId));
            if ($start) {
                my $skip = substr($frame, 0, $start);
                $frame   = substr($frame, $start);
                Log3 $name, 4, "$name: ParseFrames skipped $start bytes (" . 
                        unpack ('H*', $skip) . " from " .  unpack ('H*', $frame) . ")";
                $ioHash->{helper}{buffer} = $frame;
            }
        }
        if ($frame =~ /(..)(.+)(..)/s) {        # (id fCode) (data) (crc)     /s means treat as single line ...
            ($devAdr, $fCode) = unpack ('CC', $1);
            $data   = $2;
            $eCRC   = unpack ('v', $3);         # Header CRC - thats what we expect to calculate
            $CRC   = Modbus_CRC($1.$2);         # calculated CRC of data
        } else {
            return undef;                       # data still incomplete - continue reading
        }
    } elsif ($proto eq "ASCII") {
        if (AttrVal($name, "skipGarbage", 0)) {
            my $start = index($frame, ':');
            if ($start) {
                my $skip = substr($frame, 0, $start);
                $frame   = substr($frame, $start);
                Log3 $name, 4, "$name: ParseFrames skipped $start bytes ($skip from $frame)";
                $ioHash->{helper}{buffer} = $frame;
            }
        }
        if ($frame =~ /:(..)(..)(.+)(..)\r\n/) {# : (id) (fCode) (data) (lrc) \r\n
            $devAdr = hex($1);
            $fCode  = hex($2);
            $data   = pack('H*', $3);
            $eCRC   = hex($4);                  # Header CRC (LRC)
            $CRC    = Modbus_LRC(pack('C', $devAdr) . pack ('C', $fCode) . $data);  # calculate LRC of data
        } else {
            return undef;                       # data still incomplete - continue reading
        }

    } elsif ($proto eq "TCP") {
        $CRC = 0; $eCRC = 0;                    # for later check for all protocols (not needed for TCP)
        if (length($frame) < 8) {
            Log3 $name, 5, "$name: ParseFrames: length too small: " . length($frame);
            return undef;
        }
        ($tid, $null, $dlen, $devAdr, $pdu) = unpack ('nnnCa*', $frame);
        if ($ioHash->{REQUEST}{TID} != $tid) {
            Log3 $name, 5, "$name: ParseFrames: wrong tid ($tid), dlen=$dlen, id=$devAdr, rest=" . unpack ('H*', $pdu);
            # maybe old response after timeount, maybe rest after wrong frame is the one we're looking for
            $frame = substr($frame, $dlen + 6);     # remove wrong frame
            Log3 $name, 5, "$name: ParseFrames: takes rest after frame: " . unpack ('H*', $frame);
            if (length($frame) < 8) {
                Log3 $name, 5, "$name: ParseFrames: length of rest is too small: " . length($frame);
                return undef;
            }
            ($tid, $null, $dlen, $devAdr, $pdu) = unpack ('nnnCa*', $frame);
            Log3 $name, 5, "$name: ParseFrames: unpacked rest as tid=$tid, dlen=$dlen, id=$devAdr, pdu=" . unpack ('H*', $pdu);
            if ($ioHash->{REQUEST}{TID} != $tid) {
                return ("got wrong tid ($tid)");
            }   
        }         
        if (length($pdu) + 1 < $dlen) {
            Log3 $name, 5, "$name: ParseFrames: Modbus TCP PDU too small (expect $dlen): " . (length($pdu) + 1);
            return undef;
        }
        ($fCode, $data) = unpack ('Ca*', $pdu);            
    } else {
        Log3 $name, 3, "$name: ParseFrames: request structure contains unknown protocol $proto";
    }
    
    Log3 $name, 3, "$name: ParseFrames got a copy of the request sent before - looks like an echo!"
        if ($frame eq $ioHash->{REQUEST}{FRAME} && $fCode < 5);

    return "recieved frame from unexpected Modbus Id $devAdr, " .
            "expecting fc $ioHash->{REQUEST}{FCODE} from $reqId for device $logHash->{NAME}"
        if ($devAdr != $reqId && $reqId != 0);

    return "unexpected function code $fCode from $devAdr, ".
            "expecting fc $ioHash->{REQUEST}{FCODE} from $reqId for device $logHash->{NAME}"
        if ($ioHash->{REQUEST}{FCODE} != $fCode && $fCode < 128);
        
    #
    # frame received, now handle pdu data
    #
    $logHash->{helper}{lrecv} = gettimeofday(); # logical module side
    Modbus_Profiler($ioHash, "Fhem");
    delete $logHash->{gotReadings};     # will be filled by ParseObj later
    
    my $values    = $data;              # real value part of data (typically after a length byte) - will be overwritten
    my $actualLen = length ($data);     # actually read length of data part (registers / coils / ...) for comparison
    my $headerLen = 4;                  # expected len for some fcodes, will be overwritten for others
    my $parseAdr  = $adr;               # default, can be overwritten if adr is contained in reply
    my $quantity  = 0;                  # only used for coils / di and fcode 1 or 2. If 0 parseObj ignores it
    
    if ($fCode == 1 || $fCode == 2) {                       # read coils / discrete inputs,     pdu: bytes, coils
        ($headerLen, $values) = unpack ('Ca*', $data);
        $actualLen            = length ($values);
        $quantity             = $reqLen; # num of coils
    } elsif ($fCode == 3 || $fCode == 4) {                  # read holding/input registers,     pdu: bytes, registers
        ($headerLen, $values) = unpack ('Ca*', $data);
        if (ModbusLD_DevInfo($logHash, "h", "brokenFC3", 0)) {
            Log3 $name, 5, "$name: ParseFrames uses fix for broken fcode 3";
            ($parseAdr, $values) = unpack ('na*', $data);
            $headerLen = 4;
        }
        $actualLen            = length ($values);
    } elsif ($fCode == 5) {                                 # write single coil,                pdu: adr, coil (FF00)
        ($parseAdr, $values) = unpack ('nH4', $data);  
        if (ModbusLD_DevInfo($logHash, "c", "brokenFC5", 0)) {
            Log3 $name, 5, "$name: ParseFrames uses fix for broken fcode 5";
            $values = ($values eq "0000" ? 0 : 1);
        } else {
            $values = ($values eq "ff00" ? 1 : 0);
        }
        $quantity            = 1;
        # length of $data should be 4
    } elsif ($fCode == 6) {                                 # write single (holding) register,  pdu: adr, register
        ($parseAdr, $values) = unpack ('na*', $data);  
        # length of $data should be 4
    } elsif ($fCode == 15 || $fCode == 16) {                # write mult coils/hold. regis,     pdu: adr, quantity
        ($parseAdr, $quantity) = unpack ('nn', $data);   
        # quantity is only used for coils -> ignored for fcode 16 later
        # length of $data should be 4
    } elsif ($fCode < 128) {    # other function code
        Log3 $name, 3, "$name: ParseFrames: function code $fCode not implemented";
        return "function code $fCode not implemented";
    }
    
    if ($fCode >= 128) {                                    # error
        my $hexdata  = unpack ("H2", $data);
        my $hexFCode = unpack ("H*", pack("C", $fCode));
        my $errCode      = $Modbus_errCodes{$hexdata};
        Log3 $name, 4, "$name: ParseFrames got error code $hexFCode / $hexdata" . 
            ($errCode ? ", $errCode" : "");
        return "device replied with exception code $hexFCode / $hexdata" . ($errCode ? ", $errCode" : "");
    } else {
        if ($headerLen > $actualLen) {
            if ($eCRC != $CRC) {
                Log3 $name, 5, "$name: ParseFrames: wait for more data ($actualLen / $headerLen)";
                return undef;
            } elsif (!ModbusLD_DevInfo($logHash, $type, "allowShortResponses", 0)) {
                Log3 $name, 5, "$name: ParseFrames: wait for more data ($actualLen / $headerLen)";
                return undef;
            }
            Log3 $name, 5, "$name: ParseFrames: frame seems incomplete ($actualLen / $headerLen) but checksum is fine and allowShortResponses is set ...";
        }
        return "ParseFrames got wrong Checksum (expect $eCRC, got $CRC)" if ($eCRC != $CRC);
        Log3 $name, 4, "$name: ParseFrames got fcode $fCode from $devAdr" .
            ($proto eq "TCP" ? ", tid $tid" : "") .
            ", values " . unpack ('H*', $values) . "HeaderLen $headerLen, ActualLen $actualLen" . 
            ", request was for $type$adr ($ioHash->{REQUEST}{READING})".
            ", len $reqLen for module $logHash->{NAME}";
        if ($fCode < 15) {
            # nothing to parse after reply to 15 / 16
            Modbus_ParseObj($logHash, $values, $type.$parseAdr, $quantity, $op);     
            Log3 $name, 5, "$name: ParseFrames got " . scalar keys (%{$logHash->{gotReadings}}) . " readings from ParseObj";
        } else {
            Log3 $name, 5, "$name: reply to fcode 15 and 16 does not contain values";
        }
        return 1;
    }
    return;
}



#####################################
# End of BUSY
# called with physical device hash
sub Modbus_EndBUSY($)
{
    my $hash = shift;
    my $name = $hash->{NAME};

    $hash->{helper}{buffer} = "";
    $hash->{BUSY} = 0;
    delete $hash->{REQUEST};
    delete $hash->{nextTimeout};
    Modbus_Profiler($hash, "Idle"); 
    Modbus_Statistics($hash, "Timeouts", 0);    # damit bei Bedarf das Reading gesetzt wird
    RemoveInternalTimer ("timeout:$name");
    return;
}


#####################################
# Called from the global loop, when the select for hash->{FD} reports data
# hash is hash of the physical device ( = logical device for TCP)
sub Modbus_Read($)
{
    # physical layer function - read to common physical buffers ...
    my $hash = shift;
    my $name = $hash->{NAME};
    my $buf  = DevIo_SimpleRead($hash);
    return if(!defined($buf));
    my $now = gettimeofday();
    
    Modbus_Profiler($hash, "Read");
    Log3 $name, 5, "$name: raw read: " . unpack ('H*', $buf);

    $hash->{helper}{buffer} .= $buf;  
    $hash->{helper}{lrecv}   = $now;        # physical side

    my $code = Modbus_ParseFrames($hash);
    if ($code) {
        if ($code ne "1") {
            Log3 $name, 5, "$name: ParseFrames returned error: $code" 
        }
        delete $hash->{TIMEOUTS};
        Modbus_EndBUSY ($hash);         # set BUSY to 0, delete REQUEST, clear Buffer, do Profilig
        RemoveInternalTimer ("queue:$name"); 
        Modbus_HandleSendQueue ("direct:$name"); # don't wait for next regular handle queue slot
    }
    return;
}


###########################
# open connection 
# $hash is physical or both (TCP)
# called from set reconnect, Attr (disable), Notify (initialized, rereadcfg, |(MODIFIED $name)), Ready
sub Modbus_Open($;$)
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
    $hash->{IODev}          = $hash if ($hash->{DEST});      # for TCP Log-Module itself is IODev (removed during CloseDev) 
    $hash->{BUSY}           = 0;   
    $hash->{BUSY_OPENDEV}   = 1;
    $hash->{LASTOPEN}       = $now;
    $hash->{nextOpenDelay}  = AttrVal($name, "nextOpenDelay", 60);   
    $hash->{devioLoglevel}  = (AttrVal($name, "silentReconnect", 0) ? 4 : 3);
    $hash->{TIMEOUT}        = AttrVal($name, "openTimeout", 3);
    $hash->{helper}{buffer} = "";       # clear Buffer for reception

    DevIo_OpenDev($hash, $reopen, 0, \&Modbus_OpenCB);
    delete $hash->{TIMEOUT};
    return;
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
            Log3 $name, 3, "$name: _Reconnect: $name is disabled - don't try to reconnect";
            DevIo_CloseDev($hash);
            $hash->{BUSY} = 0;                         
            return;
        }
        Modbus_Open($hash, 1);  # reopen, dont call DevIoClose before reopening
        return;     # a return value only triggers direct read for windows - main loop will select for data
    }
    # This is relevant for windows/USB only
    my $po = $hash->{USBDev};
    if ($po) {
        my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
        return ($InBytes>0);    # tell fhem.pl to read when we return
    }
    return;
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


#######################################
sub Modbus_CountTimeouts($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};

    if ($hash->{DEST}) {
        # modbus TCP/RTU/ASCII over TCP
        if ($hash->{TIMEOUTS}) {
            $hash->{TIMEOUTS}++;
            my $max = AttrVal($name, "maxTimeoutsToReconnect", 0);
            if ($max && $hash->{TIMEOUTS} >= $max) {
                Log3 $name, 3, "$name: $hash->{TIMEOUTS} successive timeouts, setting state to disconnected";
                DevIo_Disconnected($hash);
            }
        } else {
            $hash->{TIMEOUTS} = 1;
        }
    }
    return;
}


#######################################
# Aufruf aus InternalTimer mit "timeout:$name" 
# wobei name das physical device ist
sub Modbus_TimeoutSend($)
{
    my $param = shift;
    my (undef,$name) = split(':',$param);
    my $ioHash = $defs{$name};
    my $logLvl = AttrVal($name, "timeoutLogLevel", 3);
    Log3 $name, $logLvl, "$name: timeout waiting for fc $ioHash->{REQUEST}{FCODE} " .
                "from id $ioHash->{REQUEST}{MODBUSID}, " .
                "Request was $ioHash->{REQUESTHEX}" .
                " ($ioHash->{REQUEST}{TYPE}$ioHash->{REQUEST}{ADR} / $ioHash->{REQUEST}{READING}, len $ioHash->{REQUEST}{LEN})" .
                ($ioHash->{helper}{buffer} ? ", Buffer contains " . unpack ("H*", $ioHash->{helper}{buffer}) : "");

    Modbus_Statistics($ioHash, "Timeouts", 1);
    Modbus_EndBUSY ($ioHash);                   # set BUSY to 0, delete REQUEST, clear Buffer, do Profilig, remove internalTimer
    Modbus_CountTimeouts ($ioHash);
    Modbus_HandleSendQueue ("direct:$name");    # verwaltet auch idle und busy time statistics variables  
    return;
};


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
    
    Log3 $name, 5, "$name: handle queue check $title ($delay) for $devName: rest $rest";
    if ($rest > 0) {
        Modbus_Profiler($ioHash, "Delay");  
        if ($force) {
            Log3 $name, 4, "$name: HandleSendQueue / CheckDelay $title ($delay) for $devName not over, sleep $rest forced";
            sleep $rest if ($rest > 0 && $rest < $delay);
            return 0;
        } else {
            InternalTimer($t2, "Modbus_HandleSendQueue", "queue:$name", 0);
            Log3 $name, 4, "$name: HandleSendQueue / CheckDelay $title ($delay) for $devName not over, try again in $rest";
            return 1;
        }
    }  
    return 0;
}


#######################################
# Aufruf aus InternalTimer mit "queue:$name" 
# oder direkt mit "direkt:$name
# wobei name das physical device ist
# greift über den Request der Queue auf das logische Device zu
# um Timings und Zeitstempel zu verarbeiten
sub Modbus_HandleSendQueue($;$)
{
    my (undef,$name) = split(':', shift);
    my $force  = shift;
    my $ioHash = $defs{$name};
    my $queue  = $ioHash->{QUEUE};
    my $now    = gettimeofday();
  
    #Log3 $name, 5, "$name: handle queue" . ($force ? ", force" : "");
    RemoveInternalTimer ("queue:$name");
  
    return if(!defined($queue) || @{$queue} == 0);

    my $queueDelay  = AttrVal($name, "queueDelay", 1);  
  
    if ($ioHash->{STATE} eq "disconnected") {
        Log3 $name, 4, "$name: handle queue: device is disconnected, dropping requests in queue";
        Modbus_Profiler($ioHash, "Idle");   
        delete $ioHash->{QUEUE};
        return;
    } 
    if (IsDisabled($name)) {
        Log3 $name, 4, "$name: HandleSendQueue called but device is disabled. Dropping requests in queue";
        Modbus_Profiler($ioHash, "Idle");   
        delete $ioHash->{QUEUE};
        return;
    }   
    if (!$init_done) {      # fhem not initialized, wait with IO
        InternalTimer($now+$queueDelay, "Modbus_HandleSendQueue", "queue:$name", 0);
        Log3 $name, 3, "$name: handle queue: not available yet (init not done), try again in $queueDelay seconds";
        return;
    }
    if ($ioHash->{BUSY}) {  # still waiting for reply to last request
        InternalTimer($now+$queueDelay, "Modbus_HandleSendQueue", "queue:$name", 0);
        #Log3 $name, 5, "$name: handle queue: busy, try again in $queueDelay seconds";
        #Modbus_Profiler($ioHash, "Wait");  
        return;
    }
    
    return if ((!$queue) || (!$queue->[0]));    # nothing in queue
        
    # get top element from Queue
    my $request = $queue->[0];    
    if (!$request->{FCODE}) {
        Log3 $name, 4, "$name: HandleSendQueue called with empty fcode entry. Dropping request";
        shift(@{$queue});           # remove first element from queue
        return;
    }

    my $reading = $request->{READING};
    my $len     = $request->{LEN};
    my $tid     = $request->{TID};
    my $adr     = $request->{ADR}; 
    my $reqId   = $request->{MODBUSID};
    my $proto   = $request->{PROTOCOL};
    my $type    = $request->{TYPE};
    my $fCode   = $request->{FCODE};
    my $v1      = $request->{VALUE};
    my $logHash = $request->{DEVHASH};

    if (IsDisabled($logHash->{NAME})) {
        Log3 $name, 4, "$name: HandleSendQueue called but logical device is disabled. Dropping request";
        shift(@{$queue});           # remove first element from queue
        #Modbus_Profiler($ioHash, "Idle");   
        # todo: profiler? 
        return;
    }   

    # todo: check profiler setting in case delays not over  
    # check defined delays
    if ($ioHash->{helper}{lrecv}) {
        #Log3 $name, 5, "$name: check busDelay ...";
        return if (Modbus_CheckDelay($ioHash, $name, $force, 
                "busDelay", AttrVal($name, "busDelay", 0),
                $ioHash->{helper}{lrecv}));
        #Log3 $name, 5, "$name: check clientSwitchDelay ...";       
        my $clSwDelay = AttrVal($name, "clientSwitchDelay", 0);
        if ($clSwDelay && $ioHash->{helper}{lid}
            && $reqId != $ioHash->{helper}{lid}) {
            return if (Modbus_CheckDelay($ioHash, $name, $force, 
                    "clientSwitchDelay", $clSwDelay, 
                    $ioHash->{helper}{lrecv}));
        }
    }
    if ($logHash->{helper}{lrecv}) {
        return if (Modbus_CheckDelay($ioHash, $logHash->{NAME}, $force, 
                "commDelay", ModbusLD_DevInfo($logHash, "timing", "commDelay", 0.1),
                $logHash->{helper}{lrecv}));
    }
    if ($logHash->{helper}{lsend}) {
        return if (Modbus_CheckDelay($ioHash, $logHash->{NAME}, $force, 
                "sendDelay", ModbusLD_DevInfo($logHash, "timing", "sendDelay", 0.1),
                $logHash->{helper}{lsend}));
    }
    Log3 $name, 5, "$name: HandleSendQueue: finished delay checking, proceed with sending";       
    
    my $data;
    if ($fCode == 1 || $fCode == 2) {           # read coils / discrete inputs, pdu: StartAdr, Len (=number of coils)
        $data = pack ('nn', $adr, $len);        
    } elsif ($fCode == 3 || $fCode == 4) {      # read holding/input registers, pdu: StartAdr, Len (=number of regs)
        $data = pack ('nn', $adr, $len);
    } elsif ($fCode == 5) {                     # write single coil,            pdu: StartAdr, Value (1-bit as FF00)
        if (ModbusLD_DevInfo($logHash, "c", "brokenFC5", 0)) {
            my $oneCode = lc ModbusLD_DevInfo($logHash, "c", "brokenFC5");
            $data = pack ('nH4', $adr, (unpack ('n',$v1) ? $oneCode : "0000"));
        } else {
            $data = pack ('nH4', $adr, (unpack ('n',$v1) ? "FF00" : "0000"));
        }
    } elsif ($fCode == 6) {                     # write single register,        pdu: StartAdr, Value
        $data = pack ('n', $adr) . $v1;
    } elsif ($fCode == 15) {                    # write multiple coils,         pdu: StartAdr, NumOfCoils, ByteCount, Values
        $data = pack ('nnCC', $adr, int($len/8)+1, $len, $v1);      # todo: test / fix 
    } elsif ($fCode == 16) {                    # write multiple regs,          pdu: StartAdr, NumOfRegs, ByteCount, Values
        $data = pack ('nnC', $adr, $len, $len*2) . $v1;
    } else {                                    # function code not implemented yet
        Log3 $name, 3, "$name: Send function code $fCode not yet implemented";
        return;
    }
    my $pdu = pack ('C', $fCode) . $data;
    
    my $frame;
    my $packedId = pack ('C', $reqId);
    
    if ($proto eq "RTU") {           # frame format: ID, (fCode, data), CRC
        my $crc    = pack ('v', Modbus_CRC($packedId . $pdu));
        $frame     = $packedId . $pdu . $crc;
    } elsif ($proto eq "ASCII") {    # frame format: ID, (fCode, data), LRC
        my $lrc    = uc(unpack ('H2', pack ('v', Modbus_LRC($packedId.$pdu))));
        #Log3 $name, 5, "$name: LRC: $lrc";
        $frame     = ':' . uc(unpack ('H2', $packedId) . unpack ('H*', $pdu)) . $lrc . "\r\n";
    } elsif ($proto eq "TCP") {      # frame format: tid, 0, len, ID, (fCode, data)
        my $dlen   = bytes::length($pdu)+1;         # length of pdu + Id
        my $header = pack ('nnnC', ($tid, 0, $dlen, $reqId));
        $frame     = $header.$pdu;
    }
    
    $request->{FRAME}  = $frame;    # frame as data string for echo detection
    $ioHash->{REQUEST} = $request;  # save for later
    
    Modbus_Profiler($ioHash, "Send");   
    $ioHash->{REQUESTHEX}     = unpack ('H*', $frame); # for debugging / log
    $ioHash->{BUSY}           = 1;        # modbus bus is busy until response is received
    $ioHash->{helper}{buffer} = "";       # clear Buffer for reception
    
    #Log3 $name, 3, "$name: insert Garbage for testing";
    #$ioHash->{helper}{buffer} = pack ("C",0);       # test / debug / todo: remove
  
    Log3 $name, 4, "$name: HandleSendQueue sends fc $fCode to id $reqId, tid $tid for $reading ($type$adr), len $len" .
                    ", device $logHash->{NAME} ($proto), pdu " . unpack ('H*', $pdu) . ", V $Modbus_Version";
    
    DevIo_SimpleWrite($ioHash, $frame, 0);
    
    $now = gettimeofday();
    $ioHash->{helper}{lsend}  = $now;     # remember when last send to this bus
    $logHash->{helper}{lsend} = $now;     # remember when last send to this device
    $ioHash->{helper}{lid}    = $reqId;   # device id we talked to

    Modbus_Statistics($ioHash, "Requests", 1);
    Modbus_Profiler($ioHash, "Wait");   
    my $timeout = ModbusLD_DevInfo($logHash, "timing", "timeout", 2);
    my $toTime  = $now+$timeout;
    RemoveInternalTimer ("timeout:$name");
    InternalTimer($toTime, "Modbus_TimeoutSend", "timeout:$name", 0);
    $ioHash->{nextTimeout} = $toTime;
        
    shift(@{$queue});           # remove first element from queue
    if(@{$queue} > 0) {         # more items in queue -> schedule next handle 
        InternalTimer($now+$queueDelay, "Modbus_HandleSendQueue", "queue:$name", 0);
    }
    return;
}



##################################################
#
# Funktionen für logische Geräte 
# zum Aufruf aus anderen Modulen
#
##################################################


#####################################
sub ModbusLD_Initialize($ )
{
    my ($modHash) = @_;

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
        "obj-[cdih][0-9]+-poll " .
        "obj-[cdih][0-9]+-polldelay ";

        #"(get|set)([0-9]+)request([0-9]+) "
        
    $modHash->{DevAttrList} = 
        "dev-([cdih]-)*read " .
        "dev-([cdih]-)*write " .
        "dev-([cdih]-)*combine " .
        "dev-([cdih]-)*allowShortResponses " .

        "dev-([cdih]-)*defRevRegs " .
        "dev-([cdih]-)*defBswapRegs " .
        "dev-([cdih]-)*defLen " .
        "dev-([cdih]-)*defUnpack " .
        "dev-([cdih]-)*defDecode " .
        "dev-([cdih]-)*defEncode " .
        "dev-([cdih]-)*defExpr " .
        "dev-([cdih]-)*defIgnoreExpr " .
        "dev-([cdih]-)*defFormat " .
        "dev-([cdih]-)*defShowGet " .
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

        "dev-timing-timeout " .
        "dev-timing-sendDelay " .
        "dev-timing-commDelay ";
    return;            
}


#####################################
sub ModbusLD_SetIODev($)
{
    my ($hash) = @_;
    my $name   = $hash->{NAME};
    my $ioName = AttrVal($name, "IODev", "");
    my $ioHash;
    if ($ioName) {
        # handle IODev Attribute
        if ($defs{$ioName}) {         # gibt es den Geräte-Hash zum IODev Attribut?
            $ioHash = $defs{$ioName};
        } else {
            Log3 $name, 3, "$name: SetIODev can't use $ioName from IODev attribute - device does not exist";
        }
    }
    if (!$ioHash) {
        # search for usable physical Modbus device
        for my $p (sort { $defs{$b}{NR} <=> $defs{$a}{NR} } keys %defs) {
            if ( $defs{$p}{TYPE} eq "Modbus") {
                $ioHash = $defs{$p};
                $attr{$name}{IODev} = $ioHash->{NAME};       # set IODev attribute
                last;
            }
        }
    }
    if (!$ioHash) {
        # still nothing found -> give up for now
        Log3 $name, 3, "$name: SetIODev found no physical modbus device";
        return undef;
    }
    $ioName = $ioHash->{NAME};
    Log3 $name, 3, "$name: SetIODev registers $name with Id $hash->{MODBUSID} at $ioName";
    $hash->{IODev} = $ioHash;                           # point internal IODev to io device hash
    $hash->{IODev}{defptr}{$hash->{MODBUSID}} = $hash;  # register device for given id at io hash (for removal at undef)
    Log3 $name, 5, "$name: SetIODev is using $ioHash->{NAME}";
    return $ioHash;
}



#########################################################################
# set internal Timer to call GetUpdate if necessary
# either at next interval 
# or if start is passed in start seconds (e.g. 2 seconds after Fhem init)
sub ModbusLD_SetTimer($;$)
{
    my ($hash, $start) = @_;
    my $nextTrigger;
    my $name = $hash->{NAME};
    my $now  = gettimeofday();
    $start   = 0 if (!$start);

    if ($hash->{INTERVAL} && $hash->{INTERVAL} > 0) {
        if ($hash->{TimeAlign}) {
            my $count = int(($now - $hash->{TimeAlign} + $start) / $hash->{INTERVAL});
            my $curCycle = $hash->{TimeAlign} + $count * $hash->{INTERVAL};
            $nextTrigger = $curCycle + $hash->{INTERVAL};
        } else {
            $nextTrigger = $now + ($start ? $start : $hash->{INTERVAL});
        }
        
        $hash->{TRIGGERTIME}     = $nextTrigger;
        $hash->{TRIGGERTIME_FMT} = FmtDateTime($nextTrigger);
        RemoveInternalTimer("update:$name");
        InternalTimer($nextTrigger, "ModbusLD_GetUpdate", "update:$name", 0);
        Log3 $name, 4, "$name: update timer modified: will call GetUpdate in " . 
            sprintf ("%.1f", $nextTrigger - $now) . " seconds at $hash->{TRIGGERTIME_FMT} - Interval $hash->{INTERVAL}";
    } else {
       $hash->{TRIGGERTIME}     = 0;
       $hash->{TRIGGERTIME_FMT} = "";
    }
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
    delete $hash->{TIMEOUTS} if ($hash->{FD});
    return;
}


#####################################
sub ModbusLD_Define($$)
{
    my ($hash, $def) = @_;
    my @a = split("[ \t]+", $def);
    my ($name, $module, $id, $interval, $dest, $proto) = @a;
    
    return "wrong syntax: define <name> $module [id] [interval] [host:port] [RTU|ASCII|TCP]"
        if(@a < 2);

    if ($proto) {
        $proto = uc($proto);
        return "wrong syntax: define <name> $module [id] [interval] [host:port] [RTU|ASCII|TCP]"
            if ($proto !~ /RTU|ASCII|TCP/);
    } else {
        if ($dest && uc($dest) =~ /RTU|ASCII|TCP/) {
            # no host but protocol given
            $proto = uc($dest);
            $dest = "";
        }
    }

    # for TCP $id is an optional Unit ID that is ignored by most devices
    # but some gateways may use it to select the device to forward to.

    $id       = 1     if (!defined($id));
    $interval = 0     if (!defined($interval));
    $proto    = "RTU" if (!defined($proto));
    $dest     = ""    if (!defined($dest));
    
    return "Interval has to be numeric" if ($interval !~ /[0-9.]+/);
        
    $hash->{NOTIFYDEV}       = "global";                  # NotifyFn nur aufrufen wenn global events (INITIALIZED etc.)
    $hash->{ModuleVersion}   = $Modbus_Version;
    $hash->{MODBUSID}        = $id;
    $hash->{INTERVAL}        = $interval;
    $hash->{PROTOCOL}        = $proto;    
    $hash->{'.getList'}      = "";
    $hash->{'.setList'}      = "";
    $hash->{".updateSetGet"} = 1;

    if ($dest) {                                    # Modbus über TCP mit IP Adresse angegeben (TCP oder auch RTU/ASCII über TCP)
        $dest .= ":502" if ($dest !~ /.*:[0-9]/);   # add default port if no port specified
        $hash->{DEST}          = $dest;  
        $hash->{IODev}         = $hash;             # Modul ist selbst IODev
        $hash->{defptr}{$id}   = $hash;             # ID verweist zurück auf eigenes Modul  
        $hash->{DeviceName}    = $dest;             # needed by DevIo to get Device, Port, Speed etc.
        $hash->{STATE}         = "disconnected";    # initial value
        
        my $modHash = $modules{$hash->{TYPE}};
        $modHash->{AttrList} .= $Modbus_PhysAttrs;  # affects all devices - even non TCP - sorry ...
        #Log3 $name, 3, "$name: added attributes for physical devices for Modbus TCP";
    } else {
        $hash->{DEST} = "";         # logical device that uses a physical Modbus device
    }
    Log3 $name, 3, "$name: defined with id $id, interval $interval, protocol $proto" .
                    ($dest ? ", destination $dest" : "");
    return;
}


#########################################################################
sub Modbus_Attr(@)
{
    my ($cmd,$name,$aName,$aVal) = @_;
    my $hash = $defs{$name};        # hash des physischen Devices
    
    Log3 $name, 5, "$name: $cmd attr $aName" . (defined($aVal) ? ", $aVal" : "");
    if ($aName eq 'disable' && $init_done) {        # only after init_done, otherwise see NotifyFN
        # disable on a physical serial device
        if ($cmd eq "set" && $aVal) {
            Log3 $name, 3, "$name: disable attribute set" . ($hash->{FD} ? ", closing connection" : "");
            DevIo_CloseDev($hash) if ($hash->{FD});
            $hash->{STATE} = "disconnected";
            $hash->{BUSY}  = 0;
            
        } elsif ($cmd eq "del" || ($cmd eq "set" && !$aVal)) {
            Log3 $name, 3, "$name: disable attribute removed";
            Modbus_Open($hash);
        }
    }   
    return undef;
}




#########################################################################
sub ModbusLD_Attr(@)
{
    my ($cmd,$name,$aName,$aVal) = @_;
    my $hash = $defs{$name};        # hash des logischen Devices
    my $inCheckEval = 0;

    # todo: validate other attrs
    # e.g. unpack not allowed for coils / discrete inputs, len not for coils,
    # max combine,  etc.
    # 
    if ($cmd eq "set") {
        if ($aName =~ "expr") {     # validate all Expressions
            my $val = 1;
            eval $aVal;
            if ($@) {
                Log3 $name, 3, "$name: Attr with invalid Expression in attr $name $aName $aVal: $@";
                return "Invalid Expression $aVal";
            }
        } elsif ($aName eq "IODev") {   # defptr housekeeping
            my $ioHash = $defs{$aVal};
            if ($ioHash && $ioHash->{TYPE} eq "Modbus") {           # gibt es den Geräte-Hash zum IODev Attribut?
                $ioHash->{defptr}{$hash->{MODBUSID}} = $hash;       # register logical device
                Log3 $name, 5, "$name: Attr IODev - using $aVal";
            } else {
                Log3 $name, 5, "$name: Attr IODev can't use $aVal - device does not exist (yet?) or is not a physical Modbus Device";
            }            
        } elsif ($aName eq 'alignTime') {
            my ($alErr, $alHr, $alMin, $alSec, undef) = GetTimeSpec($aVal);
            return "Invalid Format $aVal in $aName : $alErr" if ($alErr);
            my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
            $hash->{TimeAlign}    = fhemTimeLocal($alSec, $alMin, $alHr, $mday, $mon, $year);
            $hash->{TimeAlignFmt} = FmtDateTime($hash->{TimeAlign});
            ModbusLD_SetTimer($hash);     # change timer for alignment 
        } elsif (" $Modbus_PhysAttrs " =~ /\ $aName[: ]/) {
            if (!$hash->{DEST}) {
                Log3 $name, 3, "$name: attribute $aName is only valid for physical Modbus devices or Modbus TCP - please use this attribute for your physical IO device $hash->{IODev}{NAME}";
                return "attribute $aName is only valid for physical Modbus devices or Modbus TCP - please use this attribute for your physical IO device $hash->{IODev}{NAME}";
            }
        } elsif ($aName =~ /(obj-[cdih])(0+([0-9]+))-/) {
            # leading zero in obj-Attr detected
            if (length($2) > 5) {
                my $new = $1 . substr("00000", 5 - length ($3)) . $3;
                $aName = $new;
                Log3 $name, 3, "$name: Address in attribute $aName too long, shortened to $new";
            }
            if (!$hash->{LeadingZeros}) {
                $hash->{LeadingZeros} = 1;
                Log3 $name, 3, "$name: Support for leading zeros in object addresses enabled. This might slow down the fhem modbus module a bit";
            }
        }
        
        addToDevAttrList($name, $aName);
        
    } elsif ($cmd eq "del") {    
        #Log3 $name, 5, "$name: del attribute $aName";
        if ($aName =~ /obj-[cdih]0[0-9]+-/) {
            if (!(grep !/$aName/, grep (/obj-[cdih]0[0-9]+-/, keys %{$attr{$name}}))) {
                delete $hash->{LeadingZeros};   # no more leading zeros            
            }
        }
    }
    $hash->{".updateSetGet"} = 1;
    
    if ($aName eq 'disable' && $init_done) {    # if not init_done, nothing to be done here (see NotifyFN)
        # disable on a logical device (not physical here!)
        if ($cmd eq "set" && $aVal) {
            if ($hash->{DEST}) {            # Modbus TCP
                Log3 $name, 3, "$name: disable attribute set" .
                    ($hash->{FD} ? ", closing TCP connection" : "");
                DevIo_CloseDev($hash) if ($hash->{FD});
                $hash->{BUSY} = 0;
            }
            RemoveInternalTimer("update:$name");
            
        } elsif ($cmd eq "del" || ($cmd eq "set" && !$aVal)) {
            Log3 $name, 3, "$name: disable attribute removed" . 
                ($hash->{DEST} ? ", opening TCP connection" : "");
            if ($hash->{DEST}) {            # Modbus TCP
                Modbus_Open($hash);         # should be called with hash of physical device but for TCP it's the same
            } else {            
                my $ioHash = ModbusLD_GetIOHash($hash);
                my $ioName = $ioHash->{NAME};    
                if ($ioName) {
                    Log3 $name, 3, "$name: using $ioName for communication";
                } else {
                    Log3 $name, 3, "$name: no IODev for communication";
                }
            }           
            ModbusLD_SetTimer($hash, 1);    # first Update in 1 second or aligned if interval is defined
        }
    }   
    return;
}


#####################################
sub ModbusLD_Undef($$)
{
    my ($hash, $arg) = @_;
    my $name = $hash->{NAME};
    
    DevIo_CloseDev($hash) if ($hash->{DEST});   # logical Device over TCP - no underlying physical Device
    RemoveInternalTimer ("update:$name");
    RemoveInternalTimer ("timeout:$name");
    RemoveInternalTimer ("queue:$name"); 
    return;
}


#####################################
sub ModbusLD_UpdateGetSetList($)
{
    my ($hash)    = @_;
    my $name      = $hash->{NAME};
    my $modHash   = $modules{$hash->{TYPE}};
    my $parseInfo = $modHash->{parseInfo};
    
    if (AttrVal($name, "enableControlSet", undef)) {        # spezielle Sets freigeschaltet?
        $hash->{'.setList'} = "interval reread:noArg reconnect:noArg stop:noArg start:noArg ";
        if ($hash->{PROTOCOL} =~ /RTU|ASCII/) {
            $hash->{'.setList'} .= "scanModbusId ";
        }
        $hash->{'.setList'} .= "scanStop:noArg scanModbusObjects ";
    } else {
        $hash->{'.setList'}  = "";
    }
    $hash->{'.getList'}  = "";

    my @ObjList = keys (%{$parseInfo});
    foreach my $at (keys %{$attr{$name}}) {
        if ($at =~ /^obj-(.*)-reading$/) {
            push @ObjList, $1 if (!$parseInfo->{$1});
        }
    }
    #Log3 $name, 5, "$name: UpdateGetSetList full object list: " . join (" ",  @ObjList);
    
    foreach my $objCombi (sort @ObjList) {
        my $reading = ModbusLD_ObjInfo($hash, $objCombi, "reading");
        my $showget = ModbusLD_ObjInfo($hash, $objCombi, "showGet", "defShowGet", 0);   # default to 0
        my $set     = ModbusLD_ObjInfo($hash, $objCombi, "set", 0);                     # default to 0
        my $map     = ModbusLD_ObjInfo($hash, $objCombi, "map", "defMap");
        my $hint    = ModbusLD_ObjInfo($hash, $objCombi, "hint");
        #my $type    = substr($objCombi, 0, 1);
        #my $adr     = substr($objCombi, 1);
        my $setopt;
        $hash->{'.getList'} .= "$reading:noArg " if ($showget); # sichtbares get

        if ($set) {                 # gibt es für das Reading ein SET?
            if ($map){              # ist eine Map definiert, aus der Hints abgeleitet werden können?
                my $hl = $map;
                $hl =~ s/([^ ,\$]+):([^ ,\$]+,?) ?/$2/g;
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
    #Log3 $name, 5, "$name: UpdateSetList: setList=$hash->{'.setList'}";
    #Log3 $name, 5, "$name: UpdateSetList: getList=$hash->{'.getList'}";
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
 
    my $objCombi;
    if ($getName ne "?") {
        $objCombi = ModbusLD_ObjKey($hash, $getName);
        #Log3 $name, 5, "$name: Get: key for $getName = $objCombi";
    }

    if (!$objCombi) {
        ModbusLD_UpdateGetSetList($hash) if ($hash->{".updateSetGet"});
        Log3 $name, 5, "$name: Get: $getName not found, return list $hash->{'.getList'}"
            if ($getName ne "?");
        return "Unknown argument $a[1], choose one of $hash->{'.getList'}";
    }
    if (IsDisabled($name)) {
        Log3 $name, 5, "$name: Get called with $getName but device is disabled";
        return undef;
    }

    my $ioHash  = ModbusLD_GetIOHash($hash);
    return undef if (!$ioHash);

    my ($err, $result);
    Log3 $name, 5, "$name: Get: Called with $getName ($objCombi)";
    
    if ($ioHash->{BUSY}) {                              # Answer for last function code has not yet arrived
        Log3 $name, 5, "$name: Get: Queue is stil busy - taking over the read with ReadAnswer";

        ModbusLD_ReadAnswer($hash);                     # finish last read and wait for the result before next request
        Modbus_EndBUSY ($ioHash);                       # set BUSY to 0, delete REQUEST, clear Buffer, do Profilig
    }

    ModbusLD_Send($hash, $objCombi, "read", 0, 1);      # add at beginning of queue and force send / sleep if necessary
    ($err, $result) = ModbusLD_ReadAnswer($hash, $getName);
    Modbus_EndBUSY ($ioHash);                           # set BUSY to 0, delete REQUEST, clear Buffer, do Profilig

    return $err if ($err);
    return $result;
}


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


#
# SET command - handle predifined control sets
################################################
sub ModbusLD_ControlSet($$$)
{
    my ($hash, $setName, $setVal) = @_;
    my $name = $hash->{NAME};
    
    if ($setName eq 'interval') {
        if (!$setVal || $setVal !~ /[0-9.]+/) {
            Log3 $name, 3, "$name: no valid interval (secs) specified in set, continuing with $hash->{INTERVAL} (sec)";
            return "No valid Interval specified";
        } else {
            $hash->{INTERVAL} = $setVal;
            Log3 $name, 3, "$name: timer interval changed to $hash->{INTERVAL} seconds";
            ModbusLD_SetTimer($hash);
            return "0";
        }
        
    } elsif ($setName eq 'reread') {
        ModbusLD_GetUpdate("reread:$name");
        return "0";
        
    } elsif ($setName eq 'reconnect') { 
        if (IsDisabled($name)) {
            Log3 $name, 3, "$name: set reconnect called but device is disabled";
            return "set reconnect called but device is disabled";
        }
        if (!$hash->{DEST}) {
            Log3 $name, 3, "$name: set reconnect called but device is not using Modbus TCP and the connection is going through another device so the connection can't be reconnected from here";
            return "set reconnect called but device is connecting through another physical device";
        }
        Modbus_Open($hash);         # should be called with hash of physical device but for TCP it's the same
        return "0";
        
    } elsif ($setName eq 'stop') {
        RemoveInternalTimer("update:$name");    
        $hash->{TRIGGERTIME}     = 0;
        $hash->{TRIGGERTIME_FMT} = "";
        Log3 $name, 3, "$name: internal interval timer stopped";
        return "0";
        
    } elsif ($setName eq 'start') {
        ModbusLD_SetTimer($hash);
        return "0";
        
    } elsif ($setName eq 'scanStop') {
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
        Log3 $name, 3, "$name: Scan range specified as Modbus Id $hash->{scanIdStart} to $hash->{scanIdEnd}" .
                        " with $hash->{scanOType}$hash->{scanOAdr}, Len ";
        delete $hash->{scanId};
        
        my $now        = gettimeofday();
        my $scanDelay  = AttrVal($name, "scanDelay", 1);  
        RemoveInternalTimer ("scan:$name");
        InternalTimer($now+$scanDelay, "ModbusLD_ScanIds", "scan:$name", 0);   
        return "0";
        
    } elsif ($setName eq 'scanModbusObjects') { 
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
        Log3 $name, 3, "$name: Scan $hash->{scanOType} from $hash->{scanOStart} to $hash->{scanOEnd} len $hash->{scanOLen}";        
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
            Log3 $name, 3, "$name: Cannot create output file $hash->{OUTPUT}";
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
    my $hash      = $defs{$name};   # hash des logischen Devices, da GetUpdate aus dem logischen Modul per Timer gestartet wird

    my $now        = gettimeofday();
    my $scanDelay  = AttrVal($name, "scanDelay", 1);  
    my $ioHash     = ModbusLD_GetIOHash($hash);
    my $queue      = $ioHash->{QUEUE};
    my $qlen       = ($ioHash->{QUEUE} ? scalar(@{$ioHash->{QUEUE}}) : 0);
    
    RemoveInternalTimer ("scan:$name");
    if ($qlen && $qlen > AttrVal($name, "queueMax", 100) / 2) {
        InternalTimer($now+$scanDelay, "ModbusLD_ScanObjects", "scan:$name", 0);
        Log3 $name, 5, "$name: ScanObjects waits until queue gets smaller";
        return;
    }
    if ($hash->{scanOAdr} || $hash->{scanOAdr} eq "0") {
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
    ModbusLD_Send ($hash, $hash->{scanOType}.$hash->{scanOAdr}, 'scanobj', 0, 0, $hash->{scanOLen});
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
    my $hash      = $defs{$name};   # hash des logischen Devices, da GetUpdate aus dem logischen Modul per Timer gestartet wird

    my $now        = gettimeofday();
    my $scanDelay  = AttrVal($name, "scanDelay", 1);  
    my $ioHash     = ModbusLD_GetIOHash($hash);
    my $queue      = $ioHash->{QUEUE};
    my $qLen       = ($ioHash->{QUEUE} ? scalar(@{$ioHash->{QUEUE}}) : 0);
    my $qMax       = AttrVal($name, "queueMax", 100) / 2;
    
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
    ModbusLD_Send ($hash, $hash->{scanOType}.$hash->{scanOAdr}, 'scanid'.$hash->{scanId}, 0, 0, $hash->{scanOLen});
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
    Log3 $name, 5, "$name: ScanFormat: hex=$h, bytes=$len";
    
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


#####################################
sub ModbusLD_Set($@)
{
    my ($hash, @a) = @_;
    return "\"set $a[0]\" needs at least an argument" if(@a < 2);

    my ($name, $setName, @setValArr) = @a;
    my $setVal = (@setValArr ? join(' ', @setValArr) : "");
    my $rawVal  = "";
    
    if (AttrVal($name, "enableControlSet", undef)) {            # spezielle Sets freigeschaltet?
        my $error = ModbusLD_ControlSet($hash, $setName, $setVal);
        return if (defined($error) && $error eq "0");     # control set found and done.
        return $error if ($error);                              # error
        # continue if function returned undef
    }
    
    my $objCombi;
    if ($setName ne "?") {
        $objCombi = ModbusLD_ObjKey($hash, $setName);
        #Log3 $name, 5, "$name: Set: key for $setName = $objCombi";
    }

    if (!$objCombi) {
        ModbusLD_UpdateGetSetList($hash) if ($hash->{".updateSetGet"});
        Log3 $name, 5, "$name: Set: $setName not found, return list $hash->{'.setList'}"
            if ($setName ne "?");
        return "Unknown argument $a[1], choose one of $hash->{'.setList'}";
    } 

    if (IsDisabled($name)) {
        Log3 $name, 4, "$name: set called with $setName but device is disabled";
        return;
    }   

    my $ioHash  = ModbusLD_GetIOHash($hash);    # get or reconstruct ioHash. reconnecton is done in Queue handling if necessary
    return if (!$ioHash);
    
    my $type = substr($objCombi, 0, 1);
    my ($err,$result);
    
    # todo: noarg checking?
    if (!defined($setVal)) {
        Log3 $name, 3, "$name: No Value given to set $setName";
        return "No Value given to set $setName";
    }
    Log3 $name, 5, "$name: Set called with $setName ($objCombi), setVal = $setVal";

    if ($ioHash->{BUSY}) {
        Log3 $name, 5, "$name: Set: Queue still busy - taking over the read with ReadAnswer";
        # Answer for last function code has not yet arrived
        ModbusLD_ReadAnswer($hash);     # finish last read and wait for the result before next request
        Modbus_EndBUSY ($ioHash);       # set BUSY to 0, delete REQUEST, clear Buffer, do Profilig            
    }
    my $map     = ModbusLD_ObjInfo($hash, $objCombi, "map", "defMap");
    my $setmin  = ModbusLD_ObjInfo($hash, $objCombi, "min", "", "");        # default to ""
    my $setmax  = ModbusLD_ObjInfo($hash, $objCombi, "max", "", "");        # default to ""
    my $setexpr = ModbusLD_ObjInfo($hash, $objCombi, "setexpr");
    my $textArg = ModbusLD_ObjInfo($hash, $objCombi, "textArg");
    my $unpack  = ModbusLD_ObjInfo($hash, $objCombi, "unpack", "defUnpack", "n");   
    my $revRegs = ModbusLD_ObjInfo($hash, $objCombi, "revRegs", "defRevRegs");     
    my $swpRegs = ModbusLD_ObjInfo($hash, $objCombi, "bswapRegs", "defBswapRegs"); 
    my $len     = ModbusLD_ObjInfo($hash, $objCombi, "len", "defLen", 1); 
   
    my $fCode   = ModbusLD_DevInfo($hash, $type, "write", $Modbus_defaultFCode{$type}{write});

    if ($map) {         # 1. Schritt: Map prüfen
        my $rm = $map;
        $rm =~ s/([^ ,\$]+):([^ ,\$]+),? ?/$2 $1 /g;    # reverse map string erzeugen
        my %rmap = split (' ', $rm);                    # reverse hash aus dem reverse string                   
        if (defined($rmap{$setVal})) {                  # reverse map Eintrag für das Reading und den Wert definiert
            $rawVal = $rmap{$setVal};
            Log3 $name, 5, "$name: Set: found $setVal in map and converted to $rawVal";
        } else {                                        # Wert nicht in der Map
            Log3 $name, 3, "$name: Set: Value $setVal did not match defined map";
            return "Set Value $setVal did not match defined map";
        }
    } else {
       $rawVal = $setVal;
    }
    
    if ($rawVal =~ /^\s*-?\d+\.?\d*\s*$/) {             # a number (potentially with blanks)
        $rawVal =~ s/\s+//g if (!$textArg);             # remove blanks
        if ($setmin ne "") {        # 2. Schritt: falls definiert Min- und Max-Werte prüfen
            Log3 $name, 5, "$name: Set: checking value $rawVal against min $setmin";
            return "value $rawVal is smaller than min ($setmin)" if ($rawVal < $setmin);
        }
        if ($setmax ne "") {
            Log3 $name, 5, "$name: Set: checking value $rawVal against max $setmax";
            return "value $rawVal is bigger than max ($setmax)" if ($rawVal > $setmax);
        }
    } else {
        if (!$textArg) {
            Log3 $name, 3, "$name: Set: Value $rawVal is not numeric and textArg not specified";
            return "Set Value $rawVal is not numeric and textArg not specified";
        }
    }
    
    # 3. Schritt: Konvertiere mit setexpr falls definiert
    $rawVal = Modbus_CheckEval($hash, $rawVal, $setexpr, "Set", "setexpr for $setName") if ($setexpr);
        
    my $packedVal = pack ($unpack, $rawVal);
    Log3 $name, 5, "$name: set packed hex " . unpack ('H*', $rawVal) . " with $unpack to hex " . unpack ('H*', $packedVal);
    $packedVal = Modbus_RevRegs($hash, $packedVal, $len) if ($revRegs && $len > 1);
    $packedVal = Modbus_SwpRegs($hash, $packedVal, $len) if ($swpRegs);
    
    if (AttrVal($name, "nonPrioritizedSet", 0)) {
        ModbusLD_Send($hash, $objCombi, "write", $packedVal, 0);    # no force, just queue
    } else {
        ModbusLD_Send($hash, $objCombi, "write", $packedVal, 1);   # add at beginning and force send / sleep if necessary
        ($err, $result) = ModbusLD_ReadAnswer($hash, $setName);
        Modbus_EndBUSY ($ioHash);       # set BUSY to 0, delete REQUEST, clear Buffer, do Profilig
        return $err if ($err);
    }
            
    if ($fCode == 15 || $fCode == 16) {
        # read after write
        Log3 $name, 5, "$name: Set: sending read after write";
        
        if (AttrVal($name, "nonPrioritizedSet", 0)) {
            ModbusLD_Send($hash, $objCombi, "read", 0, 0);      # no force, just queue
        } else {
            ModbusLD_Send($hash, $objCombi, "read", 0, 1);      # add at beginning and force send / sleep if necessary
            ($err, $result) = ModbusLD_ReadAnswer($hash, $setName);
            Modbus_EndBUSY ($ioHash);       # set BUSY to 0, delete REQUEST, clear Buffer, do Profilig
            return "$err (in read after write for FCode 16)" if ($err);          
        }
    }
    return;     # no return code if no error 
}


###############################################
# Called from get / set to get a direct answer
# called with logical device hash
# has to return a value and an error separately
# so set can ignore  the value and only return an error
# whereas get needs the value or error 
sub ModbusLD_ReadAnswer($;$)
{
    my ($hash, $reading) = @_;
    my $name  = $hash->{NAME};
    my $now   = gettimeofday();

    my $ioHash = ModbusLD_GetIOHash($hash); 
    my $ioName = $ioHash->{NAME};       
    Log3 $name, 3, "$name: _ReadAnswer called but IO Device is disabled" if (IsDisabled ($ioName));
    return ("IO Device is disabled", undef) if (IsDisabled ($ioName));
    return ("No FD", undef) if (!$ioHash);
    return ("No FD", undef) if ($^O !~ /Win/ && !defined($ioHash->{FD}));

    my $buf;
    my $rin = '';

    # get timeout. In case ReadAnswer is called after a delay
    # only wait for remaining time
    my $to   = ModbusLD_DevInfo($hash, "timing", "timeout", 2); 
    my $rest = ($ioHash->{nextTimeout} ? $ioHash->{nextTimeout} - $now : 0);
        
    if ($rest <= 0) {
        Log3 $name, 5, "$name: ReadAnswer called but timeout already over" .
            ($reading ? " requested reading was $reading" : "");
        return ("Timeout reading answer", undef);
    }
    if ($rest < $to) {
        Log3 $name, 5, "$name: ReadAnswer called and remaining timeout is $rest" .
            ($reading ? " requested reading is $reading" : "");
        $to = $rest;
    } else {
        Log3 $name, 5, "$name: ReadAnswer called" . ($reading ? " for $reading" : "");
    }
    
    delete $hash->{gotReadings}; 
    $reading = "" if (!$reading);

    Modbus_Profiler($ioHash, "Read");     
    for(;;) {

        if($^O =~ m/Win/ && $ioHash->{USBDev}) {        
            $ioHash->{USBDev}->read_const_time($to*1000);   # set timeout (ms)
            $buf = $ioHash->{USBDev}->read(999);
            if(length($buf) == 0) {
                my $logLvl = AttrVal($ioHash->{NAME}, "timeoutLogLevel", 3);
                Log3 $name, $logLvl, "$name: Timeout in ReadAnswer" . ($reading ? " for $reading" : "");
                Modbus_CountTimeouts ($ioHash);
                return ("Timeout reading answer", undef)
            }
        } else {
            if(!$ioHash->{FD}) {
                Log3 $name, 3, "$name: Device lost in ReadAnswer". ($reading ? " for $reading" : "");
                return ("Device lost when reading answer", undef);
            }

            vec($rin, $ioHash->{FD}, 1) = 1;    # setze entsprechendes Bit in rin
            my $nfound = select($rin, undef, undef, $to);
            if($nfound < 0) {
                next if ($! == EAGAIN() || $! == EINTR() || $! == 0);
                my $err = $!;
                DevIo_Disconnected($ioHash);
                Log3 $name, 3, "$name: ReadAnswer error: $err";
                return("Modbus_ReadAnswer error: $err", undef);
            }
            if($nfound == 0) {
                my $logLvl = AttrVal($ioHash->{NAME}, "timeoutLogLevel", 3);
                Log3 $name, $logLvl, "$name: Timeout2 in ReadAnswer" . ($reading ? " for $reading" : "");
                Modbus_CountTimeouts ($ioHash);
                return ("Timeout reading answer", undef);
            }

            $buf = DevIo_SimpleRead($ioHash);
            if(!defined($buf)) {
                Log3 $name, 3, "$name: ReadAnswer got no data" . ($reading ? " for $reading" : "");
                return ("No data", undef);
            }
        }

        if($buf) {
            $ioHash->{helper}{buffer} .= $buf;
            $now = gettimeofday();
            $hash->{helper}{lrecv}   = $now;
            $ioHash->{helper}{lrecv} = $now;
            Log3 $name, 5, "$name: ReadAnswer got: " . unpack ("H*", $ioHash->{helper}{buffer});
        }

        my $code = Modbus_ParseFrames($ioHash);
        if ($code) {
            if ($code ne "1") {
                Log3 $name, 5, "$name: ReadAnswer: ParseFrames returned error: $code";
                return ($code, undef);
            }

            Log3 $name, 5, "$name: ReadAnswer done" . ($reading ? ", reading is $reading" : "") .
                (defined($hash->{gotReadings}{$reading}) ? ", value: $hash->{gotReadings}{$reading}" : "");
            if ($reading && defined($hash->{gotReadings}{$reading})) {
                return (undef, $hash->{gotReadings}{$reading});     # no error
            }
            return (undef, undef);  # no error but also no value
        }
    }
    return ("no Data", undef);
}


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

#####################################
# called via internal timer from 
# logical device module with 
# update:name - name of logical device
#
sub ModbusLD_GetUpdate($) {
    my $param = shift;
    my ($calltype,$name) = split(':',$param);
    my $hash      = $defs{$name};   # hash des logischen Devices, da GetUpdate aus dem logischen Modul per Timer gestartet wird
    my $modHash   = $modules{$hash->{TYPE}};
    my $parseInfo = $modHash->{parseInfo};
    my $devInfo   = $modHash->{deviceInfo};
    my $now       = gettimeofday();
    my $ioHash    = ModbusLD_GetIOHash($hash);
    
    Log3 $name, 5, "$name: GetUpdate called";

    if ($calltype eq "update") {    ## todo check if interval > min
        ModbusLD_SetTimer($hash);
    }
    
    if (IsDisabled($name)) {
        Log3 $name, 5, "$name: GetUpdate called but device is disabled";
        return;
    }

    return if (!$ioHash);
    if ($ioHash->{STATE} eq "disconnected") {
        Log3 $name, 5, "$name: GetUpdate called, but device is disconnected";
        return;
    }
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
        my $reading    = ModbusLD_ObjInfo($hash, $objCombi, "reading");
        my $objHashRef = $parseInfo->{$objCombi};
        #my $devTypeRef = $devInfo->{$type};
        my $poll       = ModbusLD_ObjInfo($hash, $objCombi, "poll", "defPoll", 0);
        my $lastRead   = ($hash->{lastRead}{$objCombi} ? $hash->{lastRead}{$objCombi} : 0);
        Log3 $name, 5, "$name: GetUpdate check $objCombi => $reading, poll = $poll, last = $lastRead";
        
        if (($poll && $poll ne "once") || ($poll eq "once" && !$lastRead)) {
        
            my $delay = ModbusLD_ObjInfo($hash, $objCombi, "polldelay", "", "0.5");
            if ($delay =~ "^x([0-9]+)") {
                $delay = $1 * $hash->{INTERVAL};            # Delay als Multiplikator des Intervalls falls es mit x beginnt.
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
        $nextReading = ModbusLD_ObjInfo($hash, $nextObj, "reading");
        $nextLen     = ModbusLD_ObjInfo($hash, $nextObj, "len", "defLen", 1);
        $readList{$nextObj} = $nextLen;
        if ($obj && $maxLen){
            $nextSpan = ($nextAdr + $nextLen) - $adr;   # Combined length with next object
            if ($nextType eq $type && $nextSpan <= $maxLen && $nextSpan > $span) {
                Log3 $name, 5, "$name: Combine $reading ($obj) with $nextReading ($nextObj), ".
                    "span=$nextSpan, max=$maxLen, drop read for $nextObj";
                delete $readList{$nextObj};             # no individual read for this object, combine with last
                $span = $nextSpan;
                $readList{$obj} = $nextSpan;            # increase the length to include following object
                next;   # don't change current object variables
            } else {
                Log3 $name, 5, "$name: No Combine $reading / $obj with $nextReading / $nextObj, ".
                    "span $nextSpan > max $maxLen";
                $nextSpan = 0;
            }
        }
        ($obj, $type, $adr, $reading, $len, $span) = ($nextObj,  $nextType, $nextAdr, $nextReading, $nextLen, $nextSpan);
        $maxLen = ModbusLD_DevInfo($hash, $type, "combine", 1);
        # Log3 $name, 5, "$name: GetUpdate: combine for $type is $maxLen";    
    }

    if (AttrVal($name, "sortUpdate", 0)) {
        Log3 $name, 5, "$name: sort objList before sending requests";
        foreach my $objCombi (sort Modbus_compObjKeys keys %readList) {
            my $span = $readList{$objCombi};
            ModbusLD_Send($hash, $objCombi, "read", 0, 0, $span);
        }
    } else {
        Log3 $name, 5, "$name: don't sort objList before sending requests";
        while (my ($objCombi, $span) = each %readList) {
            ModbusLD_Send($hash, $objCombi, "read", 0, 0, $span);
        }
    }
    Modbus_Profiler($ioHash, "Idle");   
    return;
}



######################################
# called from logical device fuctions 
# with log dev hash to get the 
# physical io device hash

sub ModbusLD_GetIOHash($){
    my $hash   = shift;
    my $name   = $hash->{NAME};             # name of logical device
    my $ioHash;
    
    #Log3 $name, 5, "$name: GetIOHash, TYPE = $hash->{TYPE}" . ($hash->{DEST} ? ", DEST = $hash->{DEST}" : "");
    if ($hash->{TYPE} eq "Modbus") {
        # physical Device
        return $hash;
    } else {
        # logical Device
        if ($hash->{DEST}) {
            return $hash;                               # Modbus TCP/RTU/ASCII über TCP, physical hash = logical hash
        } else {
            return $hash->{IODev} if ($hash->{IODev});  # logical device needs pointer to physical device (IODev)
            if (ModbusLD_SetIODev($hash)) {
                return $hash->{IODev};
            }
            Log3 $name, 3, "$name: no IODev attribute or matching physical Modbus-device found for $hash->{NAME}";
        }
    }
    return;
}


#####################################
# called from send and parse
# reverse order of word registers
sub Modbus_RevRegs($$$) {
    my ($hash, $buffer, $len) = @_;             # hash only needed for logging
    my $name = $hash->{NAME};                   # name of device for logging

    Log3 $name, 5, "$name: RevRegs: reversing order of up to $len registers";
    my $work = substr($buffer, 0, $len * 2);    # the first 2*len bytes of buffer
    my $rest = substr($buffer, $len * 2);       # everything after len
    
    my $new = "";
    while ($work) {
        $new = substr($work, 0, 2) . $new;      # prepend first two bytes of work to new
        $work = substr($work, 2);               # remove first word from work
    }
    Log3 $name, 5, "$name: RevRegs: string before is " . unpack ("H*", $buffer);
    $buffer = $new . $rest;
    Log3 $name, 5, "$name: RevRegs: string after  is " . unpack ("H*", $buffer);
    return $buffer;
}


#####################################
# called from send and parse
# reverse byte order in word registers
sub Modbus_SwpRegs($$$) {
    my ($hash, $buffer, $len) = @_;             # hash only needed for logging
    my $name = $hash->{NAME};                   # name of device for logging

    Log3 $name, 5, "$name: SwpRegs: reversing byte order of up to $len registers";
    my $rest = substr($buffer, $len * 2);       # everything after len
    my $nval = "";
    for (my $i = 0; $i < $len; $i++) { 
        $nval = $nval . substr($buffer,$i*2 + 1,1) . substr($buffer,$i*2,1);
    }; 
    Log3 $name, 5, "$name: SwpRegs: string before is " . unpack ("H*", $buffer);
    $buffer = $nval . $rest;
    Log3 $name, 5, "$name: SwpRegs: string after  is " . unpack ("H*", $buffer);
    return $buffer;
}



#####################################
# called from logical device functions 
# with log dev hash
sub ModbusLD_Send($$$;$$$){
    my ($hash, $objCombi, $op, $v1, $force, $reqLen) = @_;
    # $hash     : the logival Device hash
    # $objCombi : type+adr 
    # $op       : read, write or scanids/scanobj
    # $v1       : value for writing (already packed)
    # $force    : put in front of queue and don't reschedule but wait if necessary
    
    my $name    = $hash->{NAME};                # name of logical device
    my $devId   = ($op =~ /^scanid([0-9]+)/ ? $1 : $hash->{MODBUSID});
    my $proto   = $hash->{PROTOCOL};
    my $ioHash  = ModbusLD_GetIOHash($hash);
    my $type    = substr($objCombi, 0, 1);
    my $adr     = substr($objCombi, 1);
    my $reading = ModbusLD_ObjInfo($hash, $objCombi, "reading");
    my $objLen  = ModbusLD_ObjInfo($hash, $objCombi, "len", "defLen", 1);
    my $fcKey   = $op;
    if ($op =~ /^scan/) {
        $objLen = $reqLen;      # for scan there is no objLen but reqLen is given - avoid confusing log and set objLen ...
        $fcKey  = 'read';
    }
    
    return if (!$ioHash); 
    my $ioName = $ioHash->{NAME};    
    my $qlen   = ($ioHash->{QUEUE} ? scalar(@{$ioHash->{QUEUE}}) : 0);
    
    Log3 $name, 3, "$name: _Send called but IO Device is disabled" if (IsDisabled ($ioName));

    Log3 $name, 4, "$name: Send called with $type$adr, objLen $objLen / reqLen " .
        ($reqLen ? $reqLen : "-") . " to id $devId, op $op, qlen $qlen" .
        ((defined($v1) && $op eq 'write') ? ", value hex " . unpack ('H*', $v1) : "");
    $reqLen = $objLen if (!$reqLen);    # reqLen given as parameter (only for combined read requests from GetUpdate or scans)
        
    my $unpack = ModbusLD_ObjInfo($hash, $objCombi, "unpack", "defUnpack", "n"); 
    if ($objLen < 2 && $unpack =~ /lLIqQfFNVD/) {
        Log3 $name, 3, "$name: _Send with unpack $unpack but len seems too small - please set obj-${objCombi}-Len!";
    }       
    
    if ($qlen && AttrVal($ioName, "dropQueueDoubles", 0)) {
        Log3 $name, 5, "$name: Send is checking if request is already in queue ($qlen requests)";
        foreach my $elem (@{$ioHash->{QUEUE}}) {
            Log3 $name, 5, "$name: is it $elem->{TYPE} $elem->{ADR} reqLen $elem->{LEN} to id $elem->{MODBUSID}?";
            if($elem->{ADR} == $adr && $elem->{TYPE} eq $type 
                && $elem->{LEN} == $reqLen && $elem->{MODBUSID} eq $devId) {
                Log3 $name, 4, "$name: request already in queue - dropping";
                return;
            }
        }
    }

    my $tid = int(rand(255));
    my %request;
    $request{DEVHASH}   = $hash;    # logical device in charge
    $request{TYPE}      = $type;    # type of object (cdih)
    $request{ADR}       = $adr;     # address of object
    $request{LEN}       = $reqLen;  # number of registers / length of object
    $request{READING}   = $reading; # reading name of the object
    $request{TID}       = $tid;     # transaction id for Modbus TCP
    $request{PROTOCOL}  = $proto;   # RTU / ASCII / ...
    $request{MODBUSID}  = $devId;   # ModbusId of the addressed device - coming from logical device hash
    $request{VALUE}     = $v1;      # Value to be written (set)
    $request{OPERATION} = $op;      # read / write / scan
    
    my $fCode = ModbusLD_DevInfo($hash, $type, $fcKey, $Modbus_defaultFCode{$type}{$fcKey}); 
    if (!$fCode) {
        Log3 $name, 3, "$name: Send did not find fCode for $fcKey type $type";
        return;
    }
    $request{FCODE} = $fCode;   # function code
    
    Log3 $name, 4, "$name: Send" .
        ($force ? " adds " : " queues ") .
        "fc $fCode to $devId" .
        ($proto eq "TCP" ? ", tid $tid" : "") . ", for $type$adr" .
        ($reading ? " ($reading)" : "") . ", reqLen $reqLen" .
        ((defined($v1) && $op eq 'write') ? ", value hex " . unpack ('H*', $v1) : "") .
        ($force ? " at beginning of queue for immediate sending" : "");
    
    if(!$qlen) {
        #Log3 $name, 5, "$name: Send is creating new queue";
        $ioHash->{QUEUE} = [ \%request ];
    } else {
        #Log3 $name, 5, "$name: Send initial queue length is $qlen";
        if ($qlen > AttrVal($name, "queueMax", 100)) {
            Log3 $name, 3, "$name: Send queue too long ($qlen), dropping new request";
        } else {
            if ($force) {
                unshift (@{$ioHash->{QUEUE}}, \%request);   # an den Anfang
            } else {
                push(@{$ioHash->{QUEUE}}, \%request);       # ans Ende
            }
        }
    }
    Modbus_HandleSendQueue("direct:".$ioName, $force); # name is physical device
    return;
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
        <li><b>queueDelay</b></li> 
            modify the delay used when sending requests to the device from the internal queue, defaults to 1 second <br>
        <li><b>busDelay</b></li> 
            defines a delay that is always enforced between the last read from the bus and the next send to the bus for all connected devices<br>
        <li><b>clientSwitchDelay</b></li> 
            defines a delay that is always enforced between the last read from the bus and the next send to the bus for all connected devices but only if the next send goes to a different device than the last one<br>
        <li><b>dropQueueDoubles</b></li> 
            prevents new request to be queued if the same request is already in the send queue<br>
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

