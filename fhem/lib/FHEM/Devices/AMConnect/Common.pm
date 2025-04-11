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
use strict;
use warnings;
use POSIX;
use GPUtils qw(:all);
use FHEM::Core::Authentication::Passwords qw(:ALL);
use Time::HiRes qw(gettimeofday);
use Time::Local;
use DevIo;
use Storable qw(dclone retrieve store);
use DateTime;
use List::Util qw( min );
my $EMPTY = q{};
my $missingModul = $EMPTY;
## no critic (ProhibitConditionalUseStatements)
eval { use Readonly; 1 } or $missingModul .= 'Readonly ';

Readonly my $AUTHURL       => 'https://api.authentication.husqvarnagroup.dev/v1';
Readonly my $APIURL        => 'https://api.amc.husqvarna.dev/v1';
Readonly my $WSDEVICENAME  => 'wss:ws.openapi.husqvarna.dev:443/v1';
Readonly my $SPACE         => q{ };
Readonly    $EMPTY         => q{};
eval { use JSON; 1 } or $missingModul .= 'JSON ';
## use critic

# Import der FHEM Funktionen
BEGIN {
    GP_Import(
        qw(
          AttrVal
          CommandAttr
          CommandDeleteReading
          data
          defs
          DoTrigger
          FmtDateTime
          fhemTimeGm
          FW_ME
          FW_dir
          FW_wname
          FW_httpheader
          getKeyValue
          init_done
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
          setDevAttrList
          setKeyValue
          unicodeEncoding
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

require HttpUtils;

my $cvsid = '$Id$';

my $errorjson = '{"1":"Outside working area","":"No loop signal","3":"Wrong loop signal","4":"Loop sensor problem front","5 ":"Loop sensor problem rear","6":"Loop sensor problem left","7":"Loop sensor problem right","8":"Wrong PIN code","9":"Trapped","10":"Upside down","11":"Low battery","12":"Empty battery","13":"No drive","14":"Mower lifted","15":"Lifted","16":"Stuck in charging station","17":"Charging station blocked","18":"Collision sensor problem rear","19":"Collision sensor problem front","20":"Wheel motor blocked right","21":"Wheel motor blocked left","22":"Wheel drive problem right","23":"Wheel drive problem left","24":"Cutting system blocked","25":"Cutting system blocked","26":"Invalid sub-device combination","27":"Settings restored","28":"Memory circuit problem","29":"Slope too steep","30":"Charging system problem","31":"STOP button problem","32":"Tilt sensor problem","33":"Mower tilted","34":"Cutting stopped - slope too steep","35":"Wheel motor overloaded right","36":"Wheel motor overloaded left","37":"Charging current too high","38":"Electronic problem","39":"Cutting motor problem","40":"Limited cutting height range","41":"Unexpected cutting height adj","42":"Limited cutting height range","43":"Cutting height problem drive","44":"Cutting height problem curr","45":"Cutting height problem dir","46":"Cutting height blocked","47":"Cutting height problem","48":"No response from charger","49":"Ultrasonic problem","50":"Guide 1 not found","51":"Guide 2 not found","52":"Guide 3 not found","53":"GPS navigation problem","54":"Weak GPS signal","55":"Difficult finding home","56":"Guide calibration accomplished","57":"Guide calibration failed","58":"Temporary battery problem","59":"Temporary battery problem","60":"Temporary battery problem","61":"Temporary battery problem","62":"Temporary battery problem","63":"Temporary battery problem","64":"Temporary battery problem","65":"Temporary battery problem","66":"Battery problem","67":"Battery problem","68":"Temporary battery problem","69":"Alarm! Mower switched off","70":"Alarm! Mower stopped","71":"Alarm! Mower lifted","72":"Alarm! Mower tilted","73":"Alarm! Mower in motion","74":"Alarm! Outside geofence","75":"Connection changed","76":"Connection NOT changed","77":"Com board not available","78":"Slipped - Mower has Slipped.Situation not solved with moving pattern","79":"Invalid battery combination - Invalid combination of different battery types.","80":"Cutting system imbalance Warning","81":"Safety function faulty","82":"Wheel motor blocked rear right","83":"Wheel motor blocked rear left","84":"Wheel drive problem rear right","85":"Wheel drive problem rear left","86":"Wheel motor overloaded rear right","87":"Wheel motor overloaded rear left","88":"Angular sensor problem","89":"Invalid system configuration","90":"No power in charging station","91":"Switch cord problem","92":"Work area not valid","93":"No accurate position from satellites","94":"Reference station communication problem","95":"Folding sensor activated","96":"Right brush motor overloaded","97":"Left brush motor overloaded","98":"Ultrasonic Sensor 1 defect","99":"Ultrasonic Sensor 2 defect","100":"Ultrasonic Sensor 3 defect","101":"Ultrasonic Sensor 4 defect","102":"Cutting drive motor 1 defect","103":"Cutting drive motor 2 defect","104":"Cutting drive motor 3 defect","105":"Lift Sensor defect","106":"Collision sensor defect","107":"Docking sensor defect","108":"Folding cutting deck sensor defect","109":"Loop sensor defect","110":"Collision sensor error","111":"No confirmed position","112":"Cutting system major imbalance","113":"Complex working area","114":"Too high discharge current","115":"Too high internal current","116":"High charging power loss","117":"High internal power loss","118":"Charging system problem","119":"Zone generator problem","120":"Internal voltage error","121":"High internal temerature","122":"CAN error","123":"Destination not reachable","124":"Destination blocked","125":"Battery needs replacement","126":"Battery near end of life","127":"Battery problem","128":"Multiple reference stations detected","129":"Auxiliary cutting means blocked","130":"Imbalanced auxiliary cutting disc detected","131":"Lifted in link arm","132":"EPOS accessory missing","133":"Bluetooth com with CS failed","134":"Invalid SW configuration","135":"Radar problem","136":"Work area tampered","137":"High temperature in cutting motor right","138":"High temperature in cutting motor center","139":"High temperature in cutting motor left","141":"Wheel brush motor problem","143":"Accessory power problem","144":"Boundary wire problem","145":"No correction data available","147":"Cutting disc lost","148":"Chassis collision","701":"Connectivity problem","702":"Connectivity settings restored","703":"Connectivity problem","704":"Connectivity problem","705":"Connectivity problem","706":"Poor signal quality","707":"SIM card requires PIN","708":"SIM card locked","709":"SIM card not found","710":"SIM card locked","711":"SIM card locked","712":"SIM card locked","713":"Geofence problem","714":"Geofence problem","715":"Connectivity problem","716":"Connectivity problem","717":"SMS could not be sent","724":"Communication circuit board SW must be updated"}';

our $errortable = eval { JSON::XS->new->decode ( $errorjson ) }; ## no critic (ProhibitPackageVars)

if ($@) {
  return "FHEM::Devices::AMConnect::Common \$errortable: $@";
}
$errorjson = undef;

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
  my $client_id = $EMPTY;
  my $mowerNumber = 0;

  return "$iam install missing modul $missingModul" if( $missingModul );
  return "$iam too few parameters: define <NAME> $type <client_id> [<mower number>]" if( @val < 3 );

  $client_id =$val[2];
  $mowerNumber = $val[3] ? $val[3] : 0;

  my $mapAttr = <<'EOF';
areaLimitsColor="#ff8000"
areaLimitsLineWidth="1"
areaLimitsConnector=""
hullColor="#0066ff"
hullLineWidth="1"
hullConnector="1"
hullResolution="40"
hullCalculate="1"
hullSubtract=""
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
otherActivityPathDotWidth="2"
leavingPathLineColor="#33cc33"
leavingPathLineDash="6,2"
leavingPathLineWidth="1"
leavingPathDotWidth="2"
goingHomePathLineColor="#0099ff"
goingHomePathLineDash="6,2"
goingHomePathLineWidth="1"
goingHomePathDotWidth="2"
mowingPathDisplayStart=""
mowingPathLineColor="#ff0000"
mowingPathLineDash="6,2"
mowingPathLineWidth="1"
mowingPathDotWidth="2"
mowingPathUseDots=""
mowingPathShowCollisions=""
hideSchedulerButton=""
EOF

  my $mapZonesTpl = <<'EOF';
{
  "01_oben" : {
    "condition" : "$latitude > 52.6484600648553 || $longitude > 9.54799477359984 && $latitude > 52.64839739580418",
    "cuttingHeight" : "7"
  },
  "02_unten" : {
    "condition" : "undef",
    "cuttingHeight" : "3"
  }
}
EOF

  my $noPositionAttr =  "disable:1,0 " .
                        "disabledForIntervals " .
                        "mowerPanel:textField-long,85 " .
                        "mowerSchedule:textField-long " .
                        "addPollingMinInterval " .
                        $readingFnAttributes;

  %{ $hash } = ( %{ $hash },
    helper => {
      passObj                   => FHEM::Core::Authentication::Passwords->new($type),
      FWEXTA                    => {
        path                    => 'automowerconnect/',
        file                    => 'hull.js',
        url                     => 'https://raw.githubusercontent.com/AndriiHeonia/hull/master/dist/hull.js'
      },
      interval                  => 840,
      isDst                     => -1,
      no_position_attr          => $noPositionAttr,
      interval_ws               => 7110,
      interval_ping             => 570,
      use_position_polling      => 0,
      additional_polling        => 0,
      reverse_positions_order   => 1,
      reverse_pollpos_order     => 0,
      retry_interval_apiauth    => 840,
      retry_interval_getmower   => 840,
      retry_interval_wsreopen   => 2,
      timeout_apiauth           => 5,
      timeout_getmower          => 5,
      timeout_cmd               => 15,
      timeZoneName              => DateTime::TimeZone->new( name => 'local' )->name,
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
      newcollisions             => 0,
      newzonedatasets           => 0,
      cuttingHeightLatency      => 100,
      cuttingHeightLast         => 0,
      positionsTime             => 0,
      storesum                  => 0,
      statusTime                => 0,
      cspos                     => [],
      areapos                   => [],
      errorstack                => [],
      errorstackmax             => 5,
      lasterror                 => {
        positions               => [],
        timestamp               => 0,
        errordesc               => '-',
        errordate               => $EMPTY,
        errorstate              => $EMPTY
      },
      UNKNOWN                   => {
        short                   => 'U',
        arrayName               => $EMPTY,
        maxLength               => 100,
        cnt                     => 0
      },
      NOT_APPLICABLE            => {
        short                   => 'N',
        arrayName               => $EMPTY,
        maxLength               => 50,
        cnt                     => 0
      },
      NONE                      => {
        short                   => 'N',
        arrayName               => $EMPTY,
        maxLength               => 50,
        cnt                     => 0
      },
      MOWING                    => {
        short                   => 'M',
        arrayName               => 'areapos',
        maxLength               => 5000,
        maxLengthDefault        => 5000,
        cnt                     => 0
      },
      GOING_HOME                => {
        short                   => 'G',
        arrayName               => $EMPTY,
        maxLength               => 50,
        cnt                     => 0
      },
      CHARGING                  => {
        short                   => 'C',
        arrayName               => 'cspos',
        maxLength               => 100,
        cnt                     => 0
      },
      LEAVING                   => {
        short                   => 'L',
        arrayName               => $EMPTY,
        maxLength               => 50,
        cnt                     => 0
      },
      PARKED_IN_CS              => {
        short                   => 'P',
        arrayName               => 'cspos',
        maxLength               => 100,
        cnt                     => 0
      },
      STOPPED_IN_GARDEN         => {
        short                   => 'S',
        arrayName               => $EMPTY,
        maxLength               => 50,
        cnt                     => 0
      },
      statistics                => {
        currentSpeed            => 0,
        currentDayTrack         => 0,
        currentDayArea          => 0,
        currentDayTime          => 0,
        currentDayCollisions    => 0,
        lastDayTrack            => 0,
        lastDayArea             => 0,
        lastDaytime             => 0,
        lastDayCollisions       => 0,
        currentWeekTrack        => 0,
        currentWeekArea         => 0,
        currentWeekTime         => 0,
        lastWeekTrack           => 0,
        lastWeekArea            => 0,
        lastWeekTime            => 0,
        propertyArea            => 0,
        mowingArea              => 0,
        hullArea                => 0
      },
      wsbuf                     => {
        sum_changed             => 0,
        sum_duplicates          => 0,
        'position-event-v2'     => $EMPTY,
        'mower-event-v2'        => $EMPTY,
        'battery-event-v2'      => $EMPTY,
        'planner-event-v2'      => $EMPTY,
        'cuttingHeight-event-v2'=> $EMPTY,
        'headlights-event-v2'    => $EMPTY,
        'calendar-event-v2'     => $EMPTY,
        'message-event-v2'      => $EMPTY,
        position_changed        => 0,
        mower_changed           => 0,
        battery_changed         => 0,
        planner_changed         => 0,
        cuttingHeight_changed   => 0,
        headlights_changed       => 0,
        calendar_changed        => 0,
        message_changed         => 0,
        position_duplicates     => 0,
        mower_duplicates        => 0,
        battery_duplicates      => 0,
        planner_duplicates      => 0,
        cuttingHeight_duplicates=> 0,
        headlights_duplicates    => 0,
        calendar_duplicates     => 0,
        message_duplicates      => 0
      }
    }
  );
  
  ( $hash->{VERSION} ) = $::FHEM::AutomowerConnect::cvsid =~ /\.pm (.*)Z/; ## no critic (ProhibitPackageVars)
  $attr{$name}{room} = 'AutomowerConnect' if( !defined( $attr{$name}{room} ) );
  $attr{$name}{icon} = 'automower' if( !defined( $attr{$name}{icon} ) );
  ( $hash->{LIBRARY_VERSION} ) = $cvsid =~ /\.pm (.*)Z/;
  $WSDEVICENAME =~ /wss:(?<host>.*):(?<port>.*)/;
  $hash->{Host} = $+{host};
  $hash->{Port} = $+{port};
  $hash->{devioNoSTATE} = 1;

  AddExtension( $name, \&GetMap, "$type/$name/map" );
  AddExtension( $name, \&GetJson, "$type/$name/json" );

  if ( $init_done ) {

    my $attrVal = $attr{$name}{mapImagePath};

    if ( $attrVal || $attrVal =~ '(webp|png|jpg|jpeg)$' ) {

      $hash->{helper}{MAP_PATH} = $attrVal;
      $hash->{helper}{MAP_MIME} = "image/".$1;
      readMap( $hash );

    }

  }

    my $url = $hash->{helper}{FWEXTA}{url};
    my $path = $hash->{helper}{FWEXTA}{path};
    my $file = $hash->{helper}{FWEXTA}{file};
    mkdir( "$FW_dir/$path" ) if ( ! -d "$FW_dir/$path" );
    getTpFile( $hash, $url, "$FW_dir/$path", $file ) if ( ! -e "$FW_dir/$path/$file"); 

  if( $hash->{helper}->{passObj}->getReadPassword($name) ) {

    RemoveInternalTimer($hash);
    InternalTimer( gettimeofday() + 2, \&APIAuth, $hash, 1);

      readingsSingleUpdate( $hash, 'device_state', 'defined', 1 );

  } else {

      readingsSingleUpdate( $hash, 'device_state', 'defined - client_secret missing', 1 );

  }

  return;

}

#########################
sub Shutdown {
  my ( $hash, $arg )  = @_;

  DevIo_CloseDev( $hash ) if ( DevIo_IsOpen( $hash ) );
  DevIo_setStates( $hash, 'closed' );

  return;
}

#########################
sub Undefine {
  my ( $hash, $arg )  = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};

  RemoveInternalTimer( $hash );
  RemoveExtension( "$type/$name/map" );
  RemoveExtension( "$type/$name/json" );

  return;
}

##########################
sub Delete {
  my ( $hash, $arg ) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $iam ="$type $name Delete: ";
  Log3( $name, 5, "$iam called" );
  if ( scalar devspec2array( "TYPE=$type" ) == 1 ) {
    delete $data{FWEXT}{AutomowerConnect};
  }
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

  return;
}

#########################
sub FW_summaryFn {
  my ($FW_wname, $name, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $hash = $defs{$name};
  my $type = $hash->{TYPE};
  my $content = AttrVal($name, 'mowerPanel', $EMPTY);
  return $EMPTY if( AttrVal($name, 'disable', 0) || !$content || !$init_done);
  $content =~ s/command=['"](.*?)['"]/onclick="AutomowerConnectPanelCmd('set $name $1')"/g;
  return $content if ( $content =~ /IN_STATE/ );
  return;
}

#########################
sub FW_detailFn { ## no critic (ProhibitExcessComplexity [complexity core maintenance])
  my ($FW_wname, $name, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $hash = $defs{$name};
  my $type = $hash->{TYPE};
  my $iam = "$type $name FW_detailFn:";
  return $EMPTY if( AttrVal($name, 'disable', 0) || !$init_done || !$FW_ME );

  my $mapDesign = getDesignAttr( $hash );
  my $reta = "<div id='amc_${name}_schedule_buttons' name='fhem_amc_mower_schedule_buttons' ><button id='amc_${name}_schedule_button' onclick='AutomowerConnectSchedule( \"$name\" )' style='font-size:16px; ' >Mower Schedule</button>";
  # $reta .= "<label for='amc_${name}_select_workareas' > for Work Area: </label><select id='amc_${name}_select_workareas' name=work_areas_select>";
  # $reta .= "<option value='-1' selected >default</option>";
  # $reta .= "<select/>";
  $reta .= '</div>';
  return $reta if( !AttrVal ($name, 'showMap', 1 ) || !$hash->{helper}{mower}{attributes}{capabilities}{position} );

  my $img = "$FW_ME/$type/$name/map";

  my $zoom=AttrVal( $name,'mapImageZoom', 0.7 );
  my $backgroundcolor = AttrVal($name, 'mapBackgroundColor',$EMPTY);
  my $bgstyle = $backgroundcolor ? " background-color:$backgroundcolor;" : $EMPTY;

  my ($picx,$picy) = AttrVal( $name, 'mapImageWidthHeight', $hash->{helper}{imageWidthHeight} ) =~ /(\d+)\s(\d+)/;
  $picx=int($picx*$zoom);
  $picy=int($picy*$zoom);

  my ( $lonlo, $latlo, $dummy, $lonru, $latru ) = AttrVal( $name, 'mapImageCoordinatesToRegister', $hash->{helper}{posMinMax} ) =~ /(-?\d*\.?\d+)\s(-?\d*\.?\d+)(\R|\s)(-?\d*\.?\d+)\s(-?\d*\.?\d+)/;
  my $mapx = $lonlo-$lonru;
  my $mapy = $latlo-$latru;

  my ( $scx, $scy ) = AttrVal($name,'scaleToMeterXY', $hash->{helper}{scaleToMeterLongitude} . ' ' .$hash->{helper}{scaleToMeterLatitude}) =~ /(-?\d+)\s+(-?\d+)/;
  my $scalx = ( $lonru - $lonlo ) * $scx;
  my $scaly = ( $latlo - $latru ) * $scy;

  # CHARGING STATION POSITION 
  my $csimgpos = AttrVal( $name, 'chargingStationImagePosition', 'right' );
  my $xm = $hash->{helper}{chargingStation}{longitude} // 10.1165;
  my $ym = $hash->{helper}{chargingStation}{latitude} // 51.28;

  my ($cslo,$csla) = AttrVal( $name, 'chargingStationCoordinates', "$xm $ym" ) =~  /(-?\d*\.?\d+)\s(-?\d*\.?\d+)/;
  my $cslon = int(($lonlo-$cslo) * $picx / $mapx);
  my $cslat = int(($latlo-$csla) * $picy / $mapy);
  my $csdata = 'data-csimgpos="'.$csimgpos.'" data-cslon="'.$cslon.'" data-cslat="'.$cslat.'"';

  # AREA LIMITS
  my $arealimits = AttrVal( $name, 'mowingAreaLimits', $EMPTY );
  my $limi = $EMPTY;
  if ($arealimits) {
    my @lixy = (split(/\s|,|\R$/,$arealimits));
    my @liar = ();
    $limi = int( ( $lonlo - $lixy[ 0 ] ) * $picx / $mapx ) . "," . int( ( $latlo - $lixy[ 1 ] ) * $picy / $mapy );
    for (my $i=2;$i<@lixy;$i+=2){
      $limi .= ",".int( ( $lonlo - $lixy[ $i ] ) * $picx / $mapx).",".int( ( $latlo - $lixy[$i+1] ) * $picy / $mapy);
      my $x = ( $lonlo - $lixy[ $i ] ) * $scx;
      my $y = ( $latlo - $lixy[$i+1] ) * $scy;
      push( @liar, [ $x, $y ]);
    }
    my $x0 = ( $lonlo - $lixy[ 0 ] ) * $scx;
    my $y0 = ( $latlo - $lixy[ 1] ) * $scy;
    unshift( @liar, [ $x0, $y0 ]);
    push( @liar, [ $x0, $y0 ]);
    $hash->{helper}{statistics}{mowingArea} = int( abs( polygonArea( \@liar, 1, 1) ) );
  }
  $limi = 'data-areaLimitsPath="'.$limi.'"';

  # PROPERTY LIMITS
  my $propertylimits = AttrVal( $name, 'propertyLimits', $EMPTY );
  my $propli = $EMPTY;
  if ($propertylimits) {
    my @propxy = (split(/\s|,|\R$/,$propertylimits));
    my @liar = ();
    $propli = int(($lonlo-$propxy[0]) * $picx / $mapx).",".int(($latlo-$propxy[1]) * $picy / $mapy);
    for (my $i=2;$i<@propxy;$i+=2){
      $propli .= ",".int(($lonlo-$propxy[$i]) * $picx / $mapx).",".int(($latlo-$propxy[$i+1]) * $picy / $mapy);
      my $x = ( $lonlo - $propxy[ $i ] ) * $scx;
      my $y = ( $latlo - $propxy[$i+1] ) * $scy;
      push( @liar, [ $x, $y ]);
    }
    my $x0 = ( $lonlo - $propxy[ 0 ] ) * $scx;
    my $y0 = ( $latlo - $propxy[ 1] ) * $scy;
    unshift( @liar, [ $x0, $y0 ]);
    push( @liar, [ $x0, $y0 ]);
    $hash->{helper}{statistics}{propertyArea} = int( abs( polygonArea( \@liar, 1, 1) ) );
  }
  $propli = 'data-propertyLimitsPath="'.$propli.'"';

  # MOWING AREA HULL 
  my $hulljson = AttrVal($name, 'mowingAreaHull', '[]');
  my $hull = eval { JSON::XS->new->decode( $hulljson ) };
  if ( $@ ) {
    Log3 $name, 1, "$type $name FW_detailFn: decode error: $@ \n $hulljson";
    $hull = [];
  }

  $hash->{helper}{statistics}{hullArea} = int( polygonArea( $hull, $scalx/$picx, $scaly/$picy ) );
  $hash->{helper}{mapupdate}{hullxy} = $hull;

  my $ret = $EMPTY;
  $ret .= '<style>'
  .".${type}_${name}_div{padding:0px !important;"
  ."  $bgstyle background-image: url('$img');"
  ."  background-size: ${picx}px ${picy}px;"
  ."  background-repeat: no-repeat; "
  ."  width: ${picx}px; height: ${picy}px;"
  .'  position: relative;}'
  .".${type}_${name}_canvas_0{"
  .'  position: absolute; left: 0; top: 0; z-index: 0;}'
  .". ${type}_${name}_canvas_1{"
  .'  position: absolute; left: 0; top: 0; z-index: 1;}'
  .'</style>';
  my $content = AttrVal($name, 'mowerPanel', $EMPTY);
  my $contentflg = $content =~ /ON_TOP/;
  $content =~ s/command=['"](.*?)['"]/onclick="AutomowerConnectPanelCmd('set $name $1')"/g;
  $ret .= $content if ( $contentflg );
  my $mDesign = ${$mapDesign};
  $mDesign =~ s/data-hideSchedulerButton="1?"//;
  $ret .= "<div id='${type}_${name}_div' class='${type}_${name}_div' $mDesign $csdata $limi $propli width='$picx' height='$picy' >";
  $ret .= "<canvas id='${type}_${name}_canvas_0' class='${type}_${name}_canvas_0' width='$picx' height='$picy' ></canvas>";
  $ret .= "<canvas id='${type}_${name}_canvas_1' class='${type}_${name}_canvas_1' width='$picx' height='$picy' ></canvas>";
  $ret .= "</div>";
  $ret .=  $reta if( AttrVal ($name, 'showMap', 1 ) ) && ${ $mapDesign } =~ m/hideSchedulerButton=""/g;

  $ret .= "<div class='fhem_amc_hull_buttons' >";
  $ret .= "<button class='fhem_amc_hull_button' title='Sends the hull polygon points to attribute mowingAreaHull.' onclick='AutomowerConnectGetHull( \"$FW_ME/$type/$name/json\" )' style='font-size:12pt; ' >mowingAreaHullToAttribute</button>"
          if ( -e "$FW_dir/$hash->{helper}{FWEXTA}{path}/$hash->{helper}{FWEXTA}{file}" && !AttrVal( $name, 'mowingAreaHull', $EMPTY ) && ${ $mapDesign } =~ m/hullCalculate="1"/g );
  $ret .= "<button class='fhem_amc_hull_button' title='Subtracts hull polygon points from way points. To hide button set hullSubtract=\"\".' onclick='AutomowerConnectSubtractHull( \"$FW_ME/$type/$name/json\" )' style='font-size:12pt; ' >Subtract Hull</button>"
          if ( -e "$FW_dir/$hash->{helper}{FWEXTA}{path}/$hash->{helper}{FWEXTA}{file}" && AttrVal( $name, 'mowingAreaHull', $EMPTY ) && ${ $mapDesign } =~ m/hullSubtract="\d+"/g );
  $ret .= "</div>";
  $ret .= $content  if ( !$contentflg );

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
  return if( AttrVal($name, 'disable', 0) || !AttrVal($name, 'showMap', 1) || !$hash->{helper}{mower}{attributes}{capabilities}{position} );

  my @pos = @{ $hash->{helper}{areapos} };
  my @poserr = @{ $hash->{helper}{lasterror}{positions} };

  my ( $lonlo, $latlo, $dummy, $lonru, $latru ) = AttrVal( $name,'mapImageCoordinatesToRegister',$hash->{helper}{posMinMax} ) =~ /(-?\d*\.?\d+)\s(-?\d*\.?\d+)(\R|\s)(-?\d*\.?\d+)\s(-?\d*\.?\d+)/;

  my $zoom = AttrVal( $name,'mapImageZoom', 0.7 );
  
  my ($picx,$picy) = AttrVal( $name,'mapImageWidthHeight', $hash->{helper}{imageWidthHeight} ) =~ /(\d+)\s(\d+)/;

  my ( $scaleToMeterX, $scaleToMeterY ) = AttrVal( $name,'scaleToMeterXY', $hash->{helper}{scaleToMeterLongitude} . $SPACE .$hash->{helper}{scaleToMeterLatitude} ) =~ /(-?\d+)\s+(-?\d+)/;
  my $scalx = ( $lonru - $lonlo ) * $scaleToMeterX;
  my $scaly = ( $latlo - $latru ) * $scaleToMeterY;

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
  $hash->{helper}{mapupdate}{scaly} = $scaly;
  $hash->{helper}{mapupdate}{errdesc} = [ "$errdesc", "$errdate", "$errstate" ];
  $hash->{helper}{mapupdate}{posxy} = \@posxy;
  $hash->{helper}{mapupdate}{poserrxy} = \@poserrxy;

  for ( devspec2array( 'TYPE=FHEMWEB' ) ) { 
    ::FW_directNotify( "#FHEMWEB:$_", "AutomowerConnectUpdateJson ( '$FW_ME/$type/$name/json' )", $EMPTY ) if ( $FW_ME );
  }

  $hash->{helper}{detailFnFirst} = 0;

return;
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

  if ( IsDisabled( $name ) ) {

    if ( IsDisabled( $name ) == 1 and ReadingsVal( $name, 'device_state', $EMPTY ) ne 'disabled' ) {

      readingsSingleUpdate( $hash, 'device_state', 'disabled', 1 );

    } elsif ( IsDisabled( $name ) == 2 and ReadingsVal( $name, 'device_state', $EMPTY ) ne 'temporarily disabled' ) {

      readingsSingleUpdate( $hash, 'device_state', 'temporarily disabled', 1 );

    }

    RemoveInternalTimer( $hash );
    InternalTimer( gettimeofday() + $hash->{helper}{retry_interval_apiauth}, \&APIAuth, $hash, 0 );
    return;

  }

  if ( !$update && $init_done ) {

    if ( ReadingsVal( $name,'.access_token',$EMPTY ) and gettimeofday() < (ReadingsVal( $name, '.expires', 0 ) - 45 ) ) {

      $hash->{header} = { "Authorization", "Bearer ". ReadingsVal( $name,'.access_token',$EMPTY ) };
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
        url         => $AUTHURL . '/oauth2/token',
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
  return;
}

#########################
sub APIAuthResponse {
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $statuscode = $param->{code} // $EMPTY;
  my $iam = "$type $name APIAuthResponse:";

  Log3 $name, 1, "$iam response time ". sprintf( "%.2f", ( gettimeofday() - $param->{t_begin} ) ) . ' s' if ( $param->{timeout} == 60 );
  Log3 $name, 5, "$iam \n\$statuscode [$statuscode]\n\$err [$err],\n \$data [$data] \n\$param->url $param->{url}";

  if( !$err && $statuscode == 200 && $data) {

    my $result = eval { JSON::XS->new->utf8( not $unicodeEncoding )->decode( $data ) };
    if ($@) {

      Log3 $name, 2, "$iam JSON error [ $@ ]";
      readingsSingleUpdate( $hash, 'device_state', 'error JSON', 1 );

    } else {

      $hash->{helper}->{auth} = $result;
      $hash->{header} = { 'Authorization', "Bearer $hash->{helper}{auth}{access_token}" };
      
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
      return;
    }

  } else {

    readingsSingleUpdate( $hash, 'device_state', "error statuscode $statuscode", 1 );
    Log3 $name, 1, "\n$iam\n\$statuscode [$statuscode]\n\$err [$err],\n\$data [$data]\n\$param->url $param->{url}";

  }

  RemoveInternalTimer( $hash, \&APIAuth );
  InternalTimer( gettimeofday() + $hash->{helper}{retry_interval_apiauth}, \&APIAuth, $hash, 0 );
  Log3 $name, 1, "$iam failed retry in $hash->{helper}{retry_interval_apiauth} seconds.";
  DoTrigger($name, 'AUTHENTICATION ERROR');

  return;

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
  my $access_token = ReadingsVal($name,".access_token",$EMPTY);
  my $provider = ReadingsVal($name,'.provider',$EMPTY);
  my $client_id = $hash->{helper}->{client_id};
  my $timeout = AttrVal( $name, 'timeoutGetMower', $hash->{helper}->{timeout_getmower} );

  my $header = "Accept: application/vnd.api+json\r\nX-Api-Key: " . $client_id . "\r\nAuthorization: Bearer " . $access_token . "\r\nAuthorization-Provider: " . $provider;
  Log3 $name, 5, "$iam header [ $header ]";
  readingsSingleUpdate( $hash, 'api_callsThisMonth' , ReadingsVal( $name, 'api_callsThisMonth', 0 ) + 1, 0) if ( $hash->{helper}{additional_polling} );

  ::HttpUtils_NonblockingGet({
    url        => $APIURL . '/mowers',
    timeout    => $timeout,
    hash       => $hash,
    method     => "GET",
    header     => $header,  
    callback   => \&getMowerResponse,
    t_begin    => scalar gettimeofday()
  });

  return;
}

#########################
sub getMowerResponse {
  
  my ( $param, $err, $data ) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $statuscode = $param->{code} // $EMPTY;
  my $iam = "$type $name getMowerResponse:";
  my $mowerNumber = $hash->{helper}{mowerNumber};
  
  Log3 $name, 1, "$iam response time ". sprintf( "%.2f", ( gettimeofday() - $param->{t_begin} ) ) . ' s' if ( $param->{timeout} == 60 );
  Log3 $name, 4, "$iam response \$statuscode >$statuscode<, \$err >$err<, \$param->url $param->{url} \n\$data >$data<";
  
  if( !$err && $statuscode == 200 && $data) {
    
    if ( $data eq '[]' ) {
      
      Log3 $name, 2, "$iam no mower data present";
      
    } else {

      my $result = eval { JSON::XS->new->utf8( not $unicodeEncoding )->decode( $data ) };

      if ($@) {

        Log3( $name, 2, "$iam - JSON error while request: $@");

      } else {

        $hash->{helper}{mowers} = $result->{data};

        my $maxMower = 0;
        $maxMower = @{$hash->{helper}{mowers}} if ( ref ( $hash->{helper}{mowers} ) eq 'ARRAY' );

        if ($maxMower <= $mowerNumber || $mowerNumber < 0 ) {

          Log3 $name, 2, "$iam wrong mower number $mowerNumber ($maxMower mower available). Change definition of $name.";
          return;

        }

        my $foundMower = '0 => ' . $hash->{helper}{mowers}[0]{attributes}{system}{name} . $SPACE . $hash->{helper}{mowers}[0]{id};
        for (my $i = 1; $i < $maxMower; $i++) {

          $foundMower .= "\n" . $i .' => '. $hash->{helper}{mowers}[$i]{attributes}{system}{name} . $SPACE . $hash->{helper}{mowers}[$i]{id};

        }

        $hash->{helper}{foundMower} = $foundMower;
        Log3 $name, 5, "$iam found $foundMower ";

        processingMowerResponse( $hash );

        # schedule new access token
        RemoveInternalTimer( $hash, \&getNewAccessToken );
        InternalTimer( ReadingsVal($name, '.expires', 600)-37, \&getNewAccessToken, $hash, 0 );

        # Websocket initialisieren, schedule ping, reopen
        RemoveInternalTimer( $hash, \&wsReopen );
        InternalTimer( gettimeofday() + 1.5, \&wsReopen, $hash, 0 );
        $hash->{helper}{midnightCycle} = 0;

        return;

      }

    }

  } else {

    readingsSingleUpdate( $hash, 'device_state', "error statuscode $statuscode", 1 );
    Log3 $name, 1, "$iam \$statuscode >$statuscode<, \$err >$err<, \$param->url $param->{url} \n\$data >$data<";
    DoTrigger($name, 'MOWERAPI ERROR');

  }

  RemoveInternalTimer( $hash, \&APIAuth );
  InternalTimer( gettimeofday() + $hash->{helper}{retry_interval_getmower}, \&APIAuth, $hash, 0 );
  Log3 $name, 1, "$iam failed retry in $hash->{helper}{retry_interval_getmower} seconds.";

  return;

}

#########################
sub processingMowerResponse {

  my ( $hash ) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $iam = "$type $name processingMowerResponse:";
  my $mowerNumber = $hash->{helper}{mowerNumber};
  my $foundMower = defined( $hash->{helper}{foundMower} ) ? $hash->{helper}{foundMower} : undef;

  if ( defined ( $hash->{helper}{mower}{id} ) && $hash->{helper}{midnightCycle} ) { # update dataset

    $hash->{helper}{mowerold}{attributes}{metadata}{statusTimestamp} = $hash->{helper}{mower}{attributes}{metadata}{statusTimestamp};
    $hash->{helper}{mowerold}{attributes}{mower}{activity} = $hash->{helper}{mower}{attributes}{mower}{activity};
    $hash->{helper}{mowerold}{attributes}{statistics}{numberOfCollisions} = $hash->{helper}{mower}{attributes}{statistics}{numberOfCollisions};

  } elsif ( !defined ($hash->{helper}{mower}{id}) ) { # first data set

    $hash->{helper}{mowerold}{attributes}{metadata}{statusTimestamp} = $hash->{helper}{mowers}[$mowerNumber]{attributes}{metadata}{statusTimestamp};
    $hash->{helper}{mowerold}{attributes}{mower}{activity} = $hash->{helper}{mowers}[$mowerNumber]{attributes}{mower}{activity};
    $hash->{helper}{mowerold}{attributes}{statistics}{numberOfCollisions} = $hash->{helper}{mowers}[$mowerNumber]{attributes}{statistics}{numberOfCollisions};
    $hash->{helper}{statistics}{numberOfCollisionsOld} = $hash->{helper}{mowers}[$mowerNumber]{attributes}{statistics}{numberOfCollisions};

    if ( $hash->{helper}{mowers}[$mowerNumber]{attributes}{capabilities}{position} ) {

      $hash->{helper}{searchpos} = [ dclone $hash->{helper}{mowers}[$mowerNumber]{attributes}{positions}[0] ];

      if ( AttrVal( $name, 'mapImageCoordinatesToRegister', $EMPTY ) eq $EMPTY ) {
        posMinMax( $hash, $hash->{helper}{mowers}[$mowerNumber]{attributes}{positions} );
      }

    }

  }

  $hash->{helper}{mower} = dclone( $hash->{helper}{mowers}[$mowerNumber] );
  $hash->{helper}{mower_id} = $hash->{helper}{mower}{id};
  $hash->{helper}{newdatasets} = 0;

  if ( $hash->{helper}{mower}{attributes}{capabilities}{position} ) {
    setDevAttrList( $name );
  } else {
    setDevAttrList( $name, $hash->{helper}{no_position_attr} );
  }

  $hash->{helper}{storediff} = $hash->{helper}{mower}{attributes}{metadata}{statusTimestamp} - $hash->{helper}{mowerold}{attributes}{metadata}{statusTimestamp};

  calculateStatistics( $hash ) if ( $hash->{helper}{midnightCycle} );
  $hash->{helper}{midnightCycle} = 0;

  # Update readings
  readingsBeginUpdate( $hash );

    readingsBulkUpdateIfChanged( $hash, 'api_MowerFound', $foundMower ) if ( $foundMower );
    fillReadings( $hash );
    readingsBulkUpdate( $hash, 'device_state', 'connected' );

  readingsEndUpdate( $hash, 1 );
  return;
}

#########################
sub getMowerWs {
  my $hash = shift;
  my $endpoint = shift // $EMPTY;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $iam = "$type $name getMowerWs:";
  my $access_token = ReadingsVal( $name, '.access_token', $EMPTY );
  my $provider = ReadingsVal( $name, '.provider', $EMPTY );
  my $client_id = $hash->{helper}->{client_id};
  my $timeout = AttrVal( $name, 'timeoutGetMower', $hash->{helper}->{timeout_getmower} );
  my $callback = \&getMowerResponseWs;

  my $header = "Accept: application/vnd.api+json\r\nX-Api-Key: " . $client_id . "\r\nAuthorization: Bearer " . $access_token . "\r\nAuthorization-Provider: " . $provider;
  Log3 $name, 5, "$iam header [ $header ]";
  readingsSingleUpdate( $hash, 'api_callsThisMonth' , ReadingsVal( $name,  'api_callsThisMonth', 0 ) + 1, 0) if ( $hash->{helper}{additional_polling} );

  if ( $endpoint eq 'messages') { $callback = \&getEndpointResponse }

  ::HttpUtils_NonblockingGet( {
    url        => $APIURL . '/mowers/' . $hash->{helper}{mower}{id} . ($endpoint ? '/' . $endpoint : $EMPTY),
    timeout    => $timeout,
    hash       => $hash,
    method     => "GET",
    header     => $header,  
    callback   => $callback,
    endpoint   => $endpoint,
    t_begin    => scalar gettimeofday()
  } );

  return;
}

#########################
sub getEndpointResponse {

  my ( $param, $err, $data ) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $statuscode = $param->{code} // $EMPTY;
  my $endpoint = $param->{endpoint} // $EMPTY;
  my $iam = "$type $name getEndpointResponse:";

  Log3 $name, 1, "$iam response time ". sprintf( "%.2f", ( gettimeofday() - $param->{t_begin} ) ) . ' s' if ( $param->{timeout} == 60 );
  Log3 $name, 4, "$iam response calling \$endpoint >$endpoint<, \$statuscode >$statuscode<, \$err >$err<, \$param->url $param->{url} \n \$data >$data<";

  if ( !$err && $statuscode == 200 && $data) {

    if ( $data eq $EMPTY ) {

      Log3 $name, 2, "$iam no mower data present";

    } else {

      my $result = eval { JSON::XS->new->allow_nonref(0)->utf8( not $unicodeEncoding )->decode( $data ) };

      if ( $@ ) {

        Log3( $name, 2, "$iam - JSON error while request: $@");

      } elsif ( $endpoint eq 'messages' ) {

        if ( defined $result->{data}{attributes}{messages} ) {

          $hash->{helper}{endpoints}{$endpoint} = $result->{data};
          $hash->{helper}->{mower_commandStatus} = 'OK - messages';
          $hash->{helper}->{mower_commandSend} = 'messages';

        } else {

          $hash->{helper}->{mower_commandStatus} = 'OK - no messages recieved';
          $hash->{helper}->{mower_commandSend} = 'messages';

        }

      }

      readingsBeginUpdate($hash);

        readingsBulkUpdateIfChanged( $hash, 'mower_commandStatus', $hash->{helper}{mower_commandStatus}, 1 );
        readingsBulkUpdateIfChanged( $hash, 'mower_commandSend', $hash->{helper}{mower_commandSend}, 1 );

      readingsEndUpdate($hash, 1);

    }

  } else {

    readingsBeginUpdate($hash);

      readingsBulkUpdateIfChanged( $hash, 'mower_commandStatus', "ERROR statuscode $statuscode", 1 );
      readingsBulkUpdateIfChanged( $hash, 'mower_commandSend', $hash->{helper}{mower_commandSend}, 1 );

    readingsEndUpdate($hash, 1);

    Log3 $name, 1, "$iam \$statuscode >$statuscode<, \$err >$err<,\n \$data [$data] \n\$param->url $param->{url}";
    DoTrigger($name, 'MOWERAPI ERROR');

  }

  return;

}

#########################
sub getMowerResponseWs {

  my ( $param, $err, $data ) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $statuscode = $param->{code} // $EMPTY;
  my $iam = "$type $name getMowerResponseWs:";

  Log3 $name, 1, "$iam response time ". sprintf( "%.2f", ( gettimeofday() - $param->{t_begin} ) ) . ' s' if ( $param->{timeout} == 60 );
  Log3 $name, 5, "$iam response polling after mower-event-v2 \$statuscode >$statuscode<, \$err >$err<, \$param->url $param->{url} \n \$data >$data<";
   ## no critic (ProhibitDeepNests [complexity core maintenance])
  if( !$err && $statuscode == 200 && $data) {

    if ( $data eq $EMPTY ) {

      Log3 $name, 2, "$iam no mower data present";

    } else {

      my $result = eval { JSON::XS->new->utf8( not $unicodeEncoding )->decode( $data ) };

      if ($@) {

        Log3( $name, 2, "$iam - JSON error while request: $@");

      } else {

        $hash->{helper}{wsResult}{mower} = dclone( $result->{data} ) if ( AttrVal($name, 'debug', $EMPTY) );
        $hash->{helper}{mower}{attributes} = dclone( $result->{data}{attributes} );

        if ( $hash->{helper}{use_position_polling} && $hash->{helper}{mower}{attributes}{capabilities}{position} ) {

          my $cnt = 0;
          my $tmp = [];
          my $poslen = @{ $result->{data}{attributes}{positions} };

          for ( $cnt = 0; $cnt < $poslen; $cnt++ ) { 

            if (   $hash->{helper}{searchpos}[ 0 ]{longitude} == $result->{data}{attributes}{positions}[ $cnt ]{longitude}
                && $hash->{helper}{searchpos}[ 0 ]{latitude} == $result->{data}{attributes}{positions}[ $cnt ]{latitude} || $cnt == $poslen -1) { # if nothing found take all

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

          $hash->{helper}{searchpos} = [ dclone $result->{data}{attributes}{positions}[ 0 ] ];

        }

        isErrorThanPrepare( $hash );
        resetLastErrorIfCorrected( $hash );

        # Update readings
        readingsBeginUpdate($hash);

          fillReadings( $hash );
          # readingsBulkUpdate( $hash, 'mower_wsEvent', 'additionnal-polling' );
          readingsBulkUpdateIfChanged( $hash, 'device_state', 'connected' );

        readingsEndUpdate($hash, 1);

        return;

      }

    }
    
  } else {

    readingsSingleUpdate( $hash, 'device_state', "additional Polling error statuscode $statuscode", 1 );
    Log3 $name, 1, "$iam \$statuscode [$statuscode]\n\$err [$err],\n \$data [$data] \n\$param->url $param->{url}";
    DoTrigger($name, 'MOWERAPI ERROR');


  }
  ## use critic
  return;

}

#########################
sub additionalPollingWS {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $iam = "$type $name additionalPollingWS:";
  my $additional_polling = $hash->{helper}{additional_polling} * 1000;
  my $act = $hash->{helper}{mower}{attributes}{mower}{activity};

  #respect polling min interval
  if ( $additional_polling < $hash->{helper}{storesum} && !$hash->{helper}{midnightCycle} ) {

    $hash->{helper}{storesum} = 0;
    RemoveInternalTimer( $hash, \&getMowerWs );
    InternalTimer(gettimeofday() + 1,  \&getMowerWs, $hash, 0 );
    Log3 $name, 4, "$iam Done!";

    return 1;

  }

  return;
}

#########################
sub getNewAccessToken {
  my ($hash) = @_;
  $hash->{helper}{midnightCycle} = 1;
  APIAuth( $hash );
  return;
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

  Log3 $name, 4, "$iam called with $setName " . ($setVal ? $setVal : $EMPTY);

  if ( $setName eq 'html' ) { ## no critic (ProhibitCascadingIfElse [complexity core maintenance pbp])
    
    my $ret = '<html>' . FW_detailFn( undef, $name, undef, undef) . '</html>';
    return $ret;

  } elsif (  $setName eq 'errorCodes' ) {

    my $ret = listErrorCodes();
    return $ret;

  } elsif (  $setName eq 'InternalData' ) {

    my $ret = listInternalData($hash);
    return $ret;

  } elsif ( $setName eq 'MowerData' ) {

    my $ret = listMowerData($hash);
    return $ret;

  } elsif (  $setName eq 'StatisticsData' ) {

    my $ret = listStatisticsData($hash);
    return $ret;

  } elsif ( $setName eq 'errorStack' ) {

    my $ret = listErrorStack($hash);
    return $ret;

  } else {

    return "Unknown argument $setName, choose one of StatisticsData:noArg MowerData:noArg InternalData:noArg errorCodes:noArg errorStack:noArg ";

  }
}

#########################
sub Set { ## no critic (ProhibitExcessComplexity [complexity core maintenance])
  my ($hash,@val) = @_;
  my $type = $hash->{TYPE};
  my $name = $hash->{NAME};
  my $iam = "$type $name Set:";
  my $cmd_blocking = 'defined|initialized|authentification|authenticated|update';

  return "$iam: needs at least one argument" if ( @val < 2 );
  return "Unknown argument, $iam is disabled, choose one of none:noArg" if ( IsDisabled( $name ) );

  my ($pname,$setName,$setVal,$setVal2,$setVal3) = @val;

  Log3 $name, 4, "$iam called with $setName " . ($setVal ? $setVal : $EMPTY) if ( $setName !~ /^(?:\?|client_secret)$/ );

  ########## Device Setter ##########
  if ( !$hash->{helper}{midnightCycle} && $setName eq 'getUpdate' ) { ## no critic (ProhibitCascadingIfElse [complexity core maintenance pbp])

    RemoveInternalTimer($hash, \&APIAuth);
    APIAuth($hash);
    return;

  ##########
  } elsif ( $setName eq 'chargingStationPositionToAttribute' && $hash->{helper}{mower}{attributes}{capabilities}{position} ) {

    my $xm = $hash->{helper}{chargingStation}{longitude} // 10.1165;
    my $ym = $hash->{helper}{chargingStation}{latitude} // 51.28;
    CommandAttr( $hash, "$name chargingStationCoordinates $xm $ym" );
    return;

  ##########
  } elsif ( $setName eq 'defaultDesignAttributesToAttribute' && $hash->{helper}{mower}{attributes}{capabilities}{position} ) {

    my $design = $hash->{helper}{mapdesign};
    CommandAttr( $hash, "$name mapDesignAttributes $design" );
    return;

  ##########
  } elsif ( $setName eq 'mapZonesTemplateToAttribute' && $hash->{helper}{mower}{attributes}{capabilities}{position} ) {

    my $tpl = $hash->{helper}{mapZonesTpl};
    CommandAttr( $hash, "$name mapZones $tpl" );
    return;

  ##########
  } elsif ( $setName eq 'mowerScheduleToAttribute' ) {

    my $calendarjson = eval {
      require JSON::PP;
      my %ORDER=(start=>1,duration=>2,monday=>3,tuesday=>4,wednesday=>5,thursday=>6,friday=>7,saturday=>8,sunday=>9,workAreaId=>10);
      JSON::PP->new->sort_by(
        sub {($ORDER{$JSON::PP::a} // 999) <=> ($ORDER{$JSON::PP::b} // 999) or $JSON::PP::a cmp $JSON::PP::b}) ## no critic (ProhibitPackageVars)
        ->pretty(1)->utf8( not $unicodeEncoding )->encode( $hash->{helper}{mower}{attributes}{calendar}{tasks} )
    };
    return "$iam $@" if ($@);
    
    CommandAttr($hash,"$name mowerSchedule $calendarjson");
    return;

  ##########
  } elsif ( $setName eq 'sendJsonScheduleToAttribute' ) {

    my $calendarjson = eval { JSON::XS->new->decode ( $setVal ) };
    return "$iam decode error: $@ \n $setVal" if ($@);
    $calendarjson = eval {
      require JSON::PP;
      my %ORDER=(start=>1,duration=>2,monday=>3,tuesday=>4,wednesday=>5,thursday=>6,friday=>7,saturday=>8,sunday=>9,workAreaId=>10);
      JSON::PP->new->sort_by(
        sub {($ORDER{$JSON::PP::a} // 999) <=> ($ORDER{$JSON::PP::b} // 999) or $JSON::PP::a cmp $JSON::PP::b}) ## no critic (ProhibitPackageVars)
        ->pretty(1)->utf8( not $unicodeEncoding )->encode( $calendarjson )
    };
    return "$iam encode error: $@ in \$calendarjson" if ($@);
    CommandAttr($hash,"$name mowerSchedule $calendarjson");

  return;

  ##########
  } elsif ( $setName eq 'client_secret' ) {
    if ( $setVal ) {

      my ($passResp, $passErr) = $hash->{helper}->{passObj}->setStorePassword($name, $setVal);
      Log3 $name, 1, "$iam error: $passErr" if ($passErr);
      return "$iam $passErr" if( $passErr );

      readingsBeginUpdate($hash);
        readingsBulkUpdateIfChanged( $hash, '.access_token', $EMPTY, 0 );
        readingsBulkUpdateIfChanged( $hash, 'device_state', 'initialized');
        readingsBulkUpdateIfChanged( $hash, 'mower_commandStatus', 'cleared');
      readingsEndUpdate($hash, 1);
      
      RemoveInternalTimer($hash, \&APIAuth);
      APIAuth($hash);
      return;
    }

  ########## Mower Setter ##########
  } elsif ( $setName eq 'getNewAccessToken' ) {

    readingsBeginUpdate($hash);
      readingsBulkUpdateIfChanged( $hash, '.access_token', $EMPTY, 0 );
      readingsBulkUpdateIfChanged( $hash, 'device_state', 'initialized');
      readingsBulkUpdateIfChanged( $hash, 'mower_commandStatus', 'cleared');
    readingsEndUpdate($hash, 1);

      RemoveInternalTimer($hash, \&APIAuth);
      APIAuth($hash);
      return;

  ##########
  } elsif ( ReadingsVal( $name, 'device_state', 'defined' ) !~ /$cmd_blocking/ && ( $setName =~ /^(Start|Park)$/ || $setName =~ /^cuttingHeight$/
    && defined $hash->{helper}{mower}{attributes}{settings}{cuttingHeight} ) ) {
    if ( $setVal =~ /^(\d+)$/) {

      CMD($hash ,$setName, $setVal);
      return;

    }

  ##########
  } elsif ( ReadingsVal( $name, 'device_state', 'defined' ) !~ /$cmd_blocking/ && $setName eq 'headlight' 
    && $hash->{helper}{mower}{attributes}{capabilities}{headlights}) {
    if ( $setVal =~ /ALWAYS_OFF|ALWAYS_ON|EVENING_ONLY|EVENING_AND_NIGHT/) {

      CMD($hash ,$setName, $setVal);

      return;
    }

  ##########
  } elsif ( ReadingsVal( $name, 'device_state', 'defined' ) !~ /$cmd_blocking/ 
    && $setName =~ /ParkUntilFurtherNotice|ParkUntilNextSchedule|Pause|ResumeSchedule|sendScheduleFromAttributeToMower|dateTime/ ) {

    CMD($hash,$setName);
    return;

  ##########
  } elsif ( ReadingsVal( $name, 'device_state', 'defined' ) !~ /$cmd_blocking/ && $setName =~ /sendJsonScheduleToMower/ ) {

    CMD($hash,$setName,$setVal);
    return;

  ##########
  } elsif ( ReadingsVal( $name, 'device_state', 'defined' ) !~ /$cmd_blocking/ && $setName =~ /confirmError/
    && $hash->{helper}{mower}{attributes}{capabilities}{canConfirmError} && AttrVal( $name, 'testing', $EMPTY ) ) {

    CMD($hash,$setName);
    return;

  ##########
  } elsif ( ReadingsVal( $name, 'device_state', 'defined' ) !~ /$cmd_blocking/ && $setName =~ /resetCuttingBladeUsageTime/
    && defined( $hash->{helper}{mower}{attributes}{statistics}{cuttingBladeUsageTime} ) ) {

    CMD($hash,$setName);
    return;

  ##########
  } elsif ( ReadingsVal( $name, 'device_state', 'defined' ) !~ /$cmd_blocking/ && $setName =~ /getMessages/ ) {

    getMowerWs( $hash, 'messages' );
    return;

  ##########
  } elsif ( ReadingsVal( $name, 'device_state', 'defined' ) !~ /$cmd_blocking/ && $setName =~ /^(StartInWorkArea|cuttingHeightInWorkArea)$/
    && $hash->{helper}{mower}{attributes}{capabilities}{workAreas} && AttrVal( $name, 'testing', $EMPTY ) ) {

    ( $setVal, $setVal2 ) = $setVal =~ /(.*),(\d+)/ if ( $setVal =~/,/ && !defined( $setVal2 ) );
    my $id = undef;
    $id = name2id( $hash, $setVal, 'workAreas' ) if ( $setVal !~ /^\d+$/ );
    $setVal = $id // $setVal;
    if ( $setVal =~ /^\d+$/ && ( $setVal2 =~ /^\d+$/ || !$setVal2 ) ) { # 

      CMD($hash ,$setName, $setVal, $setVal2);
      return;

    }

    Log3 $name, 2, "$iam $setName : no valid Id or zone name for $setVal .";

  ##########
  } elsif ( ReadingsVal( $name, 'device_state', 'defined' ) !~ /$cmd_blocking/ && $setName =~ /^stayOutZone$/
    && $hash->{helper}{mower}{attributes}{capabilities}{stayOutZones} && AttrVal( $name, 'testing', $EMPTY ) ) {

    ( $setVal, $setVal2 ) = $setVal =~ /(.*),(enable|disable)/ if ( $setVal =~/,/ && ! defined( $setVal2 ) );
    my $id = undef;
    $id = name2id( $hash, $setVal, 'stayOutZones' ) if ( $setVal !~ /\b[0-9a-f]{8}\b-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-\b[0-9a-f]{12}\b/ );
    $setVal = $id // $setVal;
    if ( $setVal =~ /\b[0-9a-f]{8}\b-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-\b[0-9a-f]{12}\b/ ) {

      $setVal2 = $setVal2 eq 'enable' ? 'true' : 'false';
      CMD($hash ,$setName, $setVal, $setVal2);
      return;

    }

    Log3 $name, 2, "$iam $setName : no valid Id or zone name for $setVal .";

  }
  ##########
  my $ret = ' getNewAccessToken:noArg ParkUntilFurtherNotice:noArg ParkUntilNextSchedule:noArg Pause:noArg Start:selectnumbers,30,30,600,0,lin Park:selectnumbers,30,30,600,0,lin ResumeSchedule:noArg getUpdate:noArg client_secret getMessages:noArg ';
  $ret .= AttrVal( $name, 'mowerAutoSyncTime', 0 ) ? $EMPTY : 'dateTime:noArg ';
  $ret .= 'mowerScheduleToAttribute:noArg sendScheduleFromAttributeToMower:noArg ';
  $ret .= 'cuttingHeight:1,2,3,4,5,6,7,8,9 ' if ( defined $hash->{helper}{mower}{attributes}{settings}{cuttingHeight} );
  $ret .= 'defaultDesignAttributesToAttribute:noArg mapZonesTemplateToAttribute:noArg chargingStationPositionToAttribute:noArg ' if ( $hash->{helper}{mower}{attributes}{capabilities}{position} );
  $ret .= 'headlight:ALWAYS_OFF,ALWAYS_ON,EVENING_ONLY,EVENING_AND_NIGHT ' if ( $hash->{helper}{mower}{attributes}{capabilities}{headlights} );

  ##########
  if ( $hash->{helper}{mower}{attributes}{capabilities}{workAreas} && defined ( $hash->{helper}{mower}{attributes}{workAreas} ) && AttrVal( $name, 'testing', $EMPTY ) ) {

    my @ar = @{ $hash->{helper}{mower}{attributes}{workAreas} };
    my @anlist = map { ','.$_->{name} } @ar;
    $ret .= 'cuttingHeightInWorkArea:widgetList,'.(scalar @anlist + 1).',select'.join( $EMPTY, @anlist).',6,selectnumbers,0,10,100,0,lin ';
    $ret .= 'StartInWorkArea:widgetList,'.(scalar @anlist + 1).',select'.join($EMPTY,@anlist).',6,selectnumbers,0,30,600,0,lin ';

  }

  ##########
  if ( $hash->{helper}{mower}{attributes}{capabilities}{stayOutZones} && defined ( $hash->{helper}{mower}{attributes}{stayOutZones}{zones} ) && AttrVal( $name, 'testing', $EMPTY ) ) {

    my @so = @{ $hash->{helper}{mower}{attributes}{stayOutZones}{zones} };
    my @solist = map { ','.$_->{name} } @so;
    $ret .= 'stayOutZone:widgetList,'.(scalar @solist + 1).',select'.join($EMPTY,@solist).',3,select,enable,disable ';

  }

  $ret .= 'confirmError:noArg ' if ( $hash->{helper}{mower}{attributes}{capabilities}{canConfirmError} && AttrVal( $name, 'testing', $EMPTY ) );
  $ret .= 'resetCuttingBladeUsageTime ' if ( defined( $hash->{helper}{mower}{attributes}{statistics}{cuttingBladeUsageTime} ) );
  return "Unknown argument $setName, choose one of".$ret;
  
}

##############################################################
#
# SEND COMMAND
#
##############################################################

sub CMD { ## no critic (ProhibitExcessComplexity [complexity core maintenance])
  my ( $hash, @cmd ) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $iam = "$type $name CMD:";
  my $timeout = AttrVal( $name, 'timeoutCMD', $hash->{helper}->{timeout_cmd} );
  my $method = 'POST';
  my $ts = time();
  my $tz_name = AttrVal( $name, 'mowerTimeZone', $hash->{helper}{timeZoneName} );
  $hash->{helper}{mower_commandSend} = $cmd[ 0 ] . ( $cmd[ 1 ] ? $SPACE.$cmd[ 1 ] : $EMPTY ) . ( $cmd[ 2 ] ? $SPACE.$cmd[ 2 ] : $EMPTY );

  if ( IsDisabled( $name ) ) {

    Log3 $name, 3, "$iam disabled"; 
    return

  }

  my $client_id = $hash->{helper}->{client_id};
  my $token = ReadingsVal($name,'.access_token',$EMPTY);
  my $provider = ReadingsVal($name,'.provider',$EMPTY);
  my $mower_id = $hash->{helper}{mower}{id};

  my $json = $EMPTY;
  my $post = $EMPTY;

my $header = "Accept: application/vnd.api+json\r\nX-Api-Key: ".$client_id."\r\nAuthorization: Bearer " . $token . "\r\nAuthorization-Provider: " . $provider . "\r\nContent-Type: application/vnd.api+json";

  if    ($cmd[0] eq 'ParkUntilFurtherNotice')     { $json = '{"data":{"type":"'.$cmd[0].'"}}'; $post = 'actions' } ## no critic (ProhibitCascadingIfElse [complexity core maintenance pbp])
  elsif ($cmd[0] eq 'ParkUntilNextSchedule')      { $json = '{"data": {"type":"'.$cmd[0].'"}}'; $post = 'actions' }
  elsif ($cmd[0] eq 'ResumeSchedule')  { $json = '{"data": {"type":"'.$cmd[0].'"}}'; $post = 'actions' }
  elsif ($cmd[0] eq 'Pause')           { $json = '{"data": {"type":"'.$cmd[0].'"}}'; $post = 'actions' }
  elsif ($cmd[0] eq 'Park')            { $json = '{"data": {"type":"'.$cmd[0].'","attributes":{"duration":'.$cmd[1].'}}}'; $post = 'actions' }
  elsif ($cmd[0] eq 'Start')           { $json = '{"data": {"type":"'.$cmd[0].'","attributes":{"duration":'.$cmd[1].'}}}'; $post = 'actions' }
  elsif ($cmd[0] eq 'cuttingHeightInWorkArea')
                                        { $json = '{"data": {"type":"workArea","id":"'.$cmd[1].'","attributes":{"cuttingHight":'.$cmd[2].'}}}'; $post = 'workAreas/'.$cmd[1]; $method = 'PATCH' }
  elsif ($cmd[0] eq 'StartInWorkArea' && $cmd[2])
                                       { $json = '{"data": {"type":"'.$cmd[0].'","attributes":{"workAreaId":'.$cmd[1].',"duration":'.$cmd[2].'}}}'; $post = 'actions' }
  elsif ($cmd[0] eq 'StartInWorkArea' && !$cmd[2])
                                       { $json = '{"data": {"type":"'.$cmd[0].'","attributes":{"workAreaId":'.$cmd[1].'}}}'; $post = 'actions' }
  elsif ($cmd[0] eq 'headlight')       { $json = '{"data": {"type":"settings","attributes":{"'.$cmd[0].'": {"mode": "'.$cmd[1].'"}}}}'; $post = 'settings' }
  elsif ($cmd[0] eq 'dateTime')        { $json = '{"data": {"type":"settings","attributes":{"timer": {"'.$cmd[0].'": '.( $cmd[1] ? $cmd[1] : $ts ).',"timeZone": "'.$tz_name.'"}}}}'; $post = 'settings';$hash->{helper}{mower_commandSend} .= ( $cmd[1] ? ' '.$cmd[1] : ' '.$ts ).' '.$tz_name }
  elsif ($cmd[0] eq 'cuttingHeight')   { $json = '{"data": {"type":"settings","attributes":{"'.$cmd[0].'": '.$cmd[1].'}}}'; $post = 'settings' }
  elsif ($cmd[0] eq 'stayOutZone')     { $json = '{"data": {"type":"stayOutZone","id":"'.$cmd[1].'","attributes":{"enable": '.$cmd[2].'}}}'; $post = 'stayOutZones/' . $cmd[1]; $method = 'PATCH' }
  elsif ($cmd[0] eq 'confirmError')    { $json = '{}'; $post = 'errors/confirm' }
  elsif ($cmd[0] eq 'resetCuttingBladeUsageTime') { $json = '{}'; $post = 'statistics/resetCuttingBladeUsageTime' }
  elsif ($cmd[0] eq 'sendScheduleFromAttributeToMower' && AttrVal( $name, 'mowerSchedule', $EMPTY)) {

    my $perl = eval { JSON::XS->new->decode (AttrVal( $name, 'mowerSchedule', $EMPTY)) };
    return "$iam decode error: $@ \n $perl" if ($@);
    
    my $jsonSchedule = eval { JSON::XS->new->utf8( not $unicodeEncoding )->encode ($perl) };
    return "$iam encode error: $@ \n $jsonSchedule" if ($@);
    
    $hash->{helper}{mower_commandSend} .= $SPACE. $jsonSchedule;
    $json = '{"data":{"type": "calendar","attributes":{"tasks":'.$jsonSchedule.'}}}'; 
    $post = 'calendar';
  }
  elsif ($cmd[0] eq 'sendJsonScheduleToMower' && $cmd[1]) {

    my $perl = eval { JSON::XS->new->decode ( $cmd[1] ) };
    return "$iam decode error: $@ \n $perl" if ($@);

    my $jsonSchedule = eval { JSON::XS->new->utf8( not $unicodeEncoding )->encode ($perl) };
    return "$iam encode error: $@ \n $jsonSchedule" if ($@);

    $json = '{"data":{"type": "calendar","attributes":{"tasks":'.$jsonSchedule.'}}}'; 
    $post = 'calendar';
  }

  Log3 $name, 5, "$iam $header \n $cmd[0] \n $json"; 
  readingsSingleUpdate( $hash, 'api_callsThisMonth' , ReadingsVal( $name,  'api_callsThisMonth', 0 ) + 1, 0) if ( $hash->{helper}{additional_polling} );

  ::HttpUtils_NonblockingGet( {
    url           => $APIURL . '/mowers/'. $mower_id . '/'.$post,
    timeout       => $timeout,
    hash          => $hash,
    method        => $method,
    header        => $header,
    data          => $json,
    callback      => \&CMDResponse,
    t_begin       => scalar gettimeofday()
  } );  

return;
}

##############################################################
sub CMDResponse {
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $statuscode = $param->{code} // $EMPTY;
  my $iam = "$type $name CMDResponse:";

  Log3 $name, 1, "$iam response time ". sprintf( "%.2f", ( gettimeofday() - $param->{t_begin} ) ) . ' s' if ( $param->{timeout} == 60 );
  Log3 $name, 5, "$iam \n\$statuscode >$statuscode<\n\$err >$err<,\n \$data >$data< \n\$param->url $param->{url}";

  if ( !$err && $statuscode == 202 && $data ) {

    my $result = eval { JSON::XS->new->decode($data) };

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

        return;

      }

    }

  }
  readingsBeginUpdate($hash);

    readingsBulkUpdateIfChanged( $hash, 'mower_commandStatus', "ERROR statuscode $statuscode", 1 );
    readingsBulkUpdateIfChanged( $hash, 'mower_commandSend', $hash->{helper}{mower_commandSend}, 1 );

  readingsEndUpdate($hash, 1);

  Log3 $name, 2, "$iam \n\$statuscode >$statuscode<\n\$err >$err<,\n\$data >$data<\n\$param->{url} >$param->{url}<\n\$param->{data} >$param->{data}<";
  DoTrigger($name, 'MOWERAPI ERROR');
  
  return;
}

#########################
sub Attr { ## no critic (ProhibitExcessComplexity [complexity core maintenance])

  my ( $cmd, $name, $attrName, $attrVal ) = @_;
  my $hash = $defs{$name};
  my $type = $hash->{TYPE};
  my $iam = "$type $name Attr:";

  ##########
  if( $attrName eq "disable" ) { ## no critic (ProhibitCascadingIfElse [complexity core maintenance pbp])
    if( $cmd eq "set" and $attrVal eq "1" ) {

      readingsSingleUpdate( $hash,'device_state','disabled',1);
      RemoveInternalTimer( $hash );
      DevIo_CloseDev( $hash );
      DevIo_setStates( $hash, 'closed' );
      Log3 $name, 3, "$iam $cmd $attrName disabled";

    } elsif( $cmd eq 'del' || $cmd eq 'set' && !$attrVal ) {

      RemoveInternalTimer( $hash, \&APIAuth);
      InternalTimer( gettimeofday() + 1, \&APIAuth, $hash, 0 );
      Log3 $name, 3, "$iam $cmd $attrName enabled";

    }

  ##########
  } elsif ( $attrName eq 'mapImagePath' ) {

    if( $cmd eq 'set') {

      if ($attrVal =~ '(webp|png|jpg|jpeg)$' ) {

        $hash->{helper}{MAP_PATH} = $attrVal;
        $hash->{helper}{MAP_MIME} = 'image/'.$1;
        ::FHEM::Devices::AMConnect::Common::readMap( $hash );

        if ( $attrVal =~ /(\d+)x(\d+)/ ) {
          $attr{$name}{mapImageWidthHeight} = "$1 $2";
        }

        Log3 $name, 3, "$iam $cmd $attrName $attrVal";

      } else {

        Log3 $name, 3, "$iam $cmd $attrName wrong image type, use webp, png, jpeg or jpg";
        return "$iam $cmd $attrName wrong image type, use webp, png, jpeg or jpg";
      
      }

    } elsif( $cmd eq 'del' ) {

      $hash->{helper}{MAP_PATH} = $EMPTY;
      $hash->{helper}{MAP_CACHE} = $EMPTY;
      $hash->{helper}{MAP_MIME} = $EMPTY;
      Log3 $name, 3, "$iam $cmd $attrName";

    }

  ##########
  } elsif( $attrName eq 'mowingAreaHull' ) {

    if( $cmd eq "set" ) {

      my $perl = eval { JSON::XS->new->decode ( $attrVal ) };
      return "$iam $cmd $attrName decode error: $@ \n $attrVal" if ($@);
      Log3 $name, 4, "$iam $cmd $attrName";

    }
    
  ##########
  } elsif( $attrName eq 'weekdaysToResetWayPoints' ) {

    if( $cmd eq 'set' ) {

      return "$iam $attrName is invalid, enter a combination of weekday numbers, space or - [0123456 -]" unless( $attrVal =~ /0|1|2|3|4|5|6| |-/ );
      Log3 $name, 4, "$iam $cmd $attrName $attrVal";

    } elsif( $cmd eq 'del' ) {

      Log3 $name, 3, "$iam $cmd $attrName and set default to 1";

    }
  ##########
  } elsif( $attrName eq 'loglevelDevIo' ) {

    if( $cmd eq "set" ) {

      return "$iam $attrName is invalid, select a number of [012345]" unless( $attrVal =~ /^[0-5]{1}$/ );
      $hash->{devioLoglevel} = $attrVal;
      Log3 $name, 4, "$iam $cmd $attrName $attrVal";

    } elsif( $cmd eq 'del' ) {

      delete( $hash->{devioLoglevel} );
      Log3 $name, 3, "$iam $cmd $attrName and set default.";

    }
  ##########
  } elsif( $attrName =~ /^(timeoutGetMower|timeoutApiAuth|timeoutCMD)$/ ) {

    if( $cmd eq 'set' ) {

      return "$iam $attrVal is invalid, allowed time as integer between 5 and 61" if ( !( $attrVal =~ /^[\d]{1,2}$/ && $attrVal > 5 && $attrVal < 61 ) );
      Log3 $name, 4, "$iam $cmd $attrName $attrVal";

    } elsif( $cmd eq 'del' ) {

      Log3 $name, 3, "$iam $cmd $attrName and set default value.";

    }
  ##########
  } elsif( $attrName eq 'addPollingMinInterval' ) {

    if( $cmd eq 'set' ) {

      return "$iam $attrVal is invalid, allowed time in seconds >= 0." if ( !( $attrVal >= 0 ) );
      $hash->{helper}{additional_polling} = $attrVal;
      Log3 $name, 4, "$iam $cmd $attrName $attrVal";

      if ( $attrVal == 0 ) {

        delete $attr{$name}{addPositionPolling} if ( defined( $attr{$name}{addPositionPolling} ) );
        $hash->{helper}{use_position_polling} = 0;

      }


    } elsif( $cmd eq 'del' ) {

      $hash->{helper}{additional_polling} = 0;
      readingsDelete( $hash, 'api_callsThisMonth' );
      Log3 $name, 3, "$iam $cmd $attrName and set default value 0.";
      delete $attr{$name}{addPositionPolling} if ( defined( $attr{$name}{addPositionPolling} ) );
      $hash->{helper}{use_position_polling} = 0;

    }
  ##########
  } elsif( $attrName eq 'addPositionPolling' ) {

    if( $cmd eq 'set' ) {

      return "$iam $attrVal is invalid, allowed value 0 or 1." unless( $attrVal == 0 || $attrVal == 1 );
      return "$iam $attrVal set attribute addPollingMinInterval > 0 first." if ( !( defined( $attr{$name}{addPollingMinInterval} ) && $attr{$name}{addPollingMinInterval} > 0 ) );
      $hash->{helper}{use_position_polling} = $attrVal;
      Log3 $name, 4, "$iam $cmd $attrName $attrVal";

    } elsif( $cmd eq 'del' ) {

      $hash->{helper}{use_position_polling} = 0;
      Log3 $name, 3, "$iam $cmd $attrName and set default value 0.";

    }
  ##########
  } elsif ( $attrName eq 'numberOfWayPointsToDisplay' ) {

    my $icurr = scalar @{$hash->{helper}{areapos}};
    if( $cmd eq 'set' && $attrVal =~ /\d+/ ) {

      return "$iam $attrVal is invalid, min value is 100." if ( $attrVal < 100 );
      # reduce array
      $hash->{helper}{MOWING}{maxLength} = $attrVal;
      for ( my $i = $icurr; $i > $attrVal; $i-- ) {
        pop @{$hash->{helper}{areapos}};
      }
      Log3 $name, 4, "$iam $cmd $attrName $attrVal";

    } elsif( $cmd eq 'del' ) {

      # reduce array
      my $imax = $hash->{helper}{MOWING}{maxLengthDefault};
      $hash->{helper}{MOWING}{maxLength} = $imax;
      for ( my $i = $icurr; $i > $imax; $i-- ) {
        pop @{$hash->{helper}{areapos}};
      }
      Log3 $name, 3, "$iam $cmd $attrName $attrName and set default $imax";

    }
  ##########
  } elsif( $attrName eq 'mapImageCoordinatesUTM' ) {

    if( $cmd eq 'set' ) {

      if ( AttrVal( $name,'mapImageCoordinatesToRegister', $EMPTY ) && $attrVal =~ /(?<x1>-?\d*\.?\d+)\s(?<y1>-?\d*\.?\d+) #upper left coordinates
                                                                                (?:\R|\s)
                                                                                (?<x2>-?\d*\.?\d+)\s(?<y2>-?\d*\.?\d+) #lower right coordinates
                                                                               /x ) {

        my ( $x1, $y1, $x2, $y2 ) = ( $+{x1}, $+{y1}, $+{x2}, $+{y2} );
        AttrVal( $name,'mapImageCoordinatesToRegister', $EMPTY ) =~ /(?<lo1>-?\d*\.?\d+)\s(?<la1>-?\d*\.?\d+) #upper left coordinates
                                                                 (?:\R|\s)
                                                                 (?<lo2>-?\d*\.?\d+)\s(?<la2>-?\d*\.?\d+) #lower right coordinates
                                                                /x;
        my ( $lo1, $la1, $lo2, $la2 ) = ( $+{lo1}, $+{la1}, $+{lo2}, $+{la2} );

        return "$iam $attrName illegal value 0 for the difference of longitudes." unless ( $lo1 - $lo2 );
        return "$iam $attrName illegal value 0 for the difference of latitudes." unless ( $la1 - $la2 );

        my $scx = int( ( $x1 - $x2) / ( $lo1 - $lo2 ) );
        my $scy = int( ( $y1 - $y2 ) / ( $la1 - $la2 ) );
        $attr{$name}{scaleToMeterXY} = "$scx $scy";

      } else {
        return "$iam $attrName has a wrong format use linewise pairs <floating point longitude><one space character><floating point latitude> or the attribute mapImageCoordinatesToRegister was not set before.";
    }
      Log3 $name, 3, "$iam $cmd $attrName $attrVal";

    } elsif( $cmd eq 'del' ) {

      Log3 $name, 3, "$iam $cmd $attrName and set default 0 90<Line feed>90 0";

    }
  ##########
  } elsif( $attrName eq 'mapImageCoordinatesToRegister' ) {

    if( $cmd eq 'set' ) {

      return "$iam $attrName has a wrong format use linewise pairs <floating point longitude><one space character><floating point latitude>"
        unless( $attrVal =~ /(?<lo1>-?\d*\.?\d+)\s(?<la1>-?\d*\.?\d+) #upper left coordinates
                             (?:\R|\s)
                             (?<lo2>-?\d*\.?\d+)\s(?<la2>-?\d*\.?\d+) #lower right coordinates
                            /x );
      my ( $lo1, $la1, $lo2, $la2 ) = ( $+{lo1}, $+{la1}, $+{lo2}, $+{la2} );
      return "$iam $attrName illegal value 0 for the difference of longitudes." unless ( $lo1 - $lo2 );
      return "$iam $attrName illegal value 0 for the difference of latitudes." unless ( $la1 - $la2 );
      
      

      Log3 $name, 3, "$iam $cmd $attrName $attrVal";

    } elsif( $cmd eq 'del' ) {

      Log3 $name, 3, "$iam $cmd $attrName and set default 0 90<Line feed>90 0";

    }
  ##########
  } elsif( $attrName eq 'chargingStationCoordinates' ) {

    if( $cmd eq 'set' ) {

      return "$iam $attrName has a wrong format use <floating point longitude><one space character><floating point latitude>" unless( $attrVal =~ /(-?\d*\.?\d+)\s(-?\d*\.?\d+)/ );
      Log3 $name, 3, "$iam $cmd $attrName $attrVal";

    } elsif( $cmd eq 'del' ) {

      Log3 $name, 3, "$iam $cmd $attrName and set default 10.1165 51.28";

    }
  ##########
  } elsif( $attrName eq 'mapImageWidthHeight' ) {

    if( $cmd eq 'set' ) {

      return "$iam $attrName has a wrong format use <integer longitude><one space character><integer latitude>" unless( $attrVal =~ /(\d+)\s(\d+)/ );
      Log3 $name, 3, "$iam $cmd $attrName $attrVal";

    } elsif( $cmd eq 'del' ) {

      Log3 $name, 3, "$iam $cmd $attrName and set default 100 200";

    }
  ##########
  } elsif( $attrName eq 'scaleToMeterXY' ) {

    if( $cmd eq 'set' ) {

      return "$iam $attrName has a wrong format use <integer longitude><one space character><integer latitude>" unless( $attrVal =~ /(-?\d+)\s(-?\d+)/ );
      Log3 $name, 3, "$iam $cmd $attrName $attrVal";

    } elsif( $cmd eq 'del' ) {

      Log3 $name, 3, "$iam $cmd $attrName and set default $hash->{helper}{scaleToMeterLongitude} $hash->{helper}{scaleToMeterLatitude}";

    }
  ##########
  } elsif( $attrName eq 'mowerSchedule' ) {
    if( $cmd eq 'set' ) {

      my $perl = eval { JSON::XS->new->decode ($attrVal) };
      return "$iam $cmd $attrName decode error: $@ \n $perl" if ($@);

      $attrVal = eval {
        require JSON::PP;
        my %ORDER=(start=>1,duration=>2,monday=>3,tuesday=>4,wednesday=>5,thursday=>6,friday=>7,saturday=>8,sunday=>9,workAreaId=>10);
        JSON::PP->new->sort_by(
          sub {($ORDER{$JSON::PP::a} // 999) <=> ($ORDER{$JSON::PP::b} // 999) or $JSON::PP::a cmp $JSON::PP::b}) ## no critic (ProhibitPackageVars)
          ->pretty(1)->encode( $perl )
      };
      return "$iam $cmd $attrName encode error: $@ \n $attrVal" if ($@);

      Log3 $name, 4, "$iam $cmd $attrName mower schedule array";

    }
  ##########
  } elsif( $attrName eq 'mapZones' ) {
    if( $cmd eq 'set' ) {

      my $longitude = 10;
      my $latitude = 52;
      my $perl = eval { JSON::XS->new->decode ($attrVal) };

      return "$iam $cmd $attrName decode error: $@ \n $attrVal" if ($@);

      for ( keys %{$perl} ) {

        $perl->{$_}{zoneCnt} = 0;
        $perl->{$_}{zoneLength} = 0;
        my $cond = eval "($perl->{$_}{condition})"; ## no critic 'eval'
        return "$iam $cmd $attrName syntax error in condition: $@ \n $perl->{$_}{condition}" if ($@);

      }

        Log3 $name, 4, "$iam $cmd $attrName";
        $hash->{helper}{mapZones} = $perl;

    } elsif( $cmd eq 'del' ) {

      delete $hash->{helper}{mapZones};
      delete $hash->{helper}{currentZone};
      CommandDeleteReading( $hash, "$name mower_currentZone" );
      Log3 $name, 3, "$iam $cmd $attrName";

    }
  }
  return;
}

#########################
sub name2id {
  my ( $hash, $zname, $ztype ) = @_;
  $ztype = $ztype // 'workAreas';
  if ( $ztype eq 'workAreas' && defined ( $hash->{helper}{mower}{attributes}{workAreas} ) ) {

    my @ar = @{ $hash->{helper}{mower}{attributes}{workAreas} };
    for ( @ar ) {

      return $_->{workAreaId} if ( $_->{name} eq $zname );

    }

  } elsif ( $ztype eq 'stayOutZones' && defined( $hash->{helper}{mower}{attributes}{stayOutZones} ) && defined ( $hash->{helper}{mower}{attributes}{stayOutZones}{zones} ) ) {

    if (  defined( $hash->{helper}{mower}{attributes}{stayOutZones}{dirty} ) && $hash->{helper}{mower}{attributes}{stayOutZones}{dirty} == 0) {

      my @ar = @{ $hash->{helper}{mower}{attributes}{stayOutZones}{zones} };
      for ( @ar ) {

        return $_->{Id} if ( $_->{name} eq $zname );

      }

    }

  }
  return;
}

#########################
sub AlignArray { ## no critic (ProhibitExcessComplexity [complexity core maintenance])
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $use_position_polling = $hash->{helper}{use_position_polling};
  my $reverse_positions_order = $hash->{helper}{reverse_positions_order};
  my $reverse_pollpos_order = $hash->{helper}{reverse_pollpos_order};
  my $additional_polling = $hash->{helper}{additional_polling};
  my $act = $hash->{helper}{mower}{attributes}{mower}{activity};
  my $cnt = @{ $hash->{helper}{mower}{attributes}{positions} };
  my $tmp = [];

  if ( $cnt > 0 ) {

    my @ar = @{ $hash->{helper}{mower}{attributes}{positions} };

    for ( @ar ) { $_->{act} = $hash->{helper}{$act}{short} };

    if ( !$use_position_polling ) {

      if ( $reverse_positions_order ) {

        @ar = reverse @ar if ( $cnt > 1 ); # positions seem to be in reversed order

      }

    } elsif ( $use_position_polling ) {

      if ( $reverse_pollpos_order ) {

        @ar = reverse @ar if ( $cnt > 1 ); # positions seem to be in reversed order

      }

    }

    $tmp = dclone( \@ar );

    if ( @{ $hash->{helper}{areapos} } ) {

      unshift ( @{ $hash->{helper}{areapos} }, @{ $tmp } );

    } else {

      $hash->{helper}{areapos} = $tmp;
      $hash->{helper}{areapos}[0]{start} = 'first value';

    }

    while ( @{ $hash->{helper}{areapos} } > $hash->{helper}{MOWING}{maxLength} ) {

        pop ( @{ $hash->{helper}{areapos}} ); # reduce to max allowed length

    }

    posMinMax( $hash, $tmp );

    if ( $act =~ /MOWING/ ) {

      AreaStatistics ( $hash, $cnt );

    }

    if ( $hash->{helper}{newcollisions} && $additional_polling && $act =~ /MOWING/ ) {

      TagWayPointsAsCollision ( $hash, $cnt );

    }

    if ( AttrVal($name, 'mapZones', 0) && $act =~ /MOWING/ ) {

      $tmp = dclone( \@ar );
      ZoneHandling ( $hash, $tmp, $cnt );

    }

    # set cutting height per zone
    my $cuthi = $hash->{helper}{mower}{attributes}{settings}{cuttingHeight};
    if ( AttrVal( $name, 'mapZones', 0 ) && $act =~ /MOWING/
        && defined( $hash->{helper}{currentZone} )
        && defined( $hash->{helper}{mapZones}{$hash->{helper}{currentZone}}{cuttingHeight} )
        && $hash->{helper}{mapZones}{$hash->{helper}{currentZone}}{cuttingHeight} !~ /$cuthi/
        && ( $hash->{helper}{cuttingHeightLast} + $hash->{helper}{cuttingHeightLatency} ) < scalar gettimeofday() ) {

      RemoveInternalTimer( $hash, \&setCuttingHeight );
      InternalTimer( gettimeofday() + 11, \&setCuttingHeight, $hash, 0 )

    }

    if ( $act =~ /CHARGING|PARKED/ ) {

      $tmp = dclone( \@ar );
      ChargingStationPosition ( $hash, $tmp, $cnt );

    }

  }

  $hash->{helper}{newdatasets} = $cnt;
  return;

}

#########################
sub isErrorThanPrepare {
  my ( $hash ) = @_;
  my $name = $hash->{NAME};

  if ( $hash->{helper}{mower}{attributes}{mower}{errorCodeTimestamp} ) {

    if ( ( $hash->{helper}{lasterror}{timestamp} != $hash->{helper}{mower}{attributes}{mower}{errorCodeTimestamp} ) ) {

      if ( $hash->{helper}{mower}{attributes}{capabilities}{position} && @{ $hash->{helper}{areapos} } > 1 ) {

        $hash->{helper}{areapos}[ 0 ]{act} = 'N';
        $hash->{helper}{areapos}[ 1 ]{act} = 'N';
        $hash->{helper}{lasterror}{positions} = [ dclone( $hash->{helper}{areapos}[ 0 ] ), dclone( $hash->{helper}{areapos}[ 1 ] ) ];

      }

      my $ect = $hash->{helper}{mower}{attributes}{mower}{errorCodeTimestamp};
      $hash->{helper}{lasterror}{timestamp} = $ect;
      my $errc = $hash->{helper}{mower}{attributes}{mower}{errorCode};
      $hash->{helper}{lasterror}{errordesc} = $errortable->{$errc};
      $hash->{helper}{lasterror}{errordate} = FmtDateTime( $ect / 1000 );
      $hash->{helper}{lasterror}{errorstate} = $hash->{helper}{mower}{attributes}{mower}{state};
      $hash->{helper}{lasterror}{errorzone} = $hash->{helper}{currentZone} if ( defined( $hash->{helper}{currentZone} ) );

      my $tmp = dclone( $hash->{helper}{lasterror} );
      unshift ( @{ $hash->{helper}{errorstack} }, $tmp );
      pop ( @{ $hash->{helper}{errorstack} } ) if ( @{ $hash->{helper}{errorstack} } > $hash->{helper}{errorstackmax} );
      FW_detailFn_Update ($hash);

    }

  return;

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
    $hash->{helper}{lasterror}{errordate} = $EMPTY;
    $hash->{helper}{lasterror}{errorstate} = $EMPTY;
    FW_detailFn_Update ($hash);

  }

  return;

}
#########################
sub ZoneHandling {
  my ( $hash, $poshash, $cnt ) = @_;
  my $name = $hash->{NAME};
  my $zone = $EMPTY;
  my $nextzone = $EMPTY;
  my @pos = @{$poshash};
  my $longitude = 0;
  my $latitude = 0;
  my @zonekeys = sort (keys %{$hash->{helper}{mapZones}});
  my $i = 0;
  my $k = 0;

  for ( @zonekeys ){ $hash->{helper}{mapZones}{$_}{curZoneCnt} = 0 }

  for ( $i = 0; $i < $cnt; $i++){

    $longitude = $pos[$i]{longitude};
    $latitude = $pos[$i]{latitude};

    for ( $k = 0; $k < @zonekeys-1; $k++){

      if ( eval ("$hash->{helper}{mapZones}{$zonekeys[$k]}{condition}") ) { ## no critic 'eval'

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

      for ( @zonekeys ){

        $sumDayCnt += $hash->{helper}{mapZones}{$_}{zoneCnt};
        $sumDayArea += $hash->{helper}{mapZones}{$_}{zoneLength};

      };

      for ( @zonekeys ){

        $hash->{helper}{mapZones}{$_}{currentDayCntPct} = ( $sumDayCnt ? sprintf( "%.0f", $hash->{helper}{mapZones}{$_}{zoneCnt} / $sumDayCnt * 100 ) : 0 );
        $hash->{helper}{mapZones}{$_}{currentDayAreaPct} = ( $sumDayArea ? sprintf( "%.0f", $hash->{helper}{mapZones}{$_}{zoneLength} / $sumDayArea * 100 ) : 0 );
        $hash->{helper}{mapZones}{$_}{currentDayTrack} = $hash->{helper}{mapZones}{$_}{zoneLength};
        $hash->{helper}{mapZones}{$_}{currentDayTime} = $hash->{helper}{mapZones}{$_}{zoneCnt} * 30;

      };

      $hash->{helper}{mapZones}{$hash->{helper}{currentZone}}{currentDayCollisions} += $hash->{helper}{newcollisions};
      $hash->{helper}{newzonedatasets} = $cnt;

  return;

}

#########################
sub ChargingStationPosition {
  my ( $hash, $poshash, $cnt ) = @_;
  if ( $cnt && @{ $hash->{helper}{cspos} } ) {

    unshift ( @{ $hash->{helper}{cspos} }, @{$poshash} );

  } elsif ( $cnt ) {

    $hash->{helper}{cspos} = $poshash;

  }

  while ( @{ $hash->{helper}{cspos} } > $hash->{helper}{PARKED_IN_CS}{maxLength} ) {

      pop ( @{ $hash->{helper}{cspos}} ); # reduce to max allowed length

  }
  my $n = @{$hash->{helper}{cspos}};
  if ( $n > 0 ) {

    my $xm = 0;
    for ( @{$hash->{helper}{cspos}} ){ $xm += $_->{longitude} };
    $xm = $xm/$n;
    my $ym = 0;
    for ( @{$hash->{helper}{cspos}} ){ $ym += $_->{latitude} };
    $ym = $ym/$n;
    $hash->{helper}{chargingStation}{longitude} = sprintf("%.8f",$xm);
    $hash->{helper}{chargingStation}{latitude} = sprintf("%.8f",$ym);

  }
  return;
}


#########################
sub calcPathLength {
  my ( $hash, $istart, $i ) = @_;
  my $name = $hash->{NAME};
  my $k = 0;
  my @xyarr  = @{$hash->{helper}{areapos}};# areapos
  my $n = scalar @xyarr;
  my ($sclon, $sclat) = AttrVal($name,'scaleToMeterXY', $hash->{helper}{scaleToMeterLongitude} . $SPACE .$hash->{helper}{scaleToMeterLatitude}) =~ /(-?\d+)\s+(-?\d+)/;
  my $lsum = 0;

  for ( $k = $istart; $k < $i; $k++) {

    $lsum += ( ( ( $xyarr[ $k ]{longitude} - $xyarr[ $k+1 ]{longitude} ) * $sclon ) ** 2 + ( ( $xyarr[ $k ]{latitude} - $xyarr[ $k+1 ]{latitude} ) * $sclat ) ** 2 ) ** 0.5 if ( $xyarr[ $k+1 ]{longitude} && $xyarr[ $k+1 ]{latitude} );

  }
  return $lsum;
}

#########################
sub TagWayPointsAsCollision {
  my ( $hash, $i ) = @_;
  my $name = $hash->{NAME};
  for ( my $k = 1; $k < ($i-1); $k++) {

    $hash->{helper}{areapos}[$k]{act} = 'K';

  }
  $hash->{helper}{areapos}[0]{act} = 'KE';
  $hash->{helper}{areapos}[$i-1]{act} = 'KS' if ($i>1);

  return;

}

#########################
sub AreaStatistics {
  my ( $hash, $i ) = @_;
  my $name = $hash->{NAME};
  my $activity = 'MOWING';
  my $lsum = calcPathLength( $hash, 0, $i );
  my $asum = 0;
  my $atim = 0;
  my $acol = $hash->{helper}{mower}{attributes}{statistics}{numberOfCollisions} - $hash->{helper}{mowerold}{attributes}{statistics}{numberOfCollisions};
  $hash->{helper}{newcollisions} = $acol - $hash->{helper}{statistics}{currentDayCollisions};

  $asum = $lsum * AttrVal($name,'mowerCuttingWidth',0.24);
  $atim = $i*30; # seconds
  $hash->{helper}{$activity}{track} = $lsum;
  $hash->{helper}{$activity}{area} = $asum;
  $hash->{helper}{$activity}{time} = $atim;
  $hash->{helper}{statistics}{currentDayTrack} += $lsum;
  $hash->{helper}{statistics}{currentDayArea} += $asum;
  $hash->{helper}{statistics}{currentDayTime} += $atim;
  $hash->{helper}{statistics}{currentDayCollisions} = $acol;

  return;
}

#########################
sub AddExtension {
    my ( $name, $func, $link ) = @_;
    my $hash = $defs{$name};
    my $type = $hash->{TYPE};

    my $url = "/$link";
    Log3( $name, 2, "Registering $type $name for URL $url..." );
    $data{FWEXT}{$url}{deviceName} = $name;
    $data{FWEXT}{$url}{FUNC}       = $func;
    $data{FWEXT}{$url}{LINK}       = $link;

    return;
}

#########################
sub RemoveExtension {
    my ($link) = @_;
    my $url  = "/$link";
    my $name = $data{FWEXT}{$url}{deviceName};

    Log3( $name, 2, "Unregistering URL $url..." );
    delete $data{FWEXT}{$url};

    return;
}

#########################
sub GetMap() {
  my ($request) = @_;

  if ( $request =~ /^\/(AutomowerConnect)\/(\w+)\/map/ ) {

    my $type   = $1;
    my $name   = $2;
    my $hash = $defs{$name};
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
    my $hash = $defs{$name};
    my $jsonMime = "application/json";
    my $jsonData = eval { JSON::XS->new->encode ( $hash->{helper}{mapupdate} ) };
    if ($@) {

      Log3 $name, 2, "$type $name encode error: $@";
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

    if ( open my $fh, '<:raw', $filename ) { ## no critic (RequireBriefOpen [core maintenance pbp])


      my $content = $EMPTY;

      while (1) {

        my $success = read $fh, $content, 1024, length( $content );

        if ( not defined $success ) {

          close $fh;
          Log3 $name, 1, "$iam read file \"$filename\" with error $!";
          return;

        }

        last if not $success;

      }

      close $fh;
      $hash->{helper}{MAP_CACHE} = $content;
      Log3 $name, 4, "$iam file \"$filename\" content length: ".length( $content );

    } else {

      Log3 $name, 1, "$iam open file \"$filename\" with error $!";

    }

  } else {

    Log3 $name, 2, "$iam file \"$filename\" does not exist.";

  }

  return;

}

#########################
sub setCuttingHeight {
  my ( $hash ) = @_;
  RemoveInternalTimer( $hash, \&setCuttingHeight );

  if ( $hash->{helper}{mapZones}{$hash->{helper}{currentZone}}{cuttingHeight} != $hash->{helper}{mower}{attributes}{settings}{cuttingHeight} ) {

    CMD( $hash ,'cuttingHeight', $hash->{helper}{mapZones}{$hash->{helper}{currentZone}}{cuttingHeight} );
    $hash->{helper}{cuttingHeightLast} = scalar gettimeofday();

  }

  return;
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
  $hash->{helper}{imageWidthHeight} = int($hash->{helper}{imageHeight} * ($maxLon-$minLon) / ($maxLat-$minLat)) . $SPACE . $hash->{helper}{imageHeight} if ($maxLat-$minLat);

  return;
}

#########################
sub fillReadings {
  my ( $hash ) = @_;
  my $name = $hash->{NAME};
  readingsBulkUpdateIfChanged( $hash, '.mower_id', $hash->{helper}{mower}{id}, 0 ); 
  readingsBulkUpdateIfChanged( $hash, "batteryPercent", $hash->{helper}{mower}{attributes}{battery}{batteryPercent} ); 
  my $model = uc $hash->{helper}{mower}{attributes}{system}{model};
  $model =~ s/AUTOMOWER./AM/;
  readingsBulkUpdateIfChanged( $hash, 'model', $model );
  my $pref = 'mower';
  my $rval = ReadingsVal( $name, $pref.'_inactiveReason', $EMPTY );

  if ( !$rval && $hash->{helper}{mower}{attributes}{$pref}{inactiveReason} !~ /NONE/ ) {
    readingsBulkUpdateIfChanged( $hash, $pref.'_inactiveReason', $hash->{helper}{mower}{attributes}{$pref}{inactiveReason} );
  } elsif ( $rval ) {
    readingsBulkUpdateIfChanged( $hash, $pref.'_inactiveReason', $hash->{helper}{mower}{attributes}{$pref}{inactiveReason} );
  }

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
  # my $timestamp = FmtDateTimeGMT( $tstamp/1000 );
  my $timestamp = FmtDateTime( $tstamp/1000 );
  readingsBulkUpdateIfChanged( $hash, $pref."_errorCodeTimestamp", $tstamp ? $timestamp : '-' );

  my $errc = $hash->{helper}{mower}{attributes}{$pref}{errorCode};
  readingsBulkUpdateIfChanged( $hash, $pref.'_errorCode', $tstamp ? $errc  : '-');

  if ( $errc =~ /\d+/ ) {;

    my $errd = $errortable->{$errc};
    readingsBulkUpdateIfChanged( $hash, $pref.'_errorDescription', $tstamp ? $errd : '-');

  }

  $pref = 'system';
  readingsBulkUpdateIfChanged( $hash, $pref.'_name', $hash->{helper}{mower}{attributes}{$pref}{name} );
  $pref = 'planner';
  readingsBulkUpdateIfChanged( $hash, $pref.'_restrictedReason', $hash->{helper}{mower}{attributes}{$pref}{restrictedReason} );
  readingsBulkUpdateIfChanged( $hash, $pref.'_overrideAction', $hash->{helper}{mower}{attributes}{$pref}{override}{action} ) if ( $hash->{helper}{mower}{attributes}{$pref}{override}{action} );

  if ( AttrVal( $name, 'calculateReadings', $EMPTY ) =~ /nextStart/ ) {

    readingsBulkUpdateIfChanged( $hash, $pref.'_nextStart', calculateNextStart( $hash ) );

  } else {

    $tstamp = $hash->{helper}{mower}{attributes}{$pref}{nextStartTimestamp};
    $timestamp = FmtDateTimeGMT( $tstamp/1000 );
    readingsBulkUpdateIfChanged( $hash, $pref.'_nextStart', $tstamp ? $timestamp : '-' );

  }

  $pref = 'statistics';
  my $noCol = $hash->{helper}{statistics}{currentDayCollisions};
  readingsBulkUpdateIfChanged( $hash, $pref.'_numberOfCollisions', '(' . $noCol . '/' . $hash->{helper}{statistics}{lastDayCollisions} . '/' . $hash->{helper}{mower}{attributes}{$pref}{numberOfCollisions} . ')' );
  readingsBulkUpdateIfChanged( $hash, $pref.'_newGeoDataSets', $hash->{helper}{newdatasets} ) if ( $hash->{helper}{mower}{attributes}{capabilities}{position} );
  $pref = 'settings';
  readingsBulkUpdateIfChanged( $hash, $pref.'_headlight', $hash->{helper}{mower}{attributes}{$pref}{headlight}{mode} ) if ( $hash->{helper}{mower}{attributes}{capabilities}{headlights} );
  readingsBulkUpdateIfChanged( $hash, $pref.'_cuttingHeight', $hash->{helper}{mower}{attributes}{$pref}{cuttingHeight} ) if ( defined $hash->{helper}{mower}{attributes}{$pref}{cuttingHeight} );
  $pref = 'status';
  my $connected = $hash->{helper}{mower}{attributes}{metadata}{connected};
  readingsBulkUpdateIfChanged( $hash, $pref.'_connected', ( $connected ? "CONNECTED($connected)"  : "OFFLINE($connected)") );

  readingsBulkUpdateIfChanged( $hash, $pref.'_Timestamp', FmtDateTime( $hash->{helper}{mower}{attributes}{metadata}{statusTimestamp}/1000 ) );
  readingsBulkUpdateIfChanged( $hash, $pref.'_TimestampDiff', sprintf( "%.0f", $hash->{helper}{storediff}/1000 ) );

  return;
}

#########################
sub calculateStatistics { ## no critic (ProhibitExcessComplexity [complexity core maintenance])
  my ( $hash ) = @_;
  my $name = $hash->{NAME};
  my @time = localtime();

  $hash->{helper}{statistics}{lastDayCollisions} = $hash->{helper}{mower}{attributes}{statistics}{numberOfCollisions} - $hash->{helper}{statistics}{numberOfCollisionsOld};
  $hash->{helper}{statistics}{numberOfCollisionsOld} = $hash->{helper}{mower}{attributes}{statistics}{numberOfCollisions};
  $hash->{helper}{statistics}{currentWeekCollisions} += $hash->{helper}{statistics}{lastDayCollisions};

  if ( $hash->{helper}{mower}{attributes}{capabilities}{position} ) {
    $hash->{helper}{statistics}{lastDayTrack} = $hash->{helper}{statistics}{currentDayTrack};
    $hash->{helper}{statistics}{lastDayArea} = $hash->{helper}{statistics}{currentDayArea};
    $hash->{helper}{statistics}{lastDayTime} = $hash->{helper}{statistics}{currentDayTime};
    $hash->{helper}{statistics}{currentWeekTrack} += $hash->{helper}{statistics}{currentDayTrack};
    $hash->{helper}{statistics}{currentWeekArea} += $hash->{helper}{statistics}{currentDayArea};
    $hash->{helper}{statistics}{currentWeekTime} += $hash->{helper}{statistics}{currentDayTime};
  }

  $hash->{helper}{statistics}{currentDayTrack} = 0;
  $hash->{helper}{statistics}{currentDayArea} = 0;
  $hash->{helper}{statistics}{currentDayTime} = 0;
  $hash->{helper}{statistics}{currentDayCollisions} = 0;

  if ( AttrVal($name, 'mapZones', 0) && defined( $hash->{helper}{mapZones} ) ) {
    
    my @zonekeys = sort (keys %{$hash->{helper}{mapZones}});
    my $sumCurrentWeekCnt=0;
    my $sumCurrentWeekArea=0;

    for (@zonekeys){ 
      $hash->{helper}{mapZones}{$_}{currentWeekCnt} += $hash->{helper}{mapZones}{$_}{zoneCnt};
      $sumCurrentWeekCnt += $hash->{helper}{mapZones}{$_}{currentWeekCnt};
      $hash->{helper}{mapZones}{$_}{currentWeekArea} += $hash->{helper}{mapZones}{$_}{zoneLength};
      $sumCurrentWeekArea += ( $hash->{helper}{mapZones}{$_}{currentWeekArea} ? $hash->{helper}{mapZones}{$_}{currentWeekArea} : 0 );
      $hash->{helper}{mapZones}{$_}{lastDayTrack} = $hash->{helper}{mapZones}{$_}{currentDayTrack};
      $hash->{helper}{mapZones}{$_}{currentWeekTrack} += ( $hash->{helper}{mapZones}{$_}{currentDayTrack} ? $hash->{helper}{mapZones}{$_}{currentDayTrack} : 0 );
      $hash->{helper}{mapZones}{$_}{lastDayTime} = ( $hash->{helper}{mapZones}{$_}{currentDayTime} ? $hash->{helper}{mapZones}{$_}{currentDayTime} : 0 );
      $hash->{helper}{mapZones}{$_}{currentWeekTime} += ( $hash->{helper}{mapZones}{$_}{currentDayTime} ? $hash->{helper}{mapZones}{$_}{currentDayTime} : 0 );
      $hash->{helper}{mapZones}{$_}{zoneCnt} = 0;
      $hash->{helper}{mapZones}{$_}{zoneLength} = 0;
      $hash->{helper}{mapZones}{$_}{currentDayTrack} = 0;
      $hash->{helper}{mapZones}{$_}{currentDayTime} = 0;
    };

        for (@zonekeys){ 
      $hash->{helper}{mapZones}{$_}{lastDayCntPct} = $hash->{helper}{mapZones}{$_}{currentDayCntPct};
      $hash->{helper}{mapZones}{$_}{currentWeekCntPct} = ( $sumCurrentWeekCnt ? sprintf( "%.0f", $hash->{helper}{mapZones}{$_}{currentWeekCnt} / $sumCurrentWeekCnt * 100 ) : $EMPTY );
      $hash->{helper}{mapZones}{$_}{lastDayAreaPct} = $hash->{helper}{mapZones}{$_}{currentDayAreaPct};
      $hash->{helper}{mapZones}{$_}{currentWeekAreaPct} = ( $sumCurrentWeekArea ? sprintf( "%.0f", $hash->{helper}{mapZones}{$_}{currentWeekArea} / $sumCurrentWeekArea * 100 ) : $EMPTY );
      $hash->{helper}{mapZones}{$_}{currentDayCntPct} = $EMPTY;
      $hash->{helper}{mapZones}{$_}{currentDayAreaPct} = $EMPTY;
      if ( $hash->{helper}{additional_polling} ) {
        $hash->{helper}{mapZones}{$_}{lastDayCollisions} = ( $hash->{helper}{mapZones}{$_}{currentDayCollisions} ? $hash->{helper}{mapZones}{$_}{currentDayCollisions} : 0 );
        $hash->{helper}{mapZones}{$_}{currentWeekCollisions} += ( $hash->{helper}{mapZones}{$_}{currentDayCollisions} ? $hash->{helper}{mapZones}{$_}{currentDayCollisions} : 0 );
        $hash->{helper}{mapZones}{$_}{currentDayCollisions} = 0;
      }
    };

  }
  # do on days
  if ( $time[6] == 1 ) {

    $hash->{helper}{statistics}{lastWeekTrack} = $hash->{helper}{statistics}{currentWeekTrack};
    $hash->{helper}{statistics}{lastWeekArea} = $hash->{helper}{statistics}{currentWeekArea};
    $hash->{helper}{statistics}{lastWeekTime} = $hash->{helper}{statistics}{currentWeekTime};
    $hash->{helper}{statistics}{lastWeekCollisions} = $hash->{helper}{statistics}{currentWeekCollisions};
    $hash->{helper}{statistics}{currentWeekTrack} = 0;
    $hash->{helper}{statistics}{currentWeekArea} = 0;
    $hash->{helper}{statistics}{currentWeekTime} = 0;
    $hash->{helper}{statistics}{currentWeekCollisions} = 0;

    if ( AttrVal($name, 'mapZones', 0) && defined( $hash->{helper}{mapZones} ) ) {

      my @zonekeys = sort (keys %{$hash->{helper}{mapZones}});

          for (@zonekeys){ 
        $hash->{helper}{mapZones}{$_}{lastWeekCntPct} = $hash->{helper}{mapZones}{$_}{currentWeekCntPct};
        $hash->{helper}{mapZones}{$_}{lastWeekAreaPct} = $hash->{helper}{mapZones}{$_}{currentWeekAreaPct};
        $hash->{helper}{mapZones}{$_}{lastWeekTrack} = $hash->{helper}{mapZones}{$_}{currentWeekTrack};
        $hash->{helper}{mapZones}{$_}{lastWeekTime} = $hash->{helper}{mapZones}{$_}{currentWeekTime};
        $hash->{helper}{mapZones}{$_}{currentWeekCntPct} = $EMPTY;
        $hash->{helper}{mapZones}{$_}{currentWeekAreaPct} = $EMPTY;
        $hash->{helper}{mapZones}{$_}{currentWeekTrack} = 0;
        $hash->{helper}{mapZones}{$_}{currentWeekTime} = 0;
        if ( $hash->{helper}{additional_polling} ) {
          $hash->{helper}{mapZones}{$_}{lastWeekCollisions} = $hash->{helper}{mapZones}{$_}{currentWeekCollisions};
          $hash->{helper}{mapZones}{$_}{currentWeekCollisions} = 0;
        }
      };

    }

  }

  readingsSingleUpdate( $hash, 'api_callsThisMonth' , 0, 0) if ( $hash->{helper}{additional_polling} && $time[3] == 1 ); # reset monthly API calls

  #clear position arrays
  if ( AttrVal( $name, 'weekdaysToResetWayPoints', 1 ) =~ $time[6] ) {

    $hash->{helper}{areapos} = [];

  }

  return;
}

#########################
sub listStatisticsData { ## no critic (ProhibitExcessComplexity [complexity core maintenance])
  my ( $hash ) = @_;
  if ( $init_done && $hash->{helper}{statistics} ) {

    my %unit =(
      Track      => 'm',
      Area       => 'qm',
      Time       => 's',
      Collisions => $SPACE,
      CntPct     => '%',
      AreaPct    => '%'
    );
    my @props = qw(Track Area Time Collisions);
    my @items = qw(currentDay lastDay currentWeek lastWeek);
    my $additional_polling = $hash->{helper}{additional_polling};
    my $name = $hash->{NAME};
    my $cnt = 0;
    my $ret = $EMPTY;
    $ret .= '<html><table class="block wide">';
    $ret .= '<caption><b>Statistics Data</b></caption><tbody>'; 

    $ret .= '<tr class="col_header"><td> Hash Path </td><td> Value </td><td> Unit </td></tr>';
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{statistics}{<b>numberOfChargingCycles</b>} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{statistics}{numberOfChargingCycles} . ' </td><td>  </td></tr>';
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{statistics}{<b>numberOfCollisions</b>} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{statistics}{numberOfCollisions} . ' </td><td>  </td></tr>';
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{statistics}{<b>totalChargingTime</b>} &emsp;</td><td> ' . sprintf( "%.0f", $hash->{helper}{mower}{attributes}{statistics}{totalChargingTime} / 3600 ) . ' </td><td> h </td></tr>';
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{statistics}{<b>totalCuttingTime</b>} &emsp;</td><td> ' . sprintf( "%.0f", $hash->{helper}{mower}{attributes}{statistics}{totalCuttingTime} / 3600 ) . ' </td><td> h </td></tr>';
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{statistics}{<b>totalDriveDistance</b>} &emsp;</td><td> ' . sprintf( "%.0f", $hash->{helper}{mower}{attributes}{statistics}{totalDriveDistance} / 1000 ) . '<sup>1</sup> </td><td> km </td></tr>';
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{statistics}{<b>totalRunningTime</b>} &emsp;</td><td> ' . sprintf( "%.0f", $hash->{helper}{mower}{attributes}{statistics}{totalRunningTime} / 3600 ) . '<sup>2</sup> </td><td> h </td></tr>';
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{statistics}{<b>totalSearchingTime</b>} &emsp;</td><td> ' . sprintf( "%.0f", $hash->{helper}{mower}{attributes}{statistics}{totalSearchingTime} / 3600 ) . ' </td><td> h </td></tr>';
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{statistics}{<b>cuttingBladeUsageTime</b>} &emsp;</td><td> ' . sprintf( "%.0f", $hash->{helper}{mower}{attributes}{statistics}{cuttingBladeUsageTime} / 3600 ) . ' </td><td> h </td></tr>' if ( defined $hash->{helper}{mower}{attributes}{statistics}{cuttingBladeUsageTime} );
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{statistics}{<b>upTime</b>} &emsp;</td><td> ' . sprintf( "%.0f", $hash->{helper}{mower}{attributes}{statistics}{upTime} / 3600 ) . ' </td><td> h </td></tr>' if ( defined $hash->{helper}{mower}{attributes}{statistics}{upTime} );
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{statistics}{<b>downTime</b>} &emsp;</td><td> ' . sprintf( "%.0f", $hash->{helper}{mower}{attributes}{statistics}{downTime} / 3600 ) . ' </td><td> h </td></tr>' if ( defined $hash->{helper}{mower}{attributes}{statistics}{downTime} );

    for my $item ( @items ) {

      for my $prop ( @props ) {

        $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{statistics}{<b>'. $item . $prop . '</b>} &emsp;</td><td> ' . sprintf( "%.0f", ( $hash->{helper}{statistics}{$item.$prop} ? $hash->{helper}{statistics}{$item.$prop} : 0 ) ) . ' </td><td> ' . $unit{$prop} . ' </td></tr>' if ( $item.$prop ne 'currentDayCollision' or $additional_polling );

      }

        $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> <b>'. $item . ' calculated speed</b> &emsp;</td><td> ' . sprintf( "%.2f", $hash->{helper}{statistics}{$item.'Track'} / $hash->{helper}{statistics}{$item.'Time'} ) . ' </td><td> m/s </td></tr>' if ( $hash->{helper}{statistics}{$item.'Time'} );

    }


    if ( AttrVal($name, 'mapZones', 0) && defined( $hash->{helper}{mapZones} ) ) {

      my @zonekeys = sort (keys %{$hash->{helper}{mapZones}});
      my @propsZ = qw(Track CntPct AreaPct);
      unshift @propsZ, 'Collisions' if ( $additional_polling );

      for my $prop ( @propsZ ) {

        for my $item ( @items ) {

          for ( @zonekeys ) {

            if ($prop eq 'Track') {  ## no critic (ProhibitDeepNests [complexity core maintenance])

              $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> <b> '. $item . ' calculated speed for '. $_ . '</b> &emsp;</td><td> ' . sprintf( "%.2f", $hash->{helper}{mapZones}{$_}{$item.'Track'} / $hash->{helper}{mapZones}{$_}{$item.'Time'} ) . ' </td><td> m/s </td></tr>' if ( $hash->{helper}{mapZones}{$_}{$item.'Time'} );

            } else {

              $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ) . '"><td> $hash->{helper}{mapZones}{' . $_ . '}{<b>'. $item . $prop . '</b>} &emsp;</td><td> ' . ( $hash->{helper}{mapZones}{$_}{$item.$prop} ? $hash->{helper}{mapZones}{$_}{$item.$prop} : $EMPTY ) . ' </td><td> ' . $unit{$prop} . ' </td></tr>';

            }

          }

        }

      }

    }

    my @fences = qw(hull mowing property);

    for my $item ( @fences ) {

      $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> <b> calculated '.$item.' area </b> &emsp;</td><td> ' . $hash->{helper}{statistics}{$item.'Area'} . ' </td><td> qm </td></tr>' if ( $hash->{helper}{statistics}{$item.'Area'} );

    }

    $ret .= '</tbody></table>';
    $ret .= '<p><sup>1</sup> totalDriveDistance = totalRunningTime * '. sprintf( "%.2f", $hash->{helper}{mower}{attributes}{statistics}{totalDriveDistance} / $hash->{helper}{mower}{attributes}{statistics}{totalRunningTime} ) if ( $hash->{helper}{mower}{attributes}{statistics}{totalRunningTime} );
    $ret .= '<p><sup>2</sup> totalRunningTime = totalCuttingTime + totalSearchingTime';
    $ret .= '</html>';

    return $ret;

  } else {

    return '<html><table class="block wide"><tr><td>error codes are not yet available</td></tr></table></html>';

  }
}

#########################
sub listMowerData {  ## no critic (ProhibitExcessComplexity [complexity core maintenance])
  my ( $hash ) = @_;
  my $name = $hash->{NAME};
  my $cnt = 0;
  my $ret = $EMPTY;
  if ( $init_done && defined( $hash->{helper}{mower}{type} ) ) {

    $ret .= '<html><table class="block wide">';
    $ret .= '<caption><b>Mower Data</b></caption><tbody>'; 

    $ret .= '<tr class="col_header"><td> Hash Path </td><td> Value </td><td> Unit </td></tr>';
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{type} &emsp;</td><td> ' . $hash->{helper}{mower}{type} . ' </td><td>  </td></tr>';
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{id} &emsp;</td><td> ' . $hash->{helper}{mower}{id} . ' </td><td>  </td></tr>';
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{system}{name} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{system}{name} . ' </td><td>  </td></tr>';
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{system}{model} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{system}{model} . ' </td><td>  </td></tr>';
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{system}{serialNumber} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{system}{serialNumber} . ' </td><td>  </td></tr>';
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{battery}{batteryPercent} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{battery}{batteryPercent} . ' </td><td> % </td></tr>';
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{mower}{mode} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{mower}{mode} . ' </td><td>  </td></tr>';
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{mower}{activity} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{mower}{activity} . ' </td><td>  </td></tr>';
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{mower}{state} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{mower}{state} . ' </td><td>  </td></tr>';
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{mower}{errorCode} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{mower}{errorCode} . ' </td><td>  </td></tr>';
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{mower}{errorCodeTimestamp} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{mower}{errorCodeTimestamp} . ' </td><td> ms </td></tr>';

    my $calendarjson = eval { JSON::XS->new->pretty(1)->encode ($hash->{helper}{mower}{attributes}{calendar}{tasks}) };

    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td style="vertical-align:middle;" > $hash->{helper}{mower}{attributes}{calendar}{tasks} &emsp;</td><td colspan="2" style="word-wrap:break-word; max-width:34em;" > ' . ($@ ? $@ : $calendarjson) . ' </td></tr>';
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{planner}{nextStartTimestamp} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{planner}{nextStartTimestamp} . ' </td><td>  </td></tr>';
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{planner}{override}{action} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{planner}{override}{action} . ' </td><td>  </td></tr>';
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{planner}{restrictedReason} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{planner}{restrictedReason} . ' </td><td>  </td></tr>';
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{metadata}{connected} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{metadata}{connected} . ' </td><td>  </td></tr>';
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{metadata}{statusTimestamp} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{metadata}{statusTimestamp} . ' </td><td> ms </td></tr>';
     if ( $hash->{helper}{mower}{attributes}{capabilities}{position} ) {
      $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{positions}[0]{longitude} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{positions}[0]{longitude} . ' </td><td> decimal degree </td></tr>';
      $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{positions}[0]{latitude} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{positions}[0]{latitude} . ' </td><td> decimal degree </td></tr>';
    }
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{settings}{cuttingHeight} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{settings}{cuttingHeight} . ' </td><td>  </td></tr>' if ( defined $hash->{helper}{mower}{attributes}{settings}{cuttingHeight} );
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{settings}{headlight}{mode} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{settings}{headlight}{mode} . ' </td><td>  </td></tr>' if ( $hash->{helper}{mower}{attributes}{settings}{headlight}{mode} );
   $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{statistics}{cuttingBladeUsageTime} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{statistics}{cuttingBladeUsageTime} . ' </td><td>  </td></tr>' if ( defined $hash->{helper}{mower}{attributes}{statistics}{cuttingBladeUsageTime} );
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{statistics}{numberOfChargingCycles} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{statistics}{numberOfChargingCycles} . ' </td><td>  </td></tr>';
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{statistics}{numberOfCollisions} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{statistics}{numberOfCollisions} . ' </td><td>  </td></tr>';
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{statistics}{totalChargingTime} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{statistics}{totalChargingTime} . ' </td><td> s </td></tr>';
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{statistics}{totalCuttingTime} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{statistics}{totalCuttingTime} . ' </td><td> s </td></tr>';
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{statistics}{totalDriveDistance} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{statistics}{totalDriveDistance} . '<sup>1</sup></td><td> m </td></tr>';
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{statistics}{totalRunningTime} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{statistics}{totalRunningTime} . '<sup>2</sup> </td><td> s </td></tr>';
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{statistics}{totalSearchingTime} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{statistics}{totalSearchingTime} . ' </td><td> s </td></tr>';
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{capabilities}{headlights} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{capabilities}{headlights} . ' </td><td>  </td></tr>';
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{capabilities}{stayOutZones} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{capabilities}{stayOutZones} . ' </td><td>  </td></tr>';
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{capabilities}{workAreas} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{capabilities}{workAreas} . ' </td><td>  </td></tr>';
    $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{capabilities}{position} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{capabilities}{position} . ' </td><td>  </td></tr>';

    $ret .= '</tbody></table>';
    $ret .= '<p><sup>1</sup> totalDriveDistance = totalRunningTime * '. sprintf( "%.2f", $hash->{helper}{mower}{attributes}{statistics}{totalDriveDistance} / $hash->{helper}{mower}{attributes}{statistics}{totalRunningTime} ) if ( $hash->{helper}{mower}{attributes}{statistics}{totalRunningTime} );
    $ret .= '<p><sup>2</sup> totalRunningTime = totalCuttingTime + totalSearchingTime';
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
  my $ret = '<html>';
  if ( $init_done && defined( $hash->{helper}{mower}{type} ) && @{ $hash->{helper}{errorstack} } ) {

    $ret .= '<table class="block wide">';
    $ret .= '<caption><b>Last Errors</b></caption><tbody>'; 

    $ret .= '<tr class="col_header"><td> Timestamp </td><td> Description </td><td> &emsp;Zone &emsp;</td><td> Longitude / Latitude </td></tr>';

    for ( my $i = 0; $i < @{ $hash->{helper}{errorstack} }; $i++ ) {

      $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> ' . $hash->{helper}{errorstack}[$i]{errordate} . ' </td><td> ' . $hash->{helper}{errorstack}[$i]{errorstate} . ' - ' . $hash->{helper}{errorstack}[$i]{errordesc} . ' </td><td> ' . $hash->{helper}{errorstack}[$i]{errorzone} . ' </td><td> ' . $hash->{helper}{errorstack}[$i]{positions}[0]{longitude} . ' / ' . $hash->{helper}{errorstack}[$i]{positions}[0]{latitude} . ' </td></tr>';

    }

    $ret .= '</tbody></table>';

  } else {

    $ret .= '<table class="block wide"><tr><td>No error in stack. </td></tr></table>';

  }

  if ( $init_done && defined ( $hash->{helper}{endpoints}{messages}{attributes}{messages} ) && ref $hash->{helper}{endpoints}{messages}{attributes}{messages} eq 'ARRAY' && @{ $hash->{helper}{endpoints}{messages}{attributes}{messages} } > 0 ) {


    my @msg = @{ $hash->{helper}{endpoints}{messages}{attributes}{messages} };
    $ret .= '<table class="block wide">';
    $ret .= '<caption><b>Last Messages</b></caption><tbody>'; 

    $ret .= '<tr class="col_header"><td> Timestamp </td><td> Description </td><td> Longitude / Latitude </td></tr>';
    

    for ( my $i = 0; $i < @{ $hash->{helper}{endpoints}{messages}{attributes}{messages} }; $i++ ) {

      $ret .= '<tr class="column '.( $cnt++ % 2 ? 'odd' : 'even' ).'"><td> ' . FmtDateTimeGMT( $msg[$i]{time} ) . ' </td><td> ' . $msg[$i]{severity} . ' - ' . $errortable->{ $msg[$i]{code} } . ' </td><td> ' . ( defined $msg[$i]{longitude} ? $msg[$i]{longitude} : '-' ) . ' / ' . ( defined $msg[$i]{latitude} ? $msg[$i]{latitude} : '-' ) . ' </td></tr>';

    }

  } else {

    $ret .= '<table class="block wide"><tr><td>No messages available. </td></tr></table>';

  }

  $ret .= '</html>';
  return $ret;

}

#########################
sub listInternalData { ## no critic (ProhibitExcessComplexity [complexity core maintenance])
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

  if ( $init_done && $1 && $2 && $4 && $5 ) {

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
    $ret .= '<tr class="column odd"><td>NOT_APPLICABLE with error time stamp&emsp;</td><td> lasterror/positions&emsp;</td><td> ' . $ernr . ' </td><td> -&emsp;</td></tr>';

    $ret .= '</tbody></table>';
    $ret .= '<p><table class="block wide">';
    $ret .= '<caption><b>Websocket Events</b></caption><tbody>';

    $ret .= '<tr class="col_header"><td> Events&emsp;</td><td> Changed&emsp;</td><td> Unchanged&emsp;</td><td> Sum&emsp;</td></tr>';
    my @evt = qw(battery calendar cuttingHeight headlights message mower planner position sum);

    for my $key (@evt) {

      my $hc = $hash->{helper}{wsbuf}{$key . '_changed'};
      my $hd = $hash->{helper}{wsbuf}{$key . '_duplicates'};
      $ret .= '<tr class="column ' . ( $cnt++ % 2 ? "odd" : "even" ) . '"><td> ' . $key . '&emsp;</td><td> ' . $hc . '&emsp;</td><td> ' . $hd . ' </td><td> ' . ( $hc + $hd ) . '&emsp;</td></tr>';

    }

    $ret .= '</tbody></table>';

    $ret .= '<p><table class="block wide">';
    $ret .= '<caption><b>Rest API Data</b></caption><tbody>'; 

    $ret .= '<tr class="column ' . ( $cnt++ % 2 ? "odd" : "even" ) . '"><td> Link to APIs</td><td><a target="_blank" href="https://developer.husqvarnagroup.cloud/">Husqvarna Developer</a></td></tr>';
    $ret .= '<tr class="column ' . ( $cnt++ % 2 ? "odd" : "even" ) . '"><td> Authentification API URL</td><td>' . $AUTHURL . '</td></tr>';
    $ret .= '<tr class="column ' . ( $cnt++ % 2 ? "odd" : "even" ) . '"><td> Automower Connect API URL</td><td>' . $APIURL . '</td></tr>';
    $ret .= '<tr class="column ' . ( $cnt++ % 2 ? "odd" : "even" ) . '"><td> Websocket IO Device name</td><td>' . $WSDEVICENAME . '</td></tr>';
    $ret .= '<tr class="column ' . ( $cnt++ % 2 ? "odd" : "even" ) . '"><td> Client-Id</td><td>' . $hash->{helper}{client_id} . '</td></tr>';
    $ret .= '<tr class="column ' . ( $cnt++ % 2 ? "odd" : "even" ) . '"><td> Grant-Type</td><td>' . $hash->{helper}{grant_type} . '</td></tr>';
    $ret .= '<tr class="column ' . ( $cnt++ % 2 ? "odd" : "even" ) . '"><td> User-Id</td><td>' . ReadingsVal($name, '.user_id', '-') . '</td></tr>';
    $ret .= '<tr class="column ' . ( $cnt++ % 2 ? "odd" : "even" ) . '"><td> Provider</td><td>' . ReadingsVal($name, '.provider', '-') . '</td></tr>';
    $ret .= '<tr class="column ' . ( $cnt++ % 2 ? "odd" : "even" ) . '"><td> Scope</td><td>' . ReadingsVal($name, '.scope', '-') . '</td></tr>';
    $ret .= '<tr class="column ' . ( $cnt++ % 2 ? "odd" : "even" ) . '"><td> Token Type</td><td>' . ReadingsVal($name, '.token_type', '-') . '</td></tr>';
    $ret .= '<tr class="column ' . ( $cnt++ % 2 ? "odd" : "even" ) . '"><td> Token Expires</td><td> ' . FmtDateTime( ReadingsVal($name, '.expires', '0') ) . '</td></tr>';
    $ret .= '<tr class="column ' . ( $cnt++ % 2 ? "odd" : "even" ) . '"><td> Access Token</td><td style="word-wrap:break-word; max-width:40em">' . ReadingsVal($name, '.access_token', '0') . '</td></tr>';

    $ret .= '</tbody></table>';
    $ret .= '<p><table class="block wide">';
    $ret .= '<caption><b>Default mapDesignAttributes</b></caption><tbody>'; 

    my $mapdesign = $hash->{helper}{mapdesign};
    $mapdesign =~ s/\n/<br>/g;
    $ret .= '<tr class="column ' . ( $cnt++ % 2 ? "odd" : "even" ) . '"><td style="word-wrap:break-word; max-width:40em">' . $mapdesign . '</td></tr>';

    $ret .= '</tbody></table>';
    $ret .= '<p><table class="block wide">';
    $ret .= '<caption><b>Third Party Software</b></caption><tbody>'; 

    $ret .= '<tr class="column ' . ( $cnt++ % 2 ? "odd" : "even" ) . '"><td>hull calculation (hull.js)</td><td style="word-wrap:break-word; max-width:40em"> Server: ' . $hash->{helper}{FWEXTA}{url} . '</td></tr>';

    $ret .= '</tbody></table>';

    $ret .= '</html>';
    return $ret;

  } else {

    return '<html><table class="block wide"><tr><td>Internal data is not yet available</td></tr></table></html>';

  }
}

#########################
sub listErrorCodes {
  if ($init_done) {

    my $rowCount = 0;
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
      $ret .= ( $rowCount++ % 2 ? "odd" : "even" );
      $ret .= '"><td>';
      $ret .= $_;
      $ret .= '</td><td>';
      $ret .= $ec->{$_};
      $ret .= '</td></tr>';
    }
    
    $ret .= '</tbody></table></html>';
    return $ret;

  } else {

    return '<html><table class="block wide"><tr><td>error codes are not yet available</td></tr></table></html>';

  }
}

#########################
sub FmtDateTimeGMT {
  # Returns a yyyy-mm-dd HH:MM:SS formated string for a UNIX like timestamp for local time (seconds since EPOCH)
  return POSIX::strftime( "%F %H:%M:%S", gmtime( shift // 0 ) );
}

#########################
sub autoDstSync {
  my ( $hash ) = @_;
  my @ti = localtime();
  my $isDstOld = $hash->{helper}{isDst};
  if ( $ti[8] != $isDstOld && ( $ti[2] == 4 || $isDstOld == -1 ) ) {

    $hash->{helper}{isDst} = $ti[8];
    InternalTimer( gettimeofday() + 7, \&CMDdateTime, $hash, 0 );

  }
  return
}

#########################
sub CMDdateTime {
  my ( $hash ) = @_;
  my $name = $hash->{NAME};
  RemoveInternalTimer( $hash, \&CMDdateTime );
  CMD( $hash, 'dateTime' );
  return
}

#########################
sub polygonArea {
  my ( $ptsref, $sx, $sy )  = @_;
  my $sumarea = 0;
  my @pts = @{$ptsref};

  for (my $i = 0; $i < @pts; $i++) {
      my $addX = $pts[$i][0]*$sx;
      my $addY = $pts[$i == @pts - 1 ? 0 : $i + 1][1]*$sy;
      my $subX = $pts[$i == @pts - 1 ? 0 : $i + 1][0]*$sx;
      my $subY = $pts[$i][1]*$sy;
      $sumarea += ($addX * $addY * 0.5);
      $sumarea -= ($subX * $subY * 0.5);

  }
  return $sumarea;
}

#########################
sub getTpFile {
  my ( $hash, $url, $path, $file ) = @_;
  my $name = $hash->{NAME};
  my $msg = ::GetFileFromURL( $url );
  if ( $msg ) {
    my $fh;

    if( !open( $fh, '>', "$path/$file" ) ) {

      Log3 $name, 1, "$name getTpFile: Can't open $path/$file";

    } else {

      print $fh $msg;
      close( $fh );
      readingsSingleUpdate( $hash, 'third_party_library', "$file downloaded to: $path", 1 );
      Log3 $name, 1, "$name getTpFile: third party library downloaded from $url to $path";


    }

  }
  return;
}

#########################
sub getDefaultScheduleAsJSON {
  my ( $name ) = @_;
  my $hash = $defs{$name};
  my $json = eval {
    require JSON::PP;
    my %ORDER=(start=>1,duration=>2,monday=>3,tuesday=>4,wednesday=>5,thursday=>6,friday=>7,saturday=>8,sunday=>9,workAreaId=>10);
    JSON::PP->new->sort_by(
      sub {($ORDER{$JSON::PP::a} // 999) <=> ($ORDER{$JSON::PP::b} // 999) or $JSON::PP::a cmp $JSON::PP::b}) ## no critic (ProhibitPackageVars)
      ->utf8( not $unicodeEncoding )->encode( $hash->{helper}{mower}{attributes}{calendar}{tasks} )
  };
  return "$name getDefaultScheduleAsJSON: $@" if ($@);
  return $json;
}

#########################
sub getDesignAttr {
  my ( $hash ) = @_;
  my $name = $hash->{NAME};             
  my @designDefault = split( /\R/,$hash->{helper}{mapdesign} );
  my @designAttr = split( /\R/, AttrVal( $name, 'mapDesignAttributes', $EMPTY ) );
  my $hsh = $EMPTY;
  my $val = $EMPTY;
  ## no critic (ProhibitComplexMappings [complexity core maintenance pbp])
  my %desDef = map { ( $hsh, $val ) = $_ =~ /(.*)=(.*)/; $hsh => $val } @designDefault;
  %desDef = ( %desDef, map { ( $hsh, $val ) = $_ =~ /(.*)=(.*)/; $hsh => $val } @designAttr );
  ## use critic
  my $desDef = \%desDef;
  my @mergedDesign = map { "$_=$desDef->{$_}" } sort keys %desDef;
  my $design = 'data-' . join( 'data-', @mergedDesign );
  return \$design;
}

#########################
sub makeStatusTimeStamp {
  my ( $hash ) = @_;
  my $ts = gettimeofday() ;
  $hash->{helper}{statusTime} = $ts;
  my $tsold = $hash->{helper}{mower}{attributes}{metadata}{statusTimestamp};
  $ts = int ( $ts * 1000 );
  my $tsdiff = $ts - $tsold;
  if ( $tsdiff > 1000 ) {

  $hash->{helper}{mowerold}{attributes}{metadata}{statusTimestamp} = $tsold;
  $hash->{helper}{mower}{attributes}{metadata}{statusTimestamp} = $ts;
  $hash->{helper}{storediff} = $tsdiff;
  $hash->{helper}{storesum} += $tsdiff if ( $hash->{helper}{additional_polling} );

  }
  return;

}

#########################
sub calculateNextStart {
  my ( $hash ) = @_;
  return "-" if ( $hash->{helper}{mower}{attributes}{mower}{mode} !~ /MAIN_AREA/ ) || $hash->{helper}{mower}{attributes}{mower}{state} =~ /IN_OPERATION/;

  my $nt = gettimeofday();
  my @lt = gmtime( $nt );
  my $wday = $lt[ 6 ];
  my $mn = $nt - ( $lt[ 2 ] * 3600 + $lt[ 1 ] * 60 + $lt[ 0 ] ); # Midnight
  my @days = qw( sunday monday tuesday wednesday thursday friday saturday sunday monday tuesday wednesday thursday friday saturday );
  my @cal = @{ $hash->{helper}{mower}{attributes}{calendar}{tasks} };
  my @times =();

  for ( my $i = 0; $i < @cal; $i++ ) {

    my $calt = $mn + $cal [ $i ]->{start} * 60;
     
    for ( my $wd = $lt [ 6 ]; $wd < $lt [ 6 ] + 7 ; $wd++ ) {

      my $nx = $calt + 86400 * ( $wd - $lt [ 6 ] );
      push @times, $nx if ( $cal [ $i ]->{$days [ $wd ]} && $nx > $nt );

    }

  }

  # my $nextTime = POSIX::strftime( "%F %H:%M:00", localtime( min( @times ) ) );
  my $nextTime = FmtDateTimeGMT( min( @times ) );
  return $nextTime;
}

##############################################################
#
# WEBSOCKET
#
##############################################################

sub wsKeepAlive {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if ( IsDisabled( $name ) == 2 ) {

      RemoveInternalTimer( $hash );
      DevIo_CloseDev( $hash ) if ( DevIo_IsOpen( $hash ) );
      DevIo_setStates( $hash, 'closed' );
      InternalTimer( gettimeofday() + 1, \&APIAuth, $hash, 0 );

  }

  RemoveInternalTimer( $hash, \&wsKeepAlive);
  DevIo_Ping($hash);
  InternalTimer(gettimeofday() + $hash->{helper}{interval_ping}, \&wsKeepAlive, $hash, 0);
  return;
}

#########################
sub wsInit {

  my ( $hash ) = @_;
  $hash->{First_Read} = 1;
  RemoveInternalTimer( $hash, \&wsReopen );
  RemoveInternalTimer( $hash, \&wsKeepAlive );
  InternalTimer( gettimeofday() + $hash->{helper}{interval_ws}, \&wsReopen, $hash, 0 );
  InternalTimer( gettimeofday() + $hash->{helper}{interval_ping}, \&wsKeepAlive, $hash, 0 );
  return;

}

#########################
sub wsCb {
  my ($hash, $error) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $iam = "$type $name wsCb:";
  my $l = $hash->{devioLoglevel};
  if( $error ){
    Log3 $name, ( $l ? $l : 1 ), "$iam failed with error: $error";
    DoTrigger($name, 'WEBSOCKET ERROR');
  }
  return;

}

#########################
sub wsReopen {
  my ( $hash ) = @_;
  RemoveInternalTimer( $hash, \&wsReopen );
  RemoveInternalTimer( $hash, \&wsKeepAlive );
  DevIo_CloseDev( $hash ) if ( DevIo_IsOpen( $hash ) );
  # $hash->{DeviceName} = $WSDEVICENAME;
  # DevIo_OpenDev( $hash, 0, \&wsInit, \&wsCb );
  InternalTimer( gettimeofday() + $hash->{helper}{retry_interval_wsreopen}, \&wsAsyncDevIo_OpenDev, $hash, 0 );
  return;

}

#########################
sub wsAsyncDevIo_OpenDev {
  my ( $hash ) = @_;
  RemoveInternalTimer( $hash, \&wsAsyncDevIo_OpenDev );
  $hash->{DeviceName} = $WSDEVICENAME;
  $hash->{helper}{retry_interval_wsreopen} = 2;
  DevIo_OpenDev( $hash, 0, \&wsInit, \&wsCb );
  return;
}

#########################
sub wsRead {  ## no critic (ProhibitExcessComplexity [complexity core maintenance])
  # contains workarounds due to websocket V2 to be removed if not nessessary any more
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $iam = "$type $name wsRead:";
  my $additional_polling = $hash->{helper}{additional_polling} * 1000;
  my $use_position_polling = $hash->{helper}{use_position_polling};
  my $buforig = DevIo_SimpleRead( $hash );
  return if ( !defined( $buforig ) );

  Log3 $name, 4, "$iam received websocket data: >$buforig<";

## no critic (ProhibitDeepNests [complexity core maintenance])
  if ( $buforig ) { # buffer has content

    my ( @bufj ) = split('\}\{', $buforig ); # split in case buffer contains more than one event string

    if ( @bufj > 1 ) { # complete JSON strings due to splitting

      my $i = 0;
      $bufj[$i] = $bufj[$i].'}';

      for ( $i = 1; $i < @bufj - 1; $i++ ) {

        $bufj[$i] = '{'.$bufj[$i].'}';

      }

      $bufj[$i] = '{'.$bufj[$i];

    }

    for my $buf (@bufj) { # process each buffer part

      if ( $buf =~ /((position|mower|battery|planner|cuttingHeight|headlights|calendar|message)-event-v2)/ ) { # pass only correct event types and count dubletts

        my $evt = $1;
        my $evn = $2;

        if ( $buf ne $hash->{helper}{wsbuf}{$evt} ) { # handle changed events

          $hash->{helper}{wsbuf}{$evt} = $buf;
          $hash->{helper}{wsbuf}{sum_changed}++ ;
          $hash->{helper}{wsbuf}{$evn.'_changed'}++ ;

          my $result = eval { JSON::XS->new->decode( $buf ) };

          if ( $@ ) {

            Log3 $name, 1, "$iam - JSON error while request: $@\n\nbuffer content: >$buf<\n";

          } else {

            if ( !defined( $result->{type} ) ) {

              $hash->{helper}{wsResult}{other} = dclone( $result );

              if ( defined( $result->{ready} ) && !$result->{ready} ) {

                readingsSingleUpdate( $hash, 'mower_wsEvent', 'not ready', 1);
                $hash->{helper}{retry_interval_wsreopen} = 420;
                wsReopen($hash);

              }

            }

            if ( defined( $result->{type} ) && $result->{type} =~ /-v2$/ && $result->{id} eq $hash->{helper}{mower_id} ) {

              Log3 $name, 5, "$iam processed websocket event: >$buf<";
              $hash->{helper}{wsResult}{$result->{type}} = dclone( $result );
              $hash->{helper}{wsResult}{type} = $result->{type};
              makeStatusTimeStamp( $hash ); # no timestamp transmitted in ws v2, 430x

# position-event-v2
              if ( $result->{type} =~ /^pos/ ) { ## no critic (ProhibitCascadingIfElse [complexity core maintenance pbp])

                if ( !$use_position_polling ) { 

                  $hash->{helper}{positionsTime} = gettimeofday();
                  my @wspos = ( dclone( $result->{attributes}{position} ) );
                  $hash->{helper}{mower}{attributes}{positions} = \@wspos;

                  AlignArray( $hash );
                  FW_detailFn_Update ($hash);

                } elsif ( $use_position_polling ) {

                  next;

                }

              }
# mower-event-v2
              elsif ( $result->{type} =~ /^mow/ ) {

                $hash->{helper}{mowerold}{attributes}{mower}{activity}  = $hash->{helper}{mower}{attributes}{mower}{activity};
                $hash->{helper}{mower}{attributes}{mower}{mode} = $result->{attributes}{mower}{mode} if ( defined $result->{attributes}{mower}{mode} );
                $hash->{helper}{mower}{attributes}{mower}{state} = $result->{attributes}{mower}{state} if ( defined $result->{attributes}{mower}{state} );
                $hash->{helper}{mower}{attributes}{mower}{inactiveReason} = $result->{attributes}{mower}{inactiveReason} if ( defined $result->{attributes}{mower}{inactiveReason} );
                $hash->{helper}{mower}{attributes}{mower}{activity} = $result->{attributes}{mower}{activity} if ( defined $result->{attributes}{mower}{activity} );
                $hash->{helper}{mower}{attributes}{mower}{errorCode} = $result->{attributes}{mower}{errorCode} if ( defined $result->{attributes}{mower}{errorCode} );

                if ( $hash->{helper}{mower}{attributes}{mower}{errorCode} && !$hash->{helper}{mower}{attributes}{mower}{errorCodeTimestamp} ) { # no errorCodeTimestamp transmitted, 430x

                  $hash->{helper}{mower}{attributes}{mower}{errorCodeTimestamp} = int( $hash->{helper}{statusTime} * 1000 );

                } elsif ( $hash->{helper}{mower}{attributes}{mower}{errorCode} == 0 && $hash->{helper}{mower}{attributes}{mower}{errorCodeTimestamp} ) {

                  $hash->{helper}{mower}{attributes}{mower}{errorCodeTimestamp} = 0;

                }

                $hash->{helper}{mower}{attributes}{mower}{errorCodeTimestamp} = $result->{attributes}{mower}{errorCodeTimestamp} if ( defined $result->{attributes}{mower}{errorCodeTimestamp} );
                $hash->{helper}{mower}{attributes}{mower}{isErrorConfirmable} = $result->{attributes}{mower}{isErrorConfirmable} if ( defined $result->{attributes}{mower}{isErrorConfirmable} );

                if ( !$additional_polling ) {

                  isErrorThanPrepare( $hash );
                  resetLastErrorIfCorrected( $hash );

                }

              }

# battery-event-v2
              elsif ( $result->{type} =~/^bat/ ) {

                my $tmp = $result->{attributes}{battery}{batteryPercent};
                $hash->{helper}{mower}{attributes}{battery}{batteryPercent} = $tmp if ( $tmp ); # batteryPercent zero sometimes 430x

              }

# planner-event-v2
              elsif ( $result->{type} =~ /^pla/ ) { # no planner event 430x

                $hash->{helper}{mower}{attributes}{planner}{restrictedReason} = $result->{attributes}{planner}{restrictedReason} if ( defined $result->{attributes}{planner}{restrictedReason} );

                # Timestamp in s not in ms as described, 415x
                if ( defined $result->{attributes}{planner}{nextStartTimestamp} ) {

                  my $tmp = $result->{attributes}{planner}{nextStartTimestamp};
                  $hash->{helper}{mower}{attributes}{planner}{nextStartTimestamp} = length( $tmp ) == 10 ? $tmp * 1000 : $tmp;

                }

              }

# cuttingHeight-event-v2
              elsif ( $result->{type} =~ /^cut/ ) { # first event after setting transmits old value 430x

                $hash->{helper}{mower}{attributes}{settings}{cuttingHeight} = $result->{attributes}{cuttingHeight}{height};

              }

# headlights-event-v2
              elsif ( $result->{type} =~ /^hea/ ) { #no headlights event 430x

                $hash->{helper}{mower}{attributes}{settings}{headlight}{mode} = $result->{attributes}{headlight}{mode};

              }

# calendar-event-v2
              elsif ( $result->{type} =~ /^cal/ ) {

                $hash->{helper}{mower}{attributes}{calendar} = dclone( $result->{attributes}{calendar} );

              }

# message-event-v2
              elsif ( $result->{type} =~ /^mes/ ) { # no message event 430x

                $hash->{helper}{mower}{attributes}{ws_message} = dclone( $result->{attributes}{message} );

              }

              # Update readings
              readingsBeginUpdate($hash);

                fillReadings( $hash ) if ( !additionalPollingWS( $hash ) ); # call additional polling or fill reaadings
                readingsBulkUpdate( $hash, 'mower_wsEvent', $hash->{helper}{wsResult}{type} );

              readingsEndUpdate($hash, 1);

            }

          }

          autoDstSync( $hash ) if ( AttrVal( $name, "mowerAutoSyncTime", 0 ) );

        } else { # handle duplicates

          $hash->{helper}{wsbuf}{sum_duplicates}++;
          $hash->{helper}{wsbuf}{$evn.'_duplicates'}++ ;

        } # end handle duplicates/changed

      } # end only correct event types

    } # next process each buffer part

  } # end buffer has content

  ## use critic
  $hash->{First_Read} = 0;
  return;

}

#########################
sub wsReady {
  my  ($hash ) = @_;
  RemoveInternalTimer( $hash, \&wsAsyncDevIo_OpenDev);
  RemoveInternalTimer( $hash, \&wsReopen);
  RemoveInternalTimer( $hash, \&wsKeepAlive);
  return DevIo_OpenDev( $hash, 1, \&wsInit, \&wsCb );

}


##############################################################

1;

