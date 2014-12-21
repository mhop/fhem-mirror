# $Id: 98_HourCounter.pm 7281 2014-12-21 12:00:00Z john $
####################################################################################################
#
#   98_HourCounter.pm
#   The HourCounter accumulates single events to a counter object.
#   In the case of binary weighted events pulse- and pause-time are determined
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
#  16.11.13 - 0.99.b
#      Loglevel adjusted
#  02.12.13 - 0.99.c
#      $readingFnAttributes added
#  03.12.13 - 0.99.d
#      missed attribute event-on-change-reading
#  02.02.14 - 1.00
#      command queues
#  04.02.14 - 1.01
#      queue removed
#  17.03.14 - 1.02
#      adjusting log-levels, forceYearChange,HourCounter_RoundYear
#  07.06.14 - 1.03
#      $ID changed
#      setter for pulseTimeIncrement, pauseTimeIncrement
#  25.10.14 - 1.0.0.4
#      official part of fhem
#      adjusting log-output
#      update documentation
#  14.11.14 - 1.0.0.5
#      minor fixes for logging in HourCounter_Set: thanks kubuntufan
#      reformating
#  17.11.14 - 1.0.0.6
#     cyclic calculation of pulse/pause-duration
#     correctly restores counter values after restart
#  10.12.14 - 1.0.1.0
#     new readings pulseTimeEdge, pauseTimeEdge hold the last pusle*-Increment value
#     all operative readings beside the tick*-readings are updated every cycle now
#     new reading tickChanged is fired, if the value is changed
#     new reading tickUpdated is fired each time the operative readings are updated
#     some bug fixes concerning duration and calc calculations
#     note, that also 99_UtilsHourCounter needs changes
#  21.12.14 - 1.0.1.1
#     bug: if OFF is not defined, nothing was counted
#     html : check with tidy
####################################################################################################

package main;
use strict;
use warnings;
use vars qw(%defs);
use vars qw($readingFnAttributes);
use vars qw(%attr);
use vars qw(%modules);
my $HourCounter_Version = "1.0.1.1 - 21.12.2014";

my @HourCounter_cmdQeue = ();

my $DEBUG = 1;

##########################
sub HourCounter_Log($$$)
{
  my ( $hash, $loglevel, $text ) = @_;
  my $xline       = ( caller(0) )[2];
  my $xsubroutine = ( caller(1) )[3];
  my $sub         = ( split( ':', $xsubroutine ) )[2];
  $sub =~ s/HourCounter_//;
  my $instName = ( ref($hash) eq "HASH" ) ? $hash->{NAME} : "HourCounter";
  Log3 $hash, $loglevel, "HourCounter $instName $sub.$xline " . $text;
}
##########################
sub HourCounter_AddLog($$$)
{
  my ( $logdevice, $readingName, $value ) = @_;
  my $cmd = '';
  if ( $readingName =~ m,state,i )
  {
    $cmd = "trigger $logdevice $value   << addLog";
  } else
  {
    $cmd = "trigger $logdevice $readingName: $value   << addLog";
  }
  HourCounter_Log '', 3, $cmd;
  fhem($cmd);
}
##########################
# execute the content of the given parameter
sub HourCounter_Exec($)
{
  my $doit = shift;
  my $ret  = '';
  eval $doit;
  $ret = $@ if ($@);
  return $ret;
}
##########################
# add command to queue
sub HourCounter_cmdQueueAdd($$)
{
  my ( $hash, $cmd ) = @_;
  push( @{ $hash->{helper}{cmdQueue} }, $cmd );
}
##########################
# execute command queue
sub HourCounter_ExecQueue($)
{
  my ($hash) = @_;
  my $result;
  my $cnt    = $#{ $hash->{helper}{cmdQueue} };
  my $loops  = 0;
  my $cntAll = 0;
  HourCounter_Log $hash, 4, "cnt: $cnt";
  while ( $cnt >= 0 )
  {

    for my $i ( 0 .. $cnt )
    {
      my $cmd = ${ $hash->{helper}{cmdQueue} }[$i];
      ${ $hash->{helper}{cmdQueue} }[$i] = '';
      $result = HourCounter_Exec($cmd);
      if ($result)
      {
        HourCounter_Log $hash, 2, "$result";
      } else
      {
        HourCounter_Log $hash, 4, "exec ok:$cmd";
      }
      $cntAll++;
    }

    # bearbeitete eintraege loeschen
    for ( my $i = $cnt ; $i > -1 ; $i-- )
    {
      splice( @{ $hash->{helper}{cmdQueue} }, $i, 1 );
    }
    $cnt = $#HourCounter_cmdQeue;
    $loops++;
    if ( $loops >= 5 || $cntAll > 100 )
    {
      HourCounter_Log $hash, 2, "!!! too deep recursion";
      last;
    }
  }
}
##########################
# round off the date passed to the hour
sub HourCounter_RoundHour($)
{
  my ( $sec, $min, $hour, $mday, $mon, $year ) = localtime(shift);
  return mktime( 0, 0, $hour, $mday, $mon, $year );
}
##########################
# round off the date passed to the day
sub HourCounter_RoundDay($)
{
  my ( $sec, $min, $hour, $mday, $mon, $year ) = localtime(shift);
  return mktime( 0, 0, 0, $mday, $mon, $year );
}
##########################
# round off the date passed to the week
sub HourCounter_RoundWeek($)
{
  my ($time) = @_;
  my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime($time);

  # wday 0 Sonntag 1 Montag ...
  $time -= $wday * 86400;
  return HourCounter_RoundDay($time);
}
##########################
# returns the seconds since the start of the day
sub HourCounter_SecondsOfDay()
{
  my $timeToday = gettimeofday();
  return int( $timeToday - HourCounter_RoundDay($timeToday) );
}
##########################
# round off the date passed to the month
sub HourCounter_RoundMonth($)
{
  my ( $sec, $min, $hour, $mday, $mon, $year ) = localtime(shift);
  return mktime( 0, 0, 0, 1, $mon, $year );
}
##########################
# round off the date passed to the year
sub HourCounter_RoundYear($)
{
  my ( $sec, $min, $hour, $mday, $mon, $year ) = localtime(shift);
  return mktime( 0, 0, 0, 1, 1, $year );
}
##########################
sub HourCounter_Initialize($)
{
  my ($hash) = @_;
  $hash->{DefFn}    = "HourCounter_Define";
  $hash->{UndefFn}  = "HourCounter_Undef";
  $hash->{SetFn}    = "HourCounter_Set";
  $hash->{GetFn}    = "HourCounter_Get";
  $hash->{NotifyFn} = "HourCounter_Notify";
  $hash->{AttrFn}   = "HourCounter_Attr";
  $hash->{AttrList} = "disable:0,1 interval:1,2,3,4,5,10,15,20,30,60 " . $readingFnAttributes;
  HourCounter_Log "", 3, "Init Done with Version $HourCounter_Version";
}
##########################
sub HourCounter_Define($$$)
{
  my ( $hash, $def ) = @_;
  my @a = split( "[ \t][ \t]*", $def );
  my $name = $a[0];
  HourCounter_Log $hash, ($DEBUG) ? 0 : 4, "parameters: @a";
  if ( @a < 3 )
  {
    return "wrong syntax: define <name> HourCounter <regexp_for_ON> [<regexp_for_OFF>]";
  }
  my $onRegexp = $a[2];
  my $offRegexp = ( @a == 4 ) ? $a[3] : undef;

  # Checking for misleading regexps
  eval { "Hallo" =~ m/^$onRegexp/ };
  return "Bad regexp_for_ON : $@" if ($@);
  if ($offRegexp)
  {
    eval { "Hallo" =~ m/^$offRegexp/ };
    return "Bad regexp_for_ON : $@" if ($@);
  }
  $hash->{helper}{ON_Regexp}        = $onRegexp;
  $hash->{helper}{OFF_Regexp}       = $offRegexp;
  $hash->{helper}{isFirstRun}       = 1;
  $hash->{helper}{value}            = -1;
  $hash->{helper}{forceHourChange}  = '';
  $hash->{helper}{forceDayChange}   = '';
  $hash->{helper}{forceWeekChange}  = '';
  $hash->{helper}{forceMonthChange} = '';
  $hash->{helper}{forceYearChange}  = '';
  $hash->{helper}{forceClear}       = '';
  $hash->{helper}{calledByEvent}    = '';
  $hash->{helper}{changedTimestamp} = '';
  @{ $hash->{helper}{cmdQueue} } = ();
  $modules{HourCounter}{defptr}{$name} = $hash;
  RemoveInternalTimer($name);

  # wait until alle readings have been restored
  InternalTimer( int( gettimeofday() + 15 ), "HourCounter_Run", $name, 0 );
  return undef;
}
##########################
sub HourCounter_Undef($$)
{
  my ( $hash, $arg ) = @_;
  HourCounter_Log $hash, 3, "Done";
  return undef;
}
###########################
sub HourCounter_Get($@)
{
  my ( $hash, @a ) = @_;
  my $name = $hash->{NAME};
  my $ret  = "Unknown argument $a[1], choose one of version:noArg";
  my $cmd  = lc( $a[1] );
  if ( $cmd eq 'version' )
  {
    $ret = "Version       : $HourCounter_Version\n";
  }
  return $ret;
}
###########################
sub HourCounter_Set($@)
{
  my ( $hash, @a ) = @_;
  my $name  = $hash->{NAME};
  my $reINT = '^([\\+,\\-]?\\d+$)';    # int

  # determine userReadings beginning with app
  my @readingNames = keys( %{ $hash->{READINGS} } );
  my @userReadings = ();
  foreach (@readingNames)
  {
    if ( $_ =~ m/app.*/ )
    {
      push( @userReadings, $_ );
    }
  }
  my $strUserReadings = join( " ", @userReadings ) . " ";

  # standard commands with parameter
  my @cmdPara = (
    "countsOverall",    "countsPerDay",       "pauseTimeIncrement", "pauseTimePerDay",
    "pauseTimeOverall", "pulseTimeIncrement", "pulseTimePerDay",    "pulseTimeOverall"
  );

  # standard commands with no parameter
  my @cmdNoPara =
    ( "clear", "forceHourChange", "forceDayChange", "forceWeekChange", "forceMonthChange", "forceYearChange", "calc" );
  my @allCommands = ( @cmdPara, @cmdNoPara, @userReadings );
  my $strAllCommands =
    join( " ", ( @cmdPara, @userReadings ) ) . " " . join( ":noArg ", @cmdNoPara ) . ":noArg ";

  #HourCounter_Log $hash, 2, "strAllCommands : $strAllCommands";
  # stop:noArg
  my $usage = "Unknown argument $a[1], choose one of " . $strAllCommands;

  # we need at least 2 parameters
  return "Need a parameter for set" if ( @a < 2 );
  my $cmd = $a[1];
  if ( $cmd eq "?" )
  {
    return $usage;
  }
  my $value = $a[2];

  # is command defined ?
  if ( ( grep { /$cmd/ } @allCommands ) <= 0 )
  {
    HourCounter_Log $hash, 2, "cmd:$cmd no match for : @allCommands";
    return return "unknown command : $cmd";
  }

  # need we a parameter ?
  my $hits = scalar grep { /$cmd/ } @cmdNoPara;
  my $needPara = ( $hits > 0 ) ? '' : 1;
  HourCounter_Log $hash, 4, "hits: $hits needPara:$needPara";

  # if parameter needed, it must be an integer
  return "Value must be an integer" if ( $needPara && !( $value =~ m/$reINT/ ) );
  my $info = "command : " . $cmd;
  $info .= " " . $value if ($needPara);
  HourCounter_Log $hash, 4, $info;
  my $doRun = '';
  if ($needPara)
  {
    readingsSingleUpdate( $hash, $cmd, $value, 1 );
  } elsif ( $cmd eq "forceHourChange" )
  {
    $hash->{helper}{forceHourChange} = 1;
    $doRun = 1;
  } elsif ( $cmd eq "forceDayChange" )
  {
    $hash->{helper}{forceDayChange} = 1;
    $doRun = 1;
  } elsif ( $cmd eq "forceWeekChange" )
  {
    $hash->{helper}{forceWeekChange} = 1;
    $doRun = 1;
  } elsif ( $cmd eq "forceMonthChange" )
  {
    $hash->{helper}{forceMonthChange} = 1;
    $doRun = 1;
  } elsif ( $cmd eq "forceYearChange" )
  {
    $hash->{helper}{forceYearChange} = 1;
    $doRun = 1;
  } elsif ( $cmd eq "clear" )
  {
    $hash->{helper}{forceClear} = 1;
    $doRun = 1;
  } elsif ( $cmd eq "calc" )
  {
    $doRun = 1;
  } else
  {
    return "unknown command (2): $cmd";
  }

  # perform run
  if ( $doRun && !$hash->{helper}{isFirstRun} )
  {
    $hash->{helper}{value}         = -1;
    $hash->{helper}{calledByEvent} = 1;
    HourCounter_Run( $hash->{NAME} );
  }
  return;
}
##########################
sub HourCounter_Notify($$)
{
  my ( $hash, $dev ) = @_;
  my $name    = $hash->{NAME};
  my $devName = $dev->{NAME};

  # return if disabled
  if ( AttrVal( $name, 'disable', '0' ) eq '1' )
  {
    return "";
  }
  my $onRegexp  = $hash->{helper}{ON_Regexp};
  my $offRegexp = $hash->{helper}{OFF_Regexp};
  my $max       = int( @{ $dev->{CHANGED} } );
  for ( my $i = 0 ; $i < $max ; $i++ )
  {
    my $s = $dev->{CHANGED}[$i];    # read changed reading
    $s = "" if ( !defined($s) );
    my $isOnReading = ( "$devName:$s" =~ m/^$onRegexp$/ );
    my $isOffReading = ($offRegexp) ? ( "$devName:$s" =~ m/^$offRegexp$/ ) : '';

    # HourCounter_Log $hash, 5, "devName:$devName; CHANGED:$s; isOnReading:$isOnReading; isOffReading:$isOffReading;";
    next if ( !( $isOnReading || ( $isOffReading && $offRegexp ) ) );
    $hash->{helper}{value} = 1 if ($isOnReading);
    $hash->{helper}{value} = 0 if ($isOffReading);
    $hash->{helper}{calledByEvent} = 1;
    if ( !$hash->{helper}{isFirstRun} )
    {
      HourCounter_Run( $hash->{NAME} );
    }
  }
}
##########################
sub HourCounter_Attr($$$$)
{
  my ( $command, $name, $attribute, $value ) = @_;
  my $msg  = undef;
  my $hash = $defs{$name};
  if ( $attribute eq "interval" )
  {
    #HourCounter_Log $hash, 0, "cmd:$command name:$name attribute:$attribute";
    if ( !$hash->{helper}{isFirstRun} )
    {
      HourCounter_Run($name);
    }
  }
  return $msg;
}
##########################
# converts the seconds in the date format
sub HourCounter_Seconds2HMS($)
{
  my ($seconds) = @_;
  my ( $Sekunde, $Minute, $Stunde, $Monatstag, $Monat, $Jahr, $Wochentag, $Jahrestag, $Sommerzeit ) =
    localtime($seconds);
  my $days = int( $seconds / 86400 );
  return sprintf( "%d Tage %02d:%02d:%02d", $days, $Stunde - 1, $Minute, $Sekunde );
}
##########################
# rounds the timestamp do the beginning of the week
sub HourCounter_weekBase($)
{
  my ($time) = @_;
  my $dayDiff = 60 * 60 * 24;
  my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime($time);

  # wday 0 Sonntag 1 Montag ...
  my $a = $time - $wday * $dayDiff;
  my $b = int( $a / $dayDiff );       # auf tage gehen
  my $c = $b * $dayDiff;
  return $c;
}
##########################
# this either called by timer for cyclic update
# or it is called by an event (on/off)
sub HourCounter_Run($)
{
  # print "xxx TAG A\n" ;
  my ($name) = @_;
  my $hash = $defs{$name};

  # must be of type hourcounter
  return if ( !defined( $hash->{TYPE} ) || $hash->{TYPE} ne 'HourCounter' );

  # timestamps for event-log-file-entries, older than current time
  delete( $hash->{CHANGETIME} );

  # flag for called by event
  my $calledByEvent = $hash->{helper}{calledByEvent};

  # reset flag
  $hash->{helper}{calledByEvent} = '';

  # if call was made by timer, than force value to -1
  my $valuePara = ($calledByEvent) ? $hash->{helper}{value} : -1;

  # initialize changedTimestamp, if it does not exist
  $hash->{helper}{changedTimestamp} = ReadingsTimestamp( $name, "value", TimeNow() )
    if ( !$hash->{helper}{changedTimestamp} );

  # serial date for changed timestamp
  my $sdValue      = time_str2num( $hash->{helper}{changedTimestamp} );
  my $sdCurTime    = gettimeofday();
  my $isOffDefined = ( $hash->{helper}{OFF_Regexp} ) ? 1 : '';

  # calc time diff
  my $timeIncrement = int( $sdCurTime - $sdValue );

  # wrong time offset in case of summer/winter time
  $timeIncrement = 0 if ( $timeIncrement < 0 );

  # get the old value
  my $valueOld = ReadingsVal( $name, 'value', 0 );

  # variable for reading update
  my $value = undef;

  my $countsPerDay  = ReadingsVal( $name, "countsPerDay",  0 );
  my $countsOverall = ReadingsVal( $name, "countsOverall", 0 );

  my $pulseTimeIncrement = ReadingsVal( $name, "pulseTimeIncrement", 0 );
  my $pulseTimePerDay    = ReadingsVal( $name, "pulseTimePerDay",    0 );
  my $pulseTimeOverall   = ReadingsVal( $name, "pulseTimeOverall",   0 );
  my $pulseTimeEdge      = ReadingsVal( $name, "pulseTimeEdge",      0 );

  my $pauseTimeIncrement = ReadingsVal( $name, "pauseTimeIncrement", 0 );
  my $pauseTimePerDay    = ReadingsVal( $name, "pauseTimePerDay",    0 );
  my $pauseTimeOverall   = ReadingsVal( $name, "pauseTimeOverall",   0 );
  my $pauseTimeEdge      = ReadingsVal( $name, "pauseTimeEdge",      0 );

  my $tickUpdated = ReadingsVal( $name, "tickUpdated", 0 ) + 1;
  $tickUpdated = 1 if ( $tickUpdated >= 1000 );

  my $tickChanged = ReadingsVal( $name, "tickChanged", 0 );
  my $tickHour    = ReadingsVal( $name, "tickHour",    0 );
  my $tickDay     = ReadingsVal( $name, "tickDay",     0 );
  my $tickWeek    = ReadingsVal( $name, "tickWeek",    0 );
  my $tickMonth   = ReadingsVal( $name, "tickMonth",   0 );
  my $tickYear    = ReadingsVal( $name, "tickYear",    0 );

  my $state = '';

  my $sdTickHour = time_str2num( ReadingsTimestamp( $name, "tickHour", TimeNow() ) );

  # serial date for current hour
  my $sdRoundHour = HourCounter_RoundHour($sdCurTime);

  my $sdRoundHourLast = HourCounter_RoundHour($sdTickHour);
  $sdRoundHourLast = $sdRoundHour if ( !$sdRoundHourLast );
  my $isHourChanged = ( $sdRoundHour != $sdRoundHourLast ) || $hash->{helper}{forceHourChange};

  # serial date for current day
  my $sdRoundDayCurTime = HourCounter_RoundDay($sdCurTime);
  my $sdRoundDayValue   = HourCounter_RoundDay($sdRoundHourLast);
  my $isDayChanged      = ( $sdRoundDayCurTime != $sdRoundDayValue ) || $hash->{helper}{forceDayChange};

  # serial date for current week
  my $sdRoundWeekCurTime = HourCounter_RoundWeek($sdCurTime);
  my $sdRoundWeekValue   = HourCounter_RoundWeek($sdRoundHourLast);
  my $isWeekChanged =
    ( $sdRoundWeekCurTime != $sdRoundWeekValue ) || $hash->{helper}{forceWeekChange};

  # serial date for current month
  my $sdRoundMonthCurTime = HourCounter_RoundMonth($sdCurTime);
  my $sdRoundMonthValue   = HourCounter_RoundMonth($sdRoundHourLast);
  my $isMonthChanged =
    ( $sdRoundMonthCurTime != $sdRoundMonthValue ) || $hash->{helper}{forceMonthChange};

  # serial date for current year
  my $sdRoundYearCurTime = HourCounter_RoundYear($sdCurTime);
  my $sdRoundYearValue   = HourCounter_RoundYear($sdRoundHourLast);
  my $isYearChanged =
    ( $sdRoundYearCurTime != $sdRoundYearValue ) || $hash->{helper}{forceYearChange};

  # loop forever
  while (1)
  {
    # stop if disabled
    last if ( AttrVal( $name, 'disable', '0' ) eq '1' );

    # variables for controlling
    HourCounter_Log $hash, 5, "value:$valuePara changedTimestamp:" . $hash->{helper}{changedTimestamp};

    # ------------ basic init, when first run
    if ( $hash->{helper}{isFirstRun} )
    {
      $hash->{helper}{isFirstRun}      = undef;
      $hash->{helper}{sdRoundHourLast} = $sdRoundHourLast;

      # first init after startup
      readingsBeginUpdate($hash);
      readingsBulkUpdate( $hash, 'tickHour',  0 );
      readingsBulkUpdate( $hash, 'tickDay',   0 );
      readingsBulkUpdate( $hash, 'tickWeek',  0 );
      readingsBulkUpdate( $hash, 'tickMonth', 0 );
      readingsBulkUpdate( $hash, 'tickYear',  0 );
      readingsEndUpdate( $hash, 0 );

      # set initial values
      $value         = $valueOld;    # value als reading anlegen falls nicht vorhanden
      $timeIncrement = 0;

      HourCounter_Log $hash, 0, "first run done countsOverall:" . $countsOverall;    #4
    }

    # -------- force clear request
    if ( $hash->{helper}{forceClear} )
    {
      HourCounter_Log $hash, 0, "force clear request";
      readingsSingleUpdate( $hash, 'clearDate', TimeNow(), 1 );

      # reset all counters
      $countsOverall = 0;
      $countsPerDay  = 0;

      $pauseTimeIncrement = 0;
      $pauseTimeEdge      = 0;

      $pauseTimeOverall = 0;
      $pauseTimePerDay  = 0;

      $pulseTimeIncrement = 0;
      $pulseTimeEdge      = 0;

      $pulseTimeOverall = 0;
      $pulseTimePerDay  = 0;

      $hash->{helper}{forceClear} = '';
      $timeIncrement = 0;
    }

    # -------------- handling of transitions
    my $hasValueChanged = 0;
    if ( ( $isOffDefined && $valuePara >= 0 && $valuePara != $valueOld )
      || ( !$isOffDefined && $calledByEvent ) )
    {
      $hasValueChanged = 1;
    }

    # -------------- positive edge
    if ( $hasValueChanged && $valuePara == 1 )
    {
      $value    = $valuePara;
      $valueOld = $valuePara;

      # handling of counters
      $countsPerDay  += 1;
      $countsOverall += 1;

      #..  handling of pause
      if ($isOffDefined)
      {
        $pauseTimeIncrement += $timeIncrement;
        $pauseTimePerDay    += $timeIncrement;
        $pauseTimeOverall   += $timeIncrement;
        $pulseTimeIncrement = 0;
        $pauseTimeEdge      = $pauseTimeIncrement;
      }
      HourCounter_Log $hash, 4, "rising edge; pauseTimeIncr:$pauseTimeIncrement countPerDay:$countsPerDay";
    }

    # ------------ negative edge
    elsif ( $hasValueChanged && $valuePara == 0 )
    {
      $value    = $valuePara;
      $valueOld = $valuePara;

      # handling of pulse time
      $pulseTimeIncrement += $timeIncrement;
      $pulseTimePerDay    += $timeIncrement;
      $pulseTimeOverall   += $timeIncrement;
      $pulseTimeEdge      = $pulseTimeIncrement;
      $pauseTimeIncrement = 0;
      HourCounter_Log $hash, 4, "falling edge pulseTimeIncrement:$pulseTimeIncrement";
    }

    # --------------- no change
    elsif ( $valuePara == -1 && $isOffDefined )
    {
      if ( $valueOld == 0 )
      {
        $pauseTimeIncrement += $timeIncrement;
        $pauseTimePerDay    += $timeIncrement;
        $pauseTimeOverall   += $timeIncrement;
      } elsif ( $valueOld == 1 )
      {
        $pulseTimeIncrement += $timeIncrement;
        $pulseTimePerDay    += $timeIncrement;
        $pulseTimeOverall   += $timeIncrement;
      }
    }

    $hash->{helper}{changedTimestamp} = TimeNow();

    $value = $valueOld;

    $state = $countsPerDay;

    # ---------update readings, if vars defined
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "countsPerDay",  $countsPerDay );
    readingsBulkUpdate( $hash, "countsOverall", $countsOverall );
    if ($isOffDefined)
    {
      readingsBulkUpdate( $hash, "pulseTimeIncrement", $pulseTimeIncrement );
      readingsBulkUpdate( $hash, "pulseTimeEdge",      $pulseTimeEdge );

      readingsBulkUpdate( $hash, "pulseTimePerDay",  $pulseTimePerDay );
      readingsBulkUpdate( $hash, "pulseTimeOverall", $pulseTimeOverall );

      readingsBulkUpdate( $hash, "pauseTimeIncrement", $pauseTimeIncrement );
      readingsBulkUpdate( $hash, "pauseTimeEdge",      $pauseTimeEdge );

      readingsBulkUpdate( $hash, "pauseTimePerDay",  $pauseTimePerDay );
      readingsBulkUpdate( $hash, "pauseTimeOverall", $pauseTimeOverall );
    }
    readingsBulkUpdate( $hash, "value",       $value );
    readingsBulkUpdate( $hash, 'state',       $state );
    readingsBulkUpdate( $hash, 'tickUpdated', $tickUpdated );
    readingsEndUpdate( $hash, 1 );

    # --------------- fire time interval ticks for hour,day,month

    if ($hasValueChanged)
    {
      $tickChanged++;
      $tickChanged = 1 if ( $tickChanged >= 1000 );
      readingsSingleUpdate( $hash, 'tickChanged', $tickChanged, 1 );
      HourCounter_Log $hash, 4, 'tickChanged fired ';
    }
    if ($isHourChanged)
    {
      $tickHour++;
      $tickHour = 1 if ( $tickHour >= 1000 );
      $hash->{helper}{forceHourChange} = '';
      $hash->{helper}{sdRoundHourLast} = $sdRoundHour;
      readingsSingleUpdate( $hash, 'tickHour', $tickHour, 1 );
      HourCounter_Log $hash, 4, "tickHour fired";
    }
    if ($isDayChanged)
    {
      $tickDay++;
      $tickDay = 1 if ( $tickDay >= 1000 );
      $hash->{helper}{forceDayChange} = '';
      readingsSingleUpdate( $hash, 'tickDay', $tickDay, 1 );
      HourCounter_Log $hash, 4, "tickDay fired";
    }
    if ($isWeekChanged)
    {
      $tickWeek++;
      $tickWeek = 1 if ( $tickWeek >= 1000 );
      $hash->{helper}{forceWeekChange} = '';
      readingsSingleUpdate( $hash, 'tickWeek', $tickWeek, 1 );
      HourCounter_Log $hash, 4, "tickWeek fired";
    }
    if ($isMonthChanged)
    {
      $tickMonth++;
      $tickMonth = 1 if ( $tickMonth >= 1000 );
      $hash->{helper}{forceMonthChange} = '';
      readingsSingleUpdate( $hash, 'tickMonth', $tickMonth, 1 );
      HourCounter_Log $hash, 4, "tickMonth fired";
    }
    if ($isYearChanged)
    {
      $tickYear++;
      $tickYear = 1 if ( $tickYear >= 1000 );
      $hash->{helper}{forceYearChange} = '';
      readingsSingleUpdate( $hash, 'tickYear', $tickYear, 1 );
      HourCounter_Log $hash, 4, "tickYear fired";
    }

    # execute command queue
    HourCounter_ExecQueue($hash);

    # day change, so reset day readings
    if ($isDayChanged)
    {
      ### reset all day counters
      readingsBeginUpdate($hash);
      readingsBulkUpdate( $hash, "countsPerDay",    0 );
      readingsBulkUpdate( $hash, "pulseTimePerDay", 0 );
      readingsBulkUpdate( $hash, "pauseTimePerDay", 0 );
      readingsEndUpdate( $hash, 1 );
      HourCounter_Log $hash, 4, "reset day counters";
    }
    last;
  }

  # ------------ calculate seconds until next hour starts
  my $interval = AttrVal( $name, 'interval', '60' );
  my $actTime = int( gettimeofday() );
  my ( $sec, $min, $hour ) = localtime($actTime);

  # round to next interval
  my $seconds = $interval * 60;
  my $nextHourTime = int( ( $actTime + $seconds ) / $seconds ) * $seconds;

  # calc diff in seconds
  my $nextCall = $nextHourTime - $actTime;
  HourCounter_Log $hash, 5, "nextCall:$nextCall changedTimestamp:" . $hash->{helper}{changedTimestamp};
  RemoveInternalTimer($name);
  InternalTimer( gettimeofday() + $nextCall, "HourCounter_Run", $hash->{NAME}, 0 );
  return undef;
}
1;

=pod
=begin html

  <div id="includedContent">
    <a name="HourCounter" id="HourCounter"></a>

    <h3>HourCounter</h3>

    <div style="margin-left: 2em">
      <a name="HourCounterdefine" id="HourCounterdefine"></a> <b>Define</b>

      <div style="margin-left: 2em">
        <br />
        <code>define &lt;name&gt; HourCounter &lt;pattern_for_ON&gt; [&lt;pattern_for_OFF&gt;]</code><br />
        <br />
        Hourcounter can detect both the activiy-time and the inactivity-time of a property.<br />
        The "pattern_for_ON" identifies the events, that signal the activity of the desired property.<br />
        The "pattern_for_OFF" identifies the events, that signal the inactivity of the desired property.<br />
        <br />
        If "pattern_for_OFF" is not defined, any matching event of "patter_for_ON" will be counted.<br />
        Otherwise only the rising edges of "pattern_for_ON" will be counted.<br />
        This means a "pattern_for_OFF"-event must be detected before a "pattern_for_ON"-event is accepted.<br />
        <br />
        "pattern_for_ON" and "pattern_for_OFF" must be formed using the following structure:<br />
        <br />
        <code>device:[regexp]</code><br />
        <br />
        The forming-rules are the same as for the notify-command.<br />
        <br />
        <b>Example:</b><br />
        <br />

        <div style="margin-left: 2em">
          <code>define BurnerCounter HourCounter SHUTTER_TEST:on SHUTTER_TEST:off</code>
        </div>
      </div><br />
      <a name="HourCounterset" id="HourCounterset"></a> <b>Set-Commands</b>

      <div style="margin-left: 2em">
        <br />
        <code>set &lt;name&gt; calc</code><br />
        <br />

        <div style="margin-left: 2em">
          starts the calculation of pulse/pause-time.<br />
        </div><br />
        <br />
        <code>set &lt;name&gt; clear</code><br />
        <br />

        <div style="margin-left: 2em">
          clears the readings countsPerDay, countsOverall,pauseTimeIncrement, pauseTimePerDay, pauseTimeOverall,
          pulseTimeIncrement, pulseTimePerDay, pulseTimeOverall by setting to 0.<br />
          The reading clearDate is set to the current Date/Time.
        </div><br />
        <br />
        <code>set &lt;name&gt; countsOverall &lt;value&gt;</code><br />
        <br />

        <div style="margin-left: 2em">
          Sets the reading countsOverall to the given value.This is the total-counter.
        </div><br />
        <br />
        <code>set &lt;name&gt; countsPerDay &lt;value&gt;</code><br />
        <br />

        <div style="margin-left: 2em">
          Sets the reading countsPerDay to the given value. This reading will automatically be set to 0, after change
          of day.
        </div><br />
        <br />
        <code>set &lt;name&gt; pauseTimeIncrement &lt;value&gt;</code><br />
        <br />

        <div style="margin-left: 2em">
          Sets the reading pauseTimeIncrement to the given value.<br />
          This reading in seconds is automatically set after a rising edge.
        </div><br />
        <br />
        <code>set &lt;name&gt; pauseTimeEdge &lt;value&gt;</code><br />
        <br />

        <div style="margin-left: 2em">
          Sets the reading pauseTimeEdge to the given value.<br />
          This reading in seconds is automatically set after a rising edge.
        </div><br />
        <br />
        <code>set &lt;name&gt; pauseTimeOverall &lt;value&gt;</code><br />
        <br />

        <div style="margin-left: 2em">
          Sets the reading pauseTimeOverall to the given value.<br />
          This reading in seconds is automatically adjusted after a change of pauseTimeIncrement.
        </div><br />
        <br />
        <code>set &lt;name&gt; pauseTimePerDay &lt;value&gt;</code><br />
        <br />

        <div style="margin-left: 2em">
          Sets the reading pauseTimePerDay to the given value.<br />
          This reading in seconds is automatically adjusted after a change of pauseTimeIncrement and set to 0 after
          change of day.
        </div><br />
        <br />
        <code>set &lt;name&gt; pulseTimeIncrement &lt;value&gt;</code><br />
        <br />

        <div style="margin-left: 2em">
          Sets the reading pulseTimeIncrement to the given value.<br />
          This reading in seconds is automatically set after a falling edge of the property.
        </div><br />
        <br />
        <code>set &lt;name&gt; pulseTimeEdge &lt;value&gt;</code><br />
        <br />

        <div style="margin-left: 2em">
          Sets the reading pulseTimeEdge to the given value.<br />
          This reading in seconds is automatically set after a rising edge.
        </div><br />
        <br />
        <code>set &lt;name&gt; pulseTimeOverall &lt;value&gt;</code><br />
        <br />

        <div style="margin-left: 2em">
          Sets the reading pulseTimeOverall to the given value.<br />
          This reading in seconds is automatically adjusted after a change of pulseTimeIncrement.
        </div><br />
        <br />
        <code>set &lt;name&gt; pulseTimePerDay &lt;value&gt;</code><br />
        <br />

        <div style="margin-left: 2em">
          Sets the reading pulseTimePerDay to the given value.<br />
          This reading in seconds is automatically adjusted after a change of pulseTimeIncrement and set to 0 after
          change of day.
        </div><br />
        <br />
        <code>set &lt;name&gt; forceHourChange</code><br />
        <br />

        <div style="margin-left: 2em">
          This modifies the reading tickHour, which is automatically modified after change of hour.
        </div><br />
        <br />
        <code>set &lt;name&gt; forceDayChange</code><br />
        <br />

        <div style="margin-left: 2em">
          This modifies the reading tickDay, which is automatically modified after change of day.
        </div><br />
        <br />
        <code>set &lt;name&gt; forceWeekChange</code><br />
        <br />

        <div style="margin-left: 2em">
          This modifies the reading tickWeek, which is automatically modified after change of week.
        </div><br />
        <br />
        <code>set &lt;name&gt; forceMonthChange</code><br />
        <br />

        <div style="margin-left: 2em">
          This modifies the reading tickMonth, which is automatically modified after change of month.
        </div><br />
        <br />
        <code>set &lt;name&gt; forceYearChange</code><br />
        <br />

        <div style="margin-left: 2em">
          This modifies the reading tickYear, which is automatically modified after change of year.
        </div><br />
        <br />
        <code>set &lt;name&gt; app.* &lt;value&gt;</code><br />
        <br />

        <div style="margin-left: 2em">
          Any reading with the leading term "app", can be modified.<br />
          This can be useful for user-readings.
        </div><br />
      </div><br />
      <a name="HourCounterget" id="HourCounterget"></a> <b>Get-Commands</b><br />

      <div style="margin-left: 2em">
        <br />
        <code>get &lt;name&gt; version</code><br />
        <br />

        <div style="margin-left: 2em">
          Get the current version of the module.
        </div><br />
      </div><br />
      <a name="HourCounterattr" id="HourCounterattr"></a> <b>Attributes</b>
      <br />

      <ul>
        <li><p><b>interval</b><br />
        the update interval for pulse/pause-time in minutes [default 60]</p></li>

        <li><p><a href="#readingFnAttributes">readingFnAttributes</a></p></li>
      </ul>
      <b>Additional information</b>
      <br />

      <ul>
        <li><p><a href="http://forum.fhem.de/index.php/topic,12216.0.html">Discussion in FHEM forum</a></p></li>
        <li><p><a href="http://www.fhemwiki.de/wiki/HourCounter">WIKI information in FHEM Wiki</a></p></li>
        <li><p>The file 99_UtilsHourCounter.pm is a reference implementation for user defined extensions.<br />
        It shows how to create sum values for hours,days, weeks, months and years.<br />
        This file is located in the sub-folder contrib. For further information take a look to FHEM Wiki.</p></li>
      </ul>
    </div>
  </div>

=end html
=cut
