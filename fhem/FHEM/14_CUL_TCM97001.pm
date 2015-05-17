##############################################
# From dancer0705
#
# Receive temperature sensor
# Supported models:
#  - "TCM97..."
#  - "ABS700"
#  - "TCM21...."
#  - "Prologue"
#  - "Rubicson"
#  - "NC_WS"
#  - "GT-WT-02"
#  - "AURIOL"
#
# Unsupported models are saved in a device named CUL_TCM97001_Unknown
#
# Copyright (C) 2015 Bjoern Hempel
#
# This program is free software; you can redistribute it and/or modify it under 
# the terms of the GNU General Public License as published by the Free Software 
# Foundation; either version 2 of the License, or (at your option) any later 
# version.
#
# This program is distributed in the hope that it will be useful, but 
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY 
# or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for 
# more details.
#
# You should have received a copy of the GNU General Public License along with 
# this program; if not, write to the 
# Free Software Foundation, Inc., 
# 51 Franklin St, Fifth Floor, Boston, MA 02110, USA
#
##############################################

package main;


use strict;
use warnings;

use SetExtensions;
use constant { TRUE => 1, FALSE => 0 };

#
# All suported models
#
my %models = (
    "TCM97..."    => 'TCM97...',
    "ABS700"      => 'ABS700',
    "TCM21...."   => 'TCM21....',
    "Prologue"    => 'Prologue',
    "Rubicson"    => 'Rubicson',
    "NC_WS"       => 'NC_WS',
    "GT-WT-02"    => 'GT-WT-02',
    "AURIOL"      => 'AURIOL',
    "Unknown"     => 'Unknown',
);

sub
CUL_TCM97001_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^s....."; 
  $hash->{DefFn}     = "CUL_TCM97001_Define";
  $hash->{UndefFn}   = "CUL_TCM97001_Undef";
  $hash->{ParseFn}   = "CUL_TCM97001_Parse";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ignore:0,1 showtime:1,0 " .
                        "$readingFnAttributes " .
                        "model:".join(",", sort keys %models);

  $hash->{AutoCreate}=
        { "CUL_TCM97001.*" => { GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME" } };
}

#############################
sub
CUL_TCM97001_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> CUL_TCM97001 <code>"
        if(int(@a) < 3 || int(@a) > 5);

  $hash->{CODE} = $a[2];
  $hash->{lastT} =  0;
  $hash->{lastH} =  0;

  $modules{CUL_TCM97001}{defptr}{$a[2]} = $hash;
  $hash->{STATE} = "Defined";

  return undef;
}

#####################################
sub
CUL_TCM97001_Undef($$)
{
  my ($hash, $name) = @_;
  delete($modules{CUL_TCM97001}{defptr}{$hash->{CODE}})
     if(defined($hash->{CODE}) &&
        defined($modules{CUL_TCM97001}{defptr}{$hash->{CODE}}));
  return undef;
}

#
# CRC Check for TCM 21....
#
sub checkCRC {
  my $msg = shift;
  my @a = split("", $msg);
  my $bitReverse = undef;
  my $x = undef;
  foreach $x (@a) {
     my $bin3=sprintf("%04b",hex($x));
    $bitReverse = $bitReverse . reverse($bin3); 
  }
  my $hexReverse = unpack("H*", pack ("B*", $bitReverse));

  #Split reversed a again
  my @aReverse = split("", $hexReverse);

  my $CRC = (hex($aReverse[0])+hex($aReverse[1])+hex($aReverse[2])+hex($aReverse[3])
            +hex($aReverse[4])+hex($aReverse[5])+hex($aReverse[6])+hex($aReverse[7])) & 15;
  if ($CRC + hex($aReverse[8]) == 15) {
      return TRUE;
  }
  return FALSE;
}

#
# CRC Check for GT-WT-02
#
sub checkCRC_GTWT02 {
  my $msg = shift;
  my @a = split("", $msg);

  my $CRC = (hex($a[0])+hex($a[1])+hex($a[2])+hex($a[3])
            +hex($a[4])+hex($a[5])+hex($a[6])+hex($a[7])) -1;
  my $CRCCHECKVAL= (hex($a[7].$a[8].$a[9]) & 0x1F8) >> 3; 
  if ($CRC == $CRCCHECKVAL) {
      return TRUE;
  }
  return FALSE;
}

sub checkValues {
  my $temp = shift;
  my $humidy = shift;
  if (!defined($humidy)) {
    $humidy = 50;
  }
  if ($temp < 60 && $temp > -30
      && $humidy > 0 && $humidy < 100) {
    return TRUE;
  }
  return FALSE;
}

###################################
sub
CUL_TCM97001_Parse($$)
{
  my ($hash, $msg) = @_;
  $msg = substr($msg, 1);
  my @a = split("", $msg);

  my $id3 = hex($a[0] . $a[1]);
  #my $id4 = hex($a[0] . $a[1] . $a[2] . (hex($a[3]) & 0x3));

  my $def = $modules{CUL_TCM97001}{defptr}{$id3};
  #my $def2 = $modules{CUL_TCM97001}{defptr}{$id4};
  
  
  my $now = time();

  my $name = "Unknown";
  if($def) {
    $name = $def->{NAME};
  #} elsif($def2) {
  #  $name = $def2->{NAME};
  } 

  my $readedModel = AttrVal($name, "model", "Unknown");
  
  my $rssi;
  my $l = length($msg);
  $rssi = substr($msg, $l-2, 2);
  undef($rssi) if ($rssi eq "00");
  
  if (defined($rssi))
  {
	  $rssi = hex($rssi);
    $rssi = ($rssi>=128 ? (($rssi-256)/2-74) : ($rssi/2-74)) if defined($rssi);
    Log3 $name, 4, "CUL_TCM97001 $name $id3 ($msg) length: $l RSSI: $rssi";
  } else {
    Log3 $name, 4, "CUL_TCM97001 $name $id3 ($msg) length: $l"; 
  }

  my ($msgtype, $msgtypeH);
  
  my $packageOK = FALSE;
  
  my $batbit=undef;
  my $mode=undef;
  my $trend=undef;
  my $hashumidity = FALSE;
  my $hasbatcheck = FALSE;
  my $hastrend = FALSE;
  my $haschannel = FALSE;
  my $model="Unknown";
  my $temp = undef;
  my $humidity=undef;  
  my $channel = undef;

  if (length($msg) == 8) {
    # Only tmp TCM device
    #eg. 1000 1111 0100 0011 0110 1000 = 21.8C
    #eg. --> shift2  0100 0011 0110 10
    my $tcm97id = hex($a[0] . $a[1]);
    $def = $modules{CUL_TCM97001}{defptr}{$tcm97id};
    if($def) {
      $name = $def->{NAME};
    }
    $readedModel = AttrVal($name, "model", "Unknown");
    
    if ($readedModel eq "Unknown" || $readedModel eq "TCM97...") {
      $def = $modules{CUL_TCM97001}{defptr}{$tcm97id};
      if($def) {
        $name = $def->{NAME};
      } 

      $temp    = (hex($a[3].$a[4].$a[5]) >> 2) & 0xFFFF;  
      my $negative    = (hex($a[2]) >> 0) & 0x3; 

      if ($negative == 0x3) {
        $temp = (~$temp & 0x03FF) + 1;
        $temp = -$temp;
      }

      $temp = $temp / 10;

      # I think bit 3 on byte 3 is battery warning
      $batbit    = (hex($a[2]) >> 0) & 0x4; 

      $mode    = (hex($a[5]) >> 0) & 0x1; 

      my $unknown    = (hex($a[4]) >> 0) & 0x2; 

      if ($mode) {
        Log3 $name, 5, "CUL_TCM97001 Mode: manual triggert";
      } else {
        Log3 $name, 5, "CUL_TCM97001 Mode: auto triggert";
      }
      if ($unknown) {
          Log3 $name, 5, "CUL_TCM97001 Unknown Bit: $unknown";
      }
      
      if (checkValues($temp, 50)) {
        if(!$def) {
          Log3 $name, 2, "CUL_TCM97001 Unknown device $tcm97id, please define it";
          return "UNDEFINED CUL_TCM97001_$tcm97id CUL_TCM97001 $tcm97id"; 
        }        
        $packageOK = TRUE;
        $hasbatcheck = TRUE;
        $model="TCM97...";
        $readedModel=$model;
      }
    }
    if ($readedModel eq "Unknown" || $readedModel eq "ABS700") {
      $def = $modules{CUL_TCM97001}{defptr}{$tcm97id};
      if($def) {
        $name = $def->{NAME};
      } 
      

      $temp = (hex($a[2].$a[3]) & 0x7F)+(hex($a[5])/10);
      if ((hex($a[2]) & 0x8) == 0x8) {
        $temp = -$temp;
      }
      $batbit = ((hex($a[4]) & 0x8) != 0x8);
      $mode = (hex($a[4]) & 0x4) >> 2;
      if (checkValues($temp, 50)) {
        if(!$def) {
          Log3 $name, 2, "CUL_TCM97001 Unknown device $tcm97id, please define it";
          return "UNDEFINED CUL_TCM97001_$tcm97id CUL_TCM97001 $tcm97id"; 
        }
        $hasbatcheck = TRUE;
        $packageOK = TRUE;
        $model="ABS700";
        $readedModel=$model;
      }
    } 
  } elsif (length($msg) == 12) { 
    my $bin = undef;
    my $idType1 = hex($a[0] . $a[1]);
    #my $idType2 = hex($a[0] . $a[1] . $a[2]);
    #my $idType3 = hex($a[0] . $a[1] . $a[2] . (hex($a[3]) & 0x3));

    $def = $modules{CUL_TCM97001}{defptr}{$idType1};
    #my $def2 = $modules{CUL_TCM97001}{defptr}{$idType2};
    #my $def3 = $modules{CUL_TCM97001}{defptr}{$idType3};
    if($def) {
      $name = $def->{NAME};
    #} elsif($def2) {
    #  $def = $def2;
    #  $name = $def->{NAME};
    #} elsif($def3) {
    #  $def = $def3;
    #  $name = $def->{NAME};
    }
    $readedModel = AttrVal($name, "model", "Unknown");
    Log3 $name, 4, "CUL_TCM97001 Define Name: $name  Model defined: $readedModel";
    
    if (checkCRC($msg) == TRUE && ($readedModel eq "Unknown" || $readedModel eq "TCM21....")) {
        # Long with tmp
        # All nibbles must be reversed  
        # e.g. 154E800480	   0001	0101 0100	1110 1000	0000 0000	0100 1000	0000
        #                      A    B    C    D    E    F    G    H    I
        # A+B = Addess
        # C Bit 1 Battery
        # D+E+F Temp 
        # G+H Hum
        # I CRC
        $def = $modules{CUL_TCM97001}{defptr}{$idType1};
        if($def) {
          $name = $def->{NAME};
        }
        my @a = split("", $msg);
        my $bitReverse = undef;
        my $x = undef;
        foreach $x (@a) {
           my $bin3=sprintf("%024b",hex($x));
           $bitReverse = $bitReverse . substr(reverse($bin3),0,4); 
        }
        my $hexReverse = unpack("H*", pack ("B*", $bitReverse));

        #Split reversed a again
        my @aReverse = split("", $hexReverse);

        if (hex($aReverse[5]) > 3) {
           # negative temp
           $temp = ((hex($aReverse[3]) + hex($aReverse[4]) * 16 + hex($aReverse[5]) * 256));
           $temp = (~$temp & 0x03FF) + 1;
           $temp = -$temp/10;
        } else {
           # positive temp
           $temp = (hex($aReverse[3]) + hex($aReverse[4]) * 16 + hex($aReverse[5]) * 256)/10;
        }

        $humidity = hex($aReverse[7]).hex($aReverse[6]);

        $batbit = (hex($a[2]) & 0x8) >> 3;

        if (checkValues($temp, $humidity)) {
          if(!$def) {
              Log3 $name, 2, "CUL_TCM97001 Unknown device $idType1, please define it";
              return "UNDEFINED CUL_TCM97001_$idType1 CUL_TCM97001 $idType1"; 
          }
          $hashumidity = TRUE;    
          $packageOK = TRUE;
          $hasbatcheck = TRUE;
          $model="TCM21....";
          $readedModel=$model;
        } else {
            $name = "Unknown";
        }
    } 

    if (checkCRC_GTWT02($msg) == TRUE && ($readedModel eq "GT-WT-02" || $readedModel eq "Unknown")) {
      #    F    F    0    0    F    9    5    5    F   
        # 1111 1111 0000 0000 1111 1001 0101 0101 1111 
        #    A    B    C    D    E    F    G    H    I 
        # A+B = Zufällige Code wechelt beim Batteriewechsel
        # C Bit 4 Battery, 3 Manual, 2+1 Channel
        # D+E+F Temperatur, wenn es negativ wird muss man negieren und dann 1 addieren, wie im ersten Post beschrieben.
        # G+H Hum - bit 0-7 
        # I CRC?
      #$def = $modules{CUL_TCM97001}{defptr}{$idType3};
      $def = $modules{CUL_TCM97001}{defptr}{$idType1};
      if($def) {
        $name = $def->{NAME};
      } 
      $channel    = (hex($a[2])) & 0x3;
      $temp    = (hex($a[3].$a[4].$a[5])) & 0x3FF;  
      my $negative    = (hex($a[3])) & 0xC; 
      if ($negative == 0xC) {
        $temp = (~$temp & 0x03FF) + 1;
        $temp = -$temp;
      }
      $temp = $temp / 10;
      $humidity = (hex($a[6].$a[7]) & 0x0FE) >> 1; # only the first 7 bits are the humidity

      if (checkValues($temp, $humidity)) {
        if(!$def) {
          $name, 2, "CUL_TCM97001 Unknown device $idType1, please define it";
          return "UNDEFINED CUL_TCM97001_$idType1 CUL_TCM97001 $idType1"; 
        }
        if ($humidity >= 20) {
          $hashumidity = TRUE;
        }
        $hasbatcheck = TRUE;  
        $haschannel = TRUE;     
        $packageOK = TRUE;
        $model="GT-WT-02";
        $readedModel=$model;
      } else {
          $name = "Unknown";
      }
    }
      #Log3 $name, 4, "CUL_TCM97001: CRC for TCM21.... Failed, checking other protocolls";
      # Check for Prologue
    if ($readedModel eq "Prologue" || (hex($a[0]) == 0x9 && $readedModel eq "Unknown")) {
        # Protocol prologue start everytime with 1001
        # e.g. 91080F614C	    1001 0001 0000 1000 0000 1111 0110 0001 0100 1100
        #                      A    B    C    D    E    F    G    H    I
        # A = Startbit 1001
        # B+C = Random Address
        # D Bit 4 Battery, 3 Manual, 2+1 Channel 
        # E+F+G Bit 15+16 negativ temp, 14-0 temp
        # H+I Hum
        #$def = $modules{CUL_TCM97001}{defptr}{$idType3};
        $def = $modules{CUL_TCM97001}{defptr}{$idType1};
        if($def) {
          $name = $def->{NAME};
        }         
        $temp    = (hex($a[4].$a[5].$a[6])) & 0x3FFF;  
        my $negative    = (hex($a[4])) & 0xC; 

        if ($negative == 0xC) {
          $temp = (~$temp & 0x03FF) + 1;
          $temp = -$temp;
        }
        $temp = $temp / 10;

        if (hex($a[7]) != 0xC && hex($a[8]) != 0xC) {
          $humidity = hex($a[7].$a[8]);
        }

        $channel = (hex($a[3])) & 0x3;
        $batbit = (hex($a[3]) & 0x8) >> 3;
        $mode = (hex($a[3]) & 0x4) >> 2;
        if (checkValues($temp, $humidity)) {
          if(!$def) {
            Log3 $name, 2, "CUL_TCM97001 Unknown device $idType1, please define it";
            return "UNDEFINED CUL_TCM97001_$idType1 CUL_TCM97001 $idType1"; 
          }
          if (defined($humidity)) {
            if ($humidity >= 20) {
              $hashumidity = TRUE;
            }  
          }  
          $hasbatcheck = TRUE;
          $packageOK = TRUE;
          $haschannel = TRUE;
          $model="Prologue";
          $readedModel=$model;
        } else {
            $name = "Unknown";
        }
    } 
    
    if ($readedModel eq "NC_WS" || (hex($a[0]) == 0x5 && $readedModel eq "Unknown")) {
      # Implementation from Femduino
      # PEARL NC7159, LogiLink WS0002
      #                 /--------------------------------- Sensdortype      
      #                /     / ---------------------------- ID, changes after every battery change      
      #               /     /          /--------------------- Battery state 0 == Ok
      #              /     /          /  / ------------------ forced send      
      #             /     /          /  /  / ---------------- Channel (0..2)      
      #            /     /          /  /  /   / -------------- neg Temp: if 1 then temp = temp - 2048
      #           /     /          /  /  /   /   / ----------- Temp
      #          /     /          /  /  /   /   /             /-- unknown
      #         /     /          /  /  /   /   /             /  / Humidity
      #         0101  0010 1001  0 0 00   0 010 0011 0000   1 101 1101
      # Bit     0     4         12 13 14  16 17            28 29    36
      #$def = $modules{CUL_TCM97001}{defptr}{$idType3};
      $def = $modules{CUL_TCM97001}{defptr}{$idType1};
      if($def) {
        $name = $def->{NAME};
      } 
      $temp    = (hex($a[4].$a[5].$a[6])) & 0x7FFF;  
      my $negative    = (hex($a[4])) & 0x8; 

      if ($negative == 0x8) {
        $temp = (~$temp & 0x07FF) + 1;
        $temp = -$temp;
      }
      $temp = $temp / 10;
      
      $channel = (hex($a[3])) & 0x3;
      $humidity = hex($a[7].$a[8]) & 0x7F;

      $batbit = (hex($a[3]) & 0x8) >> 3;
      $batbit = ~$batbit & 0x1; # Bat bit umdrehen
      $mode = (hex($a[3]) & 0x4) >> 2;
      if (checkValues($temp, $humidity)) {
        if(!$def) {
          #Log3 $name, 2, "CUL_TCM97001 Unknown device $idType3, please define it";
          #return "UNDEFINED CUL_TCM97001_$idType3 CUL_TCM97001 $idType3" if(!$def); 
          Log3 $name, 2, "CUL_TCM97001 Unknown device $idType1, please define it";
          return "UNDEFINED CUL_TCM97001_$idType1 CUL_TCM97001 $idType1" if(!$def); 
        }
        $hashumidity = TRUE;
        $hasbatcheck = TRUE;
        $packageOK = TRUE;
        $haschannel = TRUE; 
        $model="NC_WS";
        $readedModel=$model;
      } else {
          $name = "Unknown";
      }
    } 

    if ($readedModel eq "Rubicson" || (hex($a[2]) == 0x8 && $readedModel eq "Unknown")) {
      # Protocol Rubicson has as nibble C every time 1000
      # e.g. F4806B8E14	    1111 0100 1000 0000 0110 1011 1000 1110	0001 0100
      #                      A    B    C    D    E    F    G    H    I
      # A+B = Random Address
      # C = Rubicson = 1000
      # D+E+F 12 bit temp
      # G+H+I Unknown
      $def = $modules{CUL_TCM97001}{defptr}{$idType1};
      if($def) {
        $name = $def->{NAME};
      } 
      $temp    = (hex($a[3].$a[4].$a[5])) & 0x3FF;  
      my $negative    = (hex($a[3])) & 0xC; 

      if ($negative == 0xC) {
        $temp = (~$temp & 0x03FF) + 1;
        $temp = -$temp;
      }
      $temp = $temp / 10;

      if (checkValues($temp, $humidity)) {
        if(!$def) {
          Log3 $name, 2, "CUL_TCM97001 Unknown device $idType1, please define it";
          return "UNDEFINED CUL_TCM97001_$idType1 CUL_TCM97001 $idType1" if(!$def); 
        }
        $packageOK = TRUE;
        $model="Rubicson";
        $readedModel=$model;
      } else {
          $name = "Unknown";
      }
    }

    if (($readedModel eq "AURIOL" || $readedModel eq "Unknown")) {
      # Implementation from Femduino
      # AURIOL (Lidl Version: 09/2013)
      #                /--------------------------------- Channel, changes after every battery change      
      #               /           / ------------------------ Battery state 1 == Ok      
      #              /           / /------------------------ Battery changed, Sync startet      
      #             /           / /  ----------------------- Unknown      
      #            /           / / /    /--------------------- neg Temp: if 1 then temp = temp - 4096
      #           /           / / /    /---------------------- 12 Bit Temperature
      #          /           / / /    /               /---------- ??? CRC 
      #         /           / / /    /               /       /---- Trend 10 == rising, 01 == falling
      #         0101 0101  1 0 00   0001 0000 1011  1100  01 00
      # Bit     0          8 9 10   12              24       30
      $def = $modules{CUL_TCM97001}{defptr}{$idType1};
      if($def) {
        $name = $def->{NAME};
      } 
      $temp    = (hex($a[3].$a[4].$a[5])) & 0x7FF;  
      my $negative    = (hex($a[3])) & 0x8; 
      if ($negative == 0x8) {
        $temp = (~$temp & 0x07FF) + 1;
        $temp = -$temp;
      }
      $temp = $temp / 10;

      $batbit = (hex($a[3]) & 0x8) >> 3;
      $batbit = ~$batbit & 0x1; # Bat bit umdrehen

      $trend = (hex($a[7]) & 0x3);
      if (checkValues($temp, 50)) {
        if(!$def) {
          Log3 $name, 2, "CUL_TCM97001 Unknown device $idType1, please define it";
          return "UNDEFINED CUL_TCM97001_$idType1 CUL_TCM97001 $idType1" if(!$def); 
        }
        $hasbatcheck = TRUE;
        $hastrend = TRUE;     
        $packageOK = TRUE;
        $model="AURIOL";
        $readedModel=$model;
      } else {
          $name = "Unknown";
      }
    }
     
  }
  
  if ($packageOK == TRUE) {
    if($def) {
      $def->{lastT} = $now;
    } 
    my ($val, $valH, $state);
    $msgtype = "temperature";
    $val = sprintf("%2.1f", ($temp) );
    $state="T: $val";
    if ($hashumidity == TRUE) {
      $msgtypeH = "humidity";
      $valH = $humidity;
      $state="$state H: $valH";
      Log3 $name, 4, "CUL_TCM97001 $msgtype $name $id3 T: $val H: $valH"; 
    } else {
      Log3 $name, 4, "CUL_TCM97001 $msgtype $name $id3 T: $val";
    }

    readingsBeginUpdate($def);


    if($hastrend) {
      my $readTrend = ReadingsVal($name, "trend", "unknown");
      if ($trend == 1) {
        if ($readTrend ne  "falling") { readingsBulkUpdate($def, "trend", "falling"); }
      } else {
        if ($readTrend ne  "rising") { readingsBulkUpdate($def, "trend", "rising"); }
      }
    }
    if ($hasbatcheck) {
      my $battery = ReadingsVal($name, "battery", "unknown");
      if ($batbit) {
        if ($battery ne  "low") { readingsBulkUpdate($def, "battery", "low"); }
      } else {
        if ($battery ne  "ok") { readingsBulkUpdate($def, "battery", "ok"); }
      }
    }
    if ($haschannel) {
      my $readChannel = ReadingsVal($name, "channel", "");
      if (defined($readChannel) && $readChannel ne $channel) { readingsBulkUpdate($def, "channel", $channel); }
    }
    readingsBulkUpdate($def, $msgtype, $val);
    if ($hashumidity == TRUE) {
      readingsBulkUpdate($def, $msgtypeH, $valH);
    }
    
    readingsBulkUpdate($def, "state", $state);
    
    readingsEndUpdate($def, 1);
    if(defined($rssi)) {
      $def->{RSSI} = $rssi;
    } 
    $attr{$name}{model} = $model;
    return $name;
  } else {
    my $defUnknown = $modules{CUL_TCM97001}{defptr}{"Unknown"};
    
    if (!$defUnknown) {
      Log3 "Unknown", 2, "CUL_TCM97001 Unknown device Unknown, please define it";
      return "UNDEFINED CUL_TCM97001_Unknown CUL_TCM97001 Unknown"; 
    } 
    $name = $defUnknown->{NAME};
    Log3 $name, 4, "CUL_TCM97001 Device not implemented yet name Unknown msg $msg";

    my $state="Code: $msg";

    if ($defUnknown) {
      $defUnknown->{lastT} = $now;
    }

    $attr{$name}{model} = $model;
    readingsBeginUpdate($defUnknown);
    readingsBulkUpdate($defUnknown, "state", $state);
    readingsEndUpdate($defUnknown, 1);
    if(defined($rssi)) {
      $defUnknown->{RSSI} = $rssi;
    }

    my $defSvg = $defs{"SVG_CUL_TCM97001_Unknown"}; 

    if ($defSvg) {
      CommandDelete(undef, $defSvg->{NAME});
    }
    return $name;
  }


  return undef;
}

1;


=pod
=begin html

<a name="CUL_TCM97001"></a>
<h3>CUL_TCM97001</h3>
<ul>
  The CUL_TCM97001 module interprets temperature sensor messages received by a Device like CUL, CUN, SIGNALduino etc.<br>
  <br>
  <b>Supported models:</b>
  <ul>
    <li>TCM97...</li>
    <li>ABS700</li>
    <li>TCM21....</li>
    <li>Prologue</li>
    <li>Rubicson</li>
    <li>NC_WS</li>
    <li>GT-WT-02</li>
    <li>AURIOL</li>
  </ul>
  <br>
  New received device packages are add in fhem category CUL_TCM97001 with autocreate.
  <br><br>

  <a name="CUL_TCM97001_Define"></a>
  <b>Define</b> 
  <ul>The received devices created automatically.<br>
  The ID of the defive are the first two Hex values of the package as dezimal.<br>
  </ul>
  <br>
  <a name="CUL_TCM97001 Events"></a>
  <b>Generated events:</b>
  <ul>
     <li>temperature: The temperature</li>
     <li>humidity: The humidity (if available)</li>
     <li>battery: The battery state: low or ok (if available)</li>
     <li>channel: The Channelnumber (if available)</li>
     <li>trend: The temperature trend (if available)</li>
  </ul>
  <br>
  <b>Attributes</b>
  <ul>
    <li><a href="#IODev">IODev</a>
      Note: by setting this attribute you can define different sets of 8
      devices in FHEM, each set belonging to a Device which is capable of receiving the signals. It is important, however,
      that a device is only received by the defined IO Device, e.g. by using
      different Frquencies (433MHz vs 868MHz)
      </li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#model">model</a> (TCM97..., ABS700, TCM21...., Prologue, Rubicson, NC_WS, GT-WT-02, AURIOL, Unknown)</li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>

  <a name="CUL_TCM97001_Set"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="CUL_TCM97001_Parse"></a>
  <b>Set</b> <ul>N/A</ul><br>

</ul>

=end html

=begin html_DE

<a name="CUL_TCM97001"></a>
<h3>CUL_TCM97001</h3>
<ul>
  Das CUL_TCM97001 Module verarbeitet von einem IO Gerät (CUL, CUN, SIGNALDuino, etc.) empfangene Nachrichten von Temperatur-Sensoren.<br>
  <br>
  <b>Unterstütze Modelle:</b>
  <ul>
    <li>TCM97...</li>
    <li>ABS700</li>
    <li>TCM21....</li>
    <li>Prologue</li>
    <li>Rubicson</li>
    <li>NC_WS</li>
    <li>GT-WT-02</li>
    <li>AURIOL</li>
  </ul>
  <br>
  Neu empfangene Sensoren werden in der fhem Kategory CUL_TCM97001 per autocreate angelegt.
  <br><br>

  <a name="CUL_TCM97001_Define"></a>
  <b>Define</b> 
  <ul>Die empfangenen Sensoren werden automatisch angelegt.<br>
  Die ID der angelgten Sensoren sind die ersten zwei HEX Werte des empfangenen Paketes in dezimaler Schreibweise.<br>
  </ul>
  <br>
  <a name="CUL_TCM97001 Events"></a>
  <b>Generierte Events:</b>
  <ul>
     <li>temperature: Die aktuelle Temperatur</li>
     <li>humidity: Die aktuelle Luftfeutigkeit (falls verfügbar)</li>
     <li>battery: Der Batteriestatus: low oder ok (falls verfügbar)</li>
     <li>channel: Kanalnummer (falls verfügbar)</li>
     <li>trend: Der Temperaturtrend (falls verfügbar)</li>
  </ul>
  <br>
  <b>Attribute</b>
  <ul>
    <li><a href="#IODev">IODev</a>
      Spezifiziert das physische Ger&auml;t, das die Ausstrahlung der Befehle f&uuml;r das 
      "logische" Ger&auml;t ausf&uuml;hrt. Ein Beispiel f&uuml;r ein physisches Ger&auml;t ist ein CUL.<br>
      </li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#model">model</a> (TCM97..., ABS700, TCM21...., Prologue, Rubicson, NC_WS, GT-WT-02, AURIOL, Unknown)</li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>

  <a name="CUL_TCM97001_Set"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="CUL_TCM97001_Parse"></a>
  <b>Set</b> <ul>N/A</ul><br>

</ul>

=end html_DE
=cut
