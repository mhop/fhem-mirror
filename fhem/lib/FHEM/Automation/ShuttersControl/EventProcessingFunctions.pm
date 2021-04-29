###############################################################################
#
# Developed with Kate
#
#  (c) 2018-2020 Copyright: Marko Oldenburg (fhemsupport@cooltux.net)
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
package FHEM::Automation::ShuttersControl::EventProcessingFunctions;

use strict;
use warnings;
use POSIX qw(strftime);
use utf8;

use Data::Dumper;    #only for Debugging

use FHEM::Automation::ShuttersControl::Helper qw (:ALL);
use FHEM::Automation::ShuttersControl::Shading qw (:ALL);

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(
                    EventProcessingPartyMode
                    EventProcessingGeneral
                    EventProcessingShutters
                    EventProcessingAdvShuttersClose
);
our %EXPORT_TAGS = (
    ALL => [
        qw(
           EventProcessingPartyMode
           EventProcessingGeneral
           EventProcessingShutters
           EventProcessingAdvShuttersClose
          )
    ],
);

use GPUtils qw(GP_Import);
## Import der FHEM Funktionen
BEGIN {
    GP_Import(
        qw(
           Log3
           gettimeofday
           computeAlignTime
           CommandSet
           ReadingsVal
           RemoveInternalTimer
          )
    );
}

sub EventProcessingGeneral {
    my $hash    = shift;
    my $devname = shift;
    my $events  = shift;

    my $name = $hash->{NAME};

    if ( defined($devname) && ($devname) )
    { # es wird lediglich der Devicename der Funktion mitgegeben wenn es sich nicht um global handelt daher hier die Unterscheidung
        my $windReading = $FHEM::Automation::ShuttersControl::ascDev->getWindSensorReading // 'none';
        my $rainReading = $FHEM::Automation::ShuttersControl::ascDev->getRainSensorReading // 'none';

        while ( my ( $device, $deviceAttr ) =
            each %{ $hash->{monitoredDevs}{$devname} } )
        {
            if ( $device eq $name ) {
                EventProcessingResidents( $hash, $device, $events )
                  if ( $deviceAttr eq 'ASC_residentsDev' );
                EventProcessingRain( $hash, $device, $events )
                  if ( $events =~ m{$rainReading}xms );
                EventProcessingWind( $hash, $device, $events )
                  if ( $events =~ m{$windReading}xms );

                EventProcessingTwilightDevice( $hash, $device, $events )
                  if ( $deviceAttr eq 'ASC_twilightDevice' );
            }

            EventProcessingWindowRec( $hash, $device, $events )
              if ( $deviceAttr eq 'ASC_WindowRec' )
              ;    # ist es ein Fensterdevice wird die Funktion gestartet
            EventProcessingRoommate( $hash, $device, $events )
              if ( $deviceAttr eq 'ASC_Roommate_Device' )
              ;    # ist es ein Bewohner Device wird diese Funktion gestartet

            EventProcessingExternalTriggerDevice( $hash, $device, $events )
              if ( $deviceAttr eq 'ASC_ExternalTrigger' );

            $FHEM::Automation::ShuttersControl::shutters->setShuttersDev($device)
              if ( $deviceAttr eq 'ASC_BrightnessSensor' );

            if (
                $deviceAttr eq 'ASC_BrightnessSensor'
                && (   $FHEM::Automation::ShuttersControl::shutters->getDown eq 'brightness'
                    || $FHEM::Automation::ShuttersControl::shutters->getUp eq 'brightness' )
              )
            {
                EventProcessingBrightness( $hash, $device, $events );
            }
            elsif ( $deviceAttr eq 'ASC_BrightnessSensor' ) {
                EventProcessingShadingBrightness( $hash, $device, $events );
            }
        }
    }
    else {    # alles was kein Devicenamen mit übergeben hat landet hier
        if (
            $events =~ m{^ATTR\s(.*)
             \s(ASC_Roommate_Device|ASC_WindowRec|ASC_residentsDev|ASC_rainSensor
                |ASC_windSensor|ASC_BrightnessSensor|ASC_ExternalTrigger
                |ASC_twilightDevice)
             \s(.*)$}xms
          )
        {     # wurde den Attributen unserer Rolläden ein Wert zugewiesen ?
            FHEM::Automation::ShuttersControl::AddNotifyDev( $hash, $3, $1, $2 ) if ( $3 ne 'none' );
            Log3( $name, 4,
                "AutoShuttersControl ($name) - EventProcessing: ATTR" );
        }
        elsif (
            $events =~ m{^DELETEATTR
                \s(.*)\s(ASC_Roommate_Device
                    |ASC_WindowRec|ASC_residentsDev|ASC_rainSensor
                    |ASC_windSensor|ASC_BrightnessSensor|ASC_ExternalTrigger
                    |ASC_twilightDevice)
                $}xms
          )
        {    # wurde das Attribut unserer Rolläden gelöscht ?
            Log3( $name, 4,
                "AutoShuttersControl ($name) - EventProcessing: DELETEATTR" );
            FHEM::Automation::ShuttersControl::DeleteNotifyDev( $hash, $1, $2 );
        }
        elsif (
            $events =~ m{^(DELETEATTR|ATTR)
                \s(.*)\s(ASC_Time_Up_WE_Holiday|ASC_Up|ASC_Down
                    |ASC_AutoAstroModeMorning|ASC_AutoAstroModeMorningHorizon
                    |ASC_PrivacyDownValue_beforeNightClose
                    |ASC_PrivacyUpValue_beforeDayOpen|ASC_AutoAstroModeEvening
                    |ASC_AutoAstroModeEveningHorizon|ASC_Time_Up_Early
                    |ASC_Time_Up_Late|ASC_Time_Down_Early|ASC_Time_Down_Late)
                (.*)?}xms
          )
        {
            FHEM::Automation::ShuttersControl::CreateSunRiseSetShuttersTimer( $hash, $2 )
              if (
                $3 ne 'ASC_Time_Up_WE_Holiday'
                || (   $3 eq 'ASC_Time_Up_WE_Holiday'
                    && $FHEM::Automation::ShuttersControl::ascDev->getSunriseTimeWeHoliday eq 'on' )
              );
        }
        elsif (
            $events =~ m{^(DELETEATTR|ATTR)
                \s(.*)\s(ASC_autoAstroModeMorning|ASC_autoAstroModeMorningHorizon
                    |ASC_autoAstroModeEvening|ASC_autoAstroModeEveningHorizon)
                (.*)?}xms
          )
        {
            FHEM::Automation::ShuttersControl::RenewSunRiseSetShuttersTimer($hash);
        }
        elsif (
            $events =~ m{^(DELETEATTR|ATTR)
                \s(.*)\s(ASC_Shading_StateChange_SunnyCloudy)
                (.*)?}xms
          )
        {
            $FHEM::Automation::ShuttersControl::shutters->deleteShadingStateChangeSunny;
        }

        if (
            $events =~
m{^(DELETEATTR|ATTR)         #global ATTR myASC ASC_tempSensor Cellar
                \s(.*)\s(ASC_tempSensor
                    |ASC_Shading_Mode
                    |ASC_BrightnessSensor
                    |ASC_TempSensor)
                (.*)?}xms
          )
        {
#             ATTR RolloKinZimSteven_F1 ASC_Shading_Mode off
            if ( $events =~ m{^ATTR\s(.*)\sASC_Shading_Mode\s(off)}xms ) {
                my %funcHash = (
                    hash            => $hash,
                    shuttersdevice  => $1,
                    value           => $2,
                    attrEvent       => 1,
                );

                FHEM::Automation::ShuttersControl::Shading::_CheckShuttersConditionsForShadingFn(\%funcHash);
            }
            else {
                CommandSet( undef, $name . ' controlShading on' )
                if ( ReadingsVal( $name, 'controlShading', 'off' ) ne 'off' );
            }
        }
    }

    return;
}

## Sub zum steuern der Rolläden bei einem Fenster Event
sub EventProcessingWindowRec {
    my $hash        = shift;
    my $shuttersDev = shift;
    my $events      = shift;

    my $name = $hash->{NAME};

    my $reading =
      $FHEM::Automation::ShuttersControl::shutters->getWinDevReading;

    if ( $events =~
        m{.*$reading:.*?([Oo]pen(?>ed)?|[Cc]losed?|tilt(?>ed)?|true|false)}xms
        && IsAfterShuttersManualBlocking($shuttersDev) )
    {
        my $match = $1;

        FHEM::Automation::ShuttersControl::ASC_Debug(
                'EventProcessingWindowRec: '
              . $FHEM::Automation::ShuttersControl::shutters->getShuttersDev
              . ' - RECEIVED EVENT: '
              . $events
              . ' - IDENTIFIED EVENT: '
              . $1
              . ' - STORED EVENT: '
              . $match );

        $FHEM::Automation::ShuttersControl::shutters->setShuttersDev(
            $shuttersDev);
        my $homemode =
          $FHEM::Automation::ShuttersControl::shutters->getRoommatesStatus;
        $homemode =
          $FHEM::Automation::ShuttersControl::ascDev->getResidentsStatus
          if ( $homemode eq 'none' );

        #### Hardware Lock der Rollläden
        $FHEM::Automation::ShuttersControl::shutters->setHardLockOut('off')
          if ( $match =~ m{[Cc]lose|true}xms
            && $FHEM::Automation::ShuttersControl::shutters->getShuttersPlace
            eq 'terrace' );
        $FHEM::Automation::ShuttersControl::shutters->setHardLockOut('on')
          if ( $match =~ m{[Oo]pen|false}xms
            && $FHEM::Automation::ShuttersControl::shutters->getShuttersPlace
            eq 'terrace' );

        FHEM::Automation::ShuttersControl::ASC_Debug(
                'EventProcessingWindowRec: '
              . $FHEM::Automation::ShuttersControl::shutters->getShuttersDev
              . ' - HOMEMODE: '
              . $homemode
              . ' QueryShuttersPosWinRecTilted:'
              . $FHEM::Automation::ShuttersControl::shutters
              ->getQueryShuttersPos(
                $FHEM::Automation::ShuttersControl::shutters->getVentilatePos
              )
              . ' QueryShuttersPosWinRecComfort: '
              . $FHEM::Automation::ShuttersControl::shutters
              ->getQueryShuttersPos(
                $FHEM::Automation::ShuttersControl::shutters->getComfortOpenPos
              )
        );

        if (
               $match =~ m{[Cc]lose|true}xms
            && IsAfterShuttersTimeBlocking($shuttersDev)
            && (
                $FHEM::Automation::ShuttersControl::shutters->getStatus ==
                $FHEM::Automation::ShuttersControl::shutters->getVentilatePos
                || $FHEM::Automation::ShuttersControl::shutters->getStatus ==
                $FHEM::Automation::ShuttersControl::shutters->getComfortOpenPos
                || (   $FHEM::Automation::ShuttersControl::shutters->getStatus ==
                       $FHEM::Automation::ShuttersControl::shutters->getOpenPos
                    && $FHEM::Automation::ShuttersControl::shutters->getLastDrive
                      eq 'ventilate - window open'
                    && $FHEM::Automation::ShuttersControl::shutters->getSubTyp
                      eq 'twostate'
                    && $FHEM::Automation::ShuttersControl::shutters->getVentilateOpen
                      eq 'on' )
                || ( $FHEM::Automation::ShuttersControl::shutters->getStatus ==
                    $FHEM::Automation::ShuttersControl::shutters
                    ->getPrivacyDownPos
                    && $FHEM::Automation::ShuttersControl::shutters
                    ->getPrivacyDownStatus == 1
                    && !$FHEM::Automation::ShuttersControl::shutters->getIsDay )
            )
            && ( $FHEM::Automation::ShuttersControl::shutters->getVentilateOpen
                eq 'on'
                || $FHEM::Automation::ShuttersControl::ascDev
                ->getAutoShuttersControlComfort eq 'on' )
          )
        {
            FHEM::Automation::ShuttersControl::ASC_Debug(
                    'EventProcessingWindowRec: '
                  . $FHEM::Automation::ShuttersControl::shutters->getShuttersDev
                  . ' Event Closed' );

            if (
                $FHEM::Automation::ShuttersControl::shutters->getIsDay
                && ( ( $homemode ne 'asleep' && $homemode ne 'gotosleep' )
                    || $homemode eq 'none' )
                && $FHEM::Automation::ShuttersControl::shutters->getModeUp ne
                'absent'
                && $FHEM::Automation::ShuttersControl::shutters->getModeUp ne
                'off'
              )
            {
                if (
                    $FHEM::Automation::ShuttersControl::shutters->getIfInShading
                    && $FHEM::Automation::ShuttersControl::shutters
                    ->getShadingPos !=
                    $FHEM::Automation::ShuttersControl::shutters->getStatus
                    && $FHEM::Automation::ShuttersControl::shutters
                    ->getShadingMode ne 'absent' )
                {
                    $FHEM::Automation::ShuttersControl::shutters->setLastDrive(
                        'shading in');
                    $FHEM::Automation::ShuttersControl::shutters->setNoDelay(1);
                    $FHEM::Automation::ShuttersControl::shutters->setDriveCmd(
                        $FHEM::Automation::ShuttersControl::shutters
                          ->getShadingPos );
                }
                elsif (
                    !$FHEM::Automation::ShuttersControl::shutters
                    ->getIfInShading
                    && ( $FHEM::Automation::ShuttersControl::shutters->getStatus
                        != $FHEM::Automation::ShuttersControl::shutters
                        ->getOpenPos
                        || $FHEM::Automation::ShuttersControl::shutters
                        ->getStatus !=
                        $FHEM::Automation::ShuttersControl::shutters
                        ->getLastManPos )
                  )
                {
                    if ( $FHEM::Automation::ShuttersControl::shutters
                        ->getPrivacyDownStatus == 2 )
                    {
                        $FHEM::Automation::ShuttersControl::shutters
                          ->setLastDrive(
                            'window closed at privacy night close');
                        $FHEM::Automation::ShuttersControl::shutters
                          ->setNoDelay(1);
                        $FHEM::Automation::ShuttersControl::shutters
                          ->setDriveCmd(
                            $FHEM::Automation::ShuttersControl::shutters
                              ->getPrivacyDownPos );
                    }
                    else {
                        $FHEM::Automation::ShuttersControl::shutters
                          ->setLastDrive('window closed at day');
                        $FHEM::Automation::ShuttersControl::shutters
                          ->setNoDelay(1);
                        $FHEM::Automation::ShuttersControl::shutters
                          ->setDriveCmd(
                            (
                                $FHEM::Automation::ShuttersControl::shutters
                                  ->getVentilatePosAfterDayClosed eq 'open'
                                ? $FHEM::Automation::ShuttersControl::shutters
                                  ->getOpenPos
                                : $FHEM::Automation::ShuttersControl::shutters
                                  ->getLastManPos
                            )
                          );
                    }
                }
            }
            elsif (
                   !$FHEM::Automation::ShuttersControl::shutters->getIsDay
                && $FHEM::Automation::ShuttersControl::shutters->getModeDown eq 'roommate'
                && ( $FHEM::Automation::ShuttersControl::shutters->getRoommatesStatus eq 'home'
                  || $FHEM::Automation::ShuttersControl::shutters->getRoommatesStatus eq 'awoken' )
              )
            {
                $FHEM::Automation::ShuttersControl::shutters
                          ->setDriveCmd(
                            (
                                $FHEM::Automation::ShuttersControl::shutters
                                  ->getVentilatePosAfterDayClosed eq 'open'
                                ? $FHEM::Automation::ShuttersControl::shutters
                                  ->getOpenPos
                                : $FHEM::Automation::ShuttersControl::shutters
                                  ->getLastManPos
                            )
                          );
            }
            elsif (
                $FHEM::Automation::ShuttersControl::shutters->getModeDown ne
                'absent'
                && $FHEM::Automation::ShuttersControl::shutters->getModeDown ne
                'off'
                && (
                    (
                        !$FHEM::Automation::ShuttersControl::shutters->getIsDay
                        && $FHEM::Automation::ShuttersControl::shutters
                        ->getModeDown ne 'roommate'
                    )
                    || $homemode eq 'asleep'
                    || $homemode eq 'gotosleep'
                )
                && $FHEM::Automation::ShuttersControl::ascDev
                ->getAutoShuttersControlEvening eq 'on'
              )
            {
                if ( $FHEM::Automation::ShuttersControl::shutters
                    ->getPrivacyUpStatus == 2 )
                {
                    $FHEM::Automation::ShuttersControl::shutters->setLastDrive(
                        'window closed at privacy day open');
                    $FHEM::Automation::ShuttersControl::shutters->setNoDelay(1);
                    $FHEM::Automation::ShuttersControl::shutters->setDriveCmd(
                        $FHEM::Automation::ShuttersControl::shutters
                          ->getPrivacyDownPos );
                }
                else {
                    $FHEM::Automation::ShuttersControl::shutters->setLastDrive(
                        'window closed at night');
                    $FHEM::Automation::ShuttersControl::shutters->setNoDelay(1);
                    $FHEM::Automation::ShuttersControl::shutters->setDriveCmd(
                        (
                            $FHEM::Automation::ShuttersControl::shutters
                              ->getSleepPos > 0
                            ? $FHEM::Automation::ShuttersControl::shutters
                              ->getSleepPos
                            : $FHEM::Automation::ShuttersControl::shutters
                              ->getClosedPos
                        )
                    );
                }
            }
        }
        elsif (
            (
                $match =~ m{tilt}xms || ( $match =~ m{[Oo]pen|false}xms
                    && $FHEM::Automation::ShuttersControl::shutters->getSubTyp
                    eq 'twostate' )
            )
            && $FHEM::Automation::ShuttersControl::shutters->getVentilateOpen
            eq 'on'
            && $FHEM::Automation::ShuttersControl::shutters
            ->getQueryShuttersPos(
                $FHEM::Automation::ShuttersControl::shutters->getVentilatePos
            )
          )
        {
            $FHEM::Automation::ShuttersControl::shutters->setLastDrive(
                'ventilate - window open');
            $FHEM::Automation::ShuttersControl::shutters->setNoDelay(1);
            $FHEM::Automation::ShuttersControl::shutters->setDriveCmd(
                (
                    (
                        $FHEM::Automation::ShuttersControl::shutters
                          ->getShuttersPlace eq 'terrace'
                          && $FHEM::Automation::ShuttersControl::shutters
                          ->getSubTyp eq 'twostate'
                    )
                    ? $FHEM::Automation::ShuttersControl::shutters->getOpenPos
                    : $FHEM::Automation::ShuttersControl::shutters
                      ->getVentilatePos
                )
            );
        }
        elsif ($match =~ m{[Oo]pen|false}xms
            && $FHEM::Automation::ShuttersControl::shutters->getSubTyp eq
            'threestate' )
        {
            my $posValue =
              $FHEM::Automation::ShuttersControl::shutters->getStatus;
            my $setLastDrive;
            if (
                $FHEM::Automation::ShuttersControl::ascDev
                ->getAutoShuttersControlComfort eq 'on'
                and $FHEM::Automation::ShuttersControl::shutters
                ->getQueryShuttersPos(
                    $FHEM::Automation::ShuttersControl::shutters
                      ->getComfortOpenPos
                )
              )
            {
                $posValue = $FHEM::Automation::ShuttersControl::shutters
                  ->getComfortOpenPos;
                $setLastDrive = 'comfort - window open';
            }
            elsif (
                $FHEM::Automation::ShuttersControl::shutters
                ->getQueryShuttersPos(
                    $FHEM::Automation::ShuttersControl::shutters
                      ->getVentilatePos
                )
                && $FHEM::Automation::ShuttersControl::shutters
                ->getVentilateOpen eq 'on'
              )
            {
                $posValue =
                  $FHEM::Automation::ShuttersControl::shutters->getVentilatePos;
                $setLastDrive = 'ventilate - window open';
            }

            if ( defined($posValue) && $posValue ) {
                $FHEM::Automation::ShuttersControl::shutters->setLastDrive(
                    $setLastDrive);
                $FHEM::Automation::ShuttersControl::shutters->setNoDelay(1);
                $FHEM::Automation::ShuttersControl::shutters->setDriveCmd(
                    $posValue);
            }
        }
    }

    return;
}

## Sub zum steuern der Rolladen bei einem Bewohner/Roommate Event
sub EventProcessingRoommate {
    my $hash        = shift;
    my $shuttersDev = shift;
    my $events      = shift;

    my $name = $hash->{NAME};

    $FHEM::Automation::ShuttersControl::shutters->setShuttersDev($shuttersDev);
    my $reading =
      $FHEM::Automation::ShuttersControl::shutters->getRoommatesReading;

    if ( $events =~ m{$reading:\s(absent|gotosleep|asleep|awoken|home)}xms ) {
        Log3( $name, 4,
            "AutoShuttersControl ($name) - EventProcessingRoommate: "
              . $FHEM::Automation::ShuttersControl::shutters
              ->getRoommatesReading );
        Log3( $name, 4,
"AutoShuttersControl ($name) - EventProcessingRoommate: $shuttersDev und Events $events"
        );

        my $getModeUp = $FHEM::Automation::ShuttersControl::shutters->getModeUp;
        my $getModeDown =
          $FHEM::Automation::ShuttersControl::shutters->getModeDown;
        my $getRoommatesStatus =
          $FHEM::Automation::ShuttersControl::shutters->getRoommatesStatus;
        my $getRoommatesLastStatus =
          $FHEM::Automation::ShuttersControl::shutters->getRoommatesLastStatus;
        my $event    = $1;
        my $posValue = $FHEM::Automation::ShuttersControl::shutters->getStatus;

        if (
            ( $event eq 'home' || $event eq 'awoken' )
            && (   $getRoommatesStatus eq 'home'
                || $getRoommatesStatus eq 'awoken' )
            && ( $FHEM::Automation::ShuttersControl::ascDev
                ->getAutoShuttersControlMorning eq 'on'
                || $FHEM::Automation::ShuttersControl::shutters->getUp eq
                'roommate' )
            && IsAfterShuttersManualBlocking($shuttersDev)
          )
        {
            Log3( $name, 4,
"AutoShuttersControl ($name) - EventProcessingRoommate_1: $shuttersDev und Events $events"
            );
            if (
                (
                    (
                        $getRoommatesLastStatus eq 'asleep'
                        && ( $FHEM::Automation::ShuttersControl::shutters
                            ->getModeUp eq 'always'
                            or $FHEM::Automation::ShuttersControl::shutters
                            ->getModeUp eq $event )
                    )
                    || (
                        $getRoommatesLastStatus eq 'awoken'
                        && ( $FHEM::Automation::ShuttersControl::shutters
                            ->getModeUp eq 'always'
                            or $FHEM::Automation::ShuttersControl::shutters
                            ->getModeUp eq $event )
                    )
                )
                && (   $FHEM::Automation::ShuttersControl::shutters->getIsDay
                    || $FHEM::Automation::ShuttersControl::shutters->getUp eq
                    'roommate' )
                && ( IsAfterShuttersTimeBlocking($shuttersDev)
                    || $FHEM::Automation::ShuttersControl::shutters->getUp eq
                    'roommate' )
              )
            {
                Log3( $name, 4,
"AutoShuttersControl ($name) - EventProcessingRoommate_2: $shuttersDev und Events $events"
                );

                if (
                    $FHEM::Automation::ShuttersControl::shutters->getIfInShading
                    && !$FHEM::Automation::ShuttersControl::shutters
                    ->getShadingManualDriveStatus
                    && $FHEM::Automation::ShuttersControl::shutters->getStatus
                    != $FHEM::Automation::ShuttersControl::shutters
                    ->getShadingPos )
                {
                    $FHEM::Automation::ShuttersControl::shutters->setLastDrive(
                        'shading in');
                    $posValue = $FHEM::Automation::ShuttersControl::shutters
                      ->getShadingPos;
                }
                elsif ( !$FHEM::Automation::ShuttersControl::shutters
                    ->getIfInShading )
                {
                    $FHEM::Automation::ShuttersControl::shutters->setLastDrive(
                        'roommate awoken');
                    $posValue =
                      $FHEM::Automation::ShuttersControl::shutters->getOpenPos;
                }

                FHEM::Automation::ShuttersControl::ShuttersCommandSet( $hash,
                    $shuttersDev, $posValue );
            }
            elsif (
                (
                       $getRoommatesLastStatus eq 'absent'
                    || $getRoommatesLastStatus eq 'gone'
                )
                && $getRoommatesStatus eq 'home'
              )
            {
                if (
                       $FHEM::Automation::ShuttersControl::shutters->getIsDay
                    && $FHEM::Automation::ShuttersControl::shutters
                    ->getIfInShading
                    && $FHEM::Automation::ShuttersControl::shutters->getStatus
                    != $FHEM::Automation::ShuttersControl::shutters
                    ->getShadingPos
                    && !$FHEM::Automation::ShuttersControl::shutters
                    ->getShadingManualDriveStatus
                    && !(
                        CheckIfShuttersWindowRecOpen($shuttersDev) == 2
                        && $FHEM::Automation::ShuttersControl::shutters
                        ->getShuttersPlace eq 'terrace'
                    )
                    && !$FHEM::Automation::ShuttersControl::shutters
                    ->getSelfDefenseState
                  )
                {
                    ShadingProcessingDriveCommand( $hash, $shuttersDev, 1 );
                }
                elsif (
                       !$FHEM::Automation::ShuttersControl::shutters->getIsDay
                    && IsAfterShuttersTimeBlocking($shuttersDev)
                    && (   $getModeDown eq 'home'
                        || $getModeDown eq 'always' )
                    && $FHEM::Automation::ShuttersControl::shutters->getDown ne
                    'roommate'
                  )
                {
                    $FHEM::Automation::ShuttersControl::shutters->setLastDrive(
                        'roommate come home');

                    if ( CheckIfShuttersWindowRecOpen($shuttersDev) == 0
                        || $FHEM::Automation::ShuttersControl::shutters
                        ->getVentilateOpen eq 'off' )
                    {
                        $posValue = (
                            $FHEM::Automation::ShuttersControl::shutters
                              ->getSleepPos > 0
                            ? $FHEM::Automation::ShuttersControl::shutters
                              ->getSleepPos
                            : (
                                $FHEM::Automation::ShuttersControl::shutters
                                  ->getSleepPos > 0
                                ? $FHEM::Automation::ShuttersControl::shutters
                                  ->getSleepPos
                                : $FHEM::Automation::ShuttersControl::shutters
                                  ->getClosedPos
                            )
                        );
                    }
                    else {
                        $posValue = $FHEM::Automation::ShuttersControl::shutters
                          ->getVentilatePos;
                        $FHEM::Automation::ShuttersControl::shutters
                          ->setLastDrive(
                            $FHEM::Automation::ShuttersControl::shutters
                              ->getLastDrive . ' - ventilate mode' );
                    }

                    FHEM::Automation::ShuttersControl::ShuttersCommandSet(
                        $hash, $shuttersDev, $posValue );
                }
                elsif (
                    (
                        $FHEM::Automation::ShuttersControl::shutters->getIsDay
                        || $FHEM::Automation::ShuttersControl::shutters->getUp
                        eq 'roommate'
                    )
                    && IsAfterShuttersTimeBlocking($shuttersDev)
                    && (   $getModeUp eq 'home'
                        || $getModeUp eq 'always' )
                    && !$FHEM::Automation::ShuttersControl::shutters
                    ->getIfInShading
                  )
                {
                    if ( $FHEM::Automation::ShuttersControl::shutters
                        ->getIfInShading
                        && !$FHEM::Automation::ShuttersControl::shutters
                        ->getShadingManualDriveStatus
                        && $FHEM::Automation::ShuttersControl::shutters
                        ->getStatus ==
                        $FHEM::Automation::ShuttersControl::shutters->getOpenPos
                        && $FHEM::Automation::ShuttersControl::shutters
                        ->getShadingMode eq 'home' )
                    {
                        $FHEM::Automation::ShuttersControl::shutters
                          ->setLastDrive('shading in');
                        FHEM::Automation::ShuttersControl::ShuttersCommandSet(
                            $hash,
                            $shuttersDev,
                            $FHEM::Automation::ShuttersControl::shutters
                              ->getShadingPos
                        );
                    }
                    elsif (
                        (
                            !$FHEM::Automation::ShuttersControl::shutters
                            ->getIfInShading
                            || $FHEM::Automation::ShuttersControl::shutters
                            ->getShadingMode eq 'absent'
                        )
                        && ( $FHEM::Automation::ShuttersControl::shutters
                            ->getStatus ==
                            $FHEM::Automation::ShuttersControl::shutters
                            ->getClosedPos
                            || $FHEM::Automation::ShuttersControl::shutters
                            ->getStatus ==
                            $FHEM::Automation::ShuttersControl::shutters
                            ->getSleepPos
                            || $FHEM::Automation::ShuttersControl::shutters
                            ->getStatus ==
                            $FHEM::Automation::ShuttersControl::shutters
                            ->getShadingPos )
                      )
                    {
                        $FHEM::Automation::ShuttersControl::shutters
                          ->setLastDrive(
                            (
                                (
                                    $FHEM::Automation::ShuttersControl::shutters
                                      ->getStatus ==
                                      $FHEM::Automation::ShuttersControl::shutters
                                      ->getClosedPos
                                      || $FHEM::Automation::ShuttersControl::shutters
                                      ->getStatus ==
                                      $FHEM::Automation::ShuttersControl::shutters
                                      ->getSleepPos
                                )
                                ? 'roommate come home'
                                : 'shading out'
                            )
                          );

                        FHEM::Automation::ShuttersControl::ShuttersCommandSet(
                            $hash,
                            $shuttersDev,
                            $FHEM::Automation::ShuttersControl::shutters
                              ->getOpenPos
                        );
                    }
                }
            }
        }
        elsif (
            ( $event eq 'gotosleep' || $event eq 'asleep' )
            && $FHEM::Automation::ShuttersControl::shutters->getModeDown ne
                'absent'
            && ( $FHEM::Automation::ShuttersControl::ascDev
                ->getAutoShuttersControlEvening eq 'on'
                || $FHEM::Automation::ShuttersControl::shutters->getDown eq
                'roommate' )
            && ( IsAfterShuttersManualBlocking($shuttersDev)
                || $FHEM::Automation::ShuttersControl::shutters->getDown eq
                'roommate' )
          )
        {
            $FHEM::Automation::ShuttersControl::shutters->setLastDrive(
                'roommate asleep');

            if ( CheckIfShuttersWindowRecOpen($shuttersDev) == 0
                || $FHEM::Automation::ShuttersControl::shutters
                ->getVentilateOpen eq 'off' )
            {
                $posValue = (
                    $FHEM::Automation::ShuttersControl::shutters->getSleepPos >
                      0
                    ? $FHEM::Automation::ShuttersControl::shutters->getSleepPos
                    : $FHEM::Automation::ShuttersControl::shutters->getClosedPos
                );
            }
            else {
                $posValue =
                  $FHEM::Automation::ShuttersControl::shutters->getVentilatePos;
                $FHEM::Automation::ShuttersControl::shutters->setLastDrive(
                    $FHEM::Automation::ShuttersControl::shutters->getLastDrive
                      . ' - ventilate mode' );
            }

            FHEM::Automation::ShuttersControl::ShuttersCommandSet( $hash,
                $shuttersDev, $posValue );
        }
        elsif (
            $event eq 'absent'
            && (  !$FHEM::Automation::ShuttersControl::shutters->getIsDay
                || $FHEM::Automation::ShuttersControl::shutters->getDown eq
                'roommate'
                || $FHEM::Automation::ShuttersControl::shutters->getShadingMode
                eq 'absent'
                || $FHEM::Automation::ShuttersControl::shutters->getModeUp eq
                'absent'
                || $FHEM::Automation::ShuttersControl::shutters->getModeDown eq
                'absent' )
          )
        {
            Log3( $name, 4,
"AutoShuttersControl ($name) - EventProcessingRoommate absent: $shuttersDev"
            );

            if (
                (
                       $FHEM::Automation::ShuttersControl::shutters->getIsDay
                    || $FHEM::Automation::ShuttersControl::shutters->getUp eq
                    'roommate'
                )
                && $FHEM::Automation::ShuttersControl::shutters->getIfInShading
                && !$FHEM::Automation::ShuttersControl::shutters
                ->getQueryShuttersPos(
                    $FHEM::Automation::ShuttersControl::shutters->getShadingPos
                )
                && $FHEM::Automation::ShuttersControl::shutters->getShadingMode
                eq 'absent'
              )
            {
                Log3( $name, 4,
"AutoShuttersControl ($name) - EventProcessingRoommate Shading: $shuttersDev"
                );

                $FHEM::Automation::ShuttersControl::shutters->setLastDrive(
                    'shading in');
                FHEM::Automation::ShuttersControl::ShuttersCommandSet(
                    $hash,
                    $shuttersDev,
                    $FHEM::Automation::ShuttersControl::shutters->getShadingPos
                );
            }
            elsif (
                (
                      !$FHEM::Automation::ShuttersControl::shutters->getIsDay
                    || $FHEM::Automation::ShuttersControl::shutters->getDown eq
                    'roommate'
                )
                && $getModeDown eq 'absent'
                && $getRoommatesStatus eq 'absent'
              )
            {
                Log3( $name, 4,
"AutoShuttersControl ($name) - EventProcessingRoommate Down: $shuttersDev"
                );

                $FHEM::Automation::ShuttersControl::shutters->setLastDrive(
                    'roommate absent');
                FHEM::Automation::ShuttersControl::ShuttersCommandSet(
                    $hash,
                    $shuttersDev,
                    $FHEM::Automation::ShuttersControl::shutters->getClosedPos
                );
            }
            elsif ($FHEM::Automation::ShuttersControl::shutters->getIsDay
                && $FHEM::Automation::ShuttersControl::shutters->getModeUp eq
                'absent'
                && $getRoommatesStatus eq 'absent' )
            {
                Log3( $name, 4,
"AutoShuttersControl ($name) - EventProcessingRoommate Up: $shuttersDev"
                );

                $FHEM::Automation::ShuttersControl::shutters->setLastDrive(
                    'roommate absent');
                FHEM::Automation::ShuttersControl::ShuttersCommandSet( $hash,
                    $shuttersDev,
                    $FHEM::Automation::ShuttersControl::shutters->getOpenPos );
            }

            Log3( $name, 4,
"AutoShuttersControl ($name) - EventProcessingRoommate NICHTS: $shuttersDev"
            );
        }
    }

    return;
}

sub EventProcessingResidents {
    my $hash   = shift;
    my $device = shift;
    my $events = shift;

    my $name = $device;
    my $reading =
      $FHEM::Automation::ShuttersControl::ascDev->getResidentsReading;
    my $getResidentsLastStatus =
      $FHEM::Automation::ShuttersControl::ascDev->getResidentsLastStatus;

    if ( $events =~ m{$reading:\s((?:pet_[a-z]+)|(?:absent))}xms ) {
        for my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
            $FHEM::Automation::ShuttersControl::shutters->setShuttersDev(
                $shuttersDev);

            my $getModeUp =
              $FHEM::Automation::ShuttersControl::shutters->getModeUp;
            my $getModeDown =
              $FHEM::Automation::ShuttersControl::shutters->getModeDown;
            $FHEM::Automation::ShuttersControl::shutters->setHardLockOut('off');

            if (
                $FHEM::Automation::ShuttersControl::ascDev->getSelfDefense eq
                'on'
                && $FHEM::Automation::ShuttersControl::shutters
                ->getSelfDefenseMode ne 'off'
                || $getModeDown eq 'absent'
#                     || $getModeDown eq 'always' )       Wird zu Testzwecken auskommentiert, siehe #90 Github
                || ( $FHEM::Automation::ShuttersControl::shutters
                    ->getShadingMode eq 'absent'
                    && $FHEM::Automation::ShuttersControl::shutters
                    ->getRoommatesStatus eq 'none' )
                || ( $FHEM::Automation::ShuttersControl::shutters
                    ->getShadingMode eq 'home'
                    && $FHEM::Automation::ShuttersControl::shutters
                    ->getRoommatesStatus eq 'none' )
              )
            {
                if (
                    $FHEM::Automation::ShuttersControl::ascDev->getSelfDefense
                    eq 'on'
                    && (
                        $FHEM::Automation::ShuttersControl::shutters
                        ->getSelfDefenseMode eq 'absent'
                        || ( CheckIfShuttersWindowRecOpen($shuttersDev) == 2
                            && $FHEM::Automation::ShuttersControl::shutters
                            ->getSelfDefenseMode eq 'gone'
                            && $FHEM::Automation::ShuttersControl::shutters
                            ->getShuttersPlace eq 'terrace'
                            && $FHEM::Automation::ShuttersControl::shutters
                            ->getSelfDefenseMode ne 'off' )
                    )
                  )
                {
                    $FHEM::Automation::ShuttersControl::shutters->setLastDrive(
                        'selfDefense absent active');
                    $FHEM::Automation::ShuttersControl::shutters
                      ->setSelfDefenseAbsent( 0, 1 )
                      ; # der erste Wert ist ob der timer schon läuft, der zweite ist ob self defense aktiv ist durch die Bedingungen
                    $FHEM::Automation::ShuttersControl::shutters
                      ->setSelfDefenseState(1);
                    $FHEM::Automation::ShuttersControl::shutters->setDriveCmd(
                        $FHEM::Automation::ShuttersControl::shutters
                          ->getClosedPos );
                }
                elsif ($FHEM::Automation::ShuttersControl::shutters->getIsDay
                    && $FHEM::Automation::ShuttersControl::shutters
                    ->getIfInShading
                    && $FHEM::Automation::ShuttersControl::shutters
                    ->getShadingMode eq 'absent'
                    && $FHEM::Automation::ShuttersControl::shutters
                    ->getRoommatesStatus eq 'none' )
                {
                    ShadingProcessingDriveCommand( $hash, $shuttersDev, 1 );
                }
                elsif (
                    $FHEM::Automation::ShuttersControl::shutters
                    ->getShadingMode eq 'home'
                    && $FHEM::Automation::ShuttersControl::shutters->getIsDay
                    && $FHEM::Automation::ShuttersControl::shutters
                    ->getIfInShading
                    && $FHEM::Automation::ShuttersControl::shutters->getStatus
                    == $FHEM::Automation::ShuttersControl::shutters
                    ->getShadingPos
                    && $FHEM::Automation::ShuttersControl::shutters
                    ->getRoommatesStatus eq 'none'
                    && !(
                        CheckIfShuttersWindowRecOpen($shuttersDev) == 2
                        && $FHEM::Automation::ShuttersControl::shutters
                        ->getShuttersPlace eq 'terrace'
                    )
                    && !$FHEM::Automation::ShuttersControl::shutters
                    ->getSelfDefenseState
                  )
                {
                    $FHEM::Automation::ShuttersControl::shutters->setLastDrive(
                        'shading out');
                    $FHEM::Automation::ShuttersControl::shutters->setDriveCmd(
                        $FHEM::Automation::ShuttersControl::shutters
                          ->getLastPos );
                }
                elsif ( $getModeDown eq 'absent'        # || $getModeDown eq 'always' )   Wird zu Testzwecken auskommentiert, siehe #90 Github
                    && !$FHEM::Automation::ShuttersControl::shutters->getIsDay
                    && IsAfterShuttersTimeBlocking($shuttersDev)
                    && $FHEM::Automation::ShuttersControl::shutters
                    ->getRoommatesStatus eq 'none' )
                {
                    $FHEM::Automation::ShuttersControl::shutters->setLastDrive(
                        'residents absent');
                    $FHEM::Automation::ShuttersControl::shutters->setDriveCmd(
                        $FHEM::Automation::ShuttersControl::shutters
                          ->getClosedPos );
                }
            }
        }
    }
    elsif ($events =~ m{$reading:\s(gone)}xms
        && $FHEM::Automation::ShuttersControl::ascDev->getSelfDefense eq 'on' )
    {
        for my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
            $FHEM::Automation::ShuttersControl::shutters->setShuttersDev(
                $shuttersDev);
            $FHEM::Automation::ShuttersControl::shutters->setHardLockOut('off');
            if ( $FHEM::Automation::ShuttersControl::shutters
                ->getSelfDefenseMode ne 'off' )
            {

                $FHEM::Automation::ShuttersControl::shutters->setLastDrive(
                    'selfDefense gone active');
                $FHEM::Automation::ShuttersControl::shutters
                  ->setSelfDefenseState(1);
                $FHEM::Automation::ShuttersControl::shutters->setDriveCmd(
                    $FHEM::Automation::ShuttersControl::shutters->getClosedPos
                );
            }
        }
    }
    elsif (
        $events =~ m{$reading:\s((?:[a-z]+_)?home)}xms
        && (   $getResidentsLastStatus eq 'absent'
            || $getResidentsLastStatus eq 'gone'
            || $getResidentsLastStatus eq 'asleep'
            || $getResidentsLastStatus eq 'awoken' )
      )
    {
        for my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
            $FHEM::Automation::ShuttersControl::shutters->setShuttersDev(
                $shuttersDev);
            my $getModeUp =
              $FHEM::Automation::ShuttersControl::shutters->getModeUp;
            my $getModeDown =
              $FHEM::Automation::ShuttersControl::shutters->getModeDown;

            if (
                (
                    $FHEM::Automation::ShuttersControl::shutters->getStatus !=
                    $FHEM::Automation::ShuttersControl::shutters->getClosedPos
                    || $FHEM::Automation::ShuttersControl::shutters->getStatus
                    != $FHEM::Automation::ShuttersControl::shutters->getSleepPos
                )
                && !$FHEM::Automation::ShuttersControl::shutters->getIsDay
                && $FHEM::Automation::ShuttersControl::shutters
                ->getRoommatesStatus eq 'none'
                && (   $getModeDown eq 'home'
                    || $getModeDown eq 'always' )
                && $getResidentsLastStatus ne 'asleep'
                && $getResidentsLastStatus ne 'awoken'
                && IsAfterShuttersTimeBlocking($shuttersDev)
                && !$FHEM::Automation::ShuttersControl::shutters
                ->getSelfDefenseState
              )
            {
                $FHEM::Automation::ShuttersControl::shutters->setLastDrive(
                    'residents come home');
                $FHEM::Automation::ShuttersControl::shutters->setDriveCmd(
                    (
                        $FHEM::Automation::ShuttersControl::shutters
                          ->getSleepPos > 0
                        ? $FHEM::Automation::ShuttersControl::shutters
                          ->getSleepPos
                        : $FHEM::Automation::ShuttersControl::shutters
                          ->getClosedPos
                    )
                );
            }
            elsif (
                (
                    $FHEM::Automation::ShuttersControl::shutters
                    ->getShadingMode eq 'home'
                    || $FHEM::Automation::ShuttersControl::shutters
                    ->getShadingMode eq 'always'
                )
                && $FHEM::Automation::ShuttersControl::shutters->getIsDay
                && $FHEM::Automation::ShuttersControl::shutters->getIfInShading
                && $FHEM::Automation::ShuttersControl::shutters
                ->getRoommatesStatus eq 'none'
                && $FHEM::Automation::ShuttersControl::shutters->getStatus !=
                $FHEM::Automation::ShuttersControl::shutters->getShadingPos
                && !$FHEM::Automation::ShuttersControl::shutters
                ->getShadingManualDriveStatus
                && !(
                    CheckIfShuttersWindowRecOpen($shuttersDev) == 2
                    && $FHEM::Automation::ShuttersControl::shutters
                    ->getShuttersPlace eq 'terrace'
                )
                && !$FHEM::Automation::ShuttersControl::shutters
                ->getSelfDefenseState
              )
            {
                ShadingProcessingDriveCommand( $hash, $shuttersDev, 1 );
            }
            elsif (
                $FHEM::Automation::ShuttersControl::shutters->getShadingMode eq
                'absent'
                && $FHEM::Automation::ShuttersControl::shutters->getIsDay
                && $FHEM::Automation::ShuttersControl::shutters->getIfInShading
                && $FHEM::Automation::ShuttersControl::shutters->getStatus ==
                $FHEM::Automation::ShuttersControl::shutters->getShadingPos
                && $FHEM::Automation::ShuttersControl::shutters
                ->getRoommatesStatus eq 'none'
                && !$FHEM::Automation::ShuttersControl::shutters
                ->getShadingManualDriveStatus
                && !(
                    CheckIfShuttersWindowRecOpen($shuttersDev) == 2
                    && $FHEM::Automation::ShuttersControl::shutters
                    ->getShuttersPlace eq 'terrace'
                )
                && !$FHEM::Automation::ShuttersControl::shutters
                ->getSelfDefenseState
              )
            {
                $FHEM::Automation::ShuttersControl::shutters->setLastDrive(
                    'shading out');
                $FHEM::Automation::ShuttersControl::shutters->setDriveCmd(
                    $FHEM::Automation::ShuttersControl::shutters->getLastPos );
            }
            elsif (
                $FHEM::Automation::ShuttersControl::ascDev->getSelfDefense eq
                'on'
                && $FHEM::Automation::ShuttersControl::shutters
                ->getSelfDefenseMode ne 'off'
                && !$FHEM::Automation::ShuttersControl::shutters->getIfInShading
                && (   $getResidentsLastStatus eq 'gone'
                    || $getResidentsLastStatus eq 'absent' )
                && $FHEM::Automation::ShuttersControl::shutters
                ->getSelfDefenseState
              )
            {
                RemoveInternalTimer(
                    $FHEM::Automation::ShuttersControl::shutters
                      ->getSelfDefenseAbsentTimerhash )
                  if ( $getResidentsLastStatus eq 'absent'
                    && $FHEM::Automation::ShuttersControl::ascDev
                    ->getSelfDefense eq 'on'
                    && $FHEM::Automation::ShuttersControl::shutters
                    ->getSelfDefenseMode ne 'off'
                    && !$FHEM::Automation::ShuttersControl::shutters
                    ->getSelfDefenseAbsent
                    && $FHEM::Automation::ShuttersControl::shutters
                    ->getSelfDefenseAbsentTimerrun );

                if (
                    (
                        $FHEM::Automation::ShuttersControl::shutters->getStatus
                        == $FHEM::Automation::ShuttersControl::shutters
                        ->getClosedPos
                        || $FHEM::Automation::ShuttersControl::shutters
                        ->getStatus ==
                        $FHEM::Automation::ShuttersControl::shutters
                        ->getSleepPos
                    )
                    && $FHEM::Automation::ShuttersControl::shutters->getIsDay
                  )
                {
                    $FHEM::Automation::ShuttersControl::shutters
                      ->setHardLockOut('on')
                      if (
                        CheckIfShuttersWindowRecOpen($shuttersDev) == 2
                        && $FHEM::Automation::ShuttersControl::shutters
                        ->getShuttersPlace eq 'terrace'
                        && (   $getModeUp eq 'absent'
                            || $getModeUp eq 'off' )
                      );

                    $FHEM::Automation::ShuttersControl::shutters
                      ->setSelfDefenseState(0);
                    $FHEM::Automation::ShuttersControl::shutters->setLastDrive(
                        'selfDefense inactive');
                    $FHEM::Automation::ShuttersControl::shutters->setDriveCmd(
                        (
                            $FHEM::Automation::ShuttersControl::shutters
                              ->getPrivacyDownStatus == 2
                            ? $FHEM::Automation::ShuttersControl::shutters
                              ->getPrivacyDownPos
                            : $FHEM::Automation::ShuttersControl::shutters
                              ->getOpenPos
                        )
                    );
                }
            }
            elsif (
                (
                    $FHEM::Automation::ShuttersControl::shutters->getStatus ==
                    $FHEM::Automation::ShuttersControl::shutters->getClosedPos
                    || $FHEM::Automation::ShuttersControl::shutters->getStatus
                    == $FHEM::Automation::ShuttersControl::shutters->getSleepPos
                )
                && $FHEM::Automation::ShuttersControl::shutters->getIsDay
                && $FHEM::Automation::ShuttersControl::shutters
                ->getRoommatesStatus eq 'none'
                && (   $getModeUp eq 'home'
                    || $getModeUp eq 'always' )
                && IsAfterShuttersTimeBlocking($shuttersDev)
                && !$FHEM::Automation::ShuttersControl::shutters->getIfInShading
                && !$FHEM::Automation::ShuttersControl::shutters
                ->getSelfDefenseState
              )
            {
                if (   $getResidentsLastStatus eq 'asleep'
                    || $getResidentsLastStatus eq 'awoken' )
                {
                    $FHEM::Automation::ShuttersControl::shutters->setLastDrive(
                        'residents awoken');
                }
                else {
                    $FHEM::Automation::ShuttersControl::shutters->setLastDrive(
                        'residents home');
                }
                $FHEM::Automation::ShuttersControl::shutters->setDriveCmd(
                    $FHEM::Automation::ShuttersControl::shutters->getOpenPos );
            }
        }
    }

    return;
}

sub EventProcessingRain {

    #### Ist noch nicht fertig, es fehlt noch das verzögerte Prüfen auf erhalten bleiben des getriggerten Wertes.

    my $hash   = shift;
    my $device = shift;
    my $events = shift;

    my $name = $device;
    my $reading =
      $FHEM::Automation::ShuttersControl::ascDev->getRainSensorReading
      // 'none';

    if ( $events =~ m{$reading:\s(\d+(\.\d+)?|rain|dry)}xms ) {
        my $val;
        my $triggerMax =
          $FHEM::Automation::ShuttersControl::ascDev->getRainTriggerMax;
        my $triggerMin =
          $FHEM::Automation::ShuttersControl::ascDev->getRainTriggerMin;
        my $closedPos = $FHEM::Automation::ShuttersControl::ascDev
          ->getRainSensorShuttersClosedPos;

        if    ( $1 eq 'rain' ) { $val = $triggerMax + 1 }
        elsif ( $1 eq 'dry' )  { $val = $triggerMin }
        else                   { $val = $1 }

        RainProtection( $hash, $val, $triggerMax, $triggerMin, $closedPos );
    }

    return;
}

sub RainProtection {
    my ( $hash, $val, $triggerMax, $triggerMin, $closedPos ) = @_;

    for my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
        $FHEM::Automation::ShuttersControl::shutters->setShuttersDev(
            $shuttersDev);

        next
          if (
            $FHEM::Automation::ShuttersControl::shutters->getRainProtection eq
            'off' );

        if (   $val > $triggerMax
            && $FHEM::Automation::ShuttersControl::shutters->getStatus !=
            $closedPos
            && $FHEM::Automation::ShuttersControl::shutters
            ->getRainProtectionStatus eq 'unprotected' )
        {
            $FHEM::Automation::ShuttersControl::shutters->setLastDrive(
                'rain protected');
            $FHEM::Automation::ShuttersControl::shutters->setDriveCmd(
                $closedPos);
            $FHEM::Automation::ShuttersControl::shutters
              ->setRainProtectionStatus('protected');
        }
        elsif ( ( $val == 0 || $val < $triggerMin )
            && $FHEM::Automation::ShuttersControl::shutters->getStatus ==
            $closedPos
            && IsAfterShuttersManualBlocking($shuttersDev)
            && $FHEM::Automation::ShuttersControl::shutters
            ->getRainProtectionStatus eq 'protected' )
        {
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
    }

    return;
}

sub EventProcessingWind {
    my $hash        = shift;
    my $shuttersDev = shift;
    my $events      = shift;

    my $name = $hash->{NAME};
    $FHEM::Automation::ShuttersControl::shutters->setShuttersDev($shuttersDev);

    my $reading =
      $FHEM::Automation::ShuttersControl::ascDev->getWindSensorReading
      // 'none';
    if ( $events =~ m{$reading:\s(\d+(\.\d+)?)}xms ) {
        for my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
            $FHEM::Automation::ShuttersControl::shutters->setShuttersDev(
                $shuttersDev);

            FHEM::Automation::ShuttersControl::ASC_Debug(
                    'EventProcessingWind: '
                  . $FHEM::Automation::ShuttersControl::shutters->getShuttersDev
                  . ' - WindProtection1: '
                  . $FHEM::Automation::ShuttersControl::shutters
                  ->getWindProtectionStatus
                  . ' WindMax1: '
                  . $FHEM::Automation::ShuttersControl::shutters->getWindMax
                  . ' WindMin1: '
                  . $FHEM::Automation::ShuttersControl::shutters->getWindMin
                  . ' Bekommender Wert1: '
                  . $1 );

            next
              if (
                (
                    CheckIfShuttersWindowRecOpen($shuttersDev) != 0
                    && $FHEM::Automation::ShuttersControl::shutters
                    ->getShuttersPlace eq 'terrace'
                )
                || $FHEM::Automation::ShuttersControl::shutters
                ->getWindProtection eq 'off'
              );

            if (   $1 > $FHEM::Automation::ShuttersControl::shutters->getWindMax
                && $FHEM::Automation::ShuttersControl::shutters
                ->getWindProtectionStatus eq 'unprotected' )
            {
                $FHEM::Automation::ShuttersControl::shutters->setLastDrive(
                    'wind protected');
                $FHEM::Automation::ShuttersControl::shutters->setDriveCmd(
                    $FHEM::Automation::ShuttersControl::shutters->getWindPos );
                $FHEM::Automation::ShuttersControl::shutters
                  ->setWindProtectionStatus('protected');
            }
            elsif (
                   $1 < $FHEM::Automation::ShuttersControl::shutters->getWindMin
                && $FHEM::Automation::ShuttersControl::shutters
                ->getWindProtectionStatus eq 'protected' )
            {
                $FHEM::Automation::ShuttersControl::shutters->setLastDrive(
                    'wind un-protected');
                $FHEM::Automation::ShuttersControl::shutters->setDriveCmd(
                    (
                          $FHEM::Automation::ShuttersControl::shutters->getIsDay
                        ? $FHEM::Automation::ShuttersControl::shutters
                          ->getLastPos
                        : (
                            $FHEM::Automation::ShuttersControl::shutters
                              ->getPrivacyDownStatus == 2
                            ? $FHEM::Automation::ShuttersControl::shutters
                              ->getPrivacyDownPos
                            : (
                                $FHEM::Automation::ShuttersControl::shutters
                                  ->getSleepPos > 0
                                ? $FHEM::Automation::ShuttersControl::shutters
                                  ->getSleepPos
                                : $FHEM::Automation::ShuttersControl::shutters
                                  ->getClosedPos
                            )
                        )
                    )
                );
                $FHEM::Automation::ShuttersControl::shutters
                  ->setWindProtectionStatus('unprotected');
            }

            FHEM::Automation::ShuttersControl::ASC_Debug(
                    'EventProcessingWind: '
                  . $FHEM::Automation::ShuttersControl::shutters->getShuttersDev
                  . ' - WindProtection2: '
                  . $FHEM::Automation::ShuttersControl::shutters
                  ->getWindProtectionStatus
                  . ' WindMax2: '
                  . $FHEM::Automation::ShuttersControl::shutters->getWindMax
                  . ' WindMin2: '
                  . $FHEM::Automation::ShuttersControl::shutters->getWindMin
                  . ' Bekommender Wert2: '
                  . $1 );
        }
    }

    return;
}
##########

sub EventProcessingBrightness {
    my $hash        = shift;
    my $shuttersDev = shift;
    my $events      = shift;

    my $name = $hash->{NAME};
    $FHEM::Automation::ShuttersControl::shutters->setShuttersDev($shuttersDev);

    FHEM::Automation::ShuttersControl::ASC_Debug( 'EventProcessingBrightness: '
          . $FHEM::Automation::ShuttersControl::shutters->getShuttersDev
          . ' - Event von einem Helligkeitssensor erkannt. Verarbeitung läuft. Sollten keine weitere Meldungen aus der Funktion kommen, so befindet sich die aktuelle Zeit nicht innerhalb der Verarbeitungszeit für Sunset oder Sunrise'
    );

    return EventProcessingShadingBrightness( $hash, $shuttersDev, $events )
      if (
        (
            $FHEM::Automation::ShuttersControl::shutters->getDown ne
            'brightness'
            && $FHEM::Automation::ShuttersControl::shutters->getUp ne
            'brightness'
        )
        || (
            (
                $FHEM::Automation::ShuttersControl::shutters->getDown eq
                'brightness'
                || $FHEM::Automation::ShuttersControl::shutters->getUp eq
                'brightness'
            )
            && (
                (
                    (
                        (
                            int( gettimeofday() / 86400 ) == int(
                                computeAlignTime(
                                    '24:00',
                                    $FHEM::Automation::ShuttersControl::shutters
                                      ->getTimeUpEarly
                                ) / 86400
                            )
                            && (
                                !IsWe()
                                || (
                                    IsWe()
                                    && $FHEM::Automation::ShuttersControl::ascDev
                                    ->getSunriseTimeWeHoliday eq 'off'
                                    || (
                                        $FHEM::Automation::ShuttersControl::ascDev
                                        ->getSunriseTimeWeHoliday eq 'on'
                                        && $FHEM::Automation::ShuttersControl::shutters
                                        ->getTimeUpWeHoliday eq '01:25' )
                                )
                            )
                        )
                        || (
                            int( gettimeofday() / 86400 ) == int(
                                computeAlignTime(
                                    '24:00',
                                    $FHEM::Automation::ShuttersControl::shutters
                                      ->getTimeUpWeHoliday
                                ) / 86400
                            )
                            && IsWe()
                            && $FHEM::Automation::ShuttersControl::ascDev
                            ->getSunriseTimeWeHoliday eq 'on'
                            && $FHEM::Automation::ShuttersControl::shutters
                            ->getTimeUpWeHoliday ne '01:25'
                        )
                    )
                    && int( gettimeofday() / 86400 ) == int(
                        computeAlignTime(
                            '24:00',
                            $FHEM::Automation::ShuttersControl::shutters
                              ->getTimeUpLate
                        ) / 86400
                    )

                    || (
                        (
                            int( gettimeofday() / 86400 ) != int(
                                computeAlignTime(
                                    '24:00',
                                    $FHEM::Automation::ShuttersControl::shutters
                                      ->getTimeUpEarly
                                ) / 86400
                            )
                            && (
                                !IsWe()
                                || (
                                    IsWe()
                                    && $FHEM::Automation::ShuttersControl::ascDev
                                    ->getSunriseTimeWeHoliday eq 'off'
                                    || (
                                        $FHEM::Automation::ShuttersControl::ascDev
                                        ->getSunriseTimeWeHoliday eq 'on'
                                        && $FHEM::Automation::ShuttersControl::shutters
                                        ->getTimeUpWeHoliday eq '01:25' )
                                )
                            )
                        )
                        || (
                            int( gettimeofday() / 86400 ) != int(
                                computeAlignTime(
                                    '24:00',
                                    $FHEM::Automation::ShuttersControl::shutters
                                      ->getTimeUpWeHoliday
                                ) / 86400
                            )
                            && IsWe()
                            && $FHEM::Automation::ShuttersControl::ascDev
                            ->getSunriseTimeWeHoliday eq 'on'
                            && $FHEM::Automation::ShuttersControl::shutters
                            ->getTimeUpWeHoliday ne '01:25'
                        )
                    )
                    && int( gettimeofday() / 86400 ) != int(
                        computeAlignTime(
                            '24:00',
                            $FHEM::Automation::ShuttersControl::shutters
                              ->getTimeUpLate
                        ) / 86400
                    )
                )
                && (
                    (
                        int( gettimeofday() / 86400 ) == int(
                            computeAlignTime(
                                '24:00',
                                $FHEM::Automation::ShuttersControl::shutters
                                  ->getTimeDownEarly
                            ) / 86400
                        )
                        && int( gettimeofday() / 86400 ) == int(
                            computeAlignTime(
                                '24:00',
                                $FHEM::Automation::ShuttersControl::shutters
                                  ->getTimeDownLate
                            ) / 86400
                        )
                    )
                    || (
                        int( gettimeofday() / 86400 ) != int(
                            computeAlignTime(
                                '24:00',
                                $FHEM::Automation::ShuttersControl::shutters
                                  ->getTimeDownEarly
                            ) / 86400
                        )
                        && int( gettimeofday() / 86400 ) != int(
                            computeAlignTime(
                                '24:00',
                                $FHEM::Automation::ShuttersControl::shutters
                                  ->getTimeDownLate
                            ) / 86400
                        )
                    )
                )
            )
        )
      );

    FHEM::Automation::ShuttersControl::ASC_Debug( 'EventProcessingBrightness: '
          . $FHEM::Automation::ShuttersControl::shutters->getShuttersDev
          . ' - Die aktuelle Zeit befindet sich innerhalb der Sunset/Sunrise Brightness Verarbeitungszeit. Also zwischen Time Early und Time Late'
    );

    my $reading =
      $FHEM::Automation::ShuttersControl::shutters->getBrightnessReading;
    if ( $events =~ m{$reading:\s(\d+(\.\d+)?)}xms ) {
        my $brightnessMinVal;
        if ( $FHEM::Automation::ShuttersControl::shutters->getBrightnessMinVal >
            -2 )
        {
            $brightnessMinVal =
              $FHEM::Automation::ShuttersControl::shutters->getBrightnessMinVal;
        }
        else {
            $brightnessMinVal =
              $FHEM::Automation::ShuttersControl::ascDev->getBrightnessMinVal;
        }

        my $brightnessMaxVal;
        if ( $FHEM::Automation::ShuttersControl::shutters->getBrightnessMaxVal >
            -2 )
        {
            $brightnessMaxVal =
              $FHEM::Automation::ShuttersControl::shutters->getBrightnessMaxVal;
        }
        else {
            $brightnessMaxVal =
              $FHEM::Automation::ShuttersControl::ascDev->getBrightnessMaxVal;
        }

        my $brightnessPrivacyUpVal =
          $FHEM::Automation::ShuttersControl::shutters
          ->getPrivacyUpBrightnessVal;
        my $brightnessPrivacyDownVal =
          $FHEM::Automation::ShuttersControl::shutters
          ->getPrivacyDownBrightnessVal;

        FHEM::Automation::ShuttersControl::ASC_Debug(
                'EventProcessingBrightness: '
              . $FHEM::Automation::ShuttersControl::shutters->getShuttersDev
              . ' - Es wird geprüft ob Sunset oder Sunrise gefahren werden soll und der aktuelle übergebene Brightness-Wert: '
              . $1
              . ' Größer dem eingestellten Sunrise-Wert: '
              . $brightnessMaxVal
              . ' oder kleiner dem eingestellten Sunset-Wert: '
              . $brightnessMinVal
              . ' ist. Werte für weitere Parameter - getUp ist: '
              . $FHEM::Automation::ShuttersControl::shutters->getUp
              . ' getDown ist: '
              . $FHEM::Automation::ShuttersControl::shutters->getDown
              . ' getSunrise ist: '
              . $FHEM::Automation::ShuttersControl::shutters->getSunrise
              . ' getSunset ist: '
              . $FHEM::Automation::ShuttersControl::shutters->getSunset );

        if (
            (
                (
                    (
                        int( gettimeofday() / 86400 ) != int(
                            computeAlignTime(
                                '24:00',
                                $FHEM::Automation::ShuttersControl::shutters
                                  ->getTimeUpEarly
                            ) / 86400
                        )
                        && (
                            !IsWe()
                            || (
                                IsWe()
                                && $FHEM::Automation::ShuttersControl::ascDev
                                ->getSunriseTimeWeHoliday eq 'off'
                                || ( $FHEM::Automation::ShuttersControl::ascDev
                                    ->getSunriseTimeWeHoliday eq 'on'
                                    && $FHEM::Automation::ShuttersControl::shutters
                                    ->getTimeUpWeHoliday eq '01:25' )
                            )
                        )
                    )
                    || (
                        int( gettimeofday() / 86400 ) != int(
                            computeAlignTime(
                                '24:00',
                                $FHEM::Automation::ShuttersControl::shutters
                                  ->getTimeUpWeHoliday
                            ) / 86400
                        )
                        && IsWe()
                        && $FHEM::Automation::ShuttersControl::ascDev
                        ->getSunriseTimeWeHoliday eq 'on'
                        && $FHEM::Automation::ShuttersControl::shutters
                        ->getTimeUpWeHoliday ne '01:25'
                    )
                )
                && int( gettimeofday() / 86400 ) == int(
                    computeAlignTime(
                        '24:00',
                        $FHEM::Automation::ShuttersControl::shutters
                          ->getTimeUpLate
                    ) / 86400
                )
            )
            && (
                $1 > $brightnessMaxVal
                || (   $1 > $brightnessPrivacyUpVal
                    && $FHEM::Automation::ShuttersControl::shutters
                    ->getPrivacyUpStatus == 1 )
            )
            && $FHEM::Automation::ShuttersControl::shutters->getUp eq
            'brightness'
            && !$FHEM::Automation::ShuttersControl::shutters->getSunrise
            && $FHEM::Automation::ShuttersControl::ascDev
            ->getAutoShuttersControlMorning eq 'on'
            && (
                $FHEM::Automation::ShuttersControl::ascDev->getSelfDefense eq
                'off'
                || $FHEM::Automation::ShuttersControl::shutters
                ->getSelfDefenseMode eq 'off'
                || ( $FHEM::Automation::ShuttersControl::ascDev->getSelfDefense
                    eq 'on'
                    && $FHEM::Automation::ShuttersControl::ascDev
                    ->getResidentsStatus ne 'gone' )
            )
          )
        {
            Log3( $name, 4,
"AutoShuttersControl ($shuttersDev) - EventProcessingBrightness: Steuerung für Morgens"
            );

            FHEM::Automation::ShuttersControl::ASC_Debug(
                    'EventProcessingBrightness: '
                  . $FHEM::Automation::ShuttersControl::shutters->getShuttersDev
                  . ' - Verarbeitungszeit für Sunrise wurd erkannt. Prüfe Status der Roommates'
            );

            my $homemode =
              $FHEM::Automation::ShuttersControl::shutters->getRoommatesStatus;
            $homemode =
              $FHEM::Automation::ShuttersControl::ascDev->getResidentsStatus
              if ( $homemode eq 'none' );

            if (
                $FHEM::Automation::ShuttersControl::shutters->getModeUp eq
                $homemode
                || ( $FHEM::Automation::ShuttersControl::shutters->getModeUp eq
                    'absent'
                    && $homemode eq 'gone' )
                || $FHEM::Automation::ShuttersControl::shutters->getModeUp eq
                'always'
              )
            {
                my $roommatestatus =
                  $FHEM::Automation::ShuttersControl::shutters
                  ->getRoommatesStatus;

                if (
                       $roommatestatus eq 'home'
                    || $roommatestatus eq 'awoken'
                    || $roommatestatus eq 'absent'
                    || $roommatestatus eq 'gone'
                    || $roommatestatus eq 'none'
                    && (
                        $FHEM::Automation::ShuttersControl::ascDev
                        ->getSelfDefense eq 'off'
                        || ( $FHEM::Automation::ShuttersControl::ascDev
                            ->getSelfDefense eq 'on'
                            && CheckIfShuttersWindowRecOpen($shuttersDev) == 0 )
                        || ( $FHEM::Automation::ShuttersControl::ascDev
                               ->getSelfDefense eq 'on'
                            && CheckIfShuttersWindowRecOpen($shuttersDev) != 0
                            && $FHEM::Automation::ShuttersControl::ascDev
                            ->getResidentsStatus eq 'home' )
                    )
                  )
                {

                    if (   $brightnessPrivacyUpVal > 0
                        && $1 < $brightnessMaxVal
                        && $1 > $brightnessPrivacyUpVal )
                    {
                        $FHEM::Automation::ShuttersControl::shutters
                          ->setPrivacyUpStatus(2);
                        $FHEM::Automation::ShuttersControl::shutters
                          ->setLastDrive('brightness privacy day open');
                        FHEM::Automation::ShuttersControl::ShuttersCommandSet(
                            $hash,
                            $shuttersDev,
                            $FHEM::Automation::ShuttersControl::shutters
                              ->getPrivacyUpPos
                          )
                          if (
                            $FHEM::Automation::ShuttersControl::shutters
                            ->getQueryShuttersPos(
                                $FHEM::Automation::ShuttersControl::shutters
                                  ->getPrivacyUpPos
                            )
                          );

                        FHEM::Automation::ShuttersControl::ASC_Debug(
                            'EventProcessingBrightness: '
                              . $FHEM::Automation::ShuttersControl::shutters
                              ->getShuttersDev
                              . ' - Verarbeitung für Sunrise Privacy Down. Roommatestatus korrekt zum fahren. Fahrbefehl wird an die Funktion FnFHEM::Automation::ShuttersControl::ShuttersCommandSet gesendet. Grund des fahrens: '
                              . $FHEM::Automation::ShuttersControl::shutters
                              ->getLastDrive );

                        FHEM::Automation::ShuttersControl::CreateSunRiseSetShuttersTimer( $hash, $shuttersDev );
                    }
                    else {
                        $FHEM::Automation::ShuttersControl::shutters
                          ->setLastDrive(
                            'maximum brightness threshold exceeded');
                        $FHEM::Automation::ShuttersControl::shutters
                          ->setSunrise(1);
                        $FHEM::Automation::ShuttersControl::shutters
                          ->setSunset(0);
                        $FHEM::Automation::ShuttersControl::shutters
                          ->setPrivacyUpStatus(0)
                          if ( $FHEM::Automation::ShuttersControl::shutters
                            ->getPrivacyUpStatus == 2 );
                        FHEM::Automation::ShuttersControl::ShuttersCommandSet(
                            $hash,
                            $shuttersDev,
                            $FHEM::Automation::ShuttersControl::shutters
                              ->getOpenPos
                        );

                        FHEM::Automation::ShuttersControl::ASC_Debug(
                            'EventProcessingBrightness: '
                              . $FHEM::Automation::ShuttersControl::shutters
                              ->getShuttersDev
                              . ' - Verarbeitung für Sunrise. Roommatestatus korrekt zum fahren. Fahrbefehl wird an die Funktion FnFHEM::Automation::ShuttersControl::ShuttersCommandSet gesendet. Grund des fahrens: '
                              . $FHEM::Automation::ShuttersControl::shutters
                              ->getLastDrive );
                    }
                }
                else {
                    EventProcessingShadingBrightness( $hash, $shuttersDev,
                        $events );
                    FHEM::Automation::ShuttersControl::ASC_Debug(
                        'EventProcessingBrightness: '
                          . $FHEM::Automation::ShuttersControl::shutters
                          ->getShuttersDev
                          . ' - Verarbeitung für Sunrise. Roommatestatus nicht zum hochfahren oder Fenster sind offen. Fahrbebehl bleibt aus!!! Es wird an die Event verarbeitende Beschattungsfunktion weiter gereicht'
                    );
                }
            }
        }
        elsif (
            int( gettimeofday() / 86400 ) != int(
                computeAlignTime( '24:00',
                    $FHEM::Automation::ShuttersControl::shutters
                      ->getTimeDownEarly ) / 86400
            )
            && int( gettimeofday() / 86400 ) == int(
                computeAlignTime(
                    '24:00',
                    $FHEM::Automation::ShuttersControl::shutters
                      ->getTimeDownLate
                ) / 86400
            )
            && (
                $1 < $brightnessMinVal
                || (   $1 < $brightnessPrivacyDownVal
                    && $FHEM::Automation::ShuttersControl::shutters
                    ->getPrivacyDownStatus == 1 )
            )
            && $FHEM::Automation::ShuttersControl::shutters->getDown eq
            'brightness'
            && !$FHEM::Automation::ShuttersControl::shutters->getSunset
            && IsAfterShuttersManualBlocking($shuttersDev)
            && $FHEM::Automation::ShuttersControl::ascDev
            ->getAutoShuttersControlEvening eq 'on'
          )
        {
            Log3( $name, 4,
"AutoShuttersControl ($shuttersDev) - EventProcessingBrightness: Steuerung für Abends"
            );

            FHEM::Automation::ShuttersControl::ASC_Debug(
                    'EventProcessingBrightness: '
                  . $FHEM::Automation::ShuttersControl::shutters->getShuttersDev
                  . ' - Verarbeitungszeit für Sunset wurd erkannt. Prüfe Status der Roommates'
            );

            my $homemode =
              $FHEM::Automation::ShuttersControl::shutters->getRoommatesStatus;
            $homemode =
              $FHEM::Automation::ShuttersControl::ascDev->getResidentsStatus
              if ( $homemode eq 'none' );

            if (
                $FHEM::Automation::ShuttersControl::shutters->getModeDown eq
                $homemode
                || ( $FHEM::Automation::ShuttersControl::shutters->getModeDown
                    eq 'absent'
                    && $homemode eq 'gone' )
                || $FHEM::Automation::ShuttersControl::shutters->getModeDown eq
                'always'
              )
            {
                my $posValue =
                  $FHEM::Automation::ShuttersControl::shutters->getStatus;
                my $lastDrive;

                ## Setzt den PrivacyDown Modus für die Sichtschutzfahrt auf den Status 0
                ##  1 bedeutet das PrivacyDown Timer aktiviert wurde, 2 beudet das er im privacyDown ist
                ##  also das Rollo in privacyDown Position steht und VOR der endgültigen Nachfahrt

                if (   $brightnessPrivacyDownVal > 0
                    && $1 > $brightnessMinVal
                    && $1 < $brightnessPrivacyDownVal )
                {
                    $lastDrive = 'brightness privacy night close';
                    $posValue  = (
                        (
                            !$FHEM::Automation::ShuttersControl::shutters
                              ->getQueryShuttersPos(
                                $FHEM::Automation::ShuttersControl::shutters
                                  ->getPrivacyDownPos
                              )
                        )
                        ? $FHEM::Automation::ShuttersControl::shutters
                          ->getPrivacyDownPos
                        : $FHEM::Automation::ShuttersControl::shutters
                          ->getStatus
                    );
                    $FHEM::Automation::ShuttersControl::shutters
                      ->setPrivacyDownStatus(2);

                    FHEM::Automation::ShuttersControl::ASC_Debug(
                        'EventProcessingBrightness: '
                          . $FHEM::Automation::ShuttersControl::shutters
                          ->getShuttersDev
                          . ' - Verarbeitung für Sunset Privacy Down. Roommatestatus korrekt zum fahren. Fahrbefehl wird an die Funktion FnFHEM::Automation::ShuttersControl::ShuttersCommandSet gesendet. Grund des fahrens: '
                          . $FHEM::Automation::ShuttersControl::shutters
                          ->getLastDrive );
                }
                elsif ( CheckIfShuttersWindowRecOpen($shuttersDev) == 2
                    && $FHEM::Automation::ShuttersControl::shutters->getSubTyp
                    eq 'threestate'
                    && $FHEM::Automation::ShuttersControl::ascDev
                    ->getAutoShuttersControlComfort eq 'on' )
                {
                    $posValue = $FHEM::Automation::ShuttersControl::shutters
                      ->getComfortOpenPos;
                    $lastDrive = 'minimum brightness threshold fell below';
                    $FHEM::Automation::ShuttersControl::shutters
                      ->setPrivacyDownStatus(0)
                      if ( $FHEM::Automation::ShuttersControl::shutters
                        ->getPrivacyDownStatus == 2 );
                }
                elsif ( CheckIfShuttersWindowRecOpen($shuttersDev) == 0
                    || $FHEM::Automation::ShuttersControl::shutters
                    ->getVentilateOpen eq 'off' )
                {
                    $posValue = (
                        $FHEM::Automation::ShuttersControl::shutters
                          ->getSleepPos > 0
                        ? $FHEM::Automation::ShuttersControl::shutters
                          ->getSleepPos
                        : $FHEM::Automation::ShuttersControl::shutters
                          ->getClosedPos
                    );
                    $lastDrive = 'minimum brightness threshold fell below';
                    $FHEM::Automation::ShuttersControl::shutters
                      ->setPrivacyDownStatus(0)
                      if ( $FHEM::Automation::ShuttersControl::shutters
                        ->getPrivacyDownStatus == 2 );
                }
                else {
                    $posValue = $FHEM::Automation::ShuttersControl::shutters
                      ->getVentilatePos;
                    $lastDrive = 'minimum brightness threshold fell below';
                    $FHEM::Automation::ShuttersControl::shutters
                      ->setPrivacyDownStatus(0)
                      if ( $FHEM::Automation::ShuttersControl::shutters
                        ->getPrivacyDownStatus == 2 );
                }

                $FHEM::Automation::ShuttersControl::shutters->setLastDrive(
                    $lastDrive);

                if (
                    $FHEM::Automation::ShuttersControl::shutters
                    ->getPrivacyDownStatus != 2
                  )
                {
                    $FHEM::Automation::ShuttersControl::shutters->setSunrise(0);
                    $FHEM::Automation::ShuttersControl::shutters->setSunset(1);
                }

                FHEM::Automation::ShuttersControl::ShuttersCommandSet( $hash,
                    $shuttersDev, $posValue );

                FHEM::Automation::ShuttersControl::ASC_Debug(
                    'EventProcessingBrightness: '
                      . $FHEM::Automation::ShuttersControl::shutters
                      ->getShuttersDev
                      . ' - Verarbeitung für Sunset. Roommatestatus korrekt zum fahren. Fahrbefehl wird an die Funktion FnFHEM::Automation::ShuttersControl::ShuttersCommandSet gesendet. Zielposition: '
                      . $posValue
                      . ' Grund des fahrens: '
                      . $FHEM::Automation::ShuttersControl::shutters
                      ->getLastDrive );
            }
            else {
                EventProcessingShadingBrightness( $hash, $shuttersDev, $events )
                  if ( $FHEM::Automation::ShuttersControl::shutters
                    ->getPrivacyDownStatus != 2 );

                FHEM::Automation::ShuttersControl::ASC_Debug(
                    'EventProcessingBrightness: '
                      . $FHEM::Automation::ShuttersControl::shutters
                      ->getShuttersDev
                      . ' - Verarbeitung für Sunset. Roommatestatus nicht zum runter fahren. Fahrbebehl bleibt aus!!! Es wird an die Event verarbeitende Beschattungsfunktion weiter gereicht'
                );
            }
        }
        else {
            EventProcessingShadingBrightness( $hash, $shuttersDev, $events )
              if ( $FHEM::Automation::ShuttersControl::shutters
                ->getPrivacyDownStatus != 2 );

            FHEM::Automation::ShuttersControl::ASC_Debug(
                    'EventProcessingBrightness: '
                  . $FHEM::Automation::ShuttersControl::shutters->getShuttersDev
                  . ' - Brightness Event kam nicht innerhalb der Verarbeitungszeit für Sunset oder Sunris oder aber für beide wurden die entsprechendne Verarbeitungsschwellen nicht erreicht.'
            );
        }
    }
    else {
        FHEM::Automation::ShuttersControl::ASC_Debug(
                'EventProcessingBrightness: '
              . $FHEM::Automation::ShuttersControl::shutters->getShuttersDev
              . ' - Leider konnte kein Korrekter Brightnesswert aus dem Event erkannt werden. Entweder passt das Reading oder der tatsächliche nummerishce Wert des Events nicht'
        );
    }

    return;
}

sub EventProcessingShadingBrightness {
    my $hash        = shift;
    my $shuttersDev = shift;
    my $events      = shift;

    my $name = $hash->{NAME};
    $FHEM::Automation::ShuttersControl::shutters->setShuttersDev($shuttersDev);
    my $reading =
      $FHEM::Automation::ShuttersControl::shutters->getBrightnessReading;
    my $outTemp = (
          $FHEM::Automation::ShuttersControl::shutters->getOutTemp != -100
        ? $FHEM::Automation::ShuttersControl::shutters->getOutTemp
        : $FHEM::Automation::ShuttersControl::ascDev->getOutTemp
    );

    Log3( $name, 4,
        "AutoShuttersControl ($shuttersDev) - EventProcessingShadingBrightness"
    );

    FHEM::Automation::ShuttersControl::ASC_Debug(
            'EventProcessingShadingBrightness: '
          . $FHEM::Automation::ShuttersControl::shutters->getShuttersDev
          . ' - Es wird nun geprüft ob der übergebene Event ein nummerischer Wert vom Brightnessreading ist.'
    );

    if ( $events =~ m{$reading:\s(\d+(\.\d+)?)}xms ) {
        Log3(
            $name, 4,
"AutoShuttersControl ($shuttersDev) - EventProcessingShadingBrightness
            Brightness: " . $1
        );

        ## Brightness Wert in ein Array schieben zur Berechnung eines Average Wertes
        $FHEM::Automation::ShuttersControl::shutters->setPushBrightnessInArray(
            $1);

        FHEM::Automation::ShuttersControl::ASC_Debug(
                'EventProcessingShadingBrightness: '
              . $FHEM::Automation::ShuttersControl::shutters->getShuttersDev
              . ' - Nummerischer Brightness-Wert wurde erkannt. Der Brightness Average Wert ist: '
              . $FHEM::Automation::ShuttersControl::shutters
              ->getBrightnessAverage
              . ' RainProtection: '
              . $FHEM::Automation::ShuttersControl::shutters
              ->getRainProtectionStatus
              . ' WindProtection: '
              . $FHEM::Automation::ShuttersControl::shutters
              ->getWindProtectionStatus );

        if ( $FHEM::Automation::ShuttersControl::ascDev
            ->getAutoShuttersControlShading eq 'on'
            && $FHEM::Automation::ShuttersControl::shutters
            ->getRainProtectionStatus eq 'unprotected'
            && $FHEM::Automation::ShuttersControl::shutters
            ->getWindProtectionStatus eq 'unprotected' )
        {
            ShadingProcessing(
                $hash,
                $shuttersDev,
                $FHEM::Automation::ShuttersControl::ascDev->getAzimuth,
                $FHEM::Automation::ShuttersControl::ascDev->getElevation,
                $outTemp,
                $FHEM::Automation::ShuttersControl::shutters
                  ->getShadingAzimuthLeft,
                $FHEM::Automation::ShuttersControl::shutters
                  ->getShadingAzimuthRight
            );

            FHEM::Automation::ShuttersControl::ASC_Debug(
                    'EventProcessingShadingBrightness: '
                  . $FHEM::Automation::ShuttersControl::shutters->getShuttersDev
                  . ' - Alle Bedingungen zur weiteren Beschattungsverarbeitung sind erfüllt. Es wird nun die eigentliche Beschattungsfunktion aufgerufen'
            );
        }
    }

    return;
}

sub EventProcessingTwilightDevice {
    my $hash   = shift;
    my $device = shift;
    my $events = shift;

    #     Twilight
    #     azimuth = azimuth = Sonnenwinkel
    #     elevation = elevation = Sonnenhöhe
    #
    #     Astro
    #     SunAz = azimuth = Sonnenwinkel
    #     SunAlt = elevation = Sonnenhöhe

    FHEM::Automation::ShuttersControl::ASC_Debug(
            'EventProcessingTwilightDevice: '
          . $FHEM::Automation::ShuttersControl::shutters->getShuttersDev
          . ' - Event vom Astro oder Twilight Device wurde erkannt. Event wird verarbeitet'
    );

    if ( $events =~ m{(azimuth|elevation|SunAz|SunAlt):\s(\d+.\d+)}xms ) {
        my $name    = $device;
        my $outTemp = $FHEM::Automation::ShuttersControl::ascDev->getOutTemp;
        my ( $azimuth, $elevation );

        $azimuth   = $2 if ( $1 eq 'azimuth'   || $1 eq 'SunAz' );
        $elevation = $2 if ( $1 eq 'elevation' || $1 eq 'SunAlt' );

        $azimuth = $FHEM::Automation::ShuttersControl::ascDev->getAzimuth
          if ( !defined($azimuth) && !$azimuth );
        $elevation = $FHEM::Automation::ShuttersControl::ascDev->getElevation
          if ( !defined($elevation) && !$elevation );

        FHEM::Automation::ShuttersControl::ASC_Debug(
                'EventProcessingTwilightDevice: '
              . $name
              . ' - Passendes Event wurde erkannt. Verarbeitung über alle Rollos beginnt'
        );

        for my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
            $FHEM::Automation::ShuttersControl::shutters->setShuttersDev(
                $shuttersDev);

            my $homemode =
              $FHEM::Automation::ShuttersControl::shutters->getRoommatesStatus;
            $homemode =
              $FHEM::Automation::ShuttersControl::ascDev->getResidentsStatus
              if ( $homemode eq 'none' );
            $outTemp = $FHEM::Automation::ShuttersControl::shutters->getOutTemp
              if ( $FHEM::Automation::ShuttersControl::shutters->getOutTemp !=
                -100 );

            FHEM::Automation::ShuttersControl::ASC_Debug(
                    'EventProcessingTwilightDevice: '
                  . $FHEM::Automation::ShuttersControl::shutters->getShuttersDev
                  . ' RainProtection: '
                  . $FHEM::Automation::ShuttersControl::shutters
                    ->getRainProtectionStatus
                  . ' WindProtection: '
                  . $FHEM::Automation::ShuttersControl::shutters
                    ->getWindProtectionStatus );

            if (   $FHEM::Automation::ShuttersControl::ascDev
                   ->getAutoShuttersControlShading eq 'on'
                && $FHEM::Automation::ShuttersControl::shutters
                   ->getRainProtectionStatus eq 'unprotected'
                && $FHEM::Automation::ShuttersControl::shutters
                   ->getWindProtectionStatus eq 'unprotected' )
            {
                ShadingProcessing(
                    $hash,
                    $shuttersDev,
                    $azimuth,
                    $elevation,
                    $outTemp,
                    $FHEM::Automation::ShuttersControl::shutters
                      ->getShadingAzimuthLeft,
                    $FHEM::Automation::ShuttersControl::shutters
                      ->getShadingAzimuthRight
                );

                FHEM::Automation::ShuttersControl::ASC_Debug(
                    'EventProcessingTwilightDevice: '
                      . $FHEM::Automation::ShuttersControl::shutters
                      ->getShuttersDev
                      . ' - Alle Bedingungen zur weiteren Beschattungsverarbeitung sind erfüllt. Es wird nun die Beschattungsfunktion ausgeführt'
                );
            }
        }
    }

    return;
}

sub EventProcessingPartyMode {
    my $hash = shift;

    my $name = $hash->{NAME};

    for my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
        $FHEM::Automation::ShuttersControl::shutters->setShuttersDev(
            $shuttersDev);
        next
          if ( $FHEM::Automation::ShuttersControl::shutters->getPartyMode eq
            'off' );

        if (  !$FHEM::Automation::ShuttersControl::shutters->getIsDay
            && $FHEM::Automation::ShuttersControl::shutters->getModeDown ne
            'off'
            && IsAfterShuttersManualBlocking($shuttersDev) )
        {
            if ( CheckIfShuttersWindowRecOpen($shuttersDev) == 2
                && $FHEM::Automation::ShuttersControl::shutters->getSubTyp eq
                'threestate' )
            {
                Log3( $name, 4,
"AutoShuttersControl ($name) - EventProcessingPartyMode Fenster offen"
                );
                $FHEM::Automation::ShuttersControl::shutters->setDelayCmd(
                    $FHEM::Automation::ShuttersControl::shutters->getClosedPos
                );
                Log3( $name, 4,
"AutoShuttersControl ($name) - EventProcessingPartyMode - Spring in ShuttersCommandDelaySet"
                );
            }
            else {
                Log3( $name, 4,
"AutoShuttersControl ($name) - EventProcessingPartyMode Fenster nicht offen"
                );
                $FHEM::Automation::ShuttersControl::shutters->setLastDrive(
                    'drive after party mode');
                FHEM::Automation::ShuttersControl::ShuttersCommandSet(
                    $hash,
                    $shuttersDev,
                    (
                        CheckIfShuttersWindowRecOpen($shuttersDev) == 0
                        ? ($FHEM::Automation::ShuttersControl::shutters
                              ->getSleepPos > 0
                            ? $FHEM::Automation::ShuttersControl::shutters
                                ->getSleepPos
                            : $FHEM::Automation::ShuttersControl::shutters
                                ->getClosedPos)
                        : $FHEM::Automation::ShuttersControl::shutters
                          ->getVentilatePos
                    )
                );
            }
        }
        elsif (
               $FHEM::Automation::ShuttersControl::shutters->getDelayCmd ne 'none'
            && $FHEM::Automation::ShuttersControl::shutters->getIsDay
            && IsAfterShuttersManualBlocking($shuttersDev) )
        {
            $FHEM::Automation::ShuttersControl::shutters->setLastDrive(
                'drive after party mode');
            FHEM::Automation::ShuttersControl::ShuttersCommandSet( $hash,
                $shuttersDev,
                $FHEM::Automation::ShuttersControl::shutters->getDelayCmd );
        }
    }

    return;
}

sub EventProcessingAdvShuttersClose {
    my $hash = shift;

    my $name = $hash->{NAME};

    for my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
        $FHEM::Automation::ShuttersControl::shutters->setShuttersDev(
            $shuttersDev);
        next
          if ( !$FHEM::Automation::ShuttersControl::shutters->getAdv
            && !$FHEM::Automation::ShuttersControl::shutters->getAdvDelay );

        $FHEM::Automation::ShuttersControl::shutters->setLastDrive(
            'adv delay close');
        $FHEM::Automation::ShuttersControl::shutters->setAdvDelay(1);
        FHEM::Automation::ShuttersControl::ShuttersCommandSet(
            $hash,
            $shuttersDev,
            (
                $FHEM::Automation::ShuttersControl::shutters->getDelayCmd ne
                  'none'
                ? $FHEM::Automation::ShuttersControl::shutters->getDelayCmd
                : $FHEM::Automation::ShuttersControl::shutters->getClosedPos
            )
        );
    }

    return;
}

sub EventProcessingShutters {
    my $hash        = shift;
    my $shuttersDev = shift;
    my $events      = shift;

    my $name = $hash->{NAME};

    FHEM::Automation::ShuttersControl::ASC_Debug( 'EventProcessingShutters: '
          . ' Fn wurde durch Notify aufgerufen da ASC_Pos_Reading Event erkannt wurde '
          . ' - RECEIVED EVENT: '
          . Dumper $events);

    if ( $events =~ m{.*:\s(\d+)}xms ) {
        $FHEM::Automation::ShuttersControl::shutters->setShuttersDev(
            $shuttersDev);
        $FHEM::Automation::ShuttersControl::ascDev->setPosReading;

        FHEM::Automation::ShuttersControl::ASC_Debug(
                'EventProcessingShutters: '
              . $FHEM::Automation::ShuttersControl::shutters->getShuttersDev
              . ' - Event vom Rollo erkannt. Es wird nun eine etwaige manuelle Fahrt ausgewertet.'
              . ' Int von gettimeofday: '
              . int( gettimeofday() )
              . ' Last Position Timestamp: '
              . $FHEM::Automation::ShuttersControl::shutters
              ->getLastPosTimestamp
              . ' Drive Up Max Duration: '
              . $FHEM::Automation::ShuttersControl::shutters
              ->getDriveUpMaxDuration
              . ' Last Position: '
              . $FHEM::Automation::ShuttersControl::shutters->getLastPos
              . ' aktuelle Position: '
              . $FHEM::Automation::ShuttersControl::shutters->getStatus );

        if (
            (
                int( gettimeofday() ) -
                $FHEM::Automation::ShuttersControl::shutters
                ->getLastPosTimestamp
            ) >
            $FHEM::Automation::ShuttersControl::shutters->getDriveUpMaxDuration
            && (
                int( gettimeofday() ) -
                $FHEM::Automation::ShuttersControl::shutters
                ->getLastManPosTimestamp ) >
            $FHEM::Automation::ShuttersControl::shutters->getDriveUpMaxDuration
          )
        {
            $FHEM::Automation::ShuttersControl::shutters->setLastDrive(
                'manual');
            $FHEM::Automation::ShuttersControl::shutters->setLastDriveReading;
            $FHEM::Automation::ShuttersControl::ascDev->setStateReading;
            $FHEM::Automation::ShuttersControl::shutters->setLastManPos($1);

            $FHEM::Automation::ShuttersControl::shutters
              ->setShadingManualDriveStatus(1)
              if ( $FHEM::Automation::ShuttersControl::shutters->getIsDay
                && $FHEM::Automation::ShuttersControl::shutters->getIfInShading
              );

            FHEM::Automation::ShuttersControl::ASC_Debug(
                'EventProcessingShutters: eine manualle Fahrt wurde erkannt!');
        }
        else {
            $FHEM::Automation::ShuttersControl::shutters->setLastDriveReading;
            $FHEM::Automation::ShuttersControl::ascDev->setStateReading;

            FHEM::Automation::ShuttersControl::ASC_Debug(
'EventProcessingShutters: eine automatisierte Fahrt durch ASC wurde erkannt! Es werden nun die LastDriveReading und StateReading Werte gesetzt!'
            );
        }
    }

    FHEM::Automation::ShuttersControl::ASC_Debug( 'EventProcessingShutters: '
          . ' Fn wurde durlaufen und es sollten Debugausgaben gekommen sein. '
          . ' !!!Wenn nicht!!! wurde der Event nicht korrekt als Nummerisch erkannt. '
    );

    return;
}

sub EventProcessingExternalTriggerDevice {
    my $hash        = shift;
    my $shuttersDev = shift;
    my $events      = shift;

    my $name = $hash->{NAME};

    $FHEM::Automation::ShuttersControl::shutters->setShuttersDev($shuttersDev);

    FHEM::Automation::ShuttersControl::ASC_Debug(
            'EventProcessingExternalTriggerDevice: '
          . ' Fn wurde durch Notify '
          . ' - RECEIVED EVENT: '
          . Dumper $events);

    my $reading =
      $FHEM::Automation::ShuttersControl::shutters->getExternalTriggerReading;
    my $triggerValActive = $FHEM::Automation::ShuttersControl::shutters
      ->getExternalTriggerValueActive;
    my $triggerValActive2 = $FHEM::Automation::ShuttersControl::shutters
      ->getExternalTriggerValueActive2;
    my $triggerValInactive = $FHEM::Automation::ShuttersControl::shutters
      ->getExternalTriggerValueInactive;
    my $triggerPosActive =
      $FHEM::Automation::ShuttersControl::shutters->getExternalTriggerPosActive;
    my $triggerPosActive2 = $FHEM::Automation::ShuttersControl::shutters
      ->getExternalTriggerPosActive2;
    my $triggerPosInactive = $FHEM::Automation::ShuttersControl::shutters
      ->getExternalTriggerPosInactive;

    if ( $events =~ m{$reading:\s($triggerValActive|$triggerValActive2)}xms ) {

#         && !$FHEM::Automation::ShuttersControl::shutters->getQueryShuttersPos($triggerPosActive)

        FHEM::Automation::ShuttersControl::ASC_Debug(
                'EventProcessingExternalTriggerDevice: '
              . ' In der RegEx Schleife Trigger Val Aktiv'
              . ' - TriggerVal: '
              . $triggerValActive
              . ' - TriggerVal2: '
              . $triggerValActive2 );

        if ( $1 eq $triggerValActive2 ) {
            $FHEM::Automation::ShuttersControl::shutters->setLastDrive(
                'external trigger2 device active');
            $FHEM::Automation::ShuttersControl::shutters->setNoDelay(1);
            $FHEM::Automation::ShuttersControl::shutters
              ->setExternalTriggerStatus(1);
            FHEM::Automation::ShuttersControl::ShuttersCommandSet( $hash,
                $shuttersDev, $triggerPosActive2 );
        }
        else {
            $FHEM::Automation::ShuttersControl::shutters->setLastDrive(
                'external trigger device active');
            $FHEM::Automation::ShuttersControl::shutters->setNoDelay(1);
            $FHEM::Automation::ShuttersControl::shutters
              ->setExternalTriggerStatus(1);
            FHEM::Automation::ShuttersControl::ShuttersCommandSet( $hash,
                $shuttersDev, $triggerPosActive );
        }
    }
    elsif (
        $events =~ m{$reading:\s($triggerValInactive)}xms
        && ( $FHEM::Automation::ShuttersControl::shutters->getPrivacyDownStatus
            != 2
            || $FHEM::Automation::ShuttersControl::shutters->getPrivacyUpStatus
            != 2 )
        && !$FHEM::Automation::ShuttersControl::shutters->getIfInShading
      )
    {
        FHEM::Automation::ShuttersControl::ASC_Debug(
                'EventProcessingExternalTriggerDevice: '
              . ' In der RegEx Schleife Trigger Val Inaktiv'
              . ' - TriggerVal: '
              . $triggerValInactive );

        $FHEM::Automation::ShuttersControl::shutters->setLastDrive(
            'external trigger device inactive');
        $FHEM::Automation::ShuttersControl::shutters->setNoDelay(1);
        $FHEM::Automation::ShuttersControl::shutters->setExternalTriggerStatus(
            1);
        FHEM::Automation::ShuttersControl::ShuttersCommandSet(
            $hash,
            $shuttersDev,
            (
                  $FHEM::Automation::ShuttersControl::shutters->getIsDay
                ? $triggerPosInactive
                : $FHEM::Automation::ShuttersControl::shutters->getClosedPos
            )
        );
    }

    FHEM::Automation::ShuttersControl::ASC_Debug(
        'EventProcessingExternalTriggerDevice: ' . ' Funktion durchlaufen' );

    return;
}




1;
