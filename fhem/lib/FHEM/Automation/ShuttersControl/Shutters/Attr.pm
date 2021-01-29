###############################################################################
#
# Developed with Kate
#
#  (c) 2018-2020 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
#  All rights reserved
#
#   Special thanks goes to:
#       - Bernd (Cluni) this module is based on the logic of his script "Rollladensteuerung für HM/ROLLO inkl. Abschattung und Komfortfunktionen in Perl" (https://forum.fhem.de/index.php/topic,73964.0.html)
#       - Beta-User for many tests, many suggestions and good discussions
#       - pc1246 write english commandref
#       - FunkOdyssey commandref style
#       - sledge fix many typo in commandref
#       - many User that use with modul and report bugs
#       - Christoph (christoph.kaiser.in) Patch that expand RegEx for Window Events
#       - Julian (Loredo) expand Residents Events for new Residents functions
#       - Christoph (Christoph Morrison) for fix Commandref, many suggestions and good discussions
#
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License,or
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
# $Id$
#
###############################################################################

## Subklasse Attr von ASC_Shutters##
package FHEM::Automation::ShuttersControl::Shutters::Attr;

use strict;
use warnings;
use utf8;

use FHEM::Automation::ShuttersControl::Helper qw (IsAdv PerlCodeCheck);

use GPUtils qw(GP_Import);

## Import der FHEM Funktionen
BEGIN {
    GP_Import(
        qw(
          AttrVal
          CommandAttr
          gettimeofday)
    );
}

sub _setAttributs {
    my $shuttersDev = shift;
    my $attr        = shift;
    my $attrVal     = shift;

    CommandAttr( undef, $shuttersDev . ' ' . $attr . ' ' . $attrVal );

    return;
}

sub _getPosition {
    my $self = shift;

    my $attr         = shift;
    my $userAttrList = shift;

    return $self->{ $self->{shuttersDev} }->{$attr}->{position}
      if (
        exists( $self->{ $self->{shuttersDev} }->{$attr}->{LASTGETTIME} )
        && ( gettimeofday() -
            $self->{ $self->{shuttersDev} }->{$attr}->{LASTGETTIME} ) < 2
      );
    $self->{ $self->{shuttersDev} }->{$attr}->{LASTGETTIME} =
      int( gettimeofday() );

    my $position;
    my $posAssignment;

    if (
        AttrVal( $self->{shuttersDev}, $attr,
            $FHEM::Automation::ShuttersControl::userAttrList{$userAttrList}
              [ AttrVal( $self->{shuttersDev}, 'ASC', 2 ) ] ) =~
        m{\A\{.+\}\z}xms
      )
    {
        my $response = PerlCodeCheck(
            AttrVal(
                $self->{shuttersDev},
                $attr,
                $FHEM::Automation::ShuttersControl::userAttrList{$userAttrList}
                  [ AttrVal( $self->{shuttersDev}, 'ASC', 2 ) ]
            )
        );

        ( $position, $posAssignment ) = split ':', $response;

        $position = (
              $position =~ m{\A\d+(\.\d+)?\z}xms
            ? $position
            : $FHEM::Automation::ShuttersControl::userAttrList{$userAttrList}
              [ AttrVal( $self->{shuttersDev}, 'ASC', 2 ) ]
        );

        $posAssignment = (
                defined($posAssignment)
            &&  $posAssignment =~ m{\A\d+(\.\d+)?\z}xms
              ? $posAssignment
              : 'none'
        );
    }
    else {
        ( $position, $posAssignment ) =
          FHEM::Automation::ShuttersControl::Helper::GetAttrValues(
            $self->{shuttersDev},
            $attr,
            $FHEM::Automation::ShuttersControl::userAttrList{$userAttrList}
              [ AttrVal( $self->{shuttersDev}, 'ASC', 2 ) ]
          );
    }

    ### erwartetes Ergebnis
    # DEVICE:READING
    $self->{ $self->{shuttersDev} }->{$attr}->{position} = $position;
    $self->{ $self->{shuttersDev} }->{$attr}->{posAssignment} =
      $posAssignment;

    return $self->{ $self->{shuttersDev} }->{$attr}->{position};

    if (
        defined(
            PerlCodeCheck(
                $self->{ $self->{shuttersDev} }->{$attr}->{position}
            )
        )
      )
    {
        $self->{ $self->{shuttersDev} }->{$attr}->{position} =
          PerlCodeCheck(
            $self->{ $self->{shuttersDev} }->{$attr}->{position} );
    }

    return (
        $self->{ $self->{shuttersDev} }->{$attr}->{position} =~
          m{^\d+(\.\d+)?$}xms
        ? $self->{ $self->{shuttersDev} }->{$attr}->{position}
        : $FHEM::Automation::ShuttersControl::userAttrList{$userAttrList}
          [ AttrVal( $self->{shuttersDev}, 'ASC', 2 ) ]
    );
}

sub _getPositionAssignment {
    my $self = shift;

    my $attr  = shift;
    my $getFn = shift;

    return $self->{ $self->{shuttersDev} }->{$attr}->{posAssignment}
      if (
        exists( $self->{ $self->{shuttersDev} }->{$attr}->{LASTGETTIME} )
        && ( gettimeofday() -
            $self->{ $self->{shuttersDev} }->{$attr}->{LASTGETTIME} ) < 2
      );
    $FHEM::Automation::ShuttersControl::shutters->$getFn;

    return ( $self->{ $self->{shuttersDev} }->{$attr}->{posAssignment} );
}

sub setAntiFreezePos {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_Antifreeze_Pos', $attrVal );

    return;
}

sub getAntiFreezePos {
    my $self = shift;

    return $FHEM::Automation::ShuttersControl::shutters->_getPosition(
        'ASC_Antifreeze_Pos',
'ASC_Antifreeze_Pos:5,10,15,20,25,30,35,40,45,50,55,60,65,70,75,80,85,90,95,100'
    );
}

sub getAntiFreezePosAssignment {
    my $self = shift;

    return
      $FHEM::Automation::ShuttersControl::shutters->_getPositionAssignment(
        'ASC_Antifreeze_Pos', 'getAntiFreezePos' );
}

sub setShuttersPlace {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_ShuttersPlace', $attrVal );

    return;
}

sub getShuttersPlace {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_ShuttersPlace', 'window' );
}

sub setSlatPosCmd {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_SlatPosCmd_SlatDevice',
        $attrVal );

    return;
}

sub getSlatPosCmd {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }->{ASC_SlatPosCmd_SlatDevice}
      ->{poscmd}
      if (
        exists(
            $self->{ $self->{shuttersDev} }->{ASC_SlatPosCmd_SlatDevice}
              ->{LASTGETTIME}
        )
        && ( gettimeofday() -
            $self->{ $self->{shuttersDev} }->{ASC_SlatPosCmd_SlatDevice}
            ->{LASTGETTIME} ) < 2
      );
    $self->{ $self->{shuttersDev} }->{ASC_SlatPosCmd_SlatDevice}->{LASTGETTIME}
      = int( gettimeofday() );
    my ( $slatPosCmd, $slatDevice ) =
      FHEM::Automation::ShuttersControl::Helper::GetAttrValues( $self->{shuttersDev},
        'ASC_SlatPosCmd_SlatDevice', 'none:none' );

    ## Erwartetes Ergebnis
    # upTime:upBrightnessVal

    $self->{ $self->{shuttersDev} }->{ASC_SlatPosCmd_SlatDevice}->{poscmd} =
      $slatPosCmd;
    $self->{ $self->{shuttersDev} }->{ASC_SlatPosCmd_SlatDevice}->{device} =
      $slatDevice;

    return $self->{ $self->{shuttersDev} }->{ASC_SlatPosCmd_SlatDevice}
      ->{poscmd};
}

sub getSlatDevice {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }->{ASC_SlatPosCmd_SlatDevice}
      ->{device}
      if (
        exists(
            $self->{ $self->{shuttersDev} }->{ASC_SlatPosCmd_SlatDevice}
              ->{LASTGETTIME}
        )
        && ( gettimeofday() -
            $self->{ $self->{shuttersDev} }->{ASC_SlatPosCmd_SlatDevice}
            ->{LASTGETTIME} ) < 2
      );
    $FHEM::Automation::ShuttersControl::shutters->getSlatPosCmd;

    return (
        $self->{ $self->{shuttersDev} }->{ASC_SlatPosCmd_SlatDevice}->{device}
    );
}

sub setPrivacyUpTime {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_PrivacyUpValue_beforeDayOpen',
        $attrVal );

    return;
}

sub getPrivacyUpTime {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }->{ASC_PrivacyUpValue_beforeDayOpen}
      ->{uptime}
      if (
        exists(
            $self->{ $self->{shuttersDev} }->{ASC_PrivacyUpValue_beforeDayOpen}
              ->{LASTGETTIME}
        )
        && ( gettimeofday() -
            $self->{ $self->{shuttersDev} }->{ASC_PrivacyUpValue_beforeDayOpen}
            ->{LASTGETTIME} ) < 2
      );
    $self->{ $self->{shuttersDev} }->{ASC_PrivacyUpValue_beforeDayOpen}
      ->{LASTGETTIME} = int( gettimeofday() );
    my ( $upTime, $upBrightnessVal ) =
      FHEM::Automation::ShuttersControl::Helper::GetAttrValues( $self->{shuttersDev},
        'ASC_PrivacyUpValue_beforeDayOpen', '-1:-1' );

    ## Erwartetes Ergebnis
    # upTime:upBrightnessVal

    $self->{ $self->{shuttersDev} }->{ASC_PrivacyUpValue_beforeDayOpen}
      ->{uptime} = $upTime;
    $self->{ $self->{shuttersDev} }->{ASC_PrivacyUpValue_beforeDayOpen}
      ->{upbrightnessval} =
      ( $upBrightnessVal ne 'none' ? $upBrightnessVal : -1 );

    $FHEM::Automation::ShuttersControl::shutters->setPrivacyUpStatus(0)
      if (
        defined(
            $FHEM::Automation::ShuttersControl::shutters->getPrivacyUpStatus
        )
        && $self->{ $self->{shuttersDev} }->{ASC_PrivacyUpValue_beforeDayOpen}
        ->{uptime} == -1
      );

    return $self->{ $self->{shuttersDev} }->{ASC_PrivacyUpValue_beforeDayOpen}
      ->{uptime};
}

sub getPrivacyUpBrightnessVal {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }->{ASC_PrivacyUpValue_beforeDayOpen}
      ->{upbrightnessval}
      if (
        exists(
            $self->{ $self->{shuttersDev} }->{ASC_PrivacyUpValue_beforeDayOpen}
              ->{LASTGETTIME}
        )
        && ( gettimeofday() -
            $self->{ $self->{shuttersDev} }->{ASC_PrivacyUpValue_beforeDayOpen}
            ->{LASTGETTIME} ) < 2
      );
    $FHEM::Automation::ShuttersControl::shutters->getPrivacyUpTime;

    return (
        defined(
            $self->{ $self->{shuttersDev} }->{ASC_PrivacyUpValue_beforeDayOpen}
              ->{upbrightnessval}
          )
        ? $self->{ $self->{shuttersDev} }->{ASC_PrivacyUpValue_beforeDayOpen}
          ->{upbrightnessval}
        : -1
    );
}

sub setPrivacyDownTime {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev},
        'ASC_PrivacyDownValue_beforeNightClose', $attrVal );

    return;
}

sub getPrivacyDownTime {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }
      ->{ASC_PrivacyDownValue_beforeNightClose}->{downtime}
      if (
        exists(
            $self->{ $self->{shuttersDev} }
              ->{ASC_PrivacyDownValue_beforeNightClose}->{LASTGETTIME}
        )
        && ( gettimeofday() -
            $self->{ $self->{shuttersDev} }
            ->{ASC_PrivacyDownValue_beforeNightClose}->{LASTGETTIME} ) < 2
      );
    $self->{ $self->{shuttersDev} }->{ASC_PrivacyDownValue_beforeNightClose}
      ->{LASTGETTIME} = int( gettimeofday() );
    my ( $downTime, $downBrightnessVal ) =
      FHEM::Automation::ShuttersControl::Helper::GetAttrValues( $self->{shuttersDev},
        'ASC_PrivacyDownValue_beforeNightClose', '-1:-1' );

    ## Erwartetes Ergebnis
    # downTime:downBrightnessVal

    $self->{ $self->{shuttersDev} }->{ASC_PrivacyDownValue_beforeNightClose}
      ->{downtime} = $downTime;
    $self->{ $self->{shuttersDev} }->{ASC_PrivacyDownValue_beforeNightClose}
      ->{downbrightnessval} =
      ( $downBrightnessVal ne 'none' ? $downBrightnessVal : -1 );

    $FHEM::Automation::ShuttersControl::shutters->setPrivacyDownStatus(0)
      if (
        defined(
            $FHEM::Automation::ShuttersControl::shutters->getPrivacyDownStatus
        )
        && $self->{ $self->{shuttersDev} }
        ->{ASC_PrivacyDownValue_beforeNightClose}->{downtime} == -1
      );

    return $self->{ $self->{shuttersDev} }
      ->{ASC_PrivacyDownValue_beforeNightClose}->{downtime};
}

sub getPrivacyDownBrightnessVal {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }
      ->{ASC_PrivacyDownValue_beforeNightClose}->{downbrightnessval}
      if (
        exists(
            $self->{ $self->{shuttersDev} }
              ->{ASC_PrivacyDownValue_beforeNightClose}->{LASTGETTIME}
        )
        && ( gettimeofday() -
            $self->{ $self->{shuttersDev} }
            ->{ASC_PrivacyDownValue_beforeNightClose}->{LASTGETTIME} ) < 2
      );
    $FHEM::Automation::ShuttersControl::shutters->getPrivacyDownTime;

    return (
        defined(
            $self->{ $self->{shuttersDev} }
              ->{ASC_PrivacyDownValue_beforeNightClose}->{downbrightnessval}
          )
        ? $self->{ $self->{shuttersDev} }
          ->{ASC_PrivacyDownValue_beforeNightClose}->{downbrightnessval}
        : -1
    );
}

sub setPrivacyUpPos {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_PrivacyUp_Pos', $attrVal );

    return;
}

sub getPrivacyUpPos {
    my $self = shift;

    return $FHEM::Automation::ShuttersControl::shutters->_getPosition(
        'ASC_PrivacyUp_Pos', 'ASC_PrivacyUp_Pos' );
}

sub getPrivacyUpPositionAssignment {
    my $self = shift;

    return
      $FHEM::Automation::ShuttersControl::shutters->_getPositionAssignment(
        'ASC_PrivacyUp_Pos', 'getPrivacyUpPos' );
}

sub setPrivacyDownPos {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_PrivacyDown_Pos', $attrVal );

    return;
}

sub getPrivacyDownPos {
    my $self = shift;

    return $FHEM::Automation::ShuttersControl::shutters->_getPosition(
        'ASC_PrivacyDown_Pos', 'ASC_PrivacyDown_Pos' );
}

sub getPrivacyDownPositionAssignment {
    my $self = shift;

    return
      $FHEM::Automation::ShuttersControl::shutters->_getPositionAssignment(
        'ASC_PrivacyDown_Pos', 'getPrivacyDownPos' );
}

sub setSelfDefenseMode {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_Self_Defense_Mode', $attrVal );

    return;
}

sub getSelfDefenseMode {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Self_Defense_Mode', 'gone' );
}

sub setSelfDefenseAbsentDelay {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_Self_Defense_AbsentDelay',
        $attrVal );

    return;
}

sub getSelfDefenseAbsentDelay {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Self_Defense_AbsentDelay', 300 );
}

sub setWiggleValue {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_WiggleValue', $attrVal );

    return;
}

sub getWiggleValue {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_WiggleValue', 5 );
}

sub setAdv {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_Adv', $attrVal );

    return;
}

sub getAdv {
    my $self = shift;

    return (
        AttrVal( $self->{shuttersDev}, 'ASC_Adv', 'off' ) eq 'on'
        ? ( IsAdv == 1 ? 1 : 0 )
        : 0
    );
}

### Begin Beschattung
sub setShadingPos {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_Shading_Pos', $attrVal );

    return;
}

sub getShadingPos {
    my $self = shift;

    return $FHEM::Automation::ShuttersControl::shutters->_getPosition(
        'ASC_Shading_Pos', 'ASC_Shading_Pos:10,20,30,40,50,60,70,80,90,100' );
}

sub getShadingPositionAssignment {
    my $self = shift;

    return
      $FHEM::Automation::ShuttersControl::shutters->_getPositionAssignment(
        'ASC_Shading_Pos', 'getShadingPos' );
}

sub setShadingMode {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_Shading_Mode', $attrVal );

    return;
}

sub getShadingMode {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Shading_Mode', 'off' );
}

sub _getTempSensor {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }->{ASC_TempSensor}->{device}
      if (
        exists(
            $self->{ $self->{shuttersDev} }->{ASC_TempSensor}->{LASTGETTIME}
        )
        && ( gettimeofday() -
            $self->{ $self->{shuttersDev} }->{ASC_TempSensor}->{LASTGETTIME} )
        < 2
      );
    $self->{ $self->{shuttersDev} }->{ASC_TempSensor}->{LASTGETTIME} =
      int( gettimeofday() );
    my ( $device, $reading ) =
      FHEM::Automation::ShuttersControl::Helper::GetAttrValues( $self->{shuttersDev},
        'ASC_TempSensor', 'none' );

    ### erwartetes Ergebnis
    # DEVICE:READING
    $self->{ $self->{shuttersDev} }->{ASC_TempSensor}->{device} = $device;
    $self->{ $self->{shuttersDev} }->{ASC_TempSensor}->{reading} =
      ( $reading ne 'none' ? $reading : 'temperature' );

    return $self->{ $self->{shuttersDev} }->{ASC_TempSensor}->{device};
}

sub getTempSensorReading {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }->{ASC_TempSensor}->{reading}
      if (
        exists(
            $self->{ $self->{shuttersDev} }->{ASC_TempSensor}->{LASTGETTIME}
        )
        && ( gettimeofday() -
            $self->{ $self->{shuttersDev} }->{ASC_TempSensor}->{LASTGETTIME} )
        < 2
      );
    $FHEM::Automation::ShuttersControl::shutters->_getTempSensor;

    return (
        defined( $self->{ $self->{shuttersDev} }->{ASC_TempSensor}->{reading} )
        ? $self->{ $self->{shuttersDev} }->{ASC_TempSensor}->{reading}
        : 'temperature'
    );
}

sub setIdleDetectionReading {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_Shutter_IdleDetection',
        $attrVal );

    return;
}

sub _getIdleDetectionReading {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }->{ASC_Shutter_IdleDetection}
      ->{reading}
      if (
        exists(
            $self->{ $self->{shuttersDev} }->{ASC_Shutter_IdleDetection}
              ->{LASTGETTIME}
        )
        && ( gettimeofday() -
            $self->{ $self->{shuttersDev} }->{ASC_Shutter_IdleDetection}
            ->{LASTGETTIME} ) < 2
      );
    $self->{ $self->{shuttersDev} }->{ASC_Shutter_IdleDetection}->{LASTGETTIME}
      = int( gettimeofday() );
    my ( $reading, $value ) =
      FHEM::Automation::ShuttersControl::Helper::GetAttrValues( $self->{shuttersDev},
        'ASC_Shutter_IdleDetection', 'none' );

    ### erwartetes Ergebnis
    # READING:VALUE
    $self->{ $self->{shuttersDev} }->{ASC_Shutter_IdleDetection}->{reading} =
      $reading;
    $self->{ $self->{shuttersDev} }->{ASC_Shutter_IdleDetection}->{value} =
      $value;

    return $self->{ $self->{shuttersDev} }->{ASC_Shutter_IdleDetection}
      ->{reading};
}

sub getIdleDetectionValue {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }->{ASC_Shutter_IdleDetection}->{value}
      if (
        exists(
            $self->{ $self->{shuttersDev} }->{ASC_Shutter_IdleDetection}
              ->{LASTGETTIME}
        )
        && ( gettimeofday() -
            $self->{ $self->{shuttersDev} }->{ASC_Shutter_IdleDetection}
            ->{LASTGETTIME} ) < 2
      );
    $FHEM::Automation::ShuttersControl::shutters->_getIdleDetectionReading;

    return (
        defined(
            $self->{ $self->{shuttersDev} }->{ASC_Shutter_IdleDetection}
              ->{value}
          )
        ? $self->{ $self->{shuttersDev} }->{ASC_Shutter_IdleDetection}->{value}
        : 'none'
    );
}

sub setBrightnessSensor {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_BrightnessSensor', $attrVal );

    return;
}

sub _getBrightnessSensor {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }->{ASC_BrightnessSensor}->{device}
      if (
        exists(
            $self->{ $self->{shuttersDev} }->{ASC_BrightnessSensor}
              ->{LASTGETTIME}
        )
        && ( gettimeofday() -
            $self->{ $self->{shuttersDev} }->{ASC_BrightnessSensor}
            ->{LASTGETTIME} ) < 2
      );
    $self->{ $self->{shuttersDev} }->{ASC_BrightnessSensor}->{LASTGETTIME} =
      int( gettimeofday() );
    my ( $device, $reading, $max, $min ) =
      FHEM::Automation::ShuttersControl::Helper::GetAttrValues( $self->{shuttersDev},
        'ASC_BrightnessSensor', 'none' );

    ### erwartetes Ergebnis
    # DEVICE:READING MAX:MIN
    $self->{ $self->{shuttersDev} }->{ASC_BrightnessSensor}->{device} = $device;
    $self->{ $self->{shuttersDev} }->{ASC_BrightnessSensor}->{reading} =
      ( $reading ne 'none' ? $reading : 'brightness' );
    $self->{ $self->{shuttersDev} }->{ASC_BrightnessSensor}->{triggermin} =
      ( $min ne 'none' ? $min : -2 );
    $self->{ $self->{shuttersDev} }->{ASC_BrightnessSensor}->{triggermax} =
      ( $max ne 'none' ? $max : -2 );

    return $self->{ $self->{shuttersDev} }->{ASC_BrightnessSensor}->{device};
}

sub getBrightnessReading {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }->{ASC_BrightnessSensor}->{reading}
      if (
        exists(
            $self->{ $self->{shuttersDev} }->{ASC_BrightnessSensor}
              ->{LASTGETTIME}
        )
        && ( gettimeofday() -
            $self->{ $self->{shuttersDev} }->{ASC_BrightnessSensor}
            ->{LASTGETTIME} ) < 2
      );
    $FHEM::Automation::ShuttersControl::shutters->_getBrightnessSensor;

    return (
        defined(
            $self->{ $self->{shuttersDev} }->{ASC_BrightnessSensor}->{reading}
          )
        ? $self->{ $self->{shuttersDev} }->{ASC_BrightnessSensor}->{reading}
        : 'brightness'
    );
}

sub getShadingAzimuthLeft {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }->{ASC_Shading_InOutAzimuth}
      ->{leftVal}
      if (
        exists(
            $self->{ $self->{shuttersDev} }->{ASC_Shading_InOutAzimuth}
              ->{LASTGETTIME}
        )
        && ( gettimeofday() -
            $self->{ $self->{shuttersDev} }->{ASC_Shading_InOutAzimuth}
            ->{LASTGETTIME} ) < 2
      );
    $FHEM::Automation::ShuttersControl::shutters->getShadingAzimuthRight;

    return $self->{ $self->{shuttersDev} }->{ASC_Shading_InOutAzimuth}
      ->{leftVal};
}

sub setShadingInOutAzimuth {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_Shading_InOutAzimuth', $attrVal );

    return;
}

sub getShadingAzimuthRight {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }->{ASC_Shading_InOutAzimuth}
      ->{rightVal}
      if (
        exists(
            $self->{ $self->{shuttersDev} }->{ASC_Shading_InOutAzimuth}
              ->{LASTGETTIME}
        )
        && ( gettimeofday() -
            $self->{ $self->{shuttersDev} }->{ASC_Shading_InOutAzimuth}
            ->{LASTGETTIME} ) < 2
      );
    $self->{ $self->{shuttersDev} }->{ASC_Shading_InOutAzimuth}->{LASTGETTIME}
      = int( gettimeofday() );
    my ( $left, $right ) =
      FHEM::Automation::ShuttersControl::Helper::GetAttrValues( $self->{shuttersDev},
        'ASC_Shading_InOutAzimuth', '95:265' );

    ### erwartetes Ergebnis
    # MIN:MAX

    $self->{ $self->{shuttersDev} }->{ASC_Shading_InOutAzimuth}->{leftVal} =
      $left;
    $self->{ $self->{shuttersDev} }->{ASC_Shading_InOutAzimuth}->{rightVal} =
      $right;

    return $self->{ $self->{shuttersDev} }->{ASC_Shading_InOutAzimuth}
      ->{rightVal};
}

sub setShadingMinOutsideTemperature {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_Shading_Min_OutsideTemperature',
        $attrVal );

    return;
}

sub getShadingMinOutsideTemperature {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Shading_Min_OutsideTemperature',
        18 );
}

sub setShadingMinMaxElevation {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_Shading_MinMax_Elevation',
        $attrVal );

    return;
}

sub getShadingMinElevation {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }->{ASC_Shading_MinMax_Elevation}
      ->{minVal}
      if (
        exists(
            $self->{ $self->{shuttersDev} }->{ASC_Shading_MinMax_Elevation}
              ->{LASTGETTIME}
        )
        && ( gettimeofday() -
            $self->{ $self->{shuttersDev} }->{ASC_Shading_MinMax_Elevation}
            ->{LASTGETTIME} ) < 2
      );
    $self->{ $self->{shuttersDev} }->{ASC_Shading_MinMax_Elevation}
      ->{LASTGETTIME} = int( gettimeofday() );
    my ( $min, $max ) =
      FHEM::Automation::ShuttersControl::Helper::GetAttrValues( $self->{shuttersDev},
        'ASC_Shading_MinMax_Elevation', '25.0:100.0' );

    ### erwartetes Ergebnis
    # MIN:MAX

    $self->{ $self->{shuttersDev} }->{ASC_Shading_MinMax_Elevation}->{minVal} =
      $min;
    $self->{ $self->{shuttersDev} }->{ASC_Shading_MinMax_Elevation}->{maxVal} =
      ( $max ne 'none' ? $max : 100 );

    return $self->{ $self->{shuttersDev} }->{ASC_Shading_MinMax_Elevation}
      ->{minVal};
}

sub getShadingMaxElevation {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }->{ASC_Shading_MinMax_Elevation}
      ->{maxVal}
      if (
        exists(
            $self->{ $self->{shuttersDev} }->{ASC_Shading_MinMax_Elevation}
              ->{LASTGETTIME}
        )
        && ( gettimeofday() -
            $self->{ $self->{shuttersDev} }->{ASC_Shading_MinMax_Elevation}
            ->{LASTGETTIME} ) < 2
      );
    $FHEM::Automation::ShuttersControl::shutters->getShadingMinElevation;

    return $self->{ $self->{shuttersDev} }->{ASC_Shading_MinMax_Elevation}
      ->{maxVal};
}

sub setShadingStateChangeSunnyCloudy {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_Shading_StateChange_SunnyCloudy',
        $attrVal );

    return;
}

sub deleteShadingStateChangeSunny {
    my $self = shift;

    delete $self->{ $self->{shuttersDev} }->{BrightnessAverageArray};

    return;
}

sub getShadingStateChangeSunny {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }
      ->{ASC_Shading_StateChange_SunnyCloudy}->{sunny}
      if (
        exists(
            $self->{ $self->{shuttersDev} }
              ->{ASC_Shading_StateChange_SunnyCloudy}->{LASTGETTIME}
        )
        && ( gettimeofday() -
            $self->{ $self->{shuttersDev} }
            ->{ASC_Shading_StateChange_SunnyCloudy}->{LASTGETTIME} ) < 2
      );
    $self->{ $self->{shuttersDev} }->{ASC_Shading_StateChange_SunnyCloudy}
      ->{LASTGETTIME} = int( gettimeofday() );
    my ( $sunny, $cloudy, $maxBrightnessAverageArrayObjects ) =
      FHEM::Automation::ShuttersControl::Helper::GetAttrValues( $self->{shuttersDev},
        'ASC_Shading_StateChange_SunnyCloudy',
        '35000:20000' );

    ### erwartetes Ergebnis
    # SUNNY:CLOUDY [BrightnessAverage]

    $self->{ $self->{shuttersDev} }->{ASC_Shading_StateChange_SunnyCloudy}
      ->{sunny} = $sunny;
    $self->{ $self->{shuttersDev} }->{ASC_Shading_StateChange_SunnyCloudy}
      ->{cloudy} = $cloudy;
    $self->{ $self->{shuttersDev} }->{BrightnessAverageArray}->{MAXOBJECT} = (
        defined($maxBrightnessAverageArrayObjects)
          && $maxBrightnessAverageArrayObjects ne 'none'
        ? $maxBrightnessAverageArrayObjects
        : 3
    );

    return $self->{ $self->{shuttersDev} }
      ->{ASC_Shading_StateChange_SunnyCloudy}->{sunny};
}

sub getShadingStateChangeCloudy {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }
      ->{ASC_Shading_StateChange_SunnyCloudy}->{cloudy}
      if (
        exists(
            $self->{ $self->{shuttersDev} }
              ->{ASC_Shading_StateChange_SunnyCloudy}->{LASTGETTIME}
        )
        && ( gettimeofday() -
            $self->{ $self->{shuttersDev} }
            ->{ASC_Shading_StateChange_SunnyCloudy}->{LASTGETTIME} ) < 2
      );
    $FHEM::Automation::ShuttersControl::shutters->getShadingStateChangeSunny;

    return $self->{ $self->{shuttersDev} }
      ->{ASC_Shading_StateChange_SunnyCloudy}->{cloudy};
}

sub getMaxBrightnessAverageArrayObjects {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }->{BrightnessAverageArray}
      ->{MAXOBJECT}
      if (
        exists(
            $self->{ $self->{shuttersDev} }
              ->{ASC_Shading_StateChange_SunnyCloudy}->{LASTGETTIME}
        )
        && ( gettimeofday() -
            $self->{ $self->{shuttersDev} }
            ->{ASC_Shading_StateChange_SunnyCloudy}->{LASTGETTIME} ) < 2
      );
    $FHEM::Automation::ShuttersControl::shutters->getShadingStateChangeSunny;

    return $self->{ $self->{shuttersDev} }->{BrightnessAverageArray}
      ->{MAXOBJECT};
}

sub setShadingWaitingPeriod {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_Shading_WaitingPeriod',
        $attrVal );

    return;
}

sub getShadingWaitingPeriod {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Shading_WaitingPeriod', 1200 );
}
### Ende Beschattung
sub setExternalTrigger {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_ExternalTrigger', $attrVal );

    return;
}

sub getExternalTriggerDevice {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}->{device}
      if (
        exists(
            $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}
              ->{LASTGETTIME}
        )
        && ( gettimeofday() -
            $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}
            ->{LASTGETTIME} ) < 2
      );
    $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}->{LASTGETTIME} =
      int( gettimeofday() );
    my ( $device, $reading, $valueActive, $valueInactive, $posActive,
        $posInactive, $valueActive2, $posActive2 )
      = FHEM::Automation::ShuttersControl::Helper::GetAttrValues( $self->{shuttersDev},
        'ASC_ExternalTrigger', 'none' );

    ### erwartetes Ergebnis
# DEVICE:READING VALUEACTIVE:VALUEINACTIVE POSACTIVE:POSINACTIVE VALUEACTIVE2:POSACTIVE2

    $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}->{device} =
      $device;
    $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}->{reading} =
      $reading;
    $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}->{valueactive} =
      $valueActive;
    $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}->{valueinactive} =
      $valueInactive;
    $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}->{posactive} =
      $posActive;
    $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}->{posinactive} =
      (   $posInactive ne 'none'
        ? $posInactive
        : $FHEM::Automation::ShuttersControl::shutters->getLastPos );
    $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}->{valueactive2} =
      $valueActive2;
    $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}->{posactive2} =
      $posActive2;

    return $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}->{device};

}

sub getExternalTriggerReading {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}->{reading}
      if (
        exists(
            $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}
              ->{LASTGETTIME}
        )
        && ( gettimeofday() -
            $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}
            ->{LASTGETTIME} ) < 2
      );
    $FHEM::Automation::ShuttersControl::shutters->getExternalTriggerDevice;

    return $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}->{reading};
}

sub getExternalTriggerValueActive {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}->{valueactive}
      if (
        exists(
            $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}
              ->{LASTGETTIME}
        )
        && ( gettimeofday() -
            $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}
            ->{LASTGETTIME} ) < 2
      );
    $FHEM::Automation::ShuttersControl::shutters->getExternalTriggerDevice;

    return $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}
      ->{valueactive};
}

sub getExternalTriggerValueActive2 {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}
      ->{valueactive2}
      if (
        exists(
            $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}
              ->{LASTGETTIME}
        )
        && ( gettimeofday() -
            $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}
            ->{LASTGETTIME} ) < 2
      );
    $FHEM::Automation::ShuttersControl::shutters->getExternalTriggerDevice;

    return $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}
      ->{valueactive2};
}

sub getExternalTriggerValueInactive {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}
      ->{valueinactive}
      if (
        exists(
            $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}
              ->{LASTGETTIME}
        )
        && ( gettimeofday() -
            $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}
            ->{LASTGETTIME} ) < 2
      );
    $FHEM::Automation::ShuttersControl::shutters->getExternalTriggerDevice;

    return $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}
      ->{valueinactive};
}

sub getExternalTriggerPosActive {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}->{posactive}
      if (
        exists(
            $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}
              ->{LASTGETTIME}
        )
        && ( gettimeofday() -
            $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}
            ->{LASTGETTIME} ) < 2
      );
    $FHEM::Automation::ShuttersControl::shutters->getExternalTriggerDevice;

    return $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}->{posactive};
}

sub getExternalTriggerPosActive2 {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}->{posactive2}
      if (
        exists(
            $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}
              ->{LASTGETTIME}
        )
        && ( gettimeofday() -
            $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}
            ->{LASTGETTIME} ) < 2
      );
    $FHEM::Automation::ShuttersControl::shutters->getExternalTriggerDevice;

    return $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}->{posactive2};
}

sub getExternalTriggerPosInactive {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}->{posinactive}
      if (
        exists(
            $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}
              ->{LASTGETTIME}
        )
        && ( gettimeofday() -
            $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}
            ->{LASTGETTIME} ) < 2
      );
    $FHEM::Automation::ShuttersControl::shutters->getExternalTriggerDevice;

    return $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}
      ->{posinactive};
}

sub setDelay {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_Drive_Delay', $attrVal );

    return;
}

sub getDelay {
    my $self = shift;

    my $val = AttrVal( $self->{shuttersDev}, 'ASC_Drive_Delay', -1 );
    return ( $val =~ m{^\d+$}xms ? $val : -1 );
}

sub setDelayStart {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_Drive_DelayStart', $attrVal );

    return;
}

sub getDelayStart {
    my $self = shift;

    my $val = AttrVal( $self->{shuttersDev}, 'ASC_Drive_DelayStart', -1 );
    return ( ( $val > 0 && $val =~ m{^\d+$}xms ) ? $val : -1 );
}

sub setBlockingTimeAfterManual {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_BlockingTime_afterManual',
        $attrVal );

    return;
}

sub getBlockingTimeAfterManual {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_BlockingTime_afterManual',
        1200 );
}

sub setBlockingTimeBeforNightClose {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_BlockingTime_beforNightClose',
        $attrVal );

    return;
}

sub getBlockingTimeBeforNightClose {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_BlockingTime_beforNightClose',
        3600 );
}

sub setBlockingTimeBeforDayOpen {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_BlockingTime_beforDayOpen',
        $attrVal );

    return;
}

sub getBlockingTimeBeforDayOpen {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_BlockingTime_beforDayOpen',
        3600 );
}

sub setPosCmd {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_Pos_Reading', $attrVal );

    return;
}

sub getPosCmd {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Pos_Reading',
        $FHEM::Automation::ShuttersControl::userAttrList{'ASC_Pos_Reading'}
          [ AttrVal( $self->{shuttersDev}, 'ASC', 1 ) ] );
}

sub setOpenPos {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_Open_Pos', $attrVal );

    return;
}

sub getOpenPos {
    my $self = shift;

    return $FHEM::Automation::ShuttersControl::shutters->_getPosition(
        'ASC_Open_Pos', 'ASC_Open_Pos:0,10,20,30,40,50,60,70,80,90,100' );
}

sub getOpenPositionAssignment {
    my $self = shift;

    return
      $FHEM::Automation::ShuttersControl::shutters->_getPositionAssignment(
        'ASC_Open_Pos', 'getOpenPos' );
}

sub setVentilatePos {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_Ventilate_Pos', $attrVal );

    return;
}

sub getVentilatePos {
    my $self = shift;

    return $FHEM::Automation::ShuttersControl::shutters->_getPosition(
        'ASC_Ventilate_Pos',
        'ASC_Ventilate_Pos:10,20,30,40,50,60,70,80,90,100' );
}

sub getVentilatePositionAssignment {
    my $self = shift;

    return
      $FHEM::Automation::ShuttersControl::shutters->_getPositionAssignment(
        'ASC_Ventilate_Pos', 'getVentilatePos' );
}

sub setVentilatePosAfterDayClosed {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_WindowRec_PosAfterDayClosed',
        $attrVal );

    return;
}

sub getVentilatePosAfterDayClosed {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_WindowRec_PosAfterDayClosed',
        'open' );
}

sub setClosedPos {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_Closed_Pos', $attrVal );

    return;
}

sub getClosedPos {
    my $self = shift;

    return $FHEM::Automation::ShuttersControl::shutters->_getPosition(
        'ASC_Closed_Pos', 'ASC_Closed_Pos:0,10,20,30,40,50,60,70,80,90,100' );
}

sub getClosedPositionAssignment {
    my $self = shift;

    return
      $FHEM::Automation::ShuttersControl::shutters->_getPositionAssignment(
        'ASC_Closed_Pos', 'getClosedPos' );
}

sub setSleepPos {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_Sleep_Pos', $attrVal );

    return;
}

sub getSleepPos {
    my $self = shift;

    return $FHEM::Automation::ShuttersControl::shutters->_getPosition(
        'ASC_Sleep_Pos', 'ASC_Sleep_Pos:0,10,20,30,40,50,60,70,80,90,100' );
}

sub getSleepPositionAssignment {
    my $self = shift;

    return
      $FHEM::Automation::ShuttersControl::shutters->_getPositionAssignment(
        'ASC_Sleep_Pos', 'getSleepPos' );
}

sub setVentilateOpen {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_Ventilate_Window_Open',
        $attrVal );

    return;
}

sub getVentilateOpen {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Ventilate_Window_Open', 'on' );
}

sub setComfortOpenPos {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_ComfortOpen_Pos', $attrVal );

    return;
}

sub getComfortOpenPos {
    my $self = shift;

    return $FHEM::Automation::ShuttersControl::shutters->_getPosition(
        'ASC_ComfortOpen_Pos',
        'ASC_ComfortOpen_Pos:0,10,20,30,40,50,60,70,80,90,100' );
}

sub getComfortOpenPositionAssignment {
    my $self = shift;

    return
      $FHEM::Automation::ShuttersControl::shutters->_getPositionAssignment(
        'ASC_ComfortOpen_Pos', 'getComfortOpenPos' );
}

sub setPartyMode {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_Partymode', $attrVal );

    return;
}

sub getPartyMode {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Partymode', 'off' );
}

sub setRoommates {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_Roommate_Device', $attrVal );

    return;
}

sub getRoommates {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Roommate_Device', 'none' );
}

sub setRoommatesReading {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_Roommate_Reading', $attrVal );

    return;
}

sub getRoommatesReading {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Roommate_Reading', 'state' );
}

sub getWindPos {
    my $self = shift;

    my $name = $self->{name};

    return $self->{ $self->{shuttersDev} }->{ASC_WindParameters}->{closedPos}
      if (
        exists(
            $self->{ $self->{shuttersDev} }->{ASC_WindParameters}->{LASTGETTIME}
        )
        && ( gettimeofday() -
            $self->{ $self->{shuttersDev} }->{ASC_WindParameters}->{LASTGETTIME}
        ) < 2
      );
    $FHEM::Automation::ShuttersControl::shutters->getWindMax;

    return $self->{ $self->{shuttersDev} }->{ASC_WindParameters}->{closedPos};
}

sub getWindMax {
    my $self = shift;

    my $name = $self->{name};

    return $self->{ $self->{shuttersDev} }->{ASC_WindParameters}->{triggermax}
      if (
        exists(
            $self->{ $self->{shuttersDev} }->{ASC_WindParameters}->{LASTGETTIME}
        )
        && ( gettimeofday() -
            $self->{ $self->{shuttersDev} }->{ASC_WindParameters}->{LASTGETTIME}
        ) < 2
      );
    $self->{ $self->{shuttersDev} }->{ASC_WindParameters}->{LASTGETTIME} =
      int( gettimeofday() );
    my ( $max, $hyst, $pos ) =
      FHEM::Automation::ShuttersControl::Helper::GetAttrValues( $self->{shuttersDev},
        'ASC_WindParameters', '50:20' );

    ## Erwartetes Ergebnis
    # max:hyst pos

    $self->{ $self->{shuttersDev} }->{ASC_WindParameters}->{triggermax} = $max;
    $self->{ $self->{shuttersDev} }->{ASC_WindParameters}->{triggerhyst} =
      ( $hyst ne 'none' ? $max - $hyst : $max - 20 );
    $self->{ $self->{shuttersDev} }->{ASC_WindParameters}->{closedPos} =
      (   $pos ne 'none'
        ? $pos
        : $FHEM::Automation::ShuttersControl::shutters->getOpenPos );

    return $self->{ $self->{shuttersDev} }->{ASC_WindParameters}->{triggermax};
}

sub setWindParameters {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_WindParameters', $attrVal );

    return;
}

sub getWindMin {
    my $self = shift;

    my $name = $self->{name};

    return $self->{ $self->{shuttersDev} }->{ASC_WindParameters}->{triggerhyst}
      if (
        exists(
            $self->{ $self->{shuttersDev} }->{ASC_WindParameters}->{LASTGETTIME}
        )
        && ( gettimeofday() -
            $self->{ $self->{shuttersDev} }->{ASC_WindParameters}->{LASTGETTIME}
        ) < 2
      );
    $FHEM::Automation::ShuttersControl::shutters->getWindMax;

    return $self->{ $self->{shuttersDev} }->{ASC_WindParameters}->{triggerhyst};
}

sub setWindProtection {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_WindProtection', $attrVal );

    return;
}

sub getWindProtection {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_WindProtection', 'off' );
}

sub setRainProtection {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_RainProtection', $attrVal );

    return;
}

sub getRainProtection {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_RainProtection', 'off' );
}

sub setModeUp {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_Mode_Up', $attrVal );

    return;
}

sub getModeUp {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Mode_Up', 'always' );
}

sub setModeDown {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_Mode_Down', $attrVal );

    return;
}

sub getModeDown {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Mode_Down', 'always' );
}

sub setLockOut {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_LockOut', $attrVal );

    return;
}

sub getLockOut {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_LockOut', 'off' );
}

sub setLockOutCmd {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_LockOut_Cmd', $attrVal );

    return;
}

sub getLockOutCmd {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_LockOut_Cmd', 'none' );
}

sub setAntiFreeze {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_Antifreeze', $attrVal );

    return;
}

sub getAntiFreeze {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Antifreeze', 'off' );
}

sub setAutoAstroModeMorning {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_AutoAstroModeMorning', $attrVal );

    return;
}

sub getAutoAstroModeMorning {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_AutoAstroModeMorning', 'none' );
}

sub setAutoAstroModeEvening {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_AutoAstroModeEvening', $attrVal );

    return;
}

sub getAutoAstroModeEvening {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_AutoAstroModeEvening', 'none' );
}

sub setAutoAstroModeMorningHorizon {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_AutoAstroModeMorningHorizon',
        $attrVal );

    return;
}

sub getAutoAstroModeMorningHorizon {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_AutoAstroModeMorningHorizon',
        0 );
}

sub setAutoAstroModeEveningHorizon {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_AutoAstroModeEveningHorizon',
        $attrVal );

    return;
}

sub getAutoAstroModeEveningHorizon {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_AutoAstroModeEveningHorizon',
        0 );
}

sub setUp {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_Up', $attrVal );

    return;
}

sub getUp {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Up', 'astro' );
}

sub setDown {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_Down', $attrVal );

    return;
}

sub getDown {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Down', 'astro' );
}

sub setShadingBetweenTheTime {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_Shading_BetweenTheTime', $attrVal );

    return;
}

sub getShadingBetweenTheTime {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Shading_BetweenTheTime', '00:00-24:00' );
}

sub setTimeUpEarly {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_Time_Up_Early', $attrVal );

    return;
}

sub getTimeUpEarly {
    my $self = shift;

    my $val = AttrVal( $self->{shuttersDev}, 'ASC_Time_Up_Early', '05:00' );

    if ( defined( PerlCodeCheck($val) ) ) {
        $val = PerlCodeCheck($val);
    }

    return (
          $val =~ m{^(?:[01]?\d|2[0-3]):(?:[0-5]\d)(:(?:[0-5]\d))?$}xms
        ? $val
        : '05:00'
    );
}

sub setTimeUpLate {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_Time_Up_Late', $attrVal );

    return;
}

sub getTimeUpLate {
    my $self = shift;

    my $val = AttrVal( $self->{shuttersDev}, 'ASC_Time_Up_Late', '08:30' );

    if ( defined( PerlCodeCheck($val) ) ) {
        $val = PerlCodeCheck($val);
    }

    return (
          $val =~ m{^(?:[01]?\d|2[0-3]):(?:[0-5]\d)(:(?:[0-5]\d))?$}xms
        ? $val
        : '08:30'
    );
}

sub setTimeDownEarly {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_Time_Down_Early', $attrVal );

    return;
}

sub getTimeDownEarly {
    my $self = shift;

    my $val = AttrVal( $self->{shuttersDev}, 'ASC_Time_Down_Early', '16:00' );

    if ( defined( PerlCodeCheck($val) ) ) {
        $val = PerlCodeCheck($val);
    }

    return (
          $val =~ m{^(?:[01]?\d|2[0-3]):(?:[0-5]\d)(:(?:[0-5]\d))?$}xms
        ? $val
        : '16:00'
    );
}

sub setTimeDownLate {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_Time_Down_Late', $attrVal );

    return;
}

sub getTimeDownLate {
    my $self = shift;

    my $val = AttrVal( $self->{shuttersDev}, 'ASC_Time_Down_Late', '22:00' );

    if ( defined( PerlCodeCheck($val) ) ) {
        $val = PerlCodeCheck($val);
    }

    return (
          $val =~ m{^(?:[01]?\d|2[0-3]):(?:[0-5]\d)(:(?:[0-5]\d))?$}xms
        ? $val
        : '22:00'
    );
}

sub setTimeUpWeHoliday {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_Time_Up_WE_Holiday', $attrVal );

    return;
}

sub getTimeUpWeHoliday {
    my $self = shift;

    my $val =
      AttrVal( $self->{shuttersDev}, 'ASC_Time_Up_WE_Holiday', '01:25' );

    if ( defined( PerlCodeCheck($val) ) ) {
        $val = PerlCodeCheck($val);
    }

    return (
          $val =~ m{^(?:[01]?\d|2[0-3]):(?:[0-5]\d)(:(?:[0-5]\d))?$}xms
        ? $val
        : '01:25'
    );
}

sub getBrightnessMinVal {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }->{ASC_BrightnessSensor}->{triggermin}
      if (
        exists(
            $self->{ $self->{shuttersDev} }->{ASC_BrightnessSensor}
              ->{LASTGETTIME}
        )
        && ( gettimeofday() -
            $self->{ $self->{shuttersDev} }->{ASC_BrightnessSensor}
            ->{LASTGETTIME} ) < 2
      );
    $FHEM::Automation::ShuttersControl::shutters->_getBrightnessSensor;

    return $self->{ $self->{shuttersDev} }->{ASC_BrightnessSensor}
      ->{triggermin};
}

sub getBrightnessMaxVal {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }->{ASC_BrightnessSensor}->{triggermax}
      if (
        exists(
            $self->{ $self->{shuttersDev} }->{ASC_BrightnessSensor}
              ->{LASTGETTIME}
        )
        && ( gettimeofday() -
            $self->{ $self->{shuttersDev} }->{ASC_BrightnessSensor}
            ->{LASTGETTIME} ) < 2
      );
    $FHEM::Automation::ShuttersControl::shutters->_getBrightnessSensor;

    return $self->{ $self->{shuttersDev} }->{ASC_BrightnessSensor}
      ->{triggermax};
}

sub setDriveUpMaxDuration {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_DriveUpMaxDuration', $attrVal );

    return;
}

sub getDriveUpMaxDuration {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_DriveUpMaxDuration', 60 );
}

1;
