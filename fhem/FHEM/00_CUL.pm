##############################################
# Implemented:
# - Transmit limit trigger: Fire if more then 1% airtime 
#   is used in the last hour
# - reconnect
# - message flow control (send one F message every 0.25 seconds)
# - repeater/filtertimeout
# - FS20 rcv
# - FS20 xmit
# - FHT rcv

# TODO:
# - FHT xmit
# - HMS rcv
# - KS300 rcv
# - EMEM rcv
# - EMWZ rcv
# - EMGZ rcv
# - S300TH rcv


package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);


sub CUL_Write($$$);
sub CUL_Read($);
sub CUL_ReadAnswer($$);
sub CUL_Ready($$);

my $initstr = "X01";    # Only translated messages, no RSSI
my %msghist;		# Used when more than one CUL is attached
my $msgcount = 0;
my %gets = (
  "ccreg"    => "C",
  "eeprom"   => "R",
  "version"  => "V",
  "time"     => "t",
  "raw"      => "",
  "ccconf"   => "=",
);

my %sets = (
  "eeprom"    => "W",
  "raw"       => "",
  "verbose"   => "X",
  "freq"      => "=",
  "bandwidth" => "=",
);

sub
CUL_Initialize($)
{
  my ($hash) = @_;

# Provider
  $hash->{ReadFn}  = "CUL_Read";
  $hash->{WriteFn} = "CUL_Write";
  $hash->{Clients} = ":FS20:FHT:KS300:CUL_EM:CUL_WS:";
  $hash->{ReadyFn} = "CUL_Ready" if ($^O eq 'MSWin32');

# Normal devices
  $hash->{DefFn}   = "CUL_Define";
  $hash->{UndefFn} = "CUL_Undef";
  $hash->{GetFn}   = "CUL_Get";
  $hash->{SetFn}   = "CUL_Set";
  $hash->{StateFn} = "CUL_SetState";
  $hash->{AttrList}= "do_not_notify:1,0 dummy:1,0 filtertimeout repeater:1,0 " .
                   "showtime:1,0 model:CUL loglevel:0,1,2,3,4,5,6";
}

#####################################
sub
CUL_Define($$)
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
  $attr{$name}{repeater} = 1;

  if($dev eq "none") {
    Log 1, "CUL device is none, commands will be echoed only";
    $attr{$name}{dummy} = 1;
    return undef;
  }
  
  Log 3, "CUL opening CUL device $dev";
  if ($^O=~/Win/) {
   require Win32::SerialPort;
   $po = new Win32::SerialPort ($dev);
  } else  {
   require Device::SerialPort;
   $po = new Device::SerialPort ($dev);
  }
  return "Can't open $dev: $!\n" if(!$po);
  Log 3, "CUL opened CUL device $dev";

  $hash->{PortObj} = $po;
  if( $^O !~ /Win/ ) {
    $hash->{FD} = $po->FILENO;
    $selectlist{"$name.$dev"} = $hash;
  } else {
    $readyfnlist{"$name.$dev"} = $hash;
  }
  
  $hash->{DeviceName} = $dev;
  $hash->{PARTIAL} = "";
  return CUL_DoInit($hash);
}

#####################################
sub
CUL_Undef($$)
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
CUL_Set($@)
{
  my ($hash, @a) = @_;

  return "\"set CUL\" needs at least one parameter" if(@a < 2);
  return "Unknown argument $a[1], choose one of " . join(" ", sort keys %sets)
  	if(!defined($sets{$a[1]}));

  my $name = shift @a;
  my $type = shift @a;
  my $arg = join("", @a);

  if($type eq "freq") {                         # MHz

    my $f = $arg/26*65536;

    my $f2 = sprintf("%02x", $f / 65536);
    my $f1 = sprintf("%02x", int($f % 65536) / 256);
    my $f0 = sprintf("%02x", $f % 256);
    $arg = sprintf("%.3f", (hex($f2)*65536+hex($f1)*256+hex($f0))/65536*26);
    my $msg = "Setting FREQ2..0 (0D,0E,0F) to $f2 $f1 $f0 = $arg MHz, ".
                "verbose to $initstr";
    Log GetLogLevel($name,4), $msg;
    CUL_SimpleWrite($hash, "W0D$f2");            # Will reprogram the CC1101
    CUL_SimpleWrite($hash, "W0E$f1");
    CUL_SimpleWrite($hash, "W0F$f0");
    CUL_SimpleWrite($hash, $initstr);
    return $msg;

  } elsif($type eq "bandwidth") {               # KHz

    my $ob = 5;
    if(!IsDummy($hash->{NAME})) {
      CUL_SimpleWrite($hash, "C10");
      $ob = CUL_ReadAnswer($hash, $type);
      return "Can't get old MDMCFG4 value" if($ob !~ m,/ (.*)\r,);
      $ob = $1 & 0x0f;
    }

    my ($bits, $bw) = (0,0);
    for (my $e = 0; $e < 4; $e++) {
      for (my $m = 0; $m < 4; $m++) {
        $bits = ($e<<6)+($m<<4);
        $bw  = int(26000/(8 * (4+$m) * (1 << $e))); # KHz
        goto GOTBW if($arg >= $bw);
      }
    }
GOTBW:
    $ob = sprintf("%02x", $ob+$bits);
    my $msg = "Setting MDMCFG4 (10) to $ob = $bw KHz, verbose to $initstr";

    Log GetLogLevel($name,4), $msg;
    CUL_SimpleWrite($hash, "W10$ob");
    CUL_SimpleWrite($hash, $initstr);
    return $msg;

  } else {

    return "Expecting a 0-padded hex number"
        if((length($arg)&1) == 1 && $type ne "raw");
    $initstr = "X$arg" if($type eq "verbose");
    Log GetLogLevel($name,4), "set $name $type $arg";
    CUL_Write($hash, $sets{$type}, $arg);

  }
  return undef;
}

#####################################
sub
CUL_Get($@)
{
  my ($hash, @a) = @_;

  return "\"get CUL\" needs at least one parameter" if(@a < 2);
  return "Unknown argument $a[1], choose one of " . join(" ", sort keys %gets)
  	if(!defined($gets{$a[1]}));

  my $arg = ($a[2] ? $a[2] : "");
  my $msg = "";

  return "No $a[1] for dummies" if(IsDummy($hash->{NAME}));

  if($a[1] eq "ccconf") {

    my %r = ( "0D"=>1,"0E"=>1,"0F"=>1,"10"=>1,"1B"=>1,"1D"=>1,
              "23"=>1,"24"=>1,"25"=>1,"26"=>1,"34"=>1) ;
    foreach my $a (sort keys %r) {
      CUL_SimpleWrite($hash, "C$a");
      my @answ = split(" ", CUL_ReadAnswer($hash, "C$a"));
      $r{$a} = $answ[4];
    }
    $msg = sprintf("Freq:%.3fMHz Bwidth:%dKHz Ampl:%ddB " .
                   "Sens:%ddB FSCAL:%02X%02X%02X%02X RSSI: %ddB", 
        26*(($r{"0D"}*256+$r{"0E"})*256+$r{"0F"})/65536,                #Freq
        26000/(8 * (4+(($r{"10"}>>4)&3)) * (1 << (($r{"10"}>>6)&3))),   #Bw
        $r{"1B"}&7<4 ? 24+3*($r{"1B"}&7) : 36+2*(($r{"1B"}&7)-4),       #Ampl
        4+4*($r{"1D"}&3),                                               #Sens
        $r{"23"}, $r{"24"}, $r{"25"}, $r{"26"},                         #FSCAL
        $r{"34"}>=128 ? (($r{34}-256)/2-74) : ($r{34}/2-74)             #RSSI

        );
    
  } else {

    CUL_Write($hash, $gets{$a[1]}, $arg) if(!IsDummy($hash->{NAME}));
    $msg = CUL_ReadAnswer($hash, $a[1]);
    $msg = "No answer" if(!defined($msg));
    $msg =~ s/[\r\n]//g;

  }

  $hash->{READINGS}{$a[1]}{VAL} = $msg;
  $hash->{READINGS}{$a[1]}{TIME} = TimeNow();

  return "$a[0] $a[1] => $msg";
}

#####################################
sub
CUL_SetState($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;
  return undef;
}

#####################################
sub
CUL_DoInit($)
{
  my $hash = shift;
  my $name = $hash->{NAME};

  # Clear the pipe
  $hash->{RA_Timeout} = 0.1;
  for(;;) {
    last if(CUL_ReadAnswer($hash, "Clear") =~ m/^Timeout/);
  }
  delete($hash->{RA_Timeout});

  $hash->{PortObj}->write("V\n");
  my $ver = CUL_ReadAnswer($hash, "Version");
  if($ver !~ m/^V/) {
    $attr{$name}{dummy} = 1;
    $hash->{PortObj}->close();
    my $msg = "Not an CUL device, receives for V:  $ver";
    Log 1, $msg;
    return $msg;
  }
  CUL_SimpleWrite($hash, $initstr);

  # Reset the counter
  delete($hash->{XMIT_TIME});
  delete($hash->{NR_CMD_LAST_H});
}

#####################################
# This is a direct read for commands like get
sub
CUL_ReadAnswer($$)
{
  my ($hash,$arg) = @_;

  return undef if(!$hash || !defined($hash->{FD}));
  my ($mculdata, $rin) = ("", '');
  my $nfound;
  for(;;) {
    if($^O eq 'MSWin32') {
      $nfound=CUL_Ready($hash, undef);
    } else {
      vec($rin, $hash->{FD}, 1) = 1;
      my $to = 3;                                         # 3 seconds timeout
      $to = $hash->{RA_Timeout} if($hash->{RA_Timeout});  # ...or less
      $nfound = select($rin, undef, undef, $to);
      if($nfound < 0) {
        next if ($! == EAGAIN() || $! == EINTR() || $! == 0);
        return "Select error $nfound / $!";
      }
    }
    return "Timeout reading answer for get $arg" if($nfound == 0);
    my $buf = $hash->{PortObj}->input();

    Log 5, "CUL/RAW: $buf";
    $mculdata .= $buf;
    return $mculdata if($mculdata =~ m/\r\n/);
  }
}

#####################################
# Check if the 1% limit is reached and trigger notifies
sub
CUL_XmitLimitCheck($$)
{
  my ($hash,$fn) = @_;
  my $now = time();

  if(!$hash->{XMIT_TIME}) {
    $hash->{XMIT_TIME}[0] = $now;
    $hash->{NR_CMD_LAST_H} = 1;
    return;
  }

  my $nowM1h = $now-3600;
  my @b = grep { $_ > $nowM1h } @{$hash->{XMIT_TIME}};

  if(@b > 163) {          # Maximum nr of transmissions per hour (unconfirmed).

    my $name = $hash->{NAME};
    Log GetLogLevel($name,2), "CUL TRANSMIT LIMIT EXCEEDED";
    DoTrigger($name, "TRANSMIT LIMIT EXCEEDED");

  } else {

    push(@b, $now);

  }
  $hash->{XMIT_TIME} = \@b;
  $hash->{NR_CMD_LAST_H} = int(@b);
}

sub
CUL_SimpleWrite($$)
{
  my ($hash, $msg) = @_;
  return if(!$hash || !defined($hash->{PortObj}));
  $hash->{PortObj}->write($msg . "\n");
}

#####################################
sub
CUL_Write($$$)
{
  my ($hash,$fn,$msg) = @_;

  if(!$hash || !defined($hash->{PortObj})) {
    Log 5, "CUL device is not active, cannot send";
    return;
  }
  my $name = $hash->{NAME};

  ###################
  # Rewrite message from FHZ -> CUL
  if(length($fn) <= 1) {                                   # CUL Native
  } elsif($fn eq "04" && substr($msg,0,6) eq "010101") {   # FS20
    $fn = "F";
    $msg = substr($msg,6);
  } else {
    Log GetLogLevel($name,2), "CUL cannot translate $fn $msg";
    return;
  }

  ###############
  # insert value into the msghist. At the moment this only makes sense for FS20
  # devices. As the transmitted value differs from the received one, we have to
  # recompute.
  if($fn eq "F" || $fn eq "T") {
    $msghist{$msgcount}{TIME} = gettimeofday();
    $msghist{$msgcount}{NAME} = $hash->{NAME};
    $msghist{$msgcount}{MSG}  = "$fn$msg";
    $msgcount++;
  }

  Log 5, "CUL sending $fn$msg";
  my $bstring = "$fn$msg\n";

  if($fn eq "F") {
    if(!$hash->{QUEUECNT}) {

      CUL_XmitLimitCheck($hash, $bstring);
      $hash->{PortObj}->write($bstring);

      ##############
      # Write the next buffer not earlier than 0.227 seconds (= 65.6ms + 10ms +
      # 65.6ms + 10ms + 65.6ms + 10ms)
      InternalTimer(gettimeofday()+0.25, "CUL_HandleWriteQueue", $hash, 1);

    } elsif($hash->{QUEUECNT} == 1) {
      $hash->{QUEUE} = [ $bstring ];
    } else {
      push(@{$hash->{QUEUE}}, $bstring);
    }
    $hash->{QUEUECNT}++;

  } else {

    $hash->{PortObj}->write($bstring);

  }

}

#####################################
sub
CUL_HandleWriteQueue($)
{
  my $hash = shift;
  my $cnt = --$hash->{QUEUECNT};
  if($cnt > 0) {
    my $bstring = shift(@{$hash->{QUEUE}});
    CUL_XmitLimitCheck($hash,$bstring);
    $hash->{PortObj}->write($bstring);
    InternalTimer(gettimeofday()+0.25, "CUL_HandleWriteQueue", $hash, 1);
  }
}

#####################################
sub
CUL_Read($)
{
  my ($hash) = @_;

  my $buf = $hash->{PortObj}->input();
  my $iohash = $modules{$hash->{TYPE}}; # Our (CUL) module pointer
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
        CUL_DoInit($hash);
	return;
      }
    }
  }

  my $culdata = $hash->{PARTIAL};
  Log 5, "CUL/RAW: $culdata/$buf";
  $culdata .= $buf;

  while($culdata =~ m/\n/) {

    my $dmsg;
    ($dmsg,$culdata) = split("\n", $culdata);
    $dmsg =~ s/\r//;

    # Debug message, X05
    if($dmsg =~ m/^p /) {
      foreach my $m (split("p ", $dmsg)) {
        Log GetLogLevel($name,4), "CUL: p $m";
      }
      goto NEXTMSG;
    }

    ###############
    # check for duplicate msg from different CUL's
    my $now = gettimeofday();
    my $skip;
    my $meetoo = ($attr{$name}{repeater} ? 1 : 0);

    my $to = 0.3;
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

    if($initstr =~ m/X2/) {                          # RSSI
      my $l = length($dmsg);
      my $rssi = hex(substr($dmsg, $l-2, 2));
      $dmsg = substr($dmsg, 0, $l-2);
      $rssi = ($rssi>=128 ? (($rssi-256)/2-74) : ($rssi/2-74));
      Log GetLogLevel($name,4), "CUL: $dmsg $rssi";
    } else {
      Log GetLogLevel($name,4), "CUL: $dmsg";
    }

    ###########################################
    #Translate Message from CUL to FHZ
    my $fn = substr($dmsg,0,1);
    my $len = length($dmsg);

    if($fn eq "F") {                                 # Reformat for 10_FS20.pm

      $dmsg = sprintf("81%02x04xx0101a001%s00%s",
                        $len/2+5, substr($dmsg,1,6), substr($dmsg,7));
      $dmsg = lc($dmsg);

    } elsif($fn eq "T") {                            # Reformat for 11_FHT.pm

      $dmsg = sprintf("81%02x04xx0909a001%s00%s",
                        $len/2+5, substr($dmsg,1,6), substr($dmsg,7));
      $dmsg = lc($dmsg);

    } elsif($fn eq "K") {

      if($len == 99) {                               # Reformat for 13_KS300.pm
        my @a = split("", $dmsg);
        $dmsg = sprintf("81%02x04xx4027a001", $len/2+6);
        for(my $i = 0; $i < 14; $i+=2) { # Swap nibbles.
          $dmsg .= $a[$i+2] . $a[$i+1];
        }
      }
      # Other K... Messages ar sent to CUL_WS

    } elsif($fn eq "E") {                            # CUL_EM / Native
      ;
    } else {
      Log GetLogLevel($name,4), "CUL: unknown message $dmsg";
      goto NEXTMSG;
    }


    my @found;
    my $last_module;
    foreach my $m (sort { $modules{$a}{ORDER} cmp $modules{$b}{ORDER} }
                    grep {defined($modules{$_}{ORDER});}keys %modules) {
      next if($iohash->{Clients} !~ m/:$m:/);

      # Module is not loaded or the message is not for this module
      next if(!$modules{$m}{Match} || $dmsg !~ m/$modules{$m}{Match}/i);

      no strict "refs";
      @found = &{$modules{$m}{ParseFn}}($hash,$dmsg);
      use strict "refs";
      $last_module = $m;
      last if(int(@found));
    }
    if(!int(@found)) {
      Log GetLogLevel($name,3), "Unknown code $dmsg, help me!";
      goto NEXTMSG;
    }

    goto NEXTMSG if($found[0] eq "");	# Special return: Do not notify

    # The trigger needs a device: we create a minimal temporary one
    if($found[0] =~ m/^(UNDEFINED) ([^ ]*) (.*)$/) {
      my $d = $1;
      $defs{$d}{NAME} = $1;
      $defs{$d}{TYPE} = $last_module;
      DoTrigger($d, "$2 $3");
      CommandDelete(undef, $d);                 # Remove the device
      goto NEXTMSG;
    }

    foreach my $found (@found) {
      DoTrigger($found, undef);
    }
NEXTMSG:
  }
  $hash->{PARTIAL} = $culdata;
}

#####################################
sub
CUL_Ready($$)           # Windows - only
{
  my ($hash, $dev) = @_;
  my $po=$hash->{PortObj};
  return undef if !$po;
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags)=$po->status;
  return ($InBytes>0);
}

1;
