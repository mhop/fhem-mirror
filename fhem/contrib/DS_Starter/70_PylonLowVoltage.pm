#########################################################################################################################
# $Id$
#########################################################################################################################
#
# 70_PylonLowVoltage.pm
#
# A FHEM module to read BMS values from a
# Pylontech US2000plus/US3000 LiFePo04 battery
#
# This module is based on 70_Pylontech.pm written 2019 by Harald Schmitz
# Code modifications and extensions: (c) 2023 by Heiko Maaz   e-mail: Heiko dot Maaz at t-online dot de
#
# Forumlinks:
# https://forum.fhem.de/index.php?topic=117466.0  (Source of original module)
# https://forum.fhem.de/index.php?topic=126361.0
# https://forum.fhem.de/index.php?topic=112947.0
# https://forum.fhem.de/index.php?topic=32037.0
#
# Photovoltaik Forum:
# https://www.photovoltaikforum.com/thread/130061-pylontech-us2000b-daten-protokolle-programme
#
#########################################################################################################################
# Copyright notice
#
# (c) 2019 Harald Schmitz (70_Pylontech.pm)
# (c) 2023 Heiko Maaz
#
# This script is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# The GNU General Public License can be found at
# http://www.gnu.org/copyleft/gpl.html.
#
# This script is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# This copyright notice MUST APPEAR in all copies of the script!
#
#########################################################################################################################
#
#  Leerzeichen entfernen: sed -i 's/[[:space:]]*$//' 70_PylonLowVoltage.pm
#
#########################################################################################################################
package FHEM::PylonLowVoltage;                                     ## no critic 'package'

use strict;
use warnings;
use GPUtils qw(GP_Import GP_Export);                               # wird für den Import der FHEM Funktionen aus der fhem.pl benötigt
use Time::HiRes qw(gettimeofday ualarm);
use IO::Socket::INET;
use Errno qw(ETIMEDOUT EWOULDBLOCK);
use Scalar::Util qw(looks_like_number);

eval "use FHEM::Meta;1"          or my $modMetaAbsent = 1;         ## no critic 'eval'
eval "use IO::Socket::Timeout;1" or my $iostAbsent    = 1;         ## no critic 'eval'

use FHEM::SynoModules::SMUtils qw(moduleVersion);                  # Hilfsroutinen Modul

no if $] >= 5.017011, warnings => 'experimental::smartmatch';

# Run before module compilation
BEGIN {
  # Import from main::
  GP_Import(
      qw(
          AttrVal
          AttrNum
          data
          defs
          fhemTimeLocal
          fhem
          FmtTime
          FmtDateTime
          init_done
          InternalTimer
          IsDisabled
          Log
          Log3
          modules
          parseParams
          readingsSingleUpdate
          readingsBulkUpdate
          readingsBulkUpdateIfChanged
          readingsBeginUpdate
          readingsDelete
          readingsEndUpdate
          ReadingsAge
          ReadingsNum
          ReadingsTimestamp
          ReadingsVal
          RemoveInternalTimer
          readingFnAttributes
        )
  );

  # Export to main context with different name
  #     my $pkg  = caller(0);
  #     my $main = $pkg;
  #     $main =~ s/^(?:.+::)?([^:]+)$/main::$1\_/g;
  #     foreach (@_) {
  #         *{ $main . $_ } = *{ $pkg . '::' . $_ };
  #     }
  GP_Export(
      qw(
          Initialize
        )
  );
}

# Versions History intern (Versions history by Heiko Maaz)
my %vNotesIntern = (
  "0.1.1"  => "16.08.2023 integrate US3000C, add print request command in HEX to Logfile, attr timeout ".
              "change validation of received data, change DEF format, extend evaluation of chargeManagmentInfo ".
              "add evaluate systemParameters, additional own values packImbalance, packState ",
  "0.1.0"  => "12.08.2023 initial version, switch to perl package, attributes: disable, interval, add command hashes ".
                          "get ... data command, add meta support and version management, more code changes ",
);

## Konstanten
###############
my @PylonRdngs = (
    'serialNumber',
    'batteryVoltage',                                                # V
    'averageCellVoltage',
    'batteryCurrent',                                                # A
    'SOC',                                                           # % (state of charge)
    'cycles',                                                        # charge/discharge cycles (>6000)
    'cellVoltage_01',                                                # V
    'cellVoltage_02',
    'cellVoltage_03',
    'cellVoltage_04',
    'cellVoltage_05',
    'cellVoltage_06',
    'cellVoltage_07',
    'cellVoltage_08',
    'cellVoltage_09',
    'cellVoltage_10',
    'cellVoltage_11',
    'cellVoltage_12',
    'cellVoltage_13',
    'cellVoltage_14',
    'cellVoltage_15',
    'bmsTemperature',                                                # °C
    'cellTemperature_0104',
    'cellTemperature_0508',
    'cellTemperature_0912',
    'cellTemperature_1315',
    'alarmInfoRaw',                                                  # Alarm raw data
    'alarmInfo',                                                     # ok, failure, offline
    'power',                                                         # W
    'capacity',                                                      # Ah
    'capacityRemain',                                                # Ah
    'chargeManagmentInfo',                                           # bitte vollladen, SOC<9, SOC<13
    'max_Ladestrom',                                                 # A
    'max_Entladestrom',                                              # A
    'max_Ladespannung',                                              # V
    'max_Entladespannung',
    'Ladung',                                                        # erlaubt, nicht erlaubt
    'Entladung',                                                     # erlaubt, nicht erlaubt
    'Ausgleichsladung',                                              # ja, nein
    'Name_Manufacturer',
    'Name_Battery',
    'moduleSoftwareVersion_manufacture',
    'moduleSoftwareVersion_mainline',
    'softwareVersion',
    );

my $invalid     = 'unknown';                                         # default value for invalid readings
my $definterval = 30;                                                # default Abrufintervall der Batteriewerte
my $defto       = 0.5;                                               # default connection Timeout zum RS485 Gateway
my @blackl      = qw(state nextCycletime);                           # Ausnahmeliste deleteReadingspec


# Steuerhashes
###############
my %hrtnc = (                                                        # RTN Codes
  '00' => { desc => 'normal'               },                          # normal Code
  '01' => { desc => 'VER error'            },
  '02' => { desc => 'CHKSUM error'         },
  '03' => { desc => 'LCHKSUM error'        },
  '04' => { desc => 'CID2 invalidation'    },
  '05' => { desc => 'Command format error' },
  '06' => { desc => 'invalid data'         },
  '90' => { desc => 'ADR error'            },
  '91' => { desc => 'Communication error between Master and Slave Pack' },
  '99' => { desc => 'unknown error code'   },
);

##################################################################################################################################################################
# The Basic data format SOI (7EH, ASCII '~') and EOI (CR -> 0DH) are explained and transferred in hexadecimal, 
# the other items are explained in hexadecimal and transferred by hexadecimal-ASCII, each byte contains two 
# ASCII, e.g. CID2 4BH transfer 2byte: 
# 34H (the ASCII of ‘4’) and 42H(the ASCII of ‘B’).
#
# HEX-ASCII converter: https://www.rapidtables.com/convert/number/ascii-hex-bin-dec-converter.html
# Modulo Rechner: https://miniwebtool.com/de/modulo-calculator/
# Pylontech Dokus: https://github.com/Interster/PylonTechBattery
##################################################################################################################################################################
#
# request command für '1': ~20024693E00202FD2D + CR
# command (HEX):           7e 32 30 30 32 34 36 39 33 45 30 30 32 30 32, 46 44 32 44 0d
# ADR: n=Batterienummer (2-x), m=Group Nr. (0-8), ADR = 0x0n + (0x10 * m) -> f. Batterie 1 = 0x02 + (0x10 * 0) = 0x02
# CID1: Kommando spezifisch, hier 46H
# CID2: Kommando spezifisch, hier 93H
# LENGTH: LENID + LCHKSUM -> Pylon LFP V2.8 Doku
# INFO: muß hier mit ADR übereinstimmen
# CHKSUM: 32+30+30+32+34+36+39+33+45+30+30+32+30+32 = 02D3H -> modulo 65536 = 02D3H -> bitweise invert = 1111 1101 0010 1100 -> +1 = 1111 1101 0010 1101 -> FD2DH
# 
# SOI  VER    ADR   CID1  CID2      LENGTH     INFO    CHKSUM
#  ~    20    02      46    93     E0    02    02      FD   2D
# 7E  32 30  30 32  34 36 39 33  45 30 30 32  30 32  46 44 32 44
#
my %hrsnb = (                                                        # Codierung Abruf serialNumber                     
  1 => { cmd => "~20024693E00202FD2D\x{0d}" },
  2 => { cmd => "~20034693E00203FD2B\x{0d}" },
  3 => { cmd => "~20044693E00204FD29\x{0d}" },
  4 => { cmd => "~20054693E00205FD27\x{0d}" },
  5 => { cmd => "~20064693E00206FD25\x{0d}" },
  6 => { cmd => "~20074693E00207FD23\x{0d}" },
);

# request command für '1': ~20024651E00202FD33 + CR
# command (HEX):           7e 32 30 30 32 34 36 35 31 45 30 30 32 30 32 46 44 33 33 0d
# ADR: n=Batterienummer (2-x), m=Group Nr. (0-8), ADR = 0x0n + (0x10 * m) -> f. Batterie 1 = 0x02 + (0x10 * 0) = 0x02
# CID1: Kommando spezifisch, hier 46H
# CID2: Kommando spezifisch, hier 51H
# LENGTH: LENID + LCHKSUM -> Pylon LFP V2.8 Doku
# INFO: muß hier mit ADR übereinstimmen
# CHKSUM: 32+30+30+32+34+36+35+31+45+30+30+32+30+32 = 02CDH -> modulo 65536 = 02CDH -> bitweise invert = 1111 1101 0011 0010 -> +1 = 1111 1101 0011 0011 -> FD33H
# 
# SOI  VER    ADR   CID1  CID2      LENGTH    INFO     CHKSUM
#  ~    20    02      46    51     E0    02    02      FD   33
# 7E  32 30  30 32  34 36 35 31  45 30 30 32  30 32  46 44 32 44
#
my %hrmfi = (                                                        # Codierung Abruf manufacturerInfo
  1 => { cmd => "~20024651E00202FD33\x{0d}" },
  2 => { cmd => "~20034651E00203FD31\x{0d}" },
  3 => { cmd => "~20044651E00204FD2F\x{0d}" },
  4 => { cmd => "~20054651E00205FD2D\x{0d}" },
  5 => { cmd => "~20064651E00206FD2B\x{0d}" },
  6 => { cmd => "~20074651E00207FD29\x{0d}" },
);

# request command für '1': ~20024651E00202FD33 + CR
# command (HEX):           
# ADR: n=Batterienummer (2-x), m=Group Nr. (0-8), ADR = 0x0n + (0x10 * m) -> f. Batterie 1 = 0x02 + (0x10 * 0) = 0x02
# CID1: Kommando spezifisch, hier 46H
# CID2: Kommando spezifisch, hier 4FH
# LENGTH: LENID + LCHKSUM -> Pylon LFP V2.8 Doku
# INFO: muß hier mit ADR übereinstimmen
# CHKSUM: 30+30+30+33+34+36+34+46+45+30+30+32+30+33 = 02E1H -> modulo 65536 = 02E1H -> bitweise invert = 1111 1101 0001 1110 -> +1 = 1111 1101 0001 1111 -> FD1FH
# 
# SOI  VER    ADR   CID1   CID2      LENGTH    INFO     CHKSUM
#  ~    00    02      46    4F      E0    02    02      FD   21
# 7E  30 30  30 32  34 36  34 46  45 30 30 32  30 32  46 44 31 46
#
my %hrprt = (                                                        # Codierung Abruf protocolVersion
  1 => { cmd => "~0002464FE00202FD21\x{0d}" },
  2 => { cmd => "~0003464FE00203FD1F\x{0d}" },
  3 => { cmd => "~0004464FE00204FD1D\x{0d}" },
  4 => { cmd => "~0005464FE00205FD1B\x{0d}" },
  5 => { cmd => "~0006464FE00206FD19\x{0d}" },
  6 => { cmd => "~0007464FE00207FD17\x{0d}" },
);


my %hrswv = (                                                        # Codierung Abruf softwareVersion
  1 => { cmd => "~20024696E00202FD2A\x{0d}" },
  2 => { cmd => "~20034696E00203FD28\x{0d}" },
  3 => { cmd => "~20044696E00204FD26\x{0d}" },
  4 => { cmd => "~20054696E00205FD24\x{0d}" },
  5 => { cmd => "~20064696E00206FD22\x{0d}" },
  6 => { cmd => "~20074696E00207FD20\x{0d}" },
);

my %hralm = (                                                        # Codierung Abruf alarmInfo
  1 => { cmd => "~20024644E00202FD31\x{0d}" },
  2 => { cmd => "~20034644E00203FD2F\x{0d}" },
  3 => { cmd => "~20044644E00204FD2D\x{0d}" },
  4 => { cmd => "~20054644E00205FD2B\x{0d}" },
  5 => { cmd => "~20064644E00206FD29\x{0d}" },
  6 => { cmd => "~20074644E00207FD27\x{0d}" },
);

my %hrspm = (                                                        # Codierung Abruf Systemparameter
  1 => { cmd => "~20024647E00202FD2E\x{0d}" },
  2 => { cmd => "~20034647E00203FD2C\x{0d}" },
  3 => { cmd => "~20044647E00204FD2A\x{0d}" },
  4 => { cmd => "~20054647E00205FD28\x{0d}" },
  5 => { cmd => "~20064647E00206FD26\x{0d}" },
  6 => { cmd => "~20074647E00207FD24\x{0d}" },
);

my %hrcmi = (                                                        # Codierung Abruf chargeManagmentInfo
  1 => { cmd => "~20024692E00202FD2E\x{0d}" },
  2 => { cmd => "~20034692E00203FD2C\x{0d}" },
  3 => { cmd => "~20044692E00204FD2A\x{0d}" },
  4 => { cmd => "~20054692E00205FD28\x{0d}" },
  5 => { cmd => "~20064692E00206FD26\x{0d}" },
  6 => { cmd => "~20074692E00207FD24\x{0d}" },
);

my %hrcmn = (                                                        # Codierung Abruf analogValue
  1 => { cmd => "~20024642E00202FD33\x{0d}" },
  2 => { cmd => "~20034642E00203FD31\x{0d}" },
  3 => { cmd => "~20044642E00204FD2F\x{0d}" },
  4 => { cmd => "~20054642E00205FD2D\x{0d}" },
  5 => { cmd => "~20064642E00206FD2B\x{0d}" },
  6 => { cmd => "~20074642E00207FD29\x{0d}" },
);


###############################################################
#                  PylonLowVoltage Initialize
###############################################################
sub Initialize {
  my $hash = shift;

  $hash->{DefFn}    = \&Define;
  $hash->{UndefFn}  = \&Undef;
  $hash->{GetFn}    = \&Get;
  $hash->{AttrFn}   = \&Attr;
  $hash->{AttrList} = "disable:1,0 ".
                      "interval ".
                      "timeout ".
                      $readingFnAttributes;
                        
  eval { FHEM::Meta::InitMod( __FILE__, $hash ) };     ## no critic 'eval'
  
return;
}

###############################################################
#                  PylonLowVoltage Define
###############################################################
sub Define {
  my ($hash, $def) = @_;
  my @args         = split m{\s+}x, $def;

  if (int(@args) < 2) {
      return "Define: too few arguments. Usage:\n" .
              "define <name> PylonLowVoltage <host>:<port> [<bataddress>]";
  }
  
  my $name = $hash->{NAME};
  
  if ($iostAbsent) {
      my $err = "Perl module >$iostAbsent< is missing. You have to install this perl module.";
      Log3 ($name, 1, "$name - ERROR - $err");
      return "Error: $err";
  }

  $hash->{HELPER}{MODMETAABSENT} = 1 if($modMetaAbsent);                           # Modul Meta.pm nicht vorhanden
  ($hash->{HOST}, $hash->{PORT}) = split ":", $args[2];
  $hash->{BATADDRESS}             = $args[3] // 1;
  
  if ($hash->{BATADDRESS} !~ /[123456]/xs) {
      return "Define: bataddress must be a value between 1 and 6";
  }
    
  my $params = {
      hash        => $hash,
      notes       => \%vNotesIntern,
      useAPI      => 0,
      useSMUtils  => 1,
      useErrCodes => 0,
      useCTZ      => 0,
  };
  use version 0.77; our $VERSION = moduleVersion ($params);                        # Versionsinformationen setzen

  Update ($hash);

return;
}

###############################################################
#                  PylonLowVoltage Get
###############################################################
sub Get {
  my ($hash, @a) = @_;
  return qq{"get X" needs at least an argument} if(@a < 2);
  my $name = shift @a;
  my $opt  = shift @a;
  my $arg  = join " ", map { my $p = $_; $p =~ s/\s//xg; $p; } @a;     ## no critic 'Map blocks'

  my $getlist = "Unknown argument $opt, choose one of ".
                "data:noArg "
                ;

  return if(IsDisabled($name));

  if ($opt eq 'data') {
      Update ($hash);
      return;
  }

return $getlist;
}

###############################################################
#                  PylonLowVoltage Update
###############################################################
sub Attr {
  my $cmd   = shift;
  my $name  = shift;
  my $aName = shift;
  my $aVal  = shift;
  my $hash  = $defs{$name};

  my ($do,$val);

  # $cmd can be "del" or "set"
  # $name is device name
  # aName and aVal are Attribute name and value

  if ($aName eq 'disable') {
      if($cmd eq 'set') {
          $do = $aVal ? 1 : 0;
      }

      $do  = 0 if($cmd eq 'del');
      $val = ($do == 1 ? 'disabled' : 'initialized');

      readingsSingleUpdate ($hash, 'state', $val, 1);

      if ($do == 0) {
          InternalTimer(gettimeofday() + 2.0, "FHEM::PylonLowVoltage::Update", $hash, 0);
      }
  }

  if ($aName eq "interval") {
      unless ($aVal =~ /^[0-9]+$/x) {
          return qq{The value for $aName is not valid. Use only figures 0-9!};
      }

      InternalTimer(gettimeofday()+1.0, "FHEM::PylonLowVoltage::Update", $hash, 0);
  }
  
  if ($aName eq "timeout") {
      if (!looks_like_number($aVal)) {
          return qq{The value for $aName is not valid, it must be numeric!};
      }
  }

return;
}

###############################################################
#                  PylonLowVoltage Update
###############################################################
sub Update {
    my $hash = shift;
    my $name = $hash->{NAME};

    RemoveInternalTimer ($hash);

    if(!$init_done) {
        InternalTimer(gettimeofday() + 2, "FHEM::PylonLowVoltage::Update", $hash, 0);
        return;
    }

    return if(IsDisabled ($name));

    my $interval  = AttrVal ($name, 'interval', $definterval);                                 # 0 -> manuell gesteuert
    my $timeout   = AttrVal ($name, 'timeout',        $defto);
    my %readings  = ();
    my $protocol  = 'tcp';
    my $rtnerr    = q{};
    my $socket;

    if(!$interval) {
        $hash->{OPMODE}          = 'Manual';
        $readings{nextCycletime} = 'Manual';
    }
    else {
        my $new = gettimeofday() + $interval;
        InternalTimer ($new, "FHEM::PylonLowVoltage::Update", $hash, 0);                       # Wiederholungsintervall
        
        $hash->{OPMODE}          = 'Automatic';
        $readings{nextCycletime} = FmtTime($new);
    }

    Log3 ($name, 4, "$name - start request cycle to battery number >$hash->{BATADDRESS}< at host:port $hash->{HOST}:$hash->{PORT}");

    eval {
        local $SIG{ALRM} = sub { die 'gatewaytimeout' };
        ualarm ($timeout * 1000000);                                                           # ualarm in Mikrosekunden

        $socket = IO::Socket::INET->new( Proto    => $protocol, 
                                         PeerAddr => $hash->{HOST}, 
                                         PeerPort => $hash->{PORT}, 
                                         Timeout  => $timeout
                                       );
                                          
        if (!$socket) {
            doOnError ({ hash     => $hash, 
                         readings => \%readings, 
                         state    => 'no socket is established to RS485 gateway'
                       }
                      );           
            return;        
        }

        if (!$socket->connected()) {
            doOnError ({ hash     => $hash, 
                         readings => \%readings,
                         sock     => $socket,                         
                         state    => 'disconnected'
                       }
                      );            
            return;
        }

        IO::Socket::Timeout->enable_timeouts_on ($socket);                       # nur notwendig für read or write timeout
        $socket->read_timeout ($timeout - 0.2);                                  # Lesetimeout immer kleiner als Sockettimeout
        $socket->autoflush(1);

        my $res;

        # relativ statische Werte abrufen
        ###################################
        if (ReadingsAge ($name, "serialNumber", 601) >= 0) {
            # Abruf serialNumber
            #####################
            $res = Request($hash, $socket, $hrsnb{$hash->{BATADDRESS}}{cmd}, 'serialNumber');
            
            $rtnerr = respStat ($res);
            if ($rtnerr) {
                doOnError ({ hash     => $hash, 
                             readings => \%readings,
                             sock     => $socket,                             
                             state    => $rtnerr
                           }
                          );                
                return;
            }

            my $sernum              = substr ($res, 15, 32);
            $readings{serialNumber} = pack   ("H*", $sernum);
            
            # Abruf manufacturerInfo
            #########################
            $res = Request($hash, $socket, $hrmfi{$hash->{BATADDRESS}}{cmd}, 'manufacturerInfo');
            
            $rtnerr = respStat ($res);
            if ($rtnerr) {
                doOnError ({ hash     => $hash, 
                             readings => \%readings, 
                             sock     => $socket,
                             state    => $rtnerr
                           }
                          );                  
                return;
            }

            my $BatteryHex             = substr ($res, 13, 20);                       
            $readings{batteryType}     = pack   ("H*", $BatteryHex);
            $readings{softwareVersion} = 'V'.hex (substr ($res, 33, 2)).'.'.hex (substr ($res, 35, 2));      # substr ($res, 33, 4);
            my $ManufacturerHex        = substr ($res, 37, 40);
            $readings{Manufacturer}    = pack   ("H*", $ManufacturerHex);
            
            # Abruf protocolVersion
            ########################                
            $res = Request($hash, $socket, $hrprt{$hash->{BATADDRESS}}{cmd}, 'protocolVersion');
            
            $rtnerr = respStat ($res);
            if ($rtnerr) {
                doOnError ({ hash     => $hash, 
                             readings => \%readings,
                             sock     => $socket,                             
                             state    => $rtnerr
                           }
                          );  
                return;
            }
    
            $readings{protocolVersion} = 'V'.hex (substr ($res, 1, 1)).'.'.hex (substr ($res, 2, 1));
            
            # Abruf softwareVersion
            ########################
            $res = Request($hash, $socket, $hrswv{$hash->{BATADDRESS}}{cmd}, 'softwareVersion');
            
            $rtnerr = respStat ($res);
            if ($rtnerr) {
                doOnError ({ hash     => $hash, 
                             readings => \%readings,
                             sock     => $socket,                             
                             state    => $rtnerr
                           }
                          );                  
                return;
            }

            $readings{moduleSoftwareVersion_manufacture} = 'V'.hex (substr ($res, 15, 2)).'.'.hex (substr ($res, 17, 2)); 
            $readings{moduleSoftwareVersion_mainline}    = 'V'.hex (substr ($res, 19, 2)).'.'.hex (substr ($res, 21, 2)).'.'.hex (substr ($res, 23, 2));

            # Abruf alarmInfo
            ##################
            $res = Request($hash, $socket, $hralm{$hash->{BATADDRESS}}{cmd}, 'alarmInfo');
            
            $rtnerr = respStat ($res);
            if ($rtnerr) {
                doOnError ({ hash     => $hash, 
                             readings => \%readings,
                             sock     => $socket,                             
                             state    => $rtnerr
                           }
                          );                  
                return;
            }
            
            $readings{packCellcount} = hex (substr($res, 17, 2));

            if (substr($res, 19, 30)=="000000000000000000000000000000" && 
                substr($res, 51, 10)=="0000000000"                     && 
                substr($res, 67, 2) =="00"                             && 
                substr($res, 73, 4) =="0000") {
                $readings{packAlarmInfo} = "ok";
            }
            else {
                $readings{packAlarmInfo} = "failure";
            }

            # Abruf Systemparameter
            ########################
            $res = Request($hash, $socket, $hrspm{$hash->{BATADDRESS}}{cmd}, 'systemParameters');

            $rtnerr = respStat ($res);
            if ($rtnerr) {
                doOnError ({ hash     => $hash, 
                             readings => \%readings,
                             sock     => $socket,                             
                             state    => $rtnerr
                           }
                          );                  
                return;
            }
            
            $readings{paramCellHighVoltLimit}      = sprintf "%.3f", (hex substr  ($res, 15, 4)) / 1000;
            $readings{paramCellLowVoltLimit}       = sprintf "%.3f", (hex substr  ($res, 19, 4)) / 1000;                   # Alarm Limit
            $readings{paramCellUnderVoltLimit}     = sprintf "%.3f", (hex substr  ($res, 23, 4)) / 1000;                   # Schutz Limit
            $readings{paramChargeHighTempLimit}    = sprintf "%.1f", ((hex substr ($res, 27, 4)) - 2731) / 10; 
            $readings{paramChargeLowTempLimit}     = sprintf "%.1f", ((hex substr ($res, 31, 4)) - 2731) / 10; 
            $readings{paramChargeCurrentLimit}     = sprintf "%.3f", (hex substr  ($res, 35, 4)) * 100 / 1000; 
            $readings{paramModuleHighVoltLimit}    = sprintf "%.3f", (hex substr  ($res, 39, 4)) / 1000;
            $readings{paramModuleLowVoltLimit}     = sprintf "%.3f", (hex substr  ($res, 43, 4)) / 1000;                   # Alarm Limit
            $readings{paramModuleUnderVoltLimit}   = sprintf "%.3f", (hex substr  ($res, 47, 4)) / 1000;                   # Schutz Limit
            $readings{paramDischargeHighTempLimit} = sprintf "%.1f", ((hex substr ($res, 51, 4)) - 2731) / 10;
            $readings{paramDischargeLowTempLimit}  = sprintf "%.1f", ((hex substr ($res, 55, 4)) - 2731) / 10;
            $readings{paramDischargeCurrentLimit}  = sprintf "%.3f", (65535 - (hex substr  ($res, 59, 4))) * 100 / 1000;   # mit Symbol (-)
        }
        
        # Abruf chargeManagmentInfo
        ############################
        $res = Request($hash, $socket, $hrcmi{$hash->{BATADDRESS}}{cmd}, 'chargeManagmentInfo');
        
        $rtnerr = respStat ($res);
        if ($rtnerr) {
            doOnError ({ hash     => $hash, 
                         readings => \%readings,
                         sock     => $socket,                             
                         state    => $rtnerr
                       }
                      );                 
            return;
        }

        $readings{chargeVoltageLimit}    = sprintf "%.3f", hex (substr ($res, 15, 4)) / 1000;        # Genauigkeit 3
        $readings{dischargeVoltageLimit} = sprintf "%.3f", hex (substr ($res, 19, 4)) / 1000;        # Genauigkeit 3
        $readings{chargeCurrentLimit}    = sprintf "%.1f", hex (substr ($res, 23, 4)) / 10;          # Genauigkeit 1
        $readings{dischargeCurrentLimit} = sprintf "%.1f", (65536 - hex substr ($res, 27, 4)) / 10;  # Genauigkeit 1, Fixed point, unsigned integer

        my $cdstat                        = sprintf "%08b", hex substr ($res, 31, 2);                # Rohstatus
        $readings{chargeEnable}           = substr ($cdstat, 0, 1) == 1 ? 'yes' : 'no';              # Bit 7
        $readings{dischargeEnable}        = substr ($cdstat, 1, 1) == 1 ? 'yes' : 'no';              # Bit 6
        $readings{chargeImmediatelySOC5}  = substr ($cdstat, 2, 1) == 1 ? 'yes' : 'no';              # Bit 5 - SOC 5~9%  -> für Wechselrichter, die aktives Batteriemanagement bei gegebener DC-Spannungsfunktion haben oder Wechselrichter, der von sich aus einen niedrigen SOC/Spannungsgrenzwert hat
        $readings{chargeImmediatelySOC10} = substr ($cdstat, 3, 1) == 1 ? 'yes' : 'no';              # Bit 4 - SOC 9~13% -> für Wechselrichter hat keine aktive Batterieabschaltung haben
        $readings{chargeFullRequest}      = substr ($cdstat, 4, 1) == 1 ? 'yes' : 'no';              # Bit 3 - wenn SOC in 30 Tagen nie höher als 97% -> Flag = 1, wenn SOC-Wert ≥ 97% -> Flag = 0

        # Abruf analogValue
        ####################
        # Answer from US2000 = 128 Bytes, from US3000 = 140 Bytes
        # Remain capacity US2000 hex(substr($res,109,4), US3000 hex(substr($res,123,6)
        # Module capacity US2000 hex(substr($res,115,4), US3000 hex(substr($res,129,6)
        ###############################################################################
        $res = Request($hash, $socket, $hrcmn{$hash->{BATADDRESS}}{cmd}, 'analogValue');

        $rtnerr = respStat ($res);
        if ($rtnerr) {
            doOnError ({ hash     => $hash, 
                         readings => \%readings,
                         sock     => $socket,                             
                         state    => $rtnerr
                       }
                      );                
            return;
        }     

        $readings{packCellcount}   = hex (substr($res, 17,  2));
        $readings{packVolt}        = hex (substr($res, 105, 4)) / 1000;
        my $current                = hex (substr($res, 101, 4));
        
        if ($current & 0x8000) {
            $current = $current - 0x10000;
        }

        $readings{packCurrent} = sprintf "%.2f", $current / 10;

        if (length($res) == 128) {
            $readings{packCapacity}       = hex (substr($res, 115, 4)) / 1000;
            $readings{packCapacityRemain} = hex (substr($res, 109, 4)) / 1000;
        }
        else {
            $readings{packCapacity}       = hex (substr($res, 129, 6)) / 1000;
            $readings{packCapacityRemain} = hex (substr($res, 123, 6)) / 1000;
        }
        
        $readings{cellVoltage_01}       = sprintf "%.3f", hex(substr($res,19,4)) / 1000;
        $readings{cellVoltage_02}       = sprintf "%.3f", hex(substr($res,23,4)) / 1000;
        $readings{cellVoltage_03}       = sprintf "%.3f", hex(substr($res,27,4)) / 1000;
        $readings{cellVoltage_04}       = sprintf "%.3f", hex(substr($res,31,4)) / 1000;
        $readings{cellVoltage_05}       = sprintf "%.3f", hex(substr($res,35,4)) / 1000;
        $readings{cellVoltage_06}       = sprintf "%.3f", hex(substr($res,39,4)) / 1000;
        $readings{cellVoltage_07}       = sprintf "%.3f", hex(substr($res,43,4)) / 1000;
        $readings{cellVoltage_08}       = sprintf "%.3f", hex(substr($res,47,4)) / 1000;
        $readings{cellVoltage_09}       = sprintf "%.3f", hex(substr($res,51,4)) / 1000;
        $readings{cellVoltage_10}       = sprintf "%.3f", hex(substr($res,55,4)) / 1000;
        $readings{cellVoltage_11}       = sprintf "%.3f", hex(substr($res,59,4)) / 1000;
        $readings{cellVoltage_12}       = sprintf "%.3f", hex(substr($res,63,4)) / 1000;
        $readings{cellVoltage_13}       = sprintf "%.3f", hex(substr($res,67,4)) / 1000;
        $readings{cellVoltage_14}       = sprintf "%.3f", hex(substr($res,71,4)) / 1000;
        $readings{cellVoltage_15}       = sprintf "%.3f", hex(substr($res,75,4)) / 1000;
        $readings{packCycles}           = hex  (substr($res, 119, 4));
        $readings{bmsTemperature}       = (hex (substr($res, 81,  4)) - 2731) / 10;
        $readings{cellTemperature_0104} = (hex (substr($res, 85,  4)) - 2731) / 10;
        $readings{cellTemperature_0508} = (hex (substr($res, 89,  4)) - 2731) / 10;
        $readings{cellTemperature_0912} = (hex (substr($res, 93,  4)) - 2731) / 10;
        $readings{cellTemperature_1315} = (hex (substr($res, 97,  4)) - 2731) / 10;
    };  # eval
    
    if ($@) {
        my $errtxt;
        if ($@ =~ /gatewaytimeout/xs) {
            $errtxt = 'Timeout in communication to RS485 gateway';                         
        }
        else {
            $errtxt = $@; 
        }        
        
        doOnError ({ hash     => $hash, 
                     readings => \%readings, 
                     sock     => $socket,
                     state    => $errtxt
                   }
                  );          
        return;
    }

    ualarm(0);
    close ($socket) if($socket);
    
    Log3 ($name, 4, "$name - got fresh values from battery number >$hash->{BATADDRESS}<");
    
    additionalReadings (\%readings);                                                 # zusätzliche eigene Readings erstellen
    
    $readings{state} = 'connected' if(!defined $readings{state});

    createReadings ($hash, \%readings);                                              # Readings erstellen

return;
}

###############################################################
#                  PylonLowVoltage Request
###############################################################
sub Request {
    my $hash   = shift;
    my $socket = shift;
    my $cmd    = shift;
    my $cmdtxt = shift // 'unspecified data';
    
    my $name = $hash->{NAME};
    
    Log3 ($name, 4, "$name - retrieve battery info: ".$cmdtxt);
    Log3 ($name, 4, "$name - request command (ASCII): ".$cmd);
    Log3 ($name, 5, "$name - request command (HEX): ".unpack "H*", $cmd);  

    printf $socket $cmd;

return Reread ($hash, $socket);
}

###############################################################
#    RS485 Daten lesen/empfagen
###############################################################
sub Reread {
    my $hash   = shift;
    my $socket = shift;

    my $singlechar;
    my $name = $hash->{NAME};
    my $res  = q{};

    do {
        $socket->read ($singlechar, 1);

        if (!$singlechar && (0+$! == ETIMEDOUT || 0+$! == EWOULDBLOCK)) {                # nur notwendig für read timeout
            die 'Timeout reading data from battery';
        }

        $res = $res . $singlechar if (!(length($res) == 0 && ord($singlechar) == 13))    # ord 13 -> ASCII dezimal für CR (Hex 0d)

    } while (length($res) == 0 || ord($singlechar) != 13);

    Log3 ($name, 5, "$name - data returned raw: ".$res);
    Log3 ($name, 5, "$name - data returned:\n"   .Hexdump($res));

return $res;
}

###############################################################
#                  PylonLowVoltage Undef
###############################################################
sub Undef {
  my ($hash, $args) = @_;
  RemoveInternalTimer ($hash);

return;
}

###############################################################
#                  PylonLowVoltage Hexdump
###############################################################
sub Hexdump {
  my $offset = 0;
  my $result = "";

  for my $chunk (unpack "(a16)*", $_[0]) {
      my $hex  = unpack "H*", $chunk;                                                       # hexadecimal magic
      $chunk   =~ tr/ -~/./c;                                                               # replace unprintables
      $hex     =~ s/(.{1,8})/$1 /gs;                                                        # insert spaces
      $result .= sprintf "0x%08x (%05u)  %-*s %s\n", $offset, $offset, 36, $hex, $chunk;
      $offset += 16;
  }

return $result;
}

###############################################################
#       Response Status ermitteln
###############################################################
sub respStat {               
  my $res  = shift;

  my $rst    = substr($res,7,2);
  my $rtnerr = $hrtnc{99}{desc}.": $rst";
    
  if(defined $hrtnc{$rst}{desc}) {
      $rtnerr = $hrtnc{$rst}{desc};
      return if($rtnerr eq 'normal');
  }
    
return $rtnerr;
}

###############################################################
#       Fehlerausstieg
###############################################################
sub doOnError {           
  my $paref = shift;

  my $hash     = $paref->{hash};
  my $readings = $paref->{readings};     # Referenz auf das Hash der zu erstellenden Readings
  my $state    = $paref->{state};
  my $socket   = $paref->{sock};
  
  ualarm(0);
  close ($socket) if($socket);

  my $name           = $hash->{NAME};
  $state             = (split "at ", $state)[0];
  $readings->{state} = $state;
    
  Log3 ($name, 3, "$name - ".$readings->{state});
    
  deleteReadingspec ($hash);
  createReadings    ($hash, $readings);                
    
return;
}

###############################################################
#       eigene zusaätzliche Werte erstellen
###############################################################
sub additionalReadings {               
    my $readings = shift;                # Referenz auf das Hash der zu erstellenden Readings

    my ($vmax, $vmin);
    
    $readings->{averageCellVolt} = sprintf "%.3f", $readings->{packVolt} / $readings->{packCellcount};
    $readings->{packSOC}         = sprintf "%.2f", ($readings->{packCapacityRemain} / $readings->{packCapacity} * 100);
    $readings->{packPower}       = sprintf "%.2f", $readings->{packCurrent} * $readings->{packVolt};
    
    for (my $i=1; $i <= $readings->{packCellcount}; $i++) {
        $i    = sprintf "%02d", $i;
        $vmax = $readings->{'cellVoltage_'.$i} if(!$vmax || $vmax < $readings->{'cellVoltage_'.$i});
        $vmin = $readings->{'cellVoltage_'.$i} if(!$vmin || $vmin > $readings->{'cellVoltage_'.$i});
    }
    
    if ($vmax && $vmin) {
        my $maxdf = $vmax - $vmin;
        $readings->{packImbalance} = sprintf "%.3f", 100 * $maxdf / $readings->{averageCellVolt};
    }
    
    $readings->{packState} = $readings->{packCurrent} < 0 ? 'discharging' :
                             $readings->{packCurrent} > 0 ? 'charging'    :
                             'idle';
    
return;
}

###############################################################
#       Readings erstellen
###############################################################
sub createReadings {               
    my $hash     = shift;
    my $readings = shift;                # Referenz auf das Hash der zu erstellenden Readings

    readingsBeginUpdate ($hash);
    
    for my $spec (keys %{$readings}) {
        next if(!defined $readings->{$spec});
        readingsBulkUpdate ($hash, $spec, $readings->{$spec});
    }

    readingsEndUpdate  ($hash, 1);
    
return;
}

################################################################
#    alle Readings eines Devices oder nur Reading-Regex
#    löschen
#    Readings der Blacklist werden nicht gelöscht
################################################################
sub deleteReadingspec {
  my $hash = shift;
  my $spec = shift // ".*";

  my $readingspec = '^'.$spec.'$';

  for my $reading ( grep { /$readingspec/x } keys %{$hash->{READINGS}} ) {
      next if($reading ~~ @blackl);
      readingsDelete ($hash, $reading);
  }

return;
}

1;


=pod
=item device
=item summary Integration of pylontech LiFePo4 low voltage batteries (incl. BMS) over RS485 via ethernet gateway (ethernet interface)
=item summary_DE Integration von Pylontech Niedervolt Batterien (mit BMS) über RS485 via Ethernet-Gateway (Ethernet Interface)

=begin html

<a id="PylonLowVoltage"></a>
<h3>PylonLowVoltage</h3>
<br>
Module for the integration of batteries with battery management system (BMS) from manufacturer Pylontech via RS485 via RS485 / Ethernet gateway.<br>
The test was carried out with a US2000plus Pylontech battery, which was connected via a USRiot "USR-TCP" low-cost Ethernet gateway.<br>
In principle, any other RS485 / Ethernet gateway should also be possible here.<br>
The module thus only communicates via an Ethernet connection.<br>
<br><br>

<b>Requirements</b>
<br><br>
This module requires the Perl modules:
<ul>
    <li>IO::Socket::INET   (apt-get install libio-socket-multicast-perl)</li>
    <li>IO::Socket::Timeout   (Installation e.g. via the CPAN shell)    </li>
</ul>
<br>
<br>

<a id="PylonLowVoltage-define"></a>
<b>Definition</b>
<ul>
  <code><b>define &lt;name&gt; PylonLowVoltage &lt;bataddress&gt; &lt;hostname/ip&gt; &lt;port&gt; [&lt;timeout&gt;]</b></code><br>
  <br>
  <li><b>bataddress:</b><br>
  Device address of the Pylontech battery. Up to 6 pylon tech batteries can be connected via a Pylontech specific link link.<br>
  The first battery in the network (to which the RS485 cable is connected) has the address 1, the next battery has the address 2 and so on.<br>
  The individual batteries can thus be addressed individually.</li>
  <li><b>hostname/ip:</b><br>
  Host name oder IP address of the RS485/Ethernet gateways</li>
  <li><b>port:</b><br>
  Port number of the port configured in the RS485 / Ethernet Gateway</li>
  <li><b>timeout:</b><br>
  Timeout in seconds for a query (optional, default 10)<br></li>
</ul>

<b>Working method</b>
<ul>
The module cyclically reads values that the battery management system provides via the RS485 interface.<br>
All data is read out at the interval specified in the definition.
</ul>

<a id="PylonLowVoltage-get"></a>
<b>Get</b>
<br>
<ul>
  <li><b>data</b><br>
    The data query of the battery management system is executed. The timer of the cyclic query is reinitialized according
    to the set value of the "interval" attribute.
    <br>
  </li>
<br>
</ul>

<a id="PylonLowVoltage-attr"></a>
<b>Attributes</b>
<br<br>
<ul>
   <a id="PylonLowVoltage-attr-disable"></a>
   <li><b>disable 0|1</b><br>
     Activates/deactivates the device.
   </li>
   <br>

   <a id="PylonLowVoltage-attr-interval"></a>
   <li><b>interval &lt;seconds&gt;</b><br>
     Interval of data retrieval from the battery in seconds. If "interval" is explicitly set to the value "0", there is no
     automatic data query. <br>
     (default: 30)
   </li>
   <br>
</ul>

<a id="PylonLowVoltage-readings"></a>
<b>Readings</b>
<ul>
<li><b>serialNumber</b><br>Serial number (is read only once a minute)<br></li>
<li><b>batteryVoltage</b><br>Battery voltage of the entire battery [in V]<br></li>
<li><b>averageCellVoltage</b><br>Mean cell voltage [in V]<br></li>
<li><b>batteryCurrent</b><br>Battery current [in A]<br></li>
<li><b>SOC</b><br>State of charge [in%]<br></li>
<li><b>cycles</b><br>Number of Cycles - The number of cycles is a measure of battery wear.
A complete load and unload is considered a cycle. If the battery is discharged and recharged 50%, it will only count as half a cycle.
The manufacturer specifies a lifetime of several 1000 cycles (see data sheet).<br></li>
<li><b>cellVoltage_1</b><br>Cell voltage of the 1st cell pack [in V] - In the battery 15 cell packs
are connected in series. Each cell pack consists of parallel cells.<br></li>
<li><b>cellVoltage_2</b><br>Cell voltage of the 2nd cell pack [in V]<br>
<b>.</b><br>
<b>.</b><br>
<b>.</b><br>
</li>
<li><b>cellVoltage_15</b><br>Cell voltage of the 15th cell pack [in V]<br></li>
<li><b>bmsTemperature</b><br>Temperature of the battery management system (BMS) [in ° C]<br></li>
<li><b>cellTemperature_0104</b><br>Temperature of cell packs 1 to 4 [in ° C]<br></li>
<li><b>cellTemperature_0508</b><br>Temperature of cell packs 5 to 8 [in ° C]<br></li>
<li><b>cellTemperature_0912</b><br>Temperature of cell packs 9 to 12 [in ° C]<br></li>
<li><b>cellTemperature_1315</b><br>Temperature of cell packs 13 to 15 [in ° C]<br></li>
<li><b>alarmInfo</b><br>Alarm status [ok - battery module is OK, failure - there is a fault in the battery module]<br>(is read only once a minute)<br></li>
<li><b>alarmInfoRaw</b><br>Alarm raw data for more detailed analysis<br>(is read only once a minute)<br></li>
<li><b>state</b><br>Status [ok, failure, offline]<br></li>
</ul>
<br><br>

=end html
=begin html_DE

<a id="PylonLowVoltage"></a>
<h3>PylonLowVoltage</h3>
<br>
Modul zur Einbindung von Batterien mit Batteriemanagmentsystem (BMS) des Herstellers Pylontech über RS485 via 
RS485/Ethernet-Gateway. Die Kommunikation zum RS485-Gateway erfolgt ausschließlich über eine Ethernet-Verbindung.<br>
Das Modul wurde bisher erfolgreich mit Pylontech Batterien folgender Typen eingesetzt: <br>

<ul>
 <li> US2000 </li>
 <li> US2000plus </li>
 <li> US3000 </li>
 <li> US3000C </li>
</ul>
 <br>

Als RS485-Ethernet-Gateways wurden bisher folgende Geräte eingesetzt: <br>
<ul>
 <li> USR-TCP232-304 des Herstellers USRiot </li>
 <li> Waveshare RS485 to Ethernet Converter </li>
</ul>
<br>
 
Prinzipiell sollte hier auch jedes andere RS485/Ethernet-Gateway möglich sein.
<br><br>

<b>Voraussetzungen</b>
<br><br>
Dieses Modul benötigt die Perl-Module:
<ul>
    <li>IO::Socket::INET    (apt-get install libio-socket-multicast-perl)</li>
    <li>IO::Socket::Timeout (Installation z.B. über die CPAN-Shell)      </li>
</ul>
<br>

<a id="PylonLowVoltage-define"></a>
<b>Definition</b>
<ul>
  <code><b>define &lt;name&gt; PylonLowVoltage &lt;hostname/ip&gt;:&lt;port&gt; [&lt;bataddress&gt;]</b></code><br>
  <br>
  <li><b>hostname/ip:</b><br>
     Hostname oder IP-Adresse des RS485/Ethernet-Gateways
  </li>

  <li><b>port:</b><br>
     Port-Nummer des im RS485/Ethernet-Gateways konfigurierten Ports
  </li>
  
  <li><b>bataddress:</b><br>
     Geräteadresse der Pylontech Batterie. Es können bis zu 6 Pylontech Batterien über eine Pylontech-spezifische
     Link-Verbindung verbunden werden.<br>
     Die erste Batterie im Verbund (an der die RS485-Verbindung angeschlossen ist) hat die Adresse 1, die nächste Batterie
     hat dann die Adresse 2 und so weiter.<br>
     Ist keine Geräteadresse angegeben, wird die Adresse 1 verwendet.
  </li>
  <br>
</ul>

<b>Arbeitsweise</b>
<ul>
Das Modul liest zyklisch Werte aus, die das Batteriemanagementsystem über die RS485-Schnittstelle zur Verfügung stellt.<br>
Alle Daten werden mit dem bei der Definition angegebene Intervall ausgelesen.
</ul>

<a id="PylonLowVoltage-get"></a>
<b>Get</b>
<br>
<ul>
  <li><b>data</b><br>
    Die Datenabfrage des Batteriemanagementsystems wird ausgeführt. Der Zeitgeber der zyklischen Abfrage wird entsprechend
    dem gesetzten Wert des Attributes "interval" neu initialisiert.
    <br>
  </li>
<br>
</ul>

<a id="PylonLowVoltage-attr"></a>
<b>Attribute</b>
<br<br>
<ul>
   <a id="PylonLowVoltage-attr-disable"></a>
   <li><b>disable 0|1</b><br>
     Aktiviert/deaktiviert das Gerät.
   </li>
   <br>

   <a id="PylonLowVoltage-attr-interval"></a>
   <li><b>interval &lt;Sekunden&gt;</b><br>
     Intervall der Datenabfrage von der Batterie in Sekunden. Ist "interval" explizit auf den Wert "0" gesetzt, erfolgt
     keine automatische Datenabfrage.<br>
     (default: 30)
   </li>
   <br>
   
   <a id="PylonLowVoltage-attr-timeout"></a>
   <li><b>timeout &lt;Sekunden&gt;</b><br>
     Timeout für den Verbindungsaufbau zum RS485 Gateway. <br>
     (default: 0.5)
   </li>
   <br>
</ul>

<a id="PylonLowVoltage-readings"></a>
<b>Readings</b>
<ul>
<li><b>serialNumber</b><br>Seriennummer<br>                                         </li>
<li><b>batteryVoltage</b><br>Batterie Spannung (V) der gesamten Batterie<br>        </li>
<li><b>averageCellVoltage</b><br>mittlere Zellenspannung (V) <br>                   </li>
<li><b>batteryCurrent</b><br>Batteriestrom (A)<br>                                  </li>
<li><b>SOC</b><br>Ladezustand (%)<br>                                               </li>
<li><b>cycles</b><br>Anzahl der Zyklen - Die Anzahl der Zyklen ist in gewisserweise ein Maß für den Verschleiß der Batterie.
                     Eine komplettes Laden und Entladen wird als ein Zyklus gewertet.
                     Wird die Batterie 50% Entladen und wieder aufgeladen, zählt das nur als ein halber Zyklus.
                     Der Hersteller gibt eine Lebensdauer von mehreren 1000 Zyklen an (siehe Datenblatt).<br>                </li>
<li><b>cellVoltage_1</b><br>Zellenspannung (V) des 1. Zellenpacks - In der Batterie sind 15 Zellenpacks in Serie geschaltet.
                            Jedes Zellenpack besteht aus parallel geschalten Einzelzellen.<br>                               </li>
<li><b>cellVoltage_2</b><br>Zellenspannung (V) des 2. Zellenpacks<br>
                        <b>.</b><br>
                        <b>.</b><br>
                        <b>.</b><br>
                        </li>
<li><b>cellVoltage_15</b><br>Zellenspannung (V) des 15. Zellenpacks<br>                            </li>
<li><b>bmsTemperature</b><br>Temperatur (°C) des Batteriemanagementsystems<br>                     </li>
<li><b>cellTemperature_0104</b><br>Temperatur (°C) der Zellenpacks 1 bis 4<br>                     </li>
<li><b>cellTemperature_0508</b><br>Temperatur (°C) der Zellenpacks 5 bis 8<br>                     </li>
<li><b>cellTemperature_0912</b><br>Temperatur (°C) der Zellenpacks 9 bis 12<br>                    </li>
<li><b>cellTemperature_1315</b><br>Temperatur (°C) der Zellenpacks 13 bis 15<br>                   </li>
<li><b>alarmInfo</b><br>Alarmstatus (ok - Batterienmodul ist in Ordnung, failure - im Batteriemodul liegt eine Störung vor)<br></li>                                                                                                               </li>
</ul>
<br><br>

=end html_DE

=for :application/json;q=META.json 70_PylonLowVoltage.pm
{
  "abstract": "Integration of pylontech LiFePo4 low voltage batteries (incl. BMS) over RS485 via ethernet gateway (ethernet interface)",
  "x_lang": {
    "de": {
      "abstract": "Integration von Pylontech Niedervolt Batterien (mit BMS) &uumlber RS485 via Ethernet-Gateway (Ethernet Interface)"
    }
  },
  "keywords": [
    "inverter",
    "photovoltaik",
    "electricity",
    "battery",
    "Pylontech",
    "BMS",
    "ESS",
    "PV"
  ],
  "version": "v1.1.1",
  "release_status": "stable",
  "author": [
    "Heiko Maaz <heiko.maaz@t-online.de>"
  ],
  "x_fhem_maintainer": [
    "DS_Starter"
  ],
  "x_fhem_maintainer_github": [
    "nasseeder1"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918799,
        "perl": 5.014,
        "GPUtils": 0,
        "IO::Socket::INET": 0,
        "IO::Socket::Timeout": 0,
        "Errno": 0,
        "FHEM::SynoModules::SMUtils": 1.0220,
        "Time::HiRes": 0,
        "Scalar::Util": 0
      },
      "recommends": {
        "FHEM::Meta": 0
      },
      "suggests": {
      }
    }
  },
  "resources": {
    "x_wiki": {
      "web": "",
      "title": ""
    },
    "repository": {
      "x_dev": {
        "type": "svn",
        "url": "https://svn.fhem.de/trac/browser/trunk/fhem/contrib/DS_Starter",
        "web": "https://svn.fhem.de/trac/browser/trunk/fhem/contrib/DS_Starter/70_PylonLowVoltage.pm",
        "x_branch": "dev",
        "x_filepath": "fhem/contrib/",
        "x_raw": "https://svn.fhem.de/fhem/trunk/fhem/contrib/DS_Starter/70_PylonLowVoltage.pm"
      }
    }
  }
}
=end :application/json;q=META.json

=cut