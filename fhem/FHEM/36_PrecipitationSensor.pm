# $Id$

package main;

use strict;
use warnings;
use Blocking;
use Time::HiRes qw(gettimeofday);
use Time::Local;

sub PrecipitationSensor_Initialize($) {
  my ($hash) = @_;
  
  require "$attr{global}{modpath}/FHEM/DevIo.pm";
  
  $hash->{ReadFn}         = "PrecipitationSensor_Read";
  $hash->{WriteFn}        = "PrecipitationSensor_Write";
  $hash->{ReadyFn}        = "PrecipitationSensor_Ready";
  $hash->{DefFn}          = "PrecipitationSensor_Define";
  $hash->{NotifyFn}       = "PrecipitationSensor_Notify";
  $hash->{FingerprintFn}  = "PrecipitationSensor_Fingerprint";
  $hash->{UndefFn}        = "PrecipitationSensor_Undef";
  $hash->{SetFn}          = "PrecipitationSensor_Set";
  $hash->{AttrFn}         = "PrecipitationSensor_Attr";
  $hash->{AttrList}       = " initCommands"
    ." timeout"
    ." disable:0,1"
    ." $readingFnAttributes";
  
}

#=======================================================================================
sub PrecipitationSensor_Fingerprint($$) {
}

#=======================================================================================
sub PrecipitationSensor_Notify($$) {
  my ($hash, $source_hash) = @_;
  my $name = $hash->{NAME};
  
  my $sourceName = $source_hash->{NAME};
  my $events = deviceEvents($source_hash, 1);
  
  if($sourceName eq "global" && grep(m/^INITIALIZED|REREADCFG$/, @{$events})) {
    PrecipitationSensor_Connect($hash)
  }
  
}

#=======================================================================================
sub PrecipitationSensor_Define($$) {
  my ( $hash, $def ) = @_;
  my @a = split( "[ \t][ \t]*", $def );
  
  my $name   = $a[0];
  my $type   = $a[1];
  my $device = $a[2];
  
  DevIo_CloseDev($hash);
  
  if(@a != 3) {
    my $msg = "wrong syntax: define <name> PrecipitationSensor <hostname:port>";
    Log3 undef, 2, $msg;
    return $msg;
  }
  
  $hash->{DeviceName} = $device;
  $hash->{NAME}       = $name;
  $hash->{TYPE}       = $type;
  $hash->{TIMEOUT}    = 0.5;
  
  if( !defined( $attr{$name}{timeout} ) ) {
    $attr{$name}{timeout} = "60"
  }
  
  PrecipitationSensor_Connect($hash) if($init_done);
  
  return undef;
}

#=======================================================================================
sub PrecipitationSensor_Undef($$) {
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  
  BlockingKill($hash->{helper}{RUNNING_PID}) if(defined($hash->{helper}{RUNNING_PID}));
  
  if($hash->{STATE} ne "disconnected") {
    DevIo_CloseDev($hash);
  }
  
  return undef;
}

#=======================================================================================
sub PrecipitationSensor_LogOTA($) {
  my($text) = @_;
  BlockingInformParent("DoTrigger", ["global", "   $text"], 0);
}

#=======================================================================================
sub PrecipitationSensor_StartUpload($) {
  my ($string) = @_;
  my ($name, $argument) = split("\\|", $string);
  my $hash = $defs{$name};
  
  sleep(2);
  PrecipitationSensor_LogOTA("Started not blocking");
  
  my @deviceName = split('@', $hash->{DeviceName});
  my $port = $deviceName[0];
  my $logFile = AttrVal("global", "logdir", "./log") . "/PrecipitationSensorFlash.log";
  my $hexFile = "./FHEM/firmware/precipitationSensor32.bin";
  
  if(!-e $hexFile) {
    PrecipitationSensor_LogOTA("The file '$hexFile' does not exist");
    return $name;
  }
  
  PrecipitationSensor_LogOTA("flashing PrecipitationSensor $name");
  PrecipitationSensor_LogOTA("hex file: $hexFile");
  
  eval "use LWP::UserAgent";
  if($@) {
    PrecipitationSensor_LogOTA("ERROR: Please install LWP::UserAgent");
    return $name;
  }
  eval "use HTTP::Request::Common";
  if($@) {
    PrecipitationSensor_LogOTA("ERROR: Please install HTTP::Request::Common");
    return $name;
  }
  
  PrecipitationSensor_LogOTA("PrecipitationSensor OTA-update");
  DevIo_CloseDev($hash);
  readingsSingleUpdate($hash, "state", "disconnected", 1);
  PrecipitationSensor_LogOTA("$name closed");
  
  my @spl = split(':', $hash->{DeviceName});
  my $targetIP = $spl[0];
  my $targetURL = "http://" . $targetIP . "/ota/firmware.bin";
  PrecipitationSensor_LogOTA("target: $targetURL");
  
  my $request = POST($targetURL, Content_Type => 'multipart/form-data', Content => [ file => [$hexFile, "firmware.bin"] ]);
  my $userAgent = LWP::UserAgent->new;
  $userAgent->timeout(120);
  PrecipitationSensor_LogOTA("Upload started, please wait a minute or two ...");
  my $response = $userAgent->request($request);
  if ($response->is_success) {
    PrecipitationSensor_LogOTA("");
    PrecipitationSensor_LogOTA("--- Firmware reports ---------------------------------------------------------------------------");
    my @lines = split /\r\n|\n|\r/, $response->decoded_content;
    foreach (@lines) {
      PrecipitationSensor_LogOTA($_);
    }
    PrecipitationSensor_LogOTA("----------------------------------------------------------------------------------------------------");
    
  }
  else {
    PrecipitationSensor_LogOTA("");
    PrecipitationSensor_LogOTA("ERROR: " . $response->code);
    my @lines = split /\r\n|\n|\r/, $response->decoded_content;
    foreach (@lines) {
      PrecipitationSensor_LogOTA($_);
    }
  }
  
  return $name;
}

#=======================================================================================
sub PrecipitationSensor_UploadDone($) {
  my ($name) = @_;
  return unless(defined($name));
  my $hash = $defs{$name};
  delete($hash->{helper}{RUNNING_PID});
  delete($hash->{helper}{FLASHING});
  
  PrecipitationSensor_Connect($hash);
  PrecipitationSensor_LogOTA("$name opened");
  
  PrecipitationSensor_LogOTA("Finshed");
}

#=======================================================================================
sub PrecipitationSensor_UploadError($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  delete($hash->{helper}{RUNNING_PID});
  delete($hash->{helper}{FLASHING});
  PrecipitationSensor_LogOTA("Upload failed");
  PrecipitationSensor_Connect($hash);
  PrecipitationSensor_LogOTA("$name opened");
}

#=======================================================================================
sub PrecipitationSensor_Set($@) {
  my ($hash, @a) = @_;
  my $name = shift @a;
  my $cmd = shift @a;
  my $arg = join(" ", @a);
  
  my $list = "raw connect flash parse reboot treshold calibrate resetPreciAmount savesettings";
  return $list if( $cmd eq '?' || $cmd eq '');
  
  if ($cmd eq "raw") {
    Log3 $name, 4, "set $name $cmd $arg";
    PrecipitationSensor_SimpleWrite($hash, $arg);
  }
  elsif ($cmd eq "flash") {
    CallFn("WEB", "ActivateInformFn", $hash, "global");
    DevIo_CloseDev($hash);
    readingsSingleUpdate($hash, "state", "disconnected", 1);
    $hash->{helper}{FLASHING} = 1;
    $hash->{helper}{RUNNING_PID} = BlockingCall("PrecipitationSensor_StartUpload", $name . "|" . $arg, "PrecipitationSensor_UploadDone", 300, "PrecipitationSensor_UploadError", $hash);
    return undef;
  }
  elsif ($cmd eq "connect") {
    DevIo_CloseDev($hash);
    return PrecipitationSensor_Connect($hash);
  }
  elsif ($cmd eq "reboot") {
    PrecipitationSensor_SimpleWrite($hash, "reboot");
    PrecipitationSensor_Connect($hash);
  }
  elsif ($cmd eq "parse") {
    PrecipitationSensor_Parse($hash, $name, $arg);
  }
  elsif ($cmd eq "treshold") {
    PrecipitationSensor_SimpleWrite($hash, "treshold=$arg");
  }
  elsif ($cmd eq "calibrate") {
    PrecipitationSensor_SimpleWrite($hash, "calibrate");
  }
  elsif ($cmd eq "resetPreciAmount") {
    PrecipitationSensor_SimpleWrite($hash, "resetPreciAmount");
  }
  elsif ($cmd eq "savesettings") {
    PrecipitationSensor_SimpleWrite($hash, "savesettings");
  }
  else {
    return "Unknown argument $cmd, choose one of ".$list;
  }
  
  return undef;
}

#=======================================================================================
sub PrecipitationSensor_DoInit($) {
  my $hash = shift;
  my $name = $hash->{NAME};
  
  my $enabled = AttrVal($name, "disable", "0") != "1" && !defined($hash->{helper}{FLASHING});
  if($enabled) {
    PrecipitationSensor_SimpleWrite($hash, "alive");
    PrecipitationSensor_SimpleWrite($hash, "version");
    readingsSingleUpdate($hash, "state", "opened", 1);
  }
  else {
    readingsSingleUpdate($hash, "state", "disabled", 1);
  }
  
  return undef;
}

#=======================================================================================
sub PrecipitationSensor_Ready($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  PrecipitationSensor_Connect($hash, 1);
  
  # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags);
  if($po) {
    ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  }
  return ($InBytes && $InBytes>0);
}

#=======================================================================================
sub PrecipitationSensor_Write($$)  {
  my ($hash, $cmd, $msg) = @_;
  my $name = $hash->{NAME};
  my $arg = $cmd;
  $arg .= " " . $msg if(defined($msg));
  
  PrecipitationSensor_SimpleWrite($hash, $arg);
}

#=======================================================================================
sub PrecipitationSensor_Read($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  my $buf = DevIo_SimpleRead($hash);
  return "" if(!defined($buf));
  
  my $data = $hash->{PARTIAL};
  $data .= $buf;
  
  while($data =~ m/\n/) {
    my $rmsg;
    ($rmsg, $data) = split("\n", $data, 2);
    $rmsg =~ s/\r//;
    PrecipitationSensor_Parse($hash, $name, $rmsg) if($rmsg);
  }
  $hash->{PARTIAL} = $data;
}

#=======================================================================================
sub PrecipitationSensor_Parse($$$) {
  my ($hash, $name, $msg) = @_;
  my $item = "";
  my $value = "";
  
  next if (!$msg || length($msg) < 1);
  return if ($msg =~ m/[^\x20-\x7E]/);
  
  if ($msg =~ /^alive$/) {
    $hash->{Alive} = TimeNow();
    return;
  }
  
  if ($msg =~ /^version=/) {
    ($item, $value) = split(/=/, $msg, 2);
    $hash->{VERSION} = $value;
    
    if (ReadingsVal($name, "state", "") eq "opened") {
      if (my $initCommandsString = AttrVal($name, "initCommands", undef)) {
        my @initCommands = split(' ', $initCommandsString);
        foreach my $command (@initCommands) {
          PrecipitationSensor_SimpleWrite($hash, $command);
        }
      }
      
      readingsSingleUpdate($hash, "state", "initialized", 1);
    }
    
    return;
  }
  
  if ($msg =~ /^uptime=/) {
    ($item, $value) = split(/=/, $msg, 2);
    $hash->{UPTIME} = $value;
    return;
  }
  
  if ($msg =~ /^data=/) {
    ($item, $value) = split(/=/, $msg, 2);
    
    readingsBeginUpdate($hash);
    
    my @kvPairs;
    my @data = split(',', $value);
    for my $i (0 .. $#data) {
      if (@kvPairs && index($data[$i], "=") == - 1) {
        splice(@kvPairs, @kvPairs - 1, 1, $kvPairs[@kvPairs - 1] . "," . $data[$i]);
      }
      else {
        push(@kvPairs, $data[$i]);
      }
    }
    
    while (@kvPairs) {
      my $kvPairString = shift(@kvPairs);
      my @kvPair = split('=', $kvPairString, 2);
      my $key = $kvPair[0];
      $key =~ s/^\s+|\s+$//g;
      
      readingsBulkUpdate($hash, $key, $kvPair[1]);
    }
    
    readingsEndUpdate($hash, 1);
  }
  
  $hash->{MSGCNT}++;
  $hash->{TIME} = TimeNow();
  readingsSingleUpdate($hash, "state", $hash->{READINGS}{state}{VAL}, 0);
}

#=======================================================================================
sub PrecipitationSensor_SimpleWrite(@) {
  my ($hash, $msg, $nocr) = @_;
  return if(!$hash);
  
  my $name = $hash->{NAME};
  Log3 $name, 5, "SW: $msg";
  
  $msg .= "\n" unless($nocr);
  
  $hash->{USBDev}->write($msg)    if($hash->{USBDev});
  syswrite($hash->{TCPDev}, $msg) if($hash->{TCPDev});
  syswrite($hash->{DIODev}, $msg) if($hash->{DIODev});
  
  # Some linux installations are broken with 0.001, T01 returns no answer
  select(undef, undef, undef, 0.01);
}

#=======================================================================================
sub PrecipitationSensor_Connect($;$) {
  my ($hash, $mode) = @_;
  my $name = $hash->{NAME};
  
  DevIo_CloseDev($hash);
  
  $mode = 0 if!($mode);
  my $enabled = AttrVal($name, "disable", "0") != "1" && !defined($hash->{helper}{FLASHING});
  if($enabled) {
    $hash->{nextOpenDelay} = 2;
    my $ret = DevIo_OpenDev($hash, $mode, "PrecipitationSensor_DoInit");
    return $ret;
  }
  
  return undef;
}

#=======================================================================================
sub PrecipitationSensor_StartConnectTimer($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  my $interval = AttrVal($name, "timeout", undef);
  if(defined($interval)) {
    InternalTimer(gettimeofday() + $interval / 2, "PrecipitationSensor_OnConnectTimer", $hash, 0);
  }
  
}

#=======================================================================================
sub PrecipitationSensor_OnConnectTimer($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  RemoveInternalTimer($hash, "PrecipitationSensor_OnConnectTimer");
  
  my $interval = AttrVal($name, "timeout", undef);
  if(defined($interval)) {
    PrecipitationSensor_StartConnectTimer($hash);
    
    if(AttrVal($name, "disable", "0") != "1" && !defined($hash->{helper}{FLASHING})) {
      my ($date, $time, $year, $month, $day, $hour, $min, $sec, $timestamp, $alive);
      PrecipitationSensor_SimpleWrite($hash, "alive");
      PrecipitationSensor_SimpleWrite($hash, "uptime");
      $alive = $hash->{Alive};
      $alive = "2000-01-01 00:00:00" if !$alive;
      
      ($date, $time) = split( ' ', $alive);
      ($year, $month, $day) = split( '-', $date);
      ($hour, $min, $sec) = split( ':', $time);
      $month -= 01;
      $timestamp = timelocal($sec, $min, $hour, $day, $month, $year);
      
      if (gettimeofday() - $timestamp > $interval +2) {
        return PrecipitationSensor_Connect($hash, 1);
      }
      
    }
    
  }
}

#=======================================================================================
sub PrecipitationSensor_Attr(@) {
  my ($cmd, $name, $aName, $aVal) = @_;
  my $hash = $defs{$name};
  
  if ($aName eq "timeout") {
    RemoveInternalTimer($hash, "PrecipitationSensor_OnConnectTimer");
    if($aVal) {
      PrecipitationSensor_SimpleWrite($hash, "alive");
      PrecipitationSensor_StartConnectTimer($hash);
    }
  }
  elsif ($aName eq "disable") {
    if($aVal eq "1") {
      DevIo_CloseDev($hash);
      readingsSingleUpdate($hash, "state", "disabled", 1);
    }
    else {
      if($hash->{READINGS}{state}{VAL} eq "disabled") {
        readingsSingleUpdate($hash, "state", "disconnected", 1);
        PrecipitationSensor_Connect($hash, 1);
        PrecipitationSensor_StartConnectTimer($hash);
      }
    }
  }
  
  return undef;
}


#=======================================================================================
1;

=pod
=item summary    Radar PrecipitationSensor
=item summary_DE Radar PrecipitationSensor
=begin html

<a name="PrecipitationSensor"></a>
<h3>PrecipitationSensor</h3>
<ul>
  For more information about the PrecipitationSensor see here: <a href="https://forum.fhem.de/index.php?topic=73016.0">FHEM thread</a>
  <br><br>

  <a name="PrecipitationSensor_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; PrecipitationSensor &lt;device&gt;</code> <br>
    &lt;device&gt; specifies the network device<br>
    Normally this is the IP-address and the port in the form ip:port<br>
    Example: 192.168.1.100:81<br>
    <br>
  </ul>

  <a name="PrecipitationSensor_Set"></a>
  <b>Set</b>
  <ul>
    <li>raw &lt;data&gt;<br>
        send &lt;data&gt; to the PrecipitationSensor.
    </li><br>

    <li>connect<br>
        tries to (re-)connect to the PrecipitationSensor. It does not reset the PrecipitationSensor but only try to get a connection to it.
    </li><br>

    <li>reboot<br>
    Reboots the PrecipitationSensor. Works only if we are connected (state is opened or initialized)
    </li><br>
	
	<li>calibrate<br>
  Calibrates and saves the threshold levels of the PrecipitationSensor. Works only if we are connected (state is opened or initialized)</br>
  How to perform a calibration:</br>
  1.) Place the sensor in a location with absolutely no motion within a radius of at least 3 meters<br>
  2.) Set the "Publish interval" on the web interface to 60 seconds</br>
  3.) Wait for at least 120 seconds before calling the "calibrate" command</br>
  4.) The calibrated threshold levels "GroupMagThresh" will be updated after the next Publish interval cycle
  </li><br>
  
    <li>restPreciAmount<br>
    Resets the amount of precipitation. Works only if we are connected (state is opened or initialized)
    </li><br>
	
	<li>savesettings<br>
    Saves the changes to flash. Works only if we are connected (state is opened or initialized)
    </li><br>

    <li>flash<br>
      This provides a way to flash it directly from FHEM.
    </li><br>
    
  </ul>

  <a name="PrecipitationSensor_Get"></a>
  <b>Get</b>
  <ul>
  ---
  </ul>
  <br>

  <a name="PrecipitationSensor_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>initCommands<br>
      Space separated list of commands to send for initialization.
    </li><br>

    <li>timeout<br>
      format: &lt;timeout&gt<br>
      Asks the PrecipitationSensor every timeout seconds if it is still alive. If there is no response it reconnects to the PrecipitationSensor.<br>
    </li><br>

    <li>disable<br>
      if disabled, it does not try to connect
    </li><br>


  </ul>
  <br>
</ul>

=end html
=cut