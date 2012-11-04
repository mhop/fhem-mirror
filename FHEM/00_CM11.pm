################################################################
#
#  Copyright notice
#
#  (c) 2008 Dr. Boris Neubert (omega@online.de)
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
#
################################################################

# $Id$

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);


sub CM11_Write($$$);
sub CM11_Read($);
sub CM11_Ready($$);

my $msg_pollpc   = pack("H*", "5a"); # interface poll signal (CM11->PC)
my $msg_pollpcpf = pack("H*", "a5"); # power fail poll signal (CM11->PC)
my $msg_pollack  = pack("H*", "c3"); # response to poll signal (PC->CM11)
my $msg_pollackpf= pack("H*", "fb"); # response to power fail poll signal (PC->CM11)
my $msg_txok     = pack("H*", "00"); # OK for transmission (PC->CM11)
my $msg_ifrdy    = pack("H*", "55"); # interface ready (CM11->PC)
my $msg_statusrq = pack("H*", "8b");  # status request (PC->CM11)

my %housecodes_rcv = qw(0110 A  1110 B  0010 C  1010 D
                        0001 E  1001 F  0101 G  1101 H
                        0111 I  1111 J  0011 K  1011 L
                        0000 M  1000 N  0100 O  1100 P);

my %unitcodes_rcv  = qw(0110 1  1110 2  0010 3  1010 4
                        0001 5  1001 6  0101 7  1101 8
                        0111 9  1111 10  0011 11  1011 12
                        0000 13  1000 14 0100 15 1100 16);

my %functions_rcv  = qw(0000 ALL_UNITS_OFF
			0001 ALL_LIGHTS_ON
			0010 ON
			0011 OFF
			0100 DIM
			0101 BRIGHT
			0110 ALL_LIGHTS_OFF
                        0111 EXTENDED_CODE
			1000 HAIL_REQUEST
			1001 HAIL_ACK
			1010 PRESET_DIM1
			1011 PRESET_DIM2
			1100 EXTENDED_DATA_TRANSFER
                        1101 STATUS_ON
			1110 STATUS_OFF
			1111 STATUS_REQUEST);


my %gets = (
  "fwrev"   => "xxx",
  "time"   => "xxx",
);

my %sets = (
  "reopen"   => "xxx",
);


#####################################

sub
CM11_Initialize($)
{
  my ($hash) = @_;

# Provider
  $hash->{ReadFn}  = "CM11_Read";
  $hash->{WriteFn} = "CM11_Write";
  $hash->{Clients} = ":X10:";
  $hash->{ReadyFn} = "CM11_Ready";

# Normal Device
  $hash->{DefFn}   = "CM11_Define";
  $hash->{UndefFn} = "CM11_Undef";
  $hash->{GetFn}   = "CM11_Get";
  $hash->{SetFn}   = "CM11_Set";
  $hash->{StateFn} = "CM11_SetState";
  $hash->{AttrList}= "do_not_notify:1,0 dummy:1,0 " .
                     "model:CM11 loglevel:0,1,2,3,4,5,6";
}
#####################################
sub
CM11_DoInit($$$)
{
  my ($name,$type,$po) = @_;
  my @init;

  $po->reset_error();
  $po->baudrate(4800);
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
  $defs{$name}{STATE} = "Initialized";

}


#####################################
sub
CM11_Reopen($)
{
  my ($hash) = @_;

  my $dev = $hash->{DeviceName};
  $hash->{PortObj}->close();
  Log 1, "Device $dev closed";
  for(;;) {
      sleep(5);
      if($^O =~ m/Win/) {
        $hash->{PortObj} = new Win32::SerialPort($dev);
      }else{
        $hash->{PortObj} = new Device::SerialPort($dev);
      }
      if($hash->{PortObj}) {
        Log 1, "Device $dev reopened";
        $hash->{FD} = $hash->{PortObj}->FILENO if($^O !~ m/Win/);
        CM11_DoInit($hash->{NAME}, $hash->{ttytype}, $hash->{PortObj});
        return;
      }
  }
}

#####################################
sub
CM11_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $po;

  return "wrong syntax: define <name> CM11 devicename ".
                        "[normal|strangetty] [mobile]" if(@a < 3 || @a > 5);


  delete $hash->{PortObj};
  delete $hash->{FD};

  my $name = $a[0];
  my $dev = $a[2];
  $hash->{ttytype} = $a[3] if($a[3]);
  $hash->{MOBILE} = 1 if($a[4] && $a[4] eq "mobile");
  $hash->{STATE} = "defined";

  if($dev eq "none") {
    Log 1, "CM11 device is none, commands will be echoed only";
    $attr{$name}{dummy} = 1;
    return undef;
  }

  $hash->{DeviceName} = $dev;
  $hash->{PARTIAL} = "";
  Log 3, "CM11 opening CM11 device $dev";
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
  Log 3, "CM11 opened CM11 device $dev";

  $hash->{PortObj} = $po;
  if( $^O !~ /Win/ ) {
    $hash->{FD} = $po->FILENO;
    $selectlist{"$name.$dev"} = $hash;
  } else {
    $readyfnlist{"$name.$dev"} = $hash;
  }

  CM11_DoInit($name, $hash->{ttytype}, $po);

  #CM11_SetInterfaceTime($hash);
  #CM11_GetInterfaceStatus($hash);
  return undef;
}

#####################################
sub
CM11_Undef($$)
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
CM11_SetState($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;
  return undef;
}

#####################################
sub
CM11_LogReadWrite($@)
{
  my ($rw,$hash, $msg, $trlr) = @_;
  my $name= $hash->{NAME};
  Log GetLogLevel($name,5),
      "CM11 device " . $name . ": $rw " .
      sprintf("%2d: ", length($msg)) . unpack("H*", $msg);
}

sub
CM11_LogRead(@)
{
  CM11_LogReadWrite("read ", @_);
}

sub
CM11_LogWrite(@)
{
  CM11_LogReadWrite("write", @_);
}

#####################################

sub
CM11_SimpleWrite($$)
{
  my ($hash, $msg) = @_;
  return if(!$hash || !defined($hash->{PortObj}));
  CM11_LogWrite($hash,$msg);
  $hash->{PortObj}->write($msg);
}

#####################################
sub
CM11_ReadDirect($$)
{
  # This is a direct read for CM11_Write
  my ($hash,$arg) = @_;
  return undef if(!$hash || !defined($hash->{FD}));

  my $name= $hash->{NAME};
  my $prefix= "CM11 device " . $name . ":";
  my $rin= '';
  my $nfound;

  if($^O eq 'MSWin32') {
      $nfound= CM11_Ready($hash, undef);
  } else {
      vec($rin, $hash->{FD}, 1) = 1;
      my $to = 20;  # seconds timeout (response might be damn slow)
      $to = $hash->{RA_Timeout} if($hash->{RA_Timeout});  # ...or less
      $nfound = select($rin, undef, undef, $to);
      if($nfound < 0) {
        next if ($! == EAGAIN() || $! == EINTR() || $! == 0);
        Log GetLogLevel($name,3), "$prefix Select error $nfound / $!";
        return undef;
      }
  }
  if(!$nfound) {
      Log GetLogLevel($name,3), "$prefix Timeout reading $arg";
      return undef;
  }

  my $buf = $hash->{PortObj}->input();
  CM11_LogRead($hash,$buf);
  return $buf;
}

#####################################
sub
CM11_Write($$$)
{
  # send two bytes, verify checksum, send ok
  my ($hash,$b1,$b2) = @_;
  my $name = $hash->{NAME};
  my $prefix= "CM11 device $name:";

  if(!$hash || !defined($hash->{PortObj})) {
    Log GetLogLevel($name,3),
        "$prefix device is not active, cannot send";
    return;

  }

  # checksum
  my $b1d = unpack('C', $b1);
  my $b2d = unpack('C', $b2);
  my $checksum_w = ($b1d + $b2d) & 0xff;

  my $data;

  # try 5 times to send
  my $try= 5;
  for(;;) {
    $try--;
    # send two bytes
    $data= $b1 . $b2;
    CM11_LogWrite($hash,$data);
    $hash->{PortObj}->write($data);

    # get checksum
    my $checksum= CM11_ReadDirect($hash, "checksum");
    return 0 if(!defined($checksum)); # read failure

    my $checksum_r= unpack('C', $checksum);
    if($checksum_w ne $checksum_r) {
      Log 5,
      "$prefix wrong checksum (send: $checksum_w, received: $checksum_r)";
      return 0 if(!$try);
      my $nexttry= 6-$try;
      Log 5,
      "$prefix retrying (" . $nexttry . "/5)";
    } else {
      Log 5, "$prefix checksum correct, OK for transmission";
      last;
    }
  }

  # checksum ok => send OK for transmission
  $data= $msg_txok;
  CM11_LogWrite($hash,$data);
  $hash->{PortObj}->write($data);
  my $ready= CM11_ReadDirect($hash, "ready");
  return 0 if(!defined($ready)); # read failure
  if($ready ne $msg_ifrdy) {
      Log GetLogLevel($name,3),
        "$prefix strange ready signal (" . unpack('C', $ready) . ")";
      return 0
  } else {
      Log 5, "$prefix ready";
  }

  # we are fine
  return 1;
}

#####################################
sub
CM11_GetInterfaceStatus($)
{
    my ($hash)= @_;

    CM11_SimpleWrite($hash, $msg_statusrq);
    my $statusmsg= "";
    while(length($statusmsg)<14) {
      my $buf= CM11_ReadDirect($hash, "status");
      return if(!defined($buf)); # read error
      $statusmsg.= $buf;
    }
    return $statusmsg;
}

#####################################
sub CM11_Get($@)
{
  my ($hash, @a) = @_;

  return "CM11: get needs only one parameter" if(@a != 2);
  return "Unknown argument $a[1], choose one of " . join(",", sort keys %gets)
        if(!defined($gets{$a[1]}));

  my ($fn, $arg) = split(" ", $gets{$a[1]});

  my $v = join(" ", @a);
  my $name = $hash->{NAME};
  Log GetLogLevel($name,2), "CM11 get $v";

  my $statusmsg= CM11_GetInterfaceStatus($hash);
  if(!defined($statusmsg)) {
	$v= "error";
	Log 2, "CM11 error, device is irresponsive."
  } else {
	my $msg= unpack("H*", $statusmsg);
  	Log 5, "CM11 got ". $msg;

	if($a[1] eq "fwrev") {
    		$v = hex(substr($msg, 14, 1));
  	} elsif($a[1] eq "time") {
		my $sec= hex(substr($msg, 4, 2));
		my $hour= hex(substr($msg, 8, 2))*2;
		my $min= hex(substr($msg, 6, 2)); 
		if($min>59) {
			$min-= 60;
			$hour++;	
		}
		my $day= hex(substr($msg, 10, 2));
		$day+= 256 if(hex(substr($msg, 12, 1)) & 0xf);
		$v= sprintf("%d.%02d:%02d:%02d", $day,$hour,$min,$sec);
	}
  }
  $hash->{READINGS}{$a[1]}{VAL} = $v;
  $hash->{READINGS}{$a[1]}{TIME} = TimeNow();

  return "$a[0] $a[1] => $v";
}


#####################################
sub
CM11_Set($@)
{
  my ($hash, @a) = @_;

  return "CM11: set needs one parameter" if(@a != 2);
  return "Unknown argument $a[1], choose one of " . join(" ", sort keys %sets)
        if(!defined($sets{$a[1]}));

  my ($fn, $arg) = split(" ", $sets{$a[1]});

  my $v = join(" ", @a);
  my $name = $hash->{NAME};
  Log GetLogLevel($name,2), "CM11 set $v";

  if($a[1] eq "reopen") {
    CM11_Reopen($hash);
  }

  return undef;
}

#####################################
sub
CM11_SetInterfaceTime($)
{
    my ($hash)= @_;

# 7 Bytes, Bits 0..55 are
# 55 to 48   timer download header (0x9b)
# 47 to 40   Current time (seconds)
# 39 to 32   Current time (minutes ranging from 0 to 119)
# 31 to 23   Current time (hours/2, ranging from 0 to 11)
# 23 to 16   Current year day (bits 0 to 7)
# 15         Current year day (bit 8)
# 14 to 8    Day mask (SMTWTFS)
# 7 to 4     Monitored house code
# 3          Reserved
# 2          Battery timer clear flag
# 1          Monitored status clear flag
# 0          Timer purge flag

    # make the interface happy (time is set to zero)
    my $data = pack('C7', 0x9b,0x00,0x00,0x00,0x00,0x00,0x03);
    CM11_SimpleWrite($hash, $data);
    # get checksum (ignored)
    my $checksum= CM11_ReadDirect($hash, "checksum");
    return 0 if(!defined($checksum)); # read failure
    # tx OK
    CM11_SimpleWrite($hash, $msg_txok);
    # get ready (ignored)
    my $ready= CM11_ReadDirect($hash, "ready");
    return 0 if(!defined($ready)); # read failure
    return 1;
}

#####################################
sub
CM11_Read($)
{
  #
  # prolog
  #

  my ($hash) = @_;

  my $buf = $hash->{PortObj}->input();
  my $name = $hash->{NAME};

  # prefix for logging
  my $prefix= "CM11 device " . $name . ":";

  # Lets' try again: Some drivers return len(0) on the first read...
  if(defined($buf) && length($buf) == 0) {
    $buf = $hash->{PortObj}->input();
  }

  # USB troubleshooting
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
  }

  #
  # begin of message digesting
  #

  # concatenate yet unparsed message and newly received data
  my $x10data = $hash->{PARTIAL} . $buf;
  CM11_LogRead($hash,$buf);
  Log 5, "$prefix Data: " . unpack('H*',$x10data);

  # normally the while loop will run only once
  while(length($x10data) > 0) {

        # we cut off everything before the latest poll signal
        my $p= index(reverse($x10data), $msg_pollpc);
        if($p<0) { $p= index(reverse($x10data), $msg_pollpcpf); }
        if($p>=0) { $x10data= substr($x10data, -$p-1); }

        # to start with, a single 0x5a is received
	if( substr($x10data,0,1) eq $msg_pollpc ) {	# CM11 polls PC
		Log 5, "$prefix start of message";
		CM11_SimpleWrite($hash, $msg_pollack);	# PC ready
		$x10data= substr($x10data,1);		# $x10data now empty
		next;
	}

        # experimental code follows
	#if( substr($x10data,0,2) eq pack("H*", "98e6") ) {	# CM11 polls PC
        #	Log 5, "$prefix 98e6";
	#	CM11_SimpleWrite($hash, $msg_pollack);	# PC ready
        #        $x10data= "";
	#	next;
	#}
	#if( substr($x10data,0,1) eq pack("H*", "98") ) {	# CM11 polls PC
	#	Log 5, "$prefix 98";
	#	next;
	#}

        # a single 0xa5 is a power-fail macro download poll
        if( substr($x10data,0,1) eq $msg_pollpcpf ) {     # CM11 polls PC
                Log 5, "$prefix power-fail poll";
                # the documentation wrongly says that the macros should be downloaded
                # in fact, the time must be set!
                if(CM11_SetInterfaceTime($hash)) {
                  Log 5, "$prefix power-fail poll satisfied";
                } else {
                  Log 5, "$prefix power-fail poll satisfaction failed";
                }
                $x10data= substr($x10data,1);             # $x10data now empty
                next;
        }

        # a single 0x55 is a leftover from a failed transmission
        if( substr($x10data,0,1) eq $msg_ifrdy ) {      # CM11 polls PC
                Log 5, "$prefix skipping leftover ready signal";
                $x10data= substr($x10data,1);
                next;
        }

        # the message comes in small chunks of 1 or few bytes instead of the
        # whole buffer at once
	my $len= ord(substr($x10data,0,1))-1;		# upload buffer size
	last if(length($x10data)< $len+2);		# wait for complete msg

	# message is now complete, start interpretation

	# mask: Bits 0 (LSB)..7 (MSB) correspond to data bytes 0..7
        # bit= 0: unitcode, bit= 1: function
	my $mask= unpack('B8', substr($x10data,1,1));
	$x10data= substr($x10data,2); # cut off length and mask

        # $x10data now contains $len data bytes
	my $databytes= unpack('H*', substr($x10data,0));
	Log 5, "$prefix message complete " .
               "(length $len, mask $mask, data $databytes)";

	# the following lines decode the messages into unitcodes and functions
	# in general we have 0..n unitcodes followed by 1..m functions in the
        # message
	my $i= 0;
	my $dmsg= "";
	while($i< $len) {

		my $data= substr($x10data, $i);
           	my $bits = unpack('B8', $data);
           	my $nibble_hi = substr($bits, 0, 4);
           	my $nibble_lo = substr($bits, 4, 4);

		my $housecode= $housecodes_rcv{$nibble_hi};

		# one hash for unitcodes X_UNIT and one hash for functions
                # X_FUNC is maintained per housecode X= A..P
		my $housecode_unit= $housecode . "_UNIT";
		my $housecode_func= $housecode . "_FUNC";

		my $isfunc= (substr($mask, -$i-1, 1));
		if($isfunc) {
			# data byte is function
			my $x10func= $functions_rcv{$nibble_lo};
			if(($x10func eq "DIM") || ($x10func eq "BRIGHT")) {
				my $level= ord(substr($x10data, ++$i));
				$x10func.= " $level";
			}
			elsif($x10func eq "EXTENDED_DATA_TRANSFER") {
				$data= substr($x10data, 2+(++$i));
				my $command= substr($x10data, ++$i);
				$x10func.= unpack("H*", $data) . ":" .
                                            unpack("H*", $command);
			}
			$hash->{$housecode_func}= $x10func;
			Log 5, "$prefix $housecode_func: " .
                                $hash->{$housecode_func};
			# dispatch message to clients

                        my $hu = $hash->{$housecode_unit};
                        $hu= "" unless(defined($hu));
                        my $hf = $hash->{$housecode_func};
                        my $dmsg= "X10:$housecode;$hu;$hf";
			Dispatch($hash, $dmsg, undef);
		} else {
			# data byte is unitcode
			# if a command was executed before, clear unitcode list
			if(defined($hash->{$housecode_func})) {
				undef $hash->{$housecode_unit};
				undef $hash->{$housecode_func};
			}
			# get unitcode of unitcode
			my $unitcode= $unitcodes_rcv{$nibble_lo};
			# append to list of unitcodes
			my $unitcodes= $hash->{$housecode_unit};
			if(defined($hash->{$housecode_unit})) {
				$unitcodes= $hash->{$housecode_unit} . " ";
			} else {
				$unitcodes= "";
			}
			$hash->{$housecode_unit}= "$unitcodes$unitcode";
			Log 5, "$prefix $housecode_unit: " .
                                $hash->{$housecode_unit};
		}
	$i++;
	}
	$x10data= '';
  }

  $hash->{PARTIAL} = $x10data;
}

#####################################
sub
CM11_Ready($$)
{
  my ($hash, $dev) = @_;
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

    CM11_DoInit($name, $hash->{ttytype}, $po);
    DoTrigger($name, "CONNECTED");
    return undef;

  }

  # This is relevant for windows only
  return undef if !$po;
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags)=$po->status;
  return ($InBytes>0);
}

1;

=pod
=begin html

<a name="CM11"></a>
<h3>CM11</h3>
<ul>
  Note: this module requires the Device::SerialPort or Win32::SerialPort module.
  <br><br>
  <a name="CM11define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; CM11 &lt;serial-device&gt;</code>
    <br><br>
    CM11 is the X10 module to interface X10 devices with the PC.<br><br>

    The current implementation can evaluate incoming data on the powerline of
    any kind. It can send on, off, dimdown and dimup commands.
    <br><br>
    The name of the serial-device depends on your distribution. If
    serial-device is none, then no device will be opened, so you can experiment
    without hardware attached.<br>

    If you experience problems (for verbose 4 you get a lot of "Bad CRC message"
    in the log), then try to define your device as <br>
    <code>define &lt;name&gt; FHZ &lt;serial-device&gt; strangetty</code><br>
    <br>

    Example:
    <ul>
      <code>define x10if CM11 /dev/ttyUSB3</code><br>
    </ul>
    <br>
  </ul>

  <a name="CM11set"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; reopen</code>
    <br><br>
    Reopens the serial port.
  </ul>
  <br>

  <a name="CM11get"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; fwrev</code>
    <br><br>
    Reads the firmware revision of the CM11 device. Returns <code>error</code>
    if the serial connection to the device times out. Can be used for error
    detection.
    <br><br>

    <code>get &lt;name&gt; time</code>
    <br><br>
    Reads the internal time of the device which is the total uptime (modulo one
    year), since fhem sets the time to 0.00:00:00 if the device requests the time
    to be set after being powered on. Returns <code>error</code>
    if the serial connection to the device times out. Can be used for error
    detection.
  </ul>
  <br>

  <a name="CM11attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#attrdummy">dummy</a></li>
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#model">model</a> (CM11)</li>
  </ul>
  <br>
</ul>

=end html
=cut
