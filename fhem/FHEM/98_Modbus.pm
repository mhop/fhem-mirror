##############################################################################
# $Id$
# fhem Modul für Geräte mit Modbus-Interface - 
# Basis für logische Geräte-Module wie zum Beispiel 
# ModbusAttr.pm or ModbusSET.pm
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
#   ToDo / Ideas 
#                   limit combine?!! (Max 7d / 125 Register read bzw. 7b write), bei coils read max 7d0, bei write 7b0
#                   verify that nextOpenDelay is integer and >= 1
#                   set active results in error when tcp is already open
#                   enforce nextOpenDelay even if slave immediately closes after open https://forum.fhem.de/index.php/topic,75638.570.html
#                   set generateTestData to create rData hash and calls to is(getEvent...), save config, ...
#
#                   when define of relay is modified -> close all open TCP server connection devices to force reconnect and get correct parameters
#                   debug two tcp relays in parallel on same physical bus (logs shown by mike have strange incoming frames, responses seem to go to wrong device)
#               
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

# $hash->{Interval}         Interval for cyclic request of a master device
# $hash->{RELAY}            used for mode relay: name of a master device where we forward requests to
# $hash->{DeviceName}       needed by DevIo to get Device, Port, Speed etc.
# $hash->{IODev}            hash of the io device or this device itself if connecting through tcp
# $hash->{defptr}           reference to the name of the logical device responsible for an id (defptr}{lName} => id
# $hash->{TCPConn}          set to 1 if connecting through tcp/ip
# $hash->{TCPServer}        set to 1 if this is a tcp server / listening device (not a connection itself)
# $hash->{TCPChild}         set to 1 if this is a tcp server connection (child of a devive with TCPServer = 1)
# $hash->{EXPECT}           internal state - what are we waiting for 
#                           for master this can only be response or idle
#                           for slave / relay (=receiving side of a relay) it can only be request or response while we are parsing something not for us
#                           for passive it can be only request / response
#                           

# $hash->{MODE} can be master, slave, relay or passive - set during ld define
# relay is special because it to another master device to pass over requests to

# $hash->{FRAME}            the frame just received, beeing parsed / handled


# $hash->{REQUEST}          the request just received, beeing parsed / handled. 
#                               It is set in HandleRequest as slave -> send reply, done synchronously
#                               or in HandleRequest as relay -> queue via master side where a modified copy
#                               of $hash->{REQUEST} will be stored
#                               or ProcessRequestQueue (master) -> take from queue, send -> wait for reply
#
# $hash->{RESPONSE}         the response just received, beeing parsed / handled or created
#
# both are destroyed after HandleResponse
#


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
# Fhem Master       Expr    Register in externem Gerät (read)   Readings in Fhem                # implemented in ParseDataString
# Fhem Slave        Expr    Werte von externem Gerät (write)    Readings in Fhem                # implemented in ParseDataString
#
# Fhem Master    setexpr    Benutzereingabe (set->write)        Register in externem Gerät      # implemented in Set
# Fhem Slave     setexpr    Readings in Fhem (read)             Register zu externem Gerät      # implemented in PackObj
#                
#
# Fhem Master       Map     Registerdarstellung extern (read)   Readings in Fhem                # implemented in ParseDataString
# Fhem Slave        Map     Werte von externem Gerät (write)    Readings in Fhem                # implemented in ParseDataString
#
# Fhem Master     revMap    Benutzereingabe (set->write)        Register in externem Gerät      # implemented in Set
# Fhem Slave      revMap    Readings in Fhem (read)             Register in externem Gerät      # implemented in PackObj
#

                    
package Modbus;

use strict;
use warnings;
use GPUtils         qw(:all);
use SetExtensions   qw(:all);
use Time::HiRes     qw(gettimeofday tv_interval sleep);     # work with floats, not just full seconds
use POSIX           qw(strftime);
use Encode          qw(decode encode);
use Scalar::Util    qw(looks_like_number);
use TcpServerUtils  qw(:all);
use DevIo;
use FHEM::HTTPMOD::Utils qw(:all);

use Exporter ('import');
our @EXPORT_OK = qw();
our %EXPORT_TAGS = (all => [@EXPORT_OK]);

BEGIN {                         # functions / variables needed from package main
    GP_Import( qw(
        CommandAttr
        CommandDeleteAttr
        CommandDelete
        addToDevAttrList
        AttrVal
        ReadingsVal
        ReadingsTimestamp
        readingsSingleUpdate
        readingsBeginUpdate
        readingsBulkUpdate
        readingsEndUpdate
        InternalVal
        makeReadingName
        goodReadingName
        DoTrigger
    
        Log3
        RemoveInternalTimer
        InternalTimer
        deviceEvents
        EvalSpecials
        AnalyzePerlCommand
        CheckRegexp
        IsDisabled

        gettimeofday
        FmtDateTime
        GetTimeSpec
        fhemTimeLocal
        time_str2num
        rtrim

        DevIo_OpenDev
        DevIo_SimpleWrite
        DevIo_SimpleRead
        DevIo_CloseDev
        DevIo_IsOpen
        DevIo_Disconnected
        SetExtensions

        TcpServer_Open
        TcpServer_Accept
        TcpServer_SetSSL
        TcpServer_Close

        featurelevel
        defs
        modules
        attr
        init_done
    ));
    
    # function to be visible im package main as Modbus_Name
    GP_Export( qw(                  
        Initialize
    ));

    # special case to be used by legacy Fhem modules built on Modbus ...
    *main::ModbusLD_Initialize = *Modbus::InitializeLD;
    *main::ModbusLD_Define = *Modbus::DefineLDFn;
    *main::ModbusLD_Undef = *Modbus::UndefLDFn;
    *main::ModbusLD_Set = *Modbus::SetLDFn;
    *main::ModbusLD_Get = *Modbus::GetLDFn;
    *main::ModbusLD_Attr = *Modbus::AttrLDFn;
    *main::Modbus_Notify = *Modbus::NotifyFn;

};

my $Module_Version = '4.4.01 - 18.3.2021';

my $PhysAttrs = join (' ', 
        'queueDelay',
        'queueMax',
        'queueTimeout',
        'busDelay',
        'clientSwitchDelay',
        'frameGap',
        'dropQueueDoubles:0,1',
        'enableQueueLengthReading:0,1',
        'retriesAfterTimeout',
        'profileInterval',
        'openTimeout',
        'nextOpenDelay',
        'nextOpenDelay2',
        'maxTimeoutsToReconnect',             # for Modbus over TCP/IP only        
        'skipGarbage:0,1',
        'timeoutLogLevel:3,4',
        'closeAfterResponse:0,1',             # for Modbus over TCP/IP only
        'silentReconnect:0,1');
        
my $LogAttrs = join (' ', 
        'IODev',                              # fhem.pl macht dann $hash->{IODev} = $defs{$ioname}
        'queueMax',
        'alignTime',
        'enableControlSet:0,1',
        'enableSetInactive:0,1',
        'nonPrioritizedSet:0,1',
        'nonPrioritizedGet:0,1',
        'sortUpdate:0,1',
        'propagateVerbose:0,1',
        'connectionsRoom',
        'serverIdExpr',
        'scanDelay');
        
my $CommonAttrs = 
        'disable:0,1';
        
my $ObjAttrs = join (' ', 
        'obj-[cdih][0-9]+-reading',
        'obj-[cdih][0-9]+-name',
        'obj-[cdih][0-9]+-min',
        'obj-[cdih][0-9]+-max',
        'obj-[cdih][0-9]+-hint',
        'obj-[cdih][0-9]+-map',
        'obj-[cdih][0-9]+-set',
        'obj-[cdih][0-9]+-setexpr',
        'obj-[cdih][0-9]+-textArg',
        'obj-[cdih][0-9]+-revRegs',
        'obj-[cdih][0-9]+-bswapRegs',
        'obj-[cdih][0-9]+-len',
        'obj-[cdih][0-9]+-unpack',
        'obj-[cdih][0-9]+-decode',
        'obj-[cdih][0-9]+-encode',
        'obj-[cdih][0-9]+-expr',
        'obj-[cdih][0-9]+-ignoreExpr',
        'obj-[cdih][0-9]+-format',
        'obj-[ih][0-9]+-type',
        'obj-[cdih][0-9]+-showGet',
        'obj-[cdih][0-9]+-allowWrite',
        'obj-[cdih][0-9]+-group',
        'obj-[cdih][0-9]+-poll',
        'obj-[cdih][0-9]+-polldelay');
        
my $DevAttrs = join (' ',
        'dev-([cdih]-)?read',
        'dev-([cdih]-)?write',
        'dev-([cdih]-)?combine',
        'dev-([cdih]-)?allowShortResponses',
        'dev-([cdih]-)?addressErrCode',
        'dev-([cdih]-)?valueErrCode',
        'dev-([cdih]-)?notAllowedErrCode',
        

        'dev-([cdih]-)?defRevRegs',
        'dev-([cdih]-)?defBswapRegs',
        'dev-([cdih]-)?defLen',
        'dev-([cdih]-)?defUnpack',
        'dev-([cdih]-)?defDecode',
        'dev-([cdih]-)?defEncode',
        'dev-([cdih]-)?defExpr',
        'dev-([cdih]-)?defSet',
        'dev-([cdih]-)?defHint',
        'dev-([cdih]-)?defSetexpr',
        'dev-([cdih]-)?defIgnoreExpr',
        'dev-([cdih]-)?defFormat',
        'dev-([cdih]-)?defShowGet',
        'dev-([cdih]-)?defAllowWrite',
        'dev-([cdih]-)?defPoll',
        'dev-h-brokenFC3',
        'dev-c-brokenFC5',
        
        'dev-type-[A-Za-z0-9_]+-unpack',
        'dev-type-[A-Za-z0-9_]+-len',
        'dev-type-[A-Za-z0-9_]+-encode',
        'dev-type-[A-Za-z0-9_]+-decode',
        'dev-type-[A-Za-z0-9_]+-revRegs',
        'dev-type-[A-Za-z0-9_]+-bswapRegs',
        'dev-type-[A-Za-z0-9_]+-format',
        'dev-type-[A-Za-z0-9_]+-expr',
        'dev-type-[A-Za-z0-9_]+-map',
        'dev-type-[A-Za-z0-9_]+-hint',
        'dev-type-[A-Za-z0-9_]+-set',

        'dev-timing-timeout',
        'dev-timing-serverTimeout',       
        'dev-timing-sendDelay',
        'dev-timing-commDelay');

my %errCodes = (
    '01' => 'illegal function',
    '02' => 'illegal data address',
    '03' => 'illegal data value',
    '04' => 'slave device failure',
    '05' => 'acknowledge',
    '06' => 'slave device busy',
    '08' => 'memory parity error',
    '0a' => 'gateway path unavailable',
    '0b' => 'gateway target failed to respond'
);

my %PDUOverhead = (         # bytes on top of the PDU (fcode, data)
    'RTU'   =>  3,          # id + checksum
    'ASCII' =>  7,          # Start:, 2 Ziffern Id, 2 Ziffern LRC, CR LF
    'TCP'   =>  7);

my %fcMap = (
    1   =>  {   read => 1, 
                type => 'c',
                default => 1,
                objReturn => 1,
            },
    2   =>  {   read => 1, 
                type => 'd',
                default => 1,
                objReturn => 1,
            },
    3   =>  {   read => 1,
                type => 'h', 
                default => 1,
                objReturn => 1,
            },
    4   =>  {   read => 1,
                type => 'i', 
                default => 1,
                objReturn => 1,
            },
    5   =>  {   write => 1, 
                type => 'c',
                default => 1,
                objReturn => 1,
            },
    6   =>  {   write => 1, 
                type => 'h',
                default => 1,
                objReturn => 1,
            },
    15  =>  {   write => 1, 
                type => 'c',
            },                
    16  =>  {   write => 1,
                type => 'h',
            },
    17  =>  {   read => 1,
            }
);


my %attrDefaults = (
    'allowWrite'    => { devDefault => 'defAllowWrite',
                         default    => 0},
    'bswapRegs'     => { devDefault => 'defBswapRegs'},
    'decode'        => { devDefault => 'defDecode'},
    'encode'        => { devDefault => 'defEncode'},
    'expr'          => { devDefault => 'defExpr'},
    'format'        => { devDefault => 'defFormat'},
    'hint'          => { devDefault => 'defHint'},
    'ignoreExpr'    => { devDefault => 'defIgnoreExpr'},
    'len'           => { devDefault => 'defLen',
                         default    => 1},
    'map'           => { devDefault => 'defMap'},
    'max'           => { default    =>  ''},
    'min'           => { default    =>  ''},
    'poll'          => { devDefault => 'defPoll',
                         default    => 0},
    'polldelay'     => { default    => '0.5'},
    'reading'       => {},
    'revRegs'       => { devDefault => 'defRevRegs'},
    'set'           => { devDefault => 'defSet'},
    'setexpr'       => { devDefault => 'defSetexpr'},
    'showGet'       => { devDefault => 'defShowGet'},
    'textArg'       => {},
    'type'          => { default    => '***NoTypeInfo***'},
    'unpack'        => { devDefault => 'defUnpack',
                         default    => 'n'},
);
    
###########################################################
# _initialize for the physical io device, 
# exported as Modbus_Initialize 
# called when the module is lodaded by Fhem
sub Initialize {
    my $modHash = shift;

    $modHash->{ReadFn}   = \&Modbus::ReadFn;
    $modHash->{ReadyFn}  = \&Modbus::ReadyFn;
    $modHash->{DefFn}    = \&Modbus::DefineFn;
    $modHash->{UndefFn}  = \&Modbus::UndefFn;
    $modHash->{NotifyFn} = \&Modbus::NotifyFn;
    $modHash->{AttrFn}   = \&Modbus::AttrFn;

    $modHash->{AttrList} = join (' ', 
        'do_not_notify:1,0',
        $PhysAttrs,
        $CommonAttrs,
        $main::readingFnAttributes);
    return;
}


###########################################################
# initialize logical device
# needs to be visible like this from Device-Modules based on Modbus
sub InitializeLD {
    my ($modHash) = @_;

    $modHash->{DefFn}     = \&Modbus::DefineLDFn;    # functions are provided by the Modbus base module
    $modHash->{UndefFn}   = \&Modbus::UndefLDFn;
    $modHash->{ReadFn}    = \&Modbus::ReadFn;
    $modHash->{ReadyFn}   = \&Modbus::ReadyFn;
    $modHash->{AttrFn}    = \&Modbus::AttrLDFn;
    $modHash->{SetFn}     = \&Modbus::SetLDFn;
    $modHash->{GetFn}     = \&Modbus::GetLDFn;
    $modHash->{NotifyFn}  = \&Modbus::NotifyFn;

    $modHash->{AttrList}= join (' ', 
        'do_not_notify:1,0',         
        $LogAttrs, 
        $CommonAttrs,
        $main::readingFnAttributes);

    $modHash->{ObjAttrList} = $ObjAttrs;
    $modHash->{DevAttrList} = $DevAttrs;
    return;            
}


###########################################################################
# Define for the physical serial base device
# modbus id, Intervall don't live here but in the logical device 
# Also Modbus over TCP is opened in the logical open
sub DefineFn {
    my $ioHash = shift;                     # new hash of the device to be created
    my $def    = shift;                     # definition string 
    my @a      = split(/\s+/, $def);
    my $name   = shift @a;                  # name of the device to be created
    my $type   = shift @a;                  # type / module to be used
    my $dev    = shift @a;                  # serial device 

    return "wrong syntax: define <name> $type [tty-devicename|none]" if (!$dev);

    $ioHash->{DeviceName} = $dev;       # needed by DevIo to get Device, Port, Speed etc.
    $ioHash->{IODev}      = $ioHash;    # point back to self to make getIOHash easier
    $ioHash->{SerialConn} = 1;
    $ioHash->{NOTIFYDEV}  = 'global';   # NotifyFn nur aufrufen wenn global events (INITIALIZED)

    # todo: check if tcp or serial to allow sharing of a tcp connection iodev for multiple devices
    # e.g. to a gateway

    DoClose($ioHash, 1);                # close, set Expect, clear Buffer, but don't set state to disconnected
    Log3 $name, 3, "$name: defined as $dev";
    return;                             # open is done later from NOTIFY
}



########################################################################
# define of the logical device
sub DefineLDFn {
    my $hash = shift;
    my $def  = shift;
    my ($name, $module, $id, $interval, $mode, $ipPort, $proto, $relay, $logInfo);
    
    my $rxIP      = qr{ (?!ASCII|RTU|TCP)\S+                                         }xms; 
    my $rxPort    = qr{ [0-9]+                                                       }xms;
    my $rxName    = qr{ (?<name> \S+)                                                }xms;
    my $rxModule  = qr{ (?<module> \S+)                                              }xms;
    my $rxId      = qr{ (?:id)? (?<id> [0-9]+)                                       }xms;
    my $rxDest    = qr{ (?:destination)? (?<ipport> $rxIP(?:\:$rxPort)?)             }xms;
    my $rxListen  = qr{ (?:listen)? (?<ipport> $rxIP\:$rxPort)                       }xms;
    my $rxProto   = qr{ (?<proto> RTU|ASCII|TCP)                                     }xms;
    my $rxInterv  = qr{ (?:interval)? (?<interval> [0-9]+ (?:\.[0-9]+)? )            }xms;
    my $rxRelay   = qr{ (?<relay> \S+)                                               }xms;
    my $rxSp      = qr{ \s+                                                          }xms;
    
    # classic master define
    if ($def =~ m{\A $rxName $rxSp $rxModule                    # DevName, Module
                $rxSp $rxId                                     # ModbusId
                $rxSp $rxInterv                                 # Interval
                (?: $rxSp $rxDest )?                            # optional IP:Port for TCP destination
                (?: $rxSp $rxProto )? \z                        # optional protocol (RTU|ASCII|TCP)
                }xms) {                
        (  $name,    $module,    $id,    $interval,    $ipPort,    $proto) 
      = ($+{name}, $+{module}, $+{id}, $+{interval}, $+{ipport}, $+{proto});
        $mode     = 'master';
        $logInfo  = " and interval $interval" . ($ipPort ? ", connection to $ipPort" : "");
    } 
    # slave (=server) define
    elsif ($def =~ m{\A  $rxName $rxSp $rxModule 
                    $rxSp $rxId 
                    $rxSp (?: slave | server)
                    (?: $rxSp $rxListen )?
                    (?: $rxSp $rxProto )? \z }xms) {
        (  $name,    $module,    $id,    $ipPort,    $proto) 
      = ($+{name}, $+{module}, $+{id}, $+{ipport}, $+{proto});
        $mode     = 'slave';
        $logInfo  = ($ipPort ? "listening at $ipPort" : ' with connection through io device');
    }
    # passive define
    elsif ($def =~ m{\A  $rxName $rxSp $rxModule 
                    $rxSp $rxId 
                    $rxSp passive
                    (?: $rxSp $rxProto )? \z }xms) {
        $mode     = 'passive';
        (  $name,    $module,    $id,    $proto) 
      = ($+{name}, $+{module}, $+{id}, $+{proto});
    }
    # relay define
    elsif ($def =~ m{\A $rxName $rxSp $rxModule 
                    $rxSp $rxId
                    $rxSp relay
                    (?: $rxSp $rxListen )?
                    (?: $rxSp $rxProto )?
                    $rxSp to $rxSp $rxRelay \z }xms) {
        (  $name,    $module,    $id,    $interval,    $ipPort,    $proto,    $relay) 
      = ($+{name}, $+{module}, $+{id}, $+{interval}, $+{ipport}, $+{proto}, $+{relay});
        $mode     = 'relay';
        $logInfo  = ($ipPort ? " listening at $ipPort" : " receiving through IODev") . " and relaying to device $relay";
    }
    else {
        ($name, $module) = ($def =~ /(\S+)\s+(\S+)\s+.*/);
        return "Usage: define <name> $module <id> <interval>|slave|server|relay|passive [host:port] [RTU|ASCII|TCP] [to <relayMasterDevice>]"
    }

    $hash->{MODBUSID} = $id;
    $hash->{MODE}     = $mode;
    $hash->{PROTOCOL} = $proto // 'RTU';
    Log3 $name, 3, "$name: defined $mode with id $id, protocol $hash->{PROTOCOL}" . ($logInfo // '');
    
    # for Modbus TCP physical hash = logical has so MODE is set for physical device as well.    
    # for Modbus over serial lines this is set when IODev Attr and GetIOHash is called 
    # or later when it is needed and GetIOHash is called
    
    # for TCP $id is an optional Unit ID that is ignored by most devices
    # but some gateways may use it to select the device to forward to.
        
    $hash->{'.getList'}      = '';
    $hash->{'.setList'}      = '';
    $hash->{'.updateSetGet'} = 1;
    $hash->{NOTIFYDEV}       = 'global';                # NotifyFn nur aufrufen wenn global events (INITIALIZED etc.)
    $hash->{MODULEVERSION}   = "Modbus $Module_Version";
    
    if ($interval) {
        $hash->{Interval}    = $interval;
    } else {
        delete $hash->{Interval};                       # keep display of internals in Fhemweb short
    }
    
    if ($relay) {
        $hash->{RELAY}       = $relay;
    } else {
        delete $hash->{RELAY};
    }

    if ($ipPort) {                                      # Modbus über TCP mit IP Adresse (TCP oder auch RTU/ASCII über TCP)
        $ipPort .= ':502' if ($ipPort !~ /.*:[0-9]/);   # add default port if no port specified
        $hash->{DeviceName}    = $ipPort;               # needed by DevIo to get Device, Port, Speed etc.
        $hash->{IODev}         = $hash;                 # Modul ist selbst IODev
        $hash->{defptr}{$name} = $id;                   # logisches Gerät für die Id (selbes Device bei TCP)
        $hash->{TCPConn}       = 1;
        $hash->{TCPServer}     = 1 if ($mode eq 'slave' || $mode eq 'relay');
        $hash->{'.AttrList'}   = $modules{$hash->{TYPE}}{AttrList} . ' ' . $PhysAttrs;  # add physical attributes to TCP devices
    } 
    else {
        $ipPort = '';
        delete $hash->{TCPConn};
        delete $hash->{TCPServer};
        delete $hash->{TCPChild};
    }
    SetStates($hash, 'disconnected');                   # initial state after define - might modify to disabled / inactive
    # connection will be opened later in NotifyFN (INITIALIZED, DEFINED, MODIFIED, ...)
    # for serial connections we use a separate physical device. This is set in Notify
    return;
}



#####################################
# delete physical Device
sub UndefFn {
    my $ioHash = shift;
    my $arg    = shift;
    my $name   = $ioHash->{NAME};

    # device is already in the process of being deleted so we should not issue commandDelete inside _Close again
    DoClose($ioHash,1 ,1) if (IsOpen($ioHash));  # close, set Expect, clear Buffer, don't set state, don't delete yet

    # lösche auch die Verweise aus logischen Modulen auf dieses physische.
    foreach my $d (keys %{$ioHash->{defptr}}) {
        Log3 $name, 3, "$name: Undef is removing IO device for $d";
        my $lHash = $defs{$d};
        delete $lHash->{IODev} if ($lHash);
        UpdateTimer($lHash, \&Modbus::GetUpdate, 'stop');
    }
    Profiler($ioHash, 'Idle');                   # set category to book following time, can be Delay, Fhem, Idle, Read, Send or Wait
    #Log3 $name, 3, "$name: _UnDef done";
    return;
}



#####################################
# device is being deleted
sub UndefLDFn {
    my $hash = shift;
    my $arg  = shift;
    my $name = $hash->{NAME};
    Log3 $name, 3, "$name: _UnDef is closing $name";    
    UnregAtIODev($hash);
    
    # device is already in the process of being deleted so we should not issue commandDelete inside _Close again
    DoClose($hash,1 ,1) if (IsOpen($hash));      # close, set Expect, clear Buffer, don't set state, don't delete yet
    UpdateTimer($hash, \&Modbus::GetUpdate, 'stop');        
    delete $hash->{PROTOCOL};                       # just in case somebody keeps a pointer to our hash ...
    delete $hash->{MODE};
    delete $hash->{IODev};
    return;
}


#########################################################################
# AttrFn for physical serial device. 
# special treatment only für attr disable.
sub AttrFn {
    my $cmd   = shift;                  # 'set' or 'del'
    my $name  = shift;                  # the Fhem device name
    my $aName = shift;                  # attribute name
    my $aVal  = shift;                  # attribute value
    my $hash  = $defs{$name};           # reference to the Fhem device hash
    
    Log3 $name, 5, "$name: attr $cmd $aName" . (defined($aVal) ? ", $aVal" : "");
    if ($aName eq 'disable' && $init_done) {        # only after init_done, otherwise see NotifyFN
        # disable on a physical serial device
        if ($cmd eq "set" && $aVal) {
            Log3 $name, 3, "$name: attr disable set" . (IsOpen($hash) ? ", closing connection" : "");
            DoClose($hash);                    # close, set Expect, clear Buffer, set state to disconnected
            UpdateTimer($hash, \&Modbus::GetUpdate, 'stop');    
        } 
        elsif ($cmd eq 'del' || ($cmd eq 'set' && !$aVal)) {
            Log3 $name, 3, "$name: attr disable removed";
            DoOpen($hash) if (!AttrVal($name, 'closeAfterResponse', 0));
        }
    }   
    return;
}


#########################################################################
# AttrFn for logical device. 
sub AttrLDFn {
    my $cmd   = shift;                  # 'set' or 'del'
    my $name  = shift;                  # the Fhem device name
    my $aName = shift;                  # attribute name
    my $aVal  = shift;                  # attribute value
    my $hash  = $defs{$name};           # reference to the Fhem device hash
    
    if ($cmd eq 'set') {
        if ($aName =~ /expr/) {     # validate all Expressions
            return "Invalid Expression $aVal" 
                if (!EvalExpr($hash, {expr => $aVal, checkOnly => 1, action => "attr $aName"} ));
        } 
        elsif ($aName eq 'IODev') {
            if ($hash->{TCPConn}) {
                return "Attr IODev is not allowed for devices connected through TCP";
            }           
            if (!SetIODev($hash, $aVal) && $init_done) {       # set physical device proto, mode, reg/unreg
                return "$aVal can not be used as IODev, see log for details";
            }
        } 
        elsif ($aName eq 'verbose') {
            if ($aVal =~ /^[0-5]$/ && $hash->{TCPServer} && $hash->{FD}) {
                Log3 $name, 4, "$name: propagate verbose level $aVal to connection subdevices";
                foreach my $conn (keys %{$hash->{CONNECTHASH}}) {
                    my $chash = $hash->{CONNECTHASH}{$conn};
                    $attr{$chash->{NAME}}{verbose} = $aVal;
                }
            }
            if (AttrVal($name, 'propagateVerbose', 0)) {
				Log3 $name, 4, "$name: propagateVerbose is set, propagate level $aVal to IO device and potential relay device";
                my $ioHash = GetIOHash($hash);     # get ioName for meaningful logging
                if ($ioHash && $ioHash != $hash) {
                    $attr{$ioHash->{NAME}}{verbose} = $aVal;
                    #Log3 $name, 3, "$name: verbose $aVal propagated to $ioHash->{NAME}";
                }
                if ($hash->{RELAY}) {
					#Log3 $name, 4, "$name: propagateVerbose is set and RELAY is $hash->{RELAY}";
                    $attr{$hash->{RELAY}}{verbose} = $aVal;
                    #Log3 $name, 3, "$name: verbose $aVal propagated to $hash->{RELAY}";
                    my $rIoHash = GetRelayIO($hash);
					#Log3 $name, 4, "$name: propagateVerbose is set and RELAY IO device is $rIoHash->{NAME}";
                    if ($rIoHash && $rIoHash != $hash) {
                        $attr{$rIoHash->{NAME}}{verbose} = $aVal;
                        #Log3 $name, 3, "$name: verbose $aVal propagated to $rIoHash->{NAME}";
                    }
                }
            }
        } 
        elsif ($aName eq 'alignTime') {
            my ($alErr, $alHr, $alMin, $alSec, undef) = GetTimeSpec($aVal);
            return "Invalid Format $aVal in $aName : $alErr" if ($alErr);
            my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
            $hash->{'.TimeAlign'} = fhemTimeLocal($alSec, $alMin, $alHr, $mday, $mon, $year);
            $hash->{TimeAlignFmt} = FmtDateTime($hash->{'.TimeAlign'});
            UpdateTimer($hash, \&Modbus::GetUpdate, 'start');           # set / change timer
        } 
        elsif (" $PhysAttrs " =~ /\ $aName[: ]/) {
            if (!$hash->{TCPConn} && !$hash->{SerialConn}) {
                Log3 $name, 3, "$name: attr $aName is only valid for physical Modbus devices or Modbus TCP - please use this attribute for your physical IO device" . ($hash->{IODev}{NAME} ? ' ' . $hash->{IODev}{NAME} : "");
                return "attribute $aName is only valid for physical Modbus devices or Modbus TCP - please use this attribute for your physical IO device" . ($hash->{IODev}{NAME} ? ' ' . $hash->{IODev}{NAME} : "");
            }
        } 
        elsif ($aName =~ /(obj-[cdih])[0-9]+-reading/) {
            return "unsupported character in reading name $aName ".
                "(not A-Za-z/\\d_\\.-)" if(!goodReadingName($aName));
        } 
        elsif ($aName eq 'SSL') {
            if (!$hash->{TCPConn}) {
                Log3 $name, 3, "$name: attr $aName is only valid Modbus TCP slaves (=servers)";
                return "attribute $aName is only valid for Modbus TCP slaves (=servers)";
            }       
            TcpServer_SetSSL($hash);            # todo: does this work? is tcp connection open yet? does it have to be?
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
        ManageUserAttr($hash, $aName);
    } 
    elsif ($cmd eq 'del') {    
        #Log3 $name, 5, "$name: attr del $aName";
        if ($aName =~ /obj-[cdih]0[0-9]+-/) {
            if (!(grep {!/$aName/} grep {/obj-[cdih]0[0-9]+-/} keys %{$attr{$name}})) {
                delete $hash->{LeadingZeros};   # no more leading zeros            
            }
        } 
        elsif ($aName eq 'verbose') {
            if ($hash->{TCPServer} && $hash->{FD}) {
                Log3 $name, 5, "$name: delete verbose level in connection subdevices";
                foreach my $conn (keys %{$hash->{CONNECTHASH}}) {
                    my $chash = $hash->{CONNECTHASH}{$conn};
                    delete $attr{$chash->{NAME}}{verbose};
                }
            }
        }
    }
    $hash->{'.updateSetGet'} = 1;
    #Log3 $name, 5, "$name: attr change set updateGetSetList to 1";
    
    if ($aName eq 'disable' && $init_done) {    # if not init_done, nothing to be done here (see NotifyFN)
        if ($cmd eq "set" && $aVal) {           # disable set on a logical device (not physical serial here!)
            SetLDInactive($hash);
            SetStates($hash, 'disabled');
        } 
        elsif ($cmd eq 'del' || ($cmd eq 'set' && !$aVal)) {    # disable removed / cleared
            Log3 $name, 3, "$name: attr disable removed";
            SetLDActive($hash);
            SetStates($hash, 'enabled');                               # don't check attr disable (not cleared yet) and set to active temporarily
        }
    }   
    return;
}


######################################################
# set the logical device to inactive, close IO 
# and stop timer
sub SetLDInactive {
    my $hash = shift;
    my $name = $hash->{NAME};

    if ($hash->{TCPConn}) {             # Modbus over TCP connection
        Log3 $name, 3, "$name: device is beeing set to inactive / disabled" . (IsOpen($hash) ? ", closing TCP connection" : "");
        DoClose($hash);                 # close, set Expect, clear Buffer, set state to disconnected
        UpdateTimer($hash, \&Modbus::GetUpdate, 'stop');
    } 
    else {                              # connection via serial io device
        UnregAtIODev($hash);            # unregister at physical device because logical device is disabled
    }
    UpdateTimer($hash, \&Modbus::GetUpdate, 'stop');
    return;
}


######################################################
# activate the logical device, reopen, set timer
sub SetLDActive {
    my $hash = shift;
    my $name = $hash->{NAME};

    if ($hash->{TCPConn}) {                     # Modbus over TCP connection
        if (!IsOpen($hash)) {
            DoOpen($hash) if !AttrVal($name, "closeAfterResponse", 0);
        }
    } 
    else {
        my $ioHash = GetIOHash($hash);     	    # get ioHash / check compatibility and set / register if necessary
        Log3 $name, 3, "$name: " . ($ioHash ? "using $ioHash->{NAME}" : "no IODev") . " for communication";
    }
    if ($hash->{MODE} && $hash->{MODE} eq 'master') {
        UpdateTimer($hash, \&Modbus::GetUpdate, 'start');   # set / change timer
    }
    return;
}


###########################################################################
# called from get / set if $hash->{'.updateSetGet'} is set
# which is done in define and attr
sub UpdateGetSetList {
    my $hash      = shift;
    my $name      = $hash->{NAME};
    my $modHash   = $modules{$hash->{TYPE}};
    my $parseInfo = $hash->{parseInfo}  // $modHash->{parseInfo};
    my $devInfo   = $hash->{deviceInfo} // $modHash->{deviceInfo};
    $hash->{'.getList'}  = '';
    $hash->{'.setList'}  = '';
    if (AttrVal($name, "enableControlSet", 1)) {            # special sets active (since 4.0 1 by default)
        $hash->{'.setList'}  = "reconnect:noArg saveAsModule createAttrsFromParseInfo ";
        if ($hash->{MODE} && $hash->{MODE} eq 'master') {
            $hash->{'.setList'} .= "interval reread:noArg stop:noArg start:noArg close:noArg ";
            $hash->{'.setList'} .= "scanStop:noArg scanModbusObjects ";
            $hash->{'.setList'} .= "scanModbusId " if ($hash->{PROTOCOL} =~ /RTU|ASCII/);
        }
        if (AttrVal($name, 'enableSetInactive', 1)) {
            $hash->{'.setList'} .= "inactive active ";
        }
    }
    if ($hash->{MODE} && $hash->{MODE} eq 'master') {
        my @ObjList = keys (%{$parseInfo});
        foreach my $at (keys %{$attr{$name}}) {
            if ($at =~ /^obj-(.*)-reading$/) {
                push @ObjList, $1 if (!$parseInfo->{$1});
            }
        }
        #Log3 $name, 5, "$name: UpdateGetSetList full object list: " . join (" ",  @ObjList);
        
        foreach my $objCombi (sort @ObjList) {
            my $reading = ObjInfo($hash, $objCombi, 'reading');
            my $showget = ObjInfo($hash, $objCombi, 'showGet');
            my $set     = ObjInfo($hash, $objCombi, 'set'); 
            my $map     = ObjInfo($hash, $objCombi, 'map');
            my $hint    = ObjInfo($hash, $objCombi, 'hint');
            my $setopt;
            $hash->{'.getList'} .= "$reading:noArg " if ($showget); # sichtbares get
    
            if ($set) {                 # gibt es für das Reading ein SET?
                $setopt = $reading . ($map ? ':' . MapToHint($map) : '');
                $setopt = $reading . ':' . $hint if ($hint);
                $hash->{'.setList'} .= "$setopt ";              # add set option
            }
        }
    }
    Log3 $name, 5, "$name: UpdateSetList: setList=$hash->{'.setList'}";
    Log3 $name, 5, "$name: UpdateSetList: getList=$hash->{'.getList'}";
    $hash->{'.updateSetGet'} = 0;
    return;
}


############################################################
# Get Funktion für logische Geräte / Module
sub GetLDFn {
    my @getValArr = @_;                     # rest is optional values
    my $hash      = shift @getValArr;       # reference to device hash
    my $name      = shift @getValArr;       # device name
    my $getName   = shift @getValArr;       # get option name
    my $getVal    = join(' ', @getValArr);  # optional value after get name
    my $objCombi  = ObjKey($hash, $getName);
    my $async     = AttrVal($name, "nonPrioritizedGet", 0);
    return "\"get $name\" needs at least one argument" if (!$getName);
    Log3 $name, 4, "$name: get called with $getName " . ($objCombi ? "($objCombi)" : '') if ($getName ne '?');

    if (!$objCombi) {
        UpdateGetSetList($hash) if ($hash->{'.updateSetGet'});
        #Log3 $name, 5, "$name: get $getName not found, return list $hash->{'.getList'}" if ($getName ne '?');
        return "Unknown argument $getName, choose one of $hash->{'.getList'}";
    }
    my $msg = GetSetChecks($hash, $async);
    return $msg if ($msg);                                      # no other action because io device is not usable anyway
    
    my $type = substr($objCombi, 0, 1);
    my $adr  = substr($objCombi, 1);
    delete $hash->{gotReadings};
	DoRequest($hash, {TYPE => $type, ADR => $adr, OPERATION => 'read', DBGINFO => "get $getName", FORCE => !$async});
    # doRequest calls queueRequest and then either processRequestQueue diretly or sets timer so no further startQueueTimer necessary
    #StartQueueTimer($hash, \&Modbus::ProcessRequestQueue, {delay => 0});    # call processRequestQueue at next possibility (others waiting?)
    if (!$async) {
        my $err = ReadAnswer(GetIOHash($hash));
        return $err if ($err);
    }
    return $hash->{gotReadings}{$getName};
}


################################################################
# check, encode / format the value to be set
# called from setLDFn
sub FormatSetVal {
    my $hash     = shift;
    my $objCombi = shift;
    my $setVal   = shift;
    my $name     = $hash->{NAME};

    my $unpack   = ObjInfo($hash, $objCombi, 'unpack');   
    my $len      = ObjInfo($hash, $objCombi, 'len'); 
    my $type     = substr($objCombi, 0, 1);
    my $fCode    = GetFC($hash, {TYPE => $type, LEN => $len, OPERATION => 'write'});
    my $rawVal   = $setVal;

    # 1. Schritt: Map prüfen
    $rawVal = MapConvert ($hash, {map => ObjInfo($hash, $objCombi, 'map'), 
                                  val => $rawVal, reverse => 1, undefIfNoMatch => 1});
    return (undef, "set value $setVal did not match defined map") if (!defined($rawVal));
    
    # 2. Schritt: falls definiert Min- und Max-Werte prüfen
    if (!CheckRange($hash, {val => $rawVal, min => ObjInfo($hash, $objCombi, 'min'), max => ObjInfo($hash, $objCombi, 'max')} ) ) {
        return (undef, "value $rawVal is not within defined min/max range");
    }
    if (!looks_like_number $rawVal && !ObjInfo($hash, $objCombi, 'textArg')) {
        Log3 $name, 3, "$name: set value $rawVal is not numeric and textArg not specified";
        return (undef, "Set Value $rawVal is not numeric and textArg not specified");
    }
    
    # 3. Schritt: Konvertiere mit setexpr falls definiert
    $rawVal = EvalExpr($hash, {expr => ObjInfo($hash, $objCombi, 'setexpr'), val => $rawVal});
    
    # 4. Schritt: Pack value
    my $packedVal;
    if ($fCode == 5) {                                      # special treatment when writing one coil
        my $oneCode = uc DevInfo($hash, 'c', 'brokenFC5', 'FF00');
        $packedVal = pack ('H4', ($rawVal ? $oneCode : '0000'));
        Log3 $name, 5, "$name: set packed coil to hex " . unpack ('H*', $packedVal);
    } 
    else {                                                  # other function code
        $packedVal = pack ($unpack, $rawVal);   
        Log3 $name, 5, "$name: set packed hex " . unpack ('H*', $rawVal) . " with $unpack to hex " . unpack ('H*', $packedVal);
    }
    # 5. Schritt: RevRegs / SwapRegs if needed
    $packedVal = ReverseWordOrder($hash, $packedVal, $len) if (ObjInfo($hash, $objCombi, 'revRegs'));
    $packedVal = SwapByteOrder($hash, $packedVal, $len) if (ObjInfo($hash, $objCombi, 'bswapRegs'));
    return ($packedVal, undef);
}


################################################################
# set funktion für logische Geräte
sub SetLDFn {
    my @setValArr = @_;                     # remainder is set values 
    my $hash      = shift @setValArr;       # reference to Fhem device hash
    my $name      = shift @setValArr;       # Fhem device name
    my $setName   = shift @setValArr;       # name of the set option
    my $setVal    = join(' ', @setValArr);  # set values as one string   
    my $async     = AttrVal($name, 'nonPrioritizedSet', 0);

    return "\"set $name\" needs at least an argument" if (!$setName);
    
    if (AttrVal($name, 'enableControlSet', 1)) {        # spezielle Sets freigeschaltet?
        my $error = ControlSet($hash, $setName, $setVal);
        return if (defined($error) && $error eq '0');   # control set found and done.
        return $error if ($error);                      # error
        # continue if ControlSet function returned undef
    }
    
    my $objCombi = ObjKey($hash, $setName);

    Log3 $name, 4, "$name: set called with $setName " . ($objCombi ? "($objCombi) " : ' ') . 
            (defined($setVal) ? "setVal = $setVal" :'') if ($setName ne '?');
    
    if (!$objCombi) {
        UpdateGetSetList($hash) if ($hash->{'.updateSetGet'});
        #Log3 $name, 5, "$name: set $setName not found, return list $hash->{'.setList'}" if ($setName ne '?');
        return "Unknown argument $setName, choose one of $hash->{'.setList'}";
    } 
    if (!defined($setVal)) {
        Log3 $name, 3, "$name: set without value for $setName";
        return "No Value given to set $setName";
    }
    
    my $msg = GetSetChecks($hash, $async);
    return $msg if ($msg);                              # no other action because io device is not usable anyway
    
    my ($packedVal, $error) = FormatSetVal($hash, $objCombi, $setVal);
    return $error if ($error);

    my $type   = substr($objCombi, 0, 1);
    my $adr    = substr($objCombi, 1);
    my $len    = ObjInfo($hash, $objCombi, 'len');
    #my $fCode  = DevInfo($hash, $type, 'write', $defaultFCode{$type}{write});
    my $fCode  = GetFC($hash, {TYPE => $type, LEN => $len, OPERATION => 'write'});
    my $ioHash = GetIOHash($hash);                      # ioHash has been checked in GetSetChecks above already
    DoRequest($hash, {TYPE => $type, ADR => $adr, LEN => $len, OPERATION => 'write', VALUES => $packedVal, FORCE => !$async, DBGINFO => "set $setName"});
    StartQueueTimer($hash, \&Modbus::ProcessRequestQueue, {delay => 0});    # call processRequestQueue at next possibility (others waiting?)
    if (!$async) {
        my $err = ReadAnswer($ioHash);
        return $err if ($err);
    }
    if ($fCode == 15 || $fCode == 16) {                 # read after write
        Log3 $name, 5, "$name: set is sending read after write";
        DoRequest($hash, {TYPE => $type, ADR => $adr, OPERATION => 'read', FORCE => !$async, DBGINFO => "set $setName Rd"});
        if (!$async) {
            my $err = ReadAnswer($ioHash);
            return "$err (in read after write for FCode $fCode)" if ($err);          
        }
    }
    return;     # no return code if no error 
}


########################################################################
# SET command - handle predefined control sets fpr logical device
sub ControlSet {
    my $hash    = shift;
    my $setName = shift;
    my $setVal  = shift;
    my $name    = $hash->{NAME};
    
    if ($setName eq 'interval') {
        return 'set interval is only allowed when Fhem is Modbus master' if ($hash->{MODE} ne 'master');
        if (!$setVal || $setVal !~ m{ \A [0-9.]+ (\.[0-9]+)? \z}xms ) {
            Log3 $name, 3, "$name: set interval $setVal not valid";
            Log3 $name, 3, "$name: continuing with $hash->{Interval} (sec)" if ($hash->{Interval});
            return 'No valid Interval specified';
        } 
        $hash->{Interval} = $setVal;
        Log3 $name, 3, "$name: set interval changed interval to $hash->{Interval} seconds";
        UpdateTimer($hash, \&Modbus::GetUpdate, 'start');           # set / change timer
        return '0';
    } 
    if ($setName eq 'reread') {
        return "set reread is only allowed when Fhem is Modbus master" if ($hash->{MODE} ne 'master');
        GetUpdate("reread:$name");
        return '0';
    } 
    if ($setName eq 'reconnect') {     
        if (!$hash->{TCPConn} && $hash->{TYPE} ne 'Modbus') {
            Log3 $name, 3, "$name: reconnect only possible for physical or TCP connections, not for logical devices";
            return 'reconnect only possible for physical or TCP connections, not for logical devices';
        }
        # todo: close and immediate reopen might case problems on windows with usb device - needs testing on windows

        my $msg = CheckDisable($hash);
        return $msg if ($msg);

        DoOpen($hash, {CLOSEFIRST => 1});    # async but close first
        return '0';
    } 
    if ($setName eq 'close') {     
        if (!$hash->{TCPConn} && $hash->{TYPE} ne 'Modbus') {
            Log3 $name, 3, "$name: close only possible for physical or TCP connections, not for logical devices";
            return 'close only possible for physical or TCP connections, not for logical devices';
        }
        DoClose($hash);         # should be called with hash of physical device but for TCP it's the same
        return '0';
    } 
    if ($setName eq 'active' && AttrVal($name, 'enableSetInactive', 1) ) {
        return 'device is disabled' if (AttrVal($name, 'disable', 0));
        SetStates($hash, 'active');
        SetLDActive($hash);
        return '0';
    } 
    if ($setName eq 'inactive' && AttrVal($name, 'enableSetInactive', 1)) {
        return 'device is disabled' if (AttrVal($name, 'disable', 0));
        SetStates($hash, 'inactive');
        SetLDInactive($hash);
        return '0';
    }     
    if ($setName eq 'stop') {
        return "set stop is only allowed when Fhem is Modbus master" if ($hash->{MODE} ne 'master');
        UpdateTimer($hash, \&Modbus::GetUpdate, 'stop');
        return '0';
    } 
    if ($setName eq 'start') {
        my $msg = CheckDisable($hash);
        return $msg if ($msg);

        return 'set start is only allowed when Fhem is Modbus master' if ($hash->{MODE} ne 'master');
        UpdateTimer($hash, \&Modbus::GetUpdate, 'start');           # set / change timer
        return '0';
    } 
    if ($setName eq 'scanStop') {
        Log3 $name, 3, '$name: scanStop - try asyncOutput to $hash';
        my $cl = $hash->{CL};
        asyncOutput($cl, 'Hallo <b>Du</b>');
        
        my $msg = CheckDisable($hash);
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
        return '0';
    } 
    if ($setName eq 'scanModbusId') {
        my $msg = CheckDisable($hash);
        return $msg if ($msg);
        return 'set scanModbusId is only allowed when Fhem is Modbus master' if ($hash->{MODE} ne 'master');
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
        my $scanDelay  = AttrVal($name, 'scanDelay', 1);  
        RemoveInternalTimer ("scan:$name");
        InternalTimer($now+$scanDelay, \&Modbus::ScanIds, "scan:$name", 0);   
        return '0';
    } 
    if ($setName eq 'scanModbusObjects') { 
        my $msg = CheckDisable($hash);
        return $msg if ($msg);
        return 'set scanModbusObjects is only allowed when Fhem is Modbus master' if ($hash->{MODE} ne 'master');
        delete $hash->{scanId};
        delete $hash->{scanIdStart};
        delete $hash->{scanIdEnd};
        $hash->{scanOType}  = 'h';
        $hash->{scanOStart} = '1';
        $hash->{scanOEnd}   = '16384';
        $hash->{scanOLen}   = '1';
        if ($setVal && $setVal =~ /([hicd][0-9]+) *- *([hicd]?([0-9]+)) ?(len)? ?([0-9]+)?/) {
            $hash->{scanOType}  = substr($1,0,1);
            $hash->{scanOStart} = substr($1,1);
            $hash->{scanOEnd}   = $3;
            $hash->{scanOLen}   = ($5 ? $5 : 1);
        }
        Log3 $name, 3, "$name: set scan $hash->{scanOType} from $hash->{scanOStart} to $hash->{scanOEnd} len $hash->{scanOLen}";        
        delete $hash->{scanOAdr};
        
        my $now        = gettimeofday();
        my $scanDelay  = AttrVal($name, 'scanDelay', 1);  
        RemoveInternalTimer ("scan:$name");
        InternalTimer($now+$scanDelay, \&Modbus::ScanObjects, "scan:$name", 0);
        return '0';
    } 
    if ($setName eq 'saveAsModule') {         
        return SaveAsModule ($hash, $setVal);
    }
    if ($setName eq 'createAttrsFromParseInfo') {         
        return createAttrsFromParseInfo ($hash);
    }

    return;   # no control set identified - continue with other sets
}


####################################################################
# create a Fhem module file based on the current configuration 
# in attributes
sub createAttrsFromParseInfo {
    my $hash      = shift;
    my $name      = $hash->{NAME};
    my $modHash   = $modules{$hash->{TYPE}};
    my $parseInfo = $modHash->{parseInfo};
    my $devInfo   = $modHash->{deviceInfo};
    my $last      = 'x';

    #Log3 $name, 3, "$name: createAttrsFromParseInfo called, TYPE $hash->{TYPE}, parseInfo $parseInfo";
    foreach my $a (sort keys %{$parseInfo}) {
        if ($a =~ /([ihcd])(\d+)/) {
            my $type = $1;
            my $adr  = $2;
            foreach my $k (sort keys %{$parseInfo->{$a}}) {
                my $attrName = "obj-$type$adr-$k";
                my $val      = $parseInfo->{$a}{$k};
                #Log3 $name, 3, "$name: createAttrsFromParseInfo working on $attrName $val";
                if (exists $attr{$name}{$attrName}) {
                    if ($attr{$name}{$attrName} ne $val) {
                        return "createAttrsFromParseInfo aborted because attr $attrName already exists with value $attr{$name}{$attrName} (parseInfo contains $val)";
                    }
                }
                CommandAttr(undef, "$name $attrName $val");
            }
        }
    }
    foreach my $a (sort keys %{$devInfo}) {
        foreach my $k (sort keys %{$devInfo->{$a}}) {
            my $attrName = "dev-$a-$k";
            my $val      = $devInfo->{$a}{$k};
            #Log3 $name, 3, "$name: createAttrsFromParseInfo working on $attrName $val";
            if (exists $attr{$name}{$attrName}) {
                if ($attr{$name}{$attrName} ne $val) {
                    return "createAttrsFromParseInfo aborted because attr $attrName already exists with value $attr{$name}{$attrName} (devInfo contains $val)";
                }
            }
            CommandAttr(undef, "$name $attrName $val");
        }
    }
    Log3 $name, 3, "$name: createAttrsFromParseInfo done";
    return '0';
}


####################################################################
# create a Fhem module file based on the current configuration 
# in attributes
sub SaveAsModule {
    my $hash  = shift;
    my $fName = shift;
    my $name  = $hash->{NAME};
    my $tFile = 'lib/FHEM/Modbus/modTemplate';
    my $oFile = "/tmp/98_ModbusGen$fName.pm";
    my $tmpl;
    if (!open($tmpl, "<", $tFile)) {
        Log3 $name, 3, "$name: Cannot open template file $tFile";
        return "cannot open $tFile";
    };
    my $content = '';
    while (<$tmpl>) {
        $content .= $_;
    }
    close $tmpl;
    Log3 $name, 3, "$name: template file $tFile read successfully";

    my $t     = '';
    my $last  = 'x';
    foreach my $a (sort keys %{$attr{$name}}) {
        if ($a =~ /^obj-([^\-]+)-(.*)$/) {
            my $adr = $1;
            my $key = $2;
            if ($1 ne $last) {
                $t .= sprintf "%26s", "},\n" if ($last ne "x"); 
                $t .= sprintf "%2s", " " . sprintf "%16s%s", "\"$adr\"", " =>  { ";
                $last = $adr;
            } else {
                $t .= sprintf "%25s", " ";
            }
            my $aVal = $attr{$name}{$a};
            $aVal =~ s/\'/\\\'/g;
            $t .= sprintf "%15s%s", "\'".$key."\'", " => \'$aVal\',\n";
        }
    }
    $t .= sprintf "%28s", "}\n);\n\n" if ($last ne 'x');

    $t .= "my %ModbusGen${fName}deviceInfo = (\n";
    $last = "x";
    foreach my $a (sort keys %{$attr{$name}}) {
        if ($a =~ /^dev-((type-)?[^\-]+)-(.*)$/) {
            if ($1 ne $last) {
                $t .= sprintf "%26s", "},\n" if ($last ne "x");
                $t .= sprintf "%2s", " " . sprintf "%16s%s", "\"$1\"", " =>  { ";
                $last = $1;
            } else {
                $t .= sprintf "%25s", " ";
            }
            $t .= sprintf "%15s%s", "\'".$3."\'", " => \'$attr{$name}{$a}\',\n";
        }
    }
    $t .= sprintf "%28s", "}\n);\n\n" if ($last ne 'x');

    $content =~ s/(\$\{.*\})/$1/gee;
    my $out;
    if (!open($out, '>', $oFile)) {         ## no critic 
        Log3 $name, 3, "$name: set saveAsModule cannot create output file $oFile";
        return "saveAsModule cannot create output file $oFile";
    }
    print $out $content;
    close $out;
    Log3 $name, 3, "$name: set saveAsModule created $oFile";
    return "0"; 
}


###############################################################
# called via internal timer from 
# logical device module with 
# scan:name - name of logical device
#
sub ScanObjects {
    my $param      = shift;
    my ($calltype,$name) = split(':',$param);
    my $hash       = $defs{$name};   # hash des logischen Devices, da GetUpdate aus dem logischen Modul per Timer gestartet wird
    my $now        = gettimeofday();
    my $scanDelay  = AttrVal($name, 'scanDelay', 1);  
    my $ioHash     = GetIOHash($hash);         # get ioHash to check for full queue. It has been checked in GetSetChecks
    my $queue      = $ioHash->{QUEUE};
    my $qlen       = ($ioHash->{QUEUE} ? scalar(@{$ioHash->{QUEUE}}) : 0);
    my $qMax       = AttrVal($ioHash->{NAME}, 'queueMax', AttrVal($name, 'queueMax', 100));
    RemoveInternalTimer ("scan:$name");
    if ($qlen && $qlen > $qMax / 2) {
        InternalTimer($now+$scanDelay, \&Modbus::ScanObjects, "scan:$name", 0);
        Log3 $name, 5, "$name: ScanObjects waits until queue gets smaller";
        return;
    }
    if (defined($hash->{scanOAdr})) {
        if ($hash->{scanOAdr} >= $hash->{scanOEnd}) {
            delete $hash->{scanOAdr};
            delete $hash->{scanOStart};
            delete $hash->{scanOEnd};
            delete $hash->{scanOType};
            delete $hash->{scanOLen};
            Log3 $name, 4, "$name: ScanObjects called from " . FhemCaller() . " ends at " . 
                ($hash->{scanOType} // '') . ($hash->{scanOAdr} //'');
            return; # end
        }
       $hash->{scanOAdr}++;
    } 
    else {        
        $hash->{scanOAdr} = $hash->{scanOStart};
    }
    Log3 $name, 4, "$name: ScanObjects called from " . FhemCaller() . " will now try " . 
        ($hash->{scanOType} // '') . ($hash->{scanOAdr} //'');
    DoRequest($hash, {TYPE => $hash->{scanOType}, ADR => $hash->{scanOAdr}, 
        OPERATION => 'scanobj', LEN => $hash->{scanOLen}, DBGINFO => 'scan objs'});
    InternalTimer($now+$scanDelay, \&Modbus::ScanObjects, "scan:$name", 0);
    return;
}


####################################################################
# called via internal timer from 
# logical device module with 
# scan:name - name of logical device
#
sub ScanIds {
    my $param      = shift;
    my ($calltype,$name) = split(':',$param);
    my $hash       = $defs{$name};   # hash des logischen Devices, da GetUpdate aus dem logischen Modul per Timer gestartet wird
    my $now        = gettimeofday();
    my $scanDelay  = AttrVal($name, 'scanDelay', 1);  
    my $ioHash     = GetIOHash($hash);         # get ioHash to check for full queue. It has been checked in GetSetChecks
    my $queue      = $ioHash->{QUEUE};
    my $qLen       = ($ioHash->{QUEUE} ? scalar(@{$ioHash->{QUEUE}}) : 0);
    my $qMax       = AttrVal($ioHash->{NAME}, 'queueMax', AttrVal($name, 'queueMax', 100));
    
    RemoveInternalTimer ("scan:$name");
    if ($qLen && $qLen > $qMax) {
        InternalTimer($now+$scanDelay, \&Modbus::ScanIds, "scan:$name", 0);
        Log3 $name, 5, "$name: ScanIds waits until queue gets smaller";
        return;
    }
    if ($hash->{scanId}) {
        if ($hash->{scanId} >= $hash->{scanIdEnd}) {
            delete $hash->{scanId};
            delete $hash->{scanIdStart};
            delete $hash->{scanIdEnd};
            delete $hash->{scanOAdr};
            delete $hash->{scanOLen};
            delete $hash->{scanOType};
            Log3 $name, 4, "$name: ScanId called from " . FhemCaller() . " will ends with id " . 
                (delete $hash->{scanId} // '') . ' ' . ($hash->{scanOType} // '') . ($hash->{scanOAdr} //'');
            return; # end
        }
        $hash->{scanId}++;
    } 
    else {        
        $hash->{scanId} = $hash->{scanIdStart};
    }
    Log3 $name, 4, "$name: ScanId called from " . FhemCaller() . " will now try id " . 
        ($hash->{scanId} // '') . ' ' . ($hash->{scanOType} // '') . ($hash->{scanOAdr} //'');
    DoRequest($hash, {TYPE => $hash->{scanOType}, ADR => $hash->{scanOAdr}, 
        OPERATION => 'scanid'.$hash->{scanId}, LEN => $hash->{scanOLen}, DBGINFO => 'scan ids'});
    InternalTimer($now+$scanDelay, \&Modbus::ScanIds, "scan:$name", 0);
    return;
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
# könnte man $hash{NOTIFYDEV} auf ',' setzen und %ntfyHash auf () löschen...
# 
# im Modul die NotifyFn zu entfernen würde den Aufruf verhindern, aber 
# $hash{NTFY_ORDER} bleibt und daher erzeugt auch createNtfyHash() immer wieder verweise
# auf das Gerät, obwohl die NotifyFn nicht mehr registriert ist ...
sub NotifyFn {
    my $hash   = shift;
    my $source = shift;
    my $name   = $hash->{NAME};             # my Name
    my $sName  = $source->{NAME};           # Name of Device that created the events
    return if($sName ne 'global');          # only interested in global Events

    my $events = deviceEvents($source, 1);
    return if(!$events);                    # no events
    
    #Log3 $name, 5, "$name: Notify called for source $source->{NAME} with events: @{$events}";
    return if (!grep {m/^INITIALIZED|REREADCFG|(MODIFIED $name)$|(DEFINED $name)$/}  @{$events});
    # DEFINED is not triggered if init is not done.
    
    if (IsDisabled($name)) {
        Log3 $name, 3, "$name: Notify / Init: device is disabled";
        return;
    }   
    if ($hash->{TYPE} eq 'Modbus' || $hash->{TCPConn}) {	# physical or TCP -> call open (even for slave)
        Log3 $name, 4, "$name: Notify / Init: opening connection";
        DoOpen($hash, {CLOSEFIRST => 1}) if (!AttrVal($name, 'closeAfterResponse', 0) || $hash->{MODE} ne 'master');
        # connection or listening socket for tcp slave
    } 
    else {                                            	    # logical dev and not TCP  -> check for IO Device
        delete $hash->{IODev};                          	# force call to setIODev / register and set state to opened
        my $ioHash = GetIOHash($hash);                      # get / search and register at iodev
        Log3 $name, 3, "$name: Notify / Init: " . ($ioHash ? "using $ioHash->{NAME}" : "no IODev") . " for communication";
    }
    if ($hash->{TYPE} ne 'Modbus' && $hash->{MODE} eq 'master') {   # Mode Master     
        UpdateTimer($hash, \&Modbus::GetUpdate, 'start');
    } 
    elsif ($hash->{MODE} && $hash->{MODE} eq 'relay') {             # Mode relay -> find / check relay device
        my $reName = $hash->{RELAY};
        my $reIOHash = GetRelayIO($hash);
        Log3 $name, 3, "$name: Notify / Init: " . ($reIOHash ? "using $reIOHash->{NAME}" : "no device") . " as Modbus relay device (master)";
    }
    #Log3 $name, 3, '$name: _Notify done';
    return;
}


##############################################################
# open connection 
# $hash is physical or both (connection over TCP)
# called from set reconnect, Attr / LDAttr (disable), 
#        Notify (initialized, rereadcfg, |(MODIFIED $name)), 
#        Ready, ProcessRequestQueue and GetSetChecks
sub DoOpen {
    my $hash    = shift;
    my $arg_ref = shift // {};
    my $ready   = $arg_ref->{READY} // 0;
    my $name    = $hash->{NAME};
    my $now     = gettimeofday();
    my $caller  = FhemCaller();
    
    if ($hash->{DeviceName} eq 'none') {
        Log3 $name, 5, "$name: open called from $caller, device is defined with none" if ($caller ne 'Ready'); 
        SetStates($hash, 'opened');
    } 
    elsif (!$hash->{TCPConn} && $hash->{TYPE} ne 'Modbus') {
        Log3 $name, 3, "$name: open called from $caller for logical device - this should not happen";
        return;
    }
    elsif ($hash->{TCPChild}) {
        Log3 $name, 3, "$name: open called for a TCP Child hash - this should not happen";
        return;
    }
    elsif ($hash->{TCPServer}) {
        # Modbus slave or relay over TCP connection -> open listening port
        Log3 $name, 5, "$name: Open called for listening to a TCP connection";
        if ($arg_ref->{CLOSEFIRST} && IsOpen($hash)) {
            DoClose($hash, 1);                      # close, set Expect, clear Buffer, don't set state
        }
        my ($dest, $port) = split(/[:\s]+/, $hash->{DeviceName});
        my $ret = TcpServer_Open($hash, $port, $dest);
        if ($ret) {
            Log3 $name, 3, "$name: TcpServerOpen returned $ret";
        } else {
            SetStates($hash, 'opened');
        }
    } 
    else {
        my $timeOt = AttrVal($name, 'openTimeout', 3);
        my $delay2 = AttrVal($name, 'nextOpenDelay2', 1);
        my $nextOp = $hash->{NEXT_OPEN} // 0;
        #Log3 $name, 5, "$name: Open nextOpenDelay = $delay2 ";
        my $lastOp = $hash->{LASTOPEN};                     # set when OpenDev is really called and cleared in DoClose
        Log3 $name, 5, "$name: open called from $caller, busyOpenDev " . 
            ($hash->{BUSY_OPENDEV} // 0) . ($nextOp ? ' NEXT_OPEN ' . FmtTimeMs($nextOp) : '') if (!$ready); 
        if ($hash->{BUSY_OPENDEV}) {                        # still waiting for callback to last open 
            return if (!$lastOp || $now < $lastOp + ($timeOt * 2) || $now < $lastOp + 15);
            Log3 $name, 3, "$name: open - still waiting for open callback, timeout is over twice - this should never happen";
            Log3 $name, 3, "$name: open - stop waiting for callback and reset the BUSY flag.";
            $hash->{BUSY_OPENDEV} = 0;
        }    
        if ($arg_ref->{CLOSEFIRST} && IsOpen($hash)) {      # close first and already open
            Log3 $name, 5, "$name: Open called for DevIo connection - closing first";
            DoClose($hash, 1);                              # close, set Expect, clear Buffer, don't set state to disconnected
            delete $hash->{DevIoJustClosed};                # allow direct opening without further delay
        } elsif ($nextOp && ($nextOp > $now)) {
            Log3 $name, 5, "$name: open ignored because DevIo has set NEXT_OPEN to $nextOp / " . FmtTimeMs($nextOp) .
                " and now is $now / " . FmtTimeMs($now);
            return;
        }
        if ($lastOp && $now < ($lastOp + $delay2)) {        # ignore too many open requests within nextOpenDelay2
            Log3 $name, 5, "$name: successive open ignored, last open was " . 
                sprintf('%3.3f', ($now - $lastOp)) . ' secs ago at ' . FmtTimeMs($lastOp) . " but should be $delay2" if (!$ready);
            return;
        }
        Log3 $name, 4, "$name: open trying to open connection to $hash->{DeviceName}" if (!$ready);
        delete $hash->{NEXT_OPEN};                          # already handled above
        delete $hash->{DevIoJustClosed} if ($delay2);       # allow direct opening without further delay
        $hash->{IODev}          = $hash if ($hash->{TCPConn});     # point back to self
        $hash->{LASTOPEN}       = $now;
        $hash->{nextOpenDelay}  = AttrVal($name, 'nextOpenDelay', 60);   
        $hash->{devioLoglevel}  = (AttrVal($name, 'silentReconnect', 0) ? 4 : 3);
        $hash->{TIMEOUT}        = $timeOt;
        if ($arg_ref->{FORCE}) {
            DevIo_OpenDev($hash, $ready, 0);                # standard open
            OpenCB($hash);                                  # do remaining steps (callback not specified in above call)
        } 
        else {
            $hash->{BUSY_OPENDEV} = 1;
            DevIo_OpenDev($hash, $ready, 0, \&OpenCB);      # async open
        }
    }
    Profiler($hash, 'Idle');                                # set category to book following time, can be Delay, Fhem, Idle, Read, Send or Wait
    ResetExpect($hash);
    StartQueueTimer($hash, \&Modbus::ProcessRequestQueue, {delay => 0.5, silent => 0});      # process queue in case something is waiting but delay so open can call back
    DropBuffer($hash);
    delete $hash->{TIMEOUT};
    return;
}


#####################################
sub OpenCB {
    my $hash = shift;
    my $msg  = shift;
    my $name = $hash->{NAME};
    if ($msg) {
        Log3 $name, 5, "$name: Open callback: $msg" if ($msg);
    }
    delete $hash->{BUSY_OPENDEV};
    if (IsOpen($hash)) {
        delete $hash->{TIMEOUTS} ;
        UpdateTimer($hash, \&Modbus::GetUpdate, 'start');           # set / change timer
    } 
    return;
}


##################################################
# close connection 
# $hash is physical or both (connection over TCP)
sub DoClose {
    my ($hash, $noState, $noDelete) = @_;
    my $name = $hash->{NAME};
    
    if (!$hash->{TCPConn} && $hash->{TYPE} ne 'Modbus') {
        Log3 $name, 3, "$name: close called from " . FhemCaller() . 
                        ' for logical device - this should not happen';
        return;
    }
    
    Log3 $name, 5, "$name: Close called from " . FhemCaller() . 
        ($noState || $noDelete ? ' with ' : '') . ($noState ? 'noState' : '') .     # set state?
        ($noState && $noDelete ? ' and ' : '') . ($noDelete ? 'noDelete' : '');     # command delete on connection device?
    
    delete $hash->{LASTOPEN};                           # reset so next open will actually call OpenDev
    if ($hash->{TCPChild} && IsOpen($hash)) {           # this is a slave or relay connection hash
        Log3 $name, 4, "$name: Close TCP server listening connection and delete hash";
        TcpServer_Close($hash);
        RemoveInternalTimer ("stimeout:$name");
        CommandDelete(undef, $name) if (!$noDelete);
        if ($hash->{CHILDOF} && $hash->{CHILDOF}{LASTCONN} && $hash->{CHILDOF}{LASTCONN} eq $hash->{NAME}) {
            Log3 $name, 5, "$name: Close is removing lastconn from parent device $hash->{CHILDOF}{NAME}";
            delete $hash->{CHILDOF}{LASTCONN}
        }
    } 
    elsif ($hash->{TCPServer} && IsOpen($hash)) {       # this is a slave or relay listening device
        Log3 $name, 4, "$name: Close TCP server socket, now look for active connections";
        TcpServer_Close($hash);
        foreach my $conn (keys %{$hash->{CONNECTHASH}}) {
            my $chash = $hash->{CONNECTHASH}{$conn};
            TcpServer_Close($chash);
            Log3 $chash->{NAME}, 4, "$chash->{NAME}: Close TCP server connection of parent $name and delete hash";
            RemoveInternalTimer ("stimeout:$chash->{NAME}");
            CommandDelete(undef, $chash->{NAME}) if (!$noDelete);
        }
        delete $hash->{CONNECTHASH};    # delete hash containing the connection devices
        Log3 $name, 5, "$name: Close deleted the CONNECTHASH";
    } 
    elsif ($hash->{DeviceName} eq 'none') {
        Log3 $name, 4, "$name: Simulate closing connection to none";
    } 
    else {
        Log3 $name, 4, "$name: Close connection with DevIo_CloseDev";
        # close even if it was not open yet but on ready list (need to remove entry from readylist)
        DevIo_CloseDev($hash);
    }
    SetStates($hash, 'disconnected') if (!$noState);
    ResetExpect($hash);
    DropBuffer($hash);
    Profiler($hash, 'Idle');                   # set category to book following time, can be Delay, Fhem, Idle, Read, Send or Wait
    StopQueueTimer($hash, {silent => 1});
    RemoveInternalTimer ("timeout:$name");
    delete $hash->{nextTimeout};
    delete $hash->{QUEUE};
    return;
}
    

###########################################################################
# ready fn for physical device
# and logical device (in case of tcp when logical device opens connection)
sub ReadyFn {
    my $hash = shift;
    my $name = $hash->{NAME};
    
    if($hash->{STATE} eq 'disconnected') {
        if (IsDisabled($name)) {
            Log3 $name, 3, "$name: ready called but $name is disabled - don't try to reconnect - call DoClose";
            DoClose($hash, 1);          # close, set Expect, clear Buffer, don't set state to disconnected (must have already been done)
            UpdateTimer($hash, \&Modbus::GetUpdate, 'stop');
            return;
        }
        DoOpen($hash, {READY => 1});    # reopen, dont call DevIoClose before reopening
        return;                         # a return value only triggers direct read for windows - main loop select
    }
    # This is relevant for windows/USB only
    my $po = $hash->{USBDev};
    if ($po) {
        my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
        return ($InBytes>0);            # tell fhem.pl to read when we return if data available
    }
    return;
}


############################################################################
# Called from the global loop, when the select for hash->{FD} reports data
# hash is hash of the physical device ( = logical device for TCP)
# this creates a new connection device
sub HandleServerConnection {
    my $hash  = shift;
    my $name  = $hash->{NAME};
    my $chash = TcpServer_Accept($hash, $hash->{TYPE}); # accept with this module
    return if(!$chash);
    $chash->{CD}->flush();
    Log3 $name, 4, "$name: HandleServerConnection accepted new TCP connection as device $chash->{NAME}";
    $chash->{MODBUSID}   = $hash->{MODBUSID};
    $chash->{PROTOCOL}   = $hash->{PROTOCOL};
    $chash->{MODE}       = $hash->{MODE};
    $chash->{RELAY}      = $hash->{RELAY};
    $chash->{CHILDOF}    = $hash;                               # point to parent device to get object definitions from there
    $chash->{IODev}      = $chash;
    $chash->{TCPConn}    = 1;
    $chash->{TCPChild}   = 1;
    $chash->{DeviceName} = $hash->{DeviceName};
    ResetExpect($chash);
    # DoTrigger('global', "DEFINED $chash->{NAME}", 1) if($init_done);
    # dotrigger is probably not helpful here. However it will not cause NotifyFn since the ecebt is not global ...
    
    $attr{$chash->{NAME}}{verbose} = $attr{$name}{verbose};     # copy verbose attr from parent
    $hash->{LASTCONN} = $chash->{NAME};                         # point from parent device to last connection device
    $hash->{CONNECTHASH}{$chash->{NAME}} = $chash;
    my $room = AttrVal($name, 'connectionsRoom', 'Connections');
    if ($room !~ '[Nn]one') {
        CommandAttr(undef, "$chash->{NAME} room $room");        # set room
    }
    
    my $to = gettimeofday() + DevInfo($hash, 'timing', 'serverTimeout', 120); 
    InternalTimer($to, \&Modbus::ServerTimeout, "stimeout:$chash->{NAME}", 0);

    return;
}


##############################################
# check time gap between now and last read
# to clear old buffer or set expect to request
sub HandleGaps {
    my $hash = shift;               # physical device hash
    my $name = $hash->{NAME};
    my $now  = gettimeofday();

    # check time since last read / frameGap and remove old buffer if necessary
    if (!$hash->{REMEMBER}{lrecv}) {
        DropBuffer($hash, '(initialisation)');
        return;
    }
    my $gap = ($now - $hash->{REMEMBER}{lrecv});
    my $fTo = AttrVal($name, 'frameGap', 1.5);
    if ($gap > $fTo && $hash->{READ}{BUFFER}) {
        DropBuffer($hash, 'after gap of ' . sprintf ('%.2f', $gap) . ' secs.');
    }
    # also check if EXPECT should be reset 
    # Mode slave or relay: (receiving side): if we reading something after a long delay it has to be a new request
    # Mode passive: use DevInfo($hash, 'timing', 'timeout', 2) as timout to switch from response to request
    # Mode master: is only reading responses, anything else is an error. Nothing to be done here
    my $to = DevInfo($hash, 'timing', 'timeout', 2); 
    if ($gap > $to) {
        if ($hash->{MODE} ne 'master') {
            ResetExpect($hash, 'read gap is more than response timeout');
        }
    }
    return;
}


###########################################################################
# Called from the global loop, when the select for hash->{FD} reports data
# hash is hash of the physical device ( = logical device for TCP)
sub ReadFn {
    my $hash = shift;
    my $name = $hash->{NAME};
    my $now  = gettimeofday();
    my ($buf, $ret);
    
    # first get data from socket / serial device into buffer
    if ($hash->{DeviceName} eq 'none') {            # simulate receiving
        if ($hash->{TestInput}) {
            $buf = $hash->{TestInput};
            delete $hash->{TestInput};
        }
    } 
    elsif($hash->{TCPServer} || $hash->{TCPChild}) {   
        if($hash->{SERVERSOCKET}) {             # this is a TCP server / modbus slave device 
            HandleServerConnection($hash);      # accept and create a child device hash for the connection
            return;
        } 
        # TCP client device connection device hash
        Profiler($hash, 'Read');            # read from TCP socket
        $ret = sysread($hash->{CD}, $buf, 256) if ($hash->{CD});
        if(!defined($ret) || $ret <= 0) {   # connection closed
            Log3 $name, 3, "$name: read from TCP server connection got null -> closing";
            CommandDelete(undef, $name);
            return;
        }
        RemoveInternalTimer ("stimeout:$name");
        my $to = $now + DevInfo($hash, 'timing', 'serverTimeout', 120); 
        InternalTimer($to, \&Modbus::ServerTimeout, "stimeout:$name", 0);
    } 
    else {
        Profiler($hash, 'Read'); 
        $buf = DevIo_SimpleRead($hash);         # read from serial connection
        return if(!defined($buf));
    }

    HandleGaps ($hash);                         # check timing / frameGap and remove old buffer if necessary
    $hash->{READ}{BUFFER} .= $buf;              # now add new data to buffer
    $hash->{REMEMBER}{lrecv} = $now;            # rember time for physical side
    Log3 $name, 5, "$name: readFn buffer: " . ShowBuffer($hash);
    delete $hash->{FRAME};                      # remove old stuff

    if (!$hash->{MODE} || !$hash->{PROTOCOL}) { # MODE and PROTOCOL keys are taken from logical device in NOTIFY
        DropBuffer($hash, 'mode or protocol not set (probably no active logical device registered)');
        return;                                 # EXPECT doesn't matter, Logging frame not needed
    }
    
    for (;;) {
        # parse frame start, create $hash->{FRAME} with {MODBUSID}, {FCODE}, {DATA}
        # and for TCP also $hash->{FRAME}{PDULEXP} and $hash->{FRAME}{TID}
        if (!ParseFrameStart($hash)) {          # not enough data / no frame match
            Log3 $name, 5, "$name: readFn did not see a valid $hash->{PROTOCOL} frame start yet, wait for more data";
            return;
        }    
        my $frame = $hash->{FRAME};              # is set after calling ParseFrameStart
        
        # EXPECT exists on io dev. Special case for relays:
        #     there are two io devs. receiving side and forwarding side. 
        #     read can be called when a new request comes in on receiving side (mode relay)
        #     or when a response comes in at forwarding side (mode master)
        

        if ($hash->{EXPECT} eq 'request') {             # --- REQUEST ---
            return if (!HandleRequest($hash)) ;         # check for valid PDU, parse, return if frame not complete (yet)
            # ERROR is only set by Checksum Check or unsupported fCode here.
            if ($hash->{FRAME}{CHECKSUMERROR} && $hash->{MODE} eq 'passive') {      
                Log3 $name, 5, "$name: no valid request -> try interpretation as response instead";
                delete $hash->{REQUEST};                # this one would be invalid anyway
                delete $hash->{FRAME}{ERROR};
                return if (!HandleResponse($hash));     # try as response PDU, CRC, parse, log, return if frame not complete (yet)
            }
            DropFrame($hash);                           # drop $hash->{FRAME} and the relevant part of $hash->{READ}{BUFFER}
        } 
        elsif ($hash->{EXPECT} eq 'response') {         # --- RESPONSE ---
            return if (!HandleResponse($hash));         # check PDU, CRC, parse, log, return if frame not complete (yet)
            if ($hash->{FRAME}{CHECKSUMERROR} && $hash->{MODE} ne 'master') {
                Log3 $name, 5, "$name: no valid response -> try interpretation as request instead";
                delete $hash->{FRAME}{ERROR};
                return if (!HandleRequest($hash));      # try as response PDU, CRC, parse, log, return if frame not complete (yet)
            }
            DropFrame($hash);                           # drop $hash->{FRAME} and the relevant part of $hash->{READ}{BUFFER}
        }
        elsif ($hash->{EXPECT} eq 'idle') {             # master is doing nothing but maybe there is an illegal other master?
            Log3 $name, 3, "$name: readfn got data while EXPECT was set to idle: " . ShowBuffer($hash);
            if ($hash->{MODE} eq 'master') {
                DropBuffer($hash);
				return;
            }
            ResetExpect($hash);                         # when we are not master we should not be idle
        } 
        else {                                          # this should not be possible
            Log3 $name, 3, "$name: internal error, illegal EXPECT value " . $hash->{EXPECT} // 'undefined';
            ResetExpect($hash);
        }
        return if (!$hash->{READ}{BUFFER});             # return if no more data, else parse on
    } # next round in loop
    return; # never reached
}


################################################################################
# Called from get / set to get a direct answer - only for Fhem as master.
# Returns an error message or undef if success.
# queue timer is started after calling ReadAnswer
sub ReadAnswer {
    my $hash    = shift;                        # called with physical io device hash
    my $name    = $hash->{NAME};       
    my $logHash = $hash->{REQUEST}{MASTERHASH}; # logical device that sent last request, stored by ProcessRequestQueue
    my $timeout = DevInfo($logHash, 'timing', 'timeout', 2); 
    my $now     = gettimeofday();
    my $timeRest;
    my $rin     = '';
    my $buf;
    my $msg     = '';
    
    Log3 $name, 5, "$name: ReadAnswer called from " . FhemCaller();

    # nextTimeout is set when a request is sent. This can be the last getUpdate or the get/set
    $hash->{nextTimeout} = $now + $timeout if (!$hash->{nextTimeout});  # just to be sure, should not happen. 

    RemoveInternalTimer ("timeout:$name");              # remove timer, timeout is handled in here now
    Profiler($hash, 'Read');

    READLOOP:
    for (;;) {

        # get timeout. In case ReadAnswer is called after a delay or to take over an async read, 
        # only wait for remaining time
        $timeRest = $hash->{nextTimeout} - gettimeofday();        
        $timeout  = $timeRest if ($timeRest < $timeout);
        Log3 $name, 5, "$name: ReadAnswer remaining timeout is $timeout";        

        if ($timeout <= 0 || ($hash->{DeviceName} eq 'none' && !$hash->{TestInput})) {
            last READLOOP;                              # Timeout - will be logged after the loop
        }
        if ($hash->{DeviceName} eq 'none') {            # simulate receiving
            $buf = $hash->{TestInput};
            delete $hash->{TestInput};
        } 
        elsif ($^O =~ m/Win/ && $hash->{USBDev}) {        
            $hash->{USBDev}->read_const_time($timeout*1000); # set timeout (ms)
            $buf = $hash->{USBDev}->read(999);
            last READLOOP if(length($buf) == 0);        
        } 
        else {
            if (!$hash->{FD}) {
                $msg = "ReadAnswer called but Device $name lost connection";
                last READLOOP;                          # exit loop and report error
            }
            vec($rin, $hash->{FD}, 1) = 1;              # setze entsprechendes Bit in rin
            my $nfound = select($rin, undef, undef, $timeout);
            last READLOOP if ($nfound == 0);            # Timeout - will be logged after the loop
            if ($nfound < 0) {
                next if ($! == EAGAIN() || $! == EINTR() || $! == 0);
                $msg = 'Error in ReadAnswer: $!';
                DevIo_Disconnected($hash);              # close, set state but put back on readyfnlist for reopening
                last READLOOP;
            }
            $buf = DevIo_SimpleRead($hash);
            if (!defined($buf)) {
                $msg = 'ReadAnswer got no data';
                last READLOOP
            }
        }
        if ($buf) {
            $now = gettimeofday();
            $hash->{READ}{BUFFER} .= $buf;
            $hash->{REMEMBER}{lrecv}    = $now;
            $logHash->{REMEMBER}{lrecv} = $now;
            Log3 $name, 5, "$name: ReadAnswer got: " . ShowBuffer($hash);
        }
        
        delete $hash->{FRAME};              # remove old stuff
        # create $hash->{FRAME}{MODBUSID}, $hash->{FRAME}{FCODE}, $hash->{FRAME}{DATA}
        # and for TCP also $hash->{FRAME}{PDULEXP} and $hash->{FRAME}{TID}
        if (!ParseFrameStart($hash)) {      # not enough data / no frame match
            Log3 $name, 5, "$name: ReadAnswer got no valid frame after HandleFrameStart, wait for more data";
            next READLOOP;
        }    
        my $frame = $hash->{FRAME};         # is set after HandleFrameStart     
        if (HandleResponse($hash)) {        # end of parsing. error or valid frame, cleans up and sets Profiler to 'Idle' if done
            DropFrame($hash);               # drop $hash->{FRAME} and the relevant part of $hash->{READ}{BUFFER}
            if ($hash->{RESPONSE}{ERRCODE}) {
                my $ret = "Error code $hash->{RESPONSE}{ERRCODE} / $errCodes{$hash->{RESPONSE}{ERRCODE}}";
                Log3 $name, 5, "$name: ReadAnswer got $ret";
                return $ret;
            }
            return;
        }
    } 
    # READOOP exited because of error / timeout
    $timeRest = $hash->{nextTimeout} - gettimeofday();          # timeout?
    if ($timeRest <= 0) {
        $msg .= ($msg ? ', ' : '') . 'Timeout in Readanswer';
        Statistics($hash, 'Timeouts');
        CountTimeouts ($hash);
    }

    LogFrame($hash, $msg, AttrVal($name, 'timeoutLogLevel', 3));
    $hash->{EXPECT} = 'idle';
    Profiler($hash, 'Idle');
    DropFrame($hash);                           # drop $hash->{FRAME} and the relevant part of $hash->{READ}{BUFFER}
    delete $hash->{nextTimeout};
    delete $hash->{REQUEST};
    StartQueueTimer($hash, \&Modbus::ProcessRequestQueue, {delay => 0});    # call processRequestQueue at next possibility if appropriate
    return $msg;
}


##########################################################################
# check if expected start byte comes later (ASCII or D for RTU)
# and skip garbage until this position
# startByte is always ':'' for ASCII or the Request Id for RTU Responses
# called from parseFrameStart
sub SkipGarbageCheck {
    my $hash      = shift;              # io device hash
    my $startByte = shift;              # optional byte to look for (: for Modbus ASCII, known ID for RTU)
    my $name      = $hash->{NAME};
    my $skipMode  = AttrVal ($name, 'skipGarbage', 0);
    my $start     = 0;

    if ($hash->{MODE} ne 'master' && $hash->{PROTOCOL} ne 'ASCII' && !$skipMode) {
        # always check for start byte when protocol is ASCII or mode is Master.
        # otherwise depend on the skipMode attribute
        return $hash->{READ}{BUFFER};
    }
    use bytes;

    if (!$startByte && $hash->{PROTOCOL} eq 'RTU') {
        # check for a possible ID of one of the logical devices
        Log3 $name, 5, "$name: SkipGarbageCheck special feature without given id";
        $start = length($hash->{READ}{BUFFER});         # default if no start found -> drop everything
        BUFLOOP:
        for my $pos (0..length($hash->{READ}{BUFFER})-1) {
            my $id = unpack('C', substr($hash->{READ}{BUFFER}, $pos, 1));
            DEVLOOP:
            for my $ld (keys %{$hash->{defptr}}) {      # for each registered logical device    
                if ($defs{$ld} && $defs{$ld}{MODBUSID} == $id) {
                    $start = $pos if ($pos < $start);
                    Log3 $name, 4, "$name: SkipGarbageCheck found potential id $id at pos $start";
                }
            }
            last BUFLOOP if ($start < length($hash->{READ}{BUFFER}));   # exit at first pos found
        }
    } elsif ($startByte) {
        #Log3 $name, 4, "$name: SkipGarbageCheck looking for start byte " . unpack ('H*', $startByte). 
        #    " protocol is $hash->{PROTOCOL}, mode is $hash->{MODE}";
        $start = index($hash->{READ}{BUFFER}, $startByte);
    }
    
    if ($start > 0) {
        my $skip = substr($hash->{READ}{BUFFER}, 0, $start);
        $hash->{READ}{BUFFER} = substr($hash->{READ}{BUFFER}, $start);
        Log3 $name, 4, "$name: SkipGarbageCheck skipped $start bytes (" . 
                ShowBuffer($hash, $skip) . ' rest ' .  ShowBuffer($hash) . ')';
    }
    return $hash->{READ}{BUFFER};
}


#####################################################
# parse the beginning of a request or response frame
# called from ReadFn and ReadAnswer with physical hash
sub ParseFrameStart {
    my $hash        = shift;                    # the device hash of the io device
    my $name        = $hash->{NAME};
    my $proto       = $hash->{PROTOCOL};
    my $frameString = $hash->{READ}{BUFFER};
    my ($id, $fCode, $data, $tid, $dlen, $pdu, $null);
    my $expectId;
    $expectId = $hash->{REQUEST}{MODBUSID} if ($hash->{REQUEST} && $hash->{REQUEST}{MODBUSID}); 
    # todo: should be removed in passive mode when the last request was not valid
    
    Log3 $name, 5, "$name: ParseFrameStart called from " . FhemCaller() .
        ($expectId ? " protocol $proto expecting id $expectId" : '');
    use bytes;
    if ($proto eq 'RTU') {
        # Skip for RTU only works when expectId is passed (parsing Modbus responses from a known Id)
        # todo: expectId could be a list of all ids of logical devices defined for this io dev
        $frameString = SkipGarbageCheck($hash, ($expectId ? pack('C', $expectId) : undef));     # pass undef if no $expectId
        return if ($frameString !~ /(..)(.*)(..)/s);            # (id fCode) (data) (crc), return if incomplete. fc17 has no data ...
        ($id, $fCode) = unpack ('CC', $1);
        $data = $2;
    } 
    elsif ($proto eq 'ASCII') {
        $frameString = SkipGarbageCheck($hash, ':');            # always do this for ASCII
        return if ($frameString !~ /:(..)(..)(.+)(..)\r\n/);    # : (id) (fCode) (data) (lrc) \r\n, return if incomplete    
        local $SIG{__WARN__} = sub { Log3 $name, 3, "$name: reading hex data from ASCII in ParseFrameStart created warning: @_"; };
        $id    = hex($1);
        $fCode = hex($2);
        $data  = pack('H*', $3);
    } 
    elsif ($proto eq 'TCP') {
        return if (length($frameString) < 8);                   # return if incomplete
        ($tid, $null, $dlen, $id, $pdu) = unpack ('nnnCa*', $frameString);
        ($fCode, $data) = unpack ('Ca*', $pdu);
        $hash->{FRAME}{TID} = $tid;
        $hash->{FRAME}{PDULEXP} = $dlen-1;                      # data length without id
        #Log3 $name, 5, "$name: ParseFrameStart for TCP extracted tid $tid, null, dlen $dlen, id $id and pdu " . unpack ('H*', $pdu);
    }
    $hash->{FRAME}{MODBUSID} = $id;
    $hash->{FRAME}{FCODE} = $fCode;
    $hash->{FRAME}{DATA} = $data;
    Log3 $name, 4, "$name: ParseFrameStart ($proto, $hash->{MODE}) extracted id $id, fCode $fCode" .
            ($hash->{FRAME}{TID} ? ', tid ' . $hash->{FRAME}{TID} : '') .
            ($dlen ? ', dlen ' . $dlen : '') .
            ' and potential data ' . unpack ('H*', $data);
    return 1;
}


#############################################################################
# called after ParseFrameStart by read / readAnswer if we are master
# check that response fits our request_method, call parseResponse
# validate checksums, call ParseDataString to set readings
# return undef if need more data or 1 if final success or error.
# cleans up at the end.
#
# note that we could be the master part of a relay and the request 
# might have come in through a TCP slave part of the relay
# so data in the response might need to be interpreted in the context
# of a TCP slave parent device ...
#############################################################################
sub HandleResponse {
    my $hash      = shift;                              # the physical io device hash
    my $name      = $hash->{NAME};
    my $frame     = $hash->{FRAME};
    my $request   = $hash->{REQUEST};                   # the request for this response
    my $masterHash;                                     # the logical (master) device - for timing    
    my $relayHash;
    
    Log3 $name, 5, "$name: HandleResponse called from " . FhemCaller();
    
    # idea: how to cancel a request but still remember that is was canceled when we send a new one?
    # do we need a list of sent requests at io dev?
    
    if ($request) {
        $masterHash = $request->{MASTERHASH};
        $masterHash = GetLogHash($hash, $frame->{MODBUSID}) if (!$masterHash);  # e.g. for passive mode
        $relayHash  = ($request->{RELAYHASH}{CHILDOF} ? $request->{RELAYHASH}{CHILDOF} : $request->{RELAYHASH}) if ($request->{RELAYHASH});
        if ($request->{FRAME} && $hash->{READ}{BUFFER} eq $request->{FRAME} && $frame->{FCODE} < 5) {   # might be ok.
            Log3 $name, 3, "$name: HandleResponse read the same data sent before - looks like an echo!";    
        }
        if ($frame->{MODBUSID} != $request->{MODBUSID} && $request->{MODBUSID} != 0) {  # definitely wrong.
            AddFrameError($frame, "Modbus ID $frame->{MODBUSID} of response does not match request ID $request->{MODBUSID}");
        }
        if ($hash->{PROTOCOL} eq 'TCP' && $request->{TID} != $frame->{TID}) {   # wrong. dont need to wait for another answer...
            AddFrameError($frame, "TID $frame->{TID} in Modbus TCP response does not match request TID $request->{TID}");
        }   
        if ($request->{FCODE} != $frame->{FCODE} && $frame->{FCODE} < 128) {
            AddFrameError($frame, "Function code $frame->{FCODE} in Modbus response does not match request function code $request->{FCODE}");
        }
    } 
    else {
        Log3 $name, 4, "$name: HandleResponse got data but we don't have a request";
        $masterHash = GetLogHash($hash, $frame->{MODBUSID});
    }
    
    $hash->{REMEMBER}{lid} = $frame->{MODBUSID};            # device id we last heard from 
    if ($masterHash) {
        $masterHash->{REMEMBER}{lrecv} = gettimeofday();
        $hash->{REMEMBER}{lname}  = $masterHash->{NAME};    # logical device name
    }
    
    my %responseData;                                       # create new response structure
    my $response = \%responseData;
    if ($request) {
        #Log3 $name, 5, "$name: prefill reponse hash with request " . RequestText($request);
        $response->{ADR}        = $request->{ADR};          # prefill so we don't need $request in ParseResponse and it gets shorter
        $response->{LEN}        = $request->{LEN};
        $response->{OPERATION}  = $request->{OPERATION};    # for later call to ParseDataString
        $response->{MASTERHASH} = $masterHash if ($masterHash);    
        $response->{RELAYHASH}  = $request->{RELAYHASH} if ($request->{RELAYHASH});    # not $relayHash!
    }   # if no request known, we will skip most of the part below
    
    # parse response and fill response hash
    # also $frame->{PDULEXP} will be set now if not already earlier.    
    return if (!ParseResponse($hash, $response, $masterHash));  # frame not complete - continue reading
    $hash->{RESPONSE} = $response;                              # save in receiving io hash for later parsing of response??
    
    if ($request && !$frame->{ERROR}) {     # only proceed if we know the request - otherwise fall through and finish parsing
        Profiler($hash, 'Fhem');   
        if ($response->{ERRCODE}) {         # valid error message response
            my $errCode  = $errCodes{$response->{ERRCODE}};
            if ($masterHash) {              # be quiet if no logical device hash (not our responsibility)
                Log3 $name, 4, "$name: HandleResponse got response with error code " . unpack ('H*', pack('C', $response->{FCODE})) 
                        . " / $response->{ERRCODE}" . ($errCode ? ", $errCode" : '');
            }
        } 
        else {                              # no error response, now check if we can parse data
            if ($frame->{FCODE} < 15) {     # is there data to parse? (nothing to parse after response to 15 / 16)
                Log3 $name, 5, "$name: now parsing response data objects, master is " . 
                    ($masterHash ? $masterHash->{NAME} : 'undefined') . " relay is " .
                    ($relayHash ? $relayHash->{NAME} : 'undefined');
                ParseDataString($masterHash, $response) if ($masterHash);
                ParseDataString($relayHash, $response) if ($relayHash);
            }
        }
        RelayResponse($hash, $request, $response) if ($relayHash && $request);       # add to {ERROR} if relay device is unavailable
    }
    
    if ($hash->{MODE} eq 'master' && AttrVal($name, 'closeAfterResponse', 0) && ($hash->{QUEUE} ? scalar(@{$hash->{QUEUE}}) : 0) == 0) {
        Log3 $name, 4, "$name: HandleResponse will close because closeAfterResponse is set and queue is empty";
        DoClose($hash) 
    }
    LogFrame($hash, ($hash->{FRAME}{ERROR} ? "HandleResponse error" : 'HandleResponse done'), 4);
    Statistics($hash, 'Timeouts', 0);       # damit bei Bedarf das Reading gesetzt wird
    ResetExpect($hash);                     # for master back to 'idle', otherwise back to 'request'
    Profiler($hash, 'Idle');
    delete $hash->{nextTimeout};
    delete $hash->{TIMEOUTS};
    delete $hash->{RETRY};
    delete $hash->{REQUEST};                    
    delete $hash->{RESPONSE};
    RemoveInternalTimer ("timeout:$name");
    StartQueueTimer($hash, \&Modbus::ProcessRequestQueue, {delay => 0});    # set  timer to call processRequestQueue asap
    return 1;                               # error or not, parsing is done.
}


#######################################################################
# Parse Response, called from handleResponse 
# require {FRAME} to be filled before by HandleFrameStart
# fill {RESPONSE} and some more fields of {FRAME}
# $frame->{PDULEXP} is set so the following functions can see if they still need to wait for more data
sub ParseResponse {
    my $hash       = shift;
    my $response   = shift;
    my $masterHash = shift;                                 # to be able to check for brokenFCX or allowShortResponses
    my $name       = $hash->{NAME};
    my $frame      = $hash->{FRAME} // {};
    my $fCode      = $frame->{FCODE};                       # filled in handleFrameStart
    my $data       = $frame->{DATA};

    Log3 $name, 5, "$name: ParseResponse called from " . FhemCaller();
    
    use bytes;
    $response->{FCODE}    = $fCode;
    $response->{MODBUSID} = $frame->{MODBUSID};
    +
    # if we don't have enough data then checksum check will fail later which is fine.
    # however unpack might produce undefined results if there is not enough data so return early.
    my $dataLength = length($data);
    if ($fCode == 1 || $fCode == 2) {                       
        # read coils / discrete inputs,                     pdu: fCode, num of bytes, coils
        # adr and len are copied from request
        return if ($dataLength) < 1;
        my ($len, $values) = unpack ('Ca*', $data);         # length of values data and values from frame
        $values = substr($values, 0, $len) if (length($values) > $len);
        $response->{VALUES}   = $values;
        $response->{TYPE}     = ($fCode == 1 ? 'c' : 'd');  # coils or discrete inputs
        $frame->{PDULEXP}     = $len + 2;                   # 1 Byte fCode + 1 Byte len + len of expected values  
    } 
    elsif ($fCode == 3 || $fCode == 4) {                  
        # read holding/input registers,                     pdu: fCode, num of bytes, registers
        return if ($dataLength) < 1;
        my ($len, $values) = unpack ('Ca*', $data);
        $response->{TYPE}  = ($fCode == 3 ? 'h' : 'i');     # holding registers / input registers
        if ($fCode == 3 && $masterHash && DevInfo($masterHash, 'h', 'brokenFC3', 0)) {
            # devices that respond with wrong pdu           pdu: fCode, adr, registers
            $len = $response->{LEN} * 2;
            Log3 $name, 5, "$name: ParseResponse uses fix for broken fcode 3, use len $len from request";
            my $adr;
            ($adr, $values)   = unpack ('na*', $data);
            $response->{ADR}  = $adr;                       # adr of registers
            $frame->{PDULEXP} = $response->{LEN} * 2 + 3;   # 1 Byte fCode + 2 Byte adr + 2 bytes per register
        } else {
            $frame->{PDULEXP}  = $len + 2;                  # 1 Byte fCode + 1 Byte len + len of expected values
        }
        $values = substr($values, 0, $len) if (length($values) > $len);
        $response->{VALUES} = $values;    
    } 
    elsif ($fCode == 5) {                                 
        # write single coil,                                pdu: fCode, adr, coil (FF00)
        return if ($dataLength) < 3;
        my ($adr, $values) = unpack ('nH4', $data);         # 2 bytes adr, 2 bytes values
        if ($fCode == 5 && $masterHash && DevInfo($masterHash, 'c', 'brokenFC5', 0)) {
            Log3 $name, 5, "$name: ParseResponse uses fix for broken fcode 5";
            $values = ($values eq '0000' ? 0 : 1);
        } else {
            $values = ($values eq 'ff00' ? 1 : 0);
        }
        $response->{ADR}    = $adr;                         # adr of coil
        $response->{LEN}    = 1;                            # always one coil
        $response->{VALUES} = pack ('c', $values);          # bit as binary string
        $response->{TYPE}   = 'c';                          # coils
        $frame->{PDULEXP}   = 5;                            # 1 Byte fCode + 2 Bytes adr + 2 Bytes coil
    } 
    elsif ($fCode == 6) {        
        # write single (holding) register,                  pdu: fCode, adr, register
        return if ($dataLength) < 2;
        my ($adr, $values)  = unpack ('na*', $data);  
        $response->{ADR}    = $adr;                         # adr of register
        $response->{VALUES} = $values;
        $response->{TYPE}   = 'h';                          # holding registers
        $frame->{PDULEXP}   = 5;                            # 1 Byte fCode + 2 Bytes adr + 2 Bytes register  
    } 
    elsif ($fCode == 15 || $fCode == 16) {                
        # write mult coils/holding registers,               pdu: fCode, adr, len    
        return if ($dataLength) < 2;
        $response->{TYPE} = ($fCode == 15 ? 'c' : 'c');     # coils / holding registers
        $frame->{PDULEXP} = 5;                              # 1 byte fCode + 2 byte adr + 2 bytes len   
        # response to fc 15 / 16 does not contain data -> nothing to be done, ParseDataString will not be called    
    } 
    elsif ($fCode >= 128) {
        # error fCode                                       pdu: fCode, data
        return if ($dataLength) < 1;
        $response->{ERRCODE} = unpack ('H2', $data);
        $frame->{PDULEXP}    = 2;                           # 1 byte error fCode + 1 code   
    } 
    else {
        # other function code
        AddFrameError($frame, "Function code $fCode not implemented");
        $frame->{PDULEXP} = 2;                              # minimum to expect (fCode + 1 more)
        # todo: now we don't know the real length! maybe better drop everything we have ...
        # todo: set another flag so we know this later!
    }
    $response->{PDU} = pack ('C', $fCode) . substr($data, 0, $frame->{PDULEXP});

    CheckChecksum($hash);                                   # calls AddFrameError if needed so $frame->{ERROR} might be set afterwards if checksum wrong

    my $frameLen = $frame->{PDULEXP} + $PDUOverhead{$hash->{PROTOCOL}};
    my $readLen  = length($hash->{READ}{BUFFER});
    if ($readLen < $frameLen ) {
        Log3 $name, 5, "$name: ParseResponse got incomplete frame. Got $readLen but expecting $frameLen bytes";
        return if ($frame->{ERROR});
        # frame is too small but no error - even checksum is fine!
        if (!$masterHash || !DevInfo($masterHash, $response->{TYPE}, 'allowShortResponses', 0)) {
            Log3 $name, 4, "$name: ParseResponse got frame that looks valid but is too short. set allowShortResponses to allow such frames";
            return;                                         # short frames are not allowed -> continue reading
        }
    }
    return 1;                                               # frame complete, go on with other checks / handling / dropping
}


#####################################################
# create a reading name for objects while scanning
sub ScanReadingName {
    my $logHash  = shift;
    my $reading  = shift;
    my $type     = shift;
    my $startAdr = shift;
    my $op       = shift;
    my $name     = $logHash->{NAME};
    my $key      = $type . $startAdr;

    if ($op =~ /scanid([0-9]+)/) {          # scanning for Modbus ID
        $reading = 'scanId-' . $1 . "-Response-$key";
        $logHash->{MODBUSID} = $1;
        Log3 $name, 3, "$name: ScanReadingName scanIds got response from Id $1 - set internal MODBUSID to $1";
        return $reading;
    } 
    # scan Modbus objects
    Log3 $name, 5, "$name: ScanReadingName scanobj reading=$reading";
    if (!$reading) {
        my $fKey = $type . sprintf ('%05d', $startAdr);     # objcombi with leading zeros
        $reading = "scan-$fKey";
        Log3 $name, 5, "$name: ScanReadingName scanobj sets reading=$reading";
        CommandAttr(undef, "$name obj-${fKey}-reading $reading");
    }
    return $reading;
}


#################################################
# called from CreateDataObjects to format 
# responses with different types while scanning
sub ScanFormat {
    my $hash = shift;
    my $val  = shift;
    my $name = $hash->{NAME};
    use bytes;
    my $len = length($val);
    my $i   = unpack('s', $val);
    my $n   = unpack('S', $val);
    my $h   = unpack('H*', $val);
    Log3 $name, 5, "$name: ScanFormat hex=$h, bytes=$len";
    
    my $ret = "hex=$h, string=";
        for my $c (split //, $val) {
            $ret .= $c =~ /[[:graph:]]/ ? $c : '.';
        }
                
        $ret .= ', s=' . unpack('s', $val) .
        ', s>=' . unpack('s>', $val) .
        ', S=' . unpack('S', $val) .
        ', S>=' . unpack('S>', $val);
    if ($len > 2) {         
        $ret .= ', i=' . unpack('s', $val) .
        ', i>=' . unpack('s>', $val) .
        ', I=' . unpack('S', $val) .
        ', I>=' . unpack('S>', $val);

        $ret .= ', f=' . unpack('f', $val) .
        ', f>=' . unpack('f>', $val);

        #my $r1 = substr($h, 0, 4);
        #my $r2 = substr($h, 4, 4);
        #my $rev = pack ('H*', $r2 . $r1);
        #$ret .= ', revf=' . unpack('f', $rev) .
        #', revf>=' . unpack('f>', $rev);
    }
    return $ret;
}


#####################################################################
# decode and then encode all array elements
# called from CreateDataObjects
sub arrayEncoding {
    my $hash   = shift;
    my $aRef   = shift;
    my $decode = shift;
    my $encode = shift;
    my $name   = $hash->{NAME};
    return if (!$decode && !$encode);

    for (my $i=0; $i < @{$aRef}; $i++) {
        $aRef->[$i] = decode($decode, $aRef->[$i]) if ($decode);
        $aRef->[$i] = encode($encode, $aRef->[$i]) if ($encode);
    }
    Log3 $name, 5, "$name: arrayEncoding for " . FhemCaller() . " modified charset of $aRef to: " . ReadableArray($aRef);
    return;
}


##################################################
# slave got data to write from its master
sub WriteObject {
    my $hash     = shift;
    my $transPtr = shift;
    my $type     = shift;
    my $adr      = shift;
    my $val      = shift;
    my $name     = $hash->{NAME};
    my $objCombi = $type . $adr;   
    my $reading  = ObjInfo($hash, $objCombi, 'reading');     # '' if nothing specified
    if (!$reading) {                        # no parse information -> skip to next object
        Log3 $name, 5, "$name: WriteObject has no information about handling $objCombi";
        $transPtr->{ERRCODE} = DevInfo($hash, $type, 'addressErrCode', 2);
        return;
    }
    if (!ObjInfo($hash, $objCombi, 'allowWrite', 'defAllowWrite', 0)) { # write allowed. 
        Log3 $name, 4, "$name: WriteObject refuses to set reading $reading (allowWrite not set)";
        $transPtr->{ERRCODE} = DevInfo($hash, $type, 'notAllowedErrCode', 1);
        return;
    }
    
    my $device = $name;                                 # default device is myself
    my $rname  = $reading;                              # given name as reading name
    my $dev    = $hash;
    if ($rname =~ /^([^\:]+):(.+)$/) {                  # can we split given name to device:reading?
        $device = $1;
        $rname  = $2;
        $dev    = $defs{$device};
    }
            
    if (!CheckRange($hash, {val => $val, min => ObjInfo($hash, $objCombi, 'min'), max => ObjInfo($hash, $objCombi, 'max')} ) ) {
        Log3 $name, 4, "$name: WriteObject ignores value $val because it is out of bounds for reading $rname of device $device";
        $transPtr->{ERRCODE} = DevInfo($hash, $type, 'valueErrCode', 1);    # for slave write processing
        next OBJLOOP;
    }
    if (!TryCall($hash, 'ModbusReadingsFn', $reading, $val)) {    
        Log3 $name, 4, "$name: ParseDataString assigns value $val to reading $rname of device $device";
        if ($dev eq $hash) {
            readingsBulkUpdate($dev, $rname, $val);         # assign value to one of this devices readings 
        } else {
            readingsSingleUpdate($dev, $rname, $val, 1);    # assign value to reading - another Fhem device
        }
    }
    $hash->{gotReadings}{$reading} = $val;
    return;
}


#####################################################
# split data part in a response or write request 
# into objects that later can be assigned to readings
sub SplitDataString {
    my $hash      = shift;
    my $transPtr  = shift;                      # $transPtr can be response (mode master) or request (mode slave and write request)
    my $name      = $hash->{NAME};
    my $type      = $transPtr->{TYPE};
    my $startAdr  = $transPtr->{ADR};
    my $valuesLen = $transPtr->{LEN};           # valuesLen is only used for coils / discrete inputs
    my $op        = $transPtr->{OPERATION} // '';
    my $dataStr   = $transPtr->{VALUES};
    my $lastAdr   = ($valuesLen ? $startAdr + $valuesLen -1 : 0);
    my @objList;                                # result array of object hashes

    Log3 $name, 5, "$name: SplitDataString called from " . FhemCaller() . " with data hex " . unpack ('H*', $transPtr->{VALUES}) . 
                ", type $type, adr $startAdr" .  ($valuesLen ? ", valuesLen $valuesLen" : '') .  ($op ? ", op $op" : '');

    if ($type =~ '[cd]') {
        $valuesLen = 1 if (!$valuesLen);
        $dataStr   = unpack ("b$valuesLen", $transPtr->{VALUES});   # convert binary data to bit string
        # for fc5 responses paresResponse already converts ff00 to 1. For requests the above unpack will also work for 0000 / ff00
        Log3 $name, 5, "$name: SplitDataString shortened coil / input bit string to " . $dataStr . ", start adr $startAdr, valuesLen $valuesLen";
    }

    use bytes;
    my ($reading, $unpack, $objLen, $expr);
    OBJLOOP:
    while (length($dataStr) > 0) {              # parse every field / object passed in $transPtr structure
        my $objCombi  = $type . $startAdr;
        $reading = ObjInfo($hash, $objCombi, 'reading');     # '' if nothing specified
        if ($type =~ '[cd]') {                  # coils or digital inputs
            $unpack = 'a';                      # for coils just take the next byte with 0/1 from the string. 
            $objLen = 1;                        # to be used in continue block (go to next coil/input in unpacked bit string)
        } 
        else {                                  # holding / input register
            if ($op =~ /^scan/) {               # special handling / presentation if scanning
                $objLen  = length($dataStr) / 2;   # length of rest as number of registers when scanning
                $objLen  = 1 if ($objLen < 1);  # just to be sure
                $unpack  = 'a' . $objLen*2;     # for Modbus::ScanFormat
                $reading = ScanReadingName ($hash, $reading, $type, $startAdr, $op);
            }
            else {                              # not scanning - use unpack, len and expr from attributes
                $objLen  = ObjInfo($hash, $objCombi, 'len');             # default to 1 (1 Reg / 2 Bytes) with global attrDefaults
                $unpack  = ObjInfo($hash, $objCombi, 'unpack'); 
            }
        }
        if (!$reading) {                        # no parse information -> skip to next object
            Log3 $name, 5, "$name: SplitDataString has no information about handling $objCombi";
            $transPtr->{ERRCODE} = DevInfo($hash, $type, 'addressErrCode', 2) if ($hash->{MODE} eq 'slave');
            next OBJLOOP;
        }
        my %obj;
        $obj{objCombi}   = $objCombi;
        $obj{reading}    = $reading;
        $obj{unpack}     = $unpack;
        $obj{adr}        = $startAdr;
        $obj{len}        = $objLen;
        $obj{data}       = substr($dataStr, 0, $objLen * 2);
        $obj{group}      = ObjInfo($hash, $objCombi, 'group');
        push @objList, \%obj;
    }
    continue {                                                      # take next object in data string
        if ($type =~ '[cd]') {
            $startAdr++;
            $dataStr = (length($dataStr) > 1 ? substr($dataStr, 1) : '');
            last OBJLOOP if ($lastAdr && $startAdr > $lastAdr);     # only set for unpacked coil / input bit string
        } 
        else {
            $startAdr += $objLen;            
            $dataStr = (length($dataStr) > ($objLen*2) ? substr($dataStr, $objLen * 2) : '');
        }
        #Log3 $name, 5, "$name: SplitDataString moves to next object, skip $objLen to $type$startAdr" if ($dataStr);
    }
    return \@objList;
}


#######################################################
# create readings from a hash containing all data parts
# with unpack, map, format and so on
sub CreateDataObjects {
    my $hash     = shift;
    my $objList  = shift;
    my $transPtr = shift;                       # $transPtr can be response (mode master) or request (mode slave and write request)
    my $name     = $hash->{NAME};

    Log3 $name, 5, "$name: CreateDataObjects called from " . FhemCaller() . " with objList " 
        . join ',', map {$_->{objCombi}} @{$objList};
    my @sortedList = sort compObjGroups @{$objList};        # sorted by group and pos in group, then type / adr
    Log3 $name, 5, "$name: CreateDataObjects sortedList " 
        . join ',', map {$_->{objCombi}} @sortedList;

    readingsBeginUpdate($hash);
    OBJLOOP:
    foreach my $obj (@sortedList) {
        my $objCombi = $obj->{objCombi};
        my $objData  = $obj->{data};

        $objData = ReverseWordOrder($hash, $objData, $obj->{len}) if (ObjInfo($hash, $objCombi, 'revRegs'));
        $objData = SwapByteOrder   ($hash, $objData, $obj->{len}) if (ObjInfo($hash, $objCombi, 'bswapRegs'));

        my @val = unpack ($obj->{unpack}, $objData);      # fill @val array in case unpack contains codes for more fields, other elements can be used in expr later.
        if (!defined($val[0])) {                # undefined value as result of unpack -> skip to next object
            my $logLvl = AttrVal($name, 'timeoutLogLevel', 3);
            Log3 $name, $logLvl, "$name: CreateDataObjects unpack of " . unpack ('H*', $objData) . " with $obj->{unpack} for $obj->{reading} resulted in undefined value";
            next OBJLOOP;
        } 
        Log3 $name, 5, "$name: CreateDataObjects unpacked " . unpack ('H*', $objData) . " with $obj->{unpack} to " . ReadableArray(\@val);
        arrayEncoding($hash, \@val, ObjInfo($hash, $objCombi, 'decode'), ObjInfo($hash, $objCombi, 'encode'));
        my $val = $val[0];

        next OBJLOOP if (EvalExpr($hash,        # ignore exp results true -> skip to next object
            {expr => ObjInfo($hash, $objCombi, 'ignoreExpr'), val => $val,, '@val' => \@val, 
             nullIfNoExp => 1, action => "ignoreExpr for $obj->{reading}"}));

        if ($transPtr->{OPERATION} && $transPtr->{OPERATION} =~ /^scan/) {
            $val = ScanFormat($hash, $val);     # interpretations with diferent unpack codes
        } 
        else {
            $val = EvalExpr($hash,   {val => $val, expr => ObjInfo($hash, $objCombi, 'expr'), '%val' => \@val});   
            $val = MapConvert($hash, {val => $val, map => ObjInfo($hash, $objCombi, 'map'),  undefIfNoMatch => 0});
            $val = FormatVal($hash,  {val => $val, format => ObjInfo($hash, $objCombi, 'format')});
        }

        if ($hash->{MODE} eq 'slave') {
            WriteObject($hash, $transPtr, $transPtr->{TYPE}, $obj->{adr}, $val);     # do slave write
        }
        else {
            if (!TryCall($hash, 'ModbusReadingsFn', $obj->{reading}, $val)) {    
                Log3 $name, 4, "$name: CreateDataObjects assigns value $val to $obj->{reading}";
                readingsBulkUpdate($hash, $obj->{reading}, $val);
            }
            $hash->{gotReadings}{$obj->{reading}} = $val;
            $hash->{lastRead}{$objCombi} = gettimeofday();     # used for pollDelay checking by getUpdate (mode master)
        }
    }
    readingsEndUpdate($hash, 1);
    return;
}


#################################################
# Parse holding / input register / coil Data
# called from ParseResponse which is only called from HandleResponse
# or from HandleRequest (for write requests as slave)
# with logical device hash, data string and the object type/adr to start with
sub ParseDataString {
    my $hash     = shift;
    my $transPtr = shift;                       # $transPtr can be response (mode master) or request (mode slave and write request)
    my $name     = $hash->{NAME};

    Log3 $name, 5, "$name: ParseDataString called from " . FhemCaller() . " with data hex " . unpack ('H*', $transPtr->{VALUES}) . 
                ", type $transPtr->{TYPE}, adr $transPtr->{ADR}" . ($transPtr->{OPERATION} ? ", op $transPtr->{OPERATION}" : '');
    delete $hash->{gotReadings};                # will be filled later and queried by caller. Used for logging and return value in get-command

    my $obj = SplitDataString($hash, $transPtr);    # split value string into objects in a new hash with its parameters from attrs
    if ($transPtr->{ERRCODE}) {
        Log3 $name, 5, "$name: ParseDataString returns because ERRCODE was set while splitting objects";
        return;
    }

    CreateDataObjects($hash, $obj, $transPtr);

    Log3 $name, 5, "$name: ParseDataString created " . scalar keys (%{$hash->{gotReadings}}) . " readings";
    return;
}


###########################################################################################
# called from read when we are passive, a slave or relay (receiving part)
# and we are reading a new request
#
# call parse request, get logical device responsible and write / read data as requested
# call CreateResponse to create and send a response
#
# when called we have $hash->{FRAME}{MODBUSID}, $hash->{FRAME}{FCODE}, $hash->{FRAME}{DATA}
# and for TCP also $hash->{FRAME}{PDULEXP} and $hash->{FRAME}{TID}
#
# return undef if read should continue reading or 1 if we can react on data that was read
#
# for relay: when a new request comes in and another on is still not answered, 
#            the old one can not be canceled so we block any further requests from beeing accepted 
#            before the forwarding side runs into timeout or has answered.
#            RelayRequest takes care of this.
#
#
sub HandleRequest {
    my $hash  = shift;                              # physical or TCP connection device hash
    my $name  = $hash->{NAME};                      # name of physical serial device or the tcp connection device
    my $frame = $hash->{FRAME};
    my $id    = $frame->{MODBUSID};
    my $fCode = $frame->{FCODE};
    my $logHash;
    my $msg   = '';
	delete $hash->{REQUEST};						# any old request in io dev is outdated now
    
    Log3 $name, 5, "$name: HandleRequest called from " . FhemCaller();
    
    my %requestData;                                # create new request structure
    my $request = \%requestData;
    
    if (!ParseRequest($hash, $request)) {           # take frame hash and fill request hash
        Log3 $name, 5, "$name: HandleRequest could not parse request frame yet, wait for more data";
        return;                                     # continue reading
    }
    # for unknown fCode $request->{ERRCODE} as well as $frame->{ERROR} are set by ParseRequest, later CreateResponse copies ERRCODE from Request into Response
    # ParseRequest also calls CheckChecksum to set $hash->{FRAME}{CHECKSUMERROR} if necessary

    # got a valid frame - maybe we can't handle it (unsupported fCode -> ERRCODE, set by parseRequest)
    Profiler($hash, 'Fhem');   
                                                    
    $hash->{REQUEST} = $request;                    # stick request data to physical or tcp connection hash for parsing the response (e.g. passive), no effect on relays where relay device != master
    # needed for replying back as relay, keeping track in mode passive
    # for relays $hash is the relay slave side io device which receives a request 
    # this is forwarded via another io hash on the forwarding master side (not visible here)
    LogFrame($hash, 'HandleRequest', 4);

    if ($frame->{CHECKSUMERROR}) { 
        $hash->{EXPECT} = 'request';                # wait for another (hopefully valid) request (hash key should already be set to request - only for clarity)
        delete $hash->{REQUEST};                    # this one was invalid anyway
    } else {
        $logHash = GetLogHash($hash, $id);              # look for Modbus logical slave or relay device (right id)
        if ($logHash) {                                 # other errors might need to create a response answer back to the master
            # our id, no cheksum error, we are responsible, logHash is set properly                                          
            if ($hash->{MODE} eq 'slave') {
                if (!$request->{ERRCODE} && exists $fcMap{$fCode}{write}) {   # supported write fCode request contains data to be parsed and stored
                    my $pLogHash = ($logHash->{CHILDOF} ? $logHash->{CHILDOF} : $logHash);
                    Log3 $name, 5, "$name: passing value string of write request to ParseDataString to set readings";                  
                    ParseDataString($pLogHash, $request); # parse the request value, set reading with formatting etc. like for replies
                    # ParseDataString can also set ERRCODE (illegal address, value out of bounds) so CreateResponse/PackResponse will create an error message back to master
                }
                CreateResponse($hash, $logHash, $request);  # create and send response, data or unsupported fCode error if request->{ERRCODE} and {ERROR} were set during parse
                $hash->{EXPECT} = 'request';  
            }
            elsif ($hash->{MODE} eq 'relay') {        
                $request->{RELAYHASH} = $logHash;           # remember who to pass the response to 
                RelayRequest($hash, $request, $frame);      # even if unspported fCode ...
                $hash->{EXPECT} = 'request';                # just to be safe, should already be request
            }
            elsif ($hash->{MODE} eq 'passive') {   
                Log3 $name, 4, "$name: received valid request, now wait for the reponse.";
                $hash->{EXPECT} = 'response';               # nothing else to do if we are a passive listener 
            }
        } else {                                            # none of our ids
            $hash->{EXPECT} = 'response';                   # not our request, parse response that follows
            $msg .= ', frame is not for us';
        }
    }
    my $text = 'HandleRequest Done' . $msg . ($hash->{FRAME}{ERROR} ? ", error: $hash->{FRAME}{ERROR}" : '');
    LogFrame($hash, $text, 4);
    Profiler($hash, 'Idle');  
    delete $hash->{RESPONSE};                           # remove response structure from physical io hash
    return 1;                                           # error or not, parsing is done.
}

 
#######################################################################
# Parse Request, only called from handleRequest
# require $physHash->{FRAME} to be filled before by HandleFrameStart
# fills request hash, 
# returns undef if not enough data, 1 if success or error ($request->{ERRCODE} is set)
# fills {PDULEXP} so the following functions can see if they still need to wait for more data
sub ParseRequest {
    my $hash    = shift;
    my $request = shift;
    my $name    = $hash->{NAME};
    my $frame   = $hash->{FRAME} // {};
    my $fCode   = $frame->{FCODE};                      # filled in handleFrameStart
    my $data    = $frame->{DATA};
    
    Log3 $name, 5, "$name: ParseRequest called from " . FhemCaller();
    
    use bytes;
    my $dataLength       = length($data);
    $request->{FCODE}    = $frame->{FCODE};             
    $request->{MODBUSID} = $frame->{MODBUSID};
    $request->{TID}      = $frame->{TID} if ($frame->{TID});

    if ($fCode == 1 || $fCode == 2) {
        # read coils / discrete inputs,                 pdu: fCode, StartAdr, Len (=number of coils)
        return if ($dataLength) < 4;                    # minimum pdu length minus fcode
        my ($adr, $len) = unpack ('nn', $data);
        $request->{TYPE}  = ($fCode == 1 ? 'c' : 'd');  # coils or discrete inputs
        $request->{ADR}   = $adr;                       # 16 Bit Coil / Input adr
        $request->{LEN}   = $len;                       # 16 Bit number of Coils / Inputs
        $frame->{PDULEXP} = 5;                          # fCode + 2x16Bit  
    } 
    elsif ($fCode == 3 || $fCode == 4) {      
        # read holding/input registers,                 pdu: fCode, StartAdr, Len (=number of regs)
        return if ($dataLength) < 4;                    # minimum pdu length minus fcode
        my ($adr, $len) = unpack ('nn', $data);
        $request->{TYPE}  = ($fCode == 3 ? 'h' : 'i');  # holding registers / input registers
        $request->{ADR}   = $adr;                       # 16 Bit Coil / Input adr
        $request->{LEN}   = $len;                       # 16 Bit number of registers
        $frame->{PDULEXP} = 5;                          # fCode + 2x16Bit  
    } 
    elsif ($fCode == 5) {                     
        # write single coil,                            pdu: fCode, StartAdr, Value (1-bit as FF00)
        return if ($dataLength) < 4;                    # minimum pdu length minus fcode
        my ($adr, $value) = unpack ('na*', $data);
        $request->{TYPE}   = 'c';                       # coil
        $request->{ADR}    = $adr;                      # 16 Bit Coil adr
        $request->{LEN}    = 1;
        $request->{VALUES} = $value;
        $frame->{PDULEXP} = 5;                          # fCode + 2 16Bit Values  
    } 
    elsif ($fCode == 6) {                     
        # write single holding register,                pdu: fCode, StartAdr, Value
        return if ($dataLength) < 4;                    # minimum pdu length minus fcode
        my ($adr, $value) = unpack ('na*', $data);
        $request->{TYPE}  = 'h';                        # holding register
        $request->{ADR}   = $adr;                       # 16 Bit holding register adr
        $request->{LEN}   = 1;
        $request->{VALUES} = $value;
        $frame->{PDULEXP} = 5;                          # fCode + 2x16Bit 
    }
    elsif ($fCode == 15) {                    
        # write multiple coils,                         pdu: fCode, StartAdr, NumOfCoils, ByteCount, Values as bits
        return if ($dataLength) < 6;                    # minimum pdu length minus fcode
        my ($adr, $len, $bytes, $values) = unpack ('nnCa*', $data);
        $request->{TYPE}  = 'c';                        # coils
        $request->{ADR}   = $adr;                       # 16 Bit Coil adr
        $request->{LEN}   = $len;
        $request->{VALUES} = $values;
        $frame->{PDULEXP} = 6 + $bytes;                 # fCode + 2x16Bit + bytecount + values
    }
    elsif ($fCode == 16) {                    
        # write multiple regs,                          pdu: fCode, StartAdr, NumOfRegs, ByteCount, Values
        my ($adr, $len, $bytes, $values) = unpack ('nnCa*', $data);
        return if ($dataLength) < 6;                    # minimum pdu length minus fcode
        $request->{TYPE}  = 'h';                        # coils
        $request->{ADR}   = $adr;                       # 16 Bit Coil adr
        $request->{LEN}   = $len;
        $request->{VALUES} = $values;
        $frame->{PDULEXP} = 6 + $bytes;                 # fCode + 2x16Bit + bytecount + values
    }
    elsif ($fCode == 17) {
        # report server id (serial only)                pdu: only fCode
        $request->{ADR}   = 0;                          # special request, no normal objects requested 
        $request->{LEN}   = 0;
        $frame->{PDULEXP} = 1;                          # nothing after fCode
    } 
    else {                                              # function code not implemented yet
        $request->{ERRCODE} = 1;                        # error code 1 in Modbus response = illegal function
        AddFrameError($frame, "Function code $fCode not implemented");
        $frame->{PDULEXP} = 2;
    }
    $request->{PDU} = pack ('C', $fCode) . substr($data, 0, $frame->{PDULEXP});
    CheckChecksum($hash);                               # set $hash->{FRAME}{CHECKSUMERROR} if wrong

    my $frameLen = $frame->{PDULEXP} + $PDUOverhead{$hash->{PROTOCOL}};
    my $readLen  = length($hash->{READ}{BUFFER});
    return if ($readLen < $frameLen );                  # continue reading
    return 1;                                           # reading done, continue handling / dropping this frame
}



#######################################################
# get the valid io device for the relay forward device
# called with the logical device hash of a relay
# this relay device hash has hash->{RELAY} set to the name of the forward device
# also sets $hash->{RELID} (in the logical relay device) 
# to the Modbus id of the relay forward device 
sub GetRelayIO {
    my $relayHash = shift;    
    $relayHash    = $relayHash->{CHILDOF} if ($relayHash->{CHILDOF});  # switch to parent context if available
    my $name      = $relayHash->{NAME};
    my $masterName;
    my $masterHash;
    my $masterIOHash;
    my $msg;
    
    if (!$relayHash->{RELAY}) {
        $msg = 'GetRelay does not have a relay forward device';
    } 
    else {
        $masterName = $relayHash->{RELAY};                      # name of the relay forward device as defined
        $masterHash = $defs{$masterName};
        #Log3 $name, 5, "$name: GetRelayIO for relay forward device $masterHash->{NAME}";
        if (!$masterHash || !$masterHash->{MODULEVERSION} || 
                $masterHash->{MODULEVERSION} !~ /^Modbus / || $masterHash->{MODE} ne 'master'
                || $masterHash->{TYPE} eq 'Modbus') {
            $msg = "relay forward device $masterName is not a modbus master";
        } 
        else {
            # now we have a $masterHash for the logical relay forward device at least
            $masterIOHash = GetIOHash($masterHash);    # get io device hash of the relay forward device
            my $slIOHash = GetIOHash($relayHash);      # get io device hash of the relay slave part (has to be different). Check later if available
            if (!$masterIOHash) {
                $msg = 'no relay forward io device';
            } elsif ($masterIOHash eq $slIOHash) {
                $msg = 'relay forward io device must not must not be same as receiving device';
            } else {
                # now check for disabled devices
                $msg = CheckDisable($masterHash);      # is relay forward device or its io device disabled?
            }
        }
    }
    # don't check if relay io device is actually opened. This will be done when the queue is processed 
    if ($msg) {
        Log3 $name, 3, "$name: GetRelayIO: $msg";
        delete $relayHash->{RELID};
        return;
    }
    $relayHash->{MASTERHASH} = $masterHash;
    $relayHash->{RELID} = $masterHash->{MODBUSID};
    Log3 $name, 5, "$name: GetRelayIO found $masterIOHash->{NAME} as Modbus relay forward io device for $masterHash->{NAME} with id $masterHash->{MODBUSID}";
    #Log3 $name, 5, "$name: GetRelayIO set RELID of $relayHash to $relayHash->{RELID}";
    return $masterIOHash;
}


##################################################################################
# relay request to the specified relay device 
# called from HandleRequest with the physical device hash that received the request
# as io device for the relay device which is referenced as $request->{RELAYHASH} 
# (same for tcp connection but different if relay reads from serial)
sub RelayRequest {
    my $hash      = shift;
    my $request   = shift;
    my $frame     = shift;
    my $name      = $hash->{NAME};                      # the io device of the device defined with MODE relay (received the request)
    my $relayHash = $request->{RELAYHASH};              # the logical device with MODE relay (that handled the incoming request)
                                                        # for a relay from TCP to serial this is the connection device hash

    Log3 $name, 4, "$name: RelayRequest called from " . FhemCaller();
    
    my $reIOHash = GetRelayIO($relayHash);              # the io device of the relay forward device (relay to)
    my $relayParentHash = ($relayHash->{CHILDOF} ? $relayHash->{CHILDOF} : $relayHash); # switch to parent context if available
    my $id = $relayParentHash->{RELID};                 # Modbus ID of relay target - set by GetRelayIO
    my $masterHash = $relayParentHash->{MASTERHASH};    # Device hash of master used by relay - set by GetRelayIO
    #Log3 $name, 5, "$name: RelayRequest got RELID of $relayParentHash as $id";
	    
    if (!$reIOHash) {
        AddFrameError($frame, 'relay forward device unavailable');   # message in frame hash for logging
        $request->{ERRCODE} = 10;                       # gw path unavail; 11=gw target fail to resp.
        CreateResponse($hash, $relayHash, $request);    # create and send error response with request data and errcode 
        return;
    } 
    my $queue = $reIOHash->{QUEUE};                 # request queue on forwarding side
    my $topRequest = $queue->[0];
    if ($topRequest && $topRequest->{RELAYHASH} eq $relayHash) {   # if there is another request for this relay waiting
        shift(@{$queue});                           # remove first element in queue - its outdated now
    }
    
    if ($reIOHash->{EXPECT} eq 'response') {        # forward side is still busy waiting for another reply - refuse another request
        AddFrameError($frame, 'relay forward path busy');   # message in frame hash for log
        $request->{ERRCODE} = 6;            		        # slave busy
		CreateResponse($hash, $relayHash, $request);        # create and send an error response
		return;
    }
    
    my %fRequest = %{$request};                     # create a copy to modify and forward
    $fRequest{MASTERHASH} = $masterHash;
    LogFrame($hash, "RelayRequest via $reIOHash->{NAME}, Proto $reIOHash->{PROTOCOL} with id $id", 4);
    if ($reIOHash->{PROTOCOL} eq 'TCP') {           # forward as Modbus TCP?
        my $tid = int(rand(255));
        $fRequest{TID} = $tid;                      # new transaction id for Modbus TCP forwarding
    }
    $fRequest{MODBUSID} = $id;                      # Modified target ID for the request to forward
    $fRequest{DBGINFO}  = 'relayed';
    $fRequest{FORCE}    = 1;                        # force: put at pos 0 of queue
    QueueRequest($reIOHash, \%fRequest);  
    return;
}



######################################################################################
# relay response back to the device that sent the original request. 
# called from HandleResponse with the io hash of the device that received the response
# and the request that was modified and forwarded
# and the response received.

# zurücksenden muss bei tcp über den connection child hash gehen
# ebenso steht der original request im connection hash
# andererseits steht die aktuelle config im parent hash der connection...

# entscheidend ist {RELAYHASH}
# wird im request schon gesetzt und von dort in die Reponse übernommen

sub RelayResponse {
    my $hash     = shift;
    my $request  = shift;
    my $response = shift;                       # hash and name refer to the forward side
    my $name     = $hash->{NAME};               # physical device that received a response 
        
    my $relayHash = $response->{RELAYHASH};     # hash of logical relay device that got the first request
    my $ioHash = GetIOHash($relayHash);         # the ioHash that received the original request
    if (!$ioHash) {
        Log3 $name, 4, "$name: RelayResponse failed because slave (=server) side io device disappeared";
        return;
    }
    
	my $origRequest = $ioHash->{REQUEST};       # needed ($hash->{REQUEST} was modified / forwarded)
	
	if (!$origRequest->{MODBUSID}) {
		Log3 $name, 4, "$name: RelayResponse failed because original request is missing. " .
		    'relayHash name ' . $relayHash->{NAME} . ' relay io hash name ' . $ioHash->{NAME} .
		    ' ioHash request hash ' . $origRequest . ' type ' . ($origRequest->{TYPE} // 'undef') . ' adr ' . ($origRequest->{ADR} // 'undef');
		return;
	}
    # adjust Modbus ID for back communication
    $response->{MODBUSID} = $origRequest->{MODBUSID};
    $response->{TID}      = ($origRequest->{TID} ? $origRequest->{TID} : 0);
    
    LogFrame($hash, "RelayResponse via $relayHash->{NAME}, ioDev $relayHash->{IODev}{NAME}", 4, $request, $response);
    
    my $responseFrame = PackFrame($ioHash, $relayHash->{MODBUSID}, $response->{PDU}, $response->{TID}); 
    SendFrame($ioHash, $relayHash->{MODBUSID}, $responseFrame, $relayHash);
    Profiler($hash, 'Idle');   
    return;
}


#############################################################################################
# create and send a response
# called from HandleRequest, RelayRequest
# and responseTimeout (when a relay wants to inform its master about the downstream timeout)
#
# the start adr and length of the request is taken to assemble a response frame out of
# one or several objects
#
sub CreateResponse {
    my $hash    = shift;
    my $logHash = shift;
    my $request = shift;
    $logHash    = $logHash->{CHILDOF} if ($logHash->{CHILDOF});
    my $name    = $logHash->{NAME};                 # name of logical device    
    
    Log3 $name, 5, "$name: CreateResponse called from " . FhemCaller() . 
		($request->{ERRCODE} ? " ErrCode=$request->{ERRCODE}" : '');
    
    my %responseData;                               # create a new response structure
    my $response = \%responseData;
    $hash->{RESPONSE} = $response;
    
    $response->{ADR}      = $request->{ADR} // 0;   # get values for response from request
    $response->{LEN}      = $request->{LEN} // 0;
    $response->{TYPE}     = $request->{TYPE} // '';
    $response->{MODBUSID} = $request->{MODBUSID};
    $response->{FCODE}    = $request->{FCODE};
    $response->{TID}      = $request->{TID}     if ($request->{TID});
    $response->{ERRCODE}  = $request->{ERRCODE} if ($request->{ERRCODE});
    
    # pack one or more values into a values string
    if (exists $fcMap{$response->{FCODE}}{objReturn} && !$response->{ERRCODE}) {
        $response->{VALUES} = PackObj($logHash, $response) 
    } elsif ($response->{FCODE} == 17) {
        my $serverId = EvalExpr($logHash, {expr => AttrVal($name, 'serverIdExpr', 'fhem')});
        $response->{VALUES} = $serverId;
        Log3 $name, 3, "$name: server id requested, send $serverId";
    }
        
    Log3 $name, 5, "$name: CreateResponse calls PackFrame to prepare response pdu";

    $response->{FCODE} += 128 if ($response->{ERRCODE});
    my $responsePDU   = PackResponse($hash, $response);     # creates response or error PDU Data if {ERRCODE} is set
    my $responseFrame = PackFrame($hash, $response->{MODBUSID}, $responsePDU, $response->{TID});        
    Log3 $name, 4, "$name: CreateResponse sends " . ResponseText($response) .
                   ", device $name ($hash->{PROTOCOL}), pdu " . 
                    unpack ('H*', $responsePDU) . ", V $Module_Version";    
    SendFrame($hash, $response->{MODBUSID}, $responseFrame, $logHash);
    Profiler($hash, 'Idle');
    return;
}
        

##############################################################
# get the correct function code
# called from DoRequest
sub GetFC {
    my $hash    = shift;
    my $request = shift;
    my $type    = $request->{TYPE};
    my $len     = $request->{LEN};
    my $op      = $request->{OPERATION};
    my $name    = $hash->{NAME};                # name of logical device
    my $fcKey   = ($op =~ /^scan/ ? 'read' : $op);

    #my $defFC   = $defaultFCode{$type}{$fcKey};
    my $defFC   = 3;
    SEARCH:
    foreach my $fc (keys %fcMap) {
        if ($fcMap{$fc}{type} && $fcMap{$fc}{type} eq $type && exists $fcMap{$fc}{$op} && exists $fcMap{$fc}{default}) {
            $defFC = $fc;
            last SEARCH;
        }
    }
    $defFC    = 16 if ($defFC == 6 && $request->{LEN} > 1);
    my $fCode = DevInfo($hash, $type, $fcKey, $defFC); 
    if (!$fCode) {
        Log3 $name, 3, "$name: GetFC called from " . FhemCaller() . " did not find fCode for $fcKey type $type";
    } 
    elsif ($fCode == 6 && $request->{LEN} > 1) {
        Log3 $name, 3, "$name: GetFC called from " . FhemCaller() . ' tries to use function code 6 to write more than one register. This will not work!';
    }
    elsif ($fCode !~ /^[0-9]+$/) {
        Log3 $name, 3, "$name: GetFC called from " . FhemCaller() . ' get fCode $fCode which is not numeric. This will not work!';
    }
    return $fCode;
}


##############################################################
# called from logical device functions 
# get, set, scan etc. with logical device hash. 
# Create request and call QueueRequest
sub DoRequest {
    my $hash     = shift;
    my $request  = shift;
    my $name     = $hash->{NAME};           # name of logical device
    my $ioHash   = GetIOHash($hash);        # send queue is at physical hash
    my $qlen     = ($ioHash->{QUEUE} ? scalar(@{$ioHash->{QUEUE}}) : 0);
    my $objCombi = $request->{TYPE} . $request->{ADR};

    #Log3 $name, 4, "$name: DoRequest called from " . FhemCaller() . ' ' . RequestText($request);
    return if (CheckDisable($hash));        # returns if there is no io device
    
    $request->{MODBUSID}   = $request->{OPERATION} =~ /^scanid([0-9]+)/ ? $1 : $hash->{MODBUSID};
    $request->{READING}    = ObjInfo($hash, $objCombi, 'reading');
    $request->{LEN}        = ObjInfo($hash, $objCombi, 'len') if (not exists $request->{LEN});
    $request->{MASTERHASH} = $hash;                                             # logical device in charge
    $request->{TID}        = int(rand(255)) if ($hash->{PROTOCOL} eq 'TCP');    # transaction id for Modbus TCP
    $request->{FCODE}      = GetFC($hash, $request);
    return if (!$request->{FCODE});

    # check if defined unpack code matches a corresponding len and log warning if appropriate
    my $unpack = ObjInfo($hash, $objCombi, 'unpack'); 
    Log3 $name, 3, "$name: DoRequest with unpack $unpack but len < 2 - please set obj-${objCombi}-Len!" 
        if ($request->{LEN} < 2 && $unpack =~ /[lLIqQfFNVD]/);

    delete $ioHash->{RETRY};
    #$ioHash->{REQUEST} = $request;         # It might overwrite the one sent -> dont link here
    LogFrame($hash, 'DoRequest called from ' . FhemCaller() . ' created new request', 4, $request);
    QueueRequest($ioHash, $request);        # queue and process / set queue timer depending on force
    return;
}   



########################################################################
# called from DoRequest, RelayRequest and ResponseTimeout (for retrying)
# with physical device hash and request
sub QueueRequest {
    my $hash    = shift;                    # the physical device hash (io hash to send a request through)
    my $request = shift;
    my $force   = $request->{FORCE};
    my $front   = $request->{FRONT} || $request->{FORCE};
    my $name    = $hash->{NAME};            # name of physical device with the queue
    my $qlen    = ($hash->{QUEUE} ? scalar(@{$hash->{QUEUE}}) : 0);
    my $mName   = ($request->{MASTERHASH} ? $request->{MASTERHASH}{NAME} : 'unknown');
    my $lqMax   = AttrVal($mName, 'queueMax', 100);
    my $qMax    = AttrVal($name, 'queueMax', $lqMax);
    
    Log3 $name, 5, "$name: QueueRequest called from " . FhemCaller() . 
        " with $request->{TYPE}$request->{ADR}, qlen $qlen" .
        (defined ($request->{MASTERHASH}) && $request->{MASTERHASH}{NAME} ? " from master $request->{MASTERHASH}{NAME}" : '' ) .
        (defined ($request->{RELAYHASH})  && $request->{RELAYHASH}{NAME}  ? " for relay $request->{RELAYHASH}{NAME}" : '' ) .
        " through io device $hash->{NAME}";
    
    return if (CheckDisable($hash));       # also returns if there is no io device

    # check for queue doubles if not forcing
    my $checkDoubles = (AttrVal($name, 'dropQueueDoubles', 0) || $request->{RELAYHASH});
    if ($qlen && $checkDoubles && !$front) {
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
    $request->{QUEUED} = $now;
    if(!$qlen) {
        #Log3 $name, 5, "$name: QueueRequest is creating new queue";
        $hash->{QUEUE} = [ $request ];
    } 
    else {
        #Log3 $name, 5, "$name: QueueRequest initial queue length is $qlen";
        if ($qlen > $qMax) {
            Log3 $name, 3, "$name: QueueRequest queue too long ($qlen), dropping new request";
        } else {
            if ($front) {
                unshift (@{$hash->{QUEUE}}, $request);          # prepend at beginning
            } else {
                push(@{$hash->{QUEUE}}, $request);              # add to end of queue
            }
        }
    }   
    if ($force) {
        ProcessRequestQueue('direct:'.$name);                   # call directly - even wait if force is set
        return;
    }
    readingsSingleUpdate($hash, 'QueueLength', ($hash->{QUEUE} ? scalar(@{$hash->{QUEUE}}) : 0), 1) if (AttrVal($name, 'enableQueueLengthReading', 0));
    StartQueueTimer($hash, \&Modbus::ProcessRequestQueue, {delay => 0});  # process asap, after delays are over
    return;
}   


######################################################
# remove internal timer for next queue processing
sub NextRequestFromQueue {
    my $ioHash = shift;
    my $name   = $ioHash->{NAME};
    my $queue  = $ioHash->{QUEUE};
    my $qTo    = AttrVal($name, 'queueTimeout', 20);  
    my $now    = gettimeofday();
    my $QLR    = AttrVal($name, 'enableQueueLengthReading', 0);
    my $request;
    CLEANLOOP: 
    {                                           # get first usable entry or return if none
        if(!$queue || !scalar(@{$queue})) {     # nothing in queue -> return
            readingsSingleUpdate($ioHash, 'QueueLength', 0, 1) if ($QLR);
            return;
        }
        $request = $queue->[0];                                         # get top element from Queue
        next CLEANLOOP if (!$request || !$request->{FCODE});            # skip invalid entry (should not happen)
        $request->{QUEUED} = $now if (!$request->{QUEUED});
        last CLEANLOOP if ($now - $request->{QUEUED} <= $qTo);          # element is not outdated -> exit loop
    } continue {
        shift(@{$queue});                                               # remove first element and iterate
    }
    return $request
}


####################################################
# neue Funktion zum Prüfen der Delays vor dem Senden
sub CheckDelays {
    my $ioHash     = shift;
    my $masterHash = shift;
    my $request    = shift;
    my $force      = $request->{FORCE};
    my $min        = 0;
    my $name       = $ioHash->{NAME};
    my $masterName = $masterHash->{NAME};
    my $now        = gettimeofday();
    my $reqId      = $request->{MODBUSID};
    my ($maxRest, $maxRestKey);

	my $delays = {   
        busDelayRead => {   
            name  => 'last activity on bus',
            last  => $ioHash->{REMEMBER}{lrecv} // 0,
            last2 => $ioHash->{REMEMBER}{lsend} // 0,
            delay => AttrVal($name, 'busDelay', 0),
        },
        clientSwitchDelay => {  
            name  => 'last read with different id',
            if    => ($ioHash->{REMEMBER}{lid} && $reqId != $ioHash->{REMEMBER}{lid}),
            last  => $ioHash->{REMEMBER}{lrecv},
            delay => AttrVal($name, 'clientSwitchDelay', 0),
        },
        commDelay => {
            name  => 'last communication with same device',
            last  => $masterHash->{REMEMBER}{lrecv},
            delay => DevInfo($masterHash, 'timing', 'commDelay', 0.1),
        },
        sendDelay => {
            name  => 'last send to same device',
            last  => $masterHash->{REMEMBER}{lsend},
            delay => DevInfo($masterHash, 'timing', 'sendDelay', 0.1),
        },
    };

    DELAYLOOP:
    foreach my $dKey (keys %{$delays}) {
        if (exists $delays->{$dKey}{if} && ! $delays->{$dKey}{if}) {
            Log3 $name, 5, "$name: checkDelays $dKey is not relevant";
            next DELAYLOOP;
        }
        my $last = ($delays->{$dKey}{last1} && $delays->{$dKey}{last1} < $delays->{$dKey}{last}) ? 
                $delays->{$dKey}{last1} : ($delays->{$dKey}{last} // 0);
        my $tDiff    = $now - $last;
        my $tDiffStr = $last ? sprintf('%.3f', $tDiff) . ' secs ago' : 'never';
        my $require  = $delays->{$dKey}{delay};
        my $rest     = $require - $tDiff;
        $rest        = $require if ($rest > $require);      # just to be sure nothing went wrong
        Log3 $name, 5, "$name: checkDelays $dKey, $delays->{$dKey}{name} was $tDiffStr, required delay is $delays->{$dKey}{delay}";
        if ($rest > ($maxRest // 0)) {
            $maxRest    = $rest;
            $maxRestKey = $dKey;
        }
    }
    return if (!$maxRestKey);               # no remaining delay > 0 -> go on with sending
    $maxRest = sprintf('%.3f', $maxRest);
    Profiler($ioHash, 'Delay');  
    if ($force) {
        Log3 $name, 4, "$name: checkDelays found $maxRestKey not over, sleep for $maxRest forced";
        sleep $maxRest;
        Log3 $name, 4, "$name: checkDelays sleep done, go on with sending";
        return; # contine with sending, Profiler key will be set there
    } 
    Log3 $name, 4, "$name: checkDelays found $maxRestKey not over, set timer to try again in $maxRest";
    StartQueueTimer($ioHash, \&Modbus::ProcessRequestQueue, {delay => $maxRest, silent => 1});     # call processRequestQueue when remaining delay is over
    return 1;   # processRequestQueue will return and wait to be called again later, keep Profiler in 'Delay'
}


#######################################
# Aufruf aus InternalTimer mit "queue:$name" 
# oder direkt mit "direkt:$name, wobei name das physical device ist
# greift über den Request der Queue auf das logische Device zu
# um Timings und Zeitstempel zu verarbeiten
# setzt selbst wieder einen Timer nach qDelay (default 1 Sek)

# to be able to open tcp connections on demand and close them after communication
# ProcessRequestQueue should call open if necessary and then return / set timer with queueDelay
# to try again in x seconds.
# then the queue entries should have their own timeout so they can get removed e.g. after 10 seconds
# otherwise the queue will overflow sometimes.
# the age of entries is checked in NextRequestFromQueue and the entry removed if it is too old.
sub ProcessRequestQueue {
    my ($ckey,$name) = split(':', shift);
    my $ioHash  = $defs{$name};
    my $queue   = $ioHash->{QUEUE};
    my $now     = gettimeofday();
    my $qDelay  = AttrVal($name, 'queueDelay', 1);  
    my $request = NextRequestFromQueue($ioHash);
    my $force   = $request->{FORCE};
    my $reqId   = $request->{MODBUSID};
    my $maHash  = $request->{MASTERHASH};       # the logical device from which the request came (relay/master)         
    my $qlen    = scalar(@{$queue});

    StopQueueTimer($ioHash, {silent => 1});     # maybe we were called direct
    Log3 $name, 5, "$name: ProcessRequestQueue called from " . FhemCaller() . " as $ckey:$name, qlen $qlen" . ($force ? ", force" : '') .
        ($request ? ", request: " . RequestText($request) : ', no usable requests in queue');
    return if (!$request);                      # nothing to send
    
    my $msg = CheckDisable($maHash);
    if ($msg) {                                 # logical/physical device disabled, logged by CheckDisable
        $msg = 'dropping queue because logical or io device is unavailable or disabled';
        delete $ioHash->{QUEUE};                # drop whole queue
    } 
    elsif (!IsOpen($ioHash)) {
        $msg = 'device is disconnected';
        DoOpen($ioHash);                        # try to open asynchronously so we can proceed after qDelay
    } 
    elsif (!$init_done) {                       # fhem not initialized, wait with IO
        $msg = 'device is not available yet (init not done)';
    } 
    elsif ($ioHash->{MODE} && $ioHash->{MODE} ne 'master') {
        $msg = 'dropping queue because device is not in mode master';
        delete $ioHash->{QUEUE};                # drop whole queue
    } 
    elsif ($ioHash->{EXPECT} eq 'response') { # still busy waiting for response to last request
        $msg = 'Fhem is still waiting for response, ' . FrameText($ioHash);
    }
    readingsSingleUpdate($ioHash, 'QueueLength', ($queue ? scalar(@{$queue}) : 0), 1) if (AttrVal($name, 'enableQueueLengthReading', 0));
    if ($msg) {
        Profiler($ioHash, 'Idle') if ($ioHash->{EXPECT} ne 'response');
        #Log3 $name, 5, "$name: debug last open was " . sprintf('%3.3f', ($now - $ioHash->{LASTOPEN})) . ' secs ago at ' . FmtTimeMs($ioHash->{LASTOPEN});
        Log3 $name, 5, "$name: ProcessRequestQueue will return, $msg, " .
                "qlen $qlen, try again in $qDelay seconds";
        StartQueueTimer($ioHash, \&Modbus::ProcessRequestQueue, {silent => 0});    # try again after qDelay, no shorter waiting time obvious                
        return;
    }

    return if (CheckDelays($ioHash, $maHash, $request));    # might set Profiler to delay
                
    my $pdu   = PackRequest($ioHash, $request);
    my $frame = PackFrame($ioHash, $reqId, $pdu, $request->{TID});
    LogFrame ($ioHash, "ProcessRequestQueue (V$Module_Version) qlen $qlen, sending " 
        . ShowBuffer($ioHash, $frame) . " via $ioHash->{DeviceName}", 4, $request);

    $request->{SENT}   = $now;
    $request->{FRAME}  = $frame;            # frame as data string for echo detection
    $ioHash->{REQUEST} = $request;          # save for later handling incoming response
    $ioHash->{EXPECT}  = 'response';        # expect to read a response
    
    DropBuffer($ioHash);    
    Statistics($ioHash, 'Requests');
    SendFrame($ioHash, $reqId, $frame, $maHash);  # send the request, set Profiler key to 'Send'
    Profiler($ioHash, 'Wait');              # wait for response to our request

    my $timeout = DevInfo($maHash, 'timing', 'timeout', ($request->{RELAYHASH} ? 1.5 : 2));
    my $toTime  = $now+$timeout;
    RemoveInternalTimer ("timeout:$name");
    InternalTimer($toTime, \&Modbus::ResponseTimeout, "timeout:$name", 0);
    $ioHash->{nextTimeout} = $toTime;       # to be able to calculate remaining timeout time in ReadAnswer
        
    shift(@{$queue});                       # remove first element from queue
    readingsSingleUpdate($ioHash, 'QueueLength', ($queue ? scalar(@{$queue}) : 0), 1) if (AttrVal($name, 'enableQueueLengthReading', 0));
    StartQueueTimer($ioHash, \&Modbus::ProcessRequestQueue);    # schedule next call if there are more items in the queue
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
sub PackObj {
    my $logHash   = shift;
    my $response  = shift;
    my $name      = $logHash->{NAME};
    my $valuesLen = $response->{LEN};           # length of the values string requested (registers / bits)
    my $type      = $response->{TYPE};          # object to start with
    my $startAdr  = $response->{ADR};
    my $lastAdr   = ($valuesLen ? $startAdr + $valuesLen -1 : 0);
    my $data      = '';
    my $counter   = 0;
    
    #Log3 $name, 5, "$name: PackObj called from " . FhemCaller();
    Log3 $name, 5, "$name: PackObj called from " . FhemCaller() . " with $type $startAdr" .  
                    ($valuesLen ? " and valuesLen $valuesLen" : '');
    $valuesLen = 1 if (!$valuesLen);
    use bytes;
    
    while ($counter < $valuesLen) {
        # einzelne Felder verarbeiten
        my $objCombi = $type . $startAdr;
        #Log3 $name, 5, "$name: PackObj at $objCombi, counter $counter, valuesLen $valuesLen";
        my $reading  = ObjInfo($logHash, $objCombi, 'reading');     # is data coming from a reading
        my $expr     = ObjInfo($logHash, $objCombi, 'setexpr');     # or a setexpr (convert to register data)
        my $unpack   = ObjInfo($logHash, $objCombi, 'unpack');      # pack code to use, defaults to n
        my $len      = ObjInfo($logHash, $objCombi, 'len');         # default to 1 Reg / 2 Bytes
        my $decode   = ObjInfo($logHash, $objCombi, 'decode');      # character decoding 
        my $encode   = ObjInfo($logHash, $objCombi, 'encode');      # character encoding 
        my $revRegs  = ObjInfo($logHash, $objCombi, 'revRegs');     # do not reverse register order by default
        my $swpRegs  = ObjInfo($logHash, $objCombi, 'bswapRegs');   # dont reverse bytes in registers by default
        #Log3 $name, 5, "$name: PackObj at $objCombi, counter $counter, valuesLen $valuesLen, reading $reading";
        $len = 1 if ($type =~ /[cd]/);
        
        if (!$reading && !$expr) {
            Log3 $name, 5, "$name: PackObj doesn't have reading or expr information for $objCombi";
            my $code = DevInfo($logHash, $type, 'addressErrCode', 2); 
            if ($code) {
                $response->{ERRCODE} = $code;       			# if set, packResponse will not use values string
                Log3 $name, 5, "$name: PackObj sets error code to $code";
                return 0;
            }
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
            $val = ReadingsVal($device, $rname, '');
            Log3 $name, 4, "$name: PackObj for $objCombi is using reading $rname of device $device with value $val";
        }

        $val = EvalExpr($logHash, {expr => $expr, val => $val, '$type' => $type, '%startAdr' => $startAdr} );
        $val = FormatVal($logHash, {val => $val, format => ObjInfo($logHash, $objCombi, 'format')});        
        $val = MapConvert($logHash, {map => ObjInfo($logHash, $objCombi, 'map'), 
                                      val => $val, reverse => 1, undefIfNoMatch => 1});
        $val = decode($decode, $val) if ($decode);              # decode
        $val = encode($encode, $val) if ($encode);              # encode again

        if ($type =~ /[cd]/) {
            $data .= ($val ? '1' : '0');
            $counter++;
        } 
        else {
            local $SIG{__WARN__} = sub { Log3 $name, 3, "$name: PackObj pack for $objCombi value $val with code $unpack created warning: @_"; };
            my $dataPart = pack ($unpack, $val);                # use unpack code, might create warnings
            Log3 $name, 5, "$name: PackObj packed $val with pack code $unpack to " . unpack ('H*', $dataPart);
            $dataPart =  substr ($dataPart . pack ('x' . $len * 2, undef), 0, $len * 2);
            Log3 $name, 5, "$name: PackObj padded / cut object to " . unpack ('H*', $dataPart);
            $counter += $len; 
            Log3 $name, 5, "$name: PackObj revRegs = $revRegs, dplen = " . length($dataPart);
            $dataPart = ReverseWordOrder($logHash, $dataPart, $len) if ($revRegs && length($dataPart) > 3);
            $dataPart = SwapByteOrder($logHash, $dataPart, $len) if ($swpRegs);
            $data .= $dataPart;
        }
        $startAdr += $len;                                      # go to the next object
        if ($counter < $valuesLen) {
            Log3 $name, 5, "$name: PackObj moves to next object, skip $len to $type$startAdr, counter=$counter";
        }
    } # next loop round for next object

    if ($type =~ /[cd]/) {
        Log3 $name, 5, "$name: PackObj full bit string is $data";
        $data = pack ("b$valuesLen", $data);
        Log3 $name, 5, "$name: PackObj packed / cut data string is " . unpack ('H*', $data);
    } 
    else {
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
sub PackRequest {
    my $ioHash  = shift;
    my $request = shift // {};
    my $name    = $ioHash->{NAME};
    my $fCode   = $request->{FCODE};
    my $adr     = $request->{ADR};
    my $len     = $request->{LEN};
    my $values  = $request->{VALUES} // 0;
    
    #Log3 $name, 5, "$name: PackRequest called from " . FhemCaller();
    my $data;
    if ($fCode == 1 || $fCode == 2) {           
    # read coils / discrete inputs,             pdu: fCode, startAdr, len (=number of coils)
        $data = pack ('nn', $adr, $len);        
    } 
    elsif ($fCode == 3 || $fCode == 4) {      
        # read holding/input registers,         pdu: fCode, startAdr, len (=number of regs)
        $data = pack ('nn', $adr, $len);
    } 
    elsif ($fCode == 5) {                     
        # write single coil,                    pdu: fCode, startAdr, value (1-bit as FF00)
        $data = pack ('n', $adr) . $values;
    } 
    elsif ($fCode == 6) {                     
        # write single register,                pdu: fCode, startAdr, value
        $data = pack ('n', $adr) . $values;     
    } 
    elsif ($fCode == 15) {                    
        # write multiple coils,                 pdu: fCode, startAdr, numOfCoils, byteCount, values
        $data = pack ('nnC', $adr, $len, int($len/8)+1) . $values;      
    } 
    elsif ($fCode == 16) {                    
        # write multiple regs,                  pdu: fCode, startAdr, numOfRegs, byteCount, values
        $data = pack ('nnC', $adr, $len, $len*2) . $values;
    } 
    else {                                    
        # function code not implemented yet
        Log3 $name, 3, "$name: Send function code $fCode not yet implemented";
        return;
    }
    return pack ('C', $fCode) . $data;
}   


#########################################################################
# Pack response pdu from fCode, adr, len and the packed values 
# or an error pdu if $response->{ERRCODE} contains something
# called from createResponse which is called from HandleRequest as slave
# and relayRequest (for error replies)
sub PackResponse {
    my $ioHash   = shift;
    my $response = shift // {};
    my $name     = $ioHash->{NAME};
    my $fCode    = $response->{FCODE};
    my $adr      = $response->{ADR};
    my $len      = $response->{LEN};
    my $values   = $response->{VALUES} // 0;
    
    Log3 $name, 5, "$name: PackResponse called from " . FhemCaller();
    my $data;
    if ($response->{ERRCODE}) {               # error PDU                     pdu: fCode+128, Errcode
        return pack ('CC', $fCode, $response->{ERRCODE});
    } 
    elsif ($fCode == 1 || $fCode == 2) {      # read coils / discrete inputs, pdu: fCode, len (=number of bytes), coils/inputs as bits
        $data = pack ('C', int($len/8)+1) . $values;        
    } 
    elsif ($fCode == 3 || $fCode == 4) {      # read holding/input registers, pdu: fCode, len (=number of bytes), registers
        $data = pack ('C', $len * 2) . $values;
    } 
    elsif ($fCode == 5) {                     # write single coil,            pdu: fCode, startAdr, coil value (1-bit as FF00)
        $values = pack ('H*', $values ? 'ff00' : '0000');
        $data = pack ('n', $adr) . $values;
    } 
    elsif ($fCode == 6) {                     # write single register,        pdu: fCode, startAdr, register value
        $data = pack ('n', $adr) . $values;
    } 
    elsif ($fCode == 15) {                    # write multiple coils,         pdu: fCode, startAdr, numOfCoils
        $data = pack ('nn', $adr, $len);      
    } 
    elsif ($fCode == 16) {                    # write multiple regs,          pdu: fCode, startAdr, numOfRegs
        $data = pack ('nn', $adr, $len);
    } 
    elsif ($fCode == 17) {                    # report server id,             pdu: fCode, len (=number of bytes), server id string, run indicator, optional data
        $data = pack ('C', length($values)) . $values;
    } 

    else {                                    # function code not implemented yet
        Log3 $name, 3, "$name: Send function code $fCode not yet implemented";
        return;
    }
    return pack ('C', $fCode) . $data;
}   


#######################################
# Pack Modbus Frame
sub PackFrame {
    my $hash  = shift;
    my $id    = shift;
    my $pdu   = shift;
    my $tid   = shift;
    my $name  = $hash->{NAME};
    my $proto = $hash->{PROTOCOL};
    
    #Log3 $name, 5, "$name: PackFrame called from " . FhemCaller() . " id $id" .
    #    ($tid ? ", tid $tid" : '') . ', pdu ' . unpack ('H*', $pdu);
    
    my $packedId = pack ('C', $id);    
    my $frame;
    if ($proto eq 'RTU') {                          # RTU frame format: ID, (fCode, data), CRC
        my $crc    = pack ('v', CRC($packedId . $pdu));
        $frame     = $packedId . $pdu . $crc;
    } 
    elsif ($proto eq 'ASCII') {                   # ASCII frame format: ID, (fCode, data), LRC
        my $lrc    = uc(unpack ('H2', pack ('v', LRC($packedId.$pdu))));
        $frame     = ':' . uc(unpack ('H2', $packedId) . unpack ('H*', $pdu)) . $lrc . "\r\n";
        #Log3 $name, 5, "$name: packed ASCII frame with lrc $lrc is $frame";
    } 
    elsif ($proto eq 'TCP') {                     # TCP frame format: tid, 0, len, ID, (fCode, data)
        my $dlen   = bytes::length($pdu)+1;         # length of pdu + Id
        my $header = pack ('nnnC', ($tid, 0, $dlen, $id));
        $frame     = $header.$pdu;
    } 
    else {
        Log3 $name, 3, "$name: PackFrame got unknown protocol $proto";
    }
    return $frame;
}



#####################################
# send a frame string
# called from processRequestQueue, CreateResponse 
# and RelayResponse
sub SendFrame {
    my $ioHash  = shift;
    my $id      = shift;
    my $frame   = shift;
    my $logHash = shift;
    my $name    = $ioHash->{NAME};

    Log3 $name, 5, "$name: Send called from " . FhemCaller();
    
    if ($ioHash->{TCPServer}) {
        Log3 $name, 3, "$name: Send called for TCP Server hash - this should not happen";
        return;
    }
    
    if ($ioHash->{DeviceName} eq 'none') {
        Log3 $name, 4, "$name: Simulate sending to none: " . ShowBuffer($ioHash, $frame);
    } 
    elsif ($ioHash->{TCPChild}) {
        # write to TCP connected modbus master / tcp client (we are modbus slave)
        if (!$ioHash->{CD}) {
            Log3 $name, 3, "$name: no connection to send to";
            return;
        }
        Log3 $name, 4, "$name: Send " . ShowBuffer($ioHash, $frame);
        Profiler($ioHash, 'Send');       
        for (;;) {
            my $l = syswrite($ioHash->{CD}, $frame);
            last if(!$l || $l == length($frame));
            $frame = substr($frame, $l);
        }
        $ioHash->{CD}->flush();
    } 
    else {
        if (!IsOpen($ioHash)) {
            Log3 $name, 3, "$name: no connection to send to";
            return;
        }
        Profiler($ioHash, 'Send');       
        # write to serial or TCP connected modbus slave / tcp server (we are modbus master)
        DevIo_SimpleWrite($ioHash, $frame, 0);
    }
    
    my $now = gettimeofday();
    $logHash->{REMEMBER}{lsend} = $now;         # remember when last send to this device
    $ioHash->{REMEMBER}{lsend}  = $now;         # remember when last send to this bus
    $ioHash->{REMEMBER}{lid}    = $id;          # device id we talked to
    $ioHash->{REMEMBER}{lname}  = $name;        # logical device name
    return;
}


###########################################################
# create a hash with all objects / groups to be requested
sub CreateUpdateHash {
    my $hash      = shift;
    my $name      = $hash->{NAME};
    my $modHash   = $modules{$hash->{TYPE}};    # module hash
    my $parseInfo = ($hash->{parseInfo} ? $hash->{parseInfo} : $modHash->{parseInfo});
    my $devInfo   = ($hash->{deviceInfo} ? $hash->{deviceInfo} : $modHash->{deviceInfo});
    my $intvl     = $hash->{Interval};
    my $now       = gettimeofday();

    my @RawObjList;
    foreach my $attribute (keys %{$attr{$name}}) {     # add all reading attributes to a list unless they are also in parseInfo
        if ($attribute =~ /^obj-(.*)-reading$/) {
            push @RawObjList, $1 if (!$parseInfo->{$1});
        }
    };
    push @RawObjList, keys (%{$parseInfo});     # add all parseInfo readings to the list
    Log3 $name, 5, "$name: CreateUpdateList full object list: " . join (' ',  sort @RawObjList);

    my @objList;
    my %objHash;
    my %grpHash;
    foreach my $objCombi (sort compObjCombi @RawObjList) {   # sorted by type+adr
        my $reading    = ObjInfo($hash, $objCombi, 'reading');
        my $poll       = ObjInfo($hash, $objCombi, 'poll');
        my $delay      = ObjInfo($hash, $objCombi, 'polldelay');
        my $group      = ObjInfo($hash, $objCombi, 'group');
        my $len        = ObjInfo($hash, $objCombi, 'len');
        my $lastRead   = $hash->{lastRead}{$objCombi} // 0;
        my $type       = substr($objCombi, 0, 1);
        my $adr        = substr($objCombi, 1);
        my $maxLen     = DevInfo($hash, $type, 'combine', 0);
        my $objText    = "$objCombi len $len $reading";
        #Log3 $name, 5, "$name: CreateUpdateList check $objCombi reading $reading, poll = $poll, polldelay = $delay, last = $lastRead";
        my $groupNr;
        $groupNr = $1 if ($group && $group =~ /(\d+)-(\d+)/);
        if ($groupNr) {                                 # handle group
            my $objRef = $grpHash{'g'.$groupNr};
            my $span   = 0;
            if ($objRef) {
                $span = $adr - $objRef->{adr} + $len;
                if ($objRef->{type} ne $type) {
                    Log3 $name, 3, "$name: CreateUpdateList found incompatible types in group $groupNr (so far $objRef->{type}, now $type";
                } 
                elsif ($objRef->{adr} > $adr) {
                    Log3 $name, 3, "$name: CreateUpdateList found wrong adr sorting in group $groupNr. Old $objRef->{adr}, new $adr. Please report this bug";
                } 
                elsif ($maxLen && $span > $maxLen) {
                    Log3 $name, 3, "$name: CreateUpdateList found group $groupNr span $span is longer than defined maximum $maxLen";
                } 
                else {              # add to group
                    $objRef->{len} = $span;
                    $objRef->{groupInfo} .= ($objRef->{groupInfo} ? ' and ' : '') . $objText;
                    #Log3 $name, 5, "$name: CreateUpdateList adds $objText to group $groupNr";
                }
            } 
            else {                  # new object for group
                #Log3 $name, 5, "$name: CreateUpdateList creates new hash for group $groupNr with $objText";
                $objRef = {type => $type, adr => $adr, len => $len, reading => $reading, 
                        groupInfo => $objText, group => $group, objCombi => 'g'.$groupNr};
                $grpHash{'g'.$groupNr} = $objRef;
            }
        }
        if (($poll && $poll ne 'once') || ($poll eq 'once' && !$lastRead)) {        # this was wrongly implemented (once should be specified as delay). Keep for backward compatibility
            if (!$delay || ($delay && $delay ne 'once') || ($delay eq 'once' && !$lastRead)) {
                $delay = 0 if ($delay eq 'once' || !$delay);
                $delay = $1 * ($intvl ? $intvl : 1) if ($delay =~ /^x([0-9]+)/);    # delay as multiplyer if starts with x
                if ($now >= $lastRead + $delay) {           # this object is due to be requested
                    if ($groupNr) {
                        $objHash{'g'.$groupNr} = $grpHash{'g'.$groupNr};
                        Log3 $name, 5, "$name: CreateUpdateList will request group $groupNr because of $objText";
                    } 
                    else {                                  # no group
                        $objHash{$objCombi} = {objCombi => $objCombi, type => $type, adr => $adr, reading => $reading, len => $len};
                        Log3 $name, 5, "$name: CreateUpdateList will request $objText";
                    }
                }
                else {                                          # delay not over
                    if ($groupNr && $objHash{'g'.$groupNr}) {   # but part of a group to be requested
                        Log3 $name, 5, "$name: CreateUpdateList will request $reading because it is part of group $groupNr";
                    } 
                    else {                                      # delay not over and not in a group to be requested
                        my $passed = $now - $lastRead;
                        Log3 $name, 5, "$name: CreateUpdateList will skip $reading, delay not over (delay $delay, $passed passed)";
                    }
                }
            }
        }
    }
    return \%objHash;
}


###################################
# combine objects to be requested
sub CombineUpdateHash {
    my $hash     = shift;
    my $objHash  = shift;
    my $name     = $hash->{NAME};
    my $nextSpan = 0;
    my $reason   = 'first object';
    my $lastText = '';
    my $nextText = '';
    my $lastObj;
    my $maxLen;

    Log3 $name, 4, "$name: CombineUpdateHash objHash keys before combine: " . join ',', keys %{$objHash};
    Log3 $name, 5, "$name: CombineUpdateHash tries to combine read commands";

    COMBINELOOP:
    foreach my $nextObj (sort compObjTA values %{$objHash}) {       # sorting type/adr 
        $maxLen = DevInfo($hash, $nextObj->{type}, 'combine', 1);
        next COMBINELOOP if (!$lastObj);            # initial round
        $reason = '';
        $lastText = $lastObj->{groupInfo} ? "$lastObj->{objCombi} len $lastObj->{len} ($lastObj->{groupInfo})" 
            : "$lastObj->{objCombi} len $lastObj->{len} $lastObj->{reading}";
        $nextText = $nextObj->{groupInfo} ? "$nextObj->{objCombi} len $nextObj->{len} ($nextObj->{groupInfo})" 
            : "$nextObj->{objCombi} len $nextObj->{len} $nextObj->{reading}";            
        $nextSpan = ($nextObj->{adr} + $nextObj->{len}) - $lastObj->{adr};   # combined length
        if ($nextObj->{adr} <= $lastObj->{adr}) {
            $reason = 'wrong order defined';
        } elsif ($nextObj->{type} ne $lastObj->{type}) {
            $reason = 'different types';
        } elsif ($nextSpan > $maxLen) {
            $reason = "span $nextSpan would be bigger than max $maxLen";
        }
        if (!$reason) {                                 # do combine, no reason against it
            Log3 $name, 5, "$name: CombineUpdateHash combine $lastText with $nextText to span $nextSpan, drop read for $nextObj->{objCombi}";
            $lastObj->{combine} .= ($lastObj->{combine} ? ' and ' : "$lastText with ") . $nextText;
            $lastObj->{span} = $nextSpan;               # increase the length to include following object
            delete $objHash->{$nextObj->{objCombi}};    # remove from hash
        } else {
            Log3 $name, 5, "$name: CombineUpdateHash cant combine $lastText with $nextText, $reason";
        }
    }
    continue {
        if ($reason) {
            $nextObj->{span} = $nextObj->{len};
            $lastObj = $nextObj ;        # point last obj to next so combination can start with the next one
        }
    }
    Log3 $name, 5, "$name: CombineUpdateHash keys are now " . join ',', keys %{$objHash};
    my $logMsg = '';
    foreach my $obj (sort compObjTA values %{$objHash}) {
        #Log3 $name, 5, "$name: CombineUpdateHash logmsg obj = $obj->{objCombi} span $obj->{span} reading $obj->{reading}";
        $logMsg = ($logMsg ? "$logMsg, " : '') . "$obj->{objCombi} len $obj->{span} " . 
                    ($obj->{combine} ? "(combined $obj->{combine})" : "($obj->{reading})");
    }
    Log3 $name, 4, "$name: GetUpdate will now create requests for $logMsg" ;    
    return;
}    


###############################################################################
# called via internal timer from 
# logical device module with 
# update:name - name of logical device
#
# connection doesn't need to be open - request can just be queued 
# and then processqueue will call async open and remove queue entries
# if they get too old
#
sub GetUpdate {
    my $param     = shift;
    my ($calltype,$name) = split(':',$param);
    my $hash      = $defs{$name};               # logical device hash
    my $now       = gettimeofday();
    
    Log3 $name, 4, "$name: GetUpdate (V$Module_Version) called from " . FhemCaller();
    $hash->{'.LastUpdate'} = $now;              # note that we were called - even when not as 'update' and UpdateTimer is not called afterwards
    UpdateTimer($hash, \&Modbus::GetUpdate, 'next') if ($calltype eq 'update');    
    my $msg = CheckDisable($hash);
    return if ($msg);
    my $ioHash = GetIOHash($hash);              # only needed for profiling, availability id checked in CheckDisable    
    Profiler($ioHash, 'Fhem');
    
    my $objHash = CreateUpdateHash($hash);    
    CombineUpdateHash($hash, $objHash);

    # now create the requests
    foreach my $obj (sort compObjTA values %{$objHash}) {       # sorted by type / adr
        next if !$obj;  
        my $span = $obj->{span};
        DoRequest($hash, {TYPE => $obj->{type}, ADR => $obj->{adr}, OPERATION => 'read', LEN => $span, 
                        DBGINFO => "getUpdate for " . 
                        ($obj->{combine} ? "combined $obj->{combine}" : "$obj->{reading} len $obj->{len}")});
    }
    Profiler($ioHash, 'Idle');   
    return;
}


######################################################
# describe request as string
sub RequestText {
    my $request = shift;    
    my $now     = gettimeofday();
    return 'request: ' . 
            (defined($request->{MODBUSID}) ? "id $request->{MODBUSID}" : 'unknown id' ) .
            (defined($request->{OPERATION}) ? ", $request->{OPERATION}" : '') .
            (defined($request->{FCODE}) ? " fc $request->{FCODE}" : ', unknown fc') .
            ' ' . ($request->{TYPE} // '') . ($request->{ADR} // '') .
            ($request->{LEN} ? ", len $request->{LEN}" : '') .
            ($request->{VALUES} ? ", value " . unpack('H*', $request->{VALUES}) : '') .
            (defined($request->{TID}) ? ", tid $request->{TID}" : '') .
            ($request->{DEVHASH}    && $request->{DEVHASH}{NAME}    ? ", DEVHASH $request->{DEVHASH}{NAME}" : '') .
            ($request->{MASTERHASH} && $request->{MASTERHASH}{NAME} ? ", master device $request->{MASTERHASH}{NAME}" : '') .
            ($request->{RELAYHASH}  && $request->{RELAYHASH}{NAME}  ? ", for relay device $request->{RELAYHASH}{NAME}" : '') .
            ($request->{READING} ? ", reading $request->{READING}" : '') . 
            ($request->{DBGINFO} ? " ($request->{DBGINFO})" : '') . 
            ($request->{QUEUED} ? ', queued ' . sprintf('%.2f', $now - $request->{QUEUED}) . ' secs ago' : '') . 
            ($request->{SENT} ? ', sent ' . sprintf('%.2f', $now - $request->{SENT}) . ' secs ago' : '');
}


######################################################
# describe response as string
sub ResponseText {
    my $response = shift;    
    return "response: " . ($response->{MODBUSID} ? "id $response->{MODBUSID}" : 'no id') .
        ($response->{FCODE} ? ", fc $response->{FCODE}" : ", no fcode ") .
        ($response->{ERRCODE} ? ", error code $response->{ERRCODE}" : '') .
        ($response->{TYPE} && $response->{ADR} ? ", $response->{TYPE}$response->{ADR}" : '') .
        ($response->{LEN} ? ", len $response->{LEN}" : '') .
        ($response->{VALUES} ? ', values ' . unpack('H*', $response->{VALUES}) : '') .
        (defined($response->{TID}) ? ", tid $response->{TID}" : '');
}


######################################################
# log current frame in buffer 
sub FrameText {
    my ($hash, $request, $response) = @_;
    $request  = $hash->{REQUEST} if (!$request);
    $response = $hash->{RESPONSE} if (!$response);   
    return 
        ($hash->{READ}{BUFFER} ? 'current frame / read buffer: ' . ShowBuffer($hash) : 'read buffer empty') .
        ($hash->{FRAME}{MODBUSID} ? ", id $hash->{FRAME}{MODBUSID}" : '') .
        ($hash->{FRAME}{FCODE} ? ", fCode $hash->{FRAME}{FCODE}" : '') .
        (defined($hash->{FRAME}{TID}) ? ", tid $hash->{FRAME}{TID}" : '') .
    ($request  ? ", \n" . RequestText($request) : '') . 
    ($response ? ", \n" . ResponseText($response) : '') .
    ($hash->{FRAME}{ERROR} ? ", error: $hash->{FRAME}{ERROR}" : '');
}


######################################################
# log current frame in buffer 
sub LogFrame {
    my ($hash, $msg, $logLvl, $request, $response) = @_;
    my $name  = $hash->{NAME};
    Log3 $name, $logLvl, "$name: $msg, " . FrameText($hash, $request, $response);
    return;
}


######################################################
# drop current frame from buffer or clear full buffer
# called from Timeout-, Done and Error functions
# as well as ReadFn / ReadAnswer after HandleRequest / HandleResponse
sub DropFrame {
    my $hash = shift;
    my $name = $hash->{NAME};
    my $drop = $hash->{READ}{BUFFER} // ''; # default: drop everything as master
    my $rest = '';                          # default
    my $bLen = length($drop);               # length of the buffer;
    
    return if (!$bLen);                     # no buffer no drop
    
    # mode is propagated from logical device so we know if we are master, slave or passive.
    # when we are the forwarding side of a relay, io device would be in mode master

    if ($hash->{MODE} ne 'master') {
        if ($hash->{FRAME}{CHECKSUMERROR}) {
            $drop = substr($hash->{READ}{BUFFER}, 0, 1);
            $rest = substr($hash->{READ}{BUFFER}, 1);
        }
        elsif ($hash->{FRAME}{PDULEXP} && $hash->{PROTOCOL}) {
            my $frameLen = $hash->{FRAME}{PDULEXP} + $PDUOverhead{$hash->{PROTOCOL}};
            if ($frameLen < $bLen) {
                $drop = substr($hash->{READ}{BUFFER}, 0, $frameLen);
                $rest = substr($hash->{READ}{BUFFER}, $frameLen);
            }
        }
    }
    Log3 $name, 5, "$name: DropFrame called from " . FhemCaller() . " - drop " . ShowBuffer($hash, $drop) .
        ($rest ? ' rest ' . ShowBuffer($hash, $rest) : '');
    $hash->{READ}{BUFFER} = $rest;
    delete $hash->{FRAME};
    return;
}


##################################################+
# add a message to the $frame->{ERROR} String
sub AddFrameError {
    my $frame = shift;
    my $msg   = shift;
    $frame->{ERROR} .= ($frame->{ERROR} ? ', ' : '') . $msg;
    return;
}


##################################################################
# get end of pdu / start of lrc / crc if applicable
# check crc / lrc and set $hash->{FRAME}{CHECKSUMERR} if necessary
# leave length checking, reaction / logging / dropping 
# to read function
sub CheckChecksum {   
    my $hash  = shift;
    my $name  = $hash->{NAME};
    my $proto = $hash->{PROTOCOL};
    my $frame = $hash->{FRAME};
    
    use bytes;
    my $readLen  = length($hash->{READ}{BUFFER});
    delete $frame->{CHECKSUMERROR};
    
    if ($proto eq 'RTU') {
        # todo: optimize
        my $frameLen = $frame->{PDULEXP} + $PDUOverhead{$hash->{PROTOCOL}}; # everything including id to crc
        # for RTU Overhead is 3 (id ... 2 Bytes CRC)
        my $crcInputLen = ($readLen < $frameLen ? $readLen : $frameLen) - 2; # frame without 2 bytes crc
        my $sent = unpack('v', substr($hash->{READ}{BUFFER}, $crcInputLen, 2));
        my $calc = CRC(substr($hash->{READ}{BUFFER}, 0, $crcInputLen));
        
        if ($calc != $sent) {
            $frame->{CHECKSUMERROR} = 1;
            AddFrameError($frame, 'Invalid checksum ' . unpack('H4', pack('v', $sent)) .
                ' received. Calculated ' . unpack('H4', pack('v', $calc)));
            return 0;
        } 
        else {
            Log3 $name, 5, "$name: CheckChecksum (called from " . FhemCaller() . '): ' . unpack ('H4', pack ('v', $sent)) . ' is valid';
            return 1;
        }
    } 
    elsif ($proto eq 'ASCII') {
        my $frameLen = $frame->{PDULEXP} * 2 + $PDUOverhead{$hash->{PROTOCOL}}; # everything including id and lrc
        # for ASCII: Oberhead is 7 (Start:, 2 Ziffern Id, 2 Ziffern LRC, CR LF)
        
        my $lrcInputLen = ($readLen < $frameLen ? $readLen : $frameLen) - 5;
        # : (id id ... ) lrc lrc cr lf
        
        my $lrcRead = substr($hash->{READ}{BUFFER}, $lrcInputLen + 1, 2);
        my $lrcData = substr($hash->{READ}{BUFFER}, 1, $lrcInputLen);
        my $sent = hex($lrcRead);
        my $calc = LRC(pack ('H*', $lrcData));
        #Log3 $name, 5, "$name: CheckChecksum readLen=$readLen, frameLen=$frameLen (exp $frame->{PDULEXP}, " .
        #    "ovr $PDUOverhead{$hash->{PROTOCOL}}), lrcdata " . ShowBuffer($hash, $lrcData) . 
        #    " and lrc " . ShowBuffer($hash, $lrcRead) . 
        #    " calculated " . unpack ('H2', pack ('C', $calc)) . 
        #    " Buffer " . ShowBuffer($hash);
        
        if ($calc != $sent) {
            $frame->{CHECKSUMERROR} = 1;
            AddFrameError($frame, 'Invalid checksum ' . unpack('H2', pack('C', $sent)) .
                ' received. Calculated ' . unpack('H2', pack('C', $calc)));
            return 0;
        } 
        else {
            Log3 $name, 5, "$name: CheckChecksum (called from " . FhemCaller() . '): ' .
                unpack('H2', pack('C', $sent)) . ' is valid';
            return 1;
        }
    } 
    elsif ($proto eq 'TCP') {
        # nothing to be done.
        return 1;   
    } 
    else {
        Log3 $name, 3, "$name: CheckChecksum (called from " . FhemCaller() . ") got unknown protocol $proto";
        return 0;
    }
    return 1;
}


#######################################
sub CountTimeouts {
    my $hash = shift;
    my $name = $hash->{NAME};

    if ($hash->{TCPConn}) {             # modbus TCP/RTU/ASCII over TCP
        if ($hash->{TCPServer} || $hash->{TCPChild}) {
            Log3 $name, 3, "$name: CountTimeouts called for TCP Server connection - this should not happen";
            return;
        }
        if (!$hash->{TIMEOUTS}) {
            $hash->{TIMEOUTS} = 1;
            return;
        }
        $hash->{TIMEOUTS}++;
        my $max = AttrVal($name, 'maxTimeoutsToReconnect', 0);
        if ($max && $hash->{TIMEOUTS} >= $max) {
            Log3 $name, 3, "$name: CountTimeouts counted $hash->{TIMEOUTS} successive timeouts, setting state to disconnected";
            DevIo_Disconnected($hash);      # close, set state and put on readyfnlist for reopening
        }
    }
    return;
}


#################################################################
# set state Reading and STATE internal 
# call instead of setting STATE directly and when inactive / disconnected
# when called with 

# opened - set to disabled if attr disable is set (after attr IODev, disabled would not be set after successful open)
#               set to inactive if state reading is inactive
#               otherwise set to opened
# disconnected - set to disabled if attr disable is set (when connection is lost or after define)
#               set to inactive if state reading is already inactive
#               otherwise set to disconnected

# inactive - set to disabled if attr disable is set (after set inactive)
#               otherwise set to inactive
# active - set to disabled if attr disable is set (after set active)
#               otherwise set to active temporarily
#               after open state will be set again

# disabled - set to disabled (while attr disable is set)
# enabled - set to active temporarily  (when attr disable is removed)
#               after open state will be set again
sub SetStates {
    my $hash     = shift;
    my $state    = shift;
    my $name     = $hash->{NAME};
    my $newState = $state;

    #Log3 $name, 5, "$name: SetState called from " . FhemCaller() . " with $state, current state reading is " . ReadingsVal($name, 'state', '');
    if ($state ne 'disabled') {                                         # for disabled nothing else matters
        if ($state eq 'enabled') {
            $newState = 'active';                                       # enabled (disable removed) becomes active
        } elsif ($state ne 'active') {
            if (AttrVal($name, 'disable', 0)) {                         # otherweise check disable attr first
                $newState = 'disabled';
            } elsif (ReadingsVal($name, 'state', '') eq 'inactive') {   # and then check if inactive
                $newState = 'inactive';
            }
        }
    }
    Log3 $name, 5, "$name: SetState called from " . FhemCaller() . " with $state sets state and STATE to $newState";
    $hash->{STATE} = $newState;
    return if ($newState eq ReadingsVal($name, 'state', ''));
    readingsSingleUpdate($hash, 'state', $newState, 1);
    return;
}


###############################################
# Called via InternalTimer with 'stimeout:$name' 
# timer is set in ...
# if this is called, we are TCP Slave
sub ServerTimeout {
    my $param = shift;
    my ($error,$name) = split(':',$param);
    my $hash  = $defs{$name};
    if ($hash) {
        if ($hash->{CHILDOF}) {
            my $pName = $hash->{CHILDOF}{NAME};
            Log3 $pName, 4, "$pName: closing connection after inactivity" if ($pName);
        }
        DoClose($hash);
    }
    return;
};


################################################################################
# timeout waiting for a response
# Called via InternalTimer with "timeout:$name" (physical device)
# timer is set in ProcessRequestQueue only
#
# if this is called then we are Master and did send a request
# or we were used as relay forward device and did send a request

# todo: how is timeout handled in passive mode?

sub ResponseTimeout {
    my $param   = shift;                        # text:name (name of physical io device)
    my ($error,$name) = split(':',$param);
    my $hash    = $defs{$name};
    my $logLvl  = AttrVal($name, 'timeoutLogLevel', 3);
    my $retries = AttrVal($name, 'retriesAfterTimeout', 0);
    my $request;
    my $masterHash;
    my $relayHash;
    
    if ($hash->{REQUEST}) {
        $request    = $hash->{REQUEST};
        $masterHash = $request->{MASTERHASH};               # REQUEST stored in physical hash by ProcessRequestQueue
        $relayHash  = $request->{RELAYHASH};
        #Log3 $name, 3, "$name: ResponseTimeout called, master was $masterHash->{NAME}" .
        #    ($relayHash ? " for relay $relayHash->{NAME}" : '');
    } 
    else {
        Log3 $name, 3, "$name: ResponseTimeout called but request structure doesn't exist - this error should never happen";
    }
    $hash->{EXPECT} = 'idle';
    
    LogFrame($hash, 'Timeout waiting for a modbus response', $logLvl);
    Statistics($hash, 'Timeouts');
    CountTimeouts ($hash);
    if ($request && $relayHash) {                           # create an error response through the relay
		my $origRequest = $relayHash->{REQUEST};
		if (!$origRequest->{MODBUSID}) {
			Log3 $name, 4, "$name: relaying error response back failed because original request is missing";
		} 
        else {
			# adjust Modbus ID for back communication
			$request->{MODBUSID} = $origRequest->{MODBUSID};
			$request->{TID}      = ($origRequest->{TID} ? $origRequest->{TID} : 0);
			Log3 $name, $logLvl, "$name: ResponseTimeout sends error messsage back to id $request->{MODBUSID}" .
				($request->{TID} ? ", tid $request->{TID}" : '');
		
			my $reIoHash = GetIOHash($relayHash);      # the physical hash of the relay that received the original request
			if (!$reIoHash) {
				Log3 $name, $logLvl, "$name: sending timout response back failed because relay slave (=server) side io device disappeared";
			} 
            else {
				$request->{ERRCODE} = 11;            			    # gw target failed to respond ($hash->{REQUEST} is a copy of the original request)
				CreateResponse($reIoHash, $relayHash, $request);    # create and send an error response, don't pack values since ERRCODE is set
			}
		}
        if ($retries != 0) {
            Log3 $name, 4, "$name: ResponseTimeout ignores retriesAfterTimeout because the request was relayed";
            $retries = 0;                                   # don't retry as a relay
        }
    }
    Profiler($hash, 'Idle');
    DropFrame($hash);                                       # drop $hash->{FRAME} and the relevant part of $hash->{READ}{BUFFER}
    delete $hash->{nextTimeout};    
    
    $hash->{RETRY} = ($hash->{RETRY} ? $hash->{RETRY} : 0); # deleted in doRequest and handleResponse
    if ($hash->{RETRY} < $retries && $request) {			# retry?
        $hash->{RETRY}++;
        Log3 $name, 4, "$name: retry last request, retry counter $hash->{RETRY}";
        $request->{FRONT} = 1;                              # put this retry in the front of the queue but don't sleep if delay is necessary
        QueueRequest($hash, $request);
    } 
    else {
        delete $hash->{REQUEST};
        delete $hash->{RETRY};
    }
    StartQueueTimer($hash, \&Modbus::ProcessRequestQueue, {delay => 0});    # call processRequestQueue at next possibility if appropriate
    return;
};


###############################################################
# Check if connection through IO Dev is not disabled 
# and call open (force) if necessary for prioritized get / set
# and potentially take over last read with readAnswer
#
# if non prioritized get / set (parameter async = 1) 
# we leave the connection management to ready and processRequestQueue 
# 
sub GetSetChecks {
    my $hash  = shift;
    my $async = shift;
    my $name  = $hash->{NAME};
    my $force = !$async;
    my $msg   = CheckDisable($hash);
    if (!$msg) {
        if (!$hash->{MODE} || !$hash->{PROTOCOL} || $hash->{MODE} ne 'master') {
            $msg = 'only possible as Modbus master';
        } 
        elsif ($force) {                            # only check connection if not async 
            Log3 $name, 5, "$name: GetSetChecks with force";
            
            my $ioHash = GetIOHash($hash);          # physical hash to check busy / take over with readAnswer
            if (!$ioHash) {
                $msg = 'no IO device';
            } 
            elsif (!IsOpen($ioHash)) {
                DoOpen($ioHash, {FORCE => $force}); # force synchronous open unless non prioritized get / set
                $msg = 'device is disconnected' if (!IsOpen($ioHash));
            }
            if (!$msg && $ioHash->{EXPECT} eq 'response') { # Answer for last request has not yet arrived
                Log3 $name, 4, "$name: GetSetChecks calls ReadAnswer to take over async read, still waiting for response, " . FrameText($ioHash);
                # no $msg because we want to continue afterwards
                ReadAnswer($ioHash);                # finish last read and wait for result
            }
        }
    }
    Log3 $name, 5, "$name: GetSetChecks returns " . ($msg // 'success');
    return $msg;
}   
   

############################################
# Check if disabled or IO device is disabled
sub CheckDisable {
    my $hash = shift;    
    my $name = $hash->{NAME};
    my $msg;
    #Log3 $name, 5, "$name: CheckDisable called from " . FhemCaller();
    
    if ($hash->{TYPE} eq 'Modbus' || $hash->{TCPConn}) {    # physical hash
        if (IsDisabled($name)) {
            $msg = 'device is disabled';
        }
    } 
    else {                                                  # this is a logical device hash
        my $ioHash = GetIOHash($hash);                      # get physical io device hash
        if (IsDisabled($name)) {
            $msg = 'device is disabled';
        } elsif (!$ioHash) {
            $msg = 'no IO Device to communicate through';
        } elsif (IsDisabled($ioHash->{NAME})) {
            $msg = 'IO device is disabled';
        }
    }
    Log3 $name, 5, "$name: CheckDisable called from " . FhemCaller() . " returns $msg" if ($msg);
    return $msg;
}   


################################################################
# set the $hash->{IODev} pointer to the physical io device
# and register there 
#
# check the name passed or the IODev attr or search for device
# 
# called from GetIOHash with the logical hash or from attr IODev
################################################################
sub SetIODev {
    my $hash   = shift;                                 # the logical device hash
    my $name   = $hash->{NAME};                         # name of the logical device 
    my $ioName = shift // AttrVal($name, 'IODev', '');  # the name of the desired io dev    
    my $id     = $hash->{MODBUSID};
    my $ioHash;

    return $hash if ($hash->{TCPConn});
    Log3 $name, 5, "$name: SetIODev called from " . FhemCaller();
    if ($ioName) {                                  # if we have a name (passed or from attribute), check its usability
        if (!$defs{$ioName}) {
            Log3 $name, 3, "$name: SetIODev from $name to $ioName but $ioName does not exist (yet?)";
        } 
        elsif (CheckIOCompat($hash, $defs{$ioName}, 3)) {
            $ioHash = $defs{$ioName};               # ioName can be used as io device, set hash
        }
    }
    if (!$ioHash && !$ioName) {                     # if no attr and no name passed search for usable io device
        DEVLOOP:
        for my $p (sort { $defs{$b}{NR} <=> $defs{$a}{NR} } keys %defs) {       
            if (CheckIOCompat($hash, $defs{$p}, 5)) {
                $ioHash = $defs{$p};
                last DEVLOOP;
            }
        }
    }
    if (!$ioHash) {                                 # nothing found -> give up for now
        Log3 $name, 3, "$name: SetIODev found no usable physical modbus device";
        SetStates($hash, 'disconnected');
        UnregAtIODev($hash);
        delete $hash->{IODev};
        return;
    }
    RegisterAtIODev($hash, $ioHash);		        # register, set MODE and PROTOCOL
    SetStates($hash, 'opened');                     # set initial state for logical device connected through physical serial device like DevIo would do it after open
    return $ioHash;
}

    
#####################################################################
# called from logical device fuctions with log dev hash 
# to get the physical io device hash which should be
# stored in $hash->{IODev} (fhem.pl sets this when IODev attr is set)
# or find suitable io dev, register there 
# and reconstruct this pointer by calling SetIODev if necessary
#
# called from many LD functions like get, set, getUpdate, send, ...
#####################################################################
sub GetIOHash {
    my $hash = shift;
    my $name = $hash->{NAME};                                   # name of logical device
    #Log3 $name, 5, "$name: GetIOHash called from " . FhemCaller();
    
    return $hash if ($hash->{TCPConn});                         # for TCP/IP connected devices ioHash = hash
    return $hash if ($hash->{TYPE} eq 'Modbus');                # this is already the physical device!
    return $hash->{IODev} if ($hash->{IODev} 
            && IsRegisteredAtIODev($hash, $hash->{IODev}));     # $hash->{IODev} is set correctly and $hash is registerd
    
    Log3 $name, 4, "$name: GetIOHash (called from " . FhemCaller() . ") did not find valid IODev hash key, calling SetIODev now";
    return $hash->{IODev} if (SetIODev($hash));                 # reconstruct pointer to physical device
    #Log3 $name, 4, '$name: GetIOHash did not find IODev attribute or matching physical serial Modbus device';
    return;
}


#####################################################################
# Check if $ioHash can be used as IODev for $hash
# return 1 if ok, log if not
#####################################################################
sub CheckIOCompat {
    my $hash   = shift;
    my $ioHash = shift;
    my $logLvl = shift;
    my $name   = $hash->{NAME};                                 # name of logical device
    my $ioName = $ioHash->{NAME};                               # name of physical device
    my $id     = $hash->{MODBUSID};                             # Modbus id of logical device
    my $msg    = '';

    return 1 if ($hash->{TCPConn});                             # for TCP/IP connected devices ioHash = hash so everything is fine 
    return if (!$ioHash || !$id || $ioHash->{TYPE} ne 'Modbus');
    if (!$hash->{PROTOCOL}) {
        $msg = "$name doesn't have a protocol set";
    } 
    elsif (!$hash->{MODE}) {
        $msg = "$name doesn't have a mode set";
    } 
    elsif ($ioHash->{PROTOCOL} && $ioHash->{PROTOCOL} ne $hash->{PROTOCOL}) {
        $msg = "$ioName is locked to protocol $ioHash->{PROTOCOL} by " .
                DevLockingKey($ioHash, 'PROTOCOL');
    } 
    elsif ($ioHash->{MODE} && $ioHash->{MODE} ne $hash->{MODE}) {
        $msg = "$ioName is locked to mode $ioHash->{MODE} by " .
                DevLockingKey($ioHash, 'MODE');
    } 
    elsif ($ioHash->{MODE} && $ioHash->{MODE} ne 'master') {    # check that no other device has registered this id (unless master)
        for my $ld (keys %{$ioHash->{defptr}}) {                # for each registered logical device    
            if ($ld ne $name && $defs{$ld} && $defs{$ld}{MODBUSID} == $id) {
                $msg = "$ioName has already registered id $id for $ld";
            }
        }
    }
    if ($msg) {
        Log3 $name, ($logLvl ? $logLvl : 5), "$name: CheckIOCompat (called from " . FhemCaller() . ") for $name and $ioName: $msg";
        return;
    }
    return 1;
}


################################################################
# check if logical device is registered at io dev 
sub IsRegisteredAtIODev {
    my $hash   = shift;
    my $ioHash = shift;
    my $name   = $hash->{NAME};

    return 1 if ($hash->{MODBUSID}
                && $hash->{MODBUSID}   == $ioHash->{defptr}{$name}
                && $hash->{PROTOCOL}   && $hash->{MODE}
                && $ioHash->{PROTOCOL} && $ioHash->{MODE}
                && $ioHash->{PROTOCOL} eq $hash->{PROTOCOL}
                && $ioHash->{MODE}     eq $hash->{MODE});
    return;
}


################################################################
# register / lock protocol and mode at io dev 
# called from SetIODev
sub RegisterAtIODev {
    my $hash   = shift;
    my $ioHash = shift;
    my $name   = $hash->{NAME};
    my $id     = $hash->{MODBUSID};
    my $ioName = $ioHash->{NAME};

    return if ($hash->{TCPConn});
    Log3 $name, 3, "$name: RegisterAtIODev called from " . FhemCaller() . " registers $name at $ioName with id $id" . 
        ($hash->{MODE} ? ", MODE $hash->{MODE}" : '') .
        ($hash->{PROTOCOL} ? ", PROTOCOL $hash->{PROTOCOL}" : '');

    UnregAtIODev ($hash, 1);                        # first silently clean up existing registrations
    $hash->{IODev}           = $ioHash;             # point internal IODev to io device hash    
    $ioHash->{defptr}{$name} = $id;                 # register logical device for given id at io
    $ioHash->{PROTOCOL}      = $hash->{PROTOCOL};   # lock protocol and mode
    $ioHash->{MODE}          = $hash->{MODE};
    ResetExpect($ioHash);
    return;
}

    
################################################################
# unregister / unlock protocol and mode at io dev 
# to be called when MODBUSID or IODEv changes 
# or when device is deleted
# see attr, notify or directly from undef
################################################################
# todo: Tests for register / unregister with several modes / protocols
# todo: Tests with relays, rename MasterSlave1 to OpenDelays
sub UnregAtIODev {
    my $hash   = shift;
    my $silent = shift;
    my $name   = $hash->{NAME};
    my $id     = $hash->{MODBUSID};
    return if ($hash->{TCPConn});
    Log3 $name, 5, "$name: UnregAtIODev called from " . FhemCaller() if (!$silent);

    DEVLOOP:
    for my $d (values %defs) {                  # go through all physical Modbus devices
        next DEVLOOP if ($d->{TYPE} ne 'Modbus');
        my $protocolCount = 0;
        my $modeCount     = 0;
        for my $ld (keys %{$d->{defptr}}) {     # and logical devices registered there with their ids 
            my $ldev = $defs{$ld};
            if ($ldev && $ld eq $name) {        # the one to be unregistered
                Log3 $name, 5, "$name: UnregAtIODev is removing $name from registrations at $d->{NAME}"
                    if (!$silent);
                delete $d->{defptr}{$name};     # delete id as key pointing to $hash if found
            } 
            else {                              # another logical device registered at $d
                if ($ldev && $ldev->{PROTOCOL} eq $d->{PROTOCOL}) {
                    $protocolCount++;
                } else {
                    Log3 $name, 3, "$name: UnregAtIODev called from " . FhemCaller() . " found device $ld" .
                            " with protocol $ldev->{PROTOCOL} registered at $d->{NAME} with protocol $d->{PROTOCOL}." .
                            ' This should not happen';
                }
                if ($ldev->{MODE} eq $d->{MODE}) {
                    $modeCount++;
                } else {
                    Log3 $name, 3, "$name: UnregAtIODev called from " . FhemCaller() . " found device $ld" .
                            " with mode $ldev->{MODE} registered at $d->{NAME} with mode $d->{MODE}." .
                            ' This should not happen';
                }
            }
        }
        if (!$protocolCount && !$modeCount) {
            Log3 $name, 5, "$name: UnregAtIODev is removing locks at $d->{NAME}" if (!$silent);
            delete $d->{PROTOCOL};
            delete $d->{MODE};
        }
    }
    return;
}


#########################################################################
# called from HandleRequest / HandleResponse with Modbus ID 
# to get logical device hash responsible for this Id
#
# The Id passed here (from a received Modbus frame) is looked up
# in the table of registered logical devices.
# for requests this is the way to find the right logical device hash
#
# for responses it should match the id of the request sent/seen before
# 
# The logical device hash pointed to should have this id set as well
# and if it is TCP connected, the logical hash is also the physical
#
# todo: pass mode required (master or slave/relay?) ??
sub GetLogHash {
    my $ioHash = shift;
    my $Id     = shift;
    my $name   = $ioHash->{NAME};               # name of physical device
    my $logHash;
    my $logName; 

    if ($ioHash->{TCPConn}) {
        $logHash = $ioHash;                     # Modbus TCP/RTU/ASCII over TCP, physical hash = logical hash
    } 
    else {
        for my $ld (keys %{$ioHash->{defptr}}) {    # for each registered logical device    
            $logHash = $defs{$ld} if ($ioHash->{defptr}{$ld} == $Id);
        }
        if (!$logHash) {
            for my $d (values %defs) {          # go through all physical Modbus devices and look for a suitable one
                if ($d->{TYPE} ne 'Modbus' && $d->{MODULEVERSION} && $d->{MODULEVERSION} =~ /^Modbus / 
                        && $d->{MODBUSID} eq $Id && $d->{PROTOCOL} eq $ioHash->{PROTOCOL} && $d->{MODE} eq $ioHash->{MODE}) {
                    $logHash = $d;
                    Log3 $name, 3, "$name: GetLogHash called from " . FhemCaller() . 
                        ' found logical device by searching! This should not happen';
                }
            }
        }
    }
    if (!$logHash) {	
        Log3 $name, 5, "$name: GetLogHash didnt't find a logical device for Modbus id $Id";
        return;
    }
    $logName = $logHash->{NAME};            # don't refer to parent - we need to focus on the right connection
    if ($logHash->{MODBUSID} != $Id) {
        Log3 $name, 3, "$name: GetLogHash called from " . FhemCaller() . " detected wrong Modbus Id $Id, expecting $logHash->{MODBUSID}";
        return;
    } 
    Log3 $name, 5, "$name: GetLogHash returns hash for device $logName" if (!$ioHash->{TCPConn});
    return $logHash
}



#######################################################################################
# who locked key at iodev ?
sub DevLockingKey {
    my $ioHash = shift;
    my $key    = shift;

    foreach my $ld (keys %{$ioHash->{defptr}}) {
        if ($defs{$ld} && $defs{$ld}{$key} eq $ioHash->{$key}) {
            my $ioName = $ioHash->{NAME};
            Log3 $ioName, 5, "$ioName: DevLockingKey found $ld to lock key $key at $ioName as $defs{$ld}{$key}";
            return $ld;
        }
    }
    return 'unknown (this should not happen)';
}


################################################################
# show buffer as hex string or ascii for Modbus ascii
sub ShowBuffer {
    my $hash   = shift;
    my $buffer = shift // $hash->{READ}{BUFFER};
    if ($hash->{PROTOCOL} && $hash->{PROTOCOL} eq 'ASCII') {
        my $ret = '';
        foreach my $char (split //, $buffer) {
            if ($char =~ /[0-9A-Fa-f\:]/) {
                $ret .= $char;
            } else {
                $ret .= ' \\' . ord($char) . ' ';
            }
        }
        return $ret;
    }
    return unpack ('H*', $buffer);
}


################################################################
# reset EXPECT in physical device hash to initial value
sub DropBuffer {
    my $hash = shift;
    my $add  = shift;
    my $name = $hash->{NAME};
    if ($hash->{READ}{BUFFER}) {
        Log3 $name, 5, "$name: DropBuffer for " . FhemCaller() . 
            " clears the reception buffer with " . ShowBuffer($hash) .
            ($add ? " $add" : '');
        $hash->{READ}{BUFFER} = '';
    }
    return;
}


################################################################
# reset EXPECT in physical device hash to initial value
sub ResetExpect {
    my $hash = shift;
    my $add  = shift;
    my $name = $hash->{NAME};
    my $oldE = $hash->{EXPECT} // 'undefined';
    $hash->{EXPECT} = (!$hash->{MODE} || $hash->{MODE} eq 'master' ? 'idle' : 'request');
    Log3 $name, 5, "$name: ResetExpect for " . FhemCaller() . " from $oldE to $hash->{EXPECT}" .
        ($add ? " $add" : '') if ($hash->{EXPECT} ne $oldE);
    return;
}


########################################
# used for sorting and combine checking
sub compObjCombi ($$) {                      ## no critic - seems to be required here
    my ($a,$b) = @_;
    my $aType  = substr($a, 0, 1);
    my $aStart = substr($a, 1);
    my $bType  = substr($b, 0, 1);
    my $bStart = substr($b, 1);
    my $result = ($aType cmp $bType);   
    return $result if ($result);
    $result = $aStart <=> $bStart;
    return $result;
}


##############################################################################
# used for sorting hashes that contain data objects for reading creation
# compare $obj{$objCombi}{group} group-order values
sub compObjGroups ($$) {                    ## no critic - seems to be required here
    my ($a, $b) = @_;
    my $aGrp = $a->{group} // 0;
    my $bGrp = $b->{group} // 0;
    my ($aNr, $aPos) = ($aGrp =~ /(\d+)-(\d+)/);
    my ($bNr, $bPos) = ($bGrp =~ /(\d+)-(\d+)/);
    my $result = (($aNr // 0) <=> ($bNr // 0));
    return $result if ($result);
    $result = ($aPos // 0) <=> ($bPos // 0);
    return $result if ($result);

    my $aType  = $a->{type} // '';
    my $aStart = $a->{adr} // 0;
    my $bType  = $b->{type} // '';
    my $bStart = $b->{adr} // 0;
    $result = ($aType cmp $bType);   
    return $result if ($result);
    $result = $aStart <=> $bStart;
    return $result;
}


##############################################################################
# used for sorting hashes that contain data objects for getupdate
sub compObjTA ($$) {                    ## no critic - seems to be required here
    my ($a, $b) = @_;
    my $aType  = $a->{type} // '';
    my $aStart = $a->{adr} // 0;
    my $bType  = $b->{type} // '';
    my $bStart = $b->{adr} // 0;
    my $result = ($aType cmp $bType);   
    return $result if ($result);
    $result = $aStart <=> $bStart;
    return $result;
}


#####################################
sub CRC {
    use bytes;
    my $frame = shift;
    my $crc   = 0xFFFF;
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
sub LRC {
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


################################################
# Get obj- Attribute with potential 
# leading zeros
sub ObjAttr {
    my $hash  = shift;
    my $key   = shift;
    my $oName = shift;
    my $name  = $hash->{NAME};
    my $aName = 'obj-'.$key.'-'.$oName;
    return $attr{$name}{$aName} if (defined($attr{$name}{$aName}));
    if ($hash->{LeadingZeros}) {    
        if ($key =~ /([cdih])0*([0-9]+)/) {
            my $type = $1;
            my $adr  = $2;
            while (length($adr) <= 5) {             
                $aName = 'obj-'.$type.$adr.'-'.$oName;
                #Log3 $name, 5, "$name: ObjInfo check $aName";
                return $attr{$name}{$aName} 
                    if (defined($attr{$name}{$aName}));
                $adr = '0' . $adr;
            }
        }
    }
    return;
}

    
################################################
# Get Object Info from Attributes,
# parseInfo Hash or default from deviceInfo Hash
sub ObjInfo {
    my $hash        = shift;
    my $key         = shift;
    my $oName       = shift;
   
    my $defName     = $attrDefaults{$oName}{devDefault};
    my $lastDefault = $attrDefaults{$oName}{default};
    $hash = $hash->{CHILDOF} if ($hash->{CHILDOF});                     # take info from parent device if TCP server conn (TCP slave)
    my $name        = $hash->{NAME};
    my $modHash     = $modules{$hash->{TYPE}};
    my $parseInfo   = ($hash->{parseInfo} ? $hash->{parseInfo} : $modHash->{parseInfo});
    #Log3 $name, 5, "$name: ObjInfo called from " . FhemCaller() . " for $key, object $oName" . 
    #   ($defName ? ", defName $defName" : '') . ($lastDefault ? ", lastDefault $lastDefault" : '');
        
    my $reading = ObjAttr($hash, $key, 'reading');
    if (!defined($reading) && $parseInfo->{$key} && $parseInfo->{$key}{reading}) {
        $reading = $parseInfo->{$key}{reading};
    }
    if (!defined($reading)) {
        #Log3 $name, 5, "$name: ObjInfo could not find a reading name";
        return (defined($lastDefault) ? $lastDefault : '');
    }
    
    #Log3 $name, 5, "$name: ObjInfo now looks at attrs for oName $oName / reading $reading / $key";
    if (defined($attr{$name})) {
        # check for explicit attribute for this object
        my $value = ObjAttr($hash, $key, $oName);
        return $value if (defined($value));
        
        # check for special case: attribute can be name of reading with prefix like poll-reading
        return $attr{$name}{$oName.'-'.$reading} 
            if (defined($attr{$name}{$oName.'-'.$reading}));
    }
    
    # parseInfo for object $oName if special Fhem module using parseinfoHash
    return $parseInfo->{$key}{$oName}
        if (defined($parseInfo->{$key}) && defined($parseInfo->{$key}{$oName}));
    
    # check for type entry / attr ...
    if ($oName ne 'type') {
        #Log3 $name, 5, "$name: ObjInfo checking types";
        my $dType = ObjInfo($hash, $key, 'type');
        if ($dType ne '***NoTypeInfo***') {
            #Log3 $name, 5, "$name: ObjInfo for $key and $oName found type $dType";
            my $typeSpec = DevInfo($hash, "type-$dType", $oName, '***NoTypeInfo***');
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
            my $daName    = 'dev-'.$type.'-'.$defName;
            #Log3 $name, 5, "$name: ObjInfo checking $daName";
            return $attr{$name}{$daName} 
                if (defined($attr{$name}{$daName}));
            
            # check for default attribute for all object types
            my $dadName   = 'dev-'.$defName;
            #Log3 $name, 5, "$name: ObjInfo checking $dadName";
            return $attr{$name}{$dadName} 
                if (defined($attr{$name}{$dadName}));
        }
        my $devInfo = ($hash->{deviceInfo} ? $hash->{deviceInfo} : $modHash->{deviceInfo});
        return $devInfo->{$type}{$defName}
            if (defined($devInfo->{$type}) && defined($devInfo->{$type}{$defName}));
    }
    return (defined($lastDefault) ? $lastDefault : '');
}


################################################
# Get Type Info from Attributes,
# or deviceInfo Hash
sub DevInfo {
    my $hash        = shift;
    my $type        = shift;
    my $oName       = shift;
    my $lastDefault = shift;
    $hash = $hash->{CHILDOF} if ($hash->{CHILDOF});                     # take info from parent device if TCP server conn
    my $name        = $hash->{NAME};
    my $modHash     = $modules{$hash->{TYPE}};
    my $devInfo     = ($hash->{deviceInfo} ? $hash->{deviceInfo} : $modHash->{deviceInfo});
    my $aName       = 'dev-'.$type.'-'.$oName;
    my $adName      = 'dev-'.$oName;
    
    if (defined($attr{$name})) {
        return $attr{$name}{$aName} if (defined($attr{$name}{$aName}));     # explicit attribute for this object type
        return $attr{$name}{$adName} if (defined($attr{$name}{$adName}));   # default attribute for all object types
    }
    # default for object type in deviceInfo
    return $devInfo->{$type}{$oName} if (defined($devInfo->{$type}) && defined($devInfo->{$type}{$oName}));
    return (defined($lastDefault) ? $lastDefault : '');
}


##################################################
# Get Type/Adr for a reading name from Attributes,
# or parseInfo Hash
# called from get and set to get objCombi for name
sub ObjKey {
    my $hash    = shift;
    my $reading = shift // '';
    return if ($reading eq '?');
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
    return '';
}


# Try to call a user defined function if defined
#################################################
sub TryCall {
    my ($hash, $fName, $reading, $val) = @_;
    my $name = $hash->{NAME};
    my $modHash = $modules{$hash->{TYPE}};
    if ($modHash->{$fName}) {
        my $func = $modHash->{$fName};
        Log3 $name, 5, "$name: " . FhemCaller() . " is calling $fName via TryCall for reading $reading and val $val";
        no strict 'refs';               ## no critic - need symbolic function name from attr
        my $ret = eval { &{$func}($hash,$reading,$val) };
        if( $@ ) {         
            Log3 $name, 3, "$name: " . FhemCaller() . " error calling $fName: $@";
            return;
        }                   
        use strict 'refs';
        return $ret
    }
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
        <li><b>frameGap</b></li> 
            defines the time after which the read buffer is discarded if no frame has been received. This defaults to 1.5 seconds.
        <li><b>dropQueueDoubles</b></li> 
            prevents new request to be queued if the same request is already in the send queue
        <li><b>retriesAfterTimeout</b></li> 
            tbd.    
            
        <li><b>skipGarbage</b></li> 
            If the module is used as master or if it is using Modbus ASCII as protocol, then the module will skip bytes received 
            that can not be the start of correct frames.<br>
            For Modbus ASCII it skips bytes until the expected starting byte ":" is seen.
            For Modbus RTU a response has to start with the id of the request that was sent before.<br>
            If set to 1 this attribute will enhance the way the module treats Modbus request frames over serial lines in passive mode and a slave.
            It will then skip all bytes until a byte with a modbus id is seen that is used by a logical Fhem modbus device. 
            Or if the last frame was a request, then it skips everything until the modbus id of this request is seen as the start of a response.
            Setting this attribuet to 1 might lead to more robustness, however when there are other slaves on the same bus, it might als create trouble when other slaves do not send responses.
            <br>
            
        <li><b>profileInterval</b></li> 
            if set to something non zero it is the time period in seconds for which the module will create bus usage statistics. 
            Please note that this number should be at least twice as big as the interval used for requesting values in logical devices that use this physical device<br>
            The bus usage statistics create the following readings:
            <ul>
                <li><b>Profiler_Delay_sum</b></li>
                    seconds used as delays to implement the defined delays like sendDelay and commDelay
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


