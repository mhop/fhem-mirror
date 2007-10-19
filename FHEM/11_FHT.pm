##############################################
package main;

use strict;
use warnings;

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
  "help" 	  => 1,
  "refreshvalues" => 1,
);

my %priority = (
  "desired-temp"	=> 1,	
  "mode"		=> 2,	
  "refreshvalues"	=> 3,	
  "holiday1"	=> 4,	
  "holiday2"	=> 5,	
  "day-temp"	=> 6,	
  "night-temp"	=> 7,	
);

my %c2m = (0 => "auto", 1 => "manual", 2 => "holiday", 3 => "holiday_short");
my %m2c;						# Reverse c2m
my %c2b;						# command->button hash (reverse of codes)
my %c2bset;						# Setteable values
my %defptr;

my $timerCheckBufferIsRunning	= 0;		# set to 1 if the timer is running
my $minFhzHardwareBufferSpace	= 10;		# min. bytes free in hardware buffer before sending commands
my $fhzHardwareBufferSpace	= 0;		# actual hardware buffer space in fhz

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
  $hash->{AttrList}  = "do_not_notify:0,1 model;fht80b dummy:0,1 showtime:0,1 loglevel:0,1,2,3,4,5,6";
}

# Parse the incomming commands and send them via sendCommand to the FHZ
# or via toSendbuffer in the Softwarebuffer (queue)
#
sub FHT_Set($@)
{
  my ($hash, @a)	= @_;
  my $ret		= undef;
  my $arg		= "020183" . $hash->{CODE} . $c2bset{$a[1]};
  my $val		= $a[2];

  return "\"set $a[0]\" needs two parameters" if(@a < 2);
  return "Unknown argument $a[1], choose one of " .
		join(" ", sort {$c2bset{$a} cmp $c2bset{$b} } keys %c2bset)
  		if(!defined($c2bset{$a[1]}));
  return "\"set $a[0]\" needs two parameters"
            if(@a != 3 && !(@a == 2 && $nosetarg{$a[1]}));

  if($a[1] eq "refreshvalues") {
  	
  } elsif ($a[1] =~ m/-temp/) {
    return "Invalid temperature, use NN.N" if($val !~ m/^\d*\.?\d+$/);

    # additional check for temperature
    return "Invalid temperature, must between 5.5 and 30.5" if($val < 5.5 || $val > 30.5);

    my $a = int($val*2);
    $arg .= sprintf("%02x", $a);
    $ret = sprintf("Rounded temperature to %.1f", $a/2) if($a/2 != $val);
    $val = sprintf("%.1f", $a/2) if($a/2 != $val);
    $val = sprintf("%.1f", $val);

  } elsif($a[1] =~ m/-from/ || $a[1] =~ m/-to/) {
    return "Invalid timeformat, use HH:MM" if($val !~ m/^([0-2]\d):([0-5]\d)/);
    my $a = ($1*6) + ($2/10);
    $arg .= sprintf("%02x", $a);

    my $nt = sprintf("%02d:%02d", $1, ($2/10)*10);
    $val = $nt if($nt ne $val);
    $ret = "Rounded time to $nt" if($nt ne $val);

  } elsif($a[1] eq "mode") {
    return "Invalid mode, use one of " . join(" ", sort keys %m2c)
      if(!defined($m2c{$val}));
    $arg .= sprintf("%02x", $m2c{$val});

  } elsif ($a[1] eq "lowtemp-offset") {
    return "Invalid lowtemperature-offset, use N" if($val !~ m/^\d*\.?\d+$/);

    # additional check for temperature
    return "Invalid lowtemperature-offset, must between 1 and 5" if($val < 1 || $val > 5);

    my $a = int($val);
    $arg .= sprintf("%02x", $a);
    $ret = sprintf("Rounded temperature to %d.0", $a) if($a != $val);
    $val = "$a.0";

  } else {	# Holiday1, Holiday2
    $arg .= sprintf("%02x", $val);
  }
  
  my $dev		= $hash->{CODE};
  my $def		= $defptr{$dev};
  my $name		= $def->{NAME};
  my $type		= $a[1];
  my $sbCount = keys(%{$def->{SENDBUFFER}});		# Count of sendbuffer

  # get firsttime hardware buffer of FHZ if $fhzHardwareBufferSpace not set
  $fhzHardwareBufferSpace	= getFhzBuffer () if ($fhzHardwareBufferSpace == 0);

  # set default values for config value attr FHZ softbuffer
  $attr{FHZ}{softbuffer}	= 1 if (!defined($attr{FHZ}{softbuffer}));

  $val = "" if (!defined($val));

  if ( ($sbCount == 0 && $fhzHardwareBufferSpace >= $minFhzHardwareBufferSpace) || $attr{FHZ}{softbuffer} == 0) {
    sendCommand ($hash, $arg, $name, $type, $val);					# send command direct to FHZ 
  } else {

    Log GetLogLevel($name,2), "FHT set $name $type $val (Enqueue to buffer)"	if ($fhzHardwareBufferSpace >= $minFhzHardwareBufferSpace);

    Log GetLogLevel($name,2), "Can't send command set $name $type $val. " .
                              "No space left in FHZ hardware buffer."		if($fhzHardwareBufferSpace < $minFhzHardwareBufferSpace);

  }

  # only if softbuffer not disabled via config
  if ($attr{FHZ}{softbuffer} == 1) {
    toSendbuffer ($hash, $type, $val, $arg, "", 0);					# send command also to buffer

    if ($timerCheckBufferIsRunning == 0 && $init_done) {
      $timerCheckBufferIsRunning = 1;							# set $timerCheckBufferIsRunning to 1 to remeber a timer is running
      InternalTimer(gettimeofday()+70, "timerCheckBuffer", $hash);		# start internal Timer to periodical check the buffer
    }
  }

  return $ret;
}


# Send command to FHZ
#
sub sendCommand ($$$$$)
{

  my ($hash, $arg, $name, $type, $val) = @_;

  if($type eq "refreshvalues") {
    # This is special. Without the sleep the next FHT won't send its data
    if(!IsDummy($name)) {
      my $havefhz;
      $havefhz = 1 if($hash->{IODev} && defined($hash->{IODev}->{FD}));

      IOWrite($hash, "04", $arg);
      sleep(1) if($havefhz);
      IOWrite($hash, "04", "c90185");  # Check the fht buffer
      sleep(1) if($havefhz);
    }
  } else {
    IOWrite($hash, "04", $arg) if(!IsDummy($name));
  }

  Log GetLogLevel($name,2), "FHT set $name $type $val";

  # decrease $fhzHardwareBufferSpace for each command sending to the FHZ
  $fhzHardwareBufferSpace = $fhzHardwareBufferSpace -5 if(!IsDummy($name));
}


sub resendCommand ($)
{

  my ($buffer)	= @_;
  my $hash		= $buffer->{HASH};
  my $dev		= $hash->{CODE};
  my $def		= $defptr{$dev};
  my $nRetry	= $buffer->{RETRY} + 1;

  if ($fhzHardwareBufferSpace > $minFhzHardwareBufferSpace) {
    Log GetLogLevel($def->{NAME},2), "Resending command to FHT set " . $def->{NAME} . " " . $buffer->{TYPE} . " " .  $buffer->{VAL} .
                                     " (Retry $nRetry / ". $attr{FHZ}{softmaxretry} . ")";

    sendCommand ($buffer->{HASH}, $buffer->{ARG}, $buffer->{NAME}, $buffer->{TYPE}, $buffer->{VAL});
    toSendbuffer ($buffer->{HASH}, $buffer->{TYPE}, $buffer->{VAL}, $buffer->{ARG}, $buffer->{KEY}, $nRetry);	# send command also to buffer

  } else {
    Log GetLogLevel($def->{NAME},2), "Can't send command \"set " . $def->{NAME} . " " . $buffer->{TYPE} . " " . $buffer->{VAL} .
                                     "\". No space in FHZ hardware buffer left. Resending next time if free bufferspace available.";
  }
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
  $defptr{$a[2]} = $hash;

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

  $fhzHardwareBufferSpace = getFhzBuffer () if ($fhzHardwareBufferSpace == 0);

  if(!defined($defptr{$dev})) {
    Log 3, "FHT Unknown device $dev, please define it";
    return "UNDEFINED FHT $dev";
  }

  my $def = $defptr{$dev};

  # Unknown, but don't want report it. Should come with c409c401
  return "" if($cde eq "00");

  if(length($cde) < 6) {
    my $name = $def->{NAME};
    Log GetLogLevel($name,2), "FHT Unknown code from $name : $cde";
    $def->{CHANGED}[0] = "unknown code $cde";
    return $name;
  }


  if(!$val) {
    # This is a confirmation message. We reformat it so that
    # it looks like a real message, and let the rest parse it
    Log 4, "FHT $def->{NAME} confirmation: $cde)";
    $val = substr($cde, 2, 2);

    # get the free hardware buffer space in the FHZ after each confirmation message
    $fhzHardwareBufferSpace = hex substr($cde, 4, 2);
    
    # increase $fhzHardwareBufferSpace at 5 because the confirmed command is deleted in the FHZ after confirmation
    $fhzHardwareBufferSpace = $fhzHardwareBufferSpace + 5;
    Log 4, "FHZ new FHT Buffer: $fhzHardwareBufferSpace";

    $cde = substr($cde, 0, 2) . "0069";

    # set help var to remember this is a confirmation
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
    Log 4, "FHT $def->{NAME} (Unknown: $cde => $val)";
    $def->{CHANGED}[0] = "unknown $cde: $val";
    return $def->{NAME};
  }

  my $tn = TimeNow();

  ###########################
  # Reformat the values so they are readable

  if($type eq "actuator") {
    $val = sprintf("%02d%%", int(100*$val/255 + 0.5));
  } elsif($type eq "lime-protection") {
    $val = sprintf("(actuator: %02d%%)", int(100*$val/255 + 0.5));
  } elsif($cde ge "140069" && $cde le "2f0069") {	# Time specs
    Log 5, "FHT $def->{NAME} ($type: $val)";
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

    my @nVal;
    $nVal[0] = "Battery low"			if ($val &  1);
    $nVal[1] = "Window open"			if ($val & 32);
    $nVal[2] = "Fault on window sensor"	if ($val & 16);
    $nVal[3] = "Temperature to low"		if ($val & 2);

    if ($val > 0) {
      $val = "";
      foreach (@nVal) {
        $val .= "$_; " if (defined($_));
      }
      $val = substr($val, 0, length($val)-2);
    } else {
      $val = "none";
    }

  } elsif($type eq "lowtemp-offset") {
    $val = sprintf("%d.0 (Celsius)", $val)

  } elsif($type =~ m/echo_/) {		# Ignore these messages
    return "";
    
  }

  $def->{READINGS}{$type}{TIME} = $tn;
  $def->{READINGS}{$type}{VAL} = $val;

  Log 4, "FHT $def->{NAME} ($type: $val)";

  ###########################################################################
  # here starts the processing the confirmation to control the softwarebuffer
  #

  $attr{FHZ}{softbuffer} = 1 if (!defined($attr{FHZ}{softbuffer}));			# set default values for config value attr FHZ softbuffer

  my $sbCount = keys(%{$def->{SENDBUFFER}});							# count the existing sendbuffer
  my $nsCount = keys(%{$def->{NOTSEND}});								# count the existing failbuffer

  if ($confirm && ($sbCount > 0 || $nsCount > 0) && $attr{FHZ}{softbuffer} == 1) {
    $type = "refreshvalues" if ($type eq "init");

    my ($sbPr, $sbTs);
    my $sbType = "";
    my $sbVal;
    my $dKey; 

    my ($val2) = split (/\s/, $val);

    # if the confirmation message for a command recive to late
    # (the command moved to the notsend list yet)
    # found the specific command ond delete them from the notsend list
    foreach my $c (sort keys %{$def->{NOTSEND}}) {						# go through the notsend list
      ($sbPr, $sbTs, $sbType) = split (/:/, $c);
      $sbVal = $def->{NOTSEND}->{$c}{VAL};
      $dKey = $c;

      $sbVal = $val2 if ($type eq "refreshvalues");						# refreshvalues have no value
      if ($sbType eq $type && $sbVal eq $val2) {

        Log GetLogLevel($def->{NAME},2), "FHT $def->{NAME} late - confirmation ". 
                                        "($sbType: $sbVal) (delete from NOTSEND)";

        delete($def->{NOTSEND}{$dKey});								# delete command from notsend list
        last;												# we can leave the loop because the command was deleted from the list
      }
    }

    # get the next entry from the buffer queue
    foreach my $c (sort keys %{$def->{SENDBUFFER}}) {
      ($sbPr, $sbTs, $sbType) = split (/:/, $c);
      $sbVal = $def->{SENDBUFFER}->{$c}{VAL};
      $dKey = $c;
      last;													# exit foreach because we need the first entry only
    }

    $sbVal = $val2 if ($type eq "refreshvalues");						# refreshvalues have no value

    # if the actual confirmation message part of the first command in the queue
    if ($sbType eq $type && $sbVal eq $val2) {
      delete($def->{SENDBUFFER}{$dKey});								# this buffer entry can deleted

      foreach my $c (sort keys %{$def->{SENDBUFFER}}) {					# get the next buffer entry
        my $nType = $def->{SENDBUFFER}->{$c}{TYPE};
        my $nArg = $def->{SENDBUFFER}->{$c}{ARG};
        my $nName = $def->{SENDBUFFER}->{$c}{NAME};
        my $nHash = $def->{SENDBUFFER}->{$c}{HASH};
        my $nVal = $def->{SENDBUFFER}->{$c}{VAL};
        my $nKey = $def->{SENDBUFFER}->{$c}{KEY};

        sendCommand ($nHash, $nArg, $nName, $nType, $nVal);					# nächsten Buffereintrag senden
        toSendbuffer ($nHash, $nType, $nVal, $nArg, $nKey, 0);	# send command also to buffer

        last;												# exit foreach because we need the next entry only
      }
    }
  }

  #
  # end processing confirmation to control the softwarebuffer
  ###########################################################################

  $def->{CHANGED}[0] = "$type: $val";
  $def->{STATE} = "$type: $val" if($type eq "measured-temp");
  return $def->{NAME};
}

# check are commands in softwarebuffer
# ans send the next command to the FHZ
sub timerCheckBuffer ($)
{

  Log 4, "Timer (Checking for unsend FHT commands)";

  my ($hash) = @_;
  my $bufCount = 0;										# help counter
  my $now = gettimeofday();
  my $ts = time;
  
  # set default values for config value attr FHZ softbuffer
  $attr{FHZ}{softrepeat} = 240 if (!defined($attr{FHZ}{softrepeat}));
  $attr{FHZ}{softmaxretry} = 3 if (!defined($attr{FHZ}{softmaxretry}));

  # loop to process all FHT devices
  foreach my $d (keys %defptr) {
    my $def = $defptr{$d};									# the actual FHT device

    # process all buffer entries
    foreach my $c (sort keys %{$def->{SENDBUFFER}}) {
      my ($rPr, undef, $rType) = split (/:/, $c);					# priority and type
      my $rVal = $def->{SENDBUFFER}{$c}{VAL};						# value
	my $rTs = $def->{SENDBUFFER}{$c}{SENDTIME};					# the time of the sending moment to the FHT
	my $rRetry = $def->{SENDBUFFER}{$c}{RETRY};					# retry counter
	$rRetry ++ if ($fhzHardwareBufferSpace > $minFhzHardwareBufferSpace);	# increase retrycounter if enough hardwarebuffer available
      my $rKey = $c;										# the bufferkey

      $rVal = "" if (!defined($rVal));							# set value to "" if value not defined (e.g. "refreshvalues" have no value)
      $bufCount ++;										# increase $bufCount
      
      my $buffer = $def->{SENDBUFFER}{$c};						# actual buffer entry

      # if the forst command in buffer to old, resend them again to the FHZ
	if ($ts-$rTs > $attr{FHZ}{softrepeat}) {
	  if ($rRetry <= $attr{FHZ}{softmaxretry}) {					# resend the command only if the max resend amount not reached
          resendCommand ($buffer);								# resend the actual command
        } else {
          # command resend fail after "softmaxretry" attempt to send
          Log GetLogLevel($def->{NAME},2), $def->{NAME} . " $rType $rVal no confirmation after $rRetry retry";
          $def->{NOTSEND}{$rKey} = $def->{SENDBUFFER}{$rKey};			# put the buffer entry to the notsend list
          $def->{NOTSEND}{$rKey}{RETRY} = $rRetry;
          delete($def->{SENDBUFFER}{$rKey});						# delete command from buffer queue
        }
      }
      last												# exit foreach because we need only the first buffer value
    }
  }

  if ($bufCount > 0) {
    Log 4, "Refresh FHT resend timer";
    InternalTimer(gettimeofday()+70, "timerCheckBuffer", $hash);			# restart the internal Timer if any buffer contains commands
  } else {
    $timerCheckBufferIsRunning = 0;								# remember timer is not running anymore
  }
}

# set given command tothe internal software buffer
# each command queued until the previous command become a confirmation
#
sub toSendbuffer ($$$$)
{

  my ($hash, $type, $val, $arg, $nBufferKey, $retry) = @_;

  if (!$init_done || $attr{FHZ}{softbuffer} == 0) {
  	return
  }

  my $dev		= $hash->{CODE};
  my $def		= $defptr{$dev};
  
  my $tn		= TimeNow();							# Readable time
  my $ts		= time;								# Unix timestamp
  my $pr		= 9;									# Default priority for command
  my $sendTime	= 0;									# Timestamp for last sending command
  my $sbCount	= keys(%{$def->{SENDBUFFER}});				# Count of sendbuffer

  $pr			= $priority{$type} if (defined($priority{$type}));	# get priority for specific command type
  $val		= "" if (!defined($val));

  if ($sbCount == 0) {
    $pr		= 0;									# First command in buffer have always priority 0 (highest)
    $sendTime	= $ts;
  }

  my $bufferKey	= "$pr:$ts:$type";						#Default bufferkey
  
  # if bufferkey existing. delete the entry and save the entry with a new buffer
  if ($nBufferKey ne "") {
  	$sendTime = $ts;
	$bufferKey = $nBufferKey;
      ($pr, $ts, $type) = split (/:/, $bufferKey);
      delete($def->{SENDBUFFER}{$bufferKey});					# delete "old" bufferentry

      $bufferKey = "0:$ts:$type";							# new bufferkey für new bufferentry
  }

  $def->{SENDBUFFER}{$bufferKey}{TIME}		= $tn;
  $def->{SENDBUFFER}{$bufferKey}{VAL}		= $val;
  $def->{SENDBUFFER}{$bufferKey}{NAME}		= $def->{NAME};
  $def->{SENDBUFFER}{$bufferKey}{TYPE}		= $type;
  $def->{SENDBUFFER}{$bufferKey}{ARG}		= $arg;
  $def->{SENDBUFFER}{$bufferKey}{SENDTIME}	= $sendTime;
  $def->{SENDBUFFER}{$bufferKey}{RETRY}		= $retry;
  $def->{SENDBUFFER}{$bufferKey}{KEY}		= $bufferKey;
  $def->{SENDBUFFER}{$bufferKey}{HASH}		= $hash;
}

1;
