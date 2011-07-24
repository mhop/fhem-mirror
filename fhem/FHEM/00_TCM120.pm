##############################################
package main;

# by r.koenig at koeniglich.de
# See also TCM_120_User_Manual_V1.53_02.pdf 

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

sub TCM120_Read($);
sub TCM120_ReadAnswer($$);
sub TCM120_Ready($);
sub TCM120_Write($$$);

sub TCM120_OpenDev($$);
sub TCM120_CloseDev($);
sub TCM120_SimpleWrite($$);
sub TCM120_SimpleRead($);
sub TCM120_Disconnected($);
sub TCM120_Parse($$$);

sub
TCM120_Initialize($)
{
  my ($hash) = @_;

# Provider
  $hash->{ReadFn}  = "TCM120_Read";
  $hash->{WriteFn} = "TCM120_Write";
  $hash->{ReadyFn} = "TCM120_Ready";
  $hash->{Clients} = ":EnOcean:";
  my %matchList= (
    "1:EnOcean"   => "^EnOcean:0B",
  );
  $hash->{MatchList} = \%matchList;

# Normal devices
  $hash->{DefFn}   = "TCM120_Define";
  $hash->{GetFn}   = "TCM120_Get";
  $hash->{SetFn}   = "TCM120_Set";
  $hash->{AttrList}= "do_not_notify:1,0 dummy:1,0 loglevel:0,1,2,3,4,5,6 ";
}

#####################################
sub
TCM120_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a != 3) {
    Log 1, "ARG:".int(@a);
    my $msg = "wrong syntax: define <name> TCM120 ".
                        "{devicename[\@baudrate]|ip:port}";
    return $msg;
  }

  TCM120_CloseDev($hash);

  my $name = $a[0];
  my $dev  = $a[2];

  if($dev eq "none") {
    Log 1, "$name device is none, commands will be echoed only";
    $attr{$name}{dummy} = 1;
    return undef;
  }
  
  $hash->{DeviceName} = $dev;
  my $ret = TCM120_OpenDev($hash, 0);
  return $ret;
}


#####################################
# Input is HEX, without header and CRC
sub
TCM120_Write($$$)
{
  my ($hash,$fn,$msg) = @_;
  my $name = $hash->{NAME};
  my $ll5 = GetLogLevel($name,5);

  return if(!defined($fn));

  Log $ll5, "$hash->{NAME} sending $fn$msg";
  my $bstring = "$fn$msg";
  $bstring = "A55A".$bstring.TCM120_CRC($bstring);

  TCM120_SimpleWrite($hash, $bstring);
}

#####################################
sub
TCM120_CRC($)
{
  my $msg = shift;
  my @data;
  for(my $i = 0; $i < length($msg); $i += 2) {
    push(@data, ord(pack('H*', substr($msg, $i, 2))));
  }
  my $sum = 0;
  map { $sum += $_; } @data;
  return sprintf("%02X", $sum & 0xFF);
}

#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub
TCM120_Read($)
{
  my ($hash) = @_;

  my $buf = TCM120_SimpleRead($hash);
  my $name = $hash->{NAME};
  my $ll5 = GetLogLevel($name,5);

  ###########
  # Lets' try again: Some drivers return len(0) on the first read...
  if(defined($buf) && length($buf) == 0) {
    $buf = TCM120_SimpleRead($hash);
  }

  if(!defined($buf) || length($buf) == 0) {
    TCM120_Disconnected($hash);
    return "";
  }

  my $data = $hash->{PARTIAL} . uc(unpack('H*', $buf));
  Log $ll5, "$name/RAW: $data";

  if($data =~ m/^A55A(.B.{20})(..)/) {
    my ($net, $crc) = ($1, $2);
    my $mycrc = TCM120_CRC($net);
    $hash->{PARTIAL} = substr($data, 28);

    if($crc ne $mycrc) {
      Log $ll5, "$name: wrong checksum: got $crc, computed $mycrc" ;
      return;
    }
    if($net =~ m/^0B/) {        # Receive Radio Telegram (RRT)
      Dispatch($hash, "EnOcean:$net", undef);
    } else {                    # Receive Message Telegram (RMT)
      TCM120_Parse($hash, $net, 0);
    }


  } else {
    if(length($data) >= 4) {
      $data =~ s/.*A55A/A55A/ if($data !~ m/^A55A/);
      $data = "" if($data !~ m/^A55A/);
    }
    $hash->{PARTIAL} = $data;

  }
}

#####################################
my %parsetbl = (
  "8B08" => { msg=>"ERR_SYNTAX_H_SEQ" },
  "8B09" => { msg=>"ERR_SYNTAX_LENGTH" },
  "8B0A" => { msg=>"ERR_SYNTAX_CHKSUM" },
  "8B0B" => { msg=>"ERR_SYNTAX_ORG" },
  "8B0C" => { msg=>"ERR_MODEM_DUP_ID" },
  "8B19" => { msg=>"ERR" },
  "8B1A" => { msg=>"ERR_IDRANGE" },
  "8B22" => { msg=>"ERR_TX_IDRANGE" },
  "8B28" => { msg=>"ERR_MODEM_NOTWANTEDACK" },
  "8B29" => { msg=>"ERR_MODEM_NOTACK" },
  "8B58" => { msg=>"OK" },
  "8B8C" => { msg=>"INF_SW_VER", expr=>'"$a[2].$a[3].$a[4].$a[5]"' },
  "8B88" => { msg=>"INF_RX_SENSIVITY", expr=>'$a[2] ? "High (01)":"Low (00)"' },
  "8B89" => { msg=>"INFO", expr=>'substr($rawstr,2,9)' },
  "8B98" => { msg=>"INF_IDBASE",
              expr=>'sprintf("%02x%02x%02x%02x", $a[2], $a[3], $a[4], $a[5])' },
  "8BA8" => { msg=>"INF_MODEM_STATUS",
              expr=>'sprintf("%s, ID:%02x%02x", $a[2]?"on":"off", $a[3], $a[4])' },
);

sub
TCM120_Parse($$$)
{
  my ($hash,$rawmsg,$ret) = @_;
  my $name = $hash->{NAME};
  my $ll5 = GetLogLevel($name,5);
  my $ll2 = GetLogLevel($name,2);

  Log $ll5, "TCMParse: $rawmsg";

  my $msg = "";
  my $cmd = $parsetbl{substr($rawmsg, 0, 4)};

  if(!$cmd) {
    $msg ="Unknown command: $rawmsg";

  } else {
    if($cmd->{expr}) {
      $msg = $cmd->{msg}." " if(!$ret);
      my $rawstr = pack('H*', $rawmsg);
      $rawstr =~ s/[\r\n]//g;
      my @a = map { ord($_) } split("", $rawstr);
      $msg .= eval $cmd->{expr};

    } else {
      return "" if($cmd ->{msg} eq "OK" && !$ret); # SKIP Ok
      $msg = $cmd->{msg};

    }

  }

  Log $ll2, "$name $msg" if(!$ret);
  return $msg;
}

#####################################
sub
TCM120_Ready($)
{
  my ($hash) = @_;

  return TCM120_OpenDev($hash, 1)
                if($hash->{STATE} eq "disconnected");

  # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  return ($InBytes>0);
}

########################
# Input is HEX, with header and CRC
sub
TCM120_SimpleWrite($$)
{
  my ($hash, $msg) = @_;
  return if(!$hash);

  $msg = pack('H*', $msg);
  $hash->{USBDev}->write($msg)    if($hash->{USBDev});
  syswrite($hash->{TCPDev}, $msg) if($hash->{TCPDev});
  select(undef, undef, undef, 0.001);
}

########################
sub
TCM120_SimpleRead($)
{
  my ($hash) = @_;
  my $buf;

  $buf = $hash->{USBDev}->input() if($hash->{USBDev});
  $buf = sysread($hash->{TCPDev}, $buf, 256) if($hash->{TCPDev});
  return $buf;
}

########################
sub
TCM120_CloseDev($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $dev = $hash->{DeviceName};

  return if(!$dev);

  if($hash->{TCPDev}) {
    $hash->{TCPDev}->close();
    delete($hash->{TCPDev});

  } elsif($hash->{USBDev}) {
    $hash->{USBDev}->close() ;
    delete($hash->{USBDev});

  }
  
  ($dev, undef) = split("@", $dev); # Remove the baudrate
  delete($selectlist{"$name.$dev"});
  delete($readyfnlist{"$name.$dev"});
  delete($hash->{FD});
}

########################
sub
TCM120_OpenDev($$)
{
  my ($hash, $reopen) = @_;
  my $dev = $hash->{DeviceName};
  my $name = $hash->{NAME};
  my $po;
  my $baudrate;
  ($dev, $baudrate) = split("@", $dev);


  $hash->{PARTIAL} = "";
  Log 3, "TCM120 opening $name device $dev"
        if(!$reopen);

  if($dev =~ m/^(.+):([0-9]+)$/) {       # host:port

    # This part is called every time the timeout (5sec) is expired _OR_
    # somebody is communicating over another TCP connection. As the connect
    # for non-existent devices has a delay of 3 sec, we are sitting all the
    # time in this connect. NEXT_OPEN tries to avoid this problem.
    if($hash->{NEXT_OPEN} && time() < $hash->{NEXT_OPEN}) {
      return;
    }

    my $conn = IO::Socket::INET->new(PeerAddr => $dev);
    if($conn) {
      delete($hash->{NEXT_OPEN})

    } else {
      Log(3, "Can't connect to $dev: $!") if(!$reopen);
      $readyfnlist{"$name.$dev"} = $hash;
      $hash->{STATE} = "disconnected";
      $hash->{NEXT_OPEN} = time()+60;
      return "";
    }

    $hash->{TCPDev} = $conn;
    $hash->{FD} = $conn->fileno();
    delete($readyfnlist{"$name.$dev"});
    $selectlist{"$name.$dev"} = $hash;

  } else {                              # USB/Serial device

    if ($^O=~/Win/) {
     require Win32::SerialPort;
     $po = new Win32::SerialPort ($dev);
    } else  {
     require Device::SerialPort;
     $po = new Device::SerialPort ($dev);
    }

    if(!$po) {
      return undef if($reopen);
      Log(3, "Can't open $dev: $!");
      $readyfnlist{"$name.$dev"} = $hash;
      $hash->{STATE} = "disconnected";
      return "";
    }
    $hash->{USBDev} = $po;
    if( $^O =~ /Win/ ) {
      $readyfnlist{"$name.$dev"} = $hash;
    } else {
      $hash->{FD} = $po->FILENO;
      delete($readyfnlist{"$name.$dev"});
      $selectlist{"$name.$dev"} = $hash;
    }

    if($baudrate) {
      $po->reset_error();
      Log 3, "TCM120 setting $name baudrate to $baudrate";
      $po->baudrate($baudrate);
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
    }

    $po->write_settings;
  }

  if($reopen) {
    Log 1, "TCM120 $dev reappeared ($name)";
  } else {
    Log 3, "TCM120 device opened";
  }

  $hash->{STATE}="connected";

  DoTrigger($name, "CONNECTED") if($reopen);
  return "";
}

sub
TCM120_Disconnected($)
{
  my $hash = shift;
  my $dev = $hash->{DeviceName};
  my $name = $hash->{NAME};
  my $baudrate;
  ($dev, $baudrate) = split("@", $dev);

  return if(!defined($hash->{FD}));                 # Already deleted or RFR

  Log 1, "$dev disconnected, waiting to reappear";
  TCM120_CloseDev($hash);
  $readyfnlist{"$name.$dev"} = $hash;               # Start polling
  $hash->{STATE} = "disconnected";

  # Without the following sleep the open of the device causes a SIGSEGV,
  # and following opens block infinitely. Only a reboot helps.
  sleep(5);

  DoTrigger($name, "DISCONNECTED");
}

my %gets = (    # Name, Data to send to the CUL, Regexp for the answer
  "sensitivity"  => "AB48",
  "idbase"       => "AB58",
  "modem_status" => "AB68",
  "sw_ver"       => "AB4B",
);

sub
TCM120_Get($@)
{
  my ($hash, @a) = @_;
  my $name = $hash->{NAME};

  return "\"get $name\" needs one parameter" if(@a != 2);
  my $cmd = $a[1];
  my $rawcmd = $gets{$cmd};
  return "Unknown argument $cmd, choose one of " . join(" ", sort keys %gets)
  	if(!defined($rawcmd));

  $rawcmd .= "000000000000000000";
  TCM120_Write($hash, "", $rawcmd);

  my ($err, $data) = TCM120_ReadAnswer($hash, "get $cmd");
  if($err) {
    Log 1, $err;
    return $err;
  }

  if($data =~ m/^A55A(.B.{20})(..)/) {
    my ($net, $crc) = ($1, $2);
    my $mycrc = TCM120_CRC($net);
    $hash->{PARTIAL} = substr($data, 28);

    if($crc ne $mycrc) {
      return "wrong checksum: got $crc, computed $mycrc" ;
    }
    my $msg = TCM120_Parse($hash, $net, 1);
    $hash->{READINGS}{$cmd}{VAL} = $msg;
    $hash->{READINGS}{$cmd}{TIME} = TimeNow();
    return $msg;

  } else {
    return "Bogus answer received";

  }

}

my %sets = (    # Name, Data to send to the CUL, Regexp for the answer
  "idbase"       => { cmd=>"AB18", arg=>"[0-9A-F]{8}" },
  "sensitivity"  => { cmd=>"AB08", arg=>"0[01]" },
  "sleep"        => { cmd=>"AB09" },
  "wake"         => { cmd=>"" }, # Special
  "reset"        => { cmd=>"AB0A" },
  "modem_on"     => { cmd=>"AB28", arg=>"[0-9A-F]{4}" },
  "modem_off"    => { cmd=>"AB2A" },
);

sub
TCM120_Set($@)
{
  my ($hash, @a) = @_;
  my $name = $hash->{NAME};

  return "\"set $name\" needs at least one parameter" if(@a < 2);
  my $cmd = $a[1];
  my $arg = $a[2];
  my $cmdhash = $sets{$cmd};
  return "Unknown argument $cmd, choose one of " . join(" ", sort keys %sets)
  	if(!defined($cmdhash));

  my $rawcmd = $cmdhash->{cmd};
  my $argre = $cmdhash->{arg};
  if($argre) {
    return "Argument needed for set $name $cmd ($argre)" if(!defined($arg));
    return "Argument does not match the regexp ($argre)" if($arg !~ m/$argre/i);
    $rawcmd .= $arg;
  }

  if($rawcmd eq "") {            # wake is very special
    TCM120_SimpleWrite($hash, "AA");
    return "";
  }

  $rawcmd .= "0"x(22-length($rawcmd));  # Padding with 0
  TCM120_Write($hash, "", $rawcmd);

  my ($err, $data) = TCM120_ReadAnswer($hash, "get $cmd");
  if($err) {
    Log 1, $err;
    return $err;
  }

  if($data =~ m/^A55A(.B.{20})(..)/) {
    my ($net, $crc) = ($1, $2);
    my $mycrc = TCM120_CRC($net);
    $hash->{PARTIAL} = substr($data, 28);

    if($crc ne $mycrc) {
      return "wrong checksum: got $crc, computed $mycrc" ;
    }
    my $msg = TCM120_Parse($hash, $net, 1);
    $hash->{READINGS}{$cmd}{VAL} = $msg;
    $hash->{READINGS}{$cmd}{TIME} = TimeNow();
    return $msg;

  } else {
    return "Bogus answer received";

  }

}


sub
TCM120_ReadAnswer($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  my $ll5 = GetLogLevel($name,5);

  return ("No FD", undef)
        if(!$hash || ($^O !~ /Win/ && !defined($hash->{FD})));

  my ($data, $rin, $buf) = ("", "", "");
  my $to = 1;                                         # 1 seconds timeout
  while(length($data) < 28) {
    if($^O =~ m/Win/ && $hash->{USBDev}) {
      $hash->{USBDev}->read_const_time($to*1000); # set timeout (ms)
      # Read anstatt input sonst funzt read_const_time nicht.
      $buf = $hash->{USBDev}->read(999);          
      return ("$name Timeout reading answer for $arg", undef)
        if(length($buf) == 0);

    } else {
      return ("Device lost when reading answer for $arg", undef)
        if(!$hash->{FD});

      vec($rin, $hash->{FD}, 1) = 1;
      my $nfound = select($rin, undef, undef, $to);
      if($nfound < 0) {
        next if ($! == EAGAIN() || $! == EINTR() || $! == 0);
        my $err = $!;
        TCM120_Disconnected($hash);
        return("TCM120_ReadAnswer $err", undef);
      }
      return ("Timeout reading answer for $arg", undef)
        if($nfound == 0);
      $buf = TCM120_SimpleRead($hash);
      return ("No data", undef) if(!defined($buf));

    }

    if(defined($buf)) {
      Log 5, "TCM120/RAW (ReadAnswer): $buf";
      $data .= uc(unpack('H*', $buf));
    }
  }
  return (undef, $data);

}

1;
