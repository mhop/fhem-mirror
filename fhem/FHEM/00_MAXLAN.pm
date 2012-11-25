##############################################
# $Id$
# Written by Matthias Gehre, M.Gehre@gmx.de, 2012
package main;

use strict;
use warnings;
use MIME::Base64;
use Data::Dumper;
use POSIX;

sub MAXLAN_Parse($$);
sub MAXLAN_Read($);
sub MAXLAN_Write($$);
sub MAXLAN_ReadAnswer($);
sub MAXLAN_SimpleWrite(@);
sub MAXLAN_Poll($);
sub MAXLAN_SendDeviceCmd($$);
sub MAXLAN_RequestConfiguration($$);
sub MAXLAN_RemoveDevice($$);

my %device_types = (
  0 => "Cube",
  1 => "HeatingThermostat",
  2 => "HeatingThermostatPlus",
  3 => "WallMountedThermostat",
  4 => "ShutterContact",
  5 => "PushButton"
);

my @boost_durations = (0, 5, 10, 15, 20, 25, 30, 60);

#Time after which we reconnect after a failed connection attempt
my $reconnect_interval = 5; #seconds

#the time it takes after sending one command till we see its effect in the L: response
my $roundtriptime = 3; #seconds

my $metadata_magic = 0x56;
my $metadata_version = 2;

my $defaultPollInterval = 60;

sub
MAXLAN_Initialize($)
{
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

# Provider
  $hash->{ReadFn}  = "MAXLAN_Read";
  $hash->{WriteFn} = "MAXLAN_Write";
  $hash->{SetFn}   = "MAXLAN_Set";
  $hash->{Clients} = ":MAX:";
  my %mc = (
       "1:MAX" => "^MAX",
  );
  $hash->{MatchList} = \%mc;

# Normal devices
  $hash->{DefFn}   = "MAXLAN_Define";
  $hash->{UndefFn} = "MAXLAN_Undef";
  $hash->{AttrList}= "do_not_notify:1,0 dummy:1,0 " .
                     "loglevel:0,1,2,3,4,5,6 addvaltrigger "; 
}

#####################################
sub
MAXLAN_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a < 3 or @a > 4) {
    my $msg = "wrong syntax: define <name> MAXLAN ip[:port] [pollintervall]";
    Log 2, $msg;
    return $msg;
  }
  DevIo_CloseDev($hash);

  my $name = $a[0];
  my $dev = $a[2];
  $dev .= ":62910" if($dev !~ m/:/ && $dev ne "none" && $dev !~ m/\@/);

  if($dev eq "none") {
    Log 1, "$name device is none, commands will be echoed only";
    $attr{$name}{dummy} = 1;
    return undef;
  }

  #Sometimes (race condition in the cube?) the cube sends invalid
  #configuration. Doing a reconnect usually remedies that.
  $hash->{InvalidConfigurationReconnectCount} = 10;

  $hash->{PARTIAL} = "";
  $hash->{DeviceName} = $dev;
  $hash->{INTERVAL} = @a > 3 ? $a[3] : $defaultPollInterval;
  #This interface is shared with 14_CUL_MAX.pm
  $hash->{SendDeviceCmd} = \&MAXLAN_SendDeviceCmd;
  $hash->{RemoveDevice} = \&MAXLAN_RemoveDevice;


  MAXLAN_Connect($hash);
}

sub
MAXLAN_Connect($)
{
  my $hash = shift;

  #Close connection (if there is a previous one)
  DevIo_CloseDev($hash);

  RemoveInternalTimer($hash);

  $hash->{gothello} = 0;
  $hash->{gotInvalidConfiguration} = 0;

  delete($hash->{NEXT_OPEN}); #work around the connection rate limiter in DevIo

  my $ret = DevIo_OpenDev($hash, 0, "MAXLAN_DoInit");
  if($hash->{STATE} ne "opened"){
    Log 3, "Scheduling reconnect attempt in $reconnect_interval seconds";
    InternalTimer(gettimeofday()+$reconnect_interval, "MAXLAN_Connect", $hash, 0);
  }
  return $ret;
}


#####################################
sub
MAXLAN_Undef($$)
{
  my ($hash, $arg) = @_;
  RemoveInternalTimer($hash);
  MAXLAN_Write($hash,"q:");
  DevIo_CloseDev($hash); 
  return undef;
}

#####################################
sub
MAXLAN_Set($@)
{
  my ($hash, $device, @a) = @_;
  return "\"set MAXLAN\" needs at least one parameter" if(@a < 1);
  my ($setting, @args) = @a;

  if($setting eq "pairmode"){
    if(@args > 0 and $args[0] eq "cancel") {
      MAXLAN_Write($hash,"x:");
      return MAXLAN_ExpectAnswer($hash,"N:");
    } else {
      my $duration = 60;
      $duration = $args[0] if(@args > 0);
      MAXLAN_Write($hash,"n:".sprintf("%04x",$duration));
      $hash->{STATE} = "pairing";
    }

  }elsif($setting eq "raw"){
    MAXLAN_Write($hash,$args[0]);

  }elsif($setting eq "clock"){
    if(!exists($hash->{rfaddr})){
      Log 5, "Defering the setting of time until after hello";
      $hash->{setTimeOnHello} = 1;
      return;
    }

    #This encodes the winter/summer timezones, its meaning is not entirely clear
    my $timezones = "Q0VUAAAKAAMAAA4QQ0VTVAADAAIAABwg";

    #The offset was obtained by experiment and is up to 1 minute, I don't know exactly what
    #time format the cube uses. Something based on ntp I guess. Maybe this only works in GMT+1?
    my $time = time()-946684774;
    my $rmsg = "v:".$timezones.",".sprintf("%08x",$time);
    MAXLAN_Write($hash,$rmsg);
    my $answer = MAXLAN_ReadAnswer($hash);
    if($answer ne "A:"){
      Log 1, "Failed to set clock, answer was $answer, expected A:";
    }else{
      Dispatch($hash, "MAX,CubeClockState,$hash->{rfaddr},1", {RAWMSG => $rmsg});
    }

  }elsif($setting eq "factoryReset") {
    MAXLAN_RequestReset($hash);

  }elsif($setting eq "reconnect") {
    MAXLAN_Connect($hash);
  }else{
    return "Unknown argument $setting, choose one of pairmode raw clock factoryReset reconnect";
  }
  return undef;
}

sub
MAXLAN_ExpectAnswer($$)
{
  my ($hash,$expectedanswer) = @_;
  my $rmsg = MAXLAN_ReadAnswer($hash);
  return "Error while receiving" if(!defined($rmsg)); #error is already logged in MAXLAN_ReadAnswer

  my $ret = undef;
  if($rmsg !~ m/^$expectedanswer/) {
    Log 2, "MAXLAN_ParseAnswer: Got unexpected response, expected $expectedanswer";
    MAXLAN_Parse($hash,$rmsg);
    return "Got unexpected response, expected $expectedanswer";
  }
  return MAXLAN_Parse($hash,$rmsg);
}


#####################################
sub
MAXLAN_ReadAnswer($)
{
  my ($hash) = @_;

  #Read until we have a complete line
  until($hash->{PARTIAL} =~ m/\n/) {
    my $buf = DevIo_SimpleRead($hash);
    if(!defined($buf)){
      Log 1, "MAXLAN_ReadAnswer: error during read";
      return undef; #error occured
    }
    $hash->{PARTIAL} .= $buf;
  }

  my $rmsg;
  ($rmsg,$hash->{PARTIAL}) = split("\n", $hash->{PARTIAL}, 2);
  $rmsg =~ s/\r//; #remove \r
  return $rmsg;
}

my %lhash;

#####################################
sub
MAXLAN_Write($$)
{
  my ($hash,$msg) = @_;
  
  MAXLAN_SimpleWrite($hash, $msg);
}

#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub
MAXLAN_Read($)
{
  my ($hash) = @_;

  my $buf = DevIo_SimpleRead($hash);
  return "" if(!defined($buf));
  my $name = $hash->{NAME};

  $hash->{PARTIAL} .= $buf;

  #while we have a complete line
  while($hash->{PARTIAL} =~ m/\n/) {
    my $rmsg;
    ($rmsg,$hash->{PARTIAL}) = split("\n", $hash->{PARTIAL}, 2);
    $rmsg =~ s/\r//;#remove \r
    MAXLAN_Parse($hash, $rmsg) if($rmsg);
  }
}

sub
MAXLAN_SendMetadata($)
{
  my $hash = shift;

  if(defined($hash->{metadataVersionMismatch})){
    Log 3,"MAXLAN_SendMetadata: current version of metadata unexpected, not overwriting!";
    return;
  }

  my $maxNameLength = 32;
  my $maxGroupCount = 20;
  my $maxDeviceCount = 140;

  my @groups = @{$hash->{groups}};
  my @devices = @{$hash->{devices}};

  if(@groups > $maxGroupCount || @devices > $maxDeviceCount) {
    Log 1, "MAXLAN_SendMetadata: you got more than $maxGroupCount groups or $maxDeviceCount devices";
    return;
  }

  my $metadata = pack("CC",$metadata_magic,$metadata_version);

  $metadata .= pack("C",scalar(@groups));
  foreach(@groups){
    if(length($_->{name}) > $maxNameLength) {
      Log 1, "Group name $_->{name} is too long, maximum of $maxNameLength characters allowed";
      return;
    }
    $metadata .= pack("CC/aH6",$_->{id}, $_->{name}, $_->{masterAddr});
  }
  $metadata .= pack("C",scalar(@devices));
  foreach(@devices){
    if(length($_->{name}) > $maxNameLength) {
      Log 1, "Device name $_->{name} is too long, maximum of $maxNameLength characters allowed";
      return;
    }
    $metadata .= pack("CH6a[10]C/aC",$_->{type}, $_->{addr}, $_->{serial}, $_->{name}, $_->{groupid});
  }

  $metadata .= pack("C",1); #dstenables, should always be 1
  my $blocksize = 1900;

  $metadata = encode_base64($metadata,"");

  my $numpackages = ceil(length($metadata)/$blocksize);
  for(my $i=0;$i < $numpackages; $i++) {
    my $package = substr($metadata,$i*$blocksize,$blocksize);

    MAXLAN_Write($hash,"m:".sprintf("%02d",$i).",".$package);
    my $answer = MAXLAN_ReadAnswer($hash);
    if($answer ne "A:"){
      Log 1, "SendMetadata got response $answer, expected 'A:'";
      return;
    }
  }
}

sub
MAXLAN_FinishConnect($)
{
  my ($hash) = @_;

  if($hash->{gotInvalidConfiguration} and $hash->{InvalidConfigurationReconnectCount} > 0) {
    #Workaround a cube bug by reconnecting
    Log 3, "Reconnecting to workaround a cube bug, $hash->{InvalidConfigurationReconnectCount} attempts left";
    $hash->{InvalidConfigurationReconnectCount} -= 1;
    MAXLAN_Connect($hash); #reconnect
    return;
  }

  #Reset reconnect count if we finally got a good configuration
  $hash->{InvalidConfigurationReconnectCount} = 10 if(!$hash->{gotInvalidConfiguration});

  #Handle deferred setting of time (L: is the last response after connection before the cube starts to idle)
  if(defined($hash->{setTimeOnHello})) {
    MAXLAN_Set($hash,$hash->{NAME},"clock");
    delete $hash->{setTimeOnHello};
  }
  #Enable polling timer
  InternalTimer(gettimeofday()+$hash->{INTERVAL}, "MAXLAN_Poll", $hash, 0)
}

sub
MAXLAN_Parse($$)
{
  #http://www.domoticaforum.eu/viewtopic.php?f=66&t=6654
  my ($hash, $rmsg) = @_;

  my $name = $hash->{NAME};
  my $ll3 = GetLogLevel($name,3);
  my $ll5 = GetLogLevel($name,5);
  Log $ll5, "Msg $rmsg";
  my $cmd = substr($rmsg,0,1); # get leading char
  my @args = split(',', substr($rmsg,2));
  #Log $ll5, 'args '.join(" ",@args);

  if ($cmd eq 'H'){ #Hello
    $hash->{serial} = $args[0];
    $hash->{rfaddr} = $args[1];
    $hash->{fwversion} = $args[2];
    my $dutycycle = 0;
    if(@args > 5){
      $dutycycle = $args[5];
    }
    my $freememory = 0;
    if(@args > 6){
      $freememory = $args[6];
    }
    my $cubedatetime = {
            year => 2000+hex(substr($args[7],0,2)),
            month => hex(substr($args[7],2,2)),
            day => hex(substr($args[7],4,2)),
            hour => hex(substr($args[8],0,2)),
            minute => hex(substr($args[8],2,2)),
          };
    my $clockset = hex($args[9]);
    #$cubedatetime is only valid if $clockset is 1
    if($clockset) {
      my ($sec,$min,$hour,$mday,$mon,$year) = localtime(time);
      my $difference = ((((($cubedatetime->{year} - $year-1900)*12
                          + $cubedatetime->{month} - $mon-1)*30
                          + $cubedatetime->{day} - $mday)*24
                          + $cubedatetime->{hour} - $hour)*60
                          + $cubedatetime->{minute} - $min);
      Log 3, "Cube thinks it is $cubedatetime->{day}.$cubedatetime->{month}.$cubedatetime->{year} $cubedatetime->{hour}:$cubedatetime->{minute}";
      Log 3, "Time difference is $difference minutes";
    }

    Dispatch($hash, "MAX,define,$hash->{rfaddr},Cube,$hash->{serial}", {RAWMSG => $rmsg});
    Dispatch($hash, "MAX,CubeConnectionState,$hash->{rfaddr},1", {RAWMSG => $rmsg});
    Dispatch($hash, "MAX,CubeClockState,$hash->{rfaddr},$clockset", {RAWMSG => $rmsg});
    Log $ll5, "MAXLAN_Parse: Got hello, connection ip $args[4], duty cycle $dutycycle, freememory $freememory, clockset $clockset";

  } elsif($cmd eq 'M') {
    #Metadata, this is basically a readwrite part of the cube's memory.
    #I don't think that the cube interprets any of that data.
    #One can write to that memory with the "m:" command
    #The actual configuration comes with the "C:" response and can be set
    #with the "s:" command.
    return if(@args < 3); #On virgin devices, we get nothing, not even $magic$version$numgroups$numdevices

    my $bindata = decode_base64($args[2]);
    #$version is the version the serialized data format I guess
    my ($magic,$version,$numgroups,@groupsdevices);
    eval {
      ($magic,$version,$numgroups,@groupsdevices) = unpack("CCCXC/(CC/aH6)C/(CH6a[10]C/aC)C",$bindata);
      1;
    } or do {
      Log 1, "Metadata response is malformed!";
      return;
    };
    
    if($magic != $metadata_magic || $version != $metadata_version) {
      Log 3, "MAXLAN_Parse: magic $magic/version $version are not $metadata_magic/$metadata_version as expected";
      $hash->{metadataVersionMismatch} = 1;
    }

    my $daylightsaving = pop(@groupsdevices); #should be always true (=0x01)

    my $i;
    $hash->{groups} = ();
    for($i=0;$i<3*$numgroups;$i+=3){
      $hash->{groups}[@{$hash->{groups}}]->{id} = $groupsdevices[$i];
      $hash->{groups}[-1]->{name} = $groupsdevices[$i+1];
      $hash->{groups}[-1]->{masterAddr} = $groupsdevices[$i+2];
    }
    #After a device is freshly paired, it does not appear in this metadata response,
    #we first have to set some metadata for it
    $hash->{devices} = ();
    for(;$i<@groupsdevices;$i+=5){
      $hash->{devices}[@{$hash->{devices}}]->{type} = $groupsdevices[$i];
      $hash->{devices}[-1]->{addr} = $groupsdevices[$i+1];
      $hash->{devices}[-1]->{serial} = $groupsdevices[$i+2];
      $hash->{devices}[-1]->{name} = $groupsdevices[$i+3];
      $hash->{devices}[-1]->{groupid} = $groupsdevices[$i+4];
      Dispatch($hash, "MAX,define,$hash->{devices}[-1]->{addr},$device_types{$hash->{devices}[-1]->{type}},$hash->{devices}[-1]->{serial},$hash->{devices}[-1]->{groupid}", {RAWMSG => $rmsg});
    }

    Log $ll5, "Got Metadata, hash: ".Dumper($hash);

  }elsif($cmd eq "C"){#Configuration
    return if(@args < 2);
    my $bindata = decode_base64($args[1]);

    if(length($bindata) < 18) {
      Log 1, "Invalid C: response, not enough data";
      return "Invalid C: response, not enough data";
    }

    #Parse the first 18 bytes, those are send for every device
    my ($len,$addr,$devicetype,$groupid,$firmware,$testresult,$serial) = unpack("CH6CCCCa[10]", $bindata);
    Log $ll5, "len $len, addr $addr, devicetype $devicetype, firmware $firmware, testresult $testresult, groupid $groupid, serial $serial";

    $len = $len+1; #The len field itself was not counted

    Dispatch($hash, "MAX,define,$addr,$device_types{$devicetype},$serial,$groupid", {RAWMSG => $rmsg});

    if($len != length($bindata)) {
      Dispatch($hash, "MAX,Error,$addr,Parts of configuration are missing", {RAWMSG => $rmsg});
      $hash->{gotInvalidConfiguration} = 1;
      return "Invalid C: response, len does not match";
    }

    #devicetype: Cube = 0, HeatingThermostat = 1, HeatingThermostatPlus = 2, WallMountedThermostat = 3, ShutterContact = 4, PushButton = 5
    #Seems that ShutterContact does not have any configdata
    if($devicetype == 0){#Cube
      #TODO: there is a lot of data left to interpret
    }elsif($devicetype == 1){#HeatingThermostat
      my ($comforttemp,$ecotemp,$maxsetpointtemp,$minsetpointtemp,$tempoffset,$windowopentemp,$windowopendur,$boost,$decalcifiction,$maxvalvesetting,$valveoffset) = unpack("CCCCCCCCCCC",substr($bindata,18));
      my $boostValve = ($boost & 0x1F) * 5;
      my $boostDuration =  $boost_durations[$boost >> 5]; #in minutes
      #There is some trailing data missing, which maps to the weekly program
      $comforttemp=$comforttemp/2.0; #convert to degree celcius
      $ecotemp=$ecotemp/2.0; #convert to degree celcius
      $tempoffset = $tempoffset/2.0-3.5; #convert to degree
      $maxsetpointtemp=$maxsetpointtemp/2.0;
      $minsetpointtemp=$minsetpointtemp/2.0;
      $windowopentemp=$windowopentemp/2.0;
      $windowopendur=$windowopendur*5;
      Log $ll5, "comfortemp $comforttemp, ecotemp $ecotemp, boostValve $boostValve, boostDuration $boostDuration, tempoffset $tempoffset, $minsetpointtemp minsetpointtemp, maxsetpointtemp $maxsetpointtemp, windowopentemp $windowopentemp, windowopendur $windowopendur";
      Dispatch($hash, "MAX,HeatingThermostatConfig,$addr,$ecotemp,$comforttemp,$boostValve,$boostDuration,$tempoffset,$maxsetpointtemp,$minsetpointtemp,$windowopentemp,$windowopendur", {RAWMSG => $rmsg});
    }elsif($devicetype == 4){#ShutterContact TODO
      Log 2, "ShutterContact send some configuration, but none was expected" if($len > 18);
    }else{ #TODO
      Log 2, "Got configdata for unimplemented devicetype $devicetype";
    }

    #Clear Error
    Dispatch($hash, "MAX,Error,$addr", {RAWMSG => $rmsg});

    #Check if it is already recorded in devices
    my $found = 0;
    foreach (@{$hash->{devices}}) {
      $found = 1 if($_->{addr} eq $addr);
    }
    #Add device if it is not already known and not the cube itself
    if(!$found && $devicetype != 0){
      $hash->{devices}[@{$hash->{devices}}]->{type} = $devicetype;
      $hash->{devices}[-1]->{addr} = $addr;
      $hash->{devices}[-1]->{serial} = $serial;
      $hash->{devices}[-1]->{name} = "no name";
      $hash->{devices}[-1]->{groupid} = $groupid;
    }

  }elsif($cmd eq 'L'){#List

    my $bindata = "";
    $bindata  = decode_base64($args[0]) if(@args > 0);
    #The L command consists of blocks of states (one for each device)
    while(length($bindata)){
      my ($len,$addr,$errframetype,$bits1) = unpack("CH6Ca",$bindata);
      my $unkbit1 = vec($bits1,0,1);
      my $initialized = vec($bits1,1,1); #I never saw this beeing 0
      my $answer = vec($bits1,2,1); #answer to what?
      my $rferror1 = vec($bits1,3,1); # if 1 then see errframetype
      my $valid = vec($bits1,4,1); #is the status following the common header valid
      my $unkbit2 = vec($bits1,5,1);
      my $unkbit3 = vec($bits1,6,2);
  
      Log 5, "len $len, addr $addr, initialized $initialized, valid $valid, rferror $rferror1, errframetype $errframetype, answer $answer, unkbit ($unkbit1,$unkbit2,$unkbit3)";

      my $payload = unpack("H*",substr($bindata,6,$len-6+1)); #+1 because the len field is not counted
      if($valid) {
        my $shash = $modules{MAX}{defptr}{$addr};

        if(!$shash) {
          Log 2, "Got List response for undefined device with addr $addr";
        }elsif($shash->{type} eq "HeatingThermostat"){
          Dispatch($hash, "MAX,HeatingThermostatState,$addr,$payload", {RAWMSG => $rmsg});
        }elsif($shash->{type} eq "ShutterContact"){
          Dispatch($hash, "MAX,ShutterContactState,$addr,$payload", {RAWMSG => $rmsg});
        }else{
          Log 2, "Got status for unimplemented device type $shash->{type}";
        }
      } # if($valid)
      $bindata=substr($bindata,$len+1); #+1 because the len field is not counted
    } # while(length($bindata))

    if(!$hash->{gothello}) {
      # "L:..." is the last response after connection before the cube starts to idle
      $hash->{gothello} = 1;
      MAXLAN_FinishConnect($hash);
    }
  }elsif($cmd eq "N"){#New device paired
    if(@args==0){
      $hash->{STATE} = "initalized"; #pairing ended
      return;
    }
    my ($type, $addr, $serial) = unpack("CH6a[10]", decode_base64($args[0]));
    Log 2, "Paired new device, type $device_types{$type}, addr $addr, serial $serial";
    Dispatch($hash, "MAX,define,$addr,$device_types{$type},$serial", {RAWMSG => $rmsg});

    #After a device has been paired, it automatically appears in the "L" and "C" commands,
    MAXLAN_RequestConfiguration($hash,$addr);
  } elsif($cmd eq "A"){#Acknowledged
    Log 3, "Got stray Acknowledged from cube, this should be read by MAXLAN_ReadAnswer";

  } elsif($cmd eq "S"){#Response to s:
    my $dutycycle = hex($args[0]); #number of command send over the air
    my $discarded = $args[1];
    my $freememoryslot = $args[2];
    Log 5, "dutycyle $dutycycle, freememoryslot $freememoryslot";

    Log 3, "1% rule: we sent too much, cmd is now in queue" if($dutycycle == 100 && $freememoryslot > 0);
    Log 3, "1% rule: we sent too much, queue is full, cmd discarded" if($dutycycle == 100 && $freememoryslot == 0);
    Log 3, "Command was discarded" if($discarded);
    return "Command was discarded" if($discarded);
  } else {
    Log $ll5, "$name Unknown command $cmd";
    return "Unknown command $cmd";
  }
  return undef;
}


########################
sub
MAXLAN_SimpleWrite(@)
{
  my ($hash, $msg) = @_;
  my $name = $hash->{NAME};

  Log GetLogLevel($name,5), 'MAXLAN_SimpleWrite:  '.$msg;
  
  $msg .= "\r\n";
  
  my $ret = syswrite($hash->{TCPDev}, $msg);
  #TODO: none of those conditions detect if the connection is actually lost!
  if(!$hash->{TCPDev} || !defined($ret) || !$hash->{TCPDev}->connected) {
      Log GetLogLevel($name,1), 'MAXLAN_SimpleWrite failed';
      MAXLAN_Connect($hash);
    }
}

########################
sub
MAXLAN_DoInit($)
{
  my ($hash) = @_;
  $hash->{gothello} = 0;
  return undef;
}

sub
MAXLAN_RequestList($)
{
  my $hash = shift;
  MAXLAN_Write($hash, "l:");
  return MAXLAN_ExpectAnswer($hash, "L:");
}

#####################################
sub
MAXLAN_Poll($)
{
  my $hash = shift;

  return if(!$hash->{FD});

  if(!defined(MAXLAN_RequestList($hash))) {
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "MAXLAN_Poll", $hash, 0);
  } else {
    Log 1, "MAXLAN_Poll: Did not get any answer";
  }
}

sub
MAXLAN_RequestConfiguration($$)
{
  my ($hash,$addr) = @_;
  MAXLAN_Write($hash,"c:$addr");
  MAXLAN_ExpectAnswer($hash, "C:");
}

#Sends command to a device and waits for acknowledgment
sub
MAXLAN_SendDeviceCmd($$)
{
  my ($hash,$payload) = @_;
  MAXLAN_Write($hash,"s:".encode_base64($payload,""));
  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+$roundtriptime, "MAXLAN_Poll", $hash, 0);
  return MAXLAN_ExpectAnswer($hash, "S:");
}

#Resets the cube, i.e. does a factory reset. All pairings will be lost.
sub
MAXLAN_RequestReset($)
{
  my $hash = shift;
  MAXLAN_Write($hash,"a:");
  MAXLAN_ExpectAnswer($hash, "A:");
}

#Remove the device from the cube, i.e. deletes the pairing
sub
MAXLAN_RemoveDevice($$)
{
  my ($hash,$addr) = @_;
  MAXLAN_Write($hash,"t:1,1,".encode_base64(pack("H6",$addr),""));
  MAXLAN_ExpectAnswer($hash, "A:");
}

1;

=pod
=begin html

<a name="MAXLAN"></a>
<h3>MAXLAN</h3>
<ul>
  <tr><td>
  The MAXLAN is the fhem module for the eQ-3 MAX! Cube LAN Gateway.
  <br><br>
  The fhem module makes the MAX! "bus" accessible to fhem, automatically detecting paired MAX! devices. (The devices themselves are handled by the <a href="#MAX">MAX</a> module).<br>
  The MAXLAN module keeps a persistant connection to the cube. The cube only allows one connection at a time, so neither the Max! Software or the
  Max! internet portal can be used at the same time.
  <br>

  <a name="MAXLANdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; MAXLAN &lt;ip-address&gt;[:port] [&lt;pollintervall&gt;]</code><br>
    <br>
    port is 62910 by default. (If your Cube listens on port 80, you have to update the firmware with
    the official MAX! software).
    If the ip-address is called none, then no device will be opened, so you
    can experiment without hardware attached.<br>
    The optional parameter &lt;pollintervall&gt; defines the time in seconds between each polling of data from the cube.<br>
  </ul>
  <br>

  <a name="MAXLANset"></a>
  <b>Set</b>
  <ul>
    <li>pairmode [&lt;n&gt;,cancel]<br>
    Sets the cube into pairing mode for &lt;n&gt; seconds (default is 60s ) where it can be paired with other devices (Thermostats, Buttons, etc.). You also have to set the other device into pairing mode manually. (For Thermostats, this is pressing the "Boost" button for 3 seconds, for example).
Setting pairmode to "cancel" puts the cube out of pairing mode.</li>
    <li>raw &lt;data&gt;<br>
    Sends the raw &lt;data&gt; to the cube.</li>
    <li>clock<br>
    Sets the internal clock in the cube to the current system time of fhem's machine. You can add<br>
    <code>set ml clock</code><br>
    to your fhem.cfg to do this automatically on startup.</li>
    <li>factorReset<br>
      Reset the cube to factory defaults.</li>
    <li>reconnect<br>
      FHEM will terminate the current connection to the cube and then reconnect. This allows
      re-reading the configuration data from the cube, as it is only send after establishing a new connection.</li>
  </ul>
  <br>

  <a name="MAXLANget"></a>
  <b>Get</b>
  <ul>
  N/A
  </ul>
  <br>
  <br>

  <a name="MAXLANattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li><br>
    <li><a href="#attrdummy">dummy</a></li><br>
    <li><a href="#loglevel">loglevel</a></li><br>
    <li><a href="#addvaltrigger">addvaltrigger</a></li><br>
  </ul>
</ul>

=end html
=cut
