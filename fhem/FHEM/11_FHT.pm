##############################################
package main;

use strict;
use warnings;

sub doSoftBuffer($);
sub softBufferTimer($);
sub sendCommand($$$$);

my %codes = (
  "0000.6" => "actuator",	
  "00002c" => "synctime",		# Not verified
  "0100.6" => "actuator1",		# Not verified (1-8)
  "0200.6" => "actuator2",
  "0300.6" => "actuator3",
  "0400.6" => "actuator4",
  "0500.6" => "actuator5",
  "0600.6" => "actuator6",
  "0700.6" => "actuator7",
  "0800.6" => "actuator8",
  "140069" => "mon-from1",
  "150069" => "mon-to1",
  "160069" => "mon-from2",
  "170069" => "mon-to2",
  "180069" => "tue-from1",
  "190069" => "tue-to1",
  "1a0069" => "tue-from2",
  "1b0069" => "tue-to2",
  "1c0069" => "wed-from1",
  "1d0069" => "wed-to1",
  "1e0069" => "wed-from2",
  "1f0069" => "wed-to2",
  "200069" => "thu-from1",
  "210069" => "thu-to1",
  "220069" => "thu-from2",
  "230069" => "thu-to2",
  "240069" => "fri-from1",
  "250069" => "fri-to1",
  "260069" => "fri-from2",
  "270069" => "fri-to2",
  "280069" => "sat-from1",
  "290069" => "sat-to1",
  "2a0069" => "sat-from2",
  "2b0069" => "sat-to2",
  "2c0069" => "sun-from1",
  "2d0069" => "sun-to1",
  "2e0069" => "sun-from2",
  "2f0069" => "sun-to2",
  "3e0069" => "mode",
  "3f0069" => "holiday1",		# Not verified
  "400069" => "holiday2",		# Not verified
  "410069" => "desired-temp",
  "XX0069" => "measured-temp",		# sum of next. two, never "really" sent
  "420069" => "measured-low",
  "430069" => "measured-high",
  "440069" => "warnings",
  "450069" => "manu-temp",		# Manuelle Temperatur keine ahnung was das bewirkt
  "600069" => "year",
  "610069" => "month",
  "620069" => "day",
  "630069" => "hour",
  "640069" => "minute",
  "650069" => "init",
  "820069" => "day-temp",
  "840069" => "night-temp",
  "850069" => "lowtemp-offset",	# Alarm-Temp.-Differenz
  "8a0069" => "windowopen-temp",
  "00002a" => "lime-protection",
  "0000aa" => "code_0000aa",
  "0000ba" => "code_0000ba",
  "430079" => "code_430079",
  "440079" => "code_440079",
  "4b0067" => "code_4b0067",
  "4b0077" => "code_4b0077",
  "7e0067" => "code_7e0067",
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
  "synctime"      => 1,
  "measured-temp" => 1,
  "measured-high" => 1,
  "measured-low"  => 1,
  "warnings"       => 1,
  "init"          => 1,
  "lime-protection"=>1,

  "code_0000aa"   => 1,
  "code_0000ba"   => 1,
  "code_430079"   => 1,
  "code_440079"   => 1,
  "code_4b0067"   => 1,
  "code_4b0077"   => 1,
  "code_7e0067"   => 1,
);

my %nosetarg = (
  "refreshvalues" => 1,
);

my %priority = (
  "desired-temp"=> 1,	
  "mode"	=> 2,	
  "refreshvalues"=> 3,	
  "holiday1"	=> 4,	
  "holiday2"	=> 5,	
  "day-temp"	=> 6,	
  "night-temp"	=> 7,	
);

my %c2m = (0 => "auto", 1 => "manual", 2 => "holiday", 3 => "holiday_short");
my %m2c;	# Reverse c2m
my %c2b;	# command->button hash (reverse of codes)
my %c2bset;	# Setteable values
my %defptr;

my $minFhzHardwareBuffer = 10; # min fhtbuf free bytes before sending commands
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
    $c2bset{$v} = substr($k, 0, 2) if(!defined($cantset{$v}));
  }
  foreach my $k (keys %c2m) {
    $m2c{$c2m{$k}} = $k;
  }
  $c2bset{refreshvalues} = "65ff66ff";

#                        810c0426 0909a001 1111 1600
#                        810c04b3 0909a001 1111 44006900
#                        810b0402 83098301 1111 41301d
#                        81090421 c409c401 1111 00
#                        810c0d20 0909a001 3232 7e006724 (NYI)
  $hash->{Match}     = "^81..(04|09|0d)..(0909a001|83098301|c409c401)..";
  $hash->{SetFn}     = "FHT_Set";
  $hash->{StateFn}   = "FHT_SetState";
  $hash->{DefFn}     = "FHT_Define";
  $hash->{UndefFn}   = "FHT_Undef";
  $hash->{ParseFn}   = "FHT_Parse";
  $hash->{AttrList}  = "do_not_notify:0,1 model;fht80b dummy:0,1 " .
                  "showtime:0,1 loglevel:0,1,2,3,4,5,6 retrycount";
}


sub
FHT_Set($@)
{
  my ($hash, @a) = @_;
  my $ret;

  return "\"set $a[0]\" needs at least two parameters" if(@a < 2);

  my $name    = shift(@a);

  my $ncmd = 0;
  my $arg = "020183" . $hash->{CODE};
  my ($cmd, $val) = ("", "");

  while(@a) {
    my $lcmd = shift(@a);

    $cmd .=" " if($cmd);
    $cmd .= $lcmd;

    return "Unknown argument $lcmd, choose one of " .
                join(" ", sort {$c2bset{$a} cmp $c2bset{$b} } keys %c2bset)
                if(!defined($c2bset{$lcmd}));
    return "\"set $name\" needs a parameters"
                if(@a < 1 && !$nosetarg{$lcmd});
    $ncmd++;

    if(!$nosetarg{$lcmd}) {
      $val = shift(@a);
      $cmd .= " $val";
    } else {
      $val = undef;
    }

    $arg .= $c2bset{$lcmd};

    if ($lcmd =~ m/-temp/) {

      return "Invalid temperature, use NN.N" if($val !~ m/^\d*\.?\d+$/);
      return "Invalid temperature, must between 5.5 and 30.5"
                          if($val < 5.5 || $val > 30.5);
      my $a = int($val*2);
      $arg .= sprintf("%02x", $a);
      $ret = sprintf("Rounded temperature to %.1f", $a/2) if($a/2 != $val);
      $val = sprintf("%.1f", $a/2);

    } elsif($lcmd =~ m/-from/ || $lcmd =~ m/-to/) {

      return "Invalid timeformat, use HH:MM"
                        if($val !~ m/^([0-2]\d):([0-5]\d)/);
      my $a = ($1*6) + ($2/10);
      $arg .= sprintf("%02x", $a);

      my $nt = sprintf("%02d:%02d", $1, ($2/10)*10);
      $ret = "Rounded time to $nt" if($nt ne $val);
      $val = $nt;

    } elsif($lcmd eq "mode") {

      return "Invalid mode, use one of " . join(" ", sort keys %m2c)
        if(!defined($m2c{$val}));
      $arg .= sprintf("%02x", $m2c{$val});

    } elsif ($lcmd eq "lowtemp-offset") {

      return "Invalid lowtemperature-offset, must between 1 and 5"
          if($val !~ m/^[1-5]$/);
      $arg .= sprintf("%02x", $val);
      $val = "$val.0";

    } else {	# Holiday1, Holiday2

      $arg .= sprintf("%02x", $val) if(defined($val));

    }
  }

  $val = "" if (!defined($val) || $ncmd > 1);


  my $ioname = "";
  $ioname = $hash->{IODev}->{NAME} if($hash->{IODev});
  if($attr{$ioname} && $attr{$ioname}{fhtsoftbuffer}) {
    if($ncmd > 1) {
      return "Cannot accept multiple FHT commands with fhtsoftbuffer enabled";
    }
    my $io = $hash->{IODev};
    my %h = (HASH => $hash, CMD => $cmd, VAL => $val, ARG => $arg);

    my $prio = $priority{$cmd};
    $prio = "9" if(!$prio);
    my $key = $prio . ":" . gettimeofday() . ":" . $cmdcount++;

    $io->{SOFTBUFFER}{$key} = \%h;
    doSoftBuffer($io);

  } else {

    sendCommand($hash, $cmd, $val, $arg);

  }

  return $ret;
}


#####################################
sub
FHT_SetState($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;

  return "Undefined type $vt" if(!defined($c2b{$vt}));
  return undef;
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
  $hash->{CODE} = $a[2];
  $defptr{$a[2]} = $hash;
  $attr{$a[0]}{retrycount} = 3;

  AssignIoPort($hash);

  Log GetLogLevel($a[0],2),"Asking the FHT device $a[0]/$a[2] to send its data";
  FHT_Set($hash, ($a[0], "refreshvalues"));

  return undef;
}

#####################################
sub
FHT_Undef($$)
{
  my ($hash, $name) = @_;
  delete($defptr{$hash->{CODE}});
  return undef;
}

#####################################
sub 
FHT_Parse($$)
{
  my ($hash, $msg) = @_;

  my $dev = substr($msg, 16, 4);
  my $cde = substr($msg, 20, 6);
  my $val = substr($msg, 26, 2) if(length($msg) > 26);
  my $confirm = 0;

  if(!defined($defptr{$dev})) {
    Log 3, "FHT Unknown device $dev, please define it";
    return "UNDEFINED FHT $dev";
  }

  my $def = $defptr{$dev};
  my $name = $def->{NAME};

  # Unknown, but don't want report it. Should come with c409c401
  return "" if($cde eq "00");

  if(length($cde) < 6) {
    Log GetLogLevel($name,2), "FHT Unknown code from $name : $cde";
    $def->{CHANGED}[0] = "unknown code $cde";
    return $name;
  }

  if(!$val) {
    # This is a confirmation message. We reformat it so that
    # it looks like a real message, and let the rest parse it
    Log 4, "FHT $name confirmation: $cde";
    $val = substr($cde, 2, 2);
    $cde = substr($cde, 0, 2) . "0069";
    $confirm = 1;
  }

  my $type;
  foreach my $c (keys %codes) {
    if($cde =~ m/$c/) {
      $type = $codes{$c};
      last;
    }
  }

  $val =  hex($val);

  if(!$type) {
    Log 4, "FHT $name (Unknown: $cde => $val)";
    $def->{CHANGED}[0] = "unknown $cde: $val";
    return $name;
  }

  my $tn = TimeNow();

  ###########################
  # Reformat the values so they are readable

  if($type eq "actuator") {
    $val = sprintf("%02d%%", int(100*$val/255 + 0.5));
  } elsif($type eq "lime-protection") {
    $val = sprintf("(actuator: %02d%%)", int(100*$val/255 + 0.5));
  } elsif($cde ge "140069" && $cde le "2f0069") {	# Time specs
    Log 5, "FHT $name ($type: $val)";
    return "" if($val == 144);	# Empty, forget it
    my $hour = $val / 6;
    my $min = ($val % 6) * 10;
    $val = sprintf("%02d:%02d", $hour, $min);

  } elsif($type eq "mode") {
    $val = $c2m{$val} if(defined($c2m{$val}));

  } elsif($type eq "measured-low") {

    $def->{READINGS}{$type}{TIME} = $tn;
    $def->{READINGS}{$type}{VAL} = $val;
    return "";

  } elsif($type eq "measured-high") {

    $def->{READINGS}{$type}{TIME} = $tn;
    $def->{READINGS}{$type}{VAL} = $val;

    if(defined($def->{READINGS}{"measured-low"}{VAL})) {

      $val = $val*256 + $def->{READINGS}{"measured-low"}{VAL};
      $val /= 10;
      $val = sprintf("%.1f (Celsius)", $val);
      $type = "measured-temp"

    } else {
      return "";
    }

  } elsif($type =~ m/.*-temp/) {
    $val = sprintf("%.1f (Celsius)", $val / 2)

  } elsif($type eq "warnings") {

    my $nVal;
    if($val & 1) {                          $nVal  = "Battery low"; }
    if($val & 2) { $nVal .= "; " if($nVal); $nVal .= "Temperature too low"; }
    if($val &32) { $nVal .= "; " if($nVal); $nVal .= "Window open"; }
    if($val &16) { $nVal .= "; " if($nVal); $nVal .= "Fault on window sensor"; }
    $val = $nVal? $nVal : "none";

  } elsif($type eq "lowtemp-offset") {
    $val = sprintf("%d.0 (Celsius)", $val)

  }

  $def->{READINGS}{$type}{TIME} = $tn;
  $def->{READINGS}{$type}{VAL} = $val;
  $def->{CHANGED}[0] = "$type: $val";
  $def->{STATE} = "$type: $val" if($type eq "measured-temp");

  Log 4, "FHT $name $type: $val";

  ################################
  # Softbuffer: deleted confirmed commands
  if($confirm) {
    my $found; 
    my $io = $def->{IODev};
    foreach my $key (sort keys %{$io->{SOFTBUFFER}}) {
      my $h = $io->{SOFTBUFFER}{$key};
      my $hcmd = $h->{CMD};
      $hcmd = "init" if($hcmd eq "refreshvalues");
      Log 5, "FHT check $h->{HASH}->{NAME} eq $name && $hcmd eq $type";
      if($h->{HASH}->{NAME} eq $name && $hcmd eq $type) {
        $found = $key;
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
        Log GetLogLevel($name,2), "$name set $h->{CMD} $h->{VAL}: ".
                          "no confirmation after $h->{NSENT} tries, giving up";
        delete($io->{SOFTBUFFER}{$key});
        next;
      }
    }

    $fhzbuflen = getFhzBuffer($io) if($fhzbuflen == -999);
    next if($fhzbuflen < $minFhzHardwareBuffer);
    sendCommand($h->{HASH}, $h->{CMD}, $h->{VAL}, $h->{ARG});
    $fhzbuflen -= ($h->{CMD} eq "refreshvalues" ? 7 : 5);
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
# get the FHZ hardwarebuffer without logentry as decimal value
sub
getFhzBuffer($)
{
  my ($io) = @_;
  my $count = 0;

  return $minFhzHardwareBuffer if(IsDummy($io->{NAME}));

  for(;;) {
    FHZ_Write($io, "04", "c90185");
    my $msg = FHZ_ReadAnswer($io, "fhtbuf");
    Log 5, "getFhzBuffer: $count $msg";
  
    return hex(substr($msg, 16, 2)) if($msg && $msg =~ m/^[0-9A-F]+$/i);
    return 0 if($count++ > 5);
  }
}

#####################################
# Send FHZ command
sub
sendCommand($$$$)
{
  my ($hash, $cmd, $val, $arg) = @_;
  my $name = $hash->{NAME};

  if($cmd eq "refreshvalues") {

    # This is special. Without the sleep the next FHT won't send its data
    if(!IsDummy($name)) {
      my $havefhz = ($hash->{IODev} && defined($hash->{IODev}->{FD}));
      IOWrite($hash, "04", $arg);
      sleep(1) if($havefhz);
    }

  } else {

    IOWrite($hash, "04", $arg) if(!IsDummy($name));

  }
  Log GetLogLevel($name,2), "FHT set $name $cmd $val";
}

1;
