#############################################
# $Id$
package main;

use strict;
use warnings;

sub
FHT8V_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}     = "FHT8V_Define";
  $hash->{SetFn}     = "FHT8V_Set";
  $hash->{GetFn}     = "FHT8V_Get";
  $hash->{AttrList}  = "IODev dummy:1,0 ignore:1,0 ".
                         $readingFnAttributes;
}

#############################
sub
FHT8V_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $n = $a[0];

  return "wrong syntax: define <name> FHT8V housecode [IODev|FHTID]" if(@a < 3);
  return "wrong housecode format: specify a 4 digit hex value "
  		if(($a[2] !~ m/^[a-f0-9]{4}$/i));

  my $fhtid;
  if(@a > 3 && $defs{$a[3]}) {
    $hash->{IODev} = $defs{$a[3]};

  } else {
    AssignIoPort($hash);
    $fhtid = $a[3] if($a[3]);
  }

  return "$n: No IODev found" if(!$hash->{IODev});
  $fhtid = $hash->{IODev}->{FHTID} if(!$fhtid);

  return "$n: Wrong IODev $hash->{IODev}{NAME}, has no FHTID" if(!$fhtid);

  #####################
  # Check if the address corresponds to the CUL
  my $ioaddr = hex($fhtid);
  my $myaddr = hex($a[2]);
  my ($io1, $io0) = (int($ioaddr/255), $ioaddr % 256);
  my ($my1, $my0) = (int($myaddr/255), $myaddr % 256);
  if($my1 < $io1 || $my1 > $io1+7 || $io0 != $my0) {
    my $vals = "";
    for(my $m = 0; $m <= 7; $m++) {
      $vals .= sprintf(" %2x%2x", $io1+$m, $io0);
    }
    return sprintf("Wrong housecode: must be one of$vals");
  }

  $hash->{addr} = uc($a[2]);
  $hash->{idx}  = sprintf("%02X", $my1-$io1);
  $hash->{STATE} = "defined";
  return "";
}


sub
FHT8V_Set($@)
{
  my ($hash, @a) = @_;
  my $n = $hash->{NAME};

  return "Need a parameter for set" if(@a < 2);
  my $arg = $a[1];

  if($arg eq "valve" ) {
    return "Set valve needs a numeric parameter between 0 and 100"
        if(@a != 3 || $a[2] !~ m/^\d+$/ || $a[2] < 0 || $a[2] > 100);
    Log3 $n, 3, "FHT8V set $n $arg $a[2]";
    $hash->{STATE} = sprintf("%d %%", $a[2]);
    IOWrite($hash, "", sprintf("T%s0026%02X", $hash->{addr}, $a[2]*2.55));

  } elsif ($arg eq "pair" ) {
    Log3 $n, 3, "FHT8V set $n $arg";
    IOWrite($hash, "", sprintf("T%s002f00", $hash->{addr}));

  } elsif ($arg eq "decalc" ) {
    Log3 $n, 3, "FHT8V set $n $arg";
    $hash->{STATE} = "lime-protection";
    IOWrite($hash, "", sprintf("T%s000A00", $hash->{addr}));

  } else {
    return "Unknown argument $a[1], choose one of valve pair decalc"

  }
  return "";

}

sub
FHT8V_Get($@)
{
  my ($hash, @a) = @_;
  my $n = $hash->{NAME};

  return "Need a parameter for get" if(@a < 2);
  my $arg = $a[1];

  if($arg eq "valve" ) {
    my $io = $hash->{IODev};
    my $msg = CallFn($io->{NAME}, "GetFn", $io, (" ", "raw", "T10"));
    my $idx = $hash->{idx};
    return int(hex($1)/2.55) if($msg =~ m/$idx:26(..)/);
    return "N/A";

  }
  return "Unknown argument $a[1], choose one of valve"
}


1;

=pod
=begin html

<a name="FHT8V"></a>
<h3>FHT8V</h3>
<ul>
  Fhem can directly control FHT8V type valves via a <a href="#CUL">CUL</a>
  device without an intermediate FHT. This paragraph documents one of the
  building blocks, the other is the <a href="#PID">PID</a> device.
  <br>
  <br>

  <a name="FHT8Vdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FHT &lt;housecode&gt; [IODev|FHTID]</code>
    <br><br>

    <code>&lt;housecode&gt;</code> is a four digit hex number,
    and must have the following relation to the housecode of the corresponding CUL
    device:
    <ul>given the CUL housecode as AABB, then this housecode must be
    of the form CCBB, where CC is greater or equal to AA, but less then AA+8.
    </ul>
    This form is chosen so that the CUL can update all FHT8V valve states
    within 2 minutes.
    <br>
    <br>
    <code>&lt;IODev&gt;</code> must be specified if the last defined CUL device
    is not the one to use. Usually this is done voa the <a
    href="#IODev">IODev</a> attribute, but as the address checked is performed
    at the definition, we must use an exception here.<br>

    As an alternative you can specify the FHTID of the assigned IODev device
    (instead of the IODev itself), this method is needed if you are using FHT8V
    through FHEM2FHEM.
    <br>

    Examples:
    <ul>
      <code>define wz FHT8V 3232</code><br>
    </ul>
  </ul>
  <br>

  <a name="FHT8Vset"></a>
  <b>Set </b>
  <ul>
      <li>set &lt;name&gt; valve &lt;value;&gt;<br>
        Set the valve to the given value (in percent, from 0 to 100).
        </li>
      <li>set &lt;name&gt; pair<br>
        Pair the valve with the CUL.
        </li>
      <li>set &lt;name&gt; decalc<br>
        Start a decalcifying cycle on the given valve
        </li>
  </ul>
  <br>

  <a name="FHT8Vget"></a>
  <b>Get </b>
  <ul>
      <li>get &lt;name&gt; valve<br>
      Read back the valve position from the CUL FHT buffer, and convert it to percent (from 0 to 100).
      </li>
  </ul>
  <br>

  <a name="FHT8Vattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#IODev">IODev</a></li>
    <li><a href="#dummy">dummy</a></li>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#eventMap">eventMap</a></li><br>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>
</ul>


=end html
=cut
