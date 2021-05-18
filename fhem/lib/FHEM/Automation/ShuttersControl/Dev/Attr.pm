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

## Subklasse Attr ##
package FHEM::Automation::ShuttersControl::Dev::Attr;

use strict;
use warnings;
use utf8;

use GPUtils qw(GP_Import);

## Import der FHEM Funktionen
BEGIN {
    GP_Import(
        qw(
          AttrVal
          gettimeofday)
    );
}

sub getShuttersOffset {
    my $self = shift;

    my $name = $self->{name};

    return AttrVal( $name, 'ASC_shuttersDriveDelay', -1 );
}

sub getBrightnessMinVal {
    my $self = shift;

    my $name = $self->{name};

    return $self->{ASC_brightness}->{triggermin}
      if ( exists( $self->{ASC_brightness}->{LASTGETTIME} )
        && ( gettimeofday() - $self->{ASC_brightness}->{LASTGETTIME} ) < 2 );
    $FHEM::Automation::ShuttersControl::ascDev->getBrightnessMaxVal;

    return $self->{ASC_brightness}->{triggermin};
}

sub getBrightnessMaxVal {
    my $self = shift;

    my $name = $self->{name};

    return $self->{ASC_brightness}->{triggermax}
      if ( exists( $self->{ASC_brightness}->{LASTGETTIME} )
        && ( gettimeofday() - $self->{ASC_brightness}->{LASTGETTIME} ) < 2 );
    $self->{ASC_brightness}->{LASTGETTIME} = int( gettimeofday() );

    my ( $triggermax, $triggermin ) =
      FHEM::Automation::ShuttersControl::Helper::GetAttrValues( $name,
        'ASC_brightnessDriveUpDown', '800:500' );

    ## erwartetes Ergebnis
    # max:min

    $self->{ASC_brightness}->{triggermin} = $triggermin;
    $self->{ASC_brightness}->{triggermax} = $triggermax;

    return $self->{ASC_brightness}->{triggermax};
}

sub _getTwilightDevice {
    my $self = shift;

    my $name = $self->{name};

    return AttrVal( $name, 'ASC_twilightDevice', 'none' );
}

sub getAutoAstroModeEvening {
    my $self = shift;

    my $name = $self->{name};

    return AttrVal( $name, 'ASC_autoAstroModeEvening', 'REAL' );
}

sub getAutoAstroModeEveningHorizon {
    my $self = shift;

    my $name = $self->{name};

    return AttrVal( $name, 'ASC_autoAstroModeEveningHorizon', 0 );
}

sub getAutoAstroModeMorning {
    my $self = shift;

    my $name = $self->{name};

    return AttrVal( $name, 'ASC_autoAstroModeMorning', 'REAL' );
}

sub getAutoAstroModeMorningHorizon {
    my $self = shift;

    my $name = $self->{name};

    return AttrVal( $name, 'ASC_autoAstroModeMorningHorizon', 0 );
}

sub getAutoShuttersControlMorning {
    my $self = shift;

    my $name = $self->{name};

    return AttrVal( $name, 'ASC_autoShuttersControlMorning', 'on' );
}

sub getAutoShuttersControlEvening {
    my $self = shift;

    my $name = $self->{name};

    return AttrVal( $name, 'ASC_autoShuttersControlEvening', 'on' );
}

sub getAutoShuttersControlComfort {
    my $self = shift;

    my $name = $self->{name};

    return AttrVal( $name, 'ASC_autoShuttersControlComfort', 'off' );
}

sub getFreezeTemp {
    my $self = shift;

    my $name = $self->{name};

    return AttrVal( $name, 'ASC_freezeTemp', 3 );
}

sub getSlatDriveCmdInverse {
    my $self = shift;

    my $name = $self->{name};

    return AttrVal( $name, 'ASC_slatDriveCmdInverse', 0 );
}

sub _getTempSensor {
    my $self = shift;

    my $name = $self->{name};

    return $self->{ASC_tempSensor}->{device}
      if ( exists( $self->{ASC_tempSensor}->{LASTGETTIME} )
        && ( gettimeofday() - $self->{ASC_tempSensor}->{LASTGETTIME} ) < 2 );
    $self->{ASC_tempSensor}->{LASTGETTIME} = int( gettimeofday() );
    my ( $device, $reading ) =
      FHEM::Automation::ShuttersControl::Helper::GetAttrValues( $name, 'ASC_tempSensor',
        'none' );

    ## erwartetes Ergebnis
    # DEVICE:READING
    $self->{ASC_tempSensor}->{device} = $device;
    $self->{ASC_tempSensor}->{reading} =
      ( $reading ne 'none' ? $reading : 'temperature' );

    return $self->{ASC_tempSensor}->{device};
}

sub getTempSensorReading {
    my $self = shift;

    my $name = $self->{name};

    return $self->{ASC_tempSensor}->{reading}
      if ( exists( $self->{ASC_tempSensor}->{LASTGETTIME} )
        && ( gettimeofday() - $self->{ASC_tempSensor}->{LASTGETTIME} ) < 2 );
    $FHEM::Automation::ShuttersControl::ascDev->_getTempSensor;
    return $self->{ASC_tempSensor}->{reading};
}

sub _getResidentsDev {
    my $self = shift;

    my $name = $self->{name};

    return $self->{ASC_residentsDev}->{device}
      if ( exists( $self->{ASC_residentsDev}->{LASTGETTIME} )
        && ( gettimeofday() - $self->{ASC_residentsDev}->{LASTGETTIME} ) < 2 );
    $self->{ASC_residentsDev}->{LASTGETTIME} = int( gettimeofday() );
    my ( $device, $reading ) =
      FHEM::Automation::ShuttersControl::Helper::GetAttrValues( $name,
        'ASC_residentsDev', 'none' );

    $self->{ASC_residentsDev}->{device} = $device;
    $self->{ASC_residentsDev}->{reading} =
      ( $reading ne 'none' ? $reading : 'state' );

    return $self->{ASC_residentsDev}->{device};
}

sub getResidentsReading {
    my $self = shift;

    my $name = $self->{name};

    return $self->{ASC_residentsDev}->{reading}
      if ( exists( $self->{ASC_residentsDev}->{LASTGETTIME} )
        && ( gettimeofday() - $self->{ASC_residentsDev}->{LASTGETTIME} ) < 2 );
    $FHEM::Automation::ShuttersControl::ascDev->_getResidentsDev;
    return $self->{ASC_residentsDev}->{reading};
}

sub _getRainSensor {
    my $self = shift;

    my $name = $self->{name};

    return $self->{ASC_rainSensor}->{device}
      if ( exists( $self->{ASC_rainSensor}->{LASTGETTIME} )
        && ( gettimeofday() - $self->{ASC_rainSensor}->{LASTGETTIME} ) < 2 );
    $self->{ASC_rainSensor}->{LASTGETTIME} = int( gettimeofday() );
    my ( $device, $reading, $max, $hyst, $pos, $wait ) =
      FHEM::Automation::ShuttersControl::Helper::GetAttrValues( $name, 'ASC_rainSensor',
        'none' );

    ## erwartetes Ergebnis
    # DEVICE:READING MAX:HYST

    return $device if ( $device eq 'none' );
    $self->{ASC_rainSensor}->{device} = $device;
    $self->{ASC_rainSensor}->{reading} =
      ( $reading ne 'none' ? $reading : 'rain' );
    $self->{ASC_rainSensor}->{triggermax} = (
         (   $max ne 'none'
          && $max =~ m{\A(-?\d+(\.\d+)?)\z}xms )
        ? $max
        : 1000 );

    $self->{ASC_rainSensor}->{triggerhyst} = (
          $hyst ne 'none'
        ? $self->{ASC_rainSensor}->{triggermax} - $hyst
        : ( $self->{ASC_rainSensor}->{triggermax} * 0 )
    );

    $self->{ASC_rainSensor}->{shuttersClosedPos} =
      (   $pos ne 'none'
        ? $pos
        : $FHEM::Automation::ShuttersControl::shutters->getClosedPos );
    $self->{ASC_rainSensor}->{waitingTime} =
      ( $wait ne 'none' ? $wait : 0 );

    return $self->{ASC_rainSensor}->{device};
}

sub getRainSensorReading {
    my $self = shift;

    my $name = $self->{name};

    return $self->{ASC_rainSensor}->{reading}
      if ( exists( $self->{ASC_rainSensor}->{LASTGETTIME} )
        && ( gettimeofday() - $self->{ASC_rainSensor}->{LASTGETTIME} ) < 2 );
    $FHEM::Automation::ShuttersControl::ascDev->_getRainSensor;
    return $self->{ASC_rainSensor}->{reading};
}

sub getRainTriggerMax {
    my $self = shift;

    my $name = $self->{name};

    return $self->{ASC_rainSensor}->{triggermax}
      if ( exists( $self->{ASC_rainSensor}->{LASTGETTIME} )
        && ( gettimeofday() - $self->{ASC_rainSensor}->{LASTGETTIME} ) < 2 );
    $FHEM::Automation::ShuttersControl::ascDev->_getRainSensor;
    return $self->{ASC_rainSensor}->{triggermax};
}

sub getRainTriggerMin {
    my $self = shift;

    my $name = $self->{name};

    return $self->{ASC_rainSensor}->{triggerhyst}
      if ( exists( $self->{ASC_rainSensor}->{LASTGETTIME} )
        && ( gettimeofday() - $self->{ASC_rainSensor}->{LASTGETTIME} ) < 2 );
    $FHEM::Automation::ShuttersControl::ascDev->_getRainSensor;
    return $self->{ASC_rainSensor}->{triggerhyst};
}

sub getRainSensorShuttersClosedPos {
    my $self = shift;

    my $name = $self->{name};

    return $self->{ASC_rainSensor}->{shuttersClosedPos}
      if ( exists( $self->{ASC_rainSensor}->{LASTGETTIME} )
        && ( gettimeofday() - $self->{ASC_rainSensor}->{LASTGETTIME} ) < 2 );
    $FHEM::Automation::ShuttersControl::ascDev->_getRainSensor;
    return $self->{ASC_rainSensor}->{shuttersClosedPos};
}

sub getRainWaitingTime {
    my $self = shift;

    my $name = $self->{name};

    return $self->{ASC_rainSensor}->{waitingTime}
      if ( exists( $self->{ASC_rainSensor}->{LASTGETTIME} )
        && ( gettimeofday() - $self->{ASC_rainSensor}->{LASTGETTIME} ) < 2 );
    $FHEM::Automation::ShuttersControl::ascDev->_getRainSensor;
    return $self->{ASC_rainSensor}->{waitingTime};
}

sub _getWindSensor {
    my $self = shift;

    my $name = $self->{name};

    return $self->{ASC_windSensor}->{device}
      if ( exists( $self->{ASC_windSensor}->{LASTGETTIME} )
        && ( gettimeofday() - $self->{ASC_windSensor}->{LASTGETTIME} ) < 2 );
    $self->{ASC_windSensor}->{LASTGETTIME} = int( gettimeofday() );
    my ( $device, $reading ) =
      FHEM::Automation::ShuttersControl::Helper::GetAttrValues( $name, 'ASC_windSensor',
        'none' );

    return $device if ( $device eq 'none' );
    $self->{ASC_windSensor}->{device} = $device;
    $self->{ASC_windSensor}->{reading} =
      ( $reading ne 'none' ? $reading : 'wind' );

    return $self->{ASC_windSensor}->{device};
}

sub getWindSensorReading {
    my $self = shift;

    my $name = $self->{name};

    return $self->{ASC_windSensor}->{reading}
      if ( exists( $self->{ASC_windSensor}->{LASTGETTIME} )
        && ( gettimeofday() - $self->{ASC_windSensor}->{LASTGETTIME} ) < 2 );
    $FHEM::Automation::ShuttersControl::ascDev->_getWindSensor;
    return (
        defined( $self->{ASC_windSensor}->{reading} )
        ? $self->{ASC_windSensor}->{reading}
        : 'wind'
    );
}

sub getBlockAscDrivesAfterManual {
    my $self = shift;

    my $name = $self->{name};

    return AttrVal( $name, 'ASC_blockAscDrivesAfterManual', 0 );
}

sub getAdvDate {
    my $self = shift;

    my $name = $self->{name};

    return AttrVal( $name, 'ASC_advDate', 'FirstAdvent' );
}




1;
