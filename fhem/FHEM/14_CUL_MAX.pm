##############################################
# $Id$
# Written by Matthias Gehre, M.Gehre@gmx.de, 2012-2013
package main;

use v5.10.1;

use strict;
use warnings;
use MaxCommon;
use POSIX;

sub CUL_MAX_BroadcastTime(@);
sub CUL_MAX_Set($@);
sub CUL_MAX_SendTimeInformation(@);
sub CUL_MAX_GetTimeInformationPayload();
sub CUL_MAX_Send(@);
sub CUL_MAX_SendQueueHandler($);

my $pairmodeDuration = 60; #seconds

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
  $hash->{AttrFn}    = "CUL_MAX_Attr";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ignore:0,1 " .
                        "showtime:1,0 loglevel:0,1,2,3,4,5,6 ".
                        $readingFnAttributes;

  $hash->{sendQueue} = [];
}

#############################

sub
CUL_MAX_SetupCUL($)
{
  my $hash = $_[0];
  AssignIoPort($hash);
  if(!defined($hash->{IODev})) {
    Log 1, "$hash->{NAME}: did not find suitable IODev (CUL etc. in rfmode MAX)! You may want to execute 'attr $hash->{NAME} IODev SomeCUL'";
    return 0;
  }

  if(CUL_MAX_Check($hash) >= 152) {
    #Doing this on older firmware disables MAX mode
    IOWrite($hash, "", "Za". $hash->{addr});
    #Append to initString, so this is resend if cul disappears and then reappears
    $hash->{IODev}{initString} .= "\nZa". $hash->{addr};
  }
  if(CUL_MAX_Check($hash) >= 153) {
    #Doing this on older firmware disables MAX mode
    my $cmd = "Zw". CUL_MAX_fakeWTaddr($hash);
    IOWrite($hash, "", $cmd);
    $hash->{IODev}{initString} .= "\n".$cmd;
  }
  return 1
}

sub
CUL_MAX_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> CUL_MAX <srcAddr>" if(@a<3);

  if(exists($modules{CUL_MAX}{defptr})) {
    Log 1, "There is already one CUL_MAX defined";
    return "There is already one CUL_MAX defined";
  }
  $modules{CUL_MAX}{defptr} = $hash;

  $hash->{addr} = lc($a[2]);
  $hash->{STATE} = "Defined";
  $hash->{cnt} = 0;
  $hash->{pairmode} = 0;
  $hash->{retryCount} = 0;
  $hash->{sendQueue} = [];
  CUL_MAX_SetupCUL($hash);

  #This interface is shared with 00_MAXLAN.pm
  $hash->{Send} = \&CUL_MAX_Send;

  #Start broadcasting time after 30 seconds, so there is enough time to parse the config
  InternalTimer(gettimeofday()+30, "CUL_MAX_BroadcastTime", $hash, 0);
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
CUL_MAX_Check($@)
{
  my ($hash) = @_;
  return if(!defined($hash->{IODev}));
  return if(!defined($hash->{IODev}{TYPE}));
  return if($hash->{IODev}{TYPE} ne "CUL");
  return if(!defined($hash->{IODev}{VERSION}));
  my $version = $hash->{IODev}{VERSION};

  #Looks like "V 1.49 CUL868"
  $version =~ m/V (.*)\.(.*) .*/;
  my ($major_version,$minorversion) = ($1, $2);
  $version = 100*$major_version + $minorversion;
  if($version < 154) {
    Log 2, "You are using an old version of the CUL firmware, which has known bugs with respect to MAX! support. Please update.";
  }
  return $version;
}

sub
CUL_MAX_Attr(@)
{
  my ($hash, $action, $name, $attr, $value) = @_;
  if ($action eq "set") {
    return "No such attribute" if($attr !~ ["fakeWTaddr", "fakeSCaddr", "IODev"]);
    return "Invalid value" if($attr ~~ ["fakeWTaddr", "fakeSCaddr"] && $value !~ /^[0-9a-fA-F]{6}$/);
  }
}

sub
CUL_MAX_fakeWTaddr($)
{
  return lc(AttrVal($_[0]->{NAME}, "fakeWTaddr", "111111"));
}

sub
CUL_MAX_fakeSCaddr($)
{
  return lc(AttrVal($_[0]->{NAME}, "fakeSCaddr", "222222"));
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

  } elsif($setting ~~ ["fakeSC", "fakeWT"]) {
    return "Invalid number of arguments" if(@args == 0);
    my $dest = $args[0];
    my $destname;
    #$dest may be either a name or an address
    if(exists($defs{$dest})) {
      return "Destination is not a MAX device" if($defs{$dest}{TYPE} ne "MAX");
      $destname = $dest;
      $dest = $defs{$dest}{addr};
    } else {
      $dest = lc($dest); #address to lower-case
      return "No MAX device with address $dest" if(!exists($modules{MAX}{defptr}{$dest}));
      $destname = $modules{MAX}{defptr}{$dest}{NAME};
    }

    if($setting eq "fakeSC") {
      return "Invalid number of arguments" if(@args != 2);
      return "Invalid fakeSCaddr attribute set (must not be 000000)" if(CUL_MAX_fakeSCaddr($hash) eq "000000");

      my $state = $args[1] ? "12" : "10";
      my $groupid = ReadingsVal($destname,"groupid",0);
      return CUL_MAX_Send($hash, "ShutterContactState",$dest,$state,
                          groupId => sprintf("%02x",$groupid),
                          flags => ( $groupid ? "04" : "06" ),
                          src => CUL_MAX_fakeSCaddr($hash));

    } elsif($setting eq "fakeWT") {
      return "Invalid number of arguments" if(@args != 3);
      return "desiredTemperature is invalid" if(!validTemperature($args[1]));
      return "Invalid fakeWTaddr attribute set (must not be 000000)" if(CUL_MAX_fakeWTaddr($hash) eq "000000");

      #Valid range for measured temperature is 0 - 51.1 degree
      $args[2] = 0 if($args[2] < 0); #Clamp temperature to minimum of 0 degree

      #Encode into binary form
      my $arg2 = int(10*$args[2]);
      #First bit is 9th bit of temperature, rest is desiredTemperature
      my $arg1 = (($arg2&0x100)>>1) | (int(2*MAX_ParseTemperature($args[1]))&0x7F);
      $arg2 &= 0xFF; #only take the lower 8 bits
      my $groupid = ReadingsVal($destname,"groupid",0);

      return CUL_MAX_Send($hash,"WallThermostatControl",$dest,
        sprintf("%02x%02x",$arg1,$arg2), groupId => sprintf("%02x",$groupid),
                flags => ( $groupid ? "04" : "00" ),
                src => CUL_MAX_fakeWTaddr($hash));
    }

  } else {
    return "Unknown argument $setting, choose one of pairmode broadcastTime";
  }
  return undef;
}

sub
CUL_MAX_Parse($$)
{
  #Attention: there is a limit in the culfw firmware: It only receives messages shorter than 30 bytes (see rf_moritz.h)
  my ($hash, $rmsg) = @_;

  if(!exists($modules{CUL_MAX}{defptr})) {
      Log 2, "No CUL_MAX defined";
      return "UNDEFINED CULMAX0 CUL_MAX 123456";
  }
  my $shash = $modules{CUL_MAX}{defptr};
  my $ll5 = GetLogLevel($shash->{NAME}, 5);

  return () if($rmsg !~ m/Z(..)(..)(..)(..)(......)(......)(..)(.*)/);

  my ($len,$msgcnt,$msgFlag,$msgTypeRaw,$src,$dst,$groupid,$payload) = ($1,$2,$3,$4,$5,$6,$7,$8);
  $len = hex($len);
  if(2*$len+3 != length($rmsg)) { #+3 = +1 for 'Z' and +2 for len field in hex
    Log 1, "CUL_MAX_Parse: len mismatch";
    return $shash->{NAME};
  }

  $groupid = hex($groupid);

  #convert adresses to lower case
  $src = lc($src);
  $dst = lc($dst);
  my $msgType = exists($msgId2Cmd{$msgTypeRaw}) ? $msgId2Cmd{$msgTypeRaw} : $msgTypeRaw;
  Log $ll5, "CUL_MAX_Parse: len $len, msgcnt $msgcnt, msgflag $msgFlag, msgTypeRaw $msgType, src $src, dst $dst, groupid $groupid, payload $payload";
  my $isToMe = ($dst eq $shash->{addr}) ? 1 : 0; # $isToMe is true if that packet was directed at us

  #Set RSSI on MAX device
  if(exists($modules{MAX}{defptr}{$src}) && exists($hash->{RSSI})) {
    Log 5, "CUL_MAX_Parse: rssi: $hash->{RSSI}";
    $modules{MAX}{defptr}{$src}{RSSI} = $hash->{RSSI};
  }

  if(exists($msgId2Cmd{$msgTypeRaw})) {

    if($msgType eq "Ack") {
      #Ignore packets generated by culfw's auto-Ack
      return $shash->{NAME} if($src eq $shash->{addr});
      return $shash->{NAME} if($src eq CUL_MAX_fakeWTaddr($hash));
      return $shash->{NAME} if($src eq CUL_MAX_fakeSCaddr($hash));

      Dispatch($shash, "MAX,$isToMe,Ack,$src,$payload", {RAWMSG => $rmsg});

      return $shash->{NAME} if(!@{$shash->{sendQueue}}); #we are not waiting for any Ack

      my $packet = $shash->{sendQueue}[0];
      if($packet->{src} eq $dst and $packet->{dst} eq $src and $packet->{cnt} == hex($msgcnt)) {
        Log $ll5, "Got matching ack";
        my $isnak = unpack("C",pack("H*",$payload)) & 0x80;
        $packet->{sent} = $isnak ? 3 : 2;
        return $shash->{NAME};
      }

    } elsif($msgType eq "TimeInformation") {
      if($isToMe) {
        #This is a request for TimeInformation send to us
        Log $ll5, "Got request for TimeInformation, sending it";
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
        Log $ll5, "CUL_MAX_Parse: Got TimeInformation: (in GMT) year $year, mon $month, day $day, hour $hour, min $min, sec $sec, unk ($unk1, $unk2, $unk3)";
      }
    } elsif($msgType eq "PairPing") {
      my ($unk1,$type,$unk2,$serial) = unpack("CCCa*",pack("H*",$payload));
      Log $ll5, "CUL_MAX_Parse: Got PairPing (dst $dst, pairmode $shash->{pairmode}), unk1 $unk1, type $type, unk2 $unk2, serial $serial";

      #There are two variants of PairPing:
      #1. It has a destination address of "000000" and can be paired to any device.
      #2. It is sent after changing batteries or repressing the pair button (without factory reset) and has a destination address of the last paired device. We can answer it with PairPong and even get an Ack, but it will still not be paired to us. A factory reset (originating from the last paired device) is needed first.
      if(($dst ne "000000") and !$isToMe) {
        Log $ll5, "Device want's to be re-paired to $dst, not to us";
        return $shash->{NAME};
      }

      if($shash->{pairmode}) {
        Log 3, "CUL_MAX_Parse: Pairing device $src of type $device_types{$type} with serial $serial";
        Dispatch($shash, "MAX,$isToMe,define,$src,$device_types{$type},$serial,0,0", {RAWMSG => $rmsg});
        #Send after dispatch the define, otherwise Send will create an invalid device
        CUL_MAX_Send($shash, "PairPong", $src, "00");

        #This are the default values that a device has after factory reset or pairing
        if($device_types{$type} =~ /HeatingThermostat.*/) {
          Dispatch($shash, "MAX,$isToMe,HeatingThermostatConfig,$src,17,21,30.5,4.5,80,5,0,12,15,100,0,0,12,$defaultWeekProfile", {RAWMSG => $rmsg});
        } elsif($device_types{$type} eq "WallMountedThermostat") {
          Dispatch($shash, "MAX,$isToMe,WallThermostatConfig,$src,17,21,30.5,4.5,$defaultWeekProfile", {RAWMSG => $rmsg});
        }
        #Todo: CUL_MAX_SendTimeInformation($shash, $src); on Ack for our PairPong
      }
    } elsif($msgType ~~ ["ShutterContactState", "WallThermostatState", "WallThermostatControl", "ThermostatState", "PushButtonState"])  {
      Dispatch($shash, "MAX,$isToMe,$msgType,$src,$payload", {RAWMSG => $rmsg});
    } else {
      Log $ll5, "Unhandled message $msgType";
    }
  } else {
    Log 2, "CUL_MAX_Parse: Got unhandled message type $msgTypeRaw";
  }
  return $shash->{NAME};
}

#All inputs are hex strings, $cmd is one from %msgCmd2Id
sub
CUL_MAX_Send(@)
{
  # $cmd is one of
  my ($hash, $cmd, $dst, $payload, %opts) = @_;

  my $flags = "00";
  my $groupId = "00";
  my $src = $hash->{addr};
  my $callbackParam = undef;

  $flags = $opts{flags} if(exists($opts{flags}));
  $groupId = $opts{groupId} if(exists($opts{groupId}));
  $src = $opts{src} if(exists($opts{src}));
  $callbackParam = $opts{callbackParam} if(exists($opts{callbackParam}));

  my $dhash = CUL_MAX_DeviceHash($dst);
  $dhash->{READINGS}{msgcnt}{VAL} += 1;
  $dhash->{READINGS}{msgcnt}{VAL} &= 0xFF;
  $dhash->{READINGS}{msgcnt}{TIME} = TimeNow();
  my $msgcnt = sprintf("%02x",$dhash->{READINGS}{msgcnt}{VAL});

  my $packet = $msgcnt . $flags . $msgCmd2Id{$cmd} . $src . $dst . $groupId . $payload;

  #prefix length in bytes
  $packet = sprintf("%02x",length($packet)/2) . $packet;

  Log GetLogLevel($hash->{NAME}, 5), "CUL_MAX_Send: enqueuing $packet";
  my $timeout = gettimeofday()+$ackTimeout;
  my $aref = $hash->{sendQueue};
  push(@{$aref},  { "packet" => $packet,
                    "src" => $src,
                    "dst" => $dst,
                    "cnt" => hex($msgcnt),
                    "time" => $timeout,
                    "sent" => "0",
                    "cmd" => $cmd,
                    "callbackParam" => $callbackParam,
                  });

  #Call CUL_MAX_SendQueueHandler if we just enqueued the only packet
  #otherwise it is already in the InternalTimer list
  CUL_MAX_SendQueueHandler($hash) if(@{$hash->{sendQueue}} == 1);
  return undef;
}

sub
CUL_MAX_DeviceHash($)
{
  my $addr = shift;
  return $modules{MAX}{defptr}{$addr};
}

#This can be called for two reasons:
#1. @sendQueue was empty, CUL_MAX_Send added a packet and then called us
#2. We sent a packet from @sendQueue and know the ackTimeout is over.
#   The packet my still be in @sendQueue (timed out) or removed when the Ack was received.
sub
CUL_MAX_SendQueueHandler($)
{
  my $hash = shift;
  Log GetLogLevel($hash->{NAME}, 5), "CUL_MAX_SendQueueHandler: " . @{$hash->{sendQueue}} . " items in queue";
  return if(!@{$hash->{sendQueue}}); #nothing to do

  my $timeout = gettimeofday(); #reschedule immediatly

  #Check if we have an IODev
  if(!defined($hash->{IODev})) {
      Log 1, "$hash->{NAME}: did not find suitable IODev (CUL etc. in rfmode MAX), cannot send! You may want to execute 'attr $hash->{NAME} IODev SomeCUL'";
      #Maybe some CUL will appear magically in some seconds
      #At least we cannot quit here with an non-empty queue, so we have two alternatives:
      #1. Delete the packet from queue and quit -> packet is lost
      #2. Wait, recheck, wait, recheck ... -> a lot of logs

      #InternalTimer($timeout+60, "CUL_MAX_SendQueueHandler", $hash, 0);
      $hash->{sendQueue} = [];
      return undef;
  }

  my $packet = $hash->{sendQueue}[0];

  if( $packet->{sent} == 0 ) { #Need to send it first
    #We can use fast sending without preamble on culfw 1.53 and higher when the devices has been woken up
    my $needPreamble = ((CUL_MAX_Check($hash) < 153)
      || !defined($modules{MAX}{defptr}{$packet->{dst}}{wakeUpUntil})
      || $modules{MAX}{defptr}{$packet->{dst}}{wakeUpUntil} < gettimeofday()) ? 1 : 0;

    #Send to CUL
    my ($credit10ms) = (CommandGet("","$hash->{IODev}{NAME} credit10ms") =~ /[^ ]* [^ ]* => (.*)/);
    if($credit10ms eq "No answer") {
      Log 1, "Error in CUL_MAX_SendQueueHandler: CUL $hash->{IODev}{NAME} did not answer request for current credits. Waiting 5 seconds.";
      $timeout += 5;
    } else {
      # We need 1000ms for preamble + len in bits (=hex len * 4) ms for payload. Divide by 10 to get credit10ms units
      # keep this in sync with culfw's code in clib/rf_moritz.c!
      my $necessaryCredit = ceil(100*$needPreamble + (length($packet->{packet})*4)/10);
      Log 5, "needPreamble: $needPreamble, necessaryCredit: $necessaryCredit, credit10ms: $credit10ms";
      if( defined($credit10ms) && $credit10ms < $necessaryCredit ) {
        my $waitTime = $necessaryCredit-$credit10ms; #we get one credit10ms every second
        $timeout += $waitTime;
        Log 2, "CUL_MAX_SendQueueHandler: Not enough credit! credit10ms is $credit10ms, but we need $necessaryCredit. Waiting $waitTime seconds.";
      } else {
        #Update TimeInformation payload. It should reflect the current time when sending,
        #not the time when it was enqueued. A low credit10ms can defer such a packet for multiple
        #minutes
        if( $msgId2Cmd{substr($packet->{packet},6,2)} eq "TimeInformation" ) {
          Log GetLogLevel($hash->{NAME}, 5), "Updating TimeInformation payload";
          substr($packet->{packet},22) = CUL_MAX_GetTimeInformationPayload();
        }
        IOWrite($hash, "", ($needPreamble ? "Zs" : "Zf") . $packet->{packet});

        $packet->{sent} = 1;
        $packet->{sentTime} = gettimeofday();
        $timeout += 0.5; #recheck for Ack
      }
    } # $credit10ms ne "No answer"

  } elsif( $packet->{sent} == 1 ) { #Already sent it, got no Ack
    if( $packet->{sentTime} + $ackTimeout < gettimeofday() ) {
      # ackTimeout exceeded
      Log 2, "CUL_MAX_SendQueueHandler: Missing ack from $packet->{dst} for $packet->{packet}";
      splice @{$hash->{sendQueue}}, 0, 1; #Remove from array
      readingsSingleUpdate($hash, "packetsLost", ReadingsVal($hash->{NAME}, "packetsLost", 0) + 1, 1);
    } else {
      # Recheck for Ack
      $timeout += 0.5;
    }

  } elsif( $packet->{sent} == 2 ) { #Got ack
    if(defined($packet->{callbackParam})) {
      Dispatch($hash, "MAX,1,Ack$packet->{cmd},$packet->{dst},$packet->{callbackParam}", {RAWMSG => ""});
    }
    splice @{$hash->{sendQueue}}, 0, 1; #Remove from array

  } elsif( $packet->{sent} == 3 ) { #Got nack
    splice @{$hash->{sendQueue}}, 0, 1; #Remove from array
  }

  return if(!@{$hash->{sendQueue}}); #everything done
  InternalTimer($timeout, "CUL_MAX_SendQueueHandler", $hash, 0);
}

sub
CUL_MAX_GetTimeInformationPayload()
{
  my ($sec,$min,$hour,$day,$mon,$year,$wday,$yday,$isdst) = localtime(time());
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
  Log GetLogLevel($hash->{NAME}, 5), "broadcast time to $addr";
  CUL_MAX_Send($hash, "TimeInformation", $addr, $payload, flags => "04");
}

sub
CUL_MAX_BroadcastTime(@)
{
  my ($hash,$manual) = @_;
  my $payload = CUL_MAX_GetTimeInformationPayload();
  Log GetLogLevel($hash->{NAME}, 5), "CUL_MAX_BroadcastTime: payload $payload ";
  my $i = 1;

  my @used_slots = ( 0, 0, 0, 0, 0, 0 );

  # First, lookup all thermstats for their current TimeInformationHour
  foreach my $addr (keys %{$modules{MAX}{defptr}}) {
    my $dhash = $modules{MAX}{defptr}{$addr};
    if(exists($dhash->{IODev}) && $dhash->{IODev} == $hash
          && $dhash->{type} =~ /.*Thermostat.*/ ) {

      my $h = ReadingsVal($dhash->{NAME},"TimeInformationHour","");
      $used_slots[$h]++ if( $h =~ /^[0-5]$/);
    }
  }

  foreach my $addr (keys %{$modules{MAX}{defptr}}) {
    my $dhash = $modules{MAX}{defptr}{$addr};
    #Check that
    #1. the MAX device dhash uses this MAX_CUL as IODev
    #2. the MAX device is a Wall/HeatingThermostat
    if(exists($dhash->{IODev}) && $dhash->{IODev} == $hash
    && $dhash->{type} =~ /.*Thermostat.*/ ) {

      my $h = ReadingsVal($dhash->{NAME},"TimeInformationHour",""); 
      if( $h !~ /^[0-5]$/ ) {
        #Find the used_slot with the smallest number of entries
        $h = (sort { $used_slots[$a] cmp $used_slots[$b] } 0 .. 5)[0];
        readingsSingleUpdate($dhash, "TimeInformationHour", $h, 1);
        $used_slots[$h]++;
      }

      CUL_MAX_SendTimeInformation($hash, $addr, $payload) if( [gmtime()]->[2] % 6 == $h );
    }
  }

  #Check again in 1 hour if some thermostats with the right TimeInformationHour need updating
  InternalTimer(gettimeofday() + 3600, "CUL_MAX_BroadcastTime", $hash, 0) unless(defined($manual));
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
  <b>Set</b>
  <ul>
      <li>pairmode<br>
      Sets the CUL_MAX into pairing mode for 60 seconds where it can be paired with other devices (Thermostats, Buttons, etc.). You also have to set the other device into pairing mode manually. (For Thermostats, this is pressing the "Boost" button for 3 seconds, for example).</li>
      <li>fakeSC &lt;device&gt; &lt;open&gt;<br>
      Sends a fake ShutterContactState message; &lt;open&gt; must be 0 or 1 for "window closed" or "window opened". If the &lt;device&gt; has a non-zero groupId, the fake ShutterContactState message affects all devices with that groupId. Make sure you associate the target device(s) with fakeShutterContact beforehand.</li>
      <li>fakeWT &lt;device&gt; &lt;desiredTemperature&gt; &lt;measuredTemperature&gt;<br>
      Sends a fake WallThermostatControl message (parameters both may have one digit after the decimal point, for desiredTemperature it may only by 0 or 5). If the &lt;device&gt; has a non-zero groupId, the fake WallThermostatControl message affects all devices with that groupId. Make sure you associate the target device with fakeWallThermostat beforehand.</li>
  </ul>
  <br>

  <a name="CUL_MAXget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="CUL_MAXattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#ignore">ignore</a></li><br>
    <li><a href="#do_not_notify">do_not_notify</a></li><br>
    <li><a href="#showtime">showtime</a></li><br>
    <li><a href="#loglevel">loglevel</a></li><br>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>

  <a name="CUL_MAXevents"></a>
  <b>Generated events:</b>
  <ul>N/A</ul>
  <br>

</ul>


=end html
=cut
