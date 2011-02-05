#################################################################################
# 40_RFXCOM.pm
# Modul for FHEM
#
# Tested with USB-RFXCOM-Receiver (433.92MHz, USB, order code 80002)
# (see http://www.rfxcom.com/).
# To use this module, you need to define an RFXCOM receiver:
#	define RFXCOM RFXCOM /dev/ttyUSB0
#
# The module also has code to access LAN based RFXCOM receivers like 81003 and 83003.
# This was tested by me with the help of the RFXCOM people (Thanks to Bert!) and works
# for the basic functions. However a disconnect of the TCP connection is currectly
# not detected. 
#
# To use it define the IP-Adresss and the Port:
#	define RFXCOM RFXCOM 192.168.169.111:10001
# optionally you may issue not to initialize the device (useful if you share an RFXCOM device with other programs) 
#	define RFXCOM RFXCOM 192.168.169.111:10001 noinit
#
# The RFXCOM receivers supports lots of protocols that may be implemented for FHEM 
# writing the appropriate FHEM modules.
# Special thanks to RFXCOM, http://www.rfxcom.com/, for their help. 
# I own an USB-RFXCOM-Receiver (433.92MHz, USB, order code 80002) and highly recommend it.
#
# The module 41_OREGON.pm implements the decoding of the Oregon Scientific weather sensors.
# It is derived from xPL Perl (http://www.xpl-perl.org.uk/). I suggest to look there 
# if you want to implement other protocols.
# 
#  Willi Herzig, 2010
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# 
#################################################################################
# derived from 00_CUL.pm
#
###########################
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

my $last_rmsg = "abcd";
my $last_time = 1;

sub RFXCOM_Clear($);
sub RFXCOM_Read($);
sub RFXCOM_SimpleWrite(@);
sub RFXCOM_SimpleRead($);
sub RFXCOM_Ready($);
sub RFXCOM_Parse($$$$);

sub RFXCOM_OpenDev($$);
sub RFXCOM_CloseDev($);
sub RFXCOM_Disconnected($);

sub
RFXCOM_Initialize($)
{
  my ($hash) = @_;

# Provider
  $hash->{ReadFn}  = "RFXCOM_Read";
  $hash->{Clients} =
        ":RFXMETER:OREGON:RFXX10REC:RFXELSE:";
  my %mc = (
    "1:RFXMETER"   => "^0.*",
    "2:OREGON"   => "^[\x38-\x78].*",
    "3:RFXX10REC"   => "^(\\ |\\)).*", # 0x20 or 0x29
    "4:RFXELSE"   => "^.*",
  );
  $hash->{MatchList} = \%mc;

  $hash->{ReadyFn} = "RFXCOM_Ready";

# Normal devices
  $hash->{DefFn}   = "RFXCOM_Define";
  $hash->{UndefFn} = "RFXCOM_Undef";
  $hash->{GetFn}   = "RFXCOM_Get";
  $hash->{SetFn}   = "RFXCOM_Set";
  $hash->{StateFn} = "RFXCOM_SetState";
  $hash->{AttrList}= "do_not_notify:1,0 do_not_init:1:0 loglevel:0,1,2,3,4,5,6";
  $hash->{ShutdownFn} = "RFXCOM_Shutdown";
}

#####################################
sub
RFXCOM_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> RFXCOM devicename [noinit]"
    if(@a != 3 && @a != 4);

  RFXCOM_CloseDev($hash);

  my $name = $a[0];
  my $dev = $a[2];
  my $opt = $a[3] if(@a == 4);;

  if($dev eq "none") {
    Log 1, "RFXCOM: $name device is none, commands will be echoed only";
    $attr{$name}{dummy} = 1;
    return undef;
  }

  if(defined($opt)) {
    if($opt eq "noinit") {
      Log 1, "RFXCOM: $name no init is done";
      $attr{$name}{do_not_init} = 1;
    } else {
      return "wrong syntax: define <name> RFXCOM devicename [noinit]"
    }
  }
  
  
  $hash->{DeviceName} = $dev;
  my $ret = RFXCOM_OpenDev($hash, 0);
  return $ret;
}


#####################################
sub
RFXCOM_Undef($$)
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

  RFXCOM_CloseDev($hash); 
  return undef;
}

#####################################
sub
RFXCOM_Shutdown($)
{
  my ($hash) = @_;
  return undef;
}

#####################################
sub
RFXCOM_Set($@)
{
  my ($hash, @a) = @_;

  my $msg;
  my $name=$a[0];
  my $reading= $a[1];
  $msg="$name => No Set function ($reading) implemented";
    Log 1,$msg;
    return $msg;
}

#####################################
sub
RFXCOM_Get($@)
{
  my ($hash, @a) = @_;

  my $msg;
  my $name=$a[0];
  my $reading= $a[1];
  $msg="$name => No Get function ($reading) implemented";
    Log 1,$msg;
    return $msg;
}

#####################################
sub
RFXCOM_SetState($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;
  return undef;
}

sub
RFXCOM_Clear($)
{
  my $hash = shift;
  my $buf;

  # clear buffer:
  if($hash->{USBDev}) {
    while ($hash->{USBDev}->lookfor()) { 
    	$buf = RFXCOM_SimpleRead($hash);
    }
  }
  if($hash->{TCPDev}) {
   # TODO
   # while ($hash->{USBDev}->lookfor()) { 
   # 	$buf = RFXCOM_SimpleRead($hash);
   # }
    return $buf;
  }


}

#####################################
sub
RFXCOM_DoInit($)
{
  my $hash = shift;
  my $name = $hash->{NAME};
  my $err;
  my $msg = undef;
  my $buf;
  my $char = undef ;

  RFXCOM_Clear($hash);

  if(defined($attr{$name}) && defined($attr{$name}{"do_not_init"})) {
    	Log 1, "RFXCOM: defined with noinit. Do not send init string to device.";
  	$hash->{STATE} = "Initialized" if(!$hash->{STATE});

        # Reset the counter
        delete($hash->{XMIT_TIME});
        delete($hash->{NR_CMD_LAST_H});

	return undef;
  }

  #
  # Init
  my $init = pack('H*', 'F02C');
  RFXCOM_SimpleWrite($hash, $init);
  sleep(1);

  $buf = RFXCOM_SimpleRead($hash);
  if (defined($buf)) { $char = ord($buf); }
  if (! $buf) {
	return "RFXCOM: Initialization Error $name: no char read";
  } elsif ($char ne 0x2c) {
	my $hexline = unpack('H*', $buf);
    	Log 1, "RFXCOM: Initialization Error hexline='$hexline'";
	return "RFXCOM: Initialization Error %name expected char=0x2c, but char=$char received.";
  } else {
    	Log 1, "RFXCOM: Init OK";
  	$hash->{STATE} = "Initialized" if(!$hash->{STATE});
  }
  #

  # Reset the counter
  delete($hash->{XMIT_TIME});
  delete($hash->{NR_CMD_LAST_H});

  return undef;
}


#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub
RFXCOM_Read($)
{
  my ($hash) = @_;

  my $name = $hash->{NAME};

  my $char;

  my $mybuf = RFXCOM_SimpleRead($hash);

  if(!defined($mybuf) || length($mybuf) == 0) {
    RFXCOM_Disconnected($hash);
    return "";
  }

  my $rfxcom_data = $hash->{PARTIAL};
  #Log 5, "RFXCOM/RAW: $rfxcom_data/$mybuf";
  $rfxcom_data .= $mybuf;

  #my $hexline = unpack('H*', $rfxcom_data);
  #Log 1, "RFXCOM: RFXCOM_Read '$hexline'";

  # first char as byte represents number of bits of the message
  my $bits = ord($rfxcom_data);
  my $num_bytes = $bits >> 3; if (($bits & 0x7) != 0) { $num_bytes++; }

  while(length($rfxcom_data) > $num_bytes) {
    # the buffer contains at least the number of bytes we need
    my $rmsg;
    $rmsg = substr($rfxcom_data, 0, $num_bytes+1);
    #my $hexline = unpack('H*', $rmsg);
    #Log 1, "RFXCOM_Read rmsg '$hexline'";
    $rfxcom_data = substr($rfxcom_data, $num_bytes+1);;
    #$hexline = unpack('H*', $rfxcom_data);
    #Log 1, "RFXCOM_Read rfxcom_data '$hexline'";
    #
    RFXCOM_Parse($hash, $hash, $name, $rmsg);
  }
  #Log 1, "RFXCOM_Read END";

  $hash->{PARTIAL} = $rfxcom_data;
}

sub
RFXCOM_Parse($$$$)
{
  my ($hash, $iohash, $name, $rmsg) = @_;

  my $hexline = unpack('H*', $rmsg);
  Log 5, "RFXCOM_Parse1 '$hexline'";

  my %addvals;
  # Parse only if message is different within 2 seconds 
  # (some Oregon sensors always sends the message twice, X10 security sensors even sends the message five times)
  if (("$last_rmsg" ne "$rmsg") || (time() - $last_time) > 1) { 
    Log 5, "RFXCOM_Dispatch '$hexline'";
    #Log 1, "RFXCOM_Dispatch '$hexline'";
    Dispatch($hash, $rmsg, \%addvals); 
    $hash->{"${name}_MSGCNT"}++;
    $hash->{"${name}_TIME"} = TimeNow();
    $hash->{RAWMSG} = $rmsg;
  } else { 
    #Log 1, "RFXCOM_Dispatch '$hexline' dup";
    #Log 1, "<-duplicate->";
  }

  $last_rmsg = $rmsg;
  $last_time = time();

  #$hexline = unpack('H*', $rmsg);
  #Log 1, "RFXCOM_Parse2 '$hexline'";

}


#####################################
sub
RFXCOM_Ready($)
{
  my ($hash) = @_;

  return RFXCOM_OpenDev($hash, 1)
                if($hash->{STATE} eq "disconnected");

  # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  return ($InBytes>0);
}

########################
sub
RFXCOM_SimpleWrite(@)
{
  my ($hash, $msg) = @_;
  return if(!$hash);

  $hash->{USBDev}->write($msg) if($hash->{USBDev});
  syswrite($hash->{TCPDev}, $msg)     if($hash->{TCPDev});

  #my $hexline = unpack('H*', $msg);
  #Log 1, "RFXCOM_SimpleWrite '$hexline'";
  select(undef, undef, undef, 0.001);
}

########################
sub
RFXCOM_SimpleRead($)
{
  my ($hash) = @_;
  my $buf;

  if($hash->{USBDev}) {
    $buf = $hash->{USBDev}->read(1) ; 
    #my $hexline = unpack('H*', $buf);
    #Log 1, "RFXCOM: RFXCOM_SimpleRead1 '$hexline'";
    if (!defined($buf) || length($buf) == 0) {
	#sleep(1); 
	$buf = $hash->{USBDev}->read(1) ; 
    }
    return $buf;
  }

  if($hash->{TCPDev}) {
    my $buf;
    if(!defined(sysread($hash->{TCPDev}, $buf, 1))) {
      RFXCOM_Disconnected($hash);
      return undef;
    }
    return $buf;
  }

  return undef;
}

########################
sub
RFXCOM_CloseDev($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $dev = $hash->{DeviceName};

  return if(!$dev);
  
  Log 1, "RFXCOM: closing $dev";
  if($hash->{TCPDev}) {
    $hash->{TCPDev}->close();
    delete($hash->{TCPDev});

  } elsif($hash->{USBDev}) {
    $hash->{USBDev}->close() ;
    delete($hash->{USBDev});

  }
  delete($selectlist{"$name.$dev"});
  delete($readyfnlist{"$name.$dev"});
  delete($hash->{FD});
}

########################
sub
RFXCOM_OpenDev($$)
{
  my ($hash, $reopen) = @_;
  my $dev = $hash->{DeviceName};
  my $name = $hash->{NAME};
  my $po;


  $hash->{PARTIAL} = "";
  Log 3, "RFXCOM opening $name device $dev"
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
      delete($hash->{NEXT_OPEN});
    } else {
      Log(3, "RFXCOM: Can't connect to $dev: $!") if(!$reopen);
      $readyfnlist{"$name.$dev"} = $hash;
      $hash->{STATE} = "disconnected";
      $hash->{NEXT_OPEN} = time()+60;
      RFXCOM_Disconnected($hash);
      return "";
    }

    $hash->{TCPDev} = $conn;
    $hash->{FD} = $conn->fileno();
    delete($readyfnlist{"$name.$dev"});
    $selectlist{"$name.$dev"} = $hash;

  } else {                              # USB Device

    if ($^O=~/Win/) {
     require Win32::SerialPort;
     $po = new Win32::SerialPort ($dev);
    } else  {
     #Log(1, "RFXCOM: new Device");
     require Device::SerialPort;
     $po = new Device::SerialPort ($dev);
    }

    if(!$po) {
      return undef if($reopen);
      Log(3, "RFXCOM: Can't open $dev: $!");
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

    #$po->reset_error || Log 1, "RFXCOM reset_error";
    $po->databits(8) || Log 1, "RFXCOM could not set databits";
    $po->baudrate(4800) || Log 1, "RFXCOM could not set baudrate";
    $po->parity('none') || Log 1, "RFXCOM could not set parity";
    $po->stopbits(1) || Log 1, "RFXCOM could not set stopbits";
    $po->handshake('none') || Log 1, "RFXCOM could not set handshake";
    $po->datatype('raw') || Log 1, "RFXCOM could not set datatype";
    #$po->lookclear || Log 1, "RFXCOM could not set lookclear";


    $po->write_settings || Log 1, "RFXCOM could not write_settings $dev";

    $hash->{po} = $po;
    $hash->{socket} = 0;

  Log 1, "RFXCOM: RFXCOM_OpenDev $dev done";
  }

  if($reopen) {
    Log 1, "RFXCOM: $dev reappeared ($name)";
  } else {
    Log 3, "RFXCOM: device opened";
  }

  $hash->{STATE}="";       # Allow InitDev to set the state
  my $ret  = RFXCOM_DoInit($hash);

  if($ret) {
    #  try again
    Log 1, "RFXCOM: Cannot init $dev, at first try. Trying again.";
    my $ret  = RFXCOM_DoInit($hash);
    if($ret) {
      RFXCOM_CloseDev($hash);
      Log 1, "RFXCOM: Cannot init $dev, ignoring it";
      return "RFXCOM: Error Init string.";
    }
  }

  DoTrigger($name, "CONNECTED") if($reopen);
  return $ret;
}

sub
RFXCOM_Disconnected($)
{
  my $hash = shift;
  my $dev = $hash->{DeviceName};
  my $name = $hash->{NAME};

  return if(!defined($hash->{FD}));                 # Already deleted or RFR

  Log 1, "RFXCOM: $dev disconnected, waiting to reappear";
  RFXCOM_CloseDev($hash);
  $readyfnlist{"$name.$dev"} = $hash;               # Start polling
  $hash->{STATE} = "disconnected";

  # Without the following sleep the open of the device causes a SIGSEGV,
  # and following opens block infinitely. Only a reboot helps.
  sleep(5);

  DoTrigger($name, "DISCONNECTED");
}

1;
