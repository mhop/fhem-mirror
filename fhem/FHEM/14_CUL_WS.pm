##############################################
package main;

use strict;
use warnings;

my %defptr;

#####################################
sub
CUL_WS_Initialize($)
{
  my ($hash) = @_;

  # Message is like
  # K41350270

  $hash->{Match}     = "^K(........|............)\$";
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

  return "wrong syntax: define <name> CUL_WS <code> [corr1 [corr2]]"
            if(int(@a) < 3 || int(@a) > 5);
  $a[2] = lc($a[2]);
  return "Define $a[0]: wrong CODE format: valid is 1-7"
                if($a[2] !~ m/^[1-7]$/);

  $hash->{CODE} = $a[2];
  $hash->{corr1} = ((int(@a) > 3) ? $a[3] : 0);
  $hash->{corr2} = ((int(@a) > 4) ? $a[4] : 0);
  $defptr{$a[2]} = $hash;
  return undef;
}

#####################################
sub
CUL_WS_Undef($$)
{
  my ($hash, $name) = @_;
  delete($defptr{$hash->{CODE}});
  return undef;
}


#####################################
sub
CUL_WS_Parse($$)
{
  my ($hash,$msg) = @_;
  my %tlist = ("2"=>"rain","3"=>"wind","4"=>"temp/hum/press","5"=>"brightness");

  # 0123456789012
  # K41505268        -> Code (4+1) 5, T: 25.0  H: 68.5
  # K............

  my @a = split("", $msg);
  my $firstbyte = hex($a[1]);
  my $cde = ($firstbyte&7) + 1;

  my $type = "Temp/Hum";
  if(@a == 13) {
    $type = $tlist{$a[2]} ? $tlist{$a[2]} : "unknown";
  }

  if(!$defptr{$cde}) {
    Log 1, "CUL_WS UNDEFINED $type sensor detected, code $cde";
    return "UNDEFINED CUL_WS: $cde";
  }

  if(@a == 9) {

    $hash = $defptr{$cde};
    my $name = $hash->{NAME};

    my $sgn = ($firstbyte&8) ? -1 : 1;
    my $tmp = $sgn * ($a[6].$a[3].".".$a[4]) + $hash->{corr1};
    my $hum = ($a[7].$a[8].".".$a[5]) + $hash->{corr2};
    my $val = "T: $tmp  H: $hum";

    Log GetLogLevel($name,4), "CUL_WS $name: $val";

    $hash->{STATE} = $val;                      # List overview
    $hash->{READINGS}{state}{TIME} = TimeNow(); # For list
    $hash->{READINGS}{state}{VAL} = $val;

    $hash->{CHANGED}[0] = $val;                 # For notify

    return $name;

  } else {

  }

  return "";
}

1;
