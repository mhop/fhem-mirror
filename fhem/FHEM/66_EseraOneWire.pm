################################################################################
#
# $Id$
#
# 66_EseraOneWire.pm
#
# Copyright (C) 2018  pizmus
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
################################################################################
#
# This FHEM module controls the Esera "1-wire Controller 1" and the
# "1-wire Controller 2" with LAN interface.
# It works together with the following client modules:
#  66_EseraAnalogInOut
#  66_EseraDigitalInOut
#  66_EseraMulti
#  66_EseraTemp
#  66_EseraCount
#  66_EseraIButton
#  66_EseraShutter
#
# For Esera 1-wire controllers with serial/USB interface please check the
# commandref.
#
################################################################################
#
# Data stored in device hash:
# - Various information read from the controller e.g. during EseraOneWire_refreshControllerInfo().
#   In most cases the hash key is named like the controller command.
# - Hashes storing information per 1-wire device reported by the controller:
#   - ESERA ID of the device (index into a list of devices kept by the controller)
#   - device type
#   - status
#   The key used with these hashes is always a 1-wire ID.
#
################################################################################
#
# Known issues and potential enhancements:
#
# - Let the user control certain settings, like DATATIME, SEACHTIME and wait time
#   used after posted writes, e.g. as parameters to the define command.
# - Implement support for all devices listed in the Programmierhandbuch.
#
################################################################################

package main;

use HttpUtils;
use strict;
use warnings;
use vars qw {%attr %defs};
use DevIo;

sub
EseraOneWire_Initialize($)
{
  my ($hash) = @_;
  $hash->{ReadFn} = "EseraOneWire_Read";
  $hash->{WriteFn} = "EseraOneWire_Write";
  $hash->{ReadyFn} = "EseraOneWire_Ready";
  $hash->{DefFn} = "EseraOneWire_Define";
  $hash->{UndefFn} = "EseraOneWire_Undef";
  $hash->{DeleteFn} = "EseraOneWire_Delete";
  $hash->{GetFn} = "EseraOneWire_Get";
  $hash->{SetFn} = "EseraOneWire_Set";
  $hash->{AttrFn} = "EseraOneWire_Attr";
  $hash->{AttrList} = $readingFnAttributes;
  $hash->{AttrList} = "pollTime ".
                      "dataTime ".
                      $readingFnAttributes;


  $hash->{Clients} = ":EseraDigitalInOut:EseraTemp:EseraMulti:EseraAnalogInOut:EseraIButton:EseraCount:EseraShutter:";
  $hash->{MatchList} = { "1:EseraDigitalInOut" => "^DS2408|^11220|^11233|^11228|^11229|^11216|^SYS1|^SYS2",
                         "2:EseraTemp" => "^DS1820",
                         "3:EseraMulti" => "^DS2438|^11121|^11132|^11133|^11134|^11135",
                         "4:EseraAnalogInOut" => "^SYS3",
                         "5:EseraIButton" => "^DS2401",
			 "6:EseraCount" => "^DS2423",
                         "7:EseraShutter" => "^11231|^11209",
                         "8:EseraDimmer" => "^11221|^11222"};
}

sub
EseraOneWire_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t]+", $def);

  my $name = $a[0];

  # $a[1] always equals the module name

  # first argument is the hostname or IP address of the device (e.g. "192.168.1.120")
  # or the serial port (e.g. /dev/ttyUSB0)
  my $dev = $a[2];

  return "no device given" unless($dev);

  my $isSerialDevice = ($dev =~ m/^COM|^\/dev\//);
  if (not $isSerialDevice)
  {
    # add the default port
    $dev .= ':5000' if (not $dev =~ m/:\d+$/);
    Log3 $name, 3, "EseraOneWire ($name) - define: $dev (TCP/IP)";
  }
  else
  {
    Log3 $name, 3, "EseraOneWire ($name) - define: $dev (serial)";
  }

  $hash->{DeviceName} = $dev;

  $hash->{KAL_PERIOD} = 60;
  $hash->{RECOMMENDED_FW} = 12027;
  $hash->{DEFAULT_POLLTIME} = 5;
  $hash->{DEFAULT_DATATIME} = 10;

  # close connection if maybe open (on definition modify)
  DevIo_CloseDev($hash) if(DevIo_IsOpen($hash));

  # open connection with custom init and error callback function (non-blocking connection establishment)
  DevIo_OpenDev($hash, 0, "EseraOneWire_Init", "EseraOneWire_Callback");

  EseraOneWire_SetStatus($hash, "defined");

  return undef;
}

sub
EseraOneWire_Undef($$)
{
  my ($hash, $name) = @_;

  # close the connection
  DevIo_CloseDev($hash);

  RemoveInternalTimer($hash);

  return undef;
}

sub
EseraOneWire_Delete($$)
{
  my ($hash, $name) = @_;
  #delete all dev-spec temp-files
  unlink($attr{global}{modpath}. "/FHEM/FhemUtils/$name.tmp");
  return undef;
}

sub
EseraOneWire_Ready($)
{
  my ($hash) = @_;

  # try to reopen the connection in case the connection is lost
  return DevIo_OpenDev($hash, 1, "EseraOneWire_Init", "EseraOneWire_Callback");
}

sub
EseraOneWire_Attr($$$$)
{
  my ($cmd, $name, $attrName, $attrValue) = @_;
  # $cmd  -  "del" or "set"
  # $name - device name
  # $attrName/$attrValue
  my $hash = $defs{$name};

  if ($attrName eq "pollTime")
  {
    if ($cmd eq "set")
    {
      if (not ($attrValue =~ m/^[0-9]+$/))
      {
        my $message = "illegal value for pollTime, not an integer number";
        Log3 $name, 3, "EseraOneWire ($name) - ".$message;
        return $message;
      }

      if (($attrValue < 1) or ($attrValue > 240))
      {
        my $message = "illegal value for pollTime, out of range";
        Log3 $name, 3, "EseraOneWire ($name) - ".$message;
        return $message;
      }

      if ($attrValue >= AttrVal($name, "dataTime", $hash->{DEFAULT_DATATIME}))
      {
        my $message = "illegal value for pollTime, compared to dataTime";
        Log3 $name, 3, "EseraOneWire ($name) - ".$message;
        return $message;
      }

      Log3 $name, 3, "EseraOneWire ($name) - attribute pollTime = $attrValue, re-initializing the controller";
      InternalTimer(gettimeofday()+1, "EseraOneWire_baseSettings", $hash);
    }
    if ($cmd eq "del")
    {
      Log3 $name, 3, "EseraOneWire ($name) - attribute pollTime deleted, re-initializing the controller";
      InternalTimer(gettimeofday()+1, "EseraOneWire_baseSettings", $hash);
    }
  }

  if ($attrName eq "dataTime")
  {
    if ($cmd eq "set")
    {
      if (not ($attrValue =~ m/^[0-9]+$/))
      {
        my $message = "illegal value for dataTime, not an integer number";
        Log3 $name, 3, "EseraOneWire ($name) - ".$message;
        return $message;
      }
      if (($attrValue < 10) or ($attrValue > 240))
      {
        my $message = "illegal value for dataTime, out of range";
        Log3 $name, 3, "EseraOneWire ($name) - ".$message;
        return $message;
      }
      if ($attrValue <= AttrVal($name, "pollTime", $hash->{DEFAULT_POLLTIME}))
      {
        my $message = "illegal value for dataTime, compared to pollTime";
        Log3 $name, 3, "EseraOneWire ($name) - ".$message;
        return $message;
      }

      Log3 $name, 3, "EseraOneWire ($name) - attribute dataTime = $attrValue, re-initializing the controller";

      InternalTimer(gettimeofday()+1, "EseraOneWire_baseSettings", $hash);
    }
    if ($cmd eq "del")
    {
      Log3 $name, 3, "EseraOneWire ($name) - attribute dataTime deleted, re-initializing the controller";
      InternalTimer(gettimeofday()+1, "EseraOneWire_baseSettings", $hash);
    }
  }

  return undef;
}

sub
EseraOneWire_Init($)
{
  my ($hash) = @_;
  EseraOneWire_SetStatus($hash, "connected");
  EseraOneWire_baseSettings($hash);
  return undef;
}

sub
EseraOneWire_Callback($$)
{
  my ($hash, $error) = @_;
  my $name = $hash->{NAME};

  if ($error)
  {
    EseraOneWire_SetStatus($hash, "disconnected");
    Log3 $name, 1, "EseraOneWire ($name) - error while connecting: >>".$error."<<";
  }

  return undef;
}

sub
EseraOneWire_initTimeoutHandler($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 3, "EseraOneWire ($name) - info: initialization timeout detected, trying again";

  EseraOneWire_baseSettings($hash);
}

################################################################################
# controller info, settings and status
################################################################################

sub
EseraOneWire_baseSettings($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if (not DevIo_IsOpen($hash))
  {
    Log3 $name, 1, "EseraOneWire ($name) - initialization aborted due to missing connection";
    return undef;
  }

  EseraOneWire_SetStatus($hash, "initializing");
  $hash->{".READ_PENDING"} = 0;

  # start a timeout counter for initialization
  RemoveInternalTimer($hash, "EseraOneWire_initTimeoutHandler");
  InternalTimer(gettimeofday()+60, "EseraOneWire_initTimeoutHandler", $hash);

  # clear task list before reset
  undef $hash->{TASK_LIST} unless (!defined $hash->{TASK_LIST});

  # send reset command (posted)
  EseraOneWire_taskListAddPostedWrite($hash, "set,sys,rst,1", 5.0);

  # Sending this request as a dummy, because the first access seems to get an 1_ERR always, followed
  # by the correct response. Wait time of 3s between "set,sys,rst,1" and "set,sys,dataprint,1" does not help.
  EseraOneWire_taskListAddSync($hash, "set,sys,dataprint,1", "1_DATAPRINT", \&EseraOneWire_query_response_handler);

  # commands below here are expected to receive a "good" response

  # ensure factory default settings
  # This command does not clear the list of devices, only the settings. If you want to clear the list
  # as well use "set,sys,facreset,1" with expected response "1_FACRESET|1".
  EseraOneWire_taskListAddSimple($hash, "set,sys,loaddefault,1", "1_LOADDEFAULT", \&EseraOneWire_query_response_handler);

  # wait some time, 0.2s works -> adding some safety buffer
  EseraOneWire_taskListAddPostedWrite($hash, "", 0.4);

  # events must contain the 1-wire ID, not the ESERA ID
  EseraOneWire_taskListAddSimple($hash, "set,owb,owdid,1", "1_OWDID", \&EseraOneWire_query_response_handler);

  # get iButton events for connect and disconnect
  EseraOneWire_taskListAddSimple($hash, "set,key,data,2", "1_DATA", \&EseraOneWire_query_response_handler);

  # Due to a bug in FW version 12027 there is no response to this command if the license is not available.
  # Therefore, do a posted write only.
  # EseraOneWire_taskListAddSimple($hash, "set,key,fast,1", "1_FAST", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddPostedWrite($hash, "set,key,fast,1", 1.0);

  # load list of devices so that iButton devices which are stored in the controller are handled quickly
  EseraOneWire_taskListAddSimple($hash, "set,owb,load", "1_LOAD", \&EseraOneWire_query_response_handler);

  # more explicit default settings...
  EseraOneWire_taskListAddSimple($hash, "set,sys,datatime,10", "1_DATATIME", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "set,sys,kalsend,1", "1_KALSEND", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "set,sys,kalsendtime,".$hash->{KAL_PERIOD}, "1_KALSENDTIME", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "set,sys,kalrec,0", "1_KALREC", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "set,owb,search,2", "1_SEARCH", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "set,owb,searchtime,30", "1_SEARCHTIME", \&EseraOneWire_query_response_handler);

  # settings from attributes
  my $dataTime = AttrVal($name, "dataTime", $hash->{DEFAULT_DATATIME});
  EseraOneWire_taskListAddSimple($hash, "set,sys,datatime,$dataTime", "1_DATATIME", \&EseraOneWire_query_response_handler);
  my $pollTime = AttrVal($name, "pollTime", $hash->{DEFAULT_POLLTIME});
  EseraOneWire_taskListAddSimple($hash, "set,owb,polltime,$pollTime", "1_POLLTIME", \&EseraOneWire_query_response_handler);

  # wait some time to give the controller time to detect the devices
  EseraOneWire_taskListAddPostedWrite($hash, "", 4);

  # read settings, ... from the controller and store the info in the hash
  EseraOneWire_refreshControllerInfo($hash);

  # wait some more time before readings can be forwarded to clients
  EseraOneWire_taskListAddPostedWrite($hash, "", 2);

  # This must be the last one.
  EseraOneWire_taskListAddSimple($hash, "get,sys,run", "1_RUN", \&EseraOneWire_init_complete_handler);
}

sub
EseraOneWire_removeDeviceTypeFromList($$)
{
  my ($hash, $oneWireId) = @_;
  my $name = $hash->{NAME};

  if (defined $hash->{DEVICE_TYPES})
  {
    # list is not empty; get it and delete entry
    my $deviceTypesRef = $hash->{DEVICE_TYPES};
    my %deviceTypes = %$deviceTypesRef;
    if (defined $deviceTypes{$oneWireId})
    {
      delete($deviceTypes{$oneWireId});
    }
    $hash->{DEVICE_TYPES} = \%deviceTypes;
  }
}

# incremental update of device list
sub
EseraOneWire_updateDeviceList($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  # do nothing if a refresh is already in process
  return undef if ((defined $hash->{".READ_PENDING"}) && ($hash->{".READ_PENDING"} == 1));

  Log3 $name, 4, "EseraOneWire ($name) - info: reading device list from controller";

  # do not clear old device information

  # Enqueue a query to retrieve the device list.
  # The LST query gets multiple responses. We read all devices, not just the currently active ones,
  # so that iButton devices which are known to the controller can be handled.
  # Read the list with a posted write. The wait time has to chosen so that all LST responses are received
  # before the next command is sent. LST responses are handled generically in the EseraOneWire_Read().
  EseraOneWire_taskListAddPostedWrite($hash, "get,owb,listall", 2);

  # This must be the last one.
  EseraOneWire_taskListAddSimple($hash, "get,sys,run", "1_RUN", \&EseraOneWire_read_complete_handler);
  $hash->{".READ_PENDING"} = 1;

  return undef;
}

sub
EseraOneWire_refreshControllerInfo($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  # do nothing if a refresh is already in process
  return undef if ((defined $hash->{".READ_PENDING"}) && ($hash->{".READ_PENDING"} == 1));

  # clear old information
  undef $hash->{ESERA_IDS} unless (!defined $hash->{ESERA_IDS});
  undef $hash->{DEVICE_TYPES} unless (!defined $hash->{DEVICE_TYPES});

  # queue queries to retrieve updated information

  # The LST query gets multiple responses. We read all devices, not just the currently active ones,
  # so that iButton devices which are known to the controller can be handled.
  # Read the list with a posted write. The wait time has to chosen so that all LST responses are received
  # before the next command is sent. LST responses are handled generically in the EseraOneWire_Read().
  EseraOneWire_taskListAddPostedWrite($hash, "get,owb,listall", 2);

  EseraOneWire_taskListAddSimple($hash, "get,sys,fw", "1_FW", \&EseraOneWire_fw_handler);
  EseraOneWire_taskListAddSimple($hash, "get,sys,hw", "1_HW", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "get,sys,serial", "1_SERIAL", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "get,sys,id", "1_ID", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "get,sys,dom", "1_DOM", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "get,sys,run", "1_RUN", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "get,sys,contno", "1_CONTNO", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "get,sys,kalrec", "1_KALREC", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "get,sys,kalrectime", "1_KALRECTIME", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "get,sys,dataprint", "1_DATAPRINT", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "get,sys,datatime", "1_DATATIME", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "get,sys,kalsend", "1_KALSEND", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "get,sys,kalsendtime", "1_KALSENDTIME", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "get,owb,owdid", "1_OWDID", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "get,owb,owdidformat", "1_OWDIDFORMAT", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "get,owb,search", "1_SEARCH", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "get,owb,searchtime", "1_SEARCHTIME", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "get,owb,polltime", "1_POLLTIME", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "get,owd,ds2408inv", "1_DS2408INV", \&EseraOneWire_query_response_handler);

  EseraOneWire_taskListAddSimple($hash, "get,key,data", "1_DATA", \&EseraOneWire_query_response_handler);
  # Due to a bug in FW version 12027 this command does not get a response. Skip it for now.
  # EseraOneWire_taskListAddSimple($hash, "get,key,fast", "1_FAST", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "get,sys,liz,2", "1_LIZ", \&EseraOneWire_LIZ2_handler);

  # TODO This does not work. The command is documented like this but it causes an
  # ERR response. What does the last parameter mean anyway? Ask Esera.
  # 2018.09.23 15:36:04 1: EseraOneWire (owc) - COMM sending: get,sys,owdid,0
  # 2018.09.23 15:36:05 1: EseraOneWire (owc) - COMM Read: 1_INF|18:17:21
  # 2018.09.23 15:36:05 1: EseraOneWire (owc) - COMM Read: 1_ERR|3
  # 2018.09.23 15:36:05 1: EseraOneWire (owc) - COMM error response received, expected: 1_OWDID
  # 2018.09.23 15:36:05 1: EseraOneWire (owc) - error response, command: get,sys,owdid,0 , response: 1_ERR|3 , ignoring the response
  #EseraOneWire_taskListAddSimple($hash, "get,sys,owdid,0", "1_OWDID", \&EseraOneWire_query_response_handler);

  # TODO This does not work as documented. It returns an ERR message. Ask Esera.
  # 2018.09.23 15:36:05 1: EseraOneWire (owc) - COMM sending: get,sys,echo
  # 2018.09.23 15:36:05 1: EseraOneWire (owc) - COMM Read: 1_INF|18:17:21
  # 2018.09.23 15:36:05 1: EseraOneWire (owc) - COMM Read: 1_ERR|3
  # 2018.09.23 15:36:05 1: EseraOneWire (owc) - COMM error response received, expected: 1_ECHO
  #2018.09.23 15:36:05 1: EseraOneWire (owc) - error response, command: get,sys,echo , response: 1_ERR|3 , ignoring the response
  #EseraOneWire_taskListAddSimple($hash, "get,sys,echo", "1_ECHO", \&EseraOneWire_query_response_handler);

  # This must be the last one.
  EseraOneWire_taskListAddSimple($hash, "get,sys,run", "1_RUN", \&EseraOneWire_read_complete_handler);
  $hash->{".READ_PENDING"} = 1;

  return undef;
}

sub
EseraOneWire_refreshStatus($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  # get access to list of active devices
  my $eseraIdsRef = $hash->{ESERA_IDS};
  if (!defined $eseraIdsRef)
  {
    Log3 $name, 1, "EseraOneWire ($name) - no devices known";
    return undef;
  }

  # clear old information
  undef $hash->{DEVICE_STATUS} unless (!defined $hash->{DEVICE_STATUS});
  undef $hash->{DEVICE_ERRORS} unless (!defined $hash->{DEVICE_ERRORS});

  # iterate over known devices
  my %eseraIds = %$eseraIdsRef;
  my @keys = keys %eseraIds;
  foreach (@keys)
  {
    my $eseraId = $eseraIds{$_};

    # query the status
    EseraOneWire_taskListAdd($hash, "get,owd,status,".$eseraId,
      "1_OWD_", \&EseraOneWire_DEVICE_STATUS_handler, "ERR", \&EseraOneWire_error_handler, \&EseraOneWire_unexpected_handler, 0);

    # sample response: "1_ERROWD2|0"
    EseraOneWire_taskListAddSimple($hash, "get,owb,errowd,".$eseraId,
      "1_ERROWD", \&EseraOneWire_ERROWD_handler);
  }
}

sub
EseraOneWire_eseraIdToOneWireId($$)
{
  my ($hash, $eseraId) = @_;
  my $name = $hash->{NAME};

  my $eseraIdsRef = $hash->{ESERA_IDS};
  if (defined $eseraIdsRef)
  {
    my %eseraIds = %$eseraIdsRef;
    my @keys = keys %eseraIds;
    foreach (@keys)
    {
      if ($eseraIds{$_} eq $eseraId)
      {
        return $_;
      }
    }
  }
  return undef;
}

sub
EseraOneWire_oneWireIdToEseraId($$)
{
  my ($hash, $oneWireId) = @_;
  my $name = $hash->{NAME};
  my $eseraIdsRef = $hash->{ESERA_IDS};
  if (defined $eseraIdsRef)
  {
    my %eseraIds = %$eseraIdsRef;
    my $eseraId = $eseraIds{$oneWireId};
    if (defined $eseraId)
    {
      return $eseraId;
    }
    else
    {
      Log3 $name, 4, "EseraOneWire ($name) - EseraOneWire_oneWireIdToEseraId, not found, ".$oneWireId;
    }
  }
  else
  {
    Log3 $name, 4, "EseraOneWire ($name) - EseraOneWire_oneWireIdToEseraId, hash does not exist";
  }
  return undef;
}

################################################################################
# Set command
################################################################################

sub
EseraOneWire_Set($$)
{
  my ($hash, @parameters) = @_;
  my $name = $parameters[0];
  my $what = lc($parameters[1]);

  if ($what eq "raw")
  {
    if (scalar(@parameters) != 3)
    {
      my $message = "error: unexpected number of parameters (".scalar(@parameters).") to raw";
      Log3 $name, 1, "EseraOneWire ($name) - ".$message;
      return $message;
    }
    my $rawCommand = lc($parameters[2]);
    my $message = "command to ESERA controller: ".$rawCommand;
    Log3 $name, 4, "EseraOneWire ($name) - ".$message;

    $hash->{RAW_COMMAND} = $rawCommand;
    $hash->{RAW_RESPONSE} = ".";

    EseraOneWire_taskListAdd($hash, $rawCommand,
      "1_", \&EseraOneWire_raw_command_handler, "ZZZ", \&EseraOneWire_error_handler,
      \&EseraOneWire_unexpected_handler, 0.5);

    return undef;
  }
  elsif ($what eq "refresh")
  {
    EseraOneWire_refreshStatus($hash);
    EseraOneWire_refreshControllerInfo($hash);
  }
  elsif ($what eq "clearlist")
  {
    EseraOneWire_taskListAddSimple($hash, "set,owb,delmem", "1_DELMEM", \&EseraOneWire_query_response_handler);
  }
  elsif ($what eq "savelist")
  {
    EseraOneWire_taskListAddSimple($hash, "set,owb,save", "1_SAVE", \&EseraOneWire_query_response_handler);
  }
  elsif ($what eq "reset")
  {
    if (scalar(@parameters) != 3)
    {
      my $message = "error: unexpected number of parameters (".scalar(@parameters).") to reset";
      Log3 $name, 1, "EseraOneWire ($name) - ".$message;
      return $message;
    }
    my $resetSpecifier = lc($parameters[2]);
    my $message;
    if ($resetSpecifier eq "tasks")
    {
      undef $hash->{TASK_LIST} unless (!defined $hash->{TASK_LIST});
    }
    elsif ($resetSpecifier eq "controller")
    {
      EseraOneWire_baseSettings($hash);
      $message = "reset controller";
      Log3 $name, 4, "EseraOneWire ($name) - ".$message;
    }
    else
    {
      $message = "error: unknown reset specifier ".$resetSpecifier;
      Log3 $name, 1, "EseraOneWire ($name) - ".$message;
    }
    return undef;
  }
  elsif ($what eq "close")
  {
    # close connection if open
    if (DevIo_IsOpen($hash))
    {
      DevIo_CloseDev($hash);

      RemoveInternalTimer($hash, "EseraOneWire_initTimeoutHandler");
      RemoveInternalTimer($hash, "EseraOneWire_KalTimeoutHandler");

      EseraOneWire_SetStatus($hash, "disconnected");
      if (DevIo_IsOpen($hash))
      {
        Log3 $name, 1, "EseraOneWire ($name) - set close: failed";
      }
      else
      {
        Log3 $name, 3, "EseraOneWire ($name) - set close: success";
      }
    }
    else
    {
      Log3 $name, 3, "EseraOneWire ($name) - set close: is not open";
    }
  }
  elsif ($what eq "open")
  {
    Log3 $name, 3, "EseraOneWire ($name) - set open";
    # open connection with custom init and error callback function (non-blocking connection establishment)
    DevIo_OpenDev($hash, 0, "EseraOneWire_Init", "EseraOneWire_Callback") if(!DevIo_IsOpen($hash));
  }
  elsif ($what eq "?")
  {
    my $message = "unknown argument $what, choose one of clearlist:noArg savelist:noArg refresh:noArg reset:controller,tasks raw close:noArg open:noArg";
    return $message;
  }
  else
  {
    my $message = "unknown argument $what, choose one of clearlist savelist reset refresh raw close open";
    Log3 $name, 1, "EseraOneWire ($name) - ".$message;
    return $message;
  }
  return undef;
}

################################################################################
# Get command
################################################################################

sub
EseraOneWire_getDevices($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $eseraIdsRef = $hash->{ESERA_IDS};
  my $deviceTypesRef = $hash->{DEVICE_TYPES};
  my $list = "";
  my $isEmpty = 1;
  if (defined $eseraIdsRef && defined $deviceTypesRef)
  {
    my %eseraIds = %$eseraIdsRef;
    my %deviceTypes = %$deviceTypesRef;
    my @keys = keys %eseraIds;
    my $updateNeeded = 0;
    foreach (@keys)
    {
      $isEmpty = 0;
      if (defined $deviceTypes{$_})
      {
        $list .= $_.",".$eseraIds{$_}.",".$deviceTypes{$_}.";\n";
      }
      else
      {
        $list .= $_.",".$eseraIds{$_}.",pending;\n";
	$updateNeeded = 1;
      }
    }
    if ($updateNeeded)
    {
      EseraOneWire_updateDeviceList($hash);
    }
  }

  if ($isEmpty)
  {
    $list .= "device list is empty\n";
  }

  return $list;
}

sub
EseraOneWire_getInfo($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $list = "";

  my $fwVersion = $hash->{".FW"};
  my $hwVersion = $hash->{".HW"};
  my $serialNumber = $hash->{".SERIAL"};
  my $productNumber = $hash->{".ID"};
  my $dom = $hash->{".DOM"};

  $fwVersion = "UNKNOWN" if (!defined $fwVersion);
  $hwVersion = "UNKNOWN" if (!defined $hwVersion);
  $serialNumber = "UNKNOWN" if (!defined $serialNumber);
  $productNumber = "UNKNOWN" if (!defined $productNumber);
  $dom = "UNKNOWN" if (!defined $dom);

  $list .= "FW version: ".$fwVersion."\n";
  $list .= "HW version: ".$hwVersion."\n";
  $list .= "serial number: ".$serialNumber."\n";
  $list .= "ESERA product number: ".$productNumber."\n";
  $list .= "date of manufacturing: ".$dom."\n";
  return $list;
}

sub
EseraOneWire_getSettings($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $list = "";

  my $run = $hash->{".RUN"};
  my $contno = $hash->{".CONTNO"};
  my $kalrec = $hash->{".KALREC"};
  my $kalrectime = $hash->{".KALRECTIME"};
  my $kalsend = $hash->{".KALSEND"};
  my $kalsendtime = $hash->{".KALSENDTIME"};
  my $dataprint = $hash->{".DATAPRINT"};
  my $datatime = $hash->{".DATATIME"};
  my $useOwdid = $hash->{".OWDID"};
  my $owdidFormat = $hash->{".OWDIDFORMAT"};
  my $searchMode = $hash->{".SEARCH"};
  my $searchTime = $hash->{".SEARCHTIME"};
  my $polltime = $hash->{".POLLTIME"};
  my $ds2408inv = $hash->{".DS2408INV"};
  my $data = $hash->{".DATA"};
  my $fast = $hash->{".FAST"};

  my $license = $hash->{".LIZ2"};

  $run = "UNKNOWN" if (!defined $run);
  $contno = "UNKNOWN" if (!defined $contno);
  $kalrec = "UNKNOWN" if (!defined $kalrec);
  $kalrectime = "UNKNOWN" if (!defined $kalrectime);
  $kalsend = "UNKNOWN" if (!defined $kalsend);
  $kalsendtime = "UNKNOWN" if (!defined $kalsendtime);
  $dataprint = "UNKNOWN" if (!defined $dataprint);
  $datatime = "UNKNOWN" if (!defined $datatime);
  $useOwdid = "UNKNOWN" if (!defined $useOwdid);
  $owdidFormat = "UNKNOWN" if (!defined $owdidFormat);
  $searchMode = "UNKNOWN" if (!defined $searchMode);
  $searchTime = "UNKNOWN" if (!defined $searchTime);
  $polltime = "UNKNOWN" if (!defined $polltime);
  $ds2408inv = "UNKNOWN" if (!defined $ds2408inv);
  $data = "UNKNOWN" if (!defined $data);
  $fast = "UNKNOWN" if (!defined $fast);
  $license = "UNKNOWN" if (!defined $license);

  $list .= "RUN: ".$run." (1=controller sending to FHEM)\n";
  $list .= "CONTNO: ".$contno." (ESERA controller number)\n";
  $list .= "KALREC: ".$kalrec." (1=keep-alive signal expected by controller)\n";
  $list .= "KALRECTIME: ".$kalrectime." (time period in seconds used for expected keep-alive messages)\n";
  $list .= "KALSEND: ".$kalsend." (1=controller sending keep-alive messages)\n";
  $list .= "KALSENDTIME: ".$kalsendtime." (time period in seconds used for sending keep-alive messages)\n";
  $list .= "DATAPRINT: ".$dataprint." (0=list responses are returned in a single line)\n";
  $list .= "DATATIME: ".$datatime." (time period used for data delivery to FHEM)\n";
  $list .= "OWDID: ".$useOwdid." (1=return readings with 1-wire ID instead of Esera ID)\n";
  $list .= "OWDIDFORMAT: ".$owdidFormat." (selects format of 1-wire ID)\n";
  $list .= "SEARCH: ".$searchMode." (2=cyclic search for new devices)\n";
  $list .= "SEARCHTIME: ".$searchTime." (time period in seconds used to search for new devices)\n";
  $list .= "POLLTIME: ".$polltime." (time period in seconds used with periodic reads from devices)\n";
  $list .= "DS2408INV: ".$ds2408inv." (1=invert readings from DS2408 devices)\n";
  $list .= "DATA: ".$data." (2=get events for iButton connect and disconnect)\n";
  $list .= "FAST: ".$fast." (1=fast polling is enabled, requires special license)\n";
  $list .= "LIZ2: ".$license." (1=iButton fast mode license found)\n";

  return $list;
}

sub
EseraOneWire_getStatus($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  # get access to stored device information
  my $eseraIdsRef = $hash->{ESERA_IDS};
  my $deviceTypesRef = $hash->{DEVICE_TYPES};
  if (!defined $eseraIdsRef || !defined $deviceTypesRef)
  {
    EseraOneWire_refreshControllerInfo($hash);
    my $message = "No device information found. Refreshing list. Please try again.";
    Log3 $name, 3, "EseraOneWire ($name) - ".$message;
    return $message;
  }

  # get access to stored device status
  my $deviceStatusRef = $hash->{DEVICE_STATUS};
  if (!defined $deviceStatusRef)
  {
    EseraOneWire_refreshStatus($hash);
    my $message = "No status information found. Triggering refresh. Please try again.";
    Log3 $name, 3, "EseraOneWire ($name) - ".$message;
    return $message;
  }

  # get access to stored device errors
  my $deviceErrorsRef = $hash->{DEVICE_ERRORS};
  if (!defined $deviceErrorsRef)
  {
    EseraOneWire_refreshStatus($hash);
    my $message = "No error information found. Triggering refresh. Please try again.";
    Log3 $name, 3, "EseraOneWire ($name) - ".$message;
    return $message;
  }

  # iterate over detected devices
  my $list = "";
  my %eseraIds = %$eseraIdsRef;
  my %deviceTypes = %$deviceTypesRef;
  my %deviceStatus = %$deviceStatusRef;
  my %deviceErrors = %$deviceErrorsRef;
  my @keys = keys %eseraIds;
  foreach (@keys)
  {
    if (defined $deviceTypes{$_})
    {
      $list .= $_.",".$eseraIds{$_}.",".$deviceTypes{$_}.",";
    }
    else
    {
      $list .= $_.",".$eseraIds{$_}.",pending,";
      EseraOneWire_updateDeviceList($hash);
    }

    my $status = $deviceStatus{$_};
    if (!defined $status)
    {
      $list .= "unknown";
    }
    else
    {
      $list .= $status;
    }
    $list .= ",".$deviceErrors{$_};
    $list .= ";\n";
  }

  # trigger next read of status info from controller
  EseraOneWire_refreshStatus($hash);

  return $list;
}

sub
EseraOneWire_Get($$)
{
  my ($hash, @parameters) = @_;
  my $name = $hash->{NAME};
  my $what = lc($parameters[1]);

  if ($what eq "devices")
  {
    return EseraOneWire_getDevices($hash);
  }
  elsif ($what eq "info")
  {
    return EseraOneWire_getInfo($hash);
  }
  elsif ($what eq "settings")
  {
    return EseraOneWire_getSettings($hash);
  }
  elsif ($what eq "status")
  {
    return EseraOneWire_getStatus($hash);
  }
  elsif ($what eq "?")
  {
    my $message = "unknown argument $what, choose one of devices:noArg info:noArg settings:noArg status:noArg";
    return $message;
  }

  my $message = "unknown argument $what, choose one of devices:noArg info:noArg settings:noArg status:noArg";
  Log3 $name, 3, "EseraOneWire ($name) - ".$message;
  return $message;
}

################################################################################
# Read command - process data coming from the device
################################################################################

sub
EseraOneWire_Read($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $data = DevIo_SimpleRead($hash);
  return if (!defined($data)); # connection lost

  my $buffer = $hash->{PARTIAL};

  $data =~ s/\r//g;

  # concat received data to $buffer
  $buffer .= $data;

  while ($buffer =~ m/\n/)
  {
    my $msg;

    # extract the complete message ($msg), everything else is assigned to $buffer
    ($msg, $buffer) = split("\n", $buffer, 2);

    # remove trailing whitespaces
    chomp $msg;

    Log3 $name, 4, "EseraOneWire ($name) - COMM Read: $msg";

    my $ascii = $msg;

    if ((length $ascii) == 0)
    {
      Log3 $name, 4, "EseraOneWire ($name) - COMM - error: empty response detected";
      next;
    }

    my @fields = split(/\|/, $ascii);
    my $type = $fields[0];

    if ($type =~ m/1_EVT/)
    {
      Log3 $name, 5, "EseraOneWire ($name) - EVT received";
    }
    elsif ($type =~ m/1_CSE/)
    {
      Log3 $name, 5, "EseraOneWire ($name) - CSE received";
    }
    elsif ($type =~ m/1_CSI/)
    {
      Log3 $name, 5, "EseraOneWire ($name) - CSI received";
    }
    elsif ($type =~ m/1_INF/)
    {
      Log3 $name, 5, "EseraOneWire ($name) - COMM - INF received";
    }
    elsif ($type =~ m/1_KAL$/)
    {
      EseraOneWire_processKalMessage($hash);
    }
    elsif ($type =~ m/^1_LST/)
    {
      Log3 $name, 4, "EseraOneWire ($name) - COMM - 1_LST received";
    }
    elsif ($type eq "LST")
    {
      EseraOneWire_LIST_handler($hash, $ascii);
    }
    elsif ($type =~ m/1_OWD(\d+)_(\d+)/)
    {
      if (EseraOneWire_IsReadyToAcceptHardwareReadings($hash))
      {
        Log3 $name, 4, "EseraOneWire ($name) - readings data from controller has incorrect format (1_OWD*_* instead of using the 1-wire ID)";
      }
    }
    elsif ($ascii =~ m/^1_([0-9A-F]+)_(\d+)/)
    {
      if (EseraOneWire_IsReadyToAcceptHardwareReadings($hash))
      {
        EseraOneWire_parseReading($hash, $ascii);
      }
      else
      {
        Log3 $name, 5, "EseraOneWire ($name) - readings ignored because controller is not initialized (1)";
      }
    }
    elsif ($ascii =~ m/^1_([0-9A-F]+)\|/)
    {
      if (EseraOneWire_IsReadyToAcceptHardwareReadings($hash))
      {
        EseraOneWire_parseReading($hash, $ascii);
      }
      else
      {
        Log3 $name, 5, "EseraOneWire ($name) - readings ignored because controller is not initialized (2)";
      }
    }
    elsif ($ascii =~ m/^1_OWD([0-9A-F]+)\|/)
    {
      if (EseraOneWire_IsReadyToAcceptHardwareReadings($hash))
      {
        EseraOneWire_parseReading($hash, $ascii);
      }
      else
      {
        Log3 $name, 5, "EseraOneWire ($name) - readings ignored because controller is not initialized (3)";
      }
    }
    elsif ($ascii =~ m/^1_SYS(\d+)/)
    {
      if (EseraOneWire_IsReadyToAcceptHardwareReadings($hash))
      {
        EseraOneWire_parseReading($hash, $ascii);
      }
      else
      {
        Log3 $name, 5, "EseraOneWire ($name) - readings ignored because controller is not initialized (4)";
      }
    }
    else
    {
      # everything else is considered a response to latest command
      EseraOneWire_taskListHandleResponse($hash, $ascii);
    }
  }

  $hash->{PARTIAL} = $buffer;
}

sub
EseraOneWire_processListEntry($$)
{
  my ($hash, $fieldsRef) = @_;
  my $name = $hash->{NAME};
  my @fields = @$fieldsRef;
  if (scalar(@fields) != 5)
  {
    Log3 $name, 1, "EseraOneWire ($name) - error: unexpected number of response fields for list entry";
  }

  # extract OWD number from response
  my $longEseraOwd = $fields[1];
  my $eseraOwd;
  if ($longEseraOwd =~ m/1_OWD(\d+)$/)
  {
    $eseraOwd = $1;
  }
  else
  {
    $eseraOwd = "_".$longEseraOwd."_";
    Log3 $name, 1, "EseraOneWire ($name) - error: unexpected OWD number format in LST response: ".$longEseraOwd;
  }

  # extract 1-wire ID
  my $oneWireId = $fields[2];

  my $status = $fields[3];

  # extract device type
  my $oneWireDeviceType = $fields[4];

  Log3 $name, 5, "EseraOneWire ($name) - new list entry: Esera OWD ".$eseraOwd." 1-wire ID ".$oneWireId." device type ".$oneWireDeviceType;

  if ($oneWireId =~ m/^FFFFFFFFFFFFFFFF/)
  {
    Log3 $name, 5, "EseraOneWire ($name) - list entry ".$eseraOwd." is not in use";
    return;
  }

  # store ESERA ID in hash
  if (defined $hash->{ESERA_IDS})
  {
    # list is not empty; get it and add new entry
    my $eseraIdsRef = $hash->{ESERA_IDS};
    my %eseraIds = %$eseraIdsRef;
    $eseraIds{$oneWireId} = $eseraOwd;
    $hash->{ESERA_IDS} = \%eseraIds;
  }
  else
  {
    # list is empty; create new list and store in hash
    my %eseraIds;
    $eseraIds{$oneWireId} = $eseraOwd;
    $hash->{ESERA_IDS} = \%eseraIds;
  }

  # store device type in hash
  if (defined $hash->{DEVICE_TYPES})
  {
    # list is not empty; get it and add new entry
    my $deviceTypesRef = $hash->{DEVICE_TYPES};
    my %deviceTypes = %$deviceTypesRef;
    $deviceTypes{$oneWireId} = $oneWireDeviceType;
    $hash->{DEVICE_TYPES} = \%deviceTypes;
  }
  else
  {
    # list is empty; create new list and store in hash
    my %deviceTypes;
    $deviceTypes{$oneWireId} = $oneWireDeviceType;
    $hash->{DEVICE_TYPES} = \%deviceTypes;
  }
}

sub
EseraOneWire_LIST_handler($$)
{
  my ($hash, $response) = @_;
  my $name = $hash->{NAME};

  my @fields = split(/\|/, $response);
  my $numberOfFields = scalar(@fields);
  if ($numberOfFields > 0)
  {
    my $type = $fields[0];
    if ($type eq "LST")
    {
      EseraOneWire_processListEntry($hash, \@fields);
    }
    else
    {
      Log3 $name, 1, "EseraOneWire ($name) - unexpected content in LST response: ".$response;
    }
  }
}

################################################################################
# Write command - process requests from client modules
################################################################################

sub
EseraOneWire_Write($$)
{
  my ($hash, $msg) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "EseraOneWire ($name) - received command from client: ".$msg;

  my @fields = split(/;/, $msg);
  if ($fields[0] eq "set")
  {
    # set;<oneWireId>;<rawMessageToSend>
    if (scalar(@fields) != 3)
    {
      Log3 $name, 1, "EseraOneWire ($name) - syntax error in command from client: ".$msg;
      return undef;
    }
    EseraOneWire_taskListAddPostedWrite($hash, $fields[2], 0.1);
  }
  elsif ($fields[0] eq "assign")
  {
    # assign;<oneWireId>;<productNumber> -> send command to controller, used to apply an ESERA product number
    #   This uses a specific call response handler which sends an error message to the client if something goes wrong.
    if (scalar(@fields) != 3)
    {
      Log3 $name, 1, "EseraOneWire ($name) - syntax error in command from client: ".$msg;
      return undef;
    }

    my $oneWireId = $fields[1];
    my $eseraId = EseraOneWire_oneWireIdToEseraId($hash, $oneWireId);
    if (!defined $eseraId)
    {
      Log3 $name, 1, "EseraOneWire ($name) - error looking up eseraId for assign request, oneWireId $oneWireId";
      return undef;
    }

    my $productNumber = $fields[2];
    my $command = "set,owd,art,".$eseraId.",".$productNumber;

    Log3 $name, 4, "EseraOneWire ($name) - info: assigning product number $productNumber to $oneWireId";

    EseraOneWire_taskListAdd($hash, $command, "1_ART", \&EseraOneWire_clientArtHandler,
      "1_ERR", \&EseraOneWire_clientArtErrorHandler, \&EseraOneWire_unexpected_handler, undef);

    # trigger an update of the device type in the device list
    EseraOneWire_removeDeviceTypeFromList($hash, $oneWireId);
    EseraOneWire_updateDeviceList($hash)
  }
  elsif ($fields[0] eq "status")
  {
    # status;<oneWireId> -> retrieve status for given device from controller and return it via Dispatch
    #   $deviceType.";".$owId.";".$readingId.";".$value (and readingId==STATISTIC)
    #   This requires a response handler that calls Dispatch after receiving and processing the response from the
    #   controller.
    if (scalar(@fields) != 4)
    {
      Log3 $name, 1, "EseraOneWire ($name) - syntax error in command from client: ".$msg;
      return undef;
    }
    Log3 $name, 4, "EseraOneWire ($name) - status command from client not supported yet";
  }
  else
  {
    Log3 $name, 1, "EseraOneWire ($name) - syntax error in command from client: ".$msg;
    return undef;
  }
}

################################################################################
# Readings
################################################################################

sub
EseraOneWire_forwardReadingToClient($$$$$)
{
  my ($hash, $fieldsCount, $owId, $readingId, $value) = @_;
  my $name = $hash->{NAME};
  if ($fieldsCount != 2)
  {
    Log3 $name, 1, "EseraOneWire ($name) - error: unexpected number of fields for reading";
  }

  my $eseraIdsRef = $hash->{ESERA_IDS};
  my $deviceTypesRef = $hash->{DEVICE_TYPES};
  if (!defined $eseraIdsRef || !defined $deviceTypesRef)
  {
    EseraOneWire_updateDeviceList($hash);
    return undef;
  }

  my %eseraIds = %$eseraIdsRef;
  my %deviceTypes = %$deviceTypesRef;
  if (!defined $eseraIds{$owId} || !defined $deviceTypes{$owId})
  {
    EseraOneWire_updateDeviceList($hash);
    return undef;
  }

  my $deviceType = $deviceTypes{$owId};
  my $eseraId = $eseraIds{$owId};
  my $message = $deviceType."_".$owId."_".$eseraId."_".$readingId."_".$value;
  Log3 $name, 4, "EseraOneWire ($name) - forwarding reading to clients: ".$message;
  Dispatch($hash, $message, "");
  EseraOneWire_SetStatus($hash, "ready");

  return undef;
}

sub
EseraOneWire_parseSysReadings($$$$$)
{
  my ($hash, $fieldsCount, $owId, $readingId, $value) = @_;
  my $name = $hash->{NAME};
  if ($fieldsCount != 2)
  {
    Log3 $name, 1, "EseraOneWire ($name) - error: unexpected number of fields for reading";
  }

  my $deviceType = $owId;
  my $eseraId = $owId;
  my $message = $deviceType."_".$owId."_".$eseraId."_".$readingId."_".$value;
  Log3 $name, 4, "EseraOneWire ($name) - passing reading to clients: ".$message;
  Dispatch($hash, $message, "");

  return undef;
}

# examples of reading messages from controller:
#2019.02.13 23:43:17 4: EseraOneWire (owc2) - COMM Read: 1_SYS1_1|0
#2019.02.13 23:43:17 4: EseraOneWire (owc2) - COMM Read: 1_SYS1_2|00000000
#2019.02.13 23:43:18 4: EseraOneWire (owc2) - COMM Read: 1_SYS2_1|0
#2019.02.13 23:43:18 4: EseraOneWire (owc2) - COMM Read: 1_SYS2_2|00000000
#2019.02.13 23:43:18 4: EseraOneWire (owc2) - COMM Read: 1_SYS3|0
#2019.02.13 23:43:18 4: EseraOneWire (owc2) - COMM Read: 1_0400000763496828|2262
#2019.02.13 23:43:18 4: EseraOneWire (owc2) - COMM Read: 1_E6000001C3748301|1
#2019.02.13 23:43:20 4: EseraOneWire (owc2) - COMM Read: 1_OWD2|0
#2019.02.13 23:43:22 4: EseraOneWire (owc2) - COMM Read: 1_OWD2|1
sub
EseraOneWire_parseReading($$)
{
  my ($hash, $line) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "EseraOneWire ($name) - line: ".$line;

  my @fields = split(/\|/, $line);
  my $numberOfFields = scalar(@fields);
  if ($numberOfFields == 2)
  {
    if ($fields[0] =~ m/^1_([0-9A-F]+)_([0-9]+)$/)
    {
      my $owId = $1;
      my $readingId = $2;
      my $value = $fields[1];

      EseraOneWire_forwardReadingToClient($hash, 2, $owId, $readingId, $value);
    }
    elsif ($fields[0] =~ m/^1_([0-9A-F]+)$/)
    {
      my $owId = $1;
      my $readingId = 0;
      my $value = $fields[1];

      EseraOneWire_forwardReadingToClient($hash, 2, $owId, $readingId, $value);
    }
    elsif ($fields[0] =~ m/1_([0-9:]+)_(\d+)/)   # TODO still needed after controller update?
    {
      my $owId = $2;
      my $readingId = 0;
      my $value = $fields[1];

      EseraOneWire_forwardReadingToClient($hash, 2, $owId, $readingId, $value);
    }
    elsif ($fields[0] =~ m/^1_SYS(\d)_(\d)/)
    {
      my $owId = "SYS".$1;
      my $readingId = $2;
      my $value = $fields[1];

      EseraOneWire_parseSysReadings($hash, 2, $owId, $readingId, $value);
    }
    elsif ($fields[0] =~ m/^1_SYS3/)
    {
      my $owId = "SYS3";
      my $readingId = 0;
      my $value = $fields[1];

      EseraOneWire_parseSysReadings($hash, 2, $owId, $readingId, $value);
    }
    elsif ($fields[0] =~ m/^1_OWD(\d)/)
    {
      my $eseraId = $1;
      my $owId = EseraOneWire_eseraIdToOneWireId($hash, $eseraId);
      if (not $owId)
      {
        Log3 $name, 1, "EseraOneWire ($name) - unexpected readings format (1) $fields[0]";
	return undef;
      }
      my $readingId = 0;
      my $value = $fields[1];
      EseraOneWire_forwardReadingToClient($hash, 2, $owId, $readingId, $value);
    }
    else
    {
      Log3 $name, 1, "EseraOneWire ($name) - unexpected readings format (2) $fields[0]";
    }
  }
  else
  {
    Log3 $name, 1, "EseraOneWire ($name) - unexpected readings format (3)";
  }
  return undef;
}

################################################################################
# response handlers
################################################################################

sub
EseraOneWire_query_response_handler($$)
{
  my ($hash, $response) = @_;
  my $name = $hash->{NAME};
  $response =~ s/;//g;
  my @fields = split(/\|/, $response);

  if (scalar(@fields) != 2)
  {
    Log3 $name, 1, "EseraOneWire ($name) - error: unexpected number of response fields for generic query response: ".$response;
    return;
  }

  if ($fields[0] =~ m/1_([A-Z0-9]+)$/)
  {
    my $key = ".".$1;
    my $value = $fields[1];
    $hash->{$key} = $value;
  }
}

sub
EseraOneWire_RST_handler($$)
{
  my ($hash, $response) = @_;
  my $name = $hash->{NAME};
  $response =~ s/;//g;
  my @fields = split(/\|/, $response);
  if (scalar(@fields) != 2)
  {
    Log3 $name, 1, "EseraOneWire ($name) - error: unexpected number of response fields for RST";
  }
  # ignore the response value
}

sub
EseraOneWire_fw_handler($$)
{
  my ($hash, $response) = @_;
  my $name = $hash->{NAME};
  $response =~ s/;//g;
  my @fields = split(/\|/, $response);

  if (scalar(@fields) != 2)
  {
    Log3 $name, 1, "EseraOneWire ($name) - error: unexpected number of response fields for fw query response: ".$response;
    return;
  }

  if ($fields[0] =~ m/1_([A-Z0-9]+)$/)
  {
    my $key = ".".$1;
    my $value = $fields[1];
    $hash->{$key} = $value;

    if ($value != $hash->{RECOMMENDED_FW})
    {
      Log3 $name, 1, "EseraOneWire ($name) - warning: actual FW version is $value, recommended FW version is ".$hash->{RECOMMENDED_FW};
    }
  }
}


sub
EseraOneWire_LIZ2_handler($$)
{
  my ($hash, $response) = @_;
  my $name = $hash->{NAME};
  $response =~ s/;//g;
  my @fields = split(/\|/, $response);
  if (scalar(@fields) != 3)
  {
    Log3 $name, 1, "EseraOneWire ($name) - error: unexpected number of response fields for LIZ,2 query";
  }
  if ($fields[1] != 2)
  {
    Log3 $name, 1, "EseraOneWire ($name) - error: unexpected LIZ response";
  }
  $hash->{".LIZ2"} = $fields[2];
}

sub
EseraOneWire_error_handler($$$)
{
  my ($hash, $command, $response) = @_;
  my $name = $hash->{NAME};
  $response =~ s/;//g;

  Log3 $name, 1, "EseraOneWire ($name) - error response, command: ".$command." , response: ".$response." , ignoring the response";
}

sub
EseraOneWire_unexpected_handler($$$)
{
  my ($hash, $command, $response) = @_;
  my $name = $hash->{NAME};
  $response =~ s/;//g;

  Log3 $name, 1, "EseraOneWire ($name) - error: unexpected response, command: ".$command.", response: ".$response.", ignoring the response";
}

sub
EseraOneWire_raw_command_handler($$$)
{
  my ($hash, $response) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 3, "EseraOneWire ($name) - response to raw command: ".$response;
  $hash->{RAW_RESPONSE} = $response;
}

sub
EseraOneWire_init_complete_handler($$$)
{
  my ($hash, $command, $response) = @_;
  my $name = $hash->{NAME};

  # stop the timeout counter
  RemoveInternalTimer($hash, "EseraOneWire_initTimeoutHandler");

  EseraOneWire_SetStatus($hash, "initialized");
}

sub
EseraOneWire_read_complete_handler($$$)
{
  my ($hash, $command, $response) = @_;
  $hash->{".READ_PENDING"} = 0;
}

sub
EseraOneWire_DEVICE_STATUS_handler($$)
{
  my ($hash, $response) = @_;
  my $name = $hash->{NAME};
  $response =~ s/;//g;
  my @fields = split(/\|/, $response);
  if (scalar(@fields) != 2)
  {
    Log3 $name, 1, "EseraOneWire ($name) - error: unexpected number of response fields for STATUS query";
  }
  my $owdId;
  my $status;
  if ($fields[0] =~ m/1_OWD_(\d+)/)
  {
    my $eseraId = $1;
    my $oneWireId = EseraOneWire_eseraIdToOneWireId($hash, $eseraId);

    if (!defined $oneWireId)
    {
      Log3 $name, 1, "EseraOneWire ($name) - error: could not map ESERA ID to 1-wire ID: ".$eseraId;
      return;
    }

    $status = $fields[1];
    my $statusText;
    if (!defined $status)
    {
      $statusText = "unknown";
    }
    elsif ($status == 0)
    {
      $statusText = "ok";
    }
    else
    {
      # TODO question to Esera: What is the meaning of status values 1..3?

      $statusText = "error (".$status .")";
    }

    if (defined $hash->{DEVICE_STATUS})
    {
      # list is not empty; get it and add new entry
      my $deviceStatusRef = $hash->{DEVICE_STATUS};
      my %deviceStatus = %$deviceStatusRef;
      $deviceStatus{$oneWireId} = $statusText;
      $hash->{DEVICE_STATUS} = \%deviceStatus;
    }
    else
    {
      # list is empty; create new list and store in hash
      my %deviceStatus;
      $deviceStatus{$oneWireId} = $statusText;
      $hash->{DEVICE_STATUS} = \%deviceStatus;
    }
  }
  else
  {
    Log3 $name, 1, "EseraOneWire ($name) - error: could not extract OWD ID";
  }
}

sub
EseraOneWire_ERROWD_handler($$)
{
  my ($hash, $response) = @_;
  my $name = $hash->{NAME};
  $response =~ s/;//g;
  my @fields = split(/\|/, $response);
  if (scalar(@fields) != 2)
  {
    Log3 $name, 1, "EseraOneWire ($name) - error: unexpected number of response fields for ERROWD query";
  }
  my $owdId;
  my $status;
  if ($fields[0] =~ m/1_ERROWD(\d+)/)
  {
    my $eseraId = $1;
    my $oneWireId = EseraOneWire_eseraIdToOneWireId($hash, $eseraId);

    if (!defined $oneWireId)
    {
      Log3 $name, 1, "EseraOneWire ($name) - error: could not map ESERA ID to 1-wire ID: ".$eseraId;
      return;
    }

    my $errorCount = $fields[1];

    if (defined $hash->{DEVICE_ERRORS})
    {
      # list is not empty; get it and add new entry
      my $deviceErrorsRef = $hash->{DEVICE_ERRORS};
      my %deviceErrors = %$deviceErrorsRef;
      $deviceErrors{$oneWireId} = $errorCount;
      $hash->{DEVICE_ERRORS} = \%deviceErrors;
    }
    else
    {
      # list is empty; create new list and store in hash
      my %deviceErrors;
      $deviceErrors{$oneWireId} = $errorCount;
      $hash->{DEVICE_ERRORS} = \%deviceErrors;
    }
  }
  else
  {
    Log3 $name, 1, "EseraOneWire ($name) - error: could not extract OWD ID";
  }
}

sub
EseraOneWire_clientArtHandler($$)
{
  my ($hash, $response) = @_;
  my $name = $hash->{NAME};
  $response =~ s/;//g;
  my @fields = split(/\|/, $response);

  if (scalar(@fields) != 3)
  {
    Log3 $name, 1, "EseraOneWire ($name) - error: unexpected number of response fields for ART response ".$response;
    return;
  }
}

sub
EseraOneWire_clientArtErrorHandler($$)
{
  my ($hash, $response) = @_;
  my $name = $hash->{NAME};
  $response =~ s/;//g;
  my @fields = split(/\|/, $response);

  if (scalar(@fields) != 2)
  {
    Log3 $name, 1, "EseraOneWire ($name) - error: unexpected number of response fields for ART error response";
    return;
  }
}

################################################################################
# task list
################################################################################
#
# The purpose of the task list is to provide queue for requests to the controller,
# to map responses to requests and to call handlers for incoming data from the
# controller. It is used to avoid blocking accesses to the controller.
#
# different kinds of tasks:
#
# 1) normal task: Command with expected response and error handling; waitTime is ignored
#    purpose: normal get/set commands that provide one single deterministic response
#
# 2) posted write: Command is sent. It is removed from the queue after waitTime.
#    Responses coming in during waitTime are recognized, but no handler function is called.
#    A zero waitTime is not allowed.
#
# 3) wait: Start a timer. Until the timer expires just do basic generic processing but
#    since no handler function is specified, do no special handling.
#    This is a special case of posted write, with no command and no handlers specified, but with
#    a specified waitTime.
#
# 4) sync: Send a command and expect a given response. Ignore responses which are not expected.
#    waitTime is undefined.

sub
EseraOneWire_taskListStartNext($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  # retrieve the task list
  my $taskListRef = $hash->{TASK_LIST};
  if (!defined $taskListRef)
  {
    Log3 $name, 4, "EseraOneWire ($name) - task list does not exist";
    return undef;
  }
  my @taskList = @$taskListRef;
  if ((scalar @taskList) < 1)
  {
    Log3 $name, 4, "EseraOneWire ($name) - task list is empty";
    return undef;
  }

  # get the next task
  my $taskRef = $taskList[0];
  my @task = @$taskRef;
  my $command = $task[0];
  my $expectedPattern = $task[1];
  my $waitTime = $task[6];

  # if a command is specified: send it to the controller
  if ($command)
  {
    Log3 $name, 4, "EseraOneWire ($name) - COMM sending: $command";
    DevIo_SimpleWrite($hash, $command."\r", 2);
  }

  # if the current command does not have an expected response: start
  # a timer to start the next command later
  if (!defined $expectedPattern)
  {
    Log3 $name, 5, "EseraOneWire ($name) - starting timer";
    InternalTimer(gettimeofday()+$waitTime, "EseraOneWire_popPostedWriteFromTaskList", $hash);
  }

  return undef;
}

sub
EseraOneWire_taskListGetCurrentCommand($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  # retrieve the task list
  my $taskListRef = $hash->{TASK_LIST};
  if (!defined $taskListRef)
  {
    Log3 $name, 4, "EseraOneWire ($name) - task list does not exist";
    return undef;
  }
  my @taskList = @$taskListRef;
  if ((scalar @taskList) < 1)
  {
    Log3 $name, 4, "EseraOneWire ($name) - task list is empty";
    return undef;
  }

  # get the task
  my $taskRef = $taskList[0];
  my @task = @$taskRef;
  my $command = $task[0];

  return $command;
}

sub
EseraOneWire_removeCurrentTaskFromList($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  # retrieve the task list
  my $taskListRef = $hash->{TASK_LIST};
  if (!defined $taskListRef)
  {
    Log3 $name, 4, "EseraOneWire ($name) - task list does not exist";
    return undef;
  }
  my @taskList = @$taskListRef;
  if ((scalar @taskList) < 1)
  {
    Log3 $name, 4, "EseraOneWire ($name) - task list is empty";
    return undef;
  }

  # remove current task from list
  my $length = scalar @taskList;
  Log3 $name, 4, "EseraOneWire ($name) - old length of task list: ".$length;
  shift @taskList;  # pop
  $length = scalar @taskList;
  Log3 $name, 4, "EseraOneWire ($name) - new length of task list: ".$length;
  $hash->{TASK_LIST} = \@taskList;

  return undef;
}

# Add a new task to the list. A task is the container for a request (read or write) to the controller,
# plus information about what to do with the response. When adding a new task to an empty
# task list that task will be started.
sub
EseraOneWire_taskListAdd($$$$$$$$)
{
  my ($hash, $command, $expectedPattern, $handler, $errorPattern, $errorHandler, $unexpectedHandler, $waitTime) = @_;
  my $name = $hash->{NAME};

  # combine task info in one array
  my @task = ($command, $expectedPattern, $handler, $errorPattern, $errorHandler, $unexpectedHandler, $waitTime);

  # retrieve the task list
  my $taskListRef = $hash->{TASK_LIST};
  my @taskList;
  if (defined $taskListRef)
  {
    @taskList = @$taskListRef;
  }

  # add task to tasklist
  push @taskList, \@task;
  $hash->{TASK_LIST} = \@taskList;

  # trigger the new task if it is the first one in the list
  my $length = scalar @taskList;
  Log3 $name, 4, "EseraOneWire ($name) - new length of task list: ".$length;
  if ($length == 1)
  {
    EseraOneWire_taskListStartNext($hash);
  }

  return undef;
}

# Add a new task to the list. Use this function for accesses that do not cause a
# response.
sub
EseraOneWire_taskListAddPostedWrite($$$)
{
  my ($hash, $command, $waitTime) = @_;
  my $name = $hash->{NAME};

  EseraOneWire_taskListAdd($hash, $command, undef, undef, undef, undef, undef, $waitTime);

  return undef;
}

sub
EseraOneWire_taskListAddSync($$$$)
{
  my ($hash, $command, $expectedPattern, $handler) = @_;
  my $name = $hash->{NAME};

  EseraOneWire_taskListAdd($hash, $command, $expectedPattern, $handler, undef, undef, undef, undef);

  return undef;
}

# Add a new task to the list. Use this function if no special handing for
# error responses and unexpected response is required..
sub
EseraOneWire_taskListAddSimple($$$$)
{
  my ($hash, $command, $expectedPattern, $handler) = @_;
  my $name = $hash->{NAME};

  EseraOneWire_taskListAdd($hash, $command, $expectedPattern, $handler,
    "1_ERR", \&EseraOneWire_error_handler, \&EseraOneWire_unexpected_handler, undef);

  return undef;
}

sub
EseraOneWire_popPostedWriteFromTaskList($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, "EseraOneWire ($name) - EseraOneWire_popPostedWriteFromTaskList";

  EseraOneWire_removeCurrentTaskFromList($hash);
  EseraOneWire_taskListStartNext($hash);

  return undef;
}

sub
EseraOneWire_taskListHandleResponse($$)
{
  my ($hash, $response) = @_;
  my $name = $hash->{NAME};

  # retrieve the task list
  my $taskListRef = $hash->{TASK_LIST};
  if (!defined $taskListRef)
  {
    Log3 $name, 4, "EseraOneWire ($name) - task list does not exist";
    return undef;
  }
  my @taskList = @$taskListRef;
  if ((scalar @taskList) < 1)
  {
    Log3 $name, 4, "EseraOneWire ($name) - task list is empty";
    return undef;
  }

  my $taskRef = $taskList[0];
  my @task = @$taskRef;
  my $expectedPattern = $task[1];
  my $errorPattern = $task[3];
  my $command = $task[0];

  if (!defined $expectedPattern)
  {
    # response during waitTime after posted write
    Log3 $name, 5, "EseraOneWire ($name) - receiving response while waiting after a posted write, ignoring: $response";
  }
  elsif ((defined $expectedPattern) and (!defined $errorPattern))
  {
    # sync task
    if ($response =~ m/$expectedPattern/)
    {
      # sync found, call registered function
      Log3 $name, 4, "EseraOneWire ($name) - COMM expected response for sync task received: ".$response;
      my $functionRef = $task[2];
      &$functionRef($hash, $response);

      EseraOneWire_removeCurrentTaskFromList($hash);
      EseraOneWire_taskListStartNext($hash);
    }
    else
    {
      # continue waiting for sync
      Log3 $name, 4, "EseraOneWire ($name) - COMM ignoring response while waiting for sync: ".$response;
    }
  }
  else
  {
    # normal task with expected response
    if ($response =~ m/$expectedPattern/)
    {
      Log3 $name, 4, "EseraOneWire ($name) - COMM expected response received: ".$response;
      # call registered handler
      my $functionRef = $task[2];
      &$functionRef($hash, $response);
    }
    elsif ($response =~ m/$errorPattern/)
    {
      Log3 $name, 1, "EseraOneWire ($name) - error response received, expected: $expectedPattern";
      # call registered error handler
      my $functionRef = $task[4];
      &$functionRef($hash, $command, $response);
    }
    else
    {
      Log3 $name, 1, "EseraOneWire ($name) - unexpected response received, expected: $expectedPattern";
      # call registered handler for unepected responses
      my $functionRef = $task[5];
      &$functionRef($hash, $command, $response);
    }
    EseraOneWire_removeCurrentTaskFromList($hash);
    EseraOneWire_taskListStartNext($hash);
  }

  return undef;
}

################################################################################
# status tracking and reporting
################################################################################

sub
EseraOneWire_SetStatus($$)
{
  my ($hash, $status) = @_;
  my $name = $hash->{NAME};

  # check whether given status is an expected value
  if (!(($status eq "defined") ||
        ($status eq "connected") ||
        ($status eq "disconnected") ||
        ($status eq "initializing") ||
        ($status eq "initialized") ||
        ($status eq "ready")))
  {
    Log3 $name, 1, "EseraOneWire ($name) - Error: SetStatus with unexpected status: $status";
    return;
  }

  # report status if it has changed
  if ((!defined $hash->{STATUS}) || (!($hash->{STATUS} eq $status)))
  {
    Log3 $name, 5, "EseraOneWire ($name) - $status";
    $hash->{STATUS} = $status;

    # Generate event consistently with events generated by DevIo.
    # Some other events are generated by DevIo.
    if ($status eq "ready")
    {
      DoTrigger($name, "READY");
    }

    # Update "state" reading consistently with DevIo. Some other
    # values are set by DevIo. Do not create event for the "state"
    # reading.
    if (($status eq "initializing") ||
        ($status eq "initialized") ||
        ($status eq "ready"))
    {
      setReadingsVal($hash, "state", $status, TimeNow());
    }
  }
}

sub
EseraOneWire_GetStatus($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if (defined  $hash->{STATUS})
  {
    return $hash->{STATUS};
  }
  else
  {
    return "unknown";
  }
}

sub
EseraOneWire_IsReadyToAcceptHardwareReadings($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $status = EseraOneWire_GetStatus($hash);

  if (($status eq "initialized") || ($status eq "ready"))
  {
    return 1;
  }

  return undef;
}

sub
EseraOneWire_KalTimeoutHandler($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 5, "EseraOneWire ($name) - EseraOneWire_KalTimeoutHandler";
  if (EseraOneWire_IsReadyToAcceptHardwareReadings($hash))
  {
    Log3 $name, 1, "EseraOneWire ($name) - error: KAL timeout";
    # We expect that the controller is up and running, but we do not
    # receive KAL messages. -> Try to reconnect.
    DevIo_CloseDev($hash) if(DevIo_IsOpen($hash));
    DevIo_OpenDev($hash, 0, "EseraOneWire_Init", "EseraOneWire_Callback");
  }
}

sub
EseraOneWire_processKalMessage($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, "EseraOneWire ($name) - COMM - 1_KAL message received";

  RemoveInternalTimer($hash, "EseraOneWire_KalTimeoutHandler");
  InternalTimer(gettimeofday()+int($hash->{KAL_PERIOD}*2.5), "EseraOneWire_KalTimeoutHandler", $hash);
}

################################################################################
1;
################################################################################

=pod
=item device
=item summary    Provides an interface between FHEM and Esera 1-wire controllers.
=item summary_DE Stellt eine Verbindung zu Esera 1-wire Controllern zur Verfuegung.
=begin html

<a name="EseraOneWire"></a>
<h3>EseraOneWire</h3>
<ul>
  This module provides an interface to Esera 1-wire controllers.<br>
  The module works in conjunction with 66_Esera* modules which support <br>
  various 1-wire devices. See these modules for more information <br>
  about supported 1-wire devices. This module supports autocreate. <br>
  <br>
  The module is tested with "Controller 1" and "Controller 2" with <br>
  TCP/IP interface, implementing the Esera ASCII protocol as described <br>
  in the Esera Controller Programmierhandbuch. The module <br>
  supports serial connections as well, for controllers with serial/USB <br>
  interface. It is tested with EseraStation 200.<br>
  <br>
  Tested with Esera controller firmware version 12027.<br>
  <br>
  <a name="EseraOneWire_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; EseraOneWire &lt;ip-address&gt;</code><br>
    Example: <code>define myEseraOneWireController EseraOneWire 192.168.0.15</code><br>
    Example: <code>define myEseraOneWireController EseraOneWire /dev/ttyUSB0</code><br>
  </ul>
  <br>
  <a name="EseraOneWire_Set"></a>
  <b>Set</b>
  <ul>
    <li>
      <b><code>set &lt;name&gt; clearlist</code><br></b>
      Clear the list of devices which is persistently stored in the controller.<br>
    </li>
    <li>
      <b><code>set &lt;name&gt; savelist</code><br></b>
      Save the current list of devices persistently in the controller. This is only<br>
      required when using iButton devices. See module EseraIButton for more information.
    </li>
    <li>
      <b><code>set &lt;name&gt; reset controller</code><br></b>
      Sends a reset command to the controller.<br>
    </li>
    <li>
      <b><code>set &lt;name&gt; reset tasks</code><br></b>
      The module internally queues tasks. Tasks are requests to the controller<br>
      which need to executed one after the other. For debug purposes only the<br>
      module provides a way to clear the queue.<br>
    </li>
    <li>
      <b><code>set &lt;name&gt; refresh</code><br></b>
      Triggers a read of updated information from the controller, including<br>
      settings, list of devices and controller info. In normal operation it<br>
      is not needed to call thi when the 1-wire devices are added. The module<br>
      triggers a re-read automatically if readings are received from unknown<br>
      devices.<br>
    </li>
    <li>
      <b><code>set &lt;name&gt; raw &lt;command&gt;</code><br></b>
      Debug only: Allows the user to send an arbitrary low level command to the<br>
      controller. The command is a command as described in the Esera Controller<br>
      Programmierhandbuch, without spaces, with commas as seperators, and without<br>
      trailing new line character.<br>
      The raw command and the received response are stored as internals<br>
      RAW_COMMAND and RAW_RESPONSE.<br>
      <br>
      Examples:<br>
      <ul>
	<li><code>set myEseraOneWireController raw get,sys,datatime</code></li>
	<li><code>set myEseraOneWire raw set,sys,datatime,0</code></li>
      </ul>
    </li>
    <li>
      <b><code>set &lt;name&gt; close</code><br></b>
      Close the TCP/IP connection to the controller.<br>
    </li>
    <li>
      <b><code>set &lt;name&gt; open</code><br></b>
      Open the TCP/IP connection to the controller.<br>
    </li>
  </ul>
  <br>
  <a name="EseraOneWire_Get"></a>
  <b>Get</b>
  <ul>
    <li>
      <b><code>get &lt;name&gt; info</code><br></b>
      Prints various information about the controller like part number,<br>
      serial number, date of manufacturing.<br>
    </li>
    <li>
      <b><code>get &lt;name&gt; settings</code><br></b>
      Returns various controller settings for debug purposes. New information<br>
      is retrieved when <i>set refresh</i> or <i>get settings</i> is called. New data<br>
      can then be printed with the following call of <i>get settings</i>. It is <br>
      implemented like this because it is a simple way to avoid blocking reads. <br>
      For more information regarding the individual settings please refer to the <br>
      Esera Controller Programmierhandbuch which can be downloaded from<br>
      www.esera.de .<br>
    </li>
    <li>
      <b><code>get &lt;name&gt; devices</code><br></b>
      Returns the list of currently connected 1-wire devices.<br>
      The format of each list entry is<br>
      <code>&lt;oneWireId&gt,&lt;eseraId&gt,&lt;deviceType&gt;;</code><br>
    </li>
    <li>
      <b><code>get &lt;name&gt; status</code><br></b>
      Reports currently known status of all connected 1-wire devices. <br>
      The format of each list entry is<br>
      <code>&lt;oneWireId&gt;,&lt;eseraId&gt;,&lt;deviceType&gt;,&lt;status&gt;,&lt;errors&gt;;</code><br>
      New status information is retrieved from the known devices when<br>
      <i>get status</i> is called. New data can then be printed with<br>
      the following call of <i>get status</i>. It is implemented like<br>
      this because it is a simple way to avoid blocking reads.<br>
    </li>
  </ul>
  <br>
  <a name="EseraOneWire_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>state &ndash; possible values are:
      <ul>
        <li><code>opened</code> &ndash; connection to controller established (from DevIo)</li>
        <li><code>disconnected</code> &ndash; disconnected from controller (from DevIo)</li>
        <li><code>failed</code> &ndash; connection to controller failed (from DevIo)</li>
        <li><code>initializing</code> &ndash; controller initialization in progress</li>
        <li><code>initialized</code> &ndash; controller initialization done</li>
        <li><code>ready</code> &ndash; fully functional</li>
      </ul>
    </li>
  </ul>
  <br>
  <a name="EseraOneWire_Attributes"></a>
  <b>Attributes</b>
  <ul>
    <li>pollTime &ndash; POLLTIME setting of the controller, see controller manual, default: 5</li>
    <li>dataTime &ndash; DATATIME setting of the controller, see controller manual, default: 10</li>
  </ul>
  <br>
  <a name="EseraOneWire_Events"></a>
  <b>Events</b>
  <ul>
    <li><code>CONNECTED</code> &ndash; from DevIo</li>
    <li><code>DISCONNECTED</code> &ndash; from DevIo</li>
    <li><code>FAILED</code> &ndash; from DevIo</li>
    <li><code>READY</code> &ndash; fully functional</li>
  </ul>
  <br>
</ul>
=end html
=cut
