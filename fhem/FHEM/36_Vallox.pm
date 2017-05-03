# $Id$

###############################################################
#
# @File36_Vallox.pm
#
# @Author Skjall
# @Created 21.07.2016 10:18:23
#
#  The modul reads and writes parameters via RS485 from and to a Vallox
#  ventilation bus.
#
#  This module was made possible by Heinz from mysensors Community
#  (https://forum.mysensors.org/user/heinz). His insights to the 
#  Vallox bus were nessecary to make this script. - Thanks!
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
#  MERCHANTABILITY || FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
#
################################################################

##############################################
package main;
use strict;
use warnings;

##############################################
# Global Variables
##############################################

##################################
# List of Datatyps of the Vallox bus
##################################
my %Vallox_datatypes = (
    "06" => "FanSpeed-Relays",
    "07" => "MultiPurpose1",
    "08" => "MultiPurpose2",

	
    "29" => "FanSpeed",
    "2A" => "Humidity",
    "2B" => "CO2High",
    "2C" => "CO2Low",
    "2D" => "MachineInstalledCO2Sensors",
    "2E" => "CurrentVoltageIncomingOnMachine",

    "2F" => "HumiditySensor1",
    "30" => "HumiditySensor2",

    "32" => "TempOutside",
    "33" => "TempExhaust",
    "34" => "TempInside",
    "35" => "TempIncoming",
    "36" => "LastSystemFault",

    "55" => "PostHeatingOnCounter",
    "56" => "PostHeatingOffTime",
    "57" => "PostHeatingTargetValue",

    "6C" => "Flags1",
    "6D" => "Flags2",
    "6E" => "Flags3",
    "6F" => "Flags4",
    "70" => "Flags5",
    "71" => "Flags6",

    "79" => "FireplaceBoosterCountdownMinutes",
           
    "8F" => "ResumeBus",
    "91" => "SuspendBusForCO2Communication",
           
    "A3" => "Select",
    "A4" => "HeatingSetPoint",
    "A5" => "FanSpeedMax",
    "A6" => "ServiceReminderMonths",
    "A7" => "PreheatingSetPoint",
    "A8" => "InputFanStopTemperatureThreshold",
    "A9" => "FanSpeedMin",
    "AA" => "Program",
    "AB" => "MaintencanceCountdownMonths",
           
    "AE" => "BasicHumidityLevel",
    "AF" => "HeatRecoveryCellBypassSetpointTemperature",
    "B0" => "DCFanInputAdjustment",
    "B1" => "DCFanOutputAdjustment",
    "B2" => "CellDefrostingSetpointTemperature",
    "B3" => "CO2SetPointUpper",
    "B4" => "CO2SetPointLower",
    "B5" => "Program2",
	
    "C0" => "Initial1",
    "C6" => "Initial2",
    "C7" => "Initial3",
    "C8" => "Initial4",
    "C9" => "Initial5",
);
 my %Vallox_datatypesReverse = reverse %Vallox_datatypes;

##################################
# Mapping of the fan speeds
##################################
my %Vallox_fanSpeedTable = (
"01" => "1",
"03" => "2",
"07" => "3",
"0F" => "4",
"1F" => "5",
"3F" => "6",
"7F" => "7",
"FF" => "8",
);
my %Vallox_fanSpeedTableReverse = reverse %Vallox_fanSpeedTable;

##################################
# Mapping of the temperatures
##################################
my %Vallox_temperatureTable = (
"00" => "-74", "01" => "-70", "02" => "-66", "03" => "-62", "04" => "-59", "05" => "-56", "06" => "-54", "07" => "-52",
"08" => "-50", "09" => "-48", "0A" => "-47", "0B" => "-46", "0C" => "-44", "0D" => "-43", "0E" => "-42", "0F" => "-41",
"10" => "-40", "11" => "-39", "12" => "-38", "13" => "-37", "14" => "-36", "15" => "-35", "16" => "-34", "17" => "-33",
"18" => "-33", "19" => "-32", "1A" => "-31", "1B" => "-30", "1C" => "-30", "1D" => "-29", "1E" => "-28", "1F" => "-28",
"20" => "-27", "21" => "-27", "22" => "-26", "23" => "-25", "24" => "-25", "25" => "-24", "26" => "-24", "27" => "-23",
"28" => "-23", "29" => "-22", "2A" => "-22", "2B" => "-21", "2C" => "-21", "2D" => "-20", "2E" => "-20", "2F" => "-19",
"30" => "-19", "31" => "-19", "32" => "-18", "33" => "-18", "34" => "-17", "35" => "-17", "36" => "-16", "37" => "-16",
"38" => "-16", "39" => "-15", "3A" => "-15", "3B" => "-14", "3C" => "-14", "3D" => "-14", "3E" => "-13", "3F" => "-13",
"40" => "-12", "41" => "-12", "42" => "-12", "43" => "-11", "44" => "-11", "45" => "-11", "46" => "-10", "47" => "-10",
"48" => "-9", "49" => "-9", "4A" => "-9", "4B" => "-8", "4C" => "-8", "4D" => "-8", "4E" => "-7", "4F" => "-7",
"50" => "-7", "51" => "-6", "52" => "-6", "53" => "-6", "54" => "-5", "55" => "-5", "56" => "-5", "57" => "-4",
"58" => "-4", "59" => "-4", "5A" => "-3", "5B" => "-3", "5C" => "-3", "5D" => "-2", "5E" => "-2", "5F" => "-2",
"60" => "-1", "61" => "-1", "62" => "-1", "63" => "-1", "64" => "0", "65" => "0", "66" => "0", "67" => "1",
"68" => "1", "69" => "1", "6A" => "2", "6B" => "2", "6C" => "2", "6D" => "3", "6E" => "3", "6F" => "3",
"70" => "4", "71" => "4", "72" => "4", "73" => "5", "74" => "5", "75" => "5", "76" => "5", "77" => "6",
"78" => "6", "79" => "6", "7A" => "7", "7B" => "7", "7C" => "7", "7D" => "8", "7E" => "8", "7F" => "8",
"80" => "9", "81" => "9", "82" => "9", "83" => "10", "84" => "10", "85" => "10", "86" => "11", "87" => "11",
"88" => "11", "89" => "12", "8A" => "12", "8B" => "12", "8C" => "13", "8D" => "13", "8E" => "13", "8F" => "14",
"90" => "14", "91" => "14", "92" => "15", "93" => "15", "94" => "15", "95" => "16", "96" => "16", "97" => "16",
"98" => "17", "99" => "17", "9A" => "18", "9B" => "18", "9C" => "18", "9D" => "19", "9E" => "19", "9F" => "19",
"A0" => "20", "A1" => "20", "A2" => "21", "A3" => "21", "A4" => "21", "A5" => "22", "A6" => "22", "A7" => "22",
"A8" => "23", "A9" => "23", "AA" => "24", "AB" => "24", "AC" => "24", "AD" => "25", "AE" => "25", "AF" => "26",
"B0" => "26", "B1" => "27", "B2" => "27", "B3" => "27", "B4" => "28", "B5" => "28", "B6" => "29", "B7" => "29",
"B8" => "30", "B9" => "30", "BA" => "31", "BB" => "31", "BC" => "32", "BD" => "32", "BE" => "33", "BF" => "33",
"C0" => "34", "C1" => "34", "C2" => "35", "C3" => "35", "C4" => "36", "C5" => "36", "C6" => "37", "C7" => "37",
"C8" => "38", "C9" => "38", "CA" => "39", "CB" => "40", "CC" => "40", "CD" => "41", "CE" => "41", "CF" => "42",
"D0" => "43", "D1" => "43", "D2" => "44", "D3" => "45", "D4" => "45", "D5" => "46", "D6" => "47", "D7" => "48",
"D8" => "49", "D9" => "49", "DA" => "50", "DB" => "51", "DC" => "52", "DD" => "53", "DE" => "53", "DF" => "54",
"E0" => "55", "E1" => "56", "E2" => "57", "E3" => "59", "E4" => "60", "E5" => "61", "E6" => "62", "E7" => "63",
"E8" => "65", "E9" => "66", "EA" => "68", "EB" => "69", "EC" => "71", "ED" => "73", "EE" => "75", "EF" => "77",
"F0" => "79", "F1" => "81", "F2" => "82", "F3" => "86", "F4" => "90", "F5" => "93", "F6" => "97", "F7" => "100",
"F8" => "100", "F9" => "100", "FA" => "100", "FB" => "100", "FC" => "100", "FD" => "100", "FE" => "100", "FF" => "100"  
);
my %Vallox_temperatureTableReverse = reverse %Vallox_temperatureTable;


##################################
# Mapping of the percentages (eg humidity)
##################################
my %Vallox_percentageTable = (
"34" => "0",  "36" => "1",  "38" => "2",  "3A" => "3",  "3C" =>  "4", "3E" =>  "5", "40" => "6",  "42" => "7",  "44" => "8",  "46" => "9",
"48" => "10", "4A" => "11", "4C" => "12", "4E" => "13", "50" => "14", "52" => "15", "54" => "16", "56" => "17", "58" => "18", "5A" => "19",
"5C" => "20", "5E" => "21", "60" => "22", "62" => "23", "64" => "24", "66" => "25", "68" => "26", "6A" => "27", "6C" => "28", "6E" => "29",
"70" => "30", "72" => "31", "74" => "32", "76" => "33", "78" => "34", "7A" => "35", "7C" => "36", "7E" => "37", "80" => "38", "82" => "39",
"84" => "40", "86" => "41", "88" => "42", "8A" => "43", "8C" => "44", "8E" => "45", "90" => "46", "92" => "47", "94" => "48", "96" => "49",
"98" => "50", "9A" => "51", "9C" => "52", "9E" => "53", "A0" => "54", "A2" => "55", "A4" => "56", "A6" => "57", "A8" => "58", "AA" => "59",
"AC" => "60", "AE" => "61", "B0" => "62", "B2" => "63", "B4" => "64", "B6" => "65", "B8" => "66", "BA" => "67", "BC" => "68", "BE" => "69",
"C0" => "70", "C2" => "71", "C4" => "72", "C6" => "73", "C8" => "74", "CA" => "75", "CC" => "76", "CE" => "77", "D0" => "78", "D2" => "79",
"D4" => "80", "D6" => "81", "D8" => "82", "DA" => "83", "DC" => "84", "DE" => "85", "E0" => "86", "E2" => "87", "E4" => "88", "E6" => "89",
"E8" => "90", "EA" => "91", "EC" => "92", "EE" => "93", "F0" => "94", "F2" => "95", "F4" => "96", "F6" => "97", "F8" => "98", "FA" => "99",
"FC" => "100"
);
my %Vallox_percentageTableReverse = reverse %Vallox_percentageTable;

##################################
# Mapping of the faults
##################################
my %Vallox_faultTable = (
"00" => "No fault stored",
"05" => "Supply air temperature sensor fault",
"06" => "Carbon dioxide alarm",
"07" => "Outdoor air sensor fault",
"08" => "Extract air sensor fault",
"09" => "Water radiator danger of freezing",
"0A" => "Exhaust air sensor fault",

);
my %Vallox_faultTableReverse = reverse %Vallox_faultTable;


##################################
# Initialize Buffer fillings
##################################
my $bufferTemp = "00";
my $bufferRead = "00";

##################################
# basic get commands
##################################
my %Vallox_gets = (
    "raw"               => "raw"
);

##################################
# basic set commands
##################################
my %Vallox_sets = (
    "raw"       => "raw"
);

##############################################
# Custom Functions
##############################################

##################################
# Create a valid message to send
##################################
sub Vallox_CreateMsg ($@)
{
	my ($hash, $readingIdentifier) = @_;
	
	my $domain = hex "0x".AttrVal($hash->{NAME}, "ValloxIDDomain", "01");		# Domain (1 by default)
	my $sender = hex "0x".AttrVal($hash->{NAME}, "ValloxIDFHEM", "22");			# ID of this FHEM
	my $receiver = hex "0x".AttrVal($hash->{NAME}, "ValloxIDCentral", "11"); 	# ID of the central
	
	my $datatype = hex "0x".$readingIdentifier;
	my $checksum = ($domain + $sender + $receiver + $datatype) % 0x100;
	
	my $msg = lc(sprintf("%02x", $domain).sprintf("%02x", $sender).sprintf("%02x", $receiver)."00".sprintf("%02x", $datatype).sprintf("%02x", $checksum));
		
	return $msg;
}

##############################################
# Check if a message is valid
##############################################
sub Vallox_ValidateStream ($@)
{
	my ($hash, @a) = @_;
    my $name = shift @a;
	
	return undef if (length($bufferRead) < 12);
	
	my $domain = hex "0x".substr($bufferRead,0,2);
	my $sender = hex "0x".substr($bufferRead,2,2);
	my $receiver = hex "0x".substr($bufferRead,4,2);
	my $data_1 = hex "0x".substr($bufferRead,6,2);
	my $data_2 = hex "0x".substr($bufferRead,8,2);
	
	my $checksum = ($domain + $sender + $receiver + $data_1 + $data_2) % 0x100;
	
	if (lc($domain) eq 01 && lc(sprintf("%02x", $domain).sprintf("%02x", $sender).sprintf("%02x", $receiver).sprintf("%02x", $data_1).sprintf("%02x", $data_2).sprintf("%02x", $checksum)) eq lc($bufferRead)) {
		#Log3 ($name, 5, "Vallox: Debug: DO ".$domain." - SE ".$sender." - RE ".$receiver." - D1 ".$data_1." - D2 ".$data_2." - CS ".$checksum." NE ".$bufferRead);
		return 1;
	} else {
		#Log3 ($name, 5, "Vallox: Debug: DO ".$domain." - SE ".$sender." - RE ".$receiver." - D1 ".$data_1." - D2 ".$data_2." - CS ".$checksum." NE ".$bufferRead);
		return 0;
	}
		

}

##############################################
# Default Functions
##############################################
##################################
sub
Vallox_Initialize($)
{
    my ($hash) = @_;

    require "$attr{global}{modpath}/FHEM/DevIo.pm";

	
    $hash->{DefFn}      = "Vallox_Define";
    $hash->{UndefFn}    = "Vallox_Undef";
    $hash->{DeleteFn}   = "Vallox_Delete";
    $hash->{SetFn}      = "Vallox_Set";
    $hash->{GetFn}      = "Vallox_Get";
    $hash->{AttrFn}     = "Vallox_Attr";
#   $hash->{NotifyFn}   = "Vallox_Notify";
    $hash->{ReadFn}     = "Vallox_Read";
#   $hash->{ReadyFn}    = "Vallox_Ready";
    $hash->{ShutdownFn} = "Vallox_Shutdown";
	
	$hash->{AttrList}   = "ValloxIDDomain ValloxIDFHEM ValloxIDCentral ".$readingFnAttributes;

}

##################################
sub Vallox_Define($) {
    
    my ($hash, $def) = @_;
    my @a = split("[ \t][ \t]*", $def);
    if(@a != 3) {
        my $msg = "wrong syntax: define <name> Vallox devicename[\@baudrate] ";
        Log3 undef, 2, "Vallox: ".$msg;
        return $msg;
    }
    DevIo_CloseDev($hash);
    my $name = $a[0];
    my $dev = $a[2];
    
    $dev .= "\@9600" if( $dev !~ m/\@/ && $def !~ m/:/ );
    $hash-> {DeviceName} = $dev;
	
    my $ret = DevIo_OpenDev($hash, 0, undef);
    return $ret;
}

##################################
sub Vallox_Undef($$)    
{                     
	my ($hash, $name) = @_;       
	DevIo_CloseDev($hash);         
	RemoveInternalTimer($hash);    
	return undef;                  
}

##################################
sub Vallox_Delete($$)    
{                     
	my ( $hash, $name ) = @_;       

	return undef;
}


##################################
sub Vallox_Get($@)
{
    my ( $hash, @a ) = @_;
    return "\"get Vallox\" needs at least one argument" if ( @a < 2 );

    my $name = shift @a;
    my $cmd = shift @a;
    my $arg = shift @a;

	# "reading" is a predefined list of readings from the bus
	if ($cmd eq "reading") {
		
		my $argKey = $Vallox_datatypesReverse{$arg};
		my $msg = Vallox_CreateMsg ($hash,$argKey);
				
		DevIo_SimpleWrite ($hash,$msg,1);
		
		Log3 ($name, 3, "Vallox: Request ".$msg." has been sent.");
		return undef;
	
	# "update" shall be ask for all possible data.
	#    Not working at the moment. Need a new idea :(
	} elsif ($cmd eq "update"){
		
		while (my ($argKey, $argValue) = each %Vallox_datatypes) {
			my $msg = Vallox_CreateMsg ($hash,$argKey);
			DevIo_SimpleWrite ($hash,$msg,1);
		}
		return undef;
		
	# "raw is a custom Hex Code
	} elsif ($cmd eq "raw"){
		return "Usage: get $name raw {HexValue}" if (!defined ($arg) || $arg =~ m/[^a-fA-F0-9]{2}/);
		
		my $msg = Vallox_CreateMsg ($hash,$arg);
		
		DevIo_SimpleWrite ($hash,$msg,1);
		Log3 ($name, 3, "Vallox: Request ".$msg." has been sent.");
		
		return undef;
	} else {
		my $retmsg;
        my @commandList = keys %Vallox_gets;
		my $commandCount = keys %Vallox_gets;
		
        my @readingList = keys %Vallox_datatypesReverse;
		my $readingCount = keys %Vallox_datatypesReverse;
		
		
		$retmsg .= join(" ", @commandList) if ($commandCount > 0);
		$retmsg .= " reading:".join(",", sort @readingList) if ($readingCount > 0);
		
		## Ich kann nicht alle befehle bulken. ... :(
		# $retmsg .= " update:noArg";
		
		Log3 ($name, 2, "Vallox: Unknown argument $cmd.") if( $cmd ne '?' && $cmd ne '');
        return "Unknown argument $cmd, choose one of " . $retmsg;
	}
}

##################################
sub Vallox_Set($@)
{
    my ( $hash, @a ) = @_;
    return "\"set Vallox\" needs at least an argument" if ( @a < 2 );

	my $domain = hex "0x".AttrVal($hash->{NAME}, "ValloxIDDomain", "01");		# Domain (1 by default)
	my $sender = hex "0x".AttrVal($hash->{NAME}, "ValloxIDFHEM", "22");			# ID of this FHEM
	my $receiver = hex "0x".AttrVal($hash->{NAME}, "ValloxIDCentral", "11"); 	# ID of the central

    my $name = shift @a;
    my $cmd = shift @a;
    my $arg = shift @a;

    my $datatype;
    my $datavalue;
  
	my $setCommands;
	my @commandList = keys %Vallox_sets;
	my $commandCount = keys %Vallox_sets;
	
	$setCommands .= join(" ", @commandList) if ($commandCount > 0);
	$setCommands .= " FanSpeed:1,2,3,4,5,6,7,8";
	$setCommands .= " BasicHumidityLevel:slider,0,1,100";
	$setCommands .= " HeatRecoveryCellBypassSetpointTemperature:slider,0,1,20";
 ## TODO 
    if (exists $Vallox_datatypesReverse{$cmd}) {
        
        $datatype = hex "0x".$Vallox_datatypesReverse{$cmd};
		
		if ($datatype == 0x29) {
			$datavalue = hex "0x".$Vallox_fanSpeedTableReverse{$arg};
		} elsif ($datatype == 0xae) {
			$datavalue = hex "0x".$Vallox_percentageTableReverse{$arg};
		} elsif ($datatype == 0xaf) {
			$datavalue = hex "0x".$Vallox_temperatureTableReverse{$arg};
		}
        
    } elsif ($cmd eq "raw") {

        $datatype = hex "0x".substr($arg,0,2);
        $datavalue = hex "0x".substr($arg,2,2);

	} else {
		Log3 ($name, 2, "Vallox: Unknown argument $cmd.") if( $cmd ne '?' && $cmd ne '');
        return "Unknown argument $cmd, choose one of " . $setCommands;
	}
        
    my $checksum = ($domain + $sender + $receiver + $datatype + $datavalue) % 0x100;
    my $msg = lc(sprintf("%02x", $domain).sprintf("%02x", $sender).sprintf("%02x", $receiver).sprintf("%02x", $datatype).sprintf("%02x", $datavalue).sprintf("%02x", $checksum));

    DevIo_SimpleWrite ($hash,$msg,1);
	Log3 ($name, 3, "Vallox: Command ".$msg." has been sent.");
	
    return undef;
    
}

sub Vallox_Attr(@)
{
	my ($cmd,$name,$aName,$aVal) = @_;
  	# $cmd can be "del" || "set"
	# $name is device name
	# aName and aVal are Attribute name and value
	if ($cmd eq "set") {
		if ($aName eq "ValloxIDDomain" || $aName eq "ValloxIDFHEM" || $aName eq "ValloxIDCentral") {
			
			if ($aVal =~ m/[^a-fA-F0-9]/ || length($aVal) != 2) {
				Log3 $name, 2, "Vallox: Invalid HexValue in attr $name $aName $aVal: $@";
				return "Invalid HexValue $aVal";
			}
		}
	}
	return undef;
}

sub Vallox_Read($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $datagram;
    my $rawReadingType;
    my $rawReadingValue;
    my $rawReadingChecksum;
    my $singlereading = 1;
    
    my $fineReadingValue = 1;
    
    
    # read from serial device
    my $buf = DevIo_SimpleRead($hash);		
    return "" if ( !defined($buf) );
    
    # Convert read data to hex and fill buffer
    $bufferTemp = unpack ('H*', $buf);
    
    $bufferRead .= $bufferTemp;
	if (length($bufferRead) >= 14) {
		$bufferRead = substr($bufferRead,2,12);
	}
	
	if (Vallox_ValidateStream($hash)) {	
		Log3 ($name, 5, "Vallox: Buffer: ".$bufferRead);
		my $datagram = uc($bufferRead);
		    
		# get the type of the datagram
		$rawReadingType = substr($datagram,6,2);
		
		# get the value of the datagram
		$rawReadingValue = substr($datagram,8,2);
		
		# get the value of the datagram
		$rawReadingChecksum = substr($datagram,10,2);

		if ($rawReadingType ne "00") {

			# Decoding for the final readings. 
			# - rawReading... is the original information from the datagram
			# - fineReading... is the human readable information
			
			# Starting with the "One information in one datagram"-Section
			
			# Convert FanSpeeds by the Vallox_fanSpeedTable
			if ($rawReadingType eq "29" || $rawReadingType eq "A5" || $rawReadingType eq "A9") {
				$fineReadingValue = $Vallox_fanSpeedTable{$rawReadingValue};
				Log3 ($name, 4, "Vallox: Incoming Status-Info (FanSpeed): $datagram (Level $fineReadingValue)");
				
			# Convert Temperatures by the Vallox_temperatureTable
			} elsif ($rawReadingType eq "32" || $rawReadingType eq "33" || $rawReadingType eq "34" || $rawReadingType eq "35" || $rawReadingType eq "A4" ||  $rawReadingType eq "A7" ||  $rawReadingType eq "A8" || $rawReadingType eq "AF") {
				$fineReadingValue = $Vallox_temperatureTable{$rawReadingValue};
				Log3 ($name, 4, "Vallox: Incoming Status-Info (Temperature): $datagram ($fineReadingValue deg.)");
			
			# Convert Percentages by the Vallox_percentageTable
			} elsif ($rawReadingType eq "AE") {
				$fineReadingValue = $Vallox_percentageTable{$rawReadingValue};
				Log3 ($name, 4, "Vallox: Incoming Status-Info (Percentage): $datagram ($fineReadingValue pct.)");
			
			# Convert Faults by the Vallox_faultTable
			} elsif ($rawReadingType eq "36") {
				$fineReadingValue = $Vallox_faultTable{$rawReadingValue};
				Log3 ($name, 4, "Vallox: Incoming Status-Info (Fault): $datagram ($fineReadingValue)");
			
			# Convert Decimal Values
			} elsif ($rawReadingType eq "2B" || $rawReadingType eq "2C" || $rawReadingType eq "2E" || $rawReadingType eq "57" || $rawReadingType eq "A6"  || $rawReadingType eq "79" || $rawReadingType eq "8F" || $rawReadingType eq "91" || $rawReadingType eq "AB" || $rawReadingType eq "B0" || $rawReadingType eq "B1" || $rawReadingType eq "B3"  || $rawReadingType eq "B4") {
				$fineReadingValue = sprintf("%d", hex "0x".$rawReadingValue);
				Log3 ($name, 4, "Vallox: Incoming Status-Info (Decimal): $datagram ($fineReadingValue)");
				
			# Convert PostHeating Time Values
			} elsif ($rawReadingType eq "55" || $rawReadingType eq "56") {
				$fineReadingValue = sprintf("%d", hex "0x".$rawReadingValue)/2.5;
				Log3 ($name, 4, "Vallox: Incoming Status-Info (PostHeatingCounter): $datagram ($fineReadingValue)");
				
			# Convert CellDefrostingSetpointTemperature Values
			} elsif ($rawReadingType eq "B2") {
				$fineReadingValue = sprintf("%d", hex "0x".$rawReadingValue)/3;
				Log3 ($name, 4, "Vallox: Incoming Status-Info (CellDefrostingSetpointTemperature): $datagram ($fineReadingValue)");
				
			# Convert measured humidity by formula (if it is negative then you don't have a humidity sensor)
			} elsif ($rawReadingType eq "2A" || $rawReadingType eq "2F" || $rawReadingType eq "30") {
				$fineReadingValue = (sprintf("%d", hex "0x".$rawReadingValue)-51)/2.04;
				
				# Negative Humidity impossible: No Sensor attatched
				if ($fineReadingValue < 0) {
					Log3 ($name, 4, "Vallox: Incoming Status-Info (Humidity) invalid: $datagram ($fineReadingValue Perc. rH)");
					return;
				}
				
				Log3 ($name, 4, "Vallox: Incoming Status-Info (Humidity): $datagram ($fineReadingValue pct. rH)");
			
			# Starting with the "Up to eight informations in one datagram"-Section
			# Disabled lines are unused.
			
			# FanSpeed-Relays 
			} elsif ($rawReadingType eq "06") {
				
				my $bits = sprintf('%08b', hex("0x".$rawReadingValue));
								
				$singlereading = 0;
				readingsBeginUpdate($hash);
				readingsBulkUpdate($hash, "Speed1", substr($bits,0,1)) if (ReadingsVal($name,"Speed1","unknown") ne substr($bits,0,1));
				readingsBulkUpdate($hash, "Speed2", substr($bits,1,1)) if (ReadingsVal($name,"Speed2","unknown") ne substr($bits,1,1));
				readingsBulkUpdate($hash, "Speed3", substr($bits,2,1)) if (ReadingsVal($name,"Speed3","unknown") ne substr($bits,2,1));
				readingsBulkUpdate($hash, "Speed4", substr($bits,3,1)) if (ReadingsVal($name,"Speed4","unknown") ne substr($bits,3,1));
				readingsBulkUpdate($hash, "Speed5", substr($bits,4,1)) if (ReadingsVal($name,"Speed5","unknown") ne substr($bits,4,1));
				readingsBulkUpdate($hash, "Speed6", substr($bits,5,1)) if (ReadingsVal($name,"Speed6","unknown") ne substr($bits,5,1));
				readingsBulkUpdate($hash, "Speed7", substr($bits,6,1)) if (ReadingsVal($name,"Speed7","unknown") ne substr($bits,6,1));
				readingsBulkUpdate($hash, "Speed8", substr($bits,7,1)) if (ReadingsVal($name,"Speed8","unknown") ne substr($bits,7,1));
				readingsEndUpdate($hash, 1);
				
				Log3 ($name, 4, "Vallox: Incoming Status-Info (FanSpeed-Relays): $datagram (Bits $bits)");
				
			# MultiPurpose1
			} elsif ($rawReadingType eq "07") {
				
				my $bits = sprintf('%08b', hex("0x".$rawReadingValue));
				
				$singlereading = 0;
				readingsBeginUpdate($hash);
				#readingsBulkUpdate($hash, "", substr($bits,0,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,0,1));
				#readingsBulkUpdate($hash, "", substr($bits,1,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,1,1));
				#readingsBulkUpdate($hash, "", substr($bits,2,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,2,1));
				#readingsBulkUpdate($hash, "", substr($bits,3,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,3,1));
				#readingsBulkUpdate($hash, "", substr($bits,4,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,4,1));
				readingsBulkUpdate($hash, "PostHeating", substr($bits,5,1)) if (ReadingsVal($name,"PostHeating","unknown") ne substr($bits,5,1));
				#readingsBulkUpdate($hash, "", substr($bits,6,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,6,1));
				#readingsBulkUpdate($hash, "", substr($bits,7,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,7,1));
				readingsEndUpdate($hash, 1);
				
				Log3 ($name, 4, "Vallox: Incoming Status-Info (MultiPurpose1): $datagram (Bits $bits)");
			
			#MultiPurpose2
			} elsif ($rawReadingType eq "08") {
				
				my $bits = sprintf('%08b', hex("0x".$rawReadingValue));
				
				$singlereading = 0;
				readingsBeginUpdate($hash);
				#readingsBulkUpdate($hash, "", substr($bits,0,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,0,1));
				readingsBulkUpdate($hash, "DamperMotorPosition", substr($bits,1,1)) if (ReadingsVal($name,"DamperMotorPosition","unknown") ne substr($bits,1,1));
				readingsBulkUpdate($hash, "FaultSignalRelay", substr($bits,2,1)) if (ReadingsVal($name,"FaultSignalRelay","unknown") ne substr($bits,2,1));
				readingsBulkUpdate($hash, "SupplyFan", substr($bits,3,1)) if (ReadingsVal($name,"SupplyFan","unknown") ne substr($bits,3,1));
				readingsBulkUpdate($hash, "PreHeating", substr($bits,4,1)) if (ReadingsVal($name,"PreHeating","unknown") ne substr($bits,4,1));
				readingsBulkUpdate($hash, "ExhaustFan", substr($bits,5,1)) if (ReadingsVal($name,"ExhaustFan","unknown") ne substr($bits,5,1));
				readingsBulkUpdate($hash, "FireplaceBooster", substr($bits,6,1)) if (ReadingsVal($name,"FireplaceBooster","unknown") ne substr($bits,6,1));
				#readingsBulkUpdate($hash, "", substr($bits,7,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,7,1));
				readingsEndUpdate($hash, 1);
				
				Log3 ($name, 4, "Vallox: Incoming Status-Info (MultiPurpose2): $datagram (Bits $bits)");
			
			#MachineInstalledCO2Sensor 
			} elsif ($rawReadingType eq "2D") {
				
				my $bits = sprintf('%08b', hex("0x".$rawReadingValue));
				
				$singlereading = 0;
				readingsBeginUpdate($hash);
				#readingsBulkUpdate($hash, "", substr($bits,0,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,0,1));
				readingsBulkUpdate($hash, "CO2Sensor1", substr($bits,1,1)) if (ReadingsVal($name,"CO2Sensor1","unknown") ne substr($bits,1,1));
				readingsBulkUpdate($hash, "CO2Sensor2", substr($bits,2,1)) if (ReadingsVal($name,"CO2Sensor2","unknown") ne substr($bits,2,1));
				readingsBulkUpdate($hash, "CO2Sensor3", substr($bits,3,1)) if (ReadingsVal($name,"CO2Sensor3","unknown") ne substr($bits,3,1));
				readingsBulkUpdate($hash, "CO2Sensor4", substr($bits,4,1)) if (ReadingsVal($name,"CO2Sensor4","unknown") ne substr($bits,4,1));
				readingsBulkUpdate($hash, "CO2Sensor5", substr($bits,5,1)) if (ReadingsVal($name,"CO2Sensor5","unknown") ne substr($bits,5,1));
				#readingsBulkUpdate($hash, "", substr($bits,6,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,6,1));
				#readingsBulkUpdate($hash, "", substr($bits,7,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,7,1));
				readingsEndUpdate($hash, 1);
				
				Log3 ($name, 4, "Vallox: Incoming Status-Info (MultiPurpose2): $datagram (Bits $bits)");
				
			#Flags2
			} elsif ($rawReadingType eq "6D") {
				
				my $bits = sprintf('%08b', hex("0x".$rawReadingValue));
				
				$singlereading = 0;
				readingsBeginUpdate($hash);
				readingsBulkUpdate($hash, "CO2HigherSpeedRequest", substr($bits,0,1)) if (ReadingsVal($name,"CO2HigherSpeedRequest","unknown") ne substr($bits,0,1));
				readingsBulkUpdate($hash, "CO2LowerRatePublicInvitation", substr($bits,1,1)) if (ReadingsVal($name,"CO2LowerRatePublicInvitation","unknown") ne substr($bits,1,1));
				readingsBulkUpdate($hash, "HumidityLowerRatePublicInvitation ", substr($bits,2,1)) if (ReadingsVal($name,"HumidityLowerRatePublicInvitation","unknown") ne substr($bits,2,1));
				readingsBulkUpdate($hash, "SwitchLowerSpeedRequest", substr($bits,3,1)) if (ReadingsVal($name,"SwitchLowerSpeedRequest","unknown") ne substr($bits,3,1));
				#readingsBulkUpdate($hash, "", substr($bits,4,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,4,1));
				#readingsBulkUpdate($hash, "", substr($bits,5,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,5,1));
				readingsBulkUpdate($hash, "CO2Alarm", substr($bits,6,1)) if (ReadingsVal($name,"CO2Alarm","unknown") ne substr($bits,6,1));
				readingsBulkUpdate($hash, "FrostAlarmSensor", substr($bits,7,1)) if (ReadingsVal($name,"FrostAlarm","unknown") ne substr($bits,5,1));
				readingsEndUpdate($hash, 1);
				
				Log3 ($name, 4, "Vallox: Incoming Status-Info (Flags2): $datagram (Bits $bits)");
			
			#Flags4
			} elsif ($rawReadingType eq "6F") {
				
				my $bits = sprintf('%08b', hex("0x".$rawReadingValue));
				
				$singlereading = 0;
				readingsBeginUpdate($hash);
				#readingsBulkUpdate($hash, "", substr($bits,0,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,0,1));
				#readingsBulkUpdate($hash, "", substr($bits,1,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,1,1));
				#readingsBulkUpdate($hash, "", substr($bits,2,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,2,1));
				readingsBulkUpdate($hash, "FrostAlarmWaterRadiator", substr($bits,3,1)) if (ReadingsVal($name,"FrostAlarmWaterRadiator","unknown") ne substr($bits,3,1));
				#readingsBulkUpdate($hash, "", substr($bits,4,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,4,1));
				#readingsBulkUpdate($hash, "", substr($bits,5,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,5,1));
				#readingsBulkUpdate($hash, "", substr($bits,6,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,6,1));
				readingsBulkUpdate($hash, "MasterSlaveSelection", substr($bits,7,1)) if (ReadingsVal($name,"MasterSlaveSelection","unknown") ne substr($bits,5,1));
				readingsEndUpdate($hash, 1);
				
				Log3 ($name, 4, "Vallox: Incoming Status-Info (Flags4): $datagram (Bits $bits)");
			
			#Flags5
			} elsif ($rawReadingType eq "70") {
				
				my $bits = sprintf('%08b', hex("0x".$rawReadingValue));
				
				$singlereading = 0;
				readingsBeginUpdate($hash);
				#readingsBulkUpdate($hash, "", substr($bits,0,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,0,1));
				#readingsBulkUpdate($hash, "", substr($bits,1,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,1,1));
				#readingsBulkUpdate($hash, "", substr($bits,2,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,2,1));
				#readingsBulkUpdate($hash, "", substr($bits,3,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,3,1));
				#readingsBulkUpdate($hash, "", substr($bits,4,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,4,1));
				#readingsBulkUpdate($hash, "", substr($bits,5,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,5,1));
				#readingsBulkUpdate($hash, "", substr($bits,6,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,6,1));
				readingsBulkUpdate($hash, "PreHeatingStatus", substr($bits,7,1)) if (ReadingsVal($name,"PreHeatingStatus","unknown") ne substr($bits,5,1));
				readingsEndUpdate($hash, 1);
				
				Log3 ($name, 4, "Vallox: Incoming Status-Info (Flags5): $datagram (Bits $bits)");
						
			#Flags6
			} elsif ($rawReadingType eq "71") {
				
				my $bits = sprintf('%08b', hex("0x".$rawReadingValue));
				
				$singlereading = 0;
				readingsBeginUpdate($hash);
				#readingsBulkUpdate($hash, "", substr($bits,0,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,0,1));
				#readingsBulkUpdate($hash, "", substr($bits,1,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,1,1));
				#readingsBulkUpdate($hash, "", substr($bits,2,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,2,1));
				#readingsBulkUpdate($hash, "", substr($bits,3,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,3,1));
				readingsBulkUpdate($hash, "RemoteMonitoringControl", substr($bits,4,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,4,1));
				readingsBulkUpdate($hash, "FireplaceSwitchActivation", substr($bits,5,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,5,1));
				readingsBulkUpdate($hash, "FireplaceBoosterStatus", substr($bits,6,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,6,1));
				#readingsBulkUpdate($hash, "", substr($bits,7,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,5,1));
				readingsEndUpdate($hash, 1);
				
				Log3 ($name, 4, "Vallox: Incoming Status-Info (Flags6): $datagram (Bits $bits)");
			
			# Select
			} elsif ($rawReadingType eq "A3") {
				
				my $bits = sprintf('%08b', hex("0x".$rawReadingValue));
				
				$singlereading = 0;
				readingsBeginUpdate($hash);
				readingsBulkUpdate($hash, "ServiceReminderIndicator", substr($bits,0,1)) if (ReadingsVal($name,"ServiceReminderIndicator","unknown") ne substr($bits,0,1));
				readingsBulkUpdate($hash, "FaultIndicator", substr($bits,1,1)) if (ReadingsVal($name,"FaultIndicator","unknown") ne substr($bits,1,1));
				readingsBulkUpdate($hash, "HeatingIndicator", substr($bits,2,1)) if (ReadingsVal($name,"HeatingIndicator","unknown") ne substr($bits,2,1));
				readingsBulkUpdate($hash, "FilterGuardIndicator", substr($bits,3,1)) if (ReadingsVal($name,"FilterGuardIndicator","unknown") ne substr($bits,3,1));
				readingsBulkUpdate($hash, "HeatingState", substr($bits,4,1)) if (ReadingsVal($name,"HeatingState","unknown") ne substr($bits,4,1));
				readingsBulkUpdate($hash, "RHAdjustState", substr($bits,5,1)) if (ReadingsVal($name,"RHAdjustState","unknown") ne substr($bits,5,1));
				readingsBulkUpdate($hash, "CO2AdjustState", substr($bits,6,1)) if (ReadingsVal($name,"CO2AdjustState","unknown") ne substr($bits,6,1));
				readingsBulkUpdate($hash, "PowerState", substr($bits,7,1)) if (ReadingsVal($name,"PowerState","unknown") ne substr($bits,7,1));
				readingsEndUpdate($hash, 1);
				
				Log3 ($name, 4, "Vallox: Incoming Status-Info (Select): $datagram (Bits $bits)");
				
			# Program
			} elsif ($rawReadingType eq "AA") {
				
				my $bits = sprintf('%08b', hex("0x".$rawReadingValue));
				
				$singlereading = 0;
				readingsBeginUpdate($hash);
				readingsBulkUpdate($hash, "HumidityCO2AdjustmentInterval", oct("0b"."0000".substr($bits,0,4))) if (ReadingsVal($name,"HumidityCO2AdjustmentInterval","unknown") ne oct("0b"."0000".substr($bits,0,4)));
				readingsBulkUpdate($hash, "AutomaticHumidityBasicLevelSeekerState", substr($bits,4,1)) if (ReadingsVal($name,"AutomaticHumidityBasicLevelSeekerState","unknown") ne substr($bits,4,1));
				readingsBulkUpdate($hash, "BoostSwitchMode", substr($bits,5,1)) if (ReadingsVal($name,"BoostSwitchMode","unknown") ne substr($bits,5,1));
				readingsBulkUpdate($hash, "RadiatorType", substr($bits,6,1)) if (ReadingsVal($name,"RadiatorType","unknown") ne substr($bits,6,1));
				readingsBulkUpdate($hash, "CascadeAdjust ", substr($bits,7,1)) if (ReadingsVal($name,"CascadeAdjust","unknown") ne substr($bits,7,1));
				readingsEndUpdate($hash, 1);
				
				Log3 ($name, 4, "Vallox: Incoming Status-Info (Program): $datagram (Bits $bits)");
					
			# Program2
			} elsif ($rawReadingType eq "B5") {
				
				my $bits = sprintf('%08b', hex("0x".$rawReadingValue));
				
				$singlereading = 0;
				readingsBeginUpdate($hash);
				readingsBulkUpdate($hash, "MaxSpeedLimitFunction", substr($bits,0,1)) if (ReadingsVal($name,"MaxSpeedLimitFunction","unknown") ne substr($bits,0,1));
				#readingsBulkUpdate($hash, "", substr($bits,1,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,1,1));
				#readingsBulkUpdate($hash, "", substr($bits,2,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,2,1));
				#readingsBulkUpdate($hash, "", substr($bits,3,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,3,1));
				#readingsBulkUpdate($hash, "", substr($bits,4,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,4,1));
				#readingsBulkUpdate($hash, "", substr($bits,5,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,5,1));
				#readingsBulkUpdate($hash, "", substr($bits,6,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,6,1));
				#readingsBulkUpdate($hash, "", substr($bits,7,1)) if (ReadingsVal($name,"","unknown") ne substr($bits,5,1));
				readingsEndUpdate($hash, 1);
				
				Log3 ($name, 4, "Vallox: Incoming Status-Info (Program2): $datagram (Bits $bits)");
			
			# Convert Unused Binarys to bits (Just not to have Hex Readings)
			} elsif ($rawReadingType eq "6C" || $rawReadingType eq "6E") {
				
				$fineReadingValue = sprintf('%08b', hex("0x".$rawReadingValue));
				
				Log3 ($name, 4, "Vallox: Incoming Status-Info (Unused Binary): $datagram (Bits $fineReadingValue)");
			
			
			# Everything else
			# All Readings shall be handled before
			} else {
				$fineReadingValue = $rawReadingValue;
				$singlereading = 1;
				
				Log3 ($name, 2, "Vallox: Incoming unhandled datagram: $datagram");
			}
			
			if($Vallox_datatypes{$rawReadingType}) {
				if ($singlereading == 1) {
					if (ReadingsVal($name,$Vallox_datatypes{$rawReadingType},"unknown") ne $fineReadingValue) {
						Log3 ($name, 5, "Vallox: Update Reading: $fineReadingValue");
						readingsSingleUpdate($hash,$Vallox_datatypes{$rawReadingType}, $fineReadingValue, 1) ;
					} else {
						Log3 ($name, 5, "Vallox: Reading not changed: $fineReadingValue - Doing nothing.");
					}
				}
			} else {
				Log3 ($name, 4, "Vallox: Datagram not in Datatypes-Table: ".$datagram);
			}
		} else {
			Log3 ($name, 5, "Vallox: Incoming Status-Request: $datagram");
		}
    } 
}

sub Vallox_Shutdown($)
{
	my ($hash) = @_;

	DevIo_CloseDev($hash);
	return undef;
}


1;

=pod
=item device
=item summary Reads and writes parameters via RS485 from and to a Vallox ventilation bus.
=item summary_DE Liest und schreibt über RS485 aus und in einen Bus einer Vallox Belüftungsanlage

=begin html

<a name="Vallox"></a>
<h3>Vallox</h3>
<div>
<ul>
    Vallox is a manufacturer for ventilation devices.
    <br>
    Their products have a built-in RS485-Interface on the central ventilation unit as well as on connected control units on which all control communication is handeled.
    <br>
    More Info on the particular <a href="http://www.fhemwiki.de/wiki/Vallox">page of FHEM-Wiki</a> (in German).
    <br>
    &nbsp;
    <br>
  
  <a name="Valloxdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Vallox &lt;RS485-Device[@baud]&gt;</code><br>
    If the baudrate is omitted, it is set to 9600 (default Vallox baudrate).
    <br>
    Example: <code>define Ventilation Vallox /dev/ttyUSB1</code>
  </ul>
  <br>
  
  <a name="Valloxset"></a>
  <b>Set</b>
   <ul>
        <li><code>FanSpeed &lt; 1-8 &gt;</code>
          <br>
          Allows to set the fan speed (1 = lowest; 8 = highest).<br>
        </li><br>
        <li><code>BasicHumidityLevel &lt; 0-100 &gt;</code>
          <br>
          Allows to set the basic humidity level in percentage.<br>
        </li><br>
        <li><code>HeatRecoveryCellBypassSetpointTemperature &lt; 0-20 &gt;</code>
          <br>
          Allows to set the heat recovery cell bypass setpoint temperature.<br>
        </li><br>
        <li><code>raw &lt; HexValue &gt;</code><br>
          HexValue is two 2-digit hex number to identify the type and value of setting.
        </li><br>
        <br>
        Example to set the fan speed to 3:<br>
		<code>set Ventilation raw 2907</code><br>
        or:<br>
		<code>set Ventilation FanSpeed 3</code>
   </ul>
   <br>
   
   <a name="Valloxget"></a>
   <b>Get</b>
   <ul>
      <li><code>reading &lt; readingname &gt;</code>
          <br>
          Allows to get any predefined reading.<br>
        </li><br>
        <li><code>raw &lt; HexValue &gt;</code><br>
          HexValue is a 2-digit hex number to identify the requested reading.
        </li><br>
   </ul>
   <br>
  
   <a name="Valloxattr"></a>
   <b>Attributes</b>
   <ul><li><code>ValloxIDDomain &lt; HexValue &gt;</code>
         <br>
         HexValue is a 2-digit hex number to identify the &QUOT;address&QUOT; of the bus domain. (01 by default).
         </li><br>
      <li><code>ValloxIDCentral &lt; HexValue &gt;</code>
         <br>
         HexValue is a 2-digit hex number to identify the &QUOT;address&QUOT; of the central ventilation unit. (11 by default).<br>
         In a normal installation ventilation units in the scope 11 to 19 and are addressed with 10 for broadcast-messages.
         </li><br>
      <li><code>ValloxIDFHEM &lt; HexValue &gt;</code>
         <br>
         HexValue is a 2-digit hex number to identify the &QUOT;address&QUOT; of this system as a virtual control terminal. (22 by default)<br>
         In a normal installation control terminals are in the scope 21 to 29 and are addressed with 20 for broadcast-messages.<br>
		 The address must be unique.<br>
		 The &QUOT;panel address&QUOT; of the physical control terminal can be set on the settings of it. Possible values are 1-15 which is the second digit of the Hex-Value (1-F). The first digit is always 2.<br>
         The physical control terminal is usually 21.
         </li><br>
      <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
   </ul>
</ul>
</div>

=end html

=begin html_DE

<a name="Vallox"></a>
<h3>Vallox</h3>
<div>
<ul>
    Vallox ist ein Hersteller von Bel&uuml;ftungsanlagen mit W&auml;rmetauscher.
    <br>
	Die Systeme verf&uuml;gen sowohl an der zentralen L&uuml;ftungskomponente, als auch an den Terminals &uuml;ber eine RS485-Schnittstelle &uuml;ber die die gesamte interne Kommunikation abgewickelt wird.
    <br>
    Mehr Informationen sind auf der <a href="http://www.fhemwiki.de/wiki/Vallox">FHEM-Wiki-Seite</a> verf&uuml;gbar.
    <br>
    &nbsp;
    <br>
  
  <a name="Valloxdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Vallox &lt;RS485-Device[@baud]&gt;</code><br>
    Wird die Baudrate weggelassen wird mit 9600 baud kommuniziert. (Standardrate des Vallox-Busses).
    <br>
    Beispiel: <code>define Ventilation Vallox /dev/ttyUSB1</code>
  </ul>
  <br>
  
  <a name="Valloxset"></a>
  <b>Set</b>
   <ul>
        <li><code>FanSpeed &lt; 1-8 &gt;</code>
          <br>
          Erlaubt das &Auml;ndern der L&uuml;ftergeschwindigkeit (1 = minimal; 8 = maximal).<br>
        </li><br>
        <li><code>BasicHumidityLevel &lt; 0-100 &gt;</code>
          <br>
          Erlaubt das &Auml;ndern des Luftfeuchtigkeits-Grenzwertes (Terminaldisplay: <code>Grenzwert &#037;RH</code>).<br>
        </li><br>
        <li><code>HeatRecoveryCellBypassSetpointTemperature &lt; 0-20 &gt;</code>
          <br>
          Erlaubt das &Auml;ndern des Grenzwertes f&uuml;r den W&auml;rmetauscher-Bypass (Terminaldisplay: <code>WRG Bypass</code>)<br>
        </li><br>
        <li><code>raw &lt; HexWert &gt;</code><br>
          HexWert sind <u>zwei</u> 2-stellige Hex-Zahlen, welche den Typ und den Wert der Einstellung identifiziert.
        </li><br>
        <br>
        Beispiel um die L&uuml;ftergeschwindigkeit auf 3 zu setzen:<br>
		<code>set Ventilation raw 2907</code><br>
        oder:<br>
		<code>set Ventilation FanSpeed 3</code>
   </ul>
   <br>
   
   <a name="Valloxget"></a>
   <b>Get</b>
   <ul>
      <li><code>reading &lt; readingname &gt;</code>
          <br>
          Erlaubt das Auslesen der vorgegebenen Datenpunkte aus dem Bus.<br>
        </li><br>
        <li><code>raw &lt; HexWert &gt;</code><br>
          HexWert ist <u>eine</u> 2-stellige Hex-Zahl, welche den Typ der abzufragenden Einstellung identifiziert.
        </li><br>
   </ul>
   <br>
  
   <a name="Valloxattr"></a>
   <b>Attributes</b>
   <ul><li><code>ValloxIDDomain &lt; HexWert &gt;</code>
         <br>
         HexWert ist eine 2-stellige Hex-Zahl die als &QUOT;Adresse&QUOT; der Bus-Dom&auml;ne dient. (Standard: 01).
         </li><br>
      <li><code>ValloxIDCentral &lt; HexWert &gt;</code>
         <br>
		 HexWert ist eine 2-stellige Hex-Zahl die als &QUOT;Adresse&QUOT; der zentralen Ventilationseinheit dient. (Standard: 11).<br>
		 In einer normalen Umgebung werden die Ventilationseinheiten mit 11 - 1F adressiert. 10 ist die Broadcast-Adresse.<br>X
         </li><br>
      <li><code>ValloxIDFHEM &lt; HexWert &gt;</code>
         <br>
		 HexWert ist eine 2-stellige Hex-Zahl die als &QUOT;Adresse&QUOT; dieses Systems als virtuelles Kontrollterminal dient. (Standard: 22).<br>
		 Sie darf nicht bereits im Bus genutzt werden.<br>
		 In einer normalen Umgebung werden die Kontrollterminals mit 21 - 2F adressiert. 20 ist die Broadcast-Adresse.<br>
		 In den Einstellungen der physikalisch vorhandenen Terminals kann die &QUOT;FBD-Adresse&QUOT; des jeweiligen Terminals eingestellt werden.<br>
		 Hierbei stehen die Werte 1-15 zur Verf&uuml;gung, was der zweiten Stelle dieser Adresse (1-F) entspricht. Die erste Stelle ist immer 2.<br>
         Das physikalische Kontrollterminal ist &uuml;blicherweise die 21.
         </li><br>
      <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
   </ul>
</ul>
</div>
=end html_DE
=cut

