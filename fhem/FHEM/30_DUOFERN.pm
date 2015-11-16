##############################################
# $Id$

package main;

use strict;
use warnings;

my %devices = (
    "40"    => "RolloTron Standard",
    "41"    => "RolloTron Comfort",
    "42"    => "Rohrmotor-Aktor",
    "43"    => "Universalaktor",
    "46"    => "Steckdosenaktor",
    "47"    => "Rohrmotor Steuerung",
    "48"    => "Dimmaktor",
    "49"    => "Rohrmotor",
    "4B"    => "Connect-Aktor",
    "4C"    => "Troll Basis",
    "4E"    => "SX5",
    "61"    => "RolloTron Comfort",
    "62"    => "Super Fake Device",
    "65"    => "RolloTron Comfort",
    "69"    => "Umweltsensor",
    "70"    => "Troll Comfort DuoFern",
    "71"    => "Troll Comfort DuoFern (Lichtmodus)",
    "A0"    => "Handsender (6 Gruppen-48 Geraete)",
    "A1"    => "Handsender (1 Gruppe-48 Geraete)",
    "A2"    => "Handsender (6 Gruppen-1 Geraet)",
    "A3"    => "Handsender (1 Gruppe-1 Geraet)",
    "A4"    => "Wandtaster",
    "A5"    => "Sonnensensor",
    "A7"    => "Funksender UP",
    "A8"    => "HomeTimer",
    "AA"    => "Markisenwaechter",
    "AB"    => "Rauchmelder",
);

my %buttons07 = (
    "01"    => "up",
    "02"    => "stop",
    "03"    => "down",
    "18"    => "stepUp",
    "19"    => "stepDown",
    "1A"    => "pressed",
);

my %buttons0E = (
    "01"    => "off",
    "02"    => "off",
    "03"    => "on",
);

my %deadTimes = (
    0x00    => "off",
    0x10    => "short(160ms)",
    0x20    => "long(480ms)",
    0x30    => "individual",
);

my %closingTimes = (
    0x00    => "off",
    0x01    => "30",
    0x02    => "60",
    0x03    => "90",
    0x04    => "120",
    0x05    => "150",
    0x06    => "180",
    0x07    => "210",
    0x08    => "240",
    0x09    => "error",
    0x0A    => "error",
    0x0B    => "error",
    0x0C    => "error",
    0x0D    => "error",
    0x0E    => "error",
    0x0F    => "error",
);

my %openSpeeds = (
    0x00    => "error",
    0x10    => "11",
    0x20    => "15",
    0x30    => "19",
);


my %commands = (                             
  "remotePair"           => {"noArg"    => "06010000000000"},
  "remoteUnpair"         => {"noArg"    => "06020000000000"},
  "up"                   => {"noArg"    => "0701tt00000000"},
  "stop"                 => {"noArg"    => "07020000000000"},
  "down"                 => {"noArg"    => "0703tt00000000"},
  "position"             => {"value"    => "0707ttnn000000"},
  "level"                => {"value"    => "0707ttnn000000"},
  "sunMode"              => {"on"       => "070801FF000000",
                             "off"      => "070A0100000000"},
  "dusk"                 => {"noArg"    => "070901FF000000"},
  "reversal"             => {"noArg"    => "070C0000000000"},
  "modeChange"           => {"noArg"    => "070C0000000000"},
  "windMode"             => {"on"       => "070D01FF000000",
                             "off"      => "070E0100000000"},
  "rainMode"             => {"on"       => "071101FF000000",
                             "off"      => "07120100000000"},
  "dawn"                 => {"noArg"    => "071301FF000000"},
  "rainDirection"        => {"down"     => "071400FD000000",
                             "up"       => "071400FE000000"},
  "windDirection"        => {"down"     => "071500FD000000",
                             "up"       => "071500FE000000"},
  "slatPosition"         => {"value"    => "071B00000000nn"},
  "sunAutomatic"         => {"on"       => "080100FD000000",
                             "off"      => "080100FE000000"},
  "sunPosition"          => {"value"    => "080100nn000000"},
  "ventilatingMode"      => {"on"       => "080200FD000000",
                             "off"      => "080200FE000000"},
  "ventilatingPosition"  => {"value"    => "080200nn000000"},
  "intermediateMode"     => {"on"       => "080200FD000000",
                             "off"      => "080200FE000000"},
  "intermediateValue"    => {"value"    => "080200nn000000"},
  "saveIntermediateOnStop"=>{"on"       => "080200FB000000",
                             "off"      => "080200FC000000"},
  "runningTime"          => {"value3"   => "0803nn00000000"},
  "timeAutomatic"        => {"on"       => "080400FD000000",
                             "off"      => "080400FE000000"},
  "duskAutomatic"        => {"on"       => "080500FD000000",
                             "off"      => "080500FE000000"},                           
  "manualMode"           => {"on"       => "080600FD000000",
                             "off"      => "080600FE000000"},
  "windAutomatic"        => {"on"       => "080700FD000000",
                             "off"      => "080700FE000000"},
  "rainAutomatic"        => {"on"       => "080800FD000000",
                             "off"      => "080800FE000000"},                                                      
  "dawnAutomatic"        => {"on"       => "080900FD000000",
                             "off"      => "080900FE000000"},
  "tiltInSunPos"         => {"on"       => "080C00FD000000",
                             "off"      => "080C00FE000000"},                           
  "tiltInVentPos"        => {"on"       => "080D00FD000000",
                             "off"      => "080D00FE000000"},
  "tiltAfterMoveLevel"   => {"on"       => "080E00FD000000",
                             "off"      => "080E00FE000000"},
  "tiltAfterStopDown"    => {"on"       => "080F00FD000000",
                             "off"      => "080F00FE000000"},                           
  "defaultSlatPos"       => {"value"    => "0810nn00000000"},
  "blindsMode"           => {"on"       => "081100FD000000",
                             "off"      => "081100FE000000"}, 
  "slatRunTime"          => {"value4"   => "0812nn00000000"},                                                        
  "motorDeadTime"        => {"off"      => "08130000000000",
                             "short"    => "08130100000000",
                             "long"     => "08130200000000"},
  "stairwellFunction"    => {"on"       => "081400FD000000",
                             "off"      => "081400FE000000"},
  "stairwellTime"        => {"value2"   => "08140000wwww00"},
  "10minuteAlarm"        => {"on"       => "081700FD000000",
                             "off"      => "081700FE000000"},
  "automaticClosing"     => {"off"      => "08180000000000",
                             "30"       => "08180001000000",
                             "60"       => "08180002000000",
                             "90"       => "08180003000000",
                             "120"      => "08180004000000",
                             "150"      => "08180005000000",
                             "180"      => "08180006000000",
                             "210"      => "08180007000000",
                             "240"      => "08180008000000"},
  "2000cycleAlarm"       => {"on"       => "081900FD000000",
                             "off"      => "081900FE000000"},
  "openSpeed"            => {"11"       => "081A0001000000",
                             "15"       => "081A0002000000",
                             "19"       => "081A0003000000"},
  "backJump"             => {"on"       => "081B00FD000000",
                             "off"      => "081B00FE000000"},          
  "on"                   => {"noArg"    => "0E03tt00000000"},
  "off"                  => {"noArg"    => "0E02tt00000000"},                          
                                                                                      
);

my %commandsStatus = (
  "getStatus"       => "0F",
  "getWeather"      => "13",
  "getTime"         => "10",
  );

my %setsDefaultRollerShutter = (
  "getStatus:noArg"                     => "",
  "up:noArg"                            => "",
  "down:noArg"                          => "",
  "stop:noArg"                          => "",
  "dusk:noArg"                          => "",
  "dawn:noArg"                          => "",
  "sunMode:on,off"                      => "",
  "position:slider,0,1,100"             => "",
  "sunPosition:slider,0,1,100"          => "",
  "ventilatingPosition:slider,0,1,100"  => "",
  "dawnAutomatic:on,off"                => "",
  "duskAutomatic:on,off"                => "",
  "manualMode:on,off"                   => "",
  "sunAutomatic:on,off"                 => "",
  "timeAutomatic:on,off"                => "",
  "ventilatingMode:on,off"              => "",
  "remotePair:noArg"                    => "",
  "remoteUnpair:noArg"                  => "",
);

my %setsRolloTube = (
  "windAutomatic:on,off"                => "",
  "rainAutomatic:on,off"                => "",
  "windDirection:up,down"               => "",
  "rainDirection:up,down"               => "",
  "windMode:on,off"                     => "",
  "rainMode:on,off"                     => "",
  "reversal:on,off"                     => "",
);

my %setsTroll = (
  "windAutomatic:on,off"                => "",
  "rainAutomatic:on,off"                => "",
  "windDirection:up,down"               => "",
  "rainDirection:up,down"               => "",
  "windMode:on,off"                     => "",
  "rainMode:on,off"                     => "",
  "runningTime:slider,0,1,150"          => "",
  "motorDeadTime:off,short,long"        => "",
  "reversal:on,off"                     => "",    
);

my %setsBlinds = (
  "tiltInSunPos:on,off"                => "",
  "tiltInVentPos:on,off"               => "",
  "tiltAfterMoveLevel:on,off"          => "",
  "tiltAfterStopDown:on,off"           => "",
  "defaultSlatPos:slider,0,1,100"      => "",
  "slatRunTime:slider,0,100,5000"      => "",
  "slatPosition:slider,0,1,100"        => "",   
);                            

my %setsSwitchActor = (
  "getStatus:noArg"                     => "",
  "dawnAutomatic:on,off"                => "",
  "duskAutomatic:on,off"                => "",
  "manualMode:on,off"                   => "",
  "sunAutomatic:on,off"                 => "",
  "timeAutomatic:on,off"                => "",
  "sunMode:on,off"                      => "",
  "modeChange:on,off"                   => "",
  "stairwellFunction:on,off"            => "",
  "stairwellTime:slider,0,10,3200"      => "",
  "on:noArg"                            => "",
  "off:noArg"                           => "",
  "remotePair:noArg"                    => "",
  "remoteUnpair:noArg"                  => "",
);

my %setsUmweltsensor = (
  "getStatus:noArg"                     => "",
  "getWeather:noArg"                    => "",
  "getTime:noArg"                       => "",   
);

my %setsUmweltsensor00 = (
  "getWeather:noArg"                    => "",
  "getTime:noArg"                       => "",   
);

my %setsUmweltsensor01 = (
  "windAutomatic:on,off"                => "",
  "rainAutomatic:on,off"                => "",
  "windDirection:up,down"               => "",
  "rainDirection:up,down"               => "",
  "windMode:on,off"                     => "",
  "rainMode:on,off"                     => "",
  "runningTime:slider,0,1,100"          => "",
  "reversal:on,off"                     => "",   
);

my %setsSX5 = (
  "getStatus:noArg"                     => "",
  "up:noArg"                            => "",
  "down:noArg"                          => "",
  "stop:noArg"                          => "",
  "position:slider,0,1,100"             => "",
  "ventilatingPosition:slider,0,1,100"  => "",
  "manualMode:on,off"                   => "",
  "timeAutomatic:on,off"                => "",
  "ventilatingMode:on,off"              => "",
  "10minuteAlarm:on,off"                => "",
  "automaticClosing:off,30,60,90,120,150,180,210,240" => "",
  "2000cycleAlarm:on,off"               => "",
  "openSpeed:11,15,19"                  => "",
  "backJump:on,off"                     => "",
  "remotePair:noArg"                    => "",
  "remoteUnpair:noArg"                  => "",
);

my %setsDimmer = (
  "getStatus:noArg"                     => "",
  "level:slider,0,1,100"                => "",
  "on:noArg"                            => "",
  "off:noArg"                           => "",
  "dawnAutomatic:on,off"                => "",
  "duskAutomatic:on,off"                => "",
  "manualMode:on,off"                   => "",
  "sunAutomatic:on,off"                 => "",
  "timeAutomatic:on,off"                => "",
  "sunMode:on,off"                      => "",
  "modeChange:on,off"                   => "",
  "stairwellFunction:on,off"            => "",
  "stairwellTime:slider,0,10,3200"      => "",
  "runningTime:slider,0,1,255"          => "",
  "intermediateMode:on,off"             => "",
  "intermediateValue:slider,0,1,100"    => "",
  "saveIntermediateOnStop:on,off"       => "",                         
  "remotePair:noArg"                    => "",
  "remoteUnpair:noArg"                  => "",
);

my $duoStatusRequest     = "0DFFnn400000000000000000000000000000yyyyyy01";
my $duoCommand           = "0Dccnnnnnnnnnnnnnn000000000000zzzzzzyyyyyy00";

#####################################
sub
DUOFERN_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^(06|0F).{42}";
  $hash->{SetFn}     = "DUOFERN_Set";
  $hash->{DefFn}     = "DUOFERN_Define";
  $hash->{UndefFn}   = "DUOFERN_Undef";
  $hash->{ParseFn}   = "DUOFERN_Parse";
  $hash->{RenameFn}  = "DUOFERN_Rename";
  $hash->{AttrFn}    = "DUOFERN_Attr";
  $hash->{AttrList}  = "IODev timeout ". $readingFnAttributes;
  #$hash->{AutoCreate}=
  #      { "DUOFERN" => { GPLOT => "", FILTER => "%NAME" } };
}

###################################
sub
DUOFERN_Set($@)
{
  my ($hash, @a) = @_;

  return "set $hash->{NAME} needs at least one parameter" if(@a < 2);

  my $me   = shift @a;
  my $cmd  = shift @a;
  my $arg  = shift @a;
  my $arg2 = shift @a;
  my $code = substr($hash->{CODE},0,6);
  my $name = $hash->{NAME};
    
  my %sets;
  
  %sets = (%setsDefaultRollerShutter, %setsRolloTube)                         if ($hash->{CODE} =~ /^49..../);
  %sets = (%setsDefaultRollerShutter, %setsTroll, ("blindsMode:on,off"=> "")) if ($hash->{CODE} =~ /^(42|4B|4C|70)..../);
  %sets = (%setsDefaultRollerShutter, %setsTroll)                             if ($hash->{CODE} =~ /^47..../);
  %sets = (%setsDefaultRollerShutter)                                         if ($hash->{CODE} =~ /^(40|41|61|65)..../);
  %sets = (%setsUmweltsensor)                                                 if ($hash->{CODE} =~ /^69....$/);
  %sets = (%setsUmweltsensor00)                                               if ($hash->{CODE} =~ /^69....00/);  
  %sets = (%setsDefaultRollerShutter, %setsUmweltsensor01)                    if ($hash->{CODE} =~ /^69....01/);
  %sets = (%setsSwitchActor)                                                  if ($hash->{CODE} =~ /^43....(01|02)/);
  %sets = ("getStatus:noArg"=> "")                                            if ($hash->{CODE} =~ /^43....$/);
  %sets = (%setsSwitchActor)                                                  if ($hash->{CODE} =~ /^(46|71)..../);
  %sets = (%setsSX5)                                                          if ($hash->{CODE} =~ /^4E..../);
  %sets = (%setsDimmer)                                                       if ($hash->{CODE} =~ /^48..../);

  my $blindsMode=ReadingsVal($name, "blindsMode", "off");
  %sets = (%sets, %setsBlinds)    if ($blindsMode eq "on");
  
  return join(" ", sort keys %sets) if ($cmd eq "?");

  if (exists $commandsStatus{$cmd}) { 
    my $buf = $duoStatusRequest;
    $buf =~ s/nn/$commandsStatus{$cmd}/;
    $buf =~ s/yyyyyy/$code/;
    
    IOWrite( $hash, $buf );
    return undef;
    
  } elsif ($cmd eq "clear") { 
    my @cH = ($hash);
    delete $_->{READINGS} foreach (@cH);
    return undef;

  } elsif(exists $commands{$cmd}) {
    my $subCmd;
    my $chanNo = "01";
    my $argV = "00";
    my $argW = "0000";
    my $timer ="00";
    my $buf = $duoCommand;
    my $command;
    
    $chanNo = $hash->{chanNo} if ($hash->{chanNo});
    
    if(exists $commands{$cmd}{noArg}) {
      $timer= "01" if ($arg && ($arg eq "timer"));
      $subCmd = "noArg";
      $argV = "00";
      
    } elsif (exists $commands{$cmd}{value}) {
      $timer= "01" if ($arg2 && ($arg2 eq "timer"));
      return "Missing argument" if (!defined($arg)); 
      return "Wrong argument $arg" if ($arg !~ m/^\d+$/ || $arg < 0 || $arg > 100);	
      $subCmd = "value";
      $argV = sprintf "%02x", $arg ;
      
    } elsif (exists $commands{$cmd}{value2}) {
      return "Missing argument" if (!defined($arg)); 
      return "Wrong argument $arg" if ($arg !~ m/^\d+$/ || $arg < 0 || $arg > 3200); 
      $subCmd = "value2";
      $argW = sprintf "%04x", $arg * 10;
    
    } elsif (exists $commands{$cmd}{value3}) {
      my $maxArg = 150;
      $maxArg = 255 if ($code =~ m/^48..../); 
      $timer= "01" if ($arg2 && ($arg2 eq "timer"));
      return "Missing argument" if (!defined($arg)); 
      return "Wrong argument $arg" if ($arg !~ m/^\d+$/ || $arg < 0 || $arg > $maxArg); 
      $subCmd = "value3";
      $argV = sprintf "%02x", $arg ;
    
    } elsif (exists $commands{$cmd}{value4}) {
      $timer= "01" if ($arg2 && ($arg2 eq "timer"));
      return "Missing argument" if (!defined($arg)); 
      return "Wrong argument $arg" if ($arg !~ m/^\d+$/ || $arg < 0 || $arg > 5000);
      $arg = $arg/100; 
      $subCmd = "value4";
      $argV = sprintf "%02x", $arg ;
             
    } else {
      return "Missing argument" if (!defined($arg)); 
      $subCmd = $arg;
      $argV = "00";
    }
    
    return "Wrong argument $arg" if (!exists $commands{$cmd}{$subCmd});
    
    $command = $commands{$cmd}{$subCmd};
    
    $buf =~ s/yyyyyy/$code/;
    $buf =~ s/nnnnnnnnnnnnnn/$command/;
    $buf =~ s/nn/$argV/;
    $buf =~ s/tt/$timer/;
    $buf =~ s/wwww/$argW/;
    $buf =~ s/cc/$chanNo/;

    IOWrite( $hash, $buf );
    
    if ($hash->{device}) {
      $hash = $defs{$hash->{device}};
    }
       
    return undef;
  }

  return "Unknown argument $cmd, choose one of ". join(" ", sort keys %sets); 
}

#####################################
sub
DUOFERN_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> DUOFERN <code>"
            if(int(@a) < 3 || int(@a) > 5);
  return "Define $a[0]: wrong CODE format: specify a 6 digit hex value"
                if($a[2] !~ m/^[a-f0-9]{6,8}$/i);

  my $code = uc($a[2]);
  $hash->{CODE} = $code;
  my $name = $hash->{NAME};
  
  if(length($code) == 8) {# define a channel
    my $chn = substr($code, 6, 2);
    my $devCode = substr($code, 0, 6);
    
    my $devHash = $modules{DUOFERN}{defptr}{$devCode};
    return "please define a device with code:".$devCode." first" if(!$devHash);

    my $devName = $devHash->{NAME};
    $hash->{device} = $devName;          #readable ref to device name
    $hash->{chanNo} = $chn;              #readable ref to Channel
    $devHash->{"channel_$chn"} = $name;  #reference in device as well
    
  }
  
  $modules{DUOFERN}{defptr}{$code} = $hash;
  
  AssignIoPort($hash);
  
  if (exists $devices{substr($hash->{CODE},0,2)}) {
  	$hash->{SUBTYPE} = $devices{substr($hash->{CODE},0,2)};
  } else {
  	$hash->{SUBTYPE} = "unknown";
  }
  
  readingsSingleUpdate($hash, "state", "Initialized", 1);
  
  if ($hash->{CODE} =~ m/^(40|41|42|43|46|47|48|49|4B|4C|4E|61|62|65|69|70|71)....$/) {
    $hash->{helper}{timeout}{t} = 30;
    InternalTimer(gettimeofday()+$hash->{helper}{timeout}{t}, "DUOFERN_StatusTimeout", $hash, 0);
    $hash->{helper}{timeout}{count} = 2;
  }
    
  
  return undef;
}

#####################################
sub 
DUOFERN_Undef($$) 
{
  my ($hash, $name) = @_;
  my $devName = $hash->{device};
  my $code = $hash->{DEF};
  my $chn = substr($code,6,2);
  if ($chn){# delete a channel
    my $devHash = $defs{$devName};
    delete $devHash->{"channel_$chn"} if ($devName);
  }
  else{# delete a device
    CommandDelete(undef,$hash->{$_}) foreach (grep(/^channel_/,keys %{$hash}));
  }
  delete($modules{CUL_HM}{defptr}{$code});
  return undef;
}

#####################################
sub
DUOFERN_Rename($$$) 
{
  my ($name, $oldName) = @_;
  my $hash = $defs{$name};
  if ($hash->{chanNo}) {# we are channel, inform the device
    my $devHash = $defs{$hash->{device}};
    $devHash->{"channel_".$hash->{chanNo}} = $name;
  
  } else {# we are a device - inform channels if exist
    foreach (grep (/^channel_/, keys%{$hash})){
      my $chnHash = $defs{$hash->{$_}};
      $chnHash->{device} = $name;
    }
  }
  return;
}

#####################################
sub
DUOFERN_Attr(@)
{
  my ($cmd,$name,$aName,$aVal) = @_;
  if($aName eq "timeout") {
    if ($cmd eq "set"){
      return "timeout must be between 0 and 180" if ($aVal !~ m/^\d+$/ || $aVal < 0 || $aVal > 180);
    }
  }  

  return undef;
}

#####################################
sub
DUOFERN_Parse($$)
{
  my ($hash,$msg) = @_;

  my $code = substr($msg,30,6);
  $code = substr($msg,36,6) if ($msg =~ m/81.{42}/);

  my $def = $modules{DUOFERN}{defptr}{$code};
   
  my $def01;
  my $def02;
  
  if(!$def) {
    DoTrigger("global","UNDEFINED DUOFERN_$code DUOFERN $code");
    $def = $modules{DUOFERN}{defptr}{$code};
    if(!$def) {
      Log3 $hash, 1, "DUOFERN UNDEFINED, code $code";
      return "UNDEFINED DUOFERN_$code DUOFERN $code $msg";
    }
  }
  
  $hash = $def;
  my $name = $hash->{NAME};  
  
  if ($msg =~ m/0602.{40}/) {
    readingsSingleUpdate($hash, "state", "paired", 1);
    delete $hash->{READINGS}{unpaired};
    Log3 $hash, 1, "DUOFERN device paired, code $code";
  
  } elsif ($msg =~ m/0603.{40}/) {
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "unpaired", 1  , 1);
    readingsBulkUpdate($hash, "state", "unpaired"  , 1);
    readingsEndUpdate($hash, 1); # Notify is done by Dispatch
    Log3 $hash, 1, "DUOFERN device unpaired, code $code";
  
  } elsif ($msg =~ m/0FFF0F.{38}/) {
    my $format = substr($msg, 6, 2);
    my $ver    = substr($msg, 24, 1).".".substr($msg, 25, 1);
    my $state;   
    
    readingsSingleUpdate($hash, "version", $ver, 0);
    
    RemoveInternalTimer($hash);
    delete $hash->{helper}{timeout};
    
    if ($code =~ m/^69..../) {
      readingsSingleUpdate($hash, "state", "OK", 1);
      $def01 = $modules{DUOFERN}{defptr}{$code."01"};
      if(!$def01) {
        DoTrigger("global","UNDEFINED DUOFERN_$code"."_actor DUOFERN $code"."01");
        $def01 = $modules{DUOFERN}{defptr}{$code."01"};
      }
      
    } elsif ($code =~ m/^43..../) {
      readingsSingleUpdate($hash, "state", "OK", 1);
      $def01 = $modules{DUOFERN}{defptr}{$code."01"};
      if(!$def01) {
	    DoTrigger("global","UNDEFINED DUOFERN_$code"."_01 DUOFERN $code"."01");
	    $def01 = $modules{DUOFERN}{defptr}{$code."01"};
	  }
	  $def02 = $modules{DUOFERN}{defptr}{$code."02"};
      if(!$def02) {
        DoTrigger("global","UNDEFINED DUOFERN_$code"."_02 DUOFERN $code"."02");
        $def02 = $modules{DUOFERN}{defptr}{$code."02"};
      }
    }
    
    $hash = $def01 if ($def01);
    
    if ($format eq "21") {  #RolloTron
      my $pos         =  hex(substr($msg, 22, 2)) & 0x7F;
      my $ventPos     =  hex(substr($msg, 12, 2)) & 0x7F;
      my $ventMode    = (hex(substr($msg, 12, 2)) & 0x80 ? "on" : "off");
      my $sunPos      =  hex(substr($msg, 20, 2)) & 0x7F;
      my $sunMode     = (hex(substr($msg, 20, 2)) & 0x80 ? "on" : "off");
      my $timerAuto   = (hex(substr($msg,  8, 2)) & 0x01 ? "on" : "off");
      my $sunAuto     = (hex(substr($msg,  8, 2)) & 0x04 ? "on" : "off");
      my $dawnAuto    = (hex(substr($msg, 10, 2)) & 0x08 ? "on" : "off");
      my $duskAuto    = (hex(substr($msg,  8, 2)) & 0x08 ? "on" : "off");
      my $manualMode  = (hex(substr($msg,  8, 2)) & 0x80 ? "on" : "off");
      
      $state = $pos;
      $state = "opened"   if ($pos == 0);
      $state = "closed"   if ($pos == 100);
      
      readingsBeginUpdate($hash); 
      readingsBulkUpdate($hash, "ventilatingPosition",  $ventPos,     1);
      readingsBulkUpdate($hash, "ventilatingMode",      $ventMode,    1);
      readingsBulkUpdate($hash, "sunPosition",          $sunPos,      1);
      readingsBulkUpdate($hash, "sunMode",              $sunMode,     1);
      readingsBulkUpdate($hash, "timeAutomatic",        $timerAuto,   1);
      readingsBulkUpdate($hash, "sunAutomatic",         $sunAuto,     1);
      readingsBulkUpdate($hash, "dawnAutomatic",        $dawnAuto,    1);
      readingsBulkUpdate($hash, "duskAutomatic",        $duskAuto,    1);
      readingsBulkUpdate($hash, "manualMode",           $manualMode,  1);
      readingsBulkUpdate($hash, "position",             $pos        , 1);
      readingsBulkUpdate($hash, "state",                $state      , 1);
      readingsEndUpdate($hash, 1); # Notify is done by Dispatch
    
    
    } elsif ($format eq "22") {  #Universal Aktor,Steckdosenaktor
      my $level             =  hex(substr($msg, 22, 2)) & 0x7F;
      my $modeChange        = (hex(substr($msg, 22, 2)) & 0x80 ? "on" : "off");
      my $sunMode           = (hex(substr($msg, 14, 2)) & 0x10 ? "on" : "off");
      my $timerAuto         = (hex(substr($msg, 14, 2)) & 0x01 ? "on" : "off");
      my $sunAuto           = (hex(substr($msg, 14, 2)) & 0x04 ? "on" : "off");
      my $dawnAuto          = (hex(substr($msg, 14, 2)) & 0x40 ? "on" : "off");
      my $duskAuto          = (hex(substr($msg, 14, 2)) & 0x02 ? "on" : "off");
      my $manualMode        = (hex(substr($msg, 14, 2)) & 0x20 ? "on" : "off");
      my $stairwellFunction = (hex(substr($msg, 16, 4)) & 0x8000 ? "on" : "off");
      my $stairwellTime     = (hex(substr($msg, 16, 4)) & 0x7FFF) / 10;
      
      $state = $level;
      $state = "off"   if ($level == 0);
      $state = "on"    if ($level == 100);
      
      readingsBeginUpdate($hash); 
      readingsBulkUpdate($hash, "sunMode",              $sunMode,     1);
      readingsBulkUpdate($hash, "timeAutomatic",        $timerAuto,   1);
      readingsBulkUpdate($hash, "sunAutomatic",         $sunAuto,     1);
      readingsBulkUpdate($hash, "dawnAutomatic",        $dawnAuto,    1);
      readingsBulkUpdate($hash, "duskAutomatic",        $duskAuto,    1);
      readingsBulkUpdate($hash, "manualMode",           $manualMode,  1);
      readingsBulkUpdate($hash, "modeChange",           $modeChange,  1);
      readingsBulkUpdate($hash, "stairwellFunction",    $stairwellFunction,  1);
      readingsBulkUpdate($hash, "stairwellTime",        $stairwellTime,  1);
      readingsBulkUpdate($hash, "level",                $level        , 1);
      readingsBulkUpdate($hash, "state",                $state      , 1);
      readingsEndUpdate($hash, 1); # Notify is done by Dispatch
      
      if ($def02) {
        $hash = $def02;
        $level             =  hex(substr($msg, 20, 2)) & 0x7F;
        $modeChange        = (hex(substr($msg, 20, 2)) & 0x80 ? "on" : "off");
        $sunMode           = (hex(substr($msg, 12, 2)) & 0x10 ? "on" : "off");
        $timerAuto         = (hex(substr($msg, 12, 2)) & 0x01 ? "on" : "off");
        $sunAuto           = (hex(substr($msg, 12, 2)) & 0x04 ? "on" : "off");
        $dawnAuto          = (hex(substr($msg, 12, 2)) & 0x40 ? "on" : "off");
        $duskAuto          = (hex(substr($msg, 12, 2)) & 0x02 ? "on" : "off");
        $manualMode        = (hex(substr($msg, 12, 2)) & 0x20 ? "on" : "off");
        $stairwellFunction = (hex(substr($msg,  8, 4)) & 0x8000 ? "on" : "off");
        $stairwellTime     = (hex(substr($msg,  8, 4)) & 0x7FFF) / 10;
        
        $state = $level;
        $state = "off"   if ($level == 0);
        $state = "on"    if ($level == 100);
        
        readingsBeginUpdate($hash); 
        readingsBulkUpdate($hash, "sunMode",              $sunMode,     1);
        readingsBulkUpdate($hash, "timeAutomatic",        $timerAuto,   1);
        readingsBulkUpdate($hash, "sunAutomatic",         $sunAuto,     1);
        readingsBulkUpdate($hash, "dawnAutomatic",        $dawnAuto,    1);
        readingsBulkUpdate($hash, "duskAutomatic",        $duskAuto,    1);
        readingsBulkUpdate($hash, "manualMode",           $manualMode,  1);
        readingsBulkUpdate($hash, "modeChange",           $modeChange,  1);
        readingsBulkUpdate($hash, "stairwellFunction",    $stairwellFunction,  1);
        readingsBulkUpdate($hash, "stairwellTime",        $stairwellTime,  1);
        readingsBulkUpdate($hash, "level",                $level        , 1);
        readingsBulkUpdate($hash, "state",                $state      , 1);
        readingsEndUpdate($hash, 1); # Notify is done by Dispatch	
      }
      
         
    } elsif ($format eq "23") {  #Troll,Rohrmotor-Aktor
      my $pos               =  hex(substr($msg, 22, 2)) & 0x7F;
      my $reversal          = (hex(substr($msg, 22, 2)) & 0x80 ? "on" : "off");
      my $ventPos           =  hex(substr($msg, 16, 2)) & 0x7F;
      my $ventMode          = (hex(substr($msg, 16, 2)) & 0x80 ? "on" : "off");
      my $sunPos            =  hex(substr($msg, 18, 2)) & 0x7F;
      my $sunMode           = (hex(substr($msg, 14, 2)) & 0x10 ? "on" : "off");
      my $timerAuto         = (hex(substr($msg, 14, 2)) & 0x01 ? "on" : "off");
      my $sunAuto           = (hex(substr($msg, 14, 2)) & 0x04 ? "on" : "off");
      my $dawnAuto          = (hex(substr($msg, 12, 2)) & 0x02 ? "on" : "off");
      my $duskAuto          = (hex(substr($msg, 14, 2)) & 0x02 ? "on" : "off");
      my $manualMode        = (hex(substr($msg, 14, 2)) & 0x20 ? "on" : "off");
      my $windAuto          = (hex(substr($msg, 14, 2)) & 0x40 ? "on" : "off");
      my $windMode          = (hex(substr($msg, 14, 2)) & 0x08 ? "on" : "off");
      my $windDir           = (hex(substr($msg, 12, 2)) & 0x04 ? "down" : "up");
      my $rainAuto          = (hex(substr($msg, 14, 2)) & 0x80 ? "on" : "off");
      my $rainMode          = (hex(substr($msg, 12, 2)) & 0x01 ? "on" : "off");
      my $rainDir           = (hex(substr($msg, 12, 2)) & 0x08 ? "down" : "up");
      my $runningTime       =  hex(substr($msg, 20, 2));
      my $deadTime          =  hex(substr($msg, 12, 2)) & 0x30;
      my $blindsMode        = (hex(substr($msg, 26, 2)) & 0x80 ? "on" : "off");
      my $tiltInSunPos      = (hex(substr($msg, 18, 2)) & 0x80 ? "on" : "off");
      my $tiltInVentPos     = (hex(substr($msg,  8, 2)) & 0x80 ? "on" : "off");
      my $tiltAfterMoveLevel= (hex(substr($msg,  8, 2)) & 0x40 ? "on" : "off");
      my $tiltAfterStopDown = (hex(substr($msg, 10, 2)) & 0x80 ? "on" : "off");
      my $defaultSlatPos    =  hex(substr($msg, 10, 2)) & 0x7F;
      my $slatRunTime       =  hex(substr($msg,  8, 2)) & 0x3F;
      my $slatPosition      =  hex(substr($msg, 26, 2)) & 0x7F; 
      
      $state = $pos;
      $state = "opened"   if ($pos == 0);
      $state = "closed"   if ($pos == 100);
      
      readingsBeginUpdate($hash); 
      readingsBulkUpdate($hash, "ventilatingPosition",  $ventPos,     1);
      readingsBulkUpdate($hash, "ventilatingMode",      $ventMode   , 1);
      readingsBulkUpdate($hash, "sunPosition",          $sunPos     , 1);
      readingsBulkUpdate($hash, "sunMode",              $sunMode    , 1);
      readingsBulkUpdate($hash, "timeAutomatic",        $timerAuto  , 1);
      readingsBulkUpdate($hash, "sunAutomatic",         $sunAuto    , 1);
      readingsBulkUpdate($hash, "dawnAutomatic",        $dawnAuto   , 1);
      readingsBulkUpdate($hash, "duskAutomatic",        $duskAuto   , 1);
      readingsBulkUpdate($hash, "manualMode",           $manualMode , 1);
      readingsBulkUpdate($hash, "windAutomatic",        $windAuto   , 1);
      readingsBulkUpdate($hash, "windMode",             $windMode   , 1);
      readingsBulkUpdate($hash, "windDirection",        $windDir    , 1);
      readingsBulkUpdate($hash, "rainAutomatic",        $rainAuto   , 1);
      readingsBulkUpdate($hash, "rainMode",             $rainMode   , 1);
      readingsBulkUpdate($hash, "rainDirection",        $rainDir    , 1);
      readingsBulkUpdate($hash, "runningTime",          $runningTime, 1);
      readingsBulkUpdate($hash, "motorDeadTime",        $deadTimes{$deadTime}, 1);
      readingsBulkUpdate($hash, "position",             $pos        , 1);
      readingsBulkUpdate($hash, "reversal",             $reversal   , 1);
      readingsBulkUpdate($hash, "blindsMode",           $blindsMode , 1);
      
       if ($blindsMode eq "on") {
         readingsBulkUpdate($hash, "tiltInSunPos",      $tiltInSunPos , 1);
         readingsBulkUpdate($hash, "tiltInVentPos",     $tiltInVentPos , 1);
         readingsBulkUpdate($hash, "tiltAfterMoveLevel",$tiltAfterMoveLevel , 1);
         readingsBulkUpdate($hash, "tiltAfterStopDown", $tiltAfterStopDown , 1);
         readingsBulkUpdate($hash, "defaultSlatPos",    $defaultSlatPos , 1);
         readingsBulkUpdate($hash, "slatRunTime",       $slatRunTime , 1);
         readingsBulkUpdate($hash, "slatPosition",      $slatPosition , 1);
       } else {
         delete($hash->{READINGS}{tiltInSunPos});
         delete($hash->{READINGS}{tiltInVentPos});
         delete($hash->{READINGS}{tiltAfterMoveLevel});
         delete($hash->{READINGS}{tiltAfterStopDown});
         delete($hash->{READINGS}{defaultSlatPos});
         delete($hash->{READINGS}{slatRunTime});
         delete($hash->{READINGS}{slatPosition});
       }
      
      
      readingsBulkUpdate($hash, "state",                $state      , 1);
      readingsEndUpdate($hash, 1); # Notify is done by Dispatch
      
       
    } elsif ($format eq "24") {  #RolloTube,SX5
      my $pos         =  hex(substr($msg, 22, 2)) & 0x7F;
      my $reversal    = (hex(substr($msg, 22, 2)) & 0x80 ? "on" : "off");
      my $ventPos     =  hex(substr($msg, 16, 2)) & 0x7F;
      my $ventMode    = (hex(substr($msg, 16, 2)) & 0x80 ? "on" : "off");
      my $sunPos      =  hex(substr($msg, 18, 2)) & 0x7F;
      my $sunMode     = (hex(substr($msg, 14, 2)) & 0x10 ? "on" : "off");
      my $timerAuto   = (hex(substr($msg, 14, 2)) & 0x01 ? "on" : "off");
      my $sunAuto     = (hex(substr($msg, 14, 2)) & 0x04 ? "on" : "off");
      my $dawnAuto    = (hex(substr($msg, 12, 2)) & 0x02 ? "on" : "off");
      my $duskAuto    = (hex(substr($msg, 14, 2)) & 0x02 ? "on" : "off");
      my $manualMode  = (hex(substr($msg, 14, 2)) & 0x20 ? "on" : "off");
      my $windAuto    = (hex(substr($msg, 14, 2)) & 0x40 ? "on" : "off");
      my $windMode    = (hex(substr($msg, 14, 2)) & 0x08 ? "on" : "off");
      my $windDir     = (hex(substr($msg, 12, 2)) & 0x04 ? "down" : "up");
      my $rainAuto    = (hex(substr($msg, 14, 2)) & 0x80 ? "on" : "off");
      my $rainMode    = (hex(substr($msg, 12, 2)) & 0x01 ? "on" : "off");
      my $rainDir     = (hex(substr($msg, 12, 2)) & 0x08 ? "down" : "up");
      my $obstacle    = (hex(substr($msg, 12, 2)) & 0x10 ? "1" : "0");
      my $block       = (hex(substr($msg, 12, 2)) & 0x40 ? "1" : "0");
      my $lightCurtain= (hex(substr($msg,  8, 2)) & 0x80 ? "1" : "0");
      my $autoClose   =  hex(substr($msg, 10, 2)) & 0x0F;
      my $openSpeed   =  hex(substr($msg, 10, 2)) & 0x30;
      my $alert2000   = (hex(substr($msg, 10, 2)) & 0x80 ? "on" : "off");
      my $backJump    = (hex(substr($msg, 26, 2)) & 0x01 ? "on" : "off");
      my $alert10     = (hex(substr($msg, 26, 2)) & 0x02 ? "on" : "off");
      
      $state = $pos;
      $state = "opened"   if ($pos == 0);
      $state = "closed"   if ($pos == 100);
      $state = "light curtain" if ($lightCurtain eq "1");
      $state = "obstacle" if ($obstacle eq "1");
      $state = "block"    if ($block eq "1");
      
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash, "manualMode",           $manualMode , 1);
      readingsBulkUpdate($hash, "timeAutomatic",        $timerAuto  , 1);
      readingsBulkUpdate($hash, "ventilatingPosition",  $ventPos    , 1);
      readingsBulkUpdate($hash, "ventilatingMode",      $ventMode   , 1);
      readingsBulkUpdate($hash, "position",             $pos        , 1);
      readingsBulkUpdate($hash, "state",                $state      , 1);
      readingsBulkUpdate($hash, "obstacle",             $obstacle   , 1);
      readingsBulkUpdate($hash, "block",                $block      , 1);
      
      if ($code =~ m/^4E..../) { #SX5
        readingsBulkUpdate($hash, "10minuteAlarm",        $alert10    , 1);
        readingsBulkUpdate($hash, "automaticClosing",     $closingTimes{$autoClose}  , 1);
        readingsBulkUpdate($hash, "2000cycleAlarm",       $alert2000  , 1);
        readingsBulkUpdate($hash, "openSpeed",            $openSpeeds{$openSpeed}  , 1);
        readingsBulkUpdate($hash, "backJump",             $backJump   , 1);
        readingsBulkUpdate($hash, "lightCurtain",         $lightCurtain      , 1);
      } else {
        readingsBulkUpdate($hash, "sunPosition",          $sunPos     , 1);
        readingsBulkUpdate($hash, "sunMode",              $sunMode    , 1);      
        readingsBulkUpdate($hash, "sunAutomatic",         $sunAuto    , 1);
        readingsBulkUpdate($hash, "dawnAutomatic",        $dawnAuto   , 1);
        readingsBulkUpdate($hash, "duskAutomatic",        $duskAuto   , 1);     
        readingsBulkUpdate($hash, "windAutomatic",        $windAuto   , 1);
        readingsBulkUpdate($hash, "windMode",             $windMode   , 1);
        readingsBulkUpdate($hash, "windDirection",        $windDir    , 1);
        readingsBulkUpdate($hash, "rainAutomatic",        $rainAuto   , 1);
        readingsBulkUpdate($hash, "rainMode",             $rainMode   , 1);
        readingsBulkUpdate($hash, "rainDirection",        $rainDir    , 1);
        readingsBulkUpdate($hash, "reversal",             $reversal   , 1);
           
      }
      
      readingsEndUpdate($hash, 1); # Notify is done by Dispatch
    
    } elsif ($format eq "25") {  #Dimmer
      my $stairwellFunction = (hex(substr($msg, 10, 4)) & 0x8000 ? "on" : "off");
      my $stairwellTime     = (hex(substr($msg, 10, 4)) & 0x7FFF) / 10;
      my $timerAuto         = (hex(substr($msg, 14, 2)) & 0x01 ? "on" : "off");
      my $duskAuto          = (hex(substr($msg, 14, 2)) & 0x02 ? "on" : "off");
      my $sunAuto           = (hex(substr($msg, 14, 2)) & 0x04 ? "on" : "off");
      my $sunMode           = (hex(substr($msg, 14, 2)) & 0x08 ? "on" : "off");
      my $manualMode        = (hex(substr($msg, 14, 2)) & 0x20 ? "on" : "off");
      my $dawnAuto          = (hex(substr($msg, 14, 2)) & 0x40 ? "on" : "off");
      my $intemedSave       = (hex(substr($msg, 14, 2)) & 0x80 ? "on" : "off");
      my $runningTime       =  hex(substr($msg, 18, 2));
      my $intemedVal        =  hex(substr($msg, 20, 2)) & 0x7F;
      my $intermedMode      = (hex(substr($msg, 20, 2)) & 0x80 ? "on" : "off");
      my $level             =  hex(substr($msg, 22, 2)) & 0x7F;
      my $modeChange        = (hex(substr($msg, 22, 2)) & 0x80 ? "on" : "off");
      
      $state = $level;
      $state = "off"   if ($level == 0);
      $state = "on"    if ($level == 100);
       
      readingsBeginUpdate($hash); 
      readingsBulkUpdate($hash, "stairwellFunction",      $stairwellFunction,  1);
      readingsBulkUpdate($hash, "stairwellTime",          $stairwellTime,  1);
      readingsBulkUpdate($hash, "timeAutomatic",          $timerAuto    , 1);
      readingsBulkUpdate($hash, "duskAutomatic",          $duskAuto     , 1);
      readingsBulkUpdate($hash, "sunAutomatic",           $sunAuto      , 1);
      readingsBulkUpdate($hash, "sunMode",                $sunMode      , 1);
      readingsBulkUpdate($hash, "manualMode",             $manualMode   , 1);
      readingsBulkUpdate($hash, "dawnAutomatic",          $dawnAuto     , 1);
      readingsBulkUpdate($hash, "saveIntermediateOnStop", $intemedSave  , 1);  
      readingsBulkUpdate($hash, "runningTime",            $runningTime  , 1);
      readingsBulkUpdate($hash, "intermediateValue",      $intemedVal   , 1);
      readingsBulkUpdate($hash, "intermediateMode",       $intermedMode , 1);
      readingsBulkUpdate($hash, "level",                  $level        , 1);
      readingsBulkUpdate($hash, "modeChange",             $modeChange   , 1);
      readingsBulkUpdate($hash, "state",                  $state        , 1);
      readingsEndUpdate($hash, 1); # Notify is done by Dispatch  
      
    } else {
      Log3 $hash, 2, "DUOFERN unknown msg: $msg";
    }
        
  } elsif ($msg =~ m/0FFF07.{38}/) {
    if($msg =~ m/0FFF070801FF.*/) {
      readingsSingleUpdate($hash, "event", "beginnSun", 1);
    } elsif($msg =~ m/0FFF070901FF.*/) {
         readingsSingleUpdate($hash, "event", "dusk", 1);
    } elsif($msg =~ m/0FFF070A0100.*/) {
         readingsSingleUpdate($hash, "event", "endSun", 1);
    } elsif($msg =~ m/0FFF071301FF.*/) {
         readingsSingleUpdate($hash, "event", "dawn", 1);
         
    } elsif($msg =~ m/0FFF07(1A|18|19|01|02|03).*/) {
      my $button = substr($msg, 6, 2);
        my $group = substr($msg, 14, 2);
        if($button =~ m/^(1A)/) {
            readingsSingleUpdate($hash, "state", "Btn$button.$group", 1);
        } else {
            readingsSingleUpdate($hash, "state", "Btn$button", 1);
        }
        if (exists $buttons07{$button}) {
          readingsSingleUpdate($hash, "channel$group", $buttons07{$button}, 1);
        } else {
          readingsSingleUpdate($hash, "channel$group", "$button", 1);
        }
        
    } else {
      Log3 $hash, 2, "DUOFERN unknown msg: $msg";
    }
  	
  } elsif ($msg =~ m/0F0107.{38}/) {
    my $button = substr($msg, 6, 2);
    my $group = substr($msg, 14, 2);
    
    if($code =~ m/^(A0|A2)..../) {
      readingsSingleUpdate($hash, "state", "Btn$button.$group", 1);
    } else {
      readingsSingleUpdate($hash, "state", "Btn$button", 1);
    }
    if (exists $buttons07{$button}) {
      readingsSingleUpdate($hash, "channel$group", $buttons07{$button}, 1);
    } else {
      readingsSingleUpdate($hash, "channel$group", "$button", 1);
    }
    
  } elsif ($msg =~ m/0FFF0E.{38}/) {
    my $button = substr($msg, 6, 2);
    my $group = substr($msg, 14, 2);
    
    readingsSingleUpdate($hash, "state", "Btn$button.$group", 1);
    
    if (exists $buttons0E{$button}) {
      readingsSingleUpdate($hash, "channel$group", $buttons0E{$button}, 1);
    } else {
      readingsSingleUpdate($hash, "channel$group", "$button", 1);
    }
  
  } elsif ($msg =~ m/0F011322.{36}/) {  
    $def01 = $modules{DUOFERN}{defptr}{$code."00"};
    if(!$def01) {
      DoTrigger("global","UNDEFINED DUOFERN_$code"."_sensor DUOFERN $code"."00");
      $def01 = $modules{DUOFERN}{defptr}{$code."00"};
    }
      
    $hash = $def01;
   
    my $brightnessExp   = (hex(substr($msg,  8, 4)) & 0x0400 ? 1000 : 1);
    my $brightness      = (hex(substr($msg,  8, 4)) & 0x01FF) * $brightnessExp;
    my $sunDirection    =  hex(substr($msg, 14, 2)) * 1.5 ;
    my $sunHeight       =  hex(substr($msg, 16, 2)) - 90 ;
    my $temperature     = (hex(substr($msg, 18, 4)) & 0x7FFF)/10 - 40 ;
    my $isRaining       = (hex(substr($msg, 18, 4)) & 0x8000 ? 1 : 0);
    my $wind            =  hex(substr($msg, 22, 4));
    
    my $state = "T: ".$temperature;
    $state .= " W: ".$wind;
    $state .= " IR: ".$isRaining;
    $state .= " B: ".$brightness;
    
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "brightness",     $brightness,     1);
    readingsBulkUpdate($hash, "sunDirection",   $sunDirection,    1);
    readingsBulkUpdate($hash, "sunHeight",      $sunHeight,      1);
    readingsBulkUpdate($hash, "temperature",    $temperature,     1);
    readingsBulkUpdate($hash, "isRaining",      $isRaining,     1);
    readingsBulkUpdate($hash, "state",          $state,     1);
    readingsBulkUpdate($hash, "wind",           $wind,     1);
    readingsEndUpdate($hash, 1); # Notify is done by Dispatch
  
  } elsif ($msg =~ m/0FFF1020.{36}/) {
    $def01 = $modules{DUOFERN}{defptr}{$code."00"};
    if(!$def01) {
      DoTrigger("global","UNDEFINED DUOFERN_$code"."_sensor DUOFERN $code"."00");
      $def01 = $modules{DUOFERN}{defptr}{$code."00"};
    }
      
    $hash = $def01;
    
    my $year    = substr($msg, 12, 2);
    my $month   = substr($msg, 14, 2);
    my $day     = substr($msg, 18, 2);
    my $hour    = substr($msg, 20, 2);
    my $minute  = substr($msg, 22, 2);
    my $second  = substr($msg, 24, 2);
    
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "date",   "20".$year."-".$month."-".$day,     1);
    readingsBulkUpdate($hash, "time",   $hour.":".$minute.":".$second,      1);
    readingsEndUpdate($hash, 1); # Notify is done by Dispatch
  
  } elsif ($msg =~ m/810003CC.{36}/) {
    $hash->{helper}{timeout}{t} = AttrVal($hash->{NAME}, "timeout", "60");    
    InternalTimer(gettimeofday()+$hash->{helper}{timeout}{t}, "DUOFERN_StatusTimeout", $hash, 0);
    $hash->{helper}{timeout}{count} = 4;
  
  } elsif ($msg =~ m/810108AA.{36}/) {
    readingsSingleUpdate($hash, "state", "MISSING ACK", 1);
    foreach (grep (/^channel_/, keys%{$hash})){
      my $chnHash = $defs{$hash->{$_}};
      readingsSingleUpdate($chnHash, "state", "MISSING ACK", 1);
    }
    Log3 $hash, 3, "DUOFERN error: $name MISSING ACK";
                   
  } else {
    Log3 $hash, 2, "DUOFERN unknown msg: $msg";
  }
  
  DoTrigger($def01->{NAME}, undef) if ($def01);
  DoTrigger($def02->{NAME}, undef) if ($def02);
  
  return $name;
}

#####################################
sub
DUOFERN_StatusTimeout($)
{
    my ($hash) = @_;
    my $code = substr($hash->{CODE},0,6);
    my $name = $hash->{NAME};
    
    if ($hash->{helper}{timeout}{count} > 0) {
      my $buf = $duoStatusRequest;
      $buf =~ s/nn/$commandsStatus{getStatus}/;
      $buf =~ s/yyyyyy/$code/;
      
      if ($hash->{helper}{timeout}{cmd}) {
        IOWrite( $hash, $hash->{helper}{timeout}{cmd} );
      } else {
        IOWrite( $hash, $buf );
      }
      
      $hash->{helper}{timeout}{count} -= 1;
      InternalTimer(gettimeofday()+$hash->{helper}{timeout}{t}, "DUOFERN_StatusTimeout", $hash, 0);
      
      Log3 $hash, 3, "DUOFERN no ACK, request Status";
      
    } else {
      readingsSingleUpdate($hash, "state", "MISSING STATUS", 1);
      foreach (grep (/^channel_/, keys%{$hash})){
        my $chnHash = $defs{$hash->{$_}};
        readingsSingleUpdate($chnHash, "state", "MISSING STATUS", 1);
      }
      Log3 $hash, 3, "DUOFERN error: $name MISSING STATUS";
    }
    
    return undef;
}


1;

=pod
=begin html

<a name="DUOFERN"></a>
<h3>DUOFERN</h3>
<ul>

  Support for DuoFern devices via the <a href="#DUOFERNSTICK">DuoFern USB Stick</a>.<br>
  <br><br>

  <a name="DUOFERN_define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; DUOFERN &lt;code&gt;</code>
    <br><br>
    &lt;code&gt; specifies the radio code of the DuoFern device<br><br>
    Example:<br>
    <ul>
      <code>define myDuoFern DUOFERN 49ABCD</code><br>
    </ul>
  </ul>
  <br>

  <a name="DUOFERN_set"></a>
  <b>Set</b>
  <ul>
    <li><b>up [timer]</b><br>
        Move the roller shutter upwards. If parameter <b>timer</b> is used the command will
        only be executed if timeAutomatic is activated.
        </li><br>
    <li><b>down [timer]</b><br>
        Move the roller shutter downwards. If parameter <b>timer</b> is used the command will
        only be executed if timeAutomatic is activated.
        </li><br>
    <li><b>stop</b><br>
        Stop motion.
        </li><br>
    <li><b>position &lt;value&gt; [timer]</b><br>
        Set roller shutter to a desired absolut level. If parameter <b>timer</b> is used the 
        command will only be executed if timeAutomatic is activated.
        </li><br>
    <li><b>on [timer]</b><br>
        Switch on the actor. If parameter <b>timer</b> is used the command will
        only be executed if timeAutomatic is activated.
        </li><br>
    <li><b>off [timer]</b><br>
        Switch off the actor. If parameter <b>timer</b> is used the command will
        only be executed if timeAutomatic is activated.
        </li><br>
    <li><b>level &lt;value&gt; [timer]</b><br>
        Set actor to a desired absolut level. If parameter <b>timer</b> is used the 
        command will only be executed if timeAutomatic is activated.
        </li><br>
    <li><b>getStatus</b><br>
        Sends a status request message to the DuoFern device.
        </li><br>
    <li><b>dusk</b><br>
        Move roller shutter downwards if duskAutomatic is activated.
        </li><br>
    <li><b>dawn</b><br>
        Move roller shutter upwards if dawnAutomatic is activated.
        </li><br>
    <li><b>manualMode [on|off]</b><br>
        Activates the manual mode. If manual mode is active 
        all automatic functions will be ignored.
        </li><br>
    <li><b>timeAutomatic [on|off]</b><br>
        Activates the timer automatic.
        </li><br>
    <li><b>sunAutomatic [on|off]</b><br>
        Activates the sun automatic.
        </li><br>
    <li><b>dawnAutomatic [on|off]</b><br>
        Activates the dawn automatic.
        </li><br>
    <li><b>duskAutomatic [on|off]</b><br>
        Activates the dusk automatic.
        </li><br>
    <li><b>rainAutomatic [on|off]</b><br>
        Activates the rain automatic.
        </li><br>
    <li><b>windAutomatic [on|off]</b><br>
        Activates the wind automatic.
        </li><br>
    <li><b>sunMode [on|off]</b><br>
        Activates the sun mode. If sun automatic is activated, 
        the roller shutter will move to the sunPosition.
        </li><br>
    <li><b>sunPosition &lt;value&gt;</b><br>
        Set the sun position.
        </li><br>
    <li><b>ventilatingMode [on|off]</b><br>
        Activates the ventilating mode. If activated, the roller 
        shutter will stop on ventilatingPosition when moving down.
        </li><br>
    <li><b>ventilatingPosition &lt;value&gt;</b><br>
        Set the ventilating position.
        </li><br>
    <li><b>windMode [on|off]</b><br>
        Activates the wind mode. If wind automatic and wind mode is 
        activated, the roller shutter moves in windDirection and ignore any automatic
        or manual command.<br>
        The wind mode ends 15 minutes after last activation automaticly.
        </li><br>
    <li><b>windDirection [up|down]</b><br>
        Movemet direction for wind mode.
        </li><br>
    <li><b>rainMode [on|off]</b><br>
        Activates the rain mode. If rain automatic and rain mode is 
        activated, the roller shutter moves in rainDirection and ignore any automatic
        command.<br>
        The rain mode ends 15 minutes after last activation automaticly.
        </li><br>
    <li><b>rainDirection [up|down]</b><br>
        Movemet direction for rain mode.
        </li><br>
    <li><b>runningTime &lt;sec&gt;</b><br>
        Set the motor running time.
        </li><br>
    <li><b>motorDeadTime [off|short|long]</b><br>
        Set the motor dead time.
        </li><br>
    <li><b>remotePair</b><br>
        Activates the pairing mode of the actor.<br>
        Some actors accept this command in unpaired mode up to two hours afte power up.
        </li><br>
    <li><b>remoteUnpair</b><br>
        Activates the unpairing mode of the actor.
        </li><br>
    <li><b>reversal [on|off]</b><br>
        Reversal of direction of rotation.
        </li><br>
    <li><b>modeChange [on|off]</b><br>
        Inverts the on/off state of a switch actor or change then modus of a dimming actor.
        </li><br>
    <li><b>stairwellFunction [on|off]</b><br>
        Activates the stairwell function of a switch/dimming actor.
        </li><br>    
    <li><b>stairwellTime &lt;sec&gt;</b><br>
        Set the stairwell time.
        </li><br>    
    <li><b>blindsMode [on|off]</b><br>
        Activates the blinds mode.
        </li><br>
    <li><b>position &lt;value&gt;</b><br>
        Set the slat to a desired absolut level.
        </li><br>   
    <li><b>defaultSlatPos &lt;value&gt;</b><br>
        Set the default slat position.
        </li><br>   
    <li><b>slatRunTime &lt;msec&gt;</b><br>
        Set the slat running time.
        </li><br>   
    <li><b>tiltInSunPos [on|off]</b><br>
        Tilt slat after blind moved to sun position.
        </li><br>
    <li><b>tiltInVentPos [on|off]</b><br>
        Tilt slat after blind moved to ventilation position.
        </li><br>
    <li><b>tiltAfterMoveLevel [on|off]</b><br>
        Tilt slat after blind moved to an absolute position.
        </li><br>
    <li><b>tiltAfterStopDown [on|off]</b><br>
        Tilt slat after stopping blind while moving down.
        </li><br>
    <li><b>10minuteAlarm [on|off]</b><br>
        Activates the alarm sound of the SX5 when the door is left open for longer than 10 minutes.
        </li><br>
    <li><b>2000cycleAlarm [on|off]</b><br>
        Activates the alarm sounds of the SX5 when the SX5 has run 2000 cycles.
        </li><br>
    <li><b>automaticClosing [off|30|60|90|120|150|180|210|240]</b><br>
        Set the automatic closing time of the SX5 (sec).
        </li><br>
    <li><b>openSpeed [11|15|19]</b><br>
        Set the open speed of the SX5 (cm/sec).
        </li><br>    
    <li><b>backJump [on|off]</b><br>
        If activated the SX5 moves briefly in the respective opposite direction after reaching the end point.
        </li><br>     
  </ul>
  <br>

  <a name="DUOFERN_get"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="DUOFERN_attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#IODev">IODev</a></li><br>
    <li><b>timeout &lt;sec&gt;</b><br>
        After sending a command to an actor, the actor must respond with its status within this time. If no status message is received,
        up to two getStatus commands are resend.<br>
        Default 60s.
        </li><br>
  </ul>
  <br>

</ul>

=end html

=cut
