###############################################################################
# $Id$
package main;
use strict;
use warnings;
use Data::Dumper;
use Time::Local;

require RESIDENTStk;

# initialize ##################################################################
sub RESIDENTS_Initialize($) {
    my ($hash) = @_;

    $hash->{InitDevFn} = "RESIDENTStk_InitializeDev";
    $hash->{DefFn}     = "RESIDENTStk_Define";
    $hash->{UndefFn}   = "RESIDENTStk_Undefine";
    $hash->{SetFn}     = "RESIDENTStk_Set";
    $hash->{AttrFn}    = "RESIDENTStk_Attr";
    $hash->{NotifyFn}  = "RESIDENTStk_Notify";

    $hash->{AttrPrefix} = "rgr_";

    $hash->{AttrList} =
        "disable:1,0 disabledForIntervals do_not_notify:1,0 "
      . "rgr_states:multiple-strict,home,gotosleep,asleep,awoken,absent,gone rgr_lang:EN,DE rgr_noDuration:0,1 rgr_showAllStates:0,1 rgr_wakeupDevice "
      . $readingFnAttributes;
}

# module Fn ####################################################################
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
          AttrVal( $guest, AttrVal( $guest, "rg_realname", "group" ), "" );

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

                if ( IsDevice( $wakeupDevice, "dummy" ) ) {

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
                UConv::duration(
                    $datetime, ReadingsVal( $name, "lastSleep", "" )
                )
            );
            readingsBulkUpdate(
                $hash,
                "lastDurSleep_cr",
                UConv::duration(
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
                    UConv::duration(
                        $datetime, ReadingsVal( $name, "lastDeparture", "-" )
                    )
                );
                readingsBulkUpdate(
                    $hash,
                    "lastDurAbsence_cr",
                    UConv::duration(
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
                    UConv::duration(
                        $datetime, ReadingsVal( $name, "lastArrival", "-" )
                    )
                );
                readingsBulkUpdate(
                    $hash,
                    "lastDurPresence_cr",
                    UConv::duration(
                        $datetime, ReadingsVal( $name, "lastArrival", "-" ),
                        "min"
                    )
                );
            }
        }

    }

    # calculate duration timers
    RESIDENTStk_DurationTimer( $hash, 1 );
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
								<i>wakeupEnforced</i> - Enforce wake-up (optional; 0=no, 1=yes, 2=if wake-up time is not wakeupDefaultTime, 3=if wake-up time is earlier than wakeupDefaultTime)
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
								<i>wakeupEnforced</i> - Forciertes wecken (optional; 0=nein, 1=ja, 2=wenn Weckzeit ungleich wakeupDefaultTime, 3=wenn Weckzeit fr&uuml;her ist als wakeupDefaultTime)
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
