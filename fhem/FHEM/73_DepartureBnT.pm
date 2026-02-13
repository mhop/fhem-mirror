# $Id$
########################################################################################################################
#
#     73_DepartureBnT.pm
#     Departure Bus and Train
#     Reads the departure data from transport.stefan-biermann.de for a given station
#     Written and best viewed with Notepad++ v.6.8.6; Language Markup: Perl
#
#
#     Author                     : Matthias Deeke 
#     e-mail                     : matthias.deeke(AT)deeke(PUNKT)eu
#     Fhem Forum                 : Not yet implemented
#     Fhem Wiki                  : Not yet implemented
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
#     fhem.cfg: define <devicename> DepartureBnT
#
#     Example:
#     define myBusStation DepartureBnT
#
########################################################################################################################

########################################################################################################################
# List of open Problems / Issues:
#
#
########################################################################################################################

package main;
use strict;
use warnings;
use utf8;
use Encode;
use Date::Parse;
use Time::Local;
use FHEM::Meta;
use Data::Dumper;
use POSIX;
my %DepartureBnT_gets;
my %DepartureBnT_sets;

###START###### Initialize module ##############################################################################START####
sub DepartureBnT_Initialize($) {
    my ($hash)  = @_;
	
    $hash->{STATE}				= "Init";
    $hash->{DefFn}				= "DepartureBnT_Define";
    $hash->{UndefFn}			= "DepartureBnT_Undefine";
    $hash->{GetFn}           	= "DepartureBnT_Get";
	$hash->{SetFn}           	= "DepartureBnT_Set";
    $hash->{AttrFn}				= "DepartureBnT_Attr";
	$hash->{FW_detailFn}        = "DepartureBnT_FW_detailFn";
	$hash->{NotifyOrderPrefix}	= "50-";

	$hash->{AttrList}       	= "disable:0,1 " .
								  "NoOfEntries:slider,1,1,20 " .
								  "UpdateInterval:slider,60,60,3600 " .
								  "StationId " .
								  "PollingTimeout " .
								  "MaxLength " .
								  "WalkTimeToStation " .
								  $readingFnAttributes;
	
	return FHEM::Meta::InitMod( __FILE__, $hash );
}
####END####### Initialize module ###############################################################################END#####


###START###### Activate module after module has been used via fhem command "define" ###########################START####
sub DepartureBnT_Define($$) {
	my ($hash, $def)		= @_;
	my @a					= split("[ \t][ \t]*", $def);
	my $name				= $a[0];
							 #$a[1] just contains the module name and we already know that
	my $interval			= $a[2];
	
	### To pass version data to META
	return $@ unless ( FHEM::Meta::SetInternals($hash) );

	### Writing values to global hash
	$hash->{NAME}							= $name;
    
	### Writing log entry
	Log3 $name, 5, $name. " : DepartureBnT - Starting to define module";

	### Proceed with Initialization as soon fhem is initialized
	# https://forum.fhem.de/index.php/topic,130351.msg1246281.html#msg1246281
	# Die InternalTimer Eintraege werden erst abgearbeitet, wenn $init_done = 1 ist.
	InternalTimer(0, \&DepartureBnT_Startup, $hash );

	
	### Write log information
	Log3 $name, 4, $name. " has been defined.";
	
	return;
}
####END####### Activate module after module has been used via fhem command "define" ############################END#####


###START###### Deactivate module module after "undefine" command by fhem ######################################START####
sub DepartureBnT_Undefine($$) {
	my ($hash, $def)  = @_;
	my $name = $hash->{NAME};	

	### Stop internal timer
	RemoveInternalTimer($hash);
	
	### Write log information
	Log3 $name, 3, $name. "DepartureBnT has been undefined.";
	
	return;
}
####END####### Deactivate module module after "undefine" command by fhem #######################################END#####


###START###### Handle attributes after changes via fhem GUI ###################################################START####
sub DepartureBnT_Attr(@) {
	my @a                      = @_;
	my $name                   = $a[1];
	my $hash                   = $defs{$name};

	### For debugging purpose only
	Log3 $name, 5, $name. " : DepartureBnT_Attr Begin__________________________________________________________________________________________________________________________";

	### Check whether "disable" attribute has been provided
	if ($a[2] eq "disable") 
	{
		if    ($a[3] eq 0)
		{	
			$hash->{STATE} = "active";
		}
		elsif ($a[3] eq 1)		
		{	
			$hash->{STATE} = "disabled";

			### Stop internal timer
			RemoveInternalTimer($hash);

			### Write log information
			Log3 $name, 4, $name. " - Device has been disabled and timer has been deleted.";
		}
	}

	### Check whether "StationId" attribute has been provided
	if ($a[2] eq "StationId") 
	{
		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DepartureBnT_Attr - StationId                : " . $a[3];
		
		### Save StationId as helper
		$hash->{helper}{StationId} = $a[3];
		
		### Delete all Readings
		DepartureBnT_DeleteAllReadings($hash);

		### Update Header
		DepartureBnT_UpdateStationDetails($hash);
		
		### Update all Departures
		DepartureBnT_Update($hash);
	}
	
	### Check whether "UpdateInterval" attribute has been provided
	if ($a[2] eq "UpdateInterval") 
	{
	
		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DepartureBnT_Attr - UpdateInterval           : " . $a[3];
	
		### Stop internal timer
		RemoveInternalTimer($hash);

		### Start internal timer on next Gauge update
		InternalTimer(gettimeofday()+$a[3], \&DepartureBnT_Update, $hash);
	}
	return;
}
####END####### Handle attributes after changes via fhem GUI ####################################################END#####


###START###### Manipulate reading after "get" command by fhem #################################################START####
sub DepartureBnT_Get($@) {
	# my ( $hash, @a ) = @_;
	
	# ### If not enough arguments have been provided
	# if ( @a < 2 ) {
		# return "\"set DepartureBnT\" needs at least one argument";
	# }
		
	# my $ReturnMessage;
	# my @cList;

	### Create Get List
	# push(@cList, " "); 


	# return "Unknown argument $reading, choose one of " . join(" ", @cList) if $reading eq '?';	
	
	return;
}
####END####### Manipulate reading after "get" command by fhem ##################################################END#####


###START###### Manipulate reading after "set" command by fhem #################################################START####
sub DepartureBnT_Set($@) {
	my ( $hash, @a ) = @_;
	my $ReturnValue;
	
	### If not enough arguments have been provided
	if ( @a < 2 ) {
		return "\"set DepartureBnT\" needs at least one argument";
	}
	
	my $name     = shift @a;
	my $command  = shift @a;
	my $option   = join(' ', @a);
	my @cList;

	### For debugging purpose only
	Log3 $name, 5, $name. " : DepartureBnT_Set Begin_______________________________________________________________________________________________________________________";
	Log3 $name, 5, $name. " : DepartureBnT_Set - command                   : " . $command;
	Log3 $name, 5, $name. " : DepartureBnT_Set - option                    : " . $option;

	
	### Create Set List
	push(@cList, "Update:noArg SearchStation "); 

	return "Unknown argument $command, choose one of " . join(" ", @cList) if $command eq '?';

	### Manually update Departures
	if ($command eq "Update") {
		DepartureBnT_Update($hash);
	}
	
	### Search for a station
	if ($command eq "SearchStation") {
		$ReturnValue = DepartureBnT_SearchStation($hash, $option);
	}
	return($ReturnValue);
}
####END####### Manipulate reading after "set" command by fhem ##################################################END#####

###START###### Delete all Readings ############################################################################START####
sub DepartureBnT_DeleteAllReadings($) {
	my ($hash) = @_;
	my $name  = $hash->{NAME};

	### Extract all existing Readings as hash reference
	my @ReadingsList = $hash->{READINGS};
	
	### For each Readings do
	foreach my $ReadingsName (keys %{$ReadingsList[0]}) {

		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DepartureBnT_DeleteAllReadings - Deleting Reading         : " . $ReadingsName;
	 
		### Delete Reading
		readingsDelete($hash, $ReadingsName);
	}
}
####END####### Delete all Readings #############################################################################END#####

###START###### Routine for first start ########################################################################START####
sub DepartureBnT_Startup($) {
	my ($hash) = @_;
	my $name  = $hash->{NAME};

	### Stop internal timer
	RemoveInternalTimer($hash);

	### For debugging purpose only
	Log3 $name, 5, $name. " : DepartureBnT_Startup Begin_______________________________________________________________________________________________________________________";
	Log3 $name, 5, $name. " : DepartureBnT_Startup - Attribute DepartureBnTStation         : " . AttrVal($name, "StationId", "NixDa");

	### Check for missing Attributes
	DepartureBnT_CheckAttributes($hash);

	if((defined(AttrVal($name, "StationId", ""))) && (AttrVal($name, "StationId", "None") ne "None")) {
		return;
	}
	else {
		### Delete all Readings
		DepartureBnT_DeleteAllReadings($hash);

		### Update Header
		DepartureBnT_UpdateStationDetails($hash);
		
		### Update all Departures
		DepartureBnT_Update($hash);
	}
	
	return;
}
####END####### Routine for first start #########################################################################END#####

###START###### Check Attributes ###############################################################################START####
sub DepartureBnT_CheckAttributes($) {
	my ($hash) = @_;
	my $name  = $hash->{NAME};

	### For debugging purpose only
	Log3 $name, 5, $name. " : DepartureBnT_CheckAttributes Begin_______________________________________________________________________________________________________________";

	### Check whether all required attributes has been provided and if not, create them with standard values
	if(!defined($attr{$name}{icon})) {
		### Set attribute with standard value since it is not available
		$attr{$name}{icon} = "bus";

		### Writing log entry
		Log3 $name, 4, $name. " : DepartureBnT - The attribute icon was missing and has been set to sea-level";
	}

	if(!defined($attr{$name}{StationId})) {
		### Set attribute with standard value since it is not available
		$attr{$name}{StationId} = "None";

		### Writing log entry
		Log3 $name, 4, $name. " : DepartureBnT - The attribute StationId was missing and has been set to None";
	}
	
	if(!defined($attr{$name}{NoOfEntries})) {
		### Set attribute with standard value since it is not available
		$attr{$name}{NoOfEntries} = 5;

		### Writing log entry
		Log3 $name, 4, $name. " : DepartureBnT - The attribute NoOfEntries was missing and has been set to 5";
	}
	
	if(!defined($attr{$name}{stateFormat})) {
		### Set attribute with standard value since it is not available
		$attr{$name}{stateFormat} = '{ReadingsVal($name, "Station_place","") . "<BR>" . ReadingsVal($name, "Station_name","")}';

		### Writing log entry
		Log3 $name, 4, $name. " : DepartureBnT - The attribute stateFormat was missing and has been set.";
	}

	if(!defined($attr{$name}{UpdateInterval})) {
		### Set attribute with standard value since it is not available
		$attr{$name}{UpdateInterval} = 60;

		### Writing log entry
		Log3 $name, 4, $name. " : DepartureBnT - The attribute UpdateInterval was missing and has been set to 60s = 1min";
	}	
	
	if(!defined($attr{$name}{PollingTimeout})) {
		### Set attribute with standard value since it is not available
		$attr{$name}{PollingTimeout} = 5;

		### Writing log entry
		Log3 $name, 4, $name. " : DepartureBnT - The attribute PollingTimeout was missing and has been set to 5s";
	}
	
	if(!defined($attr{$name}{MaxLength})) {
		### Set attribute with standard value since it is not available
		$attr{$name}{MaxLength} = 0;

		### Writing log entry
		Log3 $name, 4, $name. " : DepartureBnT - The attribute PollingTimeout was missing and has been set to 0 = deactivated";
	}

	if(!defined($attr{$name}{WalkTimeToStation})) {
		### Set attribute with standard value since it is not available
		$attr{$name}{WalkTimeToStation} = 1;

		### Writing log entry
		Log3 $name, 4, $name. " : DepartureBnT - The attribute WalkTimeToStation was missing and has been set to 1 = Right in front the house";
	}
}
####END####### Check Attributes ################################################################################END#####

###START###### Update DepartureBnT station list #######################################################################START####
sub DepartureBnT_SearchStation($$) {
	### Define variables
	my ($hash, $SearchTerm)	= @_;
	my $name  = $hash->{NAME};
	my $PollingTimeout = AttrVal($name, "PollingTimeout", 5);
	my $Stations;
	my $ReturnValue  = "         Copy the preffered ID into the Attribute \"StationId\"!\n\n";
	   $ReturnValue .= "|    ID    |           Place              |         Station Name         |\n";
	   $ReturnValue .= "|----------|------------------------------|------------------------------|\n";

	### Check whether the DepartureBnT has been disabled
	if(IsDisabled($name))
	{
		return;
	}

	### For debugging purpose only
	Log3 $name, 5, $name. " : DepartureBnT_SearchStation Begin____________________________________________________________________________________________________";

	###Replace Space with + and all Umlauts
	$SearchTerm =~ s/ /+/g;
	$SearchTerm =~ s/\xc3\x84/Ae/ug; #Special Character "Ä"
	$SearchTerm =~ s/\xc3\xa4/ae/ug; #Special Character "ä"
	$SearchTerm =~ s/\xc3\x96/Oe/ug; #Special Character "Ö"
	$SearchTerm =~ s/\xc3\xb6/oe/ug; #Special Character "ö"
	$SearchTerm =~ s/\xc3\x9c/Ue/ug; #Special Character "Ü"
	$SearchTerm =~ s/\xc3\xbc/ue/ug; #Special Character "ü"
	$SearchTerm =~ s/\xc3\x9f/sz/ug; #Special Character "ß"

	### Create Search Url
	my $SearchUrl = "https://transport.stefan-biermann.de/publictransportapi/rest/station/suggest?q=" . $SearchTerm;
	
	### For debugging purpose only
	Log3 $name, 5, $name. " : DepartureBnT_SearchStation - SearchUrl       : " .$SearchUrl;

	### Create parameter set for HttpUtils_BlockingGet
	my $param = {
					url        => $SearchUrl,
					timeout    => $PollingTimeout,
					method     => "GET",
					header     => "agent: TeleHeater/2.2.3\r\nUser-Agent: TeleHeater/2.2.3\r\nAccept: application/json",
				};

	### Retrieve data 
	my($err, $data) = HttpUtils_BlockingGet($param);

	### Log entries for debugging purposes
    Log3 $name, 5, $name. " : DepartureBnT_SearchStation - err             : " .$err;
	Log3 $name, 5, $name. " : DepartureBnT_SearchStation - data            : " .$data;


	eval{
		$Stations = decode_json(encode_utf8($data));
		1;
	}
	or do  {
		Log3 $name, 5, $name. " : DepartureBnT_SearchStation - Data cannot be parsed by JSON";
	};

	### Log entries for debugging purposes
    Log3 $name, 5, $name. " : DepartureBnT_SearchStation - Stations        : " . Dumper($Stations);

	foreach my $StationFound ( @$Stations ) {
	
		if ($StationFound->{type} eq "STATION"){

			### Log entries for debugging purposes
			#Log3 $name, 1, $name. " : DepartureBnT_SearchStation - Stations        : " . Dumper($StationFound);
			Log3 $name, 5, $name. " : DepartureBnT_SearchStation -    |Place : " . sprintf("%-20.20s|", $StationFound->{place}) . " Station Name: " . $StationFound->{name};
		

			# my $StationId    = encode("utf-8",$StationFound->{id}   ,Encode::FB_CROAK);
			# my $StationPlace = encode("utf-8",$StationFound->{place},Encode::FB_CROAK);
			# my $StationName  = encode("utf-8",$StationFound->{name} ,Encode::FB_CROAK);

			# my $StationId    = encode("utf-8",$StationFound->{id}   );
			# my $StationPlace = encode("utf-8",$StationFound->{place});
			# my $StationName  = encode("utf-8",$StationFound->{name} );

			# my $StationId    = decode('UTF-8',$StationFound->{id}   );
			# my $StationPlace = decode('UTF-8',$StationFound->{place});
			# my $StationName  = decode('UTF-8',$StationFound->{name} );

			# my $StationId    = $StationFound->{id}   ;
			# my $StationPlace = $StationFound->{place};
			# my $NoOfUmlSP    = $StationPlace =~ s/[äöüÄÖÜß]/$1/g;
			# ### Log entries for debugging purposes
			# Log3 $name, 1, $name. " : DepartureBnT_SearchStation - StationPlace     : " . $StationPlace;
			# Log3 $name, 1, $name. " : DepartureBnT_SearchStation - NoOfUmlSP        : " . $NoOfUmlSP;
			# my $StationName  = $StationFound->{name} ;
			# my $NoOfUmlSN    = $StationName =~ s/[äöüÄÖÜß]/$1/g;;
			# ### Log entries for debugging purposes
			# Log3 $name, 1, $name. " : DepartureBnT_SearchStation - StationName      : " . $StationName;
			# Log3 $name, 1, $name. " : DepartureBnT_SearchStation - NoOfUmlSN        : " . $NoOfUmlSN;
			# ### Add line with station
			# $ReturnValue .= sprintf("|%-10.10s|", $StationId) . sprintf("%-30.30s|", $StationPlace) . sprintf("%-30.30s|", $StationName) . "\n";

			my $StationId    = $StationFound->{id}   ;
			my $StationPlace = $StationFound->{place};
			my $StationName  = $StationFound->{name} ;

			### Add line with station
			$ReturnValue .= sprintf("|%-10.10s|", $StationId) . sprintf("%-30.30s|", $StationPlace) . sprintf("%-30.30s|", $StationName) . "\n";
		}
	}
	return($ReturnValue);
}
####END####### Update DepartureBnT station list ########################################################################END#####

###START###### Download DepartureBnT table ############################################################################START####
sub DepartureBnT_Update($) {

	### Define variables
	my ($hash)	       = @_;
	my $name           = $hash->{NAME};
	my $StationID      = $hash->{helper}{StationId};
	my $PollingTimeout = AttrVal($name, "PollingTimeout", 5);
	my $NoOfEntries    = AttrVal($name, "NoOfEntries", 5);
	my $DepartureEntries;
	my $ReadingName;
	
	### For debugging purpose only
	Log3 $name, 5, $name. " : DepartureBnT_Update Begin___________________________________________________________________________________________________________________";
	Log3 $name, 5, $name. " : DepartureBnT_Update - StationID              : " . $StationID;
	
	### Check whether StationID has been set and if not abort this subroutine
	if ((!defined($StationID)) || ($StationID eq "None")){
		
		### Log Entry for debugging purposes
		Log3 $name, 3, $name. " : DepartureBnT_Download - StationID does not exist.";
		
		return;
	}

	### Stop internal timer
	RemoveInternalTimer($hash);

	### Check whether the DepartureBnT has been disabled
	if(IsDisabled($name))
	{
		return;
	}


	### Create Search Url
	my $StationUrl = "https://transport.stefan-biermann.de/publictransportapi/rest/departure?from=" . $StationID . "&limit=" . $NoOfEntries;
	
	### For debugging purpose only
	Log3 $name, 5, $name. " : DepartureBnT_SearchStation - SearchUrl       : " . $StationUrl;

	### Create parameter set for HttpUtils_BlockingGet
	my $param = {
					url        => $StationUrl,
					timeout    => $PollingTimeout,
					hash       => $hash,
					method     => "GET",
					header     => "agent: TeleHeater/2.2.3\r\nUser-Agent: TeleHeater/2.2.3\r\nAccept: application/json",
					callback   =>  \&DepartureBnT_UpdateResponse
				};

	
	### Get the value
	HttpUtils_NonblockingGet($param);
}

#####

sub DepartureBnT_UpdateResponse($) {
	### Define variables
    my ($param, $err, $data) = @_;
    my $hash                 = $param->{hash};
	my $name                 = $hash->{NAME};
	my $StationID            = $hash->{helper}{StationId};
	my $NoOfEntries          = AttrVal($name, "NoOfEntries", 5);
	my $DepartureEntries;
	my $ReadingName;
	my $ReadingValue;
	
	### For debugging purpose only
	Log3 $name, 5, $name. " : DepartureBnT_UpdateResponse Begin___________________________________________________________________________________________________________";

	### Log entries for debugging purposes
    Log3 $name, 5, $name. " : DepartureBnT_UpdateResponseResponse - err             : " .$err;
	Log3 $name, 5, $name. " : DepartureBnT_UpdateResponseResponse - data            : " .$data;

	eval{
		$DepartureEntries = decode_json(encode_utf8($data));
		1;
	}
	or do  {
		Log3 $name, 3, $name. " : DepartureBnT_UpdateResponseResponse - Data cannot be parsed by JSON";
	};

	### Initiate Bulk Update
	readingsBeginUpdate($hash);

	### Log entries for debugging purposes
	Log3 $name, 5, $name. " : DepartureBnT_UpdateResponseResponse - DepartureEntries       : " . Dumper(@$DepartureEntries);
	
	### Delete doubled hash entries
	my %seen;
	my @UniqueDepartureEntries =  grep({ my $e = $_; my $key = join '___', map { $e->{$_}; } sort keys %$_;!$seen{$key}++ } @$DepartureEntries);

	### Log entries for debugging purposes
	Log3 $name, 5, $name. " : DepartureBnT_UpdateResponseResponse - UniqueDepartureEntries : " . Dumper(@UniqueDepartureEntries);

	### Calculate how much entries have been deleted
	my $DeltaDepartureEntries = @$DepartureEntries - @UniqueDepartureEntries;

	### Update readings with header entries
	readingsBulkUpdate($hash, "departure_Double-Entries", $DeltaDepartureEntries, 1);	

	### Log entries for debugging purposes
	Log3 $name, 5, $name. " : DepartureBnT_UpdateResponseResponse - DeltaDepartureEntries    : " . $DeltaDepartureEntries;

	### Set first Iteration counter
	my $ReadingOrderNo = -1;

	### For every Entry in the list (array of hashes)
	foreach my $DepartureEntry( @UniqueDepartureEntries ) {

		### Log entries for debugging purposes
		Log3 $name, 5, $name. " : DepartureBnT_UpdateResponseResponse - Stations        : " . Dumper($DepartureEntry);

		### Inkrement Iteration counter
		$ReadingOrderNo++;

		### Foreach of the hash entries 
		foreach my $DepartureEntryKey (keys %$DepartureEntry) {
			
			### Ignore departureTimestamp and departureTime - Will deal with it later
			if (($DepartureEntryKey eq "departureTimestamp") || ($DepartureEntryKey eq "departureTime")){
				### Do nothing
			}
			### If Destination Name Pops up manipulate with RegEx
			elsif ($DepartureEntryKey eq "to"){

				### Create Reading name
				$ReadingName = "departure_" . sprintf("%02d", $ReadingOrderNo)  . "_Destination-long";

				### Get Value
				$ReadingValue = $DepartureEntry->{$DepartureEntryKey};

				### Update readings with header entries
				readingsBulkUpdate($hash, $ReadingName, $ReadingValue, 1);

				### Obtain RegEx from Attribute
				my $MaxLength = AttrVal($name, "MaxLength", "");
				
				### If the RegEx-String is not empty
				if (($MaxLength eq "") || ($MaxLength eq "0")){

					### Delete Reading "Destination-short"
					readingsDelete($hash, "Destination-Short");
				}
				else {
					### Log entries for debugging purposes
					Log3 $name, 5, $name. " : DepartureBnT_UpdateResponseResponse - _____________________________________________";
					Log3 $name, 5, $name. " : DepartureBnT_UpdateResponseResponse - ReadingValue before      : " . $ReadingValue;
					Log3 $name, 5, $name. " : DepartureBnT_UpdateResponseResponse - MaxLength                : " . $MaxLength;

					$ReadingValue = substr($ReadingValue, 0, $MaxLength);

					### Create Reading name
					$ReadingName = "departure_" . sprintf("%02d", $ReadingOrderNo)  . "_Destination-short";
					
					### Log entries for debugging purposes
					Log3 $name, 5, $name. " : DepartureBnT_UpdateResponseResponse - ReadingValue after       : " . $ReadingValue;

					### Update readings with header entries
					readingsBulkUpdate($hash, $ReadingName, $ReadingValue, 1);
				}

				### Log entries for debugging purposes
				Log3 $name, 5, $name. " : DepartureBnT_UpdateResponseResponse - DepartureEntryValue      : " . $DepartureEntry->{$DepartureEntryKey};
				Log3 $name, 5, $name. " : DepartureBnT_UpdateResponseResponse - ReadingValue             : " . $ReadingValue;
			}
			else {
				### Create Reading name
				$ReadingName = "departure_" . sprintf("%02d", $ReadingOrderNo)  . "_" . $DepartureEntryKey;

				### Log entries for debugging purposes
				Log3 $name, 5, $name. " : DepartureBnT_UpdateResponseResponse - DepartureEntryKey        : " . $DepartureEntryKey;
				Log3 $name, 5, $name. " : DepartureBnT_UpdateResponseResponse - DepartureEntryValue      : " . $DepartureEntry->{$DepartureEntryKey};
		
				### Update readings with header entries
				readingsBulkUpdate($hash, $ReadingName, $DepartureEntry->{$DepartureEntryKey}, 1);				
			}
		}

		### Cut off the last 3 digits of the timestamp since they are milliseconds
		my $TimeStamp = $DepartureEntry->{departureTimestamp};
		   $TimeStamp =~ s/\d{3}$//;

		### Convert in local time and correct epoch start date
		my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($TimeStamp);
		$mon  += 1;
		$year += 1900;
		
		### Format to human readable format
		my $DepartureDateLocal = sprintf("%04d",$year) . "-" . sprintf("%02d",$mon) . "-" . sprintf("%02d",$mday);
		my $DepartureTimeLocal = sprintf("%02d",$hour) . ":" . sprintf("%02d",$min);

		### Create Reading name and update readings with header entries
		$ReadingName = "departure_" . sprintf("%02d", $ReadingOrderNo)  . "_departureTime-Local";
		readingsBulkUpdate($hash, $ReadingName, $DepartureTimeLocal, 1);

		### Create Reading name and update readings with header entries
		$ReadingName = "departure_" . sprintf("%02d", $ReadingOrderNo)  . "_departureDate-Local";
		readingsBulkUpdate($hash, $ReadingName, $DepartureDateLocal, 1);

		### Convert in GM time and correct epoch start date
		   ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = gmtime($TimeStamp);
		$mon  += 1;
		$year += 1900;
		
		### Format to human readable format
		my $DepartureDateUtc = sprintf("%04d",$year) . "-" . sprintf("%02d",$mon) . "-" . sprintf("%02d",$mday);
		my $DepartureTimeUtc = sprintf("%02d",$hour) . ":" . sprintf("%02d",$min);
		
		### Create Reading name and Update Reading
		$ReadingName = "departure_" . sprintf("%02d", $ReadingOrderNo)  . "_departureTime-UTC";
		readingsBulkUpdate($hash, $ReadingName, $DepartureTimeUtc, 1);

		### Create Reading name and Update Reading
		$ReadingName = "departure_" . sprintf("%02d", $ReadingOrderNo)  . "_departureDate-UTC";
		readingsBulkUpdate($hash, $ReadingName, $DepartureDateUtc, 1);

		### Log entries for debugging purposes
		Log3 $name, 5, $name. " : DepartureBnT_UpdateResponseResponse - departure__________________________________________";
		Log3 $name, 5, $name. " : DepartureBnT_UpdateResponseResponse - departureTimestamp       : " . $TimeStamp;
		Log3 $name, 5, $name. " : DepartureBnT_UpdateResponseResponse - DepartureTimeLocal       : " . $DepartureTimeLocal;
		Log3 $name, 5, $name. " : DepartureBnT_UpdateResponseResponse - DepartureTimeUtc         : " . $DepartureTimeUtc;
	}

	### Create Reading name and Update Reading
	$ReadingName = "departure_Entries";
	readingsBulkUpdate($hash, $ReadingName, $ReadingOrderNo++ , 1);

	### Execute Readings Bulk Update
	readingsEndUpdate($hash, 1);

	### Start internal timer on next Gauge update
	InternalTimer(gettimeofday()+AttrVal($name, "UpdateInterval", 60), \&DepartureBnT_Update, $hash);

	### Refresh Browser Surface
	FW_directNotify("FILTER=".$name, "#FHEMWEB:WEB", "location.reload('true')", "");
	
	return;
}
####END####### Download DepartureBnT table #############################################################################END#####

###START###### Download Station Header Details ########################################################################START####
sub DepartureBnT_UpdateStationDetails($) {

	### Define variables
	my ($hash)	       = @_;
	my $name           = $hash->{NAME};
	my $StationID      = $hash->{helper}{StationId};
	my $PollingTimeout = AttrVal($name, "PollingTimeout", 5);
	my $Stations;
	
	### For debugging purpose only
	Log3 $name, 5, $name. " : DepartureBnT_UpdateStationDetails Begin_______________________________________________________________________________________________";
	Log3 $name, 5, $name. " : DepartureBnT_UpdateStationDetails - StationID: " . $StationID;
	
	### Check whether StationID has been set and if not abort this subroutine
	if ((!defined($StationID)) || ($StationID eq "None")){
		
		### Log Entry for debugging purposes
		Log3 $name, 3, $name. " : DepartureBnT_UpdateStationDetails - StationID does not exist.";
		
		return;
	}

	### Stop internal timer
	RemoveInternalTimer($hash);

	### Check whether the DepartureBnT has been disabled
	if(IsDisabled($name))
	{
		return;
	}

	### Create Search Url
	my $SearchUrl = "https://transport.stefan-biermann.de/publictransportapi/rest/station/suggest?q=" . $StationID;
	
	### For debugging purpose only
	Log3 $name, 5, $name. " : DepartureBnT_UpdateStationDetails - SearchUrl: " .$SearchUrl;

	### Create parameter set for HttpUtils_BlockingGet
	my $param = {
					url        => $SearchUrl,
					timeout    => $PollingTimeout,
					method     => "GET",
					header     => "agent: TeleHeater/2.2.3\r\nUser-Agent: TeleHeater/2.2.3\r\nAccept: application/json",
				};

	### Retrieve data 
	my($err, $data) = HttpUtils_BlockingGet($param);

	### Log entries for debugging purposes
    Log3 $name, 5, $name. " : DepartureBnT_UpdateStationDetails - err      : " .$err;
	Log3 $name, 5, $name. " : DepartureBnT_UpdateStationDetails - data     : " .$data;

	eval{
		$Stations = decode_json(encode_utf8($data));
		1;
	}
	or do  {
		Log3 $name, 5, $name. " : DepartureBnT_UpdateStationDetails - Data cannot be parsed by JSON";
	};

	### Log entries for debugging purposes
    Log3 $name, 5, $name. " : DepartureBnT_UpdateStationDetails - Stations : " . Dumper($Stations);

	### Initiate Bulk Update
	readingsBeginUpdate($hash);

	### For every Entry in the list (array of hashes)
	foreach my $DepartureEntry( @$Stations ) {

		### Log entries for debugging purposes
		Log3 $name, 5, $name. " : DepartureBnT_SearchStation - Stations        : " . Dumper($DepartureEntry);

		### Foreach of the hash entries 
		foreach my $DepartureEntryKey (keys %$DepartureEntry) {
			
			### Ignore the following keys
			if (($DepartureEntryKey eq "coord") || ($DepartureEntryKey eq "latAs1E6") || ($DepartureEntryKey eq "lonAs1E6")) {
				next;
			}
			my $ReadingName;
			
			### Use different Reading names for the coordinates
			if(($DepartureEntryKey eq "latAsDouble")){
				### Create Reading name
				$ReadingName = "Station_latitude";
			}
			elsif(($DepartureEntryKey eq "lonAsDouble")){
				### Create Reading name
				$ReadingName = "Station_longitude";
			}
			else {
				### Create Reading name
				$ReadingName = "Station_" . $DepartureEntryKey;
			}

			### Log entries for debugging purposes
			Log3 $name, 5, $name. " : DepartureBnT_SearchStation - DepartureEntryKey        : " . $DepartureEntryKey;
			Log3 $name, 5, $name. " : DepartureBnT_SearchStation - DepartureEntryValue      : " . $DepartureEntry->{$DepartureEntryKey};
    
			### Update readings with header entries
			readingsBulkUpdate($hash, $ReadingName, $DepartureEntry->{$DepartureEntryKey}, 1);
		}
		last;
	}

	### Execute Readings Bulk Update
	readingsEndUpdate($hash, 1);
}
####END####### Download Station Header Details #########################################################################END#####	

###START###### Display of html code preceding the "Internals"-section #########################################START####
sub DepartureBnT_FW_detailFn($$$$) {
	my ($FW_wname, $devname, $room, $extPage) = @_;
	my $hash 			  = $defs{$devname};
	my $name 			  = $hash->{NAME};
	my $latitude          = ReadingsVal($name, "Station_latitude" , "0");
	my $longitude         = ReadingsVal($name, "Station_longitude", "0");
	my $departure_Entries = ReadingsVal($name, "departure_Entries", "0");
	my $WalkTimeToStation =     AttrVal($name, "WalkTimeToStation", "0");
	my $TableLines        = $departure_Entries +2;
	my $MapHeight         = $TableLines * 40;
	my $TableHeader       = "<h1>" . ReadingsVal($name, "Station_place", "") . " - " . ReadingsVal($name, "Station_name", "") . "</h1><h3>last Update: " . ReadingsTimestamp($name,"departure_00_departureTimeInMinutes",'') . "</h3>";

	my$htmlCode = '
	<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.0 Transitional//EN">
<html>
	<head>
		<title>Busstation</title>
		<style type="text/css">
			<!-- Flashlights -->
			.container {
				display: flex;
				gap: 10px;
			}

			.light {
				width: 20px;
				height: 20px;
				border-radius: 50%;
				background-color: grey;
				opacity: 0.3;
			}

			.off {
				<!-- Do nothing -->
			}

			.AlertLeft {
				animation: AlertLeft 1.0s infinite;
			}
			
			.AlertRight {
				animation: AlertRight 1.0s infinite;
			}

			.WarningLeft {
				animation: WarningLeft 1.0s infinite;
			}
			
			.WarningRight {
				animation: WarningRight 1.0s infinite;
			}

			.OkLeft {
				animation: OkLeft 1.0s infinite;
			}
			
			.OkRight {
				animation: OkRight 1.0s infinite;
			}

			@keyframes OkLeft {
				0%, 49% { opacity: 1; background-color: lawngreen;  }
				50%, 100% { opacity: 0.3; background-color: grey;   }
			}
			
			@keyframes OkRight {
				0%, 49% { opacity: 0.3; background-color: grey;     }
				50%, 100% { opacity: 1; background-color: lawngreen;}
			}

			@keyframes WarningLeft {
				0%, 49% { opacity: 1; background-color: gold;       }
				50%, 100% { opacity: 0.3; background-color: grey;   }
			}
			
			@keyframes WarningRight {
				0%, 49% { opacity: 0.3; background-color: grey;     }
				50%, 100% { opacity: 1; background-color: gold;     }
			}

			@keyframes AlertLeft {
				0%, 49% { opacity: 1; background-color: red;        }
				50%, 100% { opacity: 0.3; background-color: grey;   }
			}
			
			@keyframes AlertRight {
				0%, 49% { opacity: 0.3; background-color: grey;     }
				50%, 100% { opacity: 1; background-color: red;      }
			}

		</style>
	</head>
	<body>
	
		<table border=8 cellspacing=1 cellpadding=6>
			<tr>
				<td align ="center" colspan="5">
					' . $TableHeader . '
				</td>				
			</tr>
			<tr>
				<td align ="center">
					<!-- Lights -->
				</td>
				<td align ="center">
					Bus<BR>Train
				</td>
				<td align ="center">
					Destination
				</td>
				<td align ="center">
					Departure<BR>in min
				</td>
				<td rowspan="' . $TableLines . '">
					<iframe width="100%" height="' . $MapHeight . '" src="https://www.openstreetmap.org/export/embed.html?bbox=' . $longitude . '%2C' . $latitude . '%2C' . $longitude . '%2C' . $latitude . '&amp;layer=transportmap&amp;marker=' . $latitude . '%2C' . $longitude . '" style="border: 1px solid black"></iframe><br/><small><a href="https://www.openstreetmap.org/?mlat=' . $latitude . '&amp;mlon=' . $longitude . '#map=18/' . $latitude . '/' . $longitude. '&amp;layers=T">Large Map</a></small>
				</td>
			</tr>
	';

	### For all entries do
	for (my $i = 0; $i < $departure_Entries; $i++) {

		### Create Prefix for Reading Name
		my $ReadingNamePrefix = "departure_" . sprintf("%02d", $i)  . "_";

		### Get Reading values
		my $LineNumber  = ReadingsVal($name, $ReadingNamePrefix . "number"                , "0");
		my $Destination = ReadingsVal($name, $ReadingNamePrefix . "Destination-long"      , "0");
		my $DepartTime  = ReadingsVal($name, $ReadingNamePrefix . "departureTime-Local"   , "0");
		my $CountDown   = ReadingsVal($name, $ReadingNamePrefix . "departureTimeInMinutes", "0");
		my $Threshold   = $CountDown + $WalkTimeToStation;
		my $LightLeft;
		my $LightRight;
	
		if ($CountDown >=0 && $CountDown < $WalkTimeToStation){
			$LightLeft  = '<div class="light AlertLeft"></div>';
			$LightRight = '<div class="light AlertRight"></div>';
		}
		elsif($CountDown >=$WalkTimeToStation && $CountDown < ($WalkTimeToStation +5)){
			$LightLeft  = '<div class="light WarningLeft"></div>';
			$LightRight = '<div class="light WarningRight"></div>';
		}
		elsif($CountDown >=($WalkTimeToStation +5) && $CountDown < ($WalkTimeToStation +10)){
			$LightLeft  = '<div class="light OkLeft"></div>';
			$LightRight = '<div class="light OkRight"></div>';			
		}
		else{
			$LightLeft  = '<div class="light Off"></div>';
			$LightRight = '<div class="light Off"></div>';
		}
	
		$htmlCode  .= '
			<tr>
				<td>
					<table border=0>
						<td align ="center">
							' . $LightLeft . '
						</td>
						<td align ="center">
							' . $LightRight . '
						</td>
					</table>
				</td>
				<td align ="center">
					' . $LineNumber  . '
				</td>
				<td align ="center">
					' . $Destination . '
				</td>
				<td align ="center">
					' . $CountDown   . '
				</td>
			</tr>';
	}

	$htmlCode  .= '
		</table>	
	</body>
</html>';

	
	return($htmlCode);		
}
1;

###START###### Description for fhem commandref ################################################################START####
=pod
=encoding utf8
=item device
=item summary    Provides Departure Data for provided stations by transport.stefan-biermann.de
=item summary_DE Abfahrtsdaten f&uuml;r Haltestellen durch von transport.stefan-biermann.de
=begin html

<a name="DepartureBnT"></a>
<a id="DepartureBnT"></a>
<h3>DepartureBnT</h3>
<ul>
	<table>
		<tr>
			<td>
				The DepartureBnT )Departure Bus and Train) module searches for stations and provides the Departure Data<BR>
			</td>
		</tr>
	</table>
	<BR>
	<table>
		<tr><td><a id="DepartureBnT-define"></a><b>Define</b></td></tr>
		<tr><td><ul><code>define &lt;name&gt; DepartureBnT</code>                                                                                                                                                                                             <BR>          </ul></td></tr>
		<tr><td><ul><ul><code>&lt;name&gt;</code> : The name of the device. Recommendation: "myDepartureBnT".                                                                                                                                                 <BR>     </ul></ul></td></tr>
	</table>                                                                                                                                                                                                                                                                                                                                                                                                                                                     
	<BR>                                                                                                                                                                                                                                                                                                                                                                                                                                                         
	<table>                                                                                                                                                                                                                                                                                                                                                                                                                                                      
		<tr><td><a id="DepartureBnT-set"></a><b>Set</b></td></tr>                                                                                                                                                                                                                                                                                                                                                                                                    
		<tr><td><ul>The set function is able to change or activate the following features as follows:                                                                                                                                                         <BR>          </ul></td></tr>
		<tr><td><ul><a id="DepartureBnT-set-SearchStation"       > </a><li><b><u><code>set SearchStations  </code></u></b> : Searches for available stations. Hint: Use place (town) and name of stations for searching.                                      <BR></li>     </ul></td></tr>
		<tr><td><ul><a id="DepartureBnT-set-Update"              > </a><li><b><u><code>set Update          </code></u></b> : Updates the available departure data.                                                                                            <BR></li>     </ul></td></tr>
	</table>                                                                                                                                                                                                                                                                                                                                                                                                                                                         
	<BR>                                                                                                                                                                                                                                                                                                                                                                                                                                                             
	<table>                                                                                                                                                                                                                                                                                                                                                                                                                                                          
		<tr><td><a id="DepartureBnT-attr"></a><b>Attributes</b></td></tr>                                                                                                                                                                                    
		<tr><td><ul>The following user attributes can be used with the DepartureBnT module in addition to the global ones e.g. <a href="#room">room</a>.                                                                                                      <BR>          </ul></td></tr>
	</table>
	<table>
		<tr><td><ul><ul><a id="DepartureBnT-attr-disable"           > </a><li><b><u><code>disable             </code></u></b> : Stopps the device from further polling.<BR>The default value is 0 = activated                                                 <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DepartureBnT-attr-NoOfEntries"       > </a><li><b><u><code>NoOfEntries         </code></u></b> : Number of departures to be indicated as readings.                                                                             <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DepartureBnT-attr-StationId"         > </a><li><b><u><code>StationId           </code></u></b> : Station Id number found with the "SearchStations" command before.                                                             <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DepartureBnT-attr-PollingTimeout"    > </a><li><b><u><code>PollingTimeout      </code></u></b> : Number of seconds, the module shall wait fore a website reaction until it gives up.The Default value is 5s.                   <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DepartureBnT-attr-UpdateInterval"    > </a><li><b><u><code>UpdateInterval      </code></u></b> : Number of seconds, the module poll the latest departure data. The Default value is 60s.                                       <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DepartureBnT-attr-MaxLength"         > </a><li><b><u><code>MaxLength           </code></u></b> : If value not 0, the module introduces a new reading "Destination-short" which limits the length by the number provided.       <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DepartureBnT-attr-WalkTimeToStation" > </a><li><b><u><code>WalkTimeToStation   </code></u></b> : Time in minutes for how long it takes from your home to the station. The Default value is 0min = Right in front of the house. <BR></li></ul></ul></td></tr>
	</table>
</ul>
=end html
=begin html_DE

<a id="DepartureBnT"></a>
<h3>DepartureBnT</h3>
<ul>
	<table>
		<tr>
			<td>
				Das DepartureBnT (Departure Bus and Train) - Modul l&aumldt die Abfahrtszeiten einer gegebenen Haltestelle<BR>
			</td>
		</tr>
	</table>
	<BR>
	<table>
		<tr><td><a id="DepartureBnT-define"></a><b>Define</b></td></tr>
		<tr><td><ul><code>define &lt;name&gt; DepartureBnT</code>                                                                                                                                                                                               <BR>          </ul></td></tr>
		<tr><td><ul><ul><code>&lt;name&gt;</code> : Der Name der Instanz. Empfehlung: "myDepartureBnT".                                                                                                                                                         <BR>     </ul></ul></td></tr>
	</table>                                                                                                                                                                                                                                                                                                                                                                                                                                                   
	<BR>                                                                                                                                                                                                                                                                                                                                                                                                                                                       
	<table>                                                                                                                                                                                                                                                                                                                                                                                                                                                    
		<tr><td><a id="DepartureBnT-set"></a><b>Set</b></td></tr>                                                                                                                                                                                                                                                                                                                                                                                                  
		<tr><td><ul>Die Set Funktion l&ouml;st folgende Aktionen aus:                                                                                                                                                                                           <BR>          </ul></td></tr>
		<tr><td><ul><a id="DepartureBnT-set-SearchStation"       > </a><li><b><u><code>set SearchStations  </code></u></b> : Sucht nach einer verfügbaren Haltestelle. Tipp: Verwende Ort und name der Haltestelle.                                             <BR></li>     </ul></td></tr>
		<tr><td><ul><a id="DepartureBnT-set-Update"              > </a><li><b><u><code>set Update          </code></u></b> : L&auml;dt die neusten Abfahrtszeiten.                                                                                              <BR></li>     </ul></td></tr>
	</table>                                                                                                                                                                                                                                                                                                                                                                                                                                                       
	<BR>                                                                                                                                                                                                                                                                                                                                                                                                                                                           
	<table>                                                                                                                                                                                                                                                                                                                                                                                                                                                        
		<tr><td><a id="DepartureBnT-attr"></a><b>Attributes</b></td></tr>
		<tr><td><ul>Die folgenden Attribute k&ouml;nnen neben den globalen Attributen gesetzt werden z.B.: <a href="#room">room</a>.                                                                                                                            <BR>          </ul></td></tr>
	</table>
	<table>
		<tr><td><ul><ul><a id="DepartureBnT-attr-disable"           > </a><li><b><u><code>disable             </code></u></b> : Unterbricht das erneute Laden der Abfahrtszeiten.<BR>Der Default Wert ist 0 = activated                                         <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DepartureBnT-attr-NoOfEntries"       > </a><li><b><u><code>NoOfEntries         </code></u></b> : Anzahl der zuk&uuml;ftigen Abfahrten welche angezeigt werden sollen.                                                            <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DepartureBnT-attr-StationId"         > </a><li><b><u><code>StationId           </code></u></b> : Haltestellennummer welche yuvor mit dem Befehl "SearchStations" gefunden wurde.                                                 <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DepartureBnT-attr-PollingTimeout"    > </a><li><b><u><code>PollingTimeout      </code></u></b> : Anzahl der Sekunden wie lange das Modul auf eine Antwort seitens der Webseite warten soll.<BR>Der Default value is 5s.          <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DepartureBnT-attr-UpdateInterval"    > </a><li><b><u><code>UpdateInterval      </code></u></b> : Interval in  Sekunden mit der die Abfahrtszeiten erneut heruntergeladen werden sollen.<BR>Der Default Wert ist 60s.             <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DepartureBnT-attr-MaxLength"         > </a><li><b><u><code>MaxLength           </code></u></b> : Wenn der Wert nicht 0 ist, wird das Modul ein weiteres Reading "Destination-short" einf&uuml;hren und die L&auml;nge begrenzen. <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DepartureBnT-attr-WalkTimeToStation" > </a><li><b><u><code>WalkTimeToStation   </code></u></b> : Anzahl der Minuten die es ben&ouml;tigt um vom eigenen Haus zur Station zu kommen.                                              <BR></li></ul></ul></td></tr>

	</table>
</ul>



=end html_DE
=for :application/json;q=META.json 73_DepartureBnT.pm
{
	"abstract"                       : "Provides Departure Data for provided stations by transport.stefan-biermann.de",
	"description"                    : "The Webpage transport.stefan-biermann.de provides detailed departure data and station details.",
    "version"                        : "1.00",
	"name"                           : "73_DepartureBnT.pm",
	"meta-spec": {
		"version"                    : "1",
		"url"                        : "http://search.cpan.org/perldoc?CPAN::Meta::Spec"
	},	
	"x_lang": {
		"de": {
			"abstract"               : "Stellt Abfahrtsdaten f&uuml;r Haltestellen bereitgestellt von transport.stefan-biermann.de.",
			"description"            : "Die Webseite transport.stefan-biermann.de stellt detaillierte Abfahrtszeiten und Stationsdetails zur Verf&uuml;gung"
		}
	},
	"license"                        : ["GPL_2"],
	"author"                         : ["Matthias Deeke <matthias.deeke@deeke.eu>"],
	"x_fhem_maintainer"              : ["Sailor"],
	"keywords"                       : ["DepartureBnT", "Abfahrtszeiten", "Departure"],
	"prereqs": {
		"runtime": {
			"requires": {
				"constant"           : 0,
				"perl"               : 5.014,
				"strict"             : 0,
				"utf8"               : 0,
				"warnings"           : 0,
				"Encode"             : 0,
				"Time"               : 0,
				"FHEM"               : 0,
				"Data"               : 0,
				"POSIX"              : 0
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
			},
			"recommends": {
			},
			"suggests": {
			}
		}
	},
	"x_resources": {
		"x_homepage": "https://transport.stefan-biermann.de/publictransportapi/rest/station/suggest?q=Koeln&limit=12",
		"x_homepage_title": "Abfahrtszeiten als API",
	    "x_license": ["GNU General Public License"],
		"x_support_community": {
			"rss"                    : "",
			"web"                    : "https://forum.fhem.de/index.php?topic=143906.msg",
			"subCommunity" : {
				"rss"                : "",
				"title"              : "This sub-board will be first contact point",
				"web"                : "https://forum.fhem.de/index.php?topic=143906.msg"
			}
		},
		"x_wiki" : {
			"title"                  : "",
			"web"                    : ""
		}
	},
	"x_support_status"               : "supported"
}
=end :application/json;q=META.json
=cut