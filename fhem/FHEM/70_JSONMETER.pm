###############################################################
#
#  70_JSONMETER.pm
#
#  Copyright notice
#
#  (c) 2014 Torsten Poitzsch < torsten . poitzsch at gmx . de >
#
# 	This module reads data from devices that provide OBIS compatible json pathStrings (e.g. power meters)
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textpathString GPL.txt and important notices to the license
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
sub JSONMETER_UpdateDone($);
sub JSONMETER_UpdateAborted($);

# Modul Version for remote debugging
  my $modulVersion = "2014-02-08";

 ##############################################################
 # Syntax: meterType => port URL-Path
 ##############################################################
  my %meterTypes = ( ITF => "80 GetMeasuredValue.cgi" 
					,EFR => "80 json.txt"
				   );

 ##############################################################
 # Syntax: valueType, code, FHEM reading name, statisticType
 #	    valueType: 1=OBISvalue | 2=OBISvalueString | 3=jsonEntryTime | 4=jsonEntry 
 #     statisticType: 0=noStatistic | 1=maxMinStatistic | 2=timeStatistic
 ##############################################################
  my @jsonFields = (
     [3, "meterType", "meterType", 0] # {"meterId": "0000000061015736", "meterType": "Simplex", "interval": 0, "entry": [
	,[4, "timestamp", "deviceTime", 0] # {"timestamp": 1389296286, "periodEntries": [
    ,[5, "010000090B00", "deviceTime", 0] #	{ "obis":"010000090B00","value":"dd.mm.yyyy,hh:mm"}
    ,[2, "0.0.0", "meterID", 0] # {"obis": "0.0.0", "scale": 0, "value": 1627477814, "unit": "", "valueString": "0000000061015736" }, 
    ,[5, "0100000000FF", "meterID", 0] #  #	{ "obis":"0100000000FF","value":"xxxxx"},
    ,[2, "0.2.0", "firmware", 0] # {"obis": "0.2.0", "scale": 0, "value": 0, "unit": "", "valueString": "V320090704" }, 
    ,[1, "1.7.0", "currentPower", 1]  # {"obis": "1.7.0", "scale": 0, "value": 392, "unit": "W", "valueString": "0000392" }, 
	,[1, "0100010700FF", "currentPower", 1] # {"obis":"0100010700FF","value":313.07,"unit":"W"},
	,[1, "0100150700FF", "currentPowerPhase1", 1] # {"obis":"0100150700FF","value":209.40,"unit":"W"},
	,[1, "0100290700FF", "currentPowerPhase2", 1] # {"obis":"0100290700FF","value":14.27,"unit":"W"},
	,[1, "01003D0700FF", "currentPowerPhase3", 1] # {"obis":"01003D0700FF","value":89.40,"unit":"W"},
    ,[1, "1.8.0", "powerConsumption", 2] # {"obis": "1.8.0", "scale": 0, "value": 8802276, "unit": "Wh", "valueString": "0008802.276" }, 
    ,[1, "0101010800FF", "powerConsumption", 2] #{"obis":"0101010800FF","value":41.42,"unit":"kWh" },				
	,[1, "0101010801FF", "powerConsumptionTariff1", 2] # {"obis":"0101010801FF","value":33.53,"unit":"kWh"},					
	,[1, "0101010802FF", "powerConsumptionTariff2", 2] # {"obis":"0101010802FF","value":33.53,"unit":"kWh"},					
	,[1, "010020070000", "voltagePhase1", 1] #{"obis":"010020070000","value":237.06,"unit":"V"},					
	,[1, "010034070000", "voltagePhase2", 1] # {"obis":"010034070000","value":236.28,"unit":"V"},					
	,[1, "010048070000", "voltagePhase3", 1] # {"obis":"010048070000","value":236.90,"unit":"V"},
	,[1, "01000E070000", "frequency", 1] # {"obis":"01000E070000","value":49.950,"unit":"Hz"}
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
  elsif($cmd eq 'INTERVAL' && int(@_)==4 ) {
	$val = 10 if( $val < 10 );
	$hash->{INTERVAL}=$val;
	return "$name: Polling interval set to $val seconds.";
  }
  my $list = "statusRequest:noArg"
			." restartJsonAnalysis:noArg"
			." INTERVAL:slider,0,10,600";
  return "Unknown argument $cmd, choose one of $list";

} # end JSONMETER_Set


sub ##########################################
JSONMETER_Get($@)
{
  my ($hash, $name, $cmd) = @_;
  my $result;
  
  if ($cmd eq "jsonFile") {
	$result = JSONMETER_GetJsonFile $name;
	my @a = split /\|/, $result;
	my $message = decode_base64($a[2]);
	return $message;
  }
  
  my $list = "jsonFile:noArg";
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
		return "$name|0|"."Error reading device: Please define the attribute 'pathString'.";
	}
	
	$hash->{helper}{RUNNING_PID} = BlockingCall("JSONMETER_GetJsonFile", $name, "JSONMETER_UpdateDone", 10,"JSONMETER_UpdateAborted", $hash) unless(exists($hash->{helper}{RUNNING_PID}));
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
 
	 return "$name|0|".encode_base64("Error: deviceType '$type' Please define the attribute 'pathString' first.")
		if ($type eq "url" || $type eq "file") && ! defined($attr{$name}{"pathString"});

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
		# my @file = <IN>;
		close(IN);
		Log3 $name, 4, "$name: Close file";
		$message = encode_base64($message,"");
		return "$name|1|$message" ;
	 } else {
		Log3 $name, 2, "$name Error: Cannot open file $pathString: $!";
		return "$name|0|Error: Cannot open file";;
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
		$message = encode_base64($message,"");
		
		return "$name|1|$message" ;

	} else {
		Log3 $name, 2, "$name: Cannot open socket to $ip:$port/$pathString";
		
		return "$name|0|Error: Cannot open socket to $ip:$port/$pathString";
	
	}

} # end JSONMETER_ReadFromUrl

sub ###########################
JSONMETER_UpdateDone($)
{
  my ($string) = @_;
  return unless(defined($string));
  my (@a) = split("\\|", $string);
  my $hash = $defs{$a[0]};
  my $name = $hash->{NAME};
  my $value;
  
  delete($hash->{helper}{RUNNING_PID});
  

if ( $a[1] == 1 ){
	my $message = decode_base64($a[2]);
	$message =~ s/\s/ /g;
	$message =~ s/\n/ /g;

	readingsBeginUpdate($hash);

    my @fields=split(/\{/,$message); # JSON in einzelne Felder zerlegen
	
	my $jsonInterpreter = "";
  
  ####################################
  # ANALYSE once: Find all known obis codes in the first run and store in the item no, 
  # value type and reading name in the jsonInterpreter
  ####################################
    if ( $hash->{fhem}{jsonInterpreter} eq "" ) {
		Log3 $name, 3, "$name: Analyse JSON pathString for known readings";
		foreach my $f (@jsonFields) 
		{
			for(my $i=0; $i<=$#fields; $i++) 
			{
				if ($$f[0] == 1 || $$f[0] == 5) { 
					if ($fields[$i] =~ /"obis".*?:.*?"$$f[1]".*?[,}]/ && $fields[$i] =~ /"value"/) {
						$jsonInterpreter .= "|$i $$f[0] $$f[2] $$f[3]";
						Log3 $name,4,"$name: OBIS code \"$$f[1]\" will be stored in $$f[2]";
					}
				} elsif ($$f[0] == 2) { 
					if ($fields[$i] =~ /"obis".*?:.*?"$$f[1]".*?[,}]/ && $fields[$i] =~ /"valueString"/) {
						$jsonInterpreter .= "|$i $$f[0] $$f[2] $$f[3]";
						Log3 $name,4,"$name: OBIS code \"$$f[1]\" will be stored in $$f[2]";
					}
				} elsif ($$f[0] == 3) { 
					if ($fields[$i] =~ /"$$f[1]".*?:.*?[,}]/) {
						$jsonInterpreter .= "|$i $$f[0] $$f[2] $$f[3] $$f[1]";
						Log3 $name,4,"$name: Property \"$$f[1]\" will be stored in $$f[2]";
					}
				} elsif ($$f[0] == 4) { 
					if ($fields[$i] =~ /"$$f[1]".*?:.*?\d*.*?[,}]/) {
						$jsonInterpreter .= "|$i $$f[0] $$f[2] $$f[3] $$f[1]";
						Log3 $name,4,"$name: Property \"$$f[1]\" will be stored in $$f[2]";
					}
				}	
			}
		}
		if ($jsonInterpreter ne "") {
			Log3 $name, 3, "$name: Store results of JSON analysis for next device readings";
			$jsonInterpreter = substr $jsonInterpreter, 1;
			$hash->{fhem}{jsonInterpreter} = $jsonInterpreter;
		} else {
			Log3 $name, 2, "$name: Could not interpret the JSON pathString => please contact FHEM community" if $jsonInterpreter eq "";
		}
	} else {
		$jsonInterpreter = $hash->{fhem}{jsonInterpreter} if exists $hash->{fhem}{jsonInterpreter};
	}
	
  ####################################
  # INTERPRETE AND STORE
  # use the previously filled jsonInterpreter to extract the correct values
  ####################################
	my @a = split /\|/, $jsonInterpreter;
	Log3 $name, 4, "$name: Extract ".($#a+1)." readings from ".($#fields+1)." json parts";
	foreach (@a) {
		Log3 $name, 5, "$name: Handle $_";
		my @b = split / /, $_ ;
		if ($b[1] == 1) {
			if ($fields[$b[0]] =~ /"value".*?:(.*?)[,\}]/ ) {
				$value = $1;
				$value =~ s/^\s+|\s+$//g;
				Log3 $name, 4, "$name: value $value for reading $b[2] extracted from '$fields[$b[0]]'";
				readingsBulkUpdate($hash,$b[2],$value); 				
			} else {
				Log3 $name, 4, "$name: Could not extract value for reading $b[2] from '$fields[$b[0]]'";
			}
		} elsif	($b[1] == 5) {	
			if ($fields[$b[0]] =~ /"value".*?:.*?"(.*?)".*?[,}]/ ) {
				$value = $1;
				Log3 $name, 4, "$name: value $value for reading $b[2] extracted from '$fields[$b[0]]'";
				readingsBulkUpdate($hash,$b[2],$value); 
			} else {
				Log3 $name, 4, "$name: Could not extract value for reading $b[2] from '$fields[$b[0]]'";
			}
		} elsif	($b[1] == 2) {	
			if ($fields[$b[0]] =~ /"valueString".*?:.*?"(.*?)".*?[,}]/ ) {
				$value = $1;
				Log3 $name, 4, "$name: value $value for reading $b[2] extracted from '$fields[$b[0]]'";
				readingsBulkUpdate($hash,$b[2],$value); 
			} else {
				Log3 $name, 4, "$name: Could not extract value for reading $b[2] from '$fields[$b[0]]'";
			}
		} elsif	($b[1] == 3) {	
			if ($fields[$b[0]] =~ /"$b[4]".*?:.*?"(.*?)".*?[,}]/ ) {
				$value = $1;
				Log3 $name, 4, "$name: value $value for reading $b[2] extracted from '$fields[$b[0]]'";
				readingsBulkUpdate($hash, $b[2], $value); 
			} else {
				Log3 $name, 4, "$name: Could not extract value for reading $b[2] from '$fields[$b[0]]'";
			}
		} elsif	($b[1] == 4) {	
			if ($fields[$b[0]] =~ /"$b[4]".*?:(.*?)[,}]/ ) {
				$value = $1;
				$value =~ s/^\s+|\s+$//g;
				Log3 $name, 4, "$name: value $value for reading $b[2] extracted from '$fields[$b[0]]'";
				$value =  strftime "%Y-%m-%d %H:%M:%S", localtime($value);
				readingsBulkUpdate($hash, $b[2], $value); 
			} else {
				Log3 $name, 4, "$name: Could not extract value for reading $b[2] from '$fields[$b[0]]'";
			}
		}
	}

	readingsBulkUpdate($hash,"state","Connected");
    readingsEndUpdate($hash,1);
    DoTrigger($hash->{NAME}, undef) if ($init_done);
 
  } else {
	readingsSingleUpdate($hash,"state",$a[2],1);
  }

  return undef;
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
  &nbsp;
  <br>
  <b>Define</b>
  <ul>
    <li><code>define &lt;name&gt; JSONMETER &lt;deviceType&gt; [&lt;ip address&gt;] [poll-interval]</code>
	<br>
    Example: <code>define powermeter JSONMETER ITF 192.168.178.20 300</code>
	<br>
    If the pool interval is omitted, it is set to 300 (seconds). Smallest possible value is 10.
	<br>
	With 0 it will only update on "manual" request.
	<li><code>deviceType</code>
	  <ul>Used to define the path and port to extract the json file. 
	   <li><b>ITF</b> - One tariff power meter used by N-ENERGY Netz GmbH (Industrietechnik Fr&ouml;schle)</li>
	   <li><b>EFR</b> - Power meter used by N-ENERGY Netz GmbH</li>
	   <li><b>url</b> - use URL defined via the attributes 'pathString' and 'port'</li>
	   <li><b>file</b> - use file defined via the attribute 'pathString' (positioned in the FHEM file system)</li>
	   The attribute 'pathString' can also be used to add login information to the URL-path of predefined devices.
	  </ul>
	</li>
  </ul>

  <b>Set</b><br>
  <ul>
      <li><code>INTERVAL &lt;polling interval&gt;</code><br>
		  Polling interval in seconds</li>
      <li><code>statusRequest</code><br>
          Update device information</li>
      <li><code>restartJsonAnalysis</code><br>
          Restarts the analysis of the json file for known readings (compliant to the OBIS standard).
		  <br>
		  This analysis happens normally only once if readings have been found.</li>
  </ul>

 <b>Get</b><br>
   <b>Get</b>
  <ul>
      <li><code>jsonFile</code>
		<br>
		extracts and shows the json file</li>
  </ul>
  <br>

  <a name="JSONMETERattr"></a>
   <b>Attributes</b>
   <ul>
    <li><code>doStatistics &lt; 0 | 1 &gt;</code>
		<br>
		Calculates statistic values - <i>not implemented yet</i></li>
	<li><code>pathString &lt;string&gt;</code>
		<ul>
		  <li>deviceType 'file': specifies the local file name and path</li>
		  <li>deviceType 'url': specifies the url path</li>
		  <li>other: can be used to add login information to the url path of predefined devices
			  <br>
			  e.g. <code>?LogName=secret&LogPSWD=very_secret</code></li>
		</ul>
	<li><code>port &lt;number&gt;</code>
		<br>
		if the deviceType 'url' is selected the url port can be specified here (default is 80)</li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
   </ul>
</ul>

=end html

=begin html_DE

<a name="JSONMETER"></a>
<h3>JSONMETER</h3>
<ul>
  Dieses Modul liest Daten von Messger&auml;ten (z.B. Stromz&auml;hler/Energiez&auml;hler, Gasz&auml;hler oder W&auml;rmez&auml;hler, so genannte Smartmeter),
  <br>
  welche OBIS kompatible Daten im JSON-Format auf einem Webserver oder auf dem FHEM-Dateisystem zur Verf&uuml;gung stellen.
  <br>
  &nbsp;
  <br>
  <b>Define</b>
  <ul>
    <li><code>define &lt;name&gt; JSONMETER &lt;Ger&auml;tetyp&gt; [&lt;IP-Adresse&gt;] [Abfrageinterval]</code>
	<br>
    Beispiel: <code>define Stromzaehler JSONMETER ITF 192.168.178.20 300</code>
	<br>
    Wenn das Abfrage-Interval nicht angegeben ist, wird es auf 300 (Sekunden) gesetzt. Der kleinste m&ouml;gliche Wert ist 30.
	<br>
	Bei 0 kann die Ger&auml;teabfrage nur manuell gestartet werden.
	<li><code>Ger&auml;tetyp</code>
	  <ul>Definiert den Pfad und den Port, um die JSON-Datei zu einzulesen. 
	   <li><b>ITF</b> - Eintarifz&auml;hler, genutzt von N-ENERGY Netz GmbH (Industrietechnik Fr&ouml;schle)</li>
	   <li><b>EFR</b> - Stromz&auml;hler, genutzt von  N-ENERGY Netz GmbH</li>
	   <li><b>url</b> - benutzt die URL, welche durch das Attribut 'pathString' und 'port' definiert wird.</li>
	   <li><b>file</b> - benutzt die Datei, welche durch das Attribut 'pathString' definiert wird (im FHEM Dateisystem)</li>
	   Das Attribute 'pathString' kann auch benutzt werdne, um Login Information an den URL-Pfad der vordefinierten Ger&auml;te anzuh&auml;ngen.
	  </ul>
	</li>
  </ul>

  <b>Set</b><br>
  <ul>
	  <li><code>INTERVAL &lt;Abfrageinterval&gt;</code>
			<br>
			Abfrageinterval in Sekunden</li>
	  <li><code>statusRequest</code>
			<br>
			Aktualisieren der Ger&auml;tewerte</li>
      <li><code>restartJsonAnalysis</code>
		  <br>
		  Neustart der Analyse der json-Datei zum Auffinden bekannter Ger&auml;tewerte (kompatibel zum OBIS Standard).
		  <br>
		  Diese Analysie wird normaler Weise nur einmal durchgef&uuml;hrt, wenn Ger&auml;tewerte gefunden wurden.</li>
  </ul>

 <b>Get</b><br>
   <b>Get</b>
  <ul>
      <li><code>jsonFile</code>
		<br>
		Liest die JSON-Datei ein und zeigt sie an</li>
  </ul>
  <br>

  <a name="JSONMETERattr"></a>
   <b>Attributes</b>
   <ul>
    <li><code>doStatistics &lt; 0 | 1 &gt;</code>
		<br>
		Berechnet statistische Werte - <i>noch nicht implementiert</i></li>
	<li><code>pathString &lt;Zeichenkette&gt;</code>
		<ul>
		  <li>Ger&auml;tetyp 'file': definiert den lokalen Dateinamen und -pfad</li>
		  <li>Ger&auml;tetyp 'url': Definiert den URL-Pfad</li>
		  <li>Andere: Kann benutzt werden um Login-Information zum URL Pfad von vordefinerten Ger&auml;ten hinzuzuf&uuml;gen
			  <br>
			  e.g. <code>?LogName=geheim&LogPSWD=sehr_geheim</code></li>
		</ul>
	<li><code>port &lt;Nummer&gt;</code>
		<br>
		Beim Ger&auml;tetyp 'url' kann hier der URL-Port festgelegt werden (standardmässig 80)</li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
   </ul>
</ul>

=end html_DE

=cut

