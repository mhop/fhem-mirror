#####################################################################################
# $Id$
#
# Usage
#
# define <name> HOMEMODE [RESIDENTS-MASTER-DEVICE]
#
#####################################################################################

package main;

use strict;
use warnings;
use POSIX;
use Time::HiRes qw(gettimeofday);
use HttpUtils;
use vars qw{%attr %defs %modules $FW_CSRF};

my $HOMEMODE_version = "1.2.0";
my $HOMEMODE_Daytimes = "05:00|morning 10:00|day 14:00|afternoon 18:00|evening 23:00|night";
my $HOMEMODE_Seasons = "03.01|spring 06.01|summer 09.01|autumn 12.01|winter";
my $HOMEMODE_UserModes = "gotosleep,awoken,asleep";
my $HOMEMODE_UserModesAll = "$HOMEMODE_UserModes,home,absent,gone";
my $HOMEMODE_AlarmModes = "disarm,confirm,armhome,armnight,armaway";
my $HOMEMODE_Locations = "arrival,home,bed,underway,wayhome";
my $HOMEMODE_de;

sub HOMEMODE_Initialize($)
{
  my ($hash) = @_;
  $hash->{AttrFn}       = "HOMEMODE_Attr";
  $hash->{DefFn}        = "HOMEMODE_Define";
  $hash->{NotifyFn}     = "HOMEMODE_Notify";
  $hash->{GetFn}        = "HOMEMODE_Get";
  $hash->{SetFn}        = "HOMEMODE_Set";
  $hash->{UndefFn}      = "HOMEMODE_Undef";
  $hash->{FW_detailFn}  = "HOMEMODE_Details";
  $hash->{AttrList}     = HOMEMODE_Attributes($hash);
  $hash->{NotifyOrderPrefix} = "51-";
  $hash->{FW_deviceOverview} = 1;
  $hash->{FW_addDetailToSummary} = 1;
}

sub HOMEMODE_Define($$)
{
  my ($hash,$def) = @_;
  my @args = split " ",$def;
  my ($name,$type,$resdev) = @args;
  $HOMEMODE_de = AttrVal("global","language","EN") eq "DE" || AttrVal($name,"HomeLanguage","EN" eq "DE") ? 1 : 0;
  my $trans;
  if (@args < 2 || @args > 3)
  {
    $trans = $HOMEMODE_de?
      "Benutzung: define <name> HOMEMODE [RESIDENTS-MASTER-GERAET]":
      "Usage: define <name> HOMEMODE [RESIDENTS-MASTER-DEVICE]";
    return $trans;
  }
  RemoveInternalTimer($hash);
  if (!$resdev)
  {
    my @resdevs;
    foreach (devspec2array("TYPE=RESIDENTS:FILTER=disable!=1"))
    {
      push @resdevs,$_;
    }
    if (@resdevs == 1)
    {
      $trans = $HOMEMODE_de?
        "$resdevs[0] existiert nicht":
        "$resdevs[0] doesn't exists";
      return $trans if (!IsDevice($resdevs[0]));
      $hash->{DEF} = $resdevs[0];
    }
    elsif (@resdevs > 1)
    {
      $trans = $HOMEMODE_de?
        "Es gibt zu viele RESIDENTS Geräte! Bitte das Master RESIDENTS Gerät angeben! Verfügbare RESIDENTS Geräte:":
        "Found too many available RESIDENTS devives! Please specify the RESIDENTS master device! Available RESIDENTS devices:";
      return "$trans ".join(",",@resdevs);
    }
    else
    {
      $trans = $HOMEMODE_de?
        "Kein RESIDENTS Gerät gefunden! Bitte erst ein RESIDENTS Gerät anlegen und ein paar ROOMMATE/GUEST und ihre korrespondierenden PRESENCE Geräte hinzufügen um Spaß mit diesem Modul zu haben!":
        "No RESIDENTS device found! Please define a RESIDENTS device first and add some ROOMMATE/GUEST and their PRESENCE device(s) to have fun with this module!";
      return $trans;
    }
  }
  $hash->{NOTIFYDEV} = "global";
  if ($init_done && !defined $hash->{OLDDEF})
  {
    $attr{$name}{devStateIcon}  = "absent:user_away:dnd+on\n".
                                  "gone:user_ext_away:dnd+on\n".
                                  "dnd:audio_volume_mute:dnd+off\n".
                                  "gotosleep:scene_sleeping:dnd+on\n".
                                  "asleep:scene_sleeping_alternat:dnd+on\n".
                                  "awoken:weather_sunrise:dnd+on\n".
                                  "home:status_available:dnd+on\n".
                                  "morning:weather_sunrise:dnd+on\n".
                                  "day:weather_sun:dnd+on\n".
                                  "afternoon:weather_summer:dnd+on\n".
                                  "evening:weather_sunset:dnd+on\n".
                                  "night:weather_moon_phases_2:dnd+on";
    $attr{$name}{icon}          = "floor";
    $attr{$name}{room}          = "HOMEMODE";
    $attr{$name}{webCmd}        = "modeAlarm";
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,"dnd","off") if (!defined ReadingsVal($name,"dnd",undef));
    readingsBulkUpdate($hash,"anyoneElseAtHome","off") if (!defined ReadingsVal($name,"anyoneElseAtHome",undef));
    readingsBulkUpdate($hash,"panic","off") if (!defined ReadingsVal($name,"panic",undef));
    readingsEndUpdate($hash,0);
    HOMEMODE_updateInternals($hash);
  }
  return;
}

sub HOMEMODE_Undef($$)
{
  my ($hash,$arg) = @_;
  RemoveInternalTimer($hash);
  my $name = $hash->{NAME};
  if (devspec2array("TYPE=HOMEMODE:FILTER=disable!=1") == 1)
  {
    HOMEMODE_cleanUserattr($hash,AttrVal($name,"HomeSensorsContact","")) if (AttrVal($name,"HomeSensorsContact",undef));
    HOMEMODE_cleanUserattr($hash,AttrVal($name,"HomeSensorsMotion","")) if (AttrVal($name,"HomeSensorsMotion",undef));
  }
  return;
}

sub HOMEMODE_Notify($$)
{
  my ($hash,$dev) = @_;
  my $name = $hash->{NAME};
  my $devname = $dev->{NAME};
  return if (IsDisabled($name) || IsDisabled($devname));
  my $devtype = $dev->{TYPE};
  my $events = deviceEvents($dev,1);
  return if (!$events);
  Log3 $name,5,"$name: Events from monitored device $devname: ". join " --- ",@{$events};
  my $prestype = AttrVal($name,"HomePresenceDeviceType","PRESENCE");
  my @commands;
  if ($devname eq "global")
  {
    if (grep /^INITIALIZED$/,@{$events})
    {
      HOMEMODE_updateInternals($hash);
      push @commands,AttrVal($name,"HomeCMDfhemINITIALIZED","")
        if (AttrVal($name,"HomeCMDfhemINITIALIZED",""));
    }
    elsif (grep /^SAVE$/,@{$events})
    {
      push @commands,AttrVal($name,"HomeCMDfhemSAVE","")
        if (AttrVal($name,"HomeCMDfhemSAVE",""));
    }
    elsif (grep /^UPDATE$/,@{$events})
    {
      push @commands,AttrVal($name,"HomeCMDfhemUPDATE","")
        if (AttrVal($name,"HomeCMDfhemUPDATE",""));
    }
    elsif (grep /^DEFINED/,@{$events})
    {
      foreach (@{$events})
      {
        next unless ($_ =~ /^DEFINED\s(.*)$/);
        my $dev = $1;
        my $cmd = AttrVal($name,"HomeCMDfhemDEFINED","");
        if ($cmd)
        {
          $cmd =~ s/%DEFINED%/$dev/gm;
          push @commands,$cmd;
        }
        CommandAttr(undef,"$dev room ".AttrVal($name,"HomeAtTmpRoom",""))
          if ($dev =~ /^atTmp_.*_$name$/ && $defs{$dev}->{TYPE} eq "at" && AttrVal($name,"HomeAtTmpRoom",""));
      }
    }
    elsif (grep /^REREADCFG|MODIFIED\s$name$/,@{$events})
    {
      HOMEMODE_updateInternals($hash,1);
    }
  }
  else
  {
    if ($devtype =~ /^(RESIDENTS|ROOMMATE|GUEST)$/)
    {
      HOMEMODE_RESIDENTS($hash,$devname);
    }
    elsif (AttrVal($name,"HomeYahooWeatherDevice",undef) && $devname eq AttrVal($name,"HomeYahooWeatherDevice",""))
    {
      HOMEMODE_Weather($hash,$devname);
    }
    elsif (AttrVal($name,"HomeTwilightDevice",undef) && $devname eq AttrVal($name,"HomeTwilightDevice",""))
    {
      HOMEMODE_Twilight($hash,$devname);
    }
    elsif (AttrVal($name,"HomeEventsHolidayDevices",undef) && grep(/^$devname$/,devspec2array(AttrVal($name,"HomeEventsHolidayDevices",""))) && grep /^state:\s/,@{$events})
    {
      foreach my $evt (@{$events})
      {
        next unless ($evt =~ /^state:\s(.*)$/);
        HOMEMODE_EventCommands($hash,$devname,$1);
      }
    }
    elsif (AttrVal($name,"HomeUWZ",undef) && $devname eq AttrVal($name,"HomeUWZ","") && grep /^WarnCount:\s/,@{$events})
    {
      HOMEMODE_UWZCommands($hash,$events);
    }
    elsif (AttrVal($name,"HomeTriggerPanic","") && $devname eq (split /:/,AttrVal($name,"HomeTriggerPanic",""))[0])
    {
      my ($d,$r,$on,$off) = split /:/,AttrVal($name,"HomeTriggerPanic","");
      if ($devname eq $d)
      {
        if (grep /^$r:\s$on$/,@{$events})
        {
          if ($off)
          {
            CommandSet(undef,"$name:FILTER=panic=off panic on");
          }
          else
          {
            if (ReadingsVal($name,"panic","off") eq "off")
            {
              CommandSet(undef,"$name:FILTER=panic=off panic on");
            }
            else
            {
              CommandSet(undef,"$name:FILTER=panic=on panic off");
            }
          }
        }
        elsif ($off && grep /^$r:\s$off$/,@{$events})
        {
          CommandSet(undef,"$name:FILTER=panic=on panic off");
        }
      }
    }
    elsif (AttrVal($name,"HomeTriggerAnyoneElseAtHome","") && $devname eq (split /:/,AttrVal($name,"HomeTriggerAnyoneElseAtHome",""))[0])
    {
      my ($d,$r,$on,$off) = split /:/,AttrVal($name,"HomeTriggerAnyoneElseAtHome","");
      if ($devname eq $d)
      {
        if (grep /^$r:\s$on$/,@{$events})
        {
          CommandSet(undef,"$name:FILTER=anyoneElseAtHome=off anyoneElseAtHome on");
        }
        elsif (grep /^$r:\s$off$/,@{$events})
        {
          CommandSet(undef,"$name:FILTER=anyoneElseAtHome=on anyoneElseAtHome off");
        }
      }
    }
    elsif ($hash->{SENSORSENERGY} && grep(/^$devname$/,split /,/,$hash->{SENSORSENERGY}))
    {
      my $read = AttrVal($name,"HomeSensorsPowerEnergyReadings","power energy");
      $read =~ s/ /\|/g;
      foreach my $evt (@{$events})
      {
        next unless ($evt =~ /^($read):\s(.*)$/);
        HOMEMODE_PowerEnergy($hash,$devname,$1,(split " ",$2)[0]);
      }
    }
    elsif ($hash->{SENSORSSMOKE} && grep(/^$devname$/,split /,/,$hash->{SENSORSSMOKE}))
    {
      my $read = AttrVal($name,"HomeSensorsSmokeReading","state");
      foreach my $evt (@{$events})
      {
        next unless ($evt =~ /^$read:\s(.*)$/);
        HOMEMODE_Smoke($hash,$devname,$1);
      }
    }
    else
    {
      if ($hash->{SENSORSCONTACT} && grep(/^$devname$/,split /,/,$hash->{SENSORSCONTACT}))
      {
        my ($oread,$tread) = split " ",AttrVal($devname,"HomeReadings",AttrVal($name,"HomeSensorsContactReadings","state sabotageError"));
        HOMEMODE_TriggerState($hash,undef,undef,$devname) if (grep /^($oread|$tread):\s.*$/,@{$events});
      }
      if ($hash->{SENSORSMOTION} && grep(/^$devname$/,split /,/,$hash->{SENSORSMOTION}))
      {
        my ($oread,$tread) = split " ",AttrVal($devname,"HomeReadings",AttrVal($name,"HomeSensorsMotionReadings","state sabotageError"));
        HOMEMODE_TriggerState($hash,undef,undef,$devname) if (grep /^($oread|$tread):\s.*$/,@{$events});
      }
      if ($hash->{SENSORSLUMINANCE} && grep(/^$devname$/,split /,/,$hash->{SENSORSLUMINANCE}))
      {
        my $read = AttrVal($name,"HomeSensorsLuminanceReading","luminance");
        if (grep /^$read:\s.*$/,@{$events})
        {
          foreach my $evt (@{$events})
          {
            next unless ($evt =~ /^$read:\s(.*)$/);
            HOMEMODE_Luminance($hash,$devname,(split " ",$1)[0]);
          }
        }
      }
      if (AttrVal($name,"HomeSensorTemperatureOutside",undef) && $devname eq AttrVal($name,"HomeSensorTemperatureOutside","") && grep /^(temperature|humidity):\s/,@{$events})
      {
        my $temp;
        my $humi;
        foreach my $evt (@{$events})
        {
          next unless ($evt =~ /^(humidity|temperature):\s(.*)$/);
          $temp = (split " ",$2)[0] if ($1 eq "temperature");
          $humi = (split " ",$2)[0] if ($1 eq "humidity");
        }
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash,"temperature",$temp);
        if (defined $humi && !AttrVal($name,"HomeSensorHumidityOutside",undef))
        {
          readingsBulkUpdate($hash,"humidity",$humi);
          $hash->{helper}{externalHumidity} = 1;
        }
        elsif (!AttrVal($name,"HomeSensorHumidityOutside",undef))
        {
          delete $hash->{helper}{externalHumidity};
        }
        readingsEndUpdate($hash,1);
        HOMEMODE_ReadingTrend($hash,"humidity",$humi) if (defined $humi);
        HOMEMODE_ReadingTrend($hash,"temperature",$temp);
        HOMEMODE_Icewarning($hash);
      }
      if (AttrVal($name,"HomeSensorHumidityOutside",undef) && $devname eq AttrVal($name,"HomeSensorHumidityOutside","") && grep /^humidity:\s/,@{$events})
      {
        $hash->{helper}{externalHumidity} = 1;
        foreach my $evt (@{$events})
        {
          next unless ($evt =~ /^humidity:\s(.*)$/);
          my $val = (split " ",$1)[0];
          readingsSingleUpdate($hash,"humidity",$val,1);
          HOMEMODE_ReadingTrend($hash,"humidity",$val);
        }
      }
      if (AttrVal($name,"HomeSensorWindspeed",undef) && $devname eq (split /:/,AttrVal($name,"HomeSensorWindspeed",""))[0])
      {
        my $read = (split /:/,AttrVal($name,"HomeSensorWindspeed",""))[1];
        if (grep /^$read:\s(.*)$/,@{$events})
        {
          foreach my $evt (@{$events})
          {
            next unless ($evt =~ /^$read:\s(.*)$/);
            my $val = (split " ",$1)[0];
            readingsSingleUpdate($hash,"wind",$val,1);
            HOMEMODE_ReadingTrend($hash,"wind",$val);
          }
        }
      }
      if (AttrVal($name,"HomeSensorAirpressure",undef) && $devname eq (split /:/,AttrVal($name,"HomeSensorAirpressure",""))[0])
      {
        my $read = (split /:/,AttrVal($name,"HomeSensorAirpressure",""))[1];
        if (grep /^$read:\s(.*)$/,@{$events})
        {
          foreach my $evt (@{$events})
          {
            next unless ($evt =~ /^$read:\s(.*)$/);
            my $val = (split " ",$1)[0];
            readingsSingleUpdate($hash,"pressure",$val,1);
            HOMEMODE_ReadingTrend($hash,"pressure",$val);
          }
        }
      }
      if (AttrNum($name,"HomeAutoPresence",0) && $devtype =~ /^($prestype)$/ && grep(/^presence:\s(absent|present|appeared|disappeared)$/,@{$events}))
      {
        my $resident;
        my $residentregex;
        foreach (split /,/,$hash->{RESIDENTS})
        {
          my $regex = lc($_);
          $regex =~ s/^(rr_|rg_)//;
          next if (lc($devname) !~ /$regex/);
          $resident = $_;
          $residentregex = $regex;
        }
        return if (!$resident);
        $hash->{helper}{lar} = $resident;
        if (ReadingsVal($devname,"presence","") !~ /^maybe/)
        {
          my @presentdevicespresent;
          foreach my $device (devspec2array("TYPE=$prestype:FILTER=disable!=1:FILTER=presence=^(maybe.)?(absent|present|appeared|disappeared)"))
          {
            next if (lc($device) !~ /$residentregex/);
            push @presentdevicespresent,$device if (ReadingsVal($device,"presence","") =~ /^(present|appeared|maybe.absent)$/);
          }
          if (grep /^.*:\s(present|appeared)$/,@{$events})
          {
            readingsBeginUpdate($hash);
            readingsBulkUpdate($hash,"lastActivityByPresenceDevice",$devname);
            readingsBulkUpdate($hash,"lastPresentByPresenceDevice",$devname);
            readingsEndUpdate($hash,1);
            push @commands,AttrVal($name,"HomeCMDpresence-present-device","") if (AttrVal($name,"HomeCMDpresence-present-device",undef));
            push @commands,AttrVal($name,"HomeCMDpresence-present-$resident-device","") if (AttrVal($name,"HomeCMDpresence-present-$resident-device",undef));
            push @commands,AttrVal($name,"HomeCMDpresence-present-$resident-$devname","") if (AttrVal($name,"HomeCMDpresence-present-$resident-$devname",undef));
            if (@presentdevicespresent >= AttrNum($name,"HomePresenceDevicePresentCount-$resident",1)
              && ReadingsVal($resident,"state","") =~ /^(absent|[gn]one)$/)
            {
              CommandSet(undef,"$resident:FILTER=state!=home state home");
            }
          }
          elsif (grep /^.*:\s(absent|disappeared)$/,@{$events})
          {
            readingsBeginUpdate($hash);
            readingsBulkUpdate($hash,"lastActivityByPresenceDevice",$devname);
            readingsBulkUpdate($hash,"lastAbsentByPresenceDevice",$devname);
            readingsEndUpdate($hash,1);
            push @commands,AttrVal($name,"HomeCMDpresence-absent-device","") if (AttrVal($name,"HomeCMDpresence-absent-device",undef));
            push @commands,AttrVal($name,"HomeCMDpresence-absent-$resident-device","") if (AttrVal($name,"HomeCMDpresence-absent-$resident-device",undef));
            push @commands,AttrVal($name,"HomeCMDpresence-absent-$resident-$devname","") if (AttrVal($name,"HomeCMDpresence-absent-$resident-$devname",undef));
            my $devcount = 1;
            $devcount = @{$hash->{helper}{presdevs}{$resident}} if ($hash->{helper}{presdevs}{$resident});
            my $presdevsabsent = $devcount - scalar @presentdevicespresent;
            if ($presdevsabsent >= AttrNum($name,"HomePresenceDeviceAbsentCount-$resident",1)
              && ReadingsVal($resident,"state","absent") !~ /^(absent|gone|none)$/)
            {
              CommandSet(undef,"$resident:FILTER=state!=absent state absent");
            }
          }
        }
      }
    }
    if ($hash->{SENSORSBATTERY} && grep(/^$devname$/,split /,/,$hash->{SENSORSBATTERY}))
    {
      my $read = AttrVal($name,"HomeSensorsBatteryReading","battery");
      if (grep /^$read:\s(.*)$/,@{$events})
      {
        my @lowOld = split /,/,ReadingsVal($name,"batteryLow","");
        my @low;
        @low = @lowOld if (@lowOld);
        foreach my $evt (@{$events})
        {
          next unless ($evt =~ /^$read:\s(.*)$/);
          my $val = $1;
          if (($val =~ /^(\d{1,3})(%|\s%)?$/ && $1 <= AttrNum($name,"HomeSensorsBatteryLowPercentage",50)) || $val =~ /^(nok|low)$/)
          {
            push @low,$devname if (!grep /^$devname$/,@low);
          }
          elsif (grep /^$devname$/,@low)
          {
            my @lown;
            foreach (@low)
            {
              push @lown,$_ if ($_ ne $devname);
            }
            @low = @lown;
          }
        }
        readingsBeginUpdate($hash);
        if (@low)
        {
          readingsBulkUpdateIfChanged($hash,"batteryLow",join(",",@low));
          readingsBulkUpdateIfChanged($hash,"batteryLow_ct",scalar @low);
          readingsBulkUpdateIfChanged($hash,"batteryLow_hr",HOMEMODE_makeHR($hash,1,@low));
          readingsBulkUpdateIfChanged($hash,"lastBatteryLow",$devname) if (grep(/^$devname$/,@low) && !grep(/^$devname$/,@lowOld));
          push @commands,AttrVal($name,"HomeCMDbatteryLow","") if (AttrVal($name,"HomeCMDbatteryLow",undef) && grep(/^$devname$/,@low) && !grep(/^$devname$/,@lowOld));
        }
        else
        {
          readingsBulkUpdateIfChanged($hash,"batteryLow","");
          readingsBulkUpdateIfChanged($hash,"batteryLow_ct",scalar @low);
          readingsBulkUpdateIfChanged($hash,"batteryLow_hr","");
        }
        readingsEndUpdate($hash,1);
      }
    }
  }
  HOMEMODE_execCMDs($hash,HOMEMODE_serializeCMD($hash,@commands)) if (@commands);
  HOMEMODE_GetUpdate($hash) if (!$hash->{".TRIGGERTIME_NEXT"} || $hash->{".TRIGGERTIME_NEXT"} + 1 < gettimeofday());
  return;
}

sub HOMEMODE_updateInternals($;$)
{
  my ($hash,$force) = @_;
  my $name = $hash->{NAME};
  my $resdev = $hash->{DEF};
  my $trans;
  if (!IsDevice($resdev))
  {
    $trans = $HOMEMODE_de?
      "$resdev ist nicht definiert!":
      "$resdev is not defined!";
    readingsSingleUpdate($hash,"state",$trans,0);
  }
  elsif (!IsDevice($resdev,"RESIDENTS"))
  {
    $trans = $HOMEMODE_de?
      "$resdev ist kein gültiges RESIDENTS Gerät!":
      "$resdev is not a valid RESIDENTS device!";
    readingsSingleUpdate($hash,"state",$trans,0);
  }
  else
  {
    my $oldContacts = $hash->{SENSORSCONTACT};
    my $oldMotions = $hash->{SENSORSMOTION};
    delete $hash->{helper}{presdevs};
    delete $hash->{RESIDENTS};
    delete $hash->{SENSORSCONTACT};
    delete $hash->{SENSORSMOTION};
    delete $hash->{SENSORSENERGY};
    delete $hash->{SENSORSLUMINANCE};
    delete $hash->{SENSORSBATTERY};
    delete $hash->{SENSORSSMOKE};
    $hash->{VERSION} = $HOMEMODE_version;
    my @residents;
    push @residents,$defs{$resdev}->{ROOMMATES} if ($defs{$resdev}->{ROOMMATES});
    push @residents,$defs{$resdev}->{GUESTS} if ($defs{$resdev}->{GUESTS});
    if (@residents < 1)
    {
      $trans = $HOMEMODE_de?
        "Keine verfügbaren ROOMMATE/GUEST im RESIDENTS Gerät $resdev":
        "No available ROOMMATE/GUEST in RESIDENTS device $resdev";
      Log3 $name,2,$trans;
      readingsSingleUpdate($hash,"HomeInfo",$trans,1);
      return;
    }
    else
    {
      $hash->{RESIDENTS} = join(",",sort @residents);
    }
    my @allMonitoredDevices;
    push @allMonitoredDevices,"global";
    push @allMonitoredDevices,$resdev;
    my $autopresence = HOMEMODE_AttrCheck($hash,"HomeAutoPresence",0);
    my $presencetype = HOMEMODE_AttrCheck($hash,"HomePresenceDeviceType","PRESENCE");
    my @presdevs = devspec2array("TYPE=$presencetype:FILTER=disable!=1:FILTER=presence=^(maybe.)?(absent|present|appeared|disappeared)");
    my @residentsshort;
    my @logtexte;
    foreach my $resident (split /,/,$hash->{RESIDENTS})
    {
      push @allMonitoredDevices,$resident;
      my $short = lc($resident);
      $short =~ s/^(rr_|rg_)//;
      push @residentsshort,$short;
      if ($autopresence)
      {
        my @residentspresdevs;
        foreach my $p (@presdevs)
        {
          next if (lc($p) !~ /($short)/);
          push @residentspresdevs,$p;
          push @allMonitoredDevices,$p if (!grep /^($p)$/,@allMonitoredDevices);
        }
        my $c = scalar @residentspresdevs;
        if ($c)
        {
          my $devlist = join(",",@residentspresdevs);
          $trans = $HOMEMODE_de?
            "Gefunden wurden $c übereinstimmende(s) Anwesenheits Gerät(e) vom Devspec \"TYPE=$presencetype\" für Bewohner \"$resident\"! Übereinstimmende Geräte: \"$devlist\"":
            "Found $c matching presence devices of devspec \"TYPE=$presencetype\" for resident \"$resident\"! Matching devices: \"$devlist\"";
          push @logtexte,$trans;
          CommandAttr(undef,"$name HomePresenceDeviceAbsentCount-$resident $c") if ($init_done && ((!defined AttrNum($name,"HomePresenceDeviceAbsentCount-$resident",undef) && $c > 1) || (defined AttrNum($name,"HomePresenceDeviceAbsentCount-$resident",undef) && $c < AttrNum($name,"HomePresenceDeviceAbsentCount-$resident",1))));
        }
        else
        {
          $trans = $HOMEMODE_de?
            "Keine Geräte mit presence Reading gefunden vom Devspec \"TYPE=$presencetype\" für Bewohner \"$resident\"!":
            "No devices with presence reading found of devspec \"TYPE=$presencetype\" for resident \"$resident\"!";
          push @logtexte,$trans;
        }
        $hash->{helper}{presdevs}{$resident} = \@residentspresdevs if (@residentspresdevs > 1);
      }
    }
    if (@logtexte && $force)
    {
      $trans = $HOMEMODE_de?
        "Falls ein oder mehr Anweseheits Geräte falsch zugeordnet wurden, so benenne diese bitte so um dass die Bewohner Namen (".join(",",@residentsshort).") nicht Bestandteil des Namen sind.\nNach dem Umbenennen führe einfach \"set $name updateInternalsForce\" aus um diese Überprüfung zu wiederholen.":
        "If any recognized presence device is wrong, please rename this device so that it will NOT match the residents names (".join(",",@residentsshort).") somewhere in the device name.\nAfter renaming simply execute \"set $name updateInternalsForce\" to redo this check.";
      push @logtexte,"\n$trans";
      my $log = join("\n",@logtexte);
      Log3 $name,3,"$name: $log";
      $log =~ s/\n/<br>/gm;
      readingsSingleUpdate($hash,"HomeInfo","<html>$log</html>",1);
    }
    my $contacts = HOMEMODE_AttrCheck($hash,"HomeSensorsContact");
    if ($contacts)
    {
      my @sensors;
      foreach my $s (devspec2array($contacts))
      {
        next if (IsDisabled($s));
        push @sensors,$s;
        push @allMonitoredDevices,$s if (!grep /^$s$/,@allMonitoredDevices);
      }
      my $list = join(",",sort @sensors);
      $hash->{SENSORSCONTACT} = $list;
      HOMEMODE_addSensorsuserattr($hash,$list,$oldContacts) if (($force && !$oldContacts) || ($oldContacts && $list ne $oldContacts));
    }
    elsif (!$contacts && $oldContacts)
    {
      HOMEMODE_cleanUserattr($hash,$oldContacts);
    }
    my $motion = HOMEMODE_AttrCheck($hash,"HomeSensorsMotion");
    if ($motion)
    {
      my @sensors;
      foreach my $s (devspec2array($motion))
      {
        next if (IsDisabled($s));
        push @sensors,$s;
        push @allMonitoredDevices,$s if (!grep /^$s$/,@allMonitoredDevices);
      }
      my $list = join(",",sort @sensors);
      $hash->{SENSORSMOTION} = $list;
      HOMEMODE_addSensorsuserattr($hash,$list,$oldMotions) if (($force && !$oldMotions) || ($oldMotions && $list ne $oldMotions));
    }
    elsif (!$motion && $oldMotions)
    {
      HOMEMODE_cleanUserattr($hash,$oldMotions);
    }
    my $power = HOMEMODE_AttrCheck($hash,"HomeSensorsPowerEnergy");
    if ($power)
    {
      my @sensors;
      my ($p,$e) = split " ",AttrVal($name,"HomeSensorsPowerEnergyReadings","power energy");
      foreach my $s (devspec2array($power))
      {
        next unless (!IsDisabled($s) && defined ReadingsVal($s,$p,undef) && defined ReadingsVal($s,$e,undef));
        push @sensors,$s;
        push @allMonitoredDevices,$s if (!grep /^$s$/,@allMonitoredDevices);
      }
      $hash->{SENSORSENERGY} = join(",",sort @sensors) if (@sensors);
    }
    my $smoke = HOMEMODE_AttrCheck($hash,"HomeSensorsSmoke");
    if ($smoke)
    {
      my @sensors;
      my $r = AttrVal($name,"HomeSensorsSmokeReading","state");
      foreach my $s (devspec2array($smoke))
      {
        next unless (!IsDisabled($s) && defined ReadingsVal($s,$r,undef));
        push @sensors,$s;
        push @allMonitoredDevices,$s if (!grep /^$s$/,@allMonitoredDevices);
      }
      $hash->{SENSORSSMOKE} = join(",",sort @sensors) if (@sensors);
    }
    my $battery = HOMEMODE_AttrCheck($hash,"HomeSensorsBattery");
    if ($battery)
    {
      my @sensors;
      foreach my $s (devspec2array($battery))
      {
        next if (IsDisabled($s));
        my $read = AttrVal($name,"HomeSensorsBatteryReading","battery");
        my $val = ReadingsVal($s,$read,undef);
        next unless (defined $val && $val =~ /^(ok|low|nok|\d{1,3})(%|\s%)?$/);
        push @sensors,$s;
        push @allMonitoredDevices,$s if (!grep /^$s$/,@allMonitoredDevices);
      }
      $hash->{SENSORSBATTERY} = join(",",sort @sensors) if (@sensors);
    }
    my $weather = HOMEMODE_AttrCheck($hash,"HomeYahooWeatherDevice");
    push @allMonitoredDevices,$weather if ($weather && !grep /^$weather$/,@allMonitoredDevices);
    my $twilight = HOMEMODE_AttrCheck($hash,"HomeTwilightDevice");
    push @allMonitoredDevices,$twilight if ($twilight && !grep /^$twilight$/,@allMonitoredDevices);
    my $temperature = HOMEMODE_AttrCheck($hash,"HomeSensorTemperatureOutside");
    push @allMonitoredDevices,$temperature if ($temperature && !grep /^$temperature$/,@allMonitoredDevices);
    my $humidity = HOMEMODE_AttrCheck($hash,"HomeSensorHumidityOutside");
    if ($humidity && $temperature ne $humidity)
    {
      push @allMonitoredDevices,$humidity if (!grep /^$humidity$/,@allMonitoredDevices);
    }
    my $holiday = HOMEMODE_AttrCheck($hash,"HomeEventsHolidayDevices");
    if ($holiday)
    {
      foreach my $c (devspec2array($holiday))
      {
        push @allMonitoredDevices,$c if (!grep /^$c$/,@allMonitoredDevices);
      }
    }
    my $uwz = HOMEMODE_AttrCheck($hash,"HomeUWZ","");
    push @allMonitoredDevices,$uwz if ($uwz && !grep /^$uwz$/,@allMonitoredDevices);
    my $luminance = HOMEMODE_AttrCheck($hash,"HomeSensorsLuminance");
    if ($luminance)
    {
      my $read = AttrVal($name,"HomeSensorsLuminanceReading","luminance");
      my @sensors;
      foreach my $s (devspec2array($luminance))
      {
        next if (IsDisabled($s));
        if (defined ReadingsVal($s,AttrVal($name,"HomeSensorsLuminanceReading","luminance"),undef))
        {
          push @sensors,$s;
          push @allMonitoredDevices,$s if (!grep /^$s$/,@allMonitoredDevices);
        }
      }
      $hash->{SENSORSLUMINANCE} = join(",",sort @sensors) if (@sensors);
    }
    my $pressure = (split /:/,HOMEMODE_AttrCheck($hash,"HomeSensorAirpressure"))[0];
    push @allMonitoredDevices,$pressure if ($pressure && !grep /^$pressure$/,@allMonitoredDevices);
    my $wind = (split /:/,HOMEMODE_AttrCheck($hash,"HomeSensorWindspeed"))[0];
    push @allMonitoredDevices,$wind if ($wind && !grep /^$wind$/,@allMonitoredDevices);
    my $panic = (split /:/,HOMEMODE_AttrCheck($hash,"HomeTriggerPanic"))[0];
    push @allMonitoredDevices,$panic if ($panic && !grep /^$panic$/,@allMonitoredDevices);
    my $aeah = (split /:/,HOMEMODE_AttrCheck($hash,"HomeTriggerAnyoneElseAtHome"))[0];
    push @allMonitoredDevices,$aeah if ($aeah && !grep /^$aeah$/,@allMonitoredDevices);
    Log3 $name,5,"$name: new monitored device count: ".@allMonitoredDevices;
    @allMonitoredDevices = sort @allMonitoredDevices;
    $hash->{NOTIFYDEV} = join(",",@allMonitoredDevices);
    HOMEMODE_GetUpdate($hash);
    return if (!@allMonitoredDevices);
    HOMEMODE_RESIDENTS($hash);
    HOMEMODE_userattr($hash);
    HOMEMODE_TriggerState($hash) if ($hash->{SENSORSCONTACT} || $hash->{SENSORSMOTION});
    HOMEMODE_Luminance($hash) if ($hash->{SENSORSLUMINANCE});
    HOMEMODE_PowerEnergy($hash) if ($hash->{SENSORSENERGY});
    HOMEMODE_Smoke($hash) if ($hash->{SENSORSSMOKE});
    HOMEMODE_Weather($hash,$weather) if ($weather);
    HOMEMODE_Twilight($hash,$twilight,1) if ($twilight);
  }
  return;
}

sub HOMEMODE_GetUpdate(@)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  RemoveInternalTimer($hash,"HOMEMODE_GetUpdate");
  return if (IsDisabled($name));
  my $mode = HOMEMODE_DayTime($hash);
  HOMEMODE_SetDaytime($hash);
  HOMEMODE_SetSeason($hash);
  CommandSet(undef,"$name:FILTER=mode!=$mode mode $mode") if (ReadingsVal($hash->{DEF},"state","") eq "home" && AttrNum($name,"HomeAutoDaytime",1));
  HOMEMODE_checkIP($hash) if ((AttrNum($name,"HomePublicIpCheckInterval",0) && !$hash->{".IP_TRIGGERTIME_NEXT"}) || (AttrNum($name,"HomePublicIpCheckInterval",0) && $hash->{".IP_TRIGGERTIME_NEXT"} && $hash->{".IP_TRIGGERTIME_NEXT"} < gettimeofday()));
  my $timer = gettimeofday() + 5;
  $hash->{".TRIGGERTIME_NEXT"} = $timer;
  InternalTimer($timer,"HOMEMODE_GetUpdate",$hash);
  return;
}

sub HOMEMODE_Get($@)
{
  my ($hash,$name,@aa) = @_;
  my ($cmd,@args) = @aa;
  return if (IsDisabled($name) && $cmd ne "?");
  my $params;
  $params .= "contactsOpen:all,doorsinside,doorsoutside,doorsmain,outside,windows" if ($hash->{SENSORSCONTACT});
  $params .= " " if ($params);
  $params .= "sensorsTampered:noArg" if ($hash->{SENSORSCONTACT} || $hash->{SENSORSMOTION});
  $params .= " " if ($params);
  $params .= "publicIP:noArg";
  my $trans;
  if (AttrVal($name,"HomeYahooWeatherDevice",undef))
  {
    $params .= " " if ($params);
    $params .= "weather:" if (AttrVal($name,"HomeTextWeatherLong",undef) || AttrVal($name,"HomeTextWeatherShort",undef));
    $params .= "long" if (AttrVal($name,"HomeTextWeatherLong",undef));
    if (AttrVal($name,"HomeTextWeatherShort",undef))
    {
      $params .= ",";
      $params .= "short";
    }
    $params .= " " if ($params);
    $params .= "weatherForecast";
  }
  return if (!$params);
  my $value = $args[0];
  if ($cmd =~ /^contactsOpen$/)
  {
    $trans = $HOMEMODE_de?
      "$cmd benötigt ein Argument":
      "$cmd needs one argument!";
    return $trans if (!$value);
    HOMEMODE_TriggerState($hash,$cmd,$value);
  }
  elsif ($cmd =~ /^sensorsTampered$/)
  {
    $trans = $HOMEMODE_de?
      "$cmd benötigt kein Argument":
      "$cmd needs no argument!";
    return $trans if ($value);
    HOMEMODE_TriggerState($hash,$cmd);
  }
  elsif ($cmd eq "weather")
  {
    $trans = $HOMEMODE_de?
      "$cmd benötigt ein Argument, entweder long oder short!":
      "$cmd needs one argument of long or short!";
    return $trans if (!$value || $value !~ /^(long|short)$/);
    my $m = "Long";
    $m = "Short" if ($value eq "short");
    HOMEMODE_WeatherTXT($hash,AttrVal($name,"HomeTextWeather$m",""));
  }
  elsif ($cmd eq "weatherForecast")
  {
    $trans = $HOMEMODE_de?
      "Der Wert für $cmd muss zwischen 1 und 10 sein. Falls der Wert weggelassen wird, so wird 2 (für morgen) benutzt.":
      "Value for $cmd must be from 1 to 10. If omitted the value will be 2 for tomorrow.";
    return $trans if ($value && $value !~ /^[1-9]0?$/ && ($value < 1 || $value > 10));
    HOMEMODE_ForecastTXT($hash,$value);
  }
  elsif ($cmd eq "publicIP")
  {
    return HOMEMODE_checkIP($hash,1);
  }
  else
  {
    return "Unknown argument $cmd for $name, choose one of $params";
  }
}

sub HOMEMODE_Set($@)
{
  my ($hash,$name,@aa) = @_;
  my ($cmd,@args) = @aa;
  return if (IsDisabled($name) && $cmd ne "?");
  $HOMEMODE_de = AttrVal("global","language","EN") eq "DE" || AttrVal($name,"HomeLanguage","EN") eq "DE" ? 1 : 0;
  my $trans = $HOMEMODE_de?
    "\"set $name\" benötigt mindestens ein und maximal drei Argumente":
    "\"set $name\" needs at least one argument and maximum three arguments";
  return $trans if (@aa > 3);
  my $option = defined $args[0] ? $args[0] : undef;
  my $value = defined $args[1] ? $args[1] : undef;
  my $mode = ReadingsVal($name,"mode","");
  my $amode = ReadingsVal($name,"modeAlarm","");
  my $plocation = ReadingsVal($name,"location","");
  my $presence = ReadingsVal($name,"presence","");
  my @locations = split /,/,$HOMEMODE_Locations;
  my $slocations = HOMEMODE_AttrCheck($hash,"HomeSpecialLocations");
  if ($slocations)
  {
    foreach (split /,/,$slocations)
    {
      push @locations,$_;
    }
  }
  my @modeparams = split /,/,$HOMEMODE_UserModesAll;
  my $smodes = HOMEMODE_AttrCheck($hash,"HomeSpecialModes");
  if ($smodes)
  {
    foreach (split /,/,$smodes)
    {
      push @modeparams,$_;
    }
  }
  my $para;
  $para .= "mode:".join(",",sort @modeparams)." " if (!AttrNum($name,"HomeAutoDaytime",1));
  $para .= "modeAlarm:$HOMEMODE_AlarmModes";
  $para .= " modeAlarm-for-minutes";
  $para .= " dnd:on,off";
  $para .= " dnd-for-minutes";
  $para .= " anyoneElseAtHome:on,off";
  $para .= " panic:on,off";
  $para .= " location:".join(",", sort @locations);
  $para .= " updateInternalsForce:noArg";
  $para .= " updateHomebridgeMapping:noArg";
  return "$cmd is not a valid command for $name, please choose one of $para" if (!$cmd || $cmd eq "?");
  my @commands;
  if ($cmd eq "mode")
  {
    my $namode = "disarm";
    my $present = "absent";
    my $location = "underway";
    $option = HOMEMODE_DayTime($hash) if ($option && $option eq "home" && AttrNum($name,"HomeAutoDaytime",1));
    if ($option !~ /^(absent|gone)$/)
    {
      push @commands,AttrVal($name,"HomeCMDpresence-present","") if (AttrVal($name,"HomeCMDpresence-present",undef) && $mode =~ /^(absent|gone)$/);
      $present = "present";
      $location = grep(/^$plocation$/,split /,/,$slocations) ? $plocation : "home";
      if ($presence eq "absent")
      {
        if (AttrNum($name,"HomeAutoArrival",0))
        {
          my $hour = HOMEMODE_hourMaker(AttrNum($name,"HomeAutoArrival",0));
          CommandDelete(undef,"atTmp_set_home_$name") if (IsDevice("atTmp_set_home_$name"));
          CommandDefine(undef,"atTmp_set_home_$name at +$hour set $name:FILTER=location=arrival location home");
          $location = "arrival";
        }
      }
      if ($option eq "asleep")
      {
        $namode = "armnight";
        $location = "bed";
      }
    }
    elsif ($option =~ /^(absent|gone)$/)
    {
      push @commands,AttrVal($name,"HomeCMDpresence-absent","") if (AttrVal($name,"HomeCMDpresence-absent",undef) && $mode !~ /^(absent|gone)$/);
      $namode = ReadingsVal($name,"anyoneElseAtHome","off") eq "off" ? "armaway" : "armhome";
      if (AttrNum($name,"HomeModeAbsentBelatedTime",0) && AttrVal($name,"HomeCMDmode-absent-belated",undef))
      {
        my $hour = HOMEMODE_hourMaker(AttrNum($name,"HomeModeAbsentBelatedTime",0));
        CommandDelete(undef,"atTmp_absent_belated_$name") if (IsDevice("atTmp_absent_belated_$name"));
        CommandDefine(undef,"atTmp_absent_belated_$name at +$hour {HOMEMODE_execCMDs_belated(\"$name\",\"HomeCMDmode-absent-belated\",\"$option\")}");
      }
    }
    HOMEMODE_ContactOpenCheckAfterModeChange($hash,$option,$mode) if ($hash->{SENSORSCONTACT} && $option && $mode ne $option);
    push @commands,AttrVal($name,"HomeCMDmode","") if ($mode && AttrVal($name,"HomeCMDmode",undef));
    push @commands,AttrVal($name,"HomeCMDmode-$option","") if (AttrVal($name,"HomeCMDmode-$option",undef));
    CommandSetReading(undef,"$name:FILTER=presence!=$present presence $present");
    CommandSet(undef,"$name:FILTER=location!=$location location $location");
    if (AttrNum($name,"HomeAutoAlarmModes",1))
    {
      CommandDelete(undef,"atTmp_modeAlarm_delayed_arm_$name") if (IsDevice("atTmp_modeAlarm_delayed_arm_$name"));
      CommandSet(undef,"$name:FILTER=modeAlarm!=$namode modeAlarm $namode");
    }
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,$cmd,$option);
    readingsBulkUpdate($hash,"prevMode",$mode);
    readingsBulkUpdate($hash,"state",$option);
    readingsEndUpdate($hash,1);
  }
  elsif ($cmd eq "modeAlarm-for-minutes")
  {
    $trans = $HOMEMODE_de?
      "$cmd benötigt zwei Parameter: einen modeAlarm und die Minuten":
      "$cmd needs two paramters: a modeAlarm and minutes";
    return $trans if (!$option || !$value);
    my $timer = $name."_alarmMode_for_timer_$option";
    my $time = HOMEMODE_hourMaker($value);
    CommandDelete(undef,$timer) if (IsDevice($timer));
    CommandDefine(undef,"$timer at +$time set $name:FILTER=modeAlarm!=$amode modeAlarm $amode");
    CommandSet(undef,"$name:FILTER=modeAlarm!=$option modeAlarm $option");
  }
  elsif ($cmd eq "dnd-for-minutes")
  {
    $trans = $HOMEMODE_de?
      "$cmd benötigt einen Paramter: Minuten":
      "$cmd needs one paramter: minutes";
    return $trans if (!$option);
    $trans = $HOMEMODE_de?
      "$name darf nicht im dnd Modus sein um diesen Modus für bestimmte Minuten zu setzen! Bitte deaktiviere den dnd Modus zuerst!":
      "$name can't be in dnd mode to turn dnd on for minutes! Please disable dnd mode first!";
    return $trans if (ReadingsVal($name,"dnd","off") eq "on");
    my $timer = $name."_dnd_for_timer";
    my $time = HOMEMODE_hourMaker($option);
    CommandDelete(undef,$timer) if (IsDevice($timer));
    CommandDefine(undef,"$timer at +$time set $name:FILTER=dnd!=off dnd off");
    CommandSet(undef,"$name:FILTER=dnd!=on dnd on");
  }
  elsif ($cmd eq "dnd")
  {
    push @commands,AttrVal($name,"HomeCMDdnd","") if (AttrVal($name,"HomeCMDdnd",undef));
    push @commands,AttrVal($name,"HomeCMDdnd-$option","") if (AttrVal($name,"HomeCMDdnd-$option",undef));
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,$cmd,$option);
    readingsBulkUpdate($hash,"state","dnd") if ($option eq "on");
    readingsBulkUpdate($hash,"state",$mode) if ($option ne "on");
    readingsEndUpdate($hash,1);
  }
  elsif ($cmd eq "location")
  {
    push @commands,AttrVal($name,"HomeCMDlocation","") if (AttrVal($name,"HomeCMDlocation",undef));
    push @commands,AttrVal($name,"HomeCMDlocation-$option","") if (AttrVal($name,"HomeCMDlocation-$option",undef));
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,"prevLocation",$plocation);
    readingsBulkUpdate($hash,$cmd,$option);
    readingsEndUpdate($hash,1);
  }
  elsif ($cmd eq "modeAlarm")
  {
    CommandDelete(undef,"atTmp_modeAlarm_delayed_arm_$name") if (IsDevice("atTmp_modeAlarm_delayed_arm_$name"));
    my $delay;
    if ($option =~ /^arm/ && AttrVal($name,"HomeModeAlarmArmDelay",0))
    {
      my @delays = split " ",AttrVal($name,"HomeModeAlarmArmDelay",0);
      if (defined $delays[1])
      {
        $delay = $delays[0] if ($option eq "armaway");
        $delay = $delays[1] if ($option eq "armnight");
        $delay = $delays[2] if ($option eq "armhome");
      }
      else
      {
        $delay = $delays[0];
      }
    }
    if ($delay)
    {
      my $hours = HOMEMODE_hourMaker(sprintf("%.2f",$delay / 60));
      CommandDefine(undef,"atTmp_modeAlarm_delayed_arm_$name at +$hours {HOMEMODE_set_modeAlarm(\"$name\",\"$option\",\"$amode\")}");
    }
    else
    {
      HOMEMODE_set_modeAlarm($name,$option,$amode);
    }
  }
  elsif ($cmd eq "anyoneElseAtHome")
  {
    $trans = $HOMEMODE_de?
      "Zulässige Werte für $cmd sind nur on oder off!":
      "Values for $cmd can only be on or off!";
    return $trans if ($option !~ /^(on|off)$/);
    push @commands,AttrVal($name,"HomeCMDanyoneElseAtHome","") if (AttrVal($name,"HomeCMDanyoneElseAtHome",undef));
    push @commands,AttrVal($name,"HomeCMDanyoneElseAtHome-$option","") if (AttrVal($name,"HomeCMDanyoneElseAtHome-$option",undef));
    if (AttrNum($name,"HomeAutoAlarmModes",1))
    {
      CommandSet(undef,"$name:FILTER=modeAlarm=armaway modeAlarm armhome") if ($option eq "on");
      CommandSet(undef,"$name:FILTER=modeAlarm=armhome modeAlarm armaway") if ($option eq "off");
    }
    readingsSingleUpdate($hash,"anyoneElseAtHome",$option,1);
  }
  elsif ($cmd eq "panic")
  {
    $trans = $HOMEMODE_de?
      "Zulässige Werte für $cmd sind nur on oder off!":
      "Values for $cmd can only be on or off!";
    return $trans if ($option !~ /^(on|off)$/);
    push @commands,AttrVal($name,"HomeCMDpanic","") if (AttrVal($name,"HomeCMDpanic",undef));
    push @commands,AttrVal($name,"HomeCMDpanic-$option","") if (AttrVal($name,"HomeCMDpanic-$option",undef));
    readingsSingleUpdate($hash,"panic",$option,1);
  }
  elsif ($cmd eq "updateInternalsForce")
  {
    HOMEMODE_updateInternals($hash,1);
  }
  elsif ($cmd eq "updateHomebridgeMapping")
  {
    HOMEMODE_HomebridgeMapping($hash);
  }
  HOMEMODE_execCMDs($hash,HOMEMODE_serializeCMD($hash,@commands)) if (@commands);
  return;
}

sub HOMEMODE_set_modeAlarm($$$)
{
  my ($name,$option,$amode) = @_;
  my $hash = $defs{$name};
  my $resident = $hash->{helper}{lar} ? $hash->{helper}{lar} : ReadingsVal($name,"lastActivityByResident","");
  delete $hash->{helper}{lar} if ($hash->{helper}{lar});
  my @commands;
  push @commands,AttrVal($name,"HomeCMDmodeAlarm","") if (AttrVal($name,"HomeCMDmodeAlarm",undef));
  push @commands,AttrVal($name,"HomeCMDmodeAlarm-$option","") if (AttrVal($name,"HomeCMDmodeAlarm-$option",undef));
  if ($option eq "confirm")
  {
    CommandDefine(undef,"atTmp_modeAlarm_confirm_$name at +00:00:30 setreading $name:FILTER=alarmState=confirmed alarmState $amode");
    readingsSingleUpdate($hash,"alarmState",$option."ed",1);
    HOMEMODE_execCMDs($hash,HOMEMODE_serializeCMD($hash,@commands),$resident) if (@commands);
  }
  else
  {
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,"prevModeAlarm",$amode);
    readingsBulkUpdate($hash,"modeAlarm",$option);
    readingsBulkUpdateIfChanged($hash,"alarmState",$option);
    readingsEndUpdate($hash,1);
    HOMEMODE_TriggerState($hash) if ($hash->{SENSORSCONTACT} || $hash->{SENSORSMOTION});
    HOMEMODE_execCMDs($hash,HOMEMODE_serializeCMD($hash,@commands),$resident) if (@commands);
  }
}

sub HOMEMODE_execCMDs_belated($$$)
{
  my ($name,$attrib,$option) = @_;
  return if (!AttrVal($name,$attrib,undef) || ReadingsVal($name,"mode","") ne $option);
  my $hash = $defs{$name};
  my @commands;
  push @commands,AttrVal($name,$attrib,"");
  HOMEMODE_execCMDs($hash,HOMEMODE_serializeCMD($hash,@commands)) if (@commands);
}

sub HOMEMODE_alarmTriggered($@)
{
  my ($hash,@triggers) = @_;
  my $name = $hash->{NAME};
  my @commands;
  my $text = HOMEMODE_makeHR($hash,0,@triggers);
  push @commands,AttrVal($name,"HomeCMDalarmTriggered","") if (AttrVal($name,"HomeCMDalarmTriggered",undef));
  readingsBeginUpdate($hash);
  readingsBulkUpdateIfChanged($hash,"alarmTriggered_ct",scalar @triggers);
  if ($text)
  {
    push @commands,AttrVal($name,"HomeCMDalarmTriggered-on","") if (AttrVal($name,"HomeCMDalarmTriggered-on",undef));
    readingsBulkUpdateIfChanged($hash,"alarmTriggered",join ",",@triggers);
    readingsBulkUpdateIfChanged($hash,"alarmTriggered_hr",$text);
    readingsBulkUpdateIfChanged($hash,"alarmState","alarm");
  }
  else
  {
    push @commands,AttrVal($name,"HomeCMDalarmTriggered-off","") if (AttrVal($name,"HomeCMDalarmTriggered-off",undef) && ReadingsVal($name,"alarmTriggered",""));
    readingsBulkUpdateIfChanged($hash,"alarmTriggered","");
    readingsBulkUpdateIfChanged($hash,"alarmTriggered_hr","");
    readingsBulkUpdateIfChanged($hash,"alarmState",ReadingsVal($name,"modeAlarm","disarm"));
  }
  readingsEndUpdate($hash,1);
  HOMEMODE_execCMDs($hash,HOMEMODE_serializeCMD($hash,@commands)) if (@commands && ReadingsAge($name,"modeAlarm","") > 5);
}

sub HOMEMODE_makeHR($$@)
{
  my ($hash,$noart,@names) = @_;
  my $name = $hash->{NAME};
  my @aliases;
  my $and = (split /\|/,AttrVal($name,"HomeTextAndAreIs","and|are|is"))[0];
  my $text;
  foreach (@names)
  {
    my $alias = $noart ? HOMEMODE_name2alias($_) : HOMEMODE_name2alias($_,1);
    push @aliases,$alias;
  }
  if (@aliases > 0)
  {
    my $alias = $aliases[0];
    $alias =~ s/^d/D/;
    $text = $alias;
    if (@aliases > 1)
    {
      for (my $i = 1; $i < @aliases; $i++)
      {
        $text .= " $and " if ($i == @aliases - 1);
        $text .= ", " if ($i < @aliases - 1);
        $text .= $aliases[$i];
      }
    }
  }
  $text = $text ? $text : "";
  return $text;
}

sub HOMEMODE_alarmTampered($@)
{
  my ($hash,@triggers) = @_;
  my $name = $hash->{NAME};
  my @commands;
  my $text = HOMEMODE_makeHR($hash,0,@triggers);
  push @commands,AttrVal($name,"HomeCMDalarmTampered","") if (AttrVal($name,"HomeCMDalarmTampered",undef));
  if ($text)
  {
    push @commands,AttrVal($name,"HomeCMDalarmTampered-on","") if (AttrVal($name,"HomeCMDalarmTampered-on",undef));
  }
  else
  {
    push @commands,AttrVal($name,"HomeCMDalarmTampered-off","") if (AttrVal($name,"HomeCMDalarmTampered-off",undef));
  }
  HOMEMODE_execCMDs($hash,HOMEMODE_serializeCMD($hash,@commands)) if (@commands);
}

sub HOMEMODE_RESIDENTS($;$)
{
  my ($hash,$dev) = @_;
  $dev = $hash->{DEF} if (!$dev);
  my $name = $hash->{NAME};
  my $events = deviceEvents($defs{$dev},1);
  my $devtype = $defs{$dev}->{TYPE};
  my $lad = ReadingsVal($name,"lastActivityByResident","");
  my $mode;
  if (grep /^state:\s/,@{$events})
  {
    foreach (@{$events})
    {
      my $m = $_;
      $m =~ s/.*:\s//;
      next if (!grep /^$m$/,split /,/,$HOMEMODE_UserModesAll);
      $mode = $m;
    }
  }
  if ($mode && $devtype eq "RESIDENTS")
  {
    $mode = $mode eq "home" && AttrNum($name,"HomeAutoDaytime",1) ? HOMEMODE_DayTime($hash) : $mode;
    CommandSet(undef,"$name:FILTER=mode!=$mode mode $mode");
  }
  elsif ($devtype =~ /^ROOMMATE|GUEST$/)
  {
    my @commands;
    if (grep /^wayhome:\s1$/,@{$events})
    {
      readingsSingleUpdate($hash,"lastActivityByResident",$dev,1);
      CommandSet(undef,"$name:FILTER=location!=wayhome location wayhome") if (ReadingsVal($name,"state","") =~ /^absent|gone$/);
    }
    elsif (grep /^wayhome:\s0$/,@{$events})
    {
      readingsSingleUpdate($hash,"lastActivityByResident",$dev,1);
      my $rx = $hash->{RESIDENTS};
      $rx =~ s/,/|/g;
      CommandSet(undef,"$name:FILTER=location!=underway location underway") if (ReadingsVal($name,"state","") =~ /^absent|gone$/ && !devspec2array("$rx:FILTER=wayhome=1"));
    }
    if (grep /^presence:\sabsent$/,@{$events})
    {
      push @commands,AttrVal($name,"HomeCMDpresence-absent-resident","") if (AttrVal($name,"HomeCMDpresence-absent-resident",undef));
      push @commands,AttrVal($name,"HomeCMDpresence-absent-$dev","") if (AttrVal($name,"HomeCMDpresence-absent-$dev",undef));
      readingsSingleUpdate($hash,"lastAbsentByResident",$dev,1);
    }
    elsif (grep /^presence:\spresent$/,@{$events})
    {
      push @commands,AttrVal($name,"HomeCMDpresence-present-resident","") if (AttrVal($name,"HomeCMDpresence-present-resident",undef));
      push @commands,AttrVal($name,"HomeCMDpresence-present-$dev","") if (AttrVal($name,"HomeCMDpresence-present-$dev",undef));
      readingsSingleUpdate($hash,"lastPresentByResident",$dev,1);
    }
    if ($mode)
    {
      if ($mode =~ /^home|awoken$/ && AttrNum($name,"HomeAutoAwoken",0))
      {
        if ($mode eq "home" && ReadingsVal($dev,"lastState","") eq "asleep")
        {
          AnalyzeCommandChain(undef,"sleep 0.1; set $dev:FILTER=state!=awoken state awoken");
          return;
        }
        elsif ($mode eq "awoken")
        {
          my $hours = HOMEMODE_hourMaker(AttrNum($name,"HomeAutoAwoken",0));
          CommandDelete(undef,"atTmp_awoken_".$dev."_$name") if (IsDevice("atTmp_awoken_".$dev."_$name"));
          CommandDefine(undef,"atTmp_awoken_".$dev."_$name at +$hours set $dev:FILTER=state=awoken state home");
        }
      }
      if ($mode eq "home" && ReadingsVal($dev,"lastState","") =~ /^(absent|[gn]one)$/ && AttrNum($name,"HomeAutoArrival",0))
      {
        my $hours = HOMEMODE_hourMaker(AttrNum($name,"HomeAutoArrival",0));
        AnalyzeCommandChain(undef,"sleep 0.1; set $dev:FILTER=location!=arrival location arrival");
        CommandDelete(undef,"atTmp_location_home_".$dev."_$name") if (IsDevice("atTmp_location_home_".$dev."_$name"));
        CommandDefine(undef,"atTmp_location_home_".$dev."_$name at +$hours set $dev:FILTER=location=arrival location home");
      }
      if ($mode eq "gotosleep" && AttrNum($name,"HomeAutoAsleep",0))
      {
        my $hours = HOMEMODE_hourMaker(AttrNum($name,"HomeAutoAsleep",0));
        CommandDelete(undef,"atTmp_asleep_".$dev."_$name") if (IsDevice("atTmp_asleep_".$dev."_$name"));
        CommandDefine(undef,"atTmp_asleep_".$dev."_$name at +$hours set $dev:FILTER=state=gotosleep state asleep");
      }
      push @commands,AttrVal($name,"HomeCMDmode-$mode-resident","") if (AttrVal($name,"HomeCMDmode-$mode-resident",undef));
      push @commands,AttrVal($name,"HomeCMDmode-$mode-$dev","") if (AttrVal($name,"HomeCMDmode-$mode-$dev",undef));
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash,"lastActivityByResident",$dev);
      readingsBulkUpdate($hash,"lastAsleepByResident",$dev) if ($mode eq "asleep");
      readingsBulkUpdate($hash,"lastAwokenByResident",$dev) if ($mode eq "awoken");
      readingsBulkUpdate($hash,"lastGoneByResident",$dev) if ($mode =~ /^(gone|none)$/);
      readingsBulkUpdate($hash,"lastGotosleepByResident",$dev) if ($mode eq "gotosleep");
      readingsBulkUpdate($hash,"prevActivityByResident",$lad);
      readingsEndUpdate($hash,1);
      HOMEMODE_ContactOpenCheckAfterModeChange($hash,undef,undef,$dev);
    }
    if (@commands)
    {
      my $delay = AttrNum($name,"HomeResidentCmdDelay",1);
      my $cmd = encode_base64(HOMEMODE_serializeCMD($hash,@commands),"");
      InternalTimer(gettimeofday() + $delay,"HOMEMODE_execUserCMDs","$name|$cmd|$dev");
    }
  }
  return;
}

sub HOMEMODE_Attributes($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my @attribs;
  push @attribs,"disable:1,0";
  push @attribs,"disabledForIntervals";
  push @attribs,"HomeAdvancedDetails:none,detail,both,room";
  push @attribs,"HomeAdvancedUserAttr:1,0";
  push @attribs,"HomeAutoAlarmModes:0,1";
  push @attribs,"HomeAutoArrival";
  push @attribs,"HomeAutoAsleep";
  push @attribs,"HomeAutoAwoken";
  push @attribs,"HomeAutoDaytime:0,1";
  push @attribs,"HomeAutoPresence:1,0";
  push @attribs,"HomeCMDalarmSmoke:textField-long";
  push @attribs,"HomeCMDalarmSmoke-on:textField-long";
  push @attribs,"HomeCMDalarmSmoke-off:textField-long";
  push @attribs,"HomeCMDalarmTriggered:textField-long";
  push @attribs,"HomeCMDalarmTriggered-off:textField-long";
  push @attribs,"HomeCMDalarmTriggered-on:textField-long";
  push @attribs,"HomeCMDalarmTampered:textField-long";
  push @attribs,"HomeCMDalarmTampered-off:textField-long";
  push @attribs,"HomeCMDalarmTampered-on:textField-long";
  push @attribs,"HomeCMDanyoneElseAtHome:textField-long";
  push @attribs,"HomeCMDanyoneElseAtHome-on:textField-long";
  push @attribs,"HomeCMDanyoneElseAtHome-off:textField-long";
  push @attribs,"HomeCMDbatteryLow:textField-long";
  push @attribs,"HomeCMDcontact:textField-long";
  push @attribs,"HomeCMDcontactClosed:textField-long";
  push @attribs,"HomeCMDcontactOpen:textField-long";
  push @attribs,"HomeCMDcontactDoormain:textField-long";
  push @attribs,"HomeCMDcontactDoormainClosed:textField-long";
  push @attribs,"HomeCMDcontactDoormainOpen:textField-long";
  push @attribs,"HomeCMDcontactOpenWarning1:textField-long";
  push @attribs,"HomeCMDcontactOpenWarning2:textField-long";
  push @attribs,"HomeCMDcontactOpenWarningLast:textField-long";
  push @attribs,"HomeCMDdaytime:textField-long";
  push @attribs,"HomeCMDdnd:textField-long";
  push @attribs,"HomeCMDdnd-off:textField-long";
  push @attribs,"HomeCMDdnd-on:textField-long";
  push @attribs,"HomeCMDevent:textField-long";
  push @attribs,"HomeCMDfhemDEFINED:textField-long";
  push @attribs,"HomeCMDfhemINITIALIZED:textField-long";
  push @attribs,"HomeCMDfhemSAVE:textField-long";
  push @attribs,"HomeCMDfhemUPDATE:textField-long";
  push @attribs,"HomeCMDicewarning:textField-long";
  push @attribs,"HomeCMDicewarning-on:textField-long";
  push @attribs,"HomeCMDicewarning-off:textField-long";
  push @attribs,"HomeCMDlocation:textField-long";
  foreach (split /,/,$HOMEMODE_Locations)
  {
    push @attribs,"HomeCMDlocation-$_:textField-long";
  }
  push @attribs,"HomeCMDmode:textField-long";
  push @attribs,"HomeCMDmode-absent-belated:textField-long";
  foreach (split /,/,$HOMEMODE_UserModesAll)
  {
    push @attribs,"HomeCMDmode-$_:textField-long";
    push @attribs,"HomeCMDmode-$_-resident:textField-long";
  }
  push @attribs,"HomeCMDmodeAlarm:textField-long";
  foreach (split /,/,$HOMEMODE_AlarmModes)
  {
    push @attribs,"HomeCMDmodeAlarm-$_:textField-long";
  }
  push @attribs,"HomeCMDmotion:textField-long";
  push @attribs,"HomeCMDmotion-on:textField-long";
  push @attribs,"HomeCMDmotion-off:textField-long";
  push @attribs,"HomeCMDpanic:textField-long";
  push @attribs,"HomeCMDpanic-on:textField-long";
  push @attribs,"HomeCMDpanic-off:textField-long";
  push @attribs,"HomeCMDpresence-absent:textField-long";
  push @attribs,"HomeCMDpresence-present:textField-long";
  push @attribs,"HomeCMDpresence-absent-device:textField-long";
  push @attribs,"HomeCMDpresence-present-device:textField-long";
  push @attribs,"HomeCMDpresence-absent-resident:textField-long";
  push @attribs,"HomeCMDpresence-present-resident:textField-long";
  push @attribs,"HomeCMDpublic-ip-change:textField-long";
  push @attribs,"HomeCMDseason:textField-long";
  push @attribs,"HomeCMDtwilight:textField-long";
  push @attribs,"HomeCMDtwilight-sr:textField-long";
  push @attribs,"HomeCMDtwilight-sr_astro:textField-long";
  push @attribs,"HomeCMDtwilight-sr_civil:textField-long";
  push @attribs,"HomeCMDtwilight-sr_indoor:textField-long";
  push @attribs,"HomeCMDtwilight-sr_weather:textField-long";
  push @attribs,"HomeCMDtwilight-ss:textField-long";
  push @attribs,"HomeCMDtwilight-ss_astro:textField-long";
  push @attribs,"HomeCMDtwilight-ss_civil:textField-long";
  push @attribs,"HomeCMDtwilight-ss_indoor:textField-long";
  push @attribs,"HomeCMDtwilight-ss_weather:textField-long";
  push @attribs,"HomeCMDuwz-warn:textField-long";
  push @attribs,"HomeCMDuwz-warn-begin:textField-long";
  push @attribs,"HomeCMDuwz-warn-end:textField-long";
  push @attribs,"HomeDaytimes:textField-long";
  push @attribs,"HomeEventsHolidayDevices";
  push @attribs,"HomeIcewarningOnOffTemps";
  push @attribs,"HomeLanguage:DE,EN";
  push @attribs,"HomeModeAlarmArmDelay";
  push @attribs,"HomeModeAbsentBelatedTime";
  push @attribs,"HomeAtTmpRoom";
  push @attribs,"HomePresenceDeviceType";
  push @attribs,"HomePublicIpCheckInterval";
  push @attribs,"HomeResidentCmdDelay";
  push @attribs,"HomeSeasons:textField-long";
  push @attribs,"HomeSensorAirpressure";
  push @attribs,"HomeSensorHumidityOutside";
  push @attribs,"HomeSensorTemperatureOutside";
  push @attribs,"HomeSensorWindspeed";
  push @attribs,"HomeSensorsBattery";
  push @attribs,"HomeSensorsBatteryLowPercentage";
  push @attribs,"HomeSensorsBatteryReading";
  push @attribs,"HomeSensorsContact";
  push @attribs,"HomeSensorsContactReadings";
  push @attribs,"HomeSensorsContactValues";
  push @attribs,"HomeSensorsContactOpenTimeDividers";
  push @attribs,"HomeSensorsContactOpenTimeMin";
  push @attribs,"HomeSensorsContactOpenTimes";
  push @attribs,"HomeSensorsLuminance";
  push @attribs,"HomeSensorsLuminanceReading";
  push @attribs,"HomeSensorsMotion";
  push @attribs,"HomeSensorsMotionReadings";
  push @attribs,"HomeSensorsMotionValues";
  push @attribs,"HomeSensorsPowerEnergy";
  push @attribs,"HomeSensorsPowerEnergyReadings";
  push @attribs,"HomeSensorsSmoke";
  push @attribs,"HomeSensorsSmokeReading";
  push @attribs,"HomeSensorsSmokeValue";
  push @attribs,"HomeSpecialLocations";
  push @attribs,"HomeSpecialModes";
  push @attribs,"HomeTextAndAreIs";
  push @attribs,"HomeTextClosedOpen";
  push @attribs,"HomeTextRisingConstantFalling";
  push @attribs,"HomeTextNosmokeSmoke";
  push @attribs,"HomeTextTodayTomorrowAfterTomorrow";
  push @attribs,"HomeTextWeatherForecastToday:textField-long";
  push @attribs,"HomeTextWeatherForecastTomorrow:textField-long";
  push @attribs,"HomeTextWeatherForecastInSpecDays:textField-long";
  push @attribs,"HomeTextWeatherNoForecast:textField-long";
  push @attribs,"HomeTextWeatherLong:textField-long";
  push @attribs,"HomeTextWeatherShort:textField-long";
  push @attribs,"HomeTrendCalcAge:900,1800,2700,3600";
  push @attribs,"HomeTriggerAnyoneElseAtHome";
  push @attribs,"HomeTriggerPanic";
  push @attribs,"HomeTwilightDevice";
  push @attribs,"HomeUWZ";
  push @attribs,"HomeYahooWeatherDevice";
  push @attribs,$readingFnAttributes;
  return join(" ",@attribs);
}

sub HOMEMODE_userattr($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $adv = HOMEMODE_AttrCheck($hash,"HomeAdvancedUserAttr",0);
  my @userattrAll;
  my @homeattr;
  my @stayattr;
  my $specialevents = HOMEMODE_AttrCheck($hash,"HomeEventsHolidayDevices");
  my $specialmodes = HOMEMODE_AttrCheck($hash,"HomeSpecialModes");
  my $speciallocations = HOMEMODE_AttrCheck($hash,"HomeSpecialLocations");
  my $daytimes = HOMEMODE_AttrCheck($hash,"HomeDaytimes",$HOMEMODE_Daytimes);
  my $seasons = HOMEMODE_AttrCheck($hash,"HomeSeasons",$HOMEMODE_Seasons);
  foreach (split " ",AttrVal($name,"userattr",""))
  {
    if ($_ =~ /^Home/)
    {
      push @homeattr,$_;
    }
    else
    {
      push @stayattr,$_;
    }
  }
  foreach (split /,/,$specialmodes)
  {
    push @userattrAll,"HomeCMDmode-$_";
  }
  foreach (split /,/,$speciallocations)
  {
    push @userattrAll,"HomeCMDlocation-$_";
  }
  foreach my $cal (devspec2array($specialevents))
  {
    my $events = HOMEMODE_HolidayEvents($cal);
    push @userattrAll,"HomeCMDevent-$cal-each";
    if ($adv)
    {
      foreach my $evt (@{$events})
      {
        push @userattrAll,"HomeCMDevent-$cal-$evt-begin";
        push @userattrAll,"HomeCMDevent-$cal-$evt-end";
      }
    }
  }
  foreach my $resident (split /,/,$hash->{RESIDENTS})
  {
    my $devtype = IsDevice($resident) ? $defs{$resident}->{TYPE} : "";
    next if (!$devtype);
    if ($adv)
    {
      my $states = "absent";
      $states .= ",$HOMEMODE_UserModesAll" if ($devtype eq "ROOMMATE");
      $states .= ",home,$HOMEMODE_UserModes" if ($devtype eq "GUEST");
      foreach (split /,/,$states)
      {
        push @userattrAll,"HomeCMDmode-$_-$resident";
      }
      push @userattrAll,"HomeCMDpresence-absent-$resident";
      push @userattrAll,"HomeCMDpresence-present-$resident";
    }
    my @presdevs = @{$hash->{helper}{presdevs}{$resident}} if ($hash->{helper}{presdevs}{$resident});
    if (@presdevs)
    {
      my $count;
      my $numbers;
      foreach (@presdevs)
      {
        $count++;
        $numbers .= "," if ($numbers);
        $numbers .= $count;
      }
      push @userattrAll,"HomePresenceDeviceAbsentCount-$resident:$numbers";
      push @userattrAll,"HomePresenceDevicePresentCount-$resident:$numbers";
      if ($adv)
      {
        foreach (@presdevs)
        {
          push @userattrAll,"HomeCMDpresence-absent-$resident-device";
          push @userattrAll,"HomeCMDpresence-present-$resident-device";
          push @userattrAll,"HomeCMDpresence-absent-$resident-$_";
          push @userattrAll,"HomeCMDpresence-present-$resident-$_";
        }
      }
    }
  }
  foreach (split " ",$daytimes)
  {
    my $text = (split /\|/)[1];
    my $d = "HomeCMDdaytime-$text";
    my $m = "HomeCMDmode-$text";
    push @userattrAll,$d if (!grep /^$d$/,@userattrAll);
    push @userattrAll,$m if (!grep /^$m$/,@userattrAll);
  }
  foreach (split " ",$seasons)
  {
    my $text = (split /\|/)[1];
    my $s = "HomeCMDseason-$text";
    push @userattrAll,$s if (!grep /^$s$/,@userattrAll);
  }
  my @list;
  foreach my $attrib (@userattrAll)
  {
    $attrib = $attrib =~ /^.+:.+$/ ? $attrib : "$attrib:textField-long";
    push @list,$attrib if (!grep /^$attrib$/,@list);
  }
  my $lo = join " ",sort @homeattr;
  my $ln = join " ",sort @list;
  return if ($lo eq $ln);
  foreach (@stayattr)
  {
    push @list,$_;
  }
  CommandAttr(undef,"$name userattr ".join " ",sort @list);
  return;
}

sub HOMEMODE_cleanUserattr($$;$)
{
  my ($hash,$devs,$newdevs) = @_;
  my $name = $hash->{NAME};
  my @devspec = devspec2array($devs);
  return if (!@devspec);
  my @newdevspec = devspec2array($newdevs) if ($newdevs);
  foreach my $dev (@devspec)
  {
    my $userattr = AttrVal($dev,"userattr","");
    if ($userattr)
    {
      my @stayattr;
      foreach (split " ",$userattr)
      {
        if ($_ =~ /^Home/)
        {
          $_ =~ s/:.*//;
          CommandDeleteAttr(undef,"$dev $_") if ((AttrVal($dev,$_,"") && !@newdevspec) || (AttrVal($dev,$_,"") && @newdevspec && !grep /^$dev$/,@newdevspec));
          next;
        }
        push @stayattr,$_ if (!grep /^$_$/,@stayattr);
      }
      if (@stayattr)
      {
        CommandAttr(undef,"$dev userattr ".join(" ",@stayattr));
      }
      else
      {
        CommandDeleteAttr(undef,"$dev userattr");
      }
    }
  }
  return;
}

sub HOMEMODE_Attr(@)
{
  my ($cmd,$name,$attr_name,$attr_value) = @_;
  my $hash = $defs{$name};
  delete $hash->{helper}{lastChangedAttr};
  delete $hash->{helper}{lastChangedAttrValue};
  my $attr_value_old = AttrVal($name,$attr_name,"");
  $hash->{helper}{lastChangedAttr} = $attr_name;
  my $trans;
  if ($cmd eq "set")
  {
    $hash->{helper}{lastChangedAttrValue} = $attr_value;
    if ($attr_name =~ /^(HomeAutoAwoken|HomeAutoAsleep|HomeAutoArrival|HomeModeAbsentBelatedTime)$/)
    {
      $trans = $HOMEMODE_de?
        "Ungültiger Wert $attr_value für Attribut $attr_name. Muss eine Zahl von 0 bis 5999.99 sein.":
        "Invalid value $attr_value for attribute $attr_name. Must be a number from 0 to 5999.99.";
      return $trans if ($attr_value !~ /^(\d{1,4})(\.\d{1,2})?$/ || $1 >= 6000 || $1 < 0);
    }
    elsif ($attr_name eq "HomeLanguage")
    {
      $trans = $HOMEMODE_de?
        "Ungültiger Wert $attr_value für Attribut $attr_name. Kann nur \"EN\" oder \"DE\" sein, Vorgabewert ist Sprache aus global.":
        "Invalid value $attr_value for attribute $attr_name. Must be \"EN\" or \"DE\", default is language from global.";
      return $trans if ($attr_value !~ /^(DE|EN)$/);
      $HOMEMODE_de = 1 if ($attr_value eq "DE");
      $HOMEMODE_de = undef if ($attr_value eq "EN");
    }
    elsif ($attr_name eq "HomeAdvancedDetails")
    {
      $trans = $HOMEMODE_de?
        "Ungültiger Wert $attr_value für Attribut $attr_name. Kann nur \"none\", \"detail\", \"both\" oder \"room\" sein, Vorgabewert ist \"none\".":
        "Invalid value $attr_value for attribute $attr_name. Must be \"none\", \"detail\", \"both\" or \"room\", default is \"none\".";
      return $trans if ($attr_value !~ /^(none|detail|both|room)$/);
      if ($attr_value eq "detail")
      {
        $modules{HOMEMODE}->{FW_deviceOverview} = 1;
        $modules{HOMEMODE}->{FW_addDetailToSummary} = 0;
      }
      else
      {
        $modules{HOMEMODE}->{FW_deviceOverview} = 1;
        $modules{HOMEMODE}->{FW_addDetailToSummary} = 1;
      }
    }
    elsif ($attr_name =~ /^(disable|HomeAdvancedUserAttr|HomeAutoDaytime|HomeAutoAlarmModes|HomeAutoPresence)$/)
    {
      $trans = $HOMEMODE_de?
        "Ungültiger Wert $attr_value für Attribut $attr_name. Kann nur 1 oder 0 sein, Vorgabewert ist 0.":
        "Invalid value $attr_value for attribute $attr_name. Must be 1 or 0, default is 0.";
      return $trans if ($attr_value !~ /^[01]$/);
      RemoveInternalTimer($hash) if ($attr_name eq "disable" && $attr_value == 1);
      HOMEMODE_GetUpdate($hash) if ($attr_name eq "disable" && !$attr_value);
      HOMEMODE_updateInternals($hash,1) if ($attr_name =~ /^(HomeAdvancedUserAttr|HomeAutoPresence)$/ && $init_done);
    }
    elsif ($attr_name =~ /^HomeCMD/ && $init_done)
    {
      if ($attr_value_old ne $attr_value)
      {
        my $err = perlSyntaxCheck(HOMEMODE_replacePlaceholders($hash,$attr_value));
        return $err if ($err);
      }
    }
    elsif ($attr_name eq "HomeEventsHolidayDevices" && $init_done)
    {
      my $wd = HOMEMODE_CheckHolidayDevices($attr_value);
      if ($wd)
      {
        $trans = $HOMEMODE_de?
          "Ungültige holiday Geräte gefunden: ":
          "Invalid holiday device(s) found: ";
        return $trans.join(",",@{$wd});
      }
      else
      {
        HOMEMODE_updateInternals($hash);
      }
    }
    elsif ($attr_name =~ /^(HomePresenceDeviceType)$/ && $init_done)
    {
      $trans = $HOMEMODE_de?
        "$attr_value muss ein gültiger TYPE sein":
        "$attr_value must be a valid TYPE";
      return $trans if (!HOMEMODE_CheckIfIsValidDevspec("TYPE=$attr_value","presence"));
      HOMEMODE_updateInternals($hash,1);
    }
    elsif ($attr_name =~ /^(HomeSensorsContactReadings|HomeSensorsMotionReadings|HomeSensorsSmokeReading)$/)
    {
      $trans = $HOMEMODE_de?
        "Ungültiger Wert $attr_value für Attribut $attr_name. Es werden 2 Leerzeichen separierte Readings benötigt! z.B. state sabotageError":
        "Invalid value $attr_value for attribute $attr_name. You have to provide at least 2 space separated readings, e.g. state sabotageError";
      return $trans if ($attr_value !~ /^[\w\-\.]+\s[\w\-\.]+$/);
    }
    elsif ($attr_name =~ /^(HomeSensorsContactValues|HomeSensorsMotionValues|HomeSensorsSmokeValue)$/)
    {
      $trans = $HOMEMODE_de?
        "Ungültiger Wert $attr_value für Attribut $attr_name. Es wird wenigstens ein Wert oder mehrere Pipe separierte Readings benötigt! z.B. open|tilted|on":
        "Invalid value $attr_value for attribute $attr_name. You have to provide at least one value or more values pipe separated, e.g. open|tilted|on";
      return $trans if ($attr_value !~ /^[\w\-\+\*\.\(\)]+(\|[\w\-\+\*\.\(\)]+){0,}$/i);
    }
    elsif ($attr_name eq "HomeIcewarningOnOffTemps")
    {
      $trans = $HOMEMODE_de?
        "Ungültiger Wert $attr_value für Attribut $attr_name. Es werden 2 Leerzeichen separierte Temperaturen benötigt, z.B. -0.1 2.5":
        "Invalid value $attr_value for attribute $attr_name. You have to provide 2 space separated temperatures, e.g. -0.1 2.5";
      return $trans if ($attr_value !~ /^-?\d{1,2}(\.\d)?\s-?\d{1,2}(\.\d)?$/);
    }
    elsif ($attr_name eq "HomeSensorsContactOpenTimeDividers")
    {
      $trans = $HOMEMODE_de?
        "Ungültiger Wert $attr_value für Attribut $attr_name. Es werden Leerzeichen separierte Zahlen für jede Jahreszeit (aus Attribut HomeSeasons) benötigt, z.B. 2 1 2 3.333":
        "Invalid value $attr_value for attribute $attr_name. You have to provide space separated numbers for each season in order of the seasons provided in attribute HomeSeasons, e.g. 2 1 2 3.333";
      return $trans if ($attr_value !~ /^\d{1,2}(\.\d{1,3})?(\s\d{1,2}(\.\d{1,3})?){0,}$/);
      my @times = split " ",$attr_value;
      my $s = scalar split " ",AttrVal($name,"HomeSeasons",$HOMEMODE_Seasons);
      my $t = scalar @times;
      $trans = $HOMEMODE_de?
        "Anzahl von $attr_name Werten ($t) ungleich zu den verfügbaren Jahreszeiten ($s) im Attribut HomeSeasons!":
        "Number of $attr_name values ($t) not matching the number of available seasons ($s) in attribute HomeSeasons!";
      return $trans if ($s != $t);
      foreach (@times)
      {
        $trans = $HOMEMODE_de?
          "Teiler dürfen nicht 0 sein, denn Division durch 0 ist nicht definiert!":
          "Dividers can't be zero, because division by zero is not defined!";
        return $trans if ($_ == 0);
      }
    }
    elsif ($attr_name eq "HomeSensorsContactOpenTimeMin")
    {
      $trans = $HOMEMODE_de?
        "Ungültiger Wert $attr_value für Attribut $attr_name. Zahlen von 1 bis 9.9 sind nur erlaubt!":
        "Invalid value $attr_value for attribute $attr_name. Numbers from 1 to 9.9 are allowed only!";
      return $trans if ($attr_value !~ /^[1-9](\.\d)?$/);
    }
    elsif ($attr_name eq "HomeSensorsContactOpenTimes")
    {
      $trans = $HOMEMODE_de?
        "Ungültiger Wert $attr_value für Attribut $attr_name. Es werden Leerzeichen separierte Zahlen benötigt, z.B. 5 10 15 17.5":
        "Invalid value $attr_value for attribute $attr_name. You have to provide space separated numbers, e.g. 5 10 15 17.5";
      return $trans if ($attr_value !~ /^\d{1,4}(\.\d)?((\s\d{1,4}(\.\d)?)?){0,}$/);
      foreach (split " ",$attr_value)
      {
        $trans = $HOMEMODE_de?
          "Teiler dürfen nicht 0 sein, denn Division durch 0 ist nicht definiert!":
          "Dividers can't be zero, because division by zero is not defined!";
        return $trans if ($_ == 0);
      }
    }
    elsif ($attr_name eq "HomeResidentCmdDelay")
    {
      $trans = $HOMEMODE_de?
        "Ungültiger Wert $attr_value für Attribut $attr_name. Zahlen von 0 bis 9999 sind nur erlaubt!":
        "Invalid value $attr_value for attribute $attr_name. Numbers from 0 to 9999 are allowed only!";
      return $trans if ($attr_value !~ /^\d{1,4}$/);
    }
    elsif ($attr_name =~ /^(HomeSpecialModes|HomeSpecialLocations)$/ && $init_done)
    {
      $trans = $HOMEMODE_de?
        "Ungültiger Wert $attr_value für Attribut $attr_name. Muss eine Komma separierte Liste von Wörtern sein!":
        "Invalid value $attr_value for attribute $attr_name. Must be a comma separated list of words!";
      return $trans if ($attr_value !~ /^[\w\-äöüß\.]+(,[\w\-äöüß\.]+){0,}$/i);
      HOMEMODE_userattr($hash);
    }
    elsif ($attr_name eq "HomePublicIpCheckInterval")
    {
      $trans = $HOMEMODE_de?
        "Ungültiger Wert $attr_value für Attribut $attr_name. Muss eine Zahl von 1 bis 99999 für das Interval in Minuten sein!":
        "Invalid value $attr_value for attribute $attr_name. Must be a number from 1 to 99999 for interval in minutes!";
      return $trans if ($attr_value !~ /^\d{1,5}$/);
    }
    elsif ($attr_name =~ /^(HomeSensorsContact|HomeSensorsMotion|HomeSensorsSmoke)$/ && $init_done)
    {
      $trans = $HOMEMODE_de?
        "$attr_value muss ein gültiger Devspec sein!":
        "$attr_value must be a valid devspec!";
      return $trans if (!HOMEMODE_CheckIfIsValidDevspec($attr_value));
      HOMEMODE_updateInternals($hash,1) if ($attr_value ne $attr_value_old);
    }
    elsif ($attr_name eq "HomeSensorsPowerEnergy" && $init_done)
    {
      my ($p,$e) = split " ",AttrVal($name,"HomeSensorsPowerEnergyReadings","power energy");
      $trans = $HOMEMODE_de?
        "$attr_value muss ein gültiger Devspec mit $p und $e Readings sein!":
        "$attr_value must be a valid devspec with $p and $e readings!";
      return $trans if (!HOMEMODE_CheckIfIsValidDevspec($attr_value,$p) || !HOMEMODE_CheckIfIsValidDevspec($attr_value,$e));
      HOMEMODE_updateInternals($hash);
    }
    elsif ($attr_name eq "HomeTwilightDevice" && $init_done)
    {
      $trans = $HOMEMODE_de?
        "$attr_value muss ein gültiges Gerät vom TYPE Twilight sein!":
        "$attr_value must be a valid device of TYPE Twilight!";
      return $trans if (!HOMEMODE_CheckIfIsValidDevspec("$attr_value:FILTER=TYPE=Twilight"));
      if ($attr_value_old ne $attr_value)
      {
        CommandDeleteReading(undef,"$name light|twilight|twilightEvent");
        HOMEMODE_updateInternals($hash);
      }
    }
    elsif ($attr_name eq "HomeYahooWeatherDevice" && $init_done)
    {
      $trans = $HOMEMODE_de?
        "$attr_value muss ein gültiges Gerät vom TYPE Weather sein!":
        "$attr_value must be a valid device of TYPE Weather!";
      return $trans if (!HOMEMODE_CheckIfIsValidDevspec("$attr_value:FILTER=TYPE=Weather"));
      if ($attr_value_old ne $attr_value)
      {
        CommandDeleteReading(undef,"$name condition|wind_chill");
        CommandDeleteReading(undef,"$name pressure") if (!AttrVal($name,"HomeSensorAirpressure",undef));
        CommandDeleteReading(undef,"$name wind") if (!AttrVal($name,"HomeSensorWindspeed",undef));
        CommandDeleteReading(undef,"$name temperature") if (!AttrVal($name,"HomeSensorTemperatureOutside",undef));
        CommandDeleteReading(undef,"$name humidity") if (!AttrVal($name,"HomeSensorHumidityOutside",undef));
        HOMEMODE_updateInternals($hash);
      }
    }
    elsif ($attr_name eq "HomeSensorTemperatureOutside" && $init_done)
    {
      $trans = $HOMEMODE_de?
        "$attr_value muss ein gültiger Devspec mit temperature Reading sein!":
        "$attr_value must be a valid device with temperature reading!";
      return $trans if (!HOMEMODE_CheckIfIsValidDevspec($attr_value,"temperature"));
      CommandDeleteAttr(undef,"$name HomeSensorHumidityOutside") if (AttrVal($name,"HomeSensorHumidityOutside",undef) && $attr_value eq AttrVal($name,"HomeSensorHumidityOutside",undef));
      if ($attr_value_old ne $attr_value)
      {
        CommandDeleteReading(undef,"$name temperature") if (!AttrVal($name,"HomeYahooWeatherDevice",undef));
        HOMEMODE_updateInternals($hash);
      }
    }
    elsif ($attr_name eq "HomeSensorHumidityOutside" && $init_done)
    {
      $trans = $HOMEMODE_de?
        "Dieses Attribut ist wegzulassen wenn es den gleichen Wert haben sollte wie HomeSensorTemperatureOutside!":
        "You have to omit this attribute if it should have the same value like HomeSensorTemperatureOutside!";
      return $trans if ($attr_value eq AttrVal($name,"HomeSensorTemperatureOutside",undef));
      $trans = $HOMEMODE_de?
        "$attr_value muss ein gültiger Devspec mit humidity Reading sein!":
        "$attr_value must be a valid device with humidity reading!";
      return $trans if (!HOMEMODE_CheckIfIsValidDevspec($attr_value,"humidity"));
      if ($attr_value_old ne $attr_value)
      {
        CommandDeleteReading(undef,"$name humidity") if (!AttrVal($name,"HomeYahooWeatherDevice",undef));
        HOMEMODE_updateInternals($hash);
      }
    }
    elsif ($attr_name eq "HomeDaytimes" && $init_done)
    {
      $trans = $HOMEMODE_de?
        "$attr_value für $attr_name muss eine Leerzeichen separierte Liste aus Uhrzeit|Text Paaren sein! z.B. $HOMEMODE_Daytimes":
        "$attr_value for $attr_name must be a space separated list of time|text pairs! e.g. $HOMEMODE_Daytimes";
      return $trans if ($attr_value !~ /^([0-2]\d:[0-5]\d\|[\w\-äöüß\.]+)(\s[0-2]\d:[0-5]\d\|[\w\-äöüß\.]+){0,}$/i);
      if ($attr_value_old ne $attr_value)
      {
        my @ts;
        foreach (split " ",$attr_value)
        {
          my $time = (split /\|/)[0];
          my ($h,$m) = split /:/,$time;
          my $minutes = $h * 60 + $m;
          my $lastminutes = @ts ? $ts[scalar @ts - 1] : -1;
          if ($minutes > $lastminutes)
          {
            push @ts,$minutes;
          }
          else
          {
            $trans = $HOMEMODE_de?
              "Falsche Reihenfolge der Zeiten in $attr_value":
              "Wrong times order in $attr_value";
            return $trans;
          }
        }
        HOMEMODE_userattr($hash);
      }
    }
    elsif ($attr_name eq "HomeSeasons" && $init_done)
    {
      $trans = $HOMEMODE_de?
        "$attr_value für $attr_name muss eine Leerzeichen separierte Liste aus Datum|Text Paaren mit mindestens 4 Werten sein! z.B. $HOMEMODE_Seasons":
        "$attr_value for $attr_name must be a space separated list of date|text pairs with at least 4 values! e.g. $HOMEMODE_Seasons";
      return $trans if (scalar (split " ",$attr_value) < 4 || scalar (split /\|/,$attr_value) < 5);
      if ($attr_value_old ne $attr_value)
      {
        my @ds;
        foreach (split " ",$attr_value)
        {
          my $time = (split /\|/)[0];
          my ($m,$d) = split /\./,$time;
          my $days = $m * 31 + $d;
          my $lastdays = @ds ? $ds[scalar @ds - 1] : -1;
          if ($days > $lastdays)
          {
            push @ds,$days;
          }
          else
          {
            $trans = $HOMEMODE_de?
              "Falsche Reihenfolge der Datumsangaben in $attr_value":
              "Wrong dates order in $attr_value";
            return $trans;
          }
        }
        HOMEMODE_userattr($hash);
      }
    }
    elsif ($attr_name eq "HomeModeAlarmArmDelay")
    {
      $trans = $HOMEMODE_de?
        "$attr_value für $attr_name muss eine einzelne Zahl sein für die Verzögerung in Sekunden oder 3 Leerzeichen separierte Zeiten in Sekunden für jeden modeAlarm individuell (Reihenfolge: armaway armnight armhome), höhster Wert ist 99999":
        "$attr_value for $attr_name must be a single number for delay time in seconds or 3 space separated times in seconds for each modeAlarm individually (order: armaway armnight armhome), max. value is 99999";
      return $trans if ($attr_value !~ /^(\d{1,5})((\s\d{1,5})(\s\d{1,5}))?$/);
    }
    elsif ($attr_name =~ /^(HomeTextAndAreIs|HomeTextTodayTomorrowAfterTomorrow|HomeTextRisingConstantFalling)$/)
    {
      $trans = $HOMEMODE_de?
        "$attr_value für $attr_name muss eine Pipe separierte Liste mit 3 Werten sein!":
        "$attr_value for $attr_name must be a pipe separated list with 3 values!";
      return $trans if (scalar (split /\|/,$attr_value) != 3);
    }
    elsif ($attr_name eq "HomeTextClosedOpen")
    {
      $trans = $HOMEMODE_de?
        "$attr_value für $attr_name muss eine Pipe separierte Liste mit 2 Werten sein!":
        "$attr_value for $attr_name must be a pipe separated list with 2 values!";
      return $trans if (scalar (split /\|/,$attr_value) != 2);
    }
    elsif ($attr_name eq "HomeUWZ" && $init_done)
    {
      $trans = $HOMEMODE_de?
        "$attr_value muss ein gültiges Gerät vom TYPE Weather sein!":
        "$attr_value must be a valid device of TYPE Weather!";
      return "$attr_value must be a valid device of TYPE UWZ!" if (!HOMEMODE_CheckIfIsValidDevspec("$attr_value:FILTER=TYPE=UWZ"));
      HOMEMODE_updateInternals($hash) if ($attr_value_old ne $attr_value);
    }
    elsif ($attr_name eq "HomeSensorsLuminance" && $init_done)
    {
      my $read = AttrVal($name,"HomeSensorsLuminanceReading","luminance");
      $trans = $HOMEMODE_de?
        "$attr_value muss ein gültiges Gerät mit $read Reading sein!":
        "$attr_name must be a valid device with $read reading!";
      return $trans if (!HOMEMODE_CheckIfIsValidDevspec($attr_value,$read));
      HOMEMODE_updateInternals($hash);
    }
    elsif ($attr_name eq "HomeSensorsPowerEnergyReadings" && $init_done)
    {
      $trans = $HOMEMODE_de?
        "$attr_name müssen zwei gültige Readings für power und energy sein!":
        "$attr_name must be two valid readings for power and energy!";
      return $trans if ($attr_value !~ /^([\w\-\.]+)\s([\w\-\.]+)$/);
      HOMEMODE_updateInternals($hash) if ($attr_value_old ne $attr_value);
    }
    elsif ($attr_name =~ /^HomeSensorsLuminanceReading|HomeSensorsBatteryReading$/ && $init_done)
    {
      $trans = $HOMEMODE_de?
        "$attr_name muss ein einzelnes gültiges Reading sein!":
        "$attr_name must be a single valid reading!";
      return $trans if ($attr_value !~ /^([\w\-\.]+)$/);
      HOMEMODE_updateInternals($hash) if ($attr_value_old ne $attr_value);
    }
    elsif ($attr_name =~ /^HomeSensorAirpressure|HomeSensorWindspeed$/ && $init_done)
    {
      $trans = $HOMEMODE_de?
        "$attr_name muss ein einzelnes gültiges Gerät und Reading sein (Sensor:Reading)!":
        "$attr_name must be a single valid device and reading (sensor:reading)!";
      return $trans if ($attr_value !~ /^([\w\.]+):([\w\-\.]+)$/ || !HOMEMODE_CheckIfIsValidDevspec($1,$2));
      HOMEMODE_updateInternals($hash) if ($attr_value_old ne $attr_value);
    }
    elsif ($attr_name eq "HomeSensorsBattery" && $init_done)
    {
      my $read = AttrVal($name,"HomeSensorsBatteryReading","battery");
      $trans = $HOMEMODE_de?
        "$attr_value muss ein gültiges Gerät mit $read Reading sein!":
        "$attr_name must be a valid device with $read reading!";
      return $trans if (!HOMEMODE_CheckIfIsValidDevspec($attr_value,$read));
      HOMEMODE_updateInternals($hash);
    }
    elsif ($attr_name eq "HomeSensorsBatteryLowPercentage")
    {
      $trans = $HOMEMODE_de?
        "$attr_value muss ein Wert zwischen 0 und 99 sein!":
        "$attr_name must be a value from 0 to 99!";
      return $trans if ($attr_value !~ /^\d{1,2}$/);
    }
    elsif ($attr_name eq "HomeTriggerPanic" && $init_done)
    {
      $trans = $HOMEMODE_de?
        "$attr_value muss ein gültiges Gerät, Reading und Wert in Form von \"Gerät:Reading:WertAn:WertAus\" (WertAus ist optional) sein!":
        "$attr_name must be a valid device, reading and value like \"device:reading:valueOn:valueOff\" (valueOff is optional)!";
      return $trans if ($attr_value !~ /^([\w\.]+):([\w\.]+):[\w\-\.]+(:[\w\-\.]+)?$/ || !HOMEMODE_CheckIfIsValidDevspec($1,$2));
      HOMEMODE_updateInternals($hash);
    }
    elsif ($attr_name eq "HomeTriggerAnyoneElseAtHome" && $init_done)
    {
      $trans = $HOMEMODE_de?
        "$attr_value muss ein gültiges Gerät, Reading und Wert in Form von \"Gerät:Reading:WertAn:WertAus\" sein!":
        "$attr_name must be a valid device, reading and value like \"device:reading:valueOn:valueOff\" !";
      return $trans if ($attr_value !~ /^([\w\.]+):([\w\.]+):[\w\-\.]+(:[\w\-\.]+)$/ || !HOMEMODE_CheckIfIsValidDevspec($1,$2));
      HOMEMODE_updateInternals($hash);
    }
  }
  else
  {
    $hash->{helper}{lastChangedAttrValue} = "---";
    if ($attr_name eq "disable")
    {
      HOMEMODE_GetUpdate($hash);
    }
    elsif ($attr_name eq "HomeLanguage")
    {
      $HOMEMODE_de = AttrVal("global","language","DE") ? 1 : undef;
    }
    elsif ($attr_name =~ /^(HomeAdvancedUserAttr|HomeAutoPresence|HomePresenceDeviceType|HomeEventsHolidayDevices|HomeSensorAirpressure|HomeSensorWindspeed|HomeSensorsBattery|HomeSensorsBatteryReading)$/)
    {
      HOMEMODE_updateInternals($hash,1);
    }
    elsif ($attr_name =~ /^(HomeSensorsContact|HomeSensorsMotion)$/)
    {
      my $olddevs = $hash->{SENSORSCONTACT};
      $olddevs = $hash->{SENSORSMOTION} if ($attr_name eq "HomeSensorsMotion");
      my $read = "lastContact|prevContact|contacts.*";
      $read = "lastMotion|prevMotion|motions.*" if ($attr_name eq "HomeSensorsMotion");
      CommandDeleteReading(undef,"$name $read");
      HOMEMODE_updateInternals($hash);
      HOMEMODE_cleanUserattr($hash,$olddevs);
    }
    elsif ($attr_name eq "HomeSensorsSmoke")
    {
      CommandDeleteReading(undef,"$name alarm_smoke");
      HOMEMODE_updateInternals($hash);
    }
    elsif ($attr_name eq "HomeSensorsPowerEnergy")
    {
      CommandDeleteReading(undef,"$name energy|power");
      HOMEMODE_updateInternals($hash);
    }
    elsif ($attr_name eq "HomePublicIpCheckInterval")
    {
      delete $hash->{".IP_TRIGGERTIME_NEXT"};
    }
    elsif ($attr_name =~ /^(HomeYahooWeatherDevice|HomeTwilightDevice)$/)
    {
      if ($attr_name eq "HomeYahooWeatherDevice")
      {
        CommandDeleteReading(undef,"$name pressure|condition|wind");
        CommandDeleteReading(undef,"$name temperature") if (!AttrVal($name,"HomeSensorTemperatureOutside",undef));
        CommandDeleteReading(undef,"$name humidity") if (!AttrVal($name,"HomeSensorHumidityOutside",undef));
      }
      else
      {
        CommandDeleteReading(undef,"$name twilight|twilightEvent|light");
      }
      HOMEMODE_updateInternals($hash);
    }
    elsif ($attr_name =~ /^(HomeSensorTemperatureOutside|HomeSensorHumidityOutside)$/)
    {
      CommandDeleteReading(undef,"$name .*temperature.*") if (!AttrVal($name,"HomeYahooWeatherDevice",undef) && $attr_name eq "HomeSensorTemperatureOutside");
      CommandDeleteReading(undef,"$name .*humidity.*") if (!AttrVal($name,"HomeYahooWeatherDevice",undef) && $attr_name eq "HomeSensorHumidityOutside");
      HOMEMODE_updateInternals($hash);
    }
    elsif ($attr_name =~ /^(HomeDaytimes|HomeSeasons|HomeSpecialLocations|HomeSpecialModes)$/ && $init_done)
    {
      HOMEMODE_userattr($hash);
    }
    elsif ($attr_name =~ /^(HomeUWZ|HomeSensorsLuminance|HomeSensorsLuminanceReading|HomeSensorsPowerEnergyReadings)$/)
    {
      CommandDeleteReading(undef,"$name uwz.*") if ($attr_name eq "HomeUWZ");
      CommandDeleteReading(undef,"$name .*luminance.*") if ($attr_name eq "HomeSensorsLuminance");
      HOMEMODE_updateInternals($hash);
    }
  }
  return;
}

sub HOMEMODE_replacePlaceholders($$;$)
{
  my ($hash,$cmd,$resident) = @_;
  my $name = $hash->{NAME};
  my $sensor = AttrVal($name,"HomeYahooWeatherDevice","");
  $resident = $resident ? $resident : ReadingsVal($name,"lastActivityByResident","");
  my $alias = AttrVal($resident,"alias","");
  my $audio = AttrVal($resident,"msgContactAudio","");
  $audio = AttrVal("globalMsg","msgContactAudio","no msg audio device available") if (!$audio);
  my $lastabsencedur = ReadingsVal($resident,"lastDurAbsence_cr",0);
  my $lastpresencedur = ReadingsVal($resident,"lastDurPresence_cr",0);
  my $lastsleepdur = ReadingsVal($resident,"lastDurSleep_cr",0);
  my $durabsence = ReadingsVal($resident,"durTimerAbsence_cr",0);
  my $durpresence = ReadingsVal($resident,"durTimerPresence_cr",0);
  my $dursleep = ReadingsVal($resident,"durTimerSleep_cr",0);
  my $condition = ReadingsVal($sensor,"condition","");
  my $conditionart = ReadingsVal($name,".be","");
  my $contactsOpen = ReadingsVal($name,"contactsOutsideOpen_hr","");
  my $contactsOpenCt = ReadingsVal($name,"contactsOutsideOpen_ct",0);
  my $dnd = ReadingsVal($name,"dnd","off") eq "on" ? 1 : 0;
  my $aeah = ReadingsVal($name,"anyoneElseAtHome","off") eq "on" ? 1 : 0;
  my $panic = ReadingsVal($name,"panic","off") eq "on" ? 1 : 0;
  my $sensorsTampered = ReadingsVal($name,"sensorsTampered_hr","");
  my $sensorsTamperedCt = ReadingsVal($name,"sensorsTampered_ct","");
  my $ice = ReadingsVal($name,"icewarning",0);
  my $ip = ReadingsVal($name,"publicIP","");
  my $light = ReadingsVal($name,"light",0);
  my $twilight = ReadingsVal($name,"twilight",0);
  my $twilightevent = ReadingsVal($name,"twilightEvent","");
  my $location = ReadingsVal($name,"location","");
  my $rlocation = ReadingsVal($resident,"location","");
  my $alarm = ReadingsVal($name,"alarmTriggered",0);
  my $alarmc = ReadingsVal($name,"alarmTriggered_ct",0);
  my $alarmhr = ReadingsVal($name,"alarmTriggered_hr",0);
  my $daytime = HOMEMODE_DayTime($hash);
  my $mode = ReadingsVal($name,"mode","");
  my $amode = ReadingsVal($name,"modeAlarm","");
  my $pamode = ReadingsVal($name,"prevModeAlarm","");
  my $season = ReadingsVal($name,"season","");
  my $pmode = ReadingsVal($name,"prevMode","");
  my $rpmode = ReadingsVal($resident,"lastState","");
  my $pres = ReadingsVal($name,"presence","") eq "present" ? 1 : 0;
  my $rpres = ReadingsVal($resident,"presence","") eq "present" ? 1 : 0;
  my $pdevice = ReadingsVal($name,"lastActivityByPresenceDevice","");
  my $apdevice = ReadingsVal($name,"lastAbsentByPresenceDevice","");
  my $ppdevice = ReadingsVal($name,"lastPresentByPresenceDevice","");
  my $paddress = InternalVal($pdevice,"ADDRESS","");
  my $pressure = ReadingsVal($name,"pressure","");
  my $pressuretrend = ReadingsVal($sensor,"pressure_trend_txt","");
  my $weatherlong = HOMEMODE_WeatherTXT($hash,AttrVal($name,"HomeTextWeatherLong",""));
  my $weathershort = HOMEMODE_WeatherTXT($hash,AttrVal($name,"HomeTextWeatherShort",""));
  my $forecast = HOMEMODE_ForecastTXT($hash);
  my $forecasttoday = HOMEMODE_ForecastTXT($hash,1);
  my $luminance = ReadingsVal($name,"luminance",0);
  my $luminancetrend = ReadingsVal($name,"luminanceTrend",0);
  my $humi = ReadingsVal($name,"humidity",0);
  my $humitrend = ReadingsVal($name,"humidityTrend",0);
  my $temp = ReadingsVal($name,"temperature",0);
  my $temptrend = ReadingsVal($name,"temperatureTrend","constant");
  my $wind = ReadingsVal($name,"wind",0);
  my $windchill = ReadingsVal($sensor,"wind_chill",0);
  my $motion = ReadingsVal($name,"lastMotion","");
  my $pmotion = ReadingsVal($name,"prevMotion","");
  my $contact = ReadingsVal($name,"lastContact","");
  my $pcontact = ReadingsVal($name,"prevContact","");
  my $uwzc = ReadingsVal($name,"uwz_warnCount",0);
  my $uwzs = HOMEMODE_uwzTXT($hash,$uwzc,undef);
  my $uwzl = HOMEMODE_uwzTXT($hash,$uwzc,1);
  my $lowBat = HOMEMODE_name2alias(ReadingsVal($name,"lastBatteryLow",""));
  my $lowBatAll = ReadingsVal($name,"batteryLow_hr","");
  my $lowBatCount = ReadingsVal($name,"batteryLow_ct",0);
  my $sensorsbattery = $hash->{SENSORSBATTERY};
  my $sensorscontact = $hash->{SENSORSCONTACT};
  my $sensorsenergy = $hash->{SENSORSENERGY};
  my $sensorsmotion = $hash->{SENSORSMOTION};
  my $ure = $hash->{RESIDENTS};
  $ure =~ s/,/\|/g;
  my $arrivers = HOMEMODE_makeHR($hash,0,devspec2array("$ure:FILTER=location=arrival"));
  $cmd =~ s/%ADDRESS%/$paddress/g;
  $cmd =~ s/%ALARM%/$alarm/g;
  $cmd =~ s/%ALARMCT%/$alarmc/g;
  $cmd =~ s/%ALARMHR%/$alarmhr/g;
  $cmd =~ s/%ALIAS%/$alias/g;
  $cmd =~ s/%AMODE%/$amode/g;
  $cmd =~ s/%AEAH%/$aeah/g;
  $cmd =~ s/%ARRIVERS%/$arrivers/g;
  $cmd =~ s/%AUDIO%/$audio/g;
  $cmd =~ s/%BATTERYLOW%/$lowBat/g;
  $cmd =~ s/%BATTERYLOWALL%/$lowBatAll/g;
  $cmd =~ s/%BATTERYLOWCT%/$lowBatCount/g;
  $cmd =~ s/%CONDITION%/$condition/g;
  $cmd =~ s/%CONTACT%/$contact/g;
  $cmd =~ s/%DAYTIME%/$daytime/g;
  $cmd =~ s/%DEVICE%/$pdevice/g;
  $cmd =~ s/%DEVICEA%/$apdevice/g;
  $cmd =~ s/%DEVICEP%/$ppdevice/g;
  $cmd =~ s/%DND%/$dnd/g;
  if (AttrVal($name,"HomeEventsHolidayDevices",undef))
  {
    foreach my $cal (devspec2array(AttrVal($name,"HomeEventsHolidayDevices","")))
    {
      my $state = ReadingsVal($name,"event-$cal","") ne "none" ? ReadingsVal($name,"event-$cal","") : 0;
      $cmd =~ s/%$cal%/$state/g;
      my $events = HOMEMODE_HolidayEvents($cal);
      foreach my $evt (@{$events})
      {
        my $val = $state eq $evt ? 1 : 0;
        $cmd =~ s/%$cal-$evt%/$val/g;
      }
    }
  }
  $cmd =~ s/%DURABSENCE%/$durabsence/g;
  $cmd =~ s/%DURABSENCELAST%/$lastabsencedur/g;
  $cmd =~ s/%DURPRESENCE%/$durpresence/g;
  $cmd =~ s/%DURPRESENCELAST%/$lastpresencedur/g;
  $cmd =~ s/%DURSLEEP%/$dursleep/g;
  $cmd =~ s/%DURSLEEPLAST%/$lastsleepdur/g;
  $cmd =~ s/%FORECAST%/$forecast/g;
  $cmd =~ s/%FORECASTTODAY%/$forecasttoday/g;
  $cmd =~ s/%HUMIDITY%/$humi/g;
  $cmd =~ s/%HUMIDITYTREND%/$humitrend/g;
  $cmd =~ s/%ICE%/$ice/g;
  $cmd =~ s/%IP%/$ip/g;
  $cmd =~ s/%LIGHT%/$light/g;
  $cmd =~ s/%LOCATION%/$location/g;
  $cmd =~ s/%LOCATIONR%/$rlocation/g;
  $cmd =~ s/%LUMINANCE%/$luminance/g;
  $cmd =~ s/%LUMINANCETREND%/$luminancetrend/g;
  $cmd =~ s/%MODE%/$mode/g;
  $cmd =~ s/%MOTION%/$motion/g;
  $cmd =~ s/%OPEN%/$contactsOpen/g;
  $cmd =~ s/%OPENCT%/$contactsOpenCt/g;
  $cmd =~ s/%RESIDENT%/$resident/g;
  $cmd =~ s/%PANIC%/$panic/g;
  $cmd =~ s/%PRESENT%/$pres/g;
  $cmd =~ s/%PRESENTR%/$rpres/g;
  $cmd =~ s/%PRESSURE%/$pressure/g;
  $cmd =~ s/%PRESSURETREND%/$pressuretrend/g;
  $cmd =~ s/%PREVAMODE%/$pamode/g;
  $cmd =~ s/%PREVCONTACT%/$pcontact/g;
  $cmd =~ s/%PREVMODE%/$pmode/g;
  $cmd =~ s/%PREVMODER%/$rpmode/g;
  $cmd =~ s/%PREVMOTION%/$pmotion/g;
  $cmd =~ s/%SEASON%/$season/g;
  $cmd =~ s/%SELF%/$name/g;
  $cmd =~ s/%SENSORSBATTERY%/$sensorsbattery/g;
  $cmd =~ s/%SENSORSCONTACT%/$sensorscontact/g;
  $cmd =~ s/%SENSORSENERGY%/$sensorsenergy/g;
  $cmd =~ s/%SENSORSMOTION%/$sensorsmotion/g;
  $cmd =~ s/%TAMPERED%/$sensorsTampered/g;
  $cmd =~ s/%TEMPERATURE%/$temp/g;
  $cmd =~ s/%TEMPERATURETREND%/$temptrend/g;
  $cmd =~ s/%TOBE%/$conditionart/g;
  $cmd =~ s/%TWILIGHT%/$twilight/g;
  $cmd =~ s/%TWILIGHTEVENT%/$twilightevent/g;
  $cmd =~ s/%UWZ%/$uwzc/g;
  $cmd =~ s/%UWZLONG%/$uwzl/g;
  $cmd =~ s/%UWZSHORT%/$uwzs/g;
  $cmd =~ s/%WEATHER%/$weathershort/g;
  $cmd =~ s/%WEATHERLONG%/$weatherlong/g;
  $cmd =~ s/%WIND%/$wind/g;
  $cmd =~ s/%WINDCHILL%/$windchill/g;
  return $cmd;
}

sub HOMEMODE_serializeCMD($@)
{
  my ($hash,@cmds) = @_;
  my $name = $hash->{NAME};
  my @newcmds;
  foreach my $cmd (@cmds)
  {
    $cmd =~ s/\r\n/\n/gm;
    my @newcmd;
    foreach (split /\n+/,$cmd)
    {
      next if ($_ =~ /^\s*(#|$)/);
      $_ =~ s/\s{2,}/ /g;
      push @newcmd,$_;
    }
    $cmd = join(" ",@newcmd);
    Log3 $name,5,"$name: cmdnew: $cmd";
    push @newcmds,SemicolonEscape($cmd);
  }
  my $cmd = join(";",@newcmds);
  $cmd =~ s/\}\s{0,1};\s{0,1}\{/\};;\{/g;
  return $cmd;
}

sub HOMEMODE_ReadingTrend($$;$)
{
  my ($hash,$read,$val) = @_;
  my $name = $hash->{NAME};
  $val = ReadingsNum($name,$read,5) if (!$val);
  my $time = AttrNum($name,"HomeTrendCalcAge",900);
  my $pval = ReadingsNum($name,".$read",undef);
  if (defined $pval && ReadingsAge($name,".$read",0) >= $time)
  {
    my ($rising,$constant,$falling) = split /\|/,AttrVal($name,"HomeTextRisingConstantFalling","rising|constant|falling");
    my $trend = $constant;
    $trend = $rising if ($val > $pval);
    $trend = $falling if ($val < $pval);
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,".$read",$val);
    readingsBulkUpdate($hash,$read."Trend",$trend);
    readingsEndUpdate($hash,1);
  }
  elsif (!defined $pval)
  {
    readingsSingleUpdate($hash,".$read",$val,0);
  }
}

sub HOMEMODE_WeatherTXT($$)
{
  my ($hash,$text) = @_;
  my $name = $hash->{NAME};
  my $weather = AttrVal($name,"HomeYahooWeatherDevice","");
  my $condition = ReadingsVal($weather,"condition","");
  my $conditionart = ReadingsVal($name,".be","");
  my $pressure = ReadingsVal($name,"pressure","");
  my $pressuretrend = ReadingsVal($weather,"pressure_trend_txt","");
  my $humi = ReadingsVal($name,"humidity",0);
  my $temp = ReadingsVal($name,"temperature",0);
  my $windchill = ReadingsVal($weather,"wind_chill",0);
  my $wind = ReadingsVal($name,"wind",0);
  $text =~ s/%CONDITION%/$condition/gm;
  $text =~ s/%TOBE%/$conditionart/gm;
  $text =~ s/%HUMIDITY%/$humi/gm;
  $text =~ s/%PRESSURE%/$pressure/gm;
  $text =~ s/%PRESSURETREND%/$pressuretrend/gm;
  $text =~ s/%TEMPERATURE%/$temp/gm;
  $text =~ s/%WINDCHILL%/$windchill/gm;
  $text =~ s/%WIND%/$wind/gm;
  return $text;
}

sub HOMEMODE_ForecastTXT($;$)
{
  my ($hash,$day) = @_;
  $day = 2 if (!$day);
  my $name = $hash->{NAME};
  my $weather = AttrVal($name,"HomeYahooWeatherDevice","");
  my $cond = ReadingsVal($weather,"fc".$day."_condition","");
  my $low  = ReadingsVal($weather,"fc".$day."_low_c","");
  my $high = ReadingsVal($weather,"fc".$day."_high_c","");
  my $temp = ReadingsVal($name,"temperature","");
  my $hum = ReadingsVal($name,"humidity","");
  my $chill = ReadingsVal($weather,"wind_chill","");
  my $wind = ReadingsVal($name,"wind","");
  my $text;
  if (defined $cond && defined $low && defined $high)
  {
    my ($today,$tomorrow,$atomorrow) = split /\|/,AttrVal($name,"HomeTextTodayTomorrowAfterTomorrow","today|tomorrow|day after tomorrow");
    my $d = $today;
    $d = $tomorrow  if ($day == 2);
    $d = $atomorrow if ($day == 3);
    $d = $day-1     if ($day >  3);
    $text = AttrVal($name,"HomeTextWeatherForecastToday","");
    $text = AttrVal($name,"HomeTextWeatherForecastTomorrow","")    if ($day =~ /^[23]$/);
    $text = AttrVal($name,"HomeTextWeatherForecastInSpecDays","")  if ($day > 3);
    $text =~ s/%CONDITION%/$cond/gm;
    $text =~ s/%DAY%/$d/gm;
    $text =~ s/%HIGH%/$high/gm;
    $text =~ s/%LOW%/$low/gm;
    $text = HOMEMODE_WeatherTXT($hash,$text);
  }
  else
  {
    $text = AttrVal($name,"HomeTextWeatherNoForecast","No forecast available");
  }
  return $text;
}

sub HOMEMODE_uwzTXT($;$$)
{
  my ($hash,$count,$sl) = @_;
  my $name = $hash->{NAME};
  $count = defined $count ? $count : ReadingsVal($name,"uwz_warnCount",0);
  $sl = $sl ? "LongText" : "ShortText";
  my $text = "";
  for (my $i = 0; $i < $count; $i++)
  {
    my $read = "Warn_$i";
    my $ii = $i + 1;
    $text .= " " if ($i > 0);
    $text .= "$ii. " if ($count > 1);
    $text .= ReadingsVal(AttrVal($name,"HomeUWZ",""),$read."_$sl","");
  }
  return $text;
}

sub HOMEMODE_CheckIfIsValidDevspec($;$)
{
  my ($spec,$read) = @_;
  my @names;
  foreach (devspec2array($spec))
  {
    next unless (IsDevice($_));
    next if ($read && !defined ReadingsVal($_,$read,undef));
    push @names,$_;
  }
  return if (!@names);
  return \@names;
}

sub HOMEMODE_execUserCMDs($)
{
  my ($string) = @_;
  my ($name,$cmds,$resident) = split /\|/,$string;
  my $hash = $defs{$name};
  $cmds = decode_base64($cmds);
  HOMEMODE_execCMDs($hash,$cmds,$resident);
  return;
}

sub HOMEMODE_execCMDs($$;$)
{
  my ($hash,$cmds,$resident) = @_;
  my $name = $hash->{NAME};
  my $cmd = HOMEMODE_replacePlaceholders($hash,$cmds,$resident);
  my $err = AnalyzeCommandChain(undef,$cmd);
  if ($err && $err !~ /^Deleted.reading/)
  {
    Log3 $name,3,"$name: error: $err";
    Log3 $name,3,"$name: error in command: $cmd";
    readingsSingleUpdate($hash,"lastCMDerror","error: >$err< in CMD: $cmd",1);
  }
  Log3 $name,4,"executed CMDs: $cmd";
  return;
}

sub HOMEMODE_AttrCheck($$;$)
{
  my ($hash,$attribute,$default) = @_;
  $default = "" if (!defined $default);
  my $name = $hash->{NAME};
  my $value;
  if ($hash->{helper}{lastChangedAttr} && $hash->{helper}{lastChangedAttr} eq $attribute)
  {
    $value = defined $hash->{helper}{lastChangedAttrValue} && $hash->{helper}{lastChangedAttrValue} ne "---" ? $hash->{helper}{lastChangedAttrValue} : $default;
  }
  else
  {
    $value = AttrVal($name,$attribute,$default);
  }
  return $value;
}

sub HOMEMODE_DayTime($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $daytimes = HOMEMODE_AttrCheck($hash,"HomeDaytimes",$HOMEMODE_Daytimes);
  my ($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst) = localtime;
  my $loctime = $hour * 60 + $min;
  my @texts;
  my @times;
  foreach (split " ",$daytimes)
  {
    my ($dt,$text) = split /\|/;
    my ($h,$m) = split /:/,$dt;
    my $minutes = $h * 60 + $m;
    push @times,$minutes;
    push @texts,$text;
  }
  my $daytime = $texts[scalar @texts - 1];
  for (my $x = 0; $x < scalar @times; $x++)
  {
    my $y = $x + 1;
    $y = 0 if ($x == scalar @times - 1);
    $daytime = $texts[$x] if ($y > $x && $loctime >= $times[$x] && $loctime < $times[$y]);
  }
  return $daytime;
}

sub HOMEMODE_SetDaytime($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $dt = HOMEMODE_DayTime($hash);
  if (ReadingsVal($name,"daytime","") ne $dt)
  {
    my @commands;
    push @commands,AttrVal($name,"HomeCMDdaytime","") if (AttrVal($name,"HomeCMDdaytime",undef));
    push @commands,AttrVal($name,"HomeCMDdaytime-$dt","") if (AttrVal($name,"HomeCMDdaytime-$dt",undef));
    readingsSingleUpdate($hash,"daytime",$dt,1);
    HOMEMODE_execCMDs($hash,HOMEMODE_serializeCMD($hash,@commands)) if (@commands);
  }
}

sub HOMEMODE_SetSeason($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $seasons = HOMEMODE_AttrCheck($hash,"HomeSeasons",$HOMEMODE_Seasons);
  my ($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst) = localtime;
  my $locdays = ($month + 1) * 31 + $mday;
  my @texts;
  my @dates;
  foreach (split " ",$seasons)
  {
    my ($date,$text) = split /\|/;
    my ($m,$d) = split /\./,$date;
    my $days = $m * 31 + $d;
    push @dates,$days;
    push @texts,$text;
  }
  my $season = $texts[scalar @texts - 1];
  for (my $x = 0; $x < scalar @dates; $x++)
  {
    my $y = $x + 1;
    $y = 0 if ($x == scalar @dates - 1);
    $season = $texts[$x] if ($y > $x && $locdays >= $dates[$x] && $locdays < $dates[$y]);
  }
  if (ReadingsVal($name,"season","") ne $season)
  {
    my @commands;
    push @commands,AttrVal($name,"HomeCMDseason","") if (AttrVal($name,"HomeCMDseason",undef));
    push @commands,AttrVal($name,"HomeCMDseason-$season","") if (AttrVal($name,"HomeCMDseason-$season",undef));
    readingsSingleUpdate($hash,"season",$season,1);
    HOMEMODE_execCMDs($hash,HOMEMODE_serializeCMD($hash,@commands)) if (@commands);
  }
}

sub HOMEMODE_hourMaker($)
{
  my ($minutes) = @_;
  my $trans = $HOMEMODE_de?
    "keine gültigen Minuten übergeben":
    "no valid minutes given";
  return $trans if ($minutes !~ /^(\d{1,4})(\.\d{0,2})?$/ || $1 >= 6000 || $minutes < 0.01);
  my $hours = int($minutes / 60);
  $hours = length $hours > 1 ? $hours : "0$hours";
  my $min = $minutes % 60;
  $min = length $min > 1 ? $min : "0$min";
  my $sec = int(($minutes - int($minutes)) * 60);
  $sec = length $sec > 1 ? $sec : "0$sec";
  return "$hours:$min:$sec";
}

sub HOMEMODE_addSensorsuserattr($$;$)
{
  my ($hash,$devs,$olddevs) = @_;
  return if (!$devs);
  my $name = $hash->{NAME};
  my @devspec = devspec2array($devs);
  my @olddevspec = devspec2array($olddevs) if ($olddevs);
  HOMEMODE_cleanUserattr($hash,$olddevs,$devs) if (@olddevspec);
  foreach my $sensor (@devspec)
  {
    my $inolddevspec = @olddevspec && grep /^$sensor$/,@olddevspec ? 1 : 0;
    my $alias = AttrVal($sensor,"alias","");
    my @list;
    push @list,"HomeModeAlarmActive";
    push @list,"HomeReadings";
    push @list,"HomeValues";
    if ($hash->{SENSORSCONTACT} && grep(/^$sensor$/,split /,/,$hash->{SENSORSCONTACT}))
    {
      push @list,"HomeContactType:doorinside,dooroutside,doormain,window";
      push @list,"HomeOpenMaxTrigger";
      push @list,"HomeOpenDontTriggerModes";
      push @list,"HomeOpenDontTriggerModesResidents";
      push @list,"HomeOpenTimeDividers";
      push @list,"HomeOpenTimes";
      HOMEMODE_set_userattr($sensor,\@list);
      if (!$inolddevspec)
      {
        my $dr = "[Dd]oor|[Tt](ü|ue)r";
        my $wr = "[Ww]indow|[Ff]enster";
        CommandAttr(undef,"$sensor HomeContactType doorinside") if (($alias =~ /$dr/ || $sensor =~ /$dr/) && !AttrVal($sensor,"HomeContactType",""));
        CommandAttr(undef,"$sensor HomeContactType window") if (($alias =~ /$wr/ || $sensor =~ /$wr/) && !AttrVal($sensor,"HomeContactType",""));
        CommandAttr(undef,"$sensor HomeModeAlarmActive armaway") if (!AttrVal($sensor,"HomeModeAlarmActive",""));
      }
    }
    if ($hash->{SENSORSMOTION} && grep(/^$sensor$/,split /,/,$hash->{SENSORSMOTION}))
    {
      push @list,"HomeSensorLocation:inside,outside";
      HOMEMODE_set_userattr($sensor,\@list);
      if (!$inolddevspec)
      {
        my $loc = "inside";
        $loc = "outside" if ($alias =~ /([Aa]u(ss|ß)en)|([Oo]ut)/ || $sensor =~ /([Aa]u(ss|ß)en)|([Oo]ut)/);
        CommandAttr(undef,"$sensor HomeSensorLocation $loc") if (!AttrVal($sensor,"HomeSensorLocation",""));
        CommandAttr(undef,"$sensor HomeModeAlarmActive armaway") if (!AttrVal($sensor,"HomeModeAlarmActive","") && $loc eq "inside");
      }
    }
  }
  return;
}

sub HOMEMODE_set_userattr($$)
{
  my ($name,$list) = @_;
  my $val = AttrVal($name,"userattr","");
  my $l = join " ",@{$list};
  $l .= $val?" $val":"";
  CommandAttr(undef,"$name userattr $l");
  return;
}

sub HOMEMODE_Luminance($;$$)
{
  my ($hash,$dev,$lum) = @_;
  my $name = $hash->{NAME};
  my @sensors = split /,/,$hash->{SENSORSLUMINANCE};
  my $read = AttrVal($name,"HomeSensorsLuminanceReading","luminance");
  $lum = 0 if (!$lum);
  foreach (@sensors)
  {
    my $val = ReadingsNum($_,$read,0);
    next if ($val < 0);
    $lum += $val if (!$dev || $dev ne $_);
  }
  my $lumval = defined $lum ? int ($lum / scalar @sensors) : undef;
  if (defined $lumval && $lumval >= 0)
  {
    readingsSingleUpdate($hash,"luminance",$lumval,1);
    HOMEMODE_ReadingTrend($hash,"luminance",$lumval);
  }
}

sub HOMEMODE_TriggerState($;$$$)
{
  my ($hash,$getter,$type,$trigger) = @_;
  my $exit = 1 if (!$getter && !$type && $trigger);
  $getter  = "contactsOpen" if (!$getter);
  $type = "all" if (!$type);
  my $name = $hash->{NAME};
  my $events = deviceEvents($defs{$trigger},1) if ($trigger);
  my $contacts = $hash->{SENSORSCONTACT};
  my $motions = $hash->{SENSORSMOTION};
  my $tampered = ReadingsVal($name,"sensorsTampered","");
  my @contactsOpen;
  my @sensorsTampered;
  my @doorsOOpen;
  my @doorsMOpen;
  my @insideOpen;
  my @outsideOpen;
  my @windowsOpen;
  my @motionsOpen;
  my @motionsInsideOpen;
  my @motionsOutsideOpen;
  my @alarmSensors;
  my @lightSensors;
  my $amode = ReadingsVal($name,"modeAlarm","");
  if ($contacts)
  {
    foreach my $sensor (devspec2array($contacts))
    {
      next if (IsDisabled($sensor));
      my ($oread,$tread) = split " ",AttrVal($sensor,"HomeReadings",AttrVal($name,"HomeSensorsContactReadings","state sabotageError")),2;
      my $otcmd = AttrVal($sensor,"HomeValues",AttrVal($name,"HomeSensorsContactValues","open|tilted|on"));
      my $amodea = AttrVal($sensor,"HomeModeAlarmActive","-");
      my $ostate = ReadingsVal($sensor,$oread,"");
      my $tstate = ReadingsVal($sensor,$tread,"") if ($tread);
      my $kind = AttrVal($sensor,"HomeContactType","window");
      next if (!$ostate && !$tstate);
      if ($ostate =~ /^($otcmd)$/)
      {
        push @contactsOpen,$sensor;
        push @insideOpen,$sensor if ($kind eq "doorinside");
        push @doorsOOpen,$sensor if ($kind && $kind eq "dooroutside");
        push @doorsMOpen,$sensor if ($kind && $kind eq "doormain");
        push @outsideOpen,$sensor if ($kind =~ /^(dooroutside|doormain|window)$/);
        push @windowsOpen,$sensor if ($kind eq "window");
        if (grep /^($amodea)$/,$amode)
        {
          push @alarmSensors,$sensor;
        }
        if (defined $exit && $trigger eq $sensor && grep /^$oread:/,@{$events})
        {
          readingsBeginUpdate($hash);
          readingsBulkUpdate($hash,"prevContact",ReadingsVal($name,"lastContact",""));
          readingsBulkUpdate($hash,"lastContact",$sensor);
          readingsEndUpdate($hash,1);
          HOMEMODE_ContactCommands($hash,$sensor,"open",$kind);
          HOMEMODE_ContactOpenCheck($name,$sensor,"open");
        }
      }
      else
      {
        if (defined $exit && $trigger eq $sensor && grep /^$oread:/,@{$events})
        {
          readingsBeginUpdate($hash);
          readingsBulkUpdate($hash,"prevContactClosed",ReadingsVal($name,"lastContactClosed",""));
          readingsBulkUpdate($hash,"lastContactClosed",$sensor);
          readingsEndUpdate($hash,1);
          HOMEMODE_ContactCommands($hash,$sensor,"closed",$kind);
          my $timer = "atTmp_HomeOpenTimer_".$sensor."_$name";
          CommandDelete(undef,$timer) if (IsDevice($timer));
        }
      }
      if ($tread && $tstate =~ /^($otcmd)$/)
      {
        push @sensorsTampered,$sensor;
      }
    }
  }
  if ($motions)
  {
    foreach my $sensor (devspec2array($motions))
    {
      next if (IsDisabled($sensor));
      my ($oread,$tread) = split " ",AttrVal($sensor,"HomeReadings",AttrVal($name,"HomeSensorsMotionReadings","state sabotageError")),2;
      my $otcmd = AttrVal($sensor,"HomeValues",AttrVal($name,"HomeSensorsMotionValues","open|on"));
      my $amodea = AttrVal($sensor,"HomeModeAlarmActive","-");
      my $ostate = ReadingsVal($sensor,$oread,"");
      my $tstate = ReadingsVal($sensor,$tread,"") if ($tread);
      my $kind = AttrVal($sensor,"HomeSensorLocation","inside");
      next if (!$ostate && !$tstate);
      if ($ostate =~ /^($otcmd)$/)
      {
        push @motionsOpen,$sensor;
        push @motionsInsideOpen,$sensor if ($kind eq "inside");
        push @motionsOutsideOpen,$sensor if ($kind eq "outside");
        if (grep /^($amodea)$/,$amode)
        {
          push @alarmSensors,$sensor;
        }
        if (defined $exit && $trigger eq $sensor && grep /^$oread:/,@{$events})
        {
          readingsBeginUpdate($hash);
          readingsBulkUpdate($hash,"prevMotion",ReadingsVal($name,"lastMotion",""));
          readingsBulkUpdate($hash,"lastMotion",$sensor);
          readingsEndUpdate($hash,1);
          HOMEMODE_MotionCommands($hash,$sensor,"open");
        }
      }
      else
      {
        if (defined $exit && $trigger eq $sensor && grep /^$oread:/,@{$events})
        {
          readingsBeginUpdate($hash);
          readingsBulkUpdate($hash,"prevMotionClosed",ReadingsVal($name,"lastMotionClosed",""));
          readingsBulkUpdate($hash,"lastMotionClosed",$sensor);
          readingsEndUpdate($hash,1);
          HOMEMODE_MotionCommands($hash,$sensor,"closed");
        }
      }
      if ($tread && $tstate =~ /^($otcmd)$/)
      {
        push @sensorsTampered,$sensor;
      }
    }
  }
  HOMEMODE_alarmTriggered($hash,@alarmSensors);
  my $open    = @contactsOpen ? join(",",@contactsOpen) : "";
  my $opendo  = @doorsOOpen ? join(",",@doorsOOpen) : "";
  my $opendm  = @doorsMOpen ? join(",",@doorsMOpen) : "";
  my $openi   = @insideOpen ? join(",",@insideOpen) : "";
  my $openm   = @motionsOpen ? join(",",@motionsOpen) : "";
  my $openmi  = @motionsInsideOpen ? join(",",@motionsInsideOpen) : "";
  my $openmo  = @motionsOutsideOpen ? join(",",@motionsOutsideOpen) : "";
  my $openo   = @outsideOpen ? join(",",@outsideOpen) : "";
  my $openw   = @windowsOpen ? join(",",@windowsOpen) : "";
  my $tamp    = @sensorsTampered ? join(",",@sensorsTampered) : "";
  readingsBeginUpdate($hash);
  if ($contacts)
  {
    readingsBulkUpdateIfChanged($hash,"contactsDoorsInsideOpen",$openi);
    readingsBulkUpdateIfChanged($hash,"contactsDoorsInsideOpen_ct",@insideOpen);
    readingsBulkUpdateIfChanged($hash,"contactsDoorsInsideOpen_hr",HOMEMODE_makeHR($hash,0,@insideOpen));
    readingsBulkUpdateIfChanged($hash,"contactsDoorsOutsideOpen",$opendo);
    readingsBulkUpdateIfChanged($hash,"contactsDoorsOutsideOpen_ct",@doorsOOpen);
    readingsBulkUpdateIfChanged($hash,"contactsDoorsOutsideOpen_hr",HOMEMODE_makeHR($hash,0,@doorsOOpen));
    readingsBulkUpdateIfChanged($hash,"contactsDoorsMainOpen",$opendm);
    readingsBulkUpdateIfChanged($hash,"contactsDoorsMainOpen_ct",@doorsMOpen);
    readingsBulkUpdateIfChanged($hash,"contactsDoorsMainOpen_hr",HOMEMODE_makeHR($hash,0,@doorsMOpen));
    readingsBulkUpdateIfChanged($hash,"contactsOpen",$open);
    readingsBulkUpdateIfChanged($hash,"contactsOpen_ct",@contactsOpen);
    readingsBulkUpdateIfChanged($hash,"contactsOpen_hr",HOMEMODE_makeHR($hash,0,@contactsOpen));
    readingsBulkUpdateIfChanged($hash,"contactsOutsideOpen",$openo);
    readingsBulkUpdateIfChanged($hash,"contactsOutsideOpen_ct",@outsideOpen);
    readingsBulkUpdateIfChanged($hash,"contactsOutsideOpen_hr",HOMEMODE_makeHR($hash,0,@outsideOpen));
    readingsBulkUpdateIfChanged($hash,"contactsWindowsOpen",$openw);
    readingsBulkUpdateIfChanged($hash,"contactsWindowsOpen_ct",@windowsOpen);
    readingsBulkUpdateIfChanged($hash,"contactsWindowsOpen_hr",HOMEMODE_makeHR($hash,0,@windowsOpen));
  }
  readingsBulkUpdateIfChanged($hash,"sensorsTampered",$tamp);
  readingsBulkUpdateIfChanged($hash,"sensorsTampered_ct",@sensorsTampered);
  readingsBulkUpdateIfChanged($hash,"sensorsTampered_hr",HOMEMODE_makeHR($hash,0,@sensorsTampered));
  if ($motions)
  {
    readingsBulkUpdateIfChanged($hash,"motionsSensors",$openm);
    readingsBulkUpdateIfChanged($hash,"motionsSensors_ct",@motionsOpen);
    readingsBulkUpdateIfChanged($hash,"motionsSensors_hr",HOMEMODE_makeHR($hash,0,@motionsOpen));
    readingsBulkUpdateIfChanged($hash,"motionsInside",$openmi);
    readingsBulkUpdateIfChanged($hash,"motionsInside_ct",@motionsInsideOpen);
    readingsBulkUpdateIfChanged($hash,"motionsInside_hr",HOMEMODE_makeHR($hash,0,@motionsInsideOpen));
    readingsBulkUpdateIfChanged($hash,"motionsOutside",$openmo);
    readingsBulkUpdateIfChanged($hash,"motionsOutside_ct",@motionsOutsideOpen);
    readingsBulkUpdateIfChanged($hash,"motionsOutside_hr",HOMEMODE_makeHR($hash,0,@motionsOutsideOpen));
  }
  readingsEndUpdate($hash,1);
  HOMEMODE_alarmTampered($hash,@sensorsTampered) if (join(",",@sensorsTampered) ne $tampered);
  if ($getter eq "contactsOpen")
  {
    return "open contacts: $open" if ($open && $type eq "all");
    return "no open contacts" if (!$open && $type eq "all");
    return "open doorsinside: $openi" if ($openi && $type eq "doorsinside");
    return "no open doorsinside" if (!$openi && $type eq "doorsinside");
    return "open doorsoutside: $opendo" if ($opendo && $type eq "doorsoutside");
    return "no open doorsoutside" if (!$opendo && $type eq "doorsoutside");
    return "open doorsmain: $opendm" if ($opendm && $type eq "doorsmain");
    return "no open doorsmain" if (!$opendm && $type eq "doorsmain");
    return "open outside: $openo" if ($openo && $type eq "outside");
    return "no open outside" if (!$openo && $type eq "outside");
    return "open windows: $openw" if ($openw && $type eq "windows");
    return "no open windows" if (!$openw && $type eq "windows");
  }
  elsif ($getter eq "sensorsTampered")
  {
    return "tampered sensors: $tamp" if ($tamp);
    return "no tampered sensors" if (!$tamp);
  }
  return;
}

sub HOMEMODE_name2alias($;$)
{
  my ($name,$witharticle) = @_;
  my $alias = AttrVal($name,"alias",$name);
  my $art;
  $art = "der" if ($alias =~ /sensor|dete[ck]tor|melder/i);
  $art = "die" if ($alias =~ /t(ü|ue)r/i);
  $art = "das" if ($alias =~ /fenster/i);
  my $ret = $witharticle && $art ? "$art $alias" : $alias;
  return $ret;
}

sub HOMEMODE_ContactOpenCheck($$;$$)
{
  my ($name,$contact,$state,$retrigger) = @_;
  $retrigger = 0 if (!$retrigger);
  my $maxtrigger = AttrNum($contact,"HomeOpenMaxTrigger",0);
  if ($maxtrigger)
  {
    my $mode = ReadingsVal($name,"state","");
    my $dtmode = AttrVal($contact,"HomeOpenDontTriggerModes",undef);
    my $dtres = AttrVal($contact,"HomeOpenDontTriggerModesResidents",undef);
    my $donttrigger;
    $donttrigger = 1 if ($dtmode && $mode =~ /^($dtmode)$/);
    if (!$donttrigger && $dtmode && $dtres)
    {
      foreach (devspec2array($dtres))
      {
        next if (IsDisabled($_));
        $donttrigger = 1 if (ReadingsVal($_,"state","") =~ /^($dtmode)$/);
      }
    }
    my $timer = "atTmp_HomeOpenTimer_".$contact."_$name";
    CommandDelete(undef,$timer) if (IsDevice($timer) && ($retrigger || $donttrigger));
    return if ((!$retrigger && $donttrigger) || $donttrigger);
    my $season = ReadingsVal($name,"season","");
    my $seasons = AttrVal($name,"HomeSeasons",$HOMEMODE_Seasons);
    my $dividers = AttrVal($contact,"HomeOpenTimeDividers",AttrVal($name,"HomeSensorsContactOpenTimeDividers",""));
    my $mintime = AttrNum($name,"HomeSensorsContactOpenTimeMin",0);
    my @wt = split " ",AttrVal($contact,"HomeOpenTimes",AttrVal($name,"HomeSensorsContactOpenTimes","10"));
    my $waittime;
    Log3 $name,5,"$name: retrigger: $retrigger";
    $waittime = $wt[$retrigger] if ($wt[$retrigger]);
    $waittime = $wt[scalar @wt - 1] if (!defined $waittime);
    Log3 $name,5,"$name: waittime real: $waittime";
    if ($dividers && AttrVal($contact,"HomeContactType","window") !~ /^door(inside|main)$/)
    {
      my @divs = split " ",$dividers;
      my $divider;
      my $count = 0;
      foreach (split " ",$seasons)
      {
        my ($date,$text) = split /\|/;
        $divider = $divs[$count] if ($season eq $text);
        $count++;
      }
      if ($divider)
      {
        $waittime = $waittime / $divider;
        $waittime = sprintf("%.2f",$waittime) * 1;
      }
    }
    $waittime = $mintime if ($mintime && $waittime < $mintime);
    $retrigger++;
    Log3 $name,5,"$name: waittime divided: $waittime";
    $waittime = HOMEMODE_hourMaker($waittime);
    my $at = "{HOMEMODE_ContactOpenCheck(\"$name\",\"$contact\",undef,$retrigger)}" if ($retrigger <= $maxtrigger);
    my $contactname = HOMEMODE_name2alias($contact,1);
    my $contactread = (split " ",AttrVal($contact,"HomeReadings",AttrVal($name,"HomeSensorsContactReadings","state sabotageError")))[0];
    $state = $state ? $state : ReadingsVal($contact,$contactread,"");
    my $opencmds = AttrVal($contact,"HomeValues",AttrVal($name,"HomeSensorsContactValues","open|tilted|on"));
    if ($state =~ /^($opencmds|open)$/)
    {
      CommandDefine(undef,"$timer at +$waittime $at") if ($at && !IsDevice($timer));
      if ($retrigger > 1)
      {
        my @commands;
        my $hash = $defs{$name};
        Log3 $name,5,"$name: maxtrigger: $maxtrigger";
        my $cmd = AttrVal($name,"HomeCMDcontactOpenWarning1","");
        $cmd = AttrVal($name,"HomeCMDcontactOpenWarning2","") if (AttrVal($name,"HomeCMDcontactOpenWarning2",undef) && $retrigger > 2);
        $cmd = AttrVal($name,"HomeCMDcontactOpenWarningLast","") if (AttrVal($name,"HomeCMDcontactOpenWarningLast",undef) && $retrigger == $maxtrigger + 1);
        if ($cmd)
        {
          my ($c,$o) = split /\|/,AttrVal($name,"HomeTextClosedOpen","closed|open");
          $state = $state =~ /^($opencmds)$/ ? $o : $c;
          $cmd =~ s/%ALIAS%/$contactname/gm;
          $cmd =~ s/%SENSOR%/$contact/gm;
          $cmd =~ s/%STATE%/$state/gm;
          push @commands,$cmd;
        }
        HOMEMODE_execCMDs($hash,HOMEMODE_serializeCMD($hash,@commands)) if (@commands);
      }
    }
  }
}

sub HOMEMODE_ContactOpenCheckAfterModeChange($$$;$)
{
  my ($hash,$mode,$pmode,$resident) = @_;
  my $name = $hash->{NAME};
  my $contacts = ReadingsVal($name,"contactsOpen","");
  $mode = ReadingsVal($name,"mode","") if (!$mode);
  $pmode = ReadingsVal($name,"prevMode","") if (!$pmode);
  my $state = ReadingsVal($resident,"state","") if ($resident);
  my $pstate = ReadingsVal($resident,"lastState","") if ($resident);
  if ($contacts)
  {
    foreach (split /,/,$contacts)
    {
      my $m = AttrVal($_,"HomeOpenDontTriggerModes","");
      my $r = AttrVal($_,"HomeOpenDontTriggerModesResidents","");
      $r = s/,/\|/g;
      if ($resident && $m && $r && $resident =~ /^($r)$/ && $state =~ /^($m)$/ && $pstate !~ /^($m)$/)
      {
        HOMEMODE_ContactOpenCheck($name,$_,"open");
      }
      elsif ($m && !$r && $pmode =~ /^($m)$/ && $mode !~ /^($m)$/)
      {
        HOMEMODE_ContactOpenCheck($name,$_,"open");
      }
    }
  }
}

sub HOMEMODE_ContactCommands($$$$)
{
  my ($hash,$contact,$state,$kind) = @_;
  my $name = $hash->{NAME};
  my $alias = HOMEMODE_name2alias($contact,1);
  my @cmds;
  push @cmds,AttrVal($name,"HomeCMDcontact","") if (AttrVal($name,"HomeCMDcontact",undef));
  push @cmds,AttrVal($name,"HomeCMDcontactOpen","") if (AttrVal($name,"HomeCMDcontactOpen",undef) && $state eq "open");
  push @cmds,AttrVal($name,"HomeCMDcontactClosed","") if (AttrVal($name,"HomeCMDcontactClosed",undef) && $state eq "closed");
  push @cmds,AttrVal($name,"HomeCMDcontactDoormain","") if (AttrVal($name,"HomeCMDcontactDoormain",undef) && $kind eq "doormain");
  push @cmds,AttrVal($name,"HomeCMDcontactDoormainOpen","") if (AttrVal($name,"HomeCMDcontactDoormainOpen",undef) && $kind eq "doormain" && $state eq "open");
  push @cmds,AttrVal($name,"HomeCMDcontactDoormainClosed","") if (AttrVal($name,"HomeCMDcontactDoormainClosed",undef) && $kind eq "doormain" && $state eq "closed");
  if (@cmds)
  {
    foreach (@cmds)
    {
      my ($c,$o) = split /\|/,AttrVal($name,"HomeTextClosedOpen","closed|open");
      my $sta = $state eq "open" ? $o : $c;
      $_ =~ s/%ALIAS%/$alias/gm;
      $_ =~ s/%SENSOR%/$contact/gm;
      $_ =~ s/%STATE%/$sta/gm;
    }
    HOMEMODE_execCMDs($hash,HOMEMODE_serializeCMD($hash,@cmds));
  }
}

sub HOMEMODE_MotionCommands($$$)
{
  my ($hash,$sensor,$state) = @_;
  my $name = $hash->{NAME};
  my $alias = HOMEMODE_name2alias($sensor,1);
  my @cmds;
  push @cmds,AttrVal($name,"HomeCMDmotion","") if (AttrVal($name,"HomeCMDmotion",undef));
  push @cmds,AttrVal($name,"HomeCMDmotion-on","") if (AttrVal($name,"HomeCMDmotion-on",undef) && $state eq "open");
  push @cmds,AttrVal($name,"HomeCMDmotion-off","") if (AttrVal($name,"HomeCMDmotion-off",undef) && $state eq "closed");
  if (@cmds)
  {
    foreach (@cmds)
    {
      my ($c,$o) = split /\|/,AttrVal($name,"HomeTextClosedOpen","closed|open");
      $state = $state eq "open" ? $o : $c;
      $_ =~ s/%ALIAS%/$alias/gm;
      $_ =~ s/%SENSOR%/$sensor/gm;
      $_ =~ s/%STATE%/$state/gm;
    }
    HOMEMODE_execCMDs($hash,HOMEMODE_serializeCMD($hash,@cmds));
  }
}

sub HOMEMODE_EventCommands($$$)
{
  my ($hash,$cal,$event) = @_;
  my $name = $hash->{NAME};
  my $prevevent = ReadingsVal($name,"event-$cal","");
  if ($event ne $prevevent)
  {
    my $evt = $event;
    $evt =~ s/\s+/-/g;
    my $pevt = $prevevent;
    $pevt =~ s/\s+/-/g;
    my @cmds;
    push @cmds,AttrVal($name,"HomeCMDevent","") if (AttrVal($name,"HomeCMDevent",undef));
    push @cmds,AttrVal($name,"HomeCMDevent-$cal-each","") if (AttrVal($name,"HomeCMDevent-$cal-each",undef));
    push @cmds,AttrVal($name,"HomeCMDevent-$cal-$evt-begin","") if (AttrVal($name,"HomeCMDevent-$cal-$evt-begin",undef));
    push @cmds,AttrVal($name,"HomeCMDevent-$cal-$pevt-end","") if (AttrVal($name,"HomeCMDevent-$cal-$pevt-end",undef));
    if (@cmds)
    {
      foreach (@cmds)
      {
        $_ =~ s/%CALENDAR%/$cal/gm;
        $_ =~ s/%EVENT%/$event/gm;
        $_ =~ s/%PREVEVENT%/$prevevent/gm;
      }
      HOMEMODE_execCMDs($hash,HOMEMODE_serializeCMD($hash,@cmds));
    }
    readingsSingleUpdate($hash,"event-$cal",$event,1);
  }
}

sub HOMEMODE_UWZCommands($$)
{
  my ($hash,$events) = @_;
  my $name = $hash->{NAME};
  my $prev = ReadingsNum($name,"uwz_warnCount",-1);
  my $uwz = AttrVal($name,"HomeUWZ","");
  my $count;
  my $warning;
  foreach my $evt (@{$events})
  {
    next unless (grep /^WarnCount:\s[0-9]$/,$evt);
    $count = $evt;
    $count =~ s/^WarnCount:\s//;
  }
  if (defined $count)
  {
    readingsSingleUpdate($hash,"uwz_warnCount",$count,1);
    if ($count != $prev)
    {
      my $se = $count > 0 ? "begin" : "end";
      my @cmds;
      push @cmds,AttrVal($name,"HomeCMDuwz-warn","") if (AttrVal($name,"HomeCMDuwz-warn",undef));
      push @cmds,AttrVal($name,"HomeCMDuwz-warn-$se","") if (AttrVal($name,"HomeCMDuwz-warn-$se",undef));
      HOMEMODE_execCMDs($hash,HOMEMODE_serializeCMD($hash,@cmds)) if (@cmds);
    }
  }
}

sub HOMEMODE_HomebridgeMapping($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $mapping = "SecuritySystemCurrentState=alarmState,values=armhome:0;armaway:1;armnight:2;disarm:3;alarm:4";
  $mapping .= "\nSecuritySystemTargetState=modeAlarm,values=armhome:0;armaway:1;armnight:2;disarm:3,cmds=0:modeAlarm+armhome;1:modeAlarm+armaway;2:modeAlarm+armnight;3:modeAlarm+disarm,delay=1";
  $mapping .= "\nSecuritySystemAlarmType=alarmTriggered_ct,values=0:0;/.*/:1";
  $mapping .= "\nOccupancyDetected=presence,values=present:1;absent:0";
  $mapping .= "\nMute=dnd,valueOn=on,cmdOn=dnd+on,cmdOff=dnd+off";
  $mapping .= "\nOn=anyoneElseAtHome,valueOn=on,cmdOn=anyoneElseAtHome+on,cmdOff=anyoneElseAtHome+off";
  $mapping .= "\nContactSensorState=contactsOutsideOpen_ct,values=0:0;/.*/:1" if (defined ReadingsVal($name,"contactsOutsideOpen_ct",undef));
  $mapping .= "\nStatusTampered=sensorsTampered_ct,values=0:0;/.*/:1" if (defined ReadingsVal($name,"sensorsTampered_ct",undef));
  $mapping .= "\nMotionDetected=motionsInside_ct,values=0:0;/.*/:1" if (defined ReadingsVal($name,"motionsInside_ct",undef));
  $mapping .= "\nStatusLowBattery=batteryLow_ct,values=0:0;/.*/:1" if (defined ReadingsVal($name,"batteryLow_ct",undef));
  $mapping .= "\nSmokeDetected=alarm_smoke_ct,values=0:0;/.*/:1" if (defined ReadingsVal($name,"alarm_smoke_ct",undef));
  $mapping .= "\nE863F10F-079E-48FF-8F27-9C2605A29F52=pressure,name=AirPressure,format=UINT16" if (defined ReadingsVal($name,"wind",undef));
  addToDevAttrList($name,"genericDeviceType") if (!grep /^genericDeviceType/,split(" ",AttrVal("global","userattr","")));
  addToDevAttrList($name,"homebridgeMapping:textField-long") if (!grep /^homebridgeMapping/,split(" ",AttrVal("global","userattr","")));
  CommandAttr(undef,"$name genericDeviceType security");
  CommandAttr(undef,"$name homebridgeMapping $mapping");
  return;
}

sub HOMEMODE_PowerEnergy($;$$$)
{
  my ($hash,$trigger,$read,$val) = @_;
  my $name = $hash->{NAME};
  if ($trigger && $read && defined $val)
  {
    foreach (split /,/,$hash->{SENSORSENERGY})
    {
      next if ($_ eq $trigger);
      my $v = ReadingsNum($_,$read,0);
      $val += $v if ($v && $v > 0);
    }
    return if ($val < 0);
    $val = sprintf("%.2f",$val);
    readingsSingleUpdate($hash,$read,$val,1);
  }
  else
  {
    my $power = 0;
    my $energy = 0;
    my ($pr,$er) = split " ",AttrVal($name,"HomeSensorsPowerEnergyReadings","power energy");
    foreach (split /,/,$hash->{SENSORSENERGY})
    {
      my $p = ReadingsNum($_,$pr,0);
      my $e = ReadingsNum($_,$er,0);
      $power += $p if ($p && $p > 0);
      $energy += $e if ($e && $e > 0);
    }
    $power = sprintf("%.2f",$power);
    $energy = sprintf("%.2f",$energy);
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,"power",$power) if ($power * 1 > 0);
    readingsBulkUpdate($hash,"energy",$energy) if ($energy * 1 > 0);
    readingsEndUpdate($hash,1);
  }
}

sub HOMEMODE_Smoke($;$$)
{
  my ($hash,$trigger,$state) = @_;
  my $name = $hash->{NAME};
  my $r = AttrVal($name,"HomeSensorsSmokeReading","state");
  my $v = AttrVal($name,"HomeSensorsSmokeValue","on");
  my @sensors;
  foreach (split /,/,$hash->{SENSORSSMOKE})
  {
    push @sensors,$_ if (ReadingsVal($_,$r,"") eq $v)
  }
  if ($trigger && $state)
  {
    my @cmds;
    push @cmds,AttrVal($name,"HomeCMDalarmSmoke","") if (AttrVal($name,"HomeCMDalarmSmoke",""));
    if (@sensors)
    {
      push @cmds,AttrVal($name,"HomeCMDalarmSmoke-on","") if (AttrVal($name,"HomeCMDalarmSmoke-on",""));
    }
    else
    {
      push @cmds,AttrVal($name,"HomeCMDalarmSmoke-off","") if (AttrVal($name,"HomeCMDalarmSmoke-off",""));
    }
    if (@cmds)
    {
      foreach (@cmds)
      {
        my ($n,$s) = split /\|/,AttrVal($name,"HomeTextNosmokeSmoke","no smoke|smoke");
        my $sta = $state eq $v ? $s : $n;
        my $alias = HOMEMODE_name2alias($trigger,1);
        $_ =~ s/%ALIAS%/$alias/gm;
        $_ =~ s/%SENSOR%/$trigger/gm;
        $_ =~ s/%STATE%/$sta/gm;
      }
      HOMEMODE_execCMDs($hash,HOMEMODE_serializeCMD($hash,@cmds));
    }
  }
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"alarm_smoke",join(",",@sensors));
  readingsBulkUpdate($hash,"alarm_smoke_ct",scalar @sensors);
  readingsBulkUpdate($hash,"alarm_smoke_hr",HOMEMODE_makeHR($hash,0,@sensors));
  readingsEndUpdate($hash,1);
}

sub HOMEMODE_Weather($$)
{
  my ($hash,$dev) = @_;
  my $name = $hash->{NAME};
  my $cond = ReadingsVal($dev,"condition","");
  my ($and,$are,$is) = split /\|/,AttrVal($name,"HomeTextAndAreIs","and|are|is");
  my $be = $cond =~ /(und|and|[Gg]ewitter|[Tt]hunderstorm|[Ss]chauer|[Ss]hower)/ ? $are : $is;
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"humidity",ReadingsNum($dev,"humidity",5)) if (!$hash->{helper}{externalHumidity});
  readingsBulkUpdate($hash,"temperature",ReadingsNum($dev,"temperature",5)) if (!AttrVal($name,"HomeSensorTemperatureOutside",undef));
  readingsBulkUpdate($hash,"wind",ReadingsNum($dev,"wind",0)) if (!AttrVal($name,"HomeSensorWindspeed",undef));
  readingsBulkUpdate($hash,"pressure",ReadingsNum($dev,"pressure",5)) if (!AttrVal($name,"HomeSensorAirpressure",undef));
  readingsBulkUpdate($hash,".be",$be);
  readingsEndUpdate($hash,1);
  HOMEMODE_ReadingTrend($hash,"humidity") if (!$hash->{helper}{externalHumidity});
  HOMEMODE_ReadingTrend($hash,"temperature") if (!AttrVal($name,"HomeSensorTemperatureOutside",undef));
  HOMEMODE_Icewarning($hash);
}

sub HOMEMODE_Twilight($$;$)
{
  my ($hash,$dev,$force) = @_;
  my $name = $hash->{NAME};
  my $events = deviceEvents($defs{$dev},1);
  if ($force)
  {
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,"light",ReadingsVal($dev,"light",5));
    readingsBulkUpdate($hash,"twilight",ReadingsVal($dev,"twilight",5));
    readingsBulkUpdate($hash,"twilightEvent",ReadingsVal($dev,"aktEvent",5));
    readingsEndUpdate($hash,1);
  }
  else
  {
    my $pevent = ReadingsVal($name,"twilightEvent","");
    foreach my $event (@{$events})
    {
      my $val = (split " ",$event)[1];
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash,"light",$val) if ($event =~ /^light:/);
      readingsBulkUpdate($hash,"twilight",$val) if ($event =~ /^twilight:/);
      if ($event =~ /^aktEvent:/)
      {
        readingsBulkUpdate($hash,"twilightEvent",$val);
        if ($val ne $pevent)
        {
          my @commands;
          push @commands,AttrVal($name,"HomeCMDtwilight","") if (AttrVal($name,"HomeCMDtwilight",undef));
          push @commands,AttrVal($name,"HomeCMDtwilight-$val","") if (AttrVal($name,"HomeCMDtwilight-$val",undef));
          HOMEMODE_execCMDs($hash,HOMEMODE_serializeCMD($hash,@commands)) if (@commands);
        }
      }
      readingsEndUpdate($hash,1);
    }
  }
}

sub HOMEMODE_Icewarning($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $ice = ReadingsVal($name,"icewarning",2);
  my $temp = ReadingsVal($name,"temperature",5);
  my $temps = AttrVal($name,"HomeIcewarningOnOffTemps","2 3");
  my $iceon = (split " ",$temps)[0] * 1;
  my $iceoff = (split " ",$temps)[1] ? (split " ",$temps)[1] * 1 : $iceon;
  my $icewarning = 0;
  my $icewarningcmd = "off";
  $icewarning = 1 if ((!$ice && $temp <= $iceon) || ($ice && $temp <= $iceoff));
  $icewarningcmd = "on" if ($icewarning == 1);
  if ($ice != $icewarning)
  {
    my @commands;
    push @commands,AttrVal($name,"HomeCMDicewarning","") if (AttrVal($name,"HomeCMDicewarning",undef));
    push @commands,AttrVal($name,"HomeCMDicewarning-$icewarningcmd","") if (AttrVal($name,"HomeCMDicewarning-$icewarningcmd",undef));
    readingsSingleUpdate($hash,"icewarning",$icewarning,1);
    HOMEMODE_execCMDs($hash,HOMEMODE_serializeCMD($hash,@commands)) if (@commands);
  }
}

sub HOMEMODE_CheckHolidayDevices($)
{
  my ($specs) = @_;
  my @wrongdevices;
  foreach (devspec2array($specs))
  {
    push @wrongdevices,$_ if (!IsDevice($_,"holiday"));
  }
  return \@wrongdevices if (@wrongdevices);
  return;
}

sub HOMEMODE_HolidayEvents($)
{
  my ($calendar) = @_;
  my @events;
  my $fname = AttrVal("global","modpath",".")."/FHEM/".$calendar.".holiday";
  my (undef,@holidayfile) = FileRead($fname);
  foreach (@holidayfile)
  {
    next if ($_ =~ /^\s*(#|$)/);
    my @parts = split;
    my $part = $parts[0] =~ /^(1|2)$/ ? 2 : $parts[0] == 3 ? 4 : $parts[0] == 4 ? 3 : 5;
    for (my $p = 0; $p < $part; $p++)
    {
      shift @parts;
    }
    push @events,join("-",@parts);
  }
  return (\@events);
}

sub HOMEMODE_checkIP($;$)
{
  my ($hash,$r) = @_;
  my $name = $hash->{NAME};
  my $ip = GetFileFromURL("http://icanhazip.com/");
  return if (!$ip);
  $ip =~ s/\s+//g;
  chomp $ip;
  if (ReadingsVal($name,"publicIP","") ne $ip)
  {
    my @commands;
    readingsSingleUpdate($hash,"publicIP",$ip,1);
    push @commands,AttrVal($name,"HomeCMDpublic-ip-change","") if (AttrVal($name,"HomeCMDpublic-ip-change",undef));
    HOMEMODE_execCMDs($hash,HOMEMODE_serializeCMD($hash,@commands)) if (@commands);
  }
  if (AttrNum($name,"HomePublicIpCheckInterval",0))
  {
    my $timer = gettimeofday() + 60 * AttrNum($name,"HomePublicIpCheckInterval",0);
    $hash->{".IP_TRIGGERTIME_NEXT"} = $timer;
  }
  return $ip if ($r);
  return;
}

sub HOMEMODE_Details($$$)
{
  my ($FW_name,$name,$room) = @_;
  return if (AttrVal($name,"HomeAdvancedDetails","none") eq "none" || (AttrVal($name,"HomeAdvancedDetails","") eq "room" && $FW_detail eq $name));
  my $hash = $defs{$name};
  my $iid = ReadingsVal($name,"lastInfo","") ? ReadingsVal($name,"lastInfo","") : "";
  my $info = ReadingsVal($name,$iid,"");
  my $html = "<div>";
  $html .= "<style>.homehover{cursor:pointer}.homeinfo{display:none}.tar{text-align:right}.homeinfopanel{min-height:30px;max-width:480px;padding:3px 10px}</style>";
  $html .= "<div class=\"homeinfopanel\" informid=\"$name-$iid\">$info</div>";
  $html .= "<table class=\"wide\">";
  if (AttrVal($name,"HomeYahooWeatherDevice",""))
  {
    $html .= "<tr class=\"homehover\">";
    my $temp = $HOMEMODE_de ? "Temperatur" : "Temperature";
    $html .= "<td class=\"tar\">$temp:</td>";
    $html .= "<td class=\"dval\"><span informid=\"$name-temperature\">".ReadingsVal($name,"temperature","")."</span> °C<span class=\"homeinfo\" informid=\"\">".HOMEMODE_ForecastTXT($hash,1)."</span></td>";
    my $humi = $HOMEMODE_de ? "Luftfeuchte" : "Humidity";
    $html .= "<td class=\"tar\">$humi:";
    $html .= "<td class=\"dval\"><span informid=\"$name-humidity\">".ReadingsVal($name,"humidity","")."</span> %</td>";
    my $pres = $HOMEMODE_de ? "Luftdruck" : "Air pressure";
    $html .= "<td class=\"tar\">$pres:</td>";
    $html .= "<td class=\"dval\"><span informid=\"$name-pressure\">".ReadingsVal($name,"pressure","")."</span> hPa</td>";
    $html .= "</tr>";
  }
  if (AttrVal($name,"HomeSensorsPowerEnergy","") && AttrVal($name,"HomeSensorsLuminance",""))
  {
    $html .= "<tr>";
    my $power = $HOMEMODE_de ? "Leistung" : "Power";
    $html .= "<td class=\"tar\">$power:</td>";
    $html .= "<td class=\"dval\"><span informid=\"$name-power\">".ReadingsVal($name,"power","")."</span> W</td>";
    my $energy = $HOMEMODE_de ? "Energie" : "Energy";
    $html .= "<td class=\"tar\">$energy:";
    $html .= "<td class=\"dval\"><span informid=\"$name-energy\">".ReadingsVal($name,"energy","")."</span> kWh</td>";
    my $lum = $HOMEMODE_de ? "Licht" : "Luminance";
    $html .= "<td class=\"tar\">$lum:</td>";
    $html .= "<td class=\"dval\"><span informid=\"$name-luminance\">".ReadingsVal($name,"luminance","")."</span> lux</td>";
    $html .= "</tr>";
  }
  if (AttrVal($name,"HomeSensorsContact",""))
  {
    $html .= "<tr>";
    my $open = $HOMEMODE_de ? "Offen" : "Open";
    $html .= "<td class=\"tar\">$open:</td>";
    $html .= "<td class=\"dval homehover\"><span informid=\"$name-contactsOpen_ct\">".ReadingsVal($name,"contactsOpen_ct","")."</span><span class=\"homeinfo\" informid=\"$name-contactsOpen_hr\">".ReadingsVal($name,"contactsOpen_hr","")."</span></td>";
    my $tamp = $HOMEMODE_de ? "Sabotiert" : "Tampered";
    $html .= "<td class=\"tar\">$tamp:</td>";
    $html .= "<td class=\"dval homehover\"><span informid=\"$name-sensorsTampered_ct\">".ReadingsVal($name,"sensorsTampered_ct","")."</span><span class=\"homeinfo\" informid=\"$name-sensorsTampered_hr\">".ReadingsVal($name,"sensorsTampered_hr","")."</span></td>";
    my $alarms = $HOMEMODE_de ? "Alarme" : "Alarms";
    $html .= "<td class=\"tar\">$alarms:</td>";
    $html .= "<td class=\"dval homehover\"><span informid=\"$name-alarmTriggered_ct\">".ReadingsVal($name,"alarmTriggered_ct","")."</span><span class=\"homeinfo\" informid=\"$name-alarmTriggered_hr\">".ReadingsVal($name,"alarmTriggered_hr","")."</span></td>";
    $html .= "</tr>";
  }
  $html .= "</table>";
  $html .= "</div>";
  $html .= "<script>";
  $html .= "\$(\".homehover\").unbind().click(function(){";
  $html .= "var t=\$(this).find(\".homeinfo\").text();";
  $html .= "var id=\$(this).find(\".homeinfo\").attr(\"informid\");";
  $html .= "var r=id.split(\"-\")[1];";
  $html .= "\$(\".homeinfopanel\").text(t).attr(\"informid\",id);";
  $html .= "if(r){\$.post(window.location.pathname+\"?cmd=setreading%20$name%20lastInfo%20\"+r+\"$FW_CSRF\")};";
  $html .= "});</script>";
  return $html;
}

1;

=pod
=item helper
=item summary    home device with ROOMMATE/GUEST integration
=item summary_DE Zuhause Ger&auml;t mit ROOMMATE/GUEST Integration
=begin html

<a name="HOMEMODE"></a>
<h3>HOMEMODE</h3>
<ul>
  <i>HOMEMODE</i> is designed to represent the overall home state(s) in one device.<br>
  It uses the attribute userattr extensively.<br>
  It has been optimized for usage with homebridge as GUI.<br>
  You can also configure CMDs to be executed on specific events.<br>
  There is no need to create notify(s) or DOIF(s) to achieve common tasks depending on the home state(s).<br>
  It's also possible to control ROOMMATE/GUEST devices states depending on their associated presence device.<br>
  If the RESIDENTS device is on state home, the HOMEMODE device can automatically change its mode depending on the local time (morning,day,afternoon,evening,night)<br>
  There is also a daytime reading and associated HomeCMD attributes that will execute the HOMEMODE state CMDs independend of the presence of any RESIDENT.<br>
  A lot of placeholders are available for usage within the HomeCMD or HomeText attributes (see Placeholders).<br>
  All your energy and power measuring sensors can be added and calculated total readings for energy and power will be created.<br>
  You can also add your local outside temperature and humidity sensors and you'll get ice warning e.g.<br>
  If you also add your Yahoo weather device you'll also get short and long weather informations and weather forecast.<br>
  You can monitor added contact and motion sensors and execute CMDs depending on their state.<br>
  A simple alarm system is included, so your contact and motion sensors can trigger alarms depending on the current alarm mode.<br>
  A lot of customizations are possible, e.g. special event (holiday) calendars and locations.<br>
  <p><b>General information:</b></p>
  <ul>
    <li>
      The HOMEMODE device is refreshing itselfs every 5 seconds by calling HOMEMODE_GetUpdate and subfunctions.<br>
      This is the reason why some automations (e.g. daytime or season) are delayed up to 4 seconds.<br>
      All automations triggered by external events (other devices monitored by HOMEMODE) and the execution of the HomeCMD attributes will not be delayed.
    </li>
    <li>
      Each created timer will be created as at device and its name will start with "atTmp_" and end with "_&lt;name of your HOMEMODE device&gt;". You may list them with "list TYPE=at:FILTER=NAME=atTmp_.*_&lt;name of your HOMEMODE device&gt;".
    </li>
    <li>
      Seasons can also be adjusted (date and text) in attribute HomeSeasons
    </li>
    <li>
      There's a special function, which you may use, which is converting given minutes (up to 5999.99) to a timestamp that can be used for creating at devices.<br>
      This function is called HOMEMODE_hourMaker and the only value you need to pass is the number in minutes with max. 2 digits after the dot.
    </li>
    <li>
      Each set command and each updated reading of the HOMEMODE device will create an event within FHEM, so you're able to create additional notify or DOIF devices if needed.
    </li>
  </ul>
  <br>
  <a name="HOMEMODE_define"></a>
  <p><b>define [optional]</b></p>
  <ul>
    <code>define &lt;name&gt; HOMEMODE</code><br><br>
    <code>define &lt;name&gt; HOMEMODE [RESIDENTS-MASTER-DEVICE]</code><br>
  </ul>
  <br>
  <a name="HOMEMODE_set"></a>
  <p><b>set &lt;required&gt;</b></p>
  <ul>
    <li>
      <b><i>anyoneElseAtHome &lt;on/off&gt;</i></b><br>
      turn this on if anyone else is alone at home who is not a registered resident<br>
      e.g. an animal or unregistered guest<br>
      if turned on the alarm mode will be set to armhome instead of armaway while leaving, if turned on after leaving the alarm mode will change from armaway to armhome, e.g. to disable motion sensors alerts<br>
      placeholder %AEAH% is available in all HomeCMD attributes
    </li>
    <li>
      <b><i>dnd &lt;on/off&gt;</i></b><br>
      turn "do not disturb" mode on or off<br>
      e.g. to disable notification or alarms or, or, or...<br>
      placeholder %DND% is available in all HomeCMD attributes
    </li>
    <li>
      <b><i>dnd-for-minutes &lt;MINUTES&gt;</i></b><br>
      turn "do not disturb" mode on for given minutes<br>
      will return to the current (daytime) mode
    </li>
    <li>
      <b><i>location &lt;arrival/home/bed/underway/wayhome&gt;</i></b><br>
      switch to given location manually<br>
      placeholder %LOCATION% is available in all HomeCMD attributes
    </li>
    <li>
      <b><i>mode &lt;morning/day/afternoon/evening/night/gotosleep/asleep/absent/gone/home&gt;</i></b><br>
      switch to given mode manually<br>
      placeholder %MODE% is available in all HomeCMD attributes
    </li>
    <li>
      <b><i>modeAlarm &lt;armaway/armhome/armnight/confirm/disarm&gt;</i></b><br>
      switch to given alarm mode manually<br>
      placeholder %AMODE% is available in all HomeCMD attributes
    </li>
    <li>
      <b><i>modeAlarm-for-minutes &lt;armaway/armhome/armnight/disarm&gt; &lt;MINUTES&gt;</i></b><br>
      switch to given alarm mode for given minutes<br>
      will return to the previous alarm mode
    </li>
    <li>
      <b><i>panic &lt;on/off&gt;</i></b><br>
      turn panic mode on or off<br>
      placeholder %PANIC% is available in all HomeCMD attributes
    </li>
    <li>
      <b><i>updateHomebridgeMapping</i></b><br>
      will update the attribute homebridgeMapping of the HOMEMODE device depending on the available informations
    </li>
    <li>
      <b><i>updateInternalForce</i></b><br>
      will force update all internals of the HOMEMODE device<br>
      use this if you just reload this module after an update or if you made changes on any HOMEMODE monitored device, e.g. after adding residents/guest or after adding new sensors with the same devspec as before
    </li>
  </ul>
  <br>
  <a name="HOMEMODE_get"></a>
  <p><b>get &lt;required&gt; [optional]</b></p>
  <ul>
    <li>
      <b><i>contactsOpen &lt;all/doorsinside/doorsoutside/doorsmain/outside/windows&gt;</i></b><br>
      get a list of all/doorsinside/doorsoutside/doorsmain/outside/windows open contacts<br>
      placeholders %OPEN% (open contacts outside) and %OPENCT% (open contacts outside count) are available in all HomeCMD attributes
    </li>
    <li>
      <b><i>publicIP</i></b><br>
      get the public IP address<br>
      placeholder %IP% is available in all HomeCMD attributes
    </li>
    <li>
      <b><i>sensorsTampered</i></b><br>
      get a list of all tampered sensors<br>
      placeholder %TAMPERED% is available in all HomeCMD attributes
    </li>
    <li>
      <b><i>weather &lt;long/short&gt;</i></b><br>
      get weather information in given format<br>
      please specify the outputs in attributes HomeTextWeatherLong and HomeTextWeatherShort<br>
      placeholders %WEATHER% and %WEATHERLONG% are available in all HomeCMD attributes
    </li>
    <li>
      <b><i>weatherForecast [DAY]</i></b><br>
      get weather forecast for given day<br>
      if DAY is omitted the forecast for tomorrow (2) will be returned<br>
      please specify the outputs in attributes HomeTextWeatherForecastToday, HomeTextWeatherForecastTomorrow and HomeTextWeatherForecastInSpecDays<br>
      placeholders %FORECAST% (tomorrow) and %FORECASTTODAY% (today) are available in all HomeCMD attributes
    </li>
  </ul>
  <br>
  <a name="HOMEMODE_attr"></a>
  <p><b>Attributes</b></p>
  <ul>
    <li>
      <b><i>HomeAdvancedDetails</i></b><br>
      show more details depending on the monitored devices<br>
      value detail will only show advanced details in detail view, value both will show advanced details also in room view, room will show advanced details only in room view<br>
      values: none, detail, both, room<br>
      default: none
    </li>
    <li>
      <b><i>HomeAdvancedUserAttr</i></b><br>
      more HomeCMD userattr will be provided<br>
      additional attributes for each resident and each calendar event<br>
      values: 0 or 1<br>
      default: 0
    </li>
    <li>
      <b><i>HomeAutoAlarmModes</i></b><br>
      set modeAlarm automatically depending on mode<br>
      if mode is set to "home", modeAlarm will be set to "disarm"<br>
      if mode is set to "absent", modeAlarm will be set to "armaway"<br>
      if mode is set to "asleep", modeAlarm will be set to "armnight"<br>
      modeAlarm "home" can only be set manually<br>
      values 0 or 1, value 0 disables automatically set modeAlarm<br>
      default: 1
    </li>
    <li>
      <b><i>HomeAutoArrival</i></b><br>
      set resident's location to arrival (on arrival) and after given minutes to home<br>
      values from 0 to 5999.9 in minutes, value 0 disables automatically set arrival<br>
      default: 0
    </li>
    <li>
      <b><i>HomeAutoAsleep</i></b><br>
      set user from gotosleep to asleep after given minutes<br>
      values from 0 to 5999.9 in minutes, value 0 disables automatically set asleep<br>
      default: 0
    </li>
    <li>
      <b><i>HomeAutoAwoken</i></b><br>
      force set resident from asleep to awoken, even if changing from alseep to home<br>
      after given minutes awoken will change to home<br>
      values from 0 to 5999.9 in minutes, value 0 disables automatically set awoken after asleep<br>
      default: 0
    </li>
    <li>
      <b><i>HomeAutoDaytime</i></b><br>
      daytime depending home mode<br>
      values 0 or 1, value 0 disables automatically set daytime<br>
      default: 1
    </li>
    <li>
      <b><i>HomeAutoPresence</i></b><br>
      automatically change the state of residents between home and absent depending on their associated presence device<br>
      values 0 or 1, value 0 disables auto presence<br>
      default: 0
    </li>
    <li>
      <b><i>HomeCMDalarmSmoke</i></b><br>
      cmds to execute on any smoke alarm state
    </li>
    <li>
      <b><i>HomeCMDalarmSmoke-&lt;on/off&gt;</i></b><br>
      cmds to execute on smoke alarm state on/off
    </li>
    <li>
      <b><i>HomeCMDalarmTampered</i></b><br>
      cmds to execute on any tamper alarm state
    </li>
    <li>
      <b><i>HomeCMDalarmTampered-&lt;on/off&gt;</i></b><br>
      cmds to execute on tamper alarm state on/off
    </li>
    <li>
      <b><i>HomeCMDalarmTriggered</i></b><br>
      cmds to execute on any alarm state
    </li>
    <li>
      <b><i>HomeCMDalarmTriggered-&lt;on/off&gt;</i></b><br>
      cmds to execute on alarm state on/off
    </li>
    <li>
      <b><i>HomeCMDanyoneElseAtHome</i></b><br>
      cmds to execute on any anyoneElseAtHome state
    </li>
    <li>
      <b><i>HomeCMDanyoneElseAtHome-&lt;on/off&gt;</i></b><br>
      cmds to execute on anyoneElseAtHome state on/off
    </li>
    <li>
      <b><i>HomeCMDcontact</i></b><br>
      cmds to execute if any contact has been triggered (open/tilted/closed)
    </li>
    <li>
      <b><i>HomeCMDbatteryLow</i></b><br>
      cmds to execute if any battery sensor has low battery
    </li>
    <li>
      <b><i>HomeCMDcontactClosed</i></b><br>
      cmds to execute if any contact has been closed
    </li>
    <li>
      <b><i>HomeCMDcontactOpen</i></b><br>
      cmds to execute if any contact has been opened
    </li>
    <li>
      <b><i>HomeCMDcontactDoormain</i></b><br>
      cmds to execute if any contact of type doormain has been triggered (open/tilted/closed)
    </li>
    <li>
      <b><i>HomeCMDcontactDoormainClosed</i></b><br>
      cmds to execute if any contact of type doormain has been closed
    </li>
    <li>
      <b><i>HomeCMDcontactDoormainOpen</i></b><br>
      cmds to execute if any contact of type doormain has been opened
    </li>
    <li>
      <b><i>HomeCMDcontactOpenWarning1</i></b><br>
      cmds to execute on first contact open warning
    </li>
    <li>
      <b><i>HomeCMDcontactOpenWarning2</i></b><br>
      cmds to execute on second (and more) contact open warning
    </li>
    <li>
      <b><i>HomeCMDcontactOpenWarningLast</i></b><br>
      cmds to execute on last contact open warning
    </li>
    <li>
      <b><i>HomeCMDdaytime</i></b><br>
      cmds to execute on any daytime change
    </li>
    <li>
      <b><i>HomeCMDdaytime-&lt;%DAYTIME%&gt;</i></b><br>
      cmds to execute on specific day time change
    </li>
    <li>
      <b><i>HomeCMDdnd</i></b><br>
      cmds to execute on any dnd state
    </li>
    <li>
      <b><i>HomeCMDdnd-&lt;on/off&gt;</i></b><br>
      cmds to execute on dnd state on/off
    </li>
    <li>
      <b><i>HomeCMDevent</i></b><br>
      cmds to execute on each calendar event
    </li>
    <li>
      <b><i>HomeCMDevent-&lt;%CALENDAR%&gt;-each</i></b><br>
      cmds to execute on each event of the calendar
    </li>
    <li>
      <b><i>HomeCMDevent-&lt;%CALENDAR%&gt;-&lt;%EVENT%&gt;-begin</i></b><br>
      cmds to execute on start of a specific calendar event
    </li>
    <li>
      <b><i>HomeCMDevent-&lt;%CALENDAR%&gt;-&lt;%EVENT%&gt;-end</i></b><br>
      cmds to execute on end of a specific calendar event
    </li>
    <li>
      <b><i>HomeCMDfhemDEFINED</i></b><br>
      cmds to execute on any defined device
    </li>
    <li>
      <b><i>HomeCMDfhemINITIALIZED</i></b><br>
      cmds to execute on fhem start
    </li>
    <li>
      <b><i>HomeCMDfhemSAVE</i></b><br>
      cmds to execute on fhem save
    </li>
    <li>
      <b><i>HomeCMDfhemUPDATE</i></b><br>
      cmds to execute on fhem update
    </li>
    <li>
      <b><i>HomeCMDicewarning</i></b><br>
      cmds to execute on any ice warning state
    </li>
    <li>
      <b><i>HomeCMDicewarning-&lt;on/off&gt;</i></b><br>
      cmds to execute on ice warning state on/off
    </li>
    <li>
      <b><i>HomeCMDlocation</i></b><br>
      cmds to execute on any location change of the HOMEMODE device
    </li>
    <li>
      <b><i>HomeCMDlocation-&lt;%LOCATION%&gt;</i></b><br>
      cmds to execute on specific location change of the HOMEMODE device
    </li>
    <li>
      <b><i>HomeCMDmode</i></b><br>
      cmds to execute on any mode change of the HOMEMODE device
    </li>
    <li>
      <b><i>HomeCMDmode-absent-belated</i></b><br>
      cmds to execute belated to absent<br>
      belated time can be adjusted with attribute "HomeModeAbsentBelatedTime"
    </li>
    <li>
      <b><i>HomeCMDmode-&lt;%MODE%&gt;</i></b><br>
      cmds to execute on specific mode change of the HOMEMODE device
    </li>
    <li>
      <b><i>HomeCMDmode-&lt;%MODE%&gt;-resident</i></b><br>
      cmds to execute on specific mode change of the HOMEMODE device triggered by any resident
    </li>
    <li>
      <b><i>HomeCMDmode-&lt;%MODE%&gt;-&lt;%RESIDENT%&gt;</i></b><br>
      cmds to execute on specific mode change of the HOMEMODE device triggered by a specific resident
    </li>
    <li>
      <b><i>HomeCMDmodeAlarm</i></b><br>
      cmds to execute on any alarm mode change
    </li>
    <li>
      <b><i>HomeCMDmodeAlarm-&lt;armaway/armhome/armnight/confirm/disarm&gt;</i></b><br>
      cmds to execute on specific alarm mode change
    </li>
    <li>
      <b><i>HomeCMDmotion</i></b><br>
      cmds to execute on any recognized motion of any motion sensor
    </li>
    <li>
      <b><i>HomeCMDmotion-&lt;on/off&gt;</i></b><br>
      cmds to execute if any recognized motion of any motion sensor ends/starts
    </li>
    <li>
      <b><i>HomeCMDpanic</i></b><br>
      cmds to execute on any panic state
    </li>
    <li>
      <b><i>HomeCMDpanic-&lt;on/off&gt;</i></b><br>
      cmds to execute on if panic is turned on/off
    </li>
    <li>
      <b><i>HomeCMDpresence-&lt;absent/present&gt;</i></b><br>
      cmds to execute on specific presence change of the HOMEMODE device
    </li>
    <li>
      <b><i>HomeCMDpresence-&lt;absent/present&gt;-device</i></b><br>
      cmds to execute on specific presence change of any presence device
    </li>
    <li>
      <b><i>HomeCMDpresence-&lt;absent/present&gt;-resident</i></b><br>
      cmds to execute on specific presence change of a specific resident
    </li>
    <li>
      <b><i>HomeCMDpresence-&lt;absent/present&gt;-&lt;%RESIDENT%&gt;</i></b><br>
      cmds to execute on specific presence change of a specific resident
    </li>
    <li>
      <b><i>HomeCMDpresence-&lt;absent/present&gt;-&lt;%RESIDENT%&gt;-&lt;%DEVICE%&gt;</i></b><br>
      cmds to execute on specific presence change of a specific resident's presence device<br>
      only available if more than one presence device is available for a resident
    </li>
    <li>
      <b><i>HomeCMDseason</i></b><br>
      cmds to execute on any season change
    </li>
    <li>
      <b><i>HomeCMDseason-&lt;%SEASON%&gt;</i></b><br>
      cmds to execute on specific season change
    </li>
    <li>
      <b><i>HomeCMDuwz-warn</i></b><br>
      cmds to execute on any UWZ warning state
    </li>
    <li>
      <b><i>HomeCMDuwz-warn-&lt;begin/end&gt;</i></b><br>
      cmds to execute on UWZ warning state begin/end
    </li>
    <li>
      <b><i>HomeDaytimes</i></b><br>
      space separated list of time|text pairs for possible daytimes starting with the first event of the day (lowest time)<br>
      default: 05:00|morning 10:00|day 14:00|afternoon 18:00|evening 23:00|night
    </li>
    <li>
      <b><i>HomeEventsHolidayDevices</i></b><br>
      devspec of holiday calendars
    </li>
    <li>
      <b><i>HomeIcewarningOnOffTemps</i></b><br>
      2 space separated temperatures for ice warning on and off<br>
      default: 2 3
    </li>
    <li>
      <b><i>HomeLanguage</i></b><br>
      overwrite language from gloabl device<br>
      default: EN (language setting from global device)
    </li>
    <li>
      <b><i>HomeModeAbsentBelatedTime</i></b><br>
      time in minutes after changing to absent to execute "HomeCMDmode-absent-belated"<br>
      if mode changes back (to home e.g.) in this time frame "HomeCMDmode-absent-belated" will not be executed<br>
      default:
    </li>
    <li>
      <b><i>HomeModeAlarmArmDelay</i></b><br>
      time in seconds for delaying modeAlarm arm... commands<br>
      must be a single number (valid for all modeAlarm arm... commands) or 3 space separated numbers for each modeAlarm arm... command individually (order: armaway armnight armhome)<br>
      values from 0 to 99999<br>
      default: 0
    </li>
    <li>
      <b><i>HomeAtTmpRoom</i></b><br>
      move temporary ats to this room<br>
      default:
    </li>
    <li>
      <b><i>HomePresenceDeviceAbsentCount-&lt;%RESIDENT%&gt;</i></b><br>
      number of resident associated presence device to turn resident to absent<br>
      default: maximum number of available presence device for each resident
    </li>
    <li>
      <b><i>HomePresenceDevicePresentCount-&lt;%RESIDENT%&gt;</i></b><br>
      number of resident associated presence device to turn resident to home<br>
      default: 1
    </li>
    <li>
      <b><i>HomePresenceDeviceType</i></b><br>
      comma separated list of presence device types<br>
      default: PRESENCE
    </li>
    <li>
      <b><i>HomePublicIpCheckInterval</i></b><br>
      numbers from 1-99999 for interval in minutes for public IP check<br>
      default: 0 (disabled)
    </li>
    <li>
      <b><i>HomeResidentCmdDelay</i></b><br>
      time in seconds to delay the execution of specific residents commands after the change of the residents master device<br>
      normally the resident events occur before the HOMEMODE events, to restore this behavior set this value to 0<br>
      default: 1 (second)
    </li>
    <li>
      <b><i>HomeSeasons</i></b><br>
      space separated list of date|text pairs for possible seasons starting with the first season of the year (lowest date)<br>
      default: 01.01|spring 06.01|summer 09.01|autumn 12.01|winter
    </li>
    <li>
      <b><i>HomeSensorAirpressure</i></b><br>
      main outside airpressure sensor
    </li>
    <li>
      <b><i>HomeSensorWindspeed</i></b><br>
      main outside wind speed sensor
    </li>
    <li>
      <b><i>HomeSensorsBattery</i></b><br>
      devspec of battery sensors with a battery reading<br>
      all sensors with a percentage battery value or a ok/low/nok battery value are applicable
    </li>
    <li>
      <b><i>HomeSensorsBatteryLowPercentage</i></b><br>
      percentage to recognize a sensors battery as low (only percentage based sensors)<br>
      default: 50
    </li>
    <li>
      <b><i>HomeSensorsBatteryReading</i></b><br>
      a single word for the battery reading<br>
      this is only here available as global setting for all devices<br>
      default: battery
    </li>
    <li>
      <b><i>HomeSensorsContact</i></b><br>
      devspec of contact sensors<br>
      each applied contact sensor will get the following attributes, attributes will be removed after removing the contact sensors from the HOMEMODE device.<br>
      <ul>
        <li>
          <b><i>HomeContactType</i></b><br>
          specify each contacts sensor's type, choose one of: doorinside, dooroutside, doormain, window<br>
          while applying contact sensors to the HOMEMODE device, the value of this attribute will be guessed by device name or device alias
        </li>
        <li>
          <b><i>HomeModeAlarmActive</i></b><br>
          specify the alarm mode(s) by regex in which the contact sensor should trigger open/tilted as alerts<br>
          while applying contact sensors to the HOMEMODE device, the value of this attribute will be set to armaway by default<br>
          choose one or a combination of: armaway|armhome|armnight<br>
          default: armaway
        </li>
        <li>
          <b><i>HomeOpenDontTriggerModes</i></b><br>
          specify the HOMEMODE mode(s)/state(s) by regex in which the contact sensor should not trigger open warnings<br>
          choose one or a combination of all available modes of the HOMEMODE device<br>
          if you don't want open warnings while sleeping a good choice would be: gotosleep|asleep<br>
          default:
        </li>
        <li>
          <b><i>HomeOpenDontTriggerModesResidents</i></b><br>
          comma separated list of residents whose state should be the reference for HomeOpenDontTriggerModes instead of the mode of the HOMEMODE device<br>
          if one of the listed residents is in the state given by attribute HomeOpenDontTriggerModes, open warnings will not be triggered for this contact sensor<br>
          default:
        </li>
        <li>
          <b><i>HomeOpenMaxTrigger</i></b><br>
          maximum number how often open warning should be triggered<br>
          default: 0
        </li>
        <li>
          <b><i>HomeReadings</i></b><br>
          2 space separated readings for contact sensors open state and tamper alert<br>
          this is the device setting which will override the global setting from attribute HomeSensorsContactReadings from the HOMEMODE device<br>
          default: state sabotageError
        </li>
        <li>
          <b><i>HomeValues</i></b><br>
          regex of open, tilted and tamper values for contact sensors<br>
          this is the device setting which will override the global setting from attribute HomeSensorsContactValues from the HOMEMODE device<br>
          default: open|tilted|on
        </li>
        <li>
          <b><i>HomeOpenTimes</i></b><br>
          space separated list of minutes after open warning should be triggered<br>
          first value is for first warning, second value is for second warning, ...<br>
          if less values are available than the number given by HomeOpenMaxTrigger, the very last available list entry will be used<br>
          this is the device setting which will override the global setting from attribute HomeSensorsContactOpenTimes from the HOMEMODE device<br>
          default: 10
        </li>
        <li>
          <b><i>HomeOpenTimesDividers</i></b><br>
          space separated list of trigger time dividers for contact sensor open warnings depending on the season of the HOMEMODE device.<br>
          dividers in same order and same number as seasons in attribute HomeSeasons<br>
          dividers are not used for contact sensors of type doormain and doorinside!<br>
          this is the device setting which will override the global setting from attribute HomeSensorsContactOpenTimeDividers from the HOMEMODE device<br>
          values from 0.001 to 99.999<br>
          default:
        </li>
      </ul>
    </li>
    <li>
      <b><i>HomeSensorsContactReadings</i></b><br>
      2 space separated readings for contact sensors open state and tamper alert<br>
      this is the global setting, you can also set these readings in each contact sensor individually in attribute HomeReadings once they are added to the HOMEMODE device<br>
      default: state sabotageError
    </li>
    <li>
      <b><i>HomeSensorsContactValues</i></b><br>
      regex of open, tilted and tamper values for contact sensors<br>
      this is the global setting, you can also set these values in each contact sensor individually in attribute HomeValues once they are added to the HOMEMODE device<br>
      default: open|tilted|on
    </li>
    <li>
      <b><i>HomeSensorsContactOpenTimeDividers</i></b><br>
      space separated list of trigger time dividers for contact sensor open warnings depending on the season of the HOMEMODE device.<br>
      dividers in same order and same number as seasons in attribute HomeSeasons<br>
      dividers are not used for contact sensors of type doormain and doorinside!<br>
      this is the global setting, you can also set these dividers in each contact sensor individually in attribute HomeOpenTimesDividers once they are added to the HOMEMODE device<br>
      values from 0.001 to 99.999<br>
      default:
    </li>
    <li>
      <b><i>HomeSensorsContactOpenTimeMin</i></b><br>
      minimal open time for contact sensors open wanings<br>
      default:
    </li>
    <li>
      <b><i>HomeSensorsContactOpenTimes</i></b><br>
      space separated list of minutes after open warning should be triggered<br>
      first value is for first warning, second value is for second warning, ...<br>
      if less values are available than the number given by HomeOpenMaxTrigger, the very last available list entry will be used<br>
      this is the global setting, you can also set these times(s) in each contact sensor individually in attribute HomeOpenTimes once they are added to the HOMEMODE device<br>
      default: 10
    </li>
    <li>
      <b><i>HomeSensorHumidityOutside</i></b><br>
      main outside humidity sensor<br>
      if HomeSensorTemperatureOutside also has a humidity reading, you don't need to add the same sensor here
    </li>
    <li>
      <b><i>HomeSensorTemperatureOutside</i></b><br>
      main outside temperature sensor<br>
      if this sensor also has a humidity reading, you don't need to add the same sensor to HomeSensorHumidityOutside
    </li>
    <li>
      <b><i>HomeSensorsLuminance</i></b><br>
      devspec of sensors with luminance measurement capabilities<br>
      these devices will be used for total luminance calculations<br>
      please set the corresponding reading for luminance in attribute HomeSensorsLuminanceReading (if different to luminance) before applying snesors here
    </li>
    <li>
      <b><i>HomeSensorsLuminanceReading</i></b><br>
      a single word for the luminance reading<br>
      this is only here available as global setting for all devices<br>
      default: luminance
    </li>
    <li>
      <b><i>HomeSensorsMotion</i></b><br>
      devspec of motion sensors<br>
      each applied motion sensor will get the following attributes, attributes will be removed after removing the motion sensors from the HOMEMODE device.<br>
      <ul>
        <li>
          <b><i>HomeModeAlarmActive</i></b><br>
          specify the alarm mode(s) by regex in which the motion sensor should trigger motions as alerts<br>
          while applying motion sensors to the HOMEMODE device, the value of this attribute will be set to armaway by default<br>
          choose one or a combination of: armaway|armhome|armnight<br>
          default: armaway (if sensor is of type inside)
        </li>
        <li>
          <b><i>HomeSensorLocation</i></b><br>
          specify each motion sensor's location, choose one of: inside, outside<br>
          default: inside
        </li>
        <li>
          <b><i>HomeReadings</i></b><br>
          2 space separated readings for motion sensors open/closed state and tamper alert<br>
          this is the device setting which will override the global setting from attribute HomeSensorsMotionReadings from the HOMEMODE device<br>
          default: state sabotageError
        </li>
        <li>
          <b><i>HomeValues</i></b><br>
          regex of open and tamper values for motion sensors<br>
          this is the device setting which will override the global setting from attribute HomeSensorsMotionValues from the HOMEMODE device<br>
          default: open|on
        </li>
      </ul>
    </li>
    <li>
      <b><i>HomeSensorsMotionReadings</i></b><br>
      2 space separated readings for motion sensors open/closed state and tamper alert<br>
      this is the global setting, you can also set these readings in each motion sensor individually in attribute HomeReadings once they are added to the HOMEMODE device<br>
      default: state sabotageError
    </li>
    <li>
      <b><i>HomeSensorsMotionValues</i></b><br>
      regex of open and tamper values for motion sensors<br>
      this is the global setting, you can also set these values in each contact sensor individually in attribute HomeValues once they are added to the HOMEMODE device<br>
      default: open|on
    </li>
    <li>
      <b><i>HomeSensorsPowerEnergy</i></b><br>
      devspec of sensors with power and energy readings<br>
      these devices will be used for total calculations
    </li>
    <li>
      <b><i>HomeSensorsPowerEnergyReadings</i></b><br>
      2 space separated readings for power/energy sensors power and energy readings<br>
      default: power energy
    </li>
    <li>
      <b><i>HomeSensorsSmoke</i></b><br>
      devspec of smoke sensors<br>
    </li>
    <li>
      <b><i>HomeSensorsSmokeReading</i></b><br>
      readings for smoke sensors on/off state<br>
      default: state
    </li>
    <li>
      <b><i>HomeSensorsSmokeValue</i></b><br>
      on value for smoke sensors<br>
      default: on
    </li>
    <li>
      <b><i>HomeSpecialLocations</i></b><br>
      comma separated list of additional locations<br>
      default:
    </li>
    <li>
      <b><i>HomeSpecialModes</i></b><br>
      comma separated list of additional modes<br>
      default:
    </li>
    <li>
      <b><i>HomeTextAndAreIs</i></b><br>
      pipe separated list of your local translations for "and", "are" and "is"<br>
      default: and|are|is
    </li>
    <li>
      <b><i>HomeTextClosedOpen</i></b><br>
      pipe separated list of your local translation for "closed" and "open"<br>
      default: closed|open
    </li>
    <li>
      <b><i>HomeTextRisingConstantFalling</i></b><br>
      pipe separated list of your local translation for "rising", "constant" and "falling"<br>
      default: rising|constant|falling
    </li>
    <li>
      <b><i>HomeTextNosmokeSmoke</i></b><br>
      pipe separated list of your local translation for "no smoke" and "smoke"<br>
      default: so smoke|smoke
    </li>
    <li>
      <b><i>HomeTextTodayTomorrowAfterTomorrow</i></b><br>
      pipe separated list of your local translations for "today", "tomorrow" and "day after tomorrow"<br>
      this is used by weather forecast<br>
      default: today|tomorrow|day after tomorrow
    </li>
    <li>
      <b><i>HomeTextWeatherForecastInSpecDays</i></b><br>
      your text for weather forecast in specific days<br>
      placeholders can be used!<br>
      default:
    </li>
    <li>
      <b><i>HomeTextWeatherForecastToday</i></b><br>
      your text for weather forecast today<br>
      placeholders can be used!<br>
      default:
    </li>
    <li>
      <b><i>HomeTextWeatherForecastTomorrow</i></b><br>
      your text for weather forecast tomorrow and the day after tomorrow<br>
      placeholders can be used!<br>
      default:
    </li>
    <li>
      <b><i>HomeTextWeatherNoForecast</i></b><br>
      your text for no available weather forecast<br>
      default: No forecast available
    </li>
    <li>
      <b><i>HomeTextWeatherLong</i></b><br>
      your text for long weather information<br>
      placeholders can be used!<br>
      default:
    </li>
    <li>
      <b><i>HomeTextWeatherShort</i></b><br>
      your text for short weather information<br>
      placeholders can be used!<br>
      default:
    </li>
    <li>
      <b><i>HomeTrendCalcAge</i></b><br>
      time in seconds for the max age of the previous measured value for calculating trends<br>
      default: 900
    </li>
    <li>
      <b><i>HomeTriggerAnyoneElseAtHome</i></b><br>
      your anyoneElseAtHome trigger device (device:reading:valueOn:valueOff)<br>
      default:
    </li>
    <li>
      <b><i>HomeTriggerPanic</i></b><br>
      your panic trigger device (device:reading:valueOn[:valueOff])<br>
      valueOff is optional<br>
      valueOn will toggle panic mode if valueOff is not given<br>
      default:
    </li>
    <li>
      <b><i>HomeUWZ</i></b><br>
      your local UWZ device<br>
      default:
    </li>
    <li>
      <b><i>HomeYahooWeatherDevice</i></b><br>
      your local yahoo weather device<br>
      default:
    </li>
    <li>
      <b><i>disable</i></b><br>
      disable HOMEMODE device and stop executing CMDs<br>
      values 0 or 1<br>
      default: 0
    </li>
    <li>
      <b><i>disabledForIntervals</i></b><br>
      disable the HOMEMODE device for intervals
      default:
    </li>
  </ul>
  <br>
  <a name="HOMEMODE_read"></a>
  <p><b>Readings</b></p>
  <ul>
    <li>
      <b><i>alarmState</i></b><br>
      current state of alarm system (includes current alarms - for homebridgeMapping)
    </li>
    <li>
      <b><i>alarmTriggered</i></b><br>
      list of triggered alarm sensors (contact/motion sensors)
    </li>
    <li>
      <b><i>alarmTriggered_ct</i></b><br>
      count of triggered alarm sensors (contact/motion sensors)
    </li>
    <li>
      <b><i>alarmTriggered_hr</i></b><br>
      (human readable) list of triggered alarm sensors (contact/motion sensors)
    </li>
    <li>
      <b><i>anyoneElseAtHome</i></b><br>
      anyoneElseAtHome on or off
    </li>
    <li>
      <b><i>contactsDoorsInsideOpen</i></b><br>
      list of names of open contact sensors of type doorinside
    </li>
    <li>
      <b><i>batteryLow</i></b><br>
      list of names of sensors with low battery
    </li>
    <li>
      <b><i>batteryLow_ct</i></b><br>
      count of sensors with low battery
    </li>
    <li>
      <b><i>batteryLow_hr</i></b><br>
      (human readable) list of sensors with low battery
    </li>
    <li>
      <b><i>contactsDoorsInsideOpen_ct</i></b><br>
      count of open contact sensors of type doorinside
    </li>
    <li>
      <b><i>contactsDoorsInsideOpen_hr</i></b><br>
      (human readable) list of open contact sensors of type doorinside
    </li>
    <li>
      <b><i>contactsDoorsMainOpen</i></b><br>
      list of names of open contact sensors of type doormain
    </li>
    <li>
      <b><i>contactsDoorsMainOpen_ct</i></b><br>
      count of open contact sensors of type doormain
    </li>
    <li>
      <b><i>contactsDoorsMainOpen_hr</i></b><br>
      (human readable) list of open contact sensors of type doormain
    </li>
    <li>
      <b><i>contactsDoorsOutsideOpen</i></b><br>
      list of names of open contact sensors of type dooroutside
    </li>
    <li>
      <b><i>contactsDoorsOutsideOpen_ct</i></b><br>
      count of open contact sensors of type dooroutside
    </li>
    <li>
      <b><i>contactsDoorsOutsideOpen_hr</i></b><br>
      (human readable) list of contact sensors of type dooroutside
    </li>
    <li>
      <b><i>contactsOpen</i></b><br>
      list of names of all open contact sensors
    </li>
    <li>
      <b><i>contactsOpen_ct</i></b><br>
      count of all open contact sensors
    </li>
    <li>
      <b><i>contactsOpen_hr</i></b><br>
      (human readable) list of all open contact sensors
    </li>
    <li>
      <b><i>contactsOutsideOpen</i></b><br>
      list of names of open contact sensors outside (sensor types: dooroutside,doormain,window)
    </li>
    <li>
      <b><i>contactsOutsideOpen_ct</i></b><br>
      count of open contact sensors outside (sensor types: dooroutside,doormain,window)
    </li>
    <li>
      <b><i>contactsOutsideOpen_hr</i></b><br>
      (human readable) list of open contact sensors outside (sensor types: dooroutside,doormain,window)
    </li>
    <li>
      <b><i>contactsWindowsOpen</i></b><br>
      list of names of open contact sensors of type window
    </li>
    <li>
      <b><i>contactsWindowsOpen_ct</i></b><br>
      count of open contact sensors of type window
    </li>
    <li>
      <b><i>contactsWindowsOpen_hr</i></b><br>
      (human readable) list of open contact sensors of type window
    </li>
    <li>
      <b><i>daytime</i></b><br>
      current daytime (as configured in HomeDaytimes) - independent from the mode of the HOMEMODE device<br>
    </li>
    <li>
      <b><i>dnd</i></b><br>
      dnd (do not disturb) on or off
    </li>
    <li>
      <b><i>energy</i></b><br>
      calculated total energy
    </li>
    <li>
      <b><i>event-&lt;%CALENDAR%&gt;</i></b><br>
      current event of the (holiday) CALENDAR device(s)
    </li>
    <li>
      <b><i>humidty</i></b><br>
      current humidty of the Yahoo weather device or of your own sensor (if available)
    </li>
    <li>
      <b><i>humidtyTrend</i></b><br>
      trend of the humidty over the last hour<br>
      possible values: constant, rising, falling
    </li>
    <li>
      <b><i>icawarning</i></b><br>
      ice warning<br>
      values: 0 if off and 1 if on
    </li>
    <li>
      <b><i>lastAbsentByPresenceDevice</i></b><br>
      last presence device which went absent
    </li>
    <li>
      <b><i>lastAbsentByResident</i></b><br>
      last resident who went absent
    </li>
    <li>
      <b><i>lastActivityByPresenceDevice</i></b><br>
      last active presence device
    </li>
    <li>
      <b><i>lastActivityByResident</i></b><br>
      last active resident
    </li>
    <li>
      <b><i>lastAsleepByResident</i></b><br>
      last resident who went asleep
    </li>
    <li>
      <b><i>lastAwokenByResident</i></b><br>
      last resident who went awoken
    </li>
    <li>
      <b><i>lastBatteryLow</i></b><br>
      last sensor with low battery
    </li>
    <li>
      <b><i>lastCMDerror</i></b><br>
      last occured error and command(chain) while executing command(chain)
    </li>
    <li>
      <b><i>lastContact</i></b><br>
      last contact sensor which triggered open
    </li>
    <li>
      <b><i>lastContactClosed</i></b><br>
      last contact sensor which triggered closed
    </li>
    <li>
      <b><i>lastGoneByResident</i></b><br>
      last resident who went gone
    </li>
    <li>
      <b><i>lastGotosleepByResident</i></b><br>
      last resident who went gotosleep
    </li>
    <li>
      <b><i>lastInfo</i></b><br>
      last shown item on infopanel (HomeAdvancedDetails)
    </li>
    <li>
      <b><i>lastMotion</i></b><br>
      last sensor which triggered motion
    </li>
    <li>
      <b><i>lastMotionClosed</i></b><br>
      last sensor which triggered motion end
    </li>
    <li>
      <b><i>lastPresentByPresenceDevice</i></b><br>
      last presence device which came present
    </li>
    <li>
      <b><i>lastPresentByResident</i></b><br>
      last resident who came present
    </li>
    <li>
      <b><i>light</i></b><br>
      current light reading value
    </li>
    <li>
      <b><i>location</i></b><br>
      current location
    </li>
    <li>
      <b><i>luminance</i></b><br>
      average luminance of all motion sensors (if available)
    </li>
    <li>
      <b><i>luminanceTrend</i></b><br>
      trend of the luminance over the last hour<br>
      possible values: constant, rising, falling
    </li>
    <li>
      <b><i>mode</i></b><br>
      current mode
    </li>
    <li>
      <b><i>modeAlarm</i></b><br>
      current mode of alarm system
    </li>
    <li>
      <b><i>motionsInside</i></b><br>
      list of names of open motion sensors of type inside
    </li>
    <li>
      <b><i>motionsInside_ct</i></b><br>
      count of open motion sensors of type inside
    </li>
    <li>
      <b><i>motionsInside_hr</i></b><br>
      (human readable) list of open motion sensors of type inside
    </li>
    <li>
      <b><i>motionsOutside</i></b><br>
      list of names of open motion sensors of type outside
    </li>
    <li>
      <b><i>motionsOutside_ct</i></b><br>
      count of open motion sensors of type outside
    </li>
    <li>
      <b><i>motionsOutside_hr</i></b><br>
      (human readable) list of open motion sensors of type outside
    </li>
    <li>
      <b><i>motionsSensors</i></b><br>
      list of all names of open motion sensors
    </li>
    <li>
      <b><i>motionsSensors_ct</i></b><br>
      count of all open motion sensors
    </li>
    <li>
      <b><i>motionsSensors_hr</i></b><br>
      (human readable) list of all open motion sensors
    </li>
    <li>
      <b><i>power</i></b><br>
      calculated total power
    </li>
    <li>
      <b><i>prevMode</i></b><br>
      previous mode
    </li>
    <li>
      <b><i>presence</i></b><br>
      presence of any resident
    </li>
    <li>
      <b><i>pressure</i></b><br>
      current air pressure of the Yahoo weather device
    </li>
    <li>
      <b><i>prevActivityByResident</i></b><br>
      previous active resident
    </li>
    <li>
      <b><i>prevContact</i></b><br>
      previous contact sensor which triggered open
    </li>
    <li>
      <b><i>prevContactClosed</i></b><br>
      previous contact sensor which triggered closed
    </li>
    <li>
      <b><i>prevLocation</i></b><br>
      previous location
    </li>
    <li>
      <b><i>prevMode</i></b><br>
      previous mode
    </li>
    <li>
      <b><i>prevMotion</i></b><br>
      previous sensor which triggered motion
    </li>
    <li>
      <b><i>prevMotionClosed</i></b><br>
      previous sensor which triggered motion end
    </li>
    <li>
      <b><i>prevModeAlarm</i></b><br>
      previous alarm mode
    </li>
    <li>
      <b><i>publicIP</i></b><br>
      last checked public IP address
    </li>
    <li>
      <b><i>season</i></b><br>
      current season as configured in HomeSeasons<br>
    </li>
    <li>
      <b><i>sensorsTampered</i></b><br>
      list of names of tampered sensors
    </li>
    <li>
      <b><i>sensorsTampered_ct</i></b><br>
      count of tampered sensors
    </li>
    <li>
      <b><i>sensorsTampered_hr</i></b><br>
      (human readable) list of tampered sensors
    </li>
    <li>
      <b><i>state</i></b><br>
      current state
    </li>
    <li>
      <b><i>temperature</i></b><br>
      current temperature of the Yahoo weather device or of your own sensor (if available)
    </li>
    <li>
      <b><i>temperatureTrend</i></b><br>
      trend of the temperature over the last hour<br>
      possible values: constant, rising, falling
    </li>
    <li>
      <b><i>twilight</i></b><br>
      current twilight reading value
    </li>
    <li>
      <b><i>twilightEvent</i></b><br>
      current twilight event
    </li>
    <li>
      <b><i>uwz_warnCount</i></b><br>
      current UWZ warn count
    </li>
    <li>
      <b><i>wind</i></b><br>
      current wind speed of the Yahoo weather
    </li>
  </ul>
  <a name="HOMEMODE_placeholders"></a>
  <p><b>Placeholders</b></p>
  <p>These placeholders can be used in all HomeCMD attributes</p>
  <ul>
    <li>
      <b><i>%ADDRESS%</i></b><br>
      mac address of the last triggered presence device
    </li>
    <li>
      <b><i>%ALIAS%</i></b><br>
      alias of the last triggered resident
    </li>
    <li>
      <b><i>%ALARM%</i></b><br>
      value of the alarmTriggered reading of the HOMEMODE device<br>
      will return 0 if no alarm is triggered or a list of triggered sensors if alarm is triggered
    </li>
    <li>
      <b><i>%ALARMCT%</i></b><br>
      value of the alarmTriggered_ct reading of the HOMEMODE device
    </li>
    <li>
      <b><i>%ALARMHR%</i></b><br>
      value of the alarmTriggered_hr reading of the HOMEMODE device<br>
      will return 0 if no alarm is triggered or a (human readable) list of triggered sensors if alarm is triggered<br>
      can be used for sending msg e.g.
    </li>
    <li>
      <b><i>%AMODE%</i></b><br>
      current alarm mode
    </li>
    <li>
      <b><i>%AEAH%</i></b><br>
      state of anyoneElseAtHome, will return 1 if on and 0 if off
    </li>
    <li>
      <b><i>%ARRIVERS%</i></b><br>
      will return a list of aliases of all registered residents/guests with location arrival<br>
      this can be used to welcome residents after main door open/close<br>
      e.g. Peter, Paul and Marry
    </li>
    <li>
      <b><i>%AUDIO%</i></b><br>
      audio device of the last triggered resident (attribute msgContactAudio)<br>
      if attribute msgContactAudio of the resident has no value the value is trying to be taken from device globalMsg (if available)<br>
      can be used to address resident specific msg(s) of type audio, e.g. night/morning wishes
    </li>
    <li>
      <b><i>%BE%</i></b><br>
      is or are of condition reading of monitored Yahoo weather device<br>
      can be used for weather (forecast) output
    </li>
    <li>
      <b><i>%BATTERYLOW%</i></b><br>
      alias (or name if alias is not set) of the last battery sensor which reported low battery
    </li>
    <li>
      <b><i>%BATTERYLOWALL%</i></b><br>
      list of aliases (or names if alias is not set) of all battery sensor which reported low battery currently
    </li>
    <li>
      <b><i>%BATTERYLOWCT%</i></b><br>
      number of battery sensors which reported low battery currently
    </li>
    <li>
      <b><i>%CONDITION%</i></b><br>
      value of the condition reading of monitored Yahoo weather device<br>
      can be used for weather (forecast) output
    </li>
    <li>
      <b><i>%CONTACT%</i></b><br>
      value of the lastContact reading (last opened sensor)
    </li>
    <li>
      <b><i>%DEFINED%</i></b><br>
      name of the previously defined device<br>
      can be used to trigger actions based on the name of the defined device<br>
      only available within HomeCMDfhemDEFINED
    </li>
    <li>
      <b><i>%DAYTIME%</i></b><br>
      value of the daytime reading of the HOMEMODE device<br>
      can be used to trigger day time specific actions
    </li>
    <li>
      <b><i>%DEVICE%</i></b><br>
      name of the last triggered presence device<br>
      can be used to trigger actions depending on the last present/absent presence device
    </li>
    <li>
      <b><i>%DEVICEA%</i></b><br>
      name of the last triggered absent presence device
    </li>
    <li>
      <b><i>%DEVICEP%</i></b><br>
      name of the last triggered present presence device
    </li>
    <li>
      <b><i>%DND%</i></b><br>
      state of dnd, will return 1 if on and 0 if off
    </li>
    <li>
      <b><i>%DURABSENCE%</i></b><br>
      value of the durTimerAbsence_cr reading of the last triggered resident
    </li>
    <li>
      <b><i>%DURABSENCELAST%</i></b><br>
      value of the lastDurAbsence_cr reading of the last triggered resident
    </li>
    <li>
      <b><i>%DURPRESENCE%</i></b><br>
      value of the durTimerPresence_cr reading of the last triggered resident
    </li>
    <li>
      <b><i>%DURPRESENCELAST%</i></b><br>
      value of the lastDurPresence_cr reading of the last triggered resident
    </li>
    <li>
      <b><i>%DURSLEEP%</i></b><br>
      value of the durTimerSleep_cr reading of the last triggered resident
    </li>
    <li>
      <b><i>%DURSLEEPLAST%</i></b><br>
      value of the lastDurSleep_cr reading of the last triggered resident
    </li>
    <li>
      <b><i>%CALENDARNAME%</i></b><br>
      will return the current event of the given calendar name, will return 0 if event is none<br>
      can be used to trigger actions on any event of the given calendar
    </li>
    <li>
      <b><i>%CALENDARNAME-EVENTNAME%</i></b><br>
      will return 1 if given event of given calendar is current, will return 0 if event is not current<br>
      can be used to trigger actions during specific events only (Christmas?)
    </li>
    <li>
      <b><i>%FORECAST%</i></b><br>
      will return the weather forecast for tomorrow<br>
      can be used in msg or tts
    </li>
    <li>
      <b><i>%FORECASTTODAY%</i></b><br>
      will return the weather forecast for today<br>
      can be used in msg or tts
    </li>
    <li>
      <b><i>%HUMIDITY%</i></b><br>
      value of the humidity reading of the HOMEMODE device<br>
      can be used for weather info in HomeTextWeather attributes e.g.
    </li>
    <li>
      <b><i>%HUMIDITYTREND%</i></b><br>
      value of the humidityTrend reading of the HOMEMODE device<br>
      possible values: constant, rising, falling
    </li>
    <li>
      <b><i>%ICE%</i></b><br>
      will return 1 if ice warning is on, will return 0 if ice warning is off<br>
      can be used to send ice warning specific msg(s) in specific situations, e.g. to warn leaving residents
    </li>
    <li>
      <b><i>%IP%</i></b><br>
      value of reading publicIP<br>
      can be used to send msg(s) with (new) IP address
    </li>
    <li>
      <b><i>%LIGHT%</i></b><br>
      value of the light reading of the HOMEMODE device
    </li>
    <li>
      <b><i>%LOCATION%</i></b><br>
      value of the location reading of the HOMEMODE device
    </li>
    <li>
      <b><i>%LOCATIONR%</i></b><br>
      value of the location reading of the last triggered resident
    </li>
    <li>
      <b><i>%LUMINANCE%</i></b><br>
      average luminance of motion sensors (if available)
    </li>
    <li>
      <b><i>%LUMINANCETREND%</i></b><br>
      value of the luminanceTrend reading of the HOMEMODE device<br>
      possible values: constant, rising, falling
    </li>
    <li>
      <b><i>%MODE%</i></b><br>
      current mode of the HOMEMODE device
    </li>
    <li>
      <b><i>%MOTION%</i></b><br>
      value of the lastMotion reading (last opened sensor)
    </li>
    <li>
      <b><i>%OPEN%</i></b><br>
      value of the contactsOutsideOpen_hr reading of the HOMEMODE device<br>
      can be used to send msg(s) in specific situations, e.g. to warn leaving residents of open contact sensors
    </li>
    <li>
      <b><i>%OPENCT%</i></b><br>
      value of the contactsOutsideOpen_ct reading of the HOMEMODE device<br>
      can be used to send msg(s) in specific situations depending on the number of open contact sensors, maybe in combination with placeholder %OPEN%
    </li>
    <li>
      <b><i>%PANIC%</i></b><br>
      state of panic, will return 1 if on and 0 if off
    </li>
    <li>
      <b><i>%RESIDENT%</i></b><br>
      name of the last triggered resident
    </li>
    <li>
      <b><i>%PRESENT%</i></b><br>
      presence of the HOMEMODE device<br>
      will return 1 if present or 0 if absent
    </li>
    <li>
      <b><i>%PRESENTR%</i></b><br>
      presence of last triggered resident<br>
      will return 1 if present or 0 if absent
    </li>
    <li>
      <b><i>%PRESSURE%</i></b><br>
      value of the pressure reading of the HOMEMODE device<br>
      can be used for weather info in HomeTextWeather attributes e.g.
    </li>
    <li>
      <b><i>%PRESSURETREND%</i></b><br>
      value of the pressure_trend_txt reading of the Yahoo weather device<br>
      can be used for weather info in HomeTextWeather attributes e.g.
    </li>
    <li>
      <b><i>%PREVAMODE%</i></b><br>
      previous alarm mode of the HOMEMODE device
    </li>
    <li>
      <b><i>%PREVCONTACT%</i></b><br>
      previous open contact sensor
    </li>
    <li>
      <b><i>%PREVMODE%</i></b><br>
      previous mode of the HOMEMODE device
    </li>
    <li>
      <b><i>%PREVMODER%</i></b><br>
      previous state of last triggered resident
    </li>
    <li>
      <b><i>%PREVMOTION%</i></b><br>
      previous open motion sensor
    </li>
    <li>
      <b><i>%SEASON%</i></b><br>
      value of the season reading of the HOMEMODE device
    </li>
    <li>
      <b><i>%SELF%</i></b><br>
      name of the HOMEMODE device itself
    </li>
    <li>
      <b><i>%SENSORSBATTERY%</i></b><br>
      all battery sensors from internal SENSORSBATTERY
    </li>
    <li>
      <b><i>%SENSORSCONTACT%</i></b><br>
      all contact sensors from internal SENSORSCONTACT
    </li>
    <li>
      <b><i>%SENSORSENERGY%</i></b><br>
      all energy sensors from internal SENSORSENERGY
    </li>
    <li>
      <b><i>%SENSORSMOTION%</i></b><br>
      all motion sensors from internal SENSORSMOTION
    </li>
    <li>
      <b><i>%TAMPERED%</i></b><br>
      will return all tampered sensors
    </li>
    <li>
      <b><i>%TAMPEREDCT%</i></b><br>
      will return the number of tampered sensors
    </li>
    <li>
      <b><i>%TEMPERATURE%</i></b><br>
      value of the temperature reading of the HOMEMODE device<br>
      can be used for weather info in HomeTextWeather attributes e.g.
    </li>
    <li>
      <b><i>%TEMPERATURETREND%</i></b><br>
      value of the temperatureTrend reading of the HOMEMODE device<br>
      possible values: constant, rising, falling
    </li>
    <li>
      <b><i>%TWILIGHT%</i></b><br>
      value of the twilight reading of the HOMEMODE device
    </li>
    <li>
      <b><i>%TWILIGHTEVENT%</i></b><br>
      current twilight event
    </li>
    <li>
      <b><i>%UWZ%</i></b><br>
      UWZ warnings count
    </li>
    <li>
      <b><i>%UWZLONG%</i></b><br>
      all current UWZ warnings as long text
    </li>
    <li>
      <b><i>%UWZSHORT%</i></b><br>
      all current UWZ warnings as short text
    </li>
    <li>
      <b><i>%WEATHER%</i></b><br>
      value of "get &lt;HOMEMODE&gt; weather short"<br>
      can be used for for msg weather info e.g.
    </li>
    <li>
      <b><i>%WEATHERLONG%</i></b><br>
      value of "get &lt;HOMEMODE&gt; weather long"<br>
      can be used for for msg weather info e.g.
    </li>
    <li>
      <b><i>%WIND%</i></b><br>
      value of the wind reading of the HOMEMODE device<br>
      can be used for weather info in HomeTextWeather attributes e.g.
    </li>
    <li>
      <b><i>%WINDCHILL%</i></b><br>
      value of the wind_chill reading of the Yahoo weather device<br>
      can be used for weather info in HomeTextWeather attributes e.g.
    </li>
  </ul>
  <p>These placeholders can only be used within HomeTextWeatherForecast attributes</p>
  <ul>
    <li>
      <b><i>%CONDITION%</i></b><br>
      value of weather forecast condition
    </li>
    <li>
      <b><i>%DAY%</i></b><br>
      day number of weather forecast
    </li>
    <li>
      <b><i>%HIGH%</i></b><br>
      value of maximum weather forecast temperature
    </li>
    <li>
      <b><i>%LOW%</i></b><br>
      value of minimum weather forecast temperature
    </li>
  </ul>
  <p>These placeholders can only be used within HomeCMDcontact, HomeCMDmotion and HomeCMDalarm attributes</p>
  <ul>
    <li>
      <b><i>%ALIAS%</i></b><br>
      alias of the last triggered contact/motion/smoke sensor
    </li>
    <li>
      <b><i>%SENSOR%</i></b><br>
      name of the last triggered contact/motion/smoke sensor
    </li>
    <li>
      <b><i>%STATE%</i></b><br>
      state of the last triggered contact/motion/smoke sensor
    </li>
  </ul>
  <p>These placeholders can only be used within calendar event related HomeCMDevent attributes</p>
  <ul>
    <li>
      <b><i>%CALENDAR%</i></b><br>
      name of the calendar
    </li>
    <li>
      <b><i>%EVENT%</i></b><br>
      current event of the calendar
    </li>
    <li>
      <b><i>%PREVEVENT%</i></b><br>
      previous event of the calendar
    </li>
  </ul>
</ul>

=end html
=cut
