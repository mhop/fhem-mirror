#############################################
# $Id$
package main;

use strict;
use warnings;

sub doSoftBuffer($);
sub softBufferTimer($);
sub getFhtMin($);
sub getFhtBuffer($);

my %codes = (
  "00" => "actuator",
  "01" => "actuator1",
  "02" => "actuator2",
  "03" => "actuator3",
  "04" => "actuator4",
  "05" => "actuator5",
  "06" => "actuator6",
  "07" => "actuator7",
  "08" => "actuator8",

  "14" => "mon-from1",
  "15" => "mon-to1",
  "16" => "mon-from2",
  "17" => "mon-to2",
  "18" => "tue-from1",
  "19" => "tue-to1",
  "1a" => "tue-from2",
  "1b" => "tue-to2",
  "1c" => "wed-from1",
  "1d" => "wed-to1",
  "1e" => "wed-from2",
  "1f" => "wed-to2",
  "20" => "thu-from1",
  "21" => "thu-to1",
  "22" => "thu-from2",
  "23" => "thu-to2",
  "24" => "fri-from1",
  "25" => "fri-to1",
  "26" => "fri-from2",
  "27" => "fri-to2",
  "28" => "sat-from1",
  "29" => "sat-to1",
  "2a" => "sat-from2",
  "2b" => "sat-to2",
  "2c" => "sun-from1",
  "2d" => "sun-to1",
  "2e" => "sun-from2",
  "2f" => "sun-to2",

  "3e" => "mode",
  "3f" => "holiday1",		# Not verified
  "40" => "holiday2",		# Not verified
  "41" => "desired-temp",
  "XX" => "measured-temp",		# sum of next. two, never really sent
  "42" => "measured-low",
  "43" => "measured-high",
  "44" => "warnings",
  "45" => "manu-temp",		# No clue what it does.

  "4b" => "ack",
  "53" => "can-xmit",
  "54" => "can-rcv",

  "60" => "year",
  "61" => "month",
  "62" => "day",
  "63" => "hour",
  "64" => "minute",
  "65" => "report1",
  "66" => "report2",
  "69" => "ack2",

  "7d" => "start-xmit",
  "7e" => "end-xmit",

  "82" => "day-temp",
  "84" => "night-temp",
  "85" => "lowtemp-offset",         # Alarm-Temp.-Differenz
  "8a" => "windowopen-temp",
);

my %cantset = (
  "actuator"      => 1,
  "actuator1"     => 1,
  "actuator2"     => 1,
  "actuator3"     => 1,
  "actuator4"     => 1,
  "actuator5"     => 1,
  "actuator6"     => 1,
  "actuator7"     => 1,
  "actuator8"     => 1,

  "ack"           => 1,
  "ack2"          => 1,
  "battery"       => 1,
  "can-xmit"      => 1,
  "can-rcv"       => 1,
  "start-xmit"    => 1,
  "end-xmit"      => 1,

  "lowtemp"       => 1,
  "measured-temp" => 1,
  "measured-high" => 1,
  "measured-low"  => 1,
  "warnings"      => 1,
  "window"        => 1,
  "windowsensor"  => 1,
);

# additional warnings
my %warnings = (
  "battery"       => 1,
  "lowtemp"       => 1,
  "window"        => 1,
  "windowsensor"  => 1,
);

my %priority = (
  "desired-temp"=> 1,
  "mode"	=> 2,
  "report1"     => 3,
  "report2"     => 3,
  "holiday1"	=> 4,
  "holiday2"	=> 5,
  "day-temp"	=> 6,
  "night-temp"	=> 7,
);

my %c2m = (0 => "auto", 1 => "manual", 2 => "holiday", 3 => "holiday_short");
my %m2c;	# Reverse c2m
my %c2b;	# command->button hash (reverse of codes)
my %c2bset;	# command->button hash (settable values)

my $defmin = 0;                # min fhtbuf free bytes before sending commands
my $retryafter = 240;          # in seconds, only when fhtsoftbuffer is active
my $cmdcount = 0;

#####################################
sub
FHT_Initialize($)
{
  my ($hash) = @_;

  foreach my $k (keys %codes) {
    my $v = $codes{$k};
    $c2b{$v} = $k;
    $c2bset{$v} = $k if(!$cantset{$v});
  }
  foreach my $k (keys %c2m) {
    $m2c{$c2m{$k}} = $k;
  }

#                        810c0426 0909a001 1111 1600
#                        810c04b3 0909a001 1111 44006900
#                        810b0402 83098301 1111 41301d
#                        81090421 c409c401 1111 00
#                        810c0d20 0909a001 3232 7e006724 (NYI)
  $hash->{Match}     = "^81..(04|09|0d)..(0909a001|83098301|c409c401)..";
  $hash->{SetFn}     = "FHT_Set";
  $hash->{DefFn}     = "FHT_Define";
  $hash->{UndefFn}   = "FHT_Undef";
  $hash->{ParseFn}   = "FHT_Parse";
  $hash->{AttrList}  = "IODev do_not_notify:0,1 model;fht80b dummy:0,1 " .
                       "showtime:0,1 loglevel:0,1,2,3,4,5,6 retrycount " .
                       "minfhtbuffer lazy tmpcorr ignore:0,1";
}


sub
FHT_Set($@)
{
  my ($hash, @a) = @_;
  my $ret = "";

  return "\"set $a[0]\" needs at least two parameters" if(@a < 2);
  my $name = shift(@a);

  # Replace refreshvalues with report1 and report2, and time with hour/minute
  for(my $i = 0; $i < @a; $i++) {
    splice(@a,$i,1,("report1","255","report2","255"))
        if($a[$i] eq "refreshvalues");

    if($a[$i] eq "time") {
      my @t = localtime;
      splice(@a,$i,1,("hour",$t[2],"minute",$t[1]));
    }

    if($a[$i] eq "date") {
      my @t = localtime;
      splice(@a,$i,1,("year",$t[5]-100,"month",$t[4]+1,"day",$t[3]));
    }
  }

  my $ncmd = 0;
  my $arg = "020183" . $hash->{CODE};
  my ($cmd, $allcmd, $val) = ("", "", "");

  my $lazy= defined($attr{$name}) &&
       		defined($attr{$name}{"lazy"}) &&
       		($attr{$name}{"lazy"}>0);
  my $readings= $hash->{READINGS};


  while(@a) {
    $cmd = shift(@a);

    return "Unknown argument $cmd, choose one of " . join(" ",sort keys %c2bset)
                if(!defined($c2b{$cmd}));
    return "Readonly parameter $cmd"
                if(defined($cantset{$cmd}));
    return "\"set $name $cmd\" needs a parameter"
                if(@a < 1);

    $val = shift(@a);
    $arg .= $c2b{$cmd};

    if ($cmd =~ m/-temp/) {

      return "Invalid temperature, use NN.N" if($val !~ m/^\d*\.?\d+$/);
      return "Invalid temperature, must between 5.5 and 30.5"
                          if($val < 5.5 || $val > 30.5);
      my $a = int($val*2);
      $arg .= sprintf("%02x", $a);
      $ret .= sprintf("Rounded temperature to %.1f", $a/2) if($a/2 != $val);
      $val = sprintf("%.1f", $a/2);

    } elsif($cmd =~ m/-from/ || $cmd =~ m/-to/) {

      return "Invalid timeformat, use HH:MM"
                        if($val !~ m/^([0-2]\d):([0-5]\d)/);
      my $a = ($1*6) + ($2/10);
      $arg .= sprintf("%02x", $a);
      my $nt = sprintf("%02d:%02d", $1, int($2/10)*10);
      $ret .= "Rounded $cmd to $nt" if($nt ne $val);
      $val = $nt;

    } elsif($cmd eq "mode") {

      return "Invalid mode, use one of " . join(" ", sort keys %m2c)
        if(!defined($m2c{$val}));
      $arg .= sprintf("%02x", $m2c{$val});

    } elsif ($cmd eq "lowtemp-offset") {

      return "Invalid lowtemperature-offset, must between 1 and 5"
          if($val !~ m/^[1-5]$/);
      $arg .= sprintf("%02x", $val);
      $val = "$val.0";

    } else {	# Holiday1, Holiday2

      return "Invalid argument, must be between 1 and 255"
          if($val !~ m/^\d+$/ || $val < 0 || $val > 255);
      $arg .= sprintf("%02x", $val) if(defined($val));

    }


    if($lazy &&
    	$cmd ne "report1" && $cmd ne "report2" && $cmd ne "refreshvalues" &&
    	defined($readings->{$cmd}) && $readings->{$cmd}{VAL} eq $val) {
    	$ret .= "Lazy mode ignores $cmd";
    	Log GetLogLevel($name,2), "Lazy mode ignores $cmd $val";

    } else {
	$ncmd++;
    	$allcmd .=" " if($allcmd);
    	$allcmd .= $cmd;
    	$allcmd .= " $val" if($val);
    }
  }

  return "Too many commands specified, an FHT only supports up to 8"
        if($ncmd > 8);

  return $ret if(!$ncmd);

  my $ioname = "";
  $ioname = $hash->{IODev}->{NAME} if($hash->{IODev});
  if($attr{$ioname} && $attr{$ioname}{fhtsoftbuffer}) {
    my $io = $hash->{IODev};
    my %h = (HASH => $hash, CMD => $allcmd, ARG => $arg);

    my $prio = $priority{$cmd};
    $prio = "9" if(!$prio);
    my $key = $prio . ":" . gettimeofday() . ":" . $cmdcount++;

    $io->{SOFTBUFFER}{$key} = \%h;
    doSoftBuffer($io);

  } else {

    IOWrite($hash, "04", $arg);
    Log GetLogLevel($name,2), "FHT set $name $allcmd";

  }

  return $ret;
}


#####################################
sub
FHT_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> FHT CODE" if(int(@a) != 3);
  $a[2] = lc($a[2]);
  return "Define $a[0]: wrong CODE format: specify a 4 digit hex value"
  		if($a[2] !~ m/^[a-f0-9][a-f0-9][a-f0-9][a-f0-9]$/i);


  $hash->{CODE} = $a[2];
  AssignIoPort($hash);

  # Check if the CULs id collides with our id.
  if($hash->{IODev} && $hash->{IODev}{TYPE} eq "CUL") {
     $hash->{IODev}{FHTID} =~ m/^(..)(..)$/;
     my ($i1, $i2) = (hex($1), hex($2));
     $a[2] =~ m/^(..)(..)$/;
     my ($l1, $l2) = (hex($1), hex($2));

     if($l2 == $i2 && $l1 >= $i1 && $l1 <= $i1+7) {
       my $err = "$a[0]: CODE collides with the FHTID of the corresponding CUL";
       Log 1, $err;
       return $err;
     }
  }

  $modules{FHT}{defptr}{$a[2]} = $hash;
  $attr{$a[0]}{retrycount} = 3;

  #Log GetLogLevel($a[0],2),"Asking the FHT device $a[0]/$a[2] to send its data";
  #FHT_Set($hash, ($a[0], "report1", "255", "report2", "255"));

  return undef;
}

#####################################
sub
FHT_Undef($$)
{
  my ($hash, $name) = @_;
  delete($modules{FHT}{defptr}{$hash->{CODE}}) if($hash && $hash->{CODE});
  return undef;
}

#####################################
sub
FHT_Parse($$)
{
  my ($hash, $msg) = @_;

  $msg = lc($msg);
  my $dev = substr($msg, 16, 4);
  my $cde = substr($msg, 20, 2);
  my $val = substr($msg, 26, 2) if(length($msg) > 26);
  my $confirm = 0;

  if(!defined($modules{FHT}{defptr}{$dev})) {
    Log 3, "FHT Unknown device $dev, please define it";
    return "UNDEFINED FHT_$dev FHT $dev";
  }

  my $def = $modules{FHT}{defptr}{$dev};
  my $name = $def->{NAME};
  return "" if(IsIgnored($name));

  my $io = $def->{IODev};
  my $ll4 = GetLogLevel($name,4);

  # Short message
  if(length($msg) < 26)  {
    Log $ll4,"FHT Short message. Device $name, Message: $msg";
    return "";
  }

  if($io->{TYPE} eq "CUL") {
    $confirm = 1;

  } elsif(!$val || $cde eq "65" || $cde eq "66") {
    # This is a confirmation message. We reformat it so that
    # it looks like a real message, and let the rest parse it
    Log $ll4, "FHT $name confirmation: $cde";
    $val = substr($msg, 22, 2);
    $confirm = 1;
  }

  $val = hex($val);

  my $cmd = $codes{$cde};
  if(!$cmd) {
    Log $ll4, "FHT $name (Unknown: $cde => $val)";
    $def->{CHANGED}[0] = "unknown_$cde: $val";
    return $name;
  }

  my $tn = TimeNow();

  # counter for notifies
  my $nc = 0;

  ###########################
  # Reformat the values so they are readable.
  # The first four are confirmation messages, so they must be converted to
  # the same format as the input (for the softbuffer)

  if($cmd =~ m/-from/ || $cmd =~ m/-to/) {
    $val = sprintf("%02d:%02d", $val/6, ($val%6)*10);

  } elsif($cmd eq "mode") {
    $val = $c2m{$val} if(defined($c2m{$val}));

  } elsif($cmd =~ m/.*-temp/) {
    $val = sprintf("%.1f", $val / 2)

  } elsif($cmd eq "lowtemp-offset") {
    $val = sprintf("%d.0", $val)

  } elsif($cmd =~ m/^actuator/) {

    my $sval = lc(substr($msg,24,2));
    my $fv = sprintf("%d%%", int(100*$val/255+0.5));

       if($sval =~ m/[ab]0/) { $val = $fv; }   # sync in the summer
    elsif($sval =~ m/.0/)    { $val = "syncnow"; }
    elsif($sval =~ m/.1/)    { $val = "99%" } # FHT set to 30.5, FHT80B=="ON"
    elsif($sval =~ m/.2/)    { $val = "0%" }  # FHT set to  5.5
    elsif($sval =~ m/.6/)    { $val = "$fv" }
    elsif($sval =~ m/.8/)    { $val = "offset: " . ($val>128?(128-$val):$val) }
    elsif($sval =~ m/[23]a/) { $val = "lime-protection" }
    elsif($sval =~ m/[ab]a/) { $val = $fv } # lime protection bug
    elsif($sval =~ m/.c/)    { $val = sprintf("synctime: %d", int($val/2)-1); }
    elsif($sval =~ m/.e/)    { $val = "test" }
    elsif($sval =~ m/.f/)    { $val = "pair" }

    else { $val = "unknown_$sval: $fv" }

  } elsif($cmd eq "measured-low") {
    $def->{READINGS}{$cmd}{TIME} = $tn;
    $def->{READINGS}{$cmd}{VAL} = $val;
    return "";

  } elsif($cmd eq "measured-high") {
    $def->{READINGS}{$cmd}{TIME} = $tn;
    $def->{READINGS}{$cmd}{VAL} = $val;

    if(defined($def->{READINGS}{"measured-low"}) &&
       defined($def->{READINGS}{"measured-low"}{VAL})) {

      my $off = ($attr{$name} && $attr{$name}{tmpcorr}) ?
                        $attr{$name}{tmpcorr} : 0;
      $val = $val*256 + $def->{READINGS}{"measured-low"}{VAL};
      $val /= 10;
      $val = sprintf("%.1f (Celsius)", $val+$off);
      $cmd = "measured-temp";

    } else {
      return "";
    }

  } elsif($cmd eq "warnings") {
    my $nVal;

    # initialize values for additional warnings
    my $valBattery;
    my $valLowTemp;
    my $valWindow;
    my $valSensor;
    my $nBattery;
    my $nLowTemp;
    my $nWindow;
    my $nSensor;

    # parse warnings
    if($val & 1) {
      $nVal  = "Battery low";
      $nBattery = "low";
    }
    if($val & 2) {
      $nVal .= "; " if($nVal); $nVal .= "Temperature too low";
      $nLowTemp = "warn";
    }
    if($val &32) {
      $nVal .= ", " if($nVal); $nVal .= "Window open";
      $nWindow = "open";
    }
    if($val &16) {
      $nVal .= ", " if($nVal); $nVal .= "Fault on window sensor";
      $nSensor = "fault";
    }

    # set default values or new values if they were changed
    $valBattery = $nBattery? $nBattery : "ok";
    $valLowTemp = $nLowTemp? $nLowTemp : "ok";
    $valWindow  = $nWindow? $nWindow : "closed";
    $valSensor  = $nSensor? $nSensor : "ok";
    $val = $nVal? $nVal : "none";

    # set additional warnings and trigger notify
    $def->{READINGS}{'battery'}{TIME} = $tn;
    $def->{READINGS}{'battery'}{VAL} = $valBattery;
    $def->{CHANGED}[$nc] = "battery: $valBattery";
    Log $ll4, "FHT $name battery: $valBattery";
    $nc++;

    $def->{READINGS}{'lowtemp'}{TIME} = $tn;
    $def->{READINGS}{'lowtemp'}{VAL} = $valLowTemp;
    $def->{CHANGED}[$nc] = "lowtemp: $valLowTemp";
    Log $ll4, "FHT $name lowtemp: $valLowTemp";
    $nc++;

    $def->{READINGS}{'window'}{TIME} = $tn;
    $def->{READINGS}{'window'}{VAL} = $valWindow;
    $def->{CHANGED}[$nc] = "window: $valWindow";
    Log $ll4, "FHT $name window: $valWindow";
    $nc++;

    $def->{READINGS}{'windowsensor'}{TIME} = $tn;
    $def->{READINGS}{'windowsensor'}{VAL} = $valSensor;
    $def->{CHANGED}[$nc] = "windowsensor: $valSensor";
    Log $ll4, "FHT $name windowsensor: $valSensor";
    $nc++;
  }

  if(substr($msg,24,1) eq "7") {        # Do not store FHZ acks.
    $cmd = "FHZ:$cmd";

  } else {
    $def->{READINGS}{$cmd}{TIME} = $tn;
    $def->{READINGS}{$cmd}{VAL} = $val;
    $def->{STATE} = "$cmd: $val" if($cmd eq "measured-temp");
  }
  $def->{CHANGED}[$nc] = "$cmd: $val";

  Log $ll4, "FHT $name $cmd: $val";

  ################################
  # Softbuffer: delete confirmed commands
  if($confirm) {
    my $found;
    foreach my $key (sort keys %{$io->{SOFTBUFFER}}) {
      my $h = $io->{SOFTBUFFER}{$key};
      my $hcmd = $h->{CMD};
      my $hname = $h->{HASH}->{NAME};
      Log $ll4, "FHT softbuffer check: $hname / $hcmd";
      if($hname eq $name && $hcmd =~ m/^$cmd $val/) {
        $found = $key;
        Log $ll4, "FHT softbuffer found";
        last;
      }
    }
    delete($io->{SOFTBUFFER}{$found}) if($found);
  }

  return $name;
}


# Check the softwarebuffer and send/resend commands
sub
doSoftBuffer($)
{
  my ($io) = @_;

  my $now = gettimeofday();

  my $count = 0;
  my $fhzbuflen = -999;
  foreach my $key (keys %{ $io->{SOFTBUFFER} }) {

    $count++;
    my $h = $io->{SOFTBUFFER}{$key};
    my $name = $h->{HASH}->{NAME};
    if($h->{NSENT}) {
      next if($now-$h->{SENDTIME} < $retryafter);
      my $retry = $attr{$name}{retrycount};
      if($h->{NSENT} > $retry) {
        Log GetLogLevel($name,2), "$name set $h->{CMD}: ".
                          "no confirmation after $h->{NSENT} tries, giving up";
        delete($io->{SOFTBUFFER}{$key});
        next;
      }

    }
    # Check if it is still in the CUL buffer.
    if($io->{TYPE} eq "CUL") {
      my $cul = CallFn($io->{NAME}, "GetFn", $io, (" ", "raw", "T02"));
      my $arg = uc($h->{ARG});
      $arg =~ s/^020183//;
      $arg =~ s/(....)/,$1/g;
      $arg =~ s/,(....),/$1:/;
      $arg = uc($arg);
      if($cul =~ m/$arg/) {
        Log GetLogLevel($name,3), "fhtsoftbuffer: $name set $h->{CMD} ".
                "is still in the culfw buffer, wont send it again";
        $h->{SENDTIME} = $now;
        $h->{NSENT}++;
        next;
      }
    }

    $fhzbuflen = getFhtBuffer($io) if($fhzbuflen == -999);
    my $arglen = length($h->{ARG})/2 - 2;       # Length in bytes

    next if($fhzbuflen < $arglen || $fhzbuflen < getFhtMin($io));
    IOWrite($h->{HASH}, "04", $h->{ARG});
    Log GetLogLevel($name,2), "FHT set $name $h->{CMD}";

    $fhzbuflen -= $arglen;
    $h->{SENDTIME} = $now;
    $h->{NSENT}++;
  }

  if($count && !$io->{SOFTBUFFERTIMER}) {
    $io->{SOFTBUFFERTIMER} = 1;
    InternalTimer(gettimeofday()+30, "softBufferTimer", $io, 0);
  }
}

#####################################
# Wrapper for the InternalTimer
sub
softBufferTimer($)
{
  my ($io) = @_;
  delete($io->{SOFTBUFFERTIMER});
  doSoftBuffer($io);
}

#####################################
sub
getFhtMin($)
{
  my ($io) = @_;
  my $ioname = $io->{NAME};
  return $attr{$ioname}{minfhtbuffer}
        if($attr{$ioname} && $attr{$ioname}{minfhtbuffer});
  return $defmin;
}

#####################################
# get the FHZ hardwarebuffer without logentry as decimal value
sub
getFhtBuffer($)
{
  my ($io) = @_;
  my $count = 0;

  return getFhtMin($io) if(IsDummy($io->{NAME}));

  for(;;) {
    return 0 if(!defined($io->{FD}));    # Avoid crash if the CUL/FHZ is absent
    my $msg = CallFn($io->{NAME}, "GetFn", $io, (" ", "fhtbuf"));
    Log 5, "getFhtBuffer: $count $msg";
    return hex($1) if($msg && $msg =~ m/=> ([0-9A-F]+)$/i);
    return 0 if($count++ >= 5);
  }
}

1;
