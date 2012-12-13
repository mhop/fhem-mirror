##############################################
# $Id$
# Written by Matthias Gehre, M.Gehre@gmx.de, 2012
package main;

use strict;
use warnings;
require "10_MAX.pm";

our %msgId2Cmd;
our %msgCmd2Id;
our %device_types;

sub CUL_MAX_SendDeviceCmd($$);
sub CUL_MAX_Send(@);
sub CUL_MAX_BroadcastTime(@);
sub CUL_MAX_Set($@);
sub CUL_MAX_SendAck($$$);
sub CUL_MAX_SendTimeInformation(@);
sub CUL_MAX_Send(@);

my $pairmodeDuration = 30; #seconds

my $timeBroadcastInterval = 6*60*60; #= 6 hours, the same time that the cube uses

my $resendRetries = 0; #how often resend before giving up?

my $ackTimeout = 3; #seconds

sub
CUL_MAX_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^Z";
  $hash->{DefFn}     = "CUL_MAX_Define";
  $hash->{Clients}   = ":MAX:";
  my %mc = (
    "1:MAX" => "^MAX",
  );
  $hash->{MatchList} = \%mc;
  $hash->{UndefFn}   = "CUL_MAX_Undef";
  $hash->{ParseFn}   = "CUL_MAX_Parse";
  $hash->{SetFn}     = "CUL_MAX_Set";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ignore:0,1 " .
                        "showtime:1,0 loglevel:0,1,2,3,4,5,6";
}

#############################
sub
CUL_MAX_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> CUL_MAX <srdAddr>" if(@a<3);

  if(exists($modules{CUL_MAX}{defptr})) {
    Log 1, "There is already one CUL_MAX defined";
    return "There is already one CUL_MAX defined";
  }
  $modules{CUL_MAX}{defptr} = $hash;

  $hash->{addr} = $a[2];
  $hash->{STATE} = "Defined";
  $hash->{cnt} = 0;
  $hash->{pairmode} = 0;
  $hash->{retryCount} = 0;
  $hash->{devices} = ();
  AssignIoPort($hash);

  #This interface is shared with 00_MAXLAN.pm
  $hash->{SendDeviceCmd} = \&CUL_MAX_SendDeviceCmd;
  $hash->{Send} = \&CUL_MAX_Send;

  CUL_MAX_BroadcastTime($hash);
  return undef;
}

#####################################
sub
CUL_MAX_Undef($$)
{
  my ($hash, $name) = @_;
  RemoveInternalTimer($hash);
  delete($modules{CUL_MAX}{defptr});
  return undef;
}

sub
CUL_MAX_DisablePairmode($)
{
  my $hash = shift;
  $hash->{pairmode} = 0;
}

sub
CUL_MAX_Set($@)
{
  my ($hash, $device, @a) = @_;
  return "\"set MAXLAN\" needs at least one parameter" if(@a < 1);
  my ($setting, @args) = @a;

  if($setting eq "pairmode") {
    $hash->{pairmode} = 1;
    InternalTimer(gettimeofday()+$pairmodeDuration, "CUL_MAX_DisablePairmode", $hash, 0);

  } elsif($setting eq "broadcastTime") {
    CUL_MAX_BroadcastTime($hash, 1);

  } else {
    return "Unknown argument $setting, choose one of pairmode broadcastTime";
  }
  return undef;
}

#Array of all packet that we wait to be ack'ed
my @waitForAck = ();

sub
CUL_MAX_Parse($$)
{
  #Attention: there is a limit in the culfw firmware: It only receives messages shorter than 30 bytes (see rf_moritz.h)
  my ($hash, $rmsg) = @_;

  if(!exists($modules{CUL_MAX}{defptr})) {
      Log 5, "No CUL_MAX defined";
      return "UNDEFINED CULMAX0 CUL_MAX 123456";
  }
  my $shash = $modules{CUL_MAX}{defptr};

  $rmsg =~ m/Z(..)(..)(..)(..)(......)(......)(..)(.*)/;
  my ($len,$msgcnt,$msgFlag,$msgTypeRaw,$src,$dst,$groupid,$payload) = ($1,$2,$3,$4,$5,$6,$7,$8);
  $len = hex($len);
  if(2*$len+3 != length($rmsg)) { #+3 = +1 for 'Z' and +2 for len field in hex
    my $msg = "CUL_MAX_Parse: len mismatch";
    Log 1, $msg;
    return $msg;
  }

  $groupid = hex($groupid);

  #convert adresses to lower case
  $src = lc($src);
  $dst = lc($dst);
  my $msgType = exists($msgId2Cmd{$msgTypeRaw}) ? $msgId2Cmd{$msgTypeRaw} : $msgTypeRaw;
  Log 5, "CUL_MAX_Parse: len $len, msgcnt $msgcnt, msgflag $msgFlag, msgTypeRaw $msgType, src $src, dst $dst, groupid $groupid, payload $payload";
  my $isToMe = ($dst eq $shash->{addr}) ? 1 : 0; # $isToMe is true if that packet was directed at us

  if(exists($msgId2Cmd{$msgTypeRaw})) {

    if($msgType eq "Ack") {
      Dispatch($shash, "MAX,$isToMe,Ack,$src,$payload", {RAWMSG => $rmsg});

      return undef if(!$isToMe);

      my $i = 0;
      while ($i < @waitForAck) {
        my $packet = $waitForAck[$i];
        if($packet->{dest} eq $src and $packet->{cnt} == hex($msgcnt)) {
          Log 5, "Got matching ack";
          splice @waitForAck, $i, 1;
          return undef;
        } else {
          $i++;
        }
      }

    } elsif($msgType eq "TimeInformation") {
      if($isToMe) {
        #This is a request for TimeInformation send to us
        Log 5, "Got request for TimeInformation, sending it";
        CUL_MAX_SendTimeInformation($shash, $src);
      } else {
        my ($f1,$f2,$f3,$f4,$f5) = unpack("CCCCC",pack("H*",$payload));
        #For all fields but the month I'm quite sure
        my $year = $f1 + 2000;
        my $day  = $f2;
        my $hour = ($f3 & 0x1F);
        my $min = $f4 & 0x3F;
        my $sec = $f5 & 0x3F;
        my $month = (($f4 >> 6) << 2) | ($f5 >> 6); #this is just guessed
        my $unk1 = $f3 >> 5;
        my $unk2 = $f4 >> 6;
        my $unk3 = $f5 >> 6;
        #I guess the unk1,2,3 encode if we are in DST?
        Log 5, "CUL_MAX_Parse: Got TimeInformation: (in GMT) year $year, mon $month, day $day, hour $hour, min $min, sec $sec, unk ($unk1, $unk2, $unk3)";
      }
    } elsif($msgType eq "PairPing") {
      my ($unk1,$type,$unk2,$serial) = unpack("CCCa*",pack("H*",$payload));
      Log 5, "CUL_MAX_Parse: Got PairPing (dst $dst, pairmode $shash->{pairmode}), unk1 $unk1, type $type, unk2 $unk2, serial $serial";

      #There are two variants of PairPing:
      #1. It has a destination address of "000000" and can be paired to any device.
      #2. It is sent after changing batteries or repressing the pair button (without factory reset) and has a destination address of the last paired device. We can answer it with PairPong and even get an Ack, but it will still not be paired to us. A factory reset (originating from the last paired device) is needed first.
      if(($dst ne "000000") and !$isToMe) {
        Log 2, "Device want's to be re-paired to $dst, not to us";
        return undef;
      }

      if($shash->{pairmode}) {
        Log 3, "CUL_MAX_Parse: Pairing device $src of type $device_types{$type} with serial $serial";
        CUL_MAX_Send($shash, "PairPong", $src, "00");
        #TODO: wait for Ack
        Dispatch($shash, "MAX,$isToMe,define,$src,$device_types{$type},$serial,0,0", {RAWMSG => $rmsg});
        if($device_types{$type} eq "HeatingThermostat" or $device_types{$type} eq "WallMountedThermostat") {
          #This are the default values that a device has after factory reset or pairing
          Dispatch($shash, "MAX,$isToMe,ThermostatConfig,$src,17,21,80,5,0,30.5,4.5,12,15", {RAWMSG => $rmsg});
        }
        #TODO: send TimeInformation
      }

    } elsif($msgType ~~ ["ShutterContactState", "WallThermostatState", "ThermostatState"])  {
      Dispatch($shash, "MAX,$isToMe,$msgType,$src,$payload", {RAWMSG => $rmsg});
      #Only ShutterContactState needs ack
      if($msgType eq "ShutterContactState" and $dst eq $shash->{addr}) {
        CUL_MAX_SendAck($shash,$msgcnt,$src);
      }
    } else {
      Log 5, "Unhandled message $msgType";
    }
  } else {
    Log 2, "CUL_MAX_Parse: Got unhandled message type $msgTypeRaw";
  }
  return undef;
}

sub
CUL_MAX_SendAck($$$)
{
  my ($hash,$msgcnt,$dst) = @_;
  return CUL_MAX_Send($hash, "Ack", $dst, "00", "00", "00", $msgcnt);
}

#All inputs are hex strings, $cmd is one from %msgCmd2Id
sub
CUL_MAX_Send(@)
{
  # $cmd is one of
  my ($hash, $cmd, $dst, $payload, $flags, $groupId, $msgcnt) = @_;

  $flags = "00" if(!$flags);
  $groupId = "00" if(!defined($groupId));
  if(!defined($msgcnt)) {
    my $dhash = CUL_MAX_DeviceHash($dst);
    #replace message counter if not already set
    $dhash->{READINGS}{msgcnt}{VAL} += 1;
    $dhash->{READINGS}{msgcnt}{VAL} &= 0xFF;
    $msgcnt = sprintf("%02x",$dhash->{READINGS}{msgcnt}{VAL});
  }

  my $packet = $msgcnt . $flags . $msgCmd2Id{$cmd} . $hash->{addr} . $dst . $groupId . $payload;

  #prefix length in bytes
  $packet = sprintf("%02x",length($packet)/2) . $packet;

  #Send to CUL
  IOWrite($hash, "", "Zs". $packet);

  #Schedule checking for Ack
  return undef if($cmd eq "Ack"); #we don't get an Ack for an Ack
  my $timeout = gettimeofday()+$ackTimeout;
  $waitForAck[@waitForAck] = { "packet" => $packet,
                               "dest" => $dst,
                               "cnt" => hex($msgcnt),
                               "time" => $timeout,
                               "resends" => "0" };
  InternalTimer($timeout, "CUL_MAX_Resend", $hash, 0);
  return undef;
}

sub
CUL_MAX_DeviceHash($)
{
  my $addr = shift;
  return $modules{MAX}{defptr}{$addr};
}

sub
CUL_MAX_Resend($)
{
  my $hash = shift;

  my $resendTime = gettimeofday()+60; #some large time
  my $i = 0;
  while ($i < @waitForAck ) {
    my $packet = $waitForAck[$i];
    if( $packet->{time} <= gettimeofday() ) {
      Log 2, "CUL_MAX_Resend: Missing ack from $packet->{dest} for $packet->{packet}";
      if($packet->{resends}++ < $resendRetries) {
        #First resend is one second after original send, second resend it two seconds after first resend, etc
        $packet->{time} = gettimeofday()+$ackTimeout;
        IOWrite($hash, "", "Zs". $packet->{packet});
        readingsSingleUpdate($hash, "retryCount", ReadingsVal($hash->{NAME}, "retryCount", 0) + 1, 1);
      } else {
        Log 1, "CUL_MAX_Resend: Giving up on that packet";
        splice @waitForAck, $i, 1; #Remove from array
        readingsSingleUpdate($hash, "packetsLost", ReadingsVal($hash->{NAME}, "packetsLost", 0) + 1, 1);
        next
      }
    }
    $resendTime = $packet->{time} if($packet->{time} < $resendTime);
    $i++;
  }

  return if(!@waitForAck); #no need to recheck
  InternalTimer($resendTime, "CUL_MAX_Resend", $hash, 0);
}

sub
CUL_MAX_SendDeviceCmd($$)
{
  my ($hash,$payload) = @_;

  my $dstaddr = unpack("H6",substr($payload,6,3));
  my $dhash = CUL_MAX_DeviceHash($dstaddr);

  my $cnt = unpack("C",substr($payload,0,1));
  if($cnt == 0) {
    #replace message counter if not already set
    $cnt = ($dhash->{READINGS}{msgcnt}{VAL} + 1) & 0xFF;
    $dhash->{READINGS}{msgcnt}{VAL} = $cnt;
    substr($payload,0,1) = pack("C",$cnt);
  }
  #replace source address
  substr($payload,3,3) = pack("H6",$hash->{addr});
  #Prefix length byte
  $payload = pack("C",length($payload)) . $payload;

  $payload = unpack("H*",$payload); #convert to hex
  Log 5, "CUL_MAX_SendDeviceCmd: ". $payload;
  IOWrite($hash, "", "Zs". $payload);
  my $timeout = gettimeofday()+$ackTimeout;
  $waitForAck[@waitForAck] = { "packet" => $payload,
                               "dest" => $dstaddr,
                               "cnt" => $cnt,
                               "time" => $timeout,
                               "resends" => "0" };
  InternalTimer($timeout, "CUL_MAX_Resend", $hash, 0);
  return undef;
}

sub
CUL_MAX_GetTimeInformationPayload()
{
  my ($sec,$min,$hour,$day,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
  $mon += 1; #make month 1-based
  #month encoding is just guessed
  #perls localtime gives years since 1900, and we need years since 2000
  return unpack("H*",pack("CCCCC", $year - 100, $day, $hour, $min | (($mon & 0x0C) << 4), $sec | (($mon & 0x03) << 6)));
}

sub
CUL_MAX_SendTimeInformation(@)
{
  my ($hash,$addr,$payload) = @_;
  $payload = CUL_MAX_GetTimeInformationPayload() if(!defined($payload));
  Log 5, "broadcast time to $addr";
  CUL_MAX_Send($hash, "TimeInformation", $addr, $payload, "03");
}

sub
CUL_MAX_SendTimeInformationSender($)
{
  my $args = shift;
  my ($hash,$addr,$payload) = @{$args};
  CUL_MAX_SendTimeInformation($hash, $addr, $payload);
}

sub
CUL_MAX_BroadcastTime(@)
{
  my ($hash,$manual) = @_;
  my $payload = CUL_MAX_GetTimeInformationPayload();
  Log 5, "CUL_MAX_BroadcastTime: payload $payload";
  my $i = 1;
  foreach my $addr (keys %{$modules{MAX}{defptr}}) {
    my $dhash = $modules{MAX}{defptr}{$addr};
    if(exists($dhash->{IODev}) && $dhash->{IODev} == $hash) {
      #We queue it at different times and do not send directly, because
      #sending them all in a row makes us not see the Acks
      InternalTimer(gettimeofday()+3*$i++, "CUL_MAX_SendTimeInformationSender", [$hash, $addr, $payload], 0);
    }
  }

  InternalTimer(gettimeofday()+$timeBroadcastInterval, "CUL_MAX_BroadcastTime", $hash, 0) unless(defined($manual));
}

1;


=pod
=begin html

<a name="CUL_MAX"></a>
<h3>CUL_MAX</h3>
<ul>
  The CUL_MAX module interprets MAX! messages received by the CUL. It will be automatically created by autocreate, just make sure
  that you set the right rfmode like <code>attr CUL0 rfmode MAX</code>.<br>
  <br><br>

  <a name="CUL_MAXdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; CUL_MAX &lt;addr&gt;</code>
      <br><br>

      Defines an CUL_MAX device of type &lt;type&gt; and rf address &lt;addr&gt. The rf address
      must not be in use by any other MAX device.
  </ul>
  <br>

  <a name="CUL_MAXset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="CUL_MAXget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="CUL_MAXattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#ignore">ignore</a></li><br>
    <li><a href="#do_not_notify">do_not_notify</a></li><br>
    <li><a href="#showtime">showtime</a></li><br>
    <li><a href="#loglevel">loglevel</a></li><br>
  </ul>
  <br>

  <a name="CUL_MAXevents"></a>
  <b>Generated events:</b>
  <ul>N/A</ul>
  <br>

</ul>


=end html
=cut
