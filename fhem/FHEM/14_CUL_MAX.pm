##############################################
# $Id$
# Written by Matthias Gehre, M.Gehre@gmx.de, 2012
package main;

use strict;
use warnings;

sub CUL_MAX_SendDeviceCmd($$);
sub CUL_MAX_Send(@);
sub CUL_MAX_BroadcastTime($);
sub CUL_MAX_Set($@);

# Todo for full MAXLAN replacement:
# - Send Ack on ShutterContactState (but never else)

my $pairmodeDuration = 30; #seconds

my $timeBroadcastInterval = 6*60*60; #= 6 hours, the same time that the cube uses

#TODO: this is duplicated in MAXLAN
my %device_types = (
  0 => "Cube",
  1 => "HeatingThermostat",
  2 => "HeatingThermostatPlus",
  3 => "WallMountedThermostat",
  4 => "ShutterContact",
  5 => "PushButton"
);

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
  $hash->{devices} = ();
  AssignIoPort($hash);

  #This interface is shared with 00_MAXLAN.pm
  $hash->{SendDeviceCmd} = \&CUL_MAX_SendDeviceCmd;

  CUL_MAX_BroadcastTime($hash);
  return undef;
}

#####################################
sub
CUL_MAX_Undef($$)
{
  my ($hash, $name) = @_;
  RemoveInternalTimer($hash);
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
  } else {
    return "Unknown argument $setting, choose one of pairmode";
  }
  return undef;
}

###################################
my %msgTypes = ( #Receiving:
                 "00" => "PairPing",
                 "02" => "Ack",
                 "03" => "TimeInformation",
                 "30" => "ShutterContactState",
                 "60" => "HeatingThermostatState"
               );
my %sendTypes = (#Sending:
                 "PairPong" => "01",
                 "TimeInformation" => "03",
                 #"40" => "SetTemperature",
                 #"11" => "SetConfiguration",
                 #"F1" => "WakeUp",
               );

sub
CUL_MAX_Parse($$)
{
  my ($hash, $rmsg) = @_;

  if(!exists($modules{CUL_MAX}{defptr})) {
      Log 5, "No CUL_MAX defined";
      return "UNDEFINED CULMAX0 CUL_MAX 123456";
  }
  my $shash = $modules{CUL_MAX}{defptr};

  $rmsg =~ m/Z(..)(..)(..)(..)(......)(......)(..)(.*)/;
  my ($len,$msgcnt,$msgFlagRaw,$msgTypeRaw,$src,$dst,$zero,$payload) = ($1,$2,$3,$4,$5,$6,$7,$8);
  $len = hex($len);
  Log 1, "CUL_MAX_Parse: len mismatch" if(2*$len+3 != length($rmsg)); #+3 = +1 for 'Z' and +2 for len field in hex
  Log 1, "CUL_MAX_Parse zero = $zero" if($zero != 0);

  my $msgFlag = sprintf("%b",hex($msgFlagRaw));

  #convert adresses to lower case
  $src = lc($src);
  $dst = lc($dst);

  Log 5, "CUL_MAX_Parse: len $len, msgcnt $msgcnt, msgflag $msgFlag, msgTypeRaw $msgTypeRaw, src $src, dst $dst, payload $payload";
  if(exists($msgTypes{$msgTypeRaw})) {
    my $msgType = $msgTypes{$msgTypeRaw};
    if($msgType eq "Ack") {
      #The Ack payload for HeatingThermostats is 01HHHHHH where HHHHHH are the first 3 bytes of the HeatingThermostatState payload
      Log 5, "Got Ack";

    } elsif($msgType eq "TimeInformation") {
      if($len == 10) {
        Log 5, "Want TimeInformation?";
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
        Log 5, "Got TimeInformation: (in GMT) year $year, mon $month, day $day, hour $hour, min $min, sec $sec, unk ($unk1, $unk2, $unk3)";
      }
    } elsif($msgType eq "PairPing") {
      my ($unk1,$type,$unk2,$serial) = unpack("CCCa*",pack("H*",$payload));
      Log 5, "Got PairPing (pairmode $shash->{pairmode}), unk1 $unk1, type $type, unk2 $unk2, serial $serial";
      if($shash->{pairmode}) {
        CUL_MAX_Send($shash, "PairPong", $src, "00", "00000000");
        #TODO: wait for Ack
        Dispatch($shash, "MAX,define,$src,$device_types{$type},$serial,0,0", {RAWMSG => $rmsg});
        #TODO: send TimeInformation
      }

    } else {
      Dispatch($shash, "MAX,$msgType,$src,$payload", {RAWMSG => $rmsg});
    }
  } else {
    Log 2, "Got unhandled message type $msgTypeRaw";
  }
  return undef;
}

sub
CUL_MAX_Send(@)
{
  my ($hash, $cmd, $dst, $payload, $flags) = @_;

  $flags = "0"x8 if(!$flags);

  return CUL_MAX_SendDeviceCmd($hash, pack("H2B8H*","00",$flags,$sendTypes{$cmd}.$hash->{addr}.$dst."00".$payload));
}

sub
CUL_MAX_DeviceHash($)
{
  my $addr = shift @_;
  return $modules{MAX}{defptr}{$addr};
}

sub
CUL_MAX_SendDeviceCmd($$)
{
  my ($hash,$payload) = @_;

  my $dstaddr = substr($payload,6,3);
  my $dhash = CUL_MAX_DeviceHash($dstaddr);

  #If cnt is not right, we don't get an Ack (At least if count is too low - have to test more)
  #TODO: cnt is per device, not global
  #$dhash->{READINGS}{msgcnt}{VAL} = ($dhash->{READINGS}{msgcnt}{VAL} + 1) & 0xFF;
  my $cnt = 1;
  #replace source address
  substr($payload,3,3) = pack("H6",$hash->{addr});
  #replace message counter
  substr($payload,0,1) = pack("C",$cnt);
  #Prefix length byte
  $payload = pack("C",length($payload)) . $payload;

  $payload = unpack("H*",$payload); #convert to hex
  Log 5, "CUL_MAX_SendDeviceCmd: ". $payload;
  IOWrite($hash, "", "Zs". $payload);
  return undef;
}

sub
CUL_MAX_BroadcastTime($)
{
  my $hash = shift @_;
  my ($sec,$min,$hour,$day,$mon,$year,$wday,$yday,$isdst) = gmtime(time());
  $mon += 1; #make month 1-based
  #month encoding is just guessed
  #also $hour-1 is not so clear, maybe there is some timezone involved (maybe we should send gmtime?)
  #but where do we send the timezone? or is scheduled data/until in GMT?
  #perls localtime gives years since 1900, and we need years since 2000
  my $payload = unpack("H*",pack("CCCCC", $year - 100, $day, $hour, $min | (($mon & 0x0C) << 4), $sec | (($mon & 0x03) << 6)));
  Log 5, "CUL_MAX_BroadcastTime: payload $payload";
  while (my ($addr, $dhash) = each (%{$modules{MAX}{defptr}})) {
    if(exists($dhash->{IODev}) && $dhash->{IODev} == $hash) {
      Log 5, "broadcast time to $addr";
      CUL_MAX_Send($hash, "TimeInformation", $addr, $payload, "00000011");
    }
  }
  InternalTimer(gettimeofday()+$timeBroadcastInterval, "CUL_MAX_BroadcastTime", $hash, 0);
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
