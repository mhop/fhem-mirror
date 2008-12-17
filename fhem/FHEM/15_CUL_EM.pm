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
  $hash->{AttrList}  = "do_not_notify:0,1 showtime:0,1 model:EMEM,EMWZ,EMGZ loglevel";
}

#####################################
sub
CUL_EM_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> CUL_EM <code> [corr1 corr2]"
            if(int(@a) < 3 || int(@a) > 5);
  return "Define $a[0]: wrong CODE format: valid is 1-12"
                if($a[2] !~ m/^\d$/ || $a[2] < 1 || $a[2] > 12);

  $hash->{CODE} = $a[2];

  if($a[2] >= 1 && $a[2] <= 4) {                # EMWZ: nRotation in 5 minutes
    my $c = (int(@a) > 3 ? $a[3] : 150);
    $hash->{corr1} = (12/$c);
    $hash->{corr2} = (12/$c);

  } elsif($a[2] >= 5 && $a[2] <= 8) {           # EMEM
    # corr1 is the correction factor for power
    $hash->{corr1} = (int(@a) > 3 ? $a[3] : 0.01);
    # corr2 is the correction factor for energy
    $hash->{corr2} = (int(@a) > 4 ? $a[4] : 0.001);

  } elsif($a[2] >= 9 && $a[2] <= 12) {          # EMGZ: 0.01
    $hash->{corr1} = (int(@a) > 3 ? $a[3] : 0.01);
    $hash->{corr2} = (int(@a) > 4 ? $a[4] : 0.01);

  } else {
    $hash->{corr1} = 1;
    $hash->{corr2} = 1;
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
  my $seqno = hex($a[5].$a[6]);
  my $total_cnt = hex($a[ 9].$a[10].$a[ 7].$a[ 8]);
  my $current_cnt = hex($a[13].$a[14].$a[11].$a[12]);
  my $peak_cnt = hex($a[17].$a[18].$a[15].$a[16]);

  # these are the raw readings from the device
  my $val = sprintf("CNT: %d CUM: %d  5MIN: %d  TOP: %d",
                $seqno, $total_cnt, $current_cnt, $peak_cnt);


  # seqno    =  number of received datagram in sequence, runs from 2 to 255
  # total_cnt=  total (cumulated) value in ticks as read from the device
  # basis_cnt=  correction to total (cumulated) value in ticks to account for
  #             counter wraparounds
  # total    =  total (cumulated) value in device units
  # current  =  current value (average over latest 5 minutes) in device units
  # peak     =  maximum value in device units

  if($defptr{$cde}) {
    $hash = $defptr{$cde};


    # count changes
    my $c= 0;

    # set state to raw readings
    my $n = $hash->{NAME};
    Log GetLogLevel($n,1), "CUL_EM $n: $val";
    $hash->{STATE} = $val;
    $hash->{CHANGED}[$c++] = $val;


    #
    # calculate readings
    #

    # current time
    my $tn = TimeNow();

    # update sequence number reading
    $hash->{READINGS}{seqno}{TIME} = $tn;
    $hash->{READINGS}{seqno}{VAL} = $seqno;
    $hash->{CHANGED}[$c++] = "seqno: $seqno";

    # update raw readings
    $hash->{READINGS}{state}{TIME} = $tn;
    $hash->{READINGS}{state}{VAL} = $val;
    $hash->{CHANGED}[$c++] = "state: $val";

    # initialize total_cnt_last
    my $total_cnt_last;
    if(defined($hash->{READINGS}{total_cnt})) {
        $total_cnt_last= $hash->{READINGS}{total_cnt}{VAL};
    } else {
        $total_cnt_last= 0;
    }

    # update total_cnt reading
    $hash->{READINGS}{total_cnt}{TIME} = $tn;
    $hash->{READINGS}{total_cnt}{VAL} = $total_cnt;
    $hash->{CHANGED}[$c++] = "total_cnt: $total_cnt";

    # initialize basis_cnt_last
    my $basis_cnt_last;
    if(defined($hash->{READINGS}{basis})) {
        $basis_cnt_last= $hash->{READINGS}{basis}{VAL};
    } else {
        $basis_cnt_last= 0;
    }

    # correct counter wraparound
    my $basis_cnt= $basis_cnt_last;
    if($total_cnt< $total_cnt_last) {
        $basis_cnt+= 65536;
        # update basis_cnt
        $hash->{READINGS}{basis}{TIME}= $tn;
        $hash->{READINGS}{basis}{VAL} = $basis_cnt;
        $hash->{CHANGED}[$c++] = "basis: $basis_cnt";
    }

    #
    # translate into device units
    #
    my $corr1 = $hash->{corr1}; # EMEM power correction factor
    my $corr2 = $hash->{corr2}; # EMEM energy correction factor

    my $total    = ($basis_cnt+$total_cnt)*$corr2;
    my $current  = $current_cnt*$corr1;
    my $peak     = $peak_cnt*$corr1;

    $hash->{CHANGED}[$c++] = "total: $total";
    $hash->{READINGS}{total}{TIME} = $tn;
    $hash->{READINGS}{total}{VAL} = $total;
    $hash->{CHANGED}[$c++] = "current: $current";
    $hash->{READINGS}{current}{TIME} = $tn;
    $hash->{READINGS}{current}{VAL} = $current;
    $hash->{CHANGED}[$c++] = "peak: $peak";
    $hash->{READINGS}{peak}{TIME} = $tn;
    $hash->{READINGS}{peak}{VAL} = $peak;

    return $hash->{NAME};

  } else {

    Log 1, "CUL_EM detected, Code $cde $val";

  }

  return "";
}

1;
