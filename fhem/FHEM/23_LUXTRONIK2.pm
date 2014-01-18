################################################################
#
#  Copyright notice
#
#  (c) 2012,2014 Torsten Poitzsch (torsten.poitzsch@gmx.de)
#  (c) 2012-2013 Jan-Hinrich Fessel (oskar@fessel.org)
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
use POSIX;

my $cc; # The Itmes Changed Counter

sub
LUXTRONIK2_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "LUXTRONIK2_Define";
  $hash->{UndefFn}  = "LUXTRONIK2_Undefine";
  $hash->{SetFn}    = "LUXTRONIK2_Set";
  $hash->{AttrList} = "disable:0,1 ".
					  "allowSetParameter ".
					  "statusHTML ".
					  $readingFnAttributes;
}

sub
LUXTRONIK2_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "Usage: define <name> LUXTRONIK2 <ip-address> [poll-interval]" if(@a <3 || @a >4);

  my $name = $a[0];
  my $host = $a[2];

  my $interval = 5*60;
  $interval = $a[3] if(int(@a) == 4);
  $interval = 1*60 if( $interval < 1*60 );

  $hash->{NAME} = $name;

  $hash->{STATE} = "Initializing";
  $hash->{HOST} = $host;
  $hash->{INTERVAL} = $interval;

  RemoveInternalTimer($hash);
  #Get first data after 10 seconds
  InternalTimer(gettimeofday() + 10, "LUXTRONIK2_GetUpdate", $hash, 0);

  #Reset temporary values (min and max reading durations)
  $hash->{fhem}{durationFetchReadingsMin} = 0;
  $hash->{fhem}{durationFetchReadingsMax} = 0;
 
  return undef;
}

sub
LUXTRONIK2_Undefine($$)
{
  my ($hash, $arg) = @_;

  RemoveInternalTimer($hash);

  BlockingKill($hash->{helper}{RUNNING_PID}) if(defined($hash->{helper}{RUNNING_PID}));

  return undef;
}

sub
LUXTRONIK2_Set($$@)
{
  my ($hash, $name, $cmd, $val) = @_;
  my $resultStr;
  
  if($cmd eq 'statusRequest') {
    $hash->{LOCAL} = 1;
    LUXTRONIK2_GetUpdate($hash);
    $hash->{LOCAL} = 0;
    return undef;
  }
  elsif($cmd eq 'INTERVAL' && int(@_)==4 ) {
		$val = 1*60 if( $val < 1*60 );
		$hash->{INTERVAL}=$val;
		return "Polling interval set to $val seconds.";
  }
  elsif(int(@_)==4 && ( 
			$cmd eq 'hotWaterTemperatureTarget' ||
			$cmd eq 'hotWaterOperatingMode'
		)) {
		$hash->{LOCAL} = 1;
		$resultStr = LUXTRONIK2_SetParameter ($hash, $cmd, $val);
		$hash->{LOCAL} = 0;
		return $resultStr;
  }
  
  my $list = "statusRequest:noArg".
			 " hotWaterTemperatureTarget:slider,30.0,0.5,65.0".
			 " hotWaterOperatingMode:Automatik,Party,Off".
			 " INTERVAL:slider,60,30,1800";
  return "Unknown argument $cmd, choose one of $list";
}


sub
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

  $hash->{helper}{RUNNING_PID} = BlockingCall("LUXTRONIK2_DoUpdate", $name."|".$host, "LUXTRONIK2_UpdateDone", 10, "LUXTRONIK2_UpdateAborted", $hash) unless(exists($hash->{helper}{RUNNING_PID}));
}


sub
LUXTRONIK2_DoUpdate($)
{
  my ($string) = @_;
  my ($name, $host) = split("\\|", $string);

  my @heatpump_values;
  my @heatpump_parameters;
  my $count=0;
  my $result="";
  my $readingStartTime = time();
  
  Log3 $name, 5, "$name: Opening connection to host ".$host;
  my $socket = new IO::Socket::INET (  PeerAddr => $host, 
				       PeerPort => 8888,
				       #   Type => SOCK_STREAM, # probably needed on some systems
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
 #(FOV) read first 4 digits of response -> should be request_echo = 3004
  $socket->recv($result,4);
  $count = unpack("N", $result);
  if($count != 3004) {
      Log3 $name, 2, "$name LUXTRONIK2_DoUpdate-Error: Fetching operational values - wrong echo of request 3004: ".length($result)." -> ".$count;
  	  $socket->close();
      return "$name|0|3004 != 3004";
  }
 
 #(FOV) read next 4 digits of response -> should be status = 0
  $socket->recv($result,4);
  $count = unpack("N", $result);
  if($count > 0) {
      Log3 $name, 4, "$name parameter on target changed, restart parameter reading after 5 seconds";
	  $socket->close();
      return "$name|2|Status = $count - parameter on target changed, restart device reading after 5 seconds";
  }
  
 #(FOV) read next 4 digits of response -> should be number_of_parameters > 0
  $socket->recv($result,4);
  $count = unpack("N", $result);
  if($count == 0) {
      Log3 $name, 2, "$name LUXTRONIK2_DoUpdate-Error:  Fetching operational values - 0 values announced: ".length($result)." -> ".$count;
	  $socket->close();
      return "$name|0|0 values read";
  }
  
 #(FOV) read remaining response -> should be previous number of parameters
  my $i=1;
  $result="";
  my $buf="";
  while($i<=$count) {
	  $socket->recv($buf,4);
      $result.=$buf;
	  $i++;
  }
  if(length($result) != $count*4) {
      Log3 $name, 1, "$name LUXTRONIK2_DoUpdate-Error: operational values length check: ".length($result)." should have been ". $count * 4;
 	  $socket->close();
      return "$name|0|Number of values read mismatch ( $!)\n";
  }
  
 #(FOV) unpack response in array
  @heatpump_values = unpack("N$count", $result);
  if(scalar(@heatpump_values) != $count) {
      Log3 $name, 2, "$name LUXTRONIK2_DoUpdate-Error: unpacking problem by operation values: ".scalar(@heatpump_values)." instead of ".$count;
 	  $socket->close();
      return "$name|0|Unpacking problem of operational values";
  }

  Log3 $name, 5, "$name: $count operational values received";
 
############################ 
#Fetch set parameters (FSP)
############################ 
  Log3 $name, 5, "$name: Ask host for set parameters";
  $socket->send(pack("N", 3003));
  $socket->send(pack("N", 0));

  Log3 $name, 5, "$name: Start to receive set parameters";
 #(FSP) read first 4 digits of response -> should be request_echo=3003
  $socket->recv($result,4);
  $count = unpack("N", $result);
  if($count != 3003) {
      Log3 $name, 2, "$name LUXTRONIK2_DoUpdate-Error: wrong echo of request 3003: ".length($result)." -> ".$count;
      $socket->close();
      return "$name|0|3003 != 3003";
  }
  
 #(FSP) read next 4 digits of response -> should be number_of_parameters > 0
  $socket->recv($result,4);
  $count = unpack("N", $result);
  if($count == 0) {
      Log3 $name, 2, "$name LUXTRONIK2_DoUpdate-Error: 0 parameter read: ".length($result)." -> ".$count;
	  $socket->close();
      return "$name|0|0 parameter read";
  }
  
 #(FSP) read remaining response -> should be previous number of parameters
   my $i=1;
  $result="";
  my $buf="";
  while($i<=$count) {
	  $socket->recv($buf,4);
      $result.=$buf;
	  $i++;
  }
  if(length($result) != $count*4) {
      Log3 $name, 1, "$name LUXTRONIK2_DoUpdate-Error: parameter length check: ".length($result)." should have been ". $count * 4;
	  $socket->close();
      return "$name|0|Number of parameters read mismatch ( $!)\n";
  }

  @heatpump_parameters = unpack("N$count", $result);
  if(scalar(@heatpump_parameters) != $count) {
      Log3 $name, 2, "$name LUXTRONIK2_DoUpdate-Error: unpacking problem by set parameter: ".scalar(@heatpump_parameters)." instead of ".$count;
	  $socket->close();
      return "$name|0|Unpacking problem of set parameters";
  }

  Log3 $name, 5, "$name: $count set values received";

  Log3 $name, 5, "$name: Closing connection to host $host";
  $socket->close();

  my $readingEndTime = time();

#return certain readings for further processing
  # 0 - name
  my $return_str="$name";
  # 1 - no error = 1
  $return_str .= "|1";
  # 2 - currentOperatingStatus1
  $return_str .= "|".$heatpump_values[117];
  # 3 - currentOperatingStatus2
  $return_str .= "|".$heatpump_values[119];
  # 4 - Stufe - Value 121
  $return_str .= "|".$heatpump_values[121];
  # 5 - Temperature Value 122
  $return_str .= "|".$heatpump_values[122];
  # 6 - Kreisumkehrventil 
  $return_str .= "|".$heatpump_values[44];
  # 7 - hotWaterOperatingMode
  $return_str .= "|".$heatpump_parameters[4];
  # 8 - hotWaterMonitoring
  $return_str .= "|".$heatpump_values[124];
  # 9 - hotWaterBoilerValve
  $return_str .= "|".$heatpump_values[38];
  # 10 - heatingOperatingMode
  $return_str .= "|".$heatpump_parameters[3];
  # 11 - heatingSommerMode
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
  $return_str .= "|".$heatpump_values[13];
  # 19 - flowRate
  $return_str .= "|".$heatpump_values[155];
  # 20 - firmware
  my $fwvalue = "";
  for(my $fi=81; $fi<91; $fi++) {
      $fwvalue .= chr($heatpump_values[$fi]) if $heatpump_values[$fi];
  }
  $return_str .= "|".$fwvalue;
  # 21 - thresholdTemperatureSummerMode
  $return_str .= "|".$heatpump_parameters[700];
  # 22 - readingsDeviceTime
  $return_str .= "|".$heatpump_values[134];
  # 23 - heatSourceIN
  $return_str .= "|".$heatpump_values[19];
  # 24 - heatSourceOUT
  $return_str .= "|".$heatpump_values[20];
  # 25 - hotWaterTemperatureTarget
  $return_str .= "|".$heatpump_values[18];
  # 26 - hotGasTemperature
  $return_str .= "|".$heatpump_values[14];
  # 27 - heatingSystemCirculationPump
  $return_str .= "|".$heatpump_values[39];
  # 28 - hotWaterCirculatingPumpExtern
  $return_str .= "|".$heatpump_values[46];
  # 29 - readingStartTime
  $return_str .= "|".$readingStartTime;
  # 30 - readingEndTime
  $return_str .= "|".$readingEndTime;

  return $return_str;
}


sub
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
				5 => "Abtauen" );
  my %wpOpStat2 = ( 0 => "Heizbetrieb",
				1 => "Keine Anforderung",
				2 => "Netz Einschaltverz&ouml;gerung",
				3 => "Schaltspielzeit",
				4 => "EVU Sperrzeit",
				5 => "Brauchwasser",
				6 => "Stufe",
				7 => "Abtauen",
				8 => "Pumpenvorlauf",
				9 => "Thermische Desinfektion",
				10 => "Kuehlbetrieb",
				12 => "Schwimmbad",
				13 => "Heizen_Ext_En",
				14 => "Brauchw_Ext_En",
				16 => "Durchflussueberwachung",
				17 => "Elektrische Zusatzheizung" );
  my %wpMode = ( 0 => "Automatik",
			 1 => "Zusatzheizung",
			 2 => "Party",
			 3 => "Ferien",
			 4 => "Aus" );
  #List of firmware that are known to be compatible with this modul
  my $compatibleFirmware = "#V1.54C#";
			 
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

  #Operating status of heatpump
	  my $currentOperatingStatus1 = $wpOpStat1{$a[2]};
      $currentOperatingStatus1 = "unbekannt (".$a[2].")" unless $currentOperatingStatus1;
	  readingsBulkUpdate($hash,"currentOperatingStatus1",$currentOperatingStatus1);
	  my $currentOperatingStatus2 = $wpOpStat2{$a[3]};
	  # refine text of second state
	  if ($a[3]==6) { 
	     $currentOperatingStatus2 = "Stufe ".$a[4]." ".LUXTRONIK2_CalcTemp($a[5])." &deg;C "; 
	  }
      elsif ($a[3]==7) { 
         if ($a[6]==1) {$currentOperatingStatus2 = "Abtauen (Kreisumkehr)";}
         else {$currentOperatingStatus2 = "Luftabtauen";}
      }
      $currentOperatingStatus2 = "unbekannt (".$a[3].")" unless $currentOperatingStatus2;
	  readingsBulkUpdate($hash,"currentOperatingStatus2",$currentOperatingStatus2);
	  
	# Hot water operating mode 
	  $value = $wpMode{$a[7]};
	  $value = "unbekannt (".$a[7].")" unless $value;
	  readingsBulkUpdate($hash,"hotWaterOperatingMode",$value);
	# hotWaterStatus
	  if ($a[8]==0) {$value="Sperrzeit";}
      elsif ($a[8]==1 && $a[9]==1) {$value="Aufheizen";}
      elsif ($a[8]==1 && $a[9]==0) {$value="Temp.OK";}
	  elsif ($a[8]==3) {$value="Aus";}
      else {$value = "unbekannt (".$a[8]."/".$a[9].")";}
	  readingsBulkUpdate($hash,"hotWaterStatus",$value);

	# Heating operating mode including summer mode and average ambient temperature
	  readingsBulkUpdate($hash,"heatingSummerMode",$a[11]?"on":"off");
	  my $thresholdTemperatureSummerMode=LUXTRONIK2_CalcTemp($a[21]);
	  readingsBulkUpdate($hash,"thresholdTemperatureSummerMode",$thresholdTemperatureSummerMode);
	  my $averageAmbientTemperature=LUXTRONIK2_CalcTemp($a[13]);
	  readingsBulkUpdate($hash,"averageAmbientTemperature",$averageAmbientTemperature);
	  # Heating operating mode
	  $value = $wpMode{$a[10]};
	  # Consider also summer mode
	  if ($a[10] == 0 
	        && $a[11] == 1
		    && $averageAmbientTemperature >= $thresholdTemperatureSummerMode)
        {$value = "Automatik - Sommerbetrieb (Aus)";}
	  $value = "unbekannt (".$a[10].")" unless $value;
	  readingsBulkUpdate($hash,"heatingOperatingMode",$value);
	  
	# Remaining temperatures and flow rate
	  readingsBulkUpdate($hash,"ambientTemperature",LUXTRONIK2_CalcTemp($a[12]));
	  my $hotWaterTemperature = LUXTRONIK2_CalcTemp($a[14]);
	  readingsBulkUpdate($hash,"hotWaterTemperature",$hotWaterTemperature);
	  readingsBulkUpdate($hash,"hotWaterTemperatureTarget",LUXTRONIK2_CalcTemp($a[25]));
	  readingsBulkUpdate($hash,"flowTemperature",LUXTRONIK2_CalcTemp($a[15]));
	  readingsBulkUpdate($hash,"returnTemperature",LUXTRONIK2_CalcTemp($a[16]));
	  readingsBulkUpdate($hash,"returnTemperatureTarget",LUXTRONIK2_CalcTemp($a[17]));
	  readingsBulkUpdate($hash,"returnTemperatureExtern",LUXTRONIK2_CalcTemp($a[18]));
	  readingsBulkUpdate($hash,"flowRate",$a[19]);
	  readingsBulkUpdate($hash,"heatSourceIN",LUXTRONIK2_CalcTemp($a[23]));
	  readingsBulkUpdate($hash,"heatSourceOUT",LUXTRONIK2_CalcTemp($a[24]));
	  readingsBulkUpdate($hash,"hotGasTemperature",LUXTRONIK2_CalcTemp($a[26]));
	  
	# Input / Output status
	  readingsBulkUpdate($hash,"heatingSystemCirculationPump",$a[27]?"on":"off");
	  readingsBulkUpdate($hash,"hotWaterCirculationPumpExtern",$a[28]?"on":"off");
	  readingsBulkUpdate($hash,"hotWaterSwitchingValve",$a[9]?"on":"off");
	  
	# Firmware
	  readingsBulkUpdate($hash,"firmware",$a[20]);
	  # if unknown firmware, ask at each startup to inform comunity
	  if (!$hash->{fhem}{alertFirmware} && index("#".$a[20]."#",$compatibleFirmware) == -1) {
		$hash->{fhem}{alertFirmware} = 1;
		Log3 $hash, 2, "$name Alert: Host uses untested Firmware $a[20]. Please inform FHEM comunity about compatibility.";
	  }
	  
	# Device times during readings 
	  $value = strftime "%Y-%m-%d %H:%M:%S", localtime($a[22]);
	  readingsBulkUpdate($hash, "deviceTimeStartReadings", $value);
	  readingsBulkUpdate($hash, "delayDeviceTime", floor($a[29]-$a[22]+0.5));
	  my $durationFetchReadings = floor(($a[30]-$a[29]+0.005)*100)/100;
	  readingsBulkUpdate($hash, "durationFetchReadings", $durationFetchReadings);
	  #Remember min and max reading durations, will be reset when initializing the device
	  if ($hash->{fhem}{durationFetchReadingsMin} == 0 || $hash->{fhem}{durationFetchReadingsMin} > $durationFetchReadings) {
		$hash->{fhem}{durationFetchReadingsMin} = $durationFetchReadings;
		} 
	  if ($hash->{fhem}{durationFetchReadingsMax} < $durationFetchReadings) {
		$hash->{fhem}{durationFetchReadingsMax} = $durationFetchReadings;
		} 
	#HTML for floorplan
	if(AttrVal($name, "statusHTML", "none") ne "none") {
		  $value = "<div class=fp_" . $a[0] . "_title>" . $a[0] . "</div>";
		  $value .= $currentOperatingStatus1 . "<br>";
		  $value .= $currentOperatingStatus2 . "<br>";
		  $value .= "Brauchwasser: " . $hotWaterTemperature . "&deg;C";
		  readingsBulkUpdate($hash,"floorplanHTML",$value);
	  }

 	  readingsBulkUpdate($hash,"state",$currentOperatingStatus1." - ".$currentOperatingStatus2);
	  
      readingsEndUpdate($hash,1);

	}
	else {
		Log3 $hash, 5, "$name LUXTRONIK2_DoUpdate-Error: Status = $a[1]";
	}
    $hash->{fhem}{counterRetry} = $counterRetry;

}


sub
LUXTRONIK2_UpdateAborted($)
{
  my ($hash) = @_;
  delete($hash->{helper}{RUNNING_PID});
  my $name = $hash->{NAME};
  Log3 $hash, 1, "$name LUXTRONIK2_UpdateAborted: Timeout when connecting to host";
}


sub
LUXTRONIK2_CalcTemp($)
{
  my ($temp) = @_;
  if ($temp > 100000) {$temp = $temp-4294967296;}
  $temp /= 10;
  return $temp;
}


sub
LUXTRONIK2_SetParameter($$$)
{
  my ($hash, $parameterName, $realValue) = @_;
  my $setParameter = 0;
  my $setValue = 0;
  my $result;
  my $buffer;
  my $host = $hash->{HOST};
  my $name = $hash->{NAME};
  
   my %opMode = ( "Automatik" => 0,
			      "Party" => 2,
			      "Off" => 4);
   
  if(AttrVal($name, "allowSetParameter", "no") ne "yes") {
	return $name." Error: Setting of parameters not allowed. Please set attribut 'allowSetParameter' to 'yes'";
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
  elsif ($parameterName eq "hotWaterOperatingMode") {
	 if (! exists($opMode{$realValue})) {
		return "$name Error: Wrong parameter given for hotWaterOperatingMode, use Automatik,Party,Off"
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
	 #read first 4 digits of response -> should be request_echo = 3002
	  $socket->recv($buffer,4);
	  $result = unpack("N", $buffer);
	  if($result != 3002) {
		  Log3 $name, 2, "$name LUXTRONIK2_SetParameter-Error: Set parameter $parameterName - wrong echo of request: $result instead of 3002";
		  $socket->close();
		  return "$name Error: Host did not confirm parameter setting";
	  }
	 
	 #Read next 4 digits of response -> should be setParameter
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

1;

=pod
=begin html

<a name="LUXTRONIK2"></a>
<h3>LUXTRONIK2</h3>
<ul>
  Luxtronik 2.0 is a heating controller used in Alpha Innotec and Siemens Novelan Heatpumps.
  It has a builtin Ethernet Port, so it can be directly integrated into a local area network.
  <i>The modul uses the communication features of the firmware v1.54C.</i>
  <br>
  
  <a name="LUXTRONIK2define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; LUXTRONIK2 &lt;IP-address&gt; [poll-interval]</code>
    <br>
    If the pool interval is omitted, it is set to 300 (seconds). Smallest possible value is 60.
    <br>
    Example:
    <ul>
      <code>define Heizung LUXTRONIK2 192.168.0.12 600</code>
    </ul>
  </ul>
  <br>
  
  <a name="LUXTRONIK2set"></a>
  <b>Set </b>
  <ul><b>&lt;hotWaterOperatingMode%gt;</b> &lt;Mode:Auto|Party|Off%gt;- Operating Mode of domestic hot water boiler</ul>
  <ul><b>&lt;hotWaterTemperatureTarget%gt;</b> &lt;temperature &deg;C%gt; - Target temperature of domestic hot water boiler</ul>
  <ul><b>&lt;INTERVAL%gt;</b> &lt;seconds%gt; - Polling interval</ul>
  <ul><b>&lt;statusRequest%gt;</b> - Update device information</ul>
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
    <li>statusHTML<br>
      if set, creates a HTML-formatted reading named "floorplanHTML" for use with the <a href="#FLOORPLAN">FLOORPLAN</a> module.<br>
      Currently, if the value of this attribute is not NULL, the corresponding reading consists of the current status of the heatpump and the temperature of the water.</li>
    <li>allowSetParameter<br>
      <a href="#LUXTRONIK2set">Parameters</a> of the heatpump controller can only be changed if this attribut is set to 'yes'.</li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
  </ul>
  <br>
  
</ul>

=end html
=cut

