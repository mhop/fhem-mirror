##############################################
package main;

use strict;
use warnings;

my %defptr;

# Supports following devices:
# KS300TH     (this is redirected to the more sophisticated 14_KS300 by 00_CUL)
# S300TH  
# WS2000/WS7000
#

#####################################
sub
CUL_WS_Initialize($)
{
  my ($hash) = @_;

  # Message is like
  # K41350270

  $hash->{Match}     = "^K.....";
  $hash->{DefFn}     = "CUL_WS_Define";
  $hash->{UndefFn}   = "CUL_WS_Undef";
  $hash->{AttrFn}    = "CUL_WS_Attr";
  $hash->{ParseFn}   = "CUL_WS_Parse";
  $hash->{AttrList}  = "IODev do_not_notify:0,1 showtime:0,1 model:S300TH,KS300 loglevel";
}


#####################################
sub
CUL_WS_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> CUL_WS <code> [corr1...corr4]"
            if(int(@a) < 3 || int(@a) > 7);
  $a[2] = lc($a[2]);
  return "Define $a[0]: wrong CODE format: valid is 1-8"
                if($a[2] !~ m/^[1-8]$/);

  $hash->{CODE} = $a[2];
  $hash->{corr1} = ((int(@a) > 3) ? $a[3] : 0);
  $hash->{corr2} = ((int(@a) > 4) ? $a[4] : 0);
  $hash->{corr3} = ((int(@a) > 5) ? $a[5] : 0);
  $hash->{corr4} = ((int(@a) > 6) ? $a[6] : 0);
  $defptr{$a[2]} = $hash;
  AssignIoPort($hash);
  return undef;
}

#####################################
sub
CUL_WS_Undef($$)
{
  my ($hash, $name) = @_;
  delete($defptr{$hash->{CODE}}) if($hash && $hash->{CODE});
  return undef;
}


#####################################
sub
CUL_WS_Parse($$)
{
  my ($hash,$msg) = @_;
  my %tlist = ("0"=>"temp",
               "1"=>"temp/hum",
               "2"=>"rain",
               "3"=>"wind",
               "4"=>"temp/hum/press",
               "5"=>"brightness",
               "6"=>"pyro",
               "7"=>"temp/hum");


  my @a = split("", $msg);

  my $firstbyte = hex($a[1]);
  my $cde = ($firstbyte&7) + 1;
  my $type = $tlist{$a[2]} ? $tlist{$a[2]} : "unknown";

  my $def = $defptr{$hash->{NAME} . "." . $cde};
  $def = $defptr{$cde} if(!$def);
  return "" if($def->{IODev} && $def->{IODev}{NAME} ne $hash->{NAME});

  if(!$def) {
    Log 1, "CUL_WS UNDEFINED $type sensor detected, code $cde";
    return "UNDEFINED CUL_WS: $cde";
  }

  my $tm=TimeNow();
  $hash = $def;
 
  my $typbyte = hex($a[2]) & 7;
  my $sfirstbyte = $firstbyte & 7;
  my $val = "";
  my $devtype = "unknown";
  my $family  = "unknown";
  my ($sgn, $tmp, $rain, $hum, $prs, $wnd);

  if($sfirstbyte == 7) {
  
    if($typbyte == 0) {                         # temp
      $sgn = ($firstbyte&8) ? -1 : 1;
      $tmp = $sgn * ($a[6].$a[3].".".$a[4]) + $hash->{corr1};
      $val = "T: $tmp";
      $devtype = "Temp";
    }

    if($typbyte == 1) {                         # temp/hum
      $sgn = ($firstbyte&8) ? -1 : 1;
      $tmp = $sgn * ($a[6].$a[3].".".$a[4]) + $hash->{corr1};
      $hum = ($a[7].$a[8].".".$a[5]) + $hash->{corr2};
      $val = "T: $tmp  H: $hum";
      $devtype = "PS50";
      $family = "WS300";
    }

    if($typbyte == 2) {                         # rain
      #my $more = ($firstbyte&8) ? 0 : 1000;
      my $c = $hash->{corr1} ? $hash->{corr1} : 1;
      $rain = hex($a[5].$a[3].$a[4]) + $c;
      $val = "R: $rain";
      $devtype =  "Rain";
      $family = "WS300";
    }

    if($typbyte == 3) {                         # wind
      my $hun = ($firstbyte&8) ? 100 : 0;
      $wnd = ($a[6].$a[3].".".$a[4])+$hun;
      my $dir  = (($a[7]&3).$a[8].$a[5])+0;
      my $swing = ($a[7]&6) >> 2;
      $val = "W: $wnd D: $dir A: $swing";
      $devtype = "Wind";
      $family = "WS300";
    }

    if($typbyte == 4) {                         # temp/hum/press
      $sgn = ($firstbyte&8) ? -1 : 1;
      $tmp = $sgn * ($a[6].$a[3].".".$a[4]) + $hash->{corr1};
      $hum = ($a[7].$a[8].".".$a[5]) + $hash->{corr2};
      $prs = ($a[9].$a[10])+ 900 + $hash->{corr3};
      if($prs < 930) {
        $prs = $prs + 100;
      }
      $val = "T: $tmp  H: $hum  P: $prs";
      $devtype = "Indoor";
      $family = "WS300";
    }

    if($typbyte == 5) {                         # brightness
      my $fakt = 1;
      my $rawfakt = ($a[5])+0;
      if($rawfakt == 1) { $fakt =   10; }
      if($rawfakt == 2) { $fakt =  100; }
      if($rawfakt == 3) { $fakt = 1000; }
     
      my $br = (hex($a[5].$a[4].$a[3])*$fakt)  + $hash->{corr1};
      $val = "B: $br";
      $devtype = "Brightness";
      $family = "WS300";
    }

    if($typbyte == 6) {                         # Pyro: wurde nie gebaut
      $devtype = "Pyro";
      $family = "WS300";
    }

    if($typbyte == 7) {                         # Temp/hum
      $sgn = ($firstbyte&8) ? -1 : 1;
      $tmp = $sgn * ($a[6].$a[3].".".$a[4]) + $hash->{corr1};
      $hum = ($a[7].$a[8].".".$a[5]) + $hash->{corr2};
      $val = "T: $tmp  H: $hum";
      $devtype = "Temp/Hum";

    }
    
  } else {                                      # $firstbyte not 7

    if(@a == 9) {                               #  S300TH
      $sgn = ($firstbyte&8) ? -1 : 1;
      $tmp = $sgn * ($a[6].$a[3].".".$a[4]) + $hash->{corr1};
      $hum = ($a[7].$a[8].".".$a[5]) + $hash->{corr2};
      $val = "T: $tmp  H: $hum";
      $devtype = "S300TH";
      $family = "WS300";

    } elsif(@a == 15) {                         # KS300/2

      my $c = $hash->{corr4} ? $hash->{corr4} : 255;
      $rain = sprintf("%0.1f", hex("$a[14]$a[11]$a[12]") * $c / 1000);
      $wnd  = sprintf("%0.1f", "$a[9]$a[10].$a[7]" + $hash->{corr3});
      $hum  = sprintf( "%02d", "$a[8]$a[5]" + $hash->{corr2});
      $tmp  = sprintf("%0.1f", ("$a[6]$a[3].$a[4]"+ $hash->{corr1}),
                             (($a[1] & 0xC) ? -1 : 1));
      my $ir = ((hex($a[1]) & 2)) ? "yes" : "no";

      $val = "T: $tmp  H: $hum  W: $wnd  R: $rain  IR: $ir";
      $devtype = "KS300/2";
      $family = "WS300";

    } else {                                    # WS7000 Temp/Hum sensors

      $sgn = ($firstbyte&8) ? -1 : 1;
      $tmp = $sgn * ($a[6].$a[3].".".$a[4]) + $hash->{corr1};
      $hum = ($a[7].$a[8].".".$a[5]) + $hash->{corr2};
      $val = "T: $tmp  H: $hum";
      $devtype = "TH".$sfirstbyte;
      $family = "WS7000";

    }

  }

  my $name = $hash->{NAME};
  Log GetLogLevel($name,4), "CUL_WS $devtype $name: $val";

  if($hum < 0) {
    Log 1, "BOGUS: $name reading: $val, skipping it";
    return $name;
  }

  $hash->{STATE} = $val;                      # List overview
  $hash->{READINGS}{state}{TIME} = TimeNow(); # For list
  $hash->{READINGS}{state}{VAL} = $val;
  $hash->{CHANGED}[0] = $val;                 # For notify

  $hash->{READINGS}{DEVTYPE}{VAL}=$devtype;
  $hash->{READINGS}{DEVTYPE}{TIME}=$tm;
  $hash->{READINGS}{DEVFAMILY}{VAL}=$family;
  $hash->{READINGS}{DEVFAMILY}{TIME}=$tm;

  return $name;
}

sub
CUL_WS_Attr(@)
{
  my @a = @_;

  # Make possible to use the same code for different logical devices when they
  # are received through different physical devices.
  return if($a[0] ne "set" || $a[2] ne "IODev");
  my $hash = $defs{$a[1]};
  my $iohash = $defs{$a[3]};
  my $cde = $hash->{CODE};
  delete($defptr{$cde});
  $defptr{$iohash->{NAME} . "." . $cde} = $hash;
  return undef;
}


1;
