##############################################

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);


sub CUL_Write($$$);
sub CUL_Read($);
sub CUL_ReadAnswer($$);
sub CUL_Ready($);
sub CUL_HandleCurRequest($$);

my $initstr = "X21";    # Only translated messages + RSSI
my %gets = (
  "version"  => "V",
  "raw"      => "",
  "ccconf"   => "=",
  "uptime"   => "t",
);

my %sets = (
  "raw"       => "",
  "freq"      => "",
  "bWidth"    => "",
  "rAmpl"     => "",
  "sens"      => "",
  "verbose"   => "X",
  "led"       => "l",
  "patable"   => "x",
);

my @ampllist = (24, 27, 30, 33, 36, 38, 40, 42);

sub
CUL_Initialize($)
{
  my ($hash) = @_;

# Provider
  $hash->{ReadFn}  = "CUL_Read";
  $hash->{WriteFn} = "CUL_Write";
  $hash->{Clients} = ":FS20:FHT:KS300:CUL_EM:CUL_WS:";
  $hash->{ReadyFn} = "CUL_Ready";

# Normal devices
  $hash->{DefFn}   = "CUL_Define";
  $hash->{UndefFn} = "CUL_Undef";
  $hash->{GetFn}   = "CUL_Get";
  $hash->{SetFn}   = "CUL_Set";
  $hash->{StateFn} = "CUL_SetState";
  $hash->{AttrList}= "do_not_notify:1,0 dummy:1,0 filtertimeout repeater:1,0 " .
                     "showtime:1,0 model:CUL,CUR loglevel:0,1,2,3,4,5,6 " . 
                     "CUR_id_list";
}

#####################################
sub
CUL_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $po;

  return "wrong syntax: define <name> CUL devicename [mobile]"
    if(@a < 3 || @a > 4);

  delete $hash->{PortObj};
  delete $hash->{FD};

  my $name = $a[0];
  my $dev = $a[2];
  $hash->{MOBILE} = 1 if($a[3] && $a[3] eq "mobile");
  $hash->{STATE} = "defined";

  $attr{$name}{savefirst} = 1;
  $attr{$name}{repeater} = 1;

  if($dev eq "none") {
    Log 1, "CUL device is none, commands will be echoed only";
    $attr{$name}{dummy} = 1;
    return undef;
  }
  
  $hash->{DeviceName} = $dev;
  $hash->{PARTIAL} = "";
  Log 3, "CUL opening CUL device $dev";
  if ($^O=~/Win/) {
   require Win32::SerialPort;
   $po = new Win32::SerialPort ($dev);
  } else  {
   require Device::SerialPort;
   $po = new Device::SerialPort ($dev);
  }
  if(!$po) {
    my $msg = "Can't open $dev: $!";
    Log(3, $msg) if($hash->{MOBILE});
    return $msg if(!$hash->{MOBILE});
    $readyfnlist{"$name.$dev"} = $hash;
    return "";
  }
  Log 3, "CUL opened CUL device $dev";

  $hash->{PortObj} = $po;
  if( $^O !~ /Win/ ) {
    $hash->{FD} = $po->FILENO;
    $selectlist{"$name.$dev"} = $hash;
  } else {
    $readyfnlist{"$name.$dev"} = $hash;
  }
  
  my $ret  = CUL_DoInit($hash);
  if($ret) {
    delete($selectlist{"$name.$dev"});
    delete($readyfnlist{"$name.$dev"});
  }
  return $ret;
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
        my $lev = ($reread_active ? 4 : 2);
        Log GetLogLevel($name,$lev), "deleting port for $d";
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
    my $msg = "Setting FREQ2..0 (0D,0E,0F) to $f2 $f1 $f0 = $arg MHz";
    Log GetLogLevel($name,4), $msg;
    CUL_SimpleWrite($hash, "W0F$f2");
    CUL_SimpleWrite($hash, "W10$f1");
    CUL_SimpleWrite($hash, "W11$f0");
    CUL_SimpleWrite($hash, $initstr);           # Will reprogram the CC1101
    return $msg;

  } elsif($type eq "bWidth") {               # KHz

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
    my $msg = "Setting MDMCFG4 (10) to $ob = $bw KHz";

    Log GetLogLevel($name,4), $msg;
    CUL_SimpleWrite($hash, "W12$ob");
    CUL_SimpleWrite($hash, $initstr);
    return $msg;

  } elsif($type eq "rAmpl") {               # dB

    return "a numerical value between 24 and 42 is expected"
        if($arg !~ m/^\d+$/ || $arg < 24 || $arg > 42);
    my ($v, $w);
    for($v = 0; $v < @ampllist; $v++) {
      last if($ampllist[$v] > $arg);
    }
    $v = sprintf("%02d", $v-1);
    $w = $ampllist[$v];
    my $msg = "Setting AGCCTRL2 (1B) to $v / $w dB";
    CUL_SimpleWrite($hash, "W1D$v");
    CUL_SimpleWrite($hash, $initstr);
    return $msg;

  } elsif($type eq "sens") {               # dB

    return "a numerical value between 4 and 16 is expected"
        if($arg !~ m/^\d+$/ || $arg < 4 || $arg > 16);
    my $w = int($arg/4)*4;
    my $v = sprintf("9%d",$arg/4-1);
    my $msg = "Setting AGCCTRL0 (1D) to $v / $w dB";
    CUL_SimpleWrite($hash, "W1F$v");
    CUL_SimpleWrite($hash, $initstr);
    return $msg;


  } else { 

    return "Expecting a 0-padded hex number"
        if((length($arg)&1) == 0 && $type ne "raw");
    $initstr = "X$arg" if($type eq "verbose");
    Log GetLogLevel($name,4), "set $name $type $arg";
    CUL_SimpleWrite($hash, $sets{$type} . $arg);

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

    my %r = ( "0D"=>1,"0E"=>1,"0F"=>1,"10"=>1,"1B"=>1,"1D"=>1 );
    foreach my $a (sort keys %r) {
      CUL_SimpleWrite($hash, "C$a");
      my @answ = split(" ", CUL_ReadAnswer($hash, "C$a"));
      $r{$a} = $answ[4];
    }
    $msg = sprintf("freq:%.3fMHz bWidth:%dKHz rAmpl:%ddB sens:%ddB",
        26*(($r{"0D"}*256+$r{"0E"})*256+$r{"0F"})/65536,                #Freq
        26000/(8 * (4+(($r{"10"}>>4)&3)) * (1 << (($r{"10"}>>6)&3))),   #Bw
        $ampllist[$r{"1B"}],
        4+4*($r{"1D"}&3)                                                #Sens
        );
    
  } else {

    CUL_SimpleWrite($hash, $gets{$a[1]} . $arg) if(!IsDummy($hash->{NAME}));
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

  my ($ver, $try) = ("", 0);
  while($try++ < 3 && $ver !~ m/^V/) {
    $hash->{PortObj}->write("V\n");
    $ver = CUL_ReadAnswer($hash, "Version");
  }

  if($ver !~ m/^V/) {
    $attr{$name}{dummy} = 1;
    $hash->{PortObj}->close();
    my $msg = "Not an CUL device, receives for V:  $ver";
    Log 1, $msg;
    return $msg;
  }

  CUL_SimpleWrite($hash, $initstr);
  $hash->{STATE} = "Initialized";

  # Reset the counter
  delete($hash->{XMIT_TIME});
  delete($hash->{NR_CMD_LAST_H});
  return undef;
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
      $nfound=CUL_Ready($hash);
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

  Log 5, "CUL sending $fn$msg";
  my $bstring = "$fn$msg\n";

  if($fn eq "F") {

    if(!$hash->{QUEUE}) {

      CUL_XmitLimitCheck($hash,$bstring);
      $hash->{QUEUE} = [ $bstring ];
      $hash->{PortObj}->write($bstring);

      ##############
      # Write the next buffer not earlier than 0.22 seconds (= 65.6ms + 10ms +
      # 65.6ms + 10ms + 65.6ms), else it will be discarded by the FHZ1X00 PC
      InternalTimer(gettimeofday()+0.25, "CUL_HandleWriteQueue", $hash, 1);

    } else {
      push(@{$hash->{QUEUE}}, $bstring);
    }

  } else {

    $hash->{PortObj}->write($bstring);

  }

}

#####################################
sub
CUL_HandleWriteQueue($)
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
  my $name = $hash->{NAME};

  ###########
  # Lets' try again: Some drivers return len(0) on the first read...
  if(defined($buf) && length($buf) == 0) {
    $buf = $hash->{PortObj}->input();
  }

  if(!defined($buf) || length($buf) == 0) {

    my $dev = $hash->{DeviceName};
    Log 1, "USB device $dev disconnected, waiting to reappear";
    $hash->{PortObj}->close();
    DoTrigger($name, "DISCONNECTED");

    delete($hash->{PortObj});
    delete($selectlist{"$name.$dev"});
    $readyfnlist{"$name.$dev"} = $hash; # Start polling
    $hash->{STATE} = "disconnected";

    # Without the following sleep the open of the device causes a SIGSEGV,
    # and following opens block infinitely. Only a reboot helps.
    sleep(5);

    return "";
  }

  my $culdata = $hash->{PARTIAL};
  Log 5, "CUL/RAW: $culdata/$buf";
  $culdata .= $buf;

  while($culdata =~ m/\n/) {

    my $dmsg;
    ($dmsg,$culdata) = split("\n", $culdata);
    $dmsg =~ s/\r//;
    goto NEXTMSG if($dmsg eq "");

    # Debug message, X05
    if($dmsg =~ m/p /) {
      foreach my $m (split("p ", $dmsg)) {
        Log GetLogLevel($name,4), "CUL: p $m";
      }
      goto NEXTMSG;
    }

    my $rssi;
    if($initstr =~ m/X2/ && $dmsg =~ m/[FEHTK]([A-F0-9][A-F0-9])+$/) { # RSSI
      my $l = length($dmsg);
      $rssi = hex(substr($dmsg, $l-2, 2));
      $dmsg = substr($dmsg, 0, $l-2);
      $rssi = ($rssi>=128 ? (($rssi-256)/2-74) : ($rssi/2-74));
      Log GetLogLevel($name,4), "$name: $dmsg $rssi";
    } else {
      Log GetLogLevel($name,4), "$name: $dmsg";
    }

    ###########################################
    #Translate Message from CUL to FHZ
    next if(!$dmsg || length($dmsg) < 1);            # Bogus messages
    my $fn = substr($dmsg,0,1);
    my $len = length($dmsg);

    if($fn eq "F") {                                 # Reformat for 10_FS20.pm

      if(defined($attr{$name}) && defined($attr{$name}{CUR_id_list})) {
        my $id= substr($dmsg,1,4);
        if($attr{$name}{CUR_id_list} =~ m/$id/) {    # CUR Request
          CUL_HandleCurRequest($hash,$dmsg);
          goto NEXTMSG;
        }
      }

      $dmsg = sprintf("81%02x04xx0101a001%s00%s",
                        $len/2+5, substr($dmsg,1,6), substr($dmsg,7));
      $dmsg = lc($dmsg);

    } elsif($fn eq "T") {                            # Reformat for 11_FHT.pm

      $dmsg = sprintf("81%02x04xx0909a001%s00%s",
                        $len/2+5, substr($dmsg,1,6), substr($dmsg,7));
      $dmsg = lc($dmsg);

    } elsif($fn eq "K") {

      if($len == 15) {                               # Reformat for 13_KS300.pm
        my @a = split("", $dmsg);
        $dmsg = sprintf("81%02x04xx4027a001", $len/2+6);
        for(my $i = 1; $i < 14; $i+=2) { # Swap nibbles.
          $dmsg .= $a[$i+1] . $a[$i];
        }
      }
      # Other K... Messages ar sent to CUL_WS

    } elsif($fn eq "E") {                            # CUL_EM / Native
      ;
    } else {
      #Log GetLogLevel($name,4), "CUL: unknown message $dmsg";
      goto NEXTMSG;
    }

    $hash->{RSSI} = $rssi;
    my @found = Dispatch($hash, $dmsg);
    if($rssi) {
      foreach my $d (@found) {
        next if(!$defs{$d});
        $defs{$d}{RSSI} = $rssi;
      }
    }

NEXTMSG:
  }
  $hash->{PARTIAL} = $culdata;
}

#####################################
sub
CUL_Ready($)           # Windows - only
{
  my ($hash) = @_;
  my $po=$hash->{PortObj};

  if(!$po) {    # Looking for the device

    my $dev = $hash->{DeviceName};
    my $name = $hash->{NAME};

    $hash->{PARTIAL} = "";
    if ($^O=~/Win/) {
     $po = new Win32::SerialPort ($dev);
    } else  {
     $po = new Device::SerialPort ($dev);
    }
    return undef if(!$po);

    Log 1, "USB device $dev reappeared";
    $hash->{PortObj} = $po;
    if( $^O !~ /Win/ ) {
      $hash->{FD} = $po->FILENO;
      delete($readyfnlist{"$name.$dev"});
      $selectlist{"$name.$dev"} = $hash;
    } else {
      $readyfnlist{"$name.$dev"} = $hash;
    }
    my $ret  = CUL_DoInit($hash);
    if($ret) {
      delete($selectlist{"$name.$dev"});
      delete($readyfnlist{"$name.$dev"});
      Log 1, "Won't listen to this device any more";
    }
    DoTrigger($name, "CONNECTED");
    return $ret;

  }

  # This is relevant for windows only
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags)=$po->status;
  return ($InBytes>0);
}

sub
CUL_SendCurMsg($$$)
{
  my ($hash,$id,$msg) = @_;

  $msg = substr($msg, 0, 12) if(length($msg) > 12);
  my $rmsg = "F" . $id .  unpack('H*', $msg);
  Log 1, "CUL_SendCurMsg: $id:$msg / $rmsg";
  sleep(1);                # Poor mans CSMA/CD
  CUL_SimpleWrite($hash, $rmsg);
}

sub
CUL_HandleCurRequest($$)
{
  my ($hash,$msg) = @_;


  Log 1, "CUR Request: $msg";
  my $l = length($msg);
  return if($l < 9);

  my $id = substr($msg,1,4);
  my $cm = substr($msg,5,2);
  my $a1 = substr($msg,7,2);
  my $a2 = pack('H*', substr($msg,9)) if($l > 9);

  if($cm eq "00") {     # Get status
    $msg = defined($defs{$a2}) ? $defs{$a2}{STATE} : "Undefined $a2";
    $msg =~ s/: /:/g;
    $msg =~ s/  / /g;
    $msg =~ s/.*[a-z]-//g;      # FHT desired-temp, but keep T:-1
    $msg =~ s/\(.*//g;          # FHT (Celsius) 
    $msg =~ s/.*5MIN:/5MIN:/g;  # EM
    $msg =~ s/\.$//;
    $msg =~ s/ *//;            # One letter seldom makes sense
    CUL_SendCurMsg($hash,$id, "d" . $msg);  # Display the message on the CUR
  }

  if($cm eq "01") {     # Send time
    my @a = localtime;
    $msg = sprintf("c%02d%02d%02d", $a[2],$a[1],$a[0]);
    CUL_SendCurMsg($hash,$id, $msg);
  }

  if($cm eq "02") {     # FHT desired temp
    $msg = sprintf("set %s desired-temp %.1f", $a2, $a1/2);
    fhem( $msg );
  }

}

1;
