###############################################################################
#
#  $Id$
# 
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#
#
################################################################################

package FHEM::AutomowerConnectDevice;
use strict;
use warnings;
use POSIX;

# wird für den Import der FHEM Funktionen aus der fhem.pl benötigt
use GPUtils qw(:all);

use Time::HiRes qw(gettimeofday);
use Blocking;
use Storable qw(dclone store retrieve);

# Import der FHEM Funktionen
BEGIN {
    GP_Import(
        qw(
          AttrVal
          CommandAttr
          fhemTzOffset
          FmtDateTime
          getKeyValue
          InternalTimer
          InternalVal
          IsDisabled
          Log3
          readingFnAttributes
          readingsBeginUpdate
          readingsBulkUpdate
          readingsBulkUpdateIfChanged
          readingsDelete
          readingsEndUpdate
          ReadingsNum
          readingsSingleUpdate
          ReadingsVal
          RemoveInternalTimer
          setKeyValue
          defs
          attr
          modules
          deviceEvents
          devspec2array
          )
    );
}

GP_Export(
    qw(
      Initialize
      )
);

my $missingModul = "";

eval "use JSON;1" or $missingModul .= "JSON ";
require HttpUtils;

use constant AUTHURL => 'https://api.authentication.husqvarnagroup.dev/v1';
use constant APIURL => 'https://api.amc.husqvarna.dev/v1';

##############################################################

sub Initialize() {
  my ($hash) = @_;

  $hash->{SetFn}      = \&Set;
  $hash->{GetFn}      = \&Get;
  $hash->{DefFn}      = \&Define;
  $hash->{UndefFn}    = \&Undef;
  $hash->{NotifyFn}   = \&Notify;
  $hash->{FW_detailFn}= \&FW_detailFn;
  $hash->{AttrFn}     = \&Attr;
  $hash->{AttrList}   = "disable:1,0 " .
                        "debug:1,0 " .
                        "disabledForIntervals " .
                        "mapImagePath " .
                        "mapImageWidthHeight " .
                        "mapImageCoordinatesToRegister:textField-long " .
                        "mapImageCoordinatesUTM:textField-long " .
                        "mapImageZoom " .
                        "showMap:1,0 " .
                        "chargingStationCoordinates " .
                        "chargingStationImagePosition:left,top,right,bottom,center " .
                        "scaleToMeterXY " .
                        "mowerCuttingWidth " .
                        "mowerSchedule:textField-long " .
                        "mowingAreaLimits:textField-long " .
                        "propertyLimits:textField-long " .
                        "numberOfWayPointsToDisplay " .
                        $readingFnAttributes;

  return undef;
}


##############################################################
#
# DEFINE
#
##############################################################

sub Define{
  my ( $hash, $def ) = @_;
  my @val = split( "[ \t]+", $def );
  my $name = $val[0];
  my $type = $val[1];
  my $iam = "$type $name Define:";

  return "$iam too few parameters: define <NAME> $type <host name> <mower number>" if( @val < 4 ) ;
  return "$iam Cannot define $type device. Perl modul $missingModul is missing." if ( $missingModul );
  my $hostname =$val[2];
  my $mowerNumber = $val[3];
  
  ::notifyRegexpChanged($hash, $hostname.':state:.connected');
  
  %$hash = (%$hash,
    helper => {
      hostname                  => $hostname,
      mowerNumber               => $mowerNumber,
      scaleToMeterLongitude     => 67425,
      scaleToMeterLatitude      => 108886,
      MAP_PATH                  => '',
      MAP_MIME                  => '',
      MAP_CACHE                 => '',
      UNKNOWN                   => {
        arrayName               => '',
        maxLength               => 0,
        callFn                  => ''
      },
      NOT_APPLICABLE            => {
        arrayName               => '',
        maxLength               => 0,
        callFn                  => ''
      },
      MOWING                    => {
        arrayName               => 'areapos',
        maxLength               => 500,
        maxLengthDefault        => 500,
        callFn                  => \&AreaStatistics
      },
      GOING_HOME                => {
        arrayName               => '',
        maxLength               => 0,
        callFn                  => ''
      },
      CHARGING                  => {
        arrayName               => 'cspos',
        maxLength               => 500,
        callFn                  => \&ChargingStationPosition
      },
      LEAVING                   => {
        arrayName               => '',
        maxLength               => 0,
        callFn                  => ''
      },
      PARKED_IN_CS              => {
        arrayName               => 'cspos',
        maxLength               => 50,
        callFn                  => \&ChargingStationPosition
      },
      STOPPED_IN_GARDEN         => {
        arrayName               => '',
        maxLength               => 0,
        callFn                  => ''
      }
    }
  );
  

my $errorjson = <<'EOF';
{"23":"Wheel drive problem, left","24":"Cutting system blocked","123":"Destination not reachable","710":"SIM card locked","50":"Guide 1 not found","717":"SMS could not be sent","108":"Folding cutting deck sensor defect","4":"Loop sensor problem, front","15":"Lifted","29":"Slope too steep","1":"Outside working area","45":"Cutting height problem, dir","52":"Guide 3 not found","28":"Memory circuit problem","95":"Folding sensor activated","9":"Trapped","114":"Too high discharge current","103":"Cutting drive motor 2 defect","65":"Temporary battery problem","119":"Zone generator problem","6":"Loop sensor problem, left","82":"Wheel motor blocked, rear right","714":"Geofence problem","703":"Connectivity problem","708":"SIM card locked","75":"Connection changed","7":"Loop sensor problem, right","35":"Wheel motor overloaded, right","3":"Wrong loop signal","117":"High internal power loss","0":"Unexpected error","80":"Cutting system imbalance - Warning","110":"Collision sensor error","100":"Ultrasonic Sensor 3 defect","79":"Invalid battery combination - Invalid combination of different battery types.","724":"Communication circuit board SW must be updated","86":"Wheel motor overloaded, rear right","81":"Safety function faulty","78":"Slipped - Mower has Slipped.Situation not solved with moving pattern","107":"Docking sensor defect","33":"Mower tilted","69":"Alarm! Mower switched off","68":"Temporary battery problem","34":"Cutting stopped - slope too steep","127":"Battery problem","73":"Alarm! Mower in motion","74":"Alarm! Outside geofence","713":"Geofence problem","87":"Wheel motor overloaded, rear left","120":"Internal voltage error","39":"Cutting motor problem","704":"Connectivity problem","63":"Temporary battery problem","109":"Loop sensor defect","38":"Electronic problem","64":"Temporary battery problem","113":"Complex working area","93":"No accurate position from satellites","104":"Cutting drive motor 3 defect","709":"SIM card not found","94":"Reference station communication problem","43":"Cutting height problem, drive","13":"No drive","44":"Cutting height problem, curr","118":"Charging system problem","14":"Mower lifted","57":"Guide calibration failed","707":"SIM card requires PIN","99":"Ultrasonic Sensor 2 defect","98":"Ultrasonic Sensor 1 defect","51":"Guide 2 not found","56":"Guide calibration accomplished","49":"Ultrasonic problem","2":"No loop signal","124":"Destination blocked","25":"Cutting system blocked","19":"Collision sensor problem, front","18":"Collision sensor problem, rear","48":"No response from charger","105":"Lift Sensor defect","111":"No confirmed position","10":"Upside down","40":"Limited cutting height range","716":"Connectivity problem","27":"Settings restored","90":"No power in charging station","21":"Wheel motor blocked, left","26":"Invalid sub-device combination","92":"Work area not valid","702":"Connectivity settings restored","125":"Battery needs replacement","5":"Loop sensor problem, rear","12":"Empty battery","55":"Difficult finding home","42":"Limited cutting height range","30":"Charging system problem","72":"Alarm! Mower tilted","85":"Wheel drive problem, rear left","8":"Wrong PIN code","62":"Temporary battery problem","102":"Cutting drive motor 1 defect","116":"High charging power loss","122":"CAN error","60":"Temporary battery problem","705":"Connectivity problem","711":"SIM card locked","70":"Alarm! Mower stopped","32":"Tilt sensor problem","37":"Charging current too high","89":"Invalid system configuration","76":"Connection NOT changed","71":"Alarm! Mower lifted","88":"Angular sensor problem","701":"Connectivity problem","715":"Connectivity problem","61":"Temporary battery problem","66":"Battery problem","106":"Collision sensor defect","67":"Battery problem","112":"Cutting system major imbalance","83":"Wheel motor blocked, rear left","84":"Wheel drive problem, rear right","126":"Battery near end of life","77":"Com board not available","36":"Wheel motor overloaded, left","31":"STOP button problem","17":"Charging station blocked","54":"Weak GPS signal","47":"Cutting height problem","53":"GPS navigation problem","121":"High internal temerature","97":"Left brush motor overloaded","712":"SIM card locked","20":"Wheel motor blocked, right","91":"Switch cord problem","96":"Right brush motor overloaded","58":"Temporary battery problem","59":"Temporary battery problem","22":"Wheel drive problem, right","706":"Poor signal quality","41":"Unexpected cutting height adj","46":"Cutting height blocked","11":"Low battery","16":"Stuck in charging station","101":"Ultrasonic Sensor 4 defect","115":"Too high internal current"}
EOF
  my $errortable = eval { decode_json ($errorjson) };
  if ($@) {
    return "$iam $@";
  }

  $hash->{helper}{errortable} = $errortable;
  $errorjson = undef;
  $errortable = undef;

  $attr{$name}{room} = $type if( !defined( $attr{$name}{room} ) );
  $attr{$name}{icon} = 'automower' if( !defined( $attr{$name}{icon} ) );
  if (::AnalyzeCommandChain(undef,"version 75_AutomowerConnectDevice.pm noheader") =~ "^75_AutomowerConnectDevice.pm (.*)Z") {
    $hash->{VERSION}=$1;
  }

  RemoveInternalTimer($hash);
  InternalTimer( gettimeofday() + 25, \&readMap, $hash, 0);

  AddExtension( $name, \&GetMap, "$type/$name/map" );

  
  readingsSingleUpdate( $hash, 'state', 'defined', 1 );

  return undef;

}


##############################################################
#
# GET MOWER
#
##############################################################

sub Notify {
  
  my ($hash,$hosthash) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $iam = "$type $name Notify:";
  my $mowerNumber = $hash->{helper}{mowerNumber};
  my $events = ::deviceEvents($hosthash,1);

  if ( IsDisabled($name) ) {

    return undef 

  }

  if ( grep /^state:.connected$/, @{$events} ) {

    my $maxMower = 0;
    $maxMower = @{$hosthash->{helper}{mowers}} if ( ref ( $hosthash->{helper}{mowers} ) eq 'ARRAY' );
    if ($maxMower <= $mowerNumber || $mowerNumber < 0 ) {

      Log3 $name, 2, "$iam wrong mower number $mowerNumber ($maxMower mower available). Change definition of $name.";
      return undef;

    }

    my $mowerhash = $hosthash->{helper}{mowers}[$mowerNumber];
    my $myMower = dclone( $mowerhash );
    if ( defined ($hash->{helper}{mower}{id}) ){

      $hash->{helper}{mowerold} = dclone( $hash->{helper}{mower} );
      
    } else {

      $hash->{helper}{mowerold} = $myMower;
      
      $hash->{helper}{searchpos} = [ dclone( $hash->{helper}{mowerold}{attributes}{positions}[0] ), dclone( $hash->{helper}{mowerold}{attributes}{positions}[1] ) ];

      $hash->{helper}{areapos} = [ dclone( $hash->{helper}{mowerold}{attributes}{positions}[0] ), dclone( $hash->{helper}{mowerold}{attributes}{positions}[1] ) ];
      $hash->{helper}{areapos}[0]{statusTimestamp} = $hash->{helper}{mowerold}{attributes}{metadata}{statusTimestamp};
      $hash->{helper}{areapos}[1]{statusTimestamp} = $hash->{helper}{mowerold}{attributes}{metadata}{statusTimestamp} - 12000;

      $hash->{helper}{cspos} = [ dclone( $hash->{helper}{mowerold}{attributes}{positions}[0] ), dclone( $hash->{helper}{mowerold}{attributes}{positions}[1] ) ];
      $hash->{helper}{cspos}[0]{statusTimestamp} = $hash->{helper}{mowerold}{attributes}{metadata}{statusTimestamp};
      $hash->{helper}{cspos}[1]{statusTimestamp} = $hash->{helper}{mowerold}{attributes}{metadata}{statusTimestamp} - 600000;
    }

    $hash->{helper}{mower} = $myMower;
    my $storediff = $hash->{helper}{mower}{attributes}{metadata}{statusTimestamp} - $hash->{helper}{mowerold}{attributes}{metadata}{statusTimestamp};
    if ($storediff) {
      AlignArray( $hash );
      FW_detailFn_Update ($hash) if (AttrVal($name,'showMap',1));

    }


    
    readingsBeginUpdate($hash);

      readingsBulkUpdateIfChanged($hash, "batteryPercent", $hash->{helper}{mower}{attributes}{battery}{batteryPercent} ); 
      my $pref = 'mower';
      readingsBulkUpdateIfChanged($hash, $pref.'_id', $hash->{helper}{mower}{id} );
      readingsBulkUpdateIfChanged($hash, $pref.'_mode', $hash->{helper}{mower}{attributes}{$pref}{mode} );
      readingsBulkUpdateIfChanged($hash, $pref.'_activity', $hash->{helper}{mower}{attributes}{$pref}{activity} );
      readingsBulkUpdateIfChanged($hash, $pref.'_state', $hash->{helper}{mower}{attributes}{$pref}{state} );
      readingsBulkUpdateIfChanged($hash, $pref.'_commandStatus', 'cleared' );
      my $tstamp = $hash->{helper}{mower}{attributes}{$pref}{errorCodeTimestamp};
      my $timestamp = FmtDateTime($tstamp/1000);
      readingsBulkUpdateIfChanged($hash, $pref."_errorCodeTimestamp", $tstamp ? $timestamp : '-' );
      my $errc = $hash->{helper}{mower}{attributes}{$pref}{errorCode};
      readingsBulkUpdateIfChanged($hash, $pref.'_errorCode', $tstamp ? $errc  : '-');
      my $errd = $hash->{helper}{errortable}{$errc};
      readingsBulkUpdateIfChanged($hash, $pref.'_errorDescription', $tstamp ? $errd : '-');
      $pref = 'system';
      readingsBulkUpdateIfChanged($hash, $pref."_name", $hash->{helper}{mower}{attributes}{$pref}{name} );
      my $model = $hash->{helper}{mower}{attributes}{$pref}{model};
      $model =~ s/AUTOMOWER./AUTOMOWER®/;
      $hash->{MODEL} = $model if ( $model && $hash->{MODEL} ne $model );
      # readingsBulkUpdateIfChanged($hash, $pref."_model", $model );
      readingsBulkUpdateIfChanged($hash, $pref."_serialNumber", $hash->{helper}{mower}{attributes}{$pref}{serialNumber} );
      $pref = 'planner';
      readingsBulkUpdateIfChanged($hash, "planner_restrictedReason", $hash->{helper}{mower}{attributes}{$pref}{restrictedReason} );
      readingsBulkUpdateIfChanged($hash, "planner_overrideAction", $hash->{helper}{mower}{attributes}{$pref}{override}{action} );
      
      $tstamp = $hash->{helper}{mower}{attributes}{$pref}{nextStartTimestamp};
      $timestamp = FmtDateTime($tstamp/1000);
      readingsBulkUpdateIfChanged($hash, "planner_nextStart", $tstamp ? $timestamp : '-' );  
      $pref = 'statistics';
      readingsBulkUpdateIfChanged($hash, $pref."_numberOfChargingCycles", $hash->{helper}->{mower}{attributes}{$pref}{numberOfChargingCycles} );
      readingsBulkUpdateIfChanged($hash, $pref."_totalCuttingTime", $hash->{helper}->{mower}{attributes}{$pref}{totalCuttingTime} );
      readingsBulkUpdateIfChanged($hash, $pref."_totalChargingTime", $hash->{helper}->{mower}{attributes}{$pref}{totalChargingTime} );
      readingsBulkUpdateIfChanged($hash, $pref."_totalSearchingTime", $hash->{helper}->{mower}{attributes}{$pref}{totalSearchingTime} );
      readingsBulkUpdateIfChanged($hash, $pref."_numberOfCollisions", $hash->{helper}->{mower}{attributes}{$pref}{numberOfCollisions} );
      readingsBulkUpdateIfChanged($hash, $pref."_totalRunningTime", $hash->{helper}->{mower}{attributes}{$pref}{totalRunningTime} );
      $pref = 'settings';
      readingsBulkUpdateIfChanged($hash, $pref."_headlight", $hash->{helper}->{mower}{attributes}{$pref}{headlight}{mode} );
      readingsBulkUpdateIfChanged($hash, $pref."_cuttingHeight", $hash->{helper}->{mower}{attributes}{$pref}{cuttingHeight} );
      $pref = 'status';
      readingsBulkUpdateIfChanged($hash, $pref."_connected", $hash->{helper}{mower}{attributes}{metadata}{connected} );
      readingsBulkUpdateIfChanged($hash, $pref."_Timestamp", FmtDateTime( $hash->{helper}{mower}{attributes}{metadata}{statusTimestamp}/1000 ));
      readingsBulkUpdateIfChanged($hash, $pref."_TimestampDiff", $storediff/1000 );
      readingsBulkUpdateIfChanged($hash, $pref."_TimestampOld", FmtDateTime( $hash->{helper}{mowerold}{attributes}{metadata}{statusTimestamp}/1000 ));
      $pref = 'positions';
      readingsBulkUpdateIfChanged($hash, $pref."_lastLatitude", $hash->{helper}{mower}{attributes}{$pref}[0]{latitude} );
      readingsBulkUpdateIfChanged($hash, $pref."_lastLongitude", $hash->{helper}{mower}{attributes}{$pref}[0]{longitude} );
      readingsBulkUpdateIfChanged($hash, 'state', 'connected' );

      my @time = localtime();
      my $secs = ( $time[2] * 3600 ) + ( $time[1] * 60 ) + $time[0];
      my $interval = $hosthash->{helper}->{interval};
      # do at midnight
      if ( $secs <= $interval ) {

        readingsBulkUpdateIfChanged( $hash, 'statistics_lastDayTrack', ReadingsNum( $name, 'statistics_currentDayTrack', 0 ));
        readingsBulkUpdateIfChanged( $hash, 'statistics_lastDayArea', ReadingsNum( $name, 'statistics_currentDayArea', 0 ));
        readingsBulkUpdateIfChanged( $hash, 'statistics_currentWeekTrack', ReadingsNum( $name, 'statistics_currentWeekTrack', 0 ) + ReadingsNum( $name, 'statistics_currentDayTrack', 0 ));
        readingsBulkUpdateIfChanged( $hash, 'statistics_currentWeekArea', ReadingsNum( $name, 'statistics_currentWeekArea', 0 ) + ReadingsNum( $name, 'statistics_currentDayArea', 0 ));
        readingsBulkUpdateIfChanged( $hash, 'statistics_currentDayTrack', 0, 0);
        readingsBulkUpdateIfChanged( $hash, 'statistics_currentDayArea', 0, 0);
       # do on mondays
        if ( $time[6] == 1 && $secs <= $interval ) {

          readingsBulkUpdateIfChanged( $hash, 'statistics_lastWeekTrack', ReadingsNum( $name, 'statistics_currentWeekTrack', 0 ));
          readingsBulkUpdateIfChanged( $hash, 'statistics_lastWeekArea', ReadingsNum( $name, 'statistics_currentWeekArea', 0 ));
          readingsBulkUpdateIfChanged( $hash, 'statistics_currentWeekTrack', 0, 0);
          readingsBulkUpdateIfChanged( $hash, 'statistics_currentWeekArea', 0, 0);

        }
      }
    readingsEndUpdate($hash, 1);
  }

  return undef;

}


##############################################################
#
# SEND COMMAND
#
##############################################################

sub CMD {
  my ($hash,@cmd) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $iam = "$type $name CMD:";
  my $hostname = $hash->{helper}{hostname};
  my $hosthash = $defs{$hostname};

  if ( IsDisabled($hostname) ) {

    Log3 $name, 3, "$iam Host $hostname disabled"; 
    return undef 

  }
  if ( IsDisabled($name) ) {

    Log3 $name, 3, "$iam disabled"; 
    return undef 

  }

  my $client_id = $hosthash->{helper}->{client_id};
  my $token = ReadingsVal($hostname,".access_token","");
  my $provider = ReadingsVal($hostname,".provider","");
  my $mower_id = $hash->{helper}{mower}{id};

  my $json = '';
  my $post = '';
    

my $header = "Accept: application/vnd.api+json\r\nX-Api-Key: ".$client_id."\r\nAuthorization: Bearer " . $token . "\r\nAuthorization-Provider: " . $provider . "\r\nContent-Type: application/vnd.api+json";
  

  if      ($cmd[0] eq "ParkUntilFurtherNotice")     { $json = '{"data":{"type":"'.$cmd[0].'"}}'; $post = 'actions' }
  elsif   ($cmd[0] eq "ParkUntilNextSchedule")      { $json = '{"data": {"type":"'.$cmd[0].'"}}'; $post = 'actions' }
  elsif   ($cmd[0] eq "ResumeSchedule")  { $json = '{"data": {"type":"'.$cmd[0].'"}}'; $post = 'actions' }
  elsif   ($cmd[0] eq "Pause")           { $json = '{"data": {"type":"'.$cmd[0].'"}}'; $post = 'actions' }
  elsif   ($cmd[0] eq "Park")            { $json = '{"data": {"type":"'.$cmd[0].'","attributes":{"duration":'.$cmd[1].'}}}'; $post = 'actions' }
  elsif   ($cmd[0] eq "Start")           { $json = '{"data": {"type":"'.$cmd[0].'","attributes":{"duration":'.$cmd[1].'}}}'; $post = 'actions' }
  elsif   ($cmd[0] eq "headlight")       { $json = '{"data": {"type":"settings","attributes":{"'.$cmd[0].'": {"mode": "'.$cmd[1].'"}}}}'; $post = 'settings' }
  elsif   ($cmd[0] eq "cuttingHeight")   { $json = '{"data": {"type":"settings","attributes":{"'.$cmd[0].'": '.$cmd[1].'}}}'; $post = 'settings' }
  elsif   ($cmd[0] eq "sendScheduleFromAttributeToMower" && AttrVal( $name, 'mowerSchedule', '')) {
    
    my $perl = eval { decode_json (AttrVal( $name, 'mowerSchedule', '')) };
    if ($@) {
      return "$iam decode error: $@ \n $perl";
    }
    my $jsonSchedule = eval { encode_json ($perl) };
    if ($@) {
      return "$iam encode error: $@ \n $json";
    }
    $json = '{"data":{"type": "calendar","attributes":{"tasks":'.$jsonSchedule.'}}}'; 
    $post = 'calendar';
  }

  Log3 $name, 5, "$iam $header \n $cmd[0] \n $json"; 

  ::HttpUtils_NonblockingGet({
    url           => APIURL . "/mowers/". $mower_id . "/".$post,
    timeout       => 10,
    hash          => $hash,
    method        => "POST",
    header        => $header,
    data          => $json,
    callback      => \&CMDResponse,
  });  
  
}

##############################################################
sub CMDResponse {
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $statuscode = $param->{code};
  my $iam = "$type $name CMDResponse:";

  Log3 $name, 1, "\ndebug $iam \n\$statuscode [$statuscode]\n\$err [$err],\n \$data [$data] \n\$param->url $param->{url}" if ( AttrVal($name, 'debug', '') );

  if( !$err && $statuscode == 202 && $data ) {

    my $result = eval { decode_json($data) };
    if ($@) {

      Log3( $name, 2, "$iam - JSON error while request: $@");

    } else {

      $hash->{helper}{CMDResponse} = $result;
      if ($result->{data}) {
        
        Log3 $name, 5, $data; 
        if ( ref ($result->{data}) eq 'ARRAY') {

        $hash->{helper}->{mower_commandStatus} = 'OK - '. $result->{data}[0]{type};

        } else {

        $hash->{helper}->{mower_commandStatus} = 'OK - '. $result->{data}{type};

        }

        readingsSingleUpdate($hash, 'mower_commandStatus', $hash->{helper}->{mower_commandStatus} ,1);
        return undef;

      }

    }

  }

  readingsSingleUpdate($hash, 'mower_commandStatus', "ERROR statuscode $statuscode" ,1);
  Log3 $name, 2, "\n$iam \n\$statuscode [$statuscode]\n\$err [$err],\n\$data [$data]\n\$param->url $param->{url}";
  return undef;
}

##############################################################
sub Get {
  my ($hash,@val) = @_;
  my $type = $hash->{TYPE};

  return "$type $hash->{NAME} Get: needs at least an argument" if ( @val < 2 );

  my ($name,$setName,$setVal,$setVal2,$setVal3) = @val;
  my $iam = "$type $name Get:";

  Log3 $name, 4, "$iam called with $setName " . ($setVal ? $setVal : "");

  if ( $setName eq 'html' ) {
    my $ret = '<html>' . FW_detailFn( undef, $name, undef, undef) . '</html>';
    return $ret;

  }
}

##############################################################
sub Set {
  my ($hash,@a) = @_;
  my $type = $hash->{TYPE};

  return "$type $hash->{NAME} Set: needs at least an argument" if ( @a < 2 );
  my ($name,$setName,$setVal,$setVal2,$setVal3) = @a;
  my $iam = "$type $name Set:";

  Log3 $name, 4, "$iam set called with $setName " . ($setVal ? $setVal : "") if ($setName !~ /^\?$/);

  if ( $setName eq 'chargingStationPositionToAttribute' ) {
      my ($xm, $ym, $n) = split(/,\s/,ReadingsVal($name,'status_calcChargingStationPositionXYn','10.1165, 51.28, 0'));
    CommandAttr($hash,"$name chargingStationCoordinates $xm $ym");
      return undef;

  ################
  } elsif ( ReadingsVal( $name, 'state', 'defined' ) !~ /defined|initialized/ && $setName eq 'mowerScheduleToAttribute' ) {
    
      my $calendarjson = JSON::XS->new->pretty(1)->encode ($hash->{helper}{mower}{attributes}{calendar}{tasks});
      if ( $@ ) {
        return "$iam $@";
      }
      CommandAttr($hash,"$name mowerSchedule $calendarjson");
      return undef;

  ################
  } elsif ( ReadingsVal( $name, 'state', 'defined' ) !~ /defined|initialized/ && $setName =~ /^(Start|Park|cuttingHeight)$/ ) {
    if ( $setVal =~ /^(\d+)$/) {
      CMD($hash ,$setName, $setVal);
      return undef;
    }

  ################
  } elsif ( ReadingsVal( $name, 'state', 'defined' ) !~ /defined|initialized/ && $setName eq 'headlight' ) {
    if ( $setVal =~ /^(ALWAYS_OFF|ALWAYS_ON|EVENING_ONLY|EVENING_AND_NIGHT)$/) {
      CMD($hash ,$setName, $setVal);
      return undef;
    }

  ################
  } elsif (ReadingsVal( $name, 'state', 'defined' ) !~ /defined|initialized/ && $setName =~ /ParkUntilFurtherNotice|ParkUntilNextSchedule|Pause|ResumeSchedule|sendScheduleFromAttributeToMower/) {
    CMD($hash,$setName);
    return undef;
  }
  my $ret = " ParkUntilFurtherNotice:noArg ParkUntilNextSchedule:noArg Pause:noArg Start Park ResumeSchedule:noArg ";
  $ret .= "chargingStationPositionToAttribute:noArg headlight:ALWAYS_OFF,ALWAYS_ON,EVENING_ONLY,EVENING_AND_NIGHT cuttingHeight:1,2,3,4,5,6,7,8,9 mowerScheduleToAttribute:noArg ";
  $ret .= "sendScheduleFromAttributeToMower:noArg ";
  return "Unknown argument $setName, choose one of".$ret;

}

#########################
sub FW_detailFn {
  my ($FW_wname, $name, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $hash = $defs{$name};
  my $type = $hash->{TYPE};
  return undef if( IsDisabled($name) || !AttrVal($name, 'showMap', 1) );
  if ( $hash->{helper} && $hash->{helper}{mower} && $hash->{helper}{mower}{attributes} && $hash->{helper}{mower}{attributes}{positions} && @{$hash->{helper}{mower}{attributes}{positions}} > 0 ) {
    my $img = "./fhem/$type/$name/map";
    my $zoom=AttrVal($name,"mapImageZoom",0.7);

    AttrVal($name,"mapImageWidthHeight",'100 200') =~ /(\d+)\s(\d+)/;
    my ($picx,$picy) = ($1, $2);

    $picx=int($picx*$zoom);
    $picy=int($picy*$zoom);
    my $ret = "";
    $ret .= "<style> ." . $type. "_" . $name . "_div{background-image: url('$img');background-size: ".$picx."px ".$picy."px;background-repeat: no-repeat; width:".$picx."px;height:".$picy."px;}</style>";
    $ret .= "<div class='" . $type. "_" . $name . "_div' >";
    $ret .= "<canvas id= '" . $type. "_" . $name . "_canvas' width='$picx' height='$picy' ></canvas>";
    $ret .= "</div>";
    
    InternalTimer( gettimeofday() + 2.0, \&FW_detailFn_Update, $hash, 0 );
    
    return $ret;
  }
  return undef;
}

#########################
sub FW_detailFn_Update {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  if ( $hash->{helper} && $hash->{helper}{mower} && $hash->{helper}{mower}{attributes} && $hash->{helper}{mower}{attributes}{positions} && @{$hash->{helper}{mower}{attributes}{positions}} > 0 ) {

    my @pos = ();
    my @posc = ();
    # @pos = @{$hash->{helper}{mower}{attributes}{positions}}; # developement mode
    @pos = @{$hash->{helper}{areapos}}; # operational mode
    @posc =@{$hash->{helper}{cspos}}; # maybe operational mode
    my $img = "./fhem/$type/$name/map";

    AttrVal($name,"mapImageCoordinatesToRegister","0 90\n90 0") =~ /(\d*\.?\d+)\s(\d*\.?\d+)(\R|\s)(\d*\.?\d+)\s(\d*\.?\d+)/;
    my ( $lonlo, $latlo, $lonru, $latru ) = ($1, $2, $4, $5);

    my $zoom = AttrVal($name,"mapImageZoom",0.7);
    
    AttrVal($name,"mapImageWidthHeight",'100 200') =~ /(\d+)\s(\d+)/;
    my ($picx,$picy) = ($1, $2);

    AttrVal($name,'scaleToMeterXY', $hash->{helper}{scaleToMeterLongitude} . ' ' .$hash->{helper}{scaleToMeterLatitude}) =~ /(\d+)\s+(\d+)/;
    my $scalx = ($lonru-$lonlo) * $1;

    $picx = int($picx*$zoom);
    $picy = int($picy*$zoom);
    my $mapx = $lonlo-$lonru;
    my $mapy = $latlo-$latru;

    if ( ($hash->{helper}{PARKED_IN_CS}{callFn} || $hash->{helper}{CHARGING}{callFn}) && (!$hash->{helper}{chargingStation}{longitude} || !$hash->{helper}{chargingStation}{latitude}) ) {
      no strict "refs";
      &{$hash->{helper}{PARKED_IN_CS}{callFn}}($hash);
      use strict "refs";
    }

    my $csimgpos = AttrVal($name,"chargingStationImagePosition","right");

    AttrVal($name,"chargingStationCoordinates",'10.1165 51.28') =~  /(\d*\.?\d+)\s(\d*\.?\d+)/;
    my ($cslo,$csla) = ($1, $2);

    my $cslon = int(($lonlo-$cslo) * $picx / $mapx);
    my $cslat = int(($latlo-$csla) * $picy / $mapy);
    # my $lon = int(($lonlo-$pos[0]{longitude}) * $picx / $mapx);
    # my $lat = int(($latlo-$pos[0]{latitude}) * $picy / $mapy);
    # my $lastx = int(($lonlo-$pos[$#pos]{longitude}) * $picx / $mapx);
    # my $lasty = int(($latlo-$pos[$#pos]{latitude}) * $picy / $mapy);

    # MOWING PATH
    my $posxy = int(($lonlo-$pos[0]{longitude}) * $picx / $mapx).",".int(($latlo-$pos[0]{latitude}) * $picy / $mapy);
    for (my $i=1;$i<@pos;$i++){
        $posxy .= ",".int(($lonlo-$pos[$i]{longitude}) * $picx / $mapx).",".int(($latlo-$pos[$i]{latitude}) * $picy / $mapy);
    }

    # CHARGING STATION PATH 
    my $poscxy = int(($lonlo-$posc[0]{longitude}) * $picx / $mapx).",".int(($latlo-$posc[0]{latitude}) * $picy / $mapy);
    for (my $i=1;$i<@posc;$i++){
        $poscxy .= ",".int(($lonlo-$posc[$i]{longitude}) * $picx / $mapx).",".int(($latlo-$posc[$i]{latitude}) * $picy / $mapy);
    }

    # AREA LIMITS
    my $arealimits = AttrVal($name,'mowingAreaLimits','');
    my $limi = '';
    if ($arealimits) {
      my @lixy = (split(/\s|,|\R$/,$arealimits));
      $limi = int(($lonlo-$lixy[0]) * $picx / $mapx).",".int(($latlo-$lixy[1]) * $picy / $mapy);
      for (my $i=2;$i<@lixy;$i+=2){
        $limi .= ",".int(($lonlo-$lixy[$i]) * $picx / $mapx).",".int(($latlo-$lixy[$i+1]) * $picy / $mapy);
      }
    }

    # PROPERTY LIMITS
    my $propertylimits = AttrVal($name,'propertyLimits','');
    my $propli = '';
    if ($propertylimits) {
      my @propxy = (split(/\s|,|\R$/,$propertylimits));
      $propli = int(($lonlo-$propxy[0]) * $picx / $mapx).",".int(($latlo-$propxy[1]) * $picy / $mapy);
      for (my $i=2;$i<@propxy;$i+=2){
        $propli .= ",".int(($lonlo-$propxy[$i]) * $picx / $mapx).",".int(($latlo-$propxy[$i+1]) * $picy / $mapy);
      }
    }

    map { 
      ::FW_directNotify("#FHEMWEB:$_", "AutomowerConnectUpdateDetail ('$name', '$type', '$img', $picx, $picy, $cslon, $cslat, '$csimgpos', $scalx, [ $posxy ], [ $limi ], [ $propli ], [ $poscxy ] )","");
    } devspec2array("TYPE=FHEMWEB");
  }
  return undef;
}


#########################
sub Attr {

  my ( $cmd, $name, $attrName, $attrVal ) = @_;
  my $hash = $defs{$name};
  my $type = $hash->{TYPE};
  my $iam = "$type $name Attr:";
  ##########
  if( $attrName eq "disable" ) {
    if( $cmd eq "set" and $attrVal eq "1" ) {

      ::setDisableNotifyFn($hash, 1);
      readingsSingleUpdate ( $hash, "state", "disabled", 1 );
      Log3 $name, 3, "$iam $cmd $attrName $attrVal";

    } elsif( $cmd eq "del" or $cmd eq 'set' and !$attrVal ) {

      my $hostname = $hash->{helper}{hostname};
      readMap($hash);
      ::notifyRegexpChanged($hash, $hostname.':state:.connected');
      readingsSingleUpdate ( $hash, "state", "initialized", 1 );
      Log3 $name, 3, "$iam $cmd $attrName $attrVal";

    }

  ##########
  } elsif ( $attrName eq 'mapImagePath' ) {

    if( $cmd eq "set") {
      if ($attrVal =~ '(webp|png|jpg)$' ) {
        $hash->{helper}{MAP_PATH} = $attrVal;
        $hash->{helper}{MAP_MIME} = "image/".$1;

        if ($attrVal =~ /(\d+)x(\d+)/) {
          CommandAttr($hash,"$name mapImageWidthHeight $1 $2");
        }

        readMap($hash);
        Log3 $name, 3, "$iam $cmd $attrName $attrVal";
      } else {
        return "$iam $attrName wrong image type, use webp, png, jpeg or jpg";
        Log3 $name, 3, "$iam wrong image type, use webp, png, jpeg or jpg";
      }

    } elsif( $cmd eq "del" ) {

      $hash->{helper}{MAP_PATH} = '';
      $hash->{helper}{MAP_CACHE} = '';
      $hash->{helper}{MAP_MIME} = '';
      Log3 $name, 3, "$iam $cmd $attrName";

    }

  ##########
  } elsif ( $attrName eq 'numberOfWayPointsToDisplay' ) {
    
    my $icurr = @{$hash->{helper}{areapos}};
    if( $cmd eq "set" && $attrVal =~ /\d+/ && $attrVal > $hash->{helper}{MOWING}{maxLengthDefault}) {

      # reduce array
      $hash->{helper}{MOWING}{maxLength} = $attrVal;
      for ( my $i = $icurr; $i > $attrVal; $i-- ) {
        pop @{$hash->{helper}{areapos}};
      }
      Log3 $name, 3, "$iam $cmd $attrName $attrVal";

    } elsif( $cmd eq "del" ) {

      # reduce array
      my $imax = $hash->{helper}{MOWING}{maxLengthDefault};
      $hash->{helper}{MOWING}{maxLength} = $imax;
      for ( my $i = $icurr; $i > $imax; $i-- ) {
        pop @{$hash->{helper}{areapos}};
      }
      Log3 $name, 3, "$iam $cmd $attrName default $imax";

    }
  ##########
  } elsif( $attrName eq "mapImageCoordinatesUTM" ) {

    if( $cmd eq "set" ) {

      if ( AttrVal( $name,'mapImageCoordinatesToRegister', '' ) && $attrVal =~ /(\d*\.?\d+)\s(\d*\.?\d+)(\R|\s)(\d*\.?\d+)\s(\d*\.?\d+)/ ) {

        my ( $x1, $y1, $x2, $y2 ) = ( $1, $2, $4, $5 );
        AttrVal( $name,'mapImageCoordinatesToRegister', '' ) =~ /(\d*\.?\d+)\s(\d*\.?\d+)(\R|\s)(\d*\.?\d+)\s(\d*\.?\d+)/;
        my ( $lo1, $la1, $lo2, $la2 ) = ( $1, $2, $4, $5 );
        my $scx = int( ( $x1 - $x2) / ( $lo1 - $lo2 ) );
        my $scy = int( ( $y1 - $y2 ) / ( $la1 - $la2 ) );
        CommandAttr($hash,"$name scaleToMeterXY $scx $scy");

      } else {
        return "$iam $attrName has a wrong format use linewise pairs <floating point longitude><one space character><floating point latitude> or the attribute mapImageCoordinatesToRegister was not set before.";
    }
      Log3 $name, 3, "$iam $cmd $attrName $attrVal";

    } elsif( $cmd eq "del" ) {

      Log3 $name, 3, "$iam $cmd $attrName and set default 0 90<Line feed>90 0";

    }
  ##########
  } elsif( $attrName eq "mapImageCoordinatesToRegister" ) {

    if( $cmd eq "set" ) {

      return "$iam $attrName has a wrong format use linewise pairs <floating point longitude><one space character><floating point latitude>" unless($attrVal =~ /(\d*\.?\d+)\s(\d*\.?\d+)(\R|\s)(\d*\.?\d+)\s(\d*\.?\d+)/);
      Log3 $name, 3, "$iam $cmd $attrName $attrVal";

    } elsif( $cmd eq "del" ) {

      Log3 $name, 3, "$iam $cmd $attrName and set default 0 90<Line feed>90 0";

    }
  ##########
  } elsif( $attrName eq "chargingStationCoordinates" ) {

    if( $cmd eq "set" ) {

      return "$iam $attrName has a wrong format use <floating point longitude><one space character><floating point latitude>" unless($attrVal =~ /(\d*\.?\d+)\s(\d*\.?\d+)/);
      Log3 $name, 3, "$iam $cmd $attrName $attrVal";

    } elsif( $cmd eq "del" ) {

      Log3 $name, 3, "$iam $cmd $attrName and set default 10.1165 51.28";

    }
  ##########
  } elsif( $attrName eq "mapImageWidthHeight" ) {

    if( $cmd eq "set" ) {

      return "$iam $attrName has a wrong format use <integer longitude><one space character><integer latitude>" unless($attrVal =~ /(\d+)\s(\d+)/);
      Log3 $name, 3, "$iam $cmd $attrName $attrVal";

    } elsif( $cmd eq "del" ) {

      Log3 $name, 3, "$iam $cmd $attrName and set default 100 200";

    }
  ##########
  } elsif( $attrName eq "scaleToMeterXY" ) {

    if( $cmd eq "set" ) {

      return "$iam $attrName has a wrong format use <integer longitude><one space character><integer latitude>" unless($attrVal =~ /(\d+)\s(\d+)/);
      Log3 $name, 3, "$iam - $cmd $attrName $attrVal";

    } elsif( $cmd eq "del" ) {

      Log3 $name, 3, "$iam $cmd $attrName and set to default: $hash->{helper}{scaleToMeterLongitude} $hash->{helper}{scaleToMeterLatitude}";

    }
  ##########
  } elsif( $attrName eq "mowerSchedule" ) {
    if( $cmd eq "set" ) {

      my $perl = eval { decode_json ($attrVal) };

      if ($@) {
        return "$iam $attrName decode error: $@ \n $perl";
      }
      my $json = eval { encode_json ($perl) };
      if ($@) {
        return "$iam $attrName encode error: $@ \n $json";
      }
      Log3 $name, 4, "$iam $cmd $attrName array";

    }
  }
  return undef;
}


#########################
sub Undef {
  my ( $hash, $arg )  = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  RemoveExtension("$type/$name/map");
  return undef;
}


###############################################################################
#
# HELPER FUINCTION
#
###############################################################################

sub AlignArray {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  if ($hash->{helper}{searchpos} && $hash->{helper}{cspos} && $hash->{helper}{areapos} && @{$hash->{helper}{searchpos}} > 1 && @{$hash->{helper}{cspos}} > 1 && @{$hash->{helper}{areapos}} > 1) {
    my $i = 0;
    my $k = -1;
    my $poslen = @{$hash->{helper}{mower}{attributes}{positions}};
    my $searchlen = 2;
    my @searchposlon = ($hash->{helper}{searchpos}[0]{longitude}, $hash->{helper}{searchpos}[1]{longitude});
    my @searchposlat = ($hash->{helper}{searchpos}[0]{latitude}, $hash->{helper}{searchpos}[1]{latitude});
    my $activity = $hash->{helper}{mower}{attributes}{mower}{activity};
    my $arrayName = $hash->{helper}{$activity}{arrayName};
    my $maxLength = $hash->{helper}{$activity}{maxLength};
    for ( $i = 0; $i < $poslen-1; $i++ ) {
      if ( $searchposlon[0] == $hash->{helper}{mower}{attributes}{positions}[ $i ]{longitude}
        && $searchposlat[0] == $hash->{helper}{mower}{attributes}{positions}[ $i ]{latitude}
        && $searchposlon[1] == $hash->{helper}{mower}{attributes}{positions}[ $i+1 ]{longitude}
        && $searchposlat[1] == $hash->{helper}{mower}{attributes}{positions}[ $i+1 ]{latitude}
        || $i == $poslen-2 ) {
        $i++ if ($i == $poslen-2);
        # timediff per step
        my $dt = 0;
        $dt = int(($hash->{helper}{mower}{attributes}{metadata}{statusTimestamp} - $hash->{helper}{$arrayName}[0]{statusTimestamp})/$i) if ($i);
        for ($k=$i-1;$k>-1;$k--) {

          unshift (@{$hash->{helper}{$arrayName}}, dclone($hash->{helper}{mower}{attributes}{positions}[ $k ]) );
          pop (@{$hash->{helper}{$arrayName}}) if (@{$hash->{helper}{$arrayName}} > $maxLength);
          $hash->{helper}{$arrayName}[0]{statusTimestamp} = $hash->{helper}{mower}{attributes}{metadata}{statusTimestamp} - $dt * $k;

          unshift (@{$hash->{helper}{searchpos}}, dclone($hash->{helper}{mower}{attributes}{positions}[ $k ]) );
          pop (@{$hash->{helper}{searchpos}}) if (@{$hash->{helper}{searchpos}} > $searchlen);
        }
        #callFn if present
        if ($hash->{helper}{$activity}{callFn}) {
          $hash->{helper}{$activity}{cnt} = $i;
          no strict "refs";
          &{$hash->{helper}{$activity}{callFn}}($hash);
          use strict "refs";
        }
        last;
      }
    }
  }
}

#########################
sub ChargingStationPosition {
  my ($hash) = @_;
  my $n = @{$hash->{helper}{cspos}};
  my $xm = 0;
  map { $xm += $_->{longitude} } @{$hash->{helper}{cspos}};
  $xm = $xm/$n;
  my $ym = 0;
  map { $ym += $_->{latitude} } @{$hash->{helper}{cspos}};
  $ym = $ym/$n;
  $hash->{helper}{chargingStation}{longitude} = $xm;
  $hash->{helper}{chargingStation}{latitude} = $ym;
  readingsSingleUpdate($hash, "statistics_ChargingStationPositionXYn", (int($xm * 10000000 + 0.5) / 10000000).", ".(int($ym * 10000000 + 0.5) / 10000000).", ".$n, 0);
  return undef;
}

#########################
sub AreaStatistics {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $i = $hash->{helper}{MOWING}{cnt};
  my $k = 0;
  my @xyarr  = @{$hash->{helper}{areapos}};# areapos
  my $n = @xyarr;

  AttrVal($name,'scaleToMeterXY', $hash->{helper}{scaleToMeterLongitude} . ' ' .$hash->{helper}{scaleToMeterLatitude}) =~ /(\d+)\s+(\d+)/;
  my ($sclon, $sclat) = ($1, $2);

  my $lsum = 0;
  my $asum = 0;
  my $vm = 0;
  
  for ( $k = 0; $k <= $i-1; $k++) {
   $lsum += ((($xyarr[ $k ]{longitude} - $xyarr[ $k+1 ]{longitude}) * $sclon)**2 + (($xyarr[ $k ]{latitude} - $xyarr[ $k+1 ]{latitude}) * $sclat)**2)**0.5;
  }
  $asum = $lsum * AttrVal($name,'mowerCuttingWidth',0.24);
  my $td = $xyarr[ 0 ]{storedTimestamp} - $xyarr[ $k ]{storedTimestamp};
  $vm = int($lsum / $td * 1000000 + 0.5)/1000 if ($td);
  $lsum += int( ReadingsNum( $name, 'statistics_currentDayTrack', 0 ) );
  $asum += int( ReadingsNum( $name, 'statistics_currentDayArea', 0 ) );
  readingsBeginUpdate($hash);
    readingsBulkUpdateIfChanged($hash,'statistics_currentDayTrack', int($lsum)); # m
    readingsBulkUpdateIfChanged($hash,'statistics_currentDayArea', int($asum)); # qm
    readingsBulkUpdateIfChanged($hash,'statistics_lastIntervalMowerSpeed', $vm); # m/s
    readingsBulkUpdateIfChanged($hash,'statistics_lastIntervalNumberOfWayPoints', $i-1); # m/s
  readingsEndUpdate($hash,1);
  return  undef;
}

#########################
sub AddExtension {
    my ( $name, $func, $link ) = @_;
    my $hash = $defs{$name};
    my $type = $hash->{TYPE};

    my $url = "/$link";
    Log3( $name, 2, "Registering $type $name for URL $url..." );
    $::data{FWEXT}{$url}{deviceName} = $name;
    $::data{FWEXT}{$url}{FUNC}       = $func;
    $::data{FWEXT}{$url}{LINK}       = $link;

    return;
}

#########################
sub RemoveExtension {
    my ($link) = @_;
    my $url  = "/$link";
    my $name = $::data{FWEXT}{$url}{deviceName};
    my $hash = $defs{$name};
    my $type = $hash->{TYPE};

    Log3( $name, 2, "Unregistering $type $name for URL $url..." );
    delete $::data{FWEXT}{$url};

    return;
}

#########################
sub GetMap() {
  my ($request) = @_;

  if ( $request =~ /^\/AutomowerConnectDevice\/(\w+)\/map/ ) {
    my $name   = $1;
    my $hash = $::defs{$name};
      return ( "text/plain; charset=utf-8","AutomowerConnectDevice: No MAP_MIME for webhook $request" ) if ( !defined $hash->{helper}{MAP_MIME} || !$hash->{helper}{MAP_MIME} );
      return ( "text/plain; charset=utf-8","AutomowerConnectDevice: No MAP_CACHE for webhook $request" ) if ( !defined $hash->{helper}{MAP_CACHE} || !$hash->{helper}{MAP_CACHE} );
    my $mapMime = $hash->{helper}{MAP_MIME};
    my $mapData = $hash->{helper}{MAP_CACHE};
    return ( $mapMime, $mapData );
  }
  return ( "text/plain; charset=utf-8","No AutomowerConnectDevice device for webhook $request" );

}

#########################
sub readMap {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $iam = "$type $name readMap:";
  RemoveInternalTimer( $hash, \&readMap );
  my $filename = $hash->{helper}{MAP_PATH};
  
  if ( $filename and -e $filename ) {
    open my $fh, '<:raw', $filename or die $!;
    my $content = '';
    while (1) {
      my $success = read $fh, $content, 1024, length($content);
      die $! if not defined $success;
      last if not $success;
    }
    close $fh;
    $hash->{helper}{MAP_CACHE} = $content;
    Log3 $name, 5, "$iam file \"$filename\" content length: ".length($content);
  } else {
    Log3 $name, 2, "$iam file \"$filename\" does not exist.";
  }
}

##############################################################

1;


=pod

=item device
=item summary    Module to control Husqvarnas robotic lawn mowers with Connect Module (SIM) 
=item summary_DE Modul zur Steuerung von Husqvarnas Mähroboter mit Connect Modul (SIM)

=begin html

<a id="AutomowerConnectDevice"></a>
<h3>AutomowerConnectDevice</h3>
<ul>
  <u><b>FHEM-FORUM:</b></u> <a target="_blank" href="https://forum.fhem.de/index.php/topic,131661.0.html"> AutomowerConnect und AutomowerConnectDevice</a><br>
  <u><b>FHEM-Wiki:</b></u> <a target="_blank" href="https://wiki.fhem.de/wiki/AutomowerConnect"> AutomowerConnect und AutomowerConnectDevice: Wie erstellt man eine Karte des Mähbereiches?</a>
  <br><br>
  <u><b>Introduction</b></u>
  <br><br>
  <ul>
    <li>This module uses an entity of the AutomowerConnect Module as host, to control additional Husqvarna Automower equipped with Connect Module (SIM) and if their data hosted there.</li>
    <li>The entities of this module are FHEM devices of additional mowers.</li>
    <li>This module is nessesary only when additional mowers registered under the same application key.</li>
    <li>The mower path is shown in the detail view.</li>
    <li>The number of way points to display is customizable.</li>
    <li>An arbitrary map can be used as background for the mower path.</li>
    <li>The map has to be a raster image in webp, png or jpg format.</li>
    <li>It's possible to control everything the API offers, e.g. schedule, headlight, cutting height and actions like start, pause, park etc. </li>
    <li>All API data is stored in the device hash, the last and the second last one. Use <code>{Dumper $defs{&lt;name&gt;}}</code> in the commandline to find the data and build userReadings out of it.</li><br>
  </ul>
  <u><b>Requirements</b></u>
  <br><br>
  <ul>
    <li>An active entity (device, host) of the AutomowerConnect module is required.</li>
    <li>Readings and state connected are shown after a host's update.</li>
  </ul>
  <br>
  <a id="AutomowerConnectDeviceDefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;device name&gt; AutomowerConnectDevice &lt;host name&gt; &lt;mower number&gt;</code><br>
    Example:<br>
    <code>define myAdditionalMower AutomowerConnectDevice myMower 1</code> the host name is myMower and the mower number is 1.<br>
    <br><br>
  </ul>
  <br>

  <a id="AutomowerConnectDeviceSet"></a>
  <b>Set</b>
  <ul>
    <li><a id='AutomowerConnectDevice-set-Park'>Park</a><br>
      <code>set &lt;name&gt; Park &lt;number of minutes&gt;</code><br>
       Parks mower in charging station for &lt;number of minutes&gt;</li>
    <li><a id='AutomowerConnectDevice-set-ParkUntilFurtherNotice'>ParkUntilFurtherNotice</a><br>
      <code>set &lt;name&gt; ParkUntilFurtherNotice</code><br>
      Parks mower in charging station until further notice</li>
    <li><a id='AutomowerConnectDevice-set-ParkUntilNextSchedule'>ParkUntilNextSchedule</a><br>
      <code>set &lt;name&gt; ParkUntilNextSchedule</code><br>
      Parks mower in charging station and starts with next planned start</li>
    <li><a id='AutomowerConnectDevice-set-Pause'>Pause</a><br>
      <code>set &lt;name&gt; Pause</code><br>
      Pauses mower immediately at current position</li>
    <li><a id='AutomowerConnectDevice-set-ResumeSchedule'>ResumeSchedule</a><br>
      <code>set &lt;name&gt; ResumeSchedule</code><br>
      Starts immediately if in planned intervall, otherwise with next scheduled start&gt;</li>
    <li><a id='AutomowerConnectDevice-set-Start'>Start</a><br>
      <code>set &lt;name&gt; Start &lt;number of minutes&gt;</code><br>
      Starts immediately for &lt;number of minutes&gt;</li>
    <li><a id='AutomowerConnectDevice-set-chargingStationPositionToAttribute'>chargingStationPositionToAttribute</a><br>
      <code>set &lt;name&gt; chargingStationPositionToAttribute</code><br>
      Sets the calculated charging station coordinates to the corresponding attributes.</li>
     <li><a id='AutomowerConnectDevice-set-cuttingHeight'>cuttingHeight</a><br>
      <code>set &lt;name&gt; cuttingHeight &lt;1..9&gt;</code><br>
      Sets the cutting height. NOTE: Do not use for 550 EPOS and Ceora.</li>
     <li><a id='AutomowerConnectDevice-set-headlight'>headlight</a><br>
      <code>set &lt;name&gt; headlight &lt;ALWAYS_OFF|ALWAYS_ON|EVENIG_ONLY|EVENING_AND_NIGHT&gt;</code><br>
      </li>
     <li><a id='AutomowerConnectDevice-set-mowerScheduleToAttrbute'>mowerScheduleToAttrbute</a><br>
      <code>set &lt;name&gt; mowerScheduleToAttrbute</code><br>
      Writes the schedule in to the attribute <code>moverSchedule</code>.</li>
     <li><a id='AutomowerConnectDevice-set-sendScheduleFromAttributeToMower'>sendScheduleFromAttributeToMower</a><br>
      <code>set &lt;name&gt; sendScheduleFromAttributeToMower</code><br>
      Sends the schedule to the mower. NOTE: Do not use for 550 EPOS and Ceora.</li>

     <li><a id='AutomowerConnectDevice-set-'></a><br>
      <code>set &lt;name&gt; </code><br>
      </li>

  </ul>
  <br>

  <a id="AutomowerConnectDeviceGet"></a>
  <b>Get</b>
  <ul>
    <li><a id='AutomowerConnectDevice-get-html'>html</a><br>
      <code>get &lt;name&gt; html </code><br>
      Returns the mower area image as html code. For use in uiTable, TabletUI, Floorplan, readingsGroup, weblink etc.</li>
    <br><br>
  </ul>
  <br>

  <a id="AutomowerConnectDeviceAttributes"></a>
  <b>Attributes</b>
  <ul>

    <li><a id='AutomowerConnectDevice-attr-mapImagePath'>mapImagePath</a><br>
      <code>attr &lt;name&gt; mapImagePath &lt;path to image&gt;</code><br>
      Path of a raster image file for an area the mower path has to be drawn to.<br>
      If the image name implies the image size by containing a part which matches <code>/(\d+)x(\d+)/</code><br>
      the corresponding attribute will be set to <code>mapImageWidthHeight = '$1 $2'</code><br>
      Image name example: <code>map740x1300.webp</code></li>

    <li><a id='AutomowerConnectDevice-attr-mapImageWidthHeight'>mapImageWidthHeight</a><br>
      <code>attr &lt;name&gt; mapImageWidthHeight &lt;width in pixel&gt;&lt;separator&gt;&lt;height in pixel&gt;</code><br>
      Width and Height in pixel of a raster image file for an area image the mower path has to be drawn to. &lt;separator&gt; is one space character.</li>

     <li><a id='AutomowerConnectDevice-attr-mapImageZoom'>mapImageZoom</a><br>
      <code>attr &lt;name&gt; mapImageZoom &lt;height in pixel&gt;</code><br>
      Zoom of a raster image for an area the mower path has to be drawn to. Default: 0.5</li>

    <li><a id='AutomowerConnectDevice-attr-mapImageCoordinatesToRegister'>mapImageCoordinatesToRegister</a><br>
      <code>attr &lt;name&gt; mapImageCoordinatesToRegister &lt;upper left longitude&gt;&lt;space&gt;&lt;upper left latitude&gt;&lt;line feed&gt;&lt;lower right longitude&gt;&lt;space&gt;&lt;lower right latitude&gt;</code><br>
      Upper left and lower right coordinates to register (or to fit to earth) the image. Format: linewise longitude and latitude values separated by 1 space.<br>
      The lines are splitted by (<code>/\s|\R$/</code>). Use WGS84 (GPS) coordinates in decimal degree notation.</li>

    <li><a id='AutomowerConnectDevice-attr-mapImageCoordinatesUTM'>mapImageCoordinatesUTM</a><br>
      <code>attr &lt;name&gt; mapImageCoordinatesUTM &lt;upper left longitude&gt;&lt;space&gt;&lt;upper left latitude&gt;&lt;line feed&gt;&lt;lower right longitude&gt;&lt;space&gt;&lt;lower right latitude&gt;</code><br>
      Upper left and lower right coordinates to register (or to fit to earth) the image. Format: linewise longitude and latitude values separated by 1 space.<br>
      The lines are splitted by (<code>/\s|\R$/</code>). Use UTM coordinates in meter notation.<br>
      This attribute has to be set after the attribute mapImageCoordinatesToRegister. The values are used to calculate the scale factors and the attribute scaleToMeterXY is set accordingly.</li>

    <li><a id='AutomowerConnectDevice-attr-showMap'>showMap</a><br>
      <code>attr &lt;name&gt; showMap &lt;&gt;<b>1</b>,0</code><br>
      Shows Map on (1 default) or not (0).</li>

   <li><a id='AutomowerConnectDevice-attr-chargingStationCoordinates'>chargingStationCoordinates</a><br>
      <code>attr &lt;name&gt; chargingStationCoordinates &lt;longitude&gt;&lt;separator&gt;&lt;latitude&gt;</code><br>
      Longitude and latitude of the charging station. Use WGS84 (GPS) coordinates in decimal degree notation. &lt;separator&gt; is one space character</li>

    <li><a id='AutomowerConnectDevice-attr-chargingStationImagePosition'>chargingStationImagePosition</a><br>
      <code>attr &lt;name&gt; chargingStationImagePosition &lt;<b>right</b>, bottom, left, top, center&gt;</code><br>
      Position of the charging station image relative to its coordinates.</li>

    <li><a id='AutomowerConnectDevice-attr-mowerCuttingWidth'>mowerCuttingWidth</a><br>
      <code>attr &lt;name&gt; mowerCuttingWidth &lt;cutting width&gt;</code><br>
      mower cutting width in meter to calculate the mowed area. default: 0.24</li>

    <li><a id='AutomowerConnectDevice-attr-mowerSchedule'>mowerSchedule</a><br>
      <code>attr &lt;name&gt; mowerSchedule &lt;schedule array&gt;</code><br>
      This attribute provides the possebility to edit the mower schedule in form of an JSON array.<br>The actual schedule can be loaded with the command <code>set &lt;name&gt; mowerScheduleToAttribute</code>. <br>The command <code>set &lt;name&gt; sendScheduleFromAttributeToMower</code> sends the schedule to the mower. The maximum of array elements is 14 and 2 each day, so every day of a week can have 2 time spans. Each array element consists of 7 unsorted day values (<code>monday</code> to <code>sunday</code>) which can be <code>true</code> or <code>false</code>, a <code>start</code> and <code>duration</code> value in minutes. Start time counts from midnight.  NOTE: Do not use for 550 EPOS and Ceora. Delete the attribute after the schedule is successfully uploaded.</li>

    <li><a id='AutomowerConnectDevice-attr-mowingAreaLimits'>mowingAreaLimits</a><br>
      <code>attr &lt;name&gt; mowingAreaLimits &lt;positions list&gt;</code><br>
      List of position describing the area to mow. Format: linewise pairs of longitude and latitude values separated by 1 space. The lines are splitted by (<code>/\s|\R$/</code>).<br>The position values could be taken from Google Earth KML file, but whithout the altitude values.</li>

    <li><a id='AutomowerConnectDevice-attr-propertyLimits'>propertyLimits</a><br>
      <code>attr &lt;name&gt; propertyLimits &lt;positions list&gt;</code><br>
      List of position describing the property limits. Format: linewise pairs of longitude and latitude values separated by 1 space. The lines are splitted by (<code>/\s|\R$/</code>).The position values could be taken from <a href"https://www.geoportal.de/Anwendungen/Geoportale%20der%20L%C3%A4nder.html"></a>. For converting UTM32 meter to ETRS89 decimal degree you can use the BKG-Geodatenzentrum <a href"https://gdz.bkg.bund.de/koordinatentransformation"></a>.</li>

    <li><a id='AutomowerConnectDevice-attr-numberOfWayPointsToDisplay'>numberOfWayPointsToDisplay</a><br>
      <code>attr &lt;name&gt; numberOfWayPointsToDisplay &lt;number of way points&gt;</code><br>
      Set the number of way points stored and displayed, default 500</li>

     <li><a id='AutomowerConnectDevice-attr-scaleToMeterXY'>scaleToMeterXY</a><br>
      <code>attr &lt;name&gt; scaleToMeterXY &lt;scale factor longitude&gt;&lt;seperator&gt;&lt;scale factor latitude&gt;</code><br>
      The scale factor depends from the Location on earth, so it has to be calculated for short ranges only. &lt;seperator&gt; is one space character.<br>
      Longitude: <code>(LongitudeMeter_1 - LongitudeMeter_2) / (LongitudeDegree_1 - LongitudeDegree _2)</code><br>
      Latitude: <code>(LatitudeMeter_1 - LatitudeMeter_2) / (LatitudeDegree_1 - LatitudeDegree _2)</code></li>

     <li><a href="disable">disable</a></li>
     <li><a href="disabledForIntervals">disabledForIntervals</a></li>


    <li><a id='AutomowerConnectDevice-attr-'></a><br>
      <code>attr &lt;name&gt;  &lt;&gt;</code><br>
      </li>
  </ul>
  <br>

  <a id="AutomowerConnectDeviceReadings"></a>
  <b>Readings</b>
  <ul>
    <li>batteryPercent - battery state of charge in percent</li>
    <li>mower_activity - current activity "UNKNOWN" | "NOT_APPLICABLE" | "MOWING" | "GOING_HOME" | "CHARGING" | "LEAVING" | "PARKED_IN_CS" | "STOPPED_IN_GARDEN"</li>
    <li>mower_commandStatus - Status of the last sent command cleared each status update</li>
    <li>mower_errorCode - last error code</li>
    <li>mower_errorCodeTimestamp - last error code time stamp</li>
    <li>mower_errorDescription - error description</li>
    <li>mower_id - ID of the mower</li>
    <li>mower_mode - current working mode "MAIN_AREA" | "SECONDARY_AREA" | "HOME" | "DEMO" | "UNKNOWN"</li>
    <li>mower_state - current status "UNKNOWN" | "NOT_APPLICABLE" | "PAUSED" | "IN_OPERATION" | "WAIT_UPDATING" | "WAIT_POWER_UP" | "RESTRICTED" | "OFF" | "STOPPED" | "ERROR" | "FATAL_ERROR" |"ERROR_AT_POWER_UP"</li>
    <li>planner_nextStart - next start time</li>
    <li>planner_restrictedReason - reason for parking NONE, WEEK_SCHEDULE, PARK_OVERRIDE, SENSOR, DAILY_LIMIT, FOTA, FROST</li>
    <li>planner_overrideAction - reason for override a planned action NOT_ACTIVE, FORCE_PARK, FORCE_MOW</li>
    <li>positions_lastLatitude - last known position (latitude)</li>
    <li>positions_lastLongitude - last known position (longitude)</li>
    <li>state - status of connection FHEM to Husqvarna Cloud API and device state(e.g.  defined, authorization, authorized, connected, error, update)</li>
    <li>status_statusTimestampOld - local time of second last change of the API content</li>
    <li>settings_cuttingHeight - actual cutting height from API</li>
    <li>settings_headlight - actual headlight mode from API</li>
    <li>statistics_ChargingStationPositionXYn - calculated position of the carging station (longitude, latitude, number of datasets) during mower_activity PARKED_IN_CS and CHARGING</li>
    <li>statistics_numberOfChargingCycles - number of charging cycles</li>
    <li>statistics_numberOfCollisions - number of collisions</li>
    <li>statistics_totalChargingTime - total charging time in hours</li>
    <li>statistics_totalCuttingTime - total cutting time in hours</li>
    <li>statistics_totalRunningTime - total running time in hours</li>
    <li>statistics_totalSearchingTime - total searching time in hours</li>
    <li>statistics_currentDayTrack - calculated mowed track length in meter during mower_activity MOWING since midnight</li>
    <li>statistics_currentDayArea - calculated mowed area in square meter during mower_activity MOWING since midnight</li>
    <li>statistics_lastIntervalNumberOfWayPoints - last Intervals Number of way points</li>
    <li>statistics_currentMowerSpeed - calculated mower speed in meter per second during mower_activity MOWING for the last interval</li>
    <li>statistics_lastDayTrack - calculated mowed track length in meter during mower_activity MOWING for yesterday</li>
    <li>statistics_lastDayArea - calculated mowed area in square meter during mower_activity MOWING for yesterday</li>
    <li>statistics_currentWeekTrack - calculated mowed track length in meter during mower_activity MOWING of the current week</li>
    <li>statistics_currentWeekArea - calculated mowed area in square meter during mower_activity MOWING of the current week</li>
    <li>statistics_lastWeekTrack - calculated mowed track length in meter during mower_activity MOWING of the last week</li>
    <li>statistics_lastWeekArea - calculated mowed area in square meter during mower_activity MOWING of the last week</li>
    <li>status_connected - state of connetion between mower and Husqvarna Cloud, (1 => true, 0 => false)</li>
    <li>status_statusTimestamp - local time of last change of the API content</li>
    <li>status_statusTimestampDiff - time difference in seconds between the last and second last change of the API content</li>
    <li>status_statusTimestampOld - local time of second last change of the API content</li>
    <li>system_name - name of the mower</li>
    <li>system_serialNumber - serial number of the mower</li>

  </ul>
</ul>

=end html



=begin html_DE

<a id="AutomowerConnectDevice"></a>
<h3>AutomowerConnectDevice</h3>
<ul>
  <u><b>FHEM-FORUM:</b></u> <a target="_blank" href="https://forum.fhem.de/index.php/topic,131661.0.html"> AutomowerConnect und AutomowerConnectDevice</a><br>
  <u><b>FHEM-Wiki:</b></u> <a target="_blank" href="https://wiki.fhem.de/wiki/AutomowerConnect"> AutomowerConnect und AutomowerConnectDevice: Wie erstellt man eine Karte des Mähbereiches?</a>

  <br><br>
  <u><b>Einleitung</b></u>
  <br><br>
  <ul>
    <li>Dieses Modul nutzt eine Istanz des AutomowerConnect Moduls als Host, um einen weiteren Husqvarna Automower, dessen Daten dort gehostet werden und der mit einem Connect Modul (SIM) ausgerüstet ist, zu steuern.</li>
    <li>Die Instanzen dieses Moduls bilden die FHEM-Geräte weiterer Mähroboter.</li>
    <li>Dieses Modul wird also erst benötigt, wenn mehrere Mähroboter unter einem  Application Key registriert sind.</li>
    <li>Der Pfad des Mähroboters wird in der Detailansicht des FHEMWEB Frontends angezeigt.</li>
    <li>Die Zahl der anzuzeigenden Wegpunkte des Pfades kann frei gewählt werden.</li>
    <li>Der Pfad kann mit einer beliebigen Karte hinterlegt werden.</li>
    <li>Die Karte muss als Rasterbild im webp, png oder jpg Format vorliegen.</li>
    <li>Es ist möglich alles was Die API anbietet zu steuern, z.B. Mähplan,Scheinwerfer, Schnitthöhe und Aktionen wie, Start, Pause, Parken usw. </li>
    <li>Die letzten und vorletzten Daten aus dem Host sind im Gerätehash gespeichert, Mit <code>{Dumper $defs{&lt;device name&gt;}}</code> in der Befehlszeile können die Daten angezeigt werden und daraus userReadings erstellt werden.</li><br>
  </ul>
  <u><b>Anforderungen</b></u>
  <br><br>
  <ul>
    <li>Es wird eine aktive Instanz (Device, FHEM-Gerät) des Moduls AutomowerConnect vorausgesetzt.</a>.</li>
    <li>Readings und der Status connected wird erst angezeigt, wenn in dem Hostgerät ein Update erfolgt ist.</a>.</li>
  </ul>
  <br>
  <a id="AutomowerConnectDeviceDefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;device name&gt; AutomowerConnectDevice &lt;host name&gt; &lt;mower number&gt;</code><br>
    Beispiel:<br>
    <code>define myAdditionalMower AutomowerConnectDevice myMower 1</code> myMower ist der Hostname und 1 ist die Nummer des anzuzeigenden Mähers.<br>
    <br><br>
  </ul>
  <br>

    <a id="AutomowerConnectDeviceSet"></a>
    <b>Set</b>
  <ul>
    <li><a id='AutomowerConnectDevice-set-Park'>Park</a><br>
      <code>set &lt;name&gt; Park &lt;number of minutes&gt;</code><br>
       Parkt den Mäher in der Ladestation (LS) für &lt;number of minutes&gt;</li>
    <li><a id='AutomowerConnectDevice-set-ParkUntilFurtherNotice'>ParkUntilFurtherNotice</a><br>
      <code>set &lt;name&gt; ParkUntilFurtherNotice</code><br>
      Parkt den Mäher bis auf Weiteres in der LS</li>
    <li><a id='AutomowerConnectDevice-set-ParkUntilNextSchedule'>ParkUntilNextSchedule</a><br>
      <code>set &lt;name&gt; ParkUntilNextSchedule</code><br>
      Parkt den Mäher bis auf Weiteres in der LS und startet zum nächsten geplanten Zeitpunkt</li>
    <li><a id='AutomowerConnectDevice-set-Pause'>Pause</a><br>
      <code>set &lt;name&gt; Pause</code><br>
      Pausiert den Mäher sofort am aktuellen Standort</li>
    <li><a id='AutomowerConnectDevice-set-ResumeSchedule'>ResumeSchedule</a><br>
      <code>set &lt;name&gt; ResumeSchedule</code><br>
      Startet im geplanten Interval den Mäher sofort, sonst zum nächsten geplanten Zeitpunkt</li>
    <li><a id='AutomowerConnectDevice-set-Start'>Start</a><br>
      <code>set &lt;name&gt; Start &lt;number of minutes&gt;</code><br>
      Startet sofort für &lt;number of minutes&gt;</li>
    <li><a id='AutomowerConnectDevice-set-chargingStationPositionToAttribute'>chargingStationPositionToAttribute</a><br>
      <code>set &lt;name&gt; chargingStationPositionToAttribute</code><br>
      Setzt die berechneten Koordinaten der LS in das entsprechende Attribut.</li>
     <li><a id='AutomowerConnectDevice-set-cuttingHeight'>cuttingHeight</a><br>
      <code>set &lt;name&gt; cuttingHeight &lt;1..9&gt;</code><br>
      Setzt die Schnitthöhe. HINWEIS: Nicht für 550 EPOS und Ceora geeignet.</li>
     <li><a id='AutomowerConnectDevice-set-headlight'>headlight</a><br>
      <code>set &lt;name&gt; headlight &lt;ALWAYS_OFF|ALWAYS_ON|EVENIG_ONLY|EVENING_AND_NIGHT&gt;</code><br>
      Setzt den Scheinwerfermode</li>
     <li><a id='AutomowerConnectDevice-set-mowerScheduleToAttrbute'>mowerScheduleToAttrbute</a><br>
      <code>set &lt;name&gt; mowerScheduleToAttrbute</code><br>
      Schreibt den Mähplan  ins Attribut <code>moverSchedule</code>.</li>
     <li><a id='AutomowerConnectDevice-set-sendScheduleFromAttributeToMower'>sendScheduleFromAttributeToMower</a><br>
      <code>set &lt;name&gt; sendScheduleFromAttributeToMower</code><br>
      Sendet den Mähplan zum Mäher. HINWEIS: Nicht für 550 EPOS und Ceora geeignet.</li>

    <li><a id='AutomowerConnectDevice-set-'></a><br>
      <code>set &lt;name&gt; </code><br>
      </li>

  <a id="AutomowerConnectDeviceGet"></a>
  <b>Get</b>
  <ul>
    <li><a id='AutomowerConnectDevice-get-html'>html</a><br>
      <code>get &lt;name&gt; html </code><br>
      Gibt das Bild des Mäherbereiches html kodiert zurück, zur Verwendung in uiTable, TabletUI, Floorplan, readingsGroup, weblink usw.</li>
    <br><br>
  </ul>
  <br>

  </ul>
    <br>
    <a id="AutomowerConnectDeviceAttributes"></a>
    <b>Attributes</b>
  <ul>

    <li><a id='AutomowerConnectDevice-attr-mapImagePath'>mapImagePath</a><br>
      <code>attr &lt;name&gt; mapImagePath &lt;path to image&gt;</code><br>
      Pfad zur Bilddatei. Auf das Bild werden Pfad, Anfangs- u. Endpunkte gezeichnet.<br>
      Wenn der Bildname die Bildgröße impliziert indem er zu dem regulären Ausdruck <code>/(\d+)x(\d+)/</code> passt,<br>
      wird das zugehörige Attribut gesetzt <code>mapImageWidthHeight = '$1 $2'</code><br>
      Beispiel Bildname: <code>map740x1300.webp</code></li>

    <li><a id='AutomowerConnectDevice-attr-mapImageWidthHeight'>mapImageWidthHeight</a><br>
      <code>attr &lt;name&gt; mapImageWidthHeight &lt;width in pixel&gt;&lt;separator&gt;&lt;height in pixel&gt;</code><br>
      Bildbreite in Pixel des Bildes auf das Pfad, Anfangs- u. Endpunkte gezeichnet werden. &lt;separator&gt; ist 1 Leerzeichen.</li>

    <li><a id='AutomowerConnectDevice-attr-mapImageHeight'>mapImageHeight</a><br>
      <code>attr &lt;name&gt;  &lt;&gt;</code><br>
      Bildh&ouml;he in Pixel des Bildes auf das Pfad, Anfangs- u. Endpunkte gezeichnet werden.</li>

    <li><a id='AutomowerConnectDevice-attr-mapImageZoom'>mapImageZoom</a><br>
      <code>attr &lt;name&gt; mapImageHeight &lt;height in pixel&gt;</code><br>
      Zoomfaktor zur Salierung des Bildes auf das Pfad, Anfangs- u. Endpunkte gezeichnet werden. Standard: 0.5</li>

    <li><a id='AutomowerConnectDevice-attr-mapImageCoordinatesToRegister'>mapImageCoordinatesToRegister</a><br>
      <code>attr &lt;name&gt; mapImageCoordinatesToRegister &lt;upper left longitude&gt;&lt;space&gt;&lt;upper left latitude&gt;&lt;line feed&gt;&lt;lower right longitude&gt;&lt;space&gt;&lt;lower right latitude&gt;</code><br>
      Obere linke und untere rechte Ecke der Fläche auf der Erde, die durch das Bild dargestellt wird um das Bild auf der Fläche zu registrieren (oder einzupassen).<br>
      Format: Zeilenweise Paare von Longitude- u. Latitudewerten getrennt durch 1 Leerzeichen. Die Zeilen werden aufgeteilt durch (<code>/\s|\R$/</code>).<br>
      Angabe der WGS84 (GPS) Koordinaten als Deimalgrad.</li>

    <li><a id='AutomowerConnectDevice-attr-mapImageCoordinatesUTM'>mapImageCoordinatesUTM</a><br>
      <code>attr &lt;name&gt; mapImageCoordinatesUTM &lt;upper left longitude&gt;&lt;space&gt;&lt;upper left latitude&gt;&lt;line feed&gt;&lt;lower right longitude&gt;&lt;space&gt;&lt;lower right latitude&gt;</code><br>
      Obere linke und untere rechte Ecke der Fläche auf der Erde, die durch das Bild dargestellt wird um das Bild auf der Fläche zu registrieren (oder einzupassen).<br>
      Format: Zeilenweise Paare von Longitude- u. Latitudewerten getrennt durch 1 Leerzeichen. Die Zeilen werden aufgeteilt durch (<code>/\s|\R$/</code>).<br>
      Die Angabe der UTM Koordinaten muss als Dezimalzahl in Meter erfolgen.<br>
      Das Attribut muss nach dem Attribut mapImageCoordinatesToRegister gesetzt werden.<br>
      Dieses Attribut berechnet die Skalierungsfaktoren. Das Attribut scaleToMeterXY wird entsprechend gesetzt</li>

    <li><a id='AutomowerConnectDevice-attr-showMap'>showMap</a><br>
      <code>attr &lt;name&gt; showMap &lt;&gt;<b>1</b>,0</code><br>
      Zeigt die Karte an (1 default) oder nicht (0).</li>

   <li><a id='AutomowerConnectDevice-attr-chargingStationCoordinates'>chargingStationCoordinates</a><br>
      <code>attr &lt;name&gt; chargingStationCoordinates &lt;longitude&gt;&lt;separator&gt;&lt;latitude&gt;</code><br>
      Longitude und Latitude der Ladestation als WGS84 (GPS) Koordinaten als Deimalgrad. &lt;separator&gt; ist 1 Leerzeichen</li>

    <li><a id='AutomowerConnectDevice-attr-chargingStationImagePosition'>chargingStationImagePosition</a><br>
      <code>attr &lt;name&gt; chargingStationImagePosition &lt;<b>right</b>, bottom, left, top, center&gt;</code><br>
      Position der Ladestation relativ zu ihren Koordinaten.</li>

    <li><a id='AutomowerConnectDevice-attr-mowerCuttingWidth'>mowerCuttingWidth</a><br>
      <code>attr &lt;name&gt; mowerCuttingWidth &lt;cutting width&gt;</code><br>
      Schnittbreite in Meter zur Berechnung der gemähten Fläche. default: 0.24</li>

    <li><a id='AutomowerConnectDevice-attr-mowerSchedule'>mowerSchedule</a><br>
      <code>attr &lt;name&gt; mowerSchedule &lt;schedule array&gt;</code><br>
      Dieses Attribut bietet die Möglichkeit den Mähplan zu ändern, er liegt als JSON Array vor.<br>Der aktuelleMähplan kann mit dem Befehl <code>set &lt;name&gt; mowerScheduleToAttrbute</code> ins Attribut geschrieben werden. <br>Der Befehl <code>set &lt;name&gt; sendScheduleFromAttributeToMower</code> sendet den Mähplan an den Mäher. Das Maximum der Arrayelemente beträgt 14, 2 für jeden Tag, so daß jeden Tag zwei Intervalle geplant werden können. Jedes Arrayelement besteht aus 7 unsortierten Tageswerten (<code>monday</code> bis <code>sunday</code>) die auf <code>true</code> oder <code>false</code> gesetzt werden können, einen <code>start</code> Wert und einen <code>duration</code> Wert in Minuten. Die Startzeit <code>start</code> wird von Mitternacht an gezählt.  HINWEIS: Nicht für 550 EPOS und Ceora geeignet.</li>

    <li><a id='AutomowerConnectDevice-attr-mowingAreaLimits'>mowingAreaLimits</a><br>
      <code>attr &lt;name&gt; mowingAreaLimits &lt;positions list&gt;</code><br>
      Liste von Positionen, die den Mähbereich beschreiben. Format: Zeilenweise Paare von Longitude- u. Latitudewerten getrennt durch 1 Leerzeichen. Die Zeilen werden aufgeteilt durch (<code>/\s|,|\R$/</code>).<br>Die Liste der Positionen kann aus einer mit Google Earth erzeugten KML-Datei entnommen werden, ohne Höhenangaben zu übernehmen</li>

    <li><a id='AutomowerConnectDevice-attr-propertyLimits'>propertyLimits</a><br>
      <code>attr &lt;name&gt; propertyLimits &lt;positions list&gt;</code><br>
      Liste von Positionen, um die Grundstücksgrenze zu beschreiben. Format: Zeilenweise Paare von Longitude- u. Latitudewerten getrennt durch 1 Leerzeichen. Eine Zeile wird aufgeteilt durch (<code>/\s|,|\R$/</code>).<br>Die genaue Position der Grenzpunkte kann man über die <a target="_blank" href="https://geoportal.de/Anwendungen/Geoportale%20der%20L%C3%A4nder.html">Geoportale der Länder</a> finden. Eine Umrechnung  der UTM32 Daten in Meter nach ETRS89 in Dezimalgrad kann über das <a href"https://gdz.bkg.bund.de/koordinatentransformation">BKG-Geodatenzentrum</a> erfolgen.</li>

    <li><a id='AutomowerConnectDevice-attr-numberOfWayPointsToDisplay'>numberOfWayPointsToDisplay</a><br>
      <code>attr &lt;name&gt; numberOfWayPointsToDisplay &lt;number of way points&gt;</code><br>
      Legt die Anzahl der gespeicherten und anzuzeigenden Wegpunkte fest, default 500</li>

     <li><a id='AutomowerConnectDevice-attr-scaleToMeterXY'>scaleToMeterXY</a><br>
      <code>attr &lt;name&gt; scaleToMeterXY &lt;scale factor longitude&gt;&lt;seperator&gt;&lt;scale factor latitude&gt;</code><br>
      Der Skalierfaktor hängt vom Standort ab und muss daher für kurze Strecken berechnet werden. &lt;seperator&gt; ist 1 Leerzeichen.<br>
      Longitude: <code>(LongitudeMeter_1 - LongitudeMeter_2) / (LongitudeDegree_1 - LongitudeDegree _2)</code><br>
      Latitude: <code>(LatitudeMeter_1 - LatitudeMeter_2) / (LatitudeDegree_1 - LatitudeDegree _2)</code></li>

     <li><a href="disable">disable</a></li>
     <li><a href="disabledForIntervals">disabledForIntervals</a></li>


<li><a id='AutomowerConnectDevice-attr-'></a><br>
      <code>attr &lt;name&gt;  &lt;&gt;</code><br>
      </li>
      
  </ul>
  <br>

  <a id="AutomowerConnectDeviceReadings"></a>
  <b>Readings</b>
  <ul>
    <li>batteryPercent - Batterieladung in Prozent</li>
    <li>mower_activity - aktuelle Aktivität "UNKNOWN" | "NOT_APPLICABLE" | "MOWING" | "GOING_HOME" | "CHARGING" | "LEAVING" | "PARKED_IN_CS" | "STOPPED_IN_GARDEN"</li>
    <li>mower_commandStatus - Status des letzten uebermittelten Kommandos wird duch Statusupdate zurückgesetzt.</li>
    <li>mower_errorCode - last error code</li>
    <li>mower_errorCodeTimestamp - last error code time stamp</li>
    <li>mower_errorDescription - error description</li>
    <li>mower_id - ID des Automowers</li>
    <li>mower_mode - aktueller Arbeitsmodus "MAIN_AREA" | "SECONDARY_AREA" | "HOME" | "DEMO" | "UNKNOWN"</li>
    <li>mower_state - aktueller Status "UNKNOWN" | "NOT_APPLICABLE" | "PAUSED" | "IN_OPERATION" | "WAIT_UPDATING" | "WAIT_POWER_UP" | "RESTRICTED" | "OFF" | "STOPPED" | "ERROR" | "FATAL_ERROR" |"ERROR_AT_POWER_UP"</li>
    <li>planner_nextStart - nächste Startzeit</li>
    <li>planner_restrictedReason - Grund für Parken NONE, WEEK_SCHEDULE, PARK_OVERRIDE, SENSOR, DAILY_LIMIT, FOTA, FROST</li>
    <li>planner_overrideAction -   Grund für vorrangige Aktion NOT_ACTIVE, FORCE_PARK, FORCE_MOW</li>
    <li>positions_lastLatitude - letzte bekannte Position (Breitengrad)</li>
    <li>positions_lastLongitude - letzte bekannte Position (Längengrad)</li>
    <li>state - Status der Verbindung des FHEM-Gerätes zur Husqvarna Cloud API (defined, connected).</li>
    <li>settings_cuttingHeight - aktuelle Schnitthöhe aus der API</li>
    <li>settings_headlight - aktueller Scheinwerfermode aus der API</li>
    <li>statistics_ChargingStationPositionXYn - berechnete Position der Ladestation mit den Werten Longitude, Latitude und Anzahl der verwendeten Datensätze wähend der Mower_activity PARKED_IN_CS und CHARGING</li>
    <li>statistics_numberOfChargingCycles - Anzahl der Ladezyklen</li>
    <li>statistics_numberOfCollisions - Anzahl der Kollisionen</li>
    <li>statistics_totalChargingTime - Gesamtladezeit in Stunden</li>
    <li>statistics_totalCuttingTime - Gesamtschneidezeit in Stunden</li>
    <li>statistics_totalRunningTime - Gesamtlaufzeit  in Stunden</li>
    <li>statistics_totalSearchingTime - Gesamtsuchzeit in Stunden</li>
    <li>statistics_currentDayTrack - berechnete gefahrene Strecke in Meter bei_Activity MOWING seit Mitternacht</li>
    <li>statistics_currentDayArea - berechnete übermähte Fläche in Quadratmeter bei der Activity MOWING seit Mitternacht</li>
    <li>statistics_lastIntervalNumberOfWayPoints - Anzahl der Wegpunkte im letzten Interval</li>
    <li>statistics_currentMowerSpeed - berechnet Geschwindigkeit in Meter pro Sekunde bei der_Activity MOWING im letzten Interval</li>
    <li>statistics_lastDayTrack - berechnete gefahrene Strecke in Meter bei_Activity MOWING des letzten Tages</li>
    <li>statistics_lastDayArea - berechnete übermähte Fläche in Quadratmeter bei der Activity MOWING des letzten Tages</li>
    <li>statistics_currentWeekTrack - berechnete gefahrene Strecke in Meter bei_Activity MOWING </li>
    <li>statistics_currentWeekArea - berechnete übermähte Fläche in Quadratmeter bei der Activity MOWING der laufenden Woche</li>
    <li>statistics_lastWeekTrack - berechnete gefahrene Strecke in Meter bei_Activity MOWING  der letzten Woche</li>
    <li>statistics_lastWeekArea - berechnete übermähte Fläche in Quadratmeter bei der Activity MOWING der letzten Woche</li>
    <li>status_connected - Status der Verbindung zwischen dem Automower und der Husqvarna Cloud, (1 => true, 0 => false)</li>
    <li>status_statusTimestamp - Lokalzeit der letzten Änderung der Daten in der API</li>
    <li>status_statusTimestampDiff - Zeitdifferenz zwichen den beiden letzten Änderungen im Inhalt der Daten aus der API</li>
    <li>status_statusTimestampOld - Lokalzeit der vorletzten Änderung der Daten in der API</li>
    <li>system_name - Name des Automowers</li>
    <li>system_serialNumber - Seriennummer des Automowers</li>
  </ul>
</ul>

=end html_DE
