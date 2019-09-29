# $Id$
##############################################################################
#
#     70_BOTVAC.pm
#     An FHEM Perl module for controlling a Neato BotVacConnected.
#
#     Copyright by Ulf von Mersewsky
#     e-mail: umersewsky at gmail.com
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
##############################################################################

package main;

use strict;
use warnings;


sub BOTVAC_Initialize($) {
    my ($hash) = @_;
    our $readingFnAttributes;

    $hash->{DefFn}    = "BOTVAC::Define";
    $hash->{GetFn}    = "BOTVAC::Get";
    $hash->{SetFn}    = "BOTVAC::Set";
    $hash->{UndefFn}  = "BOTVAC::Undefine";
    $hash->{DeleteFn} = "BOTVAC::Delete";
    $hash->{ReadFn}   = "BOTVAC::wsRead";
    $hash->{ReadyFn}  = "BOTVAC::wsReady";
    $hash->{AttrFn}   = "BOTVAC::Attr";
    $hash->{AttrList} = "disable:0,1 " .
                        "actionInterval " .
                        "boundaries:textField-long " .
                         $readingFnAttributes;
}

package BOTVAC;

use strict;
use warnings;
use POSIX;

use GPUtils qw(:all);  # wird für den Import der FHEM Funktionen aus der fhem.pl benötigt

use Time::HiRes qw(gettimeofday);
use JSON qw(decode_json encode_json);
#use IO::Socket::SSL::Utils qw(PEM_string2cert);
use Digest::SHA qw(hmac_sha256_hex sha1_hex);
use Encode qw(encode_utf8);
use MIME::Base64;

require "DevIo.pm";
require "HttpUtils.pm";

## Import der FHEM Funktionen
BEGIN {
    GP_Import(qw(
        AttrVal
        createUniqueId
        FmtDateTime
        FmtDateTimeRFC1123
        fhemTzOffset
        getKeyValue
        setKeyValue
        getUniqueId
        InternalTimer
        InternalVal
        readingsSingleUpdate
        readingsBulkUpdate
        readingsBulkUpdateIfChanged
        readingsBeginUpdate
        readingsDelete
        readingsEndUpdate
        ReadingsNum
        ReadingsVal
        RemoveInternalTimer
        Log3
        trim
    ))
};

my %opcode = (    # Opcode interpretation of the ws "Payload data
  'continuation'  => 0x00,
  'text'          => 0x01,
  'binary'        => 0x02,
  'close'         => 0x08,
  'ping'          => 0x09,
  'pong'          => 0x0A
);

###################################
sub Define($$) {
    my ( $hash, $def ) = @_;
    my @a = split( "[ \t][ \t]*", $def );
    my $name = $hash->{NAME};

    Log3($name, 5, "BOTVAC $name: called function Define()");

    if ( int(@a) < 3 ) {
        my $msg =
          "Wrong syntax: define <name> BOTVAC <email> [<vendor>] [<poll-interval>]";
        Log3($name, 4, $msg);
        return $msg;
    }

    $hash->{TYPE} = "BOTVAC";

    my $email = $a[2];
    $hash->{EMAIL} = $email;

    # defaults
    my $vendor = "neato";
    my $interval = 85;

    if (defined($a[3])) {
      if (lc($a[3]) =~ /^(neato|vorwerk)$/) {
        $vendor = $1;
        $interval = $a[4] if (defined($a[4]));
      } elsif ($a[3] =~ /^[0-9]+$/ and not defined($a[4])) {
        $interval = $a[3];
      } else {
        StorePassword($hash, $a[3]);
        if (defined($a[4])) {
          if (lc($a[4]) =~ /^(neato|vorwerk)$/) {
            $vendor = $1;
            $interval = $a[5] if (defined($a[5]));
          } else {
            $interval = $a[4];
          }
        }
      }
    }
    $hash->{VENDOR} = $vendor;
    $hash->{INTERVAL} = $interval;

    unless ( defined( AttrVal( $name, "webCmd", undef ) ) ) {
      no warnings "once";
      $::attr{$name}{webCmd} = 'startCleaning:stop:sendToBase';
    }

    # start the status update timer
    RemoveInternalTimer($hash);
    InternalTimer( gettimeofday() + 2, "BOTVAC::GetStatus", $hash, 1 );

    AddExtension($name, "BOTVAC::GetMap", "BOTVAC/$name/map");

    return;
}

#####################################
sub GetStatus($;$) {
    my ( $hash, $update ) = @_;
    my $name      = $hash->{NAME};
    my $interval  = $hash->{INTERVAL};
    my @successor = ();

    Log3($name, 5, "BOTVAC $name: called function GetStatus()");

    # use actionInterval if state is busy or paused
    $interval = AttrVal($name, "actionInterval", $interval) if (ReadingsVal($name, "stateId", "0") =~ /2|3/);

    RemoveInternalTimer($hash);
    InternalTimer( gettimeofday() + $interval, "BOTVAC::GetStatus", $hash, 0 );

    return if ( AttrVal($name, "disable", 0) == 1 or ReadingsVal($name,"pollingMode",1) == 0);

    # check device availability
    if (!$update) {
      my @time = localtime();
      my $secs = ($time[2] * 3600) + ($time[1] * 60) + $time[0];

      # update once per day
      push(@successor, ["dashboard", undef]) if ($secs <= $interval);

      push(@successor, ["messages", "getSchedule"]);
      push(@successor, ["messages", "getGeneralInfo"]) if (GetServiceVersion($hash, "generalInfo") =~ /.*-1/);
      push(@successor, ["messages", "getPreferences"]) if (GetServiceVersion($hash, "preferences") ne "");

      SendCommand($hash, "messages", "getRobotState", undef, @successor);
    }

    # cleanup
    readingsDelete($hash, "accessToken");
    readingsDelete($hash, "secretKey");

    return;
}

###################################
sub Get($@) {
    my ( $hash, @a ) = @_;
    my $name = $hash->{NAME};
    my $what;

    Log3($name, 5, "BOTVAC $name: called function Get()");

    return "argument is missing" if ( int(@a) < 2 );

    $what = $a[1];

    if ( $what =~ /^(batteryPercent)$/ ) {
        if ( defined( $hash->{READINGS}{$what}{VAL} ) ) {
            return $hash->{READINGS}{$what}{VAL};
        } else {
            return "no such reading: $what";
        }
    } elsif ( $what =~ /^(statistics)$/ ) {
      if (defined($hash->{helper}{MAPS}) and @{$hash->{helper}{MAPS}} > 0) {
        return GetStatistics($hash);
      } else {
        return "maps for $what are not available yet";
      }
    } else {
        return "Unknown argument $what, choose one of batteryPercent:noArg statistics:noArg";
    }
}

###################################
sub Set($@) {
    my ( $hash, @a ) = @_;
    my $name  = $hash->{NAME};

    Log3($name, 5, "BOTVAC $name: called function Set()");

    return "No Argument given" if ( !defined( $a[1] ) );

    my $arg = $a[1];
    $arg .= " ".$a[2] if (defined( $a[2] ));
    $arg .= " ".$a[3] if (defined( $a[3] ));

    my $houseCleaningSrv = GetServiceVersion($hash, "houseCleaning");
    my $spotCleaningSrv = GetServiceVersion($hash, "spotCleaning");

    my $usage = "Unknown argument " . $a[1] . ", choose one of";

    $usage .= " password";
    if ( ReadingsVal($name, ".start", "0") ) {
      $usage .= " startCleaning:";
      if ($houseCleaningSrv eq "basic-4") {
        $usage .= "house,map,zone";
      } elsif ($houseCleaningSrv eq "basic-3") {
        $usage .= "house,map";
      } else {
        $usage .= "noArg";
      }
      $usage .= " startSpot:noArg";
    }
    $usage .= " stop:noArg"                if ( ReadingsVal($name, ".stop", "0") );
    $usage .= " pause:noArg"               if ( ReadingsVal($name, ".pause", "0") );
    $usage .= " pauseToBase:noArg"         if ( ReadingsVal($name, ".pause", "0") and ReadingsVal($name, "dockHasBeenSeen", "0") );
    $usage .= " resume:noArg"              if ( ReadingsVal($name, ".resume", "0") );
    $usage .= " sendToBase:noArg"          if ( ReadingsVal($name, ".goToBase", "0") );
    $usage .= " reloadMaps:noArg"          if ( GetServiceVersion($hash, "maps") ne "" );
    $usage .= " dismissCurrentAlert:noArg" if ( ReadingsVal($name, "alert", "") ne "" );
    $usage .= " findMe:noArg"              if ( GetServiceVersion($hash, "findMe") eq "basic-1" );
    $usage .= " startManual:noArg"         if ( GetServiceVersion($hash, "manualCleaning") ne "" );
    $usage .= " statusRequest:noArg schedule:on,off syncRobots:noArg pollingMode:on,off";

    # preferences
    $usage .= " robotSounds:on,off"                            if ( GetServiceVersion($hash, "preferences") !~ /(^$)|(basic-1)/ );
    $usage .= " dirtbinAlertReminderInterval:30,60,90,120,150" if ( GetServiceVersion($hash, "preferences") =~ /(basic-\d)|(advanced-\d)/ );
    $usage .= " filterChangeReminderInterval:1,2,3"            if ( GetServiceVersion($hash, "preferences") =~ /(basic-\d)|(advanced-\d)/ );
    $usage .= " brushChangeReminderInterval:4,5,6,7,8"         if ( GetServiceVersion($hash, "preferences") =~ /(basic-\d)|(advanced-\d)/ );

    # house cleaning
    $usage .= " nextCleaningMode:eco,turbo" if ($houseCleaningSrv =~ /basic-\d/);
    $usage .= " nextCleaningNavigationMode:normal,extra#care" if ($houseCleaningSrv eq "minimal-2");
    $usage .= " nextCleaningNavigationMode:normal,extra#care,deep" if ($houseCleaningSrv eq "basic-3" or $houseCleaningSrv eq "basic-4");
    $usage .= " nextCleaningZone" if ($houseCleaningSrv eq "basic-4");

    # spot cleaning
    $usage .= " nextCleaningModifier:normal,double" if ($spotCleaningSrv eq "basic-1" or $spotCleaningSrv eq "minimal-2");
    if ($spotCleaningSrv =~ /basic-\d/) {
      $usage .= " nextCleaningSpotWidth:100,200,300,400";
      $usage .= " nextCleaningSpotHeight:100,200,300,400";
    }

    # manual cleaning
    if ($hash->{HELPER}{WEBSOCKETS}) {
      $usage .= " wsCommand:brush-on,brush-off,eco-on,eco-off,turbo-on,turbo-off,vacuum-on,vacuum-off";
      $usage .= " wsCombo:forward,back,stop,arc-left,arc-right,pivot-left,pivot-right";
    }

    my @robots;
    if (defined($hash->{helper}{ROBOTS})) {
      @robots = @{$hash->{helper}{ROBOTS}};
      if (@robots > 1) {
        $usage .= " setRobot:";
        for (my $i = 0; $i < @robots; $i++) {
          $usage .= "," if ($i > 0);
          $usage .= $robots[$i]->{name};
        }
      }
    }

    if (GetServiceVersion($hash, "maps") eq "advanced-1" or
        GetServiceVersion($hash, "maps") eq "basic-2" or
        GetServiceVersion($hash, "maps") eq "macro-1") {
      if (defined($hash->{helper}{BoundariesList})) {
        my @Boundaries = @{$hash->{helper}{BoundariesList}};
        my @names;
        for (my $i = 0; $i < @Boundaries; $i++) {
          my $name = $Boundaries[$i]->{name};
          push @names,$name if (!(grep { $_ eq $name } @names) and ($name ne ""));
        }
        my $BoundariesList  = @names ? "multiple-strict,".join(",", @names) : "textField";
        $usage .= " setBoundariesOnFloorplan_0:".$BoundariesList if (ReadingsVal($name, "floorplan_0_id" ,"") ne "");
        $usage .= " setBoundariesOnFloorplan_1:".$BoundariesList if (ReadingsVal($name, "floorplan_1_id" ,"") ne "");
        $usage .= " setBoundariesOnFloorplan_2:".$BoundariesList if (ReadingsVal($name, "floorplan_2_id" ,"") ne "");
      }
      else {
        $usage .= " setBoundariesOnFloorplan_0:textField" if (ReadingsVal($name, "floorplan_0_id" ,"") ne "");
        $usage .= " setBoundariesOnFloorplan_1:textField" if (ReadingsVal($name, "floorplan_1_id" ,"") ne "");
        $usage .= " setBoundariesOnFloorplan_2:textField" if (ReadingsVal($name, "floorplan_2_id" ,"") ne "");
      }
    }

    my $cmd = '';
    my $result;


    # house cleaning
    if ( $a[1] eq "startCleaning" ) {
        Log3($name, 2, "BOTVAC set $name $arg");

        my $option = "house";
        $option = $a[2] if (defined($a[2]));
        SendCommand( $hash, "messages", "startCleaning", $option );
        readingsSingleUpdate($hash, ".stop", "1", 0);
    }

    # spot cleaning
    elsif ( $a[1] eq "startSpot" ) {
        Log3($name, 2, "BOTVAC set $name $arg");

        SendCommand( $hash, "messages", "startSpot" );
        readingsSingleUpdate($hash, ".stop", "1", 0);
    }

    # manual cleaning
    elsif ( $a[1] eq "startManual" ) {
        Log3($name, 2, "BOTVAC set $name $arg");

        SendCommand( $hash, "messages", "getRobotManualCleaningInfo" );
        readingsSingleUpdate($hash, ".stop", "1", 0);
    }

    # stop
    elsif ( $a[1] eq "stop" ) {
        Log3($name, 2, "BOTVAC set $name $arg");

        if ($hash->{HELPER}{WEBSOCKETS}) {
          wsClose($hash);
        } else {
          SendCommand( $hash, "messages", "stopCleaning" );
        }
    }

    # pause
    elsif ( $a[1] eq "pause" ) {
        Log3($name, 2, "BOTVAC set $name $arg");

        SendCommand( $hash, "messages", "pauseCleaning" );
    }

    # pauseToBase
    elsif ( $a[1] eq "pauseToBase" ) {
        Log3($name, 2, "BOTVAC set $name $arg");

        SendCommand( $hash, "messages", "pauseCleaning", undef, (["messages", "sendToBase"]) );
    }

    # resume
    elsif ( $a[1] eq "resume" ) {
        Log3($name, 2, "BOTVAC set $name $arg");

        SendCommand( $hash, "messages", "resumeCleaning" );
    }

    # sendToBase
    elsif ( $a[1] eq "sendToBase" ) {
        Log3($name, 2, "BOTVAC set $name $arg");

        SendCommand( $hash, "messages", "sendToBase" );
    }

    # dismissCurrentAlert
    elsif ( $a[1] eq "dismissCurrentAlert" ) {
        Log3($name, 2, "BOTVAC set $name $arg");

        SendCommand( $hash, "messages", "dismissCurrentAlert" );
    }

    # findMe
    elsif ( $a[1] eq "findMe" ) {
        Log3($name, 2, "BOTVAC set $name $arg");

        SendCommand( $hash, "messages", "findMe" );
    }

    # schedule
    elsif ( $a[1] eq "schedule" ) {
        Log3($name, 2, "BOTVAC set $name $arg");

        return "No argument given" if ( !defined( $a[2] ) );

        my $switch = $a[2];
        if ($switch eq "on") {
            SendCommand( $hash, "messages", "enableSchedule" );
        } else {
            SendCommand( $hash, "messages", "disableSchedule" );
        }
    }

    # syncRobots
    elsif ( $a[1] eq "syncRobots" ) {
        Log3($name, 2, "BOTVAC set $name $arg");

        SendCommand( $hash, "dashboard" );
    }

    # statusRequest
    elsif ( $a[1] eq "statusRequest" ) {
        Log3($name, 2, "BOTVAC set $name $arg");
        
        my @successor = ();
        push(@successor, ["messages", "getPreferences"]) if (GetServiceVersion($hash, "preferences") ne "");
        push(@successor, ["messages", "getSchedule"]);

        SendCommand( $hash, "messages", "getRobotState", undef, @successor );
    }

    # setRobot
    elsif ( $a[1] eq "setRobot" ) {
        Log3($name, 2, "BOTVAC set $name $arg");

        return "No argument given" if ( !defined( $a[2] ) );
        if (@robots) {
          my $robot = 0;
          while($a[2] ne $robots[$robot]->{name} and $robot + 1 < @robots) {
            $robot++;
          }
          readingsBeginUpdate($hash);
          SetRobot($hash, $robot);
          readingsEndUpdate( $hash, 1 );
        } else {
          Log3($name, 2, "BOTVAC Can't set robot, run 'syncRobots' before");
        }
    }

    # reloadMaps
    elsif ( $a[1] eq "reloadMaps" ) {
        Log3($name, 2, "BOTVAC set $name $arg");

        SendCommand( $hash, "robots", "maps");
    }

    # setBoundaries
    elsif ( $a[1] =~ /^setBoundariesOnFloorplan_\d$/) {
        my $floorplan = substr($a[1],25,1);
        Log3($name, 2, "BOTVAC set $name $arg");

        return "No argument given" if ( !defined( $a[2] ) );

        my $setBoundaries = "";
        if ($a[2] =~ /^\{.*\}/){
          $setBoundaries = $a[2];
        }
        elsif (defined($hash->{helper}{BoundariesList})) {
          my @names = split ",",$a[2];
          my @Boundaries = @{$hash->{helper}{BoundariesList}};
          for (my $i = 0; $i < @Boundaries; $i++) {
            foreach my $name (@names) {
              if ($Boundaries[$i]->{name} eq $name) {
                $setBoundaries .= "," if ($setBoundaries =~ /^\{.*\}/);
                $setBoundaries .= encode_json($Boundaries[$i]);
              }
            }
          }
        }
        return "Argument of $a[1] is not a valid Boundarie name and also not a JSON string: \"$a[2]\"" if ($setBoundaries eq "");
        Log3($name, 5, "BOTVAC set $name " . $a[1] . " " . $a[2] . " json: " . $setBoundaries);
        my %params;
        $params{"boundaries"} = "\[".$setBoundaries."\]";
        $params{"mapId"} = "\"".ReadingsVal($name, "floorplan_".$floorplan."_id", "myHome")."\"";
        SendCommand( $hash, "messages", "setMapBoundaries", \%params );
        return;
    }

    # nextCleaning
    elsif ( $a[1] =~ /nextCleaning/) {
        Log3($name, 2, "BOTVAC set $name $arg");

        return "No argument given" if ( !defined( $a[2] ) );

        readingsSingleUpdate($hash, $a[1], $a[2], 0);
    }

    # wsCommand || wsCommand
    elsif ( $a[1] =~ /wsCombo|wsCommand/) {
        Log3($name, 2, "BOTVAC set $name $arg");

        return "No argument given" if ( !defined( $a[2] ) );

        my $cmd = ($a[1] eq "wsCombo" ? "combo" : "command");
        wsEncode($hash, "{ \"$cmd\": \"$a[2]\" }");
    }

    # password
    elsif ( $a[1] eq "password") {
        Log3($name, 2, "BOTVAC set $name " . $a[1]);

        return "No password given" if ( !defined( $a[2] ) );

        StorePassword( $hash, $a[2] );
    }

    # pollingMode
    elsif ( $a[1] eq "pollingMode") {
        Log3($name, 4, "BOTVAC set $name $arg");

        return "No argument given" if ( !defined( $a[2] ) );

        readingsSingleUpdate($hash, "pollingMode", ($a[2] eq "off" ? "0" : "1"), 0);
    }

    # preferences
    elsif ( $a[1] =~ /^(robotSounds|dirtbinAlertReminderInterval|filterChangeReminderInterval|brushChangeReminderInterval)$/) {
        my $item = $1;
        my %params;

        Log3($name, 4, "BOTVAC set $name $arg");

        return "No argument given" if ( !defined( $a[2] ) );

        foreach my $reading ( keys %{ $hash->{READINGS} } ) {
            if ($reading =~ /^pref_(.*)/) {
                my $prefName = $1;
                $params{$prefName} = ReadingsVal($name, $reading, "null");
                $params{$prefName} *= 43200 if ($prefName =~ /ChangeReminderInterval/ and $params{$prefName} =~ /^\d*$/);
                $params{$prefName} = SetBoolean($params{$prefName}) if ($prefName eq "robotSounds");
            }
        }

        return "No preferences present, execute 'set statusRequest' first." unless (keys %params);

        $params{$item} = $a[2];
        $params{$item} *= 43200 if ($item =~ /ChangeReminderInterval/ && $params{$item} =~ /^\d*$/);
        $params{$item} = SetBoolean($params{$item}) if ($item eq "robotSounds");

        SendCommand( $hash, "messages", "setPreferences", \%params );
    }

    # return usage hint
    else {
        return $usage;
    }

    return;
}

###################################
sub Undefine($$) {
    my ( $hash, $arg ) = @_;
    my $name = $hash->{NAME};

    Log3($name, 5, "BOTVAC $name: called function Undefine()");

    # Stop the internal GetStatus-Loop and exit
    RemoveInternalTimer($hash);

    RemoveExtension("BOTVAC/$name/map");

    return;
}

###################################
sub Delete($$) {
    my ( $hash, $arg ) = @_;
    my $name = $hash->{NAME};

    Log3($name, 5, "BOTVAC $name: called function Delete()");

    my $index = $hash->{TYPE}."_".$name."_passwd";
    setKeyValue($index,undef);

    return;
}

###################################
sub Attr(@)
{
  my ($cmd,$name,$attr_name,$attr_value) = @_;
  my $hash  = $::defs{$name};
  my $err;
  if ($cmd eq "set") {
    if ($attr_name eq "boundaries") {
      if ($attr_value !~ /^\{.*\}/){
        $err = "Invalid value $attr_value for attribute $attr_name. Must be a space separated list of JSON strings.";
      } else {
        my @boundaries = split(/\s/, $attr_value);
        my @areas;
        if (@boundaries > 1) {
          foreach my $area (@boundaries) {
            push @areas,eval{decode_json $area};
          }
        } else {
          push @areas,eval{decode_json $attr_value};
        }
      $hash->{helper}{BoundariesList} = \@areas;
      }
    }
  } else {
    delete $hash->{helper}{BoundariesList} if ($attr_name eq "boundaries");
  }
  return $err ? $err : undef;
}

############################################################################################################
#
#   Begin of helper functions
#
############################################################################################################

#########################
sub AddExtension($$$) {
    my ( $name, $func, $link ) = @_;

    my $url = "/$link";
    Log3($name, 2, "Registering BOTVAC $name for URL $url...");
    $::data{FWEXT}{$url}{deviceName} = $name;
    $::data{FWEXT}{$url}{FUNC}       = $func;
    $::data{FWEXT}{$url}{LINK}       = $link;
}

#########################
sub RemoveExtension($) {
    my ($link) = @_;

    my $url  = "/$link";
    my $name = $::data{FWEXT}{$url}{deviceName};
    Log3($name, 2, "Unregistering BOTVAC $name for URL $url...");
    delete $::data{FWEXT}{$url};
}

###################################
sub SendCommand($$;$$@) {
    my ( $hash, $service, $cmd, $option, @successor ) = @_;
    my $name        = $hash->{NAME};
    my $email       = $hash->{EMAIL};
    my $password    = ReadPassword($hash);
    my $timestamp   = gettimeofday();
    my $timeout     = 180;
    my $header;
    my $data;
    my $reqId = 0;

    Log3($name, 5, "BOTVAC $name: called function SendCommand()");

    my $URL = "https://";
    my $response;
    my $return;

    my %sslArgs;

    if ($service ne "sessions" && $service ne "dashboard") {
        return if (CheckRegistration($hash, $service, $cmd, $option, @successor));
    }

    if ( !defined($cmd) ) {
        Log3($name, 4, "BOTVAC $name: REQ $service");
    }
    else {
        Log3($name, 4, "BOTVAC $name: REQ $service/$cmd");
    }
    Log3($name, 4, "BOTVAC $name: REQ option $option") if (defined($option));
    LogSuccessors($hash, @successor);

    $header = "Accept: application/vnd.neato.nucleo.v1";
    $header .= "\r\nContent-Type: application/json";

    if ($service eq "sessions") {
      if (!defined($password)) {
        readingsSingleUpdate($hash, "state", "Password missing (see instructions)",1);
        return;
      }
      my $token = createUniqueId() . createUniqueId();
      $URL .= GetBeehiveHost($hash->{VENDOR});
      $URL .= "/sessions";
      $data = "{\"platform\": \"ios\", \"email\": \"$email\", \"token\": \"$token\", \"password\": \"$password\"}";
      %sslArgs = ( SSL_verify_mode => 0 );

    } elsif ($service eq "dashboard") {
      $header .= "\r\nAuthorization: Token token=".ReadingsVal($name, ".accessToken", "");
      $URL .= GetBeehiveHost($hash->{VENDOR});
      $URL .= "/dashboard";
      %sslArgs = ( SSL_verify_mode => 0 );

    } elsif ($service eq "robots") {
      my $serial = ReadingsVal($name, "serial", "");
      return if ($serial eq "");

      $header .= "\r\nAuthorization: Token token=".ReadingsVal($name, ".accessToken", "");
      $URL .= GetBeehiveHost($hash->{VENDOR});
      $URL .= "/users/me/robots/$serial/";
      $URL .= (defined($cmd) ? $cmd : "maps");
      %sslArgs = ( SSL_verify_mode => 0 );

    } elsif ($service eq "messages") {
      my $serial = ReadingsVal($name, "serial", "");
      return if ($serial eq "");

      $URL = ReadingsVal($name, "nucleoUrl", "https://".GetNucleoHost($hash->{VENDOR}));
      $URL .= "/vendors/";
      $URL .= $hash->{VENDOR};
      $URL .= "/robots/$serial/messages";

      if (defined($option) and ref($option) eq "HASH" ) {
        if (defined($option->{reqId})) {
          $reqId = $option->{reqId};
        }
      }

      $cmd .= "Events" if ($cmd eq "getSchedule" and GetServiceVersion($hash, "schedule") eq "basic-2");

      $data = "{\"reqId\":\"$reqId\",\"cmd\":\"$cmd\"";
      if ($cmd eq "startCleaning") {
        $data .= ",\"params\":{";
        my $version = GetServiceVersion($hash, "houseCleaning");
        if ($version eq "basic-1") {
          $data .= "\"category\":2";
          $data .= ",\"mode\":";
          $data .= (GetCleaningParameter($hash, "cleaningMode", "eco") eq "eco" ? "1" : "2");
          $data .= ",\"modifier\":1";
        } elsif ($version eq "minimal-2") {
          $data .= "\"category\":2";
          $data .= ",\"navigationMode\":";
          $data .= (GetCleaningParameter($hash, "cleaningNavigationMode", "normal") eq "normal" ? "1" : "2");
        } elsif ($version eq "basic-3" or $version eq "basic-4") {
          $data .= "\"category\":";
          $data .= (($option eq "map" or $option eq "zone") ? "4" : "2");
          $data .= ",\"mode\":";
          my $cleanMode = GetCleaningParameter($hash, "cleaningMode", "eco");
          $data .= ($cleanMode eq "eco" ? "1" : "2");
          $data .= ",\"navigationMode\":";
          my $navMode = GetCleaningParameter($hash, "cleaningNavigationMode", "normal");
          if ($navMode eq "deep" and $cleanMode = "turbo") {
            $data .= "3";
          } elsif ($navMode eq "extra care") {
            $data .= "2";
          } else {
            $data .= "1";
          }
          if ($version eq "basic-4" and $option eq "zone") {
            my $zone = GetCleaningParameter($hash, "cleaningZone", "");
            $data .= ",\"boundaryId\":\"".$zone."\"" if ($zone ne "");
          }
        }
        $data .= "}";
      }
      elsif ($cmd eq "startSpot") {
        $data = "{\"reqId\":\"$reqId\",\"cmd\":\"startCleaning\"";
        $data .= ",\"params\":{";
        $data .= "\"category\":3";
        my $version = GetServiceVersion($hash, "spotCleaning");
        if ($version eq "basic-1") {
          $data .= ",\"mode\":";
          $data .= (GetCleaningParameter($hash, "cleaningMode", "eco") eq "eco" ? "1" : "2");
        }
        if ($version eq "basic-1" or $version eq "minimal-2") {
          $data .= ",\"modifier\":";
          $data .= (GetCleaningParameter($hash, "cleaningModifier", "normal") eq "normal" ? "1" : "2");
        }
        if ($version eq "micro-2" or $version eq "minimal-2") {
          $data .= ",\"navigationMode\":";
          $data .= (GetCleaningParameter($hash, "cleaningNavigationMode", "normal") eq "normal" ? "1" : "2");
        }
        if ($version eq "basic-1" or $version eq "basic-3") {
          $data .= ",\"spotWidth\":";
          $data .= GetCleaningParameter($hash, "cleaningSpotWidth", "200");
          $data .= ",\"spotHeight\":";
          $data .= GetCleaningParameter($hash, "cleaningSpotHeight", "200");
        }
        $data .= "}";
      }
      elsif ($cmd eq "setMapBoundaries" or $cmd eq "getMapBoundaries" or $cmd eq "setPreferences") {
        if (defined($option) and ref($option) eq "HASH") {
          $data .= ",\"params\":{";
          foreach( keys %$option ) {
            $data .= "\"$_\":$option->{$_}," if ($_ ne "reqId");
          }
          my $tmp = chop($data);  #remove last ","
          $data .= "}";
        }
      }
      $data .= "}";

      my $now = time();
      my $date = FmtDateTimeRFC1123($now);
      my $message = join("\n", (lc($serial), $date, $data));
      my $hmac = hmac_sha256_hex($message, ReadingsVal($name, ".secretKey", ""));

      $header .= "\r\nDate: $date";
      $header .= "\r\nAuthorization: NEATOAPP $hmac";

      #%sslArgs = ( SSL_ca =>  [ GetCAKey( $hash ) ] );
      %sslArgs = ( SSL_verify_mode => 0 );
    } elsif ($service eq "loadmap") {
      $URL = $cmd;
    }

    # send request via HTTP-POST method
    Log3($name, 5, "BOTVAC $name: POST $URL (" . ::urlDecode($data) . ")")
      if ( defined($data) );
    Log3($name, 5, "BOTVAC $name: GET $URL")
      if ( !defined($data) );
    Log3($name, 5, "BOTVAC $name: header $header")
      if ( defined($header) );

    ::HttpUtils_NonblockingGet(
        {
            url         => $URL,
            timeout     => $timeout,
            noshutdown  => 1,
            header      => $header,
            data        => $data,
            hash        => $hash,
            service     => $service,
            cmd         => $cmd,
            successor   => \@successor,
            timestamp   => $timestamp,
            sslargs     => { %sslArgs },
            callback    => \&ReceiveCommand,
        }
    );

    return;
}

###################################
sub ReceiveCommand($$$) {
    my ( $param, $err, $data ) = @_;
    my $hash      = $param->{hash};
    my $name      = $hash->{NAME};
    my $service   = $param->{service};
    my $cmd       = $param->{cmd};
    my @successor = @{$param->{successor}};

    my $rc = ( $param->{buf} ) ? $param->{buf} : $param;

    my $loadMap;
    my $return;
    my $reqId = 0;

    Log3($name, 5, "BOTVAC $name: called function ReceiveCommand() rc: $rc err: $err data: $data ");

    readingsBeginUpdate($hash);

    # device not reachable
    if ($err) {

        if ( !defined($cmd) || $cmd eq "" ) {
            Log3($name, 4, "BOTVAC $name:$service RCV $err");
        } else {
            Log3($name, 4, "BOTVAC $name:$service/$cmd RCV $err");
        }

        # keep last state
        #readingsBulkUpdateIfChanged( $hash, "state", "Error" );

        # stop pulling for current interval
        Log3($name, 4, "BOTVAC $name: drop successors");
        LogSuccessors($hash, @successor);
        return;
    }

    # data received
    elsif ($data) {

        if ( !defined($cmd) ) {
            Log3($name, 4, "BOTVAC $name: RCV $service");
        } else {
            Log3($name, 4, "BOTVAC $name: RCV $service/$cmd");
        }
        LogSuccessors($hash, @successor);

        if ( $data ne "" ) {
            if ( $service eq "loadmap" ) {
                # use $data later
            } elsif ( $data =~ /^{"message":"Could not find robot_serial for specified vendor_name"}$/ ) {
                # currently no data available
                readingsBulkUpdateIfChanged($hash, "state", "Couldn't find robot");
                readingsEndUpdate( $hash, 1 );
                return;
            } elsif ( $data =~ /^{/ || $data =~ /^\[/ ) {
                if ( !defined($cmd) || $cmd eq "" ) {
                    Log3($name, 4, "BOTVAC $name: RES $service - $data");
                } else {
                    Log3($name, 4, "BOTVAC $name: RES $service/$cmd - $data");
                }
                $return = decode_json( encode_utf8($data) );
            } else {
                Log3($name, 5, "BOTVAC $name: RES ERROR $service\n" . $data);
                if ( !defined($cmd) || $cmd eq "" ) {
                    Log3($name, 5, "BOTVAC $name: RES ERROR $service\n$data");
                } else {
                    Log3($name, 5, "BOTVAC $name: RES ERROR $service/$cmd\n$data");
                }
                return undef;
            }
        }

        # messages
        if ( $service eq "messages" ) {
          if ( $cmd =~ /Schedule/ ) {
            # getSchedule, enableSchedule, disableSchedule
            if ( ref($return->{data}) eq "HASH" ) {
              my $scheduleData = $return->{data};
              readingsBulkUpdateIfChanged($hash, "scheduleEnabled", GetBoolean($scheduleData->{enabled}));
              readingsBulkUpdateIfChanged($hash, "scheduleType",    $scheduleData->{type})
                  if (defined($scheduleData->{type}));

              my %currentEvents;
              foreach ( keys %{ $hash->{READINGS} } ) {
                $currentEvents{$_} = 1 if ( $_ =~ /^event\d.*/ );
              }

              if (ref($scheduleData->{events}) eq "ARRAY") {
                my @events = @{$scheduleData->{events}};
                for (my $i = 0; $i < @events; $i++) {
                  if (defined($events[$i]->{day})) {
                    readingsBulkUpdateIfChanged($hash, "event".$i."day",       GetDayText($events[$i]->{day}));
                    delete $currentEvents{"event".$i."day"};
                  }
                  if (defined($events[$i]->{mode})) {
                    readingsBulkUpdateIfChanged($hash, "event".$i."mode",      GetModeText($events[$i]->{mode}));
                    delete $currentEvents{"event".$i."mode"};
                  }
                  if (defined($events[$i]->{startTime})) {
                    readingsBulkUpdateIfChanged($hash, "event".$i."startTime", $events[$i]->{startTime});
                    delete $currentEvents{"event".$i."startTime"};
                  }
                  if (defined($events[$i]->{type})) {
                    readingsBulkUpdateIfChanged($hash, "event".$i."type",      $events[$i]->{type});
                    delete $currentEvents{"event".$i."type"};
                  }
                  if (defined($events[$i]->{duration})) {
                    readingsBulkUpdateIfChanged($hash, "event".$i."duration",  $events[$i]->{duration});
                    delete $currentEvents{"event".$i."duration"};
                  }
                  if (defined($events[$i]->{mapId})) {
                    readingsBulkUpdateIfChanged($hash, "event".$i."mapId",     $events[$i]->{mapId});
                    delete $currentEvents{"event".$i."mapId"};
                  }
                  if ( ref($events[$i]->{boundary}) eq "HASH" ) {
                    my $boundary = $events[$i]->{boundary};
                    readingsBulkUpdateIfChanged($hash, "event".$i."boundaryId",   $boundary->{id});
                    readingsBulkUpdateIfChanged($hash, "event".$i."boundaryName", $boundary->{name});
                    delete $currentEvents{"event".$i."boundaryId"};
                    delete $currentEvents{"event".$i."boundaryName"};
                  }
                  if ( ref($events[$i]->{recurring}) eq "HASH" ) {
                    my $recurring = $events[$i]->{recurring};
                    readingsBulkUpdateIfChanged($hash, "event".$i."end",     $recurring->{end});
                    delete $currentEvents{"event".$i."end"};
                    if (ref($events[$i]->{days}) eq "ARRAY") {
                      my @days = @{$events[$i]->{days}};
                      my $days_str;
                      for (my $j = 0; $j < @days; $j++) {
                        $days_str .= "," if (defined($days_str));
                        $days_str .= GetDayText($days[$j]->{day});
                      }
                      readingsBulkUpdateIfChanged($hash, "event".$i."days",  $days_str);
                      delete $currentEvents{"event".$i."days"};
                    }
                  }
                  if ( ref($events[$i]->{cmd}) eq "HASH" ) {
                    my $cmd = $events[$i]->{cmd};
                    my $cmd_str = $cmd->{name};
                    if ( ref($cmd->{params}) eq "HASH" ) {
                      $cmd_str .= ":".GetCategoryText($cmd->{category});
                      $cmd_str .= ",".GetModeText($cmd->{mode});
                      $cmd_str .= ",".GetModifierText($cmd->{modifier});
                      $cmd_str .= ",".GetNavigationModeText($cmd->{navigationMode}) if (defined($cmd->{navigationMode}));
                    }
                    readingsBulkUpdateIfChanged($hash, "event".$i."command", $cmd_str);
                    delete $currentEvents{"event".$i."command"};
                  }
                }
              }

              #remove outdated calendar information
              foreach ( keys %currentEvents ) {
                delete( $hash->{READINGS}{$_} );
              }
            }
          }
          elsif ( $cmd eq "getMapBoundaries" ) {
              if ( ref($return->{data}) eq "HASH" ) {
                $reqId = $return->{reqId};
                my $boundariesData = $return->{data};
                if (ref($boundariesData->{boundaries}) eq "ARRAY") {
                  my @boundaries = @{$boundariesData->{boundaries}};
                  my $tmp = "";
                  my $boundariesList = "";
                  my $zonesList = "";
                  for (my $i = 0; $i < @boundaries; $i++) {
                    my $currentBoundary = "{";
                    $currentBoundary .= "\"id\":\"".$boundaries[$i]->{id}."\"," if ($boundaries[$i]->{type} eq "polygon");
                    $currentBoundary .= "\"type\":\"".$boundaries[$i]->{type}."\",";
                    if (ref($boundaries[$i]->{vertices}) eq "ARRAY") {
                      my @vertices = @{$boundaries[$i]->{vertices}};
                      $currentBoundary .= "\"vertices\":[";
                      for (my $e = 0; $e < @vertices; $e++) {
                        if (ref($vertices[$e]) eq "ARRAY") {
                          my @xy = @{$vertices[$e]};
                          $currentBoundary .= "[".$xy[0].",".$xy[1]."],";
                        }
                      }
                      $tmp = chop($currentBoundary);  #remove last ","
                      $currentBoundary .= "],";
                    }
                    $currentBoundary .= "\"name\":\"".$boundaries[$i]->{name}."\",";
                    $currentBoundary .= "\"color\":\"".$boundaries[$i]->{color}."\",";
                    $tmp = $boundaries[$i]->{enabled} eq "1" ? "true" : "false";
                    $currentBoundary .= "\"enabled\":".$tmp.",";
                    $tmp = chop($currentBoundary);  #remove last ","
                    $currentBoundary .= "},\n";
                    if ($boundaries[$i]->{type} eq "polygon") {
                      $zonesList .= $currentBoundary;
                    } else {
                      $boundariesList .= $currentBoundary;
                    }
                  }
                  $tmp = chomp($boundariesList);  #remove last "\n"
                  $tmp = chomp($zonesList);  #remove last "\n"
                  $tmp = chop($boundariesList);  #remove last ","
                  $tmp = chop($zonesList);  #remove last ","
                  readingsBulkUpdateIfChanged($hash, "floorplan_".$reqId."_boundaries", $boundariesList);
                  readingsBulkUpdateIfChanged($hash, "floorplan_".$reqId."_zones", $zonesList);
                }
              }
          }
          elsif ( $cmd eq "getGeneralInfo" ) {
            if ( ref($return->{data}) eq "HASH" ) {
              my $generalInfo = $return->{data};
              if ( ref($generalInfo->{battery}) eq "HASH" ) {
                my $batteryInfo = $generalInfo->{battery};
                readingsBulkUpdateIfChanged($hash, "batteryTimeToEmpty",         $batteryInfo->{timeToEmpty})
                    if (defined($batteryInfo->{timeToEmpty}));
                readingsBulkUpdateIfChanged($hash, "batteryTimeToFullCharge",    $batteryInfo->{timeToFullCharge})
                    if (defined($batteryInfo->{timeToFullCharge}));
                readingsBulkUpdateIfChanged($hash, "batteryTotalCharges",        $batteryInfo->{totalCharges});
                readingsBulkUpdateIfChanged($hash, "batteryManufacturingDate",   $batteryInfo->{manufacturingDate});
                readingsBulkUpdateIfChanged($hash, "batteryAuthorizationStatus", GetAuthStatusText($batteryInfo->{authorizationStatus}));
                readingsBulkUpdateIfChanged($hash, "batteryVendor",              $batteryInfo->{vendor});
              }
            }
          }
          else {
            # getRobotState, startCleaning, pauseCleaning, stopCleaning, resumeCleaning,
            # sendToBase, setMapBoundaries, getRobotManualCleaningInfo, getPreferences
            if ( ref($return) eq "HASH" ) {
              push(@successor , ["robots", "maps"])
                  if ($cmd eq "setMapBoundaries" or
                      (defined($return->{state}) and
                       ($return->{state} == 1 or $return->{state} == 4) and   # Idle or Error
                       $return->{state} != ReadingsNum($name, "stateId", $return->{state})));

              #readingsBulkUpdateIfChanged($hash, "version", $return->{version});
              #readingsBulkUpdateIfChanged($hash, "data", $return->{data});
              readingsBulkUpdateIfChanged($hash, "result", $return->{result}) if (defined($return->{result}));

              if ($cmd eq "getRobotManualCleaningInfo") {
                if ( ref($return->{data}) eq "HASH") {
                  my $data = $return->{data};
                  readingsBulkUpdateIfChanged($hash, "wlanIpAddress", $data->{ip_address});
                  readingsBulkUpdateIfChanged($hash, "wlanPort",      $data->{port});
                  readingsBulkUpdateIfChanged($hash, "wlanSsid",      $data->{ssid});
                  readingsBulkUpdateIfChanged($hash, "wlanToken",     $data->{token}) if (defined($data->{token}));
                  readingsBulkUpdateIfChanged($hash, "wlanValidity",  GetValidityEnd($data->{valid_for_seconds}))
                      if (defined($data->{valid_for_seconds}));
                  wsOpen($hash, $data->{ip_address}, $data->{port});
                } elsif (ReadingsVal($name, "wlanValidity", "") ne "") {
                  readingsBulkUpdateIfChanged($hash, "wlanValidity",  "unavailable");
                }
              }
              if ($cmd eq "getPreferences") {
                if ( ref($return->{data}) eq "HASH") {
                  my $data = $return->{data};
                  foreach my $key (keys %{$return->{data}}) {
                    my $value = $data->{$key};
                    $value /= 43200
                        if ($key =~ /ChangeReminderInterval/ and $value =~ /^[1-9]\d*$/);
                    $value = GetBoolean($value)
                        if ($key =~ /(robotSounds)|(dirtbinAlert)|(allAlerts)|(leds)|(buttonClicks)|(clock24h)/);
                    readingsBulkUpdateIfChanged($hash, "pref_$key", $value);
                  }
                }
              }
              if ( ref($return->{cleaning}) eq "HASH" ) {
                my $cleaning = $return->{cleaning};
                readingsBulkUpdateIfChanged($hash, "cleaningCategory",       GetCategoryText($cleaning->{category}));
                readingsBulkUpdateIfChanged($hash, "cleaningMode",           GetModeText($cleaning->{mode}));
                readingsBulkUpdateIfChanged($hash, "cleaningModifier",       GetModifierText($cleaning->{modifier}));
                readingsBulkUpdateIfChanged($hash, "cleaningNavigationMode", GetNavigationModeText($cleaning->{navigationMode}))
                    if (defined($cleaning->{navigationMode}));
                readingsBulkUpdateIfChanged($hash, "cleaningSpotWidth",      $cleaning->{spotWidth});
                readingsBulkUpdateIfChanged($hash, "cleaningSpotHeight",     $cleaning->{spotHeight});
              }
              if ( ref($return->{details}) eq "HASH" ) {
                my $details = $return->{details};
                readingsBulkUpdateIfChanged($hash, "isCharging",      GetBoolean($details->{isCharging}));
                readingsBulkUpdateIfChanged($hash, "isDocked",        GetBoolean($details->{isDocked}));
                readingsBulkUpdateIfChanged($hash, "scheduleEnabled", GetBoolean($details->{isScheduleEnabled}));
                readingsBulkUpdateIfChanged($hash, "dockHasBeenSeen", GetBoolean($details->{dockHasBeenSeen}));
                readingsBulkUpdateIfChanged($hash, "batteryPercent",  $details->{charge});
              }
              if ( ref($return->{availableCommands}) eq "HASH" ) {
                my $availableCommands = $return->{availableCommands};
                readingsBulkUpdateIfChanged($hash, ".start",    GetBoolean($availableCommands->{start}));
                readingsBulkUpdateIfChanged($hash, ".pause",    GetBoolean($availableCommands->{pause}));
                readingsBulkUpdateIfChanged($hash, ".resume",   GetBoolean($availableCommands->{resume}));
                readingsBulkUpdateIfChanged($hash, ".goToBase", GetBoolean($availableCommands->{goToBase}));
                readingsBulkUpdateIfChanged($hash, ".stop",     GetBoolean($availableCommands->{stop}))
                    unless ($cmd =~ /start.*/ or $cmd eq "getRobotManualCleaningInfo");
              }
              if ( ref($return->{availableServices}) eq "HASH" ) {
                SetServices($hash, $return->{availableServices});
              }
              if ( ref($return->{meta}) eq "HASH" ) {
                my $meta = $return->{meta};
                readingsBulkUpdateIfChanged($hash, "model",    $meta->{modelName});
                readingsBulkUpdateIfChanged($hash, "firmware", $meta->{firmware});
              }
              if (defined($return->{state})){ #State Response
                my $error = ($return->{error}) ? $return->{error} : "";
                readingsBulkUpdateIfChanged($hash, "error", $error);
                my $alert = ($return->{alert}) ? $return->{alert} : "";
                readingsBulkUpdateIfChanged($hash, "alert", $alert);
                readingsBulkUpdateIfChanged($hash, "stateId", $return->{state});
                readingsBulkUpdateIfChanged($hash, "action", $return->{action});
                readingsBulkUpdateIfChanged(
                  $hash,
                  "state",
                  BuildState($hash, $return->{state}, $return->{action}, $return->{error}));
              }
            }
          }
        }

        # Sessions
        elsif ( $service eq "sessions" ) {
          if ( ref($return) eq "HASH" and defined($return->{access_token})) {
            readingsBulkUpdateIfChanged($hash, ".accessToken", $return->{access_token});
          }
        }

        # dashboard
        elsif ( $service eq "dashboard" ) {
          if ( ref($return) eq "HASH" ) {
            if ( ref($return->{robots} ) eq "ARRAY" ) {
              my @robotList = ();
              my @robots = @{$return->{robots}};
              for (my $i = 0; $i < @robots; $i++) {
                my $r = {
                  "name"      => $robots[$i]->{name},
                  "model"     => $robots[$i]->{model},
                  "serial"    => $robots[$i]->{serial},
                  "secretKey" => $robots[$i]->{secret_key},
                  "macAddr"   => $robots[$i]->{mac_address},
                  "nucleoUrl" => $robots[$i]->{nucleo_url}
                };
                $r->{recentFirmware} = $return->{recent_firmwares}{$r->{model}}{version}
                  if ( ref($return->{recent_firmwares} ) eq "HASH" );

                push(@robotList, $r);
              }
              $hash->{helper}{ROBOTS} = \@robotList;
              if (@robotList) {
                SetRobot($hash, ReadingsNum($name, "robot", 0));
                push(@successor , ["robots", "maps"]);
              } else {
                Log3($name, 3, "BOTVAC $name: no robots found");
                Log3($name, 4, "BOTVAC $name: drop successors");
                LogSuccessors($hash, @successor);
                @successor = ();
              }
            }
          }
        }

        # robots
        elsif ( $service eq "robots" ) {
          if ( $cmd eq "maps" ) {
            if ( ref($return) eq "HASH" ) {
              if ( ref($return->{maps} ) eq "ARRAY" ) {
                my @maps = @{$return->{maps}};
                $hash->{helper}{MAPS} = $return->{maps};
                if (@maps) {
                  # take first - newest
                  my $map = $maps[0];
                  foreach my $key (keys %$map) {
                    readingsBulkUpdateIfChanged($hash, "map_".$key, defined($map->{$key})?$map->{$key}:"")
                        if ($key !~ "url|url_valid_for_seconds|generated_at|start_at|end_at");
                  }
                  readingsBulkUpdateIfChanged($hash, "map_date",   GetTimeFromString($map->{generated_at}));
                  readingsBulkUpdateIfChanged($hash, ".map_url",   $map->{url});
                  my $t1 = GetSecondsFromString($map->{end_at});
                  my $t2 = GetSecondsFromString($map->{start_at});
                  my $dt = $t1-$t2-$map->{time_in_suspended_cleaning}-$map->{time_in_error}-$map->{time_in_pause};
                  my $dc = $map->{run_charge_at_start}-$map->{run_charge_at_end};
                  my $expa = int($map->{cleaned_area}*100/$dc+.5) if ($dc > 0);
                  my $expt = int($dt*100/$dc/60+.5) if ($dc > 0);
                  readingsBulkUpdateIfChanged($hash, "map_duration", int($dt/6+.5)/10); # min
                  readingsBulkUpdateIfChanged($hash, "map_expected_area", $expa>0?$expa:0); # qm
                  readingsBulkUpdateIfChanged($hash, "map_run_discharge", $dc>0?$dc:0); # %
                  readingsBulkUpdateIfChanged($hash, "map_expected_time", $expt>0?$expt:0); # min
                  readingsBulkUpdateIfChanged($hash, "map_area_per_time", ($expt>0 and $expa>0)?(int($expa*10/$expt+.5)/10):0); # qm/min
                  readingsBulkUpdateIfChanged($hash, "map_discharge_per_time", ($dt>0 and $dc>0)?(int($dc*600/$dt+.5)/10):0); # %/min
                  $loadMap = 1;
                  # getPersistentMaps
                  push(@successor , ["robots", "persistent_maps"]);
                }
              }
            }
          }
          elsif ( $cmd eq "persistent_maps" ) {
            if ( ref($return) eq "ARRAY" ) {
              my @persistent_maps = @{$return};
              for (my $i = 0; $i < @persistent_maps; $i++) {
                readingsBulkUpdateIfChanged($hash, "floorplan_".$i."_name", $persistent_maps[$i]->{name});
                readingsBulkUpdateIfChanged($hash, "floorplan_".$i."_id", $persistent_maps[$i]->{id});
                # getMapBoundaries
                if (GetServiceVersion($hash, "maps") eq "advanced-1" or
                    GetServiceVersion($hash, "maps") eq "basic-2" or
                    GetServiceVersion($hash, "maps") eq "macro-1"){
                  my %params;
                  $params{"reqId"} = $i;
                  $params{"mapId"} = "\"".$persistent_maps[$i]->{id}."\"";
                  push(@successor , ["messages", "getMapBoundaries", \%params]);
                }
              }
            }
          }
        }

        # loadmap
        elsif ( $service eq "loadmap" ) {
          readingsBulkUpdate($hash, ".map_cache", $data)
        }

        # all other command results
        else {
            Log3($name, 2, "BOTVAC $name: ERROR: method to handle response of $service not implemented");
        }

    }

    readingsEndUpdate( $hash, 1 );

    if ($loadMap) {
      my $url = ReadingsVal($name, ".map_url", "");
      push(@successor , ["loadmap", $url]) if ($url ne "");
    }

    if (@successor) {
      my @nextCmd = @{shift(@successor)};
      my $cmdLength = @nextCmd;
      my $cmdService = $nextCmd[0];
      my $cmdCmd;
      my $cmdOption;
      $cmdCmd    = $nextCmd[1] if ($cmdLength > 1);
      $cmdOption = $nextCmd[2] if ($cmdLength > 2);

      my $cmdReqId;
      my $newReqId = "false";
      if (defined($cmdOption) and ref($cmdOption) eq "HASH" ) {
        if (defined($cmdOption->{reqId})) {
          $cmdReqId = $cmdOption->{reqId};
          $newReqId = "true" if ($reqId ne $cmdReqId);
        }
      }

      SendCommand($hash, $cmdService, $cmdCmd, $cmdOption, @successor)
          if (($service ne $cmdService) or ($cmd ne $cmdCmd) or ($newReqId = "true"));
    }

    return;
}

sub GetTimeFromString($) {
  my ($timeStr) = @_;

  eval {
    use Time::Local;
    if(defined($timeStr) and $timeStr =~ m/^(\d{4})-(\d{2})-(\d{2})T([0-2]\d):([0-5]\d):([0-5]\d)Z$/) {
        my $time = timelocal($6, $5, $4, $3, $2 - 1, $1 - 1900);
        return FmtDateTime($time + fhemTzOffset($time));
    }
  }
}

sub GetSecondsFromString($) {
  my ($timeStr) = @_;

  eval {
    use Time::Local;
    if(defined($timeStr) and $timeStr =~ m/^(\d{4})-(\d{2})-(\d{2})T([0-2]\d):([0-5]\d):([0-5]\d)Z$/) {
        my $time = timelocal($6, $5, $4, $3, $2 - 1, $1 - 1900);
        return $time;
    }
  }
}

sub SetRobot($$) {
    my ( $hash, $robot ) = @_;
    my $name = $hash->{NAME};

    Log3($name, 4, "BOTVAC $name: set active robot $robot");

    my @robots = @{$hash->{helper}{ROBOTS}};
    readingsBulkUpdateIfChanged($hash, "serial",         $robots[$robot]->{serial});
    readingsBulkUpdateIfChanged($hash, "name",           $robots[$robot]->{name});
    readingsBulkUpdateIfChanged($hash, "model",          $robots[$robot]->{model});
    readingsBulkUpdateIfChanged($hash, "firmwareLatest", $robots[$robot]->{recentFirmware})
        if (defined($robots[$robot]->{recentFirmware}));
    readingsBulkUpdateIfChanged($hash, ".secretKey",     $robots[$robot]->{secretKey});
    readingsBulkUpdateIfChanged($hash, "macAddr",        $robots[$robot]->{macAddr});
    readingsBulkUpdateIfChanged($hash, "nucleoUrl",      $robots[$robot]->{nucleoUrl});
    readingsBulkUpdateIfChanged($hash, "robot",          $robot);
}

sub GetCleaningParameter($$$) {
  my ($hash, $param, $default) = @_;
  my $name = $hash->{NAME};

  my $nextReading = "next".ucfirst($param);
  return ReadingsVal($name, $nextReading, ReadingsVal($name, $param, $default));
}

sub GetServiceVersion($$) {
  my ($hash, $service) = @_;
  my $name = $hash->{NAME};

  my $serviceList = InternalVal($name, "SERVICES", "");
  if ($serviceList =~ /$service:([^,]*)/) {
    return $1;
  }
  return "";
}

sub SetServices {
  my ($hash, $services) = @_;
  my $name = $hash->{NAME};
  my $serviceList = join(", ", map { "$_:$services->{$_}" } keys %$services);

  $hash->{SERVICES} = $serviceList if (!defined($hash->{SERVICES}) or $hash->{SERVICES} ne $serviceList);
}

sub StorePassword($$) {
    my ($hash, $password) = @_;
    my $index = $hash->{TYPE}."_".$hash->{NAME}."_passwd";
    my $key = getUniqueId().$index;
    my $enc_pwd = "";

    if(eval "use Digest::MD5;1") {
      $key = Digest::MD5::md5_hex(unpack "H*", $key);
      $key .= Digest::MD5::md5_hex($key);
    }

    for my $char (split //, $password) {
      my $encode=chop($key);
      $enc_pwd.=sprintf("%.2x",ord($char)^ord($encode));
      $key=$encode.$key;
    }

    my $err = setKeyValue($index, $enc_pwd);
    return "error while saving the password - $err" if(defined($err));

    return "password successfully saved";
}

sub ReadPassword($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $index = $hash->{TYPE}."_".$hash->{NAME}."_passwd";
    my $key = getUniqueId().$index;
    my ($password, $err);

    Log3($name, 4, "BOTVAC $name: Read password from file");

    ($err, $password) = getKeyValue($index);

    if ( defined($err) ) {
      Log3($name, 3, "BOTVAC $name: unable to read password from file: $err");
      return undef;
    }

    if ( defined($password) ) {
      if ( eval "use Digest::MD5;1" ) {
        $key = Digest::MD5::md5_hex(unpack "H*", $key);
        $key .= Digest::MD5::md5_hex($key);
      }
      my $dec_pwd = '';
      for my $char (map { pack('C', hex($_)) } ($password =~ /(..)/g)) {
        my $decode=chop($key);
        $dec_pwd.=chr(ord($char)^ord($decode));
        $key=$decode.$key;
      }
      return $dec_pwd;
    } else {
      Log3($name, 3, "BOTVAC $name: No password in file");
      return undef;
    }
}

sub CheckRegistration($$$$$) {
  my ( $hash, $service, $cmd, $option, @successor ) = @_;
  my $name = $hash->{NAME};

  if (ReadingsVal($name, ".secretKey", "") eq "") {
    my @nextCmd = ($service, $cmd, $option);
    unshift(@successor, [$service, $cmd, $option]);

    my @succ_item;
    my $msg = " successor:";
    for (my $i = 0; $i < @successor; $i++) {
      @succ_item = @{$successor[$i]};
      $msg .= " $i: ";
      $msg .= join(",", map { defined($_) ? $_ : '' } @succ_item);
    }
    Log3($name, 4, "BOTVAC created".$msg);

    SendCommand($hash, "sessions", undef, undef, @successor)   if (ReadingsVal($name, ".accessToken", "") eq "");
    SendCommand($hash, "dashboard", undef, undef, @successor)  if (ReadingsVal($name, ".accessToken", "") ne "");

    return 1;
  }

  return;
}

sub GetBoolean($) {
    my ($value) = @_;
    my $booleans = {
        '0'       => "0",
        'false'   => "0",
        '1'       => "1",
        'true'    => "1"
    };

    if (defined( $booleans->{$value})) {
        return $booleans->{$value};
    } else {
        return $value;
    }
}

sub SetBoolean($) {
    my ($value) = @_;
    my $booleans = {
        '0'       => "false",
        'off'     => "false",
        '1'       => "true",
        'on'      => "true"
    };

    if (defined( $booleans->{$value})) {
        return $booleans->{$value};
    } else {
        return $value;
    }
}

sub BuildState($$$$) {
    my ($hash,$state,$action,$error) = @_;
    my $states = {
        '0'       => "Invalid",
        '1'       => "Idle",
        '2'       => "Busy",
        '3'       => "Paused",
        '4'       => "Error"
    };

    if (!defined($state)) {
        return "Unknown";
    } elsif ($state == 2) {
        return GetActionText($action);
    } elsif ($state == 3) {
        return "Paused: ".GetActionText($action);
    } elsif ($state == 4) {
      return GetErrorText($error);
    } elsif (defined( $states->{$state})) {
        return $states->{$state};
    } else {
        return $state;
    }
}

sub GetActionText($) {
    my ($action) = @_;
    my $actions = {
        '0'       => "Invalid",
        '1'       => "House Cleaning",
        '2'       => "Spot Cleaning",
        '3'       => "Manual Cleaning",
        '4'       => "Docking",
        '5'       => "User Menu Active",
        '6'       => "Suspended Cleaning",
        '7'       => "Updating",
        '8'       => "Copying Logs",
        '9'       => "Recovering Location",
        '10'      => "IEC Test",
        '11'      => "Map cleaning",
        '12'      => "Exploring map (creating a persistent map)",
        '13'      => "Acquiring Persistent Map IDs",
        '14'      => "Creating & Uploading Map",
        '15'      => "Suspended Exploration"
    };

    if (defined( $actions->{$action})) {
        return $actions->{$action};
    } else {
        return $action;
    }
}

sub GetErrorText($) {
    my ($error) = @_;
    my $errors = {
        'ui_alert_invalid'                => 'Ok',
        'ui_alert_dust_bin_full'          => 'Dust Bin Is Full!',
        'ui_alert_recovering_location'    => 'I\'m Recovering My Location!',
        'ui_error_picked_up'              => 'Picked Up!',
        'ui_error_brush_stuck'            => 'Brush Stuck!',
        'ui_error_stuck'                  => 'I\'m Stuck!',
        'ui_error_dust_bin_emptied'       => 'Dust Bin Has Been Emptied!',
        'ui_error_dust_bin_missing'       => 'Dust Bin Is Missing!',
        'ui_error_navigation_falling'     => 'Please Clear My Path!',
        'ui_error_navigation_noprogress'  => 'Please Clear My Path!'
    };

    if (defined( $errors->{$error})) {
        return $errors->{$error};
    } else {
        return $error;
    }
}

sub GetDayText($) {
    my ($day) = @_;
    my $days = {
        '0'       => "Sunday",
        '1'       => "Monday",
        '2'       => "Tuesday",
        '3'       => "Wednesday",
        '4'       => "Thursday",
        '5'       => "Friday",
        '6'       => "Saturda"
    };

    if (defined( $days->{$day})) {
        return $days->{$day};
    } else {
        return $day;
    }
}

sub GetCategoryText($) {
    my ($category) = @_;
    my $categories = {
        '1' => 'manual',
        '2' => 'house',
        '3' => 'spot',
        '4' => 'map'
    };

    if (defined($category) && defined($categories->{$category})) {
        return $categories->{$category};
    } else {
        return $category;
    }
}

sub GetModeText($) {
    my ($mode) = @_;
    my $modes = {
        '1' => 'eco',
        '2' => 'turbo'
    };

    if (defined($mode) && defined($modes->{$mode})) {
        return $modes->{$mode};
    } else {
        return $mode;
    }
}

sub GetModifierText($) {
    my ($modifier) = @_;
    my $modifiers = {
        '1' => 'normal',
        '2' => 'double'
    };

    if (defined($modifier) && defined($modifiers->{$modifier})) {
        return $modifiers->{$modifier};
    } else {
        return $modifier;
    }
}

sub GetNavigationModeText($) {
    my ($navMode) = @_;
    my $navModes = {
        '1' => 'normal',
        '2' => 'extra care',
        '3' => 'deep'
    };

    if (defined($navMode) && defined($navModes->{$navMode})) {
        return $navModes->{$navMode};
    } else {
        return $navMode;
    }
}

sub GetAuthStatusText($) {
    my ($authStatus) = @_;
    my $authStatusHash = {
        '0' => 'not supported',
        '1' => 'genuine',
        '2' => 'not genuine'
    };

    if (defined($authStatus) && defined($authStatusHash->{$authStatus})) {
        return $authStatusHash->{$authStatus};
    } else {
        return $authStatus;
    }
}

sub GetBeehiveHost($) {
    my ($vendor) = @_;
    my $vendors = {
        'neato'   => 'beehive.neatocloud.com',
        'vorwerk' => 'vorwerk-beehive-production.herokuapp.com',
    };

    if (defined( $vendors->{$vendor})) {
        return $vendors->{$vendor};
    } else {
        return $vendors->{neato};
    }
}

sub GetNucleoHost($) {
    my ($vendor) = @_;
    my $vendors = {
        'neato'   => 'nucleo.neatocloud.com',
        'vorwerk' => 'nucleo.ksecosys.com',
    };

    if (defined( $vendors->{$vendor})) {
        return $vendors->{$vendor};
    } else {
        return $vendors->{neato};
    }
}

sub GetValidityEnd($) {
    my ($validFor) = @_;
    return ($validFor =~ /\d+/ ? FmtDateTime(time() + $validFor) : $validFor);
}

sub LogSuccessors($@) {
    my ($hash,@successor) = @_;
    my $name = $hash->{NAME};

    my $msg = "BOTVAC $name: successors";
    my @succ_item;
    for (my $i = 0; $i < @successor; $i++) {
      @succ_item = @{$successor[$i]};
      $msg .= " $i: ";
      $msg .= join(",", map { defined($_) ? $_ : '' } @succ_item);
    }
    Log3($name, 4, $msg)  if (@successor > 0);
}

sub ShowMap($;$$) {
    my ($name,$width,$height) = @_;

    my $img = '<img src="/fhem/BOTVAC/'.$name.'/map"';
    $img   .= ' width="'.$width.'"'  if (defined($width));
    $img   .= ' width="'.$height.'"' if (defined($height));
    $img   .= ' alt="Map currently not available">';

    return $img;
}

sub GetMap() {
    my ($request) = @_;

    if ($request =~ /^\/BOTVAC\/(\w+)\/map/) {
      my $name   = $1;
      my $width  = $3;
      my $height = $5;

      return ("image/png", ReadingsVal($name, ".map_cache", ""));
    }

    return ("text/plain; charset=utf-8", "No BOTVAC device for webhook $request");

}

sub ShowStatistics($) {
    my ($name) = @_;
    my $hash  = $::defs{$name};
    
    return "maps for statistics are not available yet"
        if (!defined($hash->{helper}{MAPS}) or @{$hash->{helper}{MAPS}} == 0);

    return GetStatistics($hash);
}

sub GetStatistics($) {
    my($hash) = @_;
    my $name = $hash->{NAME};
    my $mapcount = @{$hash->{helper}{MAPS}};
    my $model = ReadingsVal($name, "model", "");
    my $ret = "";

    $ret .= '<html>';
    $ret .= '<table class="block wide">';
    $ret .= '<caption><b>Report: '.ReadingsVal($name,"name","name").', '.InternalVal($name,"VENDOR","VENDOR").', '.ReadingsVal($name,"model","model").'</b></caption>';
    $ret .= '<tbody>';
    $ret .= '<tr class="col_header">';
    $ret .= ' <td>Map</td><td></td>';
    $ret .= ' <td colspan="3">Expected</td><td></td>';
    $ret .= ' <td>Map</td><td></td>';
    $ret .= ' <td>Map</td><td></td>';
    $ret .= ' <td>Charge</td><td></td>';
    $ret .= ' <td>Discharge</td><td></td>';
    $ret .= ' <td>Area</td><td></td>';
    $ret .= ' <td colspan="5">Cleaning</td><td></td>';
    $ret .= ' <td>Charge</td><td></td>';
    $ret .= ' <td>Status</td><td></td>';
    $ret .= ' <td>Date</td><td></td>';
    $ret .= ' <td>Time</td>';
    $ret .= '</tr><tr class="col_header">';
    $ret .= ' <td>No.</td><td></td>';
    $ret .= ' <td>Area</td><td></td>';
    $ret .= ' <td>Time</td><td></td>';
    $ret .= ' <td>Area</td><td></td>';
    $ret .= ' <td>Time</td><td></td>';
    $ret .= ' <td>Delta</td><td></td>';
    $ret .= ' <td>Speed</td><td></td>';
    $ret .= ' <td>Speed</td><td></td>';
    $ret .= ' <td>Cat.</td><td></td>';
    $ret .= ' <td>Mode</td><td></td>';
    $ret .= ' <td>Freq.</td><td></td>';
    $ret .= ' <td>During</td><td></td>';
    $ret .= ' <td></td><td></td><td></td><td></td><td></td>';
    $ret .= '</tr><tr class="col_header">';
    $ret .= ' <td></td><td></td>';
    $ret .= ' <td>qm</td><td></td>';
    $ret .= ' <td>min</td><td></td>';
    $ret .= ' <td>qm</td><td></td>';
    $ret .= ' <td>min</td><td></td>';
    $ret .= ' <td>%</td><td></td>';
    $ret .= ' <td>%/min</td><td></td>';
    $ret .= ' <td>qm/min</td><td></td>';
    $ret .= ' <td></td><td></td><td></td><td></td><td></td><td></td>';
    $ret .= ' <td>Run</td><td></td>';
    $ret .= ' <td></td><td></td>';
    $ret .= ' <td>YYYY-MM-DD</td><td></td>';
    $ret .= ' <td>hh:mm:ss</td>';
    $ret .= '</tr>';
    for (my $i=0;$i<$mapcount;$i++) {
      my $map = \$hash->{helper}{MAPS}[$i];
      my $t1 = GetSecondsFromString($$map->{end_at});
      my $t2 = GetSecondsFromString($$map->{start_at});
      my $dt = $t1-$t2-$$map->{time_in_suspended_cleaning}-$$map->{time_in_error}-$$map->{time_in_pause};
      my $dc = $$map->{run_charge_at_start}-$$map->{run_charge_at_end};
      my $expa = ($dc > 0 ? int($$map->{cleaned_area}*100/$dc+.5) : 0);
      my $expt = ($dc > 0 ? int($dt*100/$dc/60+.5) : 0);
      my($gen_date,$gen_time) = split(" ", GetTimeFromString($$map->{generated_at}));
      $ret .= '<tr class="'.($i%2?"even":"odd").'">';
      $ret .= ' <td>'.($i+1).'</td><td> </td>'; # Map No.
      $ret .= ' <td>'.($expa>0?$expa:0).'</td><td> </td>'; # Expected Area
      $ret .= ' <td>'.($expt>0?$expt:0).'</td><td> </td>'; # Expected Time
      $ret .= ' <td>'.int($$map->{cleaned_area}+.5).'</td><td> </td>'; # Map Area
      $ret .= ' <td>'.(($dt>0)?(int($dt/60+.5)):0).'</td><td> </td>'; # Map Time
      $ret .= ' <td>'.($dc>0?$dc:0).'</td><td> </td>'; # Charge Delta
      $ret .= ' <td>'.(($dt>0 and $dc>0)?(int($dc*600/$dt+.5)/10):0).'</td><td> </td>'; # Discharge Speed
      $ret .= ' <td>'.(($expt>0 and $expa>0)?(int($expa*10/$expt+.5))/10:0).'</td><td> </td>'; # Area Speed
      $ret .= ' <td>'.GetCategoryText($$map->{category}).'</td><td> </td>'; # Cleaning Category
      $ret .= ' <td>'.GetModeText($$map->{mode}).'</td><td> </td>'; # Cleaning Mode
      $ret .= ' <td>'.GetModifierText($$map->{modifier}).'</td><td> </td>'; # Cleaning Frequency
      $ret .= ' <td>'.$$map->{suspended_cleaning_charging_count}.'x</td><td> </td>'; # Charge During Run
      $ret .= ' <td>'.$$map->{status}.'</td><td> </td>'; # Status
      $ret .= ' <td>'.$gen_date.'</td><td> </td>'; # Date
      $ret .= ' <td>'.$gen_time.'</td>'; # Time
      $ret .= '</tr>';
    }
    $ret .= '</tbody></table>';
    $ret .= "<p><b>Manufacturer Specification:</b><br>";

    my $specification = "$model specification unknown";
    $specification = "Neato Botvac Connected, eco (120 min), turbo (90 min, power 40 W)<br>" if ($model eq "BotVacConnected");
    $specification = "Neato Botvac D3 Connected, up to 60 min<br>" if ($model eq "BotVacD3Connected");
    $specification = "Neato Botvac D4 Connected, up to 75 min<br>" if ($model eq "BotVacD4Connected");
    $specification = "Neato Botvac D5 Connected, up to 90 min<br>" if ($model eq "BotVacD5Connected");
    $specification = "Neato Botvac D6/D7 Connected, up to 120 min<br>" if ($model eq "BotVacD6Connected" or $model eq "BotVacD6Connected");
    $specification = "Vorwerk VR200, battery 84 Wh, eco (90 min, 120 qm, power 50 W), turbo (60 min, 90 qm, power 70 W)<br>" if ($model eq "VR200");
    $specification = "Vorwerk VR220(VR300), battery 84 Wh, eco (90 min, 120 qm, power 65 W), turbo (60 min, 90 qm, power 85 W)<br>" if ($model eq "VR220");

    $ret .= $specification;
    $ret .= '</html>';

    return $ret;
}

#######################################
#       Websocket Functions
#######################################
sub wsOpen($$$) {
    my ($hash,$ip_address,$port) = @_;
    my $name = $hash->{NAME};

    Log3($name, 4, "BOTVAC(ws) $name: Establishing socket connection");
    $hash->{DeviceName} = join(':', $ip_address, $port);

    ::DevIo_CloseDev($hash) if(::DevIo_IsOpen($hash));

    if (::DevIo_OpenDev($hash, 0, "BOTVAC::wsHandshake")) {
      Log3($name, 2, "BOTVAC(ws) $name: ERROR: Can't open websocket to $hash->{DeviceName}");
      readingsSingleUpdate($hash,'result','ws_connect_error',1);
      readingsSingleUpdate($hash,'result','ws_ko',1);
    } else {
      readingsSingleUpdate($hash,'result','ws_ok',1);
    }
}

sub wsClose($) {
    my $hash = shift;
    my $name = $hash->{NAME};
    my $normal_closure =  pack("H*", "03e8");  #code 1000

    Log3($name, 4, "BOTVAC(ws) $name: Closing socket connection");

    wsEncode($hash, $normal_closure, "close");
    delete $hash->{HELPER}{WEBSOCKETS};
    delete $hash->{HELPER}{wsKey};
    readingsSingleUpdate($hash,'state','ws_closed',1) if (::DevIo_CloseDev($hash))
}

sub wsHandshake($) {
    my $hash    = shift;
    my $name    = $hash->{NAME};
    my $host    = ReadingsVal($name, "wlanIpAddress", "");
    my $port    = ReadingsVal($name, "wlanPort", "");
    my $path    = "/drive";
    my $wsKey   = encode_base64(gettimeofday(), '');
    my $serial  = ReadingsVal($name, "serial", "");
    my $now     = time();
    my $date    = FmtDateTimeRFC1123($now);
    my $message = lc($serial) . "\n" . $date . "\n";
    my $hmac    = hmac_sha256_hex($message, ReadingsVal($name, ".secretKey", ""));

    my $wsHandshakeCmd = "GET $path HTTP/1.1\r\n";
    $wsHandshakeCmd   .= "Host: $host:$port\r\n";
    $wsHandshakeCmd   .= "Sec-WebSocket-Key: $wsKey\r\n";
    $wsHandshakeCmd   .= "Sec-WebSocket-Version: 13\r\n";
    $wsHandshakeCmd   .= "Upgrade: websocket\r\n";
    $wsHandshakeCmd   .= "Origin: ws://$host:$port$path\r\n";
    $wsHandshakeCmd   .= "Date: $date\r\n";
    $wsHandshakeCmd   .= "Authorization: NEATOAPP $hmac\r\n";
    $wsHandshakeCmd   .= "Connection: Upgrade\r\n";
    $wsHandshakeCmd   .= "\r\n";

    Log3($name, 4, "BOTVAC(ws) $name: Starting Websocket Handshake");
    wsWrite($hash,$wsHandshakeCmd);

    $hash->{HELPER}{wsKey}  = $wsKey;

    return undef;
}

sub wsCheckHandshake($$) {
    my ($hash,$response) = @_;
    my $name = $hash->{NAME};

    # header in Hash wandeln
    my %header = ();
    foreach my $line (split("\r\n", $response)) {
      my ($key,$value) = split( ": ", $line );
      next if( !$value );
      $value =~ s/^ //;
      Log3($name, 4, "BOTVAC(ws) $name: headertohash |$key|$value|");
      $header{lc($key)} = $value;
    }

    # check handshake
    if( defined($header{'sec-websocket-accept'})) {
      my $keyAccept   = $header{'sec-websocket-accept'};
      Log3($name, 5, "BOTVAC(ws) $name: keyAccept: $keyAccept");
      my $wsKey = $hash->{HELPER}{wsKey};
      my $expectedResponse = trim(encode_base64(pack('H*', sha1_hex(trim($wsKey)."258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))));
      if ($keyAccept eq $expectedResponse) {
        Log3($name, 4, "BOTVAC(ws) $name: Successful WS connection to $hash->{DeviceName}");
        readingsSingleUpdate($hash,'state','ws_connected',1);
        $hash->{HELPER}{WEBSOCKETS} = '1';
      } else {
        wsClose($hash);
        Log3($name, 3, "BOTVAC(ws) $name: ERROR: Unsucessfull WS connection to $hash->{DeviceName}");
        readingsSingleUpdate($hash,'state','ws_handshake-error',1);
      }
    }
    return undef;
}

sub wsWrite($@) {
    my ($hash,$string)  = @_;
    my $name = $hash->{NAME};

    Log3($name, 4, "BOTVAC(ws) $name: WriteFn called:\n$string");
    ::DevIo_SimpleWrite($hash, $string, 0);

    return undef;
}

sub wsRead($) {
    my $hash = shift;
    my $name = $hash->{NAME};
    my $buf;

    Log3($name, 5, "ReadFn started");
    $buf = ::DevIo_SimpleRead($hash);

    return Log3($name, 3, "BOTVAC(ws) $name: no data received") unless( defined $buf);

    if ($hash->{HELPER}{WEBSOCKETS}) {
      Log3($name, 4, "BOTVAC(ws) $name: received data, start response processing:\n".sprintf("%v02X", $buf));
      wsDecode($hash,$buf);
    } elsif( $buf =~ /HTTP\/1.1 101 Switching Protocols/ ) {
      Log3($name, 4, "BOTVAC(ws) $name: received HTTP data string, start response processing:\n$buf");
      BOTVAC::wsCheckHandshake($hash,$buf);
    } else {
      Log3($name, 1, "BOTVAC(ws) $name: corrupted data found:\n$buf");
    }
}

sub wsCallback(@) {
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

        if($err){
        Log3($name, 3, "received callback with error:\n$err");
        } elsif($data){
                Log3($name, 5, "received callback with:\n$data");
             my $parser = $param->{parser};
        &$parser($hash, $data);
                asyncOutput($hash->{HELPER}{CLCONF}, $data) if $hash->{HELPER}{CLCONF};
                delete $hash->{HELPER}{CLCONF};
        } else {
        Log3($name, 2, "received callback without Data and Error String!!!");
    }
   return undef;
}

sub wsReady($) {
    my ($hash) = @_;
    return ::DevIo_OpenDev($hash, 1, "BOTVAC::wsHandshake") if ( $hash->{STATE} eq "disconnected" );
}

# 0                   1                   2                   3
# 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
# +-+-+-+-+-------+-+-------------+-------------------------------+
# |F|R|R|R| opcode|M| Payload len |    Extended payload length    |
# |I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
# |N|V|V|V|       |S|             |   (if payload len==126/127)   |
# | |1|2|3|       |K|             |                               |
# +-+-+-+-+-------+-+-------------+ - - - - - - - - - - - - - - - +
# |     Extended payload length continued, if payload len == 127  |
# + - - - - - - - - - - - - - - - +-------------------------------+
# |                               |Masking-key, if MASK set to 1  |
# +-------------------------------+-------------------------------+
##  | Masking-key (continued)       |          Payload Data         |
# +-------------------------------- - - - - - - - - - - - - - - - +
# :                     Payload Data continued ...                :
# + - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
# |                     Payload Data continued ...                |
# +---------------------------------------------------------------+
# https://tools.ietf.org/html/draft-ietf-hybi-thewebsocketprotocol-17
sub wsEncode($$;$$) {
    my ($hash, $payload, $type, $masked) = @_;
    my $name = $hash->{NAME};
    $type //= "text";
    $masked //= 1;    # Mask   If set to 1, a masking key is present in masking-key. 1 for all frames sent from client to server
    my $RSV = 0;
    my $FIN = 1;    # FIN    Indicates that this is the final fragment in a message. The first fragment MAY also be the final fragment.
    my $MAX_PAYLOAD_SIZE = 65536;
    my $wsString ='';
    $wsString .= pack 'C', ($opcode{$type} | $RSV | ($FIN ? 128 : 0));
    my $len = length($payload);

    Log3($name, 3, "BOTVAC(ws) $name: wsEncode Payload: " . $payload);
    return "payload to big" if ($len > $MAX_PAYLOAD_SIZE);

    if ($len <= 125) {
        $len |= 0x80 if $masked;
        $wsString .= pack 'C', $len;
    } elsif ($len <= 0xffff) {
        $wsString .= pack 'C', 126 + ($masked ? 128 : 0);
        $wsString .= pack 'n', $len;
    } else {
        $wsString .= pack 'C', 127 + ($masked ? 128 : 0);
        $wsString .= pack 'N', $len >> 32;
        $wsString .= pack 'N', ($len & 0xffffffff);
    }
    if ($masked) {
        my $mask = pack 'N', int(rand(2**32));
    $wsString .= $mask;
    $wsString .= wsMasking($payload, $mask);
    } else {
        $wsString .= $payload;
    }

    Log3($name, 3, "BOTVAC(ws) $name: String: " . unpack('H*',$wsString));
    wsWrite($hash, $wsString);
}

sub wsPong($) {
    my $hash = shift;
    my $name = $hash->{NAME};
    Log3($name, 3, "BOTVAC(ws) $name: wsPong");
    wsEncode($hash, undef, "pong");
}

sub wsDecode($$) {
    my ($hash,$wsString) = @_;
    my $name = $hash->{NAME};

    Log3($name, 5, "BOTVAC(ws) $name: String:\n" . $wsString);

    while (length $wsString) {
      my $FIN =    (ord(substr($wsString,0,1)) & 0b10000000) >> 7;
      my $OPCODE = (ord(substr($wsString,0,1)) & 0b00001111);
      my $masked = (ord(substr($wsString,1,1)) & 0b10000000) >> 7;
      my $len =    (ord(substr($wsString,1,1)) & 0b01111111);
      Log3($name, 4, "BOTVAC(ws) $name: wsDecode FIN:$FIN OPCODE:$OPCODE MASKED:$masked LEN:$len");

      my $offset = 2;
      if ($len == 126) {
        $len = unpack 'n', substr($wsString,$offset,2);
        $offset += 2;
      } elsif ($len == 127) {
        $len = unpack 'q', substr($wsString,$offset,8);
        $offset += 8;
      }
      my $mask;
      if($masked) {                     # Mask auslesen falls Masked Bit gesetzt
        $mask = substr($wsString,$offset,4);
        $offset += 4;
      }
      #String kürzer als Längenangabe -> Zwischenspeichern?
      if (length($wsString) < $offset + $len) {
        Log3($name, 3, "BOTVAC(ws) $name: wsDecode Incomplete:\n" . $wsString);
        return;
      }
      my $payload = substr($wsString, $offset, $len);     # Daten aus String extrahieren
      if ($masked) {                      # Daten demaskieren falls maskiert
         $payload = Neuron_wsMasking($payload, $mask);
      }
      Log3($name, 5, "BOTVAC(ws) $name: wsDecode Payload:\n" . $payload);
      $wsString = substr($wsString,$offset+$len);       # ausgewerteten Stringteil entfernen
      if ($FIN) {
        wsPong($hash) if ($OPCODE == $opcode{"ping"});
      }
    }
}

sub wsMasking($$) {
    my ($payload, $mask) = @_;
    $mask = $mask x (int(length($payload) / 4) + 1);
    $mask = substr($mask, 0, length($payload));
    $payload = $payload ^ $mask;
    return $payload;
}

1;
=pod
=item device
=item summary     Robot Vacuums
=item summary_DE  Staubsauger Roboter

=begin html

<a name="BOTVAC"></a>
<h3>BOTVAC</h3>
<ul>
  This module controls Neato Botvac Connected and Vorwerk Robot Vacuums.<br/>
  For issuing commands or retrieving Readings it's necessary to fetch the information from the NEATO/VORWERK Server.
  In this way, it can happen, that it's not possible to send commands to the Robot until the corresponding Values are fetched.
  This means, it can need some time until your Robot will react on your command.
  <br/><br/>

<a name="BOTVACDefine"></a>
<b>Define</b>
<ul>
  <br>
  <code>define &lt;name&gt; BOTVAC &lt;email&gt; [NEATO|VORWERK] [&lt;polling-interval&gt;]</code>
  <br/><br/>
  Example:&nbsp;<code>define myNeato BOTVAC myemail@myprovider.com NEATO 300</code>
  <br/><br/>

  After defining the Device, it's necessary to enter the password with "set &lt;name&gt; password &lt;password&gt;"<br/>
  It is exactly the same Password as you use on the Website or inside the App.
  <br/><br/>
  Example:&nbsp;<code>set NEATO passwort mySecretPassword</code>
  <br/><br/>
</ul>

<a name="BOTVACget"></a>
<b>Get</b>
<ul>
<br>
  <a name="batteryPercent"></a>
  <li><code>get &lt;name&gt; batteryPercent</code>
  <br>
  requests the state of the battery from Robot
  </li>
<br>
  <a name="statistics"></a>
  <li><code>get &lt;name&gt; statistics</code>
  <br>
  display statistical data, extracted from available maps of recent cleanings
  </li>
<br>
</ul>

<a name="BOTVACset"></a>
<b>Set</b>
<ul>
<br>
  <li>
  <a name="findMe"></a>
  <code> set &lt;name&gt; findMe</code>
  <br>
  plays a sound and let the LED light for easier finding of a stuck robot
  </li>
<br>
  <li>
  <a name="dismissCurrentAlert"></a>
  <code> set &lt;name&gt; dismissCurrentAlert</code>
  <br>
        reset an actual Warning (e.g. dustbin full)
  </li>
<br>
  <li>
  <a name="nextCleaningMode"></a>
  <code> set &lt;name&gt; nextCleaningMode</code>
  <br>
  Depending on Model, there are Arguments available: eco/turbo
  </li>
<br>
  <li>
  <a name="nextCleaningModifier"></a>
  <code> set &lt;name&gt; nextCleaningModifier</code>
  <br>
   The modifier is used for next spot cleaning.
   Depending on Model, there are Arguments available: normal/double
  </li>
<br>
  <li>
  <a name="nextCleaningNavigationMode"></a>
  <code> set &lt;name&gt; nextCleaningNavigationMode</code>
  <br>
   The navigation mode is used for the next house cleaning.
   Depending on Model, there are Arguments available: normal/extraCare/deep
  </li>
<br>
  <li>
  <a name="nextCleaningZone"></a>
  <code> set &lt;name&gt; nextCleaningZone</code>
  <br>
  Depending on Model, the ID of the zone that will be used for the next zone cleaning can be set.
  </li>
<br>
  <li>
  <a name="nextCleaningSpotHeight"></a>
  <code> set &lt;name&gt; nextCleaningSpotHeight</code>
  <br>
  Is defined as number between 100 - 400. The unit is cm.
  </li>
<br>
  <li>
  <a name="nextCleaningSpotWidth"></a>
  <code> set &lt;name&gt; nextCleaningSpotWidth</code>
  <br>
  Is defined as number between 100 - 400. The unit is cm.
  </li>
<br>
  <li>
  <a name="password"></a>
  <code> set &lt;name&gt; password &lt;password&gt;</code>
  <br>
        set the password for the NEATO/VORWERK account
  </li>
<br>
  <li>
  <a name="pause"></a>
  <code> set &lt;name&gt; pause</code>
  <br>
        interrupts the cleaning
  </li>
<br>
  <li>
  <a name="pauseToBase"></a>
  <code> set &lt;name&gt; pauseToBase</code>
  <br>
  stops cleaning and returns to base
  </li>
<br>
  <li>
  <a name="reloadMaps"></a>
  <code> set &lt;name&gt; reloadMaps</code>
  <br>
        load last map from server into the cache of the module. no file is stored!
  </li>
<br>
  <li>
  <a name="resume"></a>
  <code> set &lt;name&gt; resume</code>
  <br>
  resume cleaning after pause
  </li>
<br>
  <li>
  <a name="schedule"></a>
  <code> set &lt;name&gt; schedule</code>
  <br>
        on and off, switch time control
  </li>
<br>
  <li>
  <a name="sendToBase"></a>
  <code> set &lt;name&gt; sendToBase</code>
  <br>
  send roboter back to base
  </li>
<br>
  <li>
  <a name="setBoundariesOnFloorplan"></a>
  <code> set &lt;name&gt; setBoundariesOnFloorplan_&lt;floor plan&gt; &lt;name|{JSON String}&gt;</code>
  <br>
    Set boundaries/nogo lines in the corresponding floor plan.<br>
    The paramter can either be a name, which is already defined by attribute "boundaries", or alternatively a JSON string.
    (A comma-separated list of names is also possible.)<br>
    Description of syntax at <a href>https://developers.neatorobotics.com/api/robot-remote-protocol/maps</a><br>
    <br>
    Examples:<br>
    set &lt;name&gt; setBoundariesOnFloorplan_0 Bad<br>
    set &lt;name&gt; setBoundariesOnFloorplan_0 Bad,Kueche<br>
    set &lt;name&gt; setBoundariesOnFloorplan_0 {"type":"polyline","vertices":[[0.710,0.6217],[0.710,0.6923]],
      "name":"Bad","color":"#E54B1C","enabled":true}
  </li>
<br>
  <li>
  <a name="setRobot"></a>
  <code> set &lt;name&gt; setRobot</code>
  <br>
  choose robot if more than one is registered at the used account
  </li>
<br>
  <li>
  <a name="startCleaning"></a>
  <code> set &lt;name&gt; startCleaning ([house|map|zone])</code>
  <br>
  start the Cleaning from the scratch.
  If the robot supports boundaries/nogo lines/zones, the additional parameter can be used as:
  <ul>
  <li><code>house</code> - cleaning without a persisted map</li>
  <li><code>map</code> - cleaning with a persisted map</li>
  <li><code>zone</code> - cleaning in a specific zone, set zone with nextCleaningZone</li>
  </ul>
  </li>
<br>
  <li>
  <a name="startSpot"></a>
  <code> set &lt;name&gt; startSpot</code>
  <br>
  start spot-Cleaning from actual position.
  </li>
<br>
  <li>
  <a name="startManual"></a>
  <code> set &lt;name&gt; startManual</code>
  <br>
  start Manual Cleaning. This cleaning mode opens a direct websocket connection to the robot.
  Therefore robot and FHEM installation has to reside in the same LAN.
  Even though an internet connection is necessary as the initialization is triggered by a remote call.
  <br>
  <em>Note:</em> If the robot does not receive any messages for 30 seconds it will exit Manual Cleaning,
  but it will not close the websocket connection automaticaly.
  </li>
<br>
  <li>
  <a name="statusRequest"></a>
  <code> set &lt;name&gt; statusRequest</code>
  <br>
  pull update of all readings. necessary because NEATO/VORWERK does not send updates at their own.
  </li>
<br>
  <li>
  <a name="stop"></a>
  <code> set &lt;name&gt; stop</code>
  <br>
  stop cleaning and in case of manual cleaning mode close also the websocket connection.
  </li>
<br>
  <li>
  <a name="syncRobots"></a>
  <code> set &lt;name&gt; syncRobots</code>
  <br>
  sync robot data with online account. Useful if one has more then one robot registered.
  </li>
<br>
  <li>
  <a name="pollingMode"></a>
  <code> set &lt;name&gt; pollingMode &lt;on|off&gt;</code>
  <br>
  set polling on (default) or off like attribut disable.
  </li>
<br>
  <li>
  <a name="robotSounds"></a>
  <code> set &lt;name&gt; robotSounds &lt;on|off&gt;</code>
  <br>
  set sounds on or off.
  </li>
<br>
  <li>
  <a name="dirtbinAlertReminderInterval"></a>
  <code> set &lt;name&gt; dirtbinAlertReminderInterval &lt;30|60|90|120|150&gt;</code>
  <br>
  set alert intervall in minutes.
  </li>
<br>
  <li>
  <a name="filterChangeReminderInterval"></a>
  <code> set &lt;name&gt; filterChangeReminderInterval &lt;1|2|3&gt;</code>
  <br>
  set alert intervall in months.
  </li>
<br>
  <li>
  <a name="brushChangeReminderInterval"></a>
  <code> set &lt;name&gt; brushChangeReminderInterval &lt;4|5|6|7|8&gt;</code>
  <br>
  set alert intervall in months.
  </li>
<br>
  <li>
  <a name="wsCommand"></a>
  <code> set &lt;name&gt; wsCommand</code>
  <br>
  Commands start or stop cleaning activities.
  <ul>
  <li><code>eco-on</code></li>
  <li><code>eco-off</code></li>
  <li><code>turbo-on</code></li>
  <li><code>turbo-off</code></li>
  <li><code>brush-on</code></li>
  <li><code>brush-off</code></li>
  <li><code>vacuum-on</code></li>
  <li><code>vacuum-off</code></li>
  </ul>
  </li>
<br>
  <li>
  <a name="wsCombo"></a>
  <code> set &lt;name&gt; wsCombo</code>
  <br>
  Combos specify a behavior on the robot. They need to be sent with less than 1Hz frequency.
  If the robot doesn't receive a combo with the specified frequency it will stop moving.
  <ul>
  <li><code>forward</code> issues a continuous forward motion.</li>
  <li><code>back</code> issues a discontinuous backward motion in ~30cm intervals as a safety measure since the robot has no sensors at the back.</li>
  <li><code>arc-left</code> issues a 450 turn counter-clockwise while going forward.</li>
  <li><code>arc-right</code> issues a 450 turn clockwise while going forward.</li>
  <li><code>pivot-left</code> issues a 900 turn counter-clockwise.</li>
  <li><code>pivot-right</code> issues a 900 turn clockwise.</li>
  <li><code>stop</code> issues an immediate stop.</li>
  </ul>
  Also, if the robot does not receive any messages for 30 seconds it will exit Manual Cleaning.
  </li>
<br>
</ul>
<a name="BOTVACattr"></a>
<b>Attributes</b>
<ul>
<br>
  <li>
  <a name="actionInterval"></a>
  <code>actionInterval</code>
  <br>
  time in seconds between status requests while Device is working
  </li>
<br>
  <li>
  <a name="boundaries"></a>
  <code>boundaries</code>
  <br>
  Boundary entries separated by whitespace in JSON format, e.g.<br>
  {"type":"polyline","vertices":[[0.710,0.6217],[0.710,0.6923]],"name":"Bad","color":"#E54B1C","enabled":true}<br>
  {"type":"polyline","vertices":[[0.7139,0.4101],[0.7135,0.4282],[0.4326,0.3322],[0.4326,0.2533],[0.3931,0.2533],
    [0.3931,0.3426],[0.7452,0.4637],[0.7617,0.4196]],"name":"Kueche","color":"#000000","enabled":true}<br>
  For description of syntax see: <a href>https://developers.neatorobotics.com/api/robot-remote-protocol/maps</a><br>
  The value of paramter "name" is used as setListe for "setBoundariesOnFloorplan_&lt;floor plan&gt;".
  It is also possible to save more than one boundary with the same name.
  The command "setBoundariesOnFloorplan_&lt;floor plan&gt; &lt;name&gt;" sends all boundary with the same name.
  </li>
<br>
</ul>

</ul>

=end html
=cut
