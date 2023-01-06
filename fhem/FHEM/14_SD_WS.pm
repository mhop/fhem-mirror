# $Id$
#
# The purpose of this module is to support serval
# weather sensors which use various protocol
#
# Sidey79 & Ralf9   2016 - 2017
# Joerg             2017
# elektron-bbs      2018 -
#
# 17.04.2017 WH2 (TFA 30.3157 nur Temp, Hum = 255),es wird das Perlmodul Digest:CRC benoetigt fuer CRC-Pruefung benoetigt
# 29.05.2017 Test ob Digest::CRC installiert
# 22.07.2017 WH2 angepasst
# 21.08.2017 WH2 Abbruch wenn kein "FF" am Anfang
# 18.08.2018 Protokoll 51 - prematch auf genau 10 Nibbles angepasst, Protokoll 33 - prematch auf genau 11 Nibbles angepasst
# 21.08.2018 Modelauswahl hinzugefuegt, da 3 versch. Typen SD_WS_33 --> Batterie-Bit Positionen unterschiedlich (34,35,36)
# 11.09.2018 Plotanlegung korrigiert | doc | temp check war falsch positioniert
# 16.09.2018 neues Protokoll 84: Funk Wetterstation Auriol IAN 283582 Version 06/2017 (Lidl), Modell-Nr.: HG02832D
# 31.09.2018 neues Protokoll 85: Kombisensor TFA 30.3222.02 fuer Wetterstation TFA 35.1140.01
# 09.12.2018 neues Protokoll 89: Temperatur-/Feuchtesensor TFA 30.3221.02 fuer Wetterstation TFA 35.1140.01
# 06.01.2019 Protokoll 33: Temperatur-/Feuchtesensor TX-EZ6 fuer Wetterstation TZS First Austria hinzugefuegt
# 03.03.2019 neues Protokoll 38: Rosenstein & Soehne, PEARL NC-3911, NC-3912, Kuehlschrankthermometer
# 07.04.2019 Protokoll 51: Buxfix longID 8 statt 12 bit, prematch channel 1-3
# 15.04.2019 Protokoll 33: sub crcok ergaenzt
# 02.05.2019 neues Protokoll 94: Atech wireless weather station (vermutlicher Name: WS-308)
# 14.06.2019 neuer Sensor TECVANCE TV-4848 - Protokoll 84 angepasst (prematch)
# 09.11.2019 neues Protokoll 53: Lidl AURIOL AHFL 433 B2 IAN 314695
# 29.12.2019 neues Protokoll 27: Temperatur-/Feuchtigkeitssensor EuroChron EFTH-800
# 09.02.2020 neues Protokoll 54: Regenmesser TFA Drop
# 22.02.2020 Protokoll 58: neuer Sensor TFA 30.3228.02, FT007T Thermometer Sensor
# 25.08.2020 Protokoll 27: neuer Sensor EFS-3110A
# 27.09.2020 neues Protokoll 106: BBQ Temperature Sensor GT-TMBBQ-01s (Sender), GT-TMBBQ-01e (Empfaenger)
# 01.05.2021 neues Protokoll 108: Bresser 5-in-1 Comfort Wetter Center, Profi Regenmesser
# 15.05.2021 neues Protokoll 110: ADE WS1907 Weather station with rain gauge
# 03.06.2021 PerlCritic - HardTabs durch Leerzeichen ersetzt & Einrueckungen sortiert (keine Code/Syntaxaenderung vorgenommen)
# 06.06.2021 neues Protokoll 111: TS-FT002 Water tank level monitor with temperature
# 16.07.2021 neues Protokoll 113: Wireless Grill Thermometer, Model name: GFGT 433 B1
# 31.07.2021 neues Protokoll 115: Bresser 6-in-1 Comfort Wetter Center
# 30.08.2021 PerlCritic - fixes for severity level 5 and 4
# 07.12.2021 Protokoll 33: Conrad S522 kein Batteriebit, dafuer Trend Temperatur
# 05.01.2022 Protokoll 108: neuer Sensor Fody E42
# 08.01.2022 neues Protokoll 107: Soil Moisture Sensor Fine Offset WH51, ECOWITT WH51, MISOL/1, Froggit DP100
# 14.01.2022 neues Protokoll 116: Thunder and lightning sensor Fine Offset WH57, aka Froggit DP60, aka Ambient Weather WH31L
# 29.01.2022 neues Protokoll 117: Bresser 7-in-1 Comfort Wetter Center
# 04.02.2022 neu: set replaceBatteryForSec (Ident ersetzen bei Batteriewechsel Sensor)
# 12.03.2022 Protokoll 115: neue Sensoren SM60020 Boden-/Erd-Sensor für Feuchte- und Temperatur, Innensensor für Feuchte- und Temperatur
# 11.04.2022 Protokoll 85: neuer Sensor Windmesser TFA 30.3251.10 mit Windrichtung, Pruefung CRC8 eingearbeitet
# 23.05.2022 neues Protokoll 120: Wetterstation TFA 35.1077.54.S2 mit 30.3151 (Thermo/Hygro-Sender), 30.3152 (Regenmesser), 30.3153 (Windmesser)
# 11.06.2022 neues Protokoll 122: TM40, Wireless Grill-, Meat-, Roasting-Thermometer with 4 Temperature Sensors

package main;

#use version 0.77; our $VERSION = version->declare('v3.5.4');

use strict;
use warnings;
use Carp qw(carp);
use FHEM::Meta;

# Forward declarations
sub SD_WS_LFSR_digest8_reflect;
sub SD_WS_bin2dec;
sub SD_WS_binaryToNumber;
sub SD_WS_WH2CRCCHECK;
sub SD_WS_WH2SHIFT;

sub SD_WS_Initialize {
  my $hash = shift // return;
  $hash->{Match}    = '^W\d+x{0,1}#.*';
  $hash->{DefFn}    = \&SD_WS_Define;
  $hash->{UndefFn}  = \&SD_WS_Undef;$hash->{SetFn}    = \&SD_WS_Set;
  $hash->{ParseFn}  = \&SD_WS_Parse;
  $hash->{AttrList} = "do_not_notify:1,0 ignore:0,1 showtime:1,0 " .
                      "model:E0001PA,S522,TFA_30.3251.10,TX-EZ6,other " .
                      "max-deviation-temp:1,2,3,4,5,6,7,8,9,10,15,20,25,30,35,40,45,50 ".
                      "max-deviation-hum:1,2,3,4,5,6,7,8,9,10,15,20,25,30,35,40,45,50 ".
                      "$readingFnAttributes ";
  $hash->{AutoCreate} =
  {
    "BresserTemeo.*"  => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "temp4hum4:Temp/Hum,", autocreateThreshold => "2:180"},
    "SD_WS_WH2.*"     => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "temp4hum4:Temp/Hum,", autocreateThreshold => "2:120"},
    "SD_WS37_TH.*"    => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "temp4hum4:Temp/Hum,", autocreateThreshold => "2:180"},
    "SD_WS50_SM.*"    => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "temp4hum4:Temp/Hum,", autocreateThreshold => "2:180"},
    "SD_WS71_T.*"     => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "temp4:Temp,", autocreateThreshold => "2:180"},
    "SD_WS_106_T.*"   => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "temp4:Temp,", autocreateThreshold => "5:60"},
    "SD_WS_27_TH_.*"  => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "temp4hum4:Temp/Hum,", autocreateThreshold => "3:180"},
    "SD_WS_33_TH_.*"  => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.* model:other", FILTER => "%NAME", GPLOT => "temp4hum4:Temp/Hum,", autocreateThreshold => "2:180"},
    "SD_WS_33_T_.*"   => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.* model:other", FILTER => "%NAME", GPLOT => "temp4:Temp,", autocreateThreshold => "2:180"},
    "SD_WS_38_T_.*"   => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "temp4:Temp,", autocreateThreshold => "3:180"},
    "SD_WS_51_TH.*"   => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "temp4hum4:Temp/Hum,", autocreateThreshold => "3:180"},
    "SD_WS_53_TH.*"   => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "temp4hum4:Temp/Hum,", autocreateThreshold => "3:180"},
    "SD_WS_54_R.*"    => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "rain4:Rain,", autocreateThreshold => "3:180"},
    "SD_WS_58_TH.*"   => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "temp4hum4:Temp/Hum,", autocreateThreshold => "2:90"},
    "SD_WS_58_T_.*"   => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "temp4:Temp,", autocreateThreshold => "2:90"},
    "SD_WS_84_TH_.*"  => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "temp4hum4:Temp/Hum,", autocreateThreshold => "2:120"},
    "SD_WS_85_THW_.*" => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "temp4hum4:Temp/Hum,", autocreateThreshold => "4:120"},
    "SD_WS_89_TH.*"   => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "temp4hum4:Temp/Hum,", autocreateThreshold => "3:180"},
    "SD_WS_94_T.*"    => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", FILTER => "%NAME", GPLOT => "temp4:Temp,", autocreateThreshold => "3:180"},
    'SD_WS_107_H.*'   => { ATTR => 'event-min-interval:.*:300 event-on-change-reading:.*', FILTER => '%NAME', GPLOT => q{}, autocreateThreshold => '2:180'},
    'SD_WS_108.*'     => { ATTR => 'event-min-interval:.*:300 event-on-change-reading:.*', FILTER => '%NAME', GPLOT => 'temp4:Temp,', autocreateThreshold => '5:120'},
    'SD_WS_110_TR.*'  => { ATTR => 'event-min-interval:.*:300 event-on-change-reading:.*', FILTER => '%NAME', GPLOT => 'temp4:Temp,', autocreateThreshold => '3:180'},
    'SD_WS_111_TL.*'  => { ATTR => 'event-min-interval:.*:300 event-on-change-reading:.*', FILTER => '%NAME', GPLOT => 'temp4:Temp,', autocreateThreshold => '3:600'},
    'SD_WS_113_T.*'   => { ATTR => 'event-min-interval:.*:60 event-on-change-reading:.*', FILTER => '%NAME', GPLOT => 'temp4:Temp,', autocreateThreshold => '10:180'},
    'SD_WS_115.*'     => { ATTR => 'event-min-interval:.*:300 event-on-change-reading:.*', FILTER => '%NAME', GPLOT => 'temp4hum4:Temp/Hum,', autocreateThreshold => '5:120'},
    'SD_WS_116.*'     => { ATTR => 'event-min-interval:.*:300 event-on-change-reading:.*', FILTER => '%NAME', GPLOT => q{}, autocreateThreshold => '2:180'},
    'SD_WS_117.*'     => { ATTR => 'event-min-interval:.*:300 event-on-change-reading:.*', FILTER => '%NAME', GPLOT => 'temp4hum4:Temp/Hum,', autocreateThreshold => '5:120'},
    'SD_WS_120.*'     => { ATTR => 'event-min-interval:.*:300 event-on-change-reading:.*', FILTER => '%NAME', GPLOT => 'temp4hum4:Temp/Hum,', autocreateThreshold => '2:180'},
    'SD_WS_122_T.*'   => { ATTR => 'event-min-interval:.*:60 event-on-change-reading:.*', FILTER => '%NAME', GPLOT => 'temp4:Temp,', autocreateThreshold => '10:180'},
  };
  return FHEM::Meta::InitMod( __FILE__, $hash );
}

#############################
sub SD_WS_Define {
  my ($hash, $def) = @_;
  carp "SD_WS_Define, too few arguments ($hash, $def)" if @_ < 2;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> SD_WS <code> ".int(@a) if(int(@a) < 3 );

  $hash->{CODE} = $a[2];
  $hash->{lastMSG} =  "";
  $hash->{bitMSG} =  "";

  $modules{SD_WS}{defptr}{$a[2]} = $hash;
  $hash->{STATE} = "Defined";

  my $name= $hash->{NAME};
  return;
}

#############################
sub SD_WS_Undef {
  my ($hash, $name) = @_;
  carp "SD_WS_Undef, too few arguments ($hash, $name)" if @_ < 2;
  delete($modules{SD_WS}{defptr}{$hash->{CODE}}) if(defined($hash->{CODE}) && defined($modules{SD_WS}{defptr}{$hash->{CODE}}));
  RemoveInternalTimer($hash);
  return;
}

#############################
sub SD_WS_Set {
  my $hash = shift // carp 'device hash needs to be first parameter';
  my $name = shift // carp 'name of the device must be second parameter';
  my $cmd = shift // carp 'Specify the command as third prarameter';
  my @args = @_;

  my $ret = undef;
  my $LastInputDev = $hash->{LASTInputDev};
  return $ret if (!defined $LastInputDev);

  my $rhash = $defs{$LastInputDev};
  my $rlongids = AttrVal($rhash->{NAME},'longids',0);
  my $def = $hash->{DEF};
  my @array = split(/_/,$def);
  my $model = $array[0] . '_' . $array[1] . '_' . $array[2];
  if (($rlongids ne "0") && ($rlongids eq "1" || $rlongids eq "ALL" || ($rlongids =~ m/$model/))) {
    if ($cmd eq '?') {
      $ret = 'replaceBatteryForSec'; # return setList
    } elsif ($cmd eq 'replaceBatteryForSec') {
      return "$name: No or too small value specified for the replaceBatteryForSec command" if (scalar(@args) < 1 || $args[0] < 1);
      my @found = devspec2array("TYPE=SD_WS:FILTER=i:replaceBattery>0");
      return "$name: Only one sensor at a time, replaceBatteryForSec is already activated at @found" if (scalar(@found) > 0);
      my $repBatForSec = $args[0];
      $hash->{replaceBattery} = $repBatForSec;
      InternalTimer(gettimeofday() + $repBatForSec, \&SD_WS_TimerRemoveReplaceBattery, $hash, 0);
      Log3 $name, 3, "$name: SD_WS_Set, wait $repBatForSec seconds for a new identity of the sensor"; 
    } else {
      $ret = "$name: Unknown argument $cmd, choose replaceBatteryForSec";
    }

  }
  return $ret;
}

#############################
sub SD_WS_TimerRemoveReplaceBattery {
  my $hash = shift;
  my $name = $hash->{NAME};
  delete($hash->{replaceBattery});
  RemoveInternalTimer($hash);
  Log3 $name, 3, "$name: SD_WS_TimerRemoveReplaceBattery, no sensor with unknown identity received"; 
  return;
}

#############################
sub SD_WS_Parse {
  my ($iohash, $msg) = @_;
  carp "SD_WS_Parse, too few arguments ($iohash, $msg)" if @_ < 2;
  my $name = $iohash->{NAME};
  my $ioname = $iohash->{NAME};
  my ($protocol,$rawData) = split("#",$msg);
  $protocol=~ s/^[WP](\d+)/$1/; # extract protocol
  my $dummyreturnvalue= "Unknown, please report";
  my $hlen = length($rawData);
  my $blen = $hlen * 4;
  my $bitData = unpack("B$blen", pack("H$hlen", $rawData));
  my $bitData2;
  my $model;  # wenn im elsif Abschnitt definiert, dann wird der Sensor per AutoCreate angelegt
  my $SensorTyp;
  my $id;
  my $bat;
  my $batChange;
  my $batVoltage;
  my $batteryPercent;
  my $sendmode;
  my $channel;
  my $rawTemp;
  my $temp;
  my $temp2;
  my $temp3;
  my $temp4;
  my $hum;
  my $windspeed;
  my $winddir;
  my $winddirtxt;
  my @winddirtxtar=('N','NNE','NE','ENE','E','ESE','SE','SSE','S','SSW','SW','WSW','W','WNW','NW','NNW','N');
  my $windgust;
  my $trend;
  my $trendTemp;
  my $trendHum;
  my $rain;
  my $rain_total;
  my $rawRainCounter;
  my $sendCounter;
  my $beep;
  my $distance;
  my $uv;
  my $adc;
  my $brightness;
  my @moisture_map=(0, 7, 13, 20, 27, 33, 40, 47, 53, 60, 67, 73, 80, 87, 93, 99); # ID 115
  my $count;
  my $identified;
  my $transmitter;
  my $dcf;

  my %decodingSubs = (
    50 => # Protocol 50
     # FF550545FF9E
     # FF550541FF9A 
     # AABCDDEEFFGG
     # A = Preamble, always FF
     # B = TX type, always 5
     # C = Address (5/6/7) > low 2 bits = 1/2/3
     # D = Soil moisture 05% 
     # E = temperature 
     # F = security code, always F
     # G = Checksum 55+05+45+FF=19E CRC value = 9E
        {   # subs to decode this
          sensortype => 'XT300',
          model      => 'SD_WS_50_SM',
          prematch   => sub {my $msg = shift; return 1 if ($msg =~ /^FF5[0-9A-F]{5}FF[0-9A-F]{2}/); },           # prematch
          crcok      => sub {my $msg = shift; return 1 if ((hex(substr($msg,2,2))+hex(substr($msg,4,2))+hex(substr($msg,6,2))+hex(substr($msg,8,2))&0xFF) == (hex(substr($msg,10,2))) );  },   # crc
          id         => sub {my $msg = shift; return (hex(substr($msg,2,2)) &0x03 ); },                          # id
          temp       => sub {my $msg = shift; return  ((hex(substr($msg,6,2)))-40)  },                           # temp
          hum        => sub {my $msg = shift; return hex(substr($msg,4,2));  },                                  # hum
          channel    => sub {my (undef,$bitData) = @_; return ( SD_WS_binaryToNumber($bitData,12,15)&0x03 );  }, # channel
        },
     71 =>
     # 5C2A909F792F
     # 589A829FDFF4
     # PiiTTTK?CCCC
     # P = Preamble (immer 5 ?)
     # i = ID
     # T = Temperatur
     # K = Kanal (B/A/9)
     # ? = immer F ?
     # C = Checksum ?
      {
        sensortype => 'PV-8644',
        model      =>  'SD_WS71_T',
        prematch   => sub {my $msg = shift; return 1 if ($msg =~ /^5[A-F0-9]{6}F[A-F0-9]{2}/); },                     # prematch
        crcok      => sub {return 1; },                     # crc is unknown
        id         => sub {my (undef,$bitData) = @_; return SD_WS_binaryToNumber($bitData,4,11); },                   # id
        temp       => sub {my (undef,$bitData) = @_; return ((SD_WS_binaryToNumber($bitData,12,23) - 2448) / 10); },  # temp
        channel    => sub {my (undef,$bitData) = @_; return SD_WS_binaryToNumber($bitData,26,27); },                  # channel
      },
    27 =>
      {
        # Protokollbeschreibung: Temperatur-/Feuchtigkeitssensor EuroChron EFTH-800, EFS-3110A
        # ------------------------------------------------------------------------------------
        # 0    4    | 8    12   | 16   20   | 24   28   | 32   36   | 40   44
        # 0000 1001 | 0001 0110 | 0001 0000 | 0000 0000 | 0100 1001 | 0100 0000
        # ?ccc iiii | iiii iiii | bstt tttt | tttt ???? | hhhh hhhh | xxxx xxxx
        # c:  3 bit channel valid channels are 0-7 (stands for channel 1-8)
        # i: 12 bit random id (changes on power-loss)
        # b:  1 bit battery indicator (0=>OK, 1=>LOW)
        # s:  1 bit sign temperature (0=>negative, 1=>positive)
        # t: 10 bit unsigned temperature, scaled by 10
        # h:  8 bit relative humidity percentage (BCD)
        # x:  8 bit CRC8
        # ?: unknown (Bit 0, 28-31, always 0000 by EFTH-800, 1000 by EFS-3110A)
        # The sensor sends two messages at intervals of about 57-58 seconds

        sensortype => 'EFTH-800, EFS-3110A',
        model      => 'SD_WS_27_TH',
        # prematch   => sub {my $rawData = shift; return 1 if ($rawData =~ /^[0-9A-F]{7}0[0-9]{2}[0-9A-F]{2}$/); }, # prematch 113C49A 0 47 AE (EFTH-800)
        prematch   => sub {my $rawData = shift; return 1 if ($rawData =~ /^[0-9A-F]{7}0|8[0-9]{2}[0-9A-F]{2}$/); }, # prematch 3F94519 8 55 C7 (EFS-3110A)
        channel    => sub {my (undef,$bitData) = @_; return (SD_WS_binaryToNumber($bitData,1,3) + 1 ); },
        id         => sub {my (undef,$bitData) = @_; return substr($rawData,1,3); },
        bat        => sub {my (undef,$bitData) = @_; return substr($bitData,16,1) eq "0" ? "ok" : "low";},
        temp       => sub {my (undef,$bitData) = @_; return substr($bitData,17,1) eq "0" ? ((SD_WS_binaryToNumber($bitData,18,27) - 1024) / 10.0) : (SD_WS_binaryToNumber($bitData,18,27) / 10.0);},
        hum        => sub {my (undef,$bitData) = @_; return (SD_WS_binaryToNumber($bitData,32,35) * 10) + (SD_WS_binaryToNumber($bitData,36,39));},
        crcok      => sub {my $rawData = shift;
                            my $rc = eval
                            {
                              require Digest::CRC;
                              Digest::CRC->import();
                              1;
                            };
                            if ($rc) {
                              my $datacheck1 = pack( 'H*', substr($rawData,0,10) );
                              my $crcmein1 = Digest::CRC->new(width => 8, poly => 0x31);
                              my $rr3 = $crcmein1->add($datacheck1)->hexdigest;
                              Log3 $name, 4, "$name: SD_WS_27 Parse msg $rawData, CRC $rr3";
                              if (hex($rr3) == hex(substr($rawData,-2))) {
                                return 1;
                              } else {
                                return 0;
                              }
                            } else {
                              Log3 $name, 1, "$name: SD_WS_27 Parse msg $rawData - ERROR CRC not load, please install modul Digest::CRC";
                              return 0;
                            }  
                          }
      } ,
     33 =>
       {
      # Protokollbeschreibung
      # ------------------------------------------------------------------------
      # 0    4    | 8    12   | 16   20   | 24   28   | 32   36   40
      # 1111 1100 | 0001 0110 | 0001 0000 | 0011 0111 | 0100 1001 01
      # iiii iiii | iiuu cctt | tttt tttt | tthh hhhh | hhbu uuxx xx
      # i: 10 bit random id (changes on power-loss) - Bit 0 + 1 every 0 ???
      # b: battery indicator (0=>OK, 1=>LOW)
      # c: Channel (MSB-first, valid channels are 0x00-0x02 -> 1-3)
      # t: Temperature (MSB-first, BCD, 12 bit unsigned fahrenheit offset by 90 and scaled by 10)
      # h: Humidity (MSB-first, BCD, 8 bit relative humidity percentage)
      # u: unknown
      # x: check

      # Protokollbeschreibung: Conrad Temperatursensor S522 fuer Funk-Thermometer S521B
      # ------------------------------------------------------------------------
      # 0    4    | 8    12   | 16   20   | 24   28   | 32   36   | 40
      # 0010 0111 | 0100 0100 | 1100 0100 | 1100 0000 | 0000 1011 | 10
      # iiii iiii | iiuu cctt | tttt tttt | ttuu uuuu | uuuu TTxx | xx
      # T: Temperature trend, 00 = consistent, 01 = rising, 10 = falling
      # u: unknown (always 0)
      # i: | c: | t: | x: same like default

      # Protokollbeschreibung: renkforce Temperatursensor E0001PA fuer Funk-Wetterstation E0303H2TPR (Conrad)
      # ------------------------------------------------------------------------
      # 0    4    | 8    12   | 16   20   | 24   28   | 32   36   40
      # iiii iiii | iiuu cctt | tttt tttt | tthh hhhh | hhsb uuxx xx
      # s: sendmode (1=>Test push, send manual 0=>automatic send)
      # i: | c: | t: | h: | b: | u: | x: same like default

      # Protokollbeschreibung: Temperatur-/Fechtesensor TX-EZ6 fuer Wetterstation TZS First Austria
      # ------------------------------------------------------------------------
      # 0    4    | 8    12   | 16   20   | 24   28   | 32   36   40
      # iiii iiii | iiHH cctt | tttt tttt | tthh hhhh | hhsb TTxx xx
      # H: Humidity trend, 00 = equal, 01 = up, 10 = down
      # T: Temperature trend, 00 = equal, 01 = up, 10 = down
      # i: | c: | t: | h: | s: | b: | x: same like E0001PA

      sensortype => 'E0001PA, s014, S522, TCM, TFA 30.3200, TX-EZ6',
      model      =>  'SD_WS_33_T',
      prematch   => sub {my $msg = shift; return 1 if ($msg =~ /^[0-9A-F]{11}$/); },              # prematch
      crcok => sub  { my (undef,$bitData) = @_;
                      my $crc = 0;
                      for (my $i=0; $i < 34; $i++) {
                        if (substr($bitData, $i, 1) == ($crc & 1)) {
                          $crc >>= 1;
                        } else {
                          $crc = ($crc>>1) ^ 12;
                        }
                      }
                      $crc ^= SD_WS_bin2dec(scalar(reverse(substr($bitData, 34, 4))));
                      if ($crc == SD_WS_bin2dec(scalar(reverse(substr($bitData, 38, 4))))) {
                        return 1;
                      } else {
                        Log3 $name, 3, "$name: SD_WS_33 Parse msg $msg - ERROR check $crc != " . SD_WS_bin2dec(scalar(reverse(substr($bitData, 38, 4))));
                        return 0;
                      }
                    },
      id      => sub {my (undef,$bitData) = @_; return SD_WS_binaryToNumber($bitData,0,9); },           # id
      temp    => sub {my (undef,$bitData) = @_; return round(((SD_WS_binaryToNumber($bitData,22,25)*256 +  SD_WS_binaryToNumber($bitData,18,21)*16 + SD_WS_binaryToNumber($bitData,14,17)) - 1220) * 5 / 90.0 , 1); }, #temp
      hum     => sub {my (undef,$bitData) = @_; return (SD_WS_binaryToNumber($bitData,30,33)*16 + SD_WS_binaryToNumber($bitData,26,29));  },           #hum
      channel => sub {my (undef,$bitData) = @_; return (SD_WS_binaryToNumber($bitData,12,13)+1 );  },   # channel
      bat     => sub {my (undef,$bitData) = @_; return substr($bitData,34,1) eq "0" ? "ok" : "low";},   # other or modul orginal
       } ,
    38 =>
      {
        # Protokollbeschreibung: NC-3911, NC-3912 - Rosenstein & Soehne Digitales Kuehl- und Gefrierschrank-Thermometer
        # -------------------------------------------------------------------------------------------------------------
        # 0    4    | 8    12   | 16   20   | 24   28   | 32
        # 0000 1001 | 1001 0110 | 0001 0000 | 0000 0111 | 0100
        # iiii iiii | bpcc tttt | tttt tttt | ssss ssss | ????
        # i:  8 bit random id (changes on power-loss)
        # b:  1 bit battery indicator (1=>OK, 0=>LOW)
        # p:  1 bit beep alarm indicator (1=>ON, 0=>OFF)
        # c:  2 bit channel, valid channels are 1 and 2
        # t: 12 bit unsigned temperature, offset 500, scaled by 10
        # s:  8 bit checksum
        # ?:  4 bit equal

        sensortype => 'NC-3911',
        model      => 'SD_WS_38_T',
        prematch   => sub {my $msg = shift; return 1 if ($msg =~ /^[0-9A-F]{9}$/); },
        id         => sub {my (undef,$bitData) = @_; return substr($rawData,0,2); },
        bat        => sub {my (undef,$bitData) = @_; return substr($bitData,8,1) eq "1" ? "ok" : "low";},
        beep       => sub {my (undef,$bitData) = @_; return substr($bitData,9,1) eq "1" ? "on" : "off"; },
        channel    => sub {my (undef,$bitData) = @_; return SD_WS_binaryToNumber($bitData,10,11); },
        temp       => sub {my (undef,$bitData) = @_; return ((SD_WS_binaryToNumber($bitData,12,23) - 500) / 10.0); },
        crcok      => sub {my $msg = shift;
                           my @n = split //, $msg;
                           my $sum1 = hex($n[0]) + hex($n[2]) + hex($n[4]) + 6;
                           my $sum2 = hex($n[1]) + hex($n[3]) + hex($n[5]) + 6 + ($sum1 >> 4);
                           if (($sum1 & 0x0F) == hex($n[6]) && ($sum2 & 0x0F) == hex($n[7])) {
                            return 1;
                           } else {
                            Log3 $name, 3, "$name: SD_WS_38 Parse msg $msg - ERROR checksum " . ($sum1 & 0x0F) . "=" . hex($n[6]) . " " . ($sum2 & 0x0F) . "=" . hex($n[7]);
                            return 0;
                           }
                          },
      } ,
    51 =>
      {
        # Auriol Message Format (rflink/Plugin_044.c):
        # 0    4    8    12   16   20   24   28   32   36
        # 1011 1111 1001 1010 0110 0001 1011 0100 1001 0001
        # B    F    9    A    6    1    B    4    9    1
        # iiii iiii ???? sbTT tttt tttt tttt hhhh hhhh ??cc
        # i = ID
        # ? = unknown (0-15 check?)
        # s = sendmode (1=manual, 0=auto)
        # b = possibly battery indicator (1=low, 0=ok)
        # T = temperature trend (2 bits) indicating temp equal/up/down
        # t = Temperature => 0x61b  (0x61b-0x4c4)=0x157 *5)=0x6b3 /9)=0xBE => 0xBE = 190 decimal!
        # h = humidity (4x10+9=49%)
        # ? = unknown (always 00?)
        # c = channel: 1 (2 bits)

        sensortype => 'Auriol IAN 275901, IAN 114324, IAN 60107',
        model      => 'SD_WS_51_TH',
        prematch   => sub {my $msg = shift; return 1 if ($msg =~ /^[0-9A-F]{9}[1-3]$/);}, # 10 nibbles, 9 hex chars, only channel 1-3
        # prematch   => sub {my $msg = shift; return 1 if ($msg =~ /^[0-9A-F]{10}$/);}, # 10 nibbles, all hex chars
        crcok      => sub {return 1;  },  # crc is unknown
        id         => sub {my (undef,$bitData) = @_; return substr($rawData,0,2);}, # long-id in hex
        sendmode   => sub {my (undef,$bitData) = @_; return substr($bitData,12,1) eq "1" ? "manual" : "auto";},
        bat        => sub {my (undef,$bitData) = @_; return substr($bitData,13,1) eq "1" ? "low" : "ok";},
        trend      => sub {my (undef,$bitData) = @_; return ('consistent', 'rising', 'falling', 'unknown')[SD_WS_binaryToNumber($bitData,14,15)];},
        temp       => sub {my (undef,$bitData) = @_; return round(((SD_WS_binaryToNumber($bitData,16,27)) - 1220) * 5 / 90.0 , 1); },
        hum        => sub {my (undef,$bitData) = @_; return (SD_WS_binaryToNumber($bitData,28,31) * 10) + (SD_WS_binaryToNumber($bitData,32,35));},
        channel    => sub {my (undef,$bitData) = @_; return (SD_WS_binaryToNumber($bitData,38,39) );},
      },
    53 =>
      {
        # AURIOL AHFL 433 B2 IAN 314695 Message Format
        # ----------------------------------------------------
        # 0    4    8    12   16   20   24   28   32   36   40
        # 0000 0111 0000 0000 1101 1111 0111 1010 0100 1110 00
        # iiii iiii b?cc tttt tttt tttt hhhh hhh? ???? ssss ss
        # i:  8 bit random id (changes on power-loss)
        # b:  1 bit battery indicator (0=>OK, 1=>LOW)
        # c:  2 bit channel, valid channels are 1-3
        # t: 12 bit signed temperature, scaled by 10
        # h:  7 bit humidity
        # s:  6 bit checksum (sum over nibble 0 - 8)
        # ?:  x bit unknown (bit 32-35 always 0100)

        sensortype => 'Auriol IAN 314695',
        model      => 'SD_WS_53_TH',
        # prematch => sub {my $msg = shift; return 1 if ($msg =~ /^[0-9A-F]{11}$/); },              # prematch
        prematch   => sub {my $msg = shift; return 1 if ($msg =~ /^[0-9A-F]{8}4[0-9A-F]{2}$/); }, # prematch 0700F276 4 A4
        crcok      => sub { my (undef,$bitData) = @_;
                            my $sum = 0;
                            for (my $n = 0; $n < 36; $n += 4) {
                              $sum += SD_WS_binaryToNumber($bitData, $n, $n + 3)
                            }
                            if (($sum &= 0x3F) == SD_WS_binaryToNumber($bitData, 36, 41)) {
                              return 1;
                            } else {
                              Log3 $name, 3, "$name: SD_WS_53 Parse msg $msg - ERROR checksum $sum != " . SD_WS_binaryToNumber($bitData, 36, 41);
                              return 0;
                            }
                          },
        id         => sub {my (undef,$bitData) = @_; return substr($rawData,0,2);}, # long-id in hex
        bat        => sub {my (undef,$bitData) = @_; return substr($bitData,8,1) eq "1" ? "low" : "ok";},
        channel    => sub {my (undef,$bitData) = @_; return (SD_WS_binaryToNumber($bitData,10,11) + 1);},
        temp       => sub {my (undef,$bitData) = @_; return substr($bitData,12,1) eq "1" ? ((SD_WS_binaryToNumber($bitData,12,23) - 4096) / 10.0) : (SD_WS_binaryToNumber($bitData,12,23) / 10.0);},
        hum        => sub {my (undef,$bitData) = @_; return (SD_WS_binaryToNumber($bitData,24,30) );},
      },
    54 => {
        # TFA Drop Rainmeter 30.3233.01
        # ----------------------------------------------------------------------------------
        # 0        8        16       24       32       40       48       56       64   - 01234567890123456
        # 00111101 10011100 01000011 00001010 00011011 10101010 00000001 10001001 1000 - 3D9C430A1BAA01898
        # 00111101 10011100 01000011 00000110 00011000 10101010 00000001 00110100 0000 - 3D9C430618AA01340
        # PPPPIIII IIIIIIII IIIIIIII BCUUXXXU RRRRRRRR FFFFFFFF SSSSSSSS MMMMMMMM KKKK
        # P:  4 bit message prefix, always 0x3
        # I: 20 bit Sensor ID
        # B:  1 bit Battery indicator, 0 if battery OK, 1 if battery is low.
        # C:  1 bit Device reset, set to 1 briefly after battery insert.
        # X:  3 bit Transmission counter, rolls over.
        # R:  8 bit LSB of 16-bit little endian rain counter
        # F:  8 bit Fixed to 0xaa
        # S:  8 bit MSB of 16-bit little endian rain counter
        # M:  8 bit Checksum, compute with reverse Galois LFSR with byte reflection, generator 0x31 and key 0xf4.
        # K:  4 bit Unknown, either b1011 or b0111. - Distribution: 50:50 ???
        # U:        Unknown
        # The rain counter starts at 65526 to indicate 0 tips of the bucket. The counter rolls over at 65535 to 0, which corresponds to 9 and 10 tips of the bucket.
        # Each tip of the bucket corresponds to 0.254mm of rain.
        # After battery insertion, the sensor will transmit 7 messages in rapid succession, one message every 3 seconds. After the first message,
        # the remaining 6 messages have bit 1 of byte 3 set to 1. This could be some sort of reset indicator.
        # For these 6 messages, the transmission counter does not increase. After the full 7 messages, one regular message is sent after 30s.
        # Afterwards, messages are sent every 45s.

        sensortype     => 'TFA 30.3233.01',
        model          => 'SD_WS_54_R',
        prematch       => sub {my $rawData = shift; return 1 if ($rawData =~ /^3[0-9A-F]{9}AA[0-9A-F]{4,5}$/); }, # prematch 3 E2E390CF9 AA FF8A0
        id             => sub {my ($rawData,undef) = @_; return substr($rawData,1,5); },
        bat            => sub {my (undef,$bitData) = @_; return substr($bitData,24,1) eq "0" ? "ok" : "low";},
        batChange      => sub {my (undef,$bitData) = @_; return substr($bitData,25,1);},
        sendCounter    => sub {my (undef,$bitData) = @_; return (SD_WS_binaryToNumber($bitData,28,30));},
        rawRainCounter => sub {my (undef,$bitData) = @_; 
                                my $rawRainCounterMessage = SD_WS_binaryToNumber($bitData,32,39) + SD_WS_binaryToNumber($bitData,48,55) * 256;
                                if ($rawRainCounterMessage > 65525) {
                                  return $rawRainCounterMessage - 65526;
                                } else {
                                  return $rawRainCounterMessage + 10;
                                }
                              },
        rain_total     => sub {my (undef,$bitData) = @_; 
                                my $rawRainCounterMessage = SD_WS_binaryToNumber($bitData,32,39) + SD_WS_binaryToNumber($bitData,48,55) * 256;
                                if ($rawRainCounterMessage > 65525) {
                                  return ($rawRainCounterMessage - 65526) * 0.254;
                                } else {
                                  return ($rawRainCounterMessage + 10) * 0.254;
                                }
                              },
        crcok          => sub {my $rawData = shift;
                                my $checksum = SD_WS_LFSR_digest8_reflect(7, 0x31, 0xf4, $rawData );
                                if ($checksum == hex(substr($rawData,14,2))) {
                                  return 1;
                                } else {
                                  Log3 $name, 3, "$name: SD_WS_54 Parse msg $msg - ERROR checksum $checksum != " . hex(substr($rawData,14,2));
                                  return 0;
                                }
                              },
      },
    58 => {
        # TFA 30.3208.02, TFA 30.3228.02, TFA 30.3229.02, Froggit FT007xx, Ambient Weather F007-xx, Renkforce FT007xx
        # -----------------------------------------------------------------------------------------------------------
        # 0    4    8    12   16   20   24   28   32   36   40   44   48
        # 0100 0101 1100 0110 1001 0011 1100 1010 0011 0100 1100 0111 0000
        # yyyy yyyy iiii iiii bccc tttt tttt tttt hhhh hhhh ssss ssss ????
        # y   8 bit sensor type (45=>TH, 46=>T)
        # i:  8 bit random id (changes on power-loss)
        # b:  1 bit battery indicator (0=>OK, 1=>LOW)
        # c:  3 bit channel (valid channels are 1-8)
        # t: 12 bit temperature (Farenheit: subtract 400 and divide by 10, Celsius: subtract 720 and multiply by 0.0556)
        # h:  8 bit humidity (only type 45, type 46 changes between 10 and 15)
        # s:  8 bit check
        # ?:  4 bit unknown
        # frames sent every ~1 min (varies by channel), map of channel id to transmission interval: 1: 53s, 2: 57s, 3: 59s, 4: 61s, 5: 67s, 6: 71s, 7: 73s, 8: 79s

        sensortype => 'TFA 30.3208.02, FT007xx',
        model      => 'SD_WS_58_T', 
        # prematch => sub {my $msg = shift; return 1 if ($msg =~ /^45[0-9A-F]{11}/); }, # prematch
        prematch   => sub {my $msg = shift; return 1 if ($msg =~ /^4[5|6][0-9A-F]{11}/); }, # prematch, 45=FT007TH/TFA 30.3208.02, 46=FT007T/TFA 30.3228.02
        crcok      => sub { my $msg = shift;
                            # my @buff = split(//,substr($msg,index($msg,"45"),10));
                            # my $idx = index($msg,"45");
                            my @buff = split(//,substr($msg,0,10));
                            my $crc_check = substr($msg,10,2);
                            my $mask = 0x7C;
                            my $checksum = 0x64;
                            my $data;
                            my $nibbleCount;
                            for ( $nibbleCount=0; $nibbleCount < scalar @buff; $nibbleCount+=2) {
                              my $bitCnt;
                              if ($nibbleCount+1 <scalar @buff) {
                                $data = hex($buff[$nibbleCount].$buff[$nibbleCount+1]);
                              } else  {
                                $data = hex($buff[$nibbleCount]); 
                              }
                                for ( my $bitCnt= 7; $bitCnt >= 0 ; $bitCnt-- ) {
                                  my $bit;
                                  # Rotate mask right
                                  $bit = $mask & 1;
                                  $mask = ($mask >> 1 ) | ($mask << 7) & 0xFF;
                                  if ( $bit ) {
                                    $mask ^= 0x18 & 0xFF;
                                  }
                                  # XOR mask into checksum if data bit is 1
                                  if ( $data & 0x80 ) {
                                    $checksum ^= $mask & 0xFF;
                                  }
                                  $data <<= 1 & 0xFF;
                                }
                            }
                            if ($checksum == hex($crc_check)) {
                              return 1;
                            } else {
                              Log3 $name, 3, "$name: SD_WS_58 Parse msg $msg - ERROR checksum $checksum != " . hex($crc_check);
                              return 0;
                            }
                          },
        id         => sub {my (undef,$bitData) = @_; return SD_WS_binaryToNumber($bitData,8,15); },                         # random id
        bat        => sub {my (undef,$bitData) = @_; return SD_WS_binaryToNumber($bitData,16) eq "1" ? "low" : "ok";},      # bat?
        channel    => sub {my (undef,$bitData) = @_; return (SD_WS_binaryToNumber($bitData,17,19) + 1 ); },                 # channel
        temp       => sub {my (undef,$bitData) = @_; return round((SD_WS_binaryToNumber($bitData,20,31)-720)*0.0556,1); },  # temp
        hum        => sub {my ($rawData,$bitData) = @_; return substr($rawData,1,1) eq "5" ? (SD_WS_binaryToNumber($bitData,32,39)) : 0;},  # hum
      } ,
    84 =>
      {
        # Protokollbeschreibung: Funk Wetterstation Auriol IAN 283582 (Lidl)
        # ------------------------------------------------------------------------
        # 0    4    | 8    12   | 16   20   | 24   28   | 32   36  
        # 1111 1100 | 0001 0110 | 0001 0000 | 0011 0111 | 0100 1001
        # iiii iiii | hhhh hhhh | bscc tttt | tttt tttt | ???? ????
        # i: 8 bit id (?) - no change after battery change, i have seen two IDs: 0x03 and 0xfe
        # h: 8 bit relative humidity percentage
        # b: 1 bit battery indicator (0=>OK, 1=>LOW)
        # s: 1 bit sendmode 1=manual (button pressed) 0=auto
        # c: 2 bit channel valid channels are 0-2 (1-3)
        # t: 12 bit signed temperature scaled by 10
        # ?: unknown
        # Sensor sends approximately every 30 seconds

        sensortype => 'Auriol IAN 283582, TV-4848',
        model      => 'SD_WS_84_TH',
        prematch   => sub {my $msg = shift; return 1 if ($msg =~ /^[0-9A-F]{4}[01245689ACDE]{1}[0-9A-F]{5,6}$/); },   # valid channel only 0-2
        id         => sub {my (undef,$bitData) = @_; return SD_WS_binaryToNumber($bitData,0,7); },
        hum        => sub {my (undef,$bitData) = @_; return SD_WS_binaryToNumber($bitData,8,15); },
        bat        => sub {my (undef,$bitData) = @_; return substr($bitData,16,1) eq "0" ? "ok" : "low";},
        sendmode   => sub {my (undef,$bitData) = @_; return substr($bitData,17,1) eq "1" ? "manual" : "auto"; },
        channel    => sub {my (undef,$bitData) = @_; return (SD_WS_binaryToNumber($bitData,18,19)+1 ); },
        temp       => sub { my (undef,$bitData) = @_;
                            my $tempraw = SD_WS_binaryToNumber($bitData,20,31);
                            $tempraw -= 4096 if ($tempraw > 1023);    # negative
                            $tempraw /= 10.0;
                            return $tempraw;
                          },
        crcok      => sub {return 1;},    # crc test method is so far unknown
      } ,
    85 =>
      {
        # Protokollbeschreibung: Kombisensor TFA 30.3222.02 fuer Wetterstation TFA 35.1140.01, Windmesser TFA 30.3251.10
        # --------------------------------------------------------------------------------------------------------------
        # 0    4    | 8    12   | 16   20   | 24   28   | 32   36   | 40   44   | 48   52   | 56   60   | 64
        # 0000 1001 | 0001 0110 | 0001 0000 | 0000 0111 | 0100 1001 | 0100 0000 | 0100 1001 | 0100 1001 | 1
        # 0000 iiii | iiii iiii | iiii iiii | b??? ??yy | tttt tttt | tttt 0000 | hhhh hhhh | CCCC CCCC | ?   message 1 TFA 30.3222.02
        # 0000 iiii | iiii iiii | iiii iiii | b?cc ??yy | wwww wwww | wwww 0000 | 0000 0000 | CCCC CCCC | ?   message 2 TFA 30.3222.02
        # 0000 iiii | iiii iiii | iiii iiii | b?cc ??yy | wwww wwww | wwww dddd | dddd dddd | CCCC CCCC | ?   message 2 TFA 30.3251.10
        # i: 20 bit random id (changes on power-loss)
        # b:  1 bit battery indicator (0=>OK, 1=>LOW)
        # c:  2 bit channel valid channels are (always 00 stands for channel 1)
        # y:  2 bit typ, 01 - thermo/hygro (message 1), 10 - wind (message 2)
        # t: 12 bit unsigned temperature, offset 500, scaled by 10 - if message 1
        # h:  8 bit relative humidity percentage - if message 1
        # w: 12 bit unsigned windspeed, scaled by 10 - if message 2
        # d: 12 bit unsigned winddirection - only TFA 30.3251.10
        # C:  8 bit CRC of the preceding 7 bytes (Polynomial 0x31, Initial value 0x00, Input not reflected, Result not reflected)
        # ?: unknown
        # The sensor sends at intervals of about 30 seconds
        sensortype => 'TFA 30.3222.02, TFA 30.3251.10, LaCrosse TX141W',
        model      => 'SD_WS_85_THW',
        prematch   => sub {my $msg = shift; return 1 if ($msg =~ /^[0-9A-F]{16}/); },   # min 16 nibbles
        id         => sub {my ($rawData,undef) = @_; return substr($rawData,1,5); },    # 0952CF012B1021DF0
        bat        => sub {my (undef,$bitData) = @_; return substr($bitData,24,1) eq "0" ? "ok" : "low";},
        channel    => sub {my (undef,$bitData) = @_; return (SD_WS_binaryToNumber($bitData,26,27) + 1 ); },   # unknown
        temp       => sub {my (undef,$bitData) = @_;
                            if (substr($bitData,30,2) eq "01") {    # message 1 thermo/hygro
                              return ((SD_WS_binaryToNumber($bitData,32,43) - 500) / 10.0);
                            } else {
                              return;
                            }
                          },
        hum        => sub {my (undef,$bitData) = @_;
                            if (substr($bitData,30,2) eq "01") {    # message 1 thermo/hygro
                              return SD_WS_binaryToNumber($bitData,48,55);
                            } else {
                              return;
                            }
                          },
        windspeed  => sub {my (undef,$bitData) = @_;
                            if (substr($bitData,30,2) eq "10") {    # message 2 windspeed
                              return (SD_WS_binaryToNumber($bitData,32,43) / 10.0);
                            } else {
                              return;
                            }
                          },
        winddir    => sub {my (undef,$bitData) = @_;
                            if (substr($bitData,30,2) eq "10") {    # message 2 winddirection
                              $winddir = SD_WS_binaryToNumber($bitData,44,55);
                              return ($winddir * 1, $winddirtxtar[round(($winddir / 22.5),0)]);
                            } else {
                              return;
                            }
                          },
        crcok      => sub {my ($rawData,undef) = @_;
                            my $rc = eval {
                              require Digest::CRC;
                              Digest::CRC->import();
                              1;
                            };
                            if ($rc) {
                              my $datacheck1 = pack( 'H*', substr($rawData,0,14) );
                              my $crcmein1 = Digest::CRC->new(width => 8, poly => 0x31);
                              my $rr3 = $crcmein1->add($datacheck1)->hexdigest;
                              if (hex($rr3) != hex(substr($rawData,14,2))) {
                                Log3 $name, 3, "$name: SD_WS_85 Parse msg $rawData - ERROR CRC8";
                                return 0;
                              }
                            } else {
                              Log3 $name, 1, "$name: SD_WS_85 Parse msg $rawData - ERROR CRC not load, please install modul Digest::CRC";
                              return 0;
                            }  
                            return 1;
                          }
      } ,
    89 =>
      {
        # Protokollbeschreibung: Temperatur-/Feuchtesensor TFA 30.3221.02 fuer Wetterstation TFA 35.1140.01
        # -------------------------------------------------------------------------------------------------
        # 0    4    | 8    12   | 16   20   | 24   28   | 32   36  
        # 0000 1001 | 0001 0110 | 0001 0000 | 0000 0111 | 0100 1001
        # iiii iiii | bscc tttt | tttt tttt | hhhh hhhh | ???? ????
        # i:  8 bit random id (changes on power-loss)
        # b:  1 bit battery indicator (0=>OK, 1=>LOW)
        # s:  1 bit sendmode (0=>auto, 1=>manual)
        # c:  2 bit channel valid channels are 0-2 (1-3)
        # t: 12 bit unsigned temperature, offset 500, scaled by 10
        # h:  8 bit relative humidity percentage
        # ?:  8 bit unknown
        # The sensor sends 3 repetitions at intervals of about 60 seconds

        sensortype => 'TFA 30.3221.02',
        model      => 'SD_WS_89_TH',
        prematch   => sub {my $msg = shift; return 1 if ($msg =~ /^[0-9A-F]{2}[01245689ACDE]{1}[0-9A-F]{7}$/); },   # valid channel only 0-2
        id         => sub {my (undef,$bitData) = @_; return substr($rawData,0,2); },
        bat        => sub {my (undef,$bitData) = @_; return substr($bitData,8,1) eq "0" ? "ok" : "low";},
        sendmode   => sub {my (undef,$bitData) = @_; return substr($bitData,9,1) eq "1" ? "manual" : "auto"; },
        channel    => sub {my (undef,$bitData) = @_; return (SD_WS_binaryToNumber($bitData,10,11) + 1); },
        temp       => sub {my (undef,$bitData) = @_; return ((SD_WS_binaryToNumber($bitData,12,23) - 500) / 10.0); },
        hum        => sub {my (undef,$bitData) = @_; return SD_WS_binaryToNumber($bitData,24,31); },
        crcok      => sub {return 1;},    # crc test method is so far unknown
      } ,
    94 => {
        # Sensor sends Bit 0 as "0", Bit 1 as "110"
        # Protocol after conversion bits (Length varies from minimum 24 to maximum 32 bits.)
        # ------------------------------------------------------------------------
        # 0    4    | 8    12   | 16   20   | 24   28
        # 1111 1100 | 0000 0110 | 0001 0000 | 0011 0111
        # iiii iiii | ??s? tttt | tttt tttt | ???? ????
        # i:  8 bit id
        # s:  1 bit sign (0 = temperature positive, 1 = temperature negative
        # t: 12 bit temperature (MSB-first, BCD, 12 bit unsigned celsius scaled by 10)
        # ?: unknown

        sensortype => 'Atech',
        model      => 'SD_WS_94_T',
        prematch   => sub { return 1; },    #  no precheck known
        id         => sub { # change 110 to 1 in ref bitdata and return id
                  ($_[1] = $_[1]) =~ s/110/1/g; 
                  return sprintf('%02X', SD_WS_bin2dec(substr($_[1],0,8))); 
                  },  
        temp       => sub {
          my $rawtemp100  = SD_WS_binaryToNumber($_[1],12,15);
          my $rawtemp10   = SD_WS_binaryToNumber($_[1],16,19);
          my $rawtemp1  = SD_WS_binaryToNumber($_[1],20,23);
          if ($rawtemp100 > 9 || $rawtemp10 > 9 || $rawtemp1 > 9) {
            Log3 $iohash, 3, "$name: SD_WS_Parse $model ERROR - BCD of temperature ($rawtemp100 $rawtemp10 $rawtemp1)";
            return;
          };
          my $temp = ($rawtemp100 * 10 + $rawtemp10 + $rawtemp1 / 10) * ( substr($_[1],10,1) == 1 ? -1.0 : 1.0);
        },
        crcok      => sub {return 1;},    # crc test method is so far unknown
    },
    106 => {
        # BBQ temperature sensor MODELL: GT-TMBBQ-01s (Sender), GT-TMBBQ-01e (Empfaenger)
        # -------------------------------------------------------------------------------
        # 0    4    | 8    12   | 16   20
        # 1101 1111 | 0011 0100 | 0100 00
        # iiii iiii | tttt tttt | tttt tt
        # i:  8 bit id, changes each time the sensor is switched on
        # t: 14 bit unsigned fahrenheit offset by 90 and scaled by 20

        sensortype => 'GT-TMBBQ-01',
        model      => 'SD_WS_106_T',
        prematch   => sub { return 1; }, # no precheck known
        id         => sub { my ($rawData,undef) = @_; return substr($rawData,0,2); },
        temp       => sub { my (undef,$bitData) = @_;
                            $rawTemp =  SD_WS_binaryToNumber($bitData,8,21);
                            my $tempFh = $rawTemp / 20 - 90; # Grad Fahrenheit
                            Log3 $name, 4, "$name: SD_WS_106_T tempraw = $rawTemp, temp = $tempFh Fahrenheit";
                            return (round((($tempFh - 32) * 5 / 9) , 1)); # Grad Celsius
                          },
        crcok      => sub {return 1;}, # CRC test method does not exist
    } ,
    107 => {
        # Fine Offset WH51, ECOWITT WH51, MISOL/1, Froggit DP100 Soil Moisture Sensor
        # ---------------------------------------------------------------------------
        #          Byte: 00 01 02 03 04 05 06 07 08 09 10 11 12 13
        #        Nibble: 01 23 45 67 89 01 23 45 67 89 01 23 45 67
        # aa aa aa 2d d4 51 00 6b 58 6e 7f 24 f8 d2 ff ff ff 3c 28
        #           MN;D=51 00 C6 BF 10 7F 23 F8 C7 FF FF FF 5D A1 ;R=14; H: 35
        #                FF II II II TB YY MM ZA AA XX XX XX CC SS
        # FF:       Family code 0x51 (ECOWITT/FineOffset WH51)
        # IIIIII:   ID (3 bytes)
        # T:        Transmission period boost: highest 3 bits set to 111 on moisture change and decremented each transmission, if T = 0 period is 70 sec, if T > 0 period is 10 sec
        # B:        Battery voltage: lowest 5 bits are battery voltage * 10 (e.g. 0x0c = 12 = 1.2V). Transmitter works down to 0.7V (0x07)
        # YY:       ? Fixed: 0x7f
        # MM:       Moisture percentage 0%-100% (0x00-0x64) MM = (AD - 70) / (450 - 70)
        # Z:        ? Fixed: leftmost 7 bit 1111 100
        # AAA:      9 bit AD value MSB byte[07] & 0x01, LSB byte[08] ??? 10 bit ??? WH51 Manual.pdf says: 100%AD setting range:0%AD+10~1000
        # XXXXXX:   ? Fixed: 0xff 0xff 0xff
        # CC:       CRC of the preceding 12 bytes (Polynomial 0x31, Initial value 0x00, Input not reflected, Result not reflected)
        # SS:       Sum of the preceding 13 bytes % 256
        sensortype => 'WH51, DP100, MISOL/1',
        model      => 'SD_WS_107_H',
        prematch   => sub { ($rawData,undef) = @_; return 1 if ($rawData =~ /^51[0-9A-F]{16}[F]{6}/); },
        id         => sub { my ($rawData,undef) = @_; return substr($rawData,2,6); },
        batVoltage => sub { my (undef,$bitData) = @_; return round(SD_WS_binaryToNumber($bitData,35,39) / 10 , 1); },
        adc        => sub { my (undef,$bitData) = @_; return SD_WS_binaryToNumber($bitData,62,71); },
        hum        => sub { my ($rawData,undef) = @_; return hex(substr($rawData,12,2)); },
        crcok      => sub { my $rawData = shift;
                            my $rc = eval {
                              require Digest::CRC;
                              Digest::CRC->import();
                              1;
                            };
                            if ($rc) {
                              my $datacheck1 = pack( 'H*', substr($rawData,0,24) );
                              my $crcmein1 = Digest::CRC->new(width => 8, poly => 0x31);
                              my $rr3 = $crcmein1->add($datacheck1)->hexdigest;
                              if (hex($rr3) != hex(substr($rawData,24,2))) {
                                Log3 $name, 3, "$name: SD_WS_107 Parse msg $rawData - ERROR CRC8";
                                return 0;
                              }
                            } else {
                              Log3 $name, 1, "$name: SD_WS_107 Parse msg $rawData - ERROR CRC not load, please install modul Digest::CRC";
                              return 0;
                            }  
                            my $checksum = 0;
                            for (my $i=0; $i < 26; $i += 2) {
                              $checksum += hex(substr($rawData,$i,2));
                            }
                            $checksum &= 255;
                            if ($checksum != hex(substr($rawData,26,2))) {
                              Log3 $name, 3, "$name: SD_WS_107 Parse msg $rawData - ERROR checksum";
                              return 0;
                            }
                            return 1;
                          }
    } ,
    108 => {
        # https://github.com/merbanan/rtl_433/blob/master/src/devices/bresser_5in1.c
        # The compact 5-in-1 multifunction outdoor sensor transmits the data on 868.3 MHz.
        # The device uses FSK-PCM encoding, the device sends a transmission every 12 seconds.
        # A transmission starts with a preamble of 0xAA.
        # Preamble: aa aa aa aa aa 2d d4
        # Packet payload without preamble (203 bits):
        #  0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25
        # -----------------------------------------------------------------------------
        # ed ee 46 ff ff ff ef 9f ff 8b 7d eb ff 12 11 b9 00 00 00 10 60 00 74 82 14 00 00 00 (Rain Gauge)
        # e9 ee 46 ff ff ff ef 99 ff 8b 8b eb ff 16 11 b9 00 00 00 10 66 00 74 74 14 00 00 00 (Rain Gauge)
        # e3 fd 7f 89 7e 8a ed 68 fe af 9b fd ff 1c 02 80 76 81 75 12 97 01 50 64 02 00 00 00 (Large Wind Values, Gust=37.4m/s Avg=27.5m/s from https://github.com/merbanan/rtl_433/issues/1315)
        # ef a1 ff ff 1f ff ef dc ff de df ff 7f 10 5e 00 00 e0 00 10 23 00 21 20 00 80 00 00 (low batt +ve temp)
        # ed a1 ff ff 1f ff ef 8f ff d6 df ff 77 12 5e 00 00 e0 00 10 70 00 29 20 00 88 00 00 (low batt -ve temp -7.0C)
        # ec 91 ff ff 1f fb ef e7 fe ad ed ff f7 13 6e 00 00 e0 04 10 18 01 52 12 00 08 00 00 (good batt -ve temp)
        # CC CC CC CC CC CC CC CC CC CC CC CC CC uu II SS GG DG WW  W TT  T HH RR  R Bt
        #                                           G-MSB ^     ^ W-MSB  (strange but consistent order)
        #
        #           1         2         3         4         5     
        # 0123456789012345678901234567890123456789012345678901
        # --------------------------------------------------------
        # EC837FF7FFFBEFDEFF7A89FFFF137C8008000410210085760000   52 Nibble from SIGNALduino
        # CCCCCCCCCCCCCCCCCCCCCCCCCCuuIISSGGDGWW WTT THHRR RBt   52 Nibble
        # C = check, inverted data of 13 byte further
        # u = checksum (number/count of set bits within bytes 14-25)
        # I = station ID
        # S = sensor type, device reset, channel - ???
        #     Bit:    0    4   
        #             1000 0000
        #             r?ss cccc
        #             r:  1 bit device reset, 0 after inserting battery or pressing reset, 1 after 1 hour (checked with Fody E42)
        #             s:  2 bit sensor type, 00 = Bresser_5in1, 01 = Fody_E42, 11 = Bresser_rain_gauge
        #             c:  4 bit channel, 0000 = Bresser_5in1, 0001/0010/0011 = Fody_E42 (changes after reset), 1001 = Bresser_rain_gauge
        # G = wind gust in 1/10 m/s, normal binary coded, GGxG = 0x76D1 => 0x0176 = 256 + 118 = 374 => 37.4 m/s.  MSB is out of sequence.
        # D = wind direction 0..F = N..NNE..E..S..W..NNW
        # W = wind speed in 1/10 m/s, BCD coded, WWxW = 0x7512 => 0x0275 = 275 => 27.5 m/s. MSB is out of sequence.
        # T = temperature in 1/10 °C, BCD coded, TTxT = 1203 => 31.2 °C
        # t = temperature sign, minus if unequal 0
        # H = humidity in percent, BCD coded, HH = 23 => 23 %
        # R = rain in mm, BCD coded, RRxR = 1203 => 31.2 mm - elektron-bbs changed: RRRR = 1243 => 431.2 mm
        # B = Battery. 0=Ok, 8=Low.
        #
        # Only nibbles 28 to 52 are transferred to the module. Preprocessing in SD_Protocols.pm sub sub ConvBresser_5in1.
        #           1         2
        # 012345678901234567890123
        # ------------------------
        # 7C8008000410210085760000
        # IISSGGDGWW WTT THHRRRRBt

        sensortype => 'Bresser_5in1, Bresser_rain_gauge, Fody_E42, Fody_E43',
        model      => 'SD_WS_108',
        prematch   => sub {my $rawData = shift; return 1 if ($rawData =~ /^[0-9A-F]{8}[0-9]{2}[0-9A-F]{1}[0-9]{3}[0-9A-F]{1}[0-9]{5}[0-9A-F]{1}[0-9]{1}/); },
        id         => sub {my ($rawData,undef) = @_; return substr($rawData,0,2); },
        winddir    => sub {my ($rawData,$bitData) = @_;
                            return if (substr($bitData,10,2) eq '01' || substr($bitData,10,2) eq '11'); # Bresser rain gauge, Fody E42
                            my $winddirraw = hex(substr($rawData,6,1));
                            return ($winddirraw * 22.5, $winddirtxtar[$winddirraw]);
                          },
        windgust   => sub {my ($rawData,$bitData) = @_;
                            return if (substr($bitData,10,2) eq '01' || substr($bitData,10,2) eq '11'); # Bresser rain rauge, Fody E42
                            return (hex(substr($rawData,7,1)) * 256 + hex(substr($rawData,4,2))) / 10;
                          },
        windspeed  => sub {my ($rawData,$bitData) = @_;
                            return if (substr($bitData,10,2) eq '01' || substr($bitData,10,2) eq '11'); # Bresser rain gauge, Fody E42
                            return (substr($rawData,11,1) . substr($rawData,8,2)) / 10;
                          },
        temp       => sub {my ($rawData,undef) = @_;
                            my $sgn = substr($rawData,23,1) eq "0" ? 1 : -1;
                            $rawTemp =  $sgn * (substr($rawData,15,1) . substr($rawData,12,1) . '.' .substr($rawData,13,1));
                            return $rawTemp;
                          },
        hum        => sub {my ($rawData,$bitData) = @_;
                            return if (substr($bitData,10,2) eq '11'); # Bresser rain gauge
                            return substr($rawData,16,2) + 0;
                          },
        rain       => sub {my ($rawData,$bitData) = @_;
                            return if (substr($bitData,10,2) eq '01'); # Fody E42
                            $rain = (substr($rawData,20,2) . substr($rawData,18,2)) / 10;
                            $rain *= 2.5 if (substr($bitData,10,2) eq '11'); # Bresser rain gauge
                            return $rain;
                          },
        bat        => sub {my ($rawData,undef) = @_; return substr($rawData,22,1) eq '0' ? 'ok' : 'low';},
        batChange  => sub {my (undef,$bitData) = @_; return substr($bitData,8,1);},
        crcok      => sub {return 1;}, # checks are in SD_Protocols.pm sub ConvBresser_5in1
    } ,
    110 => {
        # ADE WS1907 Weather station with rain gauge
        # 0         1         2         3         4         5         6         7         8
        # 0    4    8    12   16   20   24   28   32   36   40   44   48   52   56   60   64
        # 1011 1111 1001 1010 0110 0001 1011 0100 1001 0001 1011 1111 1001 1010 0110 0001 01
        # iiii iiii iiii iiii bd?? ccc? rrrr rrrr rrrr rrrr tttt tttt tttt tttt ssss ssss ??
        # i: 16 bit ID
        # b:  1 bit battery indicator, 0 if battery ok, 1 if battery is low.
        # d:  1 bit device reset, set to 1 briefly after battery insert
        # c:  3 bit transmission counter, rolls over
        # r: 16 bit rain counter (LSB first)
        # t: 16 bit temperature (LSB first, unsigned fahrenheit offset by 90 and scaled by 10)
        # s:  8 bit checksum over byte 0 - 6 & 0xFF
        # ?:    unknown

        sensortype     => 'ADE WS1907',
        model          => 'SD_WS_110_TR',
        prematch       => sub {return 1;}, # no precheck known
        id             => sub {my (undef,$bitData) = @_; return substr($rawData,0,4);}, # long-id in hex
        bat            => sub {my (undef,$bitData) = @_; return substr($bitData,16,1) eq "0" ? "ok" : "low";},
        batChange      => sub {my (undef,$bitData) = @_; return substr($bitData,17,1);},
        sendCounter    => sub {my (undef,$bitData) = @_; return (SD_WS_binaryToNumber($bitData,20,22));},
        rawRainCounter => sub {my (undef,$bitData) = @_; 
                                my $rawRainCounterMessage = SD_WS_binaryToNumber($bitData,32,39) * 256 + SD_WS_binaryToNumber($bitData,24,31);
                                if ($rawRainCounterMessage > 65525) {
                                  return $rawRainCounterMessage - 65526;
                                } else {
                                  return $rawRainCounterMessage + 10;
                                }
                              },
        rain           => sub {my (undef,$bitData) = @_; 
                                my $rawRainCounterMessage = SD_WS_binaryToNumber($bitData,32,39) * 256 + SD_WS_binaryToNumber($bitData,24,31);
                                if ($rawRainCounterMessage > 65525) {
                                  return ($rawRainCounterMessage - 65526) * 0.1;
                                } else {
                                  return ($rawRainCounterMessage + 10) * 0.1;
                                }
                              },
        temp           => sub { my (undef,$bitData) = @_; return round(((SD_WS_binaryToNumber($bitData,48,55) * 256 + SD_WS_binaryToNumber($bitData,40,47)) - 1220) * 5 / 90.0 , 1); },
        crcok          => sub { my (undef,$bitData) = @_;
                                my $sum = 0;
                                for (my $n = 0; $n < 56; $n += 8) {
                                  $sum += SD_WS_binaryToNumber($bitData, $n, $n + 7)
                                }
                                if (($sum &= 0xFF) == SD_WS_binaryToNumber($bitData, 56, 63)) {
                                  return 1;
                                } else {
                                  Log3 $name, 3, "$name: SD_WS_110 Parse msg $msg - ERROR checksum $sum != " . SD_WS_binaryToNumber($bitData, 56, 63);
                                  return 0;
                                }
                              },
    },
    111 => {
        # TS-FT002 Water tank level monitor with temperature 
        # 0         1         2         3         4         5         6         7         8
        # 0    4    8    12   16   20   24   28   32   36   40   44   48   52   56   60   64   68   - 0  2  4  6  8  10 12 14 16
        # 0101 1111 0101 1011 1000 1000 0110 0000 1111 0001 0001 0000 1100 0100 0000 0000 1100 1001 - 5F 5B 88 60 F1 10 C4 00 C9
        # cccc cccc iiii iiii yyyy yyyy dddd dddd dddd bbbb tttt vvvv tttt tttt rrrr rrrr xxxx xxxx
        # c:  8 bit sync, always 0x5F
        # i:  8 bit ID
        # y:  8 bit type, always 0x88
        # d: 12 bit distance, med, migh, low (value in hex = cm, fill with 5DC on invalid, range 0 - 15 m)
        # b:  4 bit battery indicator, (1 = OK, any other value = low) - Not available with TS-FT002!
        # v:  4 bit interval (bit 3 = 0 180 s, bit 3 = 1 30 s, bit 0-2 = 1 5 s) - Not available with TS-FT002!
        # t: 12 bit temperature (offset by 400 and scaled by 10)
        # r:  8 bit rain (not used in XC-0331 and TS-FT002)
        # x:  8 bit XOR of values from bytes 0 to 8 = 0
        # all nibbles reversed, lsb first
        sensortype => 'TS-FT002',
        model      => 'SD_WS_111_TL',
        prematch   => sub {my $rawData = shift; return 1 if ($rawData =~ /^5F[0-9A-F]{2}88[0-9A-F]{12}/); }, # 5F 01 88 012345678912
        id         => sub {my ($rawData,undef) = @_; return substr($rawData,2,2);}, # long-id in hex
        distance   => sub {my (undef,$bitData) = @_; return (SD_WS_bin2dec(scalar(reverse(substr($bitData,24,4)))) * 16 + SD_WS_bin2dec(scalar(reverse(substr($bitData,28,4)))) * 256 + SD_WS_bin2dec(scalar(reverse(substr($bitData,32,4)))));},
        # bat        => sub {my (undef,$bitData) = @_; return substr($bitData,36,4) eq '0001' ? "ok" : "low";},
        # interval   => sub {my (undef,$bitData) = @_; return '180' if substr($bitData,44,4) eq '0000';
                                                     # return '30' if substr($bitData,44,4) eq '1000';
                                                     # return '5' if substr($bitData,44,4) eq '0111';
                                                     # return '0';
                              # },
        temp       => sub {my (undef,$bitData) = @_; return ((SD_WS_bin2dec(scalar(reverse(substr($bitData,48,4)))) * 16 + SD_WS_bin2dec(scalar(reverse(substr($bitData,52,4)))) * 256 + SD_WS_bin2dec(scalar(reverse(substr($bitData,40,4)))) - 400 ) / 10);},
        crcok          => sub { my (undef,$bitData) = @_;
                                my $xor = SD_WS_binaryToNumber($bitData, 0, 7);
                                for (my $n = 8; $n < 72; $n += 8) {
                                  $xor ^= SD_WS_binaryToNumber($bitData, $n, $n + 7);
                                }
                                if ($xor == 0) {
                                  return 1;
                                } else {
                                  Log3 $name, 3, "$name: SD_WS_111 Parse msg $msg - ERROR check $xor != 0";
                                  return 0;
                                }
                              },
    },
    113 => {
        # Wireless Grill Thermometer, Model name: GFGT 433 B1
        # ---------------------------------------------------------------------
        # 0    4    | 8    12   | 16   20   | 24   28   | 32   36   | 40   44
        # 0010 1111 | 0000 0110 | 1110 0100 | 0111 0000 | 1101 0001 | 0011 1110 - 2F06E470D13E, T: 201, T2: 279
        # iiii iiii | ???? tt22 | tttt tttt | 2222 2222 | ???? ???? | ???? ????
        # i:  8 bit id, changes after changing the battery
        # ?:  4 bit unknown, always 0000
        # t: 10 bit unsigned temperature 1 fahrenheit offset by 90
        # 2: 10 bit unsigned temperature 2 fahrenheit offset by 90
        # ?:  8 bit unknown, changes with id
        # ?:  8 bit unknown, always changes
        sensortype => 'GFGT_433_B1',
        model      => 'SD_WS_113_T',
        prematch   => sub { return 1; }, # no precheck known
        id         => sub { my ($rawData,undef) = @_; return substr($rawData,0,2); },
        temp       => sub { my (undef,$bitData) = @_;
                            $rawTemp =  SD_WS_binaryToNumber($bitData,12,13) * 256 + SD_WS_binaryToNumber($bitData,16,23);
                            my $tempFh = $rawTemp - 90; # Grad Fahrenheit
                            Log3 $name, 4, "$name: SD_WS_113_T tempraw1 = $rawTemp, temp1 = $tempFh Grad Fahrenheit";
                            return (round((($tempFh - 32) * 5 / 9) , 0)); # Grad Celsius
                          },
        temp2      => sub { my (undef,$bitData) = @_;
                            $rawTemp =  SD_WS_binaryToNumber($bitData,14,15) * 256 + SD_WS_binaryToNumber($bitData,24,31);
                            my $tempFh = $rawTemp - 90; # Grad Fahrenheit
                            Log3 $name, 4, "$name: SD_WS_113_T tempraw2 = $rawTemp, temp2 = $tempFh Grad Fahrenheit";
                            return (round((($tempFh - 32) * 5 / 9) , 0)); # Grad Celsius
                          },
        crcok      => sub {return 1;}, # Check could not be determined yet.
    } ,
    115 => {
        # https://github.com/merbanan/rtl_433/blob/master/src/devices/bresser_6in1.c
        # The compact 6-in-1 multifunction outdoor sensor transmits the data on 868.3 MHz.
        # The device uses FSK-PCM encoding, the device sends a transmission every 12 seconds.
        # There are at least two different message types:
        # temperatur, hum, uv and rain (alternating messages)
        # wind data (every message)
        # A transmission starts with a preamble of 0xAA.
        # Preamble: aa aa aa aa aa 2d d4
        #
        #           1         2         3         
        # 0123456789012345678901234567890123456789
        # ----------------------------------------
        # 3DA820B00C1618FFFFFF1808152294FFF01E0000  Msg 1, 40 Nibble from SIGNALduino, T: 15.2 H: 94 G:0 W: 0 D:180
        # CCCCIIIIIIIIFFGGGWWWDDD?TTTFHHVVVXSS      Msg 1, 36 Nibble, wind, temperature, humidity, uv 
        # CCCCIIIIIIIIFFGGGWWWDDD?RRRRRR???XSS      Msg 2, 36 Nibble, wind, rain
        # C = CRC16
        # I = station ID
        # F = flags, 8 bit (nibble 12 1: weather station, 2: indoor, 4: soil probe, nibble 13 1 bit battery change, 3 bit channel)
        # G = wind gust in 1/10 m/s, inverted, BCD coded, GGG = FE6 =~ 019 => 1.9 m/s.
        # W = wind speed in 1/10 m/s, inverted, BCD coded, LSB first nibble, MSB last two nibble, WWW = EFE =~ 101 => 1.1 m/s.
        # D = wind direction in grad, BCD coded, DDD = 158 => 158 °
        # ? = unknown, 0x0, 0x8 or 0xE
        # T = temperature in 1/10 °C, TTT = 312 => 31.2 °C
        # F = flags, 4 bit - bit 3 temperature (0=positive, 1=negative), bit 2 ?, bit 1 battery (1=ok, 0=low), bit 0 ?
        # H = humidity in percent, BCD coded, HH = 23 => 23 %
        # R = rain counter, inverted, BCD coded
        # V = uv,  inverted, BCD coded
        # X = message type, 0 = temp, hum, wind, uv, 1 = wind, rain
        # S = checksum (sum over byte 2 - 17 must be 255)
        sensortype => 'Bresser_6in1, new Bresser_5in1',
        model      => 'SD_WS_115',
        prematch   => sub { return 1; }, # no precheck known
        id         => sub {my ($rawData,undef) = @_; return substr($rawData,4,8); },
        bat        => sub {my ($rawData,$bitData) = @_;
                            return if (substr($rawData,12,1) eq '1' && substr($rawData,33,1) eq '1'); # not by weather station & rain
                            return substr($bitData,110,1) eq '1' ? 'ok' : 'low';
                          },
        batChange  => sub {my (undef,$bitData) = @_; return substr($bitData,52,1);},
        channel    => sub {my ($rawData,$bitData) = @_;
                            $channel = '';
                            $channel = substr($rawData,12,1) if (substr($rawData,12,1) ne '1'); # not weather station
                            return ($channel . SD_WS_binaryToNumber($bitData,53,55));
                          },
        windgust   => sub {my ($rawData,undef) = @_;
                            return if (substr($rawData,12,1) ne '1'); # only weather station
                            $windgust = substr($rawData,14,3);
                            $windgust =~ tr/0123456789ABCDEF/FEDCBA9876543210/;
                            # uncoverable branch true
                            return if ($windgust !~ m/^\d+$/xms);
                            return $windgust * 0.1;
                          },
        windspeed  => sub {my ($rawData,undef) = @_;
                            return if (substr($rawData,12,1) ne '1'); # only weather station
                            $windspeed = substr($rawData,18,2) . substr($rawData,17,1);
                            $windspeed =~ tr/0123456789ABCDEF/FEDCBA9876543210/;
                            # uncoverable branch true
                            return if ($windspeed !~ m/^\d+$/xms);
                            return $windspeed * 0.1;
                          },
        winddir    => sub {my ($rawData,undef) = @_;
                            return if (substr($rawData,12,1) ne '1' || substr($rawData,20,3) !~ m/^\d+$/xms); # only weather station
                            $winddir = substr($rawData,20,3);
                            return ($winddir * 1, $winddirtxtar[round(($winddir / 22.5),0)]);
                          },
        temp       => sub {my ($rawData,$bitData) = @_;
                            # uncoverable condition right
                            return if ((substr($rawData,12,1) eq '1' && substr($rawData,33,1) eq '1') || substr($rawData,24,3) !~ m/^\d+$/xms); # not by weather station & rain
                            $rawTemp = substr($rawData,24,3) * 0.1;
                            if (substr($bitData,108,1) eq '1') {
                              if ($rawTemp > 60) {
                                $rawTemp -= 100; # Bresser 6in1
                              } else {
                                $rawTemp *= -1;  # Bresser 3in1
                              }
                            }
                            return round($rawTemp,1);
                          },
        hum        => sub {my ($rawData,undef) = @_;
                            # uncoverable condition right
                            return if ((substr($rawData,12,1) eq '1' && substr($rawData,33,1) eq '1') || substr($rawData,28,2) !~ m/^\d+$/xms); # not by weather station & rain
                            $hum = substr($rawData,28,2) * 1;
                            if (substr($rawData,12,1) eq '4' && $hum >= 1 && $hum <= 16) {  # Soil Moisture
                              return $moisture_map[$hum - 1];
                            }
                            return $hum;
                          },
        rain       => sub {my ($rawData,undef) = @_;
                            return if (substr($rawData,33,1) ne '1' || substr($rawData,12,1) ne '1'); # message type || weather station
                            $rain = substr($rawData,24,6);
                            $rain =~ tr/0123456789ABCDEF/FEDCBA9876543210/;
                            # uncoverable branch true
                            return if ($rain !~ m/^\d+$/xms);
                            return $rain * 0.1;
                          },
        uv         => sub {my ($rawData,undef) = @_;
                            return if (substr($rawData,33,1) ne '0' || substr($rawData,12,1) ne '1'); # message type || weather station
                            $uv = substr($rawData,30,3);
                            $uv =~ tr/0123456789ABCDEF/FEDCBA9876543210/;
                            # uncoverable branch true
                            return if ($uv !~ m/^\d+$/xms);
                            return $uv * 0.1;
                          },
        crcok      => sub {return 1;}, # checks are in SD_Protocols.pm sub ConvBresser_6in1
    },
    116 => {
        # Thunder and lightning sensor Fine Offset WH57, aka Froggit DP60, aka Ambient Weather WH31L
        # ------------------------------------------------------------------------------------------
        #          Byte: 00 01 02 03 04 05 06 07 08 09 10 11
        #        Nibble: 01 23 45 67 89 01 23 45 67 89 01 23
        # aa aa aa 2d d4 57 00 C6 55 01 3F 00 F6 A8 20 01 C0
        #          MN;D= 57 00 C6 55 01 3F 00 F6 A8 20 01 C0 ;R=61;   batteryPercent=20, count=0, distance=63, identified=nothing
        #                FF S? II II ?B DD LL CC SS 
        # FF:   Family code 0x57 (FineOffset WH57)
        # S:    State indicator, 4 bit, 0: start-up, 1: interference, 4: noise, 8: strike
        # IIII: ID (2 bytes)
        # B:    Battery percent: 0 - 5, 5 = 100 %
        # DD:   Distance (km, 63 => Out of range)
        # LL:   Lightning strike count
        # CC:   CRC8 of the preceding 7 bytes (Polynomial 0x31, Initial value 0x00, Input not reflected, Result not reflected)
        # SS:   Sum of the preceding 8 bytes % 256
        sensortype     => 'WH57, DP60, WH31L',
        model          => 'SD_WS_116',
        prematch       => sub { ($rawData,undef) = @_; return 1 if ($rawData =~ /^57/); },
        identified     => sub { my ($rawData,undef) = @_;
                                $identified = substr($rawData,2,1);
                                if ($identified eq '0') {
                                  $identified = 'nothing';
                                } elsif ($identified eq '1') {
                                  $identified = 'noise';
                                } elsif ($identified eq '4') {
                                  $identified = 'disturbance';
                                } elsif ($identified eq '8') {
                                  $identified = 'lightning';
                                }
                                return $identified;
                              },
        id             => sub { my ($rawData,undef) = @_; return substr($rawData,4,4); },
        batteryPercent => sub { my ($rawData,undef) = @_; return hex(substr($rawData,9,1)) * 20; },
        distance       => sub { my ($rawData,undef) = @_; return hex(substr($rawData,10,2)); },
        count          => sub { my ($rawData,undef) = @_; return hex(substr($rawData,12,2)); },
        crcok          => sub { my $rawData = shift;
                                my $rc = eval {
                                  require Digest::CRC;
                                  Digest::CRC->import();
                                  1;
                                };
                                if ($rc) {
                                  my $datacheck1 = pack( 'H*', substr($rawData,0,14) );
                                  my $crcmein1 = Digest::CRC->new(width => 8, poly => 0x31);
                                  my $rr3 = $crcmein1->add($datacheck1)->hexdigest;
                                  Log3 $name, 5, "$name: SD_WS_107 Parse msg $rawData, CRC $rr3";
                                  if (hex($rr3) != hex(substr($rawData,14,2))) {
                                    Log3 $name, 3, "$name: SD_WS_116 Parse msg $rawData - ERROR CRC8";
                                    return 0;
                                  }
                                } else {
                                  Log3 $name, 1, "$name: SD_WS_116 Parse msg $rawData - ERROR CRC not load, please install modul Digest::CRC";
                                  return 0;
                                }  
                                my $checksum = 0;
                                for (my $i=0; $i < 16; $i += 2) {
                                  $checksum += hex(substr($rawData,$i,2));
                                }
                                $checksum &= 255;
                                if ($checksum != hex(substr($rawData,16,2))) {
                                  Log3 $name, 3, "$name: SD_WS_116 Parse msg $rawData - ERROR checksum";
                                  return 0;
                                }
                                return 1;
                              }
    } ,
    117 => {
        # https://github.com/merbanan/rtl_433/blob/master/src/devices/bresser_7in1.c
        # The compact 7-in-1 multifunction outdoor sensor transmits the data on 868.3 MHz.
        # The device uses FSK-PCM encoding, the device sends a transmission every 12 seconds.
        # A transmission starts with a preamble of 0xAA.
        # Preamble: aa aa aa aa aa 2d d4
        #
        #           1         2         3         4
        # 01234567890123456789012345678901234567890123456789
        # --------------------------------------------------
        # 0CF0A6F5B98A10AAAAAAAAAAAAAABABC3EAABBFCAAAAAAAAAA000000   original message
        # A65A0C5F1320BA000000000000001016940011560000000000AAAAAA   message after all nibbles xor 0xA
        # CCCCIIIIDDD??FGGGWWWRRRRRR??TTTBHHbbbbbbVVVttttttt
        # C = LFSR-16 digest, generator 0x8810 key 0xba95 with a final xor 0x6df1, which likely means we got that wrong.
        # I = station ID
        # D = wind direction in degree, BCD coded, DDD = 158 => 158 °
        # F = flags, 4 bit
        #     Bit:    0123
        #             1010
        #             r???
        #             r:   1 bit device reset, 1 after inserting battery
        #             ???: always 010
        # G = wind gust in 1/10 m/s, BCD coded, GGG = 123 => 12.3 m/s.
        # W = wind speed in 1/10 m/s, BCD coded, WWW = 123 => 12.3 m/s.
        # R = rain counter, in 0.1 mm, BCD coded RRRRRR = 000084 => 8.4 mm
        # T = temperature in 1/10 °C, BCD coded, TTT = 312 => 31.2 °C
        # B = battery. 0=Ok, 6=Low
        # H = humidity in percent, BCD coded, HH = 23 => 23 %
        # b = brightness, BCD coded, BBBBBB = 005584 => 5.584 klx
        # V = uv, BCD coded, VVV = 012 => 1.2
        # ? = unknown
        # t = trailer
        sensortype => 'Bresser_7in1',
        model      => 'SD_WS_117',
        prematch   => sub {my $rawData = shift; return 1 if ($rawData =~ /^[0-9A-F]{8}[0-9]{3}[0-9A-F]{3}[0-9]{12}[0-9A-F]{2}[0-9]{15}/); },
        id         => sub {my ($rawData,undef) = @_; return substr($rawData,4,4); },
        winddir    => sub {my ($rawData,undef) = @_;
                            $winddir = substr($rawData,8,3);
                            return ($winddir * 1, $winddirtxtar[round(($winddir / 22.5),0)]);
                          },
        batChange  => sub {my (undef,$bitData) = @_; return substr($bitData,52,1) eq '0' ? '1' : '0';},
        windgust   => sub {my ($rawData,undef) = @_; return substr($rawData,14,3) * 0.1;},
        windspeed  => sub {my ($rawData,undef) = @_; return substr($rawData,17,3) * 0.1;},
        rain       => sub {my ($rawData,undef) = @_; return substr($rawData,20,6) * 0.1;},
        temp       => sub {my ($rawData,undef) = @_;
                            $rawTemp = substr($rawData,28,3) * 0.1;
                            if ($rawTemp > 60) {$rawTemp -= 100};
                            return $rawTemp;
                          },
        bat        => sub {my ($rawData,undef) = @_; return substr($rawData,31,1) eq '0' ? 'ok' : 'low';},
        hum        => sub {my ($rawData,undef) = @_; return substr($rawData,32,2) * 1;},
        brightness => sub {my ($rawData,undef) = @_; return substr($rawData,34,6) * 0.001;},
        uv         => sub {my ($rawData,undef) = @_; return substr($rawData,40,3) * 0.1;},
        crcok      => sub {return 1;}, # checks are in SD_Protocols.pm sub ConvBresser_7in1
    },
    120 => {
        # Weather station TFA 35.1077.54.S2 with 30.3151 (T/H-transmitter), 30.3152 (rain gauge), 30.3153 (anemometer)
        # ------------------------------------------------------------------------------------------------------------
        # https://forum.fhem.de/index.php/topic,119335.msg1221926.html#msg1221926
        # 0    4    | 8    12   | 16   20   | 24   28   | 32   36   | 40   44   | 48   52   | 56   60   | 64   68   | 72   76
        # 1111 1110 | 1010 1011 | 0000 0100 | 1001 1110 | 1010 1010 | 0000 1000 | 0000 1100 | 0000 1100 | 0101 0011 | 0000 0000 - T: 19.1 H: 85 W: 1.3 R: 473.1
        # PPPP PPPW | WWWI IIII | IIIF BTTT | TTTT TTTH | HHHH HHHS | SSSS SSSG | GGGG GGGR | RRRR RRRR | RRRR RRR? | CCCC CCCC
        # 1111 1110 | 1100 1011 | 0001 0101 | 0011 0000 | 0000 0110 | 0000 1100 | 0100 0100 | 1000 1100 | 0100 1111 | 1011 1000 - 2022-06-27 18:03:06
        # PPPP PPPW | WWWI IIII | IIIF ???? | ?hhh hhh? | mmmm mmm? | ssss sssY | YYYY YYY? | ??MM MMM? | ?DDD DDD? | CCCC CCCC
        # P -  7 bit preamble
        # W -  4 bit whid, 0101=weather, 0110=time
        # I -  8 bit ident
        # F -  1 bit flag, 0=weather, 1=time
        # B -  1 bit battery
        # T - 10 bit temperature in 1/10 °C, offset 40
        # H -  8 bit humidity in percent
        # S -  8 bit windspeed in 1/10 m/s, resolution 0.33333
        # G -  8 bit windgust in 1/10 m/s, resolution 0.33333
        # R - 16 bit rain counter, resolution 0.3 mm
        # C -  8 bit CRC8 of byte 1-10 bytes, result must be 0 (Polynomial 0x31)
        # h -  6 bit hour, BCD coded
        # m -  7 bit minute, BCD coded
        # s -  7 bit second, BCD coded
        # Y -  8 bit year, BCD coded
        # M -  5 bit month, BCD coded
        # D -  6 bit day, BCD coded
        # ? -  x bit unknown
        sensortype     => 'TFA_35.1077',
        model          => 'SD_WS_120',
        prematch       => sub {return 1;}, # no precheck known
        id             => sub {my (undef,$bitData) = @_; return SD_WS_binaryToNumber($bitData,11,18);},
        bat            => sub {my (undef,$bitData) = @_; return substr($bitData,20,1) eq '0' ? 'ok' : 'low';},
        temp           => sub {my (undef,$bitData) = @_;
                                return if (substr($bitData,19,1) eq '1');
                                return SD_WS_binaryToNumber($bitData,21,30) * 0.1 - 40;
                               },
        hum            => sub {my (undef,$bitData) = @_;
                                return if (substr($bitData,19,1) eq '1');
                                return SD_WS_binaryToNumber($bitData,31,38);
                              },
        windspeed      => sub {my (undef,$bitData) = @_;
                                return if (substr($bitData,19,1) eq '1');
                                return round((SD_WS_binaryToNumber($bitData,39,46) / 3.0),1);
                              },
        windgust       => sub {my (undef,$bitData) = @_;
                                return if (substr($bitData,19,1) eq '1');
                                return round((SD_WS_binaryToNumber($bitData,47,54) / 3.0),1);
                              },
        rawRainCounter => sub {my (undef,$bitData) = @_;
                                return if (substr($bitData,19,1) eq '1');
                                return SD_WS_binaryToNumber($bitData,55,70);
                              },
        rain           => sub {my (undef,$bitData) = @_;
                                return if (substr($bitData,19,1) eq '1');
                                return SD_WS_binaryToNumber($bitData,55,70) * 0.3;
                              },
        dcf            => sub {my (undef,$bitData) = @_;
                                return if (substr($bitData,19,1) eq '0');
                                return '20' . SD_WS_binaryToNumber($bitData,47,50) . SD_WS_binaryToNumber($bitData,51,54) . '-' # year
                                       . substr($bitData,58,1) . SD_WS_binaryToNumber($bitData,59,62) . '-' # month
                                       . SD_WS_binaryToNumber($bitData,65,66) . SD_WS_binaryToNumber($bitData,67,70) . ' ' # day
                                       . SD_WS_binaryToNumber($bitData,25,26) . SD_WS_binaryToNumber($bitData,27,30) . ':' # hour 
                                       . SD_WS_binaryToNumber($bitData,32,34) . SD_WS_binaryToNumber($bitData,35,38) . ':' # minute
                                       . SD_WS_binaryToNumber($bitData,40,42) . SD_WS_binaryToNumber($bitData,43,46) # second
                              },
        crcok          => sub {my $rawData = shift;
                                my $rc = eval {
                                  require Digest::CRC;
                                  Digest::CRC->import();
                                  1;
                                };
                                if ($rc) {
                                  my $datacheck1 = pack( 'H*', substr($rawData,2,length($rawData)-2) );
                                  my $crcmein1 = Digest::CRC->new(width => 8, poly => 0x31);
                                  my $rr3 = $crcmein1->add($datacheck1)->hexdigest;
                                  if (hex($rr3) != 0) {
                                    Log3 $name, 3, "$name: SD_WS_120 Parse msg $rawData - ERROR CRC8";
                                    return 0;
                                  }
                                } else {
                                  Log3 $name, 1, "$name: SD_WS_120 Parse msg $rawData - ERROR CRC not load, please install modul Digest::CRC";
                                  return 0;
                                }  
                                return 1;
                              } 
    },
    122 => {
        # TM40, Wireless Grill-, Meat-, Roasting-Thermometer with 4 Temperature Sensors
        # -----------------------------------------------------------------------------
        # 0    4    | 8    12   | 16   20   | 24   28   | 32   36   | 40   44   | 48   52   | 56   60   | 64   68   | 72   76   | 80   84   | 88   92   | 96   100  | 104
        # 1001 0010 | 0110 0011 | 0000 0001 | 0011 0110 | 0000 0001 | 0011 0110 | 0000 0001 | 0100 0000 | 0000 0001 | 0110 1000 | 0000 0000 | 0000 0000 | 1011 1000 | 1000
        # iiii iiii | iiii iiii | 4444 4444 | 4444 4444 | 3333 3333 | 3333 3333 | 2222 2222 | 2222 2222 | tttt tttt | tttt tttt | ???? ???? | b??? p??? | CCCC CCCC | 1 
        # i: 16 bit id, changes when the batteries are inserted
        # 4: 16 bit unsigned temperature 4, 65235 = sensor not connected
        # 3: 16 bit unsigned temperature 3, 65235 = sensor not connected
        # 2: 16 bit unsigned temperature 2, 65235 = sensor not connected
        # t: 16 bit unsigned temperature 1, 65235 = sensor not connected
        # b:  1 bit battery. 0 = Ok, 1 = Low
        # p:  1 bit transmitter power. 0 = On, 1 = off
        # ?: 16 bit flags, 4 bits per sensor, meaning of the lower 3 bits 101 = not connected, 000 = connected
        # C:  8 bit check???, always changes bit 1-7, bit 0 always 0
        # Sensor transmits at intervals of about 3 to 4 seconds
        sensortype => 'TM40',
        model      => 'SD_WS_122_T',
        prematch   => sub { return 1; }, # no precheck known
        id         => sub { my ($rawData,undef) = @_; return substr($rawData,0,4); },
        temp4      => sub { my (undef,$bitData) = @_;
                             return if (substr($bitData,81,3) ne '000');
                            return SD_WS_binaryToNumber($bitData,16,31) / 10;
                          },
        temp3      => sub { my (undef,$bitData) = @_;
                             return if (substr($bitData,85,3) ne '000');
                            return SD_WS_binaryToNumber($bitData,32,47) / 10;
                          },
        temp2      => sub { my (undef,$bitData) = @_;
                             return if (substr($bitData,89,3) ne '000');
                            return SD_WS_binaryToNumber($bitData,48,63) / 10;
                          },
        temp       => sub { my (undef,$bitData) = @_;
                             return if (substr($bitData,93,3) ne '000');
                            return SD_WS_binaryToNumber($bitData,64,79) / 10;
                          },
        bat         => sub { my (undef,$bitData) = @_; return substr($bitData,88,1) eq "0" ? "ok" : "low"; },
        transmitter => sub { my (undef,$bitData) = @_; return substr($bitData,92,1) eq "0" ? "on" : "off"; },
        crcok      => sub {return 1;}, # Check could not be determined yet.
    },
  );

  Log3 $name, 4, "$name: SD_WS_Parse protocol $protocol, rawData $rawData";

  if ($protocol eq "37") {    # Bresser 7009994
    # Protokollbeschreibung:
    # https://github.com/merbanan/rtl_433_tests/tree/master/tests/bresser_3ch
    # The data is grouped in 5 bytes / 10 nibbles
    # ------------------------------------------------------------------------
    # 0         | 8    12   | 16        | 24        | 32
    # 1111 1100 | 0001 0110 | 0001 0000 | 0011 0111 | 0101 1001 0  65.1 F 55 %
    # iiii iiii | bscc tttt | tttt tttt | hhhh hhhh | xxxx xxxx
    # i: 8 bit random id (changes on power-loss)
    # b: battery indicator (0=>OK, 1=>LOW)
    # s: Test/Sync (0=>Normal, 1=>Test-Button pressed / Sync)
    # c: Channel (MSB-first, valid channels are 1-3)
    # t: Temperature (MSB-first, Big-endian)
    #    12 bit unsigned fahrenheit offset by 90 and scaled by 10
    # h: Humidity (MSB-first) 8 bit relative humidity percentage
    # x: checksum (byte1 + byte2 + byte3 + byte4) % 256
    #    Check with e.g. (byte1 + byte2 + byte3 + byte4 - byte5) % 256) = 0

    $model = "SD_WS37_TH";
    $SensorTyp = "Bresser 7009994";
    my $checksum = (SD_WS_binaryToNumber($bitData,0,7) + SD_WS_binaryToNumber($bitData,8,15) + SD_WS_binaryToNumber($bitData,16,23) + SD_WS_binaryToNumber($bitData,24,31)) & 0xFF;
    if ($checksum != SD_WS_binaryToNumber($bitData,32,39)) {
      Log3 $name, 4, "$name: SD_WS37 ERROR - checksum $checksum != ".SD_WS_binaryToNumber($bitData,32,39);
      return "";
    } else {
      Log3 $name, 4, "$name: SD_WS37 checksum ok $checksum = ".SD_WS_binaryToNumber($bitData,32,39);
      $id = substr($rawData,0,2);
      $bat = int(substr($bitData,8,1)) eq "0" ? "ok" : "low";   # Batterie-Bit konnte nicht geprueft werden
      $channel = SD_WS_binaryToNumber($bitData,10,11);
      $rawTemp =  SD_WS_binaryToNumber($bitData,12,23);
      $hum = SD_WS_binaryToNumber($bitData,24,31);
      my $tempFh = $rawTemp / 10 - 90;              # Grad Fahrenheit
      $temp = (($tempFh - 32) * 5 / 9);             # Grad Celsius
      $temp = sprintf("%.1f", $temp + 0.05);        # round
      Log3 $name, 4, "$name: SD_WS37 tempraw = $rawTemp, temp = $tempFh F, temp = $temp C, Hum = $hum";
      Log3 $name, 4, "$name: SD_WS37 decoded protocol = $protocol ($SensorTyp), sensor id = $id, channel = $channel";
    }
  }
  elsif  ($protocol eq "44" || $protocol eq "44x")  # BresserTemeo
  {
    # 0    4    8    12       20   24   28   32   36   40   44       52   56   60
    # 0101 0111 1001 00010101 0010 0100 0001 1010 1000 0110 11101010 1101 1011 1110 110110010
    # hhhh hhhh ?bcc viiiiiii sttt tttt tttt xxxx xxxx ?BCC VIIIIIII Syyy yyyy yyyy

    # - h humidity / -x checksum
    # - t temp     / -y checksum
    # - c Channel  / -C checksum
    # - V sign     / -V checksum
    # - i 7 bit random id (aendert sich beim Batterie- und Kanalwechsel)  / - I checksum
    # - b battery indicator (0=>OK, 1=>LOW)               / - B checksum
    # - s Test/Sync (0=>Normal, 1=>Test-Button pressed)   / - S checksum

    $model= "BresserTemeo";
    $SensorTyp = "BresserTemeo";

    #my $binvalue = unpack("B*" ,pack("H*", $rawData));
    my $binvalue = $bitData;

    if (length($binvalue) != 72) {
      Log3 $iohash, 4, "$name: SD_WS_Parse BresserTemeo length error (72 bits expected)!!!";
      return "";
    }

    # Check what Humidity Prefix (*sigh* Bresser!!!) 
    if ($protocol eq "44")
    {
      $binvalue = "0".$binvalue;
      Log3 $iohash, 4, "$name: SD_WS_Parse BresserTemeo Humidity <= 79  Flag";
    }
    else
    {
      $binvalue = "1".$binvalue;
      Log3 $iohash, 4, "$name: SD_WS_Parse BresserTemeo Humidity > 79  Flag";
    }

    Log3 $iohash, 4, "$name: SD_WS_Parse BresserTemeo new bin $binvalue";

    my $checksumOkay = 1;

    my $hum1Dec = SD_WS_binaryToNumber($binvalue, 0, 3);
    my $hum2Dec = SD_WS_binaryToNumber($binvalue, 4, 7);
    my $checkHum1 = SD_WS_binaryToNumber($binvalue, 32, 35) ^ 0b1111;
    my $checkHum2 = SD_WS_binaryToNumber($binvalue, 36, 39) ^ 0b1111;

    if ($checkHum1 != $hum1Dec || $checkHum2 != $hum2Dec)
    {
      Log3 $iohash, 4, "$name: SD_WS_Parse BresserTemeo checksum error in Humidity";
    }
    else
    {
      $hum = $hum1Dec.$hum2Dec;
      if ($hum < 1 || $hum > 100)
      {
        Log3 $iohash, 4, "$name: SD_WS_Parse BresserTemeo Humidity Error. Humidity=$hum";
        return "";
      }
    }

    my $temp1Dec = SD_WS_binaryToNumber($binvalue, 21, 23);
    my $temp2Dec = SD_WS_binaryToNumber($binvalue, 24, 27);
    my $temp3Dec = SD_WS_binaryToNumber($binvalue, 28, 31);
    my $checkTemp1 = SD_WS_binaryToNumber($binvalue, 53, 55) ^ 0b111;
    my $checkTemp2 = SD_WS_binaryToNumber($binvalue, 56, 59) ^ 0b1111;
    my $checkTemp3 = SD_WS_binaryToNumber($binvalue, 60, 63) ^ 0b1111;
    $temp = $temp1Dec.$temp2Dec.".".$temp3Dec;
    $temp +=0; # remove leading zeros
    if ($checkTemp1 != $temp1Dec || $checkTemp2 != $temp2Dec || $checkTemp3 != $temp3Dec)
    {
      Log3 $iohash, 4, "$name: SD_WS_Parse BresserTemeo checksum error in Temperature";
      $checksumOkay = 0;
    }
    if ($temp > 60)
    {
      Log3 $iohash, 4, "$name: SD_WS_Parse BresserTemeo Temperature Error. temp=$temp";
      return "";
    }

    my $sign = substr($binvalue,12,1);
    my $checkSign = substr($binvalue,44,1) ^ 0b1;

    if ($sign != $checkSign) 
    {
      Log3 $iohash, 4, "$name: SD_WS_Parse BresserTemeo checksum error in Sign";
      $checksumOkay = 0;
    }
    else
    {
      if ($sign)
      {
        $temp = 0 - $temp
      }
    }

    $bat = substr($binvalue,9,1);
    my $checkBat = substr($binvalue,41,1) ^ 0b1;

    if ($bat != $checkBat)
    {
      Log3 $iohash, 4, "$name: SD_WS_Parse BresserTemeo checksum error in Bat";
      $bat = undef;
    }
    else
    {
      $bat = ($bat == 0) ? "ok" : "low";
    }

    $channel = SD_WS_binaryToNumber($binvalue, 10, 11);
    my $checkChannel = SD_WS_binaryToNumber($binvalue, 42, 43) ^ 0b11;
    $id = SD_WS_binaryToNumber($binvalue, 13, 19);
    my $checkId = SD_WS_binaryToNumber($binvalue, 45, 51) ^ 0b1111111;

    if ($channel != $checkChannel || $id != $checkId)
    {
      Log3 $iohash, 4, "$name: SD_WS_Parse BresserTemeo checksum error in Channel or Id";
      $checksumOkay = 0;
    }

    if ($checksumOkay == 0)
    {
      Log3 $iohash, 4, "$name:SD_WS_Parse BresserTemeo checksum error!!! These Values seem incorrect: temp=$temp, channel=$channel, id=$id";
      return "";
    }

    $id = sprintf('%02X', $id);           # wandeln nach hex
    Log3 $iohash, 4, "$name: SD_WS_Parse model=$model, temp=$temp, hum=$hum, channel=$channel, id=$id, bat=$bat";

  }   elsif  ($protocol eq "64")  # WH2
  {
         #* Fine Offset Electronics WH2 Temperature/Humidity sensor protocol
         #* aka Agimex Rosenborg 66796 (sold in Denmark)
         #* aka ClimeMET CM9088 (Sold in UK)
         #* aka TFA Dostmann/Wertheim 30.3157 (Temperature only!) (sold in Germany)
         #* aka ...
         #*
         #* The sensor sends two identical packages of 48 bits each ~48s. The bits are PWM modulated with On Off Keying
         # * The data is grouped in 6 bytes / 12 nibbles
         #* [pre] [pre] [type] [id] [id] [temp] [temp] [temp] [humi] [humi] [crc] [crc]
         #*
         #* pre is always 0xFF
         #* type is always 0x4 (may be different for different sensor type?)
         #* id is a random id that is generated when the sensor starts
         #* temp is 12 bit signed magnitude scaled by 10 celcius
         #* humi is 8 bit relative humidity percentage
         #* Based on reverse engineering with gnu-radio and the nice article here:
         #*  http://lucsmall.com/2012/04/29/weather-station-hacking-part-2/
         # 0x4A/74 0x70/112 0xEF/239 0xFF/255 0x97/151 | Sensor ID: 0x4A7 | 255% | 239 | OK
         #{ Dispatch($defs{sduino}, "W64#FF48D0C9FFBA", undef) }

         #* Message Format:
         #* .- [0] -. .- [1] -. .- [2] -. .- [3] -. .- [4] -.
         #* |       | |       | |       | |       | |       |
         #* SSSS.DDDD DDN_.TTTT TTTT.TTTT WHHH.HHHH CCCC.CCCC
         #* |  | |     ||  |  | |  | |  | ||      | |       |
         #* |  | |     ||  |  | |  | |  | ||      | `--------- CRC
         #* |  | |     ||  |  | |  | |  | |`-------- Humidity
         #* |  | |     ||  |  | |  | |  | |
         #* |  | |     ||  |  | |  | |  | `---- weak battery
         #* |  | |     ||  |  | |  | |  |
         #* |  | |     ||  |  | |  | `----- Temperature T * 0.1
         #* |  | |     ||  |  | |  |
         #* |  | |     ||  |  | `---------- Temperature T * 1
         #* |  | |     ||  |  |
         #* |  | |     ||  `--------------- Temperature T * 10
         #* |  | |     | `--- new battery
         #* |  | `---------- ID
         #* `---- START = 9
         #*
         #*/ 
        $msg =  substr($msg,0,16);
        my (undef ,$rawData) = split("#",$msg);
        my $hlen = length($rawData);
        my $blen = $hlen * 4;
        my $msg_vor ="W64#";
        my $bitData20;
        my $sign = 0;
        my $rr2;
        my $vorpre = -1; 
        my $bitData = unpack("B$blen", pack("H$hlen", $rawData));

        my $temptyp = substr($bitData,0,8);
        if( $temptyp eq '11111110' ) {
            $rawData = SD_WS_WH2SHIFT($rawData);
            $msg = $msg_vor.$rawData;
            $bitData = unpack("B$blen", pack("H$hlen", $rawData));
            $temptyp = substr($bitData,0,8);
            Log3 $iohash, 4, "$name: SD_WS_WH2_1 msg=$msg length:".length($bitData) ;
            Log3 $iohash, 4, "$name: SD_WS_WH2_1 bitdata: $bitData" ;
          } else {
          if ( $temptyp eq '11111101' ) {
            $rawData = SD_WS_WH2SHIFT($rawData);
            $rawData = SD_WS_WH2SHIFT($rawData);
            $msg = $msg_vor.$rawData;
            $bitData = unpack("B$blen", pack("H$hlen", $rawData));
            $temptyp = substr($bitData,0,8);
            Log3 $iohash, 4, "$name: SD_WS_WH2_2 msg=$msg length:".length($bitData) ;
            Log3 $iohash, 4, "$name: SD_WS_WH2_2 bitdata: $bitData" ;
            }
        }

        if( $temptyp eq '11111111' ) {
              $vorpre = 8;
            }else{
              Log3 $iohash, 4, "$name: SD_WS_WH2_4 Error kein WH2: Typ: $temptyp" ;
              return "";
            }

       my $rc = eval
       {
        require Digest::CRC;
        Digest::CRC->import();
        1;
       };

      if($rc)
      {
      # Digest::CRC loaded and imported successfully
       Log3 $iohash, 4, "$name: SD_WS_WH2_1 msg: $msg raw: $rawData " ;
      $rr2 = SD_WS_WH2CRCCHECK($rawData);
       if ($rr2 == 0 ){
              # 1.CRC OK 
              Log3 $iohash, 4, "$name: SD_WS_WH2_1 CRC_OK   : CRC=$rr2 msg: $msg check:".$rawData ;
            }else{
               Log3 $iohash, 4, "$name: SD_WS_WH2_4 CRC_Error: CRC=$rr2 msg: $msg check:".$rawData ;
              return "";
            }
     }else {
        Log3 $iohash, 1, "$name: SD_WS_WH2_3 CRC_not_load: Modul Digest::CRC fehlt" ;
        return "";
     }

      $bitData = unpack("B$blen", pack("H$hlen", $rawData)); 
      Log3 $iohash, 4, "$name: converted to bits WH2 " . $bitData;    
      $model = "SD_WS_WH2";
      $SensorTyp = "WH2, WH2A";
      $id =   SD_WS_bin2dec(substr($bitData,$vorpre + 4,6));
      $id = sprintf('%03X', $id); 
      $channel =  0;
      $bat = SD_WS_binaryToNumber($bitData,$vorpre + 24) eq "1" ? "low" : "ok";

      $sign = SD_WS_bin2dec(substr($bitData,$vorpre + 12,1)); 

      if ($sign == 0) {
      # Temp positiv
          $temp = (SD_WS_bin2dec(substr($bitData,$vorpre + 13,11))) / 10;
      } else {
      # Temp negativ
        $temp = -(SD_WS_bin2dec(substr($bitData,$vorpre + 13,11))) / 10;
      }
      Log3 $iohash, 4, "$name: decoded protocolid $protocol ($SensorTyp) sensor id=$id, Data:".substr($bitData,$vorpre + 12,12)." temp=$temp";
      $hum =  SD_WS_bin2dec(substr($bitData,$vorpre + 24,8));   # TFA 30.3157 nur Temp, Hum = 255
      Log3 $iohash, 4, "$name: SD_WS_WH2_8 $protocol ($SensorTyp) sensor id=$id, Data:".substr($bitData,$vorpre + 24,8)." hum=$hum";
      Log3 $iohash, 4, "$name: SD_WS_WH2_9 $protocol ($SensorTyp) sensor id=$id, channel=$channel, temp=$temp, hum=$hum";

  }

  elsif (defined($decodingSubs{$protocol}))   # durch den hash decodieren
  {
    $SensorTyp=$decodingSubs{$protocol}{sensortype};
    if (!$decodingSubs{$protocol}{prematch}->( $rawData )) { 
      Log3 $iohash, 4, "$name: SD_WS_Parse $rawData protocolid $protocol ($SensorTyp) - ERROR prematch" ;
      return "";
    }
    my $retcrc=$decodingSubs{$protocol}{crcok}->( $rawData,$bitData );
    if (!$retcrc) {
      Log3 $iohash, 4, "$name: SD_WS_Parse $rawData protocolid $protocol ($SensorTyp) - ERROR CRC";
      return "";
    }
    $id = $decodingSubs{$protocol}{id}->( $rawData,$bitData );
    $temp = $decodingSubs{$protocol}{temp}->( $rawData,$bitData ) if (exists($decodingSubs{$protocol}{temp}));
    $temp2 = $decodingSubs{$protocol}{temp2}->( $rawData,$bitData ) if (exists($decodingSubs{$protocol}{temp2}));
    $temp3 = $decodingSubs{$protocol}{temp3}->( $rawData,$bitData ) if (exists($decodingSubs{$protocol}{temp3}));
    $temp4 = $decodingSubs{$protocol}{temp4}->( $rawData,$bitData ) if (exists($decodingSubs{$protocol}{temp4}));
    $hum = $decodingSubs{$protocol}{hum}->( $rawData,$bitData ) if (exists($decodingSubs{$protocol}{hum}));
    $windspeed = $decodingSubs{$protocol}{windspeed}->( $rawData,$bitData ) if (exists($decodingSubs{$protocol}{windspeed}));
    ($winddir,$winddirtxt) = $decodingSubs{$protocol}{winddir}->( $rawData,$bitData ) if (exists($decodingSubs{$protocol}{winddir}));
    $windgust = $decodingSubs{$protocol}{windgust}->( $rawData,$bitData ) if (exists($decodingSubs{$protocol}{windgust}));
    $channel = $decodingSubs{$protocol}{channel}->( $rawData,$bitData ) if (exists($decodingSubs{$protocol}{channel}));
    $model = $decodingSubs{$protocol}{model};
    $bat = $decodingSubs{$protocol}{bat}->( $rawData,$bitData ) if (exists($decodingSubs{$protocol}{bat}));
    $batVoltage = $decodingSubs{$protocol}{batVoltage}->( $rawData,$bitData ) if (exists($decodingSubs{$protocol}{batVoltage}));
    $batChange = $decodingSubs{$protocol}{batChange}->( $rawData,$bitData ) if (exists($decodingSubs{$protocol}{batChange}));
    $batteryPercent = $decodingSubs{$protocol}{batteryPercent}->( $rawData,$bitData ) if (exists($decodingSubs{$protocol}{batteryPercent}));
    $rawRainCounter = $decodingSubs{$protocol}{rawRainCounter}->( $rawData,$bitData ) if (exists($decodingSubs{$protocol}{rawRainCounter}));
    $rain = $decodingSubs{$protocol}{rain}->( $rawData,$bitData ) if (exists($decodingSubs{$protocol}{rain}));
    $rain_total = $decodingSubs{$protocol}{rain_total}->( $rawData,$bitData ) if (exists($decodingSubs{$protocol}{rain_total}));
    $sendCounter = $decodingSubs{$protocol}{sendCounter}->( $rawData,$bitData ) if (exists($decodingSubs{$protocol}{sendCounter}));
    $beep = $decodingSubs{$protocol}{beep}->( $rawData,$bitData ) if (exists($decodingSubs{$protocol}{beep}));
    $adc = $decodingSubs{$protocol}{adc}->( $rawData,$bitData ) if (exists($decodingSubs{$protocol}{adc}));
    if ($model eq "SD_WS_33_T" || $model eq "SD_WS_58_T") {      # for SD_WS_33 or SD_WS_58 discrimination T - TH
      $model = $decodingSubs{$protocol}{model}."H" if $hum != 0; # for models with Humidity
    }
    $sendmode = $decodingSubs{$protocol}{sendmode}->( $rawData,$bitData ) if (exists($decodingSubs{$protocol}{sendmode}));
    $trend = $decodingSubs{$protocol}{trend}->( $rawData,$bitData ) if (exists($decodingSubs{$protocol}{trend}));
    $distance = $decodingSubs{$protocol}{distance}->( $rawData,$bitData ) if (exists($decodingSubs{$protocol}{distance}));
    $count = $decodingSubs{$protocol}{count}->( $rawData,$bitData ) if (exists($decodingSubs{$protocol}{count}));
    $identified = $decodingSubs{$protocol}{identified}->( $rawData,$bitData ) if (exists($decodingSubs{$protocol}{identified}));
    $uv = $decodingSubs{$protocol}{uv}->( $rawData,$bitData ) if (exists($decodingSubs{$protocol}{uv}));
    $brightness = $decodingSubs{$protocol}{brightness}->( $rawData,$bitData ) if (exists($decodingSubs{$protocol}{brightness}));
    $transmitter = $decodingSubs{$protocol}{transmitter}->( $rawData,$bitData ) if (exists($decodingSubs{$protocol}{transmitter}));
    $dcf = $decodingSubs{$protocol}{dcf}->( $rawData,$bitData ) if (exists($decodingSubs{$protocol}{dcf}));
    Log3 $iohash, 4, "$name: SD_WS_Parse decoded protocol-id $protocol ($SensorTyp), sensor-id $id";
  }
  else {
    Log3 $iohash, 2, "$name: SD_WS_Parse unknown message, please report. converted to bits: $bitData";
    return;
  }

  if (!defined($model)) {
    return;
  }

  my $deviceCode;

  my $longids = AttrVal($ioname,'longids',0);
  if (($longids ne "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/)))
  {
    $deviceCode = $model . '_' . $id;                       # for sensors without channel
    $deviceCode .= $channel if (defined $channel);          # old form of longid
    if (!defined($modules{SD_WS}{defptr}{$deviceCode})) {
      $deviceCode = $model . '_' . $id;                     # for sensors without channel
      $deviceCode .= '_' . $channel if (defined $channel);  # new form of longid
    }
    Log3 $iohash,4, "$name: using longid for $longids device $deviceCode";
  } else {
    $deviceCode = $model; # for sensors without channel
    $deviceCode .= '_' . $channel if (defined $channel);
  }

  my $def = $modules{SD_WS}{defptr}{$deviceCode};
  $def = $modules{SD_WS}{defptr}{$deviceCode} if(!$def);

  if(!$def) {
    if (($longids ne "0") && ($longids eq "1" || $longids eq "ALL" || (",$longids," =~ m/,$model,/))) {
      my @found = devspec2array(q[TYPE=SD_WS:FILTER=i:replaceBattery>0]);
      if (scalar(@found) > 0) {
        my $rname = $found[0];
        my $rproto = InternalVal($rname, $ioname. q[_Protocol_ID], undef);
        if (defined $rproto && $rproto eq $protocol) {
          my $rhash = $defs{$rname};
          my $rdef = $rhash->{DEF};
          Log3 $name, 3, qq[$rname: SD_WS_Parse, change DEF from $rdef in $deviceCode];
          CommandModify(undef, qq[$rname $deviceCode]);
          delete($rhash->{replaceBattery});
          RemoveInternalTimer($rhash);
          return $rname;
        }
      }
    }
    Log3 $iohash, 1, "$name: SD_WS_Parse UNDEFINED sensor $model detected, code $deviceCode";
    return "UNDEFINED $deviceCode SD_WS $deviceCode";
  }

  my $hash = $def;
  $name = $hash->{NAME};
  return "" if(IsIgnored($name));

  if (defined $temp) {
    if (($temp < -30 || $temp > 70) && $protocol ne '106' && $protocol ne '113' && $protocol ne '122') { # not forBBQ temperature sensor GT-TMBBQ-01s, Wireless Grill Thermometer GFGT 433 B1 and TM40
      Log3 $name, 3, "$ioname: SD_WS_Parse $deviceCode - ERROR temperature $temp";
      return "";  
    }
  }
  if (defined $hum) {
    if ($hum > 100) {
      Log3 $name, 3, "$ioname: SD_WS_Parse $deviceCode - ERROR humidity $hum";
      return "";  
    }
  }

  # Sanity checks
  if($def && $protocol ne '106' && $protocol ne '113' && $protocol ne '122') { # not forBBQ temperature sensor GT-TMBBQ-01s, Wireless Grill Thermometer GFGT 433 B1 and TM40
    my $timeSinceLastUpdate = abs(ReadingsAge($name, 'state', 0));
    # temperature
    my $oldTemp = ReadingsVal($name, 'temperature', undef);
    if (defined $oldTemp && defined $temp) {
      #my $oldTemp = ReadingsVal($name, "temperature", undef);
      my $maxdeviation = AttrVal($name, "max-deviation-temp", 1);       # default 1 K
      my $diffTemp = abs($temp - $oldTemp);
      $diffTemp = sprintf("%.1f", $diffTemp);       
      Log3 $name, 4, "$ioname: $name old temp $oldTemp, age $timeSinceLastUpdate, new temp $temp, diff temp $diffTemp";
      my $maxDiffTemp = $timeSinceLastUpdate / 60 + $maxdeviation;      # maxdeviation + 1.0 Kelvin/Minute
      $maxDiffTemp = sprintf("%.1f", $maxDiffTemp + 0.05);              # round 0.1
      Log3 $name, 4, "$ioname: $name max difference temperature $maxDiffTemp K";
      if ($diffTemp > $maxDiffTemp) {
        Log3 $name, 3, "$ioname: $name ERROR - Temp diff too large (old $oldTemp, new $temp, diff $diffTemp)";
        return "";
      }
    }
    # humidity
    my $oldHum = ReadingsVal($name, 'humidity', undef);
    if (defined $oldHum && defined $hum) {
      #my $oldHum = ReadingsVal($name, "humidity", undef);
      my $maxdeviation = AttrVal($name, "max-deviation-hum", 1);        # default 1 %
      my $diffHum = abs($hum - $oldHum);
      $diffHum = sprintf("%.1f", $diffHum);       
      Log3 $name, 4, "$ioname: $name old hum $oldHum, age $timeSinceLastUpdate, new hum $hum, diff hum $diffHum";
      my $maxDiffHum = $timeSinceLastUpdate / 60 + $maxdeviation;       # $maxdeviation + 1.0 %/Minute
      $maxDiffHum = sprintf("%1.f", $maxDiffHum + 0.5);                 # round 1
      Log3 $name, 4, "$ioname: $name max difference humidity $maxDiffHum %";
      if ($diffHum > $maxDiffHum) {
        Log3 $name, 3, "$ioname: $name ERROR - Hum diff too large (old $oldHum, new $hum, diff $diffHum)";
        return "";
      }
    }
  }

  Log3 $name, 4, "$ioname: SD_WS_Parse $name ($rawData)";

  $hash->{lastReceive} = time();
  $hash->{lastMSG} = $rawData;
  if (defined($bitData2)) {
    $hash->{bitMSG} = $bitData2;
  } else {
    $hash->{bitMSG} = $bitData;
  }

  #my $state = (($temp > -60 && $temp < 70) ? "T: $temp":"T: xx") . (($hum > 0 && $hum < 100) ? " H: $hum":"");
  my $state = "";
  if (defined($temp)) {
    $state .= "T: $temp";
  }
  if (defined($temp2)) {
    $state .= ' ' if (length($state) > 0);
    $state .= "T2: $temp2";
  }
  if (defined($temp3)) {
    $state .= ' ' if (length($state) > 0);
    $state .= "T3: $temp3";
  }
  if (defined($temp4)) {
    $state .= ' ' if (length($state) > 0);
    $state .= "T4: $temp4";
  }
  if (defined($hum) && ($hum > 0 && $hum < 100)) {
    $state .= " H: $hum"
  }
  if (defined($windspeed)) {
    $state .= ' ' if (length($state) > 0);
    $state .= "W: $windspeed"
  }
  if (defined($rain_total)) {
    $state .= ' ' if (length($state) > 0);
    $state .= "R: $rain_total"
  }
  if (defined($rain)) {
    $state .= ' ' if (length($state) > 0);
    $state .= "R: $rain"
  }
  if (defined($identified)) {
    $state .= ' ' if (length($state) > 0);
    $state .= "I: $identified";
  }
  if (defined($distance)) {
    $state .= ' ' if (length($state) > 0);
    $state .= "D: $distance";
  }
  if (defined($brightness)) {
    $state .= ' ' if (length($state) > 0);
    $state .= "B: $brightness";
  }

  ### protocol 33 has different bits per sensor type
  if ($protocol eq "33") {
    if (AttrVal($name,'model',0) eq "S522") {                 # Conrad S522
      $bat = undef;
      $trendTemp = ('consistent', 'rising', 'falling', 'unknown')[SD_WS_binaryToNumber($bitData,36,37)];
    } elsif (AttrVal($name,'model',0) eq "E0001PA") {         # renkforce E0001PA
      $bat = substr($bitData,35,1) eq "0" ? "ok" : "low"; 
      $sendmode = substr($bitData,34,1) eq "1" ? "manual" : "auto";
    } elsif (AttrVal($name,'model',0) eq "TX-EZ6") {          # TZS First Austria TX-EZ6
      $bat = substr($bitData,35,1) eq "0" ? "ok" : "low"; 
      $sendmode = substr($bitData,34,1) eq "1" ? "manual" : "auto";
      $trendTemp = ('consistent', 'rising', 'falling', 'unknown')[SD_WS_binaryToNumber($bitData,10,11)];
      $trendHum = ('consistent', 'rising', 'falling', 'unknown')[SD_WS_binaryToNumber($bitData,36,37)];
    }
  }

  ### Protocol 85 without wind direction
  if ($protocol eq "85") {
    if (AttrVal($name,'model',0) ne "TFA_30.3251.10") {
      $winddir = undef;
      $winddirtxt = undef;
    }
  }

  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "state", $state);
  readingsBulkUpdate($hash, "temperature", $temp)  if (defined($temp) && (($temp > -60 && $temp < 70 ) || $protocol eq '106' || $protocol eq '113' || $protocol eq '122'));
  readingsBulkUpdate($hash, "temperature2", $temp2)  if (defined($temp2) && (($temp2 > -60 && $temp2 < 70 ) || $protocol eq '113' || $protocol eq '122'));
  readingsBulkUpdate($hash, "temperature3", $temp3)  if (defined($temp3) && (($temp3 > -60 && $temp3 < 70 ) || $protocol eq '122'));
  readingsBulkUpdate($hash, "temperature4", $temp4)  if (defined($temp4) && (($temp4 > -60 && $temp4 < 70 ) || $protocol eq '122'));
  readingsBulkUpdate($hash, "humidity", $hum)  if (defined($hum) && ($hum > 0 && $hum < 100 )) ;
  readingsBulkUpdate($hash, 'windSpeed', $windspeed)  if (defined($windspeed)) ;
  readingsBulkUpdate($hash, 'windDirectionDegree', $winddir)  if (defined($winddir)) ;
  readingsBulkUpdate($hash, 'windDirectionText', $winddirtxt)  if (defined($winddirtxt)) ;
  readingsBulkUpdate($hash, 'windGust', $windgust)  if (defined($windgust)) ;
  readingsBulkUpdate($hash, "batteryState", $bat) if (defined($bat) && length($bat) > 0) ;
  readingsBulkUpdate($hash, "batteryVoltage", $batVoltage)  if (defined($batVoltage));
  readingsBulkUpdate($hash, 'batteryPercent', $batteryPercent)  if (defined($batteryPercent));
  readingsBulkUpdateIfChanged($hash, "batteryChanged", $batChange) if (defined($batChange));
  readingsBulkUpdate($hash, "channel", $channel, 0) if (defined($channel)&& length($channel) > 0);
  readingsBulkUpdate($hash, "trend", $trend) if (defined($trend) && length($trend) > 0);
  readingsBulkUpdate($hash, "temperatureTrend", $trendTemp) if (defined($trendTemp) && length($trendTemp) > 0);
  readingsBulkUpdate($hash, "humidityTrend", $trendHum) if (defined($trendHum) && length($trendHum) > 0);
  readingsBulkUpdate($hash, "sendmode", $sendmode) if (defined($sendmode) && length($sendmode) > 0);
  readingsBulkUpdate($hash, "type", $SensorTyp, 0)  if (defined($SensorTyp));
  readingsBulkUpdate($hash, "beep", $beep)  if (defined($beep));
  readingsBulkUpdate($hash, "adc", $adc)  if (defined($adc));
  readingsBulkUpdate($hash, 'rain', $rain)  if (defined($rain));
  readingsBulkUpdate($hash, "rawRainCounter", $rawRainCounter)  if (defined($rawRainCounter));
  readingsBulkUpdate($hash, "rain_total", $rain_total)  if (defined($rain_total));
  readingsBulkUpdate($hash, "sendCounter", $sendCounter)  if (defined($sendCounter));
  readingsBulkUpdate($hash, "distance", $distance)  if (defined($distance));
  readingsBulkUpdate($hash, 'count', $count)  if (defined($count));
  readingsBulkUpdate($hash, 'identified', $identified)  if (defined($identified));
  readingsBulkUpdate($hash, "uv", $uv)  if (defined($uv));
  readingsBulkUpdate($hash, 'brightness', $brightness)  if (defined($brightness));
  readingsBulkUpdateIfChanged($hash, 'transmitter', $transmitter)  if (defined($transmitter));
  readingsBulkUpdate($hash, 'dcf', $dcf)  if (defined($dcf));
  readingsEndUpdate($hash, 1); # Notify is done by Dispatch

  return $name;
}

#############################
# Pruefsummenberechnung "reverse Galois LFSR with byte reflection"
# Wird nur fuer TFA Drop Protokoll benoetigt
# TFA Drop Protokoll benoetigt als gen 0x31, als key 0xf4

sub SD_WS_LFSR_digest8_reflect {
  my ($bytes, $gen, $key, $rawData) = @_;
  carp "SD_WS_LFSR_digest8_reflect, too few arguments ($bytes, $gen, $key, $rawData)" if @_ < 4;
  my $sum = 0;
  my $k = 0;
  my $i = 0;
  my $data = 0;
  for ( $k = $bytes - 1; $k >= 0; $k = $k - 1 ) {
    $data = hex(substr($rawData, $k*2, 2));
    for ( $i = 0; $i < 8; $i = $i + 1 ) {
      if ( ($data >> $i) & 0x01) {
        $sum = $sum^$key;
      }
      if ( $key & 0x80 ) {
        $key = ( $key << 1) ^ $gen;
      } else {
        $key = ( $key << 1);
      }
    }
  }
  $sum = $sum & 0xff;
  return $sum;
}

#############################
sub SD_WS_bin2dec {
  my $h = shift // return;
  my $int = unpack("N", pack("B32",substr("0" x 32 . $h, -32))); 
  return sprintf("%d", $int); 
}

#############################
sub SD_WS_binaryToNumber {
  carp 'SD_WS_binaryToNumber, too few arguments' if @_ < 2;
  my $binstr=shift;
  my $fbit=shift;
  my $lbit=$fbit;
  $lbit = shift // $lbit;
  return oct("0b".substr($binstr,$fbit,($lbit-$fbit)+1));
}

#############################
sub SD_WS_WH2CRCCHECK {
  my $rawData = shift // return;
  my $datacheck1 = pack( 'H*', substr($rawData,2,length($rawData)-2) );
  my $crcmein1 = Digest::CRC->new(width => 8, poly => 0x31);
  my $rr3 = $crcmein1->add($datacheck1)->hexdigest;
  $rr3 = sprintf("%d", hex($rr3));
  Log3 "SD_WS_CRCCHECK", 4, "SD_WS_WH2CRCCHECK :  raw:$rawData CRC=$rr3 " ;
  return $rr3 ;
}

#############################
sub SD_WS_WH2SHIFT {
  my $rawData = shift // return;
  my $hlen = length($rawData);
  my $blen = $hlen * 4;
  my $bitData = unpack("B$blen", pack("H$hlen", $rawData));
  my $bitData2 = '1'.unpack("B$blen", pack("H$hlen", $rawData));
  my $bitData20 = substr($bitData2,0,length($bitData2)-1);
  $blen = length($bitData20);
  $hlen = $blen / 4;
  $rawData = uc(unpack("H$hlen", pack("B$blen", $bitData20)));
  $bitData = $bitData20;
  Log3 "SD_WS_WH2SHIFT", 4, "SD_WS_WH2SHIFT_0  raw: $rawData length:".length($bitData) ;
  Log3 "SD_WS_WH2SHIFT", 4, "SD_WS_WH2SHIFT_1  bitdata: $bitData" ;
  return $rawData;
}

1;

=pod
=encoding utf8
=item summary    Supports various weather stations
=item summary_DE Unterst&uumltzt verschiedene Funk Wetterstationen
=begin html

<a name="SD_WS"></a>
<h3>Weather Sensors various protocols</h3>
<ul>
  The SD_WS module processes the messages from various environmental sensors received from an IO device (CUL, CUN, SIGNALDuino, SignalESP etc.).<br><br>
  <b>Known models:</b>
  <ul>
    <li>ADE WS1907 Weather station with rain gauge</li>
    <li>Atech wireless weather station</li>
    <li>BBQ temperature sensor GT-TMBBQ-01s (transmitter), GT-TMBBQ-01e (receiver)</li>
    <li>Bresser 5-in-1, 6-in-1 and 7-in-1 Comfort Weather Center, 7009994, Professional rain gauge, Temeo</li>
    <li>Conrad S522</li>
    <li>EuroChron EFTH-800, EFS-3110A (temperature and humidity sensor)</li>
    <li>Fine Offset WH51, aka ECOWITT WH51, aka Froggit DP100, aka MISOL/1 (soil moisture sensor)</li>
    <li>Fine Offset WH57, aka Froggit DP60, aka Ambient Weather WH31L (thunder and lightning sensor)</li>
    <li>Fody E42 (temperature and humidity sensor)</li>
    <li>NC-3911, NC-3912 refrigerator thermometer</li>
    <li>Opus XT300</li>
    <li>PV-8644 infactory Poolthermometer</li>
    <li>Renkforce E0001PA</li>
    <li>Rain gauge DROP TFA 47.3005.01 with rain sensor TFA 30.3233.01</li>
    <li>TECVANCE TV-4848</li>
    <li>Thermometer FT007T, FT007TP, F007T, F007TP</li>
    <li>Thermo-Hygrometer FT007TH, F007TH</li>
    <li>TS-FT002 Water tank level monitor with temperature</li>
    <li>TX-EZ6 for Weatherstation TZS First Austria</li>
    <li>WH2, WH2A (TFA Dostmann/Wertheim 30.3157 (sold in Germany), Agimex Rosenborg 66796 (sold in Denmark),ClimeMET CM9088 (Sold in UK)</li>
    <li>Weatherstation Auriol IAN 283582 Version 06/2017 (Lidl), Modell-Nr.: HG02832D</li>
    <li>Weatherstation Auriol AHFL 433 B2, IAN 314695 (Lidl)</li>
    <li>Weatherstations and sensors TFA 30.3151, 30.3152, 30.3153, 30.3157, 30.3200, 30.3208.02, 30.3221.02, 30.3222.02, 30.3228.02, 30.3229.02, 30.3233.01, 30.3251.10, 35.1077.54.S2, 35.1140.01</li>
    <li>Wireless Grill Thermometer, Model name: GFGT 433 B1</li>
  </ul><br><br>

  <a name="SD_WS_Define"></a>
  <b>Define</b><br><br>
  <ul>
    Newly received sensors are usually automatically created in FHEM via autocreate.<br>
    Sensors that support a channel number are created, for example, in the following form:<br>
    <code>SD_WS_33_1</code><br>
    The 1 indicates that the sensor with channel 1 was created.
    Sensors that do not offer a channel selection are created without a channel number, such as:<br>
    <code>SD_WS_108</code><br>
    If several sensors with no or the same channel number are received,
    so you can set the attribute "longids" with the SIGNALduino.    
    It is also possible to set up the devices manually with the following command:<br><br>
    <code>define &lt;name&gt; SD_WS &lt;code&gt; </code> <br><br>
    &lt;code&gt; is the channel or individual identifier used to identify the sensor.<br>
  </ul><br><br>

  <a name="SD_WS Events"></a>
  <b>Generated readings:</b><br><br>
  <ul>
    Some devices may not support all readings, so they will not be presented<br>
  </ul>
  <ul>
    <li>adc (raw value from analog to digital converter)</li>
    <li>batteryChanged (1)</li>
    <li>batteryState (low or ok)</li>
    <li>batteryVoltage (battery voltage in volts)</li>
    <li>batteryPercent (battery level in %)</li>
    <li>brightness (kLux)</li>
    <li>channel (number of channel</li>
    <li>distance (distance in cm (protocol 111) or km (protocol 116)</li>
    <li>humidity (humidity (1-100 % only if available)</li>
    <li>humidityTrend (consistent, rising, falling)</li>
    <li>sendmode (automatic or manual)</li>
    <li>rain (l/m&sup2;))</li>
    <li>rain_total (l/m&sup2;))</li>
    <li>state (T: H: W: R:)</li>
    <li>temperature (&deg;C)</li>
    <li>temperatureTrend (consistent, rising, falling)</li>
    <li>type (type of sensor)</li>
    <li>uv (ultraviolet radiation)</li>
    <li>windDirectionDegree (Wind direction, grad)</li>
    <li>windDirectionText (Wind direction, N, NNE, NE, ENE, E, ESE, SE, SSE, S, SSW, SW, WSW, W, WNW, NW, NNW)</li>
    <li>windGust (Gust of wind, m/s)</li>
    <li>windSpeed (Wind speed, m/s)</li>
  </ul><br><br>

  <a name="SD_WS Attribute"></a>
  <b>Attributes</b><br><br>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li><br>
    <li><a href="#ignore">ignore</a></li><br>
    <li>max-deviation-hum<br>
      (Default: 1, allowed values: 1,2,3,4,5,6,7,8,9,10,15,20,25,30,35,40,45,50)<br>
      <a name="max-deviation-hum"></a>
      Maximum permissible deviation of the measured humidity from the previous value in percent.<br>
      Since many of the sensors handled in the module do not have checksums, etc. send, it can easily come to the reception of implausible values. 
      To intercept these, a maximum deviation from the last correctly received value can be set. 
      Greater deviations are then ignored and result in an error message in the log file, such as an error message like this:<br>
      <code>SD_WS_TH_84 ERROR - Hum diff too large (old 60, new 68, diff 8)</code><br>
      In addition to the set value, a value dependent on the difference of the reception times is added. 
      This is 1.0% relative humidity per minute. 
      This means e.g. if a difference of 8 is set and the time interval of receipt of the messages is 3 minutes, the maximum allowable difference is 11.<br>
      Instead of the <code>max-deviation-hum</code> and <code>max-deviation-temp</code> attributes, 
      the <code>doubleMsgCheck_IDs</code> attribute of the SIGNALduino can also be used if the sensor is well received. 
      An update of the readings is only executed if the same values ??have been received at least twice.
      <a name="end_max-deviation-hum"></a>
    </li><br>
    <li>max-deviation-temp<br>
      (Default: 1, allowed values: 1,2,3,4,5,6,7,8,9,10,15,20,25,30,35,40,45,50)<br>
      <a name="max-deviation-temp"></a>
      Maximum permissible deviation of the measured temperature from the previous value in Kelvin.<br>
      Explanation see attribute "max-deviation-hum".
      <a name="end_max-deviation-temp"></a>
    </li><br>
    <li>model<br>
      (Default: other, currently supported sensors: E0001PA, S522, TFA_30.3251.10 and TX-EZ6)<br>
      <a name="model"></a>
      The sensors of the "SD_WS_33 series" use different positions for the battery bit and different readings. 
      If the battery bit is detected incorrectly (low instead of ok), then you can possibly adjust with the model selection of the sensor.<br>
      So far, 3 variants are known. All sensors are created by Autocreate as model "other". 
      If you receive a Conrad S522, Renkforce E0001PA or TX-EZ6, then set the appropriate model for the proper processing of readings.
      <br>
      Protocol 85 (SD_WS_85_THW) decodes two different sensor types: TFA 30.3222.02 (thermo-hygro-wind) and 30.3251.10 (wind).
      The attribute must be set to this value "TFA_30.3251.10" so that the wind direction is also displayed for the sensor TFA 30.3251.10.
      <a name="end_model"></a>
    </li><br>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li><br>
    <li><a href="#showtime">showtime</a></li><br>
  </ul><br>
  <a name="SD_WS Set"></a>
  <b>Set</b><br><br>
  <ul>
    <li>replaceBatteryForSec<br>
      (Only available for devices whose SIGNALduinos have the "longids" attribute activated.)
      <br><br>
      <code>replaceBatteryForSec &lt;seconds&gt;</code>
      <br><br>
      Puts the device into battery change mode for <code>&lt;secondes&gt;</code>.
      The first unknown address with the same protocol that is received replaces the current device address.
    </li>
  </ul><br>
</ul>

=end html

=begin html_DE

<a name="SD_WS"></a>
<h3>SD_WS</h3>
<ul>
  Das Modul SD_WS verarbeitet die von einem IO-Ger&aumlt (CUL, CUN, SIGNALDuino, SignalESP etc.) empfangenen Nachrichten verschiedener Umwelt-Sensoren.<br>
  <br>
  <b>Unterst&uumltzte Modelle:</b><br><br>
  <ul>
    <li>ADE WS1907 Wetterstation mit Regenmesser</li>
    <li>Atech Wetterstation</li>
    <li>BBQ Temperatur Sensor GT-TMBBQ-01s (Sender), GT-TMBBQ-01e (Empfaenger)</li>
    <li>Bresser 5-in-1, 6-in-1 und 7-in-1 Comfort Wetter Center, 7009994, Profi Regenmesser, Temeo</li>
    <li>Conrad S522</li>
    <li>EuroChron EFTH-800, EFS-3110A (Temperatur- und Feuchtigkeitssensor)</li>
    <li>Fine Offset WH51, aka ECOWITT WH51, aka Froggit DP100, aka MISOL/1 (Bodenfeuchtesensor)</li>
    <li>Fine Offset WH57, aka Froggit DP60, aka Ambient Weather WH31L (Gewittersensor)</li>
    <li>Fody E42 (Temperatur- und Feuchtigkeitssensor)</li>
    <li>Kabelloses Grillthermometer, Modellname: GFGT 433 B1</li>
    <li>NC-3911, NC-3912 digitales Kuehl- und Gefrierschrank-Thermometer</li>
    <li>Opus XT300</li>
    <li>PV-8644 infactory Poolthermometer</li>
    <li>Regenmesser DROP TFA 47.3005.01 mit Regensensor TFA 30.3233.01</li>
    <li>Renkforce E0001PA</li>
    <li>TECVANCE TV-4848</li>
    <li>Temperatur-Sensor FT007T, FT007TP, F007T, F007TP</li>
    <li>Temperatur/Feuchte-Sensor FT007TH, F007TH</li>
    <li>TS-FT002 Wassertank Füllstandswächter mit Temperatur</li>
    <li>TX-EZ6 fuer Wetterstation TZS First Austria</li>
    <li>WH2, WH2A (TFA Dostmann/Wertheim 30.3157 (Deutschland), Agimex Rosenborg 66796 (Denmark), ClimeMET CM9088 (UK)</li>
    <li>Wetterstation Auriol IAN 283582 Version 06/2017 (Lidl), Modell-Nr.: HG02832D</li>
    <li>Wetterstation Auriol AHFL 433 B2, IAN 314695 (Lidl)</li>
    <li>Wetterstationen und Sensoren TFA 30.3151, 30.3152, 30.3153, 30.3157, 30.3200, 30.3208.02, 30.3221.02, 30.3222.02, 30.3228.02, 30.3229.02, 30.3233.01, 30.3251.10, 35.1077.54.S2, 35.1140.01</li>
    </ul>
  <br><br>

  <a name="SD_WS_Define"></a>
  <b>Define</b><br><br>
  <ul>
    Neu empfangene Sensoren werden in FHEM normalerweise per autocreate automatisch angelegt.<br>
    Sensoren, die eine Kanalnummer unterstützen, werden z.B. in folgender Form angelegt:<br>
    <code>SD_WS_33_1</code><br>
    Dabei kennzeichnet die 1 das der Sensor mit Kanal 1 angelegt wurde.
    Sensoren, die keine Kanalauswahl bieten, werden ohne Kanalnummer angelegt, wie z.B.:<br>
    <code>SD_WS_108</code><br>
    Sollten mehrere Sensoren ohne oder mit gleicher Kanalnummer empfangen werden,
    so kann man beim SIGNALduino das Attribut "longids" setzen.
    Jeder Sensor bekommt dann eine eindeutige Ident zugeordnet, die sich allerdings beim Batteriewechsel oder Neustart ändern kann.<br>
    Es ist auch m&ouml;glich, die Ger&auml;te manuell mit folgendem Befehl einzurichten:<br><br>
    <code>define &lt;name&gt; SD_WS &lt;code&gt; </code> <br><br>
    &lt;code&gt; ist der Kanal oder eine individuelle Ident, mit dem der Sensor identifiziert wird.<br>
  </ul>
  <br><br>

  <a name="SD_WS Events"></a>
  <b>Generierte Readings:</b><br><br>
  <ul>(verschieden, je nach Typ des Sensors)</ul>
  <ul>
    <li>adc (Roh-Wert vom Analog-Digital-Wandler)</li>
    <li>batteryChanged (1)</li>
    <li>batteryState (low oder ok)</li>
    <li>batteryVoltage (Batteriespannung in Volt)</li>
    <li>batteryPercent (Batteriestand in %)</li>
    <li>brightness (Helligkeit in kLux)</li>
    <li>channel (Sensor-Kanal)</li>
    <li>distance (Entfernung in cm (Protokoll 111) oder km (Protokoll 116)</li>
    <li>humidity (Luft-/Bodenfeuchte, 1-100 %)</li>
    <li>humidityTrend (Trend Luftfeuchte, gleichbleibend, steigend, fallend)</li>
    <li>rain (Regenmenge l/m&sup2;))</li>
    <li>rain_total (Regenmenge l/m&sup2;))</li>
    <li>sendmode (Sendemodus, automatic oder manuell mittels Taster am Sender)</li>
    <li>state (T: H: W: R:)</li>
    <li>temperature (Temperatur &deg;C)</li>
    <li>temperatureTrend (Trend Temperatur gleichbleibend, steigend, fallend)</li>
    <li>type (Sensortypen)</li>
    <li>uv (Ultraviolettstrahlung)</li>
    <li>windDirectionDegree (Windrichtung, Grad)</li>
    <li>windDirectionText (Windrichtung, N, NNE, NE, ENE, E, ESE, SE, SSE, S, SSW, SW, WSW, W, WNW, NW, NNW)</li>
    <li>windGust (Windboe, m/s)</li>
    <li>windSpeed (Windgeschwindigkeit, m/s)</li>
  </ul>
  <br><br>

  <a name="SD_WS Attribute"></a>
  <b>Attribute</b><br><br>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li><br>
    <li><a href="#ignore">ignore</a></li><br>
    <li>max-deviation-hum<br>
      (Standard: 1, erlaubte Werte: 1,2,3,4,5,6,7,8,9,10,15,20,25,30,35,40,45,50)<br>
      <a name="max-deviation-hum"></a>
      Maximal erlaubte Abweichung der gemessenen Feuchte zum vorhergehenden Wert in Prozent.
      <br>Da viele der in dem Modul behandelten Sensoren keine Checksummen o.&auml;. senden, kann es leicht zum Empfang von unplausiblen Werten kommen. 
      Um diese abzufangen, kann eine maximale Abweichung zum letzten korrekt empfangenen Wert festgelegt werden.
      Gr&ouml&szlig;ere Abweichungen werden dann ignoriert und f&uuml;hren zu einer Fehlermeldung im Logfile, wie z.B. dieser:<br>
      <code>SD_WS_TH_84 ERROR - Hum diff too large (old 60, new 68, diff 8)</code><br>
      Zus&auml;tzlich zum eingestellten Wert wird ein von der Differenz der Empfangszeiten abh&auml;ngiger Wert addiert.
      Dieser betr&auml;gt 1.0 % relative Feuchte pro Minute. Das bedeutet z.B. wenn eine Differenz von 8 eingestellt ist
      und der zeitliche Abstand des Empfangs der Nachrichten betr&auml;gt 3 Minuten, ist die maximal erlaubte Differenz 11.
      <br>Anstelle der Attribute <code>max-deviation-hum</code> und <code>max-deviation-temp</code> kann bei gutem Empfang des Sensors 
      auch das Attribut <code>doubleMsgCheck_IDs</code> des SIGNALduino verwendet werden. Dabei wird ein Update der Readings erst 
      ausgef&uuml;hrt, wenn mindestens zweimal die gleichen Werte empfangen wurden.
      <a name="end_max-deviation-hum"></a>
    </li><br>
    <li>max-deviation-temp<br>
      (Standard: 1, erlaubte Werte: 1,2,3,4,5,6,7,8,9,10,15,20,25,30,35,40,45,50)<br>
      <a name="max-deviation-temp"></a>
      Maximal erlaubte Abweichung der gemessenen Temperatur zum vorhergehenden Wert in Kelvin.<br>
      Erkl&auml;rung siehe Attribut "max-deviation-hum".
      <a name="end_max-deviation-temp"></a>
    </li><br>
    <li>model<br>
      <a name="model"></a>
      (Standard: other, zur Zeit unterst&uuml;tzte Sensoren: E0001PA, S522, TFA_30.3251.10, TX-EZ6)<br>
      Die Sensoren der "SD_WS_33 - Reihe" verwenden unterschiedliche Positionen f&uuml;r das Batterie-Bit und unterst&uuml;tzen verschiedene Readings. 
      Sollte das Batterie-Bit falsch erkannt werden (low statt ok), so kann man mit der Modelauswahl des Sensors das evtl. anpassen.<br>
      Bisher sind 3 Varianten bekannt. Alle Sensoren werden durch Autocreate als Model "other" angelegt. 
      Empfangen Sie einen Sensor vom Typ Conrad S522, Renkforce E0001PA oder TX-EZ6, so stellen Sie das jeweilige Modell f&uuml;r die richtige Verarbeitung der Readings ein.
      <br>
      Protokoll 85 (SD_WS_85_THW) dekodiert zwei verschiedene Sensortypen: TFA 30.3222.02 (Thermo-Hygro-Wind) und 30.3251.10 (Wind).
      Damit auch die Windrichtung bei dem Sensor TFA 30.3251.10 angezeigt wird, muss das Attribut auf diesen Wert "TFA_30.3251.10" gesetzt werden.
      <a name="end_model"></a>
    </li><br>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li><br>
    <li><a href="#showtime">showtime</a></li><br>
  </ul>
  <br>

  <a name="SD_WS Set"></a>
  <b>Set</b><br><br>
  <ul>
    <li>replaceBatteryForSec<br>
      (Nur verfügbar bei Geräten, bei deren SIGNALduinos das Attribut "longids" aktiviert ist.)
      <br><br>
      <code>replaceBatteryForSec &lt;Sekunden&gt;</code>
      <br><br>
      Versetzt das Gerät für <code>&lt;Sekunden&gt;</code> Sekunden in den Batteriewechselmodus. 
      Die erste unbekannte Adresse mit gleichem Protokoll, die empfangen wird, ersetzt die aktuelle Geräteadresse.
    </li>
  </ul><br>
</ul>

=end html_DE
=for :application/json;q=META.json 14_SD_WS.pm
{
  "abstract": "Supports various weather stations",
  "author": [
    "Sidey <>",
    "ralf9 <>"
  ],
  "x_fhem_maintainer": [
    "Sidey"
  ],
  "x_fhem_maintainer_github": [
    "Sidey79"
  ],
  "description": "The SD_WS module processes the messages from various environmental sensors received from an IO device (CUL, CUN, SIGNALDuino, SignalESP etc.)",
  "dynamic_config": 1,
  "keywords": [
    "fhem-sonstige-systeme",
    "fhem-hausautomations-systeme",
    "fhem-mod",
    "signalduino",
    "weather",
    "station",
    "sensor",
	  "Hama",
	  "TFA",
	  "Bresser"
  ],
  "license": [
    "GPL_2"
  ],
  "meta-spec": {
    "url": "https://metacpan.org/pod/CPAN::Meta::Spec",
    "version": 2
  },
  "name": "FHEM::SD_WS",
  "prereqs": {
    "runtime": {
      "requires": {
        "Carp": "0",
        "Digest:CRC": "0"
      }
    },
    "develop": {
      "requires": {
        "Carp": "0",
        "Digest:CRC": "0"
      }
    }
  },
  "release_status": "stable",
  "resources": {
    "bugtracker": {
      "web": "https://github.com/RFD-FHEM/RFFHEM/issues/"
    },
    "x_testData": [
      {
        "url": "https://raw.githubusercontent.com/RFD-FHEM/RFFHEM/master/t/FHEM/14_SD_WS/testData.json",
        "testname": "Testdata with SD_WS sensors"
      }
    ],
    "repository": {
      "x_master": {
        "type": "git",
        "url": "https://github.com/RFD-FHEM/RFFHEM.git",
        "web": "https://github.com/RFD-FHEM/RFFHEM/tree/master"
      },
      "type": "svn",
      "url": "https://svn.fhem.de/fhem",
      "web": "https://svn.fhem.de/trac/browser/trunk/fhem/FHEM/14_Hideki.pm",
      "x_branch": "trunk",
      "x_filepath": "fhem/FHEM/",
      "x_raw": "https://svn.fhem.de/trac/export/latest/trunk/fhem/FHEM/14_SD_WS.pm"
    },
    "x_support_community": {
      "board": "Sonstige Systeme",
      "boardId": "29",
      "cat": "FHEM - Hausautomations-Systeme",
      "description": "Sonstige Hausautomations-Systeme",
      "forum": "FHEM Forum",
      "rss": "https://forum.fhem.de/index.php?action=.xml;type=rss;board=29",
      "title": "FHEM Forum: Sonstige Systeme",
      "web": "https://forum.fhem.de/index.php/board,29.0.html"
    },
    "x_wiki": {
      "web": "https://wiki.fhem.de/wiki/SIGNALduino"
    }
  }
}
=end :application/json;q=META.json
=cut
