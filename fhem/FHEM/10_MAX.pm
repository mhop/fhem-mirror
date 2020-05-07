# $Id$
# 
#  (c) 2019 Copyright: Wzut
#  (c) 2012 Copyright: Matthias Gehre, M.Gehre@gmx.de
#
#  All rights reserved
#
#  FHEM Forum : https://forum.fhem.de/index.php/board,23.0.html
#
#  This code is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
# 2.0.0  =>  28.03.2020
# 1.0.0"  => (c) M.Gehre
################################################################

package main;

use strict;
use warnings;
use AttrTemplate;
use Date::Parse;

my %device_types = (

  1 => "HeatingThermostat",
  2 => "HeatingThermostatPlus",
  3 => "WallMountedThermostat",
  4 => "ShutterContact",
  5 => "PushButton",
  6 => "virtualShutterContact",
  7 => "virtualThermostat",
  8 => "PlugAdapter"

);

my %msgId2Cmd = (
                 "00" => "PairPing",
                 "01" => "PairPong",
                 "02" => "Ack",
                 "03" => "TimeInformation",

                 "10" => "ConfigWeekProfile",
                 "11" => "ConfigTemperatures", #like eco/comfort etc
                 "12" => "ConfigValve",

                 "20" => "AddLinkPartner",
                 "21" => "RemoveLinkPartner",
                 "22" => "SetGroupId",
                 "23" => "RemoveGroupId",

                 "30" => "ShutterContactState",

                 "40" => "SetTemperature", # to thermostat
                 "42" => "WallThermostatControl", # by WallMountedThermostat
                 # Sending this without payload to thermostat sets desiredTempeerature to the comfort/eco temperature
                 # We don't use it, we just do SetTemperature
                 "43" => "SetComfortTemperature",
                 "44" => "SetEcoTemperature",

                 "50" => "PushButtonState",

                 "60" => "ThermostatState", # by HeatingThermostat

                 "70" => "WallThermostatState",

                 "82" => "SetDisplayActualTemperature",

                 "F1" => "WakeUp",
                 "F0" => "Reset",
               );

my %msgCmd2Id = reverse %msgId2Cmd;

my $defaultWeekProfile = "444855084520452045204520452045204520452045204520452044485508452045204520452045204520452045204520452045204448546c44cc55144520452045204520452045204520452045204448546c44cc55144520452045204520452045204520452045204448546c44cc55144520452045204520452045204520452045204448546c44cc55144520452045204520452045204520452045204448546c44cc5514452045204520452045204520452045204520";

my @ctrl_modes = ( "auto", "manual", "temporary", "boost" );

my %boost_durations = (0 => 0, 1 => 5, 2 => 10, 3 => 15, 4 => 20, 5 => 25, 6 => 30, 7 => 60);

my %boost_durationsInv = reverse %boost_durations;

my %decalcDays    = (0 => "Sat", 1 => "Sun", 2 => "Mon", 3 => "Tue", 4 => "Wed", 5 => "Thu", 6 => "Fri");

my @weekDays      = ("Sat", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri");

my %decalcDaysInv = reverse %decalcDays;

my %readingDef = ( #min/max/default
  "maximumTemperature"    => [ \&MAX_validTemperature, "on"],
  "minimumTemperature"    => [ \&MAX_validTemperature, "off"],
  "comfortTemperature"    => [ \&MAX_validTemperature, 21],
  "ecoTemperature"        => [ \&MAX_validTemperature, 17],
  "windowOpenTemperature" => [ \&MAX_validTemperature, 12],
  "windowOpenDuration"    => [ \&MAX_validWindowOpenDuration,   15],
  "measurementOffset"     => [ \&MAX_validMeasurementOffset, 0],
  "boostDuration"         => [ \&MAX_validBoostDuration, 5 ],
  "boostValveposition"    => [ \&MAX_validValveposition, 80 ],
  "decalcification"       => [ \&MAX_validDecalcification, "Sat 12:00" ],
  "maxValveSetting"       => [ \&MAX_validValveposition, 100 ],
  "valveOffset"           => [ \&MAX_validValveposition, 00 ],
  "groupid"               => [ \&MAX_validGroupid, 0 ],
  ".weekProfile"          => [ \&MAX_validWeekProfile, $defaultWeekProfile ]
 );

#my %interfaces = (
#  "Cube" => undef,
#  "HeatingThermostat" => "thermostat;battery;temperature",
#  "HeatingThermostatPlus" => "thermostat;battery;temperature",
#  "WallMountedThermostat" => "thermostat;temperature;battery",
#  "ShutterContact" => "switch_active;battery",
#  "PushButton" => "switch_passive;battery"
#  );


sub MAX_validTemperature { return $_[0] eq "on" || $_[0] eq "off" || ($_[0] =~ /^\d+(\.[05])?$/ && $_[0] >= 4.5 && $_[0] <= 30.5); }

# Identify for numeric values and maps "on" and "off" to their temperatures
sub MAX_ParseTemperature        { return $_[0] eq "on" ? 30.5 : ($_[0] eq "off" ? 4.5 :$_[0]); }
sub MAX_validWindowOpenDuration { return $_[0] =~ /^\d+$/ && $_[0] >= 0 && $_[0] <= 60; }
sub MAX_validMeasurementOffset  { return $_[0] =~ /^-?\d+(\.[05])?$/ && $_[0] >= -3.5 && $_[0] <= 3.5; }
sub MAX_validBoostDuration      { return $_[0] =~ /^\d+$/ && exists($boost_durationsInv{$_[0]}); }
sub MAX_validValveposition      { return $_[0] =~ /^\d+$/ && $_[0] >= 0 && $_[0] <= 100; }
sub MAX_validWeekProfile        { return length($_[0]) == 4*13*7; }
sub MAX_validGroupid            { return $_[0] =~ /^\d+$/ && $_[0] >= 0 && $_[0] <= 255; }

sub MAX_validDecalcification
{ 
  my ($decalcDay, $decalcHour) = ($_[0] =~ /^(...) (\d{1,2}):00$/);
  return defined($decalcDay) && defined($decalcHour) && exists($decalcDaysInv{$decalcDay}) && 0 <= $decalcHour && $decalcHour < 24; 
}

sub MAX_Initialize
{
  my ($hash) = shift;

  $hash->{Match}         = "^MAX";
  $hash->{DefFn}         = "MAX_Define";
  $hash->{UndefFn}       = "MAX_Undef";
  $hash->{ParseFn}       = "MAX_Parse";
  $hash->{SetFn}         = "MAX_Set";
  $hash->{GetFn}         = "MAX_Get";
  $hash->{RenameFn}      = "MAX_RenameFn";
  $hash->{NotifyFn}      = "MAX_Notify";
  $hash->{DbLog_splitFn} = "MAX_DbLog_splitFn";
  $hash->{AttrFn}        = "MAX_Attr";
  $hash->{AttrList}      = "IODev CULdev actCycle do_not_notify:1,0 ignore:0,1 dummy:0,1 keepAuto:0,1 debug:0,1 scanTemp:0,1 skipDouble:0,1 externalSensor ".
  "model:HeatingThermostat,HeatingThermostatPlus,WallMountedThermostat,ShutterContact,PushButton,Cube,PlugAdapter autosaveConfig:1,0 ".
  "peers sendMode:peers,group,Broadcast dTempCheck:0,1 windowOpenCheck:0,1 DbLog_log_onoff:0,1 ".$readingFnAttributes;

  return;
}

#############################
sub MAX_Define {

    my $hash = shift;
    my $def  = shift;

    my ($name, undef, $type, $addr) = split(m{ \s+ }xms, $def, 4);

    return "name $name is reserved for internal use" if (($name eq 'fakeWallThermostat') || ($name eq 'fakeShutterContact'));

    my $devtype = MAX_TypeToTypeId($type);

    return "$name, invalid MAX type $type !" if (!$devtype);
    return "$name, invalid address $addr !"  if (($addr !~ m/^[a-fA-F0-9]{6}$/ix) || ($addr eq '000000'));

    $addr = lc($addr); # all addr should be lowercase

 
    if (exists($modules{MAX}{defptr}{$addr}) && $modules{MAX}{defptr}{$addr}->{NAME} ne $name) {
	my $msg = "MAX_Define, a MAX device with address $addr is already defined as ".$modules{MAX}{defptr}{$addr}->{NAME};
	Log3($name, 2, $msg);
	return $msg;
    }
 
    my $old_addr = '';

    # check if we have this address already in use
    foreach my $dev ( keys %{$modules{MAX}{defptr}} ) {
	next if (!$modules{MAX}{defptr}{$dev}->{NAME});
	$old_addr = $dev if  ($modules{MAX}{defptr}{$dev}->{NAME} eq $name);
	last if ($old_addr); # device found
    }

    if (($old_addr ne '') && ($old_addr ne $addr)){
	my $msg1 = 'please dont change the address direct in DEF or RAW !';
        my $msg2 = "If you want to change $old_addr please delete device $name first and create a new one";
	Log3($name, 3, "$name, $msg1 $msg2");
	return $msg1."\n".$msg2;
    }

    if (exists($modules{MAX}{defptr}{$addr}) && $modules{MAX}{defptr}{$addr}->{type} ne $type) {
	my $msg = "$name, type changed from $modules{MAX}{defptr}{$addr}->{type} to $type !";
	Log3($name, 2, $msg);
    }

    Log3 $hash, 5, 'Max_define, '.$name.' '.$type.' with addr '.$addr;

    $hash->{type}                = $type;
    $hash->{devtype}             = $devtype;
    $hash->{addr}                = $addr;
    $hash->{TimeSlot}            = -1 if ($type =~ /.*Thermostat.*/); # wird durch CUL_MAX neu gesetzt 
    $hash->{'.count'}            = 0; # ToDo Kommentar
    $hash->{'.sendToAddr'}       = '-1'; # zu wem haben wird direkt gesendet ?
    $hash->{'.sendToName'}       = '';
    $hash->{'.timer'}            = 300;
    $hash->{SVN}                 = (qw($Id$))[2];
    $modules{MAX}{defptr}{$addr} = $hash;

    #$hash->{internals}{interfaces} = $interfaces{$type}; # wozu ?

    AssignIoPort($hash);

    CommandAttr(undef,$name.' model '.$type); # Forum Stats werten nur attr model aus

    if ($init_done == 1) {
    #nur beim ersten define setzen:
	if (($hash->{devtype} < 4) || ($hash->{devtype} == 7)) {
    	    $attr{$name}{room} = 'MAX' if( not defined( $attr{$name}{room} ) );
    	    MAX_ReadingsVal($hash,'groupid');
    	    MAX_ReadingsVal($hash,'windowOpenTemperature') if ($hash->{devtype} == 7);
    	    readingsBeginUpdate($hash);
    	    MAX_ParseWeekProfile($hash);
    	    readingsEndUpdate($hash,0);
	}
    }

    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+5, 'MAX_Timer', $hash, 0) if ($hash->{devtype} != 5);

    return;
}


sub MAX_Timer
{
  my $hash = shift;
  my $name = $hash->{NAME};

  if (!$init_done)
  {
   InternalTimer(gettimeofday()+5,"MAX_Timer", $hash, 0);
   return;
  }

  AssignIoPort($hash, AttrVal($name,'IODev','')) if (exists($hash->{IODevMissing})); # mit proposed $_

  InternalTimer(gettimeofday() + $hash->{'.timer'}, "MAX_Timer", $hash, 0) if ($hash->{'.timer'});

  return if (IsDummy($name) || IsIgnored($name));

  if ($hash->{devtype} && (($hash->{devtype} < 4) || ($hash->{devtype} == 8)))
  {
   my $dt = ReadingsNum($name,'desiredTemperature',0);
   if ($dt == ReadingsNum($name,'windowOpenTemperature','0')) # kein check bei offenen Fenster
   {
    my $age = sprintf "%02d:%02d", (gmtime(ReadingsAge($name,'desiredTemperature', 0)))[2,1];
    readingsSingleUpdate($hash,'windowOpen', $age,1) if (AttrNum($name,'windowOpenCheck',0));
    $hash->{'.timer'} = 60;
    return;
   }

   if ((ReadingsVal($name,'mode','manu') eq 'auto') && AttrNum($name,'dTempCheck',0))
   {
    $hash->{saveConfig} = 1;     # verhindern das alle weekprofile Readings neu geschrieben werden
    MAX_ParseWeekProfile($hash); # $hash->{helper}{dt} aktualisieren
    delete $hash->{saveConfig};

    my $c = ($dt != $hash->{helper}{dt}) ? sprintf("%.1f", ($dt-$hash->{helper}{dt})) : 0;
    delete $hash->{helper}{dtc} if (!$c && exists($hash->{helper}{dtc}));
    if ($c && (!exists($hash->{helper}{dtc}))) {$hash->{helper}{dtc}=1; $c=0; }; # um eine Runde verzögern
    readingsBeginUpdate($hash);
     readingsBulkUpdate($hash,'dTempCheck', $c);
     readingsBulkUpdate($hash,'windowOpen', '0') if (AttrNum($name,'windowOpenCheck',0));
    readingsEndUpdate($hash,1);
    $hash->{'.timer'} = 300;
    Log3 $hash,3,$name.', Tempcheck NOK Reading : '.$dt.' <-> WeekProfile : '.$hash->{helper}{dt} if ($c);
   }
  }
   elsif ((($hash->{devtype} == 4) || ($hash->{devtype} == 6)) && AttrNum($name,'windowOpenCheck',1))
  {
   if (ReadingsNum($name,'onoff',0))
   {
    my $age = (sprintf "%02d:%02d", (gmtime(ReadingsAge($name,'onoff', 0)))[2,1]);
    readingsSingleUpdate($hash,'windowOpen', $age ,1);
    $hash->{'.timer'} = 60;
   }
   else 
   {
    readingsSingleUpdate($hash,'windowOpen', '0',1);
    $hash->{'.timer'} = 300;
   }
  }
  return;
}


sub MAX_Attr
{
  my ($cmd, $name, $attrName, $attrVal) = @_;
  my $hash = $defs{$name};

 if ($cmd eq 'del')
 {
   return 'FHEM statistics are using this, please do not delete or change !' if ($attrName eq 'model');
   $hash->{'.actCycle'} = 0 if ($attrName eq 'actCycle');
   if ($attrName eq 'externalSensor') 
   {
    delete($hash->{NOTIFYDEV}); 
    notifyRegexpChanged($hash,'global');
   }
   return;
 }

 if ($cmd eq 'set') 
 {
  if ($attrName eq 'model')
  {
    #$$attrVal = $hash->{type}; bzw. $_[3] = $hash->{type} , muss das sein ?
    return "$name, model is $hash->{type}" if ($attrVal ne $hash->{type});
  }
  elsif ($attrName eq 'dummy')
  {
   $attr{$name}{scanTemp}  = '0' if (AttrNum($name,'scanTemp',0) && int($attrVal));
  }
  elsif ($attrName eq 'CULdev')
  {
    # ohne Abfrage von init_done : Reihenfoleproblem in der fhem.cfg !
    return "$name, invalid CUL device $attrVal" if (!exists($defs{$attrVal}) && $init_done);
  }
  elsif ($attrName eq 'actCycle')
  {
    my @ar = split(':',$attrVal);
    $ar[0] = 0 if (!$ar[0]);
    $ar[1] = 0 if (!$ar[1]);
    my $v = (int($ar[0])*3600) + (int($ar[1])*60);
    $hash->{'.actCycle'} = $v if ($v >= 0);
  } 
  elsif ($attrName eq 'externalSensor')
  {
   return $name.', attribute externalSensor is not supported for this device !' if ($hash->{devtype}>2) && ($hash->{devtype}<6);
    my ($sd,$sr,$sn) = split (':',$attrVal);
    if($sd && $sr && $sn)
    {
     notifyRegexpChanged($hash,'$sd:$sr');
     $hash->{NOTIFYDEV}=$sd;
    }
  }
 }
 return;
}

sub MAX_Undef
{
  my $hash = shift;
  delete($modules{MAX}{defptr}{$hash->{addr}});
  return;
}

sub MAX_TypeToTypeId
{
  my $type = shift;
  foreach my $id (keys %device_types)
  {
    return $id if ($type eq $device_types{$id});
  }
  return 0;
}


sub MAX_CheckIODev
{
  my $hash = shift;
  return !defined($hash->{IODev}) || ($hash->{IODev}{TYPE} ne "MAXLAN" && $hash->{IODev}{TYPE} ne "CUL_MAX");
}

# Print number in format "0.0", pass "on" and "off" verbatim, convert 30.5 and 4.5 to "on" and "off"
# Used for "desiredTemperature", "ecoTemperature" etc. but not "temperature"

#sub MAX_SerializeTemperature($)
#{
  #if (($_[0] eq  "on") || ($_[0] eq "off"))  { return $_[0]; } 
  #elsif($_[0] == 4.5)                        { return "off"; } 
  #elsif($_[0] == 30.5)                       { return "on"; } 
  #return sprintf("%2.1f",$_[0]);
#}

sub MAX_SerializeTemperature
{
 my $t = shift;
 return $t    if ( $t =~ /^(on|off)$/ );
 return 'off' if ( $t ==  4.5 );
 return 'on'  if ( $t == 30.5 );
 return sprintf("%2.1f", $t);
}

sub MAX_Validate # Todo : kann das weg ?
{
  my $name = shift;
  my $val  = shift;
  return 1 if (!exists($readingDef{$name}));
  return $readingDef{$name}[0]->($val);
}

# Get a reading, validating it's current value (maybe forcing to the default if invalid)
# "on" and "off" are converted to their numeric values

sub MAX_ReadingsVal
{
  my $hash    = shift;
  my $reading = shift;
  my $newval  = shift;
  my $name    = $hash->{NAME};

  if (defined($newval))
  {
    return if ($newval eq '');
    if (exists($hash->{".updateTimestamp"})) # readingsBulkUpdate ist aktiv, wird von fhem.pl gesetzt/gelöscht
    {
      readingsBulkUpdate($hash,$reading,$newval);
    }
     else
    {
      readingsSingleUpdate($hash,$reading,$newval,1);
    }
   return;
  }

  my $val = ReadingsVal($name,$reading,"");
  # $readingDef{$name} array is [validatingFunc, defaultValue]
  if (exists($readingDef{$reading}) && (!$readingDef{$reading}[0]->($val)))
  {
    #Error: invalid value
    my $err = "invalid or missing value $val for READING $reading";
    $val = $readingDef{$reading}[1];
    Log3 $hash, 3, "$name, $err , forcing to $val";

    #Save default value to READINGS
    if (exists($hash->{".updateTimestamp"})) # readingsBulkUpdate ist aktiv, wird von fhem.pl gesetzt/gelöscht
    {
      readingsBulkUpdate($hash,$reading,$val);
      readingsBulkUpdate($hash,'error',$err);
    }
     else
    {
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash,$reading,$val);
      readingsBulkUpdate($hash,'error',$err);
      readingsEndUpdate($hash,0);
    }
  }
  return MAX_ParseTemperature($val); # ToDo : nochmal alle Aufrufe duchsehen ob das hier Sinn macht
}

sub MAX_ParseWeekProfile
{
  my $hash  = shift;
  my @lines = undef;

  # Format of weekprofile: 16 bit integer (high byte first) for every control point, 13 control points for every day
  # each 16 bit integer value is parsed as
  # int time = (value & 0x1FF) * 5;
  # int hour = (time / 60) % 24;
  # int minute = time % 60;
  # int temperature = ((value >> 9) & 0x3F) / 2;

  my $curWeekProfile = MAX_ReadingsVal($hash, ".weekProfile");

  my (undef,$min,$hour,undef,undef,undef,$wday) = localtime(gettimeofday());
  # (Sun,Mon,Tue,Wed,Thu,Fri,Sat) -> localtime
  # (Sat,Sun,Mon,Tue,Wed,Thu,Fri) -> MAX intern
  $wday++; # localtime = MAX Day;
  $wday -= 7 if ($wday > 6);
  my $daymins = ($hour*60)+$min;

  $hash->{helper}{dt} = -1;

  #parse weekprofiles for each day
  for (my $i=0;$i<7;$i++) 
  {
    $hash->{helper}{myday} = $i if ($i == $wday);

    my (@time_prof, @temp_prof);
    for(my $j=0;$j<13;$j++) 
    {
      $time_prof[$j] = (hex(substr($curWeekProfile,($i*52)+ 4*$j,4))& 0x1FF) * 5;
      $temp_prof[$j] = (hex(substr($curWeekProfile,($i*52)+ 4*$j,4))>> 9 & 0x3F ) / 2;
    }

    my @hours;
    my @minutes;
    my $j; # ToDo umschreiben ! 

    for($j=0;$j<13;$j++) 
    {
      $hours[$j] = ($time_prof[$j] / 60 % 24);
      $minutes[$j] = ($time_prof[$j]%60);
      #if 00:00 reached, last point in profile was found
      if (int($hours[$j]) == 0 && int($minutes[$j]) == 0) 
      {
        $hours[$j] = 24;
        last;
      }
    }

    my $time_prof_str = "00:00";
    my $temp_prof_str;
    my $line ='';
    my $json_ti ='';
    my $json_te ='';

    for (my $k=0;$k<=$j;$k++) 
    { 
      $time_prof_str .= sprintf("-%02d:%02d", $hours[$k], $minutes[$k]);
      $temp_prof_str .= sprintf("%2.1f °C",$temp_prof[$k]);

      my $t = (sprintf("%2.1f",$temp_prof[$k])+0);
      $line .=  $t.',';
      $json_te .="\"$t\"";

      $t = sprintf("%02d:%02d", $hours[$k], $minutes[$k]);
      $line .=  $t;
      $json_ti .="\"$t\"";

      if (($i == $wday) && (((($hours[$k]*60)+$minutes[$k]) > $daymins) && ($hash->{helper}{dt} < 0)))
      {
       # der erste Schaltpunkt in der Zukunft ist es
       $hash->{helper}{dt} = sprintf("%.1f",$temp_prof[$k]);
      }
 
      if ($k < $j) 
      {
        $time_prof_str .= "  /  " . sprintf("%02d:%02d", $hours[$k], $minutes[$k]);
        $temp_prof_str .= "  /  ";
        $line .= ','; $json_ti .=','; $json_te .=',';
      }
    }
    if (!defined($hash->{saveConfig}))
    {
     readingsBulkUpdate($hash, "weekprofile-$i-$decalcDays{$i}-time", $time_prof_str );
     readingsBulkUpdate($hash, "weekprofile-$i-$decalcDays{$i}-temp", $temp_prof_str );
    }
    else
    {
     push @lines ,'set '.$hash->{NAME}.' weekProfile '.$decalcDays{$i}.' '.$line;
     push @lines ,'setreading '.$hash->{NAME}." weekprofile-$i-$decalcDays{$i}-time ".$time_prof_str;
     push @lines ,'setreading '.$hash->{NAME}." weekprofile-$i-$decalcDays{$i}-temp ".$temp_prof_str;
     push @lines ,'"'.$decalcDays{$i}.'":{"time":['.$json_ti.'],"temp":['.$json_te.']}';
    }
  }
 return @lines;
}
#############################

sub MAX_WakeUp
{
  my $hash = shift;
  #3F corresponds to 31 seconds wakeup (so its probably the lower 5 bits)
  return ($hash->{IODev}{Send})->($hash->{IODev},"WakeUp",$hash->{addr}, "3F", callbackParam => "31" );
}

sub MAX_Get
{
  my $hash = shift;
  my $name = shift;
  my $cmd  = shift;

  return "no get value specified" if(!$cmd);

  my $dev  = shift;

  return if (IsDummy($name) || IsIgnored($name) || ($hash->{devtype} == 6));

  my $backuped_devs = MAX_BackupedDevs($name);

  return  if(!$backuped_devs);

  if ($cmd eq 'show_savedConfig')
  {
   my $ret;
   my $dir = AttrVal('global','logdir','./log/');
   $dir .='/' if ($dir  !~ m/\/$/);

   my ($error,@lines) = FileRead($dir.$dev.'.max');
   return $error if($error);
   foreach (@lines) { $ret .= $_."\n"; }
   return $ret;
  }

  return 'unknown argument '.$cmd.' , choose one of show_savedConfig:'.$backuped_devs;
}

sub MAX_Set($@)
{
  my ($hash, $devname, @ar) = @_;
  my ($setting, @args) = @ar;
  my $ret = '';
  my $devtype = int($hash->{devtype});

  return if (IsDummy($devname) || IsIgnored($devname) || !$devtype || ($setting eq 'valveposition'));

  if ($setting eq 'mode')
  {
    if ($args[0] eq 'auto') { $setting='desiredTemperature';}
    if ($args[0] eq 'manual') 
    { $setting ='desiredTemperature'; 
      $args[0] = ReadingsVal($devname,'desiredTemperature','20') if (!$args[1]);
    }
  }

  if (($setting eq "export_Weekprofile") && ReadingsVal($devname,'.wp_json',''))
  {
   return CommandSet(undef, $args[0].' profile_data '.$devname.' '.ReadingsVal($devname,'.wp_json',''));
  }
  elsif ($setting eq "saveConfig")
  {
   return MAX_saveConfig($devname,$args[0]);
  }
  elsif ($setting eq "saveAll")
  {
   return MAX_Save('all');
  }
  elsif (($setting eq "restoreReadings") || ($setting eq "restoreDevice"))
  {
   my $f = $args[0];
   $args[0] =~ s/(.)/sprintf("%x",ord($1))/eg;
   return if (!$f || ($args[0] eq 'c2a0'));
   return MAXX_Restore($devname,$setting,$f);
  }
  elsif($setting eq "deviceRename") 
  {
    my $newName = $args[0];
    return CommandRename(undef,$devname.' '.$newName);
  }

  return $devname.', invalid IODev' if(MAX_CheckIODev($hash));
  return $devname.', can not set without IODev' if(!exists($hash->{IODev}));

  if($setting eq 'desiredTemperature' and $hash->{type} =~ /.*Thermostat.*/) 
  {
    return $devname.', missing value' if(!@args);

    my $temperature;
    my $until = undef;
    my $ctrlmode = 1; # 0=auto, 1=manual; 2=temporary
    

    if($args[0] eq "auto") 
    {
      # This enables the automatic/schedule mode where the thermostat follows the weekly program
      # There can be a temperature supplied, which will be kept until the next switch point of the weekly program

      if(@args == 2) 
      {
        if($args[1] eq "eco") 
        {
          $temperature = MAX_ReadingsVal($hash,"ecoTemperature");
        } 
        elsif($args[1] eq "comfort") 
        {
          $temperature = MAX_ReadingsVal($hash,"comfortTemperature");
        } 
        else 
        {
          $temperature = MAX_ParseTemperature($args[1]);
        }
      } 
       elsif(@args == 1) 
      {
        $temperature = 0; # use temperature from weekly program
      } 
       else
      {
        return $devname.', too many parameters: desiredTemperature auto [<temperature>]';
      }
      $ctrlmode = 0; #auto
    } # auto
     elsif($args[0] eq "boost") 
    {
      return $devname.', too many parameters: desiredTemperature boost' if(@args > 1);
      $temperature = 0;
      $ctrlmode = 3;
      #TODO: auto mode with temperature is also possible
    } 
     else
    {
      if($args[0] eq "manual") 
      {
        # User explicitly asked for manual mode
        $ctrlmode = 1; #manual, possibly overwriting keepAuto
        shift @args;
        return $devname.', not enough parameters after desiredTemperature manual' if(!@args);

      } 
      elsif(AttrNum($devname,'keepAuto',0)  && (MAX_ReadingsVal($hash,'mode') eq 'auto'))
      {
         # User did not ask for any mode explicitly, but has keepAuto
         Log3 $hash, 5, $devname.', Set: staying in auto mode';
         $ctrlmode = 0; # auto
      }

      if($args[0] eq 'eco') 
      {
        $temperature = MAX_ReadingsVal($hash,'ecoTemperature');
      } 
      elsif($args[0] eq 'comfort') 
      {
        $temperature = MAX_ReadingsVal($hash,'comfortTemperature');
      } 
      else 
      {
        $temperature = MAX_ParseTemperature($args[0]);
      }

      if(@args > 1) 
      {
        # @args == 3 and $args[1] == "until"
        return $devname.', second parameter must be until' if($args[1] ne 'until');
        return $devname.', wrong parameters : desiredTemperature <temp> until <date> <time>' if(@args != 4);

       $ctrlmode = 2; #switch manual to temporary
       my $check = 1;
       my ($day,$month,$year);

       if ($args[2] eq 'today')
       {
        (undef,undef,undef,$day,$month,$year) = localtime(gettimeofday());
        $month++; $year+=1900;
       }
       else
       {
        ($day, $month, $year) = split('\.',$args[2]);
       }

       my ($hour,$min)  = split(":", $args[3]);
       $day++; $day--; $month++; $month--; $year++; $year--; $hour++; $hour--; $min++; $min--; # mache alle zu int

       $check = 0 if (!$day || !$month || !$year || ($day > 31) || ($month > 12) || ($hour > 23));
       $check = 0 if (($min != 0) && ($min != 30));
       return "$devname, invalid Date or Time -> D[1-31] : $day, M[1-12] : $month, Y: $year, H[0-23]: $hour, M[0,30]: $min" if (!$check);

       $year +=2000 if ($year < 100);
       return "$devname, end date and time is not future" if ((str2time("$month/$day/$year $hour:$min:00")-time()) < 0);

        $until = sprintf("%06x",(($month&0xE) << 20) | ($day << 16) | (($month&1) << 15) | (($year-2000) << 8) | ($hour*2 + int($min/30)));
      }
    } # kein auto / boost

    my $payload = sprintf("%02x",int($temperature*2.0) | ($ctrlmode << 6));
      $payload .= $until if(defined($until));
    my $groupid = MAX_ReadingsVal($hash,"groupid");

    $args[0] = $temperature; 
    my $val  = join(' ',@args);

    if ($devtype != 7)
    { 
     MAX_ReadingsVal($hash,'lastcmd','set_desiredTemperature '.$val);
     return ($hash->{IODev}{Send})->($hash->{IODev},"SetTemperature",$hash->{addr},$payload, callbackParam => $val, groupId => sprintf("%02x",$groupid), flags => ( $groupid ? "04" : "00" ));
    }
    else
    { 
      #return "Invalid number of arguments" if(@args != 3);
      #return "desiredTemperature is invalid" if(!validTemperature($temperature));

      #Valid range for measured temperature is 0 - 51.1 degree
      #$args[2] = 0 if($args[2] < 0); #Clamp temperature to minimum of 0 degree

      #Encode into binary form
      #my $arg2 = int(10*$args[2]);
      #First bit is 9th bit of temperature, rest is desiredTemperature
      #my $arg1 = (($arg2&0x100)>>1) | (int(2*MAX_ParseTemperature($args[1]))&0x7F);
      #$arg2 &= 0xFF; #only take the lower 8 bits
      #my $groupid = ReadingsNum($devname,'groupid',0);

      #return CUL_MAX_Send($hash,"WallThermostatControl",'000000',
      #    sprintf("%02x%02x",$arg1,$arg2), groupId => sprintf("%02x",$groupid),flags => ( $groupid ? "04" : "00" ),src => $hash->{addr});

      MAX_ReadingsVal($hash,'desiredTemperature',$temperature);
      my $mode; 
      $mode = 'auto'      if (!$ctrlmode);
      $mode = 'manual'    if ($ctrlmode == 1);
      $mode = 'temporary' if ($ctrlmode == 2);
      $mode = 'boost'     if ($ctrlmode == 3);

      MAX_ReadingsVal($hash,'mode',$mode);
      #MAX_ReadingsVal($hash,'temperature',$temperature);
    }
  }
  elsif(grep (/^\Q$setting\E$/, ("boostDuration", "boostValveposition", "decalcification","maxValveSetting","valveOffset")) and $hash->{type} =~ /.*Thermostat.*/)
  {

    $args[0] =~ s/ //g;
    my $val = join(" ",@args); # decalcification contains a space

    if (($args[0] =~ m/1$/) && ($setting eq 'decalcification'))
    {
      my (undef,undef,$hour,undef,undef,undef,$wday,undef,undef) = localtime(gettimeofday());

      # (Sun,Mon,Tue,Wed,Thu,Fri,Sat) -> localtime
      # (Sat,Sun,Mon,Tue,Wed,Thu,Fri) -> MAX intern

      if ($args[0] eq  "1") # morgen ?
      {
       $hour ++;
       $hour  = 0 if ($hour > 23);
       $wday += 2; 
       $wday -= 7 if ($wday > 6);
      } # else für args[0] == -1 gestern entfällt, da MAX eh einen -1 Versatz zu localtime hat

      $val = $decalcDays{$wday}.' '.sprintf("%02d", $hour).':00';
    }
    elsif(!MAX_Validate($setting, $val))
    {
      my $msg = $devname.', invalid value '.$args[0].' for '.$setting;
      Log3 $hash, 1, $msg;
      return $msg;
    }

    MAX_ReadingsVal($hash,'lastcmd','set_'.$setting.' '. $val); 

    my %h;
    $h{boostDuration}      = MAX_ReadingsVal($hash,"boostDuration");
    $h{boostValveposition} = MAX_ReadingsVal($hash,"boostValveposition");
    $h{decalcification}    = MAX_ReadingsVal($hash,"decalcification");
    $h{maxValveSetting}    = MAX_ReadingsVal($hash,"maxValveSetting");
    $h{valveOffset}        = MAX_ReadingsVal($hash,"valveOffset");
    #$h{$setting}          = MAX_ParseTemperature($val); + wozu on/off wandeln wenn es hier eh keine Temperaturen gibt ?
    $h{$setting}           = $val;

    my ($decalcDay, $decalcHour) = ($h{decalcification} =~ /^(...) (\d{1,2}):00$/);

    my $decalc  = ($decalcDaysInv{$decalcDay} << 5) | $decalcHour;
    my $boost   = ($boost_durationsInv{$h{boostDuration}} << 5) | int($h{boostValveposition}/5);
    my $payload = sprintf("%02x%02x%02x%02x", $boost, $decalc, int($h{maxValveSetting}*255/100), int($h{valveOffset}*255/100));

    if (($devtype < 6) || ($devtype == 8))
     { return ($hash->{IODev}{Send})->($hash->{IODev},"ConfigValve",$hash->{addr},$payload,callbackParam => "$setting,$val"); }
     else 
     { MAX_ReadingsVal($hash,$setting,$val); }
    
  }
  elsif($setting eq "groupid")
  {
    return "argument needed" if(@args == 0);

    $args[0] = int($args[0]);
    MAX_ReadingsVal($hash,'lastcmd','set_groupid '. $args[0]) if (($devtype < 5) || ($devtype == 8));

    if ($args[0])
    {
     if (($devtype < 5) || ($devtype == 8))
     {
      return ($hash->{IODev}{Send})->($hash->{IODev},"SetGroupId",$hash->{addr}, sprintf("%02x",$args[0]), callbackParam => "$args[0]" );
     }
     else { MAX_ReadingsVal($hash,'groupid',$args[0],1); return;} # Virtueller FK / WT
    } 
    else
    {
     if (($devtype < 5) || ($devtype == 8))
     {
      return ($hash->{IODev}{Send})->($hash->{IODev},"RemoveGroupId",$hash->{addr}, "00", callbackParam => "0");
     }
     else { MAX_ReadingsVal($hash,'groupid','0',1); return; } # Virtueller FK / WT
    }
  }
  elsif( grep (/^\Q$setting\E$/, ("ecoTemperature", "comfortTemperature", "measurementOffset", "maximumTemperature", "minimumTemperature", "windowOpenTemperature", "windowOpenDuration" )) and $hash->{type} =~ /.*Thermostat.*/) 
  {
    if(!MAX_Validate($setting, $args[0])) 
    {
      $ret = $devname.', invalid value '.$args[0].' for '.$setting;
      Log3 $hash, 1, $ret;
      return $ret;
    }

    my %h;
    $h{comfortTemperature}    = MAX_ReadingsVal($hash,"comfortTemperature");
    $h{ecoTemperature}        = MAX_ReadingsVal($hash,"ecoTemperature");
    $h{maximumTemperature}    = MAX_ReadingsVal($hash,"maximumTemperature");
    $h{minimumTemperature}    = MAX_ReadingsVal($hash,"minimumTemperature");
    $h{windowOpenTemperature} = MAX_ReadingsVal($hash,"windowOpenTemperature");
    $h{windowOpenDuration}    = MAX_ReadingsVal($hash,"windowOpenDuration");
    $h{measurementOffset}     = MAX_ReadingsVal($hash,"measurementOffset");

    $h{$setting}              = MAX_ParseTemperature($args[0]);
    MAX_ReadingsVal($hash,'lastcmd','set_'.$setting.' '.$args[0]);

    my $comfort        = int($h{comfortTemperature}*2);
    my $eco            = int($h{ecoTemperature}*2);
    my $max            = int($h{maximumTemperature}*2);
    my $min            = int($h{minimumTemperature}*2);
    my $offset         = int(($h{measurementOffset} + 3.5)*2);
    my $windowOpenTemp = int($h{windowOpenTemperature}*2);
    my $windowOpenTime = int($h{windowOpenDuration}/5);

    my $groupid        = MAX_ReadingsVal($hash,"groupid");
    my $payload        = sprintf("%02x%02x%02x%02x%02x%02x%02x",$comfort,$eco,$max,$min,$offset,$windowOpenTemp,$windowOpenTime);

    if ($devtype != 7)
    {
     if($setting eq "measurementOffset") 
     {
      return ($hash->{IODev}{Send})->($hash->{IODev},"ConfigTemperatures",$hash->{addr},$payload, groupId => "00", flags => "00", callbackParam => "$setting,$args[0]");
     } 
     else 
     {
      return ($hash->{IODev}{Send})->($hash->{IODev},"ConfigTemperatures",$hash->{addr},$payload, groupId => sprintf("%02x",$groupid), flags => ( $groupid ? "04" : "00" ), callbackParam => "$setting,$args[0]");
     }
    } else {MAX_ReadingsVal($hash,$setting,$args[0]); }
  } 
  elsif($setting eq "displayActualTemperature" and $hash->{type} eq "WallMountedThermostat") 
  {
    return $devname.', invalid arg' if($args[0] ne '0' and $args[0] ne '1');
    MAX_ReadingsVal($hash,'lastcmd','set_displayActualTemperature'. $args[0]);
    if ($devtype < 6)
    { return ($hash->{IODev}{Send})->($hash->{IODev},"SetDisplayActualTemperature",$hash->{addr},sprintf("%02x",$args[0] ? 4 : 0), callbackParam => "$setting,$args[0]");}
    else 
    { MAX_ReadingsVal($hash,$setting,$args[0]); }

  } 
  elsif(grep /^\Q$setting\E$/, ("associate", "deassociate")) 
  {
    my $dest = $args[0];
    my $destType;
    if($dest eq 'fakeWallThermostat') 
    {
      return $devname.', IODev is not CUL_MAX' if($hash->{IODev}->{TYPE} ne 'CUL_MAX');
      $dest = AttrVal($hash->{IODev}->{NAME}, 'fakeWTaddr', '111111');
      return $devname.', invalid fakeWTaddr attribute set (must not be 000000)' if($dest eq '000000');
      $destType = MAX_TypeToTypeId('WallMountedThermostat'); # ToDo : reicht nicht auch einfach nur 3 ?
    } 
     elsif($dest eq 'fakeShutterContact') 
    {
      return $devname.', IODev is not CUL_MAX' if($hash->{IODev}->{TYPE} ne 'CUL_MAX');
      $dest = AttrVal($hash->{IODev}->{NAME}, 'fakeSCaddr', '222222');
      return $devname.', invalid fakeSCaddr attribute set (must not be 000000)' if($dest eq '000000');
      $destType = MAX_TypeToTypeId('ShutterContact'); # ToDo : reicht nicht auch einfach nur 4 ?
    } 
     else 
    {
      if(exists($defs{$dest})) 
      {
        return $devname.', destination is not a MAX device' if($defs{$dest}{TYPE} ne 'MAX');
        $dest = $defs{$dest}{addr}; # übersetzung des Namens in HEX Adresse
      }
       else
      { 
        return $devname.', no MAX device found with address '.$dest if(!exists($modules{MAX}{defptr}{$dest}));
      }
      $destType = MAX_TypeToTypeId($modules{MAX}{defptr}{$dest}{type});
      $destType = 4 if ($destType == 6);
      $destType = 3 if ($destType == 7);
    }

    Log3 $hash, 4, "$devname, Setting $setting, Destination $dest, destType $destType [".$modules{MAX}{defptr}{$dest}{type}.']';
    MAX_ReadingsVal($hash,'lastcmd','set_'.$setting.' '. $args[0]);

    if($setting eq "associate") 
    {
      if($hash->{IODev}->{TYPE} ne 'CUL_MAX')
      {
       return ($hash->{IODev}{Send})->($hash->{IODev},"AddLinkPartner",$hash->{addr},sprintf("%s%02x", $dest, $destType));
      }
      else
      {
       return ($hash->{IODev}{Send})->($hash->{IODev},"AddLinkPartner",$hash->{addr},sprintf("%s%02x", $dest, $destType),callbackParam=>"$setting,$dest");
      }
    } 
     else 
    {
     if($hash->{IODev}->{TYPE} ne 'CUL_MAX')
     {
       return ($hash->{IODev}{Send})->($hash->{IODev},"RemoveLinkPartner",$hash->{addr},sprintf("%s%02x", $dest, $destType));
     }
     else
     {
       return ($hash->{IODev}{Send})->($hash->{IODev},"RemoveLinkPartner",$hash->{addr},sprintf("%s%02x", $dest, $destType),callbackParam=>"$setting,$dest");
     }
    }
  } 
  elsif($setting eq "factoryReset") 
  {
    MAX_ReadingsVal($hash,'lastcmd','set_factoryReset');
    if(exists($hash->{IODev}{RemoveDevice})) 
    {
      #MAXLAN
      return ($hash->{IODev}{RemoveDevice})->($hash->{IODev},$hash->{addr});
    } 
     else 
    {
      #CUL_MAX
      return ($hash->{IODev}{Send})->($hash->{IODev},"Reset",$hash->{addr});
    }
  } 
   elsif($setting eq "wakeUp") 
  {
    return MAX_WakeUp($hash);
  }
   elsif($setting eq "weekProfile" and $hash->{type} =~ /.*Thermostat.*/) 
  {
    return "Invalid arguments.  You must specify at least one: <weekDay> <temp[,hh:mm]>\nExample: Mon 10,06:00,17,09:00" if((@args%2 == 1)||(@args == 0));

    #Send wakeUp, so we can send the weekprofile pakets without preamble
    #Disabled for now. Seems like the first packet is lost. Maybe inserting a delay after the wakeup will fix this
    #MAX_WakeUp($hash) if( @args > 2 );

    for(my $i = 0; $i < @args; $i += 2) 
    {
      return "Expected day (one of ".join (",",@weekDays)."), got $args[$i]" if(!exists($decalcDaysInv{$args[$i]}));
      my $day = $decalcDaysInv{$args[$i]};
      my @controlpoints = split(',',$args[$i+1]);
      return "Not more than 13 control points are allowed!" if(@controlpoints > 13*2);
      my $newWeekprofilePart = "";
      for(my $j = 0; $j < 13*2; $j += 2) 
      {
        if( $j >= @controlpoints ) {
          $newWeekprofilePart .= "4520";
          next;
        }
        my ($hour, $min);
        if($j + 1 == @controlpoints) 
        {
          $hour = 24; $min = 0;
        } 
         else 
        {
          ($hour, $min) = ($controlpoints[$j+1] =~ /^(\d{1,2}):(\d{1,2})$/);
        }
        my $temperature = $controlpoints[$j];
        return "Invalid time: $controlpoints[$j+1]" if(!defined($hour) || !defined($min) || $hour > 24 || $min > 59 || ($hour == 24 && $min > 0));
        return "Invalid temperature (Must be one of: off|on|5|5.5|6|6.5..30)" if(!MAX_validTemperature($temperature));
        $temperature = MAX_ParseTemperature($temperature); #replace "on" and "off" by their values
        $newWeekprofilePart .= sprintf("%04x", (int($temperature*2) << 9) | int(($hour * 60 + $min)/5));
      }
      Log3 $hash, 5, $devname.", new Temperature part for $day: $newWeekprofilePart";

      #Each day has 2 bytes * 13 controlpoints = 26 bytes = 52 hex characters
      #we don't have to update the rest, because the active part is terminated by the time 0:00

      if (($devtype < 6) || ($devtype == 8))
      {
       #First 7 controlpoints (2*7=14 bytes => 2*2*7=28 hex characters )
       ($hash->{IODev}{Send})->($hash->{IODev},"ConfigWeekProfile",$hash->{addr},
          sprintf("0%1d%s", $day, substr($newWeekprofilePart,0,2*2*7)),
          callbackParam => "$day,0,".substr($newWeekprofilePart,0,2*2*7));
       #And then the remaining 6
       ($hash->{IODev}{Send})->($hash->{IODev},"ConfigWeekProfile",$hash->{addr},
          sprintf("1%1d%s", $day, substr($newWeekprofilePart,2*2*7,2*2*6)),
          callbackParam => "$day,1,".substr($newWeekprofilePart,2*2*7,2*2*6))
            if(@controlpoints > 2*7);
      }
      else
      {
       my $wp = MAX_ReadingsVal($hash,'.weekProfile');
       substr($wp,($day*52),52,$newWeekprofilePart);
       MAX_ReadingsVal($hash,'.weekProfile',$wp);
       readingsBeginUpdate($hash);
        MAX_ParseWeekProfile($hash);
       readingsEndUpdate($hash,0);
       MAX_saveConfig($devname,'') if (AttrNum($devname,'autosaveConfig',1));
      }
 
    }
  }# letztes Set Kommando 
  elsif (($setting =~ /(open|close)/) && ($devtype == 6) && ($hash->{IODev}->{TYPE} eq 'CUL_MAX'))
  {
      my $dest     = '';
      my $state    = ($setting eq 'open') ? '12' : '10';
      my $groupid  = ReadingsNum($devname,'groupid',0);
      my $sendMode = AttrVal($devname,'sendMode','Broadcast');
      #my $hash2    = $hash; # org hash retten

      if ($groupid && ($sendMode eq 'group')) 
      {
       # alle Gruppenmitglieder finden
       foreach (keys %{$modules{MAX}{defptr}}) 
       {
        my $dname = (defined($modules{MAX}{defptr}{$_}->{NAME})) ? $modules{MAX}{defptr}{$_}->{NAME} : '' ;
        next if (!$dname || ($dname eq $devname) || (ReadingsNum($dname,'groupid',0) != $groupid)); # kein Name oder er selbst oder nicht in der gruppe
        $dest = $modules{MAX}{defptr}{$_}->{addr};
        Log3 $hash, 5, "$devname, send $setting [$state] to $dest as member of group $groupid";
        my $r = $hash->{IODev}{Send}->($hash->{IODev}, "ShutterContactState",$dest,$state,groupId => sprintf("%02x",$groupid),flags => ( $groupid ? "04" : "06" ),src => $hash->{addr});
        $ret .= $r if ($r);
        #$hash = $hash2; 
       }
      }
      elsif ($sendMode eq 'peers')
      {
       my @peers = split(',', AttrVal($devname,'peers',''));
       foreach (@peers) 
       {
        if ($_)
        {
         $dest = lc($_); $dest =~ s/ //g; 
         next if ($dest !~ m/^[a-f0-9]{6}$/i);
         Log3 $hash, 5, "$devname, send $setting [$state] to $dest as member of attribut peers [".AttrVal($devname,'peers','???').']';
         my $r = $hash->{IODev}{Send}->($hash->{IODev}, "ShutterContactState",$dest,$state,groupId => sprintf("%02x",$groupid),flags => ( $groupid ? "04" : "06" ),src => $hash->{addr});
         $ret .= $r if ($r);
         #$hash = $hash2;
        }
       }
      }
      elsif ($sendMode eq 'Broadcast')
      {
        $dest = '000000';
        Log3 $hash, 5, "$devname, send $setting [$state] to $dest as Broadcast message";
        #Log3 $hash,3,Dumper($hash);
        $ret = $hash->{IODev}{Send}->($hash->{IODev}, "ShutterContactState",$dest,$state,groupId => sprintf("%02x",$groupid),flags => ( $groupid ? "04" : "06" ),src => $hash->{addr});
        #Log3 $hash,3,Dumper($hash);
        #$hash = $hash2;
      }

      if (!$dest)
      {
        $ret = 'no destination devices found for sendmode '.$sendMode.' !';
      }
       else
      {
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash,'onoff', (($setting eq 'close') ? '0' : '1'));
        readingsBulkUpdate($hash,'state', (($setting eq 'close') ? 'closed' : 'opened'));
        readingsBulkUpdate($hash,'windowOpen','0') if (AttrNum($devname,'windowOpenCheck',1) && ($setting eq 'close'));
        if ($args[0]) { readingsEndUpdate($hash,1); } else  { readingsEndUpdate($hash,0); }
        if ($setting eq 'open') # die 1 Minuten Abfrage ab jetzt
        {
         RemoveInternalTimer($hash);
         $hash->{'.timer'} = 60;
         MAX_Timer($hash);
        }
      }

    Log3 $hash, 3, "$devname, $ret" if ($ret);
    return $ret;
  }
  elsif ($setting eq 'temperature')
  {
    return if (($devtype != 7) || ($hash->{IODev}->{TYPE} ne 'CUL_MAX'));

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,'temperature', $args[0]);
    readingsEndUpdate($hash,1);

  }
  else
  {
    my $templist = join(",",map { MAX_SerializeTemperature($_/2) }  (9..61));
    #$ret  = "Unknown argument $setting, choose one of deviceRename ";
    $ret  = "deviceRename";
    $ret .= " wakeUp:noArg factoryReset:noArg groupid" if (($devtype < 5) || ($devtype == 8));

    my @ar;
    #Build list of devices which this device can be associated to
    if(($hash->{type} =~ /HeatingThermostat.*/) || ($hash->{devtype} == 8))
    {
     foreach (keys %{$modules{MAX}{defptr}}) 
     {
      next if (!$modules{MAX}{defptr}{$_}->{NAME});
      next if (!defined($modules{MAX}{defptr}{$_}->{devtype}));
      if ( ($modules{MAX}{defptr}{$_}->{devtype} > 0) # 1 - 4
        && ($modules{MAX}{defptr}{$_}->{devtype} != 5) 
        && !IsDummy  ($modules{MAX}{defptr}{$_}->{NAME}) 
        && !IsIgnored($modules{MAX}{defptr}{$_}->{NAME})
        && ($modules{MAX}{defptr}{$_}->{NAME} ne $devname))
      { push  @ar, $modules{MAX}{defptr}{$_}->{NAME}; }
     }

     if($hash->{IODev}->{TYPE} eq "CUL_MAX") 
     {
      push @ar, "fakeShutterContact";
      push @ar, "fakeWallThermostat";
     }
    } 
     elsif($hash->{type} =~ /WallMountedThermostat/)
    {
     foreach (keys %{$modules{MAX}{defptr}})
     {
      next if (!$modules{MAX}{defptr}{$_}->{NAME});
      next if (!defined($modules{MAX}{defptr}{$_}->{devtype}));
      if ( ($modules{MAX}{defptr}{$_}->{devtype} >  0) # 1,2,4
        && ($modules{MAX}{defptr}{$_}->{devtype} != 5)
        && ($modules{MAX}{defptr}{$_}->{devtype} != 3)
        && !IsDummy  ($modules{MAX}{defptr}{$_}->{NAME}) 
        && !IsIgnored($modules{MAX}{defptr}{$_}->{NAME}))
      { push  @ar, $modules{MAX}{defptr}{$_}->{NAME}; }
     }

     push @ar, "fakeShutterContact" if($hash->{IODev}->{TYPE} eq "CUL_MAX");

    }
     elsif($hash->{type} eq "ShutterContact") 
    {
     foreach ( keys %{$modules{MAX}{defptr}} ) 
     {
      next if (!$modules{MAX}{defptr}{$_}->{NAME});
      next if (!defined($modules{MAX}{defptr}{$_}->{devtype}));
      if ( ($modules{MAX}{defptr}{$_}->{devtype} > 0) # 1 - 3
        && ($modules{MAX}{defptr}{$_}->{devtype} < 4)
        && !IsDummy  ($modules{MAX}{defptr}{$_}->{NAME}) 
        && !IsIgnored($modules{MAX}{defptr}{$_}->{NAME}))
      { push  @ar, $modules{MAX}{defptr}{$_}->{NAME}; }
     }
    }

    @ar = sort @ar if (@ar > 1); 
    $ret .= " associate:".join(",",@ar)." deassociate:".join(",",@ar) if (($devtype < 5) || ($devtype == 8));

    my $templistOffset = join(",",map { MAX_SerializeTemperature(($_-7)/2) }  (0..14));
    my $boostDurVal = join(",", sort values(%boost_durations));
 
    my $wplist='';
    for (devspec2array('TYPE=weekprofile'))
    {
     if (!$wplist) {$wplist = $defs{$_}->{NAME};} else {$wplist .= ','.$defs{$_}->{NAME};}
    }
    $wplist = (ReadingsVal($devname,'.wp_json','')) ? "export_Weekprofile:".$wplist : '';
 
    my $backuped_devs = MAX_BackupedDevs($devname);

    if ($devtype < 4)# HT,HT+,WT
    {
      $ret .= " desiredTemperature:eco,comfort,boost,auto,$templist comfortTemperature:$templist ecoTemperature:$templist";
      $ret .= " measurementOffset:$templistOffset boostDuration:$boostDurVal boostValveposition";
      $ret .= " maximumTemperature:$templist minimumTemperature:$templist windowOpenTemperature:$templist";

      $ret .= " saveConfig weekProfile";
      $ret .= " restoreReadings:$backuped_devs restoreDevice:$backuped_devs" if ($backuped_devs);
      $ret .= " ".$wplist if ($wplist);
    }

    if ($devtype < 3)# HT,HT+ 
    {
      $ret .= " windowOpenDuration decalcification maxValveSetting valveOffset" ;

     # my $shash;
      #my $wt = 0;
      # check if Wallthermo is in same group
      #foreach my $addr ( keys %{$modules{MAX}{defptr}} ) 
      #{
        #$shash = $modules{MAX}{defptr}{$addr};
        #$wt = 1 if((int($shash->{devtype}) == 3) && (ReadingsNum($shash->{NAME},'groupid',0) == ReadingsNum($devname,'groupid',99)));
      #}
      #if (!$wt) 
      #{
        #$ret .= " maximumTemperature:$templist minimumTemperature:$templist";
      #}
    } 
    elsif($devtype == 3) # WT 
    {
      $ret .= " displayActualTemperature:0,1";
    } 
    elsif($devtype == 6) # virtual SC
    {
      $ret .= " groupid";
      $ret .= " open:noArg close:noArg" if (ReadingsNum($devname,'groupid',0));
    } 
    elsif($devtype == 7) # virtual WT
    {
      MAX_ReadingsVal($hash,'groupid');
      MAX_ReadingsVal($hash,'.weekprofile');

      my $backuped_devs = MAX_BackupedDevs($devname);
      $ret .= " groupid desiredTemperature:eco,comfort,boost,auto,$templist";
      $ret .= " weekProfile saveConfig";
      $ret .= " windowOpenTemperature:$templist";
      $ret .= " restoreReadings:$backuped_devs" if ($backuped_devs);
      $ret .= " ".$wplist if ($wplist);
    } 
    elsif ($devtype == 8) # PlugAdapter
    {
      $ret .= " desiredTemperature:eco,comfort,boost,auto,$templist comfortTemperature:$templist ecoTemperature:$templist";
      $ret .= " saveConfig weekProfile";
      $ret .= " restoreReadings:$backuped_devs restoreDevice:$backuped_devs" if ($backuped_devs);
      $ret .= " ".$wplist if ($wplist);
    }
 
    return AttrTemplate_Set ($hash, $ret, $devname, $setting, @args);
  } # set ?
 return;
}

sub MAX_Save
{
 my $dev = shift;
 $dev = 'all' if (!defined($dev));

 if ($dev eq 'all')
 {
  my   $list = join(",", map { defined($_->{type}) && $_->{type} =~ /.*Thermostat.*/ ? $_->{NAME} : () } values %{$modules{MAX}{defptr}});
  my @ar = split(',' , $list);
  foreach (@ar) { MAX_saveConfig($_,''); }
 }
 else { return MAX_saveConfig($dev,''); }

 return;
}

sub MAX_saveConfig
{
 my $name    = shift;
 my $fname   = shift;
 my $hash    = $defs{$name};
 my $devtype = int($hash->{devtype});
    $fname   = $name if (!$fname);
 my $dir     = AttrVal('global','logdir','./log/');
 $dir .='/' if ($dir  !~ m/\/$/);
 my @lines;
 my %h;

 if (($devtype < 4) || ($devtype == 8)) # HT , HT+ , WT
 {
  $h{'21comfortTemperature'}       = MAX_ReadingsVal($hash,"comfortTemperature");
  $h{'22.comfortTemperature'}      = $h{'21comfortTemperature'};

  $h{'23.ecoTemperature'}           = MAX_ReadingsVal($hash,"ecoTemperature");
  #$h{'24.ecoTemperature'}          = $h{'23ecoTemperature'};

  $h{'25.maximumTemperature'}       = MAX_ReadingsVal($hash,"maximumTemperature");
  #$h{'26.maximumTemperature'}      = $h{'25maximumTemperature'};

  $h{'27.minimumTemperature'}       = MAX_ReadingsVal($hash,"minimumTemperature");
  #$h{'28.minimumTemperature'}      = $h{'27minimumTemperature'};

  $h{'29.measurementOffset'}        = MAX_ReadingsVal($hash,"measurementOffset");
  #$h{'30.measurementOffset'}       = $h{'29measurementOffset'};

  $h{'31.windowOpenTemperature'}    = MAX_ReadingsVal($hash,"windowOpenTemperature");
  #$h{'32.windowOpenTemperature'}   = $h{'31windowOpenTemperature'};

  $h{'00groupid'}                  = MAX_ReadingsVal($hash, "groupid");
  $h{'01.groupid'}                 = $h{'00groupid'};
  $h{'09'}                         = '#';
  $h{'50..weekProfile'}            = MAX_ReadingsVal($hash, ".weekProfile");
  $h{'98.peers'}                   = ReadingsVal($name,'peers',undef);
  $h{'99.PairedTo'}                = ReadingsVal($name,'PairedTo',undef);
  $h{'35displayActualTemperature'} = ReadingsVal($name,'displayActualTemperature',undef) if ($devtype == 3);
  $h{'36.displayActualTemperature'}= $h{'35displayActualTemperature'};
  $h{'59'}                         = '#';
  $h{'61.temperature'}             = MAX_ReadingsVal($hash,"temperature");
  $h{'62.msgcnt'}                  = 0;
  $h{'69'}                         = '#';
 }

 if (($devtype == 1) || ($devtype == 2) || ($devtype == 8)) # HT , HT+
 {
  $h{'10decalcification'}     = MAX_ReadingsVal($hash,"decalcification");
  $h{'11.decalcification'}    = $h{'10decalcification'};
  $h{'12.boostDuration'}      = MAX_ReadingsVal($hash,"boostDuration");
  $h{'13.boostValveposition'} = MAX_ReadingsVal($hash,"boostValveposition");
  $h{'14.maxValveSetting'}    = MAX_ReadingsVal($hash,"maxValveSetting");
  $h{'15.valveOffset'}        = MAX_ReadingsVal($hash,"valveOffset");

  $h{'20'}                    = '#';
  $h{'33.windowOpenDuration'}  = MAX_ReadingsVal($hash,"windowOpenDuration");
  #$h{'34.windowOpenDuration'} = $h{'33windowOpenDuration'};
  $h{'39'}                    = '#';
 }

 foreach (sort keys %h) 
 { 
   if (defined($h{$_}))
   {
    if ($h{$_} eq '#')
    {
     push @lines,'##############################################';
     next;
    }
    my $r = substr($_,2,length($_)); # die Sortierung abschneiden
    if (substr($r,0,1) ne '.')
    {
     push @lines,'set '.$fname.' '.$r.' '.$h{$_};
    }
    else
    {
     push @lines,'setreading '.$fname.' '.substr($r,1,length($r)).' '.$h{$_};
    }
   }
 }

 $hash->{saveConfig} = 1;
 my @ar =  MAX_ParseWeekProfile($hash);
 delete $hash->{saveConfig};
 my @json;
 foreach (@ar) 
 {
  push @lines , $_ if ($_ && (substr($_,0,1) ne '"'));
  push @json  , $_ if ($_ && (substr($_,0,1) eq '"'));
 }

 my $json = '{'; $json .= join(',',@json); $json .= '}';

 push @lines , "setreading $name .wp_json ".$json;
 my $error = FileWrite($dir.$fname.'.max', @lines);

 if ($error)
 { Log3 $hash,2,"$name, configSave : $error"; }
 else
 { 
  if(exists($hash->{".updateTimestamp"})) # readingsBulkUpdate ist aktiv, wird von fhem.pl gesetzt/gelöscht
  { 
   readingsBulkUpdate($hash,'lastConfigSave',$dir.$fname.'.max');
   readingsBulkUpdate($hash,'.wp_json',$json);
  }
  else
  { readingsBeginUpdate($hash);
     readingsBulkUpdate($hash,'lastConfigSave',$dir.$fname.'.max');
     readingsBulkUpdate($hash,'.wp_json',$json);
    readingsEndUpdate($hash,1);
  }
 }

 return $error;
}

sub MAXX_Restore
{
 my $name   = shift;
 my $action = shift;
 my $fname  = shift;
 my $hash   = $defs{$name};
 $fname     = $name if (!$fname);
 my $dir    = AttrVal('global','logdir','./log/');
 $dir .='/' if ($dir  !~ m/\/$/);

 my ($error, @lines) = FileRead($dir.$fname.'.max');

 if ($error)
 {
  Log3 $hash,2,"$name, $action : $error";
  return $error;
 }

 if (@lines && $action)
 {
  readingsBeginUpdate($hash);
  foreach (@lines)
  {
   my ($cmd,$dname,$reading,$val,$val2) = split(' ',$_);
   next if ((!defined($cmd)) || (!defined($dname)) || (!defined($reading)) || (!defined($val)));
   $val .=' '.$val2 if($val2); 
   readingsBulkUpdate($hash,$reading,$val) if ($cmd eq 'setreading');
  }

  MAX_ParseWeekProfile($hash);
  readingsEndUpdate($hash,0);
 }
 
if (@lines && ($action eq 'restoreDevice'))
 {
  foreach (@lines)
  {
   my ($cmd,$dname,$reading,$val,$val2) = split(' ',$_);
   next if ((!defined($cmd)) || (!defined($dname)) || (!defined($reading)) || (!defined($val)));
   $val .=' '.$val2 if($val2);
   $error.= CommandSet(undef,$name.' '.$reading.' '.$val) if  ($cmd eq 'set');
  }
 }
 return $error;
}


#############################
sub MAX_ParseDateTime
{
  my ($byte1,$byte2,$byte3) = @_;
  my $day = $byte1 & 0x1F;
  my $month = (($byte1 & 0xE0) >> 4) | ($byte2 >> 7);
  my $year = $byte2 & 0x3F;
  my $time = ($byte3 & 0x3F);
  if($time%2){
    $time = int($time/2).":30";
  }else{
    $time = int($time/2).":00";
  }
  return { "day" => $day, "month" => $month, "year" => $year, "time" => $time, "str" => "$day.$month.$year $time" };
}

#############################
sub MAX_Parse
{
  my $hash = shift;
  my $msg  = shift;
  my ($MAX,$isToMe,$msgtype,$addr,@args) = split(",",$msg);

  # ToDo args undef
  # $isToMe is 1 if the message was direct at the device $hash, and 0
  # if we just snooped a message directed at a different device (by CUL_MAX).
  # MAX = Aufruf via CUL_MAx , MAX2 = zweiter Durchlauf aus MAX_Parse selbst nochmal

  Log3 $hash, 5, "MAX_Parse, $msg";

  return  if (($MAX ne 'MAX') && ($MAX ne 'MAX2'));

  my $sname;

  if(!exists($modules{MAX}{defptr}{$addr}))
  {
    if (($msgtype eq 'Ack') || ($addr eq '111111') || ($addr eq '222222'))
    {
     Log3 $hash,4, 'MAX_Parse, '.$msgtype.' from undefined device '.$addr.' - ignoring !';
     return $hash->{NAME};
    }

    my $devicetype = undef;
    $devicetype = $args[0] if($msgtype eq "define" and $args[0] ne "Cube");
    $devicetype = "ShutterContact"        if($msgtype eq "ShutterContactState");
    $devicetype = "PushButton"            if($msgtype eq "PushButtonState");
    #$devicetype = "WallMountedThermostat" if(grep /^$msgtype$/, ("WallThermostatConfig","WallThermostatState","WallThermostatControl","SetTemperature"));
    # ToDo : liegt hier mit SetTemperature das Problem das so viele Geräte falsch als WT erkannt werden ?
    $devicetype = "WallMountedThermostat" if(grep /^$msgtype$/, ("WallThermostatConfig","WallThermostatState","WallThermostatControl"));
    $devicetype = "HeatingThermostat"     if(grep /^$msgtype$/, ("HeatingThermostatConfig", "ThermostatState"));
    if($devicetype) 
    {
      my $ac = (IsDisabled('autocreate')) ? 'disabled' : 'enabled' ; 
      Log3 $hash, 3, "MAX_PARSE, got message $msgtype for undefined device $addr type $devicetype , autocreate is $ac";
      return $hash->{NAME} if ($ac eq 'disabled');
      return "UNDEFINED MAX_$addr MAX $devicetype $addr";
    } 
     else 
    {
      Log3 $hash, 3, "MAX_Parse, message for undefined device $addr and failed to guess devicetype from msg $msgtype - ignoring !";
      return $hash->{NAME};
    }
  } # bisher unbekanntes Device
  ################################################################

  my $shash = $modules{MAX}{defptr}{$addr};
  if (!defined($shash->{NAME}))
  {
   Log3 $hash, 1, 'MAX_Parse, ohne Namen msg: '.$msg;
   return $hash->{NAME};
  }
  else
  {
   $sname = $shash->{NAME};
  }

  #if $isToMe is true, then the message was directed at device $hash, thus we can also use it for sending
  if($isToMe) 
  {
    $shash->{IODev}   = $hash;
    #$shash->{backend} = $hash->{NAME}; # for user information , wozu soll das gut sein ???
  }

  my $skipDouble = AttrNum($sname,'skipDouble',0); # Pakete mit gleichem MSGCNT verwerfen, bsp WT/FK an alle seine HTs ?
  my $debug      = AttrNum($sname,'debug',0);
  my $iogrp      = AttrVal($hash->{NAME} , 'IOgrp' ,''); # hat CUL_MAX eine IO Gruppe ?
  my @ios        = split(',',$iogrp);

  if ($MAX eq 'MAX')
  {
   readingsBeginUpdate($shash);
   readingsBulkUpdate($shash,'.lastact',time());
   readingsBulkUpdate($shash,'Activity','alive') if (($hash->{TYPE} eq 'CUL_MAX') && InternalVal($sname,'.actCycle','0'));
  }

  if ($iogrp && $debug)
  {
    foreach (@ios)
    {
     readingsBulkUpdate($shash,$_.'_RSSI' , $shash->{helper}{io}{$_}{'rssi'}) if (defined($shash->{helper}{io}{$_}{'rssi'}));
    }
  }

  if($msgtype eq "define")
  {
    my $devicetype = $args[0];
    Log3 $hash, 2, "$sname changed type from $shash->{type} to $devicetype" if($shash->{type} ne $devicetype);
    $shash->{type} = $devicetype;
    readingsBulkUpdate($shash, "SerialNr", $args[1]) if (defined($args[1]));
    readingsBulkUpdate($shash, "groupid",  $args[2]) if (defined($args[2]) && !$isToMe);# ToDo prüfen, wird hier die groupid beim repairing platt gemacht ?
    $shash->{IODev} = $hash;
  } 
  elsif($msgtype eq "ThermostatState") 
  {
   if (($shash->{'.count'} < 0) && $skipDouble)
   {
    Log3 $shash,4,$shash->{NAME}.", message ".abs($shash->{'.count'})." already processed - skipping";
    readingsEndUpdate($shash, 1);
    return $shash->{NAME}; # vorzeitiger Abbruch
   }
   else
   {
    $shash->{'.count'} = ($shash->{'.count'} * -1 ) if ($shash->{'.count'}>0);

    my ($bits2,$valveposition,$desiredTemperature,$until1,$until2,$until3) = unpack("aCCCCC",pack("H*",$args[0]));
    $shash->{'.mode'}       = vec($bits2, 0, 2); #
    $shash->{'.testbit'}    = vec($bits2, 2, 1); #
    $shash->{'.dstsetting'} = vec($bits2, 3, 1); # is automatically switching to DST activated
    $shash->{'.gateway'}    = vec($bits2, 4, 1); # ??
    $shash->{'.panel'}      = vec($bits2, 5, 1); # 1 if the heating thermostat is locked for manually setting the temperature at the device
    $shash->{'.rferror'}    = vec($bits2, 6, 1); # communication with link partner - if device is not accessible over the air from the cube
    $shash->{'.battery'}    = vec($bits2, 7, 1); # 1 if battery is low

    my $untilStr = defined($until3) ? MAX_ParseDateTime($until1,$until2,$until3)->{str} : "";
    my $measuredTemperature = defined($until2) ? ((($until1 &0x01)<<8) + $until2)/10 : 0;
    # If the control mode is not "temporary", the cube sends the current (measured) temperature
    $measuredTemperature = "" if($shash->{'.mode'} == 2 || $measuredTemperature == 0);
    $untilStr = '' if($shash->{'.mode'} != 2);

    $shash->{'.desiredTemperature'} = ($desiredTemperature&0x7F)/2.0; #convert to degree celcius
    #my @a = split(' ',ReadingsVal($sname , 'lastcmd',''));
    #if (($a[0] eq 'set_desiredTemperature') && ($a[1] eq MAX_SerializeTemperature($shash->{'.desiredTemperature'})))
    #{
     #readingsBulkUpdate($shash, 'lastcmd', 'desiredTemperature '.MAX_SerializeTemperature($shash->{'.desiredTemperature'}));
    #}

    my $log_txt = $sname.", bat $shash->{'.battery'}, rferror $shash->{'.rferror'}, panel $shash->{'.panel'}, langateway $shash->{'.gateway'}, dstsetting $shash->{'.dstsetting'}, mode $shash->{'.mode'}, valveposition $valveposition, desiredTemperature ".$shash->{'.desiredTemperature'};
    $log_txt .= ", until $untilStr" if ($untilStr);
    $log_txt .= ", curTemp $measuredTemperature" if($measuredTemperature);
    Log3 $shash, 5, $log_txt;

    #Very seldomly, the HeatingThermostat sends us temperatures like 0.2 or 0.3 degree Celcius - ignore them
    $measuredTemperature = "" if($measuredTemperature ne "" and $measuredTemperature < 1);

    if($shash->{'.mode'} == 2) { $shash->{until} = "$untilStr"; } else { delete($shash->{until}); }


    #The formatting of desiredTemperature must match with in MAX_Set:$templist
    #Sometime we get an MAX_Parse MAX,1,ThermostatState,01090d,180000000000, where desiredTemperature is 0 - ignore it

    readingsBulkUpdate($shash, "temperature", MAX_SerializeTemperature($measuredTemperature)) if ($measuredTemperature ne "");
    if (!AttrVal($shash->{NAME},'externalSensor',''))
    {readingsBulkUpdate($shash, "deviation", sprintf("%.1f",($measuredTemperature-$shash->{'.desiredTemperature'}))) if ($shash->{'.desiredTemperature'} && $measuredTemperature);}
    else
    {
     my ($sensor,$t,$snotify) = split(':',AttrVal($shash->{NAME},'externalSensor','::'));
     $snotify = 0 if (!defined($snotify));
     my $ext = ReadingsNum($sensor,$t,0);
     readingsBulkUpdate($shash, "deviation", sprintf("%.1f",($ext-$shash->{'.desiredTemperature'}))) if ($shash->{'.desiredTemperature'} && $ext);
     readingsBulkUpdate($shash, "externalTemp", $ext) if ($ext && !$snotify);
    }

    if($shash->{type} =~ /HeatingThermostatPlus/ and $hash->{TYPE} eq "MAXLAN") 
    {
      readingsBulkUpdate($shash, "valveposition", int($valveposition*MAX_ReadingsVal($shash,"maxValveSetting")/100));
    } 
    else
    {
      readingsBulkUpdate($shash, "valveposition", $valveposition);
    }
   } # skip Double
  }
  elsif(grep /^$msgtype$/,  ("WallThermostatState", "WallThermostatControl" ))
  {
   if (($shash->{'.count'} < 0) && $skipDouble)
   {
    Log3 $shash,4,$shash->{NAME}.", message ".abs($shash->{'.count'})." already processed - skipping";
    readingsEndUpdate($shash, 1);
    return $shash->{NAME}; # vorzeitiger Abbruch
   }
   else
   {
    $shash->{'.count'} = ($shash->{'.count'} * -1 ) if ($shash->{'.count'} >0) ;

    my ($bits2,$displayActualTemperature,$desiredTemperatureRaw,$null1,$heaterTemperature,$null2,$temperature);

    if (!defined($args[0]) || (length($args[0])<4))
    {
      Log3 $hash, 2, "MAX_Parse, invalid $msgtype packet for addr $addr , args is to short" # greift bei $args[0] undefined !
    }
    elsif( length($args[0]) == 4 ) 
    {
      # This is the message that WallMountedThermostats send to paired HeatingThermostats
      ($desiredTemperatureRaw,$temperature) = unpack("CC",pack("H*",$args[0]));
    }
    elsif( length($args[0]) >= 6 and length($args[0]) <= 14) 
    { 
      # len=14: This is the message we get from the Cube over MAXLAN and which is probably send by WallMountedThermostats to the Cube
      # len=12: Payload of an Ack message, last field "temperature" is missing
      # len=10: Received by MAX_CUL as WallThermostatState
      # len=6 : Payload of an Ack message, last four fields (especially $heaterTemperature and $temperature) are missing
      ($bits2,$displayActualTemperature,$desiredTemperatureRaw,$null1,$heaterTemperature,$null2,$temperature) = unpack("aCCCCCC",pack("H*",$args[0]));
      # $heaterTemperature/10 is the temperature measured by a paired HeatingThermostat
      # we don't do anything with it here, because this value also appears as temperature in the HeatingThermostat's ThermostatState message
      $shash->{'.mode'}       = vec($bits2, 0, 2); #
      $shash->{'.testbit'}    = vec($bits2, 2, 1); #
      $shash->{'.dstsetting'} = vec($bits2, 3, 1); # is automatically switching to DST activated
      $shash->{'.gateway'}    = vec($bits2, 4, 1); # ??
      $shash->{'.panel'}      = vec($bits2, 5, 1); # 1 if the heating thermostat is locked for manually setting the temperature at the device
      $shash->{'.rferror'}    = vec($bits2, 6, 1); # communication with link partner - if device is not accessible over the air from the cube
      $shash->{'.battery'}    = vec($bits2, 7, 1);

      my $untilStr = '';
      if(defined($null2) and ($null1 != 0 or $null2 != 0)) 
      {
        $untilStr = MAX_ParseDateTime($null1,$heaterTemperature,$null2)->{str};
        $heaterTemperature = '';
        $shash->{until} = $untilStr;
      }
      else { delete($shash->{until}); }
     
     #if(!defined($heaterTemperature))
     #{ $heaterTemperature = ''; } 
     #else { $heaterTemperature =  sprintf("%.1f",$heaterTemperature/10);}

     my $log_txt= $sname.", bat ".$shash->{'.battery'}.", rferror ".$shash->{'.rferror'}.", panel ".$shash->{'.panel'}.", langateway ".$shash->{'.gateway'}.", dst ".$shash->{'.dstsetting'}.", mode ".$shash->{'.mode'}.", displayActualTemperature $displayActualTemperature";
     #$log_txt .= ", heaterTemperature $heaterTemperature" if ($heaterTemperature);
     $log_txt .= ", untilStr $untilStr" if ($untilStr);
     Log3 $hash, 5, $log_txt;

     readingsBulkUpdate($shash, "displayActualTemperature", ($displayActualTemperature) ? 1 : 0);
    } 
    else 
    {
      Log3 $hash, 2, "MAX_Parse, invalid $msgtype packet for addr $addr , args > 14 ?" # ToDo  greift bei $args[0] undefined !
    }

    $shash->{'.desiredTemperature'} = ($desiredTemperatureRaw &0x7F)/2.0; #convert to degree celcius # ToDo $desiredTemperatureRaw undefined , erledigt mit args[0] ?
    if(defined($temperature)) 
    {
      $temperature = ((($desiredTemperatureRaw &0x80)<<1) + $temperature)/10;	# auch Temperaturen über 25.5 °C werden angezeigt !
      Log3 $hash, 5, $shash->{NAME}.", desiredTemperature : $shash->{'.desiredTemperature'}, temperature : $temperature";
      readingsBulkUpdate($shash, "temperature", sprintf("%.1f",$temperature));
      readingsBulkUpdate($shash, "deviation",   sprintf("%.1f", ($temperature-$shash->{'.desiredTemperature'})));
    } 
    else 
    {
      Log3 $hash, 5, $shash->{NAME}.", desiredTemperature ".$shash->{'.desiredTemperature'};
      #.", temperature ".$heaterTemperature; ToDo : heaterTemperature
      #readingsBulkUpdate($shash, "temperature2", $heaterTemperature) if ($heaterTemperature);
    }

    # This formatting must match with in MAX_Set:$templist
    #readingsBulkUpdate($shash, "desiredTemperature", MAX_SerializeTemperature($shash->{'.desiredTemperature'}));
   } # skip Double
  }
  elsif($msgtype eq "ShutterContactState")
  {
    if (($shash->{'.count'} < 0) && $skipDouble)
    {
      Log3 $shash,4,$shash->{NAME}.", message ".abs($shash->{'.count'})." already processed - skipping";
      readingsEndUpdate($shash, 1);
      return $shash->{NAME}; # vorzeitiger Abbruch
    }
    else
    {
     $shash->{'.count'} = ($shash->{'.count'} * -1 ) if ($shash->{'.count'} >0) ;

     my $bits             = pack("H2",$args[0]);
     $shash->{'.isopen'}  = vec($bits,0,2) == 0 ? 0 : 1;
     my $unkbits          = vec($bits,2,4);
     $shash->{'.rferror'} = vec($bits,6,1);
     $shash->{'.battery'} = vec($bits,7,1);
     Log3 $hash, 5, $shash->{NAME}.", bat ".$shash->{'.battery'}.", rferror ".$shash->{'.rferror'}.", isopen ".$shash->{'.isopen'}.", unkbits $unkbits";
    }# skip Double
  }
  elsif($msgtype eq "PushButtonState") 
  {
    my ($bits2, $isopen) = unpack("aC",pack("H*",$args[0]));
    #The meaning of $bits2 is completly guessed based on similarity to other devices, TODO: confirm
    $shash->{'.gateway'} = vec($bits2, 4, 1); # Paired to a CUBE?
    $shash->{'.rferror'} = vec($bits2, 6, 1); # communication with link partner (1 if we did not sent an Ack)
    $shash->{'.battery'} = vec($bits2, 7, 1); # 1 if battery is low
    $shash->{'.isopen'}  = $isopen;
    Log3 $hash, 5, $shash->{NAME}.", bat $shash->{'.battery'}, rferror $shash->{'.rferror'}, onoff ".$shash->{'.isopen'}.", langateway ".$shash->{'.gateway'};
  } 
  elsif(grep /^$msgtype$/, ("HeatingThermostatConfig", "WallThermostatConfig")) # ToDo : wann kommt das ?
  {
    readingsBulkUpdate($shash, "ecoTemperature",     MAX_SerializeTemperature($args[0]));
    readingsBulkUpdate($shash, "comfortTemperature", MAX_SerializeTemperature($args[1]));
    readingsBulkUpdate($shash, "maximumTemperature", MAX_SerializeTemperature($args[2]));
    readingsBulkUpdate($shash, "minimumTemperature", MAX_SerializeTemperature($args[3]));
    readingsBulkUpdate($shash, ".weekProfile", $args[4]);
    #Log3 $shash,1,$msgtype.' : '.$args[4];
    readingsBulkUpdate($shash, 'lastcmd', $msgtype);

    if(@args > 5) 
    { #HeatingThermostat and WallThermostat with new firmware
      readingsBulkUpdate($shash, "boostValveposition",    $args[5]);
      readingsBulkUpdate($shash, "boostDuration",         $boost_durations{$args[6]});
      readingsBulkUpdate($shash, "measurementOffset",     MAX_SerializeTemperature($args[7]));
      readingsBulkUpdate($shash, "windowOpenTemperature", MAX_SerializeTemperature($args[8]));
    }
    if(@args > 9) 
    { #HeatingThermostat
      readingsBulkUpdate($shash, "windowOpenDuration", $args[9]);
      readingsBulkUpdate($shash, "maxValveSetting",    $args[10]);
      readingsBulkUpdate($shash, "valveOffset",        $args[11]);
      readingsBulkUpdate($shash, "decalcification",    "$decalcDays{$args[12]} $args[13]:00");
    }

    MAX_ParseWeekProfile($shash);
    MAX_saveConfig($shash->{NAME},'') if (AttrNum($shash->{NAME},'autosaveConfig',1));
  } 
  elsif($msgtype eq "Error") # ToDo : kommen die Errors nur von MAXLAN ? 
  {
    if(@args == 0) 
    {
      delete $shash->{ERROR} if(exists($shash->{ERROR}));
    } 
     else 
    {
      $shash->{ERROR} = join(",",@args);
      readingsBulkUpdate($shash, "error",$shash->{ERROR});
      Log3 $shash , 3 ,"msg Type error : ". $shash->{ERROR};
    }
  } 
  elsif($msgtype eq "AckWakeUp") 
  {
    my ($duration) = @args;
    #substract five seconds safety margin
    $shash->{wakeUpUntil} = gettimeofday() + $duration - 5;
    readingsBulkUpdate($shash, 'lastcmd','WakeUp');
  } 
  elsif($msgtype eq "AckConfigWeekProfile") 
  {
    my ($day, $part, $profile) = @args;

    my $curWeekProfile = MAX_ReadingsVal($shash, ".weekProfile");
    substr($curWeekProfile, $day*52+$part*2*2*7, length($profile)) = $profile;
    readingsBulkUpdate($shash, ".weekProfile", $curWeekProfile);
    readingsBulkUpdate($shash, 'lastcmd','ConfigWeekProfile');
    MAX_ParseWeekProfile($shash);
    MAX_saveConfig($shash->{NAME},'') if (AttrNum($shash->{NAME},'autosaveConfig',1));
    Log3 $shash, 5, "$shash->{NAME}, new weekProfile: " . MAX_ReadingsVal($shash, ".weekProfile");
  } 
  elsif(grep /^$msgtype$/, ("AckConfigValve", "AckConfigTemperatures", "AckSetDisplayActualTemperature" )) 
  {
    if($args[0] eq "windowOpenTemperature"
    || $args[0] eq "comfortTemperature"
    || $args[0] eq "ecoTemperature"
    || $args[0] eq "maximumTemperature"
    || $args[0] eq "minimumTemperature" ) 
    {
      Log3 $shash,5,$sname.', msgtype '.$msgtype.' Reading '.$args[0].' : '.$args[1];
      my $t = MAX_SerializeTemperature($args[1]);
      readingsBulkUpdate($shash, 'lastcmd',$args[0].' '.$t);
      readingsBulkUpdate($shash, $args[0], $t);
    } 
     else 
    {
      #displayActualTemperature, boostDuration, boostValveSetting, maxValve, decalcification, valveOffset
      Log3 $shash,5,$sname.', msgtype '.$msgtype.' Reading '.$args[0].' : '.$args[1];
      readingsBulkUpdate($shash, $args[0], $args[1]);
      readingsBulkUpdate($shash, 'lastcmd',$args[0].' '.$args[1]);
    }
   MAX_saveConfig($shash->{NAME},'') if (AttrNum($shash->{NAME},'autosaveConfig',1));
  } 
  elsif(grep /^$msgtype$/, ("AckSetGroupId", "AckRemoveGroupId" )) 
  {
    Log3 $shash,5,$sname.', msgtype '.$msgtype.' Reading groupid : '.$args[0];
    readingsBulkUpdate($shash, "groupid", $args[0]);
    readingsBulkUpdate($shash, 'lastcmd','groupid '.$args[0]);
  }
  elsif($msgtype eq "AckSetTemperature")
  {
    my $val; my @ar;
    Log3 $shash,5,$sname.', msgtype '.$msgtype.' : '.join(' ' ,@args);

    @ar = split(' ',$args[0]) if ($args[0]);
    if (!$ar[0])
    { $val =  'auto/boost'; }
    else
    {
      $val = MAX_SerializeTemperature($ar[0]); 
      shift @ar;
      $val .= ' '.join(' ',@ar) if(@ar); # bei until kommt mehr zurück
    }

    readingsBulkUpdate($shash, 'lastcmd','desiredTemperature '.$val);
  }
  elsif(grep /^$msgtype$/, ("AckAddLinkPartner", "AckRemoveLinkPartner" ))
  {
  ## AckLinkPartner
    Log3 $shash,5,$sname.', msgtype '.$msgtype.'  '.join(' ',@args);
    my @peers = split(',', ReadingsVal($sname,'peers',''));
    if ($args[0] eq 'associate')
    {
     push @peers, $args[1] if (!grep {/$args[1]/} @peers); # keine doppelten Namen
     @peers = sort @peers  if (@peers > 1);
    }
    else
    {
      my @ar = grep {$_ ne $args[1]} @peers;
      @peers = sort @ar;
      readingsDelete($sname,'peers') if (!@peers); # keiner mehr da
    }

    readingsBulkUpdate($shash, 'peers', join(',',@peers)) if (@peers);
    readingsBulkUpdate($shash, 'lastcmd',join(' ',@args));
    MAX_saveConfig($shash->{NAME},'') if (AttrNum($shash->{NAME},'autosaveConfig',1));
  }
  elsif($msgtype eq "Ack") 
  {
    # The payload of an Ack is a 2-digit hex number (being "01" for okey and "81" for "invalid command/argument"
    if($isToMe and (unpack("C",pack("H*",$args[0])) & 0x80)) 
    {
      my $device = $addr;
      $device = $modules{MAX}{defptr}{$device}{NAME} if(exists($modules{MAX}{defptr}{$device}));
      Log3 $hash, 1, "MAX_Parse, device $device answered with: Invalid command/argument ".$args[0];
      readingsBulkUpdate($shash, 'error','Invalid command/argument  '.$args[0]);
      readingsEndUpdate($hash,1);
      return $shash->{NAME};
    }

    # with unknown meaning plus the data of a State broadcast from the same device
    # For HeatingThermostats, it does not contain the last three "until" bytes (or measured temperature)

    # nochmal zurück zum Anfang ?
    if ($shash->{type} =~ /HeatingThermostat.*/ )
    {
      return MAX_Parse($hash, "MAX2,$isToMe,ThermostatState,$addr,". substr($args[0],2));
    } 
     elsif ($shash->{type} eq "WallMountedThermostat") 
    {
      return MAX_Parse($hash, "MAX2,$isToMe,WallThermostatState,$addr,". substr($args[0],2));
    } 
     elsif ($shash->{type} eq "ShutterContact") 
    {
      return MAX_Parse($hash, "MAX2,$isToMe,ShutterContactState,$addr,". substr($args[0],2));
    } 
     elsif ($shash->{type} eq "PushButton") 
    {
      return MAX_Parse($hash, "MAX2,$isToMe,PushButtonState,$addr,". substr($args[0],2));
    } 
     elsif ($shash->{type} eq "Cube") 
    {
      ; #Payload is always "00"
    } 
     else 
    {
      Log3 $hash, 2, "MAX_Parse, don't know how to interpret Ack payload from $addr for $shash->{type}";
    }
  }
  elsif(grep /^$msgtype$/,  ("SetTemperature")) 
  { # SetTemperature is send by WallThermostat e.g. when pressing the boost button
    my $bits = unpack("C",pack("H*",$args[0]));
    $shash->{'.mode'} = $bits >> 6;
    my $desiredTemperature = ($bits & 0x3F) /2.0; #convert to degree celcius
    #readingsBulkUpdate($shash, "mode", $ctrl_modes[$shash->{'.mode'}] );
    # This formatting must match with in MAX_Set:$templist
    #readingsBulkUpdate($shash, "desiredTemperature", 
    $shash->{'.desiredTemperature'} = MAX_SerializeTemperature($desiredTemperature);
    Log3 $hash, 5, $shash->{NAME}.", SetTemperature mode  $ctrl_modes[$shash->{'.mode'}], desiredTemperature ".$shash->{'.desiredTemperature'} ;
  } 
   else
  {
    Log3 $hash, 1, "MAX_Parse, unknown message $msgtype , device $addr";
    readingsBulkUpdate($shash, 'error','unknown message '.$msgtype);
    readingsEndUpdate($shash, 1);
    return $shash->{NAME};
  }

  # Build state READING
  my $state = "waiting for data";

  $shash->{'.desiredTemperature'} = MAX_SerializeTemperature($shash->{'.desiredTemperature'}) if($shash->{'.desiredTemperature'});
  my $c = '';
  $c = '&deg;C' if (exists($shash->{'.desiredTemperature'}) && (substr($shash->{'.desiredTemperature'},0,1) ne 'o')); # on/off
  #$c = '°C' if (defined($shash->{'.desiredTemperature'}) && substr($shash->{'.desiredTemperature'},0,1) ne 'o'); # on/off

  $state = $shash->{'.desiredTemperature'}.$c if (exists($shash->{'.desiredTemperature'}));
  $state = ($shash->{'.isopen'}) ? 'opened' : 'closed' if (exists($shash->{'.isopen'}));

  if ($shash->{devtype} > 5) 
  {
    delete $shash->{'.rferror'};
    delete $shash->{'.battery'};
    delete $shash->{'.gateway'};
  }

  if (IsDummy($shash->{NAME}))
  {
   $state .= " (auto)"                     if (exists($shash->{mode}) && (int($shash->{'.mode'}) == 0));
   $state .= " (manual)"                   if (exists($shash->{mode}) && (int($shash->{'.mode'}) == 1));
  }

  $state .= ' (boost)'                     if (exists($shash->{'.mode'})    && (int($shash->{'.mode'}) == 3));
  $state .= ' (until '.$shash->{until}.')' if (exists($shash->{'.mode'})    && (int($shash->{'.mode'}) == 2) && exists($shash->{until}));
  $state .= ' (battery low)'               if (exists($shash->{'.battery'}) && $shash->{'.battery'});
  $state .= ' (rf error)'                  if (exists($shash->{'.rferror'}) && $shash->{'.rferror'});
 
  readingsBulkUpdate($shash, 'state',        $state);

  if (exists($shash->{'.desiredTemperature'})
      && $c # weder on noch off
      && ($shash->{'.desiredTemperature'} != ReadingsNum($sname,'windowOpenTemperature',0))
      && AttrNum($sname,'windowOpenCheck',0))
  {
   readingsBulkUpdate($shash, 'windowOpen', '0');
  }

  readingsBulkUpdate($shash, 'desiredTemperature',$shash->{'.desiredTemperature'}) if (exists($shash->{'.desiredTemperature'}));
  readingsBulkUpdate($shash, 'RSSI',         $shash->{'.rssi'})                    if (exists($shash->{'.rssi'}));
  readingsBulkUpdate($shash, 'battery',      $shash->{'.battery'} ? "low" : "ok")  if (exists($shash->{'.battery'}));
  readingsBulkUpdate($shash, 'batteryState', $shash->{'.battery'} ? "low" : "ok")  if (exists($shash->{'.battery'})); # Forum #87575
  readingsBulkUpdate($shash, 'rferror',      $shash->{'.rferror'})                 if (exists($shash->{'.rferror'}));
  readingsBulkUpdate($shash, 'gateway',      $shash->{'.gateway'})                 if (exists($shash->{'.gateway'}));
  readingsBulkUpdate($shash, 'mode',         $ctrl_modes[$shash->{'.mode'}] )      if (exists($shash->{'.mode'}));
  #readingsBulkUpdate($shash, 'onoff',        $shash->{'.isopen'} ? "opened" : "closed" ) if (exists($shash->{'.isopen'}));
  # ToDo open /close mag der MaxScanner gar nicht

  if (exists($shash->{'.isopen'}))
  {
   readingsBulkUpdate($shash, 'onoff', $shash->{'.isopen'} ? "1" : "0" );
   if ((AttrNum($sname,'windowOpenCheck',1)) && ($shash->{devtype} == 4))
   {
    if (!$shash->{'.isopen'})
    {
     readingsBulkUpdate($shash, 'windowOpen', '0');
     $shash->{'.timer'} = 300;
    }
    else
    {
     $shash->{'.timer'} = 60; 
     RemoveInternalTimer($shash);
     InternalTimer(gettimeofday()+1, "MAX_Timer", $shash, 0);
    }
   }
  }

  readingsBulkUpdate($shash, 'panel',        $shash->{'.panel'}   ? "locked" : "unlocked") if (exists($shash->{'.panel'}));

  if ($shash->{'.sendToName'} && ($shash->{'.sendToAddr'} ne '-1'))
  {
   my $val = ReadingsNum($sname,'sendTo_'.$shash->{'.sendToName'},0);
   $val ++;
   readingsBulkUpdate($shash, 'sendTo_'.$shash->{'.sendToName'},$val) if (AttrNum($sname,'debug',0));

   my @peers = split(',',ReadingsVal($sname,'peerList',''));
   push @peers, $shash->{'.sendToName'} if (!grep {/$shash->{'.sendToName'}/} @peers); # keine doppelten Namen
   @peers = sort @peers if (@peers > 1);
   readingsBulkUpdate($shash,'peerList', join(',',@peers)) if (@peers);

   @peers = split(',',ReadingsVal($sname,'peerIDs',''));
   push @peers, $shash->{'.sendToAddr'} if (!grep {/$shash->{'.sendToAddr'}/} @peers); # keine doppelten IDs
   @peers = sort @peers if (@peers > 1);
   readingsBulkUpdate($shash,'peerIDs', join(',',@peers)) if (@peers);
  }

 readingsEndUpdate($shash, 1);

 delete $shash->{'.rferror'};
 delete $shash->{'.battery'};
 delete $shash->{'.mode'};
 delete $shash->{'.gateway'};
 delete $shash->{'.isopen'};
 delete $shash->{'.rssi'};
 delete $shash->{'.desiredTemperature'};
 delete $shash->{'.panel'};
 delete $shash->{'.dstsetting'};

 return $shash->{NAME};
}
############################
#sub MAX_IncVal # ToDo : umbennen !
#{
 #my $hash = shift;
 #my $name = $hash->{NAME};
 #my $val = ReadingsNum($name,'sendTo_'.$hash->{'.sendToName'},0);
 #$val ++;
 #return $val;
#}

#############################
sub MAX_DbLog_splitFn
{
  my $event = shift;
  my $name  = shift;
  my ($reading, $value, $unit) = '';

  my @parts = split(/ /,$event);
  $reading = shift @parts;
  $reading =~ tr/://d;
  $value = $parts[0];
  $value = $parts[1]  if (defined($value) && (lc($value) =~ m/auto/));

  if (!AttrNum($name,'DbLog_log_onoff',0))
  {
   $value = '4.5'  if ( $value eq 'off' );
   $value = '30.5' if ( $value eq 'on' );
  }

  $unit = '\xB0C' if ( lc($reading) =~ m/temp/ );
  $unit = '%'     if ( lc($reading) =~ m/valve/ );
  return ($reading, $value, $unit);
}

sub MAX_RenameFn
{
  my $new = shift;
  my $old = shift;
  my $hash;

  for (devspec2array('TYPE=MAX'))
  {
    $hash = $defs{$_};
    next if(!$hash);
    if (exists($hash->{READINGS}{peerList}))
    {
     $hash->{READINGS}{peerList}{VAL} =~ s/$old/$new/;
    }
  }
 return;
}


sub MAX_Notify
{
  # $hash is my hash, $dev_hash is the hash of the changed device
  my $hash     = shift;
  my $dev_hash = shift;
  my $name = $hash->{NAME};
  my ($sd,$sr,$sn,$sm) = split(':',AttrVal($name,'externalSensor','::'));

  return  if ($dev_hash->{NAME} ne $sd);

  my $events = deviceEvents($dev_hash,0);
  my $reading; my $val; my $ret;

  foreach ( @{$events} )
  {
   Log3 $hash,5,$name.', NOTIFY EVENT -> Dev : '.$dev_hash->{NAME}.' | Event : '.$_;
   ($reading,$val) = split(': ',$_);
   $reading =~ s/ //g;
   if (!defined($val) && defined($reading)) # das muss state sein
   {
    $val     = $reading;
    $reading = 'state';
   }
   last if ($reading eq $sr);
  }
  return if (!defined($val) || ($reading ne $sr)); # der Event war nicht dabei

  if (($hash->{devtype} < 6) || ($hash->{devtype} == 8))
  {
   return if (!exists($hash->{READINGS}{desiredTemperature}{VAL}));
   my $dt = MAX_ParseTemperature($hash->{READINGS}{desiredTemperature}{VAL});

   Log3 $hash,5,$name.', updating externalTemp with '.$val;
   setReadingsVal($hash,'externalTemp',$val,TimeNow());
   $ret = CommandSet(undef,$hash->{IODev}{NAME}." fakeWT $name $dt $val") if ($sn);
  }
  elsif ($hash->{devtype} == 6)
  {
    Log3 $hash,5,"$name, $reading - $val";
    return if (($val !~ m/$sn/) && ($val !~ m/$sm/));
    Log3 $hash,4,"$name, got external open/close trigger -> $sd:$sr:$val";
    $ret = CommandSet(undef,$name.' open q')  if ($val =~ m/$sn/);
    $ret = CommandSet(undef,$name.' close q') if ($val =~ m/$sm/);
  }
  elsif ($hash->{devtype} == 7)
  {
   setReadingsVal($hash,'temperature',sprintf("%.1f",$val),TimeNow());
  }

  Log3 $hash,3,"$name, NotifyFN : $ret" if ($ret);
  return;
}

sub MAX_FileList
{
  my $dir  = shift;
  my $file = shift;
  my @ret;
  my $found = (!$file) ? 1 : 0;

  if (configDBUsed())
  {
   my @files = split(/\n/, _cfgDB_Filelist('notitle'));
   foreach (@files) 
   {
    next if ( $_ !~ m/^$dir/ );
        $_ =~ s/$dir//;
    $_ =~ s/\.max//;
    $found = 1 if ($_ eq $file);
    push @ret, $_ if ($_);
   }
  }
  else
  {
   return 0 if(!opendir(DH,$dir));
   while(readdir(DH))
   {
    next if ( $_ !~ m,\.max$,);
    $_ =~ s/\.max//;
    $found = 1 if ($_ eq $file);
    push(@ret, $_) if ($_) ;
   }
  closedir(DH);
  }
  return @ret if ($found);
  return 0;
}

sub MAX_BackupedDevs
{
  my $name = shift;
  my $dir = AttrVal('global','logdir','./log/');
  $dir .='/' if ($dir  !~ m/\/$/);
  my $files = '';
  my @list = MAX_FileList($dir,$name);
  if (!$list[0])
  {
   $name = '&nbsp;'; # ist leer wenn der eigene Name nicht drin ist
   @list = MAX_FileList($dir,'');
  }
  my @ar = grep {$_ ne $name } @list; # den eigenen Namen aus der Liste werfen
  @list = sort @ar;
  unshift @list,$name; # und wieder ganz vorne anstellen
  $files = join(',',@list);

  return $files;
}

sub MAX_today
{
  my (undef,undef,undef,$d,$m,$y) = localtime(gettimeofday());
  $m++; $y+=1900;
  return sprintf('%02d.%02d.%04d', $d,$m,$y);
}

1;

=pod
=item device
=item summary controls an MAX! device
=item summary_DE Steuerung eines MAX! Geräts
=begin html

<a name="MAX"></a>
<h3>MAX</h3>
<ul>
  Devices from the eQ-3 MAX! group.<br>
  When heating thermostats show a temperature of zero degrees, they didn't yet send any data to the cube. You can
  force the device to send data to the cube by physically setting a temperature directly at the device (not through fhem).
  <br><br>
  <a name="MAXdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; MAX &lt;type&gt; &lt;addr&gt;</code>
    <br><br>

    Define an MAX device of type &lt;type&gt; and rf address &lt;addr&gt.
    The &lt;type&gt; is one of HeatingThermostat, HeatingThermostatPlus, WallMountedThermostat, ShutterContact, PushButton, virtualShutterContact.
    The &lt;addr&gt; is a 6 digit hex number.
    You should never need to specify this by yourself, the <a href="#autocreate">autocreate</a> module will do it for you.<br>
    Exception : virtualShutterContact<br>
    It's advisable to set event-on-change-reading, like
    <code>attr MAX_123456 event-on-change-reading .*</code>
    because the polling mechanism will otherwise create events every 10 seconds.<br>

    Example:
    <ul>
      <code>define switch1 MAX PushButton ffc545</code><br>
    </ul>
  </ul>
  <br>

  <a name="MAXset"></a>
  <b>Set</b>
  <ul>
  <a name=""></a><li>deviceRename &lt;value&gt; <br>
   rename of the device and its logfile
  </li>
    <a name=""></a><li>desiredTemperature auto [&lt;temperature&gt;]<br>
        For devices of type HeatingThermostat only. If &lt;temperature&gt; is omitted,
        the current temperature according to the week profile is used. If &lt;temperature&gt; is provided,
        it is used until the next switch point of the week porfile. It maybe one of
        <ul>
          <li>degree celcius between 4.5 and 30.5 in 0.5 degree steps</li>
          <li>"on" or "off" set the thermostat to full or no heating, respectively</li>
          <li>"eco" or "comfort" using the eco/comfort temperature set on the device (just as the right-most physical button on the device itself does)</li>
        </ul></li>
    <a name=""></a><li>desiredTemperature [manual] &lt;value&gt; [until &lt;date&gt;]<br>
        For devices of type HeatingThermostat only. &lt;value&gt; maybe one of
        <ul>
          <li>degree celcius between 4.5 and 30.5 in 0.5 degree steps</li>
          <li>"on" or "off" set the thermostat to full or no heating, respectively</li>
          <li>"eco" or "comfort" using the eco/comfort temperature set on the device (just as the right-most physical button on the device itself does)</li>
        </ul>
        The optional "until" clause, with &lt;data&gt; in format "dd.mm.yyyy HH:MM" (minutes may only be "30" or "00"!),
        sets the temperature until that date/time. Make sure that the cube/device has a correct system time.
        If the keepAuto attribute is 1 and the device is currently in auto mode, 'desiredTemperature &lt;value&gt;'
        behaves as 'desiredTemperature auto &lt;value&gt;'. If the 'manual' keyword is used, the keepAuto attribute is ignored
        and the device goes into manual mode.</li>
    <a name=""></a><li>desiredTemperature boost<br>
      For devices of type HeatingThermostat only.
      Activates the boost mode, where for boostDuration minutes the valve is opened up boostValveposition percent.</li>
    <a name=""></a><li>groupid &lt;id&gt;<br>
      For devices of type HeatingThermostat only.
      Writes the given group id the device's memory. To sync all devices in one room, set them to the same groupid greater than zero.</li>
    <a name=""></a><li>ecoTemperature &lt;value&gt;<br>
      For devices of type HeatingThermostat only. Writes the given eco temperature to the device's memory. It can be activated by pressing the rightmost physical button on the device.</li>
    <a name=""></a><li>comfortTemperature &lt;value&gt;<br>
      For devices of type HeatingThermostat only. Writes the given comfort temperature to the device's memory. It can be activated by pressing the rightmost physical button on the device.</li>
    <a name=""></a><li>measurementOffset &lt;value&gt;<br>
      For devices of type HeatingThermostat only. Writes the given temperature offset to the device's memory. If the internal temperature sensor is not well calibrated, it may produce a systematic error. Using measurementOffset, this error can be compensated. The reading temperature is equal to the measured temperature at sensor + measurementOffset. Usually, the internally measured temperature is a bit higher than the overall room temperature (due to closeness to the heater), so one uses a small negative offset. Must be between -3.5 and 3.5 degree celsius.</li>
    <a name=""></a><li>minimumTemperature &lt;value&gt;<br>
      For devices of type HeatingThermostat only. Writes the given minimum temperature to the device's memory. It confines the temperature that can be manually set on the device.</li>
    <a name=""></a><li>maximumTemperature &lt;value&gt;<br>
            For devices of type HeatingThermostat only. Writes the given maximum temperature to the device's memory. It confines the temperature that can be manually set on the device.</li>
    <a name=""></a><li>windowOpenTemperature &lt;value&gt;<br>
            For devices of type HeatingThermostat only. Writes the given window open temperature to the device's memory. That is the temperature the heater will temporarily set if an open window is detected. Setting it to 4.5 degree or "off" will turn off reacting on open windows.</li>
    <a name=""></a><li>windowOpenDuration &lt;value&gt;<br>
            For devices of type HeatingThermostat only. Writes the given window open duration to the device's memory. That is the duration the heater will temporarily set the window open temperature if an open window is detected by a rapid temperature decrease. (Not used if open window is detected by ShutterControl. Must be between 0 and 60 minutes in multiples of 5.</li>
    <a name=""></a><li>decalcification &lt;value&gt;<br>
        For devices of type HeatingThermostat only. Writes the given decalcification time to the device's memory. Value must be of format "Sat 12:00" with minutes being "00". Once per week during that time, the HeatingThermostat will open the valves shortly for decalcification.</li>
    <a name=""></a><li>boostDuration &lt;value&gt;<br>
        For devices of type HeatingThermostat only. Writes the given boost duration to the device's memory. Value must be one of 5, 10, 15, 20, 25, 30, 60. It is the duration of the boost function in minutes.</li>
    <a name=""></a><li>boostValveposition &lt;value&gt;<br>
        For devices of type HeatingThermostat only. Writes the given boost valveposition to the device's memory. It is the valve position in percent during the boost function.</li>
    <a name=""></a><li>maxValveSetting &lt;value&gt;<br>
        For devices of type HeatingThermostat only. Writes the given maximum valveposition to the device's memory. The heating thermostat will not open the valve more than this value (in percent).</li>
    <a name=""></a><li>valveOffset &lt;value&gt;<br>
        For devices of type HeatingThermostat only. Writes the given valve offset to the device's memory. The heating thermostat will add this to all computed valvepositions during control.</li>
    <a name=""></a><li>factoryReset<br>
        Resets the device to factory values. It has to be paired again afterwards.<br>
        ATTENTION: When using this on a ShutterContact using the MAXLAN backend, the ShutterContact has to be triggered once manually to complete
        the factoryReset.</li>
    <a name=""></a><li>associate &lt;value&gt;<br>
        Associated one device to another. &lt;value&gt; can be the name of MAX device or its 6-digit hex address.<br>
        Associating a ShutterContact to a {Heating,WallMounted}Thermostat makes it send message to that device to automatically lower temperature to windowOpenTemperature while the shutter is opened. The thermostat must be associated to the ShutterContact, too, to accept those messages.
        <b>!Attention: After sending this associate command to the ShutterContact, you have to press the button on the ShutterContact to wake it up and accept the command. See the log for a message regarding this!</b>
        Associating HeatingThermostat and WallMountedThermostat makes them sync their desiredTemperature and uses the measured temperature of the
 WallMountedThermostat for control.</li>
    <a name=""></a><li>deassociate &lt;value&gt;<br>
        Removes the association set by associate.</li>
    <a name=""></a><li>weekProfile [&lt;day&gt; &lt;temp1&gt;,&lt;until1&gt;,&lt;temp2&gt;,&lt;until2&gt;] [&lt;day&gt; &lt;temp1&gt;,&lt;until1&gt;,&lt;temp2&gt;,&lt;until2&gt;] ...<br>
      Allows setting the week profile. For devices of type HeatingThermostat or WallMountedThermostat only. Example:<br>
      <code>set MAX_12345 weekProfile Fri 24.5,6:00,12,15:00,5 Sat 7,4:30,19,12:55,6</code><br>
      sets the profile <br>
      <code>Friday: 24.5 &deg;C for 0:00 - 6:00, 12 &deg;C for 6:00 - 15:00, 5 &deg;C for 15:00 - 0:00<br>
      Saturday: 7 &deg;C for 0:00 - 4:30, 19 &deg;C for 4:30 - 12:55, 6 &deg;C for 12:55 - 0:00</code><br>
      while keeping the old profile for all other days.
    </li>
    <a name=""></a><li>saveConfig &lt;name&gt;<br>

    </li>

    <a name=""></a><li>restoreReadings &lt;name of saved config&gt;<br>

    </li>

    <a name=""></a><li>restoreDevice &lt;name of saved config&gt;<br>

    </li>

    <a name=""></a><li>exportWeekprofile &lt;name od weekprofile device&gt;<br>

    </li>

  </ul>
  <br>

  <a name="MAXget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="MAXattr"></a>
  <b>Attributes</b>
  <ul>
    <a name="actCycle"></a><li>actCycle &lt;hh:mm&gt; default none (only with CUL_MAX)<br>
    Provides life detection for the device. [hhh: mm] sets the maximum time without a message from this device.<br>
    If no messages are received within this time, the reading activity is set to dead.<br>
    If the device sends again, the reading is reset to alive.<br>
    <b>Important</b> : does not make sense with the ECO Pushbutton,<br>
    as it is the only member of the MAX! family that does not send cyclical status messages !</li><br>
    <a name="CULdev"></a><li>CULdev &lt;name&gt; default none (only with CUL_MAX)<br>
    send device when the CUL_MAX device is using a IOgrp (Multi IO)</li><br>
    <a name="dummy"></a><li>dummy (0|1) default 0<br>sets device to a read-only device</li><br>
    <a name="debug"></a><li>debug (0|1) default 0<br>creates extra readings (only with CUL_MAX)</li><br>
    <a name="dTempCheck"></a><li>dTempCheck (0|1) default 0<br>
    monitors every 5 minutes whether the Reading desiredTemperature corresponds to the target temperature in the current weekprofile.<br>
    The result is a deviation in Reading dTempCheck, i.e. 0 = no deviation</li><br>
    <a name="externalSensor"></a><li>externalSensor &lt;device:reading&gt; default none<br>
    If there is no wall thermostat in a room but the room temperature is also recorded with an external sensor in FHEM (e.g. LaCrosse)<br>
    the current temperature value can be used to calculate the reading deviation instead of the own reading temperature</li><br>
    <a name="IODev"></a><li>IODev &lt;name&gt;<br>MAXLAN or CUL_MAX device name</li><br>
    <a name="keepAuto"></a><li>keepAuto (0|1) default 0<br>If set to 1, it will stay in the auto mode when you set a desiredTemperature while the auto (=weekly program) mode is active.</li><br>
    <a name="scanTemp"></a><li>scanTemp (0|1) default 0<br>used by MaxScanner</li><br>
    <a name="skipDouble"></a><li>skipDouble (0|1) default 0 (only with CUL_MAX)<br></li>
  </ul>
  <br>

  <a name="MAXevents"></a>
  <b>Generated events:</b>
  <ul>
    <li>desiredTemperature<br>Only for HeatingThermostat and WallMountedThermostat</li>
    <li>valveposition<br>Only for HeatingThermostat</li>
    <li>battery</li>
    <li>batteryState</li>
    <li>temperature<br>The measured temperature (= measured temperature at sensor + measurementOffset), only for HeatingThermostat and WallMountedThermostat</li>
  </ul>
</ul>

=end html

=begin html_DE

<a name="MAX"></a>
<h3>MAX</h3>
<ul>
  Verarbeitet MAX! Ger&auml;te, die von der eQ-3 MAX! Gruppe hergestellt werden.<br>
  Falls Heizk&ouml;rperthermostate eine Temperatur von Null Grad zeigen, wurde von ihnen
  noch nie Daten an den MAX Cube gesendet. In diesem Fall kann das Senden von Daten an
  den Cube durch Einstellen einer Temeratur direkt am Ger&auml;t (nicht &uuml;ber fhem)
  erzwungen werden.
  <br><br>
  <a name="MAXdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; MAX &lt;type&gt; &lt;addr&gt;</code>
    <br><br>

    Erstellt ein MAX Ger&auml;t des Typs &lt;type&gt; und der RF Adresse &lt;addr&gt;.
    Als &lt;type&gt; kann entweder <code>HeatingThermostat</code> (Heizk&ouml;rperthermostat),
    <code>HeatingThermostatPlus</code> (Heizk&ouml;rperthermostat Plus),
    <code>WallMountedThermostat</code> (Wandthermostat), <code>ShutterContact</code> (Fensterkontakt),
    <code>PushButton</code> (Eco-Taster) oder <code>virtualShutterContact</code> (virtueller Fensterkontakt) gew&auml;hlt werden.
    Die Adresse &lt;addr&gt; ist eine 6-stellige hexadezimale Zahl.
    Da <a href="#autocreate">autocreate</a> diese vergibt, sollte diese eigentlich nie h&auml;ndisch gew&auml;hlt
    werden m&uuml;ssen. Ausnahme : virtueller Fensterkontakt<br>
    Es wird dringend  empfohlen das Atribut event-on-change-reading zu setzen, z.B.
    <code>attr MAX_123456 event-on-change-reading .*</code> da ansonsten der "Polling" Mechanismus
    alle 10 s ein Ereignis erzeugt.<br>

    Beispiel:
    <ul>
      <code>define switch1 MAX PushButton ffc545</code><br>
    </ul>
  </ul>
  <br>

  <a name="MAXset"></a>
  <b>Set</b>
  <ul>
    <a name="associate"></a><li>associate &lt;value&gt;<br>
      Verbindet ein Ger&auml;t mit einem anderen. &lt;value&gt; kann entweder der Name eines MAX Ger&auml;tes oder
      seine 6-stellige hexadezimale Adresse sein.<br>
      Wenn ein Fensterkontakt mit einem HT/WT verbunden wird, sendet der Fensterkontakt automatisch die <code>windowOpen</code> Information wenn der Kontakt
      ge&ouml;ffnet ist. Das Thermostat muss ebenfalls mit dem Fensterkontakt verbunden werden, um diese Nachricht zu verarbeiten.
      <b>Achtung: Nach dem Senden der Botschaft zum Verbinden an den Fensterkontakt muss der Knopf am Fensterkontakt gedr&uuml;ckt werden um den Fensterkonakt aufzuwecken
      und den Befehl zu verarbeiten. Details &uuml;ber das erfolgreiche Verbinden finden sich in der Logdatei!</b>
      Das Verbinden eines Heizk&ouml;rperthermostates und eines Wandthermostates synchronisiert deren
      <code>desiredTemperature</code> und verwendet die am Wandthermostat gemessene Temperatur f&uuml;r die Regelung.</li>

    <a name="comfortTemperature"></a><li>comfortTemperature &lt;value&gt;<br>
      Nur f&uuml;r HT/WT. Schreibt die angegebene <code>comfort</code> Temperatur in den Speicher des Ger&auml;tes.<br>
      Diese kann durch dr&uuml;cken der Taste Halbmond/Stern am Ger&auml;t aktiviert werden.</li>

    <a name="deassociate"></a><li>deassociate &lt;value&gt;<br>
      L&ouml;st die Verbindung, die mit <code>associate</code> gemacht wurde, wieder auf.</li>

    <a name="desiredTemperature"></a><li>desiredTemperature &lt;value&gt; [until &lt;date&gt;]<br>
        Nur f&uuml;r HT/WT &lt;value&gt; kann einer aus folgenden Werten sein
        <ul>
          <li>Grad Celsius zwischen 4,5 und 30,5 Grad Celisus in 0,5 Grad Schritten</li>
          <li>"on" (30.5) oder "off" (4.5) versetzt den Thermostat in volle Heizleistung bzw. schaltet ihn ab</li>
          <li>"eco" oder "comfort" mit der eco/comfort Temperatur, die direkt am Ger&auml;t
              eingestellt wurde (&auml;nhlich wie die Halbmond/Stern Taste am Ger&auml;t selbst)</li>
          <li>"auto &lt;temperature&gt;". Damit wird das am Thermostat eingestellte Wochenprogramm
              abgearbeitet. Wenn optional die Temperatur &lt;temperature&gt; angegeben wird, wird diese
              bis zum n&auml;sten Schaltzeitpunkt des Wochenprogramms als <code>desiredTemperature</code> gesetzt.</li>
          <li>"boost" aktiviert den Boost Modus, wobei f&uuml;r <code>boostDuration</code> Minuten
              das Ventil <code>boostValveposition</code> Prozent ge&ouml;ffnet wird.</li>
        </ul>
        Alle Werte au&szlig;er "auto" k&ouml;nnen zus&auml;zlich den Wert "until" erhalten,
        wobei &lt;date&gt; in folgendem Format sein mu&szlig;: "TT.MM.JJJJ SS:MM"
        (Minuten nur 30 bzw. 00 !), um kurzzeitige eine andere Temperatur bis zu diesem Datum und dieser
        Zeit einzustellen. Wichtig : der Zeitpunkt muß in der Zukunft liegen !<br>
	Wenn dd.mm.yyyy dem heutigen Tag entspricht kann statdessen auch das Schl&uml;sselwort today verwendet werden.
	Bitte sicherstellen, dass der Cube bzw. das Ger&auml;t die korrekte Systemzeit hat</li>

      <a name="deviceRename"></a><li>deviceRename &lt;value&gt; <br>
	Benennt das Device um, inklusive dem durch autocreate erzeugtem Logfile</li>

     <a name="ecoTemperature"></a><li>ecoTemperature &lt;value&gt;<br>
      Nur f&uuml;r HT/WT. Schreibt die angegebene <code>eco</code> Temperatur in den Speicher
      des Ger&auml;tes. Diese kann durch Dr&uuml;cken der Halbmond/Stern Taste am Ger&auml;t aktiviert werden.</li>

    <a name="export_Weekprofile"></a><li>export_Weekprofile [device weekprofile name]</li>

    <a name="factoryReset"></a><li>factoryReset<br>
      Setzt das Ger&auml;t auf die Werkseinstellungen zur&uuml;ck. Das Ger&auml;t muss anschlie&szlig;end neu angelernt werden.<br>
      ACHTUNG: Wenn dies in Kombination mit einem Fensterkontakt und dem MAXLAN Modul
      verwendet wird, muss der Fensterkontakt einmal manuell ausgel&ouml;st werden, damit das Zur&uuml;cksetzen auf Werkseinstellungen beendet werden kann.</li>


    <a name="groupid"></a><li>groupid &lt;id&gt;<br>
      Nur f&uuml;r Heizk&ouml;rperthermostate.
      Schreibt die angegebene Gruppen ID in den Speicher des Ger&auml;tes.
      Um alle Ger&auml;te in einem Raum zu synchronisieren, k&ouml;nnen diese derselben Gruppen ID
      zugeordnet werden, diese mu&szlig; gr&ouml;&szlig;er Null sein.</li>

    <a name="measurementOffset"></a><li>measurementOffset &lt;value&gt;<br>
      Nur f&uuml;r Heizk&ouml;rperthermostate. Schreibt die angegebene <code>offset</code> Temperatur in den Speicher
      des Ger&auml;tes. Wenn der interne Temperatursensor nicht korrekt kalibriert ist, kann dieses einen
      systematischen Fehler erzeugen. Mit dem Wert <code>measurementOffset</code>, kann dieser Fehler
      kompensiert werden. Die ausgelese Temperatur ist gleich der gemessenen
      Temperatur + <code>measurementOffset</code>. Normalerweise ist die intern gemessene Temperatur h&ouml;her
      als die Raumtemperatur, da der Sensor n&auml;her am Heizk&ouml;rper ist und man verwendet einen
      kleinen negativen Offset, der zwischen -3,5 und 3,5 Kelvin sein mu&szlig;.</li>
    <a name="minimumTemperature"></a><li>minimumTemperature &lt;value&gt;<br>
      Nur f&uuml;r Heizk&ouml;rperthermostate. Schreibt die angegemene <code>minimum</code> Temperatur in der Speicher
      des Ger&auml;tes. Diese begrenzt die Temperatur, die am Ger&auml;t manuell eingestellt werden kann.</li>
    <a name="maximumTemperature"></a><li>maximumTemperature &lt;value&gt;<br>
      Nur f&uuml;r Heizk&ouml;rperthermostate. Schreibt die angegemene <code>maximum</code> Temperatur in der Speicher
      des Ger&auml;tes. Diese begrenzt die Temperatur, die am Ger&auml;t manuell eingestellt werden kann.</li>
    <a name="windowOpenTemperature"></a><li>windowOpenTemperature &lt;value&gt;<br>
      Nur f&uuml;r Heizk&ouml;rperthermostate. Schreibt die angegemene <code>window open</code> Temperatur in den Speicher
      des Ger&auml;tes. Das ist die Tempereratur, die an der Heizung kurzfristig eingestellt wird, wenn ein
      ge&ouml;ffnetes Fenster erkannt wird. Der Wert 4,5 Grad bzw. "off" schaltet die Reaktion auf
      ein offenes Fenster aus.</li>
    <a name="windowOpenDuration"></a><li>windowOpenDuration &lt;value&gt;<br>
      Nur f&uuml;r Heizk&ouml;rperthermostate. Schreibt die angegebene <code>window</code> open Dauer in den Speicher
      des Ger&auml;tes. Dies ist die Dauer, w&auml;hrend der die Heizung kurzfristig die window open Temperatur
      einstellt, wenn ein offenes Fenster durch einen schnellen Temperatursturz erkannt wird.
      (Wird nicht verwendet, wenn das offene Fenster von <code>ShutterControl</code> erkannt wird.)
      Parameter muss zwischen Null und 60 Minuten sein als Vielfaches von 5.</li>
    <a name="decalcification"></a><li>decalcification &lt;value&gt;<br>
      Nur f&uuml;r Heizk&ouml;rperthermostate. Schreibt die angegebene Zeit f&uuml;r <code>decalcification</code>
      in den Speicher des Ger&auml;tes. Parameter muss im Format "Sat 12:00" sein, wobei die Minuten
      "00" sein m&uuml;ssen. Zu dieser angegebenen Zeit wird das Heizk&ouml;rperthermostat das Ventil
      kurz ganz &ouml;ffnen, um vor Schwerg&auml;ngigkeit durch Kalk zu sch&uuml;tzen.</li>
    <a name="boostDuration"></a><li>boostDuration &lt;value&gt;<br>
      Nur f&uuml;r Heizk&ouml;rperthermostate. Schreibt die angegebene Boost Dauer in den Speicher
      des Ger&auml;tes. Der gew&auml;hlte Parameter muss einer aus 5, 10, 15, 20, 25, 30 oder 60 sein
      und gibt die Dauer der Boost-Funktion in Minuten an.</li>
    <a name="boostValveposition"></a><li>boostValveposition &lt;value&gt;<br>
      Nur f&uuml;r Heizk&ouml;rperthermostate. Schreibt die angegebene Boost Ventilstellung in den Speicher
      des Ger&auml;tes. Dies ist die Ventilstellung (in Prozent) die bei der Boost-Fumktion eingestellt wird.</li>
    <a name="maxValveSetting"></a><li>maxValveSetting &lt;value&gt;<br>
      Nur f&uuml;r Heizk&ouml;rperthermostate. Schreibt die angegebene maximale Ventilposition in den Speicher
      des Ger&auml;tes. Der Heizk&ouml;rperthermostat wird das Ventil nicht weiter &ouml;ffnen als diesen Wert
      (Angabe in Prozent).</li>
    <a name="valveOffset"></a><li>valveOffset &lt;value&gt;<br>
      Nur f&uuml;r Heizk&ouml;rperthermostate. Schreibt den angegebenen <code>offset</code> Wert der Ventilstellung
      in den Speicher des Ger&auml;tes Der Heizk&ouml;rperthermostat wird diesen Wert w&auml;hrend der Regelung
      zu den berechneten Ventilstellungen hinzuaddieren.</li>


    <a name="weekProfile"></a><li>weekProfile [&lt;day&gt; &lt;temp1&gt;,&lt;until1&gt;,&lt;temp2&gt;,&lt;until2&gt;]
      [&lt;day&gt; &lt;temp1&gt;,&lt;until1&gt;,&lt;temp2&gt;,&lt;until2&gt;] ...<br>
      Erlaubt das Setzen eines Wochenprofils. Nur f&uuml;r Heizk&ouml;rperthermostate bzw. Wandthermostate.<br>
      Beispiel:<br>
      <code>set MAX_12345 weekProfile Fri 24.5,6:00,12,15:00,5 Sat 7,4:30,19,12:55,6</code><br>
      stellt das folgende Profil ein<br>
      <code>Freitag: 24.5 &deg;C von 0:00 - 6:00, 12 &deg;C von 6:00 - 15:00, 5 &deg;C von 15:00 - 0:00<br>
      Samstag: 7 &deg;C von 0:00 - 4:30, 19 &deg;C von 4:30 - 12:55, 6 &deg;C von 12:55 - 0:00</code><br>
      und beh&auml;lt die Profile f&uuml;r die anderen Wochentage bei.
    </li>
    <a name="saveConfig">saveConfig</a><li>saveConfig [name]</li>
    <a name="restoreRedings"></a><li>restoreRedings [name]</li>
    <a name="restoreDevice"></a><li>restoreDevice [name]</li>
  </ul>
  <br>

  <a name="MAXget"></a>
  <b>Get</b>
   <ul>
   <a name=""></a><li>show_savedConfig <device><br>
   zeigt gespeicherte Konfigurationen an die mittels set restoreReadings / restoreDevice verwendet werden k&ouml;nnen<br>
   steht erst zur Verf&uuml;gung wenn für dieses Ger&auml;t eine gespeichrte Konfiguration gefunden wurde.
   </li>
  </ul><br>

  <a name="MAXattr"></a>
  <b>Attributes</b>
  <ul>
    <a name="actCycle"></a> <li>actCycle &lt;hh:mm&gt; default leer (nur mit CUL_MAX)<br>
    Stellt eine Lebenserkennung für das Ger&auml;t zur Verf&uuml;gung. [hhh:mm] legt die maximale Zeit ohne eine Nachricht dieses Ger&auml;ts fest.<br>
    Wenn innerhalb dieser Zeit keine Nachrichten empfangen werden wird das Reading Actifity auf dead gesetzt.<br>
    Sendet das Ger&auml;t wieder wird das Reading auf alive zur&uuml;ck gesetzt.<br>
    <b>Wichtig</b> : Der Einsatz ist Nicht sinnvoll beim ECO Taster, da dieser als einziges Mitglied der MAX! Familie keine zyklischen Statusnachrichten verschickt !</li><br>
    <a name="CULdev"></a><li>CULdev &lt;name&gt; default leer (nur mit CUL_MAX)<br>
    CUL der zum senden benutzt wird wenn CUL_MAX eine IO Gruppe verwendet (Multi IO )</li><br>
    <a name="debug"></a><li>debug (0|1) default 0<br>erzeugt zus&auml;tzliche Readings (nur mit CUL_MAX)</li><br>

    <a name="dTempCheck"></a><li>dTempCheck (0|1) default 0<br>&uuml;berwacht im Abstand von 5 Minuten ob das Reading desiredTemperatur
     der Soll Temperatur im aktuellen Wochenprofil entspricht. (nur f&uuml; Ger&aumk;te vom Typ HT oder WT)<br>
     Das Ergebniss steht als Abweichung im Reading dTempCheck, d.h. 0 = keine Abweichung<br>
     Die &Uuml;berwachung is nur aktiv wenn die Soll Temperatur ungleich der Window Open Temperatur ist</li><br>

    <a name="dummy"></a><li>dummy (0|1) default 0<br>macht das Device zum read-only Device</li><br>

    <a name="externalSensor"></a><li>externalSensor &lt;device:reading&gt; default none<br>
    Wenn in einem Raum kein Wandthermostat vorhanden ist aber die Raumtemperatur zus&auml;tlich mit einem externen Sensor in FHEM erfasst wird (z.B. LaCrosse)<br>
    kann dessen aktueller Temperatur Wert zur Berechnung des Readings deviation benutzt werden statt des eigenen Readings temperature</li><br>

    <a name="IODev"></a><li>IODev &lt;name&gt;<br> MAXLAN oder CUL_MAX Device Name</li><br>

    <a name="keepAuto"></a><li>keepAuto (0|1) default 0<br>Wenn der Wert auf 1 gesetzt wird, bleibt das Ger&auml;t im Wochenprogramm auch wenn ein desiredTemperature gesendet wird.</li><br>

    <a name="scanTemp"></a><li>scanTemp (0|1) default 0<br>wird vom MaxScanner benutzt</li><br>

    <a name="skipDouble"></a><li>skipDouble (0|1) default 0 (nur mit CUL_MAX)<br>
    Wenn mehr als ein Thermostat zusammmen mit einem Fensterkontakt und/oder einem Wandthermostst eine Gruppe bildet,<br>
    versendet jedes Mitglieder der Gruppe seine Statusnachrichten einzeln an jedes andere Mitglied der Gruppe.<br>
    Das f&uuml;hrt dazu das manche Events doppelt oder sogar dreifach ausgel&ouml;st werden, kann mit diesem Attribut unterdr&uuml;ckt werden.</li><br>

    <a name="windowOpenCheck"></a><li>windowOpenCheck (0|1)<br>&uuml;berwacht im Abstand von 5 Minuten ob bei Geräten vom Typ ShutterContact das Reading onoff den Wert 1 hat (Fenster offen , default 1)<br>
     oder bei Geräten vom Typ HT/WT ob die Soll Temperatur gleich der Window Open Temperatur ist (default 0). Das Ergebniss steht im Reading windowOpen, Format hh:mm</li><br>
  </ul>
  <br>

  <a name="MAXevents"></a>
  <b>Erzeugte Ereignisse:</b>
  <ul>
    <li>desiredTemperature<br>Nur f&uuml;r Heizk&ouml;rperthermostate und Wandthermostate</li>
    <li>valveposition<br>Nur f&uuml;r Heizk&ouml;rperthermostate</li>
    <li>battery</li>
    <li>batteryState</li>
    <li>temperature<br>Die gemessene Temperatur (= gemessene Temperatur + <code>measurementOffset</code>),
       nur f&uuml;r Heizk&ouml;rperthermostate und Wandthermostate</li>
  </ul>
</ul>

=end html_DE
=cut
