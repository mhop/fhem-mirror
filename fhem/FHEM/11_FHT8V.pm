#############################################
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
  $hash->{AttrList}  = "IODev dummy:1,0 ignore:1,0 loglevel:0,1,2,3,4,5,6";
}

#############################
sub
FHT8V_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $n = $a[0];

  return "wrong syntax: define <name> FHT8V housecode [IODev]" if(@a < 3);
  return "wrong housecode format: specify a 4 digit hex value "
  		if(($a[2] !~ m/^[a-f0-9]{4}$/i));
  if(@a > 3) {
    $hash->{IODev} = $defs{$a[3]};
  } else {
    AssignIoPort($hash);
  }
  return "$n: No IODev found" if(!$hash->{IODev});
  return "$n: Wrong IODev, has no FHTID" if(!$hash->{IODev}->{FHTID});

  #####################
  # Check if the address corresponds to the CUL
  my $ioaddr = hex($hash->{IODev}->{FHTID});
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

  $hash->{ADDR} = uc($a[2]);
  $hash->{IDX}  = sprintf("%02X", $my1-$io1);
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
    Log GetLogLevel($n,3), "FHT8V set $n $arg $a[2]";
    $hash->{STATE} = sprintf("%d %%", $a[2]);
    IOWrite($hash, "", sprintf("T%s0026%02X", $hash->{ADDR}, $a[2]*2.55));

  } elsif ($arg eq "pair" ) {
    Log GetLogLevel($n,3), "FHT8V set $n $arg";
    IOWrite($hash, "", sprintf("T%s002f00", $hash->{ADDR}));

  } else {
    return "Unknown argument $a[1], choose one of valve pair"

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
    my $idx = $hash->{IDX};
    return int(hex($1)/2.55) if($msg =~ m/$idx:26(..)/);
    return "N/A";

  }
  return "Unknown argument $a[1], choose one of valve"
}


1;
