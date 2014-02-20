###############################################################
#
#  23_LUXTRONIK2.pm
#
#  Copyright notice
#
#  (c) 2012,2014 Torsten Poitzsch (torsten poitzsch at gmx . de)
#  (c) 2012-2013 Jan-Hinrich Fessel (oskar@fessel.org)
#
#  The modul reads and writes parameters of the heat pump controller 
#  Luxtronik 2.0 used in Alpha Innotec and Siemens Novelan (WPR NET) heat pumps.
#
#  This script is free software; you can redistribute it and/or modify
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
#  This copyright notice MUST APPEAR in all copies of the script!
#
################################################################

##############################################
package main;

use strict;
use warnings;
use Blocking;
use IO::Socket; 
use Time::HiRes qw/ time /;
use Net::Telnet;

# Modul Version for remote debugging
  my $modulVersion = "2014-02-20";

#List of firmware versions that are known to be compatible with this modul
  my $testedFirmware = "#V1.54C#V1.60#V1.69#";
  my $compatibleFirmware = "#V1.54C#V1.60#V1.69#";

sub ########################################
LUXTRONIK2_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "LUXTRONIK2_Define";
  $hash->{UndefFn}  = "LUXTRONIK2_Undefine";
  $hash->{NotifyFn} = "LUXTRONIK2_Notify";
  $hash->{SetFn}    = "LUXTRONIK2_Set";
  $hash->{AttrFn}   = "LUXTRONIK2_Attr";
  $hash->{AttrList} = "disable:0,1 ".
                 "allowSetParameter:0,1 ".
                 "autoSynchClock:slider,10,5,300 ".
                 "doStatistics:0,1 ".
                 "ignoreFirmwareCheck:0,1 ".
                 "statusHTML ".
                 $readingFnAttributes;
}

sub ########################################
LUXTRONIK2_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "Usage: define <name> LUXTRONIK2 <ip-address> [poll-interval]" 
         if(@a <3 || @a >4);

  my $name = $a[0];
  my $host = $a[2];

  my $interval = 5*60;
  $interval = $a[3] if(int(@a) == 4);
  $interval = 30 if( $interval < 30 );

  $hash->{NAME} = $name;

  $hash->{STATE} = "Initializing";
  $hash->{HOST} = $host;
  $hash->{INTERVAL} = $interval;
  $hash->{NOTIFYDEV} = "global";

  RemoveInternalTimer($hash);
  #Get first data after 10 seconds
  InternalTimer(gettimeofday() + 10, "LUXTRONIK2_GetUpdate", $hash, 0);

  #Reset temporary values
  $hash->{fhem}{durationFetchReadingsMin} = 0;
  $hash->{fhem}{durationFetchReadingsMax} = 0;
  $hash->{fhem}{alertFirmware} = 0;
  $hash->{fhem}{statBoilerHeatUpStep} = 0;
  $hash->{fhem}{statBoilerCoolDownStep} = 0;
 
  $hash->{fhem}{modulVersion} = $modulVersion;
  Log3 $hash,5,"$name: LUXTRONIK2.pm version is $modulVersion.";
       
  return undef;
}

sub ########################################
LUXTRONIK2_Undefine($$)
{
  my ($hash, $arg) = @_;

  RemoveInternalTimer($hash);

  BlockingKill($hash->{helper}{RUNNING_PID}) if(defined($hash->{helper}{RUNNING_PID}));

  return undef;
}

sub ########################################
LUXTRONIK2_Notify(@) {
  my ($hash,$dev) = @_;
  my $name = $hash->{NAME};
  
  if ($dev->{NAME} eq "global" && grep (m/^INITIALIZED|REREADCFG$/,@{$dev->{CHANGED}})){
    # housekeeping
      my %cleanUp = ( 
            delayDeviceTime => "delayDeviceTimeCalc",
            deviceTimeStartReadings => "deviceTimeCalc",
            heatingSummerMode => "heatingLimit",
            thresholdTemperatureSummerMode => "thresholdHeatingLimit",
            lastDeviceClockSynch => "deviceTimeLastSync",
            operatingHoursHeatPump => "counterHoursHeatPump",
            operatingHoursSecondHeatSource1 => "counterHours2ndHeatSource1",
            operatingHoursSecondHeatSource2 => "counterHours2ndHeatSource2",
            operatingHoursSecondHeatSource3 => "counterHours2ndHeatSource3",
            operatingHoursHeating => "counterHoursHeating",
            operatingHoursHotWater => "counterHoursHotWater",
            heatQuantityHeating => "counterHeatQHeating",
            heatQuantityHotWater => "counterHeatQHotWater",
            heatQuantityTotal => "counterHeatQTotal", 
            currentOperatingStatus1 => "opStateHeatPump1",
            currentOperatingState1 => "opStateHeatPump1",
            currentOperatingStatus2 => "opStateHeatPump3",
            currentOperatingState2 => "opStateHeatPump2",
            currentOperatingState3 => "opStateHeatPump3",
            heatingOperatingMode => "opModeHeating",
            heatingOperatingState => "opStateHeating",
            hotWaterOperatingMode => "opModeHotWater",
            hotWaterStatus => "opStateHotWater",
            hotWaterState => "opStateHotWater",
            heatingSystemCirculationPump => "heatingSystemCircPump",
            hotWaterCirculationPumpExtern => "hotWaterCircPumpExtern",
            statGradientBoilerTempLoss => "statBoilerGradientHeatUp' and 'statBoilerGradientCoolDown" ); 
      my $oldReading;
      my $newReading;
      while (($oldReading, $newReading) = each(%cleanUp)) {
         if ( exists( $hash->{READINGS}{$oldReading} ) ) {
            delete($hash->{READINGS}{$oldReading});
            Log3 $name,2,"$name: !!! Change/fix in LUXTRONIK2-Modul: '$oldReading' is now '$newReading'";
         }
      }
   }
   return;
}


sub ########################################
LUXTRONIK2_Attr(@)
{
   my ($cmd,$name,$aName,$aVal) = @_;
     # $cmd can be "del" or "set"
   # $name is device name
   # aName and aVal are Attribute name and value
   if ($cmd eq "set") {
      if ($aName eq "1allowSetParameter") {
         eval { qr/$aVal/ };
         if ($@) {
            Log3 $name, 3, "LUXTRONIK2: Invalid allowSetParameter in attr $name $aName $aVal: $@";
            return "Invalid allowSetParameter $aVal";
         }
      }
   }
   
   return undef;
}


sub ########################################
LUXTRONIK2_Set($$@)
{
  my ($hash, $name, $cmd, $val) = @_;
  my $resultStr = "";
  
  if($cmd eq 'statusRequest') {
    $hash->{LOCAL} = 1;
    LUXTRONIK2_GetUpdate($hash);
    $hash->{LOCAL} = 0;
    return undef;
  }
  elsif ($cmd eq 'resetStatistics') {
   if ( ($val eq "all" || $val eq "statBoilerGradientCoolDownMin") 
         && exists($defs{$name}{READINGS}{statBoilerGradientCoolDownMin})) {
      delete $defs{$name}{READINGS}{statBoilerGradientCoolDownMin};
      $resultStr .= " statBoilerGradientCoolDownMin";
   }
   if ( $resultStr eq "" ) {
      $resultStr = "$name: No statistics to reset";
   } else {
      $resultStr = "$name: Statistic value(s) deleted:" . $resultStr;
   }
   Log3 $hash, 3, $resultStr;
   return $resultStr;
  }
  elsif($cmd eq 'INTERVAL' && int(@_)==4 ) {
   $val = 30 if( $val < 30 );
   $hash->{INTERVAL}=$val;
   return "Polling interval set to $val seconds.";
  }

  #Check Firmware and Set-Paramter-lock 
  if ($cmd eq 'synchronizeClockHeatPump' ||
         $cmd eq 'hotWaterTemperatureTarget' ||
         $cmd eq 'opModeHotWater') 
   {
    my $firmware = ReadingsVal($name,"firmware","");
    my $firmwareCheck = LUXTRONIK2_checkFirmware($firmware);
     # stop in case of incompatible firmware
    if ($firmwareCheck eq "fwNotCompatible") {
      Log3 $name, 3, $name." Error: Host firmware '$firmware' not compatible for parameter setting.";
       return "Firmware '$firmware' not compatible for parameter setting. ";
     # stop in case of untested firmware and firmware check enabled
    } elsif (AttrVal($name, "ignoreFirmwareCheck", 0)!= 1 &&
            $firmwareCheck eq "fwNotTested") {
      Log3 $name, 3, $name." Error: Host firmware '$firmware' not tested for parameter setting. To test set attribute 'ignoreFirmwareCheck' to 1";
       return "Firmware '$firmware' not compatible for parameter setting. To test set attribute 'ignoreFirmwareCheck' to 1.";
     # stop in case setting of parameters is not enabled
    } elsif ( AttrVal($name, "allowSetParameter", 0) != 1) {
      Log3 $name, 3, $name." Error: Setting of parameters not allowed. Please set attribut 'allowSetParameter' to 1";
       return "Setting of parameters not allowed. To unlock, please set attribut 'allowSetParameter' to 1.";
     }
   }
  
   if ($cmd eq 'synchronizeClockHeatPump') {
      $hash->{LOCAL} = 1;
      $resultStr = LUXTRONIK2_synchronizeClock($hash);
      $hash->{LOCAL} = 0;
      Log3 $name, 3, "$name - $resultStr";
      return $resultStr;
   } elsif(int(@_)==4 &&
         ($cmd eq 'hotWaterTemperatureTarget'
            || $cmd eq 'opModeHotWater')) {
      $hash->{LOCAL} = 1;
      $resultStr = LUXTRONIK2_SetParameter ($hash, $cmd, $val);
      $hash->{LOCAL} = 0;
      return $resultStr;
   }

  my $list = "statusRequest:noArg".
          " resetStatistics:all,statBoilerGradientCoolDownMin".
          " hotWaterTemperatureTarget:slider,30.0,0.5,65.0".
          " opModeHotWater:Auto,Party,Off".
          " synchronizeClockHeatPump:noArg".
          " INTERVAL:slider,30,30,1800";
  return "Unknown argument $cmd, choose one of $list";
}


sub ########################################
LUXTRONIK2_GetUpdate($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if(!$hash->{LOCAL}) {
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "LUXTRONIK2_GetUpdate", $hash, 1);
  }

  my $host = $hash->{HOST};

  if( !$hash->{LOCAL} ) {
    return undef if( AttrVal($name, "disable", 0 ) == 1 );
  }

  $hash->{helper}{RUNNING_PID} = BlockingCall("LUXTRONIK2_DoUpdate", $name."|".$host, "LUXTRONIK2_UpdateDone", 25, "LUXTRONIK2_UpdateAborted", $hash) unless(exists($hash->{helper}{RUNNING_PID}));
}


sub ########################################
LUXTRONIK2_DoUpdate($)
{
  my ($string) = @_;
  my ($name, $host) = split("\\|", $string);

  my @heatpump_values;
  my @heatpump_parameters;
  my @heatpump_visibility;
  my $count=0;
  my $result="";
  my $readingStartTime = time();
  
  Log3 $name, 5, "$name: Opening connection to host ".$host;
  my $socket = new IO::Socket::INET (  
                  PeerAddr => $host, 
                   PeerPort => 8888,
                   #   Type = SOCK_STREAM, # probably needed on some systems
                   Proto => 'tcp'
      );
  if (!$socket) {
      Log3 $name, 1, "$name Error: Could not open connection to host ".$host;
      return "$name|0|Can't connect to $host";
  }
  $socket->autoflush(1);
  
############################ 
#Fetch operational values (FOV)
############################ 
  Log3 $name, 5, "$name: Ask host for operational values";
  $socket->send(pack("N", 3004));
  $socket->send(pack("N", 0));
  
  Log3 $name, 5, "$name: Start to receive operational values";
 #(FOV) read first 4 bytes of response -> should be request_echo = 3004
  $socket->recv($result,4);
  $count = unpack("N", $result);
  if($count != 3004) {
      Log3 $name, 2, "$name LUXTRONIK2_DoUpdate-Error: Fetching operational values - wrong echo of request 3004: ".length($result)." -> ".$count;
       $socket->close();
      return "$name|0|3004 != $count";
  }
 
 #(FOV) read next 4 bytes of response -> should be status = 0
  $socket->recv($result,4);
  $count = unpack("N", $result);
  if($count > 0) {
      Log3 $name, 4, "$name: Parameter on target changed, restart parameter reading after 5 seconds";
     $socket->close();
      return "$name|2|Status = $count - parameter on target changed, restart device reading after 5 seconds";
  }
  
 #(FOV) read next 4 bytes of response -> should be count_calc_values > 0
  $socket->recv($result,4);
  my $count_calc_values = unpack("N", $result);
  if($count_calc_values == 0) {
      Log3 $name, 2, "$name LUXTRONIK2_DoUpdate-Error:  Fetching operational values - 0 values announced: ".length($result)." -> ".$count_calc_values;
     $socket->close();
      return "$name|0|0 values read";
  }
  
 #(FOV) read remaining response -> should be previous number of parameters
  my $i=1;
  $result="";
  my $buf="";
  while($i<=$count_calc_values) {
     $socket->recv($buf,4);
      $result.=$buf;
     $i++;
  }
  if(length($result) != $count_calc_values*4) {
      Log3 $name, 1, "$name LUXTRONIK2_DoUpdate-Error: operational values length check: ".length($result)." should have been ". $count_calc_values * 4;
      $socket->close();
      return "$name|0|Number of values read mismatch ( $!)\n";
  }
  
 #(FOV) unpack response in array
  @heatpump_values = unpack("N$count_calc_values", $result);
  if(scalar(@heatpump_values) != $count_calc_values) {
      Log3 $name, 2, "$name LUXTRONIK2_DoUpdate-Error: unpacking problem by operation values: ".scalar(@heatpump_values)." instead of ".$count_calc_values;
      $socket->close();
      return "$name|0|Unpacking problem of operational values";
  
  }

  Log3 $name, 5, "$name: $count_calc_values operational values received";
 
############################ 
#Fetch set parameters (FSP)
############################ 
  Log3 $name, 5, "$name: Ask host for set parameters";
  $socket->send(pack("N", 3003));
  $socket->send(pack("N", 0));

  Log3 $name, 5, "$name: Start to receive set parameters";
 #(FSP) read first 4 bytes of response -> should be request_echo=3003
  $socket->recv($result,4);
  $count = unpack("N", $result);
  if($count != 3003) {
      Log3 $name, 2, "$name LUXTRONIK2_DoUpdate-Error: wrong echo of request 3003: ".length($result)." -> ".$count;
      $socket->close();
      return "$name|0|3003 != 3003";
  }
  
 #(FSP) read next 4 bytes of response -> should be number_of_parameters > 0
  $socket->recv($result,4);
  my $count_set_parameter = unpack("N", $result);
  if($count_set_parameter == 0) {
      Log3 $name, 2, "$name LUXTRONIK2_DoUpdate-Error: 0 parameter read: ".length($result)." -> ".$count_set_parameter;
     $socket->close();
      return "$name|0|0 parameter read";
  }
  
 #(FSP) read remaining response -> should be previous number of parameters
  $i=1;
  $result="";
  $buf="";
  while($i<=$count_set_parameter) {
     $socket->recv($buf,4);
      $result.=$buf;
     $i++;
  }
  if(length($result) != $count_set_parameter*4) {
      Log3 $name, 1, "$name LUXTRONIK2_DoUpdate-Error: parameter length check: ".length($result)." should have been ". $count_set_parameter * 4;
     $socket->close();
      return "$name|0|Number of parameters read mismatch ( $!)\n";
  }

  @heatpump_parameters = unpack("N$count_set_parameter", $result);
  if(scalar(@heatpump_parameters) != $count_set_parameter) {
      Log3 $name, 2, "$name LUXTRONIK2_DoUpdate-Error: unpacking problem by set parameter: ".scalar(@heatpump_parameters)." instead of ".$count_set_parameter;
     $socket->close();
      return "$name|0|Unpacking problem of set parameters";
  }

  Log3 $name, 5, "$name: $count_set_parameter set values received";

############################ 
#Fetch Visibility Attributes (FVA)
############################ 
  Log3 $name, 5, "$name: Ask host for visibility attributes";
  $socket->send(pack("N", 3005));
  $socket->send(pack("N", 0));

  Log3 $name, 5, "$name: Start to receive visibility attributes";
 #(FVA) read first 4 bytes of response -> should be request_echo=3005
  $socket->recv($result,4);
  $count = unpack("N", $result);
  if($count != 3005) {
      Log3 $name, 2, "$name LUXTRONIK2_DoUpdate-Error: wrong echo of request 3005: ".length($result)." -> ".$count;
      $socket->close();
      return "$name|0|3005 != $count";
  }
  
 #(FVA) read next 4 bytes of response -> should be number_of_Visibility_Attributes > 0
  $socket->recv($result,4);
  $count = unpack("N", $result);
  if($count == 0) {
      Log3 $name, 2, "$name LUXTRONIK2_DoUpdate-Error: 0 visibility attributes announced: ".length($result)." -> ".$count;
     $socket->close();
      return "$name|0|0 visibility attributes announced";
  }
  
 #(FVA) read remaining response bytewise -> should be previous number of parameters
  $i=1;
  $result="";
  $buf="";
  while($i<=$count) {
     $socket->recv($buf,1);
      $result.=$buf;
     $i++;
  }
  if(length($result) != $count) {
      Log3 $name, 1, "$name LUXTRONIK2_DoUpdate-Error: Visibility attributes length check: ".length($result)." should have been ". $count;
     $socket->close();
      return "$name|0|Number of Visibility attributes read mismatch ( $!)\n";
  }

  @heatpump_visibility = unpack("C$count", $result);
  if(scalar(@heatpump_visibility) != $count) {
      Log3 $name, 2, "$name LUXTRONIK2_DoUpdate-Error: Unpacking problem by visibility attributes: ".scalar(@heatpump_visibility)." instead of ".$count;
     $socket->close();
      return "$name|0|Unpacking problem of visibility attributes";
  }

  Log3 $name, 5, "$name: $count visibility attributs received";

####################################  

  Log3 $name, 5, "$name: Closing connection to host $host";
  $socket->close();

  my $readingEndTime = time();

#return certain readings for further processing
  # 0 - name
  my $return_str="$name";
  # 1 - no error = 1
  $return_str .= "|1";
  # 2 - opStateHeatPump1
  $return_str .= "|".$heatpump_values[117];
  # 3 - opStateHeatPump3
  $return_str .= "|".$heatpump_values[119];
  # 4 - Stufe - ID_WEB_HauptMenuAHP_Stufe
  $return_str .= "|".$heatpump_values[121];
  # 5 - Temperature Value - ID_WEB_HauptMenuAHP_Temp
  $return_str .= "|".$heatpump_values[122];
  # 6 - Compressor1 
  $return_str .= "|".$heatpump_values[44];
  # 7 - opModeHotWater
  $return_str .= "|".$heatpump_parameters[4];
  # 8 - hotWaterMonitoring
  $return_str .= "|".$heatpump_values[124];
  # 9 - hotWaterBoilerValve
  $return_str .= "|".$heatpump_values[38];
  # 10 - opModeHeating
  $return_str .= "|".$heatpump_parameters[3];
  # 11 - heatingLimit
  $return_str .= "|".$heatpump_parameters[699];
  # 12 - ambientTemperature
  $return_str .= "|".$heatpump_values[15];
  # 13 - averageAmbientTemperature
  $return_str .= "|".$heatpump_values[16];
  # 14 - hotWaterTemperature
  $return_str .= "|".$heatpump_values[17];
  # 15 - flowTemperature
  $return_str .= "|".$heatpump_values[10];
  # 16 - returnTemperature
  $return_str .= "|".$heatpump_values[11];
  # 17 - returnTemperatureTarget
  $return_str .= "|".$heatpump_values[12];
  # 18 - returnTemperatureExtern
  $return_str .= "|".($heatpump_visibility[24]==1 ? $heatpump_values[13] : "no");
  # 19 - flowRate
  $return_str .= "|".$heatpump_values[155];
  # 20 - firmware
  my $fwvalue = "";
  for(my $fi=81; $fi<91; $fi++) {
      $fwvalue .= chr($heatpump_values[$fi]) if $heatpump_values[$fi];
  }
  $return_str .= "|".$fwvalue;
  # 21 - thresholdHeatingLimit
  $return_str .= "|".$heatpump_parameters[700];
  # 22 - rawDeviceTimeCalc
  $return_str .= "|".$heatpump_values[134];
  # 23 - heatSourceIN
  $return_str .= "|".$heatpump_values[19];
  # 24 - heatSourceOUT
  $return_str .= "|".$heatpump_values[20];
  # 25 - hotWaterTemperatureTarget
  $return_str .= "|".$heatpump_values[18];
  # 26 - hotGasTemperature
  $return_str .= "|".$heatpump_values[14];
  # 27 - heatingSystemCircPump
  $return_str .= "|".$heatpump_values[39];
  # 28 - hotWaterCircPumpExtern
  $return_str .= "|".$heatpump_values[46];
  # 29 - readingFhemStartTime
  $return_str .= "|".$readingStartTime;
  # 30 - readingFhemEndTime
  $return_str .= "|".$readingEndTime;
  # 31 - typeHeatpump
  $return_str .= "|".$heatpump_values[78];
  # 32 - counterHours2ndHeatSource1
  $return_str .= "|". ($heatpump_visibility[84]==1 ? $heatpump_values[60] : "no");
  # 33 - counterHoursHeatpump
  $return_str .= "|". ($heatpump_visibility[87]==1 ? $heatpump_values[63] : "no");
  # 34 - counterHoursHeating
  $return_str .= "|". ($heatpump_visibility[195]==1 ? $heatpump_values[64] : "no");
  # 35 - counterHoursHotWater
  $return_str .= "|". ($heatpump_visibility[196]==1 ? $heatpump_values[65] : "no");
  # 36 - counterHeatQHeating
  $return_str .= "|" . $heatpump_values[151];
  # 37 - counterHeatQHeating
  $return_str .= "|". $heatpump_values[152];
  # 38 - counterHours2ndHeatSource2
  $return_str .= "|". ($heatpump_visibility[85]==1 ? $heatpump_values[61] : "no");
  # 39 - counterHours2ndHeatSource3
  $return_str .= "|". ($heatpump_visibility[86]==1 ? $heatpump_values[62] : "no");
  # 40 - opStateHeatPump2 
  $return_str .= "|".$heatpump_values[118];
  # 41 - opStateHeatPump2Duration
  $return_str .= "|".$heatpump_values[120];
  # 42 - timeError0
  $return_str .= "|".$heatpump_values[95];
  # 43 - bivalentLevel
  $return_str .= "|".$heatpump_values[79];
  # 44 - Number of calculated values
  $return_str .= "|".$count_calc_values;
  # 45 - Number of set parameters
  $return_str .= "|".$count_set_parameter;
  # 46 - opStateHeating
  $return_str .= "|".$heatpump_values[125];
  # 47 - deltaHeatingReduction
  $return_str .= "|".$heatpump_parameters[13];
  # 48 - thresholdTemperatureSetBack
  $return_str .= "|".$heatpump_parameters[111];
  # 49 - hotWaterTemperatureHysterese
  $return_str .= "|".$heatpump_parameters[74];
  # 50 - solarCollectorTemperature
  $return_str .= "|". ($heatpump_visibility[36]==1 ? $heatpump_values[26] : "no");
  # 51 - solarBufferTemperature
  $return_str .= "|". ($heatpump_visibility[37]==1 ? $heatpump_values[27] : "no");
  # 52 - counterHoursSolar
  $return_str .= "|". ($heatpump_visibility[248]==1 ? $heatpump_values[161] : "no");
  
  return $return_str;
}


sub ########################################
LUXTRONIK2_UpdateDone($)
{
  my ($string) = @_;
  my $value = "";
  my $state = "";
  
  return unless(defined($string));

  my @a = split("\\|",$string);
  my $hash = $defs{$a[0]};
  my $name = $a[0];
  
  delete($hash->{helper}{RUNNING_PID});

  return if($hash->{helper}{DISABLED});

  Log3 $hash, 5, "$name: LUXTRONIK2_UpdateDone: $string";

  #Define Status Messages
  my %wpOpStat1 = ( 0 => "Waermepumpe laeuft",
            1 => "Waermepumpe steht",
            2 => "Waermepumpe kommt",
            4 => "Fehler",
            5 => "Abtauen",
            6 => "Warte auf LIN-Verbindung",
            7 => "Verdichter heizt auf");
  my %wpOpStat2 = ( 0 => "Heizbetrieb",
            1 => "Keine Anforderung",
            2 => "Netz Einschaltverzoegerung",
            3 => "Schaltspielzeit",
            4 => "EVU Sperrzeit",
            5 => "Brauchwasser",
            6 => "Stufe",
            7 => "Abtauen",
            8 => "Pumpenvorlauf",
            9 => "Thermische Desinfektion",
            10 => "Kuehlbetrieb",
            12 => "Schwimmbad/Photovoltaik",
            13 => "Heizen_Ext_En",
            14 => "Brauchw_Ext_En",
            16 => "Durchflussueberwachung",
            17 => "Elektrische Zusatzheizung" );
  my %wpMode = ( 0 => "Automatik",
             1 => "Zusatzheizung",
             2 => "Party",
             3 => "Ferien",
             4 => "Aus" );
   my %heatingState = ( 0 => "Abgesenkt",
                1 => "Normal",
                3 => "Aus");
  my %wpType = ( 0 => "ERC", 1 => "SW1", 
             2 => "SW2", 3 => "WW1", 
             4 => "WW2", 5 => "L1I", 
             6 => "L2I", 7 => "L1A", 
             8 => "L2A", 9 => "KSW",
            10 => "KLW", 11 => "SWC", 
            12 => "LWC", 13 => "L2G",
            14 => "WZS", 15 => "L1I407",
            16 => "L2I407", 17 => "L1A407",
            18 => "L2A407", 19 => "L2G407",
            20 => "LWC407", 21 => "L1AREV",
            22 => "L2AREV", 23 => "WWC1",
            24 => "WWC2", 25 => "L2G404",
            26 => "WZW", 27 => "L1S",
            28 => "L1H", 29 => "L2H",
            30 => "WZWD", 31 => "ERC",
            40 => "WWB_20", 41 => "LD5",
            42 => "LD7", 43 => "SW 37_45",
            44 => "SW 58_69", 45 => "SW 29_56",
            46 => "LD5 (230V)", 47 => "LD7 (230 V)",
            48 => "LD9", 49 => "LD5 REV",
            50 => "LD7 REV", 51 => "LD5 REV 230V",
            52 => "LD7 REV 230V", 53 => "LD9 REV 230V",
            54 => "SW 291", 55 => "LW SEC" );
             
  my $counterRetry = $hash->{fhem}{counterRetry};
  $counterRetry++;    

  if ($a[1]==0 ) {
     readingsSingleUpdate($hash,"state","Error: ".$a[2],1);
    $counterRetry = 0;
  }
  elsif ($a[1]==2 )  {
     if ($counterRetry <=3) {
      InternalTimer(gettimeofday() + 5, "LUXTRONIK2_GetUpdate", $hash, 0);
     }
    else {
       readingsSingleUpdate($hash,"state","Error: Reading skipped after $counterRetry tries",1);
      Log3 $hash, 2, "$name Error: Device reading skipped after $counterRetry tries with parameter change on target";
    }
  }
  elsif ($a[1]==1 )  {
    $counterRetry = 0;  

   readingsBeginUpdate($hash);

    # Temporary storage of values because needed several times
   my $ambientTemperature = LUXTRONIK2_CalcTemp($a[12]);
   my $averageAmbientTemperature = LUXTRONIK2_CalcTemp($a[13]);
   my $hotWaterTemperature = LUXTRONIK2_CalcTemp($a[14]);
   my $hotWaterTemperatureTarget = LUXTRONIK2_CalcTemp($a[25]);
   my $hotWaterTemperatureThreshold = LUXTRONIK2_CalcTemp($a[25] - $a[49]);
    my $thresholdHeatingLimit = LUXTRONIK2_CalcTemp($a[21]);
   my $thresholdTemperatureSetBack = LUXTRONIK2_CalcTemp($a[48]);
   my $flowTemperature = LUXTRONIK2_CalcTemp($a[15]);
   my $returnTemperature = LUXTRONIK2_CalcTemp($a[16]);
   
   # if selected, do all the statistic calculations
   if ( AttrVal($name,"doStatistics",0) == 1) { 
      #LUXTRONIK2_doStatisticBoilerHeatUp $hash, $currOpHours, $currHQ, $currTemp, $opState, $target
      $value = LUXTRONIK2_doStatisticBoilerHeatUp ($hash, $a[35], $a[37]/10, $hotWaterTemperature, $a[3],$hotWaterTemperatureTarget);
      if ($value ne "") {
         readingsBulkUpdate($hash,"statBoilerGradientHeatUp",$value); 
         Log3 $name,3,"$name: statBoilerGradientHeatUp set to $value";
      }
      #LUXTRONIK2_doStatisticBoilerCoolDown $hash, $time, $currTemp, $opState, $target, $threshold
      $value = LUXTRONIK2_doStatisticBoilerCoolDown ($hash, $a[22], $hotWaterTemperature, $a[3], $hotWaterTemperatureTarget, $hotWaterTemperatureThreshold);
      if ($value ne "") {
         readingsBulkUpdate($hash,"statBoilerGradientCoolDown",$value); 
         Log3 $name,3,"$name: statBoilerGradientCoolDown set to $value";
         if ( exists( $hash->{READINGS}{statBoilerGradientCoolDownMin} ) ) {
            my @new = split / /, $value;
            my @old = split / /, $hash->{READINGS}{statBoilerGradientCoolDownMin};
            if ($new[5]>6 && $new[1]>$old[1] && $new[1] < 0) {
               readingsBulkUpdate($hash,"statBoilerGradientCoolDownMin",$value); 
               Log3 $name,3,"$name: statBoilerGradientCoolDownMin set to $value";
            }
         } else {
            readingsBulkUpdate($hash,"statBoilerGradientCoolDownMin",$value); 
            Log3 $name,3,"$name: statBoilerGradientCoolDownMin set to $value";
         }
      }
   }

  #Operating status of heat pump
     my $opStateHeatPump1 = $wpOpStat1{$a[2]}; ##############
      $opStateHeatPump1 = "unbekannt (".$a[2].")" unless $opStateHeatPump1;
     readingsBulkUpdate($hash,"opStateHeatPump1",$opStateHeatPump1);
     
     my $opStateHeatPump2 = "unknown ($a[40])"; ##############
     my $prefix = "";
     if ($a[40] == 0 || $a[40] == 2) { $prefix = "seit ";}
     elsif ($a[40] == 1) { $prefix = "in ";}
     if ($a[40] == 2) { #Sonderbehandlung bei WP-Fehlern
       $opStateHeatPump2 = $prefix . strftime "%d.%m.%Y %H:%M:%S", localtime($a[42]);
     } else {
       $opStateHeatPump2 = $prefix . LUXTRONIK2_FormatDuration($a[41]);
     }
     readingsBulkUpdate($hash,"opStateHeatPump2",$opStateHeatPump2);
     
     my $opStateHeatPump3 = $wpOpStat2{$a[3]}; ##############
     # refine text of third state
     if ($a[3]==6) { 
        $opStateHeatPump3 = "Stufe ".$a[4]." ".LUXTRONIK2_CalcTemp($a[5])." C "; 
     }
      elsif ($a[3]==7) { 
         if ($a[6]==1) {$opStateHeatPump3 = "Abtauen (Kreisumkehr)";}
         else {$opStateHeatPump3 = "Luftabtauen";}
      }
      $opStateHeatPump3 = "unbekannt (".$a[3].")" unless $opStateHeatPump3;
     readingsBulkUpdate($hash,"opStateHeatPump3",$opStateHeatPump3);
   
   # Hot water operating mode 
     $value = $wpMode{$a[7]};
     $value = "unbekannt (".$a[7].")" unless $value;
     readingsBulkUpdate($hash,"opModeHotWater",$value);
   # opStateHotWater
     if ($a[8]==0) {$value="Sperrzeit";}
      elsif ($a[8]==1 && $a[9]==1) {$value="Aufheizen";}
      elsif ($a[8]==1 && $a[9]==0) {$value="Temp. OK";}
     elsif ($a[8]==3) {$value="Aus";}
      else {$value = "unbekannt (".$a[8]."/".$a[9].")";}
     readingsBulkUpdate($hash,"opStateHotWater",$value);

    # Heating operating mode
     $value = $wpMode{$a[10]};
     $value = "unbekannt (".$a[10].")" unless $value;
     readingsBulkUpdate($hash,"opModeHeating",$value);
   # Heating operating state
     # Consider also heating limit
     if ($a[10] == 0 
           && $a[11] == 1
          && $averageAmbientTemperature >= $thresholdHeatingLimit) {
      $value = "Heizungsgrenze (Aus)";
     } else {
       $value = $heatingState{$a[46]};
      $value = "unbekannt (".$a[46].")" unless $value;
     # Consider heating reduction limit
      if ($a[46] == 0) {
        if ($thresholdTemperatureSetBack <= $ambientTemperature) { 
          $value .= " ".LUXTRONIK2_CalcTemp($a[47])." C"; 
        } else {
          $value = "Normal da < $thresholdTemperatureSetBack C"; 
        }
      }
     }
     readingsBulkUpdate($hash,"opStateHeating",$value);
      
   # Device and reading times, delays and durations
     $value = strftime "%Y-%m-%d %H:%M:%S", localtime($a[22]);
     readingsBulkUpdate($hash, "deviceTimeCalc", $value);
     my $delayDeviceTimeCalc=sprintf("%.0f",$a[29]-$a[22]);
     readingsBulkUpdate($hash, "delayDeviceTimeCalc", $delayDeviceTimeCalc);
     my $durationFetchReadings = sprintf("%.2f",$a[30]-$a[29]);
     readingsBulkUpdate($hash, "durationFetchReadings", $durationFetchReadings);
     #Remember min and max reading durations, will be reset when initializing the device
     if ($hash->{fhem}{durationFetchReadingsMin} == 0 || $hash->{fhem}{durationFetchReadingsMin} > $durationFetchReadings) {
      $hash->{fhem}{durationFetchReadingsMin} = $durationFetchReadings;
      } 
     if ($hash->{fhem}{durationFetchReadingsMax} < $durationFetchReadings) {
      $hash->{fhem}{durationFetchReadingsMax} = $durationFetchReadings;
      }
   
   # Temperatures and flow rate
     readingsBulkUpdate( $hash, "ambientTemperature", $ambientTemperature);
     readingsBulkUpdate( $hash, "averageAmbientTemperature", $averageAmbientTemperature);
     readingsBulkUpdate( $hash, "heatingLimit",$a[11]?"on":"off");
     readingsBulkUpdate( $hash, "thresholdHeatingLimit", $thresholdHeatingLimit);
     readingsBulkUpdate( $hash, "thresholdTemperatureSetBack", $thresholdTemperatureSetBack); 
     readingsBulkUpdate( $hash, "hotWaterTemperature", $hotWaterTemperature);
     readingsBulkUpdate( $hash, "hotWaterTemperatureTarget",$hotWaterTemperatureTarget);
     readingsBulkUpdate( $hash, "flowTemperature", $flowTemperature);
     readingsBulkUpdate( $hash, "returnTemperature", $returnTemperature);
     readingsBulkUpdate( $hash, "returnTemperatureTarget",LUXTRONIK2_CalcTemp($a[17]));
     if ($a[18] !~ /no/) {readingsBulkUpdate( $hash, "returnTemperatureExtern",LUXTRONIK2_CalcTemp($a[18]))};
     readingsBulkUpdate( $hash, "flowRate",$a[19]);
     readingsBulkUpdate( $hash, "heatSourceIN",LUXTRONIK2_CalcTemp($a[23]));
     readingsBulkUpdate( $hash, "heatSourceOUT",LUXTRONIK2_CalcTemp($a[24]));
     readingsBulkUpdate( $hash, "hotGasTemperature",LUXTRONIK2_CalcTemp($a[26]));
     
     
   # Input / Output status
     readingsBulkUpdate($hash,"heatingSystemCircPump",$a[27]?"on":"off");
     readingsBulkUpdate($hash,"hotWaterCircPumpExtern",$a[28]?"on":"off");
     readingsBulkUpdate($hash,"hotWaterSwitchingValve",$a[9]?"on":"off");

   # bivalentLevel
     readingsBulkUpdate($hash,"bivalentLevel",$a[43]);
     
   # Firmware
     my $firmware = $a[20];
     readingsBulkUpdate($hash,"firmware",$firmware);
     my $firmwareCheck = LUXTRONIK2_checkFirmware($firmware);
     # if unknown firmware, ask at each startup to inform comunity
     if ($hash->{fhem}{alertFirmware} != 1 && $firmwareCheck eq "fwNotTested") {
      $hash->{fhem}{alertFirmware} = 1;
      Log3 $hash, 2, "$name Alert: Host uses untested Firmware '$a[20]'. Please inform FHEM comunity about compatibility.";
     }
     
   # Type of Heatpump  
     $value = $wpType{$a[31]};
     $value = "unbekannt (".$a[31].")" unless $value;
     readingsBulkUpdate($hash,"typeHeatpump",$value);

   # Operating hours (seconds->hours) and heat quantities, write/create readings only if >0   
     if ($a[32] !~ /no/) {readingsBulkUpdate($hash,"counterHours2ndHeatSource1", sprintf("%.1f", $a[32]/3600));}
     if ($a[38] !~ /no/) {readingsBulkUpdate($hash,"counterHours2ndHeatSource2", sprintf("%.1f", $a[38]/3600));}
     if ($a[39] !~ /no/) {readingsBulkUpdate($hash,"counterHours2ndHeatSource3", sprintf("%.1f", $a[39]/3600));}
     if ($a[33] !~ /no/) {readingsBulkUpdate($hash,"counterHoursHeatPump", sprintf("%.1f", $a[33]/3600));}
     if ($a[34] !~ /no/) {readingsBulkUpdate($hash,"counterHoursHeating", sprintf("%.1f", $a[34]/3600));}
     if ($a[35] !~ /no/) {readingsBulkUpdate($hash,"counterHoursHotWater", sprintf("%.1f", $a[35]/3600));}
     if ($a[36] > 0) {readingsBulkUpdate($hash,"counterHeatQHeating", $a[36]/10);}
     if ($a[37] > 0) {readingsBulkUpdate($hash,"counterHeatQHotWater" ,$a[37]/10);}
     if ($a[36] > 0 && $a[37] > 0) {readingsBulkUpdate($hash,"counterHeatQTotal",($a[36]+$a[37])/10);}
     #WM[kW] = delta_Temp [K] * Durchfluss [l/h] / ( 3.600 [kJ/kWh] / ( 4,179 [kJ/(kg*K)] (H2O Wärmekapazität bei 30 & 40°C) * 0,994 [kg/l] (H2O Dichte bei 35°C) )  
     $value = ($flowTemperature-$returnTemperature) * $a[19] / 866.65;
     readingsBulkUpdate( $hash, "currentThermalOutput", sprintf("%.1f", $value));
     
   # Solar
     if ($a[50] !~ /no/) {readingsBulkUpdate($hash, "solarCollectorTemperature", LUXTRONIK2_CalcTemp($a[50]));}
     if ($a[51] !~ /no/) {readingsBulkUpdate($hash, "solarBufferTemperature", LUXTRONIK2_CalcTemp($a[51]));}
     if ($a[52] !~ /no/) {readingsBulkUpdate($hash, "counterHoursSolar", sprintf("%.1f", $a[52]/3600));}
     
   # HTML for floorplan
     if(AttrVal($name, "statusHTML", "none") ne "none") {
        $value = "<div class=fp_" . $a[0] . "_title>" . $a[0] . "</div>";
        $value .= "$opStateHeatPump1<br>";
        $value .= "$opStateHeatPump2<br>";
        $value .= "$opStateHeatPump3<br>";
        $value .= "Brauchwasser: $hotWaterTemperature &deg;C";
        readingsBulkUpdate($hash,"floorplanHTML",$value);
     }
    # State update
      readingsBulkUpdate($hash,"state","$opStateHeatPump1 $opStateHeatPump2 - $opStateHeatPump3");
     
      readingsEndUpdate($hash,1);
     
     $hash->{helper}{fetched_calc_values} = $a[44];
     $hash->{helper}{fetched_parameters} = $a[45];
     
   ############################ 
   #Auto Synchronize Device Clock
     my $autoSynchClock = AttrVal($name, "autoSynchClock", 0);
     $autoSynchClock = 10 unless ($autoSynchClock >= 10 || $autoSynchClock == 0);
     $autoSynchClock = 600 unless $autoSynchClock <= 600;
     if ($autoSynchClock != 0 and abs($delayDeviceTimeCalc) > $autoSynchClock ) {
      Log3 $name, 3, $name." - autoSynchClock triggered (delayDeviceTimeCalc ".abs($delayDeviceTimeCalc)." > $autoSynchClock).";
      # Firmware not tested and Firmware Check not ignored
       if ($firmwareCheck eq "fwNotTested" && AttrVal($name, "ignoreFirmwareCheck", 0)!= 1) {
         Log3 $name, 1, $name." Error: Host firmware '$firmware' not tested for clock synchronization. To test set 'ignoreFirmwareCheck' to 1.";
          $attr{$name}{autoSynchClock} = 0;
         Log3 $name, 3, $name." Attribute 'autoSynchClock' set to 0.";
      #Firmware not compatible
       } elsif ($firmwareCheck eq "fwNotCompatible") {
         Log3 $name, 1, $name." Error: Host firmware '$firmware' not compatible for host clock synchronization.";
          $attr{$name}{autoSynchClock} = 0;
         Log3 $name, 3, $name." Attribute 'autoSynchClock' set to 0.";
      #Firmware OK -> Synchronize Clock
       } else {
         $value = LUXTRONIK2_synchronizeClock($hash, 600);
         Log3 $hash, 3, "$name ".$value;
       }
     }
   #End of Auto Synchronize Device Clock
     ############################ 
   }
   else {
      Log3 $hash, 5, "$name LUXTRONIK2_DoUpdate-Error: Status = $a[1]";
   }
    $hash->{fhem}{counterRetry} = $counterRetry;

}


sub ########################################
LUXTRONIK2_UpdateAborted($)
{
  my ($hash) = @_;
  delete($hash->{helper}{RUNNING_PID});
  my $name = $hash->{NAME};
  my $host = $hash->{HOST};
  Log3 $hash, 1, "$name Error: Timeout when connecting to host $host";
}


sub ########################################
LUXTRONIK2_CalcTemp($)
{
  my ($temp) = @_;
  #change unsigned into signed
  if ($temp > 2147483648) {$temp = $temp-4294967296;}
  $temp /= 10;
  return $temp;
}

sub ########################################
LUXTRONIK2_FormatDuration($)
{
  my ($value) = @_;
  my $returnstr = sprintf "%02d:", int($value/3600);
  $value %= 3600;
  $returnstr .= sprintf "%02d:", int($value/60);
  $value %= 60;
  $returnstr .= sprintf "%02d", $value;
  
  return $returnstr;
}

sub ########################################
LUXTRONIK2_SetParameter($$$)
{
  my ($hash, $parameterName, $realValue) = @_;
  my $setParameter = 0;
  my $setValue = 0;
  my $result;
  my $buffer;
  my $host = $hash->{HOST};
  my $name = $hash->{NAME};
  
   my %opMode = ( "Auto" => 0,
               "Party" => 2,
               "Off" => 4);
   
  if(AttrVal($name, "allowSetParameter", 0) != 1) {
   return $name." Error: Setting of parameters not allowed. Please set attribut 'allowSetParameter' to 1";
  }
  if ($parameterName eq "hotWaterTemperatureTarget") {
     #parameter number
    $setParameter = 2;
    #limit temperature range
    $realValue = 30 if( $realValue < 30 );
    $realValue = 65 if( $realValue > 65 );
    #Allow only integer temperature or with decimal .5
    $setValue = int($realValue * 2) * 5;
    $realValue = $setValue / 10;
  }
  elsif ($parameterName eq "opModeHotWater") {
    if (! exists($opMode{$realValue})) {
      return "$name Error: Wrong parameter given for opModeHotWater, use Automatik,Party,Off"
     }
    $setParameter = 4;
     $setValue = $opMode{$realValue};
  }
  else {
    return "$name LUXTRONIK2_SetParameter-Error: unknown parameter $parameterName";
  }

############################ 
# Send new parameter to host
############################ 
  if ($setParameter !=0) {
     Log3 $name, 5, "$name: Opening connection to host ".$host;
     my $socket = new IO::Socket::INET (  PeerAddr => $host, 
                     PeerPort => 8888,
                     Proto => 'tcp'
       );
     if (!$socket) {
        Log3 $name, 1, "$name LUXTRONIK2_SetParameter-Error: Could not open connection to host ".$host;
        return "$name Error: Could not open connection to host ".$host;
     }
     $socket->autoflush(1);
     
     Log3 $name, 5, "$name: Set parameter $parameterName ($setParameter) = $realValue ($setValue)";
     $socket->send(pack("N", 3002));
     $socket->send(pack("N", $setParameter));
     $socket->send(pack("N", $setValue));
     
     Log3 $name, 5, "$name: Receive confirmation";
    #read first 4 bytes of response -> should be request_echo = 3002
     $socket->recv($buffer,4);
     $result = unpack("N", $buffer);
     if($result != 3002) {
        Log3 $name, 2, "$name LUXTRONIK2_SetParameter-Error: Set parameter $parameterName - wrong echo of request: $result instead of 3002";
        $socket->close();
        return "$name Error: Host did not confirm parameter setting";
     }
    
    #Read next 4 bytes of response -> should be setParameter
     $socket->recv($buffer,4);
     $result = unpack("N", $buffer);
     if($result !=$setParameter) {
        Log3 $name, 2, "$name  LUXTRONIK2_SetParameter-Error: Set parameter $parameterName - missing confirmation: $result instead of $setParameter";
        $socket->close();
        return "$name Error: Host did not confirm parameter setting";
     }
     Log3 $name, 5, "$name: Parameter setting confirmed";
     
     $socket->close();
     
     readingsSingleUpdate($hash,$parameterName,$realValue,1);
     
     return "$name: Parameter $parameterName set to $realValue";
   }
  
}


sub ########################################
LUXTRONIK2_synchronizeClock (@)
{
  my ($hash,$maxDelta) = @_;
  my $host = $hash->{HOST};
  my $name = $hash->{NAME};
  my $delay = 0;
  my $returnStr = "";

  $maxDelta = 60 unless $maxDelta >= 0;
  $maxDelta = 600 unless $maxDelta <= 600;
         
   Log3 $name, 5, "$name: Open telnet connection to $host";
     my $telnet = new Net::Telnet ( Host=>$host, Port => 23, Timeout=>10, Errmode=>'return');
      if (!$telnet) {
       Log3 $name, 1, "$name LUXTRONIK2_synchronizeClock-Error: ".$telnet->errmsg;
        return "$name synchronizeDeviceClock-Error: ".$telnet->errmsg;
      }
  
    Log3 $name, 5, "$name: Log into $host";
      if (!$telnet->login('root', '')) {
        Log3 $name, 1, "$name LUXTRONIK2_synchronizeClock-Error: ".$telnet->errmsg;
        return "$name synchronizeDeviceClock-Error: ".$telnet->errmsg;
      }
      
   Log3 $name, 5, "$name: Read current time of host";
      my @output = $telnet->cmd('date +%s');
     $delay = floor(time()) - $output[0];
   Log3 $name, 5, "$name: Current time is ".localtime($output[0])." Delay is $delay seconds.";

     if (abs($delay)>$maxDelta && $maxDelta!=0) {
      $returnStr = "Do not dare to synchronize. Device clock of host $host differs by $delay seconds (max. is $maxDelta).";
     } elsif ($delay == 0) {
       $returnStr = "Internal clock of host $host has no delay. -> not synchronized";
    } else {
      my $newTime = strftime "%m%d%H%M%Y.%S", localtime();
     Log3 $name, 5, "$name: Run command 'date ".$newTime."'";
      @output=$telnet->cmd('date '.$newTime);
      $returnStr = "Internal clock of host $host corrected by $delay seconds. -> ".$output[0];
      readingsSingleUpdate($hash,"deviceTimeLastSync",TimeNow,1);
     }
   
   Log3 $name, 5, "$name: Close telnet connection.";
   $telnet->close;
   
   return $returnStr;
}

sub ######################################## 
LUXTRONIK2_checkFirmware ($) 
{
  my ($myFirmware) = @_;

  #Firmware not tested
   if (index($testedFirmware,"#".$myFirmware."#") == -1) { 
      return "fwNotTested";
  #Firmware tested but not compatible
   } elsif (index($compatibleFirmware,"#".$myFirmware."#") == -1) { 
      return "fwNotCompatible";
  #Firmware compatible
    } else {
       return "fwCompatible";
   }
}

# Calculate heat-up gradients of boiler based on hotWaterTemperature and counterHeatQHeating
sub ######################################## 
LUXTRONIK2_doStatisticBoilerHeatUp ($$$$$$) 
{

    my ($hash, $currOpHours, $currHQ, $currTemp, $opState, $target) = @_;
   my $name = $hash->{NAME};
    my $step = $hash->{fhem}{statBoilerHeatUpStep};
   my $minTemp = $hash->{fhem}{statBoilerHeatUpMin};
   my $maxTemp = $hash->{fhem}{statBoilerHeatUpMax};
   my $lastHQ = $hash->{fhem}{statBoilerHeatUpHQ};
   my $lastOpHours = $hash->{fhem}{statBoilerHeatUpOpHours}; 
   my $value1 = 0;
    my $value2 = 0;
    my $value3 = 0;
   my $returnStr = "";

  # step 0 = Initialize - if hot water preparation is off
   if ($step == 0) { 
     if ($opState != 5) { # wait till hot water preparation stopped
        Log3 $name, 4, "$name: Statistic Boiler Heat-Up step 0->1: Initializing Measurment";
        $step = 1;
        $lastOpHours = $currOpHours;
        $lastHQ = $currHQ;
        $minTemp = $currTemp;
     }
     
  # step 1 = wait till hot water preparation starts -> monitor Tmin, take previous HQ and previous operating hours
   } elsif ($step == 1) { 
     if ($currTemp < $minTemp) { # monitor minimum temperature
       Log3 $name, 4, "$name: Statistic Boiler Heat-Up step 1: Monitor minimum temperature ($minTemp -> $currTemp)";
       $minTemp = $currTemp;
     }
     if ($opState != 5) { # wait -> update operating hours and HQ to be used as start value in calculations
        $lastOpHours = $currOpHours; 
        $lastHQ = $currHQ;
     } else { # go to step 2 - if hot water preparation running
         Log3 $name, 4, "$name: Statistic Boiler Heat-Up step 1->2: Hot water preparation started ".($currOpHours-$lastOpHours)." s ago";
        $step = 2; 
        $maxTemp = $currTemp;
     }

  # step 2 = wait till hot water preparation done and target reached
   } elsif ($step == 2) { 
     if ($currTemp < $minTemp) { # monitor minimal temperature
       Log3 $name, 4, "$name: Statistic Boiler Heat-Up step 2: Boiler temperature still decreasing ($minTemp -> $currTemp)";
       $minTemp = $currTemp;
     }
     if ($currTemp > $maxTemp) { # monitor maximal temperature
       Log3 $name, 4, "$name: Statistic Boiler Heat-Up step 2: Boiler temperature increasing ($maxTemp -> $currTemp)";
       $maxTemp = $currTemp;
     }
     
     if ($opState != 5) { # wait till hot water preparation stopped
        if ($currTemp >= $target) {
          Log3 $name, 4, "$name: Statistic Boiler Heat-Up step 2->3: Hot water preparation stopped";
           $step = 3; 
        } else {
           Log3 $name, 4, "$name: Statistic Boiler Heat-Up step 2->1: Measurement cancelled (hot water preparation stopped but target not reached, $currTemp < $target)";
           $step = 1; 
           $lastOpHours = $currOpHours; 
           $lastHQ = $currHQ;
           $minTemp = $currTemp;
        }
     }
     
  # step 3 = wait with calculation till temperature maximum reached once
   } elsif ($step == 3) { 
     # cancel measurement - if hot water preparation has restarted
      if ($opState == 5) { 
         Log3 $name, 4, "$name: Statistic Boiler Heat-Up step 3->0: Measurement cancelled (hot water preparation restarted before maximum reached)";
        $step = 0; 
    # monitor maximal temperature
       } elsif ($currTemp > $maxTemp) { 
        Log3 $name, 4, "$name: Statistic Boiler Heat-Up step 3: Temperature still increasing ($maxTemp -> $currTemp)";
        $maxTemp = $currTemp;
    # else calculate temperature gradient 
      } else {
        Log3 $name, 4, "$name: Statistic Boiler Heat-Up step 3->1: Boiler heat-up measurement finished";
        $value1 =  ( int(10 * $maxTemp) - int(10 * $minTemp) ) / 10; # delta hot water temperature
        $value2 = ( $currOpHours - $lastOpHours ) / 60; # delta time (minutes)
        # $value3 = floor(100 * $value1 / $value2 + 0.5) / 100;  # Temperature gradient over time rounded to 1/100th
        # $value2 = floor(100 * $value2 + 0.5) / 100; # rounded to 1/100th
        $returnStr = "DT/min: ".sprintf("%.2f", $value1/$value2)." DT: ".sprintf("%.2f", $value1)." Dmin: ".sprintf("%.0f", $value2);

        $value2 = $currHQ - $lastHQ; # delta heat quantity
        # $value2 = floor(10*($currHQ - $lastHQ)+0.5)/10; # delta heat quantity
        # $value3 = floor(100 * $value2 / $value1 + 0.5) / 100;  # heat gradient over temperature rounded to 1/100th
        $returnStr .= " DQ/T: ".sprintf("%.2f",$value2/$value1)." DQ: ".sprintf("%.1f",$value2);

        #Volumen [l] = Wärmemenge [kWh] / (delta T) [K] * ( 3.600 [kJ/kWh] / ( 4,179 [kJ/(kg*K)] (H2O Wärmekapazität bei 40°C) * 0,992 [kg/l] (H2O Dichte bei 40°C) ) [K/(kWh*l)] )  
        $value3 = 868.4 * $value2 / $value1 ;  # heated water volume in liter
        $returnStr .= " DV: ".sprintf("%.0f",$value3);
        
        $step = 1; 
        $lastOpHours = $currOpHours; 
        $lastHQ = $currHQ;
        $minTemp = $currTemp;

      }
   }
    $hash->{fhem}{statBoilerHeatUpStep} = $step;
    $hash->{fhem}{statBoilerHeatUpMin} = $minTemp;
   $hash->{fhem}{statBoilerHeatUpMax} = $maxTemp;
   $hash->{fhem}{statBoilerHeatUpHQ} = $lastHQ;
   $hash->{fhem}{statBoilerHeatUpOpHours} = $lastOpHours; 
   
    return $returnStr;
     
}
     
# Calculate heat loss gradients of boiler based on hotWaterTemperature and counterHeatQHeating
sub ######################################## 
LUXTRONIK2_doStatisticBoilerCoolDown ($$$$$$) 
{
    my ($hash, $time, $currTemp, $opState, $target, $threshold) = @_;
   my $name = $hash->{NAME};
    my $step = $hash->{fhem}{statBoilerCoolDownStep};
   my $maxTemp = $hash->{fhem}{statBoilerCoolDownMax};
   my $startTime = $hash->{fhem}{statBoilerCoolDownStartTime}; 
    my $value1 = 0;
    my $value2 = 0;
    my $value3 = 0;
   my $returnStr = "";

  # step 0 = Initialize - if hot water preparation is off and target reached, 
    if ($step == 0) { 
     if ($opState == 5 || $currTemp < $target) { # -> stay step 0
        # Log3 $name, 4, "$name: Statistic Boiler Cool-Down step 0: Wait till hot water preparation stops and target is reached ($currTemp < $target)";
     } else {
        Log3 $name, 4, "$name: Statistic Boiler Cool-Down step 0->1: Initializing, target reached ($currTemp >= $target)";
        $step = 1; 
        $startTime = $time; 
        $maxTemp = $currTemp;
     }
  # step 1 = wait till threshold is reached -> do calculation, monitor maximal temperature
    } elsif ($step == 1) { 
     if ($currTemp > $maxTemp) { # monitor maximal temperature
        Log3 $name, 4, "$name: Statistic Boiler Cool-Down step 1: Temperature still increasing ($currTemp > $maxTemp)";
         $maxTemp = $currTemp;
        $startTime = $time; 
     }
     if ($opState == 5) {
        Log3 $name, 4, "$name: Statistic Boiler Cool-Down step 1: Measurement cancelled (restart of hot water preparation)";
        $step = 0;
     } elsif ($currTemp <= $threshold) {
         Log3 $name, 4, "$name: Statistic Boiler Cool-Down step 2->1: Measurement finished, threshold reached ($currTemp <= $threshold)";
        $value1 =  ( int(10 * $currTemp) - int(10 * $maxTemp) ) / 10; # delta hot water temperature
        $value2 = ( $time - $startTime ) / 3600; # delta time (hours)
        $value3 = floor(100 * $value1 / $value2 + 0.5) / 100;  # Temperature gradient over time rounded to 1/100th
        $value2 = floor(100 * $value2 + 0.5) / 100; # rounded to 1/100th
        $returnStr = "DT/h: $value3 DT: $value1 Dh: $value2";

        $step = 0;
     }
    }   

    $hash->{fhem}{statBoilerCoolDownStep} = $step;
   $hash->{fhem}{statBoilerCoolDownMax} = $maxTemp;
   $hash->{fhem}{statBoilerCoolDownStartTime} = $startTime; 

   return $returnStr;
}   


1;

=pod
=begin html

<a name="LUXTRONIK2"></a>
<h3>LUXTRONIK2</h3>
<ul>
  Luxtronik 2.0 is a heating controller used in <a href="http://www.alpha-innotec.de">Alpha Innotec</a> and Siemens Novelan (WPR NET) heat pumps.
  <br>
  It has a built-in ethernet port, so it can be directly integrated into a local area network (LAN).
  <br>
  <i>The modul is reported to work with firmware: V1.54C, V1.60, V1.69.</i>
  <br>
  &nbsp;
  <br>
  
  <a name="LUXTRONIK2define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; LUXTRONIK2 &lt;IP-address&gt; [poll-interval]</code><br>
    If the pool interval is omitted, it is set to 300 (seconds). Smallest possible value is 30.
    <br>
    Example: <code>define Heizung LUXTRONIK2 192.168.0.12 600</code>
  </ul>
  <br>
  
  <a name="LUXTRONIK2set"></a>
  <b>Set</b>
   <ul>A firmware check assures before each set operation that a heat pump with untested firmware is not damaged accidently.
      <li><code>opModeHotWater &lt;Mode&gt;</code><br>
         Operating Mode of domestic hot water boiler (Auto | Party | Off)</li>
      <li><code>hotWaterTemperatureTarget &lt;temperature&gt;</code><br>
         Target temperature of domestic hot water boiler in &deg;C</li>
      <li><code>INTERVAL &lt;polling interval&gt;</code><br>
         Polling interval in seconds</li>
      <li><code>statusRequest</code><br>
         Update device information</li>
      <li><code>synchClockHeatPump</code><br>
         Synchronizes controller clock with FHEM time. <b>!! This change is lost in case of controller power off!!</b></li>
   </ul>
   <br>
   
   <a name="LUXTRONIK2get"></a>
   <b>Get</b>
   <ul>
      No get implemented yet ...
   </ul>
   <br>
  
   <a name="LUXTRONIK2attr"></a>
   <b>Attributes</b>
   <ul>
      <li><code>statusHTML</code>
         <br>
         If set, a HTML-formatted reading named "floorplanHTML" is created. It can be used with the <a href="#FLOORPLAN">FLOORPLAN</a> module.
         <br>
         Currently, if the value of this attribute is not NULL, the corresponding reading consists of the current status of the heat pump and the temperature of the water.</li>
      <li><code>doStatistics &lt; 0 | 1 &gt;</code>
         <br>
         Calculates statistic values: <i>statBoilerGradientHeatUp, statBoilerGradientCoolDown, statBoilerGradientCoolDownMin (boiler heat loss)</i></li>
      <li><code>allowSetParameter &lt; 0 | 1 &gt;</code>
         <br>
         The <a href="#LUXTRONIK2set">parameters</a> of the heat pump controller can only be changed if this attribut is set to 1.</li>
      <li><code>autoSynchClock &lt;delay&gt;</code>
         <br>
         Corrects the clock of the heatpump automatically if a certain <i>delay</i> (10 s - 600 s) against the FHEM time is exeeded. Does a firmware check before.
         <br>
         <i>(A 'delayDeviceTimeCalc' &lt;= 2 s can be caused by the internal calculation interval of the heat pump controller.)</i></li>
      <li><code>ignoreFirmwareCheck &lt; 0 | 1 &gt;</code>
         <br>
         A firmware check assures before each set operation that a heatpump controller with untested firmware is not damaged accidently.
         <br>
         If this attribute is set to 1, the firmware check is ignored and new firmware can be tested for compatibility.</li>
      <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
   </ul>
</ul>

=end html

=begin html_DE

<a name="LUXTRONIK2"></a>
<h3>LUXTRONIK2</h3>
<ul>
  Die Luxtronik 2.0 ist eine Heizungssteuerung, welche in W&auml;rmepumpen von <a href="http://www.alpha-innotec.de">Alpha Innotec</a> und Siemens Novelan (WPR NET) verbaut ist.<br>
  Sie besitzt einen Ethernet Anschluss, so dass sie direkt in lokale Netzwerke (LAN) integriert werden kann.<br>
  <i>Das Modul wurde bisher mit folgender Steuerungs-Firmware getestet: V1.54C, V1.60, V1.69.</i>
  <br>&nbsp;
  <br>
  
  <a name="LUXTRONIK2define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; LUXTRONIK2 &lt;IP-Adresse&gt; [Abfrageinterval]</code>
    <br>
    Wenn das Abfrage-Interval nicht angegeben ist, wird es auf 300 (Sekunden) gesetzt. Der kleinste m&ouml;gliche Wert ist 30.
    <br>
    Beispiel: <code>define Heizung LUXTRONIK2 192.168.0.12 600</code>
 
  </ul>
  <br>
  
  <a name="LUXTRONIK2set"></a>
  <b>Set</b><br>
  <ul>
     Durch einen Firmware-Test wird vor jeder Set-Operation sichergestellt, dass W&auml;rmepumpen mit ungetester Firmware nicht unabsichtlich besch&auml;digt werden.
      <li><code>opModeHotWater &lt;Betriebsmodus&gt;</code>
         <br>
         Betriebsmodus des Hei&szlig;wasserboilers ( Auto | Party | Off )</li>
     <li><code>hotWaterTemperatureTarget &lt;Temperatur&gt;</code>
         <br>
         Soll-Temperatur des Hei&szlig;wasserboilers in &deg;C</li>
     <li><code>INTERVAL &lt;Abfrageinterval&gt;</code>
         <br>
         Abfrageinterval in Sekunden</li>
     <li><code>statusRequest</code>
         <br>
         Aktualisieren der Ger&auml;tewerte</li>
     <li><code>synchClockHeatPump</code>
         <br>
         Abgleich der Uhr der Steuerung mit der FHEM Zeit. <b>Diese &Auml;nderung geht verloren, sobald die Steuerung ausgeschaltet wird!!</b></li>
  </ul>
  <br>
  
  <a name="LUXTRONIK2get"></a>
  <b>Get</b>
  <ul>
      Es wurde noch kein "get" implementiert ...
  </ul>
  <br>
  
  <a name="LUXTRONIK2attr"></a>
  <b>Attribute</b>
  <ul>
    <li><code>statusHTML</code><br>
      wenn gesetzt, dann wird ein HTML-formatierter Wert "floorplanHTML" erzeugt, 
      welcher vom Modul <a href="#FLOORPLAN">FLOORPLAN</a> genutzt werden kann.<br>
      Momentan wird nur gepr&uuml;ft, ob der Wert dieses Attributes ungleich NULL ist, 
      der entsprechende Ger&auml;tewerte besteht aus dem aktuellen W&auml;rmepumpenstatus und der Heizwassertemperatur.</li>
    <li><code>doStatistics &lt; 0 | 1 &gt;</code>
      <br>
      Berechnet statistische Werte: <i>statBoilerGradientHeatUp, statBoilerGradientCoolDown,
      statBoilerGradientCoolDownMin (W&auml;rmeverlust des Boilers)</i></li>
   <li><code>allowSetParameter &lt; 0 | 1 &gt;</code>
      <br>
      Die internen <a href="#LUXTRONIK2set">Parameter</a> der W&auml;rmepumpensteuerung k&ouml;nnen
      nur ge&auml;ndert werden, wenn dieses Attribut auf 1 gesetzt ist.</li>
   <li><code>autoSynchClock &lt;Zeitunterschied&gt;</code>
      <br>
      Die Uhr der W&auml;rmepumpe wird automatisch korrigiert, wenn ein gewisser <i>Zeitunterschied</i> (10 s - 600 s) 
      gegen&uuml;ber der FHEM Zeit erreicht ist. Zuvor wird die Kompatibilit&auml;t der Firmware &uuml;berpr&uuml;ft.<br>
      <i>(Ein Ger&auml;tewert 'delayDeviceTimeCalc' &lt;= 2 s ist auf die internen Berechnungsintervale der
      W&auml;rmepumpensteuerung zur&uuml;ckzuf&uuml;hren.)</i></li>
   <li><code>ignoreFirmwareCheck &lt; 0 | 1 &gt;</code>
      <br>
      Durch einen Firmware-Test wird vor jeder Set-Operation sichergestellt, dass W&auml;rmepumpen
      mit ungetester Firmware nicht unabsichtlich besch&auml;digt werden. Wenn dieses Attribute auf 1
      gesetzt ist, dann wird der Firmware-Test ignoriert und neue Firmware kann getestet werden.
      Dieses Attribut wird jedoch ignoriert, wenn die Steuerungs-Firmware bereits als nicht kompatibel berichtet wurde.</li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
</ul>

=end html_DE
=cut

