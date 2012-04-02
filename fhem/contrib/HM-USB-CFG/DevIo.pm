##############################################
# $Id$
package main;
use Device::USB;
my $timeout = 1000 ;

sub DevIo_SimpleRead($);
sub DevIo_TimeoutRead($$);
sub DevIo_SimpleWrite($$);
sub DevIo_OpenDev($$$);
sub DevIo_CloseDev($);
sub DevIo_Disconnected($);

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
    $buf = undef if(!defined($res));
  }
######################################### HID by peterp
   elsif($hash->{HIDDev}) {
   my $r;         #raw message
   my $b=0;       #raw message payload
   my $c=0;       # ignore counter
   my $d=0;       #HM message length
   my $s = 0;     #start counter
   my $start = 0; #raw header flag
   my $typ ="";

   $res = sysread($hash->{HIDDev}, $buf, 512);
   $buf = undef if(!defined($res));

## HID specific
   for (my $i=0; $i<64;$i++)
      {
      if ($start != 0)
         {
         $r .= unpack('H*', substr($buf,4+$i*8,1)); #copy to raw HMmessage
         if ($typ eq "E")
            { 
            if ($b > 12) #raw message payload
               {     
               $d--;
               if ($d == 0)
                  {
                  $r .= "\n";                        #form a raw HMmessage for parse like HMLAN
                  $start = 0;
#                  Log 4, "HMUSB HMmessage:$r";
                  }
               }
            $b++;
            }
         else
            {
               $d--;
               if ($d == 0)
                  {
                  Log 2, "HMUSB HMmessage:$r";
                  $r .= "\n";                        #form a raw HMmessage for parse like HMLAN
                  $start = 0;
                  }
            }
         }
      else
         {
#         $r = unpack('H*', substr($buf,4+$i*8,1));
#         Log 4, "$r\t";
         if ( ord(substr($buf,4+$i*8,1)) == 69)
            {
            $start = 1;                           #raw header found
            $r = "E";                             #start a raw HMmessage for parse like HMLAN
            $d = ord(substr($buf,4+($i+13)*8,1)); #calc HM message length
            $s = $i;
            $typ ="E";
#            Log 4, "HMUSB ReadSimple Magic found HMlen:$d";
            }
         elsif ( ord(substr($buf,4+$i*8,1)) == 73)
            {
            Log 2, "HMUSB ReadSimple Magic >I< found i:$i b:$b ";
            $start = 1;                           #raw header found
            $typ = "I";
            $d = 4;
            }
         elsif ( ord(substr($buf,4+$i*8,1)) == 82)
            {
            Log 2, "HMUSB ReadSimple Magic >R< found i:$i b:$b ";
            }
         elsif ( ord(substr($buf,4+$i*8,1)) == 72)
            {
            Log 2, "HMUSB ReadSimple Magic >H< USB-IF found i:$i b:$b";
            $start = 1;                           #raw header found
            $typ = "H";
            $d = 40;
            }
         else
            {
            $c++; #ignore counter
            } 
         } 
      }
#   Log 4, "HMUSB ReadSimple all >$r< (raw Start $s ignored $c)";
if ($typ eq "E")
   {
   my ($src, $status, $msec, $d2, $rssi, $msg);
   $r =~ m/^E(......)(....)(........)(..)(....)(.*)/;
      ($src, $status, $msec, $d2, $rssi, $msg) =
      ($1, $2, $3, $4, $5, $6);
   my $cmsg = "E".$src.",".$status.",".$msec.",".$d2.",".$rssi.",".$msg."\n";
   Log 4, "HMUSB ReadSimple converted $cmsg";
   return $cmsg;
   }
elsif ($typ eq "H")
   {
   Log 4, "HMUSB ReadSimple Wakup found";
   my ($vers,    $serno, $d1, $owner, $msec, $d2);
   $r =~ m/^HHM-USB-IF(....)(..........)(......)(......)(........)(....)/;
   ($vers,    $serno, $d1, $owner, $msec, $d2) =
     (hex($1), $2,     $3,  $4,     $5,    $6);
   my $wmsg = "HHM-USB-IF".",".$vers.",".$serno.",".$d1.",".$owner.",".$msec.",".$d2."\n"; 
   Log 2, "HMUSB ReadSimple Wakeup converted $wmsg";
   return $wmsg;
   }
elsif ($typ eq "I")
   {
   $r =~ m/^I00.*/;
   return $r;
   }
######################################### HIDDEV by peterp
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
DevIo_SimpleWrite($$)
{
  my ($hash, $msg) = @_;
  return if(!$hash);

  my $name = $hash->{NAME};
  my $ll5 = GetLogLevel($name,3);
  Log $ll5, "DevIo SW: $msg";
####################################################
  if($hash->{HIDDev}) #added for HM-USB-CFG by peterp
     {
     $msg =~ s/,//g; 
     my $msg1 = substr($msg,0,1);
     my $msg2 = pack('H*', substr($msg,1));
     $msg = $msg1 . $msg2 . "\r\n";

     syswrite($hash->{HIDDev}, $msg);

     my $tmsg = unpack('H*', $msg);
     Log 2, "DevIo_SimpleWrite: $tmsg";
     }
  else
####################################################
     {
     $msg = pack('H*', $msg) if($ishex);
     $hash->{USBDev}->write($msg)    if($hash->{USBDev});
     syswrite($hash->{TCPDev}, $msg) if($hash->{TCPDev});
     syswrite($hash->{DIODev}, $msg) if($hash->{DIODev});
     } 
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
  Log 4, "DEVIO OpenDev $name device $dev"
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
      Log(3, "Can't connect to IPDEV $dev: $!") if(!$reopen);
      $readyfnlist{"$name.$dev"} = $hash;
      $hash->{STATE} = "disconnected";
      $hash->{NEXT_OPEN} = time()+60;
      return "";
    }

    $hash->{TCPDev} = $conn;
    $hash->{FD} = $conn->fileno();
    delete($readyfnlist{"$name.$dev"});
    $selectlist{"$name.$dev"} = $hash;

  } elsif($baudrate && lc($baudrate) eq "directio") {   # Without Device::SerialPort

    if(!open($po, "+<$dev")) {
      return undef if($reopen);
      Log(3, "Can't open $dev: $!");
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
#################################################### HIDDEV by peterp
  } elsif($dev =~ m/^\/dev\/usb\/hiddev[0-9]$/) 
      { 
       if(!open($po, "+<$dev"))
         {
         return undef if($reopen);
         Log(3, "Can't open HIDD $dev: $!");
         $readyfnlist{"$name.$dev"} = $hash;
         $hash->{STATE} = "disconnected";
         return "";
         }
      Log(2, "DevIo opened HID $dev"); #peterp

      $hash->{HIDDev} = $po;

    if( $^O =~ /Win/ ) {
      $readyfnlist{"$name.$dev"} = $hash;
    } else {
      $hash->{FD} = fileno($po);
      delete($readyfnlist{"$name.$dev"});
      $selectlist{"$name.$dev"} = $hash;
    }
#################################################### HIDDEV by peterp
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
      Log(3, "Can't open USB/Seriell $dev: $!");
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
      Log 3, "Setting $name baudrate to $baudrate";
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
    Log 1, "$dev reappeared ($name)";
  } else {
    Log 3, "$name device $dev opened";
  }

  $hash->{STATE}="opened";

  my $ret;
  if($initfn) {
    my $ret  = &$initfn($hash);
    if($ret) {
      DevIo_CloseDev($hash);
      Log 1, "Cannot init $dev, ignoring it";
    }
  }

  DoTrigger($name, "CONNECTED") if($reopen);
  return $ret;
}

########################
sub
DevIo_CloseDev($)
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

  } elsif($hash->{DIODev}) {
    close($hash->{DIODev});
    delete($hash->{DIODev});

  } elsif($hash->{HIDDev}) { #added for HM-USB-CFG by peterp
    close($hash->{HIDDev});
    delete($hash->{HIDDev});

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

  Log 1, "$dev disconnected, waiting to reappear";
  DevIo_CloseDev($hash);
  $readyfnlist{"$name.$dev"} = $hash;               # Start polling
  $hash->{STATE} = "disconnected";

  # Without the following sleep the open of the device causes a SIGSEGV,
  # and following opens block infinitely. Only a reboot helps.
  sleep(5);

  DoTrigger($name, "DISCONNECTED");
}


1;