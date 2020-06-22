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

## Subklasse Readings ##
package FHEM::Automation::ShuttersControl::Dev::Readings;

use strict;
use warnings;
use utf8;

use GPUtils qw(GP_Import);

## Import der FHEM Funktionen
BEGIN {
    GP_Import(
        qw(
          readingsSingleUpdate
          ReadingsVal
          defs)
    );
}

sub setDelayCmdReading {
    my $self = shift;

    my $name = $self->{name};
    my $hash = $defs{$name};

    readingsSingleUpdate(
        $hash,
        $FHEM::Automation::ShuttersControl::shutters->getShuttersDev
          . '_lastDelayPosValue',
        $FHEM::Automation::ShuttersControl::shutters->getDelayCmd,
        1
    );
    return;
}

sub setStateReading {
    my $self  = shift;
    my $value = shift;

    my $name = $self->{name};
    my $hash = $defs{$name};

    readingsSingleUpdate(
        $hash, 'state',
        (
            defined($value)
            ? $value
            : $FHEM::Automation::ShuttersControl::shutters->getLastDrive
        ),
        1
    );
    return;
}

sub setPosReading {
    my $self = shift;

    my $name = $self->{name};
    my $hash = $defs{$name};

    readingsSingleUpdate(
        $hash,
        $FHEM::Automation::ShuttersControl::shutters->getShuttersDev
          . '_PosValue',
        $FHEM::Automation::ShuttersControl::shutters->getStatus,
        1
    );
    return;
}

sub setLastPosReading {
    my $self = shift;

    my $name = $self->{name};
    my $hash = $defs{$name};

    readingsSingleUpdate(
        $hash,
        $FHEM::Automation::ShuttersControl::shutters->getShuttersDev
          . '_lastPosValue',
        $FHEM::Automation::ShuttersControl::shutters->getLastPos,
        1
    );
    return;
}

sub getPartyMode {
    my $self = shift;

    my $name = $self->{name};

    return ReadingsVal( $name, 'partyMode', 'off' );
}

sub getHardLockOut {
    my $self = shift;

    my $name = $self->{name};

    return ReadingsVal( $name, 'hardLockOut', 'none' );
}

sub getSunriseTimeWeHoliday {
    my $self = shift;

    my $name = $self->{name};

    return ReadingsVal( $name, 'sunriseTimeWeHoliday', 'none' );
}

sub getMonitoredDevs {
    my $self = shift;

    my $name = $self->{name};

    $self->{monitoredDevs} = ReadingsVal( $name, '.monitoredDevs', 'none' );
    return $self->{monitoredDevs};
}

sub getOutTemp {
    my $self = shift;

    return ReadingsVal(
        $FHEM::Automation::ShuttersControl::ascDev->_getTempSensor,
        $FHEM::Automation::ShuttersControl::ascDev->getTempSensorReading,
        -100 );
}

sub getResidentsStatus {
    my $self = shift;

    my $val =
      ReadingsVal( $FHEM::Automation::ShuttersControl::ascDev->_getResidentsDev,
        $FHEM::Automation::ShuttersControl::ascDev->getResidentsReading,
        'none' );

    if ( $val =~ m{^(?:(.+)_)?(.+)$}xms ) {
        return ( $1, $2 ) if (wantarray);
        return $1 && $1 eq 'pet' ? 'absent' : $2;
    }
    elsif (
        ReadingsVal(
            $FHEM::Automation::ShuttersControl::ascDev->_getResidentsDev,
            'homealoneType', '-' ) eq 'PET'
      )
    {
        return ( 'pet', 'absent' ) if (wantarray);
        return 'absent';
    }
    else {
        return ( undef, $val ) if (wantarray);
        return $val;
    }
}

sub getResidentsLastStatus {
    my $self = shift;

    my $val =
      ReadingsVal( $FHEM::Automation::ShuttersControl::ascDev->_getResidentsDev,
        'lastState', 'none' );

    if ( $val =~ m{^(?:(.+)_)?(.+)$}xms ) {
        return ( $1, $2 ) if (wantarray);
        return $1 && $1 eq 'pet' ? 'absent' : $2;
    }
    elsif (
        ReadingsVal(
            $FHEM::Automation::ShuttersControl::ascDev->_getResidentsDev,
            'lastHomealoneType', '-' ) eq 'PET'
      )
    {
        return ( 'pet', 'absent' ) if (wantarray);
        return 'absent';
    }
    else {
        return ( undef, $val ) if (wantarray);
        return $val;
    }
}

sub getAutoShuttersControlShading {
    my $self = shift;

    my $name = $self->{name};

    return ReadingsVal( $name, 'controlShading', 'none' );
}

sub getSelfDefense {
    my $self = shift;

    my $name = $self->{name};

    return ReadingsVal( $name, 'selfDefense', 'none' );
}

sub getAzimuth {
    my $self = shift;

    my $azimuth;

    $azimuth = ReadingsVal(
        $FHEM::Automation::ShuttersControl::ascDev->_getTwilightDevice,
        'azimuth', -1 )
      if (
        $defs{ $FHEM::Automation::ShuttersControl::ascDev->_getTwilightDevice }
        ->{TYPE} eq 'Twilight' );
    $azimuth = ReadingsVal(
        $FHEM::Automation::ShuttersControl::ascDev->_getTwilightDevice,
        'SunAz', -1 )
      if (
        $defs{ $FHEM::Automation::ShuttersControl::ascDev->_getTwilightDevice }
        ->{TYPE} eq 'Astro' );

    return $azimuth;
}

sub getElevation {
    my $self = shift;

    my $elevation;

    $elevation = ReadingsVal(
        $FHEM::Automation::ShuttersControl::ascDev->_getTwilightDevice,
        'elevation', -1 )
      if (
        $defs{ $FHEM::Automation::ShuttersControl::ascDev->_getTwilightDevice }
        ->{TYPE} eq 'Twilight' );
    $elevation = ReadingsVal(
        $FHEM::Automation::ShuttersControl::ascDev->_getTwilightDevice,
        'SunAlt', -1 )
      if (
        $defs{ $FHEM::Automation::ShuttersControl::ascDev->_getTwilightDevice }
        ->{TYPE} eq 'Astro' );

    return $elevation;
}

sub getASCenable {
    my $self = shift;

    my $name = $self->{name};

    return ReadingsVal( $name, 'ascEnable', 'none' );
}

1;
