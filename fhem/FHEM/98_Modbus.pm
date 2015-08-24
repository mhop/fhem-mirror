##############################################
##############################################
##############################################
# $Id: 98_Modbus.pm 
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
#
#               TODO: revRegs und bswapRegs for writing values 
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
        "profileInterval " .
        $readingFnAttributes;
}


#####################################
# Define für das physische Basismodul
# modbus id, Intervall etc. gibt es hier nicht
# sondern im logischen Modul.
# entsprechend wird auch getUpdate im 
# logischen Modul aufgerufen.
sub
Modbus_Define($$)
{
    my ($ioHash, $def) = @_;
    my @a = split("[ \t]+", $def);
    my ($name, $type, $dev) = @a;
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
    return DevIo_OpenDev($ioHash, 0, 0);
}


#####################################
sub
Modbus_Undef($$)
{
    my ($ioHash, $arg) = @_;
    my $name = $ioHash->{NAME};
    DevIo_CloseDev($ioHash); 
    RemoveInternalTimer ("timeout:$name");
    RemoveInternalTimer ("queue:$name");
    # lösche auch die Verweise aus logischen Modulen auf dieses physische.
    foreach my $d (values %{$ioHash->{defptr}}) {
        Log3 $name, 3, "removing IO device for $d->{NAME}";
        delete $d->{IODev};
        RemoveInternalTimer ("update:$d->{NAME}");
    }
    return undef;
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


#####################################
# Parse holding / input register / coil Data
# called from read via parseframes
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
    my ($unpack, $format, $expr, $map, $revRegs, $bswapRegs, $rest, $len, $encode, $decode);
    Log3 $name, 5, "$name: ParseObj called with " . unpack ("H*", $data) . " and start $startAdr" .  ($quantity ? ", quantity $quantity" : "");

    if ($type =~ "[cd]") {
        $quantity = 1 if (!$quantity);
        $rest = unpack ("b$quantity", $data);   # convert binary data to bit string
        Log3 $name, 5, "$name: ParseObj bit string: " . $rest . " and start $startAdr, quantity $quantity";
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
                $revRegs   = 0;         # not applicable
                $bswapRegs = 0;         # not applicable
            } else {
                $unpack  = ModbusLD_ObjInfo($logHash, $key, "unpack", "defUnpack", "n"); # default to big endian unsigned int
                $len       = ModbusLD_ObjInfo($logHash, $key, "len", "defLen", 1);          # default to 1 Reg / 2 Bytes
                $revRegs   = ModbusLD_ObjInfo($logHash, $key, "revRegs", "defRevRegs");     # do not reverse register order by default
                $bswapRegs = ModbusLD_ObjInfo($logHash, $key, "bswapRegs", "defBswapRegs"); # dont reverse bytes in registers by default
                $encode    = ModbusLD_ObjInfo($logHash, $key, "encode", "defEncode");       # character encoding 
                $decode    = ModbusLD_ObjInfo($logHash, $key, "decode", "defDecode");       # character decoding 
                if ($revRegs && $len > 1) {
                    Log3 $name, 5, "$name: ParseObj ObjInfo: reading=$reading: reversing order of registers before unpacking";
                    my $p1 = substr($rest, 0, $len * 2);    # the first len bytes
                    my $p2 = substr($rest, $len * 2);       # everything after len
                    my $pn = "";
                    while ($p1) {
                        $pn = substr($p1, 0, 2) . $pn;
                        $p1 = substr($p1, 2);
                    }
                    Log3 $name, 5, "$name: ParseObj ObjInfo: reading=$reading: data string before is " . unpack ("H*", $rest);
                    $rest = $pn . $p2;
                    Log3 $name, 5, "$name: ParseObj ObjInfo: reading=$reading: data string after is  " . unpack ("H*", $rest);
                } else {
                    #Log3 $name, 5, "$name: ParseObj ObjInfo: reading=$reading: NOT reversing order of registers, revRegs = $revRegs, len = $len ";
                }
                if ($bswapRegs && $len > 1) {
                    Log3 $name, 5, "$name: ParseObj ObjInfo: reading=$reading: reversing byte order of registers before unpacking";
                    my $nval = "";
                    for (my $i = 0; $i < $len; $i++) { 
                        $nval = $nval . substr($rest,$i*2 + 1,1) . substr($rest,$i*2,1);
                    }; 
                    Log3 $name, 5, "$name: ParseObj ObjInfo: reading=$reading: data string before is " . unpack ("H*", $rest);
                    $rest = $nval;
                    Log3 $name, 5, "$name: ParseObj ObjInfo: reading=$reading: data string after is " . unpack ("H*", $rest);
                }
            };
            $format  = ModbusLD_ObjInfo($logHash, $key, "format", "defFormat");          # no format if nothing specified
            $expr    = ModbusLD_ObjInfo($logHash, $key, "expr", "defExpr");              # no expr if not specified
            $map     = ModbusLD_ObjInfo($logHash, $key, "map", "defMap");                # no map if not specified
            Log3 $name, 5, "$name: ParseObj ObjInfo: reading=$reading, unpack=$unpack, expr=$expr, format=$format, map=$map";
            
            my $val = unpack ($unpack, $rest);      # verarbeite so viele register wie passend (ggf. über mehrere Register)
  
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
            $rest = substr($rest, 1);
            last if ($lastAdr && $startAdr > $lastAdr);
        } else {
            $startAdr += $len;
            $rest = substr($rest, $len * 2);    # take rest of rest starting at len*2 until the end  
        }
        Log3 $name, 5, "$name: ParseObj moves to next object, skip $len to $startAdr" if ($rest);
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
# Get log hash depending on modbus id in Frame read if through phys hash
# returns (err, data)
sub
Modbus_ParseFrames($)
{
    my $ioHash  = shift;                        # hash of io device given to function
    
    my $name    = $ioHash->{NAME};              # name of io device
    my $frame   = $ioHash->{helper}{buffer};    # frame is in buffer in io hash
    my $logHash = $ioHash->{REQUEST}{DEVICE};   # logical device hash is saved in io hash (or points back to self)
    my $type    = $ioHash->{REQUEST}{TYPE};
    my $adr     = $ioHash->{REQUEST}{ADR};
    my ($tid, $null, $dlen, $devAdr, $pdu, $fCode, $data, $crc, $crc2);
    
    if (!$logHash) {
        #Log3 $name, 3, "$name: ParseFrames has no device hash in last request";
        # todo - wenn WP ausgeschaltet, dann kommt bei Read Müll und bei Readanswer endlos Müll -> hört nie auf ...
        return ("no logical device identified", undef);
    }
    Log3 $name, 5, "$name: ParseFrames got: " . unpack ('H*', $frame);
    
    use bytes;
    if ($logHash->{PROTOCOL} eq "RTU") {
        # zerlege Frame in Device-Adresse, fCode und Data sowie CRC für Modbus RTU
        if ($frame =~ /(..)(.+)(..)/s) {        # id fCode data crc     /s means treat as single line ...
            ($devAdr, $fCode) = unpack ('CC', $1);
            $data   = $2;
            $crc    = unpack ('v', $3);
            $crc2   = Modbus_CRC($1.$2);
        } else {
            return (undef, undef);  # data still incomplete - continue reading
        }
        Log3 $name, 4, "$name: ParseFrames: fcode $fCode from $devAdr, data " . unpack ('H*', $data) . 
            " calc crc = $crc2, read = $crc" . ($crc == $crc2 ? " " : " -> mismatch!") .
            " expect $ioHash->{REQUEST}{FCODE} from $logHash->{MODBUSID} for module $logHash->{NAME}";
            
        if ($crc != $crc2) {                        
            Log3 $name, 5, "$name: ParseFrames got wrong crc and returns (maybe data is still incomplete)";
            return (undef, undef);      # Modbus Serial, data may still be incomplete
        }
        if ($logHash->{MODBUSID} != $devAdr) {
            Log3 $name, 5, "$name: ParseFrames got unexpected Device Id and returns";
            return ("wrong Device Id", undef)
        }
    } elsif ($logHash->{PROTOCOL} eq "TCP") {
        # zerlege Frame in TID, Len, Device-Adresse, fCode und Data für Modbus TCP
        #Log3 $name, 5, "$name: ParseFrames TCP handles frame " . unpack ('H*', $frame);
        if (length($frame) < 8) {
            Log3 $name, 5, "$name: ParseFrames length too small: " . length($frame);
            return (undef, undef);
        }
        ($tid, $null, $dlen, $devAdr, $pdu) = unpack ('nnnCa*', $frame);
        #Log3 $name, 5, "$name: ParseFrames unpacked tid=$tid, dlen=$dlen, id=$devAdr, pdu=" . unpack ('H*', $pdu);
        if (length($pdu) + 1 < $dlen) {
            Log3 $name, 5, "$name: ParseFrames length smaller than header len $dlen: " . (length($pdu) + 1);
            return (undef, undef);
        }
        ($fCode, $data) = unpack ('Ca*', $pdu);
        
        Log3 $name, 4, "$name: ParseFrames: fcode $fCode from $devAdr, tid $tid, data " . unpack ('H*', $data) . 
            " expect $ioHash->{REQUEST}{FCODE} from $logHash->{MODBUSID}, tid $ioHash->{REQUEST}{TID} for module $logHash->{NAME}";

        if ($logHash->{MODBUSID} != $devAdr) {
            Log3 $name, 5, "$name: ParseFrames got unexpected Device Id and returns";
            return ("wrong Device Id", undef)
        }   
    }
    
    if ($ioHash->{REQUEST}{FCODE} != $fCode && $fCode < 128) {
        Log3 $name, 5, "$name: ParseFrames got unexpected function code and returns";
        return ("unexpected function code", undef);
    }
    
    # frame received, now handle data
    $logHash->{helper}{lrecv} = gettimeofday();
    Modbus_Profiler($ioHash, "Fhem");
    
    if ($fCode == 1 || $fCode == 2) {           # reply to read coils / discrete inputs
        my ($bytes, $coils) = unpack ('Ca*', $data);
        my $rlen = length ($coils); 
        if ($bytes > $rlen) {
            Log3 $name, 5, "$name: ParseFrames expects $bytes, got $rlen, waiting fo the remaining bytes";
            return (undef, undef);      # data may be incomplete (very unlikely if not impossible ...)
        } 
        Modbus_ParseObj($logHash, $coils, $type.$adr, $ioHash->{REQUEST}{LEN});
        Log3 $name, 5, "$name: ParseFrames done, reply to fCode 1, " . scalar keys (%{$logHash->{gotReadings}}) . " readings";
        return (undef, $coils);
    } elsif ($fCode == 3 || $fCode == 4) {      # reply to read holding / input registers
        my ($bytes, $registers) = unpack ('Ca*', $data);
        my $rlen = length ($registers); 
        if ($bytes > $rlen) {
            Log3 $name, 5, "$name: ParseFrames expects $bytes, got $rlen, waiting fo the remaining bytes";
            return (undef, undef);      # data may be incomplete (very unlikely if not impossible ...)
        }
        Modbus_ParseObj($logHash, $registers, $type.$adr);
        Log3 $name, 5, "$name: ParseFrames done, reply to fCode $fCode, " . scalar keys (%{$logHash->{gotReadings}}) . " readings";
        return (undef, $registers);
    } elsif ($fCode == 5) {     # reply to write single coil
        my $rlen = length ($data); 
        if ($rlen < 4) {
            Log3 $name, 5, "$name: ParseFrames expects 4, got $rlen, waiting fo the remaining bytes";
            return (undef, undef);      # data may be incomplete (very unlikely if not impossible ...)
        }
        my ($radr, $coilCode) = unpack ('nH4', $data);  # todo: radr gegen adr testen?
        Log3 $name, 5, "$name: ParseFrames reply to fCode $fCode, coilCode $coilCode";
        Modbus_ParseObj($logHash, ($coilCode eq "ff00" ? 1 : 0), $type.$radr, 1);
        Log3 $name, 5, "$name: ParseFrames done, reply to fCode 6, " . scalar keys (%{$logHash->{gotReadings}}) . " readings";
        return (undef, $coilCode);      
    } elsif ($fCode == 6) {     # reply to write single (holding) register
        my $rlen = length ($data); 
        if ($rlen < 4) {
            Log3 $name, 5, "$name: ParseFrames expects 4, got $rlen, waiting fo the remaining bytes";
            return (undef, undef);      # data may be incomplete (very unlikely if not impossible ...)
        }
        my ($radr, $register) = unpack ('na*', $data);  # todo: radr gegen adr testen?
        Modbus_ParseObj($logHash, $register, $type.$radr);
        Log3 $name, 5, "$name: ParseFrames done, reply to fCode 6, " . scalar keys (%{$logHash->{gotReadings}}) . " readings";
        return (undef, $register);      
    } elsif ($fCode == 15 || $fCode == 16) {    # reply to write multiple coils / holding registers
        my $rlen = length ($data); 
        if ($rlen < 4) {
            Log3 $name, 5, "$name: ParseFrames expects 4, got $rlen, waiting fo the remaining bytes";
            return (undef, undef);      # data may be incomplete (very unlikely if not impossible ...)
        }
        my ($radr, $quantity) = unpack ('nn', $data);   # todo: radr gegen adr testen?
        Log3 $name, 5, "$name: ParseFrames done, reply to fcode 16, $quantity objects written";
        return (undef, $quantity);
    } elsif ($fCode >= 128) {   # error
        my $hexdata  = unpack ("H*", $data);
        my $hexFCode = unpack ("H*", pack("C", $fCode));
        my $err      = $errCodes{$hexdata};
        Log3 $name, 5, "$name: ParseFrames got error code $hexFCode / $hexdata" . 
            ($err ? ", $err" : "");
        return ("got exception code $hexFCode / $hexdata" . 
            ($err ? ", $err" : ""), undef);
    } else {    # other function code
        Log3 $name, 3, "$name: ParseFrames: function code $fCode not implemented";
        return ("function code $fCode not implemented", undef);
    }
    return ("internal module error in ParseFrames", undef);
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
# hash is hash of physical device or logical
# depending on PROTOCOL TCP / RTU
sub
Modbus_Read($)
{
    # physical layer function - read to common physical buffers ...
    my $hash = shift;
    my $name = $hash->{NAME};
    my $buf  = DevIo_SimpleRead($hash);
    return if(!defined($buf));

    Modbus_Profiler($hash, "Read");
    Log3 $name, 5, "$name: raw read: " . unpack ('H*', $buf);

    $hash->{helper}{buffer} .= $buf;  

    my ($err, $framedata) = Modbus_ParseFrames($hash);
    if ($framedata || $err) {
        Modbus_EndBUSY ($hash);         # set BUSY to 0, delete REQUEST, clear Buffer, do Profilig
        #Modbus_Statistics($hash, "BusyTime", gettimeofday() - $hash->{helper}{lsend});
        # Busy ist vorbei (hier oder bei Timeout), start in HandleSendQueue, lsend

        RemoveInternalTimer ("queue:$name"); 
        Modbus_HandleSendQueue ("direct:$name"); # don't wait for next regular handle queue slot
    }
}


#####################################
sub
Modbus_Ready($)
{
  my ($hash) = @_;
  return DevIo_OpenDev($hash, 1, undef)
                if($hash->{STATE} eq "disconnected");

  # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  
  return ($InBytes>0);
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
                "from $ioHash->{REQUEST}{DEVICE}{MODBUSID}, " .
                "Request was $ioHash->{REQUESTHEX}, " .
                "last Buffer: $ioHash->{RAWBUFFER}";

    Modbus_Statistics($ioHash, "Timeouts", 1);
        
    Modbus_EndBUSY ($ioHash);       # set BUSY to 0, delete REQUEST, clear Buffer, do Profilig

    Modbus_HandleSendQueue ("direct:$name"); # verwaltet auch idle und busy time statistics variables  
};


#######################################
# Aufruf aus InternalTimer mit "queue:$name" 
# oder direkt mit "direkt:$name
# wobei name das physical device ist
sub
Modbus_HandleSendQueue($;$)
{
  my (undef,$name) = split(':', shift);
  my $force  = shift;
  my $ioHash = $defs{$name};
  my $queue  = $ioHash->{QUEUE};
  my $now    = gettimeofday();
  
  #Log3 $name, 5, "$name: handle queue" . ($force ? ", force" : "");
  RemoveInternalTimer ("queue:$name");
  
  if(defined($queue) && @{$queue} > 0) {
  
    #if ($ioHash->{helper}{idlestart}) {
    #   Modbus_Statistics($ioHash, "IdleTime", $now - $ioHash->{helper}{idlestart});
    #   $ioHash->{helper}{idlestart} = 0;
    #   # falls bisher idle, jetzt ist es vorbei. Start wenn HandleSendQueue nichts mehr zu tun hat.
    #}
    #if (!$ioHash->{helper}{waitstart}) {
    #   $ioHash->{helper}{waitstart} = $now;
    #   # Zeit vom Aufruf HandleSendQueue bis zum erfolgreichen Senden (Teil von Busytime)
    #}

    my $queueDelay  = AttrVal($name, "queueDelay", 1);  
  
    if ($ioHash->{STATE} eq "disconnected") {
        InternalTimer($now+$queueDelay, "Modbus_HandleSendQueue", "queue:$name", 0);
        Log3 $name, 5, "$name: handle queue: device is disconnected, dropping requests in queue";
        Modbus_Profiler($ioHash, "Idle");   

        delete $ioHash->{QUEUE};
        return;
    } 
    if (!$init_done) {      # fhem not initialized, wait with IO
        InternalTimer($now+$queueDelay, "Modbus_HandleSendQueue", "queue:$name", 0);
        Log3 $name, 3, "$name: handle queue not available yet (init not done), try again in $queueDelay seconds";
        return;
    }
    if ($ioHash->{BUSY}) {  # still waiting for reply to last request
        InternalTimer($now+$queueDelay, "Modbus_HandleSendQueue", "queue:$name", 0);
        #Log3 $name, 5, "$name: handle queue busy, try again in $queueDelay seconds";
        #Modbus_Profiler($ioHash, "Wait");  
        return;
    }

    $ioHash->{REQUEST} = $queue->[0];
    my $bstring = $ioHash->{REQUEST}{FRAME};
    my $reading = $ioHash->{REQUEST}{READING};
    my $len     = $ioHash->{REQUEST}{LEN};
    
    if($bstring ne "") {    # if something to send - do so 
    
        my $logHash   = $ioHash->{REQUEST}{DEVICE};
        my $sendDelay = ModbusLD_DevInfo($logHash, "timing", "sendDelay", 0.1);
        my $commDelay = ModbusLD_DevInfo($logHash, "timing", "commDelay", 0.1);
        my $timeout   = ModbusLD_DevInfo($logHash, "timing", "timeout", 2);
        
        my ($t1, $t2, $tN) = (0,0,0);
        $t1 = $logHash->{helper}{lsend} + $sendDelay 
            if ($logHash->{helper}{lsend});
        $t2 = $logHash->{helper}{lrecv} + $commDelay
            if ($logHash->{helper}{lrecv});
        $tN = ($t1 > $t2 ? $t1 : $t2);
        
        if ($now < $t1) {
            Modbus_Profiler($ioHash, "Delay");  
            if ($force) {
                my $rest = $tN - gettimeofday();
                Log3 $name, 5, "$name: handle queue sendDelay for device $logHash->{NAME} not over, sleep $rest forced";
                sleep $rest if ($rest > 0 && $rest < $sendDelay);
                $now = gettimeofday();
            } else {
                InternalTimer($tN, "Modbus_HandleSendQueue", "queue:$name", 0);
                Log3 $name, 5, "$name: handle queue sendDelay for device $logHash->{NAME} not over, try again later";
                return;
            }
        }   
        if ($now < $t2) {
            Modbus_Profiler($ioHash, "Delay");  
            if ($force) {
                my $rest = $tN - gettimeofday();
                Log3 $name, 5, "$name: handle queue commDelay for device $logHash->{NAME} not over, sleep $rest forced";
                sleep $rest if ($rest > 0 && $rest < $commDelay);
                $now = gettimeofday();
            } else {
                InternalTimer($tN, "Modbus_HandleSendQueue", "queue:$name", 0);
                Log3 $name, 5, "$name: handle queue commDelay for device $logHash->{NAME} not over, try again later";
                return;
            }
        }   
        
        #if ($ioHash->{helper}{waitstart}) {
        #   Modbus_Statistics($ioHash, "WaitTime", gettimeofday() - $ioHash->{helper}{waitstart});
        #   # Wartezeit auf jeden Fall vorbei
        #}
        Modbus_Profiler($ioHash, "Send");   
        
        
        $ioHash->{REQUESTHEX}     = unpack ('H*', $bstring); # for debugging / log
        $ioHash->{BUSY}           = 1;        # modbus bus is busy until response is received
        $ioHash->{helper}{buffer} = "";       # clear Buffer for reception
        $ioHash->{helper}{lsend}  = $now;     # remember when last send to this bus
        $logHash->{helper}{lsend} = $now;     # remember when last send to this device
      
        Log3 $name, 4, "$name: handle queue sends $ioHash->{REQUESTHEX} " .
            "(fcode $ioHash->{REQUEST}{FCODE} to $ioHash->{REQUEST}{DEVICE}{MODBUSID} for $reading, len $len)";
        
        DevIo_SimpleWrite($ioHash, $bstring, 0);
        Modbus_Statistics($ioHash, "Requests", 1);
        Modbus_Profiler($ioHash, "Wait");   

        RemoveInternalTimer ("timeout:$name");
        InternalTimer($now+$timeout, "Modbus_TimeoutSend", "timeout:$name", 0);
    }
    shift(@{$queue});           # remove first element from queue
    if(@{$queue} > 0) {         # more items in queue -> schedule next handle 
      InternalTimer($now+$queueDelay, "Modbus_HandleSendQueue", "queue:$name", 0);
    }
  } else {
    #$ioHash->{helper}{idlestart} = $now;
  }
  #$ioHash->{helper}{waitstart} = 0;
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

    $modHash->{DefFn}   = "ModbusLD_Define";    # functions are provided by the Modbus base module
    $modHash->{UndefFn} = "ModbusLD_Undef";
    $modHash->{ReadFn}  = "Modbus_Read";
    $modHash->{ReadyFn} = "Modbus_Ready";
    $modHash->{AttrFn}  = "ModbusLD_Attr";
    $modHash->{SetFn}   = "ModbusLD_Set";
    $modHash->{GetFn}   = "ModbusLD_Get";
    $modHash->{AttrList}= 
        "do_not_notify:1,0 " . 
        "IODev " .                              # fhem.pl macht dann $hash->{IODev} = $defs{$ioname}
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
        "obj-[cdih][0-9]+-revRegs " .
        "obj-[cdih][0-9]+-bswapRegs " .
        "obj-[cdih][0-9]+-len " .
        "obj-[cdih][0-9]+-unpack " .
        "obj-[cdih][0-9]+-decode " .
        "obj-[cdih][0-9]+-encode " .
        "obj-[cdih][0-9]+-expr " .
        "obj-[cdih][0-9]+-format " .
        "obj-[cdih][0-9]+-showget " .
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
}


#####################################
sub
ModbusLD_SetIODev($)
{
    my ($hash) = @_;
    my $name   = $hash->{NAME};
    my $ioName = AttrVal($name, "IODev", "");
    my $ioDev;
    if ($ioName) {
        if ($defs{$ioName}) {         # gibt es den Geräte hash zum IODev Attribut?
            $ioDev = $defs{$ioName};
            Log3 $name, 5, "$name: SetIODev is using $ioName given in attribute";
        } else {
            Log3 $name, 3, "$name: SetIODev can't use $ioName - device does not exist";
        }
    }
    if (!$ioDev) {
        for my $p (sort { $defs{$b}{NR} <=> $defs{$a}{NR} } keys %defs) {
            if ( $defs{$p}{TYPE} eq "Modbus") {
                $ioDev = $defs{$p};
                last;
            }
        }
    }
    if ($ioDev) {
        $attr{$name}{IODev} = $ioDev->{NAME};       # set IODev attribute
        $hash->{IODev} = $ioDev;                    # set internal to io device hash
        Log3 $name, 5, "$name: SetIODev $ioDev->{NAME}";
    } else {
        Log3 $name, 3, "$name: SetIODev found no physical modbus device";
    }
    return $ioDev;
}


#####################################
sub
ModbusLD_Define($$)
{
    my ($hash, $def) = @_;
    my @a = split("[ \t]+", $def);
    my ($name, $module, $id, $interval, $dest, $proto) = @a;
    my $ret = "";
    
    return "wrong syntax: define <name> $module [id] [interval] [host:port] [RTU|ASCII|TCP]"
        if(@a < 2);

    # for TCP $id is an optional Unit ID that is ignored by most devices
    # but some gateways may use it to select the device to forward to.

    $id       = 1     if (!defined($id));
    $interval = 0     if (!defined($interval));
    $proto    = "RTU" if (!defined($proto));
    $dest     = ""    if (!defined($dest));
        
    $hash->{MODBUSID} = $id;
    $hash->{INTERVAL} = $interval;
    $hash->{PROTOCOL} = $proto;
    $hash->{DEST}     = $dest;  
    $hash->{".updateSetGet"} = 1;
    $hash->{getList} = "";
    $hash->{setList} = "";
    
    if ($dest) {                                    # Modbus TCP mit IP Adresse angegeben.                                                       
        $hash->{IODev}       = $hash;               # Modul ist selbst IODev
        $hash->{defptr}{$id} = $hash;               # ID verweist zurück auf eigenes Modul  
        $hash->{DeviceName}  = $dest;               # needed by DevIo to get Device, Port, Speed etc.
        $hash->{RAWBUFFER}   = "";
        $hash->{BUSY}        = 0;       
        $ret = DevIo_OpenDev($hash, 0, 0);
    } else {
        if (ModbusLD_SetIODev($hash)) {             # physical device found and asigned as IODev
            $hash->{IODev}{defptr}{$id} = $hash;    # register this logical device for given modbus id 
            $dest = $hash->{IODev}{NAME};           # display name of IODev in Log
            $hash->{STATE} = "opened";
        } else {
            $hash->{STATE} = "no IO Dev";
            $ret = "no physical modbus device defined";
            $dest = "none";
        }
    }
    InternalTimer(gettimeofday()+1, "ModbusLD_GetUpdate", "update:$name", 0)        # queue first request
        if ($hash->{INTERVAL});

    Log3 $name, 3, "$name: defined with id $id, interval $interval, destination $dest, protocol $proto" .
        ($ret ? ": " . $ret : "");

    return $ret;
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
            my $id = $hash->{MODBUSID};
            if ($defs{$aVal}) {         # gibt es den Geräte hash zum IODev Attribut?
                $hash->{IODev}{defptr}{$id} = $defs{$aVal};  # register logical device
                Log3 $name, 5, "$name: Attr IODev - using $aVal";
            } else {
                Log3 $name, 3, "$name: Attr IODev can't use $aVal - device does not exist";
            }
        }
        addToDevAttrList($name, $aName);
        $hash->{".updateSetGet"} = 1;
    }
    return undef;
}


#####################################
sub
ModbusLD_Undef($$)
{
    my ($hash, $arg) = @_;
    my $name = $hash->{NAME};
    DevIo_CloseDev($hash) if ($hash->{IODev} == $hash);
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
    $hash->{setList}  = "";
    $hash->{getList}  = "";

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
        $hash->{getList} .= "$reading " if ($showget); # sichtbares get

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
            $hash->{setList} .= "$setopt ";     # Liste aller Sets inkl. der Hints nach ":" für Rückgabe bei Set ?
        }
    }
    Log3 $name, 5, "$name: UpdateSetList: setList=$hash->{setList}";
    Log3 $name, 5, "$name: UpdateSetList: getList=$hash->{getList}";
    $hash->{".updateSetGet"} = 0;
}




#####################################
# Get Funktion für logische Geräte / Module
sub
ModbusLD_Get($@)
{
    my ($hash, @a) = @_;
    return "\"get $a[0]\" needs at least one argument" if(@a < 2);
    my $name    = $hash->{NAME};
    my $getName = $a[1];

    my $ioHash  = ModbusLD_GetIOHash($hash);
    return undef if (!$ioHash);
    
    my $objCombi;
    if ($getName ne "?") {
        $objCombi = ModbusLD_ObjKey($hash, $getName);
        Log3 $name, 5, "$name: Get: key for $getName = $objCombi";
    }
    
    if ($objCombi) {
        my ($err, $result);
        #my $type = substr($objCombi, 0, 1);
        #my $adr  = substr($objCombi, 1);
        Log3 $name, 5, "$name: Get: Requesting $getName ($objCombi)";
        
        if ($ioHash->{BUSY}) {
            Log3 $name, 5, "$name: Get: Queue is stil busy - taking over the read with ReadAnswer";
            # Answer for last function code has not yet arrived

            ($err, $result) = ModbusLD_ReadAnswer($hash);            
            Modbus_EndBUSY ($ioHash);       # set BUSY to 0, delete REQUEST, clear Buffer, do Profilig
        }

        ModbusLD_Send($hash, $objCombi, "read", 0, 1);      # add at beginning of queue and force send / sleep if necessary
        ($err, $result) = ModbusLD_ReadAnswer($hash, $getName);
        Modbus_EndBUSY ($ioHash);       # set BUSY to 0, delete REQUEST, clear Buffer, do Profilig

        return $err if ($err);
        return $result;
    } else {
        ModbusLD_UpdateGetSetList($hash) if ($hash->{".updateSetGet"});
        Log3 $name, 5, "$name: Get: $getName not found, return list $hash->{getList}"
            if ($getName ne "?");
        return "Unknown argument $a[1], choose one of $hash->{getList}";
    }
    RemoveInternalTimer ("queue:$name"); 
    Modbus_HandleSendQueue ("direct:$name"); # don't wait for next regular handle queue slot
    return;
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

    my $ioHash  = ModbusLD_GetIOHash($hash);
    return undef if (!$ioHash);
    
    my $objCombi;
    if ($setName ne "?") {
        $objCombi = ModbusLD_ObjKey($hash, $setName);
        Log3 $name, 5, "$name: Set: key for $setName = $objCombi";
    }

    if ($objCombi) {
        my $type = substr($objCombi, 0, 1);
        #my $adr  = substr($objCombi, 1);
        my ($err,$result);
        if (!defined($setVal)) {
            Log3 $name, 3, "$name: No Value given to set $setName";
            return "No Value given to set $setName";
        }
        Log3 $name, 5, "$name: Set: found option $setName ($objCombi), setVal = $setVal";

        if ($ioHash->{BUSY}) {
            Log3 $name, 5, "$name: Set: Queue still busy - taking over the read with ReadAnswer";
            # Answer for last function code has not yet arrived

            ($err, $result) = ModbusLD_ReadAnswer($hash);
            Modbus_EndBUSY ($ioHash);       # set BUSY to 0, delete REQUEST, clear Buffer, do Profilig            
        }
        my $map     = ModbusLD_ObjInfo($hash, $objCombi, "map", "defMap");
        my $setmin  = ModbusLD_ObjInfo($hash, $objCombi, "min", "", "");        # default to ""
        my $setmax  = ModbusLD_ObjInfo($hash, $objCombi, "max", "", "");        # default to ""
        my $setexpr = ModbusLD_ObjInfo($hash, $objCombi, "setexpr");
        
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
        } else {                                            # wenn keine map, dann wenigstens sicherstellen, dass numerisch.
            if ($setVal !~ /^-?\d+\.?\d*$/) {
                Log3 $name, 3, "$name: Set: Value $setVal is not numeric";
                return "Set Value $setVal is not numeric";
            }
            $rawVal = $setVal;
        }
        if ($setmin ne "") {        # 2. Schritt: falls definiert Min- und Max-Werte prüfen
            Log3 $name, 5, "$name: Set: checking value $rawVal against min $setmin";
            return "value $rawVal is smaller than min ($setmin)" if ($rawVal < $setmin);
        }
        if ($setmax ne "") {
            Log3 $name, 5, "$name: Set: checking value $rawVal against max $setmax";
            return "value $rawVal is bigger than max ($setmax)" if ($rawVal > $setmax);
        }
        if ($setexpr) {     # 3. Schritt: Konvertiere mit setexpr falls definiert
            my $val = $rawVal;
            $rawVal = eval($setexpr);
            Log3 $name, 5, "$name: Set: converted Value $val to $rawVal using expr $setexpr";
        }
        
        ModbusLD_Send($hash, $objCombi, "write", $rawVal, 1);   # add at beginning and force send / sleep if necessary
        ($err, $result) = ModbusLD_ReadAnswer($hash, $setName);
        Modbus_EndBUSY ($ioHash);       # set BUSY to 0, delete REQUEST, clear Buffer, do Profilig

        return $err if ($err);
                
        if ($fCode == 16) {
            # read after write
            Log3 $name, 5, "$name: Set: sending read after write";
            
            ModbusLD_Send($hash, $objCombi, "read", 0, 1);      # add at beginning and force send / sleep if necessary
            ($err, $result) = ModbusLD_ReadAnswer($hash, $setName);
            Modbus_EndBUSY ($ioHash);       # set BUSY to 0, delete REQUEST, clear Buffer, do Profilig
            
            return $err if ($err);          
        }
        return undef;               # no return code if no error 
    } else {        # undefiniertes Set
        ModbusLD_UpdateGetSetList($hash) if ($hash->{".updateSetGet"});
        Log3 $name, 5, "$name: Set: $setName not found, return list $hash->{setList}"
            if ($setName ne "?");
        return "Unknown argument $a[1], choose one of $hash->{setList}";
    }
    RemoveInternalTimer ("queue:$name"); 
    Modbus_HandleSendQueue ("direct:$name"); # don't wait for next regular handle queue slot
}


#####################################
# Called from get / set to get a direct answer
# called with logical device hash
sub
ModbusLD_ReadAnswer($;$)
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
    my $to = ModbusLD_DevInfo($hash, "timing", "timeout", 2);
    #my $to = AttrVal($name, "timeout", $hash->{deviceInfo}{timing}{timeout});
    #$to = 2 if (!$to);

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
            $hash->{helper}{lrecv} = $now;   
            Log3 $name, 5, "ReadAnswer got: " . unpack ("H*", $ioHash->{helper}{buffer});
        }

        my ($err, $framedata) = Modbus_ParseFrames($ioHash);
        if ($framedata || $err) {
            Log3 $name, 5, "$name: ReadAnswer done" .
                ($err ? ", err = $err" : "");
            
            if ($reading && defined($hash->{gotReadings}{$reading})) {  
                return ($err, $hash->{gotReadings}{$reading});
            } else {
                return ($err, $framedata);
            }
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
ModbusLD_GetUpdate($ ) {
    my $param = shift;
    my (undef,$name) = split(':',$param);
    my $hash      = $defs{$name};   # hash des logischen Devices, da GetUpdate aus dem logischen Modul per Timer gestartet wird
    my $modHash   = $modules{$hash->{TYPE}};
    my $parseInfo = $modHash->{parseInfo};
    my $devInfo   = $modHash->{deviceInfo};
    my $now       = gettimeofday();
    my $ioHash    = ModbusLD_GetIOHash($hash);
    
    InternalTimer($now + $hash->{INTERVAL}, "ModbusLD_GetUpdate", "update:$name", 0)
        if ($hash->{INTERVAL});

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
                Log3 $name, 5, "$name: GetUpdate will request $reading";
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
    foreach $nextObj (sort keys %readList) {
        $nextType    = substr($nextObj, 0, 1);
        $nextAdr     = substr($nextObj, 1);
        $nextReading = ModbusLD_ObjInfo($hash, $nextObj, "reading");
        $nextLen     = ModbusLD_ObjInfo($hash, $nextObj, "len", "defLen", 1);
        $readList{$nextObj} = $nextLen;
        if ($obj && $maxLen){
            $nextSpan = ($nextAdr + $nextLen) - $adr;
            if ($nextType eq $type && $nextSpan <= $maxLen && $nextSpan > $span) {
                Log3 $name, 5, "$name: GetUpdate combines $reading / $obj ".
                                "with $nextReading / $nextObj, span = $nextSpan, dropping read for $nextObj";
                delete $readList{$nextObj};         # no individual read for this object, combine with last
                $span = $nextSpan;
                $readList{$obj} = $nextSpan;
                next;   # don't change current object variables
            } else {
                Log3 $name, 5, "$name: GetUpdate cannot combine $reading / $obj ".
                                    "with $nextReading / $nextObj, span would be $nextSpan";
                $nextSpan = 0;
            }
        }
        ($obj, $type, $adr, $reading, $len, $span) = ($nextObj,  $nextType, $nextAdr, $nextReading, $nextLen, $nextSpan);
        $maxLen = ModbusLD_DevInfo($hash, $type, "combine", 1);
        Log3 $name, 5, "$name: GetUpdate: combine for $type is $maxLen";    
    }
    Modbus_Profiler($ioHash, "Idle");       
    while (my ($objCombi, $span) = each %readList) {
        ModbusLD_Send($hash, $objCombi, "read", 0, 0, $readList{$objCombi});
    }
}



######################################
# called from logical device fuctions 
# with log dev hash to get the 
# physical io device hash

sub
ModbusLD_GetIOHash($){
    my $hash   = shift;
    my $name   = $hash->{NAME};             # name of logical device
    my $ioHash = ($hash->{TYPE} eq "MODBUS" ? $hash : $hash->{IODev});
    if (!$ioHash) {
        Log3 $name, 3, "$name: no IODev found for $hash->{NAME}";
        return undef;
    }
    return $ioHash;
}



#####################################
# called from logical device fuctions 
# with log dev hash
sub
ModbusLD_Send($$$;$$$){
    my ($hash, $objCombi, $op, $v1, $force, $span) = @_;
    # $hash     : the logival Device hash
    # $objCombi : type+adr 
    # $op       : read, write
    # $v1       : value for writing
    # $force    : put in front of queue and don't reschedule but wait if necessary
    
    my $name    = $hash->{NAME};                # name of logical device
    my $modHash = $modules{$hash->{TYPE}};      # hash of logical module
    my $devInfo = $modHash->{deviceInfo};
    my $devId   = $hash->{MODBUSID};
    my $ioHash  = ModbusLD_GetIOHash($hash);
    my $type    = substr($objCombi, 0, 1);
    my $adr     = substr($objCombi, 1);
    my $reading = ModbusLD_ObjInfo($hash, $objCombi, "reading");
    my $len     = ModbusLD_ObjInfo($hash, $objCombi, "len", "defLen", 1);   
    my $unpack  = ModbusLD_ObjInfo($hash, $objCombi, "unpack", "defUnpack", "n");   
    
    return undef if (!$ioHash); 
    my $ioName = $ioHash->{NAME};
    
    my $fCode  = ModbusLD_DevInfo($hash, $type, $op, $defaultFCode{$type}{$op}); 
    if (!$fCode) {
        Log3 $name, 3, "$name: Send did not find fCode for $op type $type (obj $reading)";
        return;
    }
    $len = $span if ($span);    # span given as parameter
    my $data = "";
    
    if ($fCode == 1 || $fCode == 2) {           # read coils / discrete inputs, pdu format: StartAdr, Len
        $data   = pack ('nn', $adr, $len);
    } elsif ($fCode == 3 || $fCode == 4) {      # read holding / input registers, pdu format: StartAdr, Len
        $data   = pack ('nn', $adr, $len);
    } elsif ($fCode == 5) {     # function code "write single coil", pdu format: StartAdr, Value
        $data   = pack ('nH4', $adr, ($v1 ? "FF00" : "0000"));
    } elsif ($fCode == 6) {     # function code "write single register", pdu format: StartAdr, Value
        $data   = pack ('n'.$unpack, $adr, $v1);
    } elsif ($fCode == 15) {    # function code "write multiple coils", pdu format: StartAdr, NumOfCoils, ByteCount, Values
        $data   = pack ('nnCC', $adr, int($len/8)+1, $len, $v1);
    } elsif ($fCode == 16) {    # function code "write multiple registers", pdu format: StartAdr, NumOfRegisters, ByteCount, Values
        $data   = pack ('nnC'.$unpack, $adr, $len, $len*2, $v1);
    } else {
        # function code not implemented yet
        Log3 $name, 3, "$name: Send function code $fCode not yet implemented";
        return;
    }
    my $pdu = pack ('C', $fCode) . $data;
    #Log3 $name, 5, "$ioName: Send fcode $fCode for $reading, pdu : " . unpack ('H*', $pdu);
    
    my ($frame, $header, $crc, $dlen);
    my $tid = 0;
    
    if ($hash->{PROTOCOL} eq "RTU") {       # frame format: DevID, (fCode, data), CRC
        $header = pack ('C', ($devId));
        $crc    = pack ('v', Modbus_CRC($header . $pdu));
        $frame  = $header.$pdu.$crc;
    } elsif ($hash->{PROTOCOL} eq "TCP") {  # frame format: tid, 0, len, DevID, (fCode, data)
        $tid    = int(rand(255));
        $dlen   = bytes::length($pdu)+1; # length of pdu + devId
        $header = pack ('nnnC', ($tid, 0, $dlen, $devId));
        $frame  = $header.$pdu;
        #Log3 $name, 5, "$ioName: Send TCP frame tid=$tid, dlen=$dlen, devId=$devId, pdu=" . unpack ('H*', $pdu);
    }
    
    Log3 $name, 5, "$ioName: Send adds fcode $fCode for $reading to queue: " . 
        unpack ('H*', $frame) . " pdu " . unpack ('H*', $pdu) .
        ($force ? ", force send" : "");
    
    my %request;
    $request{FRAME}     = $frame;   # frame as data string
    $request{DEVICE}    = $hash;    # logical device in charge
    $request{FCODE}     = $fCode;   # function code
    $request{TYPE}      = $type;    # type of object (cdih)
    $request{ADR}       = $adr;     # address of object
    $request{LEN}       = $len;     # span / number of registers / length of object
    $request{READING}   = $reading; # reading name of the object
    $request{TID}       = $tid;     # transaction id for Modbus TCP
    
    my $qlen = ($ioHash->{QUEUE} ? scalar(@{$ioHash->{QUEUE}}) : 0);

    if(!$qlen) {
        #Log3 $name, 5, "$name: Send is creating new queue";
        $ioHash->{QUEUE} = [ \%request ];
    } else {
        #Log3 $name, 5, "$name: Send initial queue length is $qlen";
        if ($qlen > AttrVal($name, "queueMax", 100)) {
            Log3 $name, 3, "$name: Send queue too long, dropping request";
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
        <li><b>queueMax</b></li> 
            max length of the send queue, defaults to 100<br>
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

