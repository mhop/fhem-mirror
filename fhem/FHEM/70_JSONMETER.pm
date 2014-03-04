###############################################################
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
sub JSONMETER_doStatisticDelta ($$$);

# Modul Version for remote debugging
  my $modulVersion = "2014-03-03";

 ##############################################################
 # Syntax: meterType => port URL-Path
 ##############################################################
  my %meterTypes = ( ITF => "80 GetMeasuredValue.cgi" 
               ,EFR => "80 json.txt"
               ,LS110 => "80 a?f=j"
               );

 ##############################################################
 # Syntax: valueType, code, FHEM reading name, statisticType
 #     valueType: 1=OBISvalue | 2=OBISvalueString | 3=jsonProperty | 4=jsonPropertyTime
 #     statisticType: 0=noStatistic | 1=maxMinStatistic | 2=integralTimeStatistic
 ##############################################################
  my @jsonFields = (
    [3, "meterType", "meterType", 0] # {"meterId": "0000000061015736", "meterType": "Simplex", "interval": 0, "entry": [
   ,[4, "timestamp", "deviceTime", 0] # {"timestamp": 1389296286, "periodEntries": [
   ,[3, "cnt", "electricityConsumed", 2] # {"cnt":" 22,285","pwr":764,"lvl":0,"dev":"","det":"","con":"OK","sts":"(06)","raw":0}
   ,[3, "pwr", "electricityPower", 1] # {"cnt":" 22,285","pwr":764,"lvl":0,"dev":"","det":"","con":"OK","sts":"(06)","raw":0}
   ,[1, "010000090B00", "deviceTime", 0] #   { "obis":"010000090B00","value":"dd.mm.yyyy,hh:mm"}
   ,[2, "0.0.0", "meterID", 0] # {"obis": "0.0.0", "scale": 0, "value": 1627477814, "unit": "", "valueString": "0000000061015736" }, 
   ,[1, "0100000000FF", "meterID", 0] #  #   { "obis":"0100000000FF","value":"xxxxx"},
   ,[2, "0.2.0", "firmware", 0] # {"obis": "0.2.0", "scale": 0, "value": 0, "unit": "", "valueString": "V320090704" }, 
   ,[1, "1.7.0|0100010700FF", "electricityPower", 1]  # {"obis": "1.7.0", "scale": 0, "value": 392, "unit": "W", "valueString": "0000392" }, 
   ,[1, "0100150700FF", "electricityPowerPhase1", 1] # {"obis":"0100150700FF","value":209.40,"unit":"W"},
   ,[1, "0100290700FF", "electricityPowerPhase2", 1] # {"obis":"0100290700FF","value":14.27,"unit":"W"},
   ,[1, "01003D0700FF", "electricityPowerPhase3", 1] # {"obis":"01003D0700FF","value":89.40,"unit":"W"},
   ,[1, "1.8.0|0101010800FF", "electricityConsumed", 2] # {"obis": "1.8.0", "scale": 0, "value": 8802276, "unit": "Wh", "valueString": "0008802.276" }, 
   ,[1, "1.8.1|0101010801FF", "electricityConsumedTariff1", 2] # {"obis":"0101010801FF","value":33.53,"unit":"kWh"},               
   ,[1, "1.8.2|0101010802FF", "electricityConsumedTariff2", 2] # {"obis":"0101010802FF","value":33.53,"unit":"kWh"},               
   ,[1, "1.8.3|0101010803FF", "electricityConsumedTariff3", 2] # {"obis":"0101010803FF","value":33.53,"unit":"kWh"},               
   ,[1, "1.8.4|0101010804FF", "electricityConsumedTariff4", 2] # {"obis":"0101010804FF","value":33.53,"unit":"kWh"},               
   ,[1, "1.8.5|0101010805FF", "electricityConsumedTariff5", 2] # {"obis":"0101010805FF","value":33.53,"unit":"kWh"},               
   ,[1, "010001080080", "electricityConsumedToday", 0] 
   ,[1, "010001080081", "electricityConsumedYesterday", 0] 
   ,[1, "010001080082", "electricityConsumedLastWeek", 0] 
   ,[1, "010001080083", "electricityConsumedLastMonth", 0] 
   ,[1, "010001080084", "electricityConsumedLastYear", 0] 
   ,[1, "010002080080", "electricityProducedToday", 0] 
   ,[1, "010002080081", "electricityProducedYesterday", 0] 
   ,[1, "010002080082", "electricityProducedLastWeek", 0] 
   ,[1, "010002080083", "electricityProducedLastMonth", 0] 
   ,[1, "010002080084", "electricityProducedLastYear", 0] 
   ,[1, "0101020800FF", "electricityPowerOutput", 1]
   ,[1, "010020070000", "electricityVoltagePhase1", 1] #{"obis":"010020070000","value":237.06,"unit":"V"},               
   ,[1, "010034070000", "electricityVoltagePhase2", 1] # {"obis":"010034070000","value":236.28,"unit":"V"},               
   ,[1, "010048070000", "electricityVoltagePhase3", 1] # {"obis":"010048070000","value":236.90,"unit":"V"},
   ,[1, "01000E070000", "electricityFrequency", 1] # {"obis":"01000E070000","value":49.950,"unit":"Hz"}
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
                ."electricityTariff "
                ."electricityTariff1 "
                ."electricityTariff2 "
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
      foreach (sort keys %{ $hash->{READINGS} }) {
         if ($_ =~ /^\.?stat/ && $_ ne "state") {
            delete $hash->{READINGS}{$_};
            $resultStr .= "$name: Reading '$_' deleted\n";
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
   my $list = "statusRequest:noArg"
         ." resetStatistics:noArg"
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
  my $returnStr;
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
            if ($$f[0] =~ /^[15]$/) { 
               if ($fields[$i] =~ /"obis"\s*:\s*"($$f[1])"\s*[,}]/ && $fields[$i] =~ /"value"/) {
                  $jsonInterpreter .= "|$i $$f[0] $$f[2] $$f[3]";
                  Log3 $name,4,"$name: OBIS code \"$$f[1]\" will be stored in $$f[2]";
                  $returnStr .= "OBIS code \"$$f[1]\" will be extracted as reading '$$f[2]' from part $i:\n$fields[$i]\n\n";
               }
            } elsif ($$f[0] == 2) { 
               if ($fields[$i] =~ /"obis"\s*:\s*"($$f[1])"\s*[,}]/ && $fields[$i] =~ /"valueString"/) {
                  $jsonInterpreter .= "|$i $$f[0] $$f[2] $$f[3]";
                  Log3 $name,4,"$name: OBIS code \"$$f[1]\" will be stored in $$f[2]";
                  $returnStr .= "OBIS code \"$$f[1]\" will be extracted as reading '$$f[2]' from part $i:\n$fields[$i]\n\n";
               }
            } elsif ($$f[0] == 3) { 
               if ($fields[$i] =~ /"($$f[1])"\s*:/) {
                  $jsonInterpreter .= "|$i $$f[0] $$f[2] $$f[3] $$f[1]";
                  Log3 $name,4,"$name: Property \"$$f[1]\" will be stored in $$f[2]";
                  $returnStr .= "Property \"$$f[1]\" will be extracted as reading '$$f[2]' from part $i:\n$fields[$i]\n\n";
              }
            } elsif ($$f[0] == 4) { 
               if ($fields[$i] =~ /"($$f[1])"\s*:/) {
                  $jsonInterpreter .= "|$i $$f[0] $$f[2] $$f[3] $$f[1]";
                  Log3 $name,4,"$name: Property \"$$f[1]\" will be stored in $$f[2]";
                  $returnStr .= "Property \"$$f[1]\" will be extracted as reading '$$f[2]' from part $i:\n$fields[$i]\n\n";
               }
            } elsif ($$f[0] == 6) { 
               if ($fields[$i] =~ /"($$f[1])"\s*:/) {
                  $jsonInterpreter .= "|$i $$f[0] $$f[2] $$f[3] $$f[1]";
                  Log3 $name,4,"$name: Property \"$$f[1]\" will be stored in $$f[2]";
                  $returnStr .= "Property \"$$f[1]\" will be extracted as reading '$$f[2]' from part $i:\n$fields[$i]\n\n";
               }
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
      if ($b[1] == 1) { #obis value
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
      } elsif   ($b[1] == 2) { #obis valueString
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
      } elsif   ($b[1] == 3) { # JSON-Property  
         if ($fields[$b[0]] =~ /"$b[4]"\s*:\s*"(.*?)"\s*[,}]/g || $fields[$b[0]] =~ /"$b[4]"\s*:\s*(.*?)\s*[,}]/g ) {
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
      } elsif   ($b[1] == 4) {  # JSON-Property Time
         if ($fields[$b[0]] =~ /"$b[4]"\s*:\s"?(\d*)"?\s*[,}]/g ) {
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
         # JSONMETER_doStatisticMinMax $hash, $readingName, $value
         if ($statisticType == 1 ) { JSONMETER_doStatisticMinMax $hash, "stat".ucfirst($b[2]), $value ; }
         # JSONMETER_doStatisticDelta: $hash, $readingName, $value
         if ($statisticType == 2 ) { JSONMETER_doStatisticDelta $hash, "stat".ucfirst($b[2]), $value ; }
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
      if ($saveLast) {
         readingsBulkUpdate($hash, $readingName . "Last", $lastReading);
         $a[1] = 1;   $a[3] = $value;   $a[5] = 0;
         $b[1] = $value;   $b[3] = $value;   $b[5] = $value;
      } else {
         $a[1]++; # Count
         $a[3] += $value; # Sum
         if ($value < $b[1]) { $b[1]=$value; } # Min
         $b[3] = sprintf "%.0f" , $a[3] / $a[1]; # Avg
         if ($value > $b[5]) { $b[5]=$value; } # Max
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
JSONMETER_doStatisticDelta ($$$) 
{
   my ($hash, $readingName, $value) = @_;
   my $dummy;

   my @curr = split / /, $hash->{READINGS}{$readingName}{VAL} || "";
   my @start = split / /,  $hash->{READINGS}{"." . $readingName . "Start"}{VAL} || "";  

   my $saveLast=0;
   my @last;
   if (exists ($hash->{READINGS}{$readingName."Last"})) { 
     @last = split / /,  $hash->{READINGS}{$readingName."Last"}{VAL};
   } else {
      @last = split / /,  "Day: - Month: - Year: -";
   }
   
   my $result;
   my $yearLast;
   my $monthLast;
   my $dayLast;
   my $dayNow;
   my $monthNow;
   my $yearNow;
   
  # Determine date of last and current reading
   if (exists($hash->{READINGS}{$readingName}{TIME})) {
      ($yearLast, $monthLast, $dayLast) = ($hash->{READINGS}{$readingName}{TIME} =~ /^(\d\d\d\d)-(\d\d)-(\d\d)/);
   } else {
      ($dummy, $dummy, $dummy, $dayLast, $monthLast, $yearLast) = localtime;
      $yearLast += 1900;
      $monthLast ++;
      $start[1] = $value;
      $start[3] = $value;
      $start[5] = $value;
      $start[7] = 6; 
      $curr[7] = strftime "%Y-%m-%d_%H:%M:%S", localtime(); # Start
   }
   ($dummy, $dummy, $dummy, $dayNow, $monthNow, $yearNow) = localtime;
   $yearNow += 1900;
   $monthNow ++;
   
  # Yearly Statistic
   if ($yearNow != $yearLast){
      $last[5] = $curr[5];
      $start[5] = $value;
     # Do not show the "since:" value for year changes anymore
      if ($start[7] == 1) { $start[7] = 0; }
     # Shows the "since:" value for the first year change
      if ($start[7] >= 2) { 
         $last[7] = $curr[7];
         $start[7] = 1;
      }
   }
   $curr[5] = $value - $start[5];

  # Monthly Statistic 
   if ($monthNow != $monthLast){
      $last[3] = $curr[3];
      $start[3] = $value;
     # Do not show the "since:" value for month changes anymore
      if ($start[7] == 3) { $start[7] = 2; }
     # Shows the "since:" value for the first month change
      if ($start[7] >= 4) { 
         $last[7] = $curr[7];
         $start[7] = 3;
      }
   }
   $curr[3] = $value - $start[3];

   # Daily Statistic
   if ($dayNow != $dayLast){
      $last[1] = $curr[1];
      $start[1] = $value;
     # Do not show the "since:" value for day changes anymore
      if ($start[7] == 5) { $start[7] = 4; }
     # Shows the "since:" value for the first day change
      if ($start[7] >= 6) { 
         $last[7] = $curr[7];
         $start[7] = 5;
        # Next monthly and yearly values start at 00:00
         $curr[7] = strftime "%Y-%m-%d", localtime(); # Start
         $start[3] = $value;
         $start[5] = $value;
      }
      $saveLast = 1;
   }
   $curr[1] = $value - $start[1];
   
  # Store internal calculation values
   $result = "Day: $start[1] Month: $start[3] Year: $start[5] ShowDate: $start[7]";  
   readingsBulkUpdate($hash, ".".$readingName."Start", $result);

  # Store visible Reading
   $result = "Day: $curr[1] Month: $curr[3] Year: $curr[5]";
   if ($start[7] != 0 ) { $result .= " (since: $curr[7] )"; }
   readingsBulkUpdate($hash,$readingName,$result);

   if ($saveLast == 1) {
      $result = "Day: $last[1] Month: $last[3] Year: $last[5]";
      if ( $start[7] =~ /1|3|5/ ) { $result .= " (since: $last[7] )";}
      readingsBulkUpdate($hash,$readingName."Last",$result); 
   }
 
   return ;
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
         <li><b>ITF</b> - One tariff electrical meter used by N-ENERGY (<a href="http://www.itf-froeschl.de">ITF Fr&ouml;schl</a>)</li>
         <li><b>EFR</b> - <a href="http://www.efr.de">EFR</a> Smart Grid Hub for electrical meter used by EON, N-ENERGY and EnBW
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
      <li><code>INTERVAL &lt;polling interval&gt;</code><br>
        Polling interval in seconds
        </li><br>
      <li><code>statusRequest</code><br>
          Update device information
          </li><br>
      <li><code>restartJsonAnalysis</code><br>
          Restarts the analysis of the json file for known readings (compliant to the OBIS standard).
        <br>
        This analysis happens normally only once if readings have been found.</li>
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
      Calculate statistic values according to reading type (e.g. Average/Min/Max)
      <br>
      Builds daily, monthly and yearly statistics of certain readings. For diagrams, log readings of type 'stat<i>ReadingName</i><b>Last</b>'.
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
         <li><b>ITF</b> - Eintarifz&auml;hler von N-ENERGY Netz GmbH (<a href="http://www.itf-froeschl.de">ITF Fr&ouml;schl</a>)</li>
         <li><b>EFR</b> - <a href="http://www.efr.de">EFR</a> Smart Grid Hub f&uuml;r Stromz&auml;hler von EON, N-ENERGY, EnBW
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
      <li><code>INTERVAL &lt;Abfrageinterval&gt;</code>
         <br>
         Abfrageinterval in Sekunden
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
         Bildet t&auml;gliche, monatliche und j&auml;hrliche Statistiken bestimmter Ger&auml;tewerte.
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

