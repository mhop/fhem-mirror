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
###############################################################################

sub SolarEdgeAPI_SetVersion($)
{
  my ($hash) = @_;
  $hash->{VERSION} = "1.3.0";
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
  $hash->{AttrList}   = "interval ".
                        "intervalAtNightTime ".
                        "dayTimeStartHour ".
                        "nightTimeStartHour ".
                        "disable:1 ".
                        "enableStatusReadings:1,0 ".
                        "enableAggregatesReadings:1,0 ".
                        "enableOverviewReadings:1,0 ".
                        "enableDebugReadings:1,0 ".
                        $readingFnAttributes;
                        
  $hash->{FW_detailFn} = "SolarEdgeAPI_fhemwebFn";
}

sub SolarEdgeAPI_Define($$)
{
  my ($hash, $def) = @_;

  my @a = split( "[ \t][ \t]*", $def );

  if ((int(@a) != 4) and (int(@a) != 5))
  {
    return "too few parameters: define <name> SolarEdgeAPI <API-Key> <Site-ID> [<interval>|auto]";
  }
  
  if ($solarEdgeAPI_missingModul)
  {
    return "Cannot define a SolarEdgeAPI device. Perl modul $solarEdgeAPI_missingModul is missing.";
  }

  my $name = $a[0];
  
  $hash->{APIKEY} = $a[2];
  $hash->{SITEID} = $a[3];
  
  # if interval information is provided store it in the hash
  if ((int(@a) == 4) or ($a[4] eq 'auto'))
  {
    $hash->{INTERVAL} = undef;
  }
  else
  {
    $hash->{INTERVAL} = $a[4];
  }
  
  $hash->{PORT} = 80;
  $hash->{NOTIFYDEV} = "global";
  $hash->{actionQueue} = [];
  
  SolarEdgeAPI_ResetDebugCounters($hash);
  
  SolarEdgeAPI_SetVersion($hash);

  # TODO Remove this? (INCOMPATIBLE CHANGE)
  $attr{$name}{room} = "Photovoltaik" if( !defined( $attr{$name}{room} ) );

  Log3 $name, 3, "SolarEdgeAPI ($name) - defined";

  # TODO why does one of the paths have a ".json" and the others do not?
  my %paths = (
    'status' => 'currentPowerFlow.json',
    'aggregates' => 'energyDetails',
    'overview' => 'overview'
  );
  $hash->{PATHS} = \%paths;

  # remove any active timer
  RemoveInternalTimer($hash);

  # initiate periodic readings
  InternalTimer(gettimeofday() + 60, 'SolarEdgeAPI_RestartHttpRequestTimer', $hash);

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
        readingsSingleUpdate($hash, "state", "disabled", 1);
        Log3 $name, 3, "SolarEdgeAPI ($name) - attribute disable=1";
      }
      elsif ($attrVal eq "0")
      {
        InternalTimer(gettimeofday() + 5, 'SolarEdgeAPI_RestartHttpRequestTimer', $hash);
        readingsSingleUpdate($hash, "state", "active", 1);
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
      InternalTimer(gettimeofday() + 5, 'SolarEdgeAPI_RestartHttpRequestTimer', $hash);
      readingsSingleUpdate($hash, "state", "active", 1);
      Log3 $name, 3, "SolarEdgeAPI ($name) - attribute disable deleted";
    }
  }

  if ($attrName eq "disabledForIntervals")
  {
    if ($cmd eq "set")
    {
      return "check disabledForIntervals Syntax HH:MM-HH:MM or 'HH:MM-HH:MM HH:MM-HH:MM ...'"
        unless($attrVal =~ /^((\d{2}:\d{2})-(\d{2}:\d{2})\s?)+$/);
      readingsSingleUpdate($hash, "state", "disabled", 1);        
      Log3 $name, 3, "SolarEdgeAPI ($name) - attribute disabledForIntervals set";
    } 
    elsif ($cmd eq "del")
    {
      readingsSingleUpdate( $hash, "state", "active", 1 );
      Log3 $name, 3, "SolarEdgeAPI ($name) - attribute disabledForIntervals deleted";
    }
  }
    
  if ($attrName eq "interval")
  {
    if ($cmd eq "set")
    {
      if (($attrVal eq "auto") || ($attrVal >= 120))
      {
        InternalTimer(gettimeofday() + 5, 'SolarEdgeAPI_RestartHttpRequestTimer', $hash);
        Log3 $name, 3, "SolarEdgeAPI ($name) - attribute interval set to $attrVal";
      }
      else
      {
        my $message = "interval is out of range";
        Log3 $name, 3, "SolarEdgeAPI ($name) - ".$message;
        return $message;
      }
    }
    elsif ($cmd eq "del")
    {
      InternalTimer(gettimeofday() + 5, 'SolarEdgeAPI_RestartHttpRequestTimer', $hash);
      Log3 $name, 3, "SolarEdgeAPI ($name) - attribute interval deleted";
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
        InternalTimer(gettimeofday() + 5, 'SolarEdgeAPI_RestartHttpRequestTimer', $hash);
        Log3 $name, 3, "SolarEdgeAPI ($name) - attribute intervalAtNightTime set to $attrVal";
      }
    }
    elsif ($cmd eq "del")
    {
      InternalTimer(gettimeofday() + 5, 'SolarEdgeAPI_RestartHttpRequestTimer', $hash);
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
        InternalTimer(gettimeofday() + 5, 'SolarEdgeAPI_RestartHttpRequestTimer', $hash);
        Log3 $name, 3, "SolarEdgeAPI ($name) - attribute dayTimeStartHour set to $attrVal";
      }
    }
    elsif ($cmd eq "del")
    {
      InternalTimer(gettimeofday() + 5, 'SolarEdgeAPI_RestartHttpRequestTimer', $hash);
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
        InternalTimer(gettimeofday() + 5, 'SolarEdgeAPI_RestartHttpRequestTimer', $hash);
        Log3 $name, 3, "SolarEdgeAPI ($name) - attribute nightTimeStartHour set to $attrVal";
      }
    }
    elsif ($cmd eq "del")
    {
      InternalTimer(gettimeofday() + 5, 'SolarEdgeAPI_RestartHttpRequestTimer', $hash);
      Log3 $name, 3, "SolarEdgeAPI ($name) - attribute nightTimeStartHour deleted";
    }
  }
                        
  if ($attrName eq "enableStatusReadings") 
  {
    if($cmd eq "set")
    {
      if (not (($attrVal eq "0") || ($attrVal eq "1")))
      {
        my $message = "illegal value for enableStatusReadings";
        Log3 $name, 3, "SolarEdgeAPI ($name) - ".$message;
        return $message; 
      }
      else
      {
        InternalTimer(gettimeofday() + 5, 'SolarEdgeAPI_RestartHttpRequestTimer', $hash);
      }
    } 
  }

  if ($attrName eq "enableAggregatesReadings") 
  {
    if($cmd eq "set")
    {
      if (not (($attrVal eq "0") || ($attrVal eq "1")))
      {
        my $message = "illegal value for enableAggregatesReadings";
        Log3 $name, 3, "SolarEdgeAPI ($name) - ".$message;
        return $message; 
      }
      else
      {
        InternalTimer(gettimeofday() + 5, 'SolarEdgeAPI_RestartHttpRequestTimer', $hash);
      }
    } 
  }

  if ($attrName eq "enableOverviewReadings") 
  {
    if($cmd eq "set")
    {
      if (not (($attrVal eq "0") || ($attrVal eq "1")))
      {
        my $message = "illegal value for enableOverviewReadings";
        Log3 $name, 3, "SolarEdgeAPI ($name) - ".$message;
        return $message; 
      }
      else
      {
        InternalTimer(gettimeofday() + 5, 'SolarEdgeAPI_RestartHttpRequestTimer', $hash);
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
    SolarEdgeAPI_RestartHttpRequestTimer($hash);
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
  
  if (($cmd eq 'status') or ($cmd eq 'aggregates') or ($cmd eq 'overview'))
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
  else 
  {
    my $list = 'status:noArg aggregates:noArg overview:noArg';    
    return "Unknown argument $cmd, choose one of $list";
  }

  return undef;
}

###############################################################################
# HTTP request generation
###############################################################################

sub SolarEdgeAPI_SendHttpRequest($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $siteid = $hash->{SITEID};
  my $host = "monitoringapi.solaredge.com/site/".$siteid;
  my $apikey = $hash->{APIKEY};
  my $path = pop(@{$hash->{actionQueue}});
 
  # TODO explain  
  my $params = "";
  if ($path eq "aggregates")
  {
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    $params= "&timeUnit=QUARTER_OF_AN_HOUR&startTime=".(1900+$year)."-".(1+$mon)."-".$mday."%2000:00:00&endTime=".(1900+$year)."-".(1+$mon)."-".$mday."%20".$hour.":".$min.":".$sec;
  }

  my $pathsRef = $hash->{PATHS};
  my %paths = %$pathsRef;
  
  my $uri = $host . '/' . $paths{$path} . "?api_key=" . $apikey.$params;

  # TODO remove this (INCOMPATIBLE CHANGE)
  readingsSingleUpdate($hash, 'state', 'fetch data - '.scalar(@{$hash->{actionQueue}}).' entries in the Queue',1);

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

sub SolarEdgeAPI_HttpRequestTimerFunction($)
{
  my $hash = shift;
  my $name = $hash->{NAME};

  Log3 $name, 4, "SolarEdgeAPI ($name) - timer expired";

  my $pathsRef = $hash->{PATHS};
  my %paths = %$pathsRef;

  if ((defined($hash->{actionQueue})) and (scalar(@{$hash->{actionQueue}}) == 0))
  {
    if (not IsDisabled($name))
    {
      while (my $obj = each %paths) 
      {
        if ((($obj eq "status") and (AttrVal($name, "enableStatusReadings", 1))) or
            (($obj eq "aggregates") and (AttrVal($name, "enableAggregatesReadings", 1))) or
            (($obj eq "overview") and (AttrVal($name, "enableOverviewReadings", 0))))
        {
          Log3 $name, 4, "SolarEdgeAPI ($name) - adding request to actionQueue: ".$obj;
          unshift( @{$hash->{actionQueue}}, $obj );
        }
      } 
      SolarEdgeAPI_SendHttpRequest($hash);
    } 
    else 
    {
      readingsSingleUpdate($hash,'state','disabled',1);
    }
  }

  InternalTimer(SolarEdgeAPI_GetTimeOfNextReading($hash), 'SolarEdgeAPI_HttpRequestTimerFunction', $hash);
}

sub SolarEdgeAPI_RestartHttpRequestTimer($)
{
  my $hash = shift;
  my $name = $hash->{NAME};
  
  Log3 $name, 3, "SolarEdgeAPI ($name) - restarting timer";
 
  # remove any active timer
  RemoveInternalTimer($hash);
  
  # Do the next http request now. This will start a timer for the next one.
  SolarEdgeAPI_HttpRequestTimerFunction($hash);  
}

sub SolarEdgeAPI_GetTimeOfNextReading($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

  my $dayTimeStartHour = AttrVal($name, "dayTimeStartHour", 7);
  my $nightTimeStartHour = AttrVal($name, "nightTimeStartHour", 22);

  # calculate interval during day time
  
  my $defaultDaytimeInterval = 300;
  if (defined $hash->{INTERVAL})
  {
    # if an interval value was specified with "define" it is the new "default"
    $defaultDaytimeInterval = $hash->{INTERVAL};
  }
  
  # Try to use the attribute value as interval.
  my $daytimeInterval = AttrVal($name, "interval", "auto");
    
  # If attribute "interval" does not provide a value use the default.
  # This means if both the define parameter and the attribute are given
  # the attribute wins.
  if ($daytimeInterval eq "auto")
  {
    $daytimeInterval = $defaultDaytimeInterval;
  }
  
  # calculate interval during night time
  
  my $defaultNighttimeInterval = 1200;
  my $nighttimeInterval = AttrVal($name, "intervalAtNightTime", $defaultNighttimeInterval);
  
  # calculate approximate number of http requests within 24 hours
  
  my $numberOfDaytimeHours = $nightTimeStartHour - $dayTimeStartHour;
  my $numberOfNighttimeHours = 24 - $numberOfDaytimeHours;
  my $numberOfHttpRequests = 0; 
  if (AttrVal($name, "enableStatusReadings", 1)) { $numberOfHttpRequests = $numberOfHttpRequests + 1; }
  if (AttrVal($name, "enableAggregatesReadings", 1)) { $numberOfHttpRequests = $numberOfHttpRequests + 1; }
  if (AttrVal($name, "enableOverviewReadings", 0)) { $numberOfHttpRequests = $numberOfHttpRequests + 1; }
            
  $hash->{NUMBER_OF_REQUESTS_PER_DAY} = 
    ($numberOfDaytimeHours * 3600 / $daytimeInterval + 
     $numberOfNighttimeHours * 3600 / $nighttimeInterval)
    * $numberOfHttpRequests;
  
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
    # TODO Remove this. Do error reporting via Log3 and debug readings. (INCOMPATIBLE CHANGE)
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, 'state', $err, 1);
    readingsBulkUpdate($hash, 'lastRequestError', $err, 1);
    readingsEndUpdate($hash, 1);
      
    # update debug counter
    $hash->{NUMBER_OF_ERROR_1} = $hash->{NUMBER_OF_ERROR_1} + 1;
    if (AttrVal($name, "enableDebugReadings", undef))
    {
      readingsSingleUpdate($hash, 'debugNumError1', $hash->{NUMBER_OF_ERROR_1}, 1);
    }
          
    Log3 $name, 3, "SolarEdgeAPI ($name) - error (1) in http response: $err";

    # drop all outstanding requests
    $hash->{actionQueue} = [];
    
    return 1;
  }

  if (($data eq "") and (exists($param->{code})) and ($param->{code} ne 200))
  {  
    # TODO Remove this. Do error reporting via Log3 and debug readings. (INCOMPATIBLE CHANGE)
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, 'state', $param->{code}, 1);
    readingsBulkUpdate($hash, 'lastRequestError', $param->{code}, 1);
    readingsEndUpdate($hash, 1);
    
    # update debug counter
    $hash->{NUMBER_OF_ERROR_2} = $hash->{NUMBER_OF_ERROR_2} + 1;
    if (AttrVal($name, "enableDebugReadings", undef))
    {
      readingsSingleUpdate($hash, 'debugNumError2', $hash->{NUMBER_OF_ERROR_2}, 1);
    }

    Log3 $name, 3, "SolarEdgeAPI ($name) - error (2) in http response, no data, code: ".$param->{code};

    # drop all outstanding requests
    $hash->{actionQueue} = [];
    
    return 2;
  }

  if (($data =~ /Error/i) and (exists( $param->{code})))
  {     
    # TODO Remove this. Do error reporting via Log3 and debug readings. (INCOMPATIBLE CHANGE)
    readingsBeginUpdate($hash);    
    readingsBulkUpdate($hash, 'state', $param->{code}, 1);
    readingsBulkUpdate($hash, "lastRequestError", $param->{code}, 1);
    readingsEndUpdate($hash, 1);
    
    # update debug counter
    $hash->{NUMBER_OF_ERROR_3} = $hash->{NUMBER_OF_ERROR_3} + 1;
    if (AttrVal($name, "enableDebugReadings", undef))
    {
      readingsSingleUpdate($hash, 'debugNumError3', $hash->{NUMBER_OF_ERROR_3}, 1);
    }

    Log3 $name, 3, "SolarEdgeAPI ($name) - error (3) in http response, code: ".$param->{code};

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

    # TODO Remove this. Do error reporting via Log3 and debug readings. (INCOMPATIBLE CHANGE)
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, 'JSON Error', $@);
    readingsBulkUpdate($hash, 'state', 'JSON error');
    readingsEndUpdate($hash,1);
    
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
    $readings = SolarEdgeAPI_ReadingsProcessing_Overview($hash, $decodedJsonData);
  } 
  else 
  {    
    Log3 $name, 3, "SolarEdgeAPI ($name) - unknown type of response: $path";

    # TODO Remove this. Do error reporting via Log3. (INCOMPATIBLE CHANGE)
    $readings = $decodedJsonData;
  }

  SolarEdgeAPI_UpdateReadings($hash, $path, $readings);
}

sub SolarEdgeAPI_ReadingsProcessing_Aggregates($$)
{  
  my ($hash, $decodedJsonData) = @_;
  my $name = $hash->{NAME};

  my %readings;
    
  if (ref($decodedJsonData) eq "HASH")
  {
    my $data = $decodedJsonData->{'energyDetails'};
    $readings{'unit'} = $data->{'unit'} || "Error Reading Response";		
    $readings{'timeUnit'} = $data->{'timeUnit'} || "Error Reading Response";
    		
    $data = $decodedJsonData->{'energyDetails'}->{'meters'};
    my $meter_type = "";
    my $meter_cum = 0;
    my $meter_val = 0;
    foreach my $meter (@{$decodedJsonData->{'energyDetails'}->{'meters'}}) 
    {
      # meters
      $meter_type = $meter->{'type'};
      $meter_cum = 0;
      $meter_val = 0;
      foreach my $meterTelemetry (@{$meter->{'values'}})
      {
        my $v = $meterTelemetry->{'value'};
        if (defined $v)
        {
          $meter_cum = $meter_cum + $v;
          $meter_val = $v;
        }
      }
      $readings{$meter_type."-recent15min"} = $meter_val;
      $readings{$meter_type."-cumToday"} = $meter_cum;
    }
  } 
  else 
  {
    Log3 $name, 3, "SolarEdgeAPI ($name) - aggregates response is not a hash";
    
    # TODO Remove this. Do error reporting via Log3. (INCOMPATIBLE CHANGE)
    $readings{'error'} = 'aggregates response is not a Hash';
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
    
    # TODO Remove this. Do error reporting via Log3. (INCOMPATIBLE CHANGE)
    $readings{'error'} = 'API currentPowerFlow is not supported by site.';
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
    $readings{'grid_status'} = $data->{'GRID'}->{"status"} || "Error Reading Response"; # TODO rethink error reporting via readings (INCOMPATIBLE CHANGE)	
    $readings{'grid_power'} = (($load2grid > 0) ? "-" : "").$data->{'GRID'}->{"currentPower"};

    # LOAD
    $readings{'load_status'} = $data->{'LOAD'}->{"status"} || "Error Reading Response";	
    $readings{'load_power'} = $data->{'LOAD'}->{"currentPower"};		

    # PV
    $readings{'pv_status'} = $data->{'PV'}->{"status"} || "Error Reading Response";	
    $readings{'pv_power'} = $data->{'PV'}->{"currentPower"};		

    # Storage
    $readings{'storage_status'} = $data->{'STORAGE'}->{"status"} || "No storage found";
    if ($readings{'storage_status'} ne "No storage found")
    {
      $readings{'storage_power'} = (($storage2load > 0) ? "-" : "").$data->{'STORAGE'}->{"currentPower"};
      $readings{'storage_level'} = $data->{'STORAGE'}->{"chargeLevel"} || "Error Reading Response";		
      $readings{'storage_critical'} = $data->{'STORAGE'}->{"critical"};
    }
  }
    
  return \%readings;
}

sub SolarEdgeAPI_ReadingsProcessing_Overview($$)
{
  my ($hash, $decodedJsonData) = @_;
  my $name = $hash->{NAME};
    
  my %readings;
  my $data = $decodedJsonData->{'overview'};
    
  $readings{'power'} = $data->{'currentPower'}->{"power"};            
  
  # TODO generate more readings from the overview API. Some readings might only be relevant once per day.
  
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
  
  # TODO Remove this. (INCOMPATIBLE CHANGE)
  readingsBulkUpdateIfChanged($hash, 'actionQueue', scalar(@{$hash->{actionQueue}}).' entries in the Queue');
  readingsBulkUpdateIfChanged($hash, 'state', ((defined($hash->{actionQueue}) and (scalar(@{$hash->{actionQueue}}) == 0)) ? 'ready' : 'fetch data - '.scalar(@{$hash->{actionQueue}}).' paths in actionQueue'));

  readingsEndUpdate($hash, 1);
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
  Note: Features marked as "depricated" or "debug only" may change or disappear in future versions.<br>
  <br>

  <a name="SolarEdgeAPI_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; SolarEdgeAPI &lt;API Key&gt; &lt;Site ID&gt; [&lt;interval&gt;|auto]</code><br>
    The &lt;API Key&gt; and the &lt;Site ID&gt can be retrieved from the SolarEdge<br>
    Monitoring Portal. The &lt;API Key&gt; has to be enabled in the "Admin" Secion<br>
    of the web portal.<br>
    The &lt;interval&gt; parameter is optional. If a value is given it replaces the default value for attribute<br>
    interval, see below. This parameter is depricated.<br>
  </ul>
  <br>
    
  <a name="SolarEdgeAPI_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>actionQueue     - information about the entries in the action queue (for debug only)</li>
    <li>status-*        - readings generated from currentPowerFlow API response. This API is not supported by all sites.</li>
    <li>aggregates-*    - cumulative data of the energyDetails response</li>
    <li>overview-*      - readings generated from overview API response</li>    
    <li>debug*          - debug data about successful and failing http requests (for debug only)</li>    
  </ul>
  <br>
    
  <a name="SolarEdgeAPI_Get"></a>
  <b>Get</b>
  <ul>
    <li>status - fetch data from currentPowerFlow API (for debug only)</li>
    <li>aggregates - fetch data from energyDetails API (for debug only)</li>
    <li>overview - fetch data from overview API (for debug only)</li>
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
    <li>interval - interval of http requests during day time (default: 300 (seconds))</li>
    <li>intervalAtNightTime - interval of http requests during night time (default: 1200 (seconds))</li>
    <li>dayTimeStartHour - start of daytime, default 7 (= 7:00am)</li>
    <li>nightTimeStartHour - start of night time, default 22 (= 10:00pm)</li>
    <li>enableStatusReadings Enable the status-* readings. Default: 1</li>
    <li>enableAggregatesReadings Enable the aggregates-* readings. Default: 1</li>
    <li>enableOverviewReadings Enable the overview-* readings. Default: 0 (for backward compatiblity)</li> 
    <li>enableDebugReadings Enable the debug* readings. These debug readings do not cause additional http requests. Default: 0</li>
  </ul>
  <br>
  
</ul>

=end html

=cut
