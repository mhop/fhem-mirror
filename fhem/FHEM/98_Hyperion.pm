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

use DevIo;
use JSON;
use SetExtensions;
use Blocking;

my %Hyperion_sets =
(
  "addEffect"         => "textField",
  "dim"               => "slider,0,1,100",
  "dimDown"           => "textField",
  "dimUp"             => "textField",
  "clear"             => "textField",
  "clearall"          => "noArg",
  "mode"              => "clearall,effect,off,rgb",
  "off"               => "noArg",
  "on"                => "noArg",
  "reopen"            => "noArg",
  "rgb"               => "colorpicker,RGB",
  "toggle"            => "noArg",
  "toggleMode"        => "noArg",
  "valueGainDown"     => "textField",
  "valueGainUp"       => "textField"
);

my $Hyperion_requiredVersion    = "1.03.2";
my $Hyperion_serverinfo         = {"command" => "serverinfo"};
my $Hyperion_webCmd             = "rgb:effect:mode:dimDown:dimUp:on:off";
my $Hyperion_webCmd_config      = "rgb:effect:configFile:mode:dimDown:dimUp:on:off";
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
  $hash->{AttrList}   = "disable:1,0 ".
                        "disabledForIntervals ".
                        "hyperionBin ".
                        "hyperionConfigDir ".
                        "hyperionCustomEffects:textField-long ".
                        "hyperionDefaultDuration ".
                        "hyperionDefaultPriority ".
                        "hyperionDimStep ".
                        "hyperionGainStep ".
                        "hyperionNoSudo:1 ".
                        "hyperionSshUser ".
                        "hyperionToggleModes ".
                        "hyperionVersionCheck:0 ".
                        "queryAfterSet:0 ".
                        $readingFnAttributes;
  FHEM_colorpickerInit();
}

sub Hyperion_Define($$)
{
  my ($hash,$def) = @_;
  my @args = split " ",$def;
  return "Usage: define <name> Hyperion <IP> <PORT> [<INTERVAL>]"
    if (@args < 4);
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
  $interval       = 5 if ($interval && $interval < 5);
  $hash->{NOTIFYDEV} = "global";
  $hash->{DeviceName} = "$host:$port";
  RemoveInternalTimer($hash);
  if ($init_done && !defined $hash->{OLDDEF})
  {
    addToDevAttrList($name,"lightSceneParamsToSave") if (!grep /^lightSceneParamsToSave/,split(" ",$attr{"global"}{userattr}));
    addToDevAttrList($name,"homebridgeMapping:textField-long") if (!grep /^homebridgeMapping/,split(" ",$attr{"global"}{userattr}));
    $attr{$name}{alias} = "Ambilight";
    $attr{$name}{cmdIcon} = "on:general_an off:general_aus dimDown:dimdown dimUp:dimup";
    $attr{$name}{devStateIcon} = '{Hyperion_devStateIcon($name)}';
    $attr{$name}{homebridgeMapping} = $Hyperion_homebridgeMapping;
    $attr{$name}{icon} = "light_led_stripe_rgb";
    $attr{$name}{lightSceneParamsToSave} = "state";
    $attr{$name}{room} = "Hyperion";
    $attr{$name}{webCmd} = $Hyperion_webCmd;
    $attr{$name}{widgetOverride} = "dimUp:noArg dimDown:noArg";
  }
  return Hyperion_OpenDev($hash);
}

sub Hyperion_Notify($$)
{
  my ($hash,$dev) = @_;
  my $name  = $hash->{NAME};
  return if (IsDisabled($name));
  return if (!grep /^REREADCFG|MODIFIED\s$name$/,@{$dev->{CHANGED}});
  return Hyperion_OpenDev($hash);
}

sub Hyperion_OpenDev($)
{
  my ($hash) = @_;
  DevIo_CloseDev($hash);
  DevIo_OpenDev($hash,1,DevIo_SimpleWrite($hash,encode_json($Hyperion_serverinfo),2,1),sub($$$)
  {
    my ($h,$err) = @_;
    InternalTimer(gettimeofday() + 5,"Hyperion_GetUpdate",$hash);
    if ($err)
    {
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash,"lastError",$err);
      readingsBulkUpdate($hash,"serverResponse","ERROR");
      readingsBulkUpdate($hash,"state","ERROR");
      readingsEndUpdate($hash,1);
      return "ERROR: $err";
    }
    else
    {
      return $hash->{DeviceName}." connected";
    }
  });
}

sub Hyperion_Undef($$)
{                     
  my ($hash,$name) = @_;
  RemoveInternalTimer($hash);
  BlockingKill($hash->{helper}{RUNNING_PID}) if ($hash->{helper}{RUNNING_PID});
  DevIo_CloseDev($hash);
  return;                  
}

sub Hyperion_list2array($$)
{
  my ($list,$round) = @_;
  my @arr;
  foreach my $part (split /,/,$list)
  {
    $part = sprintf($round,$part) * 1;
    push @arr,$part;
  }
  return \@arr;
}

sub Hyperion_isLocal($)
{
  my ($ip) = @_;
  return ($ip =~ /^(localhost|127\.0{1,3}\.0{1,3}\.0{0,2}1|::1)$/) ? 1 : undef;
}

sub Hyperion_Get($@)
{
  my ($hash,$name,$cmd) = @_;
  return if (IsDisabled($name) && $cmd ne "?");
  my $params =  "devStateIcon:noArg ".
                "statusRequest:noArg ".
                "configFiles:noArg ";
  return "get $name needs one parameter: $params"
    if (!$cmd);
  if ($cmd eq "configFiles")
  {
    return "Work already/still in progress... Please wait for the current process to finish." if ($hash->{helper}{RUNNING_PID} && !$hash->{helper}{RUNNING_PID}{terminated});
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
  my $buf     = DevIo_SimpleRead($hash);
  return if (!$buf);
  $buf =~ s/[\r\n]//gm;
  my $result  = $hash->{PARTIAL} ? $hash->{PARTIAL}.$buf : $buf;
  $hash->{PARTIAL} = $result;
  return if ($buf !~ /(^.+"success":(true|false)\}$)/);
  Log3 $name,5,"$name: url $hash->{DeviceName} returned result: $result";
  delete $hash->{PARTIAL};
  if ($result =~ /^\{"success":true\}$/)
  {
    AnalyzeCommandChain(undef,"sleep 1; get $name statusRequest")
      if (AttrVal($name,"queryAfterSet",1) == 1 || !$hash->{INTERVAL});
    return;
  }
  elsif ($result =~ /^\{"info":\{.+\},"success":true\}$/)
  {
    my $obj         = eval {decode_json($result)};
    my $data        = $obj->{info};
    if (AttrVal($name,"hyperionVersionCheck",1) == 1)
    {
      my $error;
      $error = "Can't detect your version of hyperion!"
        if (!$data->{hyperion_build}->[0]->{version});
      if (!$error)
      {
        my $ver       = (split /V/,(split " ",$data->{hyperion_build}->[0]->{version})[0])[1];
        $ver          =~ s/\.//g;
        $ver          = $ver * 1;
        my $rver      = $Hyperion_requiredVersion;
        $rver         =~ s/\.//g;
        $rver         = $rver * 1;
        $error        = "Your version of hyperion (detected version: ".$data->{hyperion_build}->[0]->{version}.") is not (longer) supported by this module!" if ($ver<$rver);
      }
      if ($error)
      {
        $error = "ATTENTION!!! $error Please update your hyperion to V$Hyperion_requiredVersion at least using HyperCon...";
        Log3 $name,1,$error;
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash,"serverResponse","ERROR");
        readingsBulkUpdate($hash,"lastError",$error);
        readingsBulkUpdate($hash,"state","ERROR");
        readingsEndUpdate($hash,1);
        return;
      }
    }
    my $vers        = $data->{hyperion_build}->[0]->{version} ? $data->{hyperion_build}->[0]->{version} : "";
    my $prio        = (defined $data->{priorities}->[0]->{priority}) ? $data->{priorities}->[0]->{priority} : "";
    my $duration    = (defined $data->{priorities}->[0]->{duration_ms} && $data->{priorities}->[0]->{duration_ms} > 999) ? int($data->{priorities}->[0]->{duration_ms} / 1000) : 0;
    $duration       = $duration >= 1 ? $duration : "infinite";
    my $adj         = $data->{adjustment}->[0] ? $data->{adjustment}->[0] : undef;
    my $col         = $data->{activeLedColor}->[0]->{"HEX Value"}->[0] ? $data->{activeLedColor}->[0]->{"HEX Value"}->[0] : "";
    $col            = "" if ($col =~ /000000$/);
    my $configs     = ReadingsVal($name,".configs",undef);
    my $corr        = $data->{correction}->[0] ? $data->{correction}->[0] : undef;
    my $effects     = $data->{effects} ? $data->{effects} : undef;
    if ($hash->{helper}{customeffects})
    {
      foreach my $eff (@{$hash->{helper}{customeffects}})
      {
        push @{$effects},$eff;
      }
    }
    my $effectList  = $effects ? join(",",map {"$_->{name}"} @{$effects}) : "";
    $effectList     =~ s/ /_/g;
    my $effargs     = $data->{activeEffects}->[0]->{args} ? JSON->new->convert_blessed->canonical->encode($data->{activeEffects}->[0]->{args}) : undef;
    my $script      = $data->{activeEffects}->[0]->{script} ? $data->{activeEffects}->[0]->{script} : undef;
    my $temp        = $data->{temperature}->[0] ? $data->{temperature}->[0] : undef;
    my $trans       = $data->{transform}->[0] ? $data->{transform}->[0] : undef;
    my $id          = $trans->{id} ? $trans->{id} : undef;
    my $adjR        = $adj ? join(",",@{$adj->{redAdjust}}) : undef;
    my $adjG        = $adj ? join(",",@{$adj->{greenAdjust}}) : undef;
    my $adjB        = $adj ? join(",",@{$adj->{blueAdjust}}) : undef;
    my $corS        = $corr ? join(",",@{$corr->{correctionValues}}) : undef;
    my $temP        = $temp ? join(",",@{$temp->{correctionValues}}) : undef;
    my $blkL        = $trans->{blacklevel} ? sprintf("%.2f",$trans->{blacklevel}->[0]).",".sprintf("%.2f",$trans->{blacklevel}->[1]).",".sprintf("%.2f",$trans->{blacklevel}->[2]) : undef;
    my $gamM        = $trans->{gamma} ? sprintf("%.2f",$trans->{gamma}->[0]).",".sprintf("%.2f",$trans->{gamma}->[1]).",".sprintf("%.2f",$trans->{gamma}->[2]) : undef;
    my $thrE        = $trans->{threshold} ? sprintf("%.2f",$trans->{threshold}->[0]).",".sprintf("%.2f",$trans->{threshold}->[1]).",".sprintf("%.2f",$trans->{threshold}->[2]) : undef;
    my $whiL        = $trans->{whitelevel} ? sprintf("%.2f",$trans->{whitelevel}->[0]).",".sprintf("%.2f",$trans->{whitelevel}->[1]).",".sprintf("%.2f",$trans->{whitelevel}->[2]) : undef;
    my $lumG        = defined $trans->{luminanceGain} ? sprintf("%.2f",$trans->{luminanceGain}) : undef;
    my $lumM        = defined $trans->{luminanceMinimum} ? sprintf("%.2f",$trans->{luminanceMinimum}) : undef;
    my $satG        = defined $trans->{saturationGain} ? sprintf("%.2f",$trans->{saturationGain}) : undef;
    my $satL        = defined $trans->{saturationLGain} ? sprintf("%.2f",$trans->{saturationLGain}) : undef;
    my $valG        = defined $trans->{valueGain} ? sprintf("%.2f",$trans->{valueGain}) : undef;
    $hash->{hostname}       = $data->{hostname} if (($data->{hostname} && !$hash->{hostname}) || ($data->{hostname} && $hash->{hostname} ne $data->{hostname}));
    $hash->{build_version}  = $vers if (($vers && !$hash->{build_version}) || ($vers && $hash->{build_version} ne $vers));
    $hash->{build_time}     = $data->{hyperion_build}->[0]->{time} if (($data->{hyperion_build}->[0]->{time} && !$hash->{build_time}) || ($data->{hyperion_build}->[0]->{time} && $hash->{build_time} ne $data->{hyperion_build}->[0]->{time}));
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,"adjustRed",$adjR);
    readingsBulkUpdate($hash,"adjustGreen",$adjG);
    readingsBulkUpdate($hash,"adjustBlue",$adjB);
    readingsBulkUpdate($hash,"blacklevel",$blkL);
    readingsBulkUpdate($hash,"colorTemperature",$temP);
    readingsBulkUpdate($hash,"correction",$corS);
    readingsBulkUpdate($hash,"effect",(split /,/,$effectList)[0]) if (!defined ReadingsVal($name,"effect",undef));
    readingsBulkUpdate($hash,".effects",$effectList);
    readingsBulkUpdate($hash,"effectArgs",$effargs);
    readingsBulkUpdate($hash,"duration",$duration);
    readingsBulkUpdate($hash,"gamma",$gamM);
    readingsBulkUpdate($hash,"id",$id);
    readingsBulkUpdate($hash,"luminanceGain",$lumG);
    readingsBulkUpdate($hash,"luminanceMinimum",$lumM);
    readingsBulkUpdate($hash,"priority",$prio);
    readingsBulkUpdate($hash,"rgb","ff0d0d") if (!defined ReadingsVal($name,"rgb",undef));
    readingsBulkUpdate($hash,"saturationGain",$satG);
    readingsBulkUpdate($hash,"saturationLGain",$satL);
    readingsBulkUpdate($hash,"threshold",$thrE);
    readingsBulkUpdate($hash,"valueGain",$valG);
    readingsBulkUpdate($hash,"whitelevel",$whiL);
    if ($script)
    {
      my $effname;
      my $tempname;
      foreach my $e (@$effects)
      {
        if ($e->{script} && $e->{script} eq $script)
        {
          $tempname = $e->{name};
          $effname = $e->{name} if (JSON->new->convert_blessed->canonical->encode($e->{args}) eq $effargs);
        }
      }
      if (!$effname)
      {
        foreach my $e (@{$hash->{helper}{customeffects}})
        {
          $effname = $e->{name} if (JSON->new->convert_blessed->canonical->encode($e->{args}) eq $effargs);
        }
      }
      $effname = $effname ? $effname : $tempname;
      $effname =~ s/ /_/g;
      readingsBulkUpdate($hash,"effect",$effname);
      readingsBulkUpdate($hash,"mode","effect");
      readingsBulkUpdate($hash,"state","effect $effname");
      readingsBulkUpdate($hash,"mode_before_off","effect");
      Log3 $name,4,"$name: effect $effname";
    }
    elsif ($col)
    {
      my $rgb = lc((split /x/,$col)[1]);
      my ($r,$g,$b) = Color::hex2rgb($rgb);
      my ($h,$s,$v) = Color::rgb2hsv($r / 255,$g / 255,$b / 255);
      my $dim = int($v * 100);
      readingsBulkUpdate($hash,"rgb",$rgb);
      readingsBulkUpdate($hash,"dim",$dim);
      readingsBulkUpdate($hash,"mode","rgb");
      readingsBulkUpdate($hash,"mode_before_off","rgb");
      readingsBulkUpdate($hash,"state","rgb $rgb");
      Log3 $name,4,"$name: rgb $rgb";
    }
    else
    {
      if ($prio && defined $data->{priorities}->[0]->{duration_ms} && !defined $data->{priorities}->[1]->{priority})
      {
        readingsBulkUpdate($hash,"mode","clearall");
        readingsBulkUpdate($hash,"mode_before_off","clearall");
        readingsBulkUpdate($hash,"state","clearall");
        Log3 $name,4,"$name: clearall";
      }
      else
      {
        readingsBulkUpdate($hash,"mode","off");
        readingsBulkUpdate($hash,"state","off");
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
    readingsBulkUpdate($hash,"lastError","error while requesting ".$hash->{DeviceName});
    readingsBulkUpdate($hash,"serverResponse","ERROR");
    readingsBulkUpdate($hash,"state","ERROR");
    readingsEndUpdate($hash,1);
  }
  return;
}

sub Hyperion_GetConfigs($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $ip = $hash->{IP};
  my $dir = AttrVal($name,"hyperionConfigDir","/etc/hyperion/");
  my $com = "ls $dir";
  if (!Hyperion_isLocal($ip))
  {
    my $ssh = qx(which ssh);
    chomp $ssh;
    return "SSH client could NOT be found!" if (!$ssh);
    my $user = AttrVal($name,"hyperionSshUser","pi");
    $com = "$ssh $user\@$ip '$com'";
  }
  Log3 $name,4,"$name: lsCmd: $com";
  $com = encode_base64($com);
  $hash->{helper}{RUNNING_PID} = BlockingCall("Hyperion_ExecCmd","$name|$com","Hyperion_GetConfigs_finished");
  return "Working in background...";
}

sub Hyperion_GetConfigs_finished($)
{
  my ($string)    = @_;
  my @a           = split /\|/,$string;
  my $name        = $a[0];
  my @files;
  @files          = split " ",$a[1] if ($a[1]);
  my $hash        = $defs{$name};
  my $ip = $hash->{IP};
  my $dir = AttrVal($name,"hyperionConfigDir","/etc/hyperion/");
  delete $hash->{helper}{RUNNING_PID};
  my @filelist;
  foreach (@files)
  {
    my $file = $_;
    next if ($file !~ /^([-\.\w]+)\.config\.json$/);
    $file = $1;
    push @filelist,$file;
    Log3 $name,4,"$name: matching config file: \"$_\"";
  }
  if (@filelist)
  {
    my $configs = join(",",@filelist);
    readingsSingleUpdate($hash,".configs",$configs,0);
    CommandAttr(undef,"$name webCmd $Hyperion_webCmd_config") if (AttrVal($name,"webCmd","") eq $Hyperion_webCmd && @filelist > 1);
    CommandAttr(undef,"$name webCmd $Hyperion_webCmd") if (AttrVal($name,"webCmd","") eq $Hyperion_webCmd_config && @filelist < 2);
  }
  else
  {
    CommandDeleteReading(undef,"$name .configs") if (ReadingsVal($name,".configs",""));
    CommandAttr(undef,"$name webCmd $Hyperion_webCmd") if (AttrVal($name,"webCmd","") eq $Hyperion_webCmd_config);
    Log3 $name,3,"$name: No files found on server \"$ip\" in directory \"$dir\".\nMaybe the wrong directory?\n\nIf SSH is used, has the user \"".AttrVal($name,"hyperionSshUser","pi")."\" been configured to log in without\nentering a password (http://www.linuxproblem.org/art_9.html)?";
  }
  Hyperion_GetUpdate($hash);
  return;
}

sub Hyperion_GetUpdate(@)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  RemoveInternalTimer($hash);
  return if (IsDisabled($name));
  InternalTimer(gettimeofday() + $hash->{INTERVAL},"Hyperion_GetUpdate",$hash) if ($hash->{INTERVAL});
  if (!$hash->{FD})
  {
    Hyperion_OpenDev($hash);
    return;
  }
  Hyperion_Call($hash);
  return;
}

sub Hyperion_ExecCmd($)
{
  my ($string) = @_;
  my @a = split /\|/,$string;
  my $name = $a[0];
  my $cmd = decode_base64($a[1]);
  my $hash = $defs{$name};
  my @qx = qx($cmd);
  my @ret;
  my $re = "";
  foreach (@qx)
  {
    chomp $_;
    $_ =~ s/^[\s\t]{1,}/ /;
    push @ret,$_;
  }
  $re .= join " ",@ret if (@ret);
  return "$name|$re";
}

sub Hyperion_Kill_finished($)
{
  my ($string)    = @_;
  my @a           = split /\|/,$string;
  my $name        = $a[0];
  my $error       = $a[1];
  my $hash        = $defs{$name};
  delete $hash->{helper}{RUNNING_PID};
  if ($error)
  {
    Log3 $name,3,"$name: Not able to stop Hyperion! Error: $error";
    readingsSingleUpdate($hash,"lastError",$error,1);
  }
  else
  {
    Log3 $name,3,"$name: Hyperion has been stopped";
    RemoveInternalTimer($hash);
    DevIo_Disconnected($hash);
  }
  return undef;
}

sub Hyperion_Restart($)
{
  my ($string)    = @_;
  my @a           = split /\|/,$string;
  my $name        = $a[0];
  my $error       = $a[1];
  my $hash        = $defs{$name};
  delete $hash->{helper}{RUNNING_PID};
  if ($error)
  {
    Log3 $name,3,"$name: Not able to stop Hyperion! Error: $error";
    readingsSingleUpdate($hash,"lastError",$error,1);
  }
  else
  {
    my $cmd = $hash->{helper}{startCmd};
    $hash->{helper}{RUNNING_PID} = BlockingCall("Hyperion_ExecCmd","$name|$cmd","Hyperion_Restart_finished");
  }
  return undef;
}

sub Hyperion_Restart_finished($)
{
  my ($string)    = @_;
  my @a           = split /\|/,$string;
  my $name        = $a[0];
  my $error       = $a[1];
  my $hash        = $defs{$name};
  delete $hash->{helper}{RUNNING_PID};
  my $file        = $hash->{helper}{configFile};
  delete $hash->{helper}{configFile};
  delete $hash->{helper}{startCmd};
  if ($error)
  {
    Log3 $name,3,"$name: Hyperion could not be restarted! Error: $error";
    readingsSingleUpdate($hash,"lastError",$error,1);
  }
  else
  {
    Log3 $name,3,"$name: Hyperion restarted with configFile $file";
    RemoveInternalTimer($hash);
    DevIo_Disconnected($hash);
    $file =~ s/\.config\.json$//;
    readingsSingleUpdate($hash,"configFile",$file,1);
    InternalTimer(gettimeofday() + 3,"Hyperion_OpenDev",$hash);
  }
  return undef;
}

sub Hyperion_Set($@)
{
  my ($hash,$name,@aa) = @_;
  my ($cmd,@args) = @aa;
  return if (IsDisabled($name) && $cmd ne "?");
  my $value = (defined($args[0])) ? $args[0] : undef;
  return "\"set $name\" needs at least one argument and maximum five arguments" if (@aa < 1 || @aa > 5);
  my $duration = (defined $args[1]) ? int $args[1] : int AttrVal($name,"hyperionDefaultDuration",0);
  my $priority = (defined $args[2]) ? int $args[2] : int AttrVal($name,"hyperionDefaultPriority",0);
  my %Hyperion_sets_local = %Hyperion_sets;
  if (ReadingsVal($name,".configs",""))
  {
    $Hyperion_sets_local{configFile} = ReadingsVal($name,".configs","");
    $Hyperion_sets_local{binary} = "restart,stop";
  }
  $Hyperion_sets_local{adjustRed} = "textField" if (ReadingsVal($name,"adjustRed",""));
  $Hyperion_sets_local{adjustGreen} = "textField" if (ReadingsVal($name,"adjustGreen",""));
  $Hyperion_sets_local{adjustBlue} = "textField" if (ReadingsVal($name,"adjustBlue",""));
  $Hyperion_sets_local{correction} = "textField" if (ReadingsVal($name,"correction",""));
  $Hyperion_sets_local{effect} = ReadingsVal($name,".effects","") if (ReadingsVal($name,".effects",""));
  $Hyperion_sets_local{colorTemperature} = "textField" if (ReadingsVal($name,"colorTemperature",""));
  $Hyperion_sets_local{blacklevel} = "textField" if (ReadingsVal($name,"blacklevel",""));
  $Hyperion_sets_local{gamma} = "textField" if (ReadingsVal($name,"gamma",""));
  $Hyperion_sets_local{threshold} = "textField" if (ReadingsVal($name,"threshold",""));
  $Hyperion_sets_local{whitelevel} = "textField" if (ReadingsVal($name,"whitelevel",""));
  $Hyperion_sets_local{luminanceGain} = "slider,0,0.01,5,1" if (ReadingsVal($name,"luminanceGain",""));
  $Hyperion_sets_local{luminanceMinimum} = "slider,0,0.01,5,1" if (ReadingsVal($name,"luminanceMinimum",""));
  $Hyperion_sets_local{saturationGain} = "slider,0,0.01,5,1" if (ReadingsVal($name,"saturationGain",""));
  $Hyperion_sets_local{saturationLGain} = "slider,0,0.01,5,1" if (ReadingsVal($name,"saturationLGain",""));
  $Hyperion_sets_local{valueGain} = "slider,0,0.01,5,1" if (ReadingsVal($name,"valueGain",""));
  my $params = join(" ",map {"$_:$Hyperion_sets_local{$_}"} keys %Hyperion_sets_local);
  my %obj;
  Log3 $name,4,"$name: Hyperion_Set cmd: $cmd";
  Log3 $name,4,"$name: Hyperion_Set value: $value" if ($value);
  Log3 $name,4,"$name: Hyperion_Set duration: $duration, priority: $priority" if ($cmd =~ /^rgb|dim|dimUp|dimDown|effect$/);
  if ($cmd =~ /^configFile|binary$/)
  {
    return "Work already/still in progress... Please wait for the current process to finish." if ($hash->{helper}{RUNNING_PID} && !$hash->{helper}{RUNNING_PID}{terminated});
    my $binpath  = AttrVal($name,"hyperionBin","/usr/bin/hyperiond");
    my $bin = (split "/",$binpath)[scalar(split "/",$binpath) - 1];
    $bin =~ s/\.sh$// if ($bin =~ /\.sh$/);
    my $confdir     = AttrVal($name,"hyperionConfigDir","/etc/hyperion/");
    my $user  = AttrVal($name,"hyperionSshUser","pi");
    my $ip = $hash->{IP};
    my $sudo = ($user eq "root" || int AttrVal($name,"hyperionNoSudo",0) == 1) ? "" : "sudo ";
    my $kill = $sudo."kill `pidof $bin`";
    my $ssh;
    if (!Hyperion_isLocal($ip))
    {
      $ssh = qx(which ssh);
      chomp $ssh;
      return "SSH client could NOT be found!" if (!$ssh);
    }
    my $com = Hyperion_isLocal($ip)?"":"$ssh $user\@$ip '";
    if ($cmd eq "binary")
    {
      return "Value of $cmd has to be 'stop' or 'restart'" if ($value !~ /^(stop|restart)$/);
    }
    else
    {
      return "Value of $cmd must be given and must be an available config file!" if (!$value || !grep(/^$value$/,split /,/,ReadingsVal($name,".configs","")));
    }
    if ($cmd eq "binary" && $value eq "stop")
    {
      $com .= $kill;
      $com .= Hyperion_isLocal($ip)?"":"'";
      Log3 $name,4,"$name: stopCmd: $com";
      $com = encode_base64($com);
      $hash->{helper}{RUNNING_PID} = BlockingCall("Hyperion_ExecCmd","$name|$com","Hyperion_Kill_finished");
    }
    elsif (($cmd eq "binary" && $value eq "restart") || $cmd eq "configFile")
    {
      my $file;
      if ($value eq "restart")
      {
        $file = ReadingsVal($name,"configFile","")?ReadingsVal($name,"configFile",""):ReadingsVal($name,".configs","")?(split /,/,ReadingsVal($name,".configs",""))[0]:"";
        return "No restart possible because no configFile is available." if (!$file);
      }
      else
      {
        $file = $value;
      }
      my $start = $com;
      $file .= ".config.json";
      $com .= $kill;
      $start .= "$sudo$binpath $confdir".$file." > /dev/null 2>&1 &";
      if (!Hyperion_isLocal($ip))
      {
        $com .= "'";
        $start .= "'";
      }
      Log3 $name,4,"$name: stopCmd: $com";
      Log3 $name,4,"$name: startCmd: $start";
      $com = encode_base64($com);
      $hash->{helper}{configFile} = $file;
      $hash->{helper}{startCmd} = encode_base64($start);
      $hash->{helper}{RUNNING_PID} = BlockingCall("Hyperion_ExecCmd","$name|$com","Hyperion_Restart");
    }
    return;
  }
  elsif ($cmd eq "rgb")
  {
    return "Value of $cmd has to be in RGB hex format like ffffff or 3F7D90"
      if ($value !~ /^[\dA-Fa-f]{6}$/);
    $value = lc $value;
    my ($r,$g,$b) = Color::hex2rgb($value);
    $obj{color} = [$r,$g,$b];
    $obj{command} = "color";
    $obj{priority} = $priority * 1;
    $obj{duration} = $duration * 1000 if ($duration > 0);
  }
  elsif ($cmd eq "dim")
  {
    return "Value of $cmd has to be between 1 and 100"
      if ($value !~ /^(\d+)$/ || $1 > 100 || $1 < 1);
    my $rgb = ReadingsVal($name,"rgb","ffffff");
    $value = $value + 1
      if ($cmd eq "dim" && $value < 100);
    $value = $value / 100;
    my ($r,$g,$b) = Color::hex2rgb($rgb);
    my ($h,$s,$v) = Color::rgb2hsv($r / 255,$g / 255,$b / 255);
    my ($rn,$gn,$bn);
    ($rn,$gn,$bn) = Color::hsv2rgb($h,$s,$value)
      if ($cmd eq "dim");
    $rn = int($rn * 255);
    $gn = int($gn * 255);
    $bn = int($bn * 255);
    $obj{color} = [$rn,$gn,$bn];
    $obj{command} = "color";
    $obj{priority} = $priority * 1;
    $obj{duration} = $duration * 1000
      if ($duration > 0);
  }
  elsif ($cmd =~ /^(dimUp|dimDown)$/)
  {
    return "Value of $cmd has to be between 1 and 99"
      if (defined $value && ($value !~ /^(\d+)$/ || $1 > 99 || $1 < 1));
    my $dim = ReadingsVal($name,"dim",100);
    my $dimStep = $value ? $value : AttrVal($name,"hyperionDimStep",10);
    my $dimUp = ($dim + $dimStep < 100) ? $dim + $dimStep : 100;
    my $dimDown = ($dim - $dimStep > 0) ? $dim - $dimStep : 1;
    my $set = $cmd eq "dimUp" ? $dimUp : $dimDown;
    CommandSet(undef,"$name dim $set");
    return;
  }
  elsif ($cmd eq "effect")
  {
    return "Effect $value is not available in the effect list of $name!"
      if ($value !~ /^([\w-]+)$/ || index(ReadingsVal($name,".effects",""),$value) == -1);
    my $arg = $args[3] ? eval{decode_json $args[3]} : "";
    my $ce  = $hash->{helper}{customeffects};
    if (!$arg && $ce)
    {
      foreach my $eff (@{$ce})
      {
        if ($eff->{name} eq $value)
        {
          $value = $eff->{oname};
          $arg = $eff->{args};
        }
      }
    }
    $value =~ s/_/ /g;
    my %ef = ("name" => $value);
    $ef{args} = $arg if ($arg);
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
    return "Value of $cmd has to be between 0 and 65536 in steps of 1"
      if (defined $value && $value !~ /^(\d+)$/ || $1 > 65536);
    $obj{command} = $cmd;
    $value = defined $1 ? $1 : AttrVal($name,"hyperionDefaultPriority",0);
    $obj{priority} = $value*1;
  }
  elsif ($cmd eq "off")
  {
    return "$cmd need no additional value of $value" if (defined $value);
    $obj{command} = "color";
    $obj{color} = [0,0,0];
    $obj{priority} = AttrVal($name,"hyperionDefaultPriority",0)*1;
  }
  elsif ($cmd eq "on")
  {
    return "$cmd need no additional value of $value" if (defined $value);
    my $rmode     = ReadingsVal($name,"mode_before_off","rgb");
    my $rrgb      = ReadingsVal($name,"rgb","");
    my $reffect   = ReadingsVal($name,"effect","");
    my ($r,$g,$b) = Color::hex2rgb($rrgb);
    my $set       = "$rmode $rrgb";
    $set          = "$rmode $reffect" if ($rmode eq "effect");
    $set          = $rmode if ($rmode eq "clearall");
    CommandSet(undef,"$name $set");
    return;
  }
  elsif ($cmd eq "toggle")
  {
    return "$cmd need no additional value of $value" if (defined $value);
    my $state = Value($name);
    my $nstate = $state ne "off" ? "off" : "on";
    CommandSet(undef,"$name $nstate");
    return;
  }
  elsif ($cmd eq "toggleMode")
  {
    return "$cmd need no additional value of $value" if (defined $value);
    my $mode = ReadingsVal($name,"mode","off");
    my $nmode;
    my @modeorder = split /,/,AttrVal($name,"hyperionToggleModes","clearall,rgb,effect,off");
    for (my $i = 0; $i < @modeorder; $i++)
    {
      $nmode = $i < @modeorder - 1 ? $modeorder[$i+1] : $modeorder[0] if ($modeorder[$i] eq $mode);
    }
    $nmode = $nmode ? $nmode : $modeorder[0];
    CommandSet(undef,"$name mode $nmode");
    return;
  }
  elsif ($cmd eq "mode")
  {
    return "The value of mode has to be rgb,effect,clearall,off" if ($value !~ /^(off|clearall|rgb|effect)$/);
    Log3 $name,4,"$name: cmd: $cmd, value: $value";
    my $rmode     = $value;
    my $rrgb      = ReadingsVal($name,"rgb","");
    my $reffect   = ReadingsVal($name,"effect","");
    my ($r,$g,$b) = Color::hex2rgb($rrgb);
    my $set       = "$rmode $rrgb";
    $set          = "$rmode $reffect" if ($rmode eq "effect");
    $set          = $rmode if ($rmode eq "clearall");
    $set          = $rmode if ($rmode eq "off");
    CommandSet(undef,"$name $set");
    return;
  }
  elsif ($cmd =~ /^(luminanceGain|luminanceMinimum|saturationGain|saturationLGain|valueGain)$/)
  {
    return "The value of $cmd has to be from 0.00 to 5.00 in steps of 0.01."
      if ($value !~ /^((\d)\.(\d){1,2})?$/ || $1 > 5);
    $value          = sprintf("%.4f",$value) * 1;
    my %tr          = ($cmd => $value);
    $obj{command}   = "transform";
    $obj{transform} = \%tr;
  }
  elsif ($cmd =~ /^(blacklevel|gamma|threshold|whitelevel)$/)
  {
    return "Each of the three comma separated values of $cmd must be from 0.00 to 1.00 in steps of 0.01"
      if ($cmd =~ /^blacklevel|threshold|whitelevel$/ && ($value !~ /^((\d)\.(\d){1,2}),((\d)\.(\d){1,2}),((\d)\.(\d){1,2})$/ || $1 > 1 || $4 > 1 || $7 > 1));
    return "Each of the three comma separated values of $cmd must be from 0.00 to 5.00 in steps of 0.01"
      if ($cmd eq "gamma" && ($value !~ /^((\d)\.(\d){1,2}),((\d)\.(\d){1,2}),((\d)\.(\d){1,2})$/ || $1 > 5 || $4 > 5 || $7 > 5));
    my $arr = Hyperion_list2array($value,"%.4f");
    my %ar = ($cmd => $arr);
    $obj{command} = "transform";
    $obj{transform} = \%ar;
  }
  elsif ($cmd =~ /^(correction|colorTemperature)$/)
  {
    $cmd = "temperature" if ($cmd eq "colorTemperature");
    return "Each of the three comma separated values of $cmd must be from 0 to 255 in steps of 1"
      if ($value !~ /^(\d{1,3})?,(\d{1,3})?,(\d{1,3})?$/ || $1 > 255 || $2 > 255 || $3 > 255);
    my $arr = Hyperion_list2array($value,"%d");
    my %ar = ("correctionValues" => $arr);
    $obj{command} = $cmd;
    $obj{$cmd} = \%ar;
  }
  elsif ($cmd =~ /^(adjustRed|adjustGreen|adjustBlue)$/)
  {
    return "Each of the three comma separated values of $cmd must be from 0 an 255 in steps of 1"
      if ($value !~ /^(\d{1,3})?,(\d{1,3})?,(\d{1,3})?$/ || $1 > 255 || $2 > 255 || $3 > 255);
    $cmd              = "redAdjust"   if ($cmd eq "adjustRed");
    $cmd              = "greenAdjust" if ($cmd eq "adjustGreen");
    $cmd              = "blueAdjust"  if ($cmd eq "adjustBlue");
    my $arr           = Hyperion_list2array($value,"%d");
    my %ar            = ($cmd => $arr);
    $obj{command}     = "adjustment";
    $obj{adjustment}  = \%ar;
  }
  elsif ($cmd =~ /^(valueGainUp|valueGainDown)$/)
  {
    return "Value of $cmd has to be between 0.1 and 1.0 in steps of 0.1"
      if (defined $value && ($value !~ /^(\d\.\d)$/ || $1 > 1 || $1 < 0.1));
    my $gain = ReadingsNum($name,"valueGain",1);
    my $gainStep = $value ? $value : AttrVal($name,"hyperionGainStep",0.1);
    my $gainUp = ($gain + $gainStep < 5) ? $gain + $gainStep : 5;
    my $gainDown = ($gain - $gainStep > 0) ? $gain - $gainStep : 0.1;
    my $set = $cmd eq "valueGainUp" ? $gainUp : $gainDown;
    CommandSet(undef,"$name valueGain $set");
    return;
  }
  elsif ($cmd eq "addEffect")
  {
    return "$name must be in effect mode!" if (ReadingsVal($name,"mode","off") ne "effect");
    return "Value of $cmd has to be a name like My_custom_EffeKt1 or my-effect!" if (!defined $value || $value !~ /^[a-zA-Z0-9_-]+$/);
    return "Effect with name $value already defined! Please choose a different name!" if (grep(/^$value$/,split /,/,ReadingsVal($name,".effects","")));
    my $eff  = ReadingsVal($name,"effect","");
    foreach my $e (@{$hash->{helper}{customeffects}})
    {
      return "The base effect can't be a custom effect! Please set a non-custom effect first!" if ($e->{name} eq $eff);
    }
    my $effs = AttrVal($name,"hyperionCustomEffects","");
    $effs .= "\r\n" if ($effs);
    $effs .= '{"name":"'.$value.'","oname":"'.$eff.'","args":'.ReadingsVal($name,"effectArgs","").'}';
    CommandAttr(undef,"$name hyperionCustomEffects $effs");
    return;
  }
  elsif ($cmd eq "reopen")
  {
    Hyperion_OpenDev($hash);
    return;
  }
  if (keys %obj)
  {
    Log3 $name,5,"$name: $cmd obj json: ".encode_json(\%obj);
    SetExtensionsCancel($hash);
    Hyperion_Call($hash,\%obj);
    return;
  }
  return SetExtensions($hash,$params,$name,@aa);
}

sub Hyperion_Attr(@)
{
  my ($cmd,$name,$attr_name,$attr_value) = @_;
  my $hash  = $defs{$name};
  my $err;
  my $local = Hyperion_isLocal($hash->{IP});
  if ($cmd eq "set")
  {
    if ($attr_name eq "hyperionBin")
    {
      if ($attr_value !~ /^(\/.+){2,}$/)
      {
        $err = "Invalid value $attr_value for attribute $attr_name. Must be a path like /usr/bin/hyperiond.";
      }
      elsif ($local && !-e $attr_value)
      {
        $err = "The given file $attr_value is not available.";
      }
    }
    elsif ($attr_name eq "hyperionCustomEffects")
    {
      if ($attr_value !~ /^\{"name":"[a-zA-Z0-9_-]+","oname":"[a-zA-Z0-9_-]+","args":\{[a-zA-Z0-9:_\[\]\.",-]+\}\}([\s(\r\n)]\{"name":"[a-zA-Z0-9_-]+","oname":"[a-zA-Z0-9_-]+","args":\{[a-zA-Z0-9:_\[\]\.",-]+\}\}){0,}$/)
      {
        $err = "Invalid value $attr_value for attribute $attr_name. Must be a space separated list of JSON strings.";
      }
      else
      {
        my @custeffs = split " ",$attr_value;
        my @effs;
        if (@custeffs > 1)
        {
          foreach my $eff (@custeffs)
          {
            push @effs,eval{decode_json $eff};
          }
        }
        else
        {
          push @effs,eval{decode_json $attr_value};
        }
        $hash->{helper}{customeffects} = \@effs;
        Hyperion_Call($hash);
      }
    }
    elsif ($attr_name eq "hyperionConfigDir")
    {
      if ($attr_value !~ /^\/(.+\/){2,}/)
      {
        $err = "Invalid value $attr_value for attribute $attr_name. Must be a path with trailing slash like /etc/hyperion/.";
      }
      elsif ($local && !-d $attr_value)
      {
        $err = "The given directory $attr_value is not available.";
      }
      else
      {
        Hyperion_GetConfigs($hash);
        Hyperion_Call($hash);
      }
    }
    elsif ($attr_name =~ /^hyperionDefault(Priority|Duration)$/)
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
    elsif ($attr_name eq "hyperionToggleModes")
    {
      $err = "Invalid value $attr_value for attribute $attr_name. Must be a comma separated list of available modes of clearall,rgb,effect,off. Each mode only once in the list." if ($attr_value !~ /^(clearall|rgb|effect|off),(clearall|rgb|effect|off)(,(clearall|rgb|effect|off)){0,2}$/);
    }
    elsif ($attr_name eq "hyperionVersionCheck")
    {
      $err = "Invalid value $attr_value for attribute $attr_name. Can only be value 0." if ($attr_value !~ /^0$/);
    }
    elsif ($attr_name eq "queryAfterSet")
    {
      $err = "Invalid value $attr_value for attribute $attr_name. Must be 0 if set, default is 1." if ($attr_value !~ /^0$/);
    }
    elsif ($attr_name eq "disable")
    {
      $err = "Invalid value $attr_value for attribute $attr_name. Must be 1 if set, default is 0." if ($attr_value !~ /^0|1$/);
      return $err if ($err);
      if ($attr_value == 1)
      {
        RemoveInternalTimer($hash);
        DevIo_Disconnected($hash);
      }
      else
      {
        Hyperion_OpenDev($hash);
      }
    }
  }
  else
  {
    delete $hash->{helper}{customeffects} if ($attr_name eq "hyperionCustomEffects");
    Hyperion_GetUpdate($hash) if (!IsDisabled($name));
    Hyperion_OpenDev($hash) if ($attr_name eq "disable");
  }
  return $err if ($err);
  return;
}

sub Hyperion_Call($;$)
{
  my ($hash,$obj) = @_;
  $obj = $obj ? $obj : $Hyperion_serverinfo;
  my $name = $hash->{NAME};
  my $json = encode_json($obj);
  return if (IsDisabled($name));
  Log3 $name,5,"$name: Hyperion_Call: json object: $json";
  DevIo_SimpleWrite($hash,$json,2,1);
}

sub Hyperion_devStateIcon($;$)
{
  my ($hash,$state) = @_; 
  $hash = $defs{$hash} if (ref $hash ne "HASH");
  return if (!$hash);
  my $name = $hash->{NAME};
  my $rgb = ReadingsVal($name,"rgb","");
  my $dim = ReadingsVal($name,"dim",10);
  my $val = ReadingsVal($name,"state","off");
  my $mode = ReadingsVal($name,"mode","");
  my $ico = int($dim / 10) * 10 < 10 ? 10 : int($dim / 10) * 10;
  return ".*:off:on"
    if ($val =~ /^off|rgb\s000000$/);
  return ".*:light_exclamation"
    if (($val =~ /^(ERROR|disconnected)$/ && !$hash->{INTERVAL}) || ($val eq "ERROR" && $hash->{INTERVAL}));
  return ".*:light_light_dim_$ico@#".$rgb.":off"
    if ($val ne "off" && $mode eq "rgb");
  return ".*:light_led_stripe_rgb@#FFFF00:off"
    if ($val ne "off" && $mode eq "effect");
  return ".*:it_television@#0000FF:off"
    if ($val ne "off" && $mode eq "clearall");
  return ".*:light_question";
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
  You can also restart Hyperion with different configuration files (p.e. switch input/grabber)<br>
  <br>
  <a name="Hyperion_define"></a>
  <p><b>Define</b></p>
  <ul>
    <code>define &lt;name&gt; Hyperion &lt;IP or HOSTNAME&gt; &lt;PORT&gt; [&lt;INTERVAL&gt;]</code><br>
  </ul>
  <br>
  &lt;INTERVAL&gt; is optional for periodically polling.<br>
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
  <br><br>
  To change config files on your running Hyperion server or to stop/restart your Hyperion server you have to put the following code into your sudoers file (/etc/sudoers) (visudo):
  <br><br>
  <ul>
    <code>fhem    ALL=(ALL) NOPASSWD:/usr/bin/hyperiond,/bin/kill</code>
  </ul>
  <br>
  <a name="Hyperion_set"></a>
  <p><b>set &lt;required&gt; [optional]</b></p>
  <ul>
    <li>
      <i>addEffect &lt;custom_name&gt;</i><br>
      add the current effect with the given name to the custom effects<br>
      can be altered after adding in attribute hyperionCustomEffects<br>
      device has to be in effect mode with a non-custom effect and given name must be a unique effect name
    </li>
    <li>
      <i>adjustBlue &lt;0,0,255&gt;</i><br>
      adjust each color of blue separately (comma separated) (R,G,B)<br>
      values from 0 to 255 in steps of 1
    </li>
    <li>
      <i>adjustGreen &lt;0,255,0&gt;</i><br>
      adjust each color of green separately (comma separated) (R,G,B)<br>
      values from 0 to 255 in steps of 1
    </li>
    <li>
      <i>adjustRed &lt;255,0,0&gt;</i><br>
      adjust each color of red separately (comma separated) (R,G,B)<br>
      values from 0 to 255 in steps of 1
    </li>
    <li>
      <i>binary &lt;restart/stop&gt;</i><br>
      restart or stop the hyperion binary<br>
      only available after successful "get &lt;name&gt; configFiles"
    </li>
    <li>
      <i>blacklevel &lt;0.00,0.00,0.00&gt;</i><br>
      adjust blacklevel of each color separately (comma separated) (R,G,B)<br>
      values from 0.00 to 1.00 in steps of 0.01
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
      adjust temperature of each color separately (comma separated) (R,G,B)<br>
      values from 0 to 255 in steps of 1
    </li>
    <li>
      <i>configFile &lt;filename&gt;</i><br>
      restart the Hyperion server with the given configuration file (files will be listed automatically from the given directory in attribute hyperionConfigDir)<br>
      please omit the double extension of the file name (.config.json)<br>
      only available after successful "get &lt;name&gt; configFiles"
    </li>
    <li>
      <i>correction &lt;255,255,255&gt;</i><br>
      adjust correction of each color separately (comma separated) (R,G,B)<br>
      values from 0 to 255 in steps of 1
    </li>
    <li>
      <i>dim &lt;percent&gt; [duration] [priority]</i><br>
      dim the rgb light to given percentage with optional duration in seconds and optional priority
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
      <i>effect &lt;effect&gt; [duration] [priority] [effectargs]</i><br>
      set effect (replace blanks with underscore) with optional duration in seconds and priority<br>
      effectargs can also be set as very last argument - must be a JSON string without any whitespace
    </li>
    <li>
      <i>gamma &lt;1.90,1.90,1.90&gt;</i><br>
      adjust gamma of each color separately (comma separated) (R,G,B)<br>
      values from 0.00 to 5.00 in steps of 0.01
    </li>
    <li>
      <i>luminanceGain &lt;1.00&gt;</i><br>
      adjust luminanceGain<br>
      values from 0.00 to 5.00 in steps of 0.01
    </li>
    <li>
      <i>luminanceMinimum &lt;0.00&gt;</i><br>
      adjust luminanceMinimum<br>
      values from 0.00 to 5.00 in steps of 0.01
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
      <i>reopen</i><br>
      reopen the connection to the hyperion server
    </li>
    <li>
      <i>rgb &lt;RRGGBB&gt; [duration] [priority]</i><br>
      set color in RGB hex format with optional duration in seconds and priority
    </li>
    <li>
      <i>saturationGain &lt;1.10&gt;</i><br>
      adjust saturationGain<br>
      values from 0.00 to 5.00 in steps of 0.01
    </li>
    <li>
      <i>saturationLGain &lt;1.00&gt;</i><br>
      adjust saturationLGain<br>
      values from 0.00 to 5.00 in steps of 0.01
    </li>
    <li>
      <i>threshold &lt;0.16,0.16,0.16&gt;</i><br>
      adjust threshold of each color separately (comma separated) (R,G,B)<br>
      values from 0.00 to 1.00 in steps of 0.01
    </li>
    <li>
      <i>toggle</i><br>
      toggles the light between on and off
    </li>
    <li>
      <i>toggleMode</i><br>
      toggles through all modes
    </li>
    <li>
      <i>valueGain &lt;1.70&gt;</i><br>
      adjust valueGain<br>
      values from 0.00 to 5.00 in steps of 0.01
    </li>
    <li>
      <i>whitelevel &lt;0.70,0.80,0.90&gt;</i><br>
      adjust whitelevel of each color separately (comma separated) (R,G,B)<br>
      values from 0.00 to 1.00 in steps of 0.01
    </li>
  </ul>  
  <br>
  <a name="Hyperion_get"></a>
  <p><b>Get</b></p>
  <ul>
    <li>
      <i>configFiles</i><br>
      get the available config files in directory from attribute hyperionConfigDir<br>
      File names must have no spaces and must end with .config.json .<br>
      For non-local Hyperion servers you have to configure passwordless SSH login for the user running fhem to the Hyperion server host (http://www.linuxproblem.org/art_9.html), with attribute hyperionSshUser you can set the SSH user for login.<br>
      Please watch the log for possible errors while getting config files.
    </li>
    <li>
      <i>devStateIcon</i><br>
      get the current devStateIcon
    </li>
    <li>
      <i>statusRequest</i><br>
      get the state of the Hyperion server,<br>
      get also the internals of Hyperion including available effects
    </li>
  </ul>
  <br>
  <a name="Hyperion_attr"></a>
  <p><b>Attributes</b></p>
  <ul>
    <li>
      <i>disable</i><br>
      stop polling and disconnect<br>
      default: 0
    </li>
    <li>
      <i>disabledForIntervals</i><br>
      stop polling in given time frames<br>
      default:
    </li>
    <li>
      <i>hyperionBin</i><br>
      path to the hyperion daemon<br>
      OpenELEC users may set hyperiond.sh as daemon<br>
      default: /usr/bin/hyperiond
    </li>
    <li>
      <i>hyperionConfigDir</i><br>
      path to the hyperion configuration files<br>
      default: /etc/hyperion/
    </li>
    <li>
      <i>hyperionCustomEffects</i><br>
      space separated list of JSON strings (without spaces - please replace spaces in effect names with underlines)<br>
      must include name (as diplay name), oname (name of the base effect) and args (the different effect args), only this order is allowed (if different an error will be thrown on attribute save and the attribut value will not be saved).<br>
      example: {"name":"Knight_Rider_speed_2","oname":"Knight_rider","args":{"color":[255,0,255],"speed":2}} {"name":"Knight_Rider_speed_4","oname":"Knight_rider","args":{"color":[0,0,255],"speed":4}}
    </li>
    <li>
      <i>hyperionDefaultDuration</i><br>
      default duration<br>
      default: 0 = infinity
    </li>
    <li>
      <i>hyperionDefaultPriority</i><br>
      default priority<br>
      default: 0 = highest priority
    </li>
    <li>
      <i>hyperionDimStep</i><br>
      dim step for dimDown/dimUp<br>
      default: 10 (percent)
    </li>
    <li>
      <i>hyperionGainStep</i><br>
      valueGain step for valueGainDown/valueGainUp<br>
      default: 0.1
    </li>
    <li>
      <i>hyperionNoSudo</i><br>
      disable sudo for non-root ssh user<br>
      default: 0
    </li>
    <li>
      <i>hyperionSshUser</i><br>
      user name for executing SSH commands<br>
      default: pi
    </li>
    <li>
      <i>hyperionToggleModes</i><br>
      modes and order of toggleMode as comma separated list (min. 2 modes, max. 4 modes, each mode only once)<br>
      default: clearall,rgb,effect,off
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
      This is only used if periodically polling is enabled, without this polling the state will be queried automatically after set.<br>
      default: 1
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
      active/previous/remaining primary duration in seconds or infinite
    </li>
    <li>
      <i>effect</i><br>
      active/previous effect
    </li>
    <li>
      <i>effectArgs</i><br>
      active/previous effect arguments as JSON
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
      current luminanceGain
    </li>
    <li>
      <i>luminanceMinimum</i><br>
      current luminanceMinimum
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
      active saturationGain
    </li>
    <li>
      <i>saturationLGain</i><br>
      active saturationLGain
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
=begin html_DE

<a name="Hyperion"></a>
<h3>Hyperion</h3>
<ul>
  Mit <i>Hyperion</i> ist es m&ouml;glich auf einem Hyperion Server die Farbe oder den Effekt einzustellen.<br>
  Es ist auch m&ouml;glich eine komplette Farbkalibrierung vorzunehmen (&Auml;nderungen sind tempor&auml;r und werden nicht in die Konfigurationsdatei geschrieben).<br>
  Der Hyperion Server muss dem JSON Server aktiviert haben.<br>
  Es ist auch m&ouml;glich Hyperion mit verschiedenen Konfigurationsdateien zu starten (z.B. mit anderem Eingang/Grabber)<br>
  <br>
  <a name="Hyperion_define"></a>
  <p><b>Define</b></p>
  <ul>
    <code>define &lt;name&gt; Hyperion &lt;IP oder HOSTNAME&gt; &lt;PORT&gt; [&lt;INTERVAL&gt;]</code><br>
  </ul>
  <br>
  &lt;INTERVAL&gt; ist optional f&uuml;r automatisches Abfragen.<br>
  <br>
  <i>Nach dem Definieren des Ger&auml;tes wird einmalig und automatisch "get &lt;name&gt; statusRequest" aufgerufen um den aktuellen Status und die verf&uuml;gbaren Effekte vom Hyperion Server zu holen.</i><br>
  <br>
  Beispiel f&uuml;r Hyperion auf dem lokalen System:
  <br><br>
  <ul>
    <code>define Ambilight Hyperion localhost 19444 10</code><br>
  </ul>
  <br>
  Beispiel f&uuml;r Hyperion auf einem entfernten System:
  <br><br>
  <ul>
    <code>define Ambilight Hyperion 192.168.1.4 19444 10</code><br>
  </ul>
  <br>
  <a name="Hyperion_set"></a>
  <p><b>set &lt;ben&ouml;tigt&gt; [optional]</b></p>
  <ul>
    <li>
      <i>addEffect &lt;eigener_name&gt;</i><br>
      f&uuml;gt den aktuellen Effekt mit dem &uuml;bergebenen Namen den eigenen Effekten hinzu<br>
      kann nachtr&auml;glich im Attribut hyperionCustomEffects ge&auml;ndert werden<br>
      Ger&auml;t muss dazu im Effekt Modus in einen nicht-eigenen Effekt sein und der &uuml;bergebene Name muss ein einmaliger Effektname sein
    </li>
    <li>
      <i>adjustBlue &lt;0,0,255&gt;</i><br>
      Justiert jede Farbe von Blau separat (Komma separiert) (R,G,B)<br>
      Werte von 0 bis 255 in Schritten von 1
    </li>
    <li>
      <i>adjustGreen &lt;0,255,0&gt;</i><br>
      Justiere jede Farbe von Gr&uuml;n separat (Komma separiert) (R,G,B)<br>
      Werte von 0 bis 255 in Schritten von 1
    </li>
    <li>
      <i>adjustRed &lt;255,0,0&gt;</i><br>
      Justiert jede Farbe von Rot separat (Komma separiert) (R,G,B)<br>
      Werte von 0 bis 255 in Schritten von 1
    </li>
    <li>
      <i>blacklevel &lt;0.00,0.00,0.00&gt;</i><br>
      Justiert den Schwarzwert von jeder Farbe separat (Komma separiert) (R,G,B)<br>
      Werte von 0.00 bis 1.00 in Schritten von 0.01
    </li>
    <li>
      <i>clear &lt;1000&gt;</i><br>
      einen bestimmten Priorit&auml;tskanal l&ouml;schen
    </li>
    <li>
      <i>clearall</i><br>
      alle Priorit&auml;tskan&auml;le l&ouml;schen / Umschaltung auf Ambilight
    </li>
    <li>
      <i>colorTemperature &lt;255,255,255&gt;</i><br>
      Justiert die Temperatur von jeder Farbe separat (Komma separiert) (R,G,B)<br>
      Werte von 0 bis 255 in Schritten von 1
    </li>
    <li>
      <i>configFile &lt;Dateiname&gt;</i><br>
      Neustart des Hyperion Servers mit der angegebenen Konfigurationsdatei (Dateien werden automatisch aufgelistet aus Verzeichnis welches im Attribut hyperionConfigDir angegeben ist)<br>
      Bitte die doppelte Endung weglassen (.config.json)<br>
      Nur verf&uuml;gbar nach erfolgreichem "get &lt;name&gt; configFiles"
    </li>
    <li>
      <i>correction &lt;255,255,255&gt;</i><br>
      Justiert die Korrektur von jeder Farbe separat (Komma separiert) (R,G,B)<br>
      Werte von 0 bis 255 in Schritten von 1
    </li>
    <li>
      <i>dim &lt;Prozent&gt; [Dauer] [Priorit&auml;t]</i><br>
      Dimmt das RGB Licht auf angegebenen Prozentwert, mit optionaler Dauer in Sekunden und optionaler Priorit&auml;t
    </li>
    <li>
      <i>dimDown [delta]</i><br>
      Abdunkeln des RGB Lichts um angegebenen Prozentwert oder um Prozentwert der im Attribut hyperionDimStep eingestellt ist (Voreinstellung: 10)
    </li>
    <li>
      <i>dimUp [delta]</i><br>
      Aufhellen des RGB Lichts um angegebenen Prozentwert oder um Prozentwert der im Attribut hyperionDimStep eingestellt ist (Voreinstellung: 10)
    </li>
    <li>
      <i>effect &lt;effect&gt; [Dauer] [Priorit&auml;t] [effectargs]</i><br>
      Stellt gew&auml;hlten Effekt ein (ersetzte Leerzeichen mit Unterstrichen) mit optionaler Dauer in Sekunden und optionaler Priorit&auml;t<br>
      effectargs k&ouml;nnen ebenfalls &uuml;bermittelt werden - muss ein JSON String ohne Leerzeichen sein
    </li>
    <li>
      <i>gamma &lt;1.90,1.90,1.90&gt;</i><br>
      Justiert Gamma von jeder Farbe separat (Komma separiert) (R,G,B)<br>
      Werte von 0.00 bis 5.00 in Schritten von 0.01
    </li>
    <li>
      <i>luminanceGain &lt;1.00&gt;</i><br>
      Justiert Helligkeit<br>
      Werte von 0.00 bis 5.00 in Schritten von 0.01
    </li>
    <li>
      <i>luminanceMinimum &lt;0.00&gt;</i><br>
      Justiert Hintergrundbeleuchtung<br>
      Werte von 0.00 bis 5.00 in Schritten von 0.01
    </li>
    <li>
      <i>mode &lt;clearall|effect|off|rgb&gt;</i><br>
      Setzt das Licht im gew&auml;hlten Modus mit dem zuletzt f&uuml;r diesen Modus eingestellten Wert
    </li>
    <li>
      <i>off</i><br>
      Schaltet aus mit Farbe schwarz
    </li>
    <li>
      <i>on</i><br>
      Schaltet mit letztem Modus und letztem Wert ein
    </li>
    <li>
      <i>rgb &lt;RRGGBB&gt; [Dauer] [Priorit&auml;t]</i><br>
      Setzt Farbe im RGB Hex Format mit optionaler Dauer in Sekunden und optionaler Priorit&auml;t
    </li>
    <li>
      <i>saturationGain &lt;1.10&gt;</i><br>
      Justiert S&auml;ttigung<br>
      Werte von 0.00 bis 5.00 in Schritten von 0.01
    </li>
    <li>
      <i>saturationLGain &lt;1.00&gt;</i><br>
      Justiert minimale S&auml;ttigung<br>
      Werte von 0.00 bis 5.00 in Schritten von 0.01
    </li>
    <li>
      <i>threshold &lt;0.16,0.16,0.16&gt;</i><br>
      Justiert den Schwellenwert von jeder Farbe separat (Komma separiert) (R,G,B)<br>
      Werte von 0.00 bis 1.00 in Schritten von 0.01
    </li>
    <li>
      <i>toggle</i><br>
      Schaltet zwischen an und aus hin und her
    </li>
    <li>
      <i>toggleMode</i><br>
      Schaltet alle Modi durch
    </li>
    <li>
      <i>valueGain &lt;1.70&gt;</i><br>
      Justiert Helligkeit vom Ambilight<br>
      Werte von 0.00 bis 5.00 in Schritten von 0.01
    </li>
    <li>
      <i>whitelevel &lt;0.70,0.80,0.90&gt;</i><br>
      Justiert den Wei&szlig;wert von jeder Farbe separat (Komma separiert) (R,G,B)<br>
      Werte von 0.00 bis 1.00 in Schritten von 0.01
    </li>
  </ul>  
  <br>
  <a name="Hyperion_get"></a>
  <p><b>Get</b></p>
  <ul>
    <li>
      <i>configFiles</i><br>
      Holt die verf&uuml;gbaren Konfigurationsdateien aus dem Verzeichnis vom Attribut hyperionConfigDir<br>
      Es m&uuml;ssen mindestens zwei Konfigurationsdateien im Verzeichnis vorhanden sein. Die Dateien d&uuml;rfen keine Leerzeichen enthalten und m&uuml;ssen mit .config.json enden!
    </li>
    <li>
      <i>devStateIcon</i><br>
      Zeigt den Wert des aktuellen devStateIcon
    </li>
    <li>
      <i>statusRequest</i><br>
      Holt den aktuellen Status vom Hyperion Server,<br>
      holt auch die Internals vom Hyperion Server inklusive verf&uuml;gbarer Effekte
    </li>
  </ul>
  <br>
  <a name="Hyperion_attr"></a>
  <p><b>Attribute</b></p>
  <ul>
    <li>
      <i>disable</i><br>
      Abfragen beenden und Verbindung trennen<br>
      Voreinstellung: 0
    </li>
    <li>
      <i>hyperionBin</i><br>
      Pfad zum Hyperion Daemon<br>
      OpenELEC Benutzer m&uuml;ssen eventuell hyperiond.sh als Daemon einstellen<br>
      Voreinstellung: /usr/bin/hyperiond
    </li>
    <li>
      <i>hyperionConfigDir</i><br>
      Pfad zu den Hyperion Konfigurationsdateien<br>
      Voreinstellung: /etc/hyperion/
    </li>
    <li>
      <i>hyperionCustomEffects</i><br>
      Leerzeichen separierte Liste von JSON Strings (ohne Leerzeichen - bitte Leerzeichen in Effektnamen durch Unterstriche ersetzen)<br>
      muss name (als Anzeigename), oname (Name des basierenden Effekts) und args (die eigentlichen unterschiedlichen Effekt Argumente) beinhalten (auch genau in dieser Reihenfolge, sonst kommt beim &Uuml;bernehmen des Attributs ein Fehler und das Attribut wird nicht gespeichert)<br>
      Beispiel: {"name":"Knight_Rider_speed_2","oname":"Knight_rider","args":{"color":[255,0,255],"speed":2}} {"name":"Knight_Rider_speed_4","oname":"Knight_rider","args":{"color":[0,0,255],"speed":4}}
    </li>
    <li>
      <i>hyperionDefaultDuration</i><br>
      Voreinstellung f&uuml;r Dauer<br>
      Voreinstellung: 0 = unendlich
    </li>
    <li>
      <i>hyperionDefaultPriority</i><br>
      Voreinstellung f&uuml;r Priorit&auml;t<br>
      Voreinstellung: 0 = h&ouml;chste Priorit&auml;t
    </li>
    <li>
      <i>hyperionDimStep</i><br>
      Dimmstufen f&uuml;r dimDown/dimUp<br>
      Voreinstellung: 10 (Prozent)
    </li>
    <li>
      <i>hyperionGainStep</i><br>
      valueGain Dimmstufen f&uuml;r valueGainDown/valueGainUp<br>
      Voreinstellung: 0.1
    </li>
    <li>
      <i>hyperionNoSudo</i><br>
      Deaktiviert sudo f&uuml;r nicht root SSH Benutzer<br>
      Voreinstellung: 0
    </li>
    <li>
      <i>hyperionSshUser</i><br>
      Benutzername mit dem SSH Befehle ausgef&uuml;hrt werden sollen<br>
      Voreinstellung: pi
    </li>
    <li>
      <i>hyperionToggleModes</i><br>
      Modi und Reihenfolge von toggleMode als kommaseparierte Liste (min. 2 Werte, max. 4 Werte, jeder Mode nur 1x)<br>
      Voreinstellung: clearall,rgb,effect,off
    </li>
    <li>
      <i>hyperionVersionCheck</i><br>
      Deaktiviert Hyperion Version&uuml;berpr&uuml;fung um (eventuell) &auml;ltere Hyperion Versionen zu unterst&uuml;tzen<br>
      DAS GESCHIEHT AUF EIGENE VERANTWORTUNG! FHEM K&Ouml;NNTE UNERWARTET ABST&Uuml;RTZEN!<br>
      Voreinstellung: 1
    </li>
    <li>
      <i>queryAfterSet</i><br>
      Wenn gesetzt auf 0 wird der Status des Hyperion Server nach einem set Befehl nicht abgerufen, stattdessen wird der Status zum n&auml;chsten eingestellten Interval abgerufen.<br>
      Das wird nur verwendet wenn das priodische Abfragen aktiviert ist, ohne dieses Abfragen wird der Status automatisch nach dem set Befehl abgerufen.<br>
      Voreinstellung: 1
    </li>
  </ul>
  <br>
  <a name="Hyperion_read"></a>
  <p><b>Readings</b></p>
  <ul>
    <li>
      <i>adjustBlue</i><br>
      jede Farbe von Blau separat (Komma separiert) (R,G,B)
    </li>
    <li>
      <i>adjustGreen</i><br>
      jede Farbe von Gr&uuml;n separat (Komma separiert) (R,G,B)
    </li>
    <li>
      <i>adjustRed</i><br>
      jede Farbe von Rot separat (Komma separiert) (R,G,B)
    </li>
    <li>
      <i>blacklevel</i><br>
      Schwarzwert von jeder Farbe separat (Komma separiert) (R,G,B)
    </li>
    <li>
      <i>colorTemperature</i><br>
      Temperatur von jeder Farbe separat (Komma separiert) (R,G,B)
    </li>
    <li>
      <i>configFile</i><br>
      aktive/zuletzt geladene Konfigurationsdatei, doppelte Endung (.config.json) wird weggelassen
    </li>
    <li>
      <i>correction</i><br>
      Korrektur von jeder Farbe separat (Komma separiert) (R,G,B)
    </li>
    <li>
      <i>dim</i><br>
      aktive/letzte Dimmstufe (RGB Licht)
    </li>
    <li>
      <i>duration</i><br>
      aktive/letzte/verbleibende prim&auml;re Dauer in Sekunden oder infinite f&uuml;r unendlich
    </li>
    <li>
      <i>effect</i><br>
      aktiver/letzter Effekt
    </li>
    <li>
      <i>effectArgs</i><br>
      aktive/letzte Effekt Argumente als JSON
    </li>
    <li>
      <i>gamma</i><br>
      Gamma von jeder Farbe separat (Komma separiert) (R,G,B)
    </li>
    <li>
      <i>id</i><br>
      ID vom Hyperion Server
    </li>
    <li>
      <i>lastError</i><br>
      letzter aufgetretener Fehler w&auml;hrend der Kommunikation mit dem Hyperion Server
    </li>
    <li>
      <i>luminanceGain</i><br>
      aktive Helligkeit
    </li>
    <li>
      <i>luminanceMinimum</i><br>
      aktive Hintergrundbeleuchtung
    </li>
    <li>
      <i>mode</i><br>
      aktiver Modus
    </li>
    <li>
      <i>mode_before_off</i><br>
      letzter Modus vor aus
    </li>
    <li>
      <i>priority</i><br>
      aktive/letzte Priorit&auml;t
    </li>
    <li>
      <i>rgb</i><br>
      aktive/letzte RGB Farbe
    </li>
    <li>
      <i>saturationGain</i><br>
      aktive S&auml;ttigung
    </li>
    <li>
      <i>saturationLGain</i><br>
      aktive minimale S&auml;ttigung
    </li>
    <li>
      <i>serverResponse</i><br>
      letzte Hyperion Server Antwort (success/ERROR)
    </li>
    <li>
      <i>state</i><br>
      aktiver Status
    </li>
    <li>
      <i>threshold</i><br>
      Schwellenwert von jeder Farbe separat (Komma separiert) (R,G,B)
    </li>
    <li>
      <i>valueGain</i><br>
      aktive Helligkeit vom Ambilight
    </li>
    <li>
      <i>whitelevel</i><br>
      Wei&szlig;wert von jeder Farbe separat (Komma separiert) (R,G,B)
    </li>
  </ul>
</ul>

=end html_DE
=cut
