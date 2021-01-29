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

## Subklasse Attr von Klasse ASC_Window ##
package FHEM::Automation::ShuttersControl::Window::Attr;

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

sub setSubTyp {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_WindowRec_subType', $attrVal );

    return;
}

sub getSubTyp {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_WindowRec_subType', 'twostate' );
}

sub setWinDev {
    my $self    = shift;
    my $attrVal = shift;

    _setAttributs( $self->{shuttersDev}, 'ASC_WindowRec', $attrVal );

    return;
}

sub _getWinDev {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }->{ASC_WindowRec}->{device}
      if (
        exists(
            $self->{ $self->{shuttersDev} }->{ASC_WindowRec}->{LASTGETTIME}
        )
        && ( gettimeofday() -
            $self->{ $self->{shuttersDev} }->{ASC_WindowRec}->{LASTGETTIME} ) <
        2
      );
    $self->{ $self->{shuttersDev} }->{ASC_WindowRec}->{LASTGETTIME} =
      int( gettimeofday() );
    my ( $device, $reading ) =
      FHEM::Automation::ShuttersControl::Helper::GetAttrValues( $self->{shuttersDev},
        'ASC_WindowRec', 'none' );

    ### erwartetes Ergebnis
    # DEVICE:READING VALUEACTIVE:VALUEINACTIVE POSACTIVE:POSINACTIVE

    $self->{ $self->{shuttersDev} }->{ASC_WindowRec}->{device} =
      $device;
    $self->{ $self->{shuttersDev} }->{ASC_WindowRec}->{reading} =
      ( $reading ne 'none' ? $reading : 'state' );

    return $self->{ $self->{shuttersDev} }->{ASC_WindowRec}->{device};
}

sub getWinDevReading {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }->{ASC_WindowRec}->{reading}
      if (
        exists(
            $self->{ $self->{shuttersDev} }->{ASC_WindowRec}->{LASTGETTIME}
        )
        && ( gettimeofday() -
            $self->{ $self->{shuttersDev} }->{ASC_WindowRec}->{LASTGETTIME} ) <
        2
      );
    $FHEM::Automation::ShuttersControl::shutters->_getWinDev;

    return $self->{ $self->{shuttersDev} }->{ASC_WindowRec}->{reading};
}

1;
