##############################################
# $Id$
#
# Usage
# 
# define <name> pilight_ctrl <host:port> [5.0] 
#
# Changelog
#
# V 0.10 2015-02-22 - initial beta version 
# V 0.20 2015-02-25 - new: dimmer
# V 0.21 2015-03-01 - API 6.0 as default
# V 0.22 2015-03-03 - support more switch protocols
# V 0.23 2015-03-14 - fix: id isn't numeric
# V 0.24 2015-03-20 - new: add cleverwatts protocol
# V 0.25 2015-03-26 - new: cleverwatts unit all
#                   - fix: unit isn't numeric
# V 0.26 2015-03-29 - new: temperature and humidity sensor support (pilight_temp)
# V 0.27 2015-03-30 - new: ignore complete protocols with <protocol>:* in attr ignore
#        2015-03-30 - new: GPIO temperature and humidity sensors
# V 0.28 2015-04-09 - fix: if not connected to pilight-daemon, do not try to send messages
# V 0.29 2015-04-12 - fix: identify intertechno_old as switch
# V 0.50 2015-04-17 - fix: queue of sending messages
#                   - fix: same spelling errors - thanks to pattex
# V 0.51 2015-04-29 - CHG: rename attribute ignore to ignoreProtocol because with ignore the whole device is ignored in FHEMWEB
# V 1.00 2015-05-09 - NEW: white list for defined submodules activating by ignoreProtocol *
# V 1.01 2015-05-09 - NEW: add quigg_gt* protocol (e.q quigg_gt7000)
# V 1.02 2015-05-16 - NEW: battery state for temperature sensors
# V 1.03 2015-05-20 - NEW: handle screen messages (up,down)
# V 1.04 2015-05-30 - FIX: StateFn  
# V 1.05 2015-06-07 - FIX: Reset 
# V 1.06 2015-06-20 - NEW: set <ctrl> disconnect, checking reading state
# V 1.07 2015-06-23 - FIX: reading state always contains a valid value, checking reading state removed
# V 1.08 2015-06-23 - FIX: clear send queue by reset
# V 1.08 2015-06-23 - NEW: attribute SendTimeout for abort sending command non blocking
# V 1.09 2015-07-21 - NEW: support submodule pilight_raw to send raw codes
# V 1.10 2015-08-30 - NEW: support pressure, windavg, winddir, windgust from weather stations and GPIO sensors
# V 1.11 2015-09-06 - FIX: pressure, windavg, winddir, windgust from weather stations without temperature 
# V 1.12 2015-09-11 - FIX: handling ContactAsSwitch befor white list check
# V 1.13 2015-11-10 - FIX: POSIX isdigit is deprecated replaced by own isDigit
# V 1.14 2016-03-20 - FIX: send delimiter to signal end of stream if length of data > 1024
# V 1.15 2016-03-28 - NEW: protocol daycom (switch)
# V 1.16 2016-06-02 - NEW: protocol oregon_21 (temp)
# V 1.17 2016-06-28 - FIX: Experimental splice on scalar is now forbidden - use explizit array notation
# V 1.18 2016-06-28 - NEW: support smoke sensors (protocol: secudo_smoke_sensor)
# V 1.19 2016-09-20 - FIX: PERL WARNING: Subroutine from Blocking.pm redefined
# V 1.20 2016-10-27 - FIX: ContactAsSwitch protocol independend
# V 1.21 2016-11-13 - NEW: support contact sensors 
# V 1.22 2017-04-08 - NEW: support contact sensor GW-iwds07
# V 1.23 2017-04-08 - NEW: support new temperature protocols bmp085 and bmp180
# V 1.24 2017-04-22 - FIX: GS-iwds07 support
# V 1.25 2017-04-23 - FIX: react only of global::INITIALIZED m/^INITIALIZED$/
# V 1.26 2017-09-03 - FIX: heitech support
# V 1.27 2018-01-28 - NEW: handle bh1750 illuminance sensor as weather station
############################################## 
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use JSON;    #libjson-perl
use Switch;  #libswitch-perl

require 'DevIo.pm';
require 'Blocking.pm';

sub pilight_ctrl_Parse($$);
sub pilight_ctrl_Read($);
sub pilight_ctrl_Ready($);
sub pilight_ctrl_Write($@);
sub pilight_ctrl_SimpleWrite(@);
sub pilight_ctrl_ClientAccepted(@);
sub pilight_ctrl_Send($);
sub pilight_ctrl_Reset($);

my %sets = ( "reset:noArg" => "", "disconnect:noArg" => "");
my %matchList = ( "1:pilight_switch" => "^PISWITCH",
                  "2:pilight_dimmer" => "^PISWITCH|^PIDIMMER|^PISCREEN",
                  "3:pilight_temp"   => "^PITEMP",
                  "4:pilight_raw"    => "^PIRAW",
                  "5:pilight_smoke"  => "^PISMOKE",
                  "6:pilight_contact"=> "^PICONTACT");
                  
my @idList   = ("id","systemcode","gpio"); 
my @unitList = ("unit","unitcode","programcode");

#ignore tfa:0,...         list of <protocol>:<id> to ignore
#brands arctech:kaku,...  list of <search>:<replace> protocol names  
#ContactAsSwitch 1234,... list of ids where contact is transformed to switch

sub isDigit($)
{
  my ($d) = @_;
  return $d =~ /^\d+?$/ ? 1 : 0; 
}

sub pilight_ctrl_Initialize($)
{
  my ($hash) = @_;
  
  $hash->{ReadFn}  = "pilight_ctrl_Read";
  $hash->{WriteFn} = "pilight_ctrl_Write";
  $hash->{ReadyFn} = "pilight_ctrl_Ready";
  $hash->{DefFn}   = "pilight_ctrl_Define";
  $hash->{UndefFn} = "pilight_ctrl_Undef";
  $hash->{SetFn}   = "pilight_ctrl_Set";
  $hash->{NotifyFn}= "pilight_ctrl_Notify";
  $hash->{StateFn} = "pilight_ctrl_State";
  $hash->{AttrList}= "ignoreProtocol brands ContactAsSwitch SendTimeout ".$readingFnAttributes;
  
  $hash->{Clients} = ":pilight_switch:pilight_dimmer:pilight_temp:pilight_raw:pilight_smoke:pilight_contact:";
  #$hash->{MatchList} = \%matchList; #only for autocreate
}

#####################################
sub pilight_ctrl_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a < 3) {
    my $msg = "wrong syntax: define <name> pilight_ctrl hostname:port [5.0]";
    Log3 undef, 2, $msg;
    return $msg;
  }

  DevIo_CloseDev($hash);
  RemoveInternalTimer($hash);
    
  my $me = $a[0];
  my $dev  = $a[2];

  $hash->{DeviceName} = $dev;
  $hash->{STATE} = "defined";
  $hash->{API} = "6.0"; 
  $hash->{API} = "5.0" if (defined($a[3]) && $a[3] =~/5/);
  $hash->{RETRY_INTERVAL} = 60;
  
  $hash->{helper}{CON} = "define";
  $hash->{helper}{CHECK} = 0;
  
  my @sendQueue = ();
  $hash->{helper}->{sendQueue} = \@sendQueue;
  
  my @whiteList = ();
  $hash->{helper}->{whiteList} = \@whiteList;
  
  #$attr{$me}{verbose} = 5;
  
  return pilight_ctrl_TryConnect($hash);
}

sub pilight_ctrl_setStates($$)
{
  my ($hash, $val) = @_;
  $hash->{STATE} = $val;
  $val = "disconnected" if ($val eq "closed");
  setReadingsVal($hash, "state", $val, TimeNow());
}

#####################################
sub pilight_ctrl_State($$$$)
{
  my ($hash, $time, $name, $val) = @_;
  my $me = $hash->{NAME};  
  
  if ($name eq "STATE" && $val eq "closed") {
    Log3 $me, 3, "$me(State): abort connecting because of saved STATE";
    pilight_ctrl_Close($hash);
    return undef;
  }
  
  # gespeicherten Readings nicht wieder herstellen
  if ($name eq "state" && $hash->{STATE}) {
      setReadingsVal($hash, $name, "disconnected", TimeNow());
  }
  
  if ($name eq "rcv_raw") {
      setReadingsVal($hash, $name, "empty", TimeNow());
  }
  return undef;
}

sub pilight_ctrl_CheckReadingState($)
{
  my ($hash) = @_;
  my $me = $hash->{NAME};  
  
  my $state     = ReadingsVal($me,"state",undef);
  if (defined($state) && $state ne "opened" && $state ne "disconnected") {
    Log3 $me, 3, "$me(CheckReadingState): Unknown error: unnormal value for reading state";
   
    $hash->{STATE} = $hash->{helper}{CON};
    $hash->{STATE} = "opened" if ($hash->{helper}{CON} eq "connected");
  }
  return undef;
}

sub pilight_ctrl_Close($)
{
  my $hash = shift;
  my $me = $hash->{NAME};
  
  if (exists($hash->{helper}{RUNNING_PID})) {
    Log3 $me, 5, "$me(Close): call BlockingKill";
    BlockingKill($hash->{helper}{RUNNING_PID});
    delete($hash->{helper}{RUNNING_PID}); 
  }
   
  splice(@{$hash->{helper}->{sendQueue}});
  
  RemoveInternalTimer($hash);
  Log3 $me, 5, "$me(Close): close DevIo";
  DevIo_CloseDev($hash);
  pilight_ctrl_setStates($hash,"closed");
  $hash->{helper}{CON} = "closed";
  delete $hash->{DevIoJustClosed}; 
}

#####################################
sub pilight_ctrl_Undef($$)
{
  my ($hash, $arg) = @_;
  my $me = $hash->{NAME};
  
  pilight_ctrl_Close($hash);
  
  foreach my $d (sort keys %defs) {
    if(defined($defs{$d}) &&
       defined($defs{$d}{IODev}) &&
       $defs{$d}{IODev} == $hash)
      { 
        delete $defs{$d}{IODev}; 
      } 
  }
  return undef;
}

#####################################
sub pilight_ctrl_TryConnect($)
{
  my $hash = shift;
  my $me = $hash->{NAME};
  
  Log3 $me, 5, "$me(TryConnect): $hash->{STATE}";
  
  $hash->{helper}{CHECK} = 0;
    
  RemoveInternalTimer($hash); 
  
  delete $hash->{NEXT_OPEN}; 
  delete $hash->{DevIoJustClosed};
  
  my $ret = DevIo_OpenDev($hash, 0, "pilight_ctrl_DoInit");
  
  #DevIO set state to opened
  setReadingsVal($hash, "state", "disconnected", TimeNow());  
    
  delete $hash->{NEXT_OPEN};
  $hash->{helper}{NEXT_TRY} = time()+$hash->{RETRY_INTERVAL};
  
  InternalTimer(gettimeofday()+1,"pilight_ctrl_Check", $hash, 0);
  return $ret;
}

#####################################
sub pilight_ctrl_Reset($)
{
  my ($hash) = @_;
  pilight_ctrl_Close($hash);
  return pilight_ctrl_TryConnect($hash);
}

#####################################
sub pilight_ctrl_Set($@)
{
  my ($hash, @a) = @_;

  return "set $hash->{NAME} needs at least one parameter" if(@a < 2);

  my $me   = shift @a;
  my $cmd  = shift @a;

  return join(" ", sort keys %sets) if ($cmd eq "?");

  if ($cmd eq "reset") 
  { 
    return pilight_ctrl_Reset($hash);
  }
  
  if ($cmd eq "disconnect") {
    pilight_ctrl_Close($hash);
    return undef;
  }

  return "Unknown argument $cmd, choose one of ". join(" ", sort keys %sets); 
}

#####################################
sub pilight_ctrl_Check($)
{
  my $hash = shift;
  my $me = $hash->{NAME};
  
  RemoveInternalTimer($hash); 
  
  $hash->{helper}{CHECK} = 0 if (!isDigit($hash->{helper}{CHECK}));
  $hash->{helper}{CHECK} +=1;
  Log3 $me, 5, "$me(Check): $hash->{STATE}";
  
  if($hash->{STATE} eq "disconnected") {
    Log3 $me, 2, "$me(Check): Could not connect to pilight-daemon $hash->{DeviceName}";
    $hash->{helper}{CON} = "disconnected";
    pilight_ctrl_setStates($hash,"disconnected");
  }
  
  return if ($hash->{helper}{CON} eq "disconnected" || $hash->{helper}{CON} eq "closed");
  
  if ($hash->{helper}{CON} eq "define") { 
    Log3 $me, 2, "$me(Check): connection to $hash->{DeviceName} failed";
    $hash->{helper}{CHECK} = 0;
    $hash->{helper}{NEXT_TRY} = time()+$hash->{RETRY_INTERVAL};
    return;
  }
  
  if ($hash->{helper}{CON} eq "identify") {
    if ($hash->{helper}{CHECK} % 3 == 0 && $hash->{helper}{CHECK} < 12) { #retry
      pilight_ctrl_DoInit($hash);
    } elsif ($hash->{helper}{CHECK} >= 12) {
      Log3 $me, 4, "$me(Check): Could not connect to pilight-daemon $hash->{DeviceName} - maybe wrong api version or port";
      DevIo_Disconnected($hash);
      $hash->{helper}{CHECK} = 0;
      $hash->{helper}{CON} = "disconnected";
      pilight_ctrl_setStates($hash,"disconnected");
      $hash->{helper}{NEXT_TRY} = time()+$hash->{RETRY_INTERVAL}; 
      return;
    }
  }
  
  if ($hash->{helper}{CON} eq "identify-failed" || $hash->{helper}{CHECK} > 20) {
    delete $hash->{helper}{CHECK};
    $hash->{helper}{CON} = "disconnected";
    pilight_ctrl_setStates($hash,"disconnected");
    Log3 $me, 2, "$me(Check): identification to pilight-daemon $hash->{DeviceName} failed";
    $hash->{helper}{NEXT_TRY} = time()+$hash->{RETRY_INTERVAL};
    return;
  }
  
  if ($hash->{helper}{CON} eq "identify-rejected" || $hash->{helper}{CHECK} > 20) {
    Log3 $me, 2, "$me(Parse): connection to pilight-daemon $hash->{DeviceName} rejected";
    delete $hash->{helper}{CHECK};
    $hash->{helper}{CON} = "disconnected";
    pilight_ctrl_setStates($hash,"disconnected");
    $hash->{helper}{NEXT_TRY} = time()+$hash->{RETRY_INTERVAL};
    return;
  }
  
  if ($hash->{helper}{CON} eq "connected") {
    delete $hash->{helper}{CHECK};
    delete $hash->{helper}{NEXT_TRY};
    pilight_ctrl_setStates($hash,"connected");
    return;
  }
  
  InternalTimer(gettimeofday()+1,"pilight_ctrl_Check", $hash, 0);
  return 1;
}

#####################################
sub pilight_ctrl_DoInit($)
{
  my $hash = shift; 

  return "No FD" if(!$hash || ($^O !~ /Win/ && !defined($hash->{FD})));

  my $me = $hash->{NAME};  
  my $msg;
  my $api;

  Log3 $me, 5, "$me(DoInit): $hash->{STATE}";
  
  $hash->{helper}{CON} = "identify";

  if ($hash->{API} eq "6.0") {
    $msg = '{"action":"identify","options":{"receiver":1},"media":"all"}';
  } else {
    $msg = "{ \"message\": \"client receiver\" }";
  }
  Log3 $me, 5, "$me(DoInit): send $msg";
  pilight_ctrl_SimpleWrite($hash,$msg);
  return;
}

#####################################
sub pilight_ctrl_Write($@)
{
  my ($hash,$rmsg) = @_;
  my $me = $hash->{NAME};
  
  if ($hash->{helper}{CON} eq "closed") {
    return;
  }
  
  if ($hash->{helper}{CON} ne "connected") {
    Log3 $me, 2, "$me(Write): ERROR: no connection to pilight-daemon $hash->{DeviceName}";
    return;
  }
  
  my ($cName,$state,@args) = split(",",$rmsg);
    
  my $cType = lc($defs{$cName}->{TYPE});
  Log3 $me, 4, "$me(Write): RCV ($cType) -> $rmsg";
  
  my $proto = $defs{$cName}->{PROTOCOL};
  my $id = $defs{$cName}->{ID};
  my $unit = $defs{$cName}->{UNIT};
  my $syscode = undef;
  $syscode = $defs{$cName}->{SYSCODE} if defined($defs{$cName}->{SYSCODE});
  
  $id = "\"".$id."\""           if (defined($id) && !isDigit($id));
  $unit = "\"".$unit."\""       if (defined($unit) && !isDigit($unit));
  $syscode = "\"".$syscode."\"" if (defined($syscode) && !isDigit($syscode));
        
  my $code;
  switch($cType){
    case m/switch/  {       
        $code = "{\"protocol\":[\"$proto\"],";
        switch ($proto) {
          case m/elro/          {$code .= "\"systemcode\":$id,\"unitcode\":$unit,";}
          case m/silvercrest/   {$code .= "\"systemcode\":$id,\"unitcode\":$unit,";}
          case m/mumbi/         {$code .= "\"systemcode\":$id,\"unitcode\":$unit,";}
          case m/brennenstuhl/  {$code .= "\"systemcode\":$id,\"unitcode\":$unit,";}
          case m/pollin/        {$code .= "\"systemcode\":$id,\"unitcode\":$unit,";}
          case m/heitech/		    {$code .= "\"systemcode\":$id,\"unitcode\":$unit,";}
          case m/impuls/        {$code .= "\"systemcode\":$id,\"programcode\":$unit,";}
          case m/rsl366/        {$code .= "\"systemcode\":$id,\"programcode\":$unit,";}
          case m/daycom/        { if (!defined($syscode)) {
                                      Log3 $me, 1, "$me(Write): Error protocol daycom no systemcode defined";
                                      return;
                                  }
                                  $code .= "\"id\":$id,\"systemcode\":$syscode,\"unit\":$unit,";
                                }
          case m/cleverwatts/   { $code .= "\"id\":$id,"; 
                                  if ($unit eq "\"all\"") {
                                    $code .= "\"all\":1,";
                                  } else {
                                    $code .= "\"unit\":$unit,";
                                  }
                                }                                  
          else                  {$code .= "\"id\":$id,\"unit\":$unit,";}
        }
        $code .= "\"$state\":1}";
    }
    case m/dimmer/  {
        $code = "{\"protocol\":[\"$proto\"],\"id\":$id,\"unit\":$unit,\"$state\":1";
        $code .= ",\"dimlevel\":$args[0]" if (defined($args[0]));
        $code .= "}";
    }
    case m/raw/ {
      $code = "{\"protocol\":[\"$proto\"],\"code\":\"$state\"}";
    }
    else  {Log3 $me, 3, "$me(Write): unsupported client ($cName) -> $cType"; return;}
  }
  
  return if (!defined($code));
  
  my $msg;
  if ($hash->{API} eq "6.0") {
    $msg = "{\"action\":\"send\",\"code\":$code}";
  } else {
    $msg = "{\"message\":\"send\",\"code\":$code}";
  }
  Log3 $me, 4, "$me(Write): $msg";
  
  # we can't use the same connection because the pilight-daemon close the connection after sending
  # we have to create a second connection for sending data 
  # we do not update the readings - we will do this at the response message
  
  push @{$hash->{helper}->{sendQueue}}, $msg;
  pilight_ctrl_SendNonBlocking($hash);
}

#####################################
sub pilight_ctrl_Send($)
{
  my ($string) = @_;
  my ($me, $host,$data) = split("\\|", $string);
  my $hash = $defs{$me};
  
  my ($remote_ip,$remote_port) = split(":",$host);

  my $socket = new IO::Socket::INET (
    PeerHost => $remote_ip,
    PeerPort => $remote_port,
    Proto => 'tcp',
  );
  
  if (!$socket) {
    Log3 $me, 2, "$me(Send): ERROR. Can't open socket to pilight-daemon $remote_ip:$remote_port";
    return "$me|0";
  } 
  
  # we only need a identification to send in 5.0 version
  if ($hash->{API} eq "5.0") {    
    my $msg = "{ \"message\": \"client sender\" }";
    my $rcv;
    $socket->send($msg);
    $socket->recv($rcv,1024);
    $rcv =~ s/\n/ /g;
    
    Log3 $me, 5, "$me(Send): RCV -> $rcv";
    
    my $json = JSON->new;
    my $jsondata = $json->decode($rcv);

    if (!$jsondata)
    {
      Log3 $me, 2, "$me(Send): ERROR. no JSON response message";
      $socket->close();
      return "$me|0"; 
    }
    
    my $ret = pilight_ctrl_ClientAccepted($hash,$jsondata);
    if ( $ret != 1 ) {
      Log3 $me, 2, "$me(Send): ERROR. Connection rejected from pilight-daemon";
      $socket->close();
      return "$me|0";
    }
  }
  Log3 $me, 5, "$me(Send): $data";
  
  $data = $data."\n\n"; # add delimiter to signel end off stream if length > 1024
  $socket->send($data);
  
  #6.0 we get a response message
  if ($hash->{API} eq "6.0") {
    my $rcv;
    $socket->recv($rcv,1024);
    $rcv =~ s/\n/ /g;
    Log3 $me, 4, "$me(Send): RCV -> $rcv";
  }
  $socket->close();
  
  return "$me|1";
}

#####################################
sub pilight_ctrl_addWhiteList($$)
{
  my ($own, $dev) = @_;
  my $me = $own->{NAME};
  my $devName = $dev->{NAME};
  
  my $id =       (defined($dev->{ID}))       ? $dev->{ID}      : return;
  my $protocol = (defined($dev->{PROTOCOL})) ? $dev->{PROTOCOL}: return;
  
  Log3 $me, 4, "$me(addWhiteList): add $devName to white list";
  my $entry = {};
  
  my %whiteHash;
  @whiteHash{@{$own->{helper}->{whiteList}}}=();
  if (!exists $whiteHash{"$protocol:$id"}) { 
    push @{$own->{helper}->{whiteList}}, "$protocol:$id";
  }
  
  #spezial 2nd protocol for dimmer 
  if (defined($dev->{PROTOCOL2})) {
    $protocol = $dev->{PROTOCOL2};
    if (!exists $whiteHash{"$protocol:$id"}) { 
      push @{$own->{helper}->{whiteList}}, "$protocol:$id";
    }
  }
}

#####################################
sub pilight_ctrl_createWhiteList($)
{
  my ($own) = @_;
  splice(@{$own->{helper}->{whiteList}});
  foreach my $d (keys %defs)   
  { 
    my $module   = $defs{$d}{TYPE};
    next if ($module !~ /pilight_[d|s|t|c].*/);
    
    pilight_ctrl_addWhiteList($own,$defs{$d});
  }
}

#####################################
sub pilight_ctrl_Notify($$)
{
  my ($own, $dev) = @_;
  my $me = $own->{NAME}; # own name / hash
  my $devName = $dev->{NAME}; # Device that created the events

  return undef if ($devName ne "global");
  
  my $max = int(@{$dev->{CHANGED}}); # number of events / changes
  for (my $i = 0; $i < $max; $i++) {
    my $s = $dev->{CHANGED}[$i];
    
    next if(!defined($s));
    my ($what,$who) = split(' ',$s);
    
    if ( $what =~ m/^INITIALIZED$/  ) {
      Log3 $me, 4, "$me(Notify): create white list for $s";
      pilight_ctrl_createWhiteList($own);
    } elsif ( $what =~ m/DEFINED/ ){
      my $hash = $defs{$who};
      next if(!$hash);
      my $module = $hash->{TYPE};
      next if ($module !~ /pilight_[d|s|t].*/);
      pilight_ctrl_addWhiteList($own,$hash);
    } elsif ( $what =~ m/DELETED/ ){
      Log3 $me, 4, "$me(Notify): create white list for $s";
      pilight_ctrl_createWhiteList($own);
    }
  }
  return undef;
}

#####################################
sub pilight_ctrl_SendDone($)
{
  my ($string) = @_;
  my ($me, $ok) = split("\\|", $string);
  my $hash = $defs{$me};
  
  Log3 $me, 4, "$me(SendDone): message successfully send" if ($ok);
  Log3 $me, 2, "$me(SendDone): sending message failed" if (!$ok);
  
  delete($hash->{helper}{RUNNING_PID});
}

#####################################
sub pilight_ctrl_SendAbort($)
{
  my ($hash) = @_;
  my $me = $hash->{NAME};
  
  Log3 $me, 2, "$me(SendAbort): ERROR. sending aborted";
  
  delete($hash->{helper}{RUNNING_PID});
}

#####################################
sub pilight_ctrl_SendNonBlocking($)
{
  my ($hash) = @_;
  my $me = $hash->{NAME};
  
  RemoveInternalTimer($hash); 
  
  my $queueSize = @{$hash->{helper}->{sendQueue}};
  Log3 $me, 5, "$me(SendNonBlocking): queue size $queueSize"; 
  
  return if ($queueSize <=0);
  
  if (!(exists($hash->{helper}{RUNNING_PID}))) {    
    my $data = shift @{$hash->{helper}->{sendQueue}};    
    
    my $blockingFn = "pilight_ctrl_Send";
    my $arg        = $me."|".$hash->{DeviceName}."|".$data;
    my $finishFn   = "pilight_ctrl_SendDone";
    my $timeout    = AttrVal($me, "SendTimeout",1);
    my $abortFn    = "pilight_ctrl_SendAbort";
  
    $hash->{helper}{RUNNING_PID} = BlockingCall($blockingFn, $arg, $finishFn, $timeout, $abortFn, $hash);
    $hash->{helper}{LAST_SEND_RAW} = $data;
  } else {
    Log3 $me, 5, "$me(Write): Blocking Call running - will try it later";     
  }
  
  $queueSize = @{$hash->{helper}->{sendQueue}};
  InternalTimer(gettimeofday()+0.5,"pilight_ctrl_SendNonBlocking", $hash, 0) if ($queueSize > 0);
}

#####################################
sub pilight_ctrl_ClientAccepted(@)
{
  my ($hash,$data) = @_;
  my $me = $hash->{NAME};
  
  my $ret = 0;
  if ($hash->{API} eq "5.0") {
    my $msg = (defined($data->{message})) ? $data->{message} : "";
    $ret = 1  if(index($msg,"accept") >= 0);
    $ret = -1 if(index($msg,"reject") >= 0);
  }
  else {
    my $status = (defined($data->{status})) ? $data->{status} : "";
    $ret = 1  if(index($status,"success") >= 0);
    $ret = -1 if(index($status,"reject") >= 0);
  }
  return $ret;
}


#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub pilight_ctrl_Read($)
{
  my ($hash) = @_;
  my $me = $hash->{NAME};
  
  my $buf = DevIo_SimpleRead($hash);
  return "" if(!defined($buf));

  my $recdata = $hash->{PARTIAL};
  #Log3 $me, 5, "$me(Read): RCV->$buf"; 
  $recdata .= $buf;

  while($recdata =~ m/\n/) 
  {
    my $rmsg;
    ($rmsg,$recdata) = split("\n", $recdata, 2);
    $rmsg =~ s/\r//;    
    pilight_ctrl_Parse($hash, $rmsg) if($rmsg);
  }
  $hash->{PARTIAL} = $recdata;
}

###########################################
sub pilight_ctrl_Parse($$)
{
  my ($hash, $rmsg) = @_;
  my $me = $hash->{NAME};
  
  Log3 $me, 5, "$me(Parse): RCV -> $rmsg";

  next if(!$rmsg || length($rmsg) < 1);

  $hash->{helper}{LAST_RCV_RAW} = $rmsg;

  my $json = JSON->new;
  my $data = $json->decode($rmsg);
  return if (!$data);
  
  if ($hash->{helper}{CON} eq "identify")  # we are in identify process
  { 
    Log3 $me, 4, "$me(Parse): identify -> $rmsg";
    
    $hash->{helper}{CON} = "identify-failed";
    my $ret = pilight_ctrl_ClientAccepted($hash,$data);
    
    switch ($ret) {
      case 1  { $hash->{helper}{CON} = "connected"; }
      case -1 { $hash->{helper}{CON} = "identify-rejected"; }
      else    { Log3 $me, 3, "$me(Parse): internal error"; }
    }
    pilight_ctrl_Check($hash);
    return;
  }

  $hash->{helper}{LAST_RCV_JSON} =  $json;
  
  my $proto = (defined($data->{protocol})) ? $data->{protocol} : "";
  if (!$proto)
  {
    Log3 $me, 3, "$me(Parse): unknown message -> $rmsg";
    return;
  }

  #brands
  my @brands = split(",",AttrVal($me, "brands",""));
  foreach my $brand (@brands){
    my($search,$replace) = split(":",$brand);
    next if (!defined($search) || !defined($replace));
    $proto =~ s/$search/$replace/g;
  } 

  $hash->{helper}{LAST_RCV_PROTOCOL} = $proto;
  
  my $s           = ($hash->{API} eq "5.0")            ? "code" : "message";
  my $state       = (defined($data->{$s}{state}))      ? $data->{$s}{state}       : "";
  my $all         = (defined($data->{$s}{all}))        ? $data->{$s}{all}         : "";
 
  my $id = "";
  foreach my $sid (@idList) {
    $id          = (defined($data->{$s}{$sid}))        ? $data->{$s}{$sid}        : ""; 
    last if ($id ne "");
  }
  
  #systemcode and id for protocol daycom (needs 3 id's, systemcode, id, unit
  my $syscode = (defined($data->{$s}{"systemcode"}))   ? $data->{$s}{"systemcode"}  : ""; 
  
  my $unit = "";
  foreach my $sunit (@unitList) {
    $unit          = (defined($data->{$s}{$sunit}))    ? $data->{$s}{$sunit}      : ""; 
    last if ($unit ne "");
  }

  # handling ContactAsSwitch befor white list check
  my $asSwitch = $attr{$me}{ContactAsSwitch};
  if ( defined($asSwitch) && $asSwitch =~ /$id/ && ($state =~ /opened/ || $state =~ /closed/) ) {
    $proto =~ s/contact/switch/g;
    $state =~ s/opened/on/g;
    $state =~ s/closed/off/g;
    Log3 $me, 4, "$me(Parse): contact as switch for $id";
  }
  
  # some protocols have no id but unit(code) e.q. ev1527, GS-iwds07
  $id = $unit if ($id eq "" && $unit ne "");   
  $unit = "all" if ($unit eq "" && $all ne "");
  
  Log3 $me, 5, "$me(Parse): protocol:$proto,id:$id,unit:$unit";
        
  my @ignoreIDs = split(",",AttrVal($me, "ignoreProtocol","")); 
  
  # white or ignore list
  if (@ignoreIDs == 1 && $ignoreIDs[0] eq "*"){ # use list
      my %whiteHash;
      @whiteHash{@{$hash->{helper}->{whiteList}}}=();
      if (!exists $whiteHash{"$proto:$id"}) {
        Log3 $me, 5, "$me(Parse): $proto:$id not in white list";
        return;
      }
  } else {  #ignore list
    my %ignoreHash;
    @ignoreHash{@ignoreIDs}=();  
    if (exists $ignoreHash{"$proto:$id"} || exists $ignoreHash{"$proto:*"}) {
      Log3 $me, 5, "$me(Parse): $proto:$id is in ignoreProtocol list";
      return;
    }
  }
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"rcv_raw",$rmsg);
  readingsEndUpdate($hash, 1);
    
  my $protoID = -1;  
  switch($proto){
    #switch
    case m/switch/      {$protoID = 1;}
    case m/elro/        {$protoID = 1;}
    case m/silvercrest/ {$protoID = 1;}
    case m/mumbi/       {$protoID = 1;}
    case m/brennenstuhl/{$protoID = 1;}
    case m/pollin/      {$protoID = 1;}
    case m/daycom/      {$protoID = 1;}
    case m/impuls/      {$protoID = 1;}
    case m/rsl366/      {$protoID = 1;}
    case m/cleverwatts/ {$protoID = 1;}
    case m/intertechno_old/ {$protoID = 1;}
    case m/quigg_gt/    {$protoID = 1;}
    case m/heitech/		{$protoID = 1;}
    
    case m/dimmer/      {$protoID = 2;}
    
    #contact sensors
    case m/contact/     {$protoID = 3;}
    case m/ev1527/      {$protoID = 3;}
    case m/sc2262/      {$protoID = 3;}
    case m/GS-iwds07/   {$protoID = 3;} 
    
    #Weather Stations temperature, humidity
    case m/alecto/      {$protoID = 4;}
    case m/auriol/      {$protoID = 4;}
    case m/ninjablocks/ {$protoID = 4;}
    case m/tfa/         {$protoID = 4;}
    case m/teknihall/   {$protoID = 4;}
    case m/oregon_21/   {$protoID = 4;}
    
    #handle illuminance sensor as weather station - workaround
    case m/bh1750/      {$protoID = 4;}
    
    #gpio temperature, humidity sensors
    case m/dht11/       {$protoID = 4;}
    case m/dht22/       {$protoID = 4;}
    case m/ds18b20/     {$protoID = 4;}
    case m/ds18s20/     {$protoID = 4;}
    case m/cpu_temp/    {$protoID = 4;}
    case m/lm75/        {$protoID = 4;}
    case m/lm76/        {$protoID = 4;}
    case m/bmp085/      {$protoID = 4;}
    case m/bmp180/      {$protoID = 4;}
    
    case m/screen/      {$protoID = 5;}
    
    #smoke sensors
    case m/secudo_smoke_sensor/   {$protoID = 6;}
    
    case m/firmware/    {return;}    
    else                {Log3 $me, 3, "$me(Parse): unknown protocol -> $proto"; return;}
  }
  
  if ($id eq "") {
      Log3 $me, 3, "$me(Parse): ERROR no or unknown id $rmsg";
      return;
  }
    
  switch($protoID){
    case 1 {
      my $msg = "PISWITCH,$proto,$id,$unit,$state";
      $msg .= ",$syscode" if ($syscode ne "");
      
      Log3 $me, 4, "$me(Dispatch): $msg";
      return Dispatch($hash, $msg,undef );
      }
    case 2 {
      my $dimlevel = (defined($data->{$s}{dimlevel})) ? $data->{$s}{dimlevel} : "";
      my $msg = "PIDIMMER,$proto,$id,$unit,$state";
      $msg.= ",$dimlevel" if ($dimlevel ne "");
      Log3 $me, 4, "$me(Dispatch): $msg";
      return Dispatch($hash, $msg ,undef);
    }
    case 3 { 
		my $piTempData = "";
        $piTempData .= ",battery:$data->{$s}{battery}"          if (defined($data->{$s}{battery}));
        my $msg = "PICONTACT,$proto,$id,$unit,$state$piTempData";
        Log3 $me, 4, "$me(Dispatch): $msg";
		return Dispatch($hash, $msg,undef);		
	}
    case 4 {      
        my $piTempData = "";
        $piTempData .= ",temperature:$data->{$s}{temperature}"  if (defined($data->{$s}{temperature}));
        $piTempData .= ",humidity:$data->{$s}{humidity}"        if (defined($data->{$s}{humidity}));
        $piTempData .= ",battery:$data->{$s}{battery}"          if (defined($data->{$s}{battery}));
        $piTempData .= ",pressure:$data->{$s}{pressure}"        if (defined($data->{$s}{pressure}));
        $piTempData .= ",windavg:$data->{$s}{windavg}"          if (defined($data->{$s}{windavg}));
        $piTempData .= ",winddir:$data->{$s}{winddir}"          if (defined($data->{$s}{winddir}));
        $piTempData .= ",windgust:$data->{$s}{windgust}"        if (defined($data->{$s}{windgust}));
        #workaround illuminance sensor
        $piTempData .= ",illuminance:$data->{$s}{illuminance}"  if (defined($data->{$s}{illuminance}));
        
        my $msg = "PITEMP,$proto,$id$piTempData";
        Log3 $me, 4, "$me(Dispatch): $msg";
        return Dispatch($hash, $msg,undef);
    }
    case 5 { return Dispatch($hash, "PISCREEN,$proto,$id,$unit,$state",undef); }
    case 6 { return Dispatch($hash, "PISMOKE,$proto,$id,$state",undef); }
    else  {Log3 $me, 3, "$me(Parse): unknown protocol -> $proto"; return;}
  }
  return;
}

#####################################
# called from gobal loop to try reconnection
sub pilight_ctrl_Ready($)
{
  my ($hash) = @_;
  my $me = $hash->{NAME};
  
  if($hash->{STATE} eq "disconnected")
  {
    return if(defined($hash->{helper}{NEXT_TRY}) && $hash->{helper}{NEXT_TRY} && time() < $hash->{helper}{NEXT_TRY});
    return pilight_ctrl_TryConnect($hash);
  }
  
  
}

#####################################
sub pilight_ctrl_SimpleWrite(@)
{
  my ($hash, $msg, $nonl) = @_;
  return if(!$hash);
 
  my $me = $hash->{NAME};
  Log3 $me, 4, "$me(SimpleWrite): snd -> $msg";

  $msg .= "\n" unless($nonl);

  DevIo_SimpleWrite($hash,$msg,0);
}

1;

=pod
=item summary    base module to comunicate with pilight
=item summary_DE Basismodul zur Kommunikation mit pilight
=begin html

<a name="pilight_ctrl"></a>
<h3>pilight_ctrl</h3>
<ul>

  pilight_ctrl is the base device for the communication (sending and receiving) with the pilight-daemon.<br>
  You have to define client devices e.q. pilight_switch for switches.<br>
  Further information to pilight: <a href="http://www.pilight.org/">http://www.pilight.org/</a><br><br>
  Further information to pilight protocols: <a href="http://wiki.pilight.org/doku.php/protocols#protocols">http://wiki.pilight.org/doku.php/protocols#protocols</a><br>
  Currently supported: <br>
  <ul>
    <li>Switches:</li>
    <li>Dimmers:</li>
    <li>Temperature and humitity sensors</li>
  </ul>
  
  <br><br>

  <a name="pilight_ctrl_define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; pilight_ctrl ip:port [api]</code>
    ip:port is the IP address and port of the pilight-daemon<br>
    api specifies the pilight api version - default 6.0<br>
    <br>
    Example:
    <ul>
      <code>define myctrl pilight_ctrl localhost:5000 5.0</code><br>
      <code>define myctrl pilight_ctrl 192.168.1.1:5000</code><br>
    </ul>
  </ul>
  <br>
  <a name="pilight_ctrl_set"></a>
  <p><b>Set</b></p>
  <ul>
    <li><b>reset</b> Reset the connection to the pilight daemon</li>
    <li><b>disconnect</b>Diconnect from pilight daemon and do not reconnect automatically</li>
  </ul>
  <br>
  <a name="pilight_ctrl_readings"></a>
  <p><b>Readings</b></p>
  <ul>    
    <li>
      rcv_raw<br>
      The last complete received message in json format.
    </li>
  </ul>
  <br>
  <a name="pilight_ctrl_attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a name="ignoreProtocol">ignoreProtocol</a><br>
        Comma separated list of protocol:id combinations to ignore.<br>
        protocol:* ignores the complete protocol.<br>
        * All incomming messages will be ignored. Only protocol id combinations from defined submodules will be accepted<br>
        Example: 
        <li><code>ignoreProtocol tfa:0</code></li>
        <li><code>ignoreProtocol tfa:*</code></li>
        <li><code>ignoreProtocol *</code></li>
    </li>
    <li><a name="brands">brands</a><br>
        Comma separated list of <search>:<replace> combinations to rename protocol names. <br>
        pilight uses different protocol names for the same protocol e.q. arctech_switch and kaku_switch<br>
        Example: <code>brands archtech:kaku</code>
    </li>
    <li><a name="ContactAsSwitch">ContactAsSwitch</a><br>
        Comma separated list of ids which correspond to a contact but will be interpreted as switch. <br>
        In this case opened will be interpreted as on and closed as off.<br>
        Example: <code>ContactAsSwitch 12345</code> 
    </li>
    <li><a name="SendTimeout">SendTimeout</a><br>
        Timeout [s] for aborting sending commands (non blocking) - default 1s
    </li>
  </ul>
  <br>

</ul>

=end html

=cut

