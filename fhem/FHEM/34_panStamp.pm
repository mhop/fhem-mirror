
# $Id$

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

sub panStamp_Attr(@);
sub panStamp_Clear($);
sub panStamp_HandleWriteQueue($);
sub panStamp_Parse($$$$);
sub panStamp_Read($);
sub panStamp_ReadAnswer($$$$);
sub panStamp_Ready($);
sub panStamp_Write($$$);

sub panStamp_SimpleWrite(@);

my $clientsPanStamp = ":SWAP:";

my %matchListSWAP = (
    "1:SWAP" => "^.*",
);

sub
panStamp_Initialize($)
{
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

# Provider
  $hash->{ReadFn}  = "panStamp_Read";
  $hash->{WriteFn} = "panStamp_Write";
  $hash->{ReadyFn} = "panStamp_Ready";

# Normal devices
  $hash->{DefFn}   = "panStamp_Define";
  $hash->{FingerprintFn}   = "panStamp_Fingerprint";
  $hash->{UndefFn} = "panStamp_Undef";
  #$hash->{GetFn}   = "panStamp_Get";
  $hash->{SetFn}   = "panStamp_Set";
  #$hash->{AttrFn}  = "panStamp_Attr";
  #$hash->{AttrList}= "";

  $hash->{ShutdownFn} = "panStamp_Shutdown";
}
sub
panStamp_Fingerprint($$)
{
}

#####################################
sub
panStamp_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a < 3 || @a > 6) {
    my $msg = "wrong syntax: define <name> panStamp {devicename[\@baudrate] ".
                        "| devicename\@directio} [<address> [<channel> [<syncword>]]]";
    Log3 undef, 2, $msg;
    return $msg;
  }

  my $address = $a[3];
  $address = "01" if( !defined($address) );
  my $channel = $a[4];
  $channel = "00" if( !defined($channel) );
  my $syncword = $a[5];
  $syncword = 'B547' if( !defined($syncword) );

  return "$address is not a 1 byte hex value" if( $address !~ /^[\da-f]{2}$/i );
  return "$address is not an allowed address" if( $address eq "00" );
  return "$channel is not a 1 byte hex value" if( $channel !~ /^[\da-f]{2}$/i );
  return "$syncword is not a 2 byte hex value" if( $syncword !~ /^[\da-f]{4}$/i );

  DevIo_CloseDev($hash);

  my $name = $a[0];

  my $dev = $a[2];
  $dev .= "\@38400" if( $dev !~ m/\@/ );

  $hash->{address} = uc($address);
  $hash->{channel} = uc($channel);
  $hash->{syncword} = uc($syncword);

  $hash->{Clients} = $clientsPanStamp;
  $hash->{MatchList} = \%matchListSWAP;

  $hash->{DeviceName} = $dev;

  $hash->{nonce} = 0;

  my $ret = DevIo_OpenDev($hash, 0, "panStamp_DoInit");
  return $ret;
}

#####################################
sub
panStamp_Undef($$)
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

  panStamp_Shutdown($hash);
  DevIo_CloseDev($hash);
  return undef;
}

#####################################
sub
panStamp_Shutdown($)
{
  my ($hash) = @_;
  ###panStamp_SimpleWrite($hash, "X00");
  return undef;
}

#####################################
sub
panStamp_Set($@)
{
  my ($hash, @a) = @_;

  my $name = shift @a;
  my $cmd = shift @a;
  my $arg = join("", @a);

  my $list = "discover raw:noArg";
  return $list if( $cmd eq '?' );

  if($cmd eq "raw") {
    return "\"set panStamp $cmd\" needs exactly one parameter" if(@_ != 4);
    return "Expecting a even length hex number" if((length($arg)&1) == 1 || $arg !~ m/^[\dA-F]{12,}$/ );
    Log3 $name, 4, "set $name $cmd $arg";
    panStamp_SimpleWrite($hash, $arg);

  } elsif($cmd eq "discover") {
    Log3 $name, 4, "set $name $cmd";
    panStamp_SimpleWrite($hash, "00".$hash->{address}."0000010000" );

  } else {
    return "Unknown argument $cmd, choose one of ".$list;
  }

  return undef;
}

#####################################
sub
panStamp_Get($@)
{
  my ($hash, @a) = @_;

  #$hash->{READINGS}{$a[1]}{VAL} = $msg;
  $hash->{READINGS}{$a[1]}{TIME} = TimeNow();

  #return "$a[0] $a[1] => $msg";
}

sub
panStamp_Clear($)
{
  my $hash = shift;

  # Clear the pipe
  $hash->{RA_Timeout} = 0.1;
  for(;;) {
    my ($err, undef) = panStamp_ReadAnswer($hash, "Clear", 0, undef);
    last if($err && $err =~ m/^Timeout/);
  }
  delete($hash->{RA_Timeout});
}

#####################################
sub
panStamp_DoInit($)
{
  my $hash = shift;
  my $name = $hash->{NAME};
  my $err;
  my $msg = undef;

  my $val;

  panStamp_Clear($hash);
  panStamp_ReadAnswer($hash, "ready?", 0, undef);
  panStamp_SimpleWrite($hash, "+++", 1 );
  sleep 2;
  panStamp_ReadAnswer($hash, "cmd mode?", 0, undef);
  panStamp_SimpleWrite($hash, "ATHV?" );
  ($err, $val) = panStamp_ReadAnswer($hash, "HW Version", 0, undef);
  return "$name: $err" if($err && ($err !~ m/Timeout/));
  $hash->{HWVersion} = $val;

  panStamp_SimpleWrite($hash, "ATFV?" );
  ($err, $val) = panStamp_ReadAnswer($hash, "FW Version", 0, undef);
  return "$name: $err" if($err && ($err !~ m/Timeout/));
  $hash->{FWVersion} = $val;

  panStamp_SimpleWrite($hash, "ATSW=$hash->{syncword}" );
  ($err, $val) = panStamp_ReadAnswer($hash, "sync word", 0, undef);
  return "$name: $err" if($err && ($err !~ m/Timeout/));

  panStamp_SimpleWrite($hash, "ATSW?" );
  ($err, $val) = panStamp_ReadAnswer($hash, "sync word", 0, undef);
  return "$name: $err" if($err && ($err !~ m/Timeout/));
  $hash->{syncword} = sprintf( "%04s", $val );

  panStamp_SimpleWrite($hash, "ATCH=$hash->{channel}" );
  ($err, $val) = panStamp_ReadAnswer($hash, "channel", 0, undef);
  return "$name: $err" if($err && ($err !~ m/Timeout/));

  panStamp_SimpleWrite($hash, "ATCH?" );
  ($err, $val) = panStamp_ReadAnswer($hash, "channel", 0, undef);
  return "$name: $err" if($err && ($err !~ m/Timeout/));
  $hash->{channel} = sprintf( "%02s", $val);

  panStamp_SimpleWrite($hash, "ATDA=$hash->{address}" );
  ($err, $val) = panStamp_ReadAnswer($hash, "address", 0, undef);
  return "$name: $err" if($err && ($err !~ m/Timeout/));

  panStamp_SimpleWrite($hash, "ATDA?" );
  ($err, $val) = panStamp_ReadAnswer($hash, "address", 0, undef);
  return "$name: $err" if($err && ($err !~ m/Timeout/));
  $hash->{address} = sprintf( "%02s", $val);

  panStamp_SimpleWrite($hash, "ATO" );
  panStamp_ReadAnswer($hash, "data mode?", 0, undef);

  panStamp_SimpleWrite($hash, "00".$hash->{address}."0000010000" );

  $hash->{STATE} = "Initialized";

  # Reset the counter
  delete($hash->{XMIT_TIME});
  delete($hash->{NR_CMD_LAST_H});
  return undef;
}

#####################################
# This is a direct read for commands like get
# Anydata is used by read file to get the filesize
sub
panStamp_ReadAnswer($$$$)
{
  my ($hash, $arg, $anydata, $regexp) = @_;
  my $type = $hash->{TYPE};

  return ("No FD", undef)
        if(!$hash || ($^O !~ /Win/ && !defined($hash->{FD})));

  my ($mpandata, $rin) = ("", '');
  my $buf;
  my $to = 3;                                         # 3 seconds timeout
  $to = $hash->{RA_Timeout} if($hash->{RA_Timeout});  # ...or less
  for(;;) {

    if($^O =~ m/Win/ && $hash->{USBDev}) {
      $hash->{USBDev}->read_const_time($to*1000); # set timeout (ms)
      # Read anstatt input sonst funzt read_const_time nicht.
      $buf = $hash->{USBDev}->read(999);
      return ("Timeout reading answer for get $arg", undef)
        if(length($buf) == 0);

    } else {
      return ("Device lost when reading answer for get $arg", undef)
        if(!$hash->{FD});

      vec($rin, $hash->{FD}, 1) = 1;
      my $nfound = select($rin, undef, undef, $to);
      if($nfound < 0) {
        next if ($! == EAGAIN() || $! == EINTR() || $! == 0);
        my $err = $!;
        DevIo_Disconnected($hash);
        return("panStamp_ReadAnswer $arg: $err", undef);
      }
      return ("Timeout reading answer for get $arg", undef)
        if($nfound == 0);
      $buf = DevIo_SimpleRead($hash);
      return ("No data", undef) if(!defined($buf));

    }

    if($buf) {
      Log3 $hash->{NAME}, 5, "panStamp/RAW (ReadAnswer): $buf";
      $mpandata .= $buf;
    }

    chop($mpandata);
    chop($mpandata);

    return (undef, $mpandata)
  }

}

#####################################
# Check if the 1% limit is reached and trigger notifies
sub
panStamp_XmitLimitCheck($$)
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

  if(@b > 163) {          # 163 comes from fs20. todo: verify if correct for panstamp modulation

    my $name = $hash->{NAME};
    Log3 $name, 2, "panStamp TRANSMIT LIMIT EXCEEDED";
    DoTrigger($name, "TRANSMIT LIMIT EXCEEDED");

  } else {

    push(@b, $now);

  }
  $hash->{XMIT_TIME} = \@b;
  $hash->{NR_CMD_LAST_H} = int(@b);
}

#####################################
sub
panStamp_Write($$$)
{
  my ($hash,$addr,$msg) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, "$name sending $msg";

  my $bstring = $addr.$hash->{address}.$msg;

  panStamp_AddQueue($hash, $bstring);
  #panStamp_SimpleWrite($hash, $bstring);
}

sub
panStamp_SendFromQueue($$)
{
  my ($hash, $bstring) = @_;
  my $name = $hash->{NAME};
  my $to = 0.05;

  if($bstring ne "") {
    my $sp = AttrVal($name, "sendpool", undef);
    if($sp) {   # Is one of the panStamp-fellows sending data?
      my @fellows = split(",", $sp);
      foreach my $f (@fellows) {
        if($f ne $name &&
           $defs{$f} &&
           $defs{$f}{QUEUE} &&
           $defs{$f}{QUEUE}->[0] ne "")
          {
            unshift(@{$hash->{QUEUE}}, "");
            InternalTimer(gettimeofday()+$to, "panStamp_HandleWriteQueue", $hash, 1);
            return;
          }
      }
    }

    panStamp_XmitLimitCheck($hash,$bstring);
    panStamp_SimpleWrite($hash, $bstring);
  }

  InternalTimer(gettimeofday()+$to, "panStamp_HandleWriteQueue", $hash, 1);
}

sub
panStamp_AddQueue($$)
{
  my ($hash, $bstring) = @_;
  if(!$hash->{QUEUE}) {
    $hash->{QUEUE} = [ $bstring ];
    panStamp_SendFromQueue($hash, $bstring);

  } else {
    push(@{$hash->{QUEUE}}, $bstring);
  }
}

#####################################
sub
panStamp_HandleWriteQueue($)
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
    if($bstring eq "") {
      panStamp_HandleWriteQueue($hash);
    } else {
      panStamp_SendFromQueue($hash, $bstring);
    }
  }
}

#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub
panStamp_Read($)
{
  my ($hash) = @_;

  my $buf = DevIo_SimpleRead($hash);
  return "" if(!defined($buf));

  my $name = $hash->{NAME};

  my $pandata = $hash->{PARTIAL};
  Log3 $name, 5, "panStamp/RAW: $pandata/$buf";
  $pandata .= $buf;

  while($pandata =~ m/\n/) {
    my $rmsg;
    ($rmsg,$pandata) = split("\n", $pandata, 2);
    $rmsg =~ s/\r//;
    panStamp_Parse($hash, $hash, $name, $rmsg) if($rmsg);
  }
  $hash->{PARTIAL} = $pandata;
}

sub
panStamp_Parse($$$$)
{
  my ($hash, $iohash, $name, $rmsg) = @_;

  my $dmsg = $rmsg;
  my $l = length($dmsg);
  my $rssi = hex(substr($dmsg, 1, 2));
  $rssi = ($rssi>=128 ? (($rssi-256)/2-74) : ($rssi/2-74));
  my $lqi = hex(substr($dmsg, 3, 2));
  $dmsg = substr($dmsg, 6, $l-6);
  Log3 $name, 5, "$name: $dmsg $rssi $lqi";

  next if(!$dmsg || length($dmsg) < 1);            # Bogus messages

  $hash->{"${name}_MSGCNT"}++;
  $hash->{"${name}_TIME"} = TimeNow();
  $hash->{RAWMSG} = $rmsg;
  my %addvals = (RAWMSG => $rmsg);
  if(defined($rssi)) {
    $hash->{RSSI} = $rssi;
    $addvals{RSSI} = $rssi;
  }
  if(defined($lqi)) {
    $hash->{LQI} = $lqi;
    $addvals{LQI} = $lqi;
  }
  Dispatch($hash, $dmsg, \%addvals);
}


#####################################
sub
panStamp_Ready($)
{
  my ($hash) = @_;

  return DevIo_OpenDev($hash, 1, "panStamp_DoInit")
                if($hash->{STATE} eq "disconnected");

  # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags);
  if($po) {
    ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  }
  return ($InBytes && $InBytes>0);
}

########################
sub
panStamp_SimpleWrite(@)
{
  my ($hash, $msg, $nocr) = @_;
  return if(!$hash);

  my $name = $hash->{NAME};
  Log3 $name, 5, "SW: $msg";

  $msg .= "\r" unless($nocr);

  $hash->{USBDev}->write($msg)    if($hash->{USBDev});
  syswrite($hash->{DIODev}, $msg) if($hash->{DIODev});

  # Some linux installations are broken with 0.001, T01 returns no answer
  select(undef, undef, undef, 0.01);
}

sub
panStamp_Attr(@)
{
  my @a = @_;

  return undef;
}

1;

=pod
=begin html

<a name="panStamp"></a>
<h3>panStamp</h3>
<ul>
  The panStamp is a family of RF devices sold by <a href="http://www.panstamp.com">panstamp.com</a>.

  It is possible to attach more than one device in order to get better
  reception, fhem will filter out duplicate messages.<br><br>

  This module provides the IODevice for the <a href="#SWAP">SWAP</a> modules that implement the SWAP protocoll
  to communicate with the individual moths in a panStamp network.<br><br>

  Note: currently only panSticks are know to work. The panStamp shield for a Rasperry Pi is untested.
  <br><br>

  Note: this module may require the Device::SerialPort or Win32::SerialPort
  module if you attach the device via USB and the OS sets strange default
  parameters for serial devices.

  <br><br>

  <a name="panStamp_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; panStamp &lt;device&gt; [&lt;address&gt; [&lt;channel&gt; [&lt;syncword&gt;]]]</code> <br>
    <br>
    USB-connected devices:<br><ul>
      &lt;device&gt; specifies the serial port to communicate with the panStamp.
      The name of the serial-device depends on your distribution, under
      linux the cdc_acm kernel module is responsible, and usually a
      /dev/ttyACM0 device will be created. If your distribution does not have a
      cdc_acm module, you can force usbserial to handle the panStamp by the
      following command:<ul>modprobe usbserial vendor=0x0403
      product=0x6001</ul>In this case the device is most probably
      /dev/ttyUSB0.<br><br>

      You can also specify a baudrate if the device name contains the @
      character, e.g.: /dev/ttyACM0@38400<br><br>

      If the baudrate is "directio" (e.g.: /dev/ttyACM0@directio), then the
      perl module Device::SerialPort is not needed, and fhem opens the device
      with simple file io. This might work if the operating system uses sane
      defaults for the serial parameters, e.g. some Linux distributions and
      OSX.  <br><br>

    </ul>
    <br>
    The address is a 2 digit hex number to identify the moth in the panStamp network. The default is 01.<br>
    The channel is a 2 digit hex number to define the channel. the default is 00.<br>
    The syncword is a 4 digit hex number to identify the panStamp network. The default is B547.<br><br>

    Uppon initialization a broadcast message is send to the panStamp network to try to
    autodetect and autocreate all listening SWAP devices (i.e. all devices not in power down mode).
  </ul>
  <br>

  <a name="panStamp_Set"></a>
  <b>Set</b>
  <ul>
    <li>raw data<br>
        send raw data to the panStamp to be transmitted over the RF link.
        </li><br>
  </ul>

  <a name="panStamp_Get"></a>
  <b>Get</b>
  <ul>
  </ul>

  <a name="panStamp_Attr"></a>
  <b>Attributes</b>
  <ul>
  </ul>
  <br>
</ul>

=end html
=cut
