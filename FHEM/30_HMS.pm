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
);

my %readings;
my %defptr;


#####################################
sub
HMS_Initialize($)
{
  my ($hash) = @_;

  $hash->{Category}  = "DEV";

#                        810e047e0510a001473a000000120233 HMS100TF
#                        810e04b90511a0018e63000001100000 HMS100T
#                        810e04e80212a001ec46000001000000 HMS100WD
#                        810e04d70213a001b16d000003000000 RM100-2
#                        810e047f0214a001a81f000001000000 HMS100TFK
#                        810e048f0295a0010155000001000000 HMS100TFK (jumper)
#			 810e04330216a001b4c5000001000000 HMS100MG

  $hash->{Match}     = "^810e04....(1|5|9)[0-6]a001";
  $hash->{SetFn}     = "HMS_Set";
  $hash->{GetFn}     = "HMS_Get";
  $hash->{StateFn}   = "HMS_SetState";
  $hash->{ListFn}    = "HMS_List";
  $hash->{DefFn}     = "HMS_Define";
  $hash->{UndefFn}   = "HMS_Undef";
  $hash->{ParseFn}   = "HMS_Parse";
}

###################################
sub
HMS_Set($@)
{ 
  my ($hash, @a) = @_;
  return "No set function implemented";
}

###################################
sub
HMS_Get($@)
{ 
  my ($hash,@a) = @_;
  return "No get function implemented";
}

#####################################
sub
HMS_SetState($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;

  my $n = $hash->{CODE};
  if(!$readings{$n}{$vt} || $readings{$n}{$vt}{TIM} lt $tim) {
    $readings{$n}{$vt}{TIM} = $tim;
    $readings{$n}{$vt}{VAL} = $val;
  }
  return undef;
}

#####################################
sub
HMS_List($)
{
  my ($hash) = @_;

  my $n = $hash->{CODE};
  if(!defined($readings{$n})) {
    return "No information about " . $hash->{NAME} . "\n";
  } else {
    my $str = "";
    foreach my $m (keys %{ $readings{$n} }) {
      $str .= sprintf("%-19s   %-15s %s\n", 
      	$readings{$n}{$m}{TIM}, $m, $readings{$n}{$m}{VAL});
    }
    return $str;
  }
}

#####################################
sub
HMS_Define($@)
{
  my ($hash, @a) = @_;

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
    $v[1] = "unknown";               # Battery-low detect is _NOT_ implemented.
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

  } else {

    Log 4, "HMS Device $dev (Unknown type: $type)";
    return "";

  }

  my $now = TimeNow();
  Log 4, "HMS Device $dev ($type: $val)";

  my $max = int(@txt);
  for( my $i = 0; $i < $max; $i++) {
    $readings{$dev}{$txt[$i]}{TIM} = $now;
    my $v = "$v[$i] $sfx[$i]";
    $readings{$dev}{$txt[$i]}{VAL} = $v;
    $def->{CHANGED}[$i] = "$txt[$i]: $v";
  }
  $readings{$dev}{type}{TIM} = $now;
  $readings{$dev}{type}{VAL} = $type;

  $def->{STATE} = $val;
  $def->{CHANGED}[$max] = $val;
  return $def->{NAME};
}

1;
