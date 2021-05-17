###############################################################################
#
# Developed with Kate
#
#  (c) 2018-2021 Copyright: Marko Oldenburg (fhemdevelopment@cooltux.net)
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

## unserer packagename
package FHEM::Automation::ShuttersControl::Rainprotection;

use strict;
use warnings;
use utf8;

use FHEM::Automation::ShuttersControl::Helper qw (:ALL);

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(
  RainProcessing
);
our %EXPORT_TAGS = (
    ALL => [
        qw(
          RainProcessing
          )
    ],
);


sub RainProcessing {
    my ( $hash, $val, $triggerMax, $triggerMin ) = @_;
    
    my $rainClosedPos = $FHEM::Automation::ShuttersControl::ascDev
          ->getRainSensorShuttersClosedPos;

    for my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
        $FHEM::Automation::ShuttersControl::shutters->setShuttersDev(
            $shuttersDev);

        next
          if (
            $FHEM::Automation::ShuttersControl::shutters->getRainProtection eq
            'off' );

        if (   $val > $triggerMax
            && $FHEM::Automation::ShuttersControl::shutters->getStatus !=
            $rainClosedPos
            && $FHEM::Automation::ShuttersControl::shutters
            ->getRainProtectionStatus eq 'unprotected' )
        {
            _RainProtected();
        }
        elsif ( ( $val == 0 || $val < $triggerMin )
            && $FHEM::Automation::ShuttersControl::shutters->getStatus ==
            $rainClosedPos
            && IsAfterShuttersManualBlocking($shuttersDev)
            && $FHEM::Automation::ShuttersControl::shutters
            ->getRainProtectionStatus eq 'protected' )
        {
            my %funcHash = (
                shuttersdevice => $shuttersDev,
            );

            ::InternalTimer( ::gettimeofday() + $FHEM::Automation::ShuttersControl::ascDev->getRainWaitingTime
                , \&_RainUnprotected
                , \%funcHash );
        }
    }

    return;
}

### es muss noch beobachtet werden ob die Auswahl des Rollos welches bearbeitet werden soll bestehen bleibt oder mit in die neuen Funktionen übergeben werden muss
sub _RainProtected {
    $FHEM::Automation::ShuttersControl::shutters->setLastDrive(
            'rain protected');
        $FHEM::Automation::ShuttersControl::shutters->setDriveCmd(
            $FHEM::Automation::ShuttersControl::ascDev
          ->getRainSensorShuttersClosedPos);
        $FHEM::Automation::ShuttersControl::shutters
            ->setRainProtectionStatus('protected');
}

sub _RainUnprotected {
    my $h = shift;
    
    my $shuttersDev = $h->{shuttersdevice};
    $FHEM::Automation::ShuttersControl::shutters->setShuttersDev(
            $shuttersDev);

    $FHEM::Automation::ShuttersControl::shutters->setLastDrive(
            'rain un-protected');
        $FHEM::Automation::ShuttersControl::shutters->setDriveCmd(
            (
                    $FHEM::Automation::ShuttersControl::shutters->getIsDay
                ? $FHEM::Automation::ShuttersControl::shutters->getLastPos
                : (
                    $FHEM::Automation::ShuttersControl::shutters
                        ->getPrivacyDownStatus == 2
                    ? $FHEM::Automation::ShuttersControl::shutters
                        ->getPrivacyDownPos
                    : $FHEM::Automation::ShuttersControl::shutters
                        ->getClosedPos
                )
            )
        );

        $FHEM::Automation::ShuttersControl::shutters
            ->setRainProtectionStatus('unprotected');
}




1;
