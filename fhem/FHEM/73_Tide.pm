# $Id$
########################################################################################################################
#
#     73_Tide.pm
#     Reads the Tide Data for a given station in Germany provided by Bundesamt für Seeschifffahrt und Hydrographie (BSH)  
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
#     fhem.cfg: define <devicename> Tide
#
#     Example:
#     define myTide Tide
#
########################################################################################################################

########################################################################################################################
# https://www.bsh.de/DE/Das_BSH/Gebuehren_Preise/Gebuehren_und_Preise/_Anlagen/Downloads/Entgeltverzeichnis-digitale-Daten.pdf?__blob=publicationFile&v=6
# Entgeltverzeichnis für digitale Daten des Bundesamtes für Seeschifffahrt und Hydrographie Entgeltverzeichnis 
# Stand 01/25
#
# Anlage 2 - Allgemeine Geschäftsbedingungen (AGB) zur Abgabe von digitalen Daten des BSH mit einem einfachen 
# Nutzungsrecht
#
# Anlage 4 - Gesonderte Nutzungsbedingungen des BSH für digitale Gezeitendaten
#
# Für die Nutzung von digitalen Gezeitendaten des BSH gelten die „Allgemeinen Geschäftsbedingungen (AGB) zur Abgabe von 
# digitalen Daten des BSH mit einem einfachen Nutzungsrecht“, soweit hier keine speziellen Nutzungsbedingungen geregelt 
# sind.
#
# Die Nutzung der digitalen Gezeitendaten ist entgeltfrei. 
# Dies schließt die kommerzielle Nutzung und Veröffentlichung mit ein. 
# Es bedarf hierzu keiner schriftlichen Zustimmung  des BSH.
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
my %Tide_gets;
my %Tide_sets;

###START###### Initialize module ##############################################################################START####
sub Tide_Initialize($) {
    my ($hash)  = @_;
	
    $hash->{STATE}				= "Init";
    $hash->{DefFn}				= "Tide_Define";
    $hash->{UndefFn}			= "Tide_Undefine";
    $hash->{GetFn}           	= "Tide_Get";
	$hash->{SetFn}           	= "Tide_Set";
    $hash->{AttrFn}				= "Tide_Attr";
	$hash->{FW_detailFn}        = "Tide_FW_detailFn";
	$hash->{NotifyOrderPrefix}	= "50-";

	$hash->{AttrList}       	= "disable:0,1 " .
								  "NoOfForcast:slider,1,1,20 " .
								  "GaugeInterval:slider,180,60,3600 " .
								  "ShowTerminology:on,off " .
								  "ShowGaugeChart:on,off " .
								  $readingFnAttributes;
	
	return FHEM::Meta::InitMod( __FILE__, $hash );
}
####END####### Initialize module ###############################################################################END#####


###START###### Activate module after module has been used via fhem command "define" ###########################START####
sub Tide_Define($$) {
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
	Log3 $name, 5, $name. " : Tide - Starting to define module";

	
	### Download Tide Stations
	Tide_Stations($hash);
	
	### Proceed with Initialization as soon fhem is initialized
	# https://forum.fhem.de/index.php/topic,130351.msg1246281.html#msg1246281
	# Die InternalTimer Eintraege werden erst abgearbeitet, wenn $init_done = 1 ist.
	InternalTimer(0, \&Tide_Startup, $hash );

	
	### Write log information
	Log3 $name, 4, $name. " has been defined.";
	
	return;
}
####END####### Activate module after module has been used via fhem command "define" ############################END#####


###START###### Deactivate module module after "undefine" command by fhem ######################################START####
sub Tide_Undefine($$) {
	my ($hash, $def)  = @_;
	my $name = $hash->{NAME};	

	### Stop internal timer
	RemoveInternalTimer($hash);
	
	### Write log information
	Log3 $name, 3, $name. "Tide has been undefined.";
	
	return;
}
####END####### Deactivate module module after "undefine" command by fhem #######################################END#####


###START###### Handle attributes after changes via fhem GUI ###################################################START####
sub Tide_Attr(@) {
	my @a                      = @_;
	my $name                   = $a[1];
	my $hash                   = $defs{$name};

	### For debugging purpose only
	Log3 $name, 5, $name. " : Tide_Attr Begin__________________________________________________________________________________________________________________________";

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

	### Check whether "TideStation" attribute has been provided
	if ($a[2] eq "TideStation") 
	{
		### Get tidestations
		my %TideStations = %{ 	$hash->{helper}{TideStationList}};

		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : Tide_Attr - TideStations                     : " . Dumper(%TideStations);

		### Loop througt the List of StationIDs
		foreach my $StationID (keys %TideStations) {
			
			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : Tide_Attr - TideStationID : " . $StationID . " - TideStationName : " . $TideStations{$StationID};
			
			if ($a[3] eq $TideStations{$StationID}){
				
				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : Tide_Attr - Found Station!                   : " . $StationID . " - " . $TideStations{$StationID};

				### Save StationID in hash
				$hash->{helper}{StationID} = $StationID;
				
				### Download TideTable
				Tide_Download($hash);
			}
		}
	}
	
	### Check whether "GaugeInterval" attribute has been provided
	if ($a[2] eq "GaugeInterval") 
	{
		
		### Save GaugeInterval in hash
		$hash->{helper}{GaugeInterval} = $a[3];
		
		### UpdateTimer
		Tide_UpdateTimer($hash);
	}
	return;
}
####END####### Handle attributes after changes via fhem GUI ####################################################END#####


###START###### Manipulate reading after "get" command by fhem #################################################START####
sub Tide_Get($@) {
	# my ( $hash, @a ) = @_;
	
	# ### If not enough arguments have been provided
	# if ( @a < 2 ) {
		# return "\"set Tide\" needs at least one argument";
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
sub Tide_Set($@) {
	my ( $hash, @a ) = @_;
	
	### If not enough arguments have been provided
	if ( @a < 2 ) {
		return "\"set Tide\" needs at least one argument";
	}
	
	my $name     = shift @a;
	my $reading  = shift @a;
	my $value    = join(" ", @a);
	my $ReturnMessage;
	my @cList;

	
	### Create Set List
	push(@cList, "UpdateStations:noArg"); 

	return "Unknown argument $reading, choose one of " . join(" ", @cList) if $reading eq '?';

	### Manually update tide sation list
	if ($reading eq "UpdateStations") {
		Tide_Stations($hash);
	}
	 
	return;
}
####END####### Manipulate reading after "set" command by fhem ##################################################END#####

###START###### Routine for first start ########################################################################START####
sub Tide_Startup($) {
	my ($hash) = @_;
	my $name  = $hash->{NAME};

	### Stop internal timer
	RemoveInternalTimer($hash);

	### For debugging purpose only
	Log3 $name, 5, $name. " : Tide_Startup Begin_______________________________________________________________________________________________________________________";
	Log3 $name, 5, $name. " : Tide_Startup - Attribute TideStation         : " . AttrVal($name, "TideStation", "NixDa");

	### Check for missing Attributes
	Tide_CheckAttributes($hash);

	if((defined(AttrVal($name, "TideStation", ""))) && (AttrVal($name, "TideStation", "None") ne "None")) {
		### Get tidestations
		my %TideStations = %{ 	$hash->{helper}{TideStationList}};

		### Loop througt the List of StationIDs
		foreach my $StationID (keys %TideStations) {
			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : Tide_Startup - TideStationID : " . $StationID . " - TideStationName : " . $TideStations{$StationID};
			
			if ($attr{$name}{TideStation} eq $TideStations{$StationID}){
				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : Tide_Startup - Found Station!                : " . $StationID . " - " . $TideStations{$StationID};
				
				### Save StationID in hash
				$hash->{helper}{StationID} = $StationID;
				
				### Download TideTable
				Tide_Download($hash);
			}
			else{
				### Log Entry for debugging purposes
				Log3 $name, 5, $name. " : Tide_Startup - No  Station found!";
			}
		}
	}
	return;
}
####END####### Routine for first start #########################################################################END#####

###START###### Check Attributes ###############################################################################START####
sub Tide_CheckAttributes($) {
	my ($hash) = @_;
	my $name  = $hash->{NAME};

	### For debugging purpose only
	Log3 $name, 5, $name. " : Tide_CheckAttributes Begin_______________________________________________________________________________________________________________";

	### Check whether all required attributes has been provided and if not, create them with standard values
	if(!defined($attr{$name}{icon})) {
		### Set attribute with standard value since it is not available
		$attr{$name}{icon} = "sea-level";

		### Writing log entry
		Log3 $name, 4, $name. " : Tide - The attribute icon was missing and has been set to sea-level";
	}

	if(!defined($attr{$name}{TideStation})) {
		### Set attribute with standard value since it is not available
		$attr{$name}{TideStation} = "None";

		### Writing log entry
		Log3 $name, 4, $name. " : Tide - The attribute TideStation was missing and has been set to None";
	}
	
	if(!defined($attr{$name}{NoOfForcast})) {
		### Set attribute with standard value since it is not available
		$attr{$name}{NoOfForcast} = 5;

		### Writing log entry
		Log3 $name, 4, $name. " : Tide - The attribute NoOfForcast was missing and has been set to 5";
	}
	
	if(!defined($attr{$name}{stateFormat})) {
		### Set attribute with standard value since it is not available
		$attr{$name}{stateFormat} = "\{\"<table>\n<tbody>\n\t<tr>\n\t\t<td style=\\\"text-align: right;\\\">Station:</td>\n\t\t<td style=\\\"text-align: left;\\\" >\" . ReadingsVal(\$name,\"A04-GT-Name\",\"\") . \"</td>\n\t</tr>\n\t<tr>\n\t\t<td style=\\\"text-align: right;\\\">Water Event:</td>\n\t\t<td style=\\\"text-align: left;\\\" >\" . ReadingsVal(\$name,\"Next_00_WaterEvent\",\"\") . \"</td>\n\t</tr>\n\t<tr>\n\t\t<td style=\\\"text-align: right;\\\">Date:</td>\n\t\t<td style=\\\"text-align: left;\\\" >\". ReadingsVal(\$name,\"Next_00_Date\",\"\") . \"</td>\n\t</tr>\n\t<tr>\n\t\t<td style=\\\"text-align: right;\\\">Time:</td>\n\t\t<td style=\\\"text-align: left;\\\" >\" . ReadingsVal(\$name,\"Next_00_Time\",\"\") . \"</td>\n\t</tr>\n\t<tr>\n\t\t<td style=\\\"text-align: right;\\\">Calculated Tide Height:</td>\n\t\t<td style=\\\"text-align: left;\\\" >\" . ReadingsVal(\$name,\"Next_00_Height-PNP\",\"\") . \"m above PNP</td>\n\t</tr>\t\t\n<tr>\n\t\t<td style=\\\"text-align: right;\\\">Current Gauge Height:</td>\n\t\t<td style=\\\"text-align: left;\\\" >\" . ReadingsVal(\$name,\"Gauge_Value\",\"\") . \"m above PNP</td>\n\t</tr>\t\t\n</tbody>\n</table>\"\n\}";

		### Writing log entry
		Log3 $name, 4, $name. " : Tide - The attribute stateFormat was missing and has been set.";
	}

	if(!defined($attr{$name}{ShowTerminology})) {
		### Set attribute with standard value since it is not available
		$attr{$name}{ShowTerminology} = "on";

		### Writing log entry
		Log3 $name, 4, $name. " : Tide - The attribute ShowTerminology was missing and has been set to on";
	}

	if(!defined($attr{$name}{ShowGaugeChart})) {
		### Set attribute with standard value since it is not available
		$attr{$name}{ShowGaugeChart} = "on";

		### Writing log entry
		Log3 $name, 4, $name. " : Tide - The attribute ShowGaugeChart was missing and has been set to on";
	}

	if(!defined($attr{$name}{GaugeInterval})) {
		### Set attribute with standard value since it is not available
		$attr{$name}{GaugeInterval} = 180;

		### Writing log entry
		Log3 $name, 4, $name. " : Tide - The attribute GaugeInterval was missing and has been set to 180s = 3min which is the update interval of the website";
	}
}
####END####### Check Attributes ################################################################################END#####

###START###### Update tide station list #######################################################################START####
sub Tide_Stations($) {
	### Define variables
	my ($hash)	= @_;
	my $name  = $hash->{NAME};
	my %TideStations;
	my $AttributeSelection;

	### Stop internal timer
	RemoveInternalTimer($hash);

	### For debugging purpose only
	Log3 $name, 5, $name. " : Tide_Stations Begin______________________________________________________________________________________________________________________";

	### Check whether the Tide has been disabled
	if(IsDisabled($name))
	{
		return;
	}

	################# Tide forcast #################

	my $TideFile = GetFileFromURL("https://filebox.bsh.de/index.php/s/SbJ3z5NBkpOZloY/download?path=%2F&files=filebox_pegelliste.txt");	
	#my $TideFile = encode("utf-8",$TideFile,Encode::FB_CROAK);
	
	### Log Entry for debugging purposes
	#Log3 $name, 5, $name. " : Tide_Stations - TideFile                    		: " . $TideFile;
	
	my @TideFileEntries = split("\n", $TideFile);
	
	### Delete first 4 lines since they are header
	splice(@TideFileEntries, 0, 4);
	
	### For all entries in the liste
	for my $TideFileEntry(@TideFileEntries) {
		### Log Entry for debugging purposes
		#Log3 $name, 5, $name. " : Tide_Stations - TideFileEntry                : " . $TideFileEntry;

		### Splite name and value
		my @TideStationEntry = split("    ", $TideFileEntry);

		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : Tide_Stations - TideStationID                : " . $TideStationEntry[0];
		Log3 $name, 5, $name. " : Tide_Stations - TideStationName              : " . $TideStationEntry[1];
		
		### Push value into hash
		$TideStations{$TideStationEntry[0]} = $TideStationEntry[1];

		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : Tide_Stations - TideStations                 : " . Dumper(%TideStations);
	}

	### Loop througt the List of StationIDs
	foreach my $StationID (keys %TideStations) {
		
		### Get value
		my $StationName = $TideStations{$StationID};
		
		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : Tide_Stations - TideStationName              : " . $StationName;
		
		### Replace ", " with "-"
		$StationName =~ s/, /-/g;
		
		### Replace " " with "_"
		$StationName =~ s/ /_/g;
		
		### Replace old description with new one
		$TideStations{$StationID} = $StationName;
	}

	### Loop througt the List of StationName
	foreach my $StationName (sort values %TideStations) {

		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : Tide_Stations - TideStationName              : " . $StationName;
		
		### Create the Selectionlist for the Attribute
		$AttributeSelection .= $StationName . ",";
	}

	### Cutt off the last comma ","
	$AttributeSelection =~ s/[,]*$//;

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : Tide_Stations - AttributeSelection Before    : " . $AttributeSelection;

	### Refresh Attribute Selection
	my $AttrList =  $modules{Tide}{AttrList};
	
	### Delete former TideStationListEntry
	$AttrList =~ s/.*?(?=disable)//;
	
	### Amendt AttributeSelection
	$AttributeSelection = "TideStation:" . $AttributeSelection . " " . $AttrList;

	### Save back ATTRList
	$modules{Tide}{AttrList} = $AttributeSelection;

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : Tide_Stations - AttrList                     : " . $AttrList;
	Log3 $name, 5, $name. " : Tide_Stations - AttributeSelection After     : " . $AttributeSelection;

	### Save List of Tide Stations in hash
	$hash->{helper}{TideStationList} = \%TideStations;

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : Tide_Stations - TideStations                 : " . Dumper(%TideStations);
	Log3 $name, 5, $name. " : Tide_Stations - {helper}{TideStationList}    : " . Dumper($hash->{helper}{TideStationList});


	################# Current Water Level #################

	my $GaugeListJson = GetFileFromURL("https://www.pegelonline.wsv.de/webservices/rest-api/v2/stations");	
	my $GaugeHashRef;
	my %GaugeStations;
	
	### Log Entry for debugging purposes
	#Log3 $name, 5, $name. " : Tide_Stations - GaugeListJson                : " . $GaugeListJson;

	### Check whether the decoded content is not empty and therefore available
	if ($GaugeListJson ne "") {	
		eval  {
			$GaugeHashRef = decode_json(encode_utf8($GaugeListJson));
			1;
		}
		or do  {
			Log3 $name, 1, $name. " : Tide_Stations - CANNOT parse GaugeListJson";
		};

		for my $array(@$GaugeHashRef){
			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : Tide_Stations - GaugeListJson                : " . Dumper($array->{number});
		
			$GaugeStations{$array->{number}} = $array;
		}
	}

	### Save List of Gauge Stations in hash
	$hash->{helper}{GaugeStationList} = \%GaugeStations;

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : Tide_Stations - GaugeListHash                : " . Dumper(%GaugeStations);
	Log3 $name, 5, $name. " : Tide_Stations - {helper}{GaugeStationList}   : " . Dumper($hash->{helper}{GaugeStationList});


	return;
}
####END####### Update tide station list ########################################################################END#####

###START###### Download tide table ############################################################################START####
sub Tide_Download($) {

	### Define variables
	my ($hash)	  = @_;
	my $name      = $hash->{NAME};
	my $StationID = $hash->{helper}{StationID};

	### For debugging purpose only
	Log3 $name, 5, $name. " : Tide_Download Begin______________________________________________________________________________________________________________________";
	Log3 $name, 5, $name. " : Tide_Download - StationID                     : " . $StationID;
	
	### Check whether StationID has been set and if not abort this subroutine
	if (!defined($StationID)){
		
		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : Tide_Download - StationID does not exist.";
		
		return;
	}

	### Get current year
	my $year = (localtime)[5] + 1900;

	### Stop internal timer
	RemoveInternalTimer($hash);

	### Check whether the Tide has been disabled
	if(IsDisabled($name))
	{
		return;
	}
	
	### Extract all existing Readings as hash reference
	my @ReadingsList = $hash->{READINGS};
	
	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : Tide_Download - ReadingsList                 : " . Dumper(@ReadingsList);
	
	### For all 
	foreach my $ReadingsName (keys %{$ReadingsList[0]}) {

		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : Tide_Download - Deleting Reading             : " . $ReadingsName;
	 
		### Delete Reading
		readingsDelete($hash, $ReadingsName);
	}
	
	### Create URL for Tide File
	my $TideFileUrl = "https://filebox.bsh.de/index.php/s/SbJ3z5NBkpOZloY/download?path=/vb_hwnw/deu" . $year . "&files=" . $StationID . $year . ".txt";
	
	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : Tide_Download - StationID                    : " . $StationID  if defined $StationID;
	Log3 $name, 5, $name. " : Tide_Download - TideFileUrl                  : " . $TideFileUrl;
	
	
	### Get TideFile and transform to UTF-8
	my $TideFile = GetFileFromURL($TideFileUrl);	
	   $TideFile = encode("utf-8",$TideFile,Encode::FB_CROAK);

	### Save as Internal
	$hash->{helper}{TideFile} = $TideFile;

	### Update Tide Table in Readings
	Tide_UpdateTide($hash);

	return;
}
####END####### Download tide table #############################################################################END#####

###START###### Update timer ###################################################################################START####
sub Tide_UpdateTimer($) {
	### Define variables
	my ($hash)	  = @_;
	my $name      = $hash->{NAME};

	### For debugging purpose only
	Log3 $name, 5, $name. " : Tide_UpdateTimer Begin___________________________________________________________________________________________________________________";
	Log3 $name, 5, $name. " : Tide_UpdateTimer - GaugeInterval             : " . $hash->{helper}{GaugeInterval};
	Log3 $name, 5, $name. " : Tide_UpdateTimer - NextTideUpdate            : " . $hash->{helper}{NextTideUpdate};

	### Stop internal timer
	RemoveInternalTimer($hash);

	### Start internal timer on next Gauge update
	InternalTimer(gettimeofday()+$hash->{helper}{GaugeInterval}, \&Tide_UpdateGauge, $hash);

	### Start internal timer on next water event (plus 1s)
	InternalTimer($hash->{helper}{NextTideUpdate}, \&Tide_UpdateTide, $hash);

	return;
}
####END####### Update timer ####################################################################################END#####

###START###### Update tide table ##############################################################################START####
sub Tide_UpdateTide($) {
	### Define variables
	my ($hash)	  = @_;
	my $name      = $hash->{NAME};
	my $StationID = $hash->{helper}{StationID};


	### For debugging purpose only
	Log3 $name, 5, $name. " : Tide_UpdateTide Begin_________________________________________________________________________________________________________________________";
	Log3 $name, 5, $name. " : Tide_UpdateTide - StationID                  : " . $StationID if defined $StationID;
	
	### Check whether Attribut TideStation has been set already and if not abort this subroutine
	if (!defined($StationID)){
		
		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : Tide_UpdateTide - StationID does not exist.";
		
		return;
	}
	
	### Get current year
	my $year = (localtime)[5] + 1900;

	### Check whether the Tide has been disabled
	if(IsDisabled($name))
	{
		return;
	}

	### Get Tidefile from Internal
	my $TideFile = $hash->{helper}{TideFile};

	### Split lines of file
	my @TideFileEntries = split("\n", $TideFile);
	
	### Log Entry for debugging purposes
	#Log3 $name, 5, $name. " : Tide_UpdateTide - TideFileEntries            : " . Dumper(@TideFileEntries);

	### Initiate Bulk Update
	readingsBeginUpdate($hash);

	### Define count lines
	my $CountHeaderLines = 0;

	### For all entries in the header
	for my $TideFileEntry(@TideFileEntries)
	{
		### Inkrement Counter
		$CountHeaderLines++;
		
		### If the Stopline is reached for the header
		if ($TideFileEntry eq "LLL#") {
			last;
		}

		### Ignore the first line
		if ($CountHeaderLines < 2) {
			next;
		}

		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : Tide_UpdateTide - TideFileEntry              : " . $TideFileEntry;

		### Splite name and value
		my @TideHeaderEntry = split(":", $TideFileEntry);

		### Remove column marker and replace Umlauts
				### Replace " " with "_"
		$TideHeaderEntry[0] =~ s/ //g;
		$TideHeaderEntry[0] =~ s/#/-/;
		$TideHeaderEntry[0] =~ s/\s+$//;
		$TideHeaderEntry[0] =~ s/\xc3\x84/Ae/ug; #Special Character "Ä"
		$TideHeaderEntry[0] =~ s/\xc3\xa4/ae/ug; #Special Character "ä"
		$TideHeaderEntry[0] =~ s/\xc3\x96/Oe/ug; #Special Character "Ö"
		$TideHeaderEntry[0] =~ s/\xc3\xb6/oe/ug; #Special Character "ö"
		$TideHeaderEntry[0] =~ s/\xc3\x9c/Ue/ug; #Special Character "Ü"
		$TideHeaderEntry[0] =~ s/\xc3\xbc/ue/ug; #Special Character "ü"
		$TideHeaderEntry[0] =~ s/\xc3\x9f/sz/ug; #Special Character "ß"

		$TideHeaderEntry[1] =~ s/#//g;
		$TideHeaderEntry[1] =~ s/\s+$//;
		$TideHeaderEntry[1] =~ s/\xc3\x84/Ae/ug; #Special Character "Ä"
		$TideHeaderEntry[1] =~ s/\xc3\xa4/ae/ug; #Special Character "ä"
		$TideHeaderEntry[1] =~ s/\xc3\x96/Oe/ug; #Special Character "Ö"
		$TideHeaderEntry[1] =~ s/\xc3\xb6/oe/ug; #Special Character "ö"
		$TideHeaderEntry[1] =~ s/\xc3\x9c/Ue/ug; #Special Character "Ü"
		$TideHeaderEntry[1] =~ s/\xc3\xbc/ue/ug; #Special Character "ü"
		$TideHeaderEntry[1] =~ s/\xc3\x9f/sz/ug; #Special Character "ß"
			
		### Update readings with header entries
		readingsBulkUpdate($hash, $TideHeaderEntry[0], $TideHeaderEntry[1], 1);
	}

	### Delete first CountHeaderLines lines since they are header
	splice(@TideFileEntries, 0, $CountHeaderLines);
	
	### Initialise counter for forcasts to 0
	my $CountForcast = 0;
	
	### Initialise TimeStamp of next update to 0
	my $TimeStampNextUpdate = 0;
	

	### For all entries in the liste
	for my $TideFileEntry(@TideFileEntries) {
		### Log Entry for debugging purposes
		#Log3 $name, 5, $name. " : Tide_UpdateTide - TideFileEntry          : " . $TideFileEntry;

		### If the Stopline is reached for the header
		if ($TideFileEntry eq "EEE#") {
			last;
		}

		### Splite name and value
		my @TideStationEntry = split("#", $TideFileEntry);

		### Log Entry for debugging purposes
		#Log3 $name, 5, $name. " : Tide_UpdateTide - TideStationEntry       : " . Dumper(@TideStationEntry);

		### Replace space with leading 0
		$TideStationEntry[5] =~ s/ /0/g; # Date
		$TideStationEntry[6] =~ s/ /0/g; # Time

		### Log Entry for debugging purposes
		#Log3 $name, 5, $name. " : Tide_UpdateTide - Date                   : " . $TideStationEntry[5];
		#Log3 $name, 5, $name. " : Tide_UpdateTide - Time                   : " . $TideStationEntry[6];

		my @DateArray = split(/\./, $TideStationEntry[5]);
		my @TimeArray = split(":",  $TideStationEntry[6]);


		### Form ISO-8601 TimeString
		my $TideStationEntryDateTime = $DateArray[2] . "-" . $DateArray[1] . "-" .  $DateArray[0] . "T" . $TimeArray[0] . ":" . $TimeArray[1] . ":00";

		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : Tide_UpdateTide - TideFileTimeStamp          : " . $TideStationEntryDateTime;
		Log3 $name, 5, $name. " : Tide_UpdateTide - _________________________________________________________________________";
		Log3 $name, 5, $name. " : Tide_UpdateTide - TimeArrayEpoch             :  " . str2time($TideStationEntryDateTime);
		Log3 $name, 5, $name. " : Tide_UpdateTide - Epoch Now                  : " . time();
		Log3 $name, 5, $name. " : Tide_UpdateTide - Epoch Now - TimeArrayEpoch : " . (time() - str2time($TideStationEntryDateTime));


		### As soon the difference is smaller 0, the first entry in the future has been found
		if((time() - str2time($TideStationEntryDateTime))<0){
		
			### If this is the next event
			if ($CountForcast == 0){
			
				### Save TimeStamp for next update
				$TimeStampNextUpdate = str2time($TideStationEntryDateTime);
			}
		
			
			### Log Entry for debugging purposes
			Log3 $name, 5, $name. " : Tide_UpdateTide - _________________________________________________________________________";
			Log3 $name, 5, $name. " : Tide_UpdateTide - Epoch Now - Entry is in the future!";
			Log3 $name, 5, $name. " : Tide_UpdateTide - TideFileTimeStamp          : " . $TideStationEntryDateTime;
			Log3 $name, 5, $name. " : Tide_UpdateTide - LineID                     : " . $TideStationEntry[ 0];
			Log3 $name, 5, $name. " : Tide_UpdateTide - StationID                  : " . $TideStationEntry[ 1];
			Log3 $name, 5, $name. " : Tide_UpdateTide - Moonphase                  : " . $TideStationEntry[ 2];
			Log3 $name, 5, $name. " : Tide_UpdateTide - WaterEvent                 : " . $TideStationEntry[ 3];
			Log3 $name, 5, $name. " : Tide_UpdateTide - Weekday                    : " . $TideStationEntry[ 4];
			Log3 $name, 5, $name. " : Tide_UpdateTide - Date                       : " . $TideStationEntry[ 5];
			Log3 $name, 5, $name. " : Tide_UpdateTide - Time                       : " . $TideStationEntry[ 6];
			Log3 $name, 5, $name. " : Tide_UpdateTide - Height                     : " . $TideStationEntry[ 7];
			Log3 $name, 5, $name. " : Tide_UpdateTide - Quality                    : " . $TideStationEntry[ 8];
			Log3 $name, 5, $name. " : Tide_UpdateTide - DayCount                   : " . $TideStationEntry[ 9];
			Log3 $name, 5, $name. " : Tide_UpdateTide - TimeZone (UTC=0)           : " . $TideStationEntry[10];
			Log3 $name, 5, $name. " : Tide_UpdateTide - Transit Number for HW & Lw : " . $TideStationEntry[11];
			Log3 $name, 5, $name. " : Tide_UpdateTide - Transit Count              : " . $TideStationEntry[12];
			Log3 $name, 5, $name. " : Tide_UpdateTide - Julian Date Days to UTC    : " . $TideStationEntry[13];

			my $ReadingPrefix =  "Next_" . sprintf("%02d", $CountForcast) ."_";

			### Get chart level deltas
			my $DeltaPNP2SKN  =  ReadingsVal($name, "D03-SKNue.PNP", 0);
			my $DeltaPNP2NHN  =  ReadingsVal($name, "D01-PNPu.NHN" , 0);

			### Delete all blanks from values
			$DeltaPNP2SKN         =~ s/ //g;
			$DeltaPNP2NHN         =~ s/ //g;			
			$TideStationEntry[ 0] =~ s/ //g;
			$TideStationEntry[ 1] =~ s/ //g;
			$TideStationEntry[ 2] =~ s/ //g;
			$TideStationEntry[ 3] =~ s/ //g;
			$TideStationEntry[ 4] =~ s/ //g;
			$TideStationEntry[ 5] =~ s/ //g;
			$TideStationEntry[ 6] =~ s/ //g;
			$TideStationEntry[ 7] =~ s/ //g;
			$TideStationEntry[ 8] =~ s/ //g;
			$TideStationEntry[ 9] =~ s/ //g;
			$TideStationEntry[10] =~ s/ //g;
			$TideStationEntry[11] =~ s/ //g;
			$TideStationEntry[ 8] =~ s/ //g;
			$TideStationEntry[12] =~ s/ //g;
			$TideStationEntry[13] =~ s/ //g;

			### Calculate Water Heights based on Delta values provided
			my $HeightSKN     =  $TideStationEntry[ 7] - $DeltaPNP2SKN;
			my $HeightNHN     =  $TideStationEntry[ 7] + $DeltaPNP2NHN;
			
		   #readingsBulkUpdate($hash, $ReadingPrefix . "LineID"         , $TideStationEntry[ 0], 1);
		   #readingsBulkUpdate($hash, $ReadingPrefix . "StationID"      , $TideStationEntry[ 1], 1);
			readingsBulkUpdate($hash, $ReadingPrefix . "Moonphase"      , $TideStationEntry[ 2], 1);
			readingsBulkUpdate($hash, $ReadingPrefix . "WaterEvent"     , $TideStationEntry[ 3], 1);
		   #readingsBulkUpdate($hash, $ReadingPrefix . "Weekday"        , $TideStationEntry[ 4], 1);
			readingsBulkUpdate($hash, $ReadingPrefix . "Date"           , $TideStationEntry[ 5], 1);
			readingsBulkUpdate($hash, $ReadingPrefix . "Time"           , $TideStationEntry[ 6], 1);
			readingsBulkUpdate($hash, $ReadingPrefix . "Height-PNP"     , $TideStationEntry[ 7], 1);
			readingsBulkUpdate($hash, $ReadingPrefix . "Height-SKN"     , $HeightSKN           , 1);
			readingsBulkUpdate($hash, $ReadingPrefix . "Height-NHN"     , $HeightNHN           , 1);
		   #readingsBulkUpdate($hash, $ReadingPrefix . "DayCount"       , $TideStationEntry[ 9], 1);
		   #readingsBulkUpdate($hash, $ReadingPrefix . "TimeZone"       , $TideStationEntry[10], 1);
			readingsBulkUpdate($hash, $ReadingPrefix . "TransitNo"      , $TideStationEntry[11], 1);
		   #readingsBulkUpdate($hash, $ReadingPrefix . "Quality"        , $TideStationEntry[ 8], 1);
			readingsBulkUpdate($hash, $ReadingPrefix . "TransitCount"   , $TideStationEntry[12], 1);
		   #readingsBulkUpdate($hash, $ReadingPrefix . "JulianDateDays" , $TideStationEntry[13], 1);
			
			### Inkrement counter of forcast
			$CountForcast++;			
		}

		### If the number of required forcasts have been reached interrupt the loop
		if ($CountForcast > AttrVal($name, "NoOfForcast", 5)){
			last;
		}
	}

	### Execute Readings Bulk Update
	readingsEndUpdate($hash, 1);


	### Get station number and delete blanks
	my $ReadingA13 = ReadingsVal($name,"A13-Messstelle","");
	   $ReadingA13 =~ s/ //g;

	### Check whether Attribut TideStation has been set already and if not abort this subroutine
	if (defined($ReadingA13)){
		
		my $PegelChartUrlPrefix  = "https://www.pegelonline.wsv.de/charts/OnlineVisualisierungGanglinie?pegelnummer=";
		my $PegelChartUrlPostfix = "&parameter=WASSERSTAND%20ROHDATEN&dauer=48;24&imgLinien=2&imgBreite=715&imgHoehe=250&pegelparameter=NNW,HHW,MNW,MW,MHW,GLW,HSW,NSW,RNW,ZS_I,ZS_II,M_I,M_II,M_III,TuGLW,NW,HSW2,GOK_NN,MP_NN&schriftPegelname=11&schriftAchse=11&anzeigeUeberschrift=false&anzeigeDatenquelle=false&schriftLetzterWert=15&textUnten=&gesetzlicheZeit=true&anzeigeUnterschrift=false&rand=0";
		my $PegelChartUrl        = $PegelChartUrlPrefix . $ReadingA13 . $PegelChartUrlPostfix;

		### Save as Internal
		$hash->{helper}{PegelChartUrl} = $PegelChartUrl;
	}

	### Log Entry for debugging purposes
	my ($S, $M, $H, $d, $m, $Y) = localtime($TimeStampNextUpdate);
	$m += 1;
	$Y += 1900;
	my $NextUpdateISO = sprintf("%04d-%02d-%02d %02d:%02d:%02d", $Y, $m, $d, $H, $M, $S);
	Log3 $name, 5, $name. " : Tide_UpdateTide - TimeStampNow               : " . time();
	Log3 $name, 5, $name. " : Tide_UpdateTide - TimeStampNextUpdate        : " . $TimeStampNextUpdate;
	Log3 $name, 5, $name. " : Tide_UpdateTide - TimeStampDelta             : " . ($TimeStampNextUpdate - time());
	Log3 $name, 5, $name. " : Tide_UpdateTide - Time     NextUpdate        : " . $NextUpdateISO;
	Log3 $name, 5, $name. " : Tide_UpdateTide - {helper}{PegelChartUrl}    : " . $hash->{helper}{PegelChartUrl};

	### Save NextTideUpdate in hash
	$hash->{helper}{NextTideUpdate} = $TimeStampNextUpdate +1;
	
	### Update Gauge
	Tide_UpdateGauge($hash);

	return;
}
####END####### Update tide table ###############################################################################END#####

###START###### Update gauge value #############################################################################START####
sub Tide_UpdateGauge($) {
	### Define variables
	my ($hash)	   = @_;
	my $name       = $hash->{NAME};

	### Get station number and delete blanks
	my $ReadingA13 = ReadingsVal($name,"A13-Messstelle","");
	   $ReadingA13 =~ s/ //g;
	

	### For debugging purpose only
	Log3 $name, 5, $name. " : Tide_UpdateGauge  Begin___________________________________________________________________________________________________________________";
	Log3 $name, 5, $name. " : Tide_UpdateGauge - ReadingA13                : " . $ReadingA13 if defined $ReadingA13;
	
	### Check whether Attribut TideStation has been set already and if not abort this subroutine
	if (!defined($ReadingA13)){
		
		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : Tide_UpdateGauge - ReadingA13 does not exist.";
		
		return;
	}
	
	### Check whether TideStation has GaugeLevel available and if not abort this subroutine
	if (!defined($hash->{helper}{GaugeStationList}{$ReadingA13}{uuid})){
		
		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : Tide_UpdateGauge - GaugeStationUuid does not exist.";
		
		return;
	}
	
	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : Tide_UpdateGauge - Progressing with value and timestamp download.";
	
	### Get uuid for the selected Tide station
	my $GaugeStationUuid = $hash->{helper}{GaugeStationList}{$ReadingA13}{uuid};
	
	### For debugging purpose only
	Log3 $name, 5, $name. " : Tide_UpdateGauge - GaugeStationUuid          : " . $GaugeStationUuid;

	### Create url for pegelonline  with uuid
	my $UrlPegelonlineStation = "https://www.pegelonline.wsv.de/webservices/rest-api/v2/stations/" . $GaugeStationUuid . "/W/currentmeasurement.json";

	### For debugging purpose only
	Log3 $name, 5, $name. " : Tide_UpdateGauge - UrlPegelonlineStation     : " . $UrlPegelonlineStation;

	my $GaugeJson = GetFileFromURL($UrlPegelonlineStation);	

	### Log Entry for debugging purposes
	Log3 $name, 4, $name. " : Tide_UpdateGauge - GaugeJson                 : " . $GaugeJson;

	my $GaugeHashRef;

	eval  {
		$GaugeHashRef = decode_json(encode_utf8($GaugeJson));
		1;
	}
	or do  {
		Log3 $name, 1, $name. " : Tide_UpdateGauge - CANNOT parse GaugeJson";
	};

	### Log Entry for debugging purposes
	Log3 $name, 5, $name. " : Tide_UpdateGauge - timestamp                 : " . $GaugeHashRef->{timestamp};
	Log3 $name, 5, $name. " : Tide_UpdateGauge - value                     : " . ($GaugeHashRef->{value}/100) . "m";

	### Initiate Bulk Update
	readingsBeginUpdate($hash);

	### Write Readings for Gauge
	readingsBulkUpdate($hash, "Gauge_Timestamp",  $GaugeHashRef->{timestamp} , 1);
	readingsBulkUpdate($hash, "Gauge_Value"    , ($GaugeHashRef->{value}/100), 1);

	### Execute Readings Bulk Update
	readingsEndUpdate($hash, 1);	

	### Update Timer
	Tide_UpdateTimer($hash);
	
	return;
}
####END####### Update gauge value ##############################################################################END#####

###START###### Display of html code preceding the "Internals"-section #########################################START####
sub Tide_FW_detailFn($$$$) {
	my ($FW_wname, $devname, $room, $extPage) = @_;
	my $hash 			= $defs{$devname};
	my $name 			= $hash->{NAME};
	my$htmlCode = "
		<table>
			<tbody>
				<tr>
					<td style=\"text-align: right;\">Station:</td>
					<td style=\"text-align: left;\" >" . ReadingsVal($name,"A04-GT-Name","") . "</td>
				</tr>
				<tr>
					<td style=\"text-align: right;\">Water Event:</td>
					<td style=\"text-align: left;\" >" . ReadingsVal($name,"Next_00_WaterEvent","") . "</td>
				</tr>
				<tr>
					<td style=\"text-align: right;\">Date:</td>
					<td style=\"text-align: left;\" >". ReadingsVal($name,"Next_00_Date","") . "</td>
				</tr>
				<tr>
					<td style=\"text-align: right;\">Time:</td>
					<td style=\"text-align: left;\" >" . ReadingsVal($name,"Next_00_Time","") . "</td>
				</tr>
				<tr>
					<td style=\"text-align: right;\">Calculated Tide Height:</td>
					<td style=\"text-align: left;\" >" . ReadingsVal($name,"Next_00_Height-PNP","") . "m above PNP</td>
				</tr>
				<tr>
					<td style=\"text-align: right;\">Current Gauge Height:</td>
					<td style=\"text-align: left;\" >" . ReadingsVal($name,"Gauge_Value","") . "m above PNP</td>
				</tr>
				<tr>
					<td style=\"text-align: right;\">Chart Map Zero (SKN):</td>
					<td style=\"text-align: left;\" >" . ReadingsVal($name,"D03-SKNue.PNP","") . "m above PNP</td>
				</tr>
				<tr>
	";

	if ($attr{$name}{ShowTerminology} eq "on"){
		$htmlCode  .= "<td> <img width=\"649\" height=\"auto\" src=\"https://www.bsh.de/DE/THEMEN/Wasserstand_und_Gezeiten/Gezeiten/_Anlagen/Bilder/Gezeiten_Begriffsbestimmungen.png?__blob=normal&v=2 \"></td>";
	}

	if ($attr{$name}{ShowGaugeChart} eq "on"){
		### Log Entry for debugging purposes
		Log3 $name, 5, $name. " : Tide_FW_detailFn - {helper}{PegelChartUrl}   : " . $hash->{helper}{PegelChartUrl};
		
		#$htmlCode  .= "<td><img width=\"649\" height=\"auto\" alt=\"tick\" src=" . $hash->{helper}{PegelChartUrl} . "></td>";
		$htmlCode  .= "<td><iframe src="  . $hash->{helper}{PegelChartUrl} . " width=\"750\" height=\"325\" title=\"Gauge Chart\" loading=\"lazy\" frameBorder=\"0\"></iframe></td>";
	}

	$htmlCode  .= "	
				</tr>
			</tbody>
		</table>
	";
	
	return($htmlCode);		
}
1;

###START###### Description for fhem commandref ################################################################START####
=pod
=encoding utf8
=item device
=item summary    Downloads the tide data from BSH
=item summary_DE L&aumldt die Gezeiten-Daten vom BSH
=begin html

<a name="Tide"></a>
<a id="Tide"></a>
<h3>Tide</h3>
<ul>
	<table>
		<tr>
			<td>
				The Tide module downloads the tide data for the German tidal survey stations.<BR>
				The stations are available for direct selection.<BR>
				With the usage of this modul, the user accepts the conditions within the "Allgemeinen Gesch&auml;ftsbedingungen (AGB) zur Abgabe von digitalen Daten des BSH mit einem einfachen Nutzungsrecht" (Anlage 2) including "Gesonderten Nutzungsbedingungen des BSH f&uuml;r digitale Gezeitendaten" (Anlage 4). Refer to: <a href="https://www.bsh.de/DE/Das_BSH/Gebuehren_Preise/Gebuehren_und_Preise/_Anlagen/Downloads/Entgeltverzeichnis-digitale-Daten.html">EVz BSH</a><BR>
				All values are based on Gauge Zero (Pegelnullpunkt = PNP).<BR>
				Refer to the Terminology of the BSH:<BR>
				<img width="649" height="auto" alt="tick" src="https://www.bsh.de/DE/THEMEN/Wasserstand_und_Gezeiten/Gezeiten/_Anlagen/Bilder/Gezeiten_Begriffsbestimmungen.png?__blob=normal&v=2">
			</td>
		</tr>
	</table>
	<BR>
	<table>
		<tr><td><a id="Tide-define"></a><b>Define</b></td></tr>
		<tr><td><ul><code>define &lt;name&gt; Tide</code>                                                                                                                                                                                          <BR>          </ul></td></tr>
		<tr><td><ul><ul><code>&lt;name&gt;</code> : The name of the device. Recommendation: "myTide".                                                                                                                                              <BR>     </ul></ul></td></tr>
	</table>                                                                                                                                                                                                                                                                                                                                                                                                                                                   
	<BR>                                                                                                                                                                                                                                                                                                                                                                                                                                                       
	<table>                                                                                                                                                                                                                                                                                                                                                                                                                                                    
		<tr><td><a id="Tide-set"></a><b>Set</b></td></tr>                                                                                                                                                                                                                                                                                                                                                                                                  
		<tr><td><ul>The set function is able to change or activate the following features as follows:                                                                                                                                              <BR>          </ul></td></tr>
		<tr><td><ul><a id="Tide-set-UpdateStations"         > </a><li><b><u><code>set UpdateStations  </code></u></b> : Updates the list of available tidal monitoring stations                                                                    <BR></li>     </ul></td></tr>
	</table>                                                                                                                                                                                                                                                                                                                                                                                                                                                       
	<BR>                                                                                                                                                                                                                                                                                                                                                                                                                                                           
	<table>                                                                                                                                                                                                                                                                                                                                                                                                                                                        
		<tr><td><a id="Tide-attr"></a><b>Attributes</b></td></tr>
		<tr><td><ul>The following user attributes can be used with the Tide module in addition to the global ones e.g. <a href="#room">room</a>.                                                                                                   <BR>          </ul></td></tr>
	</table>
	<table>
		<tr><td><ul><ul><a id="Tide-attr-disable"        > </a><li><b><u><code>disable             </code></u></b> : Stopps the device from further reacting on UDP datagrams sent by the DoorBird unit.<BR>The default value is 0 = activated     <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="Tide-attr-NoOfForcast"    > </a><li><b><u><code>NoOfForcast         </code></u></b> : Number of future events to be indicated as readings.                                                                          <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="Tide-attr-ShowGaugeChart" > </a><li><b><u><code>ShowGaugeChart      </code></u></b> : Whether or whether not the current gauge chart shall be shown.                                                                <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="Tide-attr-ShowTerminology"> </a><li><b><u><code>ShowTerminology     </code></u></b> : Whether or whether not the terminology of the terms used for the water level  shall be shown.                                 <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="Tide-attr-TideStation"    > </a><li><b><u><code>TideStation         </code></u></b> : Name of the Tide Stations to be downloaded. The available name of the stations are provided as selection list.                <BR></li></ul></ul></td></tr>

	</table>
</ul>
=end html
=begin html_DE

<a id="Tide"></a>
<h3>Tide</h3>
<ul>
	<table>
		<tr>
			<td>
				Das Tide - Modul l&aumldt die Gezeiten-Daten vom Bundesamt f&uuml;r Seeschifffahrt und Hydrographie (BSH)<BR>
				Die verf&uuml;gbare Station kann direkt aus der Liste ausgew&auml;hlt werden.<BR>
				Mit der Nutzung dieses Moduls aktzeptiert der Nutzer die Bedingungen im "Allgemeinen Gesch&auml;ftsbedingungen (AGB) zur Abgabe von digitalen Daten des BSH mit einem einfachen Nutzungsrecht" (Anlage 2) und den "Gesonderten Nutzungsbedingungen des BSH f&uuml;r digitale Gezeitendaten" (Anlage 4). Siehe: <a href="https://www.bsh.de/DE/Das_BSH/Gebuehren_Preise/Gebuehren_und_Preise/_Anlagen/Downloads/Entgeltverzeichnis-digitale-Daten.html">EVz BSH</a><BR>
				Alle Werte basieren auf den Pegelnullpunkt = PNP.<BR>
				Siehe BSH Terminology:<BR>
				<img width="649" height="auto" alt="tick" src="https://www.bsh.de/DE/THEMEN/Wasserstand_und_Gezeiten/Gezeiten/_Anlagen/Bilder/Gezeiten_Begriffsbestimmungen.png?__blob=normal&v=2">
			</td>
		</tr>
	</table>
	<BR>
	<table>
		<tr><td><a id="Tide-define"></a><b>Define</b></td></tr>
		<tr><td><ul><code>define &lt;name&gt; Tide</code>                                                                                                                                                                                          <BR>          </ul></td></tr>
		<tr><td><ul><ul><code>&lt;name&gt;</code> : Der Name der Instanz. Empfehlung: "myTide".                                                                                                                                                    <BR>     </ul></ul></td></tr>
	</table>                                                                                                                                                                                                                                                                                                                                                                                                                                                   
	<BR>                                                                                                                                                                                                                                                                                                                                                                                                                                                       
	<table>                                                                                                                                                                                                                                                                                                                                                                                                                                                    
		<tr><td><a id="Tide-set"></a><b>Set</b></td></tr>                                                                                                                                                                                                                                                                                                                                                                                                  
		<tr><td><ul>Die Set Funktion l&ouml;st folgende Aktionen aus:                                                                                                                                                                              <BR>          </ul></td></tr>
		<tr><td><ul><a id="Tide-set-UpdateStations"         > </a><li><b><u><code>set UpdateStations  </code></u></b> : L&auml;dt die Liste der verf&uumlgbaren Stationen erneut aus dem Netz.                                                     <BR></li>     </ul></td></tr>
	</table>                                                                                                                                                                                                                                                                                                                                                                                                                                                       
	<BR>                                                                                                                                                                                                                                                                                                                                                                                                                                                           
	<table>                                                                                                                                                                                                                                                                                                                                                                                                                                                        
		<tr><td><a id="Tide-attr"></a><b>Attributes</b></td></tr>
		<tr><td><ul>Die folgenden Attribute k&ouml;nnen neben den globalen Attributen gesetzt werden z.B.: <a href="#room">room</a>.                                                                                                               <BR>          </ul></td></tr>
	</table>
	<table>
		<tr><td><ul><ul><a id="Tide-attr-disable"        > </a><li><b><u><code>disable             </code></u></b> : Stoppt den regelm&auml;ssigen Download/Update der Daten aus dem Netz.<BR>Der Default Wert ist 0 = aktiv.                      <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="Tide-attr-NoOfForcast"    > </a><li><b><u><code>NoOfForcast         </code></u></b> : Anzahl der anzuzeigenden Events in der Zukunft die als Readings angeyeigt werden sollen.                                      <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="Tide-attr-ShowGaugeChart" > </a><li><b><u><code>ShowGaugeChart      </code></u></b> : Anzeige der Wasserstands Grafik.<BR>Der Default Wert ist true = wird angezeigt.                                               <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="Tide-attr-ShowTerminology"> </a><li><b><u><code>ShowTerminology     </code></u></b> : Anzeige der Begriffsdefinition laut BSH.<BR>Der Default Wert ist true = wird angezeigt.                                       <BR></li></ul></ul></td></tr>
		<tr><td><ul><ul><a id="Tide-attr-TideStation"    > </a><li><b><u><code>TideStation         </code></u></b> : Name der Pegel-Station welche angezeigt werden soll. Die verf&uuml;gbaren Stationen werden in der Liste angezeigt.            <BR></li></ul></ul></td></tr>
	</table>
</ul>
=end html_DE
=for :application/json;q=META.json 73_Tide.pm
{
	"abstract"                       : "Downloads the tide data from Bundesamt f&uuml;r Seeschifffahrt und Hydrographie (BSH)",
	"description"                    : "The Tide module downloads the tide data from Bundesamt f&uuml;r Seeschifffahrt und Hydrographie (BSH) for a selected monitoring station.",
    "version"                        : "1.00",
	"name"                           : "73_Tide.pm",
	"meta-spec": {
		"version"                    : "1",
		"url"                        : "http://search.cpan.org/perldoc?CPAN::Meta::Spec"
	},	
	"x_lang": {
		"de": {
			"abstract"               : "L&aumldt die Gezeiten-Daten vom Bundesamt f&uuml;r Seeschifffahrt und Hydrographie (BSH)",
			"description"            : "Das Tide Modul l&aumldt die Gezeiten-Daten vom Bundesamt f&uuml;r Seeschifffahrt und Hydrographie (BSH) f&uuml;r eine ausgew&auml;hlte Station an."
		}
	},
	"license"                        : ["GPL_2"],
	"author"                         : ["Matthias Deeke <matthias.deeke@deeke.eu>"],
	"x_fhem_maintainer"              : ["Sailor"],
	"keywords"                       : ["Tide", "Gezeiten"],
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
		"x_homepage": "https://gezeiten.bsh.de/",
		"x_homepage_title": "Gezeitendaten des Bundesamtes f&uuml;r Seeschifffahrt und Hydrographie (BSH)",
	    "x_license": ["https://www.bsh.de/DE/Das_BSH/Gebuehren_Preise/Gebuehren_und_Preise/_Anlagen/Downloads/Entgeltverzeichnis-digitale-Daten.html"],
		"x_support_community": {
			"rss"                    : "",
			"web"                    : "https://forum.fhem.de/index.php?topic=143631.0.html",
			"subCommunity" : {
				"rss"                : "",
				"title"              : "This sub-board will be first contact point",
				"web"                : "https://forum.fhem.de/index.php?topic=143631.0.html"
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