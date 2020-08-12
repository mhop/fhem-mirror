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
package FHEM::Automation::ShuttersControl::Helper;

use strict;
use warnings;
use POSIX qw(strftime);
use utf8;

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(
  PositionValueWindowRec
  AutoSearchTwilightDev
  GetAttrValues
  CheckIfShuttersWindowRecOpen
  ExtractNotifyDevFromEvent
  ShuttersSunrise
  ShuttersSunset
  makeReadingName
  IsWe
  IsAfterShuttersTimeBlocking
  IsAfterShuttersManualBlocking
  AverageBrightness
  PerlCodeCheck
  IsAdv
  IsInTime
);
our %EXPORT_TAGS = (
    ALL => [
        qw(
          PositionValueWindowRec
          AutoSearchTwilightDev
          GetAttrValues
          CheckIfShuttersWindowRecOpen
          ExtractNotifyDevFromEvent
          ShuttersSunrise
          ShuttersSunset
          makeReadingName
          IsWe
          IsAfterShuttersTimeBlocking
          IsAfterShuttersManualBlocking
          AverageBrightness
          PerlCodeCheck
          IsAdv
          IsInTime
          )
    ],
);

use GPUtils qw(GP_Import);
## Import der FHEM Funktionen
BEGIN {
    GP_Import(
        qw(
          devspec2array
          CommandAttr
          AttrVal
          Log3
          computeAlignTime
          gettimeofday
          sunset
          sunset_abs
          sunrise
          sunrise_abs
          cmdFromAnalyze
          )
    );
}

sub PositionValueWindowRec {
    my $shuttersDev = shift;
    my $posValue    = shift;

    if ( CheckIfShuttersWindowRecOpen($shuttersDev) == 1
        && $FHEM::Automation::ShuttersControl::shutters->getVentilateOpen eq
        'on' )
    {
        $posValue =
          $FHEM::Automation::ShuttersControl::shutters->getVentilatePos;
    }
    elsif ( CheckIfShuttersWindowRecOpen($shuttersDev) == 2
        && $FHEM::Automation::ShuttersControl::shutters->getSubTyp eq
        'threestate'
        && $FHEM::Automation::ShuttersControl::ascDev
        ->getAutoShuttersControlComfort eq 'on' )
    {
        $posValue =
          $FHEM::Automation::ShuttersControl::shutters->getComfortOpenPos;
    }
    elsif (
        CheckIfShuttersWindowRecOpen($shuttersDev) == 2
        && ( $FHEM::Automation::ShuttersControl::shutters->getSubTyp eq
            'threestate'
            || $FHEM::Automation::ShuttersControl::shutters->getSubTyp eq
            'twostate' )
        && $FHEM::Automation::ShuttersControl::shutters->getVentilateOpen eq
        'on'
      )
    {
        $posValue =
          $FHEM::Automation::ShuttersControl::shutters->getVentilatePos;
    }

    if (
        $FHEM::Automation::ShuttersControl::shutters->getQueryShuttersPos(
            $posValue)
      )
    {
        $posValue = $FHEM::Automation::ShuttersControl::shutters->getStatus;
    }

    return $posValue;
}

sub AutoSearchTwilightDev {
    my $hash = shift;

    my $name = $hash->{NAME};

    if ( devspec2array('TYPE=(Astro|Twilight)') > 0 ) {
        CommandAttr( undef,
                $name
              . ' ASC_twilightDevice '
              . ( devspec2array('TYPE=(Astro|Twilight)') )[0] )
          if ( AttrVal( $name, 'ASC_twilightDevice', 'none' ) eq 'none' );
    }

    return;
}

sub GetAttrValues {
    my $dev      = shift;
    my $attribut = shift;
    my $default  = shift;

    my @values = split( ' ',
        AttrVal( $dev, $attribut, ( defined($default) ? $default : 'none' ) ) );
    my ( $value1, $value2 ) = split( ':', $values[0] );

    my ( $value3, $value4, $value5, $value6, $value7, $value8 );
    ( $value3, $value4 ) = split( ':', $values[1] )
      if ( defined( $values[1] ) );
    ( $value5, $value6 ) = split( ':', $values[2] )
      if ( defined( $values[2] ) );
    ( $value7, $value8 ) = split( ':', $values[3] )
      if ( defined( $values[3] ) );

    return (
        $value1,
        defined($value2) ? $value2 : 'none',
        defined($value3) ? $value3 : 'none',
        defined($value4) ? $value4 : 'none',
        defined($value5) ? $value5 : 'none',
        defined($value6) ? $value6 : 'none',
        defined($value7) ? $value7 : 'none',
        defined($value8) ? $value8 : 'none'
    );
}

## Kontrolliert ob das Fenster von einem bestimmten Rolladen offen ist
sub CheckIfShuttersWindowRecOpen {
    my $shuttersDev = shift;
    $FHEM::Automation::ShuttersControl::shutters->setShuttersDev($shuttersDev);

    if ( $FHEM::Automation::ShuttersControl::shutters->getWinStatus =~
        m{[Oo]pen|false}xms )    # CK: covers: open|opened
    {
        return 2;
    }
    elsif (
        $FHEM::Automation::ShuttersControl::shutters->getWinStatus =~ m{tilt}xms
        && $FHEM::Automation::ShuttersControl::shutters->getSubTyp eq
        'threestate' )           # CK: covers: tilt|tilted
    {
        return 1;
    }
    elsif ( $FHEM::Automation::ShuttersControl::shutters->getWinStatus =~
        m{[Cc]lose|true}xms )
    {
        return 0;
    }                            # CK: covers: close|closed
}

sub ExtractNotifyDevFromEvent {
    my $hash         = shift;
    my $shuttersDev  = shift;
    my $shuttersAttr = shift;

    my %notifyDevs;
    while ( my $notifyDev = each %{ $hash->{monitoredDevs} } ) {
        Log3( $hash->{NAME}, 4,
"AutoShuttersControl ($hash->{NAME}) - ExtractNotifyDevFromEvent - NotifyDev: "
              . $notifyDev );
        Log3( $hash->{NAME}, 5,
"AutoShuttersControl ($hash->{NAME}) - ExtractNotifyDevFromEvent - ShuttersDev: "
              . $shuttersDev );

        if ( defined( $hash->{monitoredDevs}{$notifyDev}{$shuttersDev} )
            && $hash->{monitoredDevs}{$notifyDev}{$shuttersDev} eq
            $shuttersAttr )
        {
            Log3( $hash->{NAME}, 4,
"AutoShuttersControl ($hash->{NAME}) - ExtractNotifyDevFromEvent - ShuttersDevHash: "
                  . $hash->{monitoredDevs}{$notifyDev}{$shuttersDev} );
            Log3( $hash->{NAME}, 5,
"AutoShuttersControl ($hash->{NAME}) - ExtractNotifyDevFromEvent - return ShuttersDev: "
                  . $notifyDev );
            $notifyDevs{$notifyDev} = $shuttersDev;
        }
    }
    return \%notifyDevs;
}

## Ist Tag oder Nacht für den entsprechende Rolladen
sub _IsDay {
    my $shuttersDev = shift;

    $FHEM::Automation::ShuttersControl::shutters->setShuttersDev($shuttersDev);

    my $brightnessMinVal = (
          $FHEM::Automation::ShuttersControl::shutters->getBrightnessMinVal > -1
        ? $FHEM::Automation::ShuttersControl::shutters->getBrightnessMinVal
        : $FHEM::Automation::ShuttersControl::ascDev->getBrightnessMinVal
    );

    my $brightnessMaxVal = (
          $FHEM::Automation::ShuttersControl::shutters->getBrightnessMaxVal > -1
        ? $FHEM::Automation::ShuttersControl::shutters->getBrightnessMaxVal
        : $FHEM::Automation::ShuttersControl::ascDev->getBrightnessMaxVal
    );

    my $isday = ( ShuttersSunrise( $shuttersDev, 'unix' ) >
          ShuttersSunset( $shuttersDev, 'unix' ) ? 1 : 0 );
    my $respIsDay = $isday;

    FHEM::Automation::ShuttersControl::ASC_Debug(
        'FnIsDay: ' . $shuttersDev . ' Allgemein: ' . $respIsDay );

    if (
        (
            (
                (
                    int( gettimeofday() / 86400 ) != int(
                        computeAlignTime( '24:00',
                            $FHEM::Automation::ShuttersControl::shutters
                              ->getTimeUpEarly ) / 86400
                    )
                    && !IsWe()
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
                    $FHEM::Automation::ShuttersControl::shutters->getTimeUpLate
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
            && int( gettimeofday() / 86400 ) == int(
                computeAlignTime(
                    '24:00',
                    $FHEM::Automation::ShuttersControl::shutters
                      ->getTimeDownLate
                ) / 86400
            )
        )
      )
    {
        ##### Nach Sonnenuntergang / Abends
        $respIsDay = (
            (
                (
                    $FHEM::Automation::ShuttersControl::shutters
                      ->getBrightness > $brightnessMinVal
                      && $isday
                      && !$FHEM::Automation::ShuttersControl::shutters
                      ->getSunset
                )
                  || !$FHEM::Automation::ShuttersControl::shutters->getSunset
            ) ? 1 : 0
          )
          if ( $FHEM::Automation::ShuttersControl::shutters->getDown eq
            'brightness' );

        FHEM::Automation::ShuttersControl::ASC_Debug( 'FnIsDay: '
              . $shuttersDev
              . ' getDownBrightness: '
              . $respIsDay
              . ' Brightness: '
              . $FHEM::Automation::ShuttersControl::shutters->getBrightness
              . ' BrightnessMin: '
              . $brightnessMinVal
              . ' Sunset: '
              . $FHEM::Automation::ShuttersControl::shutters->getSunset );

        ##### Nach Sonnenauf / Morgens
        $respIsDay = (
            (
                (
                    $FHEM::Automation::ShuttersControl::shutters
                      ->getBrightness > $brightnessMaxVal
                      && !$isday
                      && $FHEM::Automation::ShuttersControl::shutters
                      ->getSunrise
                )
                  || $respIsDay
                  || $FHEM::Automation::ShuttersControl::shutters->getSunrise
            ) ? 1 : 0
          )
          if ( $FHEM::Automation::ShuttersControl::shutters->getUp eq
            'brightness' );

        FHEM::Automation::ShuttersControl::ASC_Debug( 'FnIsDay: '
              . $shuttersDev
              . ' getUpBrightness: '
              . $respIsDay
              . ' Brightness: '
              . $FHEM::Automation::ShuttersControl::shutters->getBrightness
              . ' BrightnessMax: '
              . $brightnessMaxVal
              . ' Sunrise: '
              . $FHEM::Automation::ShuttersControl::shutters->getSunrise );
    }

    
    $respIsDay == 1
      if (
           (  $FHEM::Automation::ShuttersControl::shutters->getDown eq 'roommate'
             and ( $FHEM::Automation::ShuttersControl::shutters->getRoommates ne 'asleep'
                or $FHEM::Automation::ShuttersControl::shutters->getRoommates ne 'gotosleep' )
           ) 
        or (  $FHEM::Automation::ShuttersControl::shutters->getUp eq 'roommate'
             and ( $FHEM::Automation::ShuttersControl::shutters->getRoommates ne 'asleep'
                or $FHEM::Automation::ShuttersControl::shutters->getRoommates ne 'gotosleep' )
           )
      );
    
    return $respIsDay;
}

sub ShuttersSunrise {
    my $shuttersDev = shift;
    my $tm = shift; # Tm steht für Timemode und bedeutet Realzeit oder Unixzeit

    my $autoAstroMode;
    $FHEM::Automation::ShuttersControl::shutters->setShuttersDev($shuttersDev);

    if ( $FHEM::Automation::ShuttersControl::shutters->getAutoAstroModeMorning
        ne 'none' )
    {
        $autoAstroMode =
          $FHEM::Automation::ShuttersControl::shutters->getAutoAstroModeMorning;
        $autoAstroMode =
            $autoAstroMode . '='
          . $FHEM::Automation::ShuttersControl::shutters
          ->getAutoAstroModeMorningHorizon
          if ( $autoAstroMode eq 'HORIZON' );
    }
    else {
        $autoAstroMode =
          $FHEM::Automation::ShuttersControl::ascDev->getAutoAstroModeMorning;
        $autoAstroMode =
            $autoAstroMode . '='
          . $FHEM::Automation::ShuttersControl::ascDev
          ->getAutoAstroModeMorningHorizon
          if ( $autoAstroMode eq 'HORIZON' );
    }
    my $oldFuncHash =
      $FHEM::Automation::ShuttersControl::shutters->getInTimerFuncHash;
    my $shuttersSunriseUnixtime =
      computeAlignTime( '24:00', sunrise( 'REAL', 0, '4:30', '8:30' ) );

    if ( $tm eq 'unix' ) {
        if ( $FHEM::Automation::ShuttersControl::shutters->getUp eq 'astro' ) {
            if ( ( IsWe() || IsWe('tomorrow') )
                && $FHEM::Automation::ShuttersControl::ascDev
                ->getSunriseTimeWeHoliday eq 'on'
                && $FHEM::Automation::ShuttersControl::shutters
                ->getTimeUpWeHoliday ne '01:25' )
            {
                if ( !IsWe('tomorrow') ) {
                    if (
                        IsWe()
                        && int( gettimeofday() / 86400 ) == int(
                            (
                                computeAlignTime(
                                    '24:00',
                                    sunrise_abs(
                                        $autoAstroMode,
                                        0,
                                        $FHEM::Automation::ShuttersControl::shutters
                                          ->getTimeUpWeHoliday
                                    )
                                ) + 1
                            ) / 86400
                        )
                      )
                    {
                        $shuttersSunriseUnixtime = (
                            computeAlignTime(
                                '24:00',
                                sunrise_abs(
                                    $autoAstroMode,
                                    0,
                                    $FHEM::Automation::ShuttersControl::shutters
                                      ->getTimeUpWeHoliday
                                )
                            ) + 1
                        );
                    }
                    elsif (
                        int( gettimeofday() / 86400 ) == int(
                            (
                                computeAlignTime(
                                    '24:00',
                                    sunrise_abs(
                                        $autoAstroMode,
                                        0,
                                        $FHEM::Automation::ShuttersControl::shutters
                                          ->getTimeUpEarly,
                                        $FHEM::Automation::ShuttersControl::shutters
                                          ->getTimeUpLate
                                    )
                                ) + 1
                            ) / 86400
                        )
                      )
                    {
                        $shuttersSunriseUnixtime = (
                            computeAlignTime(
                                '24:00',
                                sunrise_abs(
                                    $autoAstroMode,
                                    0,
                                    $FHEM::Automation::ShuttersControl::shutters
                                      ->getTimeUpWeHoliday
                                )
                            ) + 1
                        );
                    }
                    else {
                        $shuttersSunriseUnixtime = (
                            computeAlignTime(
                                '24:00',
                                sunrise_abs(
                                    $autoAstroMode,
                                    0,
                                    $FHEM::Automation::ShuttersControl::shutters
                                      ->getTimeUpEarly,
                                    $FHEM::Automation::ShuttersControl::shutters
                                      ->getTimeUpLate
                                )
                            ) + 1
                        );
                    }
                }
                else {
                    if (
                        IsWe()
                        && (
                            int( gettimeofday() / 86400 ) == int(
                                (
                                    computeAlignTime(
                                        '24:00',
                                        sunrise_abs(
                                            $autoAstroMode,
                                            0,
                                            $FHEM::Automation::ShuttersControl::shutters
                                              ->getTimeUpWeHoliday
                                        )
                                    ) + 1
                                ) / 86400
                            )
                            || int( gettimeofday() / 86400 ) != int(
                                (
                                    computeAlignTime(
                                        '24:00',
                                        sunrise_abs(
                                            $autoAstroMode,
                                            0,
                                            $FHEM::Automation::ShuttersControl::shutters
                                              ->getTimeUpWeHoliday
                                        )
                                    ) + 1
                                ) / 86400
                            )
                        )
                      )
                    {
                        $shuttersSunriseUnixtime = (
                            computeAlignTime(
                                '24:00',
                                sunrise_abs(
                                    $autoAstroMode,
                                    0,
                                    $FHEM::Automation::ShuttersControl::shutters
                                      ->getTimeUpWeHoliday
                                )
                            ) + 1
                        );
                    }
                    elsif (
                        int( gettimeofday() / 86400 ) == int(
                            (
                                computeAlignTime(
                                    '24:00',
                                    sunrise_abs(
                                        $autoAstroMode,
                                        0,
                                        $FHEM::Automation::ShuttersControl::shutters
                                          ->getTimeUpEarly,
                                        $FHEM::Automation::ShuttersControl::shutters
                                          ->getTimeUpLate
                                    )
                                ) + 1
                            ) / 86400
                        )
                      )
                    {
                        $shuttersSunriseUnixtime = (
                            computeAlignTime(
                                '24:00',
                                sunrise_abs(
                                    $autoAstroMode,
                                    0,
                                    $FHEM::Automation::ShuttersControl::shutters
                                      ->getTimeUpEarly,
                                    $FHEM::Automation::ShuttersControl::shutters
                                      ->getTimeUpLate
                                )
                            ) + 1
                        );
                    }
                    else {
                        if (
                            int( gettimeofday() / 86400 ) == int(
                                (
                                    computeAlignTime(
                                        '24:00',
                                        sunrise_abs(
                                            $autoAstroMode,
                                            0,
                                            $FHEM::Automation::ShuttersControl::shutters
                                              ->getTimeUpWeHoliday
                                        )
                                    ) + 1
                                ) / 86400
                            )
                          )
                        {
                            $shuttersSunriseUnixtime = (
                                computeAlignTime(
                                    '24:00',
                                    sunrise_abs(
                                        $autoAstroMode,
                                        0,
                                        $FHEM::Automation::ShuttersControl::shutters
                                          ->getTimeUpWeHoliday
                                    )
                                ) + 86401
                            );
                        }
                        else {
                            $shuttersSunriseUnixtime = (
                                computeAlignTime(
                                    '24:00',
                                    sunrise_abs(
                                        $autoAstroMode,
                                        0,
                                        $FHEM::Automation::ShuttersControl::shutters
                                          ->getTimeUpWeHoliday
                                    )
                                ) + 1
                            );
                        }
                    }
                }
            }
            else {
                $shuttersSunriseUnixtime = (
                    computeAlignTime(
                        '24:00',
                        sunrise_abs(
                            $autoAstroMode,
                            0,
                            $FHEM::Automation::ShuttersControl::shutters
                              ->getTimeUpEarly,
                            $FHEM::Automation::ShuttersControl::shutters
                              ->getTimeUpLate
                        )
                    ) + 1
                );
            }
            if (   defined($oldFuncHash)
                && ref($oldFuncHash) eq 'HASH'
                && ( IsWe() || IsWe('tomorrow') )
                && $FHEM::Automation::ShuttersControl::ascDev
                ->getSunriseTimeWeHoliday eq 'on'
                && $FHEM::Automation::ShuttersControl::shutters
                ->getTimeUpWeHoliday ne '01:25' )
            {
                if ( !IsWe('tomorrow') ) {
                    if (
                        int( gettimeofday() / 86400 ) == int(
                            (
                                computeAlignTime(
                                    '24:00',
                                    sunrise_abs(
                                        $autoAstroMode,
                                        0,
                                        $FHEM::Automation::ShuttersControl::shutters
                                          ->getTimeUpEarly,
                                        $FHEM::Automation::ShuttersControl::shutters
                                          ->getTimeUpLate
                                    )
                                ) + 1
                            ) / 86400
                        )
                      )
                    {
                        $shuttersSunriseUnixtime =
                          ( $shuttersSunriseUnixtime + 86400 )
                          if ( $shuttersSunriseUnixtime <
                            ( $oldFuncHash->{sunrisetime} + 180 )
                            && $oldFuncHash->{sunrisetime} < gettimeofday() );
                    }
                }
            }
            elsif ( defined($oldFuncHash) && ref($oldFuncHash) eq 'HASH' ) {
                $shuttersSunriseUnixtime = ( $shuttersSunriseUnixtime + 86400 )
                  if ( $shuttersSunriseUnixtime <
                    ( $oldFuncHash->{sunrisetime} + 180 )
                    && $oldFuncHash->{sunrisetime} < gettimeofday() );
            }
        }
        elsif ( $FHEM::Automation::ShuttersControl::shutters->getUp eq 'time' )
        {
            if ( ( IsWe() || IsWe('tomorrow') )
                && $FHEM::Automation::ShuttersControl::ascDev
                ->getSunriseTimeWeHoliday eq 'on'
                && $FHEM::Automation::ShuttersControl::shutters
                ->getTimeUpWeHoliday ne '01:25' )
            {
                if ( !IsWe('tomorrow') ) {
                    if (
                        int( gettimeofday() / 86400 ) == int(
                            computeAlignTime(
                                '24:00',
                                $FHEM::Automation::ShuttersControl::shutters
                                  ->getTimeUpWeHoliday
                            ) / 86400
                        )
                      )
                    {
                        $shuttersSunriseUnixtime = computeAlignTime( '24:00',
                            $FHEM::Automation::ShuttersControl::shutters
                              ->getTimeUpWeHoliday );
                    }
                    elsif (
                        int( gettimeofday() / 86400 ) == int(
                            computeAlignTime(
                                '24:00',
                                $FHEM::Automation::ShuttersControl::shutters
                                  ->getTimeUpEarly
                            ) / 86400
                        )
                        && $FHEM::Automation::ShuttersControl::shutters
                        ->getSunrise
                      )
                    {
                        $shuttersSunriseUnixtime = computeAlignTime( '24:00',
                            $FHEM::Automation::ShuttersControl::shutters
                              ->getTimeUpEarly ) + 86400;
                    }
                    else {
                        $shuttersSunriseUnixtime = computeAlignTime( '24:00',
                            $FHEM::Automation::ShuttersControl::shutters
                              ->getTimeUpEarly );
                    }
                }
                else {
                    if (
                        IsWe()
                        && int( gettimeofday() / 86400 ) == int(
                            computeAlignTime(
                                '24:00',
                                $FHEM::Automation::ShuttersControl::shutters
                                  ->getTimeUpWeHoliday
                            ) / 86400
                        )
                      )
                    {
                        $shuttersSunriseUnixtime = computeAlignTime( '24:00',
                            $FHEM::Automation::ShuttersControl::shutters
                              ->getTimeUpWeHoliday );
                    }
                    elsif (
                        int( gettimeofday() / 86400 ) == int(
                            computeAlignTime(
                                '24:00',
                                $FHEM::Automation::ShuttersControl::shutters
                                  ->getTimeUpEarly
                            ) / 86400
                        )
                      )
                    {
                        $shuttersSunriseUnixtime = computeAlignTime( '24:00',
                            $FHEM::Automation::ShuttersControl::shutters
                              ->getTimeUpEarly );
                    }
                    elsif (
                        int( gettimeofday() / 86400 ) != int(
                            computeAlignTime(
                                '24:00',
                                $FHEM::Automation::ShuttersControl::shutters
                                  ->getTimeUpWeHoliday
                            ) / 86400
                        )
                      )
                    {
                        $shuttersSunriseUnixtime = computeAlignTime( '24:00',
                            $FHEM::Automation::ShuttersControl::shutters
                              ->getTimeUpWeHoliday );
                    }
                    else {
                        $shuttersSunriseUnixtime = computeAlignTime( '24:00',
                            $FHEM::Automation::ShuttersControl::shutters
                              ->getTimeUpWeHoliday ) + 86400;
                    }
                }
            }
            else {
                $shuttersSunriseUnixtime = computeAlignTime( '24:00',
                    $FHEM::Automation::ShuttersControl::shutters
                      ->getTimeUpEarly );
            }
        }
        elsif ( $FHEM::Automation::ShuttersControl::shutters->getUp eq
            'brightness' )
        {
            if ( ( IsWe() || IsWe('tomorrow') )
                && $FHEM::Automation::ShuttersControl::ascDev
                ->getSunriseTimeWeHoliday eq 'on'
                && $FHEM::Automation::ShuttersControl::shutters
                ->getTimeUpWeHoliday ne '01:25' )
            {
                if ( !IsWe('tomorrow') ) {
                    if (
                        IsWe()
                        && int( gettimeofday() / 86400 ) == int(
                            (
                                computeAlignTime(
                                    '24:00',
                                    $FHEM::Automation::ShuttersControl::shutters
                                      ->getTimeUpWeHoliday
                                )
                            ) / 86400
                        )
                      )
                    {
                        $shuttersSunriseUnixtime = computeAlignTime( '24:00',
                            $FHEM::Automation::ShuttersControl::shutters
                              ->getTimeUpWeHoliday );
                    }
                    elsif (
                        int( gettimeofday() / 86400 ) == int(
                            (
                                computeAlignTime(
                                    '24:00',
                                    $FHEM::Automation::ShuttersControl::shutters
                                      ->getTimeUpLate
                                )
                            ) / 86400
                        )
                      )
                    {
                        $shuttersSunriseUnixtime = computeAlignTime( '24:00',
                            $FHEM::Automation::ShuttersControl::shutters
                              ->getTimeUpWeHoliday );
                    }
                    else {
                        $shuttersSunriseUnixtime = computeAlignTime( '24:00',
                            $FHEM::Automation::ShuttersControl::shutters
                              ->getTimeUpLate );
                    }
                }
                else {
                    if (
                        IsWe()
                        && (
                            int( gettimeofday() / 86400 ) == int(
                                (
                                    computeAlignTime(
                                        '24:00',
                                        $FHEM::Automation::ShuttersControl::shutters
                                          ->getTimeUpWeHoliday
                                    )
                                ) / 86400
                            )
                            || int( gettimeofday() / 86400 ) != int(
                                (
                                    computeAlignTime(
                                        '24:00',
                                        $FHEM::Automation::ShuttersControl::shutters
                                          ->getTimeUpWeHoliday
                                    )
                                ) / 86400
                            )
                        )
                      )
                    {
                        $shuttersSunriseUnixtime = computeAlignTime( '24:00',
                            $FHEM::Automation::ShuttersControl::shutters
                              ->getTimeUpWeHoliday );
                    }
                    elsif (
                        int( gettimeofday() / 86400 ) == int(
                            (
                                computeAlignTime(
                                    '24:00',
                                    $FHEM::Automation::ShuttersControl::shutters
                                      ->getTimeUpLate
                                )
                            ) / 86400
                        )
                      )
                    {
                        $shuttersSunriseUnixtime = computeAlignTime( '24:00',
                            $FHEM::Automation::ShuttersControl::shutters
                              ->getTimeUpLate );
                    }
                    else {
                        if (
                            int( gettimeofday() / 86400 ) == int(
                                (
                                    computeAlignTime(
                                        '24:00',
                                        $FHEM::Automation::ShuttersControl::shutters
                                          ->getTimeUpWeHoliday
                                    )
                                ) / 86400
                            )
                          )
                        {
                            $shuttersSunriseUnixtime = computeAlignTime(
                                '24:00',
                                $FHEM::Automation::ShuttersControl::shutters
                                  ->getTimeUpWeHoliday
                            );
                        }
                        else {
                            $shuttersSunriseUnixtime = computeAlignTime(
                                '24:00',
                                $FHEM::Automation::ShuttersControl::shutters
                                  ->getTimeUpWeHoliday
                            );
                        }
                    }
                }
            }
            else {

                $shuttersSunriseUnixtime = computeAlignTime( '24:00',
                    $FHEM::Automation::ShuttersControl::shutters->getTimeUpLate
                );
            }
        }

        return $shuttersSunriseUnixtime;
    }
    elsif ( $tm eq 'real' ) {
        return sunrise_abs(
            $autoAstroMode,
            0,
            $FHEM::Automation::ShuttersControl::shutters->getTimeUpEarly,
            $FHEM::Automation::ShuttersControl::shutters->getTimeUpLate
          )
          if ( $FHEM::Automation::ShuttersControl::shutters->getUp eq 'astro' );
        return $FHEM::Automation::ShuttersControl::shutters->getTimeUpEarly
          if ( $FHEM::Automation::ShuttersControl::shutters->getUp eq 'time' );
    }

    return;
}

sub ShuttersSunset {
    my $shuttersDev = shift;
    my $tm = shift; # Tm steht für Timemode und bedeutet Realzeit oder Unixzeit

    my $autoAstroMode;
    $FHEM::Automation::ShuttersControl::shutters->setShuttersDev($shuttersDev);

    if ( $FHEM::Automation::ShuttersControl::shutters->getAutoAstroModeEvening
        ne 'none' )
    {
        $autoAstroMode =
          $FHEM::Automation::ShuttersControl::shutters->getAutoAstroModeEvening;
        $autoAstroMode =
            $autoAstroMode . '='
          . $FHEM::Automation::ShuttersControl::shutters
          ->getAutoAstroModeEveningHorizon
          if ( $autoAstroMode eq 'HORIZON' );
    }
    else {
        $autoAstroMode =
          $FHEM::Automation::ShuttersControl::ascDev->getAutoAstroModeEvening;
        $autoAstroMode =
            $autoAstroMode . '='
          . $FHEM::Automation::ShuttersControl::ascDev
          ->getAutoAstroModeEveningHorizon
          if ( $autoAstroMode eq 'HORIZON' );
    }
    my $oldFuncHash =
      $FHEM::Automation::ShuttersControl::shutters->getInTimerFuncHash;
    my $shuttersSunsetUnixtime =
      computeAlignTime( '24:00', sunset( 'REAL', 0, '15:30', '21:30' ) );

    if ( $tm eq 'unix' ) {
        if ( $FHEM::Automation::ShuttersControl::shutters->getDown eq 'astro' )
        {
            $shuttersSunsetUnixtime = (
                computeAlignTime(
                    '24:00',
                    sunset_abs(
                        $autoAstroMode,
                        0,
                        $FHEM::Automation::ShuttersControl::shutters
                          ->getTimeDownEarly,
                        $FHEM::Automation::ShuttersControl::shutters
                          ->getTimeDownLate
                    )
                ) + 1
            );
            if ( defined($oldFuncHash) && ref($oldFuncHash) eq 'HASH' ) {
                $shuttersSunsetUnixtime += 86400
                  if ( $shuttersSunsetUnixtime <
                    ( $oldFuncHash->{sunsettime} + 180 )
                    && $oldFuncHash->{sunsettime} < gettimeofday() );
            }
        }
        elsif (
            $FHEM::Automation::ShuttersControl::shutters->getDown eq 'time' )
        {
            $shuttersSunsetUnixtime = computeAlignTime( '24:00',
                $FHEM::Automation::ShuttersControl::shutters->getTimeDownEarly
            );
        }
        elsif ( $FHEM::Automation::ShuttersControl::shutters->getDown eq
            'brightness' )
        {
            $shuttersSunsetUnixtime =
              computeAlignTime( '24:00',
                $FHEM::Automation::ShuttersControl::shutters->getTimeDownLate );
        }
        return $shuttersSunsetUnixtime;
    }
    elsif ( $tm eq 'real' ) {
        return sunset_abs(
            $autoAstroMode,
            0,
            $FHEM::Automation::ShuttersControl::shutters->getTimeDownEarly,
            $FHEM::Automation::ShuttersControl::shutters->getTimeDownLate
          )
          if (
            $FHEM::Automation::ShuttersControl::shutters->getDown eq 'astro' );
        return $FHEM::Automation::ShuttersControl::shutters->getTimeDownEarly
          if (
            $FHEM::Automation::ShuttersControl::shutters->getDown eq 'time' );
    }

    return;
}

sub IsAfterShuttersTimeBlocking {
    my $shuttersDev = shift;

    $FHEM::Automation::ShuttersControl::shutters->setShuttersDev($shuttersDev);

    if (
        (
            int( gettimeofday() ) -
            $FHEM::Automation::ShuttersControl::shutters->getLastManPosTimestamp
        ) <
        $FHEM::Automation::ShuttersControl::shutters->getBlockingTimeAfterManual
        || (
            !$FHEM::Automation::ShuttersControl::shutters->getIsDay
            && defined(
                $FHEM::Automation::ShuttersControl::shutters->getSunriseUnixTime
            )
            && $FHEM::Automation::ShuttersControl::shutters->getSunriseUnixTime
            - ( int( gettimeofday() ) ) <
            $FHEM::Automation::ShuttersControl::shutters
            ->getBlockingTimeBeforDayOpen
        )
        || (
            $FHEM::Automation::ShuttersControl::shutters->getIsDay
            && defined(
                $FHEM::Automation::ShuttersControl::shutters->getSunriseUnixTime
            )
            && $FHEM::Automation::ShuttersControl::shutters->getSunsetUnixTime
            - ( int( gettimeofday() ) ) <
            $FHEM::Automation::ShuttersControl::shutters
            ->getBlockingTimeBeforNightClose
        )
      )
    {
        return 0;
    }

    else { return 1 }
}

sub IsAfterShuttersManualBlocking {
    my $shuttersDev = shift;
    $FHEM::Automation::ShuttersControl::shutters->setShuttersDev($shuttersDev);

    if (
        $FHEM::Automation::ShuttersControl::ascDev->getBlockAscDrivesAfterManual
        && $FHEM::Automation::ShuttersControl::shutters->getStatus !=
        $FHEM::Automation::ShuttersControl::shutters->getOpenPos
        && $FHEM::Automation::ShuttersControl::shutters->getStatus !=
        $FHEM::Automation::ShuttersControl::shutters->getClosedPos
        && $FHEM::Automation::ShuttersControl::shutters->getStatus !=
        $FHEM::Automation::ShuttersControl::shutters->getWindPos
        && $FHEM::Automation::ShuttersControl::shutters->getStatus !=
        $FHEM::Automation::ShuttersControl::shutters->getShadingPos
        && $FHEM::Automation::ShuttersControl::shutters->getStatus !=
        $FHEM::Automation::ShuttersControl::shutters->getComfortOpenPos
        && $FHEM::Automation::ShuttersControl::shutters->getStatus !=
        $FHEM::Automation::ShuttersControl::shutters->getVentilatePos
        && $FHEM::Automation::ShuttersControl::shutters->getStatus !=
        $FHEM::Automation::ShuttersControl::shutters->getAntiFreezePos
        && $FHEM::Automation::ShuttersControl::shutters->getLastDrive eq
        'manual' )
    {
        return 0;
    }
    elsif (
        (
            int( gettimeofday() ) -
            $FHEM::Automation::ShuttersControl::shutters->getLastManPosTimestamp
        ) <
        $FHEM::Automation::ShuttersControl::shutters->getBlockingTimeAfterManual
      )
    {
        return 0;
    }

    else { return 1 }
}

sub makeReadingName {
    my ($rname) = shift;
    my %charHash = (
        chr(0xe4) => "ae",    # ä
        chr(0xc4) => "Ae",    # Ä
        chr(0xfc) => "ue",    # ü
        chr(0xdc) => "Ue",    # Ü
        chr(0xf6) => "oe",    # ö
        chr(0xd6) => "Oe",    # Ö
        chr(0xdf) => "ss"     # ß
    );
    my $charHashkeys = join( "", keys(%charHash) );

    return $rname if ( $rname =~ m{^\./}xms );
    $rname =~ s/([$charHashkeys])/$charHash{$1}/xgi;
    $rname =~ s/[^a-z0-9._\-\/]/_/xgi;
    return $rname;
}

sub IsWe {
    return main::IsWe( shift, shift );
}

sub AverageBrightness {
    my @input = @_;
    use List::Util qw(sum);

    return int( sum(@input) / @input );
}

sub PerlCodeCheck {
    my $exec = shift;
    my $val  = undef;

    if ( $exec =~ m{\A\{(.+)\}\z}xms ) {
        $val = main::AnalyzePerlCommand( undef, $1 );
    }

    return $val;
}

sub IsAdv {
    my ( undef, undef, undef, $monthday, $month, $year, undef, undef, undef ) =
      localtime( gettimeofday() );
    my $adv = 0;
    $year += 1900;

    if ( $month < 1 ) {
        if ( $monthday < 7 ) {
            $adv = 1;
        }
    }
    else {
        my $time = HTTP::Date::str2time( $year . '-12-25' );
        my $wday = ( localtime($time) )[6];
        $wday = $wday ? $wday : 7;
        $time -= ( $wday + 21 ) * 86400;
        $adv = 1 if ( $time < time );
    }

    return $adv;
}

sub IsInTime {
    my $dfi = shift;

    $dfi =~ s/{([^\x7d]*)}/$cmdFromAnalyze=$1; eval $1/ge; # Forum #69787
    my ($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst) = localtime(gettimeofday());
    my $dhms = sprintf("%s\@%02d:%02d:%02d", $wday, $hour, $min, $sec);
    foreach my $ft (split(" ", $dfi)) {
        my ($from, $to) = split("-", $ft);
        if(defined($from) && defined($to)) {
            $from = "$wday\@$from" if(index($from,"@") < 0);
            $to   = "$wday\@$to"   if(index($to,  "@") < 0);
            return 1 if($from le $dhms && $dhms le $to);
        }
    }
    
    return 0;
}

1;
