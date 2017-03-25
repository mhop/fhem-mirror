# $Id$
##############################################################################
#
#     10_RESIDENTS.pm
#     An FHEM Perl module to ease resident administration.
#
#     Copyright by Julian Pawlowski
#     e-mail: julian.pawlowski at gmail.com
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################

package main;

use strict;
use warnings;
use Time::Local;
use Data::Dumper;
require RESIDENTStk;

sub RESIDENTS_Set($@);
sub RESIDENTS_Define($$);
sub RESIDENTS_Notify($$);
sub RESIDENTS_Attr(@);
sub RESIDENTS_Undefine($$);

###################################
sub RESIDENTS_Initialize($) {
    my ($hash) = @_;

    Log3 $hash, 5, "RESIDENTS_Initialize: Entering";

    $hash->{SetFn}    = "RESIDENTS_Set";
    $hash->{DefFn}    = "RESIDENTS_Define";
    $hash->{NotifyFn} = "RESIDENTS_Notify";
    $hash->{AttrFn}   = "RESIDENTS_Attr";
    $hash->{UndefFn}  = "RESIDENTS_Undefine";
    $hash->{AttrList} =
"disable:1,0 rgr_showAllStates:0,1 rgr_states:multiple-strict,home,gotosleep,asleep,awoken,absent,gone rgr_lang:EN,DE rgr_noDuration:0,1 rgr_wakeupDevice "
      . $readingFnAttributes;
}

###################################
sub RESIDENTS_Define($$) {
    my ( $hash, $def ) = @_;
    my $name = $hash->{NAME};
    my $name_attr;

    Log3 $name, 5, "RESIDENTS $name: called function RESIDENTS_Define()";

    RESIDENTStk_findResidentSlaves($hash);

    # set default settings on first define
    if ( $init_done && !defined( $hash->{OLDDEF} ) ) {
        RESIDENTS_Attr( "init", $name, "rgr_lang" );
        $attr{$name}{icon}   = "control_building_filled";
        $attr{$name}{room}   = "Residents";
        $attr{$name}{webCmd} = "state";
    }

    # run timers
    InternalTimer(
        gettimeofday() + 15,
        "RESIDENTS_StartInternalTimers",
        $hash, 0
    );

    # Injecting AttrFn for use with RESIDENTS Toolkit
    if ( !defined( $modules{dummy}{AttrFn} ) ) {
        $modules{dummy}{AttrFn} = "RESIDENTStk_AttrFnDummy";
    }
    elsif ( $modules{dummy}{AttrFn} ne "RESIDENTStk_AttrFnDummy" ) {
        Log3 $name, 5,
"RESIDENTStk $name: concurrent AttrFn already defined for dummy module. Some attribute based functions like auto-creations will not be available.";
    }

    return undef;
}

###################################
sub RESIDENTS_Attr(@) {
    my ( $cmd, $name, $attribute, $value ) = @_;
    my $hash   = $defs{$name};
    my $prefix = "rgr_";
    return unless ($init_done);

    Log3 $name, 5, "RESIDENTS $name: called function RESIDENTS_Attr()";

    if ( $attribute eq "disable" ) {
        if ( $value and $value == 1 ) {
            $hash->{STATE} = "disabled";
            RESIDENTS_StopInternalTimers($hash);
        }
        elsif ( $cmd eq "del" or !$value ) {
            evalStateFormat($hash);
            RESIDENTS_StartInternalTimers( $hash, 1 );
        }
    }

    elsif ( $attribute eq $prefix . "noDuration" ) {
        if ($value) {
            delete $hash->{DURATIONTIMER} if ( $hash->{DURATIONTIMER} );
            RESIDENTStk_RemoveInternalTimer( "DurationTimer", $hash );
        }
        elsif ( !$value ) {
            RESIDENTS_DurationTimer($hash);
        }
    }

    elsif ( $attribute eq $prefix . "lang" ) {
        my $lang =
          $cmd eq "set" ? uc($value) : AttrVal( "global", "language", "EN" );

        # for initial define, ensure fallback to EN
        $lang = "EN"
          if ( $cmd eq "init" && $lang !~ /^EN|DE$/i );

        if ( $lang eq "DE" ) {
            $attr{$name}{alias} = "Bewohner"
              if ( !defined( $attr{$name}{alias} )
                || $attr{$name}{alias} eq "Residents" );
            $attr{$name}{group} = "Haus Status"
              if ( !defined( $attr{$name}{group} )
                || $attr{$name}{group} eq "Home State" );
            $attr{$name}{devStateIcon} =
'.*anwesend:status_available:absent .*abwesend:status_away_1:home .*verreist:status_standby:home .*keine:control_building_empty .*bettfertig:status_night:asleep .*schläft:status_night:awoken .*aufgestanden:status_available:home .*:user_unknown:home';
            $attr{$name}{eventMap} =
"home:anwesend absent:abwesend gone:verreist none:keine gotosleep:bettfertig asleep:schläft awoken:aufgestanden";
            $attr{$name}{widgetOverride} =
              "state:anwesend,bettfertig,abwesend,verreist";
        }
        elsif ( $lang eq "EN" ) {
            $attr{$name}{alias} = "Residents"
              if ( !defined( $attr{$name}{alias} )
                || $attr{$name}{alias} eq "Bewohner" );
            $attr{$name}{group} = "Home State"
              if ( !defined( $attr{$name}{group} )
                || $attr{$name}{group} eq "Haus Status" );
            $attr{$name}{devStateIcon} =
'.*home:status_available:absent .*absent:status_away_1:home .*gone:status_standby:home .*none:control_building_empty .*gotosleep:status_night:asleep .*asleep:status_night:awoken .*awoken:status_available:home .*:user_unknown:home';
            delete $attr{$name}{eventMap}
              if ( defined( $attr{$name}{eventMap} ) );
            delete $attr{$name}{widgetOverride}
              if ( defined( $attr{$name}{widgetOverride} ) );
        }
        else {
            return "Unsupported language $lang";
        }

        evalStateFormat($hash);
    }

    return if ( IsDisabled($name) );
    return;
}

###################################
sub RESIDENTS_Undefine($$) {
    my ( $hash, $name ) = @_;

    RESIDENTS_StopInternalTimers($hash);
    RESIDENTStk_findResidentSlaves($hash);

    # delete child roommates
    if ( defined( $hash->{ROOMMATES} )
        && $hash->{ROOMMATES} ne "" )
    {
        my @registeredRoommates =
          split( /,/, $hash->{ROOMMATES} );

        foreach my $child (@registeredRoommates) {
            fhem( "delete " . $child );
            Log3 $name, 3, "RESIDENTS $name: deleted device $child";
        }
    }

    # delete child guests
    if ( defined( $hash->{GUESTS} )
        && $hash->{GUESTS} ne "" )
    {
        my @registeredGuests =
          split( /,/, $hash->{GUESTS} );

        foreach my $child (@registeredGuests) {
            fhem( "delete " . $child );
            Log3 $name, 3, "RESIDENTS $name: deleted device $child";
        }
    }

    return undef;
}

###################################
sub RESIDENTS_Notify($$) {
    my ( $hash, $dev ) = @_;
    my $devName  = $dev->{NAME};
    my $hashName = $hash->{NAME};
    return unless ( $devName ne $hashName );    # only foreign events
    return if ( IsDisabled($hashName) or IsDisabled($devName) );
    return
      unless ( defined( $defs{$devName} )
        && defined( $defs{$devName}{TYPE} )
        && $defs{$devName}{TYPE} =~ /^(ROOMMATE|GUEST|dummy)$/i );

    my @registeredRoommates =
      split( /,/, $hash->{ROOMMATES} )
      if ( defined( $hash->{ROOMMATES} )
        && $hash->{ROOMMATES} ne "" );

    my @registeredGuests =
      split( /,/, $hash->{GUESTS} )
      if ( defined( $hash->{GUESTS} )
        && $hash->{GUESTS} ne "" );

    my @registeredWakeupdevs =
      split( /,/, $attr{$hashName}{rgr_wakeupDevice} )
      if ( defined( $attr{$hashName}{rgr_wakeupDevice} )
        && $attr{$hashName}{rgr_wakeupDevice} ne "" );

    # process only registered ROOMMATE or GUEST devices
    if ( ( @registeredRoommates && grep { /^$devName$/ } @registeredRoommates )
        || ( @registeredGuests && grep { /^$devName$/ } @registeredGuests ) )
    {

        return
          if ( !$dev->{CHANGED} );    # Some previous notify deleted the array.

        readingsBeginUpdate($hash);

        foreach my $change ( @{ $dev->{CHANGED} } ) {

            Log3 $hash, 5,
              "RESIDENTS " . $hashName . ": processing change $change";

            # state changed
            if (   $change !~ /:/
                || $change =~ /wayhome:/
                || $change =~ /wakeup:/ )
            {
                Log3 $hash, 4,
                    "RESIDENTS "
                  . $hashName . ": "
                  . $devName
                  . ": notify about change to $change";

                RESIDENTS_UpdateReadings($hash);
            }

            # activity
            if ( $change !~ /:/ ) {

                # get user realname
                my $realname =
                  AttrVal( $devName,
                    AttrVal( $devName, "rr_realname", "group" ), $devName );
                $realname =
                  AttrVal( $devName,
                    AttrVal( $devName, "rg_realname", "alias" ), $devName )
                  if ( $dev->{TYPE} eq "GUEST" );

                # update statistics
                readingsBulkUpdate( $hash, "lastActivity",
                    ReadingsVal( $devName, "state", $change ) );
                readingsBulkUpdate( $hash, "lastActivityBy",    $realname );
                readingsBulkUpdate( $hash, "lastActivityByDev", $devName );

            }

        }

        readingsEndUpdate( $hash, 1 );

        return;
    }

    # if we have registered wakeup devices
    if (@registeredWakeupdevs) {

        # if this is a notification of a registered wakeup device
        if ( grep { /^$devName$/ } @registeredWakeupdevs ) {

            # Some previous notify deleted the array.
            return
              if ( !$dev->{CHANGED} );

            foreach my $change ( @{ $dev->{CHANGED} } ) {
                RESIDENTStk_wakeupSet( $devName, $change );
            }

            return;
        }

        # process sub-child notifies: *_wakeupDevice
        foreach my $wakeupDev (@registeredWakeupdevs) {

            # if this is a notification of a registered sub dummy device
            # of one of our wakeup devices
            if (   defined( $attr{$wakeupDev}{wakeupResetSwitcher} )
                && $attr{$wakeupDev}{wakeupResetSwitcher} eq $devName
                && $defs{$devName}{TYPE} eq "dummy" )
            {

                # Some previous notify deleted the array.
                return
                  if ( !$dev->{CHANGED} );

                foreach my $change ( @{ $dev->{CHANGED} } ) {
                    RESIDENTStk_wakeupSet( $wakeupDev, $change )
                      if ( $change ne "off" );
                }

                last;
            }
        }
    }

    return;
}

###################################
sub RESIDENTS_Set($@) {
    my ( $hash, @a ) = @_;
    my $name      = $hash->{NAME};
    my $state     = ReadingsVal( $name, "state", "initialized" );
    my $roommates = ( $hash->{ROOMMATES} ? $hash->{ROOMMATES} : "" );
    my $guests    = ( $hash->{GUESTS} ? $hash->{GUESTS} : "" );

    return if ( IsDisabled($name) );

    Log3 $name, 5, "RESIDENTS $name: called function RESIDENTS_Set()";

    return "No Argument given" if ( !defined( $a[1] ) );

    # depending on current FHEMWEB instance's allowedCommands,
    # restrict set commands if there is "set-user" in it
    my $adminMode         = 1;
    my $FWallowedCommands = 0;
    $FWallowedCommands = AttrVal( $FW_wname, "allowedCommands", 0 )
      if ( defined($FW_wname) );
    if ( $FWallowedCommands && $FWallowedCommands =~ m/\bset-user\b/ ) {
        $adminMode = 0;
        return "Forbidden command: set " . $a[1]
          if ( lc( $a[1] ) eq "addroommate"
            || lc( $a[1] ) eq "addguest"
            || lc( $a[1] ) eq "removeroommate"
            || lc( $a[1] ) eq "removeguest"
            || lc( $a[1] ) eq "create" );
    }

    # states
    my $states = (
        defined( $attr{$name}{rgr_states} ) ? $attr{$name}{rgr_states}
        : (
            defined( $attr{$name}{rgr_showAllStates} )
              && $attr{$name}{rgr_showAllStates} == 1
            ? "home,gotosleep,asleep,awoken,absent,gone"
            : "home,gotosleep,absent,gone"
        )
    );
    $states = $state . "," . $states
      if ( $state ne "initialized" && $states !~ /$state/ );

    my $usage = "Unknown argument " . $a[1] . ", choose one of state:$states";
    if ($adminMode) {
        $usage .= " addRoommate addGuest";
        $usage .= " removeRoommate:" . $roommates if ( $roommates ne "" );
        $usage .= " removeGuest:" . $guests if ( $guests ne "" );
        $usage .= " create:wakeuptimer";
    }

    # states
    if (   $a[1] eq "state"
        || $a[1] eq "home"
        || $a[1] eq "gotosleep"
        || $a[1] eq "asleep"
        || $a[1] eq "awoken"
        || $a[1] eq "absent"
        || $a[1] eq "gone" )
    {
        my $newstate;
        my $presence = "absent";

        # if not direct
        if (
               $a[1] eq "state"
            && defined( $a[2] )
            && (   $a[2] eq "home"
                || $a[2] eq "gotosleep"
                || $a[2] eq "asleep"
                || $a[2] eq "awoken"
                || $a[2] eq "absent"
                || $a[2] eq "gone" )
          )
        {
            $newstate = $a[2];
        }
        elsif ( defined( $a[2] ) ) {
            return
"Invalid 2nd argument, choose one of home gotosleep asleep awoken absent gone ";
        }
        else {
            $newstate = $a[1];
        }

        Log3 $name, 2, "RESIDENTS set $name " . $newstate;

        # loop through every roommate
        if ( defined( $hash->{ROOMMATES} )
            && $hash->{ROOMMATES} ne "" )
        {
            my @registeredRoommates =
              split( /,/, $hash->{ROOMMATES} );

            foreach my $roommate (@registeredRoommates) {
                fhem "set $roommate silentSet state $newstate"
                  if ( ReadingsVal( $roommate, "state", "initialized" ) ne
                    $newstate );
            }
        }

        # loop through every guest
        if ( defined( $hash->{GUESTS} )
            && $hash->{GUESTS} ne "" )
        {
            $newstate = "none" if ( $newstate eq "gone" );

            my @registeredGuests =
              split( /,/, $hash->{GUESTS} );

            foreach my $guest (@registeredGuests) {
                fhem "set $guest silentSet state $newstate"
                  if ( ReadingsVal( $guest, "state", "initialized" ) ne
                    $newstate );
            }
        }
    }

    # addRoommate
    elsif ( lc( $a[1] ) eq "addroommate" ) {
        Log3 $name, 2, "RESIDENTS set $name " . $a[1] . " " . $a[2]
          if ( defined( $a[2] ) );

        my $rr_name;
        my $rr_name_attr;

        if ( $a[2] ne "" ) {
            $rr_name = "rr_" unless ( $a[2] =~ /^rr_/ );
            $rr_name .= $a[2];

            # define roommate
            fhem( "define " . $rr_name . " ROOMMATE " . $name )
              unless ( defined( $defs{$rr_name} ) );

            if ( defined( $defs{$rr_name} ) ) {
                return "Can't create, device $rr_name already existing."
                  unless ( $defs{$rr_name}{TYPE} eq "ROOMMATE" );

                my $lang =
                  $a[3]
                  ? uc( $a[3] )
                  : AttrVal( $rr_name, "rr_lang",
                    AttrVal( $name, "rgr_lang", undef ) );
                fhem( "attr " . $rr_name . " rr_lang " . $lang )
                  if ($lang);

                $attr{$rr_name}{comment} = "Auto-created by $name"
                  unless ( defined( $attr{$rr_name}{comment} )
                    && $attr{$rr_name}{comment} eq "Auto-created by $name" );

                fhem "set $rr_name silentSet state home";
                Log3 $name, 3, "RESIDENTS $name: created new device $rr_name";
            }
        }
        else {
            return "No Argument given, choose one of name ";
        }
    }

    # removeRoommate
    elsif ( lc( $a[1] ) eq "removeroommate" ) {
        Log3 $name, 2, "RESIDENTS set $name " . $a[1] . " " . $a[2]
          if ( defined( $a[2] ) );

        if ( $a[2] ne "" ) {
            my $rr_name = $a[2];

            # delete roommate
            if ( defined( $defs{$rr_name} ) ) {
                Log3 $name, 3, "RESIDENTS $name: deleted device $rr_name"
                  if fhem( "delete " . $rr_name );
            }
        }
        else {
            return "No Argument given, choose one of name ";
        }
    }

    # addGuest
    elsif ( lc( $a[1] ) eq "addguest" ) {
        Log3 $name, 2, "RESIDENTS set $name " . $a[1] . " " . $a[2]
          if ( defined( $a[2] ) );

        my $rg_name;
        my $rg_name_attr;

        if ( $a[2] ne "" ) {
            $rg_name = "rg_" unless ( $a[2] =~ /^rg_/ );
            $rg_name .= $a[2];

            # define guest
            fhem( "define " . $rg_name . " GUEST " . $name )
              unless ( defined( $defs{$rg_name} ) );

            if ( defined( $defs{$rg_name} ) ) {
                return "Can't create, device $rg_name already existing."
                  unless ( $defs{$rg_name}{TYPE} eq "GUEST" );

                my $lang =
                  $a[3]
                  ? uc( $a[3] )
                  : AttrVal( $rg_name, "rg_lang",
                    AttrVal( $name, "rgr_lang", undef ) );
                fhem( "attr " . $rg_name . " rg_lang " . $lang )
                  if ($lang);

                $attr{$rg_name}{comment} = "Auto-created by $name"
                  unless ( defined( $attr{$rg_name}{comment} )
                    && $attr{$rg_name}{comment} eq "Auto-created by $name" );

                fhem "set $rg_name silentSet state home";
                Log3 $name, 3, "RESIDENTS $name: created new device $rg_name";
            }
        }
        else {
            return "No Argument given, choose one of name ";
        }
    }

    # removeGuest
    elsif ( lc( $a[1] ) eq "removeguest" ) {
        Log3 $name, 2, "RESIDENTS set $name " . $a[1] . " " . $a[2]
          if ( defined( $a[2] ) );

        if ( $a[2] ne "" ) {
            my $rg_name = $a[2];

            # delete guest
            if ( defined( $defs{$rg_name} ) ) {
                Log3 $name, 3, "RESIDENTS $name: deleted device $rg_name"
                  if fhem( "delete " . $rg_name );
            }
        }
        else {
            return "No Argument given, choose one of name ";
        }
    }

    # create
    elsif ( $a[1] eq "create" ) {
        if ( defined( $a[2] ) && $a[2] eq "wakeuptimer" ) {
            my $i               = "1";
            my $wakeuptimerName = $name . "_wakeuptimer" . $i;
            my $created         = 0;

            until ($created) {
                if ( defined( $defs{$wakeuptimerName} ) ) {
                    $i++;
                    $wakeuptimerName = $name . "_wakeuptimer" . $i;
                }
                else {
                    my $sortby = AttrVal( $name, "sortby", -1 );
                    $sortby++;

                    # create new dummy device
                    fhem "define $wakeuptimerName dummy";
                    fhem "attr $wakeuptimerName alias Wake-up Timer $i";
                    fhem
"attr $wakeuptimerName comment Auto-created by RESIDENTS module for use with RESIDENTS Toolkit";
                    fhem
"attr $wakeuptimerName devStateIcon OFF:general_aus\@red:reset running:general_an\@green:stop .*:general_an\@orange:nextRun%20OFF";
                    fhem "attr $wakeuptimerName group " . $attr{$name}{group}
                      if ( defined( $attr{$name}{group} ) );
                    fhem "attr $wakeuptimerName icon time_timer";
                    fhem "attr $wakeuptimerName room " . $attr{$name}{room}
                      if ( defined( $attr{$name}{room} ) );
                    fhem
"attr $wakeuptimerName setList nextRun:OFF,00:00,00:15,00:30,00:45,01:00,01:15,01:30,01:45,02:00,02:15,02:30,02:45,03:00,03:15,03:30,03:45,04:00,04:15,04:30,04:45,05:00,05:15,05:30,05:45,06:00,06:15,06:30,06:45,07:00,07:15,07:30,07:45,08:00,08:15,08:30,08:45,09:00,09:15,09:30,09:45,10:00,10:15,10:30,10:45,11:00,11:15,11:30,11:45,12:00,12:15,12:30,12:45,13:00,13:15,13:30,13:45,14:00,14:15,14:30,14:45,15:00,15:15,15:30,15:45,16:00,16:15,16:30,16:45,17:00,17:15,17:30,17:45,18:00,18:15,18:30,18:45,19:00,19:15,19:30,19:45,20:00,20:15,20:30,20:45,21:00,21:15,21:30,21:45,22:00,22:15,22:30,22:45,23:00,23:15,23:30,23:45 reset:noArg trigger:noArg start:noArg stop:noArg end:noArg";
                    fhem "attr $wakeuptimerName userattr wakeupUserdevice";
                    fhem "attr $wakeuptimerName sortby " . $sortby
                      if ($sortby);
                    fhem "attr $wakeuptimerName wakeupUserdevice $name";
                    fhem "attr $wakeuptimerName webCmd nextRun";

                    # register slave device
                    my $wakeupDevice = AttrVal( $name, "rgr_wakeupDevice", 0 );
                    if ( !$wakeupDevice ) {
                        fhem "attr $name rgr_wakeupDevice $wakeuptimerName";
                    }
                    elsif ( $wakeupDevice !~ /(.*,?)($wakeuptimerName)(.*,?)/ )
                    {
                        fhem "attr $name rgr_wakeupDevice "
                          . $wakeupDevice
                          . ",$wakeuptimerName";
                    }

                    # trigger first update
                    fhem "set $wakeuptimerName nextRun OFF";

                    $created = 1;
                }
            }

            return
"Dummy $wakeuptimerName and other pending devices created and pre-configured.\nYou may edit Macro_$wakeuptimerName to define your wake-up actions\nand at_$wakeuptimerName for optional at-device adjustments.";
        }
        else {
            return "Invalid 2nd argument, choose one of wakeuptimer ";
        }
    }

    # return usage hint
    else {
        return $usage;
    }

    return undef;
}

############################################################################################################
#
#   Begin of helper functions
#
############################################################################################################

sub RESIDENTS_UpdateReadings (@) {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $state    = ReadingsVal( $name, "state",    "none" );
    my $presence = ReadingsVal( $name, "presence", "absent" );

    my $state_home                          = 0;
    my $state_gotosleep                     = 0;
    my $state_asleep                        = 0;
    my $state_awoken                        = 0;
    my $state_absent                        = 0;
    my $state_gone                          = 0;
    my $state_total                         = 0;
    my $state_totalPresent                  = 0;
    my $state_totalAbsent                   = 0;
    my $state_totalGuests                   = 0;
    my $state_totalGuestsPresent            = 0;
    my $state_totalGuestsAbsent             = 0;
    my $state_totalRoommates                = 0;
    my $state_totalRoommatesPresent         = 0;
    my $state_totalRoommatesAbsent          = 0;
    my $state_guestDev                      = 0;
    my $residentsDevs_home                  = "-";
    my $residentsDevs_absent                = "-";
    my $residentsDevs_asleep                = "-";
    my $residentsDevs_awoken                = "-";
    my $residentsDevs_gone                  = "-";
    my $residentsDevs_gotosleep             = "-";
    my $residentsDevs_wakeup                = "-";
    my $residentsDevs_wayhome               = "-";
    my $residentsDevs_wayhomeDelayed        = "-";
    my $residentsDevs_totalAbsent           = "-";
    my $residentsDevs_totalPresent          = "-";
    my $residentsDevs_totalAbsentGuest      = "-";
    my $residentsDevs_totalPresentGuest     = "-";
    my $residentsDevs_totalAbsentRoommates  = "-";
    my $residentsDevs_totalPresentRoommates = "-";
    my $residents_home                      = "-";
    my $residents_absent                    = "-";
    my $residents_asleep                    = "-";
    my $residents_awoken                    = "-";
    my $residents_gone                      = "-";
    my $residents_gotosleep                 = "-";
    my $residents_wakeup                    = "-";
    my $residents_wayhome                   = "-";
    my $residents_wayhomeDelayed            = "-";
    my $residents_totalAbsent               = "-";
    my $residents_totalPresent              = "-";
    my $residents_totalAbsentGuest          = "-";
    my $residents_totalPresentGuest         = "-";
    my $residents_totalAbsentRoommates      = "-";
    my $residents_totalPresentRoommates     = "-";
    my $wayhome                             = 0;
    my $wayhomeDelayed                      = 0;
    my $wakeup                              = 0;
    my $newstate;

    my @registeredRoommates =
      split( /,/, $hash->{ROOMMATES} )
      if ( defined( $hash->{ROOMMATES} )
        && $hash->{ROOMMATES} ne "" );

    my @registeredGuests =
      split( /,/, $hash->{GUESTS} )
      if ( defined( $hash->{GUESTS} )
        && $hash->{GUESTS} ne "" );

    # count child states for ROOMMATE devices
    foreach my $roommate (@registeredRoommates) {
        $state_total++;
        $state_totalRoommates++;

        my $roommateName =
          AttrVal( $roommate,
            AttrVal( $roommate, "rr_realname", "group" ), "" );

        Log3 $name, 5,
          "RESIDENTS $name: considering $roommate for state change";

        if ( ReadingsVal( $roommate, "state", "initialized" ) eq "home" ) {
            $state_home++;
            $residentsDevs_home .= "," . $roommate
              if ( $residentsDevs_home ne "-" );
            $residentsDevs_home = $roommate
              if ( $residentsDevs_home eq "-" );
            $residents_home .= ", " . $roommateName
              if ( $roommateName ne "" && $residents_home ne "-" );
            $residents_home = $roommateName
              if ( $roommateName ne "" && $residents_home eq "-" );

            $state_totalPresent++;
            $state_totalRoommatesPresent++;
            $residentsDevs_totalPresent .= "," . $roommate
              if ( $residentsDevs_totalPresent ne "-" );
            $residentsDevs_totalPresent = $roommate
              if ( $residentsDevs_totalPresent eq "-" );
            $residentsDevs_totalPresentRoommates .= "," . $roommate
              if ( $residentsDevs_totalPresentRoommates ne "-" );
            $residentsDevs_totalPresentRoommates = $roommate
              if ( $residentsDevs_totalPresentRoommates eq "-" );
            $residents_totalPresent .= ", " . $roommateName
              if ( $roommateName ne "" && $residents_totalPresent ne "-" );
            $residents_totalPresent = $roommateName
              if ( $roommateName ne "" && $residents_totalPresent eq "-" );
            $residents_totalPresentRoommates .= ", " . $roommateName
              if ( $roommateName ne ""
                && $residents_totalPresentRoommates ne "-" );
            $residents_totalPresentRoommates = $roommateName
              if ( $roommateName ne ""
                && $residents_totalPresentRoommates eq "-" );
        }

        elsif (
            ReadingsVal( $roommate, "state", "initialized" ) eq "gotosleep" )
        {
            $state_gotosleep++;
            $residentsDevs_gotosleep .= "," . $roommate
              if ( $residentsDevs_gotosleep ne "-" );
            $residentsDevs_gotosleep = $roommate
              if ( $residentsDevs_gotosleep eq "-" );
            $residents_gotosleep .= ", " . $roommateName
              if ( $roommateName ne "" && $residents_gotosleep ne "-" );
            $residents_gotosleep = $roommateName
              if ( $roommateName ne "" && $residents_gotosleep eq "-" );

            $state_totalPresent++;
            $state_totalRoommatesPresent++;
            $residentsDevs_totalPresent .= "," . $roommate
              if ( $residentsDevs_totalPresent ne "-" );
            $residentsDevs_totalPresent = $roommate
              if ( $residentsDevs_totalPresent eq "-" );
            $residentsDevs_totalPresentRoommates .= "," . $roommate
              if ( $residentsDevs_totalPresentRoommates ne "-" );
            $residentsDevs_totalPresentRoommates = $roommate
              if ( $residentsDevs_totalPresentRoommates eq "-" );
            $residents_totalPresent .= ", " . $roommateName
              if ( $roommateName ne "" && $residents_totalPresent ne "-" );
            $residents_totalPresent = $roommateName
              if ( $roommateName ne "" && $residents_totalPresent eq "-" );
            $residents_totalPresentRoommates .= ", " . $roommateName
              if ( $roommateName ne ""
                && $residents_totalPresentRoommates ne "-" );
            $residents_totalPresentRoommates = $roommateName
              if ( $roommateName ne ""
                && $residents_totalPresentRoommates eq "-" );
        }

        elsif ( ReadingsVal( $roommate, "state", "initialized" ) eq "asleep" ) {
            $state_asleep++;
            $residentsDevs_asleep .= "," . $roommate
              if ( $residentsDevs_asleep ne "-" );
            $residentsDevs_asleep = $roommate
              if ( $residentsDevs_asleep eq "-" );
            $residents_asleep .= ", " . $roommateName
              if ( $roommateName ne "" && $residents_asleep ne "-" );
            $residents_asleep = $roommateName
              if ( $roommateName ne "" && $residents_asleep eq "-" );

            $state_totalPresent++;
            $state_totalRoommatesPresent++;
            $residentsDevs_totalPresent .= "," . $roommate
              if ( $residentsDevs_totalPresent ne "-" );
            $residentsDevs_totalPresent = $roommate
              if ( $residentsDevs_totalPresent eq "-" );
            $residentsDevs_totalPresentRoommates .= "," . $roommate
              if ( $residentsDevs_totalPresentRoommates ne "-" );
            $residentsDevs_totalPresentRoommates = $roommate
              if ( $residentsDevs_totalPresentRoommates eq "-" );
            $residents_totalPresent .= ", " . $roommateName
              if ( $roommateName ne "" && $residents_totalPresent ne "-" );
            $residents_totalPresent = $roommateName
              if ( $roommateName ne "" && $residents_totalPresent eq "-" );
            $residents_totalPresentRoommates .= ", " . $roommateName
              if ( $roommateName ne ""
                && $residents_totalPresentRoommates ne "-" );
            $residents_totalPresentRoommates = $roommateName
              if ( $roommateName ne ""
                && $residents_totalPresentRoommates eq "-" );
        }

        elsif ( ReadingsVal( $roommate, "state", "initialized" ) eq "awoken" ) {
            $state_awoken++;
            $residentsDevs_awoken .= "," . $roommate
              if ( $residentsDevs_awoken ne "-" );
            $residentsDevs_awoken = $roommate
              if ( $residentsDevs_awoken eq "-" );
            $residents_awoken .= ", " . $roommateName
              if ( $roommateName ne "" && $residents_awoken ne "-" );
            $residents_awoken = $roommateName
              if ( $roommateName ne "" && $residents_awoken eq "-" );

            $state_totalPresent++;
            $state_totalRoommatesPresent++;
            $residentsDevs_totalPresent .= "," . $roommate
              if ( $residentsDevs_totalPresent ne "-" );
            $residentsDevs_totalPresent = $roommate
              if ( $residentsDevs_totalPresent eq "-" );
            $residentsDevs_totalPresentRoommates .= "," . $roommate
              if ( $residentsDevs_totalPresentRoommates ne "-" );
            $residentsDevs_totalPresentRoommates = $roommate
              if ( $residentsDevs_totalPresentRoommates eq "-" );
            $residents_totalPresent .= ", " . $roommateName
              if ( $roommateName ne "" && $residents_totalPresent ne "-" );
            $residents_totalPresent = $roommateName
              if ( $roommateName ne "" && $residents_totalPresent eq "-" );
            $residents_totalPresentRoommates .= ", " . $roommateName
              if ( $roommateName ne ""
                && $residents_totalPresentRoommates ne "-" );
            $residents_totalPresentRoommates = $roommateName
              if ( $roommateName ne ""
                && $residents_totalPresentRoommates eq "-" );
        }

        elsif ( ReadingsVal( $roommate, "state", "initialized" ) eq "absent" ) {
            $state_absent++;
            $residentsDevs_absent .= "," . $roommate
              if ( $residentsDevs_absent ne "-" );
            $residentsDevs_absent = $roommate
              if ( $residentsDevs_absent eq "-" );
            $residents_absent .= ", " . $roommateName
              if ( $roommateName ne "" && $residents_absent ne "-" );
            $residents_absent = $roommateName
              if ( $roommateName ne "" && $residents_absent eq "-" );

            $state_totalAbsent++;
            $state_totalRoommatesAbsent++;
            $residentsDevs_totalAbsent .= "," . $roommate
              if ( $residentsDevs_totalAbsent ne "-" );
            $residentsDevs_totalAbsent = $roommate
              if ( $residentsDevs_totalAbsent eq "-" );
            $residentsDevs_totalAbsentRoommates .= "," . $roommate
              if ( $residentsDevs_totalAbsentRoommates ne "-" );
            $residentsDevs_totalAbsentRoommates = $roommate
              if ( $residentsDevs_totalAbsentRoommates eq "-" );
            $residents_totalAbsent .= ", " . $roommateName
              if ( $roommateName ne "" && $residents_totalAbsent ne "-" );
            $residents_totalAbsent = $roommateName
              if ( $roommateName ne "" && $residents_totalAbsent eq "-" );
            $residents_totalAbsentRoommates .= ", " . $roommateName
              if ( $roommateName ne ""
                && $residents_totalAbsentRoommates ne "-" );
            $residents_totalAbsentRoommates = $roommateName
              if ( $roommateName ne ""
                && $residents_totalAbsentRoommates eq "-" );
        }

        elsif ( ReadingsVal( $roommate, "state", "initialized" ) eq "gone" ) {
            $state_gone++;
            $residentsDevs_gone .= "," . $roommate
              if ( $residentsDevs_gone ne "-" );
            $residentsDevs_gone = $roommate
              if ( $residentsDevs_gone eq "-" );
            $residents_gone .= ", " . $roommateName
              if ( $roommateName ne "" && $residents_gone ne "-" );
            $residents_gone = $roommateName
              if ( $roommateName ne "" && $residents_gone eq "-" );

            $state_totalAbsent++;
            $state_totalRoommatesAbsent++;
            $residentsDevs_totalAbsent .= "," . $roommate
              if ( $residentsDevs_totalAbsent ne "-" );
            $residentsDevs_totalAbsent = $roommate
              if ( $residentsDevs_totalAbsent eq "-" );
            $residentsDevs_totalAbsentRoommates .= "," . $roommate
              if ( $residentsDevs_totalAbsentRoommates ne "-" );
            $residentsDevs_totalAbsentRoommates = $roommate
              if ( $residentsDevs_totalAbsentRoommates eq "-" );
            $residents_totalAbsent .= ", " . $roommateName
              if ( $roommateName ne "" && $residents_totalAbsent ne "-" );
            $residents_totalAbsent = $roommateName
              if ( $roommateName ne "" && $residents_totalAbsent eq "-" );
            $residents_totalAbsentRoommates .= ", " . $roommateName
              if ( $roommateName ne ""
                && $residents_totalAbsentRoommates ne "-" );
            $residents_totalAbsentRoommates = $roommateName
              if ( $roommateName ne ""
                && $residents_totalAbsentRoommates eq "-" );
        }

        if ( ReadingsVal( $roommate, "wakeup", "0" ) > 0 ) {
            $wakeup++;
            $residentsDevs_wakeup .= "," . $roommate
              if ( $residentsDevs_wakeup ne "-" );
            $residentsDevs_wakeup = $roommate
              if ( $residentsDevs_wakeup eq "-" );
            $residents_wakeup .= ", " . $roommateName
              if ( $roommateName ne "" && $residents_wakeup ne "-" );
            $residents_wakeup = $roommateName
              if ( $roommateName ne "" && $residents_wakeup eq "-" );
        }

        if ( ReadingsVal( $roommate, "wayhome", "0" ) > 0 ) {
            $wayhome++;
            $residentsDevs_wayhome .= "," . $roommate
              if ( $residentsDevs_wayhome ne "-" );
            $residentsDevs_wayhome = $roommate
              if ( $residentsDevs_wayhome eq "-" );
            $residents_wayhome .= ", " . $roommateName
              if ( $roommateName ne "" && $residents_wayhome ne "-" );
            $residents_wayhome = $roommateName
              if ( $roommateName ne "" && $residents_wayhome eq "-" );

            if ( ReadingsVal( $roommate, "wayhome", "0" ) == 2 ) {
                $wayhomeDelayed++;

                $residentsDevs_wayhomeDelayed .= "," . $roommate
                  if ( $residentsDevs_wayhomeDelayed ne "-" );
                $residentsDevs_wayhomeDelayed = $roommate
                  if ( $residentsDevs_wayhomeDelayed eq "-" );
                $residents_wayhomeDelayed .= ", " . $roommateName
                  if ( $roommateName ne ""
                    && $residents_wayhomeDelayed ne "-" );
                $residents_wayhomeDelayed = $roommateName
                  if ( $roommateName ne ""
                    && $residents_wayhomeDelayed eq "-" );
            }
        }
    }

    # count child states for GUEST devices
    foreach my $guest (@registeredGuests) {
        $state_guestDev++;

        my $guestName =
          AttrVal( $guest, AttrVal( $guest, "rg_realname", "alias" ), "" );

        Log3 $name, 5, "RESIDENTS $name: considering $guest for state change";

        if ( ReadingsVal( $guest, "state", "initialized" ) eq "home" ) {
            $state_home++;
            $state_totalPresent++;
            $state_totalGuestsPresent++;
            $state_totalGuests++;
            $state_total++;

            $residentsDevs_totalPresentGuest .= "," . $guest
              if ( $residentsDevs_totalPresentGuest ne "-" );
            $residentsDevs_totalPresentGuest = $guest
              if ( $residentsDevs_totalPresentGuest eq "-" );
            $residents_totalPresentGuest .= ", " . $guestName
              if ( $guestName ne ""
                && $residents_totalPresentGuest ne "-" );
            $residents_totalPresentGuest = $guestName
              if ( $guestName ne ""
                && $residents_totalPresentGuest eq "-" );

            $residentsDevs_totalPresent .= "," . $guest
              if ( $residentsDevs_totalPresent ne "-" );
            $residentsDevs_totalPresent = $guest
              if ( $residentsDevs_totalPresent eq "-" );
            $residents_totalPresent .= ", " . $guestName
              if ( $guestName ne ""
                && $residents_totalPresent ne "-" );
            $residents_totalPresent = $guestName
              if ( $guestName ne ""
                && $residents_totalPresent eq "-" );
        }

        elsif ( ReadingsVal( $guest, "state", "initialized" ) eq "gotosleep" ) {
            $state_gotosleep++;
            $state_totalPresent++;
            $state_totalGuestsPresent++;
            $state_totalGuests++;
            $state_total++;

            $residentsDevs_totalPresentGuest .= "," . $guest
              if ( $residentsDevs_totalPresentGuest ne "-" );
            $residentsDevs_totalPresentGuest = $guest
              if ( $residentsDevs_totalPresentGuest eq "-" );
            $residents_totalPresentGuest .= ", " . $guestName
              if ( $guestName ne ""
                && $residents_totalPresentGuest ne "-" );
            $residents_totalPresentGuest = $guestName
              if ( $guestName ne ""
                && $residents_totalPresentGuest eq "-" );

            $residentsDevs_totalPresent .= "," . $guest
              if ( $residentsDevs_totalPresent ne "-" );
            $residentsDevs_totalPresent = $guest
              if ( $residentsDevs_totalPresent eq "-" );
            $residents_totalPresent .= ", " . $guestName
              if ( $guestName ne ""
                && $residents_totalPresent ne "-" );
            $residents_totalPresent = $guestName
              if ( $guestName ne ""
                && $residents_totalPresent eq "-" );
        }

        elsif ( ReadingsVal( $guest, "state", "initialized" ) eq "asleep" ) {
            $state_asleep++;
            $state_totalPresent++;
            $state_totalGuestsPresent++;
            $state_totalGuests++;
            $state_total++;

            $residentsDevs_totalPresentGuest .= "," . $guest
              if ( $residentsDevs_totalPresentGuest ne "-" );
            $residentsDevs_totalPresentGuest = $guest
              if ( $residentsDevs_totalPresentGuest eq "-" );
            $residents_totalPresentGuest .= ", " . $guestName
              if ( $guestName ne ""
                && $residents_totalPresentGuest ne "-" );
            $residents_totalPresentGuest = $guestName
              if ( $guestName ne ""
                && $residents_totalPresentGuest eq "-" );

            $residentsDevs_totalPresent .= "," . $guest
              if ( $residentsDevs_totalPresent ne "-" );
            $residentsDevs_totalPresent = $guest
              if ( $residentsDevs_totalPresent eq "-" );
            $residents_totalPresent .= ", " . $guestName
              if ( $guestName ne ""
                && $residents_totalPresent ne "-" );
            $residents_totalPresent = $guestName
              if ( $guestName ne ""
                && $residents_totalPresent eq "-" );
        }

        elsif ( ReadingsVal( $guest, "state", "initialized" ) eq "awoken" ) {
            $state_awoken++;
            $state_totalPresent++;
            $state_totalGuestsPresent++;
            $state_totalGuests++;
            $state_total++;

            $residentsDevs_totalPresentGuest .= "," . $guest
              if ( $residentsDevs_totalPresentGuest ne "-" );
            $residentsDevs_totalPresentGuest = $guest
              if ( $residentsDevs_totalPresentGuest eq "-" );
            $residents_totalPresentGuest .= ", " . $guestName
              if ( $guestName ne ""
                && $residents_totalPresentGuest ne "-" );
            $residents_totalPresentGuest = $guestName
              if ( $guestName ne ""
                && $residents_totalPresentGuest eq "-" );

            $residentsDevs_totalPresent .= "," . $guest
              if ( $residentsDevs_totalPresent ne "-" );
            $residentsDevs_totalPresent = $guest
              if ( $residentsDevs_totalPresent eq "-" );
            $residents_totalPresent .= ", " . $guestName
              if ( $guestName ne ""
                && $residents_totalPresent ne "-" );
            $residents_totalPresent = $guestName
              if ( $guestName ne ""
                && $residents_totalPresent eq "-" );
        }

        elsif ( ReadingsVal( $guest, "state", "initialized" ) eq "absent" ) {
            $state_absent++;
            $state_totalAbsent++;
            $state_totalGuestsAbsent++;
            $state_totalGuests++;
            $state_total++;

            $residentsDevs_totalAbsentGuest .= "," . $guest
              if ( $residentsDevs_totalAbsentGuest ne "-" );
            $residentsDevs_totalAbsentGuest = $guest
              if ( $residentsDevs_totalAbsentGuest eq "-" );
            $residents_totalAbsentGuest .= ", " . $guestName
              if ( $guestName ne ""
                && $residents_totalAbsentGuest ne "-" );
            $residents_totalAbsentGuest = $guestName
              if ( $guestName ne ""
                && $residents_totalAbsentGuest eq "-" );

            $residentsDevs_totalAbsent .= "," . $guest
              if ( $residentsDevs_totalAbsent ne "-" );
            $residentsDevs_totalAbsent = $guest
              if ( $residentsDevs_totalAbsent eq "-" );
            $residents_totalAbsent .= ", " . $guestName
              if ( $guestName ne ""
                && $residents_totalAbsent ne "-" );
            $residents_totalAbsent = $guestName
              if ( $guestName ne ""
                && $residents_totalAbsent eq "-" );
        }

        if ( ReadingsVal( $guest, "wakeup", "0" ) > 0 ) {
            $wakeup++;
            $residentsDevs_wakeup .= "," . $guest
              if ( $residentsDevs_wakeup ne "-" );
            $residentsDevs_wakeup = $guest
              if ( $residentsDevs_wakeup eq "-" );
            $residents_wakeup .= ", " . $guestName
              if ( $guestName ne "" && $residents_wakeup ne "-" );
            $residents_wakeup = $guestName
              if ( $guestName ne "" && $residents_wakeup eq "-" );
        }

        if ( ReadingsVal( $guest, "wayhome", "0" ) > 0 ) {
            $wayhome++;
            $residents_wayhome .= "," . $guest
              if ( $residents_wayhome ne "-" );
            $residents_wayhome = $guest if ( $residents_wayhome eq "-" );
            $residents_wayhome .= ", " . $guestName
              if ( $guestName ne "" && $residents_wayhome ne "-" );
            $residents_wayhome = $guestName
              if ( $guestName ne "" && $residents_wayhome eq "-" );

            if ( ReadingsVal( $guest, "wayhome", "0" ) == 2 ) {
                $wayhomeDelayed++;

                $residentsDevs_wayhomeDelayed .= "," . $guest
                  if ( $residentsDevs_wayhomeDelayed ne "-" );
                $residentsDevs_wayhomeDelayed = $guest
                  if ( $residentsDevs_wayhomeDelayed eq "-" );
                $residents_wayhomeDelayed .= ", " . $guestName
                  if ( $guestName ne ""
                    && $residents_wayhomeDelayed ne "-" );
                $residents_wayhomeDelayed = $guestName
                  if ( $guestName ne ""
                    && $residents_wayhomeDelayed eq "-" );
            }
        }
    }

    # update counter
    readingsBulkUpdateIfChanged( $hash, "residentsTotal", $state_total );

    readingsBulkUpdateIfChanged( $hash, "residentsTotalGuests",
        $state_totalGuests );

    readingsBulkUpdateIfChanged( $hash, "residentsTotalGuestsPresent",
        $state_totalGuestsPresent );

    readingsBulkUpdateIfChanged(
        $hash,
        "residentsTotalGuestsPresentDevs",
        $residentsDevs_totalPresentGuest
    );

    readingsBulkUpdateIfChanged( $hash, "residentsTotalGuestsPresentNames",
        $residents_totalPresentGuest );

    readingsBulkUpdateIfChanged( $hash, "residentsTotalGuestsAbsent",
        $state_totalGuestsAbsent );

    readingsBulkUpdateIfChanged(
        $hash,
        "residentsTotalGuestsAbsentDevs",
        $residentsDevs_totalAbsentGuest
    );

    readingsBulkUpdateIfChanged( $hash, "residentsTotalGuestsAbsentNames",
        $residents_totalAbsentGuest );

    readingsBulkUpdateIfChanged( $hash, "residentsTotalRoommates",
        $state_totalRoommates );

    readingsBulkUpdateIfChanged( $hash, "residentsTotalRoommatesPresent",
        $state_totalRoommatesPresent );

    readingsBulkUpdateIfChanged(
        $hash,
        "residentsTotalRoommatesPresentDevs",
        $residentsDevs_totalPresentRoommates
    );

    readingsBulkUpdateIfChanged(
        $hash,
        "residentsTotalRoommatesPresentNames",
        $residents_totalPresentRoommates
    );

    readingsBulkUpdateIfChanged( $hash, "residentsTotalRoommatesAbsent",
        $state_totalRoommatesAbsent );

    readingsBulkUpdateIfChanged(
        $hash,
        "residentsTotalRoommatesAbsentDevs",
        $residentsDevs_totalAbsentRoommates
    );

    readingsBulkUpdateIfChanged(
        $hash,
        "residentsTotalRoommatesAbsentNames",
        $residents_totalAbsentRoommates
    );

    readingsBulkUpdateIfChanged( $hash, "residentsTotalPresent",
        $state_totalPresent );

    readingsBulkUpdateIfChanged( $hash, "residentsTotalPresentDevs",
        $residentsDevs_totalPresent );

    readingsBulkUpdateIfChanged( $hash, "residentsTotalPresentNames",
        $residents_totalPresent );

    readingsBulkUpdateIfChanged( $hash, "residentsTotalAbsent",
        $state_totalAbsent );

    readingsBulkUpdateIfChanged( $hash, "residentsTotalAbsentDevs",
        $residentsDevs_totalAbsent );

    readingsBulkUpdateIfChanged( $hash, "residentsTotalAbsentNames",
        $residents_totalAbsent );

    readingsBulkUpdateIfChanged( $hash, "residentsHome", $state_home );

    readingsBulkUpdateIfChanged( $hash, "residentsHomeDevs",
        $residentsDevs_home );

    readingsBulkUpdateIfChanged( $hash, "residentsHomeNames", $residents_home );

    readingsBulkUpdateIfChanged( $hash, "residentsGotosleep",
        $state_gotosleep );

    readingsBulkUpdateIfChanged( $hash, "residentsGotosleepDevs",
        $residentsDevs_gotosleep );

    readingsBulkUpdateIfChanged( $hash, "residentsGotosleepNames",
        $residents_gotosleep );

    readingsBulkUpdateIfChanged( $hash, "residentsAsleep", $state_asleep );

    readingsBulkUpdateIfChanged( $hash, "residentsAsleepDevs",
        $residentsDevs_asleep );

    readingsBulkUpdateIfChanged( $hash, "residentsAsleepNames",
        $residents_asleep );

    readingsBulkUpdateIfChanged( $hash, "residentsAwoken", $state_awoken );
    readingsBulkUpdateIfChanged( $hash, "residentsAwokenDevs",
        $residentsDevs_awoken );

    readingsBulkUpdateIfChanged( $hash, "residentsAwokenNames",
        $residents_awoken );

    readingsBulkUpdateIfChanged( $hash, "residentsAbsent", $state_absent );
    readingsBulkUpdateIfChanged( $hash, "residentsAbsentDevs",
        $residentsDevs_absent );

    readingsBulkUpdateIfChanged( $hash, "residentsAbsentNames",
        $residents_absent );

    readingsBulkUpdateIfChanged( $hash, "residentsGone", $state_gone );

    readingsBulkUpdateIfChanged( $hash, "residentsGoneDevs",
        $residentsDevs_gone );

    readingsBulkUpdateIfChanged( $hash, "residentsGoneNames", $residents_gone );

    readingsBulkUpdateIfChanged( $hash, "residentsTotalWakeup", $wakeup );

    readingsBulkUpdateIfChanged( $hash, "residentsTotalWakeupDevs",
        $residentsDevs_wakeup );

    readingsBulkUpdateIfChanged( $hash, "residentsTotalWakeupNames",
        $residents_wakeup );

    readingsBulkUpdateIfChanged( $hash, "residentsTotalWayhome", $wayhome );

    readingsBulkUpdateIfChanged( $hash, "residentsTotalWayhomeDevs",
        $residentsDevs_wayhome );

    readingsBulkUpdateIfChanged( $hash, "residentsTotalWayhomeNames",
        $residents_wayhome );

    readingsBulkUpdateIfChanged( $hash, "residentsTotalWayhomeDelayed",
        $wayhomeDelayed );

    readingsBulkUpdateIfChanged( $hash, "residentsTotalWayhomeDelayedDevs",
        $residentsDevs_wayhomeDelayed );

    readingsBulkUpdateIfChanged( $hash, "residentsTotalWayhomeDelayedNames",
        $residents_wayhomeDelayed );

    #
    # state calculation
    #

    # gotosleep
    if (   $state_home == 0
        && $state_gotosleep > 0
        && $state_asleep >= 0
        && $state_awoken == 0 )
    {
        $newstate = "gotosleep";
    }

    # asleep
    elsif ($state_home == 0
        && $state_gotosleep == 0
        && $state_asleep > 0
        && $state_awoken == 0 )
    {
        $newstate = "asleep";
    }

    # awoken
    elsif ($state_home == 0
        && $state_gotosleep >= 0
        && $state_asleep >= 0
        && $state_awoken > 0 )
    {
        $newstate = "awoken";
    }

    # general presence
    elsif ($state_home > 0
        || $state_gotosleep > 0
        || $state_asleep > 0
        || $state_awoken > 0 )
    {
        $newstate = "home";
    }

    # absent
    elsif ($state_absent > 0
        && $state_home == 0
        && $state_gotosleep == 0
        && $state_asleep == 0
        && $state_awoken == 0 )
    {
        $newstate = "absent";
    }

    # gone
    elsif ($state_gone > 0
        && $state_absent == 0
        && $state_home == 0
        && $state_gotosleep == 0
        && $state_asleep == 0
        && $state_awoken == 0 )
    {
        $newstate = "gone";
    }

    # none
    elsif ($state_totalGuests == 0
        && $state_totalRoommates == 0
        && $state_gone == 0
        && $state_absent == 0
        && $state_home == 0
        && $state_gotosleep == 0
        && $state_asleep == 0
        && $state_awoken == 0 )
    {
        $newstate = "none";
    }

    # unspecified; this should not happen
    else {
        $newstate = "unspecified";
    }

    # calculate presence state
    my $newpresence =
      ( $newstate ne "none" && $newstate ne "gone" && $newstate ne "absent" )
      ? "present"
      : "absent";

    Log3 $name, 4,
"RESIDENTS $name: calculation result - residentsTotal:$state_total residentsTotalRoommates:$state_totalRoommates residentsTotalRoommatesPresent:$state_totalRoommatesPresent residentsTotalRoommatesAbsent:$state_totalRoommatesAbsent residentsTotalGuests:$state_totalGuests residentsTotalGuestsPresent:$state_totalGuestsPresent residentsTotalGuestsAbsent:$state_totalGuestsAbsent residentsTotalPresent:$state_totalPresent residentsTotalAbsent:$state_totalAbsent residentsHome:$state_home residentsGotosleep:$state_gotosleep residentsAsleep:$state_asleep residentsAwoken:$state_awoken residentsAbsent:$state_absent residentsGone:$state_gone presence:$newpresence state:$newstate";

    # safe current time
    my $datetime = FmtDateTime(time);

    # if state changed
    if ( $state ne $newstate ) {

        # stop any running wakeup-timers in case state changed
        my $wakeupState = AttrVal( $name, "wakeup", 0 );
        if ($wakeupState) {
            my $wakeupDeviceList = AttrVal( $name, "rgr_wakeupDevice", 0 );

            for my $wakeupDevice ( split /,/, $wakeupDeviceList ) {
                next if !$wakeupDevice;

                if ( defined( $defs{$wakeupDevice} )
                    && $defs{$wakeupDevice}{TYPE} eq "dummy" )
                {
                    # forced-stop only if resident is not present anymore
                    if ( $newpresence eq "present" ) {
                        fhem "set $wakeupDevice:FILTER=running!=0 end";
                    }
                    else {
                        fhem "set $wakeupDevice:FILTER=running!=0 stop";
                    }
                }
            }
        }

        # if newstate is asleep, start sleep timer
        readingsBulkUpdate( $hash, "lastSleep", $datetime )
          if ( $newstate eq "asleep" );

        # if prior state was asleep, update sleep statistics
        if ( $state eq "asleep"
            && ReadingsVal( $name, "lastSleep", "" ) ne "" )
        {
            readingsBulkUpdate( $hash, "lastAwake", $datetime );
            readingsBulkUpdate(
                $hash,
                "lastDurSleep",
                RESIDENTStk_TimeDiff(
                    $datetime, ReadingsVal( $name, "lastSleep", "" )
                )
            );
            readingsBulkUpdate(
                $hash,
                "lastDurSleep_cr",
                RESIDENTStk_TimeDiff(
                    $datetime, ReadingsVal( $name, "lastSleep", "" ), "min"
                )
            );
        }

        readingsBulkUpdate( $hash, "lastState",
            ReadingsVal( $name, "state", "initialized" ) );
        readingsBulkUpdate( $hash, "state", $newstate );
    }

    # if presence changed
    if ( $newpresence ne $presence ) {
        readingsBulkUpdate( $hash, "presence", $newpresence );

        # update statistics
        if ( $newpresence eq "present" ) {
            readingsBulkUpdate( $hash, "lastArrival", $datetime );

            # absence duration
            if ( ReadingsVal( $name, "lastDeparture", "-" ) ne "-" ) {
                readingsBulkUpdate(
                    $hash,
                    "lastDurAbsence",
                    RESIDENTStk_TimeDiff(
                        $datetime, ReadingsVal( $name, "lastDeparture", "-" )
                    )
                );
                readingsBulkUpdate(
                    $hash,
                    "lastDurAbsence_cr",
                    RESIDENTStk_TimeDiff(
                        $datetime, ReadingsVal( $name, "lastDeparture", "-" ),
                        "min"
                    )
                );
            }
        }
        else {
            readingsBulkUpdate( $hash, "lastDeparture", $datetime );

            # presence duration
            if ( ReadingsVal( $name, "lastArrival", "-" ) ne "-" ) {
                readingsBulkUpdate(
                    $hash,
                    "lastDurPresence",
                    RESIDENTStk_TimeDiff(
                        $datetime, ReadingsVal( $name, "lastArrival", "-" )
                    )
                );
                readingsBulkUpdate(
                    $hash,
                    "lastDurPresence_cr",
                    RESIDENTStk_TimeDiff(
                        $datetime, ReadingsVal( $name, "lastArrival", "-" ),
                        "min"
                    )
                );
            }
        }

    }

    # calculate duration timers
    RESIDENTS_DurationTimer($hash);
}

sub RESIDENTS_DurationTimer($;$) {
    my ( $mHash, @a ) = @_;
    my $hash         = ( $mHash->{HASH} ) ? $mHash->{HASH} : $mHash;
    my $name         = $hash->{NAME};
    my $silent       = ( defined( $a[0] ) && $a[0] eq "1" ) ? 1 : 0;
    my $timestampNow = gettimeofday();
    my $diff;
    my $durPresence = "0";
    my $durAbsence  = "0";
    my $durSleep    = "0";
    my $noDuration  = AttrVal( $name, "rgr_noDuration", 0 );
    delete $hash->{DURATIONTIMER} if ( $hash->{DURATIONTIMER} );

    RESIDENTStk_RemoveInternalTimer( "DurationTimer", $hash );

    return if ( IsDisabled($name) || $noDuration );

    # presence timer
    if (   ReadingsVal( $name, "presence", "absent" ) eq "present"
        && ReadingsVal( $name, "lastArrival", "-" ) ne "-" )
    {
        $durPresence =
          $timestampNow -
          time_str2num( ReadingsVal( $name, "lastArrival", "" ) );
    }

    # absence timer
    if (   ReadingsVal( $name, "presence", "present" ) eq "absent"
        && ReadingsVal( $name, "lastDeparture", "-" ) ne "-" )
    {
        $durAbsence =
          $timestampNow -
          time_str2num( ReadingsVal( $name, "lastDeparture", "" ) );
    }

    # sleep timer
    if (   ReadingsVal( $name, "state", "home" ) eq "asleep"
        && ReadingsVal( $name, "lastSleep", "-" ) ne "-" )
    {
        $durSleep =
          $timestampNow - time_str2num( ReadingsVal( $name, "lastSleep", "" ) );
    }

    my $durPresence_hr =
      ( $durPresence > 0 )
      ? RESIDENTStk_sec2time($durPresence)
      : "00:00:00";
    my $durPresence_cr =
      ( $durPresence > 60 ) ? int( $durPresence / 60 + 0.5 ) : 0;
    my $durAbsence_hr =
      ( $durAbsence > 0 ) ? RESIDENTStk_sec2time($durAbsence) : "00:00:00";
    my $durAbsence_cr =
      ( $durAbsence > 60 ) ? int( $durAbsence / 60 + 0.5 ) : 0;
    my $durSleep_hr =
      ( $durSleep > 0 ) ? RESIDENTStk_sec2time($durSleep) : "00:00:00";
    my $durSleep_cr = ( $durSleep > 60 ) ? int( $durSleep / 60 + 0.5 ) : 0;

    readingsBeginUpdate($hash) if ( !$silent );
    readingsBulkUpdateIfChanged( $hash, "durTimerPresence_cr",
        $durPresence_cr );
    readingsBulkUpdateIfChanged( $hash, "durTimerPresence",   $durPresence_hr );
    readingsBulkUpdateIfChanged( $hash, "durTimerAbsence_cr", $durAbsence_cr );
    readingsBulkUpdateIfChanged( $hash, "durTimerAbsence",    $durAbsence_hr );
    readingsBulkUpdateIfChanged( $hash, "durTimerSleep_cr",   $durSleep_cr );
    readingsBulkUpdateIfChanged( $hash, "durTimerSleep",      $durSleep_hr );
    readingsEndUpdate( $hash, 1 ) if ( !$silent );

    $hash->{DURATIONTIMER} = $timestampNow + 60;

    RESIDENTStk_InternalTimer( "DurationTimer", $hash->{DURATIONTIMER},
        "RESIDENTS_DurationTimer", $hash, 1 );

    return undef;
}

sub RESIDENTS_StartInternalTimers($$) {
    my ($hash) = @_;

    RESIDENTS_DurationTimer($hash);
}

sub RESIDENTS_StopInternalTimers($) {
    my ($hash) = @_;

    delete $hash->{DURATIONTIMER} if ( $hash->{DURATIONTIMER} );

    RESIDENTStk_RemoveInternalTimer( "DurationTimer", $hash );
}

1;

=pod
=item helper
=item summary combines ROOMMATE and GUEST devices to a residential community
=item summary_de fasst ROOMMATE und GUEST Ger&auml;te zu einer Wohngemeinschaft zusammen
=begin html

    <p>
      <a name="RESIDENTS" id="RESIDENTS"></a>
    </p>
    <h3>
      RESIDENTS
    </h3>
    <ul>
      <a name="RESIDENTSdefine" id="RESIDENTSdefine"></a> <b>Define</b>
      <ul>
        <code>define &lt;rgr_ResidentsName&gt; RESIDENTS</code><br>
        <br>
        Provides a special virtual device to represent a group of individuals living at your home.<br>
        It locically combines individual states of <a href="#ROOMMATE">ROOMMATE</a> and <a href="#GUEST">GUEST</a> devices and allows state changes for all members.<br>
        Based on the current state and other readings, you may trigger other actions within FHEM.<br>
        <br>
        Example:<br>
        <ul>
          <code># Standalone<br>
          define rgr_Residents RESIDENTS</code>
        </ul>
      </ul><br>
      <br>
      <a name="RESIDENTSset" id="RESIDENTSset"></a> <b>Set</b>
      <ul>
        <code>set &lt;rgr_ResidentsName&gt; &lt;command&gt; [&lt;parameter&gt;]</code><br>
        <br>
        Currently, the following commands are defined.<br>
        <ul>
          <li>
            <b>addGuest</b> &nbsp;&nbsp;-&nbsp;&nbsp; creates a new GUEST device and adds it to the current RESIDENTS group. Just enter the dummy name and there you go.
          </li>
          <li>
            <b>addRoommate</b> &nbsp;&nbsp;-&nbsp;&nbsp; creates a new ROOMMATE device and adds it to the current RESIDENTS group. Just enter the first name and there you go.
          </li>
          <li>
            <b>removeGuest</b> &nbsp;&nbsp;-&nbsp;&nbsp; shows all GUEST members and allows to delete their dummy devices easily.
          </li>
          <li>
            <b>removeRoommate</b> &nbsp;&nbsp;-&nbsp;&nbsp; shows all ROOMMATE members and allows to delete their dummy devices easily.
          </li>
          <li>
            <b>state</b> &nbsp;&nbsp;home,gotosleep,asleep,awoken,absent,gone&nbsp;&nbsp; switch between states for all group members at once; see attribute rgr_states to adjust list shown in FHEMWEB
          </li>
          <li>
            <b>create</b> &nbsp;&nbsp;wakeuptimer&nbsp;&nbsp; add several pre-configurations provided by RESIDENTS Toolkit. See separate section for details.
          </li>
        </ul>
        <ul>
            <u>Note:</u> If you would like to restrict access to admin set-commands (-> addGuest, addRoommate, removeGuest, create) you may set your FHEMWEB instance's attribute allowedCommands like 'set,set-user'.
            The string 'set-user' will ensure only non-admin set-commands can be executed when accessing FHEM using this FHEMWEB instance.
        </ul>
      </ul><br>
      <br>
      <ul>
        <u>Possible states and their meaning</u><br>
        <br>
        <ul>
          This module differs between 7 states:<br>
          <br>
          <ul>
            <li>
              <b>home</b> - residents are present at home and at least one of them is not asleep
            </li>
            <li>
              <b>gotosleep</b> - present residents are on their way to bed (if they are not asleep already)
            </li>
            <li>
              <b>asleep</b> - all present residents are currently sleeping
            </li>
            <li>
              <b>awoken</b> - at least one resident just woke up from sleep
            </li>
            <li>
              <b>absent</b> - no resident is currently at home but at least one will be back shortly
            </li>
            <li>
              <b>gone</b> - all residents left home for longer period
            </li>
            <li>
              <b>none</b> - no active member
            </li>
          </ul><br>
          <br>
          Note: State 'none' cannot explicitly be set. Setting state to 'gone' will be handled as 'none' for GUEST member devices.
        </ul>
      </ul><br>
      <br>
      <a name="RESIDENTSattr" id="RESIDENTSattr"></a> <b>Attributes</b><br>
      <ul>
        <ul>
          <li>
            <b>rgr_lang</b> - overwrite global language setting; helps to set device attributes to translate FHEMWEB display text
          </li>
          <li>
            <b>rgr_noDuration</b> - may be used to disable continuous, non-event driven duration timer calculation (see readings durTimer*)
          </li>
          <li>
            <b>rgr_showAllStates</b> - states 'asleep' and 'awoken' are hidden by default to allow simple gotosleep process via devStateIcon; defaults to 0
          </li>
          <li>
            <b>rgr_states</b> - list of states to be shown in FHEMWEB; separate entries by comma only and do NOT use spaces; unsupported states will lead to errors though
          </li>
          <li>
            <b>rgr_wakeupDevice</b> - reference to enslaved DUMMY devices used as a wake-up timer (part of RESIDENTS Toolkit's wakeuptimer)
          </li>
        </ul>
      </ul><br>
      <br>
      <br>
      <b>Generated Readings/Events:</b><br>
      <ul>
        <ul>
          <li>
            <b>lastActivity</b> - the last state change of one of the group members
          </li>
          <li>
            <b>lastActivityBy</b> - the realname of the last group member with changed state
          </li>
          <li>
            <b>lastArrival</b> - timestamp of last arrival at home
          </li>
          <li>
            <b>lastAwake</b> - timestamp of last sleep cycle end
          </li>
          <li>
            <b>lastDeparture</b> - timestamp of last departure from home
          </li>
          <li>
            <b>lastDurAbsence</b> - duration of last absence from home in human readable format (hours:minutes:seconds)
          </li>
          <li>
            <b>lastDurAbsence_cr</b> - duration of last absence from home in computer readable format (minutes)
          </li>
          <li>
            <b>lastDurPresence</b> - duration of last presence at home in human readable format (hours:minutes:seconds)
          </li>
          <li>
            <b>lastDurPresence_cr</b> - duration of last presence at home in computer readable format (minutes)
          </li>
          <li>
            <b>lastDurSleep</b> - duration of last sleep in human readable format (hours:minutes:seconds)
          </li>
          <li>
            <b>lastDurSleep_cr</b> - duration of last sleep in computer readable format (minutes)
          </li>
          <li>
            <b>lastSleep</b> - timestamp of last sleep cycle begin
          </li>
          <li>
            <b>lastState</b> - the prior state
          </li>
          <li>
            <b>lastWakeup</b> - time of last wake-up timer run
          </li>
          <li>
            <b>lastWakeupDev</b> - device name of last wake-up timer
          </li>
          <li>
            <b>nextWakeup</b> - time of next wake-up program run
          </li>
          <li>
            <b>nextWakeupDev</b> - device name for next wake-up program run
          </li>
          <li>
            <b>presence</b> - reflects the home presence state, depending on value of reading 'state' (can be 'present' or 'absent')
          </li>
          <li>
            <b>residentsAbsent</b> - number of residents with state 'absent'
          </li>
          <li>
            <b>residentsAbsentDevs</b> - device name of residents with state 'absent'
          </li>
          <li>
            <b>residentsAbsentNames</b> - device alias of residents with state 'absent'
          </li>
          <li>
            <b>residentsAsleep</b> - number of residents with state 'asleep'
          </li>
          <li>
            <b>residentsAsleepDevs</b> - device name of residents with state 'asleep'
          </li>
          <li>
            <b>residentsAsleepNames</b> - device alias of residents with state 'asleep'
          </li>
          <li>
            <b>residentsAwoken</b> - number of residents with state 'awoken'
          </li>
          <li>
            <b>residentsAwokenDevs</b> - device name of residents with state 'awoken'
          </li>
          <li>
            <b>residentsAwokenNames</b> - device alias of residents with state 'awoken'
          </li>
          <li>
            <b>residentsGone</b> - number of residents with state 'gone'
          </li>
          <li>
            <b>residentsGoneDevs</b> - device name of residents with state 'gone'
          </li>
          <li>
            <b>residentsGoneNames</b> - device alias of residents with state 'gone'
          </li>
          <li>
            <b>residentsGotosleep</b> - number of residents with state 'gotosleep'
          </li>
          <li>
            <b>residentsGotosleepDevs</b> - device name of residents with state 'gotosleep'
          </li>
          <li>
            <b>residentsGotosleepNames</b> - device alias of residents with state 'gotosleep'
          </li>
          <li>
            <b>residentsHome</b> - number of residents with state 'home'
          </li>
          <li>
            <b>residentsHomeDevs</b> - device name of residents with state 'home'
          </li>
          <li>
            <b>residentsHomeNames</b> - device alias of residents with state 'home'
          </li>
          <li>
            <b>residentsTotal</b> - total number of all active residents despite their current state
          </li>
          <li>
            <b>residentsTotalAbsent</b> - number of all residents who are currently underway
          </li>
          <li>
            <b>residentsTotalAbsentDevs</b> - device name of all residents who are currently underway
          </li>
          <li>
            <b>residentsTotalAbsentNames</b> - device alias of all residents who are currently underway
          </li>
          <li>
            <b>residentsTotalGuests</b> - number of active guests who are currently treated as part of the residents scope
          </li>
          <li>
            <b>residentsTotalGuestsAbsent</b> - number of all active guests who are currently underway
          </li>
          <li>
            <b>residentsTotalGuestsAbsentDevs</b> - device name of all active guests who are currently underway
          </li>
          <li>
            <b>residentsTotalGuestsAbsentNames</b> - device alias of all active guests who are currently underway
          </li>
          <li>
            <b>residentsTotalGuestsPresent</b> - number of all active guests who are currently at home
          </li>
          <li>
            <b>residentsTotalGuestsPresentDevs</b> - device name of all active guests who are currently at home
          </li>
          <li>
            <b>residentsTotalGuestsPresentNames</b> - device alias of all active guests who are currently at home
          </li>
          <li>
            <b>residentsTotalRoommates</b> - number of residents treated as being a permanent resident
          </li>
          <li>
            <b>residentsTotalRoommatesAbsent</b> - number of all roommates who are currently underway
          </li>
          <li>
            <b>residentsTotalRoommatesAbsentDevs</b> - device name of all roommates who are currently underway
          </li>
          <li>
            <b>residentsTotalRoommatesAbsentNames</b> - device alias of all roommates who are currently underway
          </li>
          <li>
            <b>residentsTotalRoommatesPresent</b> - number of all roommates who are currently at home
          </li>
          <li>
            <b>residentsTotalRoommatesPresentDevs</b> - device name of all roommates who are currently at home
          </li>
          <li>
            <b>residentsTotalRoommatesPresentNames</b> - device alias of all roommates who are currently at home
          </li>
          <li>
            <b>residentsTotalPresent</b> - number of all residents who are currently at home
          </li>
          <li>
            <b>residentsTotalPresentDevs</b> - device name of all residents who are currently at home
          </li>
          <li>
            <b>residentsTotalPresentNames</b> - device alias of all residents who are currently at home
          </li>
          <li>
            <b>residentsTotalWakeup</b> - number of all residents which currently have a wake-up program being executed
          </li>
          <li>
            <b>residentsTotalWakeupDevs</b> - device name of all residents which currently have a wake-up program being executed
          </li>
          <li>
            <b>residentsTotalWakeupNames</b> - device alias of all residents which currently have a wake-up program being executed
          </li>
          <li>
            <b>residentsTotalWayhome</b> - number of all active residents who are currently on their way back home
          </li>
          <li>
            <b>residentsTotalWayhomeDevs</b> - device name of all active residents who are currently on their way back home
          </li>
          <li>
            <b>residentsTotalWayhomeNames</b> - device alias of all active residents who are currently on their way back home
          </li>
          <li>
            <b>residentsTotalWayhomeDelayed</b> - number of all residents who are delayed on their way back home
          </li>
          <li>
            <b>residentsTotalWayhomeDelayedDevs</b> - device name of all delayed residents who are currently on their way back home
          </li>
          <li>
            <b>residentsTotalWayhomeDelayedNames</b> - device alias of all delayed residents who are currently on their way back home
          </li>
          <li>
            <b>state</b> - reflects the current state
          </li>
          <li>
            <b>wakeup</b> - becomes '1' while a wake-up program of this resident group is being executed
          </li>
        </ul>
      </ul>
      <br>
      <br>
      <b>RESIDENTS Toolkit</b><br>
      <ul>
        <ul>
					Using set-command <code>create</code> you may add pre-configured configurations to your RESIDENTS, <a href="#ROOMMATE">ROOMMATE</a> or <a href="#GUEST">GUEST</a> devices for your convenience.<br>
					The following commands are currently available:<br>
					<br>
					<li>
						<b>wakeuptimer</b> &nbsp;&nbsp;-&nbsp;&nbsp; adds a wake-up timer dummy device with enhanced functions to start with wake-up automations
						<ul>
							A notify device is created to be used as a Macro to carry out your actual automations. The macro is triggered by a normal at device you may customize as well. However, a special RESIDENTS Toolkit function is handling the wake-up trigger event for you.<br>
              The time of activated wake-up timers may be relatively increased or decreased by using +<MINUTES> or -<MINUTES> respectively. +HH:MM can be used as well.<br>
							<br>
							The wake-up behaviour may be influenced by the following device attributes:<br>
							<li>
								<i>wakeupAtdevice</i> - backlink the at device (mandatory)
							</li>
							<li>
								<i>wakeupDays</i> - only trigger macro at these days. Mon=1,Tue=2,Wed=3,Thu=4,Fri=5,Sat=6,Sun=0 (optional)
							</li>
							<li>
								<i>wakeupDefaultTime</i> - after triggering macro reset the wake-up time to this default value (optional)
							</li>
							<li>
								<i>wakeupEnforced</i> - Enforce wake-up (optional; 0=no, 1=yes, 2=if wake-up time is not wakeupDefaultTime)
							</li>
							<li>
								<i>wakeupHolidays</i> - May trigger macro on holidays or non-holidays (optional; andHoliday=on holidays also considering wakeupDays, orHoliday=on holidays independently of wakeupDays, andNoHoliday=on non-holidays also considering wakeupDays, orNoHoliday=on non-holidays independently of wakeupDays)
							</li>
							<li>
								<i>wakeupMacro</i> - name of the notify macro device (mandatory)
							</li>
							<li>
								<i>wakeupOffset</i> - value in minutes to trigger your macro earlier than the user requested to be woken up, e.g. if you have a complex wake-up program over 30 minutes (defaults to 0)
							</li>
							<li>
								<i>wakeupResetSwitcher</i> - DUMMY device to quickly turn on/off reset function (optional, device will be auto-created)
							</li>
							<li>
								<i>wakeupResetdays</i> - if wakeupDefaultTime is set you may restrict timer reset to specific days only. Mon=1,Tue=2,Wed=3,Thu=4,Fri=5,Sat=6,Sun=0 (optional)
							</li>
							<li>
								<i>wakeupUserdevice</i> - backlink to RESIDENTS, ROOMMATE or GUEST device to check it's status (mandatory)
							</li>
							<li>
								<i>wakeupWaitPeriod</i> - waiting period threshold in minutes until wake-up program may be triggered again, e.g. if you manually set an earlier wake-up time than normal while using wakeupDefaultTime. Does not apply in case wake-up time was changed during this period; defaults to 360 minutes / 6h (optional)
							</li>
						</ul>
					</li>
        </ul>
      </ul>
    </ul>

=end html

=begin html_DE

    <p>
      <a name="RESIDENTS" id="RESIDENTS"></a>
    </p>
    <h3>
      RESIDENTS
    </h3>
    <ul>
      <a name="RESIDENTSdefine" id="RESIDENTSdefine"></a> <b>Define</b>
      <ul>
        <code>define &lt;rgr_ResidentsName&gt; RESIDENTS</code><br>
        <br>
        Stellt ein spezielles virtuelles Device bereit, um eine Gruppe von Personen zu repr&auml;sentieren, die zusammen wohnen.<br>
        Es kombiniert dabei logisch die individuellen Status von <a href="#ROOMMATE">ROOMMATE</a> und <a href="#GUEST">GUEST</a> Devices und erlaubt den Status f&uuml;r alle Mitglieder zeitgleich zu &auml;ndern. Basierend auf dem aktuellen Status und anderen Readings k&ouml;nnen andere Aktionen innerhalb von FHEM angestoßen werden.<br>
        <br>
        Beispiele:<br>
        <ul>
          <code># Einzeln<br>
          define rgr_Residents RESIDENTS</code>
        </ul>
      </ul><br>
      <br>
      <a name="RESIDENTSset" id="RESIDENTSset"></a> <b>Set</b>
      <ul>
        <code>set &lt;rgr_ResidentsName&gt; &lt;command&gt; [&lt;parameter&gt;]</code><br>
        <br>
        Momentan sind die folgenden Kommandos definiert.<br>
        <ul>
          <li>
            <b>addGuest</b> &nbsp;&nbsp;-&nbsp;&nbsp; erstellt ein neues GUEST Device und f&uuml;gt es der aktuellen RESIDENTS Gruppe hinzu. Einfach den Platzhalternamen eingeben und das wars.
          </li>
          <li>
            <b>addRoommate</b> &nbsp;&nbsp;-&nbsp;&nbsp; erstellt ein neues ROOMMATE Device und f&uuml;gt es der aktuellen RESIDENTS Gruppe hinzu. Einfach den Vornamen eingeben und das wars.
          </li>
          <li>
            <b>removeGuest</b> &nbsp;&nbsp;-&nbsp;&nbsp; zeigt alle Mitglieder vom Typ GUEST an und erm&ouml;glicht ein einfaches l&ouml;schen des dazugeh&ouml;rigen Dummy Devices.
          </li>
          <li>
            <b>removeRoommate</b> &nbsp;&nbsp;-&nbsp;&nbsp; zeigt alle Mitglieder vom Typ ROOMMATE an und erm&ouml;glicht ein einfaches l&ouml;schen des dazugeh&ouml;rigen Dummy Devices.
          </li>
          <li>
            <b>state</b> &nbsp;&nbsp;home,gotosleep,asleep,awoken,absent,gone&nbsp;&nbsp; wechselt den Status f&uuml;r alle Gruppenmitglieder gleichzeitig; siehe Attribut rgr_states, um die angezeigte Liste in FHEMWEB abzu&auml;ndern
          </li>
          <li>
            <b>create</b> &nbsp;&nbsp;wakeuptimer&nbsp;&nbsp; f&uuml;gt diverse Vorkonfigurationen auf Basis von RESIDENTS Toolkit hinzu. Siehe separate Sektion.
          </li>
        </ul>
        <ul>
            <u>Hinweis:</u> Sofern der Zugriff auf administrative set-Kommandos (-> addGuest, addRoommate, removeGuest, create) eingeschr&auml;nkt werden soll, kann in einer FHEMWEB Instanz das Attribut allowedCommands &auml;hnlich wie 'set,set-user' erweitert werden.
            Die Zeichenfolge 'set-user' stellt dabei sicher, dass beim Zugriff auf FHEM &uuml;ber diese FHEMWEB Instanz nur nicht-administrative set-Kommandos ausgef&uuml;hrt werden k&ouml;nnen.
        </ul>
      </ul><br>
      <br>
      <ul>
        <u>M&ouml;gliche Status und ihre Bedeutung</u><br>
        <br>
        <ul>
          Dieses Modul unterscheidet 7 verschiedene Status:<br>
          <br>
          <ul>
            <li>
              <b>home</b> - Bewohner sind zu Hause und mindestens einer schl&auml;ft nicht
            </li>
            <li>
              <b>gotosleep</b> - alle anwesenden Bewohner sind auf dem Weg ins Bett (wenn sie nicht schon schlafen)
            </li>
            <li>
              <b>asleep</b> - alle anwesenden Bewohner schlafen
            </li>
            <li>
              <b>awoken</b> - mindestens einer der anwesenden Bewohner ist gerade aufgewacht
            </li>
            <li>
              <b>absent</b> - keiner der Bewohner ist momentan zu Hause; mindestens einer ist aber in K&uuml;rze zur&uuml;ck
            </li>
            <li>
              <b>gone</b> - alle Bewohner sind f&uuml;r l&auml;ngere Zeit verreist
            </li>
            <li>
              <b>none</b> - kein Mitglied aktiv
            </li>
          </ul><br>
          <br>
          Hinweis: Der Status 'none' kann nicht explizit gesetzt werden. Das setzen von 'gone' wird bei Mitgliedern vom Typ GUEST als 'none' behandelt.
        </ul>
      </ul><br>
      <br>
      <a name="RESIDENTSattr" id="RESIDENTSattr"></a> <b>Attribute</b><br>
      <ul>
        <ul>
          <li>
            <b>rgr_lang</b> - &uuml;berschreibt globale Spracheinstellung; hilft beim setzen von Device Attributen, um FHEMWEB Anzeigetext zu &uuml;bersetzen
          </li>
          <li>
            <b>rgr_noDuration</b> - deaktiviert die kontinuierliche, nicht Event-basierte Berechnung der Zeitspannen (siehe Readings durTimer*)
          </li>
          <li>
            <b>rgr_showAllStates</b> - die Status 'asleep' und 'awoken' sind normalerweise nicht immer sichtbar, um einen einfachen Zubettgeh-Prozess &uuml;ber das devStateIcon Attribut zu erm&ouml;glichen; Standard ist 0
          </li>
          <li>
            <b>rgr_states</b> - Liste aller in FHEMWEB angezeigter Status; Eintrage nur mit Komma trennen und KEINE Leerzeichen benutzen; nicht unterst&uuml;tzte Status f&uuml;hren zu Fehlern
          </li>
          <li>
            <b>rgr_wakeupDevice</b> - Referenz zu versklavten DUMMY Ger&auml;ten, welche als Wecker benutzt werden (Teil von RESIDENTS Toolkit's wakeuptimer)
          </li>
        </ul>
      </ul><br>
      <br>
      <br>
      <b>Generierte Readings/Events:</b><br>
      <ul>
        <ul>
          <li>
            <b>lastActivity</b> - der letzte Status Wechsel eines Gruppenmitglieds
          </li>
          <li>
            <b>lastActivityBy</b> - der Name des Gruppenmitglieds, dessen Status zuletzt ge&auml;ndert wurde
          </li>
          <li>
            <b>lastArrival</b> - Zeitstempel der letzten Ankunft zu Hause
          </li>
          <li>
            <b>lastAwake</b> - Zeitstempel des Endes des letzten Schlafzyklus
          </li>
          <li>
            <b>lastDeparture</b> - Zeitstempel des letzten Verlassens des Zuhauses
          </li>
          <li>
            <b>lastDurAbsence</b> - Dauer der letzten Abwesenheit in normal lesbarem Format (Stunden:Minuten:Sekunden)
          </li>
          <li>
            <b>lastDurAbsence_cr</b> - Dauer der letzten Abwesenheit in Computer lesbarem Format (Minuten)
          </li>
          <li>
            <b>lastDurPresence</b> - Dauer der letzten Anwesenheit in normal lesbarem Format (Stunden:Minuten:Sekunden)
          </li>
          <li>
            <b>lastDurPresence_cr</b> - Dauer der letzten Anwesenheit in Computer lesbarem Format (Minuten)
          </li>
          <li>
            <b>lastDurSleep</b> - Dauer des letzten Schlafzyklus in normal lesbarem Format (Stunden:Minuten:Sekunden)
          </li>
          <li>
            <b>lastDurSleep_cr</b> - Dauer des letzten Schlafzyklus in Computer lesbarem Format (Minuten)
          </li>
          <li>
            <b>lastSleep</b> - Zeitstempel des Beginns des letzten Schlafzyklus
          </li>
          <li>
            <b>lastState</b> - der vorherige Status
          </li>
          <li>
            <b>lastWakeup</b> - Zeit der letzten Wake-up Timer Ausf&uuml;hring
          </li>
          <li>
            <b>lastWakeupDev</b> - Device Name des zuletzt verwendeten Wake-up Timers
          </li>
          <li>
            <b>nextWakeup</b> - Zeit der n&auml;chsten Wake-up Timer Ausf&uuml;hrung
          </li>
          <li>
            <b>nextWakeupDev</b> - Device Name des als n&auml;chstes ausgef&auml;hrten Wake-up Timer
          </li>
          <li>
            <b>presence</b> - gibt den zu Hause Status in Abh&auml;ngigkeit des Readings 'state' wieder (kann 'present' oder 'absent' sein)
          </li>
          <li>
            <b>residentsAbsent</b> - Anzahl der Bewohner mit Status 'absent'
          </li>
          <li>
            <b>residentsAbsentDevs</b> - Ger&auml;tename der Bewohner mit Status 'absent'
          </li>
          <li>
            <b>residentsAbsentNames</b> - Ger&auml;tealias der Bewohner mit Status 'absent'
          </li>
          <li>
            <b>residentsAsleep</b> - Anzahl der Bewohner mit Status 'asleep'
          </li>
          <li>
            <b>residentsAsleepDevs</b> - Ger&auml;tename der Bewohner mit Status 'asleep'
          </li>
          <li>
            <b>residentsAsleepNames</b> - Ger&auml;tealias der Bewohner mit Status 'asleep'
          </li>
          <li>
            <b>residentsAwoken</b> - Anzahl der Bewohner mit Status 'awoken'
          </li>
          <li>
            <b>residentsAwokenDevs</b> - Ger&auml;tename der Bewohner mit Status 'awoken'
          </li>
          <li>
            <b>residentsAwokenNames</b> - Ger&auml;tealias der Bewohner mit Status 'awoken'
          </li>
          <li>
            <b>residentsGone</b> - Anzahl der Bewohner mit Status 'gone'
          </li>
          <li>
            <b>residentsGoneDevs</b> - Ger&auml;tename der Bewohner mit Status 'gone'
          </li>
          <li>
            <b>residentsGoneNames</b> - Ger&auml;tealias der Bewohner mit Status 'gone'
          </li>
          <li>
            <b>residentsGotosleep</b> - Anzahl der Bewohner mit Status 'gotosleep'
          </li>
          <li>
            <b>residentsGotosleepDevs</b> - Ger&auml;tename der Bewohner mit Status 'gotosleep'
          </li>
          <li>
            <b>residentsGotosleepNames</b> - Ger&auml;tealias der Bewohner mit Status 'gotosleep'
          </li>
          <li>
            <b>residentsHome</b> - Anzahl der Bewohner mit Status 'home'
          </li>
          <li>
            <b>residentsHomeDevs</b> - Ger&auml;tename der Bewohner mit Status 'home'
          </li>
          <li>
            <b>residentsHomeNames</b> - Ger&auml;tealias der Bewohner mit Status 'home'
          </li>
          <li>
            <b>residentsTotal</b> - Summe aller aktiven Bewohner unabh&auml;ngig von ihrem aktuellen Status
          </li>
          <li>
            <b>residentsTotalAbsent</b> - Summe aller aktiven Bewohner, die unterwegs sind
          </li>
          <li>
            <b>residentsTotalAbsentDevs</b> - Ger&auml;tename aller aktiven Bewohner, die unterwegs sind
          </li>
          <li>
            <b>residentsTotalAbsentNames</b> - Ger&auml;tealias aller aktiven Bewohner, die unterwegs sind
          </li>
          <li>
            <b>residentsTotalGuests</b> - Anzahl der aktiven G&auml;ste, welche momentan du den Bewohnern dazugez&auml;hlt werden
          </li>
          <li>
            <b>residentsTotalGuestsAbsent</b> - Anzahl der aktiven G&auml;ste, die momentan unterwegs sind
          </li>
          <li>
            <b>residentsTotalGuestsAbsentDevs</b> - Ger&auml;tename der aktiven G&auml;ste, die momentan unterwegs sind
          </li>
          <li>
            <b>residentsTotalGuestsAbsentNames</b> - Ger&auml;tealias der aktiven G&auml;ste, die momentan unterwegs sind
          </li>
          <li>
            <b>residentsTotalGuestsPresent</b> - Anzahl der aktiven G&auml;ste, die momentan zu Hause sind
          </li>
          <li>
            <b>residentsTotalGuestsPresentDevs</b> - Ger&auml;tename der aktiven G&auml;ste, die momentan zu Hause sind
          </li>
          <li>
            <b>residentsTotalGuestsPresentNames</b> - Ger&auml;tealias der aktiven G&auml;ste, die momentan zu Hause sind
          </li>
          <li>
            <b>residentsTotalRoommates</b> - Anzahl der Bewohner, die als permanente Bewohner behandelt werden
          </li>
          <li>
            <b>residentsTotalRoommatesAbsent</b> - Anzahl der Besitzer, die momentan unterwegs sind
          </li>
          <li>
            <b>residentsTotalRoommatesAbsentDevs</b> - Ger&auml;tename der Besitzer, die momentan unterwegs sind
          </li>
          <li>
            <b>residentsTotalRoommatesAbsentNames</b> - Ger&auml;tealias der Besitzer, die momentan unterwegs sind
          </li>
          <li>
            <b>residentsTotalRoommatesPresent</b> - Anzahl der Besitzer, die momentan zu Hause sind
          </li>
          <li>
            <b>residentsTotalRoommatesPresentDevs</b> - Ger&auml;tename der Besitzer, die momentan zu Hause sind
          </li>
          <li>
            <b>residentsTotalRoommatesPresentNames</b> - Ger&auml;tealias der Besitzer, die momentan zu Hause sind
          </li>
          <li>
            <b>residentsTotalPresent</b> - Summe aller aktiven Bewohner, die momentan zu Hause sind
          </li>
          <li>
            <b>residentsTotalPresentDevs</b> - Ger&auml;tename aller aktiven Bewohner, die momentan zu Hause sind
          </li>
          <li>
            <b>residentsTotalPresentNames</b> - Ger&auml;tealias aller aktiven Bewohner, die momentan zu Hause sind
          </li>
          <li>
            <b>residentsTotalWakeup</b> - Summe aller Bewohner, bei denen aktuell ein Weckprogramm ausgef&uuml;hrt wird
          </li>
          <li>
            <b>residentsTotalWakeupDevs</b> - Ger&auml;tename aller Bewohner, bei denen aktuell ein Weckprogramm ausgef&uuml;hrt wird
          </li>
          <li>
            <b>residentsTotalWakeupNames</b> - Ger&auml;tealias aller Bewohner, bei denen aktuell ein Weckprogramm ausgef&uuml;hrt wird
          </li>
          <li>
            <b>residentsTotalWayhome</b> - Summe aller aktiven Bewohner, die momentan auf dem Weg zur&uuml;ck nach Hause sind
          </li>
          <li>
            <b>residentsTotalWayhomeDevs</b> - Ger&auml;tename aller aktiven Bewohner, die momentan auf dem Weg zur&uuml;ck nach Hause sind
          </li>
          <li>
            <b>residentsTotalWayhomeNames</b> - Ger&auml;tealias aller aktiven Bewohner, die momentan auf dem Weg zur&uuml;ck nach Hause sind
          </li>
          <li>
            <b>residentsTotalWayhomeDelayed</b> - Summe aller Bewohner, die momentan mit Versp&auml;tung auf dem Weg zur&uuml;ck nach Hause sind
          </li>
          <li>
            <b>residentsTotalWayhomeDelayedDevs</b> - Ger&auml;tename aller Bewohner, die momentan versp&auml;tet auf dem Weg zur&uuml;ck nach Hause sind
          </li>
          <li>
            <b>residentsTotalWayhomeDelayedNames</b> - Ger&auml;tealias aller Bewohner, die momentan versp&auml;tet auf dem Weg zur&uuml;ck nach Hause sind
          </li>
          <li>
            <b>state</b> - gibt den aktuellen Status wieder
          </li>
          <li>
            <b>wakeup</b> - hat den Wert '1' w&auml;hrend ein Weckprogramm dieser Bewohner-Gruppe ausgef&uuml;hrt wird
          </li>
        </ul>
      </ul>
      <br>
      <br>
      <b>RESIDENTS Toolkit</b><br>
      <ul>
        <ul>
					Mit dem set-Kommando <code>create</code> k&ouml;nnen zur Vereinfachung vorkonfigurierte Konfigurationen zu RESIDENTS, <a href="#ROOMMATE">ROOMMATE</a> oder <a href="#GUEST">GUEST</a> Ger&auml;ten hinzugef&uuml;gt werden.<br>
					Die folgenden Kommandos sind momentan verf&uuml;gbar:<br>
					<br>
					<li>
						<b>wakeuptimer</b> &nbsp;&nbsp;-&nbsp;&nbsp; f&uuml;gt ein Dummy Ger&auml;t mit erweiterten Funktionen als Wecker hinzu, um darauf Weck-Automationen aufzubauen.
						<ul>
							Ein notify Ger&auml;t wird als Makro erstellt, um die eigentliche Automation auszuf&uuml;hren. Das Makro wird durch ein normales at-Ger&auml;t ausgel&ouml;st und kann ebenfalls angepasst werden. Die Hauptfunktion wird dabei trotzdem von einer speziellen RESIDENTS Toolkit funktion gehandhabt.<br>
              Die Zeit aktiver Wecker kann mittels +<MINUTEN> oder -<MINUTEN> relativ erh&ouml;ht bzw. verringert werden. Die Angabe als +HH:MM ist auch m&ouml;glich.<br>
							<br>
							Die Weckfunktion kann wie folgt &uuml;ber Attribute beinflusst werden:<br>
							<li>
								<i>wakeupAtdevice</i> - Backlink zum at Ger&auml;t (notwendig)
							</li>
							<li>
								<i>wakeupDays</i> - Makro nur an bestimmten Tagen ausl&ouml;sen. Mon=1,Di=2,Mi=3,Do=4,Fr=5,Sa=6,So=0 (optional)
							</li>
							<li>
								<i>wakeupDefaultTime</i> - Stellt die Weckzeit nach dem ausl&ouml;sen zur&uuml;ck auf diesen Standardwert (optional)
							</li>
							<li>
								<i>wakeupEnforced</i> - Forciertes wecken (optional; 0=nein, 1=ja, 2=wenn Weckzeit ungleich wakeupDefaultTime)
							</li>
							<li>
								<i>wakeupHolidays</i> - Makro u.U. an Feiertagen oder Nicht-Feiertagen ausf&uuml;hren (optional; andHoliday=an Feiertagen ggf. zusammen mit wakeupDays, orHoliday=an Feiertagen unabh&auml;ngig von wakeupDays, andNoHoliday=an Nicht-Feiertagen ggf. zusammen mit wakeupDays, orNoHoliday=an Nicht-Feiertagen unabh&auml;ngig von wakeupDays)
							</li>
							<li>
								<i>wakeupMacro</i> - Name des notify Makro Ger&auml;tes (notwendig)
							</li>
							<li>
								<i>wakeupOffset</i> - Wert in Minuten, die das Makro fr&uuml;her ausgel&ouml;st werden soll, z.B. bei komplexen Weckprogrammen &uuml;ber einen Zeitraum von 30 Minuten (Standard ist 0)
							</li>
							<li>
								<i>wakeupResetSwitcher</i> - das DUMMY Device, welches zum schnellen ein/aus schalten der Resetfunktion verwendet wird (optional, Device wird automatisch angelegt)
							</li>
							<li>
								<i>wakeupResetdays</i> - sofern wakeupDefaultTime gesetzt ist, kann der Reset hier auf betimmte Tage begrenzt werden. Mon=1,Di=2,Mi=3,Do=4,Fr=5,Sa=6,So=0 (optional)
							</li>
							<li>
								<i>wakeupUserdevice</i> - Backlink zum RESIDENTS, ROOMMATE oder GUEST Ger&auml;t, um dessen Status zu pr&uuml;fen (notwendig)
							</li>
							<li>
								<i>wakeupWaitPeriod</i> - Schwelle der Wartezeit in Minuten bis das Weckprogramm erneut ausgef&uuml;hrt werden kann, z.B. wenn manuell eine fr&uuml;here Weckzeit gesetzt wurde als normal w&auml;hrend wakeupDefaultTime verwendet wird. Greift nicht, wenn die Weckzeit w&auml;hrend dieser Zeit ge&auml;ndert wurde; Standard ist 360 Minuten / 6h (optional)
							</li>
						</ul>
					</li>
        </ul>
      </ul>
    </ul>

=end html_DE

=cut
