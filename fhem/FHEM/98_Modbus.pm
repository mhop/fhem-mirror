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
#
#               
#
#   ToDo / Ideas : 
#
#                   scanner für ids
#                   don't insist on h1 instead of h001 (check with added 0's)?
#                   scanner für objekte, range in attrs erzeugt gefundene attr objekte und reading 
#                       mit Format varianten - siehe ipad notizen
#                   passive listening to other modbus traffic (state machine, parse requests of others in special queue
#                   test modbus tcp ohne dass ein physische gerät existiert
#
#                   Länge der Antwort bei fcode 3 und 4 aus der angefragten Länge ermitteln und 
#                       dann erst bei genügend Bytes crc prüfen.
#                       bzw. len aus unpack ableiten oder Meldung wenn zu klein
#
#                   todos in parseframes und parseobj geschrieben
#
#                   transform LD_Send to _Send (physical, only getting info from logical)
#                   move framing from send to handlesendqueue
#
#                   nonblocking disable attr für xp
#                   set definition with multiple requests as raw containig opt. readings / input
#                   attr prüfungen bei attrs, die nur für TCP sinnvoll sind -> ist es ein TCP Device?
#                   map mit spaces wie bei HTTPMOD
#                   :noArg etc. für Hintlist und userattr wie in HTTPMOD optimieren
#                   Input validation for define if interval is not numeric but TCP ...
#
#                   addToDevAttrList handling for wildcard attributes like in HTTPMOD
#                   Autoconfigure? (Combine testweise erhöhen, Fingerprinting -> DB?, ...?)
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
sub Modbus_ParseObj($$$;$);
sub Modbus_ParseFrames($);
sub Modbus_HandleSendQueue($;$);
sub Modbus_TimeoutSend($);
sub Modbus_CRC($);

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

my $Modbus_Version = '3.5.1 - 21.11.2016';

my %errCodes = (
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

my %defaultFCode = (
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
sub
Modbus_Initialize($)
{
    my ($modHash) = @_;

    require "$attr{global}{modpath}/FHEM/DevIo.pm";

    $modHash->{ReadFn}  = "Modbus_Read";
    $modHash->{ReadyFn} = "Modbus_Ready";
    $modHash->{DefFn}   = "Modbus_Define";
    $modHash->{UndefFn} = "Modbus_Undef";
  
    $modHash->{AttrList}= "do_not_notify:1,0 " . 
        "queueMax " .
        "queueDelay " .
        "busDelay " .
        "clientSwitchDelay " .
        "dropQueueDoubles " .
        "profileInterval " .
        $readingFnAttributes;
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
    my $ret;
    
    return "wrong syntax: define <name> $type [tty-devicename|none]"
        if(@a < 1);

    DevIo_CloseDev($ioHash);

    $ioHash->{RAWBUFFER} = "";
    $ioHash->{BUSY}      = 0;
    
    if($dev eq "none") {
        Log 1, "$name: device is none, commands will be echoed only";
        return undef;
    }
    $ioHash->{DeviceName} = $dev;           # needed by DevIo to get Device, Port, Speed etc.
    DevIo_OpenDev($ioHash, 0, 0);           # open physical device blocking (no nonblockingt TCP stuff here)
    
    return $ioHash->{FD} ? undef : "$dev could not be openend yet" . ($ret ? ". $ret" : "");
    
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
    # lösche auch die Verweise aus logischen Modulen auf dieses physische.
    foreach my $d (values %{$ioHash->{defptr}}) {
        Log3 $name, 3, "$name: Undef is removing IO device for $d->{NAME}";
        delete $d->{IODev};
        RemoveInternalTimer ("update:$d->{NAME}");
    }
    return undef;
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
sub ModbusLD_Notify($$)
{
    my ($hash, $source) = @_;
    my $name  = $hash->{NAME};              # my Name
    my $sName = $source->{NAME};            # Name of Device that created the events
    return if($sName ne "global");          # only interested in global Events

    my $events = deviceEvents($source, 1);
    return if(!$events);                    # no events
    
    # Log3 $name, 5, "$name: Notify called for source $source->{NAME} with events: @{$events}";
    return if (!grep(m/^INITIALIZED|REREADCFG$/, @{$events}));

    if ($hash->{DEST} && !AttrVal($name, "disable", undef)) {
        Modbus_Open($hash);
    }
    ModbusLD_SetTimer($hash, 1);     # first Update in 1 second or aligned

    return;
}


################################################
# Get Object Info from Attributes,
# parseInfo Hash or default from deviceInfo Hash
sub 
ModbusLD_ObjInfo($$$;$$) {
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
        # check for special case: attribute can be name of reading name with prefix like poll-reading
        return $attr{$name}{$oName."-".$reading} 
            if (defined($attr{$name}{$oName."-".$reading}));
        
        # check for explicit attribute for this object
        my $aName = "obj-".$key."-".$oName;
        return $attr{$name}{$aName} 
            if (defined($attr{$name}{$aName}));
        
        # default attribute for all objects (redundant with DevInfo attributes for all types)
        #my $adName = "obj-".$oName;
        #return $attr{$name}{$adName} 
        #   if (defined($attr{$name}{$adName}));
    }
    
    # parseInfo for object
    return $parseInfo->{$key}{$oName}
        if (defined($parseInfo->{$key}) && defined($parseInfo->{$key}{$oName}));
    
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
sub 
ModbusLD_DevInfo($$$;$) {
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
sub 
ModbusLD_ObjKey($$) {
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


#################################################
# Parse holding / input register / coil Data
# only called from parseframes 
#      which is only called from read / readanswer
#
# with logical device hash, data string
# and the object hash ref to start with
sub
Modbus_ParseObj($$$;$) {
    my ($logHash, $data, $objCombi, $quantity) = @_;
    my $name      = $logHash->{NAME};
    my $modHash   = $modules{$logHash->{TYPE}};
    my $parseInfo = $modHash->{parseInfo};
    my $devInfo   = $modHash->{deviceInfo};
    my $type      = substr($objCombi, 0, 1);
    my $startAdr  = substr($objCombi, 1);
    my $lastAdr   = ($quantity ? $startAdr + $quantity -1 : 0);
    my ($unpack, $format, $expr, $map, $rest, $len, $encode, $decode);
    Log3 $name, 5, "$name: ParseObj called with " . unpack ("H*", $data) . " and start $startAdr" .  ($quantity ? ", quantity $quantity" : "");

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
        my $key = $type . $startAdr;
        my $reading = ModbusLD_ObjInfo($logHash, $key, "reading");  # "" if nothing specified
        if ($reading) {
            if ($type =~ "[cd]") {
                $unpack    = "a";       # for coils just take the next 0/1 from the string
                $len       = 1;         # one byte contains one bit from the 01 string unpacked above
            } else {
                $unpack     = ModbusLD_ObjInfo($logHash, $key, "unpack", "defUnpack", "n"); # default to big endian unsigned int
                $len        = ModbusLD_ObjInfo($logHash, $key, "len", "defLen", 1);          # default to 1 Reg / 2 Bytes
                $encode     = ModbusLD_ObjInfo($logHash, $key, "encode", "defEncode");       # character encoding 
                $decode     = ModbusLD_ObjInfo($logHash, $key, "decode", "defDecode");       # character decoding 
                my $revRegs = ModbusLD_ObjInfo($logHash, $key, "revRegs", "defRevRegs");     # do not reverse register order by default
                my $swpRegs = ModbusLD_ObjInfo($logHash, $key, "bswapRegs", "defBswapRegs"); # dont reverse bytes in registers by default
                
                $rest = Modbus_RevRegs($logHash, $rest, $len) if ($revRegs && $len > 1);
                $rest = Modbus_SwpRegs($logHash, $rest, $len) if ($swpRegs);
            };
            $format  = ModbusLD_ObjInfo($logHash, $key, "format", "defFormat");          # no format if nothing specified
            $expr    = ModbusLD_ObjInfo($logHash, $key, "expr", "defExpr");              # no expr if not specified
            $map     = ModbusLD_ObjInfo($logHash, $key, "map", "defMap");                # no map if not specified
            Log3 $name, 5, "$name: ParseObj ObjInfo for $key: reading=$reading, unpack=$unpack, expr=$expr, format=$format, map=$map";
            
            my $val = unpack ($unpack, $rest);      # verarbeite so viele register wie passend (ggf. über mehrere Register)
            Log3 $name, 5, "$name: ParseObj unpacked " . unpack ('H*', $rest) . " with $unpack to " . unpack ('H*', $val);
  
            $val = decode($decode, $val) if ($decode);
            $val = encode($encode, $val) if ($encode);
            
            # Exp zur Nachbearbeitung der Werte?
            if ($expr) {
                Log3 $name, 5, "$name: ParseObj for $reading evaluates $val with expr $expr";
                $val = eval($expr);
            }
            # Map zur Nachbereitung der Werte?
            if ($map) {
                my %map = split (/[,: ]+/, $map);
                Log3 $name, 5, "$name: ParseObj for $reading maps value $val with " . $map;
                $val = $map{$val} if ($map{$val});
            }
            # Format angegeben?
            if ($format) {
                Log3 $name, 5, "$name: ParseObj for $reading does sprintf with format " . $format .
                    " value is $val";
                $val = sprintf($format, $val);
                Log3 $name, 5, "$name: ParseObj for $reading sprintf result is $val";
            }
            Log3 $name, 4, "$name: ParseObj for $reading assigns $val";
            readingsBulkUpdate($logHash, $reading, $val);
            $logHash->{lastRead}{$key}        = gettimeofday();
            $logHash->{gotReadings}{$reading} = $val;
        } else {
            Log3 $name, 5, "$name: ParseObj has no parseInfo for $key";
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
}


#####################################
sub 
Modbus_Statistics($$$)
{
    my ($hash, $key, $value) = @_;
    my $name = $hash->{NAME};
    #my ($seconds, $minute, $hour, @rest) = localtime (gettimeofday());

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
}


#####################################
sub 
Modbus_Profiler($$)
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
    my $chkLen  = $reqLen * 2;                  # in bytes for later compare
    my ($null, $dlen, $devAdr, $pdu, $fCode, $data, $eCRC, $CRC);
    my $tid     = 0;
    
    return "got data but did not send a request - ignoring" if (!$ioHash->{REQUEST});
    #Log3 $name, 5, "$name: ParseFrames got: " . unpack ('H*', $frame);
    
    use bytes;
    if ($proto eq "RTU") {
        if ($frame =~ /(..)(.+)(..)/s) {        # (id fCode) (data) (crc)     /s means treat as single line ...
            ($devAdr, $fCode) = unpack ('CC', $1);
            $data   = $2;
            $eCRC   = unpack ('v', $3);         # Header CRC - thats what we expect to calculate
            $CRC   = Modbus_CRC($1.$2);         # calculated CRC of data
        } else {
            return undef;                       # data still incomplete - continue reading
        }
    } elsif ($proto eq "ASCII") {
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
                $frame = substr($frame, $dlen + 6);
                return ("got wrong tid ($tid)", undef);
            }   
        }         
        if (length($pdu) + 1 < $dlen) {
            Log3 $name, 5, "$name: ParseFrames: Modbus TCP PDU too small (expect $dlen): " . (length($pdu) + 1);
            return undef;
        }
        ($fCode, $data) = unpack ('Ca*', $pdu);            
    }
    
    Log3 $name, 3, "$name: ParseFrames got a copy of the request sent before - looks like an echo!"
        if ($frame eq $ioHash->{REQUEST}{FRAME});

    return "recieved frame from unexpected Modbus Id $devAdr, " .
            "expecting fc $ioHash->{REQUEST}{FCODE} from $reqId for module $logHash->{NAME}"
        if ($devAdr != $reqId && $reqId != 0);

    return "unexpected function code $fCode from $devAdr, ".
            "expecting fc $ioHash->{REQUEST}{FCODE} from $reqId for module $logHash->{NAME}"
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
        $actualLen            = length ($values);
    } elsif ($fCode == 5) {                                 # write single coil,                pdu: adr, coil (FF00)
        ($parseAdr, $values) = unpack ('nH4', $data);  
        $values              = ($values eq "ff00" ? 1 : 0);
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
        my $hexdata  = unpack ("H*", $data);
        my $hexFCode = unpack ("H*", pack("C", $fCode));
        my $errCode      = $errCodes{$hexdata};
        Log3 $name, 5, "$name: ParseFrames got error code $hexFCode / $hexdata" . 
            ($errCode ? ", $errCode" : "");
        return "device replied with exception code $hexFCode / $hexdata" . ($errCode ? ", $errCode" : "");
    } else {
        if ($headerLen > $actualLen) {
            Log3 $name, 5, "$name: ParseFrames: wait for more data ($actualLen / $headerLen)";
            return undef;
        }
        return "ParseFrames got wrong Checksum (expect $eCRC, got $CRC)" if ($eCRC != $CRC);
        Log3 $name, 4, "$name: ParseFrames got fcode $fCode from $devAdr, tid $tid, ".
            "values " . unpack ('H*', $values) . " request was for $type.$parseAdr ($ioHash->{REQUEST}{READING})".
            ", len $reqLen for module $logHash->{NAME}";
        if ($fCode < 15) {
            # nothing to parse after reply to 15 / 16
            Modbus_ParseObj($logHash, $values, $type.$parseAdr, $quantity);     
            Log3 $name, 5, "$name: ParseFrames got " . scalar keys (%{$logHash->{gotReadings}}) . " readings from ParseObj";
        } else {
            Log3 $name, 5, "$name: reply to fcode 15 and 16 does not contain values";
        }
        return 1;
    }
}



#####################################
# End of BUSY
# called with physical device hash
sub
Modbus_EndBUSY($)
{
    my $hash = shift;
    my $name = $hash->{NAME};

    $hash->{helper}{buffer} = "";
    $hash->{BUSY} = 0;
    delete $hash->{REQUEST};
    Modbus_Profiler($hash, "Idle"); 
    RemoveInternalTimer ("timeout:$name");
}


#####################################
# Called from the global loop, when the select for hash->{FD} reports data
# hash is hash of logical device ( = physical device for TCP)
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
}


###########################
# open connection 
sub Modbus_Open($;$)
{
    my ($hash, $reopen) = @_;
    my $name = $hash->{NAME};
    my $now  = gettimeofday();
    $reopen  = 0 if (!$reopen);
    
    if ($hash->{BUSY_OPENDEV}) {  # still waiting for callback to last open 
        if ($hash->{LASTOPEN} && $now > $hash->{LASTOPEN} + (AttrVal($name, "timeout", 2)*2)
                              && $now > $hash->{LASTOPEN} + 15) {
            Log3 $name, 5, "$name: _Open - still waiting for open callback, timeout is over twice - this should never happen";
            Log3 $name, 5, "$name: _Open - stop waiting and reset the flag.";
            $hash->{BUSY_OPENDEV} = 0;
        } else {
            Log3 $name, 5, "$name: _Open - still waiting for open callback";
            return;
        }
    }    
    Log3 $name, 3, "$name: trying to open connection to $hash->{DeviceName}" if (!$reopen);
    $hash->{IODev}         = $hash if ($hash->{DEST});      # for TCP Log-Module himself is IODev (this is removed during CloseDev) 
    $hash->{RAWBUFFER}     = "";
    $hash->{BUSY}          = 0;   
    $hash->{BUSY_OPENDEV}  = 1;
    $hash->{LASTOPEN}      = $now;
    $hash->{nextOpenDelay} = AttrVal($name, "nextOpenDelay", 60);    
    DevIo_OpenDev($hash, $reopen, 0, \&Modbus_OpenCB);
}


# ready fn for physical and tcp 
#####################################
sub
Modbus_Ready($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};
    
    if($hash->{STATE} eq "disconnected") {  
        if (AttrVal($name, "disable", undef)) {
            Log3 $name, 3, "$name: _Reconnect: $name attr disabled was set - don't try to reconnect";
            DevIo_CloseDev($hash);
            $hash->{RAWBUFFER}     = "";
            $hash->{BUSY}          = 0;                         
            return;
        }
        Modbus_Open($hash, 1);  # reopen
        return;     # a return value only triggers direct read for windows - next round in main loop will select for available data
    }
    # This is relevant for windows/USB only
    my $po = $hash->{USBDev};
    if ($po) {
        my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
        return ($InBytes>0);    # tell fhem.pl to read when we return
    }
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


###################################################
# reconnect TCP connection (called from ControlSet)
sub Modbus_Reconnect($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $dest = $hash->{DEST};
    
    if (!$dest) {                            
        Log3 $name, 3, "$name: not using a TCP connection, reconnect not supported";
        return;
    }
    
    if (AttrVal($name, "disable", undef)) {
        Log3 $name, 3, "$name: _Reconnect: $name attr disabled was set - don't try to reconnect";
        DevIo_CloseDev($hash);
        $hash->{RAWBUFFER}     = "";
        $hash->{BUSY}          = 0;                         
        return;
    }
    
    DevIo_CloseDev($hash);
    delete $hash->{NEXT_OPEN};
    delete $hash->{DevIoJustClosed};
    Modbus_Open($hash);
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
}


#######################################
# Aufruf aus InternalTimer mit "timeout:$name" 
# wobei name das physical device ist
sub
Modbus_TimeoutSend($)
{
    my $param = shift;
    my (undef,$name) = split(':',$param);
    my $ioHash = $defs{$name};

    Log3 $name, 4, "$name: timeout waiting for $ioHash->{REQUEST}{FCODE} " .
                "from $ioHash->{REQUEST}{MODBUSID}, " .
                "Request was $ioHash->{REQUESTHEX}, " .
                "last Buffer: $ioHash->{RAWBUFFER}";

    Modbus_Statistics($ioHash, "Timeouts", 1);
        
    Modbus_EndBUSY ($ioHash);       # set BUSY to 0, delete REQUEST, clear Buffer, do Profilig
    
    Modbus_CountTimeouts ($ioHash);

    Modbus_HandleSendQueue ("direct:$name"); # verwaltet auch idle und busy time statistics variables  
};


#######################################
# prüfe delays vor dem Senden
sub Modbus_CheckDelay($$$$$)
{
    my ($ioHash, $force, $title, $delay, $last) = @_;
    return if (!$delay);
    my $name = $ioHash->{NAME};
    my $lNam = $ioHash->{REQUEST}{DEVHASH}{NAME};
    my $now  = gettimeofday();
    my $t2   = $last + $delay;
    my $rest = $t2 - $now;
    
    #Log3 $name, 5, "$name: handle queue check $title ($delay) for $lNam: rest $rest";
    if ($rest > 0) {
        Modbus_Profiler($ioHash, "Delay");  
        if ($force) {
            Log3 $name, 4, "$name: CheckDelay $title for $lNam not over, sleep $rest forced";
            sleep $rest if ($rest > 0 && $rest < $delay);
        } else {
            InternalTimer($t2, "Modbus_HandleSendQueue", "queue:$name", 0);
            Log3 $name, 4, "$name: CheckDelay $title for $lNam not over, try again in $rest";
            return 1;
        }
    }   
}


#######################################
# Aufruf aus InternalTimer mit "queue:$name" 
# oder direkt mit "direkt:$name
# wobei name das physical device ist
sub Modbus_HandleSendQueue($;$)
{
  my (undef,$name) = split(':', shift);
  my $force  = shift;
  my $ioHash = $defs{$name};
  my $queue  = $ioHash->{QUEUE};
  my $now    = gettimeofday();
  
  #Log3 $name, 5, "$name: handle queue" . ($force ? ", force" : "");
  RemoveInternalTimer ("queue:$name");
  
  if(defined($queue) && @{$queue} > 0) {

    my $queueDelay  = AttrVal($name, "queueDelay", 1);  
  
    if ($ioHash->{STATE} eq "disconnected") {
        InternalTimer($now+$queueDelay, "Modbus_HandleSendQueue", "queue:$name", 0);
        Log3 $name, 4, "$name: handle queue: device is disconnected, dropping requests in queue";
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

    $ioHash->{REQUEST} = $queue->[0];
    my $bstring = $ioHash->{REQUEST}{FRAME};
    my $reading = $ioHash->{REQUEST}{READING};
    my $len     = $ioHash->{REQUEST}{LEN};
    my $tid     = $ioHash->{REQUEST}{TID};
    my $adr     = $ioHash->{REQUEST}{ADR}; 
    my $reqId   = $ioHash->{REQUEST}{MODBUSID};
    my $proto   = $ioHash->{REQUEST}{PROTOCOL};
    my $type    = $ioHash->{REQUEST}{TYPE};
    my $fCode   = $ioHash->{REQUEST}{FCODE};

    if($bstring ne "") {    # if something to send - do so 
        my $logHash = $ioHash->{REQUEST}{DEVHASH};
        #Log3 $name, 5, "$name: checks delays: lrecv = $ioHash->{helper}{lrecv}";
        
        # check defined delays
        if ($ioHash->{helper}{lrecv}) {
            #Log3 $name, 5, "$name: check busDelay ...";
            return if (Modbus_CheckDelay($ioHash, $force, 
                    "busDelay",
                    AttrVal($name, "busDelay", 0),
                    $ioHash->{helper}{lrecv}));
            #Log3 $name, 5, "$name: check clientSwitchDelay ...";       
            my $clSwDelay = AttrVal($name, "clientSwitchDelay", 0);
            if ($clSwDelay && $ioHash->{helper}{lid}
                && $reqId != $ioHash->{helper}{lid}) {
                return if (Modbus_CheckDelay($ioHash, $force, 
                        "clientSwitchDelay",
                        $clSwDelay, 
                        $ioHash->{helper}{lrecv}));
            }
        }
        if ($logHash->{helper}{lrecv}) {
            return if (Modbus_CheckDelay($ioHash, $force, 
                    "commDelay", 
                    ModbusLD_DevInfo($logHash, "timing", "commDelay", 0.1),
                    $logHash->{helper}{lrecv}));
        }
        if ($logHash->{helper}{lsend}) {
            return if (Modbus_CheckDelay($ioHash, $force, 
                    "sendDelay", 
                    ModbusLD_DevInfo($logHash, "timing", "sendDelay", 0.1),
                    $logHash->{helper}{lsend}));
        }
        
        Modbus_Profiler($ioHash, "Send");   
        $ioHash->{REQUESTHEX}     = unpack ('H*', $bstring); # for debugging / log
        $ioHash->{BUSY}           = 1;        # modbus bus is busy until response is received
        $ioHash->{helper}{buffer} = "";       # clear Buffer for reception
      
        Log3 $name, 4, "$name: HandleSendQueue sends fc $fCode to $reqId, tid $tid for $reading ($type$adr), len $len)";
        
        DevIo_SimpleWrite($ioHash, $bstring, 0);
        
        $now = gettimeofday();
        $ioHash->{helper}{lsend}  = $now;     # remember when last send to this bus
        $logHash->{helper}{lsend} = $now;     # remember when last send to this device
        $ioHash->{helper}{lid}    = $reqId;   # device id we talked to

        Modbus_Statistics($ioHash, "Requests", 1);
        Modbus_Profiler($ioHash, "Wait");   
        my $timeout   = ModbusLD_DevInfo($logHash, "timing", "timeout", 2);
        RemoveInternalTimer ("timeout:$name");
        InternalTimer($now+$timeout, "Modbus_TimeoutSend", "timeout:$name", 0);
    }
    shift(@{$queue});           # remove first element from queue
    if(@{$queue} > 0) {         # more items in queue -> schedule next handle 
      InternalTimer($now+$queueDelay, "Modbus_HandleSendQueue", "queue:$name", 0);
    }
  }
}



##################################################
#
# Funktionen für logische Geräte 
# zum Aufruf aus anderen Modulen
#
##################################################


#####################################
sub
ModbusLD_Initialize($ )
{
    my ($modHash) = @_;

    $modHash->{DefFn}     = "ModbusLD_Define";    # functions are provided by the Modbus base module
    $modHash->{UndefFn}   = "ModbusLD_Undef";
    $modHash->{ReadFn}    = "Modbus_Read";
    $modHash->{ReadyFn}   = "Modbus_Ready";
    $modHash->{AttrFn}    = "ModbusLD_Attr";
    $modHash->{SetFn}     = "ModbusLD_Set";
    $modHash->{GetFn}     = "ModbusLD_Get";
    $modHash->{NotifyFn}  = "ModbusLD_Notify";


    $modHash->{AttrList}= 
        "do_not_notify:1,0 " . 
        "IODev " .                              # fhem.pl macht dann $hash->{IODev} = $defs{$ioname}
        "alignTime " .
        "enableControlSet:0,1 " .
        "nextOpenDelay " .
        "disable:0,1 " .
        "maxTimeoutsToReconnect " .             # for Modbus over TCP/IP only
        
        "(get|set)([0-9]+)request([0-9]+) " .

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
        "obj-[cdih][0-9]+-format " .
        "obj-[cdih][0-9]+-showGet " .
        "obj-[cdih][0-9]+-poll " .
        "obj-[cdih][0-9]+-polldelay ";
        
    $modHash->{DevAttrList} = 
        "dev-([cdih]-)*read " .
        "dev-([cdih]-)*write " .
        "dev-([cdih]-)*combine " .

        "dev-([cdih]-)*defRevRegs " .
        "dev-([cdih]-)*defBswapRegs " .
        "dev-([cdih]-)*defLen " .
        "dev-([cdih]-)*defUnpack " .
        "dev-([cdih]-)*defDecode " .
        "dev-([cdih]-)*defEncode " .
        "dev-([cdih]-)*defExpr " .
        "dev-([cdih]-)*defFormat " .
        "dev-([cdih]-)*defShowGet " .
        "dev-([cdih]-)*defPoll " .

        "dev-timing-timeout " .
        "dev-timing-sendDelay " .
        "dev-timing-commDelay ";
        
    $modHash->{ScanAttrList} = 
        "scan-[cdih]-range " .
        "scan-modbusid-range ";
        
}


#####################################
sub
ModbusLD_SetIODev($)
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

    $hash->{IODev} = $ioHash;                           # point internal IODev to io device hash
    $hash->{IODev}{defptr}{$hash->{MODBUSID}} = $hash;  # register this logical device for given id at io hash
    Log3 $name, 5, "$name: SetIODev is using $ioHash->{NAME}";
    return $ioHash;
}


# 
#########################################################################
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
}


#####################################
sub
ModbusLD_Define($$)
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
        
    $hash->{NOTIFYDEV} = "global";                  # NotifyFn nur aufrufen wenn global events (INITIALIZED)
    # löschen ist möglich mit $hash->{NOTIFYDEV} = ",";
    
    $hash->{ModuleVersion} = $Modbus_Version;
    $hash->{MODBUSID} = $id;
    $hash->{INTERVAL} = $interval;
    $hash->{PROTOCOL} = $proto;    
    $hash->{'.getList'}  = "";
    $hash->{'.setList'}  = "";
    $hash->{".updateSetGet"} = 1;

    #Log3 $name, 3, "$name: _define called with destination $dest, protocol $proto";
    
    my $msg;
    if ($dest) {                                    # Modbus über TCP mit IP Adresse angegeben (TCP oder auch RTU/ASCII über TCP)
        $dest .= ":502" if ($dest !~ /.*:[0-9]/);   # add default port if no port specified
        $hash->{DEST}          = $dest;  
        $hash->{IODev}         = $hash;             # Modul ist selbst IODev
        $hash->{defptr}{$id}   = $hash;             # ID verweist zurück auf eigenes Modul  
        $hash->{DeviceName}    = $dest;             # needed by DevIo to get Device, Port, Speed etc.
        $hash->{STATE}         = "disconnected";    # initial value
        # Modbus_Open($hash);   # now done in NotifyFn after INIT
    } else {
        # logical device that uses a physical Modbus device
        $hash->{DEST} = "";
        if (ModbusLD_SetIODev($hash)) {             # physical device found and asigned as IODev
            $dest = "Device $hash->{IODev}{NAME}";  # display name of IODev in Log
            $hash->{STATE} = "opened";
        } else {
            $hash->{STATE} = "no IO Dev";
            $msg = "but no physical modbus device defined";
            $dest = "none";
        }
    }

    Log3 $name, 3, "$name: defined with id $id, interval $interval, destination $dest, protocol $proto" .
        ($msg ? $msg : "");

    return;
}


#########################################################################
sub
ModbusLD_Attr(@)
{
    my ($cmd,$name,$aName,$aVal) = @_;
    my $hash = $defs{$name};        # hash des logischen Devices

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
            if ($ioHash && $ioHash->{TYPE} eq "MODBUS") {       # gibt es den Geräte hash zum IODev Attribut?
                $ioHash->{defptr}{$hash->{MODBUSID}} = $ioHash;  # register logical device
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
        }
        
        addToDevAttrList($name, $aName);
        $hash->{".updateSetGet"} = 1;
    }
    
    if ($aName eq 'disable') {
        if ($hash->{DEST}) {
            # take action only for Modbus TCP
            if ($cmd eq "set" && $aVal) {
                Log3 $name, 5, "$name: disable attribute set on a Modbus TCP connection" .
                    ($hash->{FD} ? ", closing connection" : "");
                DevIo_CloseDev($hash);
                $hash->{RAWBUFFER} = "";
                $hash->{BUSY}      = 0;                     
            } elsif ($cmd eq "del" || ($cmd eq "set" && !$aVal)) {
                Log3 $name, 5, "$name: disable attribute removed on a Modbus TCP connection";
                DevIo_CloseDev($hash);
                delete $hash->{NEXT_OPEN};
                delete $hash->{DevIoJustClosed};
                Modbus_Open($hash);
            }
        }
    }   
    return undef;
}


#####################################
sub
ModbusLD_Undef($$)
{
    my ($hash, $arg) = @_;
    my $name = $hash->{NAME};
    
    DevIo_CloseDev($hash) if ($hash->{DEST});   # logical Device over TCP - no underlying physical Device
    RemoveInternalTimer ("update:$name");
    RemoveInternalTimer ("timeout:$name");
    RemoveInternalTimer ("queue:$name"); 
    return undef;
}


#####################################
sub
ModbusLD_UpdateGetSetList($)
{
    my ($hash)    = @_;
    my $name      = $hash->{NAME};
    my $modHash   = $modules{$hash->{TYPE}};
    my $parseInfo = $modHash->{parseInfo};
    
    if (AttrVal($name, "enableControlSet", undef)) {        # spezielle Sets freigeschaltet?
        $hash->{'.setList'} = "interval reread:noArg reconnect:noArg stop:noArg start:noArg ";
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
    Log3 $name, 5, "$name: UpdateGetSetList full object list: " . join (" ",  @ObjList);
    
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
    Log3 $name, 5, "$name: UpdateSetList: setList=$hash->{'.setList'}";
    Log3 $name, 5, "$name: UpdateSetList: getList=$hash->{'.getList'}";
    $hash->{".updateSetGet"} = 0;
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
        Log3 $name, 5, "$name: Get: key for $getName = $objCombi";
    }

    if (!$objCombi) {
        ModbusLD_UpdateGetSetList($hash) if ($hash->{".updateSetGet"});
        Log3 $name, 5, "$name: Get: $getName not found, return list $hash->{'.getList'}"
            if ($getName ne "?");
        return "Unknown argument $a[1], choose one of $hash->{'.getList'}";
    }

    if (AttrVal($name, "disable", undef)) {
        Log3 $name, 5, "$name: get called with $getName but device is disabled"
            if ($getName ne "?");
        return undef;
    }

    my $ioHash  = ModbusLD_GetIOHash($hash);
    return undef if (!$ioHash);

    my ($err, $result);
    Log3 $name, 5, "$name: Get: Requesting $getName ($objCombi)";
    
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
        if (!$hash->{DEST}) {
            Log3 $name, 3, "$name: not using a TCP connection, reconnect not supported";
            return "0";
        }
        Modbus_Reconnect($hash);
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
        
    }
    return undef;   # no control set identified - continue with other sets
}


#####################################
sub
ModbusLD_Set($@)
{
    my ($hash, @a) = @_;
    return "\"set $a[0]\" needs at least an argument" if(@a < 2);
    my $name    = $hash->{NAME};
    my $setName = $a[1];
    my $setVal  = $a[2];
    my $rawVal  = "";
    
    if (AttrVal($name, "enableControlSet", undef)) {            # spezielle Sets freigeschaltet?
        my $error = ModbusLD_ControlSet($hash, $setName, $setVal);
        return undef if (defined($error) && $error eq "0");     # control set found and done.
        return $error if ($error);                              # error
        # continue if function returned undef
    }
    
    my $objCombi;
    if ($setName ne "?") {
        $objCombi = ModbusLD_ObjKey($hash, $setName);
        Log3 $name, 5, "$name: Set: key for $setName = $objCombi";
    }

    if (!$objCombi) {
        ModbusLD_UpdateGetSetList($hash) if ($hash->{".updateSetGet"});
        Log3 $name, 5, "$name: Set: $setName not found, return list $hash->{'.setList'}"
            if ($setName ne "?");
        return "Unknown argument $a[1], choose one of $hash->{'.setList'}";
    } 

    if (AttrVal($name, "disable", undef)) {
        Log3 $name, 4, "$name: set called with $setName but device is disabled"
            if ($setName ne "?");
        return undef;
    }   

    my $ioHash  = ModbusLD_GetIOHash($hash);    # get or reconstruct ioHash. reconnecton is done in Queue handling if necessary
    return undef if (!$ioHash);
    
    my $type = substr($objCombi, 0, 1);
    my ($err,$result);
    
    # todo: noarg checking?
    if (!defined($setVal)) {
        Log3 $name, 3, "$name: No Value given to set $setName";
        return "No Value given to set $setName";
    }
    Log3 $name, 5, "$name: Set: found option $setName ($objCombi), setVal = $setVal";

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
   
    my $fCode   = ModbusLD_DevInfo($hash, $type, "write", $defaultFCode{$type}{write});

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
    
    if ($rawVal =~ /^-?\d+\.?\d*$/) {
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
    
    if ($setexpr) {     # 3. Schritt: Konvertiere mit setexpr falls definiert
        my $val = $rawVal;
        $rawVal = eval($setexpr);
        Log3 $name, 5, "$name: Set: converted Value $val to $rawVal using expr $setexpr";
    }
        
    my $packedVal = pack ($unpack, $rawVal);
    Log3 $name, 5, "$name: set packed " . unpack ('H*', $rawVal) . " with $unpack to " . unpack ('H*', $packedVal);
    $packedVal = Modbus_RevRegs($hash, $packedVal, $len) if ($revRegs && $len > 1);
    $packedVal = Modbus_SwpRegs($hash, $packedVal, $len) if ($swpRegs);
    
    ModbusLD_Send($hash, $objCombi, "write", $packedVal, 1);   # add at beginning and force send / sleep if necessary
    ($err, $result) = ModbusLD_ReadAnswer($hash, $setName);
    Modbus_EndBUSY ($ioHash);       # set BUSY to 0, delete REQUEST, clear Buffer, do Profilig
    return $err if ($err);
            
    if ($fCode == 15 || $fCode == 16) {
        # read after write
        Log3 $name, 5, "$name: Set: sending read after write";
        
        ModbusLD_Send($hash, $objCombi, "read", 0, 1);      # add at beginning and force send / sleep if necessary
        ($err, $result) = ModbusLD_ReadAnswer($hash, $setName);
        Modbus_EndBUSY ($ioHash);       # set BUSY to 0, delete REQUEST, clear Buffer, do Profilig
        return "$err (in read after write for FCode 16)" if ($err);          
    }
    return undef;               # no return code if no error 
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
    return ("No FD", undef) if (!$ioHash);
    return ("No FD", undef) if ($^O !~ /Win/ && !defined($ioHash->{FD}));

    my $buf;
    my $rin = '';

    # get timeout. In case ReadAnswer is called after a delay
    # only wait for remaining time
    my $to   = ModbusLD_DevInfo($hash, "timing", "timeout", 2);
    my $arg  = "timeout:$ioHash->{NAME}";       # key in internl Timer hash
    my $rest = $to;
    # find internal timeout timer time and calculate remaining timeout
    foreach my $a (keys %intAt) {
        if($intAt{$a}{ARG} eq $arg) {
            $rest = $intAt{$a}{TRIGGERTIME} - $now;
        }
    }
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
                Log3 $name, 3, "$name: Timeout in ReadAnswer" . ($reading ? " for $reading" : "");
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
                Log3 $name, 3, "$name: Timeout2 in ReadAnswer" . ($reading ? " for $reading" : "");
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


#####################################
# called via internal timer from 
# logical device module with 
# update:name - name of logical device
#
sub
ModbusLD_GetUpdate($) {
    my $param = shift;
    my ($calltype,$name) = split(':',$param);
    my $hash      = $defs{$name};   # hash des logischen Devices, da GetUpdate aus dem logischen Modul per Timer gestartet wird
    my $modHash   = $modules{$hash->{TYPE}};
    my $parseInfo = $modHash->{parseInfo};
    my $devInfo   = $modHash->{deviceInfo};
    my $now       = gettimeofday();
    my $ioHash    = ModbusLD_GetIOHash($hash);
    
    if ($calltype eq "update") {    ## todo check if interval > min
        ModbusLD_SetTimer($hash);
    }
    
    if (AttrVal($name, "disable", undef)) {
        Log3 $name, 5, "$name: GetUpdate called but device is disabled";
        return undef;
    }

    return if (!$ioHash);
    if ($ioHash->{STATE} eq "disconnected") {
        Log3 $name, 5, "$name: GetUpdate called, but device is disconnected";
        return;
    }
    Log3 $name, 5, "$name: GetUpdate called";
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
    
    # combine objects in Readlist by increasing the length of a first obejct and removing the second
    foreach $nextObj (sort keys %readList) {
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
    Modbus_Profiler($ioHash, "Idle");       
    while (my ($objCombi, $span) = each %readList) {
        ModbusLD_Send($hash, $objCombi, "read", 0, 0, $readList{$objCombi});    # readList contains length / span
    }
}



######################################
# called from logical device fuctions 
# with log dev hash to get the 
# physical io device hash

sub ModbusLD_GetIOHash($){
    my $hash   = shift;
    my $name   = $hash->{NAME};             # name of logical device
    my $ioHash;
    
    if ($hash->{TYPE} eq "MODBUS") {
        # physical Device
        return $hash;
    } else {
        # logical Device
        if ($hash->{DEST}) {
            # Modbus TCP/RTU/ASCII über TCP, physical hash = logical hash
            return $hash;
        } else {
            # logical device needs pointer to physical device (IODev)
            return $hash->{IODev} if ($hash->{IODev});
            # recreate $hash->{IODev} and defptr registration using attr or usable physical Modbus device
            if (ModbusLD_SetIODev($hash)) {
                return $hash->{IODev};
            }
            Log3 $name, 3, "$name: no IODev attribute or matching physical Modbus-device found for $hash->{NAME}";
        }
    }
    return undef;
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
# called from logical device fuctions 
# with log dev hash
sub ModbusLD_Send($$$;$$$){
    my ($hash, $objCombi, $op, $v1, $force, $span) = @_;
    # $hash     : the logival Device hash
    # $objCombi : type+adr 
    # $op       : read, write
    # $v1       : value for writing
    # $force    : put in front of queue and don't reschedule but wait if necessary
    
    my $name    = $hash->{NAME};                # name of logical device
    my $devId   = $hash->{MODBUSID};
    my $proto   = $hash->{PROTOCOL};
    my $ioHash  = ModbusLD_GetIOHash($hash);
    my $type    = substr($objCombi, 0, 1);
    my $adr     = substr($objCombi, 1);
    my $reading = ModbusLD_ObjInfo($hash, $objCombi, "reading");
    my $len     = ModbusLD_ObjInfo($hash, $objCombi, "len", "defLen", 1);   
    
    return if (!$ioHash); 
    my $ioName = $ioHash->{NAME};    
    my $qlen = ($ioHash->{QUEUE} ? scalar(@{$ioHash->{QUEUE}}) : 0);

    Log3 $name, 4, "$name: Send called with $type$adr, len $len / span " .
        ($span ? $span : "-") . " to id $devId, queue has $qlen requests";
    $len = $span if ($span);    # span given as parameter (only for combined read requests from GetUpdate)
    
    if ($qlen && AttrVal($ioName, "dropQueueDoubles", 0)) {
        Log3 $name, 5, "$name: Send is checking if request is already in queue ($qlen requests)";
        foreach my $elem (@{$ioHash->{QUEUE}}) {
            Log3 $name, 5, "$name: is it $elem->{TYPE} $elem->{ADR} len $elem->{LEN} to id $elem->{MODBUSID}?";
            if($elem->{ADR} == $adr && $elem->{TYPE} eq $type 
                && $elem->{LEN} == $len && $elem->{MODBUSID} eq $devId) {
                Log3 $name, 4, "$name: request already in queue - dropping";
                return;
            }
        }
    }
    
    my $fCode  = ModbusLD_DevInfo($hash, $type, $op, $defaultFCode{$type}{$op}); 
    if (!$fCode) {
        Log3 $name, 3, "$name: Send did not find fCode for $op type $type (obj $reading)";
        return;
    }
    
    my $data;
    if ($fCode == 1 || $fCode == 2) {           # read coils / discrete inputs, pdu: StartAdr, Len (=number of coils)
        $data = pack ('nn', $adr, $len);        
    } elsif ($fCode == 3 || $fCode == 4) {      # read holding/input registers, pdu: StartAdr, Len (=number of regs)
        $data = pack ('nn', $adr, $len);
    } elsif ($fCode == 5) {                     # write single coil,            pdu: StartAdr, Value (1-bit as FF00)
        $data = pack ('nH4', $adr, ($v1 ? "FF00" : "0000"));
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
    #Log3 $name, 5, "$ioName: Send fcode $fCode for $reading, pdu : " . unpack ('H*', $pdu);
    
    my $frame;
    my $tid = 0;
    my $packedId = pack ('C', $devId);
    
    if ($proto eq "RTU") {           # frame format: DevID, (fCode, data), CRC
        my $crc    = pack ('v', Modbus_CRC($packedId . $pdu));
        $frame     = $packedId . $pdu . $crc;
    } elsif ($proto eq "ASCII") {    # frame format: DevID, (fCode, data), LRC
        my $lrc    = uc(unpack ('H2', pack ('v', Modbus_LRC($packedId.$pdu))));
        #Log3 $name, 5, "$name: LRC: $lrc";
        $frame     = ':' . uc(unpack ('H2', $packedId) . unpack ('H*', $pdu)) . $lrc . "\r\n";
    } elsif ($proto eq "TCP") {      # frame format: tid, 0, len, DevID, (fCode, data)
        $tid       = int(rand(255));
        my $dlen   = bytes::length($pdu)+1;         # length of pdu + devId
        my $header = pack ('nnnC', ($tid, 0, $dlen, $devId));
        $frame     = $header.$pdu;
        #Log3 $name, 5, "$ioName: Send TCP frame tid=$tid, dlen=$dlen, devId=$devId, pdu=" . unpack ('H*', $pdu);
    }
    
    Log3 $name, 4, "$name: Send queues fc $fCode to $devId, tid $tid for $type$adr ($reading), len/span $len, PDU " . 
        unpack ('H*', $pdu) . ($force ? ", force" : "");
    
    my %request;
    $request{FRAME}     = $frame;   # frame as data string
    $request{DEVHASH}   = $hash;    # logical device in charge
    $request{FCODE}     = $fCode;   # function code
    $request{TYPE}      = $type;    # type of object (cdih)
    $request{ADR}       = $adr;     # address of object
    $request{LEN}       = $len;     # span / number of registers / length of object
    $request{READING}   = $reading; # reading name of the object
    $request{TID}       = $tid;     # transaction id for Modbus TCP
    $request{PROTOCOL}  = $proto;   # RTU / ASCII / ...
    $request{MODBUSID}  = $devId;   # ModbusId of the addressed device - coming from logical device hash
    
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
    This version of the Modbus module supports Modbus RTU over serial / RS485 lines as well as Modbus TCP and Modbus RTU over TCP.
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
        <li><b>queueMax</b></li> 
            max length of the send queue, defaults to 100<br>
        <li><b>dropQueueDoubles</b></li> 
            prevents new request to be queued if the same request is already in the send queue<br>
        <li><b>profileInterval</b></li> 
            if set to something non zero it is the time period in seconds for which the module will create bus usage statistics. 
            Pleas note that this number should be at least twice as big as the interval used for requesting values in logical devices that use this physical device<br>
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

