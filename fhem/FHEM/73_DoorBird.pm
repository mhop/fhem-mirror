# $Id$
########################################################################################################################
#
#     73_DoorBird.pm
#     Creates the possibility to access and control the DoorBird IP door station
#
#     Author                     : Matthias Deeke 
#     e-mail                     : matthias.deeke(AT)deeke(DOT)eu
#     Fhem Forum                 : https://forum.fhem.de/index.php/topic,100758
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
#     fhem.cfg: define <devicename> DoorBird <IPv4-address> <User> <Password>
#
#     Example:
#     define myDoorBird DoorBird 192.168.178.240 Username SecretPW
#
########################################################################################################################

########################################################################################################################
# List of open Problems:
#
# Check problems with error message after startup: "PERL WARNING: Prototype mismatch: sub main::memcmp: none vs ($$;$) at /usr/local/share/perl/5.24.1/Sub/Exporter.pm line 445."
#
#
########################################################################################################################

package main;

use strict;
use warnings;
use utf8;
use JSON;
use HttpUtils;
use Encode;
use Cwd;
use MIME::Base64;
use Crypt::NaCl::Sodium qw( :utils );
use Crypt::Argon2 qw/argon2i_raw/;
use IO::Socket;
use LWP::UserAgent;
use constant false => 0;
use constant true  => 1;
use Data::Dumper;

###START###### Initialize module ##############################################################################START####
sub DoorBird_Initialize($)
{
    my ($hash)  = @_;

    $hash->{STATE}           = "Init";
    $hash->{DefFn}           = "DoorBird_Define";
    $hash->{UndefFn}         = "DoorBird_Undefine";
    $hash->{SetFn}           = "DoorBird_Set";
    $hash->{GetFn}           = "DoorBird_Get";
    $hash->{AttrFn}          = "DoorBird_Attr";
	$hash->{ReadFn}          = "DoorBird_Read";
	$hash->{DbLog_splitFn}   = "DoorBird_DbLog_splitFn";
	$hash->{FW_detailFn}     = "DoorBird_FW_detailFn";

    $hash->{AttrList}        = "do_not_notify:1,0 " .
							   "header " .
							   "PollingTimeout:slider,1,1,20 " .
							   "MaxHistory:slider,0,1,50 " .
							   "KeepAliveTimeout " .
							   "UdpPort:6524,35344 " .
							   "SipDevice:" . join(",", devspec2array("TYPE=SIP")) . " " .
							   "SipNumber " .
							   "ImageFileDir " .
							   "EventReset " .
							   "SessionIdSec:slider,0,10,600 " .
							   "WaitForHistory " .
							   "disable:1,0 " .
							   "debug:1,0 " .
						       "loglevel:slider,0,1,5 " .
						       $readingFnAttributes;
}
####END####### Initialize module ###############################################################################END#####


###START######  Activate module after module has been used via fhem command "define" ##########################START####
sub DoorBird_Define($$)
{
	my ($hash, $def)		= @_;
	my @a					= split("[ \t][ \t]*", $def);
	my $name				= $a[0];
							 #$a[1] just contains the "DoorBird" module name and we already know that! :-)
	my $url					= $a[2];

	### Delete all Readings for DoorBird
	readingsDelete($hash, ".*");

	### Log Entry and state
	Log3 $name, 4, $name. " : DoorBird - Starting to define device " . $name . " with DoorBird module";
	readingsSingleUpdate($hash, "state", "define", 1);
	
	### Stop the current timer if one exists errornous 
	RemoveInternalTimer($hash);
	Log3 $name, 4, $name. " : DoorBird - InternalTimer has been removed.";
	
	
    ###START### Check whether all variables are available #####################################################START####
	if (int(@a) == 5) 
	{
		###START### Check whether IPv4 address is valid
		if ($url =~ m/^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(|:([0-9]{1,4}|[0-6][0-5][0-5][0-3][0-5])){1}$/)
		{
			Log3 $name, 4, $name. " : DoorBird - IPv4-address is valid                  : " . $url;
		}
		else
		{
			return $name .": Error - IPv4 address is not valid \n Please use \"define <devicename> DoorBird <IPv4-address> <Username> <Password>\" instead!\nExamples for <IPv4-address>:\n192.168.178.240\n192.168.178.240:0 to 192.168.178.240:65535";
		}
		####END#### Check whether IPv4 address is valid	
	}
	else
	{
	    return $name .": DoorBird - Error - Not enough parameter provided." . "\n" . "DoorBird station IPv4 address, Username and Password must be provided" ."\n". "Please use \"define <devicename> DoorBird <IPv4-address> <Username> <Password>\" instead";
	}
	####END#### Check whether all variables are available ######################################################END#####

	###START### Check whether username and password are already encrypted #####################################START####
	### If the username does not contain the "crypt" prefix, then it is still bareword
	if($a[3] =~ /^((?!crypt:).)*$/ ) {
		# Encrypt bareword username and password
		my $username 					= DoorBird_credential_encrypt($a[3]);
		my $password 					= DoorBird_credential_encrypt($a[4]);
		
		### Rewrite definition of device to remove bare passwords
		$hash->{DEF} 					= "$url $username $password";
		
		### Write encrypted credentials into hash
		$hash->{helper}{".USER"}		= $username;
		$hash->{helper}{".PASSWORD"}	= $password;

		### Write Log entry
		Log3 $name, 3, $name. " : DoorBird - Credentials have been encrypted for further use.";
	}
	### If the username contains the "crypt" prefix, then it is already encrypted
	else {
		### Write encrypted credentials into hash
		$hash->{helper}{".USER"}		= $a[3];
		$hash->{helper}{".PASSWORD"}	= $a[4];
	}
	####END#### Check whether username and password are already encrypted ######################################END#####

	###START###### Writing values to global hash ###############################################################START####
	  $hash->{NAME}										= $name;
	  $hash->{RevisonAPI}								= "0.26";
	  $hash->{helper}{SOX}	  							= "/usr/bin/sox"; #On Windows systems use "C:\Programme\sox\sox.exe"
	  $hash->{helper}{URL}	  							= $url;
	  $hash->{helper}{SipDevice}						= AttrVal($name,"SipDevice","");
	  $hash->{helper}{SipNumber}						= AttrVal($name, "SipNumber", "**620");
	  $hash->{helper}{debug}							= 0;
	  $hash->{helper}{PollingTimeout}					= AttrVal($name,"PollingTimeout",5);
	  $hash->{helper}{KeepAliveTimeout}					= AttrVal($name, "KeepAliveTimeout", 30);
	  $hash->{helper}{MaxHistory}						= AttrVal($name, "MaxHistory", 50);
	  $hash->{helper}{HistoryTime}						= "????-??-?? ??:??";
	  $hash->{helper}{UdpPort}							= AttrVal($name, "UdpPort", 6524);
	  $hash->{helper}{SessionIdSec}						= AttrVal($name, "SessionIdSec", 540);
	  $hash->{helper}{ImageFileDir}						= AttrVal($name, "ImageFileDir", 0);
	  $hash->{helper}{EventReset}						= AttrVal($name, "EventReset", 5);
	  $hash->{helper}{WaitForHistory}					= AttrVal($name, "WaitForHistory", 7);
	  $hash->{helper}{CameraInstalled}					= false;
	  $hash->{helper}{SessionId}						= 0;
	  $hash->{helper}{UdpMessageId}						= 0;
	  $hash->{helper}{UdpMotionId}						= 0;
	  $hash->{helper}{UdpDoorbellId}					= 0;
	  $hash->{helper}{UdpKeypadId}						= 0;
	@{$hash->{helper}{RelayAdresses}}					= (0);
	@{$hash->{helper}{Images}{History}{doorbell}}		= ();
	@{$hash->{helper}{Images}{History}{motionsensor}}	= ();
	  $hash->{helper}{Images}{Individual}{Data}			= "";
	  $hash->{helper}{Images}{Individual}{Timestamp}	= "";
	  $hash->{helper}{HistoryDownloadActive} 			= false;
	  $hash->{helper}{HistoryDownloadCount}	 			= 0;
	  $hash->{reusePort} 								= AttrVal($name, 'reusePort', defined(&SO_REUSEPORT)?1:0)?1:0;
	  ####END####### Writing values to global hash ################################################################END#####

	
	###START###### For Debugging purpose only ##################################################################START####
	Log3 $name, 5, $name. " : DoorBird - Define H                               : " . $hash;
	Log3 $name, 5, $name. " : DoorBird - Define D                               : " . $def;
	Log3 $name, 5, $name. " : DoorBird - Define A                               : " . @a;
	Log3 $name, 5, $name. " : DoorBird - Define Name                            : " . $name;
	Log3 $name, 5, $name. " : DoorBird - Define SipDevice                       : " . $hash->{helper}{SipDevice};
	####END####### For Debugging purpose only ###################################################################END#####

	### Initialize Socket connection
	DoorBird_OpenSocketConn($hash);
	
	### Initialize Readings
	DoorBird_Info_Request($hash, "");
	DoorBird_Image_Request($hash, "");
	DoorBird_Live_Video($hash, "off");

	### Initiate the timer for first time
	InternalTimer(gettimeofday()+ $hash->{helper}{KeepAliveTimeout}	, "DoorBird_LostConn",       $hash, 0);
	InternalTimer(gettimeofday()+ 10,                                 "DoorBird_RenewSessionID", $hash, 0);

	return undef;
}
####END####### Activate module after module has been used via fhem command "define" ############################END#####


###START###### To bind unit of value to DbLog entries #########################################################START####
# sub DoorBird_DbLog_splitFn($$)
# {
   # return ();
# }
####END####### To bind unit of value to DbLog entries ##########################################################END#####


###START###### Deactivate module module after "undefine" command by fhem ######################################START####
sub DoorBird_Undefine($$)
{
	my ($hash, $def)  = @_;
	my $name = $hash->{NAME};	
	my $url  = $hash->{URL};

  	### Stop the internal timer for this module
	RemoveInternalTimer($hash);

	### Close UDP scanning
	DevIo_CloseDev($hash);
	
	### Add Log entry
	Log3 $name, 3, $name. " - DoorBird has been undefined. The DoorBird unit will no longer polled.";

	return undef;
}
####END####### Deactivate module module after "undefine" command by fhem #######################################END#####


###START###### Handle attributes after changes via fhem GUI ###################################################START####
sub DoorBird_Attr(@)
{
	my @a                      = @_;
	my $name                   = $a[1];
	my $hash                   = $defs{$name};
	
	### Check whether disable attribute has been provided
	if ($a[2] eq "disable") {
		### Check whether device shall be disabled
		if ($a[3] == 1) {
			### Update STATE of device
			readingsSingleUpdate($hash, "state", "disabled", 1);
			
			### Stop the current timer
			RemoveInternalTimer($hash);
			Log3 $name, 4, $name. " : DoorBird - InternalTimer has been removed.";

			### Delete all Readings
			readingsDelete($hash, ".*");

			### Update STATE of device
			readingsSingleUpdate($hash, "state", "disconnected", 1);
			
			Log3 $name, 3, $name. " : DoorBird - Device disabled as per attribute.";
		}
		else {
			### Update STATE of device
			readingsSingleUpdate($hash, "state", "disconnected", 1);
			Log3 $name, 4, $name. " : DoorBird - Device enabled as per attribute.";
		}
	}
	### Check whether debug attribute has been provided
	elsif ($a[2] eq "debug") {
		### Check whether debug is on
		if ($a[3] == true) {
			### Set helper in hash
			$hash->{helper}{debug} = true;
		}
		### If debug is off
		else {
			### Set helper in hash
			$hash->{helper}{debug} = false;
		}
	}
	### Check whether UdpPort attribute has been provided
	elsif ($a[2] eq "UdpPort") {
		### Check whether UdpPort is numeric
		if ($a[3] == int($a[3])) {
			### Set helper in hash
			$hash->{helper}{UdpPort} = $a[3];
		}
	}
	### Check whether SipDevice attribute has been provided
	elsif ($a[2] eq "SipDevice") {
		### Check whether SipDevice is defined as fhem device
		if (defined($defs{$a[3]})) {
			### Set helper in hash
			$hash->{helper}{SipDevice} = $a[3];
			
			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_Attr - SipDevice set to                  : " . $hash->{helper}{SipDevice};
		}
		else {
			### Set helper in hash
			$hash->{helper}{SipDevice} = "";
			
			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_Attr - SipDevice reset to                : " . $hash->{helper}{SipDevice};
		}
	}
		### Check whether SipNumber attribute has been provided
	elsif ($a[2] eq "SipNumber") {
		### Check whether SipNumber is defined
		if (defined($a[3])) {
			### Set helper in hash
			$hash->{helper}{SipNumber} = $a[3];
		}
		else {
			### Set helper in hash
			$hash->{helper}{SipNumber} = "**620";
		}
	}
	### Check whether PollingTimeout attribute has been provided
	elsif ($a[2] eq "PollingTimeout") {
		### Check whether PollingTimeout is numeric
		if (($a[3] == int($a[3])) && ($a[3] > 0)) {
			### Check whether PollingTimeout is positiv and smaller or equal than 10s
			if (($a[3] > 0) && ($a[3] <= 10)) {
				### Save attribute as internal
				$hash->{helper}{PollingTimeout}	= $a[3];
			}
			### If PollingTimeout is NOT positiv and smaller or equal than 10s
			else {
				### Return error message to GUI
			}
		}
		### If PollingTimeout is NOT numeric
		else {
			### Do nothing
		}
	}
	### Check whether MaxHistory attribute has been provided
	elsif ($a[2] eq "MaxHistory") {
		### Check whether MaxHistory is numeric
		if ($a[3] == int($a[3])) {
			### Check whether MaxHistory is positiv and smaller or equal than 50
			if (($a[3] >= 0) && ($a[3] <= 50)) {
				### Save attribute as internal
				$hash->{helper}{MaxHistory}	= $a[3];
			}
			### If MaxHistory is NOT positiv and smaller or equal than 50
			else {
				### Save attribute as internal
				$hash->{helper}{MaxHistory}	= 50;
			}
		}
		### If MaxHistory is NOT numeric
		else {
			### Save attribute as internal
			$hash->{helper}{MaxHistory}	= 50;
		}
	}
	### Check whether KeepAliveTimeout attribute has been provided
	elsif ($a[2] eq "KeepAliveTimeout") {
		### Remove Timer for LostConn
		RemoveInternalTimer($hash, "DoorBird_LostConn");
		
		### Check whether KeepAliveTimeout is numeric and greater or equal than 10
		if ($a[3] == int($a[3]) && ($a[3] >= 10)) {
			### Save attribute as internal
			$hash->{helper}{KeepAliveTimeout}  = $a[3];
		}
		### If KeepAliveTimeout is NOT numeric or smaller than 10
		else {
			### Save attribute as internal
			$hash->{helper}{KeepAliveTimeout}	= 30;
		}
		### Initiate the timer for first time
		InternalTimer(gettimeofday()+$hash->{helper}{KeepAliveTimeout}, "DoorBird_LostConn", $hash, 0);
	}
	### Check whether SessionIdSec attribute has been provided
	elsif ($a[2] eq "SessionIdSec") {	
		### Remove Timer for LostConn
		RemoveInternalTimer($hash, "DoorBird_RenewSessionID");

		### If the attribute has not been deleted entirely
		if (defined $a[3]) {
	
			### Check whether SessionIdSec is 0 = disabled
			if ($a[3] == int($a[3]) && ($a[3] == 0)) {
				### Save attribute as internal
				$hash->{helper}{SessionIdSec}  = 0;
			}
			### If KeepAliveTimeout is numeric and greater than 9s
			elsif ($a[3] == int($a[3]) &&  ($a[3] > 9)) {

				### Save attribute as internal
				$hash->{helper}{SessionIdSec}  = $a[3];

				### Re-Initiate the timer
				InternalTimer(gettimeofday()+$hash->{helper}{SessionIdSec}, "DoorBird_RenewSessionID", $hash, 0);
			}
			### If KeepAliveTimeout is NOT numeric or smaller than 10
			else{
				### Save standard interval as internal
				$hash->{helper}{SessionIdSec}  = 540;
				
				### Re-Initiate the timer
				InternalTimer(gettimeofday()+$hash->{helper}{SessionIdSec}, "DoorBird_RenewSessionID", $hash, 0);
			}
		}
		### If the attribute has been deleted entirely
		else{
			### Save standard interval as internal
			$hash->{helper}{SessionIdSec}  = 540;
			
			### Re-Initiate the timer
			InternalTimer(gettimeofday()+$hash->{helper}{SessionIdSec}, "DoorBird_RenewSessionID", $hash, 0);
		}
	}
	### Check whether ImageFileSave attribute has been provided
	elsif ($a[2] eq "ImageFileDir") {
		### Check whether ImageFileSave is defined
		if (defined($a[3])) {
			### Set helper in hash
			$hash->{helper}{ImageFileDir} = $a[3];
		}
		else {
			### Set helper in hash
			$hash->{helper}{ImageFileDir} = "";
		}
	}
	### Check whether EventReset attribute has been provided
	elsif ($a[2] eq "EventReset") {
		### Remove Timer for Event Reset
		RemoveInternalTimer($hash, "DoorBird_EventResetMotion");
		RemoveInternalTimer($hash, "DoorBird_EventResetDoorbell");
		#RemoveInternalTimer($hash, "DoorBird_EventResetKeypad");
		
		### Check whether EventReset is numeric and greater than 0
		if ($a[3] == int($a[3]) && ($a[3] > 0)) {
			### Save attribute as internal
			$hash->{helper}{EventReset}  = $a[3];
		}
		### If KeepAliveTimeout is NOT numeric or 0
		else {
			### Save attribute as internal
			$hash->{helper}{EventReset}	= 5;
		}
	}
	### Check whether WaitForHistory attribute has been provided
	elsif ($a[2] eq "WaitForHistory") {
		### Check whether WaitForHistory is numeric and greater than 5
		if ($a[3] == int($a[3]) && ($a[3] > 5)) {
			### Save attribute as internal
			$hash->{helper}{WaitForHistory}  = $a[3];
		}
		### If KeepAliveTimeout is NOT numeric or <5
		else {
			### Save attribute as internal
			$hash->{helper}{WaitForHistory}	= 5;
		}
	}
	### If no attributes of the above known ones have been selected
	else {
		# Do nothing
	}
	return undef;
}
####END####### Handle attributes after changes via fhem GUI ####################################################END#####

###START###### Obtain value after "get" command by fhem #######################################################START####
sub DoorBird_Get($@)
{
	my ( $hash, @a ) = @_;
	
	### If not enough arguments have been provided
	if ( @a < 2 )
	{
		return "\"get DoorBird\" needs at least one argument";
	}
		
	my $name	= shift @a;
	my $command	= shift @a;
	my $option	= shift @a;
	my $optionString;
	
	### Create String to avoid perl warning if option is empty
	if (defined $option) {
		$optionString = $option;
	}
	else {
		$optionString = " ";
	}
	
	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Get - name                               : " . $name;
	Log3 $name, 5, $name. " : DoorBird_Get - command                            : " . $command;
	Log3 $name, 5, $name. " : DoorBird_Get - option                             : " . $optionString;
	
	### Define "get" menu
	my $usage	= "Unknown argument, choose one of ";
	   $usage  .= "Info_Request:noArg List_Favorites:noArg List_Schedules:noArg ";
	
	### If DoorBird has a Camera installed
	if ($hash->{helper}{CameraInstalled} == true) {
		$usage .= "Image_Request:noArg History_Request:noArg "
	}
	### If DoorBird has NO Camera installed
	else {
		# Do not add anything
	}
	### Return values
	return $usage if $command eq '?';
	
	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Get - usage                              : " . $usage;

	### INFO REQUEST
	if ($command eq "Info_Request") {
		### Call Subroutine and hand back return value
		return DoorBird_Info_Request($hash, $option);
	}
	### LIVE IMAGE REQUEST
	elsif ($command eq "Image_Request") {
		### Call Subroutine and hand back return value
		return DoorBird_Image_Request($hash, $option);
	}
	### HISTORY IMAGE REQUEST
	elsif ($command eq "History_Request") {
		if ($hash->{helper}{HistoryDownloadActive} == false) {
			### Call Subroutine and hand back return value
			return DoorBird_History_Request($hash, $option);
		}
		else {
			return "History download already in progress.\nPlease wait and try again later."
		}
	}	
	### LIST FAVORITES
	elsif ($command eq "List_Favorites") {
		### Call Subroutine and hand back return value
		return DoorBird_List_Favorites($hash, $option);
	}
	### LIST SCHEDULES
	elsif ($command eq "List_Schedules") {
		### Call Subroutine and hand back return value
		return DoorBird_List_Schedules($hash, $option);
	}
	### If none of the known options has been chosen
	else {
		### Do nothing
		return
	}
	### MONITOR REQUEST
	### To be implemented via UDP
}
####END####### Obtain value after "get" command by fhem ########################################################END#####


###START###### Manipulate service after "set" command by fhem #################################################START####
sub DoorBird_Set($@)
{
	my ( $hash, @a ) = @_;
	
	### If not enough arguments have been provided
	if ( @a < 2 )
	{
		return "\"get DoorBird\" needs at least one argument";
	}
	
	my $name				= shift @a;
	my $command				= shift @a;
	my $option				= shift @a;
	my $optionString;
	my @RelayAdresses		= @{$hash->{helper}{RelayAdresses}};
	
	### Create String to avoid perl warning if option is empty
	if (defined $option) {
		$optionString = $option;
	}
	else {
		$optionString = " ";
	}
	
	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Set _______________________________________________________________________";
	Log3 $name, 5, $name. " : DoorBird_Set - name                               : " . $name;
	Log3 $name, 5, $name. " : DoorBird_Set - command                            : " . $command;
	Log3 $name, 5, $name. " : DoorBird_Set - option                             : " . $optionString;
	Log3 $name, 5, $name. " : DoorBird_Set - RelayAdresses                      : " . join(",", @RelayAdresses);
	
	### Define "set" menu
	my $usage	= "Unknown argument, choose one of ";
		$usage .= "Open_Door:" . join(",", @RelayAdresses) . " Restart:noArg Transmit_Audio ";

	### If DoorBird has a Camera installed
	if ($hash->{helper}{CameraInstalled} == true) {
		### Create Selection List for camera
		$usage .= "Live_Video:on,off Light_On:noArg Live_Audio:on,off ";
	}
	### If DoorBird has NO Camera installed
	else {
		# Do not add anything
	}
	
	### Return values
	return $usage if $command eq '?';
	
	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Set - usage                              : " . $usage;

	### LIVE VIDEO REQUEST
	if ($command eq "Live_Video") {
		### Call Subroutine and hand back return value
		return DoorBird_Live_Video($hash, $option)	
	}
	### OPEN DOOR
	elsif ($command eq "Open_Door") {
		### Call Subroutine and hand back return value
		return DoorBird_Open_Door($hash, $option)	
	}
	### LIGHT ON
	elsif ($command eq "Light_On") {
		### Call Subroutine and hand back return value
		return DoorBird_Light_On($hash, $option)	
	}
	
	### RESTART
	elsif ($command eq "Restart") {
		### Call Subroutine and hand back return value
		return DoorBird_Restart($hash, $option)	
	}
	### LIVE AUDIO RECEIVE
	elsif ($command eq "Live_Audio") {
		### Call Subroutine and hand back return value
		return DoorBird_Live_Audio($hash, $option)	
	}
	
	### LIVE AUDIO TRANSMIT
	elsif ($command eq "Transmit_Audio") {
		### Call Subroutine and hand back return value
		return DoorBird_Transmit_Audio($hash, $option)	
	}
	### ADD OR CHANGE FAVORITE
	### DELETE FAVORITE
	### ADD OR UPDATE SCHEDULE ENTRY
	### DELETE SCHEDULE ENTRY
	### If none of the above have been selected
	else {
		### Do nothing
		return
	}
}
####END####### Manipulate service after "Set" command by fhem ##################################################END#####

###START###### After return of UDP message ####################################################################START####
sub DoorBird_Read($) {
	my ($hash)            = @_;
	
	### Obtain values from hash
	my $name              = $hash->{NAME};
	my $UdpMessageIdLast  = $hash->{helper}{UdpMessageId};
	my $UdpMotionIdLast   = $hash->{helper}{UdpMotionId};
	my $UdpDoorbellIdLast = $hash->{helper}{UdpDoorbellId};
	my $UdpKeypadIdLast   = $hash->{helper}{UdpKeypadId};
	my $Username 		  = DoorBird_credential_decrypt($hash->{helper}{".USER"});
	my $Password		  = DoorBird_credential_decrypt($hash->{helper}{".PASSWORD"});
	my $PollingTimeout    = $hash->{helper}{PollingTimeout};
	my $url 			  = $hash->{helper}{URL};
	my $Method			  = "GET";
	my $Header			  = "Accept: application/json";
	my $UrlPostfix;
	my $CommandURL;
	my $ReadingEvent;
	my $ReadingEventContent;
	my $err;
	my $data;
	my $buf;
	my $flags;
	
	### Get sending Peerhost
	my $PeerHost = $hash->{CD}->peerhost;
	
	### Get and unpack UDP Datagramm 
	$hash->{CD}->recv($buf, 1024, $flags);
	
	### Unpack Hex-Package
	$data = bin2hex($buf);
	
	### Remove Newlines for better log entries
	$buf =~ s/\n+\z//;
	
	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Read _____________________________________________________________________";
	Log3 $name, 5, $name. " : DoorBird_Read - UDP Client said PeerHost          : " . $PeerHost	if defined($PeerHost);
	Log3 $name, 5, $name. " : DoorBird_Read - UDP Client said buf               : " . $buf		if defined($buf);
	Log3 $name, 5, $name. " : DoorBird_Read - UDP Client said flags             : " . $flags	if defined($flags);
	Log3 $name, 5, $name. " : DoorBird_Read - UDP Client said data              : " . $data		if defined($data);
	
	### If the UDP datagramm comes from the defined DoorBird
	if ((defined($PeerHost)) && ($PeerHost eq $url)) {
		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DoorBird_Read - UDP datagram transmitted by valid PeerHost.";

		### Extract message ID
		my $UdpMessageIdCurrent = $buf;
		   $UdpMessageIdCurrent =~ s/:.*//; 

		### If the first part is only numbers and therefore is the message Id of the KeepAlive datagramm
		if ($UdpMessageIdCurrent =~ /^\d+$/) {

			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_Read - UdpMessage is                     : Still Alive Message";
			Log3 $name, 5, $name. " : DoorBird_Read - UdpMessageIdLast                  : " . $UdpMessageIdLast;
			Log3 $name, 5, $name. " : DoorBird_Read - UdpMessageIdCurrent               : " . $UdpMessageIdCurrent;

			### If the MessageID is integer type has not yet appeared yet
			if ((int($UdpMessageIdCurrent) == $UdpMessageIdCurrent) && ($UdpMessageIdLast != $UdpMessageIdCurrent)) {
				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_Read - UDP datagram transmitted is new - Working on it.";

				### Remove timer for LostConn
				RemoveInternalTimer($hash, "DoorBird_LostConn");

				### If Reading for state is not already "connected"
				if (ReadingsVal($name, "state", "") ne "connected") {
					### Update STATE of device
					readingsSingleUpdate($hash, "state", "connected", 1);

					### Update Reading
					readingsSingleUpdate($hash, "ContactLostSince", "", 1);
				}

				### Initiate the timer for lost connection handling
				InternalTimer(gettimeofday()+ $hash->{helper}{KeepAliveTimeout}, "DoorBird_LostConn", $hash, 0);

				### Store Current UdpMessageId in hash
				$hash->{helper}{UdpMessageId} = $UdpMessageIdCurrent;
			}
			### If the UDP datagram is already known
			else {
				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_Read - UDP datagram transmitted is NOT new - Ignoring it.";
			}
		}
		### If the UDP message is an event message by comparing the first 6 hex-values ignore case sensitivity
		elsif ($data =~ /^deadbe/i) {
			### Decrypt username and password
			my $username = DoorBird_credential_decrypt($hash->{helper}{".USER"});
			my $password = DoorBird_credential_decrypt($hash->{helper}{".PASSWORD"});

			### Split up in accordance to DoorBird API description in hex values
			my $IDENT 	= substr($data, 0, 6);
			my $VERSION = substr($data, 6, 2);
		
			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_Read - UdpMessage is                     : Event Message";
			Log3 $name, 5, $name. " : DoorBird_Read - version of encryption used        : " . $VERSION;

			### If the version 1 of encryption in accordance to the DoorBird API is used
			if (hex($VERSION) == 1){
				### Split up in hex values in accordance to DoorBird API description for encryption version 1 
				my $OPSLIMIT 	= substr($data,     8,  8);
				my $MEMLIMIT 	= substr($data,    16,  8);
				my $SALT		= substr($data,    24, 32);
				my $NONCE		= substr($data,    56, 16);
				my $CIPHERTEXT	= substr($data,    72, 68);
				my $FiveCharPw  = substr($password, 0,  5);
			
				### Generate user friendly hex-string for data
				my $HexFriendlyData;
				for (my $i=0; $i < (length($data)/2); $i++) {
					$HexFriendlyData .= "0x" . substr($data, $i*2,  2) . " ";
				}
				
				### Generate user friendly hex-string for Ident
				my $HexFriendlyIdent;
				for (my $i=0; $i < (length($IDENT)/2); $i++) {
					$HexFriendlyIdent .= "0x" . substr($IDENT, $i*2,  2) . " ";
				}
				
				### Generate user friendly hex-string for Version
				my $HexFriendlyVersion;
				for (my $i=0; $i < (length($VERSION)/2); $i++) {
					$HexFriendlyVersion .= "0x" . substr($VERSION, $i*2,  2) . " ";
				}
				
				### Generate user friendly hex-string for OpsLimit
				my $HexFriendlyOpsLimit;
				for (my $i=0; $i < (length($OPSLIMIT)/2); $i++) {
					$HexFriendlyOpsLimit .= "0x" . substr($OPSLIMIT, $i*2,  2) . " ";
				}
				
				### Generate user friendly hex-string for MemLimit
				my $HexFriendlyMemLimit;
				for (my $i=0; $i < (length($MEMLIMIT)/2); $i++) {
					$HexFriendlyMemLimit .= "0x" . substr($MEMLIMIT, $i*2,  2) . " ";
				}
				
				### Generate user friendly hex-string for Salt
				my $HexFriendlySalt;
				for (my $i=0; $i < (length($SALT)/2); $i++) {
					$HexFriendlySalt .= "0x" . substr($SALT, $i*2,  2) . " ";
				}
				
				### Generate user friendly hex-string for Nonce
				my $HexFriendlyNonce;
				for (my $i=0; $i < (length($NONCE)/2); $i++) {
					$HexFriendlyNonce .= "0x" . substr($NONCE, $i*2,  2) . " ";
				}
				
				### Generate user friendly hex-string for CipherText
				my $HexFriendlyCipherText;
				for (my $i=0; $i < (length($CIPHERTEXT)/2); $i++) {
					$HexFriendlyCipherText .= "0x" . substr($CIPHERTEXT, $i*2,  2) . " ";
				}	
				
				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_Read ------------------------------ Encryption Version 1 in accordance to DoorBird API has been used ------------------------";
				#Log3 $name, 5, $name. " : DoorBird_Read - UDP Client Udp hex                : " . $HexFriendlyData;
				Log3 $name, 5, $name. " : DoorBird_Read - UDP Client Ident hex              : " . $HexFriendlyIdent;
				Log3 $name, 5, $name. " : DoorBird_Read - UDP Client Version hex            : " . $HexFriendlyVersion;
				Log3 $name, 5, $name. " : DoorBird_Read - UDP Client OpsLimit hex           : " . $HexFriendlyOpsLimit;
				Log3 $name, 5, $name. " : DoorBird_Read - UDP Client MemLimit hex           : " . $HexFriendlyMemLimit;
				Log3 $name, 5, $name. " : DoorBird_Read - UDP Client Salt hex               : " . $HexFriendlySalt;
				Log3 $name, 5, $name. " : DoorBird_Read - UDP Client Nonce hex              : " . $HexFriendlyNonce;
				Log3 $name, 5, $name. " : DoorBird_Read - UDP Client Cipher hex             : " . $HexFriendlyCipherText;

				### Convert in accordance to API 0.24 description 
				$IDENT 		= hex($IDENT);
				$VERSION 	= hex($VERSION);
				$OPSLIMIT 	= hex($OPSLIMIT);
				$MEMLIMIT 	= hex($MEMLIMIT);
				$SALT		= pack("H*", $SALT);
				$NONCE		= pack("H*", $NONCE);
				$CIPHERTEXT	= pack("H*", $CIPHERTEXT);

				### Log Entry for debugging purposes			
				Log3 $name, 5, $name. " : DoorBird_Read -- Part 2 ------------------------------------------------------------------------------------------------------------------------";
				Log3 $name, 5, $name. " : DoorBird_Read - UDP IDENT       decimal           : " . $IDENT;
				Log3 $name, 5, $name. " : DoorBird_Read - UDP VERSION     decimal           : " . $VERSION;
				Log3 $name, 5, $name. " : DoorBird_Read - UDP OPSLIMIT    decimal           : " . $OPSLIMIT;
				Log3 $name, 5, $name. " : DoorBird_Read - UDP MEMLIMIT    decimal           : " . $MEMLIMIT;
				Log3 $name, 5, $name. " : DoorBird_Read - UDP FiveCharPw  in character      : " . $FiveCharPw;

				### Create Password Hash or return error message if failed
				my $PASSWORDHASH;
				eval {
					$PASSWORDHASH = argon2i_raw($FiveCharPw, $SALT, $OPSLIMIT, $MEMLIMIT, 1, 32);
					1;
				};
				if ( $@ ) {
					Log3 $name, 3, $name . " " . $@;
					return($@);
				} 
				
				### Unpack Password Hash
				my $StrechedPWHex = unpack("H*",$PASSWORDHASH);

				### Generate user friendly hex-string
				my $StrechedPWHexFriendly;
				for (my $i=0; $i < (length($StrechedPWHex)/2); $i++) {
					$StrechedPWHexFriendly .= "0x" . substr($StrechedPWHex, $i*2,  2) . " ";
				}

				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_Read -- Part 3 ------------------------------------------------------------------------------------------------------------------------";
				Log3 $name, 5, $name. " : DoorBird_Read - UDP StrechedPW hex friendly       : " . $StrechedPWHexFriendly;

				
				### Open crypto_aead object
				my $crypto_aead = Crypt::NaCl::Sodium->aead();
				my $msg;

				### Decrypt message or create error message
				eval {
					$msg = $crypto_aead->decrypt($CIPHERTEXT, "", $NONCE, $PASSWORDHASH);
					
					1;
				};
				if ( $@ ) {
					Log3 $name, 3, $name. " : Message forged!";
				return("Messaged forged!");
				} 
				
				### Unpack message as hex
				 my $DecryptedMsgHex =  $msg->to_hex();
				
				### Generate user friendly hex-string
				my $StrechedMsgHexFriendly;
				for (my $i=0; $i < (length($DecryptedMsgHex)/2); $i++) {
					$StrechedMsgHexFriendly .= "0x" . substr($DecryptedMsgHex, $i*2,  2) . " ";
				}
				
				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_Read -- Part 4 ------------------------------------------------------------------------------------------------------------------------";
				Log3 $name, 5, $name. " : DoorBird_Read - UDP Msg        hex friendly       : " . $StrechedMsgHexFriendly;

				### Split up in accordance to API 0.24 description in hex values
				my $INTERCOM_ID = substr($DecryptedMsgHex,  0, 12);
				my $EVENT 		= substr($DecryptedMsgHex, 12, 16);
				my $TIMESTAMP 	= substr($DecryptedMsgHex, 28,  8);

				### Generate user friendly hex-string for Intercom_Id
				my $Intercom_IdHexFriendly;
				for (my $i=0; $i < (length($INTERCOM_ID)/2); $i++) {
					$Intercom_IdHexFriendly .= "0x" . substr($INTERCOM_ID, $i*2,  2) . " ";
				}
				### Generate user friendly hex-string for Event
				my $EventHexFriendly;
				for (my $i=0; $i < (length($EVENT)/2); $i++) {
					$EventHexFriendly .= "0x" . substr($EVENT, $i*2,  2) . " ";
				}
				### Generate user friendly hex-string for Timestamp
				my $TimestampHexFriendly;
				for (my $i=0; $i < (length($TIMESTAMP)/2); $i++) {
					$TimestampHexFriendly .= "0x" . substr($TIMESTAMP, $i*2,  2) . " ";
				}

				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_Read -- Part 5 ------------------------------------------------------------------------------------------------------------------------";
				Log3 $name, 5, $name. " : DoorBird_Read - UDP Intercom_Id hex friendly      : " . $Intercom_IdHexFriendly;
				Log3 $name, 5, $name. " : DoorBird_Read - UDP Event hex friendly            : " . $EventHexFriendly;
				Log3 $name, 5, $name. " : DoorBird_Read - UDP Timestamp hex friendly        : " . $TimestampHexFriendly;

				### Convert in accordance to API 0.24 description in hex values
				$INTERCOM_ID    = pack("H*", $INTERCOM_ID);
				$EVENT          = pack("H*", $EVENT);
				$TIMESTAMP      = hex($TIMESTAMP);

				### Convert in accordance to API 0.24 description in hex values
				my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime($TIMESTAMP);
				my $TIMESTAMPHR    = sprintf ( "%04d-%02d-%02d %02d:%02d:%02d",$year+1900, $mon+1, $mday, $hour, $min, $sec);

				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_Read -- Part 6 ------------------------------------------------------------------------------------------------------------------------";
				Log3 $name, 5, $name. " : DoorBird_Read - UDP Intercom_Id character         : " . $INTERCOM_ID;
				Log3 $name, 5, $name. " : DoorBird_Read - UDP EVENT character               : " . $EVENT;
				Log3 $name, 5, $name. " : DoorBird_Read - UDP TIMESTAMP UNIX                : " . $TIMESTAMP;
				Log3 $name, 5, $name. " : DoorBird_Read - UDP TIMESTAMP human readeable     : " . $TIMESTAMPHR;

				### Remove trailing whitespace
				$EVENT =~ s/\s+$//;

				### If event belongs to the current user
				if ($username =~ m/$INTERCOM_ID/){
					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_Read -- Part 7 ------------------------------------------------------------------------------------------------------------------------";
					Log3 $name, 5, $name. " : DoorBird_Read - INTERCOM_ID matches username";
				
					### Create first part command URL for DoorBird
					my $UrlPrefix 		= "https://" . $url . "/bha-api/";

					### Update STATE of device
					readingsSingleUpdate($hash, "state", "Downloading image", 1);

				
					### If event has been triggered by motion sensor
					if ($EVENT =~ m/motion/) {
						### If the MessageID is integer type has not yet appeared yet
						if ((int($TIMESTAMP) == $TIMESTAMP) && ($UdpMotionIdLast != $TIMESTAMP)) {
							### Save Timestamp as new ID
							$hash->{helper}{UdpMotionId} = $TIMESTAMP;
							
							### Create name of reading for event
							$ReadingEvent 			= "motion_sensor";
							$ReadingEventContent 	= "Motion detected!";
							
							### Create Parameter for CommandURL for motionsensor events
							$UrlPostfix = "history.cgi?event=motionsensor&index=1";

							### Create complete command URL for DoorBird
							$CommandURL = $UrlPrefix . $UrlPostfix;	
							
							### Define Parameter for Non-BlockingGet
							my $param = {
								url               => $CommandURL,
								timeout           => $PollingTimeout,
								user              => $Username,
								pwd               => $Password,
								hash              => $hash,
								method            => $Method,
								header            => $Header,
								timestamp         => $TIMESTAMP,
								event             => "motionsensor",
								incrementalTimout => 1,
								callback          => \&DoorBird_LastEvent_Image
							};

							### Initiate Bulk Update
							readingsBeginUpdate($hash);
							
							### Update readings of device
							readingsBulkUpdate($hash, "state", $ReadingEventContent, 1);
							readingsBulkUpdate($hash, $ReadingEvent, "triggered", 1);

							### Execute Readings Bulk Update
							readingsEndUpdate($hash, 1);

							### Initiate communication
							HttpUtils_NonblockingGet($param);

							### Wrap up a container and initiate the timer to reset reading "doorbell_button"
							my %Container;
							$Container{"HashReference"} = $hash;
							$Container{"Reading"} 		= $ReadingEvent;
							InternalTimer(gettimeofday()+ $hash->{helper}{EventReset}, "DoorBird_EventReset", \%Container, 0);
							
							### Log Entry
							Log3 $name, 3, $name. " : An event has been triggered by the DoorBird unit  : " . $EVENT;
							Log3 $name, 5, $name. " : DoorBird_Read - Timer for reset reading in        : " . $hash->{helper}{EventReset};
						}
						### If the MessageID is integer type has appeared before
						else {
							### Do nothing
							### Log Entry for debugging purposes
							Log3 $name, 5, $name. " : DoorBird_Read - Motion sensor message already been sent. Ignoring it!";						
						}
					}
					### If event has been triggered by keypad
					elsif ($EVENT =~ m/keypad/) {
						### If the MessageID is integer type has not yet appeared yet
						if ((int($TIMESTAMP) == $TIMESTAMP) && ($UdpKeypadIdLast != $TIMESTAMP)) {
							### Save Timestamp as new ID
							$hash->{helper}{UdpKeypadId} = $TIMESTAMP;

							### Create name of reading for event
							$ReadingEvent 			= "keypad_pin";
							$ReadingEventContent 	= "Access via Keypad!";

							### Create Parameter for CommandURL for keypad events
							$UrlPostfix = "history.cgi?event=keypad&index=1";

							### Create complete command URL for DoorBird
							$CommandURL = $UrlPrefix . $UrlPostfix;	
							
							### Define Parameter for Non-BlockingGet
							my $param = {
								url               => $CommandURL,
								timeout           => $PollingTimeout,
								user              => $Username,
								pwd               => $Password,
								hash              => $hash,
								method            => $Method,
								header            => $Header,
								timestamp         => $TIMESTAMP,
								event             => "keypad",
								incrementalTimout => 1,
								callback          => \&DoorBird_LastEvent_Image
							};
					
							### Initiate Bulk Update
							readingsBeginUpdate($hash);
							
							### Update readings of device
							readingsBulkUpdate($hash, "state", $ReadingEventContent, 1);
							readingsBulkUpdate($hash, $ReadingEvent, "triggered", 1);

							### Execute Readings Bulk Update
							readingsEndUpdate($hash, 1);

							### Initiate communication and close
							HttpUtils_NonblockingGet($param);

							### Wrap up a container and initiate the timer to reset reading "doorbell_button"
							my %Container;
							$Container{"HashReference"} = $hash;
							$Container{"Reading"} 		= $ReadingEvent;
							InternalTimer(gettimeofday()+ $hash->{helper}{EventReset}, "DoorBird_EventReset", \%Container, 0);
							
							### Log Entry
							Log3 $name, 3, $name. " : An event has been triggered by the DoorBird unit  : " . $EVENT;
							Log3 $name, 5, $name. " : DoorBird_Read - Timer for reset reading in        : " . $hash->{helper}{EventReset};
						}
						### If the MessageID is integer type has appeared before
						else {
							### Do nothing
							### Log Entry for debugging purposes
							Log3 $name, 5, $name. " : DoorBird_Read - Keypad message already been sent. Ignoring it!";						
						}
					}
					### If event has been triggered by doorbell -> Only a number has been transfered
					elsif (int($EVENT) == $EVENT) {
						### If the MessageID is integer type has not yet appeared yet
						if ((int($TIMESTAMP) == $TIMESTAMP) && ($UdpDoorbellIdLast != $TIMESTAMP)) {
							### Save Timestamp as new ID
							$hash->{helper}{UdpDoorbellId} = $TIMESTAMP;

							### Create name of reading for event
							$ReadingEvent 			= "doorbell_button_"   . sprintf("%03d", $EVENT);
							$ReadingEventContent 	= "doorbell pressed!";
							
							### Create Parameter for CommandURL for doorbell events
							$UrlPostfix = "history.cgi?event=doorbell&index=1";

							### Create complete command URL for DoorBird
							$CommandURL = $UrlPrefix . $UrlPostfix;	
							
							### Define Parameter for Non-BlockingGet
							my $param = {
								url               => $CommandURL,
								timeout           => $PollingTimeout,
								user              => $Username,
								pwd               => $Password,
								hash              => $hash,
								method            => $Method,
								header            => $Header,
								timestamp         => $TIMESTAMP,
								event             => "doorbell",
								doorbellNo        => $EVENT,
								incrementalTimout => 1,
								callback          => \&DoorBird_LastEvent_Image
							};
					
							### Initiate Bulk Update
							readingsBeginUpdate($hash);
							
							### Update readings of device
							readingsBulkUpdate($hash, "state", $ReadingEventContent, 1);
							readingsBulkUpdate($hash, $ReadingEvent, "triggered", 1);

							### Execute Readings Bulk Update
							readingsEndUpdate($hash, 1);

							### Initiate communication and close
							HttpUtils_NonblockingGet($param);

							### Wrap up a container and initiate the timer to reset reading "doorbell_button"
							my %Container;
							$Container{"HashReference"} = $hash;
							$Container{"Reading"} 		= $ReadingEvent;
							InternalTimer(gettimeofday()+ $hash->{helper}{EventReset}, "DoorBird_EventReset", \%Container, 0);
							
							### Log Entry
							Log3 $name, 3, $name. " : An event has been triggered by the DoorBird unit  : " . $EVENT;
							Log3 $name, 5, $name. " : DoorBird_Read - Timer for reset reading in        : " . $hash->{helper}{EventReset};
						}
						### If the MessageID is integer type has appeared before
						else {
							### Do nothing
							### Log Entry for debugging purposes
							Log3 $name, 5, $name. " : DoorBird_Read - Doorbell message already been sent. Ignoring it!";						
						}
					}
					### If the event has been triggered by unknown code
					else {
						### Log Entry
						Log3 $name, 3, $name. " : Unknown event triggered by Doorbird Unit : " . $EVENT;
					}
				}
				### Event does not belong to the current user
				else {
					### Do nothing
					
					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_Read -- Part 7 ------------------------------------------------------------------------------------------------------------------------";
					Log3 $name, 5, $name. " : DoorBird_Read - INTERCOM_ID does not matches username. Ignoring datagram packet!";
				}
			}
		}
	}
	else {
		### Do nothing

		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DoorBird_Read - UDP datagram transmitted by invalid PeerHost.";
	}
}
####END####### After return of UDP message #####################################################################END#####

###START###### Open UDP socket connection #####################################################################START####
sub DoorBird_OpenSocketConn($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $conn;
	my $port = $hash->{helper}{UdpPort};
	
	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_OpenSocketConn - port                    : " . $port;

	### Check if connection can be opened	
	$conn = new IO::Socket::INET (
		ReusePort => $hash->{reusePort},
		LocalPort => $port,
		Proto     => 'udp'
	);
	
	### Log Entry for debugging purposes
	my $ShowConn = Dumper($conn);
	$ShowConn =~ s/[\t]//g;
	$ShowConn =~ s/[\r]//g;
	$ShowConn =~ s/[\n]//g;
	Log3 $name, 5, $name. " : DoorBird_OpenSocketConn - SocketConnection        : " . $ShowConn;
	
	
	if (defined($conn)) {
		$hash->{FD}    		= $conn->fileno();
		$hash->{CD}			= $conn;
		$selectlist{$name}	= $hash;
		
		### Log Entry for debugging purposes
		Log3 $name, 4, $name. " : DoorBird_OpenSocketConn - Socket Connection has been established";
	}
	else {
		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DoorBird_OpenSocketConn - Socket Connection has NOT been established";
	}
	return
}
####END####### Open UDP socket connection ######################################################################END#####

###START###### Lost Connection with DorBird unit ##############################################################START####
sub DoorBird_LostConn($) {
	my ($hash) = @_;

	### Obtain values from hash
    my $name = $hash->{NAME};

	### Create Timestamp
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
	my $TimeStamp = sprintf ( "%04d-%02d-%02d %02d:%02d:%02d",$year+1900, $mon+1, $mday, $hour, $min, $sec);
	
	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_LostConn - Connection with DoorBird Unit lost";

	### If Reading for state is not already disconnected
	if (ReadingsVal($name, "state", "") ne "disconnected") {
		### Update STATE of device
		readingsSingleUpdate($hash, "state", "disconnected", 1);
	
		### Update Reading
		readingsSingleUpdate($hash, "ContactLostSince", $TimeStamp, 1);
	}
	return;
}
####END####### Lost Connection with DorBird unit ###############################################################END#####

###START###### Reset event reading ############################################################################START####
sub DoorBird_EventReset($) {
	my ($ContainerRef) = @_;
	
	### Transform hash-Reference into hash
	my %Container = %$ContainerRef;
	
	### Extract hash and reading to be reset
	my $hash        = $Container{"HashReference"};
	my $Reading     = $Container{"Reading"};

	### Obtain values from hash
    my $name = $hash->{NAME};

	### Log Entry for debugging purposes
	Log3 $name, 3, $name. " : DoorBird_EventReset - Reseting reading to idle    : " . $Reading;

	### Update readings of device
	readingsSingleUpdate($hash, "state",  "connected", 1);
	readingsSingleUpdate($hash, $Reading, "idle",      1);
	
	return;
}
####END####### Reset event reading #############################################################################END#####

###START###### Renew Session ID for DorBird unit ##############################################################START####
sub DoorBird_RenewSessionID($) {
	my ($hash) = @_;

	### Obtain values from hash
    my $name 	= $hash->{NAME};
	my $command	= "getsession.cgi"; 
	my $method	= "GET";
	my $header	= "Accept: application/json";
	my $err 	= " ";
	my $data 	= " ";
	my $json;
	
	### Obtain data
	($err, $data) = DoorBird_BlockGet($hash, $command, $method, $header);

	### Remove Newlines for better log entries
	my $ShowData = $data;
	$ShowData =~ s/[\t]//g;
	$ShowData =~ s/[\r]//g;
	$ShowData =~ s/[\n]//g;
	
	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_RenewSessionID  - err                    : " . $err      if(defined($err));
	Log3 $name, 5, $name. " : DoorBird_RenewSessionID  - data                   : " . $ShowData if(defined($ShowData));
	
	### If no error has been handed back
	if ($err eq "") {
		### Check if json can be parsed into hash	
		eval 
		{
			$json = decode_json(encode_utf8($data));
			1;
		}
		or do 
		{
			### Log Entry for debugging purposes
			Log3 $name, 3, $name. " : DoorBird_RenewSessionID - Data cannot parsed JSON   : Info_Request";
			return $name. " : DoorBird_RenewSessionID - Data cannot be parsed by JSON for Info_Request";
		};
	
		### Extract SessionId from hash
		$hash->{helper}{SessionId} = $json-> {BHA}{SESSIONID};

		### Remove timer for LostConn
		RemoveInternalTimer($hash, "DoorBird_RenewSessionID");

		### If a time interval for the Session ID has been provided.
		if ($hash->{helper}{SessionIdSec} > 0) {
			### Initiate the timer for renewing SessionId
			InternalTimer(gettimeofday()+ $hash->{helper}{SessionIdSec}, "DoorBird_RenewSessionID", $hash, 0);

			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_RenewSessionID - Session ID refreshed    : " . $hash->{helper}{SessionId};
		}
		### If a time interval of 0 = disabled has been provided.
		else {
			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_RenewSessionID - Session ID Security has been disabled - No further renewing of SessionId.";
		}
		
		### If the VideoStream has been activated
		if (ReadingsVal($name, ".VideoURL", "") ne "") {
			### Refresh Video URL
			DoorBird_Live_Video($hash, undef);
			
			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_RenewSessionID - VideoUrl refreshed";
		}
		
		### If the AudioStream has been activated
		if (ReadingsVal($name, ".AudioURL", "") ne "") {
			### Refresh Video URL
			DoorBird_Live_Audio($hash, undef);
			
			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_RenewSessionID - AudioUrl refreshed";
		}
		return
	}
	### If error has been handed back
	else {
		$err =~ s/^[^ ]*//;
		return "ERROR!\nError Code:" . $err;
	}
	return;
}
####END####### Renew Session ID for DorBird unit ###############################################################END#####

###START###### Display of html code preceding the "Internals"-section #########################################START####
sub DoorBird_FW_detailFn($$$$) {
	my ($FW_wname, $devname, $room, $extPage) = @_;
	my $hash 			= $defs{$devname};
	my $name 			= $hash->{NAME};
	my $ImageData		= $hash->{helper}{Images}{Individual}{Data};
	my $ImageTimeStamp	= $hash->{helper}{Images}{Individual}{Timestamp};
	
	my $VideoURL		= ReadingsVal($name, ".VideoURL", "");
	my $ImageURL		= ReadingsVal($name, ".ImageURL", "");
	my $AudioURL		= ReadingsVal($name, ".AudioURL", "");
	my $htmlCode;
	my $VideoHtmlCode;
	my $ImageHtmlCode;
	my $ImageHtmlCodeBig;
	my $AudioHtmlCode;
	my @HistoryDoorbell;
	my @HistoryMotion;


	### Only if DoorBird has a Camera installed view the Image and History Part
	if ($hash->{helper}{CameraInstalled} == true) {
		
		### Log Entry for debugging purposes
		if (defined $hash->{helper}{Images}{History}{doorbell}) {
			@HistoryDoorbell = @{$hash->{helper}{Images}{History}{doorbell}};
			Log3 $name, 5, $name. " : DoorBird_FW_detailFn - Size ImageData doorbell    : " . @HistoryDoorbell;
		}
		### Log Entry for debugging purposes
		if (defined $hash->{helper}{Images}{History}{motionsensor}) {
			@HistoryMotion   = @{$hash->{helper}{Images}{History}{motionsensor}};
			Log3 $name, 5, $name. " : DoorBird_FW_detailFn - Size ImageData motion      : " . @HistoryMotion;
		}
		
		### If VideoURL is empty
		if ($VideoURL eq "") {
			### Create Standard Response
			$VideoHtmlCode = "Video Stream deactivated";
		}
		### If VideoURL is NOT empty
		else {

			### Create proper html code including popup
			my $ImageHtmlCodeBig =  "<img src=\\'" . $VideoURL . "\\'>";
			my $PopupfunctionCode = "onclick=\"FW_okDialog(\'" . $ImageHtmlCodeBig . "\') \" ";
			$VideoHtmlCode    =  '<img ' . $PopupfunctionCode . ' width="400" height="300"  src="' . $VideoURL . '">';

			### Create proper html link
			#$VideoHtmlCode = '<img src="' . $VideoURL . '" width="400px" height="300px">';
		}
		
		### If ImageData is empty
		if ($ImageData eq "") {
			### Create Standard Response
			$ImageHtmlCode = "Image not available";
		}
		### If ImageData is NOT empty
		else {
			### Create proper html code including popup
			my $ImageHtmlCodeBig  =  "<img src=\\'data:image/jpeg;base64," . $ImageData . "\\'><br><center>" . $ImageTimeStamp . "</center>";
			my $PopupfunctionCode = "onclick=\"FW_okDialog(\'" . $ImageHtmlCodeBig . "\') \" ";
			$ImageHtmlCode   	  =  '<img ' . $PopupfunctionCode . ' width="400" height="300" alt="tick" src="data:image/jpeg;base64,' . $ImageData . '">';
		}
		
			### If AudioURL is empty
		if ($AudioURL eq "") {
			### Create Standard Response
			$AudioHtmlCode = "Audio Stream deactivated";
		}
		### If AudioURL is NOT empty
		else {
			### Create proper html code
			$AudioHtmlCode =  '<audio id="audio_with_controls" controls src="' . $AudioURL . '" ">Your Browser cannot play this audio stream.</audio>';
		}
		#type="audio/wav
		
		### Create html Code
		$htmlCode = '
		<table border="1" style="border-collapse:separate;">
			<tbody >
				<tr>
					<td width="400px" align="center"><b>Image from ' . $ImageTimeStamp . '</b></td>
					<td width="400px" align="center"><b>Live Stream</b></td>
				</tr>
				
				<tr>
					<td id="ImageCell" width="430px" height="300px" align="center">
						' . $ImageHtmlCode  . '
					</td>

					<td id="ImageCell" width="435px" height="300px" align="center">
						' . $VideoHtmlCode . '<BR>
					</td>
				</tr>
				
				<tr>
					<td></td>
					<td align="center">' . $AudioHtmlCode . '</td>
				</tr>	
			</tbody>
		</table>
		';
		
		### Log Entry for debugging purposes
		#	Log3 $name, 5, $name. " : DoorBird_FW_detailFn - ImageHtmlCode              : " . $ImageHtmlCode;
		#	Log3 $name, 5, $name. " : DoorBird_FW_detailFn - VideoHtmlCode              : " . $VideoHtmlCode;
		#	Log3 $name, 5, $name. " : DoorBird_FW_detailFn - AudioHtmlCode              : " . $AudioHtmlCode;
		
		if ((@HistoryDoorbell > 0) || (@HistoryMotion > 0)) {
			$htmlCode .=	
			'
			<BR>
			<BR>
			<table border="1" style="border-collapse:separate;">
				<tbody >
					<tr>
						<td align="center" colspan="5"><b>History of events - Last download: ' . $hash->{helper}{HistoryTime} . '</b></td>
					</tr>

					<tr>
						<td align="center" colspan="2"><b>Doorbell</b></td>
						<td align="center"></td>
						<td align="center" colspan="2"><b>Motion-Sensor</b></td>
					</tr>
					<tr>
						<td width="195px" align="center"><b>Picture</b></td>
						<td width="195px" align="center"><b>Timestamp</b></td>
						<td width="20px" align="center">#</td>
						<td width="195px" align="center"><b>Picture</b></td>
						<td width="195px" align="center"><b>Timestamp</b></td>
					</tr>		
			';

			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_FW_detailFn - hash->{helper}{MaxHistory} : " . $hash->{helper}{MaxHistory};
			
			### For all entries in Picture-Array do
			for (my $i=0; $i <= ($hash->{helper}{MaxHistory} - 1); $i++) {
				
				my $ImageHtmlCodeDoorbell;
				my $ImageHtmlCodeMotion;
				
				### Create proper html code for image triggered by doorbell
				if ($HistoryDoorbell[$i]{data} ne "") {
					### If element contains an error message
					if ($HistoryDoorbell[$i]{data} =~ m/Error/) {
						$ImageHtmlCodeDoorbell     = $HistoryDoorbell[$i]{data};
					}
					### If element does not contain an error message
					else {
						### Create proper html code including popup
						my $ImageHtmlCodeBig =  "<img src=\\'data:image/jpeg;base64," . $HistoryDoorbell[$i]{data} . "\\'><br><center>" . $HistoryDoorbell[$i]{timestamp} . "</center>";
						my $PopupfunctionCode = "onclick=\"FW_okDialog(\'" . $ImageHtmlCodeBig . "\') \" ";
						$ImageHtmlCodeDoorbell    =  '<img ' . $PopupfunctionCode . ' width="190" height="auto" alt="tick" src="data:image/jpeg;base64,' . $HistoryDoorbell[$i]{data} . '">';
					}
				}
				else {
					$ImageHtmlCodeDoorbell =  'No image available';
				}
				### Create proper html code for image triggered by motionsensor
				if ($HistoryMotion[$i]{data} ne "") {
					### If element contains an error message
					if ($HistoryMotion[$i]{data} =~ m/Error/) {
						$ImageHtmlCodeMotion = $HistoryMotion[$i]{data};
					}
					### If element does not contain an error message
					else {
						### Create proper html code including popup
						my $ImageHtmlCodeBig =  "<img src=\\'data:image/jpeg;base64," . $HistoryMotion[$i]{data} . "\\'><br><center>" . $HistoryMotion[$i]{timestamp} . "</center>";
						my $PopupfunctionCode = "onclick=\"FW_okDialog(\'" . $ImageHtmlCodeBig . "\') \" ";
						$ImageHtmlCodeMotion    =  '<img ' . $PopupfunctionCode . ' width="190" height="auto" alt="tick" src="data:image/jpeg;base64,' . $HistoryMotion[$i]{data} . '">';
					}
				}
				else {
					$ImageHtmlCodeMotion =  'No image available';
				}			
				
				$htmlCode .=
				'
					<tr>
						<td align="center">' . $ImageHtmlCodeDoorbell . '</td>
						<td align="center">' . $HistoryDoorbell[$i]{timestamp} . '</td>
						<td align="center">' . ($i + 1) . '</td>
						<td align="center">' . $ImageHtmlCodeMotion . '</td>
						<td align="center">' . $HistoryMotion[$i]{timestamp} . '</td>
					</tr>
				';
				### Log Entry for debugging purposes
				#	Log3 $name, 5, $name. " : DoorBird_FW_detailFn - ImageHtmlCodeDoorbell      : " . $ImageHtmlCodeDoorbell;
				#	Log3 $name, 5, $name. " : DoorBird_FW_detailFn - ImageHtmlCodeMotion        : " . $ImageHtmlCodeMotion;
			}
			
			### Finish table
			$htmlCode .=
			'
				</tbody>
			</table>	
			';
			
		}	
	}
	### Log Entry for debugging purposes
	#	Log3 $name, 5, $name. " : DoorBird_FW_detailFn - htmlCode                   : " . $htmlCode;

	# my $infoBtn = "</td><td><a onClick='FW_cmd(FW_root+\"?cmd.$name=get $name all&XHR=1\",function(data){FW_okDialog(data)})'\>$info</a>"
	# <a href=\"#!\" onclick=\"FW_okDialog('Testtitle<br><br>TestDescription')\">Testtitle</a>
	
	return($htmlCode );
}
####END####### Display of html code preceding the "Internals"-section ##########################################END#####

###START###### Define Subfunction for INFO REQUEST ############################################################START####
sub DoorBird_Info_Request($$) {
	my ($hash, $option)	= @_;
	my $name			= $hash->{NAME};
	my $command			= "info.cgi"; 
	my $method			= "GET";
	my $header			= "Accept: application/json";
	
	my $err = " ";
	my $data = " ";
	my $json;
	
	### Obtain data
	($err, $data) = DoorBird_BlockGet($hash, $command, $method, $header);

	### Remove Newlines for better log entries
	my $ShowData = $data;
	$ShowData =~ s/[\t]//g;
	$ShowData =~ s/[\r]//g;
	$ShowData =~ s/[\n]//g;

	
	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Info_Request - err                       : " . $err      if(defined($err));
	Log3 $name, 5, $name. " : DoorBird_Info_Request - data                      : " . $ShowData if(defined($ShowData));
	
	### If no error has been handed back
	if ($err eq "") {
		### If the option is asking for the JSON string
		if (defined($option) && ($option =~ /JSON/i)) {
			return $data;		
		}
		### If the option is asking for nothing special
		else {
			### Check if json can be parsed into hash	
			eval 
			{
				$json = decode_json(encode_utf8($data));
				1;
			}
			or do 
			{
				### Log Entry for debugging purposes
				Log3 $name, 3, $name. " : DoorBird_Info_Request - Data cannot parsed JSON   : Info_Request";
				return $name. " : DoorBird_Info_Request - Data cannot be parsed by JSON for Info_Request";
			};
			
			my $VersionContent = $json-> {BHA}{VERSION}[0];
			
			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_Info_Request - json                      : " . $json;
			
			### Initiate Bulk Update
			readingsBeginUpdate($hash);

			foreach my $key (keys %{$VersionContent}) {

				### If the entry are information about connected relays
				if ( $key eq "RELAYS") {
				
					### Save adresses of relays into hash
					@{$hash->{helper}{RelayAdresses}} = @{$VersionContent -> {$key}};

					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_Info_Request - No of connected relays    : " . @{$VersionContent -> {$key}};
					Log3 $name, 5, $name. " : DoorBird_Info_Request - Adresses of relays        : " . join(",", @{$VersionContent -> {$key}});
					Log3 $name, 5, $name. " : DoorBird_Info_Request - {helper}{RelayAdresses}   : " . join(",", @{$hash->{helper}{RelayAdresses}});
					
					### Delete all Readings for Relay-Addresses
					readingsDelete($hash, "RelayAddr_.*");
					
					### For all registred relays do
					my $RelayNumber =0;
					foreach my $RelayAddress (@{$VersionContent -> {$key}}) {
					
						$RelayNumber++;

						### Log Entry for debugging purposes
						Log3 $name, 5, $name. " : DoorBird_Info_Request - Adress of " . sprintf("%15s %-s", "Relay_" . sprintf("%02d", $RelayNumber), ": " . $RelayAddress);
						
						### Update Reading
						readingsBulkUpdate($hash, "RelayAddr_" . sprintf("%02d", $RelayNumber), $RelayAddress);
					}
				}
				### If the entry has the information about the device type
				elsif ( $key eq "DEVICE-TYPE") {
				
					### If the Device Type is not containing type numbers which have no camera installed - Currently only "DoorBird D301A - Door Intercom IP Upgrade"
					if ($VersionContent -> {$key} !~ m/301/) {
						### Set Information about Camera installed to true
						$hash->{helper}{CameraInstalled} = true;
					}
			
					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_Info_Request - Content of" . sprintf("%15s %-s", $key, ": " . $VersionContent -> {$key});

					### Update Reading
					readingsBulkUpdate($hash, $key, $VersionContent -> {$key} );
				}
				### For all other entries
				else {
					
					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_Info_Request - Content of" . sprintf("%15s %-s", $key, ": " . $VersionContent -> {$key});

					### Update Reading
					readingsBulkUpdate($hash, $key, $VersionContent -> {$key} );
				}
			}
			### Update Reading for Firmware-Status
			readingsBulkUpdate($hash, "Firmware-Status", "up-to-date");

			### Update SessionId
			DoorBird_RenewSessionID($hash);

			### Execute Readings Bulk Update
			readingsEndUpdate($hash, 1);

			### Download SIP Status Request
			DoorBird_SipStatus_Request($hash,"");

			### Check for Firmware-Updates
			DoorBird_FirmwareStatus($hash);
			
			return "Readings have been updated!\n";
		}
	}
	### If error has been handed back
	else {
		$err =~ s/^[^ ]*//;
		return "ERROR!\nError Code:" . $err;
	}
}
####END####### Define Subfunction for INFO REQUEST #############################################################END#####

###START###### Firmware-Update Status for DorBird unit ########################################################START####
sub DoorBird_FirmwareStatus($) {
	my ($hash) = @_;

	### Obtain values from hash
    my $name = $hash->{NAME};

	### Create Timestamp
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
	my $TimeStamp = sprintf ( "%04d-%02d-%02d %02d:%02d:%02d",$year+1900, $mon+1, $mday, $hour, $min, $sec);
	
	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_FirmwareStatus - Checking firmware status on doorbird page";
	
	my $FirmwareVersionUnit = ReadingsVal($name, "FIRMWARE", 0);

	### Download website of changelocks
	my $html = GetFileFromURL("https://www.doorbird.com/changelog");
	
	### Get the latest firmware number
	my $result;
	if ($html =~ /(?<=Firmware version )(.*)(?=\n=====)/) {
		$result = $1;
	}

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_FirmwareStatus - result                  : " . $result;
	
	### If the latest Firmware is installed
	if (int($FirmwareVersionUnit) == int($result)) {
		### Update Reading for Firmware-Status
		readingsSingleUpdate($hash, "Firmware-Status", "up-to-date", 1);	
		
		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DoorBird_FirmwareStatus - Latest firmware is installed!";
		
	}
	### If the latest Firmware is NOT installed
	elsif (int($FirmwareVersionUnit) < int($result)) {
		### Update Reading for Firmware-Status
		readingsSingleUpdate($hash, "Firmware-Status", "Firmware update required!", 1);	
		
		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DoorBird_FirmwareStatus - DoorBird requires firmware update!";
	}	
	### Something went wrong
	else {
		### Update Reading for Firmware-Status
		readingsSingleUpdate($hash, "Firmware-Status", "unknown", 1);
		
		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DoorBird_FirmwareStatus - An error occured!";
	}
	
	return;
}
####END####### Firmware-Update Status for DorBird unit #########################################################END#####

###START###### Define Subfunction for LIVE VIDEO REQUEST ######################################################START####
sub DoorBird_Live_Video($$) {
	my ($hash, $option)	= @_;

	### Obtain values from hash
	my $name			= $hash->{NAME};

	my $url 			= $hash->{helper}{URL};


	### Create complete command URL for DoorBird depending on whether SessionIdSecurity has been enabled (>0) or disabled (=0)
	my $UrlPrefix 		= "http://" . $url . "/bha-api/";
	my $UrlPostfix;
	if ($hash->{helper}{SessionIdSec} > 0) {
		$UrlPostfix 	= "?sessionid=" . $hash->{helper}{SessionId};
	}
	else {
		my $username 	= DoorBird_credential_decrypt($hash->{helper}{".USER"});
		my $password	= DoorBird_credential_decrypt($hash->{helper}{".PASSWORD"});
		$UrlPostfix 	= "?http-user=". $username . "&http-password=" . $password;
	}
	my $VideoURL 		= $UrlPrefix . "video.cgi" . $UrlPostfix;

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Live_Video - VideoURL                    : " . $VideoURL ;
	Log3 $name, 5, $name. " : DoorBird_Live_Video - VideoURL                    : Created";

	### If VideoStreaming shall be switched ON
	if ($option eq "on") {
		
		### Update Reading
		readingsSingleUpdate($hash, ".VideoURL", $VideoURL, 1);
		
		### Refresh Browser Window
		FW_directNotify("#FHEMWEB:$FW_wname", "location.reload()", "") if defined($FW_wname);
	}
	### If VideoStreaming shall be switched OFF
	elsif ($option eq "off") {
		### Update Reading
		readingsSingleUpdate($hash, ".VideoURL", "", 1);

		### Refresh Browser Window
		FW_directNotify("#FHEMWEB:$FW_wname", "location.reload()", "") if defined($FW_wname);
		
	}
	### If wrong parameter has been transfered
	else
	{
		### Do nothing - Just return
		return("ERROR!\nWrong Parameter used");
	}
	return
}
####END####### Define Subfunction for LIVE VIDEO REQUEST #######################################################END#####

###START###### Define Subfunction for LIVE AUDIO REQUEST ######################################################START####
sub DoorBird_Live_Audio($$) {
	my ($hash, $option)	= @_;

	### Obtain values from hash
	my $name			= $hash->{NAME};
	my $url 			= $hash->{helper}{URL};
	
	### Create complete command URL for DoorBird depending on whether SessionIdSecurity has been enabled (>0) or disabled (=0)
	my $UrlPrefix 		= "http://" . $url . "/bha-api/";
	my $UrlPostfix;
	if ($hash->{helper}{SessionIdSec} > 0) {
		$UrlPostfix 	= "?sessionid=" . $hash->{helper}{SessionId};
	}
	else {
		my $username 	= DoorBird_credential_decrypt($hash->{helper}{".USER"});
		my $password	= DoorBird_credential_decrypt($hash->{helper}{".PASSWORD"});
		$UrlPostfix 	= "?http-user=". $username . "&http-password=" . $password;
	}
	my $AudioURL 		= $UrlPrefix . "audio-receive.cgi" . $UrlPostfix;

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Live_Audio - AudioURL                    : " . $AudioURL ;

	### If AudioStreaming shall be switched ON
	if ($option eq "on") {
		
		### Update Reading
		readingsSingleUpdate($hash, ".AudioURL", $AudioURL, 1);
		
		### Refresh Browser Window
		FW_directNotify("#FHEMWEB:$FW_wname", "location.reload()", "") if defined($FW_wname);
	}
	### If AudioStreaming shall be switched OFF
	elsif ($option eq "off") {
		### Update Reading
		readingsSingleUpdate($hash, ".AudioURL", "", 1);

		### Refresh Browser Window		
		FW_directNotify("#FHEMWEB:$FW_wname", "location.reload()", "") if defined($FW_wname);
	}
	### If wrong parameter has been transfered
	else
	{
		### Do nothing - Just return
		return("ERROR!\nWrong Parameter used");
	}
	return
}
####END####### Define Subfunction for LIVE VIDEO REQUEST #######################################################END#####

###START###### Define Subfunction for LIVE IMAGE REQUEST ######################################################START####
sub DoorBird_Image_Request($$) {
	my ($hash, $option)	= @_;

	### Obtain values from hash
	my $name				= $hash->{NAME};
	my $username 			= DoorBird_credential_decrypt($hash->{helper}{".USER"});
	my $password			= DoorBird_credential_decrypt($hash->{helper}{".PASSWORD"});
	my $url 				= $hash->{helper}{URL};
	my $command				= "image.cgi";
	my $method				= "GET";
	my $header				= "Accept: application/json";
	my $err					= " ";
	my $data				= " ";
	my $json				= " ";
	my $ImageFileName		= " ";
	
	### Create complete command URL for DoorBird
	my $UrlPrefix 		= "https://" . $url . "/bha-api/";
	my $UrlPostfix 		= "?http-user=". $username . "&http-password=" . $password;
	my $ImageURL 		= $UrlPrefix . $command . $UrlPostfix;

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Image_Request _____________________________________________________________";
#	Log3 $name, 5, $name. " : DoorBird_Image_Request - ImageURL                 : " . $ImageURL ;

	### Update Reading
	readingsSingleUpdate($hash, ".ImageURL", $ImageURL, 1);
		
	### Get Image Data
	($err, $data) = DoorBird_BlockGet($hash, $command, $method, $header);

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Image_Request - err                      : " . $err;
#	Log3 $name, 5, $name. " : DoorBird_Image_Request - data                     : " . $data;

	
	### Encode jpeg data into base64 data and remove lose newlines
    my $ImageData =  MIME::Base64::encode($data);
       $ImageData =~ s{\n}{}g;
	
	### Create Timestamp
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
	my $ImageTimeStamp		= sprintf ( "%04d-%02d-%02d %02d:%02d:%02d",$year+1900, $mon+1, $mday, $hour, $min, $sec);
	my $ImageFileTimeStamp	= sprintf ( "%04d%02d%02d-%02d%02d%02d"    ,$year+1900, $mon+1, $mday, $hour, $min, $sec);

	### Save picture and timestamp into hash
	$hash->{helper}{Images}{Individual}{Data}		= $ImageData;
	$hash->{helper}{Images}{Individual}{Timestamp} 	= $ImageTimeStamp;

	### Refresh Browser Window
	FW_directNotify("#FHEMWEB:$FW_wname", "location.reload()", "") if defined($FW_wname);

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Image_Request - hash - ImageFileDir      : " . $hash->{helper}{ImageFileDir};

	### If pictures supposed to be saved as files
	if ($hash->{helper}{ImageFileDir} ne "0") {

		### Get current working directory
		my $cwd = getcwd();

		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DoorBird_Image_Request - working directory        : " . $cwd;


		### If the path is given as UNIX file system format
		if ($cwd =~ /\//) {
			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_Image_Request - file system format       : LINUX";

			### Find out whether it is an absolute path or an relative one (leading "/")
			if ($hash->{helper}{ImageFileDir} =~ /^\//) {
				$ImageFileName = $hash->{helper}{ImageFileDir};
			}
			else {
				$ImageFileName = $cwd . "/" . $hash->{helper}{ImageFileDir};						
			}

			### Check whether the last "/" at the end of the path has been given otherwise add it an create complete path
			if ($hash->{helper}{ImageFileDir} =~ /\/\z/) {
				$ImageFileName .=       $ImageFileTimeStamp . "_snapshot.jpg";
			}
			else {
				$ImageFileName .= "/" . $ImageFileTimeStamp . "_snapshot.jpg";
			}
		}

		### If the path is given as Windows file system format
		if ($hash->{helper}{ImageFileDir} =~ /\\/) {
			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_Image_Request - file system format       : WINDOWS";

			### Find out whether it is an absolute path or an relative one (containing ":\")
			if ($hash->{helper}{ImageFileDir} != /^.:\//) {
				$ImageFileName = $cwd . $hash->{helper}{ImageFileDir};
			}
			else {
				$ImageFileName = $hash->{helper}{ImageFileDir};						
			}

			### Check whether the last "/" at the end of the path has been given otherwise add it an create complete path
			if ($hash->{helper}{ImageFileDir} =~ /\\\z/) {
				$ImageFileName .=       $ImageFileTimeStamp . "_snapshot.jpg";
			}
			else {
				$ImageFileName .= "\\" . $ImageFileTimeStamp . "_snapshot.jpg";
			}
		}
		
		### Save filename of last snapshot into hash
		$hash->{helper}{Images}{LastSnapshotPath} = $ImageFileName;
		
		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DoorBird_Image_Request - ImageFileName            : " . $ImageFileName;

		### Open file or write error message in log
		open my $fh, ">", $ImageFileName or do {
			### Log Entry 
			Log3 $name, 2, $name. " : DoorBird_Image_Request -  open file error         : " . $! . " - ". $ImageFileName;
		};
		
		### Write the base64 decoded data in file
		print $fh decode_base64($ImageData) if defined($fh);
		
		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DoorBird_Image_Request - write file               : Successfully written " . $ImageFileName;
		
		### Close file or write error message in log
		close $fh or do {
			### Log Entry 
			Log3 $name, 2, $name. " : DoorBird_Image_Request - close file error          : " . $! . " - ". $ImageFileName;
		}
	}
	
	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Image_Request - ImageData size           : " . length($ImageData);
	Log3 $name, 5, $name. " : DoorBird_Image_Request - ImageTimeStamp           : " . $ImageTimeStamp;
	
	return;
}
####END####### Define Subfunction for LIVE IMAGE REQUEST #######################################################END#####

###START###### Define Subfunction for LAST EVENT IMAGE REQUEST ################################################START####
sub DoorBird_LastEvent_Image($$$) {
	my ($param, $err, $data) = @_;
    my $hash = $param->{hash};

	### Obtain values from hash
    my $name         = $hash->{NAME};
	my $event        = $param->{event};
	my $timestamp	 = $param->{timestamp};
	my $ReadingImage;

	if ($event =~ m/doorbell/ ){
		$ReadingImage 			= "doorbell_snapshot_" . sprintf("%03d", $param->{doorbellNo});
	}
	elsif ($event =~ m/motion/ ){
		$ReadingImage 			= "motion_snapshot";
	}
	elsif ($event =~ m/keypad/ ){
		$ReadingImage 			= "keypad_snapshot";
	}
	else {
		### Create Log entry
		Log3 $name, 2, $name. " : DoorBird_LastEvent_Image - Unknown event. Breaking up";
		
		### Exit sub
		return
	}

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_LastEvent_Image ___________________________________________________________";
	Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - err                    : " . $err           if (defined($err  ));
	Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - length data            : " . length($data)  if (defined($data ));
	#Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - param                  : " . join("\n", @{[%{$param}]}) if (defined($param));

	### If error message available
	if ($err ne "") {
		### Create Log entry
		Log3 $name, 3, $name. " : DoorBird_LastEvent_Image - Error                  : " . $err        if (defined($err  ));
		
		### Write Last Image into reading
		readingsSingleUpdate($hash, $ReadingImage, "No image data", 1);
	}
	### if no error message available
	else {
		### If any image data available
		if (defined $data) {

			### Predefine Image Data and Image-hash and hash - reference		
			my $ImageData;
			my $ImageTimeStamp;
			my $ImageFileTimeStamp;
			my $ImageFileName;
			my %ImageDataHash;
			my $ref_ImageDataHash = \%ImageDataHash;
			
			### If http response code is 200 = OK
			if ($param->{code} == 200) {
				### Encode jpeg data into base64 data and remove lose newlines
				$ImageData =  MIME::Base64::encode($data);
				$ImageData =~ s{\n}{}g;

				### Create Timestamp
				my $httpHeader = $param->{httpheader};
				   $httpHeader =~ s/^[^_]*X-Timestamp: //;
				   $httpHeader =~ s/\n.*//g;

				### If timestamp from history image has NOT been done since the timestamp from the event
				if ((int($timestamp) - int($httpHeader)) > 0){
					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - timestamp from history image has NOT been done since the timestamp from the event.";
					Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - Image timestamp        : " . $httpHeader;
					Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - Event timestamp        : " . $timestamp;
					Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - dt                     : " . (int($timestamp) - int($httpHeader));


					### If timestamp from the event is NOT older than WaitForHistory from current time => Try again
					if ((time - int($timestamp)) <= $hash->{helper}{WaitForHistory}){

						### Log Entry for debugging purposes
						Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - timestamp of event is not older than Attribute WaitForHistory: Still time to try again";
						Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - Event timestamp        : " . $timestamp;
						Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - current timestamp      : " . time;
						Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - Attr WaitForHistory    : " . $hash->{helper}{WaitForHistory};
						Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - dt                     : " . int(time - int($timestamp));

						### Try again: Initiate communication and close
						HttpUtils_NonblockingGet($param);
							
						### Exit routine
						return;
					}
					else {
						### Log Entry for debugging purposes
						Log3 $name, 2, $name. " : DoorBird_LastEvent_Image - timestamp of event is older than than Attribute WaitForHistory: Proceeding without waiting any longer...";
						Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - Event timestamp        : " . $timestamp;
						Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - current timestamp      : " . time;
						Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - Attr WaitForHistory    : " . $hash->{helper}{WaitForHistory};
						Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - dt                     : " . int(time - int($timestamp));
						
						### Write Last Image into reading
						readingsSingleUpdate($hash, $ReadingImage, "No image data", 1);
					}
				}
				### If timestamp from history picture has been done since the timestamp from the event			
				else {
					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - timestamp from history image has been done since the timestamp from the event.";
					Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - Image timestamp        : " . $httpHeader;
					Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - Event timestamp        : " . $timestamp;
					Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - dt                     : " . (int($timestamp) - int($httpHeader));
					
					my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime($httpHeader);
					$ImageTimeStamp	    = sprintf ( "%04d-%02d-%02d %02d:%02d:%02d",$year+1900, $mon+1, $mday, $hour, $min, $sec);
					$ImageFileTimeStamp	= sprintf ( "%04d%02d%02d-%02d%02d%02d"    ,$year+1900, $mon+1, $mday, $hour, $min, $sec);

					### Save picture and timestamp into hash
					$hash->{helper}{Images}{Individual}{Data}		= $ImageData;
					$hash->{helper}{Images}{Individual}{Timestamp} 	= $ImageTimeStamp;
					
					### Refresh Browser Window		
					FW_directNotify("#FHEMWEB:$FW_wname", "location.reload()", "") if defined($FW_wname);

					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - hash - ImageFileDir    : " . $hash->{helper}{ImageFileDir};

					### If pictures supposed to be saved as files
					if ($hash->{helper}{ImageFileDir} ne "0") {

						### Get current working directory
						my $cwd = getcwd();

						### Log Entry for debugging purposes
						Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - working directory      : " . $cwd;

						### If the path is given as UNIX file system format
						if ($cwd =~ /\//) {
							### Log Entry for debugging purposes
							Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - file system format     : LINUX";

							### Find out whether it is an absolute path or an relative one (leading "/")
							if ($hash->{helper}{ImageFileDir} =~ /^\//) {
								$ImageFileName = $hash->{helper}{ImageFileDir};
							}
							else {
								$ImageFileName = $cwd . "/" . $hash->{helper}{ImageFileDir};						
							}

							### Check whether the last "/" at the end of the path has been given otherwise add it an create complete path
							if ($hash->{helper}{ImageFileDir} =~ /\/\z/) {
								$ImageFileName .=       $ImageFileTimeStamp . "_" . $event . ".jpg";
							}
							else {
								$ImageFileName .= "/" . $ImageFileTimeStamp . "_" . $event . ".jpg";
							}
						}

						### If the path is given as Windows file system format
						if ($hash->{helper}{ImageFileDir} =~ /\\/) {
							### Log Entry for debugging purposes
							Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - file system format     : WINDOWS";

							### Find out whether it is an absolute path or an relative one (containing ":\")
							if ($hash->{helper}{ImageFileDir} != /^.:\//) {
								$ImageFileName = $cwd . $hash->{helper}{ImageFileDir};
							}
							else {
								$ImageFileName = $hash->{helper}{ImageFileDir};						
							}

							### Check whether the last "/" at the end of the path has been given otherwise add it an create complete path
							if ($hash->{helper}{ImageFileDir} =~ /\\\z/) {
								$ImageFileName .=       $ImageFileTimeStamp . "_" . $event . ".jpg";
							}
							else {
								$ImageFileName .= "\\" . $ImageFileTimeStamp . "_" . $event . ".jpg";
							}
						}
						
						### Log Entry for debugging purposes
						Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - ImageFileName          : " . $ImageFileName;

						### Open file or write error message in log
						open my $fh, ">", $ImageFileName or do {
							### Log Entry 
							Log3 $name, 2, $name. " : DoorBird_LastEvent_Image -  open file error       : " . $! . " - ". $ImageFileName;
						};
						
						### Write the base64 decoded data in file
						print $fh decode_base64($ImageData) if defined($fh);
						
						### Log Entry for debugging purposes
						Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - write file             : Successfully written " . $ImageFileName;
						
						### Close file or write error message in log
						close $fh or do {
							### Log Entry 
							Log3 $name, 2, $name. " : DoorBird_LastEvent_Image - close file error       : " . $! . " - ". $ImageFileName;
						};
					
						### Write Last Image into reading
						readingsSingleUpdate($hash, $ReadingImage, $ImageFileName, 1);
					}
					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - ImageData - event      : " . length($ImageData);

				}
				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - Type of event          : " . $event;
			}
			### If http response code is 204 = No permission to download the event history
			elsif ($param->{code} == 204) {
				### Create Log entry
				Log3 $name, 3, $name. " : DoorBird_LastEvent_Image - Error 204              : User not authorized to download event history";
				
				### Create Error message
				$ImageData = "Error 204: The user has no permission to download the event history.";
				$ImageTimeStamp =" ";
				
				### Write Last Image into reading
				readingsSingleUpdate($hash, $ReadingImage, "No image data", 1);
			}
			### If http response code is 404 = No picture available to download the event history
			elsif ($param->{code} == 404) {
				### Create Log entry
				Log3 $name, 5, $name. " : DoorBird_LastEvent_Image - Error 404              : No picture available to download event history. Check settings in DoorBird APP.";
				
				### Create Error message
				$ImageData = "Error 404: No picture available to download in the event history.";
				$ImageTimeStamp =" ";
				
				### Write Last Image into reading
				readingsSingleUpdate($hash, $ReadingImage, "No image data", 1);
			}
			### If http response code is none of one above
			else {
				### Create Log entry
				Log3 $name, 3, $name. " : DoorBird_LastEvent_Image - Unknown http response code    : " . $param->{code};
			
				### Create Error message
				$ImageData = "Error : " . $param->{code};
				$ImageTimeStamp =" ";
				
				### Write Last Image into reading
				readingsSingleUpdate($hash, $ReadingImage, "No image data", 1);
			}
		}
		else {
			### Write Last Image into reading
			readingsSingleUpdate($hash, $ReadingImage, "No image data", 1);
		}
	}

	return;
}
####END####### Define Subfunction for LAST EVENT IMAGE REQUEST #################################################END#####

###START###### Define Subfunction for OPEN DOOR ###############################################################START####
sub DoorBird_Open_Door($$) {
	my ($hash, $option)	= @_;
	my $name			= $hash->{NAME};
	my $command			= "open-door.cgi?r=" . $option; 
	my $method			= "GET";
	my $header			= "Accept: application/json";
	my $username 		= DoorBird_credential_decrypt($hash->{helper}{".USER"});
	my $err;
	my $data;
	my $json;

	### Activate Relay
	($err, $data) = DoorBird_BlockGet($hash, $command, $method, $header);

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Open_Door - err                          : " . $err;
	Log3 $name, 5, $name. " : DoorBird_Open_Door - data                         : " . $data;
	
	### If no error message is available
	if ($err eq "") {

		### Check if json can be parsed into hash
		eval {
			$json = decode_json(encode_utf8($data));
			1;
		}
		or do {
			### Log Entry for debugging purposes
			Log3 $name, 3, $name. " : DoorBird_Open_Door - Data cannot be parsed by JSON for: Open_Door";
			return $name. " : DoorBird_Open_Door - Data cannot be parsed by JSON for Open_Door";
		};
		
		### Create return messages and log entries based on error codes returned
		if ($json->{BHA}{RETURNCODE} eq "1") {
			### Log Entry
			Log3 $name, 3, $name. " : DoorBird_Open_Door - Door ". $option . " successfully triggered.";
			
			### Create popup message
			return "Door ". $option . " successful triggered.";
		}
		elsif ($json->{BHA}{RETURNCODE} eq "204") {
			### Log Entry
			Log3 $name, 3, $name. " : DoorBird_Open_Door - Error 204: The user " . $username . "has no “watch-always” - permission to open the door.";
			
			### Create popup message
			return "Error 204: The user " . $username . "has no “watch-always” - permission to open the door.";
		}
		else {
			### Log Entry
			Log3 $name, 3, $name. " : DoorBird_Light_On - ERROR! - Return Code:" . $json->{BHA}{RETURNCODE};
			return "ERROR!\nReturn Code:" . $json->{BHA}{RETURNCODE};	
		}
	}
	### If error message is available
	else {
		### Log Entry
		Log3 $name, 3, $name. " : DoorBird_Light_On - ERROR! - Error Code:" . $err;
		
		### Create error message
		$err =~ s/^[^ ]*//;
		return "ERROR!\nError Code:" . $err;	
	}
}
####END####### Define Subfunction for OPEN DOOR ################################################################END#####

###START###### Define Subfunction for LIGHT ON ################################################################START####
sub DoorBird_Light_On($$) {
	my ($hash, $option)	= @_;
	my $name			= $hash->{NAME};
	my $command			= "light-on.cgi"; 
	my $method			= "GET";
	my $header			= "Accept: application/json";
	my $username 		= DoorBird_credential_decrypt($hash->{helper}{".USER"});
	my $err;
	my $data;
	my $json;

	### Activate Relay
	($err, $data) = DoorBird_BlockGet($hash, $command, $method, $header);

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Light_On - err                          : " . $err;
	Log3 $name, 5, $name. " : DoorBird_Light_On - data                         : " . $data;
	
	### If no error message is available
	if ($err eq "") {
		### Check if json can be parsed into hash
		eval {
			$json = decode_json(encode_utf8($data));
			1;
		}
		or do {
			### Log Entry for debugging purposes
			Log3 $name, 3, $name. " : DoorBird_Light_On - Data cannot be parsed by JSON for: Light_On";
			return $name. " : DoorBird_Light_On - Data cannot be parsed by JSON for Light_On";
		};
		
		### Create return messages and log entries based on error codes returned
		if ($json->{BHA}{RETURNCODE} eq "1") {
			### Log Entry
			Log3 $name, 3, $name. " : DoorBird_Light_On - Light successfully triggered.";
			
			### Create popup message
			return "Light successful triggered.";
		}
		elsif ($json->{BHA}{RETURNCODE} eq "204") {
			### Log Entry
			Log3 $name, 3, $name. " : DoorBird_Light_On - Error 204: The user " . $username . "has no “watch-always” - permission to switch the light ON.";
			
			### Create popup message
			return "Error 204: The user " . $username . "has no “watch-always” - permission to switch the light ON.";
		}
		else {
			### Log Entry
			Log3 $name, 3, $name. " : DoorBird_Light_On - ERROR! - Return Code:" . $json->{BHA}{RETURNCODE};
			return "ERROR!\nReturn Code:" . $json->{BHA}{RETURNCODE};	
		}
	}
	### If error message is available
	else {
		### Log Entry
		Log3 $name, 3, $name. " : DoorBird_Light_On - ERROR! - Error Code:" . $err;
		
		### Create error message
		$err =~ s/^[^ ]*//;
		return "ERROR!\nError Code:" . $err;	
	}
}
####END####### Define Subfunction for LIGHT ON #################################################################END#####

###START###### Define Subfunction for LIVE AUDIO TRANSMIT #####################################################START####
sub DoorBird_Transmit_Audio($$) {
	my ($hash, $option)	= @_;
	
	### Obtain values from hash
	my $name				= $hash->{NAME};
	my $Username 			= DoorBird_credential_decrypt($hash->{helper}{".USER"});
	my $Password			= DoorBird_credential_decrypt($hash->{helper}{".PASSWORD"});
	my $Url 				= $hash->{helper}{URL};
	my $Sox					= $hash->{helper}{SOX};
	my $SipDevice			= $hash->{helper}{SipDevice};
	my $SipNumber			= $hash->{helper}{SipNumber};
	my $AudioDataPathOrig	= $option;
	my @ListSipDevices		= devspec2array("TYPE=SIP");
	my $err;
	
	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Transmit_Audio  - ---------------------------------------------------------------";
	
	### If device of TYPE = SIP exists
	if (@ListSipDevices > 0) {
		### If file exists
		if (-e $AudioDataPathOrig) {
			### Create new filepath from old filepath
			my $AudioDataNew;
			my $AudioDataSizeNew;
			my $AudioDataPathNew  = $AudioDataPathOrig;
			   $AudioDataPathNew  =~ s/\..*//;
			my $AudioDataPathTemp = $AudioDataPathNew . "_tmp.wav";
			   $AudioDataPathNew .= ".ulaw";

			### Delete future new file and temporary file if exist
			unlink($AudioDataPathTemp);
			unlink($AudioDataPathNew);
			
			### Create Sox - command
			my $SoxCmd = $Sox . " -V " . $AudioDataPathOrig . " -r 8000 -b 8 -c 1 -e u-law " . $AudioDataPathTemp;
			
			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_Transmit_Audio - Original Path exists    : " . $AudioDataPathOrig;
			Log3 $name, 5, $name. " : DoorBird_Transmit_Audio - Temp Path created       : " . $AudioDataPathTemp;
			Log3 $name, 5, $name. " : DoorBird_Transmit_Audio - New  Path created       : " . $AudioDataPathNew;
			Log3 $name, 5, $name. " : DoorBird_Transmit_Audio - Sox System-Command      : " . $SoxCmd;
			Log3 $name, 5, $name. " : DoorBird_Transmit_Audio - SipDeviceAttribute      : " . $SipDevice;
			Log3 $name, 5, $name. " : DoorBird_Transmit_Audio - SipNumber               : " . $SipNumber;
			Log3 $name, 5, $name. " : DoorBird_Transmit_Audio - ListSipDevices          : " . Dumper(@ListSipDevices);
				
			### Convert file
			system ($SoxCmd);

			### Rename temporary file in .ulaw
			$err = rename($AudioDataPathTemp, $AudioDataPathNew);
			
			### Get new filesize
			$AudioDataSizeNew = -s $AudioDataPathNew;

			### Log Entry for debugging purposes		
			Log3 $name, 5, $name. " : DoorBird_Transmit_Audio - New Filesize            : " . $AudioDataSizeNew;
			Log3 $name, 5, $name. " : DoorBird_Transmit_Audio - rename response message : " . $err;
			
			### If the a name for a SIP - TYPE device has been provided as per attribute
			if (defined($SipDevice)) {
				### Log Entry for debugging purposes		
				Log3 $name, 5, $name. " : DoorBird_Transmit_Audio - Attribute for SIP device: " . $SipDevice;
			
				### If SIP device provided in attribute exists
				if (defined($defs{$SipDevice})) {
					### Log Entry for debugging purposes		
					Log3 $name, 5, $name. " : DoorBird_Transmit_Audio - SIP device in Attribute exists";
				}
				### If SIP device provided in attribute does NOT exists
				else {
					### Take the first available SIP device
					$SipDevice= $ListSipDevices[0];

					### Log Entry for debugging purposes		
					Log3 $name, 5, $name. " : DoorBird_Transmit_Audio - SIP device in Attribute does NOT exist";
					Log3 $name, 5, $name. " : DoorBird_Transmit_Audio - SipDevice chosen        : " . $SipDevice;
				}
			}
			### If the a name for a SIP - TYPE device has NOT been provided as per attribute
			else {
				### Take the first available SIP device
				$SipDevice= $ListSipDevices[0];
				
				### Log Entry for debugging purposes		
				Log3 $name, 5, $name. " : DoorBird_Transmit_Audio - SIP device has not been provided in Attribute";
				Log3 $name, 5, $name. " : DoorBird_Transmit_Audio - SipDevice chosen        : " . $SipDevice;
			}
			
			
			### Use SIP device and transfer filepath
			my $FhemCommand = "set " . $SipDevice . " call " . $SipNumber . " 30 " . $AudioDataPathNew;
			fhem($FhemCommand);
			
			return "The audio file: " . $AudioDataPathOrig . " has been passed to the fhem device " . $SipDevice;
		}
		### If Filepath does not exist
		else {
			### Log Entry
			Log3 $name, 3, $name. " : DoorBird_Transmit_Audio - Path doesn't exist      : " . $AudioDataPathOrig;
			Log3 $name, 5, $name. " : DoorBird_Transmit_Audio - ---------------------------------------------------------------";
			return "The audio file: " . $AudioDataPathOrig . " does not exist!"
		}
	}
	### If no device TYPE = SIP exists
	else {
		### Log Entry
		Log3 $name, 3, $name. " : DoorBird_Transmit_Audio - No device with TYPE=SIP exists. Install SIP device first";
		Log3 $name, 5, $name. " : DoorBird_Transmit_Audio - ---------------------------------------------------------------";
		return "No device with TYPE=SIP exists. Install SIP device first"
	}
}
####END####### Define Subfunction for LIVE AUDIO TRANSMIT ######################################################END#####

###START###### Define Subfunction for HISTORY IMAGE REQUEST ###################################################START####
### https://wiki.fhem.de/wiki/HttpUtils#HttpUtils_NonblockingGet
sub DoorBird_History_Request($$) {
	my ($hash, $option)	= @_;

	### Obtain values from hash
	my $Name			= $hash->{NAME};
	my $Username 		= DoorBird_credential_decrypt($hash->{helper}{".USER"});
	my $Password		= DoorBird_credential_decrypt($hash->{helper}{".PASSWORD"});
	my $PollingTimeout  = $hash->{helper}{PollingTimeout};
	my $url 			= $hash->{helper}{URL};
	my $Method			= "GET";
	my $Header			= "Accept: application/json";
	my $err;
	my $data;
	my $UrlPostfix;
	my $CommandURL;
	
	### Create Timestamp
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
	my $ImageTimeStamp	    = sprintf ( "%04d-%02d-%02d %02d:%02d:%02d",$year+1900, $mon+1, $mday, $hour, $min, $sec);

	
	### Create first part command URL for DoorBird
	my $UrlPrefix 		= "https://" . $url . "/bha-api/";

	### If the Itereation is started for the first time = new polling
	if ($hash->{helper}{HistoryDownloadCount} == 0) {
		### Delete arrays of pictures
		@{$hash->{helper}{Images}{History}{doorbell}}		= ();
		@{$hash->{helper}{Images}{History}{motionsensor}}	= ();
		  $hash->{helper}{HistoryTime}						= $ImageTimeStamp;
		  $hash->{helper}{HistoryDownloadActive} 			= true;
	}
	
	### Define STATE message
	my $CountDown = $hash->{helper}{MaxHistory}*2 - $hash->{helper}{HistoryDownloadCount};
	
	### Update STATE of device
	readingsSingleUpdate($hash, "state", "Downloading history: " . $CountDown, 1);

	### Create the URL Index which is identical every 2nd: 1 1 2 2 3 3 4 4 5 5 6 6
	my $UrlIndex=int(int($hash->{helper}{HistoryDownloadCount})/int(2))+1;
	
	### As long the maximum ammount of Images for history events is not reached
	if ($UrlIndex <= $hash->{helper}{MaxHistory}) {
		### If the counter is even, download an image based on the doorbell event
		if (0 == $hash->{helper}{HistoryDownloadCount} % 2) {
			### Create Parameter for CommandURL for doorbell events
			$UrlPostfix = "history.cgi?event=doorbell&index=" . $UrlIndex;
		} 
		### If the counter is odd, download an image based on the motion sensor event
		else {
			### Create Parameter for CommandURL for motionsensor events
			$UrlPostfix = "history.cgi?event=motionsensor&index=" . $UrlIndex;
		}
	}
	### If the requested maximum number of Images for history events is reached
	else {
		### Reset helper
		$hash->{helper}{HistoryDownloadActive} = false;
		$hash->{helper}{HistoryDownloadCount}  = 0;
		
		### Update STATE of device
		readingsSingleUpdate($hash, "state", "connected", 1);
		
		### Refresh Browser Window		
		FW_directNotify("#FHEMWEB:$FW_wname", "location.reload()", "") if defined($FW_wname);
		
		### Return since Routine is finished or wrong parameter has been transfered.
		return
	}

	### Create complete command URL for DoorBird
	$CommandURL = $UrlPrefix . $UrlPostfix;	
	
	### Define Parameter for Non-BlockingGet
	my $param = {
		url               => $CommandURL,
		timeout           => $PollingTimeout,
		user              => $Username,
		pwd               => $Password,
		hash              => $hash,
		method            => $Method,
		header            => $Header,
		incrementalTimout => 1,
		callback          => \&DoorBird_History_Request_Parse
	};
	
	### Initiate communication and close
	HttpUtils_NonblockingGet($param);

	return;
}

sub DoorBird_History_Request_Parse($) {
	my ($param, $err, $data) = @_;
    my $hash = $param->{hash};

	### Obtain values from hash
    my $name = $hash->{NAME};

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_History_Request ___________________________________________________________";
	Log3 $name, 5, $name. " : DoorBird_History_Request - Download Index         : " . $hash->{helper}{HistoryDownloadCount};
	Log3 $name, 5, $name. " : DoorBird_History_Request - err                    : " . $err           if (defined($err  ));
	Log3 $name, 5, $name. " : DoorBird_History_Request - length data            : " . length($data)  if (defined($data ));
#	Log3 $name, 5, $name. " : DoorBird_History_Request - param                  : " . join("\n", @{[%{$param}]}) if (defined($param));

	
	### If error message available
	if ($err ne "") {
		### Create Log entry
		Log3 $name, 3, $name. " : DoorBird_History_Request - Error                  : " . $err        if (defined($err  ));
	}
	### if no error message available
	else {
		### If any image data available
		if (defined $data) {

			### Predefine Image Data and Image-hash and hash - reference		
			my $ImageData;
			my $ImageTimeStamp;
			my $ImageFileTimeStamp;
			my $ImageFileName;
			my %ImageDataHash;
			my $ref_ImageDataHash = \%ImageDataHash;
			
			### If http response code is 200 = OK
			if ($param->{code} == 200) {
				### Encode jpeg data into base64 data and remove lose newlines
				$ImageData =  MIME::Base64::encode($data);
				$ImageData =~ s{\n}{}g;

				### Create Timestamp
				my $httpHeader = $param->{httpheader};
				   $httpHeader =~ s/^[^_]*X-Timestamp: //;
				   $httpHeader =~ s/\n.*//g;
				my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime($httpHeader);
				$ImageTimeStamp	    = sprintf ( "%04d-%02d-%02d %02d:%02d:%02d",$year+1900, $mon+1, $mday, $hour, $min, $sec);
				$ImageFileTimeStamp	= sprintf ( "%04d%02d%02d-%02d%02d%02d"    ,$year+1900, $mon+1, $mday, $hour, $min, $sec);
			}
			### If http response code is 204 = Nno permission to download the event history
			elsif ($param->{code} == 204) {
				### Create Log entry
				Log3 $name, 3, $name. " : DoorBird_History_Request - Error 204              : User not authorized to download event history";
				
				### Create Error message
				$ImageData = "Error 204: The user has no permission to download the event history.";
				$ImageTimeStamp =" ";
			}
			### If http response code is 404 = No picture available to download the event history
			elsif ($param->{code} == 404) {
				### Create Log entry
				Log3 $name, 5, $name. " : DoorBird_History_Request - Error 404              : No picture available to download event history. Check settings in DoorBird APP.";
				
				### Create Error message
				$ImageData = "Error 404: No picture available to download in the event history.";
				$ImageTimeStamp =" ";
			}
			### If http response code is none of one above
			else {
				### Create Log entry
				Log3 $name, 3, $name. " : DoorBird_History_Request - Unknown http response code    : " . $param->{code};
			
				### Create Error message
				$ImageData = "Error : " . $param->{code};
				$ImageTimeStamp =" ";
			}
			
			### Create the URL Index which is identical every 2nd: 1 1 2 2 3 3 4 4 5 5 6 6
			my $UrlIndex=int(int($hash->{helper}{HistoryDownloadCount})/int(2))+1;
			
			### If the counter is even, download an image based on the doorbell event
			if (0 == $hash->{helper}{HistoryDownloadCount} % 2) {
				my $HistoryDownloadCount = $hash->{helper}{HistoryDownloadCount};
				
				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_History_Request - doorbell - HistoryCount: " . $HistoryDownloadCount;
			
				### Save Image data and timestamp into hash
				$ref_ImageDataHash->{data}      = $ImageData;
				$ref_ImageDataHash->{timestamp} = $ImageTimeStamp;
			
				### Save image hash into array of hashes
				push (@{$hash->{helper}{Images}{History}{doorbell}}, $ref_ImageDataHash);

				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_History_Request - hash - ImageFileDir    : " . $hash->{helper}{ImageFileDir};

				### If pictures supposed to be saved as files
				if ($hash->{helper}{ImageFileDir} ne "0") {

					### Get current working directory
					my $cwd = getcwd();

					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_History_Request - working directory      : " . $cwd;


					### If the path is given as UNIX file system format
					if ($cwd =~ /\//) {
						### Log Entry for debugging purposes
						Log3 $name, 5, $name. " : DoorBird_History_Request - file system format     : LINUX";

						### Find out whether it is an absolute path or an relative one (leading "/")
						if ($hash->{helper}{ImageFileDir} =~ /^\//) {
							$ImageFileName = $hash->{helper}{ImageFileDir};
						}
						else {
							$ImageFileName = $cwd . "/" . $hash->{helper}{ImageFileDir};						
						}

						### Check whether the last "/" at the end of the path has been given otherwise add it an create complete path
						if ($hash->{helper}{ImageFileDir} =~ /\/\z/) {
							$ImageFileName .=       $ImageFileTimeStamp . "_doorbell.jpg";
						}
						else {
							$ImageFileName .= "/" . $ImageFileTimeStamp . "_doorbell.jpg";
						}
					}

					### If the path is given as Windows file system format
					if ($hash->{helper}{ImageFileDir} =~ /\\/) {
						### Log Entry for debugging purposes
						Log3 $name, 5, $name. " : DoorBird_History_Request - file system format     : WINDOWS";

						### Find out whether it is an absolute path or an relative one (containing ":\")
						if ($hash->{helper}{ImageFileDir} != /^.:\//) {
							$ImageFileName = $cwd . $hash->{helper}{ImageFileDir};
						}
						else {
							$ImageFileName = $hash->{helper}{ImageFileDir};						
						}

						### Check whether the last "/" at the end of the path has been given otherwise add it an create complete path
						if ($hash->{helper}{ImageFileDir} =~ /\\\z/) {
							$ImageFileName .=       $ImageFileTimeStamp . "_doorbell.jpg";
						}
						else {
							$ImageFileName .= "\\" . $ImageFileTimeStamp . "_doorbell.jpg";
						}
					}
					
					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_History_Request - ImageFileName          : " . $ImageFileName;

					### Open file or write error message in log
					open my $fh, ">", $ImageFileName or do {
						### Log Entry 
						Log3 $name, 2, $name. " : DoorBird_History_Request -  open file error       : " . $! . " - ". $ImageFileName;
					};
					
					### Write the base64 decoded data in file
					print $fh decode_base64($ImageData) if defined($fh);
					
					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_History_Request - write file             : Successfully written " . $ImageFileName;
					
					### Close file or write error message in log
					close $fh or do {
						### Log Entry 
						Log3 $name, 2, $name. " : DoorBird_History_Request - close file error       : " . $! . " - ". $ImageFileName;
					}
				}
				
				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_History_Request - Index - doorbell       : " . $UrlIndex;
				Log3 $name, 5, $name. " : DoorBird_History_Request - ImageData - doorbell   : " . length($ImageData);
			} 
			### If the counter is odd, download an image based on the motion sensor event
			else {
				my $HistoryDownloadCount = $hash->{helper}{HistoryDownloadCount} - 50;
				
				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_History_Request - motion  - HistoryCount : " . $HistoryDownloadCount;
				
				### Save Image data and timestamp into hash
				$ref_ImageDataHash->{data}      = $ImageData;
				$ref_ImageDataHash->{timestamp} = $ImageTimeStamp;
			
				### Save image hash into array of hashes
				push (@{$hash->{helper}{Images}{History}{motionsensor}}, $ref_ImageDataHash);

				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_History_Request - hash - ImageFileDir    : " . $hash->{helper}{ImageFileDir};

				### If pictures supposed to be saved as files
				if ($hash->{helper}{ImageFileDir} ne "0") {

					### Get current working directory
					my $cwd = getcwd();

					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_History_Request - working directory      : " . $cwd;


					### If the path is given as UNIX file system format
					if ($cwd =~ /\//) {
						### Log Entry for debugging purposes
						Log3 $name, 5, $name. " : DoorBird_History_Request - file system format     : LINUX";

						### Find out whether it is an absolute path or an relative one (leading "/")
						if ($hash->{helper}{ImageFileDir} =~ /^\//) {
							$ImageFileName = $hash->{helper}{ImageFileDir};
						}
						else {
							$ImageFileName = $cwd . "/" . $hash->{helper}{ImageFileDir};						
						}

						### Check whether the last "/" at the end of the path has been given otherwise add it an create complete path
						if ($hash->{helper}{ImageFileDir} =~ /\/\z/) {
							$ImageFileName .=       $ImageFileTimeStamp . "_motionsensor.jpg";
						}
						else {
							$ImageFileName .= "/" . $ImageFileTimeStamp . "_motionsensor.jpg";
						}
					}

					### If the path is given as Windows file system format
					if ($hash->{helper}{ImageFileDir} =~ /\\/) {
						### Log Entry for debugging purposes
						Log3 $name, 5, $name. " : DoorBird_History_Request - file system format     : WINDOWS";

						### Find out whether it is an absolute path or an relative one (containing ":\")
						if ($hash->{helper}{ImageFileDir} != /^.:\//) {
							$ImageFileName = $cwd . $hash->{helper}{ImageFileDir};
						}
						else {
							$ImageFileName = $hash->{helper}{ImageFileDir};						
						}

						### Check whether the last "/" at the end of the path has been given otherwise add it an create complete path
						if ($hash->{helper}{ImageFileDir} =~ /\\\z/) {
							$ImageFileName .=       $ImageFileTimeStamp . "_motionsensor.jpg";
						}
						else {
							$ImageFileName .= "\\" . $ImageFileTimeStamp . "_motionsensor.jpg";
						}
					}
					
					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_History_Request - ImageFileName          : " . $ImageFileName;

					### Open file or write error message in log
					open my $fh, ">", $ImageFileName or do {
						### Log Entry 
						Log3 $name, 2, $name. " : DoorBird_History_Request -  open file error       : " . $! . " - ". $ImageFileName;
					};
					
					### Write the base64 decoded data in file
					print $fh decode_base64($ImageData) if defined($fh);
					
					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_History_Request - write file             : Successfully written " . $ImageFileName;
					
					### Close file or write error message in log
					close $fh or do {
						### Log Entry 
						Log3 $name, 2, $name. " : DoorBird_History_Request - close file error       : " . $! . " - ". $ImageFileName;
					}
				}
			
				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_History_Request - Index - motionsensor   : " . $UrlIndex;
				Log3 $name, 5, $name. " : DoorBird_History_Request - ImageData- motionsensor: " . length($ImageData);
			}
		}		
		### If no image data available
		else {
			### Create second part command URL for DoorBird based on iteration cycle
			if (($hash->{helper}{HistoryDownloadCount} > 0) && $hash->{helper}{HistoryDownloadCount} <= 50) {
				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_History_Request - No Image  doorbell     : " . $hash->{helper}{HistoryDownloadCount};
			}
			elsif (($hash->{helper}{HistoryDownloadCount} > 50) && $hash->{helper}{HistoryDownloadCount} <= 100) {
				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_History_Request - No Image  motionsensor : " . ($hash->{helper}{HistoryDownloadCount} -50);
			}
			else {
				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : DoorBird_History_Request - ERROR! Wrong Index  b) : " . $hash->{helper}{HistoryDownloadCount};
			}
		}
	}
	
	### Increase Download Counter and download the next one
	$hash->{helper}{HistoryDownloadCount}++;
	DoorBird_History_Request($hash, "");
	return
}
####END####### Define Subfunction for HISTORY IMAGE REQUEST ####################################################END#####

###START###### Define Subfunction for LIST FAVOURITES #########################################################START####
sub DoorBird_List_Favorites($$) {
	my ($hash, $option)	= @_;
	my $name			= $hash->{NAME};
	my $command			= "favorites.cgi"; 
	my $method			= "GET";
	my $header			= "Accept: application/json";
	
	my $err = " ";
	my $data = " ";
	my $json;
	
	### Obtain data
	($err, $data) = DoorBird_BlockGet($hash, $command, $method, $header);

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Get - List_Favourites - err                 : " . $err;
	Log3 $name, 5, $name. " : DoorBird_Get - List_Favourites - data                : " . $data;
	
	### If no error has been handed back
	if ($err eq "") {
		### If the option is  asking for the JSON string
		if (defined($option) && ($option =~ /JSON/i)) {
			return $data;		
		}
		### If the option is asking for nothing special
		else {
			### Check if json can be parsed into hash	
			eval 
			{
				$json = decode_json(encode_utf8($data));
				1;
			}
			or do 
			{
				### Log Entry for debugging purposes
				Log3 $name, 3, $name. " : DoorBird_Get - Data cannot be parsed by JSON for  : List_Favourites";
				return $name. " : DoorBird_Get - Data cannot be parsed by JSON for List_Favourites";
			};
			
			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_Get - json                               : " . $json;

			### Delete all Readings for Relay-Addresses
			fhem( "deletereading $name Favorite_.*" );
			
			### Initiate Bulk Update
			readingsBeginUpdate($hash);
			
			### For every chapter in the List of Favourites (e.g. SIP, http)
			foreach my $FavoritChapter (keys %{$json}) {
				### For every item in the List of chapters (e.g. 0, 1, 5 etc.)
				foreach my $FavoritItem (keys %{$json->{$FavoritChapter}}) {
				
					### Create first part of Reading
					my $ReadingName = "Favorite_" . $FavoritChapter . "_" . $FavoritItem;

					### Update Reading
					readingsBulkUpdate($hash, $ReadingName . "_Title", $json->{$FavoritChapter}{$FavoritItem}{title});
					readingsBulkUpdate($hash, $ReadingName . "_Value", $json->{$FavoritChapter}{$FavoritItem}{value});
										
					### Log Entry for debugging purpose
					Log3 $name, 5, $name. " : DoorBird_List_Favorites --------------------------------";
					Log3 $name, 5, $name. " : DoorBird_List_Favorites - Reading                 : " . $ReadingName;
					Log3 $name, 5, $name. " : DoorBird_List_Favorites - _Title                  : " . $json->{$FavoritChapter}{$FavoritItem}{title};
					Log3 $name, 5, $name. " : DoorBird_List_Favorites - _Value                  : " . $json->{$FavoritChapter}{$FavoritItem}{title};
				}
			}
			### Execute Readings Bulk Update
			readingsEndUpdate($hash, 1);		
			return "Readings have been updated!\nPress F5 to refresh Browser.";
		}
	}
	### If error has been handed back
	else {
		$err =~ s/^[^ ]*//;
		return "ERROR!\nError Code:" . $err;
	}
}
####END####### Define Subfunction for LIST FAVOURITES ##########################################################END#####

###START###### Define Subfunction for LIST SCHEDULES ##########################################################START####
sub DoorBird_List_Schedules($$) {
	my ($hash, $option)	= @_;
	my $name			= $hash->{NAME};
	my $command			= "schedule.cgi"; 
	my $method			= "GET";
	my $header			= "Accept: application/json";
	
	my $err = " ";
	my $data = " ";
	my $json;
	
	### Obtain data
	($err, $data) = DoorBird_BlockGet($hash, $command, $method, $header);

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Get - List_Schedules - err                  : " . $err;
	Log3 $name, 5, $name. " : DoorBird_Get - List_Schedules - data                 : " . $data;
	
	### If no error has been handed back
	if ($err eq "") {
		### If the option is  asking for the JSON string
		if (defined($option) && ($option =~ /JSON/i)) {
			return $data;		
		}
		### If the option is asking for nothing special
		else {
			### Check if json can be parsed into hash	
			eval 
			{
				$json = decode_json(encode_utf8($data));
				1;
			}
			or do 
			{
				### Log Entry for debugging purposes
				Log3 $name, 3, $name. " : DoorBird_List_Schedules - Data                    : " . $data;
				
				### Log Entry
				Log3 $name, 3, $name. " : DoorBird_Get - Data cannot be parsed by JSON for  : List_Schedules";

				return $data;
			};
			
			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_Get - json                               : " . $json;

			### Delete all Readings for Relay-Addresses
			fhem( "deletereading $name Schedule_.*" );
			
			### Initiate Bulk Update
			readingsBeginUpdate($hash);
			
			### For every chapter in the Array of elements
			foreach my $Schedule (@{$json}) {
	
				### Create first part of Reading
				my $ReadingNameA = "Schedule_" . $Schedule->{input} . "_";
				
				### If Parameter exists
				if ($Schedule->{param} ne "") {
					### Add Parameter
					$ReadingNameA .= $Schedule->{param} . "_";
				}

				### For every chapter in the Array of elements
				foreach my $Output (@{$Schedule->{output}}) {

					my $ReadingNameB = $ReadingNameA . $Output->{event} ."_";

	   				### If Parameter exists
					if ($Output->{param} ne "") {
						### Add Parameter
						$ReadingNameB .= $Schedule->{param} . "_";
					}
					else {
						### Add Parameter
						$ReadingNameB .= "x_";
					}
					
					
					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_Get - Schedules - ReadingName            : " . $ReadingNameB;

					#					my $ReadingValue  = $Output->($Output);
					#					Log3 $name, 5, $name. " : DoorBird_Get - Schedules - ReadingValue           : " . $ReadingValue;
				}
			}
	
			### Execute Readings Bulk Update
			readingsEndUpdate($hash, 1);		
			return "Readings have been updated!\nPress F5 to refresh Browser.";
		}
	}
	### If error has been handed back
	else {
		$err =~ s/^[^ ]*//;
		return "ERROR!\nError Code:" . $err;
	}
}
####END####### Define Subfunction for LIST SCHEDULES ###########################################################END#####

###START###### Define Subfunction for RESTART #################################################################START####
sub DoorBird_Restart($$) {
	my ($hash, $option)	= @_;
	my $name			= $hash->{NAME};
	my $command			= "restart.cgi"; 
	my $method			= "GET";
	my $header			= "Accept: application/json";
	my $username 		= DoorBird_credential_decrypt($hash->{helper}{".USER"});
	my $err;
	my $data;
	my $json;

	### Activate Relay
	($err, $data) = DoorBird_BlockGet($hash, $command, $method, $header);

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_Restart - err                            : " . $err;
	Log3 $name, 5, $name. " : DoorBird_Restart - data                           : " . $data;

	### If no error has been handed back
	if ($err eq "") {
		### Log Entry
		Log3 $name, 3, $name. " : DoorBird_Restart - Reboot request successfully transmitted to DoorBird";
		
		return "Reboot request successfully transmitted to DoorBird\nData: " . $data;
	}
	### If error has been handed back
	else {
		### Cut off url from error message
		$err =~ s/^[^ ]*//;

		### Log Entry
		Log3 $name, 2, $name. " : DoorBird_Restart - Reboot command failed. ErrorMsg: " . $err;

		return "ERROR!\nError Code:" . $err . "\nData: " . $data;
	}
}
####END####### Define Subfunction for RESTART ##################################################################END#####


###START###### Define Subfunction for SIP Status REQUEST ######################################################START####
sub DoorBird_SipStatus_Request($$) {
	my ($hash, $option)	= @_;
	my $name			= $hash->{NAME};
	my $command			= "sip.cgi?action=status"; 
	my $method			= "GET";
	my $header			= "Accept: application/json";
	
	my $err = " ";
	my $data = " ";
	my $json;
	
	### Obtain data
	($err, $data) = DoorBird_BlockGet($hash, $command, $method, $header);

	### Remove Newlines for better log entries
	my $ShowData = $data;
	$ShowData =~ s/[\t]//g;
	$ShowData =~ s/[\r]//g;
	$ShowData =~ s/[\n]//g;

	
	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_SipStatus_Req- err                       : " . $err      if(defined($err));
#	Log3 $name, 5, $name. " : DoorBird_SipStatus_Req- data                      : " . $ShowData if(defined($ShowData));
	
	### If no error has been handed back
	if ($err eq "") {
		### If the option is  asking for the JSON string
		if (defined($option) && ($option =~ /JSON/i)) {
			return $data;		
		}
		### If the option is asking for nothing special
		else {
			### Check if json can be parsed into hash	
			eval 
			{
				$json = decode_json(encode_utf8($data));
				1;
			}
			or do 
			{
				### Log Entry for debugging purposes
				Log3 $name, 3, $name. " : DoorBird_SipStatus_Req- Data cannot parsed JSON   : Info_Request";
				return $name. " : DoorBird_SipStatus_Req- Data cannot be parsed by JSON for Info_Request";
			};
			
			my $VersionContent = $json-> {BHA}{SIP}[0];
			
			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : DoorBird_SipStatus_Req- json                      : " . Dumper($json);
			
			 ### Initiate Bulk Update
			 readingsBeginUpdate($hash);

			 foreach my $key (keys %{$VersionContent}) {

				### If the entry are information about connected INCOMING_CALL_USER
				if ( $key eq "INCOMING_CALL_USER") {

					### Split all Call User in array
					my @CallUserArray = split(";", $VersionContent -> {$key});
					
					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_SipStatus_Req- CallUser                       : " . Dumper(@CallUserArray);
					
					### Count Number of current readings containing call user 
					my $CountCurrentCallUserReadings = 0;
					foreach my  $CurrentCallUserReading (keys(%{$hash->{READINGS}})) {
						if ($CurrentCallUserReading =~ m/SIP_INCOMING_CALL_USER_/){
							$CountCurrentCallUserReadings++;
						}
					}

					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_SipStatus_Req- CountCurrentCallUserReadings    : " . $CountCurrentCallUserReadings;
					Log3 $name, 5, $name. " : DoorBird_SipStatus_Req- CallUserArray                   : " . @CallUserArray;
					
					### If the number of call user in DoorBird unit is smaller than the number of Call user readings then delete all respective readings first
					if (@CallUserArray < $CountCurrentCallUserReadings) {
						fhem("deletereading $name SIP_INCOMING_CALL_USER_.*");
					}
					
					### For every Call-User do
					my $CallUserId;
					foreach my $CallUser (@CallUserArray) {
						
						### Increment Counter
						$CallUserId++;
						
						### Delete "sip:" if exists
						$CallUser =~ s/^[^:]*://;
					
						### Log Entry for debugging purposes
						Log3 $name, 5, $name. " : DoorBird_SipStatus_Req- Content of" . sprintf("%15s %-s", "SIP_INCOMING_CALL_USER_" . sprintf("%02d",$CallUserId), ": " . "sip:" . $CallUser);

						### Update Reading
						readingsBulkUpdate($hash, "SIP_INCOMING_CALL_USER_" . sprintf("%02d",$CallUserId), "sip:" . $CallUser);
					}
				}
				### If the entry are information about connected relais
				elsif ( $key =~ m/relais:/) {
					
					### Extract number, swap to Uppercase and concat to new Readingsname
					my ($RelaisNumer) = $key =~ /(\d+)/g;

					my $NewReadingsName = uc($key);
					$NewReadingsName =~ s/:.*//;
					$NewReadingsName = "SIP_" . $NewReadingsName . "_" . sprintf("%02d",$RelaisNumer);

					### Update Reading
					readingsBulkUpdate($hash, $NewReadingsName, $VersionContent -> {$key});
					
					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_SipStatus_Req- Content of" . sprintf("%15s %-s", $key, ": " . $VersionContent -> {$key});
					Log3 $name, 5, $name. " : DoorBird_SipStatus_Req- Content of" . sprintf("%15s %-s", "NewReadingsName", ": " . $NewReadingsName);
					Log3 $name, 5, $name. " : DoorBird_SipStatus_Req- Content of" . sprintf("%15s %-s", "RelaisNumber",    ": " . $RelaisNumer);
				}
				### For all other entries
				else {
					
					### Log Entry for debugging purposes
					Log3 $name, 5, $name. " : DoorBird_SipStatus_Req- Content of" . sprintf("%15s %-s", $key, ": " . $VersionContent -> {$key});

					### Update Reading
					readingsBulkUpdate($hash, "SIP_" . $key, $VersionContent -> {$key} );
				}
			}
			### Update Reading for Firmware-Status
			readingsBulkUpdate($hash, "Firmware-Status", "up-to-date");

			### Execute Readings Bulk Update
			readingsEndUpdate($hash, 1);

			### Check for Firmware-Updates
			DoorBird_FirmwareStatus($hash);
			
			return "Readings have been updated!\n";
		}
	}
	### If error has been handed back
	else {
		$err =~ s/^[^ ]*//;
		return "ERROR!\nError Code:" . $err;
	}
}
####END#######  Define Subfunction for SIP Status REQUEST  #####################################################END#####


###START###### Encrypt Credential #############################################################################START####
sub DoorBird_credential_encrypt($) {
  my ($decoded) = @_;
  my $key = getUniqueId();
  my $encoded;

  return $decoded if( $decoded =~ /\Qcrypt:\E/ );

  for my $char (split //, $decoded) {
    my $encode = chop($key);
    $encoded .= sprintf("%.2x",ord($char)^ord($encode));
    $key = $encode.$key;
  }

  return 'crypt:'.$encoded;
}
####END####### Encrypt Credential ##############################################################################END#####

###START###### Decrypt Credential #############################################################################START####
sub DoorBird_credential_decrypt($) {
  my ($encoded) = @_;
  my $key = getUniqueId();
  my $decoded;

  return $encoded if( $encoded !~ /crypt:/ );
  
  $encoded = $1 if( $encoded =~ /crypt:(.*)/ );

  for my $char (map { pack('C', hex($_)) } ($encoded =~ /(..)/g)) {
    my $decode = chop($key);
    $decoded .= chr(ord($char)^ord($decode));
    $key = $decode.$key;
  }

  return $decoded;
}
####END####### Decrypt Credential ##############################################################################END#####

###START###### Blocking Get ###################################################################################START####
sub DoorBird_BlockGet($$$$) {
	### https://wiki.fhem.de/wiki/HttpUtils#HttpUtils_BlockingGet
	
	### Extract subroutine parameter from caller
	my ($hash, $ApiCom, $Method, $Header)	= @_;
	
	### Obtain values from hash
	my $name			= $hash->{NAME};
	my $username 		= DoorBird_credential_decrypt($hash->{helper}{".USER"});
	my $password		= DoorBird_credential_decrypt($hash->{helper}{".PASSWORD"});
	my $url 			= $hash->{helper}{URL};
	my $PollingTimeout  = $hash->{helper}{PollingTimeout};
	
	### Create complete command URL for DoorBird
	my $UrlPrefix 		= "https://" . $url . "/bha-api/";
	my $CommandURL 		= $UrlPrefix . $ApiCom;
	
	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : DoorBird_BlockingGet - CommandURL                 : " . $CommandURL;

	my $param = {
		url               => $CommandURL,
		user              => $username,
		pwd               => $password,
		timeout           => $PollingTimeout,
		hash              => $hash,
		method            => $Method,
		header            => $Header
	};

	### Initiate communication and close
	my ($err, $data) = HttpUtils_BlockingGet($param);

	return($err, $data);
}
####END####### Blocking Get ####################################################################################END#####
1;

###START###### Description for fhem commandref ################################################################START####
=pod
=item device
=item summary    Connects fhem to the DoorBird IP door station
=item summary_DE Verbindet fhem mit der DoorBird IP T&uuml;rstation

=begin html

<a name="DoorBird"></a>
<h3>DoorBird</h3>
<ul>
	<table>
		<tr>
			<td>
				The DoorBird module establishes the communication between the DoorBird - door intercommunication unit and the fhem home automation based on the official API, published by the manufacturer.<BR>
				Please make sure, that the user has been enabled the API-Operator button in the DoorBird Android/iPhone APP under "Administration -> User -> Edit -> Permission -> API-Operator".
				The following packet - installations are pre-requisite if not already installed by other modules (Examples below tested on Raspberry JESSIE):<BR>
				<BR>
				<code>
					<li>sudo apt-get install sox					</li>
					<li>sudo apt-get install libsox-fmt-all			</li>
					<li>sudo apt-get install libsodium-dev			</li>
					<li>sudo cpan Crypt::Argon2						</li>
					<li>sudo cpan Alien::Base::ModuleBuild			</li>
					<li>sudo cpan Alien::Sodium						</li>
					<li>sudo cpan Crypt::NaCl::Sodium				</li>
				</code>
			</td>
		</tr>
	</table>
	<BR>

	<table>
		<tr>
			<td>
				<a name="DoorBirddefine"></a><b>Define</b>
			</td>
		</tr>
	</table>

	<table>
		<tr>
			<td>
				<ul>
					<code>define &lt;name&gt; DoorBird &lt;IPv4-address&gt; &lt;Username&gt; &lt;Password&gt;</code>
				</ul>
			</td>
		</tr>
	</table>

	<ul>
		<ul>
			<table>
				<tr><td><code>&lt;name&gt;                </code> : </td><td>The name of the device. Recommendation: "myDoorBird".																		</td></tr>
				<tr><td><code>&lt;IPv4-address&gt;        </code> : </td><td>A valid IPv4 address of the KMxxx. You might look into your router which DHCP address has been given to the DoorBird unit.	</td></tr>
				<tr><td><code>&lt;Username&gt;            </code> : </td><td>The username which is required to sign on the DoorBird.																	</td></tr>
				<tr><td><code>&lt;Password&gt;            </code> : </td><td>The password which is required to sign on the DoorBird.																	</td></tr>
			</table>
		</ul>
	</ul>

	<BR>

	<table>
		<tr><td><a name="DoorBirdSet"></a><b>Set</b></td></tr>
		<tr><td><ul>The set function is able to change or activate the following features as follows:</ul></td></tr>
	</table>


	<table>
		<tr><td><ul><code>set Light_On                    </code></ul></td><td> : Activates the IR lights of the DoorBird unit. The IR - light deactivates automatically by the default time within the Doorbird unit																			</td></tr>
		<tr><td><ul><code>set Live_Audio &lt;on:off&gt;   </code></ul></td><td> : Activate/Deactivate the Live Audio Stream of the DoorBird on or off and toggles the direct link in the <b>hidden</b> Reading <code>.AudioURL</code>															</td></tr>
		<tr><td><ul><code>set Live_Video &lt;on:off&gt;   </code></ul></td><td> : Activate/Deactivate the Live Video Stream of the DoorBird on or off and toggles the direct link in the <b>hidden</b> Reading <code>.VideoURL</code>															</td></tr>
		<tr><td><ul><code>set Open Door &lt;Value&gt;     </code></ul></td><td> : Activates the Relay of the DoorBird unit with the given address. The list of installed relay addresses are imported with the initialization of parameters.													</td></tr>
		<tr><td><ul><code>set Restart                     </code></ul></td><td> : Sends the command to restart (reboot) the Doorbird unit																																						</td></tr>
		<tr><td><ul><code>set Transmit_Audio &lt;Path&gt; </code></ul></td><td> : Converts a given audio file and transmits the stream to the DoorBird speaker. Requires a datapath to audio file to be converted and send. The user "fhem" needs to have write access to this directory.<BR>	</td></tr>
	</table>


	<table>
		<tr><td><a name="DoorBirdGet"></a><b>Get</b></td></tr>
		<tr><td>
			<ul>
					The get function is able to obtain the following information from the DoorBird unit:<BR><BR>
			</ul>
		</td></tr>
	</table>
	<table>
		<tr><td><ul><code>get History_Request             </code></ul></td><td> : Downloads the pictures of the last events of the doorbell and motion sensor. (Refer to attribute <code>MaxHistory</code>)																						</td></tr>
		<tr><td><ul><code>get Image_Request               </code></ul></td><td> : Downloads the current Image of the camera of DoorBird unit.																																					</td></tr>
		<tr><td><ul><code>get Info_Request                </code></ul></td><td> : Downloads the current internal setup such as relay configuration, firmware version etc. of the DoorBird unit. The obtained relay adresses will be used as options for the <code>Open_Door</code> command.		</td></tr>
	</table>


	<table>
		<tr><td><a name="DoorBirdAttr"></a><b>Attributes</b></td></tr>
		<tr><td>
			<ul>
					The following user attributes can be used with the DoorBird module in addition to the global ones e.g. <a href="#room">room</a>.<BR>
			</ul>
		</td></tr>
	</table>

	<ul>
		<table>
			<tr>
				<td>
				<code>disable</code> : </td><td>Stops the device from further reacting on UDP datagrams sent by the DoorBird unit.<BR>
																   The default value is 0 = activated<BR>
				</td>
			</tr>
			<tr>
				<td>
					<code>KeepAliveTimeout</code> : </td><td>Timeout in seconds without still-alive UDP datagrams before state of device will be set to "disconnected".<BR>
																   The default value is 30s<BR>
				</td>
			</tr>
			<tr>
				<td>
					<code>MaxHistory</code> : </td><td>Number of pictures to be downloaded from history for both - doorbell and motion sensor events.<BR>
																   The default value is "50" which is the maximum possible.<BR>
				</td>
			</tr>
			<tr>
				<td>
					<code>PollingTimeout</code> : </td><td>Timeout in seconds before download requests are terminated in cause of no reaction by DoorBird unit. Might be required to be adjusted due to network speed.<BR>
																   The default value is 10s.<BR>

				</td>
			</tr>
			<tr>
				<td>
					<code>UdpPort</code> : </td><td>Port number to be used to receice UDP datagrams. Ports are pre-defined by firmware.<BR>
																   The default value is port 6524<BR>

				</td>
			</tr>
			<tr>
				<td>
					<code>SipDevice</code> : </td><td>Name of the fhem SIP device which is registered in the DoorBird unit as those ones who are allowed to call the DoorBird. Refer to <a href="#SIP">SIP</a>.<BR>
																   The default value is the first SIP device in fhem.<BR>

				</td>
			</tr>
			<tr>
				<td>
					<code>SessionIdSec</code> : </td><td>Time in seconds for how long the session Id shall be valid, which is required for secure Video and Audio transmission. The DoorBird kills the session Id after 10min = 600s automatically. In case of use with CCTV recording units, this function must be disabled by setting to 0.<BR>
																   The default value is 540s = 9min.<BR>

				</td>
			</tr>
			<tr>
				<td>
					<code>SipNumber</code> : </td><td>The telephone number under which the DoorBird unit is registered and can be called.<BR>
																   The default value is <code>**620</code><BR>
				</td>
			</tr>
			<tr>
				<td>
					<code>ImageFileDir</code> : </td><td>The relative (e.g. "images") or absolute (e.g. "/mnt/NAS/images") with or without trailing "/" directory path to which the image files supposed to be stored.<BR>
																   The default value is <code>0</code> = disabled<BR>
				</td>
			</tr>
			<tr>
				<td>
					<code>EventReset</code> : </td><td>Time in seconds after wich the Readings for the Events Events (e.g. "doorbell_button", "motions sensor", "keypad") shal be reset to "idle".<BR>
   																   The default value is 5s<BR>
				</td>
			</tr>
			<tr>
				<td>
					<code>WaitForHistory</code> : </td><td>Time in seconds after wich the module shall wait for an history image triggered by an event is ready for download. Might be adjusted if fhem-Server and Doorbird unit have large differences in system time.<BR>
   																   The default value is 7s<BR>
				</td>
			</tr>
		</table>
	</ul>
</ul>
=end html


=begin html_DE

<a name="DoorBird"></a>
<h3>DoorBird</h3>
<ul>
	<table>
		<tr>
			<td>
				Das DoorBird Modul erm&ouml;glicht die Komminikation zwischen der DoorBird Interkommunikationseinheit und dem fhem Automationssystem basierend auf der API des Herstellers her.<BR>
				Für den vollen Funktionsumfang muss sichergestellt werden, dass das Setting "API-Operator" in der DoorBird Android/iPhone - APP unter "Administration -> User -> Edit -> Permission -> API-Operator" gesetzt ist.
				Die folgenden Software - Pakete m&uuml;ssen noch zus&auml;tzlich installiert werden, sofern dies nicht schon durch andere Module erfolgt ist. (Die Beispiele sind auf dem Raspberry JESSIE gestestet):<BR>
				<BR>
				<code>
					<li>sudo apt-get install sox					</li>
					<li>sudo apt-get install libsox-fmt-all			</li>
					<li>sudo apt-get install libsodium-dev			</li>
					<li>sudo cpan Crypt::Argon2						</li>
					<li>sudo cpan Alien::Base::ModuleBuild			</li>
					<li>sudo cpan Alien::Sodium						</li>
					<li>sudo cpan Crypt::NaCl::Sodium				</li>
				</code>
			</td>
		</tr>
	</table>
	<BR>

	<table>
		<tr>
			<td>
				<a name="DoorBirddefine"></a><b>Define</b>
			</td>
		</tr>
	</table>

	<table>
		<tr>
			<td>
				<ul>
					<code>define &lt;name&gt; DoorBird &lt;IPv4-address&gt; &lt;Username&gt; &lt;Passwort&gt;</code>
				</ul>
			</td>
		</tr>
	</table>

	<ul>
		<ul>
			<table>
				<tr><td><code>&lt;name&gt;           </code> : </td><td>Der Name des Device unter fhem. Beispiel: "myDoorBird".																												</td></tr>
				<tr><td><code>&lt;IPv4-Addresse&gt;  </code> : </td><td>Eine g&uuml;ltige IPv4 - Addresse der DoorBird-Anlage. Ggf. muss man im Router nach der entsprechenden DHCP Addresse suchen, die der DoorBird Anlage vergeben wurde.</td></tr>
				<tr><td><code>&lt;Username&gt;       </code> : </td><td>Der Username zum einloggen auf der DoorBird Anlage.																													</td></tr>
				<tr><td><code>&lt;Passwort&gt;       </code> : </td><td>Das Passwort zum einloggen auf der DoorBird Anlage.																													</td></tr>
			</table>
		</ul>
	</ul>

	<BR>

	<table>
		<tr><td><a name="DoorBirdSet"></a><b>Set</b></td></tr>
		<tr><td><ul>Die Set - Funktion ist in der lage auf der DoorBird - Anlage die folgenden Einstellungen vorzunehmen bzw. zu de-/aktivieren:</ul><BR></td></tr>
	</table>

	<table>
		<tr><td><ul><code>set Light_On                    </code></ul></td><td> : Schaltet das IR lichht der DoorBird Anlage ein. Das IR Licht schaltet sich automatisch nach der in der DoorBird - Anlage vorgegebenen Default Zeit wieder aus.																	</td></tr>
		<tr><td><ul><code>set Live_Audio &lt;on:off&gt;   </code></ul></td><td> : Aktiviert/Deaktiviert den Live Audio Stream der DoorBird - Anlage Ein oder Aus und wechselt den direkten link in dem <b>versteckten</b> Reading <code>.AudioURL.</code>															</td></tr>
		<tr><td><ul><code>set Live_Video &lt;on:off&gt;   </code></ul></td><td> : Aktiviert/Deaktiviert den Live Video Stream der DoorBird - Anlage Ein oder Aus und wechselt den direkten link in dem <b>versteckten</b> Reading <code>.VideoURL.</code>															</td></tr>
		<tr><td><ul><code>set Open Door &lt;Value&gt;     </code></ul></td><td> : Aktiviert das Relais der DoorBird - Anlage mit dessen Adresse. Die Liste der installierten Relais werden mit der Initialisierung der Parameter importiert.																		</td></tr>
		<tr><td><ul><code>set Restart                     </code></ul></td><td> : Sendet das Kommando zum rebooten der DoorBird - Anlage.																																											</td></tr>
		<tr><td><ul><code>set Transmit_Audio &lt;Path&gt; </code></ul></td><td> : Konvertiert die angegebene Audio-Datei und sendet diese zur Ausgabe an die DoorBird - Anlage. Es ben&ouml;tigt einen Dateipfad zu der Audio-Datei zu dem der User "fhem" Schreibrechte braucht (z.B.: /opt/fhem/audio).			</td></tr>
	</table>


	<table>
		<tr><td><a name="DoorBirdGet"></a><b>Get</b></td></tr>
		<tr><td><ul>Die Get - Funktion ist in der lage von der DoorBird - Anlage die folgenden Informationen und Daten zu laden:<BR><BR></ul></td></tr>
	</table>
	<table>
		<tr><td><ul><code>get History_Request             </code></ul></td><td> : L&auml;dt die Bilder der letzten Ereignisse durch die T&uuml;rklingel und dem Bewegungssensor herunter. (Siehe auch Attribut <code>MaxHistory</code>)</td></tr>
		<tr><td><ul><code>get Image_Request               </code></ul></td><td> : L&auml;dt das gegenw&auml;rtige Bild der DoorBird - Kamera herunter.</td></tr>
		<tr><td><ul><code>get Info_Request                </code></ul></td><td> : L&auml;dt das interne Setup (Firmware Version, Relais Konfiguration etc.) herunter. Die &uuml;bermittelten Relais-Adressen werden als Option f&uuml;r das Kommando <code>Open_Door</code> verwendet.</td></tr>
	</table>


	<table>
		<tr><td><a name="DoorBirdAttr"></a><b>Attributes</b></td></tr>
		<tr><td>
			<ul>
					Die folgenden Attribute k&ouml;nnen mit dem DoorBird Module neben den globalen Attributen wie <a href="#room">room</a> verwednet werden.<BR>
			</ul>
		</td></tr>
	</table>

	<ul>
		<table>
			<tr>
				<td>
					<code>disable          </code> : </td><td>Stoppt das Ger&auml;t von weiteren Reaktionen auf die von der DoorBird ß Anlage ausgesendeten UDP - Datageramme<BR>											          Der Default Wert ist 0 = aktiviert<BR>
				</td>
			</tr>
			<tr>
				<td>
					<code>KeepAliveTimeout </code> : </td><td>Timeout in Sekunden ohne "still-alive" - UDP Datagramme bevor der Status des Ger&auml;tes auf  "disconnected" gesetzt wird.<BR>
														  Der Default Wert ist 30s<BR>
				</td>
			</tr>
			<tr>
				<td>
					<code>MaxHistory       </code> : </td><td>Anzahl der herunterzuladenden Bilder aus dem Historien-Archiv sowohl f&uuml;r Ereignisse seitens der T&uuml;rklingel als auch f&uuml;r den Bewegungssensor.<BR>
														  Der Default Wert ist "50" = Maximum.<BR>
				</td>
			</tr>
			<tr>
				<td>
					<code>PollingTimeout   </code> : </td><td>Timeout in Sekunden before der Download-Versuch aufgrund fehlender Antwort seitens der DoorBird-Anlage terminiert wird. Eine Adjustierung mag notwendig sein, sobald Netzwerk-Latenzen aufteten.<BR>
														  Der Default-Wert ist 10s.<BR>
				</td>
			</tr>
			<tr>
				<td>
					<code>UdpPort          </code> : </td><td>Port Nummer auf welcher das DoorBird - Modul nach den UDP Datagrammen der DoorBird - Anlage h&ouml;ren soll. Die Ports sind von der Firmware vorgegeben.<BR>
														  Der Default Port ist 6524<BR>
				</td>
			</tr>
			<tr>
				<td>
					<code>SessionIdSec</code> : </td><td>Zeit in Sekunden nach welcher die Session Id erneuert werden soll. Diese ist f&uuml;r die sichere &Uuml;bertragung der Video und Audio Verbindungsdaten notwendig. Die DoorBird-Unit devalidiert die Session Id automatisch nach 10min. F&uuml;r den Fall, dass die DoorBird Kamera an ein &Uuml;berwachungssystem angebunden werden soll, muss diese Funktion ausser Betrieb genommen werden indem man den Wert auf 0 setzt 0.<BR>
																   Der Default Wert ist 540s = 9min.<BR>
				</td>
			</tr>
			<tr>
				<td>
					<code>SipDevice</code> : </td><td>Name des fhem SIP Device mit wessen Nummer in der DoorBird - Anlage hinterlegt wurde die die DoorBird - Anlage  anrufen d&uuml;rfen. Refer to <a href="#SIP">SIP</a>.<BR>
																   Der Default Wert ist das erste SIP device in fhem.<BR>
				</td>
			</tr>
			<tr>
				<td>
					<code>SipNumber</code> : </td><td>Die Telefonnummer unter der die DoorBird / Anlage registriert und erreicht werden kann.<BR>
																   Der Default Wert ist <code>**620</code><BR>
				</td>
			</tr>
			<tr>
				<td>
					<code>ImageFileDir</code> : </td><td>Der relative (z.B. "images") oder absolute (z.B. "/mnt/NAS/images") Verzeichnispfad mit oder ohne nachfolgendem Pfadzeichen "/"  in welchen die Bild-Dateien gespeichert werden sollen.<BR>
																   Der Default Wert ist <code>0</code> = deaktiviert<BR>
				</td>
			</tr>
			<tr>
				<td>
					<code>EventReset</code> : </td><td>Zeit in Sekunden nach welcher die Readings f&uuml;r die Events (z.B. "doorbell_button", "motions sensor", "keypad")wieder auf "idle" gesetzt werden sollen.<BR>
   																   Der Default Wert ist 5s<BR>
				</td>
			</tr>			
			<tr>
				<td>
					<code>WaitForHistory</code> : </td><td>Zeit in Sekunden die das Modul auf das Bereitstellen eines korrespondierenden History Bildes zu einem Event warten soll. Muss ggf. adjustiert werden, sobald deutliche Unterschiede in der Systemzeit zwischen fhemßServer und DoorBird Station vorliegen.<BR>
   																   Der Default Wert ist 7s<BR>
				</td>
			</tr>
		</table>
	</ul>
</ul>
=end html_DE

=encoding utf8

=for :application/json;q=META.json 73_DoorBird.pm
{
  "abstract": "Connects fhem to the DoorBird IP door station",
  "description": "The DoorBird module establishes the communication between the DoorBird - door intercommunication unit and the fhem home automation based on the official API, published by the manufacturer. Please make sure, that the user has been enabled the API-Operator button in the DoorBird Android/iPhone APP under Administration -> User -> Edit -> Permission -> API-Operator.",
  "x_lang": {
    "de": {
      "abstract": "Verbindet fhem mit der DoorBird IP Türstation",
      "description": "Das DoorBird Modul ermöglicht die Komminikation zwischen der DoorBird Interkommunikationseinheit und dem fhem Automationssystem basierend auf der API des Herstellers her. Für den vollen Funktionsumfang muss sichergestellt werden, dass das Setting \"API-Operator\" in der DoorBird Android/iPhone - APP unter Administration -> User -> Edit -> Permission -> API-Operator gesetzt ist."
    }
  },
  "license": [
    "GPL_2"
  ],
  "author": [
    "Matthias Deeke <matthias.deeke@deeke.eu>"
  ],
  "x_fhem_maintainer": [
    "Sailor"
  ],
  "keywords": [
    "Doorbird",
    "Intercom"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "Alien::Base::ModuleBuild": 0,
        "Alien::Sodium": 0,
        "Crypt::Argon2": 0,
        "Crypt::NaCl::Sodium": 0,
        "Cwd": 0,
        "Data::Dumper": 0,
        "Encode": 0,
        "HttpUtils": 0,
        "IO::Socket": 0,
        "JSON": 0,
        "LWP::UserAgent": 0,
        "MIME::Base64": 0,
        "constant": 0,
        "strict": 0,
        "utf8": 0,
        "warnings": 0,
        "perl": 5.014
      },
      "recommends": {
      },
      "suggests": {
      }
    }
  },
  "x_prereqs_os_debian": {
    "runtime": {
      "requires": {
        "sox": 0,
        "libsox-fmt-all": 0,
        "libsodium-dev": 0
      },
      "recommends": {
      },
      "suggests": {
      }
    }
  }
}
=end :application/json;q=META.json

=cut