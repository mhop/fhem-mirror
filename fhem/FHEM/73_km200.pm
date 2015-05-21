# $Id: 73_km200.pm 0051 2015-05-21 20:00:00Z Matthias_Deeke $
########################################################################################################################
#
#     73_km200.pm
#     Creates the possibility to access the Buderus central heating system via
#     Buderus KM200, KM100 or KM50 communication module. It uses HttpUtils_NonblockingGet
#     from Rudolf Koenig to avoid a full blockage of the fhem main system during the
#     polling procedure.
#
#     Author                     : Matthias Deeke 
#     Contributions              : Olaf Droegehorn, Andreas Hahn, Rudolf Koenig, Markus Bloch,
#     Contributions (continued)  : Stefan M., Furban, KaiKr, grossi33, Morkin, DLindner
#     e-mail                     : matthias.deeke(AT)deeke(PUNKT)eu
#     Fhem Forum                 : http://forum.fhem.de/index.php/topic,25540.0.html
#     Fhem Wiki                  : http://www.fhemwiki.de/wiki/Buderus_Web_Gateway
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
#     fhem.cfg: define <devicename> km200 <IPv4-address> <GatewayPassword> <PrivatePassword>
#
#     Example 1 - Bare Passwords:
#     define myKm200 km200 192.168.178.200 GatewayGeheim        PrivateGeheim
#
#     Example 2 - base64 encoded passwords: Both passwords may be pre-encode with base64
#     define myKm200 km200 192.168.178.200 R2F0ZXdheUdlaGVpbQ== UHJpdmF0ZUdlaGVpbQ==
#
########################################################################################################################
#                                               CHANGELOG
#
#     Version	Date		Programmer			Subroutine						Description of Change
#		0010	28.08.2014	Sailor				All								Initial Release for collaborative programming work
#		0011	13.10.2014	Furban				km200_Define					Correcting "if (int(@a) == 6))" into "if (int(@a) == 6)"
#		0011	13.10.2014	Furban				km200_Define					Changing "if ($url =~ m/^((\d\d\d[01]\d\d2[0-4]\d25[0-5])\.){3}(\d\d\d[01]\d\d2[0-4]\d25[0-5])$/)" into "if ($url =~ m/^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/)"
#		0012	20.10.2014	Sailor              km200_Encrypt       			Swapping over to Crypt::Rijndael
#		0012	20.10.2014	Sailor              km200_Decrypt       			Swapping over to Crypt::Rijndael
#		0013	21.10.2014	Sailor              All                 			Improving log3 functions for debugging
#		0014	22.10.2014	Sailor              All                 			New function for get status and implementing export to Readings
#		0015	23.10.2014	Sailor              km200_Define					Minimum interval changed to 20s since polling procedure lasts about 10s
#		0015	23.10.2014	Sailor              km200_Get						New subroutine to receive individual data adhoc
#		0016	25.10.2014	Sailor              km200_Set						First try
#		0017	26.10.2014	Nobody0472          ALL           					Add FailSafe & Error Handling + KM50 + Interval in Definition
#		0018    27.10.2014	Sailor				km200_GetData					Trying out whether 	"my $options = HTTP::Headers->new("Accept" => "application/json","User-Agent" => "TeleHeater/2.2.3", "agent" => "TeleHeater/2.2.3");" is the same as "$ua->agent('TeleHeater/2.2.3');"
#		0018    27.10.2014	Sailor				km200_Define					Lot's of commenting in order to improve readability	:-)
#		0018    27.10.2014	Sailor				km200_CompleteDataInit			Improvement of console output for easier debugging
#		0018    27.10.2014	Sailor				=pod							First Issue of description added
#		0019    27.10.2014	Sailor				km200_GetData					Try-out Failed and original code re enabled for: "Trying out whether "my $options = HTTP::Headers->new("Accept" => "application/json","User-Agent" => "TeleHeater/2.2.3", "agent" => "TeleHeater/2.2.3");" is the same as "$ua->agent('TeleHeater/2.2.3');""
#		0019    27.10.2014	Nobody0472			km200_Attr						First Issue
#		0019    27.10.2014	Sailor				km200_Attr						Adapted to double interval attributes "IntervalDynVal" and "IntervalStatVal"
#		0019    27.10.2014	Sailor				km200_Define					Adapted to double interval attributes "IntervalDynVal" and "IntervalStatVal" and deleted interval of being imported from the define line.
#		0019    27.10.2014	Sailor				km200_Define					Created list of known static services
#		0019    27.10.2014	Sailor				km200_Define					Calculated a list of responding services which are not static = responding dynamic services
#		0019    27.10.2014	Sailor				km200_CompleteDynData			Subroutine km200_CompleteData renamed to "km200_CompleteDynData" and only downloading responding dynamic services
#		0019    27.10.2014	Sailor				km200_CompleteStatData			Subroutine "km200_CompleteStatData" created only downloading responding static services
#		0020    28.10.2014	Sailor				km200_Define					Attribute check moved to km200_Attr
#		0020    28.10.2014	Sailor				km200_Attr						Attribute check included
#		0020    28.10.2014	Sailor				All								Clear-ups for comments and unused debug - print commands
#		0020    28.10.2014	Sailor				km200_Define					Decoding of passwords with base64 implemented to avoid bare passwords in fhem.cfg
#		0021    31.10.2014	Sailor				km200_Define					Added "/heatingCircuits/hc2" and subordinates 
#		0021    31.10.2014	Sailor				km200_CompleteDynData			First try-outs with fork() command - FAILED! All fork() commands deleted
#		0022	04.11.2014	Sailor	----------- Nearly all subroutines renamed! -----------------------------------------------------------------------------------------------------------------------
#		0022    04.11.2014	Sailor				All								Integration of  HttpUtils_NonblockingGet(). Nearly all Subroutines renamed due to new functionality
#		0023    05.11.2014	Sailor				All								Clearing up "print" and "log" command
#		0023    05.11.2014	Sailor				km200_ParseHttpResponseInit		encode_utf8() command added to avoid crashes with "/heatSources/flameCurrent" or "/system/appliance/flameCurrent"
#		0023    05.11.2014	Sailor				km200_ParseHttpResponseDyn		encode_utf8() command added to avoid crashes with "/heatSources/flameCurrent" or "/system/appliance/flameCurrent"
#		0023    05.11.2014	Sailor				km200_ParseHttpResponseStat		encode_utf8() command added to avoid crashes with "/heatSources/flameCurrent" or "/system/appliance/flameCurrent"
#		0023    05.11.2014	Sailor				km200_GetSingleService			New function used to obtain single value: HttpUtils_BlockingGet()
#		0023    05.11.2014	Sailor				km200_PostSingleService			New function used to write  single value: HttpUtils_BlockingGet() (Yes, even called "get" in the end, it allows to write (POST) as well
#		0024    06.11.2014	Sailor				km200_PostSingleService			Set value works! But only if no background download of dynamic or static values is active the same time
#		0025    06.11.2014	Sailor				km200_Get						Creating proper hash out of array of responding services
#		0025    07.11.2014	Sailor				km200_Set						Creating proper hash out of array of writeable services
#		0025    07.11.2014	Sailor				km200_Initialize				Adding DbLog_splitFn
#		0025    07.11.2014	Sailor				km200_DbLog_splitFn				First try-out. print function temporarily disabled
#		0025    07.11.2014	Sailor				All								Adding some print-commands for debugging
#		0025    07.11.2014	Sailor				km200_Set						Starting with blocking flags
#		0026    09.11.2014	Sailor				km200_GetDynService				Additional Log for debugging added
#		0026    09.11.2014	Sailor				km200_GetStatService			Additional Log for debugging added
#		0027    10.11.2014	Sailor				km200_Initialize				Corrected DbLog entry to $hash->{DbLog_splitFn}  = "km200_DbLog_splitFn";
#		0027    10.11.2014	Sailor				km200_Define					Password logging deleted. Too dangerous as soon a user posts its log seeking for help since gateway password cannot be changed
#		0027    10.11.2014	Sailor				km200_Define					Adding $hash->{DELAYDYNVAL} and $hash->{DELAYSTATVAL} to delay start of timer
#		0027    10.11.2014	Sailor				km200_Attr						Adding $hash->{DELAYDYNVAL} and $hash->{DELAYSTATVAL} to delay start of timer
#		0027    10.11.2014	Sailor				km200_PostSingleService			Error handling 
#		0027    10.11.2014	Sailor				km200_GetSingleService			Error handling 
#		0027    10.11.2014	Sailor				km200_Define					Added additional STATE information
#		0027    10.11.2014	Sailor				km200_GetDynService				Added additional STATE information
#		0027    10.11.2014	Sailor				km200_GetStatService			Added additional STATE information
#		0028    10.11.2014	Sailor				km200_Initialize				Implementing polling time-out attribute in $hash
#		0028    10.11.2014	Sailor				km200_Define					Implementing polling time-out attribute in $hash
#		0028    10.11.2014	Sailor				km200_Attr						Implementing polling time-out attribute in $hash
#		0028    10.11.2014	Sailor				km200_PostSingleService			Implementing polling time-out attribute in $hash
#		0028    10.11.2014	Sailor				km200_GetSingleService			Implementing polling time-out attribute in $hash
#		0028    10.11.2014	Sailor				km200_GetInitService			Implementing polling time-out attribute in $hash
#		0028    10.11.2014	Sailor				km200_GetDynService				Implementing polling time-out attribute in $hash
#		0028    10.11.2014	Sailor				km200_GetStatService			Implementing polling time-out attribute in $hash
#		0029    14.11.2014	Sailor				km200_GetInitService			Log Level for data not being available downgraded to Level 4		
#		0029    14.11.2014	Sailor				km200_GetSingleService			Log Level for data not being available downgraded to Level 4
#		0029    14.11.2014	Sailor				=pod							Description updated
#		0030    14.11.2014	Sailor				All							    Implement Console-Printouts only if attribute "ConsoleMessage" is set
#		0031    09.12.2014	Sailor				km200_GetDynService				Catching JSON parsing errors in order to prevent fhem crashes
#		0031    09.12.2014	Sailor				km200_GetStatService			Catching JSON parsing errors in order to prevent fhem crashes
#		0031    09.12.2014	Sailor				km200_GetInitService			Catching JSON parsing errors in order to prevent fhem crashes
#		0031    09.12.2014	Sailor				km200_GetSingleService			Catching JSON parsing errors in order to prevent fhem crashes
#		0032    09.12.2014	Sailor				All								Small format corrections
#		0033    12.12.2014	Sailor				km200_Define					Swapping service for test of communication from "/system/brand" to "/gateway/DateTime"
#		0034    12.12.2014	Sailor				km200_Initialize				Deactivating $hash->{DbLog_splitFn}
#		0035    07.01.2015	Sailor				Comments						Updating comments based on created WIKI
#		0035    07.01.2015	Sailor				km200_Attr						BugFix around ConsoleMessage Attribute
#		0035    07.01.2015	Sailor				All								Log Message of verbose level 2 improved
#		0035    07.01.2015	Sailor				=pod							Bug-fix to be joined in commandref
#		0036    13.01.2015	Sailor				Comments						Switched version system to fhem 4-digit version number scheme
#		0036    13.01.2015	Sailor				km200_Define					Switched version system to fhem 4-digit version number scheme
#		0036    13.01.2015	Sailor				km200_Define					Implementing DoNotPoll attribute
#		0036    13.01.2015	Sailor				km200_Attribute					Implementing DoNotPoll attribute
#		0036    13.01.2015	Sailor				km200_GetInitService			Implementing DoNotPoll attribute
#		0036    13.01.2015	Sailor				km200_ParseHttpResponseInit		Implementing DoNotPoll attribute
#		0036    13.01.2015	Sailor				km200_Initialize				Try-out DbLog Split (DbLog_Split is currently disabled)
#		0036    13.01.2015	Sailor				km200_Define					Preparing DbLog Split
#		0036    13.01.2015	Sailor				km200_DbLog_splitFn				Try-out DbLog Split
#		0036    13.01.2015	Sailor				km200_GetSingleService			Preparing DbLog Split
#		0036    13.01.2015	Sailor				km200_GetInitService			Preparing DbLog Split
#		0036    13.01.2015	Sailor				km200_GetDynService				Preparing DbLog Split
#		0036    13.01.2015	Sailor				km200_GetStatService			Preparing DbLog Split
#		0036    13.01.2015	Sailor				=pod							Correction of errors and German description added
#		0037    14.01.2015	Sailor				km200_DbLog_splitFn				Try-out DbLog Split (Failed... no name of device handed over in event)
#		0037    14.01.2015	Sailor				=pod							Correction of errors
#		0037    14.01.2015	Sailor				km200_Attr						Readings are being deleted if set not to be polled by attribute
#		0038    16.01.2015	Sailor				km200_Attr						Implementing hierarchy top-down in DoNotPoll 
#		0038    16.01.2015	Sailor				km200_ParseHttpResponseInit		Implementing hierarchy top-down in DoNotPoll 
#		0038    16.01.2015	Sailor				=pod							Implementing hierarchy top-down in DoNotPoll
#		0038    16.01.2015	Sailor				del_double						Adding a helper to delete double entries in arrays
#		0039    19.01.2015	Sailor				km200_Attr						Bugfix:   Handling of unknown attributes
#		0039    19.01.2015	Sailor				km200_Define					Added:    SC2 as copy of SC1
#		0039    19.01.2015	Sailor				km200_Define					Added:    More services since apparently forgotten due to update on IP-Symcon site
#		0039    19.01.2015	Sailor				km200_Get						Changed:  get-command is able to return raw data if valid json dataset is not existing to be returned
#		0039    19.01.2015	Sailor				km200_GetSingleService			Changed:  get-command is able to return raw data if valid json dataset is not existing to be returned
#		0040    20.01.2015	Sailor				km200_Define					Added /system/holidayModes
#		0041    21.02.2015	Sailor				km200_Define					Added /heatingCircuits/hc1/heatingCurveSetting
#		0041    21.02.2015	Sailor				km200_Define					Added /heatingCircuits/hc2/heatingCurveSetting
#		0041    21.02.2015	Sailor				km200_Define					Added /heatingCircuits/hc1/holidayMode
#		0041    21.02.2015	Sailor				km200_Define					Added /heatingCircuits/hc2/holidayMode
#		0041    21.02.2015	Sailor				km200_Define					Added /gateway/language
#		0041    21.02.2015	Sailor				km200_Define					Added /recordings/system/sensors/outdoorTemperatures
#		0041    24.02.2015	Sailor				km200_Define					Added /dhwCircuits/*
#		0042    03.03.2015	Sailor				km200_Define					Added more services
#		0042    03.03.2015	Sailor				km200_Set						Re-read of written value bug fixed.
#		0042    04.03.2015	Sailor				km200_Set						Correction of type change for numeric values
#		0043    09.03.2015	Sailor				km200_ParseHttpResponseInit		Read of "switchPrograms" implemented
#		0043    09.03.2015	Sailor				km200_ParseHttpResponseDyn		Read of "switchPrograms" implemented
#		0043    09.03.2015	Sailor				km200_ParseHttpResponseStat		Read of "switchPrograms" implemented
#		0043    14.03.2015	Sailor				All								My 41st birthday version.
#		0044    15.03.2015	Sailor				km200_Define					Added /system/appliance/type
#		0044    18.03.2015	Sailor				km200_Define					Added additional services below /dhwCircuits/dhw...
#		0044    15.03.2015	Sailor				km200_Set						First try-outs for switchProgram writings
#		0044    18.03.2015	Sailor				km200_ParseHttpResponseInit		fullResponde = ERROR - bug corrected
#		0044    18.03.2015	Sailor				km200_ParseHttpResponseDyn		fullResponde = ERROR - bug corrected
#		0044    18.03.2015	Sailor				km200_ParseHttpResponseStat		fullResponde = ERROR - bug corrected
#		0045    26.03.2015	Sailor				km200_ParseHttpResponseInit		Automatic Service Search
#		0045    26.03.2015	Sailor				km200_Attr						Changes for Automatic Service Search
#		0046    27.03.2015	Sailor				km200_ParseHttpResponseInit		"my $json -> {type}" - bug corrected
#		0046    27.03.2015	Sailor				km200_ParseHttpResponseDyn		"my $json -> {type}" - bug corrected
#		0046    07.04.2015	Sailor				km200_Get						Changes for SwitchProgram writings - WORKING IN PROGRESS
#		0046    07.04.2015	Sailor				km200_Set						Changes for SwitchProgram writings - WORKING IN PROGRESS
#		0046    07.04.2015	Sailor				km200_GetSingleService			Changes for SwitchProgram writings - WORKING IN PROGRESS
#		0046    07.04.2015	Sailor				km200_SetSingleService			Changes for SwitchProgram writings - WORKING IN PROGRESS
#		0046    07.04.2015	Sailor				km200_SetSingleService			Introduction of delay-attribute between push and re-reading
#		0046    07.04.2015	Sailor				km200_Attr						Introduction of delay-attribute between push and re-reading
#		0046    07.04.2015	Sailor				=pod							Introduction of delay-attribute between push and re-reading
#		0047    08.04.2015	Sailor				km200_Get						Implementation of optional return of Json-string
#		0047    08.04.2015	Sailor				km200_GetSingleService			Implementation of optional return of Json-string
#		0047    08.04.2015	Sailor				=pod							Implementation of optional return of Json-string
#		0047    09.04.2015	Sailor				km200_Get						Blocking get-command during initialisation phase
#		0047    09.04.2015	Sailor				km200_Set						Blocking set-command during initialisation phase
#		0047    09.04.2015	Sailor				km200_SetSingleService			Bugfix for error message
#		0048    09.04.2015	Sailor				km200_Attr						Improving DoNotPoll for root services
#		0048    10.04.2015	Sailor				km200_GetSingleService			Handback of complete error list
#		0048    14.04.2015	Sailor				km200_ParseHttpResponseInit		errorList missing service - bug corrected
#		0048    14.04.2015	Sailor				km200_Get						"0" - floatvalue - bug corrected by formating number
#		0049    14.04.2015	Sailor				km200_GetSingleService			Sorting error notifications descending by timestamps
#		0049    14.04.2015	Sailor				km200_ParseHttpResponseInit		Sorting error notifications descending by timestamps
#		0049    14.04.2015	Sailor				km200_ParseHttpResponseDyn		Sorting error notifications descending by timestamps
#		0049    13.05.2015	Sailor				km200_ParseHttpResponseInit		Correcting bug about wrong schedule times
#		0049    13.05.2015	Sailor				km200_ParseHttpResponseDyn		Correcting bug about wrong schedule times
#		0049    13.05.2015	Sailor				km200_GetSingleService			Correcting bug about wrong schedule times
#		0049    13.05.2015	Sailor				km200_PostSingleService			Correcting bug about wrong schedule times
#		0049    13.05.2015	Sailor				km200_PostSingleService			Implementing writing of SwitchPrograms
#		0049    13.05.2015	Sailor				km200_GetSingleService			Implementing re-writing of Readings for SwitchPrograms
#		0050    18.05.2015	Sailor				km200_PostSingleService         Correcting bug of floating point errors
#		0050    18.05.2015	Sailor				km200_ParseHttpResponseInit	    Correcting bug of floating point errors
#		0050    18.05.2015	Sailor				km200_ParseHttpResponseDyn      Correcting bug of floating point errors
#		0050    18.05.2015	Sailor				km200_PostSingleService         Implementing feature of posting complete "string of hash" to switchProgram
#		0051    20.05.2015	Sailor				km200_GetSingleService          Correcting bug of floating point errors
#		0051    21.05.2015	Sailor				km200_PostSingleService         Implementing switchPoint-hash by switchPoint-hash comparison
########################################################################################################################


########################################################################################################################
# List of open Problems:
#
# *DbLog: X_DbLog_splitFn not completely implemented in order to hand over the units of the readings to DbLog database
#         Unfortunately the global %hash of this module will not be transferred to the DbLog function. Therefore this 
#         function is useless.
#
########################################################################################################################

package main;

use strict;
use warnings;
use Blocking;
use Time::HiRes qw(gettimeofday sleep usleep);
use Digest::MD5 qw(md5 md5_hex md5_base64);
use base qw( Exporter );
use List::MoreUtils qw(first_index);
use MIME::Base64;
use LWP::UserAgent;
use JSON;
use Crypt::Rijndael;
use HttpUtils;
use Encode;
use constant false => 0;
use constant true  => 1;

sub km200_Define($$);
sub km200_Undefine($$);

###START###### Initialize module ##############################################################################START####
sub km200_Initialize($)
{
    my ($hash)  = @_;

    $hash->{STATE}           = "Init";
    $hash->{DefFn}           = "km200_Define";
    $hash->{UndefFn}         = "km200_Undefine";
    $hash->{SetFn}           = "km200_Set";
    $hash->{GetFn}           = "km200_Get";
    $hash->{AttrFn}          = "km200_Attr";
#	$hash->{DbLog_splitFn}   = "km200_DbLog_split";

    $hash->{AttrList}        = "do_not_notify:1,0 " .
						       "loglevel:0,1,2,3,4,5,6 " .
						       "IntervalDynVal " .
						       "IntervalStatVal " .
						       "PollingTimeout " .
							   "ConsoleMessage " .
							   "DoNotPoll " .
							   "ReadBackDelay " .
						       $readingFnAttributes;
}
####END####### Initialize module ###############################################################################END#####


###START######  Activate module after module has been used via fhem command "define" ##########################START####
sub km200_Define($$)
{
	my ($hash, $def)            = @_;
	my @a						= split("[ \t][ \t]*", $def);
	my $name					= $a[0];
								 #$a[1] just contains the "km200" module name and we already know that! :-)
	my $url						= $a[2];
	my $km200_gateway_password	= $a[3];
	my $km200_private_password	= $a[4];
	my $ModuleVersion           = "0051";

	$hash->{NAME}				= $name;
	$hash->{STATE}              = "define";

	Log3 $name, 5, $name. " : km200 - Starting to define module with version: " . $ModuleVersion;
		
	###START###### Define known services of gateway ###########################################################START####
	my @KM200_AllServices = (
	"/",
	"/dhwCircuits",
	"/gateway",
	"/heatingCircuits",
	"/heatSources",
	"/notifications",
	"/recordings",
	"/solarCircuits",
	"/system",
	);
	
	my @KM200_StatServices = (
	"/gateway/uuid",
	"/gateway/versionHardware",
	"/system/brand",
	"/system/bus",
	"/system/info",
	"/system/systemType"
	);
	####END####### Define known services of gateway ############################################################END#####

	
    ###START### Check whether all variables are available #####################################################START####
	if (int(@a) == 5) 
	{
		###START### Check whether IPv4 address is valid
		if ($url =~ m/^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/)
		{
			Log3 $name, 5, $name. " : km200 - IPv4-address is valid                 : " . $url;
		}
		else
		{
			return $name .": Error - IPv4 address is not valid \n Please use \"define <devicename> km200 <IPv4-address> <interval/[s]> <GatewayPassword> <PrivatePassword>\" instead";
		}
		####END#### Check whether IPv4 address is valid	

		
		###START### Check whether gateway password is base64 encoded or bare, has the right length and delete "-" if required
		my $PasswordEncrypted = false;
		my $EvalPassWord = $km200_gateway_password;
		$EvalPassWord =~ tr/-//d;

		if ( length($EvalPassWord) == 16)
		{
			$km200_gateway_password = $EvalPassWord;
			Log3 $name, 5, $name. " : km200 - Provided GatewayPassword provided as bareword has the correct length at least.";		
		}
		else # Check whether the password is eventually base64 encoded 
		{
		    # Remove additional encoding with base64
			my $decryptData = decode_base64($km200_gateway_password);
			$decryptData =~ tr/-//d;
			$decryptData =~ s/\r|\n//g;
			if ( length($decryptData) == 16)
			{
				$km200_gateway_password = $decryptData;
				$PasswordEncrypted = true;
				Log3 $name, 5, $name. " : km200 - Provided GatewayPassword encoded with base64 has the correct length at least.";
			}
			else
			{
				return $name .": Error - GatewayPassword does not have the correct length.\n". 
							  "          Please enter gateway password in the format of \"aaaabbbbccccdddd\" or \"aaaa-bbbb-cccc-dddd\"\n". 
							  "          You may encode your password with base64 first, in order to prevent bare passwords in fhem.cfg.\n".
							  "          If you choose to encrypt your gateway password with base64, you also must encrypt your private password the same way\n"; 

				Log3 $name, 3, $name. " : km200 - Provided Gateway Password does not follow the specifications";
			}
		}
		####END#### Check whether gateway password has the right length and delete "-" if required

		###START### Check whether private password is available and decode it with base64 if encoding is used
		if ($PasswordEncrypted == true)
		{
			my $decryptData = decode_base64($km200_private_password);
			$decryptData =~ s/\r|\n//g;
			if (length($decryptData) > 0)
			{
				$km200_private_password = $decryptData;
				Log3 $name, 5, $name. " : km200 - Provided PrivatePassword exists at least";
			}
			else
			{
				return $name .": Error - PrivatePassword does not have the minimum length.\n".
							  "          You may encode your password with base64 first, in order to prevent bare passwords in fhem.cfg.\n".
							  "          If you choose to encrypt your private password with base64, you also must encrypt your gateway password the same way\n"; 
			}
		}
		else # If private password is provided as bare word
		{
			if (length($km200_private_password) > 0)
			{
					Log3 $name, 5, $name. " : km200 - Provided PrivatePassword exists at least";		
			}
			else
			{
				return $name .": Error - PrivatePassword has not been provided.\n".
							  "          You may encode your password with base64 first, in order to prevent bare passwords in fhem.cfg.\n".
							  "          If you choose to encrypt your private password with base64, you also must encrypt your gateway password the same way\n"; 
				Log3 $name, 3, $name. " : km200 - Provided Private Password does not follow the specifications";
		  }
		}
		####END#### Check whether private password is available and decode it with base64 if encoding is used
	}
	else
	{
	    return $name .": km200 - Error - Not enough parameter provided." . "\n" . "Gateway IPv4 address, Gateway and Private Passwords must be provided" ."\n". "Please use \"define <devicename> km200 <IPv4-address> <GatewayPassword> <PrivatePassword>\" instead";
	}
	####END#### Check whether all variables are available ######################################################END#####

	
	###START###### Create the secret SALT of the MD5-Hash for AES-encoding ####################################START####
	my $Buderus_MD5Salt = pack(
	'C*',
	0x86, 0x78, 0x45, 0xe9, 0x7c, 0x4e, 0x29, 0xdc,
	0xe5, 0x22, 0xb9, 0xa7, 0xd3, 0xa3, 0xe0, 0x7b,
	0x15, 0x2b, 0xff, 0xad, 0xdd, 0xbe, 0xd7, 0xf5,
	0xff, 0xd8, 0x42, 0xe9, 0x89, 0x5a, 0xd1, 0xe4
	);
	####END####### Create the secret SALT of the MD5-Hash for AES-encoding #####################################END#####
	

	###START###### Create keys with MD5 #######################################################################START####
	# Copy Salt
	my $km200_crypt_md5_salt = $Buderus_MD5Salt;

	# First half of the key: MD5 of (km200GatePassword . Salt)
	my $key_1 = md5($km200_gateway_password . $km200_crypt_md5_salt);  
	  
	# Second half of the key: - Initial: MD5 of ( Salt)
	my $key_2_initial = md5($km200_crypt_md5_salt);

	# Second half of the key: -  private: MD5 of ( Salt . km200PrivatePassword)
	my $key_2_private = md5($km200_crypt_md5_salt . $km200_private_password);

	# Create keys
	my $km200_crypt_key_initial = ($key_1 . $key_2_initial);
	my $km200_crypt_key_private = ($key_1 . $key_2_private);
	####END####### Create keys with MD5 #########################################################################END#####
  
  
	###START###### Writing values to global hash ###############################################################START####
	  $hash->{NAME}                             = $name;
	  $hash->{URL}                              = $url;
      $hash->{VERSION}                          = $ModuleVersion;
	  $hash->{INTERVALDYNVAL}                   = 60;
	  $hash->{DELAYDYNVAL}                      = 60;
	  $hash->{INTERVALSTATVAL}                  = 3600;
	  $hash->{DELAYSTATVAL}                     = 120;
	  $hash->{DISABLESTATVALPOLLING}            = false;
	  $hash->{POLLINGTIMEOUT}                   = 5;
	  $hash->{CONSOLEMESSAGE}					= false;
	  $hash->{READBACKDELAY}					= 100;
	  $hash->{temp}{ServiceCounterInit}         = 0;
	  $hash->{temp}{ServiceCounterDyn}          = 0;
	  $hash->{temp}{ServiceCounterStat}         = 0;
	  $hash->{temp}{ServiceDbLogSplitHash}      = ();
	  $hash->{status}{FlagInitRequest}          = false;
	  $hash->{status}{FlagGetRequest}           = false;
	  $hash->{status}{FlagSetRequest}           = false;
	  $hash->{status}{FlagDynRequest}           = false;
	  $hash->{status}{FlagStatRequest}          = false;
	  $hash->{Secret}{CRYPTKEYPRIVATE}          = $km200_crypt_key_private;
	  $hash->{Secret}{CRYPTKEYINITIAL}          = $km200_crypt_key_initial;
	@{$hash->{Secret}{KM200ALLSERVICES}}        = sort @KM200_AllServices;
	@{$hash->{Secret}{KM200STATSERVICES}}       = @KM200_StatServices;
	@{$hash->{Secret}{KM200RESPONDINGSERVICES}} = ();
	@{$hash->{Secret}{KM200WRITEABLESERVICES}}  = ();
	@{$hash->{Secret}{KM200DONOTPOLL}}  		= ();
	####END####### Writing values to global hash ################################################################END#####

	###START###### Reset fullResponse error message ############################################################START####
	readingsSingleUpdate( $hash, "fullResponse", "OK", 1);
	####END####### Reset fullResponse error message #############################################################END#####	
	
	###START###### For Debugging purpose only ##################################################################START####  
	Log3 $name, 5, $name. " : km200 - Define H                              : " .$hash;
	Log3 $name, 5, $name. " : km200 - Define D                              : " .$def;
	Log3 $name, 5, $name. " : km200 - Define A                              : " .@a;
	Log3 $name, 5, $name. " : km200 - Define Name                           : " .$name;
	Log3 $name, 5, $name. " : km200 - Define Adr                            : " .$url;
	####END####### For Debugging purpose only ###################################################################END#####

	
	###START###### Check whether communication to the physical unit is possible ################################START####
	my $Km200Info ="";
	$hash->{temp}{service} = "/gateway/DateTime";
	$Km200Info = km200_GetSingleService($hash);
	
	if ($Km200Info eq "ERROR") 
	{
		$Km200Info = $hash->{temp}{TransferValue};
		$hash->{temp}{TransferValue} = "";
	}

	if ($Km200Info eq "ERROR") 
	{
		## Communication with Gateway WRONG !! ##
		$hash->{STATE}="Error - No Communication";
		return ($name .": km200 - ERROR - The communication between fhem and the Buderus KM200 failed! \n". 
		               "                  Please check physical connection, IP-address and passwords! \n");
	} 
	elsif ($Km200Info eq "SERVICE NOT AVAILABLE") ## Communication OK but service not available ##
	{
		Log3 $name, 5, $name. " : km200 -  /gateway/DateTime             : NOT AVAILABLE";
	} 
	else ## Communication OK and service is available ##
	{
		Log3 $name, 5, $name. " : km200 - /gateway/DateTime              : AVAILABLE";				
	}
	####END####### Check whether communication to the physical unit is possible ################################END#####

	###START###### Initiate the timer for first time polling of  values from KM200 but wait 5s ################START####
	InternalTimer(gettimeofday()+5, "km200_GetInitService", $hash, 0);
	Log3 $name, 5, $name. " : km200 - Internal timer for Initialisation of services started for the first time.";
	####END####### Initiate the timer for first time polling of  values from KM200 but wait 60s ################END#####
	
	return undef;
}
####END####### Activate module after module has been used via fhem command "define" ############################END#####


###START###### To bind unit of value to DbLog entries #########################################################START####
#sub km200_DbLog_split($)
#{
#	my ($event)  = @_;
#	my $name     = $event[0];
#	my $hash     = $defs{$name};
#	my ($reading, $value, $unit);
#	
#	
#print("DbLog_splitFn - event    : " . $event . "\n");
#print("DbLog_splitFn - event[0] : " . $event[0] . "\n");
#print("DbLog_splitFn - event[1] : " . $event[1] . "\n");
#print("DbLog_splitFn - event[2] : " . $event[2] . "\n");
#
#print("DbLog_splitFn - unit  : " . $hash->{temp}{ServiceDbLogSplitHash}{unit} ."\n");
#	
#	### Get values being changed from hash
#	$reading = $hash->{temp}{ServiceDbLogSplitHash}{id};
#	$value   = $hash->{temp}{ServiceDbLogSplitHash}{value};
#	$unit    = $hash->{temp}{ServiceDbLogSplitHash}{unit};
#	### Get values being changed from hash
#
#print("DbLog_splitFn - event:" . $event . "; value: ". $value . "; unit: ". $unit . ".\n");
#	
#	### Delete temporary json-hash for DbLog-Split
#	$hash->{temp}{ServiceDbLogSplitHash} = ();
#	### Delete temporary json-hash for DbLog-Split
#
#   return ($reading, $value, $unit);
#}
####END####### To bind unit of value to DbLog entries ##########################################################END#####


###START###### Deactivate module module after "undefine" command by fhem ######################################START####
sub km200_Undefine($$)
{
	my ($hash, $def)  = @_;
	my $name = $hash->{NAME};	
	my $url  = $hash->{URL};

  	### Stop the internal timer for this module
	RemoveInternalTimer($hash);

	Log3 $name, 3, $name. " - km200 has been undefined. The KM unit at $url will no longer polled.";

	### Console output if activated
	if ($hash->{CONSOLEMESSAGE} == true) {print("km200 has been undefined. The KM unit at $url will no longer polled.\n");}
	if ($hash->{CONSOLEMESSAGE} == true) {print("________________________________________________________________________________________________________\n\n");}
	
	return undef;
}
####END####### Deactivate module module after "undefine" command by fhem #######################################END#####


###START###### Handle attributes after changes via fhem GUI ###################################################START####
sub km200_Attr(@)
{
	my @a                      = @_;
	my $name                   = $a[1];
	my $hash                   = $defs{$name};
	my $DisableStatValPolling  = $hash->{DISABLESTATVALPOLLING};
	my $IntervalDynVal         = $hash->{INTERVALDYNVAL};
	my $IntervalStatVal        = $hash->{INTERVALSTATVAL};
	my $DelayDynVal            = $hash->{DELAYDYNVAL};
	my $DelayStatVal           = $hash->{DELAYSTATVAL};
	my $ReadBackDelay          = $hash->{READBACKDELAY};


	### Check whether dynamic interval attribute has been provided
	if ($a[2] eq "IntervalDynVal")
	{

		$IntervalDynVal = $a[3];
		###START### Check whether polling interval is not too short
		if ($IntervalDynVal > 19)
		{
			$hash->{INTERVALDYNVAL} = $IntervalDynVal;
			Log3 $name, 5, $name. " : km200 - IntervalDynVal set to attribute value:" . $IntervalDynVal ." s";
		}
		else
		{
			return $name .": Error - Gateway interval for IntervalDynVal too small - server response time longer than defined interval, please use something >=20, default is 90";
		}
		####END#### Check whether polling interval is not too short
	}
	### Check whether static interval attribute has been provided
	elsif($a[2] eq "IntervalStatVal") 
	{
		$IntervalStatVal = $a[3];

		if ($IntervalStatVal == 0) ### Check whether statical values supposed to be polled at all. The attribute "IntervalStatVal" set to "0" means no polling for statical values.
		{
			$DisableStatValPolling = true;
			$hash->{DISABLESTATVALPOLLING} = $DisableStatValPolling;
			Log3 $name, 5, $name. " : km200 - Polling for static values diabled";
		}
		else
		{
			###START### Check whether polling interval is not too short	
			if ($IntervalStatVal > 19)
			{
				$DisableStatValPolling = false;
				$hash->{INTERVALSTATVAL} = $IntervalStatVal;
				Log3 $name, 5, $name. " : km200 - IntervalStatVal set to attribute value:" . $IntervalStatVal ." s";
			}
			else
			{
				return $name .": Error - Gateway interval for IntervalStatVal too small - server response time longer than defined interval, please use something >=20, default is 3600";
			}
			####END#### Check whether polling interval is not too short	
		}
	}
	### Check whether polling timeout attribute has been provided
	elsif($a[2] eq "PollingTimeout") 
	{
		###START### Check whether timeout is not too short
		if ($a[3] >= 5)
		{
			$hash->{POLLINGTIMEOUT} = $a[3];
			Log3 $name, 5, $name. " : km200 - Polling timeout set to attribute value:" . $a[3] ." s";
		}
		else
		{
			Log3 $name, 5, $name. " : km200 - Error - Gateway polling timeout attribute too small: " . $a[3] ." s";
			return $name .": Error - Gateway polling timeout attribute is too small - server response time is 5s minimum, default is 5";
		}
		####END#### Check whether timeout is not too short
	}
	### Check whether console printout attribute has been provided
	elsif($a[2] eq "ConsoleMessage") 
	{
		### If messages on console shall be visible
		if ($a[3] == 1)
		{
			$hash->{CONSOLEMESSAGE}	= true;
			Log3 $name, 5, $name. " : km200 - Console printouts enabled";
			print("\n");
		}
		### If messages on console shall NOT be visible
		else
		{
			$hash->{CONSOLEMESSAGE}	= false;
			Log3 $name, 5, $name. " : km200 - Console printouts disabled";
		}
	}
	### Check whether DoNotPoll attribute have been provided
	elsif($a[2] eq "DoNotPoll") 
	{
		my @KM200_DONOTPOLL   = ();
		my @temp              = @a;

		### Delete the first 3 items of the array
		splice @temp, 0, 3;

		### Insert empty field as minimum entry 
		push @temp, "";
		
		### Transform string entries seperated by blank into array
		@KM200_DONOTPOLL = split(/ /, $temp[0]);

		### Remove trailing slash of each item if available
		
		### For each item found in this empty parent directory
		foreach my $item (@KM200_DONOTPOLL)
		{
			### Delete trailing slash
			$item =~ s/\/$//;
		}
		
		### Save list of services not to be polled into hash
		@{$hash->{Secret}{KM200DONOTPOLL}} = @KM200_DONOTPOLL;

		
		### For every blacklisted service
		foreach my $SearchWord(@KM200_DONOTPOLL)
		{
			### Filter all blocked root services out of services to be polled 
			my $FoundPosition = first_index{ $_ eq $SearchWord }@{$hash->{Secret}{KM200ALLSERVICES}};
			if ($FoundPosition >= 0)
			{
				splice(@{$hash->{Secret}{KM200ALLSERVICES}}, $FoundPosition, 1);
			}
		}

		### Message for debugging purposes
		Log3 $name, 5, $name. " : km200 - The following services will not be polled: ". $a[3];
	}
	### Check whether time-out for Read-Back has been provided
	if($a[2] eq "ReadBackDelay") 
	{
		$ReadBackDelay = $a[3];
		###START### Check whether ReadBackDelay is valid
		if ($ReadBackDelay >= 0)
		{
			$hash->{READBACKDELAY} = $ReadBackDelay;
			Log3 $name, 5, $name. " : km200 - ReadBackDelay set to attribute value:" . $ReadBackDelay ." s";
		}
		else
		{
			return $name .": Error - Read-Back delay time must be positive. Default is 0us";
		}
		####END#### Check whether ReadBackDelay is valid
	}
	### If no attributes of the above known ones have been selected
	else
	{
		# Do nothing
	}
	return undef;
}
####END####### Handle attributes after changes via fhem GUI ####################################################END#####


###START###### Obtain value after "get" command by fhem #######################################################START####
sub km200_Get($@)
{
	my ( $hash, @a ) = @_;
	
	### If not enough arguments have been provided
	if ( @a < 2 )
	{
		return "\"get km200\" needs at least one argument";
	}
		
	my $name     = shift @a;
	my $service  = shift @a;
	my $option   = shift @a;
	my %km200_gets;
	my $ReturnValue;
	my $ReturnMessage;
	
	### Get the list of possible services and create a hash out of it
	my @GetServices = @{$hash->{Secret}{KM200ALLSERVICES}};

	foreach my $item(@GetServices) 	
	{
		$km200_gets{$item} = ("1");
	}
	
	### Remove trailing slash if available
	$service = $1 if($service=~/(.*)\/$/);
	
	### If service chosen in GUI does not exist
	if(!$km200_gets{$service}) 
	{
		my @cList = keys %km200_gets;
		return "Unknown argument $service, choose one of " . join(" ", @cList);
	}
	
	### Check whether the initialisation process has been finished
	if ($hash->{temp}{ServiceCounterInit} == false)
	{
		### Save chosen service into hash
		$hash->{temp}{service} = $service;

		### Read service-hash
		$ReturnValue = km200_GetSingleService($hash);

		### If the "get" - option has been set to "Json" for the return of the raw Json-string
		if ($option =~ m/json/i)
		{
			$ReturnMessage = $hash->{temp}{JsonRaw};
		}
		### If no option has been chosen, just return the result of the value.
		else
		{
			### If type is a floatvalue then format decimals
			if ($ReturnValue->{type} eq "floatValue")
			{
				$ReturnMessage = sprintf("%.1f", $ReturnValue->{value});
			}
			### If type is something else just pass throught
			else
			{
				$ReturnMessage = $ReturnValue->{value};
			}
		}
	}
	### If the initialisation process has NOT been finished
	else
	{
		$ReturnMessage = "The initialisation process is still ongoing. Please wait for the STATE changing to \"Standby\"";
	}
		
	
	### Delete temporary values
	$hash->{temp}{service} = "";
	$hash->{temp}{JsonRaw} = "";
	
	### Console outputs for debugging purposes
	if ($hash->{CONSOLEMESSAGE} == true) {print("________________________________________________________________________________________________________\n\n");}

	### Return value
	return($ReturnMessage);
}
####END####### Obtain value after "get" command by fhem ########################################################END#####


###START###### Manipulate service after "set" command by fhem #################################################START####
sub km200_Set($@)
{
	my ( $hash, @a ) = @_;
	
	### If not enough arguments have been provided
	if ( @a < 2 )
	{
		return "\"set km200\" needs at least one argument";
	}
		
	my $name = shift @a;
	my $service  = shift @a;
	my $value = join(" ", @a);
	my %km200_sets;
	my $ReturnMessage;

	### Get the list of possible services and create a hash out of it
	my @WriteableServices = @{$hash->{Secret}{KM200WRITEABLESERVICES}};

	foreach my $item(@WriteableServices) 	
	{
		$km200_sets{$item} = ("1");
	}
	
	### If service chosen in GUI does not exist
	if(!$km200_sets{$service}) 
	{
		my @cList = keys %km200_sets;
		return "Unknown argument $service, choose one of " . join(" ", @cList);
	}

	### Check whether the initialisation process has been finished
	if ($hash->{temp}{ServiceCounterInit} == false)
	{
		### Save chosen service into hash
		$hash->{temp}{service}  = $service;
		$hash->{temp}{postdata} = $value;	
		
		### Call set sub
		$ReturnMessage = km200_PostSingleService($hash);
	}
	### If the initialisation process has NOT been finished
	else
	{
		$ReturnMessage = "The initialisation process is still ongoing. Please wait for the STATE changing to \"Standby\"";
	}
	
	### Delete temporary hash values
	$hash->{temp}{postdata} = "";
	$hash->{temp}{service}  = "";
	
	### Console outputs for debugging purposes
	if ($hash->{CONSOLEMESSAGE} == true) {print("________________________________________________________________________________________________________\n\n");}

	return($ReturnMessage);
}
####END####### Manipulate service after "Set" command by fhem ##################################################END#####


###START####### Repeats "string" for "count" times ############################################################START####
sub str_repeat($$)
{
    my $string = $_[0];
    my $count  = $_[1];
    return(${string}x${count});
}
####END######## Repeats "string" for "count" times #############################################################END#####


###START###### Subroutine Encrypt Data ########################################################################START####
sub km200_Encrypt($)
{
	my ($hash, $def)            = @_;

	my $km200_crypt_key_private = $hash->{Secret}{CRYPTKEYPRIVATE};
	my $name                    = $hash->{NAME};
	my $encryptData             = $hash->{temp}{jsoncontent};

    # Create Rijndael encryption object
    my $cipher = Crypt::Rijndael->new($km200_crypt_key_private, Crypt::Rijndael::MODE_ECB() );

    # Get blocksize and add PKCS #7 padding
    my $blocksize =  $cipher->blocksize();
    my $encrypt_padchar = $blocksize - ( length( $encryptData ) % $blocksize );
    $encryptData .= str_repeat( chr( $encrypt_padchar ), $encrypt_padchar );

	# Do the encryption
    my $ciphertext = $cipher->encrypt( $encryptData );

	# Do additional encoding with base64
    $ciphertext = encode_base64($ciphertext);
   
    # Return the encoded text
    return($ciphertext);
}
####END####### Subroutine Encrypt Data #########################################################################END#####


###START###### Subroutine Decrypt Data ########################################################################START####
sub km200_Decrypt($)
{
	my ($hash, $def)            = @_;

	my $km200_crypt_key_private = $hash->{Secret}{CRYPTKEYPRIVATE};
	my $name                    = $hash->{NAME};
	my $decryptData             = $hash->{temp}{decodedcontent};

    # Remove additional encoding with base64
    $decryptData = decode_base64($decryptData);

    # Create Rijndael decryption object and do the decryption
    my $cipher = Crypt::Rijndael->new($km200_crypt_key_private, Crypt::Rijndael::MODE_ECB() );
    my $deciphertext = $cipher->decrypt( $decryptData );

    # Remove zero padding
    $deciphertext =~ s/\x00+$//;

    # Remove PKCS #7 padding   
    my $decipher_len = length($deciphertext);
    my $decipher_padchar = ord(substr($deciphertext,($decipher_len - 1),1));
   
    my $i = 0;
    
    for ( $i = 0; $i < $decipher_padchar ; $i++ )
    {
        if ( $decipher_padchar != ord( substr($deciphertext,($decipher_len - $i - 1),1)))
        {
            last;
        }
    }
    
    # Return decrypted text
    if ( $i != $decipher_padchar )
    {
		### Log entries for debugging purposes
		Log3 $name, 5, $name. " : km200 - decryptData1 - decipher_len           : " .$decipher_len;
		$deciphertext =~ s/\x00+$//;
		Log3 $name, 5, $name. " : km200 - decryptData1 - deciphertext           : " .$deciphertext;
		### Log entries for debugging purposes
        return $deciphertext;
    }
    
	else
    {
		$deciphertext = substr($deciphertext,0,$decipher_len - $decipher_padchar);
		### Log entries for debugging purposes
		Log3 $name, 5, $name. " : km200 - decryptData2 - decipher_len           : " .$decipher_len;
		$deciphertext =~ s/\x00+$//;
		Log3 $name, 5, $name. " : km200 - decryptData2 - deciphertext           : " .$deciphertext;
		### Log entries for debugging purposes
        return $deciphertext;
    }
}
####END####### Subroutine Decrypt Data #########################################################################END#####


###START###### Subroutine set individual data value ###########################################################START####
sub km200_PostSingleService($)
{
	my ($hash, $def)                = @_;
	my $Service                     = $hash->{temp}{service};
	my $km200_gateway_host          = $hash->{URL} ;
	my $name                        = $hash->{NAME} ;
	my $PollingTimeout              = $hash->{POLLINGTIMEOUT};
	my $err;
	my $data;
	my $jsonSend;
	my $jsonRead;
	my $JsonContent;
	
	### Console outputs for debugging purposes
	if ($hash->{CONSOLEMESSAGE} == true) {print("km200_Set - Writing value: " . $hash->{temp}{postdata} . " to the service                     : ". $Service . "\n");}
	
	### Read the current json string 
	$jsonRead = km200_GetSingleService($hash);	
	
	#### If the get-command returns an error due to an unknown Service requested
	if ($jsonRead -> {type} eq "ERROR")
	{
		### Rescue original Service request
		my $WriteService = $Service;

		### Try to replace the Post-String with nothing
		$Service  =~ s/\/1-Mo//i;
		$Service  =~ s/\/2-Tu//i;
		$Service  =~ s/\/3-We//i;
		$Service  =~ s/\/4-Th//i;
		$Service  =~ s/\/5-Fr//i;
		$Service  =~ s/\/6-Sa//i;
		$Service  =~ s/\/7-Su//i;

		### Save corrected string in hash
		$hash->{temp}{service} = $Service;

		### Try again to read the current json string again with the corrected service
		$jsonRead = km200_GetSingleService($hash);	

		### Check whether the type is an switchProgram. 
		### If true, the requested service was a particular week of the switchProgram
		if ($jsonRead -> {type} eq "switchProgram")
		{
			### For each weekday, get current readings, delete all unnecessary blanks and transform to array
			my $TempReadingVal;
			
			   $TempReadingVal		= ReadingsVal($name,($Service . "/1-Mo"),"");
			   $TempReadingVal		=~ s/\s+/ /g;
			   $TempReadingVal		=~ s/\s+$//g;
			my @TempReadingMo 	    = split(/ /, $TempReadingVal,0);
			   
			   $TempReadingVal		= ReadingsVal($name,($Service . "/2-Tu"),"");
			   $TempReadingVal		=~ s/\s+/ /g;
			   $TempReadingVal		=~ s/\s+$//g;
			my @TempReadingTu 		= split(/ /, $TempReadingVal,0);
			   
			   $TempReadingVal		= ReadingsVal($name,($Service . "/3-We"),"");
			   $TempReadingVal		=~ s/\s+/ /g;
			   $TempReadingVal		=~ s/\s+$//g;
			my @TempReadingWe 		= split(/ /, $TempReadingVal,0);

			   $TempReadingVal		= ReadingsVal($name,($Service . "/4-Th"),"");
			   $TempReadingVal		=~ s/\s+/ /g;
			   $TempReadingVal		=~ s/\s+$//g;
			my @TempReadingTh 		= split(/ /, $TempReadingVal,0);
			
			   $TempReadingVal		= ReadingsVal($name,($Service . "/5-Fr"),"");
			   $TempReadingVal		=~ s/\s+/ /g;
			   $TempReadingVal		=~ s/\s+$//g;
			my @TempReadingFr 		= split(/ /, $TempReadingVal,0);
			
			   $TempReadingVal		= ReadingsVal($name,($Service . "/6-Sa"),"");
			   $TempReadingVal		=~ s/\s+/ /g;
			   $TempReadingVal		=~ s/\s+$//g;
			my @TempReadingSa 		= split(/ /, $TempReadingVal,0);
			
			   $TempReadingVal		= ReadingsVal($name,($Service . "/7-Su"),"");
			   $TempReadingVal		=~ s/\s+/ /g;
			   $TempReadingVal		=~ s/\s+$//g;
			my @TempReadingSu 		= split(/ /, $TempReadingVal,0);

			
			### For value to be written, delete all unnecessary blanks and transform to array and get length of array
			my $ReturnString		= $hash->{temp}{postdata};
			   $ReturnString 		=~ s/\s+/ /g;
			   $ReturnString 		=~ s/\s+$//g;
			my @TempReading			= split(/ /, $ReturnString);
			my $TempReadingLength	= @TempReading;

			
			### Obtain the allowed terminology for setpoints
			$hash->{temp}{service}	= $jsonRead -> {setpointProperty}{id};
			my $TempSetpointsJson	= km200_GetSingleService($hash);

			
			my @TempSetpointNames	=();
			### For each item found in this empty parent directory
			foreach my $item (@{ $TempSetpointsJson->{references} })
			{
				my $TempSetPoint = substr($item->{id}, (rindex($item->{id}, "/") - length($item->{id}) +1));
				
				### Add service to the list of all known services
				push (@TempSetpointNames, $TempSetPoint);
			}
			
			### Restore the original service
			$hash->{temp}{service}	= $Service;
			
			### If number of switchpoints exceeds maximum allowed
			if (($TempReadingLength / 2) > $jsonRead -> {maxNbOfSwitchPointsPerDay})
			{
				return ("ERROR - Too much Switchpoints for weeklist inserted. \n Do not add more than " . $jsonRead -> {maxNbOfSwitchPointsPerDay} . " SwitchPoints per day!\n");	
			}
			
			### If content of array is not even
			if (($TempReadingLength % 2)  != 0)
			{
				return "ERROR - At least one Switchtime or Switchpoint is missing. \n Make sure you always have couples of Switchtime and Switchpoint!\n";	
			}
			
			### Check whether description of setpoints is the same as referenced and the data is in the right order
			for (my $i=0;$i<$TempReadingLength;$i+=2)
			{ 
				### If the even element behind the uneven index [1, 3, 5, ...] is not one of the pre-defined setpoints
				if (! grep /($TempReading[$i+1])/,@TempSetpointNames)
				{
					return "ERROR - At least for one Switchpoint the wrong terminology has been used. Only use one of the following items: " . join(' , ',@TempSetpointNames) ."\n";;
				}

				### If the uneven element behind the even index [0, 2, 4, ...]is not a number, hand back an error message
				if ($TempReading[$i] !~ /^[0-9.-]+$/)
				{
					return "ERROR - At least for one Switchtime a number is expected at that position. \n Ensure the correct syntax of time and switchpoint. (E.g. 0600 eco)\n";
				}
			
				### Convert timepoint into raster of defined switchPointTimeRaster
				my $TempHours    = substr($TempReading[$i], 0, length($TempReading[$i])-2);
				if ($TempHours > 23)
				{
					$TempHours = 23;
				}
				my $TempMinutes	 = substr($TempReading[$i], -2);
				if ($TempMinutes > 59)
				{
					$TempMinutes = 59;
				}
				$TempMinutes 	 = $TempMinutes / ($jsonRead -> {switchPointTimeRaster});
				$TempMinutes 	 =~ s/^(.*?)\..*$/$1/;
				$TempMinutes 	 = $TempMinutes * ($jsonRead -> {switchPointTimeRaster});
				$TempMinutes 	 = sprintf ('%02d', $TempMinutes);
				$TempReading[$i] = ($TempHours . $TempMinutes);

			}
			
			$hash->{temp}{postdata} = join(" ", @TempReading);
			
			### For the requested day to be changed, save new value
			if    ($WriteService =~ m/1-Mo/i)
			{
				@TempReadingMo   = @TempReading;
			}
			elsif ($WriteService =~ m/2-Tu/i)
			{
				@TempReadingTu   = @TempReading;
			}
			elsif ($WriteService =~ m/3-We/i)
			{
				@TempReadingWe   = @TempReading;
			}	
			elsif ($WriteService =~ m/4-Th/i)
			{
				@TempReadingTh   = @TempReading;
			}	
			elsif ($WriteService =~ m/5-Fr/i)
			{
				@TempReadingFr   = @TempReading;
			}	
			elsif ($WriteService =~ m/6-Sa/i)
			{
				@TempReadingSa   = @TempReading;
			}	
			elsif ($WriteService =~ m/7-Su/i)
			{
				@TempReadingSu   = @TempReading;
			}	

			
			### For every weekday create setpoint hash and push it to array of hashes of switchpoints to be send
			my @SwitchPointsSend =();
			
			for (my $i=0;$i<$#TempReadingMo;$i+=2)
			{
				my $TempHashSend;
				$TempHashSend->{"dayOfWeek"} = "Mo";
				my $TempHours                = substr($TempReadingMo[$i], 0, length($TempReadingMo[$i])-2);
				my $TempMinutes	             = substr($TempReadingMo[$i], -2);
				$TempHashSend->{"time"}      = ($TempHours * 60 ) + $TempMinutes;
				$TempHashSend->{"setpoint"}  = $TempReadingMo[$i+1];
				push @SwitchPointsSend, $TempHashSend;
			}

			for (my $i=0;$i<$#TempReadingTu;$i+=2)
			{
				my $TempHashSend;
				$TempHashSend->{"dayOfWeek"} = "Tu";
				my $TempHours                = substr($TempReadingTu[$i], 0, length($TempReadingTu[$i])-2);
				my $TempMinutes	             = substr($TempReadingTu[$i], -2);
				$TempHashSend->{"time"}      = ($TempHours * 60 ) + $TempMinutes;				
				$TempHashSend->{"setpoint"}  = $TempReadingTu[$i+1];
				push @SwitchPointsSend, $TempHashSend;
			}			
			
			for (my $i=0;$i<$#TempReadingWe;$i+=2)
			{
				my $TempHashSend;
				$TempHashSend->{"dayOfWeek"} = "We";
				my $TempHours                = substr($TempReadingWe[$i], 0, length($TempReadingWe[$i])-2);
				my $TempMinutes	             = substr($TempReadingWe[$i], -2);
				$TempHashSend->{"time"}      = ($TempHours * 60 ) + $TempMinutes;
				$TempHashSend->{"setpoint"}  = $TempReadingWe[$i+1];
				push @SwitchPointsSend, $TempHashSend;
			}
	
			for (my $i=0;$i<$#TempReadingTh;$i+=2)
			{
				my $TempHashSend;
				$TempHashSend->{"dayOfWeek"} = "Th";
				my $TempHours                = substr($TempReadingTh[$i], 0, length($TempReadingTh[$i])-2);
				my $TempMinutes	             = substr($TempReadingTh[$i], -2);
				$TempHashSend->{"time"}      = ($TempHours * 60 ) + $TempMinutes;
				$TempHashSend->{"setpoint"}  = $TempReadingTh[$i+1];
				push @SwitchPointsSend, $TempHashSend;
			}
			
			for (my $i=0;$i<$#TempReadingFr;$i+=2)
			{
				my $TempHashSend;
				$TempHashSend->{"dayOfWeek"} = "Fr";
				my $TempHours                = substr($TempReadingFr[$i], 0, length($TempReadingFr[$i])-2);
				my $TempMinutes	             = substr($TempReadingFr[$i], -2);
				$TempHashSend->{"time"}      = ($TempHours * 60 ) + $TempMinutes;
				$TempHashSend->{"setpoint"}  = $TempReadingFr[$i+1];
				push @SwitchPointsSend, $TempHashSend;
			}
			
			for (my $i=0;$i<$#TempReadingSa;$i+=2)
			{
				my $TempHashSend;
				$TempHashSend->{"dayOfWeek"} = "Sa";
				my $TempHours                = substr($TempReadingSa[$i], 0, length($TempReadingSa[$i])-2);
				my $TempMinutes	             = substr($TempReadingSa[$i], -2);
				$TempHashSend->{"time"}      = ($TempHours * 60 ) + $TempMinutes;
				$TempHashSend->{"setpoint"}  = $TempReadingSa[$i+1];
				push @SwitchPointsSend, $TempHashSend;
			}
			
			for (my $i=0;$i<$#TempReadingSu;$i+=2)
			{
				my $TempHashSend;
				$TempHashSend->{"dayOfWeek"} = "Su";
				my $TempHours                = substr($TempReadingSu[$i], 0, length($TempReadingSu[$i])-2);
				my $TempMinutes	 = substr($TempReadingSu[$i], -2);
				$TempHashSend->{"time"}      = ($TempHours * 60 ) + $TempMinutes;
				$TempHashSend->{"setpoint"}  = $TempReadingSu[$i+1];
				push @SwitchPointsSend, $TempHashSend;
			}

			### Save array of hashes of switchpoints into json hash to be send
			@{$jsonSend->{switchPoints}} = @SwitchPointsSend;
			
			### Create full URL of the current Service to be written
			my $url ="http://" . $km200_gateway_host . $Service;

			### Encode as json
			$JsonContent = encode_json($jsonSend);

			### Delete the name of hash, "{" and "}" out of json String. No idea why but result of Try-and-Error method
			$JsonContent =~ s/{"switchPoints"://;
			$JsonContent =~ s/]}/]/g;

			### Delete the string marker out of json String and change time-string to integer.
			$JsonContent =~ s/,"time":"/,"time":/g;
			$JsonContent =~ s/"},{/},{/g;			

			### Encrypt 
			$hash->{temp}{jsoncontent} = $JsonContent;
			$data = km200_Encrypt($hash);
			
			### Create parameter set for HttpUtils_BlockingGet
			my $param = {
							url        => $url,
							timeout    => $PollingTimeout * 5,
							data       => $data,
							method     => "POST",
							header     => "agent: TeleHeater/2.2.3\r\nUser-Agent: TeleHeater/2.2.3\r\nAccept: application/json",
						};
						
			### Block other scheduled and unscheduled routines
			$hash->{status}{FlagSetRequest} = true;

			### Write value with HttpUtils_BlockingGet
			($err, $data) = HttpUtils_BlockingGet($param);

			### Reset flag
			$hash->{status}{FlagSetRequest} = false;
			
			### If error message has been returned
			if($err ne "") 
			{
				Log3 $name, 2, $name . " - ERROR: $err";
				if ($hash->{CONSOLEMESSAGE} == true) {print("km200_PostSingleService - Error: $err\n");}
				return $err;	
			}

			if ($hash->{CONSOLEMESSAGE} == true) {print("Waiting for processing time (READBACKDELAY / [ms])     : " . $hash->{READBACKDELAY} . " \n");}
			### Make a pause before ReadBack
			usleep ($hash->{READBACKDELAY}*1000);

		### Read service-hash and format it so it is compareable to the sent content
		my $ReReadContent = km200_GetSingleService($hash);
		   $ReReadContent = $ReReadContent->{switchPoints};
		   $ReReadContent = encode_json($ReReadContent);
		   $ReReadContent =~ s/{"switchPoints"://;
		   $ReReadContent =~ s/]}/]/g;
		   
		### Transform back into array of hashes
		eval 
			{
				$ReReadContent = decode_json(encode_utf8($ReReadContent));
				$JsonContent = decode_json(encode_utf8($JsonContent));
				1;
			}
		or do 
			{
			};
		
		### Set Counter for found items in SwitchPrograms
		my $FoundJsonItem = 0;
		
				
		### For every item of the array of SwitchPrograms to be send
		foreach my $ReReadItem (@{$ReReadContent})
		{
			### Set Counter for found items of ReRead values
			my $FoundReReadItem = 0;
			
			### For every item of the array of SwitchPrograms after Re-Reading 
			foreach my $JsonItem (@{$JsonContent})
			{

				### If the current Switchprogram - hash does not have the same amount of keys
				if (%$ReReadItem != %$JsonItem) 
				{
					### Do nothing
					#print "they don't have the same number of keys\n";
				} 
				### If the current Switchprogram - hash do have the same amount of keys
				else 
				{
					### Compare key names and values
					my %cmp = map { $_ => 1 } keys %$ReReadItem;
					for my $key (keys %$JsonItem) 
					{
						last unless exists $cmp{$key};
						last unless $$ReReadItem{$key} eq $$JsonItem{$key};
						delete $cmp{$key};
					}
					if (%cmp) 
					{
						### Do nothing
						#print "they don't have the same keys or values\n";
					} 
					else 
					{
						### Inkrement Counter
						$FoundReReadItem = 1;
						#print "they have the same keys and values\n";
					}
				}
			}

			### If item has been found
			if ($FoundReReadItem == 1)
			{ 
				### Inkrement Counter for found identical SwitchPoints
				$FoundJsonItem++;
			}
		}
		
		my $ReturnValue;
		
		if 	($FoundJsonItem == @{$ReReadContent})
		{
			$ReturnValue = "The service " . $Service . " has been changed succesfully!";
			if ($hash->{CONSOLEMESSAGE} == true) {print("Writing $Service succesfully \n");}
		}	
		else
		{
			$ReturnValue = "ERROR - The service " . $Service . " could not changed! \n";
			if ($hash->{CONSOLEMESSAGE} == true) {print("Writing $Service was NOT succesfully \n");}
		}

			### Return the status message
			return $ReturnValue;
		}
	}	
	### Check whether the type is an switchProgram. 
	### If true, the requested service is referring to the entire week but not a particular week.
	if ($jsonRead -> {type} eq "switchProgram")
	{
		### Create full URL of the current Service to be written
		my $url ="http://" . $km200_gateway_host . $Service;

		### Get the string to be send
		$JsonContent = $hash->{temp}{postdata};			

		### Encrypt 
		$hash->{temp}{jsoncontent} = $JsonContent;
		$data = km200_Encrypt($hash);
		
		### Create parameter set for HttpUtils_BlockingGet
		my $param = {
						url        => $url,
						timeout    => $PollingTimeout * 5,
						data       => $data,
						method     => "POST",
						header     => "agent: TeleHeater/2.2.3\r\nUser-Agent: TeleHeater/2.2.3\r\nAccept: application/json",
					};
					
		### Block other scheduled and unscheduled routines
		$hash->{status}{FlagSetRequest} = true;

		### Write value with HttpUtils_BlockingGet
		($err, $data) = HttpUtils_BlockingGet($param);

		### Reset flag
		$hash->{status}{FlagSetRequest} = false;
		
		### If error message has been returned
		if($err ne "") 
		{
			Log3 $name, 2, $name . " - ERROR: $err";
			if ($hash->{CONSOLEMESSAGE} == true) {print("km200_PostSingleService - Error: $err\n");}
			return $err;	
		}

		if ($hash->{CONSOLEMESSAGE} == true) {print("Waiting for processing time (READBACKDELAY / [ms])     : " . $hash->{READBACKDELAY} . " \n");}
		### Make a pause before ReadBack
		usleep ($hash->{READBACKDELAY}*1000);

		### Read service-hash and format it so it is compareable to the sent content
		my $ReReadContent = km200_GetSingleService($hash);
		   $ReReadContent = $ReReadContent->{switchPoints};
		   $ReReadContent = encode_json($ReReadContent);
		   $ReReadContent =~ s/{"switchPoints"://;
		   $ReReadContent =~ s/]}/]/g;
		   
		### Transform back into array of hashes
		eval 
			{
				$ReReadContent = decode_json(encode_utf8($ReReadContent));
				$JsonContent = decode_json(encode_utf8($JsonContent));
				1;
			}
		or do 
			{
			};
		
		### Set Counter for found items in SwitchPrograms
		my $FoundJsonItem = 0;
		
				
		### For every item of the array of SwitchPrograms to be send
		foreach my $ReReadItem (@{$ReReadContent})
		{
			### Set Counter for found items of ReRead values
			my $FoundReReadItem = 0;
			
			### For every item of the array of SwitchPrograms after Re-Reading 
			foreach my $JsonItem (@{$JsonContent})
			{

				### If the current Switchprogram - hash does not have the same amount of keys
				if (%$ReReadItem != %$JsonItem) 
				{
					### Do nothing
					#print "they don't have the same number of keys\n";
				} 
				### If the current Switchprogram - hash do have the same amount of keys
				else 
				{
					### Compare key names and values
					my %cmp = map { $_ => 1 } keys %$ReReadItem;
					for my $key (keys %$JsonItem) 
					{
						last unless exists $cmp{$key};
						last unless $$ReReadItem{$key} eq $$JsonItem{$key};
						delete $cmp{$key};
					}
					if (%cmp) 
					{
						### Do nothing
						#print "they don't have the same keys or values\n";
					} 
					else 
					{
						### Inkrement Counter
						$FoundReReadItem = 1;
						#print "they have the same keys and values\n";
					}
				}
			}

			### If item has been found
			if ($FoundReReadItem == 1)
			{ 
				### Inkrement Counter for found identical SwitchPoints
				$FoundJsonItem++;
			}
		}
		
		my $ReturnValue;
		
		if 	($FoundJsonItem == @{$ReReadContent})
		{
			$ReturnValue = "The service " . $Service . " has been changed succesfully!";
			if ($hash->{CONSOLEMESSAGE} == true) {print("Writing $Service succesfully \n");}
		}	
		else
		{
			$ReturnValue = "ERROR - The service " . $Service . " could not changed! \n";
			if ($hash->{CONSOLEMESSAGE} == true) {print("Writing $Service was NOT succesfully \n");}
		}

		### Return the status message
		return $ReturnValue;
	}	
	## Check whether the type is a single value containing a string
	elsif($jsonRead->{type} eq "stringValue") 
	{	
		### Save chosen value into hash to be send
		$jsonSend->{value} = $hash->{temp}{postdata};

		### Console outputs for debugging purposes
		if ($hash->{CONSOLEMESSAGE} == true) {print("km200_Set - String value\n");}		

		### Create full URL of the current Service to be written
		my $url ="http://" . $km200_gateway_host . $Service;

		### Encode as json
		$JsonContent = encode_json($jsonSend);
		
		### Encrypt 
		$hash->{temp}{jsoncontent} = $JsonContent;
		$data = km200_Encrypt($hash);

		
		### Create parameter set for HttpUtils_BlockingGet
		my $param = {
						url        => $url,
						timeout    => $PollingTimeout,
						data       => $data,
						method     => "POST",
						header     => "agent: TeleHeater/2.2.3\r\nUser-Agent: TeleHeater/2.2.3\r\nAccept: application/json",
					};
					
		### Block other scheduled and unscheduled routines
		$hash->{status}{FlagSetRequest} = true;

		### Write value with HttpUtils_BlockingGet
		($err, $data) = HttpUtils_BlockingGet($param);

		### Reset flag
		$hash->{status}{FlagSetRequest} = false;
		
		### If error message has been returned
		if($err ne "") 
		{
			Log3 $name, 2, $name . " - ERROR: $err";
			if ($hash->{CONSOLEMESSAGE} == true) {print("km200_PostSingleService - Error: $err\n");}
		
			return $err;	
		}

		### Make a pause before ReadBack
		usleep ($hash->{READBACKDELAY}*1000);
		
		### Read service-hash
		my $ReadValue = km200_GetSingleService($hash);
		
		### Return value
		my $ReturnValue = "";
		if ($ReadValue->{value} eq $hash->{temp}{postdata})
		{	
			$ReturnValue = "The service " . $Service . " has been changed to: " . $ReadValue->{value};
			if ($hash->{CONSOLEMESSAGE} == true) {print("km200_Set - Writing " . $Service . " succesfully with value: " . $hash->{temp}{postdata} . "\n");}
		}
		else
		{
			$ReturnValue = "ERROR - The service " . $Service . " could not changed.";
			if ($hash->{CONSOLEMESSAGE} == true) {print("km200_Set - Writing " . $Service . " was NOT successful\n");}
		}

		### Return the status message
		return $ReturnValue;
	}	
	## Check whether the type is a single value containing a float value
	elsif($jsonRead -> {type} eq "floatValue")
	{
		### Check whether value to be sent is numeric
		if ($hash->{temp}{postdata} =~ /^[0-9.-]+$/) 
		{
			### Save chosen value into hash to be send
			$jsonSend->{value} = ($hash->{temp}{postdata}) * 1;	

			### Console outputs for debugging purposes
			if ($hash->{CONSOLEMESSAGE} == true) {print("km200_Set - Numeric value\n");}
		
			### Create full URL of the current Service to be written
			my $url ="http://" . $km200_gateway_host . $Service;

			### Encode as json
			$JsonContent = encode_json($jsonSend);
			
			### Encrypt 
			$hash->{temp}{jsoncontent} = $JsonContent;
			$data = km200_Encrypt($hash);

			
			### Create parameter set for HttpUtils_BlockingGet
			my $param = {
							url        => $url,
							timeout    => $PollingTimeout,
							data       => $data,
							method     => "POST",
							header     => "agent: TeleHeater/2.2.3\r\nUser-Agent: TeleHeater/2.2.3\r\nAccept: application/json",
						};
						
			### Block other scheduled and unscheduled routines
			$hash->{status}{FlagSetRequest} = true;

			### Write value with HttpUtils_BlockingGet
			($err, $data) = HttpUtils_BlockingGet($param);

			### Reset flag
			$hash->{status}{FlagSetRequest} = false;
			
			### If error messsage has been returned
			if($err ne "") 
			{
				Log3 $name, 2, $name . " - ERROR: $err";
				if ($hash->{CONSOLEMESSAGE} == true) {print("km200_PostSingleService - Error: $err\n");}
				
				
				return $err;	
			}

			### Make a pause before ReadBack
			usleep ($hash->{READBACKDELAY}*1000);	
			
			### Read service-hash
			my $ReadValue = km200_GetSingleService($hash);
			

			### Return value
			my $ReturnValue = "";
			if ($ReadValue->{value} eq $hash->{temp}{postdata})
			{	
				$ReturnValue = "The service " . $Service . " has been changed to: " . $ReadValue->{value} . "\n";
				if ($hash->{CONSOLEMESSAGE} == true) {print("km200_Set - Writing " . $Service . " succesfully with value: " . $hash->{temp}{postdata} . "\n");}
			}
			elsif ($jsonRead -> {value} == $ReadValue->{value})
			{
				$ReturnValue = "ERROR - The service " . $Service . " could not changed to: " . $hash->{temp}{postdata} . "\n The value is: " . $ReadValue->{value} . "\n";
				if ($hash->{CONSOLEMESSAGE} == true) {print("km200_Set - Writing " . $Service . " was NOT successful\n");}
			}
			else
			{
				$ReturnValue = "The service " . $Service . " has been rounded to: " . $ReadValue->{value} . "\n";
				if ($hash->{CONSOLEMESSAGE} == true) {print("km200_Set - Writing " . $Service . " was rounded and changed successful\n");}
			}


			### Return the status message
			return $ReturnValue;
		}
		### If the value to be sent is NOT numeric
		else
		{
			### Console outputs for debugging purposes
			if ($hash->{CONSOLEMESSAGE} == true) {print("km200_Set - ERROR - Float value expected!\n");}
			return ("km200_Set - ERROR - Float value expected!\n");
		}
	}
	## If the type is unknown
	else
	{
		### Log entries for debugging purposes
		Log3 $name, 4, $name. " : km200_SetSingleService - type is unknown for: " .$Service;

		### Console outputs for debugging purposes
		if ($hash->{CONSOLEMESSAGE} == true) {print("km200_Set - Type is unknown for $Service\n");}		
	}
}
####END####### Subroutine set individual data value ############################################################END##### 


###START###### Subroutine get individual data value ###########################################################START####
sub km200_GetSingleService($)
{
	my ($hash, $def)            	= @_;
	my $Service                 	= $hash->{temp}{service};
	my $km200_gateway_host      	= $hash->{URL};
	my $name                    	= $hash->{NAME};
	my $PollingTimeout              = $hash->{POLLINGTIMEOUT};
	my $json -> {type}				= "";
	   $json -> {value}				= "";
	my $err;
	my $data;

	### Console outputs for debugging purposes
	if ($hash->{CONSOLEMESSAGE} == true) {print("Obtaining value of                                     : " . $Service . "\n");}
	
	### Create full URL of the current Service to be read
	my $url ="http://" . $km200_gateway_host . $Service;

	### Create parameter set for HttpUtils_BlockingGet
	my $param = {
					url        => $url,
					timeout    => $PollingTimeout,
					method     => "GET",
					header     => "agent: TeleHeater/2.2.3\r\nUser-Agent: TeleHeater/2.2.3\r\nAccept: application/json",
				};

	### Block other scheduled and unscheduled routines
	$hash->{status}{FlagGetRequest} = true;

	($err, $data) = HttpUtils_BlockingGet($param);

	### Block other scheduled and unscheduled routines
	$hash->{status}{FlagGetRequest} = false;
	
	### If error message has been reported
	if($err ne "") 
	{
		Log3 $name, 2, $name . " : ERROR: Service: ".$Service. ": No proper Communication with Gateway: " .$err;
		if ($hash->{CONSOLEMESSAGE} == true) {print("km200_GetSingleService ERROR: $err\n");}
		my $ReturnMessage ="ERROR";
		$json -> {type}   = $ReturnMessage;
		$json -> {value}  = $ReturnMessage;
		return $json;
	}
	### If NO error message has been reported
	else
	{
		$hash->{temp}{decodedcontent} = $data;
		my $decodedContent = km200_Decrypt($hash);

		if ($decodedContent ne "")
		{
			eval 
			{
				$json = decode_json(encode_utf8($decodedContent));
				1;
			}
			or do 
			{
			Log3 $name, 5, $name. " : km200_GetSingleService - Data cannot be parsed by JSON on km200 for http://" . $param->{url};
			if ($hash->{CONSOLEMESSAGE} == true) {print("Data not parseable on km200 for " . $param->{url} . "\n");}
			};

			### Check whether the type is a single value containing a string or float value
			if(($json -> {type} eq "stringValue") || ($json -> {type} eq "floatValue"))
			{
				my $JsonId         = $json->{id};
				my $JsonType       = $json->{type};
				my $JsonValue      = $json->{value};

				### Save json-hash for DbLog-Split
				$hash->{temp}{ServiceDbLogSplitHash} = $json;
				$hash->{temp}{JsonRaw} = $decodedContent;
				
				
				### Write reading for fhem
				readingsSingleUpdate( $hash, $JsonId, $JsonValue, 1);

				return $json
			}	
			
			### Check whether the type is an switchProgram
			elsif ($json -> {type} eq "switchProgram")
			{
				my $JsonId         = $json->{id};
				my $JsonType       = $json->{type};

				### Log entries for debugging purposes
				Log3 $name, 4, $name. " : km200_ParseHttpResponseDyn: value found for  : " .$Service;
				Log3 $name, 5, $name. " : km200_ParseHttpResponseDyn: id               : " .$JsonId;
				Log3 $name, 5, $name. " : km200_ParseHttpResponseDyn: type             : " .$JsonType;
				
				### Set up variables
				my $TempReturnVal = "";
				my $TempReadingMo = "";
				my $TempReadingTu = "";
				my $TempReadingWe = "";
				my $TempReadingTh = "";
				my $TempReadingFr = "";
				my $TempReadingSa = "";
				my $TempReadingSu = "";
				
				foreach my $item (@{ $json->{switchPoints} })
				{
					### Create string for time and switchpoint in fixed format and write part of Reading String
					
					my $time = $item->{time};
					my $temptime     = $time / 60;
					my $temptimeHH   = int($temptime);
					my $temptimeMM   = ($time - ($temptimeHH * 60));
					
					$temptimeHH = sprintf ('%02d', $temptimeHH);
					$temptimeMM = sprintf ('%02d', $temptimeMM);
					$temptime = $temptimeHH . $temptimeMM;
					
					my $tempsetpoint =  $item->{setpoint};
					$tempsetpoint    =~ s/^(.+)$/sprintf("%s%s", $1, ' 'x(8-length($1)))/e;
					my $TempReading  = $temptime . " " . $tempsetpoint;

					### Create ValueString for this day
					if ($item->{dayOfWeek} eq "Mo")
					{
						### If it is the first entry for this day
						if ($TempReadingMo eq "")
						{
							### Write the first entry
							$TempReadingMo = $TempReading;
						}
						### If it is NOT the first entry for this day
						else
						{
							### Add the next entry
							$TempReadingMo = $TempReadingMo . " " . $TempReading;
						}
					}
					elsif ($item->{dayOfWeek} eq "Tu")
					{
						### If it is the first entry for this day
						if ($TempReadingTu eq "")
						{
							### Write the first entry
							$TempReadingTu = $TempReading;
						}
						### If it is NOT the first entry for this day
						else
						{
							### Add the next entry
							$TempReadingTu = $TempReadingTu . " " . $TempReading;
						}
					}
					elsif ($item->{dayOfWeek} eq "We")
					{
						### If it is the first entry for this day
						if ($TempReadingWe eq "")
						{
							### Write the first entry
							$TempReadingWe = $TempReading;
						}
						### If it is NOT the first entry for this day
						else
						{
							### Add the next entry
							$TempReadingWe = $TempReadingWe . " " . $TempReading;
						}
					}
					elsif ($item->{dayOfWeek} eq "Th")
					{
						### If it is the first entry for this day
						if ($TempReadingTh eq "")
						{
							### Write the first entry
							$TempReadingTh = $TempReading;
						}
						### If it is NOT the first entry for this day
						else
						{
							### Add the next entry
							$TempReadingTh = $TempReadingTh . " " . $TempReading;
						}
					}
					elsif ($item->{dayOfWeek} eq "Fr")
					{
						### If it is the first entry for this day
						if ($TempReadingFr eq "")
						{
							### Write the first entry
							$TempReadingFr = $TempReading;
						}
						### If it is NOT the first entry for this day
						else
						{
							### Add the next entry
							$TempReadingFr = $TempReadingFr . " " . $TempReading;
						}
					}
					elsif ($item->{dayOfWeek} eq "Sa")
					{
						### If it is the first entry for this day
						if ($TempReadingSa eq "")
						{
							### Write the first entry
							$TempReadingSa = $TempReading;
						}
						### If it is NOT the first entry for this day
						else
						{
							### Add the next entry
							$TempReadingSa = $TempReadingSa . " " . $TempReading;
						}
					}
					elsif ($item->{dayOfWeek} eq "Su")
					{
						### If it is the first entry for this day
						if ($TempReadingSu eq "")
						{
							### Write the first entry
							$TempReadingSu = $TempReading;
						}
						### If it is NOT the first entry for this day
						else
						{
							### Add the next entry
							$TempReadingSu = $TempReadingSu . " " . $TempReading;
						}
					}
					else
					{
						if ($hash->{CONSOLEMESSAGE} == true) {print "dayOfWeek of unknow day: " . $item->{dayOfWeek};}
					}
				}

				### Create new Service and write reading for fhem
				$TempReturnVal =                  "1-Mo: " . $TempReadingMo . "\n";
				$TempReturnVal = $TempReturnVal . "2-Tu: " . $TempReadingTu . "\n";
				$TempReturnVal = $TempReturnVal . "3-We: " . $TempReadingWe . "\n";
				$TempReturnVal = $TempReturnVal . "4-Th: " . $TempReadingTh . "\n";
				$TempReturnVal = $TempReturnVal . "5-Fr: " . $TempReadingFr . "\n";
				$TempReturnVal = $TempReturnVal . "6-Sa: " . $TempReadingSa . "\n";
				$TempReturnVal = $TempReturnVal . "7-Su: " . $TempReadingSu . "\n";

				### Save weeklist in "value"
				$json->{value} = $TempReturnVal;
				
				### Save raw Json string
				$hash->{temp}{JsonRaw} = $decodedContent;
	
				
				my $TempJsonId;
				
				### Create new Service and write reading for fhem
				$TempJsonId = $JsonId . "/" . "1-Mo";
				readingsSingleUpdate( $hash, $TempJsonId, $TempReadingMo, 1);

				### Create new Service and write reading for fhem
				$TempJsonId = $JsonId . "/" . "2-Tu";
				readingsSingleUpdate( $hash, $TempJsonId, $TempReadingTu, 1);

				### Create new Service and write reading for fhem
				$TempJsonId = $JsonId . "/" . "3-We";
				readingsSingleUpdate( $hash, $TempJsonId, $TempReadingWe, 1);

				### Create new Service and write reading for fhem
				$TempJsonId = $JsonId . "/" . "4-Th";
				readingsSingleUpdate( $hash, $TempJsonId, $TempReadingTh, 1);

				### Create new Service and write reading for fhem
				$TempJsonId = $JsonId . "/" . "5-Fr";
				readingsSingleUpdate( $hash, $TempJsonId, $TempReadingFr, 1);

				### Create new Service and write reading for fhem
				$TempJsonId = $JsonId . "/" . "6-Sa";
				readingsSingleUpdate( $hash, $TempJsonId, $TempReadingSa, 1);

				### Create new Service and write reading for fhem
				$TempJsonId = $JsonId . "/" . "7-Su";
				readingsSingleUpdate( $hash, $TempJsonId, $TempReadingSu, 1);

				return $json
			}
			### Check whether the type is an errorlist
			elsif ($json -> {type} eq "errorList")
			{
				my $TempErrorList    = "";
				
				### Sort list by timestamps descending
				my @TempSortedErrorList =  sort { $b->{t} <=> $a->{t} } @{ $json->{values} };

				### For every notification do
				foreach my $item (@TempSortedErrorList)
				{					
					### Create message string with fixed blocksize
					my $TempTime      = $item->{t};
					   $TempTime      =~ s/^(.+)$/sprintf("%s%s", $1, ' 'x(20-length($1)))/e;
					my $TempErrorCode = $item->{dcd};
					   $TempErrorCode =~ s/^(.+)$/sprintf("%s%s", $1, ' 'x(3 -length($1)))/e;
					my $TempAddCode   = $item->{ccd};    
					   $TempAddCode   =~ s/^(.+)$/sprintf("%s%s", $1, ' 'x(4 -length($1)))/e;
					my $TempClassCode = $item->{cat};    
					   $TempClassCode =~ s/^(.+)$/sprintf("%s%s", $1, ' 'x(2- length($1)))/e;
					my $TempErrorMessage = "Time: " . $TempTime . "-ErrorCode: " . $TempErrorCode . " -AddCode: " . $TempAddCode . " -Category: " . $TempClassCode;

					### Create List
					$TempErrorList = $TempErrorList . $TempErrorMessage . "\n";
				}
				### Save raw Json string
				$hash->{temp}{JsonRaw} = $decodedContent;
				
				### Save errorList
				$json->{value} = $TempErrorList;
				
				return $json;
			}
			### Check whether the type is an refEnum which is indicating an empty parent directory
			elsif ($json -> {type} eq "refEnum")
			{
				### Initialise Return Message
				my $ReturnMessage = "";

				### For each item found in this empty parent directory
				foreach my $item (@{ $json->{references} })
				{
					### If it is the first item in the list
					if ($ReturnMessage eq "")
					{				
						$ReturnMessage = $item->{id};
					}
					### If it is not the first item in the list
					else
					{
						$ReturnMessage = $ReturnMessage . "\n" . $item->{id};
					}
				}
				### Return list of available directories
				$json->{value} = $ReturnMessage;
				
				### Save raw Json string
				$hash->{temp}{JsonRaw} = $decodedContent;
				
				return $json;
			}		
			### If the type is unknown
			else
			{
				### Log entries for debugging purposes
				Log3 $name, 4, $name. " : km200_GetSingleService - type is unknown for: " .$Service;
				### Log entries for debugging purposes
			}
		}
		else 
		{
			Log3 $name, 4, $name. " : km200_GetSingleService: ". $Service . " NOT available";
			if ($hash->{CONSOLEMESSAGE} == true) {print "The following Service CANNOT be read                   : $Service \n";}
		
			my $ReturnMessage = "ERROR";
			$json -> {type}   = $ReturnMessage;
			$json -> {value}  = $ReturnMessage;
			return $json;
		}
	}
}
####END####### Subroutine get individual data value ############################################################END#####


###START###### Subroutine initial contact of services via HttpUtils ###########################################START####
sub km200_GetInitService($)
{
	my ($hash, $def)                 = @_;
	my $km200_gateway_host           =   $hash->{URL} ;
	my $name                         =   $hash->{NAME} ;
	$hash->{status}{FlagInitRequest} = true;
	my @KM200_InitServices           = @{$hash->{Secret}{KM200ALLSERVICES}};
	my $ServiceCounterInit           = $hash->{temp}{ServiceCounterInit};
	my $PollingTimeout               = $hash->{POLLINGTIMEOUT};
	my $Service                      = $KM200_InitServices[$ServiceCounterInit];


	### If this this loop is accessed for the first time, stop the timer and set status
	if ($ServiceCounterInit == 0)
	{
		### Console Message if enabled
		if ($hash->{CONSOLEMESSAGE} == true) {print("\n" . "Sounding and importing of services started\n");}
		
		### Set status of km200 fhem module
		$hash->{STATE} = "Sounding...";

		### Stop the current timer
		RemoveInternalTimer($hash);
	}


	### Get the values
	my $url ="http://" . $km200_gateway_host . $Service;

	my $param = {
					url        => $url,
					timeout    => $PollingTimeout,
					hash       => $hash,
					method     => "GET",
					header     => "agent: TeleHeater/2.2.3\r\nUser-Agent: TeleHeater/2.2.3\r\nAccept: application/json",
					callback   =>  \&km200_ParseHttpResponseInit
				};

	### Set flag for initialisation
	$hash->{status}{FlagInitRequest} = true;
	
	### Get the value
	HttpUtils_NonblockingGet($param);
}
####END####### Subroutine initial contact of services via HttpUtils ############################################END#####


###START###### Subroutine to download complete initial data set from gateway ##################################START####
# For all known, but not excluded services by attribute "DoNotPoll", try reading the respective values from gateway
sub km200_ParseHttpResponseInit($)
{
    my ($param, $err, $data)     = @_;
    my $hash                     =   $param->{hash};
    my $name                     =   $hash ->{NAME};
	my $ServiceCounterInit       =   $hash ->{temp}{ServiceCounterInit};
	my @KM200_RespondingServices = @{$hash ->{Secret}{KM200RESPONDINGSERVICES}};
	my @KM200_WriteableServices  = @{$hash ->{Secret}{KM200WRITEABLESERVICES}};
	my @KM200_InitServices       = @{$hash ->{Secret}{KM200ALLSERVICES}};	
	my $NumberInitServices       = "";
	my $Service                  = $KM200_InitServices[$ServiceCounterInit];
	my $type;
    my $json ->{type} = "";
	
	
	### Log entries for debugging purposes
	Log3 $name, 5, $name. " : km200_ParseHttpResponseInit: Try to parse     : " .$Service;
	### Log entries for debugging purposes

	
	if($err ne "") 
	{
		Log3 $name, 2, $name . " : ERROR: Service: ".$Service. ": No proper Communication with Gateway: " .$err;
		if ($hash->{CONSOLEMESSAGE} == true) {print("km200_ParseHttpResponseInit ERROR: $err\n");}
		return "ERROR";	
	}

	$hash->{temp}{decodedcontent} = $data;
	my $decodedContent = km200_Decrypt($hash);
	
	### Check whether the decoded content is not empty and therefore available
	if ($decodedContent ne "")
	{	
		eval 
		{
			$json = decode_json(encode_utf8($decodedContent));
			1;
		}
		or do 
		{
			Log3 $name, 4, $name. " : km200_ParseHttpResponseInit: ". $Service . " CANNOT be parsed";
			if ($hash->{CONSOLEMESSAGE} == true) {print "The following Service CANNOT be parsed by JSON         : $Service \n";}
		};

		### Check whether the type is a single value containing a string or float value
		if(($json -> {type} eq "stringValue") || ($json -> {type} eq "floatValue"))
		{
			my $JsonId         = $json->{id};
			my $JsonType       = $json->{type};
			my $JsonValue      = $json->{value};

			### Log entries for debugging purposes
			Log3 $name, 4, $name. " : km200_ParseHttpResponseInit: value found for  : " .$Service;
			Log3 $name, 5, $name. " : km200_ParseHttpResponseInit: id               : " .$JsonId;
			Log3 $name, 5, $name. " : km200_ParseHttpResponseInit: type             : " .$JsonType;
			Log3 $name, 5, $name. " : km200_ParseHttpResponseInit: value            : " .$JsonValue;

			### Add service to the list of responding services
			push (@KM200_RespondingServices, $Service);

			### Save json-hash for DbLog-Split
			$hash->{temp}{ServiceDbLogSplitHash} = $json;

			### Write reading for fhem
			readingsSingleUpdate( $hash, $JsonId, $JsonValue, 1);

			### Console Message if enabled
			if ($hash->{CONSOLEMESSAGE} == true) {print "The following Service can be read";}

			
			### Check whether service is writeable and write name of service in array
			if ($json->{writeable} == 1)
			{
				if ($hash->{CONSOLEMESSAGE} == true) {print " and is writeable     ";}
				push (@KM200_WriteableServices, $Service);
			}
			else
			{
				# Do nothing
				if ($hash->{CONSOLEMESSAGE} == true) {print "                      ";}
			}

			### Console Message if enabled
			if ($hash->{CONSOLEMESSAGE} == true) {print ": $JsonId\n";}
		}	
		### Check whether the type is an switchProgram
		elsif ($json -> {type} eq "switchProgram")
		{
			my $JsonId         = $json->{id};
			my $JsonType       = $json->{type};
			my @JsonValues     = $json->{switchPoints};

			### Log entries for debugging purposes
			Log3 $name, 4, $name. " : km200_ParseHttpResponseInit: value found for  : " .$Service;
			Log3 $name, 5, $name. " : km200_ParseHttpResponseInit: id               : " .$JsonId;
			Log3 $name, 5, $name. " : km200_ParseHttpResponseInit: type             : " .$JsonType;
			Log3 $name, 5, $name. " : km200_ParseHttpResponseInit: value            : " .@JsonValues;

			### Add service to the list of responding services
			push (@KM200_RespondingServices, $Service);
			
			### Console Message if enabled
			if ($hash->{CONSOLEMESSAGE} == true) {print "The following Service can be read";}
			
			### Check whether service is writeable and write name of service in array
			if ($json->{writeable} == 1)
			{
				if ($hash->{CONSOLEMESSAGE} == true) {print " and is writeable     ";}
				push (@KM200_WriteableServices, $Service);
			}
			else
			{
				# Do nothing
				if ($hash->{CONSOLEMESSAGE} == true) {print "                      ";}
			}
			if ($hash->{CONSOLEMESSAGE} == true) {print ": $JsonId\n";}
			
			### Set up variables
			my $TempJsonId    = "";
			my $TempReadingMo = "";
			my $TempReadingTu = "";
			my $TempReadingWe = "";
			my $TempReadingTh = "";
			my $TempReadingFr = "";
			my $TempReadingSa = "";
			my $TempReadingSu = "";
			
			foreach my $item (@{ $json->{switchPoints} })
			{
				### Create string for time and switchpoint in fixed format and write part of Reading String
				my $time         = $item->{time};
				my $temptime     = $time / 60;
				my $temptimeHH   = int($temptime);
				my $temptimeMM   = ($time - ($temptimeHH * 60));

				$temptimeHH = sprintf ('%02d', $temptimeHH);
				$temptimeMM = sprintf ('%02d', $temptimeMM);
				$temptime = $temptimeHH . $temptimeMM;
				
				my $tempsetpoint =  $item->{setpoint};
				$tempsetpoint    =~ s/^(.+)$/sprintf("%s%s", $1, ' 'x(8-length($1)))/e;
				my $TempReading  = $temptime . " " . $tempsetpoint;

				### Create ValueString for this day
				if ($item->{dayOfWeek} eq "Mo")
				{
					### If it is the first entry for this day
					if ($TempReadingMo eq "")
					{
						### Write the first entry
						$TempReadingMo = $TempReading;
					}
					### If it is NOT the first entry for this day
					else
					{
						### Add the next entry
						$TempReadingMo = $TempReadingMo . " " . $TempReading;
					}
				}
				elsif ($item->{dayOfWeek} eq "Tu")
				{
					### If it is the first entry for this day
					if ($TempReadingTu eq "")
					{
						### Write the first entry
						$TempReadingTu = $TempReading;
					}
					### If it is NOT the first entry for this day
					else
					{
						### Add the next entry
						$TempReadingTu = $TempReadingTu . " " . $TempReading;
					}
				}
				elsif ($item->{dayOfWeek} eq "We")
				{
					### If it is the first entry for this day
					if ($TempReadingWe eq "")
					{
						### Write the first entry
						$TempReadingWe = $TempReading;
					}
					### If it is NOT the first entry for this day
					else
					{
						### Add the next entry
						$TempReadingWe = $TempReadingWe . " " . $TempReading;
					}
				}
				elsif ($item->{dayOfWeek} eq "Th")
				{
					### If it is the first entry for this day
					if ($TempReadingTh eq "")
					{
						### Write the first entry
						$TempReadingTh = $TempReading;
					}
					### If it is NOT the first entry for this day
					else
					{
						### Add the next entry
						$TempReadingTh = $TempReadingTh . " " . $TempReading;
					}
				}
				elsif ($item->{dayOfWeek} eq "Fr")
				{
					### If it is the first entry for this day
					if ($TempReadingFr eq "")
					{
						### Write the first entry
						$TempReadingFr = $TempReading;
					}
					### If it is NOT the first entry for this day
					else
					{
						### Add the next entry
						$TempReadingFr = $TempReadingFr . " " . $TempReading;
					}
				}
				elsif ($item->{dayOfWeek} eq "Sa")
				{
					### If it is the first entry for this day
					if ($TempReadingSa eq "")
					{
						### Write the first entry
						$TempReadingSa = $TempReading;
					}
					### If it is NOT the first entry for this day
					else
					{
						### Add the next entry
						$TempReadingSa = $TempReadingSa . " " . $TempReading;
					}
				}
				elsif ($item->{dayOfWeek} eq "Su")
				{
					### If it is the first entry for this day
					if ($TempReadingSu eq "")
					{
						### Write the first entry
						$TempReadingSu = $TempReading;
					}
					### If it is NOT the first entry for this day
					else
					{
						### Add the next entry
						$TempReadingSu = $TempReadingSu . " " . $TempReading;
					}
				}
				else
				{
					if ($hash->{CONSOLEMESSAGE} == true) {print "dayOfWeek of unknow day: " . $item->{dayOfWeek};}
				}
			}

			### Create new Service and write reading for fhem
			$TempJsonId = $JsonId . "/" . "1-Mo";
			readingsSingleUpdate( $hash, $TempJsonId, $TempReadingMo, 1);
			### Console Message if enabled
			if ($hash->{CONSOLEMESSAGE} == true) {print "The following Service can be read and is writeable     : " . $TempJsonId . "\n";}
			### Add service to the list of writeable services
			push (@KM200_WriteableServices, $TempJsonId);

			
			### Create new Service and write reading for fhem
			$TempJsonId = $JsonId . "/" . "2-Tu";
			readingsSingleUpdate( $hash, $TempJsonId, $TempReadingTu, 1);
			### Console Message if enabled
			if ($hash->{CONSOLEMESSAGE} == true) {print "The following Service can be read and is writeable     : " . $TempJsonId . "\n";}
			### Add service to the list of writeable services
			push (@KM200_WriteableServices, $TempJsonId);
			
			
			### Create new Service and write reading for fhem
			$TempJsonId = $JsonId . "/" . "3-We";
			readingsSingleUpdate( $hash, $TempJsonId, $TempReadingWe, 1);
			### Console Message if enabled
			if ($hash->{CONSOLEMESSAGE} == true) {print "The following Service can be read and is writeable     : " . $TempJsonId . "\n";}
			### Add service to the list of writeable services
			push (@KM200_WriteableServices, $TempJsonId);

			
			### Create new Service and write reading for fhem
			$TempJsonId = $JsonId . "/" . "4-Th";
			readingsSingleUpdate( $hash, $TempJsonId, $TempReadingTh, 1);
			### Console Message if enabled
			if ($hash->{CONSOLEMESSAGE} == true) {print "The following Service can be read and is writeable     : " . $TempJsonId . "\n";}
			### Add service to the list of writeable services
			push (@KM200_WriteableServices, $TempJsonId);

			
			### Create new Service and write reading for fhem
			$TempJsonId = $JsonId . "/" . "5-Fr";
			readingsSingleUpdate( $hash, $TempJsonId, $TempReadingFr, 1);
			### Console Message if enabled
			if ($hash->{CONSOLEMESSAGE} == true) {print "The following Service can be read and is writeable     : " . $TempJsonId . "\n";}
			### Add service to the list of writeable services
			push (@KM200_WriteableServices, $TempJsonId);

			
			### Create new Service and write reading for fhem
			$TempJsonId = $JsonId . "/" . "6-Sa";
			readingsSingleUpdate( $hash, $TempJsonId, $TempReadingSa, 1);
			### Console Message if enabled
			if ($hash->{CONSOLEMESSAGE} == true) {print "The following Service can be read and is writeable     : " . $TempJsonId . "\n";}
			### Add service to the list of writeable services
			push (@KM200_WriteableServices, $TempJsonId);

			
			### Create new Service and write reading for fhem
			$TempJsonId = $JsonId . "/" . "7-Su";
			readingsSingleUpdate( $hash, $TempJsonId, $TempReadingSu, 1);
			### Console Message if enabled
			if ($hash->{CONSOLEMESSAGE} == true) {print "The following Service can be read and is writeable     : " . $TempJsonId . "\n";}
			### Add service to the list of writeable services
			push (@KM200_WriteableServices, $TempJsonId);

		}
		### Check whether the type is an errorlist
		elsif ($json -> {type} eq "errorList")
		{
			my $JsonId         = $json->{id};
			my $JsonType       = $json->{type};

			### Log entries for debugging purposes
			Log3 $name, 4, $name. " : km200_ParseHttpResponseInit: value found for  : " .$Service;
			Log3 $name, 5, $name. " : km200_ParseHttpResponseInit: id               : " .$JsonId;
			Log3 $name, 5, $name. " : km200_ParseHttpResponseInit: type             : " .$JsonType;

			### Add service to the list of responding services
			push (@KM200_RespondingServices, $Service);
			
			### Console Message if enabled
			if ($hash->{CONSOLEMESSAGE} == true) {print "The following Service can be read";}
			
			### Check whether service is writeable and write name of service in array
			if ($json->{writeable} == 1)
			{
				if ($hash->{CONSOLEMESSAGE} == true) {print " and is writeable     ";}
				push (@KM200_WriteableServices, $Service);
			}
			else
			{
				# Do nothing
				if ($hash->{CONSOLEMESSAGE} == true) {print "                      ";}
			}
			### Console Message if enabled
			if ($hash->{CONSOLEMESSAGE} == true) {print ": $JsonId\n";}

			
			### Sort list by timestamps descending
			my $TempServiceIndex = 0;
			my @TempSortedErrorList =  sort { $b->{t} <=> $a->{t} } @{ $json->{values} };

			foreach my $item (@TempSortedErrorList)
			{
				### Increment Service-Index
				$TempServiceIndex++;
				
				### Create message string with fixed blocksize
				my $TempTime      = $item->{t};
				   $TempTime      =~ s/^(.+)$/sprintf("%s%s", $1, ' 'x(20-length($1)))/e;
				my $TempErrorCode = $item->{dcd};
				   $TempErrorCode =~ s/^(.+)$/sprintf("%s%s", $1, ' 'x(3 -length($1)))/e;
				my $TempAddCode   = $item->{ccd};    
				   $TempAddCode   =~ s/^(.+)$/sprintf("%s%s", $1, ' 'x(4 -length($1)))/e;
				my $TempClassCode = $item->{cat};    
				   $TempClassCode =~ s/^(.+)$/sprintf("%s%s", $1, ' 'x(2- length($1)))/e;
				my $TempErrorMessage = "Time: " . $TempTime . "-ErrorCode: " . $TempErrorCode . " -AddCode: " . $TempAddCode . " -Category: " . $TempClassCode;
				
				### Create Service with Increment
				my $TempServiceString = $Service . "/Error-" . (sprintf("%02d", $TempServiceIndex));
				
				### Write Reading
				readingsSingleUpdate( $hash, $TempServiceString, $TempErrorMessage, 1);
				
				### Console Message if enabled
				if ($hash->{CONSOLEMESSAGE} == true) {print "The following Service can be read                      : $TempServiceString\n";}
			}
		}
		### Check whether the type is an refEnum which is indicating an empty parent directory
		elsif ($json -> {type} eq "refEnum")
		{
			my $JsonId         = $json->{id};
			my $JsonType       = $json->{type};
			my @JsonReferences = $json->{references};
			
			### Console Message if enabled
			if ($hash->{CONSOLEMESSAGE} == true) {print "The following Service is an empty parent directory     : $JsonId\n";}
			
			### For each item found in this empty parent directory
			foreach my $item (@{ $json->{references} })
			{
				my $SearchWord = $item->{id};
				
				### If the Service found is listed as blocked service
				if ((grep {$_ eq $SearchWord} @{$hash->{Secret}{KM200DONOTPOLL}}) == 1)
				{
					### Do nothing
					
					### Console Message if enabled
					if ($hash->{CONSOLEMESSAGE} == true) {print "The following Service has been found but is blacklisted: " . $item->{id} . "\n";}
				}
				### If the Service found is NOT listed as blocked service
				else
				{
					### Add service to the list of all known services
					push (@{$hash ->{Secret}{KM200ALLSERVICES}}, $item->{id});
				}
			}
			### Sort the list of all services alphabetically
			@{$hash ->{Secret}{KM200ALLSERVICES}} = sort @{$hash ->{Secret}{KM200ALLSERVICES}};
		}
		### Check whether the type is unknown
		else
		{
			### Log entries for debugging purposes
			Log3 $name, 4, $name. " : km200_ParseHttpResponseInit - type is unknown for:" .$Service;
			
			### Console Message if enabled
			if ($hash->{CONSOLEMESSAGE} == true) {print "The data type is unknown for the following Service     : $Service \n";}
			if ($hash->{CONSOLEMESSAGE} == true) {print(" - JsonResponse: " . $json          . "\n");}
			if ($hash->{CONSOLEMESSAGE} == true) {print(" - Type        : " . $json->{type}  . "\n");}
			if ($hash->{CONSOLEMESSAGE} == true) {print(" - Value       : " . $json->{value} . "\n");}
		}
	}
	### Check whether the decoded content is empty and therefore NOT available
	else 
	{
		### Log entries for debugging purposes
		Log3 $name, 4, $name. " : km200_ParseHttpResponseInit: ". $Service . " NOT available";
		
		### Console Message if enabled
		if ($hash->{CONSOLEMESSAGE} == true) {print "The following Service CANNOT be read                   : $Service \n";}
	}

	### Log entries for debugging purposes
	Log3 $name, 5, $name. " : km200_ParseHttpResponseInit    : response         : " .$data;

	### Get the size of the array
	@KM200_InitServices       = @{$hash ->{Secret}{KM200ALLSERVICES}};
	$NumberInitServices       = @KM200_InitServices;
	
	### If the list of KM200ALLSERVICES has not been finished yet
	if ($ServiceCounterInit < ($NumberInitServices-1))
	{
		++$ServiceCounterInit;
		$hash->{temp}{ServiceCounterInit}           = $ServiceCounterInit;
		@{$hash->{Secret}{KM200RESPONDINGSERVICES}} = @KM200_RespondingServices;
		@{$hash->{Secret}{KM200WRITEABLESERVICES}}  = @KM200_WriteableServices;
		km200_GetInitService($hash);
	}
	### If the list of KM200ALLSERVICES is finished
	else
	{
		###START###### Filter all static services out of responsive services = responsive dynamic services ########START####
		my @KM200_DynServices = @KM200_RespondingServices;

		foreach my $SearchWord(@{$hash->{Secret}{KM200STATSERVICES}})
		{
			my $FoundPosition = first_index{ $_ eq $SearchWord }@KM200_DynServices;
			if ($FoundPosition >= 0)
			{
				splice(@KM200_DynServices, $FoundPosition, 1);
			}
		}
		####END####### Filter all static services out of responsive services = responsive dynamic services #########END#####

		###START###### Filter all responsive services out of known static services = responsive static services ###START####
		my @KM200_StatServices = ();

		foreach my $SearchWord(@KM200_RespondingServices)
		{
			my $FoundPosition = first_index{ $_ eq $SearchWord }@{$hash->{Secret}{KM200STATSERVICES}};
			if ($FoundPosition >= 0)
			{
				push (@KM200_StatServices, $SearchWord);
			}
		}
		####END####### Filter all responsive services out of known static services = responsive static services ####END#####
		
		
		### Save arrays of services in hash
		@{$hash->{Secret}{KM200RESPONDINGSERVICES}} = @KM200_RespondingServices;
		@{$hash->{Secret}{KM200WRITEABLESERVICES}}  = @KM200_WriteableServices;
		@{$hash->{Secret}{KM200DYNSERVICES}}        = @KM200_DynServices;
		@{$hash->{Secret}{KM200STATSERVICES}}       = @KM200_StatServices;

		
		### Reset flag for initialisation
		$hash->{status}{FlagInitRequest}            = false;
		
		
		###START###### Initiate the timer for continuous polling of dynamical values from KM200 ###################START####
		InternalTimer(gettimeofday()+($hash->{INTERVALDYNVAL}), "km200_GetDynService", $hash, 0);
		Log3 $name, 4, $name. " : km200 - Define: InternalTimer for dynamic values started with interval of: ".($hash->{INTERVALDYNVAL});
		####END####### Initiate the timer for continuous polling of dynamical values from KM200 ####################END#####

		
		###START###### Initiate the timer for continuous polling of static values from KM200 ######################START####
		if ($hash->{DISABLESTATVALPOLLING} == false)
		{
			InternalTimer(gettimeofday()+($hash->{INTERVALSTATVAL}), "km200_GetStatService", $hash, 0);
			Log3 $name, 4, $name. " : km200 - Define: InternalTimer for static values started with interval of: ".($hash->{INTERVALSTATVAL});
		}
		else
		{
			Log3 $name, 4, $name. " : km200 - Define: No InternalTimer for static values since polling disabled by \"attr IntervalStatVal 0\" in fhem.cfg ";
		}
		####END####### Initiate the timer for continuous polling of static values from KM200 #######################END#####

		### Reset fullResponse error message
		readingsSingleUpdate( $hash, "fullResponse", "OK", 1);
		
		### Console Message if enabled
		if ($hash->{CONSOLEMESSAGE} == true) {print("Sounding and importing of services is completed\n________________________________________________________________________________________________________\n\n");}

		### Set status of km200 fhem module
		$hash->{STATE} = "Standby";

		### Disable flag
		$hash->{temp}{ServiceCounterInit} = false;
	}
	### If the Initialisation process has been interuppted with an error message
	if (ReadingsVal($name,"fullResponse",0) eq "ERROR")
	{
		### Reset fullResponse error message
		readingsSingleUpdate( $hash, "fullResponse", "Restarted after ERROR", 1);
		
		### Reset timer for init procedure and start over again until it works
		InternalTimer(gettimeofday()+5, "km200_GetInitService", $hash, 0);
		Log3 $name, 5, $name. " : km200 - Internal timer for Initialisation of services restarted after fullResponse - error.";
	}
	
	### Clear up temporary variables
	$hash->{temp}{decodedcontent} = "";	
	
	return;
}
####END####### Subroutine to download complete initial data set from gateway ###################################END#####


###START###### Subroutine obtaining dynamic services via HttpUtils ############################################START####
sub km200_GetDynService($)
{
	my ($hash, $def)                 = @_;
	my $km200_gateway_host           =   $hash->{URL};
	my $name                         =   $hash->{NAME};
	$hash->{STATE}                   = "Polling";
	my @KM200_DynServices            = @{$hash->{Secret}{KM200DYNSERVICES}};
	my $ServiceCounterDyn            =   $hash->{temp}{ServiceCounterDyn};
	my $PollingTimeout               =   $hash->{POLLINGTIMEOUT};
	
	### If at least one service to be polled is available
	if (@KM200_DynServices != 0)
	{
		my $Service                  =   $KM200_DynServices[$ServiceCounterDyn];
		
		### Console outputs for debugging purposes
		if ($ServiceCounterDyn == 0)
		{
			if ($hash->{CONSOLEMESSAGE} == true) {print("Starting download of dynamic services\n");}
		}
		
		if ($hash->{CONSOLEMESSAGE} == true) {print("$Service\n");}
		### Console outputs for debugging purposes
		
		my $url = "http://" . $km200_gateway_host . $Service;
		my $param = {
						url        => $url,
						timeout    => $PollingTimeout,
						hash       => $hash,
						method     => "GET",
						header     => "agent: TeleHeater/2.2.3\r\nUser-Agent: TeleHeater/2.2.3\r\nAccept: application/json",
						callback   =>  \&km200_ParseHttpResponseDyn
					};

		### Set Status Flag in order state running dynamic request
		$hash->{status}{FlagDynRequest}           = true;

		### Get data
		HttpUtils_NonblockingGet($param);
	}
	### If no service to be polled is available
	else
	{
		Log3 $name, 5, $name . " : No dynamic values available to be read. Skipping download.";
		if ($hash->{CONSOLEMESSAGE} == true) {print("No dynamic values available to be read. Skipping download.\n")}
	}
}
####END####### Subroutine get dynamic data value ###############################################################END#####

###START###### Subroutine to download complete dynamic data set from gateway ##################################START####
# For all responding dynamic services read the respective values from gateway
sub km200_ParseHttpResponseDyn($)
{
    my ($param, $err, $data)    = @_;
    my $hash                    =   $param->{hash};
    my $name                    =   $hash ->{NAME};
	my $ServiceCounterDyn       =   $hash ->{temp}{ServiceCounterDyn};
	my @KM200_DynServices       = @{$hash ->{Secret}{KM200DYNSERVICES}};	
	my $NumberDynServices       = @KM200_DynServices;
	my $Service                 = $KM200_DynServices[$ServiceCounterDyn];
	my $type;
    my $json ->{type} = "";
	
	Log3 $name, 5, $name. " : Parsing response of dynamic service received for: " . $Service;

	### Reset Status Flag
	$hash->{status}{FlagDynRequest}           = false;
	
	if($err ne "")
	{
		Log3 $name, 2, $name . " : ERROR: Service: ".$Service. ": No proper Communication with Gateway: " .$err;
        readingsSingleUpdate($hash, "fullResponse", "ERROR", 1);
		if ($hash->{CONSOLEMESSAGE} == true) {print("km200_ParseHttpResponseDyn ERROR: $err\n");}
	}

	$hash->{temp}{decodedcontent} = $data;
	my $decodedContent = km200_Decrypt($hash);
	
	if ($decodedContent ne "")
	{
		eval 
		{
			$json = decode_json(encode_utf8($decodedContent));
			1;
		}
		or do 
		{
			Log3 $name, 5, $name. " : km200_parseHttpResponseDyn - Data cannot be parsed by JSON on km200 for http://" . $param->{url};
			if ($hash->{CONSOLEMESSAGE} == true) {print("Data not parseable on km200 for " . $param->{url} . "\n");}
		};
		
		### Check whether the type is a single value containing a string or float value
		if(($json -> {type} eq "stringValue") || ($json -> {type} eq "floatValue"))
		{
			my $JsonId         = $json->{id};
			my $JsonType       = $json->{type};
			my $JsonValue      = $json->{value};
			
			### Log entries for debugging purposes
			Log3 $name, 4, $name. " : km200_parseHttpResponseDyn: value found for  : " .$Service;
			Log3 $name, 5, $name. " : km200_parseHttpResponseDyn: id               : " .$JsonId;
			Log3 $name, 5, $name. " : km200_ParseHttpResponseDyn: type             : " .$JsonType;
			Log3 $name, 5, $name. " : km200_parseHttpResponseDyn: value            : " .$JsonValue;
			### Log entries for debugging purposes

			### Save json-hash for DbLog-Split
			$hash->{temp}{ServiceDbLogSplitHash} = $json;
			### Save json-hash for DbLog-Split

			### Write reading
			readingsSingleUpdate( $hash, $JsonId, $JsonValue, 1);
			### Write reading
		}			
		### Check whether the type is an switchProgram
		elsif ($json -> {type} eq "switchProgram")
		{
			my $JsonId         = $json->{id};
			my $JsonType       = $json->{type};

			### Log entries for debugging purposes
			Log3 $name, 4, $name. " : km200_ParseHttpResponseDyn: value found for  : " .$Service;
			Log3 $name, 5, $name. " : km200_ParseHttpResponseDyn: id               : " .$JsonId;
			Log3 $name, 5, $name. " : km200_ParseHttpResponseDyn: type             : " .$JsonType;
			
			### Set up variables
			my $TempJsonId    = "";
			my $TempReadingMo = "";
			my $TempReadingTu = "";
			my $TempReadingWe = "";
			my $TempReadingTh = "";
			my $TempReadingFr = "";
			my $TempReadingSa = "";
			my $TempReadingSu = "";
			
			foreach my $item (@{ $json->{switchPoints} })
			{
				### Create string for time and switchpoint in fixed format and write part of Reading String
				my $time         = $item->{time};
				my $temptime     = $time / 60;
				my $temptimeHH   = int($temptime);
				my $temptimeMM   = ($time - ($temptimeHH * 60));

				$temptimeHH = sprintf ('%02d', $temptimeHH);
				$temptimeMM = sprintf ('%02d', $temptimeMM);
				$temptime = $temptimeHH . $temptimeMM;
				
				my $tempsetpoint =  $item->{setpoint};
				$tempsetpoint    =~ s/^(.+)$/sprintf("%s%s", $1, ' 'x(8-length($1)))/e;
				my $TempReading  = $temptime . " " . $tempsetpoint;

				### Create ValueString for this day
				if ($item->{dayOfWeek} eq "Mo")
				{
					### If it is the first entry for this day
					if ($TempReadingMo eq "")
					{
						### Write the first entry
						$TempReadingMo = $TempReading;
					}
					### If it is NOT the first entry for this day
					else
					{
						### Add the next entry
						$TempReadingMo = $TempReadingMo . " " . $TempReading;
					}
				}
				elsif ($item->{dayOfWeek} eq "Tu")
				{
					### If it is the first entry for this day
					if ($TempReadingTu eq "")
					{
						### Write the first entry
						$TempReadingTu = $TempReading;
					}
					### If it is NOT the first entry for this day
					else
					{
						### Add the next entry
						$TempReadingTu = $TempReadingTu . " " . $TempReading;
					}
				}
				elsif ($item->{dayOfWeek} eq "We")
				{
					### If it is the first entry for this day
					if ($TempReadingWe eq "")
					{
						### Write the first entry
						$TempReadingWe = $TempReading;
					}
					### If it is NOT the first entry for this day
					else
					{
						### Add the next entry
						$TempReadingWe = $TempReadingWe . " " . $TempReading;
					}
				}
				elsif ($item->{dayOfWeek} eq "Th")
				{
					### If it is the first entry for this day
					if ($TempReadingTh eq "")
					{
						### Write the first entry
						$TempReadingTh = $TempReading;
					}
					### If it is NOT the first entry for this day
					else
					{
						### Add the next entry
						$TempReadingTh = $TempReadingTh . " " . $TempReading;
					}
				}
				elsif ($item->{dayOfWeek} eq "Fr")
				{
					### If it is the first entry for this day
					if ($TempReadingFr eq "")
					{
						### Write the first entry
						$TempReadingFr = $TempReading;
					}
					### If it is NOT the first entry for this day
					else
					{
						### Add the next entry
						$TempReadingFr = $TempReadingFr . " " . $TempReading;
					}
				}
				elsif ($item->{dayOfWeek} eq "Sa")
				{
					### If it is the first entry for this day
					if ($TempReadingSa eq "")
					{
						### Write the first entry
						$TempReadingSa = $TempReading;
					}
					### If it is NOT the first entry for this day
					else
					{
						### Add the next entry
						$TempReadingSa = $TempReadingSa . " " . $TempReading;
					}
				}
				elsif ($item->{dayOfWeek} eq "Su")
				{
					### If it is the first entry for this day
					if ($TempReadingSu eq "")
					{
						### Write the first entry
						$TempReadingSu = $TempReading;
					}
					### If it is NOT the first entry for this day
					else
					{
						### Add the next entry
						$TempReadingSu = $TempReadingSu . " " . $TempReading;
					}
				}
				else
				{
					if ($hash->{CONSOLEMESSAGE} == true) {print "dayOfWeek of unknow day: " . $item->{dayOfWeek};}
				}
			}

			### Create new Service and write reading for fhem
			$TempJsonId = $JsonId . "/" . "1-Mo";
			readingsSingleUpdate( $hash, $TempJsonId, $TempReadingMo, 1);
			
			### Create new Service and write reading for fhem
			$TempJsonId = $JsonId . "/" . "2-Tu";
			readingsSingleUpdate( $hash, $TempJsonId, $TempReadingTu, 1);
			
			### Create new Service and write reading for fhem
			$TempJsonId = $JsonId . "/" . "3-We";
			readingsSingleUpdate( $hash, $TempJsonId, $TempReadingWe, 1);
			
			### Create new Service and write reading for fhem
			$TempJsonId = $JsonId . "/" . "4-Th";
			readingsSingleUpdate( $hash, $TempJsonId, $TempReadingTh, 1);
			
			### Create new Service and write reading for fhem
			$TempJsonId = $JsonId . "/" . "5-Fr";
			readingsSingleUpdate( $hash, $TempJsonId, $TempReadingFr, 1);
			
			### Create new Service and write reading for fhem
			$TempJsonId = $JsonId . "/" . "6-Sa";
			readingsSingleUpdate( $hash, $TempJsonId, $TempReadingSa, 1);
			
			### Create new Service and write reading for fhem
			$TempJsonId = $JsonId . "/" . "7-Su";
			readingsSingleUpdate( $hash, $TempJsonId, $TempReadingSu, 1);
		}
		### Check whether the type is an errorlist
		elsif ($json -> {type} eq "errorList")
		{
			my $JsonId           = $json->{id};
			my $JsonType         = $json->{type};
			my $TempServiceIndex = 0;

			### Sort list by timestamps descending
			my @TempSortedErrorList =  sort { $b->{t} <=> $a->{t} } @{ $json->{values} };

			### For every notification do
			foreach my $item (@TempSortedErrorList)
			{
				### Increment Service-Index
				$TempServiceIndex++;
				
				### Create message string with fixed blocksize
				my $TempTime      = $item->{t};
				   $TempTime      =~ s/^(.+)$/sprintf("%s%s", $1, ' 'x(20-length($1)))/e;
				my $TempErrorCode = $item->{dcd};
				   $TempErrorCode =~ s/^(.+)$/sprintf("%s%s", $1, ' 'x(3 -length($1)))/e;
				my $TempAddCode   = $item->{ccd};    
				   $TempAddCode   =~ s/^(.+)$/sprintf("%s%s", $1, ' 'x(4 -length($1)))/e;
				my $TempClassCode = $item->{cat};    
				   $TempClassCode =~ s/^(.+)$/sprintf("%s%s", $1, ' 'x(2- length($1)))/e;
				my $TempErrorMessage = "Time: " . $TempTime . "-ErrorCode: " . $TempErrorCode . " -AddCode: " . $TempAddCode . " -Category: " . $TempClassCode;
				
				### Create Service with Increment and leading 0
				my $TempServiceString = $Service . "/Error-" . (sprintf("%02d", $TempServiceIndex));
				
				### Write Reading
				readingsSingleUpdate( $hash, $TempServiceString, $TempErrorMessage, 1);
			}
		}
		### Check whether the type is unknown
		else
		{
			### Log entries for debugging purposes
			Log3 $name, 4, $name. " : km200_ParseHttpResponseDyn - type is unknown for:" .$Service;
		}
	}
	else 
	{
		Log3 $name, 5, $name. " : km200_parseHttpResponseDyn - Data not available on km200 for http://" . $param->{url};
		if ($hash->{CONSOLEMESSAGE} == true) {print("Data not available on km200 for " . $param->{url} . "\n");}
	}

	
	### Clear up temporary variables
	$hash->{temp}{decodedcontent} = "";	
	$hash->{temp}{service}        = "";
	### Clear up temporary variables

	### If list is not complete yet
	if ($ServiceCounterDyn < ($NumberDynServices-1))
	{
		++$ServiceCounterDyn;
		$hash->{temp}{ServiceCounterDyn} = $ServiceCounterDyn;
		km200_GetDynService($hash);
	}
	### If list is complete
	else
	{
		$hash->{STATE}                   = "Standby";
		$hash->{temp}{ServiceCounterDyn} = 0;
		if ($hash->{CONSOLEMESSAGE} == true) {print ("Finished\n________________________________________________________________________________________________________\n\n");}
		
		###START###### Re-Start the timer #####################################START####
		InternalTimer(gettimeofday()+$hash->{INTERVALDYNVAL}, "km200_GetDynService", $hash, 1);
		####END####### Re-Start the timer ######################################END#####
		
		### Update fullResponse Reading
		readingsSingleUpdate( $hash, "fullResponse", "OK", 1);
		
		$hash->{status}{FlagDynRequest}  = false;
	}
	return undef;
}
####END####### Subroutine to download complete dynamic data set from gateway ###################################END#####

###START###### Subroutine obtaining static services via HttpUtils #############################################START####
sub km200_GetStatService($)
{
	my ($hash, $def)                 = @_;
	my $km200_gateway_host           =   $hash->{URL};
	my $name                         =   $hash->{NAME};
	$hash->{status}{FlagStatRequest} = true;
	$hash->{STATE}                   = "Polling";
	my @KM200_StatServices           = @{$hash->{Secret}{KM200STATSERVICES}};
	my $ServiceCounterStat           =   $hash->{temp}{ServiceCounterStat};	
	my $PollingTimeout               =   $hash->{POLLINGTIMEOUT};

	if (@KM200_StatServices != 0)
	{
		my $Service                  =   $KM200_StatServices[$ServiceCounterStat];

		### Console outputs for debugging purposes
		if ($ServiceCounterStat == 0)
		{
			if ($hash->{CONSOLEMESSAGE} == true) {print("Starting download of static services\n");}
		}
		
		if ($hash->{CONSOLEMESSAGE} == true) {print("$Service\n");}
		### Console outputs for debugging purposes
		
		my $url = "http://" . $km200_gateway_host . $Service;
		my $param = {
						url        => $url,
						timeout    => $PollingTimeout,
						hash       => $hash,
						method     => "GET",
						header     => "agent: TeleHeater/2.2.3\r\nUser-Agent: TeleHeater/2.2.3\r\nAccept: application/json",
						callback   =>  \&km200_ParseHttpResponseStat
					};

		### Set Status Flag in order state running static request
		$hash->{status}{FlagStatRequest}           = true;

		### Get data
		HttpUtils_NonblockingGet($param);
	}
	else
	{
		Log3 $name, 5, $name . " : No static values available to be read. Skipping download.";
		if ($hash->{CONSOLEMESSAGE} == true) {print("No static values available to be read. Skipping download.\n")}
	}
		
}
####END####### Subroutine get static data value ################################################################END#####

###START###### Subroutine to download complete static data set from gateway ###################################START####
# For all responding static services read the respective values from gateway
sub km200_ParseHttpResponseStat($)
{
    my ($param, $err, $data)    = @_;
    my $hash                    =   $param->{hash};
    my $name                    =   $hash ->{NAME};
	my $ServiceCounterStat      =   $hash ->{temp}{ServiceCounterStat};
	my @KM200_StatServices      = @{$hash ->{Secret}{KM200STATSERVICES}};	
	my $NumberStatServices      = @KM200_StatServices;
	my $Service                 = $KM200_StatServices[$ServiceCounterStat];
	my $json;	
	
	Log3 $name, 5, $name. " : Parsing response of static service received for: " . $Service;

	### Reset Status Flag
	$hash->{status}{FlagStatRequest}           = false;
	
	if($err ne "")
	{
		Log3 $name, 2, $name . " : ERROR: Service: ".$Service. ": No proper Communication with Gateway: " .$err;
        readingsSingleUpdate($hash, "fullResponse", "ERROR", 1);
		if ($hash->{CONSOLEMESSAGE} == true) {print("km200_ParseHttpResponseStat ERROR: $err\n");}
	}

	$hash->{temp}{decodedcontent} = $data;
	my $decodedContent = km200_Decrypt($hash);
	
	if ($decodedContent ne "")
	{
		eval 
		{
			$json = decode_json(encode_utf8($decodedContent));
			1;
		}
		or do 
		{
			Log3 $name, 5, $name. " : km200_parseHttpResponseStat - Data cannot be parsed by JSON on km200 for http://" . $param->{url};
			if ($hash->{CONSOLEMESSAGE} == true) {print("Data not parseable on km200 for " . $param->{url} . "\n");}
		};

		### Check whether the type is a single value containing a string or float value
		if(($json -> {type} eq "stringValue") || ($json -> {type} eq "floatValue"))
		{
			my $JsonId         = $json->{id};
			my $JsonType       = $json->{type};
			my $JsonValue      = $json->{value};
			
			### Log entries for debugging purposes
			Log3 $name, 4, $name. " : km200_parseHttpResponseStat: value found for  : " .$Service;
			Log3 $name, 5, $name. " : km200_parseHttpResponseStat: id               : " .$JsonId;
			Log3 $name, 5, $name. " : km200_ParseHttpResponseStat: type             : " .$JsonType;
			Log3 $name, 5, $name. " : km200_parseHttpResponseStat: value            : " .$JsonValue;
			### Log entries for debugging purposes

			### Save json-hash for DbLog-Split
			$hash->{temp}{ServiceDbLogSplitHash} = $json;
			### Save json-hash for DbLog-Split

			### Write reading
			readingsSingleUpdate( $hash, $JsonId, $JsonValue, 1);
			### Write reading
		}			
		### Check whether the type is unknown
		else
		{
			### Log entries for debugging purposes
			Log3 $name, 4, $name. " : km200_ParseHttpResponseStat - type is unknown for:" .$Service;
		}		
	}
	else 
	{
		Log3 $name, 5, $name. " : km200_parseHttpResponseStat - Data not available on km200 for http://" . $param->{url};
	}

	
	### Clear up temporary variables
	$hash->{temp}{decodedcontent} = "";	
	$hash->{temp}{service}        = "";
	### Clear up temporary variables

	if ($ServiceCounterStat < ($NumberStatServices-1))
	{
		++$ServiceCounterStat;
		$hash->{temp}{ServiceCounterStat} = $ServiceCounterStat;
		km200_GetStatService($hash);
	}
	else
	{
		$hash->{STATE}                    = "Standby";
		$hash->{temp}{ServiceCounterStat} = 0;
		if ($hash->{CONSOLEMESSAGE} == true) {print ("Finished\n________________________________________________________________________________________________________\n\n");}
		
		###START###### Re-Start the timer #####################################START####
		InternalTimer(gettimeofday()+$hash->{INTERVALSTATVAL}, "km200_GetStatService", $hash, 1);
		####END####### Re-Start the timer ######################################END#####

		### Update fullResponse Reading
		readingsSingleUpdate( $hash, "fullResponse", "OK", 1);
		
		$hash->{status}{FlagStatRequest} = false;
	}
	return undef;
}
####END####### Subroutine to download complete static data set from gateway ####################################END#####

1;

###START###### Description for fhem commandref ################################################################START####
=pod
=begin html

<a name="km200"></a>
<h3>KM200</h3>
<ul>
<table>
	<tr>
		<td>
			The Buderus <a href="http://www.buderus.de/Logamatic_Web_KM200-4608125.html">KM200</a> or <a href="http://de.documents.buderus.com/sitemap/document/id/6720807675">KM50</a> is a communication device to establish a connection between the Buderus central heating control unit and the internet.<BR>
			It has been designed in order to allow the inhabitants accessing their heating system via his Buderus App <a href="http://www.buderus.de/Online_Anwendungen/Apps/fuer_den_Endverbraucher/EasyControl-4848514.html"> EasyControl</a>.<BR>
			Furthermore it allows the maintenance companies to access the central heating control system to read and change settings.<BR>
			The km200 module enables read/write access to these parameters.<BR>
			<BR>
			In order to use the KM200 or KM50 with fhem, you must define the private password with the Buderus App <a href="http://www.buderus.de/Online_Anwendungen/Apps/fuer_den_Endverbraucher/EasyControl-4848514.html"> EasyControl</a> first.<BR>
			<BR>
			<font color="#FF0000"><b><u>Remark:</u></b><BR></font>
			Despite the instruction of the Buderus KM200 Installation guide, the ports 5222 and 5223 should not be opened and allow access to the KM200/KM50 module from outside.<BR>
			You should configure (or leave) your internet router with the respective settings.<BR>
			If you want to read or change settings on the heating system, you should access the central heating control system via your fhem system only.<BR>
			<BR>
			As soon the module has been defined within the fhem.cfg, the module is trying to obtain all known/possible services. <BR>
			After this initial contact, the module differs between a set of continuous (dynamically) changing values (e.g.: temperatures) and not changing static values (e.g.: Firmware version).<BR>
			This two different set of values can be bound to an individual polling interval. Refer to <a href="#KM200Attr">Attributes</a><BR> 
			<BR>
			</td>
	</tr>
</table>
  
<table>
<tr><td><a name="KM200define"></a><b>Define</b></td></tr>
</table>

<table><tr><td><ul><code>define &lt;name&gt; km200 &lt;IPv4-address&gt; &lt;GatewayPassword&gt; &lt;PrivatePassword&gt;</code></ul></td></tr></table>

<ul><ul>
	<table>
		<tr><td align="right" valign="top"><code>&lt;name&gt;</code> : </td><td align="left" valign="top">The name of the device. Recommendation: "myKm200".</td></tr>
		<tr><td align="right" valign="top"><code>&lt;IPv4-address&gt;</code> : </td><td align="left" valign="top">A valid IPv4 address of the KM200. You might look into your router which DHCP address has been given to the KM200/KM50.</td></tr>
		<tr><td align="right" valign="top"><code>&lt;GatewayPassword&gt;</code> : </td><td align="left" valign="top">The gateway password which is provided on the type sign of the KM200/KM50.</td></tr>
		<tr><td align="right" valign="top"><code>&lt;PrivatePassword&gt;</code> : </td><td align="left" valign="top">The private password which has been defined by the user via <a href="http://www.buderus.de/Online_Anwendungen/Apps/fuer_den_Endverbraucher/EasyControl-4848514.html"> EasyControl</a>.</td></tr>
	</table>
</ul></ul>

<BR>

<table>
	<tr><td><a name="KM200Set"></a><b>Set</b></td></tr>
	<tr><td>
		<ul>
				The set function is able to change a value of a service which has the "writeable" - tag within the KM200/KM50 service structure.<BR>
				Most of those values have an additional list of allowed values which are the only ones to be set.<BR>
				Other floatable type values can be changed only within their range of minimum and maximum value.<BR>
		</ul>
	</td></tr>
</table>

<table><tr><td><ul><code>set &lt;service&gt; &lt;value&gt;</code></ul></td></tr></table>

<ul><ul>
	<table>
		<tr><td align="right" valign="top"><code>&lt;service&gt;</code> : </td><td align="left" valign="top">The name of the service which value shall be set. E.g.: "<code>/heatingCircuits/hc1/operationMode</code>"<BR></td></tr>
		<tr><td align="right" valign="top"><code>&lt;value&gt;</code> : </td><td align="left" valign="top">A valid value for this service.<BR></td></tr>
	</table>
</ul></ul>

<BR>

<table>
	<tr><td><a name="KM200Get"></a><b>Get</b></td></tr>
	<tr><td>
		<ul>
				The get function is able to obtain a value of a service within the KM200/KM50 service structure.<BR>
				The additional list of allowed values or their range of minimum and maximum value will not be handed back.<BR>
		</ul>
	</td></tr>
</table>

<table><tr><td><ul><code>get &lt;service&gt; &lt;option&gt;</code></ul></td></tr></table>

<ul><ul>
	<table>
		<tr>
			<td align="right" valign="top"><code>&lt;service&gt;</code> : </td><td align="left" valign="top">The name of the service which value shall be obtained. E.g.: "<code>/heatingCircuits/hc1/operationMode</code>"<BR>
																											&nbsp;&nbsp;It returns only the value but not the unit or the range or list of allowed values possible.<BR>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td align="right" valign="top"><code>&lt;option&gt;</code> : </td><td align="left" valign="top">The optional Argument for the result of the get-command e.g.:  "<code>json</code>"<BR>
																											 &nbsp;&nbsp;The following options are available:<BR>
																											 &nbsp;&nbsp;json - Returns the raw json-answer from the KMxxx as string.
			</td>
		</tr>
	</table>
</ul></ul>


<BR>

<table>
	<tr><td><a name="KM200Attr"></a><b>Attributes</b></td></tr>
	<tr><td>
		<ul>
				The following user attributes can be used with the km200 module in addition to the global ones e.g. <a href="#room">room</a>.<BR>
		</ul>
	</td></tr>
</table>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td align="right" valign="top"><li><code>IntervalDynVal</code> : </li></td><td align="left" valign="top">A valid polling interval for the dynamically changing values of the KM200/KM50. The value must be >=20s to allow the km200 module to perform a full polling procedure. <BR>
																												   The default value is 90s.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
	
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td align="right" valign="top"><li><code>IntervalStatVal</code> : </li></td><td align="left" valign="top">A valid polling interval for the statical values of the KM200/KM50. The value must be >=20s to allow the km200 module to perform a full polling procedure. <BR>
																												   The default value is 3600s.<BR>
																												   The value of "0" will disable the polling of statical values until the next fhem restart or a reload of the fhem.cfg - file.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td align="right" valign="top"><li><code>PollingTimeout</code> : </li></td><td align="left" valign="top">A valid time in order to allow the module to wait for a response of the KM200/KM50. Usually this value does not need to be changed but might in case of slow network or slow response.<BR>
																												   The default and minimum value is 5s.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td align="right" valign="top"><li><code>ConsoleMessage</code> : </li></td><td align="left" valign="top">A valid boolean value whether the activity and error messages shall be displayed in the console window. "0" (deactivated) or "1" (activated)<BR>
																												   The default value 0 (deactivated).<BR>
			</td></tr>			
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td align="right" valign="top"><li><code>DoNotPoll</code> : </li></td><td align="left" valign="top">A list of services separated by blanks which shall not be downloaded due to repeatable crashes or irrelevant values.<BR>
																													The list can be filled with the name of the top - hierarchy service, which means everything below that service will also be ignored.<BR>
																													The default value (empty) therefore nothing will be ignored.<BR>
			</td></tr>			
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td align="right" valign="top"><li><code>ReadBackDelay</code> : </li></td><td align="left" valign="top">A valid time in milliseconds [ms] for the delay between writing and re-reading of values after using the "set" - command. The value must be >=0ms.<BR>
																												   The default value is 100 = 100ms = 0,1s.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>


</ul>
=end html


=begin html_DE

<a name="km200"></a>
<h3>KM200</h3>
<ul>
<table>
	<tr>
		<td>
			Das Buderus <a href="http://www.buderus.de/Logamatic_Web_KM200-4608125.html">KM200</a> or <a href="http://de.documents.buderus.com/sitemap/document/id/6720807675">KM50</a> ist eine Schnittstelle zwischen der Buderus Zentralheizungssteuerung un dem Internet.<BR>
			Es wurde entwickelt um den Bewohnern den Zugang zu Ihrem Heizungssystem durch die Buderus App <a href="http://www.buderus.de/Online_Anwendungen/Apps/fuer_den_Endverbraucher/EasyControl-4848514.html"> EasyControl zu erlauben.</a>.<BR>
			Dar&uuml;ber hinaus erlaubt es nach vorheriger Freigabe dem Heizungs- bzw. Wartungsbetrieb die Heizungsanlage von aussen zu warten und Werte zu ver&auml;ndern.<BR>
			Das km200 Modul erlaubt den Lese-/Schreibzugriff dieser Parameter durch fhem.<BR>
			<BR>
			Um das KM200 oder KM50 Ger&auml;t mit fhem nutzen zu k&ouml;nnen, mu&szlig; zun&auml;chst ein privates Passwort mit der Buderus Buderus App <a href="http://www.buderus.de/Online_Anwendungen/Apps/fuer_den_Endverbraucher/EasyControl-4848514.html"> EasyControl</a> - App gesetzt werden.<BR>
			<BR>
			<font color="#FF0000"><b><u>Anmerkung:</u></b><BR></font>
			Unabh&auml;ngig der Installationsanleitung des Buderus KM200 Ger&auml;ts, sollten die Ports 5222 und 5223 am Router geschlossen bleiben um keinen Zugriff von au&szlig;en auf das Ger&auml;t zu erlauben.<BR>
			Der Router sollte entsprechend Konfiguriert bzw. so belassen werden.<BR>
			Wenn der Lese-/Schreibzugriff von aussen gew&uuml;nscht ist, so sollte man ausschlie&szlig;lich &uuml;ber das fhem-System auf die Zentralheizung zugreifen.<BR>
			<BR>
			Sobald das Modul in der fhem.cfg definiert ist, wird das Modul versuchen alle bekannten Services abzuklopfen ob diese in der angeschlossenen Konstellation &uuml;berhaupt vorhanden sind.<BR>
			Nach diesem Initial-Kontakt unterscheidet das Modul zwisachen einem Satz an Services die sich st&auml;ndig (dynamisch) &auml;ndern (z.B.: Vorlauftemperatur) sowie sich nicht st&auml;ndig (statisch) &auml;ndernden Werten (z.B.: Firmware Version).<BR>
			Diese beiden S&auml;tze an Services k&ouml;nnen mir einem individuellen Abfrageintervall versehen werden. Siehe <a href="#KM200Attr">Attributes</a><BR> 
			<BR>
		</td>
	</tr>
</table>
  
<table>
<tr><td><a name="KM200define"></a><b>Define</b></td></tr>
</table>

<table><tr><td><ul><code>define &lt;name&gt; km200 &lt;IPv4-address&gt; &lt;GatewayPassword&gt; &lt;PrivatePassword&gt;</code></ul></td></tr></table>

<ul><ul>
	<table>
		<tr><td align="right" valign="top"><code>&lt;name&gt;</code> : </td><td align="left" valign="top">Der Name des Ger&auml;tes. Empfehlung: "myKm200".</td></tr>
		<tr><td align="right" valign="top"><code>&lt;IPv4-address&gt;</code> : </td><td align="left" valign="top">Eine g&uuml;ltige IPv4 Adresse des KM200. Eventuell im Router nachschauen welche DHCP - Addresse dem KM200/KM50 vergeben wurde.</td></tr>
		<tr><td align="right" valign="top"><code>&lt;GatewayPassword&gt;</code> : </td><td align="left" valign="top">Das gateway Passwort, welches auf dem Typenschild des KM200/KM50 zu finden ist.</td></tr>
		<tr><td align="right" valign="top"><code>&lt;PrivatePassword&gt;</code> : </td><td align="left" valign="top">Das private Passwort, welches durch den User mit Hilfe der <a href="http://www.buderus.de/Online_Anwendungen/Apps/fuer_den_Endverbraucher/EasyControl-4848514.html"> EasyControl</a> - App vergeben wurde.</td></tr>
	</table>
</ul></ul>

<BR>

<table>
	<tr><td><a name="KM200Set"></a><b>Set</b></td></tr>
	<tr><td>
		<ul>
				Die set Funktion &auml;ndert die Werte der Services welche das Flag "schreibbar" innerhalb der KM200/KM50 Service Struktur besitzen.<BR>
				Die meisten dieser beschreibbaren Werte haben eine exklusive Liste von m&ouml;glichen Werten innerhalb dessen sich der neue Wert bewegen muss.<BR>
				Andere Flie&szlig;komma Werte haben einen maximum und minumum Wert, in dessen sich der neue Wert bewegen mu&szlig;.<BR>
		</ul>
	</td></tr>
</table>

<table><tr><td><ul><code>set &lt;service&gt; &lt;value&gt;</code></ul></td></tr></table>

<ul><ul>
	<table>
		<tr><td align="right" valign="top"><code>&lt;service&gt;</code> : </td><td align="left" valign="top">Der Name des Service welcher gesetzt werden soll. Z.B.: "<code>/heatingCircuits/hc1/operationMode</code>"<BR></td></tr>
		<tr><td align="right" valign="top"><code>&lt;value&gt;</code> : </td><td align="left" valign="top">Ein g&uuml;ltiger Wert f&uuml;r diesen Service.<BR></td></tr>
	</table>
</ul></ul>

<BR>

<table>
	<tr><td><a name="KM200Get"></a><b>Get</b></td></tr>
	<tr><td>
		<ul>
				Die get-Funktion ist in der Lage einen Wert eines Service innerhalb der KM200/KM50 Service Struktur auszulesen.<BR>
				Die zus&auml;tzliche Liste von erlaubten Werten oder der Wertebereich zwischen Minimum und Maximum wird nicht zur&uuml;ck gegeben.<BR>
		</ul>
	</td></tr>
</table>

<table><tr><td><ul><code>get &lt;service&gt; &lt;option&gt;</code></ul></td></tr></table>

<ul><ul>
	<table>
		<tr>
			<td align="right" valign="top"><code>&lt;service&gt;</code> : </td><td align="left" valign="top">Der Name des Service welcher ausgelesen werden soll. Z.B.:  "<code>/heatingCircuits/hc1/operationMode</code>"<BR>
																											 &nbsp;&nbsp;Es gibt nur den Wert, aber nicht die Werteliste oder den m&ouml;glichen Wertebereich zur&uuml;ck.<BR>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td align="right" valign="top"><code>&lt;option&gt;</code> : </td><td align="left" valign="top">Das optionelle Argument f𲠤ie Ausgabe des get-Befehls Z.B.:  "<code>json</code>"<BR>
																											 &nbsp;&nbsp;Folgende Optionen sind verf𧢡r:<BR>
																											 &nbsp;&nbsp;json - Gibt anstelle des Wertes, die gesamte Json Antwort des KMxxx als String zur𣫮 
			</td>
		</tr>
	</table>
</ul></ul>

<BR>

<table>
	<tr><td><a name="KM200Attr"></a><b>Attributes</b></td></tr>
	<tr><td>
		<ul>
				Die folgenden Modul-spezifischen Attribute k&ouml;nnen neben den bekannten globalen Attributen gesetzt werden wie z.B.: <a href="#room">room</a>.<BR>
		</ul>
	</td></tr>
</table>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td align="right" valign="top"><li><code>IntervalDynVal</code> : </li></td><td align="left" valign="top">Ein g&uuml;ltiges Abfrageintervall f&uuml;r die sich st&auml;ndig ver&auml;ndernden - dynamischen Werte der KM200/KM50 Services. Der Wert muss gr&ouml;&szlig;er gleich >=20s sein um dem Modul gen&uuml;gend Zeit einzur&auml;umen eine volle Abfrage auszuf&uuml;hren bevor die n&auml;chste Abfrage startet.<BR>
																														 Der Default-Wert ist 90s.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>
	
<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td align="right" valign="top"><li><code>IntervalStatVal</code> : </li></td><td align="left" valign="top">Ein g&uuml;ltiges Abfrageintervall f&uuml;r die statischen Werte des KM200/KM50. Der Wert muss gr&ouml;&szlig;er gleich >=20s sein um dem Modul gen&uuml;gend Zeit einzur&auml;umen eine volle Abfrage auszuf&uuml;hren bevor die n&auml;chste Abfrage startet. <BR>
																														  Der Default-Wert ist 3600s.<BR>
																														  Der Wert "0" deaktiviert die wiederholte Abfrage der statischen Werte bis das fhem-System erneut gestartet wird oder die fhem.cfg neu geladen wird.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td align="right" valign="top"><li><code>PollingTimeout</code> : </li></td><td align="left" valign="top">Ein g&uuml;ltiger Zeitwert um dem KM200/KM50 gen&uuml;gend Zeit zur Antwort einzelner Werte einzur&auml;umen. Normalerweise braucht dieser Wert nicht ver&auml;ndert werden, muss jedoch im Falle eines langsamen Netzwerks erh&ouml;ht werden<BR>
																														 Der Default-Wert ist 5s.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td align="right" valign="top"><li><code>ConsoleMessage</code> : </li></td><td align="left" valign="top">Ein g&uuml;ltiger Boolean Wert (0 oder 1) welcher die Aktivit&auml;ten und Fehlermeldungen des Modul in der Konsole ausgibt. "0" (Deaktiviert) or "1" (Aktiviert)<BR>
																														 Der Default-Wert ist 0 (Deaktiviert).<BR>
			</td></tr>			
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td align="right" valign="top"><li><code>DoNotPoll</code> : </li></td><td align="left" valign="top">Eine durch Leerzeichen (Blank) getrennte Liste von Services welche von der Abfrage aufgrund irrelevanter Werte oder fhem - Abst&uuml;rzen ausgenommen werden sollen.<BR>
																													Die Liste kann auch Hierarchien von services enthalten. Dies bedeutet, das alle Services unterhalb dieses Services ebenfalls gel&ouml;scht werden.<BR>
																													Der Default Wert ist (empty) somit werden alle bekannten Services abgefragt.<BR>
			</td></tr>			
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td align="right" valign="top"><li><code>ReadBackDelay</code> : </li></td><td align="left" valign="top">Ein g&uuml;ltiger Zeitwert in Mllisekunden [ms] f&uuml;r die Pause zwischen schreiben und zur𣫬esen des Wertes durch den "set" - Befehl. Der Wert muss >=0ms sein.<BR>
																												   Der  Default-Wert ist 100 = 100ms = 0,1s.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

</ul>
=end html_DE