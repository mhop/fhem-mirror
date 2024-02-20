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
use Time::HiRes qw(gettimeofday ualarm);
use IO::Socket::INET;
use Errno qw(ETIMEDOUT EWOULDBLOCK);
use Scalar::Util qw(looks_like_number);
use Carp qw(croak carp);
use Blocking;
use MIME::Base64;

eval "use FHEM::Meta;1"                or my $modMetaAbsent = 1;                             ## no critic 'eval'
eval "use IO::Socket::Timeout;1"       or my $iostAbsent    = 'IO::Socket::Timeout';         ## no critic 'eval'
eval "use Storable qw(freeze thaw);1;" or my $storabs       = 'Storable';                    ## no critic 'eval'

use FHEM::SynoModules::SMUtils qw(moduleVersion);                                            # Hilfsroutinen Modul
#use Data::Dumper;

no if $] >= 5.017011, warnings => 'experimental::smartmatch';

# Run before module compilation
BEGIN {
  # Import from main::
  GP_Import(
      qw(
          AttrVal
          AttrNum
          BlockingCall
          BlockingKill
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

my %fns1 = (                                                                  # Abrufklasse statische Werte:
  1 => { fn => \&_callSerialNumber     },                                     #   serialNumber
  2 => { fn => \&_callManufacturerInfo },                                     #   manufacturerInfo
  3 => { fn => \&_callProtocolVersion  },                                     #   protocolVersion
  4 => { fn => \&_callSoftwareVersion  },                                     #   softwareVersion
  5 => { fn => \&_callSystemParameters },                                     #   systemParameters
);

my %fns2 = (                                                                  # Abrufklasse dynamische Werte:
  1 => { fn => \&_callAlarmInfo           },                                  #   alarmInfo
  2 => { fn => \&_callChargeManagmentInfo },                                  #   chargeManagmentInfo
  3 => { fn => \&_callAnalogValue         },                                  #   analogValue
  
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
# ADR: n=Batterienummer (2-x), m=Group Nr. (0-8), ADR = 0x0n + (0x10 * m) -> f. Batterie 1 = 0x02 + (0x10 * 0) = 0x02
# CID1: Kommando spezifisch, hier 46H
# CID2: Kommando spezifisch, hier 93H
# LENGTH: LENID + LCHKSUM -> Pylon LFP V2.8 Doku
# INFO: muß hier mit ADR übereinstimmen
# CHKSUM (als HEX! addieren): 32+30+30+41+34+36+39+33+45+30+30+32+30+41 = 02F1H -> modulo 65536 = 02F1H -> bitweise invert = 1111 1101 0000 1110 -> +1 = 1111 1101 0000 1111 -> FD0FH
#
# SOI  VER    ADR   CID1  CID2      LENGTH     INFO    CHKSUM
#  ~    20    0A      46    93     E0    02    0A      FD   0F
# 7E  32 30  30 41  34 36 39 33  45 30 30 32  30 41  
#
my %hrsnb = (                                                        # Codierung Abruf serialNumber, mlen = Mindestlänge Antwortstring
  1 => { cmd => "~20024693E00202FD2D\x{0d}", mlen => 52 },
  2 => { cmd => "~20034693E00203FD2B\x{0d}", mlen => 52 },
  3 => { cmd => "~20044693E00204FD29\x{0d}", mlen => 52 },
  4 => { cmd => "~20054693E00205FD27\x{0d}", mlen => 52 },
  5 => { cmd => "~20064693E00206FD25\x{0d}", mlen => 52 },
  6 => { cmd => "~20074693E00207FD23\x{0d}", mlen => 52 },
  7 => { cmd => "~20084693E00208FD21\x{0d}", mlen => 52 },
  8 => { cmd => "~20094693E00209FD1F\x{0d}", mlen => 52 },           
  9 => { cmd => "~200A4693E0020AFD0F\x{0d}", mlen => 52 },
 10 => { cmd => "~200B4693E0020BFD0D\x{0d}", mlen => 52 },
 11 => { cmd => "~200C4693E0020CFD0B\x{0d}", mlen => 52 },
 12 => { cmd => "~200D4693E0020DFD09\x{0d}", mlen => 52 },
 13 => { cmd => "~200E4693E0020EFD07\x{0d}", mlen => 52 },
 14 => { cmd => "~200F4693E0020FFD05\x{0d}", mlen => 52 },
 
);

# ADR: n=Batterienummer (2-x), m=Group Nr. (0-8), ADR = 0x0n + (0x10 * m) -> f. Batterie 1 = 0x02 + (0x10 * 0) = 0x02
# CID1: Kommando spezifisch, hier 46H
# CID2: Kommando spezifisch, hier 51H
# LENGTH: LENID + LCHKSUM -> Pylon LFP V3.3 Doku
# LENID = 0 -> LENID = 0000B + 0000B + 0000B = 0000B -> modulo 16 -> 0000B -> bitweise invert = 1111 -> +1 = 0001 0000 -> LCHKSUM = 0000B -> LENGTH = 0000 0000 0000 0000 -> 0000H
# wenn LENID = 0, dann ist INFO empty (Doku LFP V3.3 S.8)
# CHKSUM (als HEX! addieren): 32+30+30+41+34+36+35+31+30+30+30+30 = 0263H -> modulo 65536 = 0263H -> bitweise invert = 1111 1101 1001 1100 -> +1 = 1111 1101 1001 1101  = FD9DH
#
# SOI  VER    ADR   CID1  CID2      LENGTH    INFO     CHKSUM
#  ~    20    0A      46    51     00    00   empty    FD  9D
# 7E  32 30  30 41  34 36 35 31  30 30 30 30   - -   
#
my %hrmfi = (                                                        # Codierung Abruf manufacturerInfo, mlen = Mindestlänge Antwortstring
  1 => { cmd => "~200246510000FDAC\x{0d}", mlen => 82 },
  2 => { cmd => "~200346510000FDAB\x{0d}", mlen => 82 },
  3 => { cmd => "~200446510000FDAA\x{0d}", mlen => 82 },
  4 => { cmd => "~200546510000FDA9\x{0d}", mlen => 82 },
  5 => { cmd => "~200646510000FDA8\x{0d}", mlen => 82 },
  6 => { cmd => "~200746510000FDA7\x{0d}", mlen => 82 },
  7 => { cmd => "~200846510000FDA6\x{0d}", mlen => 82 },
  8 => { cmd => "~200946510000FDA5\x{0d}", mlen => 82 },
  9 => { cmd => "~200A46510000FD9D\x{0d}", mlen => 82 },
 10 => { cmd => "~200B46510000FD9C\x{0d}", mlen => 82 },
 11 => { cmd => "~200C46510000FD9B\x{0d}", mlen => 82 },
 12 => { cmd => "~200D46510000FD9A\x{0d}", mlen => 82 },
 13 => { cmd => "~200E46510000FD8F\x{0d}", mlen => 82 },
 14 => { cmd => "~200F46510000FD8E\x{0d}", mlen => 82 },
);

# ADR: n=Batterienummer (2-x), m=Group Nr. (0-8), ADR = 0x0n + (0x10 * m) -> f. Batterie 1 = 0x02 + (0x10 * 0) = 0x02
# CID1: Kommando spezifisch, hier 46H
# CID2: Kommando spezifisch, hier 4FH
# LENGTH: LENID + LCHKSUM -> Pylon LFP V3.3 Doku
# LENID = 0 -> LENID = 0000B + 0000B + 0000B = 0000B -> modulo 16 -> 0000B -> bitweise invert = 1111 -> +1 = 0001 0000 -> LCHKSUM = 0000B -> LENGTH = 0000 0000 0000 0000 -> 0000H
# wenn LENID = 0, dann ist INFO empty (Doku LFP V3.3 S.8)
# CHKSUM (als HEX! addieren): 30+30+30+41+34+36+34+46+30+30+30+30 = 0275H -> modulo 65536 = 0275H -> bitweise invert = 1111 1101 1000 1010 -> +1 = 1111 1101 1000 1011 -> FD8BH
#
# SOI  VER    ADR   CID1   CID2      LENGTH    INFO     CHKSUM
#  ~    00    0A      46    4F      00    00   empty    FD  8B
# 7E  30 30  30 41  34 36  34 46  30 30 30 30   - -   
#
my %hrprt = (                                                        # Codierung Abruf protocolVersion, mlen = Mindestlänge Antwortstring
  1 => { cmd => "~0002464F0000FD9A\x{0d}", mlen => 18 },
  2 => { cmd => "~0003464F0000FD99\x{0d}", mlen => 18 },
  3 => { cmd => "~0004464F0000FD98\x{0d}", mlen => 18 },
  4 => { cmd => "~0005464F0000FD97\x{0d}", mlen => 18 },
  5 => { cmd => "~0006464F0000FD96\x{0d}", mlen => 18 },
  6 => { cmd => "~0007464F0000FD95\x{0d}", mlen => 18 },
  7 => { cmd => "~0008464F0000FD94\x{0d}", mlen => 18 },
  8 => { cmd => "~0009464F0000FD93\x{0d}", mlen => 18 },
  9 => { cmd => "~000A464F0000FD8B\x{0d}", mlen => 18 },
 10 => { cmd => "~000B464F0000FD8A\x{0d}", mlen => 18 },
 11 => { cmd => "~000C464F0000FD89\x{0d}", mlen => 18 },
 12 => { cmd => "~000D464F0000FD88\x{0d}", mlen => 18 },
 13 => { cmd => "~000E464F0000FD87\x{0d}", mlen => 18 },
 14 => { cmd => "~000F464F0000FD86\x{0d}", mlen => 18 },
);

# CHKSUM (als HEX! addieren): 32+30+30+41+34+36+39+36+45+30+30+32+30+41 = 02F4H -> modulo 65536 = 02F4H -> bitweise invert = 1111 1101 0000 1011 -> +1 1111 1101 0000 1100 = FD0CH
#
# SOI  VER    ADR   CID1  CID2      LENGTH     INFO    CHKSUM
#  ~    20    0A      46    96     E0    02    0A      FD  0C
# 7E  32 30  30 41  34 36 39 36  45 30 30 32  30 41  
#

my %hrswv = (                                                        # Codierung Abruf softwareVersion
  1 => { cmd => "~20024696E00202FD2A\x{0d}", mlen => 30 },
  2 => { cmd => "~20034696E00203FD28\x{0d}", mlen => 30 },
  3 => { cmd => "~20044696E00204FD26\x{0d}", mlen => 30 },
  4 => { cmd => "~20054696E00205FD24\x{0d}", mlen => 30 },
  5 => { cmd => "~20064696E00206FD22\x{0d}", mlen => 30 },
  6 => { cmd => "~20074696E00207FD20\x{0d}", mlen => 30 },
  7 => { cmd => "~20084696E00208FD1E\x{0d}", mlen => 30 },
  8 => { cmd => "~20094696E00209FD1C\x{0d}", mlen => 30 },
  9 => { cmd => "~200A4696E0020AFD0C\x{0d}", mlen => 30 },
 10 => { cmd => "~200B4696E0020BFD0A\x{0d}", mlen => 30 },
 11 => { cmd => "~200C4696E0020CFD08\x{0d}", mlen => 30 },
 12 => { cmd => "~200D4696E0020DFD06\x{0d}", mlen => 30 },
 13 => { cmd => "~200E4696E0020EFD04\x{0d}", mlen => 30 },
 14 => { cmd => "~200F4696E0020FFD02\x{0d}", mlen => 30 },
);

# CHKSUM (als HEX! addieren): 32+30+30+41+34+36+34+34+45+30+30+32+30+41 = 02EDH -> modulo 65536 = 02EDH -> bitweise invert = 1111 1101 0001 0010 -> +1 1111 1101 0001 0011 = FD13H
#
# SOI  VER    ADR   CID1  CID2      LENGTH     INFO    CHKSUM
#  ~    20    0A      46    44     E0    02    0A      FD  13
# 7E  32 30  30 41  34 36 34 34  45 30 30 32  30 41  
#

my %hralm = (                                                        # Codierung Abruf alarmInfo
  1 => { cmd => "~20024644E00202FD31\x{0d}", mlen => 82 },
  2 => { cmd => "~20034644E00203FD2F\x{0d}", mlen => 82 },
  3 => { cmd => "~20044644E00204FD2D\x{0d}", mlen => 82 },
  4 => { cmd => "~20054644E00205FD2B\x{0d}", mlen => 82 },
  5 => { cmd => "~20064644E00206FD29\x{0d}", mlen => 82 },
  6 => { cmd => "~20074644E00207FD27\x{0d}", mlen => 82 },
  7 => { cmd => "~20084644E00208FD25\x{0d}", mlen => 82 },
  8 => { cmd => "~20094644E00209FD23\x{0d}", mlen => 82 },
  9 => { cmd => "~200A4644E0020AFD13\x{0d}", mlen => 82 },
 10 => { cmd => "~200B4644E0020BFD11\x{0d}", mlen => 82 },
 11 => { cmd => "~200C4644E0020CFD0F\x{0d}", mlen => 82 },
 12 => { cmd => "~200D4644E0020DFD0D\x{0d}", mlen => 82 },
 13 => { cmd => "~200E4644E0020EFD0B\x{0d}", mlen => 82 },
 14 => { cmd => "~200F4644E0020FFCFE\x{0d}", mlen => 82 },
);

# CHKSUM (als HEX! addieren): 32+30+30+41+34+36+34+37+45+30+30+32+30+41 = 02F0H -> modulo 65536 = 02F0H -> bitweise invert = 1111 1101 0000 1111 -> +1 1111 1101 0001 0000 = FD10H
#
# SOI  VER    ADR   CID1  CID2      LENGTH     INFO    CHKSUM
#  ~    20    0A      46    47     E0    02    0A      FD  10
# 7E  32 30  30 41  34 36 34 37  45 30 30 32  30 41  
#

my %hrspm = (                                                        # Codierung Abruf Systemparameter
  1 => { cmd => "~20024647E00202FD2E\x{0d}", mlen => 68 },
  2 => { cmd => "~20034647E00203FD2C\x{0d}", mlen => 68 },
  3 => { cmd => "~20044647E00204FD2A\x{0d}", mlen => 68 },
  4 => { cmd => "~20054647E00205FD28\x{0d}", mlen => 68 },
  5 => { cmd => "~20064647E00206FD26\x{0d}", mlen => 68 },
  6 => { cmd => "~20074647E00207FD24\x{0d}", mlen => 68 },
  7 => { cmd => "~20084647E00208FD22\x{0d}", mlen => 68 },
  8 => { cmd => "~20094647E00209FD20\x{0d}", mlen => 68 },
  9 => { cmd => "~200A4647E0020AFD10\x{0d}", mlen => 68 },
 10 => { cmd => "~200B4647E0020BFD0E\x{0d}", mlen => 68 },
 11 => { cmd => "~200C4647E0020CFD0C\x{0d}", mlen => 68 },
 12 => { cmd => "~200D4647E0020DFD0A\x{0d}", mlen => 68 },
 13 => { cmd => "~200E4647E0020EFD08\x{0d}", mlen => 68 },
 14 => { cmd => "~200F4647E0020FFD06\x{0d}", mlen => 68 },
);

# CHKSUM (als HEX! addieren): 32+30+30+41+34+36+39+32+45+30+30+32+30+41 = 02F0H -> modulo 65536 = 02F0H -> bitweise invert = 1111 1101 0000 1111 -> +1 1111 1101 0001 0000 = FD10H
#
# SOI  VER    ADR   CID1  CID2      LENGTH     INFO    CHKSUM
#  ~    20    0A      46    92     E0    02    0A      FD  10
# 7E  32 30  30 41  34 36 39 32  45 30 30 32  30 41  
#

my %hrcmi = (                                                        # Codierung Abruf chargeManagmentInfo
  1 => { cmd => "~20024692E00202FD2E\x{0d}", mlen => 38 },
  2 => { cmd => "~20034692E00203FD2C\x{0d}", mlen => 38 },
  3 => { cmd => "~20044692E00204FD2A\x{0d}", mlen => 38 },
  4 => { cmd => "~20054692E00205FD28\x{0d}", mlen => 38 },
  5 => { cmd => "~20064692E00206FD26\x{0d}", mlen => 38 },
  6 => { cmd => "~20074692E00207FD24\x{0d}", mlen => 38 },
  7 => { cmd => "~20084692E00208FD22\x{0d}", mlen => 38 },
  8 => { cmd => "~20094692E00209FD20\x{0d}", mlen => 38 },
  9 => { cmd => "~200A4692E0020AFD10\x{0d}", mlen => 38 },
 10 => { cmd => "~200B4692E0020BFD0E\x{0d}", mlen => 38 },
 11 => { cmd => "~200C4692E0020CFD0C\x{0d}", mlen => 38 },
 12 => { cmd => "~200D4692E0020DFD0A\x{0d}", mlen => 38 },
 13 => { cmd => "~200E4692E0020EFD08\x{0d}", mlen => 38 },
 14 => { cmd => "~200F4692E0020FFD06\x{0d}", mlen => 38 },
);

# ADR: n=Batterienummer (2-x), m=Group Nr. (0-8), ADR = 0x0n + (0x10 * m) -> f. Batterie 1 = 0x02 + (0x10 * 0) = 0x02
# CID1: Kommando spezifisch, hier 46H
# CID2: Kommando spezifisch, hier 42H                                                                                                              LCHK|    LENID
# LENGTH: LENID + LCHKSUM -> Pylon LFP V3.3 Doku                                                                                                   ---- --------------
# LENID = 02H -> LENID = 0000B + 0000B + 0010B = 0010B -> modulo 16 -> 0010B -> bitweise invert = 1101 -> +1 = 1110 -> LCHKSUM = 1110B -> LENGTH = 1110 0000 0000 0010 -> E002H
# wenn LENID = 0, dann ist INFO empty (Doku LFP V3.3 S.8)
# CHKSUM (als HEX! addieren): 32+30+30+41+34+36+34+32+45+30+30+32+30+41 = 02EBH -> modulo 65536 = 02EBH -> bitweise invert = 1111 1101 0001 0100 -> +1 1111 1101 0001 0101 = FD15H
#
# SOI  VER    ADR   CID1   CID2      LENGTH    INFO     CHKSUM
#  ~    20    0A     46     42      E0    02    0A      FD  15
# 7E  32 30  30 41  34 36  34 32  45 30 30 32  30 41  
#
my %hrcmn = (                                                        # Codierung Abruf analogValue
  1 => { cmd => "~20024642E00202FD33\x{0d}", mlen => 128 },
  2 => { cmd => "~20034642E00203FD31\x{0d}", mlen => 128 },
  3 => { cmd => "~20044642E00204FD2F\x{0d}", mlen => 128 },
  4 => { cmd => "~20054642E00205FD2D\x{0d}", mlen => 128 },
  5 => { cmd => "~20064642E00206FD2B\x{0d}", mlen => 128 },
  6 => { cmd => "~20074642E00207FD29\x{0d}", mlen => 128 },
  7 => { cmd => "~20084642E00208FD27\x{0d}", mlen => 128 },
  8 => { cmd => "~20094642E00209FD25\x{0d}", mlen => 128 },
  9 => { cmd => "~200A4642E0020AFD15\x{0d}", mlen => 128 },
 10 => { cmd => "~200B4642E0020BFD13\x{0d}", mlen => 128 },
 11 => { cmd => "~200C4642E0020CFD11\x{0d}", mlen => 128 },
 12 => { cmd => "~200D4642E0020DFD0F\x{0d}", mlen => 128 },
 13 => { cmd => "~200E4642E0020EFD0D\x{0d}", mlen => 128 },
 14 => { cmd => "~200F4642E0020FFD0B\x{0d}", mlen => 128 },
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

  if ($storabs) {
      my $err = "Perl module >$storabs< is missing. You have to install this perl module.";
      Log3 ($name, 1, "$name - ERROR - $err");
      return "Error: $err";
  }

  $hash->{HELPER}{MODMETAABSENT} = 1 if($modMetaAbsent);                           # Modul Meta.pm nicht vorhanden
  ($hash->{HOST}, $hash->{PORT}) = split ":", $args[2];
  $hash->{BATADDRESS}            = $args[3] // 1;

  if ($hash->{BATADDRESS} !~ /^([1-9]{1}|1[0-4])$/xs) {
      return "Define: bataddress must be a value between 1 and 14";
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

  if ($aName eq 'interval') {
      if (!looks_like_number($aVal)) {
          return qq{The value for $aName is invalid, it must be numeric!};
      }

      InternalTimer(gettimeofday()+1.0, "FHEM::PylonLowVoltage::manageUpdate", $hash, 0);
  }

  if ($aName eq 'userBatterytype') {
      $hash->{HELPER}{AGE1} = 0;
      InternalTimer(gettimeofday()+1.0, "FHEM::PylonLowVoltage::manageUpdate", $hash, 0);
  }

  if ($aName eq 'timeout') {
      if (!looks_like_number($aVal)) {
          return qq{The value for $aName is invalid, it must be numeric!};
      }
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

  if(!$init_done) {
      InternalTimer(gettimeofday() + 2, "FHEM::PylonLowVoltage::manageUpdate", $hash, 0);
      return;
  }

  return if(IsDisabled ($name));

  my $interval  = AttrVal ($name, 'interval', $definterval);                                 # 0 -> manuell gesteuert
  my $timeout   = AttrVal ($name, 'timeout',        $defto);
  my $readings;

  if(!$interval) {
      $hash->{OPMODE}            = 'Manual';
      $readings->{nextCycletime} = 'Manual';
  }
  else {
      my $new = gettimeofday() + $interval;
      InternalTimer ($new, "FHEM::PylonLowVoltage::manageUpdate", $hash, 0);                             # Wiederholungsintervall

      $hash->{OPMODE}            = 'Automatic';
      $readings->{nextCycletime} = FmtTime($new);
  }

  Log3 ($name, 4, "$name - start request cycle to battery number >$hash->{BATADDRESS}< at host:port $hash->{HOST}:$hash->{PORT}");

  if ($timeout < 1.0) {
      BlockingKill ($hash->{HELPER}{BKRUNNING}) if(defined $hash->{HELPER}{BKRUNNING});
      Log3 ($name, 4, qq{$name - Cycle started in main process});
      startUpdate  ({name => $name, timeout => $timeout, readings => $readings, age1 => $age1});
  }
  else {
     delete $hash->{HELPER}{BKRUNNING} if(defined $hash->{HELPER}{BKRUNNING} && $hash->{HELPER}{BKRUNNING}{pid} =~ /DEAD/xs);

     if (defined $hash->{HELPER}{BKRUNNING}) {
         Log3 ($name, 3, qq{$name - another BlockingCall PID "$hash->{HELPER}{BKRUNNING}{pid}" is already running ... start Update aborted});

         return;
     }

     my $blto = sprintf "%.0f", ($timeout + 10);

     $hash->{HELPER}{BKRUNNING} = BlockingCall ( "FHEM::PylonLowVoltage::startUpdate",
                                                 {name => $name, timeout => $timeout, readings => $readings, age1 => $age1, block => 1},
                                                 "FHEM::PylonLowVoltage::finishUpdate",
                                                 $blto,                                                  # Blocking Timeout höher als INET-Timeout!
                                                 "FHEM::PylonLowVoltage::abortUpdate",
                                                 $hash
                                               );


     if (defined $hash->{HELPER}{BKRUNNING}) {
         $hash->{HELPER}{BKRUNNING}{loglevel} = 3;                                                       # Forum https://forum.fhem.de/index.php/topic,77057.msg689918.html#msg689918

         Log3 ($name, 4, qq{$name - Cycle BlockingCall PID "$hash->{HELPER}{BKRUNNING}{pid}" with timeout "$blto" started});
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

  my ($socket, $serial);

  eval {                                                                                              ## no critic 'eval'
      local $SIG{ALRM} = sub { croak 'gatewaytimeout' };
      ualarm ($timeout * 1000000);                                                                    # ualarm in Mikrosekunden

      $socket = _openSocket ($hash, $timeout, $readings);

      if (!$socket) {
          $serial = encode_base64 (Serialize ( {name => $name, readings => $readings} ), "");
          $block ? return ($serial) : return \&finishUpdate ($serial);
      }

      if (ReadingsAge ($name, "serialNumber", 6000) >= $age1) {                                       # Abrufklasse statische Werte
          for my $idx (sort keys %fns1) {
              if (&{$fns1{$idx}{fn}} ($hash, $socket, $readings)) {
                  $serial = encode_base64 (Serialize ( {name => $name, readings => $readings} ), "");
                  $block ? return ($serial) : return \&finishUpdate ($serial);
              }
          }
      }

      for my $idx (sort keys %fns2) {                                                                 # Abrufklasse dynamische Werte
          if (&{$fns2{$idx}{fn}} ($hash, $socket, $readings)) {
              $serial = encode_base64 (Serialize ( {name => $name, readings => $readings} ), "");
              $block ? return ($serial) : return \&finishUpdate ($serial);
          }
      }

      $success = 1;
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

  delete($hash->{HELPER}{BKRUNNING}) if(defined $hash->{HELPER}{BKRUNNING});

  if ($success) {
      Log3 ($name, 4, "$name - got data from battery number >$hash->{BATADDRESS}< successfully");

      additionalReadings ($readings);                                                 # zusätzliche eigene Readings erstellen
      $readings->{state} = 'connected';
  }
  else {
      deleteReadingspec ($hash);
  }

  createReadings ($hash, $success, $readings);                                                  # Readings erstellen

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

  delete($hash->{HELPER}{BKRUNNING});

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
                       cmd    => $hrsnb{$hash->{BATADDRESS}}{cmd},
                       cmdtxt => 'serialNumber'
                     }
                    );

  my $rtnerr = responseCheck ($res, $hrsnb{$hash->{BATADDRESS}}{mlen});

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
                       cmd    => $hrmfi{$hash->{BATADDRESS}}{cmd},
                       cmdtxt => 'manufacturerInfo'
                     }
                    );

  my $rtnerr = responseCheck ($res, $hrmfi{$hash->{BATADDRESS}}{mlen});

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
                       cmd    => $hrprt{$hash->{BATADDRESS}}{cmd},
                       cmdtxt => 'protocolVersion'
                     }
                    );

  my $rtnerr = responseCheck ($res, $hrprt{$hash->{BATADDRESS}}{mlen});

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
                       cmd    => $hrswv{$hash->{BATADDRESS}}{cmd},
                       cmdtxt => 'softwareVersion'
                     }
                    );

  my $rtnerr = responseCheck ($res, $hrswv{$hash->{BATADDRESS}}{mlen});

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
                       cmd    => $hrspm{$hash->{BATADDRESS}}{cmd},
                       cmdtxt => 'systemParameters'
                     }
                    );

  my $rtnerr = responseCheck ($res, $hrspm{$hash->{BATADDRESS}}{mlen});

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

###############################################################
#       Abruf alarmInfo
###############################################################
sub _callAlarmInfo {
  my $hash     = shift;
  my $socket   = shift;
  my $readings = shift;                # Referenz auf das Hash der zu erstellenden Readings

  my $res = Request ({ hash   => $hash,
                       socket => $socket,
                       cmd    => $hralm{$hash->{BATADDRESS}}{cmd},
                       cmdtxt => 'alarmInfo'
                     }
                    );

  my $rtnerr = responseCheck ($res, $hralm{$hash->{BATADDRESS}}{mlen});

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

  $readings->{packCellcount} = hex (substr($res, 17, 2));

  if (substr($res, 19, 30) eq "000000000000000000000000000000" &&
      substr($res, 51, 10) eq "0000000000"                     &&
      substr($res, 67, 2)  eq "00"                             &&
      substr($res, 73, 4)  eq "0000") {
      $readings->{packAlarmInfo} = "ok";
  }
  else {
      $readings->{packAlarmInfo} = "failure";
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
                       cmd    => $hrcmi{$hash->{BATADDRESS}}{cmd},
                       cmdtxt => 'chargeManagmentInfo'
                     }
                    );

  my $rtnerr = responseCheck ($res, $hrcmi{$hash->{BATADDRESS}}{mlen});

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
                       cmd    => $hrcmn{$hash->{BATADDRESS}}{cmd},
                       cmdtxt => 'analogValue'
                     }
                    );

  my $rtnerr = responseCheck ($res, $hrcmn{$hash->{BATADDRESS}}{mlen});

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
      $readings->{'cellVoltage_'.$fz} = sprintf "%.3f", hex(substr($res, $bpos, 4)) / 1000;      # Pos 19 - 75 bei 15 Zellen
      $bpos += 4;                                                                                # letzter Durchlauf: Pos 79 bei 15 Zellen, Pos 83 bei 16 Zellen
  }

  $readings->{numberTempPos}             = hex(substr($res, $bpos, 2));                          # Anzahl der jetzt folgenden Teperaturpositionen -> 5
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

  my $current                            =  hex (substr($res, $bpos, 4));                        # Pos 101
  $bpos += 4;

  $readings->{packVolt}                  = sprintf "%.3f", hex (substr($res, $bpos, 4)) / 1000;  # Pos 105
  $bpos += 4;

  my $remcap1                            = sprintf "%.3f", hex (substr($res, $bpos, 4)) / 1000;  # Pos 109
  $bpos += 4;

  my $udi                                = hex substr($res, $bpos, 2);                           # Pos 113, user defined item=Entscheidungskriterium -> 2: Batterien <= 65Ah, 4: Batterien > 65Ah
  $bpos += 2;

  my $totcap1                            = sprintf "%.3f", hex (substr($res, $bpos, 4)) / 1000;  # Pos 115
  $bpos += 4;

  $readings->{packCycles}                = hex substr($res, $bpos, 4);                           # Pos 119
  $bpos += 4;

  my $remcap2                            = sprintf "%.3f", hex (substr($res, $bpos, 6)) / 1000;  # Pos 123
  $bpos += 6;

  my $totcap2                            = sprintf "%.3f", hex (substr($res, $bpos, 6)) / 1000;  # Pos 129
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

###############################################################
#                  PylonLowVoltage Undef
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
   
   for (my $i = 0; $i < length($string); $i = $i + 2) {
      $charcode = hex substr ($string, $i, 2);                  # charcode = aquivalente Dezimalzahl der angegebenen Hexadezimalzahl
      next if($charcode == 45);                                 # Hyphen '-' ausblenden 
      
      $text = $text.chr ($charcode);
   }
   
return $text;
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

    $readings->{averageCellVolt} = sprintf "%.3f", $readings->{packVolt} / $readings->{packCellcount}                  if(defined $readings->{packCellcount});
    $readings->{packSOC}         = sprintf "%.2f", ($readings->{packCapacityRemain} / $readings->{packCapacity} * 100) if(defined $readings->{packCapacity});
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
        readingsBulkUpdate ($hash, $rdg, $readings->{$rdg}) if($success || $rdg ~~ @blackl);
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

<b>Limitations</b>
<br>
The module currently supports a maximum of 14 batteries (master + 13 slaves) in one group.
<br><br>

<a id="PylonLowVoltage-define"></a>
<b>Definition</b>
<ul>
  <code><b>define &lt;name&gt; PylonLowVoltage &lt;hostname/ip&gt;:&lt;port&gt; [&lt;bataddress&gt;]</b></code><br>
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

<b>Einschränkungen</b>
<br>
Das Modul unterstützt zur Zeit maximal 14 Batterien (Master + 13 Slaves) in einer Gruppe.
<br><br>

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
     Geräteadresse der Pylontech Batterie. Es können mehrere Pylontech Batterien über eine Pylontech-spezifische
     Link-Verbindung verbunden werden. Die zulässige Anzahl ist der jeweiligen Pylontech Dokumentation zu entnehmen. <br>
     Die Master Batterie im Verbund (mit offenem Link Port 0 bzw. an der die RS485-Verbindung angeschlossen ist) hat die
     Adresse 1, die nächste Batterie hat dann die Adresse 2 und so weiter.
     Ist keine Geräteadresse angegeben, wird die Adresse 1 verwendet.
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