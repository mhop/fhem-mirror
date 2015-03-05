##############################################
# Thx to Himtronics
# http://www.mikrocontroller.net/topic/141831
# http://www.mikrocontroller.net/attachment/63563/km271-protokoll.txt
# Buderus documents: 63011376, 63011377, 63011378
# e.g. http://www.buderus.de/pdf/unterlagen/0063061377.pdf
# $Id$

package main;

use strict;
use warnings;
use Time::HiRes qw( time );

my %km271_sets = (
  "hk1_nachtsoll"   => {SET => "07006565%02x656565:0700%02x", # 0.5 celsius
                        OPT => ":slider,10,0.5,30,1"},
  "hk1_tagsoll"     => {SET => "0700656565%02x6565:0701%02x", # 0.5 celsius
                        OPT => ":slider,10,0.5,30,1"},
  "hk1_betriebsart" => {SET => "070065656565%02x65:0702%02x",
                        OPT => ""},
  "hk2_nachtsoll"   => {SET => "08006565%02x656565:0800%02x", # 0.5 celsius
                        OPT => ":slider,10,0.5,30,1"},
  "hk2_tagsoll"     => {SET => "0800656565%02x6565:0801%02x", # 0.5 celsius
                        OPT => ":slider,10,0.5,30,1"},
  "hk2_betriebsart" => {SET => "080065656565%02x65:0802%02x",
                        OPT => ""},

  "ww_soll"         => {SET => "0C07656565%02x6565:0c07%02x", # 1.0 celsius
                        OPT => ":slider,30,1,60"},
  "ww_betriebsart"  => {SET => "0C0E%02x6565656565:0c0e%02x",
                        OPT => ""},
  "ww_on-till"      => {SET => "0C0E%02x6565656565:0c0e%02x",
                        OPT => ""},
  "ww_zirkulation"  => {SET => "0C0E6565656565%02x:0c0f%02x",
                        OPT => ":slider,0,1,7"},

  "hk1_programm"    => {SET => "1100%02x6565656565",
                        OPT => ""},
  "hk1_timer"       => {SET => "11%s",
                        OPT => ""},
  "hk2_programm"    => {SET => "1200%02x6565656565",
                        OPT => ""},
  "hk2_timer"       => {SET => "12%s",
                        OPT => ""},

  "logmode"         => {SET => "EE0000",
                        OPT => ":noArg"}
);

my %km271_gets = (
  "l_fehler"               => ":noArg",
  "l_fehlerzeitpunkt"      => ":noArg",
  "l_fehleraktualisierung" => ":noArg"
);

# Message address:byte_offset in the message
# Attributes:
#   d:x (divide), p:x (add), bf:x (bitfield), a:x (array), ne (generate no event)
#   mb:x (multi-byte-message, x-bytes, low byte), s (signed value)
#   t (timer - special handling), eh (error history - special handling)
my %km271_tr = (
  "CFG_Sommer_ab"                   => "0000:1,p:-9,a:8",
  "CFG_HK1_Nachttemperatur"         => "0000:2,d:2",
  "cFG_HK1_Nachttemperatur"         => "0700:0,d:2",  # fake reading for internal notify
  "CFG_HK1_Tagtemperatur"           => "0000:3,d:2",
  "cFG_HK1_Tagtemperatur"           => "0701:0,d:2",  # fake reading for internal notify
  "CFG_HK1_Betriebsart"             => "0000:4,a:4",
  "cFG_HK1_Betriebsart"             => "0702:0,a:4",  # fake reading for internal notify
  "CFG_HK1_Max_Temperatur"          => "000e:2",
  "CFG_HK1_Auslegung"               => "000e:4",
  "CFG_HK1_Aufschalttemperatur"     => "0015:0,a:9",
  "CFG_Frost_ab"                    => "0015:2,s",
  "CFG_HK1_Absenkungsart"           => "001c:1,a:6",
  "CFG_HK1_Heizsystem"              => "001c:2,a:7",
  "CFG_HK1_Temperatur_Offset"       => "0031:3,s,d:2",
  "CFG_HK1_Fernbedienung"           => "0031:4,a:0",
  "CFG_HK2_Nachttemperatur"         => "0038:2,d:2",
  "cFG_HK2_Nachttemperatur"         => "0800:0,d:2",  # fake reading for internal notify
  "CFG_HK2_Tagtemperatur"           => "0038:3,d:2",
  "cFG_HK2_Tagtemperatur"           => "0801:0,d:2",  # fake reading for internal notify
  "CFG_HK2_Betriebsart"             => "0038:4,a:4",
  "cFG_HK2_Betriebsart"             => "0802:0,a:4",  # fake reading for internal notify
  "CFG_HK2_Max_Temperatur"          => "0046:2",
  "CFG_HK2_Auslegung"               => "0046:4",
  "CFG_HK2_Aufschalttemperatur"     => "004d:0,a:9",
  "CFG_WW_Vorrang"                  => "004d:1,a:0",
  "CFG_HK2_Absenkungsart"           => "0054:1,a:6",
  "CFG_HK2_Heizsystem"              => "0054:2,a:7",
  "CFG_HK2_Temperatur_Offset"       => "0069:3,s,d:2",
  "CFG_HK2_Fernbedienung"           => "0069:4,a:0",
  "CFG_Gebaeudeart"                 => "0070:2,p:1",
  "CFG_WW_Temperatur"               => "007e:3",
  "cFG_WW_Temperatur"               => "0c07:0",      # fake reading for internal notify
  "CFG_WW_Betriebsart"              => "0085:0,a:4",
  "cFG_WW_Betriebsart"              => "0c0e:0,a:4",  # fake reading for internal notify
  "CFG_WW_Aufbereitung"             => "0085:3,a:0",
  "CFG_WW_Zirkulation"              => "0085:5,a:11",
  "cFG_WW_Zirkulation"              => "0c0f:0,a:11",  # fake reading for internal notify
  "CFG_Sprache"                     => "0093:0,a:3",
  "CFG_Anzeige"                     => "0093:1,a:1",
  "CFG_Max_Kesseltemperatur"        => "009a:3",
  "CFG_Pumplogik"                   => "00a1:0",
  "CFG_Abgastemperaturschwelle"     => "00a1:5,p:-9,a:5",

  "PRG_HK1_Programm"                => "0100:0,a:2",
  "CFG_Urlaubstage"                 => "0100:3",
  "PRG_HK1_Timer01"                 => "0107:0,t",
  "PRG_HK1_Timer02"                 => "010e:0,t",
  "PRG_HK1_Timer03"                 => "0115:0,t",
  "PRG_HK1_Timer04"                 => "011c:0,t",
  "PRG_HK1_Timer05"                 => "0123:0,t",
  "PRG_HK1_Timer06"                 => "012a:0,t",
  "PRG_HK1_Timer07"                 => "0131:0,t",
  "PRG_HK1_Timer08"                 => "0138:0,t",
  "PRG_HK1_Timer09"                 => "013f:0,t",
  "PRG_HK1_Timer10"                 => "0146:0,t",
  "PRG_HK1_Timer11"                 => "014d:0,t",
  "PRG_HK1_Timer12"                 => "0154:0,t",
  "PRG_HK1_Timer13"                 => "015b:0,t",
  "PRG_HK1_Timer14"                 => "0162:0,t",
  "PRG_HK2_Programm"                => "0169:0,a:2",
  "PRG_HK2_Timer01"                 => "0170:0,t",
  "PRG_HK2_Timer02"                 => "0177:0,t",
  "PRG_HK2_Timer03"                 => "017e:0,t",
  "PRG_HK2_Timer04"                 => "0185:0,t",
  "PRG_HK2_Timer05"                 => "018c:0,t",
  "PRG_HK2_Timer06"                 => "0193:0,t",
  "PRG_HK2_Timer07"                 => "019a:0,t",
  "PRG_HK2_Timer08"                 => "01a1:0,t",
  "PRG_HK2_Timer09"                 => "01a8:0,t",
  "PRG_HK2_Timer10"                 => "01af:0,t",
  "PRG_HK2_Timer11"                 => "01b6:0,t",
  "PRG_HK2_Timer12"                 => "01bd:0,t",
  "PRG_HK2_Timer13"                 => "01c4:0,t",
  "PRG_HK2_Timer14"                 => "01cb:0,t",
  "CFG_Uhrzeit_Offset"              => "01e0:1,s",

  "ERR_Fehlerspeicher1"             => "0300:0,eh",
  "ERR_Fehlerspeicher2"             => "0307:0,eh",
  "ERR_Fehlerspeicher3"             => "030e:0,eh",
  "ERR_Fehlerspeicher4"             => "0315:0,eh",

  "HK1_Betriebswerte1"              => "8000:0,bf:0",
  "HK1_Betriebswerte2"              => "8001:0,bf:1",
  "HK1_Vorlaufsolltemperatur"       => "8002:0",
  "HK1_Vorlaufisttemperatur"        => "8003:0,ne",  # great part of all messages
  "HK1_Raumsolltemperatur"          => "8004:0,d:2",
  "HK1_Raumisttemperatur"           => "8005:0,d:2",
  "HK1_Einschaltoptimierung"        => "8006:0",
  "HK1_Ausschaltoptimierung"        => "8007:0",
  "HK1_Pumpe"                       => "8008:0",
  "HK1_Mischerstellung"             => "8009:0,ne",  # great part of all messages
  "HK1_Heizkennlinie_+10_Grad"      => "800c:0",
  "HK1_Heizkennlinie_0_Grad"        => "800d:0",
  "HK1_Heizkennlinie_-10_Grad"      => "800e:0",
  "HK2_Betriebswerte1"              => "8112:0,bf:0",
  "HK2_Betriebswerte2"              => "8113:0,bf:1",
  "HK2_Vorlaufsolltemperatur"       => "8114:0",
  "HK2_Vorlaufisttemperatur"        => "8115:0,ne",  # great part of all messages
  "HK2_Raumsolltemperatur"          => "8116:0,d:2",
  "HK2_Raumisttemperatur"           => "8117:0,d:2",
  "HK2_Einschaltoptimierung"        => "8118:0",
  "HK2_Ausschaltoptimierung"        => "8119:0",
  "HK2_Pumpe"                       => "811a:0",
  "HK2_Mischerstellung"             => "811b:0,ne",  # great part of all messages
  "HK2_Heizkennlinie_+10_Grad"      => "811e:0",
  "HK2_Heizkennlinie_0_Grad"        => "811f:0",
  "HK2_Heizkennlinie_-10_Grad"      => "8120:0",
  "WW_Betriebswerte1"               => "8424:0,bf:2",
  "WW_Betriebswerte2"               => "8425:0,bf:3",
  "WW_Solltemperatur"               => "8426:0",
  "WW_Isttemperatur"                => "8427:0",
  "WW_Einschaltoptimierung"         => "8428:0",
  "WW_Pumpentyp"                    => "8429:0,bf:5",
  "Kessel_Vorlaufsolltemperatur"    => "882a:0",
  "Kessel_Vorlaufisttemperatur"     => "882b:0,ne",  # great part of all messages
  "Brenner_Einschalttemperatur"     => "882c:0",
  "Brenner_Ausschalttemperatur"     => "882d:0",
  "Kessel_Integral1"                => "882e:0,ne",
  "Kessel_Integral"                 => "882f:0,mb:2,ne", # great part of all messages
  "Kessel_Fehler"                   => "8830:0,bf:6",
  "Kessel_Betrieb"                  => "8831:0,bf:4",
  "Brenner_Ansteuerung"             => "8832:0,a:10",
  "Abgastemperatur"                 => "8833:0",
  "Brenner_Mod_Stellglied"          => "8834:0",
  "Brenner_Laufzeit1_Minuten2"      => "8836:0",
  "Brenner_Laufzeit1_Minuten1"      => "8837:0",
  "Brenner_Laufzeit1_Minuten"       => "8838:0,mb:3",
  "Brenner_Laufzeit2_Minuten2"      => "8839:0",
  "Brenner_Laufzeit2_Minuten1"      => "883a:0",
  "Brenner_Laufzeit2_Minuten"       => "883b:0,mb:3",
  "Aussentemperatur"                => "893c:0,s",
  "Aussentemperatur_gedaempft"      => "893d:0,s",
  "Versionsnummer_VK"               => "893e:0",
  "Versionsnummer_NK"               => "893f:0",
  "Modulkennung"                    => "8940:0",

  "ERR_Alarmstatus"                 => "aa42:0,bf:7"
);

my %km271_rev;

my @km271_bitarrays = (
  # 0 - HK_Betriebswerte1
  [ "-", "Ausschaltoptimierung", "Einschaltoptimierung", "Automatik",
          "Warmwasservorrang", "Estrichtrocknung", "Ferien", "Frostschutz",
          "Manuell" ],
  # 1 - HK_Betriebswerte2
  [ "-", "Sommer", "Tag", "Keine Kommunikation mit FB", "FB fehlerhaft",
          "Fehler Vorlauffuehler", "Maximaler Vorlauf",
          "Externer Stoereingang", "Frei" ],
  # 2 - WW_Betriebswerte1
  [ "-", "Automatik", "Desinfektion", "Nachladung", "Ferien",
         "Fehler Desinfektion", "Fehler Fuehler", "Fehler WW bleibt kalt",
         "Fehler Anode" ],
  # 3 - WW_Betriebswerte2
  [ "-", "Laden", "Manuell", "Nachladen", "Ausschaltoptimierung",
         "Einschaltoptimierung", "Tag", "Warm", "Vorrang" ],
  # 4 - Kessel_Betrieb
  [ "-", "Abgastest", "Betrieb 1.Stufe", "Kesselschutz",
         "Unter Betrieb", "Leistung frei", "Leistung hoch", "Betrieb 2.Stufe", "Frei" ],
  # 5 - WW_Pumpentyp
  [ "-", "Ladepumpe", "Zirkulationspumpe", "Absenkung Solar",
         "Frei", "Frei", "Frei", "Frei", "Frei" ],
  # 6 - Kessel_Fehler
  [ "-", "Brennerstoerung", "Kesselfuehler", "Zusatzfuehler", "Kessel bleibt kalt",
        "Abgasfuehler", "Abgas ueber Grenzwert", "Sicherungskette ausgeloest", "Externe Stoerung" ],
  # 7 - Alarmstatus
  [ "-", "Abgasfuehler", "02", "Kesselvorlauffuehler", "08",
        "10", "20", "HK2-Vorlauffuehler", "80" ]
);

my @km271_arrays = (
  # 0 - CFG_Fernbedienung, CFG_WW_Vorrang, CFG_Warmwasser
  [ "Aus", "An" ],
  # 1 - CFG_Anzeige
  [ "Automatik", "Kessel", "Warmwasser", "Aussen" ],
  # 2 - CFG_Programm
  [ "Eigen", "Familie", "Frueh", "Spaet", "Vormittag", "Nachmittag",
    "Mittag", "Single", "Senior" ],
  # 3 - CFG_Sprache
  [ "DE", "FR", "IT", "NL", "EN", "PL" ],
  # 4 - CFG_Betriebsart
  [ "Nacht", "Tag", "Automatik" ],
  # 5 - CFG_Abgastemperaturschwelle
  [ "Aus","50","55","60","65","70","75","80","85","90","95","100","105",
    "110","115","120","125","130","135","140","145","150","155","160","165",
    "170","175","180","185","190","195","200","205","210","215","220","225",
    "230","235","240","245","250" ],
  # 6 - CFG_Absenkungsart
  [ "Abschalt","Reduziert","Raumhalt","Aussenhalt" ],
  # 7 - CFG_Heizsystem
  [ "Aus","Heizkoerper","-","Fussboden" ],
  # 8 - CFG_Sommer_ab
  [ "Sommer","10","11","12","13","14","15","16","17","18","19",
    "20","21","22","23","24","25","26","27","28","29","30","Winter" ],
  # 9 - CFG_Aufschalttemperatur
  [ "Aus","1","2","3","4","5","6","7","8","9","10" ],
  # 10 - Brenneransteuerung
  [ "Kessel aus", "1.Stufe an", "-", "-", "2.Stufe an bzw. Modulation frei" ],
  # 11 - CFG_Zirkulation
  [ "Aus","1","2","3","4","5","6","An" ]
);

# PRG_HK1_TimerXX, PRG_HK2_TimerXX
my %km271_days = (
  0x00  => "Mo",
  0x20  => "Di",
  0x40  => "Mi",
  0x60  => "Do",
  0x80  => "Fr",
  0xa0  => "Sa",
  0xc0  => "So"
);

my %km271_set_betriebsart = (
  "nacht"     => 0,
  "tag"       => 1,
  "automatik" => 2
);

# Used by set hk?_programm
my %km271_set_programm = (
  "eigen"      => 0,
  "familie"    => 1,
  "frueh"      => 2,
  "spaet"      => 3,
  "vormittag"  => 4,
  "nachmittag" => 5,
  "mittag"     => 6,
  "single"     => 7,
  "senior"     => 8
);

# Used by set hk?_timer
my %km271_set_day = (
  "mo"  => 0x00,
  "di"  => 0x20,
  "mi"  => 0x40,
  "do"  => 0x60,
  "fr"  => 0x80,
  "sa"  => 0xa0,
  "so"  => 0xc0
);

# Used by get last_error
my %km271_errormsg = (
   0 => "Kein Fehler",
   2 => "Aussenfuehler defekt",
   3 => "HK1-Vorlauffuehler defekt",
   4 => "HK2-Vorlauffuehler defekt",
   8 => "Warmwasserfuehler defekt",
   9 => "Warmwasser bleibt kalt",
  10 => "Stoerung thermische Desinfektion",
  11 => "HK1-Fernbedienung defekt",
  12 => "HK2-Fernbedienung defekt",
  15 => "Keine Kommunikation mit HK1-Fernbedienung",
  16 => "Keine Kommunikation mit HK2-Fernbedienung",
  20 => "Stoerung Brenner 1",
  24 => "Keine Verbindung mit Kessel 1",
  30 => "Interner Fehler Nr. 1",
  31 => "Interner Fehler Nr. 2",
  32 => "Interner Fehler Nr. 3",
  33 => "Interner Fehler Nr. 4",
  49 => "Kesselvorlauffuehler defekt",
  50 => "Kesselzusatzfuehler defekt",
  51 => "Kessel bleibt kalt",
  52 => "Stoerung Brenner",
  53 => "Stoerung Sicherheitskette",
  54 => "Externe Stoerung Kessel",
  55 => "Abgasfuehler defekt",
  56 => "Abgasgrenze ueberschritten",
  87 => "Ruecklauffuehler defekt",
  92 => "RESET"
);

#####################################
sub
KM271_Initialize($)
{
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

  $hash->{ReadFn}   = "KM271_Read";
  $hash->{ReadyFn}  = "KM271_Ready";

  $hash->{DefFn}    = "KM271_Define";
  $hash->{UndefFn}  = "KM271_Undef";
  $hash->{SetFn}    = "KM271_Set";
  $hash->{GetFn}    = "KM271_Get";
  $hash->{AttrFn}   = "KM271_Attr";
  $hash->{AttrList} = "do_not_notify:1,0 all_km271_events:1,0 ww_timermode:automatik,tag readingsFilter $readingFnAttributes";

  %km271_rev = ();
  foreach my $k (sort keys %km271_tr) {      # Reverse map
    my $v = $km271_tr{$k};
    my ($addr, $b) = split("[:,]", $v);
    $km271_rev{$addr}{$b} = $k;
  }

  my $optionList = join(",", sort keys %km271_set_betriebsart);
  $km271_sets{"hk1_betriebsart"}{OPT} = ":$optionList";
  $km271_sets{"hk2_betriebsart"}{OPT} = ":$optionList";
  $km271_sets{"ww_betriebsart"}{OPT} = ":$optionList";
  $optionList = join(",", sort keys %km271_set_programm);
  $km271_sets{"hk1_programm"}{OPT} = ":$optionList";
  $km271_sets{"hk2_programm"}{OPT} = ":$optionList";
}

#####################################
sub
KM271_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> KM271 [devicename|none]" if(@a != 3);

  DevIo_CloseDev($hash);
  my $name = $a[0];
  my $dev = $a[2];

  if($dev eq "none") {
    Log3 $name, 2, "$name: KM271 device is none, commands will be echoed only";
    return undef;
  }

  $hash->{DeviceName} = $dev;
  my @b = ();
  $hash->{SENDBUFFER} = \@b;
  # Internal hash for storing actual timing parameter of heater, populated by "logmode" command
  my %c = ();
  $hash->{PRG_TIMER} = \%c;
  # Internal array for storing the last 4 error states and timestamps
  my @d = ([0,0], [0,0], [0,0], [0,0]);
  $hash->{ERR_STATE} = \@d;

  my $ret = DevIo_OpenDev($hash, 0, "KM271_DoInit");
  return $ret;
}

#####################################
sub
KM271_Undef($$)
{
  my ($hash, $arg) = @_;
  DevIo_CloseDev($hash); 
  return undef;
}

#####################################
sub
KM271_Set($@)
{
  my ($hash, @a) = @_;
  return "\"set KM271\" needs at least an argument" if(@a < 2);
  my $name = shift @a;

  if(!defined($km271_sets{$a[0]})) {
    my $msg = "";
    foreach my $para (sort keys %km271_sets) {
      $msg .= " $para" . $km271_sets{$para}{OPT};
    }
    return "Unknown argument $a[0], choose one of" . $msg;
  }

  my $cmd = $km271_sets{$a[0]}{SET};
  my ($err, $hr, $min, $sec, $fn);
  my ($val, $numeric_val);
  if($cmd =~ m/%/) {
    return "\"set KM271 $a[0]\" needs at least one parameter" if(@a < 2);
    $val = $a[1];
    $numeric_val = ($val =~ m/^[.0-9]+$/);
  }

  if($a[0] =~ m/^hk.*soll$/) {
    return "Argument must be numeric (between 10 and 30)" if(!$numeric_val || $val < 10 || $val > 30);
    $val *= 2;
  }
  elsif($a[0] =~ m/^ww.*soll$/) {
    return "Argument must be numeric (between 30 and 60)" if(!$numeric_val || $val < 30 || $val > 60);
  }
  elsif($a[0] =~ m/_betriebsart$/) {
    $val = $km271_set_betriebsart{$val};
    return "Unknown parameter for $a[0], use one of " .
           join(" ", sort keys %km271_set_betriebsart) if(!defined($val));
  }
  elsif($a[0] =~ m/_programm$/) {
    $val = $km271_set_programm{$val};
    return "Unknown parameter for $a[0], use one of " .
           join(" ", sort keys %km271_set_programm) if(!defined($val));
  }
  elsif($a[0] =~ m/^ww.*-till$/) {	# WW on-till command
    ($err, $hr, $min, $sec, $fn) = GetTimeSpec($val);
    return $err if($err);

    my @lt = localtime;
    my $hms_till = sprintf("%02d:%02d:%02d", $hr, $min, $sec);
    my $hms_now = sprintf("%02d:%02d:%02d", $lt[2], $lt[1], $lt[0]);
    if($hms_now ge $hms_till) {
      Log3 $name, 1, "$name: ww_on-till won't switch as now $hms_now is later than till $hms_till";
      return "Won't switch as now is later than $hms_till";
    }

    my $tname = $name . "_ww_autoOff";
    CommandDelete(undef, $tname) if($defs{$tname});
    CommandDefine(undef, "$tname at $hms_till set $name ww_betriebsart nacht");
    $val = $km271_set_betriebsart{AttrVal($name, "ww_timermode", "tag")};
  }
  elsif($a[0] =~ m/^ww.*zirkulation$/) {
    return "Argument must be numeric (between 0 and 7)" if(!$numeric_val || $val < 0 || $val > 7);
  }
  elsif($a[0] =~ m/^hk.*timer$/) {  # Timer calculation
    return "\"set KM271 $a[0]\" needs typically 5 parameters (position on-day on-time off-day off-time)" if(@a < 3);
    $val = $a[1];
    $numeric_val = ($val =~ m/^[.0-9]+$/);
    # 42 slots for a timer, but each interval uses two of them (on and off)
    return "Position must be numeric (between 1 and 21)" if(!$numeric_val || $val < 1 || $val > 21);
    my $pos = $val;
    my $offval;
    if($a[2] eq "delete") {
      # Delete the interval
      $offval = "c290";   # Code for not used
      $val = $offval;
    } else {
      # Set interval: more arguments are needed
      return "\"set KM271 $a[0]\" needs at least 5 parameters (position day on-time day off-time)" if(@a < 6);
      my $offday = $km271_set_day{$a[4]};
      return "Unknown day, use one of " .
             join(" ", sort keys %km271_set_day) if(!defined($offday));

      # Time validation off-time
      ($err, $hr, $min, $sec, $fn) = GetTimeSpec($a[5]);
      return $err if($err);

      # Calculate off-day and -time (unit: 10 min) for heater
      $offval = sprintf("%02x%02x", $offday, int(($hr*60 + $min) / 10));

      my $onday = $km271_set_day{$a[2]};
      return "Unknown day, use one of " .
             join(" ", sort keys %km271_set_day) if(!defined($onday));

      # Time validation on-time
      ($err, $hr, $min, $sec, $fn) = GetTimeSpec($a[3]);
      return $err if($err);

      # Calculate on-day and time (unit: 10 min) for heater
      $val = sprintf("%02x%02x", $onday | 0x01, int(($hr*60 + $min) / 10));

      return "On- and off timepoints must not be identical" if(substr($val, 2, 2) eq substr($offval, 2, 2) && $onday == $offday);
    }
    # Calculate offsets for command and internal timer hash
    my $km271Timer = $hash->{PRG_TIMER};
    my $offset = int(($pos*2 + 1)/3)*7;
    my $keyoffset = $offset + ($a[0] =~ m/^hk1/ ? 0 : 15)*7;
    my $key = sprintf("01%02x", $keyoffset);

    # Are two updates needed (interval is spread over two lines)?
    if(($pos + 1) % 3 == 0) {
      my $key2 = sprintf("01%02x", $keyoffset + 7);
      return "Internal timer-hash is not populated, use logmode command and try again later"
             if(!defined($km271Timer->{$key}{0}) || !defined($km271Timer->{$key}{1}) || !defined($km271Timer->{$key2}{1}) || !defined($km271Timer->{$key2}{2}));

      # Check if update for key2 is needed
	   if(defined($km271Timer->{$key2}{0}) && $km271Timer->{$key2}{0} eq $offval) {
	     Log3 $name, 5, "$name: Update for second timer-part not needed";
	   } else {
        # Update internal hash
        $km271Timer->{$key2}{0} = $offval;
        $offval .= $km271Timer->{$key2}{1} . $km271Timer->{$key2}{2};
        # Dirty trick: Changes of the timer are not notified by the heater, so internal notification is added after the colon
        $offval = sprintf("%02x%s:%s%s", $offset + 7, $offval, $key2, $offval);
        # Push first command
        push @{$hash->{SENDBUFFER}}, sprintf($cmd, $offval);
	   }
	   # Check if update for key is needed
	   if(defined($km271Timer->{$key}{2}) && $km271Timer->{$key}{2} eq $val) {
	     Log3 $name, 5, "$name: Update for first timer-part not needed";
	     goto END_SET;
	   } else {
        # Update internal hash
        $km271Timer->{$key}{2} = $val;
	   }
	 } else {
      # Only one update needed
      if($pos % 3 == 1) {
        return "Internal timer-hash is not populated, use logmode command and try again later" if(!defined($km271Timer->{$key}{2}));

        # Check if update for key is needed
	     if(defined($km271Timer->{$key}{0}) && defined($km271Timer->{$key}{1}) && $km271Timer->{$key}{0} eq $val && $km271Timer->{$key}{1} eq $offval) {
          Log3 $name, 5, "$name: Update for timer not needed";
          goto END_SET;
        } else {
          # Update internal hash
          $km271Timer->{$key}{0} = $val;
          $km271Timer->{$key}{1} = $offval;
		  }
      } else {
        return "Internal timer-hash is not populated, use logmode command and try again later" if(!defined($km271Timer->{$key}{0}));

	     # Check if update for key is needed
	     if(defined($km271Timer->{$key}{1}) && defined($km271Timer->{$key}{2}) && $km271Timer->{$key}{1} eq $val && $km271Timer->{$key}{2} eq $offval) {
	       Log3 $name, 5, "$name: Update for timer not needed";
	       goto END_SET;
	     } else {
          # Update internal hash
          $km271Timer->{$key}{1} = $val;
          $km271Timer->{$key}{2} = $offval;
		  }
      }
    }
    $val = $km271Timer->{$key}{0} . $km271Timer->{$key}{1} . $km271Timer->{$key}{2};
    # Dirty trick: Changes of the timer are not notified by the heater, so internal notification is added after the colon
    $val = sprintf("%02x%s:%s%s", $offset, $val, $key, $val);
  }
  my $data = sprintf($cmd, $val, $val);
  push @{$hash->{SENDBUFFER}}, $data;

  END_SET:
  Log3 $name, 3, "$name: set " . join(" ", @a);

  if(!exists($hash->{WAITING}) && !exists($hash->{DATASENT})) {
    DevIo_DoSimpleRead($hash);
    DevIo_SimpleWrite($hash, "02", 1);
  }
  return undef;
}

#####################################
sub
KM271_Get($@)
{
  my ($hash, @a) = @_;
  return "\"get KM271\" needs at least an argument" if(@a < 2);
  my $name = shift @a;
  my $para = shift @a;

  if(!defined($km271_gets{$para})) {
    my $msg = "";
    foreach my $p (sort keys %km271_gets) {
      $msg .= " $p" . $km271_gets{$p};
    }
    return "Unknown argument $para, choose one of" . $msg;
  }

  my $lastTimestamp = 0;
  if($para eq "l_fehler") {
    my $lastError = 0;
    foreach my $row (0..@{$hash->{ERR_STATE}}-1) {
      $lastError = ${$hash->{ERR_STATE}}[$row][0];
      last if($lastError);
    }
    my $errorMsg = $km271_errormsg{$lastError};
    $errorMsg = "Unbekannter Fehler" if(!defined($errorMsg));
    return sprintf("%02d: %s", $lastError, $errorMsg);
  }
  elsif($para eq "l_fehlerzeitpunkt") {
    foreach my $row (0..@{$hash->{ERR_STATE}}-1) {
      if(${$hash->{ERR_STATE}}[$row][0]) {
        $lastTimestamp = ${$hash->{ERR_STATE}}[$row][1];
        last;
      }
    }
    return $lastTimestamp;
  }
  elsif($para eq "l_fehleraktualisierung") {
    foreach my $row (0..@{$hash->{ERR_STATE}}-1) {
      my $lts = ${$hash->{ERR_STATE}}[$row][1];
      $lastTimestamp = $lts if($lts > $lastTimestamp);
    }
    return $lastTimestamp;
  }

  return undef;
}

#####################################
# Called from the global loop, when the select for hash->{FD} reports data
sub
KM271_Read($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my ($data, $crc);

  my $buf = DevIo_SimpleRead($hash);
  return "" if(!defined($buf));

  $buf = unpack('H*', $buf);
  Log3 $name, 5, "$name: KM271RAW <$buf>";

  # Check, if we are waiting for a message from the heater
  if(exists($hash->{WAITING})) {
    # After timeout get out of waiting mode
    delete($hash->{WAITING}) if(time - $hash->{WAITING} > 2.5);
  } else {
    # Send data or waiting for acknowlegde
    if(@{$hash->{SENDBUFFER}} || $hash->{DATASENT}) {
      if($buf eq "10") {
        if($hash->{DATASENT}) {
          delete($hash->{DATASENT});
          delete($hash->{RETRYCOUNT});
          # Delete the command from the list
          shift @{$hash->{SENDBUFFER}};
          if($hash->{NOTIFY}) {
            $data = $hash->{NOTIFY};
            delete($hash->{NOTIFY});
            goto INTERNAL_NOTIFY;                             # Timer changes are not reflected by the heater
          }
          DevIo_SimpleWrite($hash, "02", 1) if(@{$hash->{SENDBUFFER}});
        } else {
          # Delete the command only after receiving ACK
          $data = shift @{$hash->{SENDBUFFER}};
          unshift @{$hash->{SENDBUFFER}}, $data;
          # Dirty trick: separate notify message after the colon
          my @dataList = split(":", $data);
          $data = $dataList[0];
          $data = KM271_encode($data);
          $data .= "1003";
          $crc = KM271_crc($data);
          $data .= $crc;
          $hash->{DATASENT} = $data;
          $hash->{RETRYCOUNT} = 0;
          if(@dataList > 1) {
            # Set notify message
            $hash->{NOTIFY} = $dataList[1];
          } else {
            delete($hash->{NOTIFY});
          }
          DevIo_SimpleWrite($hash, $data, 1);  # Send the data
        }
      } else {
        if($hash->{DATASENT}) {
          if($buf eq "15") {
            Log3 $name, 2, "$name: NAK received";            # NACK from the KM271
          } else {
            Log3 $name, 2, "$name: Bogus data after sending packet <$buf>";  # Strange response from the KM271
          }
          # Start all over again
          if(++$hash->{RETRYCOUNT} > 3) {
            # Abort sending the actual command
            Log3 $name, 1, "$name: Sending <$hash->{DATASENT}> aborted and not successful!";
            shift @{$hash->{SENDBUFFER}};
            delete($hash->{RETRYCOUNT});
          } else {
            Log3 $name, 2, "$name: Sending attempt for <$hash->{DATASENT}> failed, retrying";
          }
          delete($hash->{DATASENT});
          delete($hash->{NOTIFY});
          DevIo_SimpleWrite($hash, "02", 1) if(@{$hash->{SENDBUFFER}});
        } else {
          DevIo_SimpleWrite($hash, "02", 1);
        }
      }
    } else {
      if($buf eq "02") {                       # KM271 Wants to send
        DevIo_SimpleWrite($hash, "10", 1);      # We are ready
        $hash->{PARTIAL} = "";
        $hash->{WAITING} = time;
      }
    }
    return;
  }

  $hash->{PARTIAL} .= $buf;
  return if($hash->{PARTIAL} !~ m/^(.*)1003(..)$/);
  ($data, $crc) = ($1, $2);
  $hash->{PARTIAL} = "";
  delete($hash->{WAITING});

  if(KM271_crc($data . "1003") ne $crc) {
    Log3 $name, 1, "$name: Wrong CRC in datapacket <$crc>";
    DevIo_SimpleWrite($hash, "15", 1); # NAK
    DevIo_SimpleWrite($hash, "02", 1) if(@{$hash->{SENDBUFFER}}); # Want to send
    return;
  }

  DevIo_SimpleWrite($hash, "10", 1);       # ACK, Data received ok
  $data = KM271_decode($data);

  INTERNAL_NOTIFY:
  DevIo_SimpleWrite($hash, "02", 1) if(@{$hash->{SENDBUFFER}}); # Want to send

  if($data !~ m/^(....)(.*)/) {
    Log3 $name, 2, "$name: Bogus message <$data>";
    return;
  }

  ######################################
  # Analyze the data
  my ($fn, $arg) = ($1, $2);
  my $msghash = $km271_rev{$fn};
  my $all_events = AttrVal($name, "all_km271_events", "");

  if($msghash) {
    my $km271Timer = $hash->{PRG_TIMER};
    foreach my $off (keys %{$msghash}) {

      my $key = $msghash->{$off};
      my $val = hex(substr($arg, $off*2, 2));
      my $ntfy = 1;
      my @postprocessing = split(",", $km271_tr{$key});
      shift @postprocessing;
      while(@postprocessing) {
        my ($f,$farg) = split(":", shift @postprocessing);

           if($f eq "d")  { $val /= $farg; }
        elsif($f eq "p")  { $val += $farg; }
        elsif($f eq "ne") { $ntfy = $all_events; }
        elsif($f eq "s")  { $val = $val-256 if($val > 127); }
        elsif($f eq "bf") { $val = KM271_setbits($val, $farg); }
        elsif($f eq "a")  { $val = $km271_arrays[$farg][$val]; }
        elsif($f eq "mb") {
          $val += ReadingsVal($name, $key."1", 0) * 256;
          $val += ReadingsVal($name, $key."2", 0) * 65536 if($farg == 3); }
        elsif($f eq "t")  { $val = sprintf("%s | %s | %s", KM271_setprg($val, hex(substr($arg, ($off+1)*2, 2)))
                                                         , KM271_setprg(hex(substr($arg, ($off+2)*2, 2)), hex(substr($arg, ($off+3)*2, 2)))
                                                         , KM271_setprg(hex(substr($arg, ($off+4)*2, 2)), hex(substr($arg, ($off+5)*2, 2)))); 
                            # Fill internal timer hash
                            $km271Timer->{$fn}{0} = substr($arg, 0, 4);
                            $km271Timer->{$fn}{1} = substr($arg, 4, 4);
                            $km271Timer->{$fn}{2} = substr($arg, 8, 4); }
        elsif($f eq "eh") { $val = KM271_seterror($hash->{ERR_STATE}, substr($key, -1) -1, $arg); }
      }
      $key = ucfirst($key);   # Hack to match the original and the fake reading
      KM271_SetReading($hash, $key, $val, $ntfy);
    }

  } elsif($fn eq "0400") {
    KM271_SetReading($hash, "NoData", $arg, 0);

  } elsif($all_events) {
    KM271_SetReading($hash, "UNKNOWN_$fn", $data, 1);
  }
}

#####################################
sub
KM271_Ready($)
{
  my ($hash) = @_;

  return DevIo_OpenDev($hash, 1, undef) if($hash->{STATE} eq "disconnected");

  # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  return ($InBytes>0);
}

#####################################
sub
KM271_Attr(@)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;
  # $cmd can be "del" or "set"
  # $name is device name
  # attrName and attrVal are Attribute name and value
  if($cmd eq 'set') {
    if($attrName eq 'ww_timermode') {
      return "Invalid $attrName <$attrVal>" if(!$km271_set_betriebsart{$attrVal});
    } elsif($attrName eq 'readingsFilter') {
      eval {qr/$attrVal/};
      if($@) {
        Log3 $name, 1, "$name: Invalid Regex for $attrName <$attrVal> '$@'";
        return "Invalid Regex for $attrName <$attrVal>";
      }
    }
  }
  return undef;
}

#####################################
sub
KM271_DoInit($)
{
  my ($hash) = @_;
  push @{$hash->{SENDBUFFER}}, $km271_sets{"logmode"}{SET};
  DevIo_DoSimpleRead($hash);
  DevIo_SimpleWrite($hash, "02", 1);      # STX
  return undef;
}

#####################################
sub
KM271_setbits($$)
{
  my ($val, $arridx) = @_;
  my @ret;
  for(my $idx = 1; $idx <= 8; $idx++) {
    push(@ret, $km271_bitarrays[$arridx][$idx]) if($val & (1<<($idx-1)));
  }
  return $km271_bitarrays[$arridx][0] if(!int(@ret));
  return join(",", @ret);
}

#####################################
sub
KM271_setprg($$)
{
  my ($val, $time) = @_;
  my $ret = "-";
  my $switch = $val & 0x0f;
  if($switch < 2) {
    $ret = $switch == 0 ? "Aus: " : "An: ";
    $ret .= $km271_days{$val & 0xf0};
    $ret .= sprintf(" %02d:%02d", int($time / 6), ($time % 6)*10);
  }
  return $ret;
}

#####################################
sub
KM271_seterror($$$)
{
  my ($errState, $slot, $val) = @_;
  my $error = hex(substr($val, 0, 2));
  my $ret = "Kein Fehler";
  my $timestamp = 0;
  if($error) {
    my $hr = hex(substr($val, 2, 2));
    my $mi = hex(substr($val, 4, 2));
    my $days = hex(substr($val, 6, 2));
    $ret = sprintf("Code %02d (+): %02d:%02dUhr vor ", $error, $hr, $mi);
    my $hr2 = hex(substr($val, 8, 2));
    # get actual time
    $timestamp = int(time);
    my @ts = localtime($timestamp);
    if($hr2 == 0xff) {
      $ret .= sprintf("%d Tagen | Fehler noch offen", $days);
      # time calculation without DateTime module
      $timestamp -= (($ts[2] - $hr)*60 + $ts[1] - $mi)*60 + $days*86400;
    } else {
      $mi = hex(substr($val, 10, 2));
      my $days2 = hex(substr($val, 12, 2));
      $ret .= sprintf("%d Tagen | (-): %02d:%02dUhr vor %d Tagen", $days + $days2, $hr2, $mi, $days2);
      # time calculation without DateTime module
      $timestamp -= (($ts[2] - $hr2)*60 + $ts[1] - $mi)*60 + $days2*86400;
      $error = 0;
    }
  }
  if($slot < 4 && $slot >= 0) {
    $errState->[$slot][0] = $error;
    $errState->[$slot][1] = $timestamp;
  }
  return $ret;
}

#####################################
# Replacement for regular expression - s/10/1010/g - which works wrong for "0101"
sub
KM271_encode($)
{
  my $in = shift;
  my $out = '';
  foreach my $a (split("", pack('H*', $in))) {
    my $c = sprintf("%02x", ord($a));
    $c =~ s/10/1010/g;
    $out .= $c;
  }
  return $out;
}

#####################################
# Replacement for regular expression - s/1010/10/g - which works wrong for "010101"
sub
KM271_decode($)
{
  my $in = shift;
  my $out = '';
  my $flag = 0;
  foreach my $a (split("", pack('H*', $in))) {
    my $c = sprintf("%02x", ord($a));
    if($c eq "10") {
      if($flag) {
        $flag = 0;
        $c = '';
      } else {
        $flag = 1;
      }
    } else {
      $flag = 0;
    }
    $out .= $c;
  }
  return $out;
}

#####################################
sub
KM271_crc($)
{
  my $in = shift;
  my $x = 0;
  foreach my $a (split("", pack('H*', $in))) {
    $x ^= ord($a);
  }
  return sprintf("%02x", $x);
}

#####################################
sub
KM271_SetReading($$$$)
{
  my ($hash, $key, $val, $ntfy) = @_;
  my $name = $hash->{NAME};
  my $filter = AttrVal($name, 'readingsFilter', '');
  return if($filter && $key !~ m/$filter/s);

  Log3 $name, 4, "$name: $key $val" if($key ne 'NoData');
  readingsSingleUpdate($hash, $key, $val, $ntfy);
}

1;

=pod
=begin html

<a name="KM271"></a>
<h3>KM271</h3>
<ul>
  KM271 is the name of the communication device for the Buderus Logamatic 2105
  or 2107 heating controller. It is connected via a serial line to the fhem
  computer. The fhem module sets the communication device into log-mode, which
  then will generate an event on change of the inner parameters. There are
  about 20.000 events a day, the FHEM module ignores about 90% of them, if the
  <a href="#all_km271_events">all_km271_events</a> attribute is not set.<br>
  <br><br>

  Note: this module requires the Device::SerialPort or Win32::SerialPort module.
  <br><br>

  <a name="KM271define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; KM271 &lt;serial-device-name&gt;</code>
    <br><br>
    Example:
    <ul>
      <code>define KM271 KM271 /dev  tyS0@2400</code><br>
    </ul>
  </ul>
  <br>

  <a name="KM271set"></a>
  <b>Set</b>
  <ul>
    <code>set KM271 &lt;param&gt; [&lt;value&gt; [&lt;values&gt;]]</code><br><br>
    where param is one of:
    <ul>
      <li>hk1_tagsoll &lt;temp&gt;<br>
          sets the by day temperature for heating circuit 1<br>
          0.5 celsius resolution - temperature between 10 and 30 celsius</li>
      <li>hk2_tagsoll &lt;temp&gt;<br>
          sets the by day temperature for heating circuit 2<br>
          (see above)</li>
      <li>hk1_nachtsoll &lt;temp&gt;<br>
          sets the by night temperature for heating circuit 1<br>
          (see above)</li>
      <li>hk2_nachtsoll &lt;temp&gt;<br>
          sets the by night temperature for heating circuit 2<br>
          (see above)</li>
      <li>hk1_betriebsart [automatik|nacht|tag]<br>
          sets the working mode for heating circuit 1<br>
          <ul>
            <li>automatik: the timer program is active and the summer configuration is in effect</li>
            <li>nacht: manual by night working mode, no timer program is in effect</li>
            <li>tag: manual by day working mode, no timer program is in effect</li>
          </ul></li>
      <li>hk2_betriebsart [automatik|nacht|tag]<br>
          sets the working mode for heating circuit 2<br>
          (see above)</li>
      <li>ww_soll &lt;temp&gt;<br>
          sets the hot water temperature<br>
          1.0 celsius resolution - temperature between 30 and 60 celsius</li>
      <li>ww_betriebsart [automatik|nacht|tag]<br>
          sets the working mode for hot water<br>
          <ul>
            <li>automatik: hot water production according to the working modes of both heating circuits</li>
            <li>nacht: no hot water at all</li>
            <li>tag: manual permanent hot water</li>
          </ul></li>
      <li>ww_on-till [localtime]<br>
          start hot water production till the given time is reached<br>
          localtime must have the format HH:MM[:SS]<br>
          ww_betriebsart is set according to the attribut ww_timermode. For switching-off hot water a single one-time at command is automatically generated which will set ww_betriebsart back to nacht</li>
      <li>ww_zirkulation [count]<br>
          count pumping phases for hot water circulation per hour<br>
          count must be between 0 and 7 with special meaning for<br>
          <ul>
            <li>0: no circulation at all</li>
            <li>7: circulation is always on</li>
          </ul></li>
      <li>hk1_programm [eigen|familie|frueh|spaet|vormittag|nachmittag|mittag|single|senior]<br>
          sets the timer program for heating circuit 1<br>
          <ul>
            <li>eigen: the custom program defined by the user (see below) is used</li>
            <li>all others: predefined programs from Buderus for various situations (see Buderus manual for details)</li>
          </ul></li>
      <li>hk2_programm [eigen|familie|frueh|spaet|vormittag|nachmittag|mittag|single|senior]<br>
          sets the timer program for heating circuit 2<br>
          (see above)</li>
      <li>hk1_timer [&lt;position&gt; delete|&lt;position&gt; &lt;on-day&gt; &lt;on-time&gt; &lt;off-day&gt; &lt;off-time&gt;]<br>
          sets (or deactivates) a by day working mode time interval for the custom program of heating circuit 1<br>
          <ul>
            <li>position: addresses a slot of the custom timer program and must be between 1 and 21<br>
                The slot will be set to the interval specified by the following on- and off-timepoints or is deactivated when the next argument is <b>delete</b>.</li>
            <li>on-day: first part of the on-timepoint<br>
                valid arguments are [mo|di|mi|do|fr|sa|so]</li>
            <li>on-time: second part of the on-timepoint<br>
                valid arguments have the format HH:MM (supported resolution: 10 min)</li>
            <li>off-day: first part of the off-timepoint<br>
                (see above)</li>
            <li>off-time: second part of the off-timepoint<br>
                valid arguments have the format HH:MM (supported resolution: 10 min)</li>
          </ul>
          As the on-timepoint is reached, the heating circuit is switched to by day working mode and when the off-timepoint is attained, the circuit falls back to by night working mode.
          A program can be build up by chaining up to 21 of these intervals. They are ordered by the position argument. There's no behind the scene magic that will automatically consolidate the list.
          The consistency of the program is in the responsibility of the user.
          <br><br>
          Example:
          <ul>
            <code>set KM271 hk1_timer 1 mo 06:30 mo 08:20</code><br>
          </ul><br>
          This will toogle the by day working mode every Monday at 6:30 and will fall back to by night working mode at 8:20 the same day.</li>
      <li>hk2_timer [&lt;position&gt; delete|&lt;position&gt; &lt;on-day&gt; &lt;on-time&gt; &lt;off-day&gt; &lt;off-time&gt;]<br>
          sets (or deactivates) a by day working mode time interval for the custom program of heating circuit 2<br>
          (see above)</li>
      <li>logmode<br>set to logmode / request all readings again</li>
    </ul>
  </ul>
  <br>

  <a name="KM271get"></a>
  <b>Get</b>
  <ul>
    <code>get KM271 &lt;param&gt;</code><br><br>
    where param is one of:
    <ul>
      <li>l_fehler<br>
          gets the latest active error (code and message)</li>
      <li>l_fehlerzeitpunkt<br>
          gets the timestamp, when the latest active error occured (format of Perl-function 'time')</li>
      <li>l_fehleraktualisierung<br>
          gets the timestamp, of the latest update of an error status (format of Perl-function 'time')</li>
    </ul>
  </ul>
  <br>

  <a name="KM271attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <a name="all_km271_events"></a>
    <li>all_km271_events<br>
        If this attribute is set to 1, do not ignore following events:<br>
        HK1_Vorlaufisttemperatur, HK1_Mischerstellung, HK2_Vorlaufisttemperatur, HK2_Mischerstellung,
        Kessel_Vorlaufisttemperatur, Kessel_Integral, Kessel_Integral1<br>
        These events account for ca. 92% of all events.<br>
        All UNKNOWN events are ignored too, most of them were only seen
        directly after setting the device into logmode.
        </li>
    <a name="ww_timermode"></a>
    <li>ww_timermode [automatik|tag]<br>
        Defines the working mode for the ww_on-till command (default is tag).<br>
        ww_on-till will set the ww_betriebsart of the heater according to this attribute.
        </li>
    <a name="readingsFilter"></a>
    <li>readingsFilter<br>
        Regular expression for selection of desired readings.<br>
        Only readings which will match the regular expression will be used. All other readings are
        suppressed in the device and even in the logfile.
        </li>
  </ul>
  <br>


  <a name="KM271events"></a>
  <b>Generated events:</b>
  <ul>
    <li>Abgastemperatur</li>
    <li>Aussentemperatur</li>
    <li>Aussentemperatur_gedaempft</li>
    <li>Brenner_Ansteuerung</li>
    <li>Brenner_Ausschalttemperatur</li>
    <li>Brenner_Einschalttemperatur</li>
    <li>Brenner_Laufzeit1_Minuten2</li>
    <li>Brenner_Laufzeit1_Minuten1</li>
    <li>Brenner_Laufzeit1_Minuten</li>
    <li>Brenner_Laufzeit2_Minuten2</li>
    <li>Brenner_Laufzeit2_Minuten1</li>
    <li>Brenner_Laufzeit2_Minuten</li>
    <li>Brenner_Mod_Stellglied</li>
    <li>ERR_Fehlerspeicher1</li>
    <li>ERR_Fehlerspeicher2</li>
    <li>ERR_Fehlerspeicher3</li>
    <li>ERR_Fehlerspeicher4</li>
    <li>ERR_Alarmstatus</li>
    <li>HK1_Ausschaltoptimierung</li>
    <li>HK1_Betriebswerte1</li>
    <li>HK1_Betriebswerte2</li>
    <li>HK1_Einschaltoptimierung</li>
    <li>HK1_Heizkennlinie_+10_Grad</li>
    <li>HK1_Heizkennlinie_-10_Grad</li>
    <li>HK1_Heizkennlinie_0_Grad</li>
    <li>HK1_Mischerstellung</li>
    <li>HK1_Pumpe</li>
    <li>HK1_Raumisttemperatur</li>
    <li>HK1_Raumsolltemperatur</li>
    <li>HK1_Vorlaufisttemperatur</li>
    <li>HK1_Vorlaufsolltemperatur</li>
    <li>HK2_Ausschaltoptimierung</li>
    <li>HK2_Betriebswerte1</li>
    <li>HK2_Betriebswerte2</li>
    <li>HK2_Einschaltoptimierung</li>
    <li>HK2_Heizkennlinie_+10_Grad</li>
    <li>HK2_Heizkennlinie_-10_Grad</li>
    <li>HK2_Heizkennlinie_0_Grad</li>
    <li>HK2_Mischerstellung</li>
    <li>HK2_Pumpe</li>
    <li>HK2_Raumisttemperatur</li>
    <li>HK2_Raumsolltemperatur</li>
    <li>HK2_Vorlaufisttemperatur</li>
    <li>HK2_Vorlaufsolltemperatur</li>
    <li>Kessel_Betrieb</li>
    <li>Kessel_Fehler</li>
    <li>Kessel_Integral</li>
    <li>Kessel_Integral1</li>
    <li>Kessel_Vorlaufisttemperatur</li>
    <li>Kessel_Vorlaufsolltemperatur</li>
    <li>Modulkennung</li>
    <li>NoData</li>
    <li>Versionsnummer_NK</li>
    <li>Versionsnummer_VK</li>
    <li>WW_Betriebswerte1</li>
    <li>WW_Betriebswerte2</li>
    <li>WW_Einschaltoptimierung</li>
    <li>WW_Isttemperatur</li>
    <li>WW_Pumpentyp</li>
    <li>WW_Solltemperatur</li>
  </ul>
  <br>
  As I cannot explain all the values, I logged data for a period and plotted
  each received value in the following logs:
    <ul>
      <li><a href="km271/km271_Aussentemperatur.png">Aussentemperatur</a></li>
      <li><a href="km271/km271_Betriebswerte.png">Betriebswerte</a></li>
      <li><a href="km271/km271_Brenneransteuerung.png">Brenneransteuerung</a></li>
      <li><a href="km271/km271_Brennerlaufzeit.png">Brennerlaufzeit</a></li>
      <li><a href="km271/km271_Brennerschalttemperatur.png">Brennerschalttemperatur</a></li>
      <li><a href="km271/km271_Heizkennlinie.png">Heizkennlinie</a></li>
      <li><a href="km271/km271_Kesselbetrieb.png">Kesselbetrieb</a></li>
      <li><a href="km271/km271_Kesselintegral.png">Kesselintegral</a></li>
      <li><a href="km271/km271_Ladepumpe.png">Ladepumpe</a></li>
      <li><a href="km271/km271_Raumsolltemperatur_HK1.png">Raumsolltemperatur_HK1</a></li>
      <li><a href="km271/km271_Vorlauftemperatur.png">Vorlauftemperatur</a></li>
      <li><a href="km271/km271_Warmwasser.png">Warmwasser</a></li>
    </ul>
  All of these events are reported directly after initialization (or after
  requesting logmode), along with some 60 configuration records (6byte long
  each). Most parameters from these records are reverse engeneered, they
  all start with CFG_ for configuration and PRG_ for timer program information.
  </ul>

=end html
=cut
