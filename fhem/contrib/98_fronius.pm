# $Id$
#
##############################################
#
# 2025.01.16 - DS_Starter / fichtennadel v0.3
# - CHANGE: 
#          - check for init_done in fronius_StartUp loop instead of define (https://forum.fhem.de/index.php?topic=139206.msg1330774#msg1330774)
#
# 2024.05.27 - fichtennadel v0.2
# - CHANGE: 
#          - set GetActiveDeviceInfo
#          - re-init timer for fronius_GetActiveDeviceInfo in fronius_GetMeterRealtimeData and fronius_GetInverterRealtimeData if DeviceInfo_ is missing
#          - internal VERSION          
#
# 2024.05.27 - fichtennadel v0.1
# - INFO:  check in to svn trunk/fhem/contrib/fichtennadel 
#          - renamed file to lower case fronius to match device type (fhem standard)
#          - no functional changes
#          - removed links to outdated docs 
#          - extended copyright
#
# 2024.04.24 - fichtennadel v0.0.11d
# - CHANGE:  for inverters in standby during fhem start:
#             re-init fronius_GetAPIVersionInfo, if FroniusBaseURL is not set
# 2024.01.10 - fichtennadel v0.0.11c
# - CHANGE:  for inverters in standby during fhem start:
#             re-init fronius_GetAPIVersionInfo, if FroniusBaseURL is not set
#             fronius_Get*Data: always create timer , even if $hash->{helper}{VARS}... is not set
#
# 2023.10.01 - fichtennadel v0.0.10
# - CHANGE:  GetArchiveData API parameter StartDate+EndDate in UTC
# - CHANGE:  internal: perl use strict, NOTIFY nur von global
#
# 2023.09.30 - fichtennadel v0.0.9
# - CHANGE:  kask 2023.09.23 - https://forum.fhem.de/index.php?topic=113850.msg1287616#msg1287616
#              - Add: Modul kann mit IntervalRealtimeData <= 0 mit dem command "GetAllData"(und einzel) zum Daten abholen gezwungen werden. 
#                Die Reihenfolge der einzelnen Datensätze kann Frei gewählt werden.
#                Es erfolgt bei IntervalRealtimeData <= 0 keine automatische Datenabfrage mehr!
# - CHANGE:  spezifische, parametrisierbare Intervalle je Datenset
#              IntervalPowerFlowRealtimeData, IntervalArchiveData, IntervalStorageRealtimeData, IntervalMeterRealtimeData, IntervalInverterRealtimeData
# - CHANGE:  GetArchiveData:
#             - eigenständig, für IntervalArchiveData = 300 an fixen 5 Minuten-Intervallen ausgerichtet (minimales Datenintervall vom Fronius ist 5min)
#             - zusätzlich Verbrauchswerte für konsistente Berechnungen (Realtime Inverter + Meter Daten sind getrennt)
#                 EnergyReal_WAC_Sum_Produced, EnergyReal_WAC_Minus_Absolute, EnergyReal_WAC_Plus_Absolute, PowerReal_PAC_Sum
#             - Sekunden fix :00 (sonst leere Response von Fronius)
# - BUG:     Sommer/Winterzeit (https://forum.fhem.de/index.php?topic=113850.msg1277280#msg1277280)
# - BUG:     Timer erst nach init_done setzen (https://forum.fhem.de/index.php?topic=113850.msg1285030#msg1285030)
#
#
#
##############################################
#  Copyright by Michael Winkler v0.0.1 - v0.0.8
#  e-mail: michael.winkler at online.de
#
#
# 2022.11.14 v0.0.8
# - BUG:     Sommer/Winterzeit
#
# 2022.07.13 v0.0.7
# - BUG:     Doppelte Verwendung des Moduls z.B. 2x Fronius Wechselrichter
# - CHANGE:  Keepalive = 0
# - FEATURE: MPPT1 & MPPT2 aus den Archivdaten
#
# 2021.10.20 v0.0.6
# - BUG:     https://forum.fhem.de/index.php/topic,113850.msg1180843.html#msg1180843 (Danke carlos)
#
# 2021.10.19 v0.0.5
# - BUG:     https://forum.fhem.de/index.php/topic,113850.msg1156141.html#msg1156141 (Danke carlos)
#
# 2021.04.13 v0.0.4
# - CHANGE:  Meldung [name] [fronius_setState] to connected entfernt
#
# 2020.08.28 v0.0.3
# - BUG:     Write Boolean Data from JSON
# - CHANGE:  Logging
#
# 2020.08.28 v0.0.2
# - CHANGE:  Anpassungen Dokumentation
#            Query API Version & Base URL
#            Codebereinigung
#
# 2020.08.26 v0.0.1
# - CHANGE:  erste Version
# - FEATURE: erste Version
# - BUG:     erste Version
#
#
##############################################
#
#  This file is part of fhem.
#
#  Fhem is free software: you can redistribute it andor modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 2 of the License, or
#  (at your option) any later version.
#
#  Fhem is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
#  https://forum.fhem.de/index.php?topic=138356.0
#
##############################################################################

package main;

use strict;
use Time::Local;
use Encode;
use Encode qw/from_to/;
use URI::Escape;
use Data::Dumper;
use JSON;
use utf8;
use Date::Parse;
use Time::Piece;
use lib ('./FHEM/lib', './lib');

my $ModulVersion        = "0.3";

##############################################################################
sub fronius_Initialize($) {
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  $hash->{DefFn}        = "fronius_Define";
  $hash->{UndefFn}      = "fronius_Undefine";
  $hash->{NOTIFYDEV}    = "global";
  $hash->{NotifyFn}     = "fronius_Notify";
  #$hash->{GetFn}        = "fronius_Get";
  $hash->{SetFn}        = "fronius_Set";
  $hash->{AttrFn}       = "fronius_Attr";
  $hash->{AttrList}     = "disable:0,1 ".
                          "DeviceId ".
                          "IntervalRealtimeData ".
                          "IntervalPowerFlowRealtimeData ".
                          "IntervalArchiveData ".
                          "IntervalStorageRealtimeData ".
                          "IntervalMeterRealtimeData ".
                          "IntervalInverterRealtimeData ".
                          "SaveDataHead:0,1 ".
                          $readingFnAttributes;
}

sub fronius_Define($$$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  
  return "syntax: define <name> Fronius <IP>" if(int(@a) != 3 );
  my $name = $hash->{NAME};

  # Fronius Smart Meter
  $hash->{helper}{VARS}{FroniusIP} = $a[2];

  # nur notifies für global
  $hash->{NOTIFYDEV} = "global";

  # current version
  $hash->{VERSION} = $ModulVersion;
  
  # Internaltimer löschen
  RemoveInternalTimer($hash);

  # Module zurücksetzen
  $hash->{helper}{VARS}{FroniusBaseURL}      = "nA";
  $hash->{helper}{VARS}{Smart_Meter}         = "nA";
  $hash->{helper}{VARS}{Smart_Inverter}      = "nA";
  $hash->{helper}{VARS}{Smart_Storage}       = "nA";
  $hash->{helper}{VARS}{Smart_OhmPilot}      = "nA";
  $hash->{helper}{VARS}{Smart_SensorCard}    = "nA";
  $hash->{helper}{VARS}{Smart_StringControl} = "nA";
  
  # for WR in StandBy
  $hash->{helper}{VARS}{ReInitGetAPIVersionInfo} = 0;
  
  fronius_StartUp($hash);
  
  return undef;
}

sub fronius_Undefine($$) {
    my ( $hash, $arg ) = @_;
    my $name = $hash->{NAME};

    Log3 $name, 3, "Fronius $name [fronius_Undefine] called function";

    # Stop the internal GetStatus-Loop and exit
    RemoveInternalTimer($hash);

    return;
}

sub fronius_StartUp($) {
  my ($hash)       = @_;
  my $name = $hash->{NAME};
  
  RemoveInternalTimer ($hash, 'fronius_StartUp');

  if (!$init_done) {
      InternalTimer (gettimeofday() + 2, 'fronius_StartUp', $hash, 0);
      return;
  }
  
  my $interval     = List::Util::max(AttrVal( $name, "IntervalArchiveData", AttrVal( $name, "IntervalRealtimeData", 300 ) ), 300);

  Log3 $name, 4, "[$name] [fronius_StartUp]";

  # Datenbereinigung
  fronius_clearHeadData($hash);
  Log3 $name, 4, "[$name] [fronius_StartUp] clearHeadData";
  
  # State
  fronius_setState($hash,"initialize");
  
  # Internaltimer löschen
  RemoveInternalTimer($hash);
  Log3 $name, 4, "[$name] [fronius_StartUp] RemoveInternalTimer";

  # Internaltimer Statische Daten
  InternalTimer(gettimeofday() + 0 , "fronius_GetAPIVersionInfo",   $hash, 0);
  InternalTimer(gettimeofday() + 5 , "fronius_GetActiveDeviceInfo", $hash, 0);
  Log3 $name, 4, "[$name] [fronius_StartUp] InternalTimer Statische Daten";
  
  # Internaltimer Realtime Daten
  InternalTimer(gettimeofday() + 10, "fronius_GetPowerFlowRealtimeData", $hash, 0) if AttrVal( $name, "IntervalPowerFlowRealtimeData", AttrVal( $name, "IntervalRealtimeData", 60 ) ) > 0;
  InternalTimer(gettimeofday() + 12, "fronius_GetStorageRealtimeData",   $hash, 0) if AttrVal( $name, "IntervalStorageRealtimeData"  , AttrVal( $name, "IntervalRealtimeData", 60 ) ) > 0;
  InternalTimer(gettimeofday() + 14, "fronius_GetMeterRealtimeData",     $hash, 0) if AttrVal( $name, "IntervalMeterRealtimeData"    , AttrVal( $name, "IntervalRealtimeData", 60 ) ) > 0;
  InternalTimer(gettimeofday() + 16, "fronius_GetInverterRealtimeData",  $hash, 0) if AttrVal( $name, "IntervalInverterRealtimeData" , AttrVal( $name, "IntervalRealtimeData", 60 ) ) > 0;
  Log3 $name, 4, "[$name] [fronius_StartUp] InternalTimer Realtime Daten";

  # align GetArchiveData on 5min intervals
  $interval = AttrVal( $name, "IntervalArchiveData", AttrVal( $name, "IntervalRealtimeData", 300 ) );
  if ($interval > 0) {
    # Fronius Solar API V1 Doku - "Archive requests are not allowed to be performed in parallel and need to keep a timeout of 120 seconds between two consecutive calls."
    $interval = $interval < 120 ? 120 : $interval;
    if ($interval == 300) {
      my ($sec,$min) = localtime;
      my $rounded_min = ceil(($min+1)/5) * 5;
      
      $interval = ($rounded_min*60) - ($min*60+$sec);
    }
    InternalTimer(gettimeofday() + $interval, "fronius_GetArchiveData",           $hash, 0);
    Log3 $name, 4, "[$name] [fronius_StartUp] InternalTimer Archive Daten - $interval";
  }
  
  Log3 $name, 4, "[$name] [fronius_StartUp] done";
  
  return;
}

sub fronius_Notify($$) {
  my ($hash,$dev) = @_;
  my $name = $hash->{NAME};
  return if($dev->{NAME} ne "global");
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));
  
  Log3 $name, 4, "[$name] [fronius_Notify] reload";
  
  # (re)create timer
  fronius_StartUp($hash);
  
  return undef;
}

sub fronius_Get($@) {
  my ($hash, @a) = @_;
  shift @a;
  my $command = shift @a;
  my $parameter = join(' ',@a);
  my $name = $hash->{NAME};

  my $usage = "Unknown argument $command, choose one of ";

  return $usage;
}

sub fronius_Set($@) {
  my ($hash, $name, $opt, @a) = @_;
  my $interval     = AttrVal( $name, "IntervalRealtimeData", 60 );
  #my @options = ("GetAllData","GetPowerFlowData","GetStorageData","GetMeterData","GetInverterData","RestartInterval");
  my %sets = (
    "GetAllData" => "noArg",
    "GetPowerFlowData" => "noArg",
    "GetStorageData" => "noArg",
    "GetMeterData" => "noArg",
    "GetInverterData" => "noArg",
    "GetActiveDeviceInfo" => "noArg",
    "RestartInterval" => "noArg"
    );
  my %order = (
    "PowerFlow" => -1,
    "Storage" => -1,
    "Meter" => -1,
    "Inverter" => -1
    );

  Log3 $name, 4, "[$name] [fronius_Set] $opt" if (($opt ne '?') && ($opt ne ''));
  
  if (($opt eq '?') || ($opt eq '')){
      #return join( ' ', @options);
      return join(" ", sort keys %sets);
      
  } elsif ($opt eq 'RestartInterval') {
    RemoveInternalTimer($hash, "fronius_GetAPIVersionInfo");
    RemoveInternalTimer($hash, "fronius_GetActiveDeviceInfo");
    RemoveInternalTimer($hash, "fronius_GetPowerFlowRealtimeData");
    RemoveInternalTimer($hash, "fronius_GetStorageRealtimeData");
    RemoveInternalTimer($hash, "fronius_GetMeterRealtimeData");
    RemoveInternalTimer($hash, "fronius_GetInverterRealtimeData");
    InternalTimer(gettimeofday() +      $interval, "fronius_GetAPIVersionInfo",        $hash, 0);
    InternalTimer(gettimeofday() +  5 + $interval, "fronius_GetActiveDeviceInfo",      $hash, 0);
    InternalTimer(gettimeofday() + 10 + $interval, "fronius_GetPowerFlowRealtimeData", $hash, 0);
    InternalTimer(gettimeofday() + 15 + $interval, "fronius_GetStorageRealtimeData",   $hash, 0);
    InternalTimer(gettimeofday() + 20 + $interval, "fronius_GetMeterRealtimeData",     $hash, 0);
    InternalTimer(gettimeofday() + 25 + $interval, "fronius_GetInverterRealtimeData",  $hash, 0);
    
  } elsif ($interval le 0) {
    if ($opt eq 'GetAllData') {
      #übergabeparameter durchsuchen auf gültigkeit und übernehmen
      my $tdelay = 0;
      while(my $arg = shift(@a)){
        if( exists($order{$arg} ) ) {
          if ($order{$arg} lt 0){
            $order{$arg} = $tdelay;
            Log3 $name, 5, "[$name] [fronius_Set] arg set = $arg=$tdelay";
            $tdelay = $tdelay+2;
          }
        }
        Log3 $name, 5, "[$name] [fronius_Set] arg = $arg";
      }
      #reihenfolge aufarbeiten für nicht vorhandene calls in den übergabe parametern
      my @getorder = split ( /\s+/, join(" ", keys %order) );
      while(my $func = shift(@getorder)){
        if ($order{$func} lt 0){
          $order{$func} = $tdelay;
          $tdelay = $tdelay+2;
        }
        Log3 $name, 5, "[$name] [fronius_Set] order $func=$order{$func}";
      }
      InternalTimer(gettimeofday() + $order{"PowerFlow"}, "fronius_GetPowerFlowRealtimeData", $hash, 0);
      InternalTimer(gettimeofday() + $order{"Storage"}, "fronius_GetStorageRealtimeData",   $hash, 0);
      InternalTimer(gettimeofday() + $order{"Meter"}, "fronius_GetMeterRealtimeData",     $hash, 0);
      InternalTimer(gettimeofday() + $order{"Inverter"}, "fronius_GetInverterRealtimeData",  $hash, 0);
    } elsif ($opt eq 'GetPowerFlowData') {
      InternalTimer(gettimeofday(), "fronius_GetPowerFlowRealtimeData",   $hash, 0);
    } elsif ($opt eq 'GetStorageData') {
      InternalTimer(gettimeofday(), "fronius_GetStorageRealtimeData",   $hash, 0);
    } elsif ($opt eq 'GetMeterData') {
      InternalTimer(gettimeofday(), "fronius_GetMeterRealtimeData",     $hash, 0);
    } elsif ($opt eq 'GetInverterData') {
      InternalTimer(gettimeofday(), "fronius_GetInverterRealtimeData",  $hash, 0);
    } elsif ($opt eq 'GetActiveDeviceInfo') {
      RemoveInternalTimer($hash, "fronius_GetActiveDeviceInfo");
      InternalTimer(gettimeofday(), "fronius_GetActiveDeviceInfo",  $hash, 0);
    } else {
      #return "Unknown argument $opt choose one of : " . join( ', ', @options);
      return "Unknown argument $opt choose one of : " . join(" ", sort keys %sets) . 
             ".\x0D\x0A Or GetAllData with order argumens of \"".join("\",\"", sort keys %order)."\"". 
             ".\x0D\x0A\x0D\x0A Example: Set $name GetAllData Inverter Meter". 
             "\x0D\x0A With this example the get commands for the $name will be in the following order: GetInverterData, GetMeterData afterwards automaticaly GetPowerflow and GetStorageData";
    }
  } else {
    return "Set $opt not ok, IntervalRealtimeData > 0. Restart Interval with : set $name RestartInterval";
  }
  return undef;
}

sub fronius_Attr($$$) {
  
  my ($cmd, $name, $attrName, $attrVal) = @_;
  my $hash = $defs{$name};
  
  Log3 $name, 5, "[$name] [fronius_Attr] attrName=$attrName";
  
  if ( $attrName eq "SaveDataHead" ) {
    fronius_clearHeadData($hash);
  }
  
  return;  
}

#########################
# Standard Request
#########################
sub fronius_GetAPIVersionInfo($) {

  my ($hash)       = @_;
  my $name         = $hash->{NAME};
  my $interval     = 36000;
  
  $hash->{helper}{VARS}{ReInitGetAPIVersionInfo} = 0;
  
  fronius_SendCommand($hash,"GetAPIVersionInfo","");
  
  InternalTimer(gettimeofday() + $interval, "fronius_GetAPIVersionInfo", $hash, 0);
}

sub fronius_GetActiveDeviceInfo($) {

  my ($hash)       = @_;
  my $name         = $hash->{NAME};
  my $interval     = 36000;
  
  fronius_SendCommand($hash,"GetActiveDeviceInfo","");
  
  InternalTimer(gettimeofday() + $interval, "fronius_GetActiveDeviceInfo", $hash, 0);
}

#########################
# RealtimeData
#########################
sub fronius_GetPowerFlowRealtimeData($) {

  my ($hash)       = @_;
  my $name         = $hash->{NAME};
  my $interval     = AttrVal( $name, "IntervalPowerFlowRealtimeData", AttrVal( $name, "IntervalRealtimeData", 60 ) );
  
  fronius_SendCommand($hash,"GetPowerFlowRealtimeData","");
  
  if ($interval > 0) {
    InternalTimer(gettimeofday() + $interval, "fronius_GetPowerFlowRealtimeData", $hash, 0);
    Log3 $name, 4, "[$name] [fronius_GetPowerFlowRealtimeData] Timer $interval";
  } else {
    RemoveInternalTimer($hash, "fronius_GetPowerFlowRealtimeData");
    Log3 $name, 4, "[$name] [fronius_GetPowerFlowRealtimeData] Timer removed";
  }
}

sub fronius_GetArchiveData($) {

  my ($hash)       = @_;
  my $name         = $hash->{NAME};
  my $interval     = AttrVal( $name, "IntervalArchiveData", AttrVal( $name, "IntervalRealtimeData", 300 ) );
  
  fronius_SendCommand($hash,"GetArchiveData","");
  
  if ($interval > 0) {
    
    # Fronius Solar API V1 Doku - "Archive requests are not allowed to be performed in parallel and need to keep a timeout of 120 seconds between two consecutive calls."
    $interval = $interval < 120 ? 120 : $interval;
    
    # align on 5min intervals
    if ($interval == 300) {
      my ($sec,$min) = localtime;
      my $rounded_min = ceil(($min+1)/5) * 5;
      
      $interval = ($rounded_min*60) - ($min*60+$sec);
    }
    
    InternalTimer(gettimeofday() + $interval, "fronius_GetArchiveData", $hash, 0);
    Log3 $name, 4, "[$name] [fronius_GetArchiveData] Timer $interval";
  } else {  
    RemoveInternalTimer($hash, "fronius_GetArchiveData");
    Log3 $name, 4, "[$name] [fronius_GetArchiveData] Timer removed";
  }
}


sub fronius_GetStorageRealtimeData($) {

  my ($hash)        = @_;
  my $name          = $hash->{NAME};
  my $interval      = AttrVal( $name, "IntervalStorageRealtimeData", AttrVal( $name, "IntervalRealtimeData", 60 ) );
  my $StorageNumber = 999999999999;
  
  if ($hash->{helper}{VARS}{Smart_Storage} ne "nA") {
    foreach my $StorageDevice (sort keys %{$hash->{READINGS}}) {
      if ($StorageDevice =~ m/DeviceInfo_Storage_/ ) {
        my @StorageReading = split("\_",$StorageDevice);
          if ($StorageNumber != $StorageReading[2]) {
            $StorageNumber = $StorageReading[2];
            Log3 $name, 5, "[$name] [fronius_GetStorageRealtimeData] Start Storage $StorageNumber";
            fronius_SendCommand($hash,"GetStorageRealtimeData",$StorageNumber);
          }else {Log3 $name, 5, "[$name] [fronius_GetStorageRealtimeData] SKIP Storage $StorageNumber";}
      }
    } 

  } else {
    Log3 $name, 4, "[$name] [fronius_GetStorageRealtimeData] removing DeviceInfo_Storage_ readings";
    # Eventuell vorhandene Daten wieder löschen!
    foreach my $StorageDevice (sort keys %{$hash->{READINGS}}) {
      readingsDelete($hash, $StorageDevice) if ($StorageDevice =~ m/DeviceInfo_Storage_/ );
    }
    
    Log3 $name, 4, "[$name] [fronius_GetStorageRealtimeData] calling GetActiveDeviceInfo";
    fronius_SendCommand($hash,"GetActiveDeviceInfo","");
  }

  if ($interval > 0) {
    InternalTimer(gettimeofday() + $interval, "fronius_GetStorageRealtimeData", $hash, 0);  
    Log3 $name, 4, "[$name] [fronius_GetStorageRealtimeData] Timer $interval";
  } else {  
    RemoveInternalTimer($hash, "fronius_GetStorageRealtimeData");
    Log3 $name, 4, "[$name] [fronius_GetStorageRealtimeData] Timer removed";
  }
  
}

sub fronius_GetMeterRealtimeData($) {

  my ($hash)        = @_;
  my $name          = $hash->{NAME};
  my $interval      = AttrVal( $name, "IntervalMeterRealtimeData", AttrVal( $name, "IntervalRealtimeData", 60 ) );
  my $MeterNumber   = 999999999999;
  
  if ($hash->{helper}{VARS}{Smart_Meter} ne "nA") {
    foreach my $MeterDevice (sort keys %{$hash->{READINGS}}) {
      if ($MeterDevice =~ m/DeviceInfo_Meter_/ ) {
        my @MeterReading = split("\_",$MeterDevice);
          if ($MeterNumber != $MeterReading[2]) {
            $MeterNumber = $MeterReading[2];
            Log3 $name, 5, "[$name] [fronius_GetMeterRealtimeData] Start Storage $MeterNumber";
            fronius_SendCommand($hash,"GetMeterRealtimeData",$MeterNumber);
          }else {Log3 $name, 5, "[$name] [fronius_GetMeterRealtimeData] SKIP Storage $MeterNumber";}
      }
    } 

  } else {
    Log3 $name, 4, "[$name] [fronius_GetMeterRealtimeData] removing DeviceInfo_Meter_ readings";
    # Eventuell vorhandene Daten wieder löschen!
    foreach my $MeterDevice (sort keys %{$hash->{READINGS}}) {
      readingsDelete($hash, $MeterDevice) if ($MeterDevice =~ m/DeviceInfo_Meter_/ );
    }

    Log3 $name, 4, "[$name] [fronius_GetStorageRealtimeData] calling GetActiveDeviceInfo";
    fronius_SendCommand($hash,"GetActiveDeviceInfo","");
  }

  if ($interval > 0) {
    InternalTimer(gettimeofday() + $interval, "fronius_GetMeterRealtimeData", $hash, 0);  
    Log3 $name, 4, "[$name] [fronius_GetMeterRealtimeData] Timer $interval";
  } else {  
    RemoveInternalTimer($hash, "fronius_GetMeterRealtimeData");
    Log3 $name, 4, "[$name] [fronius_GetMeterRealtimeData] Timer removed";
  }

}

sub fronius_GetInverterRealtimeData($) {

  my ($hash)        = @_;
  my $name          = $hash->{NAME};
  my $interval      = AttrVal( $name, "IntervalInverterRealtimeData", AttrVal( $name, "IntervalRealtimeData", 60 ) );
  my $InverterNumber   = 999999999999;
  
  if ($hash->{helper}{VARS}{Smart_Inverter} ne "nA") {
  
    fronius_SendCommand($hash,"GetInverterRealtimeData_System",$InverterNumber);
  
    foreach my $InverterDevice (sort keys %{$hash->{READINGS}}) {
      if ($InverterDevice =~ m/DeviceInfo_Inverter_/ ) {
        my @InverterReading = split("\_",$InverterDevice);
          if ($InverterNumber != $InverterReading[2]) {
            $InverterNumber = $InverterReading[2];
            Log3 $name, 5, "[$name] [fronius_GetInverterRealtimeData] Start Storage $InverterNumber";
            fronius_SendCommand($hash,"GetInverterRealtimeData_Cumulation",$InverterNumber);
            fronius_SendCommand($hash,"GetInverterRealtimeData_Common",$InverterNumber);
            fronius_SendCommand($hash,"GetInverterRealtimeData_3P",$InverterNumber);
          }else {Log3 $name, 5, "[$name] [fronius_GetInverterRealtimeData] SKIP Storage $InverterNumber";}
      }
    } 

  } else {
    Log3 $name, 4, "[$name] [fronius_GetInverterRealtimeData] removing DeviceInfo_Inverter_ readings";
    # Eventuell vorhandene Daten wieder löschen!
    foreach my $InverterDevice (sort keys %{$hash->{READINGS}}) {
      readingsDelete($hash, $InverterDevice) if ($InverterDevice =~ m/DeviceInfo_Inverter_/ );
    }

    Log3 $name, 4, "[$name] [fronius_GetInverterRealtimeData] calling GetActiveDeviceInfo";
    fronius_SendCommand($hash,"GetActiveDeviceInfo","");
  }

  if ($interval > 0) {
    InternalTimer(gettimeofday() + $interval, "fronius_GetInverterRealtimeData", $hash, 0); 
    Log3 $name, 4, "[$name] [fronius_GetInverterRealtimeData] Timer $interval";
  } else {  
    RemoveInternalTimer($hash, "fronius_GetInverterRealtimeData");
    Log3 $name, 4, "[$name] [fronius_GetInverterRealtimeData] Timer removed";
  }

}


#########################
sub fronius_SendCommand($$$) {
  my ( $hash, $type, $SendData ) = @_;
  my $name = $hash->{NAME};
  
  Log3 $name, 4, "[$name] [fronius_SendCommand] [$type] START"; 
  
  my $SendUrl;
  
  # JSON Auswertung
  if ($type eq "GetAPIVersionInfo") {
    $SendUrl   = "http://" . $hash->{helper}{VARS}{FroniusIP} . "/solar_api/GetAPIVersion.cgi";
  }
  elsif ($type eq "GetPowerFlowRealtimeData") {
    $SendUrl   = "http://" . $hash->{helper}{VARS}{FroniusIP} . $hash->{helper}{VARS}{FroniusBaseURL} . "GetPowerFlowRealtimeData.fcgi";
  }
  elsif ($type eq "GetStorageRealtimeData") {
    $SendUrl   = "http://" . $hash->{helper}{VARS}{FroniusIP} . $hash->{helper}{VARS}{FroniusBaseURL} . "GetStorageRealtimeData.cgi?Scope=System&DeviceId=$SendData";
  }
  elsif ($type eq "GetMeterRealtimeData") {
    $SendUrl   = "http://" . $hash->{helper}{VARS}{FroniusIP} . $hash->{helper}{VARS}{FroniusBaseURL} . "GetMeterRealtimeData.cgi?Scope=System&DeviceId=$SendData";
  }
  elsif ($type eq "GetActiveDeviceInfo") {
    $SendUrl   = "http://" . $hash->{helper}{VARS}{FroniusIP} . $hash->{helper}{VARS}{FroniusBaseURL} . "GetActiveDeviceInfo.cgi?DeviceClass=System";
  }
  elsif ($type eq "GetInverterRealtimeData_System") {
    $SendUrl   = "http://" . $hash->{helper}{VARS}{FroniusIP} . $hash->{helper}{VARS}{FroniusBaseURL} . "GetInverterRealtimeData.cgi?Scope=System";
  }
  elsif ($type eq "GetInverterRealtimeData_Cumulation") {
    $SendUrl   = "http://" . $hash->{helper}{VARS}{FroniusIP} . $hash->{helper}{VARS}{FroniusBaseURL} . "GetInverterRealtimeData.cgi?Scope=Device&DeviceId=$SendData&DataCollection=CumulationInverterData";
  }
  elsif ($type eq "GetInverterRealtimeData_Common") {
    $SendUrl   = "http://" . $hash->{helper}{VARS}{FroniusIP} . $hash->{helper}{VARS}{FroniusBaseURL} . "GetInverterRealtimeData.cgi?Scope=Device&DeviceId=$SendData&DataCollection=CommonInverterData";
  }
  elsif ($type eq "GetInverterRealtimeData_3P") {
    $SendUrl   = "http://" . $hash->{helper}{VARS}{FroniusIP} . $hash->{helper}{VARS}{FroniusBaseURL} . "GetInverterRealtimeData.cgi?Scope=Device&DeviceId=$SendData&DataCollection=3PInverterData";
  }
  elsif ($type eq "GetArchiveData") {
    my $today = time;
    my $StartDate = strftime "%Y-%m-%dT%H:%M:00Z", gmtime($today - 300); # Fronius Solar API V1 Doku - "...intervals which can be set between 5 and 30 minutes..."
    my $EndDate = strftime "%Y-%m-%dT%H:%M:00Z", gmtime($today);
    $SendUrl   = "http://" . $hash->{helper}{VARS}{FroniusIP} . $hash->{helper}{VARS}{FroniusBaseURL} . "GetArchiveData.cgi?Scope=System&StartDate=$StartDate&EndDate=$EndDate&Channel=Current_DC_String_1&Channel=Current_DC_String_2&Channel=Voltage_DC_String_1&Channel=Voltage_DC_String_2&Channel=EnergyReal_WAC_Sum_Produced&Channel=EnergyReal_WAC_Minus_Absolute&Channel=EnergyReal_WAC_Plus_Absolute&Channel=PowerReal_PAC_Sum";
  }
  else {
    Log3 $name, 3, "[$name] [fronius_SendCommand] [$type] ERROR=Type is unkown!!";
    return;
  }
    
  #2018.01.14 - PushToCmdQueue
  if ($hash->{helper}{VARS}{FroniusBaseURL} eq "nA" && $type ne "GetAPIVersionInfo") {
    Log3 $name, 4, "[$name] [fronius_SendCommand] [$type] NOT PushToCmdQueue ERROR=Fronius API Base URL not set!";
    
    if ($hash->{helper}{VARS}{ReInitGetAPIVersionInfo} == 0) {
      RemoveInternalTimer($hash, "fronius_GetAPIVersionInfo");
      InternalTimer(gettimeofday() + 60 , "fronius_GetAPIVersionInfo", $hash, 0);
      $hash->{helper}{VARS}{ReInitGetAPIVersionInfo} = 1;
      Log3 $name, 4, "[$name] [fronius_SendCommand] [$type] re-init fronius_GetAPIVersionInfo";
    }  
  }
  else {
  
    #2018.01.14 - Übergabe SendCommandQuery
    my $SendParam = {
      url             => $SendUrl,
      hash            => $hash,
      CL              => $hash->{CL},
      httpversion     => "1.1",
      type            => $type
    };
  
    Log3 $name, 4, "[$name] [fronius_SendCommand] [$type] PushToCmdQueue SendURL=" . $SendUrl;
    push @{$hash->{helper}{CMD_QUEUE}}, $SendParam;  
    fronius_HandleCmdQueue($hash);
  }
  
  return;
}

sub fronius_HandleCmdQueue($) {
  my ($hash, $param)  = @_;
  my $name            = $hash->{NAME};
  
  return undef if(!defined($hash->{helper}{CMD_QUEUE})); 
  $hash->{helper}{RUNNING_REQUEST} = 0 if(!defined($hash->{helper}{RUNNING_REQUEST})); 
    
    if(not($hash->{helper}{RUNNING_REQUEST}) and @{$hash->{helper}{CMD_QUEUE}})
    {
  
    my $params =  {
                       url             => $param->{url},
                       timeout         => 10,
                       noshutdown      => 1,
                       keepalive       => 0,
                       method          => "GET",
                       CL              => $param->{CL},
                       hash            => $hash,
                       type            => $param->{type},
                       httpversion     => $param->{httpversion},
                       callback        => \&fronius_Parse
                      };
  
        my $request = pop @{$hash->{helper}{CMD_QUEUE}};

        map {$hash->{helper}{".HTTP_CONNECTION"}{$_} = $params->{$_}} keys %{$params};
        map {$hash->{helper}{".HTTP_CONNECTION"}{$_} = $request->{$_}} keys %{$request};
    
    my $type = $hash->{helper}{".HTTP_CONNECTION"}{type};
        
        $hash->{helper}{RUNNING_REQUEST} = 1;
        Log3 $name, 4, "[$name] [fronius_HandleCmdQueue] [$type] send command=" . $hash->{helper}{".HTTP_CONNECTION"}{url};
        HttpUtils_NonblockingGet($hash->{helper}{".HTTP_CONNECTION"});
    
    }
}

sub fronius_Parse($$$) {
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $msgtype = $param->{type};
  
  Log3 $name, 4, "[$name] [fronius_Parse] [$msgtype] ";
  Log3 $name, 5, "[$name] [fronius_Parse] [$msgtype] DATA Header=" . $param->{httpheader};
  Log3 $name, 5, "[$name] [fronius_Parse] [$msgtype] DATA Dumper=" . $data;

  $hash->{helper}{RUNNING_REQUEST} = 0;

  # Connection prüfen
  if ($err) {
    Log3 $name, 3, "[$name] [fronius_Parse] [$msgtype] ERROR=$err";
    fronius_setState($hash,"disconnected");
  }
  else {

    fronius_setState($hash,"connected");
    # HTML Informationen mit schreiben

    # Prüfen ob es sich um ein json String handelt!
    if (index($data, '{') == -1) {$data = '{"data": "nodata"}';}
    
    my $json = eval { JSON->new->utf8(0)->decode($data) };
    
    readingsBeginUpdate($hash);
    
    if    ($msgtype eq "GetAPIVersionInfo") {
      fronius_expandJSON($hash,$name,"",$json,"API_");
    } 
    elsif ($msgtype eq "GetPowerFlowRealtimeData") {
      fronius_expandJSON($hash,$name,"",$json,"PowerFlow_");
    } 
    elsif ($msgtype eq "GetActiveDeviceInfo") {
      fronius_expandJSON($hash,$name,"",$json,"DeviceInfo_");
    }
    elsif ($msgtype eq "GetStorageRealtimeData") {
      fronius_expandJSON($hash,$name,"",$json,"Storage_");
    }
    elsif ($msgtype eq "GetMeterRealtimeData") {
      fronius_expandJSON($hash,$name,"",$json,"Meter_");
    }
    elsif ($msgtype eq "GetInverterRealtimeData_System") {
      fronius_expandJSON($hash,$name,"",$json,"Inverter_System_");
    } 
    elsif ($msgtype eq "GetInverterRealtimeData_Cumulation") {
      fronius_expandJSON($hash,$name,"",$json,"Inverter_Cumulation_");
    }
    elsif ($msgtype eq "GetInverterRealtimeData_Common") {
      fronius_expandJSON($hash,$name,"",$json,"Inverter_Common_");
    }
    elsif ($msgtype eq "GetInverterRealtimeData_3P") {
      fronius_expandJSON($hash,$name,"",$json,"Inverter_3P_");
    } 
    elsif ($msgtype eq "GetArchiveData") {
      fronius_expandJSON($hash,$name,"",$json,"ArchiveData_");
      # Umrechnen in WATT
      readingsBulkUpdate($hash, "MPPT1_DC_W", ReadingsVal($name, "MPPT1_DC_A", 0) * ReadingsVal($name, "MPPT1_DC_V", 0) );
      readingsBulkUpdate($hash, "MPPT2_DC_W", ReadingsVal($name, "MPPT2_DC_A", 0) * ReadingsVal($name, "MPPT2_DC_V", 0) );
    } 
    else {
      Log3 $name, 4, "[$name] [fronius_Parse] [$msgtype] json for unknown message \n". $json;
    }
    
    readingsEndUpdate( $hash, 1 );

  }
  
  fronius_HandleCmdQueue($hash);

  return undef;
}

sub fronius_expandJSON($$$$;$$) {
  my ($hash,$dhash,$sPrefix,$ref,$prefix,$suffix) = @_;
  my ($name,$type) = ($hash->{NAME},$hash->{TYPE});
  my $SaveDataHead   = AttrVal( $name, "SaveDataHead", 0 );
  
  $prefix = "" if( !$prefix );
  $suffix = "" if( !$suffix );
  $suffix = "_$suffix" if( $suffix );

  if( ref( $ref ) eq "ARRAY" ) {
    while( my ($key,$value) = each @{ $ref } ) {
      fronius_expandJSON($hash,$name,"",$value, $prefix.sprintf("%02i",$key+1)."_");
    }
  }
  
  elsif( ref( $ref ) eq "HASH" ) {
    while( my ($key,$value) = each %{ $ref } ) {
      if( ref( $value ) && ref($value) ne "JSON::PP::Boolean") {
        fronius_expandJSON($hash,$name,"",$value,$prefix.$key.$suffix."_");
      }
      else {
        (my $reading = $sPrefix.$prefix.$key.$suffix) =~ s/[^A-Za-z\d_\.\-\/]/_/g;

        if ($prefix =~ m/_Head_/ && $SaveDataHead == 0 ){
          Log3 $name, 5, "[$name] [fronius_expandJSON] IGNOR DATA --> $reading VALUE --> $value";
          next;
        }
        
        $reading =~ s/Body_Data_//g;

        if ($reading eq "PowerFlow_Site_P_Load") {
          if ( $value + 0 eq $value) {
            if ($value < 0) {$value = $value * -1}
          }       
        }
        
        # Boolean Werte in Text umwandeln
        if    (ref($value) eq "JSON::PP::Boolean" && $value == 0) {$value="false"}
        elsif (ref($value) eq "JSON::PP::Boolean" && $value == 1) {$value="true"}

        Log3 $name, 5, "[$name] [fronius_expandJSON] WRITE DATA --> $reading VALUE --> $value";
        
        # Sub Devices
        $hash->{helper}{VARS}{Smart_Meter}         = "1" if ($prefix =~ m/DeviceInfo_Body_Data_Meter/ );
        $hash->{helper}{VARS}{Smart_Inverter}      = "1" if ($prefix =~ m/DeviceInfo_Body_Data_Inverter/ );
        $hash->{helper}{VARS}{Smart_Storage}       = "1" if ($prefix =~ m/DeviceInfo_Body_Data_Storage/ );
        $hash->{helper}{VARS}{Smart_OhmPilot}      = "1" if ($prefix =~ m/DeviceInfo_Body_Data_OhmPilot/ );
        $hash->{helper}{VARS}{Smart_StringControl} = "1" if ($prefix =~ m/DeviceInfo_Body_Data_StringControl/ );
        
        # API Base URL
        $hash->{helper}{VARS}{FroniusBaseURL}      = $value if ($reading eq "API_BaseURL");

        if ($prefix =~ m/ArchiveData_/ ) {
          if    ($prefix  =~ m/Current_DC_String_1_Values/ )                {readingsBulkUpdate($hash, "MPPT1_DC_A", encode('UTF-8', $value) );}
          elsif ($prefix  =~ m/Current_DC_String_2_Values/ )                {readingsBulkUpdate($hash, "MPPT2_DC_A", encode('UTF-8', $value) );}
          elsif ($prefix  =~ m/Voltage_DC_String_1_Values/ )                {readingsBulkUpdate($hash, "MPPT1_DC_V", encode('UTF-8', $value) );}
          elsif ($prefix  =~ m/Voltage_DC_String_2_Values/ )                {readingsBulkUpdate($hash, "MPPT2_DC_V", encode('UTF-8', $value) );}
          elsif ($prefix  =~ m/Data_PowerReal_PAC_Sum_Values/ )             {readingsBulkUpdate($hash, "ArchiveData_PowerReal_PAC_Sum"             , encode('UTF-8', $value) );}
          elsif ($prefix  =~ m/Data_EnergyReal_WAC_Sum_Produced_Values/ )   {readingsBulkUpdate($hash, "ArchiveData_EnergyReal_WAC_Sum_Produced"   , encode('UTF-8', $value) );}
          elsif ($prefix  =~ m/Data_EnergyReal_WAC_Plus_Absolute_Values/ )  {readingsBulkUpdate($hash, "ArchiveData_EnergyReal_WAC_Plus_Absolute"  , encode('UTF-8', $value) );}
          elsif ($prefix  =~ m/Data_EnergyReal_WAC_Minus_Absolute_Values/ ) {readingsBulkUpdate($hash, "ArchiveData_EnergyReal_WAC_Minus_Absolute" , encode('UTF-8', $value) );}
          elsif ($reading =~ m/1_Start/ )                                   {readingsBulkUpdate($hash, "ArchiveData_StartDate"                     , encode('UTF-8', $value) );}
          elsif ($reading =~ m/1_End/ )                                     {readingsBulkUpdate($hash, "ArchiveData_EndDate"                       , encode('UTF-8', $value) );}
          #else {Log3 $name, 3, "$prefix $reading $value";}
        }
        else {
          if ($value ne "") {readingsBulkUpdate($hash, $reading, encode('UTF-8', $value) );}
          else {readingsBulkUpdate($hash, $reading, encode('UTF-8', 0) );}          
        }
      }
    }
  }
}

#########################
# Helper
#########################
sub fronius_clearHeadData($) {
  my ($hash)       = @_;
  my $name     = $hash->{NAME};
    my $SaveDataHead = AttrVal( $name, "SaveDataHead", 0 );
  
  Log3 $name, 5, "[$name] [fronius_clearHeadData] START";
  
  if ($SaveDataHead == 0) {
    foreach my $Head (sort keys %{$hash->{READINGS}}) {
      if ($Head =~ m/_Head_/ ) {
        readingsDelete($hash, $Head) ;
        Log3 $name, 5, "[$name] [fronius_clearHeadData] delete reading $Head";
      }
    }
  }

}

sub fronius_setState($$) {
  my ($hash,$State) = @_;
  my $name = $hash->{NAME};
  
  Log3 $name, 3, "[$name] [fronius_setState] to $State"  if(ReadingsVal($name, "state", "nA") ne $State) ;
  
  readingsBeginUpdate($hash);
  readingsBulkUpdateIfChanged($hash, "state", $State, 1);
  readingsEndUpdate($hash,1);
  
  return;
}

1;

=pod
=item device
=item summary Fronius 
=begin html

<a name="fronius"></a>
<h3>fronius</h3>
<ul>
  Module to read data from Fronius inverter devices using <a href="https://www.fronius.com/~/downloads/Solar%20Energy/Operating%20Instructions/42,0410,2012.pdf">Fronius Solar API V1</a>
  <br>
  see also <a href="https://forum.fhem.de/index.php?topic=138356.0">FHEM Forum discussion thread</a>
  <br>
  <br>
  
  <a id="fronius-define"></a>
    <b>Define</b>
    <ul>
      <code>define &lt;name&gt; fronius &lt;IP-adress of device&gt;</code>
    </ul>
    <br>

  <a id="fronius-set"></a>
    <b>Set</b>
    <ul>
     <li>if (and only if) IntervalRealtimeData <= 0 requests can be sent manually:
      <ul>
       <li>Set devicename GetAllData </li>
       <li>Set devicename GetAllData Meter Inverter Storage PowerFlow</li>
       <li>Set devicename GetPowerFlowData </li>
       <li>Set devicename GetStorageData </li>
       <li>Set devicename GetMeterData </li>
       <li>Set devicename GetInverterData </li>
       <li>Set devicename GetActiveDeviceInfo </li>
      </ul>
     </li>
     <li>Restart timers, needed after changed to Interval* attributes:
       <br>
       <ul><li>set devicename RestartInterval</li></ul>          
     </li>
    </ul>
    <br>

  <a id="fronius-attr"></a>
    <b>Attributes</b>
    <ul>      
      <li><a id="fronius-IntervalRealtimeData">IntervalRealtimeData</a><br>
      Interval in seconds for requesting data from inverter, default 60s, 0 to disable requests.
      </li>
  
      <li><a id="fronius-IntervalArchiveData">IntervalArchiveData</a><br>
      Interval in seconds for requesting GetArchiveData data from inverter, default MAX(300,IntervalRealtimeData), minimum allowed value 120s (Fronius Solar API V1 Doku - "Archive requests are not allowed to be performed in parallel and need to keep a timeout of 120 seconds between two consecutive calls.")
      <br>
      if set to 300, GetArchiveData calls are aligned on 5min intervals
      <br>
      0 to disable requests.
      </li>

      <li><a id="fronius-IntervalPowerFlowRealtimeData">IntervalPowerFlowRealtimeData</a><br>
      Interval in seconds for requesting GetPowerFlowRealtimeData data from inverter, default IntervalRealtimeData, 0 to disable requests.
     </li>

      <li><a id="fronius-IntervalStorageRealtimeData">IntervalStorageRealtimeData</a><br>
      Interval in seconds for requesting GetStorageRealtimeData data from inverter, default IntervalRealtimeData, 0 to disable requests.
      </li>

      <li><a id="fronius-IntervalMeterRealtimeData">IntervalMeterRealtimeData</a><br>
      Interval in seconds for requesting GetMeterRealtimeData data from inverter, default IntervalRealtimeData, 0 to disable requests.
      </li>

      <li><a id="fronius-IntervalInverterRealtimeData">IntervalInverterRealtimeData</a><br>
      Interval in seconds for requesting GetInverterRealtimeData data from inverter, default IntervalRealtimeData, 0 to disable requests.
      </li>

    </ul>
    <br>

</ul>

=end html

=cut
