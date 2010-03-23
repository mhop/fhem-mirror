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
sub KM271_setbits($$$);
sub KM271_Reading($$);

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
  "007e" =>  "Manuell_WW",
  "0085" =>  "Manuell_ZirkulationsPumpe",
  "0093" =>  "Manuell_Uhrzeit",

  "0300" =>  "Tagwechsel_1",
  "0307" =>  "Tagwechsel_2",
  "030e" =>  "Tagwechsel_3",
  "0315" =>  "Tagwechsel_4",

  "0400" =>  "NoData",

  "8000" =>  'HK1_Betriebswerte1',              # 76, 4 [repeat]
  "8001" =>  'HK1_Betriebswerte2',              # 0 (22:33), 2 (7:33)
  "8002" =>  'HK1_Vorlaufsolltemperatur',       # 50-65
  "8003" =>  'HK1_Vorlaufisttemperatur',        # Schwingt um soll herum
  "8004" =>  'HK1_Raumsolltemperatur',          # 34 (22:33) 42 (7:33)
  "8005" =>  'HK1_Raumisttemperatur',
  "8006" =>  'HK1_Einschaltoptimierungszeit',
  "8007" =>  'HK1_Ausschaltoptimierungszeit',
  "8008" =>  'HK1_Pumpenleistung',              # 0/100 == Ladepumpe
  "8009" =>  'HK1_Mischerstellung',
  "800c" =>  'HK1_Heizkennlinie_bei_+_10_Grad', # bei Umschaltung tag/nacht
  "800d" =>  'HK1_Heizkennlinie_bei_0_Grad',    # bei Umschaltung tag/nacht
  "800e" =>  'HK1_Heizkennlinie_bei_-_10_Grad', # bei Umschaltung tag/nacht

  "8112" =>  'HK2_Betriebswerte1',
  "8113" =>  'HK2_Betriebswerte2',
  "8114" =>  'HK2_Vorlaufsolltemperatur',
  "8115" =>  'HK2_Vorlaufisttemperatur',
  "8116" =>  'HK2_Raumsolltemperatur',
  "8117" =>  'HK2_Raumisttemperatur',
  "8118" =>  'HK2_Einschaltoptimierungszeit',
  "8119" =>  'HK2_Ausschaltoptimierungszeit',
  "811a" =>  'HK2_Pumpenleistung',
  "811b" =>  'HK2_Mischerstellung',
  "811e" =>  'HK2_Heizkennlinie_bei_+_10_Grad', # == HK1 - (1 bis 3 Grad)
  "811f" =>  'HK2_Heizkennlinie_bei_0_Grad',    # == HK1 - (1 bis 3 Grad)
  "8120" =>  'HK2_Heizkennlinie_bei_-_10_Grad', # == HK1 - (1 bis 3 Grad)

  # 1377, page 11
  "8424" =>  'WW_Betriebswerte1',
  "8425" =>  'WW_Betriebswerte2',               # 0 64 96 104 225 228
  "8426" =>  'WW_Solltemperatur',               # 10/55
  "8427" =>  'WW_Isttemperatur',                # 32-55
  "8428" =>  'WW_Einschaltoptimierungszeit',
  "8429" =>  'WW_Ladepumpe',                    # 0 1 (an/aus?)

  # 1377, page 13
  "882a" =>  'Kessel_Vorlaufsolltemperatur',
  "882b" =>  'Kessel_Vorlaufisttemperatur',     # == Vorlaufisttemperatur_HK1
  "882c" =>  'Brenner_Einschalttemperatur',     #  5-81
  "882d" =>  'Brenner_Ausschalttemperatur',     # 19-85
  "882e" =>  'Kessel_IntegralHB',               #  0-23
  "882f" =>  'Kessel_IntegralLB',               #  0-255
  "8830" =>  'Kessel_Fehler',
  "8831" =>  'Kessel_Betrieb',                  # 0 2 32 34
  "8832" =>  'Brenner_Ansteuerung',             # 0 1 (an/aus?)
  "8833" =>  'Abgastemperatur',
  "8834" =>  'Brenner_Stellwert',
  "8836" =>  'Brenner_Laufzeit1_Minuten2',
  "8837" =>  'Brenner_Laufzeit1_Minuten1',      # 176
  "8838" =>  'Brenner_Laufzeit1_Minuten0',      # 0-255 (Minuten)
  "8839" =>  'Brenner_Laufzeit2_Minuten2',
  "883a" =>  'Brenner_Laufzeit2_Minuten1',
  "883b" =>  'Brenner_Laufzeit2_Minuten0',

  # 1377, page 16
  "893c" =>  'Aussentemperatur',                # 0 1 254 255
  "893d" =>  'Aussentemperatur_gedaempft',      # 0 1 2
  "893e" =>  'Versionsnummer_VK',
  "893f" =>  'Versionsnummer_NK',
  "8940" =>  'Modulkennung',
);


# Do not generate fhem events for the following high volume telegrams
# the % represents the relative nr of messages in an unfiltered stream.
# You can switch them on with attr all_km271_events
my %km271_noevent = (
  "HK1_Vorlaufisttemperatur" => 1,    # 23% of all messages
  "HK2_Vorlaufisttemperatur" => 1,
  "Kesselvorlaufisttemperatur" => 1,  # 23%, same as Vorlaufisttemperatur_HK1
  "Kessel_IntegralHB" => 1,           #  8%, ??
  "Kessel_IntegralLB" => 1,           # 38%, ??
);

my @km271_HK_Betriebswerte1 = (
  "Ausschaltoptimierung", "Einschaltoptimierung", "Automatik",
  "Warmwasservorrang", "Estrichtrocknung", "Ferien", "Frostschutz", "Manuell",
);
my @km271_HK_Betriebswerte2 = (
  "Sommer", "Tag", "keine Kommunikation mit FB", "FB fehlerhhaft",
  "Fehler Vorlauffühler", "maximaler Vorlauf", "externer Störeingang", "frei",
);
my @km271_WW_Betriebswerte1 = (
  "Automatik", "Desinfektion", "Nachladung", "Ferien", "Fehler Desinfektion",
  "Fehler Fuehler", "Fehler WW bleibt kalt", "Fehler Anode",
);
my @km271_WW_Betriebswerte2 = (
  "Laden", "Manuell", "Nachladen", "Ausschaltoptimierung",
  "Einschaltoptimierung", "Tag", "Warm", "Vorrang",
);
my @km271_Kessel_Betrieb = (
  "Tag", "Automatik", "Sommer", "Bit3", "Bit4", "Bit5", "Bit6", "Bit7",
);
my @km271_WW_Ladepumpe = (
  "Ladepumpe", "Zirkulationspumpe", "Absenkung Solar",
  "Bit3", "Bit4", "Bit5", "Bit6", "Bit7",
);


my %km271_set_betriebsart = (
  "manuell_nacht"=>0,
  "manuell_tag"  =>1,
  "automatik"    =>2,
);

my %km271_sets = (
  "hk1_nachtsoll"   => "07006565%02x656565", # 0.5 celsius
  "hk1_tagsoll"     => "0700656565%02x6565", # 0.5 celsius
  "hk1_betriebsart" => "070065656565%02x65",
  "ww_soll"         => "0C07656565%02x6565", # 1.0 celsius
  "ww_betriebsart"  => "0C0E%02x6565656565", 
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
  my @a = ();
  $hash->{SENDBUFFER} = \@a;
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

  my $fmt = $km271_sets{$a[1]};
  return "Unknown argument $a[1], choose one of " . 
                join(" ", sort keys %km271_sets) if(!defined($fmt));
  my $val = $a[2];
  my $numeric_arg = ($val =~ m/^[.0-9]+$/);

  if($a[1] =~ m/^hk.*soll$/) {
    return "Argument must be numeric (between 10 and 30)" if(!$numeric_arg);
    $val *= 2;
  }
  if($a[1] =~ m/^ww.*soll$/) {
    return "Argument must be numeric (between 30 and 60)" if(!$numeric_arg);
  }
  if($a[1] =~ m/_betriebsart/) {
    $val = $km271_set_betriebsart{$val};
    return "Unknown arg, use one of " .
      join(" ", sort keys %km271_set_betriebsart) if(!defined($val));
  }
  my $data = sprintf($fmt, $val);

  push @{$hash->{SENDBUFFER}}, $data;
  KM271_SimpleWrite($hash, $stx) if(!$hash->{WAITING});

  return undef;
}


#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub
KM271_Read($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my ($data, $crc);

  my $buf = KM271_SimpleRead($hash);
  Log GetLogLevel($name,5), "KM271 RAW: " . unpack('H*', $buf);

  if(!defined($buf)) {
    Log 1, "$name: EOF";
    KM271_CloseDev($hash);
    return;
  }

  if($buf eq "02") {                    # KM271: Want to send
    $hash->{PARTIAL} = "";
    KM271_SimpleWrite($hash, $dle);     # We are ready
    $hash->{WAITING} = 1;
    return;
  }

  if(!$hash->{WAITING}) {               # Send data

    if($buf eq "10") { 
      if($hash->{DATASENT}) {           # ACK Data
        delete($hash->{DATASENT});
        return;
      }
      $data = pop @{ $hash->{SENDBUFFER} };
      $data =~ s/10/1010/g;
      $crc = KM271_crc($data);
      KM271_SimpleWrite($hash, $data."1003$crc");  # Send the data
      $hash->{DATASENT} = 1;
    }

    if($buf eq "15" && $hash->{DATASENT}) { # NACK from the KM271
      Log 1, "$name: NACK!";
      delete($hash->{DATASENT});
      return;
    }
  }


  $hash->{PARTIAL} .= $buf;
  my $len = length($hash->{PARTIAL});
  return if($hash->{PARTIAL} !~ m/^(.*)1003(..)$/);
  ($data, $crc) = ($1, $2);
  if(KM271_crc($data) ne $crc) {
    Log 1, "Wrong CRC in $hash->{PARTIAL}: $crc vs. ". KM271_crc($data);
    $hash->{PARTIAL} = "";
    KM271_SimpleWrite($hash, $nak);
    return;
  }
  KM271_SimpleWrite($hash, $dle);       # Data received ok
  delete($hash->{WAITING});
  if($hash->{SENDBUFFER}) {
    KM271_SimpleWrite($hash, $stx)
  }

  $data =~ s/1010/10/g;


  if($data !~ m/^(....)(.*)/) {
    Log 1, "$name: Bogus message: $data";
    return;
  }

  my ($fn, $arg) = ($1, $2);
  my $msg = $km271_trhash{$fn};
  $msg = "UNKNOWN_$fn" if(!$msg);
  my $tn = TimeNow();
  my $val = unpack('H*', $arg);
  my $gen_notify = $km271_noevent{$msg} ? 0 : 1;
  $gen_notify = KM271_attr($name, "all_km271_events") 
    if(!$gen_notify);


  if($msg eq "NoData") {
    $gen_notify = 0;

  } elsif($msg =~ m/^UNKNOWN/) {
    $val = $data;
    $gen_notify = 0;
    
  } elsif($msg =~ m/Aussentemperatur/) { 
    $val = $val-256 if($val > 128);

  } elsif($msg =~ m/Brenner_Laufzeit(.)_Minuten(.)/) {
    my ($idx, $no) = ($1, $2);

    if($no == 2 || $no == 1) {
      $gen_notify = 0;

    } else {
      $msg = "Brenner_Laufzeit${idx}_Minuten";
      $val = KM271_Reading($hash, $msg . "2") * 65536 +
             KM271_Reading($hash, $msg . "1") * 256 +
             $val;
    }

  } elsif($msg =~ m/HK._Betriebswerte/) {
    $val = KM271_setbits($val, \@km271_HK_Betriebswerte1, "leer");

  } elsif($msg =~ m/HK._Betriebswerte2/) {
    $val = KM271_setbits($val, \@km271_HK_Betriebswerte2, "leer");

  } elsif($msg =~ m/WW_Betriebswerte1/) {
    $val = KM271_setbits($val, \@km271_WW_Betriebswerte1, "aus");

  } elsif($msg =~ m/WW_Betriebswerte2/) {
    $val = KM271_setbits($val, \@km271_WW_Betriebswerte2, "aus");

  } elsif($msg =~ m/Brenner_Ansteuerung/) {
    $val = ($val ? "an" : "aus");
    
  } elsif($msg =~ m/Kessel_Betrieb/) {
    $val = KM271_setbits($val, \@km271_Kessel_Betrieb, "aus");

  } elsif($msg =~ m/WW_Ladepumpe/) {
    $val = KM271_setbits($val, \@km271_WW_Ladepumpe, "aus");

  } elsif($msg =~ m/HK?_Raum.*temperatur/) {
    $val = $val/2;

  }

  $val = $arg if(length($arg) > 2);

  Log GetLogLevel($name,4), "KM271 $name: $msg $val";
  $hash->{READINGS}{$msg}{TIME} = $tn;
  $hash->{READINGS}{$msg}{VAL} = $val;
  DoTrigger($name, "$msg: $val") if($gen_notify);

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
  $hash->{Dev}->write($msg) if($hash->{DeviceName});
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

  $hash->{STATE} = "Initialized";

  #$po->write($logmode);
  push @{$hash->{SENDBUFFER}}, "EE0000";
  KM271_SimpleWrite($hash, $stx);

  Log 3, "$dev opened";
  return undef;
}

sub
KM271_setbits($$$)
{
  my ($val, $arr, $nulltxt) = @_;
  my $bit = 1;
  my @ret;

  for(my $idx = 0; $idx < 8; $idx++) {
    push(@ret, $arr->[$idx]) if($val & $bit);
    $bit *= 2;
  }
  return $nulltxt if(!@ret);
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
