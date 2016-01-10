# $Id: 98_MaxScanner.pm 10453 2016-01-11 00:00:00Z john $
####################################################################################################
#
#   98_MaxScanner.pm
#   The MaxScanner enables FHEM to capture temperature and valve-position of thermostats
#   in regular intervals
#
#	This module is written by john.
#
#	This file is part of fhem.
#
#	Fhem is free software: you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation, either version 2 of the License, or
#	(at your option) any later version.
#
#	Fhem is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#	GNU General Public License for more details.
#
#	You should have received a copy of the GNU General Public License
#	along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
#
#  25.10.15 - 1.0.0.0
#      initial build
#
#  Task-list
#      * define minimal Scan-Interval
#      * define credit threshold
#      * multiple shutters
#      * notify for shutter contacts and implicated thermostats
#      * check text off/on as desi-Temp
#
#   06.01.16
#      * RestartTimer
#   09.01.16
#      *  change: using of instead of NotifyFn explicit notify
#      *  fixed : erreous initial scenario
#      *  new   : get associatedDevices
#      *  change. scanTemp substitues scnEnabled
#   11.01.16 - 1.0.0.0
#      *  change: limit logging, when window open detected
#
####################################################################################################
package main;
use strict;
use warnings;
use Data::Dumper;
use vars qw(%defs);
use vars qw($readingFnAttributes);
use vars qw(%attr);
use vars qw(%modules);
my $MaxScanner_Version   = "1.0.0.1 - 11.01.2016";
my $MaxScanner_ModulName = "MaxScanner";

# minimal poll-rate for thermostat in minutes given by firmware
my $MaxScanner_BaseIntervall          = 3;
my $MaxScanner_DefaultCreditThreshold = 300;

# attributes for thermostat instance
my $MaxScanner_TXPerMinutes = 32;    # transmissions per hour

my $MaxScanner_AttrEnabled             = 'scanTemp';
my $MaxScanner_AttrShutterList         = 'scnShutterList';
my $MaxScanner_AttrProcessByDesiChange = 'scnProcessByDesiChange';
my $MaxScanner_AttrModeHandling        = 'scnModeHandling';

# attributes for module instance
my $MaxScanner_AttrCreditThreshold = 'scnCreditThreshold';
my $MaxScanner_AttrMinInterval     = 'scnMinInterval';

# define user defined attributes
my @MaxScanner_AttrForMax = (

  #$MaxScanner_AttrEnabled . ':0,1',
  $MaxScanner_AttrProcessByDesiChange . ':0,1',
  $MaxScanner_AttrShutterList,
  $MaxScanner_AttrModeHandling . ':NOCHANGE,AUTO,MANUAL'
);

#
##########################
# output format: <module name> <instance-name> <calling sub without prefix>.<line nr> <text>
sub MaxScanner_Log($$$)
{
  my ( $hash, $loglevel, $text ) = @_;
  my $xline       = ( caller(0) )[2];
  my $xsubroutine = ( caller(1) )[3];
  my $sub         = ( split( ':', $xsubroutine ) )[2];
  my $ss          = $MaxScanner_ModulName . "_";
  $sub =~ s/$ss//;
  my $instName =
    ( ref($hash) eq "HASH" ) ? $hash->{NAME} : $MaxScanner_ModulName;
  Log3 $hash, $loglevel, "$MaxScanner_ModulName $instName $sub.$xline " . $text;
}
##########################
sub MaxScanner_Initialize($)
{
  my ($hash) = @_;
  $hash->{DefFn}    = $MaxScanner_ModulName . '_Define';
  $hash->{UndefFn}  = $MaxScanner_ModulName . '_Undef';
  $hash->{SetFn}    = $MaxScanner_ModulName . '_Set';
  $hash->{GetFn}    = $MaxScanner_ModulName . '_Get';
  $hash->{AttrFn}   = $MaxScanner_ModulName . '_Attr';
  $hash->{NotifyFn} = $MaxScanner_ModulName . '_Notify';

  $hash->{AttrList} =
      $MaxScanner_AttrCreditThreshold
    . ':150,200,250,300,350,400 '
    . $MaxScanner_AttrMinInterval
    . ':3,6,9,12,15,18,21,24,27,30 '
    . 'disable:0,1 '
    . $readingFnAttributes;
  MaxScanner_Log '', 3, "Init Done with Version $MaxScanner_Version";
}

##########################
sub MaxScanner_RestartTimer($$)
{
  my ( $hash, $seconds ) = @_;
  my $name           = $hash->{NAME};

  $seconds = 1 if ( $seconds <= 0 );
  RemoveInternalTimer($name);

  my $sdNextScan = gettimeofday() + $seconds;
  InternalTimer( $sdNextScan, $MaxScanner_ModulName . '_Timer', $name, 1 );
}
##########################
sub MaxScanner_Define($$$)
{
  my ( $hash, $def ) = @_;
  my @a = split( "[ \t][ \t]*", $def );
  my $name = $a[0];
  MaxScanner_Log $hash, 4, "parameters: @a";
  if ( @a < 2 )
  {
    return 'wrong syntax: define <name> ' . $MaxScanner_ModulName;
  }

  # only one scanner instance is allowed
  # get the count of instances
  my @scanners = keys %{ $modules{$MaxScanner_ModulName}{defptr} };
  my $scannerCount = @scanners;
  if ($scannerCount > 0)
  {
     return 'only one scanner instance is allowed'; 
  }
  
  #.
  $hash->{helper}{thermostats} = ();
  $hash->{helper}{initDone}    = '';
  $hash->{VERSION}             = $MaxScanner_Version;

  # register modul
  $modules{$MaxScanner_ModulName}{defptr}{$name} = $hash;

  # create timer
  RemoveInternalTimer($name);
  my $xsub = $MaxScanner_ModulName . "_Timer";
  InternalTimer( gettimeofday() + 20, $xsub, $name, 0 );

  # MaxScanner_RestartTimer($hash,20);
  MaxScanner_Log $hash, 2, 'timer started';

  return undef;
}
##########################
sub MaxScanner_Undef($$)
{
  my ( $hash, $arg ) = @_;
  RemoveInternalTimer( $hash->{NAME} );
  MaxScanner_Log $hash, 2, "done";
  return undef;
}
###########################
sub MaxScanner_Get($@)
{
  my ( $hash, @a ) = @_;
  my $name = $hash->{NAME};
  my $ret  = "Unknown argument $a[1], choose one of associatedDevices:noArg";
  my $cmd  = lc( $a[1] );
  my @carr;

  MaxScanner_Log $hash, 4, 'cmd:' . $cmd;

  # check the commands
  if ( $cmd eq 'associateddevices' )
  {
    if ( defined( $hash->{helper}{associatedDevices} ) )
    {
      @carr = @{ $hash->{helper}{associatedDevices} };
      $ret = join( '<br/>', @carr );
    } else
    {
      $ret = 'no devices';
    }
  }
  return $ret;
}
###########################
sub MaxScanner_Set($@)
{
  my ( $hash, @a ) = @_;
  my $name  = $hash->{NAME};
  my $reINT = '^([\\+,\\-]?\\d+$)';    # int

  # standard commands with no parameter
  my @cmdPara     = ();
  my @cmdNoPara   = ('run');
  my @allCommands = ( @cmdPara, @cmdNoPara );
  my $strAllCommands =
    join( " ", (@cmdPara) ) . ' ' . join( ":noArg ", @cmdNoPara ) . ':noArg ';
  my $usage = "Unknown argument $a[1], choose one of " . $strAllCommands;

  # we need at least one argument
  return $usage if ( @a < 2 );
  my $cmd = $a[1];
  if ( $cmd eq "?" )
  {
    return $usage;
  }
  my $value = $a[2];

  # is command defined ?
  if ( ( grep { /$cmd/ } @allCommands ) <= 0 )
  {
    MaxScanner_Log $hash, 2, "cmd:$cmd no match for : @allCommands";
    return return "unknown command : $cmd";
  }

  # need we a parameter ?
  my $hits = scalar grep { /$cmd/ } @cmdNoPara;
  my $needPara = ( $hits > 0 ) ? '' : 1;
  MaxScanner_Log $hash, 4, "hits: $hits needPara:$needPara";

  # if parameter needed, it must be an integer
  return "Value must be an integer"
    if ( $needPara && !( $value =~ m/$reINT/ ) );

  # command run
  if ( $cmd eq "run" )
  {
    MaxScanner_Timer($name) if ( $hash->{helper}{initDone} );
  }

  return undef;
}

##########################
# handling of notifies
sub MaxScanner_Notify($$$)
{
  my ( $hash, $dev ) = @_;
  my $name = $hash->{NAME};
  my $disable = AttrVal( $name, 'disable', '0' );

  # no action if not initialized
  return if ( !$hash->{helper}{initDone} );

  # no action if disabled
  return if ( $disable eq '1' );

  my $devName = $dev->{NAME};

  #MaxScanner_Log $hash, 5, 'start: '.$devName;

  # get associated devices
  my @associated = @{ $hash->{helper}{associatedDevices} };

  # if not found return
  if ( !grep( /^$devName/, @associated ) )
  {
    return;
  }

  # get the event of the device
  my $devReadings = int( @{ $dev->{CHANGED} } );
  MaxScanner_Log $hash, 5, 'is associated: ' . $devName . ' check readings:' . $devReadings;

  my $found  = '';
  my $xevent = '';
  for ( my $i = 0 ; $i < $devReadings ; $i++ )
  {
    # <onoff: 0> , <desiredTemperature: 12.0>
    $xevent = $dev->{CHANGED}[$i];
    $xevent = '' if ( !defined($xevent) );

    #MaxScanner_Log $hash, 4,  'check event:<'.$xevent.'>';

    if ( $xevent =~ m/^(onoff|desiredTemperature|temperature):.*/ )
    {
      MaxScanner_Log $hash, 4, 'matching event:<' . $xevent . '>';
      $found = '1';
      last;
    }
  }

  # return if no matching with intersting properties
  return if ( !$found );

  # loop over all instances of scanner
  foreach my $instName ( sort keys %{ $modules{$MaxScanner_ModulName}{defptr} } )
  {
    my $instHash = $defs{$instName};
    MaxScanner_Log $instHash, 3, 'will start <' . $instName . '> triggerd by ' . $devName . ' ' . $xevent;
    MaxScanner_Timer($instName);
  }
}

##########################
# Gets the summary value of associated shutter contacts
sub MaxScanner_GetShutterValue($)
{
  my ($thermHash) = @_;
  my $retval = 0;

  # if no shutters exist
  if ( !defined( $thermHash->{helper}{shutterContacts} ) )
  {
    return $retval;
  }

  # get the array
  my @shuttersTemp = @{ $thermHash->{helper}{shutterContacts} };

  # loop over all shutters
  foreach my $shutterName (@shuttersTemp)
  {
    my $windowIsOpen = ReadingsVal( $shutterName, "onoff", 0 );
    MaxScanner_Log $thermHash, 5, $shutterName . ' onoff:' . $windowIsOpen;
    if ( $windowIsOpen > 0 )
    {
      $retval = 1;
      last;
    }
  }

  MaxScanner_Log $thermHash, 5, 'retval:' . $retval;
  return $retval;
}

##########################
# looks for shutterContacts for the given thermostat
sub MaxScanner_ShutterCheck($$)
{

  my ( $modHash, $thermHash ) = @_;
  my $thermName = $thermHash->{NAME};

  # get the list of associated shutter contacts
  my $strShutterNameList = AttrVal( $thermName, $MaxScanner_AttrShutterList, "?" );
  if ( $strShutterNameList eq '?' )
  {
    MaxScanner_Log $thermHash, 5,
      $thermName . ': found no definition for ' . $MaxScanner_AttrShutterList . ' got ' . $strShutterNameList;
    return;
  }

  #MaxScanner_Log $thermHash, 5, "found shutter definition list : ".$strShutterNameList;

  my @shutters;
  my @shuttersTemp = split( /,/, $strShutterNameList );

  #MaxScanner_Log $thermHash, 5, "shuttersTemp : ".join(',', @shuttersTemp);
  # validate each shutter contact
  foreach my $shutterName (@shuttersTemp)
  {
    #MaxScanner_Log $thermHash, 5, 'check shuttersTemp : '.$shutterName;

    # ignore empty strings
    if ( $shutterName eq '' )
    {
      next;
    }

    # ignore duplicated names
    if ( grep( /^$shutterName/, @shutters ) )
    {
      next;
    }

    # ignore unknown devices
    my $hash = $defs{$shutterName};
    if ( !$hash )
    {
      MaxScanner_Log $thermHash, 4, "unknown device : " . $shutterName;
      next;
    }

    # device is not a shutter contact
    if ( $hash->{type} ne 'ShutterContact' )
    {
      MaxScanner_Log $thermHash, 2, "device is not a shutter contact : " . $shutterName;
      next;
    }

    #MaxScanner_Log $thermHash, 5, 'accept shuttersTemp : '.$shutterName;
    push @shutters, $shutterName;
  }

  MaxScanner_Log $thermHash, 4, "accepted following shutters : " . join( ",", @shutters );

  $thermHash->{helper}{shutterContacts} = [@shutters];
}

##########################
# looks for MAX components
# called by Run
sub MaxScanner_Find($)
{
  my ($modHash)       = @_;
  my $modName         = $modHash->{NAME};
  my $numValidThermos = 0;
  my @shutterContacts = ();

  #------------------ look for all max-thermostats

  $modHash->{helper}{thermostats} = ();

  # loop over all max thermostats
  foreach my $aaa ( sort keys %{ $modules{MAX}{defptr} } )
  {
    my $hash = $modules{MAX}{defptr}{$aaa};

    # basic properties  are reqired
    if ( !defined( $hash->{IODev} )
      || !defined( $hash->{NAME} )
      || !defined( $hash->{type} ) )
    {
      MaxScanner_Log $modHash, 1, 'missing basic property for device: ' . $aaa;
      next;
    }

    #.
    # name of the max device
    my $name = $hash->{NAME};
    MaxScanner_Log $modHash, 5, "$name has type " . $hash->{type};

    # exit if it is not a HeatingThermostat
    next if $hash->{type} !~ m/^HeatingThermostat.*/;
    MaxScanner_Log $modHash, 5, $name . " is HeatingThermostat";

    # thermostat must be enabled for the scanner
    if ( AttrVal( $name, $MaxScanner_AttrEnabled, '?' ) ne '1' )
    {
      MaxScanner_Log $modHash, 5,
        $name . ' ' . $MaxScanner_AttrEnabled . ' is not active, therefore this device is ignored';
      next;
    }

    MaxScanner_Log $modHash, 5, $name . ' is enabled for scanner';

    # check special user attributes, if not exists, create them
    my $xattr = AttrVal( $name, 'userattr', '' );
    if ( !( $xattr =~ m/$MaxScanner_AttrShutterList/ ) )
    {
      # extend user attributes for scanner module
      my $scnCommands = $xattr . " " . join( " ", @MaxScanner_AttrForMax );
      my $fhemCmd = "attr $name userattr $scnCommands";
      fhem($fhemCmd);
      MaxScanner_Log $modHash, 4, $name . " initialized userAttributes";
    }

    # with keepAuto=1 Scanner cannot cooperate
    if ( AttrVal( $name, 'keepAuto', '0' ) ne '0'
      && AttrVal( $name, 'scnProcessByDesiChange', '0' ) eq '0' )
    {
      MaxScanner_Log $modHash, 0, $name . 'don\'t use keepAuto in conjunction with changeMode processing !!!';
      next;
    }

    MaxScanner_Log $modHash, 5, $name . " is accepted";
    $numValidThermos++;

    # check for shutter contacts
    MaxScanner_ShutterCheck( $modHash, $hash );

    # if there exist shuttercontacts
    if ( defined( $hash->{helper}{shutterContacts} ) )
    {
      # build sum of all sc's
      push( @shutterContacts, @{ $hash->{helper}{shutterContacts} } );
      MaxScanner_Log $modHash, 5, "shutterContacts : " . join( ",", @shutterContacts );
    }

    # create helper reading or thermostat
    $hash->{helper}{NextScan} = int( gettimeofday() )
      if ( !defined( $hash->{helper}{NextScan} ) );

    # this is needed for sorting later
    $modHash->{helper}{thermostats}{$name} = $hash->{helper}{NextScan};
  }

  # remove duplicates
  my %shutterHash = map { $_ => 1 } @shutterContacts;
  @shutterContacts = keys %shutterHash;

  # $modHash->{helper}{shutterContacts} = [@shutterContacts];

  my @thermos = keys %{ $modHash->{helper}{thermostats} };
  my @allAssociatedDevices = ( @shutterContacts, @thermos );

  $modHash->{helper}{associatedDevices} = [@allAssociatedDevices];
}
##########################################################
# return a hash with useful infos relating to weekprofile
sub MaxScanner_WeekProfileInfo($)
{
  my ($name)    = @_;
  my %result    = ();
  my $loopCount = 0;
  $result{desired} = undef;

  # return if ($name ne 'HT.JOHN');  # !!!
  my $hash = $defs{$name};
  if ( !$hash )
  {
    return undef;
  }
  my %dayNames = (
    0 => "Sat",
    1 => "Sun",
    2 => "Mon",
    3 => "Tue",
    4 => "Wed",
    5 => "Thu",
    6 => "Fri"
  );
  MaxScanner_Log $hash, 5, "----- Start ---------";
  my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime(time);

  # determine the current weekday
  my $maxWday = $wday + 1;

  # 7 equals  0   for max
  $maxWday = 0 if ( $maxWday == 7 );

  # determine next weekday
  my $WdayNext = $maxWday + 1;
  $WdayNext = 0 if ( $WdayNext == 7 );

  # get the reading names for wanted readings
  my $profileTime     = "weekprofile-$maxWday-$dayNames{$maxWday}-time";
  my $profileTemp     = "weekprofile-$maxWday-$dayNames{$maxWday}-temp";
  my $profileTempNext = "weekprofile-$WdayNext-$dayNames{$WdayNext}-temp";

  # get desired-profile for the current day
  # example:weekprofile-0-Sat-temp 20.0 °C  /  21.0 °C  /  21.0 °C  /  21.0 °C  /  20.0 °C  /  20.0 °C
  my $ltemp = ReadingsVal( $name, $profileTemp, '' );

  # get profile for the next day
  my $ltempNext = ReadingsVal( $name, $profileTempNext, '' );
  MaxScanner_Log $hash, 5, "$profileTemp:$ltemp $profileTempNext:$ltempNext";

  # current and next must be defined
  if ( !$ltemp || !$ltempNext )
  {
    return undef;
  }

# read profileTime
# example: weekprofile-0-Sat-time 00:00-06:00  /  06:00-08:00  /  08:00-16:00  /  16:00-22:00  /  22:00-23:55  /  23:55-00:00
  my $lProfileTime = ReadingsVal( $name, $profileTime, '' );

  # must be defined
  if ( !$lProfileTime )
  {
    return undef;
  }
  MaxScanner_Log $hash, 5, "$profileTime:$lProfileTime";

  # split desired-value via slash
  my @tempArr = split( '/', $ltemp );

  # the same for the next profile-step
  my @tempArrNext = split( '/', $ltempNext );

  # prepare array for desired-values
  ${ result { tempArr } } = ();

  # store all desired values of the day to an array
  $loopCount = 1;
  for my $ss (@tempArr)
  {
    # extract temperature by looking for number
    my ($xval) = ( $ss =~ /(\d+\.\d+)/ );
    MaxScanner_Log $hash, 5, "desi-Temp No. $loopCount:$xval";
    push( @{ $result{tempArr} }, $xval );
    $loopCount++;
  }

  # extract first temperature of the next day
  my ($xval) = ( $tempArrNext[0] =~ /(\d+\.\d+)/ );
  push( @{ $result{tempArr} }, $xval );
  MaxScanner_Log $hash, 5, "temp next day:$xval";

  # analyze the time-periods of the profile
  #00:00-08:00  /  08:00-22:00  /  22:00-00:00
  my @atime = split( '/', $lProfileTime );

  # create serial form of current date
  my $xDate = mktime( 0, 0, 0, $mday, $mon, $year );
  my @t = localtime($xDate);
  $xDate = sprintf( "%02d:%02d", $t[2], $t[1] );

  # split profile-time using slash as splitter
  # and remove supernummery spaces  ==> 00:00-23:55 23:55-00:00
  my @btime = split( '\s*/\s*', $lProfileTime );

  # MaxScanner_Log $hash,5,"profile-time:@atime xDate:$xDate";
  MaxScanner_Log $hash, 5, "profile-time:@btime";
  my $curTime = gettimeofday();
  my $count   = 0;

  # prepeare array
  @{ $result{timeArr} } = ();

  # loop over all time-slots
  $result{tempFound} = 0;
  for my $ss (@btime)
  {
    # extract start-time and stop-time
    my ( $a1, $a2 ) = ( $ss =~ /(\d+:\d+)\-(\d+:\d+)/ );
    if ( !defined($a2) )
    {
      MaxScanner_Log $hash, 2, "$name a2 not defined for $ss";
      next;
    }

    # adjust stop-time when special time 24:00
    $a2 = '24:00' if ( $a2 eq "00:00" );    # ende anpassen
                                            # extract hour and minute of stop-time
    my ( $xhour, $xmin ) = ( $a2 =~ /(\d+):(\d+)/ );

    # create serial date
    $xDate = mktime( 0, $xmin, $xhour, $mday, $mon, $year );

    # create string form
    my $sDate = FmtDateTime($xDate);
    MaxScanner_Log $hash, 5, "stopDate:$sDate segment-count:$count";

    # store the stop time to result-container
    push( @{ $result{timeArr} }, $xDate );

    # if current time > found stop-date
    if ( $curTime > $xDate )
    {    # mark the last found segment
      $result{tempFound} = $count + 1;
      MaxScanner_Log $hash, 5, "segment-count:$count found with " . FmtDateTime($xDate);
    }
    $count = $count + 1;
  }

  # prepare the hash
  # stop-time for the current time-slot
  $result{nextSwitchDate} = @{ $result{timeArr} }[ $result{tempFound} ];

  # desired for the next time slot
  $result{nextDesired} = @{ $result{tempArr} }[ $result{tempFound} + 1 ];

  # desired for the current time slot
  $result{desired} = @{ $result{tempArr} }[ $result{tempFound} ];

  # desired must be defined
  if ( !defined( $result{desired} ) )
  {
    MaxScanner_Log $hash, 2, "$name: desired not defined";
    return undef;
  }
  MaxScanner_Log $hash, 4, "tempFound-Idx :" . $result{tempFound};
  MaxScanner_Log $hash, 4, "nextSwitchDate:" . FmtDateTime( $result{nextSwitchDate} );
  MaxScanner_Log $hash, 4, "desired       :" . $result{desired};
  MaxScanner_Log $hash, 4, "nextDesired   :$result{nextDesired}";
  return \%result;
}
######################################################
# loop over all thermostats and check what is to do
sub MaxScanner_Work($$$)
{
  my $reUINT = '^([\\+]?\\d+)$';    # uint without whitespaces
  my ( $modHash, $thermi_sort, $numWorkIntervall ) = @_;
  my $scanDynamic = '';
  my $settingDone = '';             # end loop if a set command was performed
  my @scan_time;
  my $modName = $modHash->{NAME};

  # loop the sorted list over enabled thermostats
  foreach my $therm (@$thermi_sort)
  {
    #MaxScanner_Log $modHash, 3, Dumper($therm);
    my $hash       = $defs{$therm};
    my $sdCurTime  = gettimeofday();            #serial date of current date
    my $strCurTime = FmtDateTime($sdCurTime);

    my $boolDesiChange = AttrVal( $therm, $MaxScanner_AttrProcessByDesiChange, '0' ) eq '1';
    my $strModeHandling = uc AttrVal( $therm, $MaxScanner_AttrModeHandling, 'AUTO' );
    my $dontChangeMe = '';

    #. check timestamp of the reading temperature
    my $strTempTime = ReadingsTimestamp( $therm, 'temperature', '' );
    if ( $strTempTime eq "" )
    {
      MaxScanner_Log $hash, 1, '!! READING:temperature is not defined !!';
      next;
    }

    # get desired timestamp
    my $strDesiTime = ReadingsTimestamp( $therm, 'desiredTemperature', '' );

    # get next scan serial date
    my $sdNextScan = $hash->{helper}{NextScan};
    MaxScanner_Log $hash, 4,
      'ns:' . FmtDateTime($sdNextScan) . ' strDesiTime:' . $strDesiTime . ' ForceAuto:' . $boolDesiChange;

    # convert temperature time into serial format
    my $sdTempTime = time_str2num($strTempTime);

    # convert desired timestamp into serial format if possible, otherwise use current time
    my $sdDesiTime = ($strDesiTime) ? time_str2num($strDesiTime) : gettimeofday();

    #. check Cul
    my $strCulName;
    my $strCreditTime = '';
    my $numCulCredits;
    my $numDutyCycle = '?';
    my $strIOHash    = $defs{$therm}{IODev};    # CULMAX0, hash of IO-Devices
    my $strIOName    = $strIOHash->{NAME};
    my $strIOType    = $strIOHash->{TYPE};      # CUL_MAX,MAXLAN type des IO-Devices
    my $isCUL        = 1;

    #.
    MaxScanner_Log $hash, 4, "TYPE:$strIOType IOName:$strIOName";

    # if com-device is a MAXLAN
    if ( $strIOType eq "MAXLAN" )
    {
      # determine name of IO devices
      $strCulName = $strIOName;

      # get dutycycle
      my $strDutyCycle = ReadingsVal( $strCulName, 'dutycycle', '?' );

      # if not a number try to get it via internal value
      $strDutyCycle = InternalVal( $strCulName, 'dutycycle', 0 )
        if ( $strDutyCycle eq "?" );

      # get the timestamp of reading dutycycle
      $strCreditTime = ReadingsTimestamp( $strCulName, 'dutycycle', '' );

      # take the middle term of ...
      my ( $a1, $a2, $a3 ) = ( $strDutyCycle =~ /([\s]*)(\d+)(.*)/ );
      if ( defined($a2) )
      {
        $numDutyCycle = $a2;
      } else
      {
        $numDutyCycle = 100;
        MaxScanner_Log $hash, 2, '!! dutycyle not a number: <' . $strDutyCycle . '>; force to 100';
      }

      # transform dutycycle to CulCredits
      $numCulCredits = ( 100 - $numDutyCycle ) * 10;
      $isCUL         = '';
    }

    # we got a CUL
    else
    {
      # determine name of IO devices
      $strCulName = $strIOHash->{IODev}{NAME};

      # get the credit's timestamp
      $strCreditTime = ReadingsTimestamp( $strCulName, 'credit10ms', '' );

      # get the credits
      $numCulCredits = ReadingsVal( $strCulName, 'credit10ms', 0 );

      # force dynamic scanning for CUL
      $scanDynamic = 1;
    }

    # because cube not knows msgcnt, we fix the timestamp
    my $strLastTransmit =
      ($isCUL) ? ReadingsTimestamp( $therm, 'msgcnt', '' ) : FmtDateTime( gettimeofday() - 20 );

    # msgcnt must exist
    if ( $strLastTransmit eq '' )
    {
      MaxScanner_Log $hash, 1, '!! Reading:msgcnt is not defined';
      next;
    }

    # convert timestamp lastTransmit to serial date
    my $sdLastTransmit = time_str2num($strLastTransmit);
    MaxScanner_Log $hash, 4,
      "CulName:$strCulName CulCredits:$numCulCredits " . "CreditTime:$strCreditTime dutyCycle:$numDutyCycle";

    # somtimes we get "no answer" instead of a number
    if ( !( $numCulCredits =~ m/$reUINT/ ) )
    {
      MaxScanner_Log $hash, 1, '!! credit10ms/dutycycle must be a number';
      next;
    }

    # creditTime must exist
    if ( $strCreditTime eq '' )
    {
      MaxScanner_Log $hash, 1, '!! READINGS:credit10ms is not defined';
      next;
    }

    # convert credit time to serial date
    my $sdCreditTime = time_str2num($strCreditTime);

    # get current desired temperature
    my $numDesiTemp = ReadingsVal( $therm, 'desiredTemperature', '' );

    if ( $numDesiTemp eq 'on' || $numDesiTemp eq 'off' )    #Hint by MrHeat
    {
      MaxScanner_Log $hash, 3, 'reading desiredTemperature: thermostat is forced on/off. Skipping thermostat';
      next;
    }

    # desi temp must be a number
    elsif ( $numDesiTemp eq '' )
    {
      MaxScanner_Log $hash, 1, '!! reading desiredTemperature is not available';
      next;
    }

    # get current mode
    my $strMode = ReadingsVal( $therm, 'mode', '' );

    # current mode must be defined
    if ( $strMode eq "" )
    {
      MaxScanner_Log $hash, 1, '!! reading mode is not available';
      next;
    }

    # get weekprofile-Info
    my $weekProfile = MaxScanner_WeekProfileInfo($therm);

    # must be defined
    if ( !defined($weekProfile) )
    {
      MaxScanner_Log $hash, 1, '!! weekprofile is not available';
      next;
    }

    # don't change mode if the latency is active; only cul is affected
    if ( $sdLastTransmit + 5 >= $sdCurTime && $isCUL )
    {
      MaxScanner_Log $hash, 4, 'no action due transmission latency';
      next;
    }

    # get desired of weekprofile
    my $normDesiTemp = $weekProfile->{desired};

    # get window-open temperature
    my $numWinOpenTemp = ReadingsVal( $therm, 'windowOpenTemperature', '-1' );

    # get the additional credits calculated from the elapsed time
    my $numCreditDiff = ( $sdCurTime - $sdCreditTime );
    my $numCreditThreshold = AttrVal( $modName, $MaxScanner_AttrCreditThreshold, $MaxScanner_DefaultCreditThreshold );

    # calculate resulting credits
    my $numCredit = $numCulCredits + $numCreditDiff;

    # limit the result
    $numCredit = 900 if ( $numCredit > 900 );
    MaxScanner_Log $hash, 4,
        'CulCredits:'
      . $numCulCredits
      . ' Credits:'
      . int($numCredit)
      . ' scanDynamic:'
      . $scanDynamic
      . ' CreditThreshold:'
      . $numCreditThreshold;

    # determine next scan time depending on the time of last scan
    my $sdNextScanOld = $sdNextScan;

    # preset the minimal timestamp:
    my $nextPlan = $sdNextScan;

    # if dynamic scanning
    if ($scanDynamic)
    {
      # 17 secs before next scan time
      $nextPlan = $sdTempTime + $numWorkIntervall * 60 - 17;
    }

    # static scanning (CUBE)
    else
    {
      $nextPlan = $sdNextScan + $numWorkIntervall * 60;
    }

    # adjust the next scantime until it is in future
    $nextPlan = $nextPlan + ( 60 * $MaxScanner_BaseIntervall ) while ( $sdCurTime > $nextPlan );
    $sdNextScan = $nextPlan;
    MaxScanner_Log $hash, 4, 'ns:' . FmtTime($sdNextScan) . ' nsOld:' . FmtTime($sdNextScanOld);

    # basic inits if thermostat if not not already done
    if ( !defined( $hash->{helper}{TemperatureTime} ) )
    {
      MaxScanner_Log $hash, 4, 'create helpers with ns:' . FmtDateTime($sdNextScan);
      $hash->{helper}{TemperatureTime}    = $sdTempTime;    # timestamp of the last receive of temperature
      $hash->{helper}{DesiTime}           = $sdDesiTime;    # timestamp of the last receive of desired
      $hash->{helper}{WinWasOpen}         = 0;
      $hash->{helper}{TempBeforeWindOpen} = $numDesiTemp;

      # $hash->{helper}{LastWasAutoReset}   = '';
      $hash->{helper}{leadDesiTemp}  = ($boolDesiChange) ? $normDesiTemp                : $numDesiTemp;
      $hash->{helper}{desiredOffset} = ($boolDesiChange) ? $numDesiTemp - $normDesiTemp : 0;
      $hash->{helper}{switchDate}    = undef;
      $hash->{helper}{LastCmdDate}   = $sdCurTime;
      $hash->{helper}{gotTempTS}     = 0;
    }

    # gather the timestamp for next profile switch
    my $switchDate = ( defined($weekProfile) ) ? $weekProfile->{nextSwitchDate} : $sdDesiTime;

    # create a helper if not already done
    $hash->{helper}{switchDate} = $switchDate
      if ( !defined( $hash->{helper}{switchDate} ) );

    # if switchDate is changed, then adjust leading desired
    if ( $hash->{helper}{switchDate} != $switchDate )
    {
      $hash->{helper}{gotTempTS}          = 0;
      $hash->{helper}{switchDate}         = $switchDate;
      $hash->{helper}{leadDesiTemp}       = $normDesiTemp;
      $hash->{helper}{TempBeforeWindOpen} = $normDesiTemp;    # MrHeat
      $hash->{helper}{desiredOffset}      = 0;
      MaxScanner_Log $hash, 3, "reset leadDesiTemp:" . $hash->{helper}{leadDesiTemp};

      # when triggermode ModeChange and mode is manual, we must switch to auto to force the new setpoint/desired
      if ( !$boolDesiChange && ( $strMode eq 'manual' ) && ( $normDesiTemp != $numDesiTemp ) )
      {
        my $cmd = "set $therm desiredTemperature auto";
        fhem($cmd);
        $hash->{helper}{LastCmdDate} = $sdCurTime;
        $settingDone = 1;
        MaxScanner_Log $hash, 3, "switchTime: <<$cmd>>";
      }

      # now stop further actions with this thermostat, and wait for activation by the weekprofile
      # next;
    }

    # if mode switch is active, then offset must be 0
    if ( !$boolDesiChange && $hash->{helper}{desiredOffset} != 0 )
    {
      $hash->{helper}{desiredOffset} = 0;
      MaxScanner_Log $hash, 4, 'force desiredOffset to 0';
    }

    # determine nextScan for CUL-like devices
    if ($scanDynamic)
    {
      # if temperature time is younger than old time, then determine nextScan
      if ( $sdTempTime != $hash->{helper}{TemperatureTime} )
      {
        $hash->{helper}{gotTempTS} = 1;

        # remember timerstamp
        $hash->{helper}{TemperatureTime} = $sdTempTime;
        $hash->{helper}{NextScan}        = int($sdNextScan);
        $hash->{helper}{NextScanTimestamp} =
          FmtDateTime( $hash->{helper}{NextScan} );
        MaxScanner_Log $hash, 3, 'TEMPERATURE received at ' . $strTempTime . ', ==> new ns:' . FmtDateTime($sdNextScan);
      }
    }

    # get shutter's state
    my $boolWinIsOpenByFK = MaxScanner_GetShutterValue($hash) > 0;

    # opened window can also be detected by temperature fall
    # Don't change mode, if WindowOpen is recognized by temperature fall
    # then desiredTemp=WidowOpenTemp
    my $boolWinIsOpenByTempFall = $numDesiTemp == $numWinOpenTemp;

    # don't touch the thermostat, if windowOpen is recognized
    if ( $boolWinIsOpenByFK || $boolWinIsOpenByTempFall )
    {
      MaxScanner_Log $hash, 3,
        '<<stage 1>> no action due open window; desi-temp before window open:' . $hash->{helper}{TempBeforeWindOpen}
        if ($hash->{helper}{WinWasOpen} == 0);
      $hash->{helper}{WinWasOpen} = 1;
      $dontChangeMe = 1;

      #next;
    }

    # window is closed
    else
    {
      # now window is closed and it was open before
      if ( $hash->{helper}{WinWasOpen} > 0 )
      {
        #  ----------- <<stage 1>>  it was just closed ---------
        if ( $hash->{helper}{WinWasOpen} == 1 )
        {
          # switch to state 2: we are waiting for desi-temp
          $hash->{helper}{WinWasOpen} = 2;
          MaxScanner_Log $hash, 3,
            "strMode:$strMode DesiTemp:$numDesiTemp TempBeforeWindOpen:" . $hash->{helper}{TempBeforeWindOpen};

          # now set in each case desired temperature,
          # we expect desired temperature receive and than procede with scanner
          # therefore we will get no problem, even there is a delay by command queue
          $numCredit -= 110;    # therfore our credit counter must be reduced
          my $cmd =
              "set $therm desiredTemperature "
            . ( $strMode eq 'auto' ? 'auto' : '' ) . ' '
            . $hash->{helper}{TempBeforeWindOpen};    #MrHeat
          fhem($cmd);
          $hash->{helper}{LastCmdDate} = $sdCurTime;
          MaxScanner_Log $hash, 3, '<<stage 2>>due window is closed: ' . $cmd;
          $hash->{helper}{DesiTime} = $sdDesiTime;    # remember timestamp of desiTemp

          # no further action after changing desired
          # abort, due we waiting for feedback of desiTemp
          next;
        }

        # -------- <<stage 2 >> we are waiting for desitemp -----------------
        elsif ( $hash->{helper}{WinWasOpen} == 2 )
        {
          # forward to next step only, if timestamp of desiredTemp is changed
          if ( $hash->{helper}{DesiTime} == $sdDesiTime )
          {
            next;
          }
          MaxScanner_Log $hash, 3,
            '<<stage 3>> received new desiredTemperature after opened window: continue scanning now';

          # window open statemachine closed
          $hash->{helper}{WinWasOpen} = 0;
        }
      } else
      {
        # <<stage 0>> ----------------- window is closed and was closed before
        # only notice, if after window was closed desiTemp is received.
        $hash->{helper}{TempBeforeWindOpen} = $numDesiTemp;

        # calculate expected desiTemp
        my $expectedDesiTemp = $hash->{helper}{leadDesiTemp} + $hash->{helper}{desiredOffset};
        MaxScanner_Log $hash, 4,
          "numDesiTemp:$numDesiTemp expectedDesiTemp:$expectedDesiTemp leadDesiTemp:" . $hash->{helper}{leadDesiTemp};
        MaxScanner_Log $hash, 4, "normDesiTemp:$normDesiTemp desiredOffset:" . $hash->{helper}{desiredOffset};

        # if the expected value does not match, than desired was changed outside
        # but only, if we got temperature after a desired change by w-profile
        if ( $expectedDesiTemp != $numDesiTemp && $hash->{helper}{gotTempTS} == 1 )
        {
          $hash->{helper}{leadDesiTemp}  = $numDesiTemp;
          $hash->{helper}{desiredOffset} = 0;
          MaxScanner_Log $hash, 3, "change leadDesiTemp due manipulation:" . $hash->{helper}{leadDesiTemp};
        }
      }
    }

    # if mode equals boost, the don't change anything
    if ( $strMode eq 'boost' )
    {
      MaxScanner_Log $hash, 3, 'no action due boost';
      $dontChangeMe = 1;

      #next;
    }

    # if we perform modeChange and are in auto mode and next scan is near to the profile switch date
    # then do not perform switch, because the profile should change the desired just in time
    if (!$boolDesiChange
      && $strMode eq 'auto'
      && $sdNextScan >= $weekProfile->{nextSwitchDate} - 60 )
    {
      $hash->{helper}{NextScan} = $weekProfile->{nextSwitchDate} + 60;
      my $ss = FmtDateTime( $hash->{helper}{NextScan} );
      $hash->{helper}{NextScanTimestamp} = $ss;
      MaxScanner_Log $hash, 3, 'no action due soon a week-profile switch point is reached ns:' . $ss;
      $dontChangeMe = 1;
    }

    #---------------
    # next; # !!!
    #---------------
    MaxScanner_Log $hash, 4, "Trigger Mode Desi-Change:$boolDesiChange ";

    # if scan time is exceeded and no other setting was done,
    # we check to trigger the thermostat
    if ( !$dontChangeMe
      && !$settingDone
      && ( $sdCurTime >= $hash->{helper}{NextScan} ) )
    {
      # in each case store NextScan, this is the preliminary scan time,
      # if there are not enough credits
      # if we can transmit, the timestamp for NextScan will be again set ,
      # after receiving of temperature
      $hash->{helper}{NextScan} = int($sdNextScan);

      # if  we got enough credits, so we can trigger the thermostat
      if ( $numCredit >= $numCreditThreshold )
      {
        # the estimated reduction of credits after execution of a trigger
        $numCredit -= 110;
        my $cmd;
        my $leadDesiTemp = $hash->{helper}{leadDesiTemp};
        my $desiOffset   = $hash->{helper}{desiredOffset};

        # trigger thermostat by changing the desired temperature
        if ($boolDesiChange)
        {
          # perform trigger with offest and determin it
          if ( $desiOffset == 0 )
          {
            # calc the difference between current and desired temperature
            my $currentTemp = ReadingsVal( $therm, 'temperature', $normDesiTemp );
            my $diff = $normDesiTemp - $currentTemp;

            # calc the offset
            if ( $diff >= 0 )    # soll > ist
            {
              $desiOffset = 0.5;
            } else
            {                    # soll < ist
              $desiOffset = -0.5;
            }
          }

          # perform trigger without offset
          else
          {
            # force to zero
            $desiOffset = 0;
          }

          # calc the target desi temp
          my $newTemp = $leadDesiTemp + $desiOffset;

          # use current mode for default
          my $setMode = ( $strMode eq 'manual' ) ? '' : 'auto';

          if ( $strModeHandling eq 'AUTO' )
          {
            $setMode = 'auto';
          } elsif ( $strModeHandling eq 'MANUAL' )
          {
            $setMode = '';
          }

          $cmd = "set $therm desiredTemperature $setMode $newTemp";
        }

        # trigger thermostat by changing of mode
        else
        {
          my $modeCommand = ( $strMode eq 'manual' ) ? 'auto' : '';
          $cmd = "set $therm desiredTemperature " . $modeCommand . " $leadDesiTemp";

          # MaxScanner_Log $hash, 5, 'cmd:'.$cmd.'  modeCommand:'.$modeCommand.' strMode:'.$strMode
        }

        # exec command, at least 180 seconds after last command send
        if ( $sdCurTime > $hash->{helper}{LastCmdDate} + 180 )
        {
          fhem($cmd);
          MaxScanner_Log $hash, 3, "<<$cmd>>";
          $hash->{helper}{LastCmdDate}   = $sdCurTime;
          $hash->{helper}{desiredOffset} = $desiOffset;

          # mark execution of a command, to shortcut the loop later
          $settingDone = 1;
        } else
        {
          MaxScanner_Log $hash, 3, ' Wait at least 180 sec . after last command';
        }

        # if we are using CUL, then dynamic scanning
        if ($scanDynamic)
        {
          $hash->{helper}{NextScan} = int( $sdCurTime + 60 );
        } else    # if CUBE
        {
          $hash->{helper}{NextScan} = int( $sdCurTime + $numWorkIntervall * 60 );
        }
      }

      # there are to less credits or other preventing reasons, so we have to wait
      else
      {
        # determine the waiting time
        my $numDiffCredit = $numCreditThreshold - $numCredit;
        my $numDiffTime   = 0;

        # the waiting time must be greater then the needed credits
        # and must be a multiple of the baseinterval
        while ( $numDiffCredit > $numDiffTime )
        {
          $numDiffTime += ( 60 * $MaxScanner_BaseIntervall );
        }

        # adjust, so the check is called, before the calculated scan time is running out
        $sdNextScan += $numDiffTime - ( 60 * $MaxScanner_BaseIntervall );
        $hash->{helper}{NextScan} = int($sdNextScan);
        MaxScanner_Log $hash, 3,
            ' not enough credits( '
          . int($numCredit)
          . ' ) need '
          . int($numDiffCredit)
          . "/$numDiffTime ns:"
          . FmtDateTime($sdNextScan);

        # move the timestamp of all thermostats, which follows on the current this ensures the round robin rule
        foreach my $thAdjust (@$thermi_sort)
        {
          # if the timestamp is younger then the timestamp of the current thermostat, move it
          if ( $defs{$thAdjust}{helper}{NextScan} < $hash->{helper}{NextScan} )
          {
            # adjust the timestamp
            $defs{$thAdjust}{helper}{NextScan} += int($numDiffTime);

            # string representation of nextScan
            my $ss = FmtDateTime( $defs{$thAdjust}{helper}{NextScan} );
            $defs{$thAdjust}{helper}{NextScanTimestamp} = $ss;
            MaxScanner_Log $hash, 3, "adjust $thAdjust to $ss";
          }
        }
      }
    }

    # nothing is to do, so we wait
    else
    {
      MaxScanner_Log $hash, 4, ' WAITING ... ns : ' . FmtTime( $hash->{helper}{NextScan} );
    }

    # store NextScan in an array, for optimized timer setup
    push( @scan_time, $hash->{helper}{NextScan} );
    MaxScanner_Log $hash, 5, '++++++++ ';

    # foreach thermostat
  }

  # calculate the value for the timer
  # sort the trigger times of the thermostats
  my @scan_time_sort = sort @scan_time;

  # minimal time difference
  my $numDiffTime = 5;
  my $numCurTime  = int( gettimeofday() );

  # if we got at least one thermostat
  if ( @scan_time_sort >= 1 )
  {
    # use the scanTime with the smallest value
    my $diff = $scan_time_sort[0] - $numCurTime;

    # minimal difference
    $diff = 2 if ( $diff < 2 );
    if ( $diff > 2 )
    {
      $numDiffTime = int($diff);
      MaxScanner_Log $modHash, 3, ' next scan in seconds : ' . $numDiffTime;
    }
  }

  # return the waiting time in seconds
  return $numDiffTime;
}
##########################

sub MaxScanner_Run($)
{
  my ($name)          = @_;
  my $hash            = $defs{$name};
  my $reUINT          = '^([\\+]?\\d+)$';
  my $numValidThermos = 0;
  my $nn              = $MaxScanner_BaseIntervall;
  my $numMinInterval = ( AttrVal( $name, 'scnMinInterval', $nn ) =~ m/$reUINT/ ) ? $1 : $nn;

  #.
  my $retVal = 5;

  # loop forever
  while (1)
  {
    # find all thermostats
    MaxScanner_Find($hash);
    my $thermos = $hash->{helper}{thermostats};

    if ( !$hash->{helper}{initDone} )
    {
      $hash->{helper}{initDone} = 1;
      MaxScanner_Log $hash, 4, "init done";
    }

    # sort the thermostats concering the nextScan timestamp
    my @thermi_sort = sort { $thermos->{$a} <=> $thermos->{$b} } keys %{$thermos};
    MaxScanner_Log $hash, 4, "found " . scalar(@thermi_sort) . " thermostats";

    # number of valid thermostats
    $numValidThermos = scalar(@thermi_sort);

    # stop, if we got no thermostat
    last if ( $numValidThermos <= 0 );

    # a maximum of 32 thermostats is allowed
    $numValidThermos = $MaxScanner_TXPerMinutes if ( $numValidThermos > $MaxScanner_TXPerMinutes );

    # calculate the optimal scan interval
    my $numWorkIntervall = int( 60 / int( $MaxScanner_TXPerMinutes / $numValidThermos ) );
    $numWorkIntervall = $numMinInterval if ( $numWorkIntervall < $numMinInterval );

    # adjust the intervall, so it is a multiple of the BaseIntervall
    $numWorkIntervall += ( $MaxScanner_BaseIntervall - ( $numWorkIntervall % $MaxScanner_BaseIntervall ) )
      if ( $numWorkIntervall % $MaxScanner_BaseIntervall != 0 );

    $hash->{helper}{workInterval} = $numWorkIntervall;

    #.
    MaxScanner_Log $hash, 4, "optimal scan intervall:$numWorkIntervall";
    $retVal = MaxScanner_Work( $hash, \@thermi_sort, $numWorkIntervall );

    # exit loop
    last;
  }
  return $retVal;
}

##########################
# called by internal timer
sub MaxScanner_Timer($)
{
  my ($name)          = @_;
  my $hash            = $defs{$name};
  my $re01            = '^([0,1])$';    # only 0,1
  my $stateStr        = "processing";
  my $numValidThermos = 0;
  my $isDisabled = ( AttrVal( $name, 'disable', 0 ) =~ m/$re01/ ) ? $1 : '';
  my $numDiffTime = 5;
  my $sdNextScan;

  MaxScanner_Log $hash, 3, '------------started ---------------- instance:' . $name;

  # loop
  while (1)
  {
    # no further action if disabled
    if ($isDisabled)
    {
      MaxScanner_Log $hash, 4, "is disabled";
      $stateStr = "disabled";
      last;
    }

    # remove the timer of the script version
    RemoveInternalTimer('MaxScanRun');
    
    # call runner
    $numDiffTime = MaxScanner_Run($name);
    last;
  }

  # update state
  readingsSingleUpdate( $hash, 'state', $stateStr, 0 );

  MaxScanner_RestartTimer( $hash, $numDiffTime );

  $sdNextScan = gettimeofday() + $numDiffTime;
  $hash->{helper}{nextWorkTime} = FmtDateTime($sdNextScan);
}

##########################
# attribute handling
sub MaxScanner_Attr($$$$)
{
  my ( $command, $name, $attribute, $value ) = @_;
  my $msg    = undef;
  my $hash   = $defs{$name};
  my $reUINT = '^([\\+]?\\d+)$';

  MaxScanner_Log $hash, 4, 'name:' . $name . ' attribute:' . $attribute . ' value:' . $value . ' command:' . $command;

  if ( $attribute eq 'disable' )
  {
    # call timer delayed
    MaxScanner_RestartTimer( $hash, 1 ) if ( $hash->{helper}{initDone} );
  }

  #. threshold
  elsif ( $attribute eq $MaxScanner_AttrCreditThreshold )
  {
    my $isInt = ( $value =~ m/$reUINT/ ) ? $1 : '';
    if ( !$isInt )
    {
      $msg = 'value must be a number:' . $value;
      return $msg;
    }

    if ( $value < 150 || $value > 600 )
    {
      $msg = 'value out of range [150..600] ' . $value;
      return $msg;
    }

  }

  #. scnMinInterval
  elsif ( $attribute eq $MaxScanner_AttrMinInterval )
  {
    my $isInt = ( $value =~ m/$reUINT/ ) ? $1 : '';
    if ( !$isInt )
    {
      $msg = 'value must be a number:' . $value;
      return $msg;
    }

    if ( $value < 3 || $value > 60 )
    {
      $msg = 'value out of range [3..60] ' . $value;
      return $msg;
    }
  }

  return $msg;
}
1;

=pod
=begin html

<a name="MaxScanner"></a>
<h3>MaxScanner</h3>
     <p>The MaxScanner-Module enables FHEM to capture temperature and valve-position of thermostats in regular intervals. <p/>
<ul>
  <a name="MaxScannerdefine"></a>
  <b>Define</b>
  <ul>
    <br/> 
    <code>define &lt;name&gt; MaxScanner </code>
    <br/>
  </ul>
  <br>

  <a name="MaxScannerset"></a>
  <b>Set-Commands</b>
  <ul>
	 <code>set &lt;name&gt; run</code>
	 <br/><br/>
	 <ul>
        Runs the scanner loop immediately. (Is usually done by timer) 
    </ul><br/>
  </ul>
   
  <a name="MaxScannerget"></a>
  <b>Get-Commands</b>
  <ul>
	 <code>get &lt;name&gt; associatedDevices</code><br/><br/>
	 <ul>Gets the asscociated devices (thermostats, shutterContacts)</ul><br/>
  </ul>
   
  <a name="MaxScannerattr"></a>
  <b>Attributes for the Scanner-Device</b><br/><br/>
    
  <ul>
     <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
     <li><p><b>disable</b><br/>When value=1, then the scanner device is disabled; possible values: 0,1; default: 0</p></li>
	<li><p><b>scnCreditThreshold</b><br/>the minimum value of available credits; when lower, the scanner will remain inactive; possible values: 150..600; default: 300</p></li>
	<li><p><b>scnMinInterval</b><br/>scan interval in minutes, when the calculated interval is lower, 
	    then scnMinintervall will be used instead;possible values: 3..60; default: 3</p></li>
  </ul>
  <br/>
  
  <a name="MaxScannerthermoattr"></a>
  <b>User-Attributes for the Thermostat-Device</b><br/>
  <ul>
     <li><p><b>scanTemp</b><br/>When value=1, then scanner will use the thermostat; possible values: 0,1; default: 0</p></li>
     <li><p><b>scnProcessByDesiChange</b><br/>When value=1, then scanner will use method "desired change" instead of "mode change"; possible values: 0,1; default: 0</p></li>
     <li><p><b>scnModeHandling</b><br/>When scnProcessByDesiChange is active, this attribute select the way of handling the mode of the thermostat; possible values: [NOCHANGE,AUTO,MANUAL];default: AUTO</p></li>
     <li><p><b>scnShutterList</b><br/>comma-separated list of shutterContacts associated with the thermostat</p></li>
  </ul>
  <br/>
   
  <b>Additional information</b><br/><br/>
  <ul>
	<li><a href="http://forum.fhem.de/index.php/topic,11624.0.html">Discussion in FHEM forum</a></li><br/>
	<li><a href="http://www.fhemwiki.de/wiki/MAX!_Temperatur-Scanner">WIKI information in FHEM Wiki</a></li><br/>
  </ul>
</ul>


=end html
=cut
