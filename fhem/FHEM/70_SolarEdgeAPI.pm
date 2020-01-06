###############################################################################
#
# $Id$
#
# By (c) 2019 FHEM user 'pizmus' (pizmus at web de)
#
# Based on 70_SolarEdgeAPI.pm from https://github.com/felixmartens/fhem by
# (c) 2018 Felix Martens (felix at martensmail dot de)
#
# Based on 46_TeslaPowerwall2AC by
# (c) 2017 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
#
# All rights reserved
#
# This script is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# any later version.
#
# The GNU General Public License can be found at
# http://www.gnu.org/copyleft/gpl.html.
# A copy is found in the textfile GPL.txt and important notices to the license
# from the author is found in LICENSE.txt distributed with these scripts.
#
# This script is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
###############################################################################

package main;

use strict;
use warnings;
use HttpUtils;

###############################################################################
#
# Note: Always call the JSON module via "eval":
#
# $data = eval{decode_json($data)};
# if($@){
#   Log3($SELF, 2, "$TYPE ($SELF) - error while request: $@");
#   readingsSingleUpdate($hash, "state", "error", 1);
#   return;
# }
#
###############################################################################

my $solarEdgeAPI_missingModul = "";
eval "use JSON;1" or $solarEdgeAPI_missingModul .= "JSON ";

###############################################################################
#
# versioning scheme: <majorVersion>.<minorVersion>.<patchVersion>[betaXYZ]
#
# The <majorVersion> is incremented for changes which are not backward compatible.
# A change of the <majorVersion> may require adaptations on the user side, for
# some or all users, e.g. because a reading is removed or has a new meaning.
#
# The <minorVersion> is incremented for changes which are backward compatible,
# e.g. added functionality which does not impact old functionality.
#
# The <patchVersion> is incremented for small bug fixes, changes of source code
# comments or documentation.
#
# A string starting with "beta" is attached for release candidates which are
# distributed for testing. If no issues are found in a beta version, the "beta"
# string is removed and the source file is submitted.
#
###############################################################################
#
# 1.0.0     initial version as copied from https://github.com/felixmartens/fhem
#           with minimal changes to be able to submit it to FHEM SVN
#
# 1.1.0beta Detect that site does not support the "currentPowerFlow" API.
#           Read "overview" API to get the current power.
#           Added attributes enableStatusReadings, enableAggregatesReadings,
#           and enableOverviewReadings.
#           Note: This version was released by accident with "beta" in the
#           version string.
#
# 1.1.1     source code formatting
#           added TODOs in the source code
#
# 1.2.0     added internals that count requests, successful responses and error
#             responses
#           added "set restartTimer" and "set resetDebugCounters"
#           added attributes:
#             intervalAtNightTime
#             dayTimeStartHour
#             nightTimeStartHour
#             enableDebugReadings
#           added internal NUMBER_OF_REQUESTS_PER_DAY that shows the
#             theoretical number of http requests per day, based on current
#             attribute settings
#           Parameter "interval" of the "define" function is now optional. If
#             it is not provided the default value "auto" is used.
#           If the new attributes are not set by the user, the default values
#             are chosen so that behavior is same as in previous versions.
#           Restart periodic timer during _Define instead of _Notify.
#
# 1.3.0     show SolarEdge logo to comply with requirement from API documentation
#
# 1.4.0     new reading groups: dailyAggregates, storage, dailyStorage,
#           dailyDetails, dailyOverview
#
# 2.0.0     changes which are not backward compatible:
#           - "define" does not assign attribute room="Photovoltaik" anymore
#             reason: different users organize rooms differently, it is not the business of the FHEM module
#             impact: attribute room has to be assigned by user for new devices
#           - remove parameter "interval" of "define" function
#             reason: The interval and other related settings are configured via attributes.
#             Attributes are easy to change while the device is alive. Making the same setting
#             via define is redundant and increases complexity.
#             impact: existing devices will fail after update/restart if the optional parameter
#             was used. The device definition has to be changed by removing the last parameter.
#           - rename attribute "interval" to "intervalAtDayTime"
#             reason: make names consistent (intervalAtDayTime/intervalAtNightTime)
#             impact: All users who have specified attribute "interval" must change it to "intervalAtDayTime".
#           - default values of attributes:
#             "enableStatusReadings" -> change from 1 to 0
#             "enableAggregatesReadings" -> change from 1 to 0
#             "enableOverviewReadings" -> change from 0 to 1
#             "enableDailyDetailsReadings" -> change from 0 to 1
#             "enableDailyOverviewReadings" -> change from 0 to 1
#             "dayTimeStartHour" -> change from 7 to 6
#             "intervalAtDayTime" -> change from 300 to 215
#             reason: provide a simple default configuration that works as a good starting point for new users
#             impact: Users that have started with older versions, and who rely on default values, have to set attributes.
#           - do not show number of queue entries in readings "state" and "actionQueue".
#             example of state value (old behavior): "fetch data - 2 entries in the Queue"
#             reason: not a good value of "state" to trigger on
#             impact: Most likely none.
#           - Do not show http errors in readings "state" and "lastRequestError", write error message to log file instead.
#             reason: not a good value of "state" to trigger on. Information should be in the log file. 
#             impact: Most likely none. From now on look at log file for error messages.
#           - Do not show JSON errors in readings "JSON Error" and "state", write error message to log file instead.
#             reason: not a good value of "state" to trigger on. Information should be in the log file. 
#             impact: Most likely none. From now on look at log file for error messages.
#           - Do not report "aggregates response is not a Hash" via reading "error".
#             Do not report "API currentPowerFlow is not supported by site." via reading "error".
#             reason: Information should be in the log file.
#             impact: Most likely none.
#           - Do not assign text messages to *_status readings of "status" readings group. 
#             Use "-" instead if no data is available.
#             reason: Simplify automatic processing of readings.
#             impact: User needs to change e.g. "notify" definitions, if any. 
#           - Set the internal "STATE" and the reading "state" to:
#               - "error" if the last http request has shown an error condition
#               - "disabled" if the device is disabled
#               - "active" otherwise
#
# 2.0.1     tolerate empty field in energyDetails response
#
###############################################################################

sub SolarEdgeAPI_SetVersion($)
{
  my ($hash) = @_;
  $hash->{VERSION} = "2.0.1";
}

###############################################################################
# module interface functions
###############################################################################

sub SolarEdgeAPI_Initialize($)
{
  my ($hash) = @_;

  $hash->{GetFn}      = "SolarEdgeAPI_Get";
  $hash->{SetFn}      = "SolarEdgeAPI_Set";
  $hash->{DefFn}      = "SolarEdgeAPI_Define";
  $hash->{UndefFn}    = "SolarEdgeAPI_Undef";
  $hash->{AttrFn}     = "SolarEdgeAPI_Attr";
  $hash->{AttrList}   = "intervalAtDayTime ".
                        "intervalAtNightTime ".
                        "dayTimeStartHour ".
                        "nightTimeStartHour ".
                        "disable:1 ".
                        "enableStatusReadings:1,0 ".
                        "enableAggregatesReadings:1,0 ".
                        "enableOverviewReadings:1,0 ".
                        "enableStorageReadings:1,0 ".
                        "enableDailyDetailsReadings:1,0 ".
                        "enableDailyStorageReadings:1,0 ".
                        "enableDailyAggregatesReadings:1,0 ".
                        "enableDailyOverviewReadings:1,0 ".
                        "enableDebugReadings:1,0 ".
                        $readingFnAttributes;

  $hash->{FW_detailFn} = "SolarEdgeAPI_fhemwebFn";
}

sub SolarEdgeAPI_Define($$)
{
  my ($hash, $def) = @_;

  my @a = split( "[ \t][ \t]*", $def );

  if (int(@a) != 4)
  {
    return "incorrect number of parameters: define <name> SolarEdgeAPI <API-Key> <Site-ID>";
  }

  if ($solarEdgeAPI_missingModul)
  {
    return "Cannot define a SolarEdgeAPI device. Perl modul $solarEdgeAPI_missingModul is missing.";
  }

  my $name = $a[0];

  $hash->{APIKEY} = $a[2];
  $hash->{SITEID} = $a[3];

  $hash->{DEFAULT_DAY_TIME_INTERVAL} = 215;
  $hash->{DEFAULT_NIGHT_TIME_INTERVAL} = 1200;

  $hash->{DEFAULT_DAY_TIME_START_HOUR} = 6;
  $hash->{DEFAULT_NIGHT_TIME_START_HOUR} = 22;

  $hash->{PORT} = 80;
  $hash->{NOTIFYDEV} = "global";
  $hash->{actionQueue} = [];

  SolarEdgeAPI_ResetDebugCounters($hash);

  SolarEdgeAPI_SetVersion($hash);

  Log3 $name, 3, "SolarEdgeAPI ($name) - defined";

  my %paths = (
    'status' => 'currentPowerFlow.json',
    'aggregates' => 'energyDetails.json',
    'overview' => 'overview.json',
    'storage' => 'storageData.json',
    'dailyDetails' => 'details.json',
    'dailyStorage' => 'storageData.json',
    'dailyOverview' => 'overview.json',
    'dailyAggregates' => 'energyDetails.json'
  );
  $hash->{PATHS} = \%paths;

  # remove any active timer
  RemoveInternalTimer($hash);

  # initiate periodic readings
  InternalTimer(gettimeofday() + 60, 'SolarEdgeAPI_RestartHttpRequestTimers', $hash);

  SolarEdgeAPI_UpdateState($hash, "active");

  return undef;
}

sub SolarEdgeAPI_ResetDebugCounters($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  $hash->{NUMBER_OF_REQUESTS} = 0;
  $hash->{NUMBER_OF_GOOD_RESPONSES} = 0;
  $hash->{NUMBER_OF_ERROR_1} = 0;
  $hash->{NUMBER_OF_ERROR_2} = 0;
  $hash->{NUMBER_OF_ERROR_3} = 0;
  $hash->{NUMBER_OF_JSON_ERRORS} = 0;
  $hash->{NUMBER_OF_REQUESTS_PER_DAY} = 0;

  if (AttrVal($name, "enableDebugReadings", undef))
  {
    readingsSingleUpdate($hash, 'debugNumRequests', $hash->{NUMBER_OF_REQUESTS}, 1);
    readingsSingleUpdate($hash, 'debugNumGoodResponses', $hash->{NUMBER_OF_GOOD_RESPONSES}, 1);
    readingsSingleUpdate($hash, 'debugNumJsonErrors', $hash->{NUMBER_OF_JSON_ERRORS}, 1);
    readingsSingleUpdate($hash, 'debugNumError1', $hash->{NUMBER_OF_ERROR_1}, 1);
    readingsSingleUpdate($hash, 'debugNumError2', $hash->{NUMBER_OF_ERROR_2}, 1);
    readingsSingleUpdate($hash, 'debugNumError3', $hash->{NUMBER_OF_ERROR_3}, 1);
  }
}

sub SolarEdgeAPI_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 3, "SolarEdgeAPI ($name) - deleted";

  # remove any active timer
  RemoveInternalTimer($hash);

  return undef;
}

sub SolarEdgeAPI_Attr(@)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;
  my $hash = $defs{$name};

  if ($attrName eq "disable")
  {
    if ($cmd eq "set")
    {
      if ($attrVal eq "1")
      {
        RemoveInternalTimer($hash);
        SolarEdgeAPI_UpdateState($hash, "disabled");
        Log3 $name, 3, "SolarEdgeAPI ($name) - attribute disable=1";
      }
      elsif ($attrVal eq "0")
      {
        InternalTimer(gettimeofday() + 5, 'SolarEdgeAPI_RestartHttpRequestTimers', $hash);
        SolarEdgeAPI_UpdateState($hash, "active");
        Log3 $name, 3, "SolarEdgeAPI ($name) - attribute disable=0";
      }
      else
      {
        my $message = "unexpected value for attribute disable";
        Log3 $name, 3, "SolarEdgeAPI ($name) - ".$message;
        return $message;
      }
    }
    elsif ($cmd eq "del")
    {
      InternalTimer(gettimeofday() + 5, 'SolarEdgeAPI_RestartHttpRequestTimers', $hash);
      SolarEdgeAPI_UpdateState($hash, "active");
      Log3 $name, 3, "SolarEdgeAPI ($name) - attribute disable deleted";
    }
  }

  if ($attrName eq "disabledForIntervals")
  {
    if ($cmd eq "set")
    {
      return "check disabledForIntervals Syntax HH:MM-HH:MM or 'HH:MM-HH:MM HH:MM-HH:MM ...'"
        unless($attrVal =~ /^((\d{2}:\d{2})-(\d{2}:\d{2})\s?)+$/);
      SolarEdgeAPI_UpdateState($hash, "disabled");
      Log3 $name, 3, "SolarEdgeAPI ($name) - attribute disabledForIntervals set";
    }
    elsif ($cmd eq "del")
    {
      SolarEdgeAPI_UpdateState($hash, "active");
      Log3 $name, 3, "SolarEdgeAPI ($name) - attribute disabledForIntervals deleted";
    }
  }

  if ($attrName eq "intervalAtDayTime")
  {
    if ($cmd eq "set")
    {
      if (($attrVal eq "auto") || ($attrVal >= 120))
      {
        InternalTimer(gettimeofday() + 5, 'SolarEdgeAPI_RestartHttpRequestTimers', $hash);
        Log3 $name, 3, "SolarEdgeAPI ($name) - attribute intervalAtDayTime set to $attrVal";
      }
      else
      {
        my $message = "intervalAtDayTime is out of range";
        Log3 $name, 3, "SolarEdgeAPI ($name) - ".$message;
        return $message;
      }
    }
    elsif ($cmd eq "del")
    {
      InternalTimer(gettimeofday() + 5, 'SolarEdgeAPI_RestartHttpRequestTimers', $hash);
      Log3 $name, 3, "SolarEdgeAPI ($name) - attribute intervalAtDayTime deleted";
    }
  }

  if ($attrName eq "intervalAtNightTime")
  {
    if ($cmd eq "set")
    {
      if (($attrVal < 120) or ($attrVal > 3600))
      {
        my $message = "intervalAtNightTime is out of range";
        Log3 $name, 3, "SolarEdgeAPI ($name) - ".$message;
        return $message;
      }
      else
      {
        InternalTimer(gettimeofday() + 5, 'SolarEdgeAPI_RestartHttpRequestTimers', $hash);
        Log3 $name, 3, "SolarEdgeAPI ($name) - attribute intervalAtNightTime set to $attrVal";
      }
    }
    elsif ($cmd eq "del")
    {
      InternalTimer(gettimeofday() + 5, 'SolarEdgeAPI_RestartHttpRequestTimers', $hash);
      Log3 $name, 3, "SolarEdgeAPI ($name) - attribute intervalAtNightTime deleted";
    }
  }

  if ($attrName eq "dayTimeStartHour")
  {
    if ($cmd eq "set")
    {
      if (($attrVal < 3) or ($attrVal > 10))
      {
        my $message = "dayTimeStartHour is out of range";
        Log3 $name, 3, "SolarEdgeAPI ($name) - ".$message;
        return $message;
      }
      else
      {
        InternalTimer(gettimeofday() + 5, 'SolarEdgeAPI_RestartHttpRequestTimers', $hash);
        Log3 $name, 3, "SolarEdgeAPI ($name) - attribute dayTimeStartHour set to $attrVal";
      }
    }
    elsif ($cmd eq "del")
    {
      InternalTimer(gettimeofday() + 5, 'SolarEdgeAPI_RestartHttpRequestTimers', $hash);
      Log3 $name, 3, "SolarEdgeAPI ($name) - attribute dayTimeStartHour deleted";
    }
  }

  if ($attrName eq "nightTimeStartHour")
  {
    if ($cmd eq "set")
    {
      if (($attrVal < 14) or ($attrVal > 22))
      {
        my $message = "nightTimeStartHour is out of range";
        Log3 $name, 3, "SolarEdgeAPI ($name) - ".$message;
        return $message;
      }
      else
      {
        InternalTimer(gettimeofday() + 5, 'SolarEdgeAPI_RestartHttpRequestTimers', $hash);
        Log3 $name, 3, "SolarEdgeAPI ($name) - attribute nightTimeStartHour set to $attrVal";
      }
    }
    elsif ($cmd eq "del")
    {
      InternalTimer(gettimeofday() + 5, 'SolarEdgeAPI_RestartHttpRequestTimers', $hash);
      Log3 $name, 3, "SolarEdgeAPI ($name) - attribute nightTimeStartHour deleted";
    }
  }

  if (($attrName eq "enableStatusReadings") or
      ($attrName eq "enableAggregatesReadings") or
      ($attrName eq "enableOverviewReadings") or
      ($attrName eq "enableStorageReadings") or
      ($attrName eq "enableDailyDetailsReadings") or
      ($attrName eq "enableDailyStorageReadings") or
      ($attrName eq "enableDailyOverviewReadings") or
      ($attrName eq "enableDailyAggregatesReadings"))
  {
    if($cmd eq "set")
    {
      if (not (($attrVal eq "0") || ($attrVal eq "1")))
      {
        my $message = "illegal value for $attrName";
        Log3 $name, 3, "SolarEdgeAPI ($name) - ".$message;
        return $message;
      }
      else
      {
        InternalTimer(gettimeofday() + 5, 'SolarEdgeAPI_RestartHttpRequestTimers', $hash);
      }
    }
  }

  if ($attrName eq "enableDebugReadings")
  {
    if($cmd eq "set")
    {
      if (not (($attrVal eq "0") || ($attrVal eq "1")))
      {
        my $message = "illegal value for enableDebugReadings";
        Log3 $name, 3, "SolarEdgeAPI ($name) - ".$message;
        return $message;
      }
    }
  }

  return undef;
}

sub SolarEdgeAPI_Set($$)
{
  my ($hash, @parameters) = @_;
  my $name = $parameters[0];
  my $what = $parameters[1];

  if ($what eq "restartTimer")
  {
    Log3 $name, 3, "SolarEdgeAPI ($name) - set restartTimer";
    SolarEdgeAPI_RestartHttpRequestTimers($hash);
  }
  elsif ($what eq "resetDebugCounters")
  {
    Log3 $name, 3, "SolarEdgeAPI ($name) - set resetDebugCounters";
    SolarEdgeAPI_ResetDebugCounters($hash);
  }
  elsif ($what eq "?")
  {
    my $message = "unknown argument $what, choose one of restartTimer:noArg resetDebugCounters:noArg";
    return $message;
  }
  else
  {
    my $message = "unknown argument $what, choose one of restartTimer resetDebugCounters";
    Log3 $name, 1, "SolarEdgeAPI ($name) - ".$message;
    return $message;
  }
  return undef;
}

sub SolarEdgeAPI_Get($@)
{
  my ($hash, $name, $cmd) = @_;

  if (($cmd eq 'status') or ($cmd eq 'aggregates') or ($cmd eq 'overview') or ($cmd eq 'dailyOverview') or
      ($cmd eq 'storage') or ($cmd eq 'dailyDetails') or ($cmd eq 'dailyStorage') or ($cmd eq 'dailyAggregates'))
  {
    Log3 $name, 3, "SolarEdgeAPI ($name) - get command: ".$cmd;

    if ((defined($hash->{actionQueue})) and (scalar(@{$hash->{actionQueue}}) > 0))
    {
      Log3 $name, 3, "SolarEdgeAPI ($name) - get command ".$cmd." ignored because actionQueue is not empty";
      return 'There are still path commands in the action queue';
    }
    unshift( @{$hash->{actionQueue}}, $cmd );
    SolarEdgeAPI_SendHttpRequest($hash);
  }
  elsif ($cmd eq 'numberOfRequests')
  {
    my $daytimeInterval = AttrVal($name, "intervalAtDayTime", $hash->{DEFAULT_DAY_TIME_INTERVAL});
    my $nighttimeInterval = AttrVal($name, "intervalAtNightTime", $hash->{DEFAULT_NIGHT_TIME_INTERVAL});

    my $dayTimeStartHour = AttrVal($name, "dayTimeStartHour", $hash->{DEFAULT_DAY_TIME_START_HOUR});
    my $nightTimeStartHour = AttrVal($name, "nightTimeStartHour", $hash->{DEFAULT_NIGHT_TIME_START_HOUR});
    my $numberOfDaytimeHours = $nightTimeStartHour - $dayTimeStartHour;
    my $numberOfNighttimeHours = 24 - $numberOfDaytimeHours;

    my $numberOfPeriodicHttpRequests = 0;
    if (AttrVal($name, "enableStatusReadings", 0)) { $numberOfPeriodicHttpRequests += 1; }
    if (AttrVal($name, "enableAggregatesReadings", 0)) { $numberOfPeriodicHttpRequests += 1; }
    if (AttrVal($name, "enableOverviewReadings", 1)) { $numberOfPeriodicHttpRequests += 1; }
    if (AttrVal($name, "enableStorageReadings", 0)) { $numberOfPeriodicHttpRequests += 1; }

    $hash->{NUMBER_OF_REQUESTS_PER_DAY} =
       (($numberOfDaytimeHours * 3600 / $daytimeInterval + $numberOfNighttimeHours * 3600 / $nighttimeInterval)
        * $numberOfPeriodicHttpRequests)
        + (AttrVal($name, "enableDailyStorageReadings", 0))
        + (AttrVal($name, "enableDailyOverviewReadings", 1))
        + (AttrVal($name, "enableDailyDetailsReadings", 1))
        + (AttrVal($name, "enableDailyAggregatesReadings", 0));

    return $hash->{NUMBER_OF_REQUESTS_PER_DAY};
  }
  else
  {
    my $list = 'status:noArg aggregates:noArg overview:noArg dailyOverview:noArg storage:noArg dailyDetails:noArg dailyStorage:noArg dailyAggregates:noArg numberOfRequests:noArg';
    return "Unknown argument $cmd, choose one of $list";
  }

  return undef;
}

###############################################################################
# HTTP request generation
###############################################################################

# precondition: There must be at least one entry in actionQueue.
sub SolarEdgeAPI_SendHttpRequest($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $siteid = $hash->{SITEID};
  my $host = "monitoringapi.solaredge.com/site/".$siteid;
  my $apikey = $hash->{APIKEY};
  my $path = pop(@{$hash->{actionQueue}});

  # some API require additional parameters, e.g. the time frame and time
  # resolution to use with the query
  my $params = "";
  if ($path eq "aggregates")
  {
    # request data for the timeframe from midnight until now
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    $params = "&timeUnit=QUARTER_OF_AN_HOUR&startTime=".(1900+$year)."-".(1+$mon)."-".$mday."%2000:00:00&endTime=".(1900+$year)."-".(1+$mon)."-".$mday."%20".$hour.":".$min.":".$sec;
  }
  elsif ($path eq "dailyAggregates")
  {
    # request data for the timeframe from January 1st until today
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    $params = "&timeUnit=DAY&startTime=".(1900+$year)."-1-1"."%20"."00:00:00&endTime=".(1900+$year)."-".(1+$mon)."-".$mday."%20".$hour.":".$min.":".$sec;
  }
  elsif (($path eq "storage") or ($path eq "dailyStorage"))
  {
    # request data for the last 1/2 hour
    my ($sec1,$min1,$hour1,$mday1,$mon1,$year1,$wday1,$yday1,$isdst1) = localtime(time());
    my ($sec2,$min2,$hour2,$mday2,$mon2,$year2,$wday2,$yday2,$isdst2) = localtime(time() - (30 * 60));
    $params = "&startTime=".(1900+$year2)."-".(1+$mon2)."-".$mday2."%20".$hour2.":".$min2.":".$sec2.
                "&endTime=".(1900+$year1)."-".(1+$mon1)."-".$mday1."%20".$hour1.":".$min1.":".$sec1;
  }

  my $pathsRef = $hash->{PATHS};
  my %paths = %$pathsRef;

  my $uri = $host . '/' . $paths{$path} . "?api_key=" . $apikey.$params;

  HttpUtils_NonblockingGet(
    {
      url         => "https://".$uri,
      timeout     => 5,
      method      => 'GET',
      hash        => $hash,
      setCmd      => $path,
      doTrigger   => 1,
      callback    => \&SolarEdgeAPI_HandleHttpResponse,
    }
  );

  # update debug counter
  $hash->{NUMBER_OF_REQUESTS} = $hash->{NUMBER_OF_REQUESTS} + 1;
  if (AttrVal($name, "enableDebugReadings", undef))
  {
    readingsSingleUpdate($hash, 'debugNumRequests', $hash->{NUMBER_OF_REQUESTS}, 1);
  }

  Log3 $name, 4, "SolarEdgeAPI ($name) - SolarEdgeAPI_SendHttpRequest path: $path / $paths{$path}";
  Log3 $name, 5, "SolarEdgeAPI ($name) - request: http://$uri";
}

sub SolarEdgeAPI_PeriodicHttpRequestTimerFunction($)
{
  my $hash = shift;
  my $name = $hash->{NAME};

  Log3 $name, 4, "SolarEdgeAPI ($name) - periodic timer expired";

  my $pathsRef = $hash->{PATHS};
  my %paths = %$pathsRef;

  if ((defined($hash->{actionQueue})) and (scalar(@{$hash->{actionQueue}}) < 100))
  {
    if (not IsDisabled($name))
    {
      while (my $obj = each %paths)
      {
        if ((($obj eq "status") and (AttrVal($name, "enableStatusReadings", 0))) or
            (($obj eq "aggregates") and (AttrVal($name, "enableAggregatesReadings", 0))) or
            (($obj eq "overview") and (AttrVal($name, "enableOverviewReadings", 1))) or
            (($obj eq "storage") and (AttrVal($name, "enableStorageReadings", 0))))
        {
          Log3 $name, 4, "SolarEdgeAPI ($name) - adding periodic request to actionQueue: ".$obj;
          unshift( @{$hash->{actionQueue}}, $obj );
        }
      }
      SolarEdgeAPI_SendHttpRequest($hash);
    }
    else
    {
      SolarEdgeAPI_UpdateState($hash, "disabled");
    }
  }

  InternalTimer(SolarEdgeAPI_GetTimeOfNextReading($hash), 'SolarEdgeAPI_PeriodicHttpRequestTimerFunction', $hash);
}

sub SolarEdgeAPI_DailyHttpRequestTimerFunction($)
{
  my $hash = shift;
  my $name = $hash->{NAME};

  Log3 $name, 4, "SolarEdgeAPI ($name) - daily timer expired";

  my $pathsRef = $hash->{PATHS};
  my %paths = %$pathsRef;

  if ((defined($hash->{actionQueue})) and (scalar(@{$hash->{actionQueue}}) < 100))
  {
    if (not IsDisabled($name))
    {
      while (my $obj = each %paths)
      {
        if ((($obj eq "dailyDetails") and (AttrVal($name, "enableDailyDetailsReadings", 1))) or
            (($obj eq "dailyStorage") and (AttrVal($name, "enableDailyStorageReadings", 0))) or
            (($obj eq "dailyOverview") and (AttrVal($name, "enableDailyOverviewReadings", 1))) or
            (($obj eq "dailyAggregates") and (AttrVal($name, "enableDailyAggregatesReadings", 0))))
        {
          Log3 $name, 4, "SolarEdgeAPI ($name) - adding daily request to actionQueue: ".$obj;
          unshift( @{$hash->{actionQueue}}, $obj );
        }
      }
      SolarEdgeAPI_SendHttpRequest($hash);
    }
    else
    {
      SolarEdgeAPI_UpdateState($hash, "disabled");
    }
  }

  InternalTimer(SolarEdgeAPI_GetTimeOfNextDailyReading($hash), 'SolarEdgeAPI_DailyHttpRequestTimerFunction', $hash);
}

sub SolarEdgeAPI_RestartHttpRequestTimers($)
{
  my $hash = shift;
  my $name = $hash->{NAME};

  Log3 $name, 3, "SolarEdgeAPI ($name) - restarting timer";

  # remove any active timer
  RemoveInternalTimer($hash);

  # Do the next http request now. This will start a timer for the next one.
  SolarEdgeAPI_PeriodicHttpRequestTimerFunction($hash);

  # Schedule the first daily request now. This will start a timer for the next one.
  InternalTimer(SolarEdgeAPI_GetTimeOfNextDailyReading($hash), 'SolarEdgeAPI_DailyHttpRequestTimerFunction', $hash);
}

sub SolarEdgeAPI_GetTimeOfNextDailyReading($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $epoch = time();
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($epoch);

  if ($hour >= 22)
  {
    # If it is after 10pm the next reading should occur tomorrow.

    # add 24 hours to epoch to get a time during the following day
    $epoch += 24 * 60 * 60;

    # convert again
    ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($epoch);
  }

  # change hour to 10pm and convert to epoch
  $epoch = fhemTimeLocal(5, 0, 22, $mday, $mon, $year); # $sec, $min, $hour, $mday, $month, $year

  return $epoch;
}

sub SolarEdgeAPI_GetTimeOfNextReading($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

  my $dayTimeStartHour = AttrVal($name, "dayTimeStartHour", $hash->{DEFAULT_DAY_TIME_START_HOUR});
  my $nightTimeStartHour = AttrVal($name, "nightTimeStartHour", $hash->{DEFAULT_NIGHT_TIME_START_HOUR});

  my $daytimeInterval = AttrVal($name, "intervalAtDayTime", $hash->{DEFAULT_DAY_TIME_INTERVAL});
  my $nighttimeInterval = AttrVal($name, "intervalAtNightTime", $hash->{DEFAULT_NIGHT_TIME_INTERVAL});

  # select the interval to use now

  my $interval;
  if (($hour >= $dayTimeStartHour) && ($hour < $nightTimeStartHour))
  {
    $interval = $daytimeInterval;
  }
  else
  {
    $interval = $nighttimeInterval;
  }

  # TODO if the next night time interval ends after dayTimeStartHour change interval so
  # that the next request goes out at dayTimeStartHour

  my $newTriggerTime = gettimeofday() + $interval;

  Log3 $name, 4, "SolarEdgeAPI ($name) - next reading in $interval seconds";

  return $newTriggerTime;
}

###############################################################################
# HTTP response handling
###############################################################################

sub SolarEdgeAPI_CheckHttpError($$$$)
{
  my ($hash, $param, $err, $data) = @_;
  my $name = $hash->{NAME};

  if (defined($err) and ($err ne ""))
  {
    # update debug counter
    $hash->{NUMBER_OF_ERROR_1} = $hash->{NUMBER_OF_ERROR_1} + 1;
    if (AttrVal($name, "enableDebugReadings", undef))
    {
      readingsSingleUpdate($hash, 'debugNumError1', $hash->{NUMBER_OF_ERROR_1}, 1);
    }

    Log3 $name, 3, "SolarEdgeAPI ($name) - error (1) in http response: $err";
    SolarEdgeAPI_UpdateState($hash, "error");

    # drop all outstanding requests
    $hash->{actionQueue} = [];

    return 1;
  }

  if (($data eq "") and (exists($param->{code})) and ($param->{code} ne 200))
  {
    # update debug counter
    $hash->{NUMBER_OF_ERROR_2} = $hash->{NUMBER_OF_ERROR_2} + 1;
    if (AttrVal($name, "enableDebugReadings", undef))
    {
      readingsSingleUpdate($hash, 'debugNumError2', $hash->{NUMBER_OF_ERROR_2}, 1);
    }

    Log3 $name, 3, "SolarEdgeAPI ($name) - error (2) in http response, no data, code: ".$param->{code};
    SolarEdgeAPI_UpdateState($hash, "error");

    # drop all outstanding requests
    $hash->{actionQueue} = [];

    return 2;
  }

  if (($data =~ /Error/i) and (exists( $param->{code})))
  {
    # update debug counter
    $hash->{NUMBER_OF_ERROR_3} = $hash->{NUMBER_OF_ERROR_3} + 1;
    if (AttrVal($name, "enableDebugReadings", undef))
    {
      readingsSingleUpdate($hash, 'debugNumError3', $hash->{NUMBER_OF_ERROR_3}, 1);
    }

    Log3 $name, 3, "SolarEdgeAPI ($name) - error (3) in http response, code: ".$param->{code};
    SolarEdgeAPI_UpdateState($hash, "error");

    # drop all outstanding requests
    $hash->{actionQueue} = [];

    return 3;
  }

  return undef;
}

sub SolarEdgeAPI_HandleHttpResponse($$$)
{
  my ($param, $err, $data)  = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};

  Log3 $name, 4, "SolarEdgeAPI ($name) - SolarEdgeAPI_HandleHttpResponse";

  if (SolarEdgeAPI_CheckHttpError($hash, $param, $err, $data))
  {
    return;
  }

  Log3 $name, 5, "SolarEdgeAPI ($name) - received JSON data: $data";

  # update debug counter
  $hash->{NUMBER_OF_GOOD_RESPONSES} = $hash->{NUMBER_OF_GOOD_RESPONSES} + 1;
  if (AttrVal($name, "enableDebugReadings", undef))
  {
    readingsSingleUpdate($hash, 'debugNumGoodResponses', $hash->{NUMBER_OF_GOOD_RESPONSES}, 1);
  }

  SolarEdgeAPI_ProcessResponse($hash, $param->{setCmd}, $data);

  if (defined($hash->{actionQueue}) and scalar(@{$hash->{actionQueue}}) > 0)
  {
    SolarEdgeAPI_SendHttpRequest($hash);
  }
}

sub SolarEdgeAPI_ProcessResponse($$$)
{
  my ($hash, $path, $data) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "SolarEdgeAPI ($name) - SolarEdgeAPI_ProcessResponse: $path";

  my $readings;

  # generate fake data for storage data API for debug purposes
  my $generateFakeStorageData = 0;
  if ((($path eq 'storage') or ($path eq 'dailyStorage')) and ($generateFakeStorageData))
  {
    $data = '{"storageData":{"batteryCount":1,"batteries":[{
    "nameplate":9800.0,"serialNumber":"R155XXX","modelNumber":"R155XXX","telemetryCount":4,"telemetries":
    [{"timeStamp":"2019-11-15 00:02:35","power":100.0,"batteryState":3,"lifeTimeEnergyDischarged":2275121,"lifeTimeEnergyCharged":2646795,"batteryPercentageState":8.999232,"fullPackEnergyAvailable":9999.0,"internalTemp":21.1,"ACGridCharging":0.0},
    {"timeStamp":"2019-11-15 00:07:34","power":100.0,"batteryState":3,"lifeTimeEnergyDischarged":2275122,"lifeTimeEnergyCharged":2646795,"batteryPercentageState":8.999232,"fullPackEnergyAvailable":9999.0,"internalTemp":21.0,"ACGridCharging":0.0},
    {"timeStamp":"2019-11-15 00:12:34","power":100.0,"batteryState":3,"lifeTimeEnergyDischarged":2275123,"lifeTimeEnergyCharged":2646795,"batteryPercentageState":8.999232,"fullPackEnergyAvailable":9999.0,"internalTemp":21.0,"ACGridCharging":0.0},
    {"timeStamp":"2019-11-15 00:17:33","power":100.0,"batteryState":3,"lifeTimeEnergyDischarged":2276198,"lifeTimeEnergyCharged":2648149,"batteryPercentageState":10.99419,"fullPackEnergyAvailable":9999.0,"internalTemp":20.6,"ACGridCharging":0.0}
    ]}]}}';
  }

  my $decodedJsonData = eval{decode_json($data)};

  if ($@)
  {
    # update debug counter
    $hash->{NUMBER_OF_JSON_ERRORS} = $hash->{NUMBER_OF_JSON_ERRORS} + 1;
    if (AttrVal($name, "enableDebugReadings", undef))
    {
      readingsSingleUpdate($hash, 'debugNumJsonErrors', $hash->{NUMBER_OF_JSON_ERRORS}, 1);
    }

    Log3 $name, 3, "SolarEdgeAPI ($name) - JSON error: $@";
    SolarEdgeAPI_UpdateState($hash, "error");

    return;
  }

  if ($path eq 'aggregates')
  {
    $readings = SolarEdgeAPI_ReadingsProcessing_Aggregates($hash, $decodedJsonData);
  }
  elsif ($path eq 'status')
  {
    $readings = SolarEdgeAPI_ReadingsProcessing_Status($hash, $decodedJsonData);
  }
  elsif ($path eq 'overview')
  {
    $readings = SolarEdgeAPI_ReadingsProcessing_Overview($hash, $decodedJsonData, 0);
  }
  elsif ($path eq 'storage')
  {
    $readings = SolarEdgeAPI_ReadingsProcessing_Storage($hash, $decodedJsonData, 0);
  }
  elsif ($path eq 'dailyDetails')
  {
    $readings = SolarEdgeAPI_ReadingsProcessing_DailyDetails($hash, $decodedJsonData);
  }
  elsif ($path eq 'dailyStorage')
  {
    $readings = SolarEdgeAPI_ReadingsProcessing_Storage($hash, $decodedJsonData, 1);
  }
  elsif ($path eq 'dailyOverview')
  {
    $readings = SolarEdgeAPI_ReadingsProcessing_Overview($hash, $decodedJsonData, 1);
  }
  elsif ($path eq 'dailyAggregates')
  {
    $readings = SolarEdgeAPI_ReadingsProcessing_DailyAggregates($hash, $decodedJsonData);
  }
  else
  {
    Log3 $name, 3, "SolarEdgeAPI ($name) - unknown type of response: $path";
  }

  SolarEdgeAPI_UpdateReadings($hash, $path, $readings);
  
  SolarEdgeAPI_UpdateState($hash, "active");
}

sub SolarEdgeAPI_ReadingsProcessing_Aggregates($$)
{
  my ($hash, $decodedJsonData) = @_;
  my $name = $hash->{NAME};

  my %readings;

  if (not (ref($decodedJsonData) eq "HASH"))
  {
    Log3 $name, 3, "SolarEdgeAPI ($name) - aggregates response is not a hash";
    return \%readings;
  }

  foreach my $meter ( @{$decodedJsonData->{'energyDetails'}->{'meters'}})
  {
    my $meterType = $meter->{'type'};
    my $meterCum = 0;
    my $meterRecent15Min = 0;
    foreach my $meterData (@{$meter -> {'values'}})
    {
      my $value = $meterData->{'value'};
      if (defined $value)
      {
        $meterCum = $meterCum + $value;
        $meterRecent15Min = $value;
      }
    }
    $readings{$meterType . "-cumToday"} = $meterCum;
    $readings{$meterType . "-recent15min"} = $meterRecent15Min;
  }

  return \%readings;
}

sub SolarEdgeAPI_IsLastDayOfMonth($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $isLastDayOfMonth = 0;

  my $epoch = time();
  my ($sec1, $min1, $hour1, $mday1, $mon1, $year1, $wday1, $yday1, $isdst1) = localtime($epoch);
  my $epochOneDayLater = $epoch + 24 * 60 * 60;
  my ($sec2, $min2, $hour2, $mday2, $mon2, $year2, $wday2, $yday2, $isdst2) = localtime($epochOneDayLater);

  if ($mon1 != $mon2)
  {
    $isLastDayOfMonth = 1;
  }

  my $month = $mon1 + 1;
  my $day = $mday1;

  Log3 $name, 4, "SolarEdgeAPI ($name) - day $day month $month isLastDayOfMonth $isLastDayOfMonth";

  return $isLastDayOfMonth;
}

sub SolarEdgeAPI_IsLastDayOfYear($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $isLastDayOfYear = 0;
  my $epoch = time();
  my ($sec1, $min1, $hour1, $mday1, $mon1, $year1, $wday1, $yday1, $isdst1) = localtime($epoch);
  my $epochOneDayLater = $epoch + 24 * 60 * 60;
  my ($sec2, $min2, $hour2, $mday2, $mon2, $year2, $wday2, $yday2, $isdst2) = localtime($epochOneDayLater);
  if ($year1 != $year2)
  {
    $isLastDayOfYear = 1;
  }
  my $month = $mon1 + 1;
  my $day = $mday1;

  Log3 $name, 4, "SolarEdgeAPI ($name) - day $day month $month isLastDayOfYear $isLastDayOfYear";

  return $isLastDayOfYear;
}


sub SolarEdgeAPI_ReadingsProcessing_DailyAggregates($$)
{
  my ($hash, $decodedJsonData) = @_;
  my $name = $hash->{NAME};

  my %readings;

  if (not (ref($decodedJsonData) eq "HASH"))
  {
    Log3 $name, 3, "SolarEdgeAPI ($name) - daily aggregates response is not a hash";
    return \%readings;
  }

  my ($sec, $min, $hour, $day, $month, $year, $wday, $yday, $isdst) = localtime(time());
  $month = $month + 1;

  # iterate over day for different meters
  foreach my $meter ( @{$decodedJsonData->{'energyDetails'}->{'meters'}})
  {
    my $meterType = $meter->{'type'};
    my $cumYear = 0;
    my $cumMonth = 0;
    my $cumToday = 0;

    Log3 $name, 4, "SolarEdgeAPI ($name) - meterType $meterType";

    # accumulate values of one meter
    foreach my $meterData (@{$meter -> {'values'}})
    {
      my $value = $meterData->{'value'};

      # decode timestamp, example: "2015-10-19 00:00:00"
      my $timestamp = $meterData->{'date'};
      my $timestampMonth = -1;
      my $timestampDay = -1;
      if (!($timestamp =~ m/^([0-9]+)\-([0-9]+)\-([0-9]+)/))
      {
        Log3 $name, 3, "SolarEdgeAPI ($name) - invalid timestamp in energyDetails response";
      }
      else
      {
        $timestampMonth = $2;
        $timestampDay = $3;
      }

      Log3 $name, 4, "SolarEdgeAPI ($name) - $timestamp $value - timestampMonth $timestampMonth timestampDay $timestampDay";

      # cumulate for all days of this year
      $cumYear += $value;

      # cumulate for all days of this month
      if ($timestampMonth == $month)
      {
        $cumMonth += $value;

        # detect the cumulated value for today
        if ($timestampDay == $day)
        {
          $cumToday = $value;
        }
      }
    }

    $readings{$meterType."-cumYear"} = $cumYear / 1000.0;
    $readings{$meterType."-cumMonth"} = $cumMonth / 1000.0;
    $readings{$meterType."-cumDay"} = $cumToday;

    if (SolarEdgeAPI_IsLastDayOfMonth($hash))
    {
      $readings{$meterType."-cumMonthOnce"} = $cumMonth / 1000.0;
    }
    if (SolarEdgeAPI_IsLastDayOfYear($hash))
    {
      $readings{$meterType."-cumYearOnce"} = $cumYear / 1000.0;
    }
  }

  return \%readings;
}

sub SolarEdgeAPI_ReadingsProcessing_Status($$)
{
  my ($hash, $decodedJsonData) = @_;
  my $name = $hash->{NAME};

  my %readings;
  my $data = $decodedJsonData->{'siteCurrentPowerFlow'};

  if ((defined $data) && (!defined $data->{'unit'}))
  {
    Log3 $name, 3, "SolarEdgeAPI ($name) - API currentPowerFlow is not supported. Avoid unsuccessful server queries by setting attribute enableStatusReadings=0.";
  }
  else
  {
    $readings{'unit'} = $data->{'unit'} || "Error Reading Response";
    $readings{'updateRefreshRate'} = $data->{'updateRefreshRate'} || "Error Reading Response";

    # Connections / Directions
    my $pv2load = 0;
    my $pv2storage = 0;
    my $load2storage = 0;
    my $storage2load = 0;
    my $load2grid = 0;
    my $grid2load = 0;
    foreach my $connection ( @{ $data->{'connections'} }) {
      my $from = lc($connection->{'from'});
      my $to = lc($connection->{'to'});
      if (($from eq 'grid') and ($to eq 'load')) { $grid2load = 1; }
      if (($from eq 'load') and ($to eq 'grid')) { $load2grid = 1; }
      if (($from eq 'load') and ($to eq 'storage')) { $load2storage = 1; }
      if (($from eq 'pv') and ($to eq 'storage')) { $pv2storage = 1; }
      if (($from eq 'pv') and ($to eq 'load')) { $pv2load = 1; }
      if (($from eq 'storage') and ($to eq 'load')) { $storage2load = 1; }
    }

    # GRID
    $readings{'grid_status'} = $data->{'GRID'}->{"status"} || "-";
    $readings{'grid_power'} = (($load2grid > 0) ? "-" : "").$data->{'GRID'}->{"currentPower"};

    # LOAD
    $readings{'load_status'} = $data->{'LOAD'}->{"status"} || "-";
    $readings{'load_power'} = $data->{'LOAD'}->{"currentPower"};

    # PV
    $readings{'pv_status'} = $data->{'PV'}->{"status"} || "-";
    $readings{'pv_power'} = $data->{'PV'}->{"currentPower"};

    # Storage
    $readings{'storage_status'} = $data->{'STORAGE'}->{"status"} || "-";
    if ($readings{'storage_status'} ne "-")
    {
      $readings{'storage_power'} = (($storage2load > 0) ? "-" : "").$data->{'STORAGE'}->{"currentPower"};
      $readings{'storage_level'} = $data->{'STORAGE'}->{"chargeLevel"} || "-";
      $readings{'storage_critical'} = $data->{'STORAGE'}->{"critical"};
    }
  }

  return \%readings;
}

sub SolarEdgeAPI_ReadingsProcessing_Overview($$$)
{
  my ($hash, $decodedJsonData, $daily) = @_;
  my $name = $hash->{NAME};

  my %readings;
  my $data = $decodedJsonData->{'overview'};

  if (not $daily)
  {
    $readings{'power'} = $data->{'currentPower'}->{"power"};
  }
  $readings{'energyLifetime'} = $data->{'lifeTimeData'}->{"energy"} / 1000.0 / 1000.0;
  my $energyYear = $data->{'lastYearData'}->{"energy"} / 1000.0;
  $readings{'energyYear'} = $energyYear;

  my $energyMonth = $data->{'lastMonthData'}->{"energy"} / 1000.0;
  $readings{'energyMonth'} =  $energyMonth;

  my $energyDay = $data->{'lastDayData'}->{"energy"};
  $readings{'energyDay'} = $energyDay;

  if (SolarEdgeAPI_IsLastDayOfMonth($hash))
  {
    $readings{"energyMonthOnce"} = $energyMonth;
  }
  if (SolarEdgeAPI_IsLastDayOfYear($hash))
  {
    $readings{"energyYearOnce"} = $energyYear;
  }

  return \%readings;
}

sub SolarEdgeAPI_decodeBatteryState($)
{
  my ($code) = @_;

  my $result = "$code"."_";

  if ($code == 0) { $result .= "Off"; }
  elsif ($code == 1) { $result .= "Standby"; }
  elsif ($code == 2) { $result .= "Init"; }
  elsif ($code == 3) { $result .= "Charge"; }
  elsif ($code == 4) { $result .= "Discharge"; }
  elsif ($code == 5) { $result .= "Fault"; }
  elsif ($code == 7) { $result .= "Idle"; }
  else { $result .= "Unknown"; }

  return $result;
}

sub SolarEdgeAPI_ReadingsProcessing_Storage($$$)
{
  my ($hash, $decodedJsonData, $daily) = @_;
  my $name = $hash->{NAME};

  my %readings;

  if (not (ref($decodedJsonData) eq "HASH"))
  {
    Log3 $name, 3, "SolarEdgeAPI ($name) - storageData response is not a hash";
    return \%readings;
  }

  foreach my $batteryData ( @{$decodedJsonData->{'storageData'}->{'batteries'}})
  {
    my $serialNumber = $batteryData->{'serialNumber'};

    Log3 $name, 4, "SolarEdgeAPI ($name) - serialNumber $serialNumber";

    my $power = 0;
    my $batteryState = -1;
    my $lifeTimeEnergyCharged = 0;
    my $lifeTimeEnergyDischarged = 0;
    my $fullPackEnergyAvailable = 0;
    my $internalTemp = 0;
    my $batteryPercentageState = 0;
    my $acGridCharging = 0;

    foreach my $dataset (@{$batteryData -> {'telemetries'}})
    {
      my $newPower = $dataset->{'power'};
      my $newBatteryState = $dataset->{'batteryState'};
      my $newLifeTimeEnergyCharged = $dataset->{'lifeTimeEnergyCharged'};
      my $newLifeTimeEnergyDischarged = $dataset->{'lifeTimeEnergyDischarged'};
      my $newFullPackEnergyAvailable = $dataset->{'fullPackEnergyAvailable'};
      my $newInternalTemp = $dataset->{'internalTemp'};
      my $newBatteryPercentageState = $dataset->{'batteryPercentageState'};
      my $newAcGridCharging = $dataset->{'ACGridCharging'};

      if (($newPower > -100000) and ($newPower < 100000)) { $power = $newPower; }
      if (($newBatteryState >= 0) and ($newBatteryState <= 10)) { $batteryState = $newBatteryState; }
      if ($newLifeTimeEnergyCharged > 0) { $lifeTimeEnergyCharged = $newLifeTimeEnergyCharged; }
      if ($newLifeTimeEnergyDischarged > 0) { $lifeTimeEnergyDischarged = $newLifeTimeEnergyDischarged; }
      if ($newFullPackEnergyAvailable > 0) { $fullPackEnergyAvailable = $newFullPackEnergyAvailable; }
      if (($newInternalTemp > 0) and ($newInternalTemp < 200)) { $internalTemp = $newInternalTemp; }
      if (($newBatteryPercentageState >= 0) and ($newBatteryPercentageState <= 100)) { $batteryPercentageState = $newBatteryPercentageState; }
      if ($newAcGridCharging >= 0) { $acGridCharging = $newAcGridCharging; }

      Log3 $name, 4, "SolarEdgeAPI ($name) - new: $newPower $newBatteryState $newLifeTimeEnergyCharged $newLifeTimeEnergyDischarged $newFullPackEnergyAvailable $newInternalTemp $newBatteryPercentageState $newAcGridCharging";
      Log3 $name, 4, "SolarEdgeAPI ($name) - $power $batteryState $lifeTimeEnergyCharged $lifeTimeEnergyDischarged $fullPackEnergyAvailable $internalTemp $batteryPercentageState $acGridCharging";
    }

    if ($daily)
    {
      $readings{$serialNumber."-lifeTimeEnergyCharged"} = $lifeTimeEnergyCharged / 1000.0 / 1000.0;
      $readings{$serialNumber."-lifeTimeEnergyDischarged"} = $lifeTimeEnergyDischarged / 1000.0 / 1000.0;
      $readings{$serialNumber."-fullPackEnergyAvailable"} = $fullPackEnergyAvailable;
    }
    else
    {
      $readings{$serialNumber."-power"} = $power;
      $readings{$serialNumber."-batteryState"} = $batteryState;
      $readings{$serialNumber."-batteryStateDecoded"} = SolarEdgeAPI_decodeBatteryState($batteryState);
      $readings{$serialNumber."-lifeTimeEnergyCharged"} = $lifeTimeEnergyCharged;
      $readings{$serialNumber."-lifeTimeEnergyDischarged"} = $lifeTimeEnergyDischarged;
      $readings{$serialNumber."-internalTemp"} = $internalTemp;
      $readings{$serialNumber."-batteryPercentageState"} = $batteryPercentageState;
      $readings{$serialNumber."-ACGridCharging"} = $acGridCharging;
    }
  }

  return \%readings;
}

sub SolarEdgeAPI_ReadingsProcessing_DailyDetails($$)
{
  my ($hash, $decodedJsonData) = @_;
  my $name = $hash->{NAME};

  my %readings;
  my $data = $decodedJsonData->{'details'};

  # documented but not in the response:
  #$readings{'alertQuantity'} = $data->{'alertQuantity'};
  #$readings{'alertSeverity'} = $data->{'alertSeverity'};

  $readings{'peakPower'} = $data->{'peakPower'};
  $readings{'status'} = $data->{'status'};

  return \%readings;
}

sub SolarEdgeAPI_UpdateReadings($$$)
{
  my ($hash, $path, $readings) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "SolarEdgeAPI ($name) - SolarEdgeAPI_UpdateReadings";

  readingsBeginUpdate($hash);
  while (my ($r,$v) = each %{$readings})
  {
    readingsBulkUpdate($hash,$path.'-'.$r,$v);
  }
  readingsEndUpdate($hash, 1);
}

###############################################################################
# update "state"
###############################################################################

sub SolarEdgeAPI_UpdateState($$)
{
  my ($hash, $newState) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "SolarEdgeAPI ($name) - new state: $newState";
  $hash->{STATE} = $newState;
  readingsSingleUpdate($hash, "state", $newState, 1);
}

###############################################################################
# show SolarEdge logo
###############################################################################

sub SolarEdgeAPI_fhemwebFn($$$)
{
  my ($FW_wname, $d, $room) = @_;
  return << 'EOF'
<br>
<a href="https://www.solaredge.com">
<img src="https://www.solaredge.com/sites/default/files/SolarEdge_logo_header_new.png">
</a>
<br>
EOF
}

1;

=pod
=item device
=item summary       Retrieves data from a SolarEdge PV system via the SolarEdge Monitoring API
=item summary_DE
=begin html

<a name="SolarEdgeAPI"></a>
<h3>SolarEdgeAPI</h3>

<ul>
  This module retrieves data from a SolarEdge PV system via the SolarEdge Server Monitoring API.<br>
  <br>
  Data is retrieved from the server periodically. The interval during day time is typically higher<br>
  compared to night time. According to the API documentation the total number of server queries per<br>
  day is limited to 300.<br>
  The intervals as well as the start of day time and night time can be controlled by attributes.<br>
  In each interval each enabled group of readings is generated once. You can reduce the number of<br>
  server queries by disabling groups of readings and by increasing the interval time.<br>
  <br>
  Note: Features marked as "deprecated" or "debug only" may change or disappear in future versions.<br>
  <br>

  <a name="SolarEdgeAPI_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; SolarEdgeAPI &lt;API Key&gt; &lt;Site ID&gt;</code><br>
    The &lt;API Key&gt; and the &lt;Site ID&gt can be retrieved from the SolarEdge<br>
    Monitoring Portal. The &lt;API Key&gt; has to be enabled in the "Admin" Secion<br>
    of the web portal.<br>
  </ul>
  <br>

  <a name="SolarEdgeAPI_Readings"></a>
  <b>Readings</b>
  <ul>
    All reading names start with the name of the group of readings followed by "-".<br>
    All readings that belong to the same group have the same timing: Some groups of readings are generated<br>
    periodically. The period is defined by attributes intervalAtDayTime, intervalAtNighttime, dayTimeStartHour and<br>
    nightTimeStartHour. Other readings are generated once per day only. Reading groups which are update<br>
    once per day have a name starting with "daily". Each update of a group of readings requires on http<br>
    request to the SolarEdge server. The number of queries is limited to 300 per day, according to API<br>
    documentation.<br>
    <br>
    Groups of readings:<br>
    <br>

    <li>overview - readings generated from "overview" API response
      <ul>
        <li>overview-power [W]</li>
        <li>overview-energyLifetime [MWh]</li>
        <li>overview-energyYear [kWh]</li>
        <li>overview-energyMonth [kWh]</li>
        <li>overview-energyDay [Wh]</li>
      </ul>
    </li>

    <li>dailyOverview - readings generated from "overview" API response once per day
      <ul>
        <li>dailyOverview-energyDay [Wh] - This reading is derived. It depends on the latest dailyOverview-energyMonth reading.</li>
        <li>dailyOverview-energyMonth [kWh]</li>
        <li>dailyOverview-energyYear [kWh]</li>
        <li>dailyOverview-energyLifetime [MWh]</li>
        <li>dailyOverview-energyMonthOnce [kWh] generated on the last day of the month only</li>
        <li>dailyOverview-energyYearOnce [kWh] generated on the last day of the year only</li>
      </ul>
    </li>

    <li>aggregates - readings generated from "energyDetails" API response<br>
      <ul>
        <li>aggregates-&lt;meterType&gt;-cumToday [Wh]</li>
        <li>aggregates-&lt;meterType&gt;-recent15min [Wh](deprecated) </li>
      </ul>
    </li>

    <li>dailyAggregates - readings generated from "energyDetails" API response once per day<br>
      <ul>
        <li>dailyAggregates-&lt;meterType&gt;-cumDayOnce [Wh]</li>
        <li>dailyAggregates-&lt;meterType&gt;-cumMonthDaily [kWh]</li>
        <li>dailyAggregates-&lt;meterType&gt;-cumYearDaily [kWh]</li>
        <li>dailyAggregates-&lt;meterType&gt;-cumMonthOnce [kWh] generated on the last day of the month only</li>
        <li>dailyAggregates-&lt;meterType&gt;-cumYearOnce [kWh] generated on the last day of the year only</li>
      </ul>
    </li>

    <li>storage - readings generated from "storageData" API response<br>
      <ul>
        <li>storage-&lt;serial&gt;-power [W]</li>
        <li>storage-&lt;serial&gt;-batteryState</li>
        <li>storage-&lt;serial&gt;-batteryStateDecoded [text]</li>
        <li>storage-&lt;serial&gt;-lifetimeEnergyCharged</li>
        <li>storage-&lt;serial&gt;-lifetimeEnergyDischarged</li>
        <li>storage-&lt;serial&gt;-internalTemp [degrees C]</li>
        <li>storage-&lt;serial&gt;-batteryPercentageState [percent]</li>
      </ul>
    </li>

    <li>dailyStorage - readings generated from "storageData" API response once per day<br>
      <ul>
        <li>dailyStorage-&lt;serial&gt;-lifetimeEnergyCharged [MWh]</li>
        <li>dailyStorage-&lt;serial&gt;-lifetimeEnergyDischarged [MWh]</li>
        <li>dailyStorage-&lt;serial&gt;-fullPackEnergyAvailable [kWh]</li>
      </ul>
    </li>

    <li>dailyDetails - readings generated from "details" API response once per day<br>
      <ul>
        <li>dailyDetails-peakPower [W]</li>
        <li>dailyDetails-status [text]</li>
      </ul>
    </li>

    <li>status - readings generated from "currentPowerFlow" API response. This API is not supported by all sites.<br>
      <ul>
        <li>status-grid_status [?]</li>
        <li>status-grid_power [W]</li>
        <li>status-load_status [?]</li>
        <li>status-load_power [W]</li>
        <li>status-pv_status [?]</li>
        <li>status-pv_power [W]</li>
        <li>status-storage_status [?]</li>
        <li>status-storage_power [W]</li>
        <li>status-storage_level [?]</li>
        <li>status-storage_critical [?]</li>
      </ul>
    </li>

    <li>debug - debug data about successful and failing http requests (for debug only)</li>
    <li>actionQueue - information about the entries in the action queue (for debug only)</li>
  </ul>
  <br>

  <a name="SolarEdgeAPI_Get"></a>
  <b>Get</b>
  <ul>
    <li>numberOfRequests - get the expected number of requests per day with current attribute settings (for debug only)</li>
    <li>status - fetch corresponding group of readings (for debug only)</li>
    <li>aggregates - fetch corresponding group of readings (for debug only)</li>
    <li>overview - fetch corresponding group of readings (for debug only)</li>
    <li>storage - fetch corresponding group of readings (for debug only)</li>
    <li>dailyDetails - fetch corresponding group of readings (for debug only)</li>
    <li>dailyStorage - fetch corresponding group of readings (for debug only)</li>
    <li>dailyAggregates - fetch corresponding group of readings (for debug only)</li>
    <li>dailyOverview - fetch corresponding group of readings (for debug only)</li>
  </ul>
  <br>

  <a name="SolarEdgeAPI_Set"></a>
  <b>Set</b>
  <ul>
    <li>restartTimer - restart periodic http requests (for debug only)</li>
    <li>resetDebugCounters - reset debug counters (internals and optional debug* readings) (for debug only)</li>
  </ul>
  <br>

  <a name="SolarEdgeAPI_Attributes"></a>
  <b>Attributes</b>
  <ul>
    <li>intervalAtDayTime - interval of http requests during day time (default: 215 (seconds))</li>
    <li>intervalAtNightTime - interval of http requests during night time (default: 1200 (seconds))</li>
    <li>dayTimeStartHour - start of daytime, default 6 (= 6:00am)</li>
    <li>nightTimeStartHour - start of night time, default 22 (= 10:00pm)</li>
    <li>enableStatusReadings - enable the corresponding group of readings, default: 0</li>
    <li>enableAggregatesReadings - enable the corresponding group of readings, default: 0</li>
    <li>enableOverviewReadings  - enable the corresponding group of readings, default: 1</li>
    <li>enableStorageReadings - enable the corresponding group of readings, default: 0</li>
    <li>enableDailyDetailsReadings - enable the corresponding group of readings, default: 1</li>
    <li>enableDailyStorageReadings - enable the corresponding group of readings, default: 0</li>
    <li>enableDailyAggregatesReadings - enable the corresponding group of readings, default: 0</li>
    <li>enableDailyOverviewReadings - enable the corresponding group of readings, default: 1</li>
    <li>enableDebugReadings Enable the debug* readings. These debug readings do not cause additional http requests. Default: 0</li>
  </ul>
  <br>

</ul>

=end html

=cut
