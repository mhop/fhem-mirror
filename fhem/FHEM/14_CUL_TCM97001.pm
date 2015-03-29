##############################################
# From dancer0705
# Receive TCM 97xxx, TCM 21xxxx, GT-WT-xx and Rubicson like temperature sensor
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
# $Id: 14_CUL_TCM97001.pm 8286 2015-03-25 20:47:59Z dancer0705 $

package main;



use strict;
use warnings;

use SetExtensions;
use constant { TRUE => 1, FALSE => 0 };

my %models = (
    "TCM97..."    => 'TCM97...',
    "TCM21...."   => 'TCM21....',
    "Prologue"    => 'Prologue',
    "Rubicson"    => 'Rubicson',
    "Unknown"    => 'Unknown',
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

###################################
sub
CUL_TCM97001_Parse($$)
{
  my ($hash, $msg) = @_;
  $msg = substr($msg, 1);
  my @a = split("", $msg);

  my $id3 = hex($a[0] . $a[1]);
  my $id4 = hex($a[0] . $a[1] . $a[2] . (hex($a[3]) & 0x3));

  my $def = $modules{CUL_TCM97001}{defptr}{$id3};
  my $def2 = $modules{CUL_TCM97001}{defptr}{$id4};
  my $defUnknown = $modules{CUL_TCM97001}{defptr}{"Unknown"};
  
  my $now = time();

  my $name = "Unknown";
  if($def) {
    $name = $def->{NAME};
  } elsif($def2) {
    $name = $def2->{NAME};
  } elsif($defUnknown) {
    $name = $defUnknown->{NAME};
  }
  
  my $rssi;
  my $l = length($msg);
  $rssi = hex(substr($msg, $l-2, 2));
  $rssi = ($rssi>=128 ? (($rssi-256)/2-74) : ($rssi/2-74));

  Log3 $name, 4, "CUL_TCM97001 $name $id3 or $id4 ($msg) length:" . length($msg) . " RSSI: $rssi";

  my ($msgtype, $msgtypeH, $val, $valH);

  my $packageOK = FALSE;
  my $state="";
  my $batbit=undef;
  my $mode=undef;
  my $hashumidity = FALSE;
  my $hasbatcheck = FALSE;
  my $model="Unknown";
  
  if (length($msg) == 8) {
    # Only tmp TCM device
    #eg. 1000 1111 0100 0011 0110 1000 = 21.8C
    #eg. --> shift2  0100 0011 0110 10
    my $temp    = (hex($a[3].$a[4].$a[5]) >> 2) & 0xFFFF;  


    my $negative    = (hex($a[2]) >> 0) & 0x3; 

    if ($negative == 0x3) {
      $temp = (~$temp & 0x03FF) + 1;
      $temp = -$temp;
    }

    $temp = $temp / 10;

    if($def) {
      $def->{lastT} = $now;
    } 
    $msgtype = "temperature";
    $val = sprintf("%2.1f", ($temp) );
    Log3 $name, 4, "CUL_TCM97001 $msgtype $name $id3 T: $val";


    # I think bit 3 on byte 3 is battery warning
    $batbit    = (hex($a[2]) >> 0) & 0x4; 

    $mode    = (hex($a[5]) >> 0) & 0x1; 

    my $unknown    = (hex($a[4]) >> 0) & 0x2; 
    my $t = ReadingsVal($name, "temperature", undef);

    if(defined($t)) {
      $state="T: $t";
    }
    
    if ($mode) {
      Log3 $name, 5, "CUL_TCM97001 Mode: manual triggert";
    } else {
      Log3 $name, 5, "CUL_TCM97001 Mode: auto triggert";
    }
    if ($unknown) {
        Log3 $name, 5, "CUL_TCM97001 Unknown Bit: $unknown";
    }
    my $debug = "TEMP:$val°C BATT:";
    if ($batbit) {
      $debug = $debug . "empty";
    } else {
      $debug = $debug . "OK";
    }
    $debug = $debug . " HEX:0x";
    $debug = $debug . $a[0].$a[1].$a[2].$a[3].$a[4].$a[5];
    $debug = $debug . " BIN:";

    my @list = unpack("(A4)*", unpack ('B*', pack ('H*',$a[0].$a[1].$a[2].$a[3].$a[4].$a[5])));
    my $string = join(" ", @list);
    $debug = $debug . $string;
    Log3 $name, 5, "CUL_TCM97001 DEBUG: $debug";

    $packageOK = TRUE;
    $hasbatcheck = TRUE;
    $model="TCM97...";
  } elsif (length($msg) == 12) { 
    # Long with tmp
    # All nibbles must be reversed  
    # e.g. 154E800480	   0001	0101 0100	1110 1000	0000 0000	0100 1000	0000
    #                      A    B    C    D    E    F    G    H    I
    # A+B = Addess
    # C Bit 1 Battery
    # D+E+F Temp 
    # G+H Hum
    my $bin = undef;
    $hashumidity = TRUE;
    my $readedModel = AttrVal($name, "model", undef);

    if (checkCRC($msg) == TRUE && (!$readedModel || $readedModel eq "TCM21....")) {
        Log3 $name, 5, "CUL_TCM97001: CRC OK";
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
        my $temp = undef;
        if (hex($aReverse[5]) > 3) {
           # negative temp
           $temp = ((-hex($aReverse[3]) + -hex($aReverse[4]) * 16 + -hex($aReverse[5]) * 256)+1+4096)/10;
        } else {
           # positive temp
           $temp = (hex($aReverse[3]) + hex($aReverse[4]) * 16 + hex($aReverse[5]) * 256)/10;
        }

        if($def) {
          $def->{lastT} = $now;
        } 
        my $humidity = hex($aReverse[7]).hex($aReverse[6]);

        $msgtypeH = "humidity";
        $valH = $humidity;

        $msgtype = "temperature";
        $val = sprintf("%2.1f", ($temp) );

        Log3 $name, 4, "CUL_TCM97001 $msgtype $name $id3 T: $val H: $humidity"; 

        my $t = ReadingsVal($name, "temperature", undef);
        my $h = ReadingsVal($name, "humidity", undef);
        if(defined($t) && defined($h)) {
          $state="T: $t H: $h";

        } elsif(defined($t)) {
          $state="T: $t";
        } elsif(defined($h)) {
          $state="H: $h";
        }        

        $batbit = hex($aReverse[2]) & 1;
        $mode = (hex($aReverse[2]) & 8) >> 3;

        if ($mode) {
          Log3 $name, 5, "CUL_TCM97001 Mode: manual triggert";
        } else {
          Log3 $name, 5, "CUL_TCM97001 Mode: auto triggert";
        }
        my $debug = "TEMP:$val°C HUM:$humidity :BATT:";
        if ($batbit) {
          $debug = $debug . "empty";
        } else {
          $debug = $debug . "OK";
        }
        $debug = $debug . " HEX:0x";
        $debug = $debug . $hexReverse;
        $debug = $debug . " BIN:$bitReverse";
        Log3 $name, 5, "CUL_TCM97001 DEBUG: $debug";
        
        $packageOK = TRUE;
        $hasbatcheck = TRUE;
        $model="TCM21....";
    } else {
        Log3 $name, 4, "CUL_TCM97001: CRC for TCM21.... Failed, checking other protocolls";
        # Check for Prologue
        if (hex($a[0]) == 0x9) {
          $model="Prologue";
          # Protocol prologue start everytime with 1001
          # e.g. 91080F614C	    1001 0001 0000 1000 0000 1111 0110 0001 0100 1100
          #                      A    B    C    D    E    F    G    H    I
          # A = Startbit 1001
          # B+C = Random Address
          # D Bit 4 Battery, 3 Manual, 2+1 Channel 
          # E+F+G Bit 15+16 negativ temp, 14-0 temp
          # H+I Hum

          my $temp    = (hex($a[4].$a[5].$a[6])) & 0x3FFF;  
          my $negative    = (hex($a[4])) & 0xC; 

          if ($negative == 0xC) {
            $temp = (~$temp & 0x03FF) + 1;
            $temp = -$temp;
          }
          $temp = $temp / 10;

          if($def2) {
            $def2->{lastT} = $now;
          }
          $msgtype = "temperature";
          $val = sprintf("%2.1f", ($temp) );

          my $humidity=undef;
          if (hex($a[7]) != 0xC && hex($a[8]) != 0xC) {
            $hashumidity = TRUE;
            $humidity = hex($a[7].$a[8]);

            $msgtypeH = "humidity";
            $valH = $humidity;
          }

          Log3 $name, 4, "CUL_TCM97001 $msgtype $name $id4 T: $val H: $humidity"; 
        
          my $t = ReadingsVal($name, "temperature", undef);
          my $h = ReadingsVal($name, "humidity", undef);
          if(defined($t) && defined($h)) {
            $state="T: $t H: $h";
          } elsif(defined($t)) {
            $state="T: $t";
          } elsif(defined($h)) {
            $state="H: $h";
          }

          $batbit = (hex($a[3]) & 0x8) >> 3;
          $mode = (hex($a[2]) & 0x4) >> 2;
          $hasbatcheck = TRUE;
          $packageOK = TRUE;
      } elsif (hex($a[2]) == 0x8) {
          $model="Rubicson";
          # Protocol Rubicson has as nibble C every time 1000
          # e.g. F4806B8E14	    1111 0100 1000 0000 0110 1011 1000 1110	0001 0100
          #                      A    B    C    D    E    F    G    H    I
          # A+B = Random Address
          # C = Rubicson = 1000
          # D+E+F 12 bit temp
          # G+H+I Unknown
          my $temp    = (hex($a[3].$a[4].$a[5])) & 0x3FFF;  
          my $negative    = (hex($a[3])) & 0xC; 

          if ($negative == 0xC) {
            $temp = (~$temp & 0x03FF) + 1;
            $temp = -$temp;
          }
          $temp = $temp / 10;

          if($def) {
            $def->{lastT} = $now;
          }
          $msgtype = "temperature";
          $val = sprintf("%2.1f", ($temp) );

          Log3 $name, 4, "CUL_TCM97001 $msgtype $name $id3 T: $val"; 
          my $t = ReadingsVal($name, "temperature", undef);

          if(defined($t)) {
            $state="T: $t";
          }
          $packageOK = TRUE;
      }
    }
  }
  
  if ($packageOK == TRUE) {
    if(!$def && !$def2) {
      if ($model eq "Prologue") {
        Log3 $name, 2, "CUL_TCM97001 Unknown device $id4, please define it";
        return "UNDEFINED CUL_TCM97001_$id4 CUL_TCM97001 $id4" if(!$def2); 
      } else {
        Log3 $name, 2, "CUL_TCM97001 Unknown device $id3, please define it";
        return "UNDEFINED CUL_TCM97001_$id3 CUL_TCM97001 $id3" if(!$def); 
      }
    }
    if ($model eq "Prologue") {
      $def = $def2;
    }
    readingsBeginUpdate($def);
    readingsBulkUpdate($def, "state", $state);
    $attr{$name}{model} = $model;
    if ($hasbatcheck) {
      if ($batbit) {
        readingsBulkUpdate($def, "battery", "low");
      } else {
        readingsBulkUpdate($def, "battery", "ok");
      }
    }
    readingsBulkUpdate($def, $msgtype, $val);
    if ($hashumidity == TRUE) {
      readingsBulkUpdate($def, $msgtypeH, $valH);
    }
    readingsEndUpdate($def, 1);
    if(defined($rssi)) {
      $def->{RSSI} = $rssi;
      #$addvals{RSSI} = $rssi;
    }
    return $name;
  } else {
    Log3 $name, 4, "CUL_TCM97001 Device not interplmeted yet name $name msg $msg";
    if (!$defUnknown) {
      Log3 $name, 2, "CUL_TCM97001 Unknown device $name, please define it";
      return "UNDEFINED CUL_TCM97001_$name CUL_TCM97001 $name" if(!$defUnknown); 
    } 

    $state="Code: $msg";

    if ($defUnknown) {
      $defUnknown->{lastT} = $now;
    };

    my $defSvg = $defs{"SVG_CUL_TCM97001_Unknown"}; 

    if ($defSvg) {
      CommandDelete(undef, $defSvg->{NAME});
    }
    $attr{$name}{model} = $model;
    readingsBeginUpdate($defUnknown);
    readingsBulkUpdate($defUnknown, "state", $state);
    readingsEndUpdate($defUnknown, 1);
    if(defined($rssi)) {
      $defUnknown->{RSSI} = $rssi;
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
  The CUL_TCM97001 module interprets temperature messages of TCM 97xxx, TCM 21xxxx, GT-WT-xx and Rubicson sensor received by the CUL.<br>
  <br>
  New received device packages are add in fhem category CUL_TCM97001 with autocreate.
  <br><br>

  <a name="CUL_TCM97001define"></a>
  <b>Define</b> <ul>The received devices created automatically.</ul><br>

  <a name="CUL_TCM97001events"></a>
  <b>Generated events:</b>
  <ul>
     <li>temperature: $temp</li>
     <li>humidity: $hum</li>
     <li>battery: $bat</li>
  </ul>
  <br>

</ul>


=end html
=cut
