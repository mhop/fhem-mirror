##############################################
package main;

use strict;
use warnings;

my %defptr;

#####################################
sub
CUL_EM_Initialize($)
{
  my ($hash) = @_;

  # Message is like
  # K41350270

  $hash->{Match}     = "^E0.................\$";
  $hash->{DefFn}     = "CUL_EM_Define";
  $hash->{UndefFn}   = "CUL_EM_Undef";
  $hash->{ParseFn}   = "CUL_EM_Parse";
  $hash->{AttrList}  = "do_not_notify:0,1 showtime:0,1 model:S300TH loglevel";
}

#####################################
sub
CUL_EM_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> CUL_EM <code> [corr]"
            if(int(@a) < 3 || int(@a) > 4);
  return "Define $a[0]: wrong CODE format: valid is 1-12"
                if($a[2] !~ m/^\d$/ || $a[2] < 1 || $a[2] > 12);

  $hash->{CODE} = $a[2];
  if($a[2] >= 1 && $a[2] <= 4) {                # EMWZ: nRotation in 5 minutes
    my $c = (int(@a) > 3 ? $a[3] : 150);
    $hash->{corr} = (12/$c);
  } elsif($a[2] >= 5 && $a[2] <= 8) {           # EMEM: 0.01
    $hash->{corr} = (int(@a) > 3 ? $a[3] : 0.01);
  } else {
    $hash->{corr} = 1;
  }
  $defptr{$a[2]} = $hash;
  return undef;
}

#####################################
sub
CUL_EM_Undef($$)
{
  my ($hash, $name) = @_;
  delete($defptr{$hash->{CODE}});
  return undef;
}


#####################################
sub
CUL_EM_Parse($$)
{
  my ($hash,$msg) = @_;

  # 0123456789012345678
  # E01012471B80100B80B -> Type 01, Code 01, Cnt 10
  my @a = split("", $msg);
  my $tpe = ($a[1].$a[2])+0;
  my $cde = ($a[3].$a[4])+0;
  my $cnt = hex($a[5].$a[6]);
  my $cum = hex($a[ 9].$a[10].$a[ 7].$a[ 8]);
  my $lst = hex($a[13].$a[14].$a[11].$a[12]);
  my $top = hex($a[17].$a[18].$a[15].$a[16]);
  my $val = sprintf("CNT %d CUM: %d  5MIN: %d  TOP: %d",
                $cnt, $cum, $lst, $top);

  if($defptr{$cde}) {
    $hash = $defptr{$cde};
    my $corr = $hash->{corr};
    $cum *= $corr;
    $lst *= $corr;
    $top *= $corr;
    $val = sprintf("CNT %d  CUM: %0.3f  5MIN: %0.3f  TOP: %0.3f",
                        $cnt, $cum, $lst, $top);
    my $n = $hash->{NAME};
    Log GetLogLevel($n,1), "CUL_EM $n: $val";
    $hash->{STATE} = $val;

    $hash->{CHANGED}[0] = $val;
    $hash->{STATE} = $val;
    $hash->{READINGS}{state}{TIME} = TimeNow();
    $hash->{READINGS}{state}{VAL} = $val;

    return $hash->{NAME};

  } else {

    Log 1, "CUL_EM detected, Code $cde $val";

  }

  return "";
}

1;
