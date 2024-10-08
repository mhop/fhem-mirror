#########################################################################################################################
# $Id$
#########################################################################################################################
#
# 70_PylonLowVoltage.pm
#
# A FHEM module to read BMS values from Pylontech Low Voltage LiFePo04 batteries.
#
# This module uses the idea and informations from 70_Pylontech.pm written 2019 by Harald Schmitz.
# Further code development and extensions by Heiko Maaz (c) 2023 e-mail: Heiko dot Maaz at t-online dot de
#
# Credits to FHEM user: satprofi, Audi_Coupe_S, abc2006
#
#########################################################################################################################
# Copyright notice
#
# (c) 2019 Harald Schmitz (70_Pylontech.pm)
# (c) 2023 - 2024 Heiko Maaz
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
# Forumlinks:
# https://forum.fhem.de/index.php?topic=117466.0  (Source of module 70_Pylontech.pm)
# https://forum.fhem.de/index.php?topic=126361.0
# https://forum.fhem.de/index.php?topic=112947.0
# https://forum.fhem.de/index.php?topic=32037.0
#
# Photovoltaik Forum:
# https://www.photovoltaikforum.com/thread/130061-pylontech-us2000b-daten-protokolle-programme
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
use Time::HiRes qw(gettimeofday ualarm sleep);
use IO::Socket::INET;
use Errno qw(ETIMEDOUT EWOULDBLOCK);
use Scalar::Util qw(looks_like_number);
use Carp qw(croak carp);
use Blocking;
use MIME::Base64;

eval "use FHEM::Meta;1"                or my $modMetaAbsent = 1;                             ## no critic 'eval'
eval "use IO::Socket::Timeout;1"       or my $iostabs       = 'IO::Socket::Timeout';         ## no critic 'eval'
eval "use Storable qw(freeze thaw);1;" or my $storabs       = 'Storable';                    ## no critic 'eval'

use FHEM::SynoModules::SMUtils qw(moduleVersion);                                            # Hilfsroutinen Modul
# use Data::Dumper;

# Run before module compilation
BEGIN {
  # Import from main::
  GP_Import(
      qw(
          AttrVal
          AttrNum
          BlockingCall
          BlockingKill
          devspec2array
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
  "1.2.0"  => "05.10.2024 _composeAddr: bugfix of effective battaery addressing ",
  "1.1.0"  => "25.08.2024 manage time shift for active gateway connections of all defined  devices ",
  "1.0.0"  => "24.08.2024 implement pylon groups ",
  "0.4.0"  => "23.08.2024 Log output for timeout changed, automatic calculation of checksum, preparation for pylon groups ",
  "0.3.0"  => "22.08.2024 extend battery addresses up to 16 ",
  "0.2.6"  => "25.05.2024 replace Smartmatch Forum:#137776 ",
  "0.2.5"  => "02.04.2024 _callAnalogValue / _callAlarmInfo: integrate a Cell and Temperature Position counter ".
                          "add specific Alarm readings ",
  "0.2.4"  => "29.03.2024 avoid possible Illegal division by zero at line 1438 ",
  "0.2.3"  => "19.03.2024 edit commandref ",
  "0.2.2"  => "20.02.2024 correct commandref ",
  "0.2.1"  => "18.02.2024 doOnError: print out faulty response, Forum:https://forum.fhem.de/index.php?msg=1303912 ",
  "0.2.0"  => "15.12.2023 extend possible number of batteries up to 14 ",
  "0.1.11" => "28.10.2023 add needed data format to commandref ",
  "0.1.10" => "18.10.2023 new function pseudoHexToText in _callManufacturerInfo for translate battery name and Manufactorer ",
  "0.1.9"  => "25.09.2023 fix possible bat adresses ",
  "0.1.8"  => "23.09.2023 new Attr userBatterytype, change manufacturerInfo, protocolVersion command hash to LENID=0 ",
  "0.1.7"  => "20.09.2023 extend possible number of bats from 6 to 8 ",
  "0.1.6"  => "19.09.2023 rework of _callAnalogValue, support of more than 15 cells ",
  "0.1.5"  => "19.09.2023 internal code change ",
  "0.1.4"  => "24.08.2023 Serialize and deserialize data for update entry, usage of BlockingCall in case of long timeout ",
  "0.1.3"  => "22.08.2023 improve responseCheck and others ",
  "0.1.2"  => "20.08.2023 commandref revised, analogValue -> use 'user defined items', refactoring according PBP ",
  "0.1.1"  => "16.08.2023 integrate US3000C, add print request command in HEX to Logfile, attr timeout ".
                          "change validation of received data, change DEF format, extend evaluation of chargeManagmentInfo ".
                          "add evaluate systemParameters, additional own values packImbalance, packState ",
  "0.1.0"  => "12.08.2023 initial version, switch to perl package, attributes: disable, interval, add command hashes ".
                          "get ... data command, add meta support and version management, more code changes ",
);

## Konstanten
###############
my $invalid     = 'unknown';                                         # default value for invalid readings
my $definterval = 30;                                                # default Abrufintervall der Batteriewerte
my $defto       = 0.5;                                               # default connection Timeout zum RS485 Gateway
my @blackl      = qw(state nextCycletime);                           # Ausnahmeliste deleteReadingspec
my $age1def     = 60;                                                # default Zyklus Abrufklasse statische Werte (s)
my $wtbRS485cmd = 0.1;                                               # default Wartezeit zwischen RS485 Kommandos
my $pfx         = "~";                                               # KommandoPräfix
my $sfx         = "\x{0d}";                                          # Kommandosuffix

# Steuerhashes
###############
my %hrtnc = (                                                        # RTN Codes
  '00' => { desc => 'normal'                  },                     # normal Code
  '01' => { desc => 'VER error'               },
  '02' => { desc => 'CHKSUM error'            },
  '03' => { desc => 'LCHKSUM error'           },
  '04' => { desc => 'CID2 invalidation error' },
  '05' => { desc => 'Command format error'    },
  '06' => { desc => 'invalid data error'      },
  '90' => { desc => 'ADR error'               },
  '91' => { desc => 'Communication error between Master and Slave Pack'                                  },
  '98' => { desc => 'insufficient response length <LEN> of minimum length <MLEN> received ... discarded' },
  '99' => { desc => 'invalid data received ... discarded'                                                },
);

my %fncls = (                                                                 # Funktionsklassen
  1 => { class => 'sta', fn => \&_callSerialNumber        },                  #   statisch - serialNumber
  2 => { class => 'sta', fn => \&_callManufacturerInfo    },                  #   statisch - manufacturerInfo
  3 => { class => 'sta', fn => \&_callProtocolVersion     },                  #   statisch - protocolVersion
  4 => { class => 'sta', fn => \&_callSoftwareVersion     },                  #   statisch - softwareVersion
  5 => { class => 'sta', fn => \&_callSystemParameters    },                  #   statisch - systemParameters
  6 => { class => 'dyn', fn => \&_callAnalogValue         },                  #   dynamisch - analogValue
  7 => { class => 'dyn', fn => \&_callAlarmInfo           },                  #   dynamisch - alarmInfo
  8 => { class => 'dyn', fn => \&_callChargeManagmentInfo },                  #   dynamisch - chargeManagmentInfo  
);

my %halm = (                                                                  # Codierung Alarme
  '00' => { alm => 'normal'            },
  '01' => { alm => 'below lower limit' },
  '02' => { alm => 'above higher limit'},
  'F0' => { alm => 'other error'       },
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
#
# '--'  -> Platzhalter für Batterieadresse, wird ersetzt durch berechnete Adresse (Bat + Group in _composeAddr)
##################################################################################################################################################################
# Codierung Abruf serialNumber, mlen = Mindestlänge Antwortstring
# ADR: n=Batterienummer (2-x), m=Group Nr. (0-8), ADR = 0x0n + (0x10 * m) -> f. Batterie 1 = 0x02 + (0x10 * 0) = 0x02
# CID1: Kommando spezifisch, hier 46H
# CID2: Kommando spezifisch, hier 93H
# LENGTH: LENID + LCHKSUM -> Pylon LFP V2.8 Doku
# INFO: muß hier mit ADR übereinstimmen
# CHKSUM (als HEX! addieren): 32+30+30+41+34+36+39+33+45+30+30+32+30+41 = 02F1H -> modulo 65536 = 02F1H -> bitweise invert = 1111 1101 0000 1110 -> +1 = 1111 1101 0000 1111 -> FD0FH
#
# SOI  VER    ADR   CID1  CID2      LENGTH     INFO    CHKSUM
#  ~    20    10      46    93     E0    02    10      
# 7E  32 30  31 30  34 36 39 33  45 30 30 32  31 30                  = 02D1H -> bitweise invert = 1111 1101 0010 1110 -> +1 = 1111 1101 0010 1111 -> FD2FH
##################################################################################################################################################################
my %hrsnb = (                                                              
  1 => { cmd => '20--4693E002--', fnclsnr => 1, fname => 'serialNumber', mlen => 52 },
);

##################################################################################################################################################################
# Codierung Abruf manufacturerInfo, mlen = Mindestlänge Antwortstring
# ADR: n=Batterienummer (2-x), m=Group Nr. (0-8), ADR = 0x0n + (0x10 * m) -> f. Batterie 1 = 0x02 + (0x10 * 0) = 0x02
# CID1: Kommando spezifisch, hier 46H
# CID2: Kommando spezifisch, hier 51H
# LENGTH: LENID + LCHKSUM -> Pylon LFP V3.3 Doku
# LENID = 0 -> LENID = 0000B + 0000B + 0000B = 0000B -> modulo 16 -> 0000B -> bitweise invert = 1111 -> +1 = 0001 0000 -> LCHKSUM = 0000B -> LENGTH = 0000 0000 0000 0000 -> 0000H
# wenn LENID = 0, dann ist INFO empty (Doku LFP V3.3 S.8)
# CHKSUM (als HEX! addieren): 32+30+30+41+34+36+35+31+30+30+30+30 = 0263H -> modulo 65536 = 0263H -> bitweise invert = 1111 1101 1001 1100 -> +1 = 1111 1101 1001 1101  = FD9DH
#
# SOI  VER    ADR   CID1  CID2      LENGTH    INFO     CHKSUM
#  ~    20    10      46    51     00    00   empty    
# 7E  32 20  31 30  34 36 35 31  30 30 30 30   - -     FD  BD        = 0243H -> bitweise invert = 1111 1101 1011 1100 -> +1 = 1111 1101 1011 1101 = FDBDH
##################################################################################################################################################################
my %hrmfi = (                                                                    
  1 => { cmd => '20--46510000', fnclsnr => 2, fname => 'manufacturerInfo', mlen => 82 },
);

##################################################################################################################################################################
# Codierung Abruf protocolVersion, mlen = Mindestlänge Antwortstring
# ADR: n=Batterienummer (2-x), m=Group Nr. (0-8), ADR = 0x0n + (0x10 * m) -> f. Batterie 1 = 0x02 + (0x10 * 0) = 0x02
# CID1: Kommando spezifisch, hier 46H
# CID2: Kommando spezifisch, hier 4FH
# LENGTH: LENID + LCHKSUM -> Pylon LFP V3.3 Doku
# LENID = 0 -> LENID = 0000B + 0000B + 0000B = 0000B -> modulo 16 -> 0000B -> bitweise invert = 1111 -> +1 = 0001 0000 -> LCHKSUM = 0000B -> LENGTH = 0000 0000 0000 0000 -> 0000H
# wenn LENID = 0, dann ist INFO empty (Doku LFP V3.3 S.8)
# CHKSUM (als HEX! addieren): 30+30+30+41+34+36+34+46+30+30+30+30 = 0275H -> modulo 65536 = 0275H -> bitweise invert = 1111 1101 1000 1010 -> +1 = 1111 1101 1000 1011 -> FD8BH
#
# SOI  VER    ADR   CID1   CID2      LENGTH    INFO     CHKSUM
#  ~    00    0A      46    4F      00    00   empty    
##################################################################################################################################################################
my %hrprt = (                                                        
  1 => { cmd => '00--464F0000', fnclsnr => 3, fname => 'protocolVersion', mlen => 18 },
);

##################################################################################################################################################################
# Codierung Abruf softwareVersion
# CHKSUM (als HEX! addieren): 32+30+30+41+34+36+39+36+45+30+30+32+30+41 = 02F4H -> modulo 65536 = 02F4H -> bitweise invert = 1111 1101 0000 1011 -> +1 1111 1101 0000 1100 = FD0CH
#
# SOI  VER    ADR   CID1  CID2      LENGTH     INFO    CHKSUM
#  ~    20    11      46    96     E0    02    11     
# 7E  32 30  31 31  34 36 39 36  45 30 30 32  31 31    
##################################################################################################################################################################
my %hrswv = (                                                        
  1 => { cmd => '20--4696E002--', fnclsnr => 4, fname => 'softwareVersion', mlen => 30 },
);

##################################################################################################################################################################
# Codierung Abruf Systemparameter
# CHKSUM (als HEX! addieren): 32+30+30+41+34+36+34+37+45+30+30+32+30+41 = 02F0H -> modulo 65536 = 02F0H -> bitweise invert = 1111 1101 0000 1111 -> +1 1111 1101 0001 0000 = FD10H
#
# SOI  VER    ADR   CID1  CID2      LENGTH     INFO    CHKSUM
#  ~    20    0A      46    47     E0    02    0A      FD  10
# 7E  32 30  30 41  34 36 34 37  45 30 30 32  30 41  
##################################################################################################################################################################
my %hrspm = (                                                        
  1 => { cmd => '20--4647E002--', fnclsnr => 5, fname => 'systemParameter', mlen => 68 },
);

##################################################################################################################################################################
# Codierung Abruf analogValue
# ADR: n=Batterienummer (2-x), m=Group Nr. (0-8), ADR = 0x0n + (0x10 * m) -> f. Batterie 1 = 0x02 + (0x10 * 0) = 0x02
# CID1: Kommando spezifisch, hier 46H
# CID2: Kommando spezifisch, hier 42H                                                                                                              LCHK|    LENID
# LENGTH: LENID + LCHKSUM -> Pylon LFP V3.3 Doku                                                                                                   ---- --------------
# LENID = 02H -> LENID = 0000B + 0000B + 0010B = 0010B -> modulo 16 -> 0010B -> bitweise invert = 1101 -> +1 = 1110 -> LCHKSUM = 1110B -> LENGTH = 1110 0000 0000 0010 -> E002H
# wenn LENID = 0, dann ist INFO empty (Doku LFP V3.3 S.8)
# CHKSUM (als HEX! addieren): 32+30+30+41+34+36+34+32+45+30+30+32+30+41 = 02EBH -> modulo 65536 = 02EBH -> bitweise invert = 1111 1101 0001 0100 -> +1 1111 1101 0001 0101 = FD15H
#
# SOI  VER    ADR   CID1   CID2      LENGTH    INFO     CHKSUM
#  ~    20    10     46     42      E0    02    10      
# 7E  32 30  31 30  34 36  34 32  45 30 30 32  31 30              
##################################################################################################################################################################
my %hrcmn = (                                                       
  1 => { cmd => '20--4642E002--', fnclsnr => 6, fname => 'analogValue', mlen => 128 },
);

##################################################################################################################################################################
# Codierung Abruf alarmInfo
# CHKSUM (als HEX! addieren): 32+30+30+41+34+36+34+34+45+30+30+32+30+41 = 02EDH -> modulo 65536 = 02EDH -> bitweise invert = 1111 1101 0001 0010 -> +1 1111 1101 0001 0011 = FD13H
#
# SOI  VER    ADR   CID1  CID2      LENGTH     INFO    CHKSUM
#  ~    20    10      46    44     E0    02    10      FD  33
# 7E  32 30  31 30  34 36 34 34  45 30 30 32  31 30                  1111 1101 0011 0010
##################################################################################################################################################################
my %hralm = (                                                        
  1 => { cmd => '20--4644E002--', fnclsnr => 7, fname => 'alarmInfo', mlen => 82 },
);

##################################################################################################################################################################
# Codierung Abruf chargeManagmentInfo
# CHKSUM (als HEX! addieren): 32+30+30+41+34+36+39+32+45+30+30+32+30+41 = 02F0H -> modulo 65536 = 02F0H -> bitweise invert = 1111 1101 0000 1111 -> +1 1111 1101 0001 0000 = FD10H
#
# SOI  VER    ADR   CID1  CID2      LENGTH     INFO    CHKSUM
#  ~    20    0A      46    92     E0    02    0A      FD  10
# 7E  32 30  30 41  34 36 39 32  45 30 30 32  30 41  
##################################################################################################################################################################
my %hrcmi = (                                                        
  1 => { cmd => '20--4692E002--', fnclsnr => 8, fname => 'chargeManagmentInfo', mlen => 38 },
);



###############################################################
#                  PylonLowVoltage Initialize
###############################################################
sub Initialize {
  my $hash = shift;

  $hash->{DefFn}      = \&Define;
  $hash->{UndefFn}    = \&Undef;
  $hash->{GetFn}      = \&Get;
  $hash->{AttrFn}     = \&Attr;
  $hash->{ShutdownFn} = \&Shutdown;
  $hash->{AttrList}   = "disable:1,0 ".
                        "interval ".
                        "timeout ".
                        "userBatterytype ".
                        "waitTimeBetweenRS485Cmd:slider,0.1,0.1,2.0,1 ".
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

  if ($iostabs) {
      my $err = "Perl module >$iostabs< is missing. You have to install this perl module.";
      Log3 ($name, 1, "$name - ERROR - $err");
      return "Error: $err";
  }

  if ($storabs) {
      my $err = "Perl module >$storabs< is missing. You have to install this perl module.";
      Log3 ($name, 1, "$name - ERROR - $err");
      return "Error: $err";
  }

  $hash->{HELPER}{MODMETAABSENT} = 1 if($modMetaAbsent);                           # Modul Meta.pm nicht vorhanden
  
  my ($a,$h)                     = parseParams (join ' ', @args);  
  ($hash->{HOST}, $hash->{PORT}) = split ":", $$a[2];
  
  if (!$hash->{HOST} || !$hash->{PORT}) {
      return "The <hostname/ip>:<port> must be specified.";
  }
  
  if (defined $$a[3] && $$a[3] !~ /^([1-9]{1}|1[0-6])$/xs) {
      return "The bataddress must be an integer from 1 to 16";
  }
  
  if (defined $h->{group} && $h->{group} !~ /^([0-7]{1})$/xs) {
      return "The group number must be an integer from 0 to 7";
  }
  
  $hash->{HELPER}{BATADDRESS} = $$a[3]      // 1;
  $hash->{HELPER}{GROUP}      = $h->{group} // 0;
  $hash->{HELPER}{AGE1}       = 0;

  my $params = {
      hash        => $hash,
      notes       => \%vNotesIntern,
      useAPI      => 0,
      useSMUtils  => 1,
      useErrCodes => 0,
      useCTZ      => 0,
  };
  use version 0.77; our $VERSION = moduleVersion ($params);                        # Versionsinformationen setzen

  _closeSocket ($hash);
  manageUpdate ($hash);

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
      manageUpdate ($hash);
      return;
  }

return $getlist;
}

###############################################################
#                  PylonLowVoltage Attr
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
          InternalTimer(gettimeofday() + 2.0, "FHEM::PylonLowVoltage::manageUpdate", $hash, 0);
      }
      else {
          deleteReadingspec ($hash);
          readingsDelete    ($hash, 'nextCycletime');
          _closeSocket      ($hash);
      }
  }

  if ($cmd eq 'set') {
      if ($aName eq 'interval') {
          if (!looks_like_number($aVal)) {
              return qq{The value for $aName is invalid, it must be numeric!};
          }

          InternalTimer(gettimeofday()+1.0, "FHEM::PylonLowVoltage::manageUpdate", $hash, 0);
      }
      
      if ($aName =~ /timeout|waitTimeBetweenRS485Cmd/xs) {
          if (!looks_like_number($aVal)) {
              return qq{The value for $aName is invalid, it must be numeric!};
          }
      }
  }

  if ($aName eq 'userBatterytype') {
      $hash->{HELPER}{AGE1} = 0;
      InternalTimer(gettimeofday()+1.0, "FHEM::PylonLowVoltage::manageUpdate", $hash, 0);
  }

return;
}

###############################################################
#             Eintritt in den Update-Prozess
###############################################################
sub manageUpdate {
  my $hash = shift;
  my $name = $hash->{NAME};
  my $age1 = delete $hash->{HELPER}{AGE1} // $age1def;

  RemoveInternalTimer ($hash);

  if (!$init_done) {
      InternalTimer(gettimeofday() + 2, "FHEM::PylonLowVoltage::manageUpdate", $hash, 0);
      return;
  }

  return if(IsDisabled ($name));

  my $interval = AttrVal ($name, 'interval', $definterval);                                 # 0 -> manuell gesteuert
  my $timeout  = AttrVal ($name, 'timeout',        $defto);
  my ($readings, $new);

  if (!$interval) {
      $hash->{OPMODE}            = 'Manual';
      $readings->{nextCycletime} = 'Manual';
  }
  else {
      $new = gettimeofday() + $interval;
      InternalTimer ($new, "FHEM::PylonLowVoltage::manageUpdate", $hash, 0);                # Wiederholungsintervall

      $hash->{OPMODE}            = 'Automatic';
      $readings->{nextCycletime} = FmtTime($new);
  }
  
  delete $hash->{HELPER}{BKRUNNING} if(defined $hash->{HELPER}{BKRUNNING} && $hash->{HELPER}{BKRUNNING}{pid} =~ /DEAD/xs);
 
  for my $dev ( devspec2array ('TYPE=PylonLowVoltage') ) {
      if (defined $defs{$dev}->{HELPER}{BKRUNNING} || defined $defs{$dev}->{HELPER}{GWSESSION}) {
          $hash->{POSTPONED} += 1;
          
          RemoveInternalTimer ($hash);
          $new = gettimeofday() + 1;
          InternalTimer (gettimeofday() + 1, "FHEM::PylonLowVoltage::manageUpdate", $hash, 0); 
          
          $readings->{nextCycletime} = FmtTime ($new);
          $readings->{state}         = "cycle postponed due to active gateway connection of $dev";
          createReadings ($hash, 1, $readings);                                             
          
          if (defined $defs{$dev}->{HELPER}{BKRUNNING}) {
              Log3 ($name, 4, qq{$name - another Gateway Call from $dev with PID "$defs{$dev}->{HELPER}{BKRUNNING}{pid}" is already running ... start Update postponed});
          }
          else {
              Log3 ($name, 4, qq{$name - another Gateway Call from $dev is already running ... start Update postponed});
          }
          
          return;
      }
  }

  Log3 ($name, 4, "$name - START request cycle to battery number >$hash->{HELPER}{BATADDRESS}<, group >$hash->{HELPER}{GROUP}< at host:port $hash->{HOST}:$hash->{PORT}");

  if ($timeout < 1.0) {
      $hash->{HELPER}{GWSESSION} = 1;
      Log3 ($name, 4, qq{$name - Cycle started in main process with battery read timeout: >$timeout<});
      startUpdate  ({name => $name, timeout => $timeout, readings => $readings, age1 => $age1});
  }
  else {
     my $blto = sprintf "%.0f", ($timeout + (AttrVal ($name, 'waitTimeBetweenRS485Cmd', $wtbRS485cmd) * 15));

     $hash->{HELPER}{BKRUNNING} = BlockingCall ( "FHEM::PylonLowVoltage::startUpdate",
                                                 {name => $name, timeout => $timeout, readings => $readings, age1 => $age1, block => 1},
                                                 "FHEM::PylonLowVoltage::finishUpdate",
                                                 $blto,                                                  # Blocking Timeout höher als INET-Timeout!
                                                 "FHEM::PylonLowVoltage::abortUpdate",
                                                 $hash
                                               );


     if (defined $hash->{HELPER}{BKRUNNING}) {
         $hash->{HELPER}{BKRUNNING}{loglevel} = 3;                                                       # Forum https://forum.fhem.de/index.php/topic,77057.msg689918.html#msg689918

         Log3 ($name, 4, qq{$name - Cycle BlockingCall PID "$hash->{HELPER}{BKRUNNING}{pid}" started with battery read timeout: >$timeout<, blocking timeout >$blto<});
     }
  }

return;
}

###############################################################
#                  PylonLowVoltage startUpdate
###############################################################
sub startUpdate {
  my $paref    = shift;

  my $name     = $paref->{name};
  my $timeout  = $paref->{timeout};
  my $readings = $paref->{readings};
  my $block    = $paref->{block} // 0;
  my $age1     = $paref->{age1};

  my $hash     = $defs{$name};
  my $success  = 0;
  my $wtb      = AttrVal ($name, 'waitTimeBetweenRS485Cmd', $wtbRS485cmd);                            # Wartezeit zwischen RS485 Kommandos
  my $uat      = $block ? $timeout * 1000000 + $wtb * 1000000 : $timeout * 1000000; 

  Log3 ($name, 4, "$name - used wait time between RS485 commands: ".($block ? $wtb : 0)." seconds");  

  my ($socket, $serial);

  eval {                                                                                              ## no critic 'eval'
      local $SIG{ALRM} = sub { croak 'gatewaytimeout' };
      ualarm ($timeout * 1000000);                                                                    # ualarm in Mikrosekunden -> 1s

      $socket = _openSocket ($hash, $timeout, $readings);

      if (!$socket) {
          $serial = encode_base64 (Serialize ( {name => $name, readings => $readings} ), "");
          $block ? return ($serial) : return \&finishUpdate ($serial);
      }
      
      local $SIG{ALRM} = sub { croak 'batterytimeout' };
      
      for my $idx (sort keys %fncls) {                                                                 
          next if($fncls{$idx}{class} eq 'sta' && ReadingsAge ($name, "serialNumber", 6000) < $age1);    # Funktionsklasse statische Werte seltener abrufen
          
          ualarm ($uat);   
          
          if (&{$fncls{$idx}{fn}} ($hash, $socket, $readings)) {
              $serial = encode_base64 (Serialize ( {name => $name, readings => $readings} ), "");
              $block ? return ($serial) : return \&finishUpdate ($serial);
          }
          
          ualarm(0);
          sleep $wtb if($block); 
      }

      $success = 1;
  };  # eval

  if ($@) {
      my $errtxt;
      if ($@ =~ /gatewaytimeout/xs) {
          $errtxt = 'Timeout while establish RS485 gateway connection';
      }
      elsif ($@ =~ /batterytimeout/xs) {
          $errtxt = 'Timeout reading battery';
      }
      else {
          $errtxt = $@;
      }

      doOnError ({ hash     => $hash,
                   readings => $readings,
                   sock     => $socket,
                   state    => $errtxt,
                   res      => '',
                   verbose  => 3
                 }
                );

      $serial = encode_base64 (Serialize ( {name => $name, readings => $readings} ), "");
      $block ? return ($serial) : return \&finishUpdate ($serial);
  }

  ualarm(0);
  _closeSocket ($hash);

  $serial = encode_base64 (Serialize ({name => $name, success  => $success, readings => $readings}), "");

  if ($block) {
      return ($serial);
  }

return \&finishUpdate ($serial);
}

###############################################################
#    Restaufgaben nach Update
###############################################################
sub finishUpdate {
  my $serial   = decode_base64 (shift);

  my $paref    = eval { thaw ($serial) };                                             # Deserialisierung
  my $name     = $paref->{name};
  my $success  = $paref->{success} // 0;
  my $readings = $paref->{readings};
  my $hash     = $defs{$name};

  delete $hash->{HELPER}{BKRUNNING};
  delete $hash->{HELPER}{GWSESSION};

  if ($success) {
      Log3 ($name, 4, "$name - got data from battery number >$hash->{HELPER}{BATADDRESS}<, group >$hash->{HELPER}{GROUP}< successfully");

      additionalReadings ($readings);                                                 # zusätzliche eigene Readings erstellen
      $readings->{state} = 'connected';
  }
  else {
      deleteReadingspec ($hash);
  }

  createReadings ($hash, $success, $readings);                                        # Readings erstellen

return;
}

####################################################################################################
#                    Abbruchroutine BlockingCall Timeout
####################################################################################################
sub abortUpdate {
  my $hash   = shift;
  my $cause  = shift // "Timeout: process terminated";
  my $name   = $hash->{NAME};

  Log3 ($name, 1, "$name -> BlockingCall $hash->{HELPER}{BKRUNNING}{fn} pid:$hash->{HELPER}{BKRUNNING}{pid} aborted: $cause");

  delete $hash->{HELPER}{BKRUNNING};
  delete $hash->{HELPER}{GWSESSION};

  deleteReadingspec    ($hash);
  readingsSingleUpdate ($hash, 'state', 'Update (Child) process timed out', 1);

return;
}

###############################################################
#       Socket erstellen
###############################################################
sub _openSocket {
  my $hash     = shift;
  my $timeout  = shift;
  my $readings = shift;                # Referenz auf das Hash der zu erstellenden Readings

  my $socket   = $hash->{SOCKET};

  if ($socket && !$socket->connected()) {
      doOnError ({ hash     => $hash,
                   readings => $readings,
                   sock     => $socket,
                   res      => '',
                   state    => 'disconnected'
                 }
                );

      _closeSocket ($hash);
      undef $socket;
  }

  if (!$socket) {
      $socket = IO::Socket::INET->new( Proto    => 'tcp',
                                       PeerAddr => $hash->{HOST},
                                       PeerPort => $hash->{PORT},
                                       Timeout  => $timeout
                                     )
                or do { doOnError ({ hash     => $hash,
                                     readings => $readings,
                                     state    => 'no connection to RS485 gateway established',
                                     res      => '',
                                     verbose  => 3
                                   }
                                  );
                        return;
                      };
  }

  IO::Socket::Timeout->enable_timeouts_on ($socket);                       # nur notwendig für read or write timeout

  $socket->read_timeout  (0.5);                                            # Read/Writetimeout immer kleiner als Sockettimeout
  $socket->write_timeout (0.5);
  $socket->autoflush();

  $hash->{SOCKET} = $socket;

return $socket;
}

###############################################################
#       Socket schließen und löschen
###############################################################
sub _closeSocket {
  my $hash = shift;

  my $name   = $hash->{NAME};
  my $socket = $hash->{SOCKET};

  if ($socket) {
      close ($socket);
      delete $hash->{SOCKET};

      Log3 ($name, 4, "$name - Socket/Connection to the RS485 gateway was closed");
  }

return;
}

###############################################################
#       Abruf serialNumber
###############################################################
sub _callSerialNumber {
  my $hash     = shift;
  my $socket   = shift;
  my $readings = shift;                # Referenz auf das Hash der zu erstellenden Readings
  
  my $res = Request ({ hash   => $hash,
                       socket => $socket,
                       cmd    => getCmdString ($hash, $hrsnb{1}{cmd}),
                       cmdtxt => 'serialNumber'
                     }
                    );

  my $rtnerr = responseCheck ($res, $hrsnb{1}{mlen});

  if ($rtnerr) {
      doOnError ({ hash     => $hash,
                   readings => $readings,
                   sock     => $socket,
                   res      => $res,
                   state    => $rtnerr
                 }
                );
      return $rtnerr;
  }

  __resultLog ($hash, $res);

  my $sernum                = substr ($res, 15, 32);
  $readings->{serialNumber} = pack   ("H*", $sernum);

return;
}

###############################################################
#       Abruf manufacturerInfo
###############################################################
sub _callManufacturerInfo {
  my $hash     = shift;
  my $socket   = shift;
  my $readings = shift;                # Referenz auf das Hash der zu erstellenden Readings

  my $res = Request ({ hash   => $hash,
                       socket => $socket,
                       cmd    => getCmdString ($hash, $hrmfi{1}{cmd}),
                       cmdtxt => 'manufacturerInfo'
                     }
                    );

  my $rtnerr = responseCheck ($res, $hrmfi{1}{mlen});

  if ($rtnerr) {
      doOnError ({ hash     => $hash,
                   readings => $readings,
                   sock     => $socket,
                   res      => $res,
                   state    => $rtnerr
                 }
                );
      return $rtnerr;
  }

  __resultLog ($hash, $res);

  my $name                  = $hash->{NAME};
  my $ubtt                  = AttrVal ($name, 'userBatterytype', '');                               # evtl. Batterietyp manuell überschreiben
  my $BatteryHex            = substr  ($res, 13, 20);
  # my $softwareVersion       = 'V'.hex (substr ($res, 33, 2)).'.'.hex (substr ($res, 35, 2));      # unklare Bedeutung
  my $ManufacturerHex       = substr  ($res, 37, 40);

  $readings->{batteryType}  = $ubtt ? $ubtt.' (adapted)' : pseudoHexToText ($BatteryHex); 
  $readings->{Manufacturer} = pseudoHexToText ($ManufacturerHex);

return;
}

###############################################################
#       Abruf protocolVersion
###############################################################
sub _callProtocolVersion {
  my $hash     = shift;
  my $socket   = shift;
  my $readings = shift;                # Referenz auf das Hash der zu erstellenden Readings

  my $res = Request ({ hash   => $hash,
                       socket => $socket,
                       cmd    => getCmdString ($hash, $hrprt{1}{cmd}),
                       cmdtxt => 'protocolVersion'
                     }
                    );

  my $rtnerr = responseCheck ($res, $hrprt{1}{mlen});

  if ($rtnerr) {
      doOnError ({ hash     => $hash,
                   readings => $readings,
                   sock     => $socket,
                   res      => $res,
                   state    => $rtnerr
                 }
                );
      return $rtnerr;
  }

  __resultLog ($hash, $res);

  $readings->{protocolVersion} = 'V'.hex (substr ($res, 1, 1)).'.'.hex (substr ($res, 2, 1));

return;
}

###############################################################
#       Abruf softwareVersion
###############################################################
sub _callSoftwareVersion {
  my $hash     = shift;
  my $socket   = shift;
  my $readings = shift;                # Referenz auf das Hash der zu erstellenden Readings

  my $res = Request ({ hash   => $hash,
                       socket => $socket,
                       cmd    => getCmdString ($hash, $hrswv{1}{cmd}),
                       cmdtxt => 'softwareVersion'
                     }
                    );

  my $rtnerr = responseCheck ($res, $hrswv{1}{mlen});

  if ($rtnerr) {
      doOnError ({ hash     => $hash,
                   readings => $readings,
                   sock     => $socket,
                   res      => $res,
                   state    => $rtnerr
                 }
                );
      return $rtnerr;
  }

  __resultLog ($hash, $res);

  $readings->{moduleSoftwareVersion_manufacture} = 'V'.hex (substr ($res, 15, 2)).'.'.hex (substr ($res, 17, 2));
  $readings->{moduleSoftwareVersion_mainline}    = 'V'.hex (substr ($res, 19, 2)).'.'.hex (substr ($res, 21, 2)).'.'.hex (substr ($res, 23, 2));

return;
}

###############################################################
#       Abruf systemParameters
###############################################################
sub _callSystemParameters {
  my $hash     = shift;
  my $socket   = shift;
  my $readings = shift;                # Referenz auf das Hash der zu erstellenden Readings

  my $res = Request ({ hash   => $hash,
                       socket => $socket,
                       cmd    => getCmdString ($hash, $hrspm{1}{cmd}),
                       cmdtxt => 'systemParameters'
                     }
                    );

  my $rtnerr = responseCheck ($res, $hrspm{1}{mlen});

  if ($rtnerr) {
      doOnError ({ hash     => $hash,
                   readings => $readings,
                   sock     => $socket,
                   res      => $res,
                   state    => $rtnerr
                 }
                );
      return $rtnerr;
  }

  __resultLog ($hash, $res);

  $readings->{paramCellHighVoltLimit}      = sprintf "%.3f", (hex substr  ($res, 15, 4)) / 1000;
  $readings->{paramCellLowVoltLimit}       = sprintf "%.3f", (hex substr  ($res, 19, 4)) / 1000;                   # Alarm Limit
  $readings->{paramCellUnderVoltLimit}     = sprintf "%.3f", (hex substr  ($res, 23, 4)) / 1000;                   # Schutz Limit
  $readings->{paramChargeHighTempLimit}    = sprintf "%.1f", ((hex substr ($res, 27, 4)) - 2731) / 10;
  $readings->{paramChargeLowTempLimit}     = sprintf "%.1f", ((hex substr ($res, 31, 4)) - 2731) / 10;
  $readings->{paramChargeCurrentLimit}     = sprintf "%.3f", (hex substr  ($res, 35, 4)) * 100 / 1000;
  $readings->{paramModuleHighVoltLimit}    = sprintf "%.3f", (hex substr  ($res, 39, 4)) / 1000;
  $readings->{paramModuleLowVoltLimit}     = sprintf "%.3f", (hex substr  ($res, 43, 4)) / 1000;                   # Alarm Limit
  $readings->{paramModuleUnderVoltLimit}   = sprintf "%.3f", (hex substr  ($res, 47, 4)) / 1000;                   # Schutz Limit
  $readings->{paramDischargeHighTempLimit} = sprintf "%.1f", ((hex substr ($res, 51, 4)) - 2731) / 10;
  $readings->{paramDischargeLowTempLimit}  = sprintf "%.1f", ((hex substr ($res, 55, 4)) - 2731) / 10;
  $readings->{paramDischargeCurrentLimit}  = sprintf "%.3f", (65535 - (hex substr ($res, 59, 4))) * 100 / 1000;    # mit Symbol (-)

return;
}

#################################################################################
#       Abruf analogValue
# Answer from US2000 = 128 Bytes, from US3000 = 140 Bytes
# Remain capacity US2000 hex(substr($res,109,4), US3000 hex(substr($res,123,6)
# Module capacity US2000 hex(substr($res,115,4), US3000 hex(substr($res,129,6)
#################################################################################
sub _callAnalogValue {
  my $hash     = shift;
  my $socket   = shift;
  my $readings = shift;                # Referenz auf das Hash der zu erstellenden Readings
  my $name     = $hash->{NAME};

  my $res = Request ({ hash   => $hash,
                       socket => $socket,
                       cmd    => getCmdString ($hash, $hrcmn{1}{cmd}),
                       cmdtxt => 'analogValue'
                     }
                    );

  my $rtnerr = responseCheck ($res, $hrcmn{1}{mlen});

  if ($rtnerr) {
      doOnError ({ hash     => $hash,
                   readings => $readings,
                   sock     => $socket,
                   res      => $res,
                   state    => $rtnerr
                 }
                );
      return $rtnerr;
  }

  __resultLog ($hash, $res);

  my $bpos = 17;                                                                                 # Startposition
  my $pcc  = hex (substr($res, $bpos, 2));                                                       # Anzahl Zellen (15 od. 16)
  $bpos   += 2;                                                                                  # Pos 19

  for my $z (1..$pcc) {
      my $fz                          = sprintf "%02d", $z;                                      # formatierter Zähler
      $readings->{'cellVoltage_'.$fz} = sprintf "%.3f", hex(substr($res, $bpos, 4)) / 1000;      # Pos 19 -> 75 bei 15 Zellen
      $bpos += 4;                                                                                # letzter Durchlauf: Pos 79 bei 15 Zellen, Pos 83 bei 16 Zellen
  }
  
  $readings->{numberTempPos}             = hex(substr($res, $bpos, 2));                          # Anzahl der jetzt folgenden Temperaturpositionen -> 5 oder mehr (US5000: 6)
  $bpos += 2;

  $readings->{bmsTemperature}            = (hex (substr($res, $bpos, 4)) - 2731) / 10;           # Pos 81 bei 15 Zellen
  $bpos += 4;

  $readings->{cellTemperature_0104}      = (hex (substr($res, $bpos, 4)) - 2731) / 10;           # Pos 85
  $bpos += 4;

  $readings->{cellTemperature_0508}      = (hex (substr($res, $bpos, 4)) - 2731) / 10;           # Pos 89
  $bpos += 4;

  $readings->{cellTemperature_0912}      = (hex (substr($res, $bpos, 4)) - 2731) / 10;           # Pos 93
  $bpos += 4;

  $readings->{'cellTemperature_13'.$pcc} = (hex (substr($res, $bpos, 4)) - 2731) / 10;           # Pos 97
  $bpos += 4;

  for my $t (6..$readings->{numberTempPos}) {
      $t = 'Pos_'.sprintf "%02d", $t;
      $readings->{'cellTemperature_'.$t} = (hex (substr($res, $bpos, 4)) - 2731) / 10;           # mehr als 5 Temperaturpositionen (z.B. US5000)
      $bpos += 4;                                                                                # Position bei 5 Temp.Angaben (bei 6 Temperaturen)
  }

  my $current                            =  hex (substr($res, $bpos, 4));                        # Pos 101 (105)
  $bpos += 4;

  $readings->{packVolt}                  = sprintf "%.3f", hex (substr($res, $bpos, 4)) / 1000;  # Pos 105 (109)
  $bpos += 4;

  my $remcap1                            = sprintf "%.3f", hex (substr($res, $bpos, 4)) / 1000;  # Pos 109 (113)
  $bpos += 4;

  my $udi                                = hex substr($res, $bpos, 2);                           # Pos 113 (117)  user defined item=Entscheidungskriterium -> 2: Batterien <= 65Ah, 4: Batterien > 65Ah
  $bpos += 2;

  my $totcap1                            = sprintf "%.3f", hex (substr($res, $bpos, 4)) / 1000;  # Pos 115 (119)
  $bpos += 4;

  $readings->{packCycles}                = hex substr($res, $bpos, 4);                           # Pos 119 (123)
  $bpos += 4;

  my $remcap2                            = sprintf "%.3f", hex (substr($res, $bpos, 6)) / 1000;  # Pos 123 (127)
  $bpos += 6;

  my $totcap2                            = sprintf "%.3f", hex (substr($res, $bpos, 6)) / 1000;  # Pos 129 (133)
  $bpos += 6;

  # kalkulierte Werte generieren
  ################################
  if ($udi == 2) {
      $readings->{packCapacityRemain} = $remcap1;
      $readings->{packCapacity}       = $totcap1;
  }
  elsif ($udi == 4) {
      $readings->{packCapacityRemain} = $remcap2;
      $readings->{packCapacity}       = $totcap2;
  }
  else {
      my $err = 'wrong value retrieve analogValue -> user defined items: '.$udi;
      doOnError ({ hash     => $hash,
                   readings => $readings,
                   sock     => $socket,
                   res      => '',
                   state    => $err
                 }
                );
      return $err;
  }

  if ($current & 0x8000) {
      $current = $current - 0x10000;
  }

  $readings->{packCellcount} = $pcc;
  $readings->{packCurrent}   = sprintf "%.3f", $current / 10;

return;
}

###############################################################
#       Abruf alarmInfo
###############################################################
sub _callAlarmInfo {
  my $hash     = shift;
  my $socket   = shift;
  my $readings = shift;                # Referenz auf das Hash der zu erstellenden Readings

  my $res = Request ({ hash   => $hash,
                       socket => $socket,
                       cmd    => getCmdString ($hash, $hralm{1}{cmd}),
                       cmdtxt => 'alarmInfo'
                     }
                    );

  my $rtnerr = responseCheck ($res, $hralm{1}{mlen});

  if ($rtnerr) {
      doOnError ({ hash     => $hash,
                   readings => $readings,
                   sock     => $socket,
                   res      => $res,
                   state    => $rtnerr
                 }
                );
      return $rtnerr;
  }

  __resultLog ($hash, $res);
  
  my ($alm, $aval);
  
  my $bpos = 17;                                                                  # Startposition 
  $readings->{packCellcount} = hex (substr($res, $bpos, 2));                      # Pos. 17
  $bpos += 2;
  
  for my $cnt (1..$readings->{packCellcount}) {                                   # Start Pos. 19
      $cnt                                = sprintf "%02d", $cnt;                       
      $aval                               = substr ($res, $bpos, 2);
      $readings->{'almCellVoltage_'.$cnt} = $halm{$aval}{alm}; 
      $alm   = 1 if(int $aval);
      $bpos += 2;      
  }
  
  my $ntp = hex (substr($res, $bpos, 2));                                         # Pos. 49 bei 15 Zellen (Anzahl der Temperaturpositionen)
  $bpos += 2;

  for my $nt (1..$ntp) {                                                          # Start Pos. 51 bei 15 Zellen
      $nt                                = sprintf "%02d", $nt; 
      $aval                              = substr ($res, $bpos, 2);
      $readings->{'almTemperature_'.$nt} = $halm{$aval}{alm}; 
      $alm   = 1 if(int $aval);
      $bpos += 2;      
  }  
  
  $aval                         = substr ($res, $bpos, 2);                        # Pos. 61 b. 15 Zellen u. 5 Temp.positionen
  $readings->{almChargeCurrent} = $halm{$aval}{alm};
  $alm   = 1 if(int $aval);
  $bpos += 2;
  
  $aval                         = substr ($res, $bpos, 2);                        # Pos. 63 b. 15 Zellen u. 5 Temp.positionen
  $readings->{almModuleVoltage} = $halm{$aval}{alm};
  $alm   = 1 if(int $aval);
  $bpos += 2;
  
  $aval                            = substr ($res, $bpos, 2);                     # Pos. 65 b. 15 Zellen u. 5 Temp.positionen
  $readings->{almDischargeCurrent} = $halm{$aval}{alm};
  $alm   = 1 if(int $aval);
  $bpos += 2;
  
  my $stat1alm = substr ($res, $bpos, 2);                                         # Pos. 67 b. 15 Zellen u. 5 Temp.positionen
  $bpos += 2;
  
  my $stat2alm = substr ($res, $bpos, 2);                                         # Pos. 69 b. 15 Zellen u. 5 Temp.positionen
  $bpos += 2;
  
  my $stat3alm = substr ($res, $bpos, 2);                                         # Pos. 71 b. 15 Zellen u. 5 Temp.positionen
  $bpos += 2;
  
  my $stat4alm = substr ($res, $bpos, 2);                                         # Pos. 73 b. 15 Zellen u. 5 Temp.positionen
  $bpos += 2;
  
  my $stat5alm = substr ($res, $bpos, 2);                                         # Pos. 75 b. 15 Zellen u. 5 Temp.positionen
  
  if (!$alm) {
      $readings->{packAlarmInfo} = "ok";
  }
  else {
      $readings->{packAlarmInfo} = "failure";
  }  
    
  my $name = $hash->{NAME};
  
  if (AttrVal ($name, 'verbose', 3) > 4) {
      Log3 ($name, 5, "$name - Alarminfo - Status 1 alarm: $stat1alm");
      Log3 ($name, 5, "$name - Alarminfo - Status 2 Info: $stat2alm");
      Log3 ($name, 5, "$name - Alarminfo - Status 3 Info: $stat3alm");
      Log3 ($name, 5, "$name - Alarminfo - Status 4 alarm: $stat4alm");
      Log3 ($name, 5, "$name - Alarminfo - Status 5 alarm: $stat5alm \n");
  }
return;
}

###############################################################
#       Abruf chargeManagmentInfo
###############################################################
sub _callChargeManagmentInfo {
  my $hash     = shift;
  my $socket   = shift;
  my $readings = shift;                # Referenz auf das Hash der zu erstellenden Readings

  my $res = Request ({ hash   => $hash,
                       socket => $socket,
                       cmd    => getCmdString ($hash, $hrcmi{1}{cmd}),
                       cmdtxt => 'chargeManagmentInfo'
                     }
                    );

  my $rtnerr = responseCheck ($res, $hrcmi{1}{mlen});

  if ($rtnerr) {
      doOnError ({ hash     => $hash,
                   readings => $readings,
                   sock     => $socket,
                   res      => $res,
                   state    => $rtnerr
                 }
                );
      return $rtnerr;
  }

  __resultLog ($hash, $res);

  $readings->{chargeVoltageLimit}     = sprintf "%.3f", hex (substr ($res, 15, 4)) / 1000;        # Genauigkeit 3
  $readings->{dischargeVoltageLimit}  = sprintf "%.3f", hex (substr ($res, 19, 4)) / 1000;        # Genauigkeit 3
  $readings->{chargeCurrentLimit}     = sprintf "%.1f", hex (substr ($res, 23, 4)) / 10;          # Genauigkeit 1
  $readings->{dischargeCurrentLimit}  = sprintf "%.1f", (65536 - hex substr ($res, 27, 4)) / 10;  # Genauigkeit 1, Fixed point, unsigned integer

  my $cdstat                          = sprintf "%08b", hex substr ($res, 31, 2);                 # Rohstatus
  $readings->{chargeEnable}           = substr ($cdstat, 0, 1) == 1 ? 'yes' : 'no';               # Bit 7
  $readings->{dischargeEnable}        = substr ($cdstat, 1, 1) == 1 ? 'yes' : 'no';               # Bit 6
  $readings->{chargeImmediatelySOC05} = substr ($cdstat, 2, 1) == 1 ? 'yes' : 'no';               # Bit 5 - SOC 5~9%  -> für Wechselrichter, die aktives Batteriemanagement bei gegebener DC-Spannungsfunktion haben oder Wechselrichter, der von sich aus einen niedrigen SOC/Spannungsgrenzwert hat
  $readings->{chargeImmediatelySOC09} = substr ($cdstat, 3, 1) == 1 ? 'yes' : 'no';               # Bit 4 - SOC 9~13% -> für Wechselrichter hat keine aktive Batterieabschaltung haben
  $readings->{chargeFullRequest}      = substr ($cdstat, 4, 1) == 1 ? 'yes' : 'no';               # Bit 3 - wenn SOC in 30 Tagen nie höher als 97% -> Flag = 1, wenn SOC-Wert ≥ 97% -> Flag = 0

return;
}

###############################################################
#        Logausgabe Result
###############################################################
sub __resultLog {
  my $hash = shift;
  my $res  = shift;

  my $name = $hash->{NAME};

  Log3 ($name, 5, "$name - data returned raw: ".$res);
  Log3 ($name, 5, "$name - data returned:\n"   .Hexdump ($res));

return;
}

###############################################################
#                   Daten Serialisieren
###############################################################
sub Serialize {
  my $data = shift;
  my $name = $data->{name};

  my $serial = eval { freeze ($data)
                    }
                    or do { Log3 ($name, 2, "$name - Serialization ERROR: $@");
                            return;
                          };

return $serial;
}

###############################################################
#                  PylonLowVoltage Request
###############################################################
sub Request {
  my $paref = shift;

  my $hash   = $paref->{hash};
  my $socket = $paref->{socket};
  my $cmd    = $paref->{cmd};
  my $cmdtxt = $paref->{cmdtxt} // 'unspecified data';

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
    my $res = q{};

    do {
        $socket->read ($singlechar, 1);

        if (!$singlechar && (0+$! == ETIMEDOUT || 0+$! == EWOULDBLOCK)) {                # nur notwendig für read timeout
            croak 'Timeout reading data from battery';
        }

        $res = $res . $singlechar if(length $singlechar != 0 && $singlechar =~ /[~A-Z0-9\r]+/xs);

    } while (length $singlechar == 0 || ord($singlechar) != 13);

return $res;
}

################################################################
# Die Undef-Funktion wird aufgerufen wenn ein Gerät mit delete
# gelöscht wird oder bei der Abarbeitung des Befehls rereadcfg,
# der ebenfalls alle Geräte löscht und danach das
# Konfigurationsfile neu einliest. Entsprechend müssen in der
# Funktion typische Aufräumarbeiten durchgeführt werden wie das
# saubere Schließen von Verbindungen oder das Entfernen von
# internen Timern.
################################################################
sub Undef {
 my $hash = shift;
 my $name = shift;

 RemoveInternalTimer ($hash);
  _closeSocket       ($hash);
  BlockingKill       ($hash->{HELPER}{BKRUNNING}) if(defined $hash->{HELPER}{BKRUNNING});

return;
}

###############################################################
#                  PylonLowVoltage Shutdown
###############################################################
sub Shutdown {
  my ($hash, $args) = @_;

  RemoveInternalTimer ($hash);
  _closeSocket        ($hash);
  BlockingKill        ($hash->{HELPER}{BKRUNNING}) if(defined $hash->{HELPER}{BKRUNNING});

return;
}

###############################################################
#                  PylonLowVoltage Hexdump
###############################################################
sub Hexdump {
  my $res = shift;

  my $offset = 0;
  my $result = "";

  for my $chunk (unpack "(a16)*", $res) {
      my $hex  = unpack "H*", $chunk;                                                       # hexadecimal magic
      $chunk   =~ tr/ -~/./c;                                                               # replace unprintables
      $hex     =~ s/(.{1,8})/$1 /gxs;                                                       # insert spaces
      $result .= sprintf "0x%08x (%05u)  %-*s %s\n", $offset, $offset, 36, $hex, $chunk;
      $offset += 16;
  }

return $result;
}

###############################################################
#       Response Status ermitteln
###############################################################
sub responseCheck {
  my $res  = shift;
  my $mlen = shift // 0;                # Mindestlänge Antwortstring

  my $rtnerr = $hrtnc{99}{desc};

  if(!$res || $res !~ /^[~A-Fa-f0-9]+\r$/xs || $res =~ tr/~// != 1) {
      return $rtnerr;
  }

  my $len = length($res);

  if ($len < $mlen) {
      $rtnerr = $hrtnc{98}{desc};
      $rtnerr =~ s/<LEN>/$len/xs;
      $rtnerr =~ s/<MLEN>/$mlen/xs;
      return $rtnerr;
  }

  my $rtn = q{_};
  $rtn    = substr($res,7,2) if($res && $len >= 10);

  if(defined $hrtnc{$rtn}{desc} && substr($res, 0, 1) eq '~') {
      $rtnerr = $hrtnc{$rtn}{desc};
      return if($rtnerr eq 'normal');
  }

return $rtnerr;
}

###############################################################
#  Hex-Zeichenkette in ASCII-Zeichenkette einzeln umwandeln
###############################################################
sub pseudoHexToText {
   my $string = shift;
   
   my $charcode;
   my $text = '';
   
   for (my $i = 0; $i < length($string); $i += 2) {
      $charcode = hex substr ($string, $i, 2);                  # charcode = aquivalente Dezimalzahl der angegebenen Hexadezimalzahl
      next if($charcode == 45);                                 # Hyphen '-' ausblenden 
      
      $text = $text.chr ($charcode);
   }
   
return $text;
}

###############################################################
#          Kommandostring zusammenstellen
#          Teilstring aus Kommandohash wird übergeben
###############################################################
sub getCmdString {
  my $hash = shift;
  my $cstr = shift;                        # Komamndoteilstring                 

  my $addr = _composeAddr ($hash);         # effektive Batterieadresse berechnen
  $cstr    =~ s/--/$addr/xg;               # Platzhalter Adresse ersetzen
  
  my $cmd  = $pfx;                         # Präfix
  $cmd    .= $cstr;                        # Kommandostring
  $cmd    .= _doChecksum ($cstr);          # Checksumme ergänzen
  $cmd    .= $sfx;                         # Suffix 

return $cmd;
}

###############################################################
#  Adresse aus Batterie und Gruppe erstellen
# 
# 1) Single group battery 4:
#    n = 5; m = 0
#    ADR = 0x05 + 0x10*0 = 0x05; INFO of COMMAND = ADR = 0x05
# 2) multi group, group 3, battery 6;
#    n = 7; m = 3
#    ADR = 0x07 + 0x10*3 = 0x37; INFO of COMMAND = ADR = 0x37
###############################################################
sub _composeAddr {
   my $hash = shift;
   
   my $ba = sprintf "%02x", ($hash->{HELPER}{BATADDRESS} + 1);                          # Master startet mit "02"
   my $ga = sprintf "%02x", $hash->{HELPER}{GROUP};                    
   my $ad = sprintf "%02x", (hex ($ga) * hex (10) + hex ($ba));
   
   my $name  = $hash->{NAME};
   Log3 ($name, 5, "$name - Addressing (HEX) - Bat: $ba, Group: $ga, effective Bat address: $ad");
   
return $ad;
}

###############################################################
#  wandelt eine Zeichenkette aus HEX-Zahlen in eine 
#  hexadecimal-ASCII Zeichenkette um und berechnet daraus die
#  Checksumme (=Returnwert)
###############################################################
sub _doChecksum {
   my $hstring = shift // return;
   
   my $dezsum    = 0;
   my @asciivals = split //, $hstring;                           
   
   for my $v (@asciivals) {                                      # jedes einzelne Zeichen der HEX-Kette wird als ASCII Wert interpretiert 
       my $hex  = unpack "H*", $v;                               # in einen HEX-Wert umgewandelt
       $dezsum += hex $hex;                                      # und die Dezimalsumme gebildet
   }
   
   my $bin = sprintf '%016b', $dezsum;

   $bin    =~ s/1/x/g;                                           # invertieren
   $bin    =~ s/0/1/g;  
   $bin    =~ s/x/0/g;  
   
   $dezsum = oct("0b$bin");
   $dezsum++;
   $bin    = sprintf '%016b', $dezsum;

   my $chksum = sprintf '%X', oct("0b$bin");
   
return $chksum;
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
  my $res      = $paref->{res}     // '';
  my $verbose  = $paref->{verbose} // 4;

  ualarm(0);

  my $name           = $hash->{NAME};  
  $state             = (split "at ", $state)[0];
  $readings->{state} = $state;
  $verbose           = 3 if($readings->{state} =~ /error/xsi);

  Log3 ($name, $verbose, "$name - ".$readings->{state});
  
  if ($res) {
      Log3 ($name, 5, "$name - faulty data is printed out now: ");
      __resultLog ($hash, $res);
  }

  _closeSocket ($hash);

return;
}

###############################################################
#       eigene zusaätzliche Werte erstellen
###############################################################
sub additionalReadings {
    my $readings = shift;                # Referenz auf das Hash der zu erstellenden Readings

    my ($vmax, $vmin);

    $readings->{averageCellVolt} = sprintf "%.3f", $readings->{packVolt} / $readings->{packCellcount}                  if($readings->{packCellcount});
    $readings->{packSOC}         = sprintf "%.2f", ($readings->{packCapacityRemain} / $readings->{packCapacity} * 100) if($readings->{packCapacity});
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
    my $success  = shift;
    my $readings = shift;                # Referenz auf das Hash der zu erstellenden Readings

    readingsBeginUpdate ($hash);

    for my $rdg (keys %{$readings}) {
        next if(!defined $readings->{$rdg});
        readingsBulkUpdate ($hash, $rdg, $readings->{$rdg}) if($success || grep /^$rdg$/, @blackl);  
    }

    readingsEndUpdate ($hash, 1);

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
      next if(grep /^$reading$/, @blackl);              
      readingsDelete ($hash, $reading);
  }

return;
}

1;


=pod
=item device
=item summary Integration of Pylontech low voltage batteries via RS485 ethernet gateway
=item summary_DE Integration von Pylontech Niederspannungsbatterien über RS485-Ethernet-Gateway

=begin html

 <a id="PylonLowVoltage"></a>
 <h3>PylonLowVoltage</h3>
 <br>
 Module for integration of low voltage batteries with battery management system (BMS) of the manufacturer Pylontech via
 RS485/Ethernet gateway. Communication to the RS485 gateway takes place exclusively via an Ethernet connection.<br>
 The module has been successfully used so far with Pylontech batteries of the following types: <br>

 <ul>
  <li> US2000        </li>
  <li> US2000B Plus  </li>
  <li> US2000C       </li>
  <li> US2000 Plus   </li>
  <li> US3000        </li>
  <li> US3000C       </li>
  <li> US5000        </li>
 </ul>

 The following devices have been successfully used as RS485 Ethernet gateways to date: <br>
 <ul>
  <li> USR-TCP232-304 from the manufacturer USRiot </li>
  <li> Waveshare RS485 to Ethernet Converter       </li>
 </ul>

 In principle, any other RS485/Ethernet gateway should also be compatible.
 <br><br>

 <b>Requirements</b>
 <br><br>
 This module requires the Perl modules:
 <ul>
    <li>IO::Socket::INET    (apt-get install libio-socket-multicast-perl)                          </li>
    <li>IO::Socket::Timeout (Installation e.g. via the CPAN shell or the FHEM Installer module)    </li>
 </ul>

 The data format must be set on the RS485 gateway as follows:
 <br>

  <ul>
     <table>
     <colgroup> <col width="25%"> <col width="75%"> </colgroup>
        <tr><td> Start Bit </td><td>- 1 Bit          </td></tr>
        <tr><td> Data Bit  </td><td>- 8 Bit          </td></tr>
        <tr><td> Stop Bit  </td><td>- 1 Bit          </td></tr>
        <tr><td> Parity    </td><td>- without Parity </td></tr>
     </table>
  </ul>
  <br>
  
 <b>Example configuration of a Waveshare RS485 to Ethernet converter</b>
 <br><br>
 The converter's web interface offers several pages with settings. The relevant settings are shown below
 as an example. The assignment of a fixed IP address is assumed in advance.
 <br>

  <ul>
     <table>
     <colgroup> <col width="25%"> <col width="75%"> </colgroup>
        <tr><td> <b>Serial port settings</b>          </td><td>                                         </td></tr>
        <tr><td> - Baud Rate                          </td><td>: according to the battery setting       </td></tr>
        <tr><td> - Data Size                          </td><td>: 8 Bit                                  </td></tr>
        <tr><td> - Parity                             </td><td>: None                                   </td></tr>
        <tr><td> - Stop Bits                          </td><td>: 1                                      </td></tr>
        <tr><td> - Local Port Number                  </td><td>: freely selected                        </td></tr>
        <tr><td> - Work Mode                          </td><td>: TCP Server                             </td></tr>
        <tr><td> - Reset                              </td><td>: not set                                </td></tr>
        <tr><td> - Link                               </td><td>: set                                    </td></tr>
        <tr><td> - Index                              </td><td>: not set                                </td></tr>
        <tr><td> - Similar RCF2217                    </td><td>: set                                    </td></tr>
        <tr><td>                                      </td><td>                                         </td></tr>
        <tr><td> <b>Settings Expand Function</b>      </td><td>                                         </td></tr>
        <tr><td> - Heartbeat Packet Type              </td><td>: None                                   </td></tr>
        <tr><td> - Register Packet Type               </td><td>: None                                   </td></tr>
        <tr><td> - Short Connection                   </td><td>: not set                                </td></tr>
        <tr><td> - TCP Server-kick off old connection </td><td>: set                                    </td></tr>
        <tr><td> - Buffer Data before Connected       </td><td>: set                                    </td></tr>
        <tr><td> - UART Set Parameter                 </td><td>: not set                                </td></tr>
     </table>
  </ul>
  <br>

 <b>Limitations</b>
 <br>
 The module currently supports a maximum of 16 batteries (1 master + 15 slaves) in up to 7 groups. <br>
 The number of groups and batteries that can be realized depends on the products used. 
 Please refer to the manufacturer's instructions.
 <br><br>

 <a id="PylonLowVoltage-define"></a>
 <b>Definition</b>
 <ul>
  <code><b>define &lt;name&gt; PylonLowVoltage &lt;hostname/ip&gt;:&lt;port&gt; [&lt;bataddress&gt;]</b></code><br>
  <br>
  
  <b>Example:</b> <br>
  define Pylone1 PylonLowVoltage 192.168.2.86:9000 1 group=0 <br>
  <br>
  
  <li><b>hostname/ip:</b><br>
     Host name or IP address of the RS485/Ethernet gateway
  </li>

  <li><b>port:</b><br>
     Port number of the port configured in the RS485/Ethernet gateway
  </li>

  <li><b>bataddress:</b><br>
     Device address of the Pylontech battery. Several Pylontech batteries can be connected via a Pylontech-specific
     Link connection. The permissible number can be found in the respective Pylontech documentation. <br>
     The master battery in the network (with open link port 0 or to which the RS485 connection is connected) has the
     address 1, the next battery then has address 2 and so on.
     If no device address is specified, address 1 is used.
  </li>
  
  <li><b>group:</b><br>
     Optional group number of the battery stack. If group=0 or is not specified, the default configuration 
     “Single Group” is used. The group number can be 0 to 7.     
  </li>
  <br>
 </ul>

 <b>Mode of operation</b>
 <ul>
 Depending on the setting of the "Interval" attribute, the module cyclically reads values provided by the battery
 management system via the RS485 interface.
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
     Enables/disables the device definition.
   </li>
   <br>

   <a id="PylonLowVoltage-attr-interval"></a>
   <li><b>interval &lt;seconds&gt;</b><br>
     Interval of the data request from the battery in seconds. If "interval" is explicitly set to the value "0", there is
     no automatic data request.<br>
     (default: 30)
   </li>
   <br>

   <a id="PylonLowVoltage-attr-timeout"></a>
   <li><b>timeout &lt;seconds&gt;</b><br>
     Timeout for establishing the connection to the RS485 gateway. <br>
     (default: 0.5)

     <br><br>
     <b>Note</b>: If a timeout &gt;= 1 second is set, the module switches internally to the use of a parallel process
     (BlockingCall) so that write or read delays on the RS485 interface do not lead to blocking states in FHEM.
   </li>
   <br>

   <a id="PylonLowVoltage-attr-userBatterytype"></a>
   <li><b>userBatterytype</b><br>
     The automatically determined battery type (Reading batteryType) is replaced by the specified string.
   </li>
   <br>
   
   <a id="PylonLowVoltage-attr-waitTimeBetweenRS485Cmd"></a>
   <li><b>waitTimeBetweenRS485Cmd &lt;Sekunden&gt;</b><br>
     Waiting time between the execution of RS485 commands in seconds. <br>
     This parameter only has an effect if the “timeout” attribute is set to a value >= 1. <br>
     (default: 0.1)
   </li>
   <br>
   
 </ul>

 <a id="PylonLowVoltage-readings"></a>
 <b>Readings</b>
 <ul>
 <li><b>averageCellVolt</b><br>        Average cell voltage (V)                                                           </li>
 <li><b>bmsTemperature</b><br>         Temperature (°C) of the battery management system                                  </li>
 <li><b>cellTemperature_0104</b><br>   Temperature (°C) of cell packs 1 to 4                                              </li>
 <li><b>cellTemperature_0508</b><br>   Temperature (°C) of cell packs 5 to 8                                              </li>
 <li><b>cellTemperature_0912</b><br>   Temperature (°C) of the cell packs 9 to 12                                         </li>
 <li><b>cellTemperature_1315</b><br>   Temperature (°C) of the cell packs 13 to 15                                        </li>
 <li><b>cellTemperature_Pos_XX</b><br> Temperature (°C) of position XX (not further specified)                            </li>
 <li><b>cellVoltage_XX</b><br>         Cell voltage (V) of the cell pack XX. In the battery module "packCellcount"
                                       cell packs are connected in series. Each cell pack consists of single cells
                                       connected in parallel.                                                             </li>
 <li><b>chargeCurrentLimit</b><br>     current limit value for the charging current (A)                                   </li>
 <li><b>chargeEnable</b><br>           current flag loading allowed                                                       </li>
 <li><b>chargeFullRequest</b><br>      current flag charge battery module fully (from the mains if necessary)             </li>
 <li><b>chargeImmediatelySOCXX</b><br> current flag charge battery module immediately
                                       (05: SOC limit 5-9%, 09: SOC limit 9-13%)                                          </li>
 <li><b>chargeVoltageLimit</b><br>     current charge voltage limit (V) of the battery module                             </li>
 <li><b>dischargeCurrentLimit</b><br>  current limit value for the discharge current (A)                                  </li>
 <li><b>dischargeEnable</b><br>        current flag unloading allowed                                                     </li>
 <li><b>dischargeVoltageLimit</b><br>  current discharge voltage limit (V) of the battery module                          </li>

 <li><b>moduleSoftwareVersion_manufacture</b><br> Firmware version of the battery module                                  </li>

 <li><b>packAlarmInfo</b><br>          Alarm status (ok - battery module is OK, failure - there is a fault in the
                                       battery module)                                                                    </li>
 <li><b>packCapacity</b><br>           nominal capacity (Ah) of the battery module                                        </li>
 <li><b>packCapacityRemain</b><br>     current capacity (Ah) of the battery module                                        </li>
 <li><b>packCellcount</b><br>          Number of cell packs in the battery module                                         </li>
 <li><b>packCurrent</b><br>            current charge current (+) or discharge current (-) of the battery module (A)      </li>
 <li><b>packCycles</b><br>             Number of full cycles - The number of cycles is, to some extent, a measure of the
                                       wear and tear of the battery. A complete charge and discharge is counted as one
                                       cycle. If the battery is discharged and recharged 50%, it only counts as one
                                       half cycle. Pylontech specifies a lifetime of several 1000 cycles
                                       (see data sheet).                                                                  </li>
 <li><b>packImbalance</b><br>          current imbalance of voltage between the single cells of the
                                       battery module (%)                                                                 </li>
 <li><b>packPower</b><br>              current drawn (+) or delivered (-) power (W) of the battery module                 </li>
 <li><b>packSOC</b><br>                State of charge (%) of the battery module                                          </li>
 <li><b>packState</b><br>              current working status of the battery module                                       </li>
 <li><b>packVolt</b><br>               current voltage (V) of the battery module                                          </li>

 <li><b>paramCellHighVoltLimit</b><br>      System parameter upper voltage limit (V) of a cell                                 </li>
 <li><b>paramCellLowVoltLimit</b><br>       System parameter lower voltage limit (V) of a cell (alarm limit)                   </li>
 <li><b>paramCellUnderVoltLimit</b><br>     System parameter undervoltage limit (V) of a cell (protection limit)               </li>
 <li><b>paramChargeCurrentLimit</b><br>     System parameter charging current limit (A) of the battery module                  </li>
 <li><b>paramChargeHighTempLimit</b><br>    System parameter upper temperature limit (°C) up to which the battery charges      </li>
 <li><b>paramChargeLowTempLimit</b><br>     System parameter lower temperature limit (°C) up to which the battery charges      </li>
 <li><b>paramDischargeCurrentLimit</b><br>  System parameter discharge current limit (A) of the battery module                 </li>
 <li><b>paramDischargeHighTempLimit</b><br> System parameter upper temperature limit (°C) up to which the battery discharges   </li>
 <li><b>paramDischargeLowTempLimit</b><br>  System parameter lower temperature limit (°C) up to which the battery discharges   </li>
 <li><b>paramModuleHighVoltLimit</b><br>    System parameter upper voltage limit (V) of the battery module                     </li>
 <li><b>paramModuleLowVoltLimit</b><br>     System parameter lower voltage limit (V) of the battery module (alarm limit)       </li>
 <li><b>paramModuleUnderVoltLimit</b><br>   System parameter undervoltage limit (V) of the battery module (protection limit)   </li>
 <li><b>protocolVersion</b><br>             PYLON low voltage RS485 protocol version                                           </li>
 <li><b>serialNumber</b><br>                Serial number                                                                      </li>
 </ul>
 <br><br>

=end html
=begin html_DE

 <a id="PylonLowVoltage"></a>
 <h3>PylonLowVoltage</h3>
 <br>
 Modul zur Einbindung von Niedervolt-Batterien mit Batteriemanagmentsystem (BMS) des Herstellers Pylontech über RS485 via
 RS485/Ethernet-Gateway. Die Kommunikation zum RS485-Gateway erfolgt ausschließlich über eine Ethernet-Verbindung.<br>
 Das Modul wurde bisher erfolgreich mit Pylontech Batterien folgender Typen eingesetzt: <br>

 <ul>
  <li> US2000        </li>
  <li> US2000B Plus  </li>
  <li> US2000C       </li>
  <li> US2000 Plus   </li>
  <li> US3000        </li>
  <li> US3000C       </li>
  <li> US5000        </li>
 </ul>

 Als RS485-Ethernet-Gateways wurden bisher folgende Geräte erfolgreich eingesetzt: <br>
 <ul>
  <li> USR-TCP232-304 des Herstellers USRiot </li>
  <li> Waveshare RS485 to Ethernet Converter </li>
 </ul>

 Prinzipiell sollte auch jedes andere RS485/Ethernet-Gateway kompatibel sein.
 <br><br>

 <b>Voraussetzungen</b>
 <br><br>
 Dieses Modul benötigt die Perl-Module:
 <ul>
    <li>IO::Socket::INET    (apt-get install libio-socket-multicast-perl)                          </li>
    <li>IO::Socket::Timeout (Installation z.B. über die CPAN-Shell oder das FHEM Installer Modul)  </li>
 </ul>

 Das Datenformat muß auf dem RS485 Gateway wie folgt eingestellt werden:
 <br>

  <ul>
     <table>
     <colgroup> <col width="25%"> <col width="75%"> </colgroup>
        <tr><td> Start Bit </td><td>- 1 Bit          </td></tr>
        <tr><td> Data Bit  </td><td>- 8 Bit          </td></tr>
        <tr><td> Stop Bit  </td><td>- 1 Bit          </td></tr>
        <tr><td> Parity    </td><td>- ohne Parität   </td></tr>
     </table>
  </ul>
  <br>
  
 <b>Beispielkonfiguration eines Waveshare RS485 to Ethernet Converters</b>
 <br><br>
 Das Webinterface des Konverters bietet mehrere Seiten mit Einstellungen an. Die relevanten Einstellungen sind nachfolgend
 beispielhaft gezeigt. Die Zuweisung einer festen IP-Adresse wird vorab vorausgesetzt.
 <br>

  <ul>
     <table>
     <colgroup> <col width="25%"> <col width="75%"> </colgroup>
        <tr><td> <b>Einstellungen Serial Port</b>     </td><td>                                         </td></tr>
        <tr><td> - Baud Rate                          </td><td>: entsprechend Einstellung der Batterie  </td></tr>
        <tr><td> - Data Size                          </td><td>: 8 Bit                                  </td></tr>
        <tr><td> - Parity                             </td><td>: None                                   </td></tr>
        <tr><td> - Stop Bits                          </td><td>: 1                                      </td></tr>
        <tr><td> - Local Port Number                  </td><td>: frei gewählt                           </td></tr>
        <tr><td> - Work Mode                          </td><td>: TCP Server                             </td></tr>
        <tr><td> - Reset                              </td><td>: nicht gesetzt                          </td></tr>
        <tr><td> - Link                               </td><td>: gesetzt                                </td></tr>
        <tr><td> - Index                              </td><td>: nicht gesetzt                          </td></tr>
        <tr><td> - Similar RCF2217                    </td><td>: gesetzt                                </td></tr>
        <tr><td>                                      </td><td>                                         </td></tr>
        <tr><td> <b>Einstellungen Expand Function</b> </td><td>                                         </td></tr>
        <tr><td> - Heartbeat Packet Type              </td><td>: None                                   </td></tr>
        <tr><td> - Register Packet Type               </td><td>: None                                   </td></tr>
        <tr><td> - Short Connection                   </td><td>: nicht gesetzt                          </td></tr>
        <tr><td> - TCP Server-kick off old connection </td><td>: gesetzt                                </td></tr>
        <tr><td> - Buffer Data before Connected       </td><td>: gesetzt                                </td></tr>
        <tr><td> - UART Set Parameter                 </td><td>: nicht gesetzt                          </td></tr>
     </table>
  </ul>
  <br>

 <b>Einschränkungen</b>
 <br>
 Das Modul unterstützt zur Zeit maximal 16 Batterien (1 Master + 15 Slaves) in bis zu 7 Gruppen. <br>
 Die realisierbare Gruppen- und Batterieanzahl ist von den eingesetzen Produkten abhängig. Dazu bitte die Hinweise des 
 Herstellers beachten.
 <br><br>

 <a id="PylonLowVoltage-define"></a>
 <b>Definition</b>
 <ul>
  <code><b>define &lt;name&gt; PylonLowVoltage &lt;hostname/ip&gt;:&lt;port&gt; [&lt;bataddress&gt;] [group=&lt;N&gt;]</b></code><br>
  <br>
  
  <b>Beispiel:</b> <br>
  define Pylone1 PylonLowVoltage 192.168.2.86:9000 1 group=0 <br>
  <br>
  
  <li><b>hostname/ip:</b><br>
     Hostname oder IP-Adresse des RS485/Ethernet-Gateways
  </li>

  <li><b>port:</b><br>
     Port-Nummer des im RS485/Ethernet-Gateways konfigurierten Ports
  </li>

  <li><b>bataddress:</b><br>
     Optionale Geräteadresse der Pylontech Batterie. Es können mehrere Pylontech Batterien über eine Pylontech-spezifische
     Link-Verbindung verbunden werden. Die zulässige Anzahl ist der jeweiligen Pylontech Dokumentation zu entnehmen. <br>
     Die Master Batterie im Verbund (mit offenem Link Port 0 bzw. an der die RS485-Verbindung angeschlossen ist) hat die
     Adresse 1, die nächste Batterie hat dann die Adresse 2 und so weiter.
     Ist keine Geräteadresse angegeben, wird die Adresse 1 verwendet.
  </li>
  
  <li><b>group:</b><br>
     Optionale Gruppennummer des Batteriestacks. Ist group=0 oder nicht angegeben, wird die Standardkonfiguration 
     "Single Group" verwendet. Die Gruppennummer kann 0 bis 7 sein.     
  </li>
  <br>
 </ul>

 <b>Arbeitsweise</b>
 <ul>
 Das Modul liest entsprechend der Einstellung des Attributes "interval" zyklisch Werte aus, die das
 Batteriemanagementsystem über die RS485-Schnittstelle zur Verfügung stellt.
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
     Aktiviert/deaktiviert die Gerätedefinition.
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

     <br><br>
     <b>Hinweis</b>: Wird ein Timeout &gt;= 1 Sekunde eingestellt, schaltet das Modul intern auf die Verwendung eines
     Parallelprozesses (BlockingCall) um damit Schreib- bzw. Leseverzögerungen auf dem RS485 Interface nicht zu
     blockierenden Zuständen in FHEM führen.
   </li>
   <br>

   <a id="PylonLowVoltage-attr-userBatterytype"></a>
   <li><b>userBatterytype</b><br>
     Der automatisch ermittelte Batterietyp (Reading batteryType) wird durch die angegebene Zeichenfolge ersetzt.
   </li>
   <br>
   
   <a id="PylonLowVoltage-attr-waitTimeBetweenRS485Cmd"></a>
   <li><b>waitTimeBetweenRS485Cmd &lt;Sekunden&gt;</b><br>
     Wartezeit zwischen der Ausführung von RS485 Befehlen in Sekunden. <br>
     Dieser Parameter hat nur Auswirkung wenn das Attribut "timeout" auf einen Wert >= 1 gesetzt ist. <br>
     (default: 0.1)
   </li>
   <br>
   
 </ul>

 <a id="PylonLowVoltage-readings"></a>
 <b>Readings</b>
 <ul>
 <li><b>averageCellVolt</b><br>        mittlere Zellenspannung (V)                                                        </li>
 <li><b>bmsTemperature</b><br>         Temperatur (°C) des Batteriemanagementsystems                                      </li>
 <li><b>cellTemperature_0104</b><br>   Temperatur (°C) der Zellenpacks 1 bis 4                                            </li>
 <li><b>cellTemperature_0508</b><br>   Temperatur (°C) der Zellenpacks 5 bis 8                                            </li>
 <li><b>cellTemperature_0912</b><br>   Temperatur (°C) der Zellenpacks 9 bis 12                                           </li>
 <li><b>cellTemperature_1315</b><br>   Temperatur (°C) der Zellenpacks 13 bis 15                                          </li>
 <li><b>cellTemperature_Pos_XX</b><br> Temperatur (°C) der Position XX (nicht näher spezifiziert)                         </li>
 <li><b>cellVoltage_XX</b><br>         Zellenspannung (V) des Zellenpacks XX. In dem Batteriemodul sind "packCellcount"
                                       Zellenpacks in Serie geschaltet verbaut. Jedes Zellenpack besteht aus parallel
                                       geschalten Einzelzellen.                                                           </li>
 <li><b>chargeCurrentLimit</b><br>     aktueller Grenzwert für den Ladestrom (A)                                          </li>
 <li><b>chargeEnable</b><br>           aktuelles Flag Laden erlaubt                                                       </li>
 <li><b>chargeFullRequest</b><br>      aktuelles Flag Batteriemodul voll laden (notfalls aus dem Netz)                    </li>
 <li><b>chargeImmediatelySOCXX</b><br> aktuelles Flag Batteriemodul sofort laden
                                       (05: SOC Grenze 5-9%, 09: SOC Grenze 9-13%)                                        </li>
 <li><b>chargeVoltageLimit</b><br>     aktuelle Ladespannungsgrenze (V) des Batteriemoduls                                </li>
 <li><b>dischargeCurrentLimit</b><br>  aktueller Grenzwert für den Entladestrom (A)                                       </li>
 <li><b>dischargeEnable</b><br>        aktuelles Flag Entladen erlaubt                                                    </li>
 <li><b>dischargeVoltageLimit</b><br>  aktuelle Entladespannungsgrenze (V) des Batteriemoduls                             </li>

 <li><b>moduleSoftwareVersion_manufacture</b><br> Firmware Version des Batteriemoduls                                     </li>

 <li><b>packAlarmInfo</b><br>          Alarmstatus (ok - Batterienmodul ist in Ordnung, failure - im Batteriemodul liegt
                                       eine Störung vor)                                                                  </li>
 <li><b>packCapacity</b><br>           nominale Kapazität (Ah) des Batteriemoduls                                         </li>
 <li><b>packCapacityRemain</b><br>     aktuelle Kapazität (Ah) des Batteriemoduls                                         </li>
 <li><b>packCellcount</b><br>          Anzahl der Zellenpacks im Batteriemodul                                            </li>
 <li><b>packCurrent</b><br>            aktueller Ladestrom (+) bzw. Entladstrom (-) des Batteriemoduls (A)                </li>
 <li><b>packCycles</b><br>             Anzahl der Vollzyklen - Die Anzahl der Zyklen ist in gewisserweise ein Maß für den
                                       Verschleiß der Batterie. Eine komplettes Laden und Entladen wird als ein Zyklus
                                       gewertet. Wird die Batterie 50% entladen und wieder aufgeladen, zählt das nur als ein
                                       halber Zyklus. Pylontech gibt eine Lebensdauer von mehreren 1000 Zyklen an
                                       (siehe Datenblatt).                                                                </li>
 <li><b>packImbalance</b><br>          aktuelles Ungleichgewicht der Spannung zwischen den Einzelzellen des
                                       Batteriemoduls (%)                                                                 </li>
 <li><b>packPower</b><br>              aktuell bezogene (+) bzw. gelieferte (-) Leistung (W) des Batteriemoduls           </li>
 <li><b>packSOC</b><br>                Ladezustand (%) des Batteriemoduls                                                 </li>
 <li><b>packState</b><br>              aktueller Arbeitsstatus des Batteriemoduls                                         </li>
 <li><b>packVolt</b><br>               aktuelle Spannung (V) des Batteriemoduls                                           </li>

 <li><b>paramCellHighVoltLimit</b><br>      Systemparameter obere Spannungsgrenze (V) einer Zelle                         </li>
 <li><b>paramCellLowVoltLimit</b><br>       Systemparameter untere Spannungsgrenze (V) einer Zelle (Alarmgrenze)          </li>
 <li><b>paramCellUnderVoltLimit</b><br>     Systemparameter Unterspannungsgrenze (V) einer Zelle (Schutzgrenze)           </li>
 <li><b>paramChargeCurrentLimit</b><br>     Systemparameter Ladestromgrenze (A) des Batteriemoduls                        </li>
 <li><b>paramChargeHighTempLimit</b><br>    Systemparameter obere Temperaturgrenze (°C) bis zu der die Batterie lädt      </li>
 <li><b>paramChargeLowTempLimit</b><br>     Systemparameter untere Temperaturgrenze (°C) bis zu der die Batterie lädt     </li>
 <li><b>paramDischargeCurrentLimit</b><br>  Systemparameter Entladestromgrenze (A) des Batteriemoduls                     </li>
 <li><b>paramDischargeHighTempLimit</b><br> Systemparameter obere Temperaturgrenze (°C) bis zu der die Batterie entlädt   </li>
 <li><b>paramDischargeLowTempLimit</b><br>  Systemparameter untere Temperaturgrenze (°C) bis zu der die Batterie entlädt  </li>
 <li><b>paramModuleHighVoltLimit</b><br>    Systemparameter obere Spannungsgrenze (V) des Batteriemoduls                  </li>
 <li><b>paramModuleLowVoltLimit</b><br>     Systemparameter untere Spannungsgrenze (V) des Batteriemoduls (Alarmgrenze)   </li>
 <li><b>paramModuleUnderVoltLimit</b><br>   Systemparameter Unterspannungsgrenze (V) des Batteriemoduls (Schutzgrenze)    </li>
 <li><b>protocolVersion</b><br>             PYLON low voltage RS485 Prokollversion                                        </li>
 <li><b>serialNumber</b><br>                Seriennummer                                                                  </li>
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
        "Carp": 0,
        "Blocking": 0,
        "Storable": 0,
        "MIME::Base64": 0,
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