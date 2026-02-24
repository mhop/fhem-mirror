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
								  "ShowDetails:Fhem,Departure " .
								  "StationId " .
								  "PollingTimeout " .
								  "MaxLength " .
								  "WalkTimeToStation " .
								  "ConcatReading:0,1 " .
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
	elsif ($a[2] eq "StationId") 
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
	
	### Check whether "ConcatReading" attribute has been provided
	elsif ($a[2] eq "ConcatReading") 
	{
		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DepartureBnT_Attr - ConcatReading            : " . $a[3];
		
		### Delete all Readings
		DepartureBnT_DeleteAllReadings($hash);

		### Update Header
		DepartureBnT_UpdateStationDetails($hash);
		
		### Update all Departures
		DepartureBnT_Update($hash);
	}
	
	### Check whether "ShowDetails" attribute has been provided
	elsif ($a[2] eq "ShowDetails") 
	{
		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : DepartureBnT_Attr - ShowDetails              : " . $a[3];
		
		### Update all Departures
		DepartureBnT_Update($hash);
	}
	
	### Check whether "UpdateInterval" attribute has been provided
	elsif ($a[2] eq "UpdateInterval") 
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
		Log3 $name, 4, $name. " : DepartureBnT - The attribute MaxLength was missing and has been set to 0s = deactivated";
	}

	if(!defined($attr{$name}{WalkTimeToStation})) {
		### Set attribute with standard value since it is not available
		$attr{$name}{WalkTimeToStation} = 1;

		### Writing log entry
		Log3 $name, 4, $name. " : DepartureBnT - The attribute WalkTimeToStation was missing and has been set to 1 = Right in front the house";
	}

	if(!defined($attr{$name}{ConcatReading})) {
		### Set attribute with standard value since it is not available
		$attr{$name}{ConcatReading} = 0;

		### Writing log entry
		Log3 $name, 4, $name. " : DepartureBnT - The attribute ConcatReading was missing and has been set to 0 = Disabled";
	}
	
	if(!defined($attr{$name}{ShowDetails})) {
		### Set attribute with standard value since it is not available
		$attr{$name}{ShowDetails} = "Departure";

		### Writing log entry
		Log3 $name, 4, $name. " : DepartureBnT - The attribute ShowDetails was missing and has been set to Departure = Extended View";
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
	my $ConcatReadingValue;
	my @ConcatList;
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
					readingsDelete($hash, "departure_" . sprintf("%02d", $ReadingOrderNo) . "_Destination-short");
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

		####### Create ConcatList for compatibility to FTUI Widget Departure https://wiki.fhem.de/wiki/FTUI_Widget_Departure #######
		$ConcatList[$ReadingOrderNo]= '["' . $DepartureEntry->{number} . '","' . $DepartureEntry->{to} . '","' . $DepartureEntry->{departureTimeInMinutes} . '"]';
	}

	### Create ReadingValue for compatibility to FTUI Widget Departure if attribute is enabled
	if (AttrVal($name, "ConcatReading", "") == 1){
		$ConcatReadingValue ='[' . join(',' , @ConcatList) . ']';
		readingsBulkUpdate($hash, "departure_concat", $ConcatReadingValue , 1);
	}

	### Create Reading name and Update Reading
	$ReadingOrderNo++;
	readingsBulkUpdate($hash, "departure_Entries", $ReadingOrderNo , 1);

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
	my $htmlCode;

	### Definition of Icons
	my $IconBus           = '<svg version="1.1" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 122.88 120.96"   ><defs><style>.cls-1{fill-rule:evenodd;}</style></defs><title>Bus            </title><path class="cls-1" d="M105.5,104.64H99.44v9.53A6.81,6.81,0,0,1,92.65,121h-4a6.82,6.82,0,0,1-6.79-6.79v-9.53H40.82v9.53A6.82,6.82,0,0,1,34,121H30a6.81,6.81,0,0,1-6.78-6.79v-9.53H18.1c-3.54-.06-5.24-2-5.5-5.29V21.52c-2,.2-2.95.66-3.43,1.68V45.45H4.87A4.88,4.88,0,0,1,0,40.58V27.44a4.89,4.89,0,0,1,4.73-4.87c.41-3.82,2.06-4.93,8-5.21Q14,7.36,26.36,2.57C44.09-.68,77.73-1,96.52,2.57c8.28,3.19,12.8,8.12,13.62,14.79,6,.3,7.61,1.42,8,5.21a4.89,4.89,0,0,1,4.73,4.87V40.58A4.88,4.88,0,0,1,118,45.45h-4.3V23.14c-.48-1-1.47-1.44-3.43-1.63V98.59c0,4.46-1.44,6-4.78,6ZM16.13,84.87l.28-6.69c.16-1.17.78-1.69,1.89-1.5A129.9,129.9,0,0,1,34.39,86.85c1.09.72.66,2.11-.78,1.85L18.48,87.6a2.74,2.74,0,0,1-2.35-2.73ZM52,93.45H71.3a.94.94,0,0,1,.94.94v3.24a.94.94,0,0,1-.94.94H52a.94.94,0,0,1-.94-.94V94.39a.94.94,0,0,1,.94-.94Zm50.35,0A2.51,2.51,0,1,1,99.82,96a2.51,2.51,0,0,1,2.5-2.51Zm-82.65,0A2.51,2.51,0,1,1,17.16,96a2.51,2.51,0,0,1,2.51-2.51Zm87.08-8.63-.28-6.69c-.16-1.17-.78-1.69-1.88-1.5a129.28,129.28,0,0,0-16.1,10.17c-1.09.72-.66,2.11.78,1.85l15.13-1.1a2.73,2.73,0,0,0,2.35-2.73ZM48.19,6.11h26.5a1.63,1.63,0,0,1,1.62,1.62V12a1.63,1.63,0,0,1-1.62,1.62H48.19A1.63,1.63,0,0,1,46.57,12V7.73a1.63,1.63,0,0,1,1.62-1.62ZM20.32,18.91H102.2a2,2,0,0,1,2,2V64.09c0,1.08-.89,1.69-2,2-28.09,8.53-53.8,8.18-81.88,0-1.11-.3-2-.9-2-2V20.89a2,2,0,0,1,2-2Z"/></svg>';
	my $IconTram          = '<svg version="1.1" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 80.33 122.88"    ><defs><style>.cls-1{fill-rule:evenodd;}</style></defs><title>Tram           </title><path class="cls-1" d="M23.63,15h1.31L22.73,7.67l-.07-.24H18A3.72,3.72,0,0,1,18,0H62.33a3.72,3.72,0,0,1,0,7.43H57.67l-.06.24L55.39,15h.5c5.29,0,11.71,6.85,12.79,12L80.21,81.93c1.09,5.17-5.65,12.64-10.94,12.64H17.48C5,94.57-2.35,92,.69,76.93l10-49.39c1-5.2,7.7-12.52,13-12.52ZM30.4,7.43,32.69,15h15l2.29-7.59ZM8.56,122.88l8.93-20.72h11l-2.95,6.65H55.14l-3-6.84H62.93l8.84,20.53H61.12L58,115.66H22.34l-2.95,7.22Zm17.33-49A7.14,7.14,0,1,1,18.75,81a7.13,7.13,0,0,1,7.14-7.13Zm7.58-52.14H46.33a.6.6,0,0,1,.6.6v6a.6.6,0,0,1-.6.6H33.47a.6.6,0,0,1-.6-.6v-6a.6.6,0,0,1,.6-.6ZM9.35,67.23l7-31.43H63.87l6.58,31.43Zm44.56,6.65A7.14,7.14,0,1,1,46.78,81a7.13,7.13,0,0,1,7.13-7.13Z"/></svg>';
	my $IconTrainRegional = '<svg version="1.1" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 50 50"           ><defs><style>.cls-1{fill-rule:evenodd;}</style></defs><title>Regional Train </title><path class="cls-1" d="M34.641 37.807l-.113-.216.057-.081.057-.081c1.051-.434 2.006-.971 2.861-1.604.854-.64 1.426-1.574 1.721-2.809l.215-.988v-25.521c0-.616-.184-1.255-.547-1.905-.363-.661-.816-1.252-1.365-1.777-.543-.52-1.148-.961-1.824-1.311-.676-.344-1.32-.514-1.939-.514h-18.265c-.583 0-1.212.16-1.885.487-.675.328-1.294.747-1.854 1.257-.562.505-1.027 1.08-1.39 1.713-.364.645-.547 1.267-.547 1.89v25.901c0 .436.115.891.327 1.363.22.474.492.917.818 1.331.326.426.685.807 1.067 1.15s.753.627 1.118.844c.176.074.499.188.957.333.448.144.658.251.624.321l-7.476 11.346h4.361l5.457-7.909h15.055l5.451 7.909h4.418l-7.359-11.129zm-14.347-34.628c0-.183.087-.37.273-.575.179-.199.36-.295.545-.295h6.982c.07 0 .221.07.438.213.215.146.324.291.324.436v2.672c0 .183-.092.351-.271.49-.184.15-.35.226-.49.226h-7.035l-.222-.173c-.105-.07-.227-.166-.353-.301-.128-.122-.191-.256-.191-.401v-2.292zm-7.037 7.472c0-.363.086-.719.247-1.066.162-.345.373-.66.627-.955.256-.292.556-.521.898-.704.348-.184.705-.274 1.068-.274h16.963c.322 0 .65.076.977.214.328.146.627.35.902.602.274.252.489.532.655.822.162.284.242.596.242.923v5.783c0 .328-.088.638-.27.95-.182.317-.418.591-.709.827-.295.232-.598.424-.928.564-.326.155-.654.22-.979.22h-16.744l-.276-.049c-.144-.038-.256-.074-.329-.113-.615-.106-1.159-.435-1.633-.982-.474-.546-.711-1.144-.711-1.797v-4.965zm5.049 22.526c-.563.581-1.268.871-2.1.871-.837 0-1.52-.29-2.05-.871-.526-.58-.789-1.294-.789-2.131 0-.763.274-1.424.821-1.986.544-.565 1.217-.851 2.018-.851.832 0 1.536.27 2.1.789.564.533.845 1.226.845 2.105 0 .801-.281 1.494-.845 2.074zm12.489 0c-.562-.58-.848-1.294-.848-2.131 0-.838.299-1.515.9-2.048.602-.52 1.301-.789 2.104-.789.83 0 1.516.285 2.043.851.525.562.793 1.224.793 1.986 0 .837-.275 1.551-.82 2.131-.549.581-1.236.871-2.076.871-.834 0-1.534-.29-2.096-.871z"/></svg>';
	my $IconTrainIce      = '<svg version="1.1" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 538.043 538.043" ><defs><style>.cls-1{fill-rule:evenodd;}</style></defs><title>ICE            </title><path class="cls-1" d="M399.495,480.568c-8.728,3.336-17.827,6.038-27.321,7.963l61.959,47.144c2.056,1.59,4.484,2.344,6.911,2.344 c3.443,0,6.863-1.554,9.111-4.508c3.826-5.046,2.87-12.208-2.188-16.057L399.495,480.568z"/> <path d="M90.084,517.478c-5.046,3.838-6.014,11.012-2.188,16.057c2.248,2.953,5.667,4.508,9.111,4.508 c2.427,0,4.854-0.765,6.923-2.332l61.947-47.144c-9.494-1.937-18.592-4.651-27.321-7.987L90.084,517.478z"/> <path d="M473.948,353.602c-7.82-62.162-11.048-163.948-7.186-226.887c1.805-29.006-8.836-57.391-30.023-79.953 C408.809,17.062,365.981,0,319.207,0H218.82c-46.774,0-89.614,17.062-117.532,46.774C80.125,69.336,69.472,97.72,71.277,126.715 c3.862,62.951,0.645,164.725-7.174,226.923c-3.635,29.198,5.464,57.87,25.587,80.623c26.257,29.724,68.128,46.774,114.842,46.774 h128.951c46.714,0,88.586-17.05,114.842-46.774C468.484,411.496,477.559,382.848,473.948,353.602z M117.991,62.449 c23.626-25.145,60.38-39.564,100.853-39.564h100.375c40.473,0,77.227,14.419,100.853,39.564 c16.93,18.054,25.168,39.636,23.841,62.437c-13.284,86.075-51.222,113.384-51.545,113.587c-5.225,3.491-6.66,10.498-3.24,15.735 c2.2,3.384,29.305,29.999,56.219,35.69c0.55,9.123,1.184,18.042,1.853,26.651c-6.72,11.514-45.985,66.765-178.164,66.765 c-132.131,0-171.421-55.203-178.176-66.765c0.682-8.453,1.291-17.265,1.841-26.233c26.926-5.572,54.151-32.761,56.315-36.192 c3.288-5.189,1.817-12.1-3.216-15.591c-0.394-0.251-38.345-27.56-51.64-113.635C92.81,102.097,101.06,80.504,117.991,62.449z M333.507,458.126H204.544c-40.174,0-75.768-14.204-97.685-39.038c-15.95-18.042-22.885-39.708-20.027-62.616 c0.645-5.237,1.244-10.797,1.841-16.512c16.297,24.164,61.385,66.251,180.34,66.251s164.043-42.087,180.34-66.275 c0.598,5.727,1.22,11.287,1.841,16.512c2.846,22.933-4.089,44.598-20.039,62.64C409.263,443.922,373.681,458.126,333.507,458.126z" /> <path d="M131.896,165.395c7.198,36.037,42.948,65.342,79.678,65.342h114.902c36.718,0,72.48-29.305,79.666-65.342l6.229-31.099 c3.683-18.365-0.299-35.798-11.227-49.141c-10.952-13.331-27.273-20.673-45.997-20.673H182.915 c-18.712,0-35.045,7.341-45.997,20.673c-10.928,13.343-14.91,30.776-11.239,49.141L131.896,165.395z"/> <path d="M207.88,268.029c-1.805-4.173-5.918-6.851-10.486-6.851h-31.876c-3.874,0-7.473,1.937-9.589,5.189 c-2.116,3.24-2.451,7.329-0.897,10.856l28.66,65.402c1.83,4.173,5.943,6.851,10.486,6.851h31.9c0.096,0,0.167,0,0.215,0 c6.325,0,11.466-5.129,11.466-11.442c0-2.451-0.753-4.675-2.044-6.54L207.88,268.029z"/> <path d="M372.533,261.178h-31.876c-4.567,0-8.68,2.69-10.498,6.851l-28.672,65.378c-1.554,3.551-1.196,7.64,0.909,10.868 c2.104,3.228,5.727,5.201,9.577,5.201h31.9c4.555,0,8.669-2.702,10.486-6.851l28.66-65.402c1.554-3.527,1.231-7.628-0.897-10.856 C380.006,263.116,376.395,261.178,372.533,261.178z"/> <path d="M269.025,413.289c-11.036,0-20.015,9.039-20.015,20.123c0,11.036,8.979,20.015,20.015,20.015 c11.036,0,20.015-8.979,20.015-20.015C289.041,422.328,280.061,413.289,269.025,413.289z"/> </svg>';
	my $IconTaxi          = '<svg version="1.1" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"         ><defs><style>.cls-1{fill-rule:evenodd;}</style></defs><title>Taxi           </title><path class="cls-1" d="M34.313,250.891c2.297-5.016,6.688-13.281,14.438-27.813c3.531-6.672,7.5-14.047,11.563-21.625H24.719 C11.063,201.453,0,212.516,0,226.188c0,13.641,11.063,24.703,24.719,24.703H34.313z"/> <path class="st0" d="M487.281,201.453h-35.594c4.078,7.578,8.031,14.953,11.563,21.625c7.75,14.531,12.125,22.797,14.438,27.813 h9.594c13.656,0,24.719-11.063,24.719-24.703C512,212.516,500.938,201.453,487.281,201.453z"/> <path class="st0" d="M39.391,465.188c0,18.406,14.938,33.328,33.328,33.328c18.406,0,33.313-14.922,33.313-33.328v-31.516H39.391 V465.188z"/> <path class="st0" d="M405.938,465.188c0,18.406,14.938,33.328,33.344,33.328s33.328-14.922,33.328-33.328v-31.516h-66.672V465.188z "/> <path class="st0" d="M467.875,257.109c1.688,0.484-61.688-115.828-64.719-122.109c-8-16.672-27.781-26.703-47.063-26.703 c-22.281,0-84.344,0-84.344,0s-93.563,0-115.859,0c-19.297,0-39.031,10.031-47.047,26.703 c-3.031,6.281-66.391,122.594-64.719,122.109c0,0-20.5,20.438-22.063,22.063c-8.625,9.281-8,17.297-8,25.313c0,0,0,75.297,0,92.563 c0,17.281,3.063,26.734,23.438,26.734h437c20.375,0,23.469-9.453,23.469-26.734c0-17.266,0-92.563,0-92.563 c0-8.016,0.594-16.031-8.063-25.313C488.406,277.547,467.875,257.109,467.875,257.109z M96.563,221.422 c0,0,40.703-73.313,43.094-78.109c4.125-8.203,15.844-14.141,27.828-14.141h177.031c12,0,23.703,5.938,27.828,14.141 c2.406,4.797,43.109,78.109,43.109,78.109c3.75,6.75,0.438,19.313-10.672,19.313H107.219 C96.109,240.734,92.813,228.172,96.563,221.422z M91.125,384.469c-20.656,0-37.406-16.734-37.406-37.391 c0-20.672,16.75-37.406,37.406-37.406s37.391,16.734,37.391,37.406C128.516,367.734,111.781,384.469,91.125,384.469z M312.781,394.578c0,2.734-2.219,4.953-4.938,4.953H204.172c-2.734,0-4.953-2.219-4.953-4.953v-45.672 c0-2.703,2.219-4.906,4.953-4.906h103.672c2.719,0,4.938,2.203,4.938,4.906V394.578z M420.875,384.469 c-20.656,0-37.422-16.734-37.422-37.391c0-20.672,16.766-37.406,37.422-37.406s37.406,16.75,37.406,37.406 S441.531,384.469,420.875,384.469z"/> <path class="st0" d="M152.906,49.25c0.016-10.047,8.172-18.203,18.219-18.219h169.75c10.031,0.016,18.188,8.172,18.203,18.219 v49.172h17.547V49.25c0-19.75-16-35.75-35.75-35.766h-169.75c-19.75,0.016-35.75,16.016-35.766,35.766v49.172h17.547V49.25z"/> <path class="st0" d="M195.141,92.938h8.891c0.438,0,0.719-0.266,0.719-0.672V56.328c0-0.281,0.156-0.422,0.406-0.422h12.063 c0.406,0,0.719-0.266,0.719-0.672v-7.469c0-0.406-0.313-0.688-0.719-0.688h-35.25c-0.438,0-0.719,0.281-0.719,0.688v7.469 c0,0.406,0.281,0.672,0.719,0.672h12.047c0.281,0,0.422,0.141,0.422,0.422v35.938C194.438,92.672,194.719,92.938,195.141,92.938z" /> <path class="st0" d="M237.438,47.078c-0.5,0-0.781,0.281-0.922,0.688l-16.391,44.5c-0.156,0.406,0,0.672,0.469,0.672h9.203 c0.484,0,0.766-0.203,0.906-0.672l2.672-8.031h16.688l2.719,8.031c0.156,0.469,0.438,0.672,0.938,0.672h9.094 c0.5,0,0.625-0.266,0.5-0.672l-16.125-44.5c-0.156-0.406-0.406-0.688-0.922-0.688H237.438z M247.25,75.813h-11l5.406-16.047h0.203 L247.25,75.813z"/> <path class="st0" d="M269.844,92.938h9.688c0.625,0,0.906-0.203,1.188-0.672l8.531-13.969h0.219l8.5,13.969 c0.281,0.469,0.531,0.672,1.188,0.672h9.734c0.516,0,0.641-0.406,0.453-0.813l-14.313-22.859l13.297-21.375 c0.234-0.406,0.078-0.813-0.406-0.813h-9.734c-0.563,0-0.844,0.203-1.141,0.688l-7.578,12.391h-0.219l-7.563-12.391 c-0.266-0.484-0.547-0.688-1.125-0.688h-9.75c-0.469,0-0.625,0.406-0.406,0.813l13.266,21.375l-14.234,22.859 C269.156,92.531,269.359,92.938,269.844,92.938z"/> <path class="st0" d="M320.422,47.766v44.5c0,0.406,0.281,0.672,0.688,0.672h8.922c0.406,0,0.688-0.266,0.688-0.672v-44.5 c0-0.406-0.281-0.688-0.688-0.688h-8.922C320.703,47.078,320.422,47.359,320.422,47.766z"/></svg>';
	my $IconUnknown       = '<svg version="1.1" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 469 469"         ><defs><style>.cls-1{fill-rule:evenodd;}</style></defs><title>Unknown        </title><path class="cls-1" d="M 809,1820 C 205,1745 -161,1123 70,567 224,197 616,-37 1005,9 c 456,54 790,406 812,858 17,335 -134,630 -415,814 -165,108 -400,163 -593,139 z m 306,-155 c 203,-55 385,-203 484,-395 63,-120 85,-213 85,-355 0,-141 -16,-211 -74,-333 C 1503,357 1310,205 1067,153 978,135 792,140 705,164 561,204 410,302 314,418 249,496 179,636 155,735 c -23,94 -23,267 0,360 39,160 153,336 276,430 82,61 224,129 314,149 87,19 283,15 370,-9 z" id="path8" /> </g> <g id="text2989" fill="#000000" stroke="none"> <path d="m 216.47819,309.81169 c -0.12157,-4.37349 -0.18232,-7.65367 -0.18223,-9.84052 -9e-5,-12.87764 1.82223,-23.99378 5.46696,-33.34846 2.67264,-7.04619 6.98546,-14.15323 12.93847,-21.32114 4.37346,-5.22385 12.2398,-12.84721 23.59904,-22.87012 11.35899,-10.02259 18.73938,-18.01042 22.14119,-23.9635 3.40151,-5.95273 5.10234,-12.45233 5.1025,-19.49883 -1.6e-4,-12.75603 -4.98116,-23.96328 -14.94303,-33.6218 -9.96214,-9.65806 -22.17167,-14.4872 -36.62863,-14.48744 -13.97121,2.4e-4 -25.63404,4.3738 -34.98854,13.1207 -9.35463,8.74736 -15.48977,22.41474 -18.40543,41.0022 l -33.71292,-4.00911 c 3.03718,-24.90481 12.05766,-43.97841 27.06145,-57.22084 15.00371,-13.24193 34.83661,-19.86302 59.49875,-19.86329 26.11979,2.7e-4 46.95496,7.10731 62.50557,21.32114 15.55028,14.21434 23.32551,31.40487 23.3257,51.57166 -1.9e-4,11.66303 -2.73367,22.41471 -8.20044,32.25506 -5.46714,9.84069 -16.15807,21.80724 -32.07283,35.8997 -10.69109,9.47619 -17.67664,16.46174 -20.95668,20.95668 -3.2803,4.49516 -5.71006,9.6584 -7.28928,15.48972 -1.57947,5.83151 -2.49063,15.30757 -2.73348,28.42819 z m -2.00455,65.78575 0,-37.35756 37.35756,0 0,37.35756 z" id="path2994" /> </svg>';

	### If the Details shall be the Departure Board with Map
	if (AttrVal($name, "ShowDetails","Fhem") eq "Departure"){

		$htmlCode = '
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
						<td align ="center" colspan="7">
							' . $TableHeader . '
						</td>				
					</tr>
					<tr>
						<td align ="center">
							<!-- Lights -->
						</td>				
						<td align ="center" colspan="2">
							Vehicle
						</td>
						<td align ="center">
							Destination
						</td>
						<td align ="center">
							Departure<BR>in min
						</td>
						<td align ="center">
							Delayed<BR>in min
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
			my $Delayed     = ReadingsVal($name, $ReadingNamePrefix . "departureDelay"        , "0");
			my $Threshold   = $CountDown + $WalkTimeToStation;
			my $LightLeft;
			my $LightRight;
			my $VehicleIcon;
		
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

			my $ProductName = ReadingsVal($name, $ReadingNamePrefix . "product", "0");

			if($ProductName eq "BUS"){
				$VehicleIcon = $IconBus;
			}
			elsif ($ProductName eq "SUBURBAN_TRAIN"){
				$VehicleIcon = $IconTram ;
			}
			elsif ($ProductName eq "HIGH_SPEED_TRAIN"){
				$VehicleIcon = $IconTrainIce;
			}
			elsif ($ProductName eq "REGIONAL_TRAIN"){
				$VehicleIcon = $IconTrainRegional;
			}
			elsif ($ProductName eq "ON_DEMAND"){
				$VehicleIcon = $IconTaxi;
			}
			else {
				$VehicleIcon = $IconUnknown;			
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
					<td>
						' . $VehicleIcon . '
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
					<td align ="center">
						' . $Delayed     . '
					</td>
					
				</tr>';
		}

		$htmlCode  .= '
				</table>	
			</body>
		</html>';
	}
	### If the Details shall be the fhem Standard
	else{
		
	}

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
		<tr><td><ul><ul><a id="DepartureBnT-attr-WalkTimeToStation" > </a><li><b><u><code>WalkTimeToStation   </code></u></b> : Time in minutes for how long it takes from your home to the station. The Default value is 0min = Right in front of the house.<BR>This attribute is influencing the visualisation for the departure.<BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DepartureBnT-attr-ConcatReading"     > </a><li><b><u><code>ConcatReading       </code></u></b> : Whether the Reading "departure_concat" for the <a href="https://wiki.fhem.de/wiki/FTUI_Widget_Departure">FTUI Widget Departure</a>  shall be generated.<BR>The Default value is 0 = Disabled<BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DepartureBnT-attr-ShowDetails"       > </a><li><b><u><code>ShowDetails         </code></u></b> : Which kind of Details Page shall be presented within FHEMEB - The fhem or Departure Version.<BR>The Default value is Departure = Departure Board with Map<BR></li></ul></ul></td></tr>
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
		<tr><td><ul><ul><a id="DepartureBnT-attr-WalkTimeToStation" > </a><li><b><u><code>WalkTimeToStation   </code></u></b> : Anzahl der Minuten die es ben&ouml;tigt um vom eigenen Haus zur Station zu kommen.<BR>Dieses Attribut beeinflu&szlig;t die Visualisierung.<BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DepartureBnT-attr-ConcatReading"     > </a><li><b><u><code>ConcatReading       </code></u></b> : Erzeuge das Reading "departure_concat" f&uuml;r die Kompatibilit&auml;t zu <a href="https://wiki.fhem.de/wiki/FTUI_Widget_Departure">FTUI Widget Departure</a>  shall be generated.<BR>Der Default Wert is 0 = Deaktiviert<BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="DepartureBnT-attr-ShowDetails"       > </a><li><b><u><code>ShowDetails         </code></u></b> : Welche Details Seite soll in FHEMEB angezeigt werden - Die fhem oder Departure Version.<BR>Der Default Wert ist Departure = Abfahrtstafel mit Karte<BR></li></ul></ul></td></tr>
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