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

### Notizen
# !!!!! - Innerhalb einer Shutterschleife kein CommandAttr verwenden. Bring Fehler!!! Kommen Raumnamen in die Shutterliste !!!!!!
#

package main;

use strict;
use warnings;
use utf8;

sub ascAPIget {
    my ( $getCommand, $shutterDev, $value ) = @_;

    return ShuttersControl_ascAPIget( $getCommand, $shutterDev, $value );
}

sub ascAPIset {
    my ( $setCommand, $shutterDev, $value ) = @_;

    return ShuttersControl_ascAPIset( $setCommand, $shutterDev, $value );
}

## unserer packagename
package FHEM::Automation::ShuttersControl;

use strict;
use warnings;
use POSIX qw(strftime);
use utf8;

use Encode;
use FHEM::Meta;
use GPUtils qw(GP_Import GP_Export);
use Data::Dumper;    #only for Debugging
use Date::Parse;

use FHEM::Automation::ShuttersControl::Shutters;
use FHEM::Automation::ShuttersControl::Dev;

require Exporter;
our @ISA    = qw(Exporter);
our @Export = qw($shutters $ascDev %userAttrList);

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
          if ( !defined( $ENV{PERL_JSON_BACKEND} ) );

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

    #-- Export to main context with different name
    GP_Export(
        qw(
          ascAPIget
          ascAPIset
          DevStateIcon
          )
    );
}

## Die Attributsliste welche an die Rolläden verteilt wird. Zusammen mit Default Werten
our %userAttrList = (
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
    'ASC_Sleep_Pos:0,10,20,30,40,50,60,70,80,90,100'  => [ '', -1,  -1 ],
    'ASC_Pos_Reading'                            => [ '', 'position', 'pct' ],
    'ASC_Time_Up_Early'                          => '-',
    'ASC_Time_Up_Late'                           => '-',
    'ASC_Time_Up_WE_Holiday'                     => '-',
    'ASC_Time_Down_Early'                        => '-',
    'ASC_Time_Down_Late'                         => '-',
    'ASC_PrivacyUpValue_beforeDayOpen'           => '-',
    'ASC_PrivacyDownValue_beforeNightClose'      => '-',
    'ASC_PrivacyUp_Pos'                          => [ '', 50, 50 ],
    'ASC_PrivacyDown_Pos'                        => [ '', 50, 50 ],
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
    'ASC_Adv:on,off'                        => '-',
    'ASC_SlatPosCmd_SlatDevice'             => '-',
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
our $shutters = FHEM::Automation::ShuttersControl::Shutters->new();
our $ascDev   = FHEM::Automation::ShuttersControl::Dev->new();

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

    return;
}

sub ascAPIset {
    my ( $setCommand, $shutterDev, $value ) = @_;

    my $setter = 'set' . $setCommand;

    if (   defined($shutterDev)
        && $shutterDev
        && defined($value) )
    {
        $shutters->setShuttersDev($shutterDev);
        $shutters->$setter($value);
    }

    return;
}

sub Define {
    my $hash = shift // return;
    my $aArg = shift // return;

    return $@ if ( !FHEM::Meta::SetInternals($hash) );
    use version 0.60; our $VERSION = FHEM::Meta::Get( $hash, 'version' );

    return 'only one AutoShuttersControl instance allowed'
      if ( devspec2array('TYPE=AutoShuttersControl') > 1 )
      ; # es wird geprüft ob bereits eine Instanz unseres Modules existiert,wenn ja wird abgebrochen
    return 'too few parameters: define <name> ShuttersControl'
      if ( scalar( @{$aArg} ) != 2 );

    my $name = shift @$aArg;
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
        $name . ' devStateIcon { ShuttersControl_DevStateIcon($name) }' )
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
    my $hash = shift // return;
    my $dev  = shift // return;

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
            @{$events} && $devname eq 'global' && $init_done
        )
        || (
            grep m{^INITIALIZED$}xms,
            @{$events} or grep m{^REREADCFG$}xms,
            @{$events} or grep m{^MODIFIED.$name$}xms,
            @{$events}
        )
        && $devname eq 'global'
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
            $name . ' devStateIcon { ShuttersControl_DevStateIcon($name) }' )
          if (
            AttrVal(
                $name, 'devStateIcon',
                '{ ShuttersControl_DevStateIcon($name) }'
            ) ne '{ ShuttersControl_DevStateIcon($name) }'
          );
        CommandDeleteAttr( undef, $name . ' event-on-change-reading' )
          if ( AttrVal( $name, 'event-on-change-reading', 'none' ) ne 'none' );
        CommandDeleteAttr( undef, $name . ' event-on-update-reading' )
          if ( AttrVal( $name, 'event-on-update-reading', 'none' ) ne 'none' );

# Ist der Event ein globaler und passt zum Rest der Abfrage oben wird nach neuen Rolläden Devices gescannt und eine Liste im Rolladenmodul sortiert nach Raum generiert
        ShuttersDeviceScan($hash)
          if ( ReadingsVal( $name, 'userAttrList', 'none' ) ne 'none' );
    }
    return
      if ( ref( $hash->{helper}{shuttersList} ) ne 'ARRAY'
        || scalar( @{ $hash->{helper}{shuttersList} } ) == 0 );

    my $posReading = $shutters->getPosCmd;

    if ( $devname eq $name ) {
        if ( grep m{^userAttrList:.rolled.out$}xms, @{$events} ) {
            if ( scalar( @{ $hash->{helper}{shuttersList} } ) > 0 ) {
                WriteReadingsShuttersList($hash);
                UserAttributs_Readings_ForShutters( $hash, 'add' );
                InternalTimer(
                    gettimeofday() + 3,
'FHEM::Automation::ShuttersControl::RenewSunRiseSetShuttersTimer',
                    $hash
                );
                InternalTimer(
                    gettimeofday() + 5,
                    'FHEM::Automation::ShuttersControl::AutoSearchTwilightDev',
                    $hash
                );
                InternalTimer(
                    gettimeofday() + 5,
                    sub() { CommandSet( undef, $name . ' controlShading on' ) },
                    $hash
                  )
                  if ( ReadingsVal( $name, 'controlShading', 'off' ) ne 'off' );
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
m{^(ATTR|DELETEATTR)\s(.*ASC_Time_Up_WE_Holiday|.*ASC_Up|.*ASC_Down|.*ASC_AutoAstroModeMorning|.*ASC_AutoAstroModeMorningHorizon|.*ASC_AutoAstroModeEvening|.*ASC_AutoAstroModeEveningHorizon|.*ASC_Time_Up_Early|.*ASC_Time_Up_Late|.*ASC_Time_Down_Early|.*ASC_Time_Down_Late|.*ASC_autoAstroModeMorning|.*ASC_autoAstroModeMorningHorizon|.*ASC_PrivacyDownValue_beforeNightClose|.*ASC_PrivacyUpValue_beforeDayOpen|.*ASC_autoAstroModeEvening|.*ASC_autoAstroModeEveningHorizon|.*ASC_Roommate_Device|.*ASC_WindowRec|.*ASC_residentsDev|.*ASC_rainSensor|.*ASC_windSensor|.*ASC_tempSensor|.*ASC_BrightnessSensor|.*ASC_twilightDevice|.*ASC_ExternalTrigger)(\s.*|$)}xms,
            @{$events}
          )
        {
            EventProcessingGeneral( $hash, undef, join( ' ', @{$events} ) );
        }
    }
    elsif ( grep m{^($posReading):\s\d{1,3}$}xms, @{$events} ) {
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
            CommandSet( undef, $name . ' controlShading on' )
              if ( ReadingsVal( $name, 'controlShading', 'off' ) ne 'off' );
        }
    }

    return;
}

sub Set {
    my $hash = shift // return;
    my $aArg = shift // return;

    my $name = shift @$aArg;
    my $cmd  = shift @$aArg
      // return qq{"set $name" needs at least one argument};

    if ( lc $cmd eq 'renewalltimer' ) {
        return "usage: $cmd" if ( scalar( @{$aArg} ) != 0 );
        RenewSunRiseSetShuttersTimer($hash);
    }
    elsif ( lc $cmd eq 'renewtimer' ) {
        return "usage: $cmd" if ( scalar( @{$aArg} ) > 1 );
        CreateSunRiseSetShuttersTimer( $hash, $aArg->[0] );
    }
    elsif ( lc $cmd eq 'scanforshutters' ) {
        return "usage: $cmd" if ( scalar( @{$aArg} ) != 0 );
        ShuttersDeviceScan($hash);
    }
    elsif ( lc $cmd eq 'createnewnotifydev' ) {
        return "usage: $cmd" if ( scalar( @{$aArg} ) != 0 );
        CreateNewNotifyDev($hash);
    }
    elsif ( lc $cmd eq 'partymode' ) {
        return "usage: $cmd" if ( scalar( @{$aArg} ) > 1 );
        readingsSingleUpdate( $hash, $cmd, $aArg->[0], 1 )
          if ( $aArg->[0] ne ReadingsVal( $name, 'partyMode', 0 ) );
    }
    elsif ( lc $cmd eq 'hardlockout' ) {
        return "usage: $cmd" if ( scalar( @{$aArg} ) > 1 );
        readingsSingleUpdate( $hash, $cmd, $aArg->[0], 1 );
        HardewareBlockForShutters( $hash, $aArg->[0] );
    }
    elsif ( lc $cmd eq 'sunrisetimeweholiday' ) {
        return "usage: $cmd" if ( scalar( @{$aArg} ) > 1 );
        readingsSingleUpdate( $hash, $cmd, $aArg->[0], 1 );
    }
    elsif ( lc $cmd eq 'controlshading' ) {
        return "usage: $cmd" if ( scalar( @{$aArg} ) > 1 );

        my $response = _CheckASC_ConditionsForShadingFn($hash);
        readingsSingleUpdate(
            $hash, $cmd,
            (
                $aArg->[0] eq 'off' ? $aArg->[0]
                : (
                      $response eq 'none' ? $aArg->[0]
                    : $response
                )
            ),
            1
        );
    }
    elsif ( lc $cmd eq 'selfdefense' ) {
        return "usage: $cmd" if ( scalar( @{$aArg} ) > 1 );
        readingsSingleUpdate( $hash, $cmd, $aArg->[0], 1 );
    }
    elsif ( lc $cmd eq 'ascenable' ) {
        return "usage: $cmd" if ( scalar( @{$aArg} ) > 1 );
        readingsSingleUpdate( $hash, $cmd, $aArg->[0], 1 );
    }
    elsif ( lc $cmd eq 'advdrivedown' ) {
        return "usage: $cmd" if ( scalar( @{$aArg} ) != 0 );
        EventProcessingAdvShuttersClose($hash);
    }
    elsif ( lc $cmd eq 'shutterascenabletoggle' ) {
        return "usage: $cmd" if ( scalar( @{$aArg} ) > 1 );
        readingsSingleUpdate(
            $defs{ $aArg->[0] },
            'ASC_Enable',
            (
                ReadingsVal( $aArg->[0], 'ASC_Enable', 'off' ) eq 'on'
                ? 'off'
                : 'on'
            ),
            1
        );
    }
    elsif ( lc $cmd eq 'wiggle' ) {
        return "usage: $cmd" if ( scalar( @{$aArg} ) > 1 );

        (
            $aArg->[0] eq 'all'
            ? wiggleAll($hash)
            : wiggle( $hash, $aArg->[0] )
        );
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
    my $hash = shift // return;
    my $aArg = shift // return;

    my $name = shift @$aArg // return;
    my $cmd  = shift @$aArg
      // return qq{"get $name" needs at least one argument};

    if ( lc $cmd eq 'shownotifydevsinformations' ) {
        return "usage: $cmd" if ( scalar( @{$aArg} ) != 0 );
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

    if ( scalar(@list) == 0 ) {
        readingsBeginUpdate($hash);
        readingsBulkUpdate( $hash, 'userAttrList', 'none' );
        readingsBulkUpdate( $hash, 'state',        'no shutters found' );
        readingsEndUpdate( $hash, 1 );
        return;
    }
    my $shuttersList = '';
    for my $shuttersDev (@list) {
        push( @{ $hash->{helper}{shuttersList} }, $shuttersDev )
          ; ## einem Hash wird ein Array zugewiesen welches die Liste der erkannten Rollos beinhaltet

        $shutters->setShuttersDev($shuttersDev);

        #### Ab hier können temporäre Änderungen der Attribute gesetzt werden
        #### Gleichlautende Attribute wo lediglich die Parameter geändert werden sollen müssen hier gelöscht und die Parameter in der Funktion renewSetSunriseSunsetTimer gesetzt werden,
        #### vorher empfiehlt es sich die dort vergebenen Parameter aus zu lesen um sie dann hier wieder neu zu setzen. Dazu wird das shutters Objekt um einen Eintrag
        #### 'AttrUpdateChanges' erweitert
        if (
            ReadingsVal(
                $shuttersDev, '.ASC_AttrUpdateChanges_' . $hash->{VERSION},
                0
            ) == 0
          )
        {
#             $shutters->setAttrUpdateChanges( 'ASC_Up',
#                 AttrVal( $shuttersDev, 'ASC_Up', 'none' ) );
#             delFromDevAttrList( $shuttersDev, 'ASC_Up' );
#             $shutters->setAttrUpdateChanges( 'ASC_Down',
#                 AttrVal( $shuttersDev, 'ASC_Down', 'none' ) );
#             delFromDevAttrList( $shuttersDev, 'ASC_Down' );
#             $shutters->setAttrUpdateChanges( 'ASC_Self_Defense_Mode',
#                 AttrVal( $shuttersDev, 'ASC_Self_Defense_Mode', 'none' ) );
#             delFromDevAttrList( $shuttersDev, 'ASC_Self_Defense_Mode' );
#             $shutters->setAttrUpdateChanges( 'ASC_Self_Defense_Exclude',
#                 AttrVal( $shuttersDev, 'ASC_Self_Defense_Exclude', 'none' ) );
#             delFromDevAttrList( $shuttersDev, 'ASC_Self_Defense_Exclude' );
        }

        ####
        ####

        $shuttersList = $shuttersList . ',' . $shuttersDev;
        $shutters->setLastManPos( $shutters->getStatus );
        $shutters->setLastPos( $shutters->getStatus );
        $shutters->setDelayCmd('none');
        $shutters->setNoDelay(0);
        $shutters->setSelfDefenseAbsent( 0, 0 );
        $shutters->setPosSetCmd( $posSetCmds{ $defs{$shuttersDev}->{TYPE} } );
        $shutters->setShadingStatus(
            ( $shutters->getStatus != $shutters->getShadingPos ? 'out' : 'in' )
        );

#         $shutters->setShadingLastStatus(
#             ( $shutters->getStatus != $shutters->getShadingPos ? 'in' : 'out' )
#         );
        $shutters->setPushBrightnessInArray( $shutters->getBrightness );
        readingsSingleUpdate( $defs{$shuttersDev}, 'ASC_Enable', 'on', 0 )
          if ( ReadingsVal( $shuttersDev, 'ASC_Enable', 'none' ) eq 'none' );

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
        while ( my $shuttersDev = each %{ $hash->{monitoredDevs} } ) {
            $notifyDevString .= ',' . $shuttersDev;
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
    for my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
        readingsBulkUpdate(
            $hash,
            'room_'
              . makeReadingName( AttrVal( $shuttersDev, 'room', 'unsorted' ) ),
            ReadingsVal(
                $name,
                'room_'
                  . makeReadingName(
                    AttrVal( $shuttersDev, 'room', 'unsorted' )
                  ),
                ''
              )
              . ','
              . $shuttersDev
          )
          if (
            ReadingsVal(
                $name,
                'room_'
                  . makeReadingName(
                    AttrVal( $shuttersDev, 'room', 'unsorted' )
                  ),
                'none'
            ) ne 'none'
          );

        readingsBulkUpdate(
            $hash,
            'room_'
              . makeReadingName( AttrVal( $shuttersDev, 'room', 'unsorted' ) ),
            $shuttersDev
          )
          if (
            ReadingsVal(
                $name,
                'room_'
                  . makeReadingName(
                    AttrVal( $shuttersDev, 'room', 'unsorted' )
                  ),
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
        for my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
            addToDevAttrList( $shuttersDev, $attrib )
              ; ## fhem.pl bietet eine Funktion um ein userAttr Attribut zu befüllen. Wir schreiben also in den Attribut userAttr alle unsere Attribute rein. Pro Rolladen immer ein Attribut pro Durchlauf
            ## Danach werden die Attribute die im userAttr stehen gesetzt und mit default Werten befüllt
            ## CommandAttr hat nicht funktioniert. Führte zu Problemen
            ## https://github.com/LeonGaultier/fhem-AutoShuttersControl/commit/e33d3cc7815031b087736c1054b98c57817e7083
            if ( $cmd eq 'add' ) {
                if ( ref($attribValue) ne 'ARRAY' ) {
                    $attr{$shuttersDev}{ ( split( ':', $attrib ) )[0] } =
                      $attribValue
                      if (
                        !defined(
                            $attr{$shuttersDev}{ ( split( ':', $attrib ) )[0] }
                        )
                        && $attribValue ne '-'
                      );
                }
                else {
                    $attr{$shuttersDev}{ ( split( ':', $attrib ) )[0] } =
                      $attribValue->[ AttrVal( $shuttersDev, 'ASC', 2 ) ]
                      if (
                        !defined(
                            $attr{$shuttersDev}{ ( split( ':', $attrib ) )[0] }
                        )
                        && $attrib eq 'ASC_Pos_Reading'
                      );
                }

                ### associatedWith damit man sieht das der Rollladen mit einem ASC Device verbunden ist
                my $associatedString =
                  ReadingsVal( $shuttersDev, 'associatedWith', 'none' );
                if ( $associatedString ne 'none' ) {
                    my %hash;
                    %hash = map { ( $_ => 1 ) }
                      split( ',', "$associatedString,$name" );

                    readingsSingleUpdate( $defs{$shuttersDev},
                        'associatedWith', join( ',', sort keys %hash ), 0 );
                }
                else {
                    readingsSingleUpdate( $defs{$shuttersDev},
                        'associatedWith', $name, 0 );
                }
                #######################################
            }
            ## Oder das Attribut wird wieder gelöscht.
            elsif ( $cmd eq 'del' ) {
                $shutters->setShuttersDev($shuttersDev);

                RemoveInternalTimer( $shutters->getInTimerFuncHash );
                CommandDeleteReading( undef, $shuttersDev . ' .?(ASC)_.*' );
                CommandDeleteAttr( undef, $shuttersDev . ' ASC' );
                delFromDevAttrList( $shuttersDev, $attrib );

                ### associatedWith wird wieder entfernt
                my $associatedString =
                  ReadingsVal( $shuttersDev, 'associatedWith', 'none' );
                my %hash;
                %hash = map { ( $_ => 1 ) }
                  grep { " $name " !~ m{ $shuttersDev }xms }
                  split( ',', "$associatedString,$name" );

                if ( keys %hash > 1 ) {
                    readingsSingleUpdate( $defs{$shuttersDev},
                        'associatedWith', join( ',', sort keys %hash ), 0 );
                }
                else {
                    CommandDeleteReading( undef,
                        $shuttersDev . ' associatedWith' );
                }
                ###################################
            }
        }
    }

    return;
}

## Fügt dem NOTIFYDEV Hash weitere Devices hinzu
sub AddNotifyDev {
    ### Beispielaufruf: AddNotifyDev( $hash, $3, $1, $2 ) if ( $3 ne 'none' );
    my ( $hash, $attrVal, $shuttersDev, $shuttersAttr ) = @_;

    $attrVal = ( split( ':', $attrVal ) )[0];
    my ( $key, $value ) = split( ':', ( split( ' ', $attrVal ) )[0], 2 )
      ; ## Wir versuchen die Device Attribute anders zu setzen. device=DEVICE reading=READING
    $attrVal = $key;

    my $name = $hash->{NAME};

    my $notifyDev = $hash->{NOTIFYDEV};
    $notifyDev = '' if ( !$notifyDev );

    my %hash;
    %hash = map { ( $_ => 1 ) }
      split( ',', "$notifyDev,$attrVal" );

    $hash->{NOTIFYDEV} = join( ',', sort keys %hash );

    my @devs = split( ',', $attrVal );
    for my $dev (@devs) {
        $hash->{monitoredDevs}{$dev}{$shuttersDev} = $shuttersAttr;
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
              . $notifyDev );
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
                && (
                    (
                          !$shutters->getIsDay
                        && $shutters->getModeDown ne 'roommate'
                    )
                    || $homemode eq 'asleep'
                    || $homemode eq 'gotosleep'
                )
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
            my $posValue = $shutters->getStatus;
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
        my $event                  = $1;
        my $posValue               = $shutters->getStatus;

        if (
            ( $event eq 'home' || $event eq 'awoken' )
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
                    (
                        $getRoommatesLastStatus eq 'asleep'
                        && (   $shutters->getModeUp eq 'always'
                            or $shutters->getModeUp eq $event )
                    )
                    || (
                        $getRoommatesLastStatus eq 'awoken'
                        && (   $shutters->getModeUp eq 'always'
                            or $shutters->getModeUp eq $event )
                    )
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
                elsif ( !$shutters->getIfInShading ) {
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
                       $shutters->getIsDay
                    && $shutters->getIfInShading
                    && $shutters->getStatus != $shutters->getShadingPos
                    && !$shutters->getShadingManualDriveStatus
                    && !(
                        CheckIfShuttersWindowRecOpen($shuttersDev) == 2
                        && $shutters->getShuttersPlace eq 'terrace'
                    )
                    && !$shutters->getSelfDefenseState
                  )
                {
                    ShadingProcessingDriveCommand( $hash, $shuttersDev );
                }
                elsif (
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
                    && !$shutters->getIfInShading
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
            ( $event eq 'gotosleep' || $event eq 'asleep' )
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
            $event eq 'absent'
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
                || (   $shutters->getShadingMode eq 'absent'
                    && $shutters->getRoommatesStatus eq 'none' )
                || (   $shutters->getShadingMode eq 'home'
                    && $shutters->getRoommatesStatus eq 'none' )
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
                elsif ($shutters->getIsDay
                    && $shutters->getIfInShading
                    && $shutters->getShadingMode eq 'absent'
                    && $shutters->getRoommatesStatus eq 'none' )
                {
                    ShadingProcessingDriveCommand( $hash, $shuttersDev );
                }
                elsif (
                       $shutters->getShadingMode eq 'home'
                    && $shutters->getIsDay
                    && $shutters->getIfInShading
                    && $shutters->getStatus == $shutters->getShadingPos
                    && $shutters->getRoommatesStatus eq 'none'
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
                ShadingProcessingDriveCommand( $hash, $shuttersDev );
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
        elsif (( $val == 0 || $val < $shutters->getWindMin )
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
      if (
        (
               $shutters->getDown ne 'brightness'
            && $shutters->getUp ne 'brightness'
        )
        || (
            (
                   $shutters->getDown eq 'brightness'
                || $shutters->getUp eq 'brightness'
            )
            && (
                (
                    (
                        (
                            int( gettimeofday() / 86400 ) == int(
                                computeAlignTime( '24:00',
                                    $shutters->getTimeUpEarly ) / 86400
                            )
                            && (
                                !IsWe()
                                || (
                                    IsWe()
                                    && $ascDev->getSunriseTimeWeHoliday eq 'off'
                                    || (
                                        $ascDev->getSunriseTimeWeHoliday eq 'on'
                                        && $shutters->getTimeUpWeHoliday eq
                                        '01:25' )
                                )
                            )
                        )
                        || (
                            int( gettimeofday() / 86400 ) == int(
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

                    || (
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
                                    || (
                                        $ascDev->getSunriseTimeWeHoliday eq 'on'
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
                    && int( gettimeofday() / 86400 ) != int(
                        computeAlignTime( '24:00', $shutters->getTimeUpLate ) /
                          86400
                    )
                )
                && (
                   (
                    int( gettimeofday() / 86400 ) == int(
                        computeAlignTime(
                            '24:00', $shutters->getTimeDownEarly
                        ) / 86400
                    )
                    && int( gettimeofday() / 86400 ) == int(
                        computeAlignTime( '24:00', $shutters->getTimeDownLate
                        ) / 86400
                    )
                )
                || (
                    int( gettimeofday() / 86400 ) != int(
                        computeAlignTime(
                            '24:00', $shutters->getTimeDownEarly
                        ) / 86400
                    )
                    && int( gettimeofday() / 86400 ) != int(
                        computeAlignTime( '24:00', $shutters->getTimeDownLate
                        ) / 86400
                    )
                )
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
                          if (
                            $shutters->getQueryShuttersPos(
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
                my $posValue = $shutters->getStatus;
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
#                     && (   $posValue != $shutters->getStatus
#                         || $shutters->getSelfDefenseState )
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
                  if ( $shutters->getPrivacyDownStatus != 2 );

                ASC_Debug( 'EventProcessingBrightness: '
                      . $shutters->getShuttersDev
                      . ' - Verarbeitung für Sunset. Roommatestatus nicht zum runter fahren. Fahrbebehl bleibt aus!!! Es wird an die Event verarbeitende Beschattungsfunktion weiter gereicht'
                );
            }
        }
        else {
            EventProcessingShadingBrightness( $hash, $shuttersDev, $events )
              if ( $shutters->getPrivacyDownStatus != 2 );

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
    my $outTemp = (
          $shutters->getOutTemp != -100
        ? $shutters->getOutTemp
        : $ascDev->getOutTemp
    );

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
        my $name    = $device;
        my $outTemp = $ascDev->getOutTemp;
        my ( $azimuth, $elevation );

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
    my $shuttersDevHash  = $defs{$shuttersDev};

    my $getModeUp = $shutters->getModeUp;
    my $homemode  = $shutters->getHomemode;

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
        #         $shutters->setShadingLastStatus('in');
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

            #             $shutters->setShadingLastStatus('in')
            #               if ( $shutters->getShadingLastStatus eq 'out' );
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
        if (   $shutters->getShadingStatus eq 'out'
            || $shutters->getShadingStatus eq 'out reserved' )
        {
            $shutters->setShadingStatus('in reserved');

        }

        if ( $shutters->getShadingStatus eq 'in reserved'
            and
            ( int( gettimeofday() ) - $shutters->getShadingStatusTimestamp ) >
            ( $shutters->getShadingWaitingPeriod / 2 ) )
        {
            $shutters->setShadingStatus('in');

            #             $shutters->setShadingLastStatus('out')
            #               if ( $shutters->getShadingLastStatus eq 'in' );
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
            || $shutters->getModeUp eq 'off'
            || $shutters->getModeUp eq 'absent'
            || (   $shutters->getModeUp eq 'home'
                && $homemode ne 'asleep' )
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

    readingsBeginUpdate($shuttersDevHash);
    readingsBulkUpdate(
        $shuttersDevHash,
        'ASC_ShadingMessage',
        'INFO: current shading status is \''
          . $shutters->getShadingStatus . '\''
          . ' - next check in '
          . (
            (
                (
                         $shutters->getShadingLastStatus eq 'out reserved'
                      || $shutters->getShadingLastStatus eq 'out'
                )
                ? $shutters->getShadingWaitingPeriod
                : $shutters->getShadingWaitingPeriod / 2
            )
          ) / 60
          . 'm'
    );
    readingsEndUpdate( $shuttersDevHash, 1 );

    return;
}

sub ShadingProcessingDriveCommand {
    my $hash        = shift;
    my $shuttersDev = shift;

    my $name = $hash->{NAME};
    $shutters->setShuttersDev($shuttersDev);

    my $getShadingPos = $shutters->getShadingPos;
    my $getStatus     = $shutters->getStatus;

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
            $shutters->setExternalTriggerStatus(1);
            ShuttersCommandSet( $hash, $shuttersDev, $triggerPosActive2 );
        }
        else {
            $shutters->setLastDrive('external trigger device active');
            $shutters->setNoDelay(1);
            $shutters->setExternalTriggerStatus(1);
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
        $shutters->setExternalTriggerStatus(1);
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
            CheckIfShuttersWindowRecOpen($shuttersDev) == 2
            && $shutters->getShuttersPlace eq 'terrace'
            && (   $shutters->getLockOut eq 'soft'
                || $shutters->getLockOut eq 'hard' )
            && !$shutters->getQueryShuttersPos($posValue)
        )
        || (
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
                || $shutters->getWindProtectionStatus eq 'protected' )
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
    my $hash = shift;
    my $shuttersDev = shift // return Log3( $hash->{NAME}, 1,
"AutoShuttersControl ($hash->{NAME}) - Error in function  CreateSunRiseSetShuttersTimer. No shuttersDev given"
    );

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
    ##  1 bedeutet das Privacy Timer aktiviert wurde, 2 beudet das er im privacy ist
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

    for my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
        my $dhash = $defs{$shuttersDev};

        $shutters->setShuttersDev($shuttersDev);

        RemoveInternalTimer( $shutters->getInTimerFuncHash );
        $shutters->setInTimerFuncHash(undef);
        CreateSunRiseSetShuttersTimer( $hash, $shuttersDev );

        #### Temporär angelegt damit die neue Attributs Parameter Syntax verteilt werden kann
        #### Gleichlautende Attribute wo lediglich die Parameter geändert werden sollen müssen bereits in der Funktion ShuttersDeviceScan gelöscht werden
        #### vorher empfiehlt es sich die dort vergebenen Parameter aus zu lesen um sie dann hier wieder neu zu setzen. Dazu wird das shutters Objekt um einen Eintrag
        #### 'AttrUpdateChanges' erweitert
        if (
            ( int( gettimeofday() ) - $::fhem_started ) < 60
            and ReadingsVal(
                $shuttersDev, '.ASC_AttrUpdateChanges_' . $hash->{VERSION},
                0
            ) == 0
          )
        {
#             $attr{$shuttersDev}{'ASC_Up'} = $shutters->getAttrUpdateChanges('ASC_Up')
#               if ( $shutters->getAttrUpdateChanges('ASC_Up') ne 'none' );
#             $attr{$shuttersDev}{'ASC_Down'} =
#               $shutters->getAttrUpdateChanges('ASC_Down')
#               if ( $shutters->getAttrUpdateChanges('ASC_Down') ne 'none' );
#             $attr{$shuttersDev}{'ASC_Self_Defense_Mode'} =
#               $shutters->getAttrUpdateChanges('ASC_Self_Defense_Mode')
#               if ( $shutters->getAttrUpdateChanges('ASC_Self_Defense_Mode') ne
#                 'none' );
#             $attr{$shuttersDev}{'ASC_Self_Defense_Mode'} = 'off'
#               if (
#                 $shutters->getAttrUpdateChanges('ASC_Self_Defense_Exclude') eq
#                 'on' );

            CommandDeleteReading( undef,
                $shuttersDev . ' .ASC_AttrUpdateChanges_.*' )
              if (
                ReadingsVal( $shuttersDev,
                    '.ASC_AttrUpdateChanges_' . $hash->{VERSION}, 'none' ) eq
                'none'
              );
            readingsSingleUpdate( $dhash,
                '.ASC_AttrUpdateChanges_' . $hash->{VERSION},
                1, 0 );
        }

#         $attr{$shuttersDev}{ASC_Drive_Delay} =
#           AttrVal( $shuttersDev, 'ASC_Drive_Offset', 'none' )
#           if ( AttrVal( $shuttersDev, 'ASC_Drive_Offset', 'none' ) ne 'none' );
#         delFromDevAttrList( $shuttersDev, 'ASC_Drive_Offset' );
#
#         $attr{$shuttersDev}{ASC_Drive_DelayStart} =
#           AttrVal( $shuttersDev, 'ASC_Drive_OffsetStart', 'none' )
#           if ( AttrVal( $shuttersDev, 'ASC_Drive_OffsetStart', 'none' ) ne 'none' );
#         delFromDevAttrList( $shuttersDev, 'ASC_Drive_OffsetStart' );
#
#         $attr{$shuttersDev}{ASC_Shading_StateChange_SunnyCloudy} =
#             AttrVal( $shuttersDev, 'ASC_Shading_StateChange_Sunny', 'none' ) . ':'
#           . AttrVal( $shuttersDev, 'ASC_Shading_StateChange_Cloudy', 'none' )
#           if (
#             AttrVal( $shuttersDev, 'ASC_Shading_StateChange_Sunny', 'none' ) ne 'none'
#             && AttrVal( $shuttersDev, 'ASC_Shading_StateChange_Cloudy', 'none' ) ne
#             'none' );
#         delFromDevAttrList( $shuttersDev, 'ASC_Shading_StateChange_Sunny' );
#         delFromDevAttrList( $shuttersDev, 'ASC_Shading_StateChange_Cloudy' );
#
#         $attr{$shuttersDev}{ASC_Shading_InOutAzimuth} =
#           ( AttrVal( $shuttersDev, 'ASC_Shading_Direction', 180 ) -
#               AttrVal( $shuttersDev, 'ASC_Shading_Angle_Left', 85 ) )
#           . ':'
#           . ( AttrVal( $shuttersDev, 'ASC_Shading_Direction', 180 ) +
#               AttrVal( $shuttersDev, 'ASC_Shading_Angle_Right', 85 ) )
#           if ( AttrVal( $shuttersDev, 'ASC_Shading_Direction', 'none' ) ne 'none'
#             || AttrVal( $shuttersDev, 'ASC_Shading_Angle_Left',  'none' ) ne 'none'
#             || AttrVal( $shuttersDev, 'ASC_Shading_Angle_Right', 'none' ) ne 'none' );
#         delFromDevAttrList( $shuttersDev, 'ASC_Shading_Direction' );
#         delFromDevAttrList( $shuttersDev, 'ASC_Shading_Angle_Left' );
#         delFromDevAttrList( $shuttersDev, 'ASC_Shading_Angle_Right' );
#
#         $attr{$shuttersDev}{ASC_PrivacyDownValue_beforeNightClose} =
#           AttrVal( $shuttersDev, 'ASC_PrivacyDownTime_beforNightClose', 'none' )
#           if (
#             AttrVal( $shuttersDev, 'ASC_PrivacyDownTime_beforNightClose', 'none' ) ne
#             'none' );
#         delFromDevAttrList( $shuttersDev, 'ASC_PrivacyDownTime_beforNightClose' );
#
#         delFromDevAttrList( $shuttersDev, 'ASC_ExternalTriggerDevice' );
    }

    return;
}

## Funktion zum hardwareseitigen setzen des lock-out oder blocking beim Rolladen selbst
sub HardewareBlockForShutters {
    my $hash = shift;
    my $cmd  = shift;

    for my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
        $shutters->setShuttersDev($shuttersDev);
        $shutters->setHardLockOut($cmd);
    }

    return;
}

## Funktion für das wiggle aller Shutters zusammen
sub wiggleAll {
    my $hash = shift;

    for my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
        wiggle( $hash, $shuttersDev );
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
              if (
                !$shutters->getQueryShuttersPos( $shutters->getPrivacyDownPos )
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

    if ( $shutters->getPrivacyDownStatus != 2 ) {
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
                      if (
                        $shutters->getQueryShuttersPos(
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

    if ( $shutters->getPrivacyUpStatus != 2 ) {
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
    for my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
        AddNotifyDev( $hash,
            AttrVal( $shuttersDev, 'ASC_Roommate_Device', 'none' ),
            $shuttersDev, 'ASC_Roommate_Device' )
          if (
            AttrVal( $shuttersDev, 'ASC_Roommate_Device', 'none' ) ne 'none' );
        AddNotifyDev( $hash, AttrVal( $shuttersDev, 'ASC_WindowRec', 'none' ),
            $shuttersDev, 'ASC_WindowRec' )
          if ( AttrVal( $shuttersDev, 'ASC_WindowRec', 'none' ) ne 'none' );
        AddNotifyDev( $hash,
            AttrVal( $shuttersDev, 'ASC_BrightnessSensor', 'none' ),
            $shuttersDev, 'ASC_BrightnessSensor' )
          if (
            AttrVal( $shuttersDev, 'ASC_BrightnessSensor', 'none' ) ne 'none' );
        AddNotifyDev( $hash,
            AttrVal( $shuttersDev, 'ASC_ExternalTrigger', 'none' ),
            $shuttersDev, 'ASC_ExternalTrigger' )
          if (
            AttrVal( $shuttersDev, 'ASC_ExternalTrigger', 'none' ) ne 'none' );

        $shuttersList = $shuttersList . ',' . $shuttersDev;
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
    for my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
        $shutters->setShuttersDev($shuttersDev);

        if   ( $linecount % 2 == 0 ) { $ret .= '<tr class="even">'; }
        else                         { $ret .= '<tr class="odd">'; }
        $ret .= "<td>$shuttersDev</td>";
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
          . ReadingsVal( $shuttersDev, 'ASC_ShuttersLastDrive', 'none' )
          . "</td>";
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
                for my $shuttersDev (
                    sort keys( %{ $notifydevs->{$notifydev} } ) )
                {
                    if ( $linecount % 2 == 0 ) { $ret .= '<tr class="even">'; }
                    else                       { $ret .= '<tr class="odd">'; }
                    $ret .= "<td>$shuttersDev</td>";
                    $ret .= "<td> </td>";
                    $ret .= "<td>$notifydev</td>";
                    $ret .= "<td> </td>";
                    $ret .= "<td>$notifydevs->{$notifydev}{$shuttersDev}</td>";
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

    my $brightnessMinVal = (
          $shutters->getBrightnessMinVal > -1
        ? $shutters->getBrightnessMinVal
        : $ascDev->getBrightnessMinVal
    );

    my $brightnessMaxVal = (
          $shutters->getBrightnessMaxVal > -1
        ? $shutters->getBrightnessMaxVal
        : $ascDev->getBrightnessMaxVal
    );

    my $isday = ( ShuttersSunrise( $shuttersDev, 'unix' ) >
          ShuttersSunset( $shuttersDev, 'unix' ) ? 1 : 0 );
    my $respIsDay = $isday;

    ASC_Debug( 'FnIsDay: ' . $shuttersDev . ' Allgemein: ' . $respIsDay );

    if (
        (
            (
                (
                    int( gettimeofday() / 86400 ) != int(
                        computeAlignTime( '24:00', $shutters->getTimeUpEarly )
                          / 86400
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
                computeAlignTime( '24:00', $shutters->getTimeUpLate ) / 86400
            )
        )
        || (
            int( gettimeofday() / 86400 ) != int(
                computeAlignTime( '24:00', $shutters->getTimeDownEarly ) /
                  86400
            )
            && int( gettimeofday() / 86400 ) == int(
                computeAlignTime( '24:00', $shutters->getTimeDownLate ) / 86400
            )
        )
      )
    {
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
                      && !$isday
                      && $shutters->getSunrise
                )
                  || $respIsDay
                  || $shutters->getSunrise
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

sub _DetermineSlatCmd {
    my $value    = shift;
    my $posValue = shift;

    return $posValue    == $shutters->getShadingPos
            && $shutters->getShadingPositionAssignment      ne 'none'   ? $shutters->getShadingPositionAssignment
        : $posValue     == $shutters->getVentilatePos
            && $shutters->getVentilatePositionAssignment    ne 'none'   ? $shutters->getVentilatePositionAssignment
        : $posValue     == $shutters->getOpenPos
            && $shutters->getOpenPositionAssignment         ne 'none'   ? $shutters->getOpenPositionAssignment
        : $posValue     == $shutters->getClosedPos
            && $shutters->getClosedPositionAssignment       ne 'none'   ? $shutters->getClosedPositionAssignment
        : $posValue     == $shutters->getSleepPos
            && $shutters->getSleepPositionAssignment        ne 'none'   ? $shutters->getSleepPositionAssignment
        : $posValue     == $shutters->getComfortOpenPos
            && $shutters->getComfortOpenPositionAssignment  ne 'none'   ? $shutters->getComfortOpenPositionAssignment
        : $posValue     == $shutters->getPrivacyUpPos
            && $shutters->getPrivacyUpPositionAssignment    ne 'none'   ? $shutters->getPrivacyUpPositionAssignment
        : $posValue     == $shutters->getPrivacyDownPos
            && $shutters->getPrivacyDownPositionAssignment  ne 'none'   ? $shutters->getPrivacyDownPositionAssignment
        : $value;
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
      if (
           $shutters->getASCenable eq 'off'
        && $ascDev->getASCenable eq 'off'
        && (   $idleDetection !~ m{^$idleDetectionValue$}xms
            || $idleDetection ne 'none' )
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

    my $driveCommand = $shutters->getPosSetCmd . ' ' . $posValue;
    my $slatPos      = -1;

    if (   $shutters->getShadingPositionAssignment ne 'none'
        || $shutters->getOpenPositionAssignment ne 'none'
        || $shutters->getClosedPositionAssignment ne 'none'
        || $shutters->getPrivacyUpPositionAssignment ne 'none'
        || $shutters->getPrivacyDownPositionAssignment ne 'none'
        || $shutters->getSleepPositionAssignment ne 'none'
        || $shutters->getVentilatePositionAssignment ne 'none'
        || $shutters->getComfortOpenPositionAssignment ne 'none' )
    {
        if (
            (
                $shutters->getShadingPositionAssignment =~ m{\A[a-zA-Z]+\z}xms
                && $shutters->getShadingPositionAssignment ne 'none'
            )
            || (   $shutters->getOpenPositionAssignment =~ m{\A[a-zA-Z]+\z}xms
                && $shutters->getOpenPositionAssignment ne 'none' )
            || (   $shutters->getClosedPositionAssignment =~ m{\A[a-zA-Z]+\z}xms
                && $shutters->getClosedPositionAssignment ne 'none' )
            || (
                $shutters->getPrivacyUpPositionAssignment =~ m{\A[a-zA-Z]+\z}xms
                && $shutters->getPrivacyUpPositionAssignment ne 'none' )
            || ( $shutters->getPrivacyDownPositionAssignment =~
                m{\A[a-zA-Z]+\z}xms
                && $shutters->getPrivacyDownPositionAssignment ne 'none' )
            || (   $shutters->getSleepPositionAssignment =~ m{\A[a-zA-Z]+\z}xms
                && $shutters->getSleepPositionAssignment ne 'none' )
            || (
                $shutters->getVentilatePositionAssignment =~ m{\A[a-zA-Z]+\z}xms
                && $shutters->getVentilatePositionAssignment ne 'none' )
            || ( $shutters->getComfortOpenPositionAssignment =~
                m{\A[a-zA-Z]+\z}xms
                && $shutters->getComfortOpenPositionAssignment ne 'none' )
          )
        {
            $driveCommand = _DetermineSlatCmd( $driveCommand, $posValue );
        }
        elsif ($shutters->getShadingPositionAssignment =~ m{\A\d{1,3}\z}xms
            || $shutters->getOpenPositionAssignment =~ m{\A\d{1,3}\z}xms
            || $shutters->getClosedPositionAssignment =~ m{\A\d{1,3}\z}xms
            || $shutters->getPrivacyUpPositionAssignment =~ m{\A\d{1,3}\z}xms
            || $shutters->getPrivacyDownPositionAssignment =~ m{\A\d{1,3}\z}xms
            || $shutters->getSleepPositionAssignment =~ m{\A\d{1,3}\z}xms
            || $shutters->getVentilatePositionAssignment =~ m{\A\d{1,3}\z}xms
            || $shutters->getComfortOpenPositionAssignment =~
            m{\A\d{1,3}\z}xms )
        {
            $slatPos = _DetermineSlatCmd( $slatPos, $posValue );
        }
    }

    CommandSet( undef,
            $shuttersDev
            . ':FILTER='
            . $shutters->getPosCmd . '!='
            . $posValue . ' '
            . $driveCommand );

    InternalTimer(
        gettimeofday() + 3,
        sub() {
            CommandSet(
                undef,
                (
                        $shutters->getSlatDevice ne 'none'
                    ? $shutters->getSlatDevice
                    : $shuttersDev
                    )
                    . ' '
                    . $shutters->getSlatPosCmd . ' '
                    . $slatPos
            );
        },
        $shuttersDev
        )
        if ( $slatPos > -1
        && $shutters->getSlatPosCmd ne 'none' );

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
      if ( !AttrVal( $ascDev->getName, 'ASC_debug', 0 ) );

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

    if ( $exec =~ m{\A\{(.+)\}\z}xms ) {
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
        if ( $shutters->getPrivacyUpStatus != 2 ) {
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
        if ( $shutters->getPrivacyDownStatus != 2 ) {
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

sub _CheckASC_ConditionsForShadingFn {
    my $hash = shift;

    my $error;

    $error .=
' no valid data from the ASC temperature sensor, is ASC_tempSensor attribut set?'
      if ( $ascDev->getOutTemp == -100 );
    $error .= ' no twilight device found'
      if ( $ascDev->_getTwilightDevice eq 'none' );

    my $count = 1;
    for my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
        InternalTimer(
            gettimeofday() + $count,
'FHEM::Automation::ShuttersControl::_CheckShuttersConditionsForShadingFn',
            $shuttersDev
        );

        $count++;
    }

    return (
        defined($error)
        ? $error
        : 'none'
    );
}

sub _CheckShuttersConditionsForShadingFn {
    my $shuttersDev = shift;

    $shutters->setShuttersDev($shuttersDev);
    my $shuttersDevHash = $defs{$shuttersDev};
    my $message         = '';
    my $errorMessage;
    my $warnMessage;
    my $infoMessage;

    $infoMessage .= (
        $shutters->getShadingMode ne 'off'
          && $ascDev->getAutoShuttersControlShading eq 'on'
          && $shutters->getOutTemp == -100
        ? ' shading active, global temp sensor is set, but shutters temperature sensor is not set'
        : ''
    );

    $warnMessage .= (
        $shutters->getShadingMode eq 'off'
          && $ascDev->getAutoShuttersControlShading eq 'on'
        ? ' global shading active but ASC_Shading_Mode attribut is not set or off'
        : ''
    );

    $errorMessage .= (
        $shutters->getShadingMode ne 'off'
          && $ascDev->getAutoShuttersControlShading ne 'on'
          && $ascDev->getAutoShuttersControlShading ne 'off'
        ? ' ASC_Shading_Mode attribut is set but global shading has errors, look at ASC device '
          . '<a href="'
          . '/fhem?detail='
          . ReadingsVal( $shuttersDev, 'associatedWith', 'ASC device' )
          . $::FW_CSRF . '">'
          . ReadingsVal( $shuttersDev, 'associatedWith', 'ASC device' )
          . '</a>'
        : ''
    );

    $errorMessage .= (
        $shutters->getBrightness == -1 && $shutters->getShadingMode ne 'off'
        ? ' no brightness sensor found, please set ASC_BrightnessSensor attribut'
        : ''
    );

    $message .= ' ERROR: ' . $errorMessage
      if ( defined($errorMessage)
        && $errorMessage ne '' );

    $message .= ' WARN: ' . $warnMessage
      if ( defined($warnMessage)
        && $warnMessage ne ''
        && $errorMessage eq '' );

    $message .= ' INFO: ' . $infoMessage
      if ( defined($infoMessage)
        && $infoMessage ne ''
        && $errorMessage eq '' );

    readingsBeginUpdate($shuttersDevHash);
    readingsBulkUpdateIfChanged( $shuttersDevHash, 'ASC_ShadingMessage',
        '<html>' . $message . ' </html>' );
    readingsEndUpdate( $shuttersDevHash, 1 );
}

1;
