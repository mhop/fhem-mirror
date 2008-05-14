##############################################
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);


sub FHZ_Write($$$);
sub FHZ_Read($);
sub FHZ_ReadAnswer($$);
sub FhzCrc(@);
sub CheckFhzCrc($);
sub XmitLimitCheck($$);

my $msgstart = pack('H*', "81");# Every msg starts wit this

my %gets = (
  "init1"  => "c9 02011f64",
  "init2"  => "c9 02011f60",
  "init3"  => "c9 02011f0a",
  "serial" => "04 c90184570208",
  "fhtbuf" => "04 c90185",
);
my %sets = (
  "time"     => "c9 020161",
  "initHMS"  => "04 c90186",
  "initFS20" => "04 c90196",
  "FHTcode"  => "04 c901839e0101",

  "activefor"=> "xx xx",
  "raw"      => "xx xx",
);
my %setnrparam = (
  "time"     => 0,
  "initHMS"  => 0,
  "initFS20" => 0,
  "FHTcode"  => 1,
  "activefor"=> 1,
  "raw"      => 2,
);

my %codes = (
  "^8501..\$" => "fhtbuf",
);

my $def;
my %msghist;		# Used when more than one FHZ is attached
my $msgcount = 0;
my $xmit_limit = 163;   # Maximum nr of transmissions per hour (unconfirmed).

#####################################
# Note: we are a data provider _and_ a consumer at the same time
sub
FHZ_Initialize($)
{
  my ($hash) = @_;


# Provider
  $hash->{ReadFn}  = "FHZ_Read";
  $hash->{WriteFn} = "FHZ_Write";
  $hash->{Clients} = ":FHZ:FS20:FHT:HMS:KS300:";

# Consumer
  $hash->{Match}   = "^81..C9..0102";
  $hash->{DefFn}   = "FHZ_Define";
  $hash->{UndefFn} = "FHZ_Undef";
  $hash->{GetFn}   = "FHZ_Get";
  $hash->{SetFn}   = "FHZ_Set";
  $hash->{StateFn} = "FHZ_SetState";
  $hash->{ParseFn} = "FHZ_Parse";
  $hash->{ReadyFn} = "FHZ_Ready" if ($^O eq 'MSWin32');
  $hash->{AttrList}= "do_not_notify:1,0 dummy:1,0 filtertimeout repeater:1,0 " .
                   "showtime:1,0 model:fhz1000,fhz1300 loglevel:0,1,2,3,4,5,6 ".
                   "fhtsoftbuffer:1,0"; 
}
#####################################
sub
FHZ_Ready($$)
{
  my ($hash, $dev) = @_;
  my $po=$hash->{PortObj};
  return undef if !$po;
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags)=$po->status;
  return ($InBytes>0);
}
#####################################
sub
FHZ_Set($@)
{
  my ($hash, @a) = @_;

  return "Need one to three parameter" if(@a < 2);
  return "Unknown argument $a[1], choose one of " . join(" ", sort keys %sets)
  	if(!defined($sets{$a[1]}));
  return "Need one to three parameter" if(@a > 4);
  return "Wrong number of parameters for $a[1], need " . ($setnrparam{$a[1]}+2)
  	if(@a != ($setnrparam{$a[1]} + 2));

  my ($fn, $arg) = split(" ", $sets{$a[1]});

  my $v = join(" ", @a);
  my $name = $hash->{NAME};
  Log GetLogLevel($name,2), "FHZ set $v";

  if($a[1] eq "activefor") {

    my $dhash = $defs{$a[2]};
    return "device $a[2] unknown" if(!defined($dhash));

    return "Cannot handle $dhash->{TYPE} devices"
    		if($modules{FHZ}->{Clients} !~ m/:$dhash->{TYPE}:/);

    $dhash->{IODev} = $hash;
    return undef;

  } elsif($a[1] eq "raw") {

    $fn = $a[2];
    $arg = $a[3];

  } elsif($a[1] eq "time") {

    my @t = localtime;
    $arg .= sprintf("%02x%02x%02x%02x%02x",
    	$t[5]%100, $t[4]+1, $t[3], $t[2], $t[1]);

  } elsif($a[1] eq "FHTcode") {

    return "invalid argument, must be hex" if(!$a[2] ||
					       $a[2] !~ m/^[A-F0-9]{2}$/);
    $arg .= $a[2];

  }

  FHZ_Write($hash, $fn, $arg) if(!IsDummy("FHZ"));
  return undef;
}

#####################################
sub
FHZ_Get($@)
{
  my ($hash, @a) = @_;

  return "\"get FHZ\" needs only one parameter" if(@a != 2);
  return "Unknown argument $a[1], choose one of " . join(",", sort keys %gets)
  	if(!defined($gets{$a[1]}));

  my ($fn, $arg) = split(" ", $gets{$a[1]});

  my $v = join(" ", @a);
  my $name = $hash->{NAME};
  Log GetLogLevel($name,2), "FHZ get $v";

  FHZ_Write($hash, $fn, $arg) if(!IsDummy("FHZ"));

  my $msg = FHZ_ReadAnswer($hash, $a[1]);
  return $msg if(!$msg || $msg !~ /^81..c9..0102/);

  if($a[1] eq "serial") {
    $v = substr($msg, 22, 8)

  } elsif($a[1] eq "fhtbuf") {
    $v = substr($msg, 16, 2);

  } else {
    $v = substr($msg, 12);
  }
  $hash->{READINGS}{$a[1]}{VAL} = $v;
  $hash->{READINGS}{$a[1]}{TIME} = TimeNow();

  return "$a[0] $a[1] => $v";
}

#####################################
sub
FHZ_SetState($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;

  return "Undefined value $vt" if(!defined($gets{$vt}));
  return undef;
}


#####################################
sub
DoInit($)
{
  my $name = shift;
  my @init;
  push(@init, "get $name init2");
  push(@init, "get $name serial");
  push(@init, "set $name initHMS");
  push(@init, "set $name initFS20");
  push(@init, "set $name time");

  # Workaround: Sending "set 0001 00 off" after initialization to enable
  # the fhz1000 receiver, else we won't get anything reported.
  push(@init, "set $name raw 04 01010100010000");

  CommandChain(3, \@init);

  # Reset the counter
  my $hash = $defs{$name};
  delete($hash->{XMIT_TIME});
  delete($hash->{NR_CMD_LAST_H});
}

#####################################
sub
FHZ_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $po;
  $hash->{STATE} = "Initialized";

  delete $hash->{PortObj};
  delete $hash->{FD};

  my $name = $a[0];
  my $dev = $a[2];

  $attr{$name}{savefirst} = 1;
  $attr{$name}{fhtsoftbuffer} = 0;

  if($dev eq "none") {
    Log 1, "FHZ device is none, commands will be echoed only";
    $attr{$name}{dummy} = 1;
    return undef;
  }
  
  Log 3, "FHZ opening FHZ device $dev";
  if ($^O=~/Win/) {
   require Win32::SerialPort;
   $po = new Win32::SerialPort ($dev);
  } else  {
   require Device::SerialPort;
   $po = new Device::SerialPort ($dev);
  }
  return "Can't open $dev: $!\n" if(!$po);
  Log 3, "FHZ opened FHZ device $dev";

  $po->reset_error();
  $po->baudrate(9600);
  $po->databits(8);
  $po->parity('none');
  $po->stopbits(1);
  $po->handshake('none');

  # This part is for some Linux kernel versions whih has strange default
  # settings.  Device::SerialPort is nice: if the flag is not defined for your
  # OS then it will be ignored.
  $po->stty_icanon(0);
  #$po->stty_parmrk(0); # The debian standard install does not have it
  $po->stty_icrnl(0);
  $po->stty_echoe(0);
  $po->stty_echok(0);
  $po->stty_echoctl(0);

  # Needed for some strange distros
  $po->stty_echo(0);
  $po->stty_icanon(0);
  $po->stty_isig(0);
  $po->stty_opost(0);
  $po->stty_icrnl(0);
  $po->write_settings;


  $hash->{PortObj} = $po;
  $hash->{FD} = $po->FILENO if !( $^O =~ /Win/ );  
  
  
  $hash->{DeviceName} = $dev;
  $hash->{PARTIAL} = "";

  DoInit($name);

  return undef;
}

#####################################
sub
FHZ_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  foreach my $d (sort keys %defs) {
    if(defined($defs{$d}) &&
       defined($defs{$d}{IODev}) &&
       $defs{$d}{IODev} == $hash)
      {
        Log GetLogLevel($name,2), "deleting port for $d";
        delete $defs{$d}{IODev};
      }
  }
  $hash->{PortObj}->close() if($hash->{PortObj});
  return undef;
}

#####################################
sub
FHZ_Parse($$)
{
  my ($hash,$msg) = @_;

  my $omsg = $msg;
  $msg = substr($msg, 12);	# The first 12 bytes are not really interesting

  my $type = "";
  my $name = $hash->{NAME};
  foreach my $c (keys %codes) {
    if($msg =~ m/$c/) {
      $type = $codes{$c};
      last;
    }
  }

  if(!$type) {
    Log 4, "FHZ $name unknown: $omsg";
    $def->{CHANGED}[0] = "$msg";
    return $hash->{NAME};
  }


  if($type eq "fhtbuf") {
    $msg = substr($msg, 4, 2);
  }

  Log 4, "FHZ $name $type: $msg";
  $def->{CHANGED}[0] = "$type: $msg";
  return $hash->{NAME};
}

#####################################
sub
FhzCrc(@)
{
  my $sum = 0;
  map { $sum += $_; } @_;
  return $sum & 0xFF;
}

#####################################
sub
CheckFhzCrc($)
{
  my $msg = shift;
  return 0 if(length($msg) < 8);

  my @data;
  for(my $i = 8; $i < length($msg); $i += 2) {
    push(@data, ord(pack('H*', substr($msg, $i, 2))));
  }
  my $crc = hex(substr($msg, 6, 2));

  # FS20 Repeater generate a CRC which is one or two greater then the computed
  # one. The FHZ1000 filters such pakets, so we do not see them
  return (($crc eq FhzCrc(@data)) ? 1 : 0);
}


#####################################
# This is a direct read for commands like get
sub
FHZ_ReadAnswer($$)
{
  my ($hash,$arg) = @_;

  return undef if(!$hash || !defined($hash->{FD}));

  my ($mfhzdata, $rin) = ("", '');
  my $nfound;
  for(;;) {
    if($^O eq 'MSWin32') {
      $nfound=FHZ_Ready($hash,$def);
    } else {
      vec($rin, $hash->{FD}, 1) = 1;
       $nfound = select($rin, undef, undef, 3); # 3 seconds timeout
      if($nfound < 0) {
        next if ($! == EAGAIN() || $! == EINTR() || $! == 0);
        die("Select error $nfound / $!\n");
      }
    }
    return "Timeout reading answer for get $arg" if($nfound == 0);

    my $buf = $hash->{PortObj}->input();

    Log 5, "FHZ/RAW: " . unpack('H*',$buf);
    $mfhzdata .= $buf;
    next if(length($mfhzdata) < 2);

    my $len = ord(substr($mfhzdata,1,1)) + 2;
    if($len>20) {
      Log 4, "Oversized message (" . unpack('H*',$mfhzdata) .
      				"), dropping it ...";
      return undef;
    }
    return unpack('H*', $mfhzdata) if(length($mfhzdata) == $len);
  }
}

##############
sub
FHZ_CompleteMsg($$)
{
  my ($fn,$msg) = @_;
  my $len = length($msg);
  my @data;
  for(my $i = 0; $i < $len; $i += 2) {
    push(@data, ord(pack('H*', substr($msg, $i, 2))));
  }
  return pack('C*', 0x81, $len/2+2, ord(pack('H*',$fn)), FhzCrc(@data), @data);
}

    
#####################################
# Check if the 1% limit is reached and trigger notifies
sub
XmitLimitCheck($$)
{
  my ($hash,$bstring) = @_;
  my $now = time();

  $bstring = unpack('H*', $bstring);
  return if($bstring =~ m/c90185$/); # fhtbuf

  if(!$hash->{XMIT_TIME}) {
    $hash->{XMIT_TIME}[0] = $now;
    $hash->{NR_CMD_LAST_H} = 1;
    return;
  }

  my $nowM1h = $now-3600;
  my @b = grep { $_ > $nowM1h } @{$hash->{XMIT_TIME}};

  if(@b > $xmit_limit) {

    my $me = $hash->{NAME};
    Log GetLogLevel($me,2), "FHZ TRANSMIT LIMIT EXCEEDED";
    DoTrigger($me, "TRANSMIT LIMIT EXCEEDED");

  } else {

    push(@b, $now);

  }
  $hash->{XMIT_TIME} = \@b;
  $hash->{NR_CMD_LAST_H} = int(@b);
}

#####################################
sub
FHZ_Write($$$)
{
  my ($hash,$fn,$msg) = @_;

  if(!$hash || !defined($hash->{PortObj})) {
    Log 5, "FHZ device $hash->{NAME} is not active, cannot send";
    return;
  }

  ###############
  # insert value into the msghist. At the moment this only makes sense for FS20
  # devices. As the transmitted value differs from the received one, we have to
  # recompute.
  if($fn eq "04" && substr($msg,0,6) eq "010101") {
    my $nmsg = "0101a001" . substr($msg, 6, 6) . "00" . substr($msg, 12);
    $msghist{$msgcount}{TIME} = gettimeofday();
    $msghist{$msgcount}{NAME} = $hash->{NAME};
    $msghist{$msgcount}{MSG}  = unpack('H*', FHZ_CompleteMsg($fn, $nmsg));
    $msgcount++;
  }

  my $bstring = FHZ_CompleteMsg($fn, $msg);
  Log 5, "Sending " . unpack('H*', $bstring);

  if(!$hash->{QUEUECNT}) {

    XmitLimitCheck($hash,$bstring);
    $hash->{PortObj}->write($bstring);

    ##############
    # Write the next buffer not earlier than 0.22 seconds (= 65.6ms + 10ms +
    # 65.6ms + 10ms + 65.6ms), else it will be discarded by the FHZ1X00 PC
    InternalTimer(gettimeofday()+0.25, "FHZ_HandleWriteQueue", $hash, 1);

  } elsif($hash->{QUEUECNT} == 1) {
    $hash->{QUEUE} = [ $bstring ];
  } else {
    push(@{$hash->{QUEUE}}, $bstring);
  }
  $hash->{QUEUECNT}++;


}

#####################################
sub
FHZ_HandleWriteQueue($)
{
  my $hash = shift;
  my $cnt = --$hash->{QUEUECNT};
  if($cnt > 0) {
    my $bstring = shift(@{$hash->{QUEUE}});
    XmitLimitCheck($hash,$bstring);
    $hash->{PortObj}->write($bstring);
    InternalTimer(gettimeofday()+0.25, "FHZ_HandleWriteQueue", $hash, 1);
  }
}

#####################################
sub
FHZ_Read($)
{
  my ($hash) = @_;

  my $buf = $hash->{PortObj}->input();
  my $iohash = $modules{$hash->{TYPE}};
  my $name = $hash->{NAME};

  ###########
  # Lets' try again: Some drivers return len(0) on the first read...
  if(defined($buf) && length($buf) == 0) {
    $buf = $hash->{PortObj}->input();
  }

  if(!defined($buf) || length($buf) == 0) {

    my $devname = $hash->{DeviceName};
    Log 1, "USB device $devname disconnected, waiting to reappear";
    $hash->{PortObj}->close();
    for(;;) {
      sleep(5);
      if ($^O eq 'MSWin32') {
        $hash->{PortObj} = new Win32::SerialPort($devname);
      }else{
        $hash->{PortObj} = new Device::SerialPort($devname);  
      }
      
      if($hash->{PortObj}) {
        Log 1, "USB device $devname reappeared";
        $hash->{FD} = $hash->{PortObj}->FILENO if !($^O eq 'MSWin32');
        DoInit($name);
	return;
      }
    }
  }

  my $fhzdata = $hash->{PARTIAL};
  Log 5, "FHZ/RAW: " . unpack('H*',$buf) .
      " (Unparsed: " . unpack('H*', $fhzdata) . ")";
  $fhzdata .= $buf;

  while(length($fhzdata) > 2) {

    ###################################
    # Skip trash.
    my $si = index($fhzdata, $msgstart);
    if($si) {
      if($si == -1) {
	Log(5, "Bogus message received, no start character found");
	$fhzdata = "";
	last;
      } else {
	Log(5, "Bogus message received, skipping to start character");
	$fhzdata = substr($fhzdata, $si);
      }
    }

    my $len = ord(substr($fhzdata,1,1)) + 2;
    if($len>20) {
      Log 4,
	 "Oversized message (" . unpack('H*',$fhzdata) . "), dropping it ...";
      $fhzdata = "";
      next;
    }

    last if(length($fhzdata) < $len);

    my $dmsg = unpack('H*', substr($fhzdata, 0, $len));
    if(CheckFhzCrc($dmsg)) {

      if(substr($fhzdata,2,1) eq $msgstart) { # Skip function 0x81
	$fhzdata = substr($fhzdata, 2);
	next;
      }

      ###############
      # check for duplicate msg from different FHZ's
      my $now = gettimeofday();
      my $skip;
      my $meetoo = ($attr{$name}{repeater} ? 1 : 0);

      my $to = 3;
      if(defined($attr{$name}) && defined($attr{$name}{filtertimeout})) {
        $to = $attr{$name}{filtertimeout};
      }
      foreach my $oidx (keys %msghist) {
        if($now-$msghist{$oidx}{TIME} > $to) {
	  delete($msghist{$oidx});
          next;
        }
	if($msghist{$oidx}{MSG} eq $dmsg &&
           ($meetoo || $msghist{$oidx}{NAME} ne $name)) {
          Log 5, "Skipping $msghist{$oidx}{MSG}";
	  $skip = 1;
	}
      }
      goto NEXTMSG if($skip);
      $msghist{$msgcount}{TIME} = $now;
      $msghist{$msgcount}{NAME} = $name;
      $msghist{$msgcount}{MSG}  = $dmsg;
      $msgcount++;


      my @found;
      my $last_module;
      foreach my $m (sort { $modules{$a}{ORDER} cmp $modules{$b}{ORDER} }
		      grep {defined($modules{$_}{ORDER});}keys %modules) {
	next if($iohash->{Clients} !~ m/:$m:/);
	next if($dmsg !~ m/$modules{$m}{Match}/i);
	no strict "refs";
	@found = &{$modules{$m}{ParseFn}}($hash,$dmsg);
	use strict "refs";
        $last_module = $m;
	last if(int(@found));
      }
      if(!int(@found)) {
	Log 1, "Unknown code $dmsg, help me!";
	goto NEXTMSG;
      }

      goto NEXTMSG if($found[0] eq "");	# Special return: Do not notify

      if($found[0] =~ m/^(UNDEFINED) ([^ ]*) (.*)$/) {
	my $d = $1;
	$defs{$d}{NAME} = $1;
	$defs{$d}{TYPE} = $last_module;
	DoTrigger($d, "$2 $3");
	delete $defs{$d};
	goto NEXTMSG;
      }

      foreach my $found (@found) {
	DoTrigger($found, undef);
      }
NEXTMSG:
      $fhzdata = substr($fhzdata, $len);

    } else {

      Log 4, "Bad CRC message, skipping it (Bogus message follows)";
      $fhzdata = substr($fhzdata, 2);

    }
  }
  $hash->{PARTIAL} = $fhzdata;
}

1;
