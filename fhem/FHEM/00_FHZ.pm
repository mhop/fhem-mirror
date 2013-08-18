##############################################
# $Id$
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);


sub FHZ_Write($$$);
sub FHZ_Read($);
sub FHZ_ReadAnswer($$$);
sub FHZ_Crc(@);
sub FHZ_CheckCrc($);
sub FHZ_XmitLimitCheck($$);
sub FHZ_DoInit($$$);

my $msgstart = pack('H*', "81");# Every msg starts with this

# See also "FHZ1000 Protocol" http://fhz4linux.info/tiki-index.php?page=FHZ1000%20Protocol

# NOTE: for protocol analysis, especially the "serial" vs. "FHTcode" case
# is interestingly different yet similar:
# - code 0x84 (FHZ area) vs. 0x83 (FHT area),
# - register 0x57, _read_ vs. 0x9e, _write_ (hmm, or is this "house code" 0x9e01?)
# - _read_ 8 nibbles (4 bytes serial), _write_ 1 (1 byte FHTcode - align-corrected to two nibbles, right?)
# I did some few tests already (also scripted tests), no interesting findings so far,
# but despite that torture my 1300PC still works fine ;)

my %gets = (
  "init1"  => "c9 02011f64",
  "init2"  => "c9 02011f60",
  "init3"  => "c9 02011f0a",
  "serial" => "04 c90184570208",
  "fhtbuf" => "04 c90185", # get free FHZ memory (e.g. 23 bytes free)
  # NOTE: there probably is another command to return the number of pending
  # FHT msg submissions in FHZ (including last one), IOW: 1 == "empty";
  # see thread "Kommunikation FHZ1000PC zum FHT80b" for clues;
  # TODO: please analyze in case you use homeputer!!
);
my %sets = (
  "time"     => "c9 020161",
  "initHMS"  => "04 c90186",
  "stopHMS"  => "04 c90197",
  "initFS20" => "04 c90196",
  "initFS20_02" => "04 c9019602", # some alternate variant
  "FHTcode"  => "04 c901839e0101", # (parameter range 1-99, "Zentralencode" in contronics speak; randomly chosen - and forgotten!! - by FHZ, thus better manually hardcode it in fhem.cfg)

  "raw"      => "xx xx",
  "initfull" => "xx xx",
  "reopen"   => "xx xx",
  "close"   => "xx xx",
  "open"   => "xx xx",

);
my %setnrparam = (
  "time"     => 0,
  "initHMS"  => 0,
  "stopHMS"  => 0,
  "initFS20" => 0,
  "initFS20_02" => 0,
  "FHTcode"  => 1,
  "raw"      => 2,
  "initfull" => 0,
  "reopen"   => 0,
  "close"    => 0,
  "open"    => 0,

);

my %codes = (
  "^8501..\$" => "fhtbuf",
);

#####################################
# Note: we are a data provider _and_ a consumer at the same time
sub
FHZ_Initialize($)
{
  my ($hash) = @_;

# Provider
  $hash->{ReadFn}  = "FHZ_Read";
  $hash->{WriteFn} = "FHZ_Write";
  $hash->{Clients} = ":FHZ:FS20:FHT:HMS:KS300:USF1000:BS:";
  my %mc = (
    "1:USF1000" => "^81..(04|0c)..0101a001a5ceaa00....",
    "2:BS"      => "^81..(04|0c)..0101a001a5cf",
    "3:FS20"    => "^81..(04|0c)..0101a001",
    "4:FHT"     => "^81..(04|09|0d)..(0909a001|83098301|c409c401)..",
    "5:HMS"     => "^810e04....(1|5|9).a001",
    "6:KS300"   => "^810d04..4027a001",
  );
  $hash->{MatchList} = \%mc;
  $hash->{ReadyFn} = "FHZ_Ready";

# Consumer
  $hash->{Match}   = "^81..C9..0102";
  $hash->{ParseFn} = "FHZ_Parse";

# Normal devices
  $hash->{DefFn}   = "FHZ_Define";
  $hash->{FingerprintFn} = "FHZ_FingerprintFn";
  $hash->{UndefFn} = "FHZ_Undef";
  $hash->{GetFn}   = "FHZ_Get";
  $hash->{SetFn}   = "FHZ_Set";
  $hash->{AttrList}= "do_not_notify:1,0 dummy:1,0 " .
                   "showtime:1,0 model:fhz1000,fhz1300 ".
                   "fhtsoftbuffer:1,0 addvaltrigger";
}

sub
FHZ_FingerprintFn($$)
{
  my ($name, $msg) = @_;
 
  # Store only the "relevant" part, as the CUL won't compute the checksum
  $msg = substr($msg, 8) if($msg =~ m/^81/ && length($msg) > 8);
 
  return ($name, $msg);
}

#####################################
sub
FHZ_Ready($)
{
  my ($hash) = @_;
  my $po=$hash->{PortObj};

  if(!$po) {    # Looking for the device

    my $dev = $hash->{DeviceName};
    my $name = $hash->{NAME};

    $hash->{PARTIAL} = "";
    if($^O =~ m/Win/) {
     $po = new Win32::SerialPort ($dev);
    } else  {
     $po = new Device::SerialPort ($dev);
    }
    return undef if(!$po);

    Log3 $name, 1, "USB device $dev reappeared";
    $hash->{PortObj} = $po;
    if($^O !~ m/Win/) {
      $hash->{FD} = $po->FILENO;
      delete($readyfnlist{"$name.$dev"});
      $selectlist{"$name.$dev"} = $hash;
    } else {
      $readyfnlist{"$name.$dev"} = $hash;
    }

    FHZ_DoInit($name, $hash->{ttytype}, $po);
    DoTrigger($name, "CONNECTED");
    return undef;

  }

  # This is relevant for windows only
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
  Log3 $name, 2, "FHZ set $v";

  if($a[1] eq "initfull") {

    my @init;
    push(@init, "get $name init2");
    push(@init, "get $name serial");
    push(@init, "set $name initHMS");
    push(@init, "set $name initFS20");
    push(@init, "set $name time");
    push(@init, "set $name raw 04 01010100010000");
    CommandChain(3, \@init);
    return undef;

  } elsif($a[1] eq "reopen") {

    FHZ_Reopen($hash);
    return undef;

  } elsif($a[1] eq "close") {

    FHZ_Close($hash);
    return undef;

  } elsif($a[1] eq "open") {

    FHZ_Open($hash);
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

  FHZ_Write($hash, $fn, $arg) if(!IsDummy($hash->{NAME}));
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
  Log3 $name, 2, "FHZ get $v";

  FHZ_ReadAnswer($hash, "Flush", 0);
  FHZ_Write($hash, $fn, $arg) if(!IsDummy($hash->{NAME}));

  my $msg = FHZ_ReadAnswer($hash, $a[1], 1.0);
  Log3 $name, 5, "GET Got: $msg" if(defined($msg));
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
FHZ_DoInit($$$)
{
  my ($name,$type,$po) = @_;
  my @init;

  $po->reset_error();
  $po->baudrate(9600);
  $po->databits(8);
  $po->parity('none');
  $po->stopbits(1);
  $po->handshake('none');

  if($type && $type eq "strangetty") {

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
  }

  $po->write_settings;


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
  $hash->{STATE} = "Initialized";
  return undef;
}

#####################################
sub
FHZ_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $po;

  return "wrong syntax: define <name> FHZ devicename ".
                        "[normal|strangetty] [mobile]" if(@a < 3 || @a > 5);

  delete $hash->{PortObj};
  delete $hash->{FD};

  my $name = $a[0];
  my $dev = $a[2];
  $hash->{ttytype} = $a[3] if($a[3]);
  $hash->{MOBILE} = 1 if($a[4] && $a[4] eq "mobile");
  $hash->{STATE} = "defined";

  $attr{$name}{fhtsoftbuffer} = 0;

  if($dev eq "none") {
    Log3 $name, 1, "FHZ device is none, commands will be echoed only";
    $attr{$name}{dummy} = 1;
    return undef;
  }

  $hash->{DeviceName} = $dev;
  $hash->{PARTIAL} = "";
  Log3 $name, 3, "FHZ opening FHZ device $dev";
  if($^O =~ m/Win/) {
   require Win32::SerialPort;
   $po = new Win32::SerialPort ($dev);
  } else  {
   require Device::SerialPort;
   $po = new Device::SerialPort ($dev);
  }
  if(!$po) {
    my $msg = "Can't open $dev: $!";
    Log3($name, 3, $msg) if($hash->{MOBILE});
    return $msg if(!$hash->{MOBILE});
    $readyfnlist{"$name.$dev"} = $hash;
    return "";
  }
  Log3 $name, 3, "FHZ opened FHZ device $dev";

  $hash->{PortObj} = $po;
  if($^O !~ m/Win/) {
    $hash->{FD} = $po->FILENO;
    $selectlist{"$name.$dev"} = $hash;
  } else {
    $readyfnlist{"$name.$dev"} = $hash;
  }

  FHZ_DoInit($name, $hash->{ttytype}, $po);
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
        my $lev = ($reread_active ? 4 : 2);
        Log3 $name, $lev, "deleting port for $d";
        delete $defs{$d}{IODev};
      }
  }
  $hash->{PortObj}->close() if($hash->{PortObj});
  delete($hash->{PortObj});
  delete($hash->{FD});
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
    Log3 $name, 4, "FHZ $name unknown: $omsg";
    $hash->{CHANGED}[0] = "$msg";
    return $hash->{NAME};
  }


  if($type eq "fhtbuf") {
    $msg = substr($msg, 4, 2);
  }

  Log3 $name, 4, "FHZ $name $type: $msg";
  $hash->{CHANGED}[0] = "$type: $msg";
  return $hash->{NAME};
}

#####################################
sub
FHZ_Crc(@)
{
  my $sum = 0;
  map { $sum += $_; } @_;
  return $sum & 0xFF;
}

#####################################
sub
FHZ_CheckCrc($)
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
  return (($crc eq FHZ_Crc(@data)) ? 1 : 0);
}


#####################################
# This is a direct read for commands like get
sub
FHZ_ReadAnswer($$$)
{
  my ($hash,$arg, $to) = @_;

  return undef if(!$hash || ($^O!~/Win/ && !defined($hash->{FD})));

  my ($mfhzdata, $rin) = ("", '');
  my $buf;

  for(;;) {

    if($^O =~ m/Win/) {
      $hash->{PortObj}->read_const_time($to*1000); # set timeout (ms)
      # Read anstatt input sonst funzt read_const_time nicht.
      $buf = $hash->{PortObj}->read(999);
      return "Timeout reading answer for get $arg"
        if(length($buf) == 0);

    } else {
      vec($rin, $hash->{FD}, 1) = 1;
      my $nfound = select($rin, undef, undef, $to);
      if($nfound < 0) {
        next if ($! == EAGAIN() || $! == EINTR() || $! == 0);
        die("Select error $nfound / $!\n");
      }
      return "Timeout reading answer for get $arg"
        if($nfound == 0);
      $buf = $hash->{PortObj}->input();

    }

    Log3 $hash, 4, "FHZ/RAW: " . unpack('H*',$buf);
    $mfhzdata .= $buf;
    next if(length($mfhzdata) < 2);

    my $len = ord(substr($mfhzdata,1,1)) + 2;
    if($len>20) {
      Log3 $hash, 4, "Oversized message (" . unpack('H*',$mfhzdata) .
      				"), dropping it ...";
      return undef;
    }
    return unpack('H*', $mfhzdata) if(length($mfhzdata) == $len);
  }
}

##############
# Compute CRC, add header, glue fn and messages
sub
FHZ_CompleteMsg($$)
{
  my ($fn,$msg) = @_;
  my $len = length($msg);
  my @data;
  for(my $i = 0; $i < $len; $i += 2) {
    push(@data, ord(pack('H*', substr($msg, $i, 2))));
  }
  return pack('C*', 0x81, $len/2+2, ord(pack('H*',$fn)), FHZ_Crc(@data), @data);
}


#####################################
# Check if the 1% limit is reached and trigger notifies
sub
FHZ_XmitLimitCheck($$)
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

  if(@b > 163) {          # Maximum nr of transmissions per hour (unconfirmed).

    my $me = $hash->{NAME};
    Log3 $me, 2, "FHZ TRANSMIT LIMIT EXCEEDED";
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
    Log3 $hash, 5, "FHZ device $hash->{NAME} is not active, cannot send";
    return;
  }

  ###############
  # insert value into the msghist. At the moment this only makes sense for FS20
  # devices. As the transmitted value differs from the received one, we have to
  # recompute.
  if($fn eq "04" && substr($msg,0,6) eq "010101") {
    AddDuplicate($hash->{NAME},
                "0101a001" . substr($msg, 6, 6) . "00" . substr($msg, 12));
  }


  my $bstring = FHZ_CompleteMsg($fn, $msg);
  Log3 $hash, 5, "Sending " . unpack('H*', $bstring);

  if(!$hash->{QUEUE}) {

    FHZ_XmitLimitCheck($hash,$bstring);
    $hash->{QUEUE} = [ $bstring ];
    $hash->{PortObj}->write($bstring) if($hash->{PortObj});

    ##############
    # Write the next buffer not earlier than 0.22 seconds (= 65.6ms + 10ms +
    # 65.6ms + 10ms + 65.6ms), else it will be discarded by the FHZ1X00 PC
    InternalTimer(gettimeofday()+0.25, "FHZ_HandleWriteQueue", $hash, 1);

  } else {
    push(@{$hash->{QUEUE}}, $bstring);
  }


}

#####################################
sub
FHZ_HandleWriteQueue($)
{
  my $hash = shift;
  my $arr = $hash->{QUEUE};

  if(defined($arr) && @{$arr} > 0) {
    shift(@{$arr});
    if(@{$arr} == 0) {
      delete($hash->{QUEUE});
      return;
    }
    my $bstring = $arr->[0];
    FHZ_XmitLimitCheck($hash,$bstring);
    $hash->{PortObj}->write($bstring) if($hash->{PortObj});
    InternalTimer(gettimeofday()+0.25, "FHZ_HandleWriteQueue", $hash, 1);
  }
}

#####################################
sub
FHZ_Reopen($)
{
  my ($hash) = @_;

  my $dev = $hash->{DeviceName};
  $hash->{PortObj}->close();
  Log3 $hash, 1, "USB device $dev closed";
  for(;;) {
      sleep(5);
      if($^O =~ m/Win/) {
        $hash->{PortObj} = new Win32::SerialPort($dev);
      }else{
        $hash->{PortObj} = new Device::SerialPort($dev);
      }
      if($hash->{PortObj}) {
        Log3 $hash, 1, "USB device $dev reopened";
        $hash->{FD} = $hash->{PortObj}->FILENO if($^O !~ m/Win/);
        FHZ_DoInit($hash->{NAME}, $hash->{ttytype}, $hash->{PortObj});
        return;
      }
  }
}

#####################################
sub
FHZ_Close($)
{
  my ($hash) = @_;

  my $dev = $hash->{DeviceName};
  return if(!$dev);
  my $name = $hash->{NAME};

  $hash->{PortObj}->close();
  Log3 $name, 1, "USB device $dev closed";
  delete($hash->{PortObj});
  delete($hash->{FD});
  delete($selectlist{"$name.$dev"});
  #$readyfnlist{"$name.$dev"} = $hash; # Start polling
  $hash->{STATE} = "disconnected";


  # Without the following sleep the open of the device causes a SIGSEGV,
  # and following opens block infinitely. Only a reboot helps.
  sleep(5);

  DoTrigger($name, "DISCONNECTED");

}

#####################################
sub
FHZ_Open($)
{
  my ($hash) = @_;

  my $dev = $hash->{DeviceName};
  return if(!$dev);
  my $name = $hash->{NAME};

  $readyfnlist{"$name.$dev"} = $hash; # Start polling
  $hash->{STATE} = "disconnected";


  # Without the following sleep the open of the device causes a SIGSEGV,
  # and following opens block infinitely. Only a reboot helps.
  sleep(5);

  DoTrigger($name, "DISCONNECTED");

}

#####################################
sub
FHZ_Read($)
{
  my ($hash) = @_;

  my $buf = $hash->{PortObj}->input();
  my $iohash = $modules{$hash->{TYPE}}; # Our (FHZ) module pointer
  my $name = $hash->{NAME};

  ###########
  # Lets' try again: Some drivers return len(0) on the first read...
  if(defined($buf) && length($buf) == 0) {
    $buf = $hash->{PortObj}->input();
  }

  if(!defined($buf) || length($buf) == 0) {

    my $dev = $hash->{DeviceName};
    Log3 $name, 1, "USB device $dev disconnected, waiting to reappear";
    delete($hash->{FD});
    $hash->{PortObj}->close();
    delete($hash->{PortObj});
    delete($hash->{FD});
    delete($selectlist{"$name.$dev"});
    $readyfnlist{"$name.$dev"} = $hash; # Start polling
    $hash->{STATE} = "disconnected";

    # Without the following sleep the open of the device causes a SIGSEGV,
    # and following opens block infinitely. Only a reboot helps.
    sleep(5);

    DoTrigger($name, "DISCONNECTED");
  }


  my $fhzdata = $hash->{PARTIAL};
  Log3 $name, 4, "FHZ/RAW: " . unpack('H*',$buf) .
      " (Unparsed: " . unpack('H*', $fhzdata) . ")";
  $fhzdata .= $buf;

  while(length($fhzdata) > 2) {

    ###################################
    # Skip trash.
    my $si = index($fhzdata, $msgstart);
    if($si) {
      if($si == -1) {
	Log3 $name, 5, "Bogus message received, no start character found";
	$fhzdata = "";
	last;
      } else {
	Log3 $name, 5, "Bogus message received, skipping to start character";
	$fhzdata = substr($fhzdata, $si);
      }
    }

    my $len = ord(substr($fhzdata,1,1)) + 2;
    if($len>20) {
      Log3 $name, 4,
	 "Oversized message (" . unpack('H*',$fhzdata) . "), dropping it ...";
      $fhzdata = "";
      next;
    }

    last if(length($fhzdata) < $len);

    my $dmsg = unpack('H*', substr($fhzdata, 0, $len));
    if(FHZ_CheckCrc($dmsg)) {

      if(substr($fhzdata,2,1) eq $msgstart) { # Skip function 0x81
	$fhzdata = substr($fhzdata, 2);
	next;
      }

      $hash->{"${name}_MSGCNT"}++;
      $hash->{"${name}_TIME"} = TimeNow();
      $hash->{RAWMSG} = $dmsg;
      my %addvals = (RAWMSG => $dmsg);
      my $foundp = Dispatch($hash, $dmsg, \%addvals);

      $fhzdata = substr($fhzdata, $len);

    } else {

      Log3 $name, 4, "Bad CRC message, skipping it (Bogus message follows)";
      $fhzdata = substr($fhzdata, 2);

    }
  }
  $hash->{PARTIAL} = $fhzdata;
}

1;

=pod
=begin html

<a name="FHZ"></a>
<h3>FHZ</h3>
<ul>
  Note: this module requires the Device::SerialPort or Win32::SerialPort module
  if the devices is connected via USB or a serial port.
  <br><br>

  <a name="FHZdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FHZ &lt;serial-device&gt;</code> <br>
    <br>
    Specifies the serial port to communicate with the FHZ1000PC or FHZ1300PC.
    The name(s) of the serial-device(s) depends on your distribution. <br>

    If the serial-device is called none, then no device will be opened, so you
    can experiment without hardware attached.<br>

    The program can service multiple devices, FS20 and FHT device commands will
    be sent out through the last FHZ device defined before the definition of
    the FS20/FHT device. To change the association, use the IODev attribute.<br>
    <br>

    For GNU/Linux you may want to read our <a href="linux.html">hints for
    GNU/Linux</a> about <a href="linux.html#multipledevices">multiple USB
    devices</a>.<br>

    <b>Note:</b>The firmware of the FHZ1x00 will drop commands if the airtime
    for the last hour would exceed 1% (which corresponds roughly to 163
    commands). For this purpose there is a command counter for the last hour
    (see list FHZDEVICE), which triggers with "TRANSMIT LIMIT EXCEEDED" if
    there were more than 163 commands in the last hour.<br><br>

    If you experience problems (for verbose 4 you get a lot of "Bad CRC
    message" in the log), then try to define your device as <br> <code>define
    &lt;name&gt; FHZ &lt;serial-device&gt; strangetty</code><br>
  </ul>
  <br>

  <a name="FHZset"></a>
  <b>Set </b>
  <ul>
    <code>set FHZ &lt;variable&gt; [&lt;value&gt;]</code>
    <br><br>
    where <code>value</code> is one of:<br>
    <ul>
      FHTcode<br>
      initFS20<br>
      initHMS<br>
      stopHMS<br>
      initfull<br>
      raw<br>
      open<br>
      reopen<br>
      close<br>
      time<br>
    </ul>
    Notes:
    <ul>
      <li>raw is used to send out "raw" FS20/FHT messages (&quot;setters&quot; only - no query messages!).
          See message byte streams in FHEM/00_FHZ.pm and the doc directory for some examples.</li>
      <li>In order to set the time of your FHT's, schedule this command every
      minute:<br>
      <code>define fhz_timer at +*00:01:00 set FHZ time</code><br>
      See the <a href="#verbose">verbose</a> to prevent logging of
          this command.
      </li>
      <li>FHTcode is a two digit hex number (from 00 to 63?) and sets the
          central FHT code, which is used by the FHT devices. After changing
          it, you <b>must</b> reprogram each FHT80b with: PROG (until Sond
          appears), then select CEnt, Prog, Select nA.</li>
      <li>If the FHT ceases to work for FHT devices whereas other devices
          (e.g. HMS, KS300) continue to work, a<ul>
          <code>set FHZ initfull</code></ul> command could help. Try<ul>
          <code>set FHZ reopen</code></ul> if the FHZ
          ceases to work completely. If all else fails, shutdown fhem, unplug
          and replug the FHZ device. Problems with FHZ may also be related to
          long USB cables or insufficient power on the USB - use a powered hub
          to improve this particular part of such issues.
          See <a href="http://www.fhem.de/USB.html">our USB page</a>
          for detailed USB / electromag. interference troubleshooting.</li>
      <li><code>initfull</code> issues the initialization sequence for the FHZ
          device:<br>
          <ul><code>
            get FHZ init2<br>
            get FHZ serial<br>
            set FHZ initHMS<br>
            set FHZ initFS20<br>
            set FHZ time<br>
            set FHZ raw 04 01010100010000<br>
          </code></ul></li>
      <li><code>reopen</code> closes and reopens the serial device port. This
          implicitly initializes the FHZ and issues the
          <code>initfull</code> command sequence.</li>
      <li><code>stopHMS</code> probably is the inverse of <code>initHMS</code>
          (I don't have authoritative info on what exactly it does).</li>
      <li><code>close</code> closes and frees the serial device port until you open
          it again with <code>open</code>, e.g. useful if you need to temporarily
          unload the ftdi_sio kernel module to use the <a href="http://www.ftdichip.com/Support/Documents/AppNotes/AN232B-01_BitBang.pdf" target="_blank">bit-bang mode</a>.</li>

    </ul>
  </ul>
  <br>

  <a name="FHZget"></a>
  <b>Get</b>
  <ul>
    <code>get FHZ &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is one of:<br>
    <ul>
      init1<br>
      init2<br>
      init3<br>
      serial<br>
      fhtbuf<br>
    </ul>
    Notes:
    <ul>
      <li>The mentioned codes are needed for initializing the FHZ1X00</li>
      <li>The answer for a command is also displayed by <code>list FHZ</code>
      </li>
      <li>
          The FHZ1x00PC has a message buffer for the FHT (see the FHT entry in
          the <a href="#set">set</a> section). If the buffer is full, then newly
          issued commands will be dropped, if the attribute <a
          href="#fhtsoftbuffer">fhtsoftbuffer</a> is not set.
          <code>fhtbuf</code> returns the free memory in this buffer (in hex),
          an empty buffer in the FHZ1000 is 2c (42 bytes), in the FHZ1300 is 4a
          (74 bytes). A message occupies 3 + 2x(number of FHT commands) bytes,
          this is the second reason why sending multiple FHT commands with one
          <a href="#set"> set</a> is a good idea. The first reason is, that
          these FHT commands are sent at once to the FHT.
          </li>
    </ul>
  </ul>
  <br>

  <a name="FHZattr"></a>
  <b>Attributes</b>
  <ul>
    <a name="do_not_notify"></a>
    <li>do_not_notify<br>
    Disable FileLog/notify/inform notification for a device. This affects
    the received signal, the set and trigger commands.</li><br>

    <li><a href="#attrdummy">dummy</a></li><br>

    <li><a href="#showtime">showtime</a></li><br>

    <a name="loglevel"></a>
    <li>loglevel<br>
    <b>Note:</b>Deprecated! The module maintainer is encouraged to replace it
    with verbose.<br><br>

    Set the device loglevel to e.g. 6 if you do not wish messages from a
    given device to appear in the global logfile (FHZ/FS20/FHT).  E.g. to
    set the FHT time, you should schedule "set FHZ time" every minute, but
    this in turn makes your logfile unreadable.  These messages will not be
    generated if the FHZ attribute loglevel is set to 6.<br>
    On the other hand, if you have to debug a given device, setting its
    loglevel to a smaller value than the value of the global verbose attribute,
    it will output its messages normally seen only with higher global verbose
    levels.
    </li> <br>

    <li><a href="#model">model</a> (fhz1000,fhz1300)</li><br>

    <a name="fhtsoftbuffer"></a>
    <li>fhtsoftbuffer<br>
        As the FHZ command buffer for FHT devices is limited (see fhtbuf),
        and commands are only sent to the FHT device every 120 seconds,
        the hardware buffer may overflow and FHT commands get lost.
        Setting this attribute implements an "unlimited" software buffer.<br>
        Default is disabled (i.e. not set or set to 0).</li><br>
  </ul>
  <br>
</ul>



=end html
=cut
