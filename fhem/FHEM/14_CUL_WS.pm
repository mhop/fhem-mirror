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
  $hash->{AttrList}  = "do_not_notify:0,1 showtime:0,1 model:S300TH loglevel";
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
  return "Define $a[0]: wrong CODE format: valid is 1-7"
                if($a[2] !~ m/^[1-7]$/);

  $hash->{CODE} = $a[2];
  $hash->{corr1} = ((int(@a) > 3) ? $a[3] : 0);
  $hash->{corr2} = ((int(@a) > 4) ? $a[4] : 0);
  $hash->{corr3} = ((int(@a) > 5) ? $a[5] : 0);
  $hash->{corr4} = ((int(@a) > 6) ? $a[6] : 0);
  $defptr{$a[2]} = $hash;
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

  if(@a == 5) {                 # 433MHz / reverse the bits
    my (@b, $ob);
    for(my $i = 0; $i<@a; $i++) {
      my $r = hex($a[$i]);
      $r = ((($r & 0x3)<<2) | (($r & 0xc)>>2));
      $r = ((($r & 0x5)<<1) | (($r & 0xa)>>1));

      if($i&1) {
        push(@b, sprintf("%X%X", $r, $ob));
      } elsif($i == (@a-1)) {
        push(@b, sprintf("%X", $r));
      } else {
        $ob = $r;
      }
    }
    @a = @b;
  }

  my $firstbyte = hex($a[1]);
  my $cde = ($firstbyte&7) + 1;

    my $type = $tlist{$a[2]} ? $tlist{$a[2]} : "unknown";
  if(!$defptr{$cde}) {
    Log 1, "CUL_WS UNDEFINED $type sensor detected, code $cde";
    return "UNDEFINED CUL_WS: $cde";
  }

  $hash = $defptr{$cde};
  my $name = $hash->{NAME};

  my $val = "";

  if(@a == 5) {                 # 433MHz RainSensor
    
    my $c = $hash->{corr1} ? $hash->{corr1} : 1;
    $val = "R: " . (hex($a[5].$a[2].$a[3]) * $c);

  } elsif(@a == 9) {            #  S300TH

    my $sgn = ($firstbyte&8) ? -1 : 1;
    my $tmp = $sgn * ($a[6].$a[3].".".$a[4]) + $hash->{corr1};
    my $hum = ($a[7].$a[8].".".$a[5]) + $hash->{corr2};
    $val = "T: $tmp  H: $hum";

  } elsif(@a == 13) {           #  WS7000 sensors


    if($type eq "brightness") {

      # TODO
      my $br = hex($a[3].$a[4].$a[5].$a[6]) + $hash->{corr1};
      $val = "B: $br";

    } elsif($type eq "temp/hum/press") {

      my $sgn = ($firstbyte&8) ? -1 : 1;
      my $tmp = $sgn * ($a[6].$a[3].".".$a[4]) + $hash->{corr1};
      my $hum = ($a[7].$a[8].".".$a[5]) + $hash->{corr2};
      my $prs = ($a[9].$a[10].".".$a[11]) + $hash->{corr3};
      $val = "T: $tmp  H: $hum  P: $prs";

    } elsif($type eq "wind") {

      # TODO
      my $wnd = hex($a[3].$a[4].$a[5].$a[6]) + $hash->{corr1};
      $val = "W: $wnd";

    } elsif($type eq "rain") {

      # TODO
      my $c = $hash->{corr1} ? $hash->{corr1} : 1;
      my $rain = hex($a[3].$a[4].$a[5].$a[6]) * $c;
      $val = "R: $rain";

    } else {

      Log 1, "CUL_WS UNKNOWN sensor detected, $msg";
      return "UNKNOWN CUL_WS: $cde";

    }

  } elsif(@a == 15) {           #  KS300/2

    my $c = $hash->{corr4} ? $hash->{corr4} : 255;
    my $rain = sprintf("%0.1f", hex("$a[14]$a[11]$a[12]") * $c / 1000);
    my $wnd  = sprintf("%0.1f", "$a[9]$a[10].$a[7]" + $hash->{corr3});
    my $hum  = sprintf( "%02d", "$a[8]$a[5]" + $hash->{corr2});
    my $tmp  = sprintf("%0.1f", ("$a[6]$a[3].$a[4]"+$hash->{corr1}) *
                                (($a[3] & 8) ? -1 : 1));
    my $ir = ((hex($a[1]) & 0x2)) ? "yes" : "no";

    $val = "T: $tmp  H: $hum  W: $wnd  R: $rain  IR: $ir";

  } else {

    Log 1, "CUL_WS UNKNOWN sensor detected, $msg";
    return "UNKNOWN CUL_WS: $cde";

  }

  Log GetLogLevel($name,4), "CUL_WS $name: $val";

  $hash->{STATE} = $val;                      # List overview
  $hash->{READINGS}{state}{TIME} = TimeNow(); # For list
  $hash->{READINGS}{state}{VAL} = $val;
  $hash->{CHANGED}[0] = $val;                 # For notify

  return $name;
}

1;
