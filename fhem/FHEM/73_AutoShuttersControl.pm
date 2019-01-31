###############################################################################
#
# Developed with Kate
#
#  (c) 2018-2019 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
#  All rights reserved
#
#   Special thanks goes to:
#       - Bernd (Cluni) this module is based on the logic of his script "Rollladensteuerung für HM/ROLLO inkl. Abschattung und Komfortfunktionen in Perl" (https://forum.fhem.de/index.php/topic,73964.0.html)
#       - Beta-User for many tests and ideas
#       - pc1246 write english commandref
#       - sledge fix many typo in commandref
#       - many User that use with modul and report bugs
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

package main;

use strict;
use warnings;

my $version = '0.4.0.2';

sub AutoShuttersControl_Initialize($) {
    my ($hash) = @_;

## Da ich mit package arbeite müssen in die Initialize für die jeweiligen hash Fn Funktionen der Funktionsname
    #  und davor mit :: getrennt der eigentliche package Name des Modules
    $hash->{SetFn}    = 'AutoShuttersControl::Set';
    $hash->{GetFn}    = 'AutoShuttersControl::Get';
    $hash->{DefFn}    = 'AutoShuttersControl::Define';
    $hash->{NotifyFn} = 'AutoShuttersControl::Notify';
    $hash->{UndefFn}  = 'AutoShuttersControl::Undef';
    $hash->{AttrFn}   = 'AutoShuttersControl::Attr';
    $hash->{AttrList} =
        'ASC_guestPresence:on,off '
      . 'ASC_temperatureSensor '
      . 'ASC_temperatureReading '
      . 'ASC_brightnessMinVal '
      . 'ASC_brightnessMaxVal '
      . 'ASC_autoShuttersControlMorning:on,off '
      . 'ASC_autoShuttersControlEvening:on,off '
      . 'ASC_autoShuttersControlShading:on,off '
      . 'ASC_autoShuttersControlComfort:on,off '
      . 'ASC_residentsDevice '
      . 'ASC_residentsDeviceReading '
      . 'ASC_rainSensorDevice '
      . 'ASC_rainSensorReading '
      . 'ASC_rainSensorShuttersClosedPos:0,10,20,30,40,50,60,70,80,90,100 '
      . 'ASC_autoAstroModeMorning:REAL,CIVIL,NAUTIC,ASTRONOMIC,HORIZON '
      . 'ASC_autoAstroModeMorningHorizon:-9,-8,-7,-6,-5,-4,-3,-2,-1,0,1,2,3,4,5,6,7,8,9 '
      . 'ASC_autoAstroModeEvening:REAL,CIVIL,NAUTIC,ASTRONOMIC,HORIZON '
      . 'ASC_autoAstroModeEveningHorizon:-9,-8,-7,-6,-5,-4,-3,-2,-1,0,1,2,3,4,5,6,7,8,9 '
      . 'ASC_freezeTemp:-5,-4,-3,-2,-1,0,1,2,3,4,5 '
      . 'ASC_shuttersDriveOffset '
      . 'ASC_twilightDevice '
      . 'ASC_expert:1 '
      . $readingFnAttributes;
    $hash->{NotifyOrderPrefix} = '51-';    # Order Nummer für NotifyFn

## Ist nur damit sich bei einem reload auch die Versionsnummer erneuert.
    foreach my $d ( sort keys %{ $modules{AutoShuttersControl}{defptr} } ) {
        my $hash = $modules{AutoShuttersControl}{defptr}{$d};
        $hash->{VERSION} = $version;
    }
}

## unserer packagename
package AutoShuttersControl;

use strict;
use warnings;
use POSIX;

use GPUtils qw(:all)
  ;    # wird für den Import der FHEM Funktionen aus der fhem.pl benötigt
use Data::Dumper;    #only for Debugging
use Date::Parse;

my $missingModul = '';
eval "use JSON qw(decode_json encode_json);1" or $missingModul .= 'JSON ';

## Import der FHEM Funktionen
BEGIN {
    GP_Import(
        qw(devspec2array
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
          AttrVal
          ReadingsVal
          Value
          IsDisabled
          deviceEvents
          init_done
          addToDevAttrList
          addToAttrList
          delFromDevAttrList
          delFromAttrList
          gettimeofday
          sunset_abs
          sunrise_abs
          InternalTimer
          RemoveInternalTimer
          computeAlignTime
          ReplaceEventMap)
    );
}

## Die Attributsliste welche an die Rolläden verteilt wird. Zusammen mit Default Werten
my %userAttrList = (
    'ASC_Mode_Up:absent,always,off,home'                            => 'always',
    'ASC_Mode_Down:absent,always,off,home'                          => 'always',
    'ASC_Up:time,astro,brightness'                                  => 'astro',
    'ASC_Down:time,astro,brightness'                                => 'astro',
    'ASC_AutoAstroModeMorning:REAL,CIVIL,NAUTIC,ASTRONOMIC,HORIZON' => 'none',
'ASC_AutoAstroModeMorningHorizon:-9,-8,-7,-6,-5,-4,-3,-2,-1,0,1,2,3,4,5,6,7,8,9'
      => 'none',
    'ASC_AutoAstroModeEvening:REAL,CIVIL,NAUTIC,ASTRONOMIC,HORIZON' => 'none',
'ASC_AutoAstroModeEveningHorizon:-9,-8,-7,-6,-5,-4,-3,-2,-1,0,1,2,3,4,5,6,7,8,9'
      => 'none',
    'ASC_Open_Pos:0,10,20,30,40,50,60,70,80,90,100'   => [ '', 0,   100 ],
    'ASC_Closed_Pos:0,10,20,30,40,50,60,70,80,90,100' => [ '', 100, 0 ],
    'ASC_Pos_Reading'                            => [ '', 'position', 'pct' ],
    'ASC_Time_Up_Early'                          => '04:30',
    'ASC_Time_Up_Late'                           => '09:00',
    'ASC_Time_Up_WE_Holiday'                     => '08:30',
    'ASC_Time_Down_Early'                        => '15:30',
    'ASC_Time_Down_Late'                         => '22:30',
    'ASC_PrivacyDownTime_beforNightClose'        => -1,
    'ASC_PrivacyDown_Pos'                        => 50,
    'ASC_WindowRec'                              => 'none',
    'ASC_Ventilate_Window_Open:on,off'           => 'on',
    'ASC_LockOut:soft,hard,off'                  => 'off',
    'ASC_LockOut_Cmd:inhibit,blocked,protection' => 'none',
    'ASC_BlockingTime_afterManual'               => 1200,
    'ASC_BlockingTime_beforNightClose'           => 3600,
    'ASC_BlockingTime_beforDayOpen'              => 3600,
    'ASC_Brightness_Sensor'                      => 'none',
    'ASC_Brightness_Reading'                     => 'brightness',
    'ASC_Shading_Direction'                      => 180,
    'ASC_Shading_Pos:10,20,30,40,50,60,70,80,90,100' => [ '', 80, 20 ],
    'ASC_Shading_Mode:absent,always,off,home'        => 'off',
    'ASC_Shading_Angle_Left'                         => 75,
    'ASC_Shading_Angle_Right'                        => 75,
    'ASC_Shading_StateChange_Sunny'                  => 35000,
    'ASC_Shading_StateChange_Cloudy'                 => 20000,
    'ASC_Shading_Min_Elevation'                      => 25.0,
    'ASC_Shading_Min_OutsideTemperature'             => 18,
    'ASC_Shading_WaitingPeriod'                      => 1200,

    #     'ASC_Shading_Fast_Open:on,off'                     => 'none',
    #     'ASC_Shading_Fast_Close:on,off'                    => 'none',
    'ASC_Drive_Offset'                                     => -1,
    'ASC_Drive_OffsetStart'                                => -1,
    'ASC_WindowRec_subType:twostate,threestate'            => 'twostate',
    'ASC_ShuttersPlace:window,terrace'                     => 'window',
    'ASC_Ventilate_Pos:10,20,30,40,50,60,70,80,90,100'     => [ '', 70, 30 ],
    'ASC_ComfortOpen_Pos:0,10,20,30,40,50,60,70,80,90,100' => [ '', 20, 80 ],
    'ASC_GuestRoom:on,off'                                 => 'none',
    'ASC_Antifreeze:off,soft,hard,am,pm'                   => 'off',
'ASC_Antifreeze_Pos:5,10,15,20,25,30,35,40,45,50,55,60,65,70,75,80,85,90,95,100'
      => [ '', 85, 15 ],
    'ASC_Partymode:on,off'            => 'off',
    'ASC_Roommate_Device'             => 'none',
    'ASC_Roommate_Reading'            => 'state',
    'ASC_Self_Defense_Exclude:on,off' => 'off',
    'ASC_BrightnessMinVal'            => -1,
    'ASC_BrightnessMaxVal'            => -1,
    'ASC_WiggleValue'                 => 5,
);

my %posSetCmds = (
    ZWave      => 'dim',
    Siro       => 'position',
    CUL_HM     => 'pct',
    ROLLO      => 'pct',
    SOMFY      => 'position',
    tahoma     => 'dim',
    KLF200Node => 'pct',
    DUOFERN    => 'position',
    HM485      => 'level',
);

my $shutters = new ASC_Shutters();
my $ascDev   = new ASC_Dev();

sub Define($$) {
    my ( $hash, $def ) = @_;
    my @a = split( '[ \t][ \t]*', $def );

    return 'only one AutoShuttersControl instance allowed'
      if ( devspec2array('TYPE=AutoShuttersControl') > 1 )
      ; # es wird geprüft ob bereits eine Instanz unseres Modules existiert,wenn ja wird abgebrochen
    return 'too few parameters: define <name> ShuttersControl' if ( @a != 2 );
    return
        'Cannot define ShuttersControl device. Perl modul '
      . ${missingModul}
      . 'is missing.'
      if ($missingModul)
      ; # Abbruch wenn benötigte Hilfsmodule nicht vorhanden sind / vorerst unwichtig

    my $name = $a[0];

    $hash->{VERSION} = $version;
    $hash->{MID}     = 'da39a3ee5e6b4b0d3255bfef95601890afd80709'
      ; # eine Ein Eindeutige ID für interne FHEM Belange / nicht weiter wichtig
    $hash->{NOTIFYDEV} = 'global,'
      . $name;    # Liste aller Devices auf deren Events gehört werden sollen
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
    CommandAttr( undef, $name . ' ASC_autoAstroModeEvening REAL' )
      if ( $ascDev->getAutoAstroModeEvening eq 'none' );
    CommandAttr( undef, $name . ' ASC_autoAstroModeMorning REAL' )
      if ( $ascDev->getAutoAstroModeMorning eq 'none' );
    CommandAttr( undef, $name . ' ASC_autoShuttersControlMorning on' )
      if ( $ascDev->getAutoShuttersControlMorning eq 'none' );
    CommandAttr( undef, $name . ' ASC_autoShuttersControlEvening on' )
      if ( $ascDev->getAutoShuttersControlEvening eq 'none' );
    CommandAttr( undef, $name . ' ASC_temperatureReading temperature' )
      if ( $ascDev->getTempReading eq 'none' );
    CommandAttr( undef, $name . ' ASC_freezeTemp 3' )
      if ( $ascDev->getFreezeTemp eq 'none' );
    CommandAttr( undef,
        $name
          . ' devStateIcon selfeDefense.terrace:fts_door_tilt created.new.drive.timer:clock .*asleep:scene_sleeping roommate.(awoken|home):user_available residents.(home|awoken):status_available manual:fts_shutter_manual selfeDefense.active:status_locked selfeDefense.inactive:status_open day.open:scene_day night.close:scene_night shading.in:weather_sun shading.out:weather_cloudy'
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
    my $hash = $defs{$name};

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

        CommandDeleteReading( undef, $name . ' lockOut' )
          if ( ReadingsVal( $name, 'lockOut', 'none' ) ne 'none' )
          ;    # temporär ab Version 0.2.2

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
                    'AutoShuttersControl::RenewSunRiseSetShuttersTimer',
                    $hash );
                InternalTimer( gettimeofday() + 5,
                    'AutoShuttersControl::AutoSearchTwilightDev', $hash );
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
/^(ATTR|DELETEATTR)\s(.*ASC_Roommate_Device|.*ASC_WindowRec|.*ASC_residentsDevice|.*ASC_rainSensorDevice|.*ASC_Brightness_Sensor|.*ASC_twilightDevice)(\s.*|$)/,
            @{$events}
          )
        {
            EventProcessingGeneral( $hash, undef, join( ' ', @{$events} ) );
        }
        elsif (
            grep
/^(ATTR|DELETEATTR)\s(.*ASC_Time_Up_WE_Holiday|.*ASC_Up|.*ASC_Down|.*ASC_AutoAstroModeMorning|.*ASC_AutoAstroModeMorningHorizon|.*ASC_AutoAstroModeEvening|.*ASC_AutoAstroModeEveningHorizon|.*ASC_Time_Up_Early|.*ASC_Time_Up_Late|.*ASC_Time_Down_Early|.*ASC_Time_Down_Late|.*ASC_autoAstroModeMorning|.*ASC_autoAstroModeMorningHorizon|.*ASC_PrivacyDownTime_beforNightClose|.*ASC_autoAstroModeEvening|.*ASC_autoAstroModeEveningHorizon)(\s.*|$)/,
            @{$events}
          )
        {
            EventProcessingGeneral( $hash, undef, join( ' ', @{$events} ) );
        }
    }
    elsif ( grep /^($posReading):\s\d+$/, @{$events} ) {
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
              if ( $deviceAttr eq 'ASC_residentsDevice' );
            EventProcessingRain( $hash, $device, $events )
              if ( $deviceAttr eq 'ASC_rainSensorDevice' );
            EventProcessingTwilightDevice( $hash, $device, $events )
              if ( $deviceAttr eq 'ASC_twilightDevice' );

            $shutters->setShuttersDev($device)
              if ( $deviceAttr eq 'ASC_Brightness_Sensor' );

            if (
                $deviceAttr eq 'ASC_Brightness_Sensor'
                and (  $shutters->getDown eq 'brightness'
                    or $shutters->getUp eq 'brightness' )
              )
            {
                EventProcessingBrightness( $hash, $device, $events );
            }
            elsif ( $deviceAttr eq 'ASC_Brightness_Sensor' ) {
                EventProcessingShadingBrightness( $hash, $device, $events );
            }
        }
    }
    else {    # alles was kein Devicenamen mit übergeben hat landet hier
        if ( $events =~
m#^ATTR\s(.*)\s(ASC_Roommate_Device|ASC_WindowRec|ASC_residentsDevice|ASC_rainSensorDevice|ASC_Brightness_Sensor|ASC_twilightDevice)\s(.*)$#
          )
        {     # wurde den Attributen unserer Rolläden ein Wert zugewiesen ?
            AddNotifyDev( $hash, $3, $1, $2 ) if ( $3 ne 'none' );
            Log3( $name, 4,
                "AutoShuttersControl ($name) - EventProcessing: ATTR" );
        }
        elsif ( $events =~
m#^DELETEATTR\s(.*)\s(ASC_Roommate_Device|ASC_WindowRec|ASC_residentsDevice|ASC_rainSensorDevice|ASC_Brightness_Sensor|ASC_twilightDevice)$#
          )
        {     # wurde das Attribut unserer Rolläden gelöscht ?
            Log3( $name, 4,
                "AutoShuttersControl ($name) - EventProcessing: DELETEATTR" );
            DeleteNotifyDev( $hash, $1, $2 );
        }
        elsif ( $events =~
m#^ATTR\s(.*)\s(ASC_Time_Up_WE_Holiday|ASC_Up|ASC_Down|ASC_AutoAstroModeMorning|ASC_AutoAstroModeMorningHorizon|ASC_PrivacyDownTime_beforNightClose|ASC_AutoAstroModeEvening|ASC_AutoAstroModeEveningHorizon|ASC_Time_Up_Early|ASC_Time_Up_Late|ASC_Time_Down_Early|ASC_Time_Down_Late)\s(.*)$#
          )
        {
            CreateSunRiseSetShuttersTimer( $hash, $1 )
              if (
                $2 ne 'ASC_Time_Up_WE_Holiday'
                or (    $2 eq 'ASC_Time_Up_WE_Holiday'
                    and $ascDev->getSunriseTimeWeHoliday eq 'on' )
              );
        }
        elsif ( $events =~
m#^ATTR\s(.*)\s(ASC_autoAstroModeMorning|ASC_autoAstroModeMorningHorizon|ASC_autoAstroModeEvening|ASC_autoAstroModeEveningHorizon)\s(.*)$#
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
        readingsSingleUpdate( $hash, $cmd, join( ' ', @args ), 1 );
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
    elsif ( lc $cmd eq 'selfdefense' ) {
        return "usage: $cmd" if ( @args > 1 );
        readingsSingleUpdate( $hash, $cmd, join( ' ', @args ), 1 );
    }
    elsif ( lc $cmd eq 'wiggle' ) {
        return "usage: $cmd" if ( @args > 1 );

        ( $args[0] eq 'all' ? wiggleAll($hash) : wiggle( $hash, $args[0] ) );
    }
    else {
        my $list = "scanForShutters:noArg";
        $list .=
" renewSetSunriseSunsetTimer:noArg partyMode:on,off hardLockOut:on,off sunriseTimeWeHoliday:on,off selfDefense:on,off wiggle:all,"
          . join( ',', @{ $hash->{helper}{shuttersList} } )
          if ( ReadingsVal( $name, 'userAttrList', 'none' ) eq 'rolled out' );
        $list .= " createNewNotifyDev:noArg"
          if (  ReadingsVal( $name, 'userAttrList', 'none' ) eq 'rolled out'
            and AttrVal( $name, 'ASC_expert', 0 ) == 1 );

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

        delFromDevAttrList( $_, 'ASC_lock-out:soft,hard' )
          ;    # temporär muss später gelöscht werden ab Version 0.2.0.6
        delFromDevAttrList( $_, 'ASC_lock-outCmd:inhibit,blocked' )
          ;    # temporär muss später gelöscht werden ab Version 0.2.0.6
        delFromDevAttrList( $_,
            'ASC_Pos_after_ComfortOpen:0,10,20,30,40,50,60,70,80,90,100' )
          ;    # temporär muss später gelöscht werden ab Version 0.2.0.6

        delFromDevAttrList( $_, 'ASC_Antifreeze:off,on' )
          if ( AttrVal( $_, 'ASC_Antifreeze', 'on' ) eq 'on'
            or AttrVal( $_, 'ASC_Antifreeze', 'on' ) eq 'off' )
          ;    # temporär muss später gelöscht werden ab Version 0.2.0.6

        delFromDevAttrList( $_,
'ASC_AntifreezePos:5,10,15,20,25,30,35,40,45,50,55,60,65,70,75,80,85,90,95,100'
        );     # temporär muss später gelöscht werden ab Version 0.2.0.7

        delFromDevAttrList( $_, 'ASC_LockOut_Cmd:inhibit,blocked' )
          if ( AttrVal( $_, 'ASC_LockOut_Cmd', 'none' ) eq 'none' )
          ;    # temporär muss später gelöscht werden ab Version 0.2.0.10

        delFromDevAttrList( $_, 'ASC_Shading_Brightness_Sensor' )
          ;    # temporär muss später gelöscht werden ab Version 0.2.0.12
        delFromDevAttrList( $_, 'ASC_Shading_Brightness_Reading' )
          ;    # temporär muss später gelöscht werden ab Version 0.2.0.12

        $shuttersList = $shuttersList . ',' . $_;
        $shutters->setShuttersDev($_);
        $shutters->setLastManPos( $shutters->getStatus );
        $shutters->setLastPos( $shutters->getStatus );
        $shutters->setDelayCmd('none');
        $shutters->setNoOffset(0);
        $shutters->setPosSetCmd( $posSetCmds{ $defs{$_}->{TYPE} } );
        $shutters->setShading('out');
    }

    #     $hash->{NOTIFYDEV} = $hash->{NOTIFYDEV} . $shuttersList;
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
            if ( $cmd eq 'add' ) {
                if ( ref($attribValue) ne 'ARRAY' ) {
                    $attr{$_}{ ( split( ':', $attrib ) )[0] } = $attribValue
                      if (
                        not
                        defined( $attr{$_}{ ( split( ':', $attrib ) )[0] } ) );
                }
                else {
                    $attr{$_}{ ( split( ':', $attrib ) )[0] } =
                      $attribValue->[ AttrVal( $_, 'ASC', 2 ) ]
                      if (
                        not
                        defined( $attr{$_}{ ( split( ':', $attrib ) )[0] } ) );
                }
                ## Oder das Attribut wird wieder gelöscht.
            }
            elsif ( $cmd eq 'del' ) {
                $shutters->setShuttersDev($_);

                RemoveInternalTimer( $shutters->getInTimerFuncHash );
                CommandDeleteReading( undef,
                    $_ . ' .?(AutoShuttersControl|ASC)_.*' );
                CommandDeleteAttr( undef, $_ . ' ASC' );
                delFromDevAttrList( $_, $attrib );
            }
        }
    }
}

## Fügt dem NOTIFYDEV Hash weitere Devices hinzu
sub AddNotifyDev($@) {
    my ( $hash, $dev, $shuttersDev, $shuttersAttr ) = @_;
    my $name = $hash->{NAME};

    my $notifyDev = $hash->{NOTIFYDEV};
    $notifyDev = "" if ( !$notifyDev );
    my %hash;

    %hash = map { ( $_ => 1 ) }
      split( ",", "$notifyDev,$dev" );

    $hash->{NOTIFYDEV} = join( ",", sort keys %hash );

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
            $notifyDevString = "" if ( !$notifyDevString );
            my %hash;
            %hash = map { ( $_ => 1 ) }
              grep { " $notifyDev " !~ m/ $_ / }
              split( ",", "$notifyDevString,$notifyDev" );

            $hash->{NOTIFYDEV} = join( ",", sort keys %hash );
        }
    }
    readingsSingleUpdate( $hash, '.monitoredDevs',
        eval { encode_json( $hash->{monitoredDevs} ) }, 0 );
}

## Sub zum steuern der Rolläden bei einem Fenster Event
sub EventProcessingWindowRec($@) {
    my ( $hash, $shuttersDev, $events ) = @_;
    my $name = $hash->{NAME};

    if ( $events =~ m#state:\s(open|closed|tilted)#
        and IsAfterShuttersManualBlocking($shuttersDev) )
    {
        $shutters->setShuttersDev($shuttersDev);

        #### Hardware Lock der Rollläden
        $shutters->setHardLockOut('off')
          if ( $1 eq 'closed' and $shutters->getShuttersPlace eq 'terrace' );
        $shutters->setHardLockOut('on')
          if ( $1 eq 'open' and $shutters->getShuttersPlace eq 'terrace' );

        $shutters->setNoOffset(1);

        my $queryShuttersPosWinRecTilted = (
              $shutters->getShuttersPosCmdValueNegate
            ? $shutters->getStatus > $shutters->getVentilatePos
            : $shutters->getStatus < $shutters->getVentilatePos
        );
        my $queryShuttersPosWinRecComfort = (
              $shutters->getShuttersPosCmdValueNegate
            ? $shutters->getStatus > $shutters->getComfortOpenPos
            : $shutters->getStatus < $shutters->getComfortOpenPos
        );

#         ## Wird erstmal deaktiviert da es Sinnlos ist in meinen Augen
#         if ( $shutters->getDelayCmd ne 'none' and $1 eq 'closed' )
#         { # Es wird geschaut ob wärend der Fenster offen Phase ein Fahrbefehl über das Modul kam,wenn ja wird dieser aus geführt
#             $shutters->setLastDrive('delayed drive - window closed');
#             ShuttersCommandSet( $hash, $shuttersDev, $shutters->getDelayCmd );
#         }
        if (  $1 eq 'closed'
          and IsAfterShuttersTimeBlocking( $hash, $shuttersDev ) )
        {
            if (   $shutters->getStatus == $shutters->getVentilatePos
                or $shutters->getStatus == $shutters->getComfortOpenPos
                or $shutters->getStatus == $shutters->getOpenPos )
            {
                my $homemode = $shutters->getRoommatesStatus;
                $homemode = $ascDev->getResidentsStatus
                  if ( $homemode eq 'none' );

                if (
                        IsDay( $hash, $shuttersDev )
                    and $shutters->getStatus != $shutters->getOpenPos
                    and (  $homemode ne 'asleep'
                        or $homemode ne 'gotosleep'
                        or $homemode eq 'none' )
                  )
                {
                    $shutters->setLastDrive('window day closed');
                    ShuttersCommandSet( $hash, $shuttersDev,
                        $shutters->getLastPos );
                }

                elsif (not IsDay( $hash, $shuttersDev )
                    or $homemode eq 'asleep'
                    or $homemode eq 'gotosleep' )
                {
                    $shutters->setLastDrive('window night closed');
                    ShuttersCommandSet( $hash, $shuttersDev,
                        $shutters->getClosedPos );
                }
            }
        }
        elsif (
            (
                $1 eq 'tilted'
                or ( $1 eq 'open' and $shutters->getSubTyp eq 'twostate' )
            )
            and $shutters->getVentilateOpen eq 'on'
            and $queryShuttersPosWinRecTilted
          )
        {
            $shutters->setLastDrive('ventilate - window open');
            ShuttersCommandSet( $hash, $shuttersDev,
                $shutters->getVentilatePos );
        }
        elsif ( $1 eq 'open'
            and $shutters->getSubTyp eq 'threestate'
            and $ascDev->getAutoShuttersControlComfort eq 'on'
            and $queryShuttersPosWinRecComfort )
        {
            $shutters->setLastDrive('comfort - window open');
            ShuttersCommandSet( $hash, $shuttersDev,
                $shutters->getComfortOpenPos );
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

        if (
            ( $1 eq 'home' or $1 eq 'awoken' )
            and (  $shutters->getRoommatesStatus eq 'home'
                or $shutters->getRoommatesStatus eq 'awoken' )
            and $ascDev->getAutoShuttersControlMorning eq 'on'

            and (  $shutters->getModeUp eq 'always'
                or $shutters->getModeUp eq 'home' )
          )
        {
            Log3( $name, 4,
"AutoShuttersControl ($name) - EventProcessingRoommate_1: $shuttersDev und Events $events"
            );
            if (
                (
                       $shutters->getRoommatesLastStatus eq 'asleep'
                    or $shutters->getRoommatesLastStatus eq 'awoken'
                )
                and IsDay( $hash, $shuttersDev )
                and IsAfterShuttersTimeBlocking( $hash, $shuttersDev )
              )
            {
                Log3( $name, 4,
"AutoShuttersControl ($name) - EventProcessingRoommate_2: $shuttersDev und Events $events"
                );
                $shutters->setLastDrive('roommate awoken');
                ShuttersCommandSet( $hash, $shuttersDev,
                    $shutters->getOpenPos );
            }

            if (
                (
                       $shutters->getRoommatesLastStatus eq 'absent'
                    or $shutters->getRoommatesLastStatus eq 'gone'
                    or $shutters->getRoommatesLastStatus eq 'home'
                )
                and (  $shutters->getModeUp eq 'home'
                    or $shutters->getModeUp eq 'always'
                    or $shutters->getModeDown eq 'home'
                    or $shutters->getModeDown eq 'always' )
                and $shutters->getRoommatesStatus eq 'home'
              )
            {
                if ( not IsDay( $hash, $shuttersDev )
                    and IsAfterShuttersTimeBlocking( $hash, $shuttersDev ) )
                {
                    my $position;
                    $shutters->setLastDrive('roommate home');

                    if ( CheckIfShuttersWindowRecOpen($shuttersDev) == 0
                        or $shutters->getVentilateOpen eq 'off' )
                    {
                        $position = $shutters->getClosedPos;
                    }
                    else {
                        $position = $shutters->getVentilatePos;
                        $shutters->setLastDrive(
                            $shutters->getLastDrive . ' - ventilate mode' );
                    }

                    ShuttersCommandSet( $hash, $shuttersDev, $position );
                }
                elsif ( IsDay( $hash, $shuttersDev )
                    and $shutters->getStatus == $shutters->getClosedPos
                    and IsAfterShuttersTimeBlocking( $hash, $shuttersDev ) )
                {
                    $shutters->setLastDrive('roommate home');
                    ShuttersCommandSet( $hash, $shuttersDev,
                        $shutters->getOpenPos );
                }
            }
        }
        elsif (
            (
                   $shutters->getModeDown eq 'always'
                or $shutters->getModeDown eq 'home'
            )
            and ( $1 eq 'gotosleep' or $1 eq 'asleep' )
            and $ascDev->getAutoShuttersControlEvening eq 'on'
          )
        {
            my $position;
            $shutters->setLastDrive('roommate asleep');

            if ( CheckIfShuttersWindowRecOpen($shuttersDev) == 0
                or $shutters->getVentilateOpen eq 'off' )
            {
                $position = $shutters->getClosedPos;
            }
            else {
                $position = $shutters->getVentilatePos;
                $shutters->setLastDrive(
                    $shutters->getLastDrive . ' - ventilate mode' );
            }

            ShuttersCommandSet( $hash, $shuttersDev, $position );
        }
        elsif ( $shutters->getModeDown eq 'absent'
            and $1 eq 'absent'
            and not IsDay( $hash, $shuttersDev ) )
        {
            $shutters->setLastDrive('roommate absent');
            ShuttersCommandSet( $hash, $shuttersDev, $shutters->getClosedPos );
        }
    }
}

sub EventProcessingResidents($@) {
    my ( $hash, $device, $events ) = @_;

    my $name    = $device;
    my $reading = $ascDev->getResidentsReading;

    if ( $events =~ m#$reading:\s(absent)# ) {
        foreach my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
            $shutters->setShuttersDev($shuttersDev);
            $shutters->setHardLockOut('off');
            if (
                    CheckIfShuttersWindowRecOpen($shuttersDev) != 0
                and $ascDev->getSelfDefense eq 'on'
                and $shutters->getSelfDefenseExclude eq 'off'
                or (
                    (
                           $shutters->getModeDown eq 'absent'
                        or $shutters->getModeDown eq 'always'
                    )
                    and not IsDay( $hash, $shuttersDev )
                    and IsAfterShuttersTimeBlocking( $hash, $shuttersDev )
                )
              )
            {
                if (    CheckIfShuttersWindowRecOpen($shuttersDev) != 0
                    and $ascDev->getSelfDefense eq 'on'
                    and $shutters->getSelfDefenseExclude eq 'off' )
                {
                    $shutters->setLastDrive('selfeDefense active');
                }
                else { $shutters->setLastDrive('residents absent'); }

                $shutters->setDriveCmd( $shutters->getClosedPos );
            }
        }
    }
    elsif ( $events =~ m#$reading:\s(gone)#
        and $ascDev->getSelfDefense eq 'on' )
    {
        foreach my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
            $shutters->setShuttersDev($shuttersDev);
            $shutters->setHardLockOut('off');
            if ( $shutters->getShuttersPlace eq 'terrace' ) {
                $shutters->setLastDrive('selfeDefense terrace');
                $shutters->setDriveCmd( $shutters->getClosedPos );
            }
        }
    }
    elsif (
        $events =~ m#$reading:\s(home)#
        and (  $ascDev->getResidentsLastStatus eq 'absent'
            or $ascDev->getResidentsLastStatus eq 'gone'
            or $ascDev->getResidentsLastStatus eq 'asleep'
            or $ascDev->getResidentsLastStatus eq 'awoken' )
      )
    {
        foreach my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
            $shutters->setShuttersDev($shuttersDev);

            if (
                    $shutters->getStatus != $shutters->getClosedPos
                and not IsDay( $hash, $shuttersDev )
                and $shutters->getRoommatesStatus eq 'none'
                and (  $shutters->getModeDown eq 'home'
                    or $shutters->getModeDown eq 'always' )
                and (  $ascDev->getResidentsLastStatus ne 'asleep'
                    or $ascDev->getResidentsLastStatus ne 'awoken' )
                and IsAfterShuttersTimeBlocking( $hash, $shuttersDev )
              )
            {
                $shutters->setLastDrive('residents home');
                $shutters->setDriveCmd( $shutters->getClosedPos );
            }
            elsif (
                    $ascDev->getSelfDefense eq 'on'
                and CheckIfShuttersWindowRecOpen($shuttersDev) != 0
                and $shutters->getSelfDefenseExclude eq 'off'
                or (    $ascDev->getResidentsLastStatus eq 'gone'
                    and $shutters->getShuttersPlace eq 'terrace' )
                and (  $shutters->getModeUp eq 'absent'
                    or $shutters->getModeUp eq 'off' )
              )
            {
                $shutters->setLastDrive('selfeDefense inactive');
                $shutters->setDriveCmd( $shutters->getLastPos );
                $shutters->setHardLockOut('on')
                  if ( CheckIfShuttersWindowRecOpen($shuttersDev) == 2
                    and $shutters->getShuttersPlace eq 'terrace' );
            }
            elsif (
                    $shutters->getStatus == $shutters->getClosedPos
                and IsDay( $hash, $shuttersDev )
                and $shutters->getRoommatesStatus eq 'none'
                and (  $shutters->getModeUp eq 'home'
                    or $shutters->getModeUp eq 'always' )
                and IsAfterShuttersTimeBlocking( $hash, $shuttersDev )
              )
            {
                if (   $ascDev->getResidentsLastStatus eq 'asleep'
                    or $ascDev->getResidentsLastStatus eq 'awoken' )
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
    my $val;

    if ( $events =~ m#$reading:\s(\d+|rain|dry)# ) {
        if    ( $1 eq 'rain' ) { $val = 1000 }
        elsif ( $1 eq 'dry' )  { $val = 0 }
        else                   { $val = $1 }

        foreach my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
            $shutters->setShuttersDev($shuttersDev);
            if (    $val > 100
                and $shutters->getStatus !=
                $ascDev->getRainSensorShuttersClosedPos )
            {
                $shutters->setLastDrive('rain protection');
                $shutters->setDriveCmd(
                    $ascDev->getRainSensorShuttersClosedPos );
            }
            elsif ( $val == 0
                and $shutters->getStatus ==
                $ascDev->getRainSensorShuttersClosedPos )
            {
                $shutters->setLastDrive('rain un-protection');
                $shutters->setDriveCmd( $shutters->getLastPos );
            }
        }
    }
}

sub EventProcessingBrightness($@) {
    my ( $hash, $shuttersDev, $events ) = @_;
    my $name = $hash->{NAME};
    $shutters->setShuttersDev($shuttersDev);

    return EventProcessingShadingBrightness( $hash, $shuttersDev, $events )
      unless (
        int( gettimeofday() / 86400 ) !=
        int( computeAlignTime( '24:00', $shutters->getTimeUpEarly ) / 86400 )
        and int( gettimeofday() / 86400 ) ==
        int( computeAlignTime( '24:00', $shutters->getTimeUpLate ) / 86400 )
        or int( gettimeofday() / 86400 ) !=
        int( computeAlignTime( '24:00', $shutters->getTimeDownEarly ) / 86400 )
        and int( gettimeofday() / 86400 ) ==
        int( computeAlignTime( '24:00', $shutters->getTimeDownLate ) / 86400 )
      );

    my $reading = $shutters->getBrightnessReading;
    if ( $events =~ m#$reading:\s(\d+)# ) {
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

        if (
            int( gettimeofday() / 86400 ) != int(
                computeAlignTime( '24:00', $shutters->getTimeUpEarly ) / 86400
            )
            and int( gettimeofday() / 86400 ) == int(
                computeAlignTime( '24:00', $shutters->getTimeUpLate ) / 86400
            )
            and $1 > $brightnessMaxVal
            and $shutters->getUp eq 'brightness'
          )
        {
            Log3( $name, 4,
"AutoShuttersControl ($shuttersDev) - EventProcessingBrightness: Steuerung für Morgens"
            );
            my $homemode = $shutters->getRoommatesStatus;
            $homemode = $ascDev->getResidentsStatus
              if ( $homemode eq 'none' );
            $shutters->setLastDrive('maximum brightness threshold exceeded');

            if (   $shutters->getModeUp eq $homemode
                or $homemode eq 'none'
                or $shutters->getModeUp eq 'always' )
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
                  )
                {
                    ShuttersCommandSet( $hash, $shuttersDev,
                        $shutters->getOpenPos );
                }
                else {
                    EventProcessingShadingBrightness( $hash, $shuttersDev,
                        $events );
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
            and IsAfterShuttersManualBlocking($shuttersDev)
          )
        {
            Log3( $name, 4,
"AutoShuttersControl ($shuttersDev) - EventProcessingBrightness: Steuerung für Abends"
            );

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

            my $homemode = $shutters->getRoommatesStatus;
            $homemode = $ascDev->getResidentsStatus
              if ( $homemode eq 'none' );
            $shutters->setLastDrive('minimum brightness threshold fell below');

            if (   $shutters->getModeDown eq $homemode
                or $homemode eq 'none'
                or $shutters->getModeDown eq 'always' )
            {
                ShuttersCommandSet( $hash, $shuttersDev, $posValue );
            }
            else {
                EventProcessingShadingBrightness( $hash, $shuttersDev,
                    $events );
            }
        }
    }
    else { EventProcessingShadingBrightness( $hash, $shuttersDev, $events ); }
}

sub EventProcessingShadingBrightness($@) {
    my ( $hash, $shuttersDev, $events ) = @_;
    my $name = $hash->{NAME};
    $shutters->setShuttersDev($shuttersDev);
    my $reading = $shutters->getBrightnessReading;

    if ( $events =~ m#$reading:\s(\d+)# ) {
        my $homemode = $shutters->getRoommatesStatus;
        $homemode = $ascDev->getResidentsStatus if ( $homemode eq 'none' );

        ShadingProcessing(
            $hash,                   $shuttersDev,
            $ascDev->getAzimuth,     $ascDev->getElevation,
            $1,                      $ascDev->getOutTemp,
            $shutters->getDirection, $shutters->getShadingAngleLeft,
            $shutters->getShadingAngleRight
          )

          if (
            (
                   $shutters->getShadingMode eq 'always'
                or $shutters->getShadingMode eq $homemode
            )
            and IsDay( $hash, $shuttersDev )
          );
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
    #     SunAlt = evaluation = Sonnenhöhe

    if ( $events =~ m#(azimuth|evaluation|SunAz|SunAlt):\s(\d+.\d+)# ) {
        my $name = $device;
        my ( $azimuth, $elevation );

        $azimuth   = $2 if ( $1 eq 'azimuth'    or $1 eq 'SunAz' );
        $elevation = $2 if ( $1 eq 'evaluation' or $1 eq 'SunAlt' );

        $azimuth = $ascDev->getAzimuth
          if ( not defined($azimuth) and not $azimuth );
        $elevation = $ascDev->getElevation
          if ( not defined($elevation) and not $elevation );

        foreach my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
            $shutters->setShuttersDev($shuttersDev);

            my $homemode = $shutters->getRoommatesStatus;
            $homemode = $ascDev->getResidentsStatus if ( $homemode eq 'none' );

            ShadingProcessing(
                $hash,
                $shuttersDev,
                $azimuth,
                $elevation,
                $shutters->getBrightness,
                $ascDev->getOutTemp,
                $shutters->getDirection,
                $shutters->getShadingAngleLeft,
                $shutters->getShadingAngleRight
              )
              if (
                (
                       $shutters->getShadingMode eq 'always'
                    or $shutters->getShadingMode eq $homemode
                )
                and IsDay( $hash, $shuttersDev )
              );
        }
    }
}

sub ShadingProcessing($@) {
### angleMinus ist $shutters->getShadingAngleLeft
### anglePlus ist $shutters->getShadingAngleRight
### winPos ist die Fensterposition $shutters->getDirection
    my (
        $hash,    $shuttersDev, $azimuth,    $elevation, $brightness,
        $outTemp, $winPos,      $angleMinus, $anglePlus
    ) = @_;
    my $name = $hash->{NAME};
    $shutters->setShuttersDev($shuttersDev);
    $shutters->setShading('out')
      if ( not IsDay( $hash, $shuttersDev )
        and $shutters->getShading ne 'out' );

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
        or $outTemp < $shutters->getShadingMinOutsideTemperature
        or not IsDay( $hash, $shuttersDev )
        or ( int( gettimeofday() ) - $shutters->getShadingTimestamp ) <
        ( $shutters->getShadingWaitingPeriod / 2 )
        or not IsAfterShuttersTimeBlocking( $hash, $shuttersDev ) );

    Log3( $name, 3,
            "AutoShuttersControl ($name) - Shading Processing, Rollladen: "
          . $shuttersDev
          . " Nach dem return" );

# minimalen und maximalen Winkel des Fensters bestimmen. wenn die aktuelle Sonnenposition z.B. bei 205° läge und der Wert für angleMin/Max 85° wäre, dann würden zwischen 120° und 290° beschattet.
    my $winPosMin = $winPos - $angleMinus;
    my $winPosMax = $winPos + $anglePlus;

    if (   $azimuth < $winPosMin
        or $azimuth > $winPosMax
        or $elevation < $shutters->getShadingMinElevation
        or $brightness <= $shutters->getShadingStateChangeCloudy )
    {
        $shutters->setShading('out reserved')
          if ( $shutters->getShading eq 'in'
            or $shutters->getShading eq 'in reserved' );

        $shutters->setShading('out')
          if ( $shutters->getShading eq 'out reserved'
            and ( int( gettimeofday() ) - $shutters->getShadingTimestamp ) >=
            $shutters->getShadingWaitingPeriod );
        Log3( $name, 3,
                "AutoShuttersControl ($name) - Shading Processing, Rollladen: "
              . $shuttersDev
              . " In der Out Abfrage, Shadingwert: "
              . $shutters->getShading
              . ", Zeitstempel: "
              . $shutters->getShadingTimestamp );
    }
    elsif ( $azimuth >= $winPosMin
        and $azimuth <= $winPosMax
        and $elevation >= $shutters->getShadingMinElevation
        and $brightness >= $shutters->getShadingStateChangeSunny )
    {
        $shutters->setShading('in reserved')
          if ( $shutters->getShading eq 'out'
            or $shutters->getShading eq 'out reserved' );

        $shutters->setShading('in')
          if ( $shutters->getShading eq 'in reserved'
            and ( int( gettimeofday() ) - $shutters->getShadingTimestamp ) >=
            ( $shutters->getShadingWaitingPeriod / 2 ) );
        Log3( $name, 1,
                "AutoShuttersControl ($name) - Shading Processing, Rollladen: "
              . $shuttersDev
              . " In der In Abfrage, Shadingwert: "
              . $shutters->getShading
              . ", Zeitstempel: "
              . $shutters->getShadingTimestamp );
    }

    if ( $shutters->getShading eq 'out' or $shutters->getShading eq 'in' ) {
        $shutters->setShading( $shutters->getShading )
          if ( ( int( gettimeofday() ) - $shutters->getShadingTimestamp ) >=
            ( $shutters->getShadingWaitingPeriod / 2 ) );

        if (    $shutters->getShading eq 'in'
            and $shutters->getShadingPos != $shutters->getStatus )
        {
            my $queryShuttersShadingPos = (
                  $shutters->getShuttersPosCmdValueNegate
                ? $shutters->getStatus > $shutters->getShadingPos
                : $shutters->getStatus < $shutters->getShadingPos
            );

            $shutters->setLastDrive('shading in');
            ShuttersCommandSet( $hash, $shuttersDev, $shutters->getShadingPos )
              if ( not $queryShuttersShadingPos );
        }
        elsif ( $shutters->getShading eq 'out'
            and $shutters->getShadingPos == $shutters->getStatus )
        {
            $shutters->setLastDrive('shading out');
            ShuttersCommandSet( $hash, $shuttersDev, $shutters->getLastPos );
            Log3( $name, 3,
"AutoShuttersControl ($name) - Shading Processing - shading out läuft"
            );
        }

        Log3( $name, 3,
"AutoShuttersControl ($name) - Shading Processing - In der Routine zum fahren der Rollläden, Shading Wert: "
              . $shutters->getShading );
    }
}

sub EventProcessingPartyMode($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    foreach my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
        $shutters->setShuttersDev($shuttersDev);
        if ( not IsDay( $hash, $shuttersDev )
            and $shutters->getModeDown ne 'off' )
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
        elsif ( IsDay( $hash, $shuttersDev ) ) {
            $shutters->setLastDrive('drive after party mode');
            ShuttersCommandSet( $hash, $shuttersDev, $shutters->getDelayCmd );
        }
    }
}

sub EventProcessingShutters($@) {
    my ( $hash, $shuttersDev, $events ) = @_;
    my $name = $hash->{NAME};

    if ( $events =~ m#.*:\s(\d+)# ) {
        $shutters->setShuttersDev($shuttersDev);
        $ascDev->setPosReading;
        if ( ( int( gettimeofday() ) - $shutters->getLastPosTimestamp ) > 60
            and $shutters->getLastPos != $shutters->getStatus )
        {
            $shutters->setLastDrive('manual');
            $shutters->setLastDriveReading;
            $ascDev->setStateReading;
            $shutters->setLastManPos($1);
        }
    }
}

# Sub für das Zusammensetzen der Rolläden Steuerbefehle
sub ShuttersCommandSet($$$) {
    my ( $hash, $shuttersDev, $posValue ) = @_;
    my $name = $hash->{NAME};
    $shutters->setShuttersDev($shuttersDev);

    my $queryShuttersPosValue = (
          $shutters->getShuttersPosCmdValueNegate
        ? $shutters->getStatus > $posValue
        : $shutters->getStatus < $posValue
    );

    if (
        (
               $posValue != $shutters->getShadingPos
            or $shutters->getShuttersPlace eq 'terrace'
        )
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
            )
            or (
                CheckIfShuttersWindowRecOpen($shuttersDev) == 2
                and (  $shutters->getLockOut eq 'soft'
                    or $shutters->getLockOut eq 'hard' )
                and $ascDev->getHardLockOut eq 'on'
                and not $queryShuttersPosValue
            )
        )
      )
    {
        $shutters->setDelayCmd($posValue);
        $ascDev->setDelayCmdReading;
        Log3( $name, 4,
            "AutoShuttersControl ($name) - ShuttersCommandSet in Delay" );
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
    }
}

## Sub welche die InternalTimer nach entsprechenden Sunset oder Sunrise zusammen stellt
sub CreateSunRiseSetShuttersTimer($$) {
    my ( $hash, $shuttersDev ) = @_;
    my $name            = $hash->{NAME};
    my $shuttersDevHash = $defs{$shuttersDev};
    $shutters->setShuttersDev($shuttersDev);

    return if ( IsDisabled($name) );

    my $shuttersSunriseUnixtime =
      ShuttersSunrise( $hash, $shuttersDev, 'unix' ) + 1;
    my $shuttersSunsetUnixtime =
      ShuttersSunset( $hash, $shuttersDev, 'unix' ) + 1;

    $shutters->setSunriseUnixTime($shuttersSunriseUnixtime);
    $shutters->setSunsetUnixTime($shuttersSunsetUnixtime);

    ## In jedem Rolladen werden die errechneten Zeiten hinterlegt,es sei denn das autoShuttersControlEvening/Morning auf off steht
    readingsBeginUpdate($shuttersDevHash);
    readingsBulkUpdate(
        $shuttersDevHash,
        'ASC_Time_DriveDown',
        (
            $ascDev->getAutoShuttersControlEvening eq 'on'
            ? strftime(
                "%e.%m.%Y - %H:%M", localtime($shuttersSunsetUnixtime)
              )
            : 'AutoShuttersControl off'
        ),
        1
    );
    readingsBulkUpdate(
        $shuttersDevHash,
        'ASC_Time_DriveUp',
        (
            $ascDev->getAutoShuttersControlMorning eq 'on'
            ? strftime( "%e.%m.%Y - %H:%M",
                localtime($shuttersSunriseUnixtime) )
            : 'AutoShuttersControl off'
        ),
        1
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
        privacyMode    => 0,
        sunsettime     => $shuttersSunsetUnixtime,
        sunrisetime    => $shuttersSunriseUnixtime
    );

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
                'ASC_Time_PrivacyDriveUp',
                strftime(
                    "%e.%m.%Y - %H:%M",
                    localtime($shuttersSunsetUnixtime)
                ),
                0
            );
            $funcHash{privacyMode} = 1;
        }
    }

    InternalTimer( $shuttersSunsetUnixtime,
        'AutoShuttersControl::SunSetShuttersAfterTimerFn', \%funcHash )
      if ( $ascDev->getAutoShuttersControlEvening eq 'on' );
    InternalTimer( $shuttersSunriseUnixtime,
        'AutoShuttersControl::SunRiseShuttersAfterTimerFn', \%funcHash )
      if ( $ascDev->getAutoShuttersControlMorning eq 'on' );

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

    InternalTimer( gettimeofday() + 60, 'AutoShuttersControl::SetCmdFn', \%h );
}
####

## Funktion welche beim Ablaufen des Timers für Sunset aufgerufen werden soll
sub SunSetShuttersAfterTimerFn($) {
    my $funcHash    = shift;
    my $hash        = $funcHash->{hash};
    my $shuttersDev = $funcHash->{shuttersdevice};
    $shutters->setShuttersDev($shuttersDev);

    my $posValue;
    if ( CheckIfShuttersWindowRecOpen($shuttersDev) == 0
        or $shutters->getVentilateOpen eq 'off' )
    {
        $posValue = $shutters->getClosedPos;
    }
    else { $posValue = $shutters->getVentilatePos; }

    my $homemode = $shutters->getRoommatesStatus;
    $homemode = $ascDev->getResidentsStatus if ( $homemode eq 'none' );

    if (
        (
            $shutters->getModeDown eq $homemode
            or (    $shutters->getModeDown eq 'absent'
                and $homemode eq 'gone' )
            or $shutters->getModeDown eq 'always'
        )
        and IsAfterShuttersManualBlocking($shuttersDev)
      )
    {
        $shutters->setLastDrive(
            (
                $funcHash->{privacyMode} == 1
                ? 'privacy position'
                : 'night close'
            )
        );
        ShuttersCommandSet(
            $hash,
            $shuttersDev,
            (
                  $funcHash->{privacyMode} == 1
                ? $shutters->getPrivacyDownPos
                : $posValue
            )
        );
    }

    CreateSunRiseSetShuttersTimer( $hash, $shuttersDev );
}

## Funktion welche beim Ablaufen des Timers für Sunrise aufgerufen werden soll
sub SunRiseShuttersAfterTimerFn($) {
    my $funcHash    = shift;
    my $hash        = $funcHash->{hash};
    my $shuttersDev = $funcHash->{shuttersdevice};
    $shutters->setShuttersDev($shuttersDev);

    my $homemode = $shutters->getRoommatesStatus;
    $homemode = $ascDev->getResidentsStatus if ( $homemode eq 'none' );

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
            and (
                $ascDev->getSelfDefense eq 'off'
                or ( $ascDev->getSelfDefense eq 'on'
                    and CheckIfShuttersWindowRecOpen($shuttersDev) == 0 )
            )
          )
        {
            $shutters->setLastDrive('day open');
            ShuttersCommandSet( $hash, $shuttersDev, $shutters->getOpenPos );
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
        AddNotifyDev( $hash, AttrVal( $_, 'ASC_Brightness_Sensor', 'none' ),
            $_, 'ASC_Brightness_Sensor' )
          if ( AttrVal( $_, 'ASC_Brightness_Sensor', 'none' ) ne 'none' );
        $shuttersList = $shuttersList . ',' . $_;
    }
    AddNotifyDev( $hash, AttrVal( $name, 'ASC_residentsDevice', 'none' ),
        $name, 'ASC_residentsDevice' )
      if ( AttrVal( $name, 'ASC_residentsDevice', 'none' ) ne 'none' );
    AddNotifyDev( $hash, AttrVal( $name, 'ASC_rainSensorDevice', 'none' ),
        $name, 'ASC_rainSensorDevice' )
      if ( AttrVal( $name, 'ASC_rainSensorDevice', 'none' ) ne 'none' );
    AddNotifyDev( $hash, AttrVal( $name, 'ASC_twilightDevice', 'none' ),
        $name, 'ASC_twilightDevice' )
      if ( AttrVal( $name, 'ASC_twilightDevice', 'none' ) ne 'none' );
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
        $ret .= "<td>" . $shutters->getLastDrive . "</td>";
        $ret .= "<td> </td>";
        $ret .= "<td>" . $shutters->getStatus . "</td>";
        $ret .= "<td> </td>";
        $ret .= "<td>" . $shutters->getLastPos . "</td>";
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

    ###### create Links
    my $aHref;

# create define Link
#     $aHref="<a href=\"".$::FW_httpheader->{host}."/fhem?cmd=set+".$::FW_CSRF."\">Create new NOTIFYDEV structure</a>";
#     $aHref="<a href=\"/fhem?cmd=set+\">Create new NOTIFYDEV structure</a>";
#     $aHref="<a href=\"".$headerHost[0]."/fhem?cmd=define+".makeDeviceName($dataset->{station}{name})."+Aqicn+".$dataset->{uid}.$FW_CSRF."\">Create Station Device</a>";

    #     $ret .= '<tr class="odd"> </tr>';
    #     $ret .= '<tr class="even"> </tr>';
    #     $ret .= "<td> </td>";
    #     $ret .= "<td> </td>";
    #     $ret .= "<td> </td>";
    #     $ret .= "<td> </td>";
    #     $ret .= "<td>".$aHref."</td>";
    $ret .= '</table></td></tr>';
    $ret .= '</table></html>';

    return $ret;
}

#################################
## my little helper
#################################

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
sub IsDay($$) {
    my ( $hash, $shuttersDev ) = @_;
    my $name = $hash->{NAME};
    return ( ShuttersSunrise( $hash, $shuttersDev, 'unix' ) >
          ShuttersSunset( $hash, $shuttersDev, 'unix' ) ? 1 : 0 );
}

sub ShuttersSunrise($$$) {
    my ( $hash, $shuttersDev, $tm ) =
      @_;    # Tm steht für Timemode und bedeutet Realzeit oder Unixzeit
    my $name = $hash->{NAME};
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
    my $shuttersSunriseUnixtime;

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
                            $shutters->getTimeUpWeHoliday );
                    }
                    else {
                        $shuttersSunriseUnixtime =
                          computeAlignTime( '24:00',
                            $shutters->getTimeUpEarly );
                    }
                }
                else {
                    $shuttersSunriseUnixtime =
                      computeAlignTime( '24:00',
                        $shutters->getTimeUpWeHoliday );
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

sub IsAfterShuttersTimeBlocking($$) {
    my ( $hash, $shuttersDev ) = @_;
    $shutters->setShuttersDev($shuttersDev);

    if (
        ( int( gettimeofday() ) - $shutters->getLastManPosTimestamp ) <
        $shutters->getBlockingTimeAfterManual
        or ( not IsDay( $hash, $shuttersDev )
            and $shutters->getSunriseUnixTime - ( int( gettimeofday() ) ) <
            $shutters->getBlockingTimeBeforDayOpen )
        or ( IsDay( $hash, $shuttersDev )
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

    if ( ( int( gettimeofday() ) - $shutters->getLastManPosTimestamp ) <
        $shutters->getBlockingTimeAfterManual )
    {
        return 0;
    }

    else { return 1 }
}

sub ShuttersSunset($$$) {
    my ( $hash, $shuttersDev, $tm ) =
      @_;    # Tm steht für Timemode und bedeutet Realzeit oder Unixzeit
    my $name = $hash->{NAME};
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
    my $shuttersSunsetUnixtime;

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
                $shuttersSunsetUnixtime = ( $shuttersSunsetUnixtime + 86400 )
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

    if ( $shutters->getWinStatus eq 'open' ) { return 2; }
    elsif ( $shutters->getWinStatus eq 'tilted'
        and $shutters->getSubTyp eq 'threestate' )
    {
        return 1;
    }
    elsif ( $shutters->getWinStatus eq 'closed' ) { return 0; }
}

sub makeReadingName($) {
    my ($name) = @_;
    my %charHash = (
        "ä" => "ae",
        "Ä" => "Ae",
        "ü" => "ue",
        "Ü" => "Ue",
        "ö" => "oe",
        "Ö" => "Oe",
        "ß" => "ss"
    );
    my $charHashkeys = join( "|", keys(%charHash) );

    $name = "UNDEFINED" if ( !defined($name) );
    return $name if ( $name =~ m/^\./ );
    $name =~ s/($charHashkeys)/$charHash{$1}/gi;
    $name =~ s/[^a-z0-9._\-\/]/_/gi;
    return $name;
}

sub TimeMin2Sec($) {
    my $min = shift;
    my $sec;

    $sec = $min * 60;
    return $sec;
}

sub IsWe() {
    my ( undef, undef, undef, undef, undef, undef, $wday, undef, undef ) =
      localtime( gettimeofday() );
    my $we = ( ( $wday == 0 || $wday == 6 ) ? 1 : 0 );

    if ( !$we ) {
        foreach my $h2we ( split( ",", AttrVal( "global", "holiday2we", "" ) ) )
        {
            my ( $a, $b ) =
              ReplaceEventMap( $h2we, [ $h2we, Value($h2we) ], 0 );
            $we = 1 if ( $b && $b ne "none" );
        }
    }
    return $we;
}

sub IsWeTomorrow() {
    my ( undef, undef, undef, undef, undef, undef, $wday, undef, undef ) =
      localtime( gettimeofday() );
    my $we = (
        ( ( ( $wday + 1 == 7 ? 0 : $wday + 1 ) ) == 0 || ( $wday + 1 ) == 6 )
        ? 1
        : 0
    );

    if ( !$we ) {
        foreach my $h2we ( split( ",", AttrVal( "global", "holiday2we", "" ) ) )
        {
            my ( $a, $b ) = ReplaceEventMap( $h2we,
                [ $h2we, ReadingsVal( $h2we, "tomorrow", "none" ) ], 0 );
            $we = 1 if ( $b && $b ne "none" );
        }
    }
    return $we;
}

sub IsHoliday($) {
    my $hash = shift;
    my $name = $hash->{NAME};

    return (
        ReadingsVal(
            AttrVal( $name, 'ASC_timeUpHolidayDevice',  'none' ),
            AttrVal( $name, 'ASC_timeUpHolidayReading', 'state' ),
            0
        ) == 1 ? 1 : 0
    );
}

sub SetCmdFn($) {
    my $h           = shift;
    my $shuttersDev = $h->{shuttersDev};
    my $posValue    = $h->{posValue};

    $shutters->setShuttersDev($shuttersDev);
    $shutters->setLastDrive( $h->{lastDrive} )
      if ( defined( $h->{lastDrive} ) );

    return
      unless ( $shutters->getASC != 0 );

    if ( $shutters->getStatus != $posValue ) {
        $shutters->setLastPos( $shutters->getStatus );
        $shutters->setLastDriveReading;
        $ascDev->setStateReading;
    }
    else {
        $shutters->setLastDrive(
            ReadingsVal( $shuttersDev, 'ASC_ShuttersLastDrive', 'none' ) );
    }

    CommandSet( undef,
            $shuttersDev
          . ':FILTER='
          . $shutters->getPosCmd . '!='
          . $posValue . ' '
          . $shutters->getPosSetCmd . ' '
          . $posValue );
}

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
          CommandSet)
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
          if ( $shutters->getLockOutCmd eq 'protection' );
    }
    return 0;
}

sub setNoOffset {
    my ( $self, $noOffset ) = @_;

    $self->{ $self->{shuttersDev} }{noOffset} = $noOffset;
    return 0;
}

sub setDriveCmd {
    my ( $self, $posValue ) = @_;
    my $offSet = 0;

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

    $offSet = $shutters->getOffset       if ( $shutters->getOffset > 0 );
    $offSet = $ascDev->getShuttersOffset if ( $shutters->getOffset == -1 );

    InternalTimer(
        gettimeofday() + int( rand($offSet) + $shutters->getOffsetStart ),
        'AutoShuttersControl::SetCmdFn', \%h )
      if ( $offSet > 0 and not $shutters->getNoOffset );
    AutoShuttersControl::SetCmdFn( \%h )
      if ( $offSet == 0 or $shutters->getNoOffset );
    $shutters->setNoOffset(0);

    return 0;
}

sub setSunsetUnixTime {
    my ( $self, $unixtime ) = @_;

    $self->{ $self->{shuttersDev} }{sunsettime} = $unixtime;
    return 0;
}

sub setSunriseUnixTime {
    my ( $self, $unixtime ) = @_;

    $self->{ $self->{shuttersDev} }{sunrisetime} = $unixtime;
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

    readingsSingleUpdate( $shuttersDevHash, 'ASC_ShuttersLastDrive',
        $shutters->getLastDrive, 1 );
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

sub getFreezeStatus {
    use POSIX qw(strftime);
    my $self = shift;
    my $daytime = strftime( "%P", localtime() );

    if (    $shutters->getAntiFreeze ne 'off'
        and $ascDev->getOutTemp <= $ascDev->getFreezeTemp )
    {

        if ( $shutters->getAntiFreeze eq 'soft' ) {
            return 1;
        }
        elsif ($shutters->getAntiFreeze eq $daytime
            or $shutters->getAntiFreeze eq $daytime )
        {
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

sub getSunriseUnixTime {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }{sunrisetime};
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
        'home'      => 4,
        'absent'    => 5,
        'gone'      => 6,
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

### Begin Beschattung Objekt mit Daten befüllen
sub setShading {
    my ( $self, $value ) = @_;
    ### Werte für value = in, out, in reserved, out reserved

    $self->{ $self->{shuttersDev} }{Shading}{VAL} = $value
      if ( defined($value) );
    $self->{ $self->{shuttersDev} }{Shading}{TIME} = int( gettimeofday() )
      if ( defined( $self->{ $self->{shuttersDev} }{Shading} ) );
    return 0;
}

sub getShading {    # Werte für value = in, out, in reserved, out reserved
    my $self = shift;

    return $self->{ $self->{shuttersDev} }{Shading}{VAL}
      if (  defined( $self->{ $self->{shuttersDev} }{Shading} )
        and defined( $self->{ $self->{shuttersDev} }{Shading}{VAL} ) );
}

sub getShadingTimestamp {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }{Shading}{TIME}
      if (  defined( $self->{ $self->{shuttersDev} } )
        and defined( $self->{ $self->{shuttersDev} }{Shading} )
        and defined( $self->{ $self->{shuttersDev} }{Shading}{TIME} ) );
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
          AttrVal)
    );
}

sub getASC {
    ## Dient der Erkennung des Rolladen, 0 bedeutet soll nicht erkannt werden beim ersten Scan und soll nicht bediehnt werden wenn Events kommen
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC', 0 );
}

sub getAntiFreezePos {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Antifreeze_Pos', 50 );
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

sub getWiggleValue {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_WiggleValue', 5 );
}

### Begin Beschattung
sub getShadingPos {
    my $self    = shift;
    my $default = $self->{defaultarg};

    $default = 10 if ( not defined($default) );
    return AttrVal( $self->{shuttersDev}, 'ASC_Shading_Pos', $default );
}

sub getShadingMode {
    my $self    = shift;
    my $default = $self->{defaultarg};

    $default = 'off' if ( not defined($default) );
    return AttrVal( $self->{shuttersDev}, 'ASC_Shading_Mode', $default );
}

sub _getBrightnessSensor {
    my $self    = shift;
    my $default = $self->{defaultarg};

    $default = 'none' if ( not defined($default) );
    return AttrVal( $self->{shuttersDev}, 'ASC_Brightness_Sensor', $default );
}

sub getBrightnessReading {
    my $self    = shift;
    my $default = $self->{defaultarg};

    $default = 'brightness' if ( not defined($default) );
    return AttrVal( $self->{shuttersDev}, 'ASC_Brightness_Reading', $default );
}

sub getDirection {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Shading_Direction', -1 );
}

sub getShadingAngleLeft {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Shading_Angle_Left', -1 );
}

sub getShadingAngleRight {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Shading_Angle_Right', -1 );
}

sub getShadingMinOutsideTemperature {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Shading_Min_OutsideTemperature',
        2 );
}

sub getShadingMinElevation {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Shading_Min_Elevation', 15.0 );
}

sub getShadingStateChangeSunny {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Shading_StateChange_Sunny',
        5000 );
}

sub getShadingStateChangeCloudy {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Shading_StateChange_Cloudy',
        2000 );
}

sub getShadingWaitingPeriod {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Shading_WaitingPeriod', 1200 );
}
### Ende Beschattung

sub getOffset {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Drive_Offset', 0 );
}

sub getOffsetStart {
    my $self = shift;

    return (
          AttrVal( $self->{shuttersDev}, 'ASC_Drive_OffsetStart', 3 ) > 2
        ? AttrVal( $self->{shuttersDev}, 'ASC_Drive_OffsetStart', 3 )
        : 3
    );
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

    return AttrVal( $self->{shuttersDev}, 'ASC_Open_Pos', 0 );
}

sub getVentilatePos {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Ventilate_Pos', 80 );
}

sub getClosedPos {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Closed_Pos', 100 );
}

sub getVentilateOpen {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Ventilate_Window_Open', 'off' );
}

sub getComfortOpenPos {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_ComfortOpen_Pos', 50 );
}

sub getPartyMode {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Partymode', 'off' );
}

sub getRoommates {
    my $self    = shift;
    my $default = $self->{defaultarg};

    $default = 'none' if ( not defined($default) );
    return AttrVal( $self->{shuttersDev}, 'ASC_Roommate_Device', $default );
}

sub getRoommatesReading {
    my $self    = shift;
    my $default = $self->{defaultarg};

    $default = 'state' if ( not defined($default) );
    return AttrVal( $self->{shuttersDev}, 'ASC_Roommate_Reading', $default );
}

sub getModeUp {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Mode_Up', 'off' );
}

sub getModeDown {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Mode_Down', 'off' );
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
    my $self    = shift;
    my $default = $self->{defaultarg};

    $default = 'none' if ( not defined($default) );
    return AttrVal( $self->{shuttersDev}, 'ASC_AutoAstroModeMorning',
        $default );
}

sub getAutoAstroModeEvening {
    my $self    = shift;
    my $default = $self->{defaultarg};

    $default = 'none' if ( not defined($default) );
    return AttrVal( $self->{shuttersDev}, 'ASC_AutoAstroModeEvening',
        $default );
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

    return AttrVal( $self->{shuttersDev}, 'ASC_Time_Up_Early', '04:30:00' );
}

sub getTimeUpLate {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Time_Up_Late', '09:00:00' );
}

sub getTimeDownEarly {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Time_Down_Early', '15:30:00' );
}

sub getTimeDownLate {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Time_Down_Late', '22:00:00' );
}

sub getTimeUpWeHoliday {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_Time_Up_WE_Holiday',
        '04:00:00' );
}

sub getBrightnessMinVal {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_BrightnessMinVal', -1 );
}

sub getBrightnessMaxVal {
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC_BrightnessMaxVal', -1 );
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

    return ReadingsVal( $shutters->_getBrightnessSensor,
        $shutters->getBrightnessReading, -1 );
}

sub getStatus {
    my $self = shift;

    return ReadingsNum( $self->{shuttersDev}, $shutters->getPosCmd, 0 );
}

sub getDelayCmd {
    my $self    = shift;
    my $default = $self->{defaultarg};

    return $self->{ $self->{shuttersDev} }{delayCmd};
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
    my $self    = shift;
    my $default = $self->{defaultarg};

    $default = 'twostate' if ( not defined($default) );
    return AttrVal( $self->{shuttersDev}, 'ASC_WindowRec_subType', $default );
}

sub _getWinDev {
    my $self    = shift;
    my $default = $self->{defaultarg};

    $default = 'none' if ( not defined($default) );
    return AttrVal( $self->{shuttersDev}, 'ASC_WindowRec', $default );
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
    my $self    = shift;
    my $default = $self->{defaultarg};

    $default = 'closed' if ( not defined($default) );
    return ReadingsVal( $shutters->_getWinDev, 'state', $default );
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
    my $default  = $self->{defaultarg};

    $default = 'none' if ( not defined($default) );
    return ReadingsVal( $roommate, $shutters->getRoommatesReading, $default );
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
    my $self    = shift;
    my $name    = $self->{name};
    my $default = $self->{defaultarg};

    $default = 'none' if ( not defined($default) );
    return ReadingsVal( $name, 'partyMode', $default );
}

sub getHardLockOut {
    my $self    = shift;
    my $name    = $self->{name};
    my $default = $self->{defaultarg};

    $default = 'none' if ( not defined($default) );
    return ReadingsVal( $name, 'hardLockOut', $default );
}

sub getSunriseTimeWeHoliday {
    my $self    = shift;
    my $name    = $self->{name};
    my $default = $self->{defaultarg};

    $default = 'none' if ( not defined($default) );
    return ReadingsVal( $name, 'sunriseTimeWeHoliday', $default );
}

sub getMonitoredDevs {
    my $self = shift;
    my $name = $self->{name};

    $self->{monitoredDevs} = ReadingsVal( $name, '.monitoredDevs', 'none' );
    return $self->{monitoredDevs};
}

sub getOutTemp {
    my $self = shift;

    return ReadingsVal( $ascDev->_getTempSensor, $ascDev->getTempReading,
        -100 );
}

sub getResidentsStatus {
    my $self = shift;

    return ReadingsVal( $ascDev->_getResidentsDev, $ascDev->getResidentsReading,
        'none' );
}

sub getResidentsLastStatus {
    my $self = shift;

    return ReadingsVal( $ascDev->_getResidentsDev, 'lastState', 'none' );
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

## Subklasse Attr ##
package ASC_Dev::Attr;

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

sub getShuttersOffset {
    my $self = shift;
    my $name = $self->{name};

    return AttrVal( $name, 'ASC_shuttersDriveOffset', 0 );
}

sub getBrightnessMinVal {
    my $self    = shift;
    my $name    = $self->{name};
    my $default = $self->{defaultarg};

    $default = 8000 if ( not defined($default) );
    return AttrVal( $name, 'ASC_brightnessMinVal', $default );
}

sub getBrightnessMaxVal {
    my $self    = shift;
    my $name    = $self->{name};
    my $default = $self->{defaultarg};

    $default = 20000 if ( not defined($default) );
    return AttrVal( $name, 'ASC_brightnessMaxVal', $default );
}

sub _getTwilightDevice {
    my $self = shift;
    my $name = $self->{name};

    return AttrVal( $name, 'ASC_twilightDevice', 'none' );
}

sub getAutoAstroModeEvening {
    my $self    = shift;
    my $name    = $self->{name};
    my $default = $self->{defaultarg};

    $default = 'none' if ( not defined($default) );
    return AttrVal( $name, 'ASC_autoAstroModeEvening', $default );
}

sub getAutoAstroModeEveningHorizon {
    my $self = shift;
    my $name = $self->{name};

    return AttrVal( $name, 'ASC_autoAstroModeEveningHorizon', 0 );
}

sub getAutoAstroModeMorning {
    my $self    = shift;
    my $name    = $self->{name};
    my $default = $self->{defaultarg};

    $default = 'none' if ( not defined($default) );
    return AttrVal( $name, 'ASC_autoAstroModeMorning', $default );
}

sub getAutoAstroModeMorningHorizon {
    my $self = shift;
    my $name = $self->{name};

    return AttrVal( $name, 'ASC_autoAstroModeMorningHorizon', 0 );
}

sub getAutoShuttersControlMorning {
    my $self    = shift;
    my $name    = $self->{name};
    my $default = $self->{defaultarg};

    $default = 'none' if ( not defined($default) );
    return AttrVal( $name, 'ASC_autoShuttersControlMorning', $default );
}

sub getAutoShuttersControlEvening {
    my $self    = shift;
    my $name    = $self->{name};
    my $default = $self->{defaultarg};

    $default = 'none' if ( not defined($default) );
    return AttrVal( $name, 'ASC_autoShuttersControlEvening', $default );
}

sub getAutoShuttersControlComfort {
    my $self = shift;
    my $name = $self->{name};

    return AttrVal( $name, 'ASC_autoShuttersControlComfort', 'off' );
}

sub getFreezeTemp {
    my $self    = shift;
    my $name    = $self->{name};
    my $default = $self->{defaultarg};

    $default = 'none' if ( not defined($default) );
    return AttrVal( $name, 'ASC_freezeTemp', $default );
}

sub _getTempSensor {
    my $self    = shift;
    my $name    = $self->{name};
    my $default = $self->{defaultarg};

    $default = 'none' if ( not defined($default) );
    return AttrVal( $name, 'ASC_temperatureSensor', $default );
}

sub getTempReading {
    my $self    = shift;
    my $name    = $self->{name};
    my $default = $self->{defaultarg};

    $default = 'none' if ( not defined($default) );
    return AttrVal( $name, 'ASC_temperatureReading', $default );
}

sub _getResidentsDev {
    my $self    = shift;
    my $name    = $self->{name};
    my $default = $self->{defaultarg};

    $default = 'none' if ( not defined($default) );
    return AttrVal( $name, 'ASC_residentsDevice', $default );
}

sub getResidentsReading {
    my $self    = shift;
    my $name    = $self->{name};
    my $default = $self->{defaultarg};

    $default = 'state' if ( not defined($default) );
    return AttrVal( $name, 'ASC_residentsDeviceReading', $default );
}

sub getRainSensor {
    my $self    = shift;
    my $name    = $self->{name};
    my $default = $self->{defaultarg};

    $default = 'none' if ( not defined($default) );
    return AttrVal( $name, 'ASC_rainSensorDevice', $default );
}

sub getRainSensorReading {
    my $self    = shift;
    my $name    = $self->{name};
    my $default = $self->{defaultarg};

    $default = 'state' if ( not defined($default) );
    return AttrVal( $name, 'ASC_rainSensorReading', $default );
}

sub getRainSensorShuttersClosedPos {
    my $self = shift;
    my $name = $self->{name};

    return AttrVal( $name, 'ASC_rainSensorShuttersClosedPos', 50 );
}
1;

=pod
=item device
=item summary       Modul 
=item summary_DE    Modul zur Automatischen Rolladensteuerung auf Basis bestimmter Ereignisse

=begin html

<a name="AutoShuttersControl"></a>
<h3>Automatic shutter control - ASC</h3>
<ul>
  <u><b>AutoShuttersControl in short ASC,controls automatically your shutters following defined rules. i.e. sunrise, sunset or any window event</b></u>
  <br>
  This modul shall control all shutters which are supervised by this Modul following the configuration of attributes in the shutter device. With fitting configuration a shutter will drive up if a resident gets awake and the sun has risen already. It is also possible by tilting a window to bring a closed shutter into airing position.
  <br><br>
  <a name="AutoShuttersControlDefine"></a>
  <b>Define</b>
  <ul><br>
    <code>define &lt;name&gt; AutoShuttersControl</code>
    <br><br>
    Example:
    <ul><br>
      <code>define myASControl AutoShuttersControl</code><br>
    </ul>
    <br>
    This command creates a AutoShuttersControl device named myASControl.<br>
    After creating the device, all shutter devices which shall be controlled have to get set the attribut AutoShuttersControl with value 1 or 2.<br>
    Value 1 means "Inverse or shutter e.g.: shutter up 0,shutter down 100 and the command for percentual movement is position",2 = "Homematic Style e.g.: shutter up 100,shutter down 0 and the command for percentual movement istpct.<br>
    If the attribute is set, you may start automatic scan for your devices .
  </ul>
  <br><br>
  <a name="AutoShuttersControlReadings"></a>
  <b>Readings</b>
  <ul>
    Im Modul Device
    <ul>
      <li>..._nextAstroTimeEvent - time of the next astro event,sunrise,sunset or fixed time per shuttername</li>
      <li>..._PosValue - actual position of shutter</li>
      <li>..._lastPosValue - last position of shutter</li>
      <li>..._lastDelayPosValue - last drive command which is executed at the next permitted event (example: delay because Partymode)</li>
      <li>partyMode - on/off activates the global partymode, all shutters with the attribute ASC_Partymode set to on will not be moved. The last command which had been send by a window event or resident state, will be send again if ASC-Device partyMode is set to off</li>
      <li>lockOut - on/off to activate the lock out mode for the selected shutter. (see description of attributes for die shutterdevices)</li>
      <li>room_... - list of all shutters found in respective rooms, e.g.: room_sleepingroom,terrasse</li>
      <li>state - state of the devices active,enabled,disabled</li>
      <li>sunriseTimeWeHoliday - on/off respects the attribute ASC_Time_Up_WE_Holiday </li>
      <li>userAttrList - list of user attributea which will be send to shutters</li>
    </ul><br>
    Inside the shutter devices
    <ul>
      <li>ASC_Time_DriveUp - sunrise time for this shutter</li>
      <li>ASC_Time_DriveDown - sunset time for this shutter</li>
      <li>ASC_ShuttersLastDrive - last reason for the shutter to move</li>
    </ul>
  </ul>
  <br><br>
  <a name="AutoShuttersControlSet"></a>
  <b>Set</b>
  <ul>
    <li>partyMode - on/off activates the global party mode. see reading partyMode</li>
    <li>lockOut - on/off activates the global lock out mode. see reading lockOut</li>
    <li>renewSetSunriseSunsetTimer - refreshes the timer for sunset, sunrise and the internal timers.</li>
    <li>scanForShutters - searches all FHEM devices with attribute "ASC" 1/2</li>
    <li>sunriseTimeWeHoliday - on/off activates/deactivates respecting attribute ASC_Time_Up_WE_Holiday</li>
    <li>createNewNotifyDev - recreates the internal structure for NOTIFYDEV - attribute ASC_expert has value 1.</li>
    <li>selfDefense - on/off,activates/deactivates the mode self defense. If the resident device says absent and selfDefense is active, each shutter for open windows will be closed.</li>
    <li>wiggle - moves any shutter (for deterrence purposes) by 5% up, and after 1 minute down again to last position.</li> 
  </ul>
  <br><br>
  <a name="AutoShuttersControlGet"></a>
  <b>Get</b>
  <ul>
    <li>showShuttersInformations - shows an overview of all times/timers</li>
    <li>showNotifyDevsInformations - shows an overview of all notify devices. Is used for control - attribute ASC_expert has value 1</li>
  </ul>
  <br><br>
  <a name="AutoShuttersControlAttributes"></a>
  <b>Attributes</b>
  <ul>
  In module device
    <ul>
      <li>ASC_freezeTemp - temperature which inhibits movement of shutter. The last drive command will be stored.</li>
      <li>ASC_autoAstroModeEvening - actual REAL,CIVIL,NAUTIC,ASTRONOMIC</li>
      <li>ASC_autoAstroModeEveningHorizon - heighth above horizon if HORIZON is selected at attribute ASC_autoAstroModeEvening.</li>
      <li>ASC_autoAstroModeMorning - actual REAL,CIVIL,NAUTIC,ASTRONOMIC</li>
      <li>ASC_autoAstroModeMorningHorizon - heighth above horizon if HORIZON is selected at attribute ASC_autoAstroModeMorning.</li>
      <li>ASC_autoShuttersControlComfort - on/off turns on comfort function. Means a shutter with threestate sensor moves to a wide open position. The open position is set at shutter with the attribute ASC_ComfortOpen_Pos.</li>
      <li>ASC_autoShuttersControlEvening - on/off if the shutters shall be controlled by time in the evening.</li>
      <li>ASC_autoShuttersControlMorning - on/off if the shutters shall be controlled by time in the morning.</li>
      <li>ASC_temperatureReading - Reading for outside temperature.</li>
      <li>ASC_temperatureSensor - Device for outside temperature.</li>
      <li>ASC_residentsDevice - devicename of the residents device</li>
      <li>ASC_residentsDeviceReading - state of the residents device</li>
      <li>ASC_brightnessMinVal - minimum brightness value to activate check of conditions</li>
      <li>ASC_brightnessMaxVal - maximum brightness value to activate check of conditions</li>
      <li>ASC_rainSensorDevice - device which triggers when it is raining</li>
      <li>ASC_rainSensorReading - reading of rain sensor device</li>
      <li>ASC_rainSensorShuttersClosedPos - position to be reached if it is raining.</li>
      <li>ASC_shuttersDriveOffset - maximum delay time in seconds for drivetimes, 0 means no delay</li>
      <li>ASC_twilightDevice - Device which provides information about the position of the sun, is used for shading, among other things</li>
    </ul><br>
    In the shutter devices
    <ul>
      <li>AutoShuttersControl - 0/1/2 0 = "no creation of the attributes during the first scan or no attention to a drive command",1 = "Inverse or shutter e.g.: shutter upn 0,shutter down 100 and the command to travel is position",2 = "Homematic Style e.g.: shutter up 100,shutter down 0 and the command to travel is pct</li>
      <li>ASC_Antifreeze - soft/hard/off antifreeze if soft the shutters frive into the ASC_Antifreeze_Pos and if hard / am / pm is not driven or not driven within the appropriate time of day</li>
      <li>ASC_Antifreeze_Pos - Position to be approached when the move command closes completely, but the frost protection is active</li>
      <li>ASC_AutoAstroModeEvening - actual REAL,CIVIL,NAUTIC,ASTRONOMIC</li>
      <li>ASC_AutoAstroModeEveningHorizon - heighth above horizon if HORIZON is selected at attribute ASC_autoAstroModeEvening.</li>
      <li>ASC_AutoAstroModeMorning - actual REAL,CIVIL,NAUTIC,ASTRONOMIC</li>
      <li>ASC_AutoAstroModeMorningHorizon - heighth above horizon if HORIZON is selected at attribute ASC_autoAstroModeMorning.</li>
      <li>ASC_Closed_Pos - in 10th steps from 0 to 100, default value is pending on attribute ASC</li>
      <li>ASC_Down - astro/time/brightness with astro sunset will be calculated, with time the value of ASC_Time_Down_Early will be used and with brightness ASC_Time_Down_Early and ASC_Time_Down_Late has to be defined corectly. The timer uses ASC_Time_Down_Late time, during this time ASC_Time_Down_Early and ASC_Time_Down_Late are respected also, to control ASC_brightnessMinVal. If reached the shutter will travel down.</li>
      <li>ASC_Mode_Down - always/home/absent/off automatic is used: always/home/absent/off (if no roommate defined and absent is set no control will happen)</li>
      <li>ASC_Mode_Up - always/home/absent/off automatic is used: always/home/absent/off (if no roommate defined and absent is set no control will happen)</li>
      <li>ASC_Drive_Offset - maximum random delay in seconds for calculating drivetimes, 0 means no delay, -1 means the corresponding attribute of the ASC device shall be taken into account.</li>
      <li>ASC_Open_Pos -  in 10th steps from 0 bis 100, default value is pending from attribute ASC</li>
      <li>ASC_Partymode -  on/off  turns the partymode on or off. In case of setting ASC-DEVICE to partyMode on, all drive commands of the shutters which have the attribute set to on, will be stored for later usage.</li>
      <li>ASC_Pos_Reading - name of the reading which represents the position of the shutter in percent, is used at unknown device types for set command.</li>
      <li>ASC_ComfortOpen_Pos - in 10th steps from 0 bis 100, default value is pending from attribute ASC</li>
      <li>ASC_Roommate_Reading - the reading of the roommate device which represents the state</li>
      <li>ASC_Roommate_Device - comma seperated names of the roommate device/s representing the habitants of the room of the shutter. Senseless in in any rooms besides sleepingroom and childrens room.</li>
      <li>ASC_Time_Down_Early - Sunset earliest time to travel down</li>
      <li>ASC_Time_Down_Late - Sunset latest time to travel down</li>
      <li>ASC_Time_Up_Early - Sunrise earliest time to travel up</li>
      <li>ASC_Time_Up_Late - Sunrise latest time to travel up</li>
      <li>ASC_Time_Up_WE_Holiday - Sunrise earliest time to travel up at weekend and/or holiday (holiday2we is respected).</li>
      <li>ASC_Up - astro/time/brightness with astro sunrise is calculated, with time the value of ASC_Time_Up_Early is used and with brightness ASC_Time_Up_Early and ASC_Time_Up_Late has to be set correctly. The Timer starts after ASC_Time_Up_Late, but during this time ASC_Time_Up_Early and ASC_Time_Up_Late are used, in combination with the attribute ASC_brightnessMinVal reached, if yes the shutter will travel down</li>
      <li>ASC_Ventilate_Pos -  in 10th steps from 0 bis 100, default value is pending from attribute ASC</li>
      <li>ASC_Ventilate_Window_Open - drive to airing position if the window is tilted or opened and actual position is below airing position</li>
      <li>ASC_WindowRec - name of the window sensor mounted to window</li>
      <li>ASC_WindowRec_subType - type of the used window sensor: twostate (optical oder magnetic) or threestate (rotating handle sensor)</li>
      <li>ASC_LockOut - soft/hard/off sets the lock out mode. With global activated lock out mode (set ASC-Device lockOut soft) and window sensor open, the shutter stays up. This is true only, if commands are given by ASC module. Is global set to hard, the shutter is blocked by hardware if possible. In this case a locally mounted switch can't be used either.</li>
      <li>ASC_LockOut_Cmd - inhibit/blocked/protection set command for the shutter-device for hardware interlock. Possible if "ASC_LockOut" is set to hard</li>
      <li>ASC_Self_Defense_Exclude - on/off to exclude this shutter from active Self Defense. Shutter will not be closed if window is open and residents are absent.</li>
      <li>ASC_Brightness_Sensor - Sensor device used for brightness. ATTENTION! Is used also for ASC_Down - brightness</li>
      <li>ASC_Brightness_Reading - matching reading which fixes the brightness value of ASC_Brightness_Sensor</li>
      <li>ASC_BrightnessMinVal - minimum brightness value to activate check of conditions / if the value -1 is not changed, the value of the module device is used.</li>
      <li>ASC_BrightnessMaxVal - maximum brightness value to activate check of conditions / if the value -1 is not changed, the value of the module device is used.</li>
      <li>ASC_ShuttersPlace - window/terrace, if this attribute is set to terrace and the residents device are in state "gone"and SelfDefence is active the shutter will be closed</li>
    </ul>
  </ul>
</ul>

=end html

=begin html_DE

<a name="AutoShuttersControl"></a>
<h3>Automatische Rollladensteuerung - ASC</h3>
<ul>
  <u><b>AutoShuttersControl - oder kurz ASC - steuert automatisch Deine Rollläden nach bestimmten Vorgaben. Zum Beispiel Sonnenaufgang und Sonnenuntergang oder je nach Fenstervent</b></u>
  <br>
  Dieses Modul soll alle vom Modul &uuml;berwachten Rolll&auml;den entsprechend der Konfiguration &uuml;ber die Attribute im Rollladen Device steuern. Es wird bei entsprechender Konfiguration zum Beispiel die Rolll&auml;den hochfahren, wenn ein Bewohner erwacht ist und draussen bereits die Sonne aufgegangen ist. Auch ist es m&ouml;glich, dass der geschlossene Rollladen bei Ankippen eines Fensters in eine L&uuml;ftungsposition f&auml;hrt.
  <br><br>
  <a name="AutoShuttersControlDefine"></a>
  <b>Define</b>
  <ul><br>
    <code>define &lt;name&gt; AutoShuttersControl</code>
    <br><br>
    Example:
    <ul><br>
      <code>define myASControl AutoShuttersControl</code><br>
    </ul>
    <br>
    Der Befehl erstellt ein AutoShuttersControl Device mit Namen myASControl.<br>
    Nachdem das Device angelegt wurde, muss in allen Rolll&auml;den Devices, welche gesteuert werden sollen, das Attribut ASC mit Wert 1 oder 2 gesetzt werden.<br>
    Dabei bedeutet 1 = "Inverse oder Rollo - Bsp.: Rollo Oben 0,Rollo Unten 100 und der Befehl zum prozentualen Fahren ist position",2 = "Homematic Style - Bsp.: Rollo Oben 100,Rollo Unten 0 und der Befehl zum prozentualen Fahren ist pct.<br>
    Habt Ihr das Attribut gesetzt, k&ouml;nnt Ihr den automatischen Scan nach den Devices anstossen.
  </ul>
  <br><br>
  <a name="AutoShuttersControlReadings"></a>
  <b>Readings</b>
  <ul>
    Im Modul Device
    <ul>
      <li>..._nextAstroTimeEvent - Uhrzeit des n&auml;chsten Astro Events: Sonnenauf- oder Sonnenuntergang oder feste Zeit pro Rollonamen</li>
      <li>..._PosValue - aktuelle Position des Rollladen</li>
      <li>..._lastPosValue - letzte Position des Rollladen</li>
      <li>..._lastDelayPosValue - letzter abgesetzter Fahrbefehl, welcher beim n&auml;chsten zul&auml;ssigen Event ausgef&uuml;hrt wird.</li>
      <li>partyMode - on/off - aktiviert den globalen Partymodus: Alle Rollladen Devices, welche das Attribut ASC_Partymode auf on gestellt haben, werden nicht mehr gesteuert. Der letzte Schaltbefehl, der durch ein Fensterevent oder Bewohnerstatus an die Rolll&auml;den gesendet wurde, wird beim off setzen durch set ASC-Device partyMode off ausgef&uuml;hrt</li>
      <li>lockOut - on/off - f&uuml;r das Aktivieren des Aussperrschutzes gem&auml;&szlig; des entsprechenden Attributs ASC_LockOut im jeweiligen Rollladen. (siehe Beschreibung bei den Attributen f&uuml;r die Rollladendevices)</li>
      <li>room_... - Auflistung aller Rolll&auml;den, welche in den jeweiligen R&auml;men gefunden wurde,Bsp.: room_Schlafzimmer,Terrasse</li>
      <li>state - Status des Devices: active,enabled,disabled oder Info zur letzten Fahrt</li>
      <li>sunriseTimeWeHoliday - on/off - wird das Rollladen Device Attribut  ASC_Time_Up_WE_Holiday beachtet oder nicht</li>
      <li>userAttrList - Status der UserAttribute, welche an die Rolll&auml;den gesendet werden</li>
    </ul><br>
    In den Rolll&auml;den Devices
    <ul>
      <li>ASC_Time_DriveUp - Sonnenaufgangszeit f&uuml;r das Rollo</li>
      <li>ASC_Time_DriveDown - Sonnenuntergangszeit f&uuml;r das Rollo</li>
      <li>ASC_ShuttersLastDrive - Grund des letzten Fahrens vom Rollladen</li>
    </ul>
  </ul>
  <br><br>
  <a name="AutoShuttersControlSet"></a>
  <b>Set</b>
  <ul>
    <li>partyMode - on/off - aktiviert den globalen Partymodus. Siehe Reading partyMode</li>
    <li>lockOut - on/off - aktiviert den globalen Aussperrschutz. Siehe Reading partyMode</li>
    <li>renewSetSunriseSunsetTimer - erneuert bei allen Rolll&auml;den die Zeiten f&uuml;r Sunset und Sunrise und setzt die internen Timer neu.</li>
    <li>scanForShutters - sucht alle FHEM Devices mit dem Attribut "ASC" = 1 oder 2</li>
    <li>sunriseTimeWeHoliday - on/off - aktiviert/deaktiviert die Beachtung des Rollladen Device Attributes ASC_Time_Up_WE_Holiday</li>
    <li>createNewNotifyDev - Legt die interne Struktur f&uuml;r NOTIFYDEV neu an - das Attribut ASC_expert muss 1 sein.</li>
    <li>selfDefense - on/off - aktiviert/deaktiviert den Selbstschutz, wenn das Residents Device absent meldet, selfDefense aktiv ist und ein Fenster im Haus  noch offen steht, wird an diesem Fenster das Rollo runtergefahren</li>
    <li>wiggle - bewegt einen Rollladen oder alle Rolll&auml;den (f&uuml;r Abschreckungszwecke bei der Alarmierung) um 5%, und nach 1 Minute wieder zur&uuml;ck zur Ursprungsposition</li>
  </ul>
  <br><br>
  <a name="AutoShuttersControlGet"></a>
  <b>Get</b>
  <ul>
    <li>showShuttersInformations - zeigt eine &Uuml;bersicht der Autofahrzeiten</li>
    <li>showNotifyDevsInformations - zeigt eine &Uuml;bersicht der abgelegten NOTIFYDEV Struktur. Dient zur Kontrolle - das Attribut ASC_expert muss 1 sein.</li>
  </ul>
  <br><br>
  <a name="AutoShuttersControlAttributes"></a>
  <b>Attributes</b>
  <ul>
  Im Modul Device
    <ul>
      <li>ASC_freezeTemp - Temperatur, ab welcher der Frostschutz greifen soll und das Rollo nicht mehr f&auml;hrt. Der letzte Fahrbefehl wird gespeichert.</li>
      <li>ASC_autoAstroModeEvening - aktuell REAL,CIVIL,NAUTIC,ASTRONOMIC</li>
      <li>ASC_autoAstroModeEveningHorizon - H&ouml;he &uuml;ber Horizont wenn beim Attribut ASC_autoAstroModeEvening HORIZON ausgew&auml;hlt</li>
      <li>ASC_autoAstroModeMorning - aktuell REAL,CIVIL,NAUTIC,ASTRONOMIC</li>
      <li>ASC_autoAstroModeMorningHorizon - H&ouml;he &uuml;ber Horizont wenn beim Attribut ASC_autoAstroModeMorning HORIZON ausgew&auml;hlt</li>
      <li>ASC_autoShuttersControlComfort - on/off - schaltet die Komfortfunktion an. Bedeutet, dass ein Rollladen mit einem threestate Sensor am Fenster beim &ouml;ffnen in eine Offenposition f&auml;hrt, die  beim Rollladen &uuml;ber das Attribut ASC_ComfortOpen_Pos eingestellt wird.</li>
      <li>ASC_autoShuttersControlEvening - on/off - ob Abends die Rolll&auml;den automatisch nach Zeit gesteuert werden sollen</li>
      <li>ASC_autoShuttersControlMorning - on/off - ob Morgens die Rolll&auml;den automatisch nach Zeit gesteuert werden sollen</li>
      <li>ASC_temperatureReading - Reading f&uuml;r die Aussentemperatur</li>
      <li>ASC_temperatureSensor - Device f&uuml;r die Aussentemperatur</li>
      <li>ASC_residentsDevice - Devicenamen des Residents Device der obersten Ebene</li>
      <li>ASC_residentsDeviceReading - Status Reading vom Residents Device der obersten Ebene</li>
      <li>ASC_brightnessMinVal - minimaler Lichtwert, bei dem Schaltbedingungen gepr&uuml;ft werden sollen</li>
      <li>ASC_brightnessMaxVal - maximaler Lichtwert, bei dem Schaltbedingungen gepr&uuml;ft werden sollen</li>
      <li>ASC_rainSensorDevice - Device, welches bei Regen getriggert werden soll</li>
      <li>ASC_rainSensorReading - das ensprechende Reading zum Regendevice</li>
      <li>ASC_rainSensorShuttersClosedPos - Position in pct, welche der Rollladen anfahren soll, wenn es Regnet</li>
      <li>ASC_shuttersDriveOffset - maximal zuf&auml;llige Verz&ouml;gerung in Sekunden bei der Berechnung der Fahrzeiten, 0 bedeutet keine Verz&ouml;gerung</li>
      <li>ASC_twilightDevice - Device welches Informationen zum Sonnenstand liefert, wird unter anderem f&uuml;r die Beschattung verwendet.</li>
      <li>ASC_expert - ist der Wert 1 werden erweiterte Informationen bez&uuml;glich des NotifyDevs unter set und get angezeigt</li>
    </ul><br>
    In den Rolll&auml;den Devices
    <ul>
      <li>ASC - 0/1/2 0 = "kein Anlegen der Attribute beim ersten Scan bzw. keine Beachtung eines Fahrbefehles",1 = "Inverse oder Rollo - Bsp.: Rollo Oben 0, Rollo Unten 100 und der Befehl zum prozentualen Fahren ist position",2 = "Homematic Style - Bsp.: Rollo Oben 100, Rollo Unten 0 und der Befehl zum prozentualen Fahren ist pct</li>
      <li>ASC_Antifreeze - soft/am/pm/hard/off - Frostschutz, wenn soft f&auml;hrt der Rollladen in die ASC_Antifreeze_Pos und wenn hard/am/pm wird gar nicht oder innerhalb der entsprechenden Tageszeit nicht gefahren</li>
      <li>ASC_Antifreeze_Pos - Position die angefahren werden soll wenn der Fahrbefehl komplett schlie&szlig;en lautet, aber der Frostschutz aktiv ist</li>
      <li>ASC_AutoAstroModeEvening - aktuell REAL,CIVIL,NAUTIC,ASTRONOMIC</li>
      <li>ASC_AutoAstroModeEveningHorizon - H&ouml;he &uuml;ber Horizont wenn beim Attribut ASC_autoAstroModeEvening HORIZON ausgew&auml;hlt</li>
      <li>ASC_AutoAstroModeMorning - aktuell REAL,CIVIL,NAUTIC,ASTRONOMIC</li>
      <li>ASC_AutoAstroModeMorningHorizon - H&ouml;he &uuml;ber Horizont wenn beim Attribut ASC_autoAstroModeMorning HORIZON ausgew&auml;hlt</li>
      <li>ASC_Closed_Pos - in 10 Schritten von 0 bis 100, Default ist abh&auml;ngig vom Attribut ASC</li>
      <li>ASC_Down - astro/time/brightness - bei astro wird Sonnenuntergang berechnet, bei time wird der Wert aus ASC_Time_Down_Early als Fahrzeit verwendet und bei brightness muss ASC_Time_Down_Early und ASC_Time_Down_Late korrekt gesetzt werden. Der Timer l&auml;uft dann nach ASC_Time_Down_Late Zeit, es wird aber in der Zeit zwischen ASC_Time_Down_Early und ASC_Time_Down_Late geschaut, ob die als Attribut im Moduldevice hinterlegte ASC_brightnessMinVal erreicht wurde. Wenn ja, wird der Rollladen runter gefahren</li>
      <li>ASC_Mode_Down - always/home/absent/off - Wann darf die Automatik steuern. immer, niemals, bei Abwesenheit des Roommate (ist kein Roommate und absent eingestellt, wird gar nicht gesteuert)</li>
      <li>ASC_Mode_Up - always/home/absent/off - Wann darf die Automatik steuern. immer, niemals, bei Abwesenheit des Roommate (ist kein Roommate und absent eingestellt, wird gar nicht gesteuert)</li>
      <li>ASC_Drive_Offset - maximaler Wert f&uuml;r einen zuf&auml;llig ermittelte Verz&ouml;gerungswert in Sekunden bei der Berechnung der Fahrzeiten, 0 bedeutet keine Verz&ouml;gerung, -1 bedeutet, dass das gleichwertige Attribut aus dem ASC Device ausgewertet werden soll.</li>
      <li>ASC_Drive_OffsetStart - in Sekunden verz&ouml;gerter Wert ab welchen dann erst das Offset startet und dazu addiert wird. Funktioniert nur wenn gleichzeitig ein Drive_Offset gesetzt wird.</li>
      <li>ASC_Open_Pos -  in 10 Schritten von 0 bis 100, Default ist abh&auml;ngig vom Attribut ASC</li>
      <li>ASC_Partymode -  on/off - schaltet den Partymodus an oder aus. Wird  am ASC Device set ASC-DEVICE partyMode on geschalten, werden alle Fahrbefehle an den Rolll&auml;den, welche das Attribut auf on haben, zwischengespeichert und sp&auml;ter erst ausgef&uuml;hrt</li>
      <li>ASC_Pos_Reading - Name des Readings, welches die Position des Rollladen in Prozent an gibt; wird bei unbekannten Device Typen auch als set Befehl zum fahren verwendet</li>
      <li>ASC_ComfortOpen_Pos - in 10 Schritten von 0 bis 100, Default ist abh&auml;ngig vom Attribut ASC</li>
      <li>ASC_Roommate_Reading - das Reading zum Roommate Device, welches den Status wieder gibt</li>
      <li>ASC_Roommate_Device - mit Komma getrennte Namen des/der Roommate Device/s, welche den/die Bewohner des Raumes vom Rollladen wiedergibt. Es macht nur Sinn in Schlaf- oder Kinderzimmern</li>
      <li>ASC_Time_Down_Early - Sunset fr&uuml;hste Zeit zum Runterfahren</li>
      <li>ASC_Time_Down_Late - Sunset sp&auml;teste Zeit zum Runterfahren</li>
      <li>ASC_Time_Up_Early - Sunrise fr&uuml;hste Zeit zum Hochfahren</li>
      <li>ASC_Time_Up_Late - Sunrise sp&auml;teste Zeit zum Hochfahren</li>
      <li>ASC_Time_Up_WE_Holiday - Sunrise fr&uuml;hste Zeit zum Hochfahren am Wochenende und/oder Urlaub (holiday2we wird beachtet).</li>
      <li>ASC_Up - astro/time/brightness - bei astro wird Sonnenaufgang berechnet, bei time wird der Wert aus ASC_Time_Up_Early als Fahrzeit verwendet und bei brightness muss ASC_Time_Up_Early und ASC_Time_Up_Late korrekt gesetzt werden. Der Timer l&auml;uft dann nach ASC_Time_Up_Late Zeit, es wird aber in der Zeit zwischen ASC_Time_Up_Early und ASC_Time_Up_Late geschaut, ob die als Attribut im Moduldevice hinterlegte ASC_brightnessMinVal erreicht wurde. Wenn ja, wird der Rollladen runtergefahren</li>
      <li>ASC_Ventilate_Pos -  in 10 Schritten von 0 bis 100, Default ist abh&auml;ngig vom Attribut ASC</li>
      <li>ASC_Ventilate_Window_Open - auf l&uuml;ften, wenn das Fenster gekippt/ge&ouml;ffnet wird und aktuelle Position unterhalb der L&uuml;ften-Position ist</li>
      <li>ASC_WindowRec - Name des Fensterkontaktes, an dessen Fenster der Rollladen angebracht ist</li>
      <li>ASC_WindowRec_subType - Typ des verwendeten Fensterkontaktes: twostate (optisch oder magnetisch) oder threestate (Drehgriffkontakt)</li>
      <li>ASC_LockOut - soft/hard/off - stellt entsprechend den Aussperrschutz ein. Bei global aktivem Aussperrschutz (set ASC-Device lockOut soft) und einem Fensterkontakt open bleibt dann der Rollladen oben. Dies gilt nur bei Steuerbefehle über das ASC Modul. Stellt man global auf hard, wird bei entsprechender M&ouml;glichkeit versucht den Rollladen hardwareseitig zu blockieren. Dann ist auch ein Fahren &uuml;ber die Taster nicht mehr m&ouml;glich.</li>
      <li>ASC_LockOut_Cmd - inhibit/blocked/protection - set Befehl f&uuml;r das Rollladen-Device zum Hardware sperren. Dieser Befehl wird gesetzt werden, wenn man "ASC_LockOut" auf hard setzt</li>
      <li>ASC_Self_Defense_Exclude - on/off - bei on Wert wird dieser Rollladen bei aktiven Self Defense und offenen Fenster nicht runter gefahren, wenn Residents absent ist.</li>
      <li>ASC_Brightness_Sensor - Sensor Device, welches f&uuml;r die Lichtwerte verwendet wird.</li>
      <li>ASC_Brightness_Reading - passendes Reading welcher den Helligkeitswert von ASC_Brightness_Sensor anth&auml;lt</li>
      <li>ASC_BrightnessMinVal - minimaler Lichtwert, bei dem Schaltbedingungen gepr&uuml;ft werden sollen / wird der Wert von -1 nicht ge&auml;ndert, so wird automatisch der Wert aus dem Moduldevice genommen</li>
      <li>ASC_BrightnessMaxVal - maximaler Lichtwert, bei dem  Schaltbedingungen gepr&uuml;ft werden sollen / wird der Wert von -1 nicht ge&auml;ndert, so wird automatisch der Wert aus dem Moduldevice genommen</li>
      <li>ASC_ShuttersPlace - window/terrace - Wenn dieses Attribut auf terrace gesetzt ist, das Residence Device in den Status "gone" geht und SelfDefence aktiv ist (ohne das das Reading selfDefense gesetzt sein muss), wird das Rollo geschlossen</li>
      <li>ASC_WiggleValue - Wert um welchen sich die Position des Rollladens &auml;ndern soll</li>
      <li>ASC_BlockingTime_afterManual - wie viel Sekunden soll die Automatik nach einer manuellen Fahrt aus setzen.</li>
      <li>ASC_BlockingTime_beforNightClose - wie viel Sekunden vor dem n&auml;chtlichen schlie&zlig;en soll keine &ouml;ffnen Fahrt mehr statt finden.</li>
      <li>ASC_BlockingTime_beforDayOpen - wie viel Sekunden vor dem morgendlichen &ouml;ffnen soll keine schließen Fahrt mehr statt finden.</li>
      <li>ASC_Shading_Direction -  Position in Grad, auf der das Fenster liegt - genau Osten w&auml;re 90, S&uuml;den 180 und Westen 270</li>
      <li>ASC_Shading_Pos - Position des Rollladens für die Beschattung</li>
      <li>ASC_Shading_Mode - absent,always,off,home / wann soll die Beschattung nur statt finden.</li>
      <li>ASC_Shading_Angle_Left - Vorlaufwinkel im Bezug zum Fenster, ab wann abgeschattet wird. Beispiel: Fenster 180° - 85° ==> ab Sonnenpos. 95° wird abgeschattet</li>
      <li>ASC_Shading_Angle_Right - Nachlaufwinkel im Bezug zum Fenster, bis wann abgeschattet wird. Beispiel: Fenster 180° + 85° ==> bis Sonnenpos. 265° wird abgeschattet</li>
      <li>ASC_Shading_StateChange_Sunny - Brightness Wert ab welchen Beschattung statt finden soll, immer in Abh&auml;ngikkeit der anderen einbezogenden Sensorwerte</li>
      <li>ASC_Shading_StateChange_Cloudy - Brightness Wert ab welchen die Beschattung aufgehoben werden soll, immer in Abh&auml;ngikkeit der anderen einbezogenden Sensorwerte</li>
      <li>ASC_Shading_Min_Elevation - ab welcher Höhe des Sonnenstandes soll beschattet werden, immer in Abh&auml;ngikkeit der anderen einbezogenden Sensorwerte</li>
      <li>ASC_Shading_Min_OutsideTemperature - ab welcher Temperatur soll Beschattet werden, immer in Abh&auml;ngikkeit der anderen einbezogenden Sensorwerte</li>
      <li>ASC_Shading_WaitingPeriod - wie viele Sekunden soll gewartet werden bevor eine weitere Auswertung der Sensordaten für die Beschattung statt finden soll</li>
      <li>ASC_PrivacyDownTime_beforNightClose - wie viele Sekunden vor dem abendlichen schlie&zlig;en soll der Rollladen in die Sichtschutzposition fahren, -1 bedeutet das diese Funktion unbeachtet bleiben soll</li>
      <li>ASC_PrivacyDown_Pos - Position den Rollladens f&uuml;r den Sichtschutz</li>
    </ul>
  </ul>
</ul>

=end html_DE

=cut
