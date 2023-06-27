###############################################################################
#
# $Id$
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
# Husqvarnas Open API is used
# based on some ideas from HusqvarnaAutomower and BOTVAC module
# 
################################################################################

package FHEM::Devices::AMConnect::Common;
my $cvsid = '$Id$';
use strict;
use warnings;
use POSIX;

# wird für den Import der FHEM Funktionen aus der fhem.pl benötigt
use GPUtils qw(:all);
use FHEM::Core::Authentication::Passwords qw(:ALL);

use Time::HiRes qw(gettimeofday);
use Time::Local;
use DevIo;
use Storable qw(dclone retrieve store);

# Import der FHEM Funktionen
BEGIN {
    GP_Import(
        qw(
          AttrVal
          CommandAttr
          CommandDeleteReading
          FmtDateTime
          FW_ME
          getKeyValue
          InternalTimer
          InternalVal
          IsDisabled
          Log3
          Log
          minNum
          maxNum
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
          devspec2array
          DevIo_IsOpen
          DevIo_CloseDev
          DevIo_setStates
          DevIo_OpenDev
          DevIo_SimpleRead
          DevIo_Ping
          )
    );
}

my $missingModul = "";

eval "use JSON;1" or $missingModul .= "JSON ";
require HttpUtils;

my $errorjson = '{"23":"Wheel drive problem, left","24":"Cutting system blocked","123":"Destination not reachable","710":"SIM card locked","50":"Guide 1 not found","717":"SMS could not be sent","108":"Folding cutting deck sensor defect","4":"Loop sensor problem - front","15":"Lifted","29":"Slope too steep","1":"Outside working area","45":"Cutting height problem - dir","52":"Guide 3 not found","28":"Memory circuit problem","95":"Folding sensor activated","9":"Trapped","114":"Too high discharge current","103":"Cutting drive motor 2 defect","65":"Temporary battery problem","119":"Zone generator problem","6":"Loop sensor problem - left","82":"Wheel motor blocked - rear right","714":"Geofence problem","703":"Connectivity problem","708":"SIM card locked","75":"Connection changed","7":"Loop sensor problem - right","35":"Wheel motor overloaded - right","3":"Wrong loop signal","117":"High internal power loss","0":"Unexpected error","80":"Cutting system imbalance - Warning","110":"Collision sensor error","100":"Ultrasonic Sensor 3 defect","79":"Invalid battery combination - Invalid combination of different battery types.","724":"Communication circuit board SW must be updated","86":"Wheel motor overloaded - rear right","81":"Safety function faulty","78":"Slipped - Mower has Slipped. Situation not solved with moving pattern","107":"Docking sensor defect","33":"Mower tilted","69":"Alarm! Mower switched off","68":"Temporary battery problem","34":"Cutting stopped - slope too steep","127":"Battery problem","73":"Alarm! Mower in motion","74":"Alarm! Outside geofence","713":"Geofence problem","87":"Wheel motor overloaded - rear left","120":"Internal voltage error","39":"Cutting motor problem","704":"Connectivity problem","63":"Temporary battery problem","109":"Loop sensor defect","38":"Electronic problem","64":"Temporary battery problem","113":"Complex working area","93":"No accurate position from satellites","104":"Cutting drive motor 3 defect","709":"SIM card not found","94":"Reference station communication problem","43":"Cutting height problem - drive","13":"No drive","44":"Cutting height problem - curr","118":"Charging system problem","14":"Mower lifted","57":"Guide calibration failed","707":"SIM card requires PIN","99":"Ultrasonic Sensor 2 defect","98":"Ultrasonic Sensor 1 defect","51":"Guide 2 not found","56":"Guide calibration accomplished","49":"Ultrasonic problem","2":"No loop signal","124":"Destination blocked","25":"Cutting system blocked","19":"Collision sensor problem, front","18":"Collision sensor problem - rear","48":"No response from charger","105":"Lift Sensor defect","111":"No confirmed position","10":"Upside down","40":"Limited cutting height range","716":"Connectivity problem","27":"Settings restored","90":"No power in charging station","21":"Wheel motor blocked - left","26":"Invalid sub-device combination","92":"Work area not valid","702":"Connectivity settings restored","125":"Battery needs replacement","5":"Loop sensor problem - rear","12":"Empty battery","55":"Difficult finding home","42":"Limited cutting height range","30":"Charging system problem","72":"Alarm! Mower tilted","85":"Wheel drive problem - rear left","8":"Wrong PIN code","62":"Temporary battery problem","102":"Cutting drive motor 1 defect","116":"High charging power loss","122":"CAN error","60":"Temporary battery problem","705":"Connectivity problem","711":"SIM card locked","70":"Alarm! Mower stopped","32":"Tilt sensor problem","37":"Charging current too high","89":"Invalid system configuration","76":"Connection NOT changed","71":"Alarm! Mower lifted","88":"Angular sensor problem","701":"Connectivity problem","715":"Connectivity problem","61":"Temporary battery problem","66":"Battery problem","106":"Collision sensor defect","67":"Battery problem","112":"Cutting system major imbalance","83":"Wheel motor blocked - rear left","84":"Wheel drive problem - rear right","126":"Battery near end of life","77":"Com board not available","36":"Wheel motor overloaded - left","31":"STOP button problem","17":"Charging station blocked","54":"Weak GPS signal","47":"Cutting height problem","53":"GPS navigation problem","121":"High internal temerature","97":"Left brush motor overloaded","712":"SIM card locked","20":"Wheel motor blocked - right","91":"Switch cord problem","96":"Right brush motor overloaded","58":"Temporary battery problem","59":"Temporary battery problem","22":"Wheel drive problem - right","706":"Poor signal quality","41":"Unexpected cutting height adj","46":"Cutting height blocked","11":"Low battery","16":"Stuck in charging station","101":"Ultrasonic Sensor 4 defect","115":"Too high internal current"}';

our $errortable = eval { decode_json ( $errorjson ) };
if ($@) {
  return "FHEM::Devices::AMConnect::Common \$errortable: $@";
}
$errorjson = undef;

use constant { 
  AUTHURL       => 'https://api.authentication.husqvarnagroup.dev/v1',
  APIURL        => 'https://api.amc.husqvarna.dev/v1',
  WSDEVICENAME  => 'wss:ws.openapi.husqvarna.dev:443/v1'
};


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
  my $client_id = '';
  my $mowerNumber = 0;

  return "$iam Cannot define $type device. Perl modul $missingModul is missing." if ( $missingModul );

  return "$iam too few parameters: define <NAME> $type <client_id> [<mower number>]" if( @val < 3 );

  $client_id =$val[2];
  $mowerNumber = $val[3] ? $val[3] : 0;

my $mapAttr = 'areaLimitsColor="#ff8000"
areaLimitsLineWidth="1"
areaLimitsConnector=""
propertyLimitsColor="#33cc33"
propertyLimitsLineWidth="1"
propertyLimitsConnector="1"
errorBackgroundColor="#3d3d3d"
errorFont="14px Courier New"
errorFontColor="#ff8000"
errorPathLineColor="#ff00bf"
errorPathLineDash=""
errorPathLineWidth="2"
chargingStationPathLineColor="#999999"
chargingStationPathLineDash="6,2"
chargingStationPathLineWidth="1"
chargingStationPathDotWidth="2"
otherActivityPathLineColor="#999999"
otherActivityPathLineDash="6,2"
otherActivityPathLineWidth="1"
otherActivityPathDotWidth="4"
leavingPathLineColor="#33cc33"
leavingPathLineDash="6,2"
leavingPathLineWidth="2"
leavingPathDotWidth="4"
goingHomePathLineColor="#0099ff"
goingHomePathLineDash="6,2"
goingHomePathLineWidth="2"
goingHomePathDotWidth="4"
mowingPathDisplayStart=""
mowingPathLineColor="#ff0000"
mowingPathLineDash="6,2"
mowingPathLineWidth="1"
mowingPathDotWidth="2"
mowingPathUseDots=""';

my $mapZonesTpl = '{
    "01_oben" : {
      "condition" : "$latitude > 52.6484600648553 || $longitude > 9.54799477359984 && $latitude > 52.64839739580418",
      "cuttingHeight" : "7"
  },
    "02_unten" : {
      "condition" : "undef",
      "cuttingHeight" : "3"
  }
}';

  %$hash = (%$hash,
    helper => {
      passObj                   => FHEM::Core::Authentication::Passwords->new($type),
      interval                  => 840,
      interval_ws               => 7110,
      interval_ping             => 60,
      use_position_polling      => 0,
      additional_polling        => 0,
      retry_interval_apiauth    => 840,
      retry_interval_getmower   => 840,
      timeout_apiauth           => 5,
      timeout_getmower          => 5,
      timeout_cmd               => 10,
      midnightCycle             => 1,
      client_id                 => $client_id,
      grant_type                => 'client_credentials',
      mowerNumber               => $mowerNumber,
      detailFnFirst             => 0,
      scaleToMeterLongitude     => 67425,
      scaleToMeterLatitude      => 108886,
      minLon                    => 180,
      maxLon                    => -180,
      minLat                    => 90,
      maxLat                    => -90,
      imageHeight               => 650,
      imageWidthHeight          => '350 650',
      map_init_delay            => 2,
      mapdesign                 => $mapAttr,
      mapZonesTpl               => $mapZonesTpl,
      posMinMax                 => "-180 90\n180 -90",
      newdatasets               => 0,
      newzonedatasets           => 0,
      positionsTime             => 0,
      storesum                  => 0,
      statusTime                => 0,
      cspos                     => [],
      areapos                   => [],
      errorstack                => [],
      lasterror                 => {
        positions               => [],
        timestamp               => 0,
        errordesc               => '-',
        errordate               => '',
        errorstate              => ''
      },
      UNKNOWN                   => {
        short                   => 'U',
        arrayName               => '',
        maxLength               => 100,
        cnt                     => 0,
        callFn                  => ''
      },
      NOT_APPLICABLE            => {
        short                   => 'N',
        arrayName               => '',
        maxLength               => 50,
        cnt                     => 0,
        callFn                  => ''
      },
      MOWING                    => {
        short                   => 'M',
        arrayName               => 'areapos',
        maxLength               => 5000,
        maxLengthDefault        => 5000,
        cnt                     => 0,
        callFn                  => ''
      },
      GOING_HOME                => {
        short                   => 'G',
        arrayName               => '',
        maxLength               => 50,
        cnt                     => 0,
        callFn                  => ''
      },
      CHARGING                  => {
        short                   => 'C',
        arrayName               => 'cspos',
        maxLength               => 100,
        cnt                     => 0,
        callFn                  => ''
      },
      LEAVING                   => {
        short                   => 'L',
        arrayName               => '',
        maxLength               => 50,
        cnt                     => 0,
        callFn                  => ''
      },
      PARKED_IN_CS              => {
        short                   => 'P',
        arrayName               => 'cspos',
        maxLength               => 100,
        cnt                     => 0,
        callFn                  => ''
      },
      STOPPED_IN_GARDEN         => {
        short                   => 'S',
        arrayName               => '',
        maxLength               => 50,
        cnt                     => 0,
        callFn                  => ''
      },
      statistics                => {
        currentSpeed            => 0,
        currentDayTrack         => 0,
        currentDayArea          => 0,
        currentDayTime          => 0,
        lastDayTrack            => 0,
        lastDayArea             => 0,
        lastDaytime             => 0,
        lastDayCollisions       => 0,
        currentWeekTrack        => 0,
        currentWeekArea         => 0,
        currentWeekTime         => 0,
        lastWeekTrack           => 0,
        lastWeekArea            => 0,
        lastWeekTime            => 0
      }
    }
  );
  
  $hash->{MODEL} = '';
  ( $hash->{VERSION} ) = $::FHEM::AutomowerConnect::cvsid =~ /\.pm (.*)Z/;
  $attr{$name}{room} = 'AutomowerConnect' if( !defined( $attr{$name}{room} ) );
  $attr{$name}{icon} = 'automower' if( !defined( $attr{$name}{icon} ) );
  ( $hash->{LIBRARY_VERSION} ) = $cvsid =~ /\.pm (.*)Z/;
  $hash->{Host} = 'ws.openapi.husqvarna.dev';
  $hash->{Port} = '443/v1';
  $hash->{devioNoSTATE} = 1;

  AddExtension( $name, \&GetMap, "$type/$name/map" );
  AddExtension( $name, \&GetJson, "$type/$name/json" );

  if ( $::init_done ) {

    my $attrVal = $attr{$name}{mapImagePath};

    if ($attrVal =~ '(webp|png|jpg|jpeg)$' ) {

      $hash->{helper}{MAP_PATH} = $attrVal;
      $hash->{helper}{MAP_MIME} = "image/".$1;
      readMap( $hash );

    }

  }

  if( $hash->{helper}->{passObj}->getReadPassword($name) ) {

    RemoveInternalTimer($hash);
    InternalTimer( gettimeofday() + 2, \&APIAuth, $hash, 1);

      readingsSingleUpdate( $hash, 'device_state', 'defined', 1 );

  } else {

      readingsSingleUpdate( $hash, 'device_state', 'defined - client_secret missing', 1 );

  }

  return undef;

}

#########################
sub Shutdown {
  my ( $hash, $arg )  = @_;

  DevIo_CloseDev( $hash ) if ( DevIo_IsOpen( $hash ) );
  DevIo_setStates( $hash, "closed" );

  return undef;
}

#########################
sub Undefine {
  my ( $hash, $arg )  = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};

  RemoveInternalTimer( $hash );
  RemoveExtension( "$type/$name/map" );
  RemoveExtension( "$type/$name/json" );

  return undef;
}

##########################
sub Delete {
  my ( $hash, $arg ) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $iam ="$type $name Delete: ";
  Log3( $name, 5, "$iam called" );

  my ($passResp,$passErr) = $hash->{helper}->{passObj}->setDeletePassword($name);
  Log3( $name, 1, "$iam error: $passErr" ) if ($passErr);

  return;
}

##########################
sub Rename {
  my ( $newname, $oldname ) = @_;
  my $hash = $defs{$newname};
  my $type = $hash->{TYPE};

  RemoveExtension( "$type/$oldname/map" );
  RemoveExtension( "$type/$oldname/json" );
  AddExtension( $newname, \&GetMap, "$type/$newname/map" );
  AddExtension( $newname, \&GetJson, "$type/$newname/json" );

  if ( $type eq 'AutomowerConnect' ) {

    my ( $passResp, $passErr ) = $hash->{helper}->{passObj}->setRename( $newname, $oldname );
    Log3 $newname, 2, "$newname password rename error: $passErr" if ($passErr);

  }

  return undef;
}

#########################
sub Get {
  my ($hash,@val) = @_;
  my $type = $hash->{TYPE};
  my $name = $hash->{NAME};
  my $iam = "$type $name Get:";

  return "$iam needs at least one argument" if ( @val < 2 );
  return "$iam disabled" if ( IsDisabled( $name ) );

  my ($pname,$setName,$setVal,$setVal2,$setVal3) = @val;

  Log3 $name, 4, "$iam called with $setName " . ($setVal ? $setVal : "");

  if ( $setName eq 'html' ) {
    
    my $ret = '<html>' . FW_detailFn( undef, $name, undef, undef) . '</html>';
    return $ret;

  } elsif (  $setName eq 'errorCodes' ) {

    my $ret = listErrorCodes();
    return $ret;

  } elsif (  $setName eq 'InternalData' ) {

    my $ret = listInternalData($hash);
    return $ret;

  } elsif (  $setName eq 'MowerData' ) {

    my $ret = listMowerData($hash);
    return $ret;

  } elsif (  $setName eq 'StatisticsData' ) {

    my $ret = listStatisticsData($hash);
    return $ret;

  } elsif (  $setName eq 'errorStack' ) {

    my $ret = listErrorStack($hash);
    return $ret;

  } else {

    return "Unknown argument $setName, choose one of StatisticsData:noArg MowerData:noArg InternalData:noArg errorCodes:noArg errorStack:noArg ";

  }
}

#########################
sub FW_detailFn {
  my ($FW_wname, $name, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $hash = $defs{$name};
  my $type = $hash->{TYPE};
  return '' if( AttrVal($name, 'disable', 0) || !AttrVal($name, 'showMap', 1) );

  my $img = "$FW_ME/$type/$name/map";
  my $zoom=AttrVal( $name,"mapImageZoom", 0.7 );
  my $backgroundcolor = AttrVal($name, 'mapBackgroundColor','');
  my $bgstyle = $backgroundcolor ? " background-color:$backgroundcolor;" : '';
  my $design = AttrVal( $name, 'mapDesignAttributes', $hash->{helper}{mapdesign} );
  my @adesign = split(/\R/,$design);
  my $mapDesign = 'data-'.join("data-",@adesign);

  my ($picx,$picy) = AttrVal( $name,"mapImageWidthHeight", $hash->{helper}{imageWidthHeight} ) =~ /(\d+)\s(\d+)/;
  $picx=int($picx*$zoom);
  $picy=int($picy*$zoom);

  my ( $lonlo, $latlo, $dummy, $lonru, $latru ) = AttrVal( $name,"mapImageCoordinatesToRegister",$hash->{helper}{posMinMax} ) =~ /(-?\d*\.?\d+)\s(-?\d*\.?\d+)(\R|\s)(-?\d*\.?\d+)\s(-?\d*\.?\d+)/;
  my $mapx = $lonlo-$lonru;
  my $mapy = $latlo-$latru;

  AttrVal($name,'scaleToMeterXY', $hash->{helper}{scaleToMeterLongitude} . ' ' .$hash->{helper}{scaleToMeterLatitude}) =~ /(-?\d+)\s+(-?\d+)/;
  my $scalx = ( $lonru - $lonlo ) * $1;
  my $scaly = ( $latlo - $latru ) * $2;

  # CHARGING STATION POSITION 
  my $csimgpos = AttrVal( $name,"chargingStationImagePosition","right" );
  my $xm = $hash->{helper}{chargingStation}{longitude} // 10.1165;
  my $ym = $hash->{helper}{chargingStation}{latitude} // 51.28;

  my ($cslo,$csla) = AttrVal( $name,"chargingStationCoordinates","$xm $ym" ) =~  /(-?\d*\.?\d+)\s(-?\d*\.?\d+)/;
  my $cslon = int(($lonlo-$cslo) * $picx / $mapx);
  my $cslat = int(($latlo-$csla) * $picy / $mapy);
  my $csdata = 'data-csimgpos="'.$csimgpos.'" data-cslon="'.$cslon.'" data-cslat="'.$cslat.'"';

  # AREA LIMITS
  my $arealimits = AttrVal($name,'mowingAreaLimits','');
  my $limi = '';
  if ($arealimits) {
    my @lixy = (split(/\s|,|\R$/,$arealimits));
    $limi = int( ( $lonlo - $lixy[ 0 ] ) * $picx / $mapx ) . "," . int( ( $latlo - $lixy[ 1 ] ) * $picy / $mapy );
    for (my $i=2;$i<@lixy;$i+=2){
      $limi .= ",".int( ( $lonlo - $lixy[ $i ] ) * $picx / $mapx).",".int( ( $latlo-$lixy[$i+1] ) * $picy / $mapy);
    }
  }
  $limi = 'data-areaLimitsPath="'.$limi.'"';

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
  $propli = 'data-propertyLimitsPath="'.$propli.'"';

  my $ret = "";
  $ret .= "<style>
  .${type}_${name}_div{padding:0px !important;
    $bgstyle background-image: url('$img');
    background-size: ${picx}px ${picy}px;
    background-repeat: no-repeat; 
    width: ${picx}px; height: ${picy}px;
    position: relative;}
  .${type}_${name}_canvas_0{
    position: absolute; left: 0; top: 0; z-index: 0;}
  .${type}_${name}_canvas_1{
    position: absolute; left: 0; top: 0; z-index: 1;}
  </style>";
  $ret .= "<div id='${type}_${name}_div' class='${type}_${name}_div' $mapDesign $csdata $limi $propli >";
  $ret .= "<canvas id='${type}_${name}_canvas_0' class='${type}_${name}_canvas_0' width='$picx' height='$picy' ></canvas>";
  $ret .= "<canvas id='${type}_${name}_canvas_1' class='${type}_${name}_canvas_1' width='$picx' height='$picy' ></canvas>";
  $ret .= "</div>";
  $hash->{helper}{detailFnFirst} = 1;
  my $mid = $hash->{helper}{map_init_delay};
  InternalTimer( gettimeofday() + $mid, \&FW_detailFn_Update, $hash, 0 );

  return $ret;

}

#########################
sub FW_detailFn_Update {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  return undef if( AttrVal($name, 'disable', 0) || !AttrVal($name, 'showMap', 1) );

  my @pos = @{ $hash->{helper}{areapos} };
  my @poserr = @{ $hash->{helper}{lasterror}{positions} };

  my ( $lonlo, $latlo, $dummy, $lonru, $latru ) = AttrVal( $name,"mapImageCoordinatesToRegister",$hash->{helper}{posMinMax} ) =~ /(-?\d*\.?\d+)\s(-?\d*\.?\d+)(\R|\s)(-?\d*\.?\d+)\s(-?\d*\.?\d+)/;

  my $zoom = AttrVal( $name,"mapImageZoom", 0.7 );
  
  my ($picx,$picy) = AttrVal( $name,"mapImageWidthHeight", $hash->{helper}{imageWidthHeight} ) =~ /(\d+)\s(\d+)/;

  AttrVal($name,'scaleToMeterXY', $hash->{helper}{scaleToMeterLongitude} . ' ' .$hash->{helper}{scaleToMeterLatitude}) =~ /(-?\d+)\s+(-?\d+)/;
  my $scalx = ( $lonru - $lonlo ) * $1;
  my $scaly = ( $latlo - $latru ) * $2;

  $picx = int($picx*$zoom);
  $picy = int($picy*$zoom);
  my $mapx = $lonlo-$lonru;
  my $mapy = $latlo-$latru;

  # MOWING PATH
  my @posxy = ();

  if ( @pos > 0 ) {
    my $k = 0;
    for ( my $i = 0; $i < @pos; $i++ ){

      $posxy[ $k++ ] = int( ( $lonlo - $pos[ $i ]{longitude} ) * $picx / $mapx );
      $posxy[ $k++ ] = int( ( $latlo - $pos[ $i ]{latitude} ) * $picy / $mapy );
      $posxy[ $k++ ] = $pos[ $i ]{act};

    }

  }

  # ERROR MESSAGE
  my $errdesc = $hash->{helper}{lasterror}{errordesc};
  my $errdate = $hash->{helper}{lasterror}{errordate};
  my $errstate = $hash->{helper}{lasterror}{errorstate};

  # ERROR PATH
  my @poserrxy = ( int( ( $lonru-$lonlo ) / 2 * $picx / $mapx ), int( ( $latlo - $latru ) / 2 * $picy / $mapy ) );

  if ( @poserr > 0 ) {
    my $k = 0;
    for ( my $i = 0; $i < @poserr; $i++ ){

      $poserrxy[ $k++ ] = int( ( $lonlo - $poserr[ $i ]{longitude} ) * $picx / $mapx );
      $poserrxy[ $k++ ] = int( ( $latlo - $poserr[ $i ]{latitude} ) * $picy / $mapy );

    }

  }

  # prepare hash for json map update
  $hash->{helper}{mapupdate}{name} = $name;
  $hash->{helper}{mapupdate}{type} = $type;
  $hash->{helper}{mapupdate}{detailfnfirst} = $hash->{helper}{detailFnFirst};
  $hash->{helper}{mapupdate}{lonlo} = $lonlo;
  $hash->{helper}{mapupdate}{latlo} = $latlo;
  $hash->{helper}{mapupdate}{mapx} = $mapx;
  $hash->{helper}{mapupdate}{mapy} = $mapy;
  $hash->{helper}{mapupdate}{picx} = $picx;
  $hash->{helper}{mapupdate}{picy} = $picy;
  $hash->{helper}{mapupdate}{scalx} = $scalx;
  $hash->{helper}{mapupdate}{errdesc} = [ "$errdesc", "$errdate", "$errstate" ];
  $hash->{helper}{mapupdate}{posxy} = \@posxy;
  $hash->{helper}{mapupdate}{poserrxy} = \@poserrxy;

  map { 
    ::FW_directNotify("#FHEMWEB:$_", "AutomowerConnectUpdateJson ( '$FW_ME/$type/$name/json' )","");
  } devspec2array("TYPE=FHEMWEB");

  $hash->{helper}{detailFnFirst} = 0;

return undef;
}

##############################################################
#
# API AUTHENTICATION
#
##############################################################

sub APIAuth {
  my ( $hash, $update ) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $iam = "$type $name APIAuth:";

  return if( IsDisabled( $name ) );

  if ( !$update && $::init_done ) {

    if ( ReadingsVal( $name,'.access_token','' ) and gettimeofday() < (ReadingsVal( $name, '.expires', 0 ) - 45 ) ) {

      $hash->{header} = { "Authorization", "Bearer ". ReadingsVal( $name,'.access_token','' ) };
      readingsSingleUpdate( $hash, 'device_state', 'update', 1 );
      getMower( $hash );

    } else {

      readingsSingleUpdate( $hash, 'device_state', 'authentification', 1 );
      RemoveInternalTimer( $hash, \&wsReopen );
      RemoveInternalTimer( $hash, \&wsKeepAlive );
      DevIo_CloseDev( $hash ) if ( DevIo_IsOpen( $hash ) );
      my $client_id = $hash->{helper}->{client_id};
      my $client_secret = $hash->{helper}->{passObj}->getReadPassword( $name );
      my $grant_type = $hash->{helper}->{grant_type};
      my $timeout = AttrVal( $name, 'timeoutApiAuth', $hash->{helper}->{timeout_apiauth} );

      my $header = "Content-Type: application/x-www-form-urlencoded\r\nAccept: application/json";
      my $data = 'grant_type=' . $grant_type.'&client_id=' . $client_id . '&client_secret=' . $client_secret;
      readingsSingleUpdate( $hash, 'api_callsThisMonth' , ReadingsVal( $name,  'api_callsThisMonth', 0 ) + 1, 0) if ( $hash->{helper}{additional_polling} );

      ::HttpUtils_NonblockingGet( {
        url         => AUTHURL . '/oauth2/token',
        timeout     => $timeout,
        hash        => $hash,
        method      => 'POST',
        header      => $header,
        data        => $data,
        callback    => \&APIAuthResponse,
        t_begin     => scalar gettimeofday()
      } );
    }
  } else {

    RemoveInternalTimer( $hash, \&APIAuth );
    InternalTimer( gettimeofday() + 15, \&APIAuth, $hash, 0 );

  }
  return undef;
}

#########################
sub APIAuthResponse {
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $statuscode = $param->{code} // '';
  my $iam = "$type $name APIAuthResponse:";

  Log3 $name, 1, "$iam response time ". sprintf( "%.2f", ( gettimeofday() - $param->{t_begin} ) ) . ' s' if ( $param->{timeout} == 60 );
  Log3 $name, 1, "\ndebug $iam \n\$statuscode [$statuscode]\n\$err [$err],\n \$data [$data] \n\$param->url $param->{url}" if ( AttrVal($name, 'debug', '') );

  if( !$err && $statuscode == 200 && $data) {

    my $result = eval { decode_json($data) };
    if ($@) {

      Log3 $name, 2, "$iam JSON error [ $@ ]";
      readingsSingleUpdate( $hash, 'device_state', 'error JSON', 1 );

    } else {

      $hash->{helper}->{auth} = $result;
      $hash->{header} = { "Authorization", "Bearer $hash->{helper}{auth}{access_token}" };
      
      # Update readings
      readingsBeginUpdate($hash);
        readingsBulkUpdateIfChanged($hash,'.access_token',$hash->{helper}{auth}{access_token},0 );
        readingsBulkUpdateIfChanged($hash,'.provider',$hash->{helper}{auth}{provider},0 );
        readingsBulkUpdateIfChanged($hash,'.user_id',$hash->{helper}{auth}{user_id},0 );

        # refresh token between 00:00 and 01:00
        my $expire = $result->{expires_in} + gettimeofday();
        my ( @tim ) = localtime( $expire );
        my $seconds = $tim[0] + $tim[1] * 60 + $tim[2] * 3600;
        if ($seconds > 3600) {
          $tim[ 0 ] = 0;
          $tim[ 1 ] = 0;
          $tim[ 2 ] = 1;
          $expire = timelocal( @tim );
        }

        $hash->{helper}{auth}{expires} = $expire;
        readingsBulkUpdateIfChanged($hash,'.expires',$hash->{helper}{auth}{expires},0 );
        readingsBulkUpdateIfChanged($hash,'.scope',$hash->{helper}{auth}{scope},0 );
        readingsBulkUpdateIfChanged($hash,'.token_type',$hash->{helper}{auth}{token_type},0 );

        my $expire_date = FmtDateTime($hash->{helper}{auth}{expires});
        readingsBulkUpdateIfChanged($hash,'api_token_expires',$expire_date );
        readingsBulkUpdateIfChanged($hash,'device_state', 'authenticated');
        readingsBulkUpdateIfChanged($hash,'mower_commandStatus', 'cleared');
      readingsEndUpdate($hash, 1);

      RemoveInternalTimer( $hash, \&getMower );
      InternalTimer( gettimeofday() + 1.5, \&getMower, $hash, 0 );
      return undef;
    }

  } else {

    readingsSingleUpdate( $hash, 'device_state', "error statuscode $statuscode", 1 );
    Log3 $name, 1, "\n$iam\n\$statuscode [$statuscode]\n\$err [$err],\n\$data [$data]\n\$param->url $param->{url}";

  }

  RemoveInternalTimer( $hash, \&APIAuth );
  InternalTimer( gettimeofday() + $hash->{helper}{retry_interval_apiauth}, \&APIAuth, $hash, 0 );
  Log3 $name, 1, "$iam failed retry in $hash->{helper}{retry_interval_apiauth} seconds.";
  return undef;

}


##############################################################
#
# GET MOWERS
#
##############################################################

sub getMower {
  
  my ( $hash ) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $iam = "$type $name getMower:";
  my $access_token = ReadingsVal($name,".access_token","");
  my $provider = ReadingsVal($name,".provider","");
  my $client_id = $hash->{helper}->{client_id};
  my $timeout = AttrVal( $name, 'timeoutGetMower', $hash->{helper}->{timeout_getmower} );

  my $header = "Accept: application/vnd.api+json\r\nX-Api-Key: " . $client_id . "\r\nAuthorization: Bearer " . $access_token . "\r\nAuthorization-Provider: " . $provider;
  Log3 $name, 5, "$iam header [ $header ]";
  readingsSingleUpdate( $hash, 'api_callsThisMonth' , ReadingsVal( $name, 'api_callsThisMonth', 0 ) + 1, 0) if ( $hash->{helper}{additional_polling} );

  ::HttpUtils_NonblockingGet({
    url        => APIURL . '/mowers',
    timeout    => $timeout,
    hash       => $hash,
    method     => "GET",
    header     => $header,  
    callback   => \&getMowerResponse,
    t_begin    => scalar gettimeofday()
  });
  

  return undef;
}

#########################
sub getMowerWs {
  
  my ( $hash ) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $iam = "$type $name getMowerWs:";
  my $access_token = ReadingsVal($name,".access_token","");
  my $provider = ReadingsVal($name,".provider","");
  my $client_id = $hash->{helper}->{client_id};
  my $timeout = AttrVal( $name, 'timeoutGetMower', $hash->{helper}->{timeout_getmower} );

  my $header = "Accept: application/vnd.api+json\r\nX-Api-Key: " . $client_id . "\r\nAuthorization: Bearer " . $access_token . "\r\nAuthorization-Provider: " . $provider;
  Log3 $name, 5, "$iam header [ $header ]";
  readingsSingleUpdate( $hash, 'api_callsThisMonth' , ReadingsVal( $name,  'api_callsThisMonth', 0 ) + 1, 0) if ( $hash->{helper}{additional_polling} );

  ::HttpUtils_NonblockingGet( {
    url        => APIURL . '/mowers/' . $hash->{helper}{mower}{id},
    timeout    => $timeout,
    hash       => $hash,
    method     => "GET",
    header     => $header,  
    callback   => \&getMowerResponseWs,
    t_begin    => scalar gettimeofday()
  } );

  return undef;
}

#########################
sub getMowerResponseWs {

  my ( $param, $err, $data ) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $statuscode = $param->{code} // '';
  my $iam = "$type $name getMowerResponseWs:";

  Log3 $name, 1, "$iam response time ". sprintf( "%.2f", ( gettimeofday() - $param->{t_begin} ) ) . ' s' if ( $param->{timeout} == 60 );
  Log3 $name, 1, "debug $iam \$statuscode [$statuscode]\n\$err [$err],\n \$data [$data] \n\$param->url $param->{url}" if ( AttrVal($name, 'debug', '') );

  if( !$err && $statuscode == 200 && $data) {

    if ( $data eq '' ) {

      Log3 $name, 2, "$iam no mower data present";

    } else {

      my $result = eval { decode_json($data) };

      if ($@) {

        Log3( $name, 2, "$iam - JSON error while request: $@");

      } else {

        $hash->{helper}{wsResult}{mower} = dclone( $result->{data} ) if ( AttrVal($name, 'debug', '') );
        $hash->{helper}{mower}{attributes}{statistics} = dclone( $result->{data}{attributes}{statistics} );

        if ( $hash->{helper}{use_position_polling} ) {

          my $cnt = 0;
          my $tmp = [];
          my $poslen = @{ $result->{data}{attributes}{positions} };

          for ( $cnt = 0; $cnt < $poslen; $cnt++ ) { 

            if (   $hash->{helper}{searchpos}[ 0 ]{longitude} == $result->{data}{attributes}{positions}[ $cnt ]{longitude}
                && $hash->{helper}{searchpos}[ 0 ]{latitude} == $result->{data}{attributes}{positions}[ $cnt ]{latitude} ) {

              if ( $cnt > 0 ) {

                my @ar;
                push @ar, @{ $result->{data}{attributes}{positions} }[ 0 .. $cnt-1 ];
                $hash->{helper}{mower}{attributes}{positions} = dclone( \@ar );
                AlignArray( $hash );
                FW_detailFn_Update ($hash);

              } else {

                $hash->{helper}{mower}{attributes}{positions} = [];

              }

              last;

            }

          }

        }

        isErrorThanPrepare( $hash );
        resetLastErrorIfCorrected( $hash );

        # Update readings
        readingsBeginUpdate($hash);

          fillReadings( $hash );
          # readingsBulkUpdate( $hash, 'mower_wsEvent', $hash->{helper}{wsResult}{type} ); #to do check what event
          readingsBulkUpdate( $hash, 'mower_wsEvent', 'status-event' );

        readingsEndUpdate($hash, 1);

        $hash->{helper}{searchpos} = [ dclone $result->{data}{attributes}{positions}[ 0 ] ];

        return undef;

      }

    }
    
  } else {

    readingsSingleUpdate( $hash, 'device_state', "additional Polling error statuscode $statuscode", 1 );
    Log3 $name, 1, "$iam \$statuscode [$statuscode]\n\$err [$err],\n \$data [$data] \n\$param->url $param->{url}";

  }

  return undef;

}

#########################
sub getMowerResponse {
  
  my ( $param, $err, $data ) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $statuscode = $param->{code} // '';
  my $iam = "$type $name getMowerResponse:";
  my $mowerNumber = $hash->{helper}{mowerNumber};
  
  Log3 $name, 1, "$iam response time ". sprintf( "%.2f", ( gettimeofday() - $param->{t_begin} ) ) . ' s' if ( $param->{timeout} == 60 );
  Log3 $name, 1, "debug $iam \$statuscode [$statuscode]\n\$err [$err],\n \$data [$data] \n\$param->url $param->{url}" if ( AttrVal($name, 'debug', '') );
  
  if( !$err && $statuscode == 200 && $data) {
    
    if ( $data eq "[]" ) {
      
      Log3 $name, 2, "$iam no mower data present";
      
    } else {

      my $result = eval { decode_json($data) };
      if ($@) {

        Log3( $name, 2, "$iam - JSON error while request: $@");

      } else {

        $hash->{helper}{mowers} = $result->{data};
        my $maxMower = 0;
        $maxMower = @{$hash->{helper}{mowers}} if ( ref ( $hash->{helper}{mowers} ) eq 'ARRAY' );
        if ($maxMower <= $mowerNumber || $mowerNumber < 0 ) {

          Log3 $name, 2, "$iam wrong mower number $mowerNumber ($maxMower mower available). Change definition of $name.";
          return undef;

        }

        my $foundMower .= '0 => ' . $hash->{helper}{mowers}[0]{attributes}{system}{name} . ' ' . $hash->{helper}{mowers}[0]{id};
        for (my $i = 1; $i < $maxMower; $i++) {

          $foundMower .= "\n" . $i .' => '. $hash->{helper}{mowers}[$i]{attributes}{system}{name} . ' ' . $hash->{helper}{mowers}[$i]{id};

        }
        Log3 $name, 5, "$iam found $foundMower ";

        if ( defined ( $hash->{helper}{mower}{id} ) && $hash->{helper}{midnightCycle} ) { # update dataset

          $hash->{helper}{mowerold}{attributes}{metadata}{statusTimestamp} = $hash->{helper}{mower}{attributes}{metadata}{statusTimestamp};
          $hash->{helper}{mowerold}{attributes}{mower}{activity} = $hash->{helper}{mower}{attributes}{mower}{activity};
          $hash->{helper}{mowerold}{attributes}{statistics}{numberOfCollisions} = $hash->{helper}{mower}{attributes}{statistics}{numberOfCollisions};

        } elsif ( !defined ($hash->{helper}{mower}{id}) ) { # first data set

          $hash->{helper}{mowerold}{attributes}{metadata}{statusTimestamp} = $hash->{helper}{mowers}[$mowerNumber]{attributes}{metadata}{statusTimestamp};
          $hash->{helper}{mowerold}{attributes}{mower}{activity} = $hash->{helper}{mowers}[$mowerNumber]{attributes}{mower}{activity};
          $hash->{helper}{mowerold}{attributes}{statistics}{numberOfCollisions} = $hash->{helper}{mowers}[$mowerNumber]{attributes}{statistics}{numberOfCollisions};
          $hash->{helper}{statistics}{numberOfCollisionsOld} = $hash->{helper}{mowers}[$mowerNumber]{attributes}{statistics}{numberOfCollisions};
          $hash->{helper}{searchpos} = [ dclone $hash->{helper}{mowers}[$mowerNumber]{attributes}{positions}[0] ];

          if ( AttrVal( $name, 'mapImageCoordinatesToRegister', '' ) eq '' ) {
            posMinMax( $hash, $hash->{helper}{mowers}[$mowerNumber]{attributes}{positions} );
          }

        }

        $hash->{helper}{mower} = dclone( $hash->{helper}{mowers}[$mowerNumber] );
        $hash->{helper}{mower}{attributes}{positions}[0]{getMower} = 'from polling';
        $hash->{helper}{mower_id} = $hash->{helper}{mower}{id};
        $hash->{helper}{newdatasets} = 0;

        $hash->{helper}{storediff} = $hash->{helper}{mower}{attributes}{metadata}{statusTimestamp} - $hash->{helper}{mowerold}{attributes}{metadata}{statusTimestamp};

        calculateStatistics( $hash ) if ( $hash->{helper}{midnightCycle} );

        # Update readings
        readingsBeginUpdate($hash);

          readingsBulkUpdateIfChanged($hash, 'api_MowerFound', $foundMower );
          fillReadings( $hash );
          readingsBulkUpdate($hash, 'device_state', 'connected' );

        readingsEndUpdate($hash, 1);


        # schedule new access token
        RemoveInternalTimer( $hash, \&getNewAccessToken );
        InternalTimer( ReadingsVal($name, '.expires', 600)-37, \&getNewAccessToken, $hash, 0 );

        # Websocket initialisieren, schedule ping, reopen
        RemoveInternalTimer( $hash, \&wsReopen );
        InternalTimer( gettimeofday() + 1.5, \&wsReopen, $hash, 0 );
        $hash->{helper}{midnightCycle} = 0;

        return undef;

      }

    }
    
  } else {

    readingsSingleUpdate( $hash, 'device_state', "error statuscode $statuscode", 1 );
    Log3 $name, 1, "$iam \$statuscode [$statuscode]\n\$err [$err],\n \$data [$data] \n\$param->url $param->{url}";

  }

  RemoveInternalTimer( $hash, \&APIAuth );
  InternalTimer( gettimeofday() + $hash->{helper}{retry_interval_getmower}, \&APIAuth, $hash, 0 );
  Log3 $name, 1, "$iam failed retry in $hash->{helper}{retry_interval_getmower} seconds.";
  return undef;

}

#########################
sub getNewAccessToken {
  my ($hash) = @_;
  $hash->{helper}{midnightCycle} = 1;
  APIAuth( $hash );
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
  my $timeout = AttrVal( $name, 'timeoutCMD', $hash->{helper}->{timeout_cmd} );
  $hash->{helper}{mower_commandSend} = $cmd[ 0 ] . ' ' . ( $cmd[ 1 ] ? $cmd[ 1 ] : '' );

  if ( IsDisabled( $name ) ) {

    Log3 $name, 3, "$iam disabled"; 
    return undef 

  }

  my $client_id = $hash->{helper}->{client_id};
  my $token = ReadingsVal($name,".access_token","");
  my $provider = ReadingsVal($name,".provider","");
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
  readingsSingleUpdate( $hash, 'api_callsThisMonth' , ReadingsVal( $name,  'api_callsThisMonth', 0 ) + 1, 0) if ( $hash->{helper}{additional_polling} );

  ::HttpUtils_NonblockingGet( {
    url           => APIURL . "/mowers/". $mower_id . "/".$post,
    timeout       => $timeout,
    hash          => $hash,
    method        => "POST",
    header        => $header,
    data          => $json,
    callback      => \&CMDResponse,
    t_begin       => scalar gettimeofday()
  } );  

}

##############################################################
sub CMDResponse {
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $statuscode = $param->{code} // '';
  my $iam = "$type $name CMDResponse:";

  Log3 $name, 1, "$iam response time ". sprintf( "%.2f", ( gettimeofday() - $param->{t_begin} ) ) . ' s' if ( $param->{timeout} == 60 );
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

        readingsBeginUpdate($hash);

          readingsBulkUpdateIfChanged( $hash, 'mower_commandStatus', $hash->{helper}{mower_commandStatus}, 1 );
          readingsBulkUpdateIfChanged( $hash, 'mower_commandSend', $hash->{helper}{mower_commandSend}, 1 );

        readingsEndUpdate($hash, 1);

        return undef;

      }

    }

  }

  readingsBeginUpdate($hash);

    readingsBulkUpdateIfChanged( $hash, 'mower_commandStatus', "ERROR statuscode $statuscode", 1 );
    readingsBulkUpdateIfChanged( $hash, 'mower_commandSend', $hash->{helper}{mower_commandSend}, 1 );

  readingsEndUpdate($hash, 1);

  Log3 $name, 2, "\n$iam \n\$statuscode [$statuscode]\n\$err [$err],\n\$data [$data]\n\$param->url $param->{url}";
  return undef;
}

#########################
sub Set {
  my ($hash,@val) = @_;
  my $type = $hash->{TYPE};
  my $name = $hash->{NAME};
  my $iam = "$type $name Set:";

  return "$iam: needs at least one argument" if ( @val < 2 );
  return "Unknown argument, $iam is disabled, choose one of none:noArg" if ( IsDisabled( $name ) );

  my ($pname,$setName,$setVal,$setVal2,$setVal3) = @val;

  Log3 $name, 4, "$iam called with $setName " . ($setVal ? $setVal : "") if ($setName !~ /^(\?|client_secret)$/);

  if ( !$hash->{helper}{midnightCycle} && $setName eq 'getUpdate' ) {

    RemoveInternalTimer($hash, \&APIAuth);
    APIAuth($hash);
    return undef;

  } elsif ( $setName eq 'chargingStationPositionToAttribute' ) {

    my $xm = $hash->{helper}{chargingStation}{longitude} // 10.1165;
    my $ym = $hash->{helper}{chargingStation}{latitude} // 51.28;
    CommandAttr( $hash, "$name chargingStationCoordinates $xm $ym" );
    return undef;

  } elsif ( $setName eq 'defaultDesignAttributesToAttribute' ) {

    my $design = $hash->{helper}{mapdesign};
    CommandAttr( $hash, "$name mapDesignAttributes $design" );
    return undef;

  } elsif ( $setName eq 'mapZonesTemplateToAttribute' ) {

    my $tpl = $hash->{helper}{mapZonesTpl};
    CommandAttr( $hash, "$name mapZones $tpl" );
    return undef;

  } elsif ( ReadingsVal( $name, 'device_state', 'defined' ) !~ /defined|initialized|authentification|authenticated|update/ && $setName eq 'mowerScheduleToAttribute' ) {

    my $calendarjson = eval { JSON::XS->new->pretty(1)->encode ($hash->{helper}{mower}{attributes}{calendar}{tasks}) };
    if ( $@ ) {
      return "$iam $@";
    }
    CommandAttr($hash,"$name mowerSchedule $calendarjson");
    return undef;

  } elsif ( $setName eq 'client_secret' ) {
    if ( $setVal ) {

      my ($passResp, $passErr) = $hash->{helper}->{passObj}->setStorePassword($name, $setVal);
      Log3 $name, 1, "$iam error: $passErr" if ($passErr);
      return "$iam $passErr" if( $passErr );

      readingsBeginUpdate($hash);
        readingsBulkUpdateIfChanged( $hash, '.access_token', '', 0 );
        readingsBulkUpdateIfChanged( $hash, 'device_state', 'initialized');
        readingsBulkUpdateIfChanged( $hash, 'mower_commandStatus', 'cleared');
      readingsEndUpdate($hash, 1);
      
      RemoveInternalTimer($hash, \&APIAuth);
      APIAuth($hash);
      return undef;
    }

  } elsif ( ReadingsVal( $name, 'device_state', 'defined' ) !~ /defined|initialized|authentification|authenticated|update/ && $setName =~ /^(Start|Park|cuttingHeight)$/ ) {
    if ( $setVal =~ /^(\d+)$/) {

      CMD($hash ,$setName, $setVal);
      return undef;

    }

  } elsif ( ReadingsVal( $name, 'device_state', 'defined' ) !~ /defined|initialized|authentification|authenticated|update/ && $setName eq 'headlight' ) {
    if ( $setVal =~ /^(ALWAYS_OFF|ALWAYS_ON|EVENING_ONLY|EVENING_AND_NIGHT)$/) {

      CMD($hash ,$setName, $setVal);

      return undef;
    }

  } elsif ( $setName eq 'getNewAccessToken' ) {

    readingsBeginUpdate($hash);
      readingsBulkUpdateIfChanged( $hash, '.access_token', '', 0 );
      readingsBulkUpdateIfChanged( $hash, 'device_state', 'initialized');
      readingsBulkUpdateIfChanged( $hash, 'mower_commandStatus', 'cleared');
    readingsEndUpdate($hash, 1);

      RemoveInternalTimer($hash, \&APIAuth);
      APIAuth($hash);
      return undef;

  } elsif (ReadingsVal( $name, 'device_state', 'defined' ) !~ /defined|initialized|authentification|authenticated|update/ && $setName =~ /ParkUntilFurtherNotice|ParkUntilNextSchedule|Pause|ResumeSchedule|sendScheduleFromAttributeToMower/) {

    CMD($hash,$setName);
    return undef;

  }
  my $ret = " getNewAccessToken:noArg ParkUntilFurtherNotice:noArg ParkUntilNextSchedule:noArg Pause:noArg Start:selectnumbers,60,60,600,0,lin Park:selectnumbers,60,60,600,0,lin ResumeSchedule:noArg getUpdate:noArg client_secret ";
  $ret .= "chargingStationPositionToAttribute:noArg headlight:ALWAYS_OFF,ALWAYS_ON,EVENING_ONLY,EVENING_AND_NIGHT cuttingHeight:1,2,3,4,5,6,7,8,9 mowerScheduleToAttribute:noArg ";
  $ret .= "sendScheduleFromAttributeToMower:noArg defaultDesignAttributesToAttribute:noArg mapZonesTemplateToAttribute:noArg ";
  return "Unknown argument $setName, choose one of".$ret;
  
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

      readingsSingleUpdate( $hash,'device_state','disabled',1);
      RemoveInternalTimer( $hash );
      DevIo_CloseDev( $hash ) if ( DevIo_IsOpen( $hash ) );
      DevIo_setStates( $hash, "closed" );
      Log3 $name, 3, "$iam $cmd $attrName disabled";

    } elsif( $cmd eq "del" or $cmd eq 'set' and !$attrVal ) {

      RemoveInternalTimer( $hash, \&APIAuth);
      InternalTimer( gettimeofday() + 1, \&APIAuth, $hash, 0 );
      Log3 $name, 3, "$iam $cmd $attrName enabled";

    }

  ##########
  } elsif ( $attrName eq 'mapImagePath' ) {

    if( $cmd eq "set") {

      if ($attrVal =~ '(webp|png|jpg|jpeg)$' ) {

        $hash->{helper}{MAP_PATH} = $attrVal;
        $hash->{helper}{MAP_MIME} = "image/".$1;
        ::FHEM::Devices::AMConnect::Common::readMap( $hash );

        if ( $attrVal =~ /(\d+)x(\d+)/ ) {
          $attr{$name}{mapImageWidthHeight} = "$1 $2";
        }

        Log3 $name, 3, "$iam $cmd $attrName $attrVal";

      } else {

        return "$iam $cmd $attrName wrong image type, use webp, png, jpeg or jpg";
        Log3 $name, 3, "$iam $cmd $attrName wrong image type, use webp, png, jpeg or jpg";
      
      }

    } elsif( $cmd eq "del" ) {

      $hash->{helper}{MAP_PATH} = '';
      $hash->{helper}{MAP_CACHE} = '';
      $hash->{helper}{MAP_MIME} = '';
      Log3 $name, 3, "$iam $cmd $attrName";

    }

  ##########
  } elsif( $attrName eq "weekdaysToResetWayPoints" ) {

    if( $cmd eq "set" ) {

      return "$iam $attrName is invalid, enter a combination of weekday numbers, space or - [0123456 -]" unless( $attrVal =~ /0|1|2|3|4|5|6| |-/ );
      Log3 $name, 4, "$iam $cmd $attrName $attrVal";

    } elsif( $cmd eq "del" ) {

      Log3 $name, 3, "$iam $cmd $attrName and set default to 1";

    }
  ##########
  } elsif( $attrName eq "loglevelDevIo" ) {

    if( $cmd eq "set" ) {

      return "$iam $attrName is invalid, select a number of [012345]" unless( $attrVal =~ /^[0-5]{1}$/ );
      $hash->{devioLoglevel} = $attrVal;
      Log3 $name, 4, "$iam $cmd $attrName $attrVal";

    } elsif( $cmd eq "del" ) {

      delete( $hash->{devioLoglevel} );
      Log3 $name, 3, "$iam $cmd $attrName and set default.";

    }
  ##########
  } elsif( $attrName =~ /^(timeoutGetMower|timeoutApiAuth|timeoutCMD)$/ ) {

    if( $cmd eq "set" ) {

      return "$iam $attrVal is invalid, allowed time as integer between 5 and 61" unless( $attrVal =~ /^[\d]{1,2}$/ && $attrVal > 5 && $attrVal < 61 );
      Log3 $name, 4, "$iam $cmd $attrName $attrVal";

    } elsif( $cmd eq "del" ) {

      Log3 $name, 3, "$iam $cmd $attrName and set default value.";

    }
  ##########
  } elsif( $attrName eq 'addPollingMinInterval' ) {

    if( $cmd eq "set" ) {

      return "$iam $attrVal is invalid, allowed time in seconds >= 0." unless( $attrVal >= 0 );
      $hash->{helper}{additional_polling} = $attrVal;
      Log3 $name, 4, "$iam $cmd $attrName $attrVal";

    } elsif( $cmd eq "del" ) {

      $hash->{helper}{additional_polling} = 0;
      readingsDelete( $hash, 'api_callsThisMonth' );
      Log3 $name, 3, "$iam $cmd $attrName and set default value 0.";

    }
  ##########
  } elsif( $attrName eq 'addPositionPolling' ) {

    if( $cmd eq "set" ) {

      return "$iam $attrVal is invalid, allowed value 0 or 1." unless( $attrVal == 0 || $attrVal == 1 );
      $hash->{helper}{use_position_polling} = $attrVal;
      Log3 $name, 4, "$iam $cmd $attrName $attrVal";

    } elsif( $cmd eq "del" ) {

      $hash->{helper}{use_position_polling} = 0;
      Log3 $name, 3, "$iam $cmd $attrName and set default value 0.";

    }
  ##########
  } elsif ( $attrName eq 'numberOfWayPointsToDisplay' ) {
    
    my $icurr = scalar @{$hash->{helper}{areapos}};
    if( $cmd eq "set" && $attrVal =~ /\d+/ && $attrVal > 100 ) {

      # reduce array
      $hash->{helper}{MOWING}{maxLength} = $attrVal;
      for ( my $i = $icurr; $i > $attrVal; $i-- ) {
        pop @{$hash->{helper}{areapos}};
      }
      Log3 $name, 4, "$iam $cmd $attrName $attrVal";

    } elsif( $cmd eq "del" ) {

      # reduce array
      my $imax = $hash->{helper}{MOWING}{maxLengthDefault};
      $hash->{helper}{MOWING}{maxLength} = $imax;
      for ( my $i = $icurr; $i > $imax; $i-- ) {
        pop @{$hash->{helper}{areapos}};
      }
      Log3 $name, 3, "$iam $cmd $attrName $attrName and set default $imax";

    }
  ##########
  } elsif( $attrName eq "mapImageCoordinatesUTM" ) {

    if( $cmd eq "set" ) {

      if ( AttrVal( $name,'mapImageCoordinatesToRegister', '' ) && $attrVal =~ /(-?\d*\.?\d+)\s(-?\d*\.?\d+)(\R|\s)(-?\d*\.?\d+)\s(-?\d*\.?\d+)/ ) {

        my ( $x1, $y1, $x2, $y2 ) = ( $1, $2, $4, $5 );
        AttrVal( $name,'mapImageCoordinatesToRegister', '' ) =~ /(-?\d*\.?\d+)\s(-?\d*\.?\d+)(\R|\s)(-?\d*\.?\d+)\s(-?\d*\.?\d+)/;
        my ( $lo1, $la1, $lo2, $la2 ) = ( $1, $2, $4, $5 );

        return "$iam $attrName illegal value 0 for the difference of longitudes." unless ( $lo1 - $lo2 );
        return "$iam $attrName illegal value 0 for the difference of latitudes." unless ( $la1 - $la2 );

        my $scx = int( ( $x1 - $x2) / ( $lo1 - $lo2 ) );
        my $scy = int( ( $y1 - $y2 ) / ( $la1 - $la2 ) );
        $attr{$name}{scaleToMeterXY} = "$scx $scy";

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

      return "$iam $attrName has a wrong format use linewise pairs <floating point longitude><one space character><floating point latitude>" unless( $attrVal =~ /(-?\d*\.?\d+)\s(-?\d*\.?\d+)(\R|\s)(-?\d*\.?\d+)\s(-?\d*\.?\d+)/ );
      my ( $lo1, $la1, $lo2, $la2 ) = ( $1, $2, $4, $5 );
      return "$iam $attrName illegal value 0 for the difference of longitudes." unless ( $lo1 - $lo2 );
      return "$iam $attrName illegal value 0 for the difference of latitudes." unless ( $la1 - $la2 );
      
      

      Log3 $name, 3, "$iam $cmd $attrName $attrVal";

    } elsif( $cmd eq "del" ) {

      Log3 $name, 3, "$iam $cmd $attrName and set default 0 90<Line feed>90 0";

    }
  ##########
  } elsif( $attrName eq "chargingStationCoordinates" ) {

    if( $cmd eq "set" ) {

      return "$iam $attrName has a wrong format use <floating point longitude><one space character><floating point latitude>" unless( $attrVal =~ /(-?\d*\.?\d+)\s(-?\d*\.?\d+)/ );
      Log3 $name, 3, "$iam $cmd $attrName $attrVal";

    } elsif( $cmd eq "del" ) {

      Log3 $name, 3, "$iam $cmd $attrName and set default 10.1165 51.28";

    }
  ##########
  } elsif( $attrName eq "mapImageWidthHeight" ) {

    if( $cmd eq "set" ) {

      return "$iam $attrName has a wrong format use <integer longitude><one space character><integer latitude>" unless( $attrVal =~ /(\d+)\s(\d+)/ );
      Log3 $name, 3, "$iam $cmd $attrName $attrVal";

    } elsif( $cmd eq "del" ) {

      Log3 $name, 3, "$iam $cmd $attrName and set default 100 200";

    }
  ##########
  } elsif( $attrName eq "scaleToMeterXY" ) {

    if( $cmd eq "set" ) {

      return "$iam $attrName has a wrong format use <integer longitude><one space character><integer latitude>" unless( $attrVal =~ /(-?\d+)\s(-?\d+)/ );
      Log3 $name, 3, "$iam $cmd $attrName $attrVal";

    } elsif( $cmd eq "del" ) {

      Log3 $name, 3, "$iam $cmd $attrName and set default $hash->{helper}{scaleToMeterLongitude} $hash->{helper}{scaleToMeterLatitude}";

    }
  ##########
  } elsif( $attrName eq "mowerSchedule" ) {
    if( $cmd eq "set" ) {

      my $perl = eval { decode_json ($attrVal) };

      if ($@) {
        return "$iam $cmd $attrName decode error: $@ \n $perl";
      }
      my $json = eval { encode_json ($perl) };
      if ($@) {
        return "$iam $cmd $attrName encode error: $@ \n $json";
      }
      Log3 $name, 4, "$iam $cmd $attrName mower schedule array";

    }
  ##########
  } elsif( $attrName eq "mapZones" ) {
    if( $cmd eq "set" ) {

      my $longitude = 10;
      my $latitude = 52;
      my $perl = eval { decode_json ($attrVal) };

      if ($@) {
        return "$iam $cmd $attrName decode error: $@ \n $attrVal";
      }

      for ( keys %{$perl} ) {

        $perl->{$_}{zoneCnt} = 0;
        $perl->{$_}{zoneLength} = 0;
        my $cond = eval "($perl->{$_}{condition})";

        if ($@) {
          return "$iam $cmd $attrName syntax error in condition: $@ \n $perl->{$_}{condition}";
        }

      }

        Log3 $name, 4, "$iam $cmd $attrName";
        $hash->{helper}{mapZones} = $perl;

    } elsif( $cmd eq "del" ) {

      delete $hash->{helper}{mapZones};
      delete $hash->{helper}{currentZone};
      CommandDeleteReading( $hash, "$name mower_currentZone" );
      Log3 $name, 3, "$iam $cmd $attrName";

    }
  }
  return undef;
}

#########################
sub AlignArray {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $use_position_polling = $hash->{helper}{use_position_polling};
  my $act = $hash->{helper}{mower}{attributes}{mower}{activity};
  my $actold = $hash->{helper}{mowerold}{attributes}{mower}{activity};
  my $cnt = @{ $hash->{helper}{mower}{attributes}{positions} };
  my $tmp = [];

  if ( $cnt > 0 ) {

    my @ar = @{ $hash->{helper}{mower}{attributes}{positions} };
    my $deltaTime = $hash->{helper}{positionsTime} - $hash->{helper}{statusTime};

    # if encounter positions shortly after status event old activity is assigned to positions  
    if ( $cnt > 1 && $deltaTime > 0 && $deltaTime < 0.29 && !$use_position_polling) {

      map { $_->{act} = $hash->{helper}{$actold}{short} } @ar;

    } else {

      map { $_->{act} = $hash->{helper}{$act}{short} } @ar;

    }

    if ( !$use_position_polling ) {

      @ar = reverse @ar if ( $cnt > 1 ); # positions seem to be in reversed order
      # @ar = @ar if ( $cnt > 1 ); # positions seem to be not in reversed order

    }

    $tmp = dclone( \@ar );

    if ( @{ $hash->{helper}{areapos} } ) {

      unshift ( @{ $hash->{helper}{areapos} }, @$tmp );

    } else {

      $hash->{helper}{areapos} = $tmp;
      $hash->{helper}{areapos}[0]{start} = 'first value';

    }

    while ( @{ $hash->{helper}{areapos} } > $hash->{helper}{MOWING}{maxLength} ) {

        pop ( @{ $hash->{helper}{areapos}} ); # reduce to max allowed length

    }

    posMinMax( $hash, $tmp );

    if ( $act =~ /^(MOWING)$/ ) {

      AreaStatistics ( $hash, $cnt );

    }

    if ( AttrVal($name, 'mapZones', 0) && $act =~ /^(MOWING)$/ ) {

      $tmp = dclone( \@ar );
      ZoneHandling ( $hash, $tmp, $cnt );

    }
    # set cutting height per zone
    if ( AttrVal($name, 'mapZones', 0) && $act =~ /^MOWING$/
         && defined( $hash->{helper}{currentZone} ) 
         && defined( $hash->{helper}{mapZones}{$hash->{helper}{currentZone}}{cuttingHeight} )) {

      RemoveInternalTimer( $hash, \&setCuttingHeight );
      InternalTimer( gettimeofday() + 11, \&setCuttingHeight, $hash, 0 )
    }

    # if ( $act =~ /^(CHARGING|PARKED_IN_CS)$/ && $actold =~ /^(PARKED_IN_CS|CHARGING)$/ ) {
    if ( $act =~ /^(CHARGING|PARKED_IN_CS)$/ ) {

      $tmp = dclone( \@ar );
      ChargingStationPosition ( $hash, $tmp, $cnt );

    }

  }

  $hash->{helper}{newdatasets} = $cnt;
  return undef;

}

#########################
sub isErrorThanPrepare {
  my ( $hash ) = @_;
  my $name = $hash->{NAME};

  if ( $hash->{helper}{mower}{attributes}{mower}{errorCodeTimestamp} ) {

    if ( ( $hash->{helper}{lasterror}{timestamp} != $hash->{helper}{mower}{attributes}{mower}{errorCodeTimestamp} ) && @{ $hash->{helper}{areapos} } > 1) {

      my $ect = $hash->{helper}{mower}{attributes}{mower}{errorCodeTimestamp};
      $hash->{helper}{areapos}[ 0 ]{act} = 'N';
      $hash->{helper}{areapos}[ 1 ]{act} = 'N';
      $hash->{helper}{lasterror}{positions} = [ dclone( $hash->{helper}{areapos}[ 0 ] ), dclone( $hash->{helper}{areapos}[ 1 ] ) ];
      $hash->{helper}{lasterror}{timestamp} = $ect;
      my $errc = $hash->{helper}{mower}{attributes}{mower}{errorCode};
      $hash->{helper}{lasterror}{errordesc} = $::FHEM::Devices::AMConnect::Common::errortable->{$errc};
      $hash->{helper}{lasterror}{errordate} = FmtDateTimeGMT( $ect / 1000 );
      $hash->{helper}{lasterror}{errorstate} = $hash->{helper}{mower}{attributes}{mower}{state};
      $hash->{helper}{lasterror}{errorzone} = $hash->{helper}{currentZone} if ( defined( $hash->{helper}{currentZone} ) );

      my $tmp = dclone( $hash->{helper}{lasterror} );
      unshift ( @{ $hash->{helper}{errorstack} }, $tmp );
      pop ( @{ $hash->{helper}{errorstack} } ) if ( @{ $hash->{helper}{errorstack} } > 5 );
      ::FHEM::Devices::AMConnect::Common::FW_detailFn_Update ($hash);

    }

  }

}

#########################
sub resetLastErrorIfCorrected {
  my ( $hash ) = @_;
  my $name = $hash->{NAME};

  if (!$hash->{helper}{mower}{attributes}{mower}{errorCodeTimestamp} && $hash->{helper}{lasterror}{timestamp} ) {

    $hash->{helper}{lasterror}{positions} = [];
    $hash->{helper}{lasterror}{timestamp} = 0;
    $hash->{helper}{lasterror}{errordesc} = '-';
    $hash->{helper}{lasterror}{errordate} = '';
    $hash->{helper}{lasterror}{errorstate} = '';
    ::FHEM::Devices::AMConnect::Common::FW_detailFn_Update ($hash);

  }

}
#########################
sub ZoneHandling {
  my ( $hash, $poshash, $cnt ) = @_;
  my $name = $hash->{NAME};
  my $zone = '';
  my $nextzone = '';
  my @pos = @$poshash;
  my $longitude = 0;
  my $latitude = 0;
  my @zonekeys = sort (keys %{$hash->{helper}{mapZones}});
  my $i = 0;
  my $k = 0;

  map{ $hash->{helper}{mapZones}{$_}{curZoneCnt} = 0 } @zonekeys;

  for ( $i = 0; $i < $cnt; $i++){

    $longitude = $pos[$i]{longitude};
    $latitude = $pos[$i]{latitude};

    for ( $k = 0; $k < @zonekeys-1; $k++){

      if ( eval ("$hash->{helper}{mapZones}{$zonekeys[$k]}{condition}") ) {

        if ( $hash->{helper}{mapZones}{$zonekeys[$k]}{curZoneCnt} == $i) { # find current zone and count consecutive way points

          $hash->{helper}{mapZones}{$zonekeys[$k]}{curZoneCnt}++;
          $hash->{helper}{currentZone} = $zonekeys[$k];

        }

        $hash->{helper}{mapZones}{$zonekeys[$k]}{zoneCnt}++;
        $hash->{helper}{mapZones}{$zonekeys[$k]}{zoneLength} += calcPathLength( $hash, $i, $i + 1 );
        last;

      } elsif ( $k == @zonekeys-2 ) { # last zone

        if ( $hash->{helper}{mapZones}{$zonekeys[$k+1]}{curZoneCnt} == $i) { # find current zone and count  consecutive way points

          $hash->{helper}{mapZones}{$zonekeys[$k+1]}{curZoneCnt}++;
          $hash->{helper}{currentZone} = $zonekeys[$k+1];

        }

        $hash->{helper}{mapZones}{$zonekeys[$k+1]}{zoneCnt}++;
        $hash->{helper}{mapZones}{$zonekeys[$k+1]}{zoneLength} += calcPathLength( $hash, $i, $i + 1 );

      }

    }

  }

      my $sumDayCnt=0;
      my $sumDayArea=0;

      map { $sumDayCnt += $hash->{helper}{mapZones}{$_}{zoneCnt};
            $sumDayArea += $hash->{helper}{mapZones}{$_}{zoneLength};
      } @zonekeys;

      map { $hash->{helper}{mapZones}{$_}{currentDayCntPct} = ( $sumDayCnt ? sprintf( "%.0f", $hash->{helper}{mapZones}{$_}{zoneCnt} / $sumDayCnt * 100 ) : 0 );
            $hash->{helper}{mapZones}{$_}{currentDayAreaPct} = ( $sumDayArea ? sprintf( "%.0f", $hash->{helper}{mapZones}{$_}{zoneLength} / $sumDayArea * 100 ) : 0 );
      } @zonekeys;

      $hash->{helper}{newzonedatasets} = $cnt;

}

#########################
sub ChargingStationPosition {
  my ( $hash, $poshash, $cnt ) = @_;
  if ( $cnt && @{ $hash->{helper}{cspos} } ) {

    unshift ( @{ $hash->{helper}{cspos} }, @$poshash );

  } elsif ( $cnt ) {

    $hash->{helper}{cspos} = $poshash;

  }

  while ( @{ $hash->{helper}{cspos} } > $hash->{helper}{PARKED_IN_CS}{maxLength} ) {

      pop ( @{ $hash->{helper}{cspos}} ); # reduce to max allowed length

  }
  my $n = @{$hash->{helper}{cspos}};
  if ( $n > 0 ) {

    my $xm = 0;
    map { $xm += $_->{longitude} } @{$hash->{helper}{cspos}};
    $xm = $xm/$n;
    my $ym = 0;
    map { $ym += $_->{latitude} } @{$hash->{helper}{cspos}};
    $ym = $ym/$n;
    $hash->{helper}{chargingStation}{longitude} = sprintf("%.8f",$xm);
    $hash->{helper}{chargingStation}{latitude} = sprintf("%.8f",$ym);

  }
  return undef;
}


#########################
sub calcPathLength {
  my ( $hash, $istart, $i ) = @_;
  my $name = $hash->{NAME};
  my $k = 0;
  my @xyarr  = @{$hash->{helper}{areapos}};# areapos
  my $n = scalar @xyarr;
  my ($sclon, $sclat) = AttrVal($name,'scaleToMeterXY', $hash->{helper}{scaleToMeterLongitude} . ' ' .$hash->{helper}{scaleToMeterLatitude}) =~ /(-?\d+)\s+(-?\d+)/;
  my $lsum = 0;

  for ( $k = $istart; $k < $i; $k++) {

    $lsum += ( ( ( $xyarr[ $k ]{longitude} - $xyarr[ $k+1 ]{longitude} ) * $sclon ) ** 2 + ( ( $xyarr[ $k ]{latitude} - $xyarr[ $k+1 ]{latitude} ) * $sclat ) ** 2 ) ** 0.5 if ( $xyarr[ $k+1 ]{longitude} && $xyarr[ $k+1 ]{latitude} );

  }
  return $lsum;
}

#########################
sub AreaStatistics {
  my ( $hash, $i ) = @_;
  my $name = $hash->{NAME};
  my $activity = 'MOWING';
  my $lsum = calcPathLength( $hash, 0, $i );
  my $asum = 0;
  my $atim = 0;

  $asum = $lsum * AttrVal($name,'mowerCuttingWidth',0.24);
  $atim = $i*30; # seconds
  $hash->{helper}{$activity}{track} = $lsum;
  $hash->{helper}{$activity}{area} = $asum;
  $hash->{helper}{$activity}{time} = $atim;
  $hash->{helper}{statistics}{currentDayTrack} += $lsum;
  $hash->{helper}{statistics}{currentDayArea} += $asum;
  $hash->{helper}{statistics}{currentDayTime} += $atim;

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

    Log3( $name, 2, "Unregistering URL $url..." );
    delete $::data{FWEXT}{$url};

    return;
}

#########################
sub GetMap() {
  my ($request) = @_;

  if ( $request =~ /^\/(AutomowerConnect)\/(\w+)\/map/ ) {

    my $type   = $1;
    my $name   = $2;
    my $hash = $::defs{$name};
      return ( "text/plain; charset=utf-8","${type} ${name}: No MAP_MIME for webhook $request" ) if ( !defined $hash->{helper}{MAP_MIME} || !$hash->{helper}{MAP_MIME} );
      return ( "text/plain; charset=utf-8","${type} ${name}: No MAP_CACHE for webhook $request" ) if ( !defined $hash->{helper}{MAP_CACHE} || !$hash->{helper}{MAP_CACHE} );
    my $mapMime = $hash->{helper}{MAP_MIME};
    my $mapData = $hash->{helper}{MAP_CACHE};
    return ( $mapMime, $mapData );

  }
  return ( "text/plain; charset=utf-8", "No AutomowerConnect device for webhook $request" );

}

#########################
sub GetJson() {
  my ($request) = @_;

  if ( $request =~ /^\/(AutomowerConnect)\/(\w+)\/json/ ) {

    my $type   = $1;
    my $name   = $2;
    my $hash = $::defs{$name};
    my $jsonMime = "application/json";
    my $jsonData = eval { encode_json ( $hash->{helper}{mapupdate} ) };
    if ($@) {

      Log3 $name, 2, "$type $name encode_json error: $@";
      return ( "text/plain; charset=utf-8", "No AutomowerConnect device for webhook $request" );

    }
    return ( $jsonMime, $jsonData );

  }
  return ( "text/plain; charset=utf-8", "No AutomowerConnect device for webhook $request" );

}

#########################
sub readMap {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $iam = "$type $name readMap:";
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

#########################
sub setCuttingHeight {
  my ( $hash ) = @_;
  RemoveInternalTimer( $hash, \&setCuttingHeight );
  CMD( $hash ,'cuttingHeight', $hash->{helper}{mapZones}{$hash->{helper}{currentZone}}{cuttingHeight} )
       if ( $hash->{helper}{mapZones}{$hash->{helper}{currentZone}}{cuttingHeight} != $hash->{helper}{mower}{attributes}{settings}{cuttingHeight} );
  
  return undef;
}

#########################
sub posMinMax {
  my ($hash, $poshash) = @_;
  my $minLon = $hash->{helper}{minLon};
  my $maxLon = $hash->{helper}{maxLon};
  my $minLat = $hash->{helper}{minLat};
  my $maxLat = $hash->{helper}{maxLat};
 
  for ( @{$poshash} ) {
    $minLon = minNum( $minLon,$_->{longitude} );
    $maxLon = maxNum( $maxLon,$_->{longitude} );
    $minLat = minNum( $minLat,$_->{latitude} );
    $maxLat = maxNum( $maxLat,$_->{latitude} );
  }

  $hash->{helper}{minLon} = $minLon;
  $hash->{helper}{maxLon} = $maxLon;
  $hash->{helper}{minLat} = $minLat;
  $hash->{helper}{maxLat} = $maxLat;
  $hash->{helper}{posMinMax} = "$minLon $maxLat\n$maxLon $minLat";
  $hash->{helper}{imageWidthHeight} = int($hash->{helper}{imageHeight} * ($maxLon-$minLon) / ($maxLat-$minLat)) . ' ' . $hash->{helper}{imageHeight} if ($maxLat-$minLat);

  return undef;
}

#########################
sub fillReadings {
  my ( $hash ) = @_;
  my $name = $hash->{NAME};

  readingsBulkUpdateIfChanged( $hash, '.mower_id', $hash->{helper}{mower}{id}, 0 ); 
  readingsBulkUpdateIfChanged( $hash, "batteryPercent", $hash->{helper}{mower}{attributes}{battery}{batteryPercent} ); 
  my $pref = 'mower';
  readingsBulkUpdateIfChanged( $hash, $pref.'_mode', $hash->{helper}{mower}{attributes}{$pref}{mode} );
  readingsBulkUpdateIfChanged( $hash, $pref.'_activity', $hash->{helper}{mower}{attributes}{$pref}{activity} );
  readingsBulkUpdateIfChanged( $hash, $pref.'_state', $hash->{helper}{mower}{attributes}{$pref}{state} );
  readingsBulkUpdateIfChanged( $hash, $pref.'_commandStatus', 'cleared' );
  readingsBulkUpdateIfChanged( $hash, $pref.'_commandSend', ( $hash->{helper}{mower_commandSend} ? $hash->{helper}{mower_commandSend} : '-' ) );

  if ( AttrVal($name, 'mapZones', 0) && $hash->{helper}{currentZone} && $hash->{helper}{mapZones}{$hash->{helper}{currentZone}}{curZoneCnt} ) {
    my $curZon = $hash->{helper}{currentZone};
    my $curZonCnt = $hash->{helper}{mapZones}{$curZon}{curZoneCnt};
    readingsBulkUpdateIfChanged( $hash, $pref.'_currentZone', $curZon . '(' . $curZonCnt . '/' . $hash->{helper}{newzonedatasets} . ')' );
  }

  my $tstamp = $hash->{helper}{mower}{attributes}{$pref}{errorCodeTimestamp};
  my $timestamp = FmtDateTimeGMT( $tstamp/1000 );
  readingsBulkUpdateIfChanged( $hash, $pref."_errorCodeTimestamp", $tstamp ? $timestamp : '-' );

  my $errc = $hash->{helper}{mower}{attributes}{$pref}{errorCode};
  readingsBulkUpdateIfChanged( $hash, $pref.'_errorCode', $tstamp ? $errc  : '-');

  my $errd = $errortable->{$errc};
  readingsBulkUpdateIfChanged( $hash, $pref.'_errorDescription', $tstamp ? $errd : '-');

  $pref = 'system';
  readingsBulkUpdateIfChanged( $hash, $pref."_name", $hash->{helper}{mower}{attributes}{$pref}{name} );
  my $model = $hash->{helper}{mower}{attributes}{$pref}{model};
  $model =~ s/AUTOMOWER./AM/;
  $hash->{MODEL} = $model if ( $model && $hash->{MODEL} ne $model );
  $pref = 'planner';
  readingsBulkUpdateIfChanged( $hash, "planner_restrictedReason", $hash->{helper}{mower}{attributes}{$pref}{restrictedReason} );
  readingsBulkUpdateIfChanged( $hash, "planner_overrideAction", $hash->{helper}{mower}{attributes}{$pref}{override}{action} );

  $tstamp = $hash->{helper}{mower}{attributes}{$pref}{nextStartTimestamp};
  $timestamp = FmtDateTimeGMT( $tstamp/1000 );
  readingsBulkUpdateIfChanged($hash, "planner_nextStart", $tstamp ? $timestamp : '-' );

  $pref = 'statistics';
  my $noCol = $hash->{helper}{mower}{attributes}{$pref}{numberOfCollisions} - $hash->{helper}{mowerold}{attributes}{$pref}{numberOfCollisions};
  readingsBulkUpdateIfChanged( $hash, $pref."_numberOfCollisions", '(' . $noCol . '/' . $hash->{helper}{statistics}{lastDayCollisions} . '/' . $hash->{helper}{mower}{attributes}{$pref}{numberOfCollisions} . ')' );
  readingsBulkUpdateIfChanged( $hash, $pref."_newGeoDataSets", $hash->{helper}{newdatasets} );
  $pref = 'settings';
  readingsBulkUpdateIfChanged( $hash, $pref."_headlight", $hash->{helper}{mower}{attributes}{$pref}{headlight}{mode} );
  readingsBulkUpdateIfChanged( $hash, $pref."_cuttingHeight", $hash->{helper}{mower}{attributes}{$pref}{cuttingHeight} );
  $pref = 'status';
  my $connected = $hash->{helper}{mower}{attributes}{metadata}{connected};
  readingsBulkUpdateIfChanged( $hash, $pref."_connected", ( $connected ? "CONNECTED($connected)"  : "OFFLINE($connected)") );

  readingsBulkUpdateIfChanged( $hash, $pref."_Timestamp", FmtDateTime( $hash->{helper}{mower}{attributes}{metadata}{statusTimestamp}/1000 ) ); # verschieben nach websocket fill
  readingsBulkUpdateIfChanged( $hash, $pref."_TimestampDiff", $hash->{helper}{storediff}/1000 );# verschieben nach websocket fill

  return undef;
}

#########################
sub calculateStatistics {
  my ( $hash ) = @_;
  my $name = $hash->{NAME};
  my @time = localtime();

  $hash->{helper}{statistics}{lastDayTrack} = $hash->{helper}{statistics}{currentDayTrack};
  $hash->{helper}{statistics}{lastDayArea} = $hash->{helper}{statistics}{currentDayArea};
  $hash->{helper}{statistics}{lastDayTime} = $hash->{helper}{statistics}{currentDayTime};
  $hash->{helper}{statistics}{lastDayCollisions} = $hash->{helper}{mower}{attributes}{statistics}{numberOfCollisions} - $hash->{helper}{statistics}{numberOfCollisionsOld};
  $hash->{helper}{statistics}{numberOfCollisionsOld} = $hash->{helper}{mower}{attributes}{statistics}{numberOfCollisions};
  
  $hash->{helper}{statistics}{currentWeekTrack} += $hash->{helper}{statistics}{currentDayTrack};
  $hash->{helper}{statistics}{currentWeekArea} += $hash->{helper}{statistics}{currentDayArea};
  $hash->{helper}{statistics}{currentWeekTime} += $hash->{helper}{statistics}{currentDayTime};
  $hash->{helper}{statistics}{currentDayTrack} = 0;
  $hash->{helper}{statistics}{currentDayArea} = 0;
  $hash->{helper}{statistics}{currentDayTime} = 0;

  if ( AttrVal($name, 'mapZones', 0) && defined( $hash->{helper}{mapZones} ) ) {
    
    my @zonekeys = sort (keys %{$hash->{helper}{mapZones}});
    my $sumCurrentWeekCnt=0;
    my $sumCurrentWeekArea=0;
    map { 
      $hash->{helper}{mapZones}{$_}{currentWeekCnt} += $hash->{helper}{mapZones}{$_}{zoneCnt};
      $sumCurrentWeekCnt += $hash->{helper}{mapZones}{$_}{currentWeekCnt};
      $hash->{helper}{mapZones}{$_}{currentWeekArea} += $hash->{helper}{mapZones}{$_}{zoneLength};
      $sumCurrentWeekArea += $hash->{helper}{mapZones}{$_}{currentWeekArea};
      $hash->{helper}{mapZones}{$_}{zoneCnt} = 0;
      $hash->{helper}{mapZones}{$_}{zoneLength} = 0;
    } @zonekeys;

    map { 
      $hash->{helper}{mapZones}{$_}{lastDayCntPct} = $hash->{helper}{mapZones}{$_}{currentDayCntPct};
      $hash->{helper}{mapZones}{$_}{currentWeekCntPct} = ( $sumCurrentWeekCnt ? sprintf( "%.0f", $hash->{helper}{mapZones}{$_}{currentWeekCnt} / $sumCurrentWeekCnt * 100 ) : '' );
      $hash->{helper}{mapZones}{$_}{lastDayAreaPct} = $hash->{helper}{mapZones}{$_}{currentDayAreaPct};
      $hash->{helper}{mapZones}{$_}{currentWeekAreaPct} = ( $sumCurrentWeekArea ? sprintf( "%.0f", $hash->{helper}{mapZones}{$_}{currentWeekArea} / $sumCurrentWeekArea * 100 ) : '' );
      $hash->{helper}{mapZones}{$_}{currentDayCntPct} = '';
      $hash->{helper}{mapZones}{$_}{currentDayAreaPct} = '';
    } @zonekeys;

  }
  # do on days
  if ( $time[6] == 1 ) {

    $hash->{helper}{statistics}{lastWeekTrack} = $hash->{helper}{statistics}{currentWeekTrack};
    $hash->{helper}{statistics}{lastWeekArea} = $hash->{helper}{statistics}{currentWeekArea};
    $hash->{helper}{statistics}{lastWeekTime} = $hash->{helper}{statistics}{currentWeekTime};
    $hash->{helper}{statistics}{currentWeekTrack} = 0;
    $hash->{helper}{statistics}{currentWeekArea} = 0;
    $hash->{helper}{statistics}{currentWeekTime} = 0;

    if ( AttrVal($name, 'mapZones', 0) && defined( $hash->{helper}{mapZones} ) ) {

      my @zonekeys = sort (keys %{$hash->{helper}{mapZones}});
      map { 
        $hash->{helper}{mapZones}{$_}{lastWeekCntPct} = $hash->{helper}{mapZones}{$_}{currentWeekCntPct};
        $hash->{helper}{mapZones}{$_}{lastWeekAreaPct} = $hash->{helper}{mapZones}{$_}{currentWeekAreaPct};
        $hash->{helper}{mapZones}{$_}{currentWeekCntPct} = '';
        $hash->{helper}{mapZones}{$_}{currentWeekAreaPct} = '';
      } @zonekeys;

    }

  }

  readingsSingleUpdate( $hash, 'api_callsThisMonth' , 0, 0) if ( $hash->{helper}{additional_polling} && $time[3] == 1 ); # reset monthly API calls

  #clear position arrays
  if ( AttrVal( $name, 'weekdaysToResetWayPoints', 1 ) =~ $time[6] ) {

    $hash->{helper}{areapos} = [];

  }

  return undef;
}

#########################
sub listStatisticsData {
  my ( $hash ) = @_;
  if ( $::init_done && $hash->{helper}{statistics} ) {

    my $name = $hash->{NAME};
    my $cnt = 0;
    my $ret = '';
    $ret .= '<html><table class="block wide">';
    $ret .= '<caption><b>Statistics Data</b></caption><tbody>'; 

    $ret .= '<tr class="col_header"><td> Hash Path </td><td> Value </td><td> Unit </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{statistics}{<b>numberOfChargingCycles</b>} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{statistics}{numberOfChargingCycles} . ' </td><td>  </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{statistics}{<b>numberOfCollisions</b>} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{statistics}{numberOfCollisions} . ' </td><td>  </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{statistics}{<b>totalChargingTime</b>} &emsp;</td><td> ' . sprintf( "%.0f", $hash->{helper}{mower}{attributes}{statistics}{totalChargingTime} / 3600 ) . ' </td><td> h </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{statistics}{<b>totalCuttingTime</b>} &emsp;</td><td> ' . sprintf( "%.0f", $hash->{helper}{mower}{attributes}{statistics}{totalCuttingTime} / 3600 ) . ' </td><td> h </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{statistics}{<b>totalRunningTime</b>} &emsp;</td><td> ' . sprintf( "%.0f", $hash->{helper}{mower}{attributes}{statistics}{totalRunningTime} / 3600 ) . '<sup>1</sup> </td><td> h </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{statistics}{<b>totalSearchingTime</b>} &emsp;</td><td> ' . sprintf( "%.0f", $hash->{helper}{mower}{attributes}{statistics}{totalSearchingTime} / 3600 ) . ' </td><td> h </td></tr>';

    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{statistics}{<b>currentDayTrack</b>} &emsp;</td><td> ' . sprintf( "%.0f", $hash->{helper}{statistics}{currentDayTrack} ) . ' </td><td> m </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{statistics}{<b>currentDayArea</b>} &emsp;</td><td> ' . sprintf( "%.0f", $hash->{helper}{statistics}{currentDayArea} ) . ' </td><td> qm </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{statistics}{<b>currentDayTime</b>} &emsp;</td><td> ' . sprintf( "%.0f", $hash->{helper}{statistics}{currentDayTime} ) . ' </td><td> s </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> <b>calculated speed</b> &emsp;</td><td> ' . sprintf( "%.2f", $hash->{helper}{statistics}{currentDayTrack} / $hash->{helper}{statistics}{currentDayTime} ) . ' </td><td> m/s </td></tr>' if ( $hash->{helper}{statistics}{currentDayTime} );

    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{statistics}{<b>lastDayTrack</b>} &emsp;</td><td> ' . sprintf( "%.0f", $hash->{helper}{statistics}{lastDayTrack} ) . ' </td><td> m </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{statistics}{<b>lastDayArea</b>} &emsp;</td><td> ' . sprintf( "%.0f", $hash->{helper}{statistics}{lastDayArea} ) . ' </td><td> qm </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{statistics}{<b>lastDayTime</b>} &emsp;</td><td> ' . sprintf( "%.0f", $hash->{helper}{statistics}{lastDayTime} ) . ' </td><td> s </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{statistics}{<b>lastDayCollisions</b>} &emsp;</td><td> ' . sprintf( "%.0f", $hash->{helper}{statistics}{lastDayCollisions} ) . ' </td><td>  </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> <b>last day calculated speed</b> &emsp;</td><td> ' . sprintf( "%.2f", $hash->{helper}{statistics}{lastDayTrack} / $hash->{helper}{statistics}{lastDayTime} ) . ' </td><td> m/s </td></tr>' if ( $hash->{helper}{statistics}{lastDayTime} );

    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{statistics}{<b>currentWeekTrack</b>} &emsp;</td><td> ' . sprintf( "%.0f", $hash->{helper}{statistics}{currentWeekTrack} ) . ' </td><td> m </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{statistics}{<b>currentWeekArea</b>} &emsp;</td><td> ' . sprintf( "%.0f", $hash->{helper}{statistics}{currentWeekArea} ) . ' </td><td> qm </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{statistics}{<b>currentWeekTime</b>} &emsp;</td><td> ' . sprintf( "%.0f", $hash->{helper}{statistics}{currentWeekTime} ) . ' </td><td> s </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{statistics}{<b>lastWeekTrack</b>} &emsp;</td><td> ' . sprintf( "%.0f", $hash->{helper}{statistics}{lastWeekTrack} ) . ' </td><td> m </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{statistics}{<b>lastWeekArea</b>} &emsp;</td><td> ' . sprintf( "%.0f", $hash->{helper}{statistics}{lastWeekArea} ) . ' </td><td> qm </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{statistics}{<b>lastWeekTime</b>} &emsp;</td><td> ' . sprintf( "%.0f", $hash->{helper}{statistics}{lastWeekTime} ) . ' </td><td> s </td></tr>';

    if ( AttrVal($name, 'mapZones', 0) && defined( $hash->{helper}{mapZones} ) ) {

    my @zonekeys = sort (keys %{$hash->{helper}{mapZones}});

    for ( @zonekeys ) {

      $cnt++;
      $ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ) . '"><td> $hash->{helper}{mapZones}{' . $_ . '}{<b>currentDayCntPct</b>} &emsp;</td><td> ' . ( $hash->{helper}{mapZones}{$_}{currentDayCntPct} ? $hash->{helper}{mapZones}{$_}{currentDayCntPct} : '' ) . ' </td><td> % </td></tr>';

    }

    for ( @zonekeys ) {

      $cnt++;
      $ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ) . '"><td> $hash->{helper}{mapZones}{' . $_ . '}{<b>lastDayCntPct</b>} &emsp;</td><td> ' . ( $hash->{helper}{mapZones}{$_}{lastDayCntPct} ? $hash->{helper}{mapZones}{$_}{lastDayCntPct} : '' ) . ' </td><td> % </td></tr>';

    }

    for ( @zonekeys ) {

      $cnt++;
      $ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ) . '"><td> $hash->{helper}{mapZones}{' . $_ . '}{<b>currentWeekCntPct</b>} &emsp;</td><td> ' . ( $hash->{helper}{mapZones}{$_}{currentWeekCntPct} ? $hash->{helper}{mapZones}{$_}{currentWeekCntPct} : '' ) . ' </td><td> % </td></tr>';

    }

    for ( @zonekeys ) {

      $cnt++;
      $ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ) . '"><td> $hash->{helper}{mapZones}{' . $_ . '}{<b>lastWeekCntPct</b>} &emsp;</td><td> ' . ( $hash->{helper}{mapZones}{$_}{lastWeekCntPct} ? $hash->{helper}{mapZones}{$_}{lastWeekCntPct} : '' ). ' </td><td> % </td></tr>';

    }

    for ( @zonekeys ) {

      $cnt++;
      $ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ) . '"><td> $hash->{helper}{mapZones}{' . $_ . '}{<b>currentDayAreaPct</b>} &emsp;</td><td> ' . ( $hash->{helper}{mapZones}{$_}{currentDayAreaPct} ? $hash->{helper}{mapZones}{$_}{currentDayAreaPct} : '' ) . ' </td><td> % </td></tr>';

    }

    for ( @zonekeys ) {

      $cnt++;
      $ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ) . '"><td> $hash->{helper}{mapZones}{' . $_ . '}{<b>lastDayAreaPct</b>} &emsp;</td><td> ' . ( $hash->{helper}{mapZones}{$_}{lastDayAreaPct} ? $hash->{helper}{mapZones}{$_}{lastDayAreaPct} : '' ) . ' </td><td> % </td></tr>';

    }

    for ( @zonekeys ) {

      $cnt++;
      $ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ) . '"><td> $hash->{helper}{mapZones}{' . $_ . '}{<b>currentWeekAreaPct</b>} &emsp;</td><td> ' . ( $hash->{helper}{mapZones}{$_}{currentWeekAreaPct} ? $hash->{helper}{mapZones}{$_}{currentWeekAreaPct} : '' ) . ' </td><td> % </td></tr>';

    }

    for ( @zonekeys ) {

      $cnt++;
      $ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ) . '"><td> $hash->{helper}{mapZones}{' . $_ . '}{<b>lastWeekAreaPct</b>} &emsp;</td><td> ' . ( $hash->{helper}{mapZones}{$_}{lastWeekAreaPct} ? $hash->{helper}{mapZones}{$_}{lastWeekAreaPct} : '' ). ' </td><td> % </td></tr>';

    }

  }

    $ret .= '</tbody></table>';
    $ret .= '<p><sup>1</sup> totalRunningTime = totalCuttingTime + totalSearchingTime';
    $ret .= '</html>';

    return $ret;

  } else {

    return '<html><table class="block wide"><tr><td>error codes are not yet available</td></tr></table></html>';

  }
}

#########################
sub listMowerData {
  my ( $hash ) = @_;
  my $name = $hash->{NAME};
  my $cnt = 0;
  my $ret = '';
  if ( $::init_done && defined( $hash->{helper}{mower}{type} ) ) {

    $ret .= '<html><table class="block wide">';
    $ret .= '<caption><b>Mower Data</b></caption><tbody>'; 

    $ret .= '<tr class="col_header"><td> Hash Path </td><td> Value </td><td> Unit </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{type} &emsp;</td><td> ' . $hash->{helper}{mower}{type} . ' </td><td>  </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{id} &emsp;</td><td> ' . $hash->{helper}{mower}{id} . ' </td><td>  </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{system}{name} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{system}{name} . ' </td><td>  </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{system}{model} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{system}{model} . ' </td><td>  </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{system}{serialNumber} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{system}{serialNumber} . ' </td><td>  </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{battery}{batteryPercent} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{battery}{batteryPercent} . ' </td><td> % </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{mower}{mode} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{mower}{mode} . ' </td><td>  </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{mower}{activity} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{mower}{activity} . ' </td><td>  </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{mower}{state} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{mower}{state} . ' </td><td>  </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{mower}{errorCode} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{mower}{errorCode} . ' </td><td>  </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{mower}{errorCodeTimestamp} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{mower}{errorCodeTimestamp} . ' </td><td> ms </td></tr>';

    my $calendarjson = eval { JSON::XS->new->pretty(1)->encode ($hash->{helper}{mower}{attributes}{calendar}{tasks}) };

    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td style="vertical-align:middle;" > $hash->{helper}{mower}{attributes}{calendar}{tasks} &emsp;</td><td colspan="2" style="word-wrap:break-word; max-width:34em;" > ' . ($@ ? $@ : $calendarjson) . ' </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{planner}{nextStartTimestamp} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{planner}{nextStartTimestamp} . ' </td><td>  </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{planner}{override}{action} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{planner}{override}{action} . ' </td><td>  </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{planner}{restrictedReason} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{planner}{restrictedReason} . ' </td><td>  </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{metadata}{connected} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{metadata}{connected} . ' </td><td>  </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{metadata}{statusTimestamp} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{metadata}{statusTimestamp} . ' </td><td> ms </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{positions}[0]{longitude} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{positions}[0]{longitude} . ' </td><td> decimal degree </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{positions}[0]{latitude} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{positions}[0]{latitude} . ' </td><td> decimal degree </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{settings}{cuttingHeight} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{settings}{cuttingHeight} . ' </td><td>  </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{settings}{headlight}{mode} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{settings}{headlight}{mode} . ' </td><td>  </td></tr>';
  #  $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{statistics}{cuttingBladeUsageTime} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{statistics}{cuttingBladeUsageTime} . ' </td><td>  </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{statistics}{numberOfChargingCycles} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{statistics}{numberOfChargingCycles} . ' </td><td>  </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{statistics}{numberOfCollisions} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{statistics}{numberOfCollisions} . ' </td><td>  </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{statistics}{totalChargingTime} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{statistics}{totalChargingTime} . ' </td><td> s </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{statistics}{totalCuttingTime} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{statistics}{totalCuttingTime} . ' </td><td> s </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{statistics}{totalRunningTime} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{statistics}{totalRunningTime} . '<sup>1</sup> </td><td> s </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{statistics}{totalSearchingTime} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{statistics}{totalSearchingTime} . ' </td><td> s </td></tr>';

    $ret .= '</tbody></table>';
    $ret .= '<p><sup>1</sup> totalRunningTime = totalCuttingTime + totalSearchingTime';
    $ret .= '</html>';

    return $ret;

  } else {

    return '<html><table class="block wide"><tr><td>mower data is not yet available</td></tr></table></html>';

  }
}

#########################
sub listErrorStack {
  my ( $hash ) = @_;
  my $name = $hash->{NAME};
  my $cnt = 0;
  my $ret = '';
  if ( $::init_done && defined( $hash->{helper}{mower}{type} ) && @{ $hash->{helper}{errorstack} } ) {

    $ret .= '<html><table class="block wide">';
    $ret .= '<caption><b>Last Errors</b></caption><tbody>'; 

    $ret .= '<tr class="col_header"><td> Timestamp </td><td> Description </td><td> &emsp;Zone &emsp;</td><td> Position </td></tr>';

    for ( my $i = 0; $i < @{ $hash->{helper}{errorstack} }; $i++ ) {

      $cnt++; $ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> ' . $hash->{helper}{errorstack}[$i]{errordate} . ' </td><td> ' . $hash->{helper}{errorstack}[$i]{errorstate} . ' - ' . $hash->{helper}{errorstack}[$i]{errordesc} . ' </td><td> ' . $hash->{helper}{errorstack}[$i]{errorzone} . ' </td><td> ' . $hash->{helper}{errorstack}[$i]{positions}[0]{longitude} . ' / ' . $hash->{helper}{errorstack}[$i]{positions}[0]{latitude} . ' </td></tr>';

    }

    $ret .= '</tbody></table>';
    $ret .= '</html>';

    return $ret;

  } else {

    return '<html><table class="block wide"><tr><td>No error in stack. </td></tr></table></html>';

  }
}

#########################
sub listInternalData {
  my ( $hash ) = @_;
  my $name = $hash->{NAME};
  my $cnt = 0;
  my $ret = '<html><table class="block wide">';
  $ret .= '<caption><b>Calculated Coordinates For Automatic Registration</b></caption><tbody>';

  my $xm = $hash->{helper}{chargingStation}{longitude} // 0;
  my $ym = $hash->{helper}{chargingStation}{latitude} // 0;
  my $csnr = scalar @{ $hash->{helper}{cspos} };
  my $csnrmax = $hash->{helper}{PARKED_IN_CS}{maxLength};
  my $arnr = 0;
  $arnr = scalar @{ $hash->{helper}{areapos} } if( scalar @{ $hash->{helper}{areapos} } > 2 );
  my $arnrmax = $hash->{helper}{MOWING}{maxLength};

  my $ernr = scalar @{ $hash->{helper}{lasterror}{positions} };

  $hash->{helper}{posMinMax} =~ /(-?\d*\.?\d+)\s(-?\d*\.?\d+)(\R|\s)(-?\d*\.?\d+)\s(-?\d*\.?\d+)/;

  if ( $::init_done && $1 && $2 && $4 && $5 ) {

    $ret .= '<tr class="col_header"><td> Data Sets ( max )&emsp;</td><td> Corner </td><td> Longitude </td><td> Latitude </td></tr>';
    $ret .= '<tr class="column odd"><td rowspan="2" style="vertical-align:middle;" > ' . $arnr . ' ( ' . $arnrmax . ' )&emsp;</td><td> Upper Left </td><td> ' . $1 . ' </td><td> ' . $2 . ' </td></tr>';
    $ret .= '<tr class="column even"><td> Lower Right </td><td> ' . $4 . ' </td><td> ' . $5 . ' </td></tr>';

    $ret .= '</tbody></table><p>';
    $ret .= '<table class="block wide">';
    $ret .= '<caption><b>Calculated Charging Station Coordinates</b></caption><tbody>'; 

    $ret .= '<tr class="col_header"><td> Data Sets (max)&emsp;</td><td> Longitude&emsp;</td><td> Latitude&emsp;</td></tr>';
    $ret .= '<tr class="column odd"><td> ' . $csnr . ' ( ' . $csnrmax . ' )&emsp;</td><td> ' . $xm . ' </td><td> ' . $ym . '&emsp;</td></tr>';

    $ret .= '</tbody></table><p>';
    $ret .= '<table class="block wide">';
    $ret .= '<caption><b>Way Point Stacks</b></caption><tbody>'; 

    $ret .= '<tr class="col_header"><td> Used For Activities&emsp;</td><td> Stack Name&emsp;</td><td> Current Size&emsp;</td><td> Max Size&emsp;</td></tr>';
    $ret .= '<tr class="column odd"><td>PARKED_IN_CS, CHARGING&emsp;</td><td> cspos&emsp;</td><td> ' . $csnr . ' </td><td> ' . $csnrmax . '&emsp;</td></tr>';
    $ret .= '<tr class="column even"><td>ALL&emsp;</td><td> areapos&emsp;</td><td> ' . $arnr . ' </td><td> ' . $arnrmax . '&emsp;</td></tr>';
    $ret .= '<tr class="column even"><td>NOT_APPLICABLE with error time stamp&emsp;</td><td> lasterror/positions&emsp;</td><td> ' . $ernr . ' </td><td> -&emsp;</td></tr>';

    $ret .= '</tbody></table>';
    if ( $hash->{TYPE} eq 'AutomowerConnect' ) {

      $ret .= '<p><table class="block wide">';
      $ret .= '<caption><b>Rest API Data</b></caption><tbody>'; 

      $cnt++;$ret .= '<tr class="column ' . ( $cnt % 2 ? "odd" : "even" ) . '"><td> Link to APIs</td><td><a target="_blank" href="https://developer.husqvarnagroup.cloud/">Husqvarna Developer</a></td></tr>';
      $cnt++;$ret .= '<tr class="column ' . ( $cnt % 2 ? "odd" : "even" ) . '"><td> Authentification API URL</td><td>' . AUTHURL . '</td></tr>';
      $cnt++;$ret .= '<tr class="column ' . ( $cnt % 2 ? "odd" : "even" ) . '"><td> Automower Connect API URL</td><td>' . APIURL . '</td></tr>';
      $cnt++;$ret .= '<tr class="column ' . ( $cnt % 2 ? "odd" : "even" ) . '"><td> Websocket IO Device name</td><td>' . WSDEVICENAME . '</td></tr>';
      $cnt++;$ret .= '<tr class="column ' . ( $cnt % 2 ? "odd" : "even" ) . '"><td> Client-Id</td><td>' . $hash->{helper}{client_id} . '</td></tr>';
      $cnt++;$ret .= '<tr class="column ' . ( $cnt % 2 ? "odd" : "even" ) . '"><td> Grant-Type</td><td>' . $hash->{helper}{grant_type} . '</td></tr>';
      $cnt++;$ret .= '<tr class="column ' . ( $cnt % 2 ? "odd" : "even" ) . '"><td> User-Id</td><td>' . ReadingsVal($name, '.user_id', '-') . '</td></tr>';
      $cnt++;$ret .= '<tr class="column ' . ( $cnt % 2 ? "odd" : "even" ) . '"><td> Provider</td><td>' . ReadingsVal($name, '.provider', '-') . '</td></tr>';
      $cnt++;$ret .= '<tr class="column ' . ( $cnt % 2 ? "odd" : "even" ) . '"><td> Scope</td><td>' . ReadingsVal($name, '.scope', '-') . '</td></tr>';
      $cnt++;$ret .= '<tr class="column ' . ( $cnt % 2 ? "odd" : "even" ) . '"><td> Token Type</td><td>' . ReadingsVal($name, '.token_type', '-') . '</td></tr>';
      $cnt++;$ret .= '<tr class="column ' . ( $cnt % 2 ? "odd" : "even" ) . '"><td> Token Expires</td><td> ' . FmtDateTime( ReadingsVal($name, '.expires', '0') ) . '</td></tr>';
      $cnt++;$ret .= '<tr class="column ' . ( $cnt % 2 ? "odd" : "even" ) . '"><td> Access Token</td><td style="word-wrap:break-word; max-width:40em">' . ReadingsVal($name, '.access_token', '0') . '</td></tr>';

      $ret .= '</tbody></table>';

    }

    $ret .= '</html>';
    return $ret;

  } else {

    return '<html><table class="block wide"><tr><td>Internal data is not yet available</td></tr></table></html>';

  }
}

#########################
sub listErrorCodes {
  if ($::init_done) {

    my $rowCount = 1;
    my %ec = ();
    my $ec = \%ec;
    for ( keys %{$errortable} ) {
      $ec->{sprintf("%03d",$_)} = $errortable->{$_} ; 
    }
    my $ret = '<html><table class="block wide">';
    $ret .= '<caption><b>API-Response Status Codes</b></caption><tbody>'; 
    $ret .= '<tr class="column odd"><td>200, 201, 202<br>204</td><td style="vertical-align:middle;" >response o.k.</td></tr>';
    $ret .= '<tr class="column even"><td>400, 401, 402<br>403, 404, 415<br>500, 503</td><td style="vertical-align:middle;" >error, detailed information see logfile</td></tr>';
    $ret .= '</tbody></table><p><table class="block wide">';
    $ret .= '<caption><b>Mower Error Table</b></caption><tbody>'; 
    for (sort keys %{$ec}) {
      $ret .= '<tr class="column ';
      $ret .= ( $rowCount % 2 ? "odd" : "even" );
      $ret .= '"><td>';
      $ret .= $_;
      $ret .= '</td><td>';
      $ret .= $ec->{$_};
      $ret .= '</td></tr>';
      $rowCount++;
    }
    
    $ret .= '</tbody></table></html>';
    return $ret;

  } else {

    return '<html><table class="block wide"><tr><td>error codes are not yet available</td></tr></table></html>';

  }
}

#########################
# Format mower timestamp assuming mower time is always set to daylight saving time, because it is the mowing period.
sub FmtDateTimeGMT {
  my $ti = shift // 0;
  my $ret = POSIX::strftime( "%F %H:%M:%S", gmtime( $ti ) );
}

##############################################################
#
# WEBSOCKET
#
##############################################################

sub wsKeepAlive {
  my ($hash) = @_;
  RemoveInternalTimer( $hash, \&wsKeepAlive);
  DevIo_Ping($hash);
  InternalTimer(gettimeofday() + $hash->{helper}{interval_ping}, \&wsKeepAlive, $hash, 0);
  
}

#########################
sub wsInit {

  my ( $hash ) = @_;
  $hash->{First_Read} = 1;
  RemoveInternalTimer( $hash, \&wsReopen );
  RemoveInternalTimer( $hash, \&wsKeepAlive );
  InternalTimer( gettimeofday() + $hash->{helper}{interval_ws}, \&wsReopen, $hash, 0 );
  InternalTimer( gettimeofday() + $hash->{helper}{interval_ping}, \&wsKeepAlive, $hash, 0 );
  return undef;

}

#########################
sub wsCb {
  my ($hash, $error) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $iam = "$type $name wsCb:";
  my $l = $hash->{devioLoglevel};
  Log3 $name, ( $l ? $l : 1 ), "$iam failed with error: $error" if( $error );
  return undef;

}

#########################
sub wsReopen {
  my ( $hash ) = @_;
  RemoveInternalTimer( $hash, \&wsReopen );
  RemoveInternalTimer( $hash, \&wsKeepAlive );
  DevIo_CloseDev( $hash ) if ( DevIo_IsOpen( $hash ) );
  $hash->{DeviceName} = WSDEVICENAME;
  DevIo_OpenDev( $hash, 0, \&wsInit, \&wsCb );

}

#########################
sub wsRead {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $iam = "$type $name wsRead:";
  my $additional_polling = $hash->{helper}{additional_polling} * 1000;
  my $use_position_polling = $hash->{helper}{use_position_polling};
  my $buf = DevIo_SimpleRead( $hash );
  return "" if ( !defined($buf) );

  if ( $buf ) {

    my $result = eval { decode_json($buf) };

    if ( $@ ) {

      Log3( $name, 1, "$iam - JSON error while request: $@\n\nbuffer content: >$buf<\n");

    } else {

      if ( defined( $result->{type} ) ) {

        $hash->{helper}{wsResult}{$result->{type}} = $result;
        $hash->{helper}{wsResult}{type} = $result->{type};

      } else {

        $hash->{helper}{wsResult}{other} = $result;

      }

      if ( defined( $result->{type} && $result->{id} eq $hash->{helper}{mower_id}) ) {

        if ( $result->{type} eq "status-event" ) {

          $hash->{helper}{statusTime} = gettimeofday();
          $hash->{helper}{mowerold}{attributes}{metadata}{statusTimestamp} = $hash->{helper}{mower}{attributes}{metadata}{statusTimestamp};
          $hash->{helper}{mowerold}{attributes}{mower}{activity} = $hash->{helper}{mower}{attributes}{mower}{activity};
          $hash->{helper}{mower}{attributes}{battery} = dclone( $result->{attributes}{battery} );
          $hash->{helper}{mower}{attributes}{metadata} = dclone( $result->{attributes}{metadata} );
          $hash->{helper}{mower}{attributes}{mower} = dclone( $result->{attributes}{mower} );
          $hash->{helper}{mower}{attributes}{planner} = dclone( $result->{attributes}{planner} );
          $hash->{helper}{storediff} = $hash->{helper}{mower}{attributes}{metadata}{statusTimestamp} - $hash->{helper}{mowerold}{attributes}{metadata}{statusTimestamp};
          $hash->{helper}{storesum} += $hash->{helper}{storediff} if ( $additional_polling );
          my $act = $result->{attributes}{mower}{activity};

          if ( !$additional_polling ) {

            isErrorThanPrepare( $hash );
            resetLastErrorIfCorrected( $hash );

          } elsif ( ( $additional_polling < $hash->{helper}{storesum} || $additional_polling && $act eq 'LEAVING' ) && !$hash->{helper}{midnightCycle} ) {

            $hash->{helper}{storesum} = 0;
            # RemoveInternalTimer( $hash, \&getMowerWs );
            # InternalTimer(gettimeofday() + 2,  \&getMowerWs, $hash, 0 );
            getMowerWs( $hash );
            Log3 $name, 4, "$iam received websocket data, and polling is on: >$buf<";
            $hash->{First_Read} = 0;
            return;

          }

        }

        if ( $result->{type} eq "positions-event" ) {

          if ( !$use_position_polling || $use_position_polling && !$additional_polling ) {

          $hash->{helper}{positionsTime} = gettimeofday();
          $hash->{helper}{mower}{attributes}{positions} = dclone( $result->{attributes}{positions} );

            AlignArray( $hash );
            FW_detailFn_Update ($hash);

          } elsif ( $use_position_polling && $additional_polling ) {

            Log3 $name, 4, "$iam received websocket data, but position polling is on: >$buf<";
            $hash->{First_Read} = 0;
            return;

          }

        }

        if ( $result->{type} eq "settings-event" ) {

          $hash->{helper}{mower}{attributes}{calendar} = dclone( $result->{attributes}{calendar} ) if ( defined ( $result->{attributes}{calendar} ) );
          $hash->{helper}{mower}{attributes}{settings}{headlight} = $result->{attributes}{headlight} if ( defined ( $result->{attributes}{headlight} ) );
          $hash->{helper}{mower}{attributes}{settings}{cuttingHeight} = $result->{attributes}{cuttingHeight} if ( defined ( $result->{attributes}{cuttingHeight} ) );

        }

        # Update readings
        readingsBeginUpdate($hash);

          fillReadings( $hash );
          readingsBulkUpdate( $hash, 'mower_wsEvent', $hash->{helper}{wsResult}{type} );

        readingsEndUpdate($hash, 1);

      }

    }

  }

  Log3 $name, 4, "$iam received websocket data: >$buf<";
  $hash->{First_Read} = 0;
  return;

}

#########################
sub wsReady {
  my  ($hash ) = @_;
  RemoveInternalTimer( $hash, \&wsReopen);
  RemoveInternalTimer( $hash, \&wsKeepAlive);
  return DevIo_OpenDev( $hash, 1, \&wsInit, \&wsCb );

}


##############################################################

1;

