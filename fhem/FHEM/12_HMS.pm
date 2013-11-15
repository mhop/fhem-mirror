##############################################
# $Id$
package main;

use strict;
use warnings;

my %codes = (
  "0" => "HMS100TF",
  "1" => "HMS100T",
  "2" => "HMS100WD",
  "3" => "RM100-2",
  "4" => "HMS100TFK", # Depending on the onboard jumper it is 4 or 5
  "5" => "HMS100TFK",
  "6" => "HMS100MG",
  "8" => "HMS100CO",
  "e" => "HMS100FIT",
);


#####################################
sub
HMS_Initialize($)
{
  my ($hash) = @_;

#                        810e047e0510a001473a000000120233 HMS100TF
#                        810e04b90511a0018e63000001100000 HMS100T
#                        810e04e80212a001ec46000001000000 HMS100WD
#                        810e04d70213a001b16d000003000000 RM100-2
#                        810e047f0214a001a81f000001000000 HMS100TFK
#                        810e048f0295a0010155000001000000 HMS100TFK (jumper)
#                        810e04330216a001b4c5000001000000 HMS100MG
#                        810e04210218a00186e0000000000000 HMS100CO
#                        810e0448029ea00132d5000000000000 FI-Trenner

  $hash->{Match}     = "^810e04....(1|5|9).a001";
  $hash->{DefFn}     = "HMS_Define";
  $hash->{UndefFn}   = "HMS_Undef";
  $hash->{ParseFn}   = "HMS_Parse";
  $hash->{AttrList}  = "IODev do_not_notify:0,1 showtime:0,1 model:hms100-t,hms100-tf,hms100-wd,hms100-mg,hms100-tfk,rm100-2,hms100-co,hms100-fit ignore:0,1 $readingFnAttributes";
  $hash->{AutoCreate}= {
      "HMS100TFK_.*" => 
        { GPLOT => "fht80tf:Contact,", FILTER => "%NAME" },
      "HMS100T[F]?_.*" =>
        { GPLOT => "temp4hum6:Temp/Hum,", FILTER => "%NAME:T:.*" }
  };
}

#####################################
sub
HMS_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> HMS CODE" if(int(@a) != 3);
  $a[2] = lc($a[2]);
  return "Define $a[0]: wrong CODE format: specify a 4 digit hex value"
  		if($a[2] !~ m/^[a-f0-9][a-f0-9][a-f0-9][a-f0-9]$/);


  $hash->{CODE} = $a[2];
  $modules{HMS}{defptr}{$a[2]} = $hash;
  AssignIoPort($hash);
  return undef;
}

#####################################
sub
HMS_Undef($$)
{
  my ($hash, $name) = @_;
  delete($modules{HMS}{defptr}{$hash->{CODE}})
        if(defined($hash->{CODE}) &&
           defined($modules{HMS}{defptr}{$hash->{CODE}}));
  return undef;
}

#####################################
sub
HMS_Parse($$)
{
  my ($hash, $msg) = @_;

  my $dev = substr($msg, 16, 4);
  my $cde = substr($msg, 11, 1);
#                        012345678901234567890123456789
#                        810e047f0214a001a81f000001000000 HMS100TFK
  my $val = substr($msg, 24, 8) if(length($msg) == 32);
  if(!defined($val)) {
    Log3 $hash, 3, "Strange HMS message $msg";
    return "";
  }

  my $type = "";
  foreach my $c (keys %codes) {
    if($cde =~ m/$c/) {
      $type = $codes{$c};
      last;
    }
  }

  # As the HMS devices change their id on each battery change, we offer
  # a wildcard too for each type:  100<device-code>,
  my $odev = $dev;
  if(!defined($modules{HMS}{defptr}{$dev})) {
    Log3 $hash, 4,
        "HMS device $dev not defined, using the wildcard device 100$cde";
    $dev = "100$cde";
  }

  if(!defined($modules{HMS}{defptr}{$dev})) {
    Log3 $hash, 3, "Unknown HMS device $dev/$odev, please define it";
    $type = "HMS" if(!$type);
    $type =~ s/-//; # RM100-2, - is special in fhem names
    return "UNDEFINED ${type}_$odev HMS $odev";
  }

  my $def = $modules{HMS}{defptr}{$dev};
  my $name = $def->{NAME};
  return "" if(IsIgnored($name));

  my (@v, @txt);

  # Used for HMS100TF & HMS100T
  my $batstr1 = "ok";
  my $status1 = hex(substr($val, 0, 1));
  $batstr1 = "empty"    if( $status1 & 2 );
  $batstr1 = "replaced" if( $status1 & 4 );

  # Used for the other devices
  my $batstr2 = "ok";
  my $status = hex(substr($val, 1, 1));
  my $status2 = hex(substr($msg, 10, 1));
  $batstr2 = "empty"    if( $status2 & 4 );
  $batstr2 = "replaced" if( $status2 & 8 );

  if($type eq "HMS100TF") {

    @txt = ( "temperature", "humidity", "battery");

    # Codierung <s1><s0><t1><t0><f0><t2><f2><f1>
    $v[0] = int(substr($val, 5, 1) . substr($val, 2, 2))/10;
    $v[0] =  -$v[0] if($status1 & 8);
    $v[1] = int(substr($val, 6, 2) . substr($val, 4, 1))/10;
    $v[2] = $batstr1;

    $val = "T: $v[0]  H: $v[1]  Bat: $v[2]";
    #$v[0] = "$v[0] (Celsius)";
    #$v[1] = "$v[1] (%)";

  } elsif ($type eq "HMS100T") {

    @txt = ( "temperature", "battery");

    $v[0] = int(substr($val, 5, 1) . substr($val, 2, 2))/10;
    $v[0] =  -$v[0] if($status1 & 8);
    $v[1] = $batstr1;

    $val = "T: $v[0]  Bat: $v[1]";
    #$v[0] = "$v[0] (Celsius)";

  } elsif ($type eq "HMS100WD") {

    @txt = ( "water_detect", "battery");

    $v[0] = ($status ? "on" : "off");
    $v[1] = $batstr2;

    $val = "Water Detect: $v[0]";

 } elsif ($type eq "HMS100TFK") {    # By Peter P.

    @txt = ( "switch_detect", "battery");

    $v[0] = ($status ? "on" : "off");
    $v[1] = $batstr2;

    $val = "Switch Detect: $v[0]";

 } elsif($type eq "RM100-2") {

    @txt = ( "smoke_detect", "battery");

    $v[0] = ($status ? "on" : "off");
    $v[1] = $batstr2;

    $val = "smoke_detect: $v[0]";

  } elsif ($type eq "HMS100MG") {    # By Peter Stark

    @txt = ( "gas_detect", "battery");

    $v[0] = ($status ? "on" : "off");
    $v[1] = $batstr2;                 # Battery conditions not yet verified

    $val = "Gas Detect: $v[0]";

  } elsif ($type eq "HMS100CO") {    # By PAN

    @txt = ( "gas_detect", "battery");

    $v[0] = ($status ? "on" : "off");
    $v[1] = $batstr2;                 # Battery conditions not yet verified

    $val = "CO Detect: $v[0]";

 } elsif ($type eq "HMS100FIT") {    # By PAN

    @txt = ( "fi_triggered", "battery");

    $v[0] = ($status ? "on" : "off");
    $v[1] = $batstr2;                 # Battery conditions not yet verified

    $val = "FI triggered: $v[0]";

  } else {

    Log3 $name, 3, "HMS Device $dev (Unknown type: $type)";
    return "";

  }

  Log3 $name, 4, "HMS Device $dev ($type: $val)";

  readingsBeginUpdate($def);
  my $max = int(@txt);
  for( my $i = 0; $i < $max; $i++) {
    readingsBulkUpdate($def, $txt[$i], $v[$i]);
  }
  readingsBulkUpdate($def, "type", $type);
  readingsBulkUpdate($def, "state", $val);
  readingsBulkUpdate($def, "ExactId", $odev) if($odev ne $dev);
  readingsEndUpdate($def, 1);

  return $name;
}

1;

=pod
=begin html

<a name="HMS"></a>
<h3>HMS</h3>
<ul>
  <a name="HMSdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; HMS &lt;housecode&gt;</code>
    <br><br>

    <code>&lt;housecode&gt;</code> is a four digit hex number,
    corresponding to the address of the HMS device.
    <br>

    Examples:
    <ul>
      <code>define temp HMS 1234</code><br>
    </ul>
    Notes:<br>
    <ul>
      <li>There is _NO_ guarantee that the code will work as expected in all
      circumstances, the authors are not liable for any damage occuring as a
      result of incomplete or buggy code</li>

      <li>Currently supported devices are the HMS100-T HMS100-TF HMS100-WD
          HMS100-MG HMS100-TFK HMS100-CO HMS100-FIT RM100-2 RM100-3</li>

      <li>The housecode of the HMS devices may change if the battery is renewed.
      In order to make life easier, you can define a "wildcard" device for each
      type of HMS device. First the real device-id will be checked, then the
      wildcard device id. The wildcards are:
      <ul>
    <li>1000 for the HMS100-TF</li>
    <li>1001 for the HMS100-T</li>
    <li>1002 for the HMS100-WD</li>
    <li>1003 for the RM100-2</li>
    <li>1004 for the HMS100-TFK</li>
    <li>1006 for the HMS100-MG</li>
    <li>1008 for the HMS100-CO</li>
    <li>100e for the HMS100-FIT</li>
      </ul>
      </li>

      <li>Some battery low notifications are not yet implemented (RM100,
      HMS100WD).</li>
      <li>Please test your installation before relying on the
      functionality.</li>

    </ul>
    <br>
  </ul>
  <br>

  <a name="HMSset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="HMSget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="HMSattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#IODev">IODev</a></li>
    <li><a href="#eventMap">eventMap</a></li>
    <li><a href="#model">model</a> (hms100-t hms100-tf hms100-wd hms100-mg
        hms100-co hms100-tfk hms100-fit rm100-2)</li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>

</ul>

=end html
=cut
