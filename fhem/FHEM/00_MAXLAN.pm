##############################################
# $Id$
# Written by Matthias Gehre, M.Gehre@gmx.de, 2012
package main;

use strict;
use warnings;
use MIME::Base64;
use POSIX;

require "10_MAX.pm";
our %msgCmd2Id;
our %device_types;

sub MAXLAN_Parse($$);
sub MAXLAN_Read($);
sub MAXLAN_Write(@);
sub MAXLAN_ReadSingleResponse($$);
sub MAXLAN_SimpleWrite(@);
sub MAXLAN_Poll($);
sub MAXLAN_Send(@);
sub MAXLAN_SendDeviceCmd($$);
sub MAXLAN_RequestConfiguration($$);
sub MAXLAN_RemoveDevice($$);

my @boost_durations = (0, 5, 10, 15, 20, 25, 30, 60);

my $reconnect_interval = 2; #seconds

#the time it takes after sending one command till we see its effect in the L: response
my $roundtriptime = 3; #seconds

my $read_timeout = 2; #seconds. How long to wait for an answer from the Cube over TCP/IP

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

  if(@a < 3) {
    my $msg = "wrong syntax: define <name> MAXLAN ip[:port] [pollintervall [ondemand]]";
    Log 2, $msg;
    return $msg;
  }

  my $name = shift @a;
  shift @a;
  my $dev = shift @a;
  $dev .= ":62910" if($dev !~ m/:/ && $dev ne "none" && $dev !~ m/\@/);

  if($dev eq "none") {
    Log 1, "$name device is none, commands will be echoed only";
    $attr{$name}{dummy} = 1;
    return undef;
  }
  $hash->{INTERVAL} = $defaultPollInterval;
  $hash->{persistent} = 1;
  if(@a) {
    $hash->{INTERVAL} = shift @a;
    while(@a) {
      my $arg = shift @a;
      if($arg eq "ondemand") {
        $hash->{persistent} = 0;
      } else {
        my $msg = "unknown argument $arg";
        Log 1, $msg;
        return $msg;
      }
    }
  }

  $hash->{cubeTimeDifference} = 99999;
  $hash->{pairmode} = 0;
  $hash->{PARTIAL} = "";
  $hash->{DeviceName} = $dev;
  #This interface is shared with 14_CUL_MAX.pm
  $hash->{SendDeviceCmd} = \&MAXLAN_SendDeviceCmd;
  $hash->{Send} = \&MAXLAN_Send;
  $hash->{RemoveDevice} = \&MAXLAN_RemoveDevice;

  #Wait until all device definitions have been loaded
  InternalTimer(gettimeofday()+1, "MAXLAN_Poll", $hash, 0);
  return undef;
}

sub
MAXLAN_IsConnected($)
{
  return exists($_[0]->{FD});
}


#Disconnects from the Cube. It is safe to call this when already disconnected.
sub
MAXLAN_Disconnect($)
{
  my $hash = shift;
  Log 5, "MAXLAN_Disconnect";
  #All operations here are no-op if already disconnected
  DevIo_CloseDev($hash);
  RemoveInternalTimer($hash);
}

#Connects to the Cube. If already connected, disconnects first.
sub
MAXLAN_Connect($)
{
  my $hash = shift;

  return if(MAXLAN_IsConnected($hash));

  delete($hash->{NEXT_OPEN}); #work around the connection rate limiter in DevIo
  my $ret = DevIo_OpenDev($hash, 0, "");
  if(!MAXLAN_IsConnected($hash)) {
    my $msg = "MAXLAN_Connect: Could not connect";
    Log 2, $msg;
    return $msg;
  }

  #Read initial configuration data
  MAXLAN_ExpectAnswer($hash,"H:");
  MAXLAN_ExpectAnswer($hash,"M:");

  #We first reset the IODev for all MAX devices using this MAXLAN as a backend.
  #Parsing the "C:" responses later on will set IODev correctly again.
  #This effectively removes IODev from all devices that are not longer paired to our Cube.
  foreach (%{$modules{MAX}{defptr}}) {
    $modules{MAX}{defptr}{$_}{IODev} = undef if(defined($modules{MAX}{defptr}{$_}{IODev}) and $modules{MAX}{defptr}{$_}{IODev} == $hash);
  }

  my $rmsg;
  do
  {
    #Receive one "C:" per device
    $rmsg = MAXLAN_ReadSingleResponse($hash, 1);
    MAXLAN_Parse($hash, $rmsg);
  } until($rmsg =~ m/^L:/);
  #At the end, the cube sends a "L:"
  
  #Handle deferred setting of time
  if(AttrVal($hash->{NAME},"set-clock-on-init","1") && $hash->{cubeTimeDifference} > 1) {
    MAXLAN_Set($hash,$hash->{NAME},"clock");
  }

  return undef; 
}


#####################################
sub
MAXLAN_Undef($$)
{
  my ($hash, $arg) = @_;
  #MAXLAN_Write($hash,"q:"); #unnecessary
  MAXLAN_Disconnect($hash);
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
      MAXLAN_Write($hash,"x:", "N:");
    } else {
      my $duration = 60;
      $duration = $args[0] if(@args > 0);
      $hash->{pairmode} = 1;
      MAXLAN_Write($hash,"n:".sprintf("%04x",$duration));
      $hash->{STATE} = "pairing";
    }

  }elsif($setting eq "raw"){
    MAXLAN_Write($hash,$args[0]);

  }elsif($setting eq "clock") {
    #This encodes the winter/summer timezones, its meaning is not entirely clear
    my $timezones = "Q0VUAAAKAAMAAA4QQ0VTVAADAAIAABwg";

    #The offset was obtained by experiment and is up to 1 minute, I don't know exactly what
    #time format the cube uses. Something based on ntp I guess. Maybe this only works in GMT+1?
    my $time = time()-946684774;
    my $rmsg = "v:".$timezones.",".sprintf("%08x",$time);
    my $ret = MAXLAN_Write($hash,$rmsg, "A:");
    Dispatch($hash, "MAX,1,CubeClockState,$hash->{rfaddr},1", {RAWMSG => $rmsg}) if(!$ret);
    return $ret;

  }elsif($setting eq "factoryReset") {
    MAXLAN_RequestReset($hash);

  }elsif($setting eq "reconnect") {
    MAXLAN_Disconnect($hash);
    MAXLAN_Connect($hash) if($hash->{persistent});

  }elsif($setting eq "inject") {
    MAXLAN_Parse($hash,$args[0]);

  }else{
    return "Unknown argument $setting, choose one of pairmode raw clock factoryReset reconnect";
  }
  return undef;
}

sub
MAXLAN_ExpectAnswer($$)
{
  my ($hash,$expectedanswer) = @_;
  my $rmsg = MAXLAN_ReadSingleResponse($hash, 1);

  if(!defined($rmsg)) {
    my $msg = "MAXLAN_ExpectAnswer: Error while waiting for answer $expectedanswer";
    Log 1, $msg;
    return $msg;
  }

  my $ret = undef;
  if($rmsg !~ m/^$expectedanswer/) {
    Log 2, "MAXLAN_ExpectAnswer: Got unexpected response, expected $expectedanswer";
    MAXLAN_Parse($hash,$rmsg);
    return "Got unexpected response, expected $expectedanswer";
  }
  return MAXLAN_Parse($hash,$rmsg);
}


#####################################
sub
MAXLAN_ReadSingleResponse($$)
{
  my ($hash,$waitForResponse) = @_;


  my ($rin, $win, $ein, $rout, $wout, $eout);
  $rin = $win = $ein = '';
  vec($rin,fileno($hash->{TCPDev}),1) = 1;
  $ein = $rin;

  my $maxTime = gettimeofday()+$read_timeout;

  #Read until we have a complete line
  until($hash->{PARTIAL} =~ m/\n/) {

    #Check timeout
    if(gettimeofday() > $maxTime) {
      Log 1, "MAXLAN_ReadSingleResponse: timeout while reading from socket" if($waitForResponse);
      return undef;;
    }

    #Wait for data
    my $nfound = select($rout=$rin, $wout=$win, $eout=$ein, $read_timeout);
    if($nfound == -1) {
      Log 1, "MAXLAN_ReadSingleResponse: error during select, ret = $nfound";
      return undef;
    }
    last if($nfound == 0 and !$waitForResponse);
    next if($nfound == 0); #Sometimes select() returns early, just try again

    #Blocking read
    my $buf;
    my $res = sysread($hash->{TCPDev}, $buf, 256);
    if(!defined($res)){
      Log 1, "MAXLAN_ReadSingleResponse: error during read";
      return undef; #error occured
    }

    #Append data to partial data we got before
    $hash->{PARTIAL} .= $buf;
  }

  my $rmsg;
  ($rmsg,$hash->{PARTIAL}) = split("\n", $hash->{PARTIAL}, 2);
  $rmsg =~ s/\r//; #remove \r
  return $rmsg;
}

my %lhash;

#####################################
#Sends given msg and checks for/parses the answer
sub
MAXLAN_Write(@)
{
  my ($hash,$msg,$expectedAnswer) = @_;
  my $ret = undef;

  MAXLAN_Connect($hash); #It's a no-op if already connected
  MAXLAN_SimpleWrite($hash, $msg);
  $ret = MAXLAN_ExpectAnswer($hash, $expectedAnswer) if($expectedAnswer);
  MAXLAN_Disconnect($hash) if(!$hash->{persistent} && !$hash->{pairmode});
  return $ret;
}

#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub
MAXLAN_Read($)
{
  my ($hash) = @_;

  while(1) {
    my $rmsg = MAXLAN_ReadSingleResponse($hash, 0);
    last if(!$rmsg);
    # The Msg N: .... is the only one that may come spontanously from
    # the cube while we are in pairmode
    Log 2, "Unsolicated response from Cube: $rmsg" unless($hash->{pairmode} and substr($rmsg,0,2) eq "N:");
    MAXLAN_Parse($hash, $rmsg);
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

    return MAXLAN_Write($hash,"m:".sprintf("%02d",$i).",".$package, "A:");
  }
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
      $hash->{cubeTimeDifference} = $difference;
      if($difference > 1) {
        Log 2, "MAXLAN_Parse: Cube thinks it is $cubedatetime->{day}.$cubedatetime->{month}.$cubedatetime->{year} $cubedatetime->{hour}:$cubedatetime->{minute}";
        Log 2, "MAXLAN_Parse: Time difference is $difference minutes";
      }
    } else {
      Log 2, "MAXLAN_Parse: Cube has no time set";
    }

    Dispatch($hash, "MAX,1,define,$hash->{rfaddr},Cube,$hash->{serial},0,1", {RAWMSG => $rmsg});
    Dispatch($hash, "MAX,1,CubeConnectionState,$hash->{rfaddr},1", {RAWMSG => $rmsg});
    Dispatch($hash, "MAX,1,CubeClockState,$hash->{rfaddr},$clockset", {RAWMSG => $rmsg});
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
    }

    #Log $ll5, "Got Metadata, hash: ".Dumper($hash);

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

    Dispatch($hash, "MAX,1,define,$addr,$device_types{$devicetype},$serial,$groupid,1", {RAWMSG => $rmsg});

    if($len != length($bindata)) {
      Dispatch($hash, "MAX,1,Error,$addr,Parts of configuration are missing", {RAWMSG => $rmsg});
      return "Invalid C: response, len does not match";
    }

    #devicetype: Cube = 0, HeatingThermostat = 1, HeatingThermostatPlus = 2, WallMountedThermostat = 3, ShutterContact = 4, PushButton = 5
    #Seems that ShutterContact does not have any configdata
    if($devicetype == 0){#Cube
      #TODO: there is a lot of data left to interpret
    }elsif($devicetype == 1 or $devicetype == 3){#HeatingThermostat or #WallMountedThermostat
      my ($comforttemp,$ecotemp,$maxsetpointtemp,$minsetpointtemp,$tempoffset,$windowopentemp,$windowopendur,$boost,$decalcifiction,$maxvalvesetting,$valveoffset,$weekprofile) = unpack("CCCCCCCCCCCH*",substr($bindata,18));
      #TODO: parse week profile
      my $boostValve = ($boost & 0x1F) * 5;
      my $boostDuration =  $boost_durations[$boost >> 5]; #in minutes
      #There is some trailing data missing, which maps to the weekly program
      $comforttemp /= 2.0; #convert to degree celcius
      $ecotemp /= 2.0; #convert to degree celcius
      $tempoffset = $tempoffset/2.0-3.5; #convert to degree
      $maxsetpointtemp /= 2.0;
      $minsetpointtemp /= 2.0;
      $windowopentemp  /= 2.0;
      $windowopendur   *= 5;
      $maxvalvesetting *= 100/255;
      $valveoffset     *= 100/255;
      my $decalcDay       = ($decalcifiction >> 5) & 0x07;
      my $decalcTime      = $decalcifiction & 0x1F;
      Log $ll5, "comfortemp $comforttemp, ecotemp $ecotemp, boostValve $boostValve, boostDuration $boostDuration, tempoffset $tempoffset, minsetpointtemp $minsetpointtemp, maxsetpointtemp $maxsetpointtemp, windowopentemp $windowopentemp, windowopendur $windowopendur";
      Dispatch($hash, "MAX,1,ThermostatConfig,$addr,$ecotemp,$comforttemp,$boostValve,$boostDuration,$tempoffset,$maxsetpointtemp,$minsetpointtemp,$windowopentemp,$windowopendur,$maxvalvesetting,$valveoffset,$decalcDay,$decalcTime,$weekprofile", {RAWMSG => $rmsg});

    }elsif($devicetype == 4){#ShutterContact
      Log 2, "ShutterContact send some configuration, but none was expected" if($len > 18);
    }else{ #TODO
      Log 2, "Got configdata for unimplemented devicetype $devicetype";
    }

    #Clear Error
    Dispatch($hash, "MAX,1,Error,$addr", {RAWMSG => $rmsg});

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
        }elsif($shash->{type} eq "HeatingThermostat" or $shash->{type} eq "WallMountedThermostat"){
          Dispatch($hash, "MAX,1,ThermostatState,$addr,$payload", {RAWMSG => $rmsg});
        }elsif($shash->{type} eq "ShutterContact"){
          Dispatch($hash, "MAX,1,ShutterContactState,$addr,$payload", {RAWMSG => $rmsg});
        }else{
          Log 2, "Got status for unimplemented device type $shash->{type}";
        }
      } # if($valid)
      $bindata=substr($bindata,$len+1); #+1 because the len field is not counted
    } # while(length($bindata))

  }elsif($cmd eq "N"){#New device paired
    if(@args==0){
      $hash->{STATE} = "initalized"; #pairing ended
      $hash->{pairmode} = 0;
      return undef;
    }
    my ($type, $addr, $serial) = unpack("CH6a[10]", decode_base64($args[0]));
    Log 2, "Paired new device, type $device_types{$type}, addr $addr, serial $serial";
    Dispatch($hash, "MAX,1,define,$addr,$device_types{$type},$serial,0,1", {RAWMSG => $rmsg});

    #After a device has been paired, it automatically appears in the "L" and "C" commands,
    MAXLAN_RequestConfiguration($hash,$addr);
  } elsif($cmd eq "A"){#Acknowledged

  } elsif($cmd eq "S"){#Response to s:
    $hash->{dutycycle} = hex($args[0]); #number of command send over the air
    my $discarded = $args[1];
    $hash->{freememoryslot} = $args[2];
    Log 5, "dutycyle $hash->{dutycycle}, freememoryslot $hash->{freememoryslot}";

    Log 3, "1% rule: we sent too much, cmd is now in queue" if($hash->{dutycycle} == 100 && $hash->{freememoryslot} > 0);
    Log 2, "1% rule: we sent too much, queue is full" if($hash->{dutycycle} == 100 && $hash->{freememoryslot} == 0);
    Log 2, "Command was discarded" if($discarded);
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
    MAXLAN_Disconnect($hash);
  }
}

########################
sub
MAXLAN_DoInit($)
{
  my ($hash) = @_;
  return undef;
}

sub
MAXLAN_RequestList($)
{
  my $hash = shift;
  return MAXLAN_Write($hash, "l:", "L:");
}

#####################################
sub
MAXLAN_Poll($)
{
  my $hash = shift;

  if(MAXLAN_IsConnected($hash)) {
    my $ret = MAXLAN_RequestList($hash);
    Log 1, "MAXLAN_Poll: Did not get any answer" if($ret);
  } else {
    #Connecting gives us a RequestList for free
    my $ret = MAXLAN_Connect($hash);
    if($ret) {
      #Connecting failed
      InternalTimer(gettimeofday()+$reconnect_interval, "MAXLAN_Poll", $hash, 0);
      return;
    }
  }

  MAXLAN_Disconnect($hash) if(!$hash->{persistent} && !$hash->{pairmode});

  InternalTimer(gettimeofday()+$hash->{INTERVAL}, "MAXLAN_Poll", $hash, 0);
}

#This only works for a device that got just paired
sub
MAXLAN_RequestConfiguration($$)
{
  my ($hash,$addr) = @_;
  return MAXLAN_Write($hash,"c:$addr", "C:");
}

sub
MAXLAN_Send(@)
{
  my ($hash, $cmd, $dst, $payload, $flags, $groupId, $msgcnt) = @_;

  $flags = "0"x8 if(!$flags);
  $groupId = "00" if(!defined($groupId));

  if(defined($msgcnt)) {
    Log 2, "MAXLAN_Send: MAXLAN does not support msgcnt";
  }
  return MAXLAN_SendDeviceCmd($hash, pack("H2B8H*","00",$flags,$msgCmd2Id{$cmd}."000000".$dst.$groupId.$payload));
}

#Sends command to a device and waits for acknowledgment
sub
MAXLAN_SendDeviceCmd($$)
{
  my ($hash,$payload) = @_;
  my $ret = MAXLAN_Write($hash,"s:".encode_base64($payload,""), "S:");
  #Reschedule a poll in the near future after the cube will
  #have gotten an answer
  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+$roundtriptime, "MAXLAN_Poll", $hash, 0);
  return $ret;
}

#Resets the cube, i.e. do a factory reset. All pairings will be lost from the cube
#(but you will have to manually reset each individual device.
sub
MAXLAN_RequestReset($)
{
  my $hash = shift;
  return MAXLAN_Write($hash,"a:", "A:");
}

#Remove the device from the cube, i.e. deletes the pairing
sub
MAXLAN_RemoveDevice($$)
{
  my ($hash,$addr) = @_;
  #This does a factoryReset on the Device
  my $ret = MAXLAN_Write($hash,"t:1,1,".encode_base64(pack("H6",$addr),""), "A:");
  if(!defined($ret)) { #success
    #The device is not longer accessable by the Cube
    $modules{MAX}{defptr}{$addr}{IODev} = undef;
  }
  return $ret;
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
  <br>

  <a name="MAXLANdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; MAXLAN &lt;ip-address&gt;[:port] [&lt;pollintervall&gt; [ondemand]]</code><br>
    <br>
    port is 62910 by default. (If your Cube listens on port 80, you have to update the firmware with
    the official MAX! software).
    If the ip-address is called none, then no device will be opened, so you
    can experiment without hardware attached.<br>
    The optional parameter &lt;pollintervall&gt; defines the time in seconds between each polling of data from the cube.<br>
    You may provide the option <code>ondemand</code> forcing the MAXLAN module to tear-down the connection as often as possible
    thus making the cube usable by other applications or the web portal.
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
    <code>attr ml set-clock-on-init</code><br>
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
    <li>set-clock-on-init<br>
      (Default: 1). Automatically call "set clock" after connecting to the cube.
    <li><a href="#do_not_notify">do_not_notify</a></li><br>
    <li><a href="#attrdummy">dummy</a></li><br>
    <li><a href="#loglevel">loglevel</a></li><br>
    <li><a href="#addvaltrigger">addvaltrigger</a></li><br>
  </ul>
</ul>

=end html
=cut
