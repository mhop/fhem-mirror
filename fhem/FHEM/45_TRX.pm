# $Id$
#################################################################################
# 45_TRX.pm
#
# FHEM Module for RFXtrx433
#
# Derived from 00_CUL.pm: Copyright (C) Rudolf Koenig"
#
# Copyright (C) 2012-2016 Willi Herzig
#	  Maintenance since 2018 by KernSani
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# The GNU General Public License may also be found at http://www.gnu.org/licenses/gpl-2.0.html .
#
##############################################################################
#
#	CHANGELOG
#	
#	29.03.2018	Summary for Commandref
#
#
##############################################################################

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday usleep);

my $last_rmsg = "abcd";
my $last_time = 1;
my $trx_rssi = 0;

sub TRX_Clear($);
sub TRX_Read($@);
sub TRX_Ready($);
sub TRX_Parse($$$$);

my %sets = (
  "reopen"    => ""
);

sub
TRX_Initialize($)
{
  my ($hash) = @_;


  require "$attr{global}{modpath}/FHEM/DevIo.pm";

# Provider
  $hash->{ReadFn}  = "TRX_Read";
  $hash->{WriteFn} = "TRX_Write";
  $hash->{Clients} =
        ":TRX_WEATHER:TRX_SECURITY:TRX_LIGHT:TRX_ELSE:";
  my %mc = (
    "1:TRX_WEATHER"   	=> "^..(40|4e|50|51|52|54|55|56|57|58|5a|5b|5c|5d).*",
    "2:TRX_SECURITY" 	=> "^..(20).*", 
    "3:TRX_LIGHT"	=> "^..(10|11|12|13|14|15|16|17|18|19).*", 
    "4:TRX_ELSE"   	=> "^..(0[0-9a-f]|1[a-f]|2[1-9a-f]|3[0-9a-f]|4[1-9a-d]|4f|53|59|5e|5f|[6-9a-f][0-9a-f]).*",
  );
  $hash->{MatchList} = \%mc;

  $hash->{ReadyFn} = "TRX_Ready";
  $hash->{ReadAnswerFn} = "TRX_ReadAnswer";

# Normal devices
  $hash->{DefFn}   = "TRX_Define";
  $hash->{UndefFn} = "TRX_Undef";
  $hash->{GetFn}   = "TRX_Get";
  $hash->{SetFn}   = "TRX_Set";
  $hash->{StateFn} = "TRX_SetState";
  $hash->{AttrList}= "do_not_notify:1,0 dummy:1,0 do_not_init:1,0 addvaltrigger:1,0 longids rssi:1,0";
  $hash->{ShutdownFn} = "TRX_Shutdown";
}

#####################################
sub
TRX_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);


  if (@a != 3 && @a != 4) {
  	my $msg = "wrong syntax: define <name> TRX devicename [noinit]";
  	Log3 undef, 2, $msg;
  	return $msg;
  }

  DevIo_CloseDev($hash);

  my $name = $a[0];
  my $dev = $a[2];
  my $opt = $a[3] if(@a == 4);;

  if($dev eq "none") {
    Log3 $name, 1, "TRX: $name device is none, commands will be echoed only";
    $attr{$name}{dummy} = 1;
    return undef;
  }

  if(defined($opt)) {
    if($opt eq "noinit") {
      Log3 $name, 1 , "TRX: $name no init is done";
      $attr{$name}{do_not_init} = 1;
    } else {
      return "wrong syntax: define <name> TRX devicename [noinit]"
    }
  }
   
  $hash->{DeviceName} = $dev;
  my $ret = DevIo_OpenDev($hash, 0, "TRX_DoInit");
  return $ret;
}

#####################################
# Input is hexstring
sub
TRX_Write($$)
{
  my ($hash,$fn,$msg) = @_;
  my $name = $hash->{NAME};

  return if(!defined($fn));

  my $bstring;
  $bstring = "$fn$msg";
  Log3 $name, 5, "$hash->{NAME} sending $bstring";

  DevIo_SimpleWrite($hash, $bstring, 1);
}


#####################################
sub
TRX_Undef($$)
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

  DevIo_CloseDev($hash);
  return undef;
}

#####################################
sub
TRX_Shutdown($)
{
  my ($hash) = @_;
  return undef;
}

#####################################
sub
TRX_Reopen($)
{
  my ($hash) = @_;
  DevIo_CloseDev($hash);
  sleep(1);
  DevIo_OpenDev($hash, 0, "TRX_DoInit");
}

#####################################
sub
TRX_Get($@)
{
  my ($hash, @a) = @_;

  my $msg;
  my $name=$a[0];
  my $reading= $a[1];

  $msg="$name => No Get function ($reading) implemented";
  Log3 $name, 1, $msg if ($reading ne "?");
  return $msg;
}

#####################################
sub
TRX_Set($@)
{
  my ($hash, @a) = @_;

  return "\"set TRX\" needs at least one parameter" if(@a < 1);
  return "Unknown argument $a[1], choose one of " . join(" ", sort keys %sets)
  	if(!defined($sets{$a[1]}));

  my $name = shift @a;
  my $type = shift @a;

  if($type eq "reopen") { ####################################
    TRX_Reopen($hash);
  }

  return undef;
}

#####################################
sub
TRX_SetState($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;
  return undef;
}

sub
TRX_Clear($)
{
  my $hash = shift;

  # Clear the pipe
  $hash->{RA_Timeout} = 0.1;

  for(;;) {
    my ($err, undef) = TRX_ReadAnswer($hash, "Clear");
    last if($err);
  }
  delete($hash->{RA_Timeout});
  $hash->{PARTIAL} = "";
}

#####################################
sub
TRX_DoInit($)
{
  my $hash = shift;
  my $name = $hash->{NAME};
  my $err;
  my $msg = undef;
  my $buf;
  my $char = undef ;


  if(defined($attr{$name}) && defined($attr{$name}{"do_not_init"})) {
   	Log3 $name, 1, "TRX: defined with noinit. Do not send init string to device.";
  }
  else
  {
    # Reset
    my $init = pack('H*', "0D00000000000000000000000000");
    DevIo_SimpleWrite($hash, $init, 0);
    DevIo_TimeoutRead($hash, 0.5);
    sleep(1);

    TRX_Clear($hash);

    sleep(1);

    #
    # Get Status
    $init = pack('H*', "0D00000102000000000000000000");
    DevIo_SimpleWrite($hash, $init, 0);
    usleep(50000); # wait 50 ms
    $buf = unpack('H*',DevIo_TimeoutRead($hash, 0.2));

    if (! $buf) {
      Log3 $name, 1, "TRX: Initialization Error: No character read";
      return "TRX: Initialization Error $name: no char read";
    } elsif ($buf !~ m/0d0100....................../ && $buf !~ m/140100..................................../) {
      Log3 $name, 1, "TRX: Initialization Error hexline='$buf', expected 0d0100......................";
      return "TRX: Initialization Error %name expected 0D010, but buf=$buf received.";
    } else {
      Log3 $name,1, "TRX: Init OK";

      # Analyse result and display it:
      if ($buf =~ m/0d0100(..)(..)(..)(..)(..)(..)(..)(..)(..)(..)(..)/) {
        my $status = "";

        my $seqnbr = $1;
        my $cmnd = $2;
        my $msg1 = $3;
        my $msg2 = ord(pack('H*', $4));
        my $msg3 = ord(pack('H*', $5));
        my $msg4 = ord(pack('H*', $6));
        my $msg5 = ord(pack('H*', $7));
        my $freq = { 
	        '50' => '310MHz',
	        '51' => '315MHz',
	        '52' => '433.92MHz receiver only',
	        '53' => '433.92MHz transceiver',
	        '55' => '868.00MHz',
	        '56' => '868.00MHz FSK',
	        '57' => '868.30MHz',
	        '58' => '868.30MHz FSK',
	        '59' => '868.35MHz',
	        '5a' => '868.35MHz FSK',
	        '5b' => '868.95MHz'
                 }->{$msg1} || 'unknown Mhz';
        $status .= $freq;
        $status .= ", " . sprintf "firmware=%d",$msg2;
        $status .= ", protocols enabled: ";
        $status .= "undecoded " if ($msg3 & 0x80); 
        $status .= "RFU " if ($msg3 & 0x40); 
        $status .= "ByronSX " if ($msg3 & 0x20); 
        $status .= "RSL " if ($msg3 & 0x10); 
        $status .= "Lighting4 " if ($msg3 & 0x08); 
        $status .= "FineOffset/Viking " if ($msg3 & 0x04); 
        $status .= "Rubicson " if ($msg3 & 0x02); 
        $status .= "AE/Blyss " if ($msg3 & 0x01); 
        $status .= "BlindsT1/T2/T3/T4 " if ($msg4 & 0x80); 
        $status .= "BlindsT0  " if ($msg4 & 0x40); 
        $status .= "ProGuard " if ($msg4 & 0x20); 
        $status .= "FS20 " if ($msg4 & 0x10); 
        $status .= "LaCrosse " if ($msg4 & 0x08); 
        $status .= "Hideki " if ($msg4 & 0x04); 
        $status .= "LightwaveRF " if ($msg4 & 0x02); 
        $status .= "Mertik " if ($msg4 & 0x01); 
        $status .= "Visonic " if ($msg5 & 0x80); 
        $status .= "ATI " if ($msg5 & 0x40); 
        $status .= "OREGON " if ($msg5 & 0x20); 
        $status .= "KOPPLA " if ($msg5 & 0x10); 
        $status .= "HOMEEASY " if ($msg5 & 0x08); 
        $status .= "AC " if ($msg5 & 0x04); 
        $status .= "ARC " if ($msg5 & 0x02); 
        $status .= "X10 " if ($msg5 & 0x01); 
        my $hexline = unpack('H*', $buf);
        Log3 $name, 4, "TRX: Init status hexline='$hexline'";
        Log3 $name, 1, "TRX: Init status: '$status'";
      }
      # Since 1001
      if ($buf =~ m/140100(..)(..)(..)(..)(..)(..)(..)(..)(..)(..)(..)(..)(..)(..)(..)(..)(..)(..)/) {
        my $status = "";

        my $seqnbr = $1;
        my $cmnd = $2;
        my $msg1 = $3;
        my $msg2 = ord(pack('H*', $4));
        my $msg3 = ord(pack('H*', $5));
        my $msg4 = ord(pack('H*', $6));
        my $msg5 = ord(pack('H*', $7));
        my $msg6 = ord(pack('H*', $8));
        my $freq = { 
	        '50' => '310MHz',
	        '51' => '315MHz',
	        '52' => '433.92MHz receiver only',
	        '53' => '433.92MHz transceiver',
	        '55' => '868.00MHz',
	        '56' => '868.00MHz FSK',
	        '57' => '868.30MHz',
	        '58' => '868.30MHz FSK',
	        '59' => '868.35MHz',
	        '5a' => '868.35MHz FSK',
	        '5b' => '868.95MHz'
                 }->{$msg1} || 'unknown Mhz';
        $status .= $freq;
        $status .= ", " . sprintf "firmware=%d",$msg2+1000;
        $status .= ", protocols enabled: ";
        $status .= "undecoded " if ($msg3 & 0x80); 
        $status .= "RFU " if ($msg3 & 0x40); 
        $status .= "ByronSX " if ($msg3 & 0x20); 
        $status .= "RSL " if ($msg3 & 0x10); 
        $status .= "Lighting4 " if ($msg3 & 0x08); 
        $status .= "FineOffset/Viking " if ($msg3 & 0x04); 
        $status .= "Rubicson " if ($msg3 & 0x02); 
        $status .= "AE/Blyss " if ($msg3 & 0x01); 
        $status .= "BlindsT1/T2/T3/T4 " if ($msg4 & 0x80); 
        $status .= "BlindsT0  " if ($msg4 & 0x40); 
        $status .= "ProGuard " if ($msg4 & 0x20); 
        $status .= "FS20 " if ($msg4 & 0x10); 
        $status .= "LaCrosse " if ($msg4 & 0x08); 
        $status .= "Hideki " if ($msg4 & 0x04); 
        $status .= "LightwaveRF " if ($msg4 & 0x02); 
        $status .= "Mertik " if ($msg4 & 0x01); 
        $status .= "Visonic " if ($msg5 & 0x80); 
        $status .= "ATI " if ($msg5 & 0x40); 
        $status .= "OREGON " if ($msg5 & 0x20); 
        $status .= "KOPPLA " if ($msg5 & 0x10); 
        $status .= "HOMEEASY " if ($msg5 & 0x08); 
        $status .= "AC " if ($msg5 & 0x04); 
        $status .= "ARC " if ($msg5 & 0x02); 
        $status .= "X10 " if ($msg5 & 0x01); 
        $status .= "HomeComfort " if ($msg6 & 0x02); 
        $status .= "KEELOQ " if ($msg6 & 0x01); 
        my $hexline = unpack('H*', $buf);
        Log3 $name, 4, "TRX: Init status hexline='$hexline'";
        Log3 $name, 1, "TRX: Init status: '$status'";
      }
	}
  }

  # Reset the counter
  delete($hash->{XMIT_TIME});
  delete($hash->{NR_CMD_LAST_H});

  readingsSingleUpdate($hash, "state", "Initialized", 1);

  return undef;
}

#####################################
# This is a direct read for commands like get
sub
TRX_ReadAnswer($$)
{
  my ($hash, $arg) = @_;
  return ("No FD (dummy device?)", undef)
        if(!$hash || ($^O !~ /Win/ && !defined($hash->{FD})));
#  my $to = ($hash->{RA_Timeout} ? $hash->{RA_Timeout} : 3);
  my $to = ($hash->{RA_Timeout} ? $hash->{RA_Timeout} : 9);
  Log3 $hash, 4, "TRX_ReadAnswer arg:$arg";

  for(;;) {

    my $buf;
    if($^O =~ m/Win/ && $hash->{USBDev}) {
      $hash->{USBDev}->read_const_time($to*1000); # set timeout (ms)
      # Read anstatt input sonst funzt read_const_time nicht.
      $buf = $hash->{USBDev}->read(999);
      return ("Timeout reading answer for get $arg", undef)
        if(length($buf) == 0);

    } else {
      if(!$hash->{FD}) {
        Log3 $hash, 1, "TRX_ReadAnswer: device lost";
        return ("Device lost when reading answer for get $arg", undef);
      }

      my $rin = '';
      vec($rin, $hash->{FD}, 1) = 1;
      my $nfound = select($rin, undef, undef, $to);
      if($nfound < 0) {
        my $err = $!;
        Log3 $hash, 5, "TRX_ReadAnswer: nfound < 0 / err:$err";
        next if ($err == EAGAIN() || $err == EINTR() || $err == 0);
        DevIo_Disconnected($hash);
        return("TRX_ReadAnswer $arg: $err", undef);
      }

      if($nfound == 0){
        Log3 $hash, 5, "TRX_ReadAnswer: select timeout";
        return ("Timeout reading answer for get $arg", undef);
      }

      $buf = DevIo_SimpleRead($hash);
      if(!defined($buf)){
        Log3 $hash, 1,"TRX_ReadAnswer: no data read";
        return ("No data", undef);
      }
    }

    my $ret = TRX_Read($hash, $buf);
    if(defined($ret)){
      Log3 $hash, 4, "TRX_ReadAnswer for $arg: $ret";
      return (undef, $ret);
    }
  }
}

#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub
TRX_Read($@)
{
  my ($hash, $local) = @_;

  my $mybuf = (defined($local) ? $local : DevIo_SimpleRead($hash));
  return "" if(!defined($mybuf));
  my $name = $hash->{NAME};

  my $TRX_data = $hash->{PARTIAL};
  Log3 $name, 5, "TRX/RAW: $TRX_data/$mybuf";
  $TRX_data .= $mybuf;

  my $hexline = unpack('H*', $TRX_data);
  Log3 $name, 5, "TRX: TRX_Read '$hexline'";

  # first char as byte represents number of bytes of the message
  my $num_bytes = ord(substr($TRX_data,0,1));

  while(length($TRX_data) > $num_bytes) {
    # the buffer contains at least the number of bytes we need
    my $rmsg;
    $rmsg = substr($TRX_data, 0, $num_bytes+1);
    #my $hexline = unpack('H*', $rmsg);
    Log3 $name, 5, "TRX_Read rmsg '$hexline'";
    $TRX_data = substr($TRX_data, $num_bytes+1);;
    #$hexline = unpack('H*', $TRX_data);
    Log3 $name, 5, "TRX_Read TRX_data '$hexline'";
    #
    TRX_Parse($hash, $hash, $name, unpack('H*', $rmsg));
    $num_bytes = ord(substr($TRX_data,0,1));
  }
  Log3 $name, 5, "TRX_Read END";

  $hash->{PARTIAL} = $TRX_data;
}

sub
TRX_Parse($$$$)
{
  my ($hash, $iohash, $name, $rmsg) = @_;

  #Log3 $hash, 5, "TRX_Parse() '$rmsg'";

  if(!defined($hash->{STATE}) || $hash->{STATE} ne "Initialized"){
    Log3 $hash, 4,"TRX_Parse $rmsg: dongle not yet initialized";
    return;
  }

  my %addvals;
  # Parse only if message is different within 2 seconds 
  # (some Oregon sensors always sends the message twice, X10 security sensors even sends the message five times)
  if (("$last_rmsg" ne "$rmsg") || (time() - $last_time) > 1) { 
    Log3 $hash, 5, "TRX_Parse() '$rmsg'";
    %addvals = (RAWMSG => $rmsg);
    Dispatch($hash, $rmsg, \%addvals); 
    $hash->{"${name}_MSGCNT"}++;
    $hash->{"${name}_TIME"} = TimeNow();
    $hash->{RAWMSG} = $rmsg;
    readingsSingleUpdate($hash, "state", $hash->{READINGS}{state}{VAL}, 0);
  } else { 
    Log3 $hash, 5, "TRX_Parse() '$rmsg' dup";
  }

  $last_rmsg = $rmsg;
  $last_time = time();

}


#####################################
sub
TRX_Ready($)
{
  my ($hash) = @_;

  return DevIo_OpenDev($hash, 1, "TRX_DoInit")
                if($hash->{STATE} eq "disconnected");

  # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  return ($InBytes>0);
}

1;

=pod
=item device
=item summary    connection to RFXtrx433 USB RF transmitters
=item summary_DE Anbindung von RFXtrx433 USB Transceiver
=begin html

<a name="TRX"></a>
<h3>TRX</h3>
<ul>
  <table>
  This module is for the <a href="http://www.rfxcom.com">RFXCOM</a> RFXtrx433 USB based 433 Mhz RF transmitters.
This USB based transmitter is able to receive and transmit many protocols like Oregon Scientific weather sensors, X10 security and lighting devices, ARC ((address code wheels) HomeEasy, KlikAanKlikUit, ByeByeStandBy, Intertechno, ELRO,
AB600, Duewi, DomiaLite, COCO) and others. <br>
  Currently the following parser modules are implemented: <br>
    <ul>
    <li> 46_TRX_WEATHER.pm (see device <a href="#TRX">TRX</a>): Process messages Oregon Scientific weather sensors.
  See <a href="http://www.rfxcom.com/oregon.htm">http://www.rfxcom.com/oregon.htm</a> for a list of
  Oregon Scientific weather sensors that could be received by the RFXtrx433 tranmitter.
  Until now the following Oregon Scientific weather sensors have been tested successfully: BTHR918, BTHR918N, PCR800, RGR918, THGR228N, THGR810, THR128, THWR288A, WTGR800, WGR918. It will also work with many other Oregon sensors supported by RFXtrx433. Please give feedback if you use other sensors.<br>
    </li>
    <li> 46_TRX_SECURITY.pm (see device <a href="#TRX_SECURITY">TRX_SECURITY</a>): Receive X10, KD101 and Visonic security sensors.</li>
    <li> 46_TRX_LIGHT.pm (see device <a href="#RFXX10REC">RFXX10REC</a>): Process X10, ARC, ELRO AB400D, Waveman, Chacon EMW200, IMPULS, RisingSun, Philips SBC, AC, HomeEasy EU and ANSLUT lighting devices (switches and remote control). ARC is a protocol used by devices from HomeEasy, KlikAanKlikUit, ByeByeStandBy, Intertechno, ELRO, AB600, Duewi, DomiaLite and COCO with address code wheels. AC is the protocol used by different brands with units having a learning mode button:
KlikAanKlikUit, NEXA, CHACON, HomeEasy UK.</li>
    </ul>
  <br>
  Note: this module requires the Device::SerialPort or Win32::SerialPort module
  if the devices is connected via USB or a serial port.
  <br><br>
 <a name="TRXdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; TRX &lt;device&gt; [noinit] </code><br>
  </ul>
    <br>
    USB-connected:<br><ul>
      &lt;device&gt; specifies the USB port to communicate with the RFXtrx433 receiver.
      Normally on Linux the device will be named /dev/ttyUSBx, where x is a number.
      For example /dev/ttyUSB0. Please note that RFXtrx433 normally operates at 38400 baud. You may specify the baudrate used after the @ char.<br>
      <br>
      Example: <br>
    <code>define RFXTRXUSB TRX /dev/ttyUSB0@38400</code>
      <br>
     </ul>
    <br>
    Network-connected devices:
    <br><ul>
    &lt;device&gt; specifies the host:port of the device. E.g.
    192.168.1.5:10001
    </ul>
    <ul>
    noninit is optional and issues that the RFXtrx433 device should not be
    initialized. This is useful if you share a RFXtrx433 device via LAN. It is
    also useful for testing to simulate a RFXtrx433 receiver via netcat or via
    FHEM2FHEM.

      <br>
      <br>
      Example: <br>
    <code>define RFXTRXTCP TRX 192.168.1.5:10001</code>
    <br>
    <code>define RFXTRXTCP2 TRX 192.168.1.121:10001 noinit</code>
      <br>
    </ul>
    <br>
  </table>

  <a name="TRXattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#attrdummy">dummy</a></li><br>
    <li>longids<br>
        Comma separated list of device-types for TRX_WEATHER that should be handled using long IDs. This additional ID is a one byte hex string and is generated by the Oregon sensor when is it powered on. The value seems to be randomly generated. This has the advantage that you may use more than one Oregon sensor of the same type even if it has no switch to set a sensor id. For example the author uses two BTHR918N sensors at the same time. All have different deviceids. The drawback is that the deviceid changes after changing batteries. All devices listed as longids will get an additional one byte hex string appended to the device name.<br>
Default is to use no long IDs.
      <br><br>
      Examples:<PRE>
# Do not use any long IDs for any devices (this is default):
attr RFXCOMUSB longids 0
# Use long IDs for all devices:
attr RFXCOMUSB longids 1
# Use longids for BTHR918N devices.
# Will generate devices names like BTHR918N_f3.
attr RFXTRXUSB longids BTHR918N
# Use longids for TX3_T and TX3_H devices.
# Will generate devices names like TX3_T_07, TX3_T_01 ,TX3_H_07.
attr RFXTRXUSB longids TX3_T,TX3_H</PRE>
    </li><br>
   <li>rssi<br>
        1: enable RSSI logging, 0: disable RSSI logging<br>
Default is no RSSI logging.
      <br><br>
      Examples:<PRE>
# Do log rssi values (this is default):
attr RFXCOMUSB rssi 0
# Enable rssi logging for devices:
attr RFXCOMUSB rssi 1
    </li><br>
  </ul>
  <br>
</ul>

=end html
=cut
