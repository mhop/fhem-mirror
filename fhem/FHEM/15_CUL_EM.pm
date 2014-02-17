##############################################
# $Id$
package main;

use strict;
use warnings;

# Adjust TOTAL to you meter:
# {$defs{emwz}{READINGS}{basis}{VAL}=<meter>/<corr2>-<total_cnt> }

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
  $hash->{AttrList}  = "IODev do_not_notify:0,1 showtime:0,1 " .
                        "model:EMEM,EMWZ,EMGZ ignore:0,1 ".
                        $readingFnAttributes;
  $hash->{AutoCreate}=
        { "CUL_EM.*" => { GPLOT => "power8:Power,", FILTER => "%NAME:CNT.*" } };
}

#####################################
sub
CUL_EM_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> CUL_EM <code> ".
                                "[corr1 corr2 CostPerUnit BasicFeePerMonth]"
            if(int(@a) < 3 || int(@a) > 7);
  return "Define $a[0]: wrong CODE format: valid is 1-12"
                if($a[2] !~ m/^\d+$/ || $a[2] < 1 || $a[2] > 12);

  $hash->{CODE} = $a[2];

  if($a[2] >= 1 && $a[2] <= 4) {                # EMWZ: nRotation in 5 minutes
    my $c = (int(@a) > 3 ? $a[3] : 150);
    $hash->{corr1} = (12/$c);                   # peak/current
    $c = (int(@a) > 4 ? $a[4] : 1800);
    $hash->{corr2} = (12/$c);                   # total

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
  $hash->{CostPerUnit} = (int(@a) > 5 ? $a[5] : 0);
  $hash->{BasicFeePerMonth} = (int(@a) > 6 ? $a[6] : 0);

  $modules{CUL_EM}{defptr}{$a[2]} = $hash;
  AssignIoPort($hash);
  return undef;
}

#####################################
sub
CUL_EM_Undef($$)
{
  my ($hash, $name) = @_;
  delete($modules{CUL_EM}{defptr}{$hash->{CODE}});
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
  my $cde = hex($a[3].$a[4]);

  # seqno    =  number of received datagram in sequence, runs from 2 to 255
  # total_cnt=  total (cumulated) value in ticks as read from the device
  # basis_cnt=  correction to total (cumulated) value in ticks to account for
  #             counter wraparounds
  # total    =  total (cumulated) value in device units
  # current  =  current value (average over latest 5 minutes) in device units
  # peak     =  maximum value in device units

  my $seqno = hex($a[5].$a[6]);
  my $total_cnt = hex($a[ 9].$a[10].$a[ 7].$a[ 8]);
  my $current_cnt = hex($a[13].$a[14].$a[11].$a[12]);
  my $peak_cnt = hex($a[17].$a[18].$a[15].$a[16]);

  # these are the raw readings from the device
  my $val = sprintf("CNT: %d CUM: %d  5MIN: %d  TOP: %d",
                         $seqno, $total_cnt, $current_cnt, $peak_cnt);

  if($modules{CUL_EM}{defptr}{$cde}) {
    my $def = $modules{CUL_EM}{defptr}{$cde};
    $hash = $def;
    my $n = $hash->{NAME};
    return "" if(IsIgnored($n));

    my $tn = TimeNow();                 # current time
    my $c= 0;                           # count changes
    my %readings;

    Log3 $n, 5, "CUL_EM $n: $val";
    $readings{RAW} = $val;

    #
    # calculate readings
    #
    # initialize total_cnt_last
    my $total_cnt_last = 0;
    if(defined($hash->{READINGS}{total_cnt})) {
      $total_cnt_last= $hash->{READINGS}{total_cnt}{VAL};
    }


    # initialize basis_cnt_last
    my $basis_cnt = 0;
    if(defined($hash->{READINGS}{basis})) {
      $basis_cnt = $hash->{READINGS}{basis}{VAL};
    }

    # correct counter wraparound
    if($total_cnt < $total_cnt_last) {
      # check: real wraparound or reset only
      $basis_cnt += ($total_cnt_last > 65000 ? 65536 : $total_cnt_last);
      $readings{basis} = $basis_cnt;
    }

    #
    # translate into device units
    #
    my $corr1 = $hash->{corr1}; # EMEM power correction factor
    my $corr2 = $hash->{corr2}; # EMEM energy correction factor

    my $total    = ($basis_cnt+$total_cnt)*$corr2;
    my $current  = $current_cnt*$corr1;
    my $peak     = $peak_cnt*$corr1;

    if($tpe ne 2) {
      $peak      = 3000/($peak_cnt > 1 ? $peak_cnt : 1)*$corr1;
      $peak      = ($current > 0 ? $peak : 0);
    }


    $val = sprintf("CNT: %d CUM: %0.3f  5MIN: %0.3f  TOP: %0.3f",
                         $seqno, $total, $current, $peak);
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "state", $val);

    $readings{total_cnt}   = $total_cnt;
    $readings{current_cnt} = $current_cnt;
    $readings{peak_cnt}    = $peak_cnt;
    $readings{seqno}       = $seqno;
    $readings{total}       = $total;
    $readings{current}     = $current;
    $readings{peak}        = $peak;


    ###################################
    # Start CUMULATE day and month
    Log3 $n, 4, "CUL_EM $n: $val";
    my $tsecs_prev;

    #----- get previous tsecs
    if(defined($hash->{READINGS}{tsecs})) {
      $tsecs_prev= $hash->{READINGS}{tsecs}{VAL};
    } else {
      $tsecs_prev= 0; # 1970-01-01
    }

    #----- save actual tsecs
    my $tsecs= time();  # number of non-leap seconds since January 1, 1970, UTC
    $readings{tsecs}       = $tsecs;

    #----- get cost parameter
    my $cost = $hash->{CostPerUnit};
    my $basicfee = $hash->{BasicFeePerMonth};

    #----- check whether day or month was changed
    if(!defined($hash->{READINGS}{cum_day})) {
      #----- init cum_day if it is not set
      $val = sprintf("CUM_DAY: %0.3f CUM: %0.3f COST: %0.2f", 0,$total,0);
      $readings{cum_day}   = $val;

    } else {

      if( (localtime($tsecs_prev))[3] != (localtime($tsecs))[3] ) {
        #----- day has changed (#3)
        my @cmv = split(" ", $hash->{READINGS}{cum_day}{VAL});
        $val = sprintf("CUM_DAY: %0.3f CUM: %0.3f COST: %0.2f",
                        $total-$cmv[3], $total, ($total-$cmv[3])*$cost);
        $readings{cum_day} = $val;
        Log3 $n, 3, "CUL_EM $n: $val";


        if( (localtime($tsecs_prev))[4] != (localtime($tsecs))[4] ) {

          #----- month has changed (#4)
          if(!defined($hash->{READINGS}{cum_month})) {
            # init cum_month if not set
            $val = sprintf("CUM_MONTH: %0.3f CUM: %0.3f COST: %0.2f",
                       0, $total, 0);
            $readings{cum_month} = $val;

          } else {
            @cmv = split(" ", $hash->{READINGS}{cum_month}{VAL});
            $val = sprintf("CUM_MONTH: %0.3f CUM: %0.3f COST: %0.2f",
                       $total-$cmv[3], $total,($total-$cmv[3])*$cost+$basicfee);
            $readings{cum_month} = $val;
            Log3 $n, 3, "CUL_EM $n: $val";

          }
        }
      }
    }
    # End CUMULATE day and month
    ###################################


    foreach my $k (keys %readings) {
      readingsBulkUpdate($hash, $k, $readings{$k});
    }
    readingsEndUpdate($hash, 1);
    return $hash->{NAME};

  } else {

    Log3 $hash, 1, "CUL_EM detected, Code $cde $val";
    return "UNDEFINED CUL_EM_$cde CUL_EM $cde";

  }

}

1;


=pod
=begin html

<a name="CUL_EM"></a>
<h3>CUL_EM</h3>
<ul>
  The CUL_EM module interprets EM type of messages received by the CUL, notably
  from EMEM, EMWZ or EMGZ devices.
  <br><br>

  <a name="CUL_EMdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; CUL_EM &lt;code&gt; [corr1 corr2
                CostPerUnit BasicFeePerMonth]</code> <br>
    <br>
    &lt;code&gt; is the code which must be set on the EM device. Valid values
    are 1 through 12. 1-4 denotes EMWZ, 5-8 EMEM and 9-12 EMGZ devices.<br><br>

    <b>corr1</b> is used to correct the current number, <b>corr2</b>
    for the total number.
    <ul>
      <li>for EMWZ devices you should specify the rotation speed (R/kW)
          of your watt-meter (e.g. 150) for corr1 and 12 times this value for
          corr2</li>
      <li>for EMEM devices the corr1 value is 0.01, and the corr2 value is
          0.001 </li>
    </ul>
    <br>

    <b>CostPerUnit</b> and <b>BasicFeePerMonth</b> are used to compute your
    daily and mothly fees. Your COST will appear in the log, generated once
    daiy (without the basic fee) or month (with the bassic fee included). Your
    definition should look like E.g.:
    <ul><code>
    define emwz 1 75 900 0.15 12.50<br>
    </code></ul>
    and the Log looks like:
    <ul><code>
    CUM_DAY: 6.849 CUM: 60123.4 COST: 1.02<br>
    CUM_MONTH: 212.319 CUM: 60123.4 COST: 44.34<br>
    </code></ul>

    Tip: You can configure your EMWZ device to show in the CUM column of the
    STATE reading the current reading of your meter. For this purpose: multiply
    the current reading (from the real device) with the corr1 value (RperKW),
    and substract the RAW CUM value from it. Now set the basis reading of your
    EMWZ device (named emwz) to this value.<br>

  </ul>
  <br>

  <a name="CUL_EMset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="CUL_EMget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="CUL_EMattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#ignore">ignore</a></li><br>
    <li><a href="#do_not_notify">do_not_notify</a></li><br>
    <li><a href="#showtime">showtime</a></li><br>
    <li><a href="#model">model</a> (EMEM,EMWZ,EMGZ)</li><br>
    <li><a href="#IODev">IODev</a></li><br>
    <li><a href="#eventMap">eventMap</a></li><br>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>
</ul>

=end html

=begin html_DE

<a name="CUL_EM"></a>
<h3>CUL_EM</h3>
<ul>
  Das Modul CUL_EM wertet von einem CUL empfange Botschaften des Typs EM aus, 
  dies sind aktuell Botschaften von EMEM, EMWZ bzw. EMGZ Ger&auml;ten.
  <br><br>

  <a name="CUL_EMdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; CUL_EM &lt;code&gt; [corr1 corr2
                CostPerUnit BasicFeePerMonth]</code> <br>
    <br>
    &lt;code&gt; ist der Code, der am EM Ger&auml;t eingestellt wird. G&uuml;tige Werte sind
    1 bis 12. 1-4 gilt f&uuml;r EMWZ, 5-8 f&uuml;r EMEM und 9-12 f&uuml;r EMGZ Ger&auml;te.<br><br>

    <b>corr1</b> ist der Kalibrierfaktor f&uuml;r den Momentanverbrauch, <b>corr2</b>
    f&uuml;r den Gesamtverbrauch.
    <ul>
      <li>f&uuml;r EMWZ Ger&auml;te wird die Umdrehungsgeschwindigkeit (U/kW)
          des verwendeten Stromz&auml;hlers (z.B. 150) f&uuml;r corr1 und 12 mal 
          diesen Wert f&uuml;r corr2 verwendet</li>
      <li>f&uuml;r EMEM devices ist corr1 mit 0.01 und corr2 mit 0.001 anzugeben</li>
    </ul>
    <br>

    <b>CostPerUnit</b> und <b>BasicFeePerMonth</b> werden dazu verwendet, die 
    t&auml;gliche bzw. monatliche Kosten zu berechnen. Die Kosten werden in der 
    Logdatei einmal t&auml;glich (ohne Fixkosten) bzw. monatlich (mit Fixkosten) 
    generiert und angezeigt.
    Die Definition sollte in etwa so aussehen:
    <ul><code>
    define emwz 1 75 900 0.15 12.50<br>
    </code></ul>
    und in der Logdatei sollten diese Zeilen erscheinen:
    <ul><code>
    CUM_DAY: 6.849 CUM: 60123.4 COST: 1.02<br>
    CUM_MONTH: 212.319 CUM: 60123.4 COST: 44.34<br>
    </code></ul>

    Tipp: Das EMWZ Ger&auml;t kann so konfiguriert werden, dass es in der CUM Spalte
    des STATE Wertes den aktuellen Wert des Stromz&auml;hlers anzeigt. 
    Hierf&uuml;r muss der aktuell am Stromz&auml;hler abgelesene Wert mit corr1 (U/kW) 
    multipliziert werden und der CUM Rohwert aus der aktuellen fhem Messung ('reading') 
    davon abgezogen werden. Dann muss dieser Wert als Basiswert des EMWZ Ger&auml;tes 
    (im Beispiel emwz) gesetzt werden.<br>

  </ul>
  <br>

  <a name="CUL_EMset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="CUL_EMget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="CUL_EMattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#ignore">ignore</a></li><br>
    <li><a href="#do_not_notify">do_not_notify</a></li><br>
    <li><a href="#showtime">showtime</a></li><br>
    <li><a href="#model">model</a> (EMEM,EMWZ,EMGZ)</li><br>
    <li><a href="#IODev">IODev</a></li><br>
    <li><a href="#eventMap">eventMap</a></li><br>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>
</ul>

=end html_DE
=cut
