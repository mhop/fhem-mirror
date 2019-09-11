###############################################################################
#
# Developed with Kate
#
#  (c) 2018-2019 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
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
# - Feststellen ob ein Rolladen fährt oder nicht
# !!!!! - Innerhalb einer Shutterschleife kein CommandAttr verwenden. Bring Fehler!!! Kommen Raumnamen in die Shutterliste !!!!!!
#

package main;

use strict;
use warnings;

sub ascAPIget($@) {
    my ( $getCommand, $shutterDev, $value ) = @_;

    return AutoShuttersControl_ascAPIget( $getCommand, $shutterDev, $value );
}

## unserer packagename
package FHEM::AutoShuttersControl;

use strict;
use warnings;
use POSIX;
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
    'ASC_Pos_Reading'                            => [ '', 'position', 'pct' ],
    'ASC_Time_Up_Early'                          => '-',
    'ASC_Time_Up_Late'                           => '-',
    'ASC_Time_Up_WE_Holiday'                     => '-',
    'ASC_Time_Down_Early'                        => '-',
    'ASC_Time_Down_Late'                         => '-',
    'ASC_PrivacyDownTime_beforNightClose'        => '-',
    'ASC_PrivacyDown_Pos'                        => '-',
    'ASC_TempSensor'                             => '-',
    'ASC_Ventilate_Window_Open:on,off'           => '-',
    'ASC_LockOut:soft,hard,off'                  => '-',
    'ASC_LockOut_Cmd:inhibit,blocked,protection' => '-',
    'ASC_BlockingTime_afterManual'               => '-',
    'ASC_BlockingTime_beforNightClose'           => '-',
    'ASC_BlockingTime_beforDayOpen'              => '-',
    'ASC_BrightnessSensor'                       => '-',
    'ASC_Shading_Direction'                      => '-',
    'ASC_Shading_Pos:10,20,30,40,50,60,70,80,90,100'       => [ '', 80, 20 ],
    'ASC_Shading_Mode:absent,always,off,home'              => '-',
    'ASC_Shading_Angle_Left'                               => '-',
    'ASC_Shading_Angle_Right'                              => '-',
    'ASC_Shading_StateChange_Sunny'                        => '-',
    'ASC_Shading_StateChange_Cloudy'                       => '-',
    'ASC_Shading_MinMax_Elevation'                         => '-',
    'ASC_Shading_Min_OutsideTemperature'                   => '-',
    'ASC_Shading_WaitingPeriod'                            => '-',
    'ASC_Drive_Offset'                                     => '-',
    'ASC_Drive_OffsetStart'                                => '-',
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
    'ASC_Partymode:on,off'              => '-',
    'ASC_Roommate_Device'               => '-',
    'ASC_Roommate_Reading'              => '-',
    'ASC_Self_Defense_Exclude:on,off'   => '-',
    'ASC_Self_Defense_Mode:absent,gone' => '-',
    'ASC_Self_Defense_AbsentDelay'      => '-',
    'ASC_WiggleValue'                   => '-',
    'ASC_WindParameters'                => '-',
    'ASC_DriveUpMaxDuration'            => '-',
    'ASC_WindProtection:on,off'         => '-',
    'ASC_RainProtection:on,off'         => '-'
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

my $shutters = new ASC_Shutters();
my $ascDev   = new ASC_Dev();

sub ascAPIget($@) {
    my ( $getCommand, $shutterDev, $value ) = @_;

    my $getter = 'get' . $getCommand;

    if ( defined($value) and $value ) {
        $shutters->setShuttersDev($shutterDev);
        return $shutters->$getter($value);
    }
    elsif ( defined($shutterDev) and $shutterDev ) {
        $shutters->setShuttersDev($shutterDev);
        return $shutters->$getter;
    }
    else {
        return $ascDev->$getter;
    }
}

sub Initialize($) {
    my ($hash) = @_;

## Da ich mit package arbeite müssen in die Initialize für die jeweiligen hash Fn Funktionen der Funktionsname
    #  und davor mit :: getrennt der eigentliche package Name des Modules
    $hash->{SetFn}    = 'FHEM::AutoShuttersControl::Set';
    $hash->{GetFn}    = 'FHEM::AutoShuttersControl::Get';
    $hash->{DefFn}    = 'FHEM::AutoShuttersControl::Define';
    $hash->{NotifyFn} = 'FHEM::AutoShuttersControl::Notify';
    $hash->{UndefFn}  = 'FHEM::AutoShuttersControl::Undef';
    $hash->{AttrFn}   = 'FHEM::AutoShuttersControl::Attr';
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
      . 'ASC_shuttersDriveOffset '
      . 'ASC_twilightDevice '
      . 'ASC_windSensor '
      . 'ASC_expert:1 '
      . 'ASC_blockAscDrivesAfterManual:0,1 '
      . 'ASC_debug:1 '
      . $readingFnAttributes;
    $hash->{NotifyOrderPrefix} = '51-';    # Order Nummer für NotifyFn

    return FHEM::Meta::InitMod( __FILE__, $hash );
}

sub Define($$) {
    my ( $hash, $def ) = @_;
    my @a = split( '[ \t][ \t]*', $def );

    return $@ unless ( FHEM::Meta::SetInternals($hash) );
    use version 0.60; our $VERSION = FHEM::Meta::Get( $hash, 'version' );

    return 'only one AutoShuttersControl instance allowed'
      if ( devspec2array('TYPE=AutoShuttersControl') > 1 )
      ; # es wird geprüft ob bereits eine Instanz unseres Modules existiert,wenn ja wird abgebrochen
    return 'too few parameters: define <name> ShuttersControl' if ( @a != 2 );

    my $name = $a[0];

    $hash->{MID} = 'da39a3ee5e6b4b0d3255bfef95601890afd80709'
      ; # eine Ein Eindeutige ID für interne FHEM Belange / nicht weiter wichtig

    #   ### Versionierung ###
    # Stable Version
    $hash->{VERSION} = version->parse($VERSION)->normal;

  # Developer Version
  #     $hash->{DEV_VERSION} = FHEM::Meta::Get( $hash, 'x_developmentversion' );

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
        $name
          . ' devStateIcon selfDefense.terrace:fts_door_tilt created.new.drive.timer:clock .*asleep:scene_sleeping roommate.(awoken|home):user_available residents.(home|awoken):status_available manual:fts_shutter_manual selfDefense.active:status_locked selfDefense.inactive:status_open day.open:scene_day night.close:scene_night shading.in:weather_sun shading.out:weather_cloudy'
    ) if ( AttrVal( $name, 'devStateIcon', 'none' ) eq 'none' );

    addToAttrList('ASC:0,1,2');

    Log3( $name, 3, "AutoShuttersControl ($name) - defined" );

    $modules{AutoShuttersControl}{defptr}{ $hash->{MID} } = $hash;

    return undef;
}

sub Undef($$) {
    my ( $hash, $arg ) = @_;

    my $name = $hash->{NAME};

    UserAttributs_Readings_ForShutters( $hash, 'del' )
      ; # es sollen alle Attribute und Readings in den Rolläden Devices gelöscht werden welche vom Modul angelegt wurden
    delFromAttrList('ASC:0,1,2');

    delete( $modules{AutoShuttersControl}{defptr}{ $hash->{MID} } );

    Log3( $name, 3, "AutoShuttersControl ($name) - delete device $name" );
    return undef;
}

sub Attr(@) {
    my ( $cmd, $name, $attrName, $attrVal ) = @_;

    #     my $hash = $defs{$name};

    return undef;
}

sub Notify($$) {
    my ( $hash, $dev ) = @_;
    my $name = $hash->{NAME};

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
            grep /^DEFINED.$name$/,
            @{$events} and $devname eq 'global' and $init_done
        )
        or (
            grep /^INITIALIZED$/,
            @{$events} or grep /^REREADCFG$/,
            @{$events} or grep /^MODIFIED.$name$/,
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

# Ist der Event ein globaler und passt zum Rest der Abfrage oben wird nach neuen Rolläden Devices gescannt und eine Liste im Rolladenmodul sortiert nach Raum generiert
        ShuttersDeviceScan($hash)
          unless ( ReadingsVal( $name, 'userAttrList', 'none' ) eq 'none' );
    }
    return
      unless ( ref( $hash->{helper}{shuttersList} ) eq 'ARRAY'
        and scalar( @{ $hash->{helper}{shuttersList} } ) > 0 );

    my $posReading = $shutters->getPosCmd;

    if ( $devname eq $name ) {
        if ( grep /^userAttrList:.rolled.out$/, @{$events} ) {
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
        elsif ( grep /^partyMode:.off$/, @{$events} ) {
            EventProcessingPartyMode($hash);
        }
        elsif ( grep /^sunriseTimeWeHoliday:.(on|off)$/, @{$events} ) {
            RenewSunRiseSetShuttersTimer($hash);
        }
    }
    elsif ( $devname eq "global" )
    { # Kommt ein globales Event und beinhaltet folgende Syntax wird die Funktion zur Verarbeitung aufgerufen
        if (
            grep
/^(ATTR|DELETEATTR)\s(.*ASC_Time_Up_WE_Holiday|.*ASC_Up|.*ASC_Down|.*ASC_AutoAstroModeMorning|.*ASC_AutoAstroModeMorningHorizon|.*ASC_AutoAstroModeEvening|.*ASC_AutoAstroModeEveningHorizon|.*ASC_Time_Up_Early|.*ASC_Time_Up_Late|.*ASC_Time_Down_Early|.*ASC_Time_Down_Late|.*ASC_autoAstroModeMorning|.*ASC_autoAstroModeMorningHorizon|.*ASC_PrivacyDownTime_beforNightClose|.*ASC_autoAstroModeEvening|.*ASC_autoAstroModeEveningHorizon|.*ASC_Roommate_Device|.*ASC_WindowRec|.*ASC_residentsDev|.*ASC_rainSensor|.*ASC_windSensor|.*ASC_BrightnessSensor|.*ASC_twilightDevice)(\s.*|$)/,
            @{$events}
          )
        {
            EventProcessingGeneral( $hash, undef, join( ' ', @{$events} ) );
        }
    }
    elsif ( grep /^($posReading):\s\d+$/, @{$events} ) {
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

sub EventProcessingGeneral($$$) {
    my ( $hash, $devname, $events ) = @_;
    my $name = $hash->{NAME};

    if ( defined($devname) and ($devname) )
    { # es wird lediglich der Devicename der Funktion mitgegeben wenn es sich nicht um global handelt daher hier die Unterschiedung
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

            $shutters->setShuttersDev($device)
              if ( $deviceAttr eq 'ASC_BrightnessSensor' );

            if (
                $deviceAttr eq 'ASC_BrightnessSensor'
                and (  $shutters->getDown eq 'brightness'
                    or $shutters->getUp eq 'brightness' )
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
        if ( $events =~
m#^ATTR\s(.*)\s(ASC_Roommate_Device|ASC_WindowRec|ASC_residentsDev|ASC_rainSensor|ASC_windSensor|ASC_BrightnessSensor|ASC_twilightDevice)\s(.*)$#
          )
        {     # wurde den Attributen unserer Rolläden ein Wert zugewiesen ?
            AddNotifyDev( $hash, $3, $1, $2 ) if ( $3 ne 'none' );
            Log3( $name, 4,
                "AutoShuttersControl ($name) - EventProcessing: ATTR" );
        }
        elsif ( $events =~
m#^DELETEATTR\s(.*)\s(ASC_Roommate_Device|ASC_WindowRec|ASC_residentsDev|ASC_rainSensor|ASC_windSensor|ASC_BrightnessSensor|ASC_twilightDevice)$#
          )
        {     # wurde das Attribut unserer Rolläden gelöscht ?
            Log3( $name, 4,
                "AutoShuttersControl ($name) - EventProcessing: DELETEATTR" );
            DeleteNotifyDev( $hash, $1, $2 );
        }
        elsif ( $events =~
m#^(DELETEATTR|ATTR)\s(.*)\s(ASC_Time_Up_WE_Holiday|ASC_Up|ASC_Down|ASC_AutoAstroModeMorning|ASC_AutoAstroModeMorningHorizon|ASC_PrivacyDownTime_beforNightClose|ASC_AutoAstroModeEvening|ASC_AutoAstroModeEveningHorizon|ASC_Time_Up_Early|ASC_Time_Up_Late|ASC_Time_Down_Early|ASC_Time_Down_Late)(.*)?#
          )
        {
            CreateSunRiseSetShuttersTimer( $hash, $2 )
              if (
                $3 ne 'ASC_Time_Up_WE_Holiday'
                or (    $3 eq 'ASC_Time_Up_WE_Holiday'
                    and $ascDev->getSunriseTimeWeHoliday eq 'on' )
              );
        }
        elsif ( $events =~
m#^(DELETEATTR|ATTR)\s(.*)\s(ASC_autoAstroModeMorning|ASC_autoAstroModeMorningHorizon|ASC_autoAstroModeEvening|ASC_autoAstroModeEveningHorizon)(.*)?#
          )
        {
            RenewSunRiseSetShuttersTimer($hash);
        }
    }
}

sub Set($$@) {
    my ( $hash, $name, @aa ) = @_;
    my ( $cmd, @args ) = @aa;

    if ( lc $cmd eq 'renewsetsunrisesunsettimer' ) {
        return "usage: $cmd" if ( @args != 0 );
        RenewSunRiseSetShuttersTimer($hash);
    }
    elsif ( lc $cmd eq 'scanforshutters' ) {
        return "usage: $cmd" if ( @args != 0 );
        ShuttersDeviceScan($hash);
    }
    elsif ( lc $cmd eq 'createnewnotifydev' ) {
        return "usage: $cmd" if ( @args != 0 );
        CreateNewNotifyDev($hash);
    }
    elsif ( lc $cmd eq 'partymode' ) {
        return "usage: $cmd" if ( @args > 1 );
        readingsSingleUpdate( $hash, $cmd, join( ' ', @args ), 1 )
          if ( join( ' ', @args ) ne ReadingsVal( $name, 'partyMode', 0 ) );
    }
    elsif ( lc $cmd eq 'hardlockout' ) {
        return "usage: $cmd" if ( @args > 1 );
        readingsSingleUpdate( $hash, $cmd, join( ' ', @args ), 1 );
        HardewareBlockForShutters( $hash, join( ' ', @args ) );
    }
    elsif ( lc $cmd eq 'sunrisetimeweholiday' ) {
        return "usage: $cmd" if ( @args > 1 );
        readingsSingleUpdate( $hash, $cmd, join( ' ', @args ), 1 );
    }
    elsif ( lc $cmd eq 'controlshading' ) {
        return "usage: $cmd" if ( @args > 1 );
        readingsSingleUpdate( $hash, $cmd, join( ' ', @args ), 1 );
    }
    elsif ( lc $cmd eq 'selfdefense' ) {
        return "usage: $cmd" if ( @args > 1 );
        readingsSingleUpdate( $hash, $cmd, join( ' ', @args ), 1 );
    }
    elsif ( lc $cmd eq 'ascenable' ) {
        return "usage: $cmd" if ( @args > 1 );
        readingsSingleUpdate( $hash, $cmd, join( ' ', @args ), 1 );
    }
    elsif ( lc $cmd eq 'shutterascenabletoggle' ) {
        return "usage: $cmd" if ( @args > 1 );
        readingsSingleUpdate(
            $defs{ $args[0] },
            'ASC_Enable',
            (
                ReadingsVal( $args[0], 'ASC_Enable', 'off' ) eq 'on'
                ? 'off'
                : 'on'
            ),
            1
        );
    }
    elsif ( lc $cmd eq 'wiggle' ) {
        return "usage: $cmd" if ( @args > 1 );

        ( $args[0] eq 'all' ? wiggleAll($hash) : wiggle( $hash, $args[0] ) );
    }
    else {
        my $list = 'scanForShutters:noArg';
        $list .=
' renewSetSunriseSunsetTimer:noArg partyMode:on,off hardLockOut:on,off sunriseTimeWeHoliday:on,off controlShading:on,off selfDefense:on,off ascEnable:on,off wiggle:all,'
          . join( ',', @{ $hash->{helper}{shuttersList} } )
          if ( ReadingsVal( $name, 'userAttrList', 'none' ) eq 'rolled out' );
        $list .= ' createNewNotifyDev:noArg'
          if (  ReadingsVal( $name, 'userAttrList', 'none' ) eq 'rolled out'
            and AttrVal( $name, 'ASC_expert', 0 ) == 1 );
        $list .=
          ' shutterASCenableToggle:'
          . join( ',', @{ $hash->{helper}{shuttersList} } )
          if ( ReadingsVal( $name, 'userAttrList', 'none' ) eq 'rolled out' );

        return "Unknown argument $cmd,choose one of $list";
    }
    return undef;
}

sub Get($$@) {
    my ( $hash, $name, @aa ) = @_;

    my ( $cmd, @args ) = @aa;

    if ( lc $cmd eq 'showshuttersinformations' ) {
        return "usage: $cmd" if ( @args != 0 );
        my $ret = GetShuttersInformation($hash);
        return $ret;
    }
    elsif ( lc $cmd eq 'shownotifydevsinformations' ) {
        return "usage: $cmd" if ( @args != 0 );
        my $ret = GetMonitoredDevs($hash);
        return $ret;
    }
    else {
        my $list = "";
        $list .= " showShuttersInformations:noArg"
          if ( ReadingsVal( $name, 'userAttrList', 'none' ) eq 'rolled out' );
        $list .= " showNotifyDevsInformations:noArg"
          if (  ReadingsVal( $name, 'userAttrList', 'none' ) eq 'rolled out'
            and AttrVal( $name, 'ASC_expert', 0 ) == 1 );

        return "Unknown argument $cmd,choose one of $list";
    }
}

sub ShuttersDeviceScan($) {
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
    foreach (@list) {
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
            $shutters->setAttrUpdateChanges( 'ASC_Up',
                AttrVal( $_, 'ASC_Up', 'none' ) );
            delFromDevAttrList( $_, 'ASC_Up' );
            $shutters->setAttrUpdateChanges( 'ASC_Down',
                AttrVal( $_, 'ASC_Down', 'none' ) );
            delFromDevAttrList( $_, 'ASC_Down' );
        }

        ####

        $shuttersList = $shuttersList . ',' . $_;
        $shutters->setLastManPos( $shutters->getStatus );
        $shutters->setLastPos( $shutters->getStatus );
        $shutters->setDelayCmd('none');
        $shutters->setNoOffset(0);
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
}

## Die Funktion schreibt in das Moduldevice Readings welche Rolläden in welchen Räumen erfasst wurden.
sub WriteReadingsShuttersList($) {
    my $hash = shift;
    my $name = $hash->{NAME};

    CommandDeleteReading( undef, $name . ' room_.*' );

    readingsBeginUpdate($hash);
    foreach ( @{ $hash->{helper}{shuttersList} } ) {
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
}

sub UserAttributs_Readings_ForShutters($$) {
    my ( $hash, $cmd ) = @_;
    my $name = $hash->{NAME};

    while ( my ( $attrib, $attribValue ) = each %{userAttrList} ) {
        foreach ( @{ $hash->{helper}{shuttersList} } ) {
            addToDevAttrList( $_, $attrib )
              ; ## fhem.pl bietet eine Funktion um ein userAttr Attribut zu befüllen. Wir schreiben also in den Attribut userAttr alle unsere Attribute rein. Pro Rolladen immer ein Attribut pro Durchlauf
            ## Danach werden die Attribute die im userAttr stehen gesetzt und mit default Werten befüllt
            ## CommandAttr hat nicht funktioniert. Führte zu Problemen
            ## https://github.com/LeonGaultier/fhem-AutoShuttersControl/commit/e33d3cc7815031b087736c1054b98c57817e7083
            if ( $cmd eq 'add' ) {
                if ( ref($attribValue) ne 'ARRAY' ) {
                    $attr{$_}{ ( split( ':', $attrib ) )[0] } = $attribValue
                      if (
                        not defined( $attr{$_}{ ( split( ':', $attrib ) )[0] } )
                        and $attribValue ne '-' );
                }
                else {
                    $attr{$_}{ ( split( ':', $attrib ) )[0] } =
                      $attribValue->[ AttrVal( $_, 'ASC', 2 ) ]
                      if (
                        not defined( $attr{$_}{ ( split( ':', $attrib ) )[0] } )
                        and $attrib eq 'ASC_Pos_Reading' );
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
                  grep { " $name " !~ m/ $_ / }
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
}

## Fügt dem NOTIFYDEV Hash weitere Devices hinzu
sub AddNotifyDev($@) {
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
    foreach (@devs) {
        $hash->{monitoredDevs}{$_}{$shuttersDev} = $shuttersAttr;
    }

    readingsSingleUpdate( $hash, '.monitoredDevs',
        eval { encode_json( $hash->{monitoredDevs} ) }, 0 );
}

## entfernt aus dem NOTIFYDEV Hash Devices welche als Wert in Attributen steckten
sub DeleteNotifyDev($@) {
    my ( $hash, $shuttersDev, $shuttersAttr ) = @_;
    my $name = $hash->{NAME};

    my $notifyDevs =
      ExtractNotifyDevFromEvent( $hash, $shuttersDev, $shuttersAttr );

    foreach my $notifyDev ( keys( %{$notifyDevs} ) ) {
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
              grep { " $notifyDev " !~ m/ $_ / }
              split( ',', "$notifyDevString,$notifyDev" );

            $hash->{NOTIFYDEV} = join( ',', sort keys %hash );
        }
    }
    readingsSingleUpdate( $hash, '.monitoredDevs',
        eval { encode_json( $hash->{monitoredDevs} ) }, 0 );
}

## Sub zum steuern der Rolläden bei einem Fenster Event
sub EventProcessingWindowRec($@) {
    my ( $hash, $shuttersDev, $events ) = @_;
    my $name = $hash->{NAME};

    if ( $events =~ m#.*state:.*?([Oo]pen(?>ed)?|[Cc]losed?|tilt(?>ed)?)#
        and IsAfterShuttersManualBlocking($shuttersDev) )
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
          if (  $match =~ /[Cc]lose/
            and $shutters->getShuttersPlace eq 'terrace' );
        $shutters->setHardLockOut('on')
          if (  $match =~ /[Oo]pen/
            and $shutters->getShuttersPlace eq 'terrace' );

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
                $match =~ /[Cc]lose/
            and IsAfterShuttersTimeBlocking($shuttersDev)
            and (  $shutters->getStatus == $shutters->getVentilatePos
                or $shutters->getStatus == $shutters->getComfortOpenPos
                or $shutters->getStatus == $shutters->getOpenPos )
          )
        {
            ASC_Debug( 'EventProcessingWindowRec: '
                  . $shutters->getShuttersDev
                  . ' Event Closed' );

            if (
                $shutters->getIsDay
                and ( ( $homemode ne 'asleep' and $homemode ne 'gotosleep' )
                    or $homemode eq 'none' )
                and $shutters->getModeUp ne 'absent'
                and $shutters->getModeUp ne 'off'
              )
            {
                if (    $shutters->getShadingStatus eq 'in'
                    and $shutters->getShadingPos != $shutters->getStatus )
                {
                    $shutters->setLastDrive('shading in');
                    $shutters->setNoOffset(1);
                    $shutters->setDriveCmd( $shutters->getShadingPos );
                }
                elsif ($shutters->getStatus != $shutters->getOpenPos
                    or $shutters->getStatus != $shutters->getLastManPos )
                {
                    $shutters->setLastDrive('window closed at day');
                    $shutters->setNoOffset(1);
                    $shutters->setDriveCmd(
                        (
                              $shutters->getVentilatePosAfterDayClosed eq 'open'
                            ? $shutters->getOpenPos
                            : $shutters->getLastManPos
                        )
                    );
                }
            }
            elsif (
                    $shutters->getModeUp ne 'absent'
                and $shutters->getModeUp ne 'off'
                and (  not $shutters->getIsDay
                    or $homemode eq 'asleep'
                    or $homemode eq 'gotosleep' )
                and $shutters->getModeDown ne 'absent'
                and $shutters->getModeDown ne 'off'
              )
            {
                $shutters->setLastDrive('window closed at night');
                $shutters->setNoOffset(1);
                $shutters->setDriveCmd( $shutters->getClosedPos );
            }
        }
        elsif (
            (
                $match =~ /tilt/
                or (    $match =~ /[Oo]pen/
                    and $shutters->getSubTyp eq 'twostate' )
            )
            and $shutters->getVentilateOpen eq 'on'
            and $shutters->getQueryShuttersPos( $shutters->getVentilatePos )
          )
        {
            $shutters->setLastDrive('ventilate - window open');
            $shutters->setNoOffset(1);
            $shutters->setDriveCmd(
                (
                    (
                              $shutters->getShuttersPlace eq 'terrace'
                          and $shutters->getSubTyp eq 'twostate'
                    ) ? $shutters->getOpenPos : $shutters->getVentilatePos
                )
            );
        }
        elsif ( $match =~ /[Oo]pen/
            and $shutters->getSubTyp eq 'threestate' )
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
            elsif ( $shutters->getQueryShuttersPos( $shutters->getVentilatePos )
                and $shutters->getVentilateOpen eq 'on' )
            {
                $posValue     = $shutters->getVentilatePos;
                $setLastDrive = 'ventilate - window open';
            }

            if ( defined($posValue) and $posValue ) {
                $shutters->setLastDrive($setLastDrive);
                $shutters->setNoOffset(1);
                $shutters->setDriveCmd(
                    (
                          $shutters->getShuttersPlace eq 'terrace'
                        ? $shutters->getOpenPos
                        : $posValue
                    )
                );
            }
        }
    }
}

## Sub zum steuern der Rolladen bei einem Bewohner/Roommate Event
sub EventProcessingRoommate($@) {
    my ( $hash, $shuttersDev, $events ) = @_;
    my $name = $hash->{NAME};

    $shutters->setShuttersDev($shuttersDev);
    my $reading = $shutters->getRoommatesReading;

    if ( $events =~ m#$reading:\s(absent|gotosleep|asleep|awoken|home)# ) {
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
            ( $1 eq 'home' or $1 eq 'awoken' )
            and (  $getRoommatesStatus eq 'home'
                or $getRoommatesStatus eq 'awoken' )
            and $ascDev->getAutoShuttersControlMorning eq 'on'
            and IsAfterShuttersManualBlocking($shuttersDev)
          )
        {
            Log3( $name, 4,
"AutoShuttersControl ($name) - EventProcessingRoommate_1: $shuttersDev und Events $events"
            );
            if (
                (
                       $getRoommatesLastStatus eq 'asleep'
                    or $getRoommatesLastStatus eq 'awoken'
                )
                and $shutters->getIsDay
                and IsAfterShuttersTimeBlocking($shuttersDev)
              )
            {
                Log3( $name, 4,
"AutoShuttersControl ($name) - EventProcessingRoommate_2: $shuttersDev und Events $events"
                );

                if (    $shutters->getIfInShading
                    and not $shutters->getShadingManualDriveStatus
                    and $shutters->getStatus != $shutters->getShadingPos )
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
                    or $getRoommatesLastStatus eq 'gone'
                )
                and $getRoommatesStatus eq 'home'
              )
            {
                if (
                        not $shutters->getIsDay
                    and IsAfterShuttersTimeBlocking($shuttersDev)
                    and (  $getModeDown eq 'home'
                        or $getModeDown eq 'always' )
                  )
                {
                    $shutters->setLastDrive('roommate home');

                    if ( CheckIfShuttersWindowRecOpen($shuttersDev) == 0
                        or $shutters->getVentilateOpen eq 'off' )
                    {
                        $posValue = $shutters->getClosedPos;
                    }
                    else {
                        $posValue = $shutters->getVentilatePos;
                        $shutters->setLastDrive(
                            $shutters->getLastDrive . ' - ventilate mode' );
                    }

                    ShuttersCommandSet( $hash, $shuttersDev, $posValue );
                }
                elsif (
                        $shutters->getIsDay
                    and IsAfterShuttersTimeBlocking($shuttersDev)
                    and (  $getModeUp eq 'home'
                        or $getModeUp eq 'always' )
                  )
                {
                    if (    $shutters->getIfInShading
                        and not $shutters->getShadingManualDriveStatus
                        and $shutters->getStatus == $shutters->getOpenPos
                        and $shutters->getShadingMode eq 'home' )
                    {
                        $shutters->setLastDrive('shading in');
                        $posValue = $shutters->getShadingPos;

                        ShuttersCommandSet( $hash, $shuttersDev, $posValue );
                    }
                    elsif (
                        (
                            not $shutters->getIfInShading
                            or $shutters->getShadingMode eq 'absent'
                        )
                        and (  $shutters->getStatus == $shutters->getClosedPos
                            or $shutters->getStatus ==
                            $shutters->getShadingPos )
                      )
                    {
                        $shutters->setLastDrive(
                            (
                                $shutters->getStatus == $shutters->getClosedPos
                                ? 'roommate home'
                                : 'shading out'
                            )
                        );
                        $posValue = $shutters->getOpenPos;

                        ShuttersCommandSet( $hash, $shuttersDev, $posValue );
                    }
                }
            }
        }
        elsif ( ( $1 eq 'gotosleep' or $1 eq 'asleep' )
            and $ascDev->getAutoShuttersControlEvening eq 'on'
            and IsAfterShuttersManualBlocking($shuttersDev) )
        {
            $shutters->setLastDrive('roommate asleep');

            if ( CheckIfShuttersWindowRecOpen($shuttersDev) == 0
                or $shutters->getVentilateOpen eq 'off' )
            {
                $posValue = $shutters->getClosedPos;
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
            and ( not $shutters->getIsDay
                or $shutters->getShadingMode eq 'absent' )
          )
        {
            if (    $shutters->getIsDay
                and $shutters->getIfInShading
                and
                not $shutters->getQueryShuttersPos( $shutters->getShadingPos )
                and $shutters->getShadingMode eq 'absent' )
            {
                $posValue = $shutters->getShadingPos;
                $shutters->setLastDrive('shading in');
                ShuttersCommandSet( $hash, $shuttersDev, $posValue );
            }
            elsif ( not $shutters->getIsDay
                and $getModeDown eq 'absent'
                and $getRoommatesStatus eq 'absent' )
            {
                $posValue = $shutters->getClosedPos;
                $shutters->setLastDrive('roommate absent');
                ShuttersCommandSet( $hash, $shuttersDev, $posValue );
            }
        }
    }
}

sub EventProcessingResidents($@) {
    my ( $hash, $device, $events ) = @_;

    my $name                   = $device;
    my $reading                = $ascDev->getResidentsReading;
    my $getResidentsLastStatus = $ascDev->getResidentsLastStatus;

    if ( $events =~ m#$reading:\s((?:pet_[a-z]+)|(?:absent))# ) {
        foreach my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
            $shutters->setShuttersDev($shuttersDev);
            my $getModeUp   = $shutters->getModeUp;
            my $getModeDown = $shutters->getModeDown;
            $shutters->setHardLockOut('off');
            if (
                    $ascDev->getSelfDefense eq 'on'
                and $shutters->getSelfDefenseExclude eq 'off'
                or (   $getModeDown eq 'absent'
                    or $getModeDown eq 'always' )
              )
            {
                if (
                    (
                        CheckIfShuttersWindowRecOpen($shuttersDev) != 0
                        or $shutters->getSelfDefenseMode eq 'absent'
                    )
                    and $ascDev->getSelfDefense eq 'on'
                    and $shutters->getSelfDefenseExclude eq 'off'
                  )
                {
                    $shutters->setLastDrive('selfDefense active');
                    $shutters->setSelfDefenseAbsent( 0, 1
                      ) # der erste Wert ist ob der timer schon läuft, der zweite ist ob self defense aktiv ist durch die Bedingungen
                      if ( CheckIfShuttersWindowRecOpen($shuttersDev) == 0
                        and $shutters->getSelfDefenseMode eq 'absent' );
                    $shutters->setDriveCmd( $shutters->getClosedPos );
                }
                elsif (
                    (
                           $getModeDown eq 'absent'
                        or $getModeDown eq 'always'
                    )
                    and not $shutters->getIsDay
                    and IsAfterShuttersTimeBlocking($shuttersDev)
                    and $shutters->getRoommatesStatus eq 'none'
                  )
                {
                    $shutters->setLastDrive('residents absent');
                    $shutters->setDriveCmd( $shutters->getClosedPos );
                }
            }
        }
    }
    elsif ( $events =~ m#$reading:\s(gone)#
        and $ascDev->getSelfDefense eq 'on'
        and $shutters->getSelfDefenseMode eq 'gone'
        and $shutters->getSelfDefenseExclude eq 'off' )
    {
        foreach my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
            $shutters->setShuttersDev($shuttersDev);
            my $getModeUp   = $shutters->getModeUp;
            my $getModeDown = $shutters->getModeDown;
            $shutters->setHardLockOut('off');
            if ( $shutters->getShuttersPlace eq 'terrace' ) {
                $shutters->setLastDrive('selfDefense terrace');
                $shutters->setDriveCmd( $shutters->getClosedPos );
            }
        }
    }
    elsif (
        $events =~ m#$reading:\s((?:[a-z]+_)?home)#
        and (  $getResidentsLastStatus eq 'absent'
            or $getResidentsLastStatus eq 'gone'
            or $getResidentsLastStatus eq 'asleep'
            or $getResidentsLastStatus eq 'awoken' )
      )
    {
        foreach my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
            $shutters->setShuttersDev($shuttersDev);
            my $getModeUp   = $shutters->getModeUp;
            my $getModeDown = $shutters->getModeDown;

            if (
                    $shutters->getStatus != $shutters->getClosedPos
                and not $shutters->getIsDay
                and $shutters->getRoommatesStatus eq 'none'
                and (  $getModeDown eq 'home'
                    or $getModeDown eq 'always' )
                and (  $getResidentsLastStatus ne 'asleep'
                    or $getResidentsLastStatus ne 'awoken' )
                and IsAfterShuttersTimeBlocking($shuttersDev)
                and $shutters->getRoommatesStatus eq 'none'
              )
            {
                $shutters->setLastDrive('residents home');
                $shutters->setDriveCmd( $shutters->getClosedPos );
            }
            elsif (
                (
                       $shutters->getShadingMode eq 'home'
                    or $shutters->getShadingMode eq 'always'
                )
                and $shutters->getIsDay
                and $shutters->getIfInShading
                and $shutters->getRoommatesStatus eq 'none'
                and $shutters->getStatus != $shutters->getShadingPos
                and not $shutters->getShadingManualDriveStatus
                and not( CheckIfShuttersWindowRecOpen($shuttersDev) == 2
                    and $shutters->getShuttersPlace eq 'terrace' )
              )
            {
                $shutters->setLastDrive('shading in');
                $shutters->setDriveCmd( $shutters->getShadingPos );
            }
            elsif (
                    $shutters->getShadingMode eq 'absent'
                and $shutters->getIsDay
                and $shutters->getIfInShading
                and $shutters->getStatus == $shutters->getShadingPos
                and $shutters->getRoommatesStatus eq 'none'
                and not $shutters->getShadingManualDriveStatus
                and not( CheckIfShuttersWindowRecOpen($shuttersDev) == 2
                    and $shutters->getShuttersPlace eq 'terrace' )
              )
            {
                $shutters->setLastDrive('shading out');
                $shutters->setDriveCmd( $shutters->getLastPos );
            }
            elsif (
                (
                        $ascDev->getSelfDefense eq 'on'
                    and $shutters->getSelfDefenseExclude eq 'off'
                    or (    $getResidentsLastStatus eq 'gone'
                        and $shutters->getShuttersPlace eq 'terrace' )
                )
                and not $shutters->getIfInShading
                and (  $getResidentsLastStatus eq 'gone'
                    or $getResidentsLastStatus eq 'absent' )
                and $shutters->getLastDrive eq 'selfDefense active'
              )
            {
                RemoveInternalTimer( $shutters->getSelfDefenseAbsentTimerhash )
                  if (  $getResidentsLastStatus eq 'absent'
                    and $ascDev->getSelfDefense eq 'on'
                    and $shutters->getSelfDefenseExclude eq 'off'
                    and CheckIfShuttersWindowRecOpen($shuttersDev) == 0
                    and not $shutters->getSelfDefenseAbsent
                    and $shutters->getSelfDefenseAbsentTimerrun );

                if (    $shutters->getStatus == $shutters->getClosedPos
                    and $shutters->getIsDay )
                {
                    $shutters->setHardLockOut('on')
                      if (
                            CheckIfShuttersWindowRecOpen($shuttersDev) == 2
                        and $shutters->getShuttersPlace eq 'terrace'
                        and (  $getModeUp eq 'absent'
                            or $getModeUp eq 'off' )
                      );

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
                    $shutters->getStatus == $shutters->getClosedPos
                and $shutters->getIsDay
                and $shutters->getRoommatesStatus eq 'none'
                and (  $getModeUp eq 'home'
                    or $getModeUp eq 'always' )
                and IsAfterShuttersTimeBlocking($shuttersDev)
                and $shutters->getRoommatesStatus eq 'none'
                and not $shutters->getIfInShading
              )
            {
                if (   $getResidentsLastStatus eq 'asleep'
                    or $getResidentsLastStatus eq 'awoken' )
                {
                    $shutters->setLastDrive('residents awoken');
                }
                else { $shutters->setLastDrive('residents home'); }
                $shutters->setDriveCmd( $shutters->getOpenPos );
            }
        }
    }
}

sub EventProcessingRain($@) {
    my ( $hash, $device, $events ) = @_;
    my $name    = $device;
    my $reading = $ascDev->getRainSensorReading;

    if ( $events =~ m#$reading:\s(\d+(\.\d+)?|rain|dry)# ) {
        my $val;
        my $triggerMax = $ascDev->getRainTriggerMax;
        my $triggerMin = $ascDev->getRainTriggerMin;
        my $closedPos  = $ascDev->getRainSensorShuttersClosedPos;

        if    ( $1 eq 'rain' ) { $val = $triggerMax + 1 }
        elsif ( $1 eq 'dry' )  { $val = $triggerMin }
        else                   { $val = $1 }

        foreach my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
            $shutters->setShuttersDev($shuttersDev);

            next
              if ( $shutters->getRainProtection eq 'off' );

            if (    $val > $triggerMax
                and $shutters->getStatus != $closedPos
                and IsAfterShuttersManualBlocking($shuttersDev)
                and $shutters->getRainProtectionStatus eq 'unprotected' )
            {
                $shutters->setLastDrive('rain protected');
                $shutters->setDriveCmd($closedPos);
                $shutters->setRainProtectionStatus('protected');
            }
            elsif ( ( $val == 0 or $val < $triggerMax )
                and $shutters->getStatus == $closedPos
                and IsAfterShuttersManualBlocking($shuttersDev)
                and $shutters->getRainProtectionStatus eq 'protected' )
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
    }
}

sub EventProcessingWind($@) {
    my ( $hash, $shuttersDev, $events ) = @_;
    my $name = $hash->{NAME};
    $shutters->setShuttersDev($shuttersDev);

    my $reading = $ascDev->getWindSensorReading;
    if ( $events =~ m#$reading:\s(\d+(\.\d+)?)# ) {
        foreach my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
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
                    and $shutters->getShuttersPlace eq 'terrace'
                )
                or $shutters->getWindProtection eq 'off'
              );

            if (    $1 > $shutters->getWindMax
                and $shutters->getWindProtectionStatus eq 'unprotected' )
            {
                $shutters->setLastDrive('wind protected');
                $shutters->setDriveCmd( $shutters->getWindPos );
                $shutters->setWindProtectionStatus('protected');
            }
            elsif ( $1 < $shutters->getWindMin
                and $shutters->getWindProtectionStatus eq 'protected' )
            {
                $shutters->setLastDrive('wind un-protected');
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
}
##########

sub EventProcessingBrightness($@) {
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
            or $shutters->getUp eq 'brightness'
        )
        or (
            (
                (
                    (
                        int( gettimeofday() / 86400 ) != int(
                            computeAlignTime( '24:00',
                                $shutters->getTimeUpEarly ) / 86400
                        )
                        and (
                            not IsWe()
                            or ( IsWe()
                                and $ascDev->getSunriseTimeWeHoliday eq 'off' )
                        )
                    )
                    or (
                        int( gettimeofday() / 86400 ) != int(
                            computeAlignTime( '24:00',
                                $shutters->getTimeUpWeHoliday ) / 86400
                        )
                        and IsWe()
                        and $ascDev->getSunriseTimeWeHoliday eq 'on'
                    )
                )
                and int( gettimeofday() / 86400 ) == int(
                    computeAlignTime( '24:00', $shutters->getTimeUpLate ) /
                      86400
                )
            )
            or (
                int( gettimeofday() / 86400 ) != int(
                    computeAlignTime( '24:00', $shutters->getTimeDownEarly ) /
                      86400
                )
                and int( gettimeofday() / 86400 ) == int(
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
    if ( $events =~ m#$reading:\s(\d+(\.\d+)?)# ) {
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
                        and (
                            not IsWe()
                            or ( IsWe()
                                and $ascDev->getSunriseTimeWeHoliday eq 'off' )
                        )
                    )
                    or (
                        int( gettimeofday() / 86400 ) != int(
                            computeAlignTime( '24:00',
                                $shutters->getTimeUpWeHoliday ) / 86400
                        )
                        and IsWe()
                        and $ascDev->getSunriseTimeWeHoliday eq 'on'
                    )
                )
                and int( gettimeofday() / 86400 ) == int(
                    computeAlignTime( '24:00', $shutters->getTimeUpLate ) /
                      86400
                )
            )
            and $1 > $brightnessMaxVal
            and $shutters->getUp eq 'brightness'
            and not $shutters->getSunrise
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
                or (    $shutters->getModeUp eq 'absent'
                    and $homemode eq 'gone' )
                or $shutters->getModeUp eq 'always'
              )
            {
                if (
                    (
                           $shutters->getRoommatesStatus eq 'home'
                        or $shutters->getRoommatesStatus eq 'awoken'
                        or $shutters->getRoommatesStatus eq 'absent'
                        or $shutters->getRoommatesStatus eq 'gone'
                        or $shutters->getRoommatesStatus eq 'none'
                    )
                    and $ascDev->getSelfDefense eq 'off'
                    or ( $ascDev->getSelfDefense eq 'on'
                        and CheckIfShuttersWindowRecOpen($shuttersDev) == 0 )
                    or (    $ascDev->getSelfDefense eq 'on'
                        and CheckIfShuttersWindowRecOpen($shuttersDev) != 0
                        and $ascDev->getResidentsStatus eq 'home' )
                  )
                {
                    $shutters->setLastDrive(
                        'maximum brightness threshold exceeded');
                    $shutters->setSunrise(1);
                    $shutters->setSunset(0);
                    ShuttersCommandSet( $hash, $shuttersDev,
                        $shutters->getOpenPos );

                    ASC_Debug( 'EventProcessingBrightness: '
                          . $shutters->getShuttersDev
                          . ' - Verarbeitung für Sunrise. Roommatestatus korrekt zum fahren. Fahrbefehl wird an die Funktion FnShuttersCommandSet gesendet. Grund des fahrens: '
                          . $shutters->getLastDrive );
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
            and int( gettimeofday() / 86400 ) == int(
                computeAlignTime( '24:00', $shutters->getTimeDownLate ) / 86400
            )
            and $1 < $brightnessMinVal
            and $shutters->getDown eq 'brightness'
            and not $shutters->getSunset
            and IsAfterShuttersManualBlocking($shuttersDev)
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
                or (    $shutters->getModeDown eq 'absent'
                    and $homemode eq 'gone' )
                or $shutters->getModeDown eq 'always'
              )
            {
                my $posValue;
                if (    CheckIfShuttersWindowRecOpen($shuttersDev) == 2
                    and $shutters->getSubTyp eq 'threestate'
                    and $ascDev->getAutoShuttersControlComfort eq 'on' )
                {
                    $posValue = $shutters->getComfortOpenPos;
                }
                elsif ( CheckIfShuttersWindowRecOpen($shuttersDev) == 0
                    or $shutters->getVentilateOpen eq 'off' )
                {
                    $posValue = $shutters->getClosedPos;
                }
                else { $posValue = $shutters->getVentilatePos; }

                $shutters->setLastDrive(
                    'minimum brightness threshold fell below');
                $shutters->setSunrise(0);
                $shutters->setSunset(1);
                ShuttersCommandSet( $hash, $shuttersDev, $posValue );

                ASC_Debug( 'EventProcessingBrightness: '
                      . $shutters->getShuttersDev
                      . ' - Verarbeitung für Sunset. Roommatestatus korrekt zum fahren. Fahrbefehl wird an die Funktion FnShuttersCommandSet gesendet. Zielposition: '
                      . $posValue
                      . ' Grund des fahrens: '
                      . $shutters->getLastDrive );
            }
            else {
                EventProcessingShadingBrightness( $hash, $shuttersDev,
                    $events );
                ASC_Debug( 'EventProcessingBrightness: '
                      . $shutters->getShuttersDev
                      . ' - Verarbeitung für Sunset. Roommatestatus nicht zum runter fahren. Fahrbebehl bleibt aus!!! Es wird an die Event verarbeitende Beschattungsfunktion weiter gereicht'
                );
            }
        }
        else {
            EventProcessingShadingBrightness( $hash, $shuttersDev, $events );
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
}

sub EventProcessingShadingBrightness($@) {
    my ( $hash, $shuttersDev, $events ) = @_;
    my $name = $hash->{NAME};
    $shutters->setShuttersDev($shuttersDev);
    my $reading = $shutters->getBrightnessReading;
    my $outTemp = $ascDev->getOutTemp;

    Log3( $name, 4,
        "AutoShuttersControl ($shuttersDev) - EventProcessingShadingBrightness"
    );

    ASC_Debug( 'EventProcessingShadingBrightness: '
          . $shutters->getShuttersDev
          . ' - Es wird nun geprüft ob der übergebene Event ein nummerischer Wert vom Brightnessreading ist.'
    );

    if ( $events =~ m#$reading:\s(\d+(\.\d+)?)# ) {
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

        if (    $ascDev->getAutoShuttersControlShading eq 'on'
            and $shutters->getRainProtectionStatus eq 'unprotected'
            and $shutters->getWindProtectionStatus eq 'unprotected' )
        {
            $outTemp = $shutters->getOutTemp
              if ( $shutters->getOutTemp != -100 );
            ShadingProcessing(
                $hash,
                $shuttersDev,
                $ascDev->getAzimuth,
                $ascDev->getElevation,
                $outTemp,
                $shutters->getDirection,
                $shutters->getShadingAngleLeft,
                $shutters->getShadingAngleRight
            );

            ASC_Debug( 'EventProcessingShadingBrightness: '
                  . $shutters->getShuttersDev
                  . ' - Alle Bedingungen zur weiteren Beschattungsverarbeitung sind erfüllt. Es wird nun die eigentliche Beschattungsfunktion aufgerufen'
            );
        }
    }
}

sub EventProcessingTwilightDevice($@) {
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

    if ( $events =~ m#(azimuth|elevation|SunAz|SunAlt):\s(\d+.\d+)# ) {
        my $name = $device;
        my ( $azimuth, $elevation );
        my $outTemp = $ascDev->getOutTemp;

        $azimuth   = $2 if ( $1 eq 'azimuth'   or $1 eq 'SunAz' );
        $elevation = $2 if ( $1 eq 'elevation' or $1 eq 'SunAlt' );

        $azimuth = $ascDev->getAzimuth
          if ( not defined($azimuth) and not $azimuth );
        $elevation = $ascDev->getElevation
          if ( not defined($elevation) and not $elevation );

        ASC_Debug( 'EventProcessingTwilightDevice: '
              . $name
              . ' - Passendes Event wurde erkannt. Verarbeitung über alle Rollos beginnt'
        );

        foreach my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
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

            if (    $ascDev->getAutoShuttersControlShading eq 'on'
                and $shutters->getRainProtectionStatus eq 'unprotected'
                and $shutters->getWindProtectionStatus eq 'unprotected' )
            {
                ShadingProcessing(
                    $hash,
                    $shuttersDev,
                    $azimuth,
                    $elevation,
                    $outTemp,
                    $shutters->getDirection,
                    $shutters->getShadingAngleLeft,
                    $shutters->getShadingAngleRight
                );

                ASC_Debug( 'EventProcessingTwilightDevice: '
                      . $shutters->getShuttersDev
                      . ' - Alle Bedingungen zur weiteren Beschattungsverarbeitung sind erfüllt. Es wird nun die Beschattungsfunktion ausgeführt'
                );
            }
        }
    }
}

sub ShadingProcessing($@) {
### angleMinus ist $shutters->getShadingAngleLeft
### anglePlus ist $shutters->getShadingAngleRight
### winPos ist die Fensterposition $shutters->getDirection
    my ( $hash, $shuttersDev, $azimuth, $elevation, $outTemp,
        $winPos, $angleMinus, $anglePlus )
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
          . ', Fenster Position: '
          . $winPos
          . ', Winkel Links: '
          . $angleMinus
          . ', Winkel Rechts: '
          . $anglePlus
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
        or $elevation == -1
        or $brightness == -1
        or $outTemp == -100
        or ( int( gettimeofday() ) - $shutters->getShadingStatusTimestamp ) <
        ( $shutters->getShadingWaitingPeriod / 2 )
        or $shutters->getShadingMode eq 'off' );

    Log3( $name, 4,
            "AutoShuttersControl ($name) - Shading Processing, Rollladen: "
          . $shuttersDev
          . " Nach dem return" );

    my $getShadingPos    = $shutters->getShadingPos;
    my $getStatus        = $shutters->getStatus;
    my $oldShadingStatus = $shutters->getShadingStatus;

    ASC_Debug( 'ShadingProcessing: '
          . $shutters->getShuttersDev
          . ' - Alle Werte für die weitere Verarbeitung sind korrekt vorhanden und es wird nun mit der Beschattungsverarbeitung begonnen'
    );

# minimalen und maximalen Winkel des Fensters bestimmen. wenn die aktuelle Sonnenposition z.B. bei 205° läge und der Wert für angleMin/Max 85° wäre, dann würden zwischen 120° und 290° beschattet.
    my $winPosMin = $winPos - $angleMinus;
    my $winPosMax = $winPos + $anglePlus;

    if (
        (
               $outTemp < $shutters->getShadingMinOutsideTemperature - 3
            or $azimuth < $winPosMin
            or $azimuth > $winPosMax
        )
        and $shutters->getShadingStatus ne 'out'
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
    elsif ($azimuth < $winPosMin
        or $azimuth > $winPosMax
        or $elevation < $shutters->getShadingMinElevation
        or $elevation > $shutters->getShadingMaxElevation
        or $brightness < $shutters->getShadingStateChangeCloudy
        or $outTemp < $shutters->getShadingMinOutsideTemperature )
    {
        $shutters->setShadingStatus('out reserved')
          if ( $shutters->getShadingStatus eq 'in'
            or $shutters->getShadingStatus eq 'in reserved' );

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
    elsif ( $azimuth > $winPosMin
        and $azimuth < $winPosMax
        and $elevation > $shutters->getShadingMinElevation
        and $elevation < $shutters->getShadingMaxElevation
        and $brightness > $shutters->getShadingStateChangeSunny
        and $outTemp > $shutters->getShadingMinOutsideTemperature )
    {
        $shutters->setShadingStatus('in reserved')
          if ( $shutters->getShadingStatus eq 'out'
            or $shutters->getShadingStatus eq 'out reserved' );

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
            $shutters->getIsDay
        and IsAfterShuttersTimeBlocking($shuttersDev)
        and not $shutters->getShadingManualDriveStatus
        and (
            (
                    $shutters->getShadingStatus eq 'out'
                and $shutters->getShadingLastStatus eq 'in'
            )
            or (    $shutters->getShadingStatus eq 'in'
                and $shutters->getShadingLastStatus eq 'out' )
        )
      );
}

sub ShadingProcessingDriveCommand($$) {
    my ( $hash, $shuttersDev ) = @_;

    my $name = $hash->{NAME};
    $shutters->setShuttersDev($shuttersDev);

    my $getShadingPos = $shutters->getShadingPos;
    my $getStatus     = $shutters->getStatus;

    my $homemode = $shutters->getRoommatesStatus;
    $homemode = $ascDev->getResidentsStatus if ( $homemode eq 'none' );

    if (   $shutters->getShadingMode eq 'always'
        or $shutters->getShadingMode eq $homemode )
    {
        $shutters->setShadingStatus( $shutters->getShadingStatus )
          if (
            ( int( gettimeofday() ) - $shutters->getShadingStatusTimestamp ) >
            ( $shutters->getShadingWaitingPeriod / 2 ) );

        if (    $shutters->getShadingStatus eq 'in'
            and $getShadingPos != $getStatus )
        {
            if (
                not $shutters->getQueryShuttersPos($getShadingPos)
                and not( CheckIfShuttersWindowRecOpen($shuttersDev) == 2
                    and $shutters->getShuttersPlace eq 'terrace' )
              )
            {
                $shutters->setLastDrive('shading in');
                ShuttersCommandSet( $hash, $shuttersDev, $getShadingPos );

                ASC_Debug( 'ShadingProcessing: '
                      . $shutters->getShuttersDev
                      . ' - Der aktuelle Beschattungsstatus ist: '
                      . $shutters->getShadingStatus
                      . ' und somit wird nun in die Position: '
                      . $getShadingPos
                      . ' zum Beschatten gefahren' );
            }
        }
        elsif ( $shutters->getShadingStatus eq 'out'
            and $getShadingPos == $getStatus )
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
                        ? $shutters->getLastPos
                        : $shutters->getOpenPos
                    )
                )
            );

            ASC_Debug( 'ShadingProcessing: '
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
                'ShadingProcessing: '
              . $shutters->getShuttersDev
              . ' - Der aktuelle Beschattungsstatus ist: '
              . $shutters->getShadingStatus
              . ', Beschattungsstatus Zeitstempel: '
              . strftime(
                "%Y.%m.%e %T", localtime( $shutters->getShadingStatusTimestamp )
              )
        );
    }
}

sub EventProcessingPartyMode($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    foreach my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
        $shutters->setShuttersDev($shuttersDev);
        next
          if ( $shutters->getPartyMode eq 'off' );

        if (    not $shutters->getIsDay
            and $shutters->getModeDown ne 'off'
            and IsAfterShuttersManualBlocking($shuttersDev) )
        {
            if ( CheckIfShuttersWindowRecOpen($shuttersDev) == 2
                and $shutters->getSubTyp eq 'threestate' )
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
        elsif ( $shutters->getIsDay
            and IsAfterShuttersManualBlocking($shuttersDev) )
        {
            $shutters->setLastDrive('drive after party mode');
            ShuttersCommandSet( $hash, $shuttersDev, $shutters->getDelayCmd );
        }
    }
}

sub EventProcessingShutters($@) {
    my ( $hash, $shuttersDev, $events ) = @_;
    my $name = $hash->{NAME};

    ASC_Debug( 'EventProcessingShutters: '
          . ' Fn wurde durch Notify aufgerufen da ASC_Pos_Reading Event erkannt wurde '
          . ' - RECEIVED EVENT: '
          . Dumper $events);

    if ( $events =~ m#.*:\s(\d+)# ) {
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
            and ( int( gettimeofday() ) - $shutters->getLastManPosTimestamp ) >
            $shutters->getDriveUpMaxDuration )
        {
            $shutters->setLastDrive('manual');
            $shutters->setLastDriveReading;
            $ascDev->setStateReading;
            $shutters->setLastManPos($1);

            $shutters->setShadingManualDriveStatus(1)
              if (  $shutters->getIsDay
                and $shutters->getIfInShading );

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
}

# Sub für das Zusammensetzen der Rolläden Steuerbefehle
sub ShuttersCommandSet($$$) {
    my ( $hash, $shuttersDev, $posValue ) = @_;
    my $name = $hash->{NAME};
    $shutters->setShuttersDev($shuttersDev);

    if (
        $posValue != $shutters->getShadingPos
        and (
            (
                    $shutters->getPartyMode eq 'on'
                and $ascDev->getPartyMode eq 'on'
            )
            or (
                    CheckIfShuttersWindowRecOpen($shuttersDev) == 2
                and $shutters->getSubTyp eq 'threestate'
                and (  $ascDev->getAutoShuttersControlComfort eq 'off'
                    or $shutters->getComfortOpenPos != $posValue )
                and $shutters->getVentilateOpen eq 'on'
                and $shutters->getShuttersPlace eq 'window'
                and $shutters->getLockOut ne 'off'
            )
            or (    CheckIfShuttersWindowRecOpen($shuttersDev) == 2
                and $shutters->getSubTyp eq 'threestate'
                and $ascDev->getAutoShuttersControlComfort eq 'on'
                and $shutters->getVentilateOpen eq 'off'
                and $shutters->getShuttersPlace eq 'window'
                and $shutters->getLockOut ne 'off' )
            or (
                CheckIfShuttersWindowRecOpen($shuttersDev) == 2
                and (  $shutters->getLockOut eq 'soft'
                    or $shutters->getLockOut eq 'hard' )
                and not $shutters->getQueryShuttersPos($posValue)
            )
            or (    CheckIfShuttersWindowRecOpen($shuttersDev) == 2
                and $shutters->getShuttersPlace eq 'terrace'
                and not $shutters->getQueryShuttersPos($posValue) )
            or (    $shutters->getRainProtectionStatus eq 'protected'
                and $shutters->getWindProtectionStatus eq 'protected' )
        )
      )
    {
        $shutters->setDelayCmd($posValue);
        $ascDev->setDelayCmdReading;
        $shutters->setNoOffset(0);
        Log3( $name, 4,
            "AutoShuttersControl ($name) - ShuttersCommandSet in Delay" );

        ASC_Debug( 'FnShuttersCommandSet: '
              . $shutters->getShuttersDev
              . ' - Die Fahrt wird zurückgestellt. Grund kann ein geöffnetes Fenster sein oder ein aktivierter Party Modus'
        );
    }
    else {
        $shutters->setDriveCmd($posValue);
        $shutters->setDelayCmd('none')
          if ( $shutters->getDelayCmd ne 'none' )
          ; # setzt den Wert auf none da der Rolladen nun gesteuert werden kann.
        $ascDev->setLastPosReading;
        Log3( $name, 4,
"AutoShuttersControl ($name) - ShuttersCommandSet setDriveCmd wird aufgerufen"
        );

        ASC_Debug( 'FnShuttersCommandSet: '
              . $shutters->getShuttersDev
              . ' - Das Rollo wird gefahren. Kein Partymodus aktiv und das zugordnete Fenster ist entweder nicht offen oder keine Terassentür'
        );
    }
}

## Sub welche die InternalTimer nach entsprechenden Sunset oder Sunrise zusammen stellt
sub CreateSunRiseSetShuttersTimer($$) {
    my ( $hash, $shuttersDev ) = @_;
    my $name            = $hash->{NAME};
    my $shuttersDevHash = $defs{$shuttersDev};
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

    ## kleine Hilfe für InternalTimer damit ich alle benötigten Variablen an die Funktion übergeben kann welche von Internal Timer aufgerufen wird.
    my %funcHash = (
        hash           => $hash,
        shuttersdevice => $shuttersDev,
        sunsettime     => $shuttersSunsetUnixtime,
        sunrisetime    => $shuttersSunriseUnixtime
    );

    ## Setzt den PrivacyDown Modus für die Sichtschutzfahrt auf den Status 0
    ##  1 bedeutet das PrivacyDown Timer aktiviert wurde, 2 beudet das er im privacyDown ist
    ##  also das Rollo in privacyDown Position steht und VOR der endgültigen Nachfahrt
    $shutters->setPrivacyDownStatus(0)
      if ( not defined( $shutters->getPrivacyDownStatus ) );

    ## Ich brauche beim löschen des InternalTimer den Hash welchen ich mitgegeben habe,dieser muss gesichert werden
    $shutters->setInTimerFuncHash( \%funcHash );

    ## Abfrage für die Sichtschutzfahrt am Abend vor dem eigentlichen kompletten schließen
    if ( $shutters->getPrivacyDownTime > 0 ) {
        if ( ( $shuttersSunsetUnixtime - $shutters->getPrivacyDownTime ) >
            ( gettimeofday() + 1 ) )
        {
            $shuttersSunsetUnixtime =
              $shuttersSunsetUnixtime - $shutters->getPrivacyDownTime;
            readingsSingleUpdate(
                $shuttersDevHash,
                'ASC_Time_PrivacyDriveDown',
                strftime(
                    "%e.%m.%Y - %H:%M",
                    localtime($shuttersSunsetUnixtime)
                ),
                0
            );
            ## Setzt den PrivacyDown Modus für die Sichtschutzfahrt auf den Status 1
            $shutters->setPrivacyDownStatus(1);
        }
    }
    else {
        CommandDeleteReading( undef,
            $shuttersDev . ' ASC_Time_PrivacyDriveDown' )
          if (
            ReadingsVal( $shuttersDev, 'ASC_Time_PrivacyDriveDown', 'none' ) );
    }

    InternalTimer( $shuttersSunsetUnixtime,
        'FHEM::AutoShuttersControl::SunSetShuttersAfterTimerFn', \%funcHash );
    InternalTimer( $shuttersSunriseUnixtime,
        'FHEM::AutoShuttersControl::SunRiseShuttersAfterTimerFn', \%funcHash );

    $ascDev->setStateReading('created new drive timer');
}

## Funktion zum neu setzen der Timer und der Readings für Sunset/Rise
sub RenewSunRiseSetShuttersTimer($) {
    my $hash = shift;

    foreach ( @{ $hash->{helper}{shuttersList} } ) {
        $shutters->setShuttersDev($_);

        RemoveInternalTimer( $shutters->getInTimerFuncHash );
        $shutters->setInTimerFuncHash(undef);
        CreateSunRiseSetShuttersTimer( $hash, $_ );

        #### Temporär angelegt damit die neue Attributs Parameter Syntax verteilt werden kann
        #### Gleichlautende Attribute wo lediglich die Parameter geändert werden sollen müssen bereits in der Funktion ShuttersDeviceScan gelöscht werden
        #### vorher empfiehlt es sich die dort vergebenen Parameter aus zu lesen um sie dann hier wieder neu zu setzen. Dazu wird das shutters Objekt um einen Eintrag
        #### 'AttrUpdateChanges' erweitert
        if ( ( int( gettimeofday() ) - $::fhem_started ) < 20
            and
            ReadingsVal( $_, '.ASC_AttrUpdateChanges_' . $hash->{VERSION}, 0 )
            == 0 )
        {
            $attr{$_}{'ASC_Up'} = $shutters->getAttrUpdateChanges('ASC_Up')
              if ( $shutters->getAttrUpdateChanges('ASC_Up') ne 'none' );
            $attr{$_}{'ASC_Down'} = $shutters->getAttrUpdateChanges('ASC_Down')
              if ( $shutters->getAttrUpdateChanges('ASC_Down') ne 'none' );

            CommandDeleteReading( undef, $_ . ' .ASC_AttrUpdateChanges_.*' )
              if (
                ReadingsVal( $_, '.ASC_AttrUpdateChanges_' . $hash->{VERSION},
                    'none' ) eq 'none'
              );
            readingsSingleUpdate( $defs{$_},
                '.ASC_AttrUpdateChanges_' . $hash->{VERSION},
                1, 0 );

#             $attr{$_}{'ASC_Shading_MinMax_Elevation'} =
#                 AttrVal( $_, 'ASC_Shading_Min_Elevation', 'none' )
#                 if ( AttrVal( $_, 'ASC_Shading_Min_Elevation', 'none' ) ne 'none' );
#
#             delFromDevAttrList( $_, 'ASC_Shading_Min_Elevation' )
#                 ;    # temporär muss später gelöscht werden ab Version 0.6.17
        }
    }
}

## Funktion zum hardwareseitigen setzen des lock-out oder blocking beim Rolladen selbst
sub HardewareBlockForShutters($$) {
    my ( $hash, $cmd ) = @_;
    foreach ( @{ $hash->{helper}{shuttersList} } ) {
        $shutters->setShuttersDev($_);
        $shutters->setHardLockOut($cmd);
    }
}

## Funktion für das wiggle aller Shutters zusammen
sub wiggleAll($) {
    my $hash = shift;

    foreach ( @{ $hash->{helper}{shuttersList} } ) {
        wiggle( $hash, $_ );
    }
}

sub wiggle($$) {
    my ( $hash, $shuttersDev ) = @_;
    $shutters->setShuttersDev($shuttersDev);
    $shutters->setNoOffset(1);
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

    InternalTimer( gettimeofday() + 60,
        'FHEM::AutoShuttersControl::_SetCmdFn', \%h );
}
####

## Funktion welche beim Ablaufen des Timers für Sunset aufgerufen werden soll
sub SunSetShuttersAfterTimerFn($) {
    my $funcHash    = shift;
    my $hash        = $funcHash->{hash};
    my $shuttersDev = $funcHash->{shuttersdevice};
    $shutters->setShuttersDev($shuttersDev);

    $shutters->setSunset(1);
    $shutters->setSunrise(0);

    my $homemode = $shutters->getRoommatesStatus;
    $homemode = $ascDev->getResidentsStatus if ( $homemode eq 'none' );

    if (
            $shutters->getDown ne 'roommate'
        and $ascDev->getAutoShuttersControlEvening eq 'on'
        and IsAfterShuttersManualBlocking($shuttersDev)
        and (
            $shutters->getModeDown eq $homemode
            or (    $shutters->getModeDown eq 'absent'
                and $homemode eq 'gone' )
            or $shutters->getModeDown eq 'always'
        )
        and (
               $ascDev->getSelfDefense eq 'off'
            or $shutters->getSelfDefenseExclude eq 'on'
            or (
                $ascDev->getSelfDefense eq 'on'
                and (  $ascDev->getResidentsStatus ne 'absent'
                    or $ascDev->getResidentsStatus ne 'gone' )
            )
        )
      )
    {

        if ( $shutters->getPrivacyDownStatus == 1 ) {
            $shutters->setPrivacyDownStatus(2);
            $shutters->setLastDrive('privacy position');
            ShuttersCommandSet( $hash, $shuttersDev,
                $shutters->getPrivacyDownPos )
              unless (
                $shutters->getQueryShuttersPos( $shutters->getPrivacyDownPos )
              );
        }
        else {
            $shutters->setPrivacyDownStatus(0);
            $shutters->setLastDrive('night close');
            ShuttersCommandSet( $hash, $shuttersDev,
                PositionValueWindowRec( $shuttersDev, $shutters->getClosedPos )
            );
        }
    }

    CreateSunRiseSetShuttersTimer( $hash, $shuttersDev );
}

## Funktion welche beim Ablaufen des Timers für Sunrise aufgerufen werden soll
sub SunRiseShuttersAfterTimerFn($) {
    my $funcHash    = shift;
    my $hash        = $funcHash->{hash};
    my $shuttersDev = $funcHash->{shuttersdevice};
    $shutters->setShuttersDev($shuttersDev);

    $shutters->setSunset(0);
    $shutters->setSunrise(1);

    my $homemode = $shutters->getRoommatesStatus;
    $homemode = $ascDev->getResidentsStatus if ( $homemode eq 'none' );

    if (
            $shutters->getUp ne 'roommate'
        and $ascDev->getAutoShuttersControlMorning eq 'on'
        and (
            $shutters->getModeUp eq $homemode
            or (    $shutters->getModeUp eq 'absent'
                and $homemode eq 'gone' )
            or $shutters->getModeUp eq 'always'
        )
        and (
               $ascDev->getSelfDefense eq 'off'
            or $shutters->getSelfDefenseExclude eq 'on'
            or (    $ascDev->getSelfDefense eq 'on'
                and $ascDev->getResidentsStatus ne 'absent'
                and $ascDev->getResidentsStatus ne 'gone' )
        )
      )
    {

        if (
            (
                   $shutters->getRoommatesStatus eq 'home'
                or $shutters->getRoommatesStatus eq 'awoken'
                or $shutters->getRoommatesStatus eq 'absent'
                or $shutters->getRoommatesStatus eq 'gone'
                or $shutters->getRoommatesStatus eq 'none'
            )
            and (
                $ascDev->getSelfDefense eq 'off'
                or ( $ascDev->getSelfDefense eq 'on'
                    and CheckIfShuttersWindowRecOpen($shuttersDev) == 0 )
                or (
                        $ascDev->getSelfDefense eq 'on'
                    and CheckIfShuttersWindowRecOpen($shuttersDev) != 0
                    and (  $ascDev->getResidentsStatus ne 'absent'
                        or $ascDev->getResidentsStatus ne 'gone' )
                )
            )
          )
        {
            if ( not $shutters->getIfInShading ) {
                $shutters->setLastDrive('day open');
                ShuttersCommandSet( $hash, $shuttersDev,
                    $shutters->getOpenPos );
            }
            elsif ( $shutters->getIfInShading ) {
                $shutters->setLastDrive('shading in');
                ShuttersCommandSet( $hash, $shuttersDev,
                    $shutters->getShadingPos );
            }
        }
    }

    CreateSunRiseSetShuttersTimer( $hash, $shuttersDev );
}

sub CreateNewNotifyDev($) {
    my $hash = shift;
    my $name = $hash->{NAME};

    $hash->{NOTIFYDEV} = "global," . $name;
    delete $hash->{monitoredDevs};

    CommandDeleteReading( undef, $name . ' .monitoredDevs' );
    my $shuttersList = '';
    foreach ( @{ $hash->{helper}{shuttersList} } ) {
        AddNotifyDev( $hash, AttrVal( $_, 'ASC_Roommate_Device', 'none' ),
            $_, 'ASC_Roommate_Device' )
          if ( AttrVal( $_, 'ASC_Roommate_Device', 'none' ) ne 'none' );
        AddNotifyDev( $hash, AttrVal( $_, 'ASC_WindowRec', 'none' ),
            $_, 'ASC_WindowRec' )
          if ( AttrVal( $_, 'ASC_WindowRec', 'none' ) ne 'none' );
        AddNotifyDev( $hash, AttrVal( $_, 'ASC_BrightnessSensor', 'none' ),
            $_, 'ASC_BrightnessSensor' )
          if ( AttrVal( $_, 'ASC_BrightnessSensor', 'none' ) ne 'none' );

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
}

sub GetShuttersInformation($) {
    my $hash = shift;
    my $ret  = '<html><table><tr><td>';
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
    foreach my $shutter ( @{ $hash->{helper}{shuttersList} } ) {
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
    $ret .= '</table></html>';
    return $ret;
}

sub GetMonitoredDevs($) {
    my $hash       = shift;
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
        foreach my $notifydev ( sort keys( %{$notifydevs} ) ) {
            if ( ref( $notifydevs->{$notifydev} ) eq "HASH" ) {
                foreach
                  my $shutters ( sort keys( %{ $notifydevs->{$notifydev} } ) )
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

sub PositionValueWindowRec($$) {
    my ( $shuttersDev, $posValue ) = @_;

    if ( CheckIfShuttersWindowRecOpen($shuttersDev) == 1
        and $shutters->getVentilateOpen eq 'on' )
    {
        $posValue = $shutters->getVentilatePos;
    }
    elsif ( CheckIfShuttersWindowRecOpen($shuttersDev) == 2
        and $shutters->getSubTyp eq 'threestate'
        and $ascDev->getAutoShuttersControlComfort eq 'on' )
    {
        $posValue = $shutters->getComfortOpenPos;
    }
    elsif (
        CheckIfShuttersWindowRecOpen($shuttersDev) == 2
        and (  $shutters->getSubTyp eq 'threestate'
            or $shutters->getSubTyp eq 'twostate' )
        and $shutters->getVentilateOpen eq 'on'
      )
    {
        $posValue = $shutters->getVentilatePos;
    }

    if ( $shutters->getQueryShuttersPos($posValue) ) {
        $posValue = $shutters->getStatus;
    }

    return $posValue;
}

sub AutoSearchTwilightDev($) {
    my $hash = shift;
    my $name = $hash->{NAME};

    if ( devspec2array('TYPE=(Astro|Twilight)') > 0 ) {
        CommandAttr( undef,
                $name
              . ' ASC_twilightDevice '
              . ( devspec2array('TYPE=(Astro|Twilight)') )[0] )
          if ( AttrVal( $name, 'ASC_twilightDevice', 'none' ) eq 'none' );
    }
}

sub GetAttrValues($@) {
    my ( $dev, $attribut, $default ) = @_;

    my @values = split( ' ',
        AttrVal( $dev, $attribut, ( defined($default) ? $default : 'none' ) ) );
    my ( $value1, $value2 ) = split( ':', $values[0] );
    my ( $value3, $value4 ) = split( ':', $values[1] )
      if ( defined( $values[1] ) );
    my ( $value5, $value6 ) = split( ':', $values[2] )
      if ( defined( $values[2] ) );
    my ( $value7, $value8 ) = split( ':', $values[2] )
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
sub ExtractNotifyDevFromEvent($$$) {
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
            and $hash->{monitoredDevs}{$notifyDev}{$shuttersDev} eq
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
sub _IsDay($) {
    my ($shuttersDev) = @_;
    $shutters->setShuttersDev($shuttersDev);

    my $isday = ( ShuttersSunrise( $shuttersDev, 'unix' ) >
          ShuttersSunset( $shuttersDev, 'unix' ) ? 1 : 0 );
    my $respIsDay = $isday;

    ASC_Debug( 'FnIsDay: ' . $shuttersDev . ' Allgemein: ' . $respIsDay );

    if (
        (
               $shutters->getModeDown eq 'brightness'
            or $shutters->getModeUp eq 'brightness'
        )
        or (
            (
                (
                    (
                        int( gettimeofday() / 86400 ) != int(
                            computeAlignTime( '24:00',
                                $shutters->getTimeUpEarly ) / 86400
                        )
                        and not IsWe()
                    )
                    or (
                        int( gettimeofday() / 86400 ) != int(
                            computeAlignTime( '24:00',
                                $shutters->getTimeUpWeHoliday ) / 86400
                        )
                        and IsWe()
                        and $ascDev->getSunriseTimeWeHoliday eq 'on'
                    )
                )
                and int( gettimeofday() / 86400 ) == int(
                    computeAlignTime( '24:00', $shutters->getTimeUpLate ) /
                      86400
                )
            )
            or (
                int( gettimeofday() / 86400 ) != int(
                    computeAlignTime( '24:00', $shutters->getTimeDownEarly ) /
                      86400
                )
                and int( gettimeofday() / 86400 ) == int(
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
                      and $isday
                      and not $shutters->getSunset
                )
                  or not $shutters->getSunset
            ) ? 1 : 0
        ) if ( $shutters->getDown eq 'brightness' );

        ASC_Debug( 'FnIsDay: '
              . $shuttersDev
              . ' getDownBrightness: '
              . $respIsDay
              . ' Brightness: '
              . $shutters->getBrightness
              . ' BrightnessMin: '
              . $brightnessMinVal
              . ' Sunset: '
              . $shutters->getSunset );

        ##### Nach Sonnenauf / Morgens
        $respIsDay = (
            (
                (
                          $shutters->getBrightness > $brightnessMaxVal
                      and not $isday
                      and not $shutters->getSunrise
                )
                  or $respIsDay
                  or $shutters->getSunrise
            ) ? 1 : 0
        ) if ( $shutters->getUp eq 'brightness' );

        ASC_Debug( 'FnIsDay: '
              . $shuttersDev
              . ' getUpBrightness: '
              . $respIsDay
              . ' Brightness: '
              . $shutters->getBrightness
              . ' BrightnessMax: '
              . $brightnessMaxVal
              . ' Sunrise: '
              . $shutters->getSunrise );
    }

    return $respIsDay;
}

sub ShuttersSunrise($$) {
    my ( $shuttersDev, $tm ) =
      @_;    # Tm steht für Timemode und bedeutet Realzeit oder Unixzeit
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
            if ( ( IsWe() or IsWeTomorrow() )
                and $ascDev->getSunriseTimeWeHoliday eq 'on' )
            {
                if ( not IsWeTomorrow() ) {
                    if (
                        IsWe()
                        and int( gettimeofday() / 86400 ) == int(
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
                        and (
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
                            or int( gettimeofday() / 86400 ) != int(
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
            if (    defined($oldFuncHash)
                and ref($oldFuncHash) eq 'HASH'
                and ( IsWe() or IsWeTomorrow() )
                and $ascDev->getSunriseTimeWeHoliday eq 'on' )
            {
                if ( not IsWeTomorrow() ) {
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
                            and $oldFuncHash->{sunrisetime} < gettimeofday() );
                    }
                }
            }
            elsif ( defined($oldFuncHash) and ref($oldFuncHash) eq 'HASH' ) {
                $shuttersSunriseUnixtime = ( $shuttersSunriseUnixtime + 86400 )
                  if ( $shuttersSunriseUnixtime <
                    ( $oldFuncHash->{sunrisetime} + 180 )
                    and $oldFuncHash->{sunrisetime} < gettimeofday() );
            }
        }
        elsif ( $shutters->getUp eq 'time' ) {
            if ( ( IsWe() or IsWeTomorrow() )
                and $ascDev->getSunriseTimeWeHoliday eq 'on' )
            {
                if ( not IsWeTomorrow() ) {
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
                        and $shutters->getSunrise
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
                        and int( gettimeofday() / 86400 ) == int(
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
            $shuttersSunriseUnixtime =
              computeAlignTime( '24:00', $shutters->getTimeUpLate );
        }
        return $shuttersSunriseUnixtime;
    }
    elsif ( $tm eq 'real' ) {
        return sunrise_abs( $autoAstroMode, 0, $shutters->getTimeUpEarly,
            $shutters->getTimeUpLate )
          if ( $shutters->getUp eq 'astro' );
        return $shutters->getTimeUpEarly if ( $shutters->getUp eq 'time' );
    }
}

sub IsAfterShuttersTimeBlocking($) {
    my ($shuttersDev) = @_;
    $shutters->setShuttersDev($shuttersDev);

    if (
        ( int( gettimeofday() ) - $shutters->getLastManPosTimestamp ) <
        $shutters->getBlockingTimeAfterManual
        or (    not $shutters->getIsDay
            and defined( $shutters->getSunriseUnixTime )
            and $shutters->getSunriseUnixTime - ( int( gettimeofday() ) ) <
            $shutters->getBlockingTimeBeforDayOpen )
        or (    $shutters->getIsDay
            and defined( $shutters->getSunriseUnixTime )
            and $shutters->getSunsetUnixTime - ( int( gettimeofday() ) ) <
            $shutters->getBlockingTimeBeforNightClose )
      )
    {
        return 0;
    }

    else { return 1 }
}

sub IsAfterShuttersManualBlocking($) {
    my $shuttersDev = shift;
    $shutters->setShuttersDev($shuttersDev);

    if (    $ascDev->getblockAscDrivesAfterManual
        and $shutters->getStatus != $shutters->getOpenPos
        and $shutters->getStatus != $shutters->getClosedPos
        and $shutters->getStatus != $shutters->getWindPos
        and $shutters->getStatus != $shutters->getShadingPos
        and $shutters->getStatus != $shutters->getComfortOpenPos
        and $shutters->getStatus != $shutters->getVentilatePos
        and $shutters->getStatus != $shutters->getAntiFreezePos
        and $shutters->getLastDrive eq 'manual' )
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

sub ShuttersSunset($$) {
    my ( $shuttersDev, $tm ) =
      @_;    # Tm steht für Timemode und bedeutet Realzeit oder Unixzeit
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
            if ( defined($oldFuncHash) and ref($oldFuncHash) eq 'HASH' ) {
                $shuttersSunsetUnixtime += 86400
                  if ( $shuttersSunsetUnixtime <
                    ( $oldFuncHash->{sunsettime} + 180 )
                    and $oldFuncHash->{sunsettime} < gettimeofday() );
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
}

## Kontrolliert ob das Fenster von einem bestimmten Rolladen offen ist
sub CheckIfShuttersWindowRecOpen($) {
    my $shuttersDev = shift;
    $shutters->setShuttersDev($shuttersDev);

    if ( $shutters->getWinStatus =~ /[Oo]pen/ )    # CK: covers: open|opened
    {
        return 2;
    }
    elsif ( $shutters->getWinStatus =~ /tilt/
        and $shutters->getSubTyp eq 'threestate' )    # CK: covers: tilt|tilted
    {
        return 1;
    }
    elsif ( $shutters->getWinStatus =~ /[Cc]lose/ ) {
        return 0;
    }                                                 # CK: covers: close|closed
}

sub makeReadingName($) {
    my ($rname) = @_;
    my %charHash = (
        chr(0xe4) => "ae",                            # ä
        chr(0xc4) => "Ae",                            # Ä
        chr(0xfc) => "ue",                            # ü
        chr(0xdc) => "Ue",                            # Ü
        chr(0xf6) => "oe",                            # ö
        chr(0xd6) => "Oe",                            # Ö
        chr(0xdf) => "ss"                             # ß
    );
    my $charHashkeys = join( "", keys(%charHash) );

    return $rname if ( $rname =~ m/^\./ );
    $rname =~ s/([$charHashkeys])/$charHash{$1}/gi;
    $rname =~ s/[^a-z0-9._\-\/]/_/gi;
    return $rname;
}

sub TimeMin2Sec($) {
    my $min = shift;
    my $sec;

    $sec = $min * 60;
    return $sec;
}

sub IsWe() {
    my $we = main::IsWe();
    return $we;
}

sub IsWeTomorrow() {
    my $we = main::IsWe('tomorrow');
    return $we;
}

sub _SetCmdFn($) {
    my $h           = shift;
    my $shuttersDev = $h->{shuttersDev};
    my $posValue    = $h->{posValue};

    $shutters->setShuttersDev($shuttersDev);
    $shutters->setLastDrive( $h->{lastDrive} )
      if ( defined( $h->{lastDrive} ) );

    return
      unless ( $shutters->getASCenable eq 'on'
        and $ascDev->getASCenable eq 'on' );

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
      if ( not $shutters->getSelfDefenseAbsent
        and $shutters->getSelfDefenseAbsentTimerrun );
}

sub _setShuttersLastDriveDelayed($) {
    my $h = shift;

    my $shuttersDevHash = $h->{devHash};
    my $lastDrive       = $h->{lastDrive};

    readingsSingleUpdate( $shuttersDevHash, 'ASC_ShuttersLastDrive',
        $lastDrive, 1 );
}

sub ASC_Debug($) {
    return
      unless ( AttrVal( $ascDev->getName, 'ASC_debug', 0 ) );

    my $debugMsg = shift;
    my $debugTimestamp = strftime( "%Y.%m.%e %T", localtime(time) );

    print(
        encode_utf8(
            "\n" . 'ASC_DEBUG!!! ' . $debugTimestamp . ' - ' . $debugMsg . "\n"
        )
    );
}

sub _averageBrightness(@) {
    my @input = @_;
    use List::Util qw(sum);

    return int( sum(@input) / @input );
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
    my ( $self, $shuttersDev ) = @_;

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
    return 0;
}

sub setHardLockOut {
    my ( $self, $cmd ) = @_;

    if (    $shutters->getLockOut eq 'hard'
        and $shutters->getLockOutCmd ne 'none' )
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
    return 0;
}

sub setNoOffset {
    my ( $self, $noOffset ) = @_;

    $self->{ $self->{shuttersDev} }{noOffset} = $noOffset;
    return 0;
}

sub setSelfDefenseAbsent {
    my ( $self, $timerrun, $active, $timerhash ) = @_;

    $self->{ $self->{shuttersDev} }{selfDefenseAbsent}{timerrun}  = $timerrun;
    $self->{ $self->{shuttersDev} }{selfDefenseAbsent}{active}    = $active;
    $self->{ $self->{shuttersDev} }{selfDefenseAbsent}{timerhash} = $timerhash
      if ( defined($timerhash) );
    return 0;
}

sub setDriveCmd {
    my ( $self, $posValue ) = @_;
    my $offSet;
    my $offSetStart;

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

    $offSet = $shutters->getOffset       if ( $shutters->getOffset > -1 );
    $offSet = $ascDev->getShuttersOffset if ( $shutters->getOffset < 0 );
    $offSetStart = $shutters->getOffsetStart;

    if (    $shutters->getSelfDefenseAbsent
        and not $shutters->getSelfDefenseAbsentTimerrun
        and $shutters->getSelfDefenseExclude eq 'off'
        and $shutters->getLastDrive eq 'selfDefense active'
        and $ascDev->getSelfDefense eq 'on' )
    {
        InternalTimer( gettimeofday() + $shutters->getSelfDefenseAbsentDelay,
            'FHEM::AutoShuttersControl::_SetCmdFn', \%h );
        $shutters->setSelfDefenseAbsent( 1, 0, \%h );
    }
    elsif ( $offSetStart > 0 and not $shutters->getNoOffset ) {
        InternalTimer(
            gettimeofday() + int( rand($offSet) + $shutters->getOffsetStart ),
            'FHEM::AutoShuttersControl::_SetCmdFn', \%h );

        FHEM::AutoShuttersControl::ASC_Debug( 'FnSetDriveCmd: '
              . $shutters->getShuttersDev
              . ' - versetztes fahren' );
    }
    elsif ( $offSetStart < 1 or $shutters->getNoOffset ) {
        FHEM::AutoShuttersControl::_SetCmdFn( \%h );
        FHEM::AutoShuttersControl::ASC_Debug( 'FnSetDriveCmd: '
              . $shutters->getShuttersDev
              . ' - NICHT versetztes fahren' );
    }

    FHEM::AutoShuttersControl::ASC_Debug( 'FnSetDriveCmd: '
          . $shutters->getShuttersDev
          . ' - NoOffset: '
          . ( $shutters->getNoOffset ? 'JA' : 'NEIN' ) );
    $shutters->setNoOffset(0);
    return 0;
}

sub setSunsetUnixTime {
    my ( $self, $unixtime ) = @_;

    $self->{ $self->{shuttersDev} }{sunsettime} = $unixtime;
    return 0;
}

sub setSunset {
    my ( $self, $value ) = @_;

    $self->{ $self->{shuttersDev} }{sunset} = $value;
    return 0;
}

sub setSunriseUnixTime {
    my ( $self, $unixtime ) = @_;

    $self->{ $self->{shuttersDev} }{sunrisetime} = $unixtime;
    return 0;
}

sub setSunrise {
    my ( $self, $value ) = @_;

    $self->{ $self->{shuttersDev} }{sunrise} = $value;
    return 0;
}

sub setDelayCmd {
    my ( $self, $posValue ) = @_;

    $self->{ $self->{shuttersDev} }{delayCmd} = $posValue;
    return 0;
}

sub setLastDrive {
    my ( $self, $lastDrive ) = @_;

    $self->{ $self->{shuttersDev} }{lastDrive} = $lastDrive;
    return 0;
}

sub setPosSetCmd {
    my ( $self, $posSetCmd ) = @_;

    $self->{ $self->{shuttersDev} }{posSetCmd} = $posSetCmd;
    return 0;
}

sub setLastDriveReading {
    my $self            = shift;
    my $shuttersDevHash = $defs{ $self->{shuttersDev} };

    my %h = (
        devHash   => $shuttersDevHash,
        lastDrive => $shutters->getLastDrive,
    );

    InternalTimer( gettimeofday() + 0.1,
        'FHEM::AutoShuttersControl::_setShuttersLastDriveDelayed', \%h );
    return 0;
}

sub setLastPos
{ # letzte ermittelte Position bevor die Position des Rolladen über ASC geändert wurde
    my ( $self, $position ) = @_;

    $self->{ $self->{shuttersDev} }{lastPos}{VAL} = $position
      if ( defined($position) );
    $self->{ $self->{shuttersDev} }{lastPos}{TIME} = int( gettimeofday() )
      if ( defined( $self->{ $self->{shuttersDev} }{lastPos} ) );
    return 0;
}

sub setLastManPos {
    my ( $self, $position ) = @_;

    $self->{ $self->{shuttersDev} }{lastManPos}{VAL} = $position
      if ( defined($position) );
    $self->{ $self->{shuttersDev} }{lastManPos}{TIME} = int( gettimeofday() )
      if (  defined( $self->{ $self->{shuttersDev} }{lastManPos} )
        and defined( $self->{ $self->{shuttersDev} }{lastManPos}{TIME} ) );
    $self->{ $self->{shuttersDev} }{lastManPos}{TIME} =
      int( gettimeofday() ) - 86400
      if ( defined( $self->{ $self->{shuttersDev} }{lastManPos} )
        and not defined( $self->{ $self->{shuttersDev} }{lastManPos}{TIME} ) );
    return 0;
}

sub setDefault {
    my ( $self, $defaultarg ) = @_;

    $self->{defaultarg} = $defaultarg if ( defined($defaultarg) );
    return $self->{defaultarg};
}

sub setRoommate {
    my ( $self, $roommate ) = @_;

    $self->{roommate} = $roommate if ( defined($roommate) );
    return $self->{roommate};
}

sub setInTimerFuncHash {
    my ( $self, $inTimerFuncHash ) = @_;

    $self->{ $self->{shuttersDev} }{inTimerFuncHash} = $inTimerFuncHash
      if ( defined($inTimerFuncHash) );
    return 0;
}

sub setPrivacyDownStatus {
    my ( $self, $statusValue ) = @_;

    $self->{ $self->{shuttersDev} }->{privacyDownStatus} = $statusValue;
    return 0;
}

sub getPrivacyDownStatus {
    my $self = shift;

    return (
        defined( $self->{ $self->{shuttersDev} }->{privacyDownStatus} )
        ? $self->{ $self->{shuttersDev} }->{privacyDownStatus}
        : undef
    );
}

sub getAttrUpdateChanges {
    my ( $self, $attr ) = @_;

    return $self->{ $self->{shuttersDev} }{AttrUpdateChanges}{$attr}
      if (  defined( $self->{ $self->{shuttersDev} }{AttrUpdateChanges} )
        and
        defined( $self->{ $self->{shuttersDev} }{AttrUpdateChanges}{$attr} ) );
}

sub getIsDay {
    my $self = shift;

    return FHEM::AutoShuttersControl::_IsDay( $self->{shuttersDev} );
}

sub getFreezeStatus {
    use POSIX qw(strftime);
    my $self    = shift;
    my $daytime = strftime( "%P", localtime() );
    my $outTemp = $ascDev->getOutTemp;
    $outTemp = $shutters->getOutTemp if ( $shutters->getOutTemp != -100 );

    if (    $shutters->getAntiFreeze ne 'off'
        and $outTemp <= $ascDev->getFreezeTemp )
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
    my ( $self, $posValue ) =
      @_;    #   wenn dem so ist wird 1 zurück gegeben ansonsten 0

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

sub getNoOffset {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }{noOffset};
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

    return $self->{ $self->{shuttersDev} }{selfDefenseAbsent}{timerhash}
      if (
        defined(
            $self->{ $self->{shuttersDev} }{selfDefenseAbsent}{timerhash}
        )
      );
}

sub getLastDrive {
    my $self = shift;

    $self->{ $self->{shuttersDev} }{lastDrive} =
      ReadingsVal( $self->{shuttersDev}, 'ASC_ShuttersLastDrive', 'none' )
      if ( not defined( $self->{ $self->{shuttersDev} }{lastDrive} ) );

    return $self->{ $self->{shuttersDev} }{lastDrive};
}

sub getLastPos
{ # letzte ermittelte Position bevor die Position des Rolladen über ASC geändert wurde
    my $self = shift;

    return $self->{ $self->{shuttersDev} }{lastPos}{VAL}
      if (  defined( $self->{ $self->{shuttersDev} }{lastPos} )
        and defined( $self->{ $self->{shuttersDev} }{lastPos}{VAL} ) );
}

sub getLastPosTimestamp {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }{lastPos}{TIME}
      if (  defined( $self->{ $self->{shuttersDev} } )
        and defined( $self->{ $self->{shuttersDev} }{lastPos} )
        and defined( $self->{ $self->{shuttersDev} }{lastPos}{TIME} ) );
}

sub getLastManPos
{ # letzte ermittelte Position bevor die Position des Rolladen manuell (nicht über ASC) geändert wurde
    my $self = shift;

    return $self->{ $self->{shuttersDev} }{lastManPos}{VAL}
      if (  defined( $self->{ $self->{shuttersDev} }{lastManPos} )
        and defined( $self->{ $self->{shuttersDev} }{lastManPos}{VAL} ) );
}

sub getLastManPosTimestamp {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }{lastManPos}{TIME}
      if (  defined( $self->{ $self->{shuttersDev} } )
        and defined( $self->{ $self->{shuttersDev} }{lastManPos} )
        and defined( $self->{ $self->{shuttersDev} }{lastManPos}{TIME} ) );
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

    foreach my $ro ( split( ",", $shutters->getRoommates ) ) {
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

    foreach my $ro ( split( ",", $shutters->getRoommates ) ) {
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

### Begin Beschattung Objekt mit Daten befüllen
sub setShadingStatus {
    my ( $self, $value ) = @_;
    ### Werte für value = in, out, in reserved, out reserved

    $self->{ $self->{shuttersDev} }{ShadingStatus}{VAL} = $value
      if ( defined($value) );
    $self->{ $self->{shuttersDev} }{ShadingStatus}{TIME} = int( gettimeofday() )
      if ( defined( $self->{ $self->{shuttersDev} }{ShadingStatus} ) );
    return 0;
}

sub setShadingLastStatus {
    my ( $self, $value ) = @_;
    ### Werte für value = in, out

    $self->{ $self->{shuttersDev} }{ShadingLastStatus}{VAL} = $value
      if ( defined($value) );
    $self->{ $self->{shuttersDev} }{ShadingLastStatus}{TIME} =
      int( gettimeofday() )
      if ( defined( $self->{ $self->{shuttersDev} }{ShadingLastStatus} ) );
    $self->{ $self->{shuttersDev} }{ShadingManualDriveStatus}{VAL} = 0
      if ( $value eq 'out' );
    return 0;
}

sub setShadingManualDriveStatus {
    my ( $self, $value ) = @_;
    ### Werte für value = in, out

    $self->{ $self->{shuttersDev} }{ShadingManualDriveStatus}{VAL} = $value
      if ( defined($value) );
    return 0;
}

sub setWindProtectionStatus {    # Werte protected, unprotected
    my ( $self, $value ) = @_;

    $self->{ $self->{shuttersDev} }->{ASC_WindParameters}->{VAL} = $value
      if ( defined($value) );
    return 0;
}

sub setRainProtectionStatus {    # Werte protected, unprotected
    my ( $self, $value ) = @_;

    $self->{ $self->{shuttersDev} }->{RainProtection}->{VAL} = $value
      if ( defined($value) );
    return 0;
}

sub setPushBrightnessInArray {
    my ( $self, $value ) = @_;

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
        ) > 3
      );
}

sub getBrightnessAverage {
    my $self = shift;

    return &FHEM::AutoShuttersControl::_averageBrightness(
        @{ $self->{ $self->{shuttersDev} }->{BrightnessAverageArray}->{VAL} } )
      if (
        scalar(
            @{
                $self->{ $self->{shuttersDev} }->{BrightnessAverageArray}->{VAL}
            }
        ) > 0
      );
}

sub getShadingStatus {   # Werte für value = in, out, in reserved, out reserved
    my $self = shift;

    return $self->{ $self->{shuttersDev} }{ShadingStatus}{VAL}
      if (  defined( $self->{ $self->{shuttersDev} }{ShadingStatus} )
        and defined( $self->{ $self->{shuttersDev} }{ShadingStatus}{VAL} ) );
}

sub getShadingLastStatus {    # Werte für value = in, out
    my $self = shift;

    return $self->{ $self->{shuttersDev} }{ShadingLastStatus}{VAL}
      if (  defined( $self->{ $self->{shuttersDev} }{ShadingLastStatus} )
        and defined( $self->{ $self->{shuttersDev} }{ShadingLastStatus}{VAL} )
      );
}

sub getShadingManualDriveStatus {    # Werte für value = in, out
    my $self = shift;

    return (
        defined( $self->{ $self->{shuttersDev} }{ShadingManualDriveStatus} )
          and defined(
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
              and $shutters->getShadingLastStatus eq 'out'
        ) ? 1 : 0
    );
}

sub getWindProtectionStatus {    # Werte protected, unprotected
    my $self = shift;

    return (
        (
            defined( $self->{ $self->{shuttersDev} }->{ASC_WindParameters} )
              and defined(
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
              and defined(
                $self->{ $self->{shuttersDev} }->{RainProtection}->{VAL}
              )
        )
        ? $self->{ $self->{shuttersDev} }->{RainProtection}->{VAL}
        : 'unprotected'
    );
}

sub getShadingStatusTimestamp {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }{ShadingStatus}{TIME}
      if (  defined( $self->{ $self->{shuttersDev} } )
        and defined( $self->{ $self->{shuttersDev} }{ShadingStatus} )
        and defined( $self->{ $self->{shuttersDev} }{ShadingStatus}{TIME} ) );
}

sub getShadingLastStatusTimestamp {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }{ShadingLastStatus}{TIME}
      if (  defined( $self->{ $self->{shuttersDev} } )
        and defined( $self->{ $self->{shuttersDev} }{ShadingLastStatus} )
        and defined( $self->{ $self->{shuttersDev} }{ShadingLastStatus}{TIME} )
      );
}
### Ende Beschattung

## Subklasse Attr von ASC_Shutters##
package ASC_Shutters::Attr;

use strict;
use warnings;

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

    return AttrVal( $self->{shuttersDev}, 'ASC_Antifreeze_Pos',
        $userAttrList{ASC_Antifreeze_Pos}
          [ AttrVal( $self->{shuttersDev}, 'ASC', 2 ) ] );
}

sub getShuttersPlace {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_ShuttersPlace', 'window' );
}

sub getPrivacyDownTime {
    my $self = shift;

    return AttrVal( $self->{shuttersDev},
        'ASC_PrivacyDownTime_beforNightClose', -1 );
}

sub getPrivacyDownPos {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_PrivacyDown_Pos', 50 );
}

sub getSelfDefenseExclude {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Self_Defense_Exclude', 'off' );
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

### Begin Beschattung
sub getShadingPos {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Shading_Pos',
        $userAttrList{'ASC_Shading_Pos:10,20,30,40,50,60,70,80,90,100'}
          [ AttrVal( $self->{shuttersDev}, 'ASC', 2 ) ] );
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
        and ( gettimeofday() -
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
        and ( gettimeofday() -
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

sub _getBrightnessSensor {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }->{ASC_BrightnessSensor}->{device}
      if (
        exists(
            $self->{ $self->{shuttersDev} }->{ASC_BrightnessSensor}
              ->{LASTGETTIME}
        )
        and ( gettimeofday() -
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
        and ( gettimeofday() -
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

sub getDirection {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Shading_Direction', 180 );
}

sub getShadingAngleLeft {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Shading_Angle_Left', 75 );
}

sub getShadingAngleRight {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Shading_Angle_Right', 75 );
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
        and ( gettimeofday() -
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
        and ( gettimeofday() -
            $self->{ $self->{shuttersDev} }->{ASC_Shading_MinMax_Elevation}
            ->{LASTGETTIME} ) < 2
      );
    $shutters->getShadingMinElevation;

    return $self->{ $self->{shuttersDev} }->{ASC_Shading_MinMax_Elevation}
      ->{maxVal};
}

sub getShadingStateChangeSunny {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Shading_StateChange_Sunny',
        35000 );
}

sub getShadingStateChangeCloudy {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Shading_StateChange_Cloudy',
        20000 );
}

sub getShadingWaitingPeriod {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Shading_WaitingPeriod', 1200 );
}
### Ende Beschattung

sub getOffset {
    my $self = shift;

    my $val = AttrVal( $self->{shuttersDev}, 'ASC_Drive_Offset', -1 );
    return ( $val =~ /^\d+$/ ? $val : -1 );
}

sub getOffsetStart {
    my $self = shift;

    my $val = AttrVal( $self->{shuttersDev}, 'ASC_Drive_OffsetStart', -1 );
    return ( ( $val > 0 and $val =~ /^\d+$/ ) ? $val : -1 );
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

    return AttrVal( $self->{shuttersDev}, 'ASC_Ventilate_Pos',
        $userAttrList{'ASC_Ventilate_Pos:10,20,30,40,50,60,70,80,90,100'}
          [ AttrVal( $self->{shuttersDev}, 'ASC', 2 ) ] );
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

sub getVentilateOpen {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Ventilate_Window_Open', 'on' );
}

sub getComfortOpenPos {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_ComfortOpen_Pos',
        $userAttrList{'ASC_ComfortOpen_Pos:0,10,20,30,40,50,60,70,80,90,100'}
          [ AttrVal( $self->{shuttersDev}, 'ASC', 2 ) ] );
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
        and ( gettimeofday() -
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
        and ( gettimeofday() -
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
        and ( gettimeofday() -
            $self->{ $self->{shuttersDev} }->{ASC_WindParameters}->{LASTGETTIME}
        ) < 2
      );
    $shutters->getWindMax;

    return $self->{ $self->{shuttersDev} }->{ASC_WindParameters}->{triggerhyst};
}

sub getWindProtection {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_WindProtection', 'on' );
}

sub getRainProtection {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_RainProtection', 'on' );
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
        'none' );
}

sub getAutoAstroModeEveningHorizon {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_AutoAstroModeEveningHorizon',
        'none' );
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

    return AttrVal( $self->{shuttersDev}, 'ASC_Time_Up_Early', '05:00' );
}

sub getTimeUpLate {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Time_Up_Late', '08:30' );
}

sub getTimeDownEarly {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Time_Down_Early', '16:00' );
}

sub getTimeDownLate {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Time_Down_Late', '22:00' );
}

sub getTimeUpWeHoliday {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Time_Up_WE_Holiday', '08:00' );
}

sub getBrightnessMinVal {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }->{ASC_BrightnessSensor}->{triggermin}
      if (
        exists(
            $self->{ $self->{shuttersDev} }->{ASC_BrightnessSensor}
              ->{LASTGETTIME}
        )
        and ( gettimeofday() -
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
        and ( gettimeofday() -
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

use GPUtils qw(GP_Import);

## Import der FHEM Funktionen
BEGIN {
    GP_Import(
        qw(
          AttrVal)
    );
}

sub getSubTyp {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_WindowRec_subType', 'twostate' );
}

sub _getWinDev {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_WindowRec', 'none' );
}

## Subklasse Readings von Klasse ASC_Window ##
package ASC_Window::Readings;

use strict;
use warnings;

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

    return ReadingsVal( $shutters->_getWinDev, 'state', 'closed' );
}

## Klasse ASC_Roommate ##
package ASC_Roommate;

use strict;
use warnings;

use GPUtils qw(GP_Import);

## Import der FHEM Funktionen
BEGIN {
    GP_Import(
        qw(
          ReadingsVal)
    );
}

sub _getRoommateStatus {
    my $self     = shift;
    my $roommate = $self->{roommate};

    return ReadingsVal( $roommate, $shutters->getRoommatesReading, 'none' );
}

sub _getRoommateLastStatus {
    my $self     = shift;
    my $roommate = $self->{roommate};
    my $default  = $self->{defaultarg};

    $default = 'none' if ( not defined($default) );
    return ReadingsVal( $roommate, 'lastState', $default );
}

## Klasse ASC_Dev plus Subklassen ASC_Attr_Dev und ASC_Readings_Dev##
package ASC_Dev;
our @ISA = qw(ASC_Dev::Readings ASC_Dev::Attr);

use strict;
use warnings;

sub new {
    my $class = shift;
    my $self = { name => undef, };

    bless $self, $class;
    return $self;
}

sub setName {
    my ( $self, $name ) = @_;

    $self->{name} = $name if ( defined($name) );
    return $self->{name};
}

sub setDefault {
    my ( $self, $defaultarg ) = @_;

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
    return 0;
}

sub setStateReading {
    my $self  = shift;
    my $value = shift;
    my $name  = $self->{name};
    my $hash  = $defs{$name};

    readingsSingleUpdate( $hash, 'state',
        ( defined($value) ? $value : $shutters->getLastDrive ), 1 );
    return 0;
}

sub setPosReading {
    my $self = shift;
    my $name = $self->{name};
    my $hash = $defs{$name};

    readingsSingleUpdate( $hash, $shutters->getShuttersDev . '_PosValue',
        $shutters->getStatus, 1 );
    return 0;
}

sub setLastPosReading {
    my $self = shift;
    my $name = $self->{name};
    my $hash = $defs{$name};

    readingsSingleUpdate( $hash, $shutters->getShuttersDev . '_lastPosValue',
        $shutters->getLastPos, 1 );
    return 0;
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

    if ( $val =~ m/^(?:(.+)_)?(.+)$/ ) {
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

    if ( $val =~ m/^(?:(.+)_)?(.+)$/ ) {
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

    return AttrVal( $name, 'ASC_shuttersDriveOffset', -1 );
}

sub getBrightnessMinVal {
    my $self = shift;
    my $name = $self->{name};

    return $self->{ASC_brightness}->{triggermin}
      if ( exists( $self->{ASC_brightness}->{LASTGETTIME} )
        and ( gettimeofday() - $self->{ASC_brightness}->{LASTGETTIME} ) < 2 );
    $ascDev->getBrightnessMaxVal;

    return $self->{ASC_brightness}->{triggermin};
}

sub getBrightnessMaxVal {
    my $self = shift;
    my $name = $self->{name};

    return $self->{ASC_brightness}->{triggermax}
      if ( exists( $self->{ASC_brightness}->{LASTGETTIME} )
        and ( gettimeofday() - $self->{ASC_brightness}->{LASTGETTIME} ) < 2 );
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
        and ( gettimeofday() - $self->{ASC_tempSensor}->{LASTGETTIME} ) < 2 );
    $self->{ASC_tempSensor}->{LASTGETTIME} = int( gettimeofday() );
    my ( $device, $reading ) =
      FHEM::AutoShuttersControl::GetAttrValues( $name, 'ASC_tempSensor',
        'none' );

    ## erwartetes Ergebnis
    # DEVICE:READING

    return $device if ( $device eq 'none' );
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
        and ( gettimeofday() - $self->{ASC_tempSensor}->{LASTGETTIME} ) < 2 );
    $ascDev->_getTempSensor;
    return $self->{ASC_tempSensor}->{reading};
}

sub _getResidentsDev {
    my $self = shift;
    my $name = $self->{name};

    return $self->{ASC_residentsDev}->{device}
      if ( exists( $self->{ASC_residentsDev}->{LASTGETTIME} )
        and ( gettimeofday() - $self->{ASC_residentsDev}->{LASTGETTIME} ) < 2 );
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
        and ( gettimeofday() - $self->{ASC_residentsDev}->{LASTGETTIME} ) < 2 );
    $ascDev->_getResidentsDev;
    return $self->{ASC_residentsDev}->{reading};
}

sub _getRainSensor {
    my $self = shift;
    my $name = $self->{name};

    return $self->{ASC_rainSensor}->{device}
      if ( exists( $self->{ASC_rainSensor}->{LASTGETTIME} )
        and ( gettimeofday() - $self->{ASC_rainSensor}->{LASTGETTIME} ) < 2 );
    $self->{ASC_rainSensor}->{LASTGETTIME} = int( gettimeofday() );
    my ( $device, $reading, $max, $hyst, $pos ) =
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

    return $self->{ASC_rainSensor}->{device};
}

sub getRainSensorReading {
    my $self = shift;
    my $name = $self->{name};

    return $self->{ASC_rainSensor}->{reading}
      if ( exists( $self->{ASC_rainSensor}->{LASTGETTIME} )
        and ( gettimeofday() - $self->{ASC_rainSensor}->{LASTGETTIME} ) < 2 );
    $ascDev->_getRainSensor;
    return $self->{ASC_rainSensor}->{reading};
}

sub getRainTriggerMax {
    my $self = shift;
    my $name = $self->{name};

    return $self->{ASC_rainSensor}->{triggermax}
      if ( exists( $self->{ASC_rainSensor}->{LASTGETTIME} )
        and ( gettimeofday() - $self->{ASC_rainSensor}->{LASTGETTIME} ) < 2 );
    $ascDev->_getRainSensor;
    return $self->{ASC_rainSensor}->{triggermax};
}

sub getRainTriggerMin {
    my $self = shift;
    my $name = $self->{name};

    return $self->{ASC_rainSensor}->{triggerhyst}
      if ( exists( $self->{ASC_rainSensor}->{LASTGETTIME} )
        and ( gettimeofday() - $self->{ASC_rainSensor}->{LASTGETTIME} ) < 2 );
    $ascDev->_getRainSensor;
    return $self->{ASC_rainSensor}->{triggerhyst};
}

sub getRainSensorShuttersClosedPos {
    my $self = shift;
    my $name = $self->{name};

    return $self->{ASC_rainSensor}->{shuttersClosedPos}
      if ( exists( $self->{ASC_rainSensor}->{LASTGETTIME} )
        and ( gettimeofday() - $self->{ASC_rainSensor}->{LASTGETTIME} ) < 2 );
    $ascDev->_getRainSensor;
    return $self->{ASC_rainSensor}->{shuttersClosedPos};
}

sub _getWindSensor {
    my $self = shift;
    my $name = $self->{name};

    return $self->{ASC_windSensor}->{device}
      if ( exists( $self->{ASC_windSensor}->{LASTGETTIME} )
        and ( gettimeofday() - $self->{ASC_windSensor}->{LASTGETTIME} ) < 2 );
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
        and ( gettimeofday() - $self->{ASC_windSensor}->{LASTGETTIME} ) < 2 );
    $ascDev->_getWindSensor;
    return (
        defined( $self->{ASC_windSensor}->{reading} )
        ? $self->{ASC_windSensor}->{reading}
        : 'wind'
    );
}

sub getblockAscDrivesAfterManual {
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
        <li><strong>renewSetSunriseSunsetTimer</strong> - resets the sunrise and sunset timers for every associated
            shutter device and creates new internal FHEM timers.
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
        <li><strong>showShuttersInformations</strong> - shows an information for all associated shutter devices with
            next activation time, mode and several other state informations.
        </li>
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
            <a name="ASC_shuttersDriveOffset"></a>
            <li><strong>ASC_shuttersDriveOffset</strong> - Maximum random drive delay in seconds for calculating
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
                but <em>ASC_Antifreeze</em> is not set to <em>off</em>. Defaults to 50.
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
                Depends on the <em>ASC</em> attribute.
            </li>
            <li><strong>ASC_ComfortOpen_Pos</strong> - The comfort opening position, ranging
                from 0 to 100 percent in increments of 10. Default: depends on the <em>ASC</em> attribute.
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
            <li><strong>ASC_Drive_Offset</strong> - Maximum <strong>random</strong> drive delay in seconds for calculating the
                driving time. 0 equals to no delay, -1 <em>ASC_shuttersDriveOffset</em> is used. Defaults to -1.
            </li>
            <li><strong>ASC_Drive_OffsetStart</strong> - <strong>Fixed</strong> drive delay in seconds for calculating the
                driving time. -1 or 0 equals to no delay. Defaults to -1 (no offset).
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
                Depends on the <em>ASC</em> attribute.
            </li>
            <li><strong>ASC_Partymode on|off</strong> - Party mode. If configured to on, driving orders for the
                shutter by <abbr>ASC</abbr> will be queued if <em>partyMode</em> is set to <em>on</em> at the
                global <abbr>ASC</abbr> device. Will execute the driving orders after <em>partyMode</em> is disabled.
                Defaults to off.
            </li>
            <li><strong>ASC_Pos_Reading</strong> - Points to the reading name, which contains the current
                position for the shutter in percent. Will be used for <em>set</em> at devices of unknown kind.
            </li>
            <li><strong>ASC_PrivacyDownTime_beforNightClose</strong> - How many seconds is the privacy mode activated
                before the shutter is closed in the evening. A value of <em>-1</em> disables this. -1 is the default
                value.
            </li>
            <li><strong>ASC_PrivacyDown_Pos</strong> -
                Position in percent for privacy mode, defaults to 50.
            </li>
            <li><strong>ASC_WindProtection on|off</strong> - Shutter is protected by the wind protection. Defaults
                to off.
            </li>
            <li><strong>ASC_Roommate_Device</strong> - Comma separated list of <em>ROOMMATE</em> devices, representing
                the inhabitants of the room to which the shutter belongs. Especially useful for bedrooms. Defaults
                to none.
            </li>
            <li><strong>ASC_Roommate_Reading</strong> - Specifies a reading name to <em>ASC_Roommate_Device</em>.
                Defaults to <em>state</em>.
            </li>
            <li><strong>ASC_Self_Defense_Exclude on|off</strong> - If set to on, the shutter will not be closed
                if the self defense mode is activated and residents are absent. Defaults to off.
            </li>
            <li><strong>ASC_Self_Defense_Mode - absent/gone</strong> - which Residents status Self Defense should become 
                active without the window being open. (default: gone)
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
                from 0 to 100 percent in increments of 10. Default depending on the <em>ASC</em> attribute.
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
            <li><strong>ASC_WindowRec</strong> - Points to the window contact device, associated with the shutter.
                Defaults to none.
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
                    <li><strong>ASC_Shading_Angle_Left</strong> - Minimal shading angle in relation to the window,
                        from when shade is applied. For example: Window is 180 &deg; (perpendicular) &minus; 85 &deg; set
                        for <em>ASC_Shading_Angle_Left</em> &rarr; shading starts if sun position is 95 &deg;.
                        Defaults to 75.
                    </li>
                    <li><strong>ASC_Shading_Angle_Right</strong> - Complements <em>ASC_Shading_Angle_Left</em> and
                        sets the maximum shading angle in relation to the window. For example: Window is 180 &deg;
                        (perpendicular) &plus; 85 &deg; set from <em>ASC_Shading_Angle_Right</em> &rarr; shading until
                        sun position of 265 &deg; is reached. Defaults to 75.
                    </li>
                    <li><strong>ASC_Shading_Direction</strong> - Compass point degrees for which the window resp. shutter
                        points. East is 90 &deg;, South 180 &deg;, West is 270 &deg; and North is 0 &deg;.
                        Defaults to South (180).
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
                    <li><strong>ASC_Shading_Pos</strong> - Shading position in percent.</li>
                    <li><strong>ASC_Shading_StateChange_Cloudy</strong> - Shading <strong>ends</strong> at this
                        outdoor brightness, depending also on other sensor values. Defaults to 20000.
                    </li>
                    <li><strong>ASC_Shading_StateChange_Sunny</strong> - Shading <strong>starts</strong> at this
                        outdoor brightness, depending also on other sensor values. Defaults to 35000.
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
    <table border="1">
        <tr>
            <th>Getter</th>
            <th>Description</th>
        </tr>
        <tr>
            <td>FreezeStatus</td>
            <td>1 = soft, 2 = daytime, 3 = hard</td>
        </tr>
        <tr>
            <td>NoOffset</td>
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
    <table/>
    </p>
    <u>&Uuml;bersicht f&uuml;r das Rollladen-Device mit Parameter&uuml;bergabe</u>
    <ul>
        <code>{ ascAPIget('Getter','ROLLODEVICENAME',VALUE) }</code><br>
    </ul>
    <table border="1">
        <tr>
            <th>Getter</th><th>Erl&auml;uterung</th>
        </tr>
        <tr>
            <td>QueryShuttersPos</td><td>R&uuml;ckgabewert 1 bedeutet das die aktuelle Position des Rollos unterhalb der Valueposition ist. 0 oder nichts bedeutet oberhalb der Valueposition.</td>
        </tr>
    <table/>
    </p>
    <u>Data points of the <abbr>ASC</abbr> device</u>
        <p>
            <code>{ ascAPIget('Getter') }</code><br>
        </p>
        <table border="1">
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
        <table/>
</ul>

=end html

=begin html_DE

<a name="AutoShuttersControl"></a>
<h3>AutoShuttersControl</h3>
<ul>
    <p>AutoShuttersControl (ASC) erm&ouml;glicht eine vollst&auml;ndige Automatisierung der vorhandenen Rolll&auml;den. Das Modul bietet umfangreiche Konfigurationsm&ouml;glichkeiten, um Rolll&auml;den bspw. nach Sonnenauf- und untergangszeiten, nach Helligkeitswerten oder rein zeitgesteuert zu steuern.</p>
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
            <li><strong>ASC_Time_DriveUp</strong> - Im Astro-Modus ist hier die Sonnenaufgangszeit f&uuml;r das Rollo gespeichert. Im Brightness- und Zeit-Modus ist hier der Zeitpunkt aus dem Attribut <em>ASC_Time_Up_Late</em> gespeichert.</li>
            <li><strong>ASC_Time_DriveDown</strong>  - Im Astro-Modus ist hier die Sonnenuntergangszeit f&uuml;r das Rollo gespeichert. Im Brightness- und Zeit-Modus ist hier der Zeitpunkt aus dem Attribut <em>ASC_Time_Down_Late</em> gespeichert.</li>
            <li><strong>ASC_ShuttersLastDrive</strong>  - Grund der letzten Fahrt vom Rollladen</li>
        </ul>
    </ul>
    <br /><br />
    <a name="AutoShuttersControlSet"></a>
    <strong>Set</strong>
    <ul>
        <li><strong>ascEnable - on/off</strong> - Aktivieren oder deaktivieren der globalen ASC Steuerung</li>
        <li><strong>controlShading - on/off</strong> - Aktiviert oder deaktiviert die globale Beschattungssteuerung</li>
        <li><strong>createNewNotifyDev</strong> - Legt die interne Struktur f&uuml;r NOTIFYDEV neu an. Diese Funktion steht nur zur Verf&uuml;gung, wenn Attribut ASC_expert auf 1 gesetzt ist.</li>
        <li><strong>hardLockOut - on/off</strong> - Aktiviert den hardwareseitigen Aussperrschutz f&uuml;r die Rolll&auml;den, bei denen das Attributs <em>ASC_LockOut</em> entsprechend auf hard gesetzt ist. Mehr Informationen in der Beschreibung bei den Attributen f&uuml;r die Rollladenger&auml;ten.</li>
        <li><strong>partyMode - on/off</strong> - Aktiviert den globalen Partymodus. Alle Rollladen-Ger&auml;ten, in welchen das Attribut <em>ASC_Partymode</em> auf <em>on</em> gesetzt ist, werden durch ASC nicht mehr gesteuert. Der letzte Schaltbefehl, der bspw. durch ein Fensterevent oder Wechsel des Bewohnerstatus an die Rolll&auml;den gesendet wurde, wird beim Deaktivieren des Partymodus ausgef&uuml;hrt</li>
        <li><strong>renewSetSunriseSunsetTimer</strong> - erneuert bei allen Rolll&auml;den die Zeiten f&uuml;r Sonnenauf- und -untergang und setzt die internen Timer neu.</li>
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
        <li><strong>showShuttersInformations</strong> - zeigt eine &Uuml;bersicht aller Rolll&auml;den mit den Fahrzeiten, Modus und diverse weitere Statusanzeigen.</li>
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
            <a name="ASC_shuttersDriveOffset"></a>
            <li><strong>ASC_shuttersDriveOffset</strong> - maximale Zufallsverz&ouml;gerung in Sekunden bei der Berechnung der Fahrzeiten. 0 bedeutet keine Verz&ouml;gerung</li>
            <a name="ASC_tempSensor"></a>
            <li><strong>ASC_tempSensor - DEVICENAME[:READINGNAME]</strong> - der Inhalt ist eine Kombination aus Device und Reading f&uuml;r die Au&szlig;entemperatur</li>
            <a name="ASC_twilightDevice"></a>
            <li><strong>ASC_twilightDevice</strong> - das Device, welches die Informationen zum Sonnenstand liefert. Wird unter anderem f&uuml;r die Beschattung verwendet.</li>
            <a name="ASC_windSensor"></a>
            <li><strong>ASC_windSensor - DEVICE[:READING]</strong> - Sensor f&uuml;r die Windgeschwindigkeit. Kombination aus Device und Reading.</li>
        </ul>
        <br />
        <u> In den Rolll&auml;den-Ger&auml;ten</u>
        <ul>
            <li><strong>ASC - 0/1/2</strong> 0 = "kein Anlegen der Attribute beim ersten Scan bzw. keine Beachtung eines Fahrbefehles",1 = "Inverse oder Rollo - Bsp.: Rollo oben 0, Rollo unten 100 und der Befehl zum prozentualen Fahren ist position",2 = "Homematic Style - Bsp.: Rollo oben 100, Rollo unten 0 und der Befehl zum prozentualen Fahren ist pct</li>
            <li><strong>ASC_Antifreeze - soft/am/pm/hard/off</strong> - Frostschutz, wenn soft f&auml;hrt der Rollladen in die ASC_Antifreeze_Pos und wenn hard/am/pm wird gar nicht oder innerhalb der entsprechenden Tageszeit nicht gefahren (default: off)</li>
            <li><strong>ASC_Antifreeze_Pos</strong> - Position die angefahren werden soll, wenn der Fahrbefehl komplett schlie&szlig;en lautet, aber der Frostschutz aktiv ist (default: 50)</li>
            <li><strong>ASC_AutoAstroModeEvening</strong> - aktuell REAL,CIVIL,NAUTIC,ASTRONOMIC (default: none)</li>
            <li><strong>ASC_AutoAstroModeEveningHorizon</strong> - H&ouml;he &uuml;ber Horizont, wenn beim Attribut ASC_autoAstroModeEvening HORIZON ausgew&auml;hlt (default: none)</li>
            <li><strong>ASC_AutoAstroModeMorning</strong> - aktuell REAL,CIVIL,NAUTIC,ASTRONOMIC (default: none)</li>
            <li><strong>ASC_AutoAstroModeMorningHorizon</strong> - H&ouml;he &uuml;ber Horizont,a wenn beim Attribut ASC_autoAstroModeMorning HORIZON ausgew&auml;hlt (default: none)</li>
            <li><strong>ASC_BlockingTime_afterManual</strong> - wie viel Sekunden soll die Automatik nach einer manuellen Fahrt aussetzen. (default: 1200)</li>
            <li><strong>ASC_BlockingTime_beforDayOpen</strong> - wie viel Sekunden vor dem morgendlichen &ouml;ffnen soll keine schlie&szlig;en Fahrt mehr stattfinden. (default: 3600)</li>
            <li><strong>ASC_BlockingTime_beforNightClose</strong> - wie viel Sekunden vor dem n&auml;chtlichen schlie&szlig;en soll keine &ouml;ffnen Fahrt mehr stattfinden. (default: 3600)</li>
            <li><strong>ASC_BrightnessSensor - DEVICE[:READING] WERT-MORGENS:WERT-ABENDS</strong> / 'Sensorname[:brightness [400:800]]' Angaben zum Helligkeitssensor mit (Readingname, optional) f&uuml;r die Beschattung und dem Fahren der Rollladen nach brightness und den optionalen Brightnesswerten f&uuml;r Sonnenauf- und Sonnenuntergang. (default: none)</li>
            <li><strong>ASC_Closed_Pos</strong> - in 10 Schritten von 0 bis 100 (Default: ist abh&auml;ngig vom Attribut <em>ASC</em>)</li>
            <li><strong>ASC_ComfortOpen_Pos</strong> - in 10 Schritten von 0 bis 100 (Default: ist abh&auml;ngig vom Attribut <em>ASC</em>)</li>
            <li><strong>ASC_Down - astro/time/brightness</strong> - bei astro wird Sonnenuntergang berechnet, bei time wird der Wert aus ASC_Time_Down_Early als Fahrzeit verwendet und bei brightness muss ASC_Time_Down_Early und ASC_Time_Down_Late korrekt gesetzt werden. Der Timer l&auml;uft dann nach ASC_Time_Down_Late Zeit, es wird aber in der Zeit zwischen ASC_Time_Down_Early und ASC_Time_Down_Late geschaut, ob die als Attribut im Moduldevice hinterlegte ASC_brightnessDriveUpDown der Down Wert erreicht wurde. Wenn ja, wird der Rollladen runter gefahren (default: astro)</li>
            <li><strong>ASC_DriveUpMaxDuration</strong> - die Dauer des Hochfahrens des Rollladens plus 5 Sekunden (default: 60)</li>
            <li><strong>ASC_Drive_Offset</strong> - maximaler Wert f&uuml;r einen zuf&auml;llig ermittelte Verz&ouml;gerungswert in Sekunden bei der Berechnung der Fahrzeiten, 0 bedeutet keine Verz&ouml;gerung, -1 bedeutet, dass das gleichwertige Attribut aus dem ASC Device ausgewertet werden soll. (default: -1)</li>
            <li><strong>ASC_Drive_OffsetStart</strong> - in Sekunden verz&ouml;gerter Wert ab welchen dann erst das Offset startet und dazu addiert wird. Funktioniert nur wenn gleichzeitig ASC_Drive_Offset gesetzt wird. (default: -1)</li>
            <li><strong>ASC_LockOut - soft/hard/off</strong> - stellt entsprechend den Aussperrschutz ein. Bei global aktivem Aussperrschutz (set ASC-Device lockOut soft) und einem Fensterkontakt open bleibt dann der Rollladen oben. Dies gilt nur bei Steuerbefehlen &uuml;ber das ASC Modul. Stellt man global auf hard, wird bei entsprechender M&ouml;glichkeit versucht den Rollladen hardwareseitig zu blockieren. Dann ist auch ein Fahren &uuml;ber die Taster nicht mehr m&ouml;glich. (default: off)</li>
            <li><strong>ASC_LockOut_Cmd - inhibit/blocked/protection</strong> - set Befehl f&uuml;r das Rollladen-Device zum Hardware sperren. Dieser Befehl wird gesetzt werden, wenn man "ASC_LockOut" auf hard setzt (default: none)</li>
            <li><strong>ASC_Mode_Down - always/home/absent/off</strong> - Wann darf die Automatik steuern. immer, niemals, bei Abwesenheit des Roommate (ist kein Roommate und absent eingestellt, wird gar nicht gesteuert) (default: always)</li>
            <li><strong>ASC_Mode_Up - always/home/absent/off</strong> - Wann darf die Automatik steuern. immer, niemals, bei Abwesenheit des Roommate (ist kein Roommate und absent eingestellt, wird gar nicht gesteuert) (default: always)</li>
            <li><strong>ASC_Open_Pos</strong> -  in 10 Schritten von 0 bis 100 (default: ist abh&auml;ngig vom Attribut <em>ASC</em>)</li>
            <li><strong>ASC_Partymode -  on/off</strong> - schaltet den Partymodus an oder aus. Wird am ASC Device set ASC-DEVICE partyMode on geschalten, werden alle Fahrbefehle an den Rolll&auml;den, welche das Attribut auf on haben, zwischengespeichert und sp&auml;ter erst ausgef&uuml;hrt (default: off)</li>
            <li><strong>ASC_Pos_Reading</strong> - Name des Readings, welches die Position des Rollladen in Prozent an gibt; wird bei unbekannten Device Typen auch als set Befehl zum fahren verwendet</li>
            <li><strong>ASC_PrivacyDownTime_beforNightClose</strong> - wie viele Sekunden vor dem abendlichen schlie&szlig;en soll der Rollladen in die Sichtschutzposition fahren, -1 bedeutet das diese Funktion unbeachtet bleiben soll (default: -1)</li>
            <li><strong>ASC_PrivacyDown_Pos</strong> - Position den Rollladens f&uuml;r den Sichtschutz (default: 50)</li>
            <li><strong>ASC_WindProtection - on/off</strong> - soll der Rollladen beim Regenschutz beachtet werden. on=JA, off=NEIN.</li>
            <li><strong>ASC_Roommate_Device</strong> - mit Komma getrennte Namen des/der Roommate Device/s, welche den/die Bewohner des Raumes vom Rollladen wiedergibt. Es macht nur Sinn in Schlaf- oder Kinderzimmern (default: none)</li>
            <li><strong>ASC_Roommate_Reading</strong> - das Reading zum Roommate Device, welches den Status wieder gibt (default: state)</li>
            <li><strong>ASC_Self_Defense_Exclude - on/off</strong> - bei on Wert wird dieser Rollladen bei aktiven Self Defense und offenen Fenster nicht runter gefahren, wenn Residents absent ist. (default: off)</li>
            <li><strong>ASC_Self_Defense_Mode - absent/gone</strong> - ab welchen Residents Status soll Selfdefense aktiv werden ohne das Fenster auf sind. (default: gone)</li>
            <li><strong>ASC_Self_Defense_AbsentDelay</strong> - um wie viele Sekunden soll das fahren in Selfdefense bei Residents absent verz&ouml;gert werden. (default: 300)</li>
            <li><strong>ASC_Self_Defense_Exclude - on/off</strong> - bei on Wert wird dieser Rollladen bei aktiven Self Defense und offenen Fenster nicht runter gefahren, wenn Residents absent ist. (default: off)</li></p>
            <ul>
                <strong><u>Beschreibung der Beschattungsfunktion</u></strong>
                </br>Damit die Beschattung Funktion hat, m&uuml;ssen folgende Anforderungen erf&uuml;llt sein.
                </br><strong>Im ASC Device</strong> das Reading "controlShading" mit dem Wert on, sowie ein Astro/Twilight Device im Attribut "ASC_twilightDevice" und das Attribut "ASC_tempSensor".
                </br><strong>In den Rollladendevices</strong> ben&ouml;tigt ihr ein Helligkeitssensor als Attribut "ASC_BrightnessSensor", sofern noch nicht vorhanden. Findet der Sensor nur f&uuml;r die Beschattung Verwendung ist der Wert DEVICENAME[:READING] ausreichend.
                </br>Alle weiteren Attribute sind optional und wenn nicht gesetzt mit Default-Werten belegt. Ihr solltet sie dennoch einmal anschauen und entsprechend Euren Gegebenheiten setzen. Die Werte f&uumlr; die Fensterposition und den Vor- Nachlaufwinkel sowie die Grenzwerte f&uuml;r die StateChange_Cloudy und StateChange_Sunny solltet ihr besondere Beachtung dabei schenken.
                <li><strong>ASC_Shading_Angle_Left</strong> - Vorlaufwinkel im Bezug zum Fenster, ab wann abgeschattet wird. Beispiel: Fenster 180° - 85° ==> ab Sonnenpos. 95° wird abgeschattet (default: 75)</li>
                <li><strong>ASC_Shading_Angle_Right</strong> - Nachlaufwinkel im Bezug zum Fenster, bis wann abgeschattet wird. Beispiel: Fenster 180° + 85° ==> bis Sonnenpos. 265° wird abgeschattet (default: 75)</li>
                <li><strong>ASC_Shading_Direction</strong> -  Position in Grad, auf der das Fenster liegt - genau Osten w&auml;re 90, S&uuml;den 180 und Westen 270 (default: 180)</li>
                <li><strong>ASC_Shading_MinMax_Elevation</strong> - ab welcher min H&ouml;he des Sonnenstandes soll beschattet und ab welcher max H&ouml;he wieder beendet werden, immer in Abh&auml;ngigkeit der anderen einbezogenen Sensorwerte (default: 25.0:100.0)</li>
                <li><strong>ASC_Shading_Min_OutsideTemperature</strong> - ab welcher Temperatur soll Beschattet werden, immer in Abh&auml;ngigkeit der anderen einbezogenen Sensorwerte (default: 18)</li>
                <li><strong>ASC_Shading_Mode - absent,always,off,home</strong> / wann soll die Beschattung nur stattfinden. (default: off)</li>
                <li><strong>ASC_Shading_Pos</strong> - Position des Rollladens f&uuml;r die Beschattung</li>
                <li><strong>ASC_Shading_StateChange_Cloudy</strong> - Brightness Wert ab welchen die Beschattung aufgehoben werden soll, immer in Abh&auml;ngigkeit der anderen einbezogenen Sensorwerte (default: 20000)</li>
                <li><strong>ASC_Shading_StateChange_Sunny</strong> - Brightness Wert ab welchen Beschattung stattfinden soll, immer in Abh&auml;ngigkeit der anderen einbezogenen Sensorwerte (default: 35000)</li>
                <li><strong>ASC_Shading_WaitingPeriod</strong> - wie viele Sekunden soll gewartet werden bevor eine weitere Auswertung der Sensordaten f&uuml;r die Beschattung stattfinden soll (default: 1200)</li>
            </ul>
            <li><strong>ASC_ShuttersPlace - window/terrace</strong> - Wenn dieses Attribut auf terrace gesetzt ist, das Residence Device in den Status "gone" geht und SelfDefense aktiv ist (ohne das das Reading selfDefense gesetzt sein muss), wird das Rollo geschlossen (default: window)</li>
            <li><strong>ASC_Time_Down_Early</strong> - Sonnenuntergang fr&uuml;hste Zeit zum Runterfahren (default: 16:00)</li>
            <li><strong>ASC_Time_Down_Late</strong> - Sonnenuntergang sp&auml;teste Zeit zum Runterfahren (default: 22:00)</li>
            <li><strong>ASC_Time_Up_Early</strong> - Sonnenaufgang fr&uuml;hste Zeit zum Hochfahren (default: 05:00)</li>
            <li><strong>ASC_Time_Up_Late</strong> - Sonnenaufgang sp&auml;teste Zeit zum Hochfahren (default: 08:30)</li>
            <li><strong>ASC_Time_Up_WE_Holiday</strong> - Sonnenaufgang fr&uuml;hste Zeit zum Hochfahren am Wochenende und/oder Urlaub (holiday2we wird beachtet). (default: 08:00) ACHTUNG!!! in Verbindung mit Brightness f&uuml;r <em>ASC_Up</em> muss die Uhrzeit kleiner sein wie die Uhrzeit aus <em>ASC_Time_Up_Late</em></li>
            <li><strong>ASC_Up - astro/time/brightness</strong> - bei astro wird Sonnenaufgang berechnet, bei time wird der Wert aus ASC_Time_Up_Early als Fahrzeit verwendet und bei brightness muss ASC_Time_Up_Early und ASC_Time_Up_Late korrekt gesetzt werden. Der Timer l&auml;uft dann nach ASC_Time_Up_Late Zeit, es wird aber in der Zeit zwischen ASC_Time_Up_Early und ASC_Time_Up_Late geschaut, ob die als Attribut im Moduldevice hinterlegte Down Wert von ASC_brightnessDriveUpDown erreicht wurde. Wenn ja, wird der Rollladen hoch gefahren (default: astro)</li>
            <li><strong>ASC_Ventilate_Pos</strong> -  in 10 Schritten von 0 bis 100 (default: ist abh&auml;ngig vom Attribut <em>ASC</em>)</li>
            <li><strong>ASC_Ventilate_Window_Open</strong> - auf l&uuml;ften, wenn das Fenster gekippt/ge&ouml;ffnet wird und aktuelle Position unterhalb der L&uuml;ften-Position ist (default: on)</li>
            <li><strong>ASC_WiggleValue</strong> - Wert um welchen sich die Position des Rollladens &auml;ndern soll (default: 5)</li>
            <li><strong>ASC_WindParameters - TRIGGERMAX[:HYSTERESE] [DRIVEPOSITION]</strong> / Angabe von Max Wert ab dem f&uuml;r Wind getriggert werden soll, Hytsrese Wert ab dem der Windschutz aufgehoben werden soll TRIGGERMAX - HYSTERESE / Ist es bei einigen Rolll&auml;den nicht gew&uuml;nscht das gefahren werden soll, so ist der TRIGGERMAX Wert mit -1 an zu geben. (default: '50:20 ClosedPosition')</li>
            <li><strong>ASC_WindowRec_PosAfterDayClosed</strong> - open,lastManual / auf welche Position soll das Rollo nach dem schlie&szlig;en am Tag fahren. Open Position oder letzte gespeicherte manuelle Position (default: open)</li>
            <li><strong>ASC_WindowRec</strong> - Name des Fensterkontaktes, an dessen Fenster der Rollladen angebracht ist (default: none)</li>
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
    <table border="1">
        <tr><th>Getter</th><th>Erl&auml;uterung</th></tr>
        <tr><td>FreezeStatus</td><td>1=soft, 2=Daytime, 3=hard</td></tr>
        <tr><td>NoOffset</td><td>Wurde die Behandlung von Offset deaktiviert (Beispiel bei Fahrten &uuml;ber Fensterevents)</td></tr>
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
    <table/>
    </p>
    <u>&Uuml;bersicht f&uuml;r das Rollladen-Device mit Parameter&uuml;bergabe</u>
    <ul>
        <code>{ ascAPIget('Getter','ROLLODEVICENAME',VALUE) }</code><br>
    </ul>
    <table border="1">
        <tr><th>Getter</th><th>Erl&auml;uterung</th></tr>
        <tr><td>QueryShuttersPos</td><td>R&uuml;ckgabewert 1 bedeutet das die aktuelle Position des Rollos unterhalb der Valueposition ist. 0 oder nichts bedeutet oberhalb der Valueposition.</td></tr>
    <table/>
        </p>
        <u>&Uuml;bersicht f&uuml;r das ASC Device</u>
        <ul>
            <code>{ ascAPIget('Getter') }</code><br>
        </ul>
        <table border="1">
            <tr><th>Getter</th><th>Erl&auml;uterung</th></tr>
            <tr><td>OutTemp </td><td>aktuelle Au&szlig;entemperatur sofern ein Sensor definiert ist, wenn nicht kommt -100 als Wert zur&uuml;ck</td></tr>
            <tr><td>ResidentsStatus</td><td>aktueller Status des Residents Devices</td></tr>
            <tr><td>ResidentsLastStatus</td><td>letzter Status des Residents Devices</td></tr>
            <tr><td>Azimuth</td><td>Azimut Wert</td></tr>
            <tr><td>Elevation</td><td>Elevation Wert</td></tr>
            <tr><td>ASCenable</td><td>ist die ASC Steuerung global aktiv?</td></tr>
        <table/>
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
  "release_status": "under develop",
  "license": "GPL_2",
  "version": "v0.6.31",
  "x_developmentversion": "v0.6.19.34",
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
