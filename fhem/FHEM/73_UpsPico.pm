# $Id$
########################################################################################################################
#
#     73_UpsPico.pm
#     Creates the possibility to access the UPS PIco Uninterrupteable Power Supply
#
#     Author                     : Matthias Deeke 
#     e-mail                     : matthias.deeke(AT)deeke(PUNKT)eu
#     Fhem Forum                 : https://forum.fhem.de/index.php/topic,77000.0.html
#     Fhem Wiki                  : 
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
#     fhem.cfg: define <devicename> UpsPico <IPv4-address> <UpsOnPiUser> <UpsOnPiPassword>
#
#     Example 1 - Bare Credentials:
#     define myUpsPico UpsPico 192.168.178.200 User Geheim
#
#     Example 2 - base64 encoded Credentials: Both, username and password, may be pre-encode with base64 if attribute CredentialsEncrypted is set
#     define myUpsPico UpsPico 192.168.178.200 VXNlcm5hbWU= UGFzc3dvcmQ=
#
########################################################################################################################

########################################################################################################################
# List of open Problems:
#
# Set - command not yet implemented
#
########################################################################################################################

package main;

use strict;
use warnings;

use Net::OpenSSH;
use Data::Dumper qw(Dumper);
use Math::Expression::Evaluator;
use Digest::MD5 qw(md5 md5_hex md5_base64);

use constant false => 0;
use constant true  => 1;

sub UpsPico_Attr(@);
sub UpsPico_Get($@);
sub UpsPico_Set($@);
sub UpsPico_Define($$);
sub UpsPico_Undefine($$);
sub UpsPico_Initialize($);
sub UpsPico_GetAllData($@);
sub UpsPico_DbLog_splitFn($$);
sub UpsPico_CheckConnection($@);

###START###### Initialize module ##############################################################################START####
sub UpsPico_Initialize($)
{
    my ($hash)  = @_;

    $hash->{STATE}           = "Init";
    $hash->{DefFn}           = "UpsPico_Define";
    $hash->{UndefFn}         = "UpsPico_Undefine";
    $hash->{SetFn}           = "UpsPico_Set";
    $hash->{GetFn}           = "UpsPico_Get";
    $hash->{AttrFn}          = "UpsPico_Attr";
	$hash->{DbLog_splitFn}   = "UpsPico_DbLog_splitFn";

    $hash->{AttrList}        = "do_not_notify:0,1 " .
							   "header " .
							   "Port " .
							   "WriteCritical:0,1 " .
							   "disable:1,0 " .
						       "loglevel:0,1,2,3,4,5 " .
						       "PollingInterval " .
							   "CredentialsEncrypted:0,1 " .
						       $readingFnAttributes;
}
####END####### Initialize module ###############################################################################END#####


###START######  Activate module after module has been used via fhem command "define" ##########################START####
sub UpsPico_Define($$)
{
	my ($hash, $def)            = @_;
	my @a						= split("[ \t][ \t]*", $def);
	my $name					= $a[0];
								 #$a[1] just contains the "UpsPico" module name and we already know that! :-)
	my $url						= $a[2];
	my $RemotePiUser			= $a[3];
	my $RemotePiPass			= $a[4];

	$hash->{NAME}				= $name;
	$hash->{STATE}              = "define";

	Log3 $name, 4, $name. " : UpsPico_Define - Starting to define module";

	###START###### Reset fullResponse error message ############################################################START####
	readingsSingleUpdate( $hash, "fullResponse", "Initialising...", 1);
	####END####### Reset fullResponse error message #############################################################END#####	

	### Stop the current timer if one exists errornous 
	RemoveInternalTimer($hash);
	Log3 $name, 4, $name. " : UpsPico_Define - InternalTimer has been removed.";
	
    ###START### Check whether all variables are available #####################################################START####
	if (int(@a) == 5) 
	{
		###START### Check whether IPv4 address is valid
		if ($url =~ m/^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/)
		{
			Log3 $name, 4, $name. " : UpsPico_Define - IPv4-address is valid                                   : " . $url;
		}
		else
		{
			return $name .": Error - IPv4 address is not valid \n Please use \"define <devicename> UpsPico <IPv4-address> <interval/[s]> <Username> <Password>\" instead";
		}
		####END#### Check whether IPv4 address is valid	
	}
	else
	{
	    return $name .": UpsPico - Error - Not enough or too much parameter provided." . "\n" . "Gateway IPv4 address, Username and  Password must be provided" ."\n". "Please use \"define <devicename> UpsPico <IPv4-address> <Username> <Password>\" instead";
	}
	####END#### Check whether all variables are available ######################################################END#####

	
  	###START### Decode Username and Password if base 64 coded #################################################START####
	if (defined($attr{$name}{CredentialsEncrypted}))
	{
		if ($attr{$name}{CredentialsEncrypted} == 1)
		{
			$RemotePiUser = decode_base64($RemotePiUser);
			$RemotePiPass = decode_base64($RemotePiPass);
		}
	}
	####END#### Decode Username and Password if base 64 coded ##################################################END#####  
  
  
	###START###### Provide basic Information for all register #################################################START####
	my %RegisterInfo; 
	$RegisterInfo{"mode"}               = {RegisterBlockName => "Status",  RegisterAddress => 0x00, DataType => "Byte",     Writeable => false, Reset => false, Critical => false, Factor => undef, Unit => undef,    SelectionList => {0x01 => "RPI_MODE", 0x02 => "BAT_MODE", Default => "ERROR"}																									};
	$RegisterInfo{"batlevel"}           = {RegisterBlockName => "Status",  RegisterAddress => 0x08, DataType => "WordBCD",  Writeable => false, Reset => false, Critical => false, Factor => 0.01,  Unit => "V",      SelectionList => undef																																							};
	$RegisterInfo{"rpilevel"}           = {RegisterBlockName => "Status",  RegisterAddress => 0x0a, DataType => "WordBCD",  Writeable => false, Reset => false, Critical => false, Factor => 0.01,  Unit => "V",      SelectionList => undef																																							};
	$RegisterInfo{"eprlevel"}           = {RegisterBlockName => "Status",  RegisterAddress => 0x0c, DataType => "WordBCD",  Writeable => false, Reset => false, Critical => false, Factor => 0.01,  Unit => "V",      SelectionList => undef																																							};
	$RegisterInfo{"aEXT0level"}         = {RegisterBlockName => "Status",  RegisterAddress => 0x14, DataType => "WordBCD",  Writeable => false, Reset => false, Critical => false, Factor => 0.01,  Unit => "V",      SelectionList => undef																																							};
	$RegisterInfo{"aEXT1level"}         = {RegisterBlockName => "Status",  RegisterAddress => 0x16, DataType => "WordBCD",  Writeable => false, Reset => false, Critical => false, Factor => 0.01,  Unit => "V",      SelectionList => undef																																							};
	$RegisterInfo{"aEXT2level"}         = {RegisterBlockName => "Status",  RegisterAddress => 0x18, DataType => "WordBCD",  Writeable => false, Reset => false, Critical => false, Factor => 0.01,  Unit => "V",      SelectionList => undef																																							};
	$RegisterInfo{"key"}                = {RegisterBlockName => "Status",  RegisterAddress => 0x1a, DataType => "Byte",     Writeable => true,  Reset => true,  Critical => false, Factor => undef, Unit => undef,    SelectionList => {0x00 => "No Key pressed", 0x01 => "Key A pressed", 0x02 => "Key B pressed", 0x03 => "Key C pressed", Default => "ERROR"}										};
	$RegisterInfo{"ntc"}                = {RegisterBlockName => "Status",  RegisterAddress => 0x1b, DataType => "Byte",     Writeable => false, Reset => false, Critical => false, Factor => 1.00,  Unit => "&deg;C", SelectionList => undef																																							};
	$RegisterInfo{"TO92"}               = {RegisterBlockName => "Status",  RegisterAddress => 0x1c, DataType => "Byte",     Writeable => false, Reset => false, Critical => false, Factor => 1.00,  Unit => "&deg;C", SelectionList => undef																																							};
	$RegisterInfo{"charger"}            = {RegisterBlockName => "Status",  RegisterAddress => 0x20, DataType => "Byte",     Writeable => false, Reset => false, Critical => false, Factor => undef, Unit => undef,    SelectionList => {0x00 => "Charger OFF", 0x01 => "Charging Batt", Default => "ERROR"}																							};
	$RegisterInfo{"pico_is_running"}    = {RegisterBlockName => "Status",  RegisterAddress => 0x22, DataType => "WordHex",  Writeable => false, Reset => false, Critical => false, Factor => 1.00,  Unit => "ms",     SelectionList => undef																																							};
	$RegisterInfo{"pv"}                 = {RegisterBlockName => "Status",  RegisterAddress => 0x24, DataType => "ASCII",    Writeable => false, Reset => false, Critical => false, Factor => undef, Unit => undef,    SelectionList => undef																																							};
	$RegisterInfo{"bv"}                 = {RegisterBlockName => "Status",  RegisterAddress => 0x25, DataType => "ASCII",    Writeable => false, Reset => false, Critical => false, Factor => undef, Unit => undef,    SelectionList => undef																																							};
	$RegisterInfo{"fv"}                 = {RegisterBlockName => "Status",  RegisterAddress => 0x26, DataType => "Byte",     Writeable => false, Reset => false, Critical => false, Factor => undef, Unit => undef,    SelectionList => undef																																							};
	$RegisterInfo{"RTC_seconds"}        = {RegisterBlockName => "RTC",     RegisterAddress => 0x00, DataType => "Byte",     Writeable => false, Reset => false, Critical => false, Factor => 1.00,  Unit => "s",      SelectionList => undef																																							};
	$RegisterInfo{"RTC_minutes"}        = {RegisterBlockName => "RTC",     RegisterAddress => 0x01, DataType => "Byte",     Writeable => false, Reset => false, Critical => false, Factor => 1.00,  Unit => "min",    SelectionList => undef																																							};
	$RegisterInfo{"RTC_hours"}          = {RegisterBlockName => "RTC",     RegisterAddress => 0x02, DataType => "Byte",     Writeable => false, Reset => false, Critical => false, Factor => 1.00,  Unit => "h",      SelectionList => undef																																							};
	$RegisterInfo{"RTC_wday"}           = {RegisterBlockName => "RTC",     RegisterAddress => 0x03, DataType => "Byte",     Writeable => false, Reset => false, Critical => false, Factor => 1.00,  Unit => " ",      SelectionList => undef																																							};
	$RegisterInfo{"RTC_mday"}           = {RegisterBlockName => "RTC",     RegisterAddress => 0x04, DataType => "Byte",     Writeable => false, Reset => false, Critical => false, Factor => 1.00,  Unit => " ",      SelectionList => undef																																							};
	$RegisterInfo{"RTC_month"}          = {RegisterBlockName => "RTC",     RegisterAddress => 0x05, DataType => "Byte",     Writeable => false, Reset => false, Critical => false, Factor => 1.00,  Unit => " ",      SelectionList => undef																																							};
	$RegisterInfo{"RTC_year"}           = {RegisterBlockName => "RTC",     RegisterAddress => 0x06, DataType => "Byte",     Writeable => false, Reset => false, Critical => false, Factor => 1.00,  Unit => " ",      SelectionList => undef																																							};
	$RegisterInfo{"pico_state"}         = {RegisterBlockName => "Command", RegisterAddress => 0x00, DataType => "Byte",     Writeable => true,  Reset => false, Critical => true,  Factor => undef, Unit => undef,    SelectionList => {0x00 => "OK", 0x80 => "OK", 0xcc => "Shutdown", 0xdd => "Factory Reset", 0xee => "CPU Reset", 0xff => "Bootloader", 0xa0 => "DEFAULT", 0xa1 => "NO_RTC", 0xa2 => "ALTERNATE", Default => "ERROR"}};
	$RegisterInfo{"bat_run_time"}       = {RegisterBlockName => "Command", RegisterAddress => 0x01, DataType => "Byte",     Writeable => true,  Reset => false, Critical => false, Factor => 1.00,  Unit => "s",      SelectionList => {0xff => "BattLive", Default => "Function: 60+RegisterValue*60"}																								};
	$RegisterInfo{"rs232_rate"}         = {RegisterBlockName => "Command", RegisterAddress => 0x02, DataType => "Byte",     Writeable => true,  Reset => false, Critical => false, Factor => undef, Unit => undef,    SelectionList => {0x00 => "Disabled", 0x01 => "4800bps", 0x02 => "9600bps", 0x03 => "19200bps", 0x04 => "34600bps", 0x05 => "57600bps", 0x0f => "115200bps",Default => "ERROR"}	};
	$RegisterInfo{"STA_timer"}          = {RegisterBlockName => "Command", RegisterAddress => 0x05, DataType => "Byte",     Writeable => true,  Reset => false, Critical => false, Factor => 1.00,  Unit => "s",      SelectionList => {0xff => "Disabled", Default => "Function: RegisterValue"}																										};
	$RegisterInfo{"enable5V"}           = {RegisterBlockName => "Command", RegisterAddress => 0x06, DataType => "Byte",     Writeable => true,  Reset => false, Critical => false, Factor => undef, Unit => undef,    SelectionList => {0x00 => "Disabled", 0x01 => "Enabled", Default => "ERROR"}																									};
	$RegisterInfo{"battype"}            = {RegisterBlockName => "Command", RegisterAddress => 0x07, DataType => "Byte",     Writeable => true,  Reset => false, Critical => false, Factor => undef, Unit => undef,    SelectionList => {0x46 => "LiFePO4 - F", 0x51 => "LiFePO4 - Q", 0x53 => "LiPO - S", 0x50 => "LiPO - P", Default => "ERROR"}														};
	$RegisterInfo{"setA_D"}             = {RegisterBlockName => "Command", RegisterAddress => 0x08, DataType => "Byte",     Writeable => true,  Reset => false, Critical => true,  Factor => undef, Unit => undef,    SelectionList => {0x00 => "AEXT1: 05.2V; AEXT2: 05.2V;", 0x01 => "AEXT1: 05.2V; AEXT2: 10.0V;", 0x02 => "AEXT1: 05.2V; AEXT2: 20.0V;", 0x03 => "AEXT1: 05.2V; AEXT2: 30.0V;", 0x10 => "AEXT1: 10.0V; AEXT2: 05.2V;", 0x11 => "AEXT1: 10.0V; AEXT2: 10.0V;", 0x12 => "AEXT1: 10.0V; AEXT2: 20.0V;", 0x13 => "AEXT1: 10.0V; AEXT2: 30.0V;", 0x20 => "AEXT1: 20.0V; AEXT2: 05.2V;", 0x21 => "AEXT1: 20.0V; AEXT2: 10.0V;", 0x22 => "AEXT1: 20.0V; AEXT2: 20.0V;", 0x23 => "AEXT1: 20.0V; AEXT2: 30.0V;", 0x30 => "AEXT1: 30.0V; AEXT2: 05.2V;", 0x31 => "AEXT1: 30.0V; AEXT2: 10.0V;", 0x32 => "AEXT1: 30.0V; AEXT2: 20.0V;", 0x33 => "AEXT1: 30.0V; AEXT2: 30.0V;", Default => "ERROR"} };
	$RegisterInfo{"User_LED_Orange"}    = {RegisterBlockName => "Command", RegisterAddress => 0x09, DataType => "Byte",     Writeable => true,  Reset => false, Critical => false, Factor => undef, Unit => undef,    SelectionList => {0x00 => "OFF", 0x01 => "ON", Default => "ERROR"}																												};
	$RegisterInfo{"User_LED_Green"}     = {RegisterBlockName => "Command", RegisterAddress => 0x0a, DataType => "Byte",     Writeable => true,  Reset => false, Critical => false, Factor => undef, Unit => undef,    SelectionList => {0x00 => "OFF", 0x01 => "ON", Default => "ERROR"}																												};
	$RegisterInfo{"User_LED_Blue"}      = {RegisterBlockName => "Command", RegisterAddress => 0x0b, DataType => "Byte",     Writeable => true,  Reset => false, Critical => false, Factor => undef, Unit => undef,    SelectionList => {0x00 => "OFF", 0x01 => "ON", Default => "ERROR"}																												};
	$RegisterInfo{"brelay"}             = {RegisterBlockName => "Command", RegisterAddress => 0x0c, DataType => "Byte",     Writeable => true,  Reset => false, Critical => false, Factor => undef, Unit => undef,    SelectionList => {0x00 => "Reset", 0x01 => "Set", Default => "ERROR"}																											};
	$RegisterInfo{"bmode"}              = {RegisterBlockName => "Command", RegisterAddress => 0x0d, DataType => "Byte",     Writeable => true,  Reset => false, Critical => false, Factor => undef, Unit => undef,    SelectionList => {0x00 => "Disabled", 0x01 => "Enabled", Default => "ERROR"}																									};
	$RegisterInfo{"bfreq"}              = {RegisterBlockName => "Command", RegisterAddress => 0x0e, DataType => "WordBCD",  Writeable => true,  Reset => false, Critical => false, Factor => 1.00,  Unit => "Hz",     SelectionList => undef																																							};
	$RegisterInfo{"bdur"}               = {RegisterBlockName => "Command", RegisterAddress => 0x10, DataType => "Byte",     Writeable => true,  Reset => false, Critical => false, Factor => 10,    Unit => "ms",     SelectionList => undef																																							};
	$RegisterInfo{"fmode"}              = {RegisterBlockName => "Command", RegisterAddress => 0x11, DataType => "Byte",     Writeable => true,  Reset => false, Critical => false, Factor => undef, Unit => undef,    SelectionList => {0x00 => "Disabled", 0x01 => "Enabled", 0x02 => "Auto", Default => "ERROR"}																					};
	$RegisterInfo{"fspeed"}             = {RegisterBlockName => "Command", RegisterAddress => 0x12, DataType => "Hex",      Writeable => true,  Reset => false, Critical => false, Factor => 1.00,  Unit => "%",      SelectionList => undef																																							};
	$RegisterInfo{"fstat"}              = {RegisterBlockName => "Command", RegisterAddress => 0x13, DataType => "Byte",     Writeable => true,  Reset => false, Critical => false, Factor => undef, Unit => undef,    SelectionList => {0x00 => "OFF", 0x01 => "ON", Default => "ERROR"}																												};
	$RegisterInfo{"fttemp"}             = {RegisterBlockName => "Command", RegisterAddress => 0x14, DataType => "Byte",     Writeable => true,  Reset => false, Critical => false, Factor => 1.00,  Unit => "&deg;C", SelectionList => undef																																							};
	$RegisterInfo{"LED_OFF"}            = {RegisterBlockName => "Command", RegisterAddress => 0x15, DataType => "Byte",     Writeable => true,  Reset => false, Critical => false, Factor => undef, Unit => undef,    SelectionList => {0x00 => "All LEDs forced OFF", 0x01 => "All LED manual", Default => "ERROR"}																					};
	$RegisterInfo{"STS_active"}         = {RegisterBlockName => "StartTS", RegisterAddress => 0x00, DataType => "Byte",     Writeable => true,  Reset => false, Critical => false, Factor => undef, Unit => undef,    SelectionList => {0x00 => "Inactive", 0xff => "Active", Default => "ERROR"}																										};
	$RegisterInfo{"STS_minute"}         = {RegisterBlockName => "StartTS", RegisterAddress => 0x01, DataType => "Byte",     Writeable => true,  Reset => false, Critical => false, Factor => 1.00,  Unit => "min",    SelectionList => undef																																							};
	$RegisterInfo{"STS_hour"}           = {RegisterBlockName => "StartTS", RegisterAddress => 0x02, DataType => "Byte",     Writeable => true,  Reset => false, Critical => false, Factor => 1.00,  Unit => "h",      SelectionList => undef																																							};
	$RegisterInfo{"STS_mday"}           = {RegisterBlockName => "StartTS", RegisterAddress => 0x03, DataType => "Byte",     Writeable => true,  Reset => false, Critical => false, Factor => 1.00,  Unit => "d",    SelectionList => undef																																							};
	$RegisterInfo{"STS_month"}          = {RegisterBlockName => "StartTS", RegisterAddress => 0x04, DataType => "Byte",     Writeable => true,  Reset => false, Critical => false, Factor => 1.00,  Unit => "m",    SelectionList => undef																																							};
	$RegisterInfo{"STS_year"}           = {RegisterBlockName => "StartTS", RegisterAddress => 0x05, DataType => "Byte",     Writeable => true,  Reset => false, Critical => false, Factor => 1.00,  Unit => "y",    SelectionList => undef																																							};
	$RegisterInfo{"D_repetition"}       = {RegisterBlockName => "RunTS",   RegisterAddress => 0x00, DataType => "Byte",     Writeable => true,  Reset => false, Critical => false, Factor => 1.00,  Unit => "d",      SelectionList => {0xff => "Disabled", Default => "Function: RegisterValue"}																										};
	$RegisterInfo{"H_repetition"}       = {RegisterBlockName => "RunTS",   RegisterAddress => 0x01, DataType => "Byte",     Writeable => true,  Reset => false, Critical => false, Factor => 1.00,  Unit => "h",      SelectionList => {0xff => "Disabled", Default => "Function: RegisterValue"}																										};
	$RegisterInfo{"M_repetition"}       = {RegisterBlockName => "RunTS",   RegisterAddress => 0x02, DataType => "Byte",     Writeable => true,  Reset => false, Critical => false, Factor => 1.00,  Unit => "min",    SelectionList => {0xff => "Disabled", Default => "Function: RegisterValue"}																										};
	$RegisterInfo{"H_duration"}         = {RegisterBlockName => "RunTS",   RegisterAddress => 0x03, DataType => "Byte",     Writeable => true,  Reset => false, Critical => false, Factor => 1.00,  Unit => "h",      SelectionList => {0xff => "Disabled", Default => "Function: RegisterValue"}																										};
	$RegisterInfo{"M_duration"}         = {RegisterBlockName => "RunTS",   RegisterAddress => 0x04, DataType => "Byte",     Writeable => true,  Reset => false, Critical => false, Factor => 1.00,  Unit => "min",    SelectionList => {0xff => "Disabled", Default => "Function: RegisterValue"}																										};
#	$RegisterInfo{"??????????"}         = {RegisterBlockName => "EventS",  RegisterAddress => 0x00, DataType => "Byte",     Writeable => true,  Reset => false, Critical => false, Factor => undef, Unit => undef,    SelectionList => undef																																							};
#	$RegisterInfo{"??????????"}         = {RegisterBlockName => "ActionS", RegisterAddress => 0x00, DataType => "Byte",     Writeable => true,  Reset => false, Critical => false, Factor => undef, Unit => undef,    SelectionList => undef																																							};
	####END####### Provide basic Information for all register ##################################################END#####

	###START###### Provide charging information for batteries #################################################START####
	my %BattChargingInfo;
	$BattChargingInfo{"LiFePO4 - F"}    = {Volt0Percent => 2.9, Volt100Percent => 3.6};
	$BattChargingInfo{"LiFePO4 - Q"}    = {Volt0Percent => 2.9, Volt100Percent => 3.6};
	$BattChargingInfo{"LiPO - S"}       = {Volt0Percent => 3.4, Volt100Percent => 4.3};
	$BattChargingInfo{"LiPO - P"}       = {Volt0Percent => 3.4, Volt100Percent => 4.3};
	####END####### Provide charging information for batteries ##################################################END#####
	
	###START###### Writing values to global hash ##############################################################START####
	$hash->{NAME}						= $name;
	$hash->{URL}						= $url;
	$hash->{temp}{FIRSTTIME}			= true;
	$hash->{temp}{RemotePiUser}			= $RemotePiUser;
	$hash->{temp}{RemotePiPass}			= $RemotePiPass;
	%{$hash->{temp}{RegisterInfo}}		= %RegisterInfo;
	%{$hash->{temp}{BattChargingInfo}}  = %BattChargingInfo;
	####END####### Writing values to global hash ###############################################################END#####
	
	###START###### For Debugging purpose only #################################################################START####  
	Log3 $name, 4, $name. " : UpsPico_Define Hash                                                      : "   . $hash;
	Log3 $name, 4, $name. " : UpsPico_Define Def                                                       : "   . $def;
	Log3 $name, 4, $name. " : UpsPico_Define Array                                                     : "   . @a;
	Log3 $name, 4, $name. " : UpsPico_Define Name                                                      : "   . $name;
	Log3 $name, 4, $name. " : UpsPico_Define Address                                                   : "   . $url;
	Log3 $name, 5, $name. " : UpsPico -----------------------------------------------------------------------------";
	Log3 $name, 5, $name. " : UpsPico - RegisterInfo in fhem-hash                                      : \n" . Dumper \%$hash;
	Log3 $name, 5, $name. " : UpsPico -----------------------------------------------------------------------------";
	####END####### For Debugging purpose only ##################################################################END#####
	
	###Initiate the timer for first check of connection towards RasPi with UpsPico but wait 30s
	InternalTimer(gettimeofday()+30, "UpsPico_CheckConnection", $hash, 0);
	
	return undef;
}
####END####### Activate module after module has been used via fhem command "define" ############################END#####


###START###### To bind unit of value to DbLog entries #########################################################START####
sub UpsPico_DbLog_splitFn($$)
{
	my ($event, $name)	= @_;
	my $hash 			= $defs{$name};
	my %RegisterInfo 	= %{$hash->{temp}{RegisterInfo}};
	my @argument		= split("[ \t][ \t]*", $event);
	
	#### Delete ":" and everything behind in readings name
	$argument[0] =~ s/:.*//;

	### Pre-Define variables
	my $reading 		= $argument[0];
	my $value			= $argument[1];
	my $unit			= undef;
	
	### Log entries for debugging
	Log3 $name, 5, $name. " : UpsPico_DbLog_splitFn - Content of event                                 : " . $event;
	Log3 $name, 5, $name. " : UpsPico_DbLog_splitFn - Content of argument[0]                           : " . $argument[0];
	Log3 $name, 5, $name. " : UpsPico_DbLog_splitFn - Content of argument[1]                           : " . $argument[1];


	### Split Reading in RegisterI2CBlock and RegisterName
	my @SplitRegisterReading 		= split(/\//,$argument[0]);
									# $SplitRegisterReading[0] is an empty field
	my $RegisterI2CBlockNameEvent 	= $SplitRegisterReading[1];
	my $RegisterNameEvent 			= $SplitRegisterReading[2];
	Log3 $name, 5, $name. " : UpsPico_DbLog_splitFn - Content of RegisterI2CBlockNameEvent             : " . $RegisterI2CBlockNameEvent;
	Log3 $name, 5, $name. " : UpsPico_DbLog_splitFn - Content of RegisterNameEvent                     : " . $RegisterNameEvent;
	
	### Set I2CBlockAddressnames
	my %I2CAddress;
	$I2CAddress{Status} 	= undef;
	$I2CAddress{RTC} 		= undef;
	$I2CAddress{Command}	= undef;
	$I2CAddress{StartTS}	= undef;
	$I2CAddress{RunTS}		= undef;
	$I2CAddress{EventS}		= undef;
	$I2CAddress{ActionS}	= undef;
	
	### For all specified RegisterI2CBlocks and registers: Search for unit
	SearchLoop: 
	{
		foreach my $RegisterI2CBlock (keys %I2CAddress) 
		{
			### If the RegisterI2CBlock to be changed is identical to the RegisterI2CBlock in the loop
			if ($RegisterI2CBlockNameEvent eq $RegisterI2CBlock)
			{
				### For all specified Register
				foreach my $RegisterName (keys %RegisterInfo) 
				{
					### If the RegisterName to be changed is identical to the RegisterName in the loop
					if ($RegisterNameEvent eq $RegisterName)
					{
						Log3 $name, 5, $name. " : UpsPico_DbLog_splitFn - Found Register for reading                       : " . $reading;
						
						### Extract value and unit
						$unit    = $RegisterInfo{$RegisterName}{Unit};
						last SearchLoop;
					}
				}
			}
		}
	}
	### Log entries for debugging
	Log3 $name, 5, $name. " : UpsPico_DbLog_splitFn - Content of reading                               : " . $reading;
	Log3 $name, 5, $name. " : UpsPico_DbLog_splitFn - Content of value                                 : " . $value;
	Log3 $name, 5, $name. " : UpsPico_DbLog_splitFn - Content of unit                                  : " . $unit;

	return ($reading, $value, $unit);
}
####END####### To bind unit of value to DbLog entries ##########################################################END#####


###START###### Deactivate module module after "undefine" command by fhem ######################################START####
sub UpsPico_Undefine($$)
{
	my ($hash, $def)  = @_;
	my $name = $hash->{NAME};	
	my $url  = $hash->{URL};

  	### Stop the internal timer for this module
	RemoveInternalTimer($hash);

	Log3 $name, 3, $name. " - UpsPico has been undefined. The KM unit at $url will no longer polled.";

	return undef;
}
####END####### Deactivate module module after "undefine" command by fhem #######################################END#####


###START###### Handle attributes after changes via fhem GUI ###################################################START####
sub UpsPico_Attr(@)
{
	my @a                      = @_;
	my $name                   = $a[1];
	my $hash                   = $defs{$name};
		
	### Check whether disable attribute has been provided
	if ($a[2] eq "disable")
	{
		###START### Check whether device shall be disabled
		if ($a[3] == 1)
		{
			### Set new status
			$hash->{STATE} = "Disabled";
			
			### Stop the current timer
			RemoveInternalTimer($hash);
			Log3 $name, 4, $name. " : UpsPico_Attr          - InternalTimer has been removed.";
			### Delete all Readings
			fhem( "deletereading $name .*" );

			Log3 $name, 3, $name. " : UpsPico_Attr          - Device disabled as per attribute.";
		}
		else
		{
			### Initiate the timer for first time polling of  values from UpsPico but wait 10s
			$hash->{temp}{FIRSTTIME} = true;
			RemoveInternalTimer($hash);
			InternalTimer(gettimeofday()+180, "UpsPico_CheckConnection", $hash, 0);
			Log3 $name, 4, $name. " : UpsPico_Attr          - Internal timer for Initialisation of services re-started.";
			Log3 $name, 4, $name. " : UpsPico_Attr          - Device enabled as per attribute.";
		}
		####END#### Check whether device shall be disabled
	}
	### Check whether polling interval attribute for all data has been provided
	elsif ($a[2] eq "PollingInterval")
	{
		my $PollingInterval = $a[3];
		###START### Check whether polling interval is not too short
		if ($PollingInterval > 19)
		{
			### Initiate the timer for first time polling of  values from UpsPico but wait 10s
			$hash->{temp}{FIRSTTIME} = true;
			RemoveInternalTimer($hash);
			InternalTimer(gettimeofday()+180, "UpsPico_CheckConnection", $hash, 0);
			Log3 $name, 4, $name. " : UpsPico_Attr          - Interval for all data set to attribute value     :" . $PollingInterval ." s";
			Log3 $name, 4, $name. " : UpsPico_Attr          - Internal timer for Initialisation of services re-started.";
		}
		else
		{
			return $name .": Error - Polling interval too small - server response time greater than defined interval, please use something >=20, default is 90";
		}
		####END#### Check whether polling interval is not too short
	}
	### If no attributes of the above mentioned ones have been selected
	else
	{
		# Do nothing
	}
	return undef;
}
####END####### Handle attributes after changes via fhem GUI ####################################################END#####


###START###### Obtain value after "get" command by fhem #######################################################START####
sub UpsPico_Get($@)
{
	my ( $hash, @a ) = @_;
	
	### If not enough arguments have been provided
	if ( @a < 2 )
	{
		return "\"UpsPico_Get\" needs at least one argument";
	}
	
	my $name     		= shift @a;
	my $reading  		= shift @a;
	my $host 			= $hash->{URL};
	my $user 			= $hash->{temp}{RemotePiUser};
	my $pass 			= $hash->{temp}{RemotePiPass};
	my %RegisterInfo 	= %{$hash->{temp}{RegisterInfo}};
	
	
	### Pre-Define variables
	my $ReturnMessage;

	
	### Log entries for debugging
	Log3 $name, 5, $name. " : UpsPico_Get           ------------------- Definition ----------------------------------------------";
	Log3 $name, 5, $name. " : UpsPico_Get           - name                                             : " . $name;
	Log3 $name, 5, $name. " : UpsPico_Get           - reading                                          : " . $reading;

	
	### Prepare list of readings to be selected
	if(!$hash->{READINGS}{$reading}) 
	{
		my @cList = sort keys %{$hash->{READINGS}};
		return "Unknown argument $reading, choose one of " . join(" ", @cList);
	}
	
	
	### Split Reading in RegisterI2CBlock and RegisterName
	my @SplitRegisterReading 		= split(/\//,$reading);
									# $SplitRegisterReading[0] is an empty field
	my $RegisterI2CBlockNameEvent 	= $SplitRegisterReading[1];
	my $RegisterNameEvent 			= $SplitRegisterReading[2];
	

	Log3 $name, 5, $name. " : UpsPico_Get           - Content of RegisterI2CBlockNameEvent             : " . $RegisterI2CBlockNameEvent;
	Log3 $name, 5, $name. " : UpsPico_Get           - Content of RegisterNameEvent                     : " . $RegisterNameEvent;

	
	### Set I2C address block hash
	my %I2CAddress;
	$I2CAddress{Status} 	= undef;
	$I2CAddress{RTC} 		= undef;
	$I2CAddress{Command}	= undef;
	$I2CAddress{StartTS}	= undef;
	$I2CAddress{RunTS}		= undef;
	$I2CAddress{EventS}		= undef;
	$I2CAddress{ActionS}	= undef;

	
	### For all specified RegisterI2CBlocks and registers: Search for unit and register address
	SearchLoop: 
	{
		foreach my $RegisterI2CBlock (keys %I2CAddress) 
		{
			### If the RegisterI2CBlock to be changed is identical to the RegisterI2CBlock in the loop
			if ($RegisterI2CBlockNameEvent eq $RegisterI2CBlock)
			{
				### For all specified Register
				foreach my $RegisterName (keys %RegisterInfo) 
				{
					### If the RegisterName to be changed is identical to the RegisterName in the loop
					if ($RegisterNameEvent eq $RegisterName)
					{
						Log3 $name, 5, $name. " : UpsPico_Get           - Found Register for reading                       : " . $reading;
						
						### Call Download
						UpsPico_GetAllData($hash, @a);

						### Log entries for debugging
						Log3 $name, 5, $name. " : UpsPico_Get           ------------------- Final Handover ------------------------------------------";
						Log3 $name, 5, $name. " : UpsPico_Get           - reading                                          : " . $reading;
						Log3 $name, 5, $name. " : UpsPico_Get           - RegisterName                                     : " . $RegisterName;
						Log3 $name, 5, $name. " : UpsPico_Get           - RegisterInfo{RegisterName}{Value}                : " . $RegisterInfo{$RegisterName}{Value};
						Log3 $name, 5, $name. " : UpsPico_Get           - RegisterInfo{RegisterName}{Unit}                 : " . $RegisterInfo{$RegisterName}{Unit};
						Log3 $name, 5, $name. " : UpsPico_Get           ==============================================================================";

						### Prepare the message
						$ReturnMessage = $reading . " = " . $RegisterInfo{$RegisterName}{Value} . " " . $RegisterInfo{$RegisterName}{Unit};

						### Break the loop since the job is done
						last SearchLoop;
					}
				}
			}
		}
	}
	
	### Return value
	return($ReturnMessage);
}
####END####### Obtain value after "get" command by fhem ########################################################END#####


###START###### Manipulate service after "set" command by fhem #################################################START####
sub UpsPico_Set($@)
{
	my ( $hash, @a ) = @_;
	
	### If not enough arguments have been provided
	if ( @a < 2 )
	{
		return "\"set UpsPico\" needs at least one argument";
	}
		
	my $name 		= shift @a;
	my $register	= shift @a;
	my $value		= join(" ", @a);
	my %UpsPico_sets;
	my $ReturnMessage;
	
	return($ReturnMessage);

	### DO NOT FORGET TO CHECK ATTRIBUTE "WriteCritical"!!!
	### DO NOT FORGET TO RESET ATTRIBUTE "WriteCritical" after every single reading!!! Use fhem command "save"
}
####END####### Manipulate service after "Set" command by fhem ##################################################END#####

###START###### Check connection towards remote RasPi via SSH ##################################################START####
sub UpsPico_CheckConnection($@)
{
	my ($hash, $def)  = @_;
	my $name = $hash->{NAME};	
	my $url  = $hash->{URL};

	Log3 $name, 5, $name. " : UpsPico - CheckConnection-------------------------------------------------------------------------------------------------";
	
  	### Stop the internal timer for this module
	RemoveInternalTimer($hash);
	Log3 $name, 4, $name. " : UpsPico - CheckConnection - Internal Timer has been removed";
	
	###START###### Try to access UpsPIco to get I2C address range ##############################################START####
	my $port = $attr{$name}{Port};
	my $stderr = 0;
	my $RemotePiUser = $hash->{temp}{RemotePiUser};
	my $RemotePiPass = $hash->{temp}{RemotePiPass};
	my $stdout;
	my $exit;
	my $cmd;
	my $ssh;

	###START###### Reset fullResponse error message ############################################################START####
	readingsSingleUpdate( $hash, "fullResponse", "Checking Connection...", 1);
	####END####### Reset fullResponse error message #############################################################END#####
	
	eval {$ssh = Net::SSH::Perl->new($url);};
	if( $@ )
	{
		###Set warning for log file
		Log3 $name, 1, $name. " : UpsPico - CheckConnection - SSH Connection to RasPi with UPS-PIco could not be established since network connection failed. Retrying in 300s";

		### Stop the internal timer for this module and re-initiate the timer for another check of connection towards RasPi with UpsPico but wait 300s
		RemoveInternalTimer($hash);
		$hash->{temp}{FIRSTTIME} = true;
		InternalTimer(gettimeofday()+30, "UpsPico_CheckConnection", $hash, 0);
		Log3 $name, 4, $name. " : UpsPico - CheckConnection - Internal Timer has been removed and restarted to check connection again in 300s";

		undef $ssh;
		return undef;
	}
	else
	{
		eval {$ssh->login($RemotePiUser, $RemotePiPass);};
		if( $@ )
		{
			###Set warning for log file
			Log3 $name, 1, $name. " : UpsPico - CheckConnection - SSH Login to RasPi with UPS-PIco could not be established due to wrong credentials. Retrying in 300s";
			 
			### Stop the internal timer for this module and re-initiate the timer for another check of connection towards RasPi with UpsPico but wait 10s
			RemoveInternalTimer($hash);
			$hash->{temp}{FIRSTTIME} = true;
			InternalTimer(gettimeofday()+30, "UpsPico_CheckConnection", $hash, 0);
			Log3 $name, 4, $name. " : UpsPico - CheckConnection - Internal Timer has been removed and restarted to check connection again in 300s";
			
			undef $ssh;
			return undef;
		}
		else
		{
			#### Try out with factory default address
			$cmd  = "sudo i2cget -y 1 0x69 0x00 b";
			($stdout, $stderr, $exit) = $ssh->cmd($cmd);
			if(defined($stderr)) { Log3 $name, 2, $name. " : UpsPico - CheckConnection - Obtain I2C range with 0x69 - stderr        : " . $stderr;}
			if(defined($exit))   { Log3 $name, 5, $name. " : UpsPico - CheckConnection - Obtain I2C range with 0x69 - exit          : " . $exit;  }
			if(defined($stdout)) { Log3 $name, 5, $name. " : UpsPico - CheckConnection - Obtain I2C range with 0x69 - stdout        : " . $stdout;}
			Log3 $name, 5, $name. " : UpsPico - CheckConnection ----------------------------------------------------------";
		
			### If connection with status register on I2C address 0x69 was successfully
			if ($stdout ne "")
			{

				#### Try out whether RTC register are available
				$cmd  = "sudo i2cget -y 1 0x6A 0x00 b";
				($stdout, $stderr, $exit) = $ssh->cmd($cmd);
				if(defined($stderr)) { Log3 $name, 2, $name. " : UpsPico - CheckConnection - Obtain I2C range with 0x6A - stderr        : " . $stderr;}
				if(defined($exit))   { Log3 $name, 5, $name. " : UpsPico - CheckConnection - Obtain I2C range with 0x6A - exit          : " . $exit;  }
				if(defined($stdout)) { Log3 $name, 5, $name. " : UpsPico - CheckConnection - Obtain I2C range with 0x6A - stdout        : " . $stdout;}
				Log3 $name, 5, $name. " : UpsPico - CheckConnection ----------------------------------------------------------";

				### If connection with RTC register on I2C address 0x6A was successfully				
				if ($stdout ne "")
				{
					### Set I2CRegisterRange to "NORMAL"
					$hash->{I2cRegisterRange} = "NORMAL";
				}
				else
				{
					### Set I2CRegisterRange to "NO_RTC"
					$hash->{I2cRegisterRange} = "NO_RTC";				
				}
				
				###Initiate the timer for first time polling of  values from UpsPico but wait 10s
				RemoveInternalTimer($hash);
				$hash->{temp}{FIRSTTIME} = true;
				InternalTimer(gettimeofday()+10, "UpsPico_GetAllData", $hash, 0);
				Log3 $name, 3, $name. " : UpsPico - CheckConnection - I2C range has been set to                  : " . $hash->{I2cRegisterRange};
				Log3 $name, 4, $name. " : UpsPico - CheckConnection - Internal timer for Initialisation of services started for the first time.";
				
				###Set fullResponse error message
				readingsSingleUpdate( $hash, "fullResponse", "OK", 1);
			}
			### If connection was not successfully
			else
			{
				#### Try out with alternate address
				$cmd  = "sudo i2cget -y 1 0x59 0x00 b";
				($stdout, $stderr, $exit) = $ssh->cmd($cmd);
				if(defined($stderr)) { Log3 $name, 2, $name. " : UpsPico - CheckConnection - Obtain I2C range with 0x5A - stderr        : " . $stderr;}
				if(defined($exit))   { Log3 $name, 5, $name. " : UpsPico - CheckConnection - Obtain I2C range with 0x5A - exit          : " . $exit;  }
				if(defined($stdout)) { Log3 $name, 5, $name. " : UpsPico - CheckConnection - Obtain I2C range with 0x5A - stdout        : " . $stdout;}
				Log3 $name, 5, $name. " : UpsPico - CheckConnection ----------------------------------------------------------";
				
				### If connection with status register on I2C address 0x59 was successfully
				if ($stdout ne "")
				{
					$hash->{I2cRegisterRange} = "ALTERNATE";

					###Initiate the timer for first time polling of  values from UpsPico but wait 10s
					RemoveInternalTimer($hash);
					$hash->{temp}{FIRSTTIME} = true;
					InternalTimer(gettimeofday()+10, "UpsPico_GetAllData", $hash, 0);
					Log3 $name, 3, $name. " : UpsPico - CheckConnection - I2C range has been set to                  : " . $hash->{I2cRegisterRange};
					Log3 $name, 4, $name. " : UpsPico - CheckConnection - Internal timer for Initialisation of services started for the first time.";

					###Set fullResponse error message
					readingsSingleUpdate( $hash, "fullResponse", "OK", 1);
				}
				### Otherwise there is no UpsPIco connection available
				else
				{
					Log3 $name, 2, $name. " : UpsPico - CheckConnection - Connection to UPS-PIco could not be established. Terminating Initialisation!";
					###Set fullResponse error message
					readingsSingleUpdate( $hash, "fullResponse", "Error I2C-connection failed.  Check connection and re-define device.", 1);
					
					### Stop the internal timer for this module and re-initiate the timer for another check of connection towards RasPi with UpsPico but wait 10s
					RemoveInternalTimer($hash);
					$hash->{temp}{FIRSTTIME} = true;
					InternalTimer(gettimeofday()+10, "UpsPico_CheckConnection", $hash, 0);
					Log3 $name, 4, $name. " : UpsPico - CheckConnection - Internal Timer has been removed and restarted to check connection again in 10s";	
					return undef;
				}
			}			
		}
	}
	Log3 $name, 5, $name. " : UpsPico ----------------------------------------------------------------------------------------------------------------";
	return undef;
}
####END####### Check connection towards remote RasPi via SSH ###################################################END#####

###START###### Download all register ##########################################################################START####
sub UpsPico_GetAllData($@)
{
	my ($hash, $def)        		= @_;
	my $host 						= $hash->{URL};
	my $name                		= $hash->{NAME} ;
	my $user 						= $hash->{temp}{RemotePiUser};
	my $pass 						= $hash->{temp}{RemotePiPass};
	my $PollingInterval  	= $attr{$name}{PollingInterval};
	my %RegisterInfo 				= %{$hash->{temp}{RegisterInfo}};
	my %BattChargingInfo			= %{$hash->{temp}{BattChargingInfo}};
	my $port 						= $attr{$name}{Port};
	my $ssh;
	my $ReturnMessage;

	### Stop the current timer
	RemoveInternalTimer($hash);

	###START###### Reset fullResponse error message ############################################################START####
	readingsSingleUpdate( $hash, "fullResponse", "Downloading...", 1);
	####END####### Reset fullResponse error message #############################################################END#####	

	
	###START###### Set I2C address accordingly ###############################################################START####
	my %I2CAddress;

	if ($hash->{I2cRegisterRange} eq "NORMAL")
	{
		Log3 $name, 4, $name. " : UpsPico_GetAllData    - I2CRegisterRange has been set to NORMAL";
		$I2CAddress{Status} 	= 0x69;
		$I2CAddress{RTC} 		= 0x6a;
		$I2CAddress{Command}	= 0x6b;
		$I2CAddress{StartTS}	= 0x6c;
		$I2CAddress{RunTS}		= 0x6d;
		$I2CAddress{EventS}		= 0x6e;
		$I2CAddress{ActionS}	= 0x6f;
	}
	elsif ($hash->{I2cRegisterRange} eq "NO_RTC")
	{
		Log3 $name, 4, $name. " : UpsPico_GetAllData    - I2CRegisterRange has been set to NO_RTC";
		$I2CAddress{Status} 	= 0x69;
		$I2CAddress{RTC} 		= undef;
		$I2CAddress{Command}	= 0x6b;
		$I2CAddress{StartTS}	= undef;
		$I2CAddress{RunTS}		= undef;
		$I2CAddress{EventS}		= undef;
		$I2CAddress{ActionS}	= undef;
	}
	elsif ($hash->{I2cRegisterRange} eq "ALTERNATE")
	{
		Log3 $name, 4, $name. " : UpsPico_GetAllData    - I2CRegisterRange has been set to ALTERNATE";
		$I2CAddress{Status} 	= 0x59;
		$I2CAddress{RTC} 		= 0x5a;
		$I2CAddress{Command}	= 0x5b;
		$I2CAddress{StartTS}	= 0x5c;
		$I2CAddress{RunTS}		= 0x5d;
		$I2CAddress{EventS}		= 0x5e;
		$I2CAddress{ActionS}	= 0x5f;
	}
	####END####### Set I2C address accordingly #################################################################END#####

	###START######  Check whether all required attributes exists otherwise create them with standard values ###BEGIN####
	if(!defined($attr{$name}{Port}))
	{
		### Set attribute with standard value since it is not available
		$attr{$name}{Port} 	= 22;

		### Writing log entry
		Log3 $name, 3, $name. " : UpsPico - The attribute SSH-Port was missing and has been set to " . $attr{$name}{Port};
	}
	if(!defined($attr{$name}{PollingInterval}))
	{
		### Set attribute with standard value since it is not available
		$attr{$name}{PollingInterval} 	= 300;

		### Writing log entry
		Log3 $name, 3, $name. " : UpsPico - The attribute PollingInterval was missing and has been set to " . $attr{$name}{PollingInterval};
	}
	if(!defined($attr{$name}{room}))
	{
		### Set attribute with standard value since it is not available
		$attr{$name}{room} 	= "UpsPIco";

		### Writing log entry
		Log3 $name, 3, $name. " : UpsPico - The attribute for room was missing and has been set to " . $attr{$name}{room};
	}
	if(!defined($attr{$name}{WriteCritical}))
	{
		### Set attribute with standard value since it is not available
		$attr{$name}{WriteCritical} = 0;

		### Writing log entry
		Log3 $name, 3, $name. " : UpsPico - The attribute for allowing to write critical register was missing and has been set to " . $attr{$name}{WriteCritical};
	}
	if(!defined($attr{$name}{CredentialsEncrypted}))
	{
		### Set attribute with standard value since it is not available
		$attr{$name}{CredentialsEncrypted} = 0;

		### Writing log entry
		Log3 $name, 3, $name. " : UpsPico - The attribute for the Credentials being encrypted has been set to " . $attr{$name}{CredentialsEncrypted};
	}
	if(!defined($attr{$name}{DbLogExclude}))
	{
		### Set attribute with standard value since it is not available
		$attr{$name}{DbLogExclude} = "/Status/pico_is_running";

		### Writing log entry
		Log3 $name, 3, $name. " : UpsPico - The attribute for excluding the logging of the pico_is_running - status has been set.";
	}
	if(!defined($attr{$name}{"event-on-change-reading"}))
	{
		### Set attribute with standard value since it is not available
		$attr{$name}{"event-on-change-reading"} = ".*";

		### Writing log entry
		Log3 $name, 3, $name. " : UpsPico - The attribute for logging only on changed values has been set to all readings.";
	}
	####END#######  Check whether all required attributes exists otherwise create them with standard values ####END#####
	
	###START###### Check connection ###########################################################################START####
	
	### Check whether the network connection still exists
	eval {$ssh = Net::SSH::Perl->new($host);};
	if( $@ )
	{
		###Set warning for log file
		Log3 $name, 1, $name. " : UpsPico_GetAllData    - SSH Connection to RasPi with UPS-PIco could not be established. Terminating Initialisation!";

		###Set fullResponse error message
		readingsSingleUpdate( $hash, "fullResponse", "Error: SSH-connection failed", 1);

		### Stop the internal timer for this module and re-initiate the timer for another check of connection towards RasPi with UpsPico but wait 10s
		RemoveInternalTimer($hash);
		$hash->{temp}{FIRSTTIME} = true;		
		InternalTimer(gettimeofday()+10, "UpsPico_CheckConnection", $hash, 0);
		Log3 $name, 4, $name. " : UpsPico_GetAllData    - Error SSH-connection failed.";

		undef $ssh;
		return undef;
	}

	### Check whether the credentials are still valid
	eval {$ssh->login($user, $pass);};
	if( $@ )
	{
		###Set warning for log file
		Log3 $name, 1, $name. " : UpsPico_GetAllData    - SSH Login to RasPi with UPS-PIco could not be established. Terminating Initialisation!";

		###Set fullResponse error message
		readingsSingleUpdate( $hash, "fullResponse", "Error SSH-Login failed - Check Credentials", 1);

		### Stop the internal timer for this module and re-initiate the timer for another check of connection towards RasPi with UpsPico but wait 10s
		RemoveInternalTimer($hash);
		$hash->{temp}{FIRSTTIME} = true;
		InternalTimer(gettimeofday()+10, "UpsPico_CheckConnection", $hash, 0);
		Log3 $name, 1, $name. " : UpsPico_GetAllData    - Error SSH-Login failed - Check Credentials";			

		undef $ssh;
		return undef;
	}
	####END####### Check connection ############################################################################END#####

	###START###### Download register block from UPS PIco via ssh command ######################################START####
	foreach my $RegisterI2CBlock (keys %I2CAddress) 
	{
		###START##### Download Register #######################################################################START####
		if (defined($I2CAddress{$RegisterI2CBlock}))
		{
			Log3 $name, 4, $name. " : UpsPico_GetAllData    - working on Registerblock: " . $RegisterI2CBlock;	

			my @RegisterBlock;
			my $stdout;
			my $stderr = 0;
			my $exit;
			my $SshCmd   = "sudo i2cdump -y -r 0-255 1 " . int($I2CAddress{$RegisterI2CBlock}) . " b";		
			($stdout, $stderr, $exit) = $ssh->cmd($SshCmd);

			### For debugging purposes only
			if(defined($stderr)) { Log3 $name, 2, $name. " : UpsPico_GetAllData    - stderr " . $RegisterI2CBlock . "       : "   . $stderr; }
			if(defined($exit))   { Log3 $name, 5, $name. " : UpsPico_GetAllData    - exit   " . $RegisterI2CBlock . "       : "   . $exit;   }
			if(defined($stdout)) { Log3 $name, 5, $name. " : UpsPico_GetAllData    - stdout " . $RegisterI2CBlock . "       : \n" . $stdout; }
			Log3 $name, 5, $name. " : UpsPico_GetAllData ------------------------------------------------------------------------------------";

			my @BlockRegister	= split(/  /, $stdout);
			Log3 $name, 5, $name. " : UpsPico_GetAllData    - BlockRegister" . $RegisterI2CBlock . " : \n" . Dumper \@BlockRegister;
			Log3 $name, 5, $name. " : UpsPico_GetAllData ------------------------------------------------------------------------------------";
			
			my $LineNumber;
			for ($LineNumber = 19; $LineNumber < 530; $LineNumber = $LineNumber + 2) 
			{
				my @TempRegister = split(/ /, $BlockRegister[$LineNumber]);
				splice(@TempRegister, 0, 1);
				push(@RegisterBlock,@TempRegister);
			}
			Log3 $name, 4, $name. " : UpsPico_GetAllData    - RegisterBlock " . $RegisterI2CBlock . " successfully downloaded";
			Log3 $name, 5, $name. " : UpsPico_GetAllData    - RegisterBlock " . $RegisterI2CBlock . " : \n" . Dumper \@RegisterBlock;
			Log3 $name, 5, $name. " : UpsPico_GetAllData ------------------------------------------------------------------------------------";

			foreach my $RegisterName (keys %RegisterInfo) 
			{
				### If the Register-Information belongs to the current Register
				if ($RegisterInfo{$RegisterName}{RegisterBlockName} eq $RegisterI2CBlock)
				{
					if ($RegisterInfo{$RegisterName}{DataType} eq "Byte")
					{
						### Mark SelectionList Item as not yet found
						my $FoundSelectionListItem = false;
						
						### If SelectionList exists for this Register
						if ($RegisterInfo{$RegisterName}{SelectionList} ne undef)
						{
							### Extract Selectionlist from hash
							my %SelectionList = %{$RegisterInfo{$RegisterName}{SelectionList}};

							### For debugging purposes only
							Log3 $name, 5, $name. " : UpsPico_GetAllData -----------------Finding the Selection List entries for " . $RegisterName . "--------------------------------------------------------";
							Log3 $name, 5, $name. " : UpsPico_GetAllData    - Register to be searched in SeletionListEntry     : " .    ($RegisterBlock[$RegisterInfo{$RegisterName}{RegisterAddress}]);
							Log3 $name, 5, $name. " : UpsPico_GetAllData    - Register to be searched in SeletionListEntry hex : " . hex($RegisterBlock[$RegisterInfo{$RegisterName}{RegisterAddress}]);
							
							### Search for the correct alias in the SelectionList
							foreach my $SeletionListEntry (keys %SelectionList) 
							{
								Log3 $name, 5, $name. " : UpsPico_GetAllData    - SeletionListEntry                                : " .    ($SeletionListEntry);
							
								### If the RegisterValue matches with the Key of the Selectionlist
								if ((($SeletionListEntry) eq hex($RegisterBlock[$RegisterInfo{$RegisterName}{RegisterAddress}])) && ($SeletionListEntry ne "Default"))
								{
									Log3 $name, 5, $name. " : UpsPico_GetAllData    - Found    matching SeletionListEntry for          : " . $SeletionListEntry . ". The value is: " . $SelectionList{$SeletionListEntry};

									### Save the alias as value into the Register - hash
									$RegisterInfo{$RegisterName}{Value} = $SelectionList{$SeletionListEntry};
									Log3 $name, 4, $name. " : UpsPico_GetAllData    - SelectionList Alias from  " . $RegisterI2CBlock . " Register stored in Register-Hash for " . $RegisterName;
									
									### Mark SelectionList Item as bein already found
									$FoundSelectionListItem = true;
								}
								### If there is no match
								else
								{
									Log3 $name, 5, $name. " : UpsPico_GetAllData    - Found NO matching SeletionListEntry for          : " . $SeletionListEntry;

									### Only set default value if the SelectionList item has not been found yet
									if ($FoundSelectionListItem == false)
									{
										### Save the default value as value into the Register - hash
										$RegisterInfo{$RegisterName}{Value} = $SelectionList{Default};
										Log3 $name, 4, $name. " : UpsPico_GetAllData    - SelectionList Default from " . $RegisterI2CBlock . " Register stored in Register-Hash for " . $RegisterName;
									}
								}
							}
							Log3 $name, 4, $name. " : UpsPico_GetAllData    - Byte Value with SelectionList formation from  " . $RegisterI2CBlock . " Register stored in Register-Hash for " . $RegisterName;
							
							### If the SelectionList Vaulue is a mathematical function which needs to be calculated							
							if (index($RegisterInfo{$RegisterName}{Value}, "Function: ") != -1)
							{
								### Transform RegisterValue from hex into integer
								my $RegisterValue = hex($RegisterBlock[$RegisterInfo{$RegisterName}{RegisterAddress}]);								
								
								### Extract formula from SelectionList
								my $MathExpression = $RegisterInfo{$RegisterName}{Value};
								
								### Remove the keyword "Function " from the function string
								$MathExpression =~ s/Function: //;

								### Create Parsing object for mathematical expression
								my $MathParsingObject = Math::Expression::Evaluator->new;

								### Perform parsing and do calculation
								my $TempCalcResult = $MathParsingObject->parse("RegisterValue = " . $RegisterValue . "; " . $MathExpression)->val();
								
								### Save the default value as value into the Register - hash
								$RegisterInfo{$RegisterName}{Value} = $TempCalcResult;
								
								### For debugging purposes only
								Log3 $name, 5, $name. " : UpsPico_GetAllData    - A mathematical formula has been found in the selection list.";
								Log3 $name, 5, $name. " : UpsPico_GetAllData    - RegisterValue                                    : " . $RegisterValue;
								Log3 $name, 5, $name. " : UpsPico_GetAllData    - Expression of formula in SeletctionList          : " . $MathExpression;
								Log3 $name, 5, $name. " : UpsPico_GetAllData    - Result of formula in TempCalcResult              : " . $TempCalcResult;
							}
						}
						### If SelectionList does not exists for this Register
						else
						{
							### If the Byte Value is bound to a unit and shown as hex corresponds to BCD
							if ($RegisterInfo{$RegisterName}{Unit} ne undef)
							{
							### Just write Register-Value into Hash
							$RegisterInfo{$RegisterName}{Value} = $RegisterBlock[$RegisterInfo{$RegisterName}{RegisterAddress}];
							Log3 $name, 4, $name. " : UpsPico_GetAllData    - Byte Value as BCD from  " . $RegisterI2CBlock . " Register stored in Register-Hash for " . $RegisterName;
							}
							### If the Byte Value is not bound to a unit so do not transform it
							else
							{
							### Just write Register-Value into Hash
							$RegisterInfo{$RegisterName}{Value} = "0x" . sprintf("%02d", $RegisterBlock[$RegisterInfo{$RegisterName}{RegisterAddress}]);
							Log3 $name, 4, $name. " : UpsPico_GetAllData    - Byte Value as hex from " . $RegisterI2CBlock . " Register stored in Register-Hash for " . $RegisterName;
							}
						}
					}
					elsif ($RegisterInfo{$RegisterName}{DataType} eq "WordBCD")
					{
						$RegisterInfo{$RegisterName}{Value} = int($RegisterBlock[$RegisterInfo{$RegisterName}{RegisterAddress} + 1] . $RegisterBlock[$RegisterInfo{$RegisterName}{RegisterAddress}]) * $RegisterInfo{$RegisterName}{Factor};
						
						Log3 $name, 4, $name. " : UpsPico_GetAllData    - Word Value from  " . $RegisterI2CBlock . " Register stored in Register-Hash for "   . $RegisterName;

						Log3 $name, 5, $name. " : UpsPico_GetAllData    - Word Value - RegisterBlock[RegisterInfo{RegisterName}{RegisterAddress} + 0      : " . $RegisterBlock[$RegisterInfo{$RegisterName}{RegisterAddress}    ]  ;
						Log3 $name, 5, $name. " : UpsPico_GetAllData    - Word Value - RegisterBlock[RegisterInfo{RegisterName}{RegisterAddress} + 1      : " . $RegisterBlock[$RegisterInfo{$RegisterName}{RegisterAddress} + 1]  ;
						Log3 $name, 5, $name. " : UpsPico_GetAllData    - Word Value - RegisterBlock[RegisterInfo{RegisterName}{RegisterAddress} + 1 & +0 : " . $RegisterBlock[$RegisterInfo{$RegisterName}{RegisterAddress} + 1] . $RegisterBlock[$RegisterInfo{$RegisterName}{RegisterAddress}];
						Log3 $name, 5, $name. " : UpsPico_GetAllData    - Word Value - RegisterInfo{RegisterName}{Factor}                                 : " . $RegisterInfo{$RegisterName}{Factor};
						Log3 $name, 5, $name. " : UpsPico_GetAllData    - Word Value - RegisterInfo{RegisterName}{Value}                                  : " . $RegisterInfo{$RegisterName}{Value};						
					}
					elsif ($RegisterInfo{$RegisterName}{DataType} eq "WordHex")
					{
						$RegisterInfo{$RegisterName}{Value} = hex($RegisterBlock[$RegisterInfo{$RegisterName}{RegisterAddress} + 1] . $RegisterBlock[$RegisterInfo{$RegisterName}{RegisterAddress}]) * $RegisterInfo{$RegisterName}{Factor};
						
						Log3 $name, 4, $name. " : UpsPico_GetAllData    - Word Value from  " . $RegisterI2CBlock . " Register stored in Register-Hash for " . $RegisterName;

						Log3 $name, 5, $name. " : UpsPico_GetAllData    - Word Value - RegisterBlock[RegisterInfo{RegisterName}{RegisterAddress} + 0      : " . $RegisterBlock[$RegisterInfo{$RegisterName}{RegisterAddress}    ]  ;
						Log3 $name, 5, $name. " : UpsPico_GetAllData    - Word Value - RegisterBlock[RegisterInfo{RegisterName}{RegisterAddress} + 1      : " . $RegisterBlock[$RegisterInfo{$RegisterName}{RegisterAddress} + 1]  ;
						Log3 $name, 5, $name. " : UpsPico_GetAllData    - Word Value - RegisterBlock[RegisterInfo{RegisterName}{RegisterAddress} + 1 & +0 : " . $RegisterBlock[$RegisterInfo{$RegisterName}{RegisterAddress} + 1] . $RegisterBlock[$RegisterInfo{$RegisterName}{RegisterAddress}];
						Log3 $name, 5, $name. " : UpsPico_GetAllData    - Word Value - RegisterInfo{RegisterName}{Factor}                                 : " . $RegisterInfo{$RegisterName}{Factor};
						Log3 $name, 5, $name. " : UpsPico_GetAllData    - Word Value - RegisterInfo{RegisterName}{Value}                                  : " . $RegisterInfo{$RegisterName}{Value};						
					}
					elsif ($RegisterInfo{$RegisterName}{DataType} eq "ASCII")
					{
						$RegisterInfo{$RegisterName}{Value} = chr(hex($RegisterBlock[$RegisterInfo{$RegisterName}{RegisterAddress}]));
						Log3 $name, 4, $name. " : UpsPico_GetAllData    - ASCII Value from " . $RegisterI2CBlock . " Register stored in Register-Hash for " . $RegisterName;
					}
					elsif ($RegisterInfo{$RegisterName}{DataType} eq "Hex")
					{
						$RegisterInfo{$RegisterName}{Value} = hex($RegisterBlock[$RegisterInfo{$RegisterName}{RegisterAddress}]);
						Log3 $name, 4, $name. " : UpsPico_GetAllData    - Hex Value from " . $RegisterI2CBlock . " Register transformed into Integer and stored in Register-Hash for " . $RegisterName;
					}
					else
					{
						$RegisterInfo{$RegisterName}{Value} = "ERROR";
						Log3 $name, 2, $name. " : UpsPico_GetAllData    - ERROR - No Data Type found in Register-Hash for " . $RegisterName;
					}

					### If the Register needs to be reset after reading, write 0x00 into register.
					if(($RegisterInfo{$RegisterName}{Reset} == true))
					{
						my $SshCmdStatus   = "sudo i2cset -y 1 " . $I2CAddress{$RegisterI2CBlock} . " " . $RegisterInfo{$RegisterName}{RegisterAddress} . " 0";		
						($stdout, $stderr, $exit) = $ssh->cmd($SshCmdStatus);
											   Log3 $name, 4, $name. " : UpsPico_GetAllData    - Resetting Register to 0x00 for                   : "   . $RegisterName;
						                       Log3 $name, 5, $name. " : UpsPico_GetAllData    - SshCmdStatus                                     : "   . $SshCmdStatus;
						if(defined($stderr)) { Log3 $name, 2, $name. " : UpsPico_GetAllData    - stderr Reset                                     : "   . $stderr;      }
						if(defined($exit))   { Log3 $name, 5, $name. " : UpsPico_GetAllData    - exit   Reset                                     : "   . $exit;        }
						if(defined($stdout)) { Log3 $name, 5, $name. " : UpsPico_GetAllData    - stdout Reset                                     : \n" . $stdout;      }
						                       Log3 $name, 5, $name. " : UpsPico_GetAllData ------------------------------------------------------------------------------------";

					}		
					### Write current value
					readingsSingleUpdate($hash, "/" . $RegisterI2CBlock . "/" . $RegisterName, $RegisterInfo{$RegisterName}{Value},1);
				}
			}
		}
		####END###### Download Register ########################################################################END#####
	}
	####END####### Download register block from UPS PIco via ssh command #######################################END#####

	###START###### Calculate and save Battery charging status #################################################START####
	Log3 $name, 5, $name. " : UpsPico_GetAllData    - charge status - battype value                    : " . $RegisterInfo{"battype"}{Value};	
	
	if ($RegisterInfo{"battype"}{Value} ne undef)
	{
		my $ChargeState;
		my $BattType 			= $RegisterInfo{"battype"}{Value};
		my $FoundBatteryItem 	= false;
		my $BattChargingState   = "ERROR - No Battery found";

		### Search for the correct alias in the SelectionList
		foreach my $BattInfoEntry (keys %BattChargingInfo) 
		{
			Log3 $name, 5, $name. " : UpsPico_GetAllData    - charge status - BattInfoEntry                    : " . $RegisterInfo{"battype"}{Value};
			
			### If the entry has been found
			if ($BattInfoEntry eq $BattType)
			{
				### For debugging purpose only
				Log3 $name, 5, $name. " : UpsPico_GetAllData    - charge status - Found battype! ";
				Log3 $name, 5, $name. " : UpsPico_GetAllData    - charge status - BattType                         : " . $BattInfoEntry;
				Log3 $name, 5, $name. " : UpsPico_GetAllData    - charge status - 0   Percent Voltage              : " . $BattChargingInfo{$BattInfoEntry}{Volt0Percent};
				Log3 $name, 5, $name. " : UpsPico_GetAllData    - charge status - 100 Percent Voltage              : " . $BattChargingInfo{$BattInfoEntry}{Volt100Percent};
				Log3 $name, 5, $name. " : UpsPico_GetAllData    - charge status - Measured Voltage                 : " . $RegisterInfo{"batlevel"}{Value};
				
				my $BatVoltageLevel = $RegisterInfo{"batlevel"}{Value};
				
				### Limit Voltagelevel to maximum to avoid indication of temporary overcharging
				if ($BatVoltageLevel > $BattChargingInfo{$BattInfoEntry}{Volt100Percent})
				{
					$BatVoltageLevel = $BattChargingInfo{$BattInfoEntry}{Volt100Percent}
				}
				
				### Calculate Battery state of charging 
				$BattChargingState  = sprintf("%02d", ((($BatVoltageLevel - $BattChargingInfo{$BattInfoEntry}{Volt0Percent}) / ($BattChargingInfo{$BattInfoEntry}{Volt100Percent} - $BattChargingInfo{$BattInfoEntry}{Volt0Percent})) * 100));
			}
		}

		### Write current value to reading and STATE
		readingsSingleUpdate($hash, "BattCharge", $BattChargingState,1);
		$hash->{STATE} = $BattChargingState;

		Log3 $name, 4, $name. " : UpsPico_GetAllData    - charge status - BattChargingState                : " . $BattChargingState;
	}
	####END####### Calculate and save Battery charging status ##################################################END#####
	
	
	### For Debugging purpose only 
	Log3 $name, 5, $name. " : UpsPico_GetAllData    - RegisterInfo in fhem-hash                        : \n" . Dumper \$hash->{temp}{RegisterInfo};
	Log3 $name, 5, $name. " : UpsPico_GetAllData -----------------------------------------------------------------";
	
	### Close SSH session
	undef $ssh;
	Log3 $name, 4, $name. " : UpsPico_GetAllData    - SSH session closed";
	Log3 $name, 5, $name. " : UpsPico_GetAllData ----------------------------------------------------------------------------------------------------------------";
	####END####### Download register block from UPS PIco via ssh command #######################################END#####

	#### Initiate the timer for continuous polling of all data from UpsPico
	InternalTimer(gettimeofday()+$PollingInterval, "UpsPico_GetAllData", $hash, 0);
	Log3 $name, 4, $name. " : UpsPico_GetAllData    - Define: InternalTimer for GettAllData re-started with interval of: " . $PollingInterval . " s";

	###START###### Reset fullResponse error message ############################################################START####
	readingsSingleUpdate( $hash, "fullResponse", "Standby", 1);
	####END####### Reset fullResponse error message #############################################################END#####	
}
####END####### Download all register ###########################################################################END#####
1;
=pod
=item device
=item summary    Connects fhem to UpsPIco on remote RasPi
=item summary_DE Verbindet fhem mit einem UpsPIco auf einem entfernten RasPi

=begin html

<a name="UpsPico"></a>
<h3>UpsPico</h3>
<ul>
	<table>
		<tr>
			<td>
				The UpsPIco is an interruptible Power Supply for the Raspberry Pi from PiModules. This module is written for the Firmware Version 0x38 and above and has been tested on the "UPS PIco HV3.0A Stack Plus" only.<BR>
				This module provides all the internal data written in the UpsPIco register which are accessible via I2C - Bus. The set command is able to change the values in accordance to the specifications.<BR>
				For details to the Information contained in the register, please consult the internal register specification published in the latest manual. (See below)<BR>
				<BR>
				<u>References:</u><BR>
				<a href="http://www.pimodulescart.com/shop/item.aspx?itemid=29">UPS PIco HV3.0A Stack Plus</a><BR>
				<a href="http://www.forum.pimodules.com/viewforum.php?f=25">UPS PIco HV3.0A : Internal Register Specification, Manuals and Firmware Updates</a><BR>
				<BR>
			</td>
		</tr>
	</table>
	  
	<table>
	<tr><td><a name="UpsPicodefine"></a><b>Define</b></td></tr>
	</table>

	<table><tr><td><ul><code>define &lt;name&gt; UpsPico &lt;IPv4-address&gt; &lt;Username&gt; &lt;Password&gt;</code></ul></td></tr></table>

	<ul><ul>
		<table>
			<tr><td><code>&lt;name&gt;</code> : </td><td>The name of the device. Recommendation: "myUpsPico".</td></tr>
			<tr><td><code>&lt;IPv4-address&gt;</code> : </td><td>A valid IPv4 address of the Raspberry Pi with UpsPIco. You might look into your router which DHCP address has been given to the RasPi.</td></tr>
			<tr><td><code>&lt;GatewayPassword&gt;</code> : </td><td>The username of the remote Raspberry Pi.</td></tr>
			<tr><td><code>&lt;PrivatePassword&gt;</code> : </td><td>The password of the remote Raspberry Pi.</td></tr>
		</table>
	</ul></ul>

	<BR>

	<table>
		<tr><td><a name="UpsPicoSet"></a><b>Set</b></td></tr>
		<tr><td>
			<ul>
					The set function is able to change a value which is marked as writeable.<BR>
					If the register is considered as a critical setting (e.g. a wrong value might result in permanent damage), the attribute "WriteCritical" must be set to "1" = yes beforehand.
			</ul>
		</td></tr>
	</table>

	<table><tr><td><ul><code>set &lt;name&gt; &lt;register&gt; &lt;value&gt;</code></ul></td></tr></table>

	<ul><ul>
		<table>
			<tr><td><code>&lt;name&gt;</code>      : </td><td>The name of the defined UpsPico device<BR></td></tr>
			<tr><td><code>&lt;register&gt;</code>  : </td><td>The name of the register which value shall be set. E.g.: "<code>/Status/key</code>"<BR></td></tr>
			<tr><td><code>&lt;value&gt;</code>     : </td><td>A valid value for this register.<BR></td></tr>
		</table>
	</ul></ul>

	<BR>

	<table>
		<tr><td><a name="UpsPicoGet"></a><b>Get</b></td></tr>
		<tr><td>
			<ul>
					The get function is able to obtain a value of a register.<BR>
					It returns only the value but not the unit or the range or list of allowed values possible.<BR>
			</ul>
		</td></tr>
	</table>

	<table><tr><td><ul><code>get &lt;name&gt; &lt;register&gt;</code></ul></td></tr></table>

	<ul><ul>
		<table>
			<tr><td><code>&lt;name&gt;</code> : </td><td>The name of the defined UpsPico device<BR></td></tr>
			<tr><td><code>&lt;register&gt;</code>  : </td><td>The name of the register which value shall be obtained. E.g.: "<code>/Status/key</code>"<BR></td></tr>

				</td>
			</tr>
		</table>
	</ul></ul>

	<BR>

	<table>
		<tr><td><a name="UpsPicoAttr"></a><b>Attributes</b></td></tr>
		<tr><td>
			<ul>
				<BR>
				The following user attributes can be used with the UpsPico module in addition to the general ones e.g. <a href="#room">room</a>.<BR>
			</ul>
		</td></tr>
	</table>

	<table>
		<td>
			<ul><ul>
					<tr>
						<td>
						<BR>
						<tr><td><ul><li><code>PollingInterval</code> : </li></td><td>A valid polling interval for the values of the UPS PIco. The value must be >=20s to allow the UpsPico module to perform a full polling procedure. <BR>
																					 The default value is 300s.<BR>
						</ul></td></tr>
						</td>
					</tr>
			</ul></ul>

			<ul><ul>

					<tr>
						<td>
						<BR>
						<tr><td><ul><li><code>WriteCritical</code> : </li></td><td>Prevents acidential damaging of the UpsPico hardware by change of critical register with wrong values.<BR>
																				   The attribute must be re-activated for every single set-command.<BR>
																				   The default value is 0 = deactivated<BR>
						</ul></td></tr>
						</td>
					</tr>

			</ul></ul>

			<ul><ul>
					<tr>
						<td>
						<BR>
						<tr><td><ul><li><code>Port</code> : </li></td><td>The port number for the SSH access on the remote system.<BR>
																	  The default value is 22 = Standard SSH port<BR>
					   </ul></td></tr>
						</td>
					</tr>
			</ul></ul>

			<ul><ul>
					<tr>
						<td>
						<BR>
						<tr><td><ul><li><code>CredentialsEncrypted</code> : </li></td><td>This attributes will swap from plain text to base64 encrypted credentials in the definition.<BR>
																						  The default value is 0 = Plain Text Credentials<BR>
						</ul></td></tr>
						</td>
					</tr>
			</ul></ul>

			<ul><ul>
					<tr>
						<td>
						<BR>
						<tr><td><ul><li><code>DbLogExclude</code> : </li></td><td>This general attribute will be set automatically to the reading "/Status/pico_is_running" which is a continously counting WatchDog register.<BR>
																			  It makes no sense to log this reading.<BR>
																			  The default exclusion from logging is "/Status/pico_is_running" <BR>
						</ul></td></tr>
						</td>
					</tr>
			</ul></ul>

			<ul><ul>
					<tr>
						<td>
						<BR>
						<tr><td><ul><li><code>event-on-change-reading</code> : </li></td><td>This general attribute will be set automatically to  ".*" which prevents unchanged but updated readings to be logged.<BR>
																		   The default value is ".*" = Apply to all readings.<BR>
						</ul></td></tr>
						</td>
					</tr>
			</ul></ul>

			<ul><ul>
					<tr>
						<td>
						<BR>
						<tr><td><ul><li><code>room</code> : </li></td><td>This general attribute will be set automatically to  "UpsPIco" which prevents the device getting lost in the "Everything" room.<BR>
																	  The default value is "UpsPIco".<BR>
						</ul></td></tr>
						</td>
					</tr>
			</ul></ul>
		</td>
	</table>
</ul>
=end html

=begin html_DE

<a name="UpsPico"></a>
<h3>UpsPico</h3>
<ul>
	<table>
		<tr>
			<td>
				Der UpsPIco ist eine unterbrechungsfreie Stroimversorgung f&uuml;r den Raspberry Pi von PiModules. Dieses Modul wurde f&uuml;r die Firmware ab Version 0x38 und h&ouml;her geschrieben und wurde nur auf dem "UPS PIco HV3.0A Stack Plus" getestet.<BR>
				Dieses Modul stellt alle internen Daten zur Verf&uuml;gung, welche in die UpsPIco Register geschrieben und &uuml;ber den I2C - Bus ausgelesen werden. Der set-Befehl ist dar&uuml;ber hinaus in der Lage die Werte der Register entsprechend Ihrer Spezifikation zu &auml;ndern.<BR>
				Detailierte Informationen zu den einzelnen Registern stehen in den Register Spezifikationen in der letzten ver&ouml;ffentlichten Anleitung. (Siehe unten)<BR>
				<BR>
				<u>Referenzen:</u><BR>
				<a href="http://www.pimodulescart.com/shop/item.aspx?itemid=29">UPS PIco HV3.0A Stack Plus</a><BR>
				<a href="http://www.forum.pimodules.com/viewforum.php?f=25">UPS PIco HV3.0A : Interne Register Spezification, Anleitung and Firmware Updates</a><BR>
				<BR>
			</td>
		</tr>
	</table>
	  
	<table>
	<tr><td><a name="UpsPicodefine"></a><b>Define</b></td></tr>
	</table>

	<table><tr><td><ul><code>define &lt;name&gt; UpsPico &lt;IPv4-address&gt; &lt;Username&gt; &lt;Password&gt;</code></ul></td></tr></table>

	<ul><ul>
		<table>
			<tr><td><code>&lt;name&gt;</code> : </td><td>Der Name des Device. Empfehlung: "myUpsPico".</td></tr>
			<tr><td><code>&lt;IPv4-address&gt;</code> : </td><td>Eine g&uuml;ltige IPv4 Adresse des Raspberry Pi mit UpsPIco. Gegebenenfalls muss der Router f&uuml;r die an den Raspberry Pi vergebene DHCP Adresse konsultiert werden.</td></tr>
			<tr><td><code>&lt;GatewayPassword&gt;</code> : </td><td>Der Username des entfernten Raspberry Pi.</td></tr>
			<tr><td><code>&lt;PrivatePassword&gt;</code> : </td><td>Das Passwort des entfernten Raspberry Pi.</td></tr>
		</table>
	</ul></ul>

	<BR>

	<table>
		<tr><td><a name="UpsPicoSet"></a><b>Set</b></td></tr>
		<tr><td>
			<ul>
					Diese Funktion ver&auml;ndert die Werte der register, welche als beschreibbar definiert sind.<BR>
					Sind die entsprechenden Register als kritisch (critical) spezifiziert (Ein falscher Wert k&ouml;nnte zur Besch&auml;digung des UpsPIco f&uuml;hren), muss das Atttribut "WriteCritical" vorher auf "1" gesetzt werden.
			</ul>
		</td></tr>
	</table>

	<table><tr><td><ul><code>set &lt;name&gt; &lt;register&gt; &lt;value&gt;</code></ul></td></tr></table>

	<ul><ul>
		<table>
			<tr><td><code>&lt;name&gt;</code>      : </td><td>Der name des definierten UpsPico Device<BR></td></tr>
			<tr><td><code>&lt;register&gt;</code>  : </td><td>Der name des Registers welches ver&auml;ndert werden soll. E.g.: "<code>/Status/key</code>"<BR></td></tr>
			<tr><td><code>&lt;value&gt;</code>     : </td><td>Ein g&uuml;ltiger Wert f&uuml;r das Register.<BR></td></tr>
		</table>
	</ul></ul>

	<BR>

	<table>
		<tr><td><a name="UpsPicoGet"></a><b>Get</b></td></tr>
		<tr><td>
			<ul>
					Die get Funktion liest einzelne Register aus und schreibt sie in das entsprechende Reading.<BR>
					Es wird nur der Wert, aber nicht die Einheit oder der g&uuml;ltige Wertebereich zur&uuml;ckgegeben.<BR>
			</ul>
		</td></tr>
	</table>

	<table><tr><td><ul><code>get &lt;name&gt; &lt;register&gt;</code></ul></td></tr></table>

	<ul><ul>
		<table>
			<tr><td><code>&lt;name&gt;</code> : </td><td>Der name des definierten UpsPico Device<BR></td></tr>
			<tr><td><code>&lt;register&gt;</code>  : </td><td>Der name des Registers welches ausgelesen werden soll. E.g.: "<code>/Status/key</code>"<BR></td></tr>

				</td>
			</tr>
		</table>
	</ul></ul>

	<BR>

	<table>
		<tr><td><a name="UpsPicoAttr"></a><b>Attributes</b></td></tr>
		<tr><td>
			<ul>
				<BR>
				Die folgenden Attribute k&ouml;nnen neben den allgemeinen Attributen wie <a href="#room">room</a> vergeben werden.<BR>
			</ul>
		</td></tr>
	</table>

	<table>
		<td>
			<ul><ul>
					<tr>
						<td>
						<BR>
						<tr><td><ul><li><code>PollingInterval</code> : </li></td><td>Abrageinterval f&uuml;r den UPS PIco. Der Wert muss >=20s sein um einen vollen Polling Zyklus zu erlauben.<BR>
																					 Der Defaul Wert ist 300s.<BR>
						</ul></td></tr>
						</td>
					</tr>
			</ul></ul>

			<ul><ul>

					<tr>
						<td>
						<BR>
						<tr><td><ul><li><code>WriteCritical</code> : </li></td><td>Verhindert versehentliche Besch&auml;digungen durch Beschreiben der kritischen Register mit falschen Werten.<BR>
																				   Musz f&uuml;r jeden einzelnen Schreibvorgang erneut gesetzt werden da dieser zur&uuml;ckgesetzt wird..<BR>
																				   Der Default Wert ist 0 = Deaktiviert.<BR>
						</ul></td></tr>
						</td>
					</tr>

			</ul></ul>

			<ul><ul>
					<tr>
						<td>
						<BR>
						<tr><td><ul><li><code>Port</code> : </li></td><td>Port Nummer f&uuml;r den SSH Zugang am entfernten Raspberry Pi.<BR>
																		  Der Default Wert ist 22 = Standard SSH Port<BR>
					   </ul></td></tr>
						</td>
					</tr>
			</ul></ul>

			<ul><ul>
					<tr>
						<td>
						<BR>
						<tr><td><ul><li><code>CredentialsEncrypted</code> : </li></td><td>Definiert ob die Anmeldedaten in lesbarer Form (PlainText) oder als base64 verschl&uuml;sselt vorliegen.<BR>
																						  Der Default Wert ist 0 = Anmeldedaten liegen in PlainText vor.<BR>
						</ul></td></tr>
						</td>
					</tr>
			</ul></ul>

			<ul><ul>
					<tr>
						<td>
						<BR>
						<tr><td><ul><li><code>DbLogExclude</code> : </li></td><td>Generelles Attribut um Readings von Loggen auszuschließen. Das Attribut wird automatisch auf "/Status/pico_is_running" gesetzt welchen den kontinuierlichen Watchdog Z&auml;hler vom loggen ausnimmt.<BR>
																				  Es ergibt keinen Sinn dieses Reading zu loggen.<BR>
																				  Der Default Wert f&uuml;r die Ausnahme vom loggen liegt auf dem Reading "/Status/pico_is_running" <BR>
						</ul></td></tr>
						</td>
					</tr>
			</ul></ul>

			<ul><ul>
					<tr>
						<td>
						<BR>
						<tr><td><ul><li><code>event-on-change-reading</code> : </li></td><td>Generelles Attribut um Events nur bei &auml;nderungen von Readings zu erzeugen. Das Attribut wird automatisch auf ".*" gesetzt, was alle Readings nur bei &auml;nderungen loggt.<BR>
																							 Der Default Wert ist ".*" = Alle Readings.<BR>
						</ul></td></tr>
						</td>
					</tr>
			</ul></ul>

			<ul><ul>
					<tr>
						<td>
						<BR>
						<tr><td><ul><li><code>room</code> : </li></td><td>Generelles Attribut zum setzen des Raumes. Das Attribut wird automatisch auf "UpsPIco" gesetzt, damit das device nicht im "Everthing" Raum verschwindet.<BR>
																	  Der Default Wert ist "UpsPIco".<BR>
						</ul></td></tr>
						</td>
					</tr>
			</ul></ul>
		</td>
	</table>
</ul>
=end html_DE