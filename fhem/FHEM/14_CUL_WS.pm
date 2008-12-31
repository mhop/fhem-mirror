##############################################
package main;

use strict;
use warnings;

my %defptr;

# Supports following devices:
# KS300TH     (this is redirected to the more sophisticated 14_KS300 by 00_CUL)
# S300TH  
#
#
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
  $hash->{ParseFn}   = "CUL_WS_Parse";
  $hash->{AttrList}  = "do_not_notify:0,1 showtime:0,1 model:S300TH,KS300 loglevel";
}


#####################################
sub
CUL_WS_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> CUL_WS <code> [corr1...corr4]"
            if(int(@a) < 3 || int(@a) > 6);
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
  my %tlist = ("2"=>"rain",
               "3"=>"wind",
               "4"=>"temp/hum/press",
               "5"=>"brightness");


  my @a = split("", $msg);

  my $firstbyte = hex($a[1]);
  my $cde = ($firstbyte&7) + 1;
  my $type = $tlist{$a[2]} ? $tlist{$a[2]} : "unknown";

  if(!$defptr{$cde}) {
    Log 1, "CUL_WS UNDEFINED $type sensor detected, code $cde";
    return "UNDEFINED CUL_WS: $cde";
  }

  $hash = $defptr{$cde};
  my $name = $hash->{NAME};
  my $typbyte = hex($a[2]) & 7;
  my $sfirstbyte = $firstbyte & 7;
  my $val = "";
  my $devtype = "unknown";

  if($sfirstbyte == 7) {


    if($typbyte == 0) {
      my $sgn = ($firstbyte&8) ? -1 : 1;
      my $tmp = $sgn * ($a[6].$a[3].".".$a[4]) + $hash->{corr1};
      $val = "T: $tmp";
      $devtype = "CUL_WS WS7000 Temp";
     
    }

    if($typbyte == 1) {
      my $sgn = ($firstbyte&8) ? -1 : 1;
      my $tmp = $sgn * ($a[6].$a[3].".".$a[4]) + $hash->{corr1};
      my $hum = ($a[7].$a[8].".".$a[5]) + $hash->{corr2};
      $val = "T: $tmp  H: $hum";
      $devtype = "CUL_WS WS7000 Temp/Hum";
    }

    if($typbyte == 2) {
      #my $more = ($firstbyte&8) ? 0 : 1000;
      my $c = $hash->{corr1} ? $hash->{corr1} : 1;
      my $hexcount = hex($a[5].$a[3].$a[4]) + $c;
      $val = "R: $hexcount";
      $devtype =  "CUL_WS WS7000 Rain";
    }

    if($typbyte == 3) {
      my $hun = ($firstbyte&8) ? 100 : 0;
      my $speed = ($a[6].$a[3].".".$a[4])+$hun;
      my $dir  = (($a[7]&3).$a[8].$a[5])+0;
      my $swing = ($a[7]&6) >> 2;
      $val = "W: $speed D: $dir A: $swing";
      $devtype = "CUL_WS WS7000 Wind";
    }

    if($typbyte == 4) {
      my $sgn = ($firstbyte&8) ? -1 : 1;
      my $tmp = $sgn * ($a[6].$a[3].".".$a[4]) + $hash->{corr1};
      my $hum = ($a[7].$a[8].".".$a[5]) + $hash->{corr2};
      my $prs = ($a[9].$a[10])+ 900 + $hash->{corr3};
      if ($prs < 930) {
         $prs = $prs + 100;
      }
      if(@a == 13) {
        $val = "T: $tmp  H: $hum  P: $prs";
      } else {
        $val = "T: $tmp  H: $hum  P: $prs lenerr";
      }
      $devtype = "CUL_WS WS7000 Indoor";
    }

    if($typbyte == 5) {
      my $fakt = 1;
      my $rawfakt = ($a[5])+0;
      if($rawfakt == 1) { $fakt =   10; }
      if($rawfakt == 2) { $fakt =  100; }
      if($rawfakt == 3) { $fakt = 1000; }
     
      my $br = (hex($a[5].$a[4].$a[3])*$fakt)  + $hash->{corr1};
      $val = "B: $br";
      $devtype = "CUL_WS WS7000 Brightness";
    }

    if($typbyte == 6) {                   #wurde nie gebaut
      $devtype = "CUL_WS WS7000 Pyro";
    }
    if($typbyte == 7) {
      $devtype = "CUL_WS unknown";
    }

  } else {

    if(@a == 9) {            #  S300TH

      my $sgn = ($firstbyte&8) ? -1 : 1;
      my $tmp = $sgn * ($a[6].$a[3].".".$a[4]) + $hash->{corr1};
      my $hum = ($a[7].$a[8].".".$a[5]) + $hash->{corr2};
      $val = "T: $tmp  H: $hum";
      $devtype = "S300TH";

    } elsif(@a == 15) {           #  KS300/2

      my $c = $hash->{corr4} ? $hash->{corr4} : 255;
      my $rain = sprintf("%0.1f", hex("$a[14]$a[11]$a[12]") * $c / 1000);
      my $wnd  = sprintf("%0.1f", "$a[9]$a[10].$a[7]" + $hash->{corr3});
      my $hum  = sprintf( "%02d", "$a[8]$a[5]" + $hash->{corr2});
      my $tmp  = sprintf("%0.1f", ("$a[6]$a[3].$a[4]"+$hash->{corr1}) *
                                (($a[1] & 0xC) ? -1 : 1));
      my $ir = ((hex($a[1]) & 2)) ? "yes" : "no";

      $val = "T: $tmp  H: $hum  W: $wnd  R: $rain  IR: $ir";
      $devtype = "KS300/2";

    } 

  }

  Log GetLogLevel($name,4), "CUL_WS $devtype sensor $name: $val";

  $hash->{STATE} = $val;                      # List overview
  $hash->{READINGS}{state}{TIME} = TimeNow(); # For list
  $hash->{READINGS}{state}{VAL} = $val;
  $hash->{CHANGED}[0] = $val;                 # For notify

  return $name;
}

1;
