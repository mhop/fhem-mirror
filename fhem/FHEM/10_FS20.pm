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
  "1e" => "on-old-for-timer-prev", # old val for timer, then go to prev. state
  "1f" => "on-100-for-timer-prev", # 100% for timer, then go to previous state

);

my %readonly = (
  "thermo-on" => 1,
  "thermo-off" => 1,
);

use vars qw(%fs20_c2b);		# Peter would like to access it from outside

my $fs20_simple ="off off-for-timer on on-for-timer on-till reset timer toggle";
my %models = (
    fs20fms     => 'sender',
    fs20hgs     => 'sender',
    fs20irl     => 'sender',
    fs20kse     => 'sender',
    fs20ls      => 'sender',
    fs20pira    => 'sender',
    fs20piri    => 'sender',
    fs20piru    => 'sender',
    fs20s16     => 'sender',
    fs20s20     => 'sender',
    fs20s4      => 'sender',
    fs20s4a     => 'sender',
    fs20s4m     => 'sender',
    fs20s4u     => 'sender',
    fs20s4ub    => 'sender',
    fs20s8      => 'sender',
    fs20s8m     => 'sender',
    fs20sd      => 'sender',    # Sensor: Daemmerung
    fs20sn      => 'sender',    # Sensor: Naeherung
    fs20sr      => 'sender',    # Sensor: Regen
    fs20ss      => 'sender',    # Sensor: Sprache
    fs20str     => 'sender',    # Sensor: Thermostat+Regelung
    fs20tc1     => 'sender',
    fs20tc6     => 'sender',    # TouchControl x 6
    fs20tfk     => 'sender',    # TuerFensterKontakt
    fs20tk      => 'sender',    # TuerKlingel
    fs20uts     => 'sender',    # Universal Thermostat Sender
    fs20ze      => 'sender',    # FunkTimer (ZeitEinheit?)
    fs20bf      => 'sender',    # BodenFeuchte

    fs20di      => 'dimmer',
    fs20di10    => 'dimmer',
    fs20du      => 'dimmer',

    fs20as1     => 'simple',
    fs20as4     => 'simple',
    fs20ms2     => 'simple',
    fs20rgbsa   => 'simple',
    fs20rst     => 'simple',
    fs20rsu     => 'simple',
    fs20sa      => 'simple',
    fs20sig     => 'simple',
    fs20sm4     => 'simple',
    fs20sm8     => 'simple',
    fs20st      => 'simple',
    fs20su      => 'simple',
    fs20sv      => 'simple',
    fs20ue1     => 'simple',
    fs20usr     => 'simple',
    fs20ws1     => 'simple',

);

sub hex2four($);
sub four2hex($$);

sub
FS20_Initialize($)
{
  my ($hash) = @_;

  foreach my $k (keys %codes) {
    $fs20_c2b{$codes{$k}} = $k;
  }
  $fs20_c2b{"on-till"} = 99;

  $hash->{Match}     = "^81..(04|0c)..0101a001";
  $hash->{SetFn}     = "FS20_Set";
  $hash->{StateFn}   = "FS20_SetState";
  $hash->{DefFn}     = "FS20_Define";
  $hash->{UndefFn}   = "FS20_Undef";
  $hash->{ParseFn}   = "FS20_Parse";
  $hash->{AttrList}  = "IODev follow-on-for-timer:1,0 do_not_notify:1,0 ignore:0,1 dummy:1,0 showtime:1,0 model:fs20as1,fs20as4,fs20bf,fs20di,fs20du,fs20hgs,fs20hgs,fs20ls,fs20ms2,fs20pira,fs20piri,fs20rst,fs20s20,fs20s4,fs20s4a,fs20s4m,fs20s4u,fs20s4ub,fs20s8,fs20sa,fs20sd,fs20sig,fs20sn,fs20sr,fs20ss,fs20st,fs20str,fs20sv,fs20tfk,fs20tfk,fs20tk,fs20usr,fs20uts,fs20ze loglevel:0,1,2,3,4,5,6";
}

#####################################
sub
FS20_SetState($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;

  $val = $1 if($val =~ m/^(.*) \d+$/);
  my $name = $hash->{NAME};
  (undef, $val) = ReplaceEventMap($name, [$name, $val], 0)
        if($attr{$name}{eventMap});
  return "Undefined value $val" if(!defined($fs20_c2b{$val}));
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
  my $tname = $hash->{NAME} . "_till";
  CommandDelete(undef, $tname) if($defs{$tname});
  CommandDefine(undef, "$tname at $hms_till set $a[0] off");

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
  my $name = $a[0];
  if(!defined($c)) {

    # Model specific set arguments
    if(defined($attr{$name}) && defined($attr{$name}{"model"})) {
      my $mt = $models{$attr{$name}{"model"}};
      return "Unknown argument $a[1], choose one of "
                                               if($mt && $mt eq "sender");
      return "Unknown argument $a[1], choose one of $fs20_simple"
                                               if($mt && $mt eq "simple");
    }
    return "Unknown argument $a[1], choose one of " .
                                join(" ", sort keys %fs20_c2b);

  }

  return Do_On_Till($hash, @a) if($a[1] eq "on-till");

  return "Bad time spec" if($na == 3 && $a[2] !~ m/^\d*\.?\d+$/);

  my $v = join(" ", @a);
  Log GetLogLevel($name,2), "FS20 set $v";
  (undef, $v) = split(" ", $v, 2);	# Not interested in the name...

  my $val;

  if($na == 3) {                                # Timed command.
    $c = sprintf("%02X", (hex($c) | 0x20)); # Set the extension bit

    ########################
    # Calculating the time.
    LOOP: for(my $i = 0; $i <= 12; $i++) {
      for(my $j = 0; $j <= 15; $j++) {
        $val = (2**$i)*$j*0.25;
        if($val >= $a[2]) {
          if($val != $a[2]) {
            Log GetLogLevel($name,2), 
               "$name: changing timeout to $val from $a[2]";
          }
          $c .= sprintf("%x%x", $i, $j);
          last LOOP;
        }
      }
    }
    return "Specified timeout too large, max is 15360" if(length($c) == 2);
  }

  IOWrite($hash, "04", "010101" . $hash->{XMIT} . $hash->{BTN} . $c);

  ###########################################
  # Set the state of a device to off if on-for-timer is called
  if($modules{FS20}{ldata}{$name}) {
    CommandDelete(undef, $name . "_timer");
    delete $modules{FS20}{ldata}{$name};
  }
  if($a[1] =~ m/for-timer/ && $na == 3 &&
     defined($attr{$name}) && defined($attr{$name}{"follow-on-for-timer"})) {
    my $to = sprintf("%02d:%02d:%02d", $val/3600, ($val%3600)/60, $val%60);
    $modules{FS20}{ldata}{$name} = $to;
    Log 4, "Follow: +$to setstate $name off";
    CommandDefine(undef, $name . "_timer at +$to setstate $name off");
  }

  ##########################
  # Look for all devices with the same code, and set state, timestamp
  my $code = "$hash->{XMIT} $hash->{BTN}";
  my $tn = TimeNow();
  my $defptr = $modules{FS20}{defptr};
  foreach my $n (keys %{ $defptr->{$code} }) {
    my $lh = $defptr->{$code}{$n};
    $lh->{CHANGED}[0] = $v;
    $lh->{STATE} = $v;
    $lh->{READINGS}{state}{TIME} = $tn;
    $lh->{READINGS}{state}{VAL} = $v;
    my $lhname = $lh->{NAME};
    if($name ne $lhname) {
      DoTrigger($lhname, undef)
    }
  }
  return $ret;
}

#############################
sub
FS20_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  my $u = "wrong syntax: define <name> FS20 housecode " .
                        "addr [fg addr] [lm addr] [gm FF]";

  return $u if(int(@a) < 4);
  return "Define $a[0]: wrong housecode format: specify a 4 digit hex value ".
         "or an 8 digit quad value"
  		if( ($a[2] !~ m/^[a-f0-9]{4}$/i) && ($a[2] !~ m/^[1-4]{8}$/i) );

  return "Define $a[0]: wrong btn format: specify a 2 digit hex value " .
         "or a 4 digit quad value"
  		if( ($a[3] !~ m/^[a-f0-9]{2}$/i) && ($a[3] !~ m/^[1-4]{4}$/i) );

  my $housecode = $a[2];
  $housecode = four2hex($housecode,4) if (length($housecode) == 8);

  my $btncode = $a[3];
  $btncode = four2hex($btncode,2) if (length($btncode) == 4);

  $hash->{XMIT} = lc($housecode);
  $hash->{BTN}  = lc($btncode);

  my $code = lc("$housecode $btncode");
  my $ncode = 1;
  my $name = $a[0];
  $hash->{CODE}{$ncode++} = $code;
  $modules{FS20}{defptr}{$code}{$name}   = $hash;

  for(my $i = 4; $i < int(@a); $i += 2) {

    return "No address specified for $a[$i]" if($i == int(@a)-1);

    $a[$i] = lc($a[$i]);
    if($a[$i] eq "fg") {
      return "Bad fg address for $name, see the doc"
        if( ($a[$i+1] !~ m/^f[a-f0-9]$/) && ($a[$i+1] !~ m/^44[1-4][1-4]$/));
    } elsif($a[$i] eq "lm") {
      return "Bad lm address for $name, see the doc"
        if( ($a[$i+1] !~ m/^[a-f0-9]f$/) && ($a[$i+1] !~ m/^[1-4][1-4]44$/));
    } elsif($a[$i] eq "gm") {
      return "Bad gm address for $name, must be ff"
        if( ($a[$i+1] ne "ff") && ($a[$i+1] ne "4444"));
    } else {
      return $u;
    }

    my $grpcode = $a[$i+1];
    if (length($grpcode) == 4) {
       $grpcode = four2hex($grpcode,2);
    }

    $code = "$housecode $grpcode";
    $hash->{CODE}{$ncode++} = $code;
    $modules{FS20}{defptr}{$code}{$name}   = $hash;
  }
  AssignIoPort($hash);
}

#############################
sub
FS20_Undef($$)
{
  my ($hash, $name) = @_;

  foreach my $c (keys %{ $hash->{CODE} } ) {
    $c = $hash->{CODE}{$c};

    # As after a rename the $name my be different from the $defptr{$c}{$n}
    # we look for the hash.
    foreach my $dname (keys %{ $modules{FS20}{defptr}{$c} }) {
      delete($modules{FS20}{defptr}{$c}{$dname})
        if($modules{FS20}{defptr}{$c}{$dname} == $hash);
    }
  }
  return undef;
}

sub
FS20_Parse($$)
{
  my ($hash, $msg) = @_;

  # Msg format: 
  # 81 0b 04 f7 0101 a001 HHHH 01 00 11

  my $dev = substr($msg, 16, 4);
  my $btn = substr($msg, 20, 2);
  my $cde = substr($msg, 24, 2);


  my $dur = 0;
  my $cx = hex($cde);
  if($cx & 0x20) {      # Timed command
    $dur = hex(substr($msg, 26, 2));
    my $i = ($dur & 0xf0) / 16;
    my $j = ($dur & 0xf);
    $dur = (2**$i)*$j*0.25;
    $cde = sprintf("%02x", $cx & ~0x20);
  }

  my $v = $codes{$cde};
  $v = "unknown_$cde" if(!defined($v));
  $v .= " $dur" if($dur);


  my $def = $modules{FS20}{defptr}{"$dev $btn"};
  if($def) {
    my @list;
    foreach my $n (keys %{ $def }) {
      my $lh = $def->{$n};
      $n = $lh->{NAME};        # It may be renamed

      return "" if(IsIgnored($n));   # Little strange.

      $lh->{CHANGED}[0] = $v;
      $lh->{STATE} = $v;
      $lh->{READINGS}{state}{TIME} = TimeNow();
      $lh->{READINGS}{state}{VAL} = $v;
      Log GetLogLevel($n,2), "FS20 $n $v";

      if($modules{FS20}{ldata}{$n}) {
        CommandDelete(undef, $n . "_timer");
        delete $modules{FS20}{ldata}{$n};
      }
      if($v =~ m/for-timer/ &&
        defined($attr{$n}) &&
        defined($attr{$n}{"follow-on-for-timer"})) {
        my $to = sprintf("%02d:%02d:%02d", $dur/3600, ($dur%3600)/60, $dur%60);
        Log 4, "Follow: +$to setstate $n off";
        CommandDefine(undef, $n . "_timer at +$to setstate $n off");
        $modules{FS20}{ldata}{$n} = $to;
      }

      push(@list, $n);
    }
    return @list;

  } else {
    # Special FHZ initialization parameter. In Multi-FHZ-Mode we receive
    # it by the second FHZ
    return "" if($dev eq "0001" && $btn eq "00" && $cde eq "00");

    my $dev_four = hex2four($dev);
    my $btn_four = hex2four($btn);
    Log 3, "FS20 Unknown device $dev ($dev_four), " .
                "Button $btn ($btn_four) Code $cde ($v), please define it";
    return "UNDEFINED FS20_$dev$btn FS20 $dev $btn";
  }

}

#############################
sub
hex2four($)
{
  my $v = shift;
  my $r = "";
  foreach my $x (split("", $v)) {
    $r .= sprintf("%d%d", (hex($x)/4)+1, (hex($x)%4)+1);
  }
  return $r;
}

#############################
sub
four2hex($$)
{
  my ($v,$len) = @_;
  my $r = 0;
  foreach my $x (split("", $v)) {
    $r = $r*4+($x-1);
  }
  return sprintf("%0*x", $len,$r);
}


1;
