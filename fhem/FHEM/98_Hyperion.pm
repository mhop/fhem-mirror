#####################################################################################
# $Id$
#
# Usage
# 
# define <name> Hyperion <IP or HOSTNAME> <PORT> <INTERVAL>
#
#####################################################################################

package main;

use strict;
use warnings;

use Color;

use JSON;
use SetExtensions;
use DevIo;

my %Hyperion_sets =
(
  "adjustRed"         => "textField",
  "adjustGreen"       => "textField",
  "adjustBlue"        => "textField",
  "blacklevel"        => "textField",
  "colorTemperature"  => "textField",
  "dim"               => "slider,0,1,100",
  "dimDown"           => "noArg",
  "dimUp"             => "noArg",
  "correction"        => "textField",
  "clear"             => "textField",
  "clearall"          => "noArg",
  "gamma"             => "textField",
  "luminanceGain"     => "slider,0,0.010,1.999,1",
  "luminanceMinimum"  => "slider,0,0.010,1.999,1",
  "mode"              => "clearall,effect,off,rgb",
  "off"               => "noArg",
  "on"                => "noArg",
  "rgb"               => "colorpicker,RGB",
  "saturationGain"    => "slider,0,0.010,1.999,1",
  "saturationLGain"   => "slider,0,0.010,1.999,1",
  "threshold"         => "textField",
  "toggle"            => "noArg",
  "valueGain"         => "slider,0,0.010,1.999,1",
  "whitelevel"        => "textField"
);

my $Hyperion_requiredVersion    = "1.03.2";
my $Hyperion_serverinfo         = {"command" => "serverinfo"};
my $Hyperion_webCmd             = "rgb:effect:mode:toggle:on:off";
my $Hyperion_webCmd_config      = "rgb:effect:configFile:mode:toggle:on:off";
my $Hyperion_homebridgeMapping  = "On=state,subtype=TV.Licht,valueOn=/rgb.*/,cmdOff=off,cmdOn=mode+rgb ".
                                  "On=state,subtype=Umgebungslicht,valueOn=clearall,cmdOff=off,cmdOn=clearall ".
                                  "On=state,subtype=Effekt,valueOn=/effect.*/,cmdOff=off,cmdOn=mode+effect ";
                                  # "On=state,subtype=Knight.Rider,valueOn=/.*Knight_rider/,cmdOff=off,cmdOn=effect+Knight_rider " .
                                  # "On=configFile,subtype=Eingang.HDMI,valueOn=hyperion-hdmi,cmdOff=configFile+hyperion,cmdOn=configFile+hyperion-hdmi ";

sub Hyperion_Initialize($)
{
  my ($hash) = @_;
  $hash->{AttrFn}     = "Hyperion_Attr";
  $hash->{DefFn}      = "Hyperion_Define";
  $hash->{GetFn}      = "Hyperion_Get";
  $hash->{NotifyFn}   = "Hyperion_Notify";
  $hash->{ReadFn}     = "Hyperion_Read";
  $hash->{SetFn}      = "Hyperion_Set";
  $hash->{UndefFn}    = "Hyperion_Undef";
  $hash->{AttrList}   = "disable:1 ".
                        "hyperionBin ".
                        "hyperionConfigDir ".
                        "hyperionDefaultDuration ".
                        "hyperionDefaultPriority ".
                        "hyperionDimStep ".
                        "hyperionNoSudo:1 ".
                        "hyperionSshUser ".
                        "hyperionVersionCheck:0 ".
                        "queryAfterSet:0 ".
                        $readingFnAttributes;
  FHEM_colorpickerInit();
}

sub Hyperion_Define($$)
{
  my ($hash,$def) = @_;
  my @args = split("[ \t]+",$def);
  return "Usage: define <name> Hyperion <IP> <PORT> [<INTERVAL>]" if (@args < 4);
  my ($name,$type,$host,$port,$interval) = @args;
  if ($interval)
  {
    $hash->{INTERVAL} = $interval;
  }
  else
  {
    delete $hash->{INTERVAL};
  }
  $hash->{IP}     = $host;
  $hash->{PORT}   = $port;
  $hash->{DeviceName} = $host.":".$port;
  $hash->{helper}{sets} = join(" ",map {"$_:$Hyperion_sets{$_}"} keys %Hyperion_sets);
  $interval       = undef unless defined $interval;
  $interval       = 5 if ($interval && $interval < 5);
  RemoveInternalTimer($hash);
  Hyperion_OpenDev($hash);
  if ($init_done)
  {
    Hyperion_GetUpdate($hash);
  }
  else
  {
    InternalTimer(gettimeofday() + $interval,"Hyperion_GetUpdate",$hash,0);
  }
  $attr{$name}{room} = "Hyperion" if (!$attr{$name}{room});
  return undef;
}

sub Hyperion_DoInit($)
{
  my ($hash) = @_;
  DevIo_SimpleWrite($hash,encode_json($Hyperion_serverinfo)."\n",2);
  return undef;
}

sub Hyperion_Notify($$)
{
  my ($hash,$dev) = @_;
  my $name  = $hash->{NAME};
  return if ($dev->{NAME} ne "global");
  return if (!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));
  return undef if( AttrVal($name, "disable", 0) );
  Hyperion_OpenDev($hash);
  return undef;
}

sub Hyperion_OpenDev($)
{
  my ($hash) = @_;
  DevIo_CloseDev($hash);
  $hash->{STATE} = DevIo_OpenDev($hash,0,"Hyperion_DoInit",sub($$$) {
    my ($h,$err) = @_;
    readingsSingleUpdate($hash,"lastError",$err,1) if($err);
    readingsSingleUpdate($hash,"serverResponse","ERROR",1);
    readingsSingleUpdate($hash,"state","ERROR",1) if (Value($hash->{NAME}) ne "ERROR");
    return $err ? "Error: $err" : $hash->{DeviceName}." connected";
  });
  return undef;
}

sub Hyperion_Undef($$)
{                     
  my ($hash,$name) = @_;
  RemoveInternalTimer($hash);
  DevIo_CloseDev($hash);
  return undef;                  
}

sub Hyperion_list2array($$)
{
  my ($list,$round) = @_;
  my @arr;
  foreach my $part (split(",",$list))
  {
    $part = sprintf($round,$part) * 1;
    push @arr,$part;
  }
  return \@arr;
}

sub Hyperion_isLocal($)
{
  my ($hash) = @_;
  return 1 if ($hash->{IP} eq "localhost" || $hash->{IP} eq "127.0.0.1");
  return undef;
}

sub Hyperion_Get($@)
{
  my ($hash,$name,$cmd) = @_;
  my $params = "configFiles:noArg devStateIcon:noArg statusRequest:noArg";
  return "get $name needs one parameter: $params" if (!$cmd);
  
  if ($cmd eq "configFiles")
  {
    Hyperion_GetConfigs($hash);
  }
  elsif ($cmd eq "devStateIcon")
  {
    return Hyperion_devStateIcon($hash);
  }
  elsif ($cmd eq "statusRequest")
  {
    Hyperion_GetUpdate($hash);
  }
  else
  {
    return "Unknown argument $cmd for $name, choose one of $params";
  }
}

sub Hyperion_Read($)
{
  my ($hash)  = @_;
  my $name    = $hash->{NAME};
  my $buf  = DevIo_SimpleRead($hash);
  return undef if (!$buf);
  my $result = ($hash->{PARTIAL}) ? $hash->{PARTIAL}.$buf : $buf;
  $hash->{PARTIAL} = $result;
  return undef if ($buf !~ /(^.+"success":(true|false)\}$)/ );
  Log3 $name,5,"$name: url ".$hash->{DeviceName}." returned result: $result";
  delete $hash->{PARTIAL};
  my %Hyperion_sets_local = %Hyperion_sets;
  if ($result=~ /^\{"success":true\}$/)
  {
    fhem "sleep 1; get $name statusRequest" if (AttrVal($name,"queryAfterSet",1) == 1 || !$hash->{INTERVAL});
    return undef;
  }
  elsif ($result =~ /^\{"info":\{.+\},"success":true\}$/)
  {
    ######################
    if (defined ReadingsVal($name,"previous_mode",undef))
    {
      # set new reading to former value
      fhem "setreading $name mode_before_off ".ReadingsVal($name,"previous_mode","");
      # delete old reading
      fhem "deletereading $name previous_mode";
    }
    ######################
    my $obj         = eval {from_json($result)};
    my $data        = $obj->{info};
    if (AttrVal($name,"hyperionVersionCheck",1) == 1)
    {
      my $error;
      $error          = "Can't detect your version of hyperion!" if (!$data->{hyperion_build}->[0]->{version});
      if (!$error)
      {
        my $ver       = (split("V",(split(" ",$data->{hyperion_build}->[0]->{version}))[0]))[1];
        $ver          =~ s/\.//g;
        my $rver      = $Hyperion_requiredVersion;
        $rver         =~ s/\.//g;
        $error        = "Your version of hyperion (detected version: ".$data->{hyperion_build}->[0]->{version}.") is not (longer) supported by this module!" if ($ver<$rver);
      }
      if ($error)
      {
        $error = "ATTENTION!!! $error Please update your hyperion to V$Hyperion_requiredVersion at least using HyperCon...";
        Log3 $name, 1, $error;
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash,"serverResponse","ERROR");
        Hyperion_readingsBulkUpdateIfChanged($hash,"state","ERROR");
        Hyperion_readingsBulkUpdateIfChanged($hash,"lastError",$error);
        readingsEndUpdate($hash,1);
        return undef;
      }
    }
    my $vers        = $data->{hyperion_build}->[0]->{version};
    my $prio        = (defined $data->{priorities}->[0]->{priority}) ? $data->{priorities}->[0]->{priority} : undef;
    my $duration    = (defined $data->{priorities}->[0]->{duration_ms} && $data->{priorities}->[0]->{duration_ms} > 999) ? int($data->{priorities}->[0]->{duration_ms} / 1000) : 0;
    $duration       = ($duration) >= 1 ? $duration : "infinite";
    my $adj         = $data->{adjustment}->[0];
    my $col         = $data->{activeLedColor}->[0]->{'HEX Value'}->[0];
    my $configs     = ReadingsVal($name,".configs",undef);
    my $corr        = $data->{correction}->[0];
    my $effects     = $data->{effects};
    my $effectList  = join(",",map {"$_->{name}"} @{$effects});
    $effectList     =~ s/ /_/g;
    my $script      = $data->{activeEffects}->[0]->{script};
    my $temp        = $data->{temperature}->[0];
    my $trans       = $data->{transform}->[0];
    my $id          = $trans->{id};
    my $adjR        = join(",",@{$adj->{redAdjust}});
    my $adjG        = join(",",@{$adj->{greenAdjust}});
    my $adjB        = join(",",@{$adj->{blueAdjust}});
    my $corS        = join(",",@{$corr->{correctionValues}});
    my $temP        = join(",",@{$temp->{correctionValues}});
    my $blkL        = sprintf("%.3f",$trans->{blacklevel}->[0]).",".sprintf("%.3f",$trans->{blacklevel}->[1]).",".sprintf("%.3f",$trans->{blacklevel}->[2]);
    my $gamM        = sprintf("%.3f",$trans->{gamma}->[0]).",".sprintf("%.3f",$trans->{gamma}->[1]).",".sprintf("%.3f",$trans->{gamma}->[2]);
    my $thrE        = sprintf("%.3f",$trans->{threshold}->[0]).",".sprintf("%.3f",$trans->{threshold}->[1]).",".sprintf("%.3f",$trans->{threshold}->[2]);
    my $whiL        = sprintf("%.3f",$trans->{whitelevel}->[0]).",".sprintf("%.3f",$trans->{whitelevel}->[1]).",".sprintf("%.3f",$trans->{whitelevel}->[2]);
    my $lumG        = sprintf("%.3f",$trans->{luminanceGain});
    my $lumM        = (defined $trans->{luminanceMinimum}) ? sprintf("%.3f",$trans->{luminanceMinimum}) : undef;
    my $satG        = sprintf("%.3f",$trans->{saturationGain});
    my $satL        = (defined $trans->{saturationLGain}) ? sprintf("%.3f",$trans->{saturationLGain}) : undef;
    my $valG        = sprintf("%.3f",$trans->{valueGain});
    $Hyperion_sets_local{effect} = $effectList if (length $effectList > 0);
    if ($configs)
    {
      $Hyperion_sets_local{configFile} = $configs;
      $attr{$name}{webCmd} = $Hyperion_webCmd_config if (!$attr{$name}{webCmd} || AttrVal($name,"webCmd","") eq $Hyperion_webCmd);
    }
    $attr{$name}{alias}                   = "Ambilight" if (!$attr{$name}{alias});
    $attr{$name}{devStateIcon}            = '{(Hyperion_devStateIcon($name),"toggle")}' if (!$attr{$name}{devStateIcon});
    $attr{$name}{group}                   = "colordimmer" if (!$attr{$name}{group});
    $attr{$name}{homebridgeMapping}       = $Hyperion_homebridgeMapping if (!$attr{$name}{homebridgeMapping});
    $attr{$name}{icon}                    = "light_led_stripe_rgb" if (!$attr{$name}{icon});
    $attr{$name}{lightSceneParamsToSave}  = "state" if (!$attr{$name}{lightSceneParamsToSave});
    $attr{$name}{room}                    = "Hyperion" if (!$attr{$name}{room});
    $attr{$name}{userattr}                = "lightSceneParamsToSave" if (!$attr{$name}{userattr} && index($attr{"global"}{userattr},"lightSceneParamsToSave") == -1);
    $attr{$name}{userattr}                = "lightSceneParamsToSave ".$attr{$name}{userattr} if ($attr{$name}{userattr} && index($attr{$name}{userattr},"lightSceneParamsToSave") == -1 && index($attr{"global"}{userattr},"lightSceneParamsToSave") == -1);
    $attr{$name}{userattr}                = "homebridgeMapping" if (!$attr{$name}{userattr} && index($attr{"global"}{userattr},"homebridgeMapping") == -1);
    $attr{$name}{userattr}                = "homebridgeMapping ".$attr{$name}{userattr} if ($attr{$name}{userattr} && index($attr{$name}{userattr},"homebridgeMapping") == -1 && index($attr{"global"}{userattr},"homebridgeMapping") == -1);
    $attr{$name}{webCmd}                  = $Hyperion_webCmd if (!$attr{$name}{webCmd} || ($attr{$name}{webCmd} && !$Hyperion_sets_local{configFile}));
    $attr{$name}{webCmd}                  = $Hyperion_webCmd_config if ($attr{$name}{webCmd} && $Hyperion_sets_local{configFile} && $attr{$name}{webCmd} eq $Hyperion_webCmd);
    $hash->{helper}{sets}   = join(" ",map {"$_:$Hyperion_sets_local{$_}"} keys %Hyperion_sets_local);
    $hash->{hostname}       = $data->{hostname} if (($data->{hostname} && !$hash->{hostname}) || ($data->{hostname} && $hash->{hostname} ne $data->{hostname}));
    $hash->{build_version}  = $vers if (($vers && !$hash->{build_version}) || ($vers && $hash->{build_version} ne $vers));
    $hash->{build_time}     = $data->{hyperion_build}->[0]->{time} if (($data->{hyperion_build}->[0]->{time} && !$hash->{build_time}) || ($data->{hyperion_build}->[0]->{time} && $hash->{build_time} ne $data->{hyperion_build}->[0]->{time}));
    readingsBeginUpdate($hash);
    Hyperion_readingsBulkUpdateIfChanged($hash,"adjustRed",$adjR);
    Hyperion_readingsBulkUpdateIfChanged($hash,"adjustGreen",$adjG);
    Hyperion_readingsBulkUpdateIfChanged($hash,"adjustBlue",$adjB);
    Hyperion_readingsBulkUpdateIfChanged($hash,"blacklevel",$blkL);
    Hyperion_readingsBulkUpdateIfChanged($hash,"colorTemperature",$temP);
    Hyperion_readingsBulkUpdateIfChanged($hash,"correction",$corS);
    Hyperion_readingsBulkUpdateIfChanged($hash,"effect",(split(",",$effectList))[0]) if (!defined ReadingsVal($name,"effect",undef));
    Hyperion_readingsBulkUpdateIfChanged($hash,"effect",(split(",",$effectList))[0]) if (!defined ReadingsVal($name,"effect",undef));
    Hyperion_readingsBulkUpdateIfChanged($hash,".effects", $effectList) if ($effectList);
    Hyperion_readingsBulkUpdateIfChanged($hash,"duration",$duration);
    Hyperion_readingsBulkUpdateIfChanged($hash,"gamma",$gamM);
    Hyperion_readingsBulkUpdateIfChanged($hash,"id",$id);
    Hyperion_readingsBulkUpdateIfChanged($hash,"luminanceGain",$lumG);
    Hyperion_readingsBulkUpdateIfChanged($hash,"luminanceMinimum",$lumM) if ($lumM);
    Hyperion_readingsBulkUpdateIfChanged($hash,"priority",$prio) if (defined $prio);
    Hyperion_readingsBulkUpdateIfChanged($hash,"rgb","ff0d0d") if (!defined ReadingsVal($name,"rgb",undef));
    Hyperion_readingsBulkUpdateIfChanged($hash,"saturationGain",$satG);
    Hyperion_readingsBulkUpdateIfChanged($hash,"saturationLGain",$satL) if ($satL);
    Hyperion_readingsBulkUpdateIfChanged($hash,"threshold",$thrE);
    Hyperion_readingsBulkUpdateIfChanged($hash,"valueGain",$valG);
    Hyperion_readingsBulkUpdateIfChanged($hash,"whitelevel",$whiL);
    if ($script)
    {
      my $args = $data->{activeEffects}->[0]->{args};
      foreach my $e (@$effects)
      {
        if ($e->{script} eq $script)
        {
          my $arg = $e->{args};
          my $x   = JSON->new->convert_blessed->canonical->encode($arg);
          my $y   = JSON->new->convert_blessed->canonical->encode($args);

          if ("$x" eq "$y")
          {
            my $en = $e->{name};
            $en =~ s/ /_/g;
            Hyperion_readingsBulkUpdateIfChanged($hash,"effect",$en);
            Hyperion_readingsBulkUpdateIfChanged($hash,"mode","effect");
            Hyperion_readingsBulkUpdateIfChanged($hash,"state","effect $en");
            Hyperion_readingsBulkUpdateIfChanged($hash,"mode_before_off","effect");
            Log3 $name,4,"$name: effect $en";
          }
        }
      }
    }
    elsif ($col)
    {
      my $rgb = lc((split('x',$col))[1]);
      $rgb =~ m/^(..)(..)(..)/;
      my ($r,$g,$b) = Color::hex2rgb($rgb);
      my ($h,$s,$v) = Color::rgb2hsv($r / 255,$g / 255,$b / 255);
      my $dim = int($v * 100);
      Hyperion_readingsBulkUpdateIfChanged($hash,"rgb",$rgb);
      Hyperion_readingsBulkUpdateIfChanged($hash,"dim",$dim);
      Hyperion_readingsBulkUpdateIfChanged($hash,"mode","rgb");
      Hyperion_readingsBulkUpdateIfChanged($hash,"mode_before_off","rgb");
      Hyperion_readingsBulkUpdateIfChanged($hash,"state","rgb $rgb");
      Log3 $name,4,"$name: rgb $rgb";
    }
    else
    {
      if ($prio)
      {
        Hyperion_readingsBulkUpdateIfChanged($hash,"mode","clearall");
        Hyperion_readingsBulkUpdateIfChanged($hash,"mode_before_off","clearall");
        Hyperion_readingsBulkUpdateIfChanged($hash,"state","clearall");
        Log3 $name,4,"$name: clearall";
      }
      else
      {
        Hyperion_readingsBulkUpdateIfChanged($hash,"mode","off");
        Hyperion_readingsBulkUpdateIfChanged($hash,"state","off");
        Log3 $name,4,"$name: off";
      }
    }
    readingsBulkUpdate($hash,"serverResponse","success");
    readingsEndUpdate($hash,1);
  }
  else
  {
    Log3 $name,4,"$name: error while requesting ".$hash->{DeviceName}." - $result";
    readingsBeginUpdate($hash);
    Hyperion_readingsBulkUpdateIfChanged($hash,"lastError","error while requesting ".$hash->{DeviceName});
    readingsBulkUpdate($hash,"serverResponse","ERROR");
    Hyperion_readingsBulkUpdateIfChanged($hash,"state","ERROR") if (Value($name) ne "ERROR");
  }
  return undef;
}

sub Hyperion_GetConfigs($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $ip = $hash->{IP};
  my $dir = AttrVal($name,"hyperionConfigDir","/etc/hyperion/");
  my $com = "ls $dir 2>/dev/null";
  my @files;
  if (Hyperion_isLocal($hash))
  {
    @files = Hyperion_listFilesInDir($hash,$com);
  }
  else
  {
    my $user = AttrVal($name,"hyperionSshUser","pi");
    my $cmd = qx(which ssh);
    chomp($cmd);
    $cmd .= " $user\@$ip $com";
    @files = Hyperion_listFilesInDir($hash,$cmd);
  }
  return "No files found on server $ip in directory $dir. Maybe the wrong directory? If SSH is used, has the user ".AttrVal($name,"hyperionSshUser","pi")." been configured to log in without entering a password (http://www.linuxproblem.org/art_9.html)?" if (scalar(@files) == 0);
  if (scalar @files > 0)
  {
    my $configs = join(",",@files);
    readingsSingleUpdate($hash,".configs",$configs,1) if (ReadingsVal($name,".configs","") ne $configs);
    $attr{$name}{webCmd} = $Hyperion_webCmd_config if (AttrVal($name,"webCmd","") eq $Hyperion_webCmd);
  }
  else
  {
    fhem "deletereading $name .configs" if (defined ReadingsVal($name,".configs",undef));
    $attr{$name}{webCmd} = $Hyperion_webCmd if (AttrVal($name,"webCmd","") eq $Hyperion_webCmd_config);
  }
  Hyperion_GetUpdate($hash);
  return "Found at least one config file. Please refresh this page to see the result.";
}

sub Hyperion_listFilesInDir($$)
{
  my ($hash,$cmd) = @_;
  my $name = $hash->{NAME};
  my $fh;
  my @filelist;
  if (open($fh,"$cmd|"))
  {
    my @files = <$fh>;
    my $count = scalar @files;
    for (my $i = 0; $i < $count; $i++)
    {
      my $file = $files[$i];
      $file =~ s/\s+//gm;
      next if ($file !~ /\w+\.config\.json$/);
      $file =~ s/.config.json$//gm;
      push @filelist,$file;
      Log3 $name,4,"$name: Hyperion_listFilesInDir matching file: \"$file\"";
    }
    close $fh;
  }
  return @filelist;
}

sub Hyperion_GetUpdate(@)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  RemoveInternalTimer($hash);
  if ($hash->{INTERVAL})
  {
    InternalTimer(gettimeofday() + $hash->{INTERVAL},"Hyperion_GetUpdate",$hash,1);
  }
  return undef if (IsDisabled($name) > 0);
  Hyperion_Call($hash);
  return undef;
}

sub Hyperion_Set($@)
{
  my ($hash,$name,@aa) = @_;
  my ($cmd,@args) = @aa;
  my $value = (defined($args[0])) ? $args[0] : undef;
  return "\"set $name\" needs at least one argument and maximum five arguments" if (scalar @aa < 1 || scalar @aa > 4);
  my $duration = (defined $args[1]) ? int $args[1] : int AttrVal($name,"hyperionDefaultDuration",0);
  my $priority = (defined $args[2]) ? int $args[2] : int AttrVal($name,"hyperionDefaultPriority",0);
  my $sets = $hash->{helper}{sets};
  my %obj;
  Log3 $name,4,"$name: Hyperion_Set cmd: $cmd" if (defined $cmd);
  Log3 $name,4,"$name: Hyperion_Set value: $value" if (defined $value && $value ne "");
  Log3 $name,4,"$name: Hyperion_Set duration: $duration, priority: $priority";
  if ($cmd eq "configFile")
  {
    $value = $value.".config.json";
    my $confdir = AttrVal($name,"hyperionConfigDir","/etc/hyperion/");
    my $binpath  = AttrVal($name,"hyperionBin","/usr/bin/hyperiond");
    my $bin = (split("/",$binpath))[scalar(split("/",$binpath)) - 1];
    my $user  = AttrVal($name,"hyperionSshUser","pi");
    my $ip = $hash->{IP};
    my $sudo = ($user eq "root" || int AttrVal($name,"hyperionNoSudo",0) == 1) ? "" : "sudo ";
    my $command = $sudo."killall $bin; sleep 1; ".$sudo."$binpath $confdir$value > /dev/null 2>&1 &";
    my $status;
    my $fh;
    if (Hyperion_isLocal($hash))
    {
      if (open($fh,"$command|"))
      {
        $status = <$fh>;
        close $fh;
      }
    }
    else
    {
      my $com = qx(which ssh);
      chomp $com;
      $com .= " $user\@$ip '$command'";
      if (open($fh,"$com|"))
      {
        $status = <$fh>;
        close $fh;
      }
    }
    if (!$status)
    {
      Log3 $name,4,"$name: restarted Hyperion with $binpath $confdir$value";
      $value =~ s/.config.json$//;
      readingsSingleUpdate($hash,"configFile",$value,1);
      return undef;
    }
    else
    {
      Log3 $name,4,"$name: NOT restarted Hyperion with $binpath $confdir$value, status: $status";
      readingsSingleUpdate($hash,"lastError",$status,1);
      readingsSingleUpdate($hash,"serverResponse","ERROR",1);
      readingsSingleUpdate($hash,"state","ERROR",1) if (Value($name) ne "ERROR");
      return "$name NOT restarted Hyperion with $binpath $confdir$value, status: $status";
    }
  }
  elsif ($cmd eq "rgb")
  {
    return "Value of $cmd has to be in RGB hex format like ffffff or 3F7D90" if ($value !~ /^(\d|[a-f|A-F]){6}$/);
    $value = lc($value);
    my ($r,$g,$b) = Color::hex2rgb($value);
    $obj{color} = [$r,$g,$b];
    $obj{command} = "color";
    $obj{priority} = $priority * 1;
    $obj{duration} = $duration * 1000 if ($duration > 0);
  }
  elsif ($cmd eq "dim")
  {
    return "Value of $cmd has to be between 1 and 100" if ($value !~ /^(\d+)$/ || int($1) > 100 || int($1) < 1);
    my $rgb = ReadingsVal($name,"rgb","ffffff");
    $value = $value + 1 if ($cmd eq "dim" && $value < 100);
    $value = $value / 100;
    my ($r,$g,$b) = Color::hex2rgb($rgb);
    my ($h,$s,$v) = Color::rgb2hsv($r / 255,$g / 255,$b / 255);
    my ($rn,$gn,$bn);
    ($rn,$gn,$bn) = Color::hsv2rgb($h,$s,$value) if ($cmd eq "dim");
    $rn = int($rn * 255);
    $gn = int($gn * 255);
    $bn = int($bn * 255);
    $obj{color} = [$rn,$gn,$bn];
    $obj{command} = "color";
    $obj{priority} = $priority * 1;
    $obj{duration} = $duration * 1000 if ($duration > 0);
  }
  elsif ($cmd eq "dimUp" || $cmd eq "dimDown")
  {
    return "Value of $cmd has to be between 1 and 99" if (defined($value) && $value =~ /°(\d+)$/ && int($1) < 1 && int($1) > 99);
    my $dim = int ReadingsVal($name,"dim",100);
    my $dimStep = (defined $value) ? int $value : int AttrVal($name,"hyperionDimStep",5);
    my $dimUp = ($dim + $dimStep < 100) ? $dim + $dimStep : 100;
    my $dimDown = ($dim - $dimStep > 0) ? $dim - $dimStep : 0;
    fhem "set $name dim $dimUp" if ($cmd eq "dimUp");
    fhem "set $name dim $dimDown" if ($cmd eq "dimDown");
    return undef;
  }
  elsif ($cmd eq "effect")
  {
    return "Effect $value is not available in the effect list of $name!" if ($value !~ /^(\w+)?((_)\w+){0,}$/ || index(ReadingsVal($name,".effects",""),$value) == -1);
    $value =~ s/_/ /g;
    my %ef = ("name" => $value);
    $obj{effect} = \%ef;
    $obj{command} = "effect";
    $obj{priority} = $priority * 1;
    $obj{duration} = $duration * 1000 if ($duration > 0);
  }
  elsif ($cmd eq "clearall")
  {
    return "$cmd need no additional value of $value" if (defined $value);
    $obj{command} = $cmd;
  }
  elsif ($cmd eq "clear")
  {
    return "Value of $cmd has to be between 0 and 65536 in steps of 1" if ($value !~ /^(\d+)$/ || int $1 < 0 || int $1 > 65536);
    $value = int $value;
    $obj{command} = $cmd;
    $obj{priority} = $value * 1;
  }
  elsif ($cmd eq "off")
  {
    return "$cmd need no additional value of $value" if (defined $value);
    $obj{command} = "color";
    $obj{color} = [0,0,0];
    $obj{priority} = 0;
  }
  elsif ($cmd eq "on")
  {
    return "$cmd need no additional value of $value" if (defined $value);
    my $rmode     = ReadingsVal($name,"mode_before_off","rgb");
    my $rrgb      = ReadingsVal($name,"rgb","");
    my $reffect   = ReadingsVal($name,"effect","");
    my ($r,$g,$b) = Color::hex2rgb($rrgb);
    if ($rmode eq "rgb")
    {
      fhem "set ".$name." $rmode $rrgb";
    }
    elsif ($rmode eq "effect")
    {
      fhem "set ".$name." $rmode $reffect";
    }
    elsif ($rmode eq "clearall")
    {
      fhem "set ".$name." clearall";
    }
    return undef;
  }
  elsif ($cmd eq "toggle")
  {
    return "$cmd need no additional value of $value" if (defined $value);
    my $rstate = Value($name);
    if ($rstate ne "off")
    {
      fhem "set ".$name." off";
    }
    else
    {
      fhem "set ".$name." on";
    }
    return undef;
  }
  elsif ($cmd eq "mode")
  {
    return "The value of mode has to be rgb,effect,clearall,off" if ($value !~ /^(off|clearall|rgb|effect)$/);
    Log3 $name,4,"$name: cmd: $cmd, value: $value";
    my $rmode     = $value;
    my $rrgb      = ReadingsVal($name,"rgb","");
    my $reffect   = ReadingsVal($name,"effect","");
    my ($r,$g,$b) = Color::hex2rgb($rrgb);
    if ($rmode eq "rgb")
    {
      fhem "set ".$name." $rmode $rrgb";
    }
    elsif ($rmode eq "effect")
    {
      fhem "set ".$name." $rmode $reffect";
    }
    elsif ($rmode eq "clearall")
    {
      fhem "set ".$name." clearall";
    }
    elsif ($rmode eq "off")
    {
      fhem "set ".$name." $rmode";
    }
    return undef;
  }
  elsif ( $cmd eq "luminanceGain" ||
          $cmd eq "luminanceMinimum" ||
          $cmd eq "saturationGain" ||
          $cmd eq "saturationLGain" ||
          $cmd eq "valueGain"
        )
  {
    return "The value of $cmd has to be between 0.000 an 1.999 in steps of 0.001." if ($value !~ /^(\d)(\.\d)?(\d{1,2})?$/ || int $1 > 1);
    $value          = sprintf("%.3f",$value) * 1;
    my %tr          = ($cmd => $value);
    $obj{command}   = "transform";
    $obj{transform} = \%tr;
  }
  elsif ( $cmd eq "blacklevel" ||
          $cmd eq "gamma" ||
          $cmd eq "threshold" ||
          $cmd eq "whitelevel"
 )
  {
    return "Each of the three comma separated values of $cmd has to be between 0.000 an 9.999 in steps of 0.001" if ($value !~ /^((\d)\.(\d){1,3}),((\d)\.(\d){1,3}),((\d)\.(\d){1,3})$/ || int $1 > 9 || int $4 > 9 || int $7 > 9);
    my $arr = Hyperion_list2array($value,"%.3f");
    my %ar = ($cmd => $arr);
    $obj{command} = "transform";
    $obj{transform} = \%ar;
  }
  elsif ($cmd eq "correction" || $cmd eq "colorTemperature")
  {
    $cmd = "temperature" if ($cmd eq "colorTemperature");
    return "Each of the three comma separated values of $cmd has to be between 0 an 255 in steps of 1" if ($value !~ /^(\d{1,3})?,(\d{1,3})?,(\d{1,3})?$/ || int $1 > 255 || int $2 > 255 || int $3 > 255);
    my $arr = Hyperion_list2array($value,"%d");
    my %ar = ("correctionValues" => $arr);
    $obj{command} = $cmd;
    $obj{$cmd} = \%ar;
  }
  elsif ( $cmd eq "adjustRed" ||
          $cmd eq "adjustGreen" ||
          $cmd eq "adjustBlue"
        )
  {
    return "Each of the three comma separated values of $cmd has to be between 0 an 255 in steps of 1" if ($value !~ /^(\d{1,3})?,(\d{1,3})?,(\d{1,3})?$/ || int $1 > 255 || int $2 > 255 || int $3 > 255);
    $cmd              = "redAdjust" if ($cmd eq "adjustRed");
    $cmd              = "greenAdjust" if ($cmd eq "adjustGreen");
    $cmd              = "blueAdjust" if ($cmd eq "adjustBlue");
    my $arr           = Hyperion_list2array($value,"%d");
    my %ar            = ($cmd => $arr);
    $obj{command}     = "adjustment";
    $obj{adjustment}  = \%ar;
  }
  if (scalar keys %obj)
  {
    Log3 $name,5,"$name: $cmd obj json: ".encode_json(\%obj);
    SetExtensionsCancel($hash);
    Hyperion_Call($hash,\%obj);
  }
  else
  {
    return SetExtensions($hash,$sets,$name,@aa) ;
  }
}

sub Hyperion_Attr(@)
{
  my ($cmd,$name,$attr_name,$attr_value) = @_;
  my $hash  = $defs{$name};
  my $err   = undef;
  my $local = ($hash->{IP} eq "localhost" || $hash->{IP} eq "127.0.0.1") ? "" : undef;
  if ($cmd eq "set")
  {
    if ($attr_name eq "hyperionBin")
    {
      if ($attr_value !~ /^(\/.+){2,}$/)
      {
        $err = "Invalid value $attr_value for attribute $attr_name. Must be a path like /usr/bin/hyperiond.";
      }
      elsif (defined $local && !-e $attr_value)
      {
        $err = "The given file $attr_value is not an available file.";
      }
    }
    elsif ($attr_name eq "hyperionConfigDir")
    {
      if ($attr_value !~ /^\/(.+\/){2,}/)
      {
        $err = "Invalid value $attr_value for attribute $attr_name. Must be a path with trailing slash like /etc/hyperion/.";
      }
      elsif (defined $local && !-d $attr_value)
      {
        $err = "The given directory $attr_value is not an available directory.";
      }
      else
      {
        Hyperion_GetConfigs($hash);
        Hyperion_Call($hash);
      }
    }
    elsif ($attr_name eq "hyperionDefaultPriority" || $attr_name eq "hyperionDefaultDuration")
    {
      $err = "Invalid value $attr_value for attribute $attr_name. Must be a number between 0 and 65536." if ($attr_value !~ /^(\d+)$/ || $1 < 0 || $1 > 65536);
    }
    elsif ($attr_name eq "hyperionDimStep")
    {
      $err = "Invalid value $attr_value for attribute $attr_name. Must be between 1 and 50 in steps of 1, default is 5." if ($attr_value !~ /^(\d+)$/ || $1 < 1 || $1 > 50);
    }
    elsif ($attr_name eq "hyperionNoSudo")
    {
      $err = "Invalid value $attr_value for attribute $attr_name. Can only be value 1." if ($attr_value !~ /^1$/);
    }
    elsif ($attr_name eq "hyperionSshUser")
    {
      if ($attr_value !~ /^\w+$/)
      {
        $err = "Invalid value $attr_value for attribute $attr_name. Must be a name like pi or fhem.";
      }
      else
      {
        Hyperion_GetConfigs($hash);
        Hyperion_Call($hash);
      }
    }
    elsif ($attr_name eq "hyperionVersionCheck")
    {
      $err = "Invalid value $attr_value for attribute $attr_name. Can only be value 0." if ($attr_value !~ /^0$/);
    }
    elsif ($attr_name eq "queryAfterSet")
    {
      if ($attr_value !~ /^0$/)
      {
        $err = "Invalid value $attr_value for attribute $attr_name. Must be 0 when set, default is 1.";
      }
    }
  }
  else
  {
    Hyperion_Call($hash);
  }
  return $err if (defined $err);
  return;
}

sub Hyperion_Call($;$)
{
  my ($hash,$obj) = @_;
  $obj = ($obj) ? $obj : $Hyperion_serverinfo;
  my $name = $hash->{NAME};
  my $json = encode_json($obj);
  return undef if (IsDisabled($name) > 0);
  if (!$hash->{FD})
  {
    # DevIo_CloseDev($hash);
    Hyperion_OpenDev($hash);
    return undef;
  }
  Log3 $name,5,"$name: Hyperion_Call: json object: $json";
  DevIo_SimpleWrite($hash,$json."\n",2);
}

sub Hyperion_devStateIcon($;$)
{
  my ($hash,$state) = @_; 
  $hash = $defs{$hash} if (ref $hash ne "HASH");
  return undef if (!$hash);
  my $name = $hash->{NAME};
  my $rgb = ReadingsVal($name,"rgb","");
  my $dim = ReadingsVal($name,"dim",10);
  my $ico = (int($dim / 10) * 10 < 10) ? 10 : int($dim / 10) * 10;
  return ".*:off:toggle" if (Value($name) eq "off");
  return ".*:light_exclamation" if (Value($name) eq "ERROR");
  return ".*:light_question" if (Value($name) eq "Initialized");
  return ".*:light_light_dim_$ico@#".$rgb.":toggle" if (Value($name) ne "off" && ReadingsVal($name,"mode","") eq "rgb");
  return ".*:light_led_stripe_rgb@#FFFF00:toggle" if (Value($name) ne "off" && ReadingsVal($name,"mode","") eq "effect");
  return ".*:it_television@#0000FF:toggle" if (Value($name) ne "off" && ReadingsVal($name,"mode","") eq "clearall");
}

sub Hyperion_readingsBulkUpdateIfChanged($$$) {
  my ($hash,$read,$value) = @_;
  readingsBulkUpdate($hash,$read,$value) if ReadingsVal($hash->{NAME},$read,"SomeThingTotallyCrazy") ne $value;
}

1;

=pod
=item device
=item summary    provides access to the Hyperion JSON server
=item summary_DE stellt Zugang zum Hyperion JSON Server zur Verf&uuml;gung
=begin html

<a name="Hyperion"></a>
<h3>Hyperion</h3>
<ul>
  With <i>Hyperion</i> it is possible to change the color or start an effect on a hyperion server.<br>
  It's also possible to control the complete color calibration (changes are temorary and will not be written to the config file).<br>
  The Hyperion server must have enabled the JSON server.<br>
  You can also restart Hyperion with different configuration files (p.e. switch input)<br>
  <br>
  <a name="Hyperion_define"></a>
  <p><b>Define</b></p>
  <ul>
    <code>define &lt;name&gt; Hyperion &lt;IP or HOSTNAME&gt; &lt;PORT&gt; [&lt;INTERVAL&gt;]</code><br>
  </ul>
  <br>
  &lt;INTERVAL&gt; is optional for polling.<br>
  <br>
  <i>After defining "get &lt;name&gt; statusRequest" will be called once automatically to get the list of available effects and the current state of the Hyperion server.</i><br>
  <br>
  Example for running Hyperion on local system:
  <br><br>
  <ul>
    <code>define Ambilight Hyperion localhost 19444 10</code><br>
  </ul>
  <br>
  Example for running Hyperion on remote system:
  <br><br>
  <ul>
    <code>define Ambilight Hyperion 192.168.1.4 19444 10</code><br>
  </ul>
  <br>
  <a name="Hyperion_set"></a>
  <p><b>set &lt;required&gt; [optional]</b></p>
  <ul>
    <li>
      <i>adjustBlue &lt;0,0,255&gt;</i><br>
      adjust each color of blue separately (comma separated) (R,G,B)
    </li>
    <li>
      <i>adjustGreen &lt;0,255,0&gt;</i><br>
      adjust each color of green separately (comma separated) (R,G,B)
    </li>
    <li>
      <i>adjustRed &lt;255,0,0&gt;</i><br>
      adjust each color of red separately (comma separated) (R,G,B)
    </li>
    <li>
      <i>blacklevel &lt;0.000,0.000,0.000&gt;</i><br>
      adjust blacklevel of each color separately (comma separated) (R,G,B)
    </li>
    <li>
      <i>clear &lt;1000&gt;</i><br>
      clear a specific priority channel
    </li>
    <li>
      <i>clearall</i><br>
      clear all priority channels / switch to Ambilight mode
    </li>
    <li>
      <i>colorTemperature &lt;255,255,255&gt;</i><br>
      adjust temperature of each color separately (comma separated) (R,G,B)
    </li>
    <li>
      <i>configFile &lt;filename&gt;</i><br>
      restart the Hyperion server with the given configuration file (files will be listed automatically from the given directory in attribute hyperionConfigDir)<br>
      please omit the double extension of the file name (.config.json)
    </li>
    <li>
      <i>correction &lt;255,255,255&gt;</i><br>
      adjust correction of each color separately (comma separated) (R,G,B)
    </li>
    <li>
      <i>dim &lt;percent&gt; [duration] [priority]</i><br>
      dim the rgb light with optional duration in seconds and priority
    </li>
    <li>
      <i>dimDown [delta]</i><br>
      dim down rgb light by steps defined in attribute hyperionDimStep or by given value (default: 10)
    </li>
    <li>
      <i>dimUp [delta]</i><br>
      dim up rgb light by steps defined in attribute hyperionDimStep or by given value (default: 10)
    </li>
    <li>
      <i>effect &lt;effect&gt; [duration] [priority]</i><br>
      set effect (replace blanks with underscore) with optional duration in seconds and priority
    </li>
    <li>
      <i>gamma &lt;1.900,1.900,1.900&gt;</i><br>
      adjust gamma of each color separately (comma separated) (R,G,B)
    </li>
    <li>
      <i>luminanceGain &lt;1.000&gt;</i><br>
      adjust luminanceGain (max. value 1.999)
    </li>
    <li>
      <i>luminanceMinimum &lt;0.000&gt;</i><br>
      adjust luminanceMinimum (max. value 1.999)
    </li>
    <li>
      <i>mode &lt;clearall|effect|off|rgb&gt;</i><br>
      set the light in the specific mode with its previous value
    </li>
    <li>
      <i>off</i><br>
      set the light off while the color is black
    </li>
    <li>
      <i>on</i><br>
      set the light on and restore previous state
    </li>
    <li>
      <i>rgb &lt;RRGGBB&gt; [duration] [priority]</i><br>
      set color in RGB hex format with optional duration in seconds and priority
    </li>
    <li>
      <i>saturationGain &lt;1.100&gt;</i><br>
      adjust saturationGain (max. value 1.999)
    </li>
    <li>
      <i>saturationLGain &lt;1.000&gt;</i><br>
      adjust saturationLGain (max. value 1.999)
    </li>
    <li>
      <i>threshold &lt;0.160,0.160,0.160&gt;</i><br>
      adjust threshold of each color separately (comma separated) (R,G,B)
    </li>
    <li>
      <i>toggle</i><br>
      toggles the light between on and off
    </li>
    <li>
      <i>valueGain &lt;1.700&gt;</i><br>
      adjust valueGain (max. value 1.999)
    </li>
    <li>
      <i>whitelevel &lt;0.700,0.800,0.900&gt;</i><br>
      adjust whitelevel of each color separately (comma separated) (R,G,B)
    </li>
  </ul>  
  <br>
  <a name="Hyperion_get"></a>
  <p><b>Get</b></p>
  <ul>
    <li>
      <i>configFiles</i><br>
      get the available config files in directory from attribute hyperionConfigDir
    </li>
    <li>
      <i>devStateIcon</i><br>
      get the current devStateIcon
    </li>
    <li>
      <i>statusRequest</i><br>
      get the currently set effect or color from the Hyperion server,<br>
      get the internals of Hyperion including available effects
    </li>
  </ul>
  <br>
  <a name="Hyperion_attr"></a>
  <p><b>Attributes</b></p>
  <ul>
    <li>
      <i>hyperionBin</i><br>
      path to the hyperion executable<br>
      default: /usr/bin/hyperiond
    </li>
    <li>
      <i>hyperionConfigDir</i><br>
      path to the hyperion configuration files<br>
      default: /etc/hyperion/
    </li>
    <li>
      <i>hyperionDefaultDuration</i><br>
      default duration<br>
      default: infinity
    </li>
    <li>
      <i>hyperionNoSudo</i><br>
      disable sudo for non-root users<br>
      default: 0
    </li>
    <li>
      <i>hyperionDefaultPriority</i><br>
      default priority<br>
      default: 0
    </li>
    <li>
      <i>hyperionDimStep</i><br>
      dim step for dimDown/dimUp<br>
      default: 5 (percent)
    </li>
    <li>
      <i>hyperionSshUser</i><br>
      user for executing SSH commands
    </li>
    <li>
      <i>hyperionVersionCheck</i><br>
      disable hyperion version check to (maybe) support prior versions<br>
      DO THIS AT YOUR OWN RISK! FHEM MAY CRASH UNEXPECTEDLY!<br>
      default: 1
    </li>
    <li>
      <i>queryAfterSet</i><br>
      If set to 0 the state of the Hyperion server will not be queried after setting, instead the state will be queried on next interval query.<br>
      This is only used when polling is enabled, without polling the state will be queried automatically after set.
    </li>
  </ul>
  <br>
  <a name="Hyperion_read"></a>
  <p><b>Readings</b></p>
  <ul>
    <li>
      <i>adjustBlue</i><br>
      each color of blue separately (comma separated) (R,G,B)
    </li>
    <li>
      <i>adjustGreen</i><br>
      each color of green separately (comma separated) (R,G,B)
    </li>
    <li>
      <i>adjustRed</i><br>
      each color of red separately (comma separated) (R,G,B)
    </li>
    <li>
      <i>blacklevel</i><br>
      blacklevel of each color separately (comma separated) (R,G,B)
    </li>
    <li>
      <i>colorTemperature</i><br>
      temperature of each color separately (comma separated) (R,G,B)
    </li>
    <li>
      <i>configFile</i><br>
      active/previously loaded configuration file, double extension (.config.json) will be omitted
    </li>
    <li>
      <i>correction</i><br>
      correction of each color separately (comma separated) (R,G,B)
    </li>
    <li>
      <i>dim</i><br>
      active/previous dim value (rgb light)
    </li>
    <li>
      <i>duration</i><br>
      active/previous duration in seconds or infinite
    </li>
    <li>
      <i>effect</i><br>
      active/previous effect
    </li>
    <li>
      <i>gamma</i><br>
      gamma for each color separately (comma separated) (R,G,B)
    </li>
    <li>
      <i>id</i><br>
      id of the Hyperion server
    </li>
    <li>
      <i>lastError</i><br>
      last occured error while communicating with the Hyperion server
    </li>
    <li>
      <i>luminanceGain</i><br>
      luminanceGain
    </li>
    <li>
      <i>luminanceMinimum</i><br>
      luminanceMinimum
    </li>
    <li>
      <i>mode</i><br>
      current mode
    </li>
    <li>
      <i>mode_before_off</i><br>
      previous mode before off
    </li>
    <li>
      <i>priority</i><br>
      active/previous priority
    </li>
    <li>
      <i>rgb</i><br>
      active/previous rgb
    </li>
    <li>
      <i>saturationGain</i><br>
      active/previous saturationGain
    </li>
    <li>
      <i>saturationLGain</i><br>
      active/previous saturationLGain
    </li>
    <li>
      <i>serverResponse</i><br>
      last Hyperion server response (success/ERROR)
    </li>
    <li>
      <i>state</i><br>
      current state
    </li>
    <li>
      <i>threshold</i><br>
      threshold of each color separately (comma separated) (R,G,B)
    </li>
    <li>
      <i>valueGain</i><br>
      valueGain - gain of the Ambilight
    </li>
    <li>
      <i>whitelevel</i><br>
      whitelevel of each color separately (comma separated) (R,G,B)
    </li>
  </ul>
</ul>

=end html
=cut
