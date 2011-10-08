##############################################
package main;

# From peterp
# Lacrosse TX3-TH thermo/hygro sensor

use strict;
use warnings;

sub
CUL_TX_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^TX..........";        # Need TX to avoid FHTTK
  $hash->{DefFn}     = "CUL_TX_Define";
  $hash->{UndefFn}   = "CUL_TX_Undef";
  $hash->{ParseFn}   = "CUL_TX_Parse";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ignore:0,1 " .
                        "showtime:1,0 loglevel:0,1,2,3,4,5,6";
}

#############################
sub
CUL_TX_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> CUL_TX <code> [corr]"
        if(int(@a) < 3 || int(@a) > 4);

  $hash->{CODE} = $a[2];
  $hash->{corr} = ((int(@a) > 3) ? $a[3] : 0);

  $modules{CUL_TX}{defptr}{$a[2]} = $hash;
  $hash->{STATE} = "Defined";
  Log 4, "CUL_TX defined  $a[0] $a[2]";

  return undef;
}

#####################################
sub
CUL_TX_Undef($$)
{
  my ($hash, $name) = @_;
  delete($modules{CUL_TX}{defptr}{$hash->{CODE}})
     if(defined($hash->{CODE}) &&
        defined($modules{CUL_TX}{defptr}{$hash->{CODE}}));
  return undef;
}

###################################
sub
CUL_TX_Parse($$)
{
  my ($hash, $msg) = @_;
  $msg = substr($msg, 1);
  # Msg format: taTHHXYZXY, see http://www.f6fbb.org/domo/sensors/tx3_th.php
  my @a = split("", $msg);
  my $id2 = hex($a[4]) & 1; #meaning unknown
  my $id3 = (hex($a[3])<<3) + (hex($a[4])>>1);

  if($a[5] ne $a[8] || $a[6] ne $a[9]) {
    Log 4, "CUL_TX $id3 ($msg) data error";
    return "";
  }

  my $def = $modules{CUL_TX}{defptr}{$id3};
  if(!$def) {
    Log 2, "CUL_TX Unknown device $id3, please define it";
    return "UNDEFINED CUL_TX_$id3 CUL_TX $id3" if(!$def);
  }

  my $name = $def->{NAME};

  my $ll4 = GetLogLevel($name,4);
  Log $ll4, "CUL_TX $name $id3 ($msg)";

  my ($devtype, $val, $no);
  my $valraw = ($a[5].$a[6].".".$a[7]);
  my $type = $a[2];
  if($type eq "0") {
     $devtype = "temperature";
     $val = sprintf("%2.1f", ($valraw - 50 + $def->{corr}) );
     Log $ll4, "CUL_TX $devtype $name $id3 T: $val F: $id2";
     $no = "temperature: $val";

  } elsif ($type eq "E") {
     $devtype = "humidity";
     $val = $valraw;
     Log $ll4, "CUL_TX $devtype $name $id3 H: $val F: $id2";
     $no = "humidity: $val";

  } else {
     my $ll2 = GetLogLevel($name,4);
     Log $ll2, "CUL_TX $type $name $id3 ($msg) unknown type";
     return "";

  }

  my $tn = TimeNow();
  $def->{STATE} = $no;
  $def->{READINGS}{state}{TIME} = $tn;
  $def->{READINGS}{state}{VAL} = $val;
  $def->{CHANGED}[0] = $no;

  $def->{READINGS}{$devtype}{VAL} = $val;
  $def->{READINGS}{$devtype}{TIME} = $tn;

  DoTrigger($name, undef) if($init_done);
  return $name;
}

1;

