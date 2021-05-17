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

use FHEM::Automation::ShuttersControl::Shading qw (CheckASC_ConditionsForShadingFn);
use FHEM::Automation::ShuttersControl::EventProcessingFunctions qw (:ALL);
use FHEM::Automation::ShuttersControl::Helper qw (:ALL);

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
    'ASC_Shading_BetweenTheTime'                           => '-',
    'ASC_Drive_Delay'                                      => '-',
    'ASC_Drive_DelayStart'                                 => '-',
    'ASC_Shutter_IdleDetection'                            => '-',
    'ASC_WindowRec'                                        => '-',
    'ASC_WindowRec_subType:twostate,threestate'            => '-',
    'ASC_WindowRec_PosAfterDayClosed:open,lastManual'      => '-',
    'ASC_ShuttersPlace:window,terrace,awning'              => '-',
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
    my $getCommand = shift;
    my $shutterDev = shift;
    my $value      = shift;

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
    my $setCommand = shift;
    my $shutterDev = shift;
    my $value      = shift;

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

sub Delete {
    my $hash = shift;
    my $name = shift;

    RemoveShuttersTimer($hash);

    return;
}

sub Shutdown {
    my $hash = shift;

    RemoveShuttersTimer($hash);

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
m{^(ATTR|DELETEATTR)\s(.*ASC_Time_Up_WE_Holiday|.*ASC_Up|.*ASC_Down|.*ASC_AutoAstroModeMorning|.*ASC_AutoAstroModeMorningHorizon|.*ASC_AutoAstroModeEvening|.*ASC_AutoAstroModeEveningHorizon|.*ASC_Time_Up_Early|.*ASC_Time_Up_Late|.*ASC_Time_Down_Early|.*ASC_Time_Down_Late|.*ASC_autoAstroModeMorning|.*ASC_autoAstroModeMorningHorizon|.*ASC_PrivacyDownValue_beforeNightClose|.*ASC_PrivacyUpValue_beforeDayOpen|.*ASC_autoAstroModeEvening|.*ASC_autoAstroModeEveningHorizon|.*ASC_Roommate_Device|.*ASC_WindowRec|.*ASC_residentsDev|.*ASC_rainSensor|.*ASC_windSensor|.*ASC_tempSensor|.*ASC_BrightnessSensor|.*ASC_twilightDevice|.*ASC_ExternalTrigger|.*ASC_Shading_StateChange_SunnyCloudy|.*ASC_TempSensor|.*ASC_Shading_Mode)(\s.*|$)}xms,
            @{$events}
          )
        {
            EventProcessingGeneral( $hash, undef, join( ' ', @{$events} ) );
        }
    }
    elsif ( grep m{^($posReading):\s\d{1,3}$}xms, @{$events} ) {
        ASC_Debug( 'Notify: '
              . ' ASC_Pos_Reading Event vom Rollo ' 
              . $devname
              . ' wurde erkannt '
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

        my $response = CheckASC_ConditionsForShadingFn($hash,$aArg->[0]);
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
            $shutters->setAttrUpdateChanges( 'ASC_ShuttersPlace',
                AttrVal( $shuttersDev, 'ASC_ShuttersPlace', 'none' ) );
            delFromDevAttrList( $shuttersDev, 'ASC_ShuttersPlace' );
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
    my $hash         = shift;
    my $shuttersDev  = shift;
    my $shuttersAttr = shift;

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

# Sub für das Zusammensetzen der Rolläden Steuerbefehle
sub ShuttersCommandSet {
    my $hash        = shift;
    my $shuttersDev = shift;
    my $posValue    = shift;

    my $name = $hash->{NAME};
    $shutters->setShuttersDev($shuttersDev);

    if (
        (
               CheckIfShuttersWindowRecOpen($shuttersDev) == 2
            && $shutters->getShuttersPlace eq 'terrace'
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
                && !$shutters->getQueryShuttersPos($posValue)
                && (   $shutters->getLockOut eq 'soft'
                    || $shutters->getLockOut eq 'hard' ) )
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
    my $hash        = shift;
    my $shuttersDev = shift // return Log3( $hash->{NAME}, 1,
"AutoShuttersControl ($hash->{NAME}) - Error in function  CreateSunRiseSetShuttersTimer. No shuttersDev given"
    );

    my $name            = $hash->{NAME};
    my $shuttersDevHash = $defs{$shuttersDev} // return Log3( $hash->{NAME}, 1,
"AutoShuttersControl ($hash->{NAME}) - Error in function  CreateSunRiseSetShuttersTimer. No shuttersDevHash found for device name $shuttersDev"
    );
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
                    "%d.%m.%Y - %H:%M",
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
                    "%d.%m.%Y - %H:%M",
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
            ? strftime( "%d.%m.%Y - %H:%M",
                localtime($shuttersSunriseUnixtime) )
            : strftime(
                "%d.%m.%Y - %H:%M", localtime($shuttersSunsetUnixtime)
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
            $attr{$shuttersDev}{'ASC_ShuttersPlace'} = $shutters->getAttrUpdateChanges('ASC_ShuttersPlace')
              if ( $shutters->getAttrUpdateChanges('ASC_ShuttersPlace') ne 'none' );
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
                && $ascDev->getResidentsStatus ne 'absent'
            )
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
          . strftime( "%d.%m.%Y - %H:%M:%S",
            localtime( $shutters->getSunriseUnixTime ) )
          . "</td>";
        $ret .= "<td> </td>";
        $ret .= "<td>"
          . strftime( "%d.%m.%Y - %H:%M:%S",
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
      if ( $shutters->getASCenable eq 'off'
        || $ascDev->getASCenable eq 'off'
        || $idleDetection !~ m{^$idleDetectionValue$}xms );

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
    my $debugTimestamp = strftime( "%Y.%m.%d %T", localtime(time) );

    print(
        encode_utf8(
            "\n" . 'ASC_DEBUG!!! ' . $debugTimestamp . ' - ' . $debugMsg . "\n"
        )
    );

    return;
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
            strftime( "%d.%m.%Y - %H:%M", localtime($privacyUpUnixtime) ), 1 );
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
                "%d.%m.%Y - %H:%M",
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
            strftime( "%d.%m.%Y - %H:%M", localtime($privacyDownUnixtime) ),
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
                "%d.%m.%Y - %H:%M",
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

sub RemoveShuttersTimer {
    my $hash = shift;

    for my $shuttersDev ( @{ $hash->{helper}{shuttersList} } ) {
        $shutters->setShuttersDev($shuttersDev);

        RemoveInternalTimer( $shutters->getInTimerFuncHash );
        $shutters->setInTimerFuncHash(undef);
    }

    return;
}

1;
