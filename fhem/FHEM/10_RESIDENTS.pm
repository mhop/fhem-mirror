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
#
# Version: 1.0.2
#
# Major Version History:
# - 1.0.0 - 2014-02-08
# -- First release
#
##############################################################################

package main;

use strict;
use warnings;
use Time::Local;
use Data::Dumper;

sub RESIDENTS_Set($@);
sub RESIDENTS_Define($$);
sub RESIDENTS_Notify($$);
sub RESIDENTS_Undefine($$);

###################################
sub RESIDENTS_Initialize($) {
    my ($hash) = @_;

    Log3 $hash, 5, "RESIDENTS_Initialize: Entering";

    $hash->{SetFn}    = "RESIDENTS_Set";
    $hash->{DefFn}    = "RESIDENTS_Define";
    $hash->{NotifyFn} = "RESIDENTS_Notify";
    $hash->{UndefFn}  = "RESIDENTS_Undefine";
    $hash->{AttrList} =
      "rgr_showAllStates:0,1 rgr_states " . $readingFnAttributes;
}

###################################
sub RESIDENTS_Define($$) {
    my ( $hash, $def ) = @_;
    my $name = $hash->{NAME};
    my $name_attr;

    Log3 $name, 5, "RESIDENTS $name: called function RESIDENTS_Define()";

    $hash->{TYPE} = "RESIDENTS";

    # attr alias
    $name_attr = "alias";
    unless ( exists( $attr{$name}{$name_attr} ) ) {
        $attr{$name}{$name_attr} = "Residents";
    }

    # attr devStateIcon
    $name_attr = "devStateIcon";
    unless ( exists( $attr{$name}{$name_attr} ) ) {
        $attr{$name}{$name_attr} =
'.*home:status_available:absent .*absent:status_away_1:home .*gone:status_standby:home .*none:control_building_empty .*gotosleep:status_night:asleep .*asleep:status_night:awoken .*awoken:status_available:home';
    }

    # attr group
    $name_attr = "group";
    unless ( exists( $attr{$name}{$name_attr} ) ) {
        $attr{$name}{$name_attr} = "Home State";
    }

    # attr icon
    $name_attr = "icon";
    unless ( exists( $attr{$name}{$name_attr} ) ) {
        $attr{$name}{$name_attr} = "control_building_filled";
    }

    # attr room
    $name_attr = "room";
    unless ( exists( $attr{$name}{$name_attr} ) ) {
        $attr{$name}{$name_attr} = "Residents";
    }

    # attr webCmd
    $name_attr = "webCmd";
    unless ( exists( $attr{$name}{$name_attr} ) ) {
        $attr{$name}{$name_attr} = "state";
    }

    return undef;
}

###################################
sub RESIDENTS_Undefine($$) {
    my ( $hash, $name ) = @_;

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
    my $hashName_attr;

    # process child notifies
    if ( $devName ne $hashName ) {
        my @registeredRoommates =
          split( /,/, $hash->{ROOMMATES} )
          if ( defined( $hash->{ROOMMATES} )
            && $hash->{ROOMMATES} ne "" );

        my @registeredGuests =
          split( /,/, $hash->{GUESTS} )
          if ( defined( $hash->{GUESTS} )
            && $hash->{GUESTS} ne "" );

        # process only registered ROOMMATE or GUEST devices
        if (   ( @registeredRoommates && $devName ~~ @registeredRoommates )
            || ( @registeredGuests && $devName ~~ @registeredGuests ) )
        {

            return
              if ( !$dev->{CHANGED} ); # Some previous notify deleted the array.

            foreach my $change ( @{ $dev->{CHANGED} } ) {

                # state changed
                if ( $change !~ /:/ || $change =~ /wayhome:/ ) {
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
                    my $realnamesrc = (
                        defined( $attr{$devName}{rr_realname} )
                          && $attr{$devName}{rr_realname} ne ""
                        ? $attr{$devName}{rr_realname}
                        : "group"
                    );
                    my $realname = (
                        defined( $attr{$devName}{$realnamesrc} )
                          && $attr{$devName}{$realnamesrc} ne ""
                        ? $attr{$devName}{$realnamesrc}
                        : $devName
                    );

                    # update statistics
                    readingsBeginUpdate($hash);
                    readingsBulkUpdate( $hash, "lastActivity",   $change );
                    readingsBulkUpdate( $hash, "lastActivityBy", $realname );
                    readingsEndUpdate( $hash, 1 );
                }
            }
        }
    }

    return;
}

###################################
sub RESIDENTS_Set($@) {
    my ( $hash, @a ) = @_;
    my $name = $hash->{NAME};
    my $state =
      ( defined( $hash->{READINGS}{state}{VAL} ) )
      ? $hash->{READINGS}{state}{VAL}
      : "initialized";
    my $roommates = ( $hash->{ROOMMATES} ? $hash->{ROOMMATES} : "" );
    my $guests    = ( $hash->{GUESTS}    ? $hash->{GUESTS}    : "" );

    Log3 $name, 5, "RESIDENTS $name: called function RESIDENTS_Set()";

    return "No Argument given" if ( !defined( $a[1] ) );

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

    my $usage =
      "Unknown argument " . $a[1] . ", choose one of addRoommate addGuest";
    $usage .= " state:$states";
    $usage .= " removeRoommate:" . $roommates if ( $roommates ne "" );
    $usage .= " removeGuest:" . $guests if ( $guests ne "" );

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
                if ( defined( $defs{$roommate} )
                    && $defs{$roommate}{READINGS}{state} ne $newstate )
                {
                    fhem "set $roommate silentSet state $newstate";
                }
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
                if (   defined( $defs{$guest} )
                    && $defs{$guest}{READINGS}{state}{VAL} ne "none"
                    && $defs{$guest}{READINGS}{state}{VAL} ne $newstate )
                {
                    fhem "set $guest silentSet state $newstate";
                }
            }
        }
    }

    # addRoommate
    elsif ( $a[1] eq "addRoommate" ) {
        Log3 $name, 2, "RESIDENTS set $name " . $a[1] . " " . $a[2]
          if ( defined( $a[2] ) );

        my $rr_name;
        my $rr_name_attr;

        if ( $a[2] ne "" ) {
            $rr_name = "rr_" . $a[2];

            # define roommate
            if ( !defined( $defs{$rr_name} ) ) {
                fhem( "define " . $rr_name . " ROOMMATE " . $name );
                if ( defined( $defs{$rr_name} ) ) {
                    fhem "set $rr_name silentSet state home";
                    Log3 $name, 3,
                      "RESIDENTS $name: created new device $rr_name";
                }
            }
            else {
                return "Can't create, device $rr_name already existing.";
            }

        }
        else {
            return "No Argument given, choose one of name ";
        }
    }

    # removeRoommate
    elsif ( $a[1] eq "removeRoommate" ) {
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
    elsif ( $a[1] eq "addGuest" ) {
        Log3 $name, 2, "RESIDENTS set $name " . $a[1] . " " . $a[2]
          if ( defined( $a[2] ) );

        my $rg_name;
        my $rg_name_attr;

        if ( $a[2] ne "" ) {
            $rg_name = "rg_" . $a[2];

            # define guest
            if ( !defined( $defs{$rg_name} ) ) {
                fhem( "define " . $rg_name . " GUEST " . $name );
                if ( defined( $defs{$rg_name} ) ) {
                    fhem "set $rg_name silentSet state none";
                    Log3 $name, 3,
                      "RESIDENTS $name: created new device $rg_name";
                }
            }
            else {
                return "Can't create, device $rg_name already existing.";
            }

        }
        else {
            return "No Argument given, choose one of name ";
        }
    }

    # removeGuest
    elsif ( $a[1] eq "removeGuest" ) {
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

    # register
    elsif ( $a[1] eq "register" ) {
        if ( defined( $a[2] ) && $a[2] ne "" ) {
            return "No such device " . $a[2]
              if ( !defined( $defs{ $a[2] } ) );

            # ROOMMATE
            if ( $defs{ $a[2] }{TYPE} eq "ROOMMATE" ) {
                Log3 $name, 4, "RESIDENTS $name: " . $a[2] . " registered";

                # update readings
                $roommates .= ( $roommates eq "" ? $a[2] : "," . $a[2] )
                  if ( $roommates !~ /$a[2]/ );

                $hash->{ROOMMATES} = $roommates;
            }

            # GUEST
            elsif ( $defs{ $a[2] }{TYPE} eq "GUEST" ) {
                Log3 $name, 4, "RESIDENTS $name: " . $a[2] . " registered";

                # update readings
                $guests .= ( $guests eq "" ? $a[2] : "," . $a[2] )
                  if ( $guests !~ /$a[2]/ );

                $hash->{GUESTS} = $guests;
            }

            # unsupported
            else {
                return "Device type is not supported.";
            }

        }
        else {
            return "No Argument given, choose one of ROOMMATE GUEST ";
        }
    }

    # unregister
    elsif ( $a[1] eq "unregister" ) {
        if ( defined( $a[2] ) && $a[2] ne "" ) {
            return "No such device " . $a[2]
              if ( !defined( $defs{ $a[2] } ) );

            # ROOMMATE
            if ( $defs{ $a[2] }{TYPE} eq "ROOMMATE" ) {
                Log3 $name, 4, "RESIDENTS $name: " . $a[2] . " unregistered";

                # update readings
                my $replace = "," . $a[2];
                $roommates =~ s/$replace//g;
                $replace = $a[2] . ",";
                $roommates =~ s/^$replace//g;
                $roommates =~ s/^$a[2]//g;

                $hash->{ROOMMATES} = $roommates;
            }

            # GUEST
            elsif ( $defs{ $a[2] }{TYPE} eq "GUEST" ) {
                Log3 $name, 4, "RESIDENTS $name: " . $a[2] . " unregistered";

                # update readings
                my $replace = "," . $a[2];
                $guests =~ s/$replace//g;
                $replace = $a[2] . ",";
                $guests =~ s/^$replace//g;
                $guests =~ s/^$a[2]//g;

                $hash->{GUESTS} = $guests;
            }

            # unsupported
            else {
                return "Device type is not supported.";
            }

        }
        else {
            return "No Argument given, choose one of ROOMMATE GUEST ";
        }

        RESIDENTS_UpdateReadings($hash);
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
    my $state =
      ( defined $hash->{READINGS}{state}{VAL} ) ? $hash->{READINGS}{state}{VAL}
      : ( defined $hash->{STATE} )              ? $hash->{STATE}
      :                                           "undefined";
    my $name = $hash->{NAME};

    my $state_home         = 0;
    my $state_gotosleep    = 0;
    my $state_asleep       = 0;
    my $state_awoken       = 0;
    my $state_absent       = 0;
    my $state_gone         = 0;
    my $state_total        = 0;
    my $state_totalPresent = 0;
    my $state_totalAbsent  = 0;
    my $state_totalGuests  = 0;
    my $state_guestDev     = 0;
    my $wayhome            = 0;
    my $newstate;
    my $presence = "absent";

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

        if ( defined( $defs{$roommate}{READINGS}{state}{VAL} ) ) {
            if ( $defs{$roommate}{READINGS}{state}{VAL} eq "home" ) {
                $state_home++;
                $state_totalPresent++;
            }

            if ( $defs{$roommate}{READINGS}{state}{VAL} eq "gotosleep" ) {
                $state_gotosleep++;
                $state_totalPresent++;
            }

            if ( $defs{$roommate}{READINGS}{state}{VAL} eq "asleep" ) {
                $state_asleep++;
                $state_totalPresent++;
            }

            if ( $defs{$roommate}{READINGS}{state}{VAL} eq "awoken" ) {
                $state_awoken++;
                $state_totalPresent++;
            }

            if ( $defs{$roommate}{READINGS}{state}{VAL} eq "absent" ) {
                $state_absent++;
                $state_totalAbsent++;
            }

            if ( $defs{$roommate}{READINGS}{state}{VAL} eq "gone" ) {
                $state_gone++;
                $state_totalAbsent++;
            }
        }

        if ( defined( $defs{$roommate}{READINGS}{wayhome}{VAL} ) ) {
            $wayhome += $defs{$roommate}{READINGS}{wayhome}{VAL};
        }
    }

    # count child states for GUEST devices
    foreach my $guest (@registeredGuests) {
        $state_guestDev++;

        if ( defined( $defs{$guest}{READINGS}{state}{VAL} ) ) {
            if ( $defs{$guest}{READINGS}{state}{VAL} eq "home" ) {
                $state_home++;
                $state_totalPresent++;
                $state_totalGuests++;
                $state_total++;
            }

            if ( $defs{$guest}{READINGS}{state}{VAL} eq "gotosleep" ) {
                $state_gotosleep++;
                $state_totalPresent++;
                $state_totalGuests++;
                $state_total++;
            }

            if ( $defs{$guest}{READINGS}{state}{VAL} eq "asleep" ) {
                $state_asleep++;
                $state_totalPresent++;
                $state_totalGuests++;
                $state_total++;
            }

            if ( $defs{$guest}{READINGS}{state}{VAL} eq "awoken" ) {
                $state_awoken++;
                $state_totalPresent++;
                $state_totalGuests++;
                $state_total++;
            }

            if ( $defs{$guest}{READINGS}{state}{VAL} eq "absent" ) {
                $state_absent++;
                $state_totalAbsent++;
                $state_totalGuests++;
                $state_total++;
            }
        }

        if ( defined( $defs{$guest}{READINGS}{wayhome}{VAL} ) ) {
            $wayhome += $defs{$guest}{READINGS}{wayhome}{VAL};
        }
    }

    # update counter
    readingsBeginUpdate($hash);

    readingsBulkUpdate( $hash, "residentsTotal", $state_total )
      if ( !defined( $hash->{READINGS}{residentsTotal}{VAL} )
        || $hash->{READINGS}{residentsTotal}{VAL} ne $state_total );

    readingsBulkUpdate( $hash, "residentsGuests", $state_totalGuests )
      if ( !defined( $hash->{READINGS}{residentsGuests}{VAL} )
        || $hash->{READINGS}{residentsGuests}{VAL} ne $state_totalGuests );

    readingsBulkUpdate( $hash, "residentsTotalPresent", $state_totalPresent )
      if ( !defined( $hash->{READINGS}{residentsTotalPresent}{VAL} )
        || $hash->{READINGS}{residentsTotalPresent}{VAL} ne
        $state_totalPresent );

    readingsBulkUpdate( $hash, "residentsTotalAbsent", $state_totalAbsent )
      if ( !defined( $hash->{READINGS}{residentsTotalAbsent}{VAL} )
        || $hash->{READINGS}{residentsTotalAbsent}{VAL} ne $state_totalAbsent );

    readingsBulkUpdate( $hash, "residentsHome", $state_home )
      if ( !defined( $hash->{READINGS}{residentsHome}{VAL} )
        || $hash->{READINGS}{residentsHome}{VAL} ne $state_home );

    readingsBulkUpdate( $hash, "residentsGotosleep", $state_gotosleep )
      if ( !defined( $hash->{READINGS}{residentsGotosleep}{VAL} )
        || $hash->{READINGS}{residentsGotosleep}{VAL} ne $state_gotosleep );

    readingsBulkUpdate( $hash, "residentsAsleep", $state_asleep )
      if ( !defined( $hash->{READINGS}{residentsAsleep}{VAL} )
        || $hash->{READINGS}{residentsAsleep}{VAL} ne $state_asleep );

    readingsBulkUpdate( $hash, "residentsAwoken", $state_awoken )
      if ( !defined( $hash->{READINGS}{residentsAwoken}{VAL} )
        || $hash->{READINGS}{residentsAwoken}{VAL} ne $state_awoken );

    readingsBulkUpdate( $hash, "residentsAbsent", $state_absent )
      if ( !defined( $hash->{READINGS}{residentsAbsent}{VAL} )
        || $hash->{READINGS}{residentsAbsent}{VAL} ne $state_absent );

    readingsBulkUpdate( $hash, "residentsGone", $state_gone )
      if ( !defined( $hash->{READINGS}{residentsGone}{VAL} )
        || $hash->{READINGS}{residentsGone}{VAL} ne $state_gone );

    readingsBulkUpdate( $hash, "residentsTotalWayhome", $wayhome )
      if ( !defined( $hash->{READINGS}{residentsTotalWayhome}{VAL} )
        || $hash->{READINGS}{residentsTotalWayhome}{VAL} ne $wayhome );

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
    $presence = "present"
      if ( $newstate ne "gone"
        && $newstate ne "none"
        && $newstate ne "absent" );

    Log3 $name, 4,
"RESIDENTS $name: calculation result - residentsTotal:$state_total residentsGuests:$state_totalGuests residentsTotalPresent:$state_totalPresent residentsTotalAbsent:$state_totalAbsent residentsHome:$state_home residentsGotosleep:$state_gotosleep residentsAsleep:$state_asleep residentsAwoken:$state_awoken residentsAbsent:$state_absent residentsGone:$state_gone presence:$presence state:$newstate";

    # safe current time
    my $datetime = FmtDateTime(time);

    # if state changed
    if ( !defined( $hash->{READINGS}{state}{VAL} )
        || $state ne $newstate )
    {
        # if newstate is asleep, start sleep timer
        readingsBulkUpdate( $hash, "lastSleep", $datetime )
          if ( $newstate eq "asleep" );

        # if prior state was asleep, update sleep statistics
        if ( defined( $hash->{READINGS}{state}{VAL} )
            && $state eq "asleep" )
        {
            readingsBulkUpdate( $hash, "lastAwake", $datetime );
            readingsBulkUpdate(
                $hash,
                "lastDurSleep",
                RESIDENTS_TimeDiff(
                    $datetime, $hash->{READINGS}{lastSleep}{VAL}
                )
            );
        }

        readingsBulkUpdate( $hash, "lastState", $hash->{READINGS}{state}{VAL} );
        readingsBulkUpdate( $hash, "state",     $newstate );
    }

    # if presence changed
    if ( !defined( $hash->{READINGS}{presence}{VAL} )
        || $hash->{READINGS}{presence}{VAL} ne $presence )
    {
        readingsBulkUpdate( $hash, "presence", $presence );

        # update statistics
        if ( $presence eq "present" ) {
            readingsBulkUpdate( $hash, "lastArrival", $datetime );

            # absence duration
            if ( defined( $hash->{READINGS}{lastDeparture}{VAL} )
                && $hash->{READINGS}{lastDeparture}{VAL} ne "-" )
            {
                readingsBulkUpdate(
                    $hash,
                    "lastDurAbsence",
                    RESIDENTS_TimeDiff(
                        $datetime, $hash->{READINGS}{lastDeparture}{VAL}
                    )
                );
            }
        }
        else {
            readingsBulkUpdate( $hash, "lastDeparture", $datetime );

            # presence duration
            if ( defined( $hash->{READINGS}{lastArrival}{VAL} )
                && $hash->{READINGS}{lastArrival}{VAL} ne "-" )
            {
                readingsBulkUpdate(
                    $hash,
                    "lastDurPresence",
                    RESIDENTS_TimeDiff(
                        $datetime, $hash->{READINGS}{lastArrival}{VAL}
                    )
                );
            }
        }

    }
}

sub RESIDENTS_TimeDiff($$) {
    my ( $datetimeNow, $datetimeOld ) = @_;

    my (
        $date,         $time,         $date2,    $time2,
        $y,            $m,            $d,        $hour,
        $min,          $sec,          $y2,       $m2,
        $d2,           $hour2,        $min2,     $sec2,
        $timestampNow, $timestampOld, $timeDiff, $hours,
        $minutes,      $seconds
    );

    ( $date, $time ) = split( ' ', $datetimeNow );
    ( $y,    $m,   $d )   = split( '-', $date );
    ( $hour, $min, $sec ) = split( ':', $time );
    $m -= 01;
    $timestampNow = timelocal( $sec, $min, $hour, $d, $m, $y );

    ( $date2, $time2 ) = split( ' ', $datetimeOld );
    ( $y2,    $m2,   $d2 )   = split( '-', $date2 );
    ( $hour2, $min2, $sec2 ) = split( ':', $time2 );
    $m2 -= 01;
    $timestampOld = timelocal( $sec2, $min2, $hour2, $d2, $m2, $y2 );

    $timeDiff = $timestampNow - $timestampOld;
    $hours = ( $timeDiff < 3600 ? 0 : int( $timeDiff / 3600 ) );
    $timeDiff -= ( $hours == 0 ? 0 : ( $hours * 3600 ) );
    $minutes = ( $timeDiff < 60 ? 0 : int( $timeDiff / 60 ) );
    $seconds = $timeDiff % 60;

    $hours   = "0" . $hours   if ( $hours < 10 );
    $minutes = "0" . $minutes if ( $minutes < 10 );
    $seconds = "0" . $seconds if ( $seconds < 10 );

    return "$hours:$minutes:$seconds";
}

1;

=pod

=begin html

    <p>
      <a name="RESIDENTS" id="RESIDENTS"></a>
    </p>
    <h3>
      RESIDENTS
    </h3>
    <div style="margin-left: 2em">
      <a name="RESIDENTSdefine" id="RESIDENTSdefine"></a> <b>Define</b>
      <div style="margin-left: 2em">
        <code>define &lt;rgr_ResidentsName&gt; RESIDENTS</code><br>
        <br>
        Provides a special dummy device to represent a group of individuals living at your home.<br>
        It locically combines individual states of <a href="#ROOMMATE">ROOMMATE</a> and <a href="#GUEST">GUEST</a> devices and allows state changes for all members.<br>
        Based on the current state and other readings, you may trigger other actions within FHEM.<br>
        <br>
        Example:<br>
        <div style="margin-left: 2em">
          <code># Standalone<br>
          define rgr_Residents RESIDENTS</code>
        </div>
      </div><br>
      <br>
      <a name="RESIDENTSset" id="RESIDENTSset"></a> <b>Set</b>
      <div style="margin-left: 2em">
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
        </ul>
      </div><br>
      <br>
      <div style="margin-left: 2em">
        <u>Possible states and their meaning</u><br>
        <br>
        <div style="margin-left: 2em">
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
        </div>
      </div><br>
      <br>
      <a name="RESIDENTSattr" id="RESIDENTSattr"></a> <b>Attributes</b><br>
      <div style="margin-left: 2em">
        <ul>
          <li>
            <b>rgr_showAllStates</b> - states 'asleep' and 'awoken' are hidden by default to allow simple gotosleep process via devStateIcon; defaults to 0
          </li>
          <li>
            <b>rgr_states</b> - list of states to be shown in FHEMWEB; separate entries by comma only and do NOT use spaces; unsupported states will lead to errors though
          </li>
        </ul>
      </div><br>
      <br>
      <br>
      <b>Generated Readings/Events:</b><br>
      <div style="margin-left: 2em">
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
            <b>lastDurAbsence</b> - duration of last absence from home in following format: hours:minutes:seconds
          </li>
          <li>
            <b>lastDurPresence</b> - duration of last presence at home in following format: hours:minutes:seconds
          </li>
          <li>
            <b>lastDurSleep</b> - duration of last sleep in following format: hours:minutes:seconds
          </li>
          <li>
            <b>lastSleep</b> - timestamp of last sleep cycle begin
          </li>
          <li>
            <b>lastState</b> - the prior state
          </li>
          <li>
            <b>presence</b> - reflects the home presence state, depending on value of reading 'state' (can be 'present' or 'absent')
          </li>
          <li>
            <b>residentsAbsent</b> - number of residents with state 'absent'
          </li>
          <li>
            <b>residentsAsleep</b> - number of residents with state 'asleep'
          </li>
          <li>
            <b>residentsAwoken</b> - number of residents with state 'awoken'
          </li>
          <li>
            <b>residentsGone</b> - number of residents with state 'gone'
          </li>
          <li>
            <b>residentsGotosleep</b> - number of residents with state 'gotosleep'
          </li>
          <li>
            <b>residentsGuests</b> - number of active guests who are currently treated as part of the residents scope
          </li>
          <li>
            <b>residentsHome</b> - number of residents with state 'home'
          </li>
          <li>
            <b>residentsTotal</b> - total number of all active residents despite their current state
          </li>
          <li>
            <b>residentsTotalAbsent</b> - number of all residents who are currently underway
          </li>
          <li>
            <b>residentsTotalPresent</b> - number of all residents who are currently at home
          </li>
          <li>
            <b>residentsTotalWayhome</b> - number of all active residents who are currently on their way back home
          </li>
          <li>
            <b>state</b> - reflects the current state
          </li>
        </ul>
      </div>
    </div>

=end html

=begin html_DE

    <p>
      <a name="RESIDENTS" id="RESIDENTS"></a>
    </p>
    <h3>
      RESIDENTS
    </h3>
    <div style="margin-left: 2em">
      <a name="RESIDENTSdefine" id="RESIDENTSdefine"></a> <b>Define</b>
      <div style="margin-left: 2em">
        <code>define &lt;rgr_ResidentsName&gt; RESIDENTS</code><br>
        <br>
        Stellt ein spezielles Dummy-Device bereit, um eine Gruppe von Personen zu repräsentieren, die zusammen wohnen.<br>
        Es kombiniert dabei logisch die individuellen Stati von <a href="#ROOMMATE">ROOMMATE</a> und <a href="#GUEST">GUEST</a> Devices und erlaubt den Status für alle Mitglieder zeitgleich zu ändern. Basierend auf dem aktuelle Status und anderen Readings können andere Aktionen innerhalb von FHEM angestoßen werden.<br>
        <br>
        Beispiele:<br>
        <div style="margin-left: 2em">
          <code># Einzeln<br>
          define rgr_Residents RESIDENTS</code>
        </div>
      </div><br>
      <br>
      <a name="RESIDENTSset" id="RESIDENTSset"></a> <b>Set</b>
      <div style="margin-left: 2em">
        <code>set &lt;rgr_ResidentsName&gt; &lt;command&gt; [&lt;parameter&gt;]</code><br>
        <br>
        Momentan sind die folgenden Kommandos definiert.<br>
        <ul>
          <li>
            <b>addGuest</b> &nbsp;&nbsp;-&nbsp;&nbsp; erstellt ein neues GUEST Device und fügt es der aktuellen RESIDENTS Gruppe hinzu. Einfach den Platzhalternamen eingeben und das wars.
          </li>
          <li>
            <b>addRoommate</b> &nbsp;&nbsp;-&nbsp;&nbsp; erstellt ein neues GUEST Device und fügt es der aktuellen RESIDENTS Gruppe hinzu. Einfach den Vornamen eingeben und das wars.
          </li>
          <li>
            <b>removeGuest</b> &nbsp;&nbsp;-&nbsp;&nbsp; zeigt alle Mitglieder vom Typ GUEST an und ermöglicht ein einfaches löschen des dazugehörigen Dummy Devices.
          </li>
          <li>
            <b>removeRoommate</b> &nbsp;&nbsp;-&nbsp;&nbsp; zeigt alle Mitglieder vom Typ ROOMMATE an und ermöglicht ein einfaches löschen des dazugehörigen Dummy Devices.
          </li>
          <li>
            <b>state</b> &nbsp;&nbsp;home,gotosleep,asleep,awoken,absent,gone&nbsp;&nbsp; wechselt den Status für alle Gruppenmitglieder gleichzeitig; siehe Attribut rgr_states, um die angezeigte Liste in FHEMWEB abzuändern
          </li>
        </ul>
      </div><br>
      <br>
      <div style="margin-left: 2em">
        <u>Mögliche Stati und ihre Bedeutung</u><br>
        <br>
        <div style="margin-left: 2em">
          Dieses Modul unterscheidet 7 verschiedene Stati:<br>
          <br>
          <ul>
            <li>
              <b>home</b> - Bewohner sind zu Hause und mindestens einer schläft nicht
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
              <b>absent</b> - keiner der Bewohner ist momentan zu Hause; mindestens einer ist aber in Kürze zurück
            </li>
            <li>
              <b>gone</b> - alle Bewohner sind für längere Zeit verreist
            </li>
            <li>
              <b>none</b> - kein Mitglied aktiv
            </li>
          </ul><br>
          <br>
          Hinweis: Der Status 'none' kann nicht explizit gesetzt werden. Das setzen von 'gone' wird bei Mitgliedern vom Typ GUEST als 'none' behandelt.
        </div>
      </div><br>
      <br>
      <a name="RESIDENTSattr" id="RESIDENTSattr"></a> <b>Attribute</b><br>
      <div style="margin-left: 2em">
        <ul>
          <li>
            <b>rgr_showAllStates</b> - die Stati 'asleep' und 'awoken' sind normalerweise nicht immer sichtbar, um einen einfachen Zubettgeh-Prozess über das devStateIcon Attribut zu ermöglichen; Standard ist 0
          </li>
          <li>
            <b>rgr_states</b> - Liste aller in FHEMWEB angezeigter Stati; Eintrage nur mit Komma trennen und KEINE Leerzeichen benutzen; nicht unterstützte Stati führen zu Fehlern
          </li>
        </ul>
      </div><br>
      <br>
      <br>
      <b>Generierte Readings/Events:</b><br>
      <div style="margin-left: 2em">
        <ul>
          <li>
            <b>lastActivity</b> - der letzte Status Wechsel eines Gruppenmitglieds
          </li>
          <li>
            <b>lastActivityBy</b> - der Name des Gruppenmitglieds, dessen Status zuletzt geändert wurde
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
            <b>lastDurAbsence</b> - Dauer der letzten Abwesenheit im folgenden Format: Stunden:Minuten:Sekunden
          </li>
          <li>
            <b>lastDurPresence</b> - Dauer der letzten Anwesenheit im folgenden Format: Stunden:Minuten:Sekunden
          </li>
          <li>
            <b>lastDurSleep</b> - Dauer des letzten Schlafzyklus im folgenden Format: Stunden:Minuten:Sekunden
          </li>
          <li>
            <b>lastSleep</b> - Zeitstempel des Beginns des letzten Schlafzyklus
          </li>
          <li>
            <b>lastState</b> - der vorherige Status
          </li>
          <li>
            <b>presence</b> - gibt den Zuhause Status in Abhängigkeit des Readings 'state' wieder (kann 'present' oder 'absent' sein)
          </li>
          <li>
            <b>residentsAbsent</b> - Anzahl der Bewohner mit Status 'absent'
          </li>
          <li>
            <b>residentsAsleep</b> - Anzahl der Bewohner mit Status 'asleep'
          </li>
          <li>
            <b>residentsAwoken</b> - Anzahl der Bewohner mit Status 'awoken'
          </li>
          <li>
            <b>residentsGone</b> - Anzahl der Bewohner mit Status 'gone'
          </li>
          <li>
            <b>residentsGotosleep</b> - Anzahl der Bewohner mit Status 'gotosleep'
          </li>
          <li>
            <b>residentsGuests</b> - Anzahl der aktiven Gäste, welche momentan du den Bewohnern dazugezählt werden
          </li>
          <li>
            <b>residentsHome</b> - Anzahl der Bewohner mit Status 'home'
          </li>
          <li>
            <b>residentsTotal</b> - Summe aller aktiven Bewohner unabhängig von ihrem aktuellen Status
          </li>
          <li>
            <b>residentsTotalAbsent</b> - Summe aller aktiven Bewohner, die unterwegs sind
          </li>
          <li>
            <b>residentsTotalPresent</b> - Summe aller aktiven Bewohner, die momentan Zuhause sind
          </li>
          <li>
            <b>residentsTotalWayhome</b> - Summe aller aktiven Bewohner, die momentan auf dem Weg zurück nach Hause sind
          </li>
          <li>
            <b>state</b> - gibt den aktuellen Status wieder
          </li>
        </ul>
      </div>
    </div>

=end html_DE

=cut
