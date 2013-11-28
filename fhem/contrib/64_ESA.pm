##############################################
# (c) by STefan Mayer (stefan(at)clumsy.ch)  #
#                                            #
# please feel free to contact me for any     #
# changes, improvments, suggestions, etc     #
#                                            #
##############################################

package main;

use strict;
use warnings;

my %codes = (
  "19fa" => "ESA2000_LED",
);


#####################################
sub
ESA_Initialize($)
{
  my ($hash) = @_;

#                        S0119FA011E00007D6E003100000007C9 ESA2000_LED

  $hash->{Match}     = "^S................................\$";
  $hash->{DefFn}     = "ESA_Define";
  $hash->{UndefFn}   = "ESA_Undef";
  $hash->{ParseFn}   = "ESA_Parse";
  $hash->{AttrList}  = "IODev do_not_notify:0,1 showtime:0,1 model:esa2000-led loglevel:0,1,2,3,4,5,6 ignore:0,1";
}

#####################################
sub
ESA_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> ESA CODE" if(int(@a) != 3);
  $a[2] = lc($a[2]);
  return "Define $a[0]: wrong CODE format: specify a 4 digit hex value"
  		if($a[2] !~ m/^[a-f0-9][a-f0-9][a-f0-9][a-f0-9]$/);


  $hash->{CODE} = $a[2];
  $modules{ESA}{defptr}{$a[2]} = $hash;
  AssignIoPort($hash);
  return undef;
}

#####################################
sub
ESA_Undef($$)
{
  my ($hash, $name) = @_;
  delete($modules{ESA}{defptr}{$hash->{CODE}})
        if(defined($hash->{CODE}) &&
           defined($modules{ESA}{defptr}{$hash->{CODE}}));
  return undef;
}

#####################################
sub
ESA_Parse($$)
{
  my ($hash, $msg) = @_;

# 0123456789012345678901234567890123456789
# S0119FA011E00007D6E003100000007C9F9 ESA2000_LED
  $msg = lc($msg);
  my $seq = substr($msg, 1, 2);
  my $cde = substr($msg, 3, 4);
  my $dev = substr($msg, 7, 4);
  my $val = substr($msg, 11, 22);

  Log 5, "ESA msg $msg";
  Log 5, "ESA seq $seq";
  Log 5, "ESA device $dev";
  Log 5, "ESA code $cde";

  my $type = "";
  foreach my $c (keys %codes) {
    $c = lc($c);
    if($cde =~ m/$c/) {
      $type = $codes{$c};
      last;
    }
  }

  if(!defined($modules{ESA}{defptr}{$dev})) {
    Log 3, "Unknown ESA device $dev, please define it";
    $type = "ESA" if(!$type);
    return "UNDEFINED ${type}_$dev ESA $dev";
  }

  my $def = $modules{ESA}{defptr}{$dev};
  my $name = $def->{NAME};
  return "" if(IsIgnored($name));

  my (@v, @txt);

  if($type eq "ESA2000_LED") {

    @txt = ( "repeat", "sequence", "total_ticks", "actual_ticks", "ticks_kwh", "raw", "total_kwh", "actual_kwh" );

    # Codierung Hex
    $v[0] =  int(hex($seq) / 128) ? "+" : "-"; # repeated
    $v[1] =  hex($seq) % 128;
    $v[2] =  hex(substr($val,0,8));
    $v[3] =  hex(substr($val,8,4));
    $v[4] =  hex(substr($val,18,4)) ^ 25; # XOR 25, whyever bit 1,4,5 are swapped?!?!

    $v[5] = sprintf("CNT: %d%s CUM: %d  CUR: %d  TICKS: %d",
                         $v[1], $v[0], $v[2], $v[3], $v[4]);
    $v[6] =  $v[2]/$v[4]; # calculate kW
    $v[7] =  $v[3]/$v[4]; # calculate kW
    $val = sprintf("CNT: %d%s CUM: %0.3f  CUR: %0.3f  TICKS: %d",
                         $v[1], $v[0], $v[6], $v[7], $v[4]);


#    $v[0] = "$v[0] (Repeated)";
#    $v[1] = "$v[1] (Sequence)";
#    $v[2] = "$v[2] (Total)";
#    $v[3] = "$v[3] (Actual)";
#    $v[4] = "$v[4] (T/kWh)";

  } else {

    Log 3, "ESA Device $dev (Unknown type: $type)";
    return "";

  }

  my $now = TimeNow();

  my $max = int(@txt);

  if ( $def->{READINGS}{"sequence"}{VAL} ne $v[1] ) {
    Log GetLogLevel($name,4), "ESA $name: $val";
    for( my $i = 0; $i < $max; $i++) {
      $def->{READINGS}{$txt[$i]}{TIME} = $now;
      $def->{READINGS}{$txt[$i]}{VAL} = $v[$i];
      $def->{CHANGED}[$i] = "$txt[$i]: $v[$i]";
    }
    $def->{READINGS}{type}{TIME} = $now;
    $def->{READINGS}{type}{VAL} = $type;

    $def->{STATE} = $val;
    $def->{CHANGED}[$max++] = $val;
  } else {
    Log GetLogLevel($name,4), "(ESA/DISCARDED $name: $val)";
    return "($name)";
  }

  return $name;
}

1;
