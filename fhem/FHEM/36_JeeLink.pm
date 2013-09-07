
# $Id$

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

sub JeeLink_Attr(@);
sub JeeLink_Clear($);
sub JeeLink_HandleWriteQueue($);
sub JeeLink_Parse($$$$);
sub JeeLink_Read($);
sub JeeLink_ReadAnswer($$$$);
sub JeeLink_Ready($);
sub JeeLink_Write($$);

sub JeeLink_SimpleWrite(@);

my $clientsJeeLink = ":PCA301:EC3000:RoomNode:";

my %matchListPCA301 = (
    "1:PCA301" => "^\\S+\\s+24",
    "2:EC3000" => "^\\S+\\s+22",
    "3:RoomNode" => "^\\S+\\s+11",
);

sub
JeeLink_Initialize($)
{
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

# Provider
  $hash->{ReadFn}  = "JeeLink_Read";
  $hash->{WriteFn} = "JeeLink_Write";
  $hash->{ReadyFn} = "JeeLink_Ready";

# Normal devices
  $hash->{DefFn}   = "JeeLink_Define";
  $hash->{FingerprintFn}   = "JeeLink_Fingerprint";
  $hash->{UndefFn} = "JeeLink_Undef";
  $hash->{GetFn}   = "JeeLink_Get";
  $hash->{SetFn}   = "JeeLink_Set";
  #$hash->{AttrFn}  = "JeeLink_Attr";
  #$hash->{AttrList}= "";

  $hash->{ShutdownFn} = "JeeLink_Shutdown";
}
sub
JeeLink_Fingerprint($$)
{
}

#####################################
sub
JeeLink_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a != 3) {
    my $msg = "wrong syntax: define <name> JeeLink {devicename[\@baudrate] ".
                        "| devicename\@directio}";
    Log3 undef, 2, $msg;
    return $msg;
  }

  DevIo_CloseDev($hash);

  my $name = $a[0];

  my $dev = $a[2];
  $dev .= "\@57600" if( $dev !~ m/\@/ );

  $hash->{Clients} = $clientsJeeLink;
  $hash->{MatchList} = \%matchListPCA301;

  $hash->{DeviceName} = $dev;

  $hash->{nonce} = 0;

  my $ret = DevIo_OpenDev($hash, 0, "JeeLink_DoInit");
  return $ret;
}

#####################################
sub
JeeLink_Undef($$)
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

  JeeLink_Shutdown($hash);
  DevIo_CloseDev($hash);
  return undef;
}

#####################################
sub
JeeLink_Shutdown($)
{
  my ($hash) = @_;
  ###JeeLink_SimpleWrite($hash, "X00");
  return undef;
}

#####################################
sub
JeeLink_Set($@)
{
  my ($hash, @a) = @_;

  my $name = shift @a;
  my $cmd = shift @a;
  my $arg = join("", @a);

  my $list = "raw:noArg";
  return $list if( $cmd eq '?' );

  if($cmd eq "raw") {
    #return "\"set JeeLink $cmd\" needs exactly one parameter" if(@_ != 4);
    #return "Expecting a even length hex number" if((length($arg)&1) == 1 || $arg !~ m/^[\dA-F]{12,}$/ );
    Log3 $name, 4, "set $name $cmd $arg";
    JeeLink_SimpleWrite($hash, $arg);

  } else {
    return "Unknown argument $cmd, choose one of ".$list;
  }

  return undef;
}

#####################################
sub
JeeLink_Get($@)
{
  my ($hash, $name, $cmd ) = @_;

  my $list = "devices:noArg initJeeLink:noArg";

  if( $cmd eq "devices" ) {
    JeeLink_SimpleWrite($hash, "l");
  } elsif( $cmd eq "initJeeLink" ) {
    JeeLink_SimpleWrite($hash, "0c");
    JeeLink_SimpleWrite($hash, "2c");
  } else {
    return "Unknown argument $cmd, choose one of ".$list;
  }

  return undef;
}

sub
JeeLink_Clear($)
{
  my $hash = shift;

  # Clear the pipe
  $hash->{RA_Timeout} = 0.1;
  for(;;) {
    my ($err, undef) = JeeLink_ReadAnswer($hash, "Clear", 0, undef);
    last if($err && $err =~ m/^Timeout/);
  }
  delete($hash->{RA_Timeout});
}

#####################################
sub
JeeLink_DoInit($)
{
  my $hash = shift;
  my $name = $hash->{NAME};
  my $err;
  my $msg = undef;

  my $val;

  #JeeLink_Clear($hash);

  JeeLink_SimpleWrite($hash, "1a" ); # led on
  JeeLink_SimpleWrite($hash, "1q" ); # quiet mode
  JeeLink_SimpleWrite($hash, "0x" ); # hex mode
  JeeLink_SimpleWrite($hash, "0a" ); # led off

  JeeLink_SimpleWrite($hash, "l");   # list known devices

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
JeeLink_ReadAnswer($$$$)
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
        return("JeeLink_ReadAnswer $arg: $err", undef);
      }
      return ("Timeout reading answer for get $arg", undef)
        if($nfound == 0);
      $buf = DevIo_SimpleRead($hash);
      return ("No data", undef) if(!defined($buf));

    }

    if($buf) {
      Log3 $hash->{NAME}, 5, "JeeLink/RAW (ReadAnswer): $buf";
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
JeeLink_XmitLimitCheck($$)
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

  if(@b > 163) {          # 163 comes from fs20. todo: verify if correct for JeeLink modulation

    my $name = $hash->{NAME};
    Log3 $name, 2, "JeeLink TRANSMIT LIMIT EXCEEDED";
    DoTrigger($name, "TRANSMIT LIMIT EXCEEDED");

  } else {

    push(@b, $now);

  }
  $hash->{XMIT_TIME} = \@b;
  $hash->{NR_CMD_LAST_H} = int(@b);
}

#####################################
sub
JeeLink_Write($$)
{
  my ($hash,$msg) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, "$name sending $msg";

  JeeLink_AddQueue($hash, $msg);
  #JeeLink_SimpleWrite($hash, $msg);
}

sub
JeeLink_SendFromQueue($$)
{
  my ($hash, $bstring) = @_;
  my $name = $hash->{NAME};
  my $to = 0.05;

  if($bstring ne "") {
    my $sp = AttrVal($name, "sendpool", undef);
    if($sp) {   # Is one of the JeeLink-fellows sending data?
      my @fellows = split(",", $sp);
      foreach my $f (@fellows) {
        if($f ne $name &&
           $defs{$f} &&
           $defs{$f}{QUEUE} &&
           $defs{$f}{QUEUE}->[0] ne "")
          {
            unshift(@{$hash->{QUEUE}}, "");
            InternalTimer(gettimeofday()+$to, "JeeLink_HandleWriteQueue", $hash, 1);
            return;
          }
      }
    }

    JeeLink_XmitLimitCheck($hash,$bstring);
    JeeLink_SimpleWrite($hash, $bstring);
  }

  InternalTimer(gettimeofday()+$to, "JeeLink_HandleWriteQueue", $hash, 1);
}

sub
JeeLink_AddQueue($$)
{
  my ($hash, $bstring) = @_;
  if(!$hash->{QUEUE}) {
    $hash->{QUEUE} = [ $bstring ];
    JeeLink_SendFromQueue($hash, $bstring);

  } else {
    push(@{$hash->{QUEUE}}, $bstring);
  }
}

#####################################
sub
JeeLink_HandleWriteQueue($)
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
      JeeLink_HandleWriteQueue($hash);
    } else {
      JeeLink_SendFromQueue($hash, $bstring);
    }
  }
}

#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub
JeeLink_Read($)
{
  my ($hash) = @_;

  my $buf = DevIo_SimpleRead($hash);
  return "" if(!defined($buf));

  my $name = $hash->{NAME};

  my $pandata = $hash->{PARTIAL};
  Log3 $name, 5, "JeeLink/RAW: $pandata/$buf";
  $pandata .= $buf;

  while($pandata =~ m/\n/) {
    my $rmsg;
    ($rmsg,$pandata) = split("\n", $pandata, 2);
    $rmsg =~ s/\r//;
    JeeLink_Parse($hash, $hash, $name, $rmsg) if($rmsg);
  }
  $hash->{PARTIAL} = $pandata;
}

sub
JeeLink_Parse($$$$)
{
  my ($hash, $iohash, $name, $rmsg) = @_;

  my $dmsg = $rmsg;
  #my $l = length($dmsg);
  my $rssi;
  #my $rssi = hex(substr($dmsg, 1, 2));
  #$rssi = ($rssi>=128 ? (($rssi-256)/2-74) : ($rssi/2-74));
  my $lqi;
  #my $lqi = hex(substr($dmsg, 3, 2));
  #$dmsg = substr($dmsg, 6, $l-6);
  #Log3, $name, 5, "$name: $dmsg $rssi $lqi";

  next if(!$dmsg || length($dmsg) < 1);            # Bogus messages
  return if($dmsg =~ m/^Available commands:/ );    # ignore startup messages
  return if($dmsg =~ m/^  .* - / );                # ignore startup messages
  return if($dmsg =~ m/^-> ack/ );                 # ignore send ack

  if($dmsg =~ m/^\[pcaSerial/ ) {
    $hash->{VERSION} = $dmsg;
    return;
  }

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

  if( $rmsg =~ m/(\S* )(\d+)(.*)/ ) {
    my $node = $2 & 0x1F;              #mask HDR -> it is handled by the skech
    $dmsg = $1.$node.$3;
  }

  Dispatch($hash, $dmsg, \%addvals);
}


#####################################
sub
JeeLink_Ready($)
{
  my ($hash) = @_;

  return DevIo_OpenDev($hash, 1, "JeeLink_DoInit")
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
JeeLink_SimpleWrite(@)
{
  my ($hash, $msg, $nocr) = @_;
  return if(!$hash);

  my $name = $hash->{NAME};
  Log3 $name, 5, "SW: $msg";

  $msg .= "\n" unless($nocr);

  $hash->{USBDev}->write($msg)    if($hash->{USBDev});
  syswrite($hash->{DIODev}, $msg) if($hash->{DIODev});

  # Some linux installations are broken with 0.001, T01 returns no answer
  select(undef, undef, undef, 0.01);
}

sub
JeeLink_Attr(@)
{
  my @a = @_;

  return undef;
}

1;

=pod
=begin html

<a name="JeeLink"></a>
<h3>JeeLink</h3>
<ul>
  The JeeLink is a family of RF devices sold by <a href="http://jeelabs.com">jeelabs.com</a>.

  It is possible to attach more than one device in order to get better
  reception, fhem will filter out duplicate messages.<br><br>

  This module provides the IODevice for the <a href="#PCA301">PCA301</a> modules that implements the PCA301 protocoll.<br><br>
  In the future other RF devices like the Energy Controll 3000, JeeLabs room nodes, fs20 or kaku devices will be supportet.<br><br>

  Note: this module may require the Device::SerialPort or Win32::SerialPort
  module if you attach the device via USB and the OS sets strange default
  parameters for serial devices.

  <br><br>

  <a name="JeeLink_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; JeeLink &lt;device&gt;</code> <br>
    <br>
    USB-connected devices:<br><ul>
      &lt;device&gt; specifies the serial port to communicate with the JeeLink.
      The name of the serial-device depends on your distribution, under
      linux the cdc_acm kernel module is responsible, and usually a
      /dev/ttyACM0 device will be created. If your distribution does not have a
      cdc_acm module, you can force usbserial to handle the JeeLink by the
      following command:<ul>modprobe usbserial vendor=0x0403
      product=0x6001</ul>In this case the device is most probably
      /dev/ttyUSB0.<br><br>

      You can also specify a baudrate if the device name contains the @
      character, e.g.: /dev/ttyACM0@57600<br><br>

      If the baudrate is "directio" (e.g.: /dev/ttyACM0@directio), then the
      perl module Device::SerialPort is not needed, and fhem opens the device
      with simple file io. This might work if the operating system uses sane
      defaults for the serial parameters, e.g. some Linux distributions and
      OSX.  <br><br>

    </ul>
    <br>
  </ul>
  <br>

  <a name="JeeLink_Set"></a>
  <b>Set</b>
  <ul>
    <li>raw &lt;datar&gt;<br>
        send &lt;data&gt; as a raw message to the JeeLink to be transmitted over the RF link.
        </li><br>
  </ul>

  <a name="JeeLink_Get"></a>
  <b>Get</b>
  <ul>
  </ul>

  <a name="JeeLink_Attr"></a>
  <b>Attributes</b>
  <ul>
  </ul>
  <br>
</ul>

=end html
=cut
