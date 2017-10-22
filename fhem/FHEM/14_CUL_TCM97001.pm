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
#  - "GT_WT_02"
#  - "AURIOL"
#  - "KW9010"
#
# Unsupported models are saved in a device named CUL_TCM97001_Unknown
#
# Copyright (C) 2016 Bjoern Hempel
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
# $Id$
#
#
# 14.06.2017 W155(TCM21...) wind/rain    pejonp
# 25.06.2017 W155(TCM21...) wind/rain    pejonp
# 04.07.2017 PFR-130        rain         pejonp
# 04.07.2017 TFA 30.3161    temp/rain    pejonp
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
    "GT_WT_02"    => 'GT_WT_02',
    "AURIOL"      => 'AURIOL',
    "PFR_130"      => 'PFR_130',
    "Type1"       => 'Type1',
    "Mebus"       => 'Mebus',
    "Eurochron"   => 'Eurochron',
    "KW9010"      => 'KW9010',
    "Unknown"     => 'Unknown',
    "W174"        => 'W174',
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
        {   	
            "CUL_TCM97001_Unknown.*" => { GPLOT => "", FILTER => "%NAME", autocreateThreshold => "2:10" }, 
            "CUL_TCM97001.*" => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME", autocreateThreshold => "2:180"},
            "Prologue_.*" => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME", autocreateThreshold => "2:180"},
            "Mebus_.*" => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME", autocreateThreshold => "2:180"},
            "NC_WS.*" => {  ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME", autocreateThreshold => "2:180"}, 
            "ABS700.*" => {  ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME", autocreateThreshold => "2:180"}, 
            "Eurochron.*" => {  ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME", autocreateThreshold => "2:180"}, 
            "TCM21....*" => {  ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME", autocreateThreshold => "2:180"}, 
            "TCM97..._.*" => {  ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME", autocreateThreshold => "2:180"}, 
            "GT_WT_02.*" => {  ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME", autocreateThreshold => "2:180"}, 
            "Type1.*" => {  ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME", autocreateThreshold => "2:180"}, 
            "Rubicson.*" => {  ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME", autocreateThreshold => "2:180"},    
            "AURIOL.*" => {  ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME", autocreateThreshold => "2:180"},
            "PFR_130.*" => {  ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME", autocreateThreshold => "2:180"}, 
            "KW9010.*" => {  ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME", autocreateThreshold => "2:180"},      
            "TCM97001.*" => {  ATTR => "event-on-change-reading:.*", GPLOT => "temp4hum4:Temp/Hum,", FILTER => "%NAME", autocreateThreshold => "2:340"},
            "W174.*" => {  ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", GPLOT => "rain4:Rain,", FILTER => "%NAME", autocreateThreshold => "2:180"},      
            "Unknown_.*" => { autocreateThreshold => "2:10"}
        };
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

### inserted by elektron-bbs for rain gauge Ventus W174
# Checksum for Rain Gauge VENTUS W174 Protocol Auriol
# n8 = ( 0x7 + n0 + n1 + n2 + n3 + n4 + n5 + n6 + n7 ) & 0xf
sub checksum_W174 {
  my $msg = shift;
  Log3 "CUL_TCM97001: ", 4 , "CUL_TCM97001: W174 checksum calc for: $msg";
  my @a = split("", $msg);
  my $bitReverse = undef;
  my $x = undef;
  foreach $x (@a) {
     my $bin3=sprintf("%04b",hex($x));
    $bitReverse = $bitReverse . reverse($bin3); 
  }
  my $hexReverse = unpack("H*", pack ("B*", $bitReverse));
  my @aReverse = split("", $hexReverse);                      # Split reversed a again
  my $CRC = (7 + hex($aReverse[0])+hex($aReverse[1])+hex($aReverse[2])+hex($aReverse[3])+hex($aReverse[4])+hex($aReverse[5])+hex($aReverse[6])+hex($aReverse[7])) & 15;
  if ($CRC == hex($aReverse[8])) {
      Log3 "CUL_TCM97001: ", 4 , "CUL_TCM97001: W174 checksum ok $CRC == ".hex($aReverse[8]);
      return TRUE;
  } else {
      #Log3 "CUL_TCM97001: ", 3 , "CUL_TCM97001: W174 ERROR - checksum $CRC != ".hex($aReverse[8]);
      return FALSE;
  }
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
# CRC 4 check for PFR-130
# xor 4 bits of nibble 0 to 7
#
sub checkCRC4 {
  my $msg = shift;
  my @a = split("", $msg);
  if(scalar(@a)<9){
    Log3 "checkCRC4", 5, "CUL_TCM97001 failed for msg=($msg) length<9";
    return FALSE;
  }
  # xor nibbles 0 to 7 and compare to n8, if more nibble they might have been added to fill gap
  my $CRC = ( (hex($a[0])) ^ (hex($a[1])) ^ (hex($a[2])) ^ (hex($a[3])) ^ 
             (hex($a[4])) ^ (hex($a[5])) ^ (hex($a[6])) ^ (hex($a[7])) );
  if ($CRC ==  (hex($a[8]))) {
    Log3 "checkCRC4", 5, "CUL_TCM97001 OK for msg=($msg)";
    return TRUE;
  }
  Log3 "checkCRC4", 5, "CUL_TCM97001 FAILED for msg=($msg)";
  return FALSE;
}
#
# CRC 4 check for PFR-130
# xor 4 bits of nibble 0 to 7
#

sub isRain {
  my $msg = shift;
  my @a = split("", $msg);
  if(scalar(@a)<9){
    Log3 "isRain", 5, "isRain: CUL_TCM97001 failed for msg=($msg) length<9";
    return FALSE;
  }
  # if bit 0 of nibble 2 is 1 then this is no rain data
  my $isRainData = ( (hex($a[2]) & 1) );
  if ($isRainData == 1) {
    Log3 "isRain", 5, "isRain: CUL_TCM97001 for msg=($msg) = FALSE";
    return FALSE;
  }
  Log3 "isRain", 5, "isRain: CUL_TCM97001 for msg=($msg) = TRUE";
  return TRUE;
}

#
# CRC Check for KW9010....
#
sub checkCRCKW9010 {
  my $msg = shift;
  Log3 "CUL_TCM97001", 5 , "crc calc for: $msg";
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
  Log3 "CUL_TCM97001", 5 , "calc crc is: $CRC";
  Log3 "CUL_TCM97001", 5 , "ref crc is :".hex($aReverse[8]);
  if ($CRC == hex($aReverse[8])) {
      return TRUE;
  }
  return FALSE;
}


#
# CRC Check for Mebus
#
sub checkCRC_Mebus {
  my $msg = shift;
  my @a = split("", $msg);

  my $CRC = ((hex($a[1])+hex($a[2])+hex($a[3])
            +hex($a[4])+hex($a[5])+hex($a[6])) -1) & 15;
  my $CRCCHECKVAL= (hex($a[0])); 
  if ($CRC == $CRCCHECKVAL) {
      return TRUE;
  }
  return FALSE;
}

#
# CRC Check for GT_WT_02
### edited by elektron-bbs for GT_WT_02
sub checkCRC_GTWT02 {
  my $msg = shift;
  my @a = split("", $msg);
  my $CRC = (hex($a[0])+hex($a[1])+hex($a[2])+hex($a[3])
            +hex($a[4])+hex($a[5])+hex($a[6])+(hex($a[7]) & 0xE));
#  my $CRC = (hex($a[0])+hex($a[1])+hex($a[2])+hex($a[3])
#            +hex($a[4])+hex($a[5])+hex($a[6])+hex($a[7])) -1;
  my $CRCCHECKVAL= (hex($a[7].$a[8].$a[9]) & 0x1F8) >> 3; 
  if ($CRC  % 64 == $CRCCHECKVAL) {
      return TRUE;
  }
  return FALSE;
}

#
# CRC Check for Sensor-Type1
#
sub checkCRC_Type1 {
  my $msg = shift;
  my @a = split("", $msg);

  my $CRC = (hex($a[0])+hex($a[1])+hex($a[2])+hex($a[3])
            +hex($a[4])+hex($a[5])+hex($a[6])+hex($a[7]));
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
  if ($temp <= 60 && $temp >= -30
      && $humidy >= 0 && $humidy <= 100) {
    return TRUE;
  }
  return FALSE;
}

###################################
sub
CUL_TCM97001_Parse($$)
{

  my $enableLongIDs = TRUE; # Disable short ID support, enable longIDs
  my ($hash, $msg) = @_;
  $msg = substr($msg, 1);
  my @a = split("", $msg);

  my $id3 = hex($a[0] . $a[1]);
  #my $id4 = hex($a[0] . $a[1] . $a[2] . (hex($a[3]) & 0x3));

  my $def = $modules{CUL_TCM97001}{defptr}{$id3}; # test for already defined devices use old naming convention  
  #my $def2 = $modules{CUL_TCM97001}{defptr}{$idType2};
  if(!$def) {
     $def = $modules{CUL_TCM97001}{defptr}{'CUL_TCM97001_'.$id3};  # use new naming convention
  }
  
  my $now = time();

  my $name = "Unknown";
  if($def) {
    $name = $def->{NAME};
  }

  my $readedModel = AttrVal($name, "model", "Unknown");
  
  my $syncTimeIndex = rindex($msg,";");
  my @syncBit;
  if ($syncTimeIndex != -1) {
    my $syncTimeMsg = substr($msg, $syncTimeIndex + 1);
    @syncBit = split(":", $syncTimeMsg);
    $msg = substr($msg, 0, $syncTimeIndex);
  } else {
    $syncBit[0] = 0;
    $syncBit[1] = 4000;
  }
  
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
  my $hasmode = FALSE;
  my $model="Unknown";
  my $temp = undef;
  my $humidity=undef;  
  my $channel = undef;
  # für zusätzliche Sensoren
  my @winddir_name=("N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW");
  my $windSpeed = 0;
  my $windDirection = 0  ;
  my $windDirectionText = "N";
  my $windgrad = 0  ;
  my $windGuest = 0;
  my $rain = 0;
  my $haswindspeed = FALSE;
  my $haswind = FALSE;
  my $hasrain = FALSE;
  my $rainticks = undef;
  my $rainMM = undef;
  
  

  my $longids = AttrVal($hash->{NAME},'longids',1);

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

      $temp    = (hex($a[3].$a[4].$a[5]) >> 2) & 0xFFFF;  
      my $negative    = (hex($a[2]) >> 0) & 0x3; 

      if ($negative == 0x3) {
        $temp = (~$temp & 0x03FF) + 1;
        $temp = -$temp;
      }

      $temp = $temp / 10;


      if (checkValues($temp, 50)) {
      	$model="TCM97...";
         # I think bit 3 on byte 3 is battery warning
      	$batbit    = (hex($a[2]) >> 0) & 0x4; 
      	$batbit = ~$batbit & 0x1; # Bat bit umdrehen
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
        
        my $deviceCode;
        
        if (!defined($modules{CUL_TCM97001}{defptr}{$tcm97id}))
        {
            if ( $enableLongIDs == TRUE || (($longids != "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/))))
          	{
		         $deviceCode="CUL_TCM97001_".$tcm97id;
		         Log3 $hash,4, "CUL_TCM97001 using longid: $longids model: $model";
           	} else {
		         $deviceCode="CUL_TCM97001_" . $model;
           	}
        } else {
        	$deviceCode=$tcm97id;
        }  
      	$def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
      	if($def) {
       	  $name = $def->{NAME};
      	} 
      	
      	
      	
        if(!$def) {
          Log3 $name, 2, "CUL_TCM97001 Unknown device $deviceCode, please define it";
          return "UNDEFINED $model" . substr($deviceCode, rindex($deviceCode,"_")) . " CUL_TCM97001 $deviceCode"; 
        }        
        $packageOK = TRUE;
        $hasbatcheck = TRUE;
        $hasmode = TRUE;
        $readedModel=$model;
      }
    }
    if ($readedModel eq "Unknown" || $readedModel eq "ABS700") {

      $temp = (hex($a[2].$a[3]) & 0x7F)+(hex($a[5])/10);
      if ((hex($a[2]) & 0x8) == 0x8) {
        $temp = -$temp;
      }
      
      if (checkValues($temp, 50)) {
        $model="ABS700";
        $batbit = ((hex($a[4]) & 0x8) != 0x8);
        $mode = (hex($a[4]) & 0x4) >> 2;
      
        my $deviceCode;
        if (!defined($modules{CUL_TCM97001}{defptr}{$tcm97id}))
        {
            if ( $enableLongIDs == TRUE || (($longids != "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/))))
          	{
		         $deviceCode="CUL_TCM97001_".$tcm97id;
		         Log3 $hash,4, "CUL_TCM97001 using longid: $longids model: $model";
           	} else {
		         $deviceCode="CUL_TCM97001_" . $model;
           	}
        } else {
        	$deviceCode=$tcm97id;
        }  
      	$def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
      	if($def) {
       	  $name = $def->{NAME};
      	} 
        if(!$def) {
          Log3 $name, 2, "CUL_TCM97001 Unknown device $deviceCode, please define it";
          return "UNDEFINED $model" . substr($deviceCode, rindex($deviceCode,"_")) . " CUL_TCM97001 $deviceCode"; 
        }
        $hasbatcheck = TRUE;
        $packageOK = TRUE;
        $hasmode = TRUE;
        
        $readedModel=$model;
      }
    } 
  } elsif (length($msg) == 10) {
  	#Log3 $name, 2, "CUL_TCM97001 10er msg: " . $msg;
    my $idType2 = hex($a[1] . $a[2]);
    my $deviceCode = $idType2;
    $def = $modules{CUL_TCM97001}{defptr}{$deviceCode};   # test for already defined devices use old naming convention
    if(!$def) {
       $deviceCode = "CUL_TCM97001_" . $idType2;          # use new naming convention
       $def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
    } 
    if($def) {
      $name = $def->{NAME};
    }
    
    $readedModel = AttrVal($name, "model", "Unknown");
    
    if (checkCRC_Mebus($msg) == TRUE && ($readedModel eq "Unknown" || $readedModel eq "Mebus")) {
        # Protocol mebus start everytime with 1001
        # Sync bit 9700ms, bit 0 = 350ms, bit 1 = 2000ms
        # e.g. 8250ED70	    1000  0010  0101  0000  1110  1101  0111
        #                   A     B     C     D     E     F     G    
        # A = CRC ((B+C+D+E+F+G)-1)
        # B+C = Random Address
        # D+E+F temp (/10) 
        # G  Bit 4,3 = Channel, Bit 2 = Battery, Bit 1 = Force sending
        $temp    = (hex($a[3].$a[4].$a[5])) & 0x3FF;  
        my $negative    = (hex($a[3])) & 0xC; 

        if ($negative == 0xC) {
          $temp = (~$temp & 0x03FF) + 1;
          $temp = -$temp;
        }
        $temp = $temp / 10;

        

        if (checkValues($temp, 50)) {
            $batbit = (hex($a[6]) & 0x2) >> 1;
            #$batbit = ~$batbit & 0x1; # Bat bit umdrehen
            $mode   = (hex($a[6]) & 0x1);
            $channel = (hex($a[6]) & 0xC) >> 2;
            $model="Mebus";
            my $deviceCode;
     
         	if (!defined($modules{CUL_TCM97001}{defptr}{$idType2}))
         	{	
	          	if ( $enableLongIDs == TRUE || (($longids != "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/))))
	          	{
			         $deviceCode="CUL_TCM97001_".$idType2;
			         Log3 $hash,4, "CUL_TCM97001 using longid: $longids model: $model";
	           	} else {
			         $deviceCode="CUL_TCM97001_" . $model . "_" . $channel;
	           	}
         	}  else  {  # Fallback for already defined devices use old naming convention
         		$deviceCode=$idType2;
         	}     
          
          	$def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
          	if($def) {
              $name = $def->{NAME};
            } 
            if(!$def) {
                Log3 $name, 2, "CUL_TCM97001 Unknown device $deviceCode, please define it";
                return "UNDEFINED $model" . substr($deviceCode, rindex($deviceCode,"_")) . " CUL_TCM97001 $deviceCode"; 
            }
            $packageOK = TRUE;
            
            $readedModel=$model;
            $hasmode = TRUE;
            $hasbatcheck = TRUE;
            $haschannel = TRUE;
            $id3 = $idType2
        } else {
            $name = "Unknown";
        }
    }

	if ($packageOK == FALSE) {
		my $idType1 = hex($a[0] . $a[1]);
		$deviceCode = $idType1;
		$def = $modules{CUL_TCM97001}{defptr}{$deviceCode};   # test for already defined devices use old naming convention 
		#my $def2 = $modules{CUL_TCM97001}{defptr}{$idType2};
		#my $def3 = $modules{CUL_TCM97001}{defptr}{$idType3};
		if(!$def) {
		   $deviceCode = "CUL_TCM97001_" . $idType1;          # use new naming convention
		   $def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
		}
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

		  
		  if (checkValues($temp, 50)) {
			$batbit = (hex($a[2]) & 0x8) >> 3;
			$batbit = ~$batbit & 0x1; # Bat bit umdrehen
			$mode   = (hex($a[2]) & 0x4) >> 2;

			$trend = (hex($a[7]) & 0x3);
			$model="AURIOL";
			
			if ($deviceCode ne $idType1)  # new naming convention
			{	
				if ( $enableLongIDs == TRUE || (($longids != "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/))))
				{
					 $deviceCode="CUL_TCM97001_".$idType1;
				} else {
					 $deviceCode="CUL_TCM97001_" . $model . "_" . $channel;
				}
			}     
		  
			$def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
			if($def) {
			 $name = $def->{NAME};
			} 
					
			if(!$def) {
			  Log3 $name, 2, "CUL_TCM97001 Unknown device $deviceCode, please define it";
			  return "UNDEFINED $model" . substr($deviceCode, rindex($deviceCode,"_")) . " CUL_TCM97001 $deviceCode"; 
			}

			$hasbatcheck = TRUE;
			$hastrend = TRUE;     
			$packageOK = TRUE;
			$hasmode = TRUE;
			
			$readedModel=$model;
		  } else {
			  $name = "Unknown";
		  }
		}
	}
    
  } elsif (length($msg) == 12) { 
    my $bin = undef;
    my $deviceCode;
    my $idType1 = hex($a[0] . $a[1]);
    #my $idType2 = hex($a[1] . $a[2]);
    #my $idType3 = hex($a[0] . $a[1] . $a[2] . (hex($a[3]) & 0x3));

    $deviceCode = $idType1;
    $def = $modules{CUL_TCM97001}{defptr}{$deviceCode};   # test for already defined devices use old naming convention 
    #my $def2 = $modules{CUL_TCM97001}{defptr}{$idType2};
    #my $def3 = $modules{CUL_TCM97001}{defptr}{$idType3};
    if(!$def) {
       $deviceCode = "CUL_TCM97001_" . $idType1;          # use new naming convention
       $def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
    }
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
    Log3 $name, 4, "CUL_TCM97001 Parse Name: $name , devicecode: $deviceCode , Model defined: $readedModel";
    
    if (($readedModel eq "Eurochron" || (hex($a[6]) == 0xF && $readedModel eq "Unknown") && $syncBit[1] < 5000)) {
      # EAS 800 
      # G is every time 1111
      #
      # 0100 1110 1001 0000 1010 0001 1111 0100 1001 
      # A    B    C    D    E    F    G    H    I
      #  
      # A+B = ID = 4E
      # C Bit 0 = Bat (1) OK
      # C Bit 1-3 = Channel 001 = 1
      # D-F = Temp (0000 1010 0001) = 161 ~ 16,1°
      # G = Unknown
      # H+I = hum (0100 1001) = 73
      $def = $modules{CUL_TCM97001}{defptr}{$idType1};
      if($def) {
        $name = $def->{NAME};
      } else {
        # Redirect to
        my $SD_WS07_ClientMatch=index($hash->{Clients},"SD_WS07");
		if ($SD_WS07_ClientMatch == -1) {
		    # Append Clients and MatchList for CUL
		    $hash->{Clients} = $hash->{Clients}.":SD_WS07:";
		    $hash->{MatchList}{"C:SD_WS07"} = "^P7#[A-Fa-f0-9]{6}F[A-Fa-f0-9]{2}";
		}
		my $dmsg = "P7#" . substr($msg, 0, $l-2, 2);
		$hash->{RAWMSG} = $msg;
		my %addvals = (RAWMSG => $msg, DMSG => $dmsg);
		Log3 $name, 5, "CUL_TCM97001 Dispatch $dmsg to other modul";
		Dispatch($hash, $dmsg, \%addvals);  ## Dispatch to other Modules 
		return "";
      }
      $temp    = (hex($a[3].$a[4].$a[5])) & 0x7FF;  
      my $negative    = (hex($a[3])) & 0x8; 
      if ($negative == 0x8) {
        $temp = (~$temp & 0x07FF) + 1;
        $temp = -$temp;
      }
      $temp = $temp / 10;

      

      $humidity = hex($a[7].$a[8]) & 0x7F;

      if (checkValues($temp, $humidity)) {
        $batbit = (hex($a[2]) & 0x8) >> 3;
        #$batbit = ~$batbit & 0x1; # Bat bit umdrehen
        $mode   = (hex($a[2]) & 0x4) >> 2;
        $channel = ((hex($a[2])) & 0x3) + 1;
        $model="Eurochron";
        
        if ($deviceCode ne $idType1)  # new naming convention
     	{	
     	    if ( $enableLongIDs == TRUE || (($longids != "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/))))
          	{
		         Log3 $hash,4, "CUL_TCM97001 using longid: $longids model: $model";
           	} else {
		         $deviceCode="CUL_TCM97001_" . $model . "_" . $channel;
           	}
     	}     
      
      	$def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
        if($def) {
          $name = $def->{NAME};
        }         
        if(!$def) {
            Log3 $name, 2, "CUL_TCM97001 Unknown device $deviceCode, please define it";
            return "UNDEFINED $model" . substr($deviceCode, rindex($deviceCode,"_")) . " CUL_TCM97001 $deviceCode"; 
        }
        if (defined($humidity)) {
          if ($humidity >= 20) {
            $hashumidity = TRUE;
          }  
        }  
        $hasbatcheck = TRUE;
        $haschannel = TRUE;
        $packageOK = TRUE;
        $hasmode = TRUE;
        
        $readedModel=$model;
        } else {
          $name = "Unknown";
        }
    }

		### inserted by elektron-bbs for rain gauge Ventus W174
		if (checksum_W174($msg) == TRUE && ($readedModel eq "Unknown" || $readedModel eq "W174")) {
   	   # VENTUS W174 Rain gauge
   	   # Documentation also at http://www.tfd.hu/tfdhu/files/wsprotocol/auriol_protocol_v20.pdf
   	   # * Format for Rain
   	   # *   AAAAAAAA vXXB CCCC DDDD DDDD DDDD DDDD EEEE FFFF FFFF 
   	   # *   RC            Type Rain                Checksum
   	   # *   A = Rolling Code /Device ID
   	   # *   B = Message type (xyyx = NON temp/humidity data if yy = '11')
   	   # *   v = 0: Sensor's battery voltage is normal, 1: Battery voltage is below ~2.6 V.
   	   # *  XX = 11: Non temperature/humidity data. All other type data packets have this value in this field.
   	   # *   C = fixed to 1100 for rain gauge
   	   # *   D = Rain (bitvalue * 0.25 mm)
   	   # *   E = Checksum
   	   # *   F = 0000 0000 (W174!!!)
			my @a = split("", $msg);
         my $bitReverse = undef;
         my $bitUnreverse = undef;
         my $x = undef;
         my $bin3;
			foreach $x (@a) {
            $bin3=sprintf("%024b",hex($x));
            $bitReverse = $bitReverse . substr(reverse($bin3),0,4); 
            $bitUnreverse = $bitUnreverse . sprintf( "%b", hex( substr($bin3,0,4) ) );
         }
         my $hexReverse = unpack("H*", pack ("B*", $bitReverse));
         my @aReverse = split("", $hexReverse);							# Split reversed a again
         Log3 $hash,4, "CUL_TCM97001: W174 original-msg: $msg , reversed nibbles: $hexReverse";
         Log3 $hash,4, "CUL_TCM97001: W174 nibble 2: $aReverse[2] , nibble 3: $aReverse[3]";
         # Nibble 2 must be x110 for rain gauge 
         # Nibble 3 must be 0x03 for rain gauge
         #if ((hex($aReverse[2]) & 0b0110) == 6 && $aReverse[3] == 3) {
         if ((hex($aReverse[2]) >> 1) == 3 && $aReverse[3] == 0x03) {
            Log3 $hash,4, "CUL_TCM97001: W174 detected rain gauge message ok";
            $batbit = $aReverse[2] & 0b0001;									# Bat bit normal=0, low=1
            Log3 $hash,4, "CUL_TCM97001: W174 battery bit: $batbit";
            $batbit = ~$batbit & 0x1; 												# Bat bit negation
            $hasbatcheck = TRUE;
            my $rainticks = hex($aReverse[4]) + hex($aReverse[5]) * 16 + hex($aReverse[6]) * 256 + hex($aReverse[7]) * 4096;
            Log3 $hash,4, "CUL_TCM97001: W174 rain gauge swing count: $rainticks";
            $rain = ($rainticks + ($rainticks & 1)) / 4;			# 1 tick = 0,5 l/qm
            Log3 $hash,4, "CUL_TCM97001: W174 rain total: $rain l/qm";
            $hasrain = TRUE;
            $model="W174";
            $def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
            if($def) {
               $name = $def->{NAME};
            }         
            if(!$def) {
               Log3 $name, 2, "CUL_TCM97001 Unknown device $deviceCode, please define it";
               return "UNDEFINED $model" . substr($deviceCode, rindex($deviceCode,"_")) . " CUL_TCM97001 $deviceCode"; 
            }
            $readedModel=$model;
				$packageOK = TRUE;
			}
		}
    
    if (checkCRC($msg) == TRUE && ($readedModel eq "Unknown" || $readedModel eq "TCM21....")) {
        # Long with tmp
        # All nibbles must be reversed  
        # e.g. 154E800480	   0001	0101 0100 1110 1000	0000 0000 0100 1000	0000
        #                      A    B    C    D    E    F    G    H    I
        # A+B = Addess
        # C Bit 1 Battery
        # D+E+F Temp 
        # G+H Hum
        # I CRC    
	#/* Documentation also at http://www.tfd.hu/tfdhu/files/wsprotocol/auriol_protocol_v20.pdf
	# * Message Format: (9 nibbles, 36 bits):
	# * Please note that bytes need to be reversed before processing!
	# *
	# * Format for Temperature Humidity
	# *   AAAAAAAA BBBB CCCC CCCC CCCC DDDDDDDD EEEE
	# *   RC       Type Temperature___ Humidity Checksum
	# *   A = Rolling Code / Device ID
	# *       Device ID: AAAABBAA BB is used for channel, base channel is 01
	# *       When channel selector is used, channel can be 10 (2) and 11 (3)
	# *   B = Message type (xyyz = temp/humidity if yy <> '11') else wind/rain sensor
	# *       x indicates battery status (0 normal, 1 voltage is below ~2.6 V)
	# *       z 0 indicates regular transmission, 1 indicates requested by pushbutton
	# *   C = Temperature (two's complement)
	# *   D = Humidity BCD format
	# *   E = Checksum
	# *
	# * Format for Rain
	# *   AAAAAAAA BBBB CCCC DDDD DDDD DDDD DDDD EEEE
	# *   RC       Type      Rain                Checksum
	# *   A = Rolling Code /Device ID
	# *   B = Message type (xyyx = NON temp/humidity data if yy = '11')
	# *   C = fixed to 1100   (C)
	# *   D = Rain (bitvalue * 0.25 mm)
	# *   E = Checksum
	# *
	# * Format for Windspeed
	# *   AAAAAAAA BBBB CCCC CCCC CCCC DDDDDDDD EEEE
	# *   RC       Type                Windspd  Checksum
	# *   A = Rolling Code
	# *   B = Message type (xyyx = NON temp/humidity data if yy = '11')
	# *   C = Fixed to 1000 0000 0000   (8)
	# *   D = Windspeed  (bitvalue * 0.2 m/s, correction for webapp = 3600/1000 * 0.2 * 100 = 72)
	# *   E = Checksum
	# *
	# * Format for Winddirection & Windgust
	# *   AAAAAAAA BBBB CCCD DDDD DDDD EEEEEEEE FFFF
	# *   RC       Type      Winddir   Windgust Checksum
	# *   A = Rolling Code
	# *   B = Message type (xyyx = NON temp/humidity data if yy = '11')
	# *   C = Fixed to 111  (E)
	# *   D = Wind direction
	# *   E = Windgust (bitvalue * 0.2 m/s, correction for webapp = 3600/1000 * 0.2 * 100 = 72)
	# *   F = Checksum
	# *********************************************************************************************
	# */                                                                         
        my @a = split("", $msg);
        my $bitReverse = undef;
        my $bitUnreverse = undef;
        my $x = undef;
        my $bin3;
               
        foreach $x (@a) {
           $bin3=sprintf("%024b",hex($x));
           $bitReverse = $bitReverse . substr(reverse($bin3),0,4); 
           $bitUnreverse = $bitUnreverse . sprintf( "%b", hex( substr($bin3,0,4) ) );
        }
        my $hexReverse = unpack("H*", pack ("B*", $bitReverse));

        #Split reversed a again
        my @aReverse = split("", $hexReverse);
        Log3 $hash,4, "CUL_TCM97001 hex:$hexReverse  msg:$msg aR:@aReverse ";
        
        #  Message type (xyyz = temp/humidity if yy <> '11') else wind/rain sensor
        #  Message type (xyyx = NON temp/humidity data if yy = '11')
        $msgtype = substr(sprintf( "%04b", hex( substr( $msg,2,1))),1,2);
        Log3 $hash,4, "CUL_TCM97001 nib2:$msgtype aRev: $aReverse[2]";
        
        $msgtype = substr(sprintf( "%04b", hex( $aReverse[2])),1,2);
        Log3 $hash,4, "CUL_TCM97001 nib2R:$msgtype hexR: $hexReverse";


        if ( $msgtype ne "11") {
        Log3 $hash,4, "CUL_TCM97001 Temp/Hum Msgype: $msgtype nib3:$aReverse[3] ";

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
        $hashumidity = TRUE;   
         
        } else {
        # Wind/Rain/Guest
        Log3 $hash,4, "CUL_TCM97001 Wind/Rain/Guest Msgype: $msgtype nib3:$aReverse[3] ";
          #   C = Fixed to 1000 0000 0000  Reverse 0001 0000 0000
          if ((hex($aReverse[3])== 0x1) && (hex($aReverse[4])== 0x0)) { # Windspeed
              $windSpeed = hex($aReverse[6]) + hex($aReverse[7]);
              $haswindspeed = TRUE;
              Log3 $hash,4, "CUL_TCM97001 windSpeed: $windSpeed ";
             }
             
          if ((hex($aReverse[3])== 0xF)) { # Windguest    Reverse 
              $windGuest = hex($aReverse[6]) + hex($aReverse[7]);
              $windDirection =  hex($aReverse[4]) + hex($aReverse[5]) ;
              $windDirectionText = $winddir_name[$windDirection];
              $haswind = TRUE;
              Log3 $hash,4, "CUL_TCM97001 windGuest: $windGuest ";
             }
          if ((hex($aReverse[3])== 0x3)) { # Rain
              $rain = (hex($aReverse[4]) + hex($aReverse[5]) + hex($aReverse[6]) + hex($aReverse[7])) * 0.25;
              $hasrain = TRUE;
              Log3 $hash,4, "CUL_TCM97001 rain: $rain ";
             }      
        }

       
        #if (checkValues($temp, $humidity)) {
        if (1) {
            $batbit = (hex($a[2]) & 0x8) >> 3;
            #$mode = (hex($a[2]) & 0x4) >> 2;
            $model="TCM21....";
            if ($deviceCode ne $idType1)  # new naming convention
         	{	
         	    if ( $enableLongIDs == TRUE || (($longids != "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/))))
              	{
		             Log3 $hash,4, "CUL_TCM97001 using longid: $longids model: $model";
               	} else {
		             $deviceCode="CUL_TCM97001_" . $model . "_" . $channel;
               	}
         	}     
          
          	$def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
            if($def) {
              $name = $def->{NAME};
            }         
            if(!$def) {
                Log3 $name, 2, "CUL_TCM97001 Unknown device $deviceCode, please define it";
                return "UNDEFINED $model" . substr($deviceCode, rindex($deviceCode,"_")) . " CUL_TCM97001 $deviceCode"; 
            }
            $packageOK = TRUE;
            $hasbatcheck = TRUE;
            $readedModel=$model;
        } else {
            $name = "Unknown";
        }
        
    } 
    
    

    if (checkCRC_GTWT02($msg) == TRUE && ($readedModel eq "GT_WT_02" || $readedModel eq "Type1" || $readedModel eq "Unknown")
        || checkCRC_Type1($msg) == TRUE && ($readedModel eq "Type1" || $readedModel eq "GT_WT_02" || $readedModel eq "Unknown")) {

		### edited by elektron-bbs for Checksum
		#http://www.ludwich.de/ludwich/Temperatur.html
		#https://github.com/merbanan/rtl_433/issues/117
		#    F    F    0    0    F    9    5    5    F   
        # 1111 1111 0000 0000 1111 1001 0101 0101 1111 
        #    A    B    C    D    E    F    G    H    I 
        # A+B = Zufällige Code wechelt beim Batteriewechsel
        # C Bit 4 Battery, 3 Manual, 2+1 Channel
        # D+E+F Temperatur, wenn es negativ wird muss man negieren und dann 1 addieren, wie im ersten Post beschrieben.
        # G+H Hum - bit 0-7 
        # I CRC
      #$def = $modules{CUL_TCM97001}{defptr}{$idType3};
		
      $temp    = (hex($a[3].$a[4].$a[5])) & 0x3FF;  
      my $negative    = (hex($a[3])) & 0xC; 
      if ($negative == 0xC) {
        $temp = (~$temp & 0x03FF) + 1;
        $temp = -$temp;
      }
      $temp = $temp / 10;
      $humidity = (hex($a[6].$a[7]) & 0x0FE) >> 1; # only the first 7 bits are the humidity

      if ($humidity > 100) {
        # HH - Workaround
        $humidity = 100;
      } elsif ($humidity < 20) {
        # LL - Workaround
        $humidity = 20;
      }

      if (checkValues($temp, $humidity)) {
        $channel = ((hex($a[2])) & 0x3) + 1;
        $batbit  = ((hex($a[2]) & 0x8) != 0x8);
        $mode    = (hex($a[2]) & 0x4) >> 2;
        if (checkCRC_GTWT02($msg) == TRUE) {
            $model="GT_WT_02";
        } else {
            $model="Type1";
        }
      
        if ($deviceCode ne $idType1)  # new naming convention
     	{	
	      	if ( $enableLongIDs == TRUE || (($longids != "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/))))
          	{
	             Log3 $hash,4, "CUL_TCM97001 using longid: $longids model: $model";
           	} else {
	             $deviceCode="CUL_TCM97001_" . $model . "_" . $channel;
           	}
     	}     
      
      	$def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
        if($def) {
          $name = $def->{NAME};
        }         
        if(!$def) {
            Log3 $name, 2, "CUL_TCM97001 Unknown device $deviceCode, please define it";
            return "UNDEFINED $model" . substr($deviceCode, rindex($deviceCode,"_")) . " CUL_TCM97001 $deviceCode"; 
        }
        $hashumidity = TRUE;
        $hasbatcheck = TRUE;  
        $haschannel = TRUE;   
        $hasmode = TRUE;  
        $packageOK = TRUE;
        
        $readedModel=$model;
      } else {
          $name = "Unknown";
      }
    }
    
    
      #Log3 $name, 4, "CUL_TCM97001: CRC for TCM21.... Failed, checking other protocolls";
      # Check for Prologue
    if ($readedModel eq "Prologue" || (hex($a[0]) == 0x9 && $readedModel eq "Unknown")) {
        # Protocol prologue start everytime with 1001
        # e.g. 91080F614C	   1001 0001 0000 1000 0000 1111 0110 0001 0100 1100
        #                      A    B    C    D    E    F    G    H    I
        # A = Startbit 1001
        # B+C = Random Address
        # D Bit 4 Battery, 3 Manual, 2+1 Channel 
        # E+F+G Bit 15+16 negativ temp, 14-0 temp
        # H+I Hum
        #$def = $modules{CUL_TCM97001}{defptr}{$idType3};
        #$def = $modules{CUL_TCM97001}{defptr}{$idType1};
        
        $temp    = (hex($a[4].$a[5].$a[6])) & 0x3FFF;  
        my $negative    = (hex($a[4])) & 0xC; 

        if ($negative == 0xC) {
          $temp = (~$temp & 0x03FF) + 1;
          $temp = -$temp;
        }
        $temp = $temp / 10;

        if (!(hex($a[7]) == 0xC && hex($a[8]) == 0xC)) {
          $humidity = hex($a[7].$a[8]);
        }

        
        
        if (checkValues($temp, $humidity)) {
            $channel = (hex($a[3])) & 0x3;
            $batbit = (hex($a[3]) & 0x8) >> 3;
            $batbit = ~$batbit & 0x1; # Bat bit umdrehen
            $mode = (hex($a[3]) & 0x4) >> 2;
            
            $model="Prologue";
            
            if ($deviceCode ne $idType1)  # new naming convention
         	{	
		      	if ( $enableLongIDs == TRUE || (($longids != "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/))))
              	{
		             Log3 $hash,4, "CUL_TCM97001 using longid: $longids model: $model";
               	} else {
		             $deviceCode="CUL_TCM97001_" . $model . "_" . $channel;
               	}
         	}     
          
          	$def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
            if($def) {
              $name = $def->{NAME};
            }         
            if(!$def) {
                Log3 $name, 2, "CUL_TCM97001 Unknown device $deviceCode, please define it";
                return "UNDEFINED $model" . substr($deviceCode, rindex($deviceCode,"_")) . " CUL_TCM97001 $deviceCode"; 
            }
            if (defined($humidity)) {
                if ($humidity >= 20) {
                  $hashumidity = TRUE;
                }  
            }  
            $hasbatcheck = TRUE;
            $hasmode = TRUE;
            $packageOK = TRUE;
            $haschannel = TRUE;
            
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

      $temp    = (hex($a[4].$a[5].$a[6])) & 0x7FFF;  
      my $negative    = (hex($a[4])) & 0x8; 

      if ($negative == 0x8) {
        $temp = (~$temp & 0x07FF) + 1;
        $temp = -$temp;
      }
      $temp = $temp / 10;
      
      $humidity = hex($a[7].$a[8]) & 0x7F;

      if (checkValues($temp, $humidity)) {
     	$model="NC_WS";
     	$channel = (hex($a[3])) & 0x3;
     	$batbit = (hex($a[3]) & 0x8) >> 3;
      	$batbit = ~$batbit & 0x1; # Bat bit umdrehen
      	$mode = (hex($a[3]) & 0x4) >> 2;
     
       	if ($deviceCode ne $idType1)  # new naming convention     
     	{	
		  	if ( $enableLongIDs == TRUE || (($longids != "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/))))
          	{
	             Log3 $hash,4, "CUL_TCM97001 using longid: $longids model: $model";
           	} else {
	             $deviceCode="CUL_TCM97001_" . $model . "_" . $channel;
           	}
     	}     
      
      	$def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
      	if($def) {
       	 $name = $def->{NAME};
      	} 
      	      	
        if(!$def) {
          Log3 $name, 2, "CUL_TCM97001 Unknown device $deviceCode, please define it";
          return "UNDEFINED $model" . substr($deviceCode, rindex($deviceCode,"_")) . " CUL_TCM97001 $deviceCode"; 
        }
        $hashumidity = TRUE;
        $hasbatcheck = TRUE;
        $hasmode = TRUE;
        $packageOK = TRUE;
        $haschannel = TRUE; 
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

      if (checkValues($temp, 50)) {
        $model="Rubicson";
        
        if ($deviceCode ne $idType1)  # new naming convention
     	{	
		  	if ( $enableLongIDs == TRUE || (($longids != "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/))))
          	{
	             Log3 $hash,4, "CUL_TCM97001 using longid: $longids model: $model";
           	} else {
	             $deviceCode="CUL_TCM97001_" . $model . "_" . $channel;
           	}
     	}     
      
      	$def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
      	if($def) {
       	 $name = $def->{NAME};
      	} 
      	      	
        if(!$def) {
          Log3 $name, 2, "CUL_TCM97001 Unknown device $deviceCode, please define it";
          return "UNDEFINED $model" . substr($deviceCode, rindex($deviceCode,"_")) . " CUL_TCM97001 $deviceCode"; 
        }

        $packageOK = TRUE;
        
        $readedModel=$model;
      } else {
          $name = "Unknown";
      }
    }

      if ( (checkCRC4($msg) == TRUE) && (isRain($msg)==TRUE) &&($readedModel eq "PFR_130" || $readedModel eq "Unknown")) {
      # Implementation from Femduino
      # Pollin PFR_130)
      # nibbles n2, n6 and n7 hold the Rain fall ticks
      #                /--------------------------------- Channel, changes after every battery change      
      #               /           / ------------------------ Battery state 0 == Ok      
      #              /           / /------------------------ ??Battery changed, Sync startet      
      #             /           / /  ----------------------- n2 lower two bits ->rain ticks      
      #            /           / / /    /------------------- neg Temp: if 1 then temp = temp - 4096
      #           /           / / /    /-------------------- 12 Bit Temperature
      #          /           / / /    /               /----- n6,n7 rain ticks 8 bit (n2 & 0x03 n6 n7) 
      #         /           / / /    /               /       /---- n8, CRC (xor n0 to n7)
      #         0101 0101  1 0 00   0001 0000 1011  11000100 xxxx
      # Bit     0          8 9 10   12              24       32
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
      Log3 $name, 5, "CUL_TCM97001: PFR_130 Temp=$temp";
        
      # rain values Pollin PFR_130      
      $rainticks = (hex($a[2].$a[6].$a[7])) & 0x3FF; #mask n2 n6 n7 for rain ticks
      Log3 $name, 5, "CUL_TCM97001: PFR_130 rainticks=$rainticks";
      $rainMM = $rainticks / 25 * .5; # rain height in mm/qm, verified against sensor receiver display
      Log3 $name, 5, "CUL_TCM97001: PFR_130 rain mm=$rainMM";
      
      if (checkValues($temp, 50)) {
        $batbit = (hex($a[2]) & 0x8) >> 3; # in auriol_protocol_v20.pdf bat bit is n2 & 0x08, same
        $batbit = ~$batbit & 0x1; # Bat bit umdrehen
        $mode   = (hex($a[2]) & 0x4) >> 2; # in auriol_protocol_v20.pdf mode is: n2 & 0x01, different

        $trend = (hex($a[7]) & 0x3); # in auriol_protocol_v20.pdf there is no trend bit
        $model="PFR_130";
        my $deviceCode;
     
     	if (!defined($modules{CUL_TCM97001}{defptr}{$idType1}))
     	{	
          if ( $enableLongIDs == TRUE || (($longids != "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/))))
          	{
	             $deviceCode="CUL_TCM97001_".$idType1;
	             Log3 $hash,4, "CUL_TCM97001 using longid: $longids model: $model";
           	} else {
	             $deviceCode="CUL_TCM97001_" . $model . "_" . $channel;
           	}
     	}  else  {  # Fallback for already defined devices use old naming convention
     		$deviceCode=$idType1;
     	}     
      
      	$def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
      	if($def) {
       	 $name = $def->{NAME};
      	} 
      	      	
        if(!$def) {
          Log3 $name, 2, "CUL_TCM97001 Unknown device $deviceCode, please define it";
          return "UNDEFINED $model" . substr($deviceCode, rindex($deviceCode,"_")) . " CUL_TCM97001 $deviceCode"; 
        }

        $hasbatcheck = TRUE;
        $hastrend = TRUE;     
        $packageOK = TRUE;
        $hasmode = TRUE;
        
        $readedModel=$model;
      } else {
          $name = "Unknown";
      }
    }

    if ( (isRain($msg)!=TRUE) && ($readedModel eq "AURIOL" || $readedModel eq "Unknown") && ($readedModel ne "PFR_130")) {
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

      if (checkValues($temp, 50)) {
        $batbit = (hex($a[2]) & 0x8) >> 3;
        $batbit = ~$batbit & 0x1; # Bat bit umdrehen
        $mode   = (hex($a[2]) & 0x4) >> 2;

        $trend = (hex($a[7]) & 0x3);
        $model="AURIOL";
        my $deviceCode;
     
     	if (!defined($modules{CUL_TCM97001}{defptr}{$idType1}))
     	{	
		  	if ( $enableLongIDs == TRUE || (($longids != "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/))))
          	{
	             $deviceCode="CUL_TCM97001_".$idType1;
	             Log3 $hash,4, "CUL_TCM97001 using longid: $longids model: $model";
           	} else {
	             $deviceCode="CUL_TCM97001_" . $model . "_" . $channel;
           	}
     	}  else  {  # Fallback for already defined devices use old naming convention
     		$deviceCode=$idType1;
     	}     
      
      	$def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
      	if($def) {
       	 $name = $def->{NAME};
      	} 
      	      	
        if(!$def) {
          Log3 $name, 2, "CUL_TCM97001 Unknown device $deviceCode, please define it";
          return "UNDEFINED $model" . substr($deviceCode, rindex($deviceCode,"_")) . " CUL_TCM97001 $deviceCode"; 
        }

        $hasbatcheck = TRUE;
        $hastrend = TRUE;     
        $packageOK = TRUE;
        $hasmode = TRUE;
        
        $readedModel=$model;
      } else {
          $name = "Unknown";
      }
    }

    
    #if (($readedModel eq "Unknown" || $readedModel eq "KW9010")) {
    if (checkCRCKW9010($msg) == TRUE && ($readedModel eq "Unknown" || $readedModel eq "KW9010")) {
        # Re: Tchibo Wetterstation 433 MHz - KW9010
        # See also http://forum.arduino.cc/index.php?PHPSESSID=ffoeoe9qeuv7rf4fh0d637hd74&topic=136836.msg1536416#msg1536416
        #                 /------------------------------------- Random ID part one      
        #                /    / -------------------------------- Channel switch       
        #               /    /  /------------------------------- Random ID part two      
        #              /    /  /  / ---------------------------- Battery state 0 == Ok      
        #             /    /  /  / / --------------------------- Trend (continous, rising, falling      
        #            /    /  /  / /  / ------------------------- forced send      
        #           /    /  /  / /  /  / ----------------------- Temperature
        #          /    /  /  / /  /  /          /-------------- Temperature sign bit. if 1 then temp = temp - 4096
        #         /    /  /  / /  /  /          /  /------------ Humidity
        #        /    /  /  / /  /  /          /  /       /----- Checksum
        #       0110 00 10 1 00 1  000000100011  00001101 1101
        #       0110 01 00 0 10 1  100110001001  00001011 0101
        # Bit   0    4  6  8 9  11 12            24       32
        #
        #5922B07BC0 42 21.2 66
        # 0101 10 01 0 01 0 001010110000 01111011 1100 0000
        #                   000011010100 11011110
        #                      212       222-156=66
        my @a = split("", $msg);
        my $bitReverse = undef;
        my $x = undef;
        foreach $x (@a) {
		    $bitReverse = $bitReverse . reverse(sprintf("%04b",hex($x))); 
        }
        Log3 $hash, 5 , "KW9010 CRC Matched: ($bitReverse)";
        
        my $hexReverse = unpack("H*", pack ("B*", $bitReverse));
        Log3 $hash, 5 , "KW9010 CRC Hex Matched: $hexReverse";

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
        $humidity = hex($aReverse[7].$aReverse[6]) - 156;
        

        #if (checkValues($temp, $humidity)) {
        if (1) {
            Log3 $hash, 5 , "KW9010 values are matching";
            
            $batbit = (hex($a[2]) & 0x8) >> 3;
            #$mode = (hex($a[2]) & 0x4) >> 2; 
            $channel = ((hex($a[1])) & 0xC) >> 2;
            $mode = (hex($a[2]) & 0x1);
            $trend = (hex($a[2]) & 0x6) >> 1;
            
            $model="KW9010";
            
            if ($deviceCode ne $idType1)  # new naming convention
         	{	
		      	if ( $enableLongIDs == TRUE || (($longids != "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/))))
              	{
		             Log3 $hash,4, "CUL_TCM97001 using longid: $longids model: $model";
               	} else {
		             $deviceCode="CUL_TCM97001_" . $model . "_" . $channel;
               	}
         	}     
          
          	$def = $modules{CUL_TCM97001}{defptr}{$deviceCode};
            if($def) {
              $name = $def->{NAME};
            }         
            if(!$def) {
                Log3 $name, 2, "CUL_TCM97001 Unknown device $deviceCode, please define it";
                return "UNDEFINED $model" . substr($deviceCode, rindex($deviceCode,"_")) . " CUL_TCM97001 $deviceCode"; 
            }
            $hashumidity = TRUE;    
            $packageOK = TRUE;
            $hasbatcheck = TRUE;
            $hastrend = TRUE;  
            $haschannel = TRUE; 
            
            $readedModel=$model;
        } else {
       		Log3 $hash, 5 , "KW9010 t:$temp / h:$humidity mismatch";
       		
            $name = "Unknown";
        }
    } 
     
  }
  
  
  if ($packageOK == TRUE) {
    # save lastT, calc rainMM sum for day and hour
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    my $lastDay=$mday;
    my $lastHour=$hour;
    my $rainSumDay=0;
    my $rainSumHour=0;
   
    if($def) {
      $def->{lastT} = $now;
    }
    readingsBeginUpdate($def);
    my ($val, $valH, $state);
    
	if (defined($temp)) {
    $msgtype = "temperature";
    $val = sprintf("%2.1f", ($temp) );
    $state="T: $val";
#    if ($hashumidity == TRUE) {
#      if ($model eq "Prologue") {
#         # plausibility check 
#         my $oldhumidity = ReadingsVal($name, "humidity", "unknown");
#         if ($oldhumidity eq "unknown" || ($humidity+15 > $oldhumidity && $humidity-15 < $oldhumidity)) {
#            $hashumidity = TRUE;
#         } else {
#            $hashumidity = FALSE;
#         }
#      } 
#    }
    }
    if ($model eq "PFR_130") {
      $lastDay = ReadingsVal($name, "lastDay", $lastDay);
      $lastHour = ReadingsVal($name, "lastHour", $lastHour);
      $rainSumDay=ReadingsVal($name, "RainD", $rainSumDay);
      $rainSumHour=ReadingsVal($name, "RainH", $rainSumHour);
      
      $msgtype = "temperature";
      $val = sprintf("%2.1f", ($temp) );
      $state="T: $val";
      Log3 $name, 5, "CUL_TCM97001 1. $lastDay : $lastHour : $rainSumDay : $rainSumHour";
      #rain Pollin PFR-130
      if($mday==$lastDay){
         #same day add rainMM
         $rainSumDay+=$rainMM;
      }else {
         #new day, start over
         $rainSumDay=$rainMM;
      } 
      if($hour==$lastHour){
         $rainSumHour+=$rainMM;
      }else{
	 $rainSumHour=$rainMM;
      }
      
      readingsBulkUpdate($def, "lastDay", $lastDay );
      readingsBulkUpdate($def, "lastHour", $lastHour );
      readingsBulkUpdate($def, "RainD", $rainSumDay );
      readingsBulkUpdate($def, "RainH", $rainSumHour );
      
      Log3 $name, 5, "CUL_TCM97001 2. $lastDay : $lastHour : $rainSumDay : $rainSumHour";
      $state="$state RainH: $rainSumHour RainD: $rainSumDay R: $rainticks Rmm: $rainMM";
      Log3 $name, 5, "CUL_TCM97001 $msgtype $name $id3 state: $state"; 
    } else {
    
        $msgtype = "temperature";
        $val = sprintf("%2.1f", ($temp) );
        $state="T: $val";
#    if ($hashumidity == TRUE) {
#      if ($model eq "Prologue") {
#         # plausibility check 
#         my $oldhumidity = ReadingsVal($name, "humidity", "unknown");
#         if ($oldhumidity eq "unknown" || ($humidity+15 > $oldhumidity && $humidity-15 < $oldhumidity)) {
#            $hashumidity = TRUE;
#         } else {
#            $hashumidity = FALSE;
#         }
#      } 
#    }
    }


        
      #zusätzlich Daten für Wetterstation
      if ($hasrain == TRUE) {
         ### inserted by elektron-bbs
         my $rain_old = ReadingsVal($name, "rain", "unknown");
         if ($rain != $rain_old) {
            readingsBulkUpdate($def, "israining", "yes");
         } else {
            readingsBulkUpdate($def, "israining", "no");
         }
         readingsBulkUpdate($def, "rain", $rain );
         $state = "R: $rain";
         $hasrain = FALSE;
      }
     
      if ($haswind == TRUE) {
          readingsBulkUpdate($def, "windGust", $windGuest );
          readingsBulkUpdate($def, "windDirection", $windDirection );
          #readingsBulkUpdate($def, "windDirectionDegree", $windDirection * 360 / 16);     
          readingsBulkUpdate($def, "windDirectionText", $windDirectionText );
          $state = "Wg: $windGuest "." Wd: $windDirectionText ";
          $haswind = FALSE;
      }
      
      if ($haswindspeed == TRUE) {
          readingsBulkUpdate($def, "windSpeed", $windSpeed );
          $state = "Ws: $windSpeed ";
          $haswindspeed = FALSE;
      }
   

    if ($hashumidity == TRUE) {
      $msgtypeH = "humidity";
      $valH = $humidity;
      $state="$state H: $valH";
      Log3 $name, 4, "CUL_TCM97001 $msgtype $name $id3 T: $val H: $valH"; 
    } else {
      $msgtype = "other";
      Log3 $name, 4, "CUL_TCM97001 $msgtype $name $id3";
      #Log3 $name, 4, "CUL_TCM97001 $msgtype $name $id3 ";
    }

    

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
        if ($battery ne  "ok") { readingsBulkUpdate($def, "battery", "ok"); }
      } else {
        if ($battery ne  "low") { readingsBulkUpdate($def, "battery", "low"); }
      }
    }
    if ($hasmode) {
      my $modeVal = ReadingsVal($name, "mode", "unknown");
      if ($mode) {
        if ($modeVal ne  "forced") { readingsBulkUpdate($def, "mode", "forced"); }    
      } else {
        if ($modeVal ne  "normal") { readingsBulkUpdate($def, "mode", "normal"); }
      }
    }
    if ($haschannel) {
      my $readChannel = ReadingsVal($name, "channel", "");
      if (defined($readChannel) && $readChannel ne $channel) { readingsBulkUpdate($def, "channel", $channel); }
    }
#    if ($model eq "Prologue" || $model eq "Eurochron") {
#         # plausibility check 
#         my $oldtemp = ReadingsVal($name, "temperature", "unknown");
#         if ($oldtemp eq "unknown" || ($val+5 > $oldtemp && $val-5 < $oldtemp)) {
#            readingsBulkUpdate($def, $msgtype, $val);
#         }
#    } else { 
        readingsBulkUpdate($def, $msgtype, $val);
#    }
    if ($hashumidity == TRUE) {
      readingsBulkUpdate($def, $msgtypeH, $valH);
    }
    
    readingsBulkUpdate($def, "state", $state);
    # for testing only
    #my $rawlen = length($msg);
    #my $rawVal = substr($msg, 0, $rawlen-2);
    #readingsBulkUpdate($def, "RAW", $rawVal);

    readingsEndUpdate($def, 1);
    if(defined($rssi)) {
      $def->{RSSI} = $rssi;
    } 
    $attr{$name}{model} = $model;



    return $name;
  } else {
    if (length($msg) == 8 || length($msg) == 10 || length($msg) == 12 || length($msg) == 14) {
    my $defUnknown = $modules{CUL_TCM97001}{defptr}{"CUL_TCM97001_Unknown"};
    
    if (!$defUnknown) {
      Log3 "Unknown", 2, "CUL_TCM97001 Unknown device Unknown, please define it";
      return "UNDEFINED Unknown CUL_TCM97001 CUL_TCM97001_Unknown"; 
    } 
    $name = $defUnknown->{NAME};
    Log3 $name, 4, "CUL_TCM97001 Device not implemented yet name Unknown msg $msg";

      my $rawlen = length($msg);
      my $rawVal = substr($msg, 0, $rawlen-2);
      my $state="Code: $rawVal";

    if ($defUnknown) {
      $defUnknown->{lastT} = $now;
    }

    $attr{$name}{model} = $model;
    readingsBeginUpdate($defUnknown);
    readingsBulkUpdate($defUnknown, "state", $state);

      # for testing only
      #readingsBulkUpdate($defUnknown, "RAW", $rawVal);

      readingsEndUpdate($defUnknown, 1);
      if(defined($rssi)) {
        $defUnknown->{RSSI} = $rssi;
      }

      #my $defSvg = $defs{"SVG_CUL_TCM97001_Unknown"}; 

      #if ($defSvg) {
      #  CommandDelete(undef, $defSvg->{NAME});
      #}
      return $name;
    }
  }


  return undef;
}

1;


=pod
=item summary    This module interprets temperature sensor messages.
=item summary_DE Module verarbeitet empfangene Nachrichten von Temp-Sensoren.
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
    <li>GT_WT_02</li>
    <li>AURIOL</li>
    <li>Eurochron</li>
    <li>KW9010</li>
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
    <li><a href="#model">model</a> (TCM97..., ABS700, TCM21...., Prologue, Rubicson, NC_WS, GT_WT_02, AURIOL, KW9010, Unknown)</li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>


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
    <li>GT_WT_02</li>
    <li>AURIOL</li>
    <li>Eurochron</li>
    <li>KW9010</li>
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
    <li><a href="#model">model</a> (TCM97..., ABS700, TCM21...., Prologue, Rubicson, NC_WS, GT_WT_02, AURIOL, KW9010, Unknown)</li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>


</ul>

=end html_DE
=cut
