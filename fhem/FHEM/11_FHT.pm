# $Id$
##############################################################################
#
#     11_FHT.pm
#     Copyright by 
#     e-mail: 
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Foobar is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################
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

# { Dispatch($defs{CUL}, "810b04028309830151024130001d", undef) }
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
  $hash->{AttrList}  = "IODev do_not_notify:1,0 model:fht80b dummy:1,0 " .
                       "showtime:1,0 retrycount " .
                       "minfhtbuffer lazy tmpcorr ignore:1,0 ".
                       $readingFnAttributes;
  $hash->{AutoCreate}=
           { "FHT.*" => { GPLOT => "fht:Temp/Act,", FILTER => "%NAME" } };
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

    if(!defined($c2b{$cmd})) {
      my $cmdList = join(" ",sort keys %c2bset);
      my @list = map { ($_.".0", $_+0.5) } (6..30);
      pop @list;
      my $tmpList="on,off,".join(",",@list);
      $cmdList =~ s/-temp/-temp:$tmpList/g;     # FHEMWEB sugar
      $cmdList =~ s/(-from.|-to.)/$1:time/g;
      return "Unknown argument $cmd, choose one of $cmdList";
    }

    return "Readonly parameter $cmd"
                if(defined($cantset{$cmd}));
    return "\"set $name $cmd\" needs a parameter"
                if(@a < 1);

    $val = shift(@a);
    $arg .= $c2b{$cmd};

    if ($cmd =~ m/-temp/) {

      if(!($val eq "on" || $val eq "off" ||
          ($val =~ m/^\d*\.?\d+$/ && $val >= 5.5 && $val <= 30.5))) {
        my @list = map { ($_.".0", $_+0.5) } (6..30);
        pop @list;
        return "Invalid temperature $val, choose one of on off "
                . join(" ",@list);
      }

      $val = 30.5 if($val eq "on");
      $val =  5.5 if($val eq "off");
      my $a = int($val*2);
      $arg .= sprintf("%02x", $a);
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

      return "Invalid mode, choose one of " . join(" ", sort keys %m2c)
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
    	Log3 $name, 2, "Lazy mode ignores $cmd $val";

    } else {
	$ncmd++;
    	$allcmd .=" " if($allcmd);
    	$allcmd .= $cmd;
    	$allcmd .= " $val" if(defined($val));
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
    Log3 $name, 2, "FHT set $name $allcmd";

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
       Log3 $a[0], 1, $err;
       return $err;
     }
  }

  $modules{FHT}{defptr}{$a[2]} = $hash;
  $attr{$a[0]}{retrycount} = 3;

  #Log3 $a[0], 2, "Asking the FHT device $a[0]/$a[2] to send its data";
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
  my $val = (length($msg) > 26 ? substr($msg, 26, 2) : undef);
  my $confirm = 0;

  if(!defined($modules{FHT}{defptr}{$dev})) {
    # it might be our own FHT8v, then be silent
    foreach my $d (%defs) {
      my $dp = $defs{$d};
      next if(!$dp->{TYPE} || $dp->{TYPE} ne "FHT8V");
      return "" if($dp->{addr} eq $dev);
    }

    Log3 $hash, 3, "FHT Unknown device $dev, please define it";
    return "UNDEFINED FHT_$dev FHT $dev";
  }

  my $def = $modules{FHT}{defptr}{$dev};
  my $name = $def->{NAME};
  return "" if(IsIgnored($name));

  my $io = $def->{IODev};

  # Short message
  if(length($msg) < 26)  {
    Log3 $name, 4, "FHT Short message. Device $name, Message: $msg";
    return "";
  }

  if($io->{TYPE} eq "CUL") {
    $confirm = 1;

  } elsif(!$val || $cde eq "65" || $cde eq "66") {
    # This is a confirmation message. We reformat it so that
    # it looks like a real message, and let the rest parse it
    Log3 $name, 4, "FHT $name confirmation: $cde";
    $val = substr($msg, 22, 2);
    $confirm = 1;
  }

  $val = hex($val);

  my $cmd = $codes{$cde};
  if(!$cmd) {
    Log3 $name, 4, "FHT $name (Unknown: $cde => $val)";
    readingsSingleUpdate($def, "unknown_$cde", $val, 1);
    return $name;
  }


  #
  # special treatment for measured-temp which is actually sent in two bytes
  #

  # the measured temperature comes in two bytes: measured-low and measured-high
  # measured-temp= (measured-high * 256 + measured-low) / 10.
  # measured-low and measured-high will only be stored as internals
  if($cmd eq "measured-low") {
    $def->{".measuredLow"}= $val;
    return "";
        
  } elsif($cmd eq "measured-high") {

    $def->{".measuredHigh"}= $val;

    if(defined($def->{".measuredLow"})) {

      $val = sprintf("%.1f", ($val*256.0 + $def->{".measuredLow"})/10.0+
                                AttrVal($name, "tmpcorr", 0.0));
      $cmd = "measured-temp";
    } else {
      return "";

    }
  }

  #
  # from here readings are effectively updated
  #
  readingsBeginUpdate($def);

  # The first four are confirmation messages, so they must be converted to
  # the same format as the input (for the softbuffer)

  if($cmd =~ m/-from/ || $cmd =~ m/-to/) {
    $val = sprintf("%02d:%02d", $val/6, ($val%6)*10);

  } elsif($cmd eq "mode") {
    $val = $c2m{$val} if(defined($c2m{$val}));

  } elsif($cmd =~ m/.*-temp/ && $cmd ne "measured-temp") {
    $val = sprintf("%.1f", $val / 2);
    if($cmd eq "desired-temp") {
      $val = ($val > 30 ? "on" : ($val < 6 ? "off" : $val));
    }

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
    readingsBulkUpdate($def, "battery", $valBattery);
    Log3 $name, 4, "FHT $name battery: $valBattery";

    readingsBulkUpdate($def, "lowtemp", $valLowTemp);
    Log3 $name, 4, "FHT $name lowtemp: $valLowTemp";

    readingsBulkUpdate($def, "window", $valWindow);
    Log3 $name, 4, "FHT $name window: $valWindow";

    readingsBulkUpdate($def, "windowsensor", $valSensor);
    Log3 $name, 4, "FHT $name windowsensor: $valSensor";
  }

  $cmd = "FHZ:$cmd" if(substr($msg,24,1) eq "7");

  readingsBulkUpdate($def, $cmd, $val);
  if($cmd eq "measured-temp") {
    readingsBulkUpdate($def, "state", "measured-temp: $val", 0);
    readingsBulkUpdate($def, "temperature", $val); # For dewpoint
  }    

  Log3 $name, 4, "FHT $name $cmd: $val";

  #
  # now we are done with updating readings
  #
  readingsEndUpdate($def, 1);

  ################################
  # Softbuffer: delete confirmed commands
  if($confirm) {
    my $found;
    foreach my $key (sort keys %{$io->{SOFTBUFFER}}) {
      my $h = $io->{SOFTBUFFER}{$key};
      my $hcmd = $h->{CMD};
      my $hname = $h->{HASH}->{NAME};
      Log3 $name, 4, "FHT softbuffer check: $hname / $hcmd";
      if($hname eq $name && $hcmd =~ m/^$cmd $val/) {
        $found = $key;
        Log3 $name, 4, "FHT softbuffer found";
        last;
      }
    }
    delete($io->{SOFTBUFFER}{$found}) if($found);
  }

  return $name;
}

#####################################
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
        Log3 $name, 2, "$name set $h->{CMD}: ".
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
        Log3 $name, 3, "fhtsoftbuffer: $name set $h->{CMD} ".
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
    Log3 $name, 2, "FHT set $name $h->{CMD}";

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
    Log3 $io, 5, "getFhtBuffer: $count $msg";
    return hex($1) if($msg && $msg =~ m/=> ([0-9A-F]+)$/i);
    return 0 if($count++ >= 5);
  }
}

1;

=pod
=begin html

<a name="FHT"></a>
<h3>FHT</h3>
<ul>
  Fhem can receive FHT radio (868.35 MHz) messages either through an <a
  href="#FHZ">FHZ</a> or an <a href="#CUL">CUL</a> device, so this must be
  defined first.<br><br>

  <a name="FHTdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FHT &lt;fhtaddress&gt;</code>
    <br><br>

    <code>&lt;fhtaddress&gt;</code> is a four digit hex number,
    corresponding to the address of the FHT80b device.
    <br>

    Examples:
    <ul>
      <code>define wz FHT 3232</code><br>
    </ul>
    <br>
    See the FHT section in <a href="#set">set</a> for more.
  </ul>
  <br>

  <a name="FHTset"></a>
  <b>Set </b>
  <ul>
    <code>set &lt;name&gt; &lt;valuetype&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is one of:<br>
    <ul><code>
      desired-temp<br>
      day-temp night-temp<br>
      report1 report2<br>
      refreshvalues<br>
      mode<br>
      holiday1 holiday2      # see mode holiday_short or holiday<br>
      manu-temp              # No clue what it does.<br>
      year month day hour minute<br>
      time date<br>
      lowtemp-offset         # Alarm-Temp.-Differenz<br>
      windowopen-temp<br>
      mon-from1 mon-to1 mon-from2 mon-to2<br>
      tue-from1 tue-to1 tue-from2 tue-to2<br>
      wed-from1 wed-to1 wed-from2 wed-to2<br>
      thu-from1 thu-to1 thu-from2 thu-to2<br>
      fri-from1 fri-to1 fri-from2 fri-to2<br>
      sat-from1 sat-to1 sat-from2 sat-to2<br>
      sun-from1 sun-to1 sun-from2 sun-to2<br>
    </code></ul>

    Examples:
    <ul>
      <code>set wz desired-temp 22.5</code><br>
      <code>set fl desired-temp 20.5 day-temp 19.0 night-temp 16.0</code><br>
    </ul>
    <br>

    Notes:
    <ul>
      <li>Following events are reported (more or less regularly) by each FHT
          device: <code>measured-temp actuator actuator1...actuator8
          warnings</code><br>
          You can use these strings for <a href="#notify">notify</a> or
          <a href="#FileLog">FileLog</a> definitions.
          <ul>
            <li>warnings can contain following strings:
                none, Battery low,Temperature too low, Window open,
                Fault on window sensor
                </li>
            <li>actuator (without a suffix) stands for all actuators.</li>
            <li>actuator or actuator1..8 can take following values:
                <ul>
                  <li>&lt;value&gt;%<br>
                     This is the normal case, the actuator is instructed to
                     open to this value.
                     </li>
                  <li>offset &lt;value&gt;%<br>
                     The actuator is running with this offset.
                     </li>
                  <li>lime-protection<br>
                     The actuator was instructed to execute the lime-protection
                     procedure.
                     </li>
                  <li>synctime<br>
                     If you select Sond/Sync on the FHT80B, you'll see a count
                     down.
                     </li>
                  <li>test<br>
                     The actuator was instructed by the FHT80b to emit a beep.
                     </li>
                  <li>pair<br>
                     The the FHT80b sent a "you-belong-to-me" to this actuator.
                     </li>
                </ul></li>
          </ul></li>
          <br>

      <li>The FHT is very economical (or lazy), it accepts one message from the
          FHZ1x00 every 115+x seconds, where x depends on the fhtaddress. Don't
          be surprised if your command is only accepted 10 minutes later by the
          device. FHT commands are buffered in the FHZ1x00/CUL till they are
          sent to the FHT, see the related <code>fhtbuf</code> entry in the
          <code><a href="#get">get</a></code> section.<br> You can send up to 8
          commands in one message at once to the FHT if you specify them all as
          arguments to the same set command, see the example above.
          </li>
          <br>

      <li>time sets hour and minute to local time</li><br>

      <li>date sets year, month and date to local time</li><br>

      <li>refreshvalues is an alias for report1 255 report2 255</li><br>

      <li>All <code>*-temp</code> values need a temperature
          as argument, which will be rounded to 0.5 Celsius.<br>
          Temperature values must  between 5.5 and 30.5 Celsius. Value 5.5 sets
          the actuator to OFF, value 30.5 set the actuator to ON</li><br>

      <li><code>mode</code> is one of <code>auto, manual, holiday or
          holiday_short.</code><br>
          If the mode is holiday, then the mode switches back to either auto or
          manual at 00:00 of the day specified by the following:
            <ul>
              <li>holiday1 sets the end-day of the holiday</li>
              <li>holiday2 sets the end-month of the holiday</li>
            </ul>
          For holiday_short (party mode)
          <ul>
              <li> holiday1 sets the absolute hour to switch back from this
              mode (in 10-minute steps, max 144)</li>
              <li> holiday2 sets the day of month to switch back from this mode
              (can only be today or tomorrow, since holiday1 accepts only 24
              hours).</li>
              Example:
              <ul>
                  <li>current date is 29 Jan, time is 18:05</li>
                  <li>you want to switch to party mode until tomorrow 1:00</li>
                  <li>set holiday1 to 6 (6 x 10min = 1hour) and holiday2 to
                      30</li>

              </ul>
          </ul>
          The temperature for the holiday period is set by the desired-temperature
          parameter. <br> Note that you cannot set holiday mode for days earlier than the
          day after tomorrow, for this you must use holiday_short.<br>
          Note also, you cannot set parameters seperately, you must set them in one command.
          Example:
          <br>
	  <code>set FHT1 mode holiday holiday1 24 holiday2 12 desired-temp 14</code>
          </li>
          <br>

      <li>The <code>*-from1/*-from2/*-to1/*-to2</code> valuetypes need a time
          spec as argument in the HH:MM format. They define the periods, where
          the day-temp is valid. The minute (MM) will be rounded to 10, and
          24:00 means off.</li><br>

      <li>To synchronize the FHT time and to "wake" muted FHTs it is adviseable
          to schedule following command:<br>
      <code>define fht_sync at  +*3:30 set TYPE=FHT time</code>
          </li>
          <br>

      <li><code>report1</code> with parameter 255 requests all settings for
          monday till sunday to be sent. The argument is a bitfield, to request
          unique values add up the following:
          <ul>
            <li> 1: monday</li>
            <li> 2: tuesday</li>
            <li> 4: thursday</li>
            <li> 8: wednesday</li>
            <li>16: friday</li>
            <li>32: saturday</li>
            <li>64: sunday</li>
          </ul>
          measured-temp and actuator is sent along if it is considered
          appropriate
          by the FHT.
          <br><br>
          <b>Note:</b> This command generates a lot of RF traffic, which can
          lead to further problems, especially if the reception is not clear.
          </li><br>

      <li><code>report2</code> with parameter 255 requests the following
          settings to be reported: day-temp night-temp windowopen-temp
          lowtemp-offset desired-temp measured-temp mode warnings.
          The argument is (more or less) a bitfield, to request unique values
          add up the following:
          <ul>
          <li> 1: warnings</li>
          <li> 2: mode</li>
          <li> 4: day-temp, night-temp, windowopen-temp</li>
          <li>64: lowtemp-offset</li>
          </ul>
          measured-temp and actuator is sent along if it is considered
          appropriate by the FHT.</li>
          <br>

      <li><code>lowtemp-offset</code> needs a temperature as argument, valid
          values must be between 1.0 and 5.0 Celsius.<br> It will trigger a
          warning if <code>desired-temp - measured-temp &gt;
          lowtemp-offset</code> in a room for at least 1.5 hours after the last
          desired-temp change.</li>
          <br>

      <li>FHEM optionally has an internal software buffer for FHT devices.
          This buffer should prevent transmission errors. If there is no
          confirmation for a given period, FHEM resends the command. You can
          see the queued commands with <a href="#list">list</a>
          &lt;fht-device&gt;.
          See the <a href="#fhtsoftbuffer">fhtsoftbuffer</a>,
          <a href="#retrycount">retrycount</a> and
          <a href="#minfhtbuffer">minfhtbuffer</a> attributes for details.
          </li>
          <br>

      <li>If a buffer is still in the softbuffer, it will be sent in the
          following order:<br> <code>desired-temp,mode,report1,report2,
          holiday1,holiday2,day-temp,night-temp, [all other commands]</code>
          </li>
          <br>

    </ul>
  </ul>
  <br>

  <b>Get</b> <ul>N/A</ul><br>

  <a name="FHTattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#attrdummy">dummy</a><br>
      <b>Note:</b>It makes sense to define an FHT device even for an FHT8b,
      else you will receive "unknown FHT device, please define one" message
      for each FHT8b as the CUL is reporting the 8b valve messages.  But you
      should set the dummy attribute for these devices, else the internal FHT
      buffer of the CUL will be filled with data for the 8b's which is never
      consumed. If the buffer is full, you'll get "EOB" messages from the CUL,
      and you cannot transmit any data to the 80b's</li><br>

    <a name="retrycount"></a>
    <li>retrycount<br>
        If the <a href="#fhtsoftbuffer">fhtsoftbuffer</a> attribute is set, then
        resend commands <code>retrycount</code> times if after 240 seconds
        no confirmation message is received from the corresponding FHT
        device.<br>
        Default is 3.</li><br>

    <a name="minfhtbuffer"></a>
    <li>minfhtbuffer<br>
        FHEM won't send commands to the FHZ if its fhtbuffer is below
        this value, default is 0. If this value is low, then the ordering of
        fht commands (see the note in the FHT section of <a href="#set">set</a>)
        has little effect, as only commands in the softbuffer can be
        prioritized. The maximum value should be 7 below the hardware maximum
        (see fhtbuf).
        </li><br>

    <a name="lazy"></a>
    <li>lazy<br>
        If the lazy attribute is set, FHEM won't send commands to the FHT if
        the current reading and the value to be set are already identical. This
        may help avoiding conflicts with the max-1%-time-on-air rule in large
        installations. Not set per default.
        </li><br>

    <a name="tmpcorr"></a>
    <li>tmpcorr<br>
        Correct the temperature reported by the FHT by the value specified.
        Note: only the measured-temp value reported by fhem (used for logging)
        will be modified.
        </li><br>

    <li><a href="#ignore">ignore</a></li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#model">model</a> (fht80b)</li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#IODev">IODev</a></li>
    <li><a href="#eventMap">eventMap</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>

  </ul>
  <br>

  <a name="FHTevents"></a>
  <b>Generated events:</b>
  <ul>
     <li>actuator</li>
     <li>actuator1 actuator2 actuator3 actuator4<br>
         actuator5 actuator6 actuator7 actuator8<br>
         (sent if you configured an offset for the associated valve)</li>
     <li>mon-from1 mon-to1 mon-from2 mon-to2</li>
     <li>tue-from1 tue-to1 tue-from2 tue-to2</li>
     <li>wed-from1 wed-to1 wed-from2 wed-to2</li>
     <li>thu-from1 thu-to1 thu-from2 thu-to2</li>
     <li>fri-from1 fri-to1 fri-from2 fri-to2</li>
     <li>sat-from1 sat-to1 sat-from2 sat-to2</li>
     <li>sun-from1 sun-to1 sun-from2 sun-to2</li>
     <li>mode</li>
     <li>holiday1 holiday2</li>
     <li>desired-temp</li>
     <li>measured-temp measured-low measured-high</li>
     <li>warnings</li>
     <li>manu-temp</li>
     <li>year month day hour minute</li>
     <li>day-temp night-temp lowtemp-offset windowopen-temp</li>
     <li>ack can-xmit can-rcv ack2 start-xmit end-xmit
         (only if the CUL is configured to transmit FHT protocol data)</li>
  </ul>
  <br>

</ul>

=end html
=cut
