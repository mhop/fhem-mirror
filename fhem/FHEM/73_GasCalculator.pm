# $Id$
########################################################################################################################
#
#     73_GasCalculator.pm
#     Observes a reading of a device which represents the actual counter (e.g. OW_devive) 
#     acting as gas counter, calculates the corresponding values and writes them back to 
#     the counter device.
#     Written and best viewed with Notepad++ v.6.8.6; Language Markup: Perl
#
#     Author                     : Matthias Deeke 
#     e-mail                     : matthias.deeke(AT)deeke(PUNKT)eu
#     Fhem Forum                 : https://forum.fhem.de/index.php/topic,47909.0.html
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
#     fhem.cfg: define <devicename> GasCalculator <regexp>
#
#     Example 1:
#     define myGasCalculator GasCalculator myGasCounter:CounterA.*
#
########################################################################################################################

########################################################################################################################
# List of open Problems / Issues:
#
#	- set command to create Plots automatically
#
########################################################################################################################

package main;
use strict;
use warnings;
my %GasCalculator_gets;
my %GasCalculator_sets;

###START###### Initialize module ##############################################################################START####
sub GasCalculator_Initialize($)
{
    my ($hash)  = @_;
	
    $hash->{STATE}				= "Init";
    $hash->{DefFn}				= "GasCalculator_Define";
    $hash->{UndefFn}			= "GasCalculator_Undefine";
    $hash->{GetFn}           	= "GasCalculator_Get";
	$hash->{SetFn}           	= "GasCalculator_Set";
    $hash->{AttrFn}				= "GasCalculator_Attr";
	$hash->{NotifyFn}			= "GasCalculator_Notify";
	$hash->{NotifyOrderPrefix}	= "10-";   					# Want to be called before the rest

	$hash->{AttrList}       	= "disable:0,1 " .
								  "header " .
								  "GasCounterOffset " .
								  "GasCubicPerCounts " .
								  "GaszValue " .
								  "GasNominalHeatingValue " .
								  "BasicPricePerAnnum " .
								  "GasPricePerKWh " .
								  "MonthlyPayment " .
								  "MonthOfAnnualReading " .
								  "ReadingDestination:CalculatorDevice,CounterDevice " .
								  "SiPrefixPower:W,kW,MW,GW " .
								  "Volume:m&#179;,ft&#179; " .
								  "Currency:&#8364;,&#163;,&#36; " .
								   $readingFnAttributes;
}
####END####### Initialize module ###############################################################################END#####

###START###### Activate module after module has been used via fhem command "define" ##########################START####
sub GasCalculator_Define($$$)
{
	my ($hash, $def)              = @_;
	my ($name, $type, $RegEx, $RegExst) = split("[ \t]+", $def, 4);

	### Check whether regular expression has correct syntax
	if(!$RegEx || $RegExst) 
	{
		my $msg = "Wrong syntax: define <name> GasCalculator device[:event]";
		return $msg;
	}

	### Check whether regular expression is misleading
	eval { "Hallo" =~ m/^$RegEx$/ };
	return "Bad regexp: $@" if($@);
	$hash->{REGEXP} = $RegEx;	

	### Writing values to global hash
	notifyRegexpChanged($hash, $RegEx);
	$hash->{NAME}							= $name;
	$hash->{STATE}              			= "active";
	$hash->{REGEXP}             			= $RegEx;

	if(defined($attr{$hash}{SiPrefixPower}))
	{
		if    ($attr{$hash}{SiPrefixPower} eq "W" ) {$hash->{system}{SiPrefixPowerFactor} = 1          ;}
		elsif ($attr{$hash}{SiPrefixPower} eq "kW") {$hash->{system}{SiPrefixPowerFactor} = 1000       ;}
		elsif ($attr{$hash}{SiPrefixPower} eq "MW") {$hash->{system}{SiPrefixPowerFactor} = 1000000    ;}
		elsif ($attr{$hash}{SiPrefixPower} eq "GW") {$hash->{system}{SiPrefixPowerFactor} = 1000000000 ;}
		else                                        {$hash->{system}{SiPrefixPowerFactor} = 1          ;}
	}
	else
	{
                                                     $hash->{system}{SiPrefixPowerFactor} = 1;
	}
	
	### Writing log entry
	Log3 $name, 5, $name. " : GasCalculator - Starting to define module";

	return undef;
}
####END####### Activate module after module has been used via fhem command "define" ############################END#####


###START###### Deactivate module module after "undefine" command by fhem ######################################START####
sub GasCalculator_Undefine($$)
{
	my ($hash, $def)  = @_;
	my $name = $hash->{NAME};	

	Log3 $name, 3, $name. " GasCalculator- The gas calculator has been undefined. Values corresponding to Gas Counter will no longer calculated";
	
	return undef;
}
####END####### Deactivate module module after "undefine" command by fhem #######################################END#####


###START###### Handle attributes after changes via fhem GUI ###################################################START####
sub GasCalculator_Attr(@)
{
	my @a                      = @_;
	my $name                   = $a[1];
	my $hash                   = $defs{$name};
	
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
		}
	}

	### Check whether "SiPrefixPower" attribute has been provided
	if ($a[2] eq "SiPrefixPower")
	{
		if    ($a[3] eq "W" ) {$hash->{system}{SiPrefixPowerFactor} = 1          ;}
		elsif ($a[3] eq "kW") {$hash->{system}{SiPrefixPowerFactor} = 1000       ;}
		elsif ($a[3] eq "MW") {$hash->{system}{SiPrefixPowerFactor} = 1000000    ;}
		elsif ($a[3] eq "GW") {$hash->{system}{SiPrefixPowerFactor} = 1000000000 ;}
		else                  {$hash->{system}{SiPrefixPowerFactor} = 1          ;}
	}

	return undef;
}
####END####### Handle attributes after changes via fhem GUI ####################################################END#####


###START###### Manipulate reading after "set" command by fhem #################################################START####
sub GasCalculator_Get($@)
{
	my ( $hash, @a ) = @_;
	
	### If not enough arguments have been provided
	if ( @a < 2 )
	{
		return "\"get GasCalculator\" needs at least one argument";
	}
		
	my $GasCalcName = shift @a;
	my $reading  = shift @a;
	my $value; 
	my $ReturnMessage;

	if(!defined($GasCalculator_gets{$reading})) 
	{
		my @cList = keys %GasCalculator_sets;
		return "Unknown argument $reading, choose one of " . join(" ", @cList);

		### Create Log entries for debugging
		Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - get list: " . join(" ", @cList);
	}
	
	if ( $reading ne "?")
	{
		### Create Log entries for debugging
		Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - get " . $reading . " with value: " . $value;
		
		### Write current value
		$value = ReadingsVal($GasCalcName,  $reading, undef);
		
		### Create ReturnMessage
		$ReturnMessage = $value;
	}
	
	return($ReturnMessage);
}
####END####### Manipulate reading after "set" command by fhem ##################################################END#####

###START###### Manipulate reading after "set" command by fhem #################################################START####
sub GasCalculator_Set($@)
{
	my ( $hash, @a ) = @_;
	
	### If not enough arguments have been provided
	if ( @a < 2 )
	{
		return "\"set GasCalculator\" needs at least one argument";
	}
		
	my $GasCalcName = shift @a;
	my $reading  = shift @a;
	my $value = join(" ", @a);
	my $ReturnMessage;

	if(!defined($GasCalculator_sets{$reading})) 
	{
		my @cList = keys %GasCalculator_sets;
		return "Unknown argument $reading, choose one of " . join(" ", @cList);

		### Create Log entries for debugging
		Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - set list: " . join(" ", @cList);
	}
	
	if ( $reading ne "?")
	{
		### Create Log entries for debugging
		Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - set " . $reading . " with value: " . $value;
		
		### Write current value
		readingsSingleUpdate($hash, $reading, $value, 1);
		
		### Create ReturnMessage
		$ReturnMessage = $GasCalcName . " - Successfully set " . $reading . " with value: " . $value;
	}
	
	return($ReturnMessage);
}
####END####### Manipulate reading after "set" command by fhem ##################################################END#####

###START###### Calculate gas meter values on changed events ###################################################START####
sub GasCalculator_Notify($$)
{
	### Define variables
	my ($GasCalcDev, $GasCountDev)	= @_;
	my $GasCalcName 				= $GasCalcDev->{NAME};
	my $GasCountName				= $GasCountDev->{NAME};
	my $GasCountNameEvents			= deviceEvents($GasCountDev, 1);
	my $NumberOfChangedEvents		= int(@{$GasCountNameEvents});
 	my $RegEx						= $GasCalcDev->{REGEXP};

	### Check whether the gas calculator has been disabled
	if(IsDisabled($GasCalcName))
	{
		return "";
	}
	
	### Check whether all required attributes has been provided and if not, create them with standard values
	if(!defined($attr{$GasCalcName}{BasicPricePerAnnum}))
	{
		### Set attribute with standard value since it is not available
		$attr{$GasCalcName}{BasicPricePerAnnum} 	= 0;

		### Writing log entry
		Log3 $GasCalcName, 3, $GasCalcName. " : GasCalculator - The attribute BasicPricePerAnnum was missing and has been set to 0";
	}
	if(!defined($attr{$GasCalcName}{GasCounterOffset}))
	{
		### Set attribute with standard value since it is not available
		$attr{$GasCalcName}{GasCounterOffset} 		= 0;

		### Writing log entry
		Log3 $GasCalcName, 3, $GasCalcName. " : GasCalculator - The attribute GasCounterOffset was missing and has been set to 0";
	}
	if(!defined($attr{$GasCalcName}{GasCubicPerCounts}))
	{
		### Set attribute with standard value since it is not available
		$attr{$GasCalcName}{GasCubicPerCounts} 		= 0.01;

		### Writing log entry
		Log3 $GasCalcName, 3, $GasCalcName. " : GasCalculator - The attribute GasCubicPerCounts was missing and has been set to 0.01 counts/voulume-unit";

	}
	if(!defined($attr{$GasCalcName}{GasNominalHeatingValue}))
	{
		### Set attribute with standard value since it is not available
		$attr{$GasCalcName}{GasNominalHeatingValue}	= 10;

		### Writing log entry
		Log3 $GasCalcName, 3, $GasCalcName. " : GasCalculator - The attribute GasNominalHeatingValue was missing and has been set to 10 kWh/volume-unit";
	}
	if(!defined($attr{$GasCalcName}{GasPricePerKWh}))
	{
		### Set attribute with standard value since it is not available
		$attr{$GasCalcName}{GasPricePerKWh} 		= 0.0654;

		### Writing log entry
		Log3 $GasCalcName, 3, $GasCalcName. " : GasCalculator - The attribute GasPricePerKWh was missing and has been set to 0.0654 currency-unit/volume-unit";
	}
	if(!defined($attr{$GasCalcName}{GaszValue}))
	{
		### Set attribute with standard value since it is not available
		$attr{$GasCalcName}{GaszValue} 				= 1;

		### Writing log entry
		Log3 $GasCalcName, 3, $GasCalcName. " : GasCalculator - The attribute GaszValue was missing and has been set to 1";
	}
	if(!defined($attr{$GasCalcName}{MonthlyPayment}))
	{
		### Set attribute with standard value since it is not available
		$attr{$GasCalcName}{MonthlyPayment} 		= 0;

		### Writing log entry
		Log3 $GasCalcName, 3, $GasCalcName. " : GasCalculator - The attribute MonthlyPayment was missing and has been set to 0 currency-units";
	}
	if(!defined($attr{$GasCalcName}{MonthOfAnnualReading}))
	{
		### Set attribute with standard value since it is not available
		$attr{$GasCalcName}{MonthOfAnnualReading} 	= 5;

		### Writing log entry
		Log3 $GasCalcName, 3, $GasCalcName. " : GasCalculator - The attribute MonthOfAnnualReading was missing and has been set to 5 which is the month May";
	}
	if(!defined($attr{$GasCalcName}{Currency}))
	{
		### Set attribute with standard value since it is not available
		$attr{$GasCalcName}{Currency} 	            = "&#8364;";

		### Writing log entry
		Log3 $GasCalcName, 3, $GasCalcName. " : GasCalculator - The attribute Currency was missing and has been set to &#8364;";
	}
	if(!defined($attr{$GasCalcName}{SiPrefixPower}))
	{
		### Set attribute with standard value since it is not available
		$attr{$GasCalcName}{SiPrefixPower}         = "W";
		$GasCalcDev->{system}{SiPrefixPowerFactor} = 1;
		
		### Writing log entry
		Log3 $GasCalcName, 3, $GasCalcName. " : GasCalculator - The attribute SiPrefixPower was missing and has been set to W";
	}
	if(!defined($attr{$GasCalcName}{Volume}))
	{
		### Set attribute with standard value since it is not available
		$attr{$GasCalcName}{Volume} 	            = "m&#179;";

		### Writing log entry
		Log3 $GasCalcName, 3, $GasCalcName. " : GasCalculator - The attribute Volume was missing and has been set to m&#179;";
	}
	if(!defined($attr{$GasCalcName}{ReadingDestination}))
	{
		### Set attribute with standard value since it is not available
		$attr{$GasCalcName}{ReadingDestination}     = "CalculatorDevice";
		
		### Writing log entry
		Log3 $GasCalcName, 3, $GasCalcName. " : GasCalculator - The attribute ReadingDestination was missing and has been set to CalculatorDevice";
	}
	if(!defined($attr{$GasCalcName}{room}))
	{
		if(defined($attr{$GasCountName}{room}))
		{
			### Set attribute with standard value since it is not available
			$attr{$GasCalcName}{room} 				= $attr{$GasCountName}{room};

			### Writing log entry
			Log3 $GasCalcName, 3, $GasCalcName. " : GasCalculator - The attribute room was missing and has been set to the same room of the Gas Counter: " . $attr{$GasCountName}{room};
		}
		else
		{
			### Set attribute with standard value since it is not available
			$attr{$GasCalcName}{room} 				= "Central Heating";

			### Writing log entry
			Log3 $GasCalcName, 3, $GasCalcName. " : GasCalculator - The attribute room was missing and has been set to Central Heating";
		}
	}


	### For each feedback on in the array of defined regexpression which has been changed
	for (my $i = 0; $i < $NumberOfChangedEvents; $i++) 
	{
		### Extract event
		my $s = $GasCountNameEvents->[$i];

		### Filtering all events which do not match the defined regex
		if(!defined($s))
		{
			next;
		}
		my ($GasCountReadingName, $GasCountReadingValueCurrent) = split(": ", $s, 2); # resets $1
		if("$GasCountName:$s" !~ m/^$RegEx$/)
		{
			next;
		}
		
		### Extracting value
		if(defined($1)) 
		{
			my $RegExArg = $1;

			if(defined($2)) 
			{
				$GasCountReadingName = $1;
				$RegExArg = $2;
			}

			$GasCountReadingValueCurrent = $RegExArg if(defined($RegExArg) && $RegExArg =~ m/^(-?\d+\.?\d*)/);
		}
		if(!defined($GasCountReadingValueCurrent) || $GasCountReadingValueCurrent !~ m/^(-?\d+\.?\d*)/)
		{
			next;
		}
		
		###Get current Counter and transform in Volume (cubic) as read on mechanic gas meter
		   $GasCountReadingValueCurrent      = $1 * $attr{$GasCalcName}{GasCubicPerCounts} + $attr{$GasCalcName}{GasCounterOffset};
		my $GasCountReadingTimestampCurrent  = ReadingsTimestamp($GasCountName,$GasCountReadingName,0);		

		
		### Create Log entries for debugging
		Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator Begin_______________________________________________________________________________________________________________________________";
		
		### Create name and destination device for general reading prefix
		my $GasCalcReadingPrefix;
		my $GasCalcReadingDestinationDevice;
		my $GasCalcReadingDestinationDeviceName;
		if ($attr{$GasCalcName}{ReadingDestination} eq "CalculatorDevice")
		{
			$GasCalcReadingPrefix					= ($GasCountName . "_" . $GasCountReadingName);
			$GasCalcReadingDestinationDevice		=  $GasCalcDev;
			$GasCalcReadingDestinationDeviceName	=  $GasCalcName;

			### Create Log entries for debugging
			Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - Attribut ReadingDestination has been set to CalculatorDevice";			
			Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - GasCalcReadingPrefix                     : " . $GasCalcReadingPrefix;
			Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - GasCalcReadingDestinationDevice          : " . $GasCalcReadingDestinationDevice;
			Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - GasCalcReadingDestinationDeviceName      : " . $GasCalcReadingDestinationDeviceName;

		}
		elsif ($attr{$GasCalcName}{ReadingDestination} eq "CounterDevice")
		{
			$GasCalcReadingPrefix 					=  $GasCountReadingName;
			$GasCalcReadingDestinationDevice		=  $GasCountDev;
			$GasCalcReadingDestinationDeviceName	=  $GasCountName;

			### Create Log entries for debugging
			Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - Attribut ReadingDestination has been set to CounterDevice";
			Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - GasCalcReadingPrefix                     : " . $GasCalcReadingPrefix;
			Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - GasCalcReadingDestinationDevice          : " . $GasCalcReadingDestinationDevice;
			Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - GasCalcReadingDestinationDeviceName      : " . $GasCalcReadingDestinationDeviceName;
		}
		else
		{
			### Create Log entries for debugging
			Log3 $GasCalcName, 3, $GasCalcName. " : GasCalculator - Attribut ReadingDestination has not been set up correctly. Skipping event.";
			
			### Skipping event
			next;
		}
		
		### Restore previous Counter and if not available define it with "undef"
		my $GasCountReadingTimestampPrevious = ReadingsTimestamp($GasCalcReadingDestinationDeviceName,  "." . $GasCalcReadingPrefix . "_PrevRead", undef);
		my $GasCountReadingValuePrevious     =       ReadingsVal($GasCalcReadingDestinationDeviceName,  "." . $GasCalcReadingPrefix . "_PrevRead", undef);

		### Create Log entries for debugging
		Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - GasCountReadingValuePrevious             : " . $GasCountReadingValuePrevious;
		Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - GasCalcReadingPrefix_PrevRead            : " . $GasCalcReadingPrefix . "_PrevRead";

		### Find out whether there has been a previous value being stored
		if(defined($GasCountReadingValuePrevious))
		{
			### Write current Volume as previous Voulume for future use in the GasCalc-Device
			readingsSingleUpdate( $GasCalcReadingDestinationDevice, "." . $GasCalcReadingPrefix. "_PrevRead", sprintf('%.3f', ($GasCountReadingValueCurrent)),1);

			### Create Log entries for debugging
			Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - Previous value found. Continuing with calculations";
		}
		### If not: save value and quit loop
		else
		{
			### Write current Volume as previous Voulume for future use in the GasCalc-Device
			readingsSingleUpdate( $GasCalcReadingDestinationDevice, "." . $GasCalcReadingPrefix. "_PrevRead", sprintf('%.3f', ($GasCountReadingValueCurrent)),1);

			### Create Log entries for debugging
			Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - Previous value NOT found. Skipping Loop";
			
			### Jump out of loop since there is nothing to do anymore than to wait for the next value
			next;
		}

		###### Find out whether the device has been freshly defined and certain readings have never been set up yet or certain readings have been deleted
		### Find out whether the reading for the daily start value has not been written yet 
		if(!defined(ReadingsVal($GasCalcReadingDestinationDeviceName,  $GasCalcReadingPrefix . "_Vol1stDay", undef)))
		{
			### Save current Volume as first reading of day = first after midnight and reset min, max value, value counter and value sum
			readingsSingleUpdate( $GasCalcReadingDestinationDevice,       $GasCalcReadingPrefix . "_Vol1stDay",     $GasCountReadingValueCurrent,  1);
			readingsSingleUpdate( $GasCalcReadingDestinationDevice,       $GasCalcReadingPrefix . "_VolLastDay",    $GasCountReadingValuePrevious, 1);
			readingsSingleUpdate( $GasCalcReadingDestinationDevice, "." . $GasCalcReadingPrefix . "_PowerDaySum",   0, 1);
			readingsSingleUpdate( $GasCalcReadingDestinationDevice, "." . $GasCalcReadingPrefix . "_PowerDayCount", 0, 1);
			readingsSingleUpdate( $GasCalcReadingDestinationDevice,       $GasCalcReadingPrefix . "_PowerDayMin",   0, 1);
			readingsSingleUpdate( $GasCalcReadingDestinationDevice,       $GasCalcReadingPrefix . "_PowerDayMax",   0, 1);

			### Create Log entries for debugging
			Log3 $GasCalcName, 3, $GasCalcName. " : GasCalculator - Reading for the first daily value was not available and therfore reading and statistics have been written";
			}
		### Find out whether the reading for the monthly start value has not been written yet 
		if(!defined(ReadingsVal($GasCalcReadingDestinationDeviceName,  $GasCalcReadingPrefix . "_Vol1stMonth", undef)))
		{
			### Save current Volume as first reading of month
			readingsSingleUpdate( $GasCalcReadingDestinationDevice, $GasCalcReadingPrefix . "_Vol1stMonth",  $GasCountReadingValueCurrent,  1);	
			readingsSingleUpdate( $GasCalcReadingDestinationDevice, $GasCalcReadingPrefix . "_VolLastMonth", $GasCountReadingValuePrevious, 1);

			### Create Log entries for debugging
			Log3 $GasCalcName, 3, $GasCalcName. " : GasCalculator - Reading for the first monthly value was not available and therfore reading has been written";
			}
		### Find out whether the reading for the meter reading year value has not been written yet 
		if(!defined(ReadingsVal($GasCalcReadingDestinationDeviceName,  $GasCalcReadingPrefix . "_Vol1stMeter", undef)))
		{	
			### Save current Volume as first reading of month where gas-meter is read
			readingsSingleUpdate( $GasCalcReadingDestinationDevice, $GasCalcReadingPrefix . "_Vol1stMeter",  $GasCountReadingValueCurrent,  1);
			readingsSingleUpdate( $GasCalcReadingDestinationDevice, $GasCalcReadingPrefix . "_VolLastMeter", $GasCountReadingValuePrevious, 1);

			### Create Log entries for debugging
			Log3 $GasCalcName, 3, $GasCalcName. " : GasCalculator - Reading for the first value of gas meter year was not available and therfore reading has been written";
		}
		### Find out whether the reading for the yearly value has not been written yet 
		if(!defined(ReadingsVal($GasCalcReadingDestinationDeviceName,  $GasCalcReadingPrefix . "_Vol1stYear", undef)))
		{	
			### Save current Volume as first reading of the calendar year
			readingsSingleUpdate( $GasCalcReadingDestinationDevice, $GasCalcReadingPrefix . "_Vol1stYear",  $GasCountReadingValueCurrent,  1);
			readingsSingleUpdate( $GasCalcReadingDestinationDevice, $GasCalcReadingPrefix . "_VolLastYear", $GasCountReadingValuePrevious, 1);

			### Create Log entries for debugging
			Log3 $GasCalcName, 3, $GasCalcName. " : GasCalculator - Reading for the first yearly value was not available and therfore reading has been written";
		}
		
		### Extracting year, month and day as numbers
		my $GasCountReadingTimestampPreviousRelative = time_str2num($GasCountReadingTimestampPrevious);
		my($GasCountReadingTimestampPreviousSec,$GasCountReadingTimestampPreviousMin,$GasCountReadingTimestampPreviousHour,$GasCountReadingTimestampPreviousMday,$GasCountReadingTimestampPreviousMon,$GasCountReadingTimestampPreviousYear,$GasCountReadingTimestampPreviousWday,$GasCountReadingTimestampPreviousYday,$GasCountReadingTimestampPreviousIsdst)	= localtime($GasCountReadingTimestampPreviousRelative);
		my $GasCountReadingTimestampCurrentRelative  = time_str2num($GasCountReadingTimestampCurrent);
		my($GasCountReadingTimestampCurrentSec,$GasCountReadingTimestampCurrentMin,$GasCountReadingTimestampCurrentHour,$GasCountReadingTimestampCurrentMday,$GasCountReadingTimestampCurrentMon,$GasCountReadingTimestampCurrentYear,$GasCountReadingTimestampCurrentWday,$GasCountReadingTimestampCurrentYday,$GasCountReadingTimestampCurrentIsdst)			= localtime($GasCountReadingTimestampCurrentRelative);
		
		### Correct current month by one month since Unix/Linux start January with 0 instead of 1
		$GasCountReadingTimestampCurrentMon = $GasCountReadingTimestampCurrentMon + 1;
		
		### Create Log entries for debugging
		Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - Reading Name                             : " . $GasCountReadingName;
		Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - Previous Reading Value                   : " . $GasCountReadingTimestampPrevious;
		Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - Current Reading Value                    : " . $GasCountReadingTimestampCurrent;
		Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - Previous Reading Value                   : " . $GasCountReadingValuePrevious;
		Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - Current Reading Value                    : " . $GasCountReadingValueCurrent;

		####### Check whether Initial readings needs to be written
		### Check whether the current value is the first one after change of day = First one after midnight
		if ($GasCountReadingTimestampCurrentHour < $GasCountReadingTimestampPreviousHour)
		{
			### Create Log entries for debugging
			Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - First reading of day detected";

			### Calculate gas energy of previous day € = (Vprevious[cubic] - V1stDay[cubic]) * GaszValue * GasNominalHeatingValue[kWh/cubic] 
			my $GasCalcEnergyDayLast      = ($GasCountReadingValuePrevious - ReadingsVal($GasCalcReadingDestinationDeviceName, $GasCalcReadingPrefix . "_Vol1stDay", "0")) * $attr{$GasCalcName}{GaszValue} * $attr{$GasCalcName}{GasNominalHeatingValue};
			### Calculate pure gas cost of previous day GasCalcEnergyLastDay * Price per kWh
			my $GasCalcEnergyCostDayLast  = $GasCalcEnergyDayLast * $attr{$GasCalcName}{GasPricePerKWh};
			### Reload last Power Value
			my $GasCalcPowerCurrent = ReadingsVal($GasCalcReadingDestinationDeviceName, $GasCalcReadingPrefix . "_PowerCurrent", "0");
		
			### Save gas pure cost of previous day, current gas Energy as first reading of day = first after midnight and reset min, max value, value counter and value sum			
			readingsSingleUpdate( $GasCalcReadingDestinationDevice,       $GasCalcReadingPrefix . "_EnergyCostDayLast",	(sprintf('%.3f', ($GasCalcEnergyCostDayLast ))), 1);
			readingsSingleUpdate( $GasCalcReadingDestinationDevice,       $GasCalcReadingPrefix . "_EnergyDayLast", 	(sprintf('%.3f', ($GasCalcEnergyDayLast     ))), 1);
			readingsSingleUpdate( $GasCalcReadingDestinationDevice,       $GasCalcReadingPrefix . "_Vol1stDay",     	$GasCountReadingValueCurrent                   , 1);
			readingsSingleUpdate( $GasCalcReadingDestinationDevice,       $GasCalcReadingPrefix . "_VolLastDay",    	$GasCountReadingValuePrevious                  , 1);
			readingsSingleUpdate( $GasCalcReadingDestinationDevice, "." . $GasCalcReadingPrefix . "_PowerDaySum",   	0                                              , 1);
			readingsSingleUpdate( $GasCalcReadingDestinationDevice, "." . $GasCalcReadingPrefix . "_PowerDayCount", 	0                                              , 1);
			readingsSingleUpdate( $GasCalcReadingDestinationDevice,       $GasCalcReadingPrefix . "_PowerDayMin",   	(sprintf('%.3f', ($GasCalcPowerCurrent      ))), 1);
			readingsSingleUpdate( $GasCalcReadingDestinationDevice,       $GasCalcReadingPrefix . "_PowerDayMax",   	0                                              , 1);
			
			### Check whether the current value is the first one after change of month
			if ($GasCountReadingTimestampCurrentMday < $GasCountReadingTimestampPreviousMday)
			{
				### Create Log entries for debugging
				Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - First reading of month detected";

				### Calculate gas energy of previous month € = (Vprevious[cubic] - V1stReadMonth[cubic]) * GaszValue * GasNominalHeatingValue[kWh/cubic] 
				my $GasCalcEnergyMonthLast     = ($GasCountReadingValuePrevious - ReadingsVal($GasCalcReadingDestinationDeviceName, $GasCalcReadingPrefix . "_Vol1stMonth", "0")) * $attr{$GasCalcName}{GaszValue} * $attr{$GasCalcName}{GasNominalHeatingValue};
				### Calculate pure gas cost of previous month GasCalcEnergyLastMonth * Price per kWh
				my $GasCalcEnergyCostMonthLast = $GasCalcEnergyMonthLast * $attr{$GasCalcName}{GasPricePerKWh};

				### Save gas energy and pure cost of previous and current month 
				readingsSingleUpdate( $GasCalcReadingDestinationDevice, $GasCalcReadingPrefix . "_EnergyCostMonthLast", (sprintf('%.3f', ($GasCalcEnergyCostMonthLast   ))), 1);
				readingsSingleUpdate( $GasCalcReadingDestinationDevice, $GasCalcReadingPrefix . "_EnergyMonthLast",     (sprintf('%.3f', ($GasCalcEnergyMonthLast       ))), 1);
				readingsSingleUpdate( $GasCalcReadingDestinationDevice, $GasCalcReadingPrefix . "_Vol1stMonth",         (sprintf('%.3f', ($GasCountReadingValueCurrent  ))), 1);
				readingsSingleUpdate( $GasCalcReadingDestinationDevice, $GasCalcReadingPrefix . "_VolLastMonth",        (sprintf('%.3f', ($GasCountReadingValuePrevious ))), 1);
				
				### Check whether the current value is the first one of the meter-reading month
				if ($GasCountReadingTimestampCurrentMon eq $attr{$GasCalcName}{MonthOfAnnualReading})
				{
					### Create Log entries for debugging
					Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - First reading of month for meter reading detected";
					Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - Current month is                  : " . $GasCountReadingTimestampCurrentMon;
					Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - Attribute MonthOfAnnualReading is : " . $attr{$GasCalcName}{MonthOfAnnualReading};
					Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - Vol1stMeter  is                   : " . $GasCountReadingValueCurrent;
					Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - VolLastMeter is                   : " . $GasCountReadingValuePrevious;
					
					### Calculate gas energy of previous meter reading year € = (Vprevious[cubic] - V1stMeter[cubic]) * GaszValue * GasNominalHeatingValue[kWh/cubic]
					my $GasCalcEnergyMeterLast = ($GasCountReadingValuePrevious - ReadingsVal($GasCalcReadingDestinationDeviceName, $GasCalcReadingPrefix . "_Vol1stMeter", "0"))  * $attr{$GasCalcName}{GaszValue} * $attr{$GasCalcName}{GasNominalHeatingValue};
					### Calculate pure gas cost of previous meter reading year € = GasCalcEnergyLastMeter * Price per kWh
					my $GasCalcEnergyCostMeterLast = $GasCalcEnergyMeterLast * $attr{$GasCalcName}{GasPricePerKWh};
					
					### Save gas energy and pure cost of previous and current meter year
					readingsSingleUpdate( $GasCalcReadingDestinationDevice, $GasCalcReadingPrefix . "_EnergyCostMeterLast", (sprintf('%.3f', ($GasCalcEnergyCostMeterLast   ))), 1);
					readingsSingleUpdate( $GasCalcReadingDestinationDevice, $GasCalcReadingPrefix . "_EnergyMeterLast",     (sprintf('%.3f', ($GasCalcEnergyMeterLast       ))), 1);
					readingsSingleUpdate( $GasCalcReadingDestinationDevice, $GasCalcReadingPrefix . "_Vol1stMeter",         (sprintf('%.3f', ($GasCountReadingValueCurrent  ))), 1);
					readingsSingleUpdate( $GasCalcReadingDestinationDevice, $GasCalcReadingPrefix . "_VolLastMeter",        (sprintf('%.3f', ($GasCountReadingValuePrevious ))), 1);
				}

				### Check whether the current value is the first one of the calendar year
				if ($GasCountReadingTimestampCurrentYear > $GasCountReadingTimestampPreviousYear)
				{
					### Create Log entries for debugging
					Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - First reading of calendar year detected";

					### Calculate gas energy of previous calendar year € = (Vcurrent[cubic] - V1stYear[cubic]) * GaszValue * GasNominalHeatingValue[kWh/cubic]
					my $GasCalcEnergyYearLast = ($GasCountReadingValuePrevious - ReadingsVal($GasCalcReadingDestinationDeviceName, $GasCalcReadingPrefix . "_Vol1stYear", "0"))  * $attr{$GasCalcName}{GaszValue} * $attr{$GasCalcName}{GasNominalHeatingValue};
					### Calculate pure gas cost of previous calendar year € = GasCalcEnergyLastYear * Price per kWh
					my $GasCalcEnergyCostYearLast = $GasCalcEnergyYearLast * $attr{$GasCalcName}{GasPricePerKWh};

					### Save gas energy and pure cost of previous and current calendar year
					readingsSingleUpdate( $GasCalcReadingDestinationDevice, $GasCalcReadingPrefix . "_EnergyCostYearLast", (sprintf('%.3f', ($GasCalcEnergyCostYearLast    ))), 1);
					readingsSingleUpdate( $GasCalcReadingDestinationDevice, $GasCalcReadingPrefix . "_EnergyYearLast",     (sprintf('%.3f', ($GasCalcEnergyYearLast        ))), 1);
					readingsSingleUpdate( $GasCalcReadingDestinationDevice, $GasCalcReadingPrefix . "_Vol1stYear",         (sprintf('%.3f', ($GasCountReadingValueCurrent  ))), 1);
					readingsSingleUpdate( $GasCalcReadingDestinationDevice, $GasCalcReadingPrefix . "_VolLastYear",        (sprintf('%.3f', ($GasCountReadingValuePrevious ))), 1);
				}
			}
		}
		
		###### Do calculations
		### Calculate DtCurrent (time difference) of previous and current timestamp / [s]
		my $GasCountReadingTimestampDelta = $GasCountReadingTimestampCurrentRelative - $GasCountReadingTimestampPreviousRelative;
		Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - GasCountReadingTimestampDelta            : " . $GasCountReadingTimestampDelta . " s";

		### Continue with calculations only if time difference is not 0 to avoid "Illegal division by zero"
		if ($GasCountReadingTimestampDelta != 0)
		{
			### Calculate DV (Volume difference) of previous and current value / [cubic]
			my $GasCountReadingValueDelta = sprintf('%.3f', ($GasCountReadingValueCurrent - $GasCountReadingValuePrevious));
			Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - GasCountReadingValueDelta                : " . $GasCountReadingValueDelta . " " . $attr{$GasCalcName}{Volume};

			### Calculate Current Power P = DV/Dt[cubic/s] * GaszValue * GasNominalHeatingValue[kWh/cubic] * 3600[s/h] / SiPrefixPowerFactor
			my $GasCalcPowerCurrent    = ($GasCountReadingValueDelta / $GasCountReadingTimestampDelta) * $attr{$GasCalcName}{GaszValue} * $attr{$GasCalcName}{GasNominalHeatingValue} * 3600 / $GasCalcDev->{system}{SiPrefixPowerFactor};
			
			### Calculate daily sum of power measurements "SP" and measurement counts "n" and then calculate average Power "Paverage = SP/n"
			my $GasCalcPowerDaySum     = ReadingsVal($GasCalcReadingDestinationDeviceName,  "." . $GasCalcReadingPrefix . "_PowerDaySum",   "0") + $GasCalcPowerCurrent;
			my $GasCalcPowerDayCount   = ReadingsVal($GasCalcReadingDestinationDeviceName,  "." . $GasCalcReadingPrefix . "_PowerDayCount", "0") + 1;
			my $GasCalcPowerDayAverage = $GasCalcPowerDaySum / $GasCalcPowerDayCount;
			
			### Calculate consumed Energy of current  day   W = (Vcurrent[cubic] - V1stReadDay[cubic])   * GaszValue * GasNominalHeatingValue[kWh/cubic]
			my $GasCalcEnergyDay       = ($GasCountReadingValueCurrent - ReadingsVal($GasCalcReadingDestinationDeviceName, $GasCalcReadingPrefix . "_Vol1stDay", "0"))   * $attr{$GasCalcName}{GaszValue} * $attr{$GasCalcName}{GasNominalHeatingValue};

			### Calculate consumed Energy of current  month W = (Vcurrent[cubic] - V1stReadMonth[cubic]) * GaszValue * GasNominalHeatingValue[kWh/cubic]
			my $GasCalcEnergyMonth     = ($GasCountReadingValueCurrent - ReadingsVal($GasCalcReadingDestinationDeviceName, $GasCalcReadingPrefix . "_Vol1stMonth", "0")) * $attr{$GasCalcName}{GaszValue} * $attr{$GasCalcName}{GasNominalHeatingValue};

			### Calculate consumed Energy of current   year W = (Vcurrent[cubic] - V1stReadYear[cubic])  * GaszValue * GasNominalHeatingValue[kWh/cubic]
			my $GasCalcEnergyYear      = ($GasCountReadingValueCurrent - ReadingsVal($GasCalcReadingDestinationDeviceName, $GasCalcReadingPrefix . "_Vol1stYear", "0"))  * $attr{$GasCalcName}{GaszValue} * $attr{$GasCalcName}{GasNominalHeatingValue};

			### Calculate consumed Energy of gas-meter year W = (Vcurrent[cubic] - V1stReadMeter[cubic]) * GaszValue * GasNominalHeatingValue[kWh/cubic]
			my $GasCalcEnergyMeter     = ($GasCountReadingValueCurrent - ReadingsVal($GasCalcReadingDestinationDeviceName, $GasCalcReadingPrefix . "_Vol1stMeter", "0")) * $attr{$GasCalcName}{GaszValue} * $attr{$GasCalcName}{GasNominalHeatingValue};

			### Calculate pure Electricity cost since midnight
			my $GasCalcEnergyCostDay   = $GasCalcEnergyDay * $attr{$GasCalcName}{GasPricePerKWh};
			
			### Calculate pure gas cost since first day of month
			my $GasCalcEnergyCostMonth = $GasCalcEnergyMonth * $attr{$GasCalcName}{GasPricePerKWh};
			
			### Calculate pure gas cost since first day of calendar year
			my $GasCalcEnergyCostYear  = $GasCalcEnergyYear * $attr{$GasCalcName}{GasPricePerKWh};
			
			### Calculate pure gas cost since first day of gas meter reading year
			my $GasCalcEnergyCostMeter = $GasCalcEnergyMeter * $attr{$GasCalcName}{GasPricePerKWh};
			
			### Calculate the payment month since the year of gas meter reading started
			my $GasCalcMeterYearMonth=0;
			if (($GasCountReadingTimestampCurrentMon - $attr{$GasCalcName}{MonthOfAnnualReading} + 1) < 1)
			{
				$GasCalcMeterYearMonth  = 13 + $GasCountReadingTimestampCurrentMon - $attr{$GasCalcName}{MonthOfAnnualReading};
			}
			else
			{
				$GasCalcMeterYearMonth  =  1 + $GasCountReadingTimestampCurrentMon - $attr{$GasCalcName}{MonthOfAnnualReading};
			}
			
			### Calculate reserves at gas provider based on monthly advance payments within year of gas meter reading 
			my $GasCalcReserves        = ($GasCalcMeterYearMonth * $attr{$GasCalcName}{MonthlyPayment}) - ($attr{$GasCalcName}{BasicPricePerAnnum} / 12 * $GasCalcMeterYearMonth) - $GasCalcEnergyCostMeter;

			### Create Log entries for debugging		
			Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - _______Finance________________________________________";
			Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - Monthly Payment                          : " . $attr{$GasCalcName}{MonthlyPayment}        . " " . $attr{$GasCalcName}{Currency};
			Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - Basic price per annum                    : " . $attr{$GasCalcName}{BasicPricePerAnnum}    . " " . $attr{$GasCalcName}{Currency};
			Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - GasCalcEnergyCostMeter                   : " . sprintf('%.3f', ($GasCalcEnergyCostMeter)) . " " . $attr{$GasCalcName}{Currency};
			Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - GasCalcReserves                          : " . sprintf('%.3f', ($GasCalcReserves))        . " " . $attr{$GasCalcName}{Currency};

			Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - _______Times__________________________________________";
			Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - GasCalcMeterYearMonth                    : " . $GasCalcMeterYearMonth;
			Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - Current Month                            : " . $GasCountReadingTimestampCurrentMon;

			Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - _______Energy_________________________________________";
			Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - GasCalcEnergyDay                         : " . sprintf('%.3f', ($GasCalcEnergyDay))       . " kWh";
			Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - GasCalcEnergyMonth                       : " . sprintf('%.3f', ($GasCalcEnergyMonth))     . " kWh";
			Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - GasCalcEnergyYear                        : " . sprintf('%.3f', ($GasCalcEnergyYear))      . " kWh";
			Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - GasCalcEnergyMeter                       : " . sprintf('%.3f', ($GasCalcEnergyMeter))     . " kWh";

			Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - _______Power___________________________________________";
			Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - GasCalcPowerCurrent                      : " . sprintf('%.3f', ($GasCalcPowerCurrent))    . " kW";
			Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - GasCalcPowerDayMin                       : " . ReadingsVal( $GasCalcReadingDestinationDeviceName, $GasCalcReadingPrefix . "_PowerDayMin", 0) . " kW";
			Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - GasCalcPowerDayAverage                   : " . sprintf('%.3f', ($GasCalcPowerDayAverage)) . " kW";
			Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - GasCalcPowerDayMax                       : " . ReadingsVal( $GasCalcReadingDestinationDeviceName, $GasCalcReadingPrefix . "_PowerDayMax", 0) . " kW";
			
			###### Write readings to GasCalc device
			### Initialize Bulkupdate
			readingsBeginUpdate($GasCalcReadingDestinationDevice);

			### Write current mechanic meter reading
			readingsBulkUpdate($GasCalcReadingDestinationDevice, $GasCalcReadingPrefix . "_Meter",            sprintf('%.3f', ($GasCountReadingValueCurrent)));

			### Write consumed volume (DV) since last measurement
			readingsBulkUpdate($GasCalcReadingDestinationDevice, "." . $GasCalcReadingPrefix . "_LastDV",     sprintf('%.3f', ($GasCountReadingValueDelta)));

			### Write timelap (Dt) since last measurement
			readingsBulkUpdate($GasCalcReadingDestinationDevice, "." . $GasCalcReadingPrefix . "_LastDt",     sprintf('%.0f', ($GasCountReadingTimestampDelta)));
		
			### Write current Power = average Power over last measurement period
			readingsBulkUpdate($GasCalcReadingDestinationDevice, $GasCalcReadingPrefix . "_PowerCurrent",     sprintf('%.3f', ($GasCalcPowerCurrent)));
			
			### Write daily   Power = average Power since midnight
			readingsBulkUpdate($GasCalcReadingDestinationDevice, $GasCalcReadingPrefix . "_PowerDayAver",     sprintf('%.3f', ($GasCalcPowerDayAverage)));
			
			### Write Power measurement sum    since midnight for average calculation
			readingsBulkUpdate($GasCalcReadingDestinationDevice, "." . $GasCalcReadingPrefix . "_PowerDaySum",      sprintf('%.3f', ($GasCalcPowerDaySum)));
			
			### Write Power measurement counts since midnight for average calculation
			readingsBulkUpdate($GasCalcReadingDestinationDevice, "." . $GasCalcReadingPrefix . "_PowerDayCount",    sprintf('%.0f', ($GasCalcPowerDayCount)));
			
			### Detect new daily minimum power value and write to reading
			if (ReadingsVal($GasCalcReadingDestinationDeviceName, $GasCalcReadingPrefix . "_PowerDayMin", 0) > $GasCalcPowerCurrent)
			{
				### Write new minimum Power value
				readingsBulkUpdate($GasCalcReadingDestinationDevice, $GasCalcReadingPrefix . "_PowerDayMin",  sprintf('%.0f', ($GasCalcPowerCurrent)));
				
				### Create Log entries for debugging
				Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - New daily minimum power value detected   : " . sprintf('%.3f', ($GasCalcPowerCurrent));
			}
			
			### Detect new daily maximum power value and write to reading
			if (ReadingsVal($GasCalcReadingDestinationDeviceName, $GasCalcReadingPrefix . "_PowerDayMax", 0) < $GasCalcPowerCurrent)
			{
				### Write new maximum Power value
				readingsBulkUpdate($GasCalcReadingDestinationDevice, $GasCalcReadingPrefix . "_PowerDayMax",  sprintf('%.3f', ($GasCalcPowerCurrent)));
				
				### Create Log entries for debugging
				Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - New daily maximum power value detected   : " . sprintf('%.3f', ($GasCalcPowerCurrent));
			}
			
			### Write energy consumption since midnight
			readingsBulkUpdate($GasCalcReadingDestinationDevice, $GasCalcReadingPrefix . "_EnergyDay",        sprintf('%.3f', ($GasCalcEnergyDay)));
			
			### Write energy consumption since beginning of month
			readingsBulkUpdate($GasCalcReadingDestinationDevice, $GasCalcReadingPrefix . "_EnergyMonth",      sprintf('%.3f', ($GasCalcEnergyMonth)));

			### Write energy consumption since beginning of year
			readingsBulkUpdate($GasCalcReadingDestinationDevice, $GasCalcReadingPrefix . "_EnergyYear",       sprintf('%.3f', ($GasCalcEnergyYear)));
			
			### Write energy consumption since last meter reading
			readingsBulkUpdate($GasCalcReadingDestinationDevice, $GasCalcReadingPrefix . "_EnergyMeter",      sprintf('%.3f', ($GasCalcEnergyMeter)));
			
			### Write pure energy costs since midnight
			readingsBulkUpdate($GasCalcReadingDestinationDevice, $GasCalcReadingPrefix . "_EnergyCostDay",    sprintf('%.3f', ($GasCalcEnergyCostDay)));

			### Write pure energy costs since beginning of month
			readingsBulkUpdate($GasCalcReadingDestinationDevice, $GasCalcReadingPrefix . "_EnergyCostMonth",  sprintf('%.3f', ($GasCalcEnergyCostMonth)));
			
			### Write pure energy costs since beginning of calendar year
			readingsBulkUpdate($GasCalcReadingDestinationDevice, $GasCalcReadingPrefix . "_EnergyCostYear",   sprintf('%.3f', ($GasCalcEnergyCostYear)));
			
			### Write pure energy costs since beginning of year of gas meter reading
			readingsBulkUpdate($GasCalcReadingDestinationDevice, $GasCalcReadingPrefix . "_EnergyCostMeter",  sprintf('%.3f', ($GasCalcEnergyCostMeter)));

			### Write reserves at gas provider based on monthly advance payments within year of gas meter reading
			readingsBulkUpdate($GasCalcReadingDestinationDevice, $GasCalcReadingPrefix . "_FinanceReserve",   sprintf('%.3f', ($GasCalcReserves)));

			### Write months since last meter reading
			readingsBulkUpdate($GasCalcReadingDestinationDevice, $GasCalcReadingPrefix . "_MonthMeterReading", sprintf('%.0f', ($GasCalcMeterYearMonth)));
			
			### Finish and execute Bulkupdate
			readingsEndUpdate($GasCalcReadingDestinationDevice, 1);
		}
		else
		{
			### Create Log entries for debugging
			Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - GasCountReadingTimestampDelta = $GasCountReadingTimestampDelta. Calculations skipped!";
		}
		
		### Create Log entries for debugging
		Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator End_________________________________________________________________________________________________________________________________";
	}
	
	### If readings exist, update list of available readings
	if($GasCalcDev->{READINGS}) 
	{
		### Copy readings in list of available "gets" and "sets"
		%GasCalculator_gets = %{$GasCalcDev->{READINGS}};
		%GasCalculator_sets = %{$GasCalcDev->{READINGS}};

		### Create Log entries for debugging
		Log3 $GasCalcName, 5, $GasCalcName. " : GasCalculator - notify x_sets list: " . join(" ", (keys %GasCalculator_sets));
	}
	
	return undef;
}
####END####### Calculate gas meter values on changed events ####################################################END#####
1;

###START###### Description for fhem commandref ################################################################START####
=pod

=item helper
=item summary    Calculates the gas energy consumption and costs
=item summary_DE Berechnet den Gas-Energieverbrauch und verbundene Kosten

=begin html

<a name="GasCalculator"></a>
<h3>GasCalculator</h3>
<ul>
<table>
	<tr>
		<td>
			The GasCalculator Module calculates the gas consumption and costs of one ore more gas counters.<BR>
			It is not a counter module itself but requires a regular expression (regex or regexp) in order to know where retrieve the counting ticks of one or more mechanical gas counter.<BR>
			<BR>
			As soon the module has been defined within the fhem.cfg, the module reacts on every event of the specified counter like myOWDEVICE:counter.* etc.<BR>
			<BR>
			The GasCalculator module provides several current, historical, statistical predictable values around with respect to one or more gas-counter and creates respective readings.<BR>
			<BR>
			To avoid waiting for max. 12 months to have realistic values, the readings <code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_Vol1stDay</code>, <code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_Vol1stMonth</code>, <code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_Vol1stYear</code> and <code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_Vol1stMeter</code> must be corrected with real values by using the <code>setreading</code> - command.
			These real values may be found on the last gas bill. Otherwise it will take 24h for the daily, 30days for the monthly and up to 12 month for the yearly values to become realistic.<BR>
			<BR>
		</td>
	</tr>
</table>
  
<table><tr><td><a name="GasCalculatorDefine"></a><b>Define</b></td></tr></table>

<table><tr><td><ul><code>define &lt;name&gt; GasCalculator &lt;regex&gt;</code></ul></td></tr></table>

<ul><ul>
	<table>
		<tr><td><code>&lt;name&gt;</code> : </td><td>The name of the calculation device. Recommendation: "myGasCalculator".</td></tr>
		<tr><td><code>&lt;regex&gt;</code> : </td><td>A valid regular expression (also known as regex or regexp) of the event where the counter can be found</td></tr>
	</table>
</ul></ul>

<table><tr><td><ul>Example: <code>define myGasCalculator GasCalculator myGasCounter:countersA.*</code></ul></td></tr></table>

<BR>

<table>
	<tr><td><a name="GasCalculatorSet"></a><b>Set</b></td></tr>
	<tr><td>
		<ul>
				The set - function sets individual values for example to correct values after power loss etc.<BR>
				The set - function works only for readings which have been stored in the CalculatorDevice.<BR>
				The Readings being stored in the Counter - Device need to be changed individially with the <code>set</code> - command.<BR>
		</ul>
	</td></tr>
</table>

<BR>

<table>
	<tr><td><a name="GasCalculatorGet"></a><b>Get</b></td></tr>
	<tr><td>
		<ul>
				The get - function just returns the individual value of the reading.<BR>
				The get - function works only for readings which have been stored in the CalculatorDevice.<BR>
				The Readings being stored in the Counter - Device need to be read individially with  <code>get</code> - command.<BR>
		</ul>
	</td></tr>
</table>

<BR>

<table>
	<tr><td><a name="GasCalculatorAttr"></a><b>Attributes</b></td></tr>
	<tr><td>
		<ul>
				If the below mentioned attributes have not been pre-defined completly beforehand, the program will create the GasCalculator specific attributes with default values.<BR>
				In addition the global attributes e.g. <a href="#room">room</a> can be used.<BR>
		</ul>
	</td></tr>
</table>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>BasicPricePerAnnum</code> : </li></td><td>	A valid float number for basic annual fee in the chosen currency for the gas supply to the home.<BR>
																			The value is provided by your local gas provider is shown on your gas bill.<BR>
																			For UK users it may known under "Standing Charge". Please make sure it is based on one year<BR>
																			The default value is 0.00<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>Currency</code> : </li></td><td>	One of the pre-defined list of currency symbols [&#8364;,&#163;,&#36;].<BR>
																The default value is &#8364;<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>disable</code> : </li></td><td>			Disables the current module. The module will not react on any events described in the regular expression.<BR>
																		The default value is 0 = enabled.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>GasCounterOffset</code> : </li></td><td>	A valid float number of the volume difference = offset (not the difference of the counter ticks!) between the value shown on the mechanic meter for the gas volume and the calculated volume of this device.<BR>
																		The value for this offset will be calculated as follows V<sub>Offset</sub> = V<sub>Mechanical</sub> - V<sub>Module</sub><BR>
																		The default value is 0.00<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>GasCubicPerCounts</code> : </li></td><td>	A valid float number of the ammount of volume per ticks.<BR>
																		The value is given by the mechanical trigger of the mechanical gas meter. E.g. GasCubicPerCounts = 0.01 means each count is a hundredth of the volume basis unit.<BR>
																		The default value is 0.01<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>GasNominalHeatingValue</code> : </li></td><td>	A valid float number for the gas heating value in [kWh/ chosen Volume].<BR>
																				The value is provided by your local gas provider is shown on your gas bill.<BR>
																				The default value is 10.00<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>GaszValue</code> : </li></td><td>	A valid float number for the gas condition based on the local installation of the mechanical gas meter in relation of the gas providers main supply station.<BR>
																The value is provided by your local gas provider is shown on your gas bill.<BR>
																The default value is 1.00<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>GasPricePerKWh</code> : </li></td><td>	A valid float number for gas price in the chosen currency per kWh for the gas.<BR>
																		The value is provided by your local gas provider is shown on your gas bill.<BR>
																		The default value is 0.0654<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>MonthlyPayment</code> : </li></td><td>	A valid float number for monthly advance payments in the chosen currency towards the gas supplier.<BR>
																		The default value is 0.00<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>MonthOfAnnualReading</code> : </li></td><td>	A valid integer number for the month when the mechanical gas meter reading is performed every year.<BR>
																			The default value is 5 (May)<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>ReadingDestination</code> : </li></td><td>	One of the pre-defined list for the destination of the calculated readings: [CalculatorDevice,CounterDevice].<BR>
																			The CalculatorDevice is the device which has been created with this module.<BR>
																			The CounterDevice    is the Device which is reading the mechanical gas-meter.<BR>
																			The default value is CalculatorDevice - Therefore the readings will be written into this device.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>Volume</code> : </li></td><td>	One of the pre-defined list of volume symbols [m&#179;,ft&#179;].<BR>
																The default value is m&#179;<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<BR>

<table>
	<tr><td><a name="GasCalculatorReadings"></a><b>Readings</b></td></tr>
	<tr><td>
		<ul>
			As soon the device has been able to read at least 2 times the counter, it automatically will create a set readings:<BR>
			The placeholder <code>&lt;DestinationDevice&gt;</code> is the device which has been chosen in the attribute <code>ReadingDestination</code> above. This will not appear if CalculatorDevice has been chosen.<BR>
			The placeholder <code>&lt;SourceCounterReading&gt;</code> is the reading based on the defined regular expression.<BR>
		</ul>
	</td></tr>
</table>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyCostDayLast</code> : </li></td><td>Energy costs of the last day.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyCostMeter</code> : </li></td><td>	Energy costs in the chosen currency since the beginning of the month of where the last gas-meter reading has been performed by the gas supplier.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyCostMeterLast</code> : </li></td><td>	Energy costs in the chosen currency of the last gas-meter period.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyCostMonth</code> : </li></td><td>Energy costs in the chosen currency since the beginning of the current month.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyCostMonthLast</code> : </li></td><td>Energy costs in the chosen currency of the last month.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyCostYear</code> : </li></td><td>Energy costs in the chosen currency since the beginning of the current year.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyCostYearLast</code> : </li></td><td>Energy costs of the last calendar year.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyDay</code> : </li></td><td>Energy consumption in kWh since the beginning of the current day (midnight).<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyDayLast</code> : </li></td><td>Total Energy consumption in kWh of the last day.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyMeter</code> : </li></td><td>Energy consumption in kWh since the beginning of the month of where the last gas-meter reading has been performed by the gas supplier.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyMeterLast</code> : </li></td><td>Total Energy consumption in kWh of the last gas-meter reading period.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyMonth</code> : </li></td><td>Energy consumption in kWh since the beginning of the current month (midnight of the first).<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyMonthLast</code> : </li></td><td>Total Energy consumption in kWh of the last month.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyYear</code> : </li></td><td>Energy consumption in kWh since the beginning of the current year (midnight of the first).<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyYearLast</code> : </li></td><td>Total Energy consumption in kWh of the last calendar year.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_FinanceReserve</code> : </li></td><td>Financial Reserver based on the advanced payments done on the first of every month towards the gas supplier. With negative values, an additional payment is to be excpected.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_MonthMeterReading</code> : </li></td><td>Number of month since last meter reading. The month when the reading occured is the first month = 1.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_Meter</code> : </li></td><td>Current indicated total volume consumption on mechanical gas meter. Correct Offset-attribute if not identical.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_PowerCurrent</code> : </li></td><td>Current heating Power. (Average between current and previous measurement.)<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_PowerDayAver</code> : </li></td><td>Average heating Power since midnight.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_PowerDayMax</code> : </li></td><td>Maximum power peak since midnight.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_PowerDayMin</code> : </li></td><td>Minimum power peak since midnight.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_Vol1stDay</code> : </li></td><td>First volume reading of the current day.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_VolLastDay</code> : </li></td><td>Volume reading of the previous day.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_Vol1stMonth</code> : </li></td><td>First volume reading of the current month.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_VolLastMonth</code> : </li></td><td>Volume reading of the previous month.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_Vol1stYear</code> : </li></td><td>First volume reading of the current year.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_VolLastYear</code> : </li></td><td>Volume reading of the previous year.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_Vol1stMeter</code> : </li></td><td>First volume reading of the first day of the month of the current meter reading period.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_VolLastMeter</code> : </li></td><td>Volume reading of the first day of the month of the last meter reading period.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

</ul>

=end html

=begin html_DE

<a name="GasCalculator"></a>
<h3>GasCalculator</h3>
<ul>
<table>
	<tr>
		<td>
			Das GasCalculator Modul berechnet den Gas - Verbrauch und den verbundenen Kosten von einem oder mehreren Gas-Z&auml;hlern.<BR>
			Es ist kein eigenes Z&auml;hlermodul sondern ben&ouml;tigt eine Regular Expression (regex or regexp) um das Reading mit den Z&auml;hl-Impulse von einem oder mehreren Gasz&auml;hlern zu finden.<BR>
			<BR>
			Sobald das Modul in der fhem.cfg definiert wurde, reagiert das Modul auf jedes durch das regex definierte event wie beispielsweise ein myOWDEVICE:counter.* etc.<BR>
			<BR>
			Das GasCalculator Modul berechnet augenblickliche, historische statistische und vorhersehbare Werte von einem oder mehreren Gas-Z&auml;hlern und erstellt die entsprechenden Readings.<BR>
			<BR>
			Um zu verhindern, dass man bis zu 12 Monate warten muss, bis alle Werte der Realit&auml;t entsprechen, m&uuml;ssen die Readings <code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_Vol1stDay</code>, <code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_Vol1stMonth</code>, <code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_Vol1stYear</code> und <code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_Vol1stMeter</code> entsprechend mit dem <code>setreading</code> - Befehl korrigiert werden.
			Diese Werte findet man unter Umst&auml;nden auf der letzten Gas-Rechnung. Andernfalls dauert es bis zu 24h f&uuml;r die t&auml;glichen, 30 Tage f&uuml;r die monatlichen und bis zu 12 Monate f&uuml;r die j&auml;hrlichen Werte bis diese der Realit&auml;t entsprechen.<BR>
			<BR>
		</td>
	</tr>
</table>
  
<table>
<tr><td><a name="GasCalculatorDefine"></a><b>Define</b></td></tr>
</table>

<table><tr><td><ul><code>define &lt;name&gt; GasCalculator &lt;regex&gt;</code></ul></td></tr></table>

<ul><ul>
	<table>
		<tr><td><code>&lt;name&gt;</code> : </td><td>Der Name dieses Berechnungs-Device. Empfehlung: "myGasCalculator".</td></tr>
		<tr><td><code>&lt;regex&gt;</code> : </td><td>Eine g&uuml;ltige Regular Expression (regex or regexp) von dem Event wo der Z&auml;hlerstand gefunden werden kann</td></tr>
	</table>
</ul></ul>

<table><tr><td><ul>Beispiel: <code>define myGasCalculator GasCalculator myGasCounter:countersA.*</code></ul></td></tr></table>

<BR>

<table>
	<tr><td><a name="GasCalculatorSet"></a><b>Set</b></td></tr>
	<tr><td>
		<ul>
				Die set - Funktion erlaubt individuelle Readings zu ver&auml;ndern um beispielsweise nach einem Stromausfall Werte zu korrigieren.<BR>
				Die set - Funktion funktioniert nur f&uumlr Readings welche im CalculatorDevice gespeichert wurden.<BR>
				Die Readings welche im Counter - Device gespeichert wurden, m&uumlssen individuell mit <code>set</code> - Befehl gesetzt werden.<BR>
		</ul>
	</td></tr>
</table>

<BR>

<table>
	<tr><td><a name="GasCalculatorGet"></a><b>Get</b></td></tr>
	<tr><td>
		<ul>
				Die get - Funktion liefert nur den Wert des jeweiligen Readings zur&uuml;ck.<BR>
				Die get - Funktion funktioniert nur f&uumlr Readings welche im CalculatorDevice gespeichert wurden.<BR>
				Die Readings welche im Counter - Device gespeichert wurden, m&uumlssen individuell mit <code>get</code> - Befehl ausgelesen werden.<BR>
		</ul>
	</td></tr>
</table>

<BR>

<table>
	<tr><td><a name="GasCalculatorAttr"></a><b>Attributes</b></td></tr>
	<tr><td>
		<ul>
				Sollten die unten ausfeg&auuml;hrten Attribute bei der Definition eines entsprechenden Ger&auml;tes nicht gesetzt sein, so werden sie vom Modul mit Standard Werten automatisch gesetzt<BR>
				Zus&auml;tzlich k&ouml;nnen die globalen Attribute wie <a href="#room">room</a> verwendet werden.<BR>
		</ul>
	</td></tr>
</table>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>BasicPricePerAnnum</code> : </li></td><td>	Eine g&uuml;ltige float Zahl f&uuml;r die j&auml;hrliche Grundgeb&uuml;hr in der gew&auml;hlten W&auml;hrung f&uuml;r die Gas-Versorgung zum End-Verbraucher.<BR>
																			Dieser Wert stammt vom Gas-Zulieferer und steht auf der Gas-Rechnung.<BR>
																			Der Standard Wert ist 0.00<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>Currency</code> : </li></td><td>	Eines der vordefinerten W&auml;hrungssymbole: [&#8364;,&#163;,&#36;].<BR>
																Der Standard Wert ist &#8364;<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>disable</code> : </li></td><td>			Deaktiviert das devive. Das Modul wird nicht mehr auf die Events reagieren die durch die Regular Expression definiert wurde.<BR>
																		Der Standard Wert ist 0 = ativiert.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>GasCounterOffset</code> : </li></td><td>	Eine g&uuml;ltige float-Zahl f&uuml;r den Volumen Unterschied = Offset (Nicht der Unterschied zwischen Z&auml;hlimpulsen) zwischen dem am mechanischen Gasz&auml;hler und dem angezeigten Wert im Reading dieses Device.<BR>
																		Der Offset-Wert wird wie folgt ermittelt: V<sub>Offset</sub> = V<sub>Mechanisch</sub> - V<sub>Module</sub><BR>
																		Der Standard-Wert ist 0.00<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>GasCubicPerCounts</code> : </li></td><td>	Eine g&uuml;ltige float-Zahl f&uuml;r die Menge an Z&auml;hlimpulsen pro gew&auml;hlter Volumen-Grundeinheit.<BR>
																		Der Wert ist durch das mechanische Z&auml;hlwerk des Gasz&auml;hlers vorgegeben. GasCubicPerCounts = 0.01 bedeutet, dass jeder Z&auml;hlimpuls ein hunderstel der gew&auml;hlten Volumengrundeinheit.<BR>
																		Der Standard-Wert ist 0.01<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>GasNominalHeatingValue</code> : </li></td><td>	Eine g&uuml;ltige float-Zahl f&uuml;r den Heizwert des gelieferten Gases in [kWh/ gew&auml;hlter Volumeneinheit].<BR>
																				Dieser Wert stammt vom Gas-Zulieferer und steht auf der Gas-Rechnung.<BR>
																				Der Standard-Wert ist 10.00<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>GaszValue</code> : </li></td><td>	Eine g&uuml;ltige float-Zahl f&uuml;r die Zustandszahl des Gases basierend auf der Relation based on the local installation of the mechganical gas meter in relation of the gas providers main supply station.<BR>
																Dieser Wert stammt vom Gas-Zulieferer und steht auf der Gas-Rechnung.<BR>
																Der Standard-Wert ist 1.00<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>GasPricePerKWh</code> : </li></td><td>	Eine g&uuml;ltige float-Zahl f&uuml;r den Gas Preis in der gew&auml;hlten W&auml;hrung pro kWh.<BR>
																		Dieser Wert stammt vom Gas-Zulieferer und steht auf der Gas-Rechnung.<BR>
																		Der Standard-Wert ist 0.0654<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>MonthlyPayment</code> : </li></td><td>	Eine g&uuml;ltige float-Zahl f&uuml;r die monatlichen Abschlagszahlungen in der gew&auml;hlten W&auml;hrung an den Gas-Lieferanten.<BR>
																		Der Standard-Wert ist 0.00<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>MonthOfAnnualReading</code> : </li></td><td>	Eine g&uuml;ltige Ganz-Zahl f&uuml;r den Monat wenn der mechanische Gas-Z&auml;hler jedes Jahr durch den Gas-Lieferanten abgelesen wird.<BR>
																			Der Standard-Wert ist 5 (Mai)<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>ReadingDestination</code> : </li></td><td>	Eines der vordefinerten Device als Ziel der errechneten Readings: [CalculatorDevice,CounterDevice].<BR>
																			Das CalculatorDevice ist das mit diesem Modul erstellte Device.<BR>
																			Das CounterDevice    ist das Device von welchem der mechanische Z&auml;hler ausgelesen wird.<BR>
																			Der Standard-Wert ist CalculatorDevice.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>Volume</code> : </li></td><td>	Eine der vordefinierten Volumensymbole f&uuml;r die Volumeneinheit [m&#179;,ft&#179;].<BR>
																Der Standard-Wert ist m&#179;<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<BR>

<table>
	<tr><td><a name="GasCalculatorReadings"></a><b>Readings</b></td></tr>
	<tr><td>
		<ul>
			Sobald das Device in der Lage war mindestens 2 Werte des Z&auml;hlers einzulesen, werden automatisch die entsprechenden Readings erzeugt:<BR>
			Der Platzhalter <code>&lt;DestinationDevice&gt;</code> steht f&uuml;r das Device, welches man in dem Attribut <code>ReadingDestination</code> oben festgelegt hat. Dieser Platzhalter bleibt leer, sobald man dort CalculatorDevice ausgew&auml;hlt hat.<BR>
			Der Platzhalter <code>&lt;SourceCounterReading&gt;</code> steht f&uuml;r das Reading welches mit der Regular Expression definiert wurde.<BR>
		</ul>
	</td></tr>
</table>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyCostLastDay</code> : </li></td><td>Energiekosten in der gew&auml;hlten W&auml;hrung des letzten Tages.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyCostMeter</code> : </li></td><td>Energiekosten in der gew&auml;hlten W&auml;hrung seit Anfang des Monats wo der Gas-Versorger den Z&auml;hler abliest.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyCostMeterLast</code> : </li></td><td>Energiekosten in der gew&auml;hlten W&auml;hrung der letzten Z&auml;hlperiode des Gas-Versorgers.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyCostMonth</code> : </li></td><td>Energiekosten in der gew&auml;hlten W&auml;hrung seit Anfang des Monats.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyCostMonthLast</code> : </li></td><td>Energiekosten in der gew&auml;hlten W&auml;hrung des letzten Monats.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyCostYear</code> : </li></td><td>Energiekosten in der gew&auml;hlten W&auml;hrung seit Anfang des Jahres.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyCostYearLast</code> : </li></td><td>Energiekosten in der gew&auml;hlten W&auml;hrung des letzten Jahres.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyDay</code> : </li></td><td>Energieverbrauch in kWh seit Mitternacht.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyDayLast</code> : </li></td><td>Gesamter Energieverbrauch des letzten Tages (Gestern).<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyMeter</code> : </li></td><td>Energieverbrauch in kWh seit Anfang seit Anfang des Monats wo der Gas-Versorger den Z&auml;hler abliest.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyMeterLast</code> : </li></td><td>Gesamter Energieverbrauch der letzten Z&auml;hlerperiode des Gas-Versorgers.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyMonth</code> : </li></td><td>Energieverbrauch in kWh seit Anfang seit Anfang des Monats (Mitternacht des 01.).<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyMonthLast</code> : </li></td><td>Gesamter Energieverbrauch im letzten Monat.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyYear</code> : </li></td><td>Energieverbrauch in kWh seit Anfang seit Anfang des Jahres (Mitternacht des 01. Januar).<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_EnergyYearLast</code> : </li></td><td>Gesamter Energieverbrauch in kWh des letzten Kalender-Jahres.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_FinanceReserve</code> : </li></td><td>Finanzielle Reserve basierend auf den Abschlagszahlungen die jeden Monat an den Gas-Versorger gezahlt werden. Bei negativen Werten ist von einer Nachzahlung auszugehen.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_MonthMeterReading</code> : </li></td><td>Anzahl der Monate seit der letzten Zählerablesung. Der Monat der Zählerablesung ist der erste Monat = 1.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_Meter</code> : </li></td><td>Z&auml;hlerstand am Gasz&auml;hler. Bei Differenzen muss das Offset-Attribut korrigiert werden.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_PowerCurrent</code> : </li></td><td>Aktuelle Heizleistung. (Mittelwert zwischen aktueller und letzter Messung)<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_PowerDayAver</code> : </li></td><td>Mittlere Heitzleistung seit Mitternacht.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_PowerDayMax</code> : </li></td><td>Maximale Leistungsaufnahme seit Mitternacht.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_PowerDayMin</code> : </li></td><td>Minimale Leistungsaufnahme seit Mitternacht.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_Vol1stDay</code> : </li></td><td>Erster Volumenmesswert des Tages (Mitternacht).<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_VolLastDay</code> : </li></td><td>Verbrauchtes Volumen des vorherigen Tages.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_Vol1stMonth</code> : </li></td><td>Erster Volumenmesswert des Monats (Mitternacht des 01.).<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_VolLastMonth</code> : </li></td><td>Verbrauchtes Volumen des vorherigen Monats.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>


<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_Vol1stYear</code> : </li></td><td>Erster Volumenmesswert des Jahres (Mitternacht des 01. Januar).<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_VolLastYear</code> : </li></td><td>Verbrauchtes Volumen des vorherigen Jahres.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_Vol1stMeter</code> : </li></td><td>Erster Volumenmesswert des Zeitraums seit Anfang des Monats wo der Gas-Versorger den Z&auml;hler abliest.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

<ul><ul>
	<table>
		<tr>
			<td>
			<tr><td><li><code>&lt;DestinationDevice&gt;_&lt;SourceCounterReading&gt;_VolLastMeter</code> : </li></td><td>Verbrauchtes Volumen des vorherigen Abrechnungszeitraums.<BR>
			</td></tr>
			</td>
		</tr>
	</table>
</ul></ul>

</ul>

=end html_DE

=cut
