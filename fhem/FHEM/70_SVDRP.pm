########################################################################################
# $Id$
#
# SVDRP 
#
# control VDR via SVDRP
# refer to http://www.vdr-wiki.de/wiki/index.php/VDR_Optionen
#
# version history
#    1.01.01      first released version
#
########################################################################################
#
#  This programm is free software; you can redistribute it and/or modify
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
########################################################################################
  
package main;
use strict;
use warnings;

use Socket;     # For constants like AF_INET and SOCK_STREAM
#use Encode qw(encode);

use Blocking;
use Time::HiRes qw(gettimeofday);
use POSIX;

my $version = "1.01.01";

my %SVDRP_gets = (
  #
);

# Raw is not used by now
my %SVDRP_defaultsetsRaw = (
  "HITK"     => "",
  "LSTT"     => ":get",
  "LSTR"     => ":get",
  "NEXT"     => ":get",
  "STAT"     => ":disk",
  "UPDR"     => ":get",
  "CHAN"     => ":+,-",
  "DELT"     => "",
  "VOLU"     => ":+,-,mute",
  "cleanUp"  => ":noArg",
  "closeDev" => ":noArg",
  "connect"  => ":noArg"
);

my %SVDRP_defaultsets = (
  "HitKey"            => "",
  "ListTimers"        => ":noArg",
  "NextTimer"         => ":noArg",
  "DiskStatus"        => ":noArg",
  "UpdateRecordings"  => ":get",
  "Channel"           => ":+,-",
  "DeleteTimer"       => "",
  "Volume"            => ":+,-,mute",
  "cleanUp"           => ":noArg",
  "closeDev"          => ":noArg",
  "connect"           => ":noArg",
  "PowerOff"          => ":noArg",
  "ListRecording"     => "",
  "GetAll"            => ":noArg"
);

my %SVDRP_defaultsets_unused = (
  "ListRecordings"    => ":get"
);

my %SVDRP_cmdmap = (
  "HitKey"           => "HITK",
  "ListTimers"       => "LSTT",
  "NextTimer"        => "NEXT",
  "DiskStatus"       => "STAT",
  "UpdateRecordings" => "UPDR",
  "Channel"          => "CHAN",
  "DeleteTimer"      => "DELT",
  "Volume"           => "VOLU",
  "ListRecording"    => "LSTR"
);

my @SVDRP_statusCmds = ("LSTT", "NEXT", "CHAN", "VOLU", "STAT");

my %SVDRP_cmdmap_unused = (
  "ListRecordings" => "LSTR"
);

my %SVDRP_data = (
  #
);

my %SVDRP_result;
my %SVDRPaddattrs;

my %SVDRP_sets = %SVDRP_defaultsets;

sub SVDRP_Define {
  my ($hash, $def) = @_;
  my @param = split('[ \t]+', $def);
    
  if(int(@param) < 3) {
    return "too few parameters: define <name> SVDRP <IP_Address> [<port>]";
  }
  $hash->{NAME}       = $param[0];
  $hash->{IP_Address} = $param[2];
  if (!$param[3]){
    $hash->{port}     = "6419";
  }
  else{
    $hash->{port}     = $param[3];
  }
  $hash->{DeviceName} = $param[2].":".$hash->{port};
  
  # prevent "reappeared" messages in loglevel 1
  $hash->{devioLoglevel} = 3;
  # prevent DevIO from setting "STATE" at connect/disconnect
  $hash->{devioNoSTATE} = 1;
  # subscribe only to notify from global and self
  $hash->{NOTIFYDEV} = "global,TYPE=SVDRP";
  
  my $name = $hash->{NAME}; 
  
  # clean up
  RemoveInternalTimer($hash, "SVDRP_checkConnection");
  DevIo_CloseDev($hash);

  # force immediate reconnect
  delete $hash->{NEXT_OPEN} if ( defined( $hash->{NEXT_OPEN} ) );
  # commented to not automatically connect...
  #DevIo_OpenDev($hash, 0, "SVDRP_Init", "SVDRP_Callback");

  return ;
}

sub SVDRP_Undef {
  my ($hash, $arg) = @_; 
  RemoveInternalTimer($hash);
  BlockingKill( $hash->{helper}{RUNNING_PID} ) if ( defined( $hash->{helper}{RUNNING_PID} ) );
  DevIo_CloseDev($hash);
  return ;
}

sub SVDRP_Shutdown {
  my ($hash) = @_;
  my $name = $hash->{NAME}; 
  RemoveInternalTimer($hash);
  DevIo_CloseDev($hash);
  BlockingKill( $hash->{helper}{RUNNING_PID} ) if ( defined( $hash->{helper}{RUNNING_PID} ) );
  delete $hash->{helper}{nextConnectionCheck} if ( defined( $hash->{helper}{nextConnectionCheck} ) );
  delete $hash->{helper}{nextStatusCheck} if ( defined( $hash->{helper}{nextStatusCheck} ) );
  delete $hash->{helper}{RUNNING_PID} if ( defined( $hash->{helper}{RUNNING_PID} ) );
}

sub SVDRP_Initialize {
    my ($hash) = @_;

    $hash->{DefFn}      = \&SVDRP_Define;
    $hash->{UndefFn}    = \&SVDRP_Undef;
    $hash->{SetFn}      = \&SVDRP_Set;
    $hash->{AttrFn}     = \&SVDRP_Attr;
    $hash->{ReadFn}     = \&SVDRP_Read;
    $hash->{ReadyFn}    = \&SVDRP_Ready;
    $hash->{NotifyFn}   = \&SVDRP_Notify;
    #$hash->{StateFn}    = \&SVDRP_State;
    $hash->{ShutdownFn} = \&SVDRP_Shutdown;
    #$hash->{GetFn}      = \&SVDRP_Get;   # not required
    #$hash->{DeleteFn}   = \&SVDRP_Delete;
    #$hash->{RenameFn}   = \&SVDRP_Rename;
    #$hash->{DelayedShutdownFn} = \&SVDRP_DelayedShutdown;
    
    $hash->{AttrList} =
          "delay:1,2,3,4,5 RecordingInfo:short,long connectionCheck:off,1,15,30,60,120,300,600,3600 AdditionalSettings statusCheckCmd statusCheckInterval:off,1,5,10,15,30,60,300,600,3600 statusOfflineMsg disable:0,1 "
        . $readingFnAttributes;
}

sub SVDRP_Notify($$) {
  my ($hash, $devHash) = @_;
  my $name = $hash->{NAME}; # own name / hash
  my $devName = $devHash->{NAME}; # Device that created the events
  my $checkInterval;
  my $next;

  if(IsDisabled($name)){
    main::Log3 $name, 5, "[$name]: Notify: $name is disabled by framework!";
    return;
  }

  my $events = deviceEvents($devHash,1);
  #return if( !$events );

  # logging of notifies
  #main::Log3 $name, 5, "[$name]: running notify from $devName for $name, event is @{$events}";
  
  if($devName eq "global" && grep(m/^INITIALIZED|REREADCFG$/, @{$events})){    
    
    if ( defined( $hash->{AdditionalSettings} ))
    {
      SVDRP_Attr("set",$name,"AdditionalSettings",$hash->{AdditionalSettings});
      main::Log3 $name, 5, "adding attrs: $name, ".$hash->{AdditionalSettings};
    }  
  }
  return;
}

sub SVDRP_Attr {
  my ($cmd,$name,$attr_name,$attr_value) = @_;
	my $hash = $defs{$name};
  my $checkInterval;
  my $next;
  main::Log3 $name, 5,"[$name]: Attr: executing $cmd $attr_name to $attr_value";
	if($cmd eq "set") {
    if ($attr_name eq "AdditionalSettings") {
      my @valarray = split / /, $attr_value;
      my $key;
      my $newkey;
      my $newkeyval = "";
      %SVDRPaddattrs = ();
      $hash->{AdditionalSettings} = $attr_value;
      foreach $key (@valarray) {
        #main::Log3 $name, 3,"[$name]: key is $key";
        $newkey = (split /:/, $key, 2)[0];
        # check if AdditionalSetting is only cmd (e.g. "LSTR") without parameter (e.g. ":1,2,3")
        # otherwise take it as ""
        if (defined ((split /:/, $key, 2)[1])){
          $newkeyval = ":".(split /:/, $key, 2)[1];
        }
        main::Log3 $name, 5,"[$name]: Attr: setting $attr_name, key  is $newkey, val is $newkeyval";
        $SVDRPaddattrs{$newkey} = $newkeyval;
        %SVDRP_sets = (%SVDRP_sets, %SVDRPaddattrs);
      }
    }
    elsif ($attr_name eq "connectionCheck"){
      if ($attr_value eq "0") {
        # avoid 0 timer
        return "0 not allowed for $attr_name!";
      } 
      elsif ($attr_value eq "off"){
        RemoveInternalTimer($hash, "SVDRP_checkConnection");
        $hash->{helper}{nextConnectionCheck} = "off";
      }
      else{
        RemoveInternalTimer($hash, "SVDRP_checkConnection");
        $checkInterval = $attr_value;
        $next = gettimeofday() + $checkInterval;
        $hash->{helper}{nextConnectionCheck} = $next;
        InternalTimer( $next, "SVDRP_checkConnection", $hash);
        main::Log3 $name, 5,"[$name]: Attr: set $attr_name interval to $attr_value";        
      }
    }
    elsif ($attr_name eq "statusCheckInterval"){
      # timer to check status of device
      if ($attr_value eq "0") {
        # 0 means off
        return "0 not allowed for $attr_name!";
      } 
      elsif ($attr_value eq "off"){
        RemoveInternalTimer($hash, "SVDRP_checkStatus");
        $hash->{helper}{nextStatusCheck} = "off";
      }
      else{
        RemoveInternalTimer($hash, "SVDRP_checkStatus");
        $checkInterval = $attr_value;
        $next = gettimeofday() + $checkInterval;
        $hash->{helper}{nextStatusCheck} = $next;
        InternalTimer( $next, "SVDRP_checkStatus", $hash);
        main::Log3 $name, 5,"[$name]: Attr: set $attr_name interval to $attr_value";        
      }
    }
    elsif ($attr_name eq "StatusCheckCmd"){
      # decided not to check for allowed commands, user's freedom to define...
    }        
  }
  elsif($cmd eq "del"){
    if($attr_name eq "AdditionalSettings") {
      %SVDRPaddattrs = ();
      %SVDRP_sets = %SVDRP_defaultsets;
      main::Log3 $name, 5,"[$name]: Attr: deleting $attr_name";
    }
    elsif($attr_name eq "connectionCheck") {
      RemoveInternalTimer($hash, "SVDRP_checkConnection");
      delete $hash->{helper}{nextConnectionCheck} if (defined($hash->{helper}{nextConnectionCheck}));
      # next 4 lines to set default value 600, timer running ech 600s
      #my $next = gettimeofday() + "600";
      #$hash->{helper}{nextConnectionCheck} = $next;
      #InternalTimer( $next, "SVDRP_checkConnection", $hash);
      #main::Log3 $name, 5,"[$name]: Attr: $attr_name removed, timer set to +600";
    }
    elsif($attr_name eq "statusCheckInterval") {
      RemoveInternalTimer($hash, "SVDRP_checkStatus");
      delete $hash->{helper}{nextStatusCheck} if (defined($hash->{helper}{nextStatusCheck}));
      # next 4 lines to set default value 600, timer running ech 600s
      #my $next = gettimeofday() + "600";
      #$hash->{helper}{nextStatusCheck} = $next;
      #InternalTimer( $next, "SVDRP_checkStatus", $hash);
      #main::Log3 $name, 5,"[$name]: Attr: $attr_name removed, timer set to +600";
    }
    elsif($attr_name eq "statusCheckInterval") {
      # do nothing
    }    
  }
  return ;
}

sub SVDRP_Ready($){
  my ($hash) = @_;
  #return DevIo_OpenDev($hash, 1, undef );  
}

sub SVDRP_State($$$$){
  # not needed ... ?
  my ($hash, $time, $readingName, $value) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 5, "[$name] SetState called";  
  return undef;
}

sub SVDRP_Get {
	# return immediately, not required currently
    return "none";
}

sub SVDRP_cleanUp {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  main::Log3 $name, 5, "[$name]: cleanup: sending quit, close DevIo";
  DevIo_SimpleWrite($hash, "quit\r\n", "2");    
  RemoveInternalTimer($hash);
  BlockingKill( $hash->{helper}{RUNNING_PID} ) if ( defined( $hash->{helper}{RUNNING_PID} ) );
  delete $hash->{helper}{RUNNING_PID} if ( defined( $hash->{helper}{RUNNING_PID} ) );
  # give VDR 1 s to react before we close connection
  my $next = gettimeofday() + 3;
  InternalTimer( $next, "SVDRP_closeDev", $hash);
  #DevIo_CloseDev($hash);
  #$hash->{STATE} = "closed";
  #$hash->{PARTIAL}="";
  return ;
}

sub SVDRP_closeDev {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  main::Log3 $name, 5,"[$name]: closeDev: closing...";
  delete $hash->{DevIoJustClosed} if (defined($hash->{DevIoJustClosed}));
  DevIo_CloseDev($hash);
  $hash->{STATE} = "closed";
  $hash->{PARTIAL}="";
}

sub SVDRP_Init($){
  # default: no action - here we just could initializes connection check
  my ($hash) = @_;
  my $name = $hash->{NAME};
  main::Log3 $name, 5,"[$name]: Init: DevIo initializing";
  # my $checkInterval = AttrVal( $name, "connectionCheck", "60" );
  # #set checkInterval to 60 just for first check;
  # if ($checkInterval eq "off"){$checkInterval = 60;}
    
  RemoveInternalTimer($hash, "SVDRP_checkConnection");
    
  # my $next = gettimeofday() + $checkInterval;
  # InternalTimer($next , "SVDRP_checkConnection", $hash);
  # #SVDRP_singleWrite("VDRcontrol|STAT|disk");  
  return undef; 
}

sub SVDRP_ReInit($){
  # no action - just log subroutine call
  my ($hash) = @_;
  my $name = $hash->{NAME};
  main::Log3 $name, 5,"[$name]: ReInit: DevIo ReInit done"; 
  return undef; 
}

sub SVDRP_Callback($){
    # will be executed after connection establishment (see DevIo_OpenDev())
    my ($hash, $error) = @_;
    my $name = $hash->{NAME};

    if ($error){
      main::Log3 $name, 3, "[$name] DevIo callback error: $error";
    }
    else{
      main::Log3 $name, 3, "[$name] DevIo callback with no error";
    }
    
    #my $status = $hash->{STATE};
    my $status = DevIo_getState($hash);
    my $offlineMsg = AttrVal( $name, "statusOfflineMsg", "offline" );
    if ($status eq "disconnected"){
      # remove timers and pending setValue calls if device is disconnected
      main::Log3 $name, 3, "[$name] DevIo callback error: STATE is $status";
      my $rv = readingsSingleUpdate($hash, "globalError", $offlineMsg, 1);
      RemoveInternalTimer($hash);
      delete $hash->{helper}{nextConnectionCheck}
      if ( defined( $hash->{helper}{nextConnectionCheck} ) );
      delete $hash->{helper}{nextStatusCheck}
      if ( defined( $hash->{helper}{nextStatusCheck} ) );
      BlockingKill( $hash->{helper}{RUNNING_PID} ) if ( defined( $hash->{helper}{RUNNING_PID} ) );

      # check if we should update statusCheck
      my $checkInterval = AttrVal( $name, "statusCheckInterval", "off" );
      my $checkcmd = AttrVal( $name, "statusCheckCmd", "DiskStatus" );
      #my $offlineMsg = AttrVal( $name, "statusOfflineMsg", "offline" );
  
      if ($checkInterval ne "off"){
        my $rv = readingsSingleUpdate($hash, $checkcmd, $offlineMsg, 1);
        main::Log3 $name, 5,"[$name]: [$name] DevIo callback: $checkcmd set to $offlineMsg";
        return ;
      }      
    }    
    return undef; 
}

sub SVDRP_Read($){
  # used by devio
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  # read the available data
  my $data = DevIo_SimpleRead($hash);
  Log3 $name, 5, "[$name] Read function called";
  # stop processing if no data is available (device disconnected)
  return if(!defined($data)); # connection lost
  
  #Log3 $name, 5, "[$name] Read received: $data";

  my $buffer = $hash->{PARTIAL};
  #Log3 $name, 3, "[$name] Read: received $data (buffer contains: $buffer)";
  
  # concat received data to $buffer
  my $result = $data;
  $buffer .= $result;
  Log3 $name, 5, "[$name] Read: received: $result";
  Log3 $name, 5, "[$name] Read: buffer contains: $buffer";

  # as long as the buffer contains newlines (complete datagramm)
  my $msg = "none";
   while($buffer =~ m/\n/)
   {
     #my $msg;
     # extract the complete message ($msg), everything else is assigned to $buffer
     ($msg, $buffer) = split("\n", $buffer, 2);
     # remove trailing whitespaces
     chomp $msg;
     # now we could parse the extracted message, not implemented, since I get no data...
     SVDRP_parseMessage($hash, $msg);
   }
  # update $hash->{PARTIAL} with the current buffer content
  $hash->{PARTIAL} = $buffer;
  #Log3 $name, 5, "[$name] Read: after LF check, msg is: $msg";
  #Log3 $name, 5, "[$name] Read: after LF check, buffer contains: $buffer"; 
}

sub SVDRP_parseMessage {
  # called from Read with $hash, $msg
  # $msg contains one complete line - but one only!
  my ($hash, $msg) = @_;
  my $name = $hash->{NAME};
  #my ($input) = @_;
  #Log3 "VDR", 5, "[VSR] Parse: input: $input";
  #my ($name, $msg) = split "|", $input;
  Log3 $name, 5, "[$name] Parse: name: $name, msg: $msg";
  #my $hash = $defs{$name};
  #$msg = $hash->{PARTIAL};
  # strip last "|"
  #$msg = substr $msg, 0, -1;
  #my @resultarr = split("\\|", $msg);
  my $reading = "(unknown)";
  my $data;
  my $rv;
  my $count = 0;
  my $output;
  my $timers = "";
  my $parsedmsg = "";
  my $code;
  my $recording = "";
   
  readingsBeginUpdate($hash);
   
  ### now we should analyse which message was received, and put it to the right reading
  #if ($msg =~ /^22[0|1]/){
  if ($msg =~ /^220/){
    # format: 220 VDR SVDRP VideoDiskRecorder 2.0.6; Sun Feb 13 17:33:10 2022; UTF-8
    $reading = "infoOpen";
    (my $code, $msg) = split (/ /, $msg, 2);
    $rv = readingsSingleUpdate($hash, $reading, $msg, 1);
    #Log3 $name, 5, "[$name] Parse: updated $reading with '$msg'";
  }
  elsif ($msg =~ /^221/){
    # format: 220 VDR SVDRP VideoDiskRecorder 2.0.6; Sun Feb 13 17:33:10 2022; UTF-8
    $reading = "infoClose";
    (my $code, $msg) = split (/ /, $msg, 2);
    $rv = readingsSingleUpdate($hash, $reading, $msg, 1);
    #Log3 $name, 5, "[$name] Parse: updated $reading with '$msg'";
  }  
  elsif ($msg =~ /^5\d\d/){
    # format: 5xx some error message
    $reading = "infoError";
    (my $code, $msg) = split (/ /, $msg, 2);
    $rv = readingsSingleUpdate($hash, $reading, $msg, 1);
    #Log3 $name, 5, "[$name] Parse: updated $reading with '$msg'";
  }
  elsif ($msg =~ /^250[ ]\d+MB[ ]\d+MB[ ]\d+%\s$/){
    # disk status format: 250 1760874MB 476308MB 72%  
    $reading = "DiskStatus";
    #$rv = readingsSingleUpdate($hash, $reading, $msg, 1);
    SVDRP_parseDiskStatus($hash, $reading, $msg);
    #Log3 $name, 5, "[$name] Parse: updated $reading with '$msg'";    
  }
  elsif ($msg =~ /^250[ ]\d+[ ][A-Za-z]{3}[ ][A-Za-z]{3}[ ][1-9]{2}[ ][0-9]{2}:[0-9]{2}:[0-9]{2}[ ][0-9]{4}\s$/){  
    # next timer format: 250 1 Tue Mar 15 09:50:00 2022
    $reading = "NextTimer";
    (my $code, $msg) = split (/ /, $msg, 2);
    $rv = readingsSingleUpdate($hash, $reading, $msg, 1);
    #Log3 $name, 5, "[$name] Parse: updated $reading with $msg";    
  }  
  elsif ($msg =~ /^250[ ]\d+[ ][A-Za-z0-9\h\.\-_?!#]+\s$/){
    # Channel format: 250 4 RTL Television
    $reading = "Channel";
    (my $code, $msg) = split (/ /, $msg, 2);
    #$msg = substr $msg, 0, -1;
    $rv = readingsSingleUpdate($hash, $reading, $msg, 1);
    #Log3 $name, 5, "[$name] Parse: updated $reading with $msg"
  }
  elsif ($msg =~ /^250[ ]Audio[ ]volume[ ]is[ ][0-9]+|mute\s$/){
    # Vol format: 250 Audio volume is 245
    $reading = "Volume";
    (my $code, $msg) = split (/ /, $msg, 2);
    $rv = readingsSingleUpdate($hash, $reading, $msg, 1);
    #Log3 $name, 5, "[$name] Parse: updated $reading with $msg"
  }
  elsif ($msg =~ /^250[ ]Key[ ][A-Za-z0-9"]+[ ]accepted\s$/){
    # HitKey format: 250 Key "up" accepted
    $reading = "HitKey";
    (my $code, $msg) = split (/ /, $msg, 2);
    $rv = readingsSingleUpdate($hash, $reading, $msg, 1);
    #Log3 $name, 5, "[$name] Parse: updated $reading with $msg"
  }
  elsif ($msg =~ /^250[-|\h]\d+[ ]\d+:\d+:[A-Za-z-]{7}/ ||
        $msg =~ /^250[-|\h]\d+[ ]\d+:\d+:\d{4}-\d{2}-\d{2}:\d{4}:\d{4}:\d{2}:\d{2}:[A-Za-z0-9-_!?\.\h]+:\s$/){
    # ListTimer formats:
    # 250 1 1:1:MTWTF--@2022-03-15:0950:1115:50:99:Verrückt nach Meer (neu):
    # 250 2 1:4:2022-02-13:1858:1915:50:99:RTL Aktuell - Das Wetter:
    $reading = "ListTimers";
    # check if we got "250-n"
    if (substr($msg, 3, 1) eq "-"){
      ($code, $msg) = split (/-/, $msg, 2);
      #Log3 $name, 5, "[$name] Parse: substring contains '-'";
    }
    else{
      ($code, $msg) = split (/ /, $msg, 2);
    }
    $timers = ReadingsVal($name, $reading, "");
    $msg = SVDRP_parseTimer($name, $msg);
    #Log3 $name, 5, "[$name] Parse: parseTimer returned $msg";
    $msg = $timers."\n".$msg;
    $rv = readingsSingleUpdate($hash, $reading, $msg, 1);
    #Log3 $name, 5, "[$name] Parse: updated $reading with $parsedmsg"
  }
  elsif ($msg =~ /^250-\d+\h[0-9]{2}\.[0-9]{2}\.[0-9]{2}\h[0-9]{2}:[0-9]{2}\h/){
    # Recording List format:
    # 250-84 26.02.20 16:05v 1:25* Verrückt nach Meer~Staffel 09
    $reading = "Recordings";
    # check if we got "250-n"
    if (substr($msg, 3, 1) eq "-"){
      ($code, $msg) = split (/-/, $msg, 2);
      #Log3 $name, 5, "[$name] Parse: substring contains '-'";
    }
    else{
      ($code, $msg) = split (/ /, $msg, 2);
    }
    $recording = ReadingsVal($name, $reading, "");
    $msg = $recording."\n".$msg;    
    $rv = readingsSingleUpdate($hash, $reading, $msg, 1);
    #Log3 $name, 5, "[$name] Parse: updated $reading with $msg"        
  }
  elsif ($msg =~ /^215/){
    # Recording format: 215-xxxx
    $reading = "Recordings";
    # check if we got "215-n"
    if (substr($msg, 3, 1) eq "-"){
      ($code, $msg) = split (/-/, $msg, 2);
      #Log3 $name, 5, "[$name] Parse: substring contains '-'";
    }
    else{
      ($code, $msg) = split (/ /, $msg, 2);
    }
    $recording = ReadingsVal($name, $reading, "");
    $msg = SVDRP_parseRecording($name, $msg);
    if ($msg ne "none"){
      $msg = $recording."\n".$msg;
      $rv = readingsSingleUpdate($hash, $reading, $msg, 1);
      Log3 $name, 5, "[$name] Parse: updated $reading with '$msg'";    
    }
    #$rv = readingsSingleUpdate($hash, $reading, $msg, 1);
    #Log3 $name, 5, "[$name] Parse: updated $reading with $msg"
  }
  #Log3 $name, 5, "[$name] Parse: updated $reading with '$msg'";
}

sub SVDRP_parseDiskStatus{
  my ($hash,$reading,$resultarr) = @_;
  my $name = $hash->{NAME};
  my ($code, $disksize, $diskfree, $diskspace) = (split (" ", $resultarr,4));
  my $sizeunit = "GB";
  my $freeunit = "GB";
  my $rv;
  # strip unit "MB", keep only numbers
  $disksize =~ tr/0-9//cd;
  $diskfree =~ tr/0-9//cd;
  Log3 $name, 5, "[$name] Parse: Disksize: $disksize, Diskfree: $diskfree";
  $disksize = $disksize / 1024;
  if ($disksize > 1000){
    $disksize = sprintf ("%.1f", $disksize / 1024);
    $sizeunit = "TB";
  }
  else{
    $disksize = sprintf ("%.1f", $disksize);
  }
  $diskfree = $diskfree / 1024;
  if ($diskfree > 1000){
    $diskfree = $diskfree / 1024;
    $freeunit = "TB";
  }
  else{
    $diskfree = sprintf ("%.1f", $diskfree);
  }       
  my $returnval = "Size: ".$disksize.$sizeunit." | Free: ".$diskfree.$freeunit." | Used: ".$diskspace; 
  readingsBeginUpdate($hash);
  $rv = readingsBulkUpdate($hash, "DiskUsed", $diskspace, 1);
  $rv = readingsBulkUpdate($hash, $reading, $returnval, 1);
  readingsEndUpdate($hash, 1);
  #$rv = readingsBulkUpdate($hash, $reading, $resultarr[0], 1);
}

sub SVDRP_parseTimer{
  my ($name, $msg) = @_;
  #$count = 0;
  #$output = "";
  my $parsedmsg = "none";
  my $timerid = "0";
  my $timerstr = "none";
  my $i1 = "0";
  my $i2 = "0",
  my $day = "none";
  my $start = "0";
  my $end = "0";
  my $i3 = "0";
  my $i4 = "0";
  my $timername = "none";
  if (!defined($msg)){
    $parsedmsg = "error";
  }
  else{
    # format variants:
    # 1 1:1:MTWTF--@2022-03-15:0950:1115:50:99:Verrückt nach Meer (neu):
    # 2 1:4:2022-02-13:1858:1915:50:99:RTL Aktuell - Das Wetter:
    #Log3 $name, 5, "[$name] ParseTimer: reading: $reading, result: $resultarr[$count]";
    ($timerid, $timerstr) = split (" ", $msg,2);
    ($i1, $i2, $day, $start, $end, $i3, $i4, $timername) = split (":", $timerstr, 8);
    substr ($start, 2, 0) = ":";
    substr ($end, 2, 0) = ":";
    #$output .= "\n" if ($count > 0); # add LF only if first line is contained 
    $parsedmsg = "ID: ".sprintf("%2s",$timerid)." | Day: ".sprintf("%-10s",$day)." | Start: ".$start." | Stop: ".$end." | Name: ".$timername;
  }
  #Log3 $name, 5, "[$name] parseTimer: parsed output is $parsedmsg";
  return $parsedmsg;
}

sub SVDRP_parseRecording {
   my ($name, $msg) = @_;
   my $type = "none";
   my $recinfo = AttrVal($name,"RecordingInfo","short");
   if ($recinfo eq "short") {
     #
     #T Löwengrube (Title)
     #S Tigerbande (Subtitle)
     #D August 1950 (Description)
     if (substr($msg, 0, 1) eq "T"){
       #$type = "Title:       ";       
       $type = "- ";       
     }
     elsif (substr($msg, 0, 1) eq "S"){
       #$type = "Subtitle:    ";       
       $type = "- ";       
     }
     elsif (substr($msg, 0, 1) eq "D"){
       #$type = "Description: ";       
       $type = "";
       # add newlines after next space after $lf characters
       #$msg = join ("\n",  ( $msg =~ /.{1,80}/gs ));
       #$msg =~ s/(.{39}[^\s]*)\s+/$1\n/;
       my $length = length($msg);
       my $lf = "70";
       my $i = "1";
       my $count;
       while ($length > 0){
         $count  = $i * $lf;
         $msg =~ s/(.{\Q$count\E}[^\h]*)\s+/$1\n/g;
         $length = $length - $lf;
         $i++;
       }              
     }
     else{
       return "none";
     }
     $msg = $type.(split / /, $msg, 2)[1];
   }
   return $msg;
}

sub SVDRP_Set {
  my ($hash, @param) = @_;
	
  return '"set SVDRP" needs at least one argument' if (int(@param) < 2);
	
  my $name = shift @param;
  my $opt = shift @param;
  my $value = join("", @param);
  #my $value = shift @param;
  my $msg;
  my $msg2;
  my $list = "";
  my $optorg = $opt;
  my $next;
  my $writecmd;
  
  $hash = $defs{$name};

  # construct set list
  my @cList = (keys %SVDRP_sets);
  foreach my $key (@cList){
    $list = $list.$key.$SVDRP_sets{$key}." ";
  }
  if (!exists($SVDRP_sets{$opt})){
    return "Unknown argument $opt, please choose one of $list";
  }
  
  # return if device is disabled
  if(IsDisabled($name)){
    main::Log3 $name, 5, "[$name]: Set: $name is disabled by framework!";
    return;
  }
  # empty reading error
  readingsSingleUpdate($hash, "globalError", "", 1);
  readingsSingleUpdate($hash, "infoError", "", 1);

  if ($opt eq "cleanUp"){
    main::Log3 $name, 5, "[$name]: Set: $name cleanUp";
    SVDRP_cleanUp($hash);
    return;
  }

  if ($opt eq "closeDev"){
    main::Log3 $name, 5, "[$name]: Set: $name closeDev";
    SVDRP_closeDev($hash);
    return;
  }

  if ($opt eq "connect"){
    main::Log3 $name, 5, "[$name]: Set: $name connect";
    DevIo_OpenDev($hash, 0, "SVDRP_Init", "SVDRP_Callback");
    return;
  }  
  
  # $opt is the nice name - read real command from SVDRP_cmdmap
  if (exists($SVDRP_cmdmap{$opt})){
    $opt = $SVDRP_cmdmap{$opt};
    main::Log3 $name, 5, "[$name]: Set: converted command to $opt";    
  }
  # STAT has only one option "disk"
  $value = "disk" if ($opt eq "STAT");
  
  if ($opt eq "PowerOff"){
    $opt = "HITK";
    $value = "Power";
  }

  if ($opt eq "LSTT"){
    # delete ListTimers, will be re-filled completely
    readingsSingleUpdate($hash, "ListTimers", "", 1);
    main::Log3 $name, 5, "[$name]: Set: deleted ListTimers, value is now ".ReadingsVal($name,"ListTimers","none");
  }

  if ($opt eq "LSTR"){
    # delete Recordings, will be re-filled completely
    my $recid;
    if (!$value){
      $recid = "Recording ID: all";
    }
    else{
      $recid = "Recording ID: ".$value;
    }
    #main::Log3 $name, 5, "[$name]: Set: LastCmd is ".AttrVal($name,"LastCmd","unknown");
    #my $recid = "Recording ID: ".((split / /, AttrVal($name,"LastCmd","unknown"), 2)[1] || "all");
    readingsSingleUpdate($hash, "Recordings", $recid, 1);
    main::Log3 $name, 5, "[$name]: Set: deleted Recordings, value is now ".ReadingsVal($name,"Recordings","none");
  }

  # get or no value will sent send $msg to the given command $opt
  if ($value eq "get" || !$value){
    $msg = "$opt\r\n";
    $msg2 = $msg;
  }
  # construct command with value 
  else {
    $msg = "$opt $value\r\n";
    $msg2 = $opt."|".$value."\r\n";  
  }

  #delete $hash->{helper}{LastCmd};
  $hash->{STATE} = "query...";
  DevIo_OpenDev($hash, 1, "SVDRP_Init", "SVDRP_Callback");
  # Open connection returns welcome string like
  # "220 VDR SVDRP VideoDiskRecorder 2.0.6; Sun Feb  6 21:16:36 2022; UTF-8"
  # Read stores received data in $hash->{PARTIAL}

  my $delay = AttrVal( $name, "delay", "1" );
  # give VDR "delay" s to react before we send command
  #$writecmd = $name."|".$msg."|".$optorg;
  $next = gettimeofday() + $delay;
  if ($msg =~ /GetAll/){
    my $cmds = join (" ", @SVDRP_statusCmds);
    $writecmd = $name."|".$cmds."|".$optorg;
    InternalTimer( $next, "SVDRP_multiWrite", $writecmd);
  }
  else{
    $writecmd = $name."|".$msg."|".$optorg;
    InternalTimer( $next, "SVDRP_singleWrite", $writecmd);
  }
  
  $msg =~ s/[\r\n]//g;
  readingsSingleUpdate($hash, "LastCmd", $msg, 1);
  
  # give VDR 1 s to react before we close connection
  $next = gettimeofday() + (2 * $delay);
  InternalTimer( $next, "SVDRP_cleanUp", $hash);    
  return;    
}

sub SVDRP_singleWrite {
  # write single command via DevIo
  my ($writecmd) = @_;
  my ( $name, $msg, $optorg  ) = split( "\\|", $writecmd );
  my $hash = $defs{$name};
  #$hash->{helper}{LastCmd} = $optorg;
  DevIo_SimpleWrite($hash, $msg, "2");
  main::Log3 $name, 5, "[$name]: singleWrite: sending $msg";
}

sub SVDRP_multiWrite {
  # write multiple commands via DevIo
  my ($writecmd) = @_;
  my ( $name, $msg, $optorg  ) = split( "\\|", $writecmd );
  my $hash = $defs{$name};
  my $send;
  main::Log3 $name, 5, "[$name]: multiWrite: will send: $msg";
  my @msgarr = split / /, $msg;
  #$hash->{helper}{LastCmd} = $optorg;
  foreach (@msgarr) {
    if ($_ eq "LSTT"){
      # delete ListTimers, will be re-filled completely
      readingsSingleUpdate($hash, "ListTimers", "", 1);
    }
    if ($_ eq "STAT"){
      $send = $_." disk\r\n"
    }
    else{
      $send = "$_\r\n";
    } 
    DevIo_SimpleWrite($hash, $send, "2");
    #main::Log3 $name, 5, "[$name]: multiWrite: sending $send";
  }  
}

sub SVDRP_checkConnection ($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  RemoveInternalTimer($hash, "SVDRP_checkConnection");

  my $checkInterval = AttrVal( $name, "connectionCheck", "off" );
  
  if ($checkInterval eq "off"){
    return ;
  }
  
  # my $status = DevIo_IsOpen($hash); # would just tell if FD exists
  # let's try to reopen the connection. If successful, FD is kept or created.
  # if not successful, NEXT_OPEN is created.
  # $status is always undef, since callback fn is given
  my $status = DevIo_OpenDev($hash, 1, "SVDRP_ReInit", "SVDRP_Callback");
  
  #delete $hash->{NEXT_OPEN} if ( defined( $hash->{NEXT_OPEN} ) );
  #delete $hash->{helper}{nextConnectionCheck} if ( defined( $hash->{helper}{nextConnectionCheck} ) );

  if (!($hash->{FD}) && $hash->{NEXT_OPEN}) {
    # device was connected, but TCP timeout reached
    # DevIo tries to re-open after NEXT_OPEN
    # no internal timer needed
    delete $hash->{helper}{nextConnectionCheck}
      if ( defined( $hash->{helper}{nextConnectionCheck} ) );    
    main::Log3 $name, 3, "[$name]: DevIo_Open has no FD, NEXT_OPEN is $hash->{NEXT_OPEN}, no timer set";  
  }
  elsif (!($hash->{FD}) && !$hash->{NEXT_OPEN}){
    # not connected, DevIo not active, so device won't open again automatically
    # should never happen, since we called DevIo_Open above!
    # no internal timer needed, but should we ask DevIo again for opening the connection?
    #DevIo_OpenDev($hash, 1, "SVDRP_Init", "SVDRP_Callback");
    main::Log3 $name, 3, "[$name]: DevIo_Open has no FD, no NEXT_OPEN, should not happen!";
  }
  elsif ($hash->{FD} && $hash->{NEXT_OPEN}){
    # not connected - device was connected, but is not reachable currently
    # DevIo tries to connect again at NEXT_OPEN
    # should we try to clean up by closing and reopening?
    # no internal timer needed
    #DevIo_CloseDev($hash);
    #DevIo_OpenDev($hash, 1, "SVDRP_Init", "SVDRP_Callback");
    delete $hash->{helper}{nextConnectionCheck}
      if ( defined( $hash->{helper}{nextConnectionCheck} ) );
    main::Log3 $name, 3, "[$name]: DevIo_Open has FD and NEXT_OPEN, try to reconnect periodically";
  }
  elsif ($hash->{FD} && !$hash->{NEXT_OPEN}){
    # device is connectd, or seems to be (since broken connection is not detected by DevIo!)
    # normal state when device is on and reachable
    # or when it was on, turned off, but DevIo did not recognize (TCP timeout not reached)
    # internal timer makes sense to check, if device is really reachable
    my $next = gettimeofday() + $checkInterval; # if checkInterval is off, we won't reach this line
    $hash->{helper}{nextConnectionCheck} = $next;
    InternalTimer( $next, "SVDRP_checkConnection", $hash);
    main::Log3 $name, 3, "[$name]: DevIo_Open has FD but no NEXT_OPEN, next timer set";
  }  
}

sub SVDRP_checkStatus ($){
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  my $checkInterval = AttrVal( $name, "statusCheckInterval", "off" );
  my $checkcmd = AttrVal( $name, "statusCheckCmd", "PWR" );
  my $next;
  
  if ($checkInterval eq "off"){
    RemoveInternalTimer($hash, "SVDRP_checkStatus");
    main::Log3 $name, 5,"[$name]: checkStatus: status timer removed";
    return ;
  }
  else{
    my $value = "get";
    SVDRP_Set($hash, $name, $checkcmd, $value);
    $next = gettimeofday() + $checkInterval;
    $hash->{helper}{nextStatusCheck} = $next;
    InternalTimer( $next, "SVDRP_checkStatus", $hash);
    main::Log3 $name, 5,"[$name]: checkStatus: next status timer set";
  }  
}

###################################################
#                    end                          #
###################################################


1;

=pod
=item summary    control VDR by SVDRP via (W)Lan
=item summary_DE Steuerung von VDR mittels SVDRP über (W)Lan
=begin html

<a id="SVDRP"></a>
<h3>SVDRP</h3>

<ul>
  <i>SVDRP</i> implements SVDRP to control VDR via (W)Lan.
  <br><br>
  <a id="SVDRP-define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; SVDRP &lt;IP_Address&gt [&lt;port&gt;]</code>
    <br>
    <br>70_SVDRP.pm provides basic control of your VDR.
    <br>Only a reasonable subset of SVDRP commands in implemented, since it e.g. does not make sense to set timers via fhem - vdradmin is a much more convenient GUI for that.
    <br><br>
    <ul>
      <li><b>IP_Address</b> - the IP Address of your VDR
      </li>
      <li><b>port</b> - ... guess? Yes, the port. If not given, VDR standard port 6419 is used.
      </li>
      <li>Example: <code>define VDRcontrol SVDRP 10.10.0.1 6419</code>
      </li>
    </ul>      
  </ul>
  <br>

  <a id="SVDRP-set"></a>
  <b>Set</b>
  <br>
  <ul>
    <br>Available <b>set</b> commands are taken from http://www.vdr-wiki.de/wiki/index.php/SVDRP.
    <br>For the predefined "raw" commands, "nice" names will be shown for the readings, e.g. <b>DiskStatus</b> instead of <b>STAT disk</b>.
    <br>Default set commands are
    <br><br>
    <li>Channel
      <br>set value can be <i>"+"</i> or <i>"-"</i> or any channel number you want to switch to.
      <br><i>set &lt;name&gt; Channel</i> will get you the channel VDR is currently tuned to.
    </li>
    <br>
    <li>DeleteTimer
      <br><i>set &lt;name&gt; DeleteTimer &lt;number&gt;</i> will delete ... hm, guess?
      <br>(you can get the timer numbers via <i>ListTimers</i>) 
    </li>
    <br>
    <li>DiskStatus
      <br>no value or <i>get</i> will display the current disk usage in <i>DiskStatus</i>
      <br>Additionally, the reading <i>DiskUsed</i> will be set to the disk fill level.
    </li>
    <br>
    <li>GetAll
      <br>no value or <i>get</i> will query several SVDRP settings:
      <br>"LSTT", "NEXT", "CHAN", "VOLU", "STAT"
      <br>(i.e. ListTimers, NextTimer, Channel, Volume, DiskStatus)
    </li>
    <br>
    <li>HitKey
      <br>Enables you to send any Key defined by http://www.vdr-wiki.de/wiki/index.php/SVDRP
      <br>E.g.<i>set &lt;name&gt; HitKey Power</i> will cleanly power off VDR.
    </li>
    <br>
    <li>ListRecording
      <br>set value should be an existing recording ID. Depending on the attribute <i>RecordingInfo</i> either all available info will be shown, or a reasonable subset.
      <br>If no value is given, all available recordings will be read and shown.
      <br>Attention: Depending on the number of number of recordings, this might take a while! fhem might show "timeout", and a screen refresh might be necessary. Use with care... 
    </li>
    <br>
    <li>PowerOff
      <br>A shortcut to cleanly power off VDR, same as <i>set &lt;name&gt; HitKey Power</i>
    </li>
    <br>
    <li>ListTimers
      <br>no value or <i>get</i> will query all timers from VDR.
      <br>raw answer from VDR will be parsed into a little bit nicer format. 
    </li>
    <br>
    <li>NextTimer
      <br>no value or <i>get</i> will exactly get what it says. 
    </li>
    <br>
    <li>UpdateRecordings
      <br>no value or <i>get</i> will trigger VDR to re-read the recordings.
      <br>(No output to fhem - no sense to show all recordings here)
    </li>
    <br>
    <li>Volume
      <br>set value can be <i>"+"</i> or <i>"-"</i> or <i>mute</i> or any Volume (0-255) you want to set.
      <br><i>set &lt;name&gt; Volume</i> will get you VDR's current Volume setting.
    </li>
    <br>
    <li>connect
      <br>just connects to VDR, no further action.
      <br>Reading "info" will be updated.
      <br>Attention: As long as connection to VDR is open, no other SVDRP client can connect!
      <br>You might want to use "cleanup" to be able to reconnect other clients.
    </li>
    <br>
    <li>cleanup
      <br>closes connection to VDR, no further action.
      <br>Reading "info" will be updated.
    </li>
    <br>
    <li>closeDev
      <br>subset of cleanup. Just closes DevIo connection.
      <br>If you don't know what that means, you don't need it ;-)
    </li>
  </ul>
  <br>

  <a id="SVDRP-attr"></a>
  <b>Attributes</b>
  <br>
  <ul>
    <li>AdditionalSettings
      <br><i>cmd1:val_1,...,val_n cmd2:val_1,...,val_n</i>
      <br>You can specify own set commands here, they will be added to the <b>set</b> list.
      <br>Multiple own sets can be specified, separated by a blank.
      <br>command and values are separated by <b>":"</b>, values are separated by <b>","</b>.
      <br>Example: <i>HITK:up,down,Power MESG</i>
    </li>
    <br>
    <li>RecordingInfo
      <br><i>short|long</i>
      <br>defines the amount of information shown on <i>ListRecording </i>
      <br><i>short</i> will display recording iD, title, subtitle, Description
      <br><i>long</i> will show all available information of the requested Recording
      <br>Default value is "short"
    </li>
    <br>
    <li>connectionCheck
      <br><i>off|(value in seconds)</i>
      <br><i>value</i> defines the intervall in seconds to perform an connection check.
      <br>Normally you won't need that. Use at your own risk...
      <br>Default value is "off".
    </li>
    <br>            
    <li>statusCheckIntervall
      <br><i>off|(value in seconds)</i>
      <br><i>value</i> defines the intervall in seconds to perform an status check.
      <br>Each <i>interval</i> the VDR is queried with the command defined by <i>statusCheckCmd</i> (default: DiskStatus).
      <br>Default value is off.
    </li>
    <br>
    <li>statusCheckCmd
      <br><i>(any command(s) you set)</i>
      <br>Defines the command(s) used by statusCheckIntervall.
    </li>
    <br>            
    <li>statusOfflineMsg
      <br><i>(any message text you set)</i>
      <br>Defines the message to set in the Reading related to <i>statusCheckCmd</i> when the device goes offline.
      <br>Status of device will be checked after each <i>statusCheckIntervall</i> (default: off), querying the <i>statusCheckCmd</i> command (default: DiskStatus), and if STATE is <i>disconnected</i> the Reading of <i>statusCheckCmd</i> will be set to this message. Default: closed.
    </li>
    <br>
    <li>delay
      <br><i>delay time in seconds</i>
      <br>Depending on the answering speed of your VDR, it might be necessary to grant a certain delay beween opening the connection (and getting the initial answer shown in reading "info"), sending a command, receiving the result and closing the connection.
      <br>Default: 1.
    </li>
    <br>
  </ul>
</ul>
=end html
=cut
