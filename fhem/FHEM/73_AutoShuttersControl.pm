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

### Notizen
# !!!!! - Innerhalb einer Shutterschleife kein CommandAttr verwenden. Bring Fehler!!! Kommen Raumnamen in die Shutterliste !!!!!!
#

package main;

use strict;
use warnings;

sub ascAPIget {
    my ( $getCommand, $shutterDev, $value ) = @_;

    return AutoShuttersControl_ascAPIget( $getCommand, $shutterDev, $value );
}

## unserer packagename
package FHEM::AutoShuttersControl;

use strict;
use warnings;
use POSIX qw(strftime);
use utf8;
use Encode;
use FHEM::Meta;
use GPUtils qw(GP_Import GP_Export);
use Data::Dumper;    #only for Debugging
use Date::Parse;

# try to use JSON::MaybeXS wrapper
#   for chance of better performance + open code
eval {
    require JSON::MaybeXS;
    import JSON::MaybeXS qw( decode_json encode_json );
    1;
};

if ($@) {
    $@ = undef;

    # try to use JSON wrapper
    #   for chance of better performance
    eval {

        # JSON preference order
        local $ENV{PERL_JSON_BACKEND} =
          'Cpanel::JSON::XS,JSON::XS,JSON::PP,JSON::backportPP'
          unless ( defined( $ENV{PERL_JSON_BACKEND} ) );

        require JSON;
        import JSON qw( decode_json encode_json );
        1;
    };

    if ($@) {
        $@ = undef;

        # In rare cases, Cpanel::JSON::XS may
        #   be installed but JSON|JSON::MaybeXS not ...
        eval {
            require Cpanel::JSON::XS;
            import Cpanel::JSON::XS qw(decode_json encode_json);
            1;
        };

        if ($@) {
            $@ = undef;

            # In rare cases, JSON::XS may
            #   be installed but JSON not ...
            eval {
                require JSON::XS;
                import JSON::XS qw(decode_json encode_json);
                1;
            };

            if ($@) {
                $@ = undef;

                # Fallback to built-in JSON which SHOULD
                #   be available since 5.014 ...
                eval {
                    require JSON::PP;
                    import JSON::PP qw(decode_json encode_json);
                    1;
                };

                if ($@) {
                    $@ = undef;

                    # Fallback to JSON::backportPP in really rare cases
                    require JSON::backportPP;
                    import JSON::backportPP qw(decode_json encode_json);
                    1;
                }
            }
        }
    }
}

## Import der FHEM Funktionen
#-- Run before package compilation
BEGIN {

    # Import from main context
    GP_Import(
        qw(
          devspec2array
          readingsSingleUpdate
          readingsBulkUpdate
          readingsBulkUpdateIfChanged
          readingsBeginUpdate
          readingsEndUpdate
          defs
          modules
          Log3
          CommandAttr
          attr
          CommandDeleteAttr
          CommandDeleteReading
          CommandSet
          readingFnAttributes
          AttrVal
          ReadingsVal
          IsDisabled
          deviceEvents
          init_done
          addToDevAttrList
          addToAttrList
          delFromDevAttrList
          delFromAttrList
          gettimeofday
          sunset
          sunset_abs
          sunrise
          sunrise_abs
          InternalTimer
          RemoveInternalTimer
          computeAlignTime
          ReplaceEventMap)
    );
}

#-- Export to main context with different name
GP_Export(
    qw(
      Initialize
      ascAPIget
      DevStateIcon
      )
);

## Die Attributsliste welche an die Rolläden verteilt wird. Zusammen mit Default Werten
my %userAttrList = (
    'ASC_Mode_Up:absent,always,off,home'                            => '-',
    'ASC_Mode_Down:absent,always,off,home'                          => '-',
    'ASC_Up:time,astro,brightness,roommate'                         => '-',
    'ASC_Down:time,astro,brightness,roommate'                       => '-',
    'ASC_AutoAstroModeMorning:REAL,CIVIL,NAUTIC,ASTRONOMIC,HORIZON' => '-',
'ASC_AutoAstroModeMorningHorizon:-9,-8,-7,-6,-5,-4,-3,-2,-1,0,1,2,3,4,5,6,7,8,9'
      => '-',
    'ASC_AutoAstroModeEvening:REAL,CIVIL,NAUTIC,ASTRONOMIC,HORIZON' => '-',
'ASC_AutoAstroModeEveningHorizon:-9,-8,-7,-6,-5,-4,-3,-2,-1,0,1,2,3,4,5,6,7,8,9'
      => '-',
    'ASC_Open_Pos:0,10,20,30,40,50,60,70,80,90,100'   => [ '', 0,   100 ],
    'ASC_Closed_Pos:0,10,20,30,40,50,60,70,80,90,100' => [ '', 100, 0 ],
    'ASC_Sleep_Pos:0,10,20,30,40,50,60,70,80,90,100'  => '-',
    'ASC_Pos_Reading'                            => [ '', 'position', 'pct' ],
    'ASC_Time_Up_Early'                          => '-',
    'ASC_Time_Up_Late'                           => '-',
    'ASC_Time_Up_WE_Holiday'                     => '-',
    'ASC_Time_Down_Early'                        => '-',
    'ASC_Time_Down_Late'                         => '-',
    'ASC_PrivacyUpValue_beforeDayOpen'           => '-',
    'ASC_PrivacyDownValue_beforeNightClose'      => '-',
    'ASC_PrivacyUp_Pos'                          => '-',
    'ASC_PrivacyDown_Pos'                        => '-',
    'ASC_TempSensor'                             => '-',
    'ASC_Ventilate_Window_Open:on,off'           => '-',
    'ASC_LockOut:soft,hard,off'                  => '-',
    'ASC_LockOut_Cmd:inhibit,blocked,protection' => '-',
    'ASC_BlockingTime_afterManual'               => '-',
    'ASC_BlockingTime_beforNightClose'           => '-',
    'ASC_BlockingTime_beforDayOpen'              => '-',
    'ASC_BrightnessSensor'                       => '-',
    'ASC_Shading_Pos:10,20,30,40,50,60,70,80,90,100'       => [ '', 80, 20 ],
    'ASC_Shading_Mode:absent,always,off,home'              => '-',
    'ASC_Shading_InOutAzimuth'                             => '-',
    'ASC_Shading_StateChange_SunnyCloudy'                  => '-',
    'ASC_Shading_MinMax_Elevation'                         => '-',
    'ASC_Shading_Min_OutsideTemperature'                   => '-',
    'ASC_Shading_WaitingPeriod'                            => '-',
    'ASC_Drive_Delay'                                      => '-',
    'ASC_Drive_DelayStart'                                 => '-',
    'ASC_Shutter_IdleDetection'                            => '-',
    'ASC_WindowRec'                                        => '-',
    'ASC_WindowRec_subType:twostate,threestate'            => '-',
    'ASC_WindowRec_PosAfterDayClosed:open,lastManual'      => '-',
    'ASC_ShuttersPlace:window,terrace'                     => '-',
    'ASC_Ventilate_Pos:10,20,30,40,50,60,70,80,90,100'     => [ '', 70, 30 ],
    'ASC_ComfortOpen_Pos:0,10,20,30,40,50,60,70,80,90,100' => [ '', 20, 80 ],
    'ASC_GuestRoom:on,off'                                 => '-',
    'ASC_Antifreeze:off,soft,hard,am,pm'                   => '-',
'ASC_Antifreeze_Pos:5,10,15,20,25,30,35,40,45,50,55,60,65,70,75,80,85,90,95,100'
      => [ '', 85, 15 ],
    'ASC_Partymode:on,off'                  => '-',
    'ASC_Roommate_Device'                   => '-',
    'ASC_Roommate_Reading'                  => '-',
    'ASC_Self_Defense_Mode:absent,gone,off' => '-',
    'ASC_Self_Defense_AbsentDelay'          => '-',
    'ASC_WiggleValue'                       => '-',
    'ASC_WindParameters'                    => '-',
    'ASC_DriveUpMaxDuration'                => '-',
    'ASC_WindProtection:on,off'             => '-',
    'ASC_RainProtection:on,off'             => '-',
    'ASC_ExternalTrigger'                   => '-',
    'ASC_Adv:on,off'                        => '-'
);

my %posSetCmds = (
    ZWave       => 'dim',
    Siro        => 'pct',
    CUL_HM      => 'pct',
    ROLLO       => 'pct',
    SOMFY       => 'position',
    tahoma      => 'dim',
    KLF200Node  => 'pct',
    DUOFERN     => 'position',
    HM485       => 'level',
    SELVECommeo => 'position',
    SELVE       => 'position',
    EnOcean     => 'position',
);

## 2 Objekte werden erstellt
my $shutters = ASC_Shutters->new();
my $ascDev   = ASC_Dev->new();

sub ascAPIget {
    my ( $getCommand, $shutterDev, $value ) = @_;

    my $getter = 'get' . $getCommand;

    if ( defined($value) && $value ) {
        $shutters->setShuttersDev($shutterDev);
        return $shutters->$getter($value);
    }
    elsif ( defined($shutterDev) && $shutterDev ) {
        $shutters->setShuttersDev($shutterDev);
        return $shutters->$getter;
    }
    else {
        return $ascDev->$getter;
    }
}

sub Initialize {
    my $hash = shift;

## Da ich mit package arbeite müssen in die Initialize für die jeweiligen hash Fn Funktionen der Funktionsname
    #  und davor mit :: getrennt der eigentliche package Name des Modules
    $hash->{SetFn}    = \&Set;
    $hash->{GetFn}    = \&Get;
    $hash->{DefFn}    = \&Define;
    $hash->{NotifyFn} = \&Notify;
    $hash->{UndefFn}  = \&Undef;
    $hash->{AttrList} =
        'ASC_tempSensor '
      . 'ASC_brightnessDriveUpDown '
      . 'ASC_autoShuttersControlMorning:on,off '
      . 'ASC_autoShuttersControlEvening:on,off '
      . 'ASC_autoShuttersControlComfort:on,off '
      . 'ASC_residentsDev '
      . 'ASC_rainSensor '
      . 'ASC_autoAstroModeMorning:REAL,CIVIL,NAUTIC,ASTRONOMIC,HORIZON '
      . 'ASC_autoAstroModeMorningHorizon:-9,-8,-7,-6,-5,-4,-3,-2,-1,0,1,2,3,4,5,6,7,8,9 '
      . 'ASC_autoAstroModeEvening:REAL,CIVIL,NAUTIC,ASTRONOMIC,HORIZON '
      . 'ASC_autoAstroModeEveningHorizon:-9,-8,-7,-6,-5,-4,-3,-2,-1,0,1,2,3,4,5,6,7,8,9 '
      . 'ASC_freezeTemp:-5,-4,-3,-2,-1,0,1,2,3,4,5 '
      . 'ASC_shuttersDriveDelay '
      . 'ASC_twilightDevice '
      . 'ASC_windSensor '
      . 'ASC_expert:1 '
      . 'ASC_blockAscDrivesAfterManual:0,1 '
      . 'ASC_debug:1 '
      . $readingFnAttributes;
    $hash->{NotifyOrderPrefix} = '51-';    # Order Nummer für NotifyFn
    $hash->{FW_detailFn} = \&ShuttersInformation;
    $hash->{parseParams} = 1;

    return FHEM::Meta::InitMod( __FILE__, $hash );
}

sub Define {
    my $hash = shift;
    my $a    = shift;

    return $@ unless ( FHEM::Meta::SetInternals($hash) );
    use version 0.60; our $VERSION = FHEM::Meta::Get( $hash, 'version' );

    return 'only one AutoShuttersControl instance allowed'
      if ( devspec2array('TYPE=AutoShuttersControl') > 1 )
      ; # es wird geprüft ob bereits eine Instanz unseres Modules existiert,wenn ja wird abgebrochen
    return 'too few parameters: define <name> ShuttersControl'
      if ( scalar( @{$a} ) != 2 );

    my $name = shift @$a;
    $hash->{MID} = 'da39a3ee5e6b4b0d3255bfef95601890afd80709'
      ; # eine Ein Eindeutige ID für interne FHEM Belange / nicht weiter wichtig
    $hash->{VERSION}   = version->parse($VERSION)->normal;
    $hash->{NOTIFYDEV} = 'global,'
      . $name;    # Liste aller Devices auf deren Events gehört werden sollen
                  #$hash->{shutters} = $shutters;
                  #$hash->{ascDev} = $ascDev;
    $ascDev->setName($name);

    readingsSingleUpdate(
        $hash,
        'state',
'please set attribute ASC with value 1 or 2 in all auto controlled shutter devices and then execute \'set DEVICENAME scanForShutters\'',
        1
    );

    CommandAttr( undef, $name . ' room ASC' )
      if ( AttrVal( $name, 'room', 'none' ) eq 'none' );
    CommandAttr( undef, $name . ' icon fts_shutter_automatic' )
      if ( AttrVal( $name, 'icon', 'none' ) eq 'none' );
    CommandAttr( undef,
        $name . ' devStateIcon { AutoShuttersControl_DevStateIcon($name) }' )
      if ( AttrVal( $name, 'devStateIcon', 'none' ) eq 'none' );

    addToAttrList('ASC:0,1,2');

    Log3( $name, 3, "AutoShuttersControl ($name) - defined" );

    $modules{AutoShuttersControl}{defptr}{ $hash->{MID} } = $hash;

    return;
}

sub Undef {
    my $hash = shift;
    my $name = shift;

    UserAttributs_Readings_ForShutters( $hash, 'del' )
      ; # es sollen alle Attribute und Readings in den Rolläden Devices gelöscht werden welche vom Modul angelegt wurden
    delFromAttrList('ASC:0,1,2');

    delete( $modules{AutoShuttersControl}{defptr}{ $hash->{MID} } );

    Log3( $name, 3, "AutoShuttersControl ($name) - delete device $name" );
    return;
}

sub Notify {
    my $hash = shift;
    my $dev  = shift;

    my $name    = $hash->{NAME};
    my $devname = $dev->{NAME};
    my $devtype = $dev->{TYPE};
    my $events  = deviceEvents( $dev, 1 );
    return if ( !$events );

    Log3( $name, 4,
            "AutoShuttersControl ($name) - Devname: "
          . $devname
          . " Name: "
          . $name
          . " Notify: "
          . Dumper $events);    # mit Dumper

    if (
        (
            grep m{^DEFINED.$name$}xms,
            @{$events} and $devname eq 'global' and $init_done
        )
        or (
            grep m{^INITIALIZED$}xms,
            @{$events} or grep m{^REREADCFG$}xms,
            @{$events} or grep m{^MODIFIED.$name$}xms,
            @{$events}
        )
        and $devname eq 'global'
      )
    {
        readingsSingleUpdate( $hash, 'partyMode', 'off', 0 )
          if ( $ascDev->getPartyMode eq 'none' );
        readingsSingleUpdate( $hash, 'hardLockOut', 'off', 0 )
          if ( $ascDev->getHardLockOut eq 'none' );
        readingsSingleUpdate( $hash, 'sunriseTimeWeHoliday', 'off', 0 )
          if ( $ascDev->getSunriseTimeWeHoliday eq 'none' );
        readingsSingleUpdate( $hash, 'selfDefense', 'off', 0 )
          if ( $ascDev->getSelfDefense eq 'none' );
        readingsSingleUpdate( $hash, 'controlShading', 'off', 0 )
          if ( $ascDev->getAutoShuttersControlShading eq 'none' );
        readingsSingleUpdate( $hash, 'ascEnable', 'on', 0 )
          if ( $ascDev->getASCenable eq 'none' );
        CommandAttr( undef,
            $name
              . ' devStateIcon { AutoShuttersControl_DevStateIcon($name) }' )
          unless (
            AttrVal(
                $name, 'devStateIcon',
                '{ AutoShuttersControl_DevStateIcon($name) }'
            ) eq '{ AutoShuttersControl_DevStateIcon($name) }'
          );
        CommandDeleteAttr( undef, $name . ' event-on-change-reading' )
          unless (
            AttrVal( $name, 'event-on-change-reading', 'none' ) eq 'none' );
        CommandDeleteAttr( undef, $name . ' event-on-update-reading' )
          unless (
            AttrVal( $name, 'event-on-update-reading', 'none' ) eq 'none' );

# Ist der Event ein globaler und passt zum Rest der Abfrage oben wird nach neuen Rolläden Devices gescannt und eine Liste im Rolladenmodul sortiert nach Raum generiert
        ShuttersDeviceScan($hash)
          unless ( ReadingsVal( $name, 'userAttrList', 'none' ) eq 'none' );
    }
    return
      unless ( ref( $hash->{helper}{shuttersList} ) eq 'ARRAY'
        and scalar( @{ $hash->{helper}{shuttersList} } ) > 0 );

    my $posReading = $shutters->getPosCmd;

    if ( $devname eq $name ) {
        if ( grep m{^userAttrList:.rolled.out$}xms, @{$events} ) {
            unless ( scalar( @{ $hash->{helper}{shuttersList} } ) == 0 ) {
                WriteReadingsShuttersList($hash);
                UserAttributs_Readings_ForShutters( $hash, 'add' );
                InternalTimer( gettimeofday() + 3,
                    'FHEM::AutoShuttersControl::RenewSunRiseSetShuttersTimer',
                    $hash );
                InternalTimer( gettimeofday() + 5,
                    'FHEM::AutoShuttersControl::AutoSearchTwilightDev', $hash );
            }
        }
        elsif ( grep m{^partyMode:.off$}xms, @{$events} ) {
            EventProcessingPartyMode($hash);
        }
        elsif ( grep m{^sunriseTimeWeHoliday:.(on|off)$}xms, @{$events} ) {
            RenewSunRiseSetShuttersTimer($hash);
        }
    }
    elsif ( $devname eq "global" )
    { # Kommt ein globales Event und beinhaltet folgende Syntax wird die Funktion zur Verarbeitung aufgerufen
        if (
            grep
m{^(ATTR|DELETEATTR)\s(.*ASC_Time_Up_WE_Holiday|.*ASC_Up|.*ASC_Down|.*ASC_AutoAstroModeMorning|.*ASC_AutoAstroModeMorningHorizon|.*ASC_AutoAstroModeEvening|.*ASC_AutoAstroModeEveningHorizon|.*ASC_Time_Up_Early|.*ASC_Time_Up_Late|.*ASC_Time_Down_Early|.*ASC_Time_Down_Late|.*ASC_autoAstroModeMorning|.*ASC_autoAstroModeMorningHorizon|.*ASC_PrivacyDownValue_beforeNightClose|.*ASC_PrivacyUpValue_beforeDayOpen|.*ASC_autoAstroModeEvening|.*ASC_autoAstroModeEveningHorizon|.*ASC_Roommate_Device|.*ASC_WindowRec|.*ASC_residentsDev|.*ASC_rainSensor|.*ASC_windSensor|.*ASC_BrightnessSensor|.*ASC_twilightDevice|.*ASC_ExternalTrigger)(\s.*|$)}xms,
            @{$events}
          )
        {
            EventProcessingGeneral( $hash, undef, join( ' ', @{$events} ) );
        }
    }
    elsif ( grep m{^($posReading):\s\d+$}xms, @{$events} ) {
        ASC_Debug( 'Notify: '
              . ' ASC_Pos_Reading Event vom Rollo wurde erkannt '
              . ' - RECEIVED EVENT: '
              . Dumper $events);
        EventProcessingShutters( $hash, $devname, join( ' ', @{$events} ) );
    }
    else {
        EventProcessingGeneral( $hash, $devname, join( ' ', @{$events} ) )
          ; # bei allen anderen Events wird die entsprechende Funktion zur Verarbeitung aufgerufen
    }

    return;
}

sub EventProcessingGeneral {
    my ( $hash, $devname, $events ) = @_;
    my $name = $hash->{NAME};

    if ( defined($devname) && ($devname) )
    { # es wird lediglich der Devicename der Funktion mitgegeben wenn es sich nicht um global handelt daher hier die Unterscheidung
        while ( my ( $device, $deviceAttr ) =
            each %{ $hash->{monitoredDevs}{$devname} } )
        {
            EventProcessingWindowRec( $hash, $device, $events )
              if ( $deviceAttr eq 'ASC_WindowRec' )
              ;    # ist es ein Fensterdevice wird die Funktion gestartet
            EventProcessingRoommate( $hash, $device, $events )
              if ( $deviceAttr eq 'ASC_Roommate_Device' )
              ;    # ist es ein Bewohner Device wird diese Funktion gestartet
            EventProcessingResidents( $hash, $device, $events )
              if ( $deviceAttr eq 'ASC_residentsDev' );
            EventProcessingRain( $hash, $device, $events )
              if ( $deviceAttr eq 'ASC_rainSensor' );
            EventProcessingWind( $hash, $device, $events )
              if ( $deviceAttr eq 'ASC_windSensor' );
            EventProcessingTwilightDevice( $hash, $device, $events )
              if ( $deviceAttr eq 'ASC_twilightDevice' );
            EventProcessingExternalTriggerDevice( $hash, $device, $events )
              if ( $deviceAttr eq 'ASC_ExternalTrigger' );

            $shutters->setShuttersDev($device)
              if ( $deviceAttr eq 'ASC_BrightnessSensor' );

            if (
                $deviceAttr eq 'ASC_BrightnessSensor'
                && (   $shutters->getDown eq 'brightness'
                    || $shutters->getUp eq 'brightness' )
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
            AddNotifyDev( $hash, $3, $1, $2 ) if ( $3 ne 'none' );
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
            DeleteNotifyDev( $hash, $1, $2 );
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
            CreateSunRiseSetShuttersTimer( $hash, $2 )
              if (
                $3 ne 'ASC_Time_Up_WE_Holiday'
                || (   $3 eq 'ASC_Time_Up_WE_Holiday'
                    && $ascDev->getSunriseTimeWeHoliday eq 'on' )
              );
        }
        elsif (
            $events =~ m{^(DELETEATTR|ATTR)
                \s(.*)\s(ASC_autoAstroModeMorning|ASC_autoAstroModeMorningHorizon
                    |ASC_autoAstroModeEvening|ASC_autoAstroModeEveningHorizon)
                (.*)?}xms
          )
        {
            RenewSunRiseSetShuttersTimer($hash);
        }
    }

    return;
}

sub Set {
    my $hash = shift;
    my $a    = shift;

    my $name = shift @$a;
    my $cmd  = shift @$a // return qq{"set $name" needs at least one argument};

    if ( lc $cmd eq 'renewalltimer' ) {
        return "usage: $cmd" if ( scalar( @{$a} ) != 0 );
        RenewSunRiseSetShuttersTimer($hash);
    }
    elsif ( lc $cmd eq 'renewtimer' ) {
        return "usage: $cmd" if ( scalar( @{$a} ) > 1 );
        CreateSunRiseSetShuttersTimer( $hash, $a->[0] );
    }
    elsif ( lc $cmd eq 'scanforshutters' ) {
        return "usage: $cmd" if ( scalar( @{$a} ) != 0 );
        ShuttersDeviceScan($hash);
    }
    elsif ( lc $cmd eq 'createnewnotifydev' ) {
        return "usage: $cmd" if ( scalar( @{$a} ) != 0 );
        CreateNewNotifyDev($hash);
    }
    elsif ( lc $cmd eq 'partymode' ) {
        return "usage: $cmd" if ( scalar( @{$a} ) > 1 );
        readingsSingleUpdate( $hash, $cmd, $a->[0], 1 )
          if ( $a->[0] ne ReadingsVal( $name, 'partyMode', 0 ) );
    }
    elsif ( lc $cmd eq 'hardlockout' ) {
        return "usage: $cmd" if ( scalar( @{$a} ) > 1 );
        readingsSingleUpdate( $hash, $cmd, $a->[0], 1 );
        HardewareBlockForShutters( $hash, $a->[0] );
    }
    elsif ( lc $cmd eq 'sunrisetimeweholiday' ) {
        return "usage: $cmd" if ( scalar( @{$a} ) > 1 );
        readingsSingleUpdate( $hash, $cmd, $a->[0], 1 );
    }
    elsif ( lc $cmd eq 'controlshading' ) {
        return "usage: $cmd" if ( scalar( @{$a} ) > 1 );
        readingsSingleUpdate( $hash, $cmd, $a->[0], 1 );
    }
    elsif ( lc $cmd eq 'selfdefense' ) {
        return "usage: $cmd" if ( scalar( @{$a} ) > 1 );
        readingsSingleUpdate( $hash, $cmd, $a->[0], 1 );
    }
    elsif ( lc $cmd eq 'ascenable' ) {
        return "usage: $cmd" if ( scalar( @{$a} ) > 1 );
        readingsSingleUpdate( $hash, $cmd, $a->[0], 1 );
    }
    elsif ( lc $cmd eq 'advdrivedown' ) {
        return "usage: $cmd" if ( scalar( @{$a} ) != 0 );
        EventProcessingAdvShuttersClose($hash);
    }
    elsif ( lc $cmd eq 'shutterascenabletoggle' ) {
        return "usage: $cmd" if ( scalar( @{$a} ) > 1 );
        readingsSingleUpdate(
            $defs{ $a->[0] },
            'ASC_Enable',
            (
                ReadingsVal( $a->[0], 'ASC_Enable', 'off' ) eq 'on'
                ? 'off'
                : 'on'
            ),
            1
        );
    }
    elsif ( lc $cmd eq 'wiggle' ) {
        return "usage: $cmd" if ( scalar( @{$a} ) > 1 );

        ( $a->[0] eq 'all' ? wiggleAll($hash) : wiggle( $hash, $a->[0] ) );
    }
    else {
        my $list = 'scanForShutters:noArg';
        $list .=
' renewAllTimer:noArg advDriveDown:noArg partyMode:on,off hardLockOut:on,off sunriseTimeWeHoliday:on,off controlShading:on,off selfDefense:on,off ascEnable:on,off wiggle:all,'
          . join( ',', @{ $hash->{helper}{shuttersList} } )
          . ' shutterASCenableToggle:'
          . join( ',', @{ $hash->{helper}{shuttersList} } )
          . ' renewTimer:'
          . join( ',', @{ $hash->{helper}{shuttersList} } )
          if ( ReadingsVal( $name, 'userAttrList', 'none' ) eq 'rolled out'
            && defined( $hash->{helper}{shuttersList} )
            && scalar( @{ $hash->{helper}{shuttersList} } ) > 0 );
        $list .= ' createNewNotifyDev:noArg'
          if ( ReadingsVal( $name, 'userAttrList', 'none' ) eq 'rolled out'
            && AttrVal( $name, 'ASC_expert', 0 ) == 1 );

        return "Unknown argument $cmd,choose one of $list";
    }
    return;
}

sub Get {
    my $hash = shift;
    my $a    = shift;

    my $name = shift @$a;
    my $cmd  = shift @$a // return qq{"set $name" needs at least one argument};

    if ( lc $cmd eq 'shownotifydevsinformations' ) {
        return "usage: $cmd" if ( scalar( @{$a} ) != 0 );
        my $ret = GetMonitoredDevs($hash);
        return $ret;
    }
    else {
        my $list = "";
        $list .= " showNotifyDevsInformations:noArg"
          if ( ReadingsVal( $name, 'userAttrList', 'none' ) eq 'rolled out'
            && AttrVal( $name, 'ASC_expert', 0 ) == 1 );

        return "Unknown argument $cmd,choose one of $list";
    }
}

sub ShuttersDeviceScan {
    my $hash = shift;

    my $name = $hash->{NAME};

    delete $hash->{helper}{shuttersList};

    my @list;
    @list = devspec2array('ASC=[1-2]');

    CommandDeleteReading( undef, $name . ' .*_nextAstroTimeEvent' );

    unless ( scalar(@list) > 0 ) {
        readingsBeginUpdate($hash);
        readingsBulkUpdate( $hash, 'userAttrList', 'none' );
        readingsBulkUpdate( $hash, 'state',        'no shutters found' );
        readingsEndUpdate( $hash, 1 );
        return;
    }
    my $shuttersList = '';
    for (@list) {
        push( @{ $hash->{helper}{shuttersList} }, $_ )
          ; ## einem Hash wird ein Array zugewiesen welches die Liste der erkannten Rollos beinhaltet

        $shutters->setShuttersDev($_);

        #### Ab hier können temporäre Änderungen der Attribute gesetzt werden
        #### Gleichlautende Attribute wo lediglich die Parameter geändert werden sollen müssen hier gelöscht und die Parameter in der Funktion renewSetSunriseSunsetTimer gesetzt werden,
        #### vorher empfiehlt es sich die dort vergebenen Parameter aus zu lesen um sie dann hier wieder neu zu setzen. Dazu wird das shutters Objekt um einen Eintrag
        #### 'AttrUpdateChanges' erweitert
        if ( ReadingsVal( $_, '.ASC_AttrUpdateChanges_' . $hash->{VERSION}, 0 )
            == 0 )
        {
      #             $shutters->setAttrUpdateChanges( 'ASC_Up',
      #                 AttrVal( $_, 'ASC_Up', 'none' ) );
      #             delFromDevAttrList( $_, 'ASC_Up' );
      #             $shutters->setAttrUpdateChanges( 'ASC_Down',
      #                 AttrVal( $_, 'ASC_Down', 'none' ) );
      #             delFromDevAttrList( $_, 'ASC_Down' );
      #             $shutters->setAttrUpdateChanges( 'ASC_Self_Defense_Mode',
      #                 AttrVal( $_, 'ASC_Self_Defense_Mode', 'none' ) );
      #             delFromDevAttrList( $_, 'ASC_Self_Defense_Mode' );
      #             $shutters->setAttrUpdateChanges( 'ASC_Self_Defense_Exclude',
      #                 AttrVal( $_, 'ASC_Self_Defense_Exclude', 'none' ) );
      #             delFromDevAttrList( $_, 'ASC_Self_Defense_Exclude' );
        }

        ####
        ####

        $shuttersList = $shuttersList . ',' . $_;
        $shutters->setLastManPos( $shutters->getStatus );
        $shutters->setLastPos( $shutters->getStatus );
        $shutters->setDelayCmd('none');
        $shutters->setNoDelay(0);
        $shutters->setSelfDefenseAbsent( 0, 0 );
        $shutters->setPosSetCmd( $posSetCmds{ $defs{$_}->{TYPE} } );
        $shutters->setShadingStatus(
            ( $shutters->getStatus != $shutters->getShadingPos ? 'out' : 'in' )
        );
        $shutters->setShadingLastStatus(
            ( $shutters->getStatus != $shutters->getShadingPos ? 'in' : 'out' )
        );
        $shutters->setPushBrightnessInArray( $shutters->getBrightness );
        readingsSingleUpdate( $defs{$_}, 'ASC_Enable', 'on', 0 )
          if ( ReadingsVal( $_, 'ASC_Enable', 'none' ) eq 'none' );

        if ( $shutters->getIsDay ) {
            $shutters->setSunrise(1);
            $shutters->setSunset(0);
        }
        else {
            $shutters->setSunrise(0);
            $shutters->setSunset(1);
        }
    }

    $hash->{NOTIFYDEV} = "global," . $name . $shuttersList;

    if ( $ascDev->getMonitoredDevs ne 'none' ) {
        $hash->{monitoredDevs} =
          eval { decode_json( $ascDev->getMonitoredDevs ) };
        my $notifyDevString = $hash->{NOTIFYDEV};
        while ( each %{ $hash->{monitoredDevs} } ) {
            $notifyDevString .= ',' . $_;
        }
        $hash->{NOTIFYDEV} = $notifyDevString;
    }

    readingsSingleUpdate( $hash, 'userAttrList', 'rolled out', 1 );

    return;
}

## Die Funktion schreibt in das Moduldevice Readings welche Rolläden in welchen Räumen erfasst wurden.
sub WriteReadingsShuttersList {
    my $hash = shift;

    my $name = $hash->{NAME};

    CommandDeleteReading( undef, $name . ' room_.*' );

    readingsBeginUpdate($hash);
    for ( @{ $hash->{helper}{shuttersList} } ) {
        readingsBulkUpdate(
            $hash,
            'room_' . makeReadingName( AttrVal( $_, 'room', 'unsorted' ) ),
            ReadingsVal(
                $name,
                'room_' . makeReadingName( AttrVal( $_, 'room', 'unsorted' ) ),
                ''
              )
              . ','
              . $_
          )
          if (
            ReadingsVal(
                $name,
                'room_' . makeReadingName( AttrVal( $_, 'room', 'unsorted' ) ),
                'none'
            ) ne 'none'
          );

        readingsBulkUpdate( $hash,
            'room_' . makeReadingName( AttrVal( $_, 'room', 'unsorted' ) ), $_ )
          if (
            ReadingsVal(
                $name,
                'room_' . makeReadingName( AttrVal( $_, 'room', 'unsorted' ) ),
                'none'
            ) eq 'none'
          );
    }
    readingsBulkUpdate( $hash, 'state', 'active' );
    readingsEndUpdate( $hash, 0 );

    return;
}

sub UserAttributs_Readings_ForShutters {
    my $hash = shift;
    my $cmd  = shift;

    my $name = $hash->{NAME};

    while ( my ( $attrib, $attribValue ) = each %{userAttrList} ) {
        for ( @{ $hash->{helper}{shuttersList} } ) {
            addToDevAttrList( $_, $attrib )
              ; ## fhem.pl bietet eine Funktion um ein userAttr Attribut zu befüllen. Wir schreiben also in den Attribut userAttr alle unsere Attribute rein. Pro Rolladen immer ein Attribut pro Durchlauf
            ## Danach werden die Attribute die im userAttr stehen gesetzt und mit default Werten befüllt
            ## CommandAttr hat nicht funktioniert. Führte zu Problemen
            ## https://github.com/LeonGaultier/fhem-AutoShuttersControl/commit/e33d3cc7815031b087736c1054b98c57817e7083
            if ( $cmd eq 'add' ) {
                if ( ref($attribValue) ne 'ARRAY' ) {
                    $attr{$_}{ ( split( ':', $attrib ) )[0] } = $attribValue
                      if ( !defined( $attr{$_}{ ( split( ':', $attrib ) )[0] } )
                        && $attribValue ne '-' );
                }
                else {
                    $attr{$_}{ ( split( ':', $attrib ) )[0] } =
                      $attribValue->[ AttrVal( $_, 'ASC', 2 ) ]
                      if ( !defined( $attr{$_}{ ( split( ':', $attrib ) )[0] } )
                        && $attrib eq 'ASC_Pos_Reading' );
                }

                ### associatedWith damit man sieht das der Rollladen mit einem ASC Device verbunden ist
                my $associatedString =
                  ReadingsVal( $_, 'associatedWith', 'none' );
                if ( $associatedString ne 'none' ) {
                    my %hash;
                    %hash = map { ( $_ => 1 ) }
                      split( ',', "$associatedString,$name" );

                    readingsSingleUpdate( $defs{$_},
                        'associatedWith', join( ',', sort keys %hash ), 0 );
                }
                else {
                    readingsSingleUpdate( $defs{$_},
                        'associatedWith', $name, 0 );
                }
                #######################################
            }
            ## Oder das Attribut wird wieder gelöscht.
            elsif ( $cmd eq 'del' ) {
                $shutters->setShuttersDev($_);

                RemoveInternalTimer( $shutters->getInTimerFuncHash );
                CommandDeleteReading( undef, $_ . ' .?(ASC)_.*' );
                CommandDeleteAttr( undef, $_ . ' ASC' );
                delFromDevAttrList( $_, $attrib );

                ### associatedWith wird wieder entfernt
                my $associatedString =
                  ReadingsVal( $_, 'associatedWith', 'none' );
                my %hash;
                %hash = map { ( $_ => 1 ) }
                  grep { " $name " !~ m{ $_ }xms }
                  split( ',', "$associatedString,$name" );

                if ( keys %hash > 1 ) {
                    readingsSingleUpdate( $defs{$_},
                        'associatedWith', join( ',', sort keys %hash ), 0 );
                }
                else { CommandDeleteReading( undef, $_ . ' associatedWith' ); }
                ###################################
            }
        }
    }

    return;
}

## Fügt dem NOTIFYDEV Hash weitere Devices hinzu
sub AddNotifyDev {
    ### Beispielaufruf: AddNotifyDev( $hash, $3, $1, $2 ) if ( $3 ne 'none' );
    my ( $hash, $dev, $shuttersDev, $shuttersAttr ) = @_;

    $dev = ( split( ':', $dev ) )[0];
    my ( $key, $value ) = split( ':', ( split( ' ', $dev ) )[0], 2 )
      ; ## Wir versuchen die Device Attribute anders zu setzen. device=DEVICE reading=READING
    $dev = $key;

    my $name = $hash->{NAME};

    my $notifyDev = $hash->{NOTIFYDEV};
    $notifyDev = '' if ( !$notifyDev );

    my %hash;
    %hash = map { ( $_ => 1 ) }
      split( ',', "$notifyDev,$dev" );

    $hash->{NOTIFYDEV} = join( ',', sort keys %hash );

    my @devs = split( ',', $dev );
    for (@devs) {
        $hash->{monitoredDevs}{$_}{$shuttersDev} = $shuttersAttr;
    }

    readingsSingleUpdate( $hash, '.monitoredDevs',
        eval { encode_json( $hash->{monitoredDevs} ) }, 0 );

    return;
}

## entfernt aus dem NOTIFYDEV Hash Devices welche als Wert in Attributen steckten
sub DeleteNotifyDev {
    my ( $hash, $shuttersDev, $shuttersAttr ) = @_;

    my $name = $hash->{NAME};

    my $notifyDevs =
      ExtractNotifyDevFromEvent( $hash, $shuttersDev, $shuttersAttr );

    for my $notifyDev ( keys( %{$notifyDevs} ) ) {
        Log3( $name, 4,
            "AutoShuttersControl ($name) - DeleteNotifyDev - NotifyDev: "
              . $_ );
        delete $hash->{monitoredDevs}{$notifyDev}{$shuttersDev};

        if ( !keys %{ $hash->{monitoredDevs}{$notifyDev} } ) {
            delete $hash->{monitoredDevs}{$notifyDev};
            my $notifyDevString = $hash->{NOTIFYDEV};
            $notifyDevString = '' if ( !$notifyDevString );
            my %hash;
            %hash = map { ( $_ => 1 ) }
              grep { " $notifyDev " !~ m{ $_ }xms }
              split( ',', "$notifyDevString,$notifyDev" );

            $hash->{NOTIFYDEV} = join( ',', sort keys %hash );
        }
    }
    readingsSingleUpdate( $hash, '.monitoredDevs',
        eval { encode_json( $hash->{monitoredDevs} ) }, 0 );

    return;
}

## Sub zum steuern der Rolläden bei einem Fenster Event
sub EventProcessingWindowRec {
    my ( $hash, $shuttersDev, $events ) = @_;

    my $name = $hash->{NAME};

    my $reading = $shutters->getWinDevReading;

    if ( $events =~
        m{.*$reading:.*?([Oo]pen(?>ed)?|[Cc]losed?|tilt(?>ed)?|true|false)}xms
        && IsAfterShuttersManualBlocking($shuttersDev) )
    {
        my $match = $1;

        ASC_Debug( 'EventProcessingWindowRec: '
              . $shutters->getShuttersDev
              . ' - RECEIVED EVENT: '
              . $events
              . ' - IDENTIFIED EVENT: '
              . $1
              . ' - STORED EVENT: '
              . $match );

        $shutters->setShuttersDev($shuttersDev);
        my $homemode = $shutters->getRoommatesStatus;
        $homemode = $ascDev->getResidentsStatus if ( $homemode eq 'none' );

        #### Hardware Lock der Rollläden
        $shutters->setHardLockOut('off')
          if ( $match =~ m{[Cc]lose|true}xms
            && $shutters->getShuttersPlace eq 'terrace' );
        $shutters->setHardLockOut('on')
          if ( $match =~ m{[Oo]pen|false}xms
            && $shutters->getShuttersPlace eq 'terrace' );

        ASC_Debug( 'EventProcessingWindowRec: '
              . $shutters->getShuttersDev
              . ' - HOMEMODE: '
              . $homemode
              . ' QueryShuttersPosWinRecTilted:'
              . $shutters->getQueryShuttersPos( $shutters->getVentilatePos )
              . ' QueryShuttersPosWinRecComfort: '
              . $shutters->getQueryShuttersPos( $shutters->getComfortOpenPos )
        );

        if (
               $match =~ m{[Cc]lose|true}xms
            && IsAfterShuttersTimeBlocking($shuttersDev)
            && (
                   $shutters->getStatus == $shutters->getVentilatePos
                || $shutters->getStatus == $shutters->getComfortOpenPos
                || $shutters->getStatus == $shutters->getOpenPos
                || (   $shutters->getStatus == $shutters->getPrivacyDownPos
                    && $shutters->getPrivacyDownStatus == 1
                    && !$shutters->getIsDay )
            )
            && (   $shutters->getVentilateOpen eq 'on'
                || $ascDev->getAutoShuttersControlComfort eq 'on' )
          )
        {
            ASC_Debug( 'EventProcessingWindowRec: '
                  . $shutters->getShuttersDev
                  . ' Event Closed' );

            if (
                $shutters->getIsDay
                && ( ( $homemode ne 'asleep' && $homemode ne 'gotosleep' )
                    || $homemode eq 'none' )
                && $shutters->getModeUp ne 'absent'
                && $shutters->getModeUp ne 'off'
              )
            {
                if (   $shutters->getIfInShading
                    && $shutters->getShadingPos != $shutters->getStatus
                    && $shutters->getShadingMode ne 'absent' )
                {
                    $shutters->setLastDrive('shading in');
                    $shutters->setNoDelay(1);
                    $shutters->setDriveCmd( $shutters->getShadingPos );
                }
                elsif (
                    !$shutters->getIfInShading
                    && (   $shutters->getStatus != $shutters->getOpenPos
                        || $shutters->getStatus != $shutters->getLastManPos )
                  )
                {
                    if ( $shutters->getPrivacyDownStatus == 2 ) {
                        $shutters->setLastDrive(
                            'window closed at privacy night close');
                        $shutters->setNoDelay(1);
                        $shutters->setDriveCmd( $shutters->getPrivacyDownPos );
                    }
                    else {
                        $shutters->setLastDrive('window closed at day');
                        $shutters->setNoDelay(1);
                        $shutters->setDriveCmd(
                            (
                                $shutters->getVentilatePosAfterDayClosed eq
                                  'open'
                                ? $shutters->getOpenPos
                                : $shutters->getLastManPos
                            )
                        );
                    }
                }
            }
            elsif (
                   $shutters->getModeDown ne 'absent'
                && $shutters->getModeDown ne 'off'
                && (  !$shutters->getIsDay
                    || $homemode eq 'asleep'
                    || $homemode eq 'gotosleep' )
                && $ascDev->getAutoShuttersControlEvening eq 'on'
              )
            {
                if ( $shutters->getPrivacyUpStatus == 2 ) {
                    $shutters->setLastDrive(
                        'window closed at privacy day open');
                    $shutters->setNoDelay(1);
                    $shutters->setDriveCmd( $shutters->getPrivacyDownPos );
                }
                else {
                    $shutters->setLastDrive('window closed at night');
                    $shutters->setNoDelay(1);
                    $shutters->setDriveCmd(
                        (
                              $shutters->getSleepPos > 0
                            ? $shutters->getSleepPos
                            : $shutters->getClosedPos
                        )
                    );
                }
            }
        }
        elsif (
            (
                $match =~ m{tilt}xms || ( $match =~ m{[Oo]pen|false}xms
                    && $shutters->getSubTyp eq 'twostate' )
            )
            && $shutters->getVentilateOpen eq 'on'
            && $shutters->getQueryShuttersPos( $shutters->getVentilatePos )
          )
        {
            $shutters->setLastDrive('ventilate - window open');
            $shutters->setNoDelay(1);
            $shutters->setDriveCmd(
                (
                    (
                             $shutters->getShuttersPlace eq 'terrace'
                          && $shutters->getSubTyp eq 'twostate'
                    ) ? $shutters->getOpenPos : $shutters->getVentilatePos
                )
            );
        }
        elsif ($match =~ m{[Oo]pen|false}xms
            && $shutters->getSubTyp eq 'threestate' )
        {
            my $posValue;
            my $setLastDrive;
            if (    $ascDev->getAutoShuttersControlComfort eq 'on'
                and
                $shutters->getQueryShuttersPos( $shutters->getComfortOpenPos ) )
            {
                $posValue     = $shutters->getComfortOpenPos;
                $setLastDrive = 'comfort - window open';
            }
            elsif ($shutters->getQueryShuttersPos( $shutters->getVentilatePos )
                && $shutters->getVentilateOpen eq 'on' )
            {
                $posValue     = $shutters->getVentilatePos;
                $setLastDrive = 'ventilate - window open';
            }

            if ( defined($posValue) && $posValue ) {
                $shutters->setLastDrive($setLastDrive);
                $shutters->setNoDelay(1);
                $shutters->setDriveCmd($posValue);
            }
        }
    }

    return;
}

## Sub zum steuern der Rolladen bei einem Bewohner/Roommate Event
sub EventProcessingRoommate {
    my ( $hash, $shuttersDev, $events ) = @_;

    my $name = $hash->{NAME};

    $shutters->setShuttersDev($shuttersDev);
    my $reading = $shutters->getRoommatesReading;

    if ( $events =~ m{$reading:\s(absent|gotosleep|asleep|awoken|home)}xms ) {
        Log3( $name, 4,
            "AutoShuttersControl ($name) - EventProcessingRoommate: "
              . $shutters->getRoommatesReading );
        Log3( $name, 4,
"AutoShuttersControl ($name) - EventProcessingRoommate: $shuttersDev und Events $events"
        );

        my $getModeUp              = $shutters->getModeUp;
        my $getModeDown            = $shutters->getModeDown;
        my $getRoommatesStatus     = $shutters->getRoommatesStatus;
        my $getRoommatesLastStatus = $shutters->getRoommatesLastStatus;
        my $posValue;

        if (
            ( $1 eq 'home' || $1 eq 'awoken' )
            && (   $getRoommatesStatus eq 'home'
                || $getRoommatesStatus eq 'awoken' )
            && (   $ascDev->getAutoShuttersControlMorning eq 'on'
                || $shutters->getUp eq 'roommate' )
            && IsAfterShuttersManualBlocking($shuttersDev)
          )
        {
            Log3( $name, 4,
"AutoShuttersControl ($name) - EventProcessingRoommate_1: $shuttersDev und Events $events"
            );
            if (
                (
                       $getRoommatesLastStatus eq 'asleep'
                    || $getRoommatesLastStatus eq 'awoken'
                )
                && (   $shutters->getIsDay
                    || $shutters->getUp eq 'roommate' )
                && ( IsAfterShuttersTimeBlocking($shuttersDev)
                    || $shutters->getUp eq 'roommate' )
              )
            {
                Log3( $name, 4,
"AutoShuttersControl ($name) - EventProcessingRoommate_2: $shuttersDev und Events $events"
                );

                if (   $shutters->getIfInShading
                    && !$shutters->getShadingManualDriveStatus
                    && $shutters->getStatus != $shutters->getShadingPos )
                {
                    $shutters->setLastDrive('shading in');
                    $posValue = $shutters->getShadingPos;
                }
                else {
                    $shutters->setLastDrive('roommate awoken');
                    $posValue = $shutters->getOpenPos;
                }

                ShuttersCommandSet( $hash, $shuttersDev, $posValue );
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
                       !$shutters->getIsDay
                    && IsAfterShuttersTimeBlocking($shuttersDev)
                    && (   $getModeDown eq 'home'
                        || $getModeDown eq 'always' )
                    && $shutters->getDown ne 'roommate'
                  )
                {
                    $shutters->setLastDrive('roommate come home');

                    if ( CheckIfShuttersWindowRecOpen($shuttersDev) == 0
                        || $shutters->getVentilateOpen eq 'off' )
                    {
                        $posValue = (
                            $shutters->getSleepPos > 0 ? $shutters->getSleepPos
                            : (
                                  $shutters->getSleepPos > 0
                                ? $shutters->getSleepPos
                                : $shutters->getClosedPos
                            )
                        );
                    }
                    else {
                        $posValue = $shutters->getVentilatePos;
                        $shutters->setLastDrive(
                            $shutters->getLastDrive . ' - ventilate mode' );
                    }

                    ShuttersCommandSet( $hash, $shuttersDev, $posValue );
                }
                elsif (
                       ( $shutters->getIsDay || $shutters->getUp eq 'roommate' )
                    && IsAfterShuttersTimeBlocking($shuttersDev)
                    && (   $getModeUp eq 'home'
                        || $getModeUp eq 'always' )
                  )
                {
                    if (   $shutters->getIfInShading
                        && !$shutters->getShadingManualDriveStatus
                        && $shutters->getStatus == $shutters->getOpenPos
                        && $shutters->getShadingMode eq 'home' )
                    {
                        $shutters->setLastDrive('shading in');
                        ShuttersCommandSet( $hash, $shuttersDev,
                            $shutters->getShadingPos );
                    }
                    elsif (
                        (
                              !$shutters->getIfInShading
                            || $shutters->getShadingMode eq 'absent'
                        )
                        && (   $shutters->getStatus == $shutters->getClosedPos
                            || $shutters->getStatus == $shutters->getSleepPos
                            || $shutters->getStatus ==
                            $shutters->getShadingPos )
                      )
                    {
                        $shutters->setLastDrive(
                            (
                                (
                                    $shutters->getStatus ==
                                      $shutters->getClosedPos
                                      || $shutters->getStatus ==
                                      $shutters->getSleepPos
                                )
                                ? 'roommate come home'
                                : 'shading out'
                            )
                        );

                        ShuttersCommandSet( $hash, $shuttersDev,
                            $shutters->getOpenPos );
                    }
                }
            }
        }
        elsif (
            ( $1 eq 'gotosleep' || $1 eq 'asleep' )
            && (   $ascDev->getAutoShuttersControlEvening eq 'on'
                || $shutters->getDown eq 'roommate' )
            && ( IsAfterShuttersManualBlocking($shuttersDev)
                || $shutters->getDown eq 'roommate' )
          )
        {
            $shutters->setLastDrive('roommate asleep');

            if ( CheckIfShuttersWindowRecOpen($shuttersDev) == 0
                || $shutters->getVentilateOpen eq 'off' )
            {
                $posValue = (
                      $shutters->getSleepPos > 0
                    ? $shutters->getSleepPos
                    : $shutters->getClosedPos
                );
            }
            else {
                $posValue = $shutters->getVentilatePos;
                $shutters->setLastDrive(
                    $shutters->getLastDrive . ' - ventilate mode' );
            }

            ShuttersCommandSet( $hash, $shuttersDev, $posValue );
        }
        elsif (
            $1 eq 'absent'
            && (  !$shutters->getIsDay
                || $shutters->getDown eq 'roommate'
                || $shutters->getShadingMode eq 'absent'
                || $shutters->getModeUp eq 'absent'
                || $shutters->getModeDown eq 'absent' )
          )
        {
            Log3( $name, 4,
"AutoShuttersControl ($name) - EventProcessingRoommate absent: $shuttersDev"
            );

            if (   ( $shutters->getIsDay || $shutters->getUp eq 'roommate' )
                && $shutters->getIfInShading
                && !$shutters->getQueryShuttersPos( $shutters->getShadingPos )
                && $shutters->getShadingMode eq 'absent' )
            {
                Log3( $name, 4,
"AutoShuttersControl ($name) - EventProcessingRoommate Shading: $shuttersDev"
                );

                $shutters->setLastDrive('shading in');
                ShuttersCommandSet( $hash, $shuttersDev,
                    $shutters->getShadingPos );
            }
            elsif (( !$shutters->getIsDay || $shutters->getDown eq 'roommate' )
                && $getModeDown eq 'absent'
                && $getRoommatesStatus eq 'absent' )
            {
                Log3( $name, 4,
"AutoShuttersControl ($name) - EventProcessingRoommate Down: $shuttersDev"
                );

                $shutters->setLastDrive('roommate absent');
                ShuttersCommandSet( $hash, $shuttersDev,
                    $shutters->getClosedPos );
            }
            elsif ($shutters->getIsDay
                && $shutters->getModeUp eq 'absent'
                && $getRoommatesStatus eq 'absent' )
            {
                Log3( $name, 4,
"AutoShuttersControl ($name) - EventProcessingRoommate Up: $shuttersDev"
                );

                $shutters->setLastDrive('roommate absent');
                ShuttersCommandSet( $hash, $shuttersDev,
                    $shutters->getOpenPos );
            }

            Log3( $name, 4,
"AutoShuttersControl ($name) - EventProcessingRoommate NICHTS: $shuttersDev"
            );
        }
    }

    return;
}

sub EventProcessingResidents {
    my ( $hash, $device, $events ) = @_;

    my $name                   = $device;
    my $reading                = $ascDev->getResidentsReading;
    my $getResidentsLastStatus = $ascDev->getResidentsLastStatus;

    if ( $events =~ m{$reading:\s((?:pet_[a-z]+)|(?:absent))}xms ) {
        for my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
            $shutters->setShuttersDev($shuttersDev);
            my $getModeUp   = $shutters->getModeUp;
            my $getModeDown = $shutters->getModeDown;
            $shutters->setHardLockOut('off');
            if (
                   $ascDev->getSelfDefense eq 'on'
                && $shutters->getSelfDefenseMode ne 'off'
                || (   $getModeDown eq 'absent'
                    || $getModeDown eq 'always' )
              )
            {
                if (
                    $ascDev->getSelfDefense eq 'on'
                    && (
                        $shutters->getSelfDefenseMode eq 'absent'
                        || (   CheckIfShuttersWindowRecOpen($shuttersDev) == 2
                            && $shutters->getSelfDefenseMode eq 'gone'
                            && $shutters->getShuttersPlace eq 'terrace'
                            && $shutters->getSelfDefenseMode ne 'off' )
                    )
                  )
                {
                    $shutters->setLastDrive('selfDefense absent active');
                    $shutters->setSelfDefenseAbsent( 0, 1 )
                      ; # der erste Wert ist ob der timer schon läuft, der zweite ist ob self defense aktiv ist durch die Bedingungen
                    $shutters->setSelfDefenseState(1);
                    $shutters->setDriveCmd( $shutters->getClosedPos );
                }
                elsif (( $getModeDown eq 'absent' || $getModeDown eq 'always' )
                    && !$shutters->getIsDay
                    && IsAfterShuttersTimeBlocking($shuttersDev)
                    && $shutters->getRoommatesStatus eq 'none' )
                {
                    $shutters->setLastDrive('residents absent');
                    $shutters->setDriveCmd( $shutters->getClosedPos );
                }
            }
        }
    }
    elsif ($events =~ m{$reading:\s(gone)}xms
        && $ascDev->getSelfDefense eq 'on' )
    {
        for my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
            $shutters->setShuttersDev($shuttersDev);
            $shutters->setHardLockOut('off');
            if ( $shutters->getSelfDefenseMode ne 'off' ) {

                $shutters->setLastDrive('selfDefense gone active');
                $shutters->setSelfDefenseState(1);
                $shutters->setDriveCmd( $shutters->getClosedPos );
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
            $shutters->setShuttersDev($shuttersDev);
            my $getModeUp   = $shutters->getModeUp;
            my $getModeDown = $shutters->getModeDown;

            if (
                (
                       $shutters->getStatus != $shutters->getClosedPos
                    || $shutters->getStatus != $shutters->getSleepPos
                )
                && !$shutters->getIsDay
                && $shutters->getRoommatesStatus eq 'none'
                && (   $getModeDown eq 'home'
                    || $getModeDown eq 'always' )
                && $getResidentsLastStatus ne 'asleep'
                && $getResidentsLastStatus ne 'awoken'
                && IsAfterShuttersTimeBlocking($shuttersDev)
                && !$shutters->getSelfDefenseState
              )
            {
                $shutters->setLastDrive('residents come home');
                $shutters->setDriveCmd(
                    (
                          $shutters->getSleepPos > 0
                        ? $shutters->getSleepPos
                        : $shutters->getClosedPos
                    )
                );
            }
            elsif (
                (
                       $shutters->getShadingMode eq 'home'
                    || $shutters->getShadingMode eq 'always'
                )
                && $shutters->getIsDay
                && $shutters->getIfInShading
                && $shutters->getRoommatesStatus eq 'none'
                && $shutters->getStatus != $shutters->getShadingPos
                && !$shutters->getShadingManualDriveStatus
                && !(
                    CheckIfShuttersWindowRecOpen($shuttersDev) == 2
                    && $shutters->getShuttersPlace eq 'terrace'
                )
                && !$shutters->getSelfDefenseState
              )
            {
                $shutters->setLastDrive('shading in');
                $shutters->setDriveCmd( $shutters->getShadingPos );
            }
            elsif (
                   $shutters->getShadingMode eq 'absent'
                && $shutters->getIsDay
                && $shutters->getIfInShading
                && $shutters->getStatus == $shutters->getShadingPos
                && $shutters->getRoommatesStatus eq 'none'
                && !$shutters->getShadingManualDriveStatus
                && !(
                    CheckIfShuttersWindowRecOpen($shuttersDev) == 2
                    && $shutters->getShuttersPlace eq 'terrace'
                )
                && !$shutters->getSelfDefenseState
              )
            {
                $shutters->setLastDrive('shading out');
                $shutters->setDriveCmd( $shutters->getLastPos );
            }
            elsif (
                   $ascDev->getSelfDefense eq 'on'
                && $shutters->getSelfDefenseMode ne 'off'
                && !$shutters->getIfInShading
                && (   $getResidentsLastStatus eq 'gone'
                    || $getResidentsLastStatus eq 'absent' )
                && $shutters->getSelfDefenseState
              )
            {
                RemoveInternalTimer( $shutters->getSelfDefenseAbsentTimerhash )
                  if ( $getResidentsLastStatus eq 'absent'
                    && $ascDev->getSelfDefense eq 'on'
                    && $shutters->getSelfDefenseMode ne 'off'
                    && !$shutters->getSelfDefenseAbsent
                    && $shutters->getSelfDefenseAbsentTimerrun );

                if (
                    (
                           $shutters->getStatus == $shutters->getClosedPos
                        || $shutters->getStatus == $shutters->getSleepPos
                    )
                    && $shutters->getIsDay
                  )
                {
                    $shutters->setHardLockOut('on')
                      if (
                           CheckIfShuttersWindowRecOpen($shuttersDev) == 2
                        && $shutters->getShuttersPlace eq 'terrace'
                        && (   $getModeUp eq 'absent'
                            || $getModeUp eq 'off' )
                      );

                    $shutters->setSelfDefenseState(0);
                    $shutters->setLastDrive('selfDefense inactive');
                    $shutters->setDriveCmd(
                        (
                              $shutters->getPrivacyDownStatus == 2
                            ? $shutters->getPrivacyDownPos
                            : $shutters->getOpenPos
                        )
                    );
                }
            }
            elsif (
                (
                       $shutters->getStatus == $shutters->getClosedPos
                    || $shutters->getStatus == $shutters->getSleepPos
                )
                && $shutters->getIsDay
                && $shutters->getRoommatesStatus eq 'none'
                && (   $getModeUp eq 'home'
                    || $getModeUp eq 'always' )
                && IsAfterShuttersTimeBlocking($shuttersDev)
                && !$shutters->getIfInShading
                && !$shutters->getSelfDefenseState
              )
            {
                if (   $getResidentsLastStatus eq 'asleep'
                    || $getResidentsLastStatus eq 'awoken' )
                {
                    $shutters->setLastDrive('residents awoken');
                }
                else { $shutters->setLastDrive('residents home'); }
                $shutters->setDriveCmd( $shutters->getOpenPos );
            }
        }
    }

    return;
}

sub EventProcessingRain {

    #### Ist noch nicht fertig, es fehlt noch das verzögerte Prüfen auf erhalten bleiben des getriggerten Wertes.

    my ( $hash, $device, $events ) = @_;

    my $name    = $device;
    my $reading = $ascDev->getRainSensorReading;

    if ( $events =~ m{$reading:\s(\d+(\.\d+)?|rain|dry)}xms ) {
        my $val;
        my $triggerMax = $ascDev->getRainTriggerMax;
        my $triggerMin = $ascDev->getRainTriggerMin;
        my $closedPos  = $ascDev->getRainSensorShuttersClosedPos;

        if    ( $1 eq 'rain' ) { $val = $triggerMax + 1 }
        elsif ( $1 eq 'dry' )  { $val = $triggerMin }
        else                   { $val = $1 }

        RainProtection( $hash, $val, $triggerMax, $closedPos );
    }

    return;
}

sub RainProtection {
    my ( $hash, $val, $triggerMax, $closedPos ) = @_;

    for my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
        $shutters->setShuttersDev($shuttersDev);

        next
          if ( $shutters->getRainProtection eq 'off' );

        if (   $val > $triggerMax
            && $shutters->getStatus != $closedPos
            && IsAfterShuttersManualBlocking($shuttersDev)
            && $shutters->getRainProtectionStatus eq 'unprotected' )
        {
            $shutters->setLastDrive('rain protected');
            $shutters->setDriveCmd($closedPos);
            $shutters->setRainProtectionStatus('protected');
        }
        elsif (( $val == 0 || $val < $triggerMax )
            && $shutters->getStatus == $closedPos
            && IsAfterShuttersManualBlocking($shuttersDev)
            && $shutters->getRainProtectionStatus eq 'protected' )
        {
            $shutters->setLastDrive('rain un-protected');
            $shutters->setDriveCmd(
                (
                    $shutters->getIsDay ? $shutters->getLastPos
                    : (
                          $shutters->getPrivacyDownStatus == 2
                        ? $shutters->getPrivacyDownPos
                        : $shutters->getClosedPos
                    )
                )
            );
            $shutters->setRainProtectionStatus('unprotected');
        }
    }

    return;
}

sub EventProcessingWind {
    my ( $hash, $shuttersDev, $events ) = @_;

    my $name = $hash->{NAME};
    $shutters->setShuttersDev($shuttersDev);

    my $reading = $ascDev->getWindSensorReading;
    if ( $events =~ m{$reading:\s(\d+(\.\d+)?)}xms ) {
        for my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
            $shutters->setShuttersDev($shuttersDev);

            ASC_Debug( 'EventProcessingWind: '
                  . $shutters->getShuttersDev
                  . ' - WindProtection1: '
                  . $shutters->getWindProtectionStatus
                  . ' WindMax1: '
                  . $shutters->getWindMax
                  . ' WindMin1: '
                  . $shutters->getWindMin
                  . ' Bekommender Wert1: '
                  . $1 );

            next
              if (
                (
                    CheckIfShuttersWindowRecOpen($shuttersDev) != 0
                    && $shutters->getShuttersPlace eq 'terrace'
                )
                || $shutters->getWindProtection eq 'off'
              );

            if (   $1 > $shutters->getWindMax
                && $shutters->getWindProtectionStatus eq 'unprotected' )
            {
                $shutters->setLastDrive('wind protected');
                $shutters->setDriveCmd( $shutters->getWindPos );
                $shutters->setWindProtectionStatus('protected');
            }
            elsif ($1 < $shutters->getWindMin
                && $shutters->getWindProtectionStatus eq 'protected' )
            {
                $shutters->setLastDrive('wind un-protected');
                $shutters->setDriveCmd(
                    (
                        $shutters->getIsDay ? $shutters->getLastPos
                        : (
                              $shutters->getPrivacyDownStatus == 2
                            ? $shutters->getPrivacyDownPos
                            : (
                                  $shutters->getSleepPos > 0
                                ? $shutters->getSleepPos
                                : $shutters->getClosedPos
                            )
                        )
                    )
                );
                $shutters->setWindProtectionStatus('unprotected');
            }

            ASC_Debug( 'EventProcessingWind: '
                  . $shutters->getShuttersDev
                  . ' - WindProtection2: '
                  . $shutters->getWindProtectionStatus
                  . ' WindMax2: '
                  . $shutters->getWindMax
                  . ' WindMin2: '
                  . $shutters->getWindMin
                  . ' Bekommender Wert2: '
                  . $1 );
        }
    }

    return;
}
##########

sub EventProcessingBrightness {
    my ( $hash, $shuttersDev, $events ) = @_;

    my $name = $hash->{NAME};
    $shutters->setShuttersDev($shuttersDev);

    ASC_Debug( 'EventProcessingBrightness: '
          . $shutters->getShuttersDev
          . ' - Event von einem Helligkeitssensor erkannt. Verarbeitung läuft. Sollten keine weitere Meldungen aus der Funktion kommen, so befindet sich die aktuelle Zeit nicht innerhalb der Verarbeitungszeit für Sunset oder Sunrise'
    );

    return EventProcessingShadingBrightness( $hash, $shuttersDev, $events )
      unless (
        (
               $shutters->getDown eq 'brightness'
            || $shutters->getUp eq 'brightness'
        )
        || (
            (
                (
                    (
                        int( gettimeofday() / 86400 ) != int(
                            computeAlignTime( '24:00',
                                $shutters->getTimeUpEarly ) / 86400
                        )
                        && (
                            !IsWe()
                            || ( IsWe()
                                && $ascDev->getSunriseTimeWeHoliday eq 'off' )
                        )
                    )
                    || (
                        int( gettimeofday() / 86400 ) != int(
                            computeAlignTime( '24:00',
                                $shutters->getTimeUpWeHoliday ) / 86400
                        )
                        && IsWe()
                        && $ascDev->getSunriseTimeWeHoliday eq 'on'
                        && $shutters->getTimeUpWeHoliday eq '01:25'
                    )
                )
                && int( gettimeofday() / 86400 ) == int(
                    computeAlignTime( '24:00', $shutters->getTimeUpLate ) /
                      86400
                )
            )
            || (
                int( gettimeofday() / 86400 ) != int(
                    computeAlignTime( '24:00', $shutters->getTimeDownEarly ) /
                      86400
                )
                && int( gettimeofday() / 86400 ) == int(
                    computeAlignTime( '24:00', $shutters->getTimeDownLate ) /
                      86400
                )
            )
        )
      );

    ASC_Debug( 'EventProcessingBrightness: '
          . $shutters->getShuttersDev
          . ' - Die aktuelle Zeit befindet sich innerhalb der Sunset/Sunrise Brightness Verarbeitungszeit. Also zwischen Time Early und Time Late'
    );

    my $reading = $shutters->getBrightnessReading;
    if ( $events =~ m{$reading:\s(\d+(\.\d+)?)}xms ) {
        my $brightnessMinVal;
        if ( $shutters->getBrightnessMinVal > -1 ) {
            $brightnessMinVal = $shutters->getBrightnessMinVal;
        }
        else {
            $brightnessMinVal = $ascDev->getBrightnessMinVal;
        }

        my $brightnessMaxVal;
        if ( $shutters->getBrightnessMaxVal > -1 ) {
            $brightnessMaxVal = $shutters->getBrightnessMaxVal;
        }
        else {
            $brightnessMaxVal = $ascDev->getBrightnessMaxVal;
        }

        my $brightnessPrivacyUpVal   = $shutters->getPrivacyUpBrightnessVal;
        my $brightnessPrivacyDownVal = $shutters->getPrivacyDownBrightnessVal;

        ASC_Debug( 'EventProcessingBrightness: '
              . $shutters->getShuttersDev
              . ' - Es wird geprüft ob Sunset oder Sunrise gefahren werden soll und der aktuelle übergebene Brightness-Wert: '
              . $1
              . ' Größer dem eingestellten Sunrise-Wert: '
              . $brightnessMaxVal
              . ' oder kleiner dem eingestellten Sunset-Wert: '
              . $brightnessMinVal
              . ' ist. Werte für weitere Parameter - getUp ist: '
              . $shutters->getUp
              . ' getDown ist: '
              . $shutters->getDown
              . ' getSunrise ist: '
              . $shutters->getSunrise
              . ' getSunset ist: '
              . $shutters->getSunset );

        if (
            (
                (
                    (
                        int( gettimeofday() / 86400 ) != int(
                            computeAlignTime( '24:00',
                                $shutters->getTimeUpEarly ) / 86400
                        )
                        && (
                            !IsWe()
                            || (
                                IsWe()
                                && $ascDev->getSunriseTimeWeHoliday eq 'off'
                                || (   $ascDev->getSunriseTimeWeHoliday eq 'on'
                                    && $shutters->getTimeUpWeHoliday eq
                                    '01:25' )
                            )
                        )
                    )
                    || (
                        int( gettimeofday() / 86400 ) != int(
                            computeAlignTime( '24:00',
                                $shutters->getTimeUpWeHoliday ) / 86400
                        )
                        && IsWe()
                        && $ascDev->getSunriseTimeWeHoliday eq 'on'
                        && $shutters->getTimeUpWeHoliday ne '01:25'
                    )
                )
                && int( gettimeofday() / 86400 ) == int(
                    computeAlignTime( '24:00', $shutters->getTimeUpLate ) /
                      86400
                )
            )
            && (
                $1 > $brightnessMaxVal
                || (   $1 > $brightnessPrivacyUpVal
                    && $shutters->getPrivacyUpStatus == 1 )
            )
            && $shutters->getUp eq 'brightness'
            && !$shutters->getSunrise
            && $ascDev->getAutoShuttersControlMorning eq 'on'
            && (
                   $ascDev->getSelfDefense eq 'off'
                || $shutters->getSelfDefenseMode eq 'off'
                || (   $ascDev->getSelfDefense eq 'on'
                    && $ascDev->getResidentsStatus ne 'gone' )
            )
          )
        {
            Log3( $name, 4,
"AutoShuttersControl ($shuttersDev) - EventProcessingBrightness: Steuerung für Morgens"
            );

            ASC_Debug( 'EventProcessingBrightness: '
                  . $shutters->getShuttersDev
                  . ' - Verarbeitungszeit für Sunrise wurd erkannt. Prüfe Status der Roommates'
            );

            my $homemode = $shutters->getRoommatesStatus;
            $homemode = $ascDev->getResidentsStatus
              if ( $homemode eq 'none' );

            if (
                $shutters->getModeUp eq $homemode
                || (   $shutters->getModeUp eq 'absent'
                    && $homemode eq 'gone' )
                || $shutters->getModeUp eq 'always'
              )
            {
                my $roommatestatus = $shutters->getRoommatesStatus;

                if (
                       $roommatestatus eq 'home'
                    || $roommatestatus eq 'awoken'
                    || $roommatestatus eq 'absent'
                    || $roommatestatus eq 'gone'
                    || $roommatestatus eq 'none'
                    && (
                        $ascDev->getSelfDefense eq 'off'
                        || ( $ascDev->getSelfDefense eq 'on'
                            && CheckIfShuttersWindowRecOpen($shuttersDev) == 0 )
                        || (   $ascDev->getSelfDefense eq 'on'
                            && CheckIfShuttersWindowRecOpen($shuttersDev) != 0
                            && $ascDev->getResidentsStatus eq 'home' )
                    )
                  )
                {

                    if (   $brightnessPrivacyUpVal > 0
                        && $1 < $brightnessMaxVal
                        && $1 > $brightnessPrivacyUpVal )
                    {
                        $shutters->setPrivacyUpStatus(2);
                        $shutters->setLastDrive('brightness privacy day open');
                        ShuttersCommandSet( $hash, $shuttersDev,
                            $shutters->getPrivacyUpPos )
                          unless (
                            !$shutters->getQueryShuttersPos(
                                $shutters->getPrivacyUpPos
                            )
                          );

                        ASC_Debug( 'EventProcessingBrightness: '
                              . $shutters->getShuttersDev
                              . ' - Verarbeitung für Sunrise Privacy Down. Roommatestatus korrekt zum fahren. Fahrbefehl wird an die Funktion FnShuttersCommandSet gesendet. Grund des fahrens: '
                              . $shutters->getLastDrive );

                        CreateSunRiseSetShuttersTimer( $hash, $shuttersDev );
                    }
                    else {
                        $shutters->setLastDrive(
                            'maximum brightness threshold exceeded');
                        $shutters->setSunrise(1);
                        $shutters->setSunset(0);
                        $shutters->setPrivacyUpStatus(0)
                          if ( $shutters->getPrivacyUpStatus == 2 );
                        ShuttersCommandSet( $hash, $shuttersDev,
                            $shutters->getOpenPos );

                        ASC_Debug( 'EventProcessingBrightness: '
                              . $shutters->getShuttersDev
                              . ' - Verarbeitung für Sunrise. Roommatestatus korrekt zum fahren. Fahrbefehl wird an die Funktion FnShuttersCommandSet gesendet. Grund des fahrens: '
                              . $shutters->getLastDrive );
                    }
                }
                else {
                    EventProcessingShadingBrightness( $hash, $shuttersDev,
                        $events );
                    ASC_Debug( 'EventProcessingBrightness: '
                          . $shutters->getShuttersDev
                          . ' - Verarbeitung für Sunrise. Roommatestatus nicht zum hochfahren oder Fenster sind offen. Fahrbebehl bleibt aus!!! Es wird an die Event verarbeitende Beschattungsfunktion weiter gereicht'
                    );
                }
            }
        }
        elsif (
            int( gettimeofday() / 86400 ) != int(
                computeAlignTime( '24:00', $shutters->getTimeDownEarly ) / 86400
            )
            && int( gettimeofday() / 86400 ) == int(
                computeAlignTime( '24:00', $shutters->getTimeDownLate ) / 86400
            )
            && (
                $1 < $brightnessMinVal
                || (   $1 < $brightnessPrivacyDownVal
                    && $shutters->getPrivacyDownStatus == 1 )
            )
            && $shutters->getDown eq 'brightness'
            && !$shutters->getSunset
            && IsAfterShuttersManualBlocking($shuttersDev)
            && $ascDev->getAutoShuttersControlEvening eq 'on'
          )
        {
            Log3( $name, 4,
"AutoShuttersControl ($shuttersDev) - EventProcessingBrightness: Steuerung für Abends"
            );

            ASC_Debug( 'EventProcessingBrightness: '
                  . $shutters->getShuttersDev
                  . ' - Verarbeitungszeit für Sunset wurd erkannt. Prüfe Status der Roommates'
            );

            my $homemode = $shutters->getRoommatesStatus;
            $homemode = $ascDev->getResidentsStatus
              if ( $homemode eq 'none' );

            if (
                $shutters->getModeDown eq $homemode
                || (   $shutters->getModeDown eq 'absent'
                    && $homemode eq 'gone' )
                || $shutters->getModeDown eq 'always'
              )
            {
                my $posValue;
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
                            !$shutters->getQueryShuttersPos(
                                $shutters->getPrivacyDownPos
                            )
                        ) ? $shutters->getPrivacyDownPos : $shutters->getStatus
                    );
                    $shutters->setPrivacyDownStatus(2);

                    ASC_Debug( 'EventProcessingBrightness: '
                          . $shutters->getShuttersDev
                          . ' - Verarbeitung für Sunset Privacy Down. Roommatestatus korrekt zum fahren. Fahrbefehl wird an die Funktion FnShuttersCommandSet gesendet. Grund des fahrens: '
                          . $shutters->getLastDrive );
                }
                elsif (CheckIfShuttersWindowRecOpen($shuttersDev) == 2
                    && $shutters->getSubTyp eq 'threestate'
                    && $ascDev->getAutoShuttersControlComfort eq 'on' )
                {
                    $posValue  = $shutters->getComfortOpenPos;
                    $lastDrive = 'minimum brightness threshold fell below';
                    $shutters->setPrivacyDownStatus(0)
                      if ( $shutters->getPrivacyDownStatus == 2 );
                }
                elsif ( CheckIfShuttersWindowRecOpen($shuttersDev) == 0
                    || $shutters->getVentilateOpen eq 'off' )
                {
                    $posValue = (
                          $shutters->getSleepPos > 0
                        ? $shutters->getSleepPos
                        : $shutters->getClosedPos
                    );
                    $lastDrive = 'minimum brightness threshold fell below';
                    $shutters->setPrivacyDownStatus(0)
                      if ( $shutters->getPrivacyDownStatus == 2 );
                }
                else {
                    $posValue  = $shutters->getVentilatePos;
                    $lastDrive = 'minimum brightness threshold fell below';
                    $shutters->setPrivacyDownStatus(0)
                      if ( $shutters->getPrivacyDownStatus == 2 );
                }

                $shutters->setLastDrive($lastDrive);

                if (
                    $shutters->getPrivacyDownStatus != 2
                    && (   $posValue != $shutters->getStatus
                        || $shutters->getSelfDefenseState )
                  )
                {
                    $shutters->setSunrise(0);
                    $shutters->setSunset(1);
                }

                ShuttersCommandSet( $hash, $shuttersDev, $posValue );

                ASC_Debug( 'EventProcessingBrightness: '
                      . $shutters->getShuttersDev
                      . ' - Verarbeitung für Sunset. Roommatestatus korrekt zum fahren. Fahrbefehl wird an die Funktion FnShuttersCommandSet gesendet. Zielposition: '
                      . $posValue
                      . ' Grund des fahrens: '
                      . $shutters->getLastDrive );
            }
            else {
                EventProcessingShadingBrightness( $hash, $shuttersDev, $events )
                  unless ( $shutters->getPrivacyDownStatus == 2 );

                ASC_Debug( 'EventProcessingBrightness: '
                      . $shutters->getShuttersDev
                      . ' - Verarbeitung für Sunset. Roommatestatus nicht zum runter fahren. Fahrbebehl bleibt aus!!! Es wird an die Event verarbeitende Beschattungsfunktion weiter gereicht'
                );
            }
        }
        else {
            EventProcessingShadingBrightness( $hash, $shuttersDev, $events )
              unless ( $shutters->getPrivacyDownStatus == 2 );

            ASC_Debug( 'EventProcessingBrightness: '
                  . $shutters->getShuttersDev
                  . ' - Brightness Event kam nicht innerhalb der Verarbeitungszeit für Sunset oder Sunris oder aber für beide wurden die entsprechendne Verarbeitungsschwellen nicht erreicht.'
            );
        }
    }
    else {
        ASC_Debug( 'EventProcessingBrightness: '
              . $shutters->getShuttersDev
              . ' - Leider konnte kein Korrekter Brightnesswert aus dem Event erkannt werden. Entweder passt das Reading oder der tatsächliche nummerishce Wert des Events nicht'
        );
    }

    return;
}

sub EventProcessingShadingBrightness {
    my ( $hash, $shuttersDev, $events ) = @_;

    my $name = $hash->{NAME};
    $shutters->setShuttersDev($shuttersDev);
    my $reading = $shutters->getBrightnessReading;
    my $outTemp =
      (   $shutters->getOutTemp != -100
        ? $shutters->getOutTemp
        : $ascDev->getOutTemp );

    Log3( $name, 4,
        "AutoShuttersControl ($shuttersDev) - EventProcessingShadingBrightness"
    );

    ASC_Debug( 'EventProcessingShadingBrightness: '
          . $shutters->getShuttersDev
          . ' - Es wird nun geprüft ob der übergebene Event ein nummerischer Wert vom Brightnessreading ist.'
    );

    if ( $events =~ m{$reading:\s(\d+(\.\d+)?)}xms ) {
        Log3(
            $name, 4,
"AutoShuttersControl ($shuttersDev) - EventProcessingShadingBrightness
            Brightness: " . $1
        );

        ## Brightness Wert in ein Array schieben zur Berechnung eines Average Wertes
        $shutters->setPushBrightnessInArray($1);

        ASC_Debug( 'EventProcessingShadingBrightness: '
              . $shutters->getShuttersDev
              . ' - Nummerischer Brightness-Wert wurde erkannt. Der Brightness Average Wert ist: '
              . $shutters->getBrightnessAverage
              . ' RainProtection: '
              . $shutters->getRainProtectionStatus
              . ' WindProtection: '
              . $shutters->getWindProtectionStatus );

        if (   $ascDev->getAutoShuttersControlShading eq 'on'
            && $shutters->getRainProtectionStatus eq 'unprotected'
            && $shutters->getWindProtectionStatus eq 'unprotected' )
        {
            ShadingProcessing(
                $hash,
                $shuttersDev,
                $ascDev->getAzimuth,
                $ascDev->getElevation,
                $outTemp,
                $shutters->getShadingAzimuthLeft,
                $shutters->getShadingAzimuthRight
            );

            ASC_Debug( 'EventProcessingShadingBrightness: '
                  . $shutters->getShuttersDev
                  . ' - Alle Bedingungen zur weiteren Beschattungsverarbeitung sind erfüllt. Es wird nun die eigentliche Beschattungsfunktion aufgerufen'
            );
        }
    }

    return;
}

sub EventProcessingTwilightDevice {
    my ( $hash, $device, $events ) = @_;

    #     Twilight
    #     azimuth = azimuth = Sonnenwinkel
    #     elevation = elevation = Sonnenhöhe
    #
    #     Astro
    #     SunAz = azimuth = Sonnenwinkel
    #     SunAlt = elevation = Sonnenhöhe

    ASC_Debug( 'EventProcessingTwilightDevice: '
          . $shutters->getShuttersDev
          . ' - Event vom Astro oder Twilight Device wurde erkannt. Event wird verarbeitet'
    );

    if ( $events =~ m{(azimuth|elevation|SunAz|SunAlt):\s(\d+.\d+)}xms ) {
        my $name = $device;
        my ( $azimuth, $elevation );
        my $outTemp = $ascDev->getOutTemp;

        $azimuth   = $2 if ( $1 eq 'azimuth'   || $1 eq 'SunAz' );
        $elevation = $2 if ( $1 eq 'elevation' || $1 eq 'SunAlt' );

        $azimuth = $ascDev->getAzimuth
          if ( !defined($azimuth) && !$azimuth );
        $elevation = $ascDev->getElevation
          if ( !defined($elevation) && !$elevation );

        ASC_Debug( 'EventProcessingTwilightDevice: '
              . $name
              . ' - Passendes Event wurde erkannt. Verarbeitung über alle Rollos beginnt'
        );

        for my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
            $shutters->setShuttersDev($shuttersDev);

            my $homemode = $shutters->getRoommatesStatus;
            $homemode = $ascDev->getResidentsStatus if ( $homemode eq 'none' );
            $outTemp = $shutters->getOutTemp
              if ( $shutters->getOutTemp != -100 );

            ASC_Debug( 'EventProcessingTwilightDevice: '
                  . $shutters->getShuttersDev
                  . ' RainProtection: '
                  . $shutters->getRainProtectionStatus
                  . ' WindProtection: '
                  . $shutters->getWindProtectionStatus );

            if (   $ascDev->getAutoShuttersControlShading eq 'on'
                && $shutters->getRainProtectionStatus eq 'unprotected'
                && $shutters->getWindProtectionStatus eq 'unprotected' )
            {
                ShadingProcessing(
                    $hash,
                    $shuttersDev,
                    $azimuth,
                    $elevation,
                    $outTemp,
                    $shutters->getShadingAzimuthLeft,
                    $shutters->getShadingAzimuthRight
                );

                ASC_Debug( 'EventProcessingTwilightDevice: '
                      . $shutters->getShuttersDev
                      . ' - Alle Bedingungen zur weiteren Beschattungsverarbeitung sind erfüllt. Es wird nun die Beschattungsfunktion ausgeführt'
                );
            }
        }
    }

    return;
}

sub ShadingProcessing {
### angleMinus ist $shutters->getShadingAzimuthLeft
### anglePlus ist $shutters->getShadingAzimuthRight
### winPos ist die Fensterposition $shutters->getDirection
    my ( $hash, $shuttersDev, $azimuth, $elevation, $outTemp,
        $azimuthLeft, $azimuthRight )
      = @_;

    my $name = $hash->{NAME};
    $shutters->setShuttersDev($shuttersDev);
    my $brightness = $shutters->getBrightnessAverage;

    ASC_Debug(
            'ShadingProcessing: '
          . $shutters->getShuttersDev
          . ' - Übergebende Werte - Azimuth:'
          . $azimuth
          . ', Elevation: '
          . $elevation
          . ', Brightness: '
          . $brightness
          . ', OutTemp: '
          . $outTemp
          . ', Azimut Beschattung: '
          . $azimuthLeft
          . ', Azimut Endschattung: '
          . $azimuthRight
          . ', Ist es nach der Zeitblockadezeit: '
          . ( IsAfterShuttersTimeBlocking($shuttersDev) ? 'JA' : 'NEIN' )
          . ', Das Rollo ist in der Beschattung und wurde manuell gefahren: '
          . ( $shutters->getShadingManualDriveStatus ? 'JA' : 'NEIN' )
          . ', Ist es nach der Hälfte der Beschattungswartezeit: '
          . (
            ( int( gettimeofday() ) - $shutters->getShadingStatusTimestamp ) <
              ( $shutters->getShadingWaitingPeriod / 2 ) ? 'NEIN' : 'JA'
          )
    );

    Log3( $name, 4,
            "AutoShuttersControl ($name) - Shading Processing, Rollladen: "
          . $shuttersDev
          . " Azimuth: "
          . $azimuth
          . " Elevation: "
          . $elevation
          . " Brightness: "
          . $brightness
          . " OutTemp: "
          . $outTemp );

    return
      if ( $azimuth == -1
        || $elevation == -1
        || $brightness == -1
        || $outTemp == -100
        || ( int( gettimeofday() ) - $shutters->getShadingStatusTimestamp ) <
        ( $shutters->getShadingWaitingPeriod / 2 )
        || $shutters->getShadingMode eq 'off' );

    Log3( $name, 4,
            "AutoShuttersControl ($name) - Shading Processing, Rollladen: "
          . $shuttersDev
          . " Nach dem return" );

    my $getShadingPos    = $shutters->getShadingPos;
    my $getStatus        = $shutters->getStatus;
    my $oldShadingStatus = $shutters->getShadingStatus;
    my $homemode         = $shutters->getHomemode;

    ASC_Debug( 'ShadingProcessing: '
          . $shutters->getShuttersDev
          . ' - Alle Werte für die weitere Verarbeitung sind korrekt vorhanden und es wird nun mit der Beschattungsverarbeitung begonnen'
    );

    if (
        (
               $outTemp < $shutters->getShadingMinOutsideTemperature - 4
            || $azimuth < $azimuthLeft
            || $azimuth > $azimuthRight
            || !$shutters->getIsDay
        )
        && $shutters->getShadingStatus ne 'out'
      )
    {
        $shutters->setShadingLastStatus('in');
        $shutters->setShadingStatus('out');

        ASC_Debug( 'ShadingProcessing: '
              . $shutters->getShuttersDev
              . ' - Es ist Nacht oder die Aussentemperatur unterhalb der Shading Temperatur. Die Beschattung wird Zwangsbeendet'
        );

        Log3( $name, 4,
"AutoShuttersControl ($name) - Shading Processing - Der Sonnenstand ist ausserhalb der Winkelangaben oder die Aussentemperatur unterhalb der Shading Temperatur "
        );
    }
    elsif ($azimuth < $azimuthLeft
        || $azimuth > $azimuthRight
        || $elevation < $shutters->getShadingMinElevation
        || $elevation > $shutters->getShadingMaxElevation
        || $brightness < $shutters->getShadingStateChangeCloudy
        || $outTemp < $shutters->getShadingMinOutsideTemperature - 1 )
    {
        $shutters->setShadingStatus('out reserved')
          if ( $shutters->getShadingStatus eq 'in'
            || $shutters->getShadingStatus eq 'in reserved' );

        if (
            (
                $shutters->getShadingStatus eq 'out reserved'
                and
                ( int( gettimeofday() ) - $shutters->getShadingStatusTimestamp )
            ) > $shutters->getShadingWaitingPeriod
          )
        {
            $shutters->setShadingStatus('out');
            $shutters->setShadingLastStatus('in')
              if ( $shutters->getShadingLastStatus eq 'out' );
        }

        Log3( $name, 4,
                "AutoShuttersControl ($name) - Shading Processing, Rollladen: "
              . $shuttersDev
              . " In der Out Abfrage, Shadingwert: "
              . $shutters->getShadingStatus
              . ", Zeitstempel: "
              . $shutters->getShadingStatusTimestamp );

        ASC_Debug( 'ShadingProcessing: '
              . $shutters->getShuttersDev
              . ' - Einer der Beschattungsbedingungen wird nicht mehr erfüllt und somit wird der Beschattungsstatus um eine Stufe reduziert. Alter Status: '
              . $oldShadingStatus
              . ' Neuer Status: '
              . $shutters->getShadingStatus );
    }
    elsif ($azimuth > $azimuthLeft
        && $azimuth < $azimuthRight
        && $elevation > $shutters->getShadingMinElevation
        && $elevation < $shutters->getShadingMaxElevation
        && $brightness > $shutters->getShadingStateChangeSunny
        && $outTemp > $shutters->getShadingMinOutsideTemperature )
    {
        $shutters->setShadingStatus('in reserved')
          if ( $shutters->getShadingStatus eq 'out'
            || $shutters->getShadingStatus eq 'out reserved' );

        if ( $shutters->getShadingStatus eq 'in reserved'
            and
            ( int( gettimeofday() ) - $shutters->getShadingStatusTimestamp ) >
            ( $shutters->getShadingWaitingPeriod / 2 ) )
        {
            $shutters->setShadingStatus('in');
            $shutters->setShadingLastStatus('out')
              if ( $shutters->getShadingLastStatus eq 'in' );
        }

        Log3( $name, 4,
                "AutoShuttersControl ($name) - Shading Processing, Rollladen: "
              . $shuttersDev
              . " In der In Abfrage, Shadingwert: "
              . $shutters->getShadingStatus
              . ", Zeitstempel: "
              . $shutters->getShadingStatusTimestamp );

        ASC_Debug( 'ShadingProcessing: '
              . $shutters->getShuttersDev
              . ' - Alle Beschattungsbedingungen wurden erfüllt und somit wird der Beschattungsstatus um eine Stufe angehoben. Alter Status: '
              . $oldShadingStatus
              . ' Neuer Status: '
              . $shutters->getShadingStatus );
    }

    ShadingProcessingDriveCommand( $hash, $shuttersDev )
      if (
           IsAfterShuttersTimeBlocking($shuttersDev)
        && !$shutters->getShadingManualDriveStatus
        && $shutters->getRoommatesStatus ne 'gotosleep'
        && $shutters->getRoommatesStatus ne 'asleep'
        && (
            (
                   $shutters->getShadingStatus eq 'out'
                && $shutters->getShadingLastStatus eq 'in'
            )
            || (   $shutters->getShadingStatus eq 'in'
                && $shutters->getShadingLastStatus eq 'out' )
        )
        && (   $shutters->getShadingMode eq 'always'
            || $shutters->getShadingMode eq $homemode )
        && (
               $shutters->getModeUp eq 'always'
            || $shutters->getModeUp eq $homemode
            || (   $shutters->getModeUp eq 'home'
                && $homemode ne 'asleep' )
            || $shutters->getModeUp eq 'off'
        )
        && (
            (
                (
                    int( gettimeofday() ) -
                    $shutters->getShadingStatusTimestamp
                ) < 2
                && $shutters->getStatus != $shutters->getClosedPos
            )
            || (  !$shutters->getQueryShuttersPos( $shutters->getShadingPos )
                && $shutters->getIfInShading )
            || (  !$shutters->getIfInShading
                && $shutters->getStatus == $shutters->getShadingPos )
        )
      );

    return;
}

sub ShadingProcessingDriveCommand {
    my $hash        = shift;
    my $shuttersDev = shift;

    my $name = $hash->{NAME};
    $shutters->setShuttersDev($shuttersDev);

    my $getShadingPos = $shutters->getShadingPos;
    my $getStatus     = $shutters->getStatus;

    my $homemode = $shutters->getRoommatesStatus;
    $homemode = $ascDev->getResidentsStatus if ( $homemode eq 'none' );

    if (   $shutters->getShadingMode eq 'always'
        || $shutters->getShadingMode eq $homemode )
    {
        $shutters->setShadingStatus( $shutters->getShadingStatus );

        if (
               $shutters->getShadingStatus eq 'in'
            && $getShadingPos != $getStatus
            && ( CheckIfShuttersWindowRecOpen($shuttersDev) != 2
                || $shutters->getShuttersPlace ne 'terrace' )
          )
        {
            $shutters->setLastDrive('shading in');
            ShuttersCommandSet( $hash, $shuttersDev, $getShadingPos );

            ASC_Debug( 'ShadingProcessingDriveCommand: '
                  . $shutters->getShuttersDev
                  . ' - Der aktuelle Beschattungsstatus ist: '
                  . $shutters->getShadingStatus
                  . ' und somit wird nun in die Position: '
                  . $getShadingPos
                  . ' zum Beschatten gefahren' );
        }
        elsif ($shutters->getShadingStatus eq 'out'
            && $getShadingPos == $getStatus )
        {
            $shutters->setLastDrive('shading out');

            ShuttersCommandSet(
                $hash,
                $shuttersDev,
                (
                      $getShadingPos == $shutters->getLastPos
                    ? $shutters->getOpenPos
                    : (
                        $shutters->getQueryShuttersPos( $shutters->getLastPos )
                        ? (
                              $shutters->getLastPos == $shutters->getSleepPos
                            ? $shutters->getOpenPos
                            : $shutters->getLastPos
                          )
                        : $shutters->getOpenPos
                    )
                )
            );

            ASC_Debug( 'ShadingProcessingDriveCommand: '
                  . $shutters->getShuttersDev
                  . ' - Der aktuelle Beschattungsstatus ist: '
                  . $shutters->getShadingStatus
                  . ' und somit wird nun in die Position: '
                  . $getShadingPos
                  . ' zum beenden der Beschattung gefahren' );
        }

        Log3( $name, 4,
"AutoShuttersControl ($name) - Shading Processing - In der Routine zum fahren der Rollläden, Shading Wert: "
              . $shutters->getShadingStatus );

        ASC_Debug(
                'ShadingProcessingDriveCommand: '
              . $shutters->getShuttersDev
              . ' - Der aktuelle Beschattungsstatus ist: '
              . $shutters->getShadingStatus
              . ', Beschattungsstatus Zeitstempel: '
              . strftime(
                "%Y.%m.%e %T", localtime( $shutters->getShadingStatusTimestamp )
              )
        );
    }

    return;
}

sub EventProcessingPartyMode {
    my $hash = shift;

    my $name = $hash->{NAME};

    for my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
        $shutters->setShuttersDev($shuttersDev);
        next
          if ( $shutters->getPartyMode eq 'off' );

        if (  !$shutters->getIsDay
            && $shutters->getModeDown ne 'off'
            && IsAfterShuttersManualBlocking($shuttersDev) )
        {
            if ( CheckIfShuttersWindowRecOpen($shuttersDev) == 2
                && $shutters->getSubTyp eq 'threestate' )
            {
                Log3( $name, 4,
"AutoShuttersControl ($name) - EventProcessingPartyMode Fenster offen"
                );
                $shutters->setDelayCmd( $shutters->getClosedPos );
                Log3( $name, 4,
"AutoShuttersControl ($name) - EventProcessingPartyMode - Spring in ShuttersCommandDelaySet"
                );
            }
            else {
                Log3( $name, 4,
"AutoShuttersControl ($name) - EventProcessingPartyMode Fenster nicht offen"
                );
                $shutters->setLastDrive('drive after party mode');
                ShuttersCommandSet(
                    $hash,
                    $shuttersDev,
                    (
                        CheckIfShuttersWindowRecOpen($shuttersDev) == 0
                        ? $shutters->getClosedPos
                        : $shutters->getVentilatePos
                    )
                );
            }
        }
        elsif ($shutters->getDelayCmd ne 'none'
            && $shutters->getIsDay
            && IsAfterShuttersManualBlocking($shuttersDev) )
        {
            $shutters->setLastDrive('drive after party mode');
            ShuttersCommandSet( $hash, $shuttersDev, $shutters->getDelayCmd );
        }
    }

    return;
}

sub EventProcessingAdvShuttersClose {
    my $hash = shift;

    my $name = $hash->{NAME};

    for my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
        $shutters->setShuttersDev($shuttersDev);
        next
          if ( !$shutters->getAdv
            && !$shutters->getAdvDelay );

        $shutters->setLastDrive('adv delay close');
        $shutters->setAdvDelay(1);
        ShuttersCommandSet(
            $hash,
            $shuttersDev,
            (
                  $shutters->getDelayCmd ne 'none'
                ? $shutters->getDelayCmd
                : $shutters->getClosedPos
            )
        );
    }

    return;
}

sub EventProcessingShutters {
    my ( $hash, $shuttersDev, $events ) = @_;

    my $name = $hash->{NAME};

    ASC_Debug( 'EventProcessingShutters: '
          . ' Fn wurde durch Notify aufgerufen da ASC_Pos_Reading Event erkannt wurde '
          . ' - RECEIVED EVENT: '
          . Dumper $events);

    if ( $events =~ m{.*:\s(\d+)}xms ) {
        $shutters->setShuttersDev($shuttersDev);
        $ascDev->setPosReading;

        ASC_Debug( 'EventProcessingShutters: '
              . $shutters->getShuttersDev
              . ' - Event vom Rollo erkannt. Es wird nun eine etwaige manuelle Fahrt ausgewertet.'
              . ' Int von gettimeofday: '
              . int( gettimeofday() )
              . ' Last Position Timestamp: '
              . $shutters->getLastPosTimestamp
              . ' Drive Up Max Duration: '
              . $shutters->getDriveUpMaxDuration
              . ' Last Position: '
              . $shutters->getLastPos
              . ' aktuelle Position: '
              . $shutters->getStatus );

        if ( ( int( gettimeofday() ) - $shutters->getLastPosTimestamp ) >
            $shutters->getDriveUpMaxDuration
            && ( int( gettimeofday() ) - $shutters->getLastManPosTimestamp ) >
            $shutters->getDriveUpMaxDuration )
        {
            $shutters->setLastDrive('manual');
            $shutters->setLastDriveReading;
            $ascDev->setStateReading;
            $shutters->setLastManPos($1);

            $shutters->setShadingManualDriveStatus(1)
              if ( $shutters->getIsDay
                && $shutters->getIfInShading );

            ASC_Debug(
                'EventProcessingShutters: eine manualle Fahrt wurde erkannt!');
        }
        else {
            $shutters->setLastDriveReading;
            $ascDev->setStateReading;

            ASC_Debug(
'EventProcessingShutters: eine automatisierte Fahrt durch ASC wurde erkannt! Es werden nun die LastDriveReading und StateReading Werte gesetzt!'
            );
        }
    }

    ASC_Debug( 'EventProcessingShutters: '
          . ' Fn wurde durlaufen und es sollten Debugausgaben gekommen sein. '
          . ' !!!Wenn nicht!!! wurde der Event nicht korrekt als Nummerisch erkannt. '
    );

    return;
}

sub EventProcessingExternalTriggerDevice {
    my ( $hash, $shuttersDev, $events ) = @_;

    my $name = $hash->{NAME};

    $shutters->setShuttersDev($shuttersDev);

    ASC_Debug( 'EventProcessingExternalTriggerDevice: '
          . ' Fn wurde durch Notify '
          . ' - RECEIVED EVENT: '
          . Dumper $events);

    my $reading            = $shutters->getExternalTriggerReading;
    my $triggerValActive   = $shutters->getExternalTriggerValueActive;
    my $triggerValActive2  = $shutters->getExternalTriggerValueActive2;
    my $triggerValInactive = $shutters->getExternalTriggerValueInactive;
    my $triggerPosActive   = $shutters->getExternalTriggerPosActive;
    my $triggerPosActive2  = $shutters->getExternalTriggerPosActive2;
    my $triggerPosInactive = $shutters->getExternalTriggerPosInactive;

    if ( $events =~ m{$reading:\s($triggerValActive|$triggerValActive2)}xms ) {

        #         && !$shutters->getQueryShuttersPos($triggerPosActive)

        ASC_Debug( 'EventProcessingExternalTriggerDevice: '
              . ' In der RegEx Schleife Trigger Val Aktiv'
              . ' - TriggerVal: '
              . $triggerValActive
              . ' - TriggerVal2: '
              . $triggerValActive2 );

        if ( $1 eq $triggerValActive2 ) {
            $shutters->setLastDrive('external trigger2 device active');
            $shutters->setNoDelay(1);
            $shutters->setExternalTriggerState(1);
            ShuttersCommandSet( $hash, $shuttersDev, $triggerPosActive2 );
        }
        else {
            $shutters->setLastDrive('external trigger device active');
            $shutters->setNoDelay(1);
            $shutters->setExternalTriggerState(1);
            ShuttersCommandSet( $hash, $shuttersDev, $triggerPosActive );
        }
    }
    elsif (
        $events =~ m{$reading:\s($triggerValInactive)}xms
        && (   $shutters->getPrivacyDownStatus != 2
            || $shutters->getPrivacyUpStatus != 2 )
        && !$shutters->getIfInShading
      )
    {
        ASC_Debug( 'EventProcessingExternalTriggerDevice: '
              . ' In der RegEx Schleife Trigger Val Inaktiv'
              . ' - TriggerVal: '
              . $triggerValInactive );

        $shutters->setLastDrive('external trigger device inactive');
        $shutters->setNoDelay(1);
        $shutters->setExternalTriggerState(1);
        ShuttersCommandSet(
            $hash,
            $shuttersDev,
            (
                  $shutters->getIsDay
                ? $triggerPosInactive
                : $shutters->getClosedPos
            )
        );
    }

    ASC_Debug(
        'EventProcessingExternalTriggerDevice: ' . ' Funktion durchlaufen' );

    return;
}

# Sub für das Zusammensetzen der Rolläden Steuerbefehle
sub ShuttersCommandSet {
    my ( $hash, $shuttersDev, $posValue ) = @_;

    my $name = $hash->{NAME};
    $shutters->setShuttersDev($shuttersDev);

    if (
        (
               $posValue == $shutters->getShadingPos
            && CheckIfShuttersWindowRecOpen($shuttersDev) == 2
            && $shutters->getShuttersPlace eq 'terrace'
            && (   $shutters->getLockOut eq 'soft'
                || $shutters->getLockOut eq 'hard' )
            && !$shutters->getQueryShuttersPos($posValue)
        )
        || (
            $posValue != $shutters->getShadingPos
            && (
                (
                       $shutters->getPartyMode eq 'on'
                    && $ascDev->getPartyMode eq 'on'
                )
                || (
                       CheckIfShuttersWindowRecOpen($shuttersDev) == 2
                    && $shutters->getSubTyp eq 'threestate'
                    && (   $ascDev->getAutoShuttersControlComfort eq 'off'
                        || $shutters->getComfortOpenPos != $posValue )
                    && $shutters->getVentilateOpen eq 'on'
                    && $shutters->getShuttersPlace eq 'window'
                    && $shutters->getLockOut ne 'off'
                )
                || (   CheckIfShuttersWindowRecOpen($shuttersDev) == 2
                    && $shutters->getSubTyp eq 'threestate'
                    && $ascDev->getAutoShuttersControlComfort eq 'on'
                    && $shutters->getVentilateOpen eq 'off'
                    && $shutters->getShuttersPlace eq 'window'
                    && $shutters->getLockOut ne 'off' )
                || (
                    CheckIfShuttersWindowRecOpen($shuttersDev) == 2
                    && (   $shutters->getLockOut eq 'soft'
                        || $shutters->getLockOut eq 'hard' )
                    && !$shutters->getQueryShuttersPos($posValue)
                )
                || (   CheckIfShuttersWindowRecOpen($shuttersDev) == 2
                    && $shutters->getShuttersPlace eq 'terrace'
                    && !$shutters->getQueryShuttersPos($posValue) )
                || (   $shutters->getRainProtectionStatus eq 'protected'
                    && $shutters->getWindProtectionStatus eq 'protected' )
            )
        )
      )
    {
        $shutters->setDelayCmd($posValue);
        $ascDev->setDelayCmdReading;
        $shutters->setNoDelay(0);
        Log3( $name, 4,
            "AutoShuttersControl ($name) - ShuttersCommandSet in Delay" );

        ASC_Debug( 'FnShuttersCommandSet: '
              . $shutters->getShuttersDev
              . ' - Die Fahrt wird zurückgestellt. Grund kann ein geöffnetes Fenster sein oder ein aktivierter Party Modus'
        );
    }
    else {
        $shutters->setDriveCmd($posValue);
        $ascDev->setLastPosReading;
        Log3( $name, 4,
"AutoShuttersControl ($name) - ShuttersCommandSet setDriveCmd wird aufgerufen"
        );

        ASC_Debug( 'FnShuttersCommandSet: '
              . $shutters->getShuttersDev
              . ' - Das Rollo wird gefahren. Kein Partymodus aktiv und das zugordnete Fenster ist entweder nicht offen oder keine Terassentür'
        );
    }

    return;
}

## Sub welche die InternalTimer nach entsprechenden Sunset oder Sunrise zusammen stellt
sub CreateSunRiseSetShuttersTimer {
    my $hash        = shift;
    my $shuttersDev = shift;

    my $name            = $hash->{NAME};
    my $shuttersDevHash = $defs{$shuttersDev};
    my %funcHash;
    $shutters->setShuttersDev($shuttersDev);

    return if ( IsDisabled($name) );

    my $shuttersSunriseUnixtime = ShuttersSunrise( $shuttersDev, 'unix' ) + 1;
    my $shuttersSunsetUnixtime = ShuttersSunset( $shuttersDev, 'unix' ) + 1;

    $shutters->setSunriseUnixTime($shuttersSunriseUnixtime);
    $shutters->setSunsetUnixTime($shuttersSunsetUnixtime);

    ## In jedem Rolladen werden die errechneten Zeiten hinterlegt,es sei denn das autoShuttersControlEvening/Morning auf off steht
    readingsBeginUpdate($shuttersDevHash);
    readingsBulkUpdate(
        $shuttersDevHash,
        'ASC_Time_DriveDown',
        (
            $ascDev->getAutoShuttersControlEvening eq 'on'
            ? (
                $shutters->getDown eq 'roommate' ? 'roommate only' : strftime(
                    "%e.%m.%Y - %H:%M",
                    localtime($shuttersSunsetUnixtime)
                )
              )
            : 'AutoShuttersControl off'
        )
    );
    readingsBulkUpdate(
        $shuttersDevHash,
        'ASC_Time_DriveUp',
        (
            $ascDev->getAutoShuttersControlMorning eq 'on'
            ? (
                $shutters->getUp eq 'roommate' ? 'roommate only' : strftime(
                    "%e.%m.%Y - %H:%M",
                    localtime($shuttersSunriseUnixtime)
                )
              )
            : 'AutoShuttersControl off'
        )
    );
    readingsEndUpdate( $shuttersDevHash, 0 );

    readingsBeginUpdate($hash);
    readingsBulkUpdateIfChanged(
        $hash,
        $shuttersDev . '_nextAstroTimeEvent',
        (
            $shuttersSunriseUnixtime < $shuttersSunsetUnixtime
            ? strftime( "%e.%m.%Y - %H:%M",
                localtime($shuttersSunriseUnixtime) )
            : strftime(
                "%e.%m.%Y - %H:%M", localtime($shuttersSunsetUnixtime)
            )
        )
    );
    readingsEndUpdate( $hash, 1 );

    RemoveInternalTimer( $shutters->getInTimerFuncHash )
      if ( defined( $shutters->getInTimerFuncHash ) );

    ## Setzt den Privacy Modus für die Sichtschutzfahrt auf den Status 0
    ##  1 bedeutet das PrivacyDown Timer aktiviert wurde, 2 beudet das er im privacyDown ist
    ##  also das Rollo in privacy Position steht und VOR der endgültigen Nacht oder Tagfahrt
    $shutters->setPrivacyUpStatus(0)
      if ( !defined( $shutters->getPrivacyUpStatus ) );
    $shutters->setPrivacyDownStatus(0)
      if ( !defined( $shutters->getPrivacyDownStatus ) );

    ## Abfrage für die Sichtschutzfahrt am Morgen vor dem eigentlichen kompletten öffnen
    if ( $shutters->getPrivacyUpTime > 0 ) {
        $shuttersSunriseUnixtime =
          PrivacyUpTime( $shuttersDevHash, $shuttersSunriseUnixtime );
    }
    else {
        CommandDeleteReading( undef, $shuttersDev . ' ASC_Time_PrivacyDriveUp' )
          if ( ReadingsVal( $shuttersDev, 'ASC_Time_PrivacyDriveUp', 'none' ) ne
            'none' );
    }

    ## Abfrage für die Sichtschutzfahrt am Abend vor dem eigentlichen kompletten schließen
    if ( $shutters->getPrivacyDownTime > 0 ) {
        $shuttersSunsetUnixtime =
          PrivacyDownTime( $shuttersDevHash, $shuttersSunsetUnixtime );
    }
    else {
        CommandDeleteReading( undef,
            $shuttersDev . ' ASC_Time_PrivacyDriveDown' )
          if (
            ReadingsVal( $shuttersDev, 'ASC_Time_PrivacyDriveDown', 'none' ) ne
            'none' );
    }

    ## kleine Hilfe für InternalTimer damit ich alle benötigten Variablen an die Funktion übergeben kann welche von Internal Timer aufgerufen wird.
    %funcHash = (
        hash           => $hash,
        shuttersdevice => $shuttersDev,
        sunsettime     => $shuttersSunsetUnixtime,
        sunrisetime    => $shuttersSunriseUnixtime
    );
    ## Ich brauche beim löschen des InternalTimer den Hash welchen ich mitgegeben habe,dieser muss gesichert werden
    $shutters->setInTimerFuncHash( \%funcHash );

    InternalTimer( $shuttersSunsetUnixtime, \&SunSetShuttersAfterTimerFn,
        \%funcHash );
    InternalTimer( $shuttersSunriseUnixtime, \&SunRiseShuttersAfterTimerFn,
        \%funcHash );

    $ascDev->setStateReading('created new drive timer');

    return;
}

## Funktion zum neu setzen der Timer und der Readings für Sunset/Rise
sub RenewSunRiseSetShuttersTimer {
    my $hash = shift;

    for ( @{ $hash->{helper}{shuttersList} } ) {
        my $name  = $_;
        my $dhash = $defs{$name};

        $shutters->setShuttersDev($name);

        RemoveInternalTimer( $shutters->getInTimerFuncHash );
        $shutters->setInTimerFuncHash(undef);
        CreateSunRiseSetShuttersTimer( $hash, $name );

        #### Temporär angelegt damit die neue Attributs Parameter Syntax verteilt werden kann
        #### Gleichlautende Attribute wo lediglich die Parameter geändert werden sollen müssen bereits in der Funktion ShuttersDeviceScan gelöscht werden
        #### vorher empfiehlt es sich die dort vergebenen Parameter aus zu lesen um sie dann hier wieder neu zu setzen. Dazu wird das shutters Objekt um einen Eintrag
        #### 'AttrUpdateChanges' erweitert
        if (
            ( int( gettimeofday() ) - $::fhem_started ) < 60
            and
            ReadingsVal( $name, '.ASC_AttrUpdateChanges_' . $hash->{VERSION},
                0 ) == 0
          )
        {
#             $attr{$name}{'ASC_Up'} = $shutters->getAttrUpdateChanges('ASC_Up')
#               if ( $shutters->getAttrUpdateChanges('ASC_Up') ne 'none' );
#             $attr{$name}{'ASC_Down'} =
#               $shutters->getAttrUpdateChanges('ASC_Down')
#               if ( $shutters->getAttrUpdateChanges('ASC_Down') ne 'none' );
#             $attr{$name}{'ASC_Self_Defense_Mode'} =
#               $shutters->getAttrUpdateChanges('ASC_Self_Defense_Mode')
#               if ( $shutters->getAttrUpdateChanges('ASC_Self_Defense_Mode') ne
#                 'none' );
#             $attr{$name}{'ASC_Self_Defense_Mode'} = 'off'
#               if (
#                 $shutters->getAttrUpdateChanges('ASC_Self_Defense_Exclude') eq
#                 'on' );

            CommandDeleteReading( undef, $name . ' .ASC_AttrUpdateChanges_.*' )
              if (
                ReadingsVal(
                    $name, '.ASC_AttrUpdateChanges_' . $hash->{VERSION},
                    'none'
                ) eq 'none'
              );
            readingsSingleUpdate( $dhash,
                '.ASC_AttrUpdateChanges_' . $hash->{VERSION},
                1, 0 );
        }

#         $attr{$name}{ASC_Drive_Delay} =
#           AttrVal( $name, 'ASC_Drive_Offset', 'none' )
#           if ( AttrVal( $name, 'ASC_Drive_Offset', 'none' ) ne 'none' );
#         delFromDevAttrList( $name, 'ASC_Drive_Offset' );
#
#         $attr{$name}{ASC_Drive_DelayStart} =
#           AttrVal( $name, 'ASC_Drive_OffsetStart', 'none' )
#           if ( AttrVal( $name, 'ASC_Drive_OffsetStart', 'none' ) ne 'none' );
#         delFromDevAttrList( $name, 'ASC_Drive_OffsetStart' );
#
#         $attr{$name}{ASC_Shading_StateChange_SunnyCloudy} =
#             AttrVal( $name, 'ASC_Shading_StateChange_Sunny', 'none' ) . ':'
#           . AttrVal( $name, 'ASC_Shading_StateChange_Cloudy', 'none' )
#           if (
#             AttrVal( $name, 'ASC_Shading_StateChange_Sunny', 'none' ) ne 'none'
#             && AttrVal( $name, 'ASC_Shading_StateChange_Cloudy', 'none' ) ne
#             'none' );
#         delFromDevAttrList( $name, 'ASC_Shading_StateChange_Sunny' );
#         delFromDevAttrList( $name, 'ASC_Shading_StateChange_Cloudy' );
#
#         $attr{$name}{ASC_Shading_InOutAzimuth} =
#           ( AttrVal( $name, 'ASC_Shading_Direction', 180 ) -
#               AttrVal( $name, 'ASC_Shading_Angle_Left', 85 ) )
#           . ':'
#           . ( AttrVal( $name, 'ASC_Shading_Direction', 180 ) +
#               AttrVal( $name, 'ASC_Shading_Angle_Right', 85 ) )
#           if ( AttrVal( $name, 'ASC_Shading_Direction', 'none' ) ne 'none'
#             || AttrVal( $name, 'ASC_Shading_Angle_Left',  'none' ) ne 'none'
#             || AttrVal( $name, 'ASC_Shading_Angle_Right', 'none' ) ne 'none' );
#         delFromDevAttrList( $name, 'ASC_Shading_Direction' );
#         delFromDevAttrList( $name, 'ASC_Shading_Angle_Left' );
#         delFromDevAttrList( $name, 'ASC_Shading_Angle_Right' );
#
#         $attr{$name}{ASC_PrivacyDownValue_beforeNightClose} =
#           AttrVal( $name, 'ASC_PrivacyDownTime_beforNightClose', 'none' )
#           if (
#             AttrVal( $name, 'ASC_PrivacyDownTime_beforNightClose', 'none' ) ne
#             'none' );
#         delFromDevAttrList( $name, 'ASC_PrivacyDownTime_beforNightClose' );
#
#         delFromDevAttrList( $name, 'ASC_ExternalTriggerDevice' );
    }

    return;
}

## Funktion zum hardwareseitigen setzen des lock-out oder blocking beim Rolladen selbst
sub HardewareBlockForShutters {
    my $hash = shift;
    my $cmd  = shift;

    for ( @{ $hash->{helper}{shuttersList} } ) {
        $shutters->setShuttersDev($_);
        $shutters->setHardLockOut($cmd);
    }

    return;
}

## Funktion für das wiggle aller Shutters zusammen
sub wiggleAll {
    my $hash = shift;

    for ( @{ $hash->{helper}{shuttersList} } ) {
        wiggle( $hash, $_ );
    }

    return;
}

sub wiggle {
    my $hash        = shift;
    my $shuttersDev = shift;

    $shutters->setShuttersDev($shuttersDev);
    $shutters->setNoDelay(1);
    $shutters->setLastDrive('wiggle begin drive');

    my %h = (
        shuttersDev => $shutters->getShuttersDev,
        posValue    => $shutters->getStatus,
        lastDrive   => 'wiggle end drive',
    );

    if ( $shutters->getShuttersPosCmdValueNegate ) {
        if ( $shutters->getStatus >= $shutters->getClosedPos / 2 ) {
            $shutters->setDriveCmd(
                $shutters->getStatus - $shutters->getWiggleValue );
        }
        else {
            $shutters->setDriveCmd(
                $shutters->getStatus + $shutters->getWiggleValue );
        }
    }
    else {
        if ( $shutters->getStatus >= $shutters->getOpenPos / 2 ) {
            $shutters->setDriveCmd(
                $shutters->getStatus - $shutters->getWiggleValue );
        }
        else {
            $shutters->setDriveCmd(
                $shutters->getStatus + $shutters->getWiggleValue );
        }
    }

    InternalTimer( gettimeofday() + 60, \&_SetCmdFn, \%h );

    return;
}
####

## Funktion welche beim Ablaufen des Timers für Sunset aufgerufen werden soll
sub SunSetShuttersAfterTimerFn {
    my $funcHash = shift;

    my $hash        = $funcHash->{hash};
    my $shuttersDev = $funcHash->{shuttersdevice};
    $shutters->setShuttersDev($shuttersDev);

    my $homemode = $shutters->getRoommatesStatus;
    $homemode = $ascDev->getResidentsStatus if ( $homemode eq 'none' );

    if (
           $shutters->getDown ne 'roommate'
        && $ascDev->getAutoShuttersControlEvening eq 'on'
        && IsAfterShuttersManualBlocking($shuttersDev)
        && (
            $shutters->getModeDown eq $homemode
            || (   $shutters->getModeDown eq 'absent'
                && $homemode eq 'gone' )
            || $shutters->getModeDown eq 'always'
        )
        && (
               $ascDev->getSelfDefense eq 'off'
            || $shutters->getSelfDefenseMode eq 'off'
            || (   $ascDev->getSelfDefense eq 'on'
                && $ascDev->getResidentsStatus ne 'gone' )
        )
        && (
            $shutters->getDown ne 'brightness'
            || ( $shutters->getDown eq 'brightness'
                && !$shutters->getSunset )
        )
      )
    {

        if ( $shutters->getPrivacyDownStatus == 1 ) {
            $shutters->setPrivacyDownStatus(2);
            $shutters->setLastDrive('timer privacy night close');
            ShuttersCommandSet( $hash, $shuttersDev,
                $shutters->getPrivacyDownPos )
              unless (
                $shutters->getQueryShuttersPos( $shutters->getPrivacyDownPos )
              );
        }
        else {
            $shutters->setPrivacyDownStatus(0)
              if ( $shutters->getPrivacyDownStatus == 2 );
            $shutters->setLastDrive('night close');
            ShuttersCommandSet(
                $hash,
                $shuttersDev,
                PositionValueWindowRec(
                    $shuttersDev,
                    (
                          $shutters->getSleepPos > 0
                        ? $shutters->getSleepPos
                        : $shutters->getClosedPos
                    )
                )
            );
        }
    }

    unless ( $shutters->getPrivacyDownStatus == 2 ) {
        $shutters->setSunrise(0);
        $shutters->setSunset(1);
    }

    CreateSunRiseSetShuttersTimer( $hash, $shuttersDev );

    return;
}

## Funktion welche beim Ablaufen des Timers für Sunrise aufgerufen werden soll
sub SunRiseShuttersAfterTimerFn {
    my $funcHash = shift;

    my $hash        = $funcHash->{hash};
    my $shuttersDev = $funcHash->{shuttersdevice};
    $shutters->setShuttersDev($shuttersDev);

    my $homemode = $shutters->getRoommatesStatus;
    $homemode = $ascDev->getResidentsStatus if ( $homemode eq 'none' );

    if (
           $shutters->getUp ne 'roommate'
        && $ascDev->getAutoShuttersControlMorning eq 'on'
        && (
            $shutters->getModeUp eq $homemode
            || (   $shutters->getModeUp eq 'absent'
                && $homemode eq 'gone' )
            || $shutters->getModeUp eq 'always'
        )
        && (
               $ascDev->getSelfDefense eq 'off'
            || $shutters->getSelfDefenseMode eq 'off'
            || (
                $ascDev->getSelfDefense eq 'on'
                && (   $shutters->getSelfDefenseMode eq 'gone'
                    || $shutters->getSelfDefenseMode eq 'absent' )
                && $ascDev->getResidentsStatus ne 'gone'
            )
            || (   $ascDev->getSelfDefense eq 'on'
                && $shutters->getSelfDefenseMode eq 'absent'
                && $ascDev->getResidentsStatus ne 'absent' )
        )
        && (
            $shutters->getUp ne 'brightness'
            || ( $shutters->getUp eq 'brightness'
                && !$shutters->getSunrise )
        )
      )
    {

        if (
            (
                   $shutters->getRoommatesStatus eq 'home'
                || $shutters->getRoommatesStatus eq 'awoken'
                || $shutters->getRoommatesStatus eq 'absent'
                || $shutters->getRoommatesStatus eq 'gone'
                || $shutters->getRoommatesStatus eq 'none'
            )
            && (
                $ascDev->getSelfDefense eq 'off'
                || ( $ascDev->getSelfDefense eq 'on'
                    && CheckIfShuttersWindowRecOpen($shuttersDev) == 0 )
                || (
                       $ascDev->getSelfDefense eq 'on'
                    && CheckIfShuttersWindowRecOpen($shuttersDev) != 0
                    && (   $ascDev->getResidentsStatus ne 'absent'
                        && $ascDev->getResidentsStatus ne 'gone' )
                )
            )
          )
        {
            if ( !$shutters->getIfInShading ) {
                if ( $shutters->getPrivacyUpStatus == 1 ) {
                    $shutters->setPrivacyUpStatus(2);
                    $shutters->setLastDrive('timer privacy day open');
                    ShuttersCommandSet( $hash, $shuttersDev,
                        $shutters->getPrivacyUpPos )
                      unless (
                        !$shutters->getQueryShuttersPos(
                            $shutters->getPrivacyUpPos
                        )
                      );
                }
                else {
                    $shutters->setLastDrive('day open');
                    ShuttersCommandSet( $hash, $shuttersDev,
                        $shutters->getOpenPos );

                    $shutters->setPrivacyUpStatus(0)
                      if ( $shutters->getPrivacyUpStatus == 2 );
                }
            }
            elsif ( $shutters->getIfInShading ) {
                $shutters->setLastDrive('shading in');
                ShuttersCommandSet( $hash, $shuttersDev,
                    $shutters->getShadingPos );

                $shutters->setPrivacyUpStatus(0)
                  if ( $shutters->getPrivacyUpStatus == 2 );
            }
        }
    }

    unless ( $shutters->getPrivacyUpStatus == 2 ) {
        $shutters->setSunrise(1);
        $shutters->setSunset(0);
    }

    CreateSunRiseSetShuttersTimer( $hash, $shuttersDev );

    return;
}

sub CreateNewNotifyDev {
    my $hash = shift;

    my $name = $hash->{NAME};

    $hash->{NOTIFYDEV} = "global," . $name;
    delete $hash->{monitoredDevs};

    CommandDeleteReading( undef, $name . ' .monitoredDevs' );
    my $shuttersList = '';
    for ( @{ $hash->{helper}{shuttersList} } ) {
        AddNotifyDev( $hash, AttrVal( $_, 'ASC_Roommate_Device', 'none' ),
            $_, 'ASC_Roommate_Device' )
          if ( AttrVal( $_, 'ASC_Roommate_Device', 'none' ) ne 'none' );
        AddNotifyDev( $hash, AttrVal( $_, 'ASC_WindowRec', 'none' ),
            $_, 'ASC_WindowRec' )
          if ( AttrVal( $_, 'ASC_WindowRec', 'none' ) ne 'none' );
        AddNotifyDev( $hash, AttrVal( $_, 'ASC_BrightnessSensor', 'none' ),
            $_, 'ASC_BrightnessSensor' )
          if ( AttrVal( $_, 'ASC_BrightnessSensor', 'none' ) ne 'none' );
        AddNotifyDev( $hash, AttrVal( $_, 'ASC_ExternalTrigger', 'none' ),
            $_, 'ASC_ExternalTrigger' )
          if ( AttrVal( $_, 'ASC_ExternalTrigger', 'none' ) ne 'none' );

        $shuttersList = $shuttersList . ',' . $_;
    }

    AddNotifyDev( $hash, AttrVal( $name, 'ASC_residentsDev', 'none' ),
        $name, 'ASC_residentsDev' )
      if ( AttrVal( $name, 'ASC_residentsDev', 'none' ) ne 'none' );
    AddNotifyDev( $hash, AttrVal( $name, 'ASC_rainSensor', 'none' ),
        $name, 'ASC_rainSensor' )
      if ( AttrVal( $name, 'ASC_rainSensor', 'none' ) ne 'none' );
    AddNotifyDev( $hash, AttrVal( $name, 'ASC_twilightDevice', 'none' ),
        $name, 'ASC_twilightDevice' )
      if ( AttrVal( $name, 'ASC_twilightDevice', 'none' ) ne 'none' );
    AddNotifyDev( $hash, AttrVal( $name, 'ASC_windSensor', 'none' ),
        $name, 'ASC_windSensor' )
      if ( AttrVal( $name, 'ASC_windSensor', 'none' ) ne 'none' );

    $hash->{NOTIFYDEV} = $hash->{NOTIFYDEV} . $shuttersList;

    return;
}

sub ShuttersInformation {
    my ( $FW_wname, $d, $room, $pageHash ) = @_;

    my $hash = $defs{$d};

    return
      if ( !exists( $hash->{helper} )
        || !defined( $hash->{helper}->{shuttersList} )
        || ref( $hash->{helper}->{shuttersList} ) ne 'ARRAY'
        || scalar( @{ $hash->{helper}->{shuttersList} } ) == 0
        || !defined( $shutters->getSunriseUnixTime )
        || !defined( $shutters->getSunsetUnixTime ) );

    my $ret =
      '<html><table><tr><h3>ASC Configuration and Information Summary</h3><td>';
    $ret .= '<table class="block wide">';
    $ret .= '<tr class="even">';
    $ret .= "<td><b>Shutters</b></td>";
    $ret .= "<td> </td>";
    $ret .= "<td><b>Next DriveUp</b></td>";
    $ret .= "<td> </td>";
    $ret .= "<td><b>Next DriveDown</b></td>";
    $ret .= "<td> </td>";
    $ret .= "<td><b>ASC Up</b></td>";
    $ret .= "<td> </td>";
    $ret .= "<td><b>ASC Down</b></td>";
    $ret .= "<td> </td>";
    $ret .= "<td><b>ASC Mode Up</b></td>";
    $ret .= "<td> </td>";
    $ret .= "<td><b>ASC Mode Down</b></td>";
    $ret .= "<td> </td>";
    $ret .= "<td><b>Partymode</b></td>";
    $ret .= "<td> </td>";
    $ret .= "<td><b>Lock-Out</b></td>";
    $ret .= "<td> </td>";
    $ret .= "<td><b>Last Drive</b></td>";
    $ret .= "<td> </td>";
    $ret .= "<td><b>Position</b></td>";
    $ret .= "<td> </td>";
    $ret .= "<td><b>Last Position</b></td>";
    $ret .= "<td> </td>";
    $ret .= "<td><b>Shading Info</b></td>";
    $ret .= '</tr>';

    my $linecount = 1;
    for my $shutter ( @{ $hash->{helper}{shuttersList} } ) {
        $shutters->setShuttersDev($shutter);

        if   ( $linecount % 2 == 0 ) { $ret .= '<tr class="even">'; }
        else                         { $ret .= '<tr class="odd">'; }
        $ret .= "<td>$shutter</td>";
        $ret .= "<td> </td>";
        $ret .= "<td>"
          . strftime( "%e.%m.%Y - %H:%M:%S",
            localtime( $shutters->getSunriseUnixTime ) )
          . "</td>";
        $ret .= "<td> </td>";
        $ret .= "<td>"
          . strftime( "%e.%m.%Y - %H:%M:%S",
            localtime( $shutters->getSunsetUnixTime ) )
          . "</td>";
        $ret .= "<td> </td>";
        $ret .= "<td>" . $shutters->getUp . "</td>";
        $ret .= "<td> </td>";
        $ret .= "<td>" . $shutters->getDown . "</td>";
        $ret .= "<td> </td>";
        $ret .= "<td>" . $shutters->getModeUp . "</td>";
        $ret .= "<td> </td>";
        $ret .= "<td>" . $shutters->getModeDown . "</td>";
        $ret .= "<td> </td>";
        $ret .= "<td>" . $shutters->getPartyMode . "</td>";
        $ret .= "<td> </td>";
        $ret .= "<td>" . $shutters->getLockOut . "</td>";
        $ret .= "<td> </td>";
        $ret .= "<td>"
          . ReadingsVal( $shutter, 'ASC_ShuttersLastDrive', 'none' ) . "</td>";
        $ret .= "<td> </td>";
        $ret .= "<td>" . $shutters->getStatus . "</td>";
        $ret .= "<td> </td>";
        $ret .= "<td>" . $shutters->getLastPos . "</td>";
        $ret .= "<td> </td>";
        $ret .= "<td>"
          . $shutters->getShadingStatus . ' - '
          . strftime( "%H:%M:%S",
            localtime( $shutters->getShadingStatusTimestamp ) )
          . "</td>";
        $ret .= '</tr>';
        $linecount++;
    }
    $ret .= '</table></td></tr>';
    $ret .= '</table></html><br /><br />';

    return $ret;
}

sub GetMonitoredDevs {
    my $hash = shift;

    my $notifydevs = eval {
        decode_json( ReadingsVal( $hash->{NAME}, '.monitoredDevs', 'none' ) );
    };
    my $ret = '<html><table><tr><td>';
    $ret .= '<table class="block wide">';
    $ret .= '<tr class="even">';
    $ret .= "<td><b>Shutters/ASC-Device</b></td>";
    $ret .= "<td> </td>";
    $ret .= "<td><b>NOTIFYDEV</b></td>";
    $ret .= "<td> </td>";
    $ret .= "<td><b>Attribut</b></td>";
    $ret .= "<td> </td>";
    $ret .= '</tr>';

    if ( ref($notifydevs) eq "HASH" ) {
        my $linecount = 1;
        for my $notifydev ( sort keys( %{$notifydevs} ) ) {
            if ( ref( $notifydevs->{$notifydev} ) eq "HASH" ) {
                for my $shutters ( sort keys( %{ $notifydevs->{$notifydev} } ) )
                {
                    if ( $linecount % 2 == 0 ) { $ret .= '<tr class="even">'; }
                    else                       { $ret .= '<tr class="odd">'; }
                    $ret .= "<td>$shutters</td>";
                    $ret .= "<td> </td>";
                    $ret .= "<td>$notifydev</td>";
                    $ret .= "<td> </td>";
                    $ret .= "<td>$notifydevs->{$notifydev}{$shutters}</td>";
                    $ret .= "<td> </td>";
                    $ret .= '</tr>';
                    $linecount++;
                }
            }
        }
    }

    $ret .= '</table></td></tr>';
    $ret .= '</table></html>';

    return $ret;
}

#################################
## my little helper
#################################

sub PositionValueWindowRec {
    my $shuttersDev = shift;
    my $posValue    = shift;

    if ( CheckIfShuttersWindowRecOpen($shuttersDev) == 1
        && $shutters->getVentilateOpen eq 'on' )
    {
        $posValue = $shutters->getVentilatePos;
    }
    elsif (CheckIfShuttersWindowRecOpen($shuttersDev) == 2
        && $shutters->getSubTyp eq 'threestate'
        && $ascDev->getAutoShuttersControlComfort eq 'on' )
    {
        $posValue = $shutters->getComfortOpenPos;
    }
    elsif (
        CheckIfShuttersWindowRecOpen($shuttersDev) == 2
        && (   $shutters->getSubTyp eq 'threestate'
            || $shutters->getSubTyp eq 'twostate' )
        && $shutters->getVentilateOpen eq 'on'
      )
    {
        $posValue = $shutters->getVentilatePos;
    }

    if ( $shutters->getQueryShuttersPos($posValue) ) {
        $posValue = $shutters->getStatus;
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
    my ( $dev, $attribut, $default ) = @_;

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

# Hilfsfunktion welche meinen ReadingString zum finden der getriggerten Devices und der Zurdnung was das Device überhaupt ist und zu welchen Rolladen es gehört aus liest und das Device extraiert
sub ExtractNotifyDevFromEvent {
    my ( $hash, $shuttersDev, $shuttersAttr ) = @_;

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

    $shutters->setShuttersDev($shuttersDev);

    my $isday = ( ShuttersSunrise( $shuttersDev, 'unix' ) >
          ShuttersSunset( $shuttersDev, 'unix' ) ? 1 : 0 );
    my $respIsDay = $isday;

    ASC_Debug( 'FnIsDay: ' . $shuttersDev . ' Allgemein: ' . $respIsDay );

    if (
        (
               $shutters->getDown eq 'brightness'
            || $shutters->getUp eq 'brightness'
        )
        || (
            (
                (
                    (
                        int( gettimeofday() / 86400 ) != int(
                            computeAlignTime( '24:00',
                                $shutters->getTimeUpEarly ) / 86400
                        )
                        && !IsWe()
                    )
                    || (
                        int( gettimeofday() / 86400 ) != int(
                            computeAlignTime( '24:00',
                                $shutters->getTimeUpWeHoliday ) / 86400
                        )
                        && IsWe()
                        && $ascDev->getSunriseTimeWeHoliday eq 'on'
                        && $shutters->getTimeUpWeHoliday ne '01:25'
                    )
                )
                && int( gettimeofday() / 86400 ) == int(
                    computeAlignTime( '24:00', $shutters->getTimeUpLate ) /
                      86400
                )
            )
            || (
                int( gettimeofday() / 86400 ) != int(
                    computeAlignTime( '24:00', $shutters->getTimeDownEarly ) /
                      86400
                )
                && int( gettimeofday() / 86400 ) == int(
                    computeAlignTime( '24:00', $shutters->getTimeDownLate ) /
                      86400
                )
            )
        )
      )
    {
        my $brightnessMinVal;
        if ( $shutters->getBrightnessMinVal > -1 ) {
            $brightnessMinVal = $shutters->getBrightnessMinVal;
        }
        else {
            $brightnessMinVal = $ascDev->getBrightnessMinVal;
        }

        my $brightnessMaxVal;
        if ( $shutters->getBrightnessMaxVal > -1 ) {
            $brightnessMaxVal = $shutters->getBrightnessMaxVal;
        }
        else {
            $brightnessMaxVal = $ascDev->getBrightnessMaxVal;
        }

        ##### Nach Sonnenuntergang / Abends
        $respIsDay = (
            (
                (
                         $shutters->getBrightness > $brightnessMinVal
                      && $isday
                      && !$shutters->getSunset
                )
                  || !$shutters->getSunset
            ) ? 1 : 0
        ) if ( $shutters->getDown eq 'brightness' );

        ASC_Debug( 'FnIsDay nach Sonnenuntergang / Abends: '
              . $shuttersDev
              . ' getDownBrightness: '
              . $respIsDay
              . ' Brightness: '
              . $shutters->getBrightness
              . ' BrightnessMin: '
              . $brightnessMinVal
              . ' Sunset: '
              . $shutters->getSunset
              . ' isday: '
              . $isday );

        ##### Nach Sonnenauf / Morgens
        $respIsDay = (
            (
                (
                         $shutters->getBrightness > $brightnessMaxVal
                      && !$isday
                      && $shutters->getSunrise
                )
                  || $respIsDay
                  || $shutters->getSunrise
            ) ? 1 : 0
        ) if ( $shutters->getUp eq 'brightness' );

        ASC_Debug( 'FnIsDay nach Sonnenaufgang / Morgens: '
              . $shuttersDev
              . ' getUpBrightness: '
              . $respIsDay
              . ' Brightness: '
              . $shutters->getBrightness
              . ' BrightnessMax: '
              . $brightnessMaxVal
              . ' Sunrise: '
              . $shutters->getSunrise
              . ' isday: '
              . $isday );
    }

    return $respIsDay;
}

sub ShuttersSunrise {
    my $shuttersDev = shift;
    my $tm = shift; # Tm steht für Timemode und bedeutet Realzeit oder Unixzeit

    my $autoAstroMode;
    $shutters->setShuttersDev($shuttersDev);

    if ( $shutters->getAutoAstroModeMorning ne 'none' ) {
        $autoAstroMode = $shutters->getAutoAstroModeMorning;
        $autoAstroMode =
          $autoAstroMode . '=' . $shutters->getAutoAstroModeMorningHorizon
          if ( $autoAstroMode eq 'HORIZON' );
    }
    else {
        $autoAstroMode = $ascDev->getAutoAstroModeMorning;
        $autoAstroMode =
          $autoAstroMode . '=' . $ascDev->getAutoAstroModeMorningHorizon
          if ( $autoAstroMode eq 'HORIZON' );
    }
    my $oldFuncHash = $shutters->getInTimerFuncHash;
    my $shuttersSunriseUnixtime =
      computeAlignTime( '24:00', sunrise( 'REAL', 0, '4:30', '8:30' ) );

    if ( $tm eq 'unix' ) {
        if ( $shutters->getUp eq 'astro' ) {
            if (   ( IsWe() || IsWe('tomorrow') )
                && $ascDev->getSunriseTimeWeHoliday eq 'on'
                && $shutters->getTimeUpWeHoliday ne '01:25' )
            {
                if ( !IsWe('tomorrow') ) {
                    if (
                        IsWe()
                        && int( gettimeofday() / 86400 ) == int(
                            (
                                computeAlignTime(
                                    '24:00',
                                    sunrise_abs(
                                        $autoAstroMode, 0,
                                        $shutters->getTimeUpWeHoliday
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
                                    $autoAstroMode, 0,
                                    $shutters->getTimeUpWeHoliday
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
                                        $shutters->getTimeUpEarly,
                                        $shutters->getTimeUpLate
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
                                    $autoAstroMode, 0,
                                    $shutters->getTimeUpWeHoliday
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
                                    $shutters->getTimeUpEarly,
                                    $shutters->getTimeUpLate
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
                                            $autoAstroMode, 0,
                                            $shutters->getTimeUpWeHoliday
                                        )
                                    ) + 1
                                ) / 86400
                            )
                            || int( gettimeofday() / 86400 ) != int(
                                (
                                    computeAlignTime(
                                        '24:00',
                                        sunrise_abs(
                                            $autoAstroMode, 0,
                                            $shutters->getTimeUpWeHoliday
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
                                    $autoAstroMode, 0,
                                    $shutters->getTimeUpWeHoliday
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
                                        $shutters->getTimeUpEarly,
                                        $shutters->getTimeUpLate
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
                                    $shutters->getTimeUpEarly,
                                    $shutters->getTimeUpLate
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
                                            $autoAstroMode, 0,
                                            $shutters->getTimeUpWeHoliday
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
                                        $autoAstroMode, 0,
                                        $shutters->getTimeUpWeHoliday
                                    )
                                ) + 86401
                            );
                        }
                        else {
                            $shuttersSunriseUnixtime = (
                                computeAlignTime(
                                    '24:00',
                                    sunrise_abs(
                                        $autoAstroMode, 0,
                                        $shutters->getTimeUpWeHoliday
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
                            $shutters->getTimeUpEarly,
                            $shutters->getTimeUpLate
                        )
                    ) + 1
                );
            }
            if (   defined($oldFuncHash)
                && ref($oldFuncHash) eq 'HASH'
                && ( IsWe() || IsWe('tomorrow') )
                && $ascDev->getSunriseTimeWeHoliday eq 'on'
                && $shutters->getTimeUpWeHoliday ne '01:25' )
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
                                        $shutters->getTimeUpEarly,
                                        $shutters->getTimeUpLate
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
        elsif ( $shutters->getUp eq 'time' ) {
            if (   ( IsWe() || IsWe('tomorrow') )
                && $ascDev->getSunriseTimeWeHoliday eq 'on'
                && $shutters->getTimeUpWeHoliday ne '01:25' )
            {
                if ( !IsWe('tomorrow') ) {
                    if (
                        int( gettimeofday() / 86400 ) == int(
                            computeAlignTime( '24:00',
                                $shutters->getTimeUpWeHoliday ) / 86400
                        )
                      )
                    {
                        $shuttersSunriseUnixtime =
                          computeAlignTime( '24:00',
                            $shutters->getTimeUpWeHoliday );
                    }
                    elsif (
                        int( gettimeofday() / 86400 ) == int(
                            computeAlignTime( '24:00',
                                $shutters->getTimeUpEarly ) / 86400
                        )
                        && $shutters->getSunrise
                      )
                    {
                        $shuttersSunriseUnixtime =
                          computeAlignTime( '24:00', $shutters->getTimeUpEarly )
                          + 86400;
                    }
                    else {
                        $shuttersSunriseUnixtime =
                          computeAlignTime( '24:00',
                            $shutters->getTimeUpEarly );
                    }
                }
                else {
                    if (
                        IsWe()
                        && int( gettimeofday() / 86400 ) == int(
                            computeAlignTime( '24:00',
                                $shutters->getTimeUpWeHoliday ) / 86400
                        )
                      )
                    {
                        $shuttersSunriseUnixtime =
                          computeAlignTime( '24:00',
                            $shutters->getTimeUpWeHoliday );
                    }
                    elsif (
                        int( gettimeofday() / 86400 ) == int(
                            computeAlignTime( '24:00',
                                $shutters->getTimeUpEarly ) / 86400
                        )
                      )
                    {
                        $shuttersSunriseUnixtime =
                          computeAlignTime( '24:00',
                            $shutters->getTimeUpEarly );
                    }
                    elsif (
                        int( gettimeofday() / 86400 ) != int(
                            computeAlignTime( '24:00',
                                $shutters->getTimeUpWeHoliday ) / 86400
                        )
                      )
                    {
                        $shuttersSunriseUnixtime =
                          computeAlignTime( '24:00',
                            $shutters->getTimeUpWeHoliday );
                    }
                    else {
                        $shuttersSunriseUnixtime =
                          computeAlignTime( '24:00',
                            $shutters->getTimeUpWeHoliday ) + 86400;
                    }
                }
            }
            else {
                $shuttersSunriseUnixtime =
                  computeAlignTime( '24:00', $shutters->getTimeUpEarly );
            }
        }
        elsif ( $shutters->getUp eq 'brightness' ) {
            if (   ( IsWe() || IsWe('tomorrow') )
                && $ascDev->getSunriseTimeWeHoliday eq 'on'
                && $shutters->getTimeUpWeHoliday ne '01:25' )
            {
                if ( !IsWe('tomorrow') ) {
                    if (
                        IsWe()
                        && int( gettimeofday() / 86400 ) == int(
                            (
                                computeAlignTime(
                                    '24:00', $shutters->getTimeUpWeHoliday
                                )
                            ) / 86400
                        )
                      )
                    {
                        $shuttersSunriseUnixtime =
                          computeAlignTime( '24:00',
                            $shutters->getTimeUpWeHoliday );
                    }
                    elsif (
                        int( gettimeofday() / 86400 ) == int(
                            (
                                computeAlignTime(
                                    '24:00', $shutters->getTimeUpLate
                                )
                            ) / 86400
                        )
                      )
                    {
                        $shuttersSunriseUnixtime =
                          computeAlignTime( '24:00',
                            $shutters->getTimeUpWeHoliday );
                    }
                    else {
                        $shuttersSunriseUnixtime =
                          computeAlignTime( '24:00', $shutters->getTimeUpLate );
                    }
                }
                else {
                    if (
                        IsWe()
                        && (
                            int( gettimeofday() / 86400 ) == int(
                                (
                                    computeAlignTime(
                                        '24:00', $shutters->getTimeUpWeHoliday
                                    )
                                ) / 86400
                            )
                            || int( gettimeofday() / 86400 ) != int(
                                (
                                    computeAlignTime(
                                        '24:00', $shutters->getTimeUpWeHoliday
                                    )
                                ) / 86400
                            )
                        )
                      )
                    {
                        $shuttersSunriseUnixtime =
                          computeAlignTime( '24:00',
                            $shutters->getTimeUpWeHoliday );
                    }
                    elsif (
                        int( gettimeofday() / 86400 ) == int(
                            (
                                computeAlignTime(
                                    '24:00', $shutters->getTimeUpLate
                                )
                            ) / 86400
                        )
                      )
                    {
                        $shuttersSunriseUnixtime =
                          computeAlignTime( '24:00', $shutters->getTimeUpLate );
                    }
                    else {
                        if (
                            int( gettimeofday() / 86400 ) == int(
                                (
                                    computeAlignTime(
                                        '24:00', $shutters->getTimeUpWeHoliday
                                    )
                                ) / 86400
                            )
                          )
                        {
                            $shuttersSunriseUnixtime =
                              computeAlignTime( '24:00',
                                $shutters->getTimeUpWeHoliday );
                        }
                        else {
                            $shuttersSunriseUnixtime =
                              computeAlignTime( '24:00',
                                $shutters->getTimeUpWeHoliday );
                        }
                    }
                }
            }
            else {

                $shuttersSunriseUnixtime =
                  computeAlignTime( '24:00', $shutters->getTimeUpLate );
            }
        }

        return $shuttersSunriseUnixtime;
    }
    elsif ( $tm eq 'real' ) {
        return sunrise_abs( $autoAstroMode, 0, $shutters->getTimeUpEarly,
            $shutters->getTimeUpLate )
          if ( $shutters->getUp eq 'astro' );
        return $shutters->getTimeUpEarly if ( $shutters->getUp eq 'time' );
    }

    return;
}

sub IsAfterShuttersTimeBlocking {
    my $shuttersDev = shift;

    $shutters->setShuttersDev($shuttersDev);

    if (
        ( int( gettimeofday() ) - $shutters->getLastManPosTimestamp ) <
        $shutters->getBlockingTimeAfterManual
        || (   !$shutters->getIsDay
            && defined( $shutters->getSunriseUnixTime )
            && $shutters->getSunriseUnixTime - ( int( gettimeofday() ) ) <
            $shutters->getBlockingTimeBeforDayOpen )
        || (   $shutters->getIsDay
            && defined( $shutters->getSunriseUnixTime )
            && $shutters->getSunsetUnixTime - ( int( gettimeofday() ) ) <
            $shutters->getBlockingTimeBeforNightClose )
      )
    {
        return 0;
    }

    else { return 1 }
}

sub IsAfterShuttersManualBlocking {
    my $shuttersDev = shift;
    $shutters->setShuttersDev($shuttersDev);

    if (   $ascDev->getBlockAscDrivesAfterManual
        && $shutters->getStatus != $shutters->getOpenPos
        && $shutters->getStatus != $shutters->getClosedPos
        && $shutters->getStatus != $shutters->getWindPos
        && $shutters->getStatus != $shutters->getShadingPos
        && $shutters->getStatus != $shutters->getComfortOpenPos
        && $shutters->getStatus != $shutters->getVentilatePos
        && $shutters->getStatus != $shutters->getAntiFreezePos
        && $shutters->getLastDrive eq 'manual' )
    {
        return 0;
    }
    elsif ( ( int( gettimeofday() ) - $shutters->getLastManPosTimestamp ) <
        $shutters->getBlockingTimeAfterManual )
    {
        return 0;
    }

    else { return 1 }
}

sub ShuttersSunset {
    my $shuttersDev = shift;
    my $tm = shift; # Tm steht für Timemode und bedeutet Realzeit oder Unixzeit

    my $autoAstroMode;
    $shutters->setShuttersDev($shuttersDev);

    if ( $shutters->getAutoAstroModeEvening ne 'none' ) {
        $autoAstroMode = $shutters->getAutoAstroModeEvening;
        $autoAstroMode =
          $autoAstroMode . '=' . $shutters->getAutoAstroModeEveningHorizon
          if ( $autoAstroMode eq 'HORIZON' );
    }
    else {
        $autoAstroMode = $ascDev->getAutoAstroModeEvening;
        $autoAstroMode =
          $autoAstroMode . '=' . $ascDev->getAutoAstroModeEveningHorizon
          if ( $autoAstroMode eq 'HORIZON' );
    }
    my $oldFuncHash = $shutters->getInTimerFuncHash;
    my $shuttersSunsetUnixtime =
      computeAlignTime( '24:00', sunset( 'REAL', 0, '15:30', '21:30' ) );

    if ( $tm eq 'unix' ) {
        if ( $shutters->getDown eq 'astro' ) {
            $shuttersSunsetUnixtime = (
                computeAlignTime(
                    '24:00',
                    sunset_abs(
                        $autoAstroMode,
                        0,
                        $shutters->getTimeDownEarly,
                        $shutters->getTimeDownLate
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
        elsif ( $shutters->getDown eq 'time' ) {
            $shuttersSunsetUnixtime =
              computeAlignTime( '24:00', $shutters->getTimeDownEarly );
        }
        elsif ( $shutters->getDown eq 'brightness' ) {
            $shuttersSunsetUnixtime =
              computeAlignTime( '24:00', $shutters->getTimeDownLate );
        }
        return $shuttersSunsetUnixtime;
    }
    elsif ( $tm eq 'real' ) {
        return sunset_abs(
            $autoAstroMode, 0,
            $shutters->getTimeDownEarly,
            $shutters->getTimeDownLate
        ) if ( $shutters->getDown eq 'astro' );
        return $shutters->getTimeDownEarly
          if ( $shutters->getDown eq 'time' );
    }

    return;
}

## Kontrolliert ob das Fenster von einem bestimmten Rolladen offen ist
sub CheckIfShuttersWindowRecOpen {
    my $shuttersDev = shift;
    $shutters->setShuttersDev($shuttersDev);

    if ( $shutters->getWinStatus =~
        m{[Oo]pen|false}xms )    # CK: covers: open|opened
    {
        return 2;
    }
    elsif ($shutters->getWinStatus =~ m{tilt}xms
        && $shutters->getSubTyp eq 'threestate' )    # CK: covers: tilt|tilted
    {
        return 1;
    }
    elsif ( $shutters->getWinStatus =~ m{[Cc]lose|true}xms ) {
        return 0;
    }                                                # CK: covers: close|closed
}

sub makeReadingName {
    my ($rname) = shift;
    my %charHash = (
        chr(0xe4) => "ae",                           # ä
        chr(0xc4) => "Ae",                           # Ä
        chr(0xfc) => "ue",                           # ü
        chr(0xdc) => "Ue",                           # Ü
        chr(0xf6) => "oe",                           # ö
        chr(0xd6) => "Oe",                           # Ö
        chr(0xdf) => "ss"                            # ß
    );
    my $charHashkeys = join( "", keys(%charHash) );

    return $rname if ( $rname =~ m{^\./}xms );
    $rname =~ s/([$charHashkeys])/$charHash{$1}/xgi;
    $rname =~ s/[^a-z0-9._\-\/]/_/xgi;
    return $rname;
}

sub TimeMin2Sec {
    my $min = shift;
    my $sec;

    $sec = $min * 60;
    return $sec;
}

sub IsWe {
    return main::IsWe( shift, shift );
}

sub _SetCmdFn {
    my $h = shift;

    my $shuttersDev = $h->{shuttersDev};
    my $posValue    = $h->{posValue};

    $shutters->setShuttersDev($shuttersDev);
    $shutters->setLastDrive( $h->{lastDrive} )
      if ( defined( $h->{lastDrive} ) );

    my $idleDetectionValue = $shutters->getIdleDetectionValue;
    my $idleDetection      = $shutters->getIdleDetection;
    return
      unless (
           $shutters->getASCenable eq 'on'
        && $ascDev->getASCenable eq 'on'
        && (   $idleDetection =~ m{^$idleDetectionValue$}xms
            || $idleDetection eq 'none' )
      );

    if ( $shutters->getStatus != $posValue ) {
        $shutters->setLastPos( $shutters->getStatus );
    }
    else {
        $shutters->setLastDrive(
            ReadingsVal( $shuttersDev, 'ASC_ShuttersLastDrive', 'none' ) );
        ASC_Debug( 'FnSetCmdFn: '
              . $shuttersDev
              . ' - Abbruch aktuelle Position ist gleich der Zielposition '
              . $shutters->getStatus . '='
              . $posValue );
        return;
    }

    ASC_Debug( 'FnSetCmdFn: '
          . $shuttersDev
          . ' - Rollo wird gefahren, aktuelle Position: '
          . $shutters->getStatus
          . ', Zielposition: '
          . $posValue
          . '. Grund der Fahrt: '
          . $shutters->getLastDrive );

    CommandSet( undef,
            $shuttersDev
          . ':FILTER='
          . $shutters->getPosCmd . '!='
          . $posValue . ' '
          . $shutters->getPosSetCmd . ' '
          . $posValue );

    $shutters->setSelfDefenseAbsent( 0, 0 )
      if (!$shutters->getSelfDefenseAbsent
        && $shutters->getSelfDefenseAbsentTimerrun );

    return;
}

sub _setShuttersLastDriveDelayed {
    my $h = shift;

    my $shuttersDevHash = $h->{devHash};
    my $lastDrive       = $h->{lastDrive};

    readingsSingleUpdate( $shuttersDevHash, 'ASC_ShuttersLastDrive',
        $lastDrive, 1 );

    return;
}

sub ASC_Debug {
    return
      unless ( AttrVal( $ascDev->getName, 'ASC_debug', 0 ) );

    my $debugMsg = shift;
    my $debugTimestamp = strftime( "%Y.%m.%e %T", localtime(time) );

    print(
        encode_utf8(
            "\n" . 'ASC_DEBUG!!! ' . $debugTimestamp . ' - ' . $debugMsg . "\n"
        )
    );

    return;
}

sub _averageBrightness {
    my @input = @_;
    use List::Util qw(sum);

    return int( sum(@input) / @input );
}

sub _perlCodeCheck {
    my $exec = shift;
    my $val  = undef;

    if ( $exec =~ m{^\{(.+)\}$}xms ) {
        $val = main::AnalyzePerlCommand( undef, $1 );
    }

    return $val;
}

sub PrivacyUpTime {
    my $shuttersDevHash         = shift;
    my $shuttersSunriseUnixtime = shift;

    my $privacyUpUnixtime;

    if ( ( $shuttersSunriseUnixtime - $shutters->getPrivacyUpTime ) >
        ( gettimeofday() + 1 )
        || $shutters->getPrivacyUpStatus == 2 )
    {
        $privacyUpUnixtime =
          $shuttersSunriseUnixtime - $shutters->getPrivacyUpTime;

        $privacyUpUnixtime += 86400
          if ( $shutters->getPrivacyUpStatus == 2 );

        readingsSingleUpdate( $shuttersDevHash, 'ASC_Time_PrivacyDriveUp',
            strftime( "%e.%m.%Y - %H:%M", localtime($privacyUpUnixtime) ), 1 );
        ## Setzt den PrivacyUp Modus für die Sichtschutzfahrt auf den Status 1
        ## und gibt die Unixtime für die nächste Fahrt korrekt zurück
        unless ( $shutters->getPrivacyUpStatus == 2 ) {
            $shutters->setPrivacyUpStatus(1);
            $shuttersSunriseUnixtime = $privacyUpUnixtime;
        }
    }
    else {
        readingsSingleUpdate(
            $shuttersDevHash,
            'ASC_Time_PrivacyDriveUp',
            strftime(
                "%e.%m.%Y - %H:%M",
                localtime(
                    ( $shuttersSunriseUnixtime - $shutters->getPrivacyUpTime )
                    + 86400
                )
            ),
            1
        );
    }

    return $shuttersSunriseUnixtime;
}

sub PrivacyDownTime {
    my $shuttersDevHash        = shift;
    my $shuttersSunsetUnixtime = shift;

    my $privacyDownUnixtime;

    if ( ( $shuttersSunsetUnixtime - $shutters->getPrivacyDownTime ) >
        ( gettimeofday() + 1 )
        || $shutters->getPrivacyDownStatus == 2 )
    {
        $privacyDownUnixtime =
          $shuttersSunsetUnixtime - $shutters->getPrivacyDownTime;

        $privacyDownUnixtime += 86400
          if ( $shutters->getPrivacyDownStatus == 2 );

        readingsSingleUpdate( $shuttersDevHash, 'ASC_Time_PrivacyDriveDown',
            strftime( "%e.%m.%Y - %H:%M", localtime($privacyDownUnixtime) ),
            1 );
        ## Setzt den PrivacyDown Modus für die Sichtschutzfahrt auf den Status 1
        ## und gibt die Unixtime für die nächste Fahrt korrekt zurück
        unless ( $shutters->getPrivacyDownStatus == 2 ) {
            $shutters->setPrivacyDownStatus(1);
            $shuttersSunsetUnixtime = $privacyDownUnixtime;
        }
    }
    else {
        readingsSingleUpdate(
            $shuttersDevHash,
            'ASC_Time_PrivacyDriveDown',
            strftime(
                "%e.%m.%Y - %H:%M",
                localtime(
                    ( $shuttersSunsetUnixtime - $shutters->getPrivacyDownTime )
                    + 86400
                )
            ),
            1
        );
    }

    return $shuttersSunsetUnixtime;
}

sub _IsAdv {
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

sub DevStateIcon {
    my $hash = shift;

    $hash = $defs{$hash} if ( ref($hash) ne 'HASH' );

    return if ( !$hash );
    my $name = $hash->{NAME};

    if ( ReadingsVal( $name, 'state', undef ) eq 'created new drive timer' ) {
        return '.*:clock';
    }
    elsif ( ReadingsVal( $name, 'state', undef ) eq 'selfDefense terrace' ) {
        return '.*:fts_door_tilt';
    }
    elsif ( ReadingsVal( $name, 'state', undef ) =~ m{.*asleep$}xms ) {
        return '.*:scene_sleeping';
    }
    elsif ( ReadingsVal( $name, 'state', undef ) =~
        m{^roommate(.come)?.(awoken|home)$}xms )
    {
        return '.*:user_available';
    }
    elsif ( ReadingsVal( $name, 'state', undef ) =~
        m{^residents.(home|awoken)$}xms )
    {
        return '.*:status_available';
    }
    elsif ( ReadingsVal( $name, 'state', undef ) eq 'manual' ) {
        return '.*:fts_shutter_manual';
    }
    elsif ( ReadingsVal( $name, 'state', undef ) eq 'selfDefense inactive' ) {
        return '.*:status_open';
    }
    elsif (
        ReadingsVal( $name, 'state', undef ) =~ m{^selfDefense.*.active$}xms )
    {
        return '.*:status_locked';
    }
    elsif ( ReadingsVal( $name, 'state', undef ) eq 'day open' ) {
        return '.*:scene_day';
    }
    elsif ( ReadingsVal( $name, 'state', undef ) eq 'night close' ) {
        return '.*:scene_night';
    }
    elsif ( ReadingsVal( $name, 'state', undef ) eq 'shading in' ) {
        return '.*:fts_shutter_shadding_run';
    }
    elsif ( ReadingsVal( $name, 'state', undef ) eq 'shading out' ) {
        return '.*:fts_shutter_shadding_stop';
    }
    elsif ( ReadingsVal( $name, 'state', undef ) eq 'active' ) {
        return '.*:hourglass';
    }
    elsif ( ReadingsVal( $name, 'state', undef ) =~ m{.*privacy.*}xms ) {
        return '.*:fts_shutter_50';
    }
    elsif ( ReadingsVal( $name, 'state', undef ) eq 'adv delay close' ) {
        return '.*:christmas_tree';
    }

    return;
}

######################################
######################################
########## Begin der Klassendeklarierungen für OOP (Objektorientierte Programmierung) #########################
## Klasse Rolläden (Shutters) und die Subklassen Attr und Readings ##
## desweiteren wird noch die Klasse ASC_Roommate mit eingebunden

package ASC_Shutters;
our @ISA =
  qw(ASC_Shutters::Readings ASC_Shutters::Attr ASC_Roommate ASC_Window);

use strict;
use warnings;
use utf8;

use GPUtils qw(GP_Import);

## Import der FHEM Funktionen
BEGIN {
    GP_Import(
        qw(
          defs
          ReadingsVal
          readingsSingleUpdate
          gettimeofday
          InternalTimer
          CommandSet
          Log3)
    );
}

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

    if (   $shutters->getLockOut eq 'hard'
        && $shutters->getLockOutCmd ne 'none' )
    {
        CommandSet( undef, $self->{shuttersDev} . ' inhibit ' . $cmd )
          if ( $shutters->getLockOutCmd eq 'inhibit' );
        CommandSet( undef,
            $self->{shuttersDev} . ' '
              . ( $cmd eq 'on' ? 'blocked' : 'unblocked' ) )
          if ( $shutters->getLockOutCmd eq 'blocked' );
        CommandSet( undef,
            $self->{shuttersDev} . ' '
              . ( $cmd eq 'on' ? 'protectionOn' : 'protectionOff' ) )
          if ( $shutters->getLockOutCmd eq 'protected' );
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
        ( $shutters->getPartyMode eq 'on' && $ascDev->getPartyMode eq 'on' )
        || (   $shutters->getAdv
            && !$shutters->getQueryShuttersPos($posValue)
            && !$shutters->getAdvDelay
            && !$shutters->getExternalTriggerState
            && !$shutters->getSelfDefenseState )
      )
    {
        $shutters->setDelayCmd($posValue);
        $ascDev->setDelayCmdReading;
        $shutters->setNoDelay(0);
        $shutters->setExternalTriggerState(0)
          if ( $shutters->getExternalTriggerState );

        FHEM::AutoShuttersControl::ASC_Debug( 'setDriveCmd: '
              . $shutters->getShuttersDev
              . ' - Die Fahrt wird zurückgestellt. Grund kann ein geöffnetes Fenster sein oder ein aktivierter Party Modus oder Weihnachtszeit'
        );
    }
    else {
        $shutters->setAdvDelay(0)
          if ( $shutters->getAdvDelay );
        $shutters->setDelayCmd('none')
          if ( $shutters->getDelayCmd ne 'none' )
          ; # setzt den Wert auf none da der Rolladen nun gesteuert werden kann.
        $shutters->setExternalTriggerState(0)
          if ( $shutters->getExternalTriggerState );

        ### antifreeze Routine
        if ( $shutters->getFreezeStatus > 0 ) {
            if ( $shutters->getFreezeStatus != 1 ) {

                $posValue = $shutters->getStatus;
                $shutters->setLastDrive('no drive - antifreeze defense');
                $shutters->setLastDriveReading;
                $ascDev->setStateReading;
            }
            elsif ( $posValue == $shutters->getClosedPos ) {
                $posValue = $shutters->getAntiFreezePos;
                $shutters->setLastDrive(
                    $shutters->getLastDrive . ' - antifreeze mode' );
            }
        }

        my %h = (
            shuttersDev => $self->{shuttersDev},
            posValue    => $posValue,
        );

        $offSet = $shutters->getDelay        if ( $shutters->getDelay > -1 );
        $offSet = $ascDev->getShuttersOffset if ( $shutters->getDelay < 0 );
        $offSetStart = $shutters->getDelayStart;

        if (   $shutters->getSelfDefenseAbsent
            && !$shutters->getSelfDefenseAbsentTimerrun
            && $shutters->getSelfDefenseMode ne 'off'
            && $shutters->getSelfDefenseState
            && $ascDev->getSelfDefense eq 'on' )
        {
            InternalTimer(
                gettimeofday() + $shutters->getSelfDefenseAbsentDelay,
                \&FHEM::AutoShuttersControl::_SetCmdFn, \%h );
            $shutters->setSelfDefenseAbsent( 1, 0, \%h );
        }
        elsif ( $offSetStart > 0 && !$shutters->getNoDelay ) {
            InternalTimer(
                gettimeofday() +
                  int( rand($offSet) + $shutters->getDelayStart ),
                \&FHEM::AutoShuttersControl::_SetCmdFn, \%h
            );

            FHEM::AutoShuttersControl::ASC_Debug( 'FnSetDriveCmd: '
                  . $shutters->getShuttersDev
                  . ' - versetztes fahren' );
        }
        elsif ( $offSetStart < 1 || $shutters->getNoDelay ) {
            FHEM::AutoShuttersControl::_SetCmdFn( \%h );
            FHEM::AutoShuttersControl::ASC_Debug( 'FnSetDriveCmd: '
                  . $shutters->getShuttersDev
                  . ' - NICHT versetztes fahren' );
        }

        FHEM::AutoShuttersControl::ASC_Debug( 'FnSetDriveCmd: '
              . $shutters->getShuttersDev
              . ' - NoDelay: '
              . ( $shutters->getNoDelay ? 'JA' : 'NEIN' ) );
        $shutters->setNoDelay(0);
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
    my $shuttersDevHash = $defs{ $self->{shuttersDev} };

    my %h = (
        devHash   => $shuttersDevHash,
        lastDrive => $shutters->getLastDrive,
    );

    InternalTimer( gettimeofday() + 0.1,
        \&FHEM::AutoShuttersControl::_setShuttersLastDriveDelayed, \%h );
    return;
}

sub setLastPos {

# letzte ermittelte Position bevor die Position des Rolladen über ASC geändert wurde
    my $self     = shift;
    my $position = shift;

    $self->{ $self->{shuttersDev} }{lastPos}{VAL} = $position
      if ( defined($position) );
    $self->{ $self->{shuttersDev} }{lastPos}{TIME} = int( gettimeofday() )
      if ( defined( $self->{ $self->{shuttersDev} }{lastPos} ) );
    return;
}

sub setLastManPos {
    my $self     = shift;
    my $position = shift;

    $self->{ $self->{shuttersDev} }{lastManPos}{VAL} = $position
      if ( defined($position) );
    $self->{ $self->{shuttersDev} }{lastManPos}{TIME} = int( gettimeofday() )
      if ( defined( $self->{ $self->{shuttersDev} }{lastManPos} )
        && defined( $self->{ $self->{shuttersDev} }{lastManPos}{TIME} ) );
    $self->{ $self->{shuttersDev} }{lastManPos}{TIME} =
      int( gettimeofday() ) - 86400
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

sub getHomemode {
    my $self = shift;

    my $homemode = $shutters->getRoommatesStatus;
    $homemode = $ascDev->getResidentsStatus
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

    return FHEM::AutoShuttersControl::_IsDay( $self->{shuttersDev} );
}

sub getFreezeStatus {
    use POSIX qw(strftime);
    my $self = shift;
    my $daytime = strftime( "%P", localtime() );
    $daytime = (
        defined($daytime) && $daytime
        ? $daytime
        : ( strftime( "%k", localtime() ) < 12 ? 'am' : 'pm' )
    );
    my $outTemp = $ascDev->getOutTemp;
    $outTemp = $shutters->getOutTemp if ( $shutters->getOutTemp != -100 );

    if (   $shutters->getAntiFreeze ne 'off'
        && $outTemp <= $ascDev->getFreezeTemp )
    {

        if ( $shutters->getAntiFreeze eq 'soft' ) {
            return 1;
        }
        elsif ( $shutters->getAntiFreeze eq $daytime ) {
            return 2;
        }
        elsif ( $shutters->getAntiFreeze eq 'hard' ) {
            return 3;
        }
    }
    else { return 0; }
}

sub getShuttersPosCmdValueNegate {
    my $self = shift;

    return ( $shutters->getOpenPos < $shutters->getClosedPos ? 1 : 0 );
}

sub getQueryShuttersPos
{ # Es wird geschaut ob die aktuelle Position des Rollos unterhalb der Zielposition ist
    my $self     = shift;
    my $posValue = shift; #   wenn dem so ist wird 1 zurück gegeben ansonsten 0

    return (
          $shutters->getShuttersPosCmdValueNegate
        ? $shutters->getStatus > $posValue
        : $shutters->getStatus < $posValue
    );
}

sub getPosSetCmd {
    my $self = shift;

    return (
        defined( $self->{ $self->{shuttersDev} }{posSetCmd} )
        ? $self->{ $self->{shuttersDev} }{posSetCmd}
        : $shutters->getPosCmd
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
      ReadingsVal( $self->{shuttersDev}, 'ASC_ShuttersLastDrive', 'none' )
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

    for my $ro ( split( ",", $shutters->getRoommates ) ) {
        $shutters->setRoommate($ro);
        my $currentPrio = $statePrio{ $shutters->_getRoommateStatus };
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

    for my $ro ( split( ",", $shutters->getRoommates ) ) {
        $shutters->setRoommate($ro);
        my $currentPrio = $statePrio{ $shutters->_getRoommateLastStatus };
        $minPrio = $currentPrio if ( $minPrio > $currentPrio );
    }

    my %revStatePrio = reverse %statePrio;
    return $revStatePrio{$minPrio};
}

sub getOutTemp {
    my $self = shift;

    return ReadingsVal( $shutters->_getTempSensor,
        $shutters->getTempSensorReading, -100 );
}

sub getIdleDetection {
    my $self = shift;

    return ReadingsVal( $self->{shuttersDev},
        $shutters->_getIdleDetectionReading, 'none' );
}

### Begin Beschattung Objekt mit Daten befüllen
sub setShadingStatus {
    my $self  = shift;
    my $value = shift; ### Werte für value = in, out, in reserved, out reserved

    return
      if ( defined($value)
        && exists( $self->{ $self->{shuttersDev} }{ShadingStatus}{VAL} )
        && $self->{ $self->{shuttersDev} }{ShadingStatus}{VAL} eq $value );

    $self->{ $self->{shuttersDev} }{ShadingStatus}{VAL} = $value
      if ( defined($value) );
    $self->{ $self->{shuttersDev} }{ShadingStatus}{TIME} = int( gettimeofday() )
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
      int( gettimeofday() )
      if ( defined( $self->{ $self->{shuttersDev} }{ShadingLastStatus} ) );
    $self->{ $self->{shuttersDev} }{ShadingManualDriveStatus}{VAL} = 0
      if ( $value eq 'out' );

    return;
}

sub setShadingManualDriveStatus {
    my $self  = shift;
    my $value = shift;    ### Werte für value = in, out

    $self->{ $self->{shuttersDev} }{ShadingManualDriveStatus}{VAL} = $value
      if ( defined($value) );

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

sub setExternalTriggerState {
    my $self  = shift;
    my $value = shift;

    $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}->{event} = $value
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
        ) > $shutters->getMaxBrightnessAverageArrayObjects
      );

    return;
}

sub getBrightnessAverage {
    my $self = shift;

    return FHEM::AutoShuttersControl::_averageBrightness(
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
                 $shutters->getShadingMode ne 'off'
              && $shutters->getShadingLastStatus eq 'out'
        ) ? 1 : 0
    );
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
### Ende Beschattung

## Subklasse Attr von ASC_Shutters##
package ASC_Shutters::Attr;

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

sub getAntiFreezePos {
    my $self = shift;

    my $val = AttrVal(
        $self->{shuttersDev},
        'ASC_Antifreeze_Pos',
        $userAttrList{
'ASC_Antifreeze_Pos:5,10,15,20,25,30,35,40,45,50,55,60,65,70,75,80,85,90,95,100'
        }[ AttrVal( $self->{shuttersDev}, 'ASC', 2 ) ]
    );

    if ( defined( FHEM::AutoShuttersControl::_perlCodeCheck($val) ) ) {
        $val = FHEM::AutoShuttersControl::_perlCodeCheck($val);
    }

    return (
        $val =~ m{^\d+(\.\d+)?$}xms ? $val : $userAttrList{
'ASC_Antifreeze_Pos:5,10,15,20,25,30,35,40,45,50,55,60,65,70,75,80,85,90,95,100'
        }[ AttrVal( $self->{shuttersDev}, 'ASC', 2 ) ]
    );
}

sub getShuttersPlace {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_ShuttersPlace', 'window' );
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
      FHEM::AutoShuttersControl::GetAttrValues( $self->{shuttersDev},
        'ASC_PrivacyUpValue_beforeDayOpen', '-1:-1' );

    ## Erwartetes Ergebnis
    # upTime:upBrightnessVal

    $self->{ $self->{shuttersDev} }->{ASC_PrivacyUpValue_beforeDayOpen}
      ->{uptime} = $upTime;
    $self->{ $self->{shuttersDev} }->{ASC_PrivacyUpValue_beforeDayOpen}
      ->{upbrightnessval} =
      ( $upBrightnessVal ne 'none' ? $upBrightnessVal : -1 );

    $shutters->setPrivacyUpStatus(0)
      if ( defined( $shutters->getPrivacyUpStatus )
        && $self->{ $self->{shuttersDev} }->{ASC_PrivacyUpValue_beforeDayOpen}
        ->{uptime} == -1 );

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
    $shutters->getPrivacyUpTime;

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
      FHEM::AutoShuttersControl::GetAttrValues( $self->{shuttersDev},
        'ASC_PrivacyDownValue_beforeNightClose', '-1:-1' );

    ## Erwartetes Ergebnis
    # downTime:downBrightnessVal

    $self->{ $self->{shuttersDev} }->{ASC_PrivacyDownValue_beforeNightClose}
      ->{downtime} = $downTime;
    $self->{ $self->{shuttersDev} }->{ASC_PrivacyDownValue_beforeNightClose}
      ->{downbrightnessval} =
      ( $downBrightnessVal ne 'none' ? $downBrightnessVal : -1 );

    $shutters->setPrivacyDownStatus(0)
      if ( defined( $shutters->getPrivacyDownStatus )
        && $self->{ $self->{shuttersDev} }
        ->{ASC_PrivacyDownValue_beforeNightClose}->{downtime} == -1 );

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
    $shutters->getPrivacyDownTime;

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

sub getPrivacyUpPos {
    my $self = shift;

    my $val = AttrVal( $self->{shuttersDev}, 'ASC_PrivacyUp_Pos', 50 );

    if ( defined( FHEM::AutoShuttersControl::_perlCodeCheck($val) ) ) {
        $val = FHEM::AutoShuttersControl::_perlCodeCheck($val);
    }

    return ( $val =~ m{^\d+(\.\d+)?$}xms ? $val : 50 );
}

sub getPrivacyDownPos {
    my $self = shift;

    my $val = AttrVal( $self->{shuttersDev}, 'ASC_PrivacyDown_Pos', 50 );

    if ( defined( FHEM::AutoShuttersControl::_perlCodeCheck($val) ) ) {
        $val = FHEM::AutoShuttersControl::_perlCodeCheck($val);
    }

    return ( $val =~ m{^\d+(\.\d+)?$}xms ? $val : 50 );
}

sub getSelfDefenseMode {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Self_Defense_Mode', 'gone' );
}

sub getSelfDefenseAbsentDelay {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Self_Defense_AbsentDelay', 300 );
}

sub getWiggleValue {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_WiggleValue', 5 );
}

sub getAdv {
    my $self = shift;

    return (
        AttrVal( $self->{shuttersDev}, 'ASC_Adv', 'off' ) eq 'on'
        ? ( FHEM::AutoShuttersControl::_IsAdv == 1 ? 1 : 0 )
        : 0
    );
}

### Begin Beschattung
sub getShadingPos {
    my $self = shift;

    my $val = AttrVal( $self->{shuttersDev}, 'ASC_Shading_Pos',
        $userAttrList{'ASC_Shading_Pos:10,20,30,40,50,60,70,80,90,100'}
          [ AttrVal( $self->{shuttersDev}, 'ASC', 2 ) ] );

    if ( defined( FHEM::AutoShuttersControl::_perlCodeCheck($val) ) ) {
        $val = FHEM::AutoShuttersControl::_perlCodeCheck($val);
    }

    return (
          $val =~ m{^\d+(\.\d+)?$}xms
        ? $val
        : $userAttrList{'ASC_Shading_Pos:10,20,30,40,50,60,70,80,90,100'}
          [ AttrVal( $self->{shuttersDev}, 'ASC', 2 ) ]
    );
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
      FHEM::AutoShuttersControl::GetAttrValues( $self->{shuttersDev},
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
    $shutters->_getTempSensor;

    return (
        defined( $self->{ $self->{shuttersDev} }->{ASC_TempSensor}->{reading} )
        ? $self->{ $self->{shuttersDev} }->{ASC_TempSensor}->{reading}
        : 'temperature'
    );
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
      FHEM::AutoShuttersControl::GetAttrValues( $self->{shuttersDev},
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
    $shutters->_getIdleDetectionReading;

    return (
        defined(
            $self->{ $self->{shuttersDev} }->{ASC_Shutter_IdleDetection}
              ->{value}
          )
        ? $self->{ $self->{shuttersDev} }->{ASC_Shutter_IdleDetection}->{value}
        : 'none'
    );
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
      FHEM::AutoShuttersControl::GetAttrValues( $self->{shuttersDev},
        'ASC_BrightnessSensor', 'none' );

    ### erwartetes Ergebnis
    # DEVICE:READING MAX:MIN
    $self->{ $self->{shuttersDev} }->{ASC_BrightnessSensor}->{device} = $device;
    $self->{ $self->{shuttersDev} }->{ASC_BrightnessSensor}->{reading} =
      ( $reading ne 'none' ? $reading : 'brightness' );
    $self->{ $self->{shuttersDev} }->{ASC_BrightnessSensor}->{triggermin} =
      ( $min ne 'none' ? $min : -1 );
    $self->{ $self->{shuttersDev} }->{ASC_BrightnessSensor}->{triggermax} =
      ( $max ne 'none' ? $max : -1 );

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
    $shutters->_getBrightnessSensor;

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
    $shutters->getShadingAzimuthRight;

    return $self->{ $self->{shuttersDev} }->{ASC_Shading_InOutAzimuth}
      ->{leftVal};
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
      FHEM::AutoShuttersControl::GetAttrValues( $self->{shuttersDev},
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

sub getShadingMinOutsideTemperature {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Shading_Min_OutsideTemperature',
        18 );
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
      FHEM::AutoShuttersControl::GetAttrValues( $self->{shuttersDev},
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
    $shutters->getShadingMinElevation;

    return $self->{ $self->{shuttersDev} }->{ASC_Shading_MinMax_Elevation}
      ->{maxVal};
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
      FHEM::AutoShuttersControl::GetAttrValues( $self->{shuttersDev},
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
    $shutters->getShadingStateChangeSunny;

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
    $shutters->getShadingStateChangeSunny;

    return $self->{ $self->{shuttersDev} }->{BrightnessAverageArray}
      ->{MAXOBJECT};
}

sub getShadingWaitingPeriod {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Shading_WaitingPeriod', 1200 );
}
### Ende Beschattung

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
      = FHEM::AutoShuttersControl::GetAttrValues( $self->{shuttersDev},
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
      ( $posInactive ne 'none' ? $posInactive : $shutters->getLastPos );
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
    $shutters->getExternalTriggerDevice;

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
    $shutters->getExternalTriggerDevice;

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
    $shutters->getExternalTriggerDevice;

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
    $shutters->getExternalTriggerDevice;

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
    $shutters->getExternalTriggerDevice;

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
    $shutters->getExternalTriggerDevice;

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
    $shutters->getExternalTriggerDevice;

    return $self->{ $self->{shuttersDev} }->{ASC_ExternalTrigger}
      ->{posinactive};
}

sub getExternalTriggerState {
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

sub getDelay {
    my $self = shift;

    my $val = AttrVal( $self->{shuttersDev}, 'ASC_Drive_Delay', -1 );
    return ( $val =~ m{^\d+$}xms ? $val : -1 );
}

sub getDelayStart {
    my $self = shift;

    my $val = AttrVal( $self->{shuttersDev}, 'ASC_Drive_DelayStart', -1 );
    return ( ( $val > 0 && $val =~ m{^\d+$}xms ) ? $val : -1 );
}

sub getBlockingTimeAfterManual {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_BlockingTime_afterManual',
        1200 );
}

sub getBlockingTimeBeforNightClose {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_BlockingTime_beforNightClose',
        3600 );
}

sub getBlockingTimeBeforDayOpen {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_BlockingTime_beforDayOpen',
        3600 );
}

sub getPosCmd {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Pos_Reading', 'pct' );
}

sub getOpenPos {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Open_Pos',
        $userAttrList{'ASC_Open_Pos:0,10,20,30,40,50,60,70,80,90,100'}
          [ AttrVal( $self->{shuttersDev}, 'ASC', 2 ) ] );
}

sub getVentilatePos {
    my $self = shift;

    my $val = AttrVal( $self->{shuttersDev}, 'ASC_Ventilate_Pos',
        $userAttrList{'ASC_Ventilate_Pos:10,20,30,40,50,60,70,80,90,100'}
          [ AttrVal( $self->{shuttersDev}, 'ASC', 2 ) ] );

    if ( defined( FHEM::AutoShuttersControl::_perlCodeCheck($val) ) ) {
        $val = FHEM::AutoShuttersControl::_perlCodeCheck($val);
    }

    return (
          $val =~ m{^\d+(\.\d+)?$}xms
        ? $val
        : $userAttrList{'ASC_Ventilate_Pos:10,20,30,40,50,60,70,80,90,100'}
          [ AttrVal( $self->{shuttersDev}, 'ASC', 2 ) ]
    );
}

sub getVentilatePosAfterDayClosed {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_WindowRec_PosAfterDayClosed',
        'open' );
}

sub getClosedPos {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Closed_Pos',
        $userAttrList{'ASC_Closed_Pos:0,10,20,30,40,50,60,70,80,90,100'}
          [ AttrVal( $self->{shuttersDev}, 'ASC', 2 ) ] );
}

sub getSleepPos {
    my $self = shift;

    my $val = AttrVal( $self->{shuttersDev}, 'ASC_Sleep_Pos', -1 );

    if ( defined( FHEM::AutoShuttersControl::_perlCodeCheck($val) ) ) {
        $val = FHEM::AutoShuttersControl::_perlCodeCheck($val);
    }

    return ( $val =~ m{^\d+(\.\d+)?$}xms ? $val : -1 );
}

sub getVentilateOpen {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Ventilate_Window_Open', 'on' );
}

sub getComfortOpenPos {
    my $self = shift;
    my $val = AttrVal( $self->{shuttersDev}, 'ASC_ComfortOpen_Pos',
        $userAttrList{'ASC_ComfortOpen_Pos:0,10,20,30,40,50,60,70,80,90,100'}
          [ AttrVal( $self->{shuttersDev}, 'ASC', 2 ) ] );

    if ( defined( FHEM::AutoShuttersControl::_perlCodeCheck($val) ) ) {
        $val = FHEM::AutoShuttersControl::_perlCodeCheck($val);
    }

    return (
          $val =~ m{^\d+(\.\d+)?$}xms
        ? $val
        : $userAttrList{'ASC_ComfortOpen_Pos:0,10,20,30,40,50,60,70,80,90,100'}
          [ AttrVal( $self->{shuttersDev}, 'ASC', 2 ) ]
    );
}

sub getPartyMode {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Partymode', 'off' );
}

sub getRoommates {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Roommate_Device', 'none' );
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
    $shutters->getWindMax;

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
      FHEM::AutoShuttersControl::GetAttrValues( $self->{shuttersDev},
        'ASC_WindParameters', '50:20' );

    ## Erwartetes Ergebnis
    # max:hyst pos

    $self->{ $self->{shuttersDev} }->{ASC_WindParameters}->{triggermax} = $max;
    $self->{ $self->{shuttersDev} }->{ASC_WindParameters}->{triggerhyst} =
      ( $hyst ne 'none' ? $max - $hyst : $max - 20 );
    $self->{ $self->{shuttersDev} }->{ASC_WindParameters}->{closedPos} =
      ( $pos ne 'none' ? $pos : $shutters->getOpenPos );

    return $self->{ $self->{shuttersDev} }->{ASC_WindParameters}->{triggermax};
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
    $shutters->getWindMax;

    return $self->{ $self->{shuttersDev} }->{ASC_WindParameters}->{triggerhyst};
}

sub getWindProtection {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_WindProtection', 'off' );
}

sub getRainProtection {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_RainProtection', 'off' );
}

sub getModeUp {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Mode_Up', 'always' );
}

sub getModeDown {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Mode_Down', 'always' );
}

sub getLockOut {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_LockOut', 'off' );
}

sub getLockOutCmd {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_LockOut_Cmd', 'none' );
}

sub getAntiFreeze {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Antifreeze', 'off' );
}

sub getAutoAstroModeMorning {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_AutoAstroModeMorning', 'none' );
}

sub getAutoAstroModeEvening {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_AutoAstroModeEvening', 'none' );
}

sub getAutoAstroModeMorningHorizon {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_AutoAstroModeMorningHorizon',
        0 );
}

sub getAutoAstroModeEveningHorizon {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_AutoAstroModeEveningHorizon',
        0 );
}

sub getUp {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Up', 'astro' );
}

sub getDown {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Down', 'astro' );
}

sub getTimeUpEarly {
    my $self = shift;

    my $val = AttrVal( $self->{shuttersDev}, 'ASC_Time_Up_Early', '05:00' );

    if ( defined( FHEM::AutoShuttersControl::_perlCodeCheck($val) ) ) {
        $val = FHEM::AutoShuttersControl::_perlCodeCheck($val);
    }

    return (
          $val =~ m{^(?:[01]?\d|2[0-3]):(?:[0-5]\d)(:(?:[0-5]\d))?$}xms
        ? $val
        : '05:00'
    );
}

sub getTimeUpLate {
    my $self = shift;

    my $val = AttrVal( $self->{shuttersDev}, 'ASC_Time_Up_Late', '08:30' );

    if ( defined( FHEM::AutoShuttersControl::_perlCodeCheck($val) ) ) {
        $val = FHEM::AutoShuttersControl::_perlCodeCheck($val);
    }

    return (
          $val =~ m{^(?:[01]?\d|2[0-3]):(?:[0-5]\d)(:(?:[0-5]\d))?$}xms
        ? $val
        : '08:30'
    );
}

sub getTimeDownEarly {
    my $self = shift;

    my $val = AttrVal( $self->{shuttersDev}, 'ASC_Time_Down_Early', '16:00' );

    if ( defined( FHEM::AutoShuttersControl::_perlCodeCheck($val) ) ) {
        $val = FHEM::AutoShuttersControl::_perlCodeCheck($val);
    }

    return (
          $val =~ m{^(?:[01]?\d|2[0-3]):(?:[0-5]\d)(:(?:[0-5]\d))?$}xms
        ? $val
        : '16:00'
    );
}

sub getTimeDownLate {
    my $self = shift;

    my $val = AttrVal( $self->{shuttersDev}, 'ASC_Time_Down_Late', '22:00' );

    if ( defined( FHEM::AutoShuttersControl::_perlCodeCheck($val) ) ) {
        $val = FHEM::AutoShuttersControl::_perlCodeCheck($val);
    }

    return (
          $val =~ m{^(?:[01]?\d|2[0-3]):(?:[0-5]\d)(:(?:[0-5]\d))?$}xms
        ? $val
        : '22:00'
    );
}

sub getTimeUpWeHoliday {
    my $self = shift;

    my $val =
      AttrVal( $self->{shuttersDev}, 'ASC_Time_Up_WE_Holiday', '01:25' );

    if ( defined( FHEM::AutoShuttersControl::_perlCodeCheck($val) ) ) {
        $val = FHEM::AutoShuttersControl::_perlCodeCheck($val);
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
    $shutters->_getBrightnessSensor;

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
    $shutters->_getBrightnessSensor;

    return $self->{ $self->{shuttersDev} }->{ASC_BrightnessSensor}
      ->{triggermax};
}

sub getDriveUpMaxDuration {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_DriveUpMaxDuration', 60 );
}

## Subklasse Readings von ASC_Shutters ##
package ASC_Shutters::Readings;

use strict;
use warnings;
use utf8;

use GPUtils qw(GP_Import);

## Import der FHEM Funktionen
BEGIN {
    GP_Import(
        qw(
          ReadingsVal
          ReadingsNum)
    );
}

sub getBrightness {
    my $self = shift;

    return ReadingsNum( $shutters->_getBrightnessSensor,
        $shutters->getBrightnessReading, -1 );
}

sub getWindStatus {
    my $self = shift;

    return ReadingsVal( $ascDev->_getWindSensor,
        $ascDev->getWindSensorReading, -1 );
}

sub getStatus {
    my $self = shift;

    return ReadingsNum( $self->{shuttersDev}, $shutters->getPosCmd, 0 );
}

sub getDelayCmd {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }{delayCmd};
}

sub getASCenable {
    my $self = shift;

    return ReadingsVal( $self->{shuttersDev}, 'ASC_Enable', 'on' );
}

## Klasse Fenster (Window) und die Subklassen Attr und Readings ##
package ASC_Window;
our @ISA = qw(ASC_Window::Attr ASC_Window::Readings);

## Subklasse Attr von Klasse ASC_Window ##
package ASC_Window::Attr;

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

sub getSubTyp {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_WindowRec_subType', 'twostate' );
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
      FHEM::AutoShuttersControl::GetAttrValues( $self->{shuttersDev},
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
    $shutters->_getWinDev;

    return $self->{ $self->{shuttersDev} }->{ASC_WindowRec}->{reading};
}

## Subklasse Readings von Klasse ASC_Window ##
package ASC_Window::Readings;

use strict;
use warnings;
use utf8;

use GPUtils qw(GP_Import);

## Import der FHEM Funktionen
BEGIN {
    GP_Import(
        qw(
          ReadingsVal)
    );
}

sub getWinStatus {
    my $self = shift;

    return ReadingsVal( $shutters->_getWinDev, $shutters->getWinDevReading,
        'closed' );
}

## Klasse ASC_Roommate ##
package ASC_Roommate;

use strict;
use warnings;
use utf8;

use GPUtils qw(GP_Import);

## Import der FHEM Funktionen
BEGIN {
    GP_Import(
        qw(
          ReadingsVal)
    );
}

sub _getRoommateStatus {
    my $self = shift;

    my $roommate = $self->{roommate};

    return ReadingsVal( $roommate, $shutters->getRoommatesReading, 'none' );
}

sub _getRoommateLastStatus {
    my $self = shift;

    my $roommate = $self->{roommate};
    my $default  = $self->{defaultarg};

    $default = 'none' if ( !defined($default) );
    return ReadingsVal( $roommate, 'lastState', $default );
}

## Klasse ASC_Dev plus Subklassen ASC_Attr_Dev und ASC_Readings_Dev##
package ASC_Dev;
our @ISA = qw(ASC_Dev::Readings ASC_Dev::Attr);

use strict;
use warnings;
use utf8;

sub new {
    my $class = shift;

    my $self = { name => undef, };

    bless $self, $class;
    return $self;
}

sub setName {
    my $self = shift;
    my $name = shift;

    $self->{name} = $name if ( defined($name) );
    return $self->{name};
}

sub setDefault {
    my $self       = shift;
    my $defaultarg = shift;

    $self->{defaultarg} = $defaultarg if ( defined($defaultarg) );
    return $self->{defaultarg};
}

sub getName {
    my $self = shift;
    return $self->{name};
}

## Subklasse Readings ##
package ASC_Dev::Readings;

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

    readingsSingleUpdate( $hash,
        $shutters->getShuttersDev . '_lastDelayPosValue',
        $shutters->getDelayCmd, 1 );
    return;
}

sub setStateReading {
    my $self  = shift;
    my $value = shift;

    my $name = $self->{name};
    my $hash = $defs{$name};

    readingsSingleUpdate( $hash, 'state',
        ( defined($value) ? $value : $shutters->getLastDrive ), 1 );
    return;
}

sub setPosReading {
    my $self = shift;

    my $name = $self->{name};
    my $hash = $defs{$name};

    readingsSingleUpdate( $hash, $shutters->getShuttersDev . '_PosValue',
        $shutters->getStatus, 1 );
    return;
}

sub setLastPosReading {
    my $self = shift;

    my $name = $self->{name};
    my $hash = $defs{$name};

    readingsSingleUpdate( $hash, $shutters->getShuttersDev . '_lastPosValue',
        $shutters->getLastPos, 1 );
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

    return ReadingsVal( $ascDev->_getTempSensor, $ascDev->getTempSensorReading,
        -100 );
}

sub getResidentsStatus {
    my $self = shift;

    my $val =
      ReadingsVal( $ascDev->_getResidentsDev, $ascDev->getResidentsReading,
        'none' );

    if ( $val =~ m{^(?:(.+)_)?(.+)$}xms ) {
        return ( $1, $2 ) if (wantarray);
        return $1 && $1 eq 'pet' ? 'absent' : $2;
    }
    elsif (
        ReadingsVal( $ascDev->_getResidentsDev, 'homealoneType', '-' ) eq
        'PET' )
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

    my $val = ReadingsVal( $ascDev->_getResidentsDev, 'lastState', 'none' );

    if ( $val =~ m{^(?:(.+)_)?(.+)$}xms ) {
        return ( $1, $2 ) if (wantarray);
        return $1 && $1 eq 'pet' ? 'absent' : $2;
    }
    elsif (
        ReadingsVal( $ascDev->_getResidentsDev, 'lastHomealoneType', '-' ) eq
        'PET' )
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

    $azimuth = ReadingsVal( $ascDev->_getTwilightDevice, 'azimuth', -1 )
      if ( $defs{ $ascDev->_getTwilightDevice }->{TYPE} eq 'Twilight' );
    $azimuth = ReadingsVal( $ascDev->_getTwilightDevice, 'SunAz', -1 )
      if ( $defs{ $ascDev->_getTwilightDevice }->{TYPE} eq 'Astro' );

    return $azimuth;
}

sub getElevation {
    my $self = shift;

    my $elevation;

    $elevation = ReadingsVal( $ascDev->_getTwilightDevice, 'elevation', -1 )
      if ( $defs{ $ascDev->_getTwilightDevice }->{TYPE} eq 'Twilight' );
    $elevation = ReadingsVal( $ascDev->_getTwilightDevice, 'SunAlt', -1 )
      if ( $defs{ $ascDev->_getTwilightDevice }->{TYPE} eq 'Astro' );

    return $elevation;
}

sub getASCenable {
    my $self = shift;

    my $name = $self->{name};

    return ReadingsVal( $name, 'ascEnable', 'none' );
}

## Subklasse Attr ##
package ASC_Dev::Attr;

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
    $ascDev->getBrightnessMaxVal;

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
      FHEM::AutoShuttersControl::GetAttrValues( $name,
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

sub _getTempSensor {
    my $self = shift;

    my $name = $self->{name};

    return $self->{ASC_tempSensor}->{device}
      if ( exists( $self->{ASC_tempSensor}->{LASTGETTIME} )
        && ( gettimeofday() - $self->{ASC_tempSensor}->{LASTGETTIME} ) < 2 );
    $self->{ASC_tempSensor}->{LASTGETTIME} = int( gettimeofday() );
    my ( $device, $reading ) =
      FHEM::AutoShuttersControl::GetAttrValues( $name, 'ASC_tempSensor',
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
    $ascDev->_getTempSensor;
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
      FHEM::AutoShuttersControl::GetAttrValues( $name, 'ASC_residentsDev',
        'none' );

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
    $ascDev->_getResidentsDev;
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
      FHEM::AutoShuttersControl::GetAttrValues( $name, 'ASC_rainSensor',
        'none' );

    ## erwartetes Ergebnis
    # DEVICE:READING MAX:HYST

    return $device if ( $device eq 'none' );
    $self->{ASC_rainSensor}->{device} = $device;
    $self->{ASC_rainSensor}->{reading} =
      ( $reading ne 'none' ? $reading : 'state' );
    $self->{ASC_rainSensor}->{triggermax} = ( $max ne 'none' ? $max : 1000 );
    $self->{ASC_rainSensor}->{triggerhyst} = (
          $hyst ne 'none'
        ? $max - $hyst
        : ( $self->{ASC_rainSensor}->{triggermax} * 0 )
    );
    $self->{ASC_rainSensor}->{shuttersClosedPos} =
      ( $pos ne 'none' ? $pos : $shutters->getClosedPos );
    $self->{ASC_rainSensor}->{waitingTime} =
      ( $pos ne 'none' ? $wait : 900 );

    return $self->{ASC_rainSensor}->{device};
}

sub getRainSensorReading {
    my $self = shift;

    my $name = $self->{name};

    return $self->{ASC_rainSensor}->{reading}
      if ( exists( $self->{ASC_rainSensor}->{LASTGETTIME} )
        && ( gettimeofday() - $self->{ASC_rainSensor}->{LASTGETTIME} ) < 2 );
    $ascDev->_getRainSensor;
    return $self->{ASC_rainSensor}->{reading};
}

sub getRainTriggerMax {
    my $self = shift;

    my $name = $self->{name};

    return $self->{ASC_rainSensor}->{triggermax}
      if ( exists( $self->{ASC_rainSensor}->{LASTGETTIME} )
        && ( gettimeofday() - $self->{ASC_rainSensor}->{LASTGETTIME} ) < 2 );
    $ascDev->_getRainSensor;
    return $self->{ASC_rainSensor}->{triggermax};
}

sub getRainTriggerMin {
    my $self = shift;

    my $name = $self->{name};

    return $self->{ASC_rainSensor}->{triggerhyst}
      if ( exists( $self->{ASC_rainSensor}->{LASTGETTIME} )
        && ( gettimeofday() - $self->{ASC_rainSensor}->{LASTGETTIME} ) < 2 );
    $ascDev->_getRainSensor;
    return $self->{ASC_rainSensor}->{triggerhyst};
}

sub getRainSensorShuttersClosedPos {
    my $self = shift;

    my $name = $self->{name};

    return $self->{ASC_rainSensor}->{shuttersClosedPos}
      if ( exists( $self->{ASC_rainSensor}->{LASTGETTIME} )
        && ( gettimeofday() - $self->{ASC_rainSensor}->{LASTGETTIME} ) < 2 );
    $ascDev->_getRainSensor;
    return $self->{ASC_rainSensor}->{shuttersClosedPos};
}

sub getRainWaitingTime {
    my $self = shift;

    my $name = $self->{name};

    return $self->{ASC_rainSensor}->{waitingTime}
      if ( exists( $self->{ASC_rainSensor}->{LASTGETTIME} )
        && ( gettimeofday() - $self->{ASC_rainSensor}->{LASTGETTIME} ) < 2 );
    $ascDev->_getRainSensor;
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
      FHEM::AutoShuttersControl::GetAttrValues( $name, 'ASC_windSensor',
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
    $ascDev->_getWindSensor;
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

1;

=pod
=item device
=item summary       Module for controlling shutters depending on various conditions
=item summary_DE    Modul zur automatischen Rolladensteuerung auf Basis bestimmter Ereignisse


=begin html

<a name="AutoShuttersControl"></a>
<h3>AutoShuttersControl</h3>
<ul>
    <p>
        AutoShuttersControl (<abbr>ASC</abbr>) provides a complete automation for shutters with comprehensive
        configuration options, <abbr>e.g.</abbr> open or close shutters depending on the sunrise or sunset,
        by outdoor brightness or randomly for simulate presence.
        <br /><strong>
        So that ASC can drive the blinds on the basis of the astronomical times, it is very important to
        correctly set the location (latitude, longitude) in the device "global".</strong>
    </p>
    <p>
        After telling <abbr>ASC</abbr> which shutters should be controlled, several in-depth configuration options
        are provided. With these and in combination with a resident presence state, complex scenarios are possible:
        For example, shutters could be opened if a resident awakes from sleep and the sun is already rosen. Or if a
        closed window with shutters down is tilted, the shutters could be half opened for ventilation.
        Many more is possible.
    </p>
    <a name="AutoShuttersControlDefine"></a>
    <strong>Define</strong>
    <ul>
        <p>
            <code>define &lt;name&gt; AutoShuttersControl</code>
        </p>

        Usage:
        <p>
            <ul>
                <code>define myASControl AutoShuttersControl</code><br/>
            </ul>
        </p>
        <p>
            This creates an new AutoShuttersControl device, called <em>myASControl</em>.<br/>
            Now was the new global attribute <var>ASC</var> added to the <abbr>FHEM</abbr> installation.
            Each shutter that is to be controlled by AutoShuttersControl must now have the attribute ASC set to 1 or 2.
            The value 1 is to be used with devices whose state is given as position (i.e. ROLLO or Siro, shutters
            openend is 0, shutters closed is 100), 2 with devices whose state is given as percent closed (i.e. HomeMatic,
            shutters opened is 100, closed is 0).
        </p>
        <p>
            After setting the attributes to all devices who should be controlled, the automatic scan at the main device
            can be started for example with <br/>
            <code>set myASControl scanForShutters</code>
        </p>
    </ul>
    <br/>
    <a name="AutoShuttersControlReadings"></a>
    <strong>Readings</strong>
    <ul>
        <p>Within the ASC device:</p>
        <ul>
            <li><strong>..._nextAstroTimeEvent</strong> - Next astro event: sunrise, sunset or fixed time</li>
            <li><strong>..._PosValue</strong> - current position</li>
            <li><strong>..._lastPosValue</strong> - shutters last position</li>
            <li><strong>..._lastDelayPosValue</strong> - last specified order, will be executed with the next matching
                event
            </li>
            <li><strong>partyMode on|off</strong> - is working mode set to part?y</li>
            <li><strong>ascEnable on|off</strong> - are the associated shutters control by ASC completely?</li>
            <li><strong>controlShading on|off</strong> - are the associated shutters controlled for shading by ASC?
            </li>
            <li><strong>hardLockOut on|off</strong> - switch for preventing a global hard lock out</li>
            <li><strong>room_...</strong> - list of every found shutter for every room: room_Sleeping: Patio</li>
            <li><strong>selfDefense</strong> - state of the self defense mode</li>
            <li><strong>state</strong> - state of the ASC device: active, enabled, disabled or other state information
            </li>
            <li><strong>sunriseTimeWeHoliday on|off</strong> - state of the weekend and holiday support</li>
            <li><strong>userAttrList</strong> - ASC sets some user defined attributes (<abbr><em>userattr</em></abbr>)
                for the shutter devices. This readings shows the current state of the given user attributes to the
                shutter devices.
            </li>
        </ul>

        <p>Within the shutter devices:</p>
        <ul>
            <li><strong>ASC_Enable on|off</strong> - shutter is controlled by ASC or not</li>
            <li><strong>ASC_Time_DriveUp</strong> - if the astro mode is used, the next sunrise is shown.
                If the brightness or time mode is used, the value from <em>ASC_Time_Up_Late</em> is shown.
            </li>
            <li><strong>ASC_Time_DriveDown</strong> - if the astro mode is used, the next sunset is shown.
                If the brightness or time mode is used, the value from <em>ASC_TASC_Time_Down_Lateime_Up_Late</em> is
                shown.
            </li>
            <li><strong>ASC_ShuttersLastDrive</strong> - initiator for the last action</li>
        </ul>
    </ul>
    <br/><br/>
    <a name="AutoShuttersControlSet"></a>
    <strong>Set</strong>
    <ul>
        <li><strong>ascEnable on|off</strong> - enable or disable the global control by ASC</li>
        <li><strong>controlShading on|off</strong> - enable or disable the global shading control by ASC</li>
        <li><strong>createNewNotifyDev</strong> - re-creates the internal structure for NOTIFYDEV. Is only present if
            the
            <em>ASC_Expert</em> attribute is set to 1.
        </li>
        <li><strong>hardLockOut on|off</strong> - <li><strong>hardLockOut - on/off</strong> - Aktiviert den hardwareseitigen Aussperrschutz f&uuml;r die Rolll&auml;den, bei denen das Attributs <em>ASC_LockOut</em> entsprechend auf hard gesetzt ist. Mehr Informationen in der Beschreibung bei den Attributen f&uuml;r die Rollladenger&auml;ten.</li>
        </li>
        <li><strong>partyMode on|off</strong> - controls the global party mode for shutters. Every shutters whose
            <em>ASC_Partymode</em> attribute is set to <em>on</em>, is not longer controlled by ASC. The last saved
            working command send to the device, i.e. by a event, created by a window or presence event, will be executed
            once the party mode is disabled.
        </li>
        <li><strong>renewAllTimer</strong> - resets the sunrise and sunset timers for every associated
            shutter device and creates new internal FHEM timers.
        </li>
        <li><strong>renewTimer</strong> - resets the sunrise and sunset timers for selected shutter
            device and creates new internal FHEM timers.
        </li>
        <li><strong>scanForShutters</strong> - scans the whole FHEM installation for (new) devices whose <em>ASC</em>
            attribute is set (to 1 or 2, see above).
        </li>
        <li><strong>selfDefense on|off</strong> - controls the self defense function. This function listens for
            example on a residents device. If this device is set to <em>absent</em> and a window is still open, ASC will close
            the shutter for a rudimentary burglary protection.
        </li>
        <li><strong>shutterASCenableToggle on|off</strong> - controls if the ASC controls are shown at a associated
            shutter device.
        </li>
        <li><strong>sunriseTimeWeHoliday on|off</strong> - controls the weekend and holiday support. If enabled, the
            <em>ASC_Time_Up_WE_Holiday</em> attribute is considered.
        </li>
        <li><strong>wiggle</strong> - wiggles a device for a given value (default 5%, controlled by
            <em>ASC_WiggleValue</em>) up or down and back after a minute. Useful as a deterrence in combination with
            alarm system.
        </li>
    </ul>
    <br/><br/>
    <a name="AutoShuttersControlGet"></a>
    <strong>Get</strong>
    <ul>
        <li><strong>showNotifyDevsInformations</strong> - shows the generated <em>NOTIFYDEV</em> structure. Useful for
            debugging and only shown if the <em>ASC_expert</em> attribute is set to 1.
        </li>
    </ul>
    <br/><br/>
    <a name="AutoShuttersControlAttributes"></a>
    <strong>Attributes</strong>
    <ul>
        <p>At the global <abbr>ASC</abbr> device:</p>

        <ul>
            <a name="ASC_autoAstroModeEvening"></a>
            <li><strong>ASC_autoAstroModeEvening</strong> - REAL, CIVIL, NAUTIC, ASTRONOMIC or HORIZON</li>
            <a name="ASC_autoAstroModeEveningHorizon"></a>
            <li><strong>ASC_autoAstroModeEveningHorizon</strong> - Height above the horizon. Is only considered
                if the <em>ASC_autoAstroModeEvening</em> attribute is set to <em>HORIZON</em>. Defaults to <em>0</em>.
            </li>
            <a name="ASC_autoAstroModeMorning"></a>
            <li><strong>ASC_autoAstroModeMorning</strong> - REAL, CIVIL, NAUTIC, ASTRONOMIC or HORIZON</li>
            <a name="ASC_autoAstroModeMorningHorizon"></a>
            <li><strong>ASC_autoAstroModeMorningHorizon</strong> - Height above the horizon. Is only considered
                if the <em>ASC_autoAstroModeMorning</em> attribute is set to <em>HORIZON</em>. Defaults to <em>0</em>.
            </li>
            <a name="ASC_autoShuttersControlComfort"></a>
            <li><strong>ASC_autoShuttersControlComfort - on|off</strong> -
                Controls the comfort functions: If a three state sensor, like the <abbr>HmIP-SRH</abbr> window handle
                sensor, is installed, <abbr>ASC</abbr> will open the window if the sensor signals open position. The
                <em>ASC_ComfortOpen_Pos</em> attribute has to be set for the shutter to <em>on</em>, defaults to <em>off</em>.
            </li>
            <a name="ASC_autoShuttersControlEvening"></a>
            <li><strong>ASC_autoShuttersControlEvening - on|off</strong> - Enables the automatic control by <abbr>ASC</abbr>
                at the evenings.
            </li>
            <a name="ASC_autoShuttersControlMorning"></a>
            <li><strong>ASC_autoShuttersControlMorning - on|off</strong> - Enables the automatic control by <abbr>ASC</abbr>
                at the mornings.
            </li>
            <a name="ASC_blockAscDrivesAfterManual"></a>
            <li><strong>ASC_blockAscDrivesAfterManual 0|1</strong> - If set to <em>1</em>, <abbr>ASC</abbr> will not
                automatically control a shutter if there was an manual control to the shutter. To be considered, the
                <em>ASC_ShuttersLastDrive</em> reading has to contain the value <em>manual</em> and the shutter is in
                an unknown (i.e. not otherwise configured in <abbr>ASC</abbr>) position.
            </li>
            <a name="ASC_brightnessDriveUpDown"></a>
            <li><strong>ASC_brightnessDriveUpDown - VALUE-MORNING:VALUE-EVENING</strong> - Drive the shutters by
                brightness. <em>VALUE-MORNING</em> sets the brightness threshold for the morning. If the value is
                reached in the morning, the shutter will go up. Vice versa in the evening. This is a global setting
                and can be overwritte per device with the <em>ASC_BrightnessSensor</em> attribute (see below).
            </li>
            <a name="ASC_debug"></a>
            <li><strong>ASC_debug</strong> -
                Extendend logging for debugging purposes
            </li>
            <a name="ASC_expert"></a>
            <li><strong>ASC_expert</strong> - Switches the export mode on. Currently, if set to <em>1</em>, <em>get</em>
                and <em>set</em> will contain additional functions regarding the NOTIFYDEFs.
            </li>
            <a name="ASC_freezeTemp"></a>
            <li><strong>ASC_freezeTemp</strong> - Temperature threshold for the freeze protection. The freeze protection
                prevents the shutter to be operated by <abbr>ASC</abbr>. Last operating order will be kept.
            </li>
            <a name="ASC_rainSensor"></a>
            <li><strong>ASC_rainSensor DEVICENAME[:READINGNAME] MAXTRIGGER[:HYSTERESE] [CLOSEDPOS]</strong> - Contains
                settings for the rain protection. <em>DEVICNAME</em> specifies a rain sensor, the optional
                <em>READINGNAME</em> the name of the reading at the <em>DEVICENAME</em>. The <em>READINGNAME</em>
                should contain the values <em>rain</em> and <em>dry</em> or a numeral rain amount. <em>MAXTRIGGER</em>
                sets the threshold for the amount of rain for when the shutter is driven to <em>CLOSEDPOS</em> as soon
                the threshold is reached. <em>HYSTERESE</em> sets a hysteresis for <em>MAXTRIGGER</em>.
            </li>
            <a name="ASC_residentsDev"></a>
            <li><strong>ASC_residentsDev DEVICENAME[:READINGNAME]</strong> - <em>DEVICENAME</em> points to a device
                for presence, e.g. of type <em>RESIDENTS</em>. <em>READINGNAME</em> points to a reading at
                <em>DEVICENAME</em> which contains a presence state, e.g. <em>rgr_Residents:state</em>. The target
                should contain values alike the <em>RESIDENTS</em> family.
            </li>
            <a name="ASC_shuttersDriveDelay"></a>
            <li><strong>ASC_shuttersDriveDelay</strong> - Maximum random drive delay in seconds for calculating
                the operating time. <em>0</em> equals to no delay.
            </li>
            <a name="ASC_tempSensor"></a>
            <li><strong>ASC_tempSensor DEVICENAME[:READINGNAME]</strong> - <em>DEVICENAME</em> points to a device
                with a temperature, <em>READINGNAME</em> to a reading located at the <em>DEVICENAME</em>, for example
                <em>OUTDOOR_TEMP:measured-temp</em>. <em>READINGNAME</em> defaults to <em>temperature</em>.
            </li>
            <a name="ASC_twilightDevice"></a>
            <li><strong>ASC_twilightDevice</strong> - points to a <em>DEVICENAME</em> containing values regarding
                the sun position. Supports currently devices of type <em>Twilight</em> or <em>Astro</em>.
            </li>
            <a name="ASC_windSensor"></a>
            <li><strong>ASC_windSensor DEVICENAME[:READINGNAME]</strong> - <em>DEVICENAME</em> points to a device
                containing a wind speed. Reads from the <em>wind</em> reading, if not otherwise specified by
                <em>READINGNAME</em>.
            </li>
        </ul>
        <br/>
        <p>At shutter devices, controlled by <abbr>ASC</abbr>:</p>
        <ul>
            <li><strong>ASC - 0|1|2</strong>
                <ul>
                    <li>0 - don't create attributes for <abbr>ASC</abbr> at the first scan and don't be controlled
                    by <abbr>ASC</abbr></li>
                    <li>1 - inverse or venetian type blind mode. Shutter is open equals to 0, shutter is closed equals
                    to 100, is controlled by <em>position</em> values.</li>
                    <li>2 - <q>HomeMatic</q> mode. Shutter is open equals to 100, shutter is closed equals to 0, is
                    controlled by <em><abbr>pct</abbr></em> values.</li>
                </ul>
            </li>
            <li><strong>ASC_Antifreeze - soft|am|pm|hard|off</strong> - Freeze protection.
                <ul>
                    <li>soft - see <em>ASC_Antifreeze_Pos</em>.</li>
                    <li>hard / <abbr>am</abbr> / <abbr>pm</abbr> - freeze protection will be active (everytime,
                    ante meridiem or post meridiem).</li>
                    <li>off - freeze protection is disabled, default value</li>
                </ul>
            </li>
            <li><strong>ASC_Antifreeze_Pos</strong> - Position to be operated if the shutter should be closed,
                but <em>ASC_Antifreeze</em> is not set to <em>off</em>. (Default: dependent on attribut<em>ASC</em> 85/15).
            </li>
            <li><strong>ASC_AutoAstroModeEvening</strong> - Can be set to <em>REAL</em>, <em>CIVIL</em>,
                <em>NAUTIC</em>, <em>ASTRONOMIC</em> or <em>HORIZON</em>. Defaults to none of those.</li>
            <li><strong>ASC_AutoAstroModeEveningHorizon</strong> - If this value is reached by the sun, a sunset is
                presumed. Is used if <em>ASC_autoAstroModeEvening</em> is set to <em>HORIZON</em>. Defaults to none.
            </li>
            <li><strong>ASC_AutoAstroModeMorning</strong> - Can be set to <em>REAL</em>, <em>CIVIL</em>,
                <em>NAUTIC</em>, <em>ASTRONOMIC</em> or <em>HORIZON</em>. Defaults to none of those.</li>
            <li><strong>ASC_AutoAstroModeMorningHorizon</strong> - If this value is reached by the sun, a sunrise is
                presumed. Is used if <em>ASC_AutoAstroModeMorning</em> is set to <em>HORIZON</em>. Defaults to none.
            </li>
            <li><strong>ASC_Shutter_IdleDetection</strong> - indicates the Reading which gives information about the running status of the roller blind, as well as secondly the value in the Reading which says that the roller blind does not run.
            </li>
            <li><strong>ASC_BlockingTime_afterManual</strong> - Time in which operations by <abbr>ASC</abbr> are blocked
                after the last manual operation in seconds. Defaults to 1200 (20 minutes).
            </li>
            <li><strong>ASC_BlockingTime_beforDayOpen</strong> - Time in which no closing operation is made by
                <abbr>ASC</abbr> after opening at the morning in seconds. Defaults to 3600 (one hour).
            </li>
            <li><strong>ASC_BlockingTime_beforNightClose</strong> - Time in which no closing operation is made by
                <abbr>ASC</abbr> before closing at the evening in seconds. Defaults to 3600 (one hour).
            </li>
            <li><strong>ASC_BrightnessSensor - DEVICE[:READING] MORNING-VALUE:EVENING-VALUE</strong> -
                Drive this shutter by brightness. <em>MORNING-VALUE</em> sets the brightness threshold for the morning.
                If the value is reached in the morning, the shutter will go up. Vice versa in the evening, specified by
                <em>EVENING-VALUE</em>. Gets the brightness from <em>DEVICE</em>, reads by default from the
                <em>brightness</em> reading, unless <em>READING</em> is specified. Defaults to <em>none</em>.
            </li>
            <li><strong>ASC_Closed_Pos</strong> - The closed position value from 0 to 100 percent in increments of 10.
                (Default: dependent on attribut<em>ASC</em> 100/0).
            </li>
            <li><strong>ASC_ComfortOpen_Pos</strong> - The comfort opening position, ranging
                from 0 to 100 percent in increments of 10. (Default: dependent on attribut<em>ASC</em> 20/80).
            </li>
            <li><strong>ASC_Down - astro|time|brightness|roommate</strong> - Drive the shutter depending on this setting:
                <ul>
                    <li>astro - drive down at sunset</li>
                    <li>time - drive at <em>ASC_Time_Down_Early</em></li>
                    <li>brightness - drive between <em>ASC_Time_Down_Early</em> and <em>ASC_Time_Down_Late</em>,
                        depending on the settings of <em>ASC_BrightnessSensor</em> (see above).</li>
                    <li>roommate - no drive by time or brightness, roommate trigger only</li>
                </ul>
                Defaults to <em>astro</em>.
            </li>
            <li><strong>ASC_DriveUpMaxDuration</strong> - Drive up duration of the shutter plus 5 seconds. Defaults
                to 60 seconds if not set.
            </li>
            <li><strong>ASC_LockOut soft|hard|off</strong> - Configures the lock out protection for the current
                shutter. Values are:
                <ul>
                    <li>soft - works if the global lock out protection <em>lockOut soft</em> is set and a sensor
                        specified by <em>ASC_WindowRec</em> is set. If the sensor is set to open, the shutter will not
                        be closed. Affects only commands issued by <abbr>ASC</abbr>.
                    </li>
                    <li>
                        hard - see soft, but <abbr>ASC</abbr> tries also to block manual issued commands by a switch.
                    </li>
                    <li>
                        off - lock out protection is disabled. Default.
                    </li>
                </ul>
            </li>
            <li><strong>ASC_LockOut_Cmd inhibit|blocked|protection</strong> - Configures the lock out command for
                <em>ASC_LockOut</em> if hard is chosen as a value. Defaults to none.
            </li>
            <li><strong>ASC_Mode_Down always|home|absent|off</strong> - When will a shutter be driven down:
                <ul>
                    <li>always - <abbr>ASC</abbr> will drive always. Default value.</li>
                    <li>off - don't drive</li>
                    <li>home / absent - considers a residents status set by <em>ASC_residentsDev</em>. If no
                    resident is configured and this attribute is set to absent, <abbr>ASC</abbr> will not
                    operate the shutter.</li>
                </ul>
            </li>
            <li><strong>ASC_Mode_Up always|home|absent|off</strong> - When will a shutter be driven up:
                <ul>
                    <li>always - <abbr>ASC</abbr> will drive always. Default value.</li>
                    <li>off - don't drive</li>
                    <li>home / absent - considers a residents status set by <em>ASC_residentsDev</em>. If no
                        resident is configured and this attribute is set to absent, <abbr>ASC</abbr> will not
                        operate the shutter.</li>
                </ul>
            </li>
            <li><strong>ASC_Open_Pos</strong> - The opening position value from 0 to 100 percent in increments of 10.
                (Default: dependent on attribut<em>ASC</em> 0/100).
            </li>
            <li><strong>ASC_Sleep_Pos</strong> - The opening position value from 0 to 100 percent in increments of 10.
                (Default: dependent on attribut<em>ASC</em> 75/25).
            </li>
            <li><strong>ASC_Partymode on|off</strong> - Party mode. If configured to on, driving orders for the
                shutter by <abbr>ASC</abbr> will be queued if <em>partyMode</em> is set to <em>on</em> at the
                global <abbr>ASC</abbr> device. Will execute the driving orders after <em>partyMode</em> is disabled.
                Defaults to off.
            </li>
            <li><strong>ASC_Pos_Reading</strong> - Points to the reading name, which contains the current
                position for the shutter in percent. Will be used for <em>set</em> at devices of unknown kind.
            </li>
            <li><strong>ASC_PrivacyDownValue_beforeNightClose</strong> - How many seconds is the privacy mode activated
                before the shutter is closed in the evening. For Brightness, in addition to the time value,
                the Brightness value must also be specified. 1800:300 means 30 min before night close or above a brightness
                value of 300. -1 is the default
                value.
            </li>
            <li><strong>ASC_PrivacyDown_Pos</strong> -
                Position in percent for privacy mode, defaults to 50.
            </li>
            <li><strong>ASC_PrivacyUpValue_beforeDayOpen</strong> - How many seconds is the privacy mode activated
                before the shutter is open in the morning. For Brightness, in addition to the time value,
                the Brightness value must also be specified. 1800:600 means 30 min before day open or above a brightness
                value of 600. -1 is the default
                value.
            </li>
            <li><strong>ASC_PrivacyUp_Pos</strong> -
                Position in percent for privacy mode, defaults to 50.
            </li>
            <li><strong>ASC_WindProtection on|off</strong> - Shutter is protected by the wind protection. Defaults
                to off.
            </li>
            <li><strong>ASC_RainProtection on|off</strong> - Shutter is protected by the rain protection. Defaults
                to off.
            </li>
            <li><strong>ASC_Roommate_Device</strong> - Comma separated list of <em>ROOMMATE</em> devices, representing
                the inhabitants of the room to which the shutter belongs. Especially useful for bedrooms. Defaults
                to none.
            </li>
            <li><strong>ASC_Roommate_Reading</strong> - Specifies a reading name to <em>ASC_Roommate_Device</em>.
                Defaults to <em>state</em>.
            </li>
            <li><strong>ASC_Self_Defense_Mode - absent/gone/off</strong> - which Residents status Self Defense should become 
                active without the window being open. (default: gone) off exclude from self defense
            </li>
            <li><strong>ASC_Self_Defense_AbsentDelay</strong> - um wie viele Sekunden soll das fahren in Selfdefense bei
                Residents absent verz&ouml;gert werden. (default: 300)
            </li>
            <li><strong>ASC_ShuttersPlace window|terrace</strong> - If set to <em>terrace</em>, and the
                residents device is set to <em>gone</em>, and <em>selfDefense</em> is activated, the shutter will
                be closed. If set to window, will not. Defaults to window.
            </li>
            <li><strong>ASC_Time_Down_Early</strong> - Will not drive before time is <em>ASC_Time_Down_Early</em>
                or later, even the sunset occurs earlier. To be set in military time. Defaults to 16:00.
            </li>
            <li><strong>ASC_Time_Down_Late</strong> - Will not drive after time is <em>ASC_Time_Down_Late</em>
                or earlier, even the sunset occurs later. To be set in military time. Defaults to 22:00.
            </li>
            <li><strong>ASC_Time_Up_Early</strong> - Will not drive before time is <em>ASC_Time_Up_Early</em>
                or earlier, even the sunrise occurs earlier. To be set in military time. Defaults to 05:00.
            </li>
            <li><strong>ASC_Time_Up_Late</strong> - Will not drive after time is <em>ASC_Time_Up_Late</em>
                or earlier, even the sunrise occurs later. To be set in military time. Defaults to 08:30.
            </li>
            <li><strong>ASC_Time_Up_WE_Holiday</strong> - Will not drive before time is <em>ASC_Time_Up_WE_Holiday</em>
                on weekends and holidays (<em>holiday2we</em> is considered). Defaults to 08:00. <strong>Warning!</strong>
                If <em>ASC_Up</em> set to <em>brightness</em>, the time for <em>ASC_Time_Up_WE_Holiday</em>
                must be earlier then <em>ASC_Time_Up_Late</em>.
            </li>
            <li><strong>ASC_Up astro|time|brightness|roommate</strong> - Drive the shutter depending on this setting:
                <ul>
                    <li>astro - drive up at sunrise</li>
                    <li>time - drive at <em>ASC_Time_Up_Early</em></li>
                    <li>brightness - drive between <em>ASC_Time_Up_Early</em> and <em>ASC_Time_Up_Late</em>,
                        depending on the settings of <em>ASC_BrightnessSensor</em> (see above).</li>
                    <li>roommate - no drive by time or brightness, roommate trigger only</li>
                </ul>
                Defaults to <em>astro</em>.
            </li>
            <li><strong>ASC_Ventilate_Pos</strong> - The opening position value for ventilation
                from 0 to 100 percent in increments of 10. (Default: dependent on attribut<em>ASC</em> 70/30).
            </li>
            <li><strong>ASC_Ventilate_Window_Open on|off</strong> - Drive to ventilation position as window is opened
                or tilted, even when the current shutter position is lower than the <em>ASC_Ventilate_Pos</em>.
                Defaults to on.
            </li>
            <li><strong>ASC_WiggleValue</strong> - How many percent should the shutter be driven if a wiggle drive
                is operated. Defaults to 5.
            </li>
            <li><strong>ASC_WindParameters THRESHOLD-ON[:THRESHOLD-OFF] [DRIVEPOSITION]</strong> -
                Threshold for when the shutter is driven to the wind protection position. Optional
                <em>THRESHOLD-OFF</em> sets the complementary value when the wind protection is disabled. Disabled
                if <em>THRESHOLD-ON</em> is set to -1. Defaults to <q>50:20 <em>ASC_Closed_Pos</em></q>.
            </li>
            <li><strong>ASC_WindowRec</strong> - WINDOWREC:[READING], Points to the window contact device, associated with the shutter.
                Defaults to none. Reading is optional
            </li>
            <li><strong>ASC_WindowRec_subType</strong> - Model type of the used <em>ASC_WindowRec</em>:
                <ul>
                    <li><strong>twostate</strong> - optical or magnetical sensors with two states: opened or closed</li>
                    <li><strong>threestate</strong> - sensors with three states: opened, tilted, closed</li>
                </ul>
                Defaults to twostate.
            </li>
            <li><strong>ASC_WindowRec_PosAfterDayClosed</strong> - open,lastManual / auf welche Position soll das Rollo nach dem schlie&szlig;en am Tag fahren. Open Position oder letzte gespeicherte manuelle Position (default: open)</li>
            <blockquote>
                <p>
                    <strong><u>Shading</u></strong>
                </p>
                <p>
                    Shading is only available if the following prerequests are met:
                <ul>
                    <li>
                        The <em>controlShading</em> reading is set to on, and there is a device
                        of type Astro or Twilight configured to <em>ASC_twilightDevice</em>, and <em>ASC_tempSensor</em>
                        is set.
                    </li>
                    <li>
                        <em>ASC_BrightnessSensor</em> is configured to any shutter device.
                    </li>
                    <li>
                        All other attributes are optional and the default value for them is used, if they are not
                        otherwise configured. Please review the settings carefully, especially the values for
                        <em>StateChange_Cloudy</em> and <em>StateChange_Sunny</em>.
                    </li>
                </ul>
                </p>
                <p>
                    The following attributes are available:
                </p>
                <ul>
                    <li><strong>ASC_Shading_InOutAzimuth</strong> - Azimuth value from which shading is to be used when shading is exceeded and shading when undershooting is required.
                        Defaults to 95:265.
                    </li>
                    <li><strong>ASC_Shading_MinMax_Elevation</strong> - Shading starts as min point of sun elevation is
                        reached and end as max point of sun elevation is reached, depending also on other sensor values. Defaults to 25.0:100.0.
                    </li>
                    <li><strong>ASC_Shading_Min_OutsideTemperature</strong> - Shading starts at this outdoor temperature,
                        depending also on other sensor values. Defaults to 18.0.
                    </li>
                    <li><strong>ASC_Shading_Mode absent|always|off|home</strong> - see <em>ASC_Mode_Down</em> above,
                        but for shading. Defaults to off.
                    </li>
                    <li><strong>ASC_Shading_Pos</strong> - Shading position in percent. (Default: dependent on attribut<em>ASC</em> 85/15)</li>
                    <li><strong>ASC_Shading_StateChange_Cloudy</strong> - Shading <strong>ends</strong> at this
                        outdoor brightness, depending also on other sensor values. Defaults to 20000.
                    </li>
                    <li><strong>ASC_Shading_StateChange_SunnyCloudy</strong> - Shading <strong>starts/stops</strong> at this
                        outdoor brightness, depending also on other sensor values. A optional parameter set the maximal object in brightness average array. Defaults to 35000:20000 [3].
                    </li>
                    <li><strong>ASC_Shading_WaitingPeriod</strong> - Waiting time in seconds before additional sensor values
                        to <em>ASC_Shading_StateChange_Sunny</em> or <em>ASC_Shading_StateChange_Cloudy</em>
                        are used for shading. Defaults to 120.
                    </li>
                </ul>
            </blockquote>
        </ul>
    </ul>
    <p>
        <strong><u>AutoShuttersControl <abbr>API</abbr> description</u></strong>
    </p>
    <p>
        It's possible to access internal data of the <abbr>ASC</abbr> module by calling the <abbr>API</abbr> function.
    </p>
    <u>Data points of a shutter device, controlled by <abbr>ASC</abbr></u>
    <p>
        <pre><code>{ ascAPIget('Getter','SHUTTERS_DEVICENAME') }</code></pre>
    </p>
    <table>
        <tr>
            <th>Getter</th>
            <th>Description</th>
        </tr>
        <tr>
            <td>FreezeStatus</td>
            <td>1 = soft, 2 = daytime, 3 = hard</td>
        </tr>
        <tr>
            <td>NoDelay</td>
            <td>Was the offset handling deactivated (e.g. by operations triggered by a window event)</td>
        </tr>
        <tr>
            <td>LastDrive</td>
            <td>Reason for the last action caused by <abbr>ASC</abbr></td>
        </tr>
        <tr>
            <td>LastPos</td>
            <td>Last position of the shutter</td>
        </tr>
        <tr>
            <td>LastPosTimestamp</td>
            <td>Timestamp of the last position</td>
        </tr>
        <tr>
            <td>LastManPos</td>
            <td>Last position manually set of the shutter</td>
        </tr>
        <tr>
            <td>LastManPosTimestamp</td>
            <td>Timestamp of the last position manually set</td>
        </tr>
        <tr>
            <td>SunsetUnixTime</td>
            <td>Calculated sunset time in seconds since the <abbr>UNIX</abbr> epoche</td>
        </tr>
        <tr>
            <td>Sunset</td>
            <td>1 = operation in the evening was made, 0 = operation in the evening was not yet made</td>
        </tr>
        <tr>
            <td>SunriseUnixTime</td>
            <td>Calculated sunrise time in seconds since the <abbr>UNIX</abbr> epoche</td>
        </tr>
        <tr>
            <td>Sunrise</td>
            <td>1 = operation in the morning was made, 0 = operation in the morning was not yet made</td>
        </tr>
        <tr>
            <td>RoommatesStatus</td>
            <td>Current state of the room mate set for this shutter</td>
        </tr>
        <tr>
            <td>RoommatesLastStatus</td>
            <td>Last state of the room mate set for this shutter</td>
        </tr>
        <tr>
            <td>ShadingStatus</td>
            <td>Value of the current shading state. Can hold <em>in</em>, <em>out</em>, <em>in reserved</em> or
                <em>out reserved</em></td>
        </tr>
        <tr>
            <td>ShadingStatusTimestamp</td>
            <td>Timestamp of the last shading state</td>
        </tr>
        <tr>
            <td>IfInShading</td>
            <td>Is the shutter currently in shading (depends on the shading mode)</td>
        </tr>
        <tr>
            <td>WindProtectionStatus</td>
            <td>Current state of the wind protection. Can hold <em>protection</em> or <em>unprotection</em></td>
        </tr>
        <tr>
            <td>RainProtectionStatus</td>
            <td>Current state of the rain protection. Can hold <em>protection</em> or <em>unprotection</em></td>
        </tr>
        <tr>
            <td>DelayCmd</td>
            <td>Last operation order in the waiting queue. Set for example by the party mode</td>
        </tr>
        <tr>
            <td>Status</td>
            <td>Position of the shutter</td>
        </tr>
        <tr>
            <td>ASCenable</td>
            <td>Does <abbr>ASC</abbr> control the shutter?</td>
        </tr>
        <tr>
            <td>PrivacyDownStatus</td>
            <td>Is the shutter currently in privacyDown mode</td>
        </tr>
        <tr>
            <td>outTemp</td>
            <td>Current temperature of a configured temperature device, return -100 is no device configured</td>
        </tr>
    </table>
    </p>
    <u>&Uuml;bersicht f&uuml;r das Rollladen-Device mit Parameter&uuml;bergabe</u>
    <ul>
        <code>{ ascAPIget('Getter','ROLLODEVICENAME',VALUE) }</code><br>
    </ul>
    <table>
        <tr>
            <th>Getter</th><th>Erl&auml;uterung</th>
        </tr>
        <tr>
            <td>QueryShuttersPos</td><td>R&uuml;ckgabewert 1 bedeutet das die aktuelle Position des Rollos unterhalb der Valueposition ist. 0 oder nichts bedeutet oberhalb der Valueposition.</td>
        </tr>
    </table>
    </p>
    <u>Data points of the <abbr>ASC</abbr> device</u>
        <p>
            <code>{ ascAPIget('Getter') }</code><br>
        </p>
        <table>
            <tr>
                <th>Getter</th>
                <th>Description</th>
            </tr>
            <tr>
                <td>OutTemp</td>
                <td>Current temperature of a configured temperature device, return -100 is no device configured</td>
            </tr>
            <tr>
                <td>ResidentsStatus</td>
                <td>Current state of a configured resident device</td>
            </tr>
            <tr>
                <td>ResidentsLastStatus</td>
                <td>Last state of a configured resident device</td>
            </tr>
            <tr>
                <td>Azimuth</td>
                <td>Current azimuth of the sun</td>
            </tr>
            <tr>
                <td>Elevation</td>
                <td>Current elevation of the sun</td>
            </tr>
            <tr>
                <td>ASCenable</td>
                <td>Is <abbr>ASC</abbr> globally activated?</td>
            </tr>
        </table>
</ul>

=end html

=begin html_DE

<a name="AutoShuttersControl"></a>
<h3>AutoShuttersControl</h3>
<ul>
    <p>AutoShuttersControl (ASC) erm&ouml;glicht eine vollst&auml;ndige Automatisierung der vorhandenen Rolll&auml;den. Das Modul bietet umfangreiche Konfigurationsm&ouml;glichkeiten, um Rolll&auml;den bspw. nach Sonnenauf- und untergangszeiten, nach Helligkeitswerten oder rein zeitgesteuert zu steuern.
    <br /><strong>Damit ASC auf Basis der astronomischen Zeiten die Rollos fahren kann, ist es ganz wichtig im Device "global" die Location (Latitude,Longitude) korrekt zu setzen.</strong>
    </p>
    <p>
        Man kann festlegen, welche Rolll&auml;den von ASC in die Automatisierung mit aufgenommen werden sollen. Daraufhin stehen diverse Attribute zur Feinkonfiguration zur Verf&uuml;gung. So sind unter anderem komplexe L&ouml;sungen wie Fahrten in Abh&auml;ngigkeit des Bewohnerstatus einfach umsetzbar. Beispiel: Hochfahren von Rolll&auml;den, wenn der Bewohner erwacht ist und drau&szlig;en bereits die Sonne aufgegangen ist. Weiterhin ist es m&ouml;glich, dass der geschlossene Rollladen z.B. nach dem Ankippen eines Fensters in eine L&uuml;ftungsposition f&auml;hrt. Und vieles mehr.
    </p>
    <a name="AutoShuttersControlDefine"></a>
    <strong>Define</strong>
    <ul>
        <code>define &lt;name&gt; AutoShuttersControl</code>
        <br /><br />
        Beispiel:
        <ul>
            <br />
            <code>define myASControl AutoShuttersControl</code><br />
        </ul>
        <br />
        Der Befehl erstellt ein AutoShuttersControl Device mit Namen <em>myASControl</em>.<br />
        Nachdem das Device angelegt wurde, muss in allen Rolll&auml;den Devices, welche gesteuert werden sollen, das Attribut ASC mit Wert 1 oder 2 gesetzt werden.
        Dabei bedeutet 1 = "Prozent geschlossen" (z.B. ROLLO oder Siro Modul) - Rollo Oben 0, Rollo Unten 100, 2 = "Prozent ge&ouml;ffnet" (z.B. Homematic) - Rollo Oben 100, Rollo Unten 0.
        Die Voreinstellung f&uuml;r den Befehl zum prozentualen Fahren ist in beiden F&auml;llen unterschiedlich. 1="position" und 2="pct". Dies kann, soweit erforderlich, zu sp&auml;terer Zeit noch angepasst werden.
        Habt Ihr das Attribut gesetzt, k&ouml;nnt Ihr den automatischen Scan nach den Devices ansto&szlig;en.
    </ul>
    <br />
    <a name="AutoShuttersControlReadings"></a>
    <strong>Readings</strong>
    <ul>
        <u>Im ASC-Device</u>
        <ul>
            <li><strong>..._nextAstroTimeEvent</strong> - Uhrzeit des n&auml;chsten Astro-Events: Sonnenauf- oder Sonnenuntergang oder feste Zeit</li>
            <li><strong>..._PosValue</strong> - aktuelle Position des Rollladens</li>
            <li><strong>..._lastPosValue</strong> - letzte Position des Rollladens</li>
            <li><strong>..._lastDelayPosValue</strong> - letzter abgesetzter Fahrbefehl, welcher beim n&auml;chsten zul&auml;ssigen Event ausgef&uuml;hrt wird.</li>
            <li><strong>partyMode - on/off</strong> - Partymodus-Status</li>
            <li><strong>ascEnable - on/off</strong> - globale ASC Steuerung bei den Rollläden aktiv oder inaktiv</li>
            <li><strong>controlShading - on/off</strong> - globale Beschattungsfunktion aktiv oder inaktiv</li>
            <li><strong>hardLockOut - on/off</strong> - Status des hardwareseitigen Aussperrschutzes / gilt nur f&uuml;r Roll&auml;den mit dem Attribut bei denen das Attributs <em>ASC_LockOut</em> entsprechend auf hard gesetzt ist</li>
            <li><strong>room_...</strong> - Auflistung aller Rolll&auml;den, die in den jeweiligen R&auml;men gefunden wurde. Beispiel: room_Schlafzimmer: Terrasse</li>
            <li><strong>selfDefense</strong> - Selbstschutz-Status</li>
            <li><strong>state</strong> - Status des ASC-Devices: active, enabled, disabled oder weitere Statusinformationen</li>
            <li><strong>sunriseTimeWeHoliday - on/off</strong> - Status der Wochenendunterst&uuml;tzung</li>
            <li><strong>userAttrList</strong> - Das ASC-Modul verteilt an die gesteuerten Rollladen-Geräte diverse Benutzerattribute <em>(userattr)</em>. In diesem Reading kann der Status dieser Verteilung gepr&uuml;ft werden.</li>
        </ul><br />
        <u>In den Rolll&auml;den-Ger&auml;ten</u>
        <ul>
            <li><strong>ASC_Enable - on/off</strong> - wird der Rollladen &uuml;ber ASC gesteuert oder nicht</li>
            <li><strong>ASC_Time_DriveUp</strong> - Im Astro-Modus ist hier die Sonnenaufgangszeit f&uuml;r das Rollo gespeichert. Im Brightnessmodus ist hier der Zeitpunkt aus dem Attribut <em>ASC_Time_Up_Late</em> gespeichert. Im Timemodus ist hier der Zeitpunkt aus dem Attribut <em>ASC_Time_Up_Early</em> gespeichert.</li>
            <li><strong>ASC_Time_DriveDown</strong>  - Im Astro-Modus ist hier die Sonnenuntergangszeit f&uuml;r das Rollo gespeichert. Im Brightnessmodus ist hier der Zeitpunkt aus dem Attribut <em>ASC_Time_Down_Late</em> gespeichert. Im Timemodus ist hier der Zeitpunkt aus dem Attribut <em>ASC_Time_Down_Early</em> gespeichert.</li>
            <li><strong>ASC_ShuttersLastDrive</strong>  - Grund der letzten Fahrt vom Rollladen</li>
        </ul>
    </ul>
    <br /><br />
    <a name="AutoShuttersControlSet"></a>
    <strong>Set</strong>
    <ul>
        <li><strong>advDriveDown</strong> - holt bei allen Rolll&auml;den durch ASC_Adv on ausgesetzte Fahrten nach.</li>
        <li><strong>ascEnable - on/off</strong> - Aktivieren oder deaktivieren der globalen ASC Steuerung</li>
        <li><strong>controlShading - on/off</strong> - Aktiviert oder deaktiviert die globale Beschattungssteuerung</li>
        <li><strong>createNewNotifyDev</strong> - Legt die interne Struktur f&uuml;r NOTIFYDEV neu an. Diese Funktion steht nur zur Verf&uuml;gung, wenn Attribut ASC_expert auf 1 gesetzt ist.</li>
        <li><strong>hardLockOut - on/off</strong> - Aktiviert den hardwareseitigen Aussperrschutz f&uuml;r die Rolll&auml;den, bei denen das Attributs <em>ASC_LockOut</em> entsprechend auf hard gesetzt ist. Mehr Informationen in der Beschreibung bei den Attributen f&uuml;r die Rollladenger&auml;ten.</li>
        <li><strong>partyMode - on/off</strong> - Aktiviert den globalen Partymodus. Alle Rollladen-Ger&auml;ten, in welchen das Attribut <em>ASC_Partymode</em> auf <em>on</em> gesetzt ist, werden durch ASC nicht mehr gesteuert. Der letzte Schaltbefehl, der bspw. durch ein Fensterevent oder Wechsel des Bewohnerstatus an die Rolll&auml;den gesendet wurde, wird beim Deaktivieren des Partymodus ausgef&uuml;hrt</li>
        <li><strong>renewTimer</strong> - erneuert beim ausgew&auml;hlten Rollladen die Zeiten f&uuml;r Sonnenauf- und -untergang und setzt die internen Timer neu.</li>
        <li><strong>renewAllTimer</strong> - erneuert bei allen Rolll&auml;den die Zeiten f&uuml;r Sonnenauf- und -untergang und setzt die internen Timer neu.</li>
        <li><strong>scanForShutters</strong> - Durchsucht das System nach Ger&auml;tenRo mit dem Attribut <em>ASC = 1</em> oder <em>ASC = 2</em></li>
        <li><strong>selfDefense - on/off</strong> - Aktiviert bzw. deaktiviert die Selbstschutzfunktion. Beispiel: Wenn das Residents-Ger&auml;t <em>absent</em> meldet, die Selbstschutzfunktion aktiviert wurde und ein Fenster im Haus noch ge&ouml;ffnet ist, so wird an diesem Fenster der Rollladen deaktivieren dann heruntergefahren.</li>
        <li><strong>shutterASCenableToggle - on/off</strong> - Aktivieren oder deaktivieren der ASC Kontrolle beim einzelnen Rollladens</li>
        <li><strong>sunriseTimeWeHoliday - on/off</strong> - Aktiviert die Wochenendunterst&uuml;tzung und somit, ob im Rollladenger&auml;t das Attribut <em>ASC_Time_Up_WE_Holiday</em> beachtet werden soll oder nicht.</li>
        <li><strong>wiggle</strong> - bewegt einen oder mehrere Rolll&auml;den um einen definierten Wert (Default: 5%) und nach einer Minute wieder zur&uuml;ck in die Ursprungsposition. Diese Funktion k&ouml;nnte bspw. zur Abschreckung in einem Alarmsystem eingesetzt werden.</li>
    </ul>
    <br /><br />
    <a name="AutoShuttersControlGet"></a>
    <strong>Get</strong>
    <ul>
        <li><strong>showNotifyDevsInformations</strong> - zeigt eine &Uuml;bersicht der abgelegten NOTIFYDEV Struktur. Diese Funktion wird prim&auml;r f&uuml;rs Debugging genutzt. Hierzu ist das Attribut <em>ASC_expert = 1</em> zu setzen.</li>
    </ul>
    <br /><br />
    <a name="AutoShuttersControlAttributes"></a>
    <strong>Attributes</strong>
    <ul>
        <u>Im ASC-Device</u>
        <ul>
            <a name="ASC_autoAstroModeEvening"></a>
            <li><strong>ASC_autoAstroModeEvening</strong> - REAL, CIVIL, NAUTIC, ASTRONOMIC oder HORIZON</li>
            <a name="ASC_autoAstroModeEveningHorizon"></a>
            <li><strong>ASC_autoAstroModeEveningHorizon</strong> - H&ouml;he &uuml;ber dem Horizont. Wird nur ber&uuml;cksichtigt, wenn im Attribut <em>ASC_autoAstroModeEvening</em> der Wert <em>HORIZON</em> ausgew&auml;hlt wurde. (default: 0)</li>
            <a name="ASC_autoAstroModeMorning"></a>
            <li><strong>ASC_autoAstroModeMorning</strong> - REAL, CIVIL, NAUTIC, ASTRONOMIC oder HORIZON</li>
            <a name="ASC_autoAstroModeMorningHorizon"></a>
            <li><strong>ASC_autoAstroModeMorningHorizon</strong> - H&ouml;he &uuml;ber dem Horizont. Wird nur ber&uuml;cksichtigt, wenn im Attribut <em>ASC_autoAstroModeMorning</em> der Wert <em>HORIZON</em> ausgew&auml;hlt wurde. (default: 0)</li>
            <a name="ASC_autoShuttersControlComfort"></a>
            <li><strong>ASC_autoShuttersControlComfort - on/off</strong> - schaltet die Komfortfunktion an. Bedeutet, dass ein Rollladen mit einem threestate-Sensor am Fenster beim &Ouml;ffnen in eine Offenposition f&auml;hrt. Hierzu muss beim Rollladen das Attribut <em>ASC_ComfortOpen_Pos</em> entsprechend konfiguriert sein. (default: off)</li>
            <a name="ASC_autoShuttersControlEvening"></a>
            <li><strong>ASC_autoShuttersControlEvening - on/off</strong> - Aktiviert die automatische Steuerung durch das ASC-Modul am Abend.</li>
            <a name="ASC_autoShuttersControlMorning"></a>
            <li><strong>ASC_autoShuttersControlMorning - on/off</strong> - Aktiviert die automatische Steuerung durch das ASC-Modul am Morgen.</li>
            <a name="ASC_blockAscDrivesAfterManual"></a>
            <li><strong>ASC_blockAscDrivesAfterManual - 0,1</strong> - wenn dieser Wert auf 1 gesetzt ist, dann werden Rolll&auml;den vom ASC-Modul nicht mehr gesteuert, wenn zuvor manuell eingegriffen wurde. Voraussetzung hierf&uuml;r ist jedoch, dass im Reading <em>ASC_ShuttersLastDrive</em> der Status <em>manual</em> enthalten ist und sich der Rollladen auf eine unbekannte (nicht in den Attributen anderweitig konfigurierte) Position befindet.</li>
            <a name="ASC_brightnessDriveUpDown"></a>
            <li><strong>ASC_brightnessDriveUpDown - WERT-MORGENS:WERT-ABENDS</strong> - Werte bei dem Schaltbedingungen f&uuml;r Sonnenauf- und -untergang gepr&uuml;ft werden sollen. Diese globale Einstellung kann durch die WERT-MORGENS:WERT-ABENDS Einstellung von ASC_BrightnessSensor im Rollladen selbst &uuml;berschrieben werden.</li>
            <a name="ASC_debug"></a>
            <li><strong>ASC_debug</strong> - Aktiviert die erweiterte Logausgabe f&uuml;r Debugausgaben</li>
            <a name="ASC_expert"></a>
            <li><strong>ASC_expert</strong> - ist der Wert 1, so werden erweiterte Informationen bez&uuml;glich des NotifyDevs unter set und get angezeigt</li>
            <a name="ASC_freezeTemp"></a>
            <li><strong>ASC_freezeTemp</strong> - Temperatur, ab welcher der Frostschutz greifen soll und der Rollladen nicht mehr f&auml;hrt. Der letzte Fahrbefehl wird gespeichert.</li>
            <a name="ASC_rainSensor"></a>
            <li><strong>ASC_rainSensor - DEVICENAME[:READINGNAME] MAXTRIGGER[:HYSTERESE] [CLOSEDPOS]</strong> - der Inhalt ist eine Kombination aus Devicename, Readingname, Wert ab dem getriggert werden soll, Hysterese Wert ab dem der Status Regenschutz aufgehoben werden soll und der "wegen Regen geschlossen Position".</li>
            <a name="ASC_residentsDev"></a>
            <li><strong>ASC_residentsDev - DEVICENAME[:READINGNAME]</strong> - der Inhalt ist eine Kombination aus Devicenamen und Readingnamen des Residents-Device der obersten Ebene (z.B. rgr_Residents:state)</li>
            <a name="ASC_shuttersDriveDelay"></a>
            <li><strong>ASC_shuttersDriveDelay</strong> - maximale Zufallsverz&ouml;gerung in Sekunden bei der Berechnung der Fahrzeiten. 0 bedeutet keine Verz&ouml;gerung</li>
            <a name="ASC_tempSensor"></a>
            <li><strong>ASC_tempSensor - DEVICENAME[:READINGNAME]</strong> - der Inhalt ist eine Kombination aus Device und Reading f&uuml;r die Au&szlig;entemperatur</li>
            <a name="ASC_twilightDevice"></a>
            <li><strong>ASC_twilightDevice</strong> - das Device, welches die Informationen zum Sonnenstand liefert. Wird unter anderem f&uuml;r die Beschattung verwendet.</li>
            <a name="ASC_windSensor"></a>
            <li><strong>ASC_windSensor - DEVICE[:READING]</strong> - Sensor f&uuml;r die Windgeschwindigkeit. Kombination aus Device und Reading.</li>
        </ul>
        <br />
        <br />
        <u> In den Rolll&auml;den-Ger&auml;ten</u>
        <ul>
            <li><strong>ASC - 0/1/2</strong> 0 = "kein Anlegen der Attribute beim ersten Scan bzw. keine Beachtung eines Fahrbefehles",1 = "Inverse oder Rollo - Bsp.: Rollo oben 0, Rollo unten 100 und der Befehl zum prozentualen Fahren ist position",2 = "Homematic Style - Bsp.: Rollo oben 100, Rollo unten 0 und der Befehl zum prozentualen Fahren ist pct</li>
            <li><strong>ASC_Antifreeze - soft/am/pm/hard/off</strong> - Frostschutz, wenn soft f&auml;hrt der Rollladen in die ASC_Antifreeze_Pos und wenn hard/am/pm wird gar nicht oder innerhalb der entsprechenden Tageszeit nicht gefahren (default: off)</li>
            <li><strong>ASC_Antifreeze_Pos</strong> - Position die angefahren werden soll, wenn der Fahrbefehl komplett schlie&szlig;en lautet, aber der Frostschutz aktiv ist (Default: ist abh&auml;ngig vom Attribut<em>ASC</em> 85/15) !!!Verwendung von Perlcode ist m&ouml;glich, dieser muss in {} eingeschlossen sein. R&uuml;ckgabewert muss eine positive Zahl/Dezimalzahl sein!!!</li>
            <li><strong>ASC_AutoAstroModeEvening</strong> - aktuell REAL,CIVIL,NAUTIC,ASTRONOMIC (default: none)</li>
            <li><strong>ASC_AutoAstroModeEveningHorizon</strong> - H&ouml;he &uuml;ber Horizont, wenn beim Attribut ASC_autoAstroModeEvening HORIZON ausgew&auml;hlt (default: none)</li>
            <li><strong>ASC_AutoAstroModeMorning</strong> - aktuell REAL,CIVIL,NAUTIC,ASTRONOMIC (default: none)</li>
            <li><strong>ASC_AutoAstroModeMorningHorizon</strong> - H&ouml;he &uuml;ber Horizont,a wenn beim Attribut ASC_autoAstroModeMorning HORIZON ausgew&auml;hlt (default: none)</li>
            <li><strong>ASC_BlockingTime_afterManual</strong> - wie viel Sekunden soll die Automatik nach einer manuellen Fahrt aussetzen. (default: 1200)</li>
            <li><strong>ASC_BlockingTime_beforDayOpen</strong> - wie viel Sekunden vor dem morgendlichen &ouml;ffnen soll keine schlie&szlig;en Fahrt mehr stattfinden. (default: 3600)</li>
            <li><strong>ASC_BlockingTime_beforNightClose</strong> - wie viel Sekunden vor dem n&auml;chtlichen schlie&szlig;en soll keine &ouml;ffnen Fahrt mehr stattfinden. (default: 3600)</li>
            <li><strong>ASC_BrightnessSensor - DEVICE[:READING] WERT-MORGENS:WERT-ABENDS</strong> / 'Sensorname[:brightness [400:800]]' Angaben zum Helligkeitssensor mit (Readingname, optional) f&uuml;r die Beschattung und dem Fahren der Rollladen nach brightness und den optionalen Brightnesswerten f&uuml;r Sonnenauf- und Sonnenuntergang. (default: none)</li>
            <li><strong>ASC_Closed_Pos</strong> - in 10 Schritten von 0 bis 100 (Default: ist abh&auml;ngig vom Attribut<em>ASC</em> 0/100)</li>
            <li><strong>ASC_Open_Pos</strong> -  in 10 Schritten von 0 bis 100 (default: ist abh&auml;ngig vom Attribut<em>ASC</em> 100/0)</li>
            <li><strong>ASC_Sleep_Pos</strong> -  in 10 Schritten von 0 bis 100 (default: ist abh&auml;ngig vom Attribut<em>ASC</em> 75/25) !!!Verwendung von Perlcode ist m&ouml;glich, dieser muss in {} eingeschlossen sein. R&uuml;ckgabewert muss eine positive Zahl/Dezimalzahl sein!!!</li>
            <li><strong>ASC_ComfortOpen_Pos</strong> - in 10 Schritten von 0 bis 100 (Default: ist abh&auml;ngig vom Attribut<em>ASC</em> 20/80) !!!Verwendung von Perlcode ist m&ouml;glich, dieser muss in {} eingeschlossen sein. R&uuml;ckgabewert muss eine positive Zahl/Dezimalzahl sein!!!</li>
            <li><strong>ASC_Down - astro/time/brightness</strong> - bei astro wird Sonnenuntergang berechnet, bei time wird der Wert aus ASC_Time_Down_Early als Fahrzeit verwendet und bei brightness muss ASC_Time_Down_Early und ASC_Time_Down_Late korrekt gesetzt werden. Der Timer l&auml;uft dann nach ASC_Time_Down_Late Zeit, es wird aber in der Zeit zwischen ASC_Time_Down_Early und ASC_Time_Down_Late geschaut, ob die als Attribut im Moduldevice hinterlegte ASC_brightnessDriveUpDown der Down Wert erreicht wurde. Wenn ja, wird der Rollladen runter gefahren (default: astro)</li>
            <li><strong>ASC_Shutter_IdleDetection</strong> - <strong>READING:VALUE</strong> gibt das Reading an welches Auskunft &uuml;ber den Fahrstatus des Rollos gibt, sowie als zweites den Wert im Reading welcher aus sagt das das Rollo <strong>nicht</strong> f&auml;hrt</li>
            <li><strong>ASC_DriveUpMaxDuration</strong> - die Dauer des Hochfahrens des Rollladens plus 5 Sekunden (default: 60)</li>
            <li><strong>ASC_Drive_Delay</strong> - maximaler Wert f&uuml;r einen zuf&auml;llig ermittelte Verz&ouml;gerungswert in Sekunden bei der Berechnung der Fahrzeiten.</li>
            <li><strong>ASC_Drive_DelayStart</strong> - in Sekunden verz&ouml;gerter Wert ab welchen das Rollo gefahren werden soll.</li>
            <li><strong>ASC_LockOut - soft/hard/off</strong> - stellt entsprechend den Aussperrschutz ein. Bei global aktivem Aussperrschutz (set ASC-Device lockOut soft) und einem Fensterkontakt open bleibt dann der Rollladen oben. Dies gilt nur bei Steuerbefehlen &uuml;ber das ASC Modul. Stellt man global auf hard, wird bei entsprechender M&ouml;glichkeit versucht den Rollladen hardwareseitig zu blockieren. Dann ist auch ein Fahren &uuml;ber die Taster nicht mehr m&ouml;glich. (default: off)</li>
            <li><strong>ASC_LockOut_Cmd - inhibit/blocked/protection</strong> - set Befehl f&uuml;r das Rollladen-Device zum Hardware sperren. Dieser Befehl wird gesetzt werden, wenn man "ASC_LockOut" auf hard setzt (default: none)</li>
            <li><strong>ASC_Mode_Down - always/home/absent/off</strong> - Wann darf die Automatik steuern. immer, niemals, bei Abwesenheit des Roommate (ist kein Roommate und absent eingestellt, wird gar nicht gesteuert) (default: always)</li>
            <li><strong>ASC_Mode_Up - always/home/absent/off</strong> - Wann darf die Automatik steuern. immer, niemals, bei Abwesenheit des Roommate (ist kein Roommate und absent eingestellt, wird gar nicht gesteuert) (default: always)</li>
            <li><strong>ASC_Partymode -  on/off</strong> - schaltet den Partymodus an oder aus. Wird am ASC Device set ASC-DEVICE partyMode on geschalten, werden alle Fahrbefehle an den Rolll&auml;den, welche das Attribut auf on haben, zwischengespeichert und sp&auml;ter erst ausgef&uuml;hrt (default: off)</li>
            <li><strong>ASC_Pos_Reading</strong> - Name des Readings, welches die Position des Rollladen in Prozent an gibt; wird bei unbekannten Device Typen auch als set Befehl zum fahren verwendet</li>
            <li><strong>ASC_PrivacyUpValue_beforeDayOpen</strong> - wie viele Sekunden vor dem morgendlichen &ouml;ffnen soll der Rollladen in die Sichtschutzposition fahren, oder bei Brightness ab welchem minimum Brightnesswert soll das Rollo in die Privacy Position fahren. Bei Brightness muss zusätzlich zum Zeitwert der Brightnesswert mit angegeben werden 1800:600 bedeutet 30 min vor day open oder bei über einem Brightnesswert von 600 (default: -1)</li>
            <li><strong>ASC_PrivacyDownValue_beforeNightClose</strong> - wie viele Sekunden vor dem abendlichen schlie&szlig;en soll der Rollladen in die Sichtschutzposition fahren, oder bei Brightness ab welchem minimum Brightnesswert soll das Rollo in die Privacy Position fahren. Bei Brightness muss zusätzlich zum Zeitwert der Brightnesswert mit angegeben werden 1800:300 bedeutet 30 min vor night close oder bei unter einem Brightnesswert von 300 (default: -1)</li>
            <li><strong>ASC_PrivacyUp_Pos</strong> - Position den Rollladens f&uuml;r den morgendlichen Sichtschutz (default: 50) !!!Verwendung von Perlcode ist möglich, dieser muss in {} eingeschlossen sein. Rückgabewert muss eine positive Zahl/Dezimalzahl sein!!!</li>
            <li><strong>ASC_PrivacyDown_Pos</strong> - Position den Rollladens f&uuml;r den abendlichen Sichtschutz (default: 50) !!!Verwendung von Perlcode ist möglich, dieser muss in {} eingeschlossen sein. Rückgabewert muss eine positive Zahl/Dezimalzahl sein!!!</li>
            <li><strong>ASC_ExternalTrigger</strong> - DEVICE:READING VALUEACTIVE:VALUEINACTIVE POSACTIVE:[POSINACTIVE VALUEACTIVE2:POSACTIVE2], Beispiel: "WohnzimmerTV:state on:off 66:100" bedeutet das wenn ein "state:on" Event kommt soll das Rollo in Position 66 fahren, kommt ein "state:off" Event soll es in Position 100 fahren. Es ist m&ouml;glich die POSINACTIVE weg zu lassen dann f&auml;hrt das Rollo in LastStatus Position.</li>
            <li><strong>ASC_WindProtection - on/off</strong> - soll der Rollladen beim Windschutz beachtet werden. on=JA, off=NEIN. (default off)</li>
            <li><strong>ASC_RainProtection - on/off</strong> - soll der Rollladen beim Regenschutz beachtet werden. on=JA, off=NEIN. (default off)</li>
            <li><strong>ASC_Roommate_Device</strong> - mit Komma getrennte Namen des/der Roommate Device/s, welche den/die Bewohner des Raumes vom Rollladen wiedergibt. Es macht nur Sinn in Schlaf- oder Kinderzimmern (default: none)</li>
            <li><strong>ASC_Adv - on/off</strong> bei on wird das runterfahren des Rollos w&auml;hrend der Weihnachtszeit (1. Advent bis 6. Januar) ausgesetzt! Durch set ASCDEVICE advDriveDown werden alle ausgesetzten Fahrten nachgeholt.</li>
            <li><strong>ASC_Roommate_Reading</strong> - das Reading zum Roommate Device, welches den Status wieder gibt (default: state)</li>
            <li><strong>ASC_Self_Defense_Mode - absent/gone/off</strong> - ab welchen Residents Status soll Selfdefense aktiv werden ohne das Fenster auf sind. (default: gone)</li>
            <li><strong>ASC_Self_Defense_AbsentDelay</strong> - um wie viele Sekunden soll das fahren in Selfdefense bei Residents absent verz&ouml;gert werden. (default: 300)</li>
            <li><strong>ASC_Self_Defense_Exclude - on/off</strong> - bei on Wert wird dieser Rollladen bei aktiven Self Defense und offenen Fenster nicht runter gefahren, wenn Residents absent ist. (default: off), off bedeutet das es ausgeschlossen ist vom Self Defense</li></p>
            <ul>
                <strong><u>Beschreibung der Beschattungsfunktion</u></strong>
                </br>Damit die Beschattung Funktion hat, m&uuml;ssen folgende Anforderungen erf&uuml;llt sein.
                </br><strong>Im ASC Device</strong> das Reading "controlShading" mit dem Wert on, sowie ein Astro/Twilight Device im Attribut "ASC_twilightDevice" und das Attribut "ASC_tempSensor".
                </br><strong>In den Rollladendevices</strong> ben&ouml;tigt ihr ein Helligkeitssensor als Attribut "ASC_BrightnessSensor", sofern noch nicht vorhanden. Findet der Sensor nur f&uuml;r die Beschattung Verwendung ist der Wert DEVICENAME[:READING] ausreichend.
                </br>Alle weiteren Attribute sind optional und wenn nicht gesetzt mit Default-Werten belegt. Ihr solltet sie dennoch einmal anschauen und entsprechend Euren Gegebenheiten setzen. Die Werte f&uuml;r die Fensterposition und den Vor- Nachlaufwinkel sowie die Grenzwerte f&uuml;r die StateChange_Cloudy und StateChange_Sunny solltet ihr besondere Beachtung dabei schenken.
                <li><strong>ASC_Shading_InOutAzimuth</strong> - Azimut Wert ab dem bei &Uuml;berschreiten Beschattet und bei Unterschreiten Endschattet werden soll. (default: 95:265)</li>
                <li><strong>ASC_Shading_MinMax_Elevation</strong> - ab welcher min H&ouml;he des Sonnenstandes soll beschattet und ab welcher max H&ouml;he wieder beendet werden, immer in Abh&auml;ngigkeit der anderen einbezogenen Sensorwerte (default: 25.0:100.0)</li>
                <li><strong>ASC_Shading_Min_OutsideTemperature</strong> - ab welcher Temperatur soll Beschattet werden, immer in Abh&auml;ngigkeit der anderen einbezogenen Sensorwerte (default: 18)</li>
                <li><strong>ASC_Shading_Mode - absent,always,off,home</strong> / wann soll die Beschattung nur stattfinden. (default: off)</li>
                <li><strong>ASC_Shading_Pos</strong> - Position des Rollladens f&uuml;r die Beschattung (Default: ist abh&auml;ngig vom Attribut<em>ASC</em> 80/20) !!!Verwendung von Perlcode ist möglich, dieser muss in {} eingeschlossen sein. Rückgabewert muss eine positive Zahl/Dezimalzahl sein!!!</li>
                <li><strong>ASC_Shading_StateChange_SunnyCloudy</strong> - Brightness Wert ab welchen die Beschattung stattfinden und aufgehoben werden soll, immer in Abh&auml;ngigkeit der anderen einbezogenen Sensorwerte. Ein optionaler dritter Wert gibt an wie viele Brightnesswerte im Average Array enthalten sein sollen (default: 35000:20000 [3])</li>
                <li><strong>ASC_Shading_WaitingPeriod</strong> - wie viele Sekunden soll gewartet werden bevor eine weitere Auswertung der Sensordaten f&uuml;r die Beschattung stattfinden soll (default: 1200)</li>
            </ul></p>
            <li><strong>ASC_ShuttersPlace - window/terrace</strong> - Wenn dieses Attribut auf terrace gesetzt ist, das Residence Device in den Status "gone" geht und SelfDefense aktiv ist (ohne das das Reading selfDefense gesetzt sein muss), wird das Rollo geschlossen (default: window)</li>
            <li><strong>ASC_Time_Down_Early</strong> - Sonnenuntergang fr&uuml;hste Zeit zum Runterfahren (default: 16:00) !!!Verwendung von Perlcode ist möglich, dieser muss in {} eingeschlossen sein. Rückgabewert muss ein Zeitformat in Form HH:MM[:SS] sein!!!</li>
            <li><strong>ASC_Time_Down_Late</strong> - Sonnenuntergang sp&auml;teste Zeit zum Runterfahren (default: 22:00) !!!Verwendung von Perlcode ist möglich, dieser muss in {} eingeschlossen sein. Rückgabewert muss ein Zeitformat in Form HH:MM[:SS] sein!!!</li>
            <li><strong>ASC_Time_Up_Early</strong> - Sonnenaufgang fr&uuml;hste Zeit zum Hochfahren (default: 05:00) !!!Verwendung von Perlcode ist möglich, dieser muss in {} eingeschlossen sein. Rückgabewert muss ein Zeitformat in Form HH:MM[:SS] sein!!!</li>
            <li><strong>ASC_Time_Up_Late</strong> - Sonnenaufgang sp&auml;teste Zeit zum Hochfahren (default: 08:30) !!!Verwendung von Perlcode ist möglich, dieser muss in {} eingeschlossen sein. Rückgabewert muss ein Zeitformat in Form HH:MM[:SS] sein!!!</li>
            <li><strong>ASC_Time_Up_WE_Holiday</strong> - Sonnenaufgang fr&uuml;hste Zeit zum Hochfahren am Wochenende und/oder Urlaub (holiday2we wird beachtet). (default: 08:00) ACHTUNG!!! in Verbindung mit Brightness f&uuml;r <em>ASC_Up</em> muss die Uhrzeit kleiner sein wie die Uhrzeit aus <em>ASC_Time_Up_Late</em> !!!Verwendung von Perlcode ist möglich, dieser muss in {} eingeschlossen sein. Rückgabewert muss ein Zeitformat in Form HH:MM[:SS] sein!!!</li>
            <li><strong>ASC_Up - astro/time/brightness</strong> - bei astro wird Sonnenaufgang berechnet, bei time wird der Wert aus ASC_Time_Up_Early als Fahrzeit verwendet und bei brightness muss ASC_Time_Up_Early und ASC_Time_Up_Late korrekt gesetzt werden. Der Timer l&auml;uft dann nach ASC_Time_Up_Late Zeit, es wird aber in der Zeit zwischen ASC_Time_Up_Early und ASC_Time_Up_Late geschaut, ob die als Attribut im Moduldevice hinterlegte Down Wert von ASC_brightnessDriveUpDown erreicht wurde. Wenn ja, wird der Rollladen hoch gefahren (default: astro)</li>
            <li><strong>ASC_Ventilate_Pos</strong> -  in 10 Schritten von 0 bis 100 (default: ist abh&auml;ngig vom Attribut <em>ASC</em> 70/30) !!!Verwendung von Perlcode ist möglich, dieser muss in {} eingeschlossen sein. Rückgabewert muss eine positive Zahl/Dezimalzahl sein!!!</li>
            <li><strong>ASC_Ventilate_Window_Open</strong> - auf l&uuml;ften, wenn das Fenster gekippt/ge&ouml;ffnet wird und aktuelle Position unterhalb der L&uuml;ften-Position ist (default: on)</li>
            <li><strong>ASC_WiggleValue</strong> - Wert um welchen sich die Position des Rollladens &auml;ndern soll (default: 5)</li>
            <li><strong>ASC_WindParameters - TRIGGERMAX[:HYSTERESE] [DRIVEPOSITION]</strong> / Angabe von Max Wert ab dem f&uuml;r Wind getriggert werden soll, Hytsrese Wert ab dem der Windschutz aufgehoben werden soll TRIGGERMAX - HYSTERESE / Ist es bei einigen Rolll&auml;den nicht gew&uuml;nscht das gefahren werden soll, so ist der TRIGGERMAX Wert mit -1 an zu geben. (default: '50:20 ClosedPosition')</li>
            <li><strong>ASC_WindowRec_PosAfterDayClosed</strong> - open,lastManual / auf welche Position soll das Rollo nach dem schlie&szlig;en am Tag fahren. Open Position oder letzte gespeicherte manuelle Position (default: open)</li>
            <li><strong>ASC_WindowRec</strong> - WINDOWREC:[READING], Name des Fensterkontaktes, an dessen Fenster der Rollladen angebracht ist (default: none). Reading ist optional</li>
            <li><strong>ASC_WindowRec_subType</strong> - Typ des verwendeten Fensterkontaktes: twostate (optisch oder magnetisch) oder threestate (Drehgriffkontakt) (default: twostate)</li>
        </ul>
    </ul>
    </p>
    <strong><u>Beschreibung der AutoShuttersControl API</u></strong>
    </br>Mit dem Aufruf der API Funktion und &Uuml;bergabe der entsprechenden Parameter ist es m&ouml;glich auf interne Daten zu zu greifen.
    </p>
    <u>&Uuml;bersicht f&uuml;r das Rollladen-Device</u>
    <ul>
        <code>{ ascAPIget('Getter','ROLLODEVICENAME') }</code><br>
    </ul>
    <table>
        <tr><th>Getter</th><th>Erl&auml;uterung</th></tr>
        <tr><td>FreezeStatus</td><td>1=soft, 2=Daytime, 3=hard</td></tr>
        <tr><td>NoDelay</td><td>Wurde die Behandlung von Offset deaktiviert (Beispiel bei Fahrten &uuml;ber Fensterevents)</td></tr>
        <tr><td>LastDrive</td><td>Grund des letzten Fahrens</td></tr>
        <tr><td>LastPos</td><td>die letzte Position des Rollladens</td></tr>
        <tr><td>LastPosTimestamp</td><td>Timestamp der letzten festgestellten Position</td></tr>
        <tr><td>LastManPos</td><td>Position der letzten manuellen Fahrt</td></tr>
        <tr><td>LastManPosTimestamp</td><td>Timestamp der letzten manuellen Position</td></tr>
        <tr><td>SunsetUnixTime</td><td>berechnete Unixzeit f&uuml;r Abends (Sonnenuntergang)</td></tr>
        <tr><td>Sunset</td><td>1=Abendfahrt wurde durchgef&uuml;hrt, 0=noch keine Abendfahrt durchgef&uuml;hrt</td></tr>
        <tr><td>SunriseUnixTime</td><td>berechnete Unixzeit f&uuml;r Morgens (Sonnenaufgang)</td></tr>
        <tr><td>Sunrise</td><td>1=Morgenfahrt wurde durchgef&uuml;hrt, 0=noch keine Morgenfahrt durchgef&uuml;hrt</td></tr>
        <tr><td>RoommatesStatus</td><td>aktueller Status der/des Roommate/s f&uuml;r den Rollladen</td></tr>
        <tr><td>RoommatesLastStatus</td><td>letzter Status der/des Roommate/s f&uuml;r den Rollladen</td></tr>
        <tr><td>ShadingStatus</td><td>Ausgabe des aktuellen Shading Status, „in“, „out“, „in reserved“, „out reserved“</td></tr>
        <tr><td>ShadingStatusTimestamp</td><td>Timestamp des letzten Beschattungsstatus</td></tr>
        <tr><td>IfInShading</td><td>Befindet sich der Rollladen, in Abh&auml;ngigkeit des Shading Mode, in der Beschattung</td></tr>
        <tr><td>WindProtectionStatus</td><td>aktueller Status der Wind Protection „protected“ oder „unprotected“</td></tr>
        <tr><td>RainProtectionStatus</td><td>aktueller Status der Regen Protection „unprotected“ oder „unprotected“</td></tr>
        <tr><td>DelayCmd</td><td>letzter Fahrbefehl welcher in die Warteschlange kam. Grund z.B. Partymodus.</td></tr>
        <tr><td>Status</td><td>Position des Rollladens</td></tr>
        <tr><td>ASCenable</td><td>Abfrage ob f&uuml;r den Rollladen die ASC Steuerung aktiv ist.</td></tr>
        <tr><td>IsDay</td><td>Abfrage ob das Rollo im Tag oder Nachtmodus ist. Also nach Sunset oder nach Sunrise</td></tr>
        <tr><td>PrivacyDownStatus</td><td>Abfrage ob das Rollo aktuell im PrivacyDown Status steht</td></tr>
        <tr><td>OutTemp</td><td>aktuelle Au&szlig;entemperatur sofern ein Sensor definiert ist, wenn nicht kommt -100 als Wert zur&uuml;ck</td></tr>
    </table>
    </p>
    <u>&Uuml;bersicht f&uuml;r das Rollladen-Device mit Parameter&uuml;bergabe</u>
    <ul>
        <code>{ ascAPIget('Getter','ROLLODEVICENAME',VALUE) }</code><br>
    </ul>
    <table>
        <tr><th>Getter</th><th>Erl&auml;uterung</th></tr>
        <tr><td>QueryShuttersPos</td><td>R&uuml;ckgabewert 1 bedeutet das die aktuelle Position des Rollos unterhalb der Valueposition ist. 0 oder nichts bedeutet oberhalb der Valueposition.</td></tr>
    </table>
    </p>
    <u>&Uuml;bersicht f&uuml;r das ASC Device</u>
    <ul>
        <code>{ ascAPIget('Getter') }</code><br>
    </ul>
    <table>
        <tr><th>Getter</th><th>Erl&auml;uterung</th></tr>
        <tr><td>OutTemp </td><td>aktuelle Au&szlig;entemperatur sofern ein Sensor definiert ist, wenn nicht kommt -100 als Wert zur&uuml;ck</td></tr>
        <tr><td>ResidentsStatus</td><td>aktueller Status des Residents Devices</td></tr>
        <tr><td>ResidentsLastStatus</td><td>letzter Status des Residents Devices</td></tr>
        <tr><td>Azimuth</td><td>Azimut Wert</td></tr>
        <tr><td>Elevation</td><td>Elevation Wert</td></tr>
        <tr><td>ASCenable</td><td>ist die ASC Steuerung global aktiv?</td></tr>
    </table>
</ul>

=end html_DE

=for :application/json;q=META.json 73_AutoShuttersControl.pm
{
  "abstract": "Module for controlling shutters depending on various conditions",
  "x_lang": {
    "de": {
      "abstract": "Modul zur Automatischen Rolladensteuerung auf Basis bestimmter Ereignisse"
    }
  },
  "keywords": [
    "fhem-mod-device",
    "fhem-core",
    "Shutter",
    "Automation",
    "Rollladen",
    "Rollo",
    "Control"
  ],
  "release_status": "testing",
  "license": "GPL_2",
  "version": "v0.8.32",
  "author": [
    "Marko Oldenburg <leongaultier@gmail.com>"
  ],
  "x_fhem_maintainer": [
    "CoolTux"
  ],
  "x_fhem_maintainer_github": [
    "LeonGaultier"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918799,
        "perl": 5.016, 
        "Meta": 0,
        "JSON": 0,
        "Date::Parse": 0
      },
      "recommends": {
      },
      "suggests": {
      }
    }
  }
}
=end :application/json;q=META.json

=cut
