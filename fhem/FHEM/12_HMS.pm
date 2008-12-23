##############################################
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

my %defptr;


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
  $hash->{AttrList}  = "do_not_notify:0,1 showtime:0,1 model;hms100-t,hms100-tf,hms100-wd,hms100-mg,hms100-tfk,rm100-2,hms100-co,hms100-fit loglevel:0,1,2,3,4,5,6";
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
  $defptr{$a[2]} = $hash;

  return undef;
}

#####################################
sub
HMS_Undef($$)
{
  my ($hash, $name) = @_;
  delete($defptr{$hash->{CODE}});
  return undef;
}

#####################################
sub
HMS_Parse($$)
{
  my ($hash, $msg) = @_;

  my $dev = substr($msg, 16, 4);
  my $cde = substr($msg, 11, 1);
  my $val = substr($msg, 24, 8) if(length($msg) == 32);
  my $odev;

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
  if(!defined($defptr{$dev})) {
    Log 4, "HMS device $dev not defined, using the wildcard device 100$cde";
    $odev = $dev;
    $dev = "100$cde";
  }

  if(!defined($defptr{$dev})) {
    Log 3, "Unknown HMS device $dev/$odev, please define it";
    $type = "HMS" if(!$type);
    return "UNDEFINED $type $odev";
  }

  my $def = $defptr{$dev};

  my (@v, @txt, @sfx);

  if($type eq "HMS100TF") {

    @txt = ( "temperature", "humidity", "battery");
    @sfx = ( "(Celsius)",   "(%)",      "");

    # Codierung <s1><s0><t1><t0><f0><t2><f2><f1>
    my $status = hex(substr($val, 0, 1));
    $v[0] = int(substr($val, 5, 1) . substr($val, 2, 2))/10;
    $v[1] = int(substr($val, 6, 2) . substr($val, 4, 1))/10;
    $v[2] = "ok";
    if ( $status & 2 ) { $v[2] = "empty"; }
    if ( $status & 4 ) { $v[2] = "replaced"; }
    if ( $status & 8 ) { $v[0] =  -$v[0]; }

    $val = "T: $v[0]  H: $v[1]  Bat: $v[2]";

  } elsif ($type eq "HMS100T") {

    @txt = ( "temperature", "battery");
    @sfx = ( "(Celsius)",   "");

    my $status = hex(substr($val, 0, 1));
    $v[0] = int(substr($val, 5, 1) . substr($val, 2, 2))/10;
    $v[1] = "ok";
    if ( $status & 2 ) { $v[1] = "empty"; }
    if ( $status & 4 ) { $v[1] = "replaced"; }
    if ( $status & 8 ) { $v[0] = -$v[0]; }

    $val = "T: $v[0]  Bat: $v[1]";

  } elsif ($type eq "HMS100WD") {
  
    @txt = ( "water_detect", "battery");
    @sfx = ( "",             "");

    # Battery-low condition detect is not yet properly
    # implemented. As soon as my WD's batteries get low
    # I am willing to supply a patch ;-) SEP7-RIPE, 2006/05/13
    my $status = hex(substr($val, 1, 1));
    $v[1] = "ok";
    $v[0] = "off";
    if ( $status & 1 ) { $v[0] = "on"; }
    $val = "Water Detect: $v[0]";

 } elsif ($type eq "HMS100TFK") {    # By Peter P.
  
    @txt = ( "switch_detect", "battery");
    @sfx = ( "",             "");
    # Battery-low condition detect is not yet properly implemented.
    my $status = hex(substr($val, 1, 1));
    $v[0] = ($status ? "on" : "off");
    $v[1] = "off";
    $val = "Switch Detect: $v[0]";

  } elsif($type eq "RM100-2") {

    @txt = ( "smoke_detect", "battery");
    @sfx = ( "",             "");

    $v[0] = ( hex(substr($val, 1, 1)) != "0" ) ? "on" : "off";
    $v[1] = "ok";
    my  $status = hex(substr($msg, 10, 1));
    if( $status & 4 ) { $v[1] = "empty"; }
    if( $status & 8 ) { $v[1] = "replaced"; }
    $val = "smoke_detect: $v[0]";

  } elsif ($type eq "HMS100MG") {    # By Peter Stark
  
    @txt = ( "gas_detect", "battery");
    @sfx = ( "",             "");

    # Battery-low condition detect is not yet properly
    # implemented.
    my $status = hex(substr($val, 1, 1));
    $v[0] = ($status != "0") ? "on" : "off";
    $v[1] = "off";
    if ($status & 1) { $v[0] = "on"; }
    $val = "Gas Detect: $v[0]";

  } elsif ($type eq "HMS100CO") {    # By PAN

    @txt = ( "gas_detect", "battery");
    @sfx = ( "",             "");

    # Battery-low condition detect is not yet properly
    # implemented.
    my $status = hex(substr($val, 1, 1));
    $v[0] = ($status != "0") ? "on" : "off";
    $v[1] = "off";
    if ($status & 1) { $v[0] = "on"; }
    $val = "CO Detect: $v[0]";

 } elsif ($type eq "HMS100FIT") {    # By PAN

    @txt = ( "fi_triggered", "battery");
    @sfx = ( "",             "");

    # Battery-low condition detect is not yet properly
    # implemented.
    my $status = hex(substr($val, 1, 1));
    $v[0] = ($status != "0") ? "on" : "off";
    $v[1] = "off";
    if ($status & 1) { $v[0] = "on"; }
    $val = "FI triggered: $v[0]";

  } else {

    Log 4, "HMS Device $dev (Unknown type: $type)";
    return "";

  }

  my $now = TimeNow();
  Log GetLogLevel($def->{NAME},4), "HMS Device $dev ($type: $val)";

  my $max = int(@txt);
  for( my $i = 0; $i < $max; $i++) {
    $def->{READINGS}{$txt[$i]}{TIME} = $now;
    my $v = "$v[$i] $sfx[$i]";
    $def->{READINGS}{$txt[$i]}{VAL} = $v;
    $def->{CHANGED}[$i] = "$txt[$i]: $v";
  }
  $def->{READINGS}{type}{TIME} = $now;
  $def->{READINGS}{type}{VAL} = $type;

  $def->{STATE} = $val;
  $def->{CHANGED}[$max] = $val;

  $def->{CHANGED}[$max+1] = "ExactId: $odev" if($odev);

  return $def->{NAME};
}

1;
