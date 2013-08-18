##############################################
# $Id$
package main;

sub DevIo_SimpleRead($);
sub DevIo_TimeoutRead($$);
sub DevIo_SimpleWrite($$$);
sub DevIo_OpenDev($$$);
sub DevIo_CloseDev($@);
sub DevIo_Disconnected($);
sub DevIo_SetHwHandshake($);

########################
sub
DevIo_DoSimpleRead($)
{
  my ($hash) = @_;
  my ($buf, $res);

  if($hash->{USBDev}) {
    $buf = $hash->{USBDev}->input();

  } elsif($hash->{DIODev}) {
    $res = sysread($hash->{DIODev}, $buf, 256);
    $buf = undef if(!defined($res));

  } elsif($hash->{TCPDev}) {
    $res = sysread($hash->{TCPDev}, $buf, 256);
    $buf = "" if(!defined($res));

  }
  return $buf;
}

########################
sub
DevIo_SimpleRead($)
{
  my ($hash) = @_;
  my $buf = DevIo_DoSimpleRead($hash);

  ###########
  # Lets' try again: Some drivers return len(0) on the first read...
  if(defined($buf) && length($buf) == 0) {
    $buf = DevIo_DoSimpleRead($hash);
  }

  if(!defined($buf) || length($buf) == 0) {
    DevIo_Disconnected($hash);
    return undef;
  }
  return $buf;
}

########################
# Read until you get the timeout. Use it with care
sub
DevIo_TimeoutRead($$)
{
  my ($hash, $timeout) = @_;

  my $answer = "";
  for(;;) {
    my $rin = "";
    vec($rin, $hash->{FD}, 1) = 1;
    my $nfound = select($rin, undef, undef, $timeout);
    last if($nfound <= 0);
    my $r = DevIo_DoSimpleRead($hash);
    last if(!defined($r));
    $answer .= $r;
  }
  return $answer;
}


########################
# Input is HEX, with header and CRC
sub
DevIo_SimpleWrite($$$)
{
  my ($hash, $msg, $ishex) = @_;
  return if(!$hash);

  my $name = $hash->{NAME};
  Log3 $name, 5, "SW: $msg";

  $msg = pack('H*', $msg) if($ishex);
  $hash->{USBDev}->write($msg)    if($hash->{USBDev});
  syswrite($hash->{TCPDev}, $msg) if($hash->{TCPDev});
  syswrite($hash->{DIODev}, $msg) if($hash->{DIODev});
  select(undef, undef, undef, 0.001);
}


########################
sub
DevIo_OpenDev($$$)
{
  my ($hash, $reopen, $initfn) = @_;
  my $dev = $hash->{DeviceName};
  my $name = $hash->{NAME};
  my $po;
  my $baudrate;
  ($dev, $baudrate) = split("@", $dev);

  $hash->{PARTIAL} = "";
  Log3 $name, 3, "Opening $name device $dev"
        if(!$reopen);

  if($dev =~ m/^UNIX:(SEQPACKET|STREAM):(.*)$/) { # FBAHA
    my ($type, $fname) = ($1, $2);
    my $conn;
    eval {
      require IO::Socket::UNIX;
      $conn = IO::Socket::UNIX->new(
        Type=>($type eq "STREAM" ? SOCK_STREAM:SOCK_SEQPACKET), Peer=>$fname);
    };
    if($@) {
      Log3 $name, 1, $@;
      return $@;
    }

    if(!$conn) {
      Log3 $name, 3, "Can't connect to $dev: $!" if(!$reopen);
      $readyfnlist{"$name.$dev"} = $hash;
      $hash->{STATE} = "disconnected";
      return "";
    }
    $hash->{TCPDev} = $conn;
    $hash->{FD} = $conn->fileno();
    delete($readyfnlist{"$name.$dev"});
    $selectlist{"$name.$dev"} = $hash;

  } elsif($dev =~ m/^(.+):([0-9]+)$/) {       # host:port

    # This part is called every time the timeout (5sec) is expired _OR_
    # somebody is communicating over another TCP connection. As the connect
    # for non-existent devices has a delay of 3 sec, we are sitting all the
    # time in this connect. NEXT_OPEN tries to avoid this problem.
    if($hash->{NEXT_OPEN} && time() < $hash->{NEXT_OPEN}) {
      return;
    }

    my $timeout = $hash->{TIMEOUT} ? $hash->{TIMEOUT} : 3;
    my $conn = IO::Socket::INET->new(PeerAddr => $dev, Timeout => $timeout);
    if($conn) {
      delete($hash->{NEXT_OPEN})

    } else {
      Log3 $name, 3, "Can't connect to $dev: $!" if(!$reopen);
      $readyfnlist{"$name.$dev"} = $hash;
      $hash->{STATE} = "disconnected";
      $hash->{NEXT_OPEN} = time()+60;
      return "";
    }

    $hash->{TCPDev} = $conn;
    $hash->{FD} = $conn->fileno();
    delete($readyfnlist{"$name.$dev"});
    $selectlist{"$name.$dev"} = $hash;

  } elsif($baudrate && lc($baudrate) eq "directio") { # w/o Device::SerialPort

    if(!open($po, "+<$dev")) {
      return undef if($reopen);
      Log3 $name, 3, "Can't open $dev: $!";
      $readyfnlist{"$name.$dev"} = $hash;
      $hash->{STATE} = "disconnected";
      return "";
    }

    $hash->{DIODev} = $po;

    if( $^O =~ /Win/ ) {
      $readyfnlist{"$name.$dev"} = $hash;
    } else {
      $hash->{FD} = fileno($po);
      delete($readyfnlist{"$name.$dev"});
      $selectlist{"$name.$dev"} = $hash;
    }


  } else {                              # USB/Serial device

    if ($^O=~/Win/) {
     eval {
       require Win32::SerialPort;
       $po = new Win32::SerialPort ($dev);
     }
    } else  {
     eval {
       require Device::SerialPort;
       $po = new Device::SerialPort ($dev);
     }
    }
    if($@) {
      Log3 $name,  1, $@;
      return $@;
    }

    if(!$po) {
      return undef if($reopen);
      Log3 $name, 3, "Can't open $dev: $!";
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
      Log3 $name, 3, "Setting $name baudrate to $baudrate";
      $po->baudrate($baudrate);
      $po->databits(8);
      $po->parity('none');
      $po->stopbits(1);
      $po->handshake('none');

      # This part is for some Linux kernel versions whih has strange default
      # settings.  Device::SerialPort is nice: if the flag is not defined for
      # your OS then it will be ignored.

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
    Log3 $name, 1, "$dev reappeared ($name)";
  } else {
    Log3 $name, 3, "$name device opened";
  }

  $hash->{STATE}="opened";

  my $ret;
  if($initfn) {
    my $ret  = &$initfn($hash);
    if($ret) {
      DevIo_CloseDev($hash);
      Log3 $name, 1, "Cannot init $dev, ignoring it";
    }
  }

  DoTrigger($name, "CONNECTED") if($reopen);
  return $ret;
}

sub
DevIo_SetHwHandshake($)
{
  my ($hash) = @_;
  $hash->{USBDev}->can_dtrdsr();
  $hash->{USBDev}->can_rtscts();
}

########################
sub
DevIo_CloseDev($@)
{
  my ($hash,$isFork) = @_;
  my $name = $hash->{NAME};
  my $dev = $hash->{DeviceName};

  return if(!$dev);
  
  if($hash->{TCPDev}) {
    $hash->{TCPDev}->close();
    delete($hash->{TCPDev});

  } elsif($hash->{USBDev}) {
    if($isFork) { # SerialPort close resets the serial parameters.
      POSIX::close($hash->{USBDev}{FD});
    } else {
      $hash->{USBDev}->close() ;
    }
    delete($hash->{USBDev});

  } elsif($hash->{DIODev}) {
    close($hash->{DIODev});
    delete($hash->{DIODev});

  }
  ($dev, undef) = split("@", $dev); # Remove the baudrate
  delete($selectlist{"$name.$dev"});
  delete($readyfnlist{"$name.$dev"});
  delete($hash->{FD});
}

sub
DevIo_Disconnected($)
{
  my $hash = shift;
  my $dev = $hash->{DeviceName};
  my $name = $hash->{NAME};
  my $baudrate;
  ($dev, $baudrate) = split("@", $dev);

  return if(!defined($hash->{FD}));                 # Already deleted or RFR

  Log3 $name, 1, "$dev disconnected, waiting to reappear";
  DevIo_CloseDev($hash);
  $readyfnlist{"$name.$dev"} = $hash;               # Start polling
  $hash->{STATE} = "disconnected";

  # Without the following sleep the open of the device causes a SIGSEGV,
  # and following opens block infinitely. Only a reboot helps.
  sleep(5) if($hash->{USBDEV});

  DoTrigger($name, "DISCONNECTED");
}


1;
