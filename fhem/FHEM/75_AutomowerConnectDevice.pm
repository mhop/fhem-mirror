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
my $cvsid = '$Id$';
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
require FHEM::Devices::AMConnect::Common;


##############################################################

sub Initialize() {
  my ($hash) = @_;

  $hash->{DefFn}      = \&FHEM::Devices::AMConnect::Common::Define;
  $hash->{UndefFn}    = \&FHEM::Devices::AMConnect::Common::Undefine;
  $hash->{RenameFn}   = \&FHEM::Devices::AMConnect::Common::Rename;
  $hash->{GetFn}      = \&FHEM::Devices::AMConnect::Common::Get;
  $hash->{FW_detailFn}= \&FHEM::Devices::AMConnect::Common::FW_detailFn;
  $hash->{SetFn}      = \&Set;
  $hash->{NotifyFn}   = \&Notify;
  $hash->{AttrFn}     = \&Attr;
  $hash->{AttrList}   = "disable:1,0 " .
                        "debug:1,0 " .
                        "disabledForIntervals " .
                        "mapImagePath " .
                        "mapImageWidthHeight " .
                        "mapImageCoordinatesToRegister:textField-long " .
                        "mapImageCoordinatesUTM:textField-long " .
                        "mapImageZoom " .
                        "mapBackgroundColor " .
                        "mapDesignAttributes:textField-long " .
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
  ( $hash->{VERSION} ) = $cvsid =~ /\.pm (.*)Z/ if ( !$hash->{VERSION} );

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
    if ( defined ($hash->{helper}{mower}{id}) ){ # update dataset

      $hash->{helper}{mowerold} = dclone( $hash->{helper}{mower} );
      
    } else { # first data set

      $hash->{helper}{mowerold} = $myMower;
      $hash->{helper}{searchpos} = [ dclone( $hash->{helper}{mowerold}{attributes}{positions}[0] ), dclone( $hash->{helper}{mowerold}{attributes}{positions}[1] ) ];
      $hash->{helper}{timestamps}[ 0 ] = $hash->{helper}{mowerold}{attributes}{metadata}{statusTimestamp};

      if ( AttrVal( $name, 'mapImageCoordinatesToRegister', '' ) eq '' ) {
        ::FHEM::Devices::AMConnect::Common::posMinMax( $hash, $hash->{helper}{mowerold}{attributes}{positions} );
      }

    }

    $hash->{helper}{mower} = $myMower;
    # add alignment data set to the end
    push( @{ $hash->{helper}{mower}{attributes}{positions} }, @{ dclone( $hash->{helper}{searchpos} ) } );
    $hash->{helper}{newdatasets} = 0;

    my $storediff = $hash->{helper}{mower}{attributes}{metadata}{statusTimestamp} - $hash->{helper}{mowerold}{attributes}{metadata}{statusTimestamp};
    if ($storediff) {

      ::FHEM::Devices::AMConnect::Common::AlignArray( $hash );
      ::FHEM::Devices::AMConnect::Common::FW_detailFn_Update ($hash) if (AttrVal($name,'showMap',1));

    }


    
    readingsBeginUpdate($hash);

      readingsBulkUpdateIfChanged($hash, "batteryPercent", $hash->{helper}{mower}{attributes}{battery}{batteryPercent} ); 
      my $pref = 'mower';
      readingsBulkUpdateIfChanged($hash, $pref.'_mode', $hash->{helper}{mower}{attributes}{$pref}{mode} );
      readingsBulkUpdateIfChanged($hash, $pref.'_activity', $hash->{helper}{mower}{attributes}{$pref}{activity} );
      readingsBulkUpdateIfChanged($hash, $pref.'_state', $hash->{helper}{mower}{attributes}{$pref}{state} );
      readingsBulkUpdateIfChanged($hash, $pref.'_commandStatus', 'cleared' );

      my $tstamp = $hash->{helper}{mower}{attributes}{$pref}{errorCodeTimestamp};
      my $timestamp = ::FHEM::Devices::AMConnect::Common::FmtDateTimeGMT($tstamp/1000);
      readingsBulkUpdateIfChanged($hash, $pref."_errorCodeTimestamp", $tstamp ? $timestamp : '-' );

      my $errc = $hash->{helper}{mower}{attributes}{$pref}{errorCode};
      readingsBulkUpdateIfChanged($hash, $pref.'_errorCode', $tstamp ? $errc  : '-');

      my $errd = $::FHEM::Devices::AMConnect::Common::errortable->{$errc};
      readingsBulkUpdateIfChanged($hash, $pref.'_errorDescription', $tstamp ? $errd : '-');

      $pref = 'system';
      readingsBulkUpdateIfChanged($hash, $pref."_name", $hash->{helper}{mower}{attributes}{$pref}{name} );
      my $model = $hash->{helper}{mower}{attributes}{$pref}{model};
      $model =~ s/AUTOMOWER./AM/;
      # $hash->{MODEL} = '' if (!defined $hash->{MODEL});
      $hash->{MODEL} = $model if ( $model and $hash->{MODEL} ne $model );
      readingsBulkUpdateIfChanged($hash, $pref."_serialNumber", $hash->{helper}{mower}{attributes}{$pref}{serialNumber} );
      $pref = 'planner';
      readingsBulkUpdateIfChanged($hash, "planner_restrictedReason", $hash->{helper}{mower}{attributes}{$pref}{restrictedReason} );
      readingsBulkUpdateIfChanged($hash, "planner_overrideAction", $hash->{helper}{mower}{attributes}{$pref}{override}{action} );
      
      $tstamp = $hash->{helper}{mower}{attributes}{$pref}{nextStartTimestamp};
      $timestamp = ::FHEM::Devices::AMConnect::Common::FmtDateTimeGMT($tstamp/1000);
      readingsBulkUpdateIfChanged($hash, "planner_nextStart", $tstamp ? $timestamp : '-' );  
      $pref = 'statistics';
      readingsBulkUpdateIfChanged($hash, $pref."_numberOfCollisions", $hash->{helper}->{mower}{attributes}{$pref}{numberOfCollisions} );
      readingsBulkUpdateIfChanged($hash, $pref."_newGeoDataSets", $hash->{helper}{newdatasets} );
      $pref = 'settings';
      readingsBulkUpdateIfChanged($hash, $pref."_headlight", $hash->{helper}->{mower}{attributes}{$pref}{headlight}{mode} );
      readingsBulkUpdateIfChanged($hash, $pref."_cuttingHeight", $hash->{helper}->{mower}{attributes}{$pref}{cuttingHeight} );
      $pref = 'status';
      my $connected = $hash->{helper}{mower}{attributes}{metadata}{connected};
      readingsBulkUpdateIfChanged($hash, $pref."_connected", ( $connected ? "CONNECTED($connected)"  : "OFFLINE($connected)") );
      readingsBulkUpdateIfChanged($hash, $pref."_Timestamp", FmtDateTime( $hash->{helper}{mower}{attributes}{metadata}{statusTimestamp}/1000 ));
      readingsBulkUpdateIfChanged($hash, $pref."_TimestampDiff", $storediff/1000 );
      readingsBulkUpdateIfChanged($hash, $pref."_TimestampOld", FmtDateTime( $hash->{helper}{mowerold}{attributes}{metadata}{statusTimestamp}/1000 ));
      $pref = 'positions';
      readingsBulkUpdate($hash, 'state', 'connected',1);
    readingsEndUpdate($hash, 1);

      my @time = localtime();
      my $secs = ( $time[2] * 3600 ) + ( $time[1] * 60 ) + $time[0];
      my $interval = $hosthash->{helper}->{interval};
      # do at midnight
      if ( $secs <= $interval ) {

            $hash->{helper}{statistics}{lastDayTrack} = $hash->{helper}{statistics}{currentDayTrack};
            $hash->{helper}{statistics}{lastDayArea} = $hash->{helper}{statistics}{currentDayArea};
            $hash->{helper}{statistics}{currentWeekTrack} += $hash->{helper}{statistics}{currentDayTrack};
            $hash->{helper}{statistics}{currentWeekArea} += $hash->{helper}{statistics}{currentDayArea};
            $hash->{helper}{statistics}{currentDayTrack} = 0;
            $hash->{helper}{statistics}{currentDayArea} = 0;
            # do on mondays
            if ( $time[6] == 1 ) {

              $hash->{helper}{statistics}{lastWeekTrack} = $hash->{helper}{statistics}{currentWeekTrack};
              $hash->{helper}{statistics}{lastWeekArea} = $hash->{helper}{statistics}{currentWeekArea};
              $hash->{helper}{statistics}{currentWeekTrack} = 0;
              $hash->{helper}{statistics}{currentWeekArea} = 0;

              #clear position arrays
              $hash->{helper}{areapos} = [];
              $hash->{helper}{otherpos} = [];

        }
      }
    readingsSingleUpdate($hash, 'state', 'connected',1);

  }

  return undef;

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

    my $xm = $hash->{helper}{chargingStation}{longitude} // 10.1165;
    my $ym = $hash->{helper}{chargingStation}{latitude} // 51.28;
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
  } elsif ( $setName eq 'defaultDesignAttributesToAttribute' ) {

    my $design = $hash->{helper}{mapdesign};
    CommandAttr( $hash, "$name mapDesignAttributes $design" );
    return undef;

  ################
  } elsif ( ReadingsVal( $name, 'state', 'defined' ) !~ /defined|initialized/ && $setName =~ /^(Start|Park|cuttingHeight)$/ ) {
    if ( $setVal =~ /^(\d+)$/) {

      ::FHEM::Devices::AMConnect::Common::CMD($hash ,$setName, $setVal);
      return undef;

    }

  ################
  } elsif ( ReadingsVal( $name, 'state', 'defined' ) !~ /defined|initialized/ && $setName eq 'headlight' ) {
    if ( $setVal =~ /^(ALWAYS_OFF|ALWAYS_ON|EVENING_ONLY|EVENING_AND_NIGHT)$/) {

      ::FHEM::Devices::AMConnect::Common::CMD($hash ,$setName, $setVal);
      return undef;

    }

  ################
  } elsif (ReadingsVal( $name, 'state', 'defined' ) !~ /defined|initialized/ && $setName =~ /ParkUntilFurtherNotice|ParkUntilNextSchedule|Pause|ResumeSchedule|sendScheduleFromAttributeToMower/) {

    ::FHEM::Devices::AMConnect::Common::CMD($hash,$setName);
    return undef;

  }
  my $ret = " ParkUntilFurtherNotice:noArg ParkUntilNextSchedule:noArg Pause:noArg Start:selectnumbers,60,60,600,0,lin Park:selectnumbers,60,60,600,0,lin ResumeSchedule:noArg ";
  $ret .= "chargingStationPositionToAttribute:noArg headlight:ALWAYS_OFF,ALWAYS_ON,EVENING_ONLY,EVENING_AND_NIGHT cuttingHeight:1,2,3,4,5,6,7,8,9 mowerScheduleToAttribute:noArg ";
  $ret .= "sendScheduleFromAttributeToMower:noArg defaultDesignAttributesToAttribute:noArg ";
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

        ::FHEM::Devices::AMConnect::Common::readMap($hash);
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

      if ( AttrVal( $name,'mapImageCoordinatesToRegister', '' ) && $attrVal =~ /(-?\d*\.?\d+)\s(-?\d*\.?\d+)(\R|\s)(-?\d*\.?\d+)\s(-?\d*\.?\d+)/ ) {

        my ( $x1, $y1, $x2, $y2 ) = ( $1, $2, $4, $5 );
        AttrVal( $name,'mapImageCoordinatesToRegister', '' ) =~ /(-?\d*\.?\d+)\s(-?\d*\.?\d+)(\R|\s)(-?\d*\.?\d+)\s(-?\d*\.?\d+)/;
        my ( $lo1, $la1, $lo2, $la2 ) = ( $1, $2, $4, $5 );
        my $scx = int( ( $x1 - $x2) / ( $lo1 - $lo2 ) );
        my $scy = int( ( $y1 - $y2 ) / ( $la1 - $la2 ) );
        CommandAttr($hash,"$name scaleToMeterXY $scx $scy");

      } else {
        return "$iam $attrName has a wrong format use linewise pairs <floating point longitude><one space character><floating point latitude> or the attribute mapImageCoordinatesToRegister was not set before.";
    }
      Log3 $name, 3, "$iam $cmd $attrName $attrVal";

    } elsif( $cmd eq "del" ) {

      Log3 $name, 3, "$iam $cmd $attrName and set default";

    }
  ##########
  } elsif( $attrName eq "mapImageCoordinatesToRegister" ) {

    if( $cmd eq "set" ) {

      return "$iam $attrName has a wrong format use linewise pairs <floating point longitude><one space character><floating point latitude>" unless( $attrVal =~ /(-?\d*\.?\d+)\s(-?\d*\.?\d+)(\R|\s)(-?\d*\.?\d+)\s(-?\d*\.?\d+)/ );
      Log3 $name, 3, "$iam $cmd $attrName $attrVal";

    } elsif( $cmd eq "del" ) {

      Log3 $name, 3, "$iam $cmd $attrName and set default";

    }
  ##########
  } elsif( $attrName eq "chargingStationCoordinates" ) {

    if( $cmd eq "set" ) {

      return "$iam $attrName has a wrong format use <floating point longitude><one space character><floating point latitude>" unless( $attrVal =~ /(-?\d*\.?\d+)\s(-?\d*\.?\d+)/ );
      Log3 $name, 3, "$iam $cmd $attrName $attrVal";

    } elsif( $cmd eq "del" ) {

      Log3 $name, 3, "$iam $cmd $attrName and set default";

    }
  ##########
  } elsif( $attrName eq "mapImageWidthHeight" ) {

    if( $cmd eq "set" ) {

      return "$iam $attrName has a wrong format use <integer longitude><one space character><integer latitude>" unless( $attrVal =~ /(\d+)\s(\d+)/ );
      Log3 $name, 3, "$iam $cmd $attrName $attrVal";

    } elsif( $cmd eq "del" ) {

      Log3 $name, 3, "$iam $cmd $attrName and set default";

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

##############################################################


1;

__END__
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
     <li><a id='AutomowerConnectDevice-set-mowerScheduleToAttribute'>mowerScheduleToAttribute</a><br>
      <code>set &lt;name&gt; mowerScheduleToAttribute</code><br>
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
      <code>get &lt;name&gt; html</code><br>
      Returns the mower area image as html code. For use in uiTable, TabletUI, Floorplan, readingsGroup, weblink etc.</li>

    <li><a id='AutomowerConnectDevice-get-InternalData'>InternalData</a><br>
      <code>get &lt;name&gt; InternalData</code><br>
      Lists some device internal data</li>

    <li><a id='AutomowerConnectDevice-get-MowerData'>MowerData</a><br>
      <code>get &lt;name&gt; MowerData</code><br>
      Lists all mower data with its hash path exept positon array. The hash path can be used for generating userReadings. The trigger is <i>connected</i>.<br>
      Example: created reading <code>serialnumber</code> with hash path <code>$hash->{helper}{mower}{attributes}{system}{serialNumber}</code><br><br>
      <code>attr &lt;name&gt; userReadings serialnumber:connected {$defs{$name}->{helper}{mower}{attributes}{system}{serialNumber}}</code></li>

    <li><a id='AutomowerConnectDevice-get-StatisticsData'>StatisticsData</a><br>
      <code>get &lt;name&gt; StatisticsData</code><br>
      Lists statistics data with its hash path. The hash path can be used for generating userReadings. The trigger is <i>connected</i>.</li>

    <li><a id='AutomowerConnectDevice-get-errorCodes'>errorCodes</a><br>
      <code>get &lt;name&gt; errorCodes</code><br>
      Lists API response status codes and mower error codes</li>
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

    <li><a id='AutomowerConnectDevice-attr-mapBackgroundColor'>mapBackgroundColor</a><br>
      <code>attr &lt;name&gt; mapBackgroundColor &lt;color valuer&gt;</code><br>
      The value is used as background-color.</li>

    <li><a id='AutomowerConnectDevice-attr-mapDesignAttributes'>mapDesignAttributes</a><br>
      <code>attr &lt;name&gt; mapDesignAttributes &lt;complete list of design-attributes&gt;</code><br>
      Load the list of attributes by <code>set &lt;name&gt; defaultDesignAttributesToAttribute</code> to change its values. Some default values are 
      <ul>
        <li>mower path (activity MOWING): red</li>
        <li>path in CS (activity CHARGING,PARKED_IN_CS): grey</li>
        <li>path for interval with error (all activities with error): kind of magenta</li>
        <li>all other activities: green</li>
      </ul>
    </li>

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
      Set the number of way points stored and displayed, default 5000.
      While in activity MOWING every 30 s a geo data set is generated.
      While in activity PARKED_IN_CS/CHARGING every 42 min a geo data set is generated.</li>

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
    <li>mower_mode - current working mode "MAIN_AREA" | "SECONDARY_AREA" | "HOME" | "DEMO" | "UNKNOWN"</li>
    <li>mower_state - current status "UNKNOWN" | "NOT_APPLICABLE" | "PAUSED" | "IN_OPERATION" | "WAIT_UPDATING" | "WAIT_POWER_UP" | "RESTRICTED" | "OFF" | "STOPPED" | "ERROR" | "FATAL_ERROR" |"ERROR_AT_POWER_UP"</li>
    <li>planner_nextStart - next start time</li>
    <li>planner_restrictedReason - reason for parking NOT_APPLICABLE, NONE, WEEK_SCHEDULE, PARK_OVERRIDE, SENSOR, DAILY_LIMIT, FOTA, FROST</li>
    <li>planner_overrideAction - reason for override a planned action NOT_ACTIVE, FORCE_PARK, FORCE_MOW</li>
    <li>state - status of connection FHEM to Husqvarna Cloud API and device state (e.g. defined, connected, error)</li>
    <li>status_statusTimestampOld - local time of second last change of the API content</li>
    <li>settings_cuttingHeight - actual cutting height from API</li>
    <li>settings_headlight - actual headlight mode from API</li>
    <li>statistics_newGeoDataSets - number of new data sets between the last two different time stamps</li>
    <li>statistics_numberOfCollisions - number of collisions</li>
    <li>status_connected - state of connetion between mower and Husqvarna Cloud, (1 => CONNECTED, 0 => OFFLINE)</li>
    <li>status_statusTimestamp - local time of last change of the API content</li>
    <li>status_statusTimestampDiff - time difference in seconds between the last and second last change of the API content</li>
    <li>status_statusTimestampOld - local time of second last change of the API content</li>
    <li>system_name - name of the mower</li>

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

     <li><a id='AutomowerConnectDevice-set-mowerScheduleToAttribute'>mowerScheduleToAttribute</a><br>
      <code>set &lt;name&gt; mowerScheduleToAttribute</code><br>
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

    <li><a id='AutomowerConnectDevice-get-errorCodes'>errorCodes</a><br>
      <code>get &lt;name&gt; errorCodes</code><br>
      Listet die Statuscode der API-Anfrage und die Fehlercodes des Mähroboters auf.</li>

    <li><a id='AutomowerConnectDevice-get-InternalData'>InternalData</a><br>
      <code>get &lt;name&gt; InternalData</code><br>
      Listet einige Daten des FHEM-Gerätes auf.</li>

    <li><a id='AutomowerConnectDevice-get-MowerData'>MowerData</a><br>
      <code>get &lt;name&gt; MowerData</code><br>
      Listet alle Daten des Mähers einschließlich Hashpfad auf ausgenommen das Positonsarray. Der Hashpfad kann zur Erzeugung von userReadings genutzt werden, getriggert wird durch <i>connected</i>.<br>
      Beispiel: erzeugen des Reading <code>serialnumber</code> mit dem Hashpfad <code>$hash->{helper}{mower}{attributes}{system}{serialNumber}</code><br><br>
      <code>attr &lt;name&gt; userReadings serialnumber:connected {$defs{$name}->{helper}{mower}{attributes}{system}{serialNumber}}</code></li>

    <li><a id='AutomowerConnectDevice-get-StatisticsData'>StatisticsData</a><br>
      <code>get &lt;name&gt; StatisticsData</code><br>
      Listet statistische Daten mit ihrem Hashpfad auf. Der Hashpfad kann zur Erzeugung von userReadings genutzt werden, getriggert wird durch <i>connected</i></li>
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

    <li><a id='AutomowerConnectDevice-attr-mapImageZoom'>mapImageZoom</a><br>
      <code>attr &lt;name&gt; mapImageHeight &lt;height in pixel&gt;</code><br>
      Zoomfaktor zur Salierung des Bildes auf das Pfad, Anfangs- u. Endpunkte gezeichnet werden. Standard: 0.5</li>

    <li><a id='AutomowerConnectDevice-attr-mapBackgroundColor'>mapBackgroundColor</a><br>
      <code>attr &lt;name&gt; mapBackgroundColor &lt;color value&gt;</code><br>
      Der Wert wird als Hintergrungfarbe benutzt.</li>

    <li><a id='AutomowerConnectDevice-attr-mapDesignAttributes'>mapDesignAttributes</a><br>
      <code>attr &lt;name&gt; mapDesignAttributes &lt;complete list of design-attributes&gt;</code><br>
      Lade die Attributliste mit <code>set &lt;name&gt; defaultDesignAttributesToAttribute</code> um die Werte zu ändern. Einige Vorgabewerte:
      <ul>
        <li>Pfad beim mähen (Aktivität MOWING): rot</li>
        <li>In der Ladestation (Aktivität CHARGING,PARKED_IN_CS): grau</li>
        <li>Pfad eines Intervalls mit Fehler (alle Aktivitäten with error): Eine Art Magenta</li>
        <li>Pfad aller anderen Aktivitäten: grün</li>
      </ul>
    </li>

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
      Liste von Positionen, um die Grundstücksgrenze zu beschreiben. Format: Zeilenweise Paare von Longitude- u. Latitudewerten getrennt durch 1 Leerzeichen. Eine Zeile wird aufgeteilt durch (<code>/\s|,|\R$/</code>).<br>Die genaue Position der Grenzpunkte kann man über die <a target="_blank" href="https://geoportal.de/Anwendungen/Geoportale%20der%20L%C3%A4nder.html">Geoportale der Länder</a> finden. Eine Umrechnung  der UTM32 Daten in Meter nach ETRS89 in Dezimalgrad kann über das <a target="_href="https://gdz.bkg.bund.de/koordinatentransformation">BKG-Geodatenzentrum</a> erfolgen.</li>

    <li><a id='AutomowerConnectDevice-attr-numberOfWayPointsToDisplay'>numberOfWayPointsToDisplay</a><br>
      <code>attr &lt;name&gt; numberOfWayPointsToDisplay &lt;number of way points&gt;</code><br>
      Legt die Anzahl der gespeicherten und anzuzeigenden Wegpunkte fest, default 5000.
      Während der Aktivität MOWING wird ca. alle 30 s und während PARKED_IN_CS/CHARGING wird alle 42 min ein Geodatensatz erzeugt.</li>

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
    <li>mower_mode - aktueller Arbeitsmodus "MAIN_AREA" | "SECONDARY_AREA" | "HOME" | "DEMO" | "UNKNOWN"</li>
    <li>mower_state - aktueller Status "UNKNOWN" | "NOT_APPLICABLE" | "PAUSED" | "IN_OPERATION" | "WAIT_UPDATING" | "WAIT_POWER_UP" | "RESTRICTED" | "OFF" | "STOPPED" | "ERROR" | "FATAL_ERROR" |"ERROR_AT_POWER_UP"</li>
    <li>planner_nextStart - nächste Startzeit</li>
    <li>planner_restrictedReason - Grund für Parken NOT_APPLICABLE, NONE, WEEK_SCHEDULE, PARK_OVERRIDE, SENSOR, DAILY_LIMIT, FOTA, FROST</li>
    <li>planner_overrideAction -   Grund für vorrangige Aktion NOT_ACTIVE, FORCE_PARK, FORCE_MOW</li>
    <li>state - Status der Verbindung des FHEM-Gerätes zur Husqvarna Cloud API (defined, connected, error).</li>
    <li>settings_cuttingHeight - aktuelle Schnitthöhe aus der API</li>
    <li>settings_headlight - aktueller Scheinwerfermode aus der API</li>
    <li>statistics_newGeoDataSets - Anzahl der neuen Datensätze zwischen den letzten zwei unterschiedlichen Zeitstempeln</li>
    <li>statistics_numberOfCollisions - Anzahl der Kollisionen</li>
    <li>status_connected - Status der Verbindung zwischen dem Automower und der Husqvarna Cloud, (1 => CONNECTED, 0 => OFFLINE)</li>
    <li>status_statusTimestamp - Lokalzeit der letzten Änderung der Daten in der API</li>
    <li>status_statusTimestampDiff - Zeitdifferenz zwichen den beiden letzten Änderungen im Inhalt der Daten aus der API</li>
    <li>status_statusTimestampOld - Lokalzeit der vorletzten Änderung der Daten in der API</li>
    <li>system_name - Name des Automowers</li>
  </ul>
</ul>

=end html_DE
