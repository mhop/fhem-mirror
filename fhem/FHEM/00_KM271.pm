##############################################
# Thx to Himtronics
# http://www.mikrocontroller.net/topic/141831
# http://www.mikrocontroller.net/attachment/63563/km271-protokoll.txt
# Buderus documents: 63011376, 63011377, 63011378
# e.g. http://www.buderus.de/pdf/unterlagen/0063061377.pdf

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
sub KM271_GetReading($$);
sub KM271_SetReading($$$$$);

my %km271_sets = (
  "hk1_nachtsoll"   => "07006565%02x656565", # 0.5 celsius
  "hk1_tagsoll"     => "0700656565%02x6565", # 0.5 celsius
  "hk1_betriebsart" => "070065656565%02x65",

  "ww_soll"         => "0C07656565%02x6565", # 1.0 celsius
  "ww_betriebsart"  => "0C0E%02x6565656565", 

  "logmode"         => "EE0000",
);


# Message address:byte_offset in the message
# Attributes:
#   d:x (divide), p:x (add), bf:x (bitfield), a:x (array) ne (generate no event)
#   mb:x (multi-byte-message, x-bytes, low byte), s (signed value)

my %km271_tr = (
  "CFG_SommerAb"                    => "0000:1",     # 6510242a021e
  "CFG_Raum_Temp_Nacht"             => "0000:2,d:2",
  "CFG_Raum_Temp_Tag"               => "0000:3,d:2",
  "CFG_Betriebsart"                 => "0000:4,a:4",
  "CFG_Auslegung"                   => "000e:4",     # 01045a054d65
  "CFG_FrostAb"                     => "0015:2",     # 030104650005
  "CFG_Raum_Temp_Aufschalt"         => "0015:0,s",
  "CFG_Absenkungsart"               => "001c:1,a:6", # 0c0101656565
  "CFG_Fernbedienung"               => "0031:4,a:0", # 656565fc0104
  "CFG_Raum_Temp_Offset"            => "0031:3,s",   # 
  "CFG_GebaeudeArt"                 => "0070:2,p:1", # f66502066565
  "CFG_WW_Temperatur"               => "007e:3",     # 65fb28373c65
  "CFG_ZirkPumpe"                   => "0085:5",     # 026565016502
  "CFG_Warmwasser"                  => "0085:3,a:0",
  "CFG_Display_Lang"                => "0093:0,a:3", # 000302656565
  "CFG_Display"                     => "0093:1,a:1",
  "CFG_MaxAus"                      => "009a:3",     # 65016554050c
  "CFG_PumpLogik"                   => "00a1:0",     # 2a0565656509
  "CFG_Abgastemp"                   => "00a1:5,p:-9,a:5",
  "CFG_Programm"                    => "0100:0,a:2", # 01ffff00ffff
  "CFG_UrlaubsTage"                 => "0169:3",     # 01ffff03ffff
  "CFG_UhrDiff"                     => "01e0:1,s",   # 010065656565

  "HK1_Betriebswerte1"              => "8000:0,bf:0",
  "HK1_Betriebswerte2"              => "8001:0,bf:1",
  "HK1_Vorlaufsolltemperatur"       => "8002:0",
  "HK1_Vorlaufisttemperatur"        => "8003:0,ne",  # 23% of all messages
  "HK1_Raumsolltemperatur"          => "8004:0,d:2",
  "HK1_Raumisttemperatur"           => "8005:0,d:2",
  "HK1_Einschaltoptimierungszeit"   => "8006:0",
  "HK1_Ausschaltoptimierungszeit"   => "8007:0",
  "HK1_Pumpenleistung"              => "8008:0",
  "HK1_Mischerstellung"             => "8009:0",
  "HK1_Heizkennlinie_bei_+_10_Grad" => "800c:0",
  "HK1_Heizkennlinie_bei_0_Grad"    => "800d:0",
  "HK1_Heizkennlinie_bei_-_10_Grad" => "800e:0",
  "HK2_Betriebswerte1"              => "8112:0,bf:0",
  "HK2_Betriebswerte2"              => "8113:0,bf:1",
  "HK2_Vorlaufsolltemperatur"       => "8114:0",
  "HK2_Vorlaufisttemperatur"        => "8115:0,ne",
  "HK2_Raumsolltemperatur"          => "8116:0,d:2",
  "HK2_Raumisttemperatur"           => "8117:0,d:2",
  "HK2_Einschaltoptimierungszeit"   => "8118:0",
  "HK2_Ausschaltoptimierungszeit"   => "8119:0",
  "HK2_Pumpenleistung"              => "811a:0",
  "HK2_Mischerstellung"             => "811b:0",
  "HK2_Heizkennlinie_bei_+_10_Grad" => "811e:0",
  "HK2_Heizkennlinie_bei_0_Grad"    => "811f:0",
  "HK2_Heizkennlinie_bei_-_10_Grad" => "8120:0",
  "WW_Betriebswerte1"               => "8424:0,bf:2",
  "WW_Betriebswerte2"               => "8425:0,bf:3",
  "WW_Solltemperatur"               => "8426:0",
  "WW_Isttemperatur"                => "8427:0",
  "WW_Einschaltoptimierungszeit"    => "8428:0",
  "WW_Ladepumpe"                    => "8429:0,bf:5",
  "Kessel_Vorlaufsolltemperatur"    => "882a:0",
  "Kessel_Vorlaufisttemperatur"     => "882b:0,ne",  # 23% of all messages
  "Brenner_Einschalttemperatur"     => "882c:0",
  "Brenner_Ausschalttemperatur"     => "882d:0",
  "Kessel_Integral1"                => "882e:0,ne",
  "Kessel_Integral"                 => "882f:0,ne,mb:2", # 46% of all messages
  "Kessel_Fehler"                   => "8830:0,bf:6",
  "Kessel_Betrieb"                  => "8831:0,bf:4",
  "Brenner_Ansteuerung"             => "8832:0,a:0",
  "Abgastemperatur"                 => "8833:0",
  "Brenner_Stellwert"               => "8834:0",
  "Brenner_Laufzeit1_Minuten2"      => "8836:0,ne",
  "Brenner_Laufzeit1_Minuten1"      => "8837:0,ne",
  "Brenner_Laufzeit1_Minuten"       => "8838:0,ne,mb:3",
  "Brenner_Laufzeit2_Minuten2"      => "8839:0,ne",
  "Brenner_Laufzeit2_Minuten1"      => "883a:0,ne",
  "Brenner_Laufzeit2_Minuten"       => "883b:0,ne:mb:3",
  "Aussentemperatur"                => "893c:0,s",
  "Aussentemperatur_gedaempft"      => "893d:0,s",
  "Versionsnummer_VK"               => "893e:0",
  "Versionsnummer_NK"               => "893f:0",
  "Modulkennung"                    => "8940:0",
);
my %km271_rev;

my @km271_bitarrays = (
  # 0 - HK_Betriebswerte1
  [ "leer", "Ausschaltoptimierung", "Einschaltoptimierung", "Automatik",
          "Warmwasservorrang", "Estrichtrocknung", "Ferien", "Frostschutz",
          "Manuell" ],
  # 1 - HK_Betriebswerte2
  [ "leer", "Sommer", "Tag", "keine Kommunikation mit FB", "FB fehlerhaft",
          "Fehler Vorlauffuehler", "maximaler Vorlauf",
          "externer Stoehreingang", "frei" ],
  # 2 - WW_Betriebswerte1
  [ "aus", "Automatik", "Desinfektion", "Nachladung", "Ferien",
         "Fehler Desinfektion", "Fehler Fuehler", "Fehler WW bleibt kalt",
         "Fehler Anode" ],
  # 3 - WW_Betriebswerte2
  [ "aus", "Laden", "Manuell", "Nachladen", "Ausschaltoptimierung",
         "Einschaltoptimierung", "Tag", "Warm", "Vorrang" ],
  # 4 - Kessel_Betrieb 
  [ "aus", "Tag", "Automatik", "Sommer",
         "Bit3", "Bit4", "Bit5", "Bit6", "Bit7" ],
  # 5 - WW_Ladepumpe
  [ "aus", "Ladepumpe", "Zirkulationspumpe", "Absenkung Solar",
         "Bit3", "Bit4", "Bit5", "Bit6", "Bit7" ],
  # 6 - Kessel_Fehler
  [ "keine", "Bit1", "Bit2", "Bit3", "Bit4",
        "Abgastemperatur ueberschritten", "Bit6", "Bit7" ],
);

my @km271_arrays = (
# 0 - Brenner_Ansteuerung , CFG_Fernbedienung, CFG_Warmwasser
  [ "aus", "an" ],
# 1 - CFG_Display 
  [ "Automatik", "Kessel", "Warmwasser", "Aussen" ],
# 2 - CFG_Programm 
  [ "Eigen1", "Familie", "Frueh", "Spaet", "Vormit", "Nachmit",
    "Mittag", "Single", "Senior" ],
# 3 - CFG_Display_Lang 
  [ "DE", "FR", "IT", "NL", "EN", "PL" ],
# 4 - CFG_Betriebsart
  [ "Nacht", "Tag", "Automatik" ],
# 5 - CFG_Abgastemp
  [ "Aus","50","55","60","65","70","75","80","85","90","95","100","105",
    "110","115","120","125","130","135","140","145","150","155","160","165",
    "170","175","180","185","190","195","200","205","210","215","220","225",
    "230","235","240","245","250" ],
# 6 - CFG_Absenkungsart
  [ "Abschalt","Reduziert","Raumhal","Aussenhal"]
);

my %km271_set_betriebsart = (
  "nacht"     => 0,
  "tag"       => 1,
  "automatik" => 2,
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

  %km271_rev = ();
  foreach my $k (sort keys %km271_tr) {      # Reverse map
    my $v = $km271_tr{$k};
    my ($addr, $b) = split("[:,]", $v);
    $km271_rev{$addr}{$b} = $k;
  }
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

  return "\"set KM271\" needs at least an argument" if(@a < 2);

  my $fmt = $km271_sets{$a[1]};
  return "Unknown argument $a[1], choose one of " . 
                join(" ", sort keys %km271_sets) if(!defined($fmt));

  my ($val, $numeric_val);
  if($fmt =~ m/%/) {
    return "\"set KM271 $a[1]\" needs at least one parameter" if(@a < 3);
    $val = $a[2];
    $numeric_val = ($val =~ m/^[.0-9]+$/);
  }


  if($a[1] =~ m/^hk.*soll$/) {
    return "Argument must be numeric (between 10 and 30)" if(!$numeric_val);
    $val *= 2;
  }
  if($a[1] =~ m/^ww.*soll$/) {
    return "Argument must be numeric (between 30 and 60)" if(!$numeric_val);
  }

  if($a[1] =~ m/_betriebsart/) {
    $val = $km271_set_betriebsart{$val};
    return "Unknown arg, use one of " .
      join(" ", sort keys %km271_set_betriebsart) if(!defined($val));
  }

  my $data = ($val ? sprintf($fmt, $val) : $fmt);

  push @{$hash->{SENDBUFFER}}, $data;
  KM271_SimpleWrite($hash, "02") if(!$hash->{WAITING});

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
  Log 5, "KM271RAW: " . unpack('H*', $buf);

  if(!defined($buf)) {
    Log 1, "$name: EOF";
    KM271_CloseDev($hash);
    return;
  }

  $buf = unpack('H*', $buf);

  if(@{$hash->{SENDBUFFER}} || $hash->{DATASENT}) {               # Send data

    if($buf eq "02") {                    # KM271 Wants to send, override
      KM271_SimpleWrite($hash, "02");
      return;
    }

    if($buf eq "10") { 
      if($hash->{DATASENT}) {
        delete($hash->{DATASENT});
        KM271_SimpleWrite($hash, "02") if(@{$hash->{SENDBUFFER}});
        return;
      }
      $data = pop @{ $hash->{SENDBUFFER} };
      $data =~ s/10/1010/g;
      $crc = KM271_crc($data);
      KM271_SimpleWrite($hash, $data."1003$crc");  # Send the data
    }

    if($buf eq "15") {                        # NACK from the KM271
      Log 1, "$name: NACK!";
      delete($hash->{DATASENT});
      KM271_SimpleWrite($hash, "02") if(@{$hash->{SENDBUFFER}});
      return;
    }

  } elsif($buf eq "02") {                    # KM271 Wants to send
    KM271_SimpleWrite($hash, "10");     # We are ready
    $hash->{PARTIAL} = "";
    $hash->{WAITING} = 1;
    return;

  }


  $hash->{PARTIAL} .= $buf;
  my $len = length($hash->{PARTIAL});
  return if($hash->{PARTIAL} !~ m/^(.*)1003(..)$/);
  ($data, $crc) = ($1, $2);
  $hash->{PARTIAL} = "";
  delete($hash->{WAITING});

  if(KM271_crc($data) ne $crc) {
    Log 1, "Wrong CRC in $hash->{PARTIAL}: $crc vs. ". KM271_crc($data);
    KM271_SimpleWrite($hash, "15"); # NAK
    KM271_SimpleWrite($hash, "02") if(@{$hash->{SENDBUFFER}}); # want to send
    return;
  }

  KM271_SimpleWrite($hash, "10");       # ACK, Data received ok


  $data =~ s/1010/10/g;
  if($data !~ m/^(....)(.*)/) {
    Log 1, "$name: Bogus message: $data";
    return;
  }

  ######################################
  # Analyze the data
  my ($fn, $arg) = ($1, $2);
  my $msghash = $km271_rev{$fn};
  my $all_events = KM271_attr($name, "all_km271_events") ;
  my $tn = TimeNow();

  #Log 1, "$data" if($fn ne "0400");

  if($msghash) {
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
        elsif($f eq "s")  { $val = $val-256 if($val > 128); }
        elsif($f eq "bf") { $val = KM271_setbits($val, $farg); }
        elsif($f eq "a")  { $val = $km271_arrays[$farg][$val]; }
        elsif($f eq "mb") {
          $val += KM271_GetReading($hash, $key."1") * 256;
          $val += KM271_GetReading($hash, $key."2") * 65536 if($farg == 3);
        } 
      }
      KM271_SetReading($hash, $tn, $key, $val, $ntfy);
    }

  } elsif($fn eq "0400") {
    KM271_SetReading($hash, $tn, "NoData", $arg, 0);

  } elsif($all_events) { 
    KM271_SetReading($hash, $tn, "UNKNOWN_$fn", $data, 1);

  } else {            # Just ignore
    return;

  }

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
  Log 3, "KM271 SimpleWrite $msg" if(length($msg) != 2);
  $hash->{Dev}->write(pack('H*',$msg)) if($hash->{DeviceName});
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
  delete($hash->{DeviceName});
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

  push @{$hash->{SENDBUFFER}}, "EE0000";
  KM271_SimpleWrite($hash, "02");      # STX

  Log 3, "$dev opened";
  return undef;
}

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
KM271_GetReading($$)
{
  my ($hash, $msg) = @_;
  return $hash->{READINGS}{$msg}{VAL}
    if($hash->{READINGS} && $hash->{READINGS}{$msg});
  return 0;
}

sub
KM271_SetReading($$$$$)
{
  my ($hash,$tn,$key,$val,$ntfy) = @_;
  my $name = $hash->{NAME};
  Log GetLogLevel($name,4), "$name: $key $val" if($key ne "NoData");
  $hash->{READINGS}{$key}{TIME} = $tn;
  $hash->{READINGS}{$key}{VAL} = $val;
  DoTrigger($name, "$key: $val") if($ntfy);
}


1;
