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
# !!!!! - Innerhalb einer Shutterschleife kein CommandAttr verwenden. Bring Fehler!!! Kommen Raumnamen in die Shutterliste !!!!!!
#

package main;

use strict;
use warnings;
use FHEM::Meta;

my $version = '0.6.4';

sub AutoShuttersControl_Initialize($) {
    my ($hash) = @_;

    ### alte Attribute welche entfernt werden
    my $oldAttr =
        'ASC_temperatureSensor '
      . 'ASC_temperatureReading '
      . 'ASC_residentsDevice '
      . 'ASC_residentsDeviceReading '
      . 'ASC_rainSensorDevice '
      . 'ASC_rainSensorReading '
      . 'ASC_rainSensorShuttersClosedPos:0,10,20,30,40,50,60,70,80,90,100 '
      . 'ASC_brightnessMinVal '
      . 'ASC_brightnessMaxVal ';

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
      . 'ASC_autoShuttersControlShading:on,off '
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
      . $oldAttr
      . $readingFnAttributes;
    $hash->{NotifyOrderPrefix} = '51-';    # Order Nummer für NotifyFn

    return FHEM::Meta::InitMod( __FILE__, $hash );
}

## unserer packagename
package FHEM::AutoShuttersControl;

use strict;
use warnings;
use POSIX;
use FHEM::Meta;

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
    'ASC_Mode_Up:absent,always,off,home'                            => '-',
    'ASC_Mode_Down:absent,always,off,home'                          => '-',
    'ASC_Up:time,astro,brightness'                                  => '-',
    'ASC_Down:time,astro,brightness'                                => '-',
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
    'ASC_WindowRec'                              => '-',
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
    'ASC_Shading_Min_Elevation'                            => '-',
    'ASC_Shading_Min_OutsideTemperature'                   => '-',
    'ASC_Shading_WaitingPeriod'                            => '-',
    'ASC_Drive_Offset'                                     => '-',
    'ASC_Drive_OffsetStart'                                => '-',
    'ASC_WindowRec_subType:twostate,threestate'            => '-',
    'ASC_ShuttersPlace:window,terrace'                     => '-',
    'ASC_Ventilate_Pos:10,20,30,40,50,60,70,80,90,100'     => [ '', 70, 30 ],
    'ASC_ComfortOpen_Pos:0,10,20,30,40,50,60,70,80,90,100' => [ '', 20, 80 ],
    'ASC_GuestRoom:on,off'                                 => '-',
    'ASC_Antifreeze:off,soft,hard,am,pm'                   => '-',
'ASC_Antifreeze_Pos:5,10,15,20,25,30,35,40,45,50,55,60,65,70,75,80,85,90,95,100'
      => [ '', 85, 15 ],
    'ASC_Partymode:on,off'            => '-',
    'ASC_Roommate_Device'             => '-',
    'ASC_Roommate_Reading'            => '-',
    'ASC_Self_Defense_Exclude:on,off' => '-',
    'ASC_WiggleValue'                 => '-',
    'ASC_WindParameters'              => '-',
    'ASC_DriveUpMaxDuration'          => '-',
    'ASC_WindProtection:on,off'       => '-',
    'ASC_RainProtection:on,off'       => '-',
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

    return $@ unless ( FHEM::Meta::SetInternals($hash) );
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

        delFromDevAttrList( $_, 'ASC_Wind_SensorDevice' )
          ;    # temporär muss später gelöscht werden ab Version 0.4.0.10
        delFromDevAttrList( $_, 'ASC_Wind_SensorReading' )
          ;    # temporär muss später gelöscht werden ab Version 0.4.0.10
        delFromDevAttrList( $_, 'ASC_Wind_minMaxSpeed' )
          ;    # temporär muss später gelöscht werden ab Version 0.4.11beta6
        delFromDevAttrList( $_, 'ASC_Wind_Pos' )
          ;    # temporär muss später gelöscht werden ab Version 0.4.11beta6

        $shuttersList = $shuttersList . ',' . $_;
        $shutters->setShuttersDev($_);
        $shutters->setLastManPos( $shutters->getStatus );
        $shutters->setLastPos( $shutters->getStatus );
        $shutters->setDelayCmd('none');
        $shutters->setNoOffset(0);
        $shutters->setPosSetCmd( $posSetCmds{ $defs{$_}->{TYPE} } );
        $shutters->setShadingStatus(
            ( $shutters->getStatus != $shutters->getShadingPos ? 'out' : 'in' )
        );
    }

    ### Temporär und muss später entfernt werden
    CommandAttr( undef,
            $name
          . ' ASC_tempSensor '
          . AttrVal( $name, 'ASC_temperatureSensor',  'none' ) . ':'
          . AttrVal( $name, 'ASC_temperatureReading', 'temperature' ) )
      if ( AttrVal( $name, 'ASC_temperatureSensor', 'none' ) ne 'none' );
    CommandAttr( undef,
            $name
          . ' ASC_residentsDev '
          . AttrVal( $name, 'ASC_residentsDevice',        'none' ) . ':'
          . AttrVal( $name, 'ASC_residentsDeviceReading', 'state' ) )
      if ( AttrVal( $name, 'ASC_residentsDevice', 'none' ) ne 'none' );
    CommandAttr( undef,
            $name
          . ' ASC_rainSensor '
          . AttrVal( $name, 'ASC_rainSensorDevice',  'none' ) . ':'
          . AttrVal( $name, 'ASC_rainSensorReading', 'rain' ) . ' 100 '
          . AttrVal( $name, 'ASC_rainSensorShuttersClosedPos', 50 ) )
      if ( AttrVal( $name, 'ASC_rainSensorDevice', 'none' ) ne 'none' );
    CommandAttr( undef,
            $name
          . ' ASC_brightnessDriveUpDown '
          . AttrVal( $name, 'ASC_brightnessMinVal', 500 ) . ':'
          . AttrVal( $name, 'ASC_brightnessMaxVal', 800 ) )
      if ( AttrVal( $name, 'ASC_brightnessMinVal', 'none' ) ne 'none' );

    CommandDeleteAttr( undef, $name . ' ASC_temperatureSensor' )
      if ( AttrVal( $name, 'ASC_temperatureSensor', 'none' ) ne 'none' );
    CommandDeleteAttr( undef, $name . ' ASC_temperatureReading' )
      if ( AttrVal( $name, 'ASC_temperatureReading', 'none' ) ne 'none' );
    CommandDeleteAttr( undef, $name . ' ASC_residentsDevice' )
      if ( AttrVal( $name, 'ASC_residentsDevice', 'none' ) ne 'none' );
    CommandDeleteAttr( undef, $name . ' ASC_residentsDeviceReading' )
      if ( AttrVal( $name, 'ASC_residentsDeviceReading', 'none' ) ne 'none' );
    CommandDeleteAttr( undef, $name . ' ASC_rainSensorDevice' )
      if ( AttrVal( $name, 'ASC_rainSensorDevice', 'none' ) ne 'none' );
    CommandDeleteAttr( undef, $name . ' ASC_rainSensorReading' )
      if ( AttrVal( $name, 'ASC_rainSensorReading', 'none' ) ne 'none' );
    CommandDeleteAttr( undef, $name . ' ASC_rainSensorShuttersClosedPos' )
      if (
        AttrVal( $name, 'ASC_rainSensorShuttersClosedPos', 'none' ) ne 'none' );
    CommandDeleteAttr( undef, $name . ' ASC_brightnessMinVal' )
      if ( AttrVal( $name, 'ASC_brightnessMinVal', 'none' ) ne 'none' );
    CommandDeleteAttr( undef, $name . ' ASC_brightnessMaxVal' )
      if ( AttrVal( $name, 'ASC_brightnessMaxVal', 'none' ) ne 'none' );

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

        ### associatedWith damit man sieht das der Rollladen mit einem ASC Device verbunden ist
        readingsSingleUpdate(
            $defs{$_},
            'associatedWith',
            (
                ReadingsVal( $_, 'associatedWith', $name ) eq $name
                ? $name
                : ReadingsVal( $_, 'associatedWith', 'none' ) . ',' . $name
            ),
            0
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
            }
            ## Oder das Attribut wird wieder gelöscht.
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

    if (
        $events =~
        m#state:\s(open(ed)?|closed|tilted)# # weitere mögliche Events  (opened / closed)
        and IsAfterShuttersManualBlocking($shuttersDev)
      )
    {
        $shutters->setShuttersDev($shuttersDev);
        my $homemode = $shutters->getRoommatesStatus;
        $homemode = $ascDev->getResidentsStatus if ( $homemode eq 'none' );

        #### Hardware Lock der Rollläden
        $shutters->setHardLockOut('off')
          if ( $1 eq 'closed' and $shutters->getShuttersPlace eq 'terrace' );
        $shutters->setHardLockOut('on')
          if ( ( $1 eq 'open' or $1 eq 'opened' )
            and $shutters->getShuttersPlace eq 'terrace' );

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

        ASC_Debug( 'EventProcessingWindowRec: '
              . $shutters->getShuttersDev
              . ' - HOMEMODE: '
              . $homemode
              . ' : QueryShuttersPosWinRecTilted'
              . $queryShuttersPosWinRecTilted
              . ' QueryShuttersPosWinRecComfort: '
              . $queryShuttersPosWinRecComfort );

        if (
                $1 eq 'closed'
            and IsAfterShuttersTimeBlocking($shuttersDev)
            and (  $shutters->getStatus == $shutters->getVentilatePos
                or $shutters->getStatus == $shutters->getComfortOpenPos
                or $shutters->getStatus == $shutters->getOpenPos )
          )
        {
            if (
                    IsDay($shuttersDev)
                and $shutters->getStatus != $shutters->getOpenPos
                and ( ( $homemode ne 'asleep' and $homemode ne 'gotosleep' )
                    or $homemode eq 'none' )
                and $shutters->getModeUp ne 'absent'
                and $shutters->getModeUp ne 'off'
              )
            {
                $shutters->setLastDrive('window closed at day');
                $shutters->setNoOffset(1);
                $shutters->setDriveCmd(
                    (
                          $shutters->getLastPos != $shutters->getClosedPos
                        ? $shutters->getLastPos
                        : $shutters->getOpenPos
                    )
                );
            }

            elsif (
                    $shutters->getModeUp ne 'absent'
                and $shutters->getModeUp ne 'off'
                and (  not IsDay($shuttersDev)
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
                $1 eq 'tilted'
                or ( ( $1 eq 'open' or $1 eq 'opened' )
                    and $shutters->getSubTyp eq 'twostate' )
            )
            and $shutters->getVentilateOpen eq 'on'
            and $queryShuttersPosWinRecTilted
          )
        {
            $shutters->setLastDrive('ventilate - window open');
            $shutters->setNoOffset(1);
            $shutters->setDriveCmd( $shutters->getVentilatePos );
        }
        elsif ( ( $1 eq 'open' or $1 eq 'opened' )
            and $shutters->getSubTyp eq 'threestate' )
        {
            my $posValue;
            my $setLastDrive;
            if (    $ascDev->getAutoShuttersControlComfort eq 'on'
                and $queryShuttersPosWinRecComfort )
            {
                $posValue     = $shutters->getComfortOpenPos;
                $setLastDrive = 'comfort - window open';
            }
            elsif ( $queryShuttersPosWinRecTilted
                and $shutters->getVentilateOpen eq 'on' )
            {
                $posValue     = $shutters->getVentilatePos;
                $setLastDrive = 'ventilate - window open';
            }

            if ( defined($posValue) and $posValue ) {
                $shutters->setLastDrive($setLastDrive);
                $shutters->setNoOffset(1);
                $shutters->setDriveCmd($posValue);
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
        my $getRoommatesLastStatus = $shutters->getRoommatesLastStatus;

        if (
            ( $1 eq 'home' or $1 eq 'awoken' )
            and (  $shutters->getRoommatesStatus eq 'home'
                or $shutters->getRoommatesStatus eq 'awoken' )
            and $ascDev->getAutoShuttersControlMorning eq 'on'
            and (  $getModeUp eq 'home'
                or $getModeUp eq 'always'
                or $getModeDown eq 'home'
                or $getModeDown eq 'always' )
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
                and IsDay($shuttersDev)
                and IsAfterShuttersTimeBlocking($shuttersDev)
                and (  $getModeUp eq 'home'
                    or $getModeUp eq 'always' )
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
                       $getRoommatesLastStatus eq 'absent'
                    or $getRoommatesLastStatus eq 'gone'

                    #                     or $getRoommatesLastStatus eq 'home'
                )
                and $shutters->getRoommatesStatus eq 'home'
              )
            {
                if (
                        not IsDay($shuttersDev)
                    and IsAfterShuttersTimeBlocking($shuttersDev)
                    and (  $getModeDown eq 'home'
                        or $getModeDown eq 'always' )
                  )
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
                elsif (
                        IsDay($shuttersDev)
                    and $shutters->getStatus == $shutters->getClosedPos
                    and IsAfterShuttersTimeBlocking($shuttersDev)
                    and (  $getModeUp eq 'home'
                        or $getModeUp eq 'always' )
                    and not $shutters->getIfInShading
                  )
                {
                    $shutters->setLastDrive('roommate home');
                    ShuttersCommandSet( $hash, $shuttersDev,
                        $shutters->getOpenPos );
                }
            }
        }
        elsif (
            (
                   $getModeDown eq 'always'
                or $getModeDown eq 'home'
            )
            and ( $1 eq 'gotosleep' or $1 eq 'asleep' )
            and $ascDev->getAutoShuttersControlEvening eq 'on'
            and IsAfterShuttersManualBlocking($shuttersDev)
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
        elsif ( $getModeDown eq 'absent'
            and $1 eq 'absent'
            and not IsDay($shuttersDev) )
        {
            $shutters->setLastDrive('roommate absent');
            ShuttersCommandSet( $hash, $shuttersDev, $shutters->getClosedPos );
        }
    }
}

sub EventProcessingResidents($@) {
    my ( $hash, $device, $events ) = @_;

    my $name                   = $device;
    my $reading                = $ascDev->getResidentsReading;
    my $getResidentsLastStatus = $ascDev->getResidentsLastStatus;

    if ( $events =~ m#$reading:\s(absent)# ) {
        foreach my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
            $shutters->setShuttersDev($shuttersDev);
            my $getModeUp   = $shutters->getModeUp;
            my $getModeDown = $shutters->getModeDown;
            $shutters->setHardLockOut('off');
            if (
                    CheckIfShuttersWindowRecOpen($shuttersDev) != 0
                and $ascDev->getSelfDefense eq 'on'
                and $shutters->getSelfDefenseExclude eq 'off'
                or (
                    (
                           $getModeDown eq 'absent'
                        or $getModeDown eq 'always'
                    )
                    and not IsDay($shuttersDev)
                    and IsAfterShuttersTimeBlocking($shuttersDev)
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
            my $getModeUp   = $shutters->getModeUp;
            my $getModeDown = $shutters->getModeDown;
            $shutters->setHardLockOut('off');
            if ( $shutters->getShuttersPlace eq 'terrace' ) {
                $shutters->setLastDrive('selfeDefense terrace');
                $shutters->setDriveCmd( $shutters->getClosedPos );
            }
        }
    }
    elsif (
        $events =~ m#$reading:\s(home)#
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
                and not IsDay($shuttersDev)
                and $shutters->getRoommatesStatus eq 'none'
                and (  $getModeDown eq 'home'
                    or $getModeDown eq 'always' )
                and (  $getResidentsLastStatus ne 'asleep'
                    or $getResidentsLastStatus ne 'awoken' )
                and IsAfterShuttersTimeBlocking($shuttersDev)
              )
            {
                $shutters->setLastDrive('residents home');
                $shutters->setDriveCmd( $shutters->getClosedPos );
            }
            elsif (
                    $ascDev->getSelfDefense eq 'on'
                and CheckIfShuttersWindowRecOpen($shuttersDev) != 0
                and $shutters->getSelfDefenseExclude eq 'off'
                or (    $getResidentsLastStatus eq 'gone'
                    and $shutters->getShuttersPlace eq 'terrace' )
                and (  $getModeUp eq 'absent'
                    or $getModeUp eq 'off' )
                and not $shutters->getIfInShading
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
                and IsDay($shuttersDev)
                and $shutters->getRoommatesStatus eq 'none'
                and (  $getModeUp eq 'home'
                    or $getModeUp eq 'always' )
                and IsAfterShuttersTimeBlocking($shuttersDev)
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
                and IsAfterShuttersManualBlocking($shuttersDev) )
            {
                $shutters->setLastDrive('rain protection');
                $shutters->setDriveCmd($closedPos);
            }
            elsif ( ( $val == 0 or $val < $triggerMax )
                and $shutters->getStatus == $closedPos
                and IsAfterShuttersManualBlocking($shuttersDev) )
            {
                $shutters->setLastDrive('rain un-protection');
                $shutters->setDriveCmd( $shutters->getLastPos );
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

            $shutters->setWindProtectionStatus('unprotection')
              if ( not defined( $shutters->getWindProtectionStatus )
                or not $shutters->getWindProtectionStatus );

            next
              if (
                (
                    CheckIfShuttersWindowRecOpen($shuttersDev) != 0
                    and $shutters->getShuttersPlace eq 'terrace'
                )
                or $shutters->getWindProtection eq 'off'
              );

            if (    $1 > $shutters->getWindMax
                and $shutters->getWindProtectionStatus eq 'unprotection' )
            {
                $shutters->setLastDrive('wind protection');
                $shutters->setDriveCmd( $shutters->getWindPos );
                $shutters->setWindProtectionStatus('protection');
            }
            elsif ( $1 < $shutters->getWindMin
                and $shutters->getWindProtectionStatus eq 'protection' )
            {
                $shutters->setLastDrive('wind un-protection');
                $shutters->setDriveCmd( $shutters->getLastPos );
                $shutters->setWindProtectionStatus('unprotection');
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
              . ' ist' );

        if (
            int( gettimeofday() / 86400 ) != int(
                computeAlignTime( '24:00', $shutters->getTimeUpEarly ) / 86400
            )
            and int( gettimeofday() / 86400 ) == int(
                computeAlignTime( '24:00', $shutters->getTimeUpLate ) / 86400
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
            $shutters->setLastDrive('maximum brightness threshold exceeded');

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
                  )
                {
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

            if (
                $shutters->getModeDown eq $homemode
                or (    $shutters->getModeDown eq 'absent'
                    and $homemode eq 'gone' )
                or $shutters->getModeDown eq 'always'
              )
            {
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
            ASC_Debug( 'EventProcessingBrightness: '
                  . $shutters->getShuttersDev
                  . ' - Brightness Event kam nicht innerhalb der Verarbeitungszeit für Sunset oder Sunris oder aber für beide wurden die entsprechendne Verarbeitungsschwellen nicht erreicht.'
            );
        }
    }
    ### Wenn es kein Brightness Reading ist muss auch die Shading Funktion nicht aufgerufen werden.
#     else { EventProcessingShadingBrightness( $hash, $shuttersDev, $events ); }
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

        ASC_Debug( 'EventProcessingShadingBrightness: '
              . $shutters->getShuttersDev
              . ' - Nummerischer Brightness-Wert wurde erkannt. Der Wert ist: '
              . $1 );

        my $homemode = $shutters->getRoommatesStatus;
        $homemode = $ascDev->getResidentsStatus if ( $homemode eq 'none' );

        if (
            (
                   $shutters->getShadingMode eq 'always'
                or $shutters->getShadingMode eq $homemode
            )
            and IsDay($shuttersDev)
          )
        {
            ShadingProcessing(
                $hash,
                $shuttersDev,
                $ascDev->getAzimuth,
                $ascDev->getElevation,
                $1,
                $ascDev->getOutTemp,
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

        $azimuth   = $2 if ( $1 eq 'azimuth'   or $1 eq 'SunAz' );
        $elevation = $2 if ( $1 eq 'elevation' or $1 eq 'SunAlt' );

        $azimuth = $ascDev->getAzimuth
          if ( not defined($azimuth) and not $azimuth );
        $elevation = $ascDev->getElevation
          if ( not defined($elevation) and not $elevation );

        ASC_Debug( 'EventProcessingTwilightDevice: '
              . $name
              . ' - Passendes Event wurde erkannt. Verarbeitung über alle Rolllos beginnt'
        );

        foreach my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
            $shutters->setShuttersDev($shuttersDev);

            my $homemode = $shutters->getRoommatesStatus;
            $homemode = $ascDev->getResidentsStatus if ( $homemode eq 'none' );

            if (
                (
                       $shutters->getShadingMode eq 'always'
                    or $shutters->getShadingMode eq $homemode
                )
                and IsDay($shuttersDev)
              )
            {
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
                );

                ASC_Debug( 'EventProcessingTwilightDevice: '
                      . $shutters->getShuttersDev
                      . ' - Alle Bedingungen zur weiteren Beschattungsverarbeitung sind erfüllt. Es wird nun die Beschattungsfunktion ausgeführt'
                );
            }

            $shutters->setShadingStatus('out')
              if ( not IsDay($shuttersDev)
                and $shutters->getShadingStatus ne 'out' );
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
          . ', Ist es nach der manuellen Blockadezeit: '
          . ( IsAfterShuttersManualBlocking($shuttersDev) ? 'JA' : 'NEIN' )
          . ', Ist es nach der Hälfte der Beschattungswartezeit: '
          . (
            ( int( gettimeofday() ) - $shutters->getShadingStatusTimestamp ) <
              ( $shutters->getShadingWaitingPeriod / 2 ) ? 'NEIN' : 'JA'
          )
    );

    $shutters->setShadingStatus('out')
      if ( not IsDay($shuttersDev)
        and $shutters->getShadingStatus ne 'out' );

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
        or not IsAfterShuttersTimeBlocking($shuttersDev)
        or not IsAfterShuttersManualBlocking($shuttersDev) );

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

    if (
        (
            $outTemp < $shutters->getShadingMinOutsideTemperature - 3
            or not IsDay($shuttersDev)
        )
        and $shutters->getShadingStatus ne 'out'
        and $getStatus != $getShadingPos
      )
    {
        $shutters->setShadingStatus('out');
        $shutters->setLastDrive('shading out');

        ShuttersCommandSet( $hash, $shuttersDev, $shutters->getLastPos );

        ASC_Debug( 'ShadingProcessing: '
              . $shutters->getShuttersDev
              . ' - Es ist Nacht oder die Aussentemperatur unterhalb der Shading Temperatur. Die Beschattung wird Zwangsbeendet'
        );

        return Log3( $name, 4,
"AutoShuttersControl ($name) - Shading Processing - Es ist Sonnenuntergang vorbei oder die Aussentemperatur unterhalb der Shading Temperatur "
        );
    }

# minimalen und maximalen Winkel des Fensters bestimmen. wenn die aktuelle Sonnenposition z.B. bei 205° läge und der Wert für angleMin/Max 85° wäre, dann würden zwischen 120° und 290° beschattet.
    my $winPosMin = $winPos - $angleMinus;
    my $winPosMax = $winPos + $anglePlus;

    if (   $azimuth < $winPosMin
        or $azimuth > $winPosMax
        or $elevation < $shutters->getShadingMinElevation
        or $brightness < $shutters->getShadingStateChangeCloudy
        or $outTemp < $shutters->getShadingMinOutsideTemperature )
    {
        $shutters->setShadingStatus('out reserved')
          if ( $shutters->getShadingStatus eq 'in'
            or $shutters->getShadingStatus eq 'in reserved' );

        $shutters->setShadingStatus('out')
          if (
            (
                $shutters->getShadingStatus eq 'out reserved'
                and
                ( int( gettimeofday() ) - $shutters->getShadingStatusTimestamp )
                > $shutters->getShadingWaitingPeriod
            )
            or $azimuth > $winPosMax
          );
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
        and $brightness > $shutters->getShadingStateChangeSunny
        and $outTemp > $shutters->getShadingMinOutsideTemperature )
    {
        $shutters->setShadingStatus('in reserved')
          if ( $shutters->getShadingStatus eq 'out'
            or $shutters->getShadingStatus eq 'out reserved' );

        $shutters->setShadingStatus('in')
          if ( $shutters->getShadingStatus eq 'in reserved'
            and
            ( int( gettimeofday() ) - $shutters->getShadingStatusTimestamp ) >
            ( $shutters->getShadingWaitingPeriod / 2 ) );
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

    if (   $shutters->getShadingStatus eq 'out'
        or $shutters->getShadingStatus eq 'in' )
    {
        ### Erstmal rausgenommen könnte Grund für nicht mehr reinfahren in die Beschattung sein
        $shutters->setShadingStatus( $shutters->getShadingStatus )
          if (
            ( int( gettimeofday() ) - $shutters->getShadingStatusTimestamp ) >
            ( $shutters->getShadingWaitingPeriod / 2 ) );

        if (    $shutters->getShadingStatus eq 'in'
            and $getShadingPos != $getStatus )
        {
            my $queryShuttersShadingPos = (
                  $shutters->getShuttersPosCmdValueNegate
                ? $getStatus > $getShadingPos
                : $getStatus < $getShadingPos
            );

            if ( not $queryShuttersShadingPos ) {
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
            ShuttersCommandSet( $hash, $shuttersDev, $shutters->getLastPos );

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

        if (    not IsDay($shuttersDev)
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
        elsif ( IsDay($shuttersDev)
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

    if ( $events =~ m#.*:\s(\d+)# ) {
        $shutters->setShuttersDev($shuttersDev);
        $ascDev->setPosReading;
        if ( ( int( gettimeofday() ) - $shutters->getLastPosTimestamp ) >
                $shutters->getDriveUpMaxDuration
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
            )
            or (
                CheckIfShuttersWindowRecOpen($shuttersDev) == 2
                and (  $shutters->getLockOut eq 'soft'
                    or $shutters->getLockOut eq 'hard' )
                and $ascDev->getHardLockOut eq 'on'
                and not $queryShuttersPosValue
            )
            or (    CheckIfShuttersWindowRecOpen($shuttersDev) == 2
                and $shutters->getShuttersPlace eq 'terrace'
                and not $queryShuttersPosValue )
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
            ? strftime(
                "%e.%m.%Y - %H:%M", localtime($shuttersSunsetUnixtime)
              )
            : 'AutoShuttersControl off'
        )
    );
    readingsBulkUpdate(
        $shuttersDevHash,
        'ASC_Time_DriveUp',
        (
            $ascDev->getAutoShuttersControlMorning eq 'on'
            ? strftime( "%e.%m.%Y - %H:%M",
                localtime($shuttersSunriseUnixtime) )
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
        'FHEM::AutoShuttersControl::SunSetShuttersAfterTimerFn', \%funcHash )
      if ( $ascDev->getAutoShuttersControlEvening eq 'on' );
    InternalTimer( $shuttersSunriseUnixtime,
        'FHEM::AutoShuttersControl::SunRiseShuttersAfterTimerFn', \%funcHash )
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

        ### Temporär angelegt damit die neue Attributs Parameter Syntax verteilt werden kann
#         CommandAttr(undef, $_ . ' ASC_BrightnessSensor '.AttrVal($_, 'ASC_Brightness_Sensor', 'none').':'.AttrVal($_, 'ASC_Brightness_Reading', 'brightness').' '.AttrVal($_, 'ASC_BrightnessMinVal', 500).':'.AttrVal($_, 'ASC_BrightnessMaxVal', 700)) if ( AttrVal($_, 'ASC_Brightness_Sensor', 'none') ne 'none' );

        $attr{$_}{'ASC_BrightnessSensor'} =
            AttrVal( $_, 'ASC_Brightness_Sensor', 'none' ) . ':'
          . AttrVal( $_, 'ASC_Brightness_Reading', 'brightness' ) . ' '
          . AttrVal( $_, 'ASC_BrightnessMinVal',   500 ) . ':'
          . AttrVal( $_, 'ASC_BrightnessMaxVal',   700 )
          if ( AttrVal( $_, 'ASC_Brightness_Sensor', 'none' ) ne 'none' );

        delFromDevAttrList( $_, 'ASC_Brightness_Sensor' )
          ;    # temporär muss später gelöscht werden ab Version 0.4.11beta9
        delFromDevAttrList( $_, 'ASC_Brightness_Reading' )
          ;    # temporär muss später gelöscht werden ab Version 0.4.11beta9
        delFromDevAttrList( $_, 'ASC_BrightnessMinVal' )
          ;    # temporär muss später gelöscht werden ab Version 0.4.11beta9
        delFromDevAttrList( $_, 'ASC_BrightnessMaxVal' )
          ;    # temporär muss später gelöscht werden ab Version 0.4.11beta9

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
        'FHEM::AutoShuttersControl::SetCmdFn', \%h );
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
        my $queryShuttersPosPrivacyDown = (
              $shutters->getShuttersPosCmdValueNegate
            ? $shutters->getStatus > $shutters->getPrivacyDownPos
            : $shutters->getStatus < $shutters->getPrivacyDownPos
        );

        if ( $funcHash->{privacyMode} == 1
            and not $queryShuttersPosPrivacyDown )
        {
            $shutters->setLastDrive('privacy position');
            ShuttersCommandSet( $hash, $shuttersDev,
                $shutters->getPrivacyDownPos );
        }
        elsif ( $funcHash->{privacyMode} == 0 ) {
            $shutters->setSunset(1);
            $shutters->setLastDrive('night close');
            ShuttersCommandSet( $hash, $shuttersDev, $posValue );
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
            $shutters->setSunrise(1);
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
        $ret .= "<td>" . $shutters->getLastDrive . "</td>";
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
sub IsDay($) {
    my ($shuttersDev) = @_;
    $shutters->setShuttersDev($shuttersDev);

    my $isday = ( ShuttersSunrise( $shuttersDev, 'unix' ) >
          ShuttersSunset( $shuttersDev, 'unix' ) ? 1 : 0 );
    my $respIsDay = $isday;

    ASC_Debug( 'FnIsDay: ' . $shuttersDev . ' Allgemein: ' . $respIsDay );

    if (
        (
               $shutters->getDown eq 'brightness'
            or $shutters->getUp eq 'brightness'
        )
        and (
            (
                int( gettimeofday() / 86400 ) != int(
                    computeAlignTime( '24:00', $shutters->getTimeUpEarly ) /
                      86400
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

        $respIsDay = (
            (
                ( $shutters->getBrightness > $brightnessMinVal and $isday )
                  or $shutters->getSunset
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

        $respIsDay = (
            (
                ( $shutters->getBrightness > $brightnessMaxVal and not $isday )
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
              . ' Sunset: '
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

sub IsAfterShuttersTimeBlocking($) {
    my ($shuttersDev) = @_;
    $shutters->setShuttersDev($shuttersDev);

    if (
        ( int( gettimeofday() ) - $shutters->getLastManPosTimestamp ) <
        $shutters->getBlockingTimeAfterManual
        or ( not IsDay($shuttersDev)
            and $shutters->getSunriseUnixTime - ( int( gettimeofday() ) ) <
            $shutters->getBlockingTimeBeforDayOpen )
        or ( IsDay($shuttersDev)
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

    if (   $shutters->getWinStatus eq 'open'
        or $shutters->getWinStatus eq 'opened' )
    {
        return 2;
    }
    elsif ( $shutters->getWinStatus eq 'tilted'
        and $shutters->getSubTyp eq 'threestate' )
    {
        return 1;
    }
    elsif ( $shutters->getWinStatus eq 'closed' ) { return 0; }
}

sub makeReadingName($) {
    my ($rname) = @_;
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

    return $rname if ( $rname =~ m/^\./ );
    $rname =~ s/($charHashkeys)/$charHash{$1}/gi;
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
        ASC_Debug( 'FnSetCmdFn: '
              . $shuttersDev
              . ' - Abbruch aktuelle Position ist gleich der Zielposition '
              . $shutters->getStatus . '='
              . $posValue );
        return;
    }

    ASC_Debug( 'FnSetCmdFn: '
          . $shuttersDev
          . ' - Rolllo wird gefahren, aktuelle Position: '
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
}

sub ASC_Debug($) {
    return
      unless ( AttrVal( $ascDev->getName, 'ASC_debug', 0 ) );

    my $debugMsg = shift;
    my $debugTimestamp = strftime( "%Y.%m.%e %T", localtime(time) );

    print(
        "\n" . 'ASC_DEBUG!!! ' . $debugTimestamp . ' - ' . $debugMsg . "\n" );
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

    if ( $offSetStart > 0 and not $shutters->getNoOffset ) {
        InternalTimer(
            gettimeofday() + int( rand($offSet) + $shutters->getOffsetStart ),
            'FHEM::AutoShuttersControl::SetCmdFn', \%h );

        FHEM::AutoShuttersControl::ASC_Debug( 'FnSetDriveCmd: '
              . $shutters->getShuttersDev
              . ' - versetztes fahren' );
    }
    elsif ( $offSetStart < 1 or $shutters->getNoOffset ) {
        FHEM::AutoShuttersControl::SetCmdFn( \%h );
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
sub setShadingStatus {
    my ( $self, $value ) = @_;
    ### Werte für value = in, out, in reserved, out reserved

    $self->{ $self->{shuttersDev} }{ShadingStatus}{VAL} = $value
      if ( defined($value) );
    $self->{ $self->{shuttersDev} }{ShadingStatus}{TIME} = int( gettimeofday() )
      if ( defined( $self->{ $self->{shuttersDev} }{ShadingStatus} ) );
    return 0;
}

sub setWindProtectionStatus {    # Werte protection, unprotection
    my ( $self, $value ) = @_;

    $self->{ $self->{shuttersDev} }->{ASC_WindParameters}->{VAL} = $value
      if ( defined($value) );
    return 0;
}

sub getShadingStatus {   # Werte für value = in, out, in reserved, out reserved
    my $self = shift;

    return $self->{ $self->{shuttersDev} }{ShadingStatus}{VAL}
      if (  defined( $self->{ $self->{shuttersDev} }{ShadingStatus} )
        and defined( $self->{ $self->{shuttersDev} }{ShadingStatus}{VAL} ) );
}

sub getIfInShading {
    my $self = shift;

    return (
        (
                 $shutters->getShadingMode eq 'always'
              or $shutters->getShadingMode eq 'home'
        )
          and $shutters->getShadingStatus eq 'in' ? 1 : 0
    );
}

sub getWindProtectionStatus {    # Werte protection, unprotection
    my $self = shift;

    return $self->{ $self->{shuttersDev} }->{ASC_WindParameters}->{VAL}
      if (  defined( $self->{ $self->{shuttersDev} }->{ASC_WindParameters} )
        and
        defined( $self->{ $self->{shuttersDev} }->{ASC_WindParameters}->{VAL} )
      );
}

sub getShadingStatusTimestamp {
    my $self = shift;

    return $self->{ $self->{shuttersDev} }{ShadingStatus}{TIME}
      if (  defined( $self->{ $self->{shuttersDev} } )
        and defined( $self->{ $self->{shuttersDev} }{ShadingStatus} )
        and defined( $self->{ $self->{shuttersDev} }{ShadingStatus}{TIME} ) );
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

sub getASC {
    ## Dient der Erkennung des Rolladen, 0 bedeutet soll nicht erkannt werden beim ersten Scan und soll nicht bediehnt werden wenn Events kommen
    my $self = shift;

    return AttrVal( $self->{shuttersDev}, 'ASC', 0 );
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

    return $device if ( $device eq 'none' );
    $self->{ $self->{shuttersDev} }->{ASC_BrightnessSensor}->{device} = $device;
    $self->{ $self->{shuttersDev} }->{ASC_BrightnessSensor}->{reading} =
      ( $reading ne 'none' ? $reading : 'brightness' );
    $self->{ $self->{shuttersDev} }->{ASC_BrightnessSensor}->{triggermin} =
      ( $min ne 'none' ? $min : '-1' );
    $self->{ $self->{shuttersDev} }->{ASC_BrightnessSensor}->{triggermax} =
      ( $max ne 'none' ? $max : '-1' );

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

    return AttrVal( $self->{shuttersDev}, 'ASC_Shading_Min_Elevation', 25.0 );
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

    return AttrVal( $self->{shuttersDev}, 'ASC_Drive_Offset', -1 );
}

sub getOffsetStart {
    my $self = shift;

    return (
          AttrVal( $self->{shuttersDev}, 'ASC_Drive_OffsetStart', -1 ) > 0
        ? AttrVal( $self->{shuttersDev}, 'ASC_Drive_OffsetStart', -1 )
        : -1
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

    return AttrVal( $name, 'ASC_autoAstroModeEvening', 'none' );
}

sub getAutoAstroModeEveningHorizon {
    my $self = shift;
    my $name = $self->{name};

    return AttrVal( $name, 'ASC_autoAstroModeEveningHorizon', 0 );
}

sub getAutoAstroModeMorning {
    my $self = shift;
    my $name = $self->{name};

    return AttrVal( $name, 'ASC_autoAstroModeMorning', 'none' );
}

sub getAutoAstroModeMorningHorizon {
    my $self = shift;
    my $name = $self->{name};

    return AttrVal( $name, 'ASC_autoAstroModeMorningHorizon', 0 );
}

sub getAutoShuttersControlMorning {
    my $self = shift;
    my $name = $self->{name};

    return AttrVal( $name, 'ASC_autoShuttersControlMorning', 'none' );
}

sub getAutoShuttersControlEvening {
    my $self = shift;
    my $name = $self->{name};

    return AttrVal( $name, 'ASC_autoShuttersControlEvening', 'none' );
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

sub getTempReading {
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
=item summary_DE    Modul zur Automatischen Rolladensteuerung auf Basis bestimmter Ereignisse

=begin html

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
      <a name="ASC_autoAstroModeEvening"></a>
      <li>ASC_autoAstroModeEvening - aktuell REAL,CIVIL,NAUTIC,ASTRONOMIC</li>
      <a name="ASC_autoAstroModeEveningHorizon"></a>
      <li>ASC_autoAstroModeEveningHorizon - H&ouml;he &uuml;ber Horizont wenn beim Attribut ASC_autoAstroModeEvening HORIZON ausgew&auml;hlt / default 0 wenn nicht gesetzt</li>
      <a name="ASC_autoAstroModeMorning"></a>
      <li>ASC_autoAstroModeMorning - aktuell REAL,CIVIL,NAUTIC,ASTRONOMIC</li>
      <a name="ASC_autoAstroModeMorningHorizon"></a>
      <li>ASC_autoAstroModeMorningHorizon - H&ouml;he &uuml;ber Horizont wenn beim Attribut ASC_autoAstroModeMorning HORIZON ausgew&auml;hlt / default 0 wenn nicht gesetzt</li>
      <a name="ASC_autoShuttersControlComfort"></a>
      <li>ASC_autoShuttersControlComfort - on/off - schaltet die Komfortfunktion an. Bedeutet, dass ein Rollladen mit einem threestate Sensor am Fenster beim &ouml;ffnen in eine Offenposition f&auml;hrt, die  beim Rollladen &uuml;ber das Attribut ASC_ComfortOpen_Pos eingestellt wird. / default off wenn nicht gesetzt</li>
      <a name="ASC_autoShuttersControlEvening"></a>
      <li>ASC_autoShuttersControlEvening - on/off - ob Abends die Rolll&auml;den automatisch nach Zeit gesteuert werden sollen</li>
      <a name="ASC_autoShuttersControlMorning"></a>
      <li>ASC_autoShuttersControlMorning - on/off - ob Morgens die Rolll&auml;den automatisch nach Zeit gesteuert werden sollen</li>
      <a name="ASC_autoShuttersControlShading"></a>
      <li>ASC_autoShuttersControlShading - on/off aktiviert oder deaktiviert die globale Beschattungssteuerung</li>
      <a name="ASC_blockAscDrivesAfterManual"></a>
      <li>ASC_blockAscDrivesAfterManual - 0,1 wenn der Wert auf 1 gesetzt ist und ein Rollladen im Reading ASC_ShuttersLastDrive ein manual stehen hat und der Rollladen eine unbekannte (nicht in den Attributen konfigueriebare) position hat wird dieser Rollladen vom ASC nicht mehr gesteuert.</li>
      <a name="ASC_brightnessDriveUpDown"></a>
      <li>ASC_brightnessDriveUpDown - WERT-MORGENS:WERT-ABENDS, Werte bei dem Schaltbedingungen für Sunrise und Sunset gepr&uuml;ft werden sollen. Diese globale Einstellung kann durch die WERT-MORGENS:WERT-ABENDS Einstellung von ASC_BrightnessSensor im Rollladen selbst &uuml;berschrieben werden.</li>
      <a name="ASC_debug"></a>
      <li>ASC_debug - aktiviert die erweiterte Logausgabe für Debugausgaben</li>
      <a name="ASC_expert"></a>
      <li>ASC_expert - ist der Wert 1 werden erweiterte Informationen bez&uuml;glich des NotifyDevs unter set und get angezeigt</li>
      <a name="ASC_freezeTemp"></a>
      <li>ASC_freezeTemp - Temperatur, ab welcher der Frostschutz greifen soll und das Rollo nicht mehr f&auml;hrt. Der letzte Fahrbefehl wird gespeichert.</li>
      <a name="ASC_rainSensor"></a>
      <li>ASC_rainSensor - DEVICENAME[:READINGNAME] MAXTRIGGER[:HYSTERESE] [CLOSEDPOS] / der Inhalt ist eine Kombination aus Devicename, Readingname, Wert ab dem getriggert werden soll, Hysterese Wert ab dem der Status Regenschutz aufgehoben weden soll und der "wegen Regen geschlossen Position".</li>
      <a name="ASC_residentsDev"></a>
      <li>ASC_residentsDev - DEVICENAME[:READINGNAME] / der Inhalt ist eine Kombination aus Devicenamen und Readingnamen des Residents Device der obersten Ebene</li>
      <a name="ASC_shuttersDriveOffset"></a>
      <li>ASC_shuttersDriveOffset - maximal zuf&auml;llige Verz&ouml;gerung in Sekunden bei der Berechnung der Fahrzeiten, 0 bedeutet keine Verz&ouml;gerung</li>
      <a name="ASC_tempSensor"></a>
      <li>ASC_tempSensor - DEVICENAME[:READINGNAME] / der Inhalt des Attributes ist eine Kombination aus Device und Reading f&uuml;r die Aussentemperatur</li>
      <a name="ASC_twilightDevice"></a>
      <li>ASC_twilightDevice - Device welches Informationen zum Sonnenstand liefert, wird unter anderem f&uuml;r die Beschattung verwendet.</li>
      <a name="ASC_windSensor"></a>
      <li>ASC_windSensor - DEVICE[:READING] / Name des FHEM Devices und des Readings f&uuml;r die Windgeschwindigkeit</li>


      <a name="ASC_temperatureSensor"></a>
      <li>ASC_temperatureSensor - WARNUNG!!! OBSOLETE !!! NICHT VERWENDEN!!!</li>
      <a name="ASC_temperatureReading"></a>
      <li>ASC_temperatureReading - WARNUNG!!! OBSOLETE !!! NICHT VERWENDEN!!!</li>
      <a name="ASC_residentsDevice"></a>
      <li>ASC_residentsDevice - WARNUNG!!! OBSOLETE !!! NICHT VERWENDEN!!!</li>
      <a name="ASC_residentsDeviceReading"></a>
      <li>ASC_residentsDeviceReading - WARNUNG!!! OBSOLETE !!! NICHT VERWENDEN!!!</li>
      <a name="ASC_rainSensorDevice"></a>
      <li>ASC_rainSensorDevice - WARNUNG!!! OBSOLETE !!! NICHT VERWENDEN!!!</li>
      <a name="ASC_rainSensorReading"></a>
      <li>ASC_rainSensorReading - WARNUNG!!! OBSOLETE !!! NICHT VERWENDEN!!!</li>
      <a name="ASC_rainSensorShuttersClosedPos"></a>
      <li>ASC_rainSensorShuttersClosedPos - WARNUNG!!! OBSOLETE !!! NICHT VERWENDEN!!!</li>
      <a name="ASC_brightnessMinVal"></a>
      <li>ASC_brightnessMinVal - WARNUNG!!! OBSOLETE !!! NICHT VERWENDEN!!!</li>
      <a name="ASC_brightnessMaxVal"></a>
      <li>ASC_brightnessMaxVal - WARNUNG!!! OBSOLETE !!! NICHT VERWENDEN!!!</li>


    </ul><br>
    In den Rolll&auml;den Devices
    <ul>
      <li>ASC - 0/1/2 0 = "kein Anlegen der Attribute beim ersten Scan bzw. keine Beachtung eines Fahrbefehles",1 = "Inverse oder Rollo - Bsp.: Rollo Oben 0, Rollo Unten 100 und der Befehl zum prozentualen Fahren ist position",2 = "Homematic Style - Bsp.: Rollo Oben 100, Rollo Unten 0 und der Befehl zum prozentualen Fahren ist pct</li>
      <li>ASC_Antifreeze - soft/am/pm/hard/off - Frostschutz, wenn soft f&auml;hrt der Rollladen in die ASC_Antifreeze_Pos und wenn hard/am/pm wird gar nicht oder innerhalb der entsprechenden Tageszeit nicht gefahren / default off wenn nicht gesetzt</li>
      <li>ASC_Antifreeze_Pos - Position die angefahren werden soll wenn der Fahrbefehl komplett schlie&szlig;en lautet, aber der Frostschutz aktiv ist/ default 50 wenn nicht gesetzt</li>
      <li>ASC_AutoAstroModeEvening - aktuell REAL,CIVIL,NAUTIC,ASTRONOMIC / default none wenn nicht gesetzt</li>
      <li>ASC_AutoAstroModeEveningHorizon - H&ouml;he &uuml;ber Horizont wenn beim Attribut ASC_autoAstroModeEvening HORIZON ausgew&auml;hlt / default none wenn nicht gesetzt</li>
      <li>ASC_AutoAstroModeMorning - aktuell REAL,CIVIL,NAUTIC,ASTRONOMIC / default none wenn nicht gesetzt</li>
      <li>ASC_AutoAstroModeMorningHorizon - H&ouml;he &uuml;ber Horizont wenn beim Attribut ASC_autoAstroModeMorning HORIZON ausgew&auml;hlt / default none wenn nicht gesetzt</li>
      <li>ASC_BlockingTime_afterManual - wie viel Sekunden soll die Automatik nach einer manuellen Fahrt aus setzen. / default 1200 wenn nicht gesetzt</li>
      <li>ASC_BlockingTime_beforDayOpen - wie viel Sekunden vor dem morgendlichen &ouml;ffnen soll keine schließen Fahrt mehr statt finden. / default 3600 wenn nicht gesetzt</li>
      <li>ASC_BlockingTime_beforNightClose - wie viel Sekunden vor dem n&auml;chtlichen schlie&zlig;en soll keine &ouml;ffnen Fahrt mehr statt finden. / default 3600 wenn nicht gesetzt</li>
      <li>ASC_BrightnessSensor - DEVICE:READING WERT-MORGENS:WERT-ABENDS / 'Helligkeit:brightness 400:800' Angaben zum Helligkeitssensor und den Brightnesswerten f&uuml;r Sonnenuntergang und Sonnenaufgang. Die Sensor Device Angaben werden auch f&uuml;r die Beschattung verwendet. / default none wenn nicht gesetzt</li>
      <li>ASC_Closed_Pos - in 10 Schritten von 0 bis 100, Default ist abh&auml;ngig vom Attribut ASC</li>
      <li>ASC_ComfortOpen_Pos - in 10 Schritten von 0 bis 100, Default ist abh&auml;ngig vom Attribut ASC</li>
      <li>ASC_Down - astro/time/brightness - bei astro wird Sonnenuntergang berechnet, bei time wird der Wert aus ASC_Time_Down_Early als Fahrzeit verwendet und bei brightness muss ASC_Time_Down_Early und ASC_Time_Down_Late korrekt gesetzt werden. Der Timer l&auml;uft dann nach ASC_Time_Down_Late Zeit, es wird aber in der Zeit zwischen ASC_Time_Down_Early und ASC_Time_Down_Late geschaut, ob die als Attribut im Moduldevice hinterlegte ASC_brightnessMinVal erreicht wurde. Wenn ja, wird der Rollladen runter gefahren / default astro wenn nicht gesetzt</li>
      <li>ASC_DriveUpMaxDuration - die Dauer des hochfahrens vom Rollladen plus 5 Sekunden / default 60 wenn nicht gesetzt</li>
      <li>ASC_Drive_Offset - maximaler Wert f&uuml;r einen zuf&auml;llig ermittelte Verz&ouml;gerungswert in Sekunden bei der Berechnung der Fahrzeiten, 0 bedeutet keine Verz&ouml;gerung, -1 bedeutet, dass das gleichwertige Attribut aus dem ASC Device ausgewertet werden soll. / default -1 wenn nicht gesetzt</li>
      <li>ASC_Drive_OffsetStart - in Sekunden verz&ouml;gerter Wert ab welchen dann erst das Offset startet und dazu addiert wird. Funktioniert nur wenn gleichzeitig ein Drive_Offset gesetzt wird. / default -1 wenn nicht gesetzt</li>
      <li>ASC_LockOut - soft/hard/off - stellt entsprechend den Aussperrschutz ein. Bei global aktivem Aussperrschutz (set ASC-Device lockOut soft) und einem Fensterkontakt open bleibt dann der Rollladen oben. Dies gilt nur bei Steuerbefehle über das ASC Modul. Stellt man global auf hard, wird bei entsprechender M&ouml;glichkeit versucht den Rollladen hardwareseitig zu blockieren. Dann ist auch ein Fahren &uuml;ber die Taster nicht mehr m&ouml;glich. / default off wenn nicht gesetzt</li>
      <li>ASC_LockOut_Cmd - inhibit/blocked/protection - set Befehl f&uuml;r das Rollladen-Device zum Hardware sperren. Dieser Befehl wird gesetzt werden, wenn man "ASC_LockOut" auf hard setzt / default none wenn nicht gesetzt</li>
      <li>ASC_Mode_Down - always/home/absent/off - Wann darf die Automatik steuern. immer, niemals, bei Abwesenheit des Roommate (ist kein Roommate und absent eingestellt, wird gar nicht gesteuert) / default always wenn nicht gesetzt</li>
      <li>ASC_Mode_Up - always/home/absent/off - Wann darf die Automatik steuern. immer, niemals, bei Abwesenheit des Roommate (ist kein Roommate und absent eingestellt, wird gar nicht gesteuert) / default always wenn nicht gesetzt</li>
      <li>ASC_Open_Pos -  in 10 Schritten von 0 bis 100, Default ist abh&auml;ngig vom Attribut ASC</li>
      <li>ASC_Partymode -  on/off - schaltet den Partymodus an oder aus. Wird  am ASC Device set ASC-DEVICE partyMode on geschalten, werden alle Fahrbefehle an den Rolll&auml;den, welche das Attribut auf on haben, zwischengespeichert und sp&auml;ter erst ausgef&uuml;hrt / default off wenn nicht gesetzt</li>
      <li>ASC_Pos_Reading - Name des Readings, welches die Position des Rollladen in Prozent an gibt; wird bei unbekannten Device Typen auch als set Befehl zum fahren verwendet</li>
      <li>ASC_PrivacyDownTime_beforNightClose - wie viele Sekunden vor dem abendlichen schlie&zlig;en soll der Rollladen in die Sichtschutzposition fahren, -1 bedeutet das diese Funktion unbeachtet bleiben soll / default -1 wenn nicht gesetzt</li>
      <li>ASC_PrivacyDown_Pos - Position den Rollladens f&uuml;r den Sichtschutz / default 50 wenn nicht gesetzt</li>
      <li>ASC_Roommate_Device - mit Komma getrennte Namen des/der Roommate Device/s, welche den/die Bewohner des Raumes vom Rollladen wiedergibt. Es macht nur Sinn in Schlaf- oder Kinderzimmern / default none wenn nicht gesetzt</li>
      <li>ASC_Roommate_Reading - das Reading zum Roommate Device, welches den Status wieder gibt / default state wenn nicht gesetzt</li>
      <li>ASC_Self_Defense_Exclude - on/off - bei on Wert wird dieser Rollladen bei aktiven Self Defense und offenen Fenster nicht runter gefahren, wenn Residents absent ist. / default off wenn nicht gesetzt</li>
      <li>ASC_Shading_Angle_Left - Vorlaufwinkel im Bezug zum Fenster, ab wann abgeschattet wird. Beispiel: Fenster 180° - 85° ==> ab Sonnenpos. 95° wird abgeschattet / default 75 wenn nicht gesetzt</li>
      <li>ASC_Shading_Angle_Right - Nachlaufwinkel im Bezug zum Fenster, bis wann abgeschattet wird. Beispiel: Fenster 180° + 85° ==> bis Sonnenpos. 265° wird abgeschattet / default 75 wenn nicht gesetzt</li>
      <li>ASC_Shading_Direction -  Position in Grad, auf der das Fenster liegt - genau Osten w&auml;re 90, S&uuml;den 180 und Westen 270 / default 180 wenn nicht gesetzt</li>
      <li>ASC_Shading_Min_Elevation - ab welcher Höhe des Sonnenstandes soll beschattet werden, immer in Abh&auml;ngikkeit der anderen einbezogenden Sensorwerte / default 25.0 wenn nicht gesetzt</li>
      <li>ASC_Shading_Min_OutsideTemperature - ab welcher Temperatur soll Beschattet werden, immer in Abh&auml;ngikkeit der anderen einbezogenden Sensorwerte / default 18 wenn nicht gesetzt</li>
      <li>ASC_Shading_Mode - absent,always,off,home / wann soll die Beschattung nur statt finden. / default off wenn nicht gesetzt</li>
      <li>ASC_Shading_Pos - Position des Rollladens für die Beschattung</li>
      <li>ASC_Shading_StateChange_Cloudy - Brightness Wert ab welchen die Beschattung aufgehoben werden soll, immer in Abh&auml;ngikkeit der anderen einbezogenden Sensorwerte / default 20000 wenn nicht gesetzt</li>
      <li>ASC_Shading_StateChange_Sunny - Brightness Wert ab welchen Beschattung statt finden soll, immer in Abh&auml;ngikkeit der anderen einbezogenden Sensorwerte / default 35000 wenn nicht gesetzt</li>
      <li>ASC_Shading_WaitingPeriod - wie viele Sekunden soll gewartet werden bevor eine weitere Auswertung der Sensordaten für die Beschattung statt finden soll / default 1200 wenn nicht gesetzt</li>
      <li>ASC_ShuttersPlace - window/terrace - Wenn dieses Attribut auf terrace gesetzt ist, das Residence Device in den Status "gone" geht und SelfDefence aktiv ist (ohne das das Reading selfDefense gesetzt sein muss), wird das Rollo geschlossen / default window wenn nicht gesetzt</li>
      <li>ASC_Time_Down_Early - Sunset fr&uuml;hste Zeit zum Runterfahren / default 16:00 wenn nicht gesetzt</li>
      <li>ASC_Time_Down_Late - Sunset sp&auml;teste Zeit zum Runterfahren / default 22:00 wenn nicht gesetzt</li>
      <li>ASC_Time_Up_Early - Sunrise fr&uuml;hste Zeit zum Hochfahren / default 05:00 wenn nicht gesetzt</li>
      <li>ASC_Time_Up_Late - Sunrise sp&auml;teste Zeit zum Hochfahren / default 08:30 wenn nicht gesetzt</li>
      <li>ASC_Time_Up_WE_Holiday - Sunrise fr&uuml;hste Zeit zum Hochfahren am Wochenende und/oder Urlaub (holiday2we wird beachtet). / default 08:00 wenn nicht gesetzt</li>
      <li>ASC_Up - astro/time/brightness - bei astro wird Sonnenaufgang berechnet, bei time wird der Wert aus ASC_Time_Up_Early als Fahrzeit verwendet und bei brightness muss ASC_Time_Up_Early und ASC_Time_Up_Late korrekt gesetzt werden. Der Timer l&auml;uft dann nach ASC_Time_Up_Late Zeit, es wird aber in der Zeit zwischen ASC_Time_Up_Early und ASC_Time_Up_Late geschaut, ob die als Attribut im Moduldevice hinterlegte ASC_brightnessMinVal erreicht wurde. Wenn ja, wird der Rollladen hoch gefahren / default astro wenn nicht gesetzt</li>
      <li>ASC_Ventilate_Pos -  in 10 Schritten von 0 bis 100, Default ist abh&auml;ngig vom Attribut ASC</li>
      <li>ASC_Ventilate_Window_Open - auf l&uuml;ften, wenn das Fenster gekippt/ge&ouml;ffnet wird und aktuelle Position unterhalb der L&uuml;ften-Position ist / default on wenn nicht gesetzt</li>
      <li>ASC_WiggleValue - Wert um welchen sich die Position des Rollladens &auml;ndern soll / default 5 wenn nicht gesetzt</li>
      <li>ASC_WindParameters - TRIGGERMAX[:HYSTERESE] [DRIVEPOSITION] / Angabe von Max Wert ab dem für Wind getriggert werden soll, Hytsrese Wert ab dem der Windschutz aufgehoben werden soll TRIGGERMAX - HYSTERESE / Ist es bei einigen Rolll&auml;den nicht gew&uuml;nscht das gefahren werden soll, so ist der TRIGGERMAX Wert mit -1 an zu geben. / default '50:20 ClosedPosition' wenn nicht gesetzt</li>
      <li>ASC_WindowRec - Name des Fensterkontaktes, an dessen Fenster der Rollladen angebracht ist / default none wenn nicht gesetzt</li>
      <li>ASC_WindowRec_subType - Typ des verwendeten Fensterkontaktes: twostate (optisch oder magnetisch) oder threestate (Drehgriffkontakt) / default twostate wenn nicht gesetzt</li>
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
      <a name="ASC_autoAstroModeEvening"></a>
      <li>ASC_autoAstroModeEvening - aktuell REAL,CIVIL,NAUTIC,ASTRONOMIC</li>
      <a name="ASC_autoAstroModeEveningHorizon"></a>
      <li>ASC_autoAstroModeEveningHorizon - H&ouml;he &uuml;ber Horizont wenn beim Attribut ASC_autoAstroModeEvening HORIZON ausgew&auml;hlt / default 0 wenn nicht gesetzt</li>
      <a name="ASC_autoAstroModeMorning"></a>
      <li>ASC_autoAstroModeMorning - aktuell REAL,CIVIL,NAUTIC,ASTRONOMIC</li>
      <a name="ASC_autoAstroModeMorningHorizon"></a>
      <li>ASC_autoAstroModeMorningHorizon - H&ouml;he &uuml;ber Horizont wenn beim Attribut ASC_autoAstroModeMorning HORIZON ausgew&auml;hlt / default 0 wenn nicht gesetzt</li>
      <a name="ASC_autoShuttersControlComfort"></a>
      <li>ASC_autoShuttersControlComfort - on/off - schaltet die Komfortfunktion an. Bedeutet, dass ein Rollladen mit einem threestate Sensor am Fenster beim &ouml;ffnen in eine Offenposition f&auml;hrt, die  beim Rollladen &uuml;ber das Attribut ASC_ComfortOpen_Pos eingestellt wird. / default off wenn nicht gesetzt</li>
      <a name="ASC_autoShuttersControlEvening"></a>
      <li>ASC_autoShuttersControlEvening - on/off - ob Abends die Rolll&auml;den automatisch nach Zeit gesteuert werden sollen</li>
      <a name="ASC_autoShuttersControlMorning"></a>
      <li>ASC_autoShuttersControlMorning - on/off - ob Morgens die Rolll&auml;den automatisch nach Zeit gesteuert werden sollen</li>
      <a name="ASC_autoShuttersControlShading"></a>
      <li>ASC_autoShuttersControlShading - on/off aktiviert oder deaktiviert die globale Beschattungssteuerung</li>
      <a name="ASC_blockAscDrivesAfterManual"></a>
      <li>ASC_blockAscDrivesAfterManual - 0,1 wenn der Wert auf 1 gesetzt ist und ein Rollladen im Reading ASC_ShuttersLastDrive ein manual stehen hat und der Rollladen eine unbekannte (nicht in den Attributen konfigueriebare) position hat wird dieser Rollladen vom ASC nicht mehr gesteuert.</li>
      <a name="ASC_brightnessDriveUpDown"></a>
      <li>ASC_brightnessDriveUpDown - WERT-MORGENS:WERT-ABENDS, Werte bei dem Schaltbedingungen für Sunrise und Sunset gepr&uuml;ft werden sollen. Diese globale Einstellung kann durch die WERT-MORGENS:WERT-ABENDS Einstellung von ASC_BrightnessSensor im Rollladen selbst &uuml;berschrieben werden.</li>
      <a name="ASC_debug"></a>
      <li>ASC_debug - aktiviert die erweiterte Logausgabe für Debugausgaben</li>
      <a name="ASC_expert"></a>
      <li>ASC_expert - ist der Wert 1 werden erweiterte Informationen bez&uuml;glich des NotifyDevs unter set und get angezeigt</li>
      <a name="ASC_freezeTemp"></a>
      <li>ASC_freezeTemp - Temperatur, ab welcher der Frostschutz greifen soll und das Rollo nicht mehr f&auml;hrt. Der letzte Fahrbefehl wird gespeichert.</li>
      <a name="ASC_rainSensor"></a>
      <li>ASC_rainSensor - DEVICENAME[:READINGNAME] MAXTRIGGER[:HYSTERESE] [CLOSEDPOS] / der Inhalt ist eine Kombination aus Devicename, Readingname, Wert ab dem getriggert werden soll, Hysterese Wert ab dem der Status Regenschutz aufgehoben weden soll und der "wegen Regen geschlossen Position".</li>
      <a name="ASC_residentsDev"></a>
      <li>ASC_residentsDev - DEVICENAME[:READINGNAME] / der Inhalt ist eine Kombination aus Devicenamen und Readingnamen des Residents Device der obersten Ebene</li>
      <a name="ASC_shuttersDriveOffset"></a>
      <li>ASC_shuttersDriveOffset - maximal zuf&auml;llige Verz&ouml;gerung in Sekunden bei der Berechnung der Fahrzeiten, 0 bedeutet keine Verz&ouml;gerung</li>
      <a name="ASC_tempSensor"></a>
      <li>ASC_tempSensor - DEVICENAME[:READINGNAME] / der Inhalt des Attributes ist eine Kombination aus Device und Reading f&uuml;r die Aussentemperatur</li>
      <a name="ASC_twilightDevice"></a>
      <li>ASC_twilightDevice - Device welches Informationen zum Sonnenstand liefert, wird unter anderem f&uuml;r die Beschattung verwendet.</li>
      <a name="ASC_windSensor"></a>
      <li>ASC_windSensor - DEVICE[:READING] / Name des FHEM Devices und des Readings f&uuml;r die Windgeschwindigkeit</li>


      <a name="ASC_temperatureSensor"></a>
      <li>ASC_temperatureSensor - WARNUNG!!! OBSOLETE !!! NICHT VERWENDEN!!!</li>
      <a name="ASC_temperatureReading"></a>
      <li>ASC_temperatureReading - WARNUNG!!! OBSOLETE !!! NICHT VERWENDEN!!!</li>
      <a name="ASC_residentsDevice"></a>
      <li>ASC_residentsDevice - WARNUNG!!! OBSOLETE !!! NICHT VERWENDEN!!!</li>
      <a name="ASC_residentsDeviceReading"></a>
      <li>ASC_residentsDeviceReading - WARNUNG!!! OBSOLETE !!! NICHT VERWENDEN!!!</li>
      <a name="ASC_rainSensorDevice"></a>
      <li>ASC_rainSensorDevice - WARNUNG!!! OBSOLETE !!! NICHT VERWENDEN!!!</li>
      <a name="ASC_rainSensorReading"></a>
      <li>ASC_rainSensorReading - WARNUNG!!! OBSOLETE !!! NICHT VERWENDEN!!!</li>
      <a name="ASC_rainSensorShuttersClosedPos"></a>
      <li>ASC_rainSensorShuttersClosedPos - WARNUNG!!! OBSOLETE !!! NICHT VERWENDEN!!!</li>
      <a name="ASC_brightnessMinVal"></a>
      <li>ASC_brightnessMinVal - WARNUNG!!! OBSOLETE !!! NICHT VERWENDEN!!!</li>
      <a name="ASC_brightnessMaxVal"></a>
      <li>ASC_brightnessMaxVal - WARNUNG!!! OBSOLETE !!! NICHT VERWENDEN!!!</li>


    </ul><br>
    In den Rolll&auml;den Devices
    <ul>
      <li>ASC - 0/1/2 0 = "kein Anlegen der Attribute beim ersten Scan bzw. keine Beachtung eines Fahrbefehles",1 = "Inverse oder Rollo - Bsp.: Rollo Oben 0, Rollo Unten 100 und der Befehl zum prozentualen Fahren ist position",2 = "Homematic Style - Bsp.: Rollo Oben 100, Rollo Unten 0 und der Befehl zum prozentualen Fahren ist pct</li>
      <li>ASC_Antifreeze - soft/am/pm/hard/off - Frostschutz, wenn soft f&auml;hrt der Rollladen in die ASC_Antifreeze_Pos und wenn hard/am/pm wird gar nicht oder innerhalb der entsprechenden Tageszeit nicht gefahren / default off wenn nicht gesetzt</li>
      <li>ASC_Antifreeze_Pos - Position die angefahren werden soll wenn der Fahrbefehl komplett schlie&szlig;en lautet, aber der Frostschutz aktiv ist/ default 50 wenn nicht gesetzt</li>
      <li>ASC_AutoAstroModeEvening - aktuell REAL,CIVIL,NAUTIC,ASTRONOMIC / default none wenn nicht gesetzt</li>
      <li>ASC_AutoAstroModeEveningHorizon - H&ouml;he &uuml;ber Horizont wenn beim Attribut ASC_autoAstroModeEvening HORIZON ausgew&auml;hlt / default none wenn nicht gesetzt</li>
      <li>ASC_AutoAstroModeMorning - aktuell REAL,CIVIL,NAUTIC,ASTRONOMIC / default none wenn nicht gesetzt</li>
      <li>ASC_AutoAstroModeMorningHorizon - H&ouml;he &uuml;ber Horizont wenn beim Attribut ASC_autoAstroModeMorning HORIZON ausgew&auml;hlt / default none wenn nicht gesetzt</li>
      <li>ASC_BlockingTime_afterManual - wie viel Sekunden soll die Automatik nach einer manuellen Fahrt aus setzen. / default 1200 wenn nicht gesetzt</li>
      <li>ASC_BlockingTime_beforDayOpen - wie viel Sekunden vor dem morgendlichen &ouml;ffnen soll keine schließen Fahrt mehr statt finden. / default 3600 wenn nicht gesetzt</li>
      <li>ASC_BlockingTime_beforNightClose - wie viel Sekunden vor dem n&auml;chtlichen schlie&zlig;en soll keine &ouml;ffnen Fahrt mehr statt finden. / default 3600 wenn nicht gesetzt</li>
      <li>ASC_BrightnessSensor - DEVICE:READING WERT-MORGENS:WERT-ABENDS / 'Helligkeit:brightness 400:800' Angaben zum Helligkeitssensor und den Brightnesswerten f&uuml;r Sonnenuntergang und Sonnenaufgang. Die Sensor Device Angaben werden auch f&uuml;r die Beschattung verwendet. / default none wenn nicht gesetzt</li>
      <li>ASC_Closed_Pos - in 10 Schritten von 0 bis 100, Default ist abh&auml;ngig vom Attribut ASC</li>
      <li>ASC_ComfortOpen_Pos - in 10 Schritten von 0 bis 100, Default ist abh&auml;ngig vom Attribut ASC</li>
      <li>ASC_Down - astro/time/brightness - bei astro wird Sonnenuntergang berechnet, bei time wird der Wert aus ASC_Time_Down_Early als Fahrzeit verwendet und bei brightness muss ASC_Time_Down_Early und ASC_Time_Down_Late korrekt gesetzt werden. Der Timer l&auml;uft dann nach ASC_Time_Down_Late Zeit, es wird aber in der Zeit zwischen ASC_Time_Down_Early und ASC_Time_Down_Late geschaut, ob die als Attribut im Moduldevice hinterlegte ASC_brightnessMinVal erreicht wurde. Wenn ja, wird der Rollladen runter gefahren / default astro wenn nicht gesetzt</li>
      <li>ASC_DriveUpMaxDuration - die Dauer des hochfahrens vom Rollladen plus 5 Sekunden / default 60 wenn nicht gesetzt</li>
      <li>ASC_Drive_Offset - maximaler Wert f&uuml;r einen zuf&auml;llig ermittelte Verz&ouml;gerungswert in Sekunden bei der Berechnung der Fahrzeiten, 0 bedeutet keine Verz&ouml;gerung, -1 bedeutet, dass das gleichwertige Attribut aus dem ASC Device ausgewertet werden soll. / default -1 wenn nicht gesetzt</li>
      <li>ASC_Drive_OffsetStart - in Sekunden verz&ouml;gerter Wert ab welchen dann erst das Offset startet und dazu addiert wird. Funktioniert nur wenn gleichzeitig ein Drive_Offset gesetzt wird. / default -1 wenn nicht gesetzt</li>
      <li>ASC_LockOut - soft/hard/off - stellt entsprechend den Aussperrschutz ein. Bei global aktivem Aussperrschutz (set ASC-Device lockOut soft) und einem Fensterkontakt open bleibt dann der Rollladen oben. Dies gilt nur bei Steuerbefehle über das ASC Modul. Stellt man global auf hard, wird bei entsprechender M&ouml;glichkeit versucht den Rollladen hardwareseitig zu blockieren. Dann ist auch ein Fahren &uuml;ber die Taster nicht mehr m&ouml;glich. / default off wenn nicht gesetzt</li>
      <li>ASC_LockOut_Cmd - inhibit/blocked/protection - set Befehl f&uuml;r das Rollladen-Device zum Hardware sperren. Dieser Befehl wird gesetzt werden, wenn man "ASC_LockOut" auf hard setzt / default none wenn nicht gesetzt</li>
      <li>ASC_Mode_Down - always/home/absent/off - Wann darf die Automatik steuern. immer, niemals, bei Abwesenheit des Roommate (ist kein Roommate und absent eingestellt, wird gar nicht gesteuert) / default always wenn nicht gesetzt</li>
      <li>ASC_Mode_Up - always/home/absent/off - Wann darf die Automatik steuern. immer, niemals, bei Abwesenheit des Roommate (ist kein Roommate und absent eingestellt, wird gar nicht gesteuert) / default always wenn nicht gesetzt</li>
      <li>ASC_Open_Pos -  in 10 Schritten von 0 bis 100, Default ist abh&auml;ngig vom Attribut ASC</li>
      <li>ASC_Partymode -  on/off - schaltet den Partymodus an oder aus. Wird  am ASC Device set ASC-DEVICE partyMode on geschalten, werden alle Fahrbefehle an den Rolll&auml;den, welche das Attribut auf on haben, zwischengespeichert und sp&auml;ter erst ausgef&uuml;hrt / default off wenn nicht gesetzt</li>
      <li>ASC_Pos_Reading - Name des Readings, welches die Position des Rollladen in Prozent an gibt; wird bei unbekannten Device Typen auch als set Befehl zum fahren verwendet</li>
      <li>ASC_PrivacyDownTime_beforNightClose - wie viele Sekunden vor dem abendlichen schlie&zlig;en soll der Rollladen in die Sichtschutzposition fahren, -1 bedeutet das diese Funktion unbeachtet bleiben soll / default -1 wenn nicht gesetzt</li>
      <li>ASC_PrivacyDown_Pos - Position den Rollladens f&uuml;r den Sichtschutz / default 50 wenn nicht gesetzt</li>
      <li>ASC_Roommate_Device - mit Komma getrennte Namen des/der Roommate Device/s, welche den/die Bewohner des Raumes vom Rollladen wiedergibt. Es macht nur Sinn in Schlaf- oder Kinderzimmern / default none wenn nicht gesetzt</li>
      <li>ASC_Roommate_Reading - das Reading zum Roommate Device, welches den Status wieder gibt / default state wenn nicht gesetzt</li>
      <li>ASC_Self_Defense_Exclude - on/off - bei on Wert wird dieser Rollladen bei aktiven Self Defense und offenen Fenster nicht runter gefahren, wenn Residents absent ist. / default off wenn nicht gesetzt</li>
      <li>ASC_Shading_Angle_Left - Vorlaufwinkel im Bezug zum Fenster, ab wann abgeschattet wird. Beispiel: Fenster 180° - 85° ==> ab Sonnenpos. 95° wird abgeschattet / default 75 wenn nicht gesetzt</li>
      <li>ASC_Shading_Angle_Right - Nachlaufwinkel im Bezug zum Fenster, bis wann abgeschattet wird. Beispiel: Fenster 180° + 85° ==> bis Sonnenpos. 265° wird abgeschattet / default 75 wenn nicht gesetzt</li>
      <li>ASC_Shading_Direction -  Position in Grad, auf der das Fenster liegt - genau Osten w&auml;re 90, S&uuml;den 180 und Westen 270 / default 180 wenn nicht gesetzt</li>
      <li>ASC_Shading_Min_Elevation - ab welcher Höhe des Sonnenstandes soll beschattet werden, immer in Abh&auml;ngikkeit der anderen einbezogenden Sensorwerte / default 25.0 wenn nicht gesetzt</li>
      <li>ASC_Shading_Min_OutsideTemperature - ab welcher Temperatur soll Beschattet werden, immer in Abh&auml;ngikkeit der anderen einbezogenden Sensorwerte / default 18 wenn nicht gesetzt</li>
      <li>ASC_Shading_Mode - absent,always,off,home / wann soll die Beschattung nur statt finden. / default off wenn nicht gesetzt</li>
      <li>ASC_Shading_Pos - Position des Rollladens für die Beschattung</li>
      <li>ASC_Shading_StateChange_Cloudy - Brightness Wert ab welchen die Beschattung aufgehoben werden soll, immer in Abh&auml;ngikkeit der anderen einbezogenden Sensorwerte / default 20000 wenn nicht gesetzt</li>
      <li>ASC_Shading_StateChange_Sunny - Brightness Wert ab welchen Beschattung statt finden soll, immer in Abh&auml;ngikkeit der anderen einbezogenden Sensorwerte / default 35000 wenn nicht gesetzt</li>
      <li>ASC_Shading_WaitingPeriod - wie viele Sekunden soll gewartet werden bevor eine weitere Auswertung der Sensordaten für die Beschattung statt finden soll / default 1200 wenn nicht gesetzt</li>
      <li>ASC_ShuttersPlace - window/terrace - Wenn dieses Attribut auf terrace gesetzt ist, das Residence Device in den Status "gone" geht und SelfDefence aktiv ist (ohne das das Reading selfDefense gesetzt sein muss), wird das Rollo geschlossen / default window wenn nicht gesetzt</li>
      <li>ASC_Time_Down_Early - Sunset fr&uuml;hste Zeit zum Runterfahren / default 16:00 wenn nicht gesetzt</li>
      <li>ASC_Time_Down_Late - Sunset sp&auml;teste Zeit zum Runterfahren / default 22:00 wenn nicht gesetzt</li>
      <li>ASC_Time_Up_Early - Sunrise fr&uuml;hste Zeit zum Hochfahren / default 05:00 wenn nicht gesetzt</li>
      <li>ASC_Time_Up_Late - Sunrise sp&auml;teste Zeit zum Hochfahren / default 08:30 wenn nicht gesetzt</li>
      <li>ASC_Time_Up_WE_Holiday - Sunrise fr&uuml;hste Zeit zum Hochfahren am Wochenende und/oder Urlaub (holiday2we wird beachtet). / default 08:00 wenn nicht gesetzt
      ACHTUNG!!! in Verbindung mit Brightness f&uuml;r ASC_Up muss die Uhrzeit kleiner sein wie die Uhrzeit aus ASC_Time_Up_Late</li>
      <li>ASC_Up - astro/time/brightness - bei astro wird Sonnenaufgang berechnet, bei time wird der Wert aus ASC_Time_Up_Early als Fahrzeit verwendet und bei brightness muss ASC_Time_Up_Early und ASC_Time_Up_Late korrekt gesetzt werden. Der Timer l&auml;uft dann nach ASC_Time_Up_Late Zeit, es wird aber in der Zeit zwischen ASC_Time_Up_Early und ASC_Time_Up_Late geschaut, ob die als Attribut im Moduldevice hinterlegte ASC_brightnessMinVal erreicht wurde. Wenn ja, wird der Rollladen hoch gefahren / default astro wenn nicht gesetzt</li>
      <li>ASC_Ventilate_Pos -  in 10 Schritten von 0 bis 100, Default ist abh&auml;ngig vom Attribut ASC</li>
      <li>ASC_Ventilate_Window_Open - auf l&uuml;ften, wenn das Fenster gekippt/ge&ouml;ffnet wird und aktuelle Position unterhalb der L&uuml;ften-Position ist / default on wenn nicht gesetzt</li>
      <li>ASC_WiggleValue - Wert um welchen sich die Position des Rollladens &auml;ndern soll / default 5 wenn nicht gesetzt</li>
      <li>ASC_WindParameters - TRIGGERMAX[:HYSTERESE] [DRIVEPOSITION] / Angabe von Max Wert ab dem für Wind getriggert werden soll, Hytsrese Wert ab dem der Windschutz aufgehoben werden soll TRIGGERMAX - HYSTERESE / Ist es bei einigen Rolll&auml;den nicht gew&uuml;nscht das gefahren werden soll, so ist das Attribut ASC_WindProtection auf off zu setzen. / default '50:20 ClosedPosition' wenn nicht gesetzt</li>
      <li>ASC_WindProtection - on/off aktiviert den Windschutz f&uuml;r diesen Rollladen. / default on wenn nicht gesetzt.</li>
      <li>ASC_WindowRec - Name des Fensterkontaktes, an dessen Fenster der Rollladen angebracht ist / default none wenn nicht gesetzt</li>
      <li>ASC_WindowRec_subType - Typ des verwendeten Fensterkontaktes: twostate (optisch oder magnetisch) oder threestate (Drehgriffkontakt) / default twostate wenn nicht gesetzt</li>
    </ul>
  </ul>
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
        "JSON": 0
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
