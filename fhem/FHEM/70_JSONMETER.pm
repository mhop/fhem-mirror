###############################################################
# $Id$
#
#  70_JSONMETER.pm
#
#  Copyright notice
#
#  (c) 2014 Torsten Poitzsch < torsten . poitzsch at gmx . de >
#
#  This module reads data from devices that provide OBIS compatible data
#  in json format (e.g. power meters)
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the text file GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
#
##############################################################################
#
# define <name> JSONMETER <type> <host> [interval]
#
# If <interval> is positive, new values are read every <interval> seconds.
# The default for <interval> is 300 (i.e. 5 minutes).
#
##############################################################################

package main;

use strict;
use warnings;
use Blocking;
use IO::Socket::INET;
use MIME::Base64;

sub JSONMETER_Initialize($);
sub JSONMETER_Define($$);
sub JSONMETER_Undefine($$);
sub JSONMETER_Attr($@);
sub JSONMETER_Set($$@);
sub JSONMETER_Get($@);
sub JSONMETER_GetUpdate($);
sub JSONMETER_GetJsonFile($);
sub JSONMETER_ReadFromUrl($);
sub JSONMETER_ReadFromFile($);
sub JSONMETER_ParseJsonFile($);
sub JSONMETER_UpdateAborted($);
sub JSONMETER_doStatisticMinMax ($$$); 
sub JSONMETER_doStatisticMinMaxSingle ($$$$);
sub JSONMETER_doStatisticDelta ($$$$$);
sub JSONMETER_doStatisticDeltaSingle ($$$$$$);
# Modul Version for remote debugging
  my $modulVersion = "2014-04-29";

 ##############################################################
 # Syntax: meterType => port URL-Path
 ##############################################################
  my %meterTypes = ( ITF => "80 GetMeasuredValue.cgi" 
                    ,EFR => "80 json.txt"
                  ,LS110 => "80 a?f=j"
                  );

 ##############################################################
 # Syntax: valueType, code, FHEM reading name, statisticType, tariffType
 #     valueType: 1=OBISvalue | 2=OBISvalueString | 3=jsonProperty | 4=jsonPropertyTime
 #     statisticType: 0=noStatistic | 1=maxMinStatistic | 2=integralTimeStatistic | 3=State+IntegralTimeStatistic
 #     tariffType: 0 = tariff cannot be selected, 1 = tariff can be selected via reading "activeTariff"
 ##############################################################
  my @jsonFields = (
    [3, "meterType", "meterType", 0, 0] # {"meterId": "0000000061015736", "meterType": "Simplex", "interval": 0, "entry": [
   ,[4, "timestamp", "deviceTime", 0, 0] # {"timestamp": 1389296286, "periodEntries": [
   ,[3, "cnt", "electricityConsumed", 3, 1] # {"cnt":" 22,285","pwr":764,"lvl":0,"dev":"","det":"","con":"OK","sts":"(06)","raw":0}
   ,[3, "pwr", "electricityPower", 1, 0] # {"cnt":" 22,285","pwr":764,"lvl":0,"dev":"","det":"","con":"OK","sts":"(06)","raw":0}
   ,[1, "010000090B00", "deviceTime", 0, 0] #   { "obis":"010000090B00","value":"dd.mm.yyyy,hh:mm"}
   ,[2, "0.0.0", "meterID", 0, 0] # {"obis": "0.0.0", "scale": 0, "value": 1627477814, "unit": "", "valueString": "0000000061015736" }, 
   ,[1, "0100000000FF", "meterID", 0, 0] #  #   { "obis":"0100000000FF","value":"xxxxx"},
   ,[2, "0.2.0", "firmware", 0, 0] # {"obis": "0.2.0", "scale": 0, "value": 0, "unit": "", "valueString": "V320090704" }, 
   ,[1, "1.7.0|0100010700FF", "electricityPower", 1, 0]  # {"obis": "1.7.0", "scale": 0, "value": 392, "unit": "W", "valueString": "0000392" }, 
   ,[1, "0100150700FF", "electricityPowerPhase1", 1, 0] # {"obis":"0100150700FF","value":209.40,"unit":"W"},
   ,[1, "0100290700FF", "electricityPowerPhase2", 1, 0] # {"obis":"0100290700FF","value":14.27,"unit":"W"},
   ,[1, "01003D0700FF", "electricityPowerPhase3", 1, 0] # {"obis":"01003D0700FF","value":89.40,"unit":"W"},
   ,[1, "1.8.0|0101010800FF", "electricityConsumed", 3, 1] # {"obis": "1.8.0", "scale": 0, "value": 8802276, "unit": "Wh", "valueString": "0008802.276" }, 
   ,[1, "1.8.1|0101010801FF", "electricityConsumedTariff1", 2, 0] # {"obis":"0101010801FF","value":33.53,"unit":"kWh"},               
   ,[1, "1.8.2|0101010802FF", "electricityConsumedTariff2", 2, 0] # {"obis":"0101010802FF","value":33.53,"unit":"kWh"},               
   ,[1, "1.8.3|0101010803FF", "electricityConsumedTariff3", 2, 0] # {"obis":"0101010803FF","value":33.53,"unit":"kWh"},               
   ,[1, "1.8.4|0101010804FF", "electricityConsumedTariff4", 2, 0] # {"obis":"0101010804FF","value":33.53,"unit":"kWh"},               
   ,[1, "1.8.5|0101010805FF", "electricityConsumedTariff5", 2, 0] # {"obis":"0101010805FF","value":33.53,"unit":"kWh"},               
   ,[1, "010001080080", "electricityConsumedToday", 0, 0] 
   ,[1, "010001080081", "electricityConsumedYesterday", 0, 0] 
   ,[1, "010001080082", "electricityConsumedLastWeek", 0, 0] 
   ,[1, "010001080083", "electricityConsumedLastMonth", 0, 0] 
   ,[1, "010001080084", "electricityConsumedLastYear", 0, 0] 
   ,[1, "010002080080", "electricityProducedToday", 0, 0] 
   ,[1, "010002080081", "electricityProducedYesterday", 0, 0] 
   ,[1, "010002080082", "electricityProducedLastWeek", 0, 0] 
   ,[1, "010002080083", "electricityProducedLastMonth", 0, 0] 
   ,[1, "010002080084", "electricityProducedLastYear", 0, 0] 
   ,[1, "0101020800FF", "electricityPowerOutput", 1, 0]
   ,[1, "010020070000", "electricityVoltagePhase1", 1, 0] #{"obis":"010020070000","value":237.06,"unit":"V"},               
   ,[1, "010034070000", "electricityVoltagePhase2", 1, 0] # {"obis":"010034070000","value":236.28,"unit":"V"},               
   ,[1, "010048070000", "electricityVoltagePhase3", 1, 0] # {"obis":"010048070000","value":236.90,"unit":"V"},
   ,[1, "01000E070000", "electricityFrequency", 1, 0] # {"obis":"01000E070000","value":49.950,"unit":"Hz"}
   );
  ##############################################################


sub ##########################################
JSONMETER_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "JSONMETER_Define";
  $hash->{UndefFn}  = "JSONMETER_Undefine";

  $hash->{SetFn}    = "JSONMETER_Set";
  $hash->{GetFn}    = "JSONMETER_Get";
  $hash->{AttrFn}   = "JSONMETER_Attr";
  $hash->{AttrList} = "disable:0,1 "
                ."doStatistics:0,1 "
                ."pathString "
                ."port "
                ."alwaysAnalyse:0,1 "
                .$readingFnAttributes;

} # end JSONMETER_Initialize


sub ##########################################
JSONMETER_Define($$)
{
  my ($hash, $def) = @_;
  my @args = split("[ \t][ \t]*", $def);

  return "Usage: define <name> JSONMETER <deviceType> <host> [interval]" if(@args <3 || @args >5);

  my $name = $args[0];
  my $type = $args[2];
  my $interval = 5*60;
  my $host;
  my $typeStr;
  if ($type eq "file") 
  {
   return "Usage: define <name> JSONMETER url [interval]" if (@args >4);
     $interval = $args[3] if(int(@args) == 4);
  } else {
     return "Usage: define <name> JSONMETER <deviceType> <host> [interval]" if(@args <4);
     $host = $args[3];
     $interval = $args[4] if(int(@args) == 5);
  }
  $interval = 10 if( $interval < 10 && $interval != 0);



  if ($type ne "url" && $type ne "file") {
   $typeStr = $meterTypes{$type};
    return "Unknown type '$type': use url|file|". join ("|", keys(%meterTypes)) unless $typeStr;
    my @typeAttr = split / /, $typeStr; 
    $hash->{PORT}      = $typeAttr[0];
    $hash->{urlPath}   = $typeAttr[1];
  }

  $hash->{NAME} = $name;

  $hash->{STATE}      = "Initializing" if $interval > 0;
  $hash->{STATE}      = "Manual mode" if $interval == 0;
  $hash->{HOST}       = $host if $type ne "file";
  $hash->{INTERVAL}   = $interval;
  $hash->{NOTIFYDEV}  = "global";
  $hash->{deviceType} = $type;

  RemoveInternalTimer($hash);
  #Get first data after 13 seconds
  InternalTimer(gettimeofday() + 13, "JSONMETER_GetUpdate", $hash, 0) if $interval > 0;

  #Reset temporary values
  $hash->{fhem}{jsonInterpreter} = "";

  $hash->{fhem}{modulVersion} = $modulVersion;
  Log3 $hash,5,"$name: JSONMETER.pm version is $modulVersion.";
 
 return undef;
} #end JSONMETER_Define


sub ##########################################
JSONMETER_Undefine($$)
{
  my ($hash, $args) = @_;

  RemoveInternalTimer($hash);

  BlockingKill($hash->{helper}{RUNNING_PID}) if(defined($hash->{helper}{RUNNING_PID}));

  return undef;
} # end JSONMETER_Undefine


sub ##########################################
JSONMETER_Attr($@)
{
   my ($cmd,$name,$aName,$aVal) = @_;
     # $cmd can be "del" or "set"
   # $name is device name
   # aName and aVal are Attribute name and value
   if ($cmd eq "set") {
      if ($aName eq "1allowSetParameter") {
         eval { qr/$aVal/ };
         if ($@) {
            Log3 $name, 3, "JSONMETER: Invalid allowSetParameter in attr $name $aName $aVal: $@";
            return "Invalid allowSetParameter $aVal";
         }
      }
   }
   
   return undef;
} # JSONMETER_Attr ende


sub ##########################################
JSONMETER_Set($$@) 
{
  my ($hash, $name, $cmd, $val) = @_;
  my $resultStr = "";
   
  if($cmd eq 'statusRequest') {
    $hash->{LOCAL} = 1;
    JSONMETER_GetUpdate($hash);
    $hash->{LOCAL} = 0;
    return undef;
  }
   elsif($cmd eq 'restartJsonAnalysis') {
      $hash->{fhem}{jsonInterpreter} = "";
      $hash->{LOCAL} = 1;
      JSONMETER_GetUpdate($hash);
      $hash->{LOCAL} = 0;
      return undef;
   }
   elsif ($cmd eq 'resetStatistics') {
      if ($val =~ /all|statElectricityConsumed\.\.\.|statElectricityConsumedTariff\.\.\.|statElectricityPower\.\.\./) {
         my $regExp;
         if ($val eq "all") { $regExp = "stat"; } 
         else { $regExp = substr $val, 0, -3; } 
         foreach (sort keys %{ $hash->{READINGS} }) {
            if ($_ =~ /^\.?$regExp/ && $_ ne "state") {
               delete $hash->{READINGS}{$_};
               $resultStr .= " " . $_;
            }
         }
      }
      WriteStatefile();
      return $resultStr;
   }
   elsif($cmd eq 'INTERVAL' && int(@_)==4 ) {
      $val = 10 if( $val < 10 );
      $hash->{INTERVAL}=$val;
      return "$name: Polling interval set to $val seconds.";
   }
   elsif($cmd eq 'activeTariff' && int(@_)==4 ) {
      $val = 0 if( $val < 1 || $val > 9 );
      readingsSingleUpdate($hash,"activeTariff",$val, 1);
      return "$name: activeTariff set to $val.";
   }
   my $list = "statusRequest:noArg"
         ." activeTariff:0,1,2,3,4,5,6,7,8,9"
         ." resetStatistics:all,statElectricityConsumed...,statElectricityConsumedTariff...,statElectricityPower..."
         ." restartJsonAnalysis:noArg"
         ." INTERVAL:slider,0,10,600";
   return "Unknown argument $cmd, choose one of $list";

} # end JSONMETER_Set


sub ##########################################
JSONMETER_Get($@)
{
  my ($hash, $name, $cmd) = @_;
  my $result;
  my $message;
  
   if ($cmd eq "jsonFile") {
      $result = JSONMETER_GetJsonFile $name;
      my @a = split /\|/, $result;
      if ($a[1]==0) { 
         return $a[2]; 
      } else {
         return decode_base64($a[2]);
      }
      
  } elsif ($cmd eq "jsonAnalysis") {
      $hash->{fhem}{jsonInterpreter} = "";
      $result = JSONMETER_GetJsonFile $name;
      my @a = split /\|/, $result;
      if ($a[1]==0) { return $a[2]; }
      
      $result = JSONMETER_ParseJsonFile $result;
      # my @a = split /\|/, $result;
      $message = decode_base64($result); #$a[2]);
      return $message;
  }
  
  my $list = "jsonFile:noArg"
            ." jsonAnalysis:noArg";
  return "Unknown argument $cmd, choose one of $list";

} # end JSONMETER_Get


sub ##########################################
JSONMETER_GetUpdate($)
{
   my ($hash) = @_;
   my $name = $hash->{NAME};
   my $type = $hash->{deviceType};
   
   
   if(!$hash->{LOCAL} && $hash->{INTERVAL} > 0) {
      RemoveInternalTimer($hash);
      InternalTimer(gettimeofday()+$hash->{INTERVAL}, "JSONMETER_GetUpdate", $hash, 1);
      return undef if( AttrVal($name, "disable", 0 ) == 1 );
   }

   
   if ( ( $type eq "url" || $type eq "file" ) && ! defined($attr{$name}{"pathString"}) )  
   {
      Log3 $name,2,"$name - Error reading device: Please define the attribute 'pathString'";
      $hash->{STATE} = "pathString missing";
      return "$name|0|Error reading device: Please define the attribute 'pathString'.";
   }
   
   $hash->{helper}{RUNNING_PID} = BlockingCall("JSONMETER_GetJsonFile", $name, 
                                          "JSONMETER_ParseJsonFile", 10,
                                          "JSONMETER_UpdateAborted", $hash) 
                                unless(exists($hash->{helper}{RUNNING_PID}));
}


sub ##########################################
JSONMETER_GetJsonFile ($)
{
    my ($name) = @_;
    my $returnStr;
     my $hash = $defs{$name};
    my $type = $hash->{deviceType};
    my $ip = "";
    $ip = $hash->{HOST} if defined $hash->{HOST};
    
    my $urlPath = "";
    $urlPath = $hash->{urlPath} if defined $hash->{urlPath};
 
    if (($type eq "url" || $type eq "file") && ! defined($attr{$name}{"pathString"}))
         {return "$name|0|Error: deviceType is '$type' - Please define the attribute 'pathString' first.";}

    my $pathString = "";
    $pathString = $attr{$name}{"pathString"} if defined($attr{$name}{"pathString"});
   
    my $port = 80;
    $port = $hash->{PORT} if defined $hash->{PORT};
    $port = $attr{$name}{"port"} if $type eq "url" && defined($attr{$name}{"port"});
    $hash->{PORT} = $port if $type ne "file";
    
    
    if ( $type eq "file") 
    {
      $returnStr = JSONMETER_ReadFromFile $name."|".$pathString;
    } 
    else 
    { 
      $returnStr = JSONMETER_ReadFromUrl $name."|".$ip."|".$port."|".$urlPath.$pathString;
    } 
    return $returnStr;
}

sub ##########################################
JSONMETER_ReadFromFile($)
{
    my ($string) = @_;
    my ($name, $pathString) = split /\|/, $string; 

    Log3 $name, 4, "$name: Open file '$pathString'";
    if (open(IN, "<" . $pathString)) {
      my $message = join " ", <IN>;
      close(IN);
      Log3 $name, 4, "$name: Close file";
      $message = encode_base64($message,"");
      return "$name|1|$message" ;
    } else {
      Log3 $name, 2, "$name Error: Cannot open file $pathString: $!";
      return "$name|0|Error: Cannot open file $pathString: $!";;
    }
} # end JSONMETER_ReadFromFile


sub ##########################################
JSONMETER_ReadFromUrl($)
{
 
 my ($string) = @_;
 my ($name, $ip, $port, $pathString) = split /\|/, $string; 
 
 my $buf ;
 my $message ;

   Log3 $name, 4, "$name: opening socket to host $ip port $port" ; 

   my $socket = new IO::Socket::INET (
           PeerAddr => $ip,
           PeerPort => $port,
           Proto    => 'tcp',
           Reuse    => 0,
           Timeout  => 9
         );
   if (!$socket) {
     Log3 $name, 1, "$name Error: Could not open connection to ip $ip port $port";
     return "$name|0|Can't connect to ip $ip port $port";
   }

   if (defined ($socket) and $socket and $socket->connected()) 
   {
      print $socket "GET /$pathString HTTP/1.0\r\n\r\n";
      Log3 $name, 4, "$name: Get json file from http://$ip:$port/$pathString";
      $socket->autoflush(1);
      while ((read $socket, $buf, 1024) > 0)
      {
         $message .= $buf;
      }
      Log3 $name, 5, "$name: received:\n $message";
      $socket->close();
      Log3 $name, 4, "$name: Socket closed";
      if ($message =~ /^HTTP\/1.\d 404 Not Found/) {
           return "$name|0|Error: URL 'http://$ip:$port/$pathString' returned 'Error 404: Page Not Found'";
      }

      $message = encode_base64($message,"");

      return "$name|1|$message" ;
   }

} # end JSONMETER_ReadFromUrl


sub ###########################
JSONMETER_ParseJsonFile($)
{
  my ($string) = @_;
  return unless(defined($string));
  my (@a) = split("\\|", $string);
  my $hash = $defs{$a[0]};
  my $name = $hash->{NAME};
  my $value;
  my $returnStr ="";
  my $statisticType;
  
  delete($hash->{helper}{RUNNING_PID});


if ( $a[1] == 1 ){
   my $message = decode_base64($a[2]);

   readingsBeginUpdate($hash);

    my @fields=split(/\{/,$message); # JSON in einzelne Felder zerlegen
   
    my $jsonInterpreter =  $hash->{fhem}{jsonInterpreter} || "";
    my $alwaysAnalyse = $attr{$name}{alwaysAnalyse} || 0;
    $returnStr .= "================= Find JSON property ==================\n\n";

    ####################################
  # ANALYSE once: Find all known obis codes in the first run and store in the item no, 
  # value type and reading name in the jsonInterpreter
  ####################################
    if ( $jsonInterpreter eq "" || $alwaysAnalyse == 1 ) {
      Log3 $name, 3, "$name: Analyse JSON pathString for known readings" if $alwaysAnalyse != 1;
      Log3 $name, 4, "$name: Analyse JSON pathString for known readings" if $alwaysAnalyse == 1;
      foreach my $f (@jsonFields) 
      {
         for(my $i=0; $i<=$#fields; $i++) 
         {
            # if ($$f[0] =~ /^[15]$/) { 
            if ($$f[0] == 1) { 
               if ($fields[$i] =~ /"obis"\s*:\s*"($$f[1])"\s*[,}]/ && $fields[$i] =~ /"value"/) {
                  $jsonInterpreter .= "|$i $$f[0] $$f[2] $$f[3] $$f[4]";
                  Log3 $name,4,"$name: OBIS code \"$$f[1]\" will be stored in $$f[2]";
                  $returnStr .= "OBIS code \"$$f[1]\" will be extracted as reading '$$f[2]' (statistic type: $$f[3]) from part $i:\n$fields[$i]\n\n";
               }
            } elsif ($$f[0] == 2) { 
               if ($fields[$i] =~ /"obis"\s*:\s*"($$f[1])"\s*[,}]/ && $fields[$i] =~ /"valueString"/) {
                  $jsonInterpreter .= "|$i $$f[0] $$f[2] $$f[3] $$f[4]";
                  Log3 $name,4,"$name: OBIS code \"$$f[1]\" will be stored in $$f[2]";
                  $returnStr .= "OBIS code \"$$f[1]\" will be extracted as reading '$$f[2]' (statistic type: $$f[3]) from part $i:\n$fields[$i]\n\n";
               }
            } elsif ($$f[0] == 3) { 
               if ($fields[$i] =~ /"($$f[1])"\s*:/) {
                  $jsonInterpreter .= "|$i $$f[0] $$f[2] $$f[3] $$f[4] $$f[1]";
                  Log3 $name,4,"$name: Property \"$$f[1]\" will be stored in $$f[2]";
                  $returnStr .= "Property \"$$f[1]\" will be extracted as reading '$$f[2]' (statistic type: $$f[3]) from part $i:\n$fields[$i]\n\n";
              }
            } elsif ($$f[0] == 4) { 
               if ($fields[$i] =~ /"($$f[1])"\s*:/) {
                  $jsonInterpreter .= "|$i $$f[0] $$f[2] $$f[3] $$f[4] $$f[1]";
                  Log3 $name,4,"$name: Property \"$$f[1]\" will be stored in $$f[2]";
                  $returnStr .= "Property \"$$f[1]\" will be extracted as reading '$$f[2]' (statistic type: $$f[3]) from part $i:\n$fields[$i]\n\n";
               }
            # } elsif ($$f[0] == 6) { 
               # if ($fields[$i] =~ /"($$f[1])"\s*:/) {
                  # $jsonInterpreter .= "|$i $$f[0] $$f[2] $$f[3] $$f[4] $$f[1]";
                  # Log3 $name,4,"$name: Property \"$$f[1]\" will be stored in $$f[2]";
                  # $returnStr .= "Property \"$$f[1]\" will be extracted as reading '$$f[2]' (statistic type: $$f[3]) from part $i:\n$fields[$i]\n\n";
               # }
            }   
         }
      }
      if ($jsonInterpreter ne "") {
         Log3 $name, 3, "$name: Store results of JSON analysis for next device readings" if $alwaysAnalyse != 1;
         $jsonInterpreter = substr $jsonInterpreter, 1;
         $hash->{fhem}{jsonInterpreter} = $jsonInterpreter;
      } else {
         Log3 $name, 2, "$name: Could not interpret the JSON file => please contact FHEM community" if $jsonInterpreter eq "";
      }
   } else {
      $jsonInterpreter = $hash->{fhem}{jsonInterpreter} if exists $hash->{fhem}{jsonInterpreter};
   }
   
  ####################################
  # INTERPRETE AND STORE
  # use the previously filled jsonInterpreter to extract the correct values
  ####################################
  
  $returnStr .= "\n================= Extract JSON values ==================\n\n";

  my @a = split /\|/, $jsonInterpreter;
   Log3 $name, 4, "$name: Extract ".($#a+1)." readings from ".($#fields+1)." json parts";
   foreach (@a) {
      $statisticType = 0;
      Log3 $name, 5, "$name: Handle $_";
      my @b = split / /, $_ ;
    #obis value
      if ($b[1] == 1) { 
         if ($fields[$b[0]] =~ /"value"\s*:\s*"(.*?)"\s*[,\}]/g || $fields[$b[0]] =~ /"value"\s*:\s*(.*?)\s*[,\}]/g) {
            $value = $1;
            # $value =~ s/^\s+|\s+$//g;
            Log3 $name, 4, "$name: Value $value for reading $b[2] extracted from '$fields[$b[0]]'";
            $returnStr .= "Value \"$value\" for reading '$b[2]' extracted from part $b[0]:\n$fields[$b[0]]\n\n";
            readingsBulkUpdate($hash,$b[2],$value);
            $statisticType = $b[3];
         } else {
            Log3 $name, 4, "$name: Could not extract value for reading $b[2] from '$fields[$b[0]]'";
            $returnStr .= "Could not extract value for reading '$b[2]' from part $b[0]:\n$fields[$b[0]]\n\n";
         }
    #obis valueString
      } elsif ($b[1] == 2) { 
         if ($fields[$b[0]] =~ /"valueString"\s*:\s*"(.*?)"\s*[,}]/g ) {
            $value = $1;
            Log3 $name, 4, "$name: Value $value for reading $b[2] extracted from '$fields[$b[0]]'";
            $returnStr .= "Value \"$value\" for reading '$b[2]' extracted from part $b[0]:\n$fields[$b[0]]\n\n";
            readingsBulkUpdate($hash,$b[2],$value); 
            $statisticType = $b[3];
         } else {
            Log3 $name, 4, "$name: Could not extract value for reading $b[2] from '$fields[$b[0]]'";
            $returnStr .= "Could not extract value for reading '$b[2]' from part $b[0]:\n$fields[$b[0]]\n\n";
         }
    # JSON-Property
      } elsif ($b[1] == 3) { 
         if ($fields[$b[0]] =~ /"$b[5]"\s*:\s*"(.*?)"\s*[,}]/g || $fields[$b[0]] =~ /"$b[5]"\s*:\s*(.*?)\s*[,}]/g ) {
            $value = $1;
            $value =~ /^ *\d+(,\d\d\d)+/ && $value =~ s/,| //g;
            Log3 $name, 4, "$name: Value $value for reading $b[2] extracted from '$fields[$b[0]]'";
            $returnStr .= "Value \"$value\" for reading '$b[2]' extracted from part $b[0]:\n$fields[$b[0]]\n\n";
            readingsBulkUpdate($hash, $b[2], $value); 
            $statisticType = $b[3];
         } else {
            Log3 $name, 4, "$name: Could not extract value for reading $b[2] from '$fields[$b[0]]'";
            $returnStr .= "Could not extract value for reading '$b[2]' from part $b[0]:\n$fields[$b[0]]\n\n";
         }
    # JSON-Property Time
      } elsif ($b[1] == 4) {  
         if ($fields[$b[0]] =~ /"$b[5]"\s*:\s"?(\d*)"?\s*[,}]/g ) {
            $value = $1;
            Log3 $name, 4, "$name: Value $value for reading $b[2] extracted from '$fields[$b[0]]'";
            $returnStr .= "Value \"$value\" for reading '$b[2]' extracted from part $b[0]:\n$fields[$b[0]]\n\n";
            $value =  strftime "%Y-%m-%d %H:%M:%S", localtime($value);
            readingsBulkUpdate($hash, $b[2], $value); 
            $statisticType = $b[3];
         } else {
            Log3 $name, 4, "$name: Could not extract value for reading $b[2] from '$fields[$b[0]]'";
            $returnStr .= "Could not extract value for reading '$b[2]' from part $b[0]:\n$fields[$b[0]]\n\n";
         }
      }
     
      if ( AttrVal($name,"doStatistics",0) == 1) { 
         my $activeTariff = ReadingsVal($name,"activeTariff",0);
         if ($b[4] == 0) { $activeTariff = 0;}
         # JSONMETER_doStatisticMinMax $hash, $readingName, $value
         if ($statisticType == 1 ) { JSONMETER_doStatisticMinMax $hash, "stat".ucfirst($b[2]), $value ; }
         # JSONMETER_doStatisticDelta: $hash, $readingName, $value, $special, $activeTariff
         if ($statisticType == 2 ) { JSONMETER_doStatisticDelta $hash, "stat".ucfirst($b[2]), $value, 0, $activeTariff ; }
         # JSONMETER_doStatisticDelta: $hash, $readingName, $value, $special, $activeTariff
         if ($statisticType == 3 ) { JSONMETER_doStatisticDelta $hash, "stat".ucfirst($b[2]), $value, 1, $activeTariff ; }
      }
    }

    readingsBulkUpdate($hash,"state","Connected");
    readingsEndUpdate($hash,1);
    DoTrigger($hash->{NAME}, undef) if ($init_done);
 
  } else {
   readingsSingleUpdate($hash,"state",$a[2],1);
  }

  return encode_base64($returnStr);
}

sub ############################
JSONMETER_UpdateAborted($)
{
  my ($hash) = @_;
  delete($hash->{helper}{RUNNING_PID});
  my $name = $hash->{NAME};
  my $host = $hash->{HOST};
  Log3 $hash, 1, "$name Error: Timeout when connecting to host $host";

} # end JSONMETER_UpdateAborted

# Calculates single MaxMin Values and informs about end of day and month
sub ######################################## 
JSONMETER_doStatisticMinMax ($$$) 
{
   my ($hash, $readingName, $value) = @_;
   my $dummy;

   my $lastReading;
   my $lastSums;
   my @newReading;
   
   my $yearLast;
   my $monthLast;
   my $dayLast;
   my $dayNow;
   my $monthNow;
   my $yearNow;
   
  # Determine date of last and current reading
   if (exists($hash->{READINGS}{$readingName."Day"}{TIME})) {
      ($yearLast, $monthLast, $dayLast) = $hash->{READINGS}{$readingName."Day"}{TIME} =~ /^(\d\d\d\d)-(\d\d)-(\d\d)/;
   } else {
      ($dummy, $dummy, $dummy, $dayLast, $monthLast, $yearLast) = localtime;
      $yearLast += 1900;
      $monthLast ++;
   }
   ($dummy, $dummy, $dummy, $dayNow, $monthNow, $yearNow) = localtime;
   $yearNow += 1900;
   $monthNow ++;

  # Daily Statistic
   #JSONMETER_doStatisticMinMaxSingle: $hash, $readingName, $value, $saveLast
   JSONMETER_doStatisticMinMaxSingle $hash, $readingName."Day", $value, ($dayNow != $dayLast);
   
  # Monthly Statistic 
   #JSONMETER_doStatisticMinMaxSingle: $hash, $readingName, $value, $saveLast
   JSONMETER_doStatisticMinMaxSingle $hash, $readingName."Month", $value, ($monthNow != $monthLast);
    
  # Yearly Statistic 
   #JSONMETER_doStatisticMinMaxSingle: $hash, $readingName, $value, $saveLast
   JSONMETER_doStatisticMinMaxSingle $hash, $readingName."Year", $value, ($yearNow != $yearLast);

   return ;

}

# Calculates single MaxMin Values and informs about end of day and month
sub ######################################## 
JSONMETER_doStatisticMinMaxSingle ($$$$) 
{
   my ($hash, $readingName, $value, $saveLast) = @_;
   my $result;
   
   my $lastReading = $hash->{READINGS}{$readingName}{VAL} || "";
   
 # Initializing
   if ( $lastReading eq "" ) { 
      my $since = strftime "%Y-%m-%d_%H:%M:%S", localtime(); 
      $result = "Count: 1 Sum: $value ShowDate: 1";
      readingsBulkUpdate($hash, ".".$readingName, $result);
      $result = "Min: $value Avg: $value Max: $value (since: $since )";
      readingsBulkUpdate($hash, $readingName, $result);

 # Calculations
   } else { 
      my @a = split / /, $hash->{READINGS}{"." . $readingName}{VAL}; # Internal values
      my @b = split / /, $lastReading;
    # Do calculations
      $a[1]++; # Count
      $a[3] += $value; # Sum
      if ($value < $b[1]) { $b[1]=$value; } # Min
      if ($a[1]>0) {$b[3] = sprintf "%.0f" , $a[3] / $a[1];} # Avg
      if ($value > $b[5]) { $b[5]=$value; } # Max

    # in case of period change, save "last" values and reset counters
      if ($saveLast) {
         $result = "Min: $b[1] Avg: $b[3] Max: $b[5]";
         if ($a[5] == 1) { $result .= " (since: $b[7] )"; }
         readingsBulkUpdate($hash, $readingName . "Last", $lastReading);
         $a[1] = 1;   $a[3] = $value;   $a[5] = 0;
         $b[1] = $value;   $b[3] = $value;   $b[5] = $value;
      }
    # Store internal calculation values
      $result = "Count: $a[1] Sum: $a[3] ShowDate: $a[5]";  
      readingsBulkUpdate($hash, ".".$readingName, $result);
    # Store visible Reading
      $result = "Min: $b[1] Avg: $b[3] Max: $b[5]";  
      if ($a[5] == 1) { $result .= " (since: $b[7] )"; }
      readingsBulkUpdate($hash, $readingName, $result);
   }
   return;
}


# Calculates deltas for day, month and year
sub ######################################## 
JSONMETER_doStatisticDelta ($$$$$) 
{
   my ($hash, $readingName, $value, $special, $activeTariff) = @_;
   my $dummy;
   my $result;
   
   my $deltaValue;
   my $previousTariff; 
   my $showDate;
   
 # Determine if time period switched (day, month, year)
 # Get deltaValue and Tariff of previous call
   my $periodSwitch = 0;
   my $yearLast; my $monthLast; my $dayLast; my $hourLast;  my $hourNow; my $dayNow; my $monthNow; my $yearNow;
   if (exists($hash->{READINGS}{"." . $readingName . "Before"})) {
      ($yearLast, $monthLast, $dayLast, $hourLast) = ($hash->{READINGS}{"." . $readingName . "Before"}{TIME} =~ /^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d)/);
      $yearLast -= 1900;
      $monthLast --;
      ($dummy, $deltaValue, $dummy, $previousTariff, $dummy, $showDate) = split / /,  $hash->{READINGS}{"." . $readingName . "Before"}{VAL} || "";
      $deltaValue = $value - $deltaValue;
   } else {
      ($dummy, $dummy, $hourLast, $dayLast, $monthLast, $yearLast) = localtime;
      $deltaValue = 0;
      $previousTariff = 0; 
      $showDate = 8;
   }
   ($dummy, $dummy, $hourNow, $dayNow, $monthNow, $yearNow) = localtime;

   if ($yearNow != $yearLast) { $periodSwitch = 4; }
   elsif ($monthNow != $monthLast) { $periodSwitch = 3; }
   elsif ($dayNow != $dayLast) { $periodSwitch = 2; }
   elsif ($hourNow != $hourLast) { $periodSwitch = 1; }

   # Determine if "since" value has to be shown in current and last reading
   if ($periodSwitch == 4) {
      if ($showDate == 1) { $showDate = 0; } # Do not show the "since:" value for year changes anymore
      if ($showDate >= 2) { $showDate = 1; } # Shows the "since:" value for the first year change
   }
   if ($periodSwitch >= 3){
      if ($showDate == 3) { $showDate = 2; } # Do not show the "since:" value for month changes anymore
      if ($showDate >= 4) { $showDate = 3; } # Shows the "since:" value for the first month change
   }
   if ($periodSwitch >= 2){
      if ($showDate == 5) { $showDate = 4; } # Do not show the "since:" value for day changes anymore
      if ($showDate >= 6) { $showDate = 5; } # Shows the "since:" value for the first day change
   }
   if ($periodSwitch >= 1){
      if ($showDate == 7) { $showDate = 6; } # Do not show the "since:" value for day changes anymore
      if ($showDate >= 8) { $showDate = 7; } # Shows the "since:" value for the first hour change
   }

 # JSONMETER_doStatisticDeltaSingle; $hash, $readingName, $deltaValue, $special, $periodSwitch, $showDate, $firstCall
   JSONMETER_doStatisticDeltaSingle ($hash, $readingName, $deltaValue, $special, $periodSwitch, $showDate);

   foreach (1,2,3,4,5,6,7,8,9) {
      if ( $previousTariff == $_ ) {
         JSONMETER_doStatisticDeltaSingle ($hash, $readingName."Tariff".$_, $deltaValue, 0, $periodSwitch, $showDate);
      } elsif ($activeTariff == $_ || ($periodSwitch > 0 && exists($hash->{READINGS}{$readingName . "Tariff".$_}))) {
         JSONMETER_doStatisticDeltaSingle ($hash, $readingName."Tariff".$_, 0, 0 , $periodSwitch, $showDate);
      }
   }
      
   # Hidden storage of current values for next call(before values)
   $result = "Value: $value Tariff: $activeTariff ShowDate: $showDate ";  
   readingsBulkUpdate($hash, ".".$readingName."Before", $result);

   return ;
}

sub ######################################## 
JSONMETER_doStatisticDeltaSingle ($$$$$$) 
{
   my ($hash, $readingName, $deltaValue, $special, $periodSwitch, $showDate) = @_;
   my $dummy;
   my $result; 

 # get existing statistic reading
   my @curr;
   if (exists($hash->{READINGS}{$readingName}{VAL})) {
      @curr = split / /, $hash->{READINGS}{$readingName}{VAL} || "";
      if ($curr[0] eq "Day:") { $curr[9]=$curr[7]; $curr[7]=$curr[5]; $curr[5]=$curr[3]; $curr[3]=$curr[1]; $curr[1]=0; }
   } else {
      $curr[1] = 0; $curr[3] = 0;  $curr[5] = 0; $curr[7] = 0;
      $curr[9] = strftime "%Y-%m-%d_%H:%M:%S", localtime(); # start
   }
   
 # get statistic values of previous period
   my @last;
   if (exists ($hash->{READINGS}{$readingName."Last"})) { 
      @last = split / /,  $hash->{READINGS}{$readingName."Last"}{VAL};
      if ($last[0] eq "Day:") { $last[9]=$last[7]; $last[7]=$last[5]; $last[5]=$last[3]; $last[3]=$last[1]; $last[1]="-"; }
   } else {
      @last = split / /,  "Hour: - Day: - Month: - Year: -";
   }
   
 # Do statistic
   $curr[1] += $deltaValue;
   $curr[3] += $deltaValue;
   $curr[5] += $deltaValue;
   $curr[7] += $deltaValue;

 # If change of year, change yearly statistic
   if ($periodSwitch == 4){
      $last[7] = $curr[7];
      $curr[7] = 0;
      if ($showDate == 1) { $last[9] = $curr[9]; }
   }

 # If change of month, change monthly statistic 
   if ($periodSwitch >= 3){
      $last[5] = $curr[5];
      $curr[5] = 0;
      if ($showDate == 3) { $last[9] = $curr[9];}
   }

 # If change of day, change daily statistic
   if ($periodSwitch >= 2){
      $last[3] = $curr[3];
      $curr[3] = 0;
      if ($showDate == 5) {
         $last[9] = $curr[9];
        # Next monthly and yearly values start at 00:00 and show only date (no time)
         $curr[5] = 0;
         $curr[7] = 0;
         $curr[9] = strftime "%Y-%m-%d", localtime(); # start
      }
   }

 # If change of hour, change hourly statistic 
   if ($periodSwitch >= 1){
      $last[1] = $curr[1];
      $curr[1] = 0;
      if ($showDate == 7) { $last[9] = $curr[9];}
   }

 # Store visible statistic readings (delta values)
   $result = "Hour: $curr[1] Day: $curr[3] Month: $curr[5] Year: $curr[7]";
   if ( $showDate >=2 ) { $result .= " (since: $curr[9] )"; }
   readingsBulkUpdate($hash,$readingName,$result);
   
   if ($special == 1) { readingsBulkUpdate($hash,$readingName."Today",$curr[3]) };

 # if changed, store previous visible statistic (delta) values
   if ($periodSwitch >= 1) {
      $result = "Hour: $last[1] Day: $last[3] Month: $last[5] Year: $last[7]";
      if ( $showDate =~ /1|3|5|7/ ) { $result .= " (since: $last[9] )";}
      readingsBulkUpdate($hash,$readingName."Last",$result); 
   }
}

1;

=pod
=begin html

<a name="JSONMETER"></a>
<h3>JSONMETER</h3>
<ul>
  This module reads data from a measurement unit (so called smart meters for electricity, gas or heat)
  <br>
  that provides OBIS compliant data in JSON format on a webserver or on the FHEM file system.
  <br>
  It assumes normally, that the structur of the JSON data do not change.
  <br>
  &nbsp;
  <br>
  
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; JSONMETER &lt;deviceType&gt; [&lt;ip address&gt;] [poll-interval]</code>
   <br>
    Example: <code>define powermeter JSONMETER ITF 192.168.178.20 300</code>
   <br>&nbsp;
   <li><code>[poll-interval]</code>
   <br>
   Default is 300 seconds. Smallest possible value is 10. With 0 it will only update on "manual" request.
   </li><br>
   <li><code>&lt;deviceType&gt;</code>
     <br>
     Used to define the path and port to extract the json file.
     <br>
     The attribute 'pathString' can be used to add login information to the URL path of predefined devices.
     <br>&nbsp;
     <ul> 
         <li><b>ITF</b> - FROETEC Simplex ME one tariff electrical meter (N-ENERGY) (<a href="http://www.itf-froeschl.de">ITF Fr&ouml;schl</a>)</li>
         <li><b>EFR</b> - <a href="http://www.efr.de">EFR</a> Smart Grid Hub for electrical meter (EON, N-ENERGY and EnBW)
            <br>
            &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;use the 'pathstring' attribute to specifiy your login information
            <br>
            &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<code>attr <device> pathString ?LogName=<i>user</i>&LogPSWD=<i>password</i></code>
            </li>
         <li><b>LS110</b> - <a href="http://www.youless.nl/productdetails/product/ls110.html">YouLess LS110</a> network sensor (counter) for electro mechanical electricity meter</li>
         <li><b>url</b> - use the URL defined via the attributes 'pathString' and 'port'</li>
         <li><b>file</b> - use the file defined via the attribute 'pathString' (positioned in the FHEM file system)</li>
     </ul>
   </li>
  </ul>
  <br>

  <b>Set</b>
  <ul>
     <li><code>activeTariff &lt; 0 - 9 &gt;</code>
         <br>
         Allows the separate measurement of the consumption (doStatistics = 1) within different tariffs for all gages that miss this built-in capability (e.g. LS110). Also the possible gain of a change to a time-dependent tariff can be evaluated with this.<br>
         This value must be set at the correct point of time in accordance to the existing or planned tariff <b>by the FHEM command "at"</b>.<br>
         0 = without separate tariffs
       </li><br>
     <li><code>INTERVAL &lt;polling interval&gt;</code>
         <br>
         Polling interval in seconds
       </li><br>
     <li><code>resetStatistics &lt;all|statElectricityConsumed...|statElectricityConsumedTariff...|statElectricityPower...&gt;</code>
         <br>
         Deletes the selected statistic values.
         </li><br>
     <li><code>restartJsonAnalysis</code><br>
         Restarts the analysis of the json file for known readings (compliant to the OBIS standard).
         <br>
         This analysis happens normally only once if readings have been found.
       </li><br>
     <li><code>statusRequest</code>
         <br>
         Update device information
       </li>
  </ul>
  <br>
  
   <b>Get</b>
  <ul>
      <li><code>jsonFile</code>
      <br>
      extracts and shows the json data
      </li><br>
      <li><code>jsonAnalysis</code>
      <br>
      extracts the json data and shows the result of the analysis</li>
  </ul>
  <br>

  <a name="JSONMETERattr"></a>
   <b>Attributes</b>
   <ul>
   <li><code>alwaysAnalyse &lt; 0 | 1 &gt;</code>
      <br>
      Repeats by each update the json analysis - use if structure of json data changes
      <br>
      Normally the once analysed structure is saved to reduce CPU load.
      </li><br>
    <li><code>doStatistics &lt; 0 | 1 &gt;</code>
      <br>
      Builds daily, monthly and yearly statistics for certain readings (average/min/max or cumulated values).
      <br>
      Logging and visualisation of the statistics should be done with readings of type 'stat<i>ReadingName</i><b>Last</b>'.
      </li><br>
   <li><code>pathString &lt;string&gt;</code>
      <ul>
        <li>if deviceType = 'file': specifies the local file name and path</li>
        <li>if deviceType = 'url': specifies the url path</li>
        <li>other deviceType: can be used to add login information to the url path of predefined devices</li>
      </ul>
      </li><br>
   <li><code>port &lt;number&gt;</code>
      <br>
      Specifies the IP port for the deviceType 'url' (default is 80)
      </li><br>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
   </ul>
</ul>

=end html

=begin html_DE

<a name="JSONMETER"></a>
<h3>JSONMETER</h3>
<ul>
  Dieses Modul liest Daten von Messger&auml;ten (z.B. Stromz&auml;hler, Gasz&auml;hler oder W&auml;rmez&auml;hler, so genannte Smartmeter),
  <br>
  welche <a href="http://de.wikipedia.org/wiki/OBIS-Kennzahlen">OBIS</a> kompatible Daten im JSON-Format auf einem Webserver oder auf dem FHEM-Dateisystem zur Verf&uuml;gung stellen.
  <br>
  &nbsp;
  <br>
  
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; JSONMETER &lt;Ger&auml;tetyp&gt; [&lt;IP-Adresse&gt;] [Abfrageinterval]</code>
    <br>
    Beispiel: <code>define Stromzaehler JSONMETER ITF 192.168.178.20 300</code>
    <br>&nbsp;
    <li><code>[Abfrageinterval]</code>
      <br>
      Optional. Standardm&auml;ssig 300 Sekunden. Der kleinste m&ouml;gliche Wert ist 30.
      <br> 
      Bei 0 kann die Ger&auml;teabfrage nur manuell gestartet werden.
    </li><br>
    <li><code>&lt;Ger&auml;tetyp&gt;</code>
      <br>
      Definiert den Pfad und den Port, um die JSON-Datei einzulesen.
      <br>
      Mit dem Attribute 'pathString' k&ouml;nnen Login Information an den URL-Pfad von vordefinierten Ger&auml;te angehangen werden.
      <ul> 
         <li><b>ITF</b> - FROETEC Simplex ME Eintarifz&auml;hler (N-ENERGY) (<a href="http://www.itf-froeschl.de">ITF Fr&ouml;schl</a>)</li>
         <li><b>EFR</b> - <a href="http://www.efr.de">EFR</a> Smart Grid Hub f&uuml;r Stromz&auml;hler (EON, N-ENERGY, EnBW)
            <br>
            &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Die Login-Information wird &uuml;ber das Attribute 'pathstring' angegeben.
            <br>
            &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<code>?LogName=<i>Benutzer</i>&LogPSWD=<i>Passwort</i></code></li>
         <li><b>LS110</b> - <a href="http://www.youless.nl/productdetails/product/ls110.html">YouLess LS110</a> Netzwerkf&auml;higer Sensor f&uuml;r elektromechanische Stromz&auml;hler</li>
         <li><b>url</b> - benutzt die URL, welche durch das Attribut 'pathString' und 'port' definiert wird.</li>
         <li><b>file</b> - benutzt die Datei, welche durch das Attribut 'pathString' definiert wird (im FHEM Dateisystem)</li>
      </ul>
   </li>
  </ul>
  
  <br>
  <b>Set</b>
  <ul>
       <li><code>activeTariff &lt; 0 - 9 &gt;</code>
         <br>
         Erlaubt die gezielte, separate Erfassung der statistischen Verbrauchswerte (doStatistics = 1) für verschiedene Tarife (Doppelstromz&auml;hler), wenn der Stromz&auml;hler dies selbst nicht unterscheiden kann (z.B. LS110) oder wenn gepr&uuml;ft werden soll, ob ein zeitabh&auml;ngiger Tarif preiswerter w&auml;re.<br>
         Dieser Wert muss entsprechend des vorhandenen oder geplanten Tarifes zum jeweiligen Zeitpunkt z.B. durch den FHEM-Befehl "at" gesetzt werden.<br>
         0 = tariflos 
      </li><br>
     <li><code>INTERVAL &lt;Abfrageinterval&gt;</code>
         <br>
         Abfrageinterval in Sekunden
      </li><br>
      <li><code>resetStatistics &lt;all|statElectricityConsumed...|statElectricityConsumedTariff...|statElectricityPower...&gt;</code>
         <br>
         Löscht die ausgewählten statisischen Werte.
         </li><br>
      <li><code>restartJsonAnalysis</code>
        <br>
        Neustart der Analyse der json-Datei zum Auffinden bekannter Ger&auml;tewerte (kompatibel zum OBIS Standard).
        <br>
        Diese Analysie wird normaler Weise nur einmalig durchgef&uuml;hrt, nachdem Ger&auml;tewerte gefunden wurden.
        </li><br>
     <li><code>statusRequest</code>
         <br>
         Aktualisieren der Ger&auml;tewerte</li>
  </ul>
  <br>

  <b>Get</b>
  <ul>
      <li><code>jsonFile</code>
      <br>
      Liest die JSON-Datei ein und zeigt sie an.
      </li><br>
      <li><code>jsonAnalysis</code>
      <br>
      Extrahiert die JSON-Daten und zeigt das Resultat der JSON-Analyse.</li>
  </ul>
  <br>

  <a name="JSONMETERattr"></a>
   <b>Attributes</b>
   <ul>
      <li><code>alwaysAnalyse &lt; 0 | 1 &gt;</code>
         <br>
         F&uuml;hrt bei jeder Abfrage der Ger&auml;tewerte eine Analyse der JSON-Datenstruktur durch.
         <br>
         Dies ist sinnvoll, wenn sich die JSON-Struktur &auml;ndert. Normalerweise wird die analysierte Struktur
         zwischengespeichert, um die CPU-Last gering zu halten.
      </li><br>
      <li><code>doStatistics &lt; 0 | 1 &gt;</code>
         <br>
         Bildet t&auml;gliche, monatliche und j&auml;hrliche Statistiken bestimmter Ger&auml;tewerte (Mittel/Min/Max oder kumulierte Werte).
         <br>
         F&uuml;r grafische Auswertungen k&ouml;nnen die Werte der Form 'stat<i>ReadingName</i><b>Last</b>' genutzt werden.
         </li><br>
      <li><code>pathString &lt;Zeichenkette&gt;</code>
         <ul>
            <li>Ger&auml;tetyp 'file': definiert den lokalen Dateinamen und -pfad
               </li>
            <li>Ger&auml;tetyp 'url': Definiert den URL-Pfad
               </li>
            <li>Andere: Kann benutzt werden um Login-Information zum URL Pfad von vordefinerten Ger&auml;ten hinzuzuf&uuml;gen
               </li>
         </ul>
      </li><br>
      <li><code>port &lt;Nummer&gt;</code>
      <br>
      Beim Ger&auml;tetyp 'url' kann hier der URL-Port festgelegt werden (standardm&auml;ssig 80)
      </li><br>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
   </ul>
</ul>

=end html_DE

=cut

