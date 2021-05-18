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

######################################
######################################
########## Begin der Klassendeklarierungen für OOP (Objektorientierte Programmierung) #########################
## Klasse Rolläden (Shutters) und die Subklassen Attr und Readings ##
## desweiteren wird noch die Klasse ASC_Roommate mit eingebunden

package FHEM::Automation::ShuttersControl::Shutters;

use FHEM::Automation::ShuttersControl::Shutters::Readings;
use FHEM::Automation::ShuttersControl::Shutters::Attr;
use FHEM::Automation::ShuttersControl::Roommate;
use FHEM::Automation::ShuttersControl::Window;

our @ISA =
  qw(FHEM::Automation::ShuttersControl::Shutters::Readings FHEM::Automation::ShuttersControl::Shutters::Attr FHEM::Automation::ShuttersControl::Roommate FHEM::Automation::ShuttersControl::Window);

use strict;
use warnings;
use utf8;

sub new {
    my $class = shift;
    my $self  = {
        shuttersDev => undef,
        defaultarg  => undef,
        roommate    => undef,
    };

    bless $self, $class;
    return $self;
}

sub setShuttersDev {
    my $self        = shift;
    my $shuttersDev = shift;

    $self->{shuttersDev} = $shuttersDev if ( defined($shuttersDev) );
    return $self->{shuttersDev};
}

sub getShuttersDev {
    my $self = shift;

    return $self->{shuttersDev};
}

sub setAttrUpdateChanges {
    my ( $self, $attr, $value ) = @_;

    $self->{ $self->{shuttersDev} }{AttrUpdateChanges}{$attr} = $value;
    return;
}

sub setHardLockOut {
    my $self = shift;
    my $cmd  = shift;

    if (   $FHEM::Automation::ShuttersControl::shutters->getLockOut eq 'hard'
        && $FHEM::Automation::ShuttersControl::shutters->getLockOutCmd ne
        'none' )
    {
        ::CommandSet( undef, $self->{shuttersDev} . ' inhibit ' . $cmd )
          if ( $FHEM::Automation::ShuttersControl::shutters->getLockOutCmd eq
            'inhibit' );
        ::CommandSet( undef,
            $self->{shuttersDev} . ' '
              . ( $cmd eq 'on' ? 'blocked' : 'unblocked' ) )
          if ( $FHEM::Automation::ShuttersControl::shutters->getLockOutCmd eq
            'blocked' );
        ::CommandSet( undef,
            $self->{shuttersDev} . ' '
              . ( $cmd eq 'on' ? 'protectionOn' : 'protectionOff' ) )
          if ( $FHEM::Automation::ShuttersControl::shutters->getLockOutCmd eq
            'protected' );
    }
    return;
}

sub setNoDelay {
    my $self    = shift;
    my $noDelay = shift;

    $self->{ $self->{shuttersDev} }{noDelay} = $noDelay;
    return;
}

sub setSelfDefenseAbsent {
    my ( $self, $timerrun, $active, $timerhash ) = @_;

    $self->{ $self->{shuttersDev} }{selfDefenseAbsent}{timerrun}  = $timerrun;
    $self->{ $self->{shuttersDev} }{selfDefenseAbsent}{active}    = $active;
    $self->{ $self->{shuttersDev} }{selfDefenseAbsent}{timerhash} = $timerhash
      if ( defined($timerhash) );
    return;
}

sub setDriveCmd {
    my $self     = shift;
    my $posValue = shift;

    my $offSet;
    my $offSetStart;

    if (
        (
            $FHEM::Automation::ShuttersControl::shutters->getPartyMode eq 'on'
            && $FHEM::Automation::ShuttersControl::ascDev->getPartyMode eq 'on'
        )
        || (
            $FHEM::Automation::ShuttersControl::shutters->getAdv
            && !$FHEM::Automation::ShuttersControl::shutters
            ->getQueryShuttersPos(
                $posValue)
            && !$FHEM::Automation::ShuttersControl::shutters->getAdvDelay
            && !$FHEM::Automation::ShuttersControl::shutters
            ->getExternalTriggerStatus
            && !$FHEM::Automation::ShuttersControl::shutters
            ->getSelfDefenseState
        )
      )
    {
        $FHEM::Automation::ShuttersControl::shutters->setDelayCmd($posValue);
        $FHEM::Automation::ShuttersControl::ascDev->setDelayCmdReading;
        $FHEM::Automation::ShuttersControl::shutters->setNoDelay(0);
        $FHEM::Automation::ShuttersControl::shutters->setExternalTriggerStatus(0)
          if ( $FHEM::Automation::ShuttersControl::shutters
            ->getExternalTriggerStatus );

        FHEM::Automation::ShuttersControl::ASC_Debug( 'setDriveCmd: '
              . $FHEM::Automation::ShuttersControl::shutters->getShuttersDev
              . ' - Die Fahrt wird zurückgestellt. Grund kann ein geöffnetes Fenster sein oder ein aktivierter Party Modus oder Weihnachtszeit'
        );
    }
    else {
        $FHEM::Automation::ShuttersControl::shutters->setAdvDelay(0)
          if ( $FHEM::Automation::ShuttersControl::shutters->getAdvDelay );
        $FHEM::Automation::ShuttersControl::shutters->setDelayCmd('none')
          if ( $FHEM::Automation::ShuttersControl::shutters->getDelayCmd ne
            'none' )
          ; # setzt den Wert auf none da der Rolladen nun gesteuert werden kann.
        $FHEM::Automation::ShuttersControl::shutters->setExternalTriggerStatus(0)
          if ( $FHEM::Automation::ShuttersControl::shutters
            ->getExternalTriggerStatus );

        ### antifreeze Routine
        if ( $FHEM::Automation::ShuttersControl::shutters->getAntiFreezeStatus >
            0 )
        {
            if ( $FHEM::Automation::ShuttersControl::shutters
                ->getAntiFreezeStatus != 1 )
            {

                $posValue =
                  $FHEM::Automation::ShuttersControl::shutters->getStatus;
                $FHEM::Automation::ShuttersControl::shutters->setLastDrive(
                    'no drive - antifreeze defense');
                $FHEM::Automation::ShuttersControl::shutters
                  ->setLastDriveReading;
                $FHEM::Automation::ShuttersControl::ascDev->setStateReading;
            }
            elsif ( $posValue ==
                $FHEM::Automation::ShuttersControl::shutters->getClosedPos )
            {
                $posValue = $FHEM::Automation::ShuttersControl::shutters
                  ->getAntiFreezePos;
                $FHEM::Automation::ShuttersControl::shutters->setLastDrive(
                    $FHEM::Automation::ShuttersControl::shutters->getLastDrive
                      . ' - antifreeze mode' );
            }
        }

        my %h = (
            shuttersDev => $self->{shuttersDev},
            posValue    => $posValue,
        );

        $offSet = $FHEM::Automation::ShuttersControl::shutters->getDelay
          if ( $FHEM::Automation::ShuttersControl::shutters->getDelay > -1 );
        $offSet = $FHEM::Automation::ShuttersControl::ascDev->getShuttersOffset
          if ( $FHEM::Automation::ShuttersControl::shutters->getDelay < 0 );
        $offSetStart =
          $FHEM::Automation::ShuttersControl::shutters->getDelayStart;

        if ( $FHEM::Automation::ShuttersControl::shutters->getSelfDefenseAbsent
            && !$FHEM::Automation::ShuttersControl::shutters
            ->getSelfDefenseAbsentTimerrun
            && $FHEM::Automation::ShuttersControl::shutters->getSelfDefenseMode
            ne 'off'
            && $FHEM::Automation::ShuttersControl::shutters->getSelfDefenseState
            && $FHEM::Automation::ShuttersControl::ascDev->getSelfDefense eq
            'on' )
        {
            ::InternalTimer(
                ::gettimeofday() +
                  $FHEM::Automation::ShuttersControl::shutters
                  ->getSelfDefenseAbsentDelay,
                \&FHEM::Automation::ShuttersControl::_SetCmdFn, \%h
            );
            $FHEM::Automation::ShuttersControl::shutters->setSelfDefenseAbsent(
                1, 0, \%h );
        }
        elsif ( $offSetStart > 0
            && !$FHEM::Automation::ShuttersControl::shutters->getNoDelay )
        {
            ::InternalTimer(
                ::gettimeofday() + int(
                    rand($offSet) +
                      $FHEM::Automation::ShuttersControl::shutters
                      ->getDelayStart
                ),
                \&FHEM::Automation::ShuttersControl::_SetCmdFn,
                \%h
            );

            FHEM::Automation::ShuttersControl::ASC_Debug( 'FnSetDriveCmd: '
                  . $FHEM::Automation::ShuttersControl::shutters->getShuttersDev
                  . ' - versetztes fahren' );
        }
        elsif ($offSetStart < 1
            || $FHEM::Automation::ShuttersControl::shutters->getNoDelay )
        {
            FHEM::Automation::ShuttersControl::_SetCmdFn( \%h );
            FHEM::Automation::ShuttersControl::ASC_Debug( 'FnSetDriveCmd: '
                  . $FHEM::Automation::ShuttersControl::shutters->getShuttersDev
                  . ' - NICHT versetztes fahren' );
        }

        FHEM::Automation::ShuttersControl::ASC_Debug(
                'FnSetDriveCmd: '
              . $FHEM::Automation::ShuttersControl::shutters->getShuttersDev
              . ' - NoDelay: '
              . (
                $FHEM::Automation::ShuttersControl::shutters->getNoDelay
                ? 'JA'
                : 'NEIN'
              )
        );
        $FHEM::Automation::ShuttersControl::shutters->setNoDelay(0);
    }

    return;
}

sub setSunsetUnixTime {
    my $self     = shift;
    my $unixtime = shift;

    $self->{ $self->{shuttersDev} }{sunsettime} = $unixtime;
    return;
}

sub setSunset {
    my $self  = shift;
    my $value = shift;

    $self->{ $self->{shuttersDev} }{sunset} = $value;
    return;
}

sub setSunriseUnixTime {
    my $self     = shift;
    my $unixtime = shift;

    $self->{ $self->{shuttersDev} }{sunrisetime} = $unixtime;
    return;
}

sub setSunrise {
    my $self  = shift;
    my $value = shift;

    $self->{ $self->{shuttersDev} }{sunrise} = $value;
    return;
}

sub setDelayCmd {
    my $self     = shift;
    my $posValue = shift;

    $self->{ $self->{shuttersDev} }{delayCmd} = $posValue;
    return;
}

sub setLastDrive {
    my $self      = shift;
    my $lastDrive = shift;

    $self->{ $self->{shuttersDev} }{lastDrive} = $lastDrive;
    return;
}

sub setPosSetCmd {
    my $self      = shift;
    my $posSetCmd = shift;

    $self->{ $self->{shuttersDev} }{posSetCmd} = $posSetCmd;
    return;
}

sub setLastDriveReading {
    my $self            = shift;
    my $shuttersDevHash = $::defs{ $self->{shuttersDev} };

    my %h = (
        devHash   => $shuttersDevHash,
        lastDrive => $FHEM::Automation::ShuttersControl::shutters->getLastDrive,
    );

    ::InternalTimer( ::gettimeofday() + 0.1,
        \&FHEM::Automation::ShuttersControl::_setShuttersLastDriveDelayed,
        \%h );
    return;
}

sub setLastPos {

# letzte ermittelte Position bevor die Position des Rolladen über ASC geändert wurde
    my $self     = shift;
    my $position = shift;

    $self->{ $self->{shuttersDev} }{lastPos}{VAL} = $position
      if ( defined($position) );
    $self->{ $self->{shuttersDev} }{lastPos}{TIME} = int( ::gettimeofday() )
      if ( defined( $self->{ $self->{shuttersDev} }{lastPos} ) );
    return;
}

sub setLastManPos {
    my $self     = shift;
    my $position = shift;

    $self->{ $self->{shuttersDev} }{lastManPos}{VAL} = $position
      if ( defined($position) );
    $self->{ $self->{shuttersDev} }{lastManPos}{TIME} = int( ::gettimeofday() )
      if ( defined( $self->{ $self->{shuttersDev} }{lastManPos} )
        && defined( $self->{ $self->{shuttersDev} }{lastManPos}{TIME} ) );
    $self->{ $self->{shuttersDev} }{lastManPos}{TIME} =
      int( ::gettimeofday() ) - 86400
      if ( defined( $self->{ $self->{shuttersDev} }{lastManPos} )
        && !defined( $self->{ $self->{shuttersDev} }{lastManPos}{TIME} ) );
    return;
}

sub setDefault {
    my $self       = shift;
    my $defaultarg = shift;

    $self->{defaultarg} = $defaultarg if ( defined($defaultarg) );
    return $self->{defaultarg};
}

sub setRoommate {
    my $self     = shift;
    my $roommate = shift;

    $self->{roommate} = $roommate if ( defined($roommate) );
    return $self->{roommate};
}

sub setInTimerFuncHash {
    my $self            = shift;
    my $inTimerFuncHash = shift;

    $self->{ $self->{shuttersDev} }{inTimerFuncHash} = $inTimerFuncHash
      if ( defined($inTimerFuncHash) );
    return;
}

sub setPrivacyDownStatus {
    my $self        = shift;
    my $statusValue = shift;

    $self->{ $self->{shuttersDev} }->{privacyDownStatus} = $statusValue;
    return;
}

sub setPrivacyUpStatus {
    my $self        = shift;
    my $statusValue = shift;

    $self->{ $self->{shuttersDev} }->{privacyUpStatus} = $statusValue;
    return;
}

sub setSelfDefenseState {
    my $self  = shift;
    my $value = shift;

    $self->{ $self->{shuttersDev} }{selfDefenseState} = $value;
    return;
}

sub setAdvDelay {
    my $self     = shift;
    my $advDelay = shift;

    $self->{ $self->{shuttersDev} }->{AdvDelay} = $advDelay;
    return;
}

sub setWindProtectionStatus {    # Werte protected, unprotected
    my $self  = shift;
    my $value = shift;

    $self->{ $self->{shuttersDev} }->{ASC_WindParameters}->{VAL} = $value
      if ( defined($value) );

    return;
}

sub setRainProtectionStatus {    # Werte protected, unprotected
    my $self  = shift;
    my $value = shift;

    $self->{ $self->{shuttersDev} }->{RainProtection}->{VAL} = $value
      if ( defined($value) );
    return;
}

sub setRainUnprotectionDelayObj {
    my $self  = shift;
    my $value = shift;

    $self->{ $self->{shuttersDev} }->{RainProtection}->{UNPROTECTIONDELAYOBJVAL} = $value
      if ( defined($value) );
    return;
}

sub setExternalTriggerStatus {
    my $self  = shift;
    my $value = shift;

    $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}->{event} = $value
      if ( defined($value) );

    return;
}

sub getExternalTriggerStatus {
    my $self = shift;

    return (
        (
            defined(
                $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}->{event}
              )
              and
              $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}->{event}
        ) ? 1 : 0
    );
}

sub getHomemode {
    my $self = shift;

    my $homemode =
      $FHEM::Automation::ShuttersControl::shutters->getRoommatesStatus;
    $homemode = $FHEM::Automation::ShuttersControl::ascDev->getResidentsStatus
      if ( $homemode eq 'none' );
    return $homemode;
}

sub getAdvDelay {
    my $self = shift;

    return (
        defined( $self->{ $self->{shuttersDev} }->{AdvDelay} )
        ? $self->{ $self->{shuttersDev} }->{AdvDelay}
        : 0
    );
}

sub getPrivacyDownStatus {
    my $self = shift;

    return (
        defined( $self->{ $self->{shuttersDev} }->{privacyDownStatus} )
        ? $self->{ $self->{shuttersDev} }->{privacyDownStatus}
        : undef
    );
}

sub getPrivacyUpStatus {
    my $self = shift;

    return (
        defined( $self->{ $self->{shuttersDev} }->{privacyUpStatus} )
        ? $self->{ $self->{shuttersDev} }->{privacyUpStatus}
        : undef
    );
}

sub getAttrUpdateChanges {
    my $self = shift;
    my $attr = shift;

    return (
        defined( $self->{ $self->{shuttersDev} }{AttrUpdateChanges} )
          && defined(
            $self->{ $self->{shuttersDev} }{AttrUpdateChanges}{$attr} )
        ? $self->{ $self->{shuttersDev} }{AttrUpdateChanges}{$attr}
        : 'none'
    );
}

sub getIsDay {
    my $self = shift;

    return FHEM::Automation::ShuttersControl::Helper::_IsDay( $self->{shuttersDev} );
}

sub getAntiFreezeStatus {
    use POSIX qw(strftime);
    my $self = shift;
    my $daytime = strftime( "%P", localtime() );
    $daytime = (
        defined($daytime) && $daytime
        ? $daytime
        : ( strftime( "%H", localtime() ) < 12 ? 'am' : 'pm' )
    );
    my $outTemp = $FHEM::Automation::ShuttersControl::ascDev->getOutTemp;

#     $outTemp = $FHEM::Automation::ShuttersControl::shutters->getOutTemp if ( $FHEM::Automation::ShuttersControl::shutters->getOutTemp != -100 );        sollte raus das der Sensor im Rollo auch ein Innentemperatursensor sein kann.

    if (   $FHEM::Automation::ShuttersControl::shutters->getAntiFreeze ne 'off'
        && $outTemp <=
        $FHEM::Automation::ShuttersControl::ascDev->getFreezeTemp )
    {

        if ( $FHEM::Automation::ShuttersControl::shutters->getAntiFreeze eq
            'soft' )
        {
            return 1;
        }
        elsif ( $FHEM::Automation::ShuttersControl::shutters->getAntiFreeze eq
            $daytime )
        {
            return 2;
        }
        elsif ( $FHEM::Automation::ShuttersControl::shutters->getAntiFreeze eq
            'hard' )
        {
            return 3;
        }
    }
    else { return 0; }
}

sub getShuttersPosCmdValueNegate {
    my $self = shift;

    return ( $FHEM::Automation::ShuttersControl::shutters->getOpenPos <
          $FHEM::Automation::ShuttersControl::shutters->getClosedPos ? 1 : 0 );
}

sub getQueryShuttersPos
{ # Es wird geschaut ob die aktuelle Position des Rollos unterhalb der Zielposition ist
    my $self     = shift;
    my $posValue = shift; #   wenn dem so ist wird 1 zurück gegeben ansonsten 0

    return (
        $FHEM::Automation::ShuttersControl::shutters
          ->getShuttersPosCmdValueNegate
        ? $FHEM::Automation::ShuttersControl::shutters->getStatus > $posValue
        : $FHEM::Automation::ShuttersControl::shutters->getStatus < $posValue
    );
}

sub getPosSetCmd {
    my $self = shift;

    return (
        defined( $self->{ $self->{shuttersDev} }{posSetCmd} )
        ? $self->{ $self->{shuttersDev} }{posSetCmd}
        : $FHEM::Automation::ShuttersControl::shutters->getPosCmd
    );
}

sub getNoDelay {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }{noDelay};
}

sub getSelfDefenseState {
    my $self = shift;

    return (
        defined( $self->{ $self->{shuttersDev} }{selfDefenseState} )
        ? $self->{ $self->{shuttersDev} }{selfDefenseState}
        : 0
    );
}

sub getSelfDefenseAbsent {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }{selfDefenseAbsent}{active};
}

sub getSelfDefenseAbsentTimerrun {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }{selfDefenseAbsent}{timerrun};
}

sub getSelfDefenseAbsentTimerhash {
    my $self = shift;

    return (
        defined(
            $self->{ $self->{shuttersDev} }{selfDefenseAbsent}{timerhash}
          )
        ? $self->{ $self->{shuttersDev} }{selfDefenseAbsent}{timerhash}
        : undef
    );
}

sub getLastDrive {
    my $self = shift;

    $self->{ $self->{shuttersDev} }{lastDrive} =
      ::ReadingsVal( $self->{shuttersDev}, 'ASC_ShuttersLastDrive', 'none' )
      if ( !defined( $self->{ $self->{shuttersDev} }{lastDrive} ) );

    return $self->{ $self->{shuttersDev} }{lastDrive};
}

sub getLastPos
{ # letzte ermittelte Position bevor die Position des Rolladen über ASC geändert wurde
    my $self = shift;

    return (
        defined( $self->{ $self->{shuttersDev} }{lastPos} )
          && defined( $self->{ $self->{shuttersDev} }{lastPos}{VAL} )
        ? $self->{ $self->{shuttersDev} }{lastPos}{VAL}
        : 50
    );
}

sub getLastPosTimestamp {
    my $self = shift;

    return (
        defined( $self->{ $self->{shuttersDev} } )
          && defined( $self->{ $self->{shuttersDev} }{lastPos} )
          && defined( $self->{ $self->{shuttersDev} }{lastPos}{TIME} )
        ? $self->{ $self->{shuttersDev} }{lastPos}{TIME}
        : 0
    );
}

sub getLastManPos
{ # letzte ermittelte Position bevor die Position des Rolladen manuell (nicht über ASC) geändert wurde
    my $self = shift;

    return (
        defined( $self->{ $self->{shuttersDev} }{lastManPos} )
          && defined( $self->{ $self->{shuttersDev} }{lastManPos}{VAL} )
        ? $self->{ $self->{shuttersDev} }{lastManPos}{VAL}
        : 50
    );
}

sub getLastManPosTimestamp {
    my $self = shift;

    return (
        defined( $self->{ $self->{shuttersDev} } )
          && defined( $self->{ $self->{shuttersDev} }{lastManPos} )
          && defined( $self->{ $self->{shuttersDev} }{lastManPos}{TIME} )
        ? $self->{ $self->{shuttersDev} }{lastManPos}{TIME}
        : 0
    );
}

sub getInTimerFuncHash {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }{inTimerFuncHash};
}

sub getWindProtectionStatus {    # Werte protected, unprotected
    my $self = shift;

    return (
        (
            defined( $self->{ $self->{shuttersDev} }->{ASC_WindParameters} )
              && defined(
                $self->{ $self->{shuttersDev} }->{ASC_WindParameters}->{VAL}
              )
        )
        ? $self->{ $self->{shuttersDev} }->{ASC_WindParameters}->{VAL}
        : 'unprotected'
    );
}

sub getRainProtectionStatus {    # Werte protected, unprotected
    my $self = shift;

    return (
        (
            defined( $self->{ $self->{shuttersDev} }->{RainProtection} )
              && defined(
                $self->{ $self->{shuttersDev} }->{RainProtection}->{VAL}
              )
        )
        ? $self->{ $self->{shuttersDev} }->{RainProtection}->{VAL}
        : 'unprotected'
    );
}

sub getRainUnprotectionDelayObj {
    my $self = shift;

    return (
        (
            defined( $self->{ $self->{shuttersDev} }->{RainProtection} )
              && defined(
                $self->{ $self->{shuttersDev} }->{RainProtection}->{UNPROTECTIONDELAYOBJVAL}
              )
        )
        ? $self->{ $self->{shuttersDev} }->{RainProtection}->{UNPROTECTIONDELAYOBJVAL}
        : 'none'
    );
}

sub getSunsetUnixTime {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }{sunsettime};
}

sub getSunset {
    my $self = shift;

    return (
        defined( $self->{ $self->{shuttersDev} }{sunset} )
        ? $self->{ $self->{shuttersDev} }{sunset}
        : 0
    );
}

sub getSunriseUnixTime {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }{sunrisetime};
}

sub getSunrise {
    my $self = shift;

    return (
        defined( $self->{ $self->{shuttersDev} }{sunrise} )
        ? $self->{ $self->{shuttersDev} }{sunrise}
        : 0
    );
}

sub getRoommatesStatus {
    my $self = shift;

    my $loop = 0;
    my @roState;
    my %statePrio = (
        'asleep'    => 1,
        'gotosleep' => 2,
        'awoken'    => 3,
        'home'      => 4,
        'absent'    => 5,
        'gone'      => 6,
        'none'      => 7
    );
    my $minPrio = 10;

    for my $ro (
        split(
            ",", $FHEM::Automation::ShuttersControl::shutters->getRoommates
        )
      )
    {
        $FHEM::Automation::ShuttersControl::shutters->setRoommate($ro);
        my $currentPrio =
          $statePrio{ $FHEM::Automation::ShuttersControl::shutters
              ->_getRoommateStatus };
        $minPrio = $currentPrio if ( $minPrio > $currentPrio );
    }

    my %revStatePrio = reverse %statePrio;
    return $revStatePrio{$minPrio};
}

sub getRoommatesLastStatus {
    my $self = shift;

    my $loop = 0;
    my @roState;
    my %statePrio = (
        'asleep'    => 1,
        'gotosleep' => 2,
        'awoken'    => 3,
        'home'      => 6,
        'absent'    => 5,
        'gone'      => 4,
        'none'      => 7
    );
    my $minPrio = 10;

    for my $ro (
        split(
            ",", $FHEM::Automation::ShuttersControl::shutters->getRoommates
        )
      )
    {
        $FHEM::Automation::ShuttersControl::shutters->setRoommate($ro);
        my $currentPrio =
          $statePrio{ $FHEM::Automation::ShuttersControl::shutters
              ->_getRoommateLastStatus };
        $minPrio = $currentPrio if ( $minPrio > $currentPrio );
    }

    my %revStatePrio = reverse %statePrio;
    return $revStatePrio{$minPrio};
}

sub getOutTemp {
    my $self = shift;

    return ::ReadingsVal(
        $FHEM::Automation::ShuttersControl::shutters->_getTempSensor,
        $FHEM::Automation::ShuttersControl::shutters->getTempSensorReading,
        -100 );
}

sub getIdleDetection {
    my $self = shift;

    return ::ReadingsVal(
        $self->{shuttersDev},
        $FHEM::Automation::ShuttersControl::shutters->_getIdleDetectionReading,
        'none'
    );
}

### Begin Beschattung Objekt mit Daten befüllen
sub setShadingStatus {
    my $self  = shift;
    my $value = shift; ### Werte für value = in, out, in reserved, out reserved

# Es wird durch das return die ShadingWaitingTime nicht mehr beachtet, Bugmeldung von Bernd Griemsmann
#     return
#       if ( defined($value)
#         && exists( $self->{ $self->{shuttersDev} }{ShadingStatus}{VAL} )
#         && $self->{ $self->{shuttersDev} }{ShadingStatus}{VAL} eq $value );

    $FHEM::Automation::ShuttersControl::shutters->setShadingLastStatus(
        ( $value eq 'in' ? 'out' : 'in' ) )
      if ( $value eq 'in'
        || $value eq 'out' );

    $self->{ $self->{shuttersDev} }{ShadingStatus}{VAL} = $value
      if ( defined($value) );
    $self->{ $self->{shuttersDev} }{ShadingStatus}{TIME} = int( ::gettimeofday() )
      if ( defined( $self->{ $self->{shuttersDev} }{ShadingStatus} ) );

    return;
}

sub setShadingLastStatus {
    my $self  = shift;
    my $value = shift;    ### Werte für value = in, out

    return
      if ( defined($value)
        && exists( $self->{ $self->{shuttersDev} }{ShadingLastStatus}{VAL} )
        && $self->{ $self->{shuttersDev} }{ShadingLastStatus}{VAL} eq $value );

    $self->{ $self->{shuttersDev} }{ShadingLastStatus}{VAL} = $value
      if ( defined($value) );
    $self->{ $self->{shuttersDev} }{ShadingLastStatus}{TIME} =
      int( ::gettimeofday() )
      if ( defined( $self->{ $self->{shuttersDev} }{ShadingLastStatus} ) );
    $self->{ $self->{shuttersDev} }{ShadingManualDriveStatus}{VAL} = 0
      if ( $value eq 'out' );

    return;
}

sub setShadingManualDriveStatus {
    my $self  = shift;
    my $value = shift;    ### Werte für value = 0, 1

    $self->{ $self->{shuttersDev} }{ShadingManualDriveStatus}{VAL} = $value
      if ( defined($value) );

    return;
}

sub setShadingLastPos {
    my $self  = shift;
    my $value = shift;

    $self->{ $self->{shuttersDev} }{ShadingLastPos}{VAL} = $value
      if ( defined($value) );

    return;
}

sub setShadingBetweenTheTimeSuspend {       # Werte für value = 0, 1
    my $self  = shift;
    my $value = shift;

    $self->{ $self->{shuttersDev} }{ShadingBetweenTheTimeSuspend}{VAL} = $value
      if ( defined($value) );

    return;
}

sub setPushBrightnessInArray {
    my $self  = shift;
    my $value = shift;

    unshift(
        @{ $self->{ $self->{shuttersDev} }->{BrightnessAverageArray}->{VAL} },
        $value
    );
    pop( @{ $self->{ $self->{shuttersDev} }->{BrightnessAverageArray}->{VAL} } )
      if (
        scalar(
            @{
                $self->{ $self->{shuttersDev} }->{BrightnessAverageArray}->{VAL}
            }
        ) > $FHEM::Automation::ShuttersControl::shutters
        ->getMaxBrightnessAverageArrayObjects
      );

    return;
}

sub getBrightnessAverage {
    use FHEM::Automation::ShuttersControl::Helper qw (AverageBrightness);

    my $self = shift;

    return AverageBrightness(
        @{ $self->{ $self->{shuttersDev} }->{BrightnessAverageArray}->{VAL} } )
      if (
        ref( $self->{ $self->{shuttersDev} }->{BrightnessAverageArray}->{VAL} )
        eq 'ARRAY'
        && scalar(
            @{
                $self->{ $self->{shuttersDev} }->{BrightnessAverageArray}->{VAL}
            }
        ) > 0
      );

    return;
}

sub getShadingStatus {   # Werte für value = in, out, in reserved, out reserved
    my $self = shift;

    return (
        defined( $self->{ $self->{shuttersDev} }{ShadingStatus} )
          && defined( $self->{ $self->{shuttersDev} }{ShadingStatus}{VAL} )
        ? $self->{ $self->{shuttersDev} }{ShadingStatus}{VAL}
        : 'out'
    );
}

sub getShadingBetweenTheTimeSuspend {   # Werte für value = 0, 1
    my $self = shift;

    return (
        defined( $self->{ $self->{shuttersDev} }{ShadingBetweenTheTimeSuspend} )
          && defined( $self->{ $self->{shuttersDev} }{ShadingBetweenTheTimeSuspend}{VAL} )
        ? $self->{ $self->{shuttersDev} }{ShadingBetweenTheTimeSuspend}{VAL}
        : 0
    );
}

sub getShadingLastStatus {    # Werte für value = in, out
    my $self = shift;

    return (
        defined( $self->{ $self->{shuttersDev} }{ShadingLastStatus} )
          && defined( $self->{ $self->{shuttersDev} }{ShadingLastStatus}{VAL} )
        ? $self->{ $self->{shuttersDev} }{ShadingLastStatus}{VAL}
        : 'out'
    );
}

sub getShadingManualDriveStatus {    # Werte für value = 0, 1
    my $self = shift;

    return (
        defined( $self->{ $self->{shuttersDev} }{ShadingManualDriveStatus} )
          && defined(
            $self->{ $self->{shuttersDev} }{ShadingManualDriveStatus}{VAL}
          )
        ? $self->{ $self->{shuttersDev} }{ShadingManualDriveStatus}{VAL}
        : 0
    );
}

sub getIfInShading {
    my $self = shift;

    return (
        (
            $FHEM::Automation::ShuttersControl::shutters->getShadingMode ne
              'off'
              && $FHEM::Automation::ShuttersControl::shutters
              ->getShadingLastStatus eq 'out'
        ) ? 1 : 0
    );
}

sub getShadingStatusTimestamp {
    my $self = shift;

    return (
        defined( $self->{ $self->{shuttersDev} } )
          && defined( $self->{ $self->{shuttersDev} }{ShadingStatus} )
          && defined( $self->{ $self->{shuttersDev} }{ShadingStatus}{TIME} )
        ? $self->{ $self->{shuttersDev} }{ShadingStatus}{TIME}
        : 0
    );
}

sub getShadingLastStatusTimestamp {
    my $self = shift;

    return (
        defined( $self->{ $self->{shuttersDev} } )
          && defined( $self->{ $self->{shuttersDev} }{ShadingLastStatus} )
          && defined( $self->{ $self->{shuttersDev} }{ShadingLastStatus}{TIME} )
        ? $self->{ $self->{shuttersDev} }{ShadingLastStatus}{TIME}
        : 0
    );
}

sub getShadingLastPos {
    my $self = shift;

    return (
        defined( $self->{ $self->{shuttersDev} }{ShadingLastPos} )
          && defined(
            $self->{ $self->{shuttersDev} }{ShadingLastPos}{VAL}
          )
        ? $self->{ $self->{shuttersDev} }{ShadingLastPos}{VAL}
        : $FHEM::Automation::ShuttersControl::shutters->getShadingPos
    );
}

### Ende Beschattung




1;
