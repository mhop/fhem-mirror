##############################################
package main;

use strict;
use warnings;


my %codes = (
  "00" => "off",
  "01" => "dim06%",
  "02" => "dim12%",
  "03" => "dim18%",
  "04" => "dim25%",
  "05" => "dim31%",
  "06" => "dim37%",
  "07" => "dim43%",
  "08" => "dim50%",
  "09" => "dim56%",
  "0a" => "dim62%",
  "0b" => "dim68%",
  "0c" => "dim75%",
  "0d" => "dim81%",
  "0e" => "dim87%",
  "0f" => "dim93%",
  "10" => "dim100%",
  "11" => "on",		# Set to previous dim value (before switching it off)
  "12" => "toggle",	# between off and previous dim val
  "13" => "dimup",
  "14" => "dimdown",
  "15" => "dimupdown",
  "16" => "timer",
  "17" => "sendstate",
  "18" => "off-for-timer",
  "19" => "on-for-timer",
  "1a" => "on-old-for-timer",
  "1b" => "reset",
  "1c" => "ramp-on-time",      #time to reach the desired dim value on dimmers
  "1d" => "ramp-off-time",     #time to reach the off state on dimmers
);

my %readonly = (
  "thermo-on" => 1,
  "thermo-off" => 1,
);

use vars qw(%fs20_c2b);		# Peter would like to access it from outside
my %defptr;
my %readings;
my %follow;

sub
FS20_Initialize($)
{
  my ($hash) = @_;

  foreach my $k (keys %codes) {
    $fs20_c2b{$codes{$k}} = $k;
  }
  $fs20_c2b{"on-till"} = 99;

  $hash->{Category}  = "DEV";

  $hash->{Match}     = "^81..(04|0c)..0101a001";
  $hash->{SetFn}     = "FS20_Set";
  $hash->{GetFn}     = "FS20_Get";
  $hash->{ListFn}    = "FS20_List";
  $hash->{StateFn}   = "FS20_SetState";
  $hash->{DefFn}     = "FS20_Define";
  $hash->{UndefFn}   = "FS20_Undef";
  $hash->{ParseFn}   = "FS20_Parse";
}

###################################
sub
FS20_Get($@)
{
  my ($hash, @a) = @_;
  return "No get function implemented";
}

###################################
sub
FS20_List($)
{
  my ($hash) = @_;

  my $n = $hash->{NAME};
  if(!defined($readings{$n})) {
    return "No information about $n\n";
  } else {
    return sprintf("%-19s %s\n", $readings{$n}{TIM}, $readings{$n}{VAL});
  }
}

#####################################
sub
FS20_SetState($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;

  return "Undefined value $vt" if(!defined($fs20_c2b{$vt}));

  my $name = $hash->{NAME};
  if(!$readings{$name} || $readings{$name}{TIM} lt $tim) {
    $readings{$name}{TIM} = $tim;
    $readings{$name}{VAL} = $vt;
  }
  return undef;
}

#############################
sub
Do_On_Till($@)
{
  my ($hash, @a) = @_;
  return "Timespec (HH:MM[:SS]) needed for the on-till command" if(@a != 3);

  my ($err, $hr, $min, $sec, $fn) = GetTimeSpec($a[2]);
  return $err if($err);

  my @lt = localtime;
  my $hms_till = sprintf("%02d:%02d:%02d", $hr, $min, $sec);
  my $hms_now = sprintf("%02d:%02d:%02d", $lt[2], $lt[1], $lt[0]);
  if($hms_now ge $hms_till) {
    Log 4, "on-till: won't switch as now ($hms_now) is later than $hms_till";
    return "";
  }

  my @b = ($a[0], "on");
  FS20_Set($hash, @b);
  CommandAt(undef, "$hms_till set $a[0] off");
}


###################################
sub
FS20_Set($@)
{
  my ($hash, @a) = @_;
  my $ret = undef;
  my $na = int(@a);

  return "no set value specified" if($na < 2 || $na > 3);
  return "Readonly value $a[1]" if(defined($readonly{$a[1]}));

  my $c = $fs20_c2b{$a[1]};
  if(!defined($c)) {
    return "Unknown set value $a[1], please specify one of:\n  " .
    		join("\n  ", sort(keys %fs20_c2b));
  }

  return Do_On_Till($hash, @a) if($a[1] eq "on-till");

  return "Bad time spec" if($na == 3 && $a[2] !~ m/^\d*\.?\d+$/);

  my $v = join(" ", @a);
  Log GetLogLevel($a[0]), "FS20 set $v";
  (undef, $v) = split(" ", $v, 2);	# Not interested in the name...

  my $val;
  if($na == 2) {

    IOWrite($hash, "04", "010101" . $hash->{XMIT} . $hash->{BTN} . $c)
    	if(!IsDummy($a[0]));

  } else {

    $c =~ s/1/3/; # Set the extension bit

    ########################
    # Calculating the time.
    LOOP: for(my $i = 0; $i <= 12; $i++) {
      for(my $j = 0; $j <= 15; $j++) {
	$val = (2**$i)*$j*0.25;
	if($val >= $a[2]) {
          if($val != $a[2]) {
            $ret = "FS20 Setting timeout to $val from $a[2]";
            Log GetLogLevel($a[0]), $ret;
	  }
	  $c .= sprintf("%x%x", $i, $j);
	  last LOOP;
	}
      }
    }
    return "Specified timeout too large, max is 15360" if(length($c) == 2);

    IOWrite($hash, "04", "010101" . $hash->{XMIT} . $hash->{BTN} . $c)
    	if(!IsDummy($a[0]));

  }

  ###########################################
  # Set the state of a device to off if on-for-timer is called
  if($follow{$a[0]}) {
    CommandDelete(undef, "at .*setstate.*$a[0]");
    delete $follow{$a[0]};
  }
  if($a[1] eq "on-for-timer" && $na == 3 &&
     defined($attr{$a[0]}) && defined($attr{$a[0]}{"follow-on-for-timer"})) {
    my $to = sprintf("%02d:%02d:%02d", $val/3600, ($val%3600)/60, $val%60);
    $follow{$a[0]} = $to;
    Log 4, "Follow: +$to setstate $a[0] off";
    CommandAt(undef, "+$to setstate $a[0] off");
  }

  ##########################
  # Look for all devices with the same code, and set state, timestamp
  my $code = "$hash->{XMIT} $hash->{BTN}";
  my $tn = TimeNow();
  foreach my $n (keys %{ $defptr{$code} }) {
    $defptr{$code}{$n}->{CHANGED}[0] = $v;
    $defptr{$code}{$n}->{STATE} = $v;
    $readings{$n}{TIM} = $tn;
    $readings{$n}{VAL} = $v;
  }
  

  return $ret;
}

#############################
sub
FS20_Define($@)
{
  my ($hash, @a) = @_;
  my $u =
  "wrong syntax: define <name> FS20 housecode addr [fg addr] [lm addr] [gm FF]";

  return $u if(int(@a) < 4);
  return "Define $a[0]: wrong housecode format: specify a 4 digit hex value"
  		if($a[2] !~ m/^[a-f0-9]{4}$/i);
  return "Define $a[0]: wrong btn format: specify a 2 digit hex value"
  		if($a[3] !~ m/^[a-f0-9]{2}$/i);

  $hash->{XMIT} = lc($a[2]);
  $hash->{BTN}  = lc($a[3]);

  my $code = "$a[2] $a[3]";
  my $ncode = 1;
  my $name = $a[0];

  $hash->{CODE}{$ncode++} = $code;
  $defptr{$code}{$name}   = $hash;

  for(my $i = 4; $i < int(@a); $i += 2) {

    return "No address specified for $a[$i]" if($i == int(@a)-1);

    $a[$i] = lc($a[$i]);
    if($a[$i] eq "fg") {
      return "Bad fg address, see the doc" if($a[$i+1] !~ m/^f[a-f0-9]$/);
    } elsif($a[$i] eq "lm") {
      return "Bad lm address, see the doc" if($a[$i+1] !~ m/^[a-f0-9]f$/);
    } elsif($a[$i] eq "gm") {
      return "Bad gm address, mus be ff" if($a[$i+1] ne "ff");
    } else {
      return $u;
    }

    $code = "$a[2] $a[$i+1]";
    $hash->{CODE}{$ncode++} = $code;
    $defptr{$code}{$name}   = $hash;
  }
  AssignIoPort($hash);
}

#############################
sub
FS20_Undef($$)
{
  my ($hash, $name) = @_;
  foreach my $c (keys %{ $hash->{CODE} } ) {
    delete($defptr{$c}{$name});
  }
  return undef;
}

sub
FS20_Parse($)
{
  my ($hash, $msg) = @_;

  # Msg format: 
  # 81 0b 04 f7 0101 a001 HHHH 01 00 11

  my $dev = substr($msg, 16, 4);
  my $btn = substr($msg, 20, 2);
  my $cde = substr($msg, 24, 2);

  my $def = $defptr{"$dev $btn"};

  my $dur = 0;
  my $cx = hex($cde);
  if($cx & 0x20) {
    $dur = hex(substr($msg, 26, 2));
    my $i = ($dur & 0xf0) / 16;
    my $j = ($dur & 0xf);
    $dur = (2**$i)*$j*0.25;
    $cde = sprintf("%02x", $cx & ~0x20);
  }

  my $v = $codes{$cde};
  $v = "unknown:$cde" if(!defined($v));
  $v .= " $dur" if($dur);
  if($def) {

    my @list;
    foreach my $n (keys %{ $def }) {
      $readings{$n}{TIM} = TimeNow();
      $readings{$n}{VAL} = $v;
      $def->{$n}->{CHANGED}[0] = $v;
      $def->{$n}->{STATE} = $v;
      Log GetLogLevel($n), "FS20 $n $v";
      push(@list, $n);
    }
    return @list;

  } else {
    # Special FHZ initialization parameter. In Multi-FHZ-Mode we receive
    # it by the second FHZ
    return "" if($dev eq "0001" && $btn eq "00" && $cde eq "00");

    Log 3, "FS20 Unknown device $dev, Button $btn Code $cde ($v), " .
    	   "please define it";
    return "UNDEFINED FS20 $dev/$btn/$cde";
  }

}


1;
