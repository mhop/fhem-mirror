##############################################
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

sub KM271_Read($);
sub KM271_Ready($);
sub KM271_OpenDev($);
sub KM271_CloseDev($);
sub KM271_SimpleWrite(@);
sub KM271_SimpleRead($);
sub KM271_crc($);
sub KM271_setbits($$);
sub KM271_Reading($$);

my %sets = (
);

my $stx = pack('H*', "02");
my $dle = pack('H*', "10");
my $etx = pack('H*', "03");
my $nak = pack('H*', "15");
my $logmode = pack('H*', "EE00001003FD");

# Thx to Himtronics
# http://www.mikrocontroller.net/topic/141831
# http://www.mikrocontroller.net/attachment/63563/km271-protokoll.txt
# Buderus documents: 63011376, 63011377, 63011378
# http://www.buderus.de/pdf/unterlagen/0063061377.pdf
my %km271_trhash =
(
  "8000" =>  'Betriebswerte_1_HK1',             # 76, 4 [repeat]
  "8001" =>  'Betriebswerte_2_HK1',             # 0 (22:33), 2 (7:33)
  "8002" =>  'Vorlaufsolltemperatur_HK1',       # 50-65
  "8003" =>  'Vorlaufisttemperatur_HK1',        # Schwingt um soll herum
  "8004" =>  'Raumsolltemperatur_HK1',          # 34 (22:33) 42 (7:33)
  "8005" =>  'Raumisttemperatur_HK1',
  "8006" =>  'Einschaltoptimierungszeit_HK1',
  "8007" =>  'Ausschaltoptimierungszeit_HK1',
  "8008" =>  'Pumpenleistung_HK1',              # 0/100 == Ladepumpe
  "8009" =>  'Mischerstellung_HK1',
  "800a" =>  'nicht_belegt',
  "800b" =>  'nicht_belegt',
  "800c" =>  'Heizkennlinie_HK1_bei_+_10_Grad', # bei Umschaltung tag/nacht
  "800d" =>  'Heizkennlinie_HK1_bei_0_Grad',    # bei Umschaltung tag/nacht
  "800e" =>  'Heizkennlinie_HK1_bei_-_10_Grad', # bei Umschaltung tag/nacht
  "800f" =>  'nicht_belegt',
  "8010" =>  'nicht_belegt',
  "8011" =>  'nicht_belegt',

  "8112" =>  'Betriebswerte_1_HK2',
  "8113" =>  'Betriebswerte_1_HK2',
  "8114" =>  'Vorlaufsolltemperatur_HK2',
  "8115" =>  'Vorlaufisttemperatur_HK2',
  "8116" =>  'Raumsolltemperatur_HK2',
  "8117" =>  'Raumisttemperatur_HK2',
  "8118" =>  'Einschaltoptimierungszeit_HK2',
  "8119" =>  'Ausschaltoptimierungszeit_HK2',
  "811a" =>  'Pumpenleistung_HK2',
  "811b" =>  'Mischerstellung_HK2',
  "811c" =>  'nicht_belegt',
  "811d" =>  'nicht_belegt',
  "811e" =>  'Heizkennlinie_HK2_bei_+_10_Grad', # == HK1 - (1 bis 3)
  "811f" =>  'Heizkennlinie_HK2_bei_0_Grad',    # == HK1 - (1 bis 3)
  "8120" =>  'Heizkennlinie_HK2_bei_-_10_Grad', # == HK1 - (1 bis 3)
  "8121" =>  'nicht_belegt',
  "8122" =>  'nicht_belegt',
  "8123" =>  'nicht_belegt',

  "8424" =>  'Betriebswerte_1_WW',
  "8425" =>  'Betriebswerte_2_WW',               # 0 64 96 104 225 228
  "8426" =>  'Warmwassersolltemperatur',         # 10/55
  "8427" =>  'Warmwasseristtemperatur',          # 32-55
  "8428" =>  'Warmwasseroptimierungszeit',
  "8429" =>  'Ladepumpe',                        # 0 1 (an/aus?)

  # 1377, page 13
  "882a" =>  'Kesselvorlaufsolltemperatur',
  "882b" =>  'Kesselvorlaufisttemperatur',       # == Vorlaufisttemperatur_HK1
  "882c" =>  'Brennereinschalttemperatur',       #  5-81
  "882d" =>  'Brennerausschalttemperatur',       # 19-85
  "882e" =>  'Kesselintegral_1',                 #  0-23
  "882f" =>  'Kesselintegral_2',                 #  0-255
  "8830" =>  'Kesselfehler',
  "8831" =>  'Kesselbetrieb',                    # 0 2 32 34
  "8832" =>  'Brenneransteuerung',               # 0 1 (an/aus?)
  "8833" =>  'Abgastemperatur',
  "8834" =>  'modulare_Brenner_Stellwert',
  "8835" =>  'nicht_belegt',
  "8836" =>  'Brennerlaufzeit_1_Minuten_Byte2',
  "8837" =>  'Brennerlaufzeit_1_Minuten_Byte1',  # 176
  "8838" =>  'Brennerlaufzeit_1_Minuten_Byte0',  # 0-255 (Minuten)
  "8839" =>  'Brennerlaufzeit_2_Minuten_Byte2',
  "883a" =>  'Brennerlaufzeit_2_Minuten_Byte1',
  "883b" =>  'Brennerlaufzeit_2_Minuten_Byte0',

  # 1377, page 16
  "893c" =>  'Aussentemperatur',                # 0 1 254 255
  "893d" =>  'gedaempfte_Aussentemperatur',     # 0 1 2
  "893e" =>  'Versionsnummer_VK',
  "893f" =>  'Versionsnummer_NK',
  "8940" =>  'Modulkennung',
  "8941" =>  'nicht_belegt',
);


# Do not generate fhem events for the following high volume telegrams
# the % represents the relative nr of messages in an unfiltered stream.
# You can switch them on with attr all_km271_events
my %km271_ignore = (
  "Vorlaufisttemperatur_HK1" => 1,    # 23%
  "Kesselvorlaufisttemperatur" => 1,  # 23%, same as Vorlaufisttemperatur_HK1
  "Kesselintegral_1" => 1,            #  8%, ??
  "Kesselintegral_2" => 1,            # 38%, ??
);

my @km271_Betriebswerte_1_HK = (
  "Ausschaltoptimierung", "Einschaltoptimierung", "Automatik",
  "Warmwasservorrang", "Estrichtrocknung", "Ferien", "Frostschutz", "Manuell",
);
my @km271_Betriebswerte_2_HK = (
  "Sommer", "Tag", "keine Kommunikation mit FB", "FB fehlerhhaft",
  "Fehler Vorlauffühler", "maximaler Vorlauf", "externer Störeingang", "frei",
);
my @km271_Betriebswerte_1_WW = (
  "Automatik", "Desinfektion", "Nachladung", "Ferien", "Fehler Desinfektion",
  "Fehler Fuehler", "Fehler WW bleibt kalt", "Fehler Anode",
);
my @km271_Betriebswerte_2_WW = (
  "Laden", "Manuell", "Nachladen", "Ausschaltoptimierung",
  "Einschaltoptimierung", "Tag", "Warm", "Vorrang",
);
my @km271_Kesselbetrieb = (
  "Tag", "Automatik", "Sommer", "Bit3", "Bit4", "Bit5", "Bit6", "Bit7",
);



sub
KM271_Initialize($)
{
  my ($hash) = @_;

  $hash->{ReadFn}  = "KM271_Read";
  $hash->{ReadyFn} = "KM271_Ready";

  $hash->{DefFn}   = "KM271_Define";
  $hash->{UndefFn} = "KM271_Undef";
  $hash->{SetFn}   = "KM271_Set";
  $hash->{AttrList}= "do_not_notify:1,0 all_km271_events loglevel:0,1,2,3,4,5,6";
}

#####################################
sub
KM271_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> KM271 [devicename|none]"
    if(@a != 3);

  KM271_CloseDev($hash);
  my $name = $a[0];
  my $dev = $a[2];

  if($dev eq "none") {
    Log 1, "KM271 device is none, commands will be echoed only";
    return undef;
  }
  
  $hash->{DeviceName} = $dev;
  my $ret = KM271_OpenDev($hash);
  return $ret;
}


#####################################
sub
KM271_Undef($$)
{
  my ($hash, $arg) = @_;
  KM271_CloseDev($hash); 
  return undef;
}

#####################################
sub
KM271_Set($@)
{
  my ($hash, @a) = @_;

  return "\"set KM271\" needs at least one parameter" if(@a < 2);
  return "Unknown argument $a[1], choose one of " . join(" ", sort keys %sets)
  	if(!defined($sets{$a[1]}));

  my $name = shift @a;
  my $type = shift @a;
  my $arg = join("", @a);

  return undef;
}


#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub
KM271_Read($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $buf = KM271_SimpleRead($hash);
  Log GetLogLevel($name,5), "KM271 RAW: " . unpack('H*', $buf);

  if(!defined($buf)) {
    Log 1, "$name: EOF";
    KM271_CloseDev($hash);
    return;
  }

  $buf = unpack('H*', $buf);
  if($buf eq "02") {
    $hash->{PARTIAL} = "";
    KM271_SimpleWrite($hash, $dle);
    return;
  }

  $hash->{PARTIAL} .= $buf;
  my $len = length($hash->{PARTIAL});
  return if($hash->{PARTIAL} !~ m/^(.*)1003(..)$/);
  my ($data, $crc) = ($1, $2);
  if(KM271_crc($data) ne $crc) {
    Log 1, "Wrong CRC in $hash->{PARTIAL}: $crc vs. ". KM271_crc($data);
    $hash->{PARTIAL} = "";
    KM271_SimpleWrite($hash, $nak);
    return;
  }
  KM271_SimpleWrite($hash, $dle);

  $data =~ s/1010/10/g;
  if($data =~ m/^(8...)(..)/) {
    my ($fn, $arg) = ($1, $2);

    my $msg = $km271_trhash{$fn};
    $msg = "UNKNOWN_$fn" if(!$msg);
    my $tn = TimeNow();
    my $val = hex($arg);
    my $ignore = $km271_ignore{$msg};


    if($msg =~ m/Aussentemperatur/) { 
      $val = $val-256 if($val > 128);

    } elsif($msg =~ m/Brennerlaufzeit_(.)_Minuten_Byte(.)/) {
      my ($idx, $no) = ($1, $2);

      if($no == 2 || $no == 1) {
        $ignore = 1;

      } else {
        $msg = "Brennerlaufzeit_${idx}_Minuten";
        $val = KM271_Reading($hash, $msg . "_Byte2") * 65536 +
               KM271_Reading($hash, $msg . "_Byte1") * 256 +
               $val;
      }

    } elsif($msg =~ m/Betriebswerte_1_HK/) {
      $val = KM271_setbits($val, \@km271_Betriebswerte_1_HK);

    } elsif($msg =~ m/Betriebswerte_2_HK/) {
      $val = KM271_setbits($val, \@km271_Betriebswerte_2_HK);

    } elsif($msg =~ m/Betriebswerte_1_WW/) {
      $val = KM271_setbits($val, \@km271_Betriebswerte_1_WW);

    } elsif($msg =~ m/Betriebswerte_2_WW/) {
      $val = KM271_setbits($val, \@km271_Betriebswerte_2_WW);

    } elsif($msg =~ m/Brenneransteuerung/) {
      $val = ($val ? "an" : "aus");
      
    } elsif($msg =~ m/Kesselbetrieb/) {
      $val = KM271_setbits($val, \@km271_Kesselbetrieb);

    }

    Log GetLogLevel($name,4), "KM271 $name: $msg $val";
    $hash->{READINGS}{$msg}{TIME} = $tn;
    $hash->{READINGS}{$msg}{VAL} = $val;
    if(KM271_attr($name, "all_km271_events") || !$ignore) {
      DoTrigger($name, "$msg: $val");
    }

  } elsif($data eq "04000701c4024192") {
    # No data message

  } else {
    Log 1, "$name: UNKNOWN $data";

  }
  $hash->{PARTIAL} = "";
}

#####################################
sub
KM271_Ready($)
{
  my ($hash) = @_;

  # This is relevant for windows/USB only
  my $po = $hash->{Dev};
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  return ($InBytes>0);
}

########################
sub
KM271_SimpleWrite(@)
{
  my ($hash, $msg) = @_;
  $hash->{Dev}->write($msg);
}

########################
sub
KM271_SimpleRead($)
{
  my ($hash) = @_;

  return $hash->{Dev}->input() if($hash->{Dev});
  return undef;
}

########################
sub
KM271_CloseDev($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $dev = $hash->{DeviceName};

  return if(!$dev);     # "none"
  
  if($hash->{Dev}) {
    $hash->{Dev}->close() ;
    delete($hash->{Dev});

  }
  delete($selectlist{"$name.$dev"});
  delete($readyfnlist{"$name.$dev"});
  delete($hash->{FD});
}

########################
sub
KM271_OpenDev($)
{
  my ($hash) = @_;
  my $dev = $hash->{DeviceName};
  my $name = $hash->{NAME};
  my $po;

  $hash->{PARTIAL} = "";
  Log 3, "KM271 opening $name device $dev";

  if ($^O=~/Win/) {
   require Win32::SerialPort;
   $po = new Win32::SerialPort ($dev);
  } else  {
   require Device::SerialPort;
   $po = new Device::SerialPort ($dev);
  }

  if(!$po) {
    Log(3, "Can't open $dev: $!");
    return "";
  }
  $hash->{Dev} = $po;
  if( $^O =~ /Win/ ) {
    $readyfnlist{"$name.$dev"} = $hash;
  } else {
    $hash->{FD} = $po->FILENO;
    delete($readyfnlist{"$name.$dev"});
    $selectlist{"$name.$dev"} = $hash;
  }

  $po->reset_error();
  $po->baudrate(2400);
  $po->databits(8);
  $po->parity('none');
  $po->stopbits(1);
  $po->handshake('none');
  $po->write($logmode);

  $hash->{STATE} = "Initialized";

  Log 3, "$dev opened";
  return undef;
}

sub
KM271_setbits($$)
{
  my ($val, $arr) = @_;
  my $bit = 1;
  my @ret;

  for(my $idx = 0; $idx < 8; $idx++) {
    push(@ret, $arr->[$idx]) if($val & $bit);
    $bit *= 2;
  }
  return "keine Bits gesetzt" if(!@ret);
  return join(",", @ret);
}

sub
KM271_crc($)
{
  my $in = shift;
  my $x = 0;
  foreach my $a (split("", pack('H*', $in))) {
    $x ^= ord($a);
  }
  $x ^= 0x10;
  $x ^= 0x03;
  return sprintf("%02x", $x);
}

sub
KM271_attr($$)
{
  my ($name, $attr) = @_;
  return $attr{$name}{$attr} if($attr{$name} && $attr{$name}{$attr});
  return "";
}

sub
KM271_Reading($$)
{
  my ($hash, $msg) = @_;
  return $hash->{READINGS}{$msg}{VAL}
    if($hash->{READINGS} && $hash->{READINGS}{$msg});
  return 0;
}


1;
