##############################################
# 00_THZ
# by immi 02/2014
# v. 0.068
# this code is based on the hard work of Robert; I just tried to port it
# http://robert.penz.name/heat-pump-lwz/
# http://heatpumpmonitor.penz.name/heatpumpmonitorwiki/
########################################################################################
#
#  This programm is free software; you can redistribute it and/or modify
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
########################################################################################


package main;
use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use feature ":5.10";
sub THZ_Read($);
sub THZ_ReadAnswer($);
sub THZ_Ready($);
sub THZ_Write($$);
sub THZ_Parse($);
sub THZ_Parse1($);
sub THZ_checksum($);
sub THZ_replacebytes($$$);
sub THZ_decode($);
sub THZ_overwritechecksum($);
sub THZ_encodecommand($$);
sub hex2int($);
sub quaters2time($);
sub time2quaters($);
sub THZ_debugread($);
sub THZ_GetRefresh($);
sub THZ_Refresh_all_gets($);



########################################################################################
#
# %sets - all supported protocols are listed
# 
########################################################################################

my %sets = (
	"p01RoomTempDayHC1"		=> {cmd2=>"0B0005", argMin => "13", argMax => "28"  },   
	"p02RoomTempNightHC1"		=> {cmd2=>"0B0008", argMin => "13", argMax => "28"  },
	"p03RoomTempStandbyHC1"		=> {cmd2=>"0B013D", argMin => "13", argMax => "28"  },
	"p01RoomTempDayHC2"		=> {cmd2=>"0C0005", argMin => "13", argMax => "28"  },
	"p02RoomTempNightHC2"		=> {cmd2=>"0C0008", argMin => "13", argMax => "28"  },
	"p03RoomTempStandbyHC2"		=> {cmd2=>"0C013D", argMin => "13", argMax => "28"  },
	"p04DHWsetDay"			=> {cmd2=>"0A0013", argMin => "13", argMax => "46"  },
	"p05DHWsetNight"		=> {cmd2=>"0A05BF", argMin => "13", argMax => "46"  },
	"p07FanStageDay"		=> {cmd2=>"0A056C", argMin =>  "0", argMax =>  "3"  },
	"p08FanStageNight"		=> {cmd2=>"0A056D", argMin =>  "0", argMax =>  "3"  },
	"p09FanStageStandby"		=> {cmd2=>"0A056F", argMin =>  "0", argMax =>  "3"  },
	"p99FanStageParty"		=> {cmd2=>"0A0570", argMin =>  "0", argMax =>  "3"  },
	"holidayBegin_day"		=> {cmd2=>"0A011B", argMin =>  "1", argMax =>  "31"  }, 
	"holidayBegin_month"		=> {cmd2=>"0A011C", argMin =>  "1", argMax =>  "12"  },
	"holidayBegin_year"		=> {cmd2=>"0A011D", argMin =>  "12", argMax => "20"  },
	"holidayBegin-time"		=> {cmd2=>"0A05D3", argMin =>  "00:00", argMax =>  "23:59"},
	"holidayEnd_day"		=> {cmd2=>"0A011E", argMin =>  "1", argMax =>  "31"  }, 
	"holidayEnd_month"		=> {cmd2=>"0A011F", argMin =>  "1", argMax =>  "12"  },
	"holidayEnd_year"		=> {cmd2=>"0A0120", argMin =>  "12", argMax => "20"  }, 
	"holidayEnd-time"		=> {cmd2=>"0A05D4", argMin =>  "00:00", argMax =>  "24:60" }, # the answer look like  0A05D4-0D0A05D40029 for year 41 which is 10:15
	#"party-time"			=> {cmd2=>"0A05D1"}, # value 1Ch 28dec is 7 ; value 1Eh 30dec is 7:30
  );




########################################################################################
#
# %gets - all supported protocols are listed without header and footer
#
########################################################################################

my %gets = (
#	"hallo"       			=> { },
#	"debug_read_raw_register_slow"	=> { },
	"history"			=> {cmd2=>"09"},
	"last10errors"			=> {cmd2=>"D1"},
        "allFB"     			=> {cmd2=>"FB"},
        "timedate" 			=> {cmd2=>"FC"},
        "firmware" 			=> {cmd2=>"FD"},
	"p01RoomTempDayHC1"		=> {cmd2=>"0B0005"},   
	"p02RoomTempNightHC1"		=> {cmd2=>"0B0008"},
	"p03RoomTempStandbyHC1"		=> {cmd2=>"0B013D"},
	"p01RoomTempDayHC2"		=> {cmd2=>"0C0005"},
	"p02RoomTempNightHC2"		=> {cmd2=>"0C0008"},
	"p03RoomTempStandbyHC2"		=> {cmd2=>"0C013D"},
	"p04DHWsetDay"			=> {cmd2=>"0A0013"},
	"p05DHWsetNight"		=> {cmd2=>"0A05BF"},
	"p07FanStageDay"		=> {cmd2=>"0A056C"},
	"p08FanStageNight"		=> {cmd2=>"0A056D"},
	"p09FanStageStandby"		=> {cmd2=>"0A056F"},
	"p99FanStageParty"		=> {cmd2=>"0A0570"},
	"holidayBegin_day"		=> {cmd2=>"0A011B"}, 
	"holidayBegin_month"		=> {cmd2=>"0A011C"},
	"holidayBegin_year"		=> {cmd2=>"0A011D"},
	"holidayBegin-time"		=> {cmd2=>"0A05D3"},
	"holidayEnd_day"		=> {cmd2=>"0A011E"}, 
	"holidayEnd_month"		=> {cmd2=>"0A011F"},
	"holidayEnd_year"		=> {cmd2=>"0A0120"}, # the answer look like  0A0120-3A0A01200E00  for year 14
	"holidayEnd-time"		=> {cmd2=>"0A05D4"}, # the answer look like  0A05D4-0D0A05D40029 41 which is 10:15
	"party-time"			=> {cmd2=>"0A05D1"}, # value 1Ch 28dec is 7 ; value 1Eh 30dec is 7:30
	"programHC1_Mo_0"		=> {cmd2=>"0B1410"},  #1 is monday 0 is first prog; start and end; value 1Ch 28dec is 7 ; value 1Eh 30dec is 7:30
	"programHC1_Mo_1"		=> {cmd2=>"0B1411"},
	"programHC1_Mo_2"		=> {cmd2=>"0B1412"},
	"programHC1_Tu_0"		=> {cmd2=>"0B1420"},
	"programHC1_Tu_1"		=> {cmd2=>"0B1421"},
	"programHC1_Tu_2"		=> {cmd2=>"0B1422"},
	"programHC1_We_0"		=> {cmd2=>"0B1430"},
	"programHC1_We_1"		=> {cmd2=>"0B1431"},
	"programHC1_We_2"		=> {cmd2=>"0B1432"},
	"programHC1_Th_0"		=> {cmd2=>"0B1440"},
	"programHC1_Th_1"		=> {cmd2=>"0B1441"},
	"programHC1_Th_2"		=> {cmd2=>"0B1442"},
	"programHC1_Fr_0"		=> {cmd2=>"0B1450"},
	"programHC1_Fr_1"		=> {cmd2=>"0B1451"},
	"programHC1_Fr_2"		=> {cmd2=>"0B1452"},
	"programHC1_Sa_0"		=> {cmd2=>"0B1460"},
	"programHC1_Sa_1"		=> {cmd2=>"0B1461"},
	"programHC1_Sa_2"		=> {cmd2=>"0B1462"},
	"programHC1_So_0"		=> {cmd2=>"0B1470"},
	"programHC1_So_1"		=> {cmd2=>"0B1471"},
	"programHC1_So_2"		=> {cmd2=>"0B1472"},
	"programHC1_Mo-Fr_0"		=> {cmd2=>"0B1480"},
	"programHC1_Mo-Fr_1"		=> {cmd2=>"0B1481"},
	"programHC1_Mo-Fr_3"		=> {cmd2=>"0B1482"},
	"programHC1_Sa-So_0"		=> {cmd2=>"0B1490"},
	"programHC1_Sa-So_1"		=> {cmd2=>"0B1491"},
	"programHC1_Sa-So_3"		=> {cmd2=>"0B1492"},
	"programHC1_Mo-So_0"		=> {cmd2=>"0B14A0"},
	"programHC1_Mo-So_1"		=> {cmd2=>"0B14A1"},
	"programHC1_Mo-So_3"		=> {cmd2=>"0B14A2"},
	"programHC2_Mo_0"		=> {cmd2=>"0C1510"},  #1 is monday 0 is first prog; start and end; value 1Ch 28dec is 7 ; value 1Eh 30dec is 7:30
	"programHC2_Mo_1"		=> {cmd2=>"0C1511"},
	"programHC2_Mo_2"		=> {cmd2=>"0C1512"},
	"programHC2_Tu_0"		=> {cmd2=>"0C1520"},
	"programDHW_Mo_0"		=> {cmd2=>"0A1710"},
	"programDHW_Mo_1"		=> {cmd2=>"0A1711"}, 
	"programFan_Mo_0"		=> {cmd2=>"0A1D10"},
	"programFan_Mo_1"		=> {cmd2=>"0A1D11"}
  );


########################################################################################
#
# THZ_Initialize($)
# 
# Parameter hash
#
########################################################################################
sub THZ_Initialize($)
{
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

# Provider
  $hash->{ReadFn}  = "THZ_Read";
  $hash->{WriteFn} = "THZ_Write";
  $hash->{ReadyFn} = "THZ_Ready";
  
# Normal devices
  $hash->{DefFn}   = "THZ_Define";
  $hash->{UndefFn} = "THZ_Undef";
  $hash->{GetFn}   = "THZ_Get";
  $hash->{SetFn}   = "THZ_Set";
  $hash->{AttrList}= "do_not_notify:1,0 dummy:1,0 loglevel:0,1,2,3,4,5,6  interval_allFB:0,60,120,180,300,600,3600,7200,43200,86400 interval_history:0,3600,7200,28800,43200,86400";
}


########################################################################################
#
# THZ_define
#
# Parameter hash and configuration
#
########################################################################################
sub THZ_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name = $a[0];

  return "wrong syntax. Correct is: define <name> THZ ".
  				"{devicename[\@baudrate]|ip:port}"
  				 if(@a != 3);
  				
  DevIo_CloseDev($hash);
  my $dev  = $a[2];

  if($dev eq "none") {
    Log 1, "$name device is none, commands will be echoed only";
    $attr{$name}{dummy} = 1;
    return undef;
  }
  
  $hash->{DeviceName} = $dev;
  my $ret = DevIo_OpenDev($hash, 0, undef);
  
    
  #my %par = (command => "allFB", hash => $hash );   
  #InternalTimer(gettimeofday() +200, "THZ_GetRefresh", \%par, 0);
  #my %par1 = ( command => "firmware", hash => $hash);   
  #InternalTimer(gettimeofday() +200, "THZ_GetRefresh", \%par1, 0);
  #foreach  my $cmdhash  (keys %gets) { THZ_Get($hash, $hash->{NAME}, $cmdhash); }  #refresh all registers 
  THZ_Refresh_all_gets($hash);
  return $ret;
}

########################################################################################
#
# THZ_Refresh_all_gets - Called once refreshes current reading for all gets and initializes the regular interval calls
#
# Parameter $hash
# 
########################################################################################
sub THZ_Refresh_all_gets($) {
  my ($hash) = @_;
  RemoveInternalTimer($hash);
  my $timedelay= 1;
  foreach  my $cmdhash  (keys %gets) {
    my %par = ( command => $cmdhash, hash => $hash );
    RemoveInternalTimer(\%par);
    InternalTimer(gettimeofday() + $timedelay++ , "THZ_GetRefresh", \%par, 0); 
  }  #refresh all registers; the register with interval_command ne 0 will keep on refreshing
}


########################################################################################
#
# THZ_GetRefresh - Called in regular intervals to obtain current reading
#
# Parameter (hash => $hash, command => "allFB" )
# it get the intervall directly from a attribute; the register with interval_command ne 0 will keep on refreshing
########################################################################################
sub THZ_GetRefresh($) {
	my ($par)=@_;
	my $hash=$par->{hash};
	my $command=$par->{command};
	my $interval = AttrVal($hash->{NAME}, ("interval_".$command), 0);
	if ($interval) {
			$interval = 60 if ($interval < 60); #do not allow intervall <60 sec 
			InternalTimer(gettimeofday()+ $interval, "THZ_GetRefresh", $par, 1) ;
	}		
        my $replyc = "";
	$replyc = THZ_Get($hash, $hash->{NAME}, $command) if (!($hash->{STATE} eq "disconnected")); 
	return ($replyc);
}



#####################################
# THZ_Write -- simple write
# Parameter:  hash and message HEX
#
########################################################################################
sub THZ_Write($$) {
  my ($hash,$msg) = @_;
  my $name = $hash->{NAME};
  my $ll5 = GetLogLevel($name,5);
  my $bstring;
    $bstring = $msg;

  Log $ll5, "$hash->{NAME} sending $bstring";

  DevIo_SimpleWrite($hash, $bstring, 1);
}


#####################################
# sub THZ_Read($)
# called from the global loop, when the select for hash reports data
# used just for testing the interface
########################################################################################
sub THZ_Read($)
{
  my ($hash) = @_;

  my $buf = DevIo_SimpleRead($hash);
  return "" if(!defined($buf));

  my $name = $hash->{NAME};
  my $ll5 = GetLogLevel($name,5);
  my $ll2 = GetLogLevel($name,2);

  my $data = $hash->{PARTIAL} . uc(unpack('H*', $buf));
  
Log $ll5, "$name/RAW: $data";
Log $ll2, "$name/RAW: $data";
  
}



#####################################
#
# THZ_Ready($) - Cchecks the status
#
# Parameter hash
#
########################################################################################
sub THZ_Ready($)
{
  my ($hash) = @_;

  return DevIo_OpenDev($hash, 1, undef)
                if($hash->{STATE} eq "disconnected");
  
    # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  if($po) {
    my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
    return ($InBytes>0);
  }
  
}





#####################################
#
# THZ_Set - provides a method for setting the heatpump
#
# Parameters: hash and command to be sent to the interface
#
########################################################################################
sub THZ_Set($@){
  my ($hash, @a) = @_;
  my $dev = $hash->{DeviceName};
  my $name = $hash->{NAME};
  my $ll5 = GetLogLevel($name,5);
  my $ll2 = GetLogLevel($name,2);

  return "\"set $name\" needs at least two parameters: <device-parameter> and <value-to-be-modified>" if(@a < 2);
  my $cmd = $a[1];
  my $arg = $a[2];
  my ($err, $msg) =("", " ");
  my $cmdhash = $sets{$cmd};
  return "Unknown argument $cmd, choose one of " . join(" ", sort keys %sets) if(!defined($cmdhash));
  return "\"set $name $cmd\" needs at least one further argument: <value-to-be-modified>" if(!defined($arg));
  my $argreMax = $cmdhash->{argMax};
  my $argreMin = $cmdhash->{argMin};
  return "Argument does not match the allowed inerval Min $argreMin ...... Max $argreMax " if(($arg > $argreMax) or ($arg < $argreMin));
  my $cmdHex2 = $cmdhash->{cmd2};
    
  if     (substr($cmdHex2,0,4) eq "0A01")  {$arg=$arg*256}		        	# shift 2 times -- the answer look like  0A0120-3A0A01200E00  for year 14
  #  elsif ((substr($message,4,2) eq "1D") or (substr($message,4,2) eq "17")) 		{$message = quaters2time(substr($message, 8,2)) ."--". quaters2time(substr($message, 10,2))}  #value 1Ch 28dec is 7 ; value 1Eh 30dec is 7:30  
  #  elsif  (substr($message,4,3) eq "05D")  						{$message = quaters2time(substr($message, 10,2)) }  #value 1Ch 28dec is 7 
  elsif  ((substr($cmdHex2,0,6) eq "0A05D3") or (substr($cmdHex2,0,6) eq "0A05D4")) 	{$arg= time2quaters($arg)} 
  elsif  ((substr($cmdHex2,0,5) eq "0A056") or (substr($cmdHex2,0,5) eq "0A057"))	{ } 				# fann speed: do not multiply
  else 			             {$arg=$arg*10} 
    
  THZ_Write($hash,  "02"); 			# STX start of text
  ($err, $msg) = THZ_ReadAnswer($hash);		#Expectedanswer1    is  "10"  DLE data link escape
  
  if ($msg eq "10") {
    $cmdHex2=THZ_encodecommand(($cmdHex2 . sprintf("%04X", $arg)),"set");
    THZ_Write($hash,  $cmdHex2); 		# send request   SOH start of heading -- Null 	-- ?? -- DLE data link escape -- EOT End of Text
    ($err, $msg) = THZ_ReadAnswer($hash);	#Expectedanswer     is "10",		DLE data link escape 
     }
    
   if ($msg eq "10") {
      ($err, $msg) = THZ_ReadAnswer($hash);	#Expectedanswer  is "02"  -- STX start of text
     THZ_Write($hash,  "10"); 		    	# DLE data link escape  // ack datatranfer      
     ($err, $msg) = THZ_ReadAnswer($hash);	# Expectedanswer3 // read from the heatpump
      THZ_Write($hash,  "10");
      $msg =$msg . "kkkkkkk"
     }
   
   if (defined($err))  {return ($cmdHex2 . "-". $msg ."--" . $err);}
   else {
	sleep 1;
	THZ_Get($hash, $name, $cmd);
	#return ($cmd . " " . $cmdHex2 . "-x- ". $msg);
	} 
}




#####################################
#
# THZ_Get - provides a method for polling the heatpump
#
# Parameters: hash and command to be sent to the interface
#
########################################################################################
sub THZ_Get($@){
  my ($hash, @a) = @_;
  my $dev = $hash->{DeviceName};
  my $name = $hash->{NAME};
  my $ll5 = GetLogLevel($name,5);
  my $ll2 = GetLogLevel($name,2);

  return "\"get $name\" needs one parameter" if(@a != 2);
  my $cmd = $a[1];
  my ($err, $msg) =("", " ");

  my $cmdhash = $gets{$cmd};
  return "Unknown argument $cmd, choose one of " .
        join(" ", sort keys %gets) if(!defined($cmdhash));

  if ($cmd eq "debug_read_raw_register_slow") {
    THZ_debugread($hash);
    return ("all raw registers read and saved");
    }           
	            		
  THZ_Write($hash,  "02"); 			# STX start of text
  ($err, $msg) = THZ_ReadAnswer($hash);		#Expectedanswer1    is  "10"  DLE data link escape
  
  my $cmdHex2 = $cmdhash->{cmd2};
   if(defined($cmdHex2) and ($msg eq "10") ) {
    $cmdHex2=THZ_encodecommand($cmdHex2,"get");
      THZ_Write($hash,  $cmdHex2); 		# send request   SOH start of heading -- Null 	-- ?? -- DLE data link escape -- EOT End of Text
     ($err, $msg) = THZ_ReadAnswer($hash);	#Expectedanswer2     is "1002",		DLE data link escape -- STX start of text
    }
    
   if($msg eq "1002") {
     THZ_Write($hash,  "10"); 		    	# DLE data link escape  // ack datatranfer      
     ($err, $msg) = THZ_ReadAnswer($hash);	# Expectedanswer3 // read from the heatpump
     THZ_Write($hash,  "10");
     }
   
   if (defined($err))  {return ($msg ."\n" . $err);}
   else {   
	($err, $msg) = THZ_decode($msg); 	#clean up and remove footer and header
        if (defined($err))  {return ($msg ."\n" . $err);}
	else {   
        $msg = THZ_Parse($msg);
	my $activatetrigger =1;
	readingsSingleUpdate($hash, $cmd, $msg, $activatetrigger);
	return ($msg);
	}    
    }    
}




#####################################
#
# THZ_ReadAnswer- provides a method for simple read
#
# Parameter hash and command to be sent to the interface
#
########################################################################################
sub THZ_ReadAnswer($) {
  my ($hash) = @_;
#--next line added in order to slow-down 100ms
  select(undef, undef, undef, 0.1);
#--
  my $buf = DevIo_SimpleRead($hash);
  return ("InterfaceNotRespondig", "") if(!defined($buf));

  my $name = $hash->{NAME};
  
  my $data =  uc(unpack('H*', $buf));
  return (undef, $data);
}

 
#####################################
#
# THZ_checksum - takes a string, removes the footer (4bytes) and computes checksum (without checksum of course)
#
# Parameter string
# returns the checksum 2bytes
#
########################################################################################
sub THZ_checksum($) {
  my ($stringa) = @_;
  my $ml = length($stringa) - 4;
  my $checksum = 0;
  for(my $i = 0; $i < $ml; $i += 2) {
    ($checksum= $checksum + hex(substr($stringa, $i, 2))) if ($i != 4);
  }
  return (sprintf("%02X", ($checksum %256)));
}

#####################################
#
# hex2int - convert from hex to int with sign 16bit
#
########################################################################################
sub hex2int($) {
  my ($num) = @_;
 $num = unpack('s', pack('S', hex($num)));
  return $num;
}

####################################
#
# quaters2time - convert from hex to time; specific to the week programm registers
#
# parameter 1 byte representing number of quarter from midnight
# returns   string representing time
#
# example: value 1E is converted to decimal 30 and then to a time  7:30 
########################################################################################
sub quaters2time($) {
  my ($num) = @_;
  return("n.a.") if($num eq "80"); 
  my $quarters= hex($num) %4;
  my $hour= (hex($num) - $quarters)/4 ;
  my $time = sprintf("%02u", ($hour)) . ":" . sprintf("%02u", ($quarters*15));
  return $time;
}




####################################
#
# time2quarters - convert from time to quarters in hex; specific to the week programm registers
#
# parameter: string representing time
# returns: 1 byte representing number of quarter from midnight
#
# example: a time  7:30  is converted to decimal 30 and then to value 1E
########################################################################################
sub time2quaters($) {
 my ($h,$m) = split(":", shift);
  $m = 0 if(!$m);
  $h = 0 if(!$h);
  my $num = $h*4 +  int($m/15);
  return (sprintf("%02X", $num));
}


####################################
#
# THZ_replacebytes - replaces bytes in string
#
# parameters: string, bytes to be searched, replacing bytes 
# retunrns changed string
#
########################################################################################
sub THZ_replacebytes($$$) {
  my ($stringa, $find, $replace) = @_; 
  my $leng_str = length($stringa);
  my $leng_find = length($find);
  my $new_stringa ="";
  for(my $i = 0; $i < $leng_str; $i += 2) {
    if (substr($stringa, $i, $leng_find) eq $find){
      $new_stringa=$new_stringa . $replace;
      if ($leng_find == 4) {$i += 2;}
      }
    else {$new_stringa=$new_stringa . substr($stringa, $i, 2);};
  }
  return ($new_stringa);
}


## usage THZ_overwritechecksum("0100XX". $cmd."1003"); not needed anymore
sub THZ_overwritechecksum($) {
  my ($stringa) = @_;
  my $checksumadded=substr($stringa,0,4) . THZ_checksum($stringa) . substr($stringa,6);
  return($checksumadded);
}


####################################
#
# THZ_encodecommand - creates a telegram for the heatpump with a given command 
#
# usage THZ_encodecommand($cmd,"get") or THZ_encodecommand($cmd,"set");
# parameter string, 
# retunrns encoded string
#
########################################################################################

sub THZ_encodecommand($$) {
  my ($cmd,$getorset) = @_;
  my $header = "0100";
  $header = "0180" if ($getorset eq "set");	# "set" and "get" have differnt header
  my $footer ="1003";
  my $checksumadded=THZ_checksum($header . "XX" . $cmd . $footer) . $cmd;
  # each 2B byte must be completed by byte 18
  # each 10 byte must be repeated (duplicated)
  my $find = "10";
  my $replace = "1010";
  #$checksumadded =~ s/$find/$replace/g; #problems in 1% of the cases, in middle of a byte
  $checksumadded=THZ_replacebytes($checksumadded, $find, $replace);
  $find = "2B";
  $replace = "2B18";
  #$checksumadded =~ s/$find/$replace/g;
  $checksumadded=THZ_replacebytes($checksumadded, $find, $replace);
  return($header. $checksumadded .$footer);
}





####################################
#
# THZ_decode -	decodes a telegram from the heatpump -- no parsing here
#
# Each response has the same structure as request - header (four bytes), optional data and footer:
#   Header: 01
#    Read/Write: 00 for Read (get) response, 80 for Write (set) response; when some error occured, then device stores error code here; actually, I know only meaning of error 03 = unknown command
#    Checksum: ? 1 byte - the same algorithm as for request
#    Command: ? 1 byte - should match Request.Command
#    Data: ? only when Read, length depends on data type
#    Footer: 10 03
#
########################################################################################

sub THZ_decode($) {
  my ($message_orig) = @_;
  #  raw data received from device have to be de-escaped before header evaluation and data use:
  # - each sequece 2B 18 must be replaced with single byte 2B
  # - each sequece 10 10 must be replaced with single byte 10
    my $find = "1010";
    my $replace = "10";
    $message_orig=THZ_replacebytes($message_orig, $find, $replace);
    $find = "2B18";
    $replace = "2B";
    $message_orig=THZ_replacebytes($message_orig, $find, $replace);
  #check header and if ok 0100, check checksum and return the decoded msg
  if ("0100" eq substr($message_orig,0,4)) {
    if (THZ_checksum($message_orig) eq substr($message_orig,4,2)) {
        $message_orig =~ /0100(.*)1003/; 
        my $message = $1;
        return (undef, $message)
    }
    else {return (THZ_checksum($message_orig) . "crc_error", $message_orig)}; }

  if ("0103" eq substr($message_orig,0,4)) { return (" command not known", $message_orig)}; 

  if ("0102" eq substr($message_orig,0,4)) {  return (" CRC error in request", $message_orig)}
  else {return (" new error code " , $message_orig);}; 
}

########################################################################################
#
# THZ_Parse -0A01
#
########################################################################################
	
sub THZ_Parse($) {
  my ($message) = @_;
  given (substr($message,2,2)) {
  when ("0A")    {
      if     (substr($message,4,2) eq "01")					{$message = hex(substr($message, 8,2))} 						      # the answer look like  0A0120-3A0A01200E00  for year 14
      elsif ((substr($message,4,2) eq "1D") or (substr($message,4,2) eq "17")) 	{$message = quaters2time(substr($message, 8,2)) ."--". quaters2time(substr($message, 10,2))}  #value 1Ch 28dec is 7 ; value 1Eh 30dec is 7:30  
      elsif (substr($message,4,4) eq "05D1") 				 	{$message = quaters2time(substr($message, 10,2)) ."--". quaters2time(substr($message, 8,2))}  #like above but before stop then start !!!!
      elsif  ((substr($message,4,4) eq "05D3") or (substr($message,4,4) eq "05D4"))   		{$message = quaters2time(substr($message, 10,2)) }  #value 1Ch 28dec is 7 
      elsif  ((substr($message,4,3) eq "056")  or (substr($message,4,3) eq "057"))		{$message = hex(substr($message, 8,4))}
      else 										{$message = hex2int(substr($message, 8,4))/10 ." °C" }
  }  
  when ("0B")    {							   #set parameter HC1
      if (substr($message,4,2) eq "14")  {$message = quaters2time(substr($message, 8,2)) ."--". quaters2time(substr($message, 10,2))}  #value 1Ch 28dec is 7 ; value 1Eh 30dec is 7:30
      else 				 {$message = hex2int(substr($message, 8,4))/10 ." °C"  }
  }
  when ("0C")    {							   #set parameter HC2
      if (substr($message,4,2) eq "15")  {$message = quaters2time(substr($message, 8,2)) ."--". quaters2time(substr($message, 10,2))}  #value 1Ch 28dec is 7 ; value 1Eh 30dec is 7:30
      else 				 {$message = hex2int(substr($message, 8,4))/10 ." °C"  }
  }
  when ("F4")    {                     #allF4
    $message = 	 
        	"x08: " 			. hex2int(substr($message, 8,4))/10 . " " .
        	"x12: "				. hex2int(substr($message,12,4))/10 . " " .
        	"x16: "				. hex2int(substr($message,16,4))/10 . " " .
        	"x20: " 			. hex2int(substr($message,20,4))/10 . " " .
        	"x24: "				. hex2int(substr($message,24,4))/10 . " " .
		"x28: "				. hex2int(substr($message,28,4))/10 . " " .
        	"x32: "				. hex2int(substr($message,32,4))/10 . " " .
        	"x36: "				. hex2int(substr($message,36,4))/10 . " " .
        	"x40: "				. hex2int(substr($message,40,4))/10 . " " .
		"x44: "				. hex2int(substr($message,44,4))/10 . " " .
		"x48: " 			. hex2int(substr($message,48,4))/10 . " " .
        	"x52: "				. hex2int(substr($message,52,4))/10 . " " .
        	"x56: "				. hex2int(substr($message,56,4))/10 . " " .
        	"x60: " 			. hex2int(substr($message,60,4))/10 . " " .
        	"x64: "				. hex2int(substr($message,64,4))/10 . " " .
		"x68: "				. hex2int(substr($message,68,4))/10 . " " .
        	"x72: "				. hex2int(substr($message,72,4))/10 . " " .
        	"x76: "				. hex2int(substr($message,76,4))/10 . " " .
        	"x80: "				. hex2int(substr($message,80,4))/10 ;
        	 }
  when ("FD")    {                     #firmware_ver
    $message = "version: " . hex(substr($message,4,4))/100 ;
  }
  when ("FC")    {                     #timedate 00 - 0F 1E 08 - 0D 03 0B
    my %weekday = ( "0" =>"Monday", "1" => "Tuesday", "2" =>"Wednesday", "3" => "Thursday", "4" => "Friday", "5" =>"Saturday", "6" => "Sunday" );
    $message = 	  "Weekday: "		. $weekday{hex(substr($message, 4,2))}    . " " .
            	  "Hour: " 		. hex(substr($message, 6,2)) . " Min: " . hex(substr($message, 8,2)) . " Sec: " . hex(substr($message,10,2)) . " " .
              	  "Date: " 		. (hex(substr($message,12,2))+2000)  .	"/"		. hex(substr($message,14,2)) . "/"		. hex(substr($message,16,2));
  }
  when ("FB")    {                     #allFB
    $message =
        	  "outside_temp: " 				. hex2int(substr($message, 8,4))/10 . " " .
        	  "flow_temp: "					. hex2int(substr($message,12,4))/10 . " " .  #Vorlauf Temperatur
        	  "return_temp: "				. hex2int(substr($message,16,4))/10 . " " .  #Rücklauf Temperatur
        	  "hot_gas_temp: " 				. hex2int(substr($message,20,4))/10 . " " .  #Heißgas Temperatur		
        	  "dhw_temp: "					. hex2int(substr($message,24,4))/10 . " " .  #Speicher Temperatur current cilinder water temperature
        	  "flow_temp_HC2: "				. hex2int(substr($message,28,4))/10 . " " .  #Vorlauf TemperaturHK2
		  "evaporator_temp: "				. hex2int(substr($message,36,4))/10 . " " .  #Speicher Temperatur
        	  "condenser_temp: "				. hex2int(substr($message,40,4))/10 . " " .
        	  "Mixer_open: "				. ((hex(substr($message,44,1)) &  0b0001) / 0b0001) . " " .
		  "Mixer_closed: "				. ((hex(substr($message,44,1)) &  0b0010) / 0b0010) . " " .
		  "HeatPipeValve: "				. ((hex(substr($message,44,1)) &  0b0100) / 0b0100) . " " .
		  "DiverterValve: "				. ((hex(substr($message,44,1)) &  0b1000) / 0b1000) . " " .
		  "DHW_Pump: "					. ((hex(substr($message,45,1)) &  0b0001) / 0b0001) . " " .
		  "HeatingCircuit_Pump: "			. ((hex(substr($message,45,1)) &  0b0010) / 0b0010) . " " .
		  "Solar_Pump: "				. ((hex(substr($message,45,1)) &  0b1000) / 0b1000) . " " .
		  "Compressor: "				. ((hex(substr($message,46,1)) &  0b1000) / 0b1000) . " " .
		  "BoosterStage3: "				. ((hex(substr($message,47,1)) &  0b0001) / 0b0001) . " " .
		  "BoosterStage2: "				. ((hex(substr($message,47,1)) &  0b0010) / 0b0010) . " " .
		  "BoosterStage1: "				. ((hex(substr($message,47,1)) &  0b0100) / 0b0100). " " .
		  "HighPressureSensor: "			. ((hex(substr($message,48,1)) &  0b0001) / 0b0001). " " .  #P1 	inverterd?
		  "LowPressureSensor: "				. ((hex(substr($message,48,1)) &  0b0010) / 0b0010). " " .  #P3  inverterd?
		  "EvaporatorIceMonitor: "			. ((hex(substr($message,48,1)) &  0b0100) / 0b0100). " " .  #N3
		  "SignalAnode: "				. ((hex(substr($message,48,1)) &  0b1000) / 0b1000). " " .  #S1
		  "EVU_release: "				. ((hex(substr($message,49,1)) &  0b0001) / 0b0001). " " .  
		  "OvenFireplace: "				. ((hex(substr($message,49,1)) &  0b0010) / 0b0010). " " .  
		  "STB: "					. ((hex(substr($message,49,1)) &  0b0100) / 0b0100). " " .  	
		  "OutputVentilatorPower: "			. hex(substr($message,50,4))/10  . " " .
        	  "InputVentilatorPower: " 			. hex(substr($message,54,4))/10  . " " .
        	  "MainVentilatorPower: "			. hex(substr($message,58,4))/10  . " " .
        	  "OutputVentilatorSpeed: "			. hex(substr($message,62,4))/1  	. " " .  # m3/h
        	  "InputVentilatorSpeed: " 			. hex(substr($message,66,4))/1  	. " " .  # m3/h
        	  "MainVentilatorSpeed: "			. hex(substr($message,70,4))/1  	. " " .  # m3/h
                  "Outside_tempFiltered: "			. hex2int(substr($message,74,4))/10     . " " .
                  "Rel_humidity: "				. hex2int(substr($message,78,4))/10  	 . " " .
		  "DEW_point: "					. hex2int(substr($message,86,4))/1     . " " .
		  "P_Nd: "					. hex2int(substr($message,86,4))/100     . " " .	#bar
		  "P_Hd: "					. hex2int(substr($message,90,4))/100     . " " .  #bar
		  "Actual_power_Qc: "				. hex2int(substr($message,94,8))/1     . " " .	#kw
		  "Actual_power_Pel: "				. hex2int(substr($message,102,4))/1     . " " .	#kw
		  "collector_temp: " 				. hex2int(substr($message, 4,4))/10 ;
  }
  when ("F5")    {                     #unknownF5
    $message =    $message                . "\n" .
                  substr($message, 18,6)  . "\n" .
                  substr($message, 6,6)   . "\n"  ;
  }
  when ("09")    {                     #operating history
    $message =    "compressor_heating: "	. hex(substr($message, 4,4))    . " " .
                  "compressor_cooling: "	. hex(substr($message, 8,4))    . " " .
                  "compressor_dhw: "		. hex(substr($message, 12,4))    . " " .
                  "booster_dhw: "		. hex(substr($message, 16,4))    . " " .
                  "booster_heating: "		. hex(substr($message, 20,4))   ;			
  }
  when ("D1")    {                     #last10errors non testato e dte non convertita
    $message =    "number_of_faults: "		. hex(substr($message, 4,4))    . " " .
                  "fault0CODE: "		. hex(substr($message, 8,4))    . " " .
                  "fault0TIME: "		. hex(substr($message, 12,2)) 	. ":" . hex(substr($message, 14,2))  . " " .
                  "fault0DATE: "		. hex(substr($message, 16,4))   . " " .
		  "fault1CODE: "		. hex(substr($message, 20,4))   . " " .
                  "fault1TIME: "		. hex(substr($message, 24,2)) 	. ":" . hex(substr($message, 26,2))  . " " .
                  "fault1DATE: "		. hex(substr($message, 28,4))   . " " .
		  "fault2CODE: "		. hex(substr($message, 32,4))   . " " .
                  "fault2TIME: "		. hex(substr($message, 36,2)) 	. ":" . hex(substr($message, 38,2))  . " " .
                  "fault2DATE: "		. hex(substr($message, 40,4))   . " " .
		  "fault3CODE: "		. hex(substr($message, 44,4))   . " " .
                  "fault3TIME: "		. hex(substr($message, 48,2)) 	. ":" . hex(substr($message, 50,2))  . " " .
                  "fault3DATE: "		. hex(substr($message, 52,4))   . " " .
		  "fault4CODE: "		. hex(substr($message, 56,4))   . " " .
                  "fault4TIME: "		. hex(substr($message, 60,2)) 	. ":" . hex(substr($message, 62,2))  . " " .
                  "fault4DATE: "		. hex(substr($message, 64,4))   . " " .
		  "fault5CODE: "		. hex(substr($message, 68,4))   . " " .
                  "fault5TIME: "		. hex(substr($message, 72,2)) 	. ":" . hex(substr($message, 72,2))  . " " .
                  "fault5DATE: "		. hex(substr($message, 76,4))   . " " .
		  "fault6CODE: "		. hex(substr($message, 80,4))   . " " .
                  "fault6TIME: "		. hex(substr($message, 84,2)) 	. ":" . hex(substr($message, 86,2))  . " " .
                  "fault6DATE: "		. hex(substr($message, 88,4))   ;			
  }    
  }
  return (undef, $message);
}


#######################################
#THZ_Parse1($) could be used in order to test an external config file; I do not know if I want it
#
#######################################

sub THZ_Parse1($) {
my %parsinghash = (
        "D1"       => {"number_of_faults:" => [4,"hex",1],                                 
		        "fault0CODE:"      => [8,"hex",1],
			"fault0DATE:"      => [12,"hex",1]  
                    },
	"D2"       => {"number_of_faults:" => [8,"hex",1],                              
			"fault0CODE:"      => [8,"hex",1]              
                    }
);

  my ($Msg) = @_;
  my $parsingcmd = $parsinghash{substr($Msg,2,2)};   
  my $ParsedMsg = $Msg;
  if(defined($parsingcmd)) {
    $ParsedMsg = "";
    foreach  my $parsingkey  (keys %$parsingcmd) {
      my $positionInMsg = $parsingcmd->{$parsingkey}[0];
      my $Type = $parsingcmd->{$parsingkey}[1];
      my $divisor = $parsingcmd->{$parsingkey}[2];
      my $value = substr($Msg, $positionInMsg ,4);
      given ($Type) {
        when ("hex")    { $value= hex($value);}
        when ("hex2int")    { $value= hex($value);}
        }
    $ParsedMsg = $ParsedMsg ." ". $parsingkey ." ". $value/$divisor ; 
    }
  }
  return (undef, $ParsedMsg);
}





########################################################################################
# only for debug
#
########################################################################################
sub THZ_debugread($){
  my ($hash) = @_;
  my ($err, $msg) =("", " ");
  #my @numbers=('01', '09', '0B0005', '0B0008', '0C0005','0C0008','0A0013', '16', 'D1', 'D2', 'E8', 'E9', 'F2', 'F3', 'F4', 'F5', 'F6', 'FB', 'FC', 'FD', 'FE');
 # my @numbers=('0B14A2', '0B54A2', '0B2000', '0B2010', '0C2000','0A2008','0A3010', '0B54A2', '0B64A2', '0B7000', '0B8010', '0C8000','0A8008','0A9010');
 
  #my @numbers = (1..255);
  my @numbers = (1..65535);
  my $indice= "FF";
  unlink("data.txt"); #delete  debuglog
  foreach $indice(@numbers) {	
    #my $cmd = sprintf("%02X", $indice);
    my $cmd = "0A" . sprintf("%04X",  $indice);
    #my $cmd = $indice;
    # STX start of text
    THZ_Write($hash,  "02");
    ($err, $msg) = THZ_ReadAnswer($hash);  
    # send request
    my $cmdHex2 = THZ_encodecommand($cmd,"get"); 
    THZ_Write($hash,  $cmdHex2);
    ($err, $msg) = THZ_ReadAnswer($hash);
    # ack datatranfer and read from the heatpump        
    THZ_Write($hash,  "10");
    ($err, $msg) = THZ_ReadAnswer($hash);
    THZ_Write($hash,  "10");
    
    #my $activatetrigger =1;
	#	  readingsSingleUpdate($hash, $cmd, $msg, $activatetrigger);
	#	  open (MYFILE, '>>data.txt');
	#	  print MYFILE ($cmdHex2 . "-" . $msg . "\n");
	#	  close (MYFILE); 
    
    if (defined($err))  {return ($msg ."\n" . $err);}
    else {   #clean up and remove footer and header
	($err, $msg) = THZ_decode($msg);
	if (defined($err)) {$msg=$cmdHex2 ."-". $msg ."-". $err;} 
		  my $activatetrigger =1;
		 # readingsSingleUpdate($hash, $cmd, $msg, $activatetrigger);
		  open (MYFILE, '>>data.txt');
		  print MYFILE ($cmd . "-" . $msg . "\n");
		  close (MYFILE); 
    }    
    select(undef, undef, undef, 0.2); #equivalent to sleep 200ms
  }
}


sub THZ_Undef($$) {
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  foreach my $d (sort keys %defs) {
    if(defined($defs{$d}) &&
       defined($defs{$d}{IODev}) &&
       $defs{$d}{IODev} == $hash)
      {
        my $lev = ($reread_active ? 4 : 2);
        Log GetLogLevel($name,$lev), "deleting port for $d";
        delete $defs{$d}{IODev};
      }
  }
  DevIo_CloseDev($hash); 
  return undef;
}

1;

=pod
=begin html

<a name="THZ"></a>
<h3>THZ</h3>
<ul>
  THZ module: comunicate through serial interface (eg /dev/ttyxx) or through ser2net (e.g 10.0.x.x:5555) with a Tecalor/Eltron heatpump. <br>
   Tested on a THZ303 (with serial speed 57600) and a THZ403 (with serial speed 115200) with the same Firmware 4.39. <br>
   Tested on fritzbox, nas-qnap, raspi and macos.<br>
   This module is not working if you have an older firmware; Nevertheless, "parsing" could be easily updated, because now the registers are well described.
  https://answers.launchpad.net/heatpumpmonitor/+question/100347  <br>
   Implemented: read of status parameters and read/write of configuration parameters.
  <br><br>

  <a name="THZdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; THZ &lt;device&gt;</code> <br>
    <br>
    <code>device</code> can take the same parameters (@baudrate, @directio,
    TCP/IP, none) like the <a href="#CULdefine">CUL</a>,  e.g  57600 baud or 115200.<br>
    Example:
    direct connection   
    <ul><code>
      define Mytecalor 			THZ   /dev/ttyUSB0@115200<br>
      </code></ul>
      or network connection (like via ser2net)<br>
      <ul><code>
      define Myremotetecalor  	THZ  192.168.0.244:2323 
    </code></ul>
    <br>
      <ul><code>
      define Mythz THZ /dev/ttyUSB0@115200 <br>
      attr Mythz interval_allFB 300      # internal polling interval 5min  <br>
      attr Mythz interval_history 28800  # internal polling interval 8h    <br>
      define FileLog_Mythz FileLog ./log/Mythz-%Y.log Mythz <br>
      </code></ul>
     <br> 
   If the attributes interval_allFB and interval_history are not defined (or 0), their internal polling is disabled.  
   Clearly you can also define the polling interval outside the module with the "at" command.
    <br>
      <ul><code>
      define Mythz THZ /dev/ttyUSB0@115200 <br>
      define atMythzFB at +*00:05:00 {fhem "get Mythz allFB","1";;return()}    <br>
      define atMythz09 at +*08:00:00 {fhem "get Mythz history","1";;return()}   <br>
      define FileLog_Mythz FileLog ./log/Mythz-%Y.log Mythz <br>
      </code></ul>
      
  </ul>
  <br>
</ul>
 
=end html
=cut


