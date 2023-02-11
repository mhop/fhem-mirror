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

use Time::HiRes qw(gettimeofday);
use Blocking;
use Storable qw(dclone retrieve store);

# Import der FHEM Funktionen
BEGIN {
    GP_Import(
        qw(
          AttrVal
          CommandAttr
          FmtDateTime
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
          )
    );
}

my $missingModul = "";

eval "use JSON;1" or $missingModul .= "JSON ";

my $errorjson = '{"23":"Wheel drive problem, left","24":"Cutting system blocked","123":"Destination not reachable","710":"SIM card locked","50":"Guide 1 not found","717":"SMS could not be sent","108":"Folding cutting deck sensor defect","4":"Loop sensor problem, front","15":"Lifted","29":"Slope too steep","1":"Outside working area","45":"Cutting height problem, dir","52":"Guide 3 not found","28":"Memory circuit problem","95":"Folding sensor activated","9":"Trapped","114":"Too high discharge current","103":"Cutting drive motor 2 defect","65":"Temporary battery problem","119":"Zone generator problem","6":"Loop sensor problem, left","82":"Wheel motor blocked, rear right","714":"Geofence problem","703":"Connectivity problem","708":"SIM card locked","75":"Connection changed","7":"Loop sensor problem, right","35":"Wheel motor overloaded, right","3":"Wrong loop signal","117":"High internal power loss","0":"Unexpected error","80":"Cutting system imbalance - Warning","110":"Collision sensor error","100":"Ultrasonic Sensor 3 defect","79":"Invalid battery combination - Invalid combination of different battery types.","724":"Communication circuit board SW must be updated","86":"Wheel motor overloaded, rear right","81":"Safety function faulty","78":"Slipped - Mower has Slipped.Situation not solved with moving pattern","107":"Docking sensor defect","33":"Mower tilted","69":"Alarm! Mower switched off","68":"Temporary battery problem","34":"Cutting stopped - slope too steep","127":"Battery problem","73":"Alarm! Mower in motion","74":"Alarm! Outside geofence","713":"Geofence problem","87":"Wheel motor overloaded, rear left","120":"Internal voltage error","39":"Cutting motor problem","704":"Connectivity problem","63":"Temporary battery problem","109":"Loop sensor defect","38":"Electronic problem","64":"Temporary battery problem","113":"Complex working area","93":"No accurate position from satellites","104":"Cutting drive motor 3 defect","709":"SIM card not found","94":"Reference station communication problem","43":"Cutting height problem, drive","13":"No drive","44":"Cutting height problem, curr","118":"Charging system problem","14":"Mower lifted","57":"Guide calibration failed","707":"SIM card requires PIN","99":"Ultrasonic Sensor 2 defect","98":"Ultrasonic Sensor 1 defect","51":"Guide 2 not found","56":"Guide calibration accomplished","49":"Ultrasonic problem","2":"No loop signal","124":"Destination blocked","25":"Cutting system blocked","19":"Collision sensor problem, front","18":"Collision sensor problem, rear","48":"No response from charger","105":"Lift Sensor defect","111":"No confirmed position","10":"Upside down","40":"Limited cutting height range","716":"Connectivity problem","27":"Settings restored","90":"No power in charging station","21":"Wheel motor blocked, left","26":"Invalid sub-device combination","92":"Work area not valid","702":"Connectivity settings restored","125":"Battery needs replacement","5":"Loop sensor problem, rear","12":"Empty battery","55":"Difficult finding home","42":"Limited cutting height range","30":"Charging system problem","72":"Alarm! Mower tilted","85":"Wheel drive problem, rear left","8":"Wrong PIN code","62":"Temporary battery problem","102":"Cutting drive motor 1 defect","116":"High charging power loss","122":"CAN error","60":"Temporary battery problem","705":"Connectivity problem","711":"SIM card locked","70":"Alarm! Mower stopped","32":"Tilt sensor problem","37":"Charging current too high","89":"Invalid system configuration","76":"Connection NOT changed","71":"Alarm! Mower lifted","88":"Angular sensor problem","701":"Connectivity problem","715":"Connectivity problem","61":"Temporary battery problem","66":"Battery problem","106":"Collision sensor defect","67":"Battery problem","112":"Cutting system major imbalance","83":"Wheel motor blocked, rear left","84":"Wheel drive problem, rear right","126":"Battery near end of life","77":"Com board not available","36":"Wheel motor overloaded, left","31":"STOP button problem","17":"Charging station blocked","54":"Weak GPS signal","47":"Cutting height problem","53":"GPS navigation problem","121":"High internal temerature","97":"Left brush motor overloaded","712":"SIM card locked","20":"Wheel motor blocked, right","91":"Switch cord problem","96":"Right brush motor overloaded","58":"Temporary battery problem","59":"Temporary battery problem","22":"Wheel drive problem, right","706":"Poor signal quality","41":"Unexpected cutting height adj","46":"Cutting height blocked","11":"Low battery","16":"Stuck in charging station","101":"Ultrasonic Sensor 4 defect","115":"Too high internal current"}';

our $errortable = eval { decode_json ( $errorjson ) };
if ($@) {
  return "FHEM::Devices::AMConnect::Common \$errortable: $@";
}
$errorjson = undef;

#########################
sub Undefine {
  my ( $hash, $arg )  = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  
  RemoveInternalTimer($hash);
  ::FHEM::Devices::AMConnect::Common::RemoveExtension("$type/$name/map");
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

  my ( $passResp, $passErr ) = $hash->{helper}->{passObj}->setRename( $newname, $oldname );
  Log3 $newname, 2, "$newname password rename error: $passErr" if ($passErr);

  return undef;
}

#########################

sub Get {
  my ($hash,@val) = @_;
  my $type = $hash->{TYPE};

  return "$type $hash->{NAME} Get: needs at least one argument" if ( @val < 2 );

  my ($name,$setName,$setVal,$setVal2,$setVal3) = @val;
  my $iam = "$type $name Get:";

  Log3 $name, 4, "$iam called with $setName " . ($setVal ? $setVal : "");

  if ( $setName eq 'html' ) {
    
    my $ret = '<html>' . ::FHEM::Devices::AMConnect::Common::FW_detailFn( undef, $name, undef, undef) . '</html>';
    return $ret;

  } elsif (  $setName eq 'errorCodes' ) {

    my $ret = ::FHEM::Devices::AMConnect::Common::listErrorCodes();
    return $ret;

  } elsif (  $setName eq 'InternalData' ) {

    my $ret = ::FHEM::Devices::AMConnect::Common::listInternalData($hash);
    return $ret;

  } elsif (  $setName eq 'MowerData' ) {

    my $ret = ::FHEM::Devices::AMConnect::Common::listMowerData($hash);
    return $ret;

  } elsif (  $setName eq 'StatisticsData' ) {

    my $ret = ::FHEM::Devices::AMConnect::Common::listStatisticsData($hash);
    return $ret;

  } else {

    return "Unknown argument $setName, choose one of StatisticsData:noArg MowerData:noArg InternalData:noArg errorCodes:noArg ";

  }
}

#########################
sub FW_detailFn {
  my ($FW_wname, $name, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $hash = $defs{$name};
  my $type = $hash->{TYPE};
  return '' if( AttrVal($name, 'disable', 0) || !AttrVal($name, 'showMap', 1) );
  if ( $hash->{helper} && $hash->{helper}{mower} && $hash->{helper}{mower}{attributes} && $hash->{helper}{mower}{attributes}{positions} && @{$hash->{helper}{mower}{attributes}{positions}} > 0 ) {
    my $img = "./fhem/$type/$name/map";
    my $zoom=AttrVal( $name,"mapImageZoom", 0.7 );
    
    my ($picx,$picy) = AttrVal( $name,"mapImageWidthHeight", $hash->{helper}{imageWidthHeight} ) =~ /(\d+)\s(\d+)/;
    
    $picx=int($picx*$zoom);
    $picy=int($picy*$zoom);
    my $ret = "";
    $ret .= "<style> ." . $type . "_" . $name . "_div{background-image: url('$img');background-size: ".$picx."px ".$picy."px;background-repeat: no-repeat; width:".$picx."px;height:".$picy."px;}</style>";
    $ret .= "<div class='" . $type . "_" . $name . "_div' >";
    $ret .= "<canvas id= '" . $type . "_" . $name . "_canvas' width='$picx' height='$picy' ></canvas>";
    $ret .= "</div>";
    
    InternalTimer( gettimeofday() + 2.0, \&FW_detailFn_Update, $hash, 0 );
    
    return $ret;
  }
  return '';
}

#########################
sub FW_detailFn_Update {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  if ( $hash->{helper} && $hash->{helper}{mower} && $hash->{helper}{mower}{attributes} && $hash->{helper}{mower}{attributes}{positions} && @{$hash->{helper}{mower}{attributes}{positions}} > 0 ) {

    my @pos = @{$hash->{helper}{areapos}}; # operational mode
    my @posc = @{$hash->{helper}{cspos}}; # maybe operational mode
    my $img = "./fhem/$type/$name/map";

    my ( $lonlo, $latlo, $dummy, $lonru, $latru ) = AttrVal( $name,"mapImageCoordinatesToRegister",$hash->{helper}{posMinMax} ) =~ /(-?\d*\.?\d+)\s(-?\d*\.?\d+)(\R|\s)(-?\d*\.?\d+)\s(-?\d*\.?\d+)/;

    my $zoom = AttrVal( $name,"mapImageZoom", 0.7 );
    
    my ($picx,$picy) = AttrVal( $name,"mapImageWidthHeight", $hash->{helper}{imageWidthHeight} ) =~ /(\d+)\s(\d+)/;

    AttrVal($name,'scaleToMeterXY', $hash->{helper}{scaleToMeterLongitude} . ' ' .$hash->{helper}{scaleToMeterLatitude}) =~ /(-?\d+)\s+(-?\d+)/;
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

    my $csimgpos = AttrVal( $name,"chargingStationImagePosition","right" );
    my $xm = $hash->{helper}{chargingStation}{longitude} // 10.1165;
    my $ym = $hash->{helper}{chargingStation}{latitude} // 51.28;

    my ($cslo,$csla) = AttrVal( $name,"chargingStationCoordinates","$xm $ym" ) =~  /(-?\d*\.?\d+)\s(-?\d*\.?\d+)/;

    my $cslon = int(($lonlo-$cslo) * $picx / $mapx);
    my $cslat = int(($latlo-$csla) * $picy / $mapy);

    # MOWING PATH
    my $posxy = int($lonlo * $picx / $mapx).",".int($latlo * $picy / $mapy);
    if ( @pos > 1 ) {

      $posxy = int(($lonlo-$pos[0]{longitude}) * $picx / $mapx).",".int(($latlo-$pos[0]{latitude}) * $picy / $mapy);
      for (my $i=1;$i<@pos;$i++){
        $posxy .= ",".int(($lonlo-$pos[$i]{longitude}) * $picx / $mapx).",".int(($latlo-$pos[$i]{latitude}) * $picy / $mapy);
      }

    }

    # CHARGING STATION PATH 
    my $poscxy = int( $lonlo * $picx / $mapx ).",".int( $latlo * $picy / $mapy );
    if ( @posc > 1 ) {

      $poscxy = int( ( $lonlo-$posc[0]{longitude} ) * $picx / $mapx ).",".int( ( $latlo-$posc[0]{latitude} ) * $picy / $mapy );
      for (my $i=1;$i<@posc;$i++){
        $poscxy .= ",".int(($lonlo-$posc[$i]{longitude}) * $picx / $mapx).",".int(($latlo-$posc[$i]{latitude}) * $picy / $mapy);
      }

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
      ::FW_directNotify("#FHEMWEB:$_", "AutomowerConnectUpdateDetail ( '$name', '$type', '$img', $picx, $picy, $cslon, $cslat, '$csimgpos', $scalx, [ $posxy ], [ $limi ], [ $propli ], [ $poscxy ] )","");
    } devspec2array("TYPE=FHEMWEB");
  }
  return undef;
}

#########################
sub AlignArray {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $activity = $hash->{helper}{mower}{attributes}{mower}{activity};
  my $arrayName = $hash->{helper}{$activity}{arrayName};
  my $searchlen = 2;
  my $i = 0;
  my @temp = ();

  if ( isGoodActivity( $hash ) ) {

    my $k = -1;
    my $poslen = @{$hash->{helper}{mower}{attributes}{positions}};
    my @searchposlon = ($hash->{helper}{searchpos}[0]{longitude}, $hash->{helper}{searchpos}[1]{longitude});
    my @searchposlat = ($hash->{helper}{searchpos}[0]{latitude}, $hash->{helper}{searchpos}[1]{latitude});
    my $maxLength = $hash->{helper}{$activity}{maxLength};
    for ( $i = 0; $i < $poslen-2; $i++ ) { # 2 due to 2 alignment data sets at the end
      if ( $searchposlon[ 0 ] == $hash->{helper}{mower}{attributes}{positions}[ $i ]{longitude}
        && $searchposlat[ 0 ] == $hash->{helper}{mower}{attributes}{positions}[ $i ]{latitude}
        && $searchposlon[ 1 ] == $hash->{helper}{mower}{attributes}{positions}[ $i+1 ]{longitude}
        && $searchposlat[ 1 ] == $hash->{helper}{mower}{attributes}{positions}[ $i+1 ]{latitude} ) {
        # timediff per step
        my $dt = 0;
        $dt = int(($hash->{helper}{mower}{attributes}{metadata}{statusTimestamp} - $hash->{helper}{$arrayName}[0]{statusTimestamp})/$i) if ( $i && @{ $hash->{helper}{$arrayName} } );
        
        
        
        for ($k=$i-1;$k>-1;$k--) {

          if ( @{ $hash->{helper}{$arrayName} } ) {

            unshift (@{$hash->{helper}{$arrayName}}, dclone( $hash->{helper}{mower}{attributes}{positions}[ $k ] ) );

          } else {

            $hash->{helper}{$arrayName}[ 0 ] = dclone( $hash->{helper}{mower}{attributes}{positions}[ $k ] );

          }

          pop (@{$hash->{helper}{$arrayName}}) if (@{$hash->{helper}{$arrayName}} > $maxLength);
          $hash->{helper}{$arrayName}[ 0 ]{statusTimestamp} = $hash->{helper}{mower}{attributes}{metadata}{statusTimestamp} - $dt * $k;

          push ( @temp, dclone( $hash->{helper}{mower}{attributes}{positions}[ $k ] ) );

        }

        posMinMax( $hash, \@temp );
        #callFn if present
        if ( $hash->{helper}{$activity}{callFn} && @{$hash->{helper}{$arrayName}} > 1) {

          $hash->{helper}{$activity}{cnt} = $i;
          no strict "refs";
          &{$hash->{helper}{$activity}{callFn}}($hash);
          use strict "refs";

        }

        last;

      }

    }

  }

  $hash->{helper}{newdatasets} = $i;
  $hash->{helper}{searchpos} = [ dclone( $hash->{helper}{mower}{attributes}{positions}[0] ), dclone( $hash->{helper}{mower}{attributes}{positions}[1] ) ];
  return undef;

}

#########################
sub isGoodActivity {

  my ( $hash ) = @_;
  my $act = $hash->{helper}{mower}{attributes}{mower}{activity};
  my $actold = $hash->{helper}{mowerold}{attributes}{mower}{activity};
  
  my $ret = $hash->{helper}{$act}{arrayName} && $act eq $actold
          || $act =~ /^(CHARGING|PARKED_IN_CS)$/ && $actold =~ /^(PARKED_IN_CS|CHARGING)$/;
  return $ret;

}

#########################
sub ChargingStationPosition {
  my ($hash) = @_;
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
sub AreaStatistics {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $activity = 'MOWING';
  my $i = $hash->{helper}{$activity}{cnt};
  my $k = 0;
  my @xyarr  = @{$hash->{helper}{areapos}};# areapos
  my $n = @xyarr;
  my ($sclon, $sclat) = AttrVal($name,'scaleToMeterXY', $hash->{helper}{scaleToMeterLongitude} . ' ' .$hash->{helper}{scaleToMeterLatitude}) =~ /(-?\d+)\s+(-?\d+)/;
  my $lsum = 0;
  my $asum = 0;
  my $vm = 0;
  
  for ( $k = 0; $k <= $i-1; $k++) {

    $lsum += ((($xyarr[ $k ]{longitude} - $xyarr[ $k+1 ]{longitude}) * $sclon)**2 + (($xyarr[ $k ]{latitude} - $xyarr[ $k+1 ]{latitude}) * $sclat)**2)**0.5;

  }

  $asum = $lsum * AttrVal($name,'mowerCuttingWidth',0.24);
  my $td = $xyarr[ 0 ]{storedTimestamp} - $xyarr[ $k ]{storedTimestamp};
  $vm = sprintf( '%.6f', $lsum / $td ) * 1000 if ($td); # m/s
  $hash->{helper}{$activity}{speed} = $vm;
  $hash->{helper}{$activity}{track} = $lsum;
  $hash->{helper}{$activity}{area} = $asum;
  $hash->{helper}{statistics}{currentSpeed} = $vm;
  $hash->{helper}{statistics}{currentDayTrack} += $lsum;
  $hash->{helper}{statistics}{currentDayArea} += $asum;
  $hash->{helper}{statistics}{currentSpeed} = $vm;

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

  if ( $request =~ /^\/(AutomowerConnectDevice|AutomowerConnect)\/(\w+)\/map/ ) {

    my $type   = $1;
    my $name   = $2;
    my $hash = $::defs{$name};
      return ( "text/plain; charset=utf-8","${type} ${name}: No MAP_MIME for webhook $request" ) if ( !defined $hash->{helper}{MAP_MIME} || !$hash->{helper}{MAP_MIME} );
      return ( "text/plain; charset=utf-8","${type} ${name}: No MAP_CACHE for webhook $request" ) if ( !defined $hash->{helper}{MAP_CACHE} || !$hash->{helper}{MAP_CACHE} );
    my $mapMime = $hash->{helper}{MAP_MIME};
    my $mapData = $hash->{helper}{MAP_CACHE};
    return ( $mapMime, $mapData );

  }
  return ( "text/plain; charset=utf-8","No AutomowerConnect(Device) device for webhook $request" );

}

#########################
sub readMap {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $iam = "$type $name readMap:";
  RemoveInternalTimer( $hash, \&::FHEM::Devices::AMConnect::Common::readMap );
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
  $hash->{helper}{imageWidthHeight} = int($hash->{helper}{imageHeight} * ($maxLon-$minLon) / ($maxLat-$minLat)) . ' ' . $hash->{helper}{imageHeight} if ($maxLon-$minLon);

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
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{statistics}{numberOfChargingCycles} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{statistics}{numberOfChargingCycles} . ' </td><td>  </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{statistics}{numberOfCollisions} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{statistics}{numberOfCollisions} . ' </td><td>  </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{statistics}{totalChargingTime} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{statistics}{totalChargingTime} . ' </td><td> s </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{statistics}{totalCuttingTime} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{statistics}{totalCuttingTime} . ' </td><td> s </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{statistics}{totalRunningTime} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{statistics}{totalRunningTime} . '<sup>1</sup> </td><td> s </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{mower}{attributes}{statistics}{totalSearchingTime} &emsp;</td><td> ' . $hash->{helper}{mower}{attributes}{statistics}{totalSearchingTime} . ' </td><td> s </td></tr>';

    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{statistics}{currentSpeed} &emsp;</td><td> ' . $hash->{helper}{statistics}{currentSpeed} . ' </td><td> m/s </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{statistics}{currentDayTrack} &emsp;</td><td> ' . $hash->{helper}{statistics}{currentDayTrack} . ' </td><td> m </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{statistics}{currentDayArea} &emsp;</td><td> ' . $hash->{helper}{statistics}{currentDayArea} . ' </td><td> qm </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{statistics}{lastDayTrack} &emsp;</td><td> ' . $hash->{helper}{statistics}{lastDayTrack} . ' </td><td> m </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{statistics}{lastDayArea} &emsp;</td><td> ' . $hash->{helper}{statistics}{lastDayArea} . ' </td><td> qm </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{statistics}{currentWeekTrack} &emsp;</td><td> ' . $hash->{helper}{statistics}{currentWeekTrack} . ' </td><td> m </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{statistics}{currentWeekArea} &emsp;</td><td> ' . $hash->{helper}{statistics}{currentWeekArea} . ' </td><td> qm </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{statistics}{lastWeekTrack} &emsp;</td><td> ' . $hash->{helper}{statistics}{lastWeekTrack} . ' </td><td> m </td></tr>';
    $cnt++;$ret .= '<tr class="column '.( $cnt % 2 ? 'odd' : 'even' ).'"><td> $hash->{helper}{statistics}{lastWeekArea} &emsp;</td><td> ' . $hash->{helper}{statistics}{lastWeekArea} . ' </td><td> qm </td></tr>';

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
sub listInternalData {
  my ( $hash ) = @_;
  my $name = $hash->{NAME};
  my $cnt = 0;
  my $ret = '<html><table class="block wide">';
  $ret .= '<caption><b>Calculated Coordinates For Automatic Registration</b></caption><tbody>';

  my $xm = $hash->{helper}{chargingStation}{longitude} // 0;
  my $ym = $hash->{helper}{chargingStation}{latitude} // 0;
  my $csnr = scalar @{$hash->{helper}{cspos}};
  my $csnrmax = $hash->{helper}{PARKED_IN_CS}{maxLength};
  my $arnr = 0;
  $arnr = scalar @{$hash->{helper}{areapos}} if( scalar @{$hash->{helper}{areapos}} > 2 );
  my $arnrmax = $hash->{helper}{MOWING}{maxLength};

  $hash->{helper}{posMinMax} =~ /(-?\d*\.?\d+)\s(-?\d*\.?\d+)(\R|\s)(-?\d*\.?\d+)\s(-?\d*\.?\d+)/;

  if ( $::init_done && $1 && $2 && $4 && $5 ) {

    $ret .= '<tr class="col_header"><td> Data Sets ( max )&emsp;</td><td> Corner </td><td> Longitude </td><td> Latitude </td></tr>';
    $ret .= '<tr class="column odd"><td rowspan="2" style="vertical-align:middle;" > ' . ($csnr + $arnr) . ' ( ' . ($csnrmax + $arnrmax) . ' )&emsp;</td><td> Upper Left </td><td> ' . $1 . ' </td><td> ' . $2 . ' </td></tr>';
    $ret .= '<tr class="column even"><td> Lower Right </td><td> ' . $4 . ' </td><td> ' . $5 . ' </td></tr>';

    $ret .= '</tbody></table><p>';
    $ret .= '<table class="block wide">';
    $ret .= '<caption><b>Calculated Charging Station Coordinates</b></caption><tbody>'; 

    $ret .= '<tr class="col_header"><td> Data Sets (max)&emsp;</td><td> Longitude&emsp;</td><td> Latitude&emsp;</td></tr>';
    $ret .= '<tr class="column odd"><td> ' . $csnr . ' ( ' . $csnrmax . ' )&emsp;</td><td> ' . $xm . ' </td><td> ' . $ym . '&emsp;</td></tr>';

    $ret .= '</tbody></table><p>';
    $ret .= '<table class="block wide">';
    $ret .= '<caption><b>Way Point Stacks</b></caption><tbody>'; 

    $ret .= '<tr class="col_header"><td> Used For Action&emsp;</td><td> Stack Name&emsp;</td><td> Current Size&emsp;</td><td> Max Size&emsp;</td></tr>';
    $ret .= '<tr class="column odd"><td>PARKED_IN_CS, CHARGING&emsp;</td><td> cspos&emsp;</td><td> ' . $csnr . ' </td><td> ' . $csnrmax . '&emsp;</td></tr>';
    $ret .= '<tr class="column even"><td>MOWING&emsp;</td><td> areapos&emsp;</td><td> ' . $arnr . ' </td><td> ' . $arnrmax . '&emsp;</td></tr>';

    $ret .= '</tbody></table>';
    if ( $hash->{TYPE} eq 'AutomowerConnect' ) {

      $ret .= '<p><table class="block wide">';
      $ret .= '<caption><b>Rest API Data</b></caption><tbody>'; 

      $cnt++;$ret .= '<tr class="column ' . ( $cnt % 2 ? "odd" : "even" ) . '"><td> Link to APIs</td><td><a target="_blank" href="https://developer.husqvarnagroup.cloud/">Husqvarna Developer</a></td></tr>';
      $cnt++;$ret .= '<tr class="column ' . ( $cnt % 2 ? "odd" : "even" ) . '"><td> Authentification API URL</td><td>' . ::FHEM::AutomowerConnect::AUTHURL . '</td></tr>';
      $cnt++;$ret .= '<tr class="column ' . ( $cnt % 2 ? "odd" : "even" ) . '"><td> Automower Connect API URL</td><td>' . ::FHEM::AutomowerConnect::APIURL . '</td></tr>';
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

##############################################################

1;
